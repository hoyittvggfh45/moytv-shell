// 问题 4 回归（2026-11-27 phonefix2）：用户实报「插件怎么
// 才 38 个」。远端订阅索引（hoyittvggfh45/moytv plugins 分支
// index.json）本机实测 217 条、id 全唯一（另有 4 对同名不同
// id，属正当分包）。本测试钉住 App 侧全链不丢条：
// 1. parseSubscriptionJson 对 217 条规模的索引一条不落
//    （含同名条目——按 id 不按 name 收，一条不折叠）；
// 2. 订阅卡渲染时有显式总数「共 N 个插件」，与解析条数一致。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/idj_plugin_store.dart';
import 'package:moyi/miniapp/idj_plugin_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _entry(int i, {String? name}) => {
  'id': 'com.idj.ext.site$i',
  'name': name ?? '站点$i',
  'version': '1.0.0',
  'type': i % 18 == 0 ? 'shortdrama' : 'video',
  'adult': i % 21 != 0,
  'description': '第 $i 个插件',
  'manifest': 'site$i/site$i.idjplugin',
};

void main() {
  test('217 条索引解析一条不落（同名不折叠）', () {
    final json = <String, dynamic>{
      'name': '远程仓库',
      'plugins': [
        for (var i = 0; i < 217; i++)
          // 4 对同名（与活索引同形态）：按 id 收，不许按名折叠。
          _entry(i, name: i < 8 ? '同名站${i % 4}' : null),
      ],
      'cms': const [],
    };
    final sub = IdjPluginStore.parseSubscriptionJson(
      json,
      Uri.parse(idjBuiltInSubscriptionUrl),
    );
    expect(sub.plugins.length, 217);
    expect(sub.plugins.map((p) => p.id).toSet().length, 217);
    expect(
      sub.plugins.every((p) => p.manifestUrl.endsWith('.idjplugin')),
      isTrue,
    );
  });

  testWidgets('订阅卡显式总数与条数一致', (tester) async {
    final store = IdjPluginStore();
    final sub = IdjSubscription(
      url: idjBuiltInSubscriptionUrl,
      name: '远程仓库',
      plugins: [
        for (var i = 0; i < 217; i++)
          IdjSubscriptionPlugin(
            id: 'com.idj.ext.site$i',
            name: '站点$i',
            version: '1.0.0',
            type: 'video',
            adult: false,
            description: '',
            manifestUrl: 'https://example.com/site$i/site$i.idjplugin',
          ),
      ],
      cms: const [],
    );
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdjPluginTab(store: store, initialSubscriptions: [sub]),
        ),
      ),
    );
    // 已安装区刷新走真异步 IO，pumpAndSettle 等不到：有界泵。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('共 217 个插件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
