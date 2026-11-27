import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'danmaku_settings.dart';
import 'episode_browser.dart';
import 'intro_outro_editor.dart';
import 'intro_outro_skip.dart';
import 'playback_preferences.dart';
import 'picture_quality_ui.dart';
import 'player_core_fallback.dart';
import 'player_info_dialogs.dart';
import 'player_overlay_settings.dart';
import 'sleep_timer.dart';
import 'subtitle_style.dart';
import 'track_selection.dart';
import 'video_enhancement.dart';
import 'video_enhancement_settings.dart';

enum PlayerMenuSection {
  episodes,
  speed,
  quality,
  route,
  pictureQuality,
  settings,

  /// 更多菜单（⋮）：对齐参考的单列全项菜单，项序按参考：
  /// 定时关闭/播放地址/重载/快捷片行/播放顺序/弹幕/片头片尾/
  /// 长按倍速/屏显/解码/轨道/播放信息，后接迁入的播放设置组。
  more,
}

class PlayerMenu extends StatefulWidget {
  const PlayerMenu({
    super.key,
    required this.section,
    required this.episodes,
    required this.currentIndex,
    required this.preferences,
    required this.qualities,
    required this.actualQuality,
    required this.local,
    required this.favorite,
    required this.mobile,
    required this.onEpisode,
    required this.onPreferences,
    required this.onFavorite,
    this.routeIndex = 0,
    this.routeCount = 1,
    this.onRoute,
    this.showDanmaku = false,
    this.danmakuStatus = '',
    this.onRetryDanmaku,
    this.onSendLocalDanmaku,
    this.preloadStatus = '',
    this.enhancement,
    this.onCompareEnhancement,
    this.introOutro,
    this.introOutroEnabled = true,
    this.onIntroOutroChanged,
    this.audioTrackEntries = const [],
    this.subtitleTrackEntries = const [],
    this.onTrackEntry,
    this.videoTrackEntries = const [],
    this.onReload,
    this.sleepTimer,
    this.onShowAddress,
    this.onShowInfo,
    this.onLoadDanmakuFromUrl,
    this.onLoadDanmakuFromFile,
    this.danmakuSettingsStore,
    this.overlaySettingsStore,
    this.mpvControls = false,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.audioOnly = false,
    this.onFlipHorizontal,
    this.onFlipVertical,
    this.onAudioOnly,
    this.coreFallbackMode,
    this.onCoreFallbackChanged,
    this.seasonAutoplay = true,
    this.onSeasonAutoplayChanged,
    this.onIntroOutroEnabledChanged,
    this.subtitleStyleStore,
    this.onSubtitleStyleChanged,
    this.deepSniffer,
    this.onDeepSnifferChanged,
  });

  final PlayerMenuSection section;
  final List<Episode> episodes;
  final int currentIndex;
  final PlaybackPreferences preferences;
  final List<int> qualities;
  final int actualQuality;
  final bool local;
  final bool favorite;
  final bool mobile;
  final int routeIndex;
  final int routeCount;
  final ValueChanged<int>? onRoute;
  final bool showDanmaku;
  final String danmakuStatus;
  final VoidCallback? onRetryDanmaku;
  final VoidCallback? onSendLocalDanmaku;
  final String preloadStatus;
  final VideoEnhancementController? enhancement;
  final VoidCallback? onCompareEnhancement;

  /// 当前剧的片头/片尾分段（第 7 点）；为空时菜单不显示编辑区。
  final IntroOutroSettings? introOutro;
  final bool introOutroEnabled;
  final Future<void> Function(IntroOutroSettings)? onIntroOutroChanged;
  /// 音轨/字幕轨菜单条目（第 8 点）；为空时菜单不显示轨道区。
  /// 只有 MPV（media_kit）核会传，非 MPV 核不传、轨道区不出现。
  final List<TrackMenuEntry> audioTrackEntries;
  final List<TrackMenuEntry> subtitleTrackEntries;
  final ValueChanged<TrackMenuEntry>? onTrackEntry;

  /// 视轨菜单条目（M16）；与音轨同口径，仅 MPV 核传。
  final List<TrackMenuEntry> videoTrackEntries;

  /// 重载视频（M3）：走宿主的播放恢复链重新取址。
  final Future<void> Function()? onReload;

  /// 定时关闭（M1）：宿主持有控制器（到点停播由宿主接），
  /// 菜单只负责弹选择表与显示剩余时间。
  final SleepTimerController? sleepTimer;

  /// 播放地址（M2）/播放信息（M19）：宿主组装数据后用菜单
  /// 上下文弹对应弹窗。
  final ValueChanged<BuildContext>? onShowAddress;
  final ValueChanged<BuildContext>? onShowInfo;

  /// 弹幕加载（M6）：URL 直拉与本地 XML 文件两路，返回载入条数
  /// （文件路返回 null = 用户取消选择）。
  final Future<int> Function(String url)? onLoadDanmakuFromUrl;
  final Future<int?> Function()? onLoadDanmakuFromFile;

  /// 弹幕设置（M7）：给了才显示入口，打开弹幕设置整页。
  final DanmakuSettingsStore? danmakuSettingsStore;

  /// 屏显（M10/M11）：给了才显示屏显组。
  final OverlaySettingsStore? overlaySettingsStore;

  /// MPV 专属控制组（硬解/翻转/听视频/字幕样式）是否出现：
  /// 仅 MPV 核且非电视形态时为真，其余核不显示（按核显隐）。
  final bool mpvControls;
  final bool flipHorizontal;
  final bool flipVertical;
  final bool audioOnly;
  final ValueChanged<bool>? onFlipHorizontal;
  final ValueChanged<bool>? onFlipVertical;
  final ValueChanged<bool>? onAudioOnly;

  /// 核间自动回退（设置页迁入）：给了当前值与回调才显示。
  final CoreFallbackMode? coreFallbackMode;
  final ValueChanged<CoreFallbackMode>? onCoreFallbackChanged;

  /// 跨季自动连播（设置页迁入）。
  final bool seasonAutoplay;
  final ValueChanged<bool>? onSeasonAutoplayChanged;

  /// 跳过片头片尾全局开关（设置页迁入）：快捷弹窗里改，
  /// 当前值即 [introOutroEnabled]。
  final ValueChanged<bool>? onIntroOutroEnabledChanged;

  /// 字幕设置（M18）：给了存储才显示入口，改完回调宿主下发 MPV。
  final SubtitleStyleStore? subtitleStyleStore;
  final ValueChanged<SubtitleStyleSettings>? onSubtitleStyleChanged;

  /// 深度嗅探（观看体验页迁入）：null = 宿主不支持、不显示。
  final bool? deepSniffer;
  final ValueChanged<bool>? onDeepSnifferChanged;

  final ValueChanged<int> onEpisode;
  final Future<void> Function(PlaybackPreferences) onPreferences;
  final Future<void> Function() onFavorite;

  @override
  State<PlayerMenu> createState() => _PlayerMenuState();
}

class _PlayerMenuState extends State<PlayerMenu> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = '未能保存设置，请检查存储空间后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final colors = Theme.of(context).colorScheme;
    final title = switch (widget.section) {
      PlayerMenuSection.episodes => '选集 · 共 ${widget.episodes.length} 集',
      PlayerMenuSection.speed => '播放倍速',
      PlayerMenuSection.quality => '清晰度',
      PlayerMenuSection.route => '播放线路',
      PlayerMenuSection.pictureQuality => '画质档',
      PlayerMenuSection.settings => '播放设置',
      PlayerMenuSection.more => '更多',
    };
    return Dialog(
      key: const ValueKey('player-menu'),
      alignment: landscape ? Alignment.centerRight : Alignment.bottomCenter,
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: colors.surface,
      child: SizedBox(
        width: landscape ? math.min(440, size.width * .6) : 600,
        height: landscape ? size.height : size.height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭菜单',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFFFB4A8)),
                ),
              ),
            Expanded(
              child: widget.section == PlayerMenuSection.episodes
                  ? PlayerEpisodeGrid(
                      episodes: widget.episodes,
                      currentIndex: widget.currentIndex,
                      keyPrefix: 'menu-episode',
                      onSelected: widget.onEpisode,
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                      child: widget.section == PlayerMenuSection.more
                          ? _moreSettings()
                          : _settings(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settings() {
    final preferences = widget.preferences;
    final all = widget.section == PlayerMenuSection.settings;
    final colors = Theme.of(context).colorScheme;
    final helperStyle = TextStyle(
      fontSize: 12,
      color: colors.onSurfaceVariant,
      height: 1.5,
    );
    final qualities = {
      0,
      ...widget.qualities.where((quality) => quality > 0),
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (all || widget.section == PlayerMenuSection.speed) ...[
          const Text('倍速'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final speed in playbackSpeeds)
                ChoiceChip(
                  key: ValueKey('menu-speed-$speed'),
                  label: Text('${speed}x'),
                  selected: speed == preferences.speed,
                  onSelected: _busy
                      ? null
                      : (_) => _run(
                          () => widget.onPreferences(
                            preferences.copyWith(speed: speed),
                          ),
                        ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (all || widget.section == PlayerMenuSection.quality) ...[
          const Text('清晰度'),
          const SizedBox(height: 8),
          Text(
            widget.local
                ? '本集正在播放本地原画，画质偏好用于后续在线播放。'
                : widget.actualQuality > 0
                ? '当前播放 ${widget.actualQuality}P'
                : '使用源站可用画质',
            style: helperStyle,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final quality in qualities)
                ChoiceChip(
                  key: ValueKey('menu-quality-$quality'),
                  label: Text(quality == 0 ? '自动（优先高清）' : '${quality}P'),
                  selected: quality == preferences.quality,
                  onSelected: _busy
                      ? null
                      : (_) => _run(
                          () => widget.onPreferences(
                            preferences.copyWith(quality: quality),
                          ),
                        ),
                ),
            ],
          ),
          if (!qualities.contains(preferences.quality))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '已保存 ${preferences.quality}P 偏好，本集暂无此画质。',
                style: helperStyle,
              ),
            ),
          const SizedBox(height: 20),
        ],
        if (widget.section == PlayerMenuSection.route) ...[
          const Text('播放线路'),
          const SizedBox(height: 8),
          Text(
            widget.routeCount > 1
                ? '当前使用线路 ${widget.routeIndex + 1}，共 ${widget.routeCount} 条。切换线路后会保留当前进度，并在后续剧集继续使用该线路。'
                : '本集只有一条可用线路，无法切换。',
            style: helperStyle,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < widget.routeCount; index++)
                ChoiceChip(
                  key: ValueKey('menu-route-$index'),
                  label: Text('线路 ${index + 1}'),
                  selected: index == widget.routeIndex,
                  onSelected: widget.onRoute == null
                      ? null
                      : (_) => widget.onRoute!(index),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (all || widget.section == PlayerMenuSection.pictureQuality) ...[
          PictureQualityPanel(
            key: const ValueKey('menu-picture-quality'),
            value: preferences.pictureQuality,
            busy: _busy,
            onChanged: (next) => _run(
              () => widget.onPreferences(
                preferences.copyWith(pictureQuality: next),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        if ((all || widget.section == PlayerMenuSection.quality) &&
            widget.enhancement != null)
          VideoEnhancementSettings(
            controller: widget.enhancement!,
            busy: _busy,
            onChanged: (enhancement) => _run(
              () => widget.onPreferences(
                preferences.copyWith(enhancement: enhancement),
              ),
            ),
            onCompare: widget.onCompareEnhancement ?? () {},
          ),
        if (all &&
            (widget.audioTrackEntries.isNotEmpty ||
                widget.videoTrackEntries.isNotEmpty ||
                widget.subtitleTrackEntries.isNotEmpty)) ...[
          if (widget.audioTrackEntries.isNotEmpty) ...[
            const Text('音轨'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in widget.audioTrackEntries)
                  ChoiceChip(
                    key: ValueKey('menu-track-audio-${entry.id}'),
                    label: Text(entry.label),
                    selected: entry.selected,
                    onSelected: widget.onTrackEntry == null
                        ? null
                        : (_) => widget.onTrackEntry!(entry),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (widget.videoTrackEntries.isNotEmpty) ...[
            const Text('视轨'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in widget.videoTrackEntries)
                  ChoiceChip(
                    key: ValueKey('menu-track-video-${entry.id}'),
                    label: Text(entry.label),
                    selected: entry.selected,
                    onSelected: widget.onTrackEntry == null
                        ? null
                        : (_) => widget.onTrackEntry!(entry),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (widget.subtitleTrackEntries.isNotEmpty) ...[
            const Text('字幕'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in widget.subtitleTrackEntries)
                  ChoiceChip(
                    key: ValueKey(
                      'menu-track-sub-${entry.kind.name}-${entry.id}',
                    ),
                    label: Text(entry.label),
                    selected: entry.selected,
                    onSelected: widget.onTrackEntry == null
                        ? null
                        : (_) => widget.onTrackEntry!(entry),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ],
        if (all && (widget.showDanmaku || widget.onSendLocalDanmaku != null)) ...[
          if (widget.showDanmaku)
            SwitchListTile.adaptive(
              key: const ValueKey('player-danmaku-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('弹幕'),
              subtitle: Text(widget.danmakuStatus),
              value: preferences.danmaku,
              onChanged: _busy
                  ? null
                  : (value) => _run(
                      () => widget.onPreferences(
                        preferences.copyWith(danmaku: value),
                      ),
                    ),
            ),
          if (widget.onRetryDanmaku != null)
            TextButton.icon(
              key: const ValueKey('player-danmaku-retry'),
              onPressed: _busy ? null : widget.onRetryDanmaku,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试弹幕'),
            ),
          if (widget.onSendLocalDanmaku != null)
            TextButton.icon(
              key: const ValueKey('player-danmaku-send-local'),
              onPressed: _busy ? null : widget.onSendLocalDanmaku,
              icon: const Icon(Icons.send_rounded),
              label: const Text('发送本地弹幕'),
            ),
          const SizedBox(height: 8),
        ],
        if (all) ...[
          SwitchListTile.adaptive(
            key: const ValueKey('player-adblock-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('去广告'),
            subtitle: const Text('播放前清洗 m3u8，剔除插播在时间线里的广告分片；关闭后加载原画'),
            value: preferences.adBlock,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(adBlock: value),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const ValueKey('player-preload-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('下一集预加载'),
            subtitle: Text(widget.local ? '本地播放不预取网络视频' : widget.preloadStatus),
            value: preferences.preload,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.withPreload(value),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const ValueKey('player-seamless-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('无缝播放'),
            subtitle: const Text(
              '开启后换集时下一集首帧已在待命播放器备好，画面直接衔接不黑屏；开启时自动打开预加载，关闭预加载会连带关闭。IJK 内核暂不支持，自动按普通换集播',
            ),
            value: preferences.seamless,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.withSeamless(value),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const ValueKey('player-auto-advance'),
            contentPadding: EdgeInsets.zero,
            title: const Text('自动连播'),
            subtitle: const Text('关闭后，播放结束停在当前集'),
            value: preferences.autoAdvance,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(autoAdvance: value),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          if (widget.introOutro != null &&
              widget.onIntroOutroChanged != null) ...[
            IntroOutroEditor(
              key: const ValueKey('player-intro-outro'),
              value: widget.introOutro!,
              enabled: widget.introOutroEnabled,
              onChanged: (next) => _run(() => widget.onIntroOutroChanged!(next)),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            key: const ValueKey('player-favorite'),
            onPressed: _busy ? null : () => _run(widget.onFavorite),
            icon: Icon(
              widget.favorite
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
            ),
            label: Text(widget.favorite ? '取消追剧' : '加入追剧'),
          ),
          const SizedBox(height: 20),
          Text(
            widget.mobile
                ? '上下滑切集；长按画面临时 2 倍速，松开恢复。竖屏轻点暂停，横屏轻点显示控制；双击播放或暂停。'
                : '空格：播放 / 暂停\n左右键：后退 / 快进 5 秒\n长按右键或画面：临时 2 倍速\n上下键：音量 ±5%，M：静音\nF、F11、Ctrl+F：全屏\nEsc：先关闭菜单，再退出全屏',
            style: helperStyle.copyWith(height: 1.6),
          ),
        ],
      ],
    );
  }

  // ---- 更多菜单（单列全项，项序对齐参考） ----

  Widget _moreRow({
    required String keyName,
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey(keyName),
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 24, color: colors.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14)),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreChips<T>({
    required List<T> values,
    required T selected,
    required String Function(T value) labelOf,
    required String Function(T value) keyOf,
    required ValueChanged<T> onSelected,
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(left: 38, bottom: 6),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            key: ValueKey(keyOf(value)),
            label: Text(labelOf(value)),
            selected: value == selected,
            onSelected: _busy || !enabled
                ? null
                : (picked) {
                    if (picked) onSelected(value);
                  },
          ),
      ],
    ),
  );

  Widget _trackChips(List<TrackMenuEntry> entries, String prefix) => Padding(
    padding: const EdgeInsets.only(left: 38, bottom: 6),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in entries)
          ChoiceChip(
            key: ValueKey('more-track-$prefix-${entry.id}'),
            label: Text(entry.label),
            selected: entry.selected,
            onSelected: widget.onTrackEntry == null
                ? null
                : (_) => widget.onTrackEntry!(entry),
          ),
      ],
    ),
  );

  String _trackSubtitle(List<TrackMenuEntry> entries, String emptyText) {
    if (entries.isEmpty) return emptyText;
    final selected = entries.where((entry) => entry.selected);
    final current = selected.isEmpty ? 'auto' : selected.first.label;
    return '$current（${entries.length}条）';
  }

  Future<void> _openIntroOutroQuick() async {
    final introOutro = widget.introOutro;
    if (introOutro == null) return;
    final result = await showIntroOutroQuickDialog(
      context,
      initial: introOutro,
      globalEnabled: widget.introOutroEnabled,
    );
    if (result == null || !mounted) return;
    await _run(() async {
      if (widget.onIntroOutroChanged != null) {
        await widget.onIntroOutroChanged!(result.settings);
      }
      widget.onIntroOutroEnabledChanged?.call(result.globalEnabled);
    });
  }

  Future<void> _openSubtitleStyle() async {
    final store = widget.subtitleStyleStore;
    if (store == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: store,
        builder: (_, _) {
          final value = store.settings;
          Future<void> apply(SubtitleStyleSettings next) async {
            await store.update(next);
            widget.onSubtitleStyleChanged?.call(next);
          }

          return AlertDialog(
            title: const Text('字幕设置', style: TextStyle(fontSize: 20)),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _styleSlider(
                    keyName: 'subtitle-style-font-size',
                    title: '字体大小',
                    label: '${value.fontSize}',
                    sliderValue: value.fontSize.toDouble(),
                    min: 10,
                    max: 100,
                    onChanged: (next) =>
                        apply(value.copyWith(fontSize: next.round())),
                  ),
                  _styleSlider(
                    keyName: 'subtitle-style-position',
                    title: '位置',
                    label: '${value.position}',
                    sliderValue: value.position.toDouble(),
                    min: 0,
                    max: 100,
                    onChanged: (next) =>
                        apply(value.copyWith(position: next.round())),
                  ),
                  _styleSlider(
                    keyName: 'subtitle-style-border',
                    title: '描边粗细',
                    label: value.borderSize.toStringAsFixed(1),
                    sliderValue: value.borderSize,
                    min: 0,
                    max: 5,
                    onChanged: (next) =>
                        apply(value.copyWith(borderSize: next)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => apply(SubtitleStyleSettings.defaults),
                child: const Text('恢复默认'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _styleSlider({
    required String keyName,
    required String title,
    required String label,
    required double sliderValue,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$title $label', style: const TextStyle(fontSize: 14)),
      Slider(
        key: ValueKey(keyName),
        value: sliderValue.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    ],
  );

  Widget _moreSettings() {
    final preferences = widget.preferences;
    final colors = Theme.of(context).colorScheme;
    final helperStyle = TextStyle(
      fontSize: 12,
      color: colors.onSurfaceVariant,
      height: 1.5,
    );
    final sleepTimer = widget.sleepTimer;
    final overlayStore = widget.overlaySettingsStore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sleepTimer != null)
          AnimatedBuilder(
            animation: sleepTimer,
            builder: (_, _) => _moreRow(
              keyName: 'more-sleep-timer',
              icon: Icons.bedtime_outlined,
              title: '定时关闭',
              subtitle: sleepTimer.active ? sleepTimer.label : null,
              onTap: () => showSleepTimerSheet(
                context,
                controller: sleepTimer,
                onSelect: sleepTimer.select,
              ),
            ),
          ),
        if (widget.onShowAddress != null)
          _moreRow(
            keyName: 'more-playback-address',
            icon: Icons.link_rounded,
            title: '播放地址',
            onTap: () => widget.onShowAddress!(context),
          ),
        if (widget.onReload != null)
          _moreRow(
            keyName: 'more-reload',
            icon: Icons.refresh_rounded,
            title: '重载视频',
            onTap: () => _run(widget.onReload!),
          ),
        // M4 快捷片行：可横滑的胶囊钮行。
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (widget.mpvControls) ...[
                _quickChip(
                  keyName: 'more-flip-horizontal',
                  label: '左右翻转',
                  selected: widget.flipHorizontal,
                  onTap: () =>
                      widget.onFlipHorizontal?.call(!widget.flipHorizontal),
                ),
                _quickChip(
                  keyName: 'more-flip-vertical',
                  label: '上下翻转',
                  selected: widget.flipVertical,
                  onTap: () =>
                      widget.onFlipVertical?.call(!widget.flipVertical),
                ),
                _quickChip(
                  keyName: 'more-audio-only',
                  label: '听视频',
                  selected: widget.audioOnly,
                  onTap: () => widget.onAudioOnly?.call(!widget.audioOnly),
                ),
              ],
              _quickChip(
                keyName: 'more-background-play',
                label: '后台播放',
                selected: preferences.autoPictureInPicture,
                onTap: () => _run(
                  () => widget.onPreferences(
                    preferences.copyWith(
                      autoPictureInPicture: !preferences.autoPictureInPicture,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // M5 播放顺序。
        _moreRow(
          keyName: 'more-play-order',
          icon: Icons.playlist_play_rounded,
          title: '播放顺序',
          subtitle: preferences.autoAdvance ? '自动连播' : '播完暂停',
        ),
        _moreChips<bool>(
          values: const [false, true],
          selected: preferences.autoAdvance,
          labelOf: (value) => value ? '自动连播' : '播完暂停',
          keyOf: (value) => 'more-play-order-${value ? 'advance' : 'stop'}',
          onSelected: (value) => _run(
            () => widget.onPreferences(
              preferences.copyWith(autoAdvance: value),
            ),
          ),
        ),
        if (widget.onSeasonAutoplayChanged != null)
          SwitchListTile.adaptive(
            key: const ValueKey('season-autoplay-switch'),
            contentPadding: const EdgeInsets.only(left: 38),
            title: const Text('跨季自动连播', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              preferences.autoAdvance
                  ? '短剧播完本季最后一集后，倒计时 5 秒自动播放下一季。'
                  : '自动连播未开，本开关暂不生效。',
              style: const TextStyle(fontSize: 12),
            ),
            value: widget.seasonAutoplay,
            onChanged: _busy
                ? null
                : (value) => widget.onSeasonAutoplayChanged!(value),
          ),
        // M6/M7 弹幕。
        if (widget.onLoadDanmakuFromUrl != null &&
            widget.onLoadDanmakuFromFile != null)
          _moreRow(
            keyName: 'more-danmaku-load',
            icon: Icons.file_upload_outlined,
            title: '弹幕加载',
            onTap: () => showDanmakuLoadDialog(
              context,
              onLoadFromUrl: widget.onLoadDanmakuFromUrl!,
              onLoadFromFile: widget.onLoadDanmakuFromFile!,
            ),
          ),
        if (widget.danmakuSettingsStore != null)
          _moreRow(
            keyName: 'more-danmaku-settings',
            icon: Icons.tune_rounded,
            title: '弹幕设置',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    DanmakuSettingsPage(store: widget.danmakuSettingsStore!),
              ),
            ),
          ),
        if (widget.showDanmaku)
          SwitchListTile.adaptive(
            key: const ValueKey('player-danmaku-enabled'),
            contentPadding: const EdgeInsets.only(left: 38),
            title: const Text('弹幕', style: TextStyle(fontSize: 14)),
            subtitle: Text(
              widget.danmakuStatus,
              style: const TextStyle(fontSize: 12),
            ),
            value: preferences.danmaku,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(danmaku: value),
                    ),
                  ),
          ),
        // M8 片头片尾快捷档。
        if (widget.introOutro != null && widget.onIntroOutroChanged != null)
          _moreRow(
            keyName: 'more-intro-outro',
            icon: Icons.skip_next_rounded,
            title: '跳过片头片尾',
            subtitle: widget.introOutro!.isEmpty
                ? '未设置'
                : '片头 ${widget.introOutro!.introSeconds}s · 片尾 ${widget.introOutro!.outroSeconds}s'
                      '${widget.introOutroEnabled ? '' : '（全局关）'}',
            onTap: _openIntroOutroQuick,
          ),
        // M9 长按倍速。
        _moreRow(
          keyName: 'more-hold-speed',
          icon: Icons.fast_forward_rounded,
          title: '长按倍速',
          subtitle: '${speedLabel(preferences.holdSpeed)}x',
        ),
        _moreChips<double>(
          values: holdSpeeds,
          selected: preferences.holdSpeed,
          labelOf: (value) => '${speedLabel(value)}x',
          keyOf: (value) => 'more-hold-speed-$value',
          onSelected: (value) => _run(
            () => widget.onPreferences(preferences.copyWith(holdSpeed: value)),
          ),
        ),
        // 迁入：左右滑动快进/快退秒数。
        _moreRow(
          keyName: 'more-swipe-seek',
          icon: Icons.swipe_rounded,
          title: '左右滑动快进/快退',
          subtitle: '拖满一屏 ${preferences.swipeSeekSeconds} 秒',
        ),
        _moreChips<int>(
          values: swipeSeekChoices,
          selected: preferences.swipeSeekSeconds,
          labelOf: (value) => '$value 秒',
          keyOf: (value) => 'more-swipe-seek-$value',
          onSelected: (value) => _run(
            () => widget.onPreferences(
              preferences.copyWith(swipeSeekSeconds: value),
            ),
          ),
        ),
        // M10 屏显。
        if (overlayStore != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              '屏显',
              style: TextStyle(fontSize: 14, color: colors.onSurface),
            ),
          ),
          AnimatedBuilder(
            animation: overlayStore,
            builder: (_, _) {
              final overlay = overlayStore.settings;
              Widget capsule(String keyName, String label, bool selected,
                  ValueChanged<bool> onTap) =>
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      key: ValueKey(keyName),
                      label: Text(label, style: const TextStyle(fontSize: 13)),
                      selected: selected,
                      onSelected: _busy ? null : onTap,
                    ),
                  );
              return Padding(
                padding: const EdgeInsets.only(left: 38),
                child: Wrap(
                  spacing: 0,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    capsule(
                      'more-overlay-clock',
                      '时间',
                      overlay.showClock,
                      (value) =>
                          overlayStore.update(overlay.copyWith(showClock: value)),
                    ),
                    capsule(
                      'more-overlay-speed',
                      '网速',
                      overlay.showSpeed,
                      (value) =>
                          overlayStore.update(overlay.copyWith(showSpeed: value)),
                    ),
                    capsule(
                      'more-overlay-progress',
                      '进度',
                      overlay.showProgress,
                      (value) => overlayStore.update(
                        overlay.copyWith(showProgress: value),
                      ),
                    ),
                    capsule(
                      'more-overlay-title',
                      '标题',
                      overlay.showTitle,
                      (value) =>
                          overlayStore.update(overlay.copyWith(showTitle: value)),
                    ),
                    IconButton(
                      key: const ValueKey('more-overlay-font-minus'),
                      tooltip: '减小屏显字号',
                      onPressed: overlay.fontSize <= 8
                          ? null
                          : () => overlayStore.update(
                              overlay.copyWith(fontSize: overlay.fontSize - 1),
                            ),
                      icon: const Icon(Icons.remove_rounded, size: 18),
                    ),
                    Text(
                      '${overlay.fontSize}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    IconButton(
                      key: const ValueKey('more-overlay-font-plus'),
                      tooltip: '增大屏显字号',
                      onPressed: overlay.fontSize >= 20
                          ? null
                          : () => overlayStore.update(
                              overlay.copyWith(fontSize: overlay.fontSize + 1),
                            ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                    ),
                  ],
                ),
              );
            },
          ),
          // M11 底部进度条展示。
          _moreRow(
            keyName: 'more-progress-visibility',
            icon: Icons.linear_scale_rounded,
            title: '底部进度条展示',
            subtitle: overlayStore.settings.progressVisibility.label,
          ),
          AnimatedBuilder(
            animation: overlayStore,
            builder: (_, _) => _moreChips<ProgressVisibility>(
              values: ProgressVisibility.values,
              selected: overlayStore.settings.progressVisibility,
              labelOf: (value) => value.label,
              keyOf: (value) => 'more-progress-visibility-${value.name}',
              onSelected: (value) => overlayStore.update(
                overlayStore.settings.copyWith(progressVisibility: value),
              ),
            ),
          ),
        ],
        // M12–M14 解码（仅 MPV 核）。
        if (widget.mpvControls) ...[
          SwitchListTile.adaptive(
            key: const ValueKey('more-hardware-acceleration'),
            contentPadding: const EdgeInsets.only(left: 38),
            title: const Text('硬件加速', style: TextStyle(fontSize: 14)),
            value: preferences.hardwareAcceleration,
            onChanged: _busy
                ? null
                : (value) => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(hardwareAcceleration: value),
                    ),
                  ),
          ),
          _moreRow(
            keyName: 'more-quick-soft-decode',
            icon: Icons.memory_outlined,
            title: '快速切换到软解',
            subtitle: preferences.hardwareAcceleration
                ? '遇到解码器错误时可使用此选项'
                : '当前已是软解',
            onTap: preferences.hardwareAcceleration
                ? () => _run(
                    () => widget.onPreferences(
                      preferences.copyWith(hardwareAcceleration: false),
                    ),
                  )
                : null,
          ),
          _moreRow(
            keyName: 'more-hwdec-mode',
            icon: Icons.developer_board_outlined,
            title: '硬解模式',
            subtitle: '当前：${preferences.effectiveHwdec}',
          ),
          _moreChips<String>(
            values: hwdecModes,
            selected: preferences.hwdecMode,
            labelOf: (value) => value,
            keyOf: (value) => 'more-hwdec-$value',
            enabled: preferences.hardwareAcceleration,
            onSelected: (value) => _run(
              () => widget.onPreferences(
                preferences.copyWith(hwdecMode: value),
              ),
            ),
          ),
        ],
        // M15–M18 轨道与字幕设置。
        if (widget.audioTrackEntries.isNotEmpty) ...[
          _moreRow(
            keyName: 'more-audio-track',
            icon: Icons.audiotrack_rounded,
            title: '音轨选择',
            subtitle: _trackSubtitle(widget.audioTrackEntries, '无音轨'),
          ),
          _trackChips(widget.audioTrackEntries, 'audio'),
        ],
        if (widget.videoTrackEntries.isNotEmpty) ...[
          _moreRow(
            keyName: 'more-video-track',
            icon: Icons.video_settings_rounded,
            title: '视轨选择',
            subtitle: _trackSubtitle(widget.videoTrackEntries, '无视轨'),
          ),
          _trackChips(widget.videoTrackEntries, 'video'),
        ],
        if (widget.subtitleTrackEntries.isNotEmpty) ...[
          _moreRow(
            keyName: 'more-subtitle-track',
            icon: Icons.subtitles_rounded,
            title: '字幕选择',
            subtitle: _trackSubtitle(widget.subtitleTrackEntries, '无字幕'),
          ),
          _trackChips(widget.subtitleTrackEntries, 'sub'),
        ],
        if (widget.mpvControls && widget.subtitleStyleStore != null)
          _moreRow(
            keyName: 'more-subtitle-style',
            icon: Icons.text_fields_rounded,
            title: '字幕设置',
            subtitle: '字体大小、位置、样式等',
            onTap: _openSubtitleStyle,
          ),
        // M19 播放信息。
        if (widget.onShowInfo != null)
          _moreRow(
            keyName: 'more-playback-info',
            icon: Icons.info_outline_rounded,
            title: '播放信息',
            onTap: () => widget.onShowInfo!(context),
          ),
        const Divider(height: 28),
        // 迁入的播放设置组（原设置页「播放设置」剩余项）。
        SwitchListTile.adaptive(
          key: const ValueKey('player-adblock-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('去广告'),
          subtitle: const Text('播放前清洗 m3u8，剔除插播在时间线里的广告分片；关闭后加载原画'),
          value: preferences.adBlock,
          onChanged: _busy
              ? null
              : (value) => _run(
                  () => widget.onPreferences(
                    preferences.copyWith(adBlock: value),
                  ),
                ),
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('player-preload-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('下一集预加载'),
          subtitle: Text(widget.local ? '本地播放不预取网络视频' : widget.preloadStatus),
          value: preferences.preload,
          onChanged: _busy
              ? null
              : (value) => _run(
                  () => widget.onPreferences(preferences.withPreload(value)),
                ),
        ),
        SwitchListTile.adaptive(
          key: const ValueKey('player-seamless-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('无缝播放'),
          subtitle: const Text(
            '开启后换集时下一集首帧已在待命播放器备好，画面直接衔接不黑屏；开启时自动打开预加载，关闭预加载会连带关闭。IJK 内核暂不支持，自动按普通换集播',
          ),
          value: preferences.seamless,
          onChanged: _busy
              ? null
              : (value) => _run(
                  () => widget.onPreferences(preferences.withSeamless(value)),
                ),
        ),
        if (widget.coreFallbackMode != null &&
            widget.onCoreFallbackChanged != null) ...[
          _moreRow(
            keyName: 'more-core-fallback',
            icon: Icons.swap_horiz_rounded,
            title: '核间自动回退',
            subtitle: '播放失败时按 MPV → EXO → IJK 顺序自动换核续播',
          ),
          _moreChips<CoreFallbackMode>(
            values: CoreFallbackMode.values,
            selected: widget.coreFallbackMode!,
            labelOf: (value) => value.label,
            keyOf: (value) => 'more-core-fallback-${value.id}',
            onSelected: (value) => widget.onCoreFallbackChanged!(value),
          ),
        ],
        if (widget.deepSniffer != null && widget.onDeepSnifferChanged != null)
          SwitchListTile.adaptive(
            key: const ValueKey('more-deep-sniffer'),
            contentPadding: EdgeInsets.zero,
            title: const Text('深度嗅探'),
            subtitle: const Text('播不出来时自动嗅探播放地址'),
            value: widget.deepSniffer!,
            onChanged: _busy
                ? null
                : (value) => widget.onDeepSnifferChanged!(value),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('player-favorite'),
          onPressed: _busy ? null : () => _run(widget.onFavorite),
          icon: Icon(
            widget.favorite
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
          ),
          label: Text(widget.favorite ? '取消追剧' : '加入追剧'),
        ),
        const SizedBox(height: 16),
        Text(
          widget.mobile
              ? '上下滑切集；长按画面临时倍速，松开恢复。竖屏轻点暂停，横屏轻点显示控制；双击播放或暂停。'
              : '空格：播放 / 暂停\n左右键：后退 / 快进 5 秒\n长按右键或画面：临时倍速\n上下键：音量 ±5%，M：静音\nF、F11、Ctrl+F：全屏\nEsc：先关闭菜单，再退出全屏',
          style: helperStyle.copyWith(height: 1.6),
        ),
      ],
    );
  }

  Widget _quickChip({
    required String keyName,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      key: ValueKey(keyName),
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: selected,
      onSelected: _busy ? null : (_) => onTap(),
    ),
  );
}

class PlayerEpisodeGrid extends StatelessWidget {
  const PlayerEpisodeGrid({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onSelected,
    this.keyPrefix = 'play-episode',
    this.compact = false,
    this.title = '选集',
  });
  final List<Episode> episodes;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final String keyPrefix;
  final bool compact;
  final String title;
  @override
  Widget build(BuildContext context) => EpisodeBrowser(
    episodes: episodes,
    currentNumber: episodes.isEmpty
        ? null
        : episodes[currentIndex.clamp(0, episodes.length - 1)].number,
    onSelected: onSelected,
    keyPrefix: keyPrefix,
    compact: compact,
    title: title,
  );
}
