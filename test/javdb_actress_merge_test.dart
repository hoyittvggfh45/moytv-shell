// 问题 2 回归（2026-11-27 phonefix2）：JavDB 女优与本地库
// 女优合并。此前 JavdbActorPage 只出 JavDB 自己的作品、本地
// 库同名女优的作品一条不带；本地女优页也不带 JavDB 作品。
//
// 钉三件事：
// 1. 按归一化名字（去空白 + 小写，与库内同名合并同一口径）
//    能把 JavDB 女优对到本地库女优（含别名、带空格变体），
//    子串相似的另一个人不误配；
// 2. JavDB 演员页作品合并：本地库作品在前、JavDB 作品按归一
//    番号去重补后（同番号只留本地库），部数只数实际合并到的；
// 3. 本地女优页反向合并：JavDB 搜到的作品里本地没有的番号补
//    进作品墙，同番号不重复出卡。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/actress/actress_av_style.dart';
import 'package:moyi/actress/actress_database.dart';
import 'package:moyi/actress/actress_detail_page.dart';
import 'package:moyi/actress/actress_models.dart';
import 'package:moyi/actress/javdb_actress_merge.dart';
import 'package:moyi/actress/javdb_api.dart';
import 'package:moyi/actress/javdb_view.dart';
import 'package:moyi/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

class _FakeJavdbClient extends JavdbApiClient {
  _FakeJavdbClient({this.movies = const [], this.searchResults = const []});

  final List<JavdbMovie> movies;
  final List<JavdbMovie> searchResults;

  @override
  Future<List<JavdbMovie>> actorMovies(String actorId, {int page = 1}) async =>
      movies;

  @override
  Future<List<JavdbMovie>> searchMovies(String keyword, {int page = 1}) async =>
      searchResults;
}

JavdbMovie _movie(String number, {String title = ''}) => JavdbMovie(
  id: 'id-$number',
  number: number,
  title: title.isEmpty ? '作品 $number' : title,
  releaseDate: '2024-01-01',
);

Future<ActressPerson> _seedPerson(
  MemoryActressDatabase db, {
  required String name,
  List<String> aliases = const [],
  required List<String> codes,
}) async {
  final person = (await db.upsertRosterPerson(
    RosterPerson(
      source: ActressRosterSourceId.chaoliu,
      sourceId: 'seed-$name',
      name: name,
      sex: 'female',
      aliases: aliases,
    ),
  ))!;
  await db.upsertWorks(person.localId, [
    for (final code in codes) RosterFilm(code: code, date: '2024-01-01'),
  ]);
  return (await db.personById(person.localId))!;
}

void main() {
  group('findLocalActressByName（归一化名字匹配）', () {
    test('原名、带空格变体、别名都能对上；子串相似不误配', () async {
      final db = MemoryActressDatabase();
      final target = await _seedPerson(
        db,
        name: '波多野結衣',
        aliases: ['波多野结衣'],
        codes: ['SAN-447'],
      );
      await _seedPerson(db, name: '結衣', codes: ['ABC-001']);
      await _seedPerson(db, name: '波多野美衣', codes: ['ABC-002']);

      expect(
        (await findLocalActressByName(db, '波多野結衣'))?.localId,
        target.localId,
      );
      expect(
        (await findLocalActressByName(db, '波多野 結衣'))?.localId,
        target.localId,
      );
      expect(
        (await findLocalActressByName(db, '波多野结衣'))?.localId,
        target.localId,
      );
      expect(await findLocalActressByName(db, '不存在的人'), isNull);
    });
  });

  group('javdbMoviesNotInLocal（归一番号去重）', () {
    test('同番号（大小写/连字符差异）剔除、无番号保留、新番号保留', () {
      final movies = [
        _movie('SAN-447'),
        _movie('ssis-001'),
        _movie('OFJE-712'),
        _movie(''),
      ];
      final kept = javdbMoviesNotInLocal(movies, ['san-447', 'SSIS001']);
      expect(kept.map((m) => m.number), ['OFJE-712', '']);
    });
  });

  group('JavdbActorPage 合并', () {
    testWidgets('本地作品在前 + JavDB 去重补后，部数按实际合并数', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = MemoryActressDatabase();
      await _seedPerson(
        db,
        name: '波多野結衣',
        codes: ['SAN-447', 'SAME-711'],
      );
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      final client = _FakeJavdbClient(
        movies: [_movie('SAN-447'), _movie('OFJE-712')],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: JavdbActorPage(
            actor: const JavdbActor(id: 'a1', name: '波多野結衣'),
            client: client,
            repository: FixtureRepository(),
            store: store,
            database: db,
          ),
        ),
      );
      // 合并是两段异步（作品先回、本地合并后到）：有界轮询等
      // 合并计数行出现。
      var merged = false;
      for (var i = 0; i < 40 && !merged; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        merged =
            find
                .text('本地库 2 部 · JavDB 1 部')
                .evaluate()
                .isNotEmpty;
      }
      expect(merged, isTrue, reason: '页头应显示合并后的实际部数');
      // 本地库 2 部出 AvWorkCard（带「本地库」标）；JavDB 的
      // SAN-447 与本地同番号被去重（其标题「作品 SAN-447」
      // 不出现），独有的 OFJE-712 补在后面。
      expect(find.byType(AvWorkCard), findsNWidgets(2));
      expect(find.text('作品 SAN-447'), findsNothing);
      expect(find.text('OFJE-712'), findsOneWidget);
      expect(find.text('本地库'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('本地库没有同名女优时保持纯 JavDB 列表', (tester) async {
      final db = MemoryActressDatabase();
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      final client = _FakeJavdbClient(movies: [_movie('OFJE-712')]);
      await tester.pumpWidget(
        MaterialApp(
          home: JavdbActorPage(
            actor: const JavdbActor(id: 'a9', name: '本地没有的人'),
            client: client,
            repository: FixtureRepository(),
            store: store,
            database: db,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 部影片'), findsOneWidget);
      expect(find.text('OFJE-712'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('ActressDetailPage 反向合并', () {
    testWidgets('JavDB 独有番号补进作品墙，同番号不重复', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = MemoryActressDatabase();
      final person = await _seedPerson(
        db,
        name: '波多野結衣',
        codes: ['SAN-447'],
      );
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      final client = _FakeJavdbClient(
        searchResults: [_movie('SAN-447'), _movie('OFJE-712')],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ActressDetailPage(
            localId: person.localId,
            repository: FixtureRepository(),
            store: store,
            database: db,
            javdbClient: client,
          ),
        ),
      );
      var supplemented = false;
      for (var i = 0; i < 60 && !supplemented; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        supplemented = find.text('OFJE-712').evaluate().isNotEmpty;
      }
      expect(supplemented, isTrue, reason: 'JavDB 独有番号应补进作品墙');
      // 作品墙共 2 张卡：本地 SAN-447 + JavDB 补的 OFJE-712；
      // JavDB 结果里的 SAN-447（标题「作品 SAN-447」）同番号
      // 被去重、不重复出卡。
      expect(find.byType(AvWorkCard), findsNWidgets(2));
      expect(find.text('作品 SAN-447'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
