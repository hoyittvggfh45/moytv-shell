import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/content_jar_audio.dart';
import 'package:moyi/content_models.dart';
import 'package:moyi/content_registry.dart';
import 'package:moyi/jar_bridge.dart';
import 'package:moyi/zakatv_builtin.dart';

/// 读 dex 类定义表，返回全部已定义类的描述符（如
/// `Lcom/github/catvod/spider/TingShu;`）。只解析头、string_ids、
/// type_ids、class_defs 四段，不碰 code 段（与 eroshort 测试同款）。
List<String> _dexDefinedClasses(List<int> dexBytes) {
  final bytes = Uint8List.fromList(dexBytes);
  final data = ByteData.sublistView(bytes);
  int u32(int offset) => data.getUint32(offset, Endian.little);
  final stringIdsSize = u32(56);
  final stringIdsOff = u32(60);
  final typeIdsOff = u32(68);
  final classDefsSize = u32(96);
  final classDefsOff = u32(100);
  String readString(int index) {
    final off = u32(stringIdsOff + index * 4);
    var pos = off;
    while (bytes[pos] & 0x80 != 0) {
      pos++;
    }
    pos++;
    final start = pos;
    while (bytes[pos] != 0) {
      pos++;
    }
    // dex 字符串池是 MUTF-8，含孤代理对，utf8.decode 会抛；
    // 类描述符只取 ASCII 段，用 fromCharCodes 与 xhs 测试同款。
    return String.fromCharCodes(bytes.sublist(start, pos));
  }

  final strings = [for (var i = 0; i < stringIdsSize; i++) readString(i)];
  final classes = <String>[];
  for (var i = 0; i < classDefsSize; i++) {
    final classIdx = u32(classDefsOff + i * 32);
    final stringIdx = u32(typeIdsOff + classIdx * 4);
    classes.add(strings[stringIdx]);
  }
  return classes;
}

List<int> _dexBytesOf(Archive archive, String name) => List<int>.from(
  archive.files.firstWhere((f) => f.name == name).content as List<int>,
);

void main() {
  group('飞卢听书移植', () {
    test('Dart 登记：go_tingshu 在末尾，纯音频', () {
      // 2026-11-26 空壳片库定版：zakatv 登记表只剩飞卢听书 1 条
      //（其余 136 条片库 jar 站已剥离），它仍在末尾、仍是唯一纯音频条目。
      expect(zakatvBuiltinSites.length, 1);
      final site = zakatvBuiltinSites.singleWhere(
        (site) => site.key == 'go_tingshu',
      );
      expect(zakatvBuiltinSites.last.key, 'go_tingshu');
      expect(site.name, '飞卢听书');
      expect(site.className, 'com.github.catvod.spider.TingShu');
      expect(site.ext, '{}');
      expect(site.audioOnly, isTrue);
      // 全树唯一纯音频内置站：小程序区与插件站点列表都靠这个旗标跳过它。
      expect(zakatvBuiltinSites.where((s) => s.audioOnly).map((s) => s.key), [
        'go_tingshu',
      ]);
    });

    test('jar 未动：md5 与条目数都不变，TingShu 类早已在 classes11.dex', () {
      expect(zakatvJarMd5, '029005c7ce017dc0a412f2d079a29dab');
      final bytes = File('assets/jars/zakatv.jar').readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toList();
      expect(names.length, 23);
      expect(names, contains('classes11.dex'));
      expect(names, isNot(contains('classes21.dex')));
      final classes = _dexDefinedClasses(_dexBytesOf(archive, 'classes11.dex'));
      expect(classes, contains('Lcom/github/catvod/spider/TingShu;'));
      expect(classes, contains('Lcom/github/catvod/spider/SoLoader;'));
    });

    test('JSON 镜像已随空壳片库删除，api 映射改由 Dart 登记直供', () {
      // jar_site_configs.json 是片库 jar 站的配置镜像，2026-11-26
      // 随剥离删除；飞卢听书的登记只认 zakatvBuiltinSites 的 Dart 表
      //（registerBuiltinZakatv 直读该表，不经 JSON 镜像）。
      expect(File('assets/jar_site_configs.json').existsSync(), isFalse);
      expect(
        JarSiteSpec.classNameForApi('csp_TingShu'),
        'com.github.catvod.spider.TingShu',
      );
      expect(
        JarSiteSpec.siteIdFor(zakatvJarId, 'go_tingshu'),
        'jar:zakatv:go_tingshu',
      );
    });

    test('听书区：jar_tingshu 在末尾，走 jar 桥', () {
      final sources = ContentRegistry.sourcesFor(ContentSection.audio);
      expect(sources.map((s) => s.id).last, 'jar_tingshu');
      final source = sources.last;
      expect(source.name, '飞卢听书');
      expect(source.section, ContentSection.audio);
      expect(source, isA<JarAudioContentSource>());
    });

    test('spec 查找键与注册键一致：注册后 specFor 能取到', () {
      const spec = JarSiteSpec(
        siteId: 'jar:zakatv:go_tingshu',
        configId: 'zakatv',
        name: '飞卢听书',
        className: 'com.github.catvod.spider.TingShu',
        jarUrl: '',
        jarMd5: '029005c7ce017dc0a412f2d079a29dab',
        ext: '{}',
      );
      JarBridge.register(spec);
      try {
        expect(
          JarBridge.specFor(JarSiteSpec.siteIdFor(zakatvJarId, 'go_tingshu')),
          isNotNull,
        );
        expect(
          JarBridge.specFor('jar:zakatv:go_tingshu')!.className,
          'com.github.catvod.spider.TingShu',
        );
      } finally {
        JarBridge.unregister('jar:zakatv:go_tingshu');
      }
    });
  });
}
