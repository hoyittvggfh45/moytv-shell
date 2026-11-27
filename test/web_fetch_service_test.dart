import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/web_fetch_service.dart';

WebFetchService makeService({
  WebFetchRunner? runner,
  List<String>? sinkLog,
  Map<String, ({String cookie, String ua})>? tickets,
  DateTime Function()? now,
  Future<void> Function(Duration)? delay,
  Duration minHostInterval = Duration.zero,
  int fuseThreshold = 3,
  Duration fuseCooldown = const Duration(seconds: 60),
}) {
  return WebFetchService(
    runner: runner,
    ticketPad: (host) async => tickets?[host],
    ticketSink: (host, cookie, ua) async {
      sinkLog?.add('$host|$cookie|$ua');
    },
    now: now,
    delay: delay,
    minHostInterval: minHostInterval,
    fuseThreshold: fuseThreshold,
    fuseCooldown: fuseCooldown,
  );
}

void main() {
  group('webFetchRequestOf 标记解析', () {
    test('完整标记', () {
      final req = webFetchRequestOf({
        'webFetch': {
          'url': 'https://example.com/page',
          'headers': {'Referer': 'https://example.com/'},
          'checkJs': 'document.title',
          'timeoutMs': 45000,
          'blockRules': ['*.ads.com'],
          'ctx': {'op': 'home'},
        },
        'list': [],
      });
      expect(req, isNotNull);
      expect(req!.url, 'https://example.com/page');
      expect(req.headers['Referer'], 'https://example.com/');
      expect(req.checkJs, 'document.title');
      expect(req.timeoutMs, 45000);
      expect(req.blockRules, ['*.ads.com']);
      expect(req.ctx['op'], 'home');
    });

    test('无标记/坏标记回 null', () {
      expect(webFetchRequestOf({'list': []}), isNull);
      expect(webFetchRequestOf({'webFetch': 'x'}), isNull);
      expect(webFetchRequestOf({'webFetch': {}}), isNull);
      expect(webFetchRequestOf({'webFetch': {'url': '  '}}), isNull);
    });
  });

  group('WebFetchService', () {
    test('无 runner 回 host_unavailable', () async {
      final svc = makeService();
      final r = await svc.fetchHtml(
        const WebFetchRequest(url: 'https://example.com/'),
      );
      expect(r.ok, isFalse);
      expect(r.error, 'host_unavailable');
    });

    test('坏地址回 bad_url 且不进队列计数外泄', () async {
      final svc = makeService(
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async =>
            const WebFetchRawResult(html: '<html/>'),
      );
      final r = await svc.fetchHtml(
        const WebFetchRequest(url: 'ftp://example.com/'),
      );
      expect(r.error, 'bad_url');
      expect(svc.pendingCount, 0);
    });

    test('串行队列：后到任务等先完成', () async {
      final order = <String>[];
      final gate = Completer<void>();
      final svc = makeService(
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async {
          order.add('start:${req.url}');
          if (req.url.endsWith('/a')) await gate.future;
          order.add('end:${req.url}');
          return WebFetchRawResult(html: '<html>${req.url}</html>');
        },
      );
      final fa = svc.fetchHtml(
        const WebFetchRequest(url: 'https://a.example.com/a'),
      );
      final fb = svc.fetchHtml(
        const WebFetchRequest(url: 'https://b.example.com/b'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(order, ['start:https://a.example.com/a']);
      gate.complete();
      await Future.wait([fa, fb]);
      expect(order, [
        'start:https://a.example.com/a',
        'end:https://a.example.com/a',
        'start:https://b.example.com/b',
        'end:https://b.example.com/b',
      ]);
      expect(svc.pendingCount, 0);
    });

    test('票据双向同步：垫票进 runner、回灌 sink', () async {
      String? seenSeedCookie;
      String? seenSeedUa;
      final sinkLog = <String>[];
      final svc = makeService(
        tickets: {
          'example.com': (cookie: 'cf_clearance=tok', ua: 'UA-TICKET'),
        },
        sinkLog: sinkLog,
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async {
          seenSeedCookie = seedCookie;
          seenSeedUa = seedUserAgent;
          return const WebFetchRawResult(
            html: '<html>ok</html>',
            userAgent: 'UA-TICKET',
            cookies: 'cf_clearance=newtok; session=1',
          );
        },
      );
      final r = await svc.fetchHtml(
        const WebFetchRequest(url: 'https://example.com/'),
      );
      expect(r.ok, isTrue);
      expect(seenSeedCookie, 'cf_clearance=tok');
      expect(seenSeedUa, 'UA-TICKET');
      expect(sinkLog, [
        'example.com|cf_clearance=newtok; session=1|UA-TICKET',
      ]);
    });

    test('HTML 超上限截断并标 truncated', () async {
      final big = 'x' * (WebFetchService.maxHtmlBytes + 10);
      final svc = makeService(
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async =>
            WebFetchRawResult(html: big),
      );
      final r = await svc.fetchHtml(
        const WebFetchRequest(url: 'https://example.com/'),
      );
      expect(r.ok, isTrue);
      expect(r.truncated, isTrue);
      expect(r.html.length, WebFetchService.maxHtmlBytes);
    });

    test('连续失败熔断：达阈值后直接回 fused 不调 runner', () async {
      var calls = 0;
      final svc = makeService(
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async {
          calls++;
          return const WebFetchRawResult(html: '', error: 'need_manual');
        },
      );
      const req = WebFetchRequest(url: 'https://bad.example.com/');
      for (var i = 0; i < 3; i++) {
        final r = await svc.fetchHtml(req);
        expect(r.error, 'need_manual');
      }
      final fused = await svc.fetchHtml(req);
      expect(fused.error, 'fused');
      expect(calls, 3);
    });

    test('同主机最小间隔：假时钟下第二次要等', () async {
      var nowValue = DateTime(2026, 1, 1, 12);
      final delays = <Duration>[];
      final svc = makeService(
        now: () => nowValue,
        delay: (d) async {
          delays.add(d);
          nowValue = nowValue.add(d);
        },
        minHostInterval: const Duration(seconds: 2),
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async =>
            const WebFetchRawResult(html: '<html/>'),
      );
      const req = WebFetchRequest(url: 'https://example.com/');
      await svc.fetchHtml(req);
      await svc.fetchHtml(req);
      expect(delays, [const Duration(seconds: 2)]);
    });

    test('timeoutMs 被钳到 1–120 秒', () async {
      int? seenTimeout;
      final svc = makeService(
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async {
          seenTimeout = req.timeoutMs;
          return const WebFetchRawResult(html: '<html/>');
        },
      );
      await svc.fetchHtml(
        const WebFetchRequest(url: 'https://example.com/', timeoutMs: 999999),
      );
      expect(seenTimeout, WebFetchService.maxTimeoutMs);
    });
  });

  group('runWithWebFetch 两段编排', () {
    test('无标记原样透传，resume 不被调用', () async {
      var resumeCalls = 0;
      final out = await runWithWebFetch({'list': [1, 2]}, (resume) async {
        resumeCalls++;
        return {};
      }, service: makeService());
      expect(out, {'list': [1, 2]});
      expect(resumeCalls, 0);
    });

    test('一轮：取数后 resume 收到 html 与 ctx', () async {
      Map<String, dynamic>? seenResume;
      final svc = makeService(
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async =>
            const WebFetchRawResult(html: '<html>real</html>'),
      );
      final out = await runWithWebFetch({
        'webFetch': {
          'url': 'https://example.com/',
          'ctx': {'op': 'home'},
        },
        'list': [],
      }, (resume) async {
        seenResume = resume;
        return {'list': ['done']};
      }, service: svc);
      expect(seenResume?['html'], '<html>real</html>');
      expect(seenResume?['ok'], isTrue);
      expect((seenResume?['ctx'] as Map)['op'], 'home');
      expect(out, {'list': ['done']});
    });

    test('两轮后仍带标记：剥标记并写 webfetch_loop', () async {
      final svc = makeService(
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async =>
            const WebFetchRawResult(html: '<html/>'),
      );
      var resumes = 0;
      final out = await runWithWebFetch({
        'webFetch': {'url': 'https://example.com/'},
      }, (resume) async {
        resumes++;
        return {
          'webFetch': {'url': 'https://example.com/'},
          'list': [],
        };
      }, service: svc);
      expect(resumes, WebFetchService.maxRounds);
      expect(out.containsKey('webFetch'), isFalse);
      expect(out['webFetchError'], 'webfetch_loop');
    });

    test('取数失败也续接：resume 收到 ok=false 与失败码', () async {
      Map<String, dynamic>? seenResume;
      final svc = makeService(
        runner: (req, {seedCookie = '', seedUserAgent = ''}) async =>
            const WebFetchRawResult(html: '', error: 'need_manual'),
      );
      await runWithWebFetch({
        'webFetch': {'url': 'https://example.com/'},
      }, (resume) async {
        seenResume = resume;
        return {'list': []};
      }, service: svc);
      expect(seenResume?['ok'], isFalse);
      expect(seenResume?['error'], 'need_manual');
    });
  });
}
