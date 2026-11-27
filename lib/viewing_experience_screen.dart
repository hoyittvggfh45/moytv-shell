import 'package:flutter/material.dart';

import 'local_store.dart';
import 'tmdb/tmdb_config.dart';
import 'tmdb/tmdb_settings_page.dart';
import 'viewing_experience_settings.dart';

/// 观看体验页（已瘦身，2026-11-27）：原页内的播放相关 6 项已删——
/// 弹幕/广告过滤/预加载/无缝随播放偏好收进播放器内嵌菜单，深度
/// 嗅探迁入内嵌菜单，M3U8 边下边播在全树无消费方（死开关）直接
/// 摘除（存储字段保留兼容旧数据）。本页只剩外观与资料类：
/// 沉浸式首页与详情、详情页海报背景、TMDB 资料配置。
class ViewingExperienceScreen extends StatefulWidget {
  const ViewingExperienceScreen({super.key, required this.store});

  final LocalStore store;

  @override
  State<ViewingExperienceScreen> createState() =>
      _ViewingExperienceScreenState();
}

class _ViewingExperienceScreenState extends State<ViewingExperienceScreen> {
  ViewingExperienceSettings? _settings;
  TmdbConfig? _tmdbConfig;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await ViewingExperienceSettings.load();
    final tmdb = await TmdbConfig.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _tmdbConfig = tmdb;
    });
  }

  Future<void> _updateSettings(ViewingExperienceSettings next) async {
    setState(() => _settings = next);
    await next.save();
  }

  Future<void> _openTmdb() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const TmdbSettingsPage()),
    );
    if (!mounted) return;
    final tmdb = await TmdbConfig.load();
    setState(() => _tmdbConfig = tmdb);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final tmdb = _tmdbConfig;
    return Scaffold(
      appBar: AppBar(title: const Text('观看体验')),
      body: settings == null || tmdb == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SwitchListTile(
                      key: const ValueKey('viewing-immersive-switch'),
                      title: const Text('沉浸式首页与详情'),
                      subtitle: const Text('海报背景和玻璃控件；关闭恢复旧版'),
                      value: settings.immersive,
                      onChanged: (value) => _updateSettings(
                        settings.copyWith(immersive: value),
                      ),
                    ),
                    SwitchListTile(
                      key: const ValueKey('viewing-detail-poster-switch'),
                      title: const Text('详情页海报背景'),
                      subtitle: const Text('用影片海报作详情页背景'),
                      value: settings.detailPosterBackground,
                      onChanged: (value) => _updateSettings(
                        settings.copyWith(detailPosterBackground: value),
                      ),
                    ),
                    ListTile(
                      key: const ValueKey('viewing-tmdb-entry'),
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('TMDB 资料配置'),
                      subtitle: Text(
                        tmdb.configured
                            ? '已配置 apikey · 海报、背景、剧情与剧集预览'
                            : '未配置 apikey',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openTmdb,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
