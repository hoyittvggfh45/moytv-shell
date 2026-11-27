/// WebFetchHost：WebFetchService 的真 WebView 执行端。
///
/// 提炼自海阔宿主的隐藏 WebView 取码（haikuo_runner_page 的
/// _fetchHtmlByWebView）：1×1 控件进树、checkJs 哨兵轮询等渲染/过盾、
/// 取 outerHTML、结束即卸载。区别是生命周期归全壳：挂在根控件树，
/// 懒挂载（无任务时槽位为空、零常驻），同一时刻只跑一个任务
/// （串行由 WebFetchService 保证）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'miniapp/haikuo/haikuo_helpers.dart';
import 'web_fetch_service.dart';

/// runJavaScriptReturningResult 的返回值清洗（与海阔 _sniffResultText
/// 同口径：去引号 JSON 串、null/undefined 归空）。
String webFetchResultText(Object? raw) {
  if (raw == null) return '';
  var text = '$raw'.trim();
  if (text.isEmpty || text == 'null' || text == 'undefined') return '';
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is String) text = decoded;
    } catch (_) {
      // 不是 JSON 串，原样用
    }
  }
  return text == 'null' || text == 'undefined' ? '' : text;
}

class WebFetchHost extends StatefulWidget {
  const WebFetchHost({super.key, required this.child, this.service});

  final Widget child;
  final WebFetchService? service;

  @override
  State<WebFetchHost> createState() => _WebFetchHostState();
}

class _WebFetchHostState extends State<WebFetchHost> {
  WebViewController? _controller;
  WebFetchService get _service => widget.service ?? WebFetchService.instance;

  @override
  void initState() {
    super.initState();
    _service.runner = _run;
  }

  @override
  void dispose() {
    if (_service.runner == _run) _service.runner = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_controller != null)
          Positioned(
            left: 0,
            top: 0,
            width: 1,
            height: 1,
            child: WebViewWidget(controller: _controller!),
          ),
      ],
    );
  }

  Future<String> _pageCookiesFor(String url) async {
    try {
      final cookies = await WebViewCookieManager().getCookies(
        domain: Uri.parse(url),
      );
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _seedCookies(String url, String seedCookie) async {
    if (seedCookie.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return;
    final manager = WebViewCookieManager();
    for (final part in seedCookie.split(';')) {
      final pair = part.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      try {
        await manager.setCookie(
          WebViewCookie(
            name: pair.substring(0, eq).trim(),
            value: pair.substring(eq + 1).trim(),
            domain: uri.host,
            path: '/',
          ),
        );
      } catch (_) {
        // 单个 cookie 垫入失败不拦取数
      }
    }
  }

  Future<WebFetchRawResult> _run(
    WebFetchRequest request, {
    String seedCookie = '',
    String seedUserAgent = '',
  }) async {
    if (!mounted) {
      return const WebFetchRawResult(html: '', error: 'host_unavailable');
    }
    final timeout = Duration(milliseconds: request.timeoutMs);
    final splitUa = haikuoSplitUserAgent(request.headers);
    // 票面 UA 优先（票与 UA 同存同用），源自带 UA 次之。
    final pageUa = seedUserAgent.isNotEmpty ? seedUserAgent : splitUa.userAgent;
    final loaded = Completer<void>();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF120B20))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (navRequest) {
            final blocked = request.blockRules.any(
              (rule) => wildcardContains(navRequest.url, rule),
            );
            return blocked
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
          onPageFinished: (_) {
            if (!loaded.isCompleted) loaded.complete();
          },
        ),
      );
    if (!mounted) {
      return const WebFetchRawResult(html: '', error: 'host_unavailable');
    }
    setState(() => _controller = controller);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (pageUa.isNotEmpty) {
        await controller.setUserAgent(pageUa);
      }
      await _seedCookies(request.url, seedCookie);
      await controller.loadRequest(
        Uri.parse(request.url),
        headers: splitUa.headers,
      );
      final deadline = DateTime.now().add(timeout);
      var passed = request.checkJs.isEmpty;
      while (DateTime.now().isBefore(deadline)) {
        if (request.checkJs.isNotEmpty) {
          try {
            final pad = haikuoBridgePadScript(
              await _pageCookiesFor(request.url),
            );
            final script =
                '(function(){try{$pad}catch(e){}'
                'try{var __r=(0,eval)(${jsonEncode(request.checkJs)});'
                'return (__r===null||__r===undefined||__r===false||__r==="")'
                '?"":${jsonEncode(haikuoCheckJsPassSentinel)};}catch(e){return "";}})()';
            final raw = await controller.runJavaScriptReturningResult(script);
            if (webFetchResultText(raw) == haikuoCheckJsPassSentinel) {
              passed = true;
              break;
            }
          } catch (_) {
            // 页面还没好，这一拍跳过
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
        } else {
          await loaded.future.timeout(
            deadline.difference(DateTime.now()),
            onTimeout: () {},
          );
          // 加载完成后再宽限一会，让动态内容渲染出来。
          await Future<void>.delayed(const Duration(milliseconds: 800));
          passed = true;
          break;
        }
      }
      if (!passed) {
        return WebFetchRawResult(
          html: '',
          error: request.checkJs.isEmpty ? 'timeout' : 'need_manual',
          cookies: await _pageCookiesFor(request.url),
        );
      }
      var evalResult = '';
      if (request.evalJs.isNotEmpty) {
        try {
          final raw = await controller.runJavaScriptReturningResult(
            request.evalJs,
          );
          evalResult = webFetchResultText(raw);
        } catch (_) {
          evalResult = '';
        }
      }
      final raw = await controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML',
      );
      var userAgent = pageUa;
      try {
        userAgent = webFetchResultText(
          await controller.runJavaScriptReturningResult('navigator.userAgent'),
        );
        if (userAgent.isEmpty) userAgent = pageUa;
      } catch (_) {
        userAgent = pageUa;
      }
      return WebFetchRawResult(
        html: webFetchResultText(raw),
        userAgent: userAgent,
        cookies: await _pageCookiesFor(request.url),
        evalResult: evalResult,
      );
    } catch (_) {
      return WebFetchRawResult(
        html: '',
        error: 'load_failed',
        cookies: await _pageCookiesFor(request.url),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (identical(_controller, controller)) _controller = null;
        });
      }
    }
  }
}
