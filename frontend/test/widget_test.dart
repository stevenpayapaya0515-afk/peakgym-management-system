import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('PeakGym app loads login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PeakGymApp());

    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('LOG IN'), findsOneWidget);
  });
}