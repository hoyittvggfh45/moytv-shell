import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/danmaku_models.dart';
import 'package:moyi/intro_outro_skip.dart';
import 'package:moyi/danmaku_settings.dart';
import 'package:moyi/danmaku_xml.dart';
import 'package:moyi/models.dart';
import 'package:moyi/playback_preferences.dart';
import 'package:moyi/player_menu.dart';
import 'package:moyi/player_overlay_settings.dart';
import 'package:moyi/sleep_timer.dart';
import 'package:moyi/subtitle_style.dart';
import 'package:moyi/track_selection.dart';


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
  group('B 站弹幕 XML 解析', () {
    test('模式与颜色映射', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<i>
<d p="1.5,1,25,16777215,1700000000,0,abcd,1">普通滚动</d>
<d p="2.5,5,25,16711680,1700000000,0,abcd,2">置顶红色</d>
<d p="3.5,4,25,65280,1700000000,0,abcd,3">置底</d>
<d p="4.5,6,25,255,1700000000,0,abcd,4">反向</d>
<d p="5.5,1,25,16777215,1700000000,0,abcd,5">带&amp;实体</d>
</i>''';
      final items = parseBilibiliDanmakuXml(xml);
      expect(items, hasLength(5));
      expect(items[0].mode, DanmakuMode.scroll);
      expect(items[0].colorValue, isNull); // 白色回默认
      expect(items[0].timeMs, 1500);
      expect(items[1].mode, DanmakuMode.top);
      expect(items[1].colorValue, 0xFFFF0000);
      expect(items[2].mode, DanmakuMode.bottom);
      expect(items[3].mode, DanmakuMode.reverse);
      expect(items[4].text, '带&实体');
    });

    test('坏行跳过不抛、空文本跳过', () {
      const xml = '<i><d p="bad">x</d><d p="1,1,25,0,0,0,a,1"></d>'
          '<d p="2,1,25,0,0,0,a,2">好</d></i>';
      final items = parseBilibiliDanmakuXml(xml);
      expect(items, hasLength(1));
      expect(items.single.text, '好');
    });

    test('无 d 元素回空表', () {
      expect(parseBilibiliDanmakuXml('<html></html>'), isEmpty);
    });
  });

  group('弹幕显示设置往返与钳值', () {
    test('默认值与 SPEC 帧内值一致', () {
      const settings = DanmakuDisplaySettings.defaults;
      expect(settings.displayAreaPercent, 50);
      expect(settings.opacityPercent, 100);
      expect(settings.fontSizePercent, 100);
      expect(settings.fullscreenFontSizePercent, 120);
      expect(settings.scrollDurationSeconds, 7);
      expect(settings.staticDurationSeconds, 4);
      expect(settings.lineHeight, 1.6);
      expect(settings.strokeWidth, 1.5);
    });

    test('往返一致、越界钳回', () {
      final settings = DanmakuDisplaySettings.fromJson({
        'displayAreaPercent': 500,
        'opacityPercent': -3,
        'randomColor': true,
        'scrollDurationSeconds': 99,
      });
      expect(settings.displayAreaPercent, 100);
      expect(settings.opacityPercent, 10);
      expect(settings.randomColor, isTrue);
      expect(settings.scrollDurationSeconds, 15);
      final back = DanmakuDisplaySettings.fromJson(settings.toJson());
      expect(back.toJson(), settings.toJson());
    });
  });

  group('屏显设置往返', () {
    test('默认值全开、字号钳值', () {
      const settings = OverlayDisplaySettings();
      expect(settings.showClock, isTrue);
      expect(settings.progressVisibility, ProgressVisibility.always);
      final clamped = OverlayDisplaySettings.fromJson({'fontSize': 99});
      expect(clamped.fontSize, 20);
      final back = OverlayDisplaySettings.fromJson(settings.toJson());
      expect(back.toJson(), settings.toJson());
    });
  });

  group('字幕样式往返', () {
    test('默认值与钳值', () {
      const settings = SubtitleStyleSettings.defaults;
      expect(settings.fontSize, 55);
      expect(settings.position, 100);
      final clamped = SubtitleStyleSettings.fromJson({'fontSize': 3});
      expect(clamped.fontSize, 10);
      final back = SubtitleStyleSettings.fromJson(settings.toJson());
      expect(back.toJson(), settings.toJson());
    });
  });

  group('播放偏好硬解字段', () {
    test('往返一致', () {
      const prefs = const PlaybackPreferences();
      expect(prefs.hardwareAcceleration, isTrue);
      expect(prefs.hwdecMode, 'auto-safe');
      expect(prefs.effectiveHwdec, 'auto-safe');
      final changed = prefs.copyWith(
        hardwareAcceleration: false,
        hwdecMode: 'mediacodec-copy',
      );
      final back = PlaybackPreferences.fromJson(changed.toJson());
      expect(back.hardwareAcceleration, isFalse);
      expect(back.hwdecMode, 'mediacodec-copy');
      // 硬解关时实际下发 no，模式字段保留待重新打开时用。
      expect(back.effectiveHwdec, 'no');
    });

    test('硬解关时 effective 回 no；非法模式回默认', () {
      final off = const PlaybackPreferences().copyWith(
        hardwareAcceleration: false,
      );
      expect(off.effectiveHwdec, 'no');
      final bad = PlaybackPreferences.fromJson({'hwdecMode': 'nonsense'});
      expect(bad.hwdecMode, 'auto-safe');
    });
  });

  group('视轨条目', () {
    test('从 TrackChoice 列表构造并标选中', () {
      final entries = buildVideoTrackEntries(
        const [
          TrackChoice(id: 'v1', title: '1080p'),
          TrackChoice(id: 'v2'),
        ],
        selectedId: 'v2',
      );
      expect(entries, hasLength(2));
      expect(entries[0].label, '1080p');
      expect(entries[1].label, '视轨 2');
      expect(entries[1].selected, isTrue);
      expect(entries.every((e) => e.kind == TrackMenuEntryKind.video), isTrue);
    });
  });

  group('更多菜单冒烟', () {
    final episodes = [
      Episode(const {'id': 'e1', 'currentEpisode': 1}, 1),
      Episode(const {'id': 'e2', 'currentEpisode': 2}, 2),
    ];

    Future<PlaybackPreferences> pumpMore(
      WidgetTester tester, {
      required bool mpvControls,
      List<PlaybackPreferences>? sink,
    }) async {
      var prefs = const PlaybackPreferences();
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
                preferences: prefs,
                qualities: const [],
                actualQuality: 0,
                local: false,
                favorite: false,
                mobile: true,
                onEpisode: (_) {},
                onPreferences: (next) async {
                  prefs = next;
                  sink?.add(next);
                  setState(() {});
                },
                onFavorite: () async {},
                onReload: () async {},
                onShowAddress: (_) async {},
                onShowInfo: (_) async {},
                onLoadDanmakuFromUrl: (_) async => 0,
                onLoadDanmakuFromFile: () async => 0,
                sleepTimer: SleepTimerController(onExpire: () {}),
                danmakuSettingsStore: DanmakuSettingsStore.instance,
                introOutro: const IntroOutroSettings(),
                onIntroOutroChanged: (_) async {},
                mpvControls: mpvControls,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return prefs;
    }

    testWidgets('关键行存在；长按倍速芯片写入 holdSpeed', (tester) async {
      final written = <PlaybackPreferences>[];
      await pumpMore(tester, mpvControls: true, sink: written);
      for (final keyName in [
        'more-sleep-timer',
        'more-playback-address',
        'more-reload',
        'more-danmaku-load',
        'more-danmaku-settings',
        'more-intro-outro',
        'more-hold-speed',
        'more-playback-info',
      ]) {
        final finder = find.byKey(ValueKey(keyName));
        await revealInMenu(tester, finder);
        expect(finder, findsOneWidget, reason: keyName);
      }
      final speedChip = find.byKey(const ValueKey('more-hold-speed-3.0'));
      await revealInMenu(tester, speedChip);
      await tester.tap(speedChip);
      await tester.pump();
      // 芯片点选经 onPreferences 写回 holdSpeed=3.0。
      expect(written.last.holdSpeed, 3.0);
    });

    testWidgets('非 MPV 核不显示解码组', (tester) async {
      await pumpMore(tester, mpvControls: false);
      expect(
        find.byKey(const ValueKey('more-hardware-acceleration')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('more-quick-soft')), findsNothing);
    });

    testWidgets('MPV 核显示解码组且硬解开关可拨', (tester) async {
      await pumpMore(tester, mpvControls: true);
      final tile = find.byKey(const ValueKey('more-hardware-acceleration'));
      await revealInMenu(tester, tile);
      expect(tile, findsOneWidget);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });
  });
}
