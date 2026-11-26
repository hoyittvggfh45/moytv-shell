import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/builtin_py_sites.dart';
import 'package:moyi/content_models.dart';
import 'package:moyi/content_registry.dart';
import 'package:moyi/home_zone.dart';
import 'package:moyi/listen_read_page.dart';
import 'package:moyi/models.dart';

void main() {
  group('郑国健批内置 py 站', () {
    // 2026-11-26 空壳片库定版：漫果（manman，通用蜘蛛 zgj_maccms）
    // 的内置登记与 py 文件已剥离，改从插件市场装回；本项改守剥离干净。
    test('漫果：空壳片库已剥离，登记与通用蜘蛛文件都不在', () {
      expect(BuiltinPySites.entryFor('manman'), isNull);
      expect(
        BuiltinPySites.entries.map((e) => e.siteId),
        isNot(contains('manman')),
      );
      expect(SourceSite.allValues.any((s) => s.id == 'manman'), isFalse);
    });
  });

  group('音乐分区', () {
    test('ContentSection.music 标签与音频类语义', () {
      expect(ContentSection.music.title, '音乐');
      expect(ContentSection.music.isAudioLike, isTrue);
      expect(ContentSection.audio.isAudioLike, isTrue);
      expect(ContentSection.novel.isAudioLike, isFalse);
    });

    test('音乐区注册表可查（当前无内置音乐源时为空表）', () {
      expect(
        ContentRegistry.sourcesFor(ContentSection.music),
        isA<List<ContentSource>>(),
      );
    });

    testWidgets('听读页三胶囊：听书/阅读/音乐，点音乐回调 music 区', (tester) async {
      HomeZone? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenReadPage(
              zone: HomeZone.audio,
              onZoneSelected: (z) => picked = z,
              zoneBuilder: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('listenread-audio')), findsOneWidget);
      expect(find.byKey(const ValueKey('listenread-novel')), findsOneWidget);
      expect(find.byKey(const ValueKey('listenread-music')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('listenread-music')));
      expect(picked, HomeZone.music);
    });
  });
}
