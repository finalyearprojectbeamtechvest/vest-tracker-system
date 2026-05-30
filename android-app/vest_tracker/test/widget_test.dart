

import 'package:flutter_test/flutter_test.dart';

import 'package:vest_tracker/app.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const VestTrackerApp());
    
    expect(find.byType(VestTrackerApp), findsOneWidget);
  });
}
