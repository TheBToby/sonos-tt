import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonos_tt/app_state.dart';
import 'package:sonos_tt/main.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider(create: (_) => AppState(), child: const SonosApp()),
    );

    // Verify that the app renders without errors.
    expect(find.byType(SonosApp), findsOneWidget);
  });
}
