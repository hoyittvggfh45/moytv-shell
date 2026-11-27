// 问题 1 回归（2026-11-27 phonefix2，用户令「把门禁全删除」）：
// 用户实测 san-447（《因为丈夫超早泄而积攒起欲求不满，最终对
// 公公的毒蘑菇下手的人妻 波多野结衣》）点开落「当前用户无权
// 访问」面板、列表页弹「这条暂时取不到播放地址」。定版库里
// san-447 有两条线路：videos 主行 whos.tv 的 v.hersav.me 直链
// （实测 200 活线）＋ video_play_urls 里 mjv011 的
// streamfastpro 直链（实测 404 死线）。
//
// 本文件钉三件事：
// 1. 门禁删除后，本地库作品（source='chaoliu' 的 whos/mjv 作品
//    与 source='lsp' 的作品）在「无任何站点运行时登记 + 非管理员
//    档案且档案 sources 为空」的状态下，allowsSource 照样放行
//    ——本地库播放不再依赖任何可开关站点的注册/可见性/档案。
// 2. san-447 双线全链：死线（mjv011）排在池子第一条时，详情页
//    照常打开（不落无权访问面板）；换线链（nextLineOnExhausted）
//    能落到 whos 活线——死线排前面不拖死整部作品。
// 3. 详情页里 san-447 的标题正常出现（不是空面板）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/actress/actress_av_style.dart';
import 'package:moyi/actress/actress_database.dart';
import 'package:moyi/actress/actress_detail_page.dart';
import 'package:moyi/actress/actress_film_library.dart';
import 'package:moyi/actress/actress_json_fallback.dart';
import 'package:moyi/actress/actress_models.dart';
import 'package:moyi/detail_screen.dart';
import 'package:moyi/feed_playability.dart';
import 'package:moyi/local_profiles.dart';
import 'package:moyi/local_store.dart';
import 'package:moyi/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

const _deadUrl =
    'https://cdnfc.streamfastpro.com/ebd240206657a20856f1127f6a0491bf/30/1/rhM8ozQDgBsKL4MroNG0RA/rhM8ozQDgBsKL4MroNG0RA.m3u8';
const _liveUrl =
    'https://v.hersav.me/d5d8e9d1bcc5f3eb69ee8ffa59152c64/d5d8e9d1bcc5f3eb69ee8ffa59152c64.m3u8';
const _sanTitle = '因为丈夫超早泄而积攒起欲求不满，最终对公公的毒蘑菇下手的人妻 波多野结衣';

class _SanRepository extends FixtureRepository {
  final detailsById = <String, DramaDetail>{};

  @override
  Future<DramaDetail> detail(Drama drama) async =>
      detailsById[drama.id] ?? super.detail(drama);

  @override
  Future<PlaybackPlan> resolve(
    Drama drama,
    Episode episode, {
    bool adBlock = true,
    int quality = 0,
    int route = 0,
  }) async {
    // 本地库条目的集 id 本身就是直链（direct 口径）：原样回。
    final id = episode.id;
    return PlaybackPlan(
      url: id.startsWith('http') ? id : 'https://example.test/synthetic.mp4',
    );
  }

  @override
  Future<String> cover(Drama drama, {bool force = false}) async => '';
}

class _FakeFilmDb implements FilmDbFallbackProvider {
  _FakeFilmDb(this.rowsByCode);

  final Map<String, List<ActressJsonEntry>> rowsByCode;

  @override
  Future<List<ActressJsonEntry>> entriesForActress(
    String name, {
    String? site,
  }) async => const [];

  @override
  Future<List<ActressJsonEntry>> entriesForCode(
    String codeKey, {
    String? site,
  }) async => rowsByCode[codeKey] ?? const [];
}

ActressJsonEntry _sanEntry({required String site, required String playUrl}) =>
    ActressJsonEntry(
      site: site,
      vodId: 'san-447',
      vodName: _sanTitle,
      vodPic: '',
      vodActor: '波多野结衣',
      vodDirector: '',
      vodRemarks: '',
      vodPubdate: '',
      vodArea: '',
      vodYear: '',
      vodContent: '',
      vodPlayFrom: site == 'mjv' ? 'mjv011' : 'whos.tv',
      vodPlayUrl: '正片\$$playUrl',
      typeName: '',
      vodCode: 'SAN-447',
      vodActressPic: '',
    );

/// 死线 404、活线 200＋真播放列表头。
Future<FeedProbeResponse> _probe(
  String url,
  Map<String, String> headers,
  Duration timeout,
) async {
  if (url.contains('streamfastpro')) {
    return const FeedProbeResponse(statusCode: 404, headers: {}, headBytes: []);
  }
  return FeedProbeResponse(
    statusCode: 200,
    headers: const {'content-type': 'application/vnd.apple.mpegurl'},
    headBytes: '#EXTM3U\n#EXT-X-VERSION:3\n'.codeUnits,
  );
}

void main() {
  group('门禁删除后本地库 source 与档案/登记彻底脱钩', () {
    test('非管理员空档案 + 零登记：chaoliu / lsp 一律放行', () async {
      SharedPreferences.setMockInitialValues({
        'profiles': jsonEncode([
          LocalProfile(
            id: 'default',
            name: '管理员',
            admin: true,
            salt: '0' * 32,
            pinHash: '1' * 64,
          ).toJson(),
          const LocalProfile(id: 'viewer', name: '普通用户').toJson(),
        ]),
        'activeProfile': 'viewer',
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      expect(store.profile.admin, isFalse);
      expect(store.profile.sources, isEmpty);
      // 测试进程里没有任何运行时登记（importedSites 为空）：
      // 这正是空壳版/登记未就绪时的状态，旧门禁在此恒拦。
      expect(SourceSite.importedSites.containsKey('chaoliu'), isFalse);
      expect(store.allowsSource('chaoliu'), isTrue);
      expect(store.allowsSource('lsp'), isTrue);
      expect(store.allowsSource('whos'), isTrue);
      expect(store.allowsSource('mjv'), isTrue);
      expect(store.canDownload, isTrue);
    });

    test('本地库条目转出的 Drama.source 与放行（whos 主行 + lsp）', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      const whosEntry = FilmLibraryEntry(
        vodId: 'san-447',
        title: _sanTitle,
        coverUrl: '',
        playUrl: _liveUrl,
        actress: '波多野结衣',
        code: 'SAN-447',
        category: '',
        site: 'whos.tv',
        date: '',
        remarks: '',
        typeName: '',
        content: '',
      );
      final whosDetail = whosEntry.toDramaDetail();
      expect(whosDetail.drama.source, 'chaoliu');
      expect(whosDetail.episodes.first.id, _liveUrl);
      expect(store.allowsSource(whosDetail.drama.source), isTrue);

      const lspEntry = FilmLibraryEntry(
        vodId: 'same-711',
        title: 'SAME-711 本地库作品',
        coverUrl: '',
        playUrl: 'https://example.com/lsp/same-711.m3u8',
        actress: '',
        code: 'SAME-711',
        category: '',
        site: 'lsp',
        date: '',
        remarks: '',
        typeName: '',
        content: '',
      );
      final lspDetail = lspEntry.toDramaDetail();
      expect(lspDetail.drama.source, 'lsp');
      expect(store.allowsSource(lspDetail.drama.source), isTrue);
    });
  });

  group('san-447 双线全链（死线在前不拖死整部作品）', () {
    late MemoryActressDatabase db;
    late _SanRepository repository;
    late LocalStore store;

    setUp(() async {
      db = MemoryActressDatabase();
      repository = _SanRepository();
      SharedPreferences.setMockInitialValues({});
      store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      // MissAV 竞速腿回空详情，不抢戏（同 dbplay_restore 口径）。
      repository.detailsById['SAN447'] = DramaDetail(
        Drama(id: 'SAN447', source: 'missav', title: 'SAN-447'),
        const [],
      );
    });

    void suppressKnownListTileAssertion() {
      final original = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        if (details.toString().contains(
          'ListTile background color or ink splashes',
        )) {
          return;
        }
        original?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = original;
      });
    }

    Future<bool> pumpUntilDetail(
      WidgetTester tester, {
      int rounds = 30,
    }) async {
      for (var i = 0; i < rounds; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(DetailScreen).evaluate().isNotEmpty) return true;
      }
      return false;
    }

    testWidgets('死线排第一条：详情页照常打开，换线能落到 whos 活线', (tester) async {
      suppressKnownListTileAssertion();
      final person = (await db.upsertRosterPerson(
        const RosterPerson(
          source: ActressRosterSourceId.chaoliu,
          sourceId: 'X1',
          name: '波多野结衣',
          sex: 'female',
        ),
      ))!;
      await db.upsertWorks(person.localId, const [
        RosterFilm(code: 'SAN-447', date: '2024-01-01'),
      ]);
      final seeded = (await db.personById(person.localId))!;
      await tester.pumpWidget(
        MaterialApp(
          home: ActressDetailPage(
            localId: seeded.localId,
            repository: repository,
            store: store,
            database: db,
            filmDb: _FakeFilmDb({
              'SAN447': [
                // 池子顺序：mjv011 死线在前、whos 活线在后
                // （与定版库 san-447 的双线实况一致）。
                _sanEntry(site: 'mjv', playUrl: _deadUrl),
                _sanEntry(site: 'whos', playUrl: _liveUrl),
              ],
            }),
            verifyFetch: _probe,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AvWorkCard).first);
      final opened = await pumpUntilDetail(tester);
      expect(opened, isTrue, reason: '详情页应打开');
      expect(find.text('当前用户无权访问'), findsNothing);
      expect(find.text(_sanTitle), findsWidgets);

      final screen = tester.widget<DetailScreen>(find.byType(DetailScreen));
      // 首播按秒开口径用库里第一条（死线）直开——这本身不是错，
      // 错的是死线把整部作品拖死：换线链必须能给出活线。
      expect(screen.initialDetail?.episodes.first.id, _deadUrl);
      expect(screen.nextLineOnExhausted, isNotNull);

      // 推进竞速收尾（在线腿超时等在假时间里放干），再要下一条。
      DetailNextLine? next;
      var done = false;
      unawaited(() async {
        next = await screen.nextLineOnExhausted!();
        done = true;
      }());
      for (var i = 0; i < 120 && !done; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(done, isTrue, reason: '换线链应给出下一条');
      expect(next, isNotNull, reason: '死线在前时换线链不得耗尽');
      expect(next!.detail.episodes.first.id, _liveUrl);
      expect(next!.detail.drama.source, 'chaoliu');

      // 收尾放干剩余计时器。
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
    });
  });
}
