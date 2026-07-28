import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/input/pencil_interaction_service.dart';
import 'package:anicel/src/ui/home_page.dart';

/// PEN-5: the shell maps Pencil double-taps onto the tool notifier —
/// brush↔eraser for the switch actions, no-ops otherwise.
void main() {
  tearDown(PencilInteractionService.instance.debugReset);

  Future<void> sendPencilTap(String action) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          PencilInteractionService.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('pencilTap', {'action': action}),
          ),
          (_) {},
        );
  }

  bool toolSelected(WidgetTester tester, String keyValue) {
    // ToolsPanel buttons are keyed IconButtons carrying isSelected.
    return tester
        .widget<IconButton>(find.byKey(ValueKey<String>(keyValue)))
        .isSelected!;
  }

  testWidgets('a Pencil double-tap toggles brush↔eraser; ignore does not', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    PencilInteractionService.instance.bind(force: true);

    expect(toolSelected(tester, 'tool-brush-button'), isTrue);

    await sendPencilTap('switchEraser');
    await tester.pumpAndSettle();
    expect(toolSelected(tester, 'tool-eraser-button'), isTrue);

    await sendPencilTap('switchEraser');
    await tester.pumpAndSettle();
    expect(toolSelected(tester, 'tool-brush-button'), isTrue);

    await sendPencilTap('ignore');
    await tester.pumpAndSettle();
    expect(toolSelected(tester, 'tool-brush-button'), isTrue);
  });
}
