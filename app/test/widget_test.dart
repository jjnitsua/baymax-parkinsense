import 'package:flutter_test/flutter_test.dart';

import 'package:baymax_mobile_app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(ParkinSenseApp());
    expect(find.text('ParkinSense'), findsOneWidget);
  });
}
