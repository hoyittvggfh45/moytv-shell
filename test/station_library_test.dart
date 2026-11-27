import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/actress/actress_db_info.dart';
import 'package:moyi/actress/actress_db_manage_page.dart';
import 'package:moyi/actress/actress_sql_import.dart';
import 'package:moyi/content_legado.dart';
import 'package:moyi/content_models.dart';
import 'package:moyi/content_py.dart';
import 'package:moyi/content_registry.dart';
import 'package:moyi/content_zone_binding.dart';
import 'package:moyi/content_zone_screen.dart';
import 'package:moyi/core_bridge.dart';
import 'package:moyi/import_file_store.dart';
import 'package:moyi/station_library.dart';
import 'package:moyi/station_signature.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 站点库第一期（2026-11-27）：签名（RFC 向量 + 正式库向量）、
/// 版本门八步拒收、导入器换库/回退、管理页站点库区、内容区
/// 未导入引导、数据层落盘链。固件 test/fixtures/
/// station_library_fixture.sql 由工作目录 gen_test_fixture.py
/// 用生产钥匙签出（2 条：legado_8059_0 + asmrhoney）。

const _fixtureAudioContent = '# fixture spider for tests\n'
    'class Spider:\n'
    '    pass\n';
const _fixtureLegadoContent =
    '{"bookSourceName":"978小说",'
    '"bookSourceUrl":"https://fixture.invalid/978",'
    '"bookSourceType":0}';
const _manifest = {'legado_8059_0', 'asmrhoney'};

List<int> _hexBytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

/// 极小 SQL VALUES 解析（只服务固件/记录执行器）：字符串
/// （'' 转义）、整数、NULL。
List<Object?> _parseValuesAt(String text, int openParen) {
  final values = <Object?>[];
  var i = openParen + 1;
  while (i < text.length) {
    final c = text[i];
    if (c == ' ' || c == '\n' || c == '\t' || c == ',') {
      i++;
      continue;
    }
    if (c == ')') break;
    if (c == "'") {
      final buf = StringBuffer();
      i++;
      while (i < text.length) {
        if (text[i] == "'") {
          if (i + 1 < text.length && text[i + 1] == "'") {
            buf.write("'");
            i += 2;
            continue;
          }
          i++;
          break;
        }
        buf.write(text[i]);
        i++;
      }
      values.add(buf.toString());
      continue;
    }
    if (text.startsWith('NULL', i)) {
      values.add(null);
      i += 4;
      continue;
    }
    final m = RegExp(r'-?\d+').matchAsPrefix(text, i);
    if (m != null) {
      values.add(int.parse(m.group(0)!));
      i = m.end;
      continue;
    }
    throw StateError('无法解析 VALUES: ${text.substring(i, i + 20)}');
  }
  return values;
}

({Map<String, String> meta, List<Map<String, Object?>> rows})
_parseStationSql(String sql) {
  final meta = <String, String>{};
  final rows = <Map<String, Object?>>[];
  var from = 0;
  while (true) {
    final idx = sql.indexOf('INSERT INTO station_meta', from);
    if (idx < 0) break;
    final open = sql.indexOf('(', sql.indexOf('VALUES', idx));
    final values = _parseValuesAt(sql, open);
    meta['${values[0]}'] = '${values[1]}';
    from = open + 1;
  }
  from = 0;
  const columns = [
    'site_id', 'kind', 'section', 'name', 'asset_path', 'source_type',
    'extra_json', 'byte_len', 'sha256', 'content',
  ];
  while (true) {
    final idx = sql.indexOf('INSERT INTO station_items', from);
    if (idx < 0) break;
    final open = sql.indexOf('(', sql.indexOf('VALUES', idx));
    final values = _parseValuesAt(sql, open);
    rows.add({for (var c = 0; c < columns.length; c++) columns[c]: values[c]});
    from = open + 1;
  }
  return (meta: meta, rows: rows);
}

/// 内存执行器：按解析好的 meta/rows 应答版本门查询。
class _MemoryExecutor implements SqlImportExecutor {
  _MemoryExecutor(this.meta, this.rows, {this.hasTables = true});

  final Map<String, String> meta;
  final List<Map<String, Object?>> rows;
  final bool hasTables;

  @override
  Future<void> execute(String sql) async {}

  @override
  Future<void> executeBatch(List<String> statements) async {}

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    if (!hasTables) throw StateError('no such table');
    if (sql.contains('station_meta')) {
      return [
        for (final e in meta.entries) {'key': e.key, 'value': e.value},
      ];
    }
    return [for (final row in rows) Map<String, Object?>.of(row)];
  }

  @override
  Future<void> close() async {}
}

/// 记录执行器：真跑导入器的语句流（解析 INSERT 落内存），
/// 并在指定路径建一个空文件，好让导入器的改名顶替能走通。
class _RecordingExecutor implements SqlImportExecutor {
  _RecordingExecutor();

  factory _RecordingExecutor.fromParsed(
    ({Map<String, String> meta, List<Map<String, Object?>> rows}) parsed,
  ) {
    final executor = _RecordingExecutor();
    executor.tables.addAll(['station_meta', 'station_items']);
    executor.meta.addAll(parsed.meta);
    executor.rows.addAll(parsed.rows);
    return executor;
  }

  final tables = <String>{};
  final meta = <String, String>{};
  final rows = <Map<String, Object?>>[];

  @override
  Future<void> execute(String sql) async {
    if (sql.contains('CREATE TABLE station_meta')) {
      tables.add('station_meta');
    }
    if (sql.contains('CREATE TABLE station_items')) {
      tables.add('station_items');
    }
  }

  @override
  Future<void> executeBatch(List<String> statements) async {
    for (final statement in statements) {
      if (statement.startsWith('INSERT INTO station_meta')) {
        final open = statement.indexOf(
          '(',
          statement.indexOf('VALUES'),
        );
        final values = _parseValuesAt(statement, open);
        meta['${values[0]}'] = '${values[1]}';
      } else if (statement.startsWith('INSERT INTO station_items')) {
        final parsed = _parseStationSql('$statement;');
        rows.addAll(parsed.rows);
      }
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    if (sql.contains('station_meta')) {
      if (!tables.contains('station_meta')) {
        throw StateError('no such table: station_meta');
      }
      return [
        for (final e in meta.entries) {'key': e.key, 'value': e.value},
      ];
    }
    if (!tables.contains('station_items')) {
      throw StateError('no such table: station_items');
    }
    return [for (final row in rows) Map<String, Object?>.of(row)];
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('moyi_station_test');
    const provider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, (call) async => tempDir.path);
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    const provider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(provider, null);
    StationLibrary.debugDbPathOverride = null;
    await tempDir.delete(recursive: true);
  });

  group('Ed25519 验签', () {
    test('RFC 8032 向量 1（空消息）', () {
      final pk = _hexBytes(
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
      );
      final sig = _hexBytes(
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      );
      expect(
        ed25519Verify(signature: sig, message: const [], publicKey: pk),
        isTrue,
      );
      expect(
        ed25519Verify(signature: sig, message: const [1], publicKey: pk),
        isFalse,
      );
    });

    test('正式库向量：生成器（Python）签、App（Dart）验', () {
      final payload = stationLibrarySignaturePayload(
        formatVersion: '1',
        requiredCoreVersion: '41',
        contentSha256:
            '861339212dc852249e72acfb32e559541af70819a65304e09c25e07b2e693927',
      );
      const signature =
          '43b5a1a747c2ee16d68ef48cee55c5f6f03a4ec3d729c5bcffc347c26797ed'
          '555e48dcaaed1f4ae1ff953e517a098576e0063b1d1737076934735c20155dec08';
      expect(
        verifyStationLibrarySignature(payload: payload, signatureHex: signature),
        isTrue,
      );
      final tamperedPayload = stationLibrarySignaturePayload(
        formatVersion: '1',
        requiredCoreVersion: '42',
        contentSha256:
            '861339212dc852249e72acfb32e559541af70819a65304e09c25e07b2e693927',
      );
      expect(
        verifyStationLibrarySignature(
          payload: tamperedPayload,
          signatureHex: signature,
        ),
        isFalse,
      );
      expect(
        verifyStationLibrarySignature(
          payload: payload,
          signatureHex: '${signature.substring(0, 127)}0',
        ),
        isFalse,
      );
    });
  });

  group('版本门八步', () {
    late Map<String, String> meta;
    late List<Map<String, Object?>> rows;

    setUp(() {
      final sql = File(
        'test/fixtures/station_library_fixture.sql',
      ).readAsStringSync();
      final parsed = _parseStationSql(sql);
      meta = parsed.meta;
      rows = parsed.rows;
    });

    Future<StationLibraryGateResult> gate({
      Map<String, String>? metaOverride,
      List<Map<String, Object?>>? rowsOverride,
      int core = 41,
      bool hasTables = true,
    }) {
      return validateStationLibrary(
        _MemoryExecutor(
          metaOverride ?? meta,
          rowsOverride ?? rows,
          hasTables: hasTables,
        ),
        manifestIds: _manifest,
        currentCoreVersion: core,
      );
    }

    test('正库全过', () async {
      final result = await gate();
      expect(result.ok, isTrue, reason: result.error);
      expect(result.items, hasLength(2));
    });

    test('身份不对拒', () async {
      final result = await gate(metaOverride: {...meta, 'format': 'other'});
      expect(result.ok, isFalse);
      expect(result.error, contains('不是魔蚁站点库'));
    });

    test('缺表按身份不对拒', () async {
      final result = await gate(hasTables: false);
      expect(result.ok, isFalse);
      expect(result.error, contains('不是魔蚁站点库'));
    });

    test('格式版本不受支持拒', () async {
      final result = await gate(
        metaOverride: {...meta, 'format_version': '2'},
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('格式版本不受当前 App 支持'));
    });

    test('核心版本不够拒', () async {
      final result = await gate(
        metaOverride: {...meta, 'required_core_version': '999'},
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('要求 App 版本不低于'));
    });

    test('条数对不上拒', () async {
      final result = await gate(metaOverride: {...meta, 'item_count': '3'});
      expect(result.ok, isFalse);
      expect(result.error, contains('条数对不上'));
    });

    test('逐行哈希对不上拒', () async {
      final tampered = [
        {...rows[0], 'content': '${rows[0]['content']} '},
        rows[1],
      ];
      final result = await gate(rowsOverride: tampered);
      expect(result.ok, isFalse);
      expect(result.error, contains('内容校验失败'));
    });

    test('名单外站点整单拒', () async {
      const fake = 'print(1)';
      final fakeRow = <String, Object?>{
        'site_id': 'evil_outsider',
        'kind': 'audio_py',
        'section': 'audio',
        'name': 'x',
        'asset_path': 'assets/audio_spiders/evil.py',
        'source_type': null,
        'extra_json': '{}',
        'byte_len': utf8.encode(fake).length,
        'sha256': sha256.convert(utf8.encode(fake)).toString(),
        'content': fake,
      };
      final result = await gate(
        metaOverride: {...meta, 'item_count': '3'},
        rowsOverride: [...rows, fakeRow],
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('名单外'));
    });

    test('整库校验对不上拒', () async {
      final result = await gate(
        metaOverride: {...meta, 'content_sha256': '0' * 64},
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('整体校验失败'));
    });

    test('签名被改拒', () async {
      final sig = meta['signature']!;
      final flipped = '${sig.substring(0, 127)}'
          '${sig.endsWith('0') ? '1' : '0'}';
      final result = await gate(
        metaOverride: {...meta, 'signature': flipped},
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('签名校验失败'));
    });

    test('缺签名拒', () async {
      final noSig = {...meta}..remove('signature');
      final result = await gate(metaOverride: noSig);
      expect(result.ok, isFalse);
      expect(result.error, contains('缺少有效的整库签名'));
    });
  });

  group('导入器与状态链', () {
    late String dbPath;
    late String fixturePath;

    setUp(() {
      fixturePath = File(
        'test/fixtures/station_library_fixture.sql',
      ).absolute.path;
      dbPath = '${tempDir.path}/station_library.db';
      StationLibrary.debugDbPathOverride = dbPath;
      StationLibrary.debugSetItems(const []);
    });

    StationLibraryImporter importer() => StationLibraryImporter(
      executorFactory: (path) async {
        // 假执行器不落真库：建个空文件让导入器的改名顶替走通。
        await File(path).create(recursive: true);
        return _RecordingExecutor();
      },
    );

    test('导入正库：换库成功，再导一次留 .bak', () async {
      final first = await importer().importFile(
        sqlPath: fixturePath,
        dbPath: dbPath,
        manifestIds: _manifest,
        currentCoreVersion: 41,
      );
      expect(first.ok, isTrue, reason: first.error);
      expect(first.itemCount, 2);
      expect(await File(dbPath).exists(), isTrue);
      expect(await File('$dbPath.bak').exists(), isFalse);

      final second = await importer().importFile(
        sqlPath: fixturePath,
        dbPath: dbPath,
        manifestIds: _manifest,
        currentCoreVersion: 41,
      );
      expect(second.ok, isTrue, reason: second.error);
      expect(await File('$dbPath.bak').exists(), isTrue);
    });

    test('签名被改的文件：整单拒收，现有库一字不动', () async {
      final good = await importer().importFile(
        sqlPath: fixturePath,
        dbPath: dbPath,
        manifestIds: _manifest,
        currentCoreVersion: 41,
      );
      expect(good.ok, isTrue, reason: good.error);
      final before = await File(dbPath).length();

      final text = await File(fixturePath).readAsString();
      final sigStart = text.indexOf("'signature', '") + "'signature', '".length;
      final flipped = text[sigStart] == '0' ? '1' : '0';
      final tamperedPath = '${tempDir.path}/tampered.sql';
      await File(tamperedPath).writeAsString(
        text.replaceRange(sigStart, sigStart + 1, flipped),
      );
      final result = await importer().importFile(
        sqlPath: tamperedPath,
        dbPath: dbPath,
        manifestIds: _manifest,
        currentCoreVersion: 41,
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('签名'));
      expect(await File(dbPath).length(), before);
      expect(await File('$dbPath.importing').exists(), isFalse);
    });

    test('回退上一版：先验后换', () async {
      await importer().importFile(
        sqlPath: fixturePath,
        dbPath: dbPath,
        manifestIds: _manifest,
        currentCoreVersion: 41,
      );
      await importer().importFile(
        sqlPath: fixturePath,
        dbPath: dbPath,
        manifestIds: _manifest,
        currentCoreVersion: 41,
      );
      expect(await File('$dbPath.bak').exists(), isTrue);
      final parsed = _parseStationSql(await File(fixturePath).readAsString());
      final result = await StationLibrary.restoreBackup(
        manifestIds: _manifest,
        currentCoreVersion: 41,
        executorFactory: (_) async =>
            _RecordingExecutor.fromParsed(parsed),
      );
      expect(result.ok, isTrue, reason: result.error);
      expect(await File(dbPath).exists(), isTrue);
      expect(await File('$dbPath.bak').exists(), isFalse);
    });

    test('删库回灰：库文件、备份、落盘 py 一并清', () async {
      StationLibrary.debugSetItems(const [
        StationLibraryItem(
          siteId: 'asmrhoney',
          kind: 'audio_py',
          section: 'audio',
          name: '🔞ASMRHoney',
          assetPath: 'assets/audio_spiders/asmrhoney.py',
          sourceType: null,
          extra: {},
          content: _fixtureAudioContent,
        ),
      ]);
      expect(StationLibrary.provides('asmrhoney'), isTrue);
      await File(dbPath).writeAsString('db');
      await File('$dbPath.bak').writeAsString('bak');
      final landedName = await ImportFileStore.save(
        'builtin_asmrhoney',
        'py',
        utf8.encode(_fixtureAudioContent),
      );
      final landedPath = await ImportFileStore.pathOf(landedName);
      expect(await File(landedPath).exists(), isTrue);

      await StationLibrary.deleteLibrary();

      expect(StationLibrary.provides('asmrhoney'), isFalse);
      expect(await File(dbPath).exists(), isFalse);
      expect(await File('$dbPath.bak').exists(), isFalse);
      expect(await File(landedPath).exists(), isFalse);
    });
  });

  group('数据层门控', () {
    setUp(() => StationLibrary.debugSetItems(const []));

    PyContentSource pySource() => PyContentSource(
      id: 'asmrhoney',
      name: '🔞ASMRHoney',
      assetPath: 'assets/audio_spiders/asmrhoney.py',
    );

    JsonContentSource legadoSource() => JsonContentSource(
      id: 'legado_8059_0',
      name: '978小说',
      assetPath: 'assets/legado_sources/legado_8059_0.json',
    );

    test('名单集合口径：112 条（legado 101 + 听读 py 11）', () {
      final ids = ContentRegistry.stationLibraryManifestIds;
      expect(ids, hasLength(112));
      expect(ids.contains('legado_8059_0'), isTrue);
      expect(ids.contains('asmrhoney'), isTrue);
      expect(ids.contains('hongguo_audio'), isTrue);
      // 小说 py 不归站点库管，不进名单。
      expect(ids.contains('aabook'), isFalse);
    });

    test('听读 py：未导入抛未导入话术，导入后落盘逐字一致', () async {
      final source = pySource();
      expect(source.stationGated, isTrue);
      await expectLater(
        source.categories(),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            stationLibraryLockedMessage,
          ),
        ),
      );

      StationLibrary.debugSetItems(const [
        StationLibraryItem(
          siteId: 'asmrhoney',
          kind: 'audio_py',
          section: 'audio',
          name: '🔞ASMRHoney',
          assetPath: 'assets/audio_spiders/asmrhoney.py',
          sourceType: null,
          extra: {},
          content: _fixtureAudioContent,
        ),
      ]);
      final landedPath = await ImportFileStore.pathOf(
        'builtin_asmrhoney.py',
      );
      if (await File(landedPath).exists()) {
        await File(landedPath).delete();
      }
      Object? error;
      try {
        await pySource().catalog('audio', 1);
      } catch (e) {
        error = e;
      }
      // 桥在测试宿主里不可用（与未导入话术是两回事），但落盘
      // 必须已经发生且逐字一致——字节来源换成站点库行得证。
      expect(
        error is AppFailure &&
            error.message == stationLibraryLockedMessage,
        isFalse,
      );
      expect(await File(landedPath).readAsString(), _fixtureAudioContent);
    });

    test('legado：未导入抛未导入话术，导入后不再是未导入错', () async {
      await expectLater(
        legadoSource().categories(),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            stationLibraryLockedMessage,
          ),
        ),
      );
      StationLibrary.debugSetItems(const [
        StationLibraryItem(
          siteId: 'legado_8059_0',
          kind: 'legado_json',
          section: 'novel',
          name: '978小说',
          assetPath: 'assets/legado_sources/legado_8059_0.json',
          sourceType: 0,
          extra: {},
          content: _fixtureLegadoContent,
        ),
      ]);
      Object? error;
      try {
        await legadoSource().categories();
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(
        error is AppFailure &&
            error.message == stationLibraryLockedMessage,
        isFalse,
      );
    });
  });

  group('界面', () {
    setUp(() => StationLibrary.debugSetItems(const []));

    testWidgets('内容区：当前源未导入出引导，导入后引导退场', (tester) async {
      final source = PyContentSource(
        id: 'asmrhoney',
        name: '🔞ASMRHoney',
        assetPath: 'assets/audio_spiders/asmrhoney.py',
      );
      final binding = ContentZoneBinding(sourcesProvider: (_) => [source]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentZoneScreen(
              section: ContentSection.audio,
              binding: binding,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('station-library-guide')),
        findsOneWidget,
      );
      expect(find.textContaining('还没导入'), findsOneWidget);

      StationLibrary.debugSetItems(const [
        StationLibraryItem(
          siteId: 'asmrhoney',
          kind: 'audio_py',
          section: 'audio',
          name: '🔞ASMRHoney',
          assetPath: 'assets/audio_spiders/asmrhoney.py',
          sourceType: null,
          extra: {},
          content: _fixtureAudioContent,
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byKey(const ValueKey('station-library-guide')),
        findsNothing,
      );
    });

    testWidgets('管理页站点库区：未导入态 + jar 豁免说明 + 导入回结果', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ActressDbManagePage(
            dbPath: '/tmp/station_test_actress.db',
            closeDatabase: () async {},
            reloadDatabase: () async {},
            infoLoader: (_) async => const ActressDbInfo(exists: false),
            metaLoader: () async => null,
            stationStatusLoader: () async =>
                (imported: false, itemCount: 0, backupExists: false),
            stationMetaLoader: () async => null,
            stationImportStarter: () async =>
                const StationLibraryImportResult(ok: true, itemCount: 112),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('站点库'), 200);
      expect(find.textContaining('还没有导入站点库'), findsOneWidget);
      expect(find.textContaining('jar 站第一期不在站点库范围内'), findsOneWidget);

      final row = find.ancestor(
        of: find.text('导入站点库'),
        matching: find.byType(Row),
      );
      final importButton = find.descendant(
        of: row,
        matching: find.text('导入'),
      );
      await tester.scrollUntilVisible(importButton, 100);
      await tester.pump();
      await tester.tap(importButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('已导入站点库：共 112 条'), findsOneWidget);
    });

    testWidgets('管理页站点库区：已导入态带回退与删除', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ActressDbManagePage(
            dbPath: '/tmp/station_test_actress.db',
            closeDatabase: () async {},
            reloadDatabase: () async {},
            infoLoader: (_) async => const ActressDbInfo(exists: false),
            metaLoader: () async => null,
            stationStatusLoader: () async =>
                (imported: true, itemCount: 112, backupExists: true),
            stationMetaLoader: () async => const StationLibraryImportMeta(
              sourceName: '魔蚁站点.sql',
              importedAtMillis: 1764259200000,
              libraryVersion: '20261127',
              itemCount: 112,
              requiredCoreLabel: '2026.11.27+41',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('删除站点库'), 200);
      expect(find.textContaining('已导入站点库：共 112 条'), findsOneWidget);
      expect(find.text('回退上一版站点库'), findsOneWidget);
      expect(find.text('删除站点库'), findsOneWidget);
    });
  });
}
