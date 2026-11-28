import 'dart:convert';
import 'dart:io';

import 'package:enough_convert/gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/actress/actress_sql_import.dart';
import 'package:path/path.dart' as p;

/// 假执行器：只记 SQL、不碰真 sqlite（flutter test 里 sqflite 跑不起来）。
class _FakeExecutor implements SqlImportExecutor {
  final statements = <String>[];
  final tables = <String>{};
  final counts = <String, int>{};

  static String? _insertTable(String sql) => RegExp(
    r'INSERT INTO\s+"?(\w+)',
    caseSensitive: false,
  ).firstMatch(sql)?.group(1)?.toLowerCase();

  @override
  Future<void> execute(String sql) async {
    statements.add(sql);
    final upper = sql.trimLeft().toUpperCase();
    if (upper.startsWith('CREATE TABLE')) {
      final name = RegExp(
        r'CREATE TABLE\s+"?(\w+)',
        caseSensitive: false,
      ).firstMatch(sql)?.group(1)?.toLowerCase();
      if (name != null) tables.add(name);
    }
    final table = _insertTable(sql);
    if (table != null) counts[table] = (counts[table] ?? 0) + 1;
  }

  @override
  Future<void> executeBatch(List<String> batch) async {
    for (final statement in batch) {
      await execute(statement);
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql) async {
    if (sql.contains('sqlite_master')) {
      return [
        for (final t in tables) {'name': t},
      ];
    }
    if (sql.toUpperCase().startsWith('PRAGMA TABLE_INFO')) return const [];
    if (sql.toUpperCase().contains('COUNT(*)')) {
      final table =
          RegExp(r'FROM\s+(\w+)', caseSensitive: false)
              .firstMatch(sql)
              ?.group(1)
              ?.toLowerCase() ??
          '';
      return [
        {'n': counts[table] ?? 0},
      ];
    }
    return const [];
  }

  @override
  Future<void> close() async {}
}

const _sqlTemplate =
    'CREATE TABLE actresses (cate_id TEXT PRIMARY KEY, name TEXT, avatar TEXT);\n'
    'CREATE TABLE videos (vod_id TEXT PRIMARY KEY, title TEXT, pic_url TEXT, '
    'm3u8_url TEXT, vod_play_url TEXT, type_name TEXT);\n'
    'CREATE TABLE video_actress (vod_id TEXT, cate_id TEXT, PRIMARY KEY (vod_id, cate_id));\n'
    'CREATE TABLE video_play_urls (vod_id TEXT, play_url TEXT, play_from TEXT, '
    'PRIMARY KEY (vod_id, play_url));\n'
    "INSERT INTO actresses VALUES('1','中文演员','http://x/a.jpg');\n"
    "INSERT INTO videos VALUES('v1','中文标题','http://x/c.jpg',"
    "'http://x/1.m3u8','http://x/1.m3u8','有码');\n"
    "INSERT INTO video_actress VALUES('v1','1');\n"
    "INSERT INTO video_play_urls VALUES('v1','http://x/1.m3u8','test');\n";

void main() {
  late Directory tmp;
  late _FakeExecutor executor;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('zaka_sql_encoding_');
    executor = _FakeExecutor();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> writeSql(List<int> bytes, {String name = 'import.sql'}) async {
    final file = File(p.join(tmp.path, name));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<ActressSqlImportResult> runImport(String sqlPath) async {
    final dbPath = p.join(tmp.path, 'db', '女优库.db');
    await Directory(p.dirname(dbPath)).create(recursive: true);
    return ActressSqlImporter(
      executorFactory: (tempPath) async {
        // 真机上执行器打开的就是这个临时库文件；这里建个占位文件，
        // 换库那一步的 rename 才有源。
        await File(tempPath).writeAsBytes(const []);
        return executor;
      },
    ).importFile(
      sqlPath: sqlPath,
      dbPath: dbPath,
      closeDatabase: () async {},
      onProgress: (_) {},
    );
  }

  test('UTF-8 中文文件识别为 utf8', () async {
    final path = await writeSql(utf8.encode(_sqlTemplate));
    expect(
      await ActressSqlImporter.detectEncoding(File(path), isGz: false),
      SqlTextEncoding.utf8,
    );
  });

  test('GBK 中文文件识别为 gbk', () async {
    final path = await writeSql(gbk.encode(_sqlTemplate));
    expect(
      await ActressSqlImporter.detectEncoding(File(path), isGz: false),
      SqlTextEncoding.gbk,
    );
  });

  test('GBK 整库 .sql 能导入，中文标题不乱码', () async {
    final path = await writeSql(gbk.encode(_sqlTemplate));
    final result = await runImport(path);
    expect(result.ok, isTrue, reason: result.error ?? '');
    expect(result.videos, 1);
    expect(result.playUrls, 1);
    expect(
      executor.statements.any((sql) => sql.contains('中文标题')),
      isTrue,
      reason: '中文没被按单字节解坏',
    );
    expect(
      executor.statements.any((sql) => sql.contains('中文演员')),
      isTrue,
    );
  });

  test('UTF-8 BOM 不影响第一条建表语句', () async {
    final path = await writeSql([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(_sqlTemplate),
    ]);
    final result = await runImport(path);
    expect(result.ok, isTrue, reason: result.error ?? '');
    // 第一条语句前面还有 PRAGMA；关键是有没有识别出建表（BOM 没剥
    // 掉的话首条会是“\uFEFFCREATE …”，表名记不进来）。
    expect(executor.tables.contains('actresses'), isTrue);
    expect(
      executor.statements.any(
        (sql) => sql.contains('中文标题'),
      ),
      isTrue,
    );
  });

  test('UTF-16 文件给明确结论，不按乱码硬导', () async {
    final path = await writeSql([0xFF, 0xFE, ...utf8.encode(_sqlTemplate)]);
    final result = await runImport(path);
    expect(result.ok, isFalse);
    expect(result.error, contains('UTF-16'));
  });
}
