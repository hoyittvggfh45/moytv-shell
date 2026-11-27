import 'dart:convert';

import 'package:moyi/app_build.dart';
import 'package:moyi/core_bridge.dart';
import 'package:moyi/local_profiles.dart';
import 'package:moyi/local_store.dart';
import 'package:moyi/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('edition sources include DSD only in the all-source build', () async {
    // 2026-11-26 空壳片库定版（本项测试名保留原名以便与旧版对照）：
    // dsd（帝果）/huangdou 的 Dart 登记已随片库剥离删除，不再是
    // 已知站、不可用；当前站指向已剥离站时回落红果。
    // 注：本文件原断言按兄弟口味树（duanjushijie 口味）写成，
    // appSlug 在本树恒为 'moyi'，基线 efd0049 上这一条即因口味
    // define 差异失败；这里只断言与口味无关的剥离口径。
    SharedPreferences.setMockInitialValues({'source': 'huangdou'});
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(appSlug, 'moyi');
    expect(store.sources.length, 1);
    expect(SourceSite.values.any((source) => source.id == 'dsd'), isFalse);
    expect(SourceSite.values.any((source) => source.id == 'huangdou'), isFalse);
    expect(SourceSite.isAvailable('dsd'), isFalse);
    expect(SourceSite.isKnown('dsd'), isFalse);
    expect(SourceSite.isKnown('huangdou'), isFalse);
    // 源门禁已整体删除（2026-11-27 用户令）：allowsSource 不再查
    // 版本可用性，恒放行；isAvailable 的版本口径保留不动。
    expect(store.allowsSource('dsd'), isTrue);
    expect(store.source, 'hongguo');
    store.dispose();
  });


  test(
    'a restored foreign-source profile keeps its identity and permissions',
    () async {
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
            name: '已有用户',
            sources: ['huangdou'],
            download: false,
          ).toJson(),
        ]),
        'activeProfile': 'viewer',
        'profile.viewer.source': 'huangdou',
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      expect(store.profile.id, 'viewer');
      expect(store.profile.admin, isFalse);
      // 2026-11-26 空壳片库：来源名单里指向已剥离内置站（huangdou）
      // 的 id 在恢复时按未知 id 滤除（与「升级清旧内置登记」同一
      // 口径），用户其余数据不动。
      expect(store.profile.sources, isEmpty);
      // 门禁已删（2026-11-27 用户令）：canDownload 不再被
      // download:false 挡，allowsSource 对任何源恒放行。
      expect(store.canDownload, isTrue);
      // source 是「首页默认选中源」的展示回退（存量逻辑）：存的源
      // 不在可见列表时落第一个可见源，与访问门禁无关。
      expect(store.source, 'hongguo');
      expect(store.allowsSource('hongguo'), isTrue);
      expect(store.allowsSource('huangdou'), isTrue);
      store.dispose();
    },
  );

  test('restored DSD profile data follows edition availability', () async {
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
          name: '帝果旧用户',
          sources: ['dsd'],
          download: false,
        ).toJson(),
      ]),
      'activeProfile': 'viewer',
      'profile.viewer.source': 'dsd',
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(store.configurationError, isNull);
    // 2026-11-26 空壳片库：dsd 登记已剥离，旧档案里的 dsd 引用
    // 恢复时按未知 id 滤除，档案本身与其它设置不丢、不报错。
    expect(store.profile.sources, isEmpty);
    // 门禁已删（2026-11-27 用户令）：store.sources 不再按档案
    // sources 过滤，回到「全部已登记站源」；显示与否由 hiddenSites
    // 展示偏好决定，与档案数据脱钩。
    expect(
      store.sources.map((source) => source.id),
      SourceSite.values.map((source) => source.id),
    );
    expect(store.source, 'hongguo');
    expect(store.allowsSource('dsd'), isTrue);
    store.dispose();
  });

  test(
    'background requests no longer reject sources before native I/O',
    () async {
      // 源门禁已整体删除（2026-11-27 用户令）：后台请求不再在
      // Dart 侧按 source 准入预检抛错；请求照常下到本地核心，
      // 成败只由核心与数据本身决定（测试环境无核心，落到核心
      // 加载失败——只要不是门禁文案即可）。
      const gateMessages = {
        '当前版本不包含此站源',
        '当前用户没有此操作权限',
        '当前用户仅支持在线观看',
      };
      final repository = NativeRepository(background: true);
      final sources = [
        ...SourceSite.allValues
            .where((source) => !SourceSite.isAvailable(source.id))
            .map((source) => source.id),
        'unknown',
      ];
      for (final source in sources) {
        final drama = Drama(id: '$source:123', source: source, title: '合成数据');
        final episode = Episode({'id': '1'}, 1);
        for (final request in [
          () => repository.catalog(source),
          () => repository.cached(source),
          () => repository.sourceStatus(source),
          () => repository.startSourceJob(source, 'update'),
          () => repository.cancelSourceJob(source),
          () => repository.detail(drama),
          () => repository.cover(drama),
          () => repository.resolve(drama, episode),
          () => repository.resolveOnline(drama, episode),
          () => repository.enqueueDownloads(DramaDetail(drama, [episode]), [
            episode,
          ]),
          () => repository.localPlayback(drama, episode),
        ]) {
          await expectLater(
            request(),
            throwsA(
              predicate(
                (Object error) =>
                    error is! AppFailure ||
                    !gateMessages.contains(error.message),
                '不是门禁拦截错误',
              ),
            ),
          );
        }
      }
    },
  );
}
