import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saibaan_connect/app.dart';
import 'package:saibaan_connect/shared/widgets/common.dart';

void main() {
  testWidgets('app shell renders a provided home', (tester) async {
    await tester.pumpWidget(const SaibaanConnectApp(home: Scaffold(body: Text('home'))));
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('status and flag chips render readable labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          StatusChip.status('missing_checkout'),
          const FlagChips(['outside_geofence', 'late_sync']),
        ]),
      ),
    ));
    expect(find.text('missing checkout'), findsOneWidget);
    expect(find.text('Outside site'), findsOneWidget);
    expect(find.text('Synced late'), findsOneWidget);
  });
}
