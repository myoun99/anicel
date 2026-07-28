import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';

/// R26 #14: the Move/Transform settings' x/y/angle/scale are the shared
/// DRAG VALUE readouts (the canvas bar's zoom/angle vocabulary) — a
/// label drag writes through the selection channel, and the fields no
/// longer demand a selection first (R26 #13: none = whole picture).
void main() {
  Future<CanvasSelectionCommands> pumpMoveSettings(
    WidgetTester tester, {
    required List<SelectionTransformValues> applied,
  }) async {
    final commands = CanvasSelectionCommands();
    commands.bind(
      hasSelection: () => false,
      nudge: (_, _) {},
      deselect: () {},
      transformValues: () => null,
      setTransformValues:
          ({
            required double tx,
            required double ty,
            required double rotationDegrees,
            required double scale,
          }) {
            applied.add((
              tx: tx,
              ty: ty,
              rotationDegrees: rotationDegrees,
              scale: scale,
            ));
          },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 320,
            height: 480,
            child: ToolSettingsPanel(
              state: BrushToolState.defaults.copyWith(tool: CanvasTool.move),
              onChanged: (_) {},
              fillOptions: const FloodFillOptions(),
              onFillOptionsChanged: (_) {},
              selectionCommands: commands,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return commands;
  }

  testWidgets('an X-label drag accumulates units and writes them through '
      'the channel — no selection required', (tester) async {
    final applied = <SelectionTransformValues>[];
    await pumpMoveSettings(tester, applied: applied);

    // A comfortably slop-clearing drag; the exact delivered delta is
    // slop-dependent, the CONTRACT is that units accumulate into tx.
    await tester.drag(
      find.byKey(const ValueKey<String>('move-x-field')),
      const Offset(80, 0),
      kind: PointerDeviceKind.mouse,
    );
    // Clear the double-tap recognizer's pending window.
    await tester.pump(const Duration(milliseconds: 500));

    expect(applied, isNotEmpty, reason: 'the drag writes live');
    expect(applied.last.tx, greaterThan(20));
    expect(applied.last.ty, 0);
    expect(applied.last.scale, 1);
  });

  testWidgets('a scale-label drag clamps at the floor instead of going '
      'non-positive', (tester) async {
    final applied = <SelectionTransformValues>[];
    await pumpMoveSettings(tester, applied: applied);

    await tester.drag(
      find.byKey(const ValueKey<String>('move-scale-field')),
      const Offset(-300, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(applied, isNotEmpty);
    expect(applied.last.scale, closeTo(0.01, 1e-9));
  });

  testWidgets('the Mesh Warp entrance stays enabled without a selection '
      '(the whole picture is the target)', (tester) async {
    final applied = <SelectionTransformValues>[];
    await pumpMoveSettings(tester, applied: applied);

    final button = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Mesh Warp'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNotNull);
  });
}
