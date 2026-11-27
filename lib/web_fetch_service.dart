/// 全壳共用「隐藏浏览器取数」服务（WebFetchService）。
///
/// 设计见 ~/workspace/moyi_webview_host_20261127/DESIGN.md 第 3 节：
/// 海阔宿主里现成的隐藏 WebView 取码提炼为全壳服务，py/JS 源用声明式
/// 两段调用（结果里带 webFetch 标记 → 壳侧取渲染后 HTML → 续接回源）。
/// 本文件只管协议、队列与票据同步；真正的 WebView 执行在
/// web_fetch_host.dart（根控件懒挂载、用完即卸），经 [runner] 接缝注入，
/// 测试可换假 runner。
///
/// 红线：本服务只给我方自己写的源当取数通道；浏览器取回的内容只在
/// 直取真失败时用，不顶替直取的真实响应。
library;

import 'dart:async';

import 'nexhub_scraper/scraper/cookie_store.dart';

/// 一次 webFetch 声明（源在结果里给的标记内容）。
class WebFetchRequest {
  const WebFetchRequest({
    required this.url,
    this.headers = const {},
    this.checkJs = '',
    this.evalJs = '',
    this.timeoutMs = WebFetchService.defaultTimeoutMs,
    this.blockRules = const [],
    this.ctx = const {},
  });

  final String url;
  final Map<String, String> headers;

  /// 渲染就绪判定脚本：页面里求值，非空/非 false 即通过（哨兵口径与
  /// 海阔 checkJs 一致）。为空时只等加载完成＋宽限。
  final String checkJs;

  /// 通过后额外在页面里执行并回字符串结果的脚本（可选）。
  final String evalJs;

  final int timeoutMs;
  final List<String> blockRules;

  /// 源自带的透传上下文，续接时原样回给源。
  final Map<String, dynamic> ctx;

  String get host => Uri.tryParse(url)?.host ?? '';
}

/// runner 的原始产出（host 控件回给服务层）。
class WebFetchRawResult {
  const WebFetchRawResult({
    required this.html,
    this.userAgent = '',
    this.cookies = '',
    this.evalResult = '',
    this.error,
  });

  final String html;
  final String userAgent;

  /// 取数后该主机的 Cookie 串（`k=v; ...`），服务层据此回灌票据池。
  final String cookies;
  final String evalResult;

  /// 失败码：need_manual / timeout / host_unavailable / load_failed 等。
  final String? error;
}

/// 最终结果（服务层加工后回给调用方/续接）。
class WebFetchResult {
  const WebFetchResult({
    required this.ok,
    required this.html,
    required this.url,
    this.userAgent = '',
    this.evalResult = '',
    this.error,
    this.truncated = false,
  });

  final bool ok;
  final String html;
  final String url;
  final String userAgent;
  final String evalResult;
  final String? error;
  final bool truncated;
}

/// 真 WebView 执行接缝：生产由 WebFetchHost 注册，测试注入假实现。
typedef WebFetchRunner =
    Future<WebFetchRawResult> Function(
      WebFetchRequest request, {
      String seedCookie,
      String seedUserAgent,
    });

/// 票据读口：按主机取已存票（cookie+UA），没有回 null。
typedef WebFetchTicketPad =
    Future<({String cookie, String ua})?> Function(String host);

/// 票据写口：取数后把该主机最新 cookie+UA 回灌票据池。
typedef WebFetchTicketSink =
    Future<void> Function(String host, String cookie, String ua);

class WebFetchService {
  WebFetchService({
    this.runner,
    WebFetchTicketPad? ticketPad,
    WebFetchTicketSink? ticketSink,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    this.minHostInterval = const Duration(milliseconds: 500),
    this.fuseThreshold = 3,
    this.fuseCooldown = const Duration(seconds: 60),
  }) : _ticketPad = ticketPad ?? _defaultTicketPad,
       _ticketSink = ticketSink ?? _defaultTicketSink,
       _now = now ?? DateTime.now,
       _delay = delay ?? ((d) => Future<void>.delayed(d));

  static const int defaultTimeoutMs = 30000;
  static const int minTimeoutMs = 1000;
  static const int maxTimeoutMs = 120000;

  /// HTML 回传上限（设计 §4.2：2–4MB，取 3MB），超限截断并标 truncated。
  static const int maxHtmlBytes = 3 << 20;

  /// 单次源调用内最多几轮 webFetch（防环）。
  static const int maxRounds = 2;

  static final WebFetchService instance = WebFetchService();

  /// 真 WebView 执行体：生产由 WebFetchHost 在挂载时注册、卸载时
  /// 注销；测试注入假实现。为空时 fetchHtml 回 host_unavailable。
  WebFetchRunner? runner;

  final WebFetchTicketPad _ticketPad;
  final WebFetchTicketSink _ticketSink;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  /// 同主机两次开浏览器的最小间隔（防源写错造成开页循环）。
  final Duration minHostInterval;

  /// 同主机连续失败几次后熔断。
  final int fuseThreshold;

  /// 熔断冷却时长。
  final Duration fuseCooldown;

  Future<void> _tail = Future<void>.value();
  final Map<String, DateTime> _lastRunAt = {};
  final Map<String, int> _failStreak = {};
  final Map<String, DateTime> _fusedUntil = {};

  /// 当前排队/执行中的任务数（验收「任务完队列空」用）。
  int pendingCount = 0;

  bool get hasRunner => runner != null;

  static Future<({String cookie, String ua})?> _defaultTicketPad(
    String host,
  ) async {
    final rec = await CookieStore.get(host);
    if (rec == null) return null;
    final cookie = rec['cookie'] ?? '';
    if (cookie.isEmpty) return null;
    return (cookie: cookie, ua: rec['ua'] ?? '');
  }

  static Future<void> _defaultTicketSink(
    String host,
    String cookie,
    String ua,
  ) async {
    if (host.isEmpty || cookie.isEmpty) return;
    await CookieStore.save(host, cookie, ua);
  }

  /// 声明式取数入口：串行排队执行（全壳同时最多一个取数 WebView）。
  Future<WebFetchResult> fetchHtml(WebFetchRequest request) {
    pendingCount++;
    final run = _tail.then((_) => _runGuarded(request));
    // 队列尾巴吞掉单个任务的异常，保证后续任务不被毒死。
    _tail = run.then((_) {}, onError: (_) {});
    return run.whenComplete(() => pendingCount--);
  }

  Future<WebFetchResult> _runGuarded(WebFetchRequest request) async {
    final url = request.url.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return WebFetchResult(ok: false, html: '', url: url, error: 'bad_url');
    }
    final host = request.host;
    final fused = _fusedUntil[host];
    if (fused != null && _now().isBefore(fused)) {
      return WebFetchResult(ok: false, html: '', url: url, error: 'fused');
    }
    final last = _lastRunAt[host];
    if (last != null) {
      final wait = minHostInterval - _now().difference(last);
      if (wait > Duration.zero) await _delay(wait);
    }
    final activeRunner = runner;
    if (activeRunner == null) {
      return WebFetchResult(
        ok: false,
        html: '',
        url: url,
        error: 'host_unavailable',
      );
    }
    // 取数前垫票：票面 UA 优先（票与 UA 同存同用），源自带 UA 次之。
    var seedCookie = '';
    var seedUa = '';
    try {
      final pad = await _ticketPad(host);
      if (pad != null) {
        seedCookie = pad.cookie;
        seedUa = pad.ua;
      }
    } catch (_) {
      // 票据读失败不拦取数，走无票路。
    }
    _lastRunAt[host] = _now();
    WebFetchRawResult raw;
    try {
      raw = await activeRunner(
        WebFetchRequest(
          url: url,
          headers: request.headers,
          checkJs: request.checkJs,
          evalJs: request.evalJs,
          timeoutMs: request.timeoutMs.clamp(minTimeoutMs, maxTimeoutMs),
          blockRules: request.blockRules,
          ctx: request.ctx,
        ),
        seedCookie: seedCookie,
        seedUserAgent: seedUa,
      );
    } catch (_) {
      raw = const WebFetchRawResult(html: '', error: 'load_failed');
    }
    // 取数后回灌票据：页面域解一次盾，同主机后续通道全受益。
    if (raw.cookies.isNotEmpty) {
      try {
        await _ticketSink(
          host,
          raw.cookies,
          raw.userAgent.isNotEmpty ? raw.userAgent : seedUa,
        );
      } catch (_) {
        // 回灌失败不改取数成败。
      }
    }
    var html = raw.html;
    var truncated = false;
    if (html.length > maxHtmlBytes) {
      html = html.substring(0, maxHtmlBytes);
      truncated = true;
    }
    final ok = raw.error == null && html.isNotEmpty;
    if (ok) {
      _failStreak.remove(host);
      _fusedUntil.remove(host);
    } else {
      final streak = (_failStreak[host] ?? 0) + 1;
      _failStreak[host] = streak;
      if (streak >= fuseThreshold) {
        _fusedUntil[host] = _now().add(fuseCooldown);
      }
    }
    return WebFetchResult(
      ok: ok,
      html: html,
      url: url,
      userAgent: raw.userAgent,
      evalResult: raw.evalResult,
      error: raw.error ?? (html.isEmpty ? 'empty' : null),
      truncated: truncated,
    );
  }
}

/// 结果 Map 里的 webFetch 标记解析。不是标记回 null。
WebFetchRequest? webFetchRequestOf(Map<dynamic, dynamic> result) {
  final raw = result['webFetch'];
  if (raw is! Map) return null;
  final url = '${raw['url'] ?? ''}'.trim();
  if (url.isEmpty) return null;
  final headers = <String, String>{};
  final rawHeaders = raw['headers'];
  if (rawHeaders is Map) {
    rawHeaders.forEach((key, value) {
      headers['$key'] = '$value';
    });
  }
  final blockRules = switch (raw['blockRules']) {
    final List list => <String>[for (final e in list) '$e'],
    _ => const <String>[],
  };
  final ctx = switch (raw['ctx']) {
    final Map map => Map<String, dynamic>.from(map),
    _ => const <String, dynamic>{},
  };
  return WebFetchRequest(
    url: url,
    headers: headers,
    checkJs: '${raw['checkJs'] ?? ''}',
    evalJs: '${raw['evalJs'] ?? ''}',
    timeoutMs:
        (raw['timeoutMs'] as num?)?.toInt() ?? WebFetchService.defaultTimeoutMs,
    blockRules: blockRules,
    ctx: ctx,
  );
}

/// 声明式两段编排：结果带标记 → 取数 → 续接 → （可再一轮）→ 最终结果。
/// [resume] 收到 {html, url, ctx, ok, error, evalResult, truncated}，
/// 回源续接方法的结果。超过 [WebFetchService.maxRounds] 轮仍带标记，
/// 剥掉标记并写 webFetchError=webfetch_loop，不无限循环。
Future<Map<String, dynamic>> runWithWebFetch(
  Map<String, dynamic> first,
  Future<Map<String, dynamic>> Function(Map<String, dynamic> resume) resume, {
  WebFetchService? service,
}) async {
  final svc = service ?? WebFetchService.instance;
  var current = first;
  for (var round = 0; round < WebFetchService.maxRounds; round++) {
    final request = webFetchRequestOf(current);
    if (request == null) return current;
    final fetched = await svc.fetchHtml(request);
    current = await resume({
      'html': fetched.html,
      'url': request.url,
      'ctx': request.ctx,
      'ok': fetched.ok,
      'error': fetched.error ?? '',
      'evalResult': fetched.evalResult,
      'truncated': fetched.truncated,
    });
  }
  if (webFetchRequestOf(current) != null) {
    current = Map<String, dynamic>.from(current)
      ..remove('webFetch')
      ..['webFetchError'] = 'webfetch_loop';
  }
  return current;
}
