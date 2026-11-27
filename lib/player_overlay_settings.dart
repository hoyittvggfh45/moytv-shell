import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 底部进度条展示方式（M11）。
enum ProgressVisibility {
  /// 控制层隐藏时进度条仍常驻底部。
  always('始终展示'),

  /// 只在拖动进度时出现（随控制层显隐）。
  onDrag('仅拖动展示');

  const ProgressVisibility(this.label);
  final String label;
}

/// 播放器屏显设置（M10 屏显四项＋字号、M11 底部进度条展示）。
///
/// 与播放偏好分开存：这是控制层外观，不进 PlaybackPreferences。
class OverlayDisplaySettings {
  const OverlayDisplaySettings({
    this.showClock = true,
    this.showSpeed = true,
    this.showProgress = true,
    this.showTitle = true,
    this.fontSize = 12,
    this.progressVisibility = ProgressVisibility.always,
  });

  final bool showClock;
  final bool showSpeed;
  final bool showProgress;
  final bool showTitle;

  /// 屏显字号（步进器 8–20，默认 12，对齐参考步进器口径）。
  final int fontSize;
  final ProgressVisibility progressVisibility;

  OverlayDisplaySettings copyWith({
    bool? showClock,
    bool? showSpeed,
    bool? showProgress,
    bool? showTitle,
    int? fontSize,
    ProgressVisibility? progressVisibility,
  }) => OverlayDisplaySettings(
    showClock: showClock ?? this.showClock,
    showSpeed: showSpeed ?? this.showSpeed,
    showProgress: showProgress ?? this.showProgress,
    showTitle: showTitle ?? this.showTitle,
    fontSize: fontSize ?? this.fontSize,
    progressVisibility: progressVisibility ?? this.progressVisibility,
  );

  Map<String, dynamic> toJson() => {
    'showClock': showClock,
    'showSpeed': showSpeed,
    'showProgress': showProgress,
    'showTitle': showTitle,
    'fontSize': fontSize,
    'progressVisibility': progressVisibility.name,
  };

  factory OverlayDisplaySettings.fromJson(Map<String, dynamic> value) =>
      OverlayDisplaySettings(
        showClock: value['showClock'] as bool? ?? true,
        showSpeed: value['showSpeed'] as bool? ?? true,
        showProgress: value['showProgress'] as bool? ?? true,
        showTitle: value['showTitle'] as bool? ?? true,
        fontSize: ((value['fontSize'] as num?)?.round() ?? 12).clamp(8, 20),
        progressVisibility:
            ProgressVisibility.values.asNameMap()[value['progressVisibility']] ??
            ProgressVisibility.always,
      );
}

/// 屏显设置单例存储（与 DanmakuSettingsStore 同口径）。
class OverlaySettingsStore extends ChangeNotifier {
  OverlaySettingsStore._();

  static final OverlaySettingsStore instance = OverlaySettingsStore._();
  static const String storageKey = 'moyi_overlay_display';

  OverlayDisplaySettings _settings = const OverlayDisplaySettings();
  bool _loaded = false;
  bool _loading = false;

  OverlayDisplaySettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        _settings = OverlayDisplaySettings.fromJson(
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

  Future<void> update(OverlayDisplaySettings next) async {
    _settings = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(next.toJson()));
    } catch (_) {
      // 落盘失败不回滚内存值。
    }
  }
}
