import 'dart:io';

import 'package:moyi/builtin_py_sites.dart';
import 'package:moyi/content_models.dart';
import 'package:moyi/content_py.dart';
import 'package:moyi/content_registry.dart';
import 'package:moyi/models.dart';
import 'package:moyi/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

/// 分区内置批（2026-11-27）注册守卫：Hentai-Park 对账后我方逐站重写并
/// 全链验过的站按区内置——片库 6 站（Eporner、91视频、Fyptt、RedGifs、
/// SOOP短视频、PopkonTV短视频）走 builtin_py_sites 种子登记，听读区
/// ASMRHoney 走 content_registry 的 audio 分区。这里只守注册正确：
/// 分区/来源/类型/🔞 名、文件在位、协议 14 方法齐全、0 中文注释、
/// key 不与 jar 内置站和既有站源撞。各站真链已在站点合并批验过
/// （见 ~/workspace/hentaipark_sites_merge_20261127/WORKLIST.md）；
/// 91视频插件形态验证台最后一步曾被本机环境卡住、同址直连 206，
/// 内置 py 本体全链已验，此处如实标注、不冒充插件形态已过。
const _protocolMethods = <String>[
  'getName',
  'getDependence',
  'init',
  'destroy',
  'homeContent',
  'homeVideoContent',
  'categoryContent',
  'detailContent',
  'searchContent',
  'playerContent',
  'localProxy',
  'isVideoFormat',
  'manualVideoCheck',
  'action',
];

void _checkSpiderFile(String assetPath, String spiderName) {
  final file = File(assetPath);
  expect(file.existsSync(), isTrue, reason: '$assetPath 不存在');
  final text = file.readAsStringSync();
  expect(text.contains('class Spider(BaseSpider)'), isTrue);
  for (final method in _protocolMethods) {
    expect(
      text.contains('def $method'),
      isTrue,
      reason: '$assetPath 缺方法 $method',
    );
  }
  expect(text.contains('return "$spiderName"'), isTrue);
}

void _checkNoCjkComments(String assetPath) {
  final cjk = RegExp(r'[\u4e00-\u9fff]');
  final text = File(assetPath).readAsStringSync();
  for (final line in text.split('\n')) {
    final hash = line.indexOf('#');
    if (hash < 0) continue;
    expect(
      cjk.hasMatch(line.substring(hash)),
      isFalse,
      reason: '$assetPath 中文注释：$line',
    );
  }
}

void main() {
  const videoCases = <(SourceSite, String, String, String)>[
    // (site, assetPath, spiderName, 期望显示名) —— 显示名在逐条用例里核
    (BuiltinPySites.epornerSite, '', 'Eporner', '🔞Eporner'),
    (BuiltinPySites.porn91Site, '', '91Porn', '🔞91视频'),
    (BuiltinPySites.fypttSite, '', 'Fyptt', '🔞Fyptt'),
    (BuiltinPySites.redgifsSite, '', 'RedGifs', '🔞RedGifs'),
    (BuiltinPySites.soopshortSite, '', 'SOOP短视频', '🔞SOOP短视频'),
    (BuiltinPySites.popkonshortSite, '', 'PopkonTV短视频', '🔞PopkonTV短视频'),
  ];

  group('分区内置 · 片库 6 站', () {
    test('注册值：视频分区、内置来源、py 类型、🔞 名、进点播区', () {
      final assetById = <String, String>{
        BuiltinPySites.epornerSiteId: BuiltinPySites.epornerAssetPath,
        BuiltinPySites.porn91SiteId: BuiltinPySites.porn91AssetPath,
        BuiltinPySites.fypttSiteId: BuiltinPySites.fypttAssetPath,
        BuiltinPySites.redgifsSiteId: BuiltinPySites.redgifsAssetPath,
        BuiltinPySites.soopshortSiteId: BuiltinPySites.soopshortAssetPath,
        BuiltinPySites.popkonshortSiteId:
            BuiltinPySites.popkonshortAssetPath,
      };
      for (final (site, _, _, expectedName) in videoCases) {
        expect(site.name, expectedName, reason: site.id);
        expect(site.section, SourceSite.sectionVideo, reason: site.id);
        expect(site.origin, SourceSite.originBuiltin, reason: site.id);
        expect(site.importType, 'py', reason: site.id);
        expect(isVodZoneSource(site), isTrue, reason: site.id);
        expect(assetById[site.id], 'assets/py_spiders/${site.id}.py');
        final entry = BuiltinPySites.entryFor(site.id);
        expect(entry, isNotNull, reason: '${site.id} 未进 entries');
        expect(entry!.site, same(site));
        expect(entry.assetPath, assetById[site.id]);
        expect(entry.fileId, 'builtin_${site.id}');
      }
    });

    test('蜘蛛文件齐全：14 方法、getName、0 中文注释', () {
      final assetById = <String, String>{
        'eporner': BuiltinPySites.epornerAssetPath,
        '91porn': BuiltinPySites.porn91AssetPath,
        'fyptt': BuiltinPySites.fypttAssetPath,
        'redgifs': BuiltinPySites.redgifsAssetPath,
        'soopshort': BuiltinPySites.soopshortAssetPath,
        'popkonshort': BuiltinPySites.popkonshortAssetPath,
      };
      for (final (site, _, spiderName, _) in videoCases) {
        _checkSpiderFile(assetById[site.id]!, spiderName);
        _checkNoCjkComments(assetById[site.id]!);
      }
    });

    test('key 不与 jar 内置站、既有站源及其它内置 py 撞', () {
      final ids = videoCases.map((c) => c.$1.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final siteId in ids) {
        expect(zakatvBuiltinSites.any((s) => s.key == siteId), isFalse);
        expect(SourceSite.allValues.any((s) => s.id == siteId), isFalse);
        expect(
          BuiltinPySites.entries.where((e) => e.siteId == siteId).length,
          1,
          reason: '$siteId 在 entries 里应恰好一条',
        );
      }
    });
  });

  group('分区内置 · 听读区 ASMRHoney', () {
    test('注册值：audio 分区可见、🔞 名、资产路径', () {
      final audio = ContentRegistry.sourcesFor(ContentSection.audio);
      final source = audio.singleWhere((s) => s.id == 'asmrhoney');
      expect(source.name, '🔞ASMRHoney');
      expect(source.section, ContentSection.audio);
      expect(source, isA<PyContentSource>());
      expect(
        (source as PyContentSource).assetPath,
        'assets/audio_spiders/asmrhoney.py',
      );
      expect(ContentRegistry.isKnownId('asmrhoney'), isTrue);
      expect(
        ContentRegistry.allSources.where((s) => s.id == 'asmrhoney').length,
        1,
      );
    });

    test('蜘蛛文件齐全：14 方法、getName、0 中文注释', () {
      _checkSpiderFile('assets/audio_spiders/asmrhoney.py', 'ASMRHoney');
      _checkNoCjkComments('assets/audio_spiders/asmrhoney.py');
    });
  });
}
