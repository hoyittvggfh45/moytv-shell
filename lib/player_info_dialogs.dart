import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'intro_outro_skip.dart';

/// 播放地址信息（A1–A4）：数据由播放链现成字段汇总，缺哪段不显示
/// 哪段，不编造。
class PlaybackAddressInfo {
  const PlaybackAddressInfo({
    this.flag = '',
    this.originalUrl = '',
    this.actualUrl = '',
    this.headers = const {},
  });

  /// 播放源（flag）：集数据自带的 flag，源没给时为空。
  final String flag;

  /// 原始链接：源站给的地址。
  final String originalUrl;

  /// 实际播放地址：处理后真正在播的地址。
  final String actualUrl;

  /// 请求头。
  final Map<String, String> headers;

  bool get isEmpty =>
      flag.isEmpty &&
      originalUrl.isEmpty &&
      actualUrl.isEmpty &&
      headers.isEmpty;

  List<(String, String)> get sections => [
    if (flag.isNotEmpty) ('播放源', flag),
    if (originalUrl.isNotEmpty) ('原始链接', originalUrl),
    if (actualUrl.isNotEmpty) ('实际播放地址', actualUrl),
    if (headers.isNotEmpty)
      (
        '请求头（Headers）',
        headers.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n'),
      ),
  ];
}

const _dialogTitleStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
const _dialogBodyStyle = TextStyle(fontSize: 13, height: 1.45);

/// 播放地址信息弹窗（A1–A5：四段各带复制钮）。
Future<void> showPlaybackAddressDialog(
  BuildContext context,
  PlaybackAddressInfo info,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('播放地址信息', style: _dialogTitleStyle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.isEmpty)
                const Text('暂无可显示的地址信息', style: _dialogBodyStyle),
              for (final (name, value) in info.sections) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('address-copy-$name'),
                      tooltip: '复制',
                      iconSize: 18,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: value));
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            const SnackBar(content: Text('已复制')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      dialogContext,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    value,
                    style: _dialogBodyStyle.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 播放信息弹窗（I1–I9）：分段 dump，段名＋值原样呈现；
/// 取不到的段调用方就不传，不显示不编造。
Future<void> showPlaybackInfoDialog(
  BuildContext context,
  List<(String, String)> sections,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('播放信息', style: _dialogTitleStyle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sections.isEmpty)
                const Text('当前内核暂不提供播放信息', style: _dialogBodyStyle),
              for (final (name, value) in sections) ...[
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(value, style: _dialogBodyStyle),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 跳过片头片尾快捷弹窗的结果：秒数设置＋全局开关。
typedef IntroOutroQuickResult = ({
  IntroOutroSettings settings,
  bool globalEnabled,
});

/// 跳过片头片尾快捷弹窗（K1–K4）：秒数直填＋30/60/90 快捷档＋
/// 清除/取消/确定。与参考的差异如实标注在副注里：魔蚁按本剧保存
/// （参考是仅当次有效），全局开关即原「自动跳过片头片尾」。
Future<IntroOutroQuickResult?> showIntroOutroQuickDialog(
  BuildContext context, {
  required IntroOutroSettings initial,
  required bool globalEnabled,
}) {
  return showDialog<IntroOutroQuickResult>(
    context: context,
    builder: (_) => _IntroOutroQuickDialog(
      initial: initial,
      globalEnabled: globalEnabled,
    ),
  );
}

class _IntroOutroQuickDialog extends StatefulWidget {
  const _IntroOutroQuickDialog({
    required this.initial,
    required this.globalEnabled,
  });

  final IntroOutroSettings initial;
  final bool globalEnabled;

  @override
  State<_IntroOutroQuickDialog> createState() =>
      _IntroOutroQuickDialogState();
}

class _IntroOutroQuickDialogState extends State<_IntroOutroQuickDialog> {
  late final TextEditingController _introController = TextEditingController(
    text: widget.initial.introSeconds > 0
        ? '${widget.initial.introSeconds}'
        : '',
  );
  late final TextEditingController _outroController = TextEditingController(
    text: widget.initial.outroSeconds > 0
        ? '${widget.initial.outroSeconds}'
        : '',
  );
  late bool _enabled = widget.globalEnabled;

  @override
  void dispose() {
    _introController.dispose();
    _outroController.dispose();
    super.dispose();
  }

  int _parse(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim()) ?? 0;
    return value.clamp(0, maxSkipSeconds);
  }

  Widget _row({
    required String label,
    required TextEditingController controller,
    required String chipPrefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 44, child: Text(label)),
            SizedBox(
              width: 96,
              child: TextField(
                key: ValueKey('skip-input-$chipPrefix'),
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '秒数',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _parse(controller) > 0 ? '开' : '关',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final seconds in const [30, 60, 90])
              ActionChip(
                key: ValueKey('skip-chip-$chipPrefix-$seconds'),
                label: Text('$label${seconds}s'),
                onPressed: () => setState(
                  () => controller.text = '$seconds',
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('跳过片头片尾', style: _dialogTitleStyle),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '设置后将自动跳过片头片尾，按本剧保存',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                key: const ValueKey('skip-global-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('自动跳过片头片尾', style: TextStyle(fontSize: 14)),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 8),
              _row(
                label: '片头',
                controller: _introController,
                chipPrefix: 'intro',
              ),
              const SizedBox(height: 14),
              _row(
                label: '片尾',
                controller: _outroController,
                chipPrefix: 'outro',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('skip-clear'),
          onPressed: () => Navigator.pop(context, (
            settings: const IntroOutroSettings(),
            globalEnabled: _enabled,
          )),
          child: const Text('清除'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('skip-confirm'),
          onPressed: () => Navigator.pop(context, (
            settings: IntroOutroSettings(
              introSeconds: _parse(_introController),
              outroSeconds: _parse(_outroController),
            ),
            globalEnabled: _enabled,
          )),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 弹幕加载弹窗（D1–D4）。加载回调返回载入条数；文件回调返回
/// null 表示用户取消了选择（弹窗保持打开、不报错）。
Future<void> showDanmakuLoadDialog(
  BuildContext context, {
  required Future<int> Function(String url) onLoadFromUrl,
  required Future<int?> Function() onLoadFromFile,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DanmakuLoadDialog(
      onLoadFromUrl: onLoadFromUrl,
      onLoadFromFile: onLoadFromFile,
    ),
  );
}

class _DanmakuLoadDialog extends StatefulWidget {
  const _DanmakuLoadDialog({
    required this.onLoadFromUrl,
    required this.onLoadFromFile,
  });

  final Future<int> Function(String url) onLoadFromUrl;
  final Future<int?> Function() onLoadFromFile;

  @override
  State<_DanmakuLoadDialog> createState() => _DanmakuLoadDialogState();
}

class _DanmakuLoadDialogState extends State<_DanmakuLoadDialog> {
  final TextEditingController _urlController = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<int?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final count = await action();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = count == null ? null : '已加载 $count 条弹幕';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '加载失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('弹幕加载', style: _dialogTitleStyle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('输入弹幕地址或选择本地文件：', style: _dialogBodyStyle),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('danmaku-load-url'),
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: '请输入弹幕地址（XML格式）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('danmaku-load-file'),
              onPressed: _busy
                  ? null
                  : () => _run(widget.onLoadFromFile),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('选择本地XML文件'),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: _dialogBodyStyle),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('danmaku-load-submit'),
          onPressed: _busy
              ? null
              : () {
                  final url = _urlController.text.trim();
                  if (url.isEmpty) {
                    setState(() => _message = '请先输入弹幕地址');
                    return;
                  }
                  _run(() => widget.onLoadFromUrl(url));
                },
          child: const Text('从URL加载'),
        ),
      ],
    );
  }
}
