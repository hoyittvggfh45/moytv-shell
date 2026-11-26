import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:moyi/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deleted YouTube site is gone from the builtin list', () {
    expect(
      zakatvBuiltinSites.any((site) => site.key == 'ZakaYouTube'),
      isFalse,
    );
  });

  test('go_tingshu site exists in the builtin list as an audio-only Listen-Read site', () {
    final site =
        zakatvBuiltinSites.singleWhere((site) => site.key == 'go_tingshu');
    expect(site.name, '飞卢听书');
    expect(site.className, 'com.github.catvod.spider.TingShu');
    expect(site.audioOnly, isTrue);
  });

  test('merged zakatv jar md5 matches the asset on disk', () {
    final bytes = File('assets/jars/zakatv.jar').readAsBytesSync();
    expect(md5.convert(bytes).toString(), zakatvJarMd5);
  });

  test('standalone youtube jar 已随空壳片库剥离：文件不在', () {
    // 2026-11-26 定版：youtube.jar 与 YouTube 内置站一并剥离；
    // youtubeJarMd5 常量仅作历史记录保留。
    expect(File('assets/jars/youtube.jar').existsSync(), isFalse);
    expect(youtubeJarMd5, 'd294ce251d3b2aa8528efff12cc4bf19');
  });
}
