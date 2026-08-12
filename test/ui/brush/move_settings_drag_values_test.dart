import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';

/// R26 #14: the Move/Transform settings' x/y/angle/scale are the shared
/// DRAG VALUE readouts (the canvas bar's zoom/angle vocabulary) — a
/// label drag writes through the selection channel, and the fields no
/// longer demand a selection first (R26 #13: none = whole picture).
void main() {
  Future<CanvasSelectionCommands> pumpMoveSettings(
    WidgetTester tester, {
    required List<SelectionTransformValues> applied,
    ResampleMode resampleMode = ResampleMode.blend,
    ValueChanged<ResampleMode>? onResampleModeChanged,
  }) async {
    // The panel now takes the whole knob set as one object; this suite
    // only cares about the AA half, so it unwraps that one field back out.
    final resampleHandler = onResampleModeChanged;
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
              transformOptions: TransformToolOptions(
                resampleMode: resampleMode,
              ),
              onTransformOptionsChanged: resampleHandler == null
                  ? null
                  : (options) => resampleHandler(options.resampleMode),
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

  testWidgets('the preserve-colours switch reaches the resampler, and '
      'reads back from it', (tester) async {
    // P3e. The control was wired and tested for three rounds while the
    // switch itself stayed unbuilt, because Pick erased line art under an
    // ordinary rotate-and-shrink. It is built now, so the tap that turns
    // it on has to actually land on the kernel selector — and the state
    // has to come from the host, not from a local bool that would drift
    // away from what a commit runs through.
    final applied = <SelectionTransformValues>[];
    final chosen = <ResampleMode>[];
    await pumpMoveSettings(
      tester,
      applied: applied,
      onResampleModeChanged: chosen.add,
    );

    final switchKey = find.byKey(
      const ValueKey<String>('move-preserve-colours-switch'),
    );
    expect(switchKey, findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(switchKey).value,
      isFalse,
      reason: 'Blend is the default, so the switch starts off',
    );

    await tester.tap(switchKey);
    await tester.pump();
    expect(chosen, <ResampleMode>[ResampleMode.pick]);

    // Now with the host holding Pick: the switch must read on, and turning
    // it off must ask for Blend.
    //
    // The empty pump matters — it tears the panel's State down, so the ON
    // the switch reads back can only have come from the host. Without it,
    // pumping the identical tree reuses `_MoveSettingsState`, and a widget
    // that kept the value in a local bool set by the tap above would read
    // ON too and this half of the test would pass for the implementation
    // it exists to rule out.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMoveSettings(
      tester,
      applied: applied,
      resampleMode: ResampleMode.pick,
      onResampleModeChanged: chosen.add,
    );
    expect(tester.widget<SwitchListTile>(switchKey).value, isTrue);
    await tester.tap(switchKey);
    await tester.pump();
    expect(chosen.last, ResampleMode.blend);
  });

  testWidgets('a host that does not own the setting shows the switch '
      'disabled rather than lying about it', (tester) async {
    final applied = <SelectionTransformValues>[];
    await pumpMoveSettings(tester, applied: applied);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey<String>('move-preserve-colours-switch')),
          )
          .onChanged,
      isNull,
    );
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
