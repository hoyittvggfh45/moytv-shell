import 'package:moyi/content_models.dart';
import 'package:moyi/content_py.dart';
import 'package:moyi/content_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('内容注册表清单', () {
    test('听书：空壳只剩原生听书网、懒人听书（py 蜘蛛与飞卢已剥离）', () {
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.id),
        [
          'tingshuwang',
          'lrts',
        ],
      );
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.name),
        [
          '听书网',
          '懒人听书',
        ],
      );
    });

    test('听书：空壳无 py 成人源在列', () {
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.id),
        [
          'tingshuwang',
          'lrts',
        ],
      );
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).last.name,
        '懒人听书',
      );
    });

    test('小说：内置源默认在列，导入后只进小说区', () {
      addTearDown(() {
        ContentRegistry.setNovelImports([]);
      });
      expect(
        ContentRegistry.sourcesFor(ContentSection.novel).map((s) => s.id),
        containsAll([
          'aabook',
          'ylxs',
          'cheniyo',
          'hwg4',
          'buliang',
          'yinse',
          'mhbl',
          'ho5ho',
        ]),
      );
      ContentRegistry.setNovelImports([
        PyContentSource(
          id: 'novel_demo',
          name: '演示小说',
          importedFileName: 'demo.py',
          section: ContentSection.novel,
        ),
      ]);
      final novelIds = ContentRegistry.sourcesFor(
        ContentSection.novel,
      ).map((s) => s.id);
      expect(novelIds, contains('novel_demo'));
      expect(novelIds.last, 'novel_demo');
      expect(
        ContentRegistry.sourcesFor(ContentSection.audio).map((s) => s.id),
        [
          'tingshuwang',
          'lrts',
        ],
      );
    });

    test('小说内置源默认在列，导入源排在后面', () {
      addTearDown(() {
        ContentRegistry.setNovelImports([]);
      });
      final offIds = ContentRegistry.sourcesFor(
        ContentSection.novel,
      ).map((s) => s.id);
      expect(offIds, isNot(isEmpty));
      expect(offIds, contains('aabook'));
      final onIds = ContentRegistry.sourcesFor(
        ContentSection.novel,
      ).map((s) => s.id).toList();
      expect(onIds.sublist(0, 10), [
        'aabook',
        'ylxs',
        'cheniyo',
        'hwg4',
        'buliang',
        'yinse',
        'mhbl',
        'ho5ho',
        'modu18',
        'h528',
      ]);
      expect(
        ContentRegistry.sourcesFor(ContentSection.novel).first.name,
        '🔞疯情书库',
      );
      ContentRegistry.setNovelImports([
        PyContentSource(
          id: 'novel_demo',
          name: '演示小说',
          importedFileName: 'demo.py',
          section: ContentSection.novel,
        ),
      ]);
      final withImport = ContentRegistry.sourcesFor(
        ContentSection.novel,
      ).map((s) => s.id).toList();
      expect(withImport.last, 'novel_demo');
      expect(withImport.sublist(0, 10), [
        'aabook',
        'ylxs',
        'cheniyo',
        'hwg4',
        'buliang',
        'yinse',
        'mhbl',
        'ho5ho',
        'modu18',
        'h528',
      ]);
    });

    test('id 全局唯一且分区归属自洽', () {
      final all = [
        for (final section in ContentSection.values)
          ...ContentRegistry.sourcesFor(section),
      ];
      expect(all.map((s) => s.id).toSet(), hasLength(all.length));
      for (final section in ContentSection.values) {
        for (final source in ContentRegistry.sourcesFor(section)) {
          expect(source.section, section);
        }
      }
    });
  });
}
