import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

/// R26 #35/#13: the shared refusal channel — one controller, one overlay,
/// and a tool-switch guard every entrance writes through.
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

  test('the tool-switch guard refuses the tool and reports why; the '
      'settings in the same write still land', () {
    final notifier = PaintToolStateNotifier(BrushToolState.defaults);
    addTearDown(notifier.dispose);
    final refusals = <String>[];
    // No cascade here: `..x = (a) => b ..y = c` parses the second cascade
    // INTO the lambda body (the project's Dart gotcha).
    notifier.switchGuard = (tool) {
      return tool == CanvasTool.move ? 'Nothing to transform' : null;
    };
    notifier.onSwitchRefused = refusals.add;

    final before = notifier.value;
    notifier.value = before.copyWith(tool: CanvasTool.move, size: 42);

    expect(notifier.value.tool, before.tool, reason: 'the switch is refused');
    expect(notifier.value.size, 42, reason: 'settings are not collateral');
    expect(refusals, ['Nothing to transform']);

    // An ALLOWED tool still switches.
    notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);
    expect(notifier.value.tool, CanvasTool.eraser);
    expect(refusals, hasLength(1));
  });
}
