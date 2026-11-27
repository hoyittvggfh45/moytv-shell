import 'package:sqflite/sqflite.dart';

import 'actress_sql_import.dart';

/// 磁力分类库（2026-11-27 用户令）：磁力表格转出的 .sql 并存
/// 导入女优库——导入是往现有工作库里「加」，绝不覆盖/清空
/// 主库；演员库分类栏按已导入的分类动态增减（没导入不显
/// 示）；在数据库管理里删掉某个分类，它带来的作品随之消
/// 失，主库原有作品一条不动。交付形态以 18:09 续令为准：
/// 一个合集 .sql、分类靠库内 main_category 字段区分，导入
/// 时按分类逐片登记（早先的一类一个文件同样适用，片数=1）。
///
/// 并存的落法是「来源登记」：合并时先把临时库（.sql 已由
/// [ActressSqlImporter] 验过并落成标准结构）里每部作品、每条
/// 线路、每位演员在主库里是否已存在记进 magnet_library_*
/// 登记表，再 INSERT OR IGNORE 并进标准表。分类页的口径是
/// 「主分类 ∪ 来源登记」（见 actress_film_library 的分类谓
/// 词）：同番号作品在主库已有别的分类时，磁力分类页照样能
/// 看到它（样本里 95.9% 的番号与主库重合，只按 video_category
/// 并入的话分类页只剩 4% 新作品，不是用户要的「导入即全量
/// 显示该分类」）。删库时按登记表反向删：本库独有（导入前
/// 不存在、且没有别的磁力库也带它）的作品整部删；与主库或
/// 别的磁力库共享的作品只摘掉本库贡献的磁力线路。

/// 磁力线路在 video_play_urls.play_from 里的标记值（与转换批
/// 对齐用）。判定主尺是播放地址本身以 magnet: 开头——格式级
/// 事实，不依赖标记；play_from 标记是第二道尺，两道任一命中
/// 都算磁力线路。
const actressMagnetPlayFrom = 'magnet';

bool actressIsMagnetPlayUrl(String url) =>
    url.trim().toLowerCase().startsWith('magnet:');

bool actressIsMagnetPlayFrom(String from) {
  final value = from.trim().toLowerCase();
  return value == actressMagnetPlayFrom ||
      value.startsWith(actressMagnetPlayFrom);
}

/// 一条播放线路（video_play_urls 的一行）。
class ActressPlayLine {
  const ActressPlayLine({required this.url, required this.from});

  final String url;
  final String from;

  bool get isMagnet =>
      actressIsMagnetPlayUrl(url) || actressIsMagnetPlayFrom(from);
}

/// 已导入的一个磁力分类库的登记。
class MagnetLibraryRecord {
  const MagnetLibraryRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.sourceName,
    required this.importedAtMillis,
    required this.works,
    required this.playUrls,
  });

  final int id;

  /// 库名＝导入文件名（去后缀），同名重导＝更新这个库。
  final String name;

  /// 分类名（取库内 main_category；取不到时就是库名）。
  final String category;

  /// 来源文件名（展示用）。
  final String sourceName;

  final int importedAtMillis;

  /// 本库带来的作品数（含与主库重合的）。
  final int works;

  /// 本库带来的线路数。
  final int playUrls;
}

/// 并存合并的结果。
class MagnetMergeResult {
  const MagnetMergeResult({
    required this.ok,
    this.error,
    this.libraryId = 0,
    this.name = '',
    this.category = '',
    this.categories = const [],
    this.addedWorks = 0,
    this.totalWorks = 0,
    this.addedPlayUrls = 0,
    this.replaced = false,
  });

  final bool ok;
  final String? error;

  /// 第一个分类切片的登记 id（多切片时仅作参考）。
  final int libraryId;
  final String name;

  /// 只有一个分类切片时就是它；多切片时为空，看 [categories]。
  final String category;

  /// 本次导入登记的全部分类（一个 .sql 里有几个主分类就有
  /// 几个，逐个登记、逐个可删）。
  final List<String> categories;

  /// 真正新增进主库的作品数（导入前不存在的）。
  final int addedWorks;

  /// 本次收录的作品总数（含与主库重合的）。
  final int totalWorks;

  /// 真正新增的线路数。
  final int addedPlayUrls;

  /// 同名分类已存在、这次是更新（先删旧登记再并入）。
  final bool replaced;
}

/// 删库的结果。
class MagnetRemoveResult {
  const MagnetRemoveResult({
    required this.removedWorks,
    required this.removedPlayUrls,
  });

  /// 整部删掉的作品数（本库独有的）。
  final int removedWorks;

  /// 摘掉的线路数（含共享作品上本库贡献的磁力线路）。
  final int removedPlayUrls;
}

/// 库名＝文件名去后缀（.sql / .sql.gz / .gz 都剥）。
String magnetLibraryNameOfFile(String path) {
  var name = path.split('/').last.split('\\').last;
  final lower = name.toLowerCase();
  if (lower.endsWith('.sql.gz')) {
    name = name.substring(0, name.length - 7);
  } else if (lower.endsWith('.sql')) {
    name = name.substring(0, name.length - 4);
  } else if (lower.endsWith('.gz')) {
    name = name.substring(0, name.length - 3);
  }
  return name.trim();
}

/// 磁力分类库存储口：生产实现走 sqflite，测试可注入内存假实现。
abstract class MagnetLibraryStore {
  /// 已导入的磁力分类库（按导入时间倒序）。
  Future<List<MagnetLibraryRecord>> listLibraries();

  /// 把已落盘的临时库（stagingPath，标准结构）并存合并进主库。
  /// 不是磁力库（一条磁力线路都没有）时 ok=false、主库不动。
  Future<MagnetMergeResult> mergeFromStaging({
    required String stagingPath,
    required String name,
    required String sourceName,
  });

  /// 删除一个已导入的磁力分类库（语义见文件头）。
  Future<MagnetRemoveResult> removeLibrary(int libraryId);

  Future<void> close();
}

/// 来源登记表建表语句（落在工作库里，与标准表同库）。
const magnetLibraryDdl = <String>[
  'CREATE TABLE IF NOT EXISTS magnet_libraries ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'name TEXT NOT NULL UNIQUE, '
      "category TEXT NOT NULL DEFAULT '', "
      "source_name TEXT NOT NULL DEFAULT '', "
      'imported_at INTEGER NOT NULL DEFAULT 0, '
      'works INTEGER NOT NULL DEFAULT 0, '
      'play_urls INTEGER NOT NULL DEFAULT 0)',
  'CREATE TABLE IF NOT EXISTS magnet_library_works ('
      'library_id INTEGER NOT NULL, '
      'vod_id TEXT NOT NULL, '
      'was_existing INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (library_id, vod_id))',
  'CREATE TABLE IF NOT EXISTS magnet_library_play_urls ('
      'library_id INTEGER NOT NULL, '
      'vod_id TEXT NOT NULL, '
      'play_url TEXT NOT NULL, '
      'was_existing INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (library_id, vod_id, play_url))',
  'CREATE TABLE IF NOT EXISTS magnet_library_actresses ('
      'library_id INTEGER NOT NULL, '
      'cate_id TEXT NOT NULL, '
      'was_existing INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (library_id, cate_id))',
  // 分类行也要登记来源：主库里原本没有分类行的共享作品，
  // 并入时会吃进本库的分类行；删库时不摘掉它，这个分类就
  // 会在分类栏里阴魂不散（删库分类必须消失）。
  'CREATE TABLE IF NOT EXISTS magnet_library_categories ('
      'library_id INTEGER NOT NULL, '
      'vod_id TEXT NOT NULL, '
      'main_category TEXT NOT NULL DEFAULT \'\', '
      'was_existing INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (library_id, vod_id))',
];

Future<void> ensureMagnetLibraryTables(DatabaseExecutor db) async {
  for (final ddl in magnetLibraryDdl) {
    await db.execute(ddl);
  }
}

/// sqflite 实现：在工作库路径上单独开一条连接（与表格更新
/// 同款），合并/删库都在事务里做完，完了重建名册汇总表
/// （actress_rollup），读侧口径与整库导入后一致。
class SqfliteMagnetLibraryStore implements MagnetLibraryStore {
  SqfliteMagnetLibraryStore(this._db);

  final Database _db;

  static Future<SqfliteMagnetLibraryStore> openPath(String dbPath) async =>
      SqfliteMagnetLibraryStore(await openDatabase(dbPath));

  @override
  Future<void> close() => _db.close();

  @override
  Future<List<MagnetLibraryRecord>> listLibraries() async {
    await ensureMagnetLibraryTables(_db);
    final rows = await _db.query(
      'magnet_libraries',
      orderBy: 'imported_at DESC, id DESC',
    );
    return [for (final row in rows) _recordFromRow(row)];
  }

  MagnetLibraryRecord _recordFromRow(Map<String, Object?> row) =>
      MagnetLibraryRecord(
        id: (row['id'] as num?)?.toInt() ?? 0,
        name: row['name']?.toString() ?? '',
        category: row['category']?.toString() ?? '',
        sourceName: row['source_name']?.toString() ?? '',
        importedAtMillis: (row['imported_at'] as num?)?.toInt() ?? 0,
        works: (row['works'] as num?)?.toInt() ?? 0,
        playUrls: (row['play_urls'] as num?)?.toInt() ?? 0,
      );

  Future<bool> _tableExists(
    DatabaseExecutor db,
    String table, {
    String schema = '',
  }) async {
    final rows = await db.rawQuery(
      "SELECT name FROM ${schema}sqlite_master "
      "WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  @override
  Future<MagnetMergeResult> mergeFromStaging({
    required String stagingPath,
    required String name,
    required String sourceName,
  }) async {
    await _db.execute('ATTACH DATABASE ? AS mstage', [stagingPath]);
    try {
      // 先验：临时库里得有磁力线路，否则这不是磁力分类库，
      // 整库 .sql 走「导入数据库」的替换路，别在这里并掉。
      var magnetCount = 0;
      if (await _tableExists(_db, 'video_play_urls', schema: 'mstage.')) {
        final rows = await _db.rawQuery(
          'SELECT COUNT(*) AS c FROM mstage.video_play_urls '
          "WHERE LOWER(TRIM(play_url)) LIKE 'magnet:%'",
        );
        magnetCount = (rows.first['c'] as num?)?.toInt() ?? 0;
        if (magnetCount == 0) {
          // 第二道尺：play_from 标记（地址形态异常时兜底）。
          try {
            final marked = await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM mstage.video_play_urls '
              'WHERE LOWER(TRIM(play_from)) = ?',
              [actressMagnetPlayFrom],
            );
            magnetCount = (marked.first['c'] as num?)?.toInt() ?? 0;
          } catch (_) {
            // play_from 列都没有：按地址尺的结论走。
          }
        }
      }
      if (magnetCount == 0) {
        return const MagnetMergeResult(
          ok: false,
          error: '这个文件里没有磁力链接，不是磁力分类库；'
              '整库数据库请用上面的「导入数据库」',
        );
      }
      // 分类切片（2026-11-27 18:09 续令：交付形态改成一个
      // 合集 .sql、分类靠库内字段区分）：临时库里有几个主
      // 分类就切几个片、逐片登记，删的时候也逐片删；一类
      // 一个文件时只有一个片，行为与逐个导入一致。没有分
      // 类行的作品归以文件名命名的兜底片。
      final realCategories = <String>[];
      if (await _tableExists(_db, 'video_category', schema: 'mstage.')) {
        final rows = await _db.rawQuery(
          'SELECT main_category FROM mstage.video_category '
          "WHERE TRIM(COALESCE(main_category, '')) <> '' "
          'GROUP BY main_category ORDER BY main_category',
        );
        realCategories.addAll([
          for (final row in rows) row['main_category'].toString(),
        ]);
      }
      var hasUncategorized = realCategories.isEmpty;
      if (!hasUncategorized) {
        final rows = await _db.rawQuery(
          'SELECT COUNT(*) AS c FROM mstage.videos s '
          'LEFT JOIN mstage.video_category c ON c.vod_id = s.vod_id '
          "WHERE c.vod_id IS NULL "
          "OR TRIM(COALESCE(c.main_category, '')) = ''",
        );
        hasUncategorized = ((rows.first['c'] as num?)?.toInt() ?? 0) > 0;
      }
      final slices = <String>[...realCategories];
      if (hasUncategorized && !slices.contains(name)) slices.add(name);
      if (slices.isEmpty) slices.add(name);

      late MagnetMergeResult result;
      await _db.transaction((txn) async {
        await ensureMagnetLibraryTables(txn);
        // 同名分类重导＝更新那个分类：先按删库语义摘掉旧的。
        var replaced = false;
        final libraryIds = <String, int>{};
        final importedAt = DateTime.now().millisecondsSinceEpoch;
        for (final slice in slices) {
          final existing = await txn.query(
            'magnet_libraries',
            columns: ['id'],
            where: 'name = ?',
            whereArgs: [slice],
          );
          if (existing.isNotEmpty) {
            await _removeLibraryInTxn(
              txn,
              (existing.first['id'] as num).toInt(),
            );
            replaced = true;
          }
          libraryIds[slice] = await txn.insert('magnet_libraries', {
            'name': slice,
            'category': slice,
            'source_name': sourceName,
            'imported_at': importedAt,
          });
        }
        // 来源登记：并入前先记下每行在主库里是否已存在。
        // 作品按它在临时库里的主分类归片；线路/演员/分类行
        // 跟着作品的归片走。
        for (final entry in libraryIds.entries) {
          final slice = entry.key;
          final libraryId = entry.value;
          final isRealSlice = realCategories.contains(slice);
          if (isRealSlice) {
            await txn.execute(
              'INSERT OR IGNORE INTO magnet_library_works '
              '(library_id, vod_id, was_existing) '
              'SELECT ?, s.vod_id, CASE WHEN EXISTS ('
              'SELECT 1 FROM videos v WHERE v.vod_id = s.vod_id'
              ') THEN 1 ELSE 0 END FROM mstage.videos s '
              'JOIN mstage.video_category c ON c.vod_id = s.vod_id '
              'WHERE c.main_category = ?',
              [libraryId, slice],
            );
          }
          if (!isRealSlice || slice == name) {
            // 兜底片（以及与文件名同名的真分类片）收没有
            // 分类行的作品。
            await txn.execute(
              'INSERT OR IGNORE INTO magnet_library_works '
              '(library_id, vod_id, was_existing) '
              'SELECT ?, s.vod_id, CASE WHEN EXISTS ('
              'SELECT 1 FROM videos v WHERE v.vod_id = s.vod_id'
              ') THEN 1 ELSE 0 END FROM mstage.videos s '
              'LEFT JOIN mstage.video_category c '
              'ON c.vod_id = s.vod_id '
              "WHERE c.vod_id IS NULL "
              "OR TRIM(COALESCE(c.main_category, '')) = ''",
              [libraryId],
            );
          }
          await txn.execute(
            'INSERT OR IGNORE INTO magnet_library_play_urls '
            '(library_id, vod_id, play_url, was_existing) '
            'SELECT ?, s.vod_id, s.play_url, CASE WHEN EXISTS ('
            'SELECT 1 FROM video_play_urls u '
            'WHERE u.vod_id = s.vod_id AND u.play_url = s.play_url'
            ') THEN 1 ELSE 0 END FROM mstage.video_play_urls s '
            'JOIN magnet_library_works w '
            'ON w.library_id = ? AND w.vod_id = s.vod_id',
            [libraryId, libraryId],
          );
          await txn.execute(
            'INSERT OR IGNORE INTO magnet_library_actresses '
            '(library_id, cate_id, was_existing) '
            'SELECT ?, va.cate_id, CASE WHEN EXISTS ('
            'SELECT 1 FROM actresses a WHERE a.cate_id = va.cate_id'
            ') THEN 1 ELSE 0 END '
            'FROM (SELECT DISTINCT cate_id, vod_id '
            'FROM mstage.video_actress) va '
            'JOIN magnet_library_works w '
            'ON w.library_id = ? AND w.vod_id = va.vod_id',
            [libraryId, libraryId],
          );
          await txn.execute(
            'INSERT OR IGNORE INTO magnet_library_categories '
            '(library_id, vod_id, main_category, was_existing) '
            'SELECT ?, s.vod_id, s.main_category, CASE WHEN EXISTS ('
            'SELECT 1 FROM video_category c WHERE c.vod_id = s.vod_id'
            ') THEN 1 ELSE 0 END FROM mstage.video_category s '
            'JOIN magnet_library_works w '
            'ON w.library_id = ? AND w.vod_id = s.vod_id',
            [libraryId, libraryId],
          );
        }
        // 并入标准表：已有的行一律不覆盖（主库为准）。
        await txn.execute(
          'INSERT OR IGNORE INTO actresses '
          '(cate_id, name, avatar, created_at, sex, roster_id, claimed) '
          'SELECT cate_id, name, avatar, created_at, sex, roster_id, '
          'claimed FROM mstage.actresses',
        );
        await txn.execute(
          'INSERT OR IGNORE INTO videos '
          '(vod_id, title, pic_url, m3u8_url, vod_remarks, vod_pubdate, '
          'vod_area, vod_year, vod_content, vod_play_from, vod_play_url, '
          'type_name, created_at) '
          'SELECT vod_id, title, pic_url, m3u8_url, vod_remarks, '
          'vod_pubdate, vod_area, vod_year, vod_content, vod_play_from, '
          'vod_play_url, type_name, created_at FROM mstage.videos',
        );
        await txn.execute(
          'INSERT OR IGNORE INTO video_actress (vod_id, cate_id) '
          'SELECT vod_id, cate_id FROM mstage.video_actress',
        );
        await txn.execute(
          'INSERT OR IGNORE INTO video_play_urls '
          '(vod_id, play_url, play_from) '
          'SELECT vod_id, play_url, play_from FROM mstage.video_play_urls',
        );
        await txn.execute(
          'INSERT OR IGNORE INTO video_category (vod_id, main_category) '
          'SELECT vod_id, main_category FROM mstage.video_category',
        );
        if (await _tableExists(txn, 'video_tag') &&
            await _tableExists(txn, 'video_tag', schema: 'mstage.')) {
          await txn.execute(
            'INSERT OR IGNORE INTO video_tag (vod_id, tag_name) '
            'SELECT vod_id, tag_name FROM mstage.video_tag',
          );
        }
        var totalWorks = 0;
        var addedWorks = 0;
        var addedUrls = 0;
        for (final libraryId in libraryIds.values) {
          final sliceWorks = await _countWhere(
            txn,
            'magnet_library_works',
            libraryId,
          );
          final sliceUrls = await _countWhere(
            txn,
            'magnet_library_play_urls',
            libraryId,
          );
          totalWorks += sliceWorks;
          addedWorks += await _countWhere(
            txn,
            'magnet_library_works',
            libraryId,
            onlyNew: true,
          );
          addedUrls += await _countWhere(
            txn,
            'magnet_library_play_urls',
            libraryId,
            onlyNew: true,
          );
          await txn.update(
            'magnet_libraries',
            {'works': sliceWorks, 'play_urls': sliceUrls},
            where: 'id = ?',
            whereArgs: [libraryId],
          );
        }
        result = MagnetMergeResult(
          ok: true,
          libraryId: libraryIds.values.first,
          name: name,
          category: slices.length == 1 ? slices.single : '',
          categories: slices,
          addedWorks: addedWorks,
          totalWorks: totalWorks,
          addedPlayUrls: addedUrls,
          replaced: replaced,
        );
      });
      await _rebuildRollupQuietly();
      return result;
    } finally {
      try {
        await _db.execute('DETACH DATABASE mstage');
      } catch (_) {
        // 没挂上/已卸下：不用管。
      }
    }
  }

  Future<int> _countWhere(
    DatabaseExecutor db,
    String table,
    int libraryId, {
    bool onlyNew = false,
  }) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE library_id = ?'
      '${onlyNew ? ' AND was_existing = 0' : ''}',
      [libraryId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<MagnetRemoveResult> removeLibrary(int libraryId) async {
    await ensureMagnetLibraryTables(_db);
    late MagnetRemoveResult result;
    await _db.transaction((txn) async {
      result = await _removeLibraryInTxn(txn, libraryId);
    });
    await _rebuildRollupQuietly();
    return result;
  }

  /// 删库语义（事务内）：本库独有作品整部删；共享作品只摘
  /// 本库贡献的线路；本库带来的演员在没作品后删行。
  Future<MagnetRemoveResult> _removeLibraryInTxn(
    Transaction txn,
    int libraryId,
  ) async {
    final rows = await txn.query(
      'magnet_libraries',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [libraryId],
    );
    if (rows.isEmpty) {
      return const MagnetRemoveResult(removedWorks: 0, removedPlayUrls: 0);
    }
    // 本库独有作品（导入前不存在、别的磁力库也没带）落临时表。
    await txn.execute(
      'CREATE TEMP TABLE IF NOT EXISTS magnet_doomed '
      '(vod_id TEXT PRIMARY KEY)',
    );
    await txn.execute('DELETE FROM magnet_doomed');
    await txn.execute(
      'INSERT INTO magnet_doomed (vod_id) '
      'SELECT vod_id FROM magnet_library_works '
      'WHERE library_id = ? AND was_existing = 0 '
      'AND vod_id NOT IN (SELECT vod_id FROM magnet_library_works '
      'WHERE library_id <> ?)',
      [libraryId, libraryId],
    );
    var removedUrls = 0;
    removedUrls += await txn.rawUpdate(
      'DELETE FROM video_play_urls WHERE vod_id IN '
      '(SELECT vod_id FROM magnet_doomed)',
    );
    // 共享作品上本库贡献的线路（别的磁力库也带了同一条的不摘）。
    removedUrls += await txn.rawUpdate(
      'DELETE FROM video_play_urls WHERE (vod_id, play_url) IN '
      '(SELECT vod_id, play_url FROM magnet_library_play_urls '
      'WHERE library_id = ? AND was_existing = 0) '
      'AND vod_id NOT IN (SELECT vod_id FROM magnet_doomed) '
      'AND (vod_id, play_url) NOT IN '
      '(SELECT vod_id, play_url FROM magnet_library_play_urls '
      'WHERE library_id <> ?)',
      [libraryId, libraryId],
    );
    await txn.execute(
      'DELETE FROM video_actress WHERE vod_id IN '
      '(SELECT vod_id FROM magnet_doomed)',
    );
    await txn.execute(
      'DELETE FROM video_category WHERE vod_id IN '
      '(SELECT vod_id FROM magnet_doomed)',
    );
    // 幸存作品上本库贡献的分类行（导入前它没有分类行）也摘
    // 掉；别的磁力库给同一作品贡献了同一分类的不摘。
    await txn.execute(
      'DELETE FROM video_category WHERE (vod_id, main_category) IN '
      '(SELECT vod_id, main_category FROM magnet_library_categories '
      'WHERE library_id = ? AND was_existing = 0) '
      'AND vod_id NOT IN (SELECT vod_id FROM magnet_doomed) '
      'AND (vod_id, main_category) NOT IN '
      '(SELECT vod_id, main_category FROM magnet_library_categories '
      'WHERE library_id <> ?)',
      [libraryId, libraryId],
    );
    if (await _tableExists(txn, 'video_tag')) {
      await txn.execute(
        'DELETE FROM video_tag WHERE vod_id IN '
        '(SELECT vod_id FROM magnet_doomed)',
      );
    }
    final removedWorks = await txn.rawUpdate(
      'DELETE FROM videos WHERE vod_id IN '
      '(SELECT vod_id FROM magnet_doomed)',
    );
    // 本库带来的演员：别的库没带、删完作品后没人挂的删行。
    await txn.execute(
      'DELETE FROM actresses WHERE cate_id IN '
      '(SELECT cate_id FROM magnet_library_actresses '
      'WHERE library_id = ? AND was_existing = 0) '
      'AND cate_id NOT IN (SELECT cate_id FROM '
      'magnet_library_actresses WHERE library_id <> ?) '
      'AND cate_id NOT IN (SELECT cate_id FROM video_actress)',
      [libraryId, libraryId],
    );
    await txn.execute(
      'DELETE FROM magnet_library_works WHERE library_id = ?',
      [libraryId],
    );
    await txn.execute(
      'DELETE FROM magnet_library_play_urls WHERE library_id = ?',
      [libraryId],
    );
    await txn.execute(
      'DELETE FROM magnet_library_actresses WHERE library_id = ?',
      [libraryId],
    );
    await txn.execute(
      'DELETE FROM magnet_library_categories WHERE library_id = ?',
      [libraryId],
    );
    await txn.execute('DELETE FROM magnet_libraries WHERE id = ?', [
      libraryId,
    ]);
    await txn.execute('DROP TABLE IF EXISTS magnet_doomed');
    return MagnetRemoveResult(
      removedWorks: removedWorks,
      removedPlayUrls: removedUrls,
    );
  }

  /// 名册汇总表跟着并/删重建（与整库导入同一套算法）；失败
  /// 不拦主流程——读侧没有汇总表时会现算，只是慢一点。
  Future<void> _rebuildRollupQuietly() async {
    try {
      await ActressSqlImporter.rebuildRollup(SqfliteImportExecutor(_db));
    } catch (_) {
      // 汇总表落不下不算并库失败。
    }
  }
}
