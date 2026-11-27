import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/local_store.dart';
import 'package:moyi/models.dart';
import 'package:moyi/player_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 「去广告」开关（原在设置页「播放设置」，2026-11-27 随播放偏好
// 迁入播放器内嵌「更多」菜单）：共用 PlaybackPreferences.adBlock
// （默认开），拨动后立即落盘。

/// 菜单内有多个 Scrollable，scrollUntilVisible 默认取 .single 会炸；
/// 改用拖动 SingleChildScrollView 直到目标滚进可视区。
Future<void> revealInMenu(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(SingleChildScrollView).first;
  for (var i = 0; i < 40; i++) {
    if (finder.evaluate().isNotEmpty) {
      final view = tester.getRect(scrollable);
      final item = tester.getRect(finder);
      if (item.center.dy >= view.top && item.center.dy <= view.bottom) {
        return;
      }
    }
    await tester.drag(scrollable, const Offset(0, -320));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  Future<LocalStore> freshStore() async {
    SharedPreferences.setMockInitialValues({});
    return LocalStore(await SharedPreferences.getInstance());
  }

  final episodes = [
    Episode(const {'id': 'e1', 'currentEpisode': 1}, 1),
    Episode(const {'id': 'e2', 'currentEpisode': 2}, 2),
  ];

  Future<void> pumpMenu(WidgetTester tester, LocalStore store) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlayerMenu(
              section: PlayerMenuSection.more,
              episodes: episodes,
              currentIndex: 0,
              preferences: store.playbackPreferences,
              qualities: const [],
              actualQuality: 0,
              local: false,
              favorite: false,
              mobile: true,
              onEpisode: (_) {},
              onPreferences: (next) async {
                await store.setPlaybackPreferences(next);
                setState(() {});
              },
              onFavorite: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('去广告开关默认开，拨动后写入偏好', (tester) async {
    final store = await freshStore();
    expect(store.playbackPreferences.adBlock, isTrue);
    await pumpMenu(tester, store);
    final tile = find.byKey(const ValueKey('player-adblock-enabled'));
    await revealInMenu(tester, tile);
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pump();
    expect(store.playbackPreferences.adBlock, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pump();
    expect(store.playbackPreferences.adBlock, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  testWidgets('已保存为关时开关显示关', (tester) async {
    final store = await freshStore();
    await store.setPlaybackPreferences(
      store.playbackPreferences.copyWith(adBlock: false),
    );
    await pumpMenu(tester, store);
    final tile = find.byKey(const ValueKey('player-adblock-enabled'));
    await revealInMenu(tester, tile);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });
}
