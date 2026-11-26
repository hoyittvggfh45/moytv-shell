import 'dart:io';

import 'package:moyi/builtin_py_sites.dart';
import 'package:moyi/crosssite_probe.dart';
import 'package:moyi/models.dart';
import 'package:moyi/plugin_manager.dart';
import 'package:moyi/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

/// 潮流AV 注册守卫：2026-11-18 按用户令重写为真实站直连，不再调
/// App 的 feed API（chaoliu-feed2-k7m2 已从源里摘净）。视频链走
/// mjv011.com 直连 HTML（分类/列表/详情/搜索/play.php 取流，纯
/// Python AES 解 pid，与 jar 版 ZakaMjv011Amns2 同链）；女优库与
/// 图库走潮流自有站 chaoliu-av-tk8m.web.zaka.live 的 jp220/data220
/// 烤制数据。分类与 mjv011.com 导航 1:1（首页 + 每日更新 + 15 个
/// 导航分类 + 女优库 + 7 个图库 = 25）。蜘蛛本体交付门已全过：
/// 25 个分类首页非空有真封面、翻页零重叠、详情出 3 档播放地址、
/// playerContent 回真 m3u8（1422 分片/7109 秒、AES-128 密钥 16
/// 字节可取）、搜索出真结果、番号秒播表与 MJV 回退链均验真播；
/// 见 ~/workspace/chaoliu_realsite_20261118/（gate2/gate3/gate5
/// 日志）。这里只守注册正确：文件在位且与来源字节一致、协议齐
/// 全、key 唯一、无中文注释、分类数 25、插件清单与跨站选线已接
/// 通。手机待验：qrtuv CDN 的秒播地址本机出口 403、手机上能否播
/// 须实测；jar 版委托链与图集 Large_cgurl 提取未经真机跑。
///
/// 2026-11-26 空壳片库定版：本站内置登记与 py 文件已剥离，本文件
/// 的在树文件类断言（字节一致/协议/分类数等）随之撤除，只守剥离
/// 干净、key 不撞、跨站探针名单不断链。
void main() {
  // 2026-11-26 空壳片库定版：潮流AV 的内置登记与 py 文件已剥离
  //（改从插件市场装回，本站已有 idj 插件版）。原「注册值与蜘蛛文件
  // 齐全 / 字节一致 / 0 中文注释 / 分类数 25 / 不含 feed API」五项
  // 都是对在树文件的断言，文件不在即全部失去对象，统一改守剥离干净。
  test('潮流AV：空壳片库已剥离，登记与蜘蛛文件都不在', () {
    expect(BuiltinPySites.entryFor('chaoliu'), isNull);
    expect(File('assets/py_spiders/chaoliu.py').existsSync(), isFalse);
    expect(SourceSite.allValues.any((s) => s.id == 'chaoliu'), isFalse);
  });

  test('潮流AV：key 不与 jar 内置站撞', () {
    expect(zakatvBuiltinSites.any((s) => s.key == 'chaoliu'), isFalse);
  });

  test('潮流AV：key 不与既有站源 id 撞', () {
    expect(SourceSite.allValues.any((s) => s.id == 'chaoliu'), isFalse);
  });

  test('潮流AV：内置 py 插件清单里没有它（清单已整体清空）', () {
    expect(BuiltinPySites.entryFor('chaoliu'), isNull);
    final plugins = PluginManager.builtinPlugins();
    expect(plugins, isEmpty);
    expect(plugins.map((p) => p.id), isNot(contains('py:chaoliu')));
  });

  test('潮流AV：跨站选线已接通', () {
    expect(crossSitePrioritySiteIds, contains('chaoliu'));
  });
}
