// 磁力分类库（2026-11-27 用户令）测试：
// ① 并存导入语义（内存假存储镜像 sqflite 实现的登记表口径）：
//    主库作品行数不变、只新增；同番号作品只加磁力线路不覆盖；
//    删库后独有作品消失、共享作品留且磁力线路被摘；两库共享
//    的作品删一库不丢；同名重导是更新不是叠加。
// ② 控制器：先验后并（坏 .sql 在导入器那步就拦下、存储没被
//    碰）；非磁力文件被拒；没女优库时先拦。
// ③ 磁力点播链与三态（假 115 网关）：未登入引导、网盘有片
//    直接播、在离线中不重复提交、无片自动提交逐条试一条成
//    功即止、已提交过不重复交、全失败给中文原因。
// ④ 管理页：磁力分类库区能导入、已导入库有行、删库走完
//    消失；影视库详情页磁力作品多一条「磁力 · 115 网盘」行。
// 真 sqlite 层（sqflite 实现本身）与真 115 提交/真播要装机
// 验，本文件只验语义与接线（与本仓其它存储测试同口径）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/actress/actress_database.dart';
import 'package:moyi/actress/actress_db_info.dart';
import 'package:moyi/actress/actress_db_manage_page.dart';
import 'package:moyi/actress/actress_film_library.dart';
import 'package:moyi/actress/actress_magnet_library.dart';
import 'package:moyi/actress/actress_magnet_play.dart';
import 'package:moyi/actress/actress_sql_import.dart';
import 'package:moyi/actress/actress_sql_import_controller.dart';
import 'package:moyi/cloud_drive/cloud_115_offline.dart';
import 'package:moyi/cloud_drive/cloud_drive_types.dart';
import 'package:moyi/cloud_drive/cloud_providers.dart'
    show CloudDirectLink;
import 'package:moyi/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

const _magnet1 = 'magnet:?xt=urn:btih:AAAA1111&dn=one';
const _magnet2 = 'magnet:?xt=urn:btih:BBBB2222&dn=two';
const _magnet3 = 'magnet:?xt=urn:btih:CCCC3333&dn=three';

// ---------------------------------------------------------------------------
// 假磁力存储：内存模型镜像 SqfliteMagnetLibraryStore 的来源
// 登记语义（was_existing 登记 + INSERT OR IGNORE 并入 +
// 删库按登记反向摘）。
// ---------------------------------------------------------------------------
class FakeStagingDb {
  FakeStagingDb({
    required this.works,
    required this.urls,
    this.actresses = const {},
    this.category = '',
    this.workCategories = const {},
  });

  final Set<String> works;
  final Map<String, List<String>> urls;
  final Set<String> actresses;

  /// 全库统一分类（逐片登记时每部作品都归这一类）。
  final String category;

  /// 逐部作品的分类（合集文件用，优先于 [category]）。
  final Map<String, String> workCategories;

  String categoryOf(String vodId) => workCategories[vodId] ?? category;
}

class FakeMagnetStore implements MagnetLibraryStore {
  final videos = <String>{};
  final playUrls = <String>{}; // 'vodId|url'
  final actresses = <String>{};
  final categories = <String, String>{}; // vodId -> main_category
  final stagingDbs = <String, FakeStagingDb>{};
  final _libraries = <MagnetLibraryRecord>[];
  final _worksProv = <int, Map<String, bool>>{};
  final _urlsProv = <int, Map<String, bool>>{};
  final _actressProv = <int, Map<String, bool>>{};
  final _categoryProv = <int, Map<String, (String, bool)>>{};
  var _nextId = 1;
  var closeCalls = 0;

  @override
  Future<List<MagnetLibraryRecord>> listLibraries() async => [
    ..._libraries,
  ];

  @override
  Future<MagnetMergeResult> mergeFromStaging({
    required String stagingPath,
    required String name,
    required String sourceName,
  }) async {
    final staging = stagingDbs[stagingPath];
    if (staging == null) {
      return const MagnetMergeResult(ok: false, error: '临时库不存在');
    }
    final hasMagnet = staging.urls.values
        .expand((urls) => urls)
        .any(actressIsMagnetPlayUrl);
    if (!hasMagnet) {
      return const MagnetMergeResult(
        ok: false,
        error: '这个文件里没有磁力链接，不是磁力分类库',
      );
    }
    // 按分类切片逐片登记（合集文件多片、一类一文件单片），
    // 与 sqflite 实现同口径：没分类的作品归文件名兜底片。
    final sliceWorks = <String, List<String>>{};
    for (final vodId in staging.works) {
      final slice = staging.categoryOf(vodId);
      sliceWorks
          .putIfAbsent(slice.isEmpty ? name : slice, () => [])
          .add(vodId);
    }
    var replaced = false;
    var addedWorks = 0;
    var addedUrls = 0;
    var totalWorks = 0;
    var firstId = 0;
    for (final slice in sliceWorks.keys) {
      final existing = _libraries.where((l) => l.name == slice).toList();
      if (existing.isNotEmpty) {
        await removeLibrary(existing.first.id);
        replaced = true;
      }
      final id = _nextId++;
      if (firstId == 0) firstId = id;
      final worksProv = <String, bool>{};
      for (final vodId in sliceWorks[slice]!) {
        final was = videos.contains(vodId);
        worksProv[vodId] = was;
        if (!was) {
          videos.add(vodId);
          addedWorks++;
        }
      }
      totalWorks += worksProv.length;
      final urlsProv = <String, bool>{};
      for (final vodId in sliceWorks[slice]!) {
        for (final url in staging.urls[vodId] ?? const <String>[]) {
          final key = '$vodId|$url';
          final was = playUrls.contains(key);
          urlsProv[key] = was;
          if (!was) {
            playUrls.add(key);
            addedUrls++;
          }
        }
      }
      final actressProv = <String, bool>{};
      for (final cateId in staging.actresses) {
        final was = actresses.contains(cateId);
        actressProv[cateId] = was;
        if (!was) actresses.add(cateId);
      }
      final categoryProv = <String, (String, bool)>{};
      for (final vodId in sliceWorks[slice]!) {
        final effective = staging.categoryOf(vodId);
        if (effective.isEmpty) continue;
        final was = categories.containsKey(vodId);
        categoryProv[vodId] = (effective, was);
        if (!was) categories[vodId] = effective;
      }
      _worksProv[id] = worksProv;
      _urlsProv[id] = urlsProv;
      _actressProv[id] = actressProv;
      _categoryProv[id] = categoryProv;
      _libraries.insert(
        0,
        MagnetLibraryRecord(
          id: id,
          name: slice,
          category: slice,
          sourceName: sourceName,
          importedAtMillis: 1,
          works: worksProv.length,
          playUrls: urlsProv.length,
        ),
      );
    }
    final slices = sliceWorks.keys.toList();
    return MagnetMergeResult(
      ok: true,
      libraryId: firstId,
      name: name,
      category: slices.length == 1 ? slices.single : '',
      categories: slices,
      addedWorks: addedWorks,
      totalWorks: totalWorks,
      addedPlayUrls: addedUrls,
      replaced: replaced,
    );
  }

  @override
  Future<MagnetRemoveResult> removeLibrary(int libraryId) async {
    final index = _libraries.indexWhere((l) => l.id == libraryId);
    if (index < 0) {
      return const MagnetRemoveResult(removedWorks: 0, removedPlayUrls: 0);
    }
    _libraries.removeAt(index);
    final worksProv = _worksProv.remove(libraryId) ?? const {};
    final urlsProv = _urlsProv.remove(libraryId) ?? const {};
    _actressProv.remove(libraryId);
    final categoryProv = _categoryProv.remove(libraryId) ?? const {};
    final otherWorks = <String>{
      for (final map in _worksProv.values) ...map.keys,
    };
    final otherUrls = <String>{
      for (final map in _urlsProv.values) ...map.keys,
    };
    final otherCategories = <String>{
      for (final map in _categoryProv.values)
        for (final entry in map.entries) '${entry.key}|${entry.value.$1}',
    };
    var removedWorks = 0;
    var removedUrls = 0;
    final doomed = <String>{};
    for (final entry in worksProv.entries) {
      if (entry.value || otherWorks.contains(entry.key)) continue;
      doomed.add(entry.key);
      videos.remove(entry.key);
      categories.remove(entry.key);
      removedWorks++;
      final before = playUrls.length;
      playUrls.removeWhere((key) => key.startsWith('${entry.key}|'));
      removedUrls += before - playUrls.length;
    }
    // 幸存作品上本库贡献的分类行摘掉（与 sqflite 实现同口径）。
    for (final entry in categoryProv.entries) {
      final (category, was) = entry.value;
      if (was || doomed.contains(entry.key)) continue;
      if (otherCategories.contains('${entry.key}|$category')) continue;
      if (categories[entry.key] == category) {
        categories.remove(entry.key);
      }
    }
    for (final entry in urlsProv.entries) {
      if (entry.value || otherUrls.contains(entry.key)) continue;
      final vodId = entry.key.split('|').first;
      if (!videos.contains(vodId)) continue;
      if (playUrls.remove(entry.key)) removedUrls++;
    }
    return MagnetRemoveResult(
      removedWorks: removedWorks,
      removedPlayUrls: removedUrls,
    );
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

// ---------------------------------------------------------------------------
// 假导入器：只回结果，不落真库（控制器磁力路只看 ok/失败）。
// ---------------------------------------------------------------------------
class FakeMagnetImporter extends ActressSqlImporter {
  FakeMagnetImporter({this.result});

  final ActressSqlImportResult? result;
  var calls = 0;

  @override
  Future<ActressSqlImportResult> importFile({
    required String sqlPath,
    required String dbPath,
    required Future<void> Function() closeDatabase,
    void Function(ActressSqlImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    calls++;
    return result ??
        const ActressSqlImportResult(
          ok: true,
          videos: 2,
          actresses: 0,
          playUrls: 3,
          covers: 0,
          avatars: 0,
        );
  }
}

// ---------------------------------------------------------------------------
// 假 115 网关。
// ---------------------------------------------------------------------------
class FakePan115Gateway implements Pan115Gateway {
  FakePan115Gateway({this.loggedIn = true});

  bool loggedIn;
  CloudDriveFile? file;
  List<Pan115OfflineTask> tasks = const [];
  final submitted = <String>{};
  final submitCalls = <String>[];
  final recorded = <String>[];
  final failUrls = <String>{};

  @override
  Future<bool> isLoggedIn() async => loggedIn;

  @override
  Future<CloudDriveFile?> findFileByCode(String code) async => file;

  @override
  Future<CloudDirectLink?> directLink(CloudDriveFile file) async =>
      const CloudDirectLink(
        url: 'https://cdn.example.com/115.mp4',
        headers: {'User-Agent': 'fake'},
      );

  @override
  Future<List<Pan115OfflineTask>> listOfflineTasks() async => tasks;

  @override
  Future<bool> submitOffline(String url) async {
    submitCalls.add(url);
    return !failUrls.contains(url);
  }

  @override
  Future<Set<String>> submittedHashes() async => {...submitted};

  @override
  Future<void> recordSubmitted(String hash) async {
    recorded.add(hash);
    submitted.add(hash);
  }
}

void main() {
  group('磁力判定与库名', () {
    test('地址尺与标记尺任一命中都算磁力线路', () {
      expect(actressIsMagnetPlayUrl('magnet:?xt=urn:btih:X'), isTrue);
      expect(actressIsMagnetPlayUrl(' MAGNET:?xt=1 '), isTrue);
      expect(actressIsMagnetPlayUrl('https://x/1.m3u8'), isFalse);
      expect(
        const ActressPlayLine(url: 'https://x', from: 'magnet').isMagnet,
        isTrue,
      );
      expect(
        const ActressPlayLine(url: _magnet1, from: 'whos').isMagnet,
        isTrue,
      );
      expect(
        const ActressPlayLine(url: 'https://x', from: 'whos').isMagnet,
        isFalse,
      );
    });

    test('库名＝文件名去后缀', () {
      expect(magnetLibraryNameOfFile('/a/b/4K原版.sql'), '4K原版');
      expect(magnetLibraryNameOfFile('国产原创.sql.gz'), '国产原创');
      expect(magnetLibraryNameOfFile('VR视频区.sql'), 'VR视频区');
    });
  });

  group('并存导入语义（假存储）', () {
    FakeMagnetStore storeWithMain() {
      final store = FakeMagnetStore();
      store.videos.addAll(['ssis-001', 'abc-002']);
      store.playUrls.add('ssis-001|https://x/1.m3u8');
      store.actresses.add('a1');
      // ssis-001 在主库有分类行、abc-002 没有（验分类行来源
      // 登记：并入时 abc-002 吃进磁力库分类、删库时要摘掉）。
      store.categories['ssis-001'] = '有码';
      store.stagingDbs['stage4k'] = FakeStagingDb(
        works: {'ssis-001', 'abc-002', 'ipz-999'},
        urls: {
          'ssis-001': [_magnet1],
          'abc-002': [_magnet3],
          'ipz-999': [_magnet2, _magnet3],
        },
        actresses: {'a1', 'a2'},
        category: '4K原版',
      );
      return store;
    }

    test('并入：主库行数只增不减、共享作品加线路不覆盖', () async {
      final store = storeWithMain();
      final result = await store.mergeFromStaging(
        stagingPath: 'stage4k',
        name: '4K原版',
        sourceName: '4K原版.sql',
      );
      expect(result.ok, isTrue, reason: result.error);
      expect(result.addedWorks, 1);
      expect(result.totalWorks, 3);
      expect(result.category, '4K原版');
      // 主库原有 2 部都在，只多了 ipz-999。
      expect(store.videos, {'ssis-001', 'abc-002', 'ipz-999'});
      // 共享作品：原 http 线路还在，磁力线路加上了。
      expect(store.playUrls, contains('ssis-001|https://x/1.m3u8'));
      expect(store.playUrls, contains('ssis-001|$_magnet1'));
      expect(store.playUrls, contains('ipz-999|$_magnet2'));
      expect(store.playUrls, contains('ipz-999|$_magnet3'));
      // 分类动态出现。
      final libraries = await store.listLibraries();
      expect(libraries.map((l) => l.category), ['4K原版']);
      // 分类行：主库已有的以主库为准（ssis-001 仍是有码），
      // 主库没有的吃进本库分类（abc-002 变 4K原版那一行）。
      expect(store.categories['ssis-001'], '有码');
      expect(store.categories['abc-002'], '4K原版');
    });

    test('删库：独有作品消失、共享作品留且磁力线路被摘、分类消失', () async {
      final store = storeWithMain();
      final merged = await store.mergeFromStaging(
        stagingPath: 'stage4k',
        name: '4K原版',
        sourceName: '4K原版.sql',
      );
      final removed = await store.removeLibrary(merged.libraryId);
      expect(removed.removedWorks, 1);
      expect(store.videos, {'ssis-001', 'abc-002'});
      expect(store.playUrls, {'ssis-001|https://x/1.m3u8'});
      expect(await store.listLibraries(), isEmpty);
      // 分类行精确还原：abc-002 吃进的 4K原版行被摘掉，
      // 「4K原版」分类在库里一条不剩（分类随删库消失）。
      expect(store.categories, {'ssis-001': '有码'});
    });

    test('两库共享同一作品：删一库作品不丢、只摘它贡献的线路', () async {
      final store = storeWithMain();
      final a = await store.mergeFromStaging(
        stagingPath: 'stage4k',
        name: '4K原版',
        sourceName: '4K原版.sql',
      );
      store.stagingDbs['stageB'] = FakeStagingDb(
        works: {'ipz-999'},
        urls: {
          'ipz-999': [_magnet2],
        },
        category: '高清中字字幕',
      );
      await store.mergeFromStaging(
        stagingPath: 'stageB',
        name: '高清中字字幕',
        sourceName: '高清中字字幕.sql',
      );
      await store.removeLibrary(a.libraryId);
      // ipz-999 被 B 库也带了：作品与 magnet2 都留；只摘 A 独有的 magnet3。
      expect(store.videos, contains('ipz-999'));
      expect(store.playUrls, contains('ipz-999|$_magnet2'));
      expect(store.playUrls, isNot(contains('ipz-999|$_magnet3')));
      expect(
        (await store.listLibraries()).map((l) => l.category),
        ['高清中字字幕'],
      );
    });

    test('同名重导是更新：不叠加、计数稳定', () async {
      final store = storeWithMain();
      await store.mergeFromStaging(
        stagingPath: 'stage4k',
        name: '4K原版',
        sourceName: '4K原版.sql',
      );
      final again = await store.mergeFromStaging(
        stagingPath: 'stage4k',
        name: '4K原版',
        sourceName: '4K原版.sql',
      );
      expect(again.replaced, isTrue);
      expect(again.addedWorks, 1);
      expect(store.videos, {'ssis-001', 'abc-002', 'ipz-999'});
      expect(await store.listLibraries(), hasLength(1));
    });

    test('合集文件：一份 .sql 多个分类逐片登记、逐片可删', () async {
      final store = storeWithMain();
      store.stagingDbs['combo'] = FakeStagingDb(
        works: {'ipz-999', 'gana-111'},
        urls: {
          'ipz-999': [_magnet2],
          'gana-111': [_magnet3],
        },
        workCategories: {'ipz-999': '4K原版', 'gana-111': '国产原创'},
      );
      final result = await store.mergeFromStaging(
        stagingPath: 'combo',
        name: '磁力合集',
        sourceName: '磁力合集.sql',
      );
      expect(result.ok, isTrue, reason: result.error);
      expect(result.categories, containsAll(['4K原版', '国产原创']));
      expect(result.addedWorks, 2);
      final libraries = await store.listLibraries();
      expect(libraries.map((l) => l.category), containsAll(['4K原版', '国产原创']));
      // 删其中一片：另一片与它的作品原样不动。
      final fourK = libraries.firstWhere((l) => l.category == '4K原版');
      await store.removeLibrary(fourK.id);
      expect(store.videos, isNot(contains('ipz-999')));
      expect(store.videos, contains('gana-111'));
      expect(
        (await store.listLibraries()).map((l) => l.category),
        ['国产原创'],
      );
      expect(store.categories['gana-111'], '国产原创');
    });

    test('非磁力文件被拒、主库一字不动', () async {
      final store = storeWithMain();
      store.stagingDbs['plain'] = FakeStagingDb(
        works: {'zzz-001'},
        urls: {
          'zzz-001': ['https://x/9.m3u8'],
        },
      );
      final result = await store.mergeFromStaging(
        stagingPath: 'plain',
        name: '整库',
        sourceName: '整库.sql',
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('没有磁力链接'));
      expect(store.videos, {'ssis-001', 'abc-002'});
      expect(await store.listLibraries(), isEmpty);
    });
  });

  group('控制器并存导入', () {
    late Directory temp;
    late String dbPath;
    late String stagingPath;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('magnet_ctrl_');
      dbPath = '${temp.path}/女优库.db';
      stagingPath = '${temp.path}/.magnet-staging.db';
      File(dbPath).writeAsStringSync('MAINDB');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    ActressDbTaskController controllerWith(
      FakeMagnetStore store,
      FakeMagnetImporter importer,
    ) {
      final controller = ActressDbTaskController();
      controller.importerFactory = () => importer;
      controller.magnetStoreOpener = (_) async => store;
      return controller;
    }

    FakeMagnetStore storeWithStaging() {
      final store = FakeMagnetStore();
      store.videos.add('ssis-001');
      store.stagingDbs[stagingPath] = FakeStagingDb(
        works: {'ssis-001', 'ipz-999'},
        urls: {
          'ssis-001': [_magnet1],
          'ipz-999': [_magnet2],
        },
        category: '4K原版',
      );
      return store;
    }

    test('成功：先验后并、主库只增、代次推进、临时库清掉', () async {
      final store = storeWithStaging();
      final importer = FakeMagnetImporter();
      final controller = controllerWith(store, importer);
      var mergedCalls = 0;
      final result = await controller.startMagnetImport(
        sqlPath: '${temp.path}/4K原版.sql',
        dbPath: dbPath,
        onMerged: (_) async {
          mergedCalls++;
        },
      );
      expect(result, isNotNull);
      expect(result!.ok, isTrue, reason: result.error);
      expect(importer.calls, 1);
      expect(result.category, '4K原版');
      expect(result.addedWorks, 1);
      expect(store.videos, {'ssis-001', 'ipz-999'});
      expect(mergedCalls, 1);
      expect(controller.magnetImportResult?.ok, isTrue);
      expect(controller.magnetImportError, isNull);
      expect(controller.busy, isFalse);
      expect(controller.dataGeneration, 1);
      // 主库文件没被换掉（并存不是替换）。
      expect(File(dbPath).readAsStringSync(), 'MAINDB');
      expect(File(stagingPath).existsSync(), isFalse);
    });

    test('坏 .sql 在导入器那步拦下：存储没被碰、主库不动', () async {
      final store = storeWithStaging();
      final importer = FakeMagnetImporter(
        result: const ActressSqlImportResult(
          ok: false,
          error: '这个文件不是女优库：缺表 videos',
        ),
      );
      final controller = controllerWith(store, importer);
      final result = await controller.startMagnetImport(
        sqlPath: '${temp.path}/坏文件.sql',
        dbPath: dbPath,
      );
      expect(result!.ok, isFalse);
      expect(controller.magnetImportError, contains('缺表'));
      expect(store.videos, {'ssis-001'});
      expect(await store.listLibraries(), isEmpty);
      expect(controller.dataGeneration, 0);
    });

    test('非磁力 .sql 被拒：错误说清、主库不动', () async {
      final store = storeWithStaging();
      store.stagingDbs[stagingPath] = FakeStagingDb(
        works: {'zzz-001'},
        urls: {
          'zzz-001': ['https://x/9.m3u8'],
        },
      );
      final controller = controllerWith(store, FakeMagnetImporter());
      final result = await controller.startMagnetImport(
        sqlPath: '${temp.path}/整库.sql',
        dbPath: dbPath,
      );
      expect(result!.ok, isFalse);
      expect(controller.magnetImportError, contains('没有磁力链接'));
      expect(store.videos, {'ssis-001'});
    });

    test('没有女优库时先拦，不调导入器', () async {
      final store = storeWithStaging();
      final importer = FakeMagnetImporter();
      final controller = controllerWith(store, importer);
      final result = await controller.startMagnetImport(
        sqlPath: '${temp.path}/4K原版.sql',
        dbPath: '${temp.path}/不存在.db',
      );
      expect(result!.ok, isFalse);
      expect(controller.magnetImportError, contains('还没有女优库'));
      expect(importer.calls, 0);
    });
  });

  group('三态合成（假网关）', () {
    test('任务命中番号：完成算网盘可播、在跑算离线中', () {
      final resolver = MagnetDriveStateResolver(FakePan115Gateway());
      const doneTask = Pan115OfflineTask(
        infoHash: 'aaaa1111',
        name: 'IPZ-999.mp4',
        percent: 1,
        done: true,
      );
      const runningTask = Pan115OfflineTask(
        infoHash: 'aaaa1111',
        name: 'IPZ-999.mp4',
        percent: 0.4,
        done: false,
      );
      expect(
        resolver.stateFromSnapshot(
          code: 'ipz-999',
          magnetUrls: const [_magnet1],
          submitted: const {},
          tasks: const [doneTask],
        ),
        MagnetDriveState.readyInDrive,
      );
      expect(
        resolver.stateFromSnapshot(
          code: 'ipz-999',
          magnetUrls: const [_magnet1],
          submitted: const {},
          tasks: const [runningTask],
        ),
        MagnetDriveState.downloading,
      );
    });

    test('无番号作品靠 infohash 认任务（任务名里没番号）', () {
      final resolver = MagnetDriveStateResolver(FakePan115Gateway());
      const task = Pan115OfflineTask(
        infoHash: 'AAAA1111',
        name: '某主播 2024 直播回放.mp4',
        percent: 0.7,
        done: false,
      );
      expect(
        resolver.stateFromSnapshot(
          code: 'magnet-aaaa1111',
          magnetUrls: const [_magnet1],
          submitted: const {},
          tasks: const [task],
        ),
        MagnetDriveState.downloading,
      );
      expect(
        pan115TaskMatchesMagnets(task, const [_magnet1]),
        isTrue,
      );
      expect(
        pan115TaskMatchesMagnets(task, const [_magnet2]),
        isFalse,
      );
    });

    test('没任务但哈希在已提交记录里算离线中，其余未下载', () {
      final resolver = MagnetDriveStateResolver(FakePan115Gateway());
      expect(
        resolver.stateFromSnapshot(
          code: 'ipz-999',
          magnetUrls: const [_magnet1],
          submitted: const {'aaaa1111'},
          tasks: const [],
        ),
        MagnetDriveState.downloading,
      );
      expect(
        resolver.stateFromSnapshot(
          code: 'ipz-999',
          magnetUrls: const [_magnet1],
          submitted: const {},
          tasks: const [],
        ),
        MagnetDriveState.notDownloaded,
      );
    });

    test('resolve：网盘里真有文件才升到网盘可播', () async {
      final gateway = FakePan115Gateway()
        ..file = const CloudDriveFile(
          id: 'f1',
          name: 'IPZ-999.mp4',
          isFolder: false,
          kind: CloudFileKind.video,
        );
      final state = await MagnetDriveStateResolver(
        gateway,
      ).resolve(code: 'ipz-999', magnetUrls: const [_magnet1]);
      expect(state, MagnetDriveState.readyInDrive);
    });
  });

  group('磁力点播链（假网关）', () {
    test('未登入：引导登入，不提交', () async {
      final gateway = FakePan115Gateway(loggedIn: false);
      final outcome = await MagnetOfflinePlayFlow(
        gateway,
      ).play(code: 'ipz-999', magnetUrls: const [_magnet1]);
      expect(outcome.kind, MagnetPlayOutcomeKind.needsLogin);
      expect(gateway.submitCalls, isEmpty);
    });

    test('网盘已有片：取链直接播，不提交', () async {
      final gateway = FakePan115Gateway()
        ..file = const CloudDriveFile(
          id: 'f1',
          name: 'IPZ-999.mp4',
          isFolder: false,
          kind: CloudFileKind.video,
        );
      final outcome = await MagnetOfflinePlayFlow(
        gateway,
      ).play(code: 'ipz-999', magnetUrls: const [_magnet1]);
      expect(outcome.kind, MagnetPlayOutcomeKind.playable);
      expect(outcome.url, 'https://cdn.example.com/115.mp4');
      expect(gateway.submitCalls, isEmpty);
    });

    test('已在离线中：报进度，不重复提交', () async {
      final gateway = FakePan115Gateway()
        ..tasks = const [
          Pan115OfflineTask(
            infoHash: 'aaaa1111',
            name: 'IPZ-999.mp4',
            percent: 0.4,
            done: false,
          ),
        ];
      final outcome = await MagnetOfflinePlayFlow(
        gateway,
      ).play(code: 'ipz-999', magnetUrls: const [_magnet1]);
      expect(outcome.kind, MagnetPlayOutcomeKind.downloading);
      expect(outcome.message, contains('40%'));
      expect(gateway.submitCalls, isEmpty);
    });

    test('无片无任务：逐条试、一条成功即止并记哈希', () async {
      final gateway = FakePan115Gateway()..failUrls.add(_magnet1);
      final outcome = await MagnetOfflinePlayFlow(gateway).play(
        code: 'ipz-999',
        magnetUrls: const [_magnet1, _magnet2, _magnet3],
      );
      expect(outcome.kind, MagnetPlayOutcomeKind.submitted);
      // 第一条失败试第二条，第二条成功就停，第三条不试。
      expect(gateway.submitCalls, [_magnet1, _magnet2]);
      expect(gateway.recorded, ['bbbb2222']);
    });

    test('全部已提交过：不再交，回离线中', () async {
      final gateway = FakePan115Gateway()
        ..submitted.addAll(['aaaa1111', 'bbbb2222']);
      final outcome = await MagnetOfflinePlayFlow(gateway).play(
        code: 'ipz-999',
        magnetUrls: const [_magnet1, _magnet2],
      );
      expect(outcome.kind, MagnetPlayOutcomeKind.downloading);
      expect(gateway.submitCalls, isEmpty);
    });

    test('全提交失败：给中文原因', () async {
      final gateway = FakePan115Gateway()
        ..failUrls.addAll([_magnet1, _magnet2]);
      final outcome = await MagnetOfflinePlayFlow(gateway).play(
        code: 'ipz-999',
        magnetUrls: const [_magnet1, _magnet2],
      );
      expect(outcome.kind, MagnetPlayOutcomeKind.failed);
      expect(outcome.message, contains('提交失败'));
    });

    test('没有磁力/没有番号：直接失败不碰网关', () async {
      final gateway = FakePan115Gateway();
      final noMagnet = await MagnetOfflinePlayFlow(
        gateway,
      ).play(code: 'ipz-999', magnetUrls: const ['https://x/1.m3u8']);
      expect(noMagnet.kind, MagnetPlayOutcomeKind.failed);
      final noCode = await MagnetOfflinePlayFlow(
        gateway,
      ).play(code: '', magnetUrls: const [_magnet1]);
      expect(noCode.kind, MagnetPlayOutcomeKind.failed);
      expect(gateway.submitCalls, isEmpty);
    });
  });

  group('管理页磁力分类库区', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('magnet_page_');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    Future<FakeMagnetStore> storeWithLibrary() async {
      final store = FakeMagnetStore();
      store.stagingDbs['stage'] = FakeStagingDb(
        works: {'ipz-999'},
        urls: {
          'ipz-999': [_magnet2],
        },
        category: '4K原版',
      );
      await store.mergeFromStaging(
        stagingPath: 'stage',
        name: '4K原版',
        sourceName: '4K原版.sql',
      );
      return store;
    }

    Widget pageWith(
      FakeMagnetStore store, {
      ActressDbTaskController? controller,
      Future<String?> Function()? pickSqlFile,
    }) {
      return MaterialApp(
        home: ActressDbManagePage(
          dbPath: '${temp.path}/女优库.db',
          closeDatabase: () async {},
          reloadDatabase: () async {},
          controller: controller ?? ActressDbTaskController(),
          infoLoader: (_) async => const ActressDbInfo(
            exists: true,
            fileBytes: 100,
            videos: 10,
            actresses: 2,
            playUrls: 10,
          ),
          metaLoader: () async => null,
          magnetStoreOpener: (_) async => store,
          pickSqlFile: pickSqlFile,
        ),
      );
    }

    testWidgets('已导入库有行：分类名与部数可见', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await storeWithLibrary();
      await tester.pumpWidget(pageWith(store));
      await tester.pumpAndSettle();
      expect(find.text('磁力分类库'), findsOneWidget);
      expect(find.text('导入磁力分类库'), findsOneWidget);
      expect(find.text('4K原版'), findsOneWidget);
      expect(find.textContaining('1 部 · 来源 4K原版.sql'), findsOneWidget);
    });

    testWidgets('删库：确认后行消失、存储里也没了', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await storeWithLibrary();
      await tester.pumpWidget(pageWith(store));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('删除分类库「4K原版」？'), findsOneWidget);
      // 「删除」二字页上还有危险区的同名按钮，只点弹窗里那个。
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      );
      await tester.pumpAndSettle();
      expect(await store.listLibraries(), isEmpty);
      expect(find.text('还没有导入过磁力分类库。'), findsOneWidget);
    });

    testWidgets('导入：走控制器并入，结果文案带分类与新增数', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dbPath = '${temp.path}/女优库.db';
      File(dbPath).writeAsStringSync('MAINDB');
      final store = FakeMagnetStore();
      store.stagingDbs['${temp.path}/.magnet-staging.db'] = FakeStagingDb(
        works: {'ipz-999'},
        urls: {
          'ipz-999': [_magnet2],
        },
        category: '国产原创',
      );
      final controller = ActressDbTaskController();
      controller.importerFactory = () => FakeMagnetImporter();
      controller.magnetStoreOpener = (_) async => store;
      await tester.pumpWidget(
        pageWith(
          store,
          controller: controller,
          pickSqlFile: () async => '${temp.path}/国产原创.sql',
        ),
      );
      await tester.pumpAndSettle();
      // 页上有两个「导入」按钮（整库替换在前、磁力在后）。
      // 控制器链里有真文件检查（FakeAsync 区里永不返回），
      // 整条点按链放进 runAsync 里跑完再回来断言。
      await tester.runAsync(() async {
        await tester.tap(find.text('导入').last);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('已导入分类「国产原创」'), findsOneWidget);
      expect(find.textContaining('新增 1 部作品'), findsOneWidget);
      expect(store.videos, {'ipz-999'});
    });
  });

  group('影视库详情页磁力线路行', () {
    testWidgets('磁力作品多一条 115 网盘线，正片行不再说没地址', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = MemoryActressDatabase();
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      const entry = FilmLibraryEntry(
        vodId: 'ipz-999',
        title: '磁力测试作品',
        coverUrl: '',
        playUrl: _magnet2,
        code: 'IPZ-999',
        category: '4K原版',
        site: 'magnet',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FilmDetailPage(
            entry: entry,
            database: db,
            repository: FixtureRepository(),
            store: store,
            service: FilmLibraryService(database: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('磁力 · 115 网盘'), findsOneWidget);
      expect(find.text('磁力作品 · 走 115 网盘离线播放'), findsOneWidget);
      expect(find.text('暂无可播地址'), findsNothing);
      // 假仓库没有 115 网关：点磁力行如实提示不可用，不假装能播。
      await tester.tap(find.text('磁力 · 115 网盘'));
      await tester.pumpAndSettle();
      expect(find.textContaining('115 网盘不可用'), findsOneWidget);
    });

    testWidgets('普通直链作品没有磁力行', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = MemoryActressDatabase();
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      addTearDown(store.dispose);
      const entry = FilmLibraryEntry(
        vodId: 'ssis-001',
        title: '普通作品',
        coverUrl: '',
        playUrl: 'https://example.com/video.m3u8',
        code: 'SSIS-001',
        category: '日本AV',
        site: 'whos',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FilmDetailPage(
            entry: entry,
            database: db,
            repository: FixtureRepository(),
            store: store,
            service: FilmLibraryService(database: db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('磁力 · 115 网盘'), findsNothing);
      expect(find.text('直链播放（parse=0）'), findsOneWidget);
    });
  });
}
