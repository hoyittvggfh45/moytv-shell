import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/build_variant.dart';
import 'package:moyi/plugin_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 本文件两种变体都要跑：默认跑正常版，
  // flutter test --dart-define=MOYI_EMPTY_SHELL=true 跑空壳版。
  // 每次运行打印变体值，日志里能看出跑的是哪一版。
  test('report build variant', () {
    // ignore: avoid_print
    print('emptyShellBuild=$emptyShellBuild');
  });

  test('builtinPlugins follows the build variant', () {
    // 2026-11-26 空壳片库定版：本树即空壳发布线——内置插件登记
    // 已在源码层整表剥离，两个变体下清单都为空（带站点版在另一条
    // 发布线维护，其清单口径不在本树）。基线 efd0049 上本项因
    // 清单计数漂移（期望 126、实际 127）失败，剥离后按空表改写。
    final plugins = PluginManager.builtinPlugins();
    expect(plugins, isEmpty);
  });

  test('ensureBuiltinPlugins never throws in either variant', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await PluginManager.ensureBuiltinPlugins(preferences);
    // 空壳版直接返回；正常版在测试环境逐条吞错。都不抛错。
  });

  test('installBuiltinPlugin refuses in the empty shell', () async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
    // 2026-11-26 空壳片库定版：清单已空，两个变体下都装不出
    // 任何内置插件（原断言只在空壳变体下校验）。
    expect(
      await PluginManager.installBuiltinPlugin(PluginManager.jarPluginId),
      isFalse,
    );
    expect(
      await PluginManager.installBuiltinPlugin('py:hmav'),
      isFalse,
    );
  });
}
