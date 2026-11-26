import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/plugin_manager.dart';
import 'package:moyi/zakatv_builtin.dart';

// 2026-11-26 空壳片库定版：missav30 的登记在 2026-11-22 已摘空，
// 本版进一步把 assets/jars/missav30.jar 文件本体也剥离（此前是
// 「登记空、jar 原样留存供恢复」，空壳版口径是包内不带站点资源）。
// 本文件改写为剥离守卫 + zakatv.jar 未动守卫（该 jar 因飞卢听书
// 保留，字节必须与剥离前一致）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missav30 jar 已剥离：包内文件不在（常量仅作历史记录）', () {
    expect(File('assets/jars/missav30.jar').existsSync(), isFalse);
    expect(missav30JarMd5, '15efee5d3f3f4b2433bd25bc16ccf139');
    expect(missav30JarAsset, 'assets/jars/missav30.jar');
  });

  test('missav30 登记已摘空：2026-11-22 用户令删 MissAV 全部旧站', () {
    expect(missav30BuiltinSites, isEmpty);
    expect(zakatvBuiltinSites.any((s) => s.key == 'ZakaMissav'), isFalse);
    expect(zakatvBuiltinSites.any((s) => s.key == 'ZakaMissavOff'), isFalse);
    expect(zakatvBuiltinSites.any((s) => s.key == 'missavt'), isFalse);
    expect(zakatvBuiltinSites.any((s) => s.key == 'ZakaMirror'), isFalse);
    // 2026-11-26 空壳片库：zakatv 侧登记只剩飞卢听书 1 条。
    expect(zakatvBuiltinSites.length, 1);
    expect(zakatvBuiltinSites.single.key, 'go_tingshu');
  });

  test('missav30 插件条目已摘除（内置插件清单整体清空）', () {
    final plugins = PluginManager.builtinPlugins();
    expect(plugins, isEmpty);
    expect(plugins.any((p) => p.id == 'jar:missav30'), isFalse);
  });

  test('JSON 镜像已随剥离删除：jar_site_configs.json 不在', () {
    expect(File('assets/jar_site_configs.json').existsSync(), isFalse);
  });

  test('zakatv.jar 未动守卫：md5 + 23 条目不变', () {
    expect(zakatvJarMd5, '029005c7ce017dc0a412f2d079a29dab');
    final bytes = File('assets/jars/zakatv.jar').readAsBytesSync();
    expect(md5.convert(bytes).toString(), zakatvJarMd5);
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toList();
    expect(names.length, 23);
  });

  test('旧站点 id 全树零残留：生产 + 测试里不再有 jar:zakatv 的 3 个 MissAV id', () {
    // 模式用拼接写，避免本文件自身的字面量被扫到。
    const forbidden = [
      'jar:zakatv:'
          'ZakaMissav',
      'jar:zakatv:'
          'ZakaMissavOff',
      'jar:zakatv:'
          'missavt',
    ];
    final offenders = <String>[];
    for (final dir in ['lib', 'test']) {
      for (final entity in Directory(
        dir,
      ).listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        for (final pattern in forbidden) {
          if (text.contains(pattern)) {
            offenders.add('${entity.path} 含 $pattern');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
