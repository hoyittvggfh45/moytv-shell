// 空壳片库（2026-11-26 定版）预览图：站点列表两区（无内置区）
// 与片库空态页。只渲染出 PNG，不测行为（行为见
// site_picker_zone_flip_test 与 home 相关测试）。一测一张：调过
// toImage 的测试收尾会挂起（PNG 已落地），单跑、超时杀掉只取 PNG；
// 不要把预览文件和普通测试文件批量放在一次 flutter test 里跑。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/app_theme_config.dart';
import 'package:moyi/home_screen.dart';
import 'package:moyi/local_profiles.dart';
import 'package:moyi/local_store.dart';
import 'package:moyi/source_picker_sheet.dart';
import 'package:moyi/ui_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

const _previewDir = '/home/hatch/workspace/moyi_strip_shell_20261126/preview';

ButtonStyle _withCjk(ButtonStyle? style) {
  final resolved = style?.textStyle?.resolve({}) ?? const TextStyle();
  return (style ?? const ButtonStyle()).copyWith(
    textStyle: WidgetStatePropertyAll(
      resolved.copyWith(fontFamily: 'PreviewCJK'),
    ),
  );
}

ThemeData _previewTheme() {
  final base = AppThemeConfig.forTheme(AppThemeMode.lightClean).toThemeData();
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'PreviewCJK'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'PreviewCJK'),
    dialogTheme: base.dialogTheme.copyWith(
      titleTextStyle: base.dialogTheme.titleTextStyle?.copyWith(
        fontFamily: 'PreviewCJK',
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _withCjk(base.filledButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _withCjk(base.textButtonTheme.style),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
        fontFamily: 'PreviewCJK',
      ),
      subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
        fontFamily: 'PreviewCJK',
      ),
    ),
  );
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final dir = Directory(_previewDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('$_previewDir/$name').writeAsBytesSync(bytes);
}

/// 剥离后的真实分组形态：导入区里是原生功能三站（红果/红果新版/
/// 番茄，origin=builtin 但按现行两区口径落导入区）与用户导入站；
/// 插件区是已装插件站。没有内置区。
const _groups = [
  SourcePickerGroup(
    title: '片库',
    entries: [
      SourcePickerEntry(id: 'hongguo', name: '红果'),
      SourcePickerEntry(id: 'hongguo_new', name: '红果新版'),
      SourcePickerEntry(id: 'fanqie', name: '番茄'),
    ],
    zone: SourcePickerGroup.zoneImport,
  ),
  SourcePickerGroup(
    title: '导入的站',
    entries: [SourcePickerEntry(id: 'imp_py_demo', name: '导入演示站')],
    zone: SourcePickerGroup.zoneImport,
  ),
  SourcePickerGroup(
    title: '插件站',
    entries: [SourcePickerEntry(id: 'idj_chengguo', name: '橙果短剧')],
    zone: SourcePickerGroup.zonePlugin,
  ),
];

void main() {
  setUpAll(() async {
    try {
      final bytes = File(
        '/home/hatch/workspace/huoyi_new/cjk_subset.ttf',
      ).readAsBytesSync();
      final loader = FontLoader('PreviewCJK')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    } catch (_) {}
  });

  testWidgets('preview site picker without builtin zone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appThemeNotifier.value = AppThemeMode.lightClean;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _previewTheme(),
          home: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'PreviewCJK'),
            child: Scaffold(
              body: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: const Text(
                      '空壳片库 · 站点列表（导入区/插件区，无内置区）',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontFamily: 'PreviewCJK',
                      ),
                    ),
                  ),
                  Expanded(
                    child: SitePickerDialog(
                      sectionName: '片库',
                      currentId: 'hongguo',
                      groups: _groups,
                      onImport: () async {},
                      enableZoneFlip: true,
                      initialZoneIndex: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, key, 'site_picker_no_builtin.png');
  });

  testWidgets('preview library empty state', (tester) async {
    // 宽度 1280 走通用分支：手机窄屏且当前组为红果时首屏恒为
    // 红果戏剧首页（byId 空回落红果、戏剧首页分支抢先，基线
    // efd0049 既有行为），片库空态面板（_noSourcesPanel）在
    // 通用分支/电视/桌面与窗口模式下出现，面板本身与宽度无关。
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 无任何可用片库源的状态：受限档案的来源名单为空（恢复后
    // store.source 为 ''、visibleSources 为空），片库体走空态面板。
    // （若只是把原生三站全部隐藏，当前站会回落红果原生首页、
    // 不走本面板——那是另一条既有路径。）
    SharedPreferences.setMockInitialValues({
      'profiles': jsonEncode([
        LocalProfile(
          id: 'default',
          name: '管理员',
          admin: true,
          salt: '0' * 32,
          pinHash: '1' * 64,
        ).toJson(),
        const LocalProfile(
          id: 'viewer',
          name: '空片库用户',
          sources: [],
          download: false,
        ).toJson(),
      ]),
      'activeProfile': 'viewer',
      // 档案的当前站指向已剥离的 dsd：恢复时按未知站处理，
      // store.source 落空（与 app_build_test 的 DSD 档案口径一致）。
      'profile.viewer.source': 'dsd',
      'appThemeMode': 'lightClean',
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    appThemeNotifier.value = AppThemeMode.lightClean;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _previewTheme(),
          navigatorObservers: [homeRouteObserver],
          home: HomeScreen(repository: FixtureRepository(), store: store),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await _shoot(tester, key, 'library_empty_state.png');
  });
}
