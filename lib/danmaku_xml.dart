import 'danmaku_models.dart';

/// B 站弹幕 XML 解析（纯函数，可单测）。
///
/// 格式：`<d p="时间秒,模式,字号,颜色十进制,时间戳,池,用户,rowid">文本</d>`。
/// 模式映射：1/2/3 → 滚动，5 → 顶部，4 → 底部，6 → 反向，其余按滚动。
/// 解析只认结构合法的行：p 属性至少 4 段、时间可解析、文本非空；
/// 坏行跳过不抛错，整体不是 XML 时返回空列表（调用方据条数报错）。
List<DanmakuItem> parseBilibiliDanmakuXml(String xml) {
  final items = <DanmakuItem>[];
  final seen = <String>{};
  final pattern = RegExp(r'<d\s+p="([^"]*)"[^>]*>(.*?)</d>', dotAll: true);
  for (final match in pattern.allMatches(xml)) {
    final attrs = match.group(1)!.split(',');
    if (attrs.length < 4) continue;
    final seconds = double.tryParse(attrs[0].trim());
    if (seconds == null || seconds < 0) continue;
    final modeValue = int.tryParse(attrs[1].trim()) ?? 1;
    final mode = switch (modeValue) {
      5 => DanmakuMode.top,
      4 => DanmakuMode.bottom,
      6 => DanmakuMode.reverse,
      _ => DanmakuMode.scroll,
    };
    final colorDecimal = int.tryParse(attrs[3].trim());
    final colorValue = colorDecimal == null
        ? null
        : 0xFF000000 | (colorDecimal & 0xFFFFFF);
    final text = trimDanmakuText(
      _unescapeXml(match.group(2)!).trim(),
      181,
    );
    if (text.isEmpty) continue;
    final rowId = attrs.length > 7 ? attrs[7].trim() : '';
    final id = rowId.isNotEmpty
        ? 'xml:$rowId'
        : 'xml:${items.length}:${(seconds * 1000).round()}';
    if (!seen.add(id)) continue;
    items.add(
      DanmakuItem(
        id: id,
        text: text,
        timeMs: (seconds * 1000).round(),
        mode: mode,
        colorValue: colorValue == 0xFFFFFFFF ? null : colorValue,
      ),
    );
  }
  items.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return items;
}

String _unescapeXml(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
