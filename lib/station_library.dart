import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'actress/actress_sql_import.dart';
import 'app_update.dart';
import 'import_file_store.dart';
import 'station_signature.dart';

/// 站点库（2026-11-27 用户令，第一期）：包里只留名单（登记表），
/// 阅读 JSON 书源（legado）与听读 py 蜘蛛的代码装进独立的
/// 「魔蚁站点.sql」走导入激活——没导入，这些站只在名单里、
/// 点不开；导入后字节从站点库行落盘/直供，加载链与现行内置
/// 完全一致。站点库是独立槽：独立文件 station_library.db，
/// 不与女优库/磁力库混槽，删它不伤另两库。
///
/// 本期范围：legado_json 101 条 + audio_py 11 条。jar 站一期
/// 豁免（名单里没导入也能用）；原生站（红果、听书网、懒人
/// 听书、番茄音乐）代码在包里、同样不受站点库影响，红果是
/// 没导入前恒可用的核心站。

/// 听读 py 资产前缀：登记表里 assetPath 以它开头的 PyContentSource
/// 属站点库范围（与 content_registry 的名单口径同一判定）。
const stationAudioPyAssetPrefix = 'assets/audio_spiders/';

/// legado JSON 资产前缀：assetPath 以它开头的 JsonContentSource
/// 属站点库范围。
const stationLegadoAssetPrefix = 'assets/legado_sources/';

/// 站点库文件身份标识（station_meta.format）。
const stationLibraryFormat = 'moyi-station-library';

/// 本 App 支持的站点库格式版本集。
const stationLibrarySupportedFormatVersions = {'1'};

/// 门控站没导入时的统一话术（数据层抛错与界面引导共用口径）。
const stationLibraryLockedMessage =
    '未导入站点库，这个站还不能用：请先到数据库管理的「站点库」一节导入站点库';

class StationLibraryItem {
  const StationLibraryItem({
    required this.siteId,
    required this.kind,
    required this.section,
    required this.name,
    required this.assetPath,
    required this.sourceType,
    required this.extra,
    required this.content,
  });

  final String siteId;
  final String kind;
  final String section;
  final String name;
  final String assetPath;
  final int? sourceType;
  final Map<String, String> extra;
  final String content;
}

/// 站点库导入元信息（管理页展示用，模式同 ActressDbImportMeta：
/// 只记导入事件本身，没记录就是没导入过，不编造）。
class StationLibraryImportMeta {
  const StationLibraryImportMeta({
    required this.sourceName,
    required this.importedAtMillis,
    required this.libraryVersion,
    required this.itemCount,
    required this.requiredCoreLabel,
  });

  final String sourceName;
  final int importedAtMillis;
  final String libraryVersion;
  final int itemCount;
  final String requiredCoreLabel;

  DateTime get importedAt =>
      DateTime.fromMillisecondsSinceEpoch(importedAtMillis);

  Map<String, Object?> toJson() => {
    'sourceName': sourceName,
    'importedAtMillis': importedAtMillis,
    'libraryVersion': libraryVersion,
    'itemCount': itemCount,
    'requiredCoreLabel': requiredCoreLabel,
  };

  static StationLibraryImportMeta? fromJson(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      return StationLibraryImportMeta(
        sourceName: '${map['sourceName'] ?? ''}',
        importedAtMillis: (map['importedAtMillis'] as num?)?.toInt() ?? 0,
        libraryVersion: '${map['libraryVersion'] ?? ''}',
        itemCount: (map['itemCount'] as num?)?.toInt() ?? 0,
        requiredCoreLabel: '${map['requiredCoreLabel'] ?? ''}',
      );
    } catch (_) {
      return null;
    }
  }
}

const _kStationMetaKey = 'station_library_import_meta_v1';

Future<void> _saveStationImportMeta(StationLibraryImportMeta meta) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStationMetaKey, jsonEncode(meta.toJson()));
  } catch (_) {
    // 记不下不拦功能：管理页导入记录显示「未知」即可。
  }
}

Future<StationLibraryImportMeta?> loadStationImportMeta() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return StationLibraryImportMeta.fromJson(prefs.getString(_kStationMetaKey));
  } catch (_) {
    return null;
  }
}

Future<void> _clearStationImportMeta() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStationMetaKey);
  } catch (_) {}
}

/// 版本门结果：ok 时带全量条目与 meta 原文；不过时 error 是
/// 给用户看的中文原因（整单拒收、旧库一字不动）。
class StationLibraryGateResult {
  const StationLibraryGateResult({
    required this.ok,
    this.error,
    this.meta = const {},
    this.items = const [],
  });

  final bool ok;
  final String? error;
  final Map<String, String> meta;
  final List<StationLibraryItem> items;
}

/// 整库校验的规范串（与生成器 gen_station_sql.py 逐字一致）：
/// 先两行版本行，再按 site_id 排序逐行 id/TAB/kind/TAB/sha256。
String stationLibraryContentSha256({
  required String formatVersion,
  required String requiredCoreVersion,
  required List<({String siteId, String kind, String sha256})> rows,
}) {
  final sorted = [...rows]..sort((a, b) => a.siteId.compareTo(b.siteId));
  final canon = <String>[
    'format_version=$formatVersion',
    'required_core_version=$requiredCoreVersion',
    for (final row in sorted) '${row.siteId}\t${row.kind}\t${row.sha256}',
  ];
  return sha256.convert(utf8.encode('${canon.join('\n')}\n')).toString();
}

/// 签名载荷（与生成器逐字一致）：身份行 + 格式版本 + 所要求
/// 核心版本 + 整库校验值，四行 LF 分隔、无尾随换行。
List<int> stationLibrarySignaturePayload({
  required String formatVersion,
  required String requiredCoreVersion,
  required String contentSha256,
}) {
  return utf8.encode(
    '$stationLibraryFormat\n$formatVersion\n'
    '$requiredCoreVersion\n$contentSha256',
  );
}

/// 版本门：在已灌好数据的执行器上按钉死顺序验，任一步不过
/// 整单拒收。顺序：身份 → 格式版本 → 核心版本 → 条数 →
/// 逐行哈希 → 名单外整单拒 → 整库校验 → 整库签名（正式版
/// 新增，试点只有哈希：哈希防损坏/误改，签名防有人伪造一份
/// 自洽的假库替换名单内站点的代码）。
Future<StationLibraryGateResult> validateStationLibrary(
  SqlImportExecutor executor, {
  required Set<String> manifestIds,
  required int currentCoreVersion,
}) async {
  Map<String, String> meta;
  List<Map<String, Object?>> rows;
  try {
    final metaRows = await executor.query('SELECT key, value FROM station_meta');
    meta = {
      for (final row in metaRows)
        '${row['key']}': '${row['value'] ?? ''}',
    };
    rows = await executor.query(
      'SELECT site_id, kind, section, name, asset_path, source_type, '
      'extra_json, byte_len, sha256, content FROM station_items',
    );
  } catch (_) {
    return const StationLibraryGateResult(
      ok: false,
      error: '这个文件不是魔蚁站点库，无法导入到站点库位置。',
    );
  }
  // 1. 身份
  if (meta['format'] != stationLibraryFormat) {
    return const StationLibraryGateResult(
      ok: false,
      error: '这个文件不是魔蚁站点库，无法导入到站点库位置。',
    );
  }
  // 2. 格式版本
  final formatVersion = meta['format_version'] ?? '';
  if (!stationLibrarySupportedFormatVersions.contains(formatVersion)) {
    return const StationLibraryGateResult(
      ok: false,
      error: '这个站点库的格式版本不受当前 App 支持，请更新魔蚁后再导入。',
    );
  }
  // 3. 核心版本门
  final requiredCoreVersion = meta['required_core_version'] ?? '';
  final requiredCore = int.tryParse(requiredCoreVersion) ?? 0;
  if (currentCoreVersion < requiredCore) {
    final label = meta['required_core_label'] ?? requiredCoreVersion;
    return StationLibraryGateResult(
      ok: false,
      error: '这个站点库要求 App 版本不低于 $label，'
          '当前版本较低，请先更新魔蚁再导入。',
    );
  }
  // 4. 条数
  final declaredCount = int.tryParse(meta['item_count'] ?? '') ?? -1;
  if (declaredCount != rows.length) {
    return const StationLibraryGateResult(
      ok: false,
      error: '站点库条数对不上，文件可能不完整，已拒绝导入。',
    );
  }
  // 5. 逐行哈希（顺带把条目读出来，验过才交给上层）
  final items = <StationLibraryItem>[];
  final digestRows = <({String siteId, String kind, String sha256})>[];
  for (final row in rows) {
    final siteId = '${row['site_id'] ?? ''}';
    final content = '${row['content'] ?? ''}';
    final raw = utf8.encode(content);
    final byteLen = (row['byte_len'] as num?)?.toInt() ?? -1;
    final rowSha = '${row['sha256'] ?? ''}';
    if (raw.length != byteLen || sha256.convert(raw).toString() != rowSha) {
      return StationLibraryGateResult(
        ok: false,
        error: '站点库内容校验失败（$siteId），文件可能已损坏，已拒绝导入。',
      );
    }
    Map<String, String> extra = const {};
    final extraJson = '${row['extra_json'] ?? ''}'.trim();
    if (extraJson.isNotEmpty && extraJson != '{}') {
      try {
        final decoded = jsonDecode(extraJson);
        if (decoded is Map) {
          extra = {
            for (final entry in decoded.entries)
              '${entry.key}': '${entry.value ?? ''}',
          };
        }
      } catch (_) {
        return StationLibraryGateResult(
          ok: false,
          error: '站点库内容校验失败（$siteId），文件可能已损坏，已拒绝导入。',
        );
      }
    }
    final kind = '${row['kind'] ?? ''}';
    items.add(
      StationLibraryItem(
        siteId: siteId,
        kind: kind,
        section: '${row['section'] ?? ''}',
        name: '${row['name'] ?? ''}',
        assetPath: '${row['asset_path'] ?? ''}',
        sourceType: (row['source_type'] as num?)?.toInt(),
        extra: extra,
        content: content,
      ),
    );
    digestRows.add((siteId: siteId, kind: kind, sha256: rowSha));
  }
  // 6. 名单外整单拒
  for (final item in items) {
    if (!manifestIds.contains(item.siteId)) {
      return StationLibraryGateResult(
        ok: false,
        error: '站点库里有名单外的站点（${item.siteId}），已整库拒绝导入。',
      );
    }
  }
  // 7. 整库校验
  final digest = stationLibraryContentSha256(
    formatVersion: formatVersion,
    requiredCoreVersion: requiredCoreVersion,
    rows: digestRows,
  );
  if (digest != (meta['content_sha256'] ?? '')) {
    return const StationLibraryGateResult(
      ok: false,
      error: '站点库整体校验失败，文件可能被改动，已拒绝导入。',
    );
  }
  // 8. 整库签名（正式版必须有；缺失或验不过一律拒）
  final signature = meta['signature'] ?? '';
  if (meta['sign_alg'] != 'ed25519' || signature.isEmpty) {
    return const StationLibraryGateResult(
      ok: false,
      error: '站点库缺少有效的整库签名，无法确认来源，已拒绝导入。',
    );
  }
  final payload = stationLibrarySignaturePayload(
    formatVersion: formatVersion,
    requiredCoreVersion: requiredCoreVersion,
    contentSha256: digest,
  );
  if (!verifyStationLibrarySignature(
    payload: payload,
    signatureHex: signature,
  )) {
    return const StationLibraryGateResult(
      ok: false,
      error: '站点库签名校验失败，文件来源不可信，已拒绝导入。',
    );
  }
  return StationLibraryGateResult(ok: true, meta: meta, items: items);
}

/// 站点库导入结果。error 为 null 且 ok=false 且 cancelled=true
/// 表示用户没选文件/中途取消，不是失败。
class StationLibraryImportResult {
  const StationLibraryImportResult({
    required this.ok,
    this.error,
    this.meta,
    this.itemCount = 0,
    this.cancelled = false,
  });

  final bool ok;
  final String? error;
  final StationLibraryImportMeta? meta;
  final int itemCount;
  final bool cancelled;
}

class _StationImportCancelled implements Exception {
  const _StationImportCancelled();
}

String _stationStatementHead(String sql) {
  final trimmed = sql.trimLeft();
  final end = trimmed.indexOf(RegExp(r'[\s(]'));
  final head = end < 0 ? trimmed : trimmed.substring(0, end);
  return head.toUpperCase();
}

bool _stationIsStatisticsStatement(String sql) {
  final upper = sql.toUpperCase();
  return upper.contains('SQLITE_STAT') ||
      upper.contains('DBSTAT') ||
      upper.startsWith('ANALYZE');
}

/// 站点库导入器：照演员库导入器的「流式进临时库 → 临时库上
/// 跑完全部门 → 全过才改名顶替、旧库留 .bak」骨架，但语句
/// 执行失败一条都不许吞——站点库装的是代码，缺一行都拒。
class StationLibraryImporter {
  StationLibraryImporter({this.executorFactory});

  final Future<SqlImportExecutor> Function(String dbPath)? executorFactory;

  static const int batchSize = 200;

  Future<SqlImportExecutor> _openExecutor(String dbPath) async {
    final factory = executorFactory;
    if (factory != null) return factory(dbPath);
    final db = await openDatabase(dbPath, singleInstance: false);
    return SqfliteImportExecutor(db);
  }

  Future<StationLibraryImportResult> importFile({
    required String sqlPath,
    required String dbPath,
    required Set<String> manifestIds,
    required int currentCoreVersion,
    String sourceName = '',
    void Function(int statements)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final tempPath = '$dbPath.importing';
    SqlImportExecutor? executor;
    try {
      final source = File(sqlPath);
      if (!await source.exists()) {
        return const StationLibraryImportResult(
          ok: false,
          error: '找不到站点库文件，请重新选择。',
        );
      }
      if (await source.length() == 0) {
        return const StationLibraryImportResult(
          ok: false,
          error: '站点库文件是空的，已拒绝导入。',
        );
      }
      final temp = File(tempPath);
      if (await temp.exists()) await temp.delete();

      executor = await _openExecutor(tempPath);
      final exec = executor;
      for (final pragma in const [
        'PRAGMA journal_mode=OFF',
        'PRAGMA synchronous=OFF',
        'PRAGMA temp_store=MEMORY',
        'PRAGMA cache_size=-65536',
        'PRAGMA locking_mode=EXCLUSIVE',
      ]) {
        try {
          await exec.execute(pragma);
        } catch (_) {}
      }

      final lower = sqlPath.toLowerCase();
      Stream<String> lines;
      if (lower.endsWith('.gz')) {
        lines = source
            .openRead()
            .transform(gzip.decoder)
            .transform(utf8.decoder)
            .transform(const LineSplitter());
      } else {
        lines = source
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter());
      }
      final splitter = SqlStatementSplitter();
      var executed = 0;
      var skipped = 0;
      var pendingInserts = <String>[];

      Future<void> flushInserts() async {
        if (pendingInserts.isEmpty) return;
        await exec.executeBatch(pendingInserts);
        executed += pendingInserts.length;
        pendingInserts = <String>[];
        onProgress?.call(executed);
      }

      await for (final line in lines) {
        if (isCancelled?.call() == true) {
          throw const _StationImportCancelled();
        }
        for (final statement in splitter.addLine(line)) {
          final head = _stationStatementHead(statement);
          if (head == 'BEGIN' || head == 'COMMIT' || head == 'END') {
            continue;
          }
          if (_stationIsStatisticsStatement(statement)) {
            skipped++;
            continue;
          }
          if (head == 'INSERT') {
            pendingInserts.add(statement);
            if (pendingInserts.length >= batchSize) {
              await flushInserts();
            }
          } else {
            await flushInserts();
            await exec.execute(statement);
            executed++;
          }
        }
      }
      final tail = splitter.flush();
      if (tail != null) {
        final head = _stationStatementHead(tail);
        if (head != 'BEGIN' &&
            head != 'COMMIT' &&
            head != 'END' &&
            !_stationIsStatisticsStatement(tail)) {
          if (head == 'INSERT') {
            pendingInserts.add(tail);
          } else {
            await flushInserts();
            await exec.execute(tail);
            executed++;
          }
        }
      }
      await flushInserts();
      if (isCancelled?.call() == true) {
        throw const _StationImportCancelled();
      }
      if (skipped > 0) {
        // 统计语句本不该出现在站点库成品里；出现了说明文件
        // 不是生成器直出，宁可拒、不带病激活代码。
        return const StationLibraryImportResult(
          ok: false,
          error: '站点库文件含有不该有的语句，已拒绝导入。',
        );
      }

      final gate = await validateStationLibrary(
        exec,
        manifestIds: manifestIds,
        currentCoreVersion: currentCoreVersion,
      );
      if (!gate.ok) {
        return StationLibraryImportResult(ok: false, error: gate.error);
      }
      await exec.close();
      executor = null;

      // 全门通过：改名顶替，旧库留 .bak。
      final dbFile = File(dbPath);
      final backup = File('$dbPath.bak');
      if (await dbFile.exists()) {
        if (await backup.exists()) await backup.delete();
        await dbFile.rename(backup.path);
      }
      try {
        await File(tempPath).rename(dbPath);
      } catch (_) {
        if (!await dbFile.exists() && await backup.exists()) {
          await backup.rename(dbPath);
        }
        return const StationLibraryImportResult(
          ok: false,
          error: '站点库保存失败，请检查手机存储空间后重试。',
        );
      }
      final meta = StationLibraryImportMeta(
        sourceName: sourceName.isEmpty
            ? path.basename(sqlPath)
            : sourceName,
        importedAtMillis: DateTime.now().millisecondsSinceEpoch,
        libraryVersion: gate.meta['library_version'] ?? '',
        itemCount: gate.items.length,
        requiredCoreLabel: gate.meta['required_core_label'] ?? '',
      );
      return StationLibraryImportResult(
        ok: true,
        meta: meta,
        itemCount: gate.items.length,
      );
    } on _StationImportCancelled {
      return const StationLibraryImportResult(
        ok: false,
        cancelled: true,
        error: '已取消导入，现有站点库没有变化。',
      );
    } catch (_) {
      return const StationLibraryImportResult(
        ok: false,
        error: '站点库文件读取失败，可能已损坏或不是有效的站点库文件。',
      );
    } finally {
      try {
        await executor?.close();
      } catch (_) {}
      try {
        final temp = File(tempPath);
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }
}

/// 站点库当前状态与数据出口：App 内各处只从这里问「导没导、
/// 某站有没有、内容是什么」。状态在首次 ensureLoaded 时从
/// station_library.db 只读加载进内存；导入/删除/恢复后同步
/// 刷新并 bump [generation]——数据层缓存（py 落盘路径、legado
/// JSON）按 generation 失效，保证换库立刻生效不用重启。
class StationLibrary {
  StationLibrary._();

  /// 测试接缝：覆盖数据库路径（配合 mock path_provider 也可）。
  @visibleForTesting
  static String? debugDbPathOverride;

  /// 测试接缝：直接设定内存中的站点库状态（绕过盘上加载）。
  @visibleForTesting
  static void debugSetItems(List<StationLibraryItem> items) {
    _items = {for (final item in items) item.siteId: item};
    _loaded = true;
    generation.value++;
  }

  /// 状态代次：导入/删除/恢复成功后 +1。界面可监听刷新。
  static final ValueNotifier<int> generation = ValueNotifier<int>(0);

  static Map<String, StationLibraryItem> _items = const {};
  static bool _loaded = false;
  static Future<void>? _loading;

  static Future<String> dbPath() async {
    final override = debugDbPathOverride;
    if (override != null) return override;
    final dir = await getApplicationSupportDirectory();
    return path.join(dir.path, 'station_library.db');
  }

  static Future<String> backupPath() async => '${await dbPath()}.bak';

  /// 当前 App 的核心版本（安装序号）：运行时读原生侧 build 号，
  /// 读不到记 0（版本门会因此拒收需要更高版本的库，属保守侧）。
  static Future<int> currentCoreVersion() async {
    try {
      final info = await AppUpdateChannel.appInfo();
      return info.build;
    } catch (_) {
      return 0;
    }
  }

  static bool get isImported => _items.isNotEmpty;

  static int get itemCount => _items.length;

  static bool provides(String siteId) => _items.containsKey(siteId);

  static StationLibraryItem? itemOf(String siteId) => _items[siteId];

  static String? contentOf(String siteId) => _items[siteId]?.content;

  /// 幂等加载：库文件在就只读打开取数；不在就是未导入态。
  /// 已在盘上落定的库都是导入时全门验过的，加载时不再重验
  /// 签名（与女优库导入后直读同口径）。
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<void> _load() async {
    try {
      final dbFile = File(await dbPath());
      if (!await dbFile.exists()) {
        _items = const {};
        _loaded = true;
        return;
      }
      final db = await openDatabase(dbFile.path, readOnly: true);
      try {
        final rows = await db.query('station_items');
        _items = {
          for (final row in rows)
            '${row['site_id']}': StationLibraryItem(
              siteId: '${row['site_id']}',
              kind: '${row['kind']}',
              section: '${row['section'] ?? ''}',
              name: '${row['name'] ?? ''}',
              assetPath: '${row['asset_path'] ?? ''}',
              sourceType: (row['source_type'] as num?)?.toInt(),
              extra: _decodeExtra(row['extra_json']),
              content: '${row['content'] ?? ''}',
            ),
        };
      } finally {
        await db.close();
      }
    } catch (_) {
      // 库文件损坏到读不出：按未导入处理（名单行回灰），
      // 用户可在管理页删除或重新导入，不许因此崩。
      _items = const {};
    }
    _loaded = true;
  }

  static Map<String, String> _decodeExtra(Object? raw) {
    final text = '${raw ?? ''}'.trim();
    if (text.isEmpty || text == '{}') return const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            '${entry.key}': '${entry.value ?? ''}',
        };
      }
    } catch (_) {}
    return const {};
  }

  static Future<bool> backupExists() async =>
      File(await backupPath()).exists();

  /// 选文件并导入（内容区引导与管理页共用入口）。
  static Future<StationLibraryImportResult> pickAndImport({
    required Set<String> manifestIds,
    required int currentCoreVersion,
    StationLibraryImporter? importer,
    void Function(int statements)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    final filePath = files.isNotEmpty ? files.first.path : null;
    if (filePath == null || filePath.isEmpty) {
      return const StationLibraryImportResult(ok: false, cancelled: true);
    }
    final lower = filePath.toLowerCase();
    if (!lower.endsWith('.sql') && !lower.endsWith('.sql.gz')) {
      return const StationLibraryImportResult(
        ok: false,
        error: '请选择站点库文件（.sql 或 .sql.gz）。',
      );
    }
    return importPickedFile(
      filePath,
      manifestIds: manifestIds,
      currentCoreVersion: currentCoreVersion,
      importer: importer,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  static Future<StationLibraryImportResult> importPickedFile(
    String filePath, {
    required Set<String> manifestIds,
    required int currentCoreVersion,
    StationLibraryImporter? importer,
    void Function(int statements)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final result = await (importer ?? StationLibraryImporter()).importFile(
      sqlPath: filePath,
      dbPath: await dbPath(),
      manifestIds: manifestIds,
      currentCoreVersion: currentCoreVersion,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (result.ok && result.meta != null) {
      await _saveStationImportMeta(result.meta!);
      await _reloadFromDisk();
    }
    return result;
  }

  static Future<void> _reloadFromDisk() async {
    _loaded = false;
    await _load();
    generation.value++;
  }

  /// 删除站点库：库文件与 .bak 一并删，听读 py 的落盘副本
  /// 一并清掉（否则旧代码文件还躺在私有目录里）。女优库、
  /// 磁力库不在此列、不受影响。删后名单行回灰（未导入态）。
  static Future<void> deleteLibrary() async {
    final landedIds = [
      for (final item in _items.values)
        if (item.kind == 'audio_py') item.siteId,
    ];
    final dbFile = File(await dbPath());
    if (await dbFile.exists()) await dbFile.delete();
    final backup = File(await backupPath());
    if (await backup.exists()) await backup.delete();
    for (final siteId in landedIds) {
      try {
        await ImportFileStore.delete('builtin_$siteId.py');
      } catch (_) {}
    }
    _items = const {};
    _loaded = true;
    generation.value++;
    await _clearStationImportMeta();
  }

  /// 回退上一版：.bak 先过一遍完整版本门（含验签），过了才
  /// 顶替当前库；不过什么都不动、把中文原因带回去。
  static Future<StationLibraryImportResult> restoreBackup({
    required Set<String> manifestIds,
    required int currentCoreVersion,
    Future<SqlImportExecutor> Function(String dbPath)? executorFactory,
  }) async {
    final bak = await backupPath();
    if (!await File(bak).exists()) {
      return const StationLibraryImportResult(
        ok: false,
        error: '没有可回退的上一版站点库。',
      );
    }
    SqlImportExecutor? executor;
    StationLibraryGateResult gate;
    try {
      final factory =
          executorFactory ??
          (String dbPath) async {
            final db = await openDatabase(
              dbPath,
              readOnly: true,
              singleInstance: false,
            );
            return SqfliteImportExecutor(db);
          };
      executor = await factory(bak);
      gate = await validateStationLibrary(
        executor,
        manifestIds: manifestIds,
        currentCoreVersion: currentCoreVersion,
      );
      if (!gate.ok) {
        return StationLibraryImportResult(
          ok: false,
          error: '上一版站点库校验不过（${gate.error}），已保持现状。',
        );
      }
    } finally {
      try {
        await executor?.close();
      } catch (_) {}
    }
    final target = await dbPath();
    final dbFile = File(target);
    if (await dbFile.exists()) await dbFile.delete();
    await File(bak).rename(target);
    await _reloadFromDisk();
    await _saveStationImportMeta(
      StationLibraryImportMeta(
        sourceName: '上一版备份（恢复）',
        importedAtMillis: DateTime.now().millisecondsSinceEpoch,
        libraryVersion: gate.meta['library_version'] ?? '',
        itemCount: _items.length,
        requiredCoreLabel: gate.meta['required_core_label'] ?? '',
      ),
    );
    return StationLibraryImportResult(ok: true, itemCount: _items.length);
  }
}
