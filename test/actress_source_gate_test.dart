// 演员库内部源登记 + 门禁删除回归测试（2026-11-26 立、
// 2026-11-27 改口径）：演员库整批新接的 6 个源 id（javdb /
// av123 / ph / av01 / jable / pan115）有演员库专用登记
// （SourceSite.actressOnlySites），不进选站列表，登记供
// isAvailable / isKnown / byId 识别与站名解析。
//
// 2026-11-27 用户令「把门禁全删除」：源访问门禁整体删除——
// allowsSource 对任何 source（含未注册 id）恒放行，详情页
// 「当前用户无权访问」面板路径已删。本测试现钉两件事：
// 专用登记还在（识别/解析不退化）、门禁确实没了（谁把
// allowsSource 的拦截逻辑加回来，这批测试立刻红）。
//
// 全程按正式 App 的真实登记状态跑——新建空 LocalStore、
// 不往任何登记表里塞测试侧条目。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:moyi/detail_screen.dart';
import 'package:moyi/local_store.dart';
import 'package:moyi/models.dart';
import 'package:moyi/player_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

const _actressIds = ['javdb', 'av123', 'ph', 'av01', 'jable', 'pan115'];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<LocalStore> createStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    addTearDown(store.dispose);
    return store;
  }

  void viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('演员库专用登记（真实登记状态，不做测试侧登记）', () {
    test('6 个 id 被 isAvailable / isKnown / byId 认得', () {
      for (final id in _actressIds) {
        expect(SourceSite.isAvailable(id), isTrue, reason: id);
        expect(SourceSite.isKnown(id), isTrue, reason: id);
        // byId 不许回落红果（详情页顶栏站名靠它）。
        expect(SourceSite.byId(id).id, id, reason: id);
      }
    });

    test('allowsSource 对 6 个 id 与未注册 id 一律放行（门禁已删）', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      for (final id in _actressIds) {
        expect(store.allowsSource(id), isTrue, reason: id);
      }
      // 登记表语义保留：未注册 id 仍不算「可用/已知」；但门禁
      // 已删，allowsSource 不再据此拦截。
      expect(SourceSite.isAvailable('unregistered-random-id'), isFalse);
      expect(store.allowsSource('unregistered-random-id'), isTrue);
    });

    test('6 个 id 不进选站列表，网盘 cloud:pan115 不受牵连', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      final listed = store.sources.map((site) => site.id).toSet();
      for (final id in _actressIds) {
        expect(listed.contains(id), isFalse, reason: id);
      }
      // pan115（演员库 115 线）与 cloud:pan115（网盘站）是两个
      // id：专用登记只认前者，后者仍只由网盘登录态注册表决定。
      expect(SourceSite.actressOnlySites.containsKey('cloud:pan115'), isFalse);
      expect(SourceSite.cloudDriveSites.containsKey('pan115'), isFalse);
    });
  });

  group('详情页进页（门禁已删，正式状态）', () {
    for (final id in _actressIds) {
      testWidgets('source=$id 的作品进详情页出内容、不落没权限面板', (
        tester,
      ) async {
        viewport(tester);
        final store = await createStore();
        final drama = Drama(
          id: 'gate-$id',
          source: id,
          title: '门禁回归作品 $id',
          episodes: 2,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: DetailScreen(
              drama: drama,
              repository: FixtureRepository(),
              store: store,
            ),
          ),
        );
        await _settle(tester);
        expect(find.text('当前用户无权访问'), findsNothing);
        expect(find.text('门禁回归作品 $id'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('未注册随机 id 的作品进详情页照常出内容（门禁已删）', (
      tester,
    ) async {
      viewport(tester);
      final store = await createStore();
      const drama = Drama(
        id: 'gate-unknown',
        source: 'unregistered-random-id',
        title: '未注册来源作品',
        episodes: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DetailScreen(
            drama: drama,
            repository: FixtureRepository(),
            store: store,
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('当前用户无权访问'), findsNothing);
      expect(find.text('未注册来源作品'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('pan115 竞速赢家详情进页能起播（direct 直链集）', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      viewport(tester);
      final store = await createStore();
      // 与 actress_detail_page 里 115 线造 DramaDetail 的形状
      // 一字不差（只把地址换成回环，跳过真实网络预解析）。
      final detail = DramaDetail(
        const Drama(
          id: 'pan115:file-1',
          source: 'pan115',
          sourceId: 'file-1',
          title: '115 线作品',
          tags: ['TEST-001'],
        ),
        [
          Episode({
            'id': 'http://127.0.0.1:9/pan115/test.m3u8',
            'title': '正片',
            'direct': true,
            'headers': <String, String>{},
          }, 1),
        ],
      );
      final created = <ScriptedPlayer>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: DetailScreen(
            drama: detail.drama,
            repository: FixtureRepository(),
            store: store,
            initialDetail: detail,
            playerFactory: () {
              final platform = ScriptedPlayer();
              created.add(platform);
              return Player(platformPlayer: platform);
            },
            videoBuilder: (controls) => controls,
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('当前用户无权访问'), findsNothing);
      expect(find.byType(PlayerScreen), findsNothing);
      await tester.tap(find.byKey(const ValueKey('detail-poster-play')));
      await _settle(tester);
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.text('当前用户无权访问'), findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
