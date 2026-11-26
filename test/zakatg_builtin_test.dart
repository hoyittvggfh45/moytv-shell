import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:moyi/zakatv_builtin.dart';
import 'package:flutter_test/flutter_test.dart';

/// TG 频道 jar 内置（100 频道）注册守卫。
///
/// 2026-11-26 空壳片库定版：TG 三站（ZakaTg/ZakaTgMovie/tg片库）
/// 的 Dart 登记与 JSON 镜像已全部剥离，本文件的登记类断言已改为
/// 剥离守卫；jar 本体因飞卢听书保留未动，jar 指纹/类表断言不变；
/// 未成年指向词的注册面扫描保留（现注册面只剩 Dart 表与 Go 核表）。
///
/// 排除口径：被排除的 2 个频道绝不写进树。本测试不写出那 2 个用户名，
/// 改用两重占位比对守卫——① ext 频道数精确等于 100；② 频道名/用户名
/// 与注册面文件全文均不得命中未成年指向词表（被排除频道的名字正在
/// 词表命中范围内）。词表与 m3u 打包安全扫描同一张。
const _flaggedTerms = <String>[
  '萝莉',
  '蘿莉',
  '幼女',
  '幼齿',
  '幼齒',
  '未成年',
  '小学生',
  '初中生',
  '儿童',
  '女童',
  '男童',
  '小女孩',
  '小男孩',
  '未满18',
  '未满十八',
  '10岁',
  '11岁',
  '12岁',
  '13岁',
  '14岁',
  '15岁',
  '16岁',
  '17岁',
];

bool _hasFlaggedTerm(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('loli')) return true;
  for (final term in _flaggedTerms) {
    if (text.contains(term)) return true;
  }
  return false;
}

/// 最小 dex 类定义解析：只读 header + string_ids/type_ids/class_defs，
/// 返回本 dex 定义的类描述符集合（与 dexdump 的 defined-classes 等价）。
Set<String> _dexDefinedClasses(List<int> dex) {
  int u32(int off) =>
      dex[off] |
      (dex[off + 1] << 8) |
      (dex[off + 2] << 16) |
      (dex[off + 3] << 24);
  int uleb(int off, List<int> next) {
    var result = 0;
    var shift = 0;
    var cursor = off;
    while (true) {
      final byte = dex[cursor++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    next[0] = cursor;
    return result;
  }

  // header: string_ids_size@56, string_ids_off@60, type_ids_size@64,
  // type_ids_off@68, class_defs_size@96, class_defs_off@100。
  final stringIdsOff = u32(60);
  final typeIdsOff = u32(68);
  final classDefsSize = u32(96);
  final classDefsOff = u32(100);
  final defined = <String>{};
  for (var i = 0; i < classDefsSize; i++) {
    final classIdx = u32(classDefsOff + i * 32);
    final stringIdx = u32(typeIdsOff + classIdx * 4);
    final dataOff = u32(stringIdsOff + stringIdx * 4);
    final next = <int>[0];
    uleb(dataOff, next);
    var end = next[0];
    while (dex[end] != 0) {
      end++;
    }
    defined.add(utf8.decode(dex.sublist(next[0], end)));
  }
  return defined;
}

void main() {
  test('ZakaTg 已随空壳片库剥离：Dart 登记里没有它', () {
    // 2026-11-26 定版：片库 jar 站登记全部剥离（含全部 TG 频道站，
    // 与「带 TG 的站点不转插件」口径一致），表里只剩飞卢听书；
    // jar 本体因飞卢听书保留未动，下面 jar 内容类断言不变。
    expect(zakatvBuiltinSites.any((s) => s.key == 'ZakaTg'), isFalse);
    expect(zakatvBuiltinSites.single.key, 'go_tingshu');
  });

  test('ZakaTg ext 不带 channelsUrl（登记已剥离，本项改守不在表）', () {
    expect(zakatvBuiltinSites.any((s) => s.key == 'ZakaTg'), isFalse);
  });

  test('JSON 配置与 Dart 注册一致（镜像已随剥离删除）', () {
    expect(File('assets/jar_site_configs.json').existsSync(), isFalse);
  });

  test('注册面文件全文无未成年指向词（防排除频道回潮）', () {
    // jar_site_configs.json 已随 2026-11-26 空壳片库删除，不再是注册面。
    const surfaces = <String>[
      'lib/zakatv_builtin.dart',
      'native/core/seku/sites_jar_tg.go',
    ];
    for (final path in surfaces) {
      final text = File(path).readAsStringSync();
      expect(
        _hasFlaggedTerm(text),
        isFalse,
        reason: '$path 命中未成年指向词表',
      );
    }
  });

  test('ZakaTgMovie 已随空壳片库剥离：Dart 登记里没有它', () {
    expect(zakatvBuiltinSites.any((s) => s.key == 'ZakaTgMovie'), isFalse);
  });

  test('tg片库已随空壳片库剥离：Dart 登记里没有它', () {
    expect(zakatvBuiltinSites.any((s) => s.key == 'ZakaTgPianku'), isFalse);
  });

  test('tg片库 JSON 配置已随 jar_site_configs.json 删除', () {
    expect(File('assets/jar_site_configs.json').existsSync(), isFalse);
  });

  test('合并后 jar 指纹与盘上文件一致', () {
    final bytes = File('assets/jars/zakatv.jar').readAsBytesSync();
    expect(md5.convert(bytes).toString(), zakatvJarMd5);
  });

  test('合并后 jar 内含新 dex 且定义 ZakaTgAllAmns', () {
    final bytes = File('assets/jars/zakatv.jar').readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = [for (final f in archive.files) f.name];
    expect(names, contains('classes.dex'));
    expect(names, contains('classes16.dex'));
    final dex = archive.files.singleWhere((f) => f.name == 'classes16.dex');
    final defined = _dexDefinedClasses(dex.content as List<int>);
    expect(
      defined,
      contains('Lcom/github/catvod/spider/ZakaTgAllAmns;'),
    );
    expect(defined, contains('Lcom/github/catvod/spider/ZakaTgAmns;'));
    // 新 dex 不得重复定义 Spider 基类（已在 classes.dex 内定义）。
    expect(
      defined,
      isNot(contains('Lcom/github/catvod/crawler/Spider;')),
    );
  });
}
