import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 弹幕显示设置（对齐参考弹幕设置页 S1–S18）。
///
/// 已接渲染的：海量、随机彩色、显示区域、不透明度、字体粗细、描边、
/// 字体大小、全屏字体大小、滚动时长、静态时长、行高。
/// 渲染未接的特效开关（渐变色/流星拖尾/徽章/TMDB头像/气泡/飘心/
/// 智能方向）字段保留、界面上禁用并标注「暂未支持」，不假装生效。
class DanmakuDisplaySettings {
  const DanmakuDisplaySettings({
    this.massive = false,
    this.randomColor = false,
    this.gradient = false,
    this.meteorTrail = false,
    this.badge = false,
    this.tmdbAvatar = false,
    this.bubble = false,
    this.hearts = false,
    this.smartDirection = false,
    this.displayAreaPercent = 50,
    this.opacityPercent = 100,
    this.fontWeightLevel = 6,
    this.strokeWidth = 1.5,
    this.fontSizePercent = 100,
    this.fullscreenFontSizePercent = 120,
    this.scrollDurationSeconds = 7,
    this.staticDurationSeconds = 4,
    this.lineHeight = 1.6,
  });

  // 开关区（S1–S9）
  final bool massive;
  final bool randomColor;
  final bool gradient;
  final bool meteorTrail;
  final bool badge;
  final bool tmdbAvatar;
  final bool bubble;
  final bool hearts;
  final bool smartDirection;

  // 滑杆区（S10–S18），默认值即各滑杆的「重置」目标。
  final double displayAreaPercent;
  final double opacityPercent;
  final int fontWeightLevel;
  final double strokeWidth;
  final double fontSizePercent;
  final double fullscreenFontSizePercent;
  final double scrollDurationSeconds;
  final double staticDurationSeconds;
  final double lineHeight;

  static const defaults = DanmakuDisplaySettings();

  /// 字体粗细档（1–10）映射到 FontWeight：6 档 ≈ w600。
  FontWeight get fontWeight =>
      FontWeight.values[(fontWeightLevel.clamp(1, 10) - 1).clamp(0, 8)];

  int get scrollLifetimeMs => (scrollDurationSeconds * 1000).round();
  int get staticLifetimeMs => (staticDurationSeconds * 1000).round();

  DanmakuDisplaySettings copyWith({
    bool? massive,
    bool? randomColor,
    bool? gradient,
    bool? meteorTrail,
    bool? badge,
    bool? tmdbAvatar,
    bool? bubble,
    bool? hearts,
    bool? smartDirection,
    double? displayAreaPercent,
    double? opacityPercent,
    int? fontWeightLevel,
    double? strokeWidth,
    double? fontSizePercent,
    double? fullscreenFontSizePercent,
    double? scrollDurationSeconds,
    double? staticDurationSeconds,
    double? lineHeight,
  }) => DanmakuDisplaySettings(
    massive: massive ?? this.massive,
    randomColor: randomColor ?? this.randomColor,
    gradient: gradient ?? this.gradient,
    meteorTrail: meteorTrail ?? this.meteorTrail,
    badge: badge ?? this.badge,
    tmdbAvatar: tmdbAvatar ?? this.tmdbAvatar,
    bubble: bubble ?? this.bubble,
    hearts: hearts ?? this.hearts,
    smartDirection: smartDirection ?? this.smartDirection,
    displayAreaPercent: displayAreaPercent ?? this.displayAreaPercent,
    opacityPercent: opacityPercent ?? this.opacityPercent,
    fontWeightLevel: fontWeightLevel ?? this.fontWeightLevel,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    fontSizePercent: fontSizePercent ?? this.fontSizePercent,
    fullscreenFontSizePercent:
        fullscreenFontSizePercent ?? this.fullscreenFontSizePercent,
    scrollDurationSeconds: scrollDurationSeconds ?? this.scrollDurationSeconds,
    staticDurationSeconds: staticDurationSeconds ?? this.staticDurationSeconds,
    lineHeight: lineHeight ?? this.lineHeight,
  );

  Map<String, dynamic> toJson() => {
    'massive': massive,
    'randomColor': randomColor,
    'gradient': gradient,
    'meteorTrail': meteorTrail,
    'badge': badge,
    'tmdbAvatar': tmdbAvatar,
    'bubble': bubble,
    'hearts': hearts,
    'smartDirection': smartDirection,
    'displayAreaPercent': displayAreaPercent,
    'opacityPercent': opacityPercent,
    'fontWeightLevel': fontWeightLevel,
    'strokeWidth': strokeWidth,
    'fontSizePercent': fontSizePercent,
    'fullscreenFontSizePercent': fullscreenFontSizePercent,
    'scrollDurationSeconds': scrollDurationSeconds,
    'staticDurationSeconds': staticDurationSeconds,
    'lineHeight': lineHeight,
  };

  factory DanmakuDisplaySettings.fromJson(Map<String, dynamic> value) {
    double readDouble(String key, double fallback) =>
        (value[key] as num?)?.toDouble() ?? fallback;
    return DanmakuDisplaySettings(
      massive: value['massive'] as bool? ?? false,
      randomColor: value['randomColor'] as bool? ?? false,
      gradient: value['gradient'] as bool? ?? false,
      meteorTrail: value['meteorTrail'] as bool? ?? false,
      badge: value['badge'] as bool? ?? false,
      tmdbAvatar: value['tmdbAvatar'] as bool? ?? false,
      bubble: value['bubble'] as bool? ?? false,
      hearts: value['hearts'] as bool? ?? false,
      smartDirection: value['smartDirection'] as bool? ?? false,
      displayAreaPercent: readDouble('displayAreaPercent', 50).clamp(10, 100),
      opacityPercent: readDouble('opacityPercent', 100).clamp(10, 100),
      fontWeightLevel: (value['fontWeightLevel'] as num?)?.round() ?? 6,
      strokeWidth: readDouble('strokeWidth', 1.5).clamp(0, 3),
      fontSizePercent: readDouble('fontSizePercent', 100).clamp(50, 200),
      fullscreenFontSizePercent: readDouble(
        'fullscreenFontSizePercent',
        120,
      ).clamp(50, 200),
      scrollDurationSeconds: readDouble(
        'scrollDurationSeconds',
        7,
      ).clamp(3, 15),
      staticDurationSeconds: readDouble(
        'staticDurationSeconds',
        4,
      ).clamp(2, 10),
      lineHeight: readDouble('lineHeight', 1.6).clamp(1, 2.5),
    );
  }
}

/// 弹幕显示设置的单例存储：SharedPreferences 单键 JSON，
/// 读写失败不抛、保持现值（与 LiveSettingsStore 同口径）。
class DanmakuSettingsStore extends ChangeNotifier {
  DanmakuSettingsStore._();

  static final DanmakuSettingsStore instance = DanmakuSettingsStore._();
  static const String storageKey = 'moyi_danmaku_display';

  DanmakuDisplaySettings _settings = const DanmakuDisplaySettings();
  bool _loaded = false;
  bool _loading = false;

  DanmakuDisplaySettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        _settings = DanmakuDisplaySettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // 保持默认值与未加载标记，后续访问可重试。
    } finally {
      _loading = false;
    }
  }

  Future<void> update(DanmakuDisplaySettings next) async {
    _settings = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(next.toJson()));
    } catch (_) {
      // 落盘失败不回滚内存值，下次启动按盘上旧值走。
    }
  }
}

/// 弹幕设置整页（底部弹出页形态：由调用方以页面/弹窗承载均可）。
class DanmakuSettingsPage extends StatelessWidget {
  const DanmakuSettingsPage({super.key, required this.store});

  final DanmakuSettingsStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('弹幕设置')),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final settings = store.settings;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              _switch(
                keyName: 'danmaku-set-massive',
                title: '海量弹幕',
                value: settings.massive,
                onChanged: (value) =>
                    store.update(settings.copyWith(massive: value)),
              ),
              _switch(
                keyName: 'danmaku-set-random-color',
                title: '随机彩色',
                value: settings.randomColor,
                onChanged: (value) =>
                    store.update(settings.copyWith(randomColor: value)),
              ),
              _unsupportedSwitch('danmaku-set-gradient', '弹幕渐变色'),
              _unsupportedSwitch('danmaku-set-meteor', '流星拖尾'),
              _unsupportedSwitch('danmaku-set-badge', '徽章弹幕'),
              _unsupportedSwitch(
                'danmaku-set-tmdb-avatar',
                'TMDB演员头像优先',
                subtitle: '详情已识别演员时优先作为徽章',
              ),
              _unsupportedSwitch('danmaku-set-bubble', '气泡弹幕'),
              _unsupportedSwitch('danmaku-set-hearts', '飘心弹幕'),
              _unsupportedSwitch('danmaku-set-smart-direction', '智能方向弹幕'),
              const Divider(height: 28),
              _slider(
                keyName: 'danmaku-set-area',
                title: '显示区域',
                label: '${settings.displayAreaPercent.toStringAsFixed(1)}%',
                value: settings.displayAreaPercent,
                min: 10,
                max: 100,
                divisions: 18,
                resetValue: DanmakuDisplaySettings.defaults.displayAreaPercent,
                onChanged: (value) =>
                    store.update(settings.copyWith(displayAreaPercent: value)),
              ),
              _slider(
                keyName: 'danmaku-set-opacity',
                title: '不透明度',
                label: '${settings.opacityPercent.toStringAsFixed(1)}%',
                value: settings.opacityPercent,
                min: 10,
                max: 100,
                divisions: 18,
                resetValue: DanmakuDisplaySettings.defaults.opacityPercent,
                onChanged: (value) =>
                    store.update(settings.copyWith(opacityPercent: value)),
              ),
              _slider(
                keyName: 'danmaku-set-weight',
                title: '字体粗细',
                label: '${settings.fontWeightLevel}',
                note: '可能无法精确调节',
                value: settings.fontWeightLevel.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                resetValue: DanmakuDisplaySettings.defaults.fontWeightLevel
                    .toDouble(),
                onChanged: (value) => store.update(
                  settings.copyWith(fontWeightLevel: value.round()),
                ),
              ),
              _slider(
                keyName: 'danmaku-set-stroke',
                title: '描边粗细',
                label: settings.strokeWidth.toStringAsFixed(1),
                value: settings.strokeWidth,
                min: 0,
                max: 3,
                divisions: 12,
                resetValue: DanmakuDisplaySettings.defaults.strokeWidth,
                onChanged: (value) =>
                    store.update(settings.copyWith(strokeWidth: value)),
              ),
              _slider(
                keyName: 'danmaku-set-font-size',
                title: '字体大小',
                label: '${settings.fontSizePercent.toStringAsFixed(1)}%',
                value: settings.fontSizePercent,
                min: 50,
                max: 200,
                divisions: 30,
                resetValue: DanmakuDisplaySettings.defaults.fontSizePercent,
                onChanged: (value) =>
                    store.update(settings.copyWith(fontSizePercent: value)),
              ),
              _slider(
                keyName: 'danmaku-set-fs-font-size',
                title: '全屏字体大小',
                label:
                    '${settings.fullscreenFontSizePercent.toStringAsFixed(1)}%',
                value: settings.fullscreenFontSizePercent,
                min: 50,
                max: 200,
                divisions: 30,
                resetValue:
                    DanmakuDisplaySettings.defaults.fullscreenFontSizePercent,
                onChanged: (value) => store.update(
                  settings.copyWith(fullscreenFontSizePercent: value),
                ),
              ),
              _slider(
                keyName: 'danmaku-set-scroll-duration',
                title: '滚动弹幕时长',
                label: '${settings.scrollDurationSeconds.toStringAsFixed(1)} 秒',
                value: settings.scrollDurationSeconds,
                min: 3,
                max: 15,
                divisions: 24,
                resetValue:
                    DanmakuDisplaySettings.defaults.scrollDurationSeconds,
                onChanged: (value) => store.update(
                  settings.copyWith(scrollDurationSeconds: value),
                ),
              ),
              _slider(
                keyName: 'danmaku-set-static-duration',
                title: '静态弹幕时长',
                label: '${settings.staticDurationSeconds.toStringAsFixed(1)} 秒',
                value: settings.staticDurationSeconds,
                min: 2,
                max: 10,
                divisions: 16,
                resetValue:
                    DanmakuDisplaySettings.defaults.staticDurationSeconds,
                onChanged: (value) => store.update(
                  settings.copyWith(staticDurationSeconds: value),
                ),
              ),
              _slider(
                keyName: 'danmaku-set-line-height',
                title: '弹幕行高',
                label: settings.lineHeight.toStringAsFixed(1),
                value: settings.lineHeight,
                min: 1,
                max: 2.5,
                divisions: 15,
                resetValue: DanmakuDisplaySettings.defaults.lineHeight,
                onChanged: (value) =>
                    store.update(settings.copyWith(lineHeight: value)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _switch({
    required String keyName,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile.adaptive(
    key: ValueKey(keyName),
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontSize: 14)),
    value: value,
    onChanged: onChanged,
  );

  Widget _unsupportedSwitch(String keyName, String title, {String? subtitle}) =>
      SwitchListTile.adaptive(
        key: ValueKey(keyName),
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          subtitle == null ? '暂未支持' : '$subtitle · 暂未支持',
          style: const TextStyle(fontSize: 12),
        ),
        value: false,
        onChanged: null,
      );

  Widget _slider({
    required String keyName,
    required String title,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required double resetValue,
    required ValueChanged<double> onChanged,
    String? note,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                note == null ? '$title $label' : '$title $label（$note）',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            TextButton(
              key: ValueKey('$keyName-reset'),
              onPressed: value == resetValue
                  ? null
                  : () => onChanged(resetValue),
              child: const Text('重置', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        Slider(
          key: ValueKey(keyName),
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
