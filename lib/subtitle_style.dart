import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 字幕样式设置（M18，仅 MPV 核）：字体大小、位置、描边。
///
/// 落到 MPV 属性：sub-font-size（相对值）、sub-pos（0 顶部–100 底部）、
/// sub-border-size（描边）。外挂/内嵌字幕都吃这组属性；EXO/IJK 核
/// 没有同等属性面，菜单里不显示本项。
class SubtitleStyleSettings {
  const SubtitleStyleSettings({
    this.fontSize = 55,
    this.position = 100,
    this.borderSize = 1,
  });

  /// MPV sub-font-size：10–100，默认 55（MPV 自身默认量级）。
  final int fontSize;

  /// MPV sub-pos：0–100，100 = 贴底（默认）。
  final int position;

  /// MPV sub-border-size：0–5，默认 1。
  final double borderSize;

  static const defaults = SubtitleStyleSettings();

  SubtitleStyleSettings copyWith({
    int? fontSize,
    int? position,
    double? borderSize,
  }) => SubtitleStyleSettings(
    fontSize: fontSize ?? this.fontSize,
    position: position ?? this.position,
    borderSize: borderSize ?? this.borderSize,
  );

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'position': position,
    'borderSize': borderSize,
  };

  factory SubtitleStyleSettings.fromJson(Map<String, dynamic> value) =>
      SubtitleStyleSettings(
        fontSize: ((value['fontSize'] as num?)?.round() ?? 55).clamp(10, 100),
        position: ((value['position'] as num?)?.round() ?? 100).clamp(0, 100),
        borderSize: ((value['borderSize'] as num?)?.toDouble() ?? 1).clamp(
          0,
          5,
        ),
      );

  /// 把样式下发给 MPV；非 NativePlayer 时空操作。失败不抛
  /// （字幕样式不挡播放，调用方无需处理）。
  Future<void> applyTo(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty('sub-font-size', '$fontSize');
      await platform.setProperty('sub-pos', '$position');
      await platform.setProperty('sub-border-size', '$borderSize');
    } catch (_) {
      // 属性下发失败保持播放器现状。
    }
  }
}

/// 字幕样式单例存储（与 DanmakuSettingsStore 同口径）。
class SubtitleStyleStore extends ChangeNotifier {
  SubtitleStyleStore._();

  static final SubtitleStyleStore instance = SubtitleStyleStore._();
  static const String storageKey = 'moyi_subtitle_style';

  SubtitleStyleSettings _settings = const SubtitleStyleSettings();
  bool _loaded = false;
  bool _loading = false;

  SubtitleStyleSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        _settings = SubtitleStyleSettings.fromJson(
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

  Future<void> update(SubtitleStyleSettings next) async {
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
