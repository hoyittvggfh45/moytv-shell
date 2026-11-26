import 'package:flutter/services.dart';
import 'package:moyi/builtin_py_sites.dart';
import 'package:moyi/models.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-11-26 空壳片库定版：内置 py 站（原 127 条登记 + assets/py_spiders
// 全部文件）已剥离，站点改从插件市场安装/外部导入。本文件由原来的
// 逐站注册断言改写为剥离守卫：登记表为空、注册无操作、资源包里
// 再也加载不到任何内置 py 蜘蛛文件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('空壳片库：内置 py 登记已剥离', () {
    test('登记表为空、按 id 查不到任何条目', () {
      expect(BuiltinPySites.entries, isEmpty);
      expect(BuiltinPySites.entryFor('hmav'), isNull);
      expect(BuiltinPySites.entryFor('missav'), isNull);
      expect(BuiltinPySites.entryFor('javmenu'), isNull);
    });

    test('register/registerSkipping 是无操作，不往导入站表里加东西', () async {
      final before = Map.of(SourceSite.importedSites);
      await BuiltinPySites.register();
      await BuiltinPySites.registerSkipping(const {'hmav'});
      expect(SourceSite.importedSites, before);
      expect(
        SourceSite.importedSites.keys.where(
          (id) => id == 'hmav' || id == 'missav' || id == 'qilinyingshi',
        ),
        isEmpty,
      );
    });

    test('女优库跨站探针的三个候选站 id 常量保留（仅 id、无站点本体）', () {
      expect(BuiltinPySites.javmenuSiteId, 'javmenu');
      expect(BuiltinPySites.avdbSiteId, 'avdb');
      expect(BuiltinPySites.memojavSiteId, 'memojav');
    });

    test('资源包里加载不到已剥离的 py 蜘蛛文件', () async {
      for (final path in [
        'assets/py_spiders/hmav.py',
        'assets/py_spiders/missav.py',
        'assets/py_spiders/youtube.py',
        'assets/py_spiders/zgj_maccms.py',
      ]) {
        var threw = false;
        try {
          await rootBundle.load(path);
        } catch (_) {
          threw = true;
        }
        expect(threw, isTrue, reason: '$path 不应还能加载到');
      }
    });
  });
}
