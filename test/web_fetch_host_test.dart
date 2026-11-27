import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moyi/web_fetch_host.dart';
import 'package:moyi/web_fetch_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  testWidgets('WebFetchHost 懒挂载：空闲时无 WebView 槽位，注册/注销 runner', (
    tester,
  ) async {
    final service = WebFetchService(
      ticketPad: (_) async => null,
      ticketSink: (_, _, _) async {},
    );
    expect(service.hasRunner, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: WebFetchHost(
          service: service,
          child: const Scaffold(body: Text('正文')),
        ),
      ),
    );
    expect(find.text('正文'), findsOneWidget);
    // 空闲：槽位为空，没有 WebView 控件进树（零常驻）。
    expect(find.byType(WebViewWidget), findsNothing);
    // host 在树时服务有真执行体。
    expect(service.hasRunner, isTrue);
    // 无 runner 时期许的失败码路径：卸载后服务回 host_unavailable。
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(service.hasRunner, isFalse);
    final r = await service.fetchHtml(
      const WebFetchRequest(url: 'https://example.com/'),
    );
    expect(r.ok, isFalse);
    expect(r.error, 'host_unavailable');
  });

  test('webFetchResultText 清洗与海阔口径一致', () {
    expect(webFetchResultText(null), '');
    expect(webFetchResultText('null'), '');
    expect(webFetchResultText('undefined'), '');
    expect(webFetchResultText('"abc"'), 'abc');
    expect(webFetchResultText(' plain '), 'plain');
    expect(webFetchResultText('"<html>\\"x\\"</html>"'), '<html>"x"</html>');
  });
}
