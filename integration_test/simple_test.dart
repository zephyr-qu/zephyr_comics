import 'package:flutter_test/flutter_test.dart';
import 'package:zephyr_comics/app.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('launches the Zephyr Comics shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ZephyrApp());
    await tester.pumpAndSettle();
    expect(find.text('Zephyr'), findsOneWidget);
    expect(find.text('书架'), findsOneWidget);
    expect(find.text('历史'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
