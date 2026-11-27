import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'network_speed.dart';
import 'playback_preferences.dart';
import 'player_core.dart';
import 'player_interactions.dart';
import 'player_overlay_settings.dart';
import 'widgets.dart';
import 'video_enhancement.dart';

class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.player,
    required this.interactions,
    required this.enabled,
    required this.fullscreen,
    required this.showOnPlaybackReady,
    required this.onFullscreen,
    required this.onBack,
    required this.onPrevious,
    required this.onNext,
    required this.title,
    required this.onTogglePlayback,
    required this.onEpisodes,
    required this.onSpeed,
    required this.onQuality,
    required this.speed,
    required this.qualityLabel,
    required this.onFocusSurface,
    this.showDanmaku = false,
    this.danmakuEnabled = false,
    this.danmakuStatus = '',
    this.swipeEnabled = false,
    this.panelOpen = false,
    this.pageFullscreen = false,
    this.windowFullscreen = false,
    this.onPageFullscreen,
    this.onExitFullscreen,
    this.onSeek,
    this.onDanmaku,
    this.onRetryDanmaku,
    this.onPictureInPicture,
    this.onSettings,
    this.routeLabel = '',
    this.routeCount = 1,
    this.onRoute,
    this.enhancement,
    this.orientationMode,
    this.onOrientationMode,
    this.networkSpeed,
    this.core,
    this.onCoreTap,
    this.showTopBarBackButton = true,
    this.onControlsVisibilityChanged,
    this.coreOptions,
    this.onCoreSelected,
    this.onCast,
    this.overlaySettings = const OverlayDisplaySettings(),
  });

  final Player player;
  final PlayerInteractions interactions;
  final bool enabled;
  final bool fullscreen;
  final bool pageFullscreen;
  final bool windowFullscreen;
  final bool showOnPlaybackReady;
  final VoidCallback onFullscreen;
  final VoidCallback? onPageFullscreen;
  final VoidCallback? onExitFullscreen;
  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String title;
  final VoidCallback onTogglePlayback;
  final Future<void> Function() onEpisodes;
  final Future<void> Function() onSpeed;
  final Future<void> Function() onQuality;
  final double speed;
  final String qualityLabel;
  final VoidCallback onFocusSurface;
  final bool showDanmaku;
  final bool danmakuEnabled;
  final String danmakuStatus;
  final bool swipeEnabled;
  final bool panelOpen;
  final Future<void> Function(Duration)? onSeek;
  final Future<void> Function()? onDanmaku;
  final Future<void> Function()? onRetryDanmaku;
  final Future<void> Function()? onPictureInPicture;
  final Future<void> Function()? onSettings;
  final String routeLabel;
  final int routeCount;
  final VoidCallback? onRoute;
  final VideoEnhancementController? enhancement;
  final PlaybackOrientationMode? orientationMode;
  final ValueChanged<PlaybackOrientationMode>? onOrientationMode;
  final ValueListenable<String?>? networkSpeed;
  final PlayerCore? core;
  final VoidCallback? onCoreTap;

  /// 顶栏内核下拉（T5）：给了选项与回调时，徽章变下拉浮层
  /// （选中项打勾），不再走 onCoreTap 的居中弹窗。
  final List<PlayerCoreOption>? coreOptions;
  final ValueChanged<PlayerCore>? onCoreSelected;

  /// 投屏入口（T7）：为空时顶栏不显示投屏钮。
  final VoidCallback? onCast;

  /// 屏显设置（M10/M11）：标题/网速/时钟显隐、屏显字号、
  /// 底部进度条常驻策略。
  final OverlayDisplaySettings overlaySettings;

  /// 顶栏是否画返回箭头。宿主在同一角落另有常驻返回时传 false，
  /// 顶栏只留同尺寸占位，避免两个箭头重叠（两者行为相同）。
  final bool showTopBarBackButton;

  /// 控制层显隐变化时通知宿主（字幕抬升用）。值取 _controlsVisible
  /// （面板打开时也算可见），回调走帧后回调，不在构建中触发。
  final ValueChanged<bool>? onControlsVisibilityChanged;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _hideTimer;
  String _clockText = '';
  bool _progressDragging = false;
  bool _visible = true;
  bool _suppressAutoPlaybackStart = false;
  bool _lastPlaying = false;
  bool _pausedBeforeResume = false;
  bool? _lastNotifiedVisible;
  bool _visibilityNotifyPending = false;

  bool get _controlsVisible => _visible || widget.panelOpen;

  /// 把当前显隐值在帧后通知宿主。didUpdateWidget 里直接改 _visible 时
  /// 正处在父构建中，同步回调会触发别的 widget setState，必须帧后发；
  /// 值没变时不重复通知。
  void _scheduleVisibilityNotify() {
    if (widget.onControlsVisibilityChanged == null ||
        _visibilityNotifyPending) {
      return;
    }
    _visibilityNotifyPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityNotifyPending = false;
      if (!mounted) return;
      final visible = _controlsVisible;
      if (_lastNotifiedVisible == visible) return;
      _lastNotifiedVisible = visible;
      widget.onControlsVisibilityChanged!(visible);
    });
  }

  @override
  void initState() {
    super.initState();
    _visible = widget.showOnPlaybackReady;
    _suppressAutoPlaybackStart = !widget.showOnPlaybackReady;
    _lastPlaying = widget.player.state.playing;
    _subscriptions.add(
      widget.player.stream.volume.listen((_) {
        if (!mounted) return;
        setState(() {});
      }),
    );
    // 分辨率上屏（T4）：视频参数变化时重建顶栏信息行。
    _subscriptions.add(
      widget.player.stream.videoParams.listen((_) {
        if (!mounted) return;
        setState(() {});
      }),
    );
    // 时钟不挂周期定时器（会让测试的 pumpAndSettle 永不静止，
    // 真机上也白耗电）：挂载时取一次，其后随播放/缓冲状态变化
    // 与父级重建时顺带刷新，分钟级精度足够。
    _updateClock();
    _subscriptions.add(
      widget.player.stream.buffering.distinct().listen((_) {
        if (!mounted) return;
        _clockText = _clockNowText();
        setState(() {});
        _scheduleHide();
      }),
    );
    _subscriptions.add(
      widget.player.stream.playing.distinct().listen((playing) {
        final wasPlaying = _lastPlaying;
        _lastPlaying = playing;
        if (!mounted || !widget.enabled) return;
        setState(() {});
        if (!playing) {
          if (wasPlaying && !widget.player.state.buffering) {
            _pausedBeforeResume = true;
            _show();
          }
        } else if (!wasPlaying) {
          if (_pausedBeforeResume) {
            _pausedBeforeResume = false;
            _hide();
          } else if (_suppressAutoPlaybackStart) {
            _suppressAutoPlaybackStart = false;
            _scheduleHide();
          } else {
            _show();
          }
        }
      }),
    );
    widget.interactions.addListener(_interactionChanged);
    _scheduleHide();
    _scheduleVisibilityNotify();
  }

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级重建时顺带刷新时钟文本（不另起 setState，本次 build
    // 就会带上新值）。
    _clockText = _clockNowText();
    if (widget.enabled != oldWidget.enabled ||
        widget.panelOpen != oldWidget.panelOpen ||
        widget.fullscreen != oldWidget.fullscreen ||
        widget.pageFullscreen != oldWidget.pageFullscreen ||
        widget.windowFullscreen != oldWidget.windowFullscreen ||
        widget.showOnPlaybackReady != oldWidget.showOnPlaybackReady) {
      if (widget.showOnPlaybackReady) {
        _suppressAutoPlaybackStart = false;
      } else if (widget.enabled && !oldWidget.enabled) {
        _suppressAutoPlaybackStart = !widget.player.state.playing;
      } else if (!widget.enabled && oldWidget.enabled) {
        _suppressAutoPlaybackStart = true;
        _pausedBeforeResume = false;
        _visible = false;
      }
      if (widget.enabled && !oldWidget.enabled) {
        if (widget.showOnPlaybackReady || !widget.player.state.playing) {
          _visible = true;
        } else {
          _visible = false;
        }
      } else if (widget.panelOpen != oldWidget.panelOpen ||
          widget.fullscreen != oldWidget.fullscreen ||
          widget.pageFullscreen != oldWidget.pageFullscreen ||
          widget.windowFullscreen != oldWidget.windowFullscreen) {
        _visible = true;
      }
      _scheduleHide();
      _scheduleVisibilityNotify();
    }
  }

  String _clockNowText() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _updateClock() {
    final text = _clockNowText();
    if (text != _clockText) setState(() => _clockText = text);
  }

  void _interactionChanged() {
    if (!mounted) return;
    if (widget.interactions.boosting) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
      _scheduleVisibilityNotify();
    } else if (widget.interactions.feedback.isNotEmpty &&
        widget.interactions.feedbackRevealsControls) {
      _show();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_visible ||
        !widget.enabled ||
        widget.panelOpen ||
        !widget.player.state.playing ||
        _progressDragging) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          widget.enabled &&
          !widget.panelOpen &&
          widget.player.state.playing &&
          !widget.player.state.buffering &&
          !widget.interactions.boosting &&
          !_progressDragging) {
        setState(() => _visible = false);
        _scheduleVisibilityNotify();
      }
    });
  }

  void _show() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
    _scheduleVisibilityNotify();
  }

  void _hide() {
    _hideTimer?.cancel();
    if (_visible) setState(() => _visible = false);
    _scheduleVisibilityNotify();
  }

  void _tap() {
    if (widget.interactions.suppressTap) return;
    widget.onFocusSurface();
    setState(() => _visible = !_visible);
    _scheduleHide();
    _scheduleVisibilityNotify();
  }

  void _doubleTap() {
    if (!widget.enabled || widget.interactions.suppressTap) return;
    widget.onFocusSurface();
    widget.onTogglePlayback();
  }

  Future<void> _panel(Future<void> Function() open) async {
    _hideTimer?.cancel();
    widget.interactions.cancel();
    await open();
    _show();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hideTimer?.cancel();
    widget.interactions.removeListener(_interactionChanged);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.player.state;
    final visible = _controlsVisible;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            key: const ValueKey('player-gesture-surface'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              widget.onFocusSurface();
              widget.interactions.pointerDown(
                event,
                swipeEnabled: widget.swipeEnabled,
                height: constraints.maxHeight,
                width: constraints.maxWidth,
              );
            },
            onPointerMove: widget.interactions.pointerMove,
            onPointerUp: widget.interactions.pointerUp,
            onPointerCancel: widget.interactions.pointerCancel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tap,
              onDoubleTap: widget.swipeEnabled ? _doubleTap : null,
            ),
          ),
          if (!widget.swipeEnabled) _bottomRevealRegion(),
          if (state.buffering && widget.enabled)
            const IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            ),
          IgnorePointer(
            ignoring: !visible,
            child: ExcludeFocus(
              excluding: !visible,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xAA000000),
                              Colors.transparent,
                              Color(0xE6000000),
                            ],
                            stops: [0, .45, 1],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        8,
                        _topChromeInset(),
                        8,
                        _bottomChromeInset(),
                      ),
                      child: Stack(
                        children: [
                          if (widget.fullscreen || widget.swipeEnabled)
                            _topBar(),
                          if (!state.buffering &&
                              widget.enabled &&
                              constraints.maxHeight >=
                                  (widget.swipeEnabled ? 168 : 220))
                            _centerPlayback(state.playing, showSkip: true),
                          _sideDanmakuControl(),
                          _bottomControls(
                            constraints: constraints,
                            volume: state.volume,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // M11「始终展示」：控制层隐藏时底部进度条单独常驻
          // （可拖动），不随控制层淡出。
          if (!_controlsVisible &&
              widget.enabled &&
              widget.overlaySettings.showProgress &&
              widget.overlaySettings.progressVisibility ==
                  ProgressVisibility.always)
            Positioned(
              left: 0,
              right: 0,
              bottom: _bottomChromeInset(),
              child: _ProgressRow(
                player: widget.player,
                enabled: widget.enabled,
                active: true,
                onSeek: widget.onSeek ?? widget.player.seek,
                onDragStart: () {
                  _progressDragging = true;
                  widget.interactions.cancel();
                  _hideTimer?.cancel();
                },
                onDragEnd: () {
                  _progressDragging = false;
                  _show();
                },
              ),
            ),
          _gestureFeedback(),
          _boostBadge(),
        ],
      ),
    );
  }

  Widget _bottomRevealRegion() => Positioned(
    left: 0,
    right: 0,
    bottom: 0,
    height: 72,
    child: MouseRegion(
      opaque: false,
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (_) => _show(),
      child: const SizedBox.expand(),
    ),
  );

  Widget _topBar() {
    final compact = widget.swipeEnabled && !widget.fullscreen;
    final overlay = widget.overlaySettings;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: compact ? 8 : 0),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _topBarRow(compact, overlay, constraints.maxWidth),
        ),
      ),
    );
  }

  Widget _topBarRow(bool compact, OverlayDisplaySettings overlay, double barWidth) {
    // 窄屏（竖屏手机）顶栏塞不下时钟：<430 时藏时钟，保标题与
    // 内核下拉不被挤溢出（曾溢出 8px 打挂布局断言）。
    final showClock = overlay.showClock && barWidth >= 430;
    return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showTopBarBackButton)
              _overlayIconButton(
                tooltip: widget.fullscreen ? '退出全屏' : '返回',
                onPressed: widget.fullscreen
                    ? (widget.onExitFullscreen ?? widget.onFullscreen)
                    : widget.onBack,
                icon: widget.fullscreen
                    ? Icons.arrow_back_rounded
                    : Icons.arrow_back_ios_new_rounded,
              )
            else
              // 与 _overlayIconButton 同尺寸占位：标题与右侧图标不左移，
              // 不会压到宿主常驻返回按钮上。
              const SizedBox(width: 46, height: 42),
            if (!compact)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (overlay.showTitle)
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    _infoLine(compact: false),
                  ],
                ),
              )
            else
              const Spacer(),
            if (widget.core != null &&
                widget.onCoreSelected != null &&
                widget.coreOptions != null)
              _coreDropdown()
            else if (widget.core != null && widget.onCoreTap != null)
              PlayerCoreBadge(core: widget.core!, onTap: widget.onCoreTap!),
            if (compact && widget.networkSpeed != null && overlay.showSpeed)
              networkSpeedLabel(widget.networkSpeed!),
            if (showClock)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 3,
                  vertical: 10,
                ),
                child: Text(
                  _clockText,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: overlay.fontSize.toDouble(),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            if (widget.onCast != null)
              _overlayIconButton(
                tooltip: '投屏',
                onPressed: widget.onCast,
                icon: Icons.cast_rounded,
              ),
            if (widget.onOrientationMode != null) _orientationMenu(),
            if (compact)
              _overlayIconButton(
                tooltip: '旋转与全屏',
                onPressed: widget.onFullscreen,
                icon: Icons.screen_rotation_alt_rounded,
              ),
          ],
    );
  }

  /// T4 信息行：分辨率（WxH）＋实时网速，13sp，标题正下方。
  /// 分辨率取不到（未出画/非 MPV 路径无尺寸）时只显示网速，
  /// 两样都没有时整行不占位。
  Widget _infoLine({required bool compact}) {
    final state = widget.player.state;
    final resolution =
        (state.width ?? 0) > 0 && (state.height ?? 0) > 0
        ? '${state.width}x${state.height}'
        : '';
    final showSpeed = widget.overlaySettings.showSpeed &&
        widget.networkSpeed != null;
    if (resolution.isEmpty && !showSpeed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (resolution.isNotEmpty)
            Text(
              resolution,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          if (resolution.isNotEmpty && showSpeed) const SizedBox(width: 10),
          if (showSpeed)
            ValueListenableBuilder<String?>(
              valueListenable: widget.networkSpeed!,
              builder: (_, value, _) => Text(
                value ?? '',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  /// T5 内核下拉：胶囊徽章点开浮层，当前核绿色＋✓（对齐参考
  /// 形态），不可用核置灰带原因。
  Widget _coreDropdown() {
    final core = widget.core!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .25)),
        ),
        child: PopupMenuButton<PlayerCore>(
          key: const ValueKey('player-core-dropdown'),
          tooltip: '切换播放器内核',
          enabled: widget.enabled,
          onSelected: widget.onCoreSelected,
          itemBuilder: (_) => [
            for (final option in widget.coreOptions!)
              PopupMenuItem<PlayerCore>(
                value: option.core,
                enabled: option.enabled,
                height: 44,
                child: Row(
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      size: 16,
                      color: option.core == core
                          ? const Color(0xFF55B16C)
                          : Colors.white54,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        option.enabled
                            ? option.core.label
                            : '${option.core.label}（${option.disabledNote ?? '不可用'}）',
                        style: TextStyle(
                          fontSize: 14,
                          color: option.core == core
                              ? const Color(0xFF55B16C)
                              : null,
                        ),
                      ),
                    ),
                    if (option.core == core)
                      const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Color(0xFF55B16C),
                      ),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_arrow_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 2),
                Text(
                  core.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 16,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _orientationMenu() {
    final mode = widget.orientationMode ?? PlaybackOrientationMode.auto;
    final icon = switch (mode) {
      PlaybackOrientationMode.portrait => Icons.stay_primary_portrait_rounded,
      PlaybackOrientationMode.landscape => Icons.stay_primary_landscape_rounded,
      PlaybackOrientationMode.auto => Icons.screen_rotation_alt_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .36),
          borderRadius: BorderRadius.circular(22),
        ),
        child: PopupMenuButton<PlaybackOrientationMode>(
          tooltip: '方向控制',
          initialValue: mode,
          enabled: widget.enabled,
          onSelected: widget.onOrientationMode,
          itemBuilder: (_) => [
            for (final value in PlaybackOrientationMode.values)
              CheckedPopupMenuItem(
                value: value,
                checked: value == mode,
                child: Text(value.label),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _overlayIconButton({
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .36),
        borderRadius: BorderRadius.circular(22),
      ),
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 42, height: 42),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    ),
  );

  Widget _centerPlayback(bool playing, {required bool showSkip}) => Center(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSkip) ...[
          IconButton(
            tooltip: '上一集',
            onPressed: widget.onPrevious,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          const SizedBox(width: 12),
        ],
        IconButton.filledTonal(
          tooltip: playing ? '暂停播放' : '开始播放',
          iconSize: 38,
          onPressed: () {
            widget.onTogglePlayback();
            _show();
          },
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        if (showSkip) ...[
          const SizedBox(width: 12),
          IconButton(
            tooltip: '下一集',
            onPressed: widget.onNext,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ],
    ),
  );

  Widget _sideDanmakuControl() {
    if (!widget.showDanmaku) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(right: widget.swipeEnabled ? 0 : 4),
        child: _danmakuTool(),
      ),
    );
  }

  Widget _bottomControls({
    required BoxConstraints constraints,
    required double volume,
  }) {
    final width = constraints.maxWidth;
    final fullscreen = widget.fullscreen;
    final mobile = widget.swipeEnabled;
    final showEpisodes = !mobile;
    final showSpeedQuality =
        mobile || fullscreen && width >= 720 || !fullscreen && width >= 560;
    final showCompare = fullscreen && width >= 820;
    final showVolume = !widget.swipeEnabled && width >= 360;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mobile)
            _mobileControlRow(fullscreen: fullscreen)
          else
            _desktopControlRow(
              fullscreen: fullscreen,
              showEpisodes: showEpisodes,
              showSpeedQuality: showSpeedQuality,
              showCompare: showCompare,
              showVolume: showVolume,
              volume: volume,
            ),
          if (widget.overlaySettings.showProgress)
            _ProgressRow(
              player: widget.player,
              enabled: widget.enabled,
              active: _controlsVisible,
              onSeek: widget.onSeek ?? widget.player.seek,
              onDragStart: () {
                _progressDragging = true;
                widget.interactions.cancel();
                _hideTimer?.cancel();
              },
              onDragEnd: () {
                _progressDragging = false;
                _show();
              },
            ),
        ],
      ),
    );
  }

  double _topChromeInset() {
    if (widget.fullscreen) {
      final top = MediaQuery.paddingOf(context).top;
      if (top <= 0) return 16;
      return (top + 16).clamp(40.0, 80.0);
    }
    if (widget.swipeEnabled) {
      return 10;
    }
    return 0;
  }

  double _bottomChromeInset() {
    if (widget.fullscreen) {
      return (MediaQuery.viewPaddingOf(context).bottom + 24).clamp(64.0, 104.0);
    }
    return 0;
  }

  Widget _toolIcon({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool selected = false,
  }) => _toolButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    selected: selected,
    child: Icon(icon, size: 22),
  );

  Widget _toolText({
    required Key key,
    required String tooltip,
    required String label,
    required VoidCallback? onPressed,
    double width = 52,
    double fontSize = 12,
  }) => _toolButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    visualWidth: width,
    fontSize: fontSize,
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    ),
  );

  Widget _toolButton({
    required Key key,
    required String tooltip,
    required Widget child,
    required VoidCallback? onPressed,
    bool selected = false,
    double visualWidth = 36,
    double fontSize = 12,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final foreground = selected
        ? scheme.primary
        : Colors.white.withValues(alpha: enabled ? .92 : .36);
    final background = selected
        ? scheme.primary.withValues(alpha: .20)
        : Colors.black.withValues(alpha: .22);
    final border = selected
        ? scheme.primary.withValues(alpha: .62)
        : Colors.white.withValues(alpha: .08);
    final targetWidth = visualWidth < 40 ? 48.0 : visualWidth + 8;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: targetWidth,
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: visualWidth,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: foreground, size: 22),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      color: foreground,
                      fontSize: fontSize,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolGroup(List<Widget> children) =>
      Row(mainAxisSize: MainAxisSize.min, children: children);

  Widget _clusteredToolRow(List<Widget> tools) {
    if (tools.isEmpty) return const SizedBox.shrink();
    if (tools.length <= 5) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [_toolGroup(tools)],
      );
    }
    final leftCount = tools.length ~/ 2;
    return Row(
      children: [
        _toolGroup(tools.take(leftCount).toList()),
        const Spacer(),
        _toolGroup(tools.skip(leftCount).toList()),
      ],
    );
  }

  Widget _danmakuTool() => _toolButton(
    key: const ValueKey('player-danmaku-toggle'),
    tooltip: widget.danmakuStatus.isEmpty
        ? (widget.danmakuEnabled ? '关闭弹幕' : '打开弹幕')
        : widget.danmakuStatus,
    visualWidth: 36,
    selected: widget.danmakuEnabled,
    onPressed: widget.enabled
        ? () => _panel(widget.onRetryDanmaku ?? widget.onDanmaku!)
        : null,
    child: widget.onRetryDanmaku != null
        ? const Icon(Icons.refresh_rounded, size: 21)
        : Text(
            '弹',
            style: TextStyle(
              fontSize: 12,
              height: 1,
              fontWeight: FontWeight.w800,
              color: widget.danmakuEnabled
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: .86),
            ),
          ),
  );

  Widget? _routeTool() {
    if (widget.onRoute == null || widget.routeCount <= 1) return null;
    return _toolText(
      key: const ValueKey('player-route'),
      tooltip: '播放线路',
      label: widget.routeLabel,
      onPressed: widget.enabled ? widget.onRoute : null,
      width: 64,
    );
  }

  Widget _desktopControlRow({
    required bool fullscreen,
    required bool showEpisodes,
    required bool showSpeedQuality,
    required bool showCompare,
    required bool showVolume,
    required double volume,
  }) {
    final routeTool = _routeTool();
    final tools = [
      if (showSpeedQuality) ...[
        _toolText(
          key: const ValueKey('player-speed'),
          tooltip: '倍速',
          label: '${widget.speed}x',
          onPressed: widget.enabled ? () => _panel(widget.onSpeed) : null,
          width: 50,
          fontSize: 13,
        ),
        _toolText(
          key: const ValueKey('player-quality'),
          tooltip: '清晰度',
          label: widget.qualityLabel,
          onPressed: widget.enabled ? () => _panel(widget.onQuality) : null,
          width: 52,
        ),
        if (routeTool != null) routeTool,
      ],
      if (showEpisodes)
        _toolIcon(
          key: const ValueKey('player-episodes'),
          tooltip: '选集',
          icon: Icons.grid_view_rounded,
          onPressed: widget.enabled ? () => _panel(widget.onEpisodes) : null,
        ),
      if (widget.onSettings != null)
        _toolIcon(
          key: const ValueKey('player-settings'),
          tooltip: '更多',
          icon: Icons.more_vert_rounded,
          onPressed: widget.enabled ? () => _panel(widget.onSettings!) : null,
        ),
      if (showCompare) _enhancementCompareButton(),
      if (showVolume)
        _toolIcon(
          key: const ValueKey('player-volume'),
          tooltip: '音量',
          icon: volume == 0
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          onPressed: widget.enabled
              ? () => _panel(() => _openVolume(volume))
              : null,
        ),
      if (widget.onPictureInPicture != null)
        _toolIcon(
          key: const ValueKey('player-picture-in-picture'),
          tooltip: '画中画',
          icon: Icons.picture_in_picture_alt_rounded,
          onPressed: widget.enabled
              ? () => _panel(widget.onPictureInPicture!)
              : null,
        ),
      if (widget.onPageFullscreen != null)
        _toolIcon(
          key: const ValueKey('player-page-fullscreen'),
          tooltip: widget.pageFullscreen ? '退出页面全屏' : '页面全屏',
          icon: widget.pageFullscreen
              ? Icons.fit_screen_rounded
              : Icons.fit_screen_outlined,
          onPressed: widget.onPageFullscreen,
        ),
      _toolIcon(
        key: const ValueKey('player-fullscreen'),
        tooltip: widget.windowFullscreen ? '退出窗口全屏' : '窗口全屏',
        icon: widget.windowFullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        onPressed: widget.onFullscreen,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: _clusteredToolRow(tools),
    );
  }

  Widget _mobileControlRow({required bool fullscreen}) {
    final routeTool = _routeTool();
    final tools = [
      _toolText(
        key: const ValueKey('player-speed'),
        tooltip: '倍速',
        label: '${widget.speed}x',
        onPressed: widget.enabled ? () => _panel(widget.onSpeed) : null,
        width: 50,
        fontSize: 13,
      ),
      _toolText(
        key: const ValueKey('player-quality'),
        tooltip: '清晰度',
        label: widget.qualityLabel,
        onPressed: widget.enabled ? () => _panel(widget.onQuality) : null,
        width: 52,
      ),
      if (routeTool != null) routeTool,
      if (widget.onSettings != null)
        _toolIcon(
          key: const ValueKey('player-settings'),
          tooltip: '更多',
          icon: Icons.more_vert_rounded,
          onPressed: widget.enabled ? () => _panel(widget.onSettings!) : null,
        ),
      if (fullscreen)
        _toolIcon(
          key: const ValueKey('player-episodes'),
          tooltip: '选集',
          icon: Icons.grid_view_rounded,
          onPressed: widget.enabled ? () => _panel(widget.onEpisodes) : null,
        ),
      if (widget.onPictureInPicture != null)
        _toolIcon(
          key: const ValueKey('player-picture-in-picture'),
          tooltip: '画中画',
          icon: Icons.picture_in_picture_alt_rounded,
          onPressed: widget.enabled
              ? () => _panel(widget.onPictureInPicture!)
              : null,
        ),
      _toolIcon(
        key: const ValueKey('player-fullscreen'),
        tooltip: fullscreen ? '退出全屏' : '全屏',
        icon: fullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        onPressed: widget.onFullscreen,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      child: _clusteredToolRow(tools),
    );
  }

  Future<void> _openVolume(double initialVolume) async {
    var volume = initialVolume.clamp(0.0, 100.0);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          StatefulBuilder(
            builder: (context, setState) => SafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: widget.swipeEnabled ? 12 : 20,
                    bottom: widget.fullscreen ? 88 : 74,
                  ),
                  child: Material(
                    color: Colors.black.withValues(alpha: .88),
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 62,
                      height: 192,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: volume == 0 ? '恢复音量' : '静音',
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 40,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              final next = volume == 0 ? 100.0 : 0.0;
                              setState(() => volume = next);
                              unawaited(widget.player.setVolume(next));
                            },
                            icon: Icon(
                              volume == 0
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            height: 112,
                            child: RotatedBox(
                              quarterTurns: -1,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14,
                                  ),
                                ),
                                child: Slider(
                                  value: volume,
                                  max: 100,
                                  divisions: 20,
                                  onChanged: (value) {
                                    setState(() => volume = value);
                                    unawaited(widget.player.setVolume(value));
                                  },
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 28,
                            child: Center(
                              child: Text(
                                '${volume.round()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(.04, .08),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOut),
                  ),
              child: child,
            ),
          ),
    );
  }

  Widget _enhancementCompareButton() {
    final enhancement = widget.enhancement;
    if (enhancement == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: enhancement,
      builder: (_, _) {
        if (!enhancement.canCompare) return const SizedBox.shrink();
        return _toolIcon(
          key: const ValueKey('player-enhancement-compare'),
          tooltip: enhancement.comparing ? '原画对比中，点击恢复增强' : '原画对比',
          icon: Icons.compare_rounded,
          onPressed: widget.enabled
              ? () {
                  widget.interactions.cancel();
                  unawaited(enhancement.toggleCompare());
                  _show();
                }
              : null,
          selected: enhancement.comparing,
        );
      },
    );
  }

  Widget _gestureFeedback() => AnimatedBuilder(
    animation: widget.interactions,
    builder: (context, _) {
      final feedback = widget.interactions.feedback;
      if (feedback.isEmpty) return const SizedBox.shrink();
      return IgnorePointer(
        child: Align(
          alignment: const Alignment(0, -.5),
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              feedback,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _boostBadge() => AnimatedBuilder(
    animation: widget.interactions,
    builder: (context, _) {
      final boosting = widget.interactions.boosting && widget.enabled;
      return IgnorePointer(
        child: AnimatedOpacity(
          key: const ValueKey('player-boost-badge'),
          opacity: boosting ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.only(top: _topChromeInset() + 6, right: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .34),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fast_forward_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${widget.interactions.currentBoostRate.toStringAsFixed(1)}x',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ProgressRow extends StatefulWidget {
  const _ProgressRow({
    required this.player,
    required this.enabled,
    required this.active,
    required this.onSeek,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final Player player;
  final bool enabled;
  final bool active;
  final Future<void> Function(Duration) onSeek;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  @override
  State<_ProgressRow> createState() => _ProgressRowState();
}

class _ProgressRowState extends State<_ProgressRow> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _refreshTimer;
  double? _seekValue;

  @override
  void initState() {
    super.initState();
    for (final stream in [
      widget.player.stream.position,
      widget.player.stream.duration,
      widget.player.stream.buffer,
    ]) {
      _subscriptions.add(stream.listen((_) => _scheduleRefresh()));
    }
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(_ProgressRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) _seekValue = null;
    if (widget.active && !oldWidget.active) _scheduleRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _scheduleRefresh() {
    if (!mounted || !widget.active || _refreshTimer != null) return;
    _refreshTimer = Timer(const Duration(milliseconds: 250), () {
      _refreshTimer = null;
      if (mounted && widget.active) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.player.state;
    final duration = state.duration.inMilliseconds / 1000;
    final position = state.position.inMilliseconds / 1000;
    final buffered = state.buffer.inMilliseconds / 1000;
    // B2：时间上下两行（已播在上、总时长在下），13sp，置于进度条左侧。
    final timeStyle = TextStyle(
      fontSize: 13,
      height: 1.25,
      color: Colors.white.withValues(alpha: .82),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatPosition(_seekValue ?? position),
                    style: timeStyle,
                  ),
                  Text(formatPosition(duration), style: timeStyle),
                ],
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  secondaryActiveTrackColor: Colors.white38,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7.5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  key: const ValueKey('player-progress'),
                  value: (_seekValue ?? position).clamp(
                    0,
                    duration > 0 ? duration : 1,
                  ),
                  max: duration > 0 ? duration : 1,
                  secondaryTrackValue: buffered.clamp(
                    0,
                    duration > 0 ? duration : 1,
                  ),
                  semanticFormatterCallback: formatPosition,
                  onChangeStart: widget.enabled && duration > 0
                      ? (_) => widget.onDragStart()
                      : null,
                  onChanged: !widget.enabled || duration <= 0
                      ? null
                      : (value) {
                          setState(() => _seekValue = value);
                        },
                  onChangeEnd: (value) {
                    if (widget.enabled && duration > 0) {
                      widget.onSeek(
                        Duration(milliseconds: (value * 1000).round()),
                      );
                    }
                    setState(() => _seekValue = null);
                    widget.onDragEnd();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
