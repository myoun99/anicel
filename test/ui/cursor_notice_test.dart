import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

/// R26 #35/#13: the shared refusal channel — one controller, one overlay.
void main() {
  testWidgets('the overlay prints the live message and drops it when the '
      'notice expires', (tester) async {
    final controller = CursorNoticeController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CursorNoticeOverlay(
            controller: controller,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(find.text('no frame here'), findsNothing);
    controller.show('no frame here', duration: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('no frame here'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
      find.text('no frame here'),
      findsNothing,
      reason: 'the notice is transient — no dismissal needed',
    );
  });
}
