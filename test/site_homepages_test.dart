import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/builtin_legado_sources.dart';
import 'package:moyi/builtin_py_sites.dart';
import 'package:moyi/content_legado.dart';
import 'package:moyi/site_homepages.dart';
import 'package:moyi/site_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String originOf(String url) {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  test('py 映射：值确是 origin、主机名确在对应蜘蛛文件里', () {
    // 2026-11-26 空壳片库定版：片库内置 py 注册表已清空，本表只剩
    // 听读阅读蜘蛛的 23 条桥接。每条的键必须是真实存在的阅读蜘蛛、
    // 值是 origin、主机名确在蜘蛛文件里。
    expect(BuiltinPySites.entries, isEmpty);
    final novelIds = <String>{
      for (final file in Directory('assets/novel_spiders').listSync())
        if (file.path.endsWith('.py'))
          file.path.split('/').last.replaceAll('.py', ''),
    };
    for (final entry in pySiteHomepages.entries) {
      expect(
        novelIds,
        contains(entry.key),
        reason: '${entry.key} 不是阅读蜘蛛（片库桥接应已剥离）',
      );
      expect(entry.value, originOf(entry.value), reason: '${entry.value} 不是 origin');
      final text =
          File('assets/novel_spiders/${entry.key}.py').readAsStringSync();
      expect(
        text,
        contains(Uri.parse(entry.value).host),
        reason: '${entry.key} 的主机 ${Uri.parse(entry.value).host} 不在蜘蛛文件里',
      );
    }
    expect(pySiteHomepages.length, 23);
  });

  test('Go 映射：值确是 origin、主机名确在 Go 核源码里', () {
    // 2026-11-26 空壳片库定版：Go 核槽位站的主页桥接已随片库剥离
    // 全部删除，本表为空（Go 核文件本身不在本次剥离范围）。
    expect(goSiteHomepages, isEmpty);
  });

  test('阅读 JSON 映射：值确与源文件 bookSourceUrl 同 origin', () {
    for (final source in builtinLegadoSources) {
      final jsonSource = source as JsonContentSource;
      final data =
          jsonDecode(File(jsonSource.assetPath).readAsStringSync())
              as Map<String, dynamic>;
      final bookUrl = data['bookSourceUrl'] as String;
      final mapped = legadoSiteHomepages[source.id];
      if (!bookUrl.startsWith('http')) {
        // 自定义协议源（如 moyue://）永远取不到站标，不许进表。
        expect(mapped, isNull, reason: '${source.id} 的 $bookUrl 不应进映射表');
        continue;
      }
      expect(mapped, isNotNull, reason: '${source.id} 无主页映射');
      expect(mapped, originOf(bookUrl), reason: '${source.id} 映射值与源文件不一致');
    }
    expect(legadoSiteHomepages.length, 93);
  });

  test('桥接查表：三种 id 形态都解析，查不到回空', () {
    // 2026-11-26 空壳片库定版：片库站（hmav/v_javdb/chaoliu）的
    // 桥接已删、查表回空；听读桥接保留——akmh（阅读 py）与
    // legado_8059_0（阅读 JSON）仍可解析，jar 形态取 key 段。
    final akmh = siteHomepageCandidates('akmh');
    expect(akmh, isNotEmpty);
    expect(akmh.first, startsWith('https://www.eemh.cc'));
    expect(siteHomepageCandidates('jar:zakatv:akmh'), akmh);
    expect(siteHomepageCandidates('legado_8059_0'), isNotEmpty);
    expect(siteHomepageCandidates('hmav'), isEmpty);
    expect(siteHomepageCandidates('v_javdb'), isEmpty);
    expect(siteHomepageCandidates('chaoliu'), isEmpty);
    expect(siteHomepageCandidates('no-such-site'), isEmpty);
    expect(siteHomepageCandidates(''), isEmpty);
  });

  testWidgets('桥接站标：不传 iconUrls 也按主页取图标', (tester) async {
    const png = <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ];
    final requested = <String>[];
    final temp = Directory.systemTemp.createTempSync('site_homepages_test');
    addTearDown(() => temp.deleteSync(recursive: true));
    final cache = SiteIconCache(
      directoryProvider: () async => temp,
      fetcher: (url) async {
        requested.add(url);
        return png;
      },
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SiteIcon(
              siteId: 'legado_8059_0',
              siteName: '九七八小说',
              cache: cache,
            ),
          ),
        ),
      );
      for (var i = 0; i < 50 && temp.listSync().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    });
    expect(requested, isNotEmpty);
    expect(requested.first, startsWith('https://www.978xs.com'));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('九'), findsNothing);
  });

  testWidgets('桥接站标取不到时回落图案标', (tester) async {
    final temp = Directory.systemTemp.createTempSync('site_homepages_test');
    addTearDown(() => temp.deleteSync(recursive: true));
    final cache = SiteIconCache(
      directoryProvider: () async => temp,
      fetcher: (_) async => null,
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SiteIcon(siteId: 'hmav', siteName: '🔞河马AV', cache: cache),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    });
    expect(find.byType(Icon), findsOneWidget);
    expect(find.text('河'), findsNothing);
  });

  test('站标缓存：第二次解析不重复下载', () async {
    final temp = Directory.systemTemp.createTempSync('site_homepages_test');
    addTearDown(() => temp.deleteSync(recursive: true));
    var fetches = 0;
    final cache = SiteIconCache(
      directoryProvider: () async => temp,
      fetcher: (_) async {
        fetches++;
        return const <int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          0x00,
          0x00,
          0x00,
          0x0D,
          0x49,
          0x48,
          0x44,
          0x52,
          0x00,
          0x00,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x01,
          0x08,
          0x06,
          0x00,
          0x00,
          0x00,
          0x1F,
          0x15,
          0xC4,
          0x89,
          0x00,
          0x00,
          0x00,
          0x0A,
          0x49,
          0x44,
          0x41,
          0x54,
          0x78,
          0x9C,
          0x63,
          0x00,
          0x01,
          0x00,
          0x00,
          0x05,
          0x00,
          0x01,
          0x0D,
          0x0A,
          0x2D,
          0xB4,
          0x00,
          0x00,
          0x00,
          0x00,
          0x49,
          0x45,
          0x4E,
          0x44,
          0xAE,
          0x42,
          0x60,
          0x82,
        ];
      },
    );
    const url = 'https://example.com/favicon.png';
    final first = await cache.resolve(url);
    final second = await cache.resolve(url);
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first!.path, second!.path);
    expect(fetches, 1);
  });
}
