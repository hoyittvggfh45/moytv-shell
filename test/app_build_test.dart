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
    expect(SourceSite.values.any((source) => source.id == 'dsd'), isFalse);
    expect(SourceSite.values.any((source) => source.id == 'huangdou'), isFalse);
    expect(SourceSite.isAvailable('dsd'), isFalse);
    expect(SourceSite.isKnown('dsd'), isFalse);
    expect(SourceSite.isKnown('huangdou'), isFalse);
    expect(store.allowsSource('dsd'), isFalse);
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
      // 2026-11-26 空壳片库：档案身份/权限位原样保留；来源名单里
      // 指向已剥离内置站（huangdou）的 id 在恢复时按未知 id 滤除
      // （与「升级清旧内置登记」同一口径），用户其余数据不动。
      expect(store.profile.sources, isEmpty);
      expect(store.canDownload, isFalse);
      expect(store.source, '');
      expect(store.allowsSource('hongguo'), isFalse);
      expect(store.allowsSource('huangdou'), isFalse);
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
    expect(store.sources.map((source) => source.id), isEmpty);
    expect(store.source, '');
    expect(store.allowsSource('dsd'), isFalse);
    store.dispose();
  });

  test(
    'background requests reject unavailable sources before native I/O',
    () async {
      final repository = NativeRepository(background: true);
      final denied = [
        ...SourceSite.allValues
            .where((source) => !SourceSite.isAvailable(source.id))
            .map((source) => source.id),
        'unknown',
      ];
      for (final source in denied) {
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
              isA<AppFailure>().having(
                (error) => error.message,
                'message',
                '当前版本不包含此站源',
              ),
            ),
          );
        }
      }
    },
  );
}
