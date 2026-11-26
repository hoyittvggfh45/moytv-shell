import 'dart:io';

import 'package:moyi/jar_site_config.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-11-26 空壳片库定版：assets/jar_site_configs.json（内置 jar
// 站配置镜像）已随剥离删除。本文件改写为：文件不在、加载兜底为空
// 表（用户导入 jar 时不靠内置镜像匹配，靠学习配置/文件名兜底，
// loadBuiltinJarConfigs 的 catch 兜底保证不崩）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builtin jar configs json 已剥离：文件不在', () {
    expect(File('assets/jar_site_configs.json').existsSync(), isFalse);
  });

  test('loadBuiltinJarConfigs 缺文件时兜底空表，不抛错', () async {
    final configs = await loadBuiltinJarConfigs();
    expect(configs, isEmpty);
    expect(
      matchJarSiteConfig('com.github.catvod.spider.YouTube', configs),
      isNull,
    );
    expect(
      matchJarSiteConfig('com.github.catvod.spider.TingShu', configs),
      isNull,
    );
  });

  test('parseJarSiteConfigs 对空表回空表（解析器本身保留）', () {
    expect(parseJarSiteConfigs('{"sites":[]}'), isEmpty);
    // 空文本直接抛 FormatException——loadBuiltinJarConfigs 的
    // try/catch 正是靠它兜底回空表（文件缺失时同理）。
    expect(() => parseJarSiteConfigs(''), throwsFormatException);
  });

  test('builtin jar configs asset constant 仍指向原路径（仅作兜底寻址）', () {
    expect(builtinJarConfigsAsset, 'assets/jar_site_configs.json');
    expect(File(builtinJarConfigsAsset).existsSync(), isFalse);
  });
}
