// JavDB 女优 × 本地库女优合并（2026-11-27 phonefix2 问题 2）：
// 用户实报「JavDB 女优没有与数据库里面的女优合并」——JavDB 源
// 页签里点开一名女优只出 JavDB 自己的作品，本地库里同名女优
// 的作品一条不带；本地女优页反过来也不带 JavDB 作品。
//
// 合并口径：
// - 人物匹配按归一化名字（normalizeActressJsonName：去空白 +
//   全小写，与库内同名演员合并、影视库按名匹配的既有口径
//   一致），本名与别名都认；
// - 作品合并按归一番号（normalizeAvCode）去重，本地库作品
//   永远优先（同番号只留本地库那条，播放走本地库线路）；
// - 作品数只数实际合并到的条数，不用站方声称数字。
import 'actress_database.dart';
import 'actress_json_fallback.dart' show normalizeActressJsonName;
import 'actress_models.dart';
import 'javdb_api.dart';

/// 在本地库里按归一化名字找女优：先用原名查、再用去空白名
/// 查（库内名字可能带空格/大小写差异），命中后按归一口径
/// 精确比对本名与别名，避免 LIKE 子串误配（「結衣」配上
/// 「波多野結衣」这类）。
Future<ActressPerson?> findLocalActressByName(
  ActressDatabase db,
  String name,
) async {
  final key = normalizeActressJsonName(name);
  if (key.isEmpty) return null;
  final queries = <String>{
    name.trim(),
    name.replaceAll(RegExp(r'\s+'), ''),
  };
  for (final query in queries) {
    if (query.isEmpty) continue;
    final rows = await db.listPersons(
      sex: ActressSexFilter.all,
      sort: ActressSort.nameAsc,
      query: query,
      offset: 0,
      limit: 50,
    );
    for (final person in rows) {
      if (normalizeActressJsonName(person.displayName) == key) {
        return person;
      }
      for (final alias in person.aliases) {
        if (normalizeActressJsonName(alias) == key) return person;
      }
    }
  }
  return null;
}

/// 一批 JavDB 女优里哪些在本地库已有同名女优：返回命中的
/// JavDB 演员 id 集合（列表页打「本地库」标记用）。
Future<Set<String>> javdbActorIdsPresentLocally(
  ActressDatabase db,
  List<JavdbActor> actors,
) async {
  final hits = <String>{};
  for (final actor in actors) {
    if (actor.name.trim().isEmpty) continue;
    final person = await findLocalActressByName(db, actor.name);
    if (person != null) hits.add(actor.id);
  }
  return hits;
}

/// JavDB 作品里本地库没有的那些（按归一番号去重）：同番号
/// 本地库已有的一律剔除——合并列表里该番号只出本地库那条，
/// 播放优先本地库线路。番号为空的 JavDB 作品无法比对，保留
/// （它不与任何本地番号冲突）。
List<JavdbMovie> javdbMoviesNotInLocal(
  List<JavdbMovie> movies,
  Iterable<String> localCodeKeys,
) {
  final localCodes = <String>{
    for (final code in localCodeKeys)
      if (normalizeAvCode(code).isNotEmpty) normalizeAvCode(code),
  };
  return [
    for (final movie in movies)
      if (movie.number.trim().isEmpty ||
          !localCodes.contains(normalizeAvCode(movie.number)))
        movie,
  ];
}

/// 本地库作品的归一番号集合（合并去重用）。
Set<String> localWorkCodeKeys(Iterable<ActressWork> works) => {
  for (final work in works)
    if (normalizeAvCode(work.codeKey).isNotEmpty)
      normalizeAvCode(work.codeKey),
};
