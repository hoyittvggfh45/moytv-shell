import 'dart:io';

import 'package:moyi/builtin_py_sites.dart';
import 'package:moyi/crosssite_probe.dart';
import 'package:moyi/models.dart';
import 'package:moyi/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

/// AVDB 与 MemoJav 注册守卫：两份 py 已在 2026-11-14 用蜘蛛本体
/// 验过真站（见 ~/workspace/avdb_memojav_sources/REPORT.md：AVDB
/// 30 项过、MemoJav 35 项 + 两部全长真播过），这里只守注册正确：
/// 文件在位、协议齐全、key 唯一、无中文注释、跨站选线已接通。
/// AVDB 真播因签名 IP 绑定在本机出口验不了，属已知未验项，
/// 注册时不冒充已验，手机终验见回报清单。
///
/// 2026-11-26 空壳片库定版后：两站的登记与 py 文件已剥离（改从
/// 插件市场装回），本文件改为守「剥离干净 + 跨站探针名单不断链」：
/// 站点本体不在、文件不在，但女优库跨站选线名单里的 id 仍在
/// （探针查不到站会自动跳过）。
void main() {
  test('AVDB：空壳片库已剥离，登记与蜘蛛文件都不在', () {
    expect(BuiltinPySites.entryFor(BuiltinPySites.avdbSiteId), isNull);
    expect(File('assets/py_spiders/avdb.py').existsSync(), isFalse);
  });

  test('MemoJav：空壳片库已剥离，登记与蜘蛛文件都不在', () {
    expect(BuiltinPySites.entryFor(BuiltinPySites.memojavSiteId), isNull);
    expect(File('assets/py_spiders/memojav.py').existsSync(), isFalse);
  });

  test('AVDB 与 MemoJav：key 不与 jar 内置站撞', () {
    for (final siteId in [
      BuiltinPySites.avdbSiteId,
      BuiltinPySites.memojavSiteId,
    ]) {
      expect(zakatvBuiltinSites.any((s) => s.key == siteId), isFalse);
    }
  });

  test('AVDB 与 MemoJav：key 不与既有站源 id 撞', () {
    for (final siteId in [
      BuiltinPySites.avdbSiteId,
      BuiltinPySites.memojavSiteId,
    ]) {
      expect(SourceSite.allValues.any((s) => s.id == siteId), isFalse);
    }
  });

  test('AVDB 与 MemoJav：跨站选线已接通，不再显示未接入', () {
    expect(crossSitePrioritySiteIds, contains('avdb'));
    expect(crossSitePrioritySiteIds, contains('memojav'));
    expect(
      crossSiteUnconnectedProviders.any(
        (p) => p.id == 'avdb' || p.id == 'memojav',
      ),
      isFalse,
    );
  });
}
