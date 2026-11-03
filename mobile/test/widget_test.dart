import 'package:flutter_test/flutter_test.dart';
import 'package:saibaan_connect/app.dart';

void main() {
  testWidgets('app renders', (tester) async {
    await tester.pumpWidget(const SaibaanConnectApp());
    expect(find.text('SAIBAAN Connect — implementation scaffold'), findsOneWidget);
  });
}
