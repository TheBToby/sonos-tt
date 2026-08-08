import 'package:flutter_test/flutter_test.dart';
import 'package:sonos_tt/main.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SonosApp());

    // Verify that the app renders without errors.
    expect(find.byType(SonosApp), findsOneWidget);
  });
}
