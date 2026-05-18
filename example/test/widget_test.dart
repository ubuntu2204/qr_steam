import 'package:flutter_test/flutter_test.dart';

import 'package:qr_steam_example/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const QrSteamApp());
    // 验证应用能正常启动（根据平台渲染对应页面）
    expect(find.byType(QrSteamApp), findsOneWidget);
  });
}
