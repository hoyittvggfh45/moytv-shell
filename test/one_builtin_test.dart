import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/plugin_manager.dart';
import 'package:moyi/zakatv_builtin.dart';

// 2026-11-26 空壳片库定版：一点播（One）是片库 jar 站，登记与
// assets/jars/one.jar 已一并剥离（改从插件市场装回）。本文件由
// 原来的 jar 内容/登记断言改写为剥离守卫；jar 的 md5/资产路径
// 常量保留在 zakatv_builtin.dart 里仅作历史记录，不再被注册路径使用。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one jar 已剥离：包内文件不在', () {
    expect(File('assets/jars/one.jar').existsSync(), isFalse);
    expect(oneJarAsset, 'assets/jars/one.jar');
  });

  test('one builtin site registry 已清空', () {
    expect(oneBuiltinSites, isEmpty);
    expect(oneJarId, 'one');
  });

  test('one jar 在内置插件清单里没有条目（清单已整体清空）', () {
    final plugins = PluginManager.builtinPlugins();
    expect(plugins, isEmpty);
    expect(
      plugins.any((p) => p.id == PluginManager.oneJarPluginId),
      isFalse,
    );
  });

  test('jar site configs json 已随剥离删除，无 One 镜像可对', () {
    expect(File('assets/jar_site_configs.json').existsSync(), isFalse);
  });

  test('zakatv registry 只剩飞卢听书一条（听读保留）', () {
    expect(zakatvBuiltinSites.length, 1);
    expect(zakatvBuiltinSites.single.key, 'go_tingshu');
    expect(zakatvJarMd5, '029005c7ce017dc0a412f2d079a29dab');
    expect(zakatvBuiltinSites.any((site) => site.key == 'One'), isFalse);
  });
}
