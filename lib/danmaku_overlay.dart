import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'danmaku_controller.dart';
import 'danmaku_models.dart';
import 'danmaku_settings.dart';

class DanmakuFlight {
  const DanmakuFlight(this.item, this.text, this.lane, this.width);
  final DanmakuItem item;
  final String text;
  final int lane;
  final double width;

  bool get reverse => item.mode == DanmakuMode.reverse;
}

List<DanmakuFlight> planDanmaku(
  List<DanmakuItem> items, {
  required double width,
  required int rows,
  required double Function(String) measure,
  int lifetimeMs = danmakuLifetimeMs,
  int maxConcurrent = 24,
  int maxRows = 4,
}) {
  if (!width.isFinite || width <= 0 || rows < 1) return const [];
  final lanes = List<DanmakuFlight?>.filled(rows.clamp(1, maxRows), null);
  final sorted = items.toList()..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final seen = <String>{};
  final flights = <DanmakuFlight>[];
  for (final item in sorted) {
    if (item.id.isEmpty ||
        item.text.trim().isEmpty ||
        item.timeMs < 0 ||
        !seen.add(item.id)) {
      continue;
    }
    if (flights.reversed
            .takeWhile((flight) => item.timeMs - flight.item.timeMs < lifetimeMs)
            .length >=
        maxConcurrent) {
      continue;
    }
    final runes = item.text.runes;
    final text =
        trimDanmakuText(item.text, 100) + (runes.length > 100 ? '…' : '');
    final size = measure(text).ceilToDouble() + 8;
    final lane = lanes.indexWhere((previous) {
      if (previous == null) return true;
      final gap = item.timeMs - previous.item.timeMs;
      if (gap >= lifetimeMs) return true;
      return (width + previous.width) * gap / lifetimeMs - previous.width >=
              24 &&
          width - (width + size) * (lifetimeMs - gap) / lifetimeMs >= 24;
    });
    if (lane < 0) continue;
    final flight = DanmakuFlight(item, text, lane, size);
    lanes[lane] = flight;
    flights.add(flight);
  }
  return flights;
}

/// 随机彩色：按条目 id 哈希从亮色板里定一条颜色（同一条弹幕
/// 每次同色，不闪烁）。
Color danmakuRandomColor(String id) {
  const palette = [
    Color(0xFFFF6B6B),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFFB983FF),
    Color(0xFFFF9F45),
    Color(0xFF00C9A7),
    Color(0xFFF473B9),
  ];
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.controller,
    required this.aspectRatio,
    this.settings = const DanmakuDisplaySettings(),
    this.fullscreen = false,
  });
  final DanmakuController controller;
  final double aspectRatio;

  /// 弹幕显示设置（S10–S18 等）：由宿主从 DanmakuSettingsStore 传入，
  /// 改设置后宿主重建本控件即生效。
  final DanmakuDisplaySettings settings;
  final bool fullscreen;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  Object? _layout;
  List<DanmakuFlight> _schedule = const [];

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            return const SizedBox.shrink();
          }
          final aspect = widget.aspectRatio.isFinite && widget.aspectRatio > 0
              ? widget.aspectRatio
              : 16 / 9;
          final width = math.min(
            constraints.maxWidth,
            constraints.maxHeight * aspect,
          );
          final height = math.min(
            constraints.maxHeight,
            constraints.maxWidth / aspect,
          );
          final settings = widget.settings;
          final fontScale =
              (widget.fullscreen
                  ? settings.fullscreenFontSizePercent
                  : settings.fontSizePercent) /
              100;
          final fontSize = 12.0 * fontScale;
          final scaler = MediaQuery.textScalerOf(context);
          final rowHeight = scaler.scale(fontSize) * settings.lineHeight;
          final maxRows = settings.massive ? 8 : 4;
          final rows = ((height * settings.displayAreaPercent / 100 - 8) /
                  rowHeight)
              .floor()
              .clamp(0, maxRows);
          final stroke = settings.strokeWidth;
          final style = TextStyle(
            fontSize: fontSize,
            fontWeight: settings.fontWeight,
            color: Colors.white,
            height: 1.2,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 2 * stroke,
                offset: Offset(stroke, stroke),
              ),
            ],
          );
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final controller = widget.controller;
                    if (!controller.anyVisible || rows == 0) {
                      return const SizedBox.shrink();
                    }
                    final layout = (
                      controller,
                      controller.dataRevision,
                      width,
                      rows,
                      fontSize,
                      scaler,
                      settings,
                      widget.fullscreen,
                    );
                    if (_layout != layout) {
                      _layout = layout;
                      _schedule = planDanmaku(
                        controller.items
                            .where(
                              (item) =>
                                  item.mode == DanmakuMode.scroll ||
                                  item.mode == DanmakuMode.reverse,
                            )
                            .toList(),
                        width: width,
                        rows: rows,
                        lifetimeMs: settings.scrollLifetimeMs,
                        maxConcurrent: settings.massive ? 80 : 24,
                        maxRows: maxRows,
                        measure: (text) {
                          final painter = TextPainter(
                            text: TextSpan(text: text, style: style),
                            textDirection: TextDirection.ltr,
                            textScaler: scaler,
                            maxLines: 1,
                          )..layout();
                          final measured = painter.width;
                          painter.dispose();
                          return measured;
                        },
                      );
                    }
                    final statics = controller.items.where(
                      (item) =>
                          item.mode == DanmakuMode.top ||
                          item.mode == DanmakuMode.bottom,
                    );
                    final topStatics = <DanmakuItem>[];
                    final bottomStatics = <DanmakuItem>[];
                    for (final item in statics) {
                      if (controller.positionMs < item.timeMs ||
                          controller.positionMs >=
                              item.timeMs + settings.staticLifetimeMs) {
                        continue;
                      }
                      final bucket = item.mode == DanmakuMode.top
                          ? topStatics
                          : bottomStatics;
                      if (bucket.length < 3) bucket.add(item);
                    }
                    return Opacity(
                      opacity: settings.opacityPercent / 100,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final flight in _schedule)
                            if (controller.positionMs >= flight.item.timeMs &&
                                controller.positionMs <
                                    flight.item.timeMs +
                                        settings.scrollLifetimeMs)
                              Positioned(
                                key: ValueKey(
                                  'danmaku-item-${flight.item.id}',
                                ),
                                left: 0,
                                top: 8 + flight.lane * rowHeight,
                                width: flight.width,
                                height: rowHeight,
                                child: _DanmakuMotion(
                                  flight: flight,
                                  width: width,
                                  positionMs: controller.positionMs,
                                  moving: controller.anyMoving,
                                  rate: controller.rate,
                                  revision: controller.motionRevision,
                                  style: _styleFor(flight.item, settings, style),
                                  scaler: scaler,
                                  lifetimeMs: settings.scrollLifetimeMs,
                                ),
                              ),
                          for (var i = 0; i < topStatics.length; i++)
                            Positioned(
                              key: ValueKey(
                                'danmaku-item-${topStatics[i].id}',
                              ),
                              left: 0,
                              right: 0,
                              top: 8 + i * rowHeight,
                              height: rowHeight,
                              child: Center(
                                child: Text(
                                  topStatics[i].text,
                                  style: _styleFor(
                                    topStatics[i],
                                    settings,
                                    style,
                                  ),
                                  textScaler: scaler,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                          for (var i = 0; i < bottomStatics.length; i++)
                            Positioned(
                              key: ValueKey(
                                'danmaku-item-${bottomStatics[i].id}',
                              ),
                              left: 0,
                              right: 0,
                              bottom: 8 + i * rowHeight,
                              height: rowHeight,
                              child: Center(
                                child: Text(
                                  bottomStatics[i].text,
                                  style: _styleFor(
                                    bottomStatics[i],
                                    settings,
                                    style,
                                  ),
                                  textScaler: scaler,
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// 单条弹幕的实际样式：条目自带颜色优先，其次随机彩色设置，
/// 都没有时用基础样式（白色）。
TextStyle _styleFor(
  DanmakuItem item,
  DanmakuDisplaySettings settings,
  TextStyle base,
) {
  if (item.colorValue != null) {
    return base.copyWith(color: Color(item.colorValue!));
  }
  if (settings.randomColor) {
    return base.copyWith(color: danmakuRandomColor(item.id));
  }
  return base;
}

class _DanmakuMotion extends StatefulWidget {
  const _DanmakuMotion({
    required this.flight,
    required this.width,
    required this.positionMs,
    required this.moving,
    required this.rate,
    required this.revision,
    required this.style,
    required this.scaler,
    this.lifetimeMs = danmakuLifetimeMs,
  });
  final DanmakuFlight flight;
  final double width;
  final int positionMs;
  final bool moving;
  final double rate;
  final int revision;
  final TextStyle style;
  final TextScaler scaler;
  final int lifetimeMs;

  @override
  State<_DanmakuMotion> createState() => _DanmakuMotionState();
}

class _DanmakuMotionState extends State<_DanmakuMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_DanmakuMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.width != widget.width ||
        oldWidget.flight.width != widget.flight.width ||
        oldWidget.lifetimeMs != widget.lifetimeMs ||
        oldWidget.flight.item.timeMs != widget.flight.item.timeMs) {
      _sync();
    }
  }

  void _sync() {
    _motion.stop();
    final lifetime = widget.lifetimeMs;
    final elapsed = (widget.positionMs - widget.flight.item.timeMs).clamp(
      0,
      lifetime,
    );
    _motion.value = elapsed / lifetime;
    if (widget.moving && elapsed < lifetime) {
      _motion.animateTo(
        1,
        duration: Duration(
          microseconds: ((lifetime - elapsed) * 1000 / widget.rate)
              .round()
              .clamp(1, 86400000000),
        ),
        curve: Curves.linear,
      );
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _motion,
    child: RepaintBoundary(
      child: Text(
        widget.flight.text,
        style: widget.style,
        textScaler: widget.scaler,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        softWrap: false,
      ),
    ),
    builder: (context, child) => Transform.translate(
      key: ValueKey('danmaku-motion-${widget.flight.item.id}'),
      offset: Offset(
        widget.flight.reverse
            ? -widget.flight.width +
                  (widget.width + widget.flight.width) * _motion.value
            : widget.width -
                  (widget.width + widget.flight.width) * _motion.value,
        0,
      ),
      child: child,
    ),
  );
}
