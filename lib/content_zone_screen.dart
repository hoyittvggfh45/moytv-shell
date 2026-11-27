import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'actress/actress_database.dart';
import 'actress/actress_db_manage_page.dart';
import 'actress/actress_working_db.dart';
import 'app_page_route.dart';

import 'audio_history_screen.dart';
import 'content_detail_screen.dart';
import 'content_legado.dart';
import 'content_models.dart';
import 'content_registry.dart';
import 'content_zone_binding.dart';
import 'core_bridge.dart';
import 'novel_cover.dart';
import 'novel_source_store.dart';
import 'reading_bookshelf_screen.dart';
import 'site_icon.dart';
import 'source_picker_sheet.dart';
import 'station_library.dart';

/// 听书 / 漫画 / 小说共用的分区页：源切换 + 分类 + 搜索 + 卡片列表，
/// 文件夹卡走下钻栈（与影视区文件夹通道同一交互口径）。
class ContentZoneScreen extends StatefulWidget {
  const ContentZoneScreen({super.key, required this.section, this.binding});

  final ContentSection section;
  final ContentZoneBinding? binding;

  @override
  State<ContentZoneScreen> createState() => _ContentZoneScreenState();
}

class _ContentZoneScreenState extends State<ContentZoneScreen> {
  late final ContentZoneBinding _binding;
  List<ContentSource> _sources = const [];
  ContentSource? _source;
  List<ContentCategory> _categories = const [];
  String _categoryId = '';
  String _categoryName = '';
  final List<({String id, String name})> _drill = [];
  List<ContentBook> _items = const [];
  int _page = 1;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadingMore = false;
  String _error = '';
  String _query = '';
  final _searchController = TextEditingController();
  final _scroll = ScrollController();

  /// 自动补拉代次：切源/切区后旧的补拉自动作废，不会把旧源内容刷回来。
  int _categoryGeneration = 0;

  /// 可取消的补拉等待：页面销毁时取消计时器，测试的假时钟里不留挂起的 Timer。
  Timer? _retryTimer;
  Completer<void>? _retryCompleter;

  Future<void> _cancellableRetryDelay() async {
    final completer = Completer<void>();
    _retryCompleter = completer;
    _retryTimer = Timer(const Duration(milliseconds: 1500), () {
      _retryTimer = null;
      _retryCompleter = null;
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    if (_retryCompleter == completer) {
      _retryTimer = null;
      _retryCompleter = null;
    }
  }

  void _cancelRetryDelay() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final completer = _retryCompleter;
    _retryCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  @override
  void initState() {
    super.initState();
    _binding = widget.binding ?? ContentZoneBinding();
    // 站点库状态（导入/删除/回退）变了就重绑当前区：名单行
    // 的锁定标记与引导面板跟着新状态走，不用重启 App。
    StationLibrary.generation.addListener(_onStationLibraryChanged);
    unawaited(StationLibrary.ensureLoaded());
    if (widget.section == ContentSection.novel) {
      _loadNovelSources();
    } else {
      _bindSection();
    }
  }

  void _onStationLibraryChanged() {
    if (!mounted) return;
    setState(() {});
    final source = _source;
    if (source != null && source.stationGated) {
      unawaited(_loadCategoriesWithAutoRetry());
    }
  }

  /// 这个源归站点库管、且站点库还没给到它：名单行在、点不开。
  bool _stationLocked(ContentSource source) =>
      source.stationGated && !StationLibrary.provides(source.id);

  Future<void> _loadNovelSources() async {
    await NovelSourceStore.applyToRegistry();
    if (!mounted) return;
    _bindSection();
    setState(() {});
  }

  @override
  void didUpdateWidget(ContentZoneScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      if (widget.section == ContentSection.novel) {
        _loadNovelSources();
      } else {
        _bindSection();
      }
    }
  }

  void _bindSection() {
    _sources = _binding.sourcesFor(widget.section);
    _source = _binding.sourceFor(widget.section);
    _categories = const [];
    _categoryId = '';
    _categoryName = '';
    _drill.clear();
    _items = const [];
    _page = 1;
    _hasMore = false;
    _loading = false;
    _loadingMore = false;
    _error = '';
    _query = '';
    _searchController.clear();
    if (_source != null) unawaited(_loadCategoriesWithAutoRetry());
  }

  /// 进区 / 切源时的自动加载：分类或首屏落空/报错时自动补拉
  /// （最多再补 2 次），不用用户手动点重试；补拉期间用户切源
  /// 或手动加载优先，旧的补拉直接作废。
  Future<void> _loadCategoriesWithAutoRetry() async {
    final generation = ++_categoryGeneration;
    final source = _source;
    await _loadCategories();
    // 首轮加载落定的分类：补拉期间用户已点别的分类就作废，
    // 不能把用户的选类刷回首个分类。
    final categoryId = _categoryId;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!mounted ||
          generation != _categoryGeneration ||
          !identical(_source, source) ||
          _categoryId != categoryId ||
          _loading) {
        return;
      }
      if (_items.isNotEmpty || _error.isEmpty) return;
      if (attempt > 0) {
        await _cancellableRetryDelay();
        if (!mounted ||
            generation != _categoryGeneration ||
            !identical(_source, source) ||
            _categoryId != categoryId ||
            _loading ||
            _items.isNotEmpty ||
            _error.isEmpty) {
          return;
        }
      }
      await _loadCategories();
    }
  }

  @override
  void dispose() {
    StationLibrary.generation.removeListener(_onStationLibraryChanged);
    _cancelRetryDelay();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final source = _source;
    if (source == null) return;
    if (_stationLocked(source)) {
      // 未导入站点库：不发注定失败的取数，界面直接出导入引导。
      setState(() {
        _loading = false;
        _error = '';
        _categories = const [];
        _items = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final cats = await source.categories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoryId = cats.isNotEmpty ? cats.first.id : '';
        _categoryName = cats.isNotEmpty ? cats.first.name : '';
        _drill.clear();
      });
      await _loadPage(reset: true);
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载分类失败';
        });
      }
    }
  }

  Future<void> _loadPage({required bool reset}) async {
    final source = _source;
    if (source == null) return;
    if (reset) {
      setState(() {
        _loading = true;
        _error = '';
        _page = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = reset ? 1 : _page + 1;
      final result = _query.isNotEmpty
          ? await source.search(_query, page)
          : await source.catalog(_categoryId, page);
      if (!mounted) return;
      setState(() {
        _items = reset ? result.items : [..._items, ...result.items];
        _page = page;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
      if (reset) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        });
      }
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          if (reset) _error = e.message;
        });
        if (!reset) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          if (reset) _error = '加载失败';
        });
      }
    }
  }

  Future<void> _pickSource() async {
    final picked = await showSitePickerDialog(
      context,
      sectionName: widget.section.title,
      currentId: _source?.id ?? '',
      groups: [
        SourcePickerGroup(
          title: '',
          entries: [
            for (final source in _sources)
              SourcePickerEntry(
                id: source.id,
                name: _stationLocked(source)
                    ? '${source.name}（未导入站点库）'
                    : source.name,
              ),
          ],
        ),
      ],
    );
    if (picked == null || !mounted) return;
    final source = _sources.where((source) => source.id == picked).firstOrNull;
    if (source != null) _selectSource(source);
  }

  void _selectSource(ContentSource source) {
    if (identical(source, _source)) return;
    _binding.select(widget.section, source);
    setState(() {
      _source = source;
      _query = '';
      _searchController.clear();
      _items = const [];
      _categories = const [];
    });
    unawaited(_loadCategoriesWithAutoRetry());
  }

  void _selectCategory(ContentCategory category) {
    setState(() {
      _categoryId = category.id;
      _categoryName = category.name;
      _drill.clear();
      _query = '';
      _searchController.clear();
    });
    _loadPage(reset: true);
  }

  void _openBook(ContentBook book) {
    final source = _source;
    if (source == null) return;
    if (book.isFolder) {
      setState(() {
        _drill.add((id: _categoryId, name: _categoryName));
        _categoryId = book.drillId;
        _categoryName = book.title;
      });
      _loadPage(reset: true);
      return;
    }
    Navigator.of(context).push(
      appPageRoute(
        builder: (_) => ContentDetailScreen(
          source: source,
          book: book,
          autoPlay: source.section.isAudioLike,
        ),
      ),
    );
  }

  Future<void> _importNovel() async {
    try {
      final result = await NovelSourceStore.importPickedMany();
      if (result.records.isEmpty || !mounted) return;
      await NovelSourceStore.applyToRegistry();
      if (!mounted) return;
      _bindSection();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.records.length == 1 && result.skipped == 0
                ? '已导入 ${result.records.first.name}'
                : '已导入 ${result.records.length} 条，跳过 ${result.skipped} 条',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        final message = switch (e) {
          FormatException(message: '空文件') => '导入失败：文件是空的',
          FormatException(message: '不是小说漫画源') => '导入失败：不是小说/漫画源，视频/音频源不能导入阅读区',
          FormatException(message: final m) => '导入失败：$m',
          PlatformException() => '导入失败：所选文件取不到，试试先存到 Download 文件夹再选',
          _ => '导入失败：文件读取或保存失败',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  String _builtinSubtitle(ContentSource source) =>
      source is JsonContentSource && source.isComic ? '漫画源' : '小说源';

  Future<void> _manageNovel() async {
    final records = await NovelSourceStore.load();
    var hidden = await NovelSourceStore.builtinHiddenIds();
    var removed = await NovelSourceStore.builtinRemovedIds();
    if (!mounted) return;
    final builtins = ContentRegistry.novelJsonBuiltins;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> refreshZone() async {
            await NovelSourceStore.applyToRegistry();
            if (!mounted) return;
            _bindSection();
            setState(() {});
          }

          final visibleBuiltins = [
            for (final source in builtins)
              if (!removed.contains(source.id)) source,
          ];
          return AlertDialog(
            title: const Text('管理小说源'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('导入的小说源')),
                  if (records.isEmpty)
                    const ListTile(title: Text('暂无导入的小说源'))
                  else
                    for (final record in records)
                      ListTile(
                        title: Text(record.name),
                        subtitle: record.kind == NovelImportKind.json
                            ? Text(record.sourceType == 2 ? '漫画源' : '小说源')
                            : null,
                        trailing: IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await NovelSourceStore.remove(record);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                            await NovelSourceStore.applyToRegistry();
                            if (!mounted) return;
                            _bindSection();
                            setState(() {});
                          },
                        ),
                      ),
                  const ListTile(title: Text('内置书源')),
                  for (final source in visibleBuiltins)
                    ListTile(
                      title: Text(source.name),
                      subtitle: Text(
                        _stationLocked(source)
                            ? '${_builtinSubtitle(source)} · 未导入站点库'
                            : _builtinSubtitle(source),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: !hidden.contains(source.id),
                            onChanged: (value) async {
                              await NovelSourceStore.setBuiltinHidden(
                                source.id,
                                !value,
                              );
                              hidden =
                                  await NovelSourceStore.builtinHiddenIds();
                              setDialogState(() {});
                              await refreshZone();
                            },
                          ),
                          IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await NovelSourceStore.removeBuiltin(source.id);
                              removed =
                                  await NovelSourceStore.builtinRemovedIds();
                              setDialogState(() {});
                              await refreshZone();
                            },
                          ),
                        ],
                      ),
                    ),
                  if (removed.isNotEmpty)
                    ListTile(
                      title: Text('已删除 ${removed.length} 个内置源'),
                      trailing: TextButton(
                        onPressed: () async {
                          await NovelSourceStore.restoreRemovedBuiltins();
                          removed = await NovelSourceStore.builtinRemovedIds();
                          setDialogState(() {});
                          await refreshZone();
                        },
                        child: const Text('恢复'),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _drillBack() {
    if (_drill.isEmpty) return;
    final prev = _drill.removeLast();
    setState(() {
      _categoryId = prev.id;
      _categoryName = prev.name;
    });
    _loadPage(reset: true);
  }

  void _submitSearch() {
    setState(() {
      _query = _searchController.text.trim();
      _drill.clear();
    });
    _loadPage(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_sources.isEmpty) {
      if (widget.section == ContentSection.novel) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('小说暂无可用源'),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('novel-import-py'),
                onPressed: _importNovel,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('导入小说'),
              ),
            ],
          ),
        );
      }
      return Center(child: Text('${widget.section.title}暂无可用源'));
    }
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              // 站名文字已去掉：行首是当前源图标，点它弹源选择。
              Tooltip(
                message: '切换源',
                child: InkWell(
                  key: const ValueKey('content-source-switch'),
                  onTap: _pickSource,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: _source == null
                          ? Icon(
                              Icons.swap_horiz_rounded,
                              size: 24,
                              color: colors.onSurfaceVariant,
                            )
                          : SiteIcon(
                              siteId: _source!.id,
                              siteName: _source!.name,
                              size: 28,
                              borderRadius: 8,
                            ),
                    ),
                  ),
                ),
              ),
              if (_source != null && _source!.note.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _source!.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              if (widget.section == ContentSection.novel) ...[
                IconButton(
                  key: const ValueKey('novel-import-py'),
                  tooltip: '导入小说',
                  onPressed: _importNovel,
                  icon: const Icon(Icons.file_upload_outlined),
                ),
                IconButton(
                  key: const ValueKey('novel-manage'),
                  tooltip: '管理小说源',
                  onPressed: _manageNovel,
                  icon: const Icon(Icons.settings_outlined),
                ),
                IconButton(
                  key: const ValueKey('novel-bookshelf'),
                  tooltip: '书架',
                  onPressed: () {
                    Navigator.of(context).push(
                      appPageRoute(
                        builder: (_) =>
                            ReadingBookshelfScreen(sources: _sources),
                      ),
                    );
                  },
                  icon: const Icon(Icons.collections_bookmark_rounded),
                ),
              ],
              if (widget.section.isAudioLike) ...[
                IconButton(
                  key: const ValueKey('audio-history'),
                  tooltip: '收听记录',
                  onPressed: () {
                    Navigator.of(context).push(
                      appPageRoute(
                        builder: (_) => AudioHistoryScreen(
                          sources: _sources,
                          initialTab: 0,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history_rounded),
                ),
                IconButton(
                  key: const ValueKey('audio-favorites'),
                  tooltip: '我的收藏',
                  onPressed: () {
                    Navigator.of(context).push(
                      appPageRoute(
                        builder: (_) => AudioHistoryScreen(
                          sources: _sources,
                          initialTab: 1,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.star_border_rounded),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜索${widget.section.title}',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                        _loadPage(reset: true);
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _submitSearch(),
          ),
        ),
        if (_drill.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回上一级',
                  onPressed: _drillBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    _categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else if (_categories.isNotEmpty)
          SingleChildScrollView(
            key: ValueKey(_source?.id),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                for (final category in _categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(category.name),
                      selected: _query.isEmpty && category.id == _categoryId,
                      onSelected: (_) => _selectCategory(category),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(child: _body(colors)),
      ],
    );
  }

  Future<void> _importStationLibrary() async {
    final core = await StationLibrary.currentCoreVersion();
    final result = await StationLibrary.pickAndImport(
      manifestIds: ContentRegistry.stationLibraryManifestIds,
      currentCoreVersion: core,
    );
    if (!mounted) return;
    if (result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('站点库已导入（共 ${result.itemCount} 条）')),
      );
      // generation 监听会重绑；这里再显式刷一次保证引导立刻退场。
      setState(() {});
      final source = _source;
      if (source != null && source.stationGated) {
        unawaited(_loadCategoriesWithAutoRetry());
      }
    } else if (!result.cancelled && result.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error!)));
    }
  }

  Future<void> _openStationDbManage() async {
    final db = SqfliteActressDatabase.instance;
    final dbPath = await actressWorkingDbPath();
    if (!mounted) return;
    await Navigator.of(context).push(
      appPageRoute(
        builder: (_) => ActressDbManagePage(
          dbPath: dbPath,
          closeDatabase: db.close,
          reloadDatabase: () async {
            await db.reloadIfChanged();
          },
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  /// 未导入站点库时的引导（照演员库新装空态样板：说清现状 +
  /// 主按钮直接导入 + 次按钮去数据库管理页的站点库区）。
  Widget _stationGuide(ColorScheme colors) {
    final source = _source!;
    return Center(
      key: const ValueKey('station-library-guide'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_download_outlined,
              size: 44,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '「${source.name}」的代码在站点库里，还没导入',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              '这类站包里只留名单，代码装在「魔蚁站点.sql」站点库里。'
              '导入一次，名单里的站就都能用了；删掉站点库它们会回到'
              '只有名单的状态。',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('station-library-import'),
              onPressed: _importStationLibrary,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('导入站点库'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('station-library-manage'),
              onPressed: _openStationDbManage,
              child: const Text('去数据库管理'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme colors) {
    final source = _source;
    if (source != null && _stationLocked(source)) {
      return _stationGuide(colors);
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error, style: TextStyle(color: colors.error)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _loadPage(reset: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('暂无内容'));
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.62,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) => _card(_items[index]),
        ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () => _loadPage(reset: false),
                      child: const Text('加载更多'),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _card(ContentBook book) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _openBook(book),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: book.cover.isNotEmpty
                  ? Image.network(
                      book.cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _coverFallback(colors, book),
                    )
                  : _coverFallback(colors, book),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (book.isFolder)
                Icon(Icons.folder_rounded, size: 14, color: colors.primary),
              Expanded(
                child: Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (book.remarks.isNotEmpty)
            Text(
              book.remarks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _coverFallback(ColorScheme colors, ContentBook book) {
    if (widget.section == ContentSection.novel && !book.isFolder) {
      return Image.asset(novelDefaultCoverFor(book.id), fit: BoxFit.cover);
    }
    return Container(
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        book.isFolder ? Icons.folder_rounded : Icons.image_not_supported,
        color: colors.onSurfaceVariant,
      ),
    );
  }
}
