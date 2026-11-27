// JavDB 源界面（2026-11-26）：源切换条里的 JavDB 段——演员
// 列表 + 最新作品 + 统一搜索（搜作品），照 AvPlay 女优库的
// 功能面落：演员卡三列方形头像、作品卡三列（番号红字、徽
// 标、日期）。封面/头像走 JavDB 图片通道（XOR 解密）。
//
// 数据诚实：整条源未验（本机出口连不上接口域名、且无账号
// 令牌）——页头常挂「未验」标；加载失败给人话提示 + 重试，
// 不拿假数据冒充。
import 'dart:async';

import 'package:flutter/material.dart';

import '../app_page_route.dart';
import '../core_bridge.dart';
import '../detail_screen.dart';
import '../local_store.dart';
import '../models.dart';
import 'actress_av_style.dart';
import 'actress_database.dart';
import 'actress_detail_page.dart';
import 'actress_models.dart';
import 'actress_online_detail.dart';
import 'javdb_actress_merge.dart';
import 'javdb_api.dart';
import 'javdb_image.dart';

export 'javdb_image.dart';

/// 打开一部 JavDB 作品：信息先进 DetailScreen（番号在，跨站
/// 探活 + 在线线路区自动按番号搜线路；本地库线路经详情页既
/// 有补线链并入）——播放走既定番号竞速模型，本源不造播放
/// 链。详情补充（演员/剧照/厂商）先尽力拉一次，拉不到不挡
/// 开页。
Future<void> openJavdbWork(
  BuildContext context, {
  required JavdbMovie movie,
  required AppRepository repository,
  required LocalStore store,
  JavdbApiClient? client,
}) async {
  JavdbMovieExtra extra = const JavdbMovieExtra();
  if (movie.id.isNotEmpty) {
    try {
      extra = await (client ?? JavdbApiClient())
          .movieExtra(movie.id)
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // 补充拉不到就只带列表信息开页，不挡。
    }
  }
  if (!context.mounted) return;
  // 海报：详情自带封面优先（列表卡可能只有小图/缺图），
  // 没有再用列表卡的 poster。
  final cover = extra.poster.isNotEmpty ? extra.poster : movie.poster;
  final drama = Drama(
    id: movie.number.isNotEmpty ? movie.number : movie.id,
    source: 'javdb',
    sourceId: movie.id,
    title: movie.title.isNotEmpty ? movie.title : movie.number,
    cover: cover,
    onlineDate: movie.releaseDate,
    tags: [if (movie.number.isNotEmpty) movie.number],
  );
  final detail = DramaDetail(
    drama,
    const [],
    backdrop: cover,
    // 剧照：v4 详情的预览图优先；详情没拉到时用列表信封
    // 自带的 preview_images（免登录真数据，2026-11-27 实测
    // latest 列表每条都带）——此前两路都没接，剧照区恒空。
    stills: extra.stills.isNotEmpty ? extra.stills : movie.previewImages,
    extraInfo: [
      if (movie.releaseDate.isNotEmpty) ('发行日期', movie.releaseDate),
      // 接口 duration 单位就是分钟，直接显示（旧实现误当
      // 秒除以 60，正片只剩「3 分钟」）。
      if (movie.durationMinutes > 0) ('长度', '${movie.durationMinutes} 分钟'),
      ...extra.extraInfo,
    ],
  );
  await Navigator.of(context).push(
    appPageRoute(
      settings: const RouteSettings(name: 'detail'),
      builder: (_) => DetailScreen(
        drama: drama,
        repository: repository,
        store: store,
        pan115Gateway: actressPan115GatewayOf(repository),
        initialDetail: detail,
      ),
    ),
  );
}

/// JavDB 源视图：演员 / 最新作品两页签 + 统一搜索结果。
class JavdbSourceView extends StatefulWidget {
  const JavdbSourceView({
    super.key,
    this.initialQuery = '',
    this.client,
    this.repository,
    this.store,
    this.database,
  });

  final String initialQuery;
  final JavdbApiClient? client;
  final AppRepository? repository;
  final LocalStore? store;

  /// 本地女优库（合并用）：传了才做「本地库已有」标记与演员页
  /// 合并；不传时整条 JavDB 源照旧独立显示。
  final ActressDatabase? database;

  @override
  State<JavdbSourceView> createState() => _JavdbSourceViewState();
}

class _JavdbSourceViewState extends State<JavdbSourceView> {
  late final JavdbApiClient _client = widget.client ?? JavdbApiClient();
  int _tab = 0; // 0 演员 / 1 最新作品 / 2 搜索结果
  List<JavdbActor> _actors = const [];
  List<JavdbMovie> _movies = const [];
  bool _loading = true;
  String _error = '';
  int _page = 1;
  bool _loadingMore = false;

  /// 本地库里已有同名女优的 JavDB 演员 id（卡片打「本地库」
  /// 标记用）；database 没传时恒空。
  Set<String> _localActorIds = const {};

  String get _query => widget.initialQuery.trim();

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(JavdbSourceView old) {
    super.didUpdateWidget(old);
    if (old.initialQuery != widget.initialQuery) _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = '';
        _page = 1;
        _tab = _query.isNotEmpty ? 2 : (_tab == 2 ? 0 : _tab);
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      if (_tab == 0) {
        final rows = await _client.actors(page: _page);
        if (!mounted) return;
        setState(() {
          _actors = reset ? rows : [..._actors, ...rows];
          _loading = false;
          _loadingMore = false;
        });
        unawaited(_resolveLocalActors());
      } else if (_tab == 1) {
        final rows = await _client.latestMovies(page: _page);
        if (!mounted) return;
        setState(() {
          _movies = reset ? rows : [..._movies, ...rows];
          _loading = false;
          _loadingMore = false;
        });
      } else {
        final rows = await _client.searchMovies(_query, page: _page);
        if (!mounted) return;
        setState(() {
          _movies = reset ? rows : [..._movies, ...rows];
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) {
          _error = error is AppFailure
              ? error.message
              : 'JavDB 暂时连不上，请检查网络后重试';
        }
      });
    }
  }

  /// 演员列表到位后查本地库同名女优（归一化名字口径），命中
  /// 的卡片打「本地库」标记。查库失败不影响 JavDB 列表本身。
  Future<void> _resolveLocalActors() async {
    final db = widget.database;
    if (db == null || _actors.isEmpty) return;
    try {
      final hits = await javdbActorIdsPresentLocally(db, _actors);
      if (!mounted) return;
      setState(() => _localActorIds = hits);
    } catch (_) {
      // 本地库查不到就不打标记，不堵在线列表。
    }
  }

  @override
  Widget build(BuildContext context) {
    // 自带浅色底（同在线视图口径）：文字色全是 AvStyle 浅色
    // 版式色，宿主深色主题下不自带底会黑底黑字。
    return ColoredBox(color: AvStyle.bg, child: _buildInner(context));
  }

  Widget _buildInner(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              AvPill(
                label: '演员',
                selected: _tab == 0,
                onTap: () {
                  setState(() => _tab = 0);
                  _load(reset: true);
                },
              ),
              const SizedBox(width: 8),
              AvPill(
                label: '最新作品',
                selected: _tab == 1,
                onTap: () {
                  setState(() => _tab = 1);
                  _load(reset: true);
                },
              ),
              if (_tab == 2) ...[
                const SizedBox(width: 8),
                AvPill(label: '搜索结果', selected: true, onTap: () {}),
              ],
              const Spacer(),
              // 整条源未验的诚实标注（出口连不上 + 无账号令牌）。
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AvStyle.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '未验',
                  style: TextStyle(
                    color: AvStyle.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            'JavDB 接口演员库 · 演员与作品信息源，播放按番号自动搜线路',
            style: TextStyle(color: AvStyle.dim, fontSize: 11.5),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: AvStyle.dim, size: 36),
            const SizedBox(height: 10),
            Text(_error, style: const TextStyle(color: AvStyle.dim)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _load(reset: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_tab == 0) {
      if (_actors.isEmpty) {
        return const Center(
          child: Text('没有拿到演员数据', style: TextStyle(color: AvStyle.dim)),
        );
      }
      return _scrollGrid(
        childCount: _actors.length,
        itemBuilder: (index) => _actorCard(_actors[index]),
      );
    }
    if (_movies.isEmpty) {
      return const Center(
        child: Text('没有拿到作品数据', style: TextStyle(color: AvStyle.dim)),
      );
    }
    return _scrollGrid(
      childCount: _movies.length,
      itemBuilder: (index) => _movieCard(_movies[index]),
      works: true,
    );
  }

  Widget _scrollGrid({
    required int childCount,
    required Widget Function(int) itemBuilder,
    bool works = false,
  }) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          sliver: SliverGrid(
            gridDelegate: works
                ? avWorkGridDelegate
                : const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140,
                    childAspectRatio: 0.80,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => itemBuilder(index),
              childCount: childCount,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Center(
              child: OutlinedButton(
                onPressed: _loadingMore
                    ? null
                    : () {
                        _page++;
                        _load(reset: false);
                      },
                child: Text(_loadingMore ? '加载中…' : '加载更多'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actorCard(JavdbActor actor) {
    final inLocal = _localActorIds.contains(actor.id);
    return InkWell(
      key: ValueKey('javdb-actor-${actor.id}'),
      onTap: () => Navigator.of(context).push(
        appPageRoute(
          builder: (_) => JavdbActorPage(
            actor: actor,
            client: _client,
            repository: widget.repository,
            store: widget.store,
            database: widget.database,
          ),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(child: JavdbImage(url: actor.avatarUrl)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            actor.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AvStyle.text,
            ),
          ),
          // 本地库已有同名女优：明示标记，点进去是合并后的作品。
          if (inLocal)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AvStyle.green,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '本地库',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _movieCard(JavdbMovie movie) {
    return InkWell(
      key: ValueKey('javdb-movie-${movie.id}'),
      onTap: () {
        final repository = widget.repository;
        final store = widget.store;
        if (repository == null || store == null) return;
        openJavdbWork(
          context,
          movie: movie,
          client: _client,
          repository: repository,
          store: store,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.expand(child: JavdbImage(url: movie.poster)),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            movie.title.isNotEmpty ? movie.title : movie.number,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AvStyle.text,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  movie.number,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AvStyle.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (movie.magnetsCount > 0) ...[
                const SizedBox(width: 5),
                const Text(
                  '有资源',
                  style: TextStyle(
                    color: AvStyle.green,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (movie.hasCnsub) ...[
                const SizedBox(width: 5),
                const Text(
                  '字幕',
                  style: TextStyle(
                    color: AvStyle.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          if (movie.releaseDate.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              movie.releaseDate,
              style: const TextStyle(color: AvStyle.dim, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// JavDB 演员页：大头像 + 名字 + 作品网格（版式同女优详情）。
/// 传了本地库（database）时按归一化名字匹配本地库女优，作品
/// 列表合并：本地库作品在前（点开走本地女优页、播放优先本地
/// 库线路）、JavDB 作品按归一番号去重后补在后面（2026-11-27
/// 问题 2 合并令）。
class JavdbActorPage extends StatefulWidget {
  const JavdbActorPage({
    super.key,
    required this.actor,
    this.client,
    this.repository,
    this.store,
    this.database,
  });

  final JavdbActor actor;
  final JavdbApiClient? client;
  final AppRepository? repository;
  final LocalStore? store;
  final ActressDatabase? database;

  @override
  State<JavdbActorPage> createState() => _JavdbActorPageState();
}

class _JavdbActorPageState extends State<JavdbActorPage> {
  late final JavdbApiClient _client = widget.client ?? JavdbApiClient();
  List<JavdbMovie> _movies = const [];
  bool _loading = true;
  String _error = '';

  /// 本地库同名女优与其作品（合并用）；没匹配上时 person 为空。
  ActressPerson? _localPerson;
  List<ActressWork> _localWorks = const [];

  /// 合并后的 JavDB 侧作品：与本地库同番号的剔除（只留本地
  /// 库那条，播放优先本地库线路）。
  List<JavdbMovie> get _mergedMovies => javdbMoviesNotInLocal(
    _movies,
    _localWorks.map((work) => work.codeKey),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final rows = await _client.actorMovies(widget.actor.id);
      if (!mounted) return;
      setState(() {
        _movies = rows;
        _loading = false;
      });
      unawaited(_loadLocalMerge());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is AppFailure ? error.message : '作品暂时拉不到，请稍后再试';
      });
    }
  }

  /// 本地库合并：按归一化名字找同名女优，拉她的全部本地作品。
  /// 查不到/查失败就保持纯 JavDB 列表，不堵页面。
  Future<void> _loadLocalMerge() async {
    final db = widget.database;
    if (db == null) return;
    try {
      final person = await findLocalActressByName(db, widget.actor.name);
      if (person == null || !mounted) return;
      final total = await db.countWorks(person.localId);
      final works = total <= 0
          ? const <ActressWork>[]
          : await db.worksForPerson(
              person.localId,
              offset: 0,
              limit: total.clamp(1, 3000),
            );
      if (!mounted) return;
      setState(() {
        _localPerson = person;
        _localWorks = works;
      });
    } catch (_) {
      // 本地库合并失败不影响 JavDB 作品本身。
    }
  }

  /// 点本地库作品卡：去本地女优页（同一人的合并页，播放走
  /// 本地库点播链）。
  void _openLocalPerson() {
    final person = _localPerson;
    final repository = widget.repository;
    final store = widget.store;
    final db = widget.database;
    if (person == null || repository == null || store == null || db == null) {
      return;
    }
    Navigator.of(context).push(
      appPageRoute(
        builder: (_) => ActressDetailPage(
          localId: person.localId,
          repository: repository,
          store: store,
          database: db,
          javdbClient: _client,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actor = widget.actor;
    return Scaffold(
      backgroundColor: AvStyle.bg,
      appBar: AppBar(
        backgroundColor: AvStyle.bg,
        foregroundColor: AvStyle.text,
        elevation: 0,
        title: Text(
          actor.name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 104,
                    height: 104,
                    child: JavdbImage(url: actor.avatarUrl),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        actor.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AvStyle.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 部数只认实际合并到的（本地库实际作品数 +
                      // 去重后 JavDB 实际条数），不用站方声称数字。
                      Text(
                        _loading
                            ? '作品加载中…'
                            : _localPerson != null
                            ? '本地库 ${_localWorks.length} 部 · JavDB ${_mergedMovies.length} 部'
                            : '${_movies.length} 部影片',
                        style: const TextStyle(
                          color: AvStyle.dim,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              '她的作品',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AvStyle.text,
              ),
            ),
          ),
          Expanded(child: _worksBody()),
        ],
      ),
    );
  }

  Widget _worksBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error, style: const TextStyle(color: AvStyle.dim)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final movies = _mergedMovies;
    final total = _localWorks.length + movies.length;
    if (total == 0) {
      return const Center(
        child: Text('没有拿到作品数据', style: TextStyle(color: AvStyle.dim)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      gridDelegate: avWorkGridDelegate,
      itemCount: total,
      itemBuilder: (context, index) {
        // 本地库作品在前（合并口径：本地优先），点开去本地
        // 女优页走本地库点播链。
        if (index < _localWorks.length) {
          final work = _localWorks[index];
          return AvWorkCard(
            cover: work.coverUrl,
            title: work.displayTitle,
            code: work.codeDisplay.isNotEmpty ? work.codeDisplay : work.codeKey,
            date: work.date,
            onTap: _openLocalPerson,
            topRight: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AvStyle.green,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '本地库',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        final movie = movies[index - _localWorks.length];
        return InkWell(
          onTap: () {
            final repository = widget.repository;
            final store = widget.store;
            if (repository == null || store == null) return;
            openJavdbWork(
              context,
              movie: movie,
              client: _client,
              repository: repository,
              store: store,
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.expand(child: JavdbImage(url: movie.poster)),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                movie.title.isNotEmpty ? movie.title : movie.number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AvStyle.text,
                ),
              ),
              Text(
                movie.number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AvStyle.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (movie.releaseDate.isNotEmpty)
                Text(
                  movie.releaseDate,
                  style: const TextStyle(color: AvStyle.dim, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }
}
