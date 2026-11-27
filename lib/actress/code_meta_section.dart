// 详情页智能匹配区（2026-11-23 用户令）：按番号查三站元数据、查不到
// 按标题兜底，只显示演员与导演（番号只作匹配键、不显示；厂商、
// 年份不显示）。只加显示，不改播放链路（不碰 _playWork、不碰取流、
// 不写库、不联网、不加关注按钮）。查不到元数据、或元数据里既无
// 导演又无演员时什么都不画（不显示空字段）。
//
// 演员来源（2026-11-27 用户令修订）：原内置 who's 索引已撤，演员
// 改走已导入的女优库数据库（按番号查 video_actress → actresses）；
// 没导入数据库、或库里查不到这个番号，就没有数据库演员这一路，
// 只剩三站元数据（420 码）本身，两边都没有时整区不显示（沿
// 2026-11-23「查不到不显示」口径，不编造）。
//
// 演员行样式按红果详情页截图：小头像 + 只显示名字（2026-11-24
// 用户令：去掉主演/配角，只留名字）。
// 头像地址来自女优库 actresses.avatar，有地址显示真照片，没有
// 地址时 ActressAvatar 回落到名字首字圆圈。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import 'actress_widgets.dart';
import 'actress_working_db.dart';
import 'jav_code_meta.dart';

/// 数据库按番号查到的演员（女优/男优分开，带头像）。
typedef DbCodeCast = ({
  List<({String name, String avatarUrl})> female,
  List<({String name, String avatarUrl})> male,
});

const DbCodeCast emptyDbCodeCast = (female: [], male: []);

/// 按番号去已导入的内部工作库查演员（只读）：工作库文件不存在
/// （没导入过）直接回空；表不齐/查不到回空；任何失败回空、不抛
/// 错挡详情页。vod_id 候选：番号小写原形与下划线转横杠形。
/// 库里没有 actresses 表时（外来库只有 video_actress）cate_id
/// 本身就是人名，头像留空。
Future<DbCodeCast> dbCastForCode(String code) async {
  final upper = code.trim().toUpperCase();
  if (upper.isEmpty) return emptyDbCodeCast;
  try {
    final dbPath = await actressWorkingDbPath();
    if (!await File(dbPath).exists()) return emptyDbCodeCast;
    final db = await openDatabase(dbPath, readOnly: true);
    try {
      final tables = {
        for (final row in await db.query(
          'sqlite_master',
          columns: ['name'],
          where: 'type = ?',
          whereArgs: ['table'],
        ))
          (row['name'] as String?) ?? '',
      };
      if (!tables.contains('video_actress') || !tables.contains('videos')) {
        return emptyDbCodeCast;
      }
      final candidates = <String>{
        upper.toLowerCase(),
        upper.toLowerCase().replaceAll('_', '-'),
      }.toList();
      final marks = List.filled(candidates.length, '?').join(',');
      final List<Map<String, Object?>> rows;
      if (tables.contains('actresses')) {
        rows = await db.rawQuery(
          'SELECT a.name AS name, a.avatar AS avatar, a.sex AS sex '
          'FROM video_actress va '
          'JOIN actresses a ON a.cate_id = va.cate_id '
          'WHERE va.vod_id IN ($marks)',
          candidates,
        );
      } else {
        rows = await db.rawQuery(
          'SELECT va.cate_id AS name, \'\' AS avatar, \'\' AS sex '
          'FROM video_actress va WHERE va.vod_id IN ($marks)',
          candidates,
        );
      }
      final female = <({String name, String avatarUrl})>[];
      final male = <({String name, String avatarUrl})>[];
      final seen = <String>{};
      for (final row in rows) {
        final name = ((row['name'] as String?) ?? '').trim();
        if (name.isEmpty || name == '素人' || !seen.add(name)) continue;
        final entry = (
          name: name,
          avatarUrl: ((row['avatar'] as String?) ?? '').trim(),
        );
        if (((row['sex'] as String?) ?? '').trim() == 'male') {
          male.add(entry);
        } else {
          female.add(entry);
        }
      }
      return (female: female, male: male);
    } finally {
      await db.close();
    }
  } catch (_) {
    return emptyDbCodeCast;
  }
}

/// 详情页智能匹配区：自包含，详情页只插一行即可。
/// 找不到元数据（或资源缺失）时不占位置。
/// 详情页演员匹配入口（详情页头区演员行与 [CodeMetaSection] 共用）：
/// 三站元数据（420 码，管导演）与已导入数据库演员并行取，任一
/// 失败走空、不挡详情页。[dbCastLoader] 仅测试注入，生产走
/// [dbCastForCode]。匹配先按番号、再按标题兜底（见
/// [JavCodeMeta.match]）；查不到时返回 null，调用方不画演员区。
Future<CodeMeta?> loadCodeMetaForDrama({
  required String dramaId,
  required String title,
  required String sourceId,
  Future<DbCodeCast> Function(String code)? dbCastLoader,
}) async {
  try {
    final code = JavCodeMeta.resolveCode(
      id: dramaId,
      title: title,
      sourceId: sourceId,
    );
    final results = await Future.wait([
      JavCodeMeta.instance,
      if (code.isNotEmpty)
        (dbCastLoader ?? dbCastForCode)(code)
      else
        Future<DbCodeCast>.value(emptyDbCodeCast),
    ]);
    final map = results[0] as JavCodeMeta;
    final dbCast = results[1] as DbCodeCast;
    return map.match(
      id: dramaId,
      title: title,
      sourceId: sourceId,
      dbFemale: dbCast.female,
      dbMale: dbCast.male,
    );
  } catch (_) {
    // 资源缺失/损坏时不挡详情页：调用方直接不显示演员区。
    return null;
  }
}

class CodeMetaSection extends StatefulWidget {
  const CodeMetaSection({
    super.key,
    required this.dramaId,
    required this.title,
    this.sourceId = '',
    this.dbCastLoader,
  });

  /// 从 Drama 建（详情页用这个）。
  factory CodeMetaSection.forDrama(Drama drama) => CodeMetaSection(
    dramaId: drama.id,
    title: drama.title,
    sourceId: drama.sourceId,
  );

  /// 详情页 drama.id（如 `json:chaoliu:rki-6042`、`code_RKI-6042`）。
  final String dramaId;

  /// 详情页标题（番号查不到时作兜底键）。
  final String title;

  /// 详情页 drama.sourceId（extractAvId 兜底用）。
  final String sourceId;

  /// 测试注入：数据库演员查询；不传走 [dbCastForCode] 真库。
  final Future<DbCodeCast> Function(String code)? dbCastLoader;

  @override
  State<CodeMetaSection> createState() => _CodeMetaSectionState();
}

class _CodeMetaSectionState extends State<CodeMetaSection> {
  CodeMeta? _meta;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CodeMetaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dramaId != widget.dramaId ||
        oldWidget.title != widget.title) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final generation = ++_generation;
    // 先清掉旧的，防详情页切到另一部时短暂串台。
    setState(() => _meta = null);
    final meta = await _loadMeta();
    if (!mounted || generation != _generation) return;
    setState(() => _meta = meta);
  }

  Future<CodeMeta?> _loadMeta() => loadCodeMetaForDrama(
    dramaId: widget.dramaId,
    title: widget.title,
    sourceId: widget.sourceId,
    dbCastLoader: widget.dbCastLoader,
  );

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    if (meta == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final cast = meta.castWithAvatars;
    // 只加演员和导演：既无导演又无演员时什么都不画（番号只作匹配键、
    // 不显示；厂商、年份不显示）。
    if (meta.director.isEmpty && cast.isEmpty) {
      return const SizedBox.shrink();
    }
    final facts = <({String label, String value})>[
      if (meta.director.isNotEmpty) (label: '导演', value: meta.director),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('演员与导演', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Text(
                // 演员来自已导入数据库、导演没有时，来源标女优库；
                // 否则标三站元数据（导演只来自 420 码）。
                meta.fromDb && meta.director.isEmpty ? '女优库' : '三站元数据',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (facts.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final fact in facts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${fact.label}：${fact.value}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          if (cast.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final actor in cast)
              _ActorRow(
                key: ValueKey('code-meta-actor-${actor.name}'),
                name: actor.name,
                avatarUrl: actor.avatarUrl,
              ),
          ],
        ],
      ),
    );
  }
}

/// 演员行：小头像（真照片，没有时回落名字首字圆圈）+ 只显示名字
///（2026-11-24 用户令：主演/配角去掉）。
class _ActorRow extends StatelessWidget {
  const _ActorRow({
    super.key,
    required this.name,
    required this.avatarUrl,
  });

  final String name;
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ActressAvatar(avatarUrl: avatarUrl, name: name, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
