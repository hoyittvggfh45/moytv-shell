import 'dart:io';

import 'package:moyi/builtin_py_sites.dart';
import 'package:moyi/models.dart';
import 'package:moyi/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

/// JavMenu 注册守卫：py 已在 2026-11-13 用蜘蛛本体验过真站（39 个
/// 分类、parse=0 出真 m3u8、Range 206），这里只守注册正确：文件在
/// 位、协议齐全、key 唯一、无中文注释。已知缺口（数字开头番号如
/// /1PONDO-102726 匹配不上）属爬取逻辑，注册时不动、不扩大范围。
///
/// 2026-11-26 空壳片库定版后：本站登记与 py 文件已剥离（改从插件
/// 市场装回），本文件改为守「剥离干净」；javmenuSiteId 常量只作
/// 女优库跨站探针的候选 id 保留。
void main() {
  test('JavMenu：空壳片库已剥离，登记与蜘蛛文件都不在', () {
    expect(BuiltinPySites.entryFor(BuiltinPySites.javmenuSiteId), isNull);
    expect(File('assets/py_spiders/javmenu.py').existsSync(), isFalse);
  });

  test('JavMenu：py 文件 0 中文注释（文件已剥离，本项守文件不在）', () {
    // 原断言逐行读 javmenu.py 查中文注释；文件已随空壳片库删除，
    // 无文件即无注释可查，改守文件确实不在（与上一项同口径）。
    expect(File('assets/py_spiders/javmenu.py').existsSync(), isFalse);
  });

  test('JavMenu：key 不与 jar 内置站撞', () {
    expect(
      zakatvBuiltinSites.any((s) => s.key == BuiltinPySites.javmenuSiteId),
      isFalse,
    );
  });

  test('JavMenu：key 不与既有站源 id 撞', () {
    // Go 核槽位站是 v_javmenu，与 py 注册 key 'javmenu' 不同 id，不撞。
    expect(
      SourceSite.allValues.any((s) => s.id == BuiltinPySites.javmenuSiteId),
      isFalse,
    );
  });
}
