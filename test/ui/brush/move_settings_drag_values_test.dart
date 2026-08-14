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
    bool canEdit = true,
    TransformMode mode = TransformMode.normal,
  }) async {
    // The panel now takes the whole knob set as one object; this suite
    // only cares about the AA half, so it unwraps that one field back out.
    final resampleHandler = onResampleModeChanged;
    final commands = CanvasSelectionCommands();
    commands.bind(
      Object(),
      hasSelection: () => false,
      canEditTransform: () => canEdit,
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
                mode: mode,
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

  testWidgets('the AA switch reaches the resampler, and reads back from it', (
    tester,
  ) async {
    // P3e, relabelled. It used to read "Preserve original colours" over a
    // paragraph about in-between shades; 유저 08-13 asked for the two
    // letters and the polarity that goes with them, so ON is now the
    // smoothing default and OFF is the two-value copy. The wiring is what
    // it always was: the state has to come from the HOST, not from a local
    // bool that would drift away from what a commit runs through.
    final applied = <SelectionTransformValues>[];
    final chosen = <ResampleMode>[];
    await pumpMoveSettings(
      tester,
      applied: applied,
      onResampleModeChanged: chosen.add,
    );

    final switchKey = find.byKey(
      const ValueKey<String>('move-antialias-switch'),
    );
    expect(switchKey, findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(switchKey).value,
      isTrue,
      reason: 'Blend is the default, so AA starts ON',
    );

    await tester.tap(switchKey);
    await tester.pump();
    expect(chosen, <ResampleMode>[ResampleMode.pick]);

    // Now with the host holding Pick: AA must read off, and turning it on
    // must ask for Blend.
    //
    // The empty pump matters — it tears the panel's State down, so the
    // value the switch reads back can only have come from the host.
    // Without it, pumping the identical tree reuses `_MoveSettingsState`,
    // and a widget that kept the value in a local bool set by the tap
    // above would read the same and this half of the test would pass for
    // the implementation it exists to rule out.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMoveSettings(
      tester,
      applied: applied,
      resampleMode: ResampleMode.pick,
      onResampleModeChanged: chosen.add,
    );
    expect(tester.widget<SwitchListTile>(switchKey).value, isFalse);
    await tester.tap(switchKey);
    await tester.pump();
    expect(chosen.last, ResampleMode.blend);
  });

  testWidgets('with nothing to transform every control goes flat — the '
      'refusal is the panel, not a notice', (tester) async {
    final applied = <SelectionTransformValues>[];
    await pumpMoveSettings(
      tester,
      applied: applied,
      onResampleModeChanged: (_) {},
      canEdit: false,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey<String>('move-antialias-switch')),
          )
          .onChanged,
      isNull,
    );
    for (final key in const [
      'move-flip-horizontal-button',
      'move-flip-vertical-button',
      'move-reset-button',
    ]) {
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(ValueKey<String>(key)))
            .onPressed,
        isNull,
        reason: '$key must not be pressable with nothing to transform',
      );
    }
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('move-apply-button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('the four buttons come in the order the user asked for, and '
      'the mesh grid shows only in 메쉬', (tester) async {
    final applied = <SelectionTransformValues>[];
    await pumpMoveSettings(
      tester,
      applied: applied,
      onResampleModeChanged: (_) {},
    );
    // 좌우반전 · 상하반전 · 리셋 · 적용.
    final buttons = <Offset>[
      for (final key in const [
        'move-flip-horizontal-button',
        'move-flip-vertical-button',
        'move-reset-button',
        'move-apply-button',
      ])
        tester.getTopLeft(find.byKey(ValueKey<String>(key))),
    ];
    for (var i = 1; i < buttons.length; i += 1) {
      expect(
        buttons[i].dy > buttons[i - 1].dy ||
            (buttons[i].dy == buttons[i - 1].dy &&
                buttons[i].dx > buttons[i - 1].dx),
        isTrue,
        reason: 'button $i sits after button ${i - 1}',
      );
    }
    expect(
      find.byKey(const ValueKey<String>('move-mesh-columns-field')),
      findsNothing,
      reason: 'a grid size means nothing outside 메쉬',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpMoveSettings(
      tester,
      applied: applied,
      onResampleModeChanged: (_) {},
      mode: TransformMode.mesh,
    );
    expect(
      find.byKey(const ValueKey<String>('move-mesh-columns-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('move-mesh-rows-field')),
      findsOneWidget,
    );
  });
}
