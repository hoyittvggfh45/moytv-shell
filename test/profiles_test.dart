import 'dart:convert';

import 'package:moyi/core_bridge.dart';
import 'package:moyi/local_profiles.dart';
import 'package:moyi/local_store.dart';
import 'package:moyi/main.dart';
import 'package:moyi/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const drama = Drama(id: 'hongguo:1', source: 'hongguo', title: '合成短剧');
  const denied = Drama(id: 'huangdou:2', source: 'huangdou', title: '受限合成短剧');



  // 门禁删除后口径（2026-11-27 phonefix2，用户令「把门禁全
  // 删除」）：档案的 sources/download 不再拦原生取数——
  // supportsDownloads 恒真，各入口不再抛权限类 AppFailure；
  // 它们会直达原生桥（测试环境里死在桥缺失等非门禁错误上，
  // 或正常返回），断言只钉「错误文案里没有门禁字样」。
  // 旧名「native entry points reject denied sources and
  // downloads before native I/O」，断言已反转。
  test(
    'native entry points no longer gate on profile sources or download flag',
    () async {
      SharedPreferences.setMockInitialValues({
        'profiles': jsonEncode([
          const LocalProfile(
            id: 'default',
            name: '管理员',
            admin: true,
            salt: '11111111111111111111111111111111',
            pinHash:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ).toJson(),
          const LocalProfile(
            id: 'viewer',
            name: '只看红果',
            sources: ['hongguo'],
            download: false,
          ).toJson(),
        ]),
        'activeProfile': 'viewer',
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = NativeRepository()..access = store;
      expect(repository.supportsDownloads, isTrue);
      for (final request in [
        () => repository.catalog('huangdou'),
        () => repository.cached('huangdou'),
        () => repository.detail(denied),
        () => repository.cover(denied),
        () => repository.resolve(denied, Episode({'id': '1'}, 1)),
        () => repository.enqueueDownloads(DramaDetail(drama, []), [
          Episode({'id': '1'}, 1),
        ]),
        () => repository.localPlayback(drama, Episode({'id': '1'}, 1)),
      ]) {
        Object? error;
        try {
          await request();
        } catch (e) {
          error = e;
        }
        if (error is AppFailure) {
          expect(error.message, isNot(contains('权限')));
          expect(error.message, isNot(contains('版本不包含')));
          expect(error.message, isNot(contains('仅支持在线观看')));
        }
      }
      store.dispose();
    },
  );

  // 门禁删除后口径（2026-11-27 phonefix2）：档案 download=false
  // 不再藏下载导航、sources 名单不再过滤首页源列表——只看红果
  // 的档案照样看得到下载入口与黄豆。旧名「online-only home
  // hides download navigation and denied sources」，断言已反转。
  testWidgets('home no longer hides downloads or sources for limited profile', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profiles': jsonEncode([
        const LocalProfile(
          id: 'default',
          name: '管理员',
          admin: true,
          salt: '11111111111111111111111111111111',
          pinHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ).toJson(),
        const LocalProfile(
          id: 'viewer',
          name: '只看红果',
          sources: ['hongguo'],
          download: false,
        ).toJson(),
      ]),
      'activeProfile': 'viewer',
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    // 店级口径（判定本体所在层）：下载不再被 download=false
    // 挡、源准入不再按档案 sources 名单判——黄豆在本测试的
    // 版本变体里本来就不在可用表（isAvailable 版本口径保留），
    // 钉的是 allowsSource 对它恒放行、canDownload 恒真。
    expect(store.canDownload, isTrue);
    expect(store.allowsSource('huangdou'), isTrue);
    expect(store.sources.map((s) => s.id), contains('hongguo'));
    await tester.pumpWidget(
      MoyiApp(repository: FixtureRepository(), store: store),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 放行后首页会起周期任务，拆树前先把假时间推过去冲掉
    // 待触发的定时器，否则 teardown 的 timersPending 断言拦。
    await tester.pump(const Duration(minutes: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 10));
    store.dispose();
  });
}
