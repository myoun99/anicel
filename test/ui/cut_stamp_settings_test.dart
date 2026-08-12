import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';

CutPiece _piece({int scalePercent = 100, bool flipHorizontal = false}) {
  return CutPiece(
    image: BrushStampImage(
      id: 'p',
      width: 40,
      height: 24,
      rgba: Uint8List(40 * 24 * 4),
    ),
    originLeft: 5,
    originTop: 6,
    scalePercent: scalePercent,
    flipHorizontal: flipHorizontal,
  );
}

void main() {
  const stampKey = ValueKey<String>('tool-settings-cut-stamp');
  const grabKey = ValueKey<String>('tool-settings-cut-grab');

  Future<void> pump(
    WidgetTester tester, {
    required CanvasTool tool,
    CutPieceSlot? slot,
    VoidCallback? onPasteAbove,
    VoidCallback? onPasteBelow,
    VoidCallback? onRegisterAsTip,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 720,
            child: ToolSettingsPanel(
              state: BrushToolState.defaults.copyWith(tool: tool),
              onChanged: (_) {},
              fillOptions: const FloodFillOptions(),
              onFillOptionsChanged: (_) {},
              selectionMaskOptions: SelectionMaskOptions.none,
              eyedropperSource: CanvasColorSampleSource.display,
              cutPieceSlot: slot,
              onCutPasteAbove: onPasteAbove,
              onCutPasteBelow: onPasteBelow,
              onRegisterCutPieceAsTip: onRegisterAsTip,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the grab tiles say what the tool does and offer no knobs', (
    tester,
  ) async {
    // The grab makes no selection and its mask is hard by law, so there is
    // genuinely nothing to set — the empty panel is the design.
    await pump(tester, tool: CanvasTool.cut, slot: CutPieceSlot());
    expect(find.byKey(grabKey), findsOneWidget);
    expect(find.byKey(stampKey), findsNothing);
  });

  testWidgets('an empty slot tells you to cut something first', (tester) async {
    await pump(tester, tool: CanvasTool.cutStamp, slot: CutPieceSlot());
    expect(find.byKey(stampKey), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('cut-scale-slider')), findsNothing);
  });

  testWidgets('a held piece shows its size and the full knob set', (
    tester,
  ) async {
    final slot = CutPieceSlot()..hold(_piece());
    await pump(tester, tool: CanvasTool.cutStamp, slot: slot);
    expect(find.text('Holding 40×24 px'), findsOneWidget);
    for (final key in const [
      'cut-paste-above-button',
      'cut-paste-below-button',
      'cut-flip-horizontal-switch',
      'cut-flip-vertical-switch',
      'cut-scale-slider',
      'cut-reset-button',
      'cut-register-tip-button',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('there is no spacing knob — that belongs to a registered tip', (
    tester,
  ) async {
    final slot = CutPieceSlot()..hold(_piece());
    await pump(tester, tool: CanvasTool.cutStamp, slot: slot);
    expect(find.textContaining('Spacing'), findsNothing);
    expect(find.textContaining('Jitter'), findsNothing);
  });

  testWidgets('flipping poses the held piece without touching its bytes', (
    tester,
  ) async {
    final slot = CutPieceSlot()..hold(_piece());
    final bytes = slot.piece!.image;
    await pump(tester, tool: CanvasTool.cutStamp, slot: slot);
    await tester.tap(
      find.byKey(const ValueKey<String>('cut-flip-horizontal-switch')),
    );
    await tester.pump();
    expect(slot.piece!.flipHorizontal, isTrue);
    // The flag moved; the pixels did not. Baking would destroy the
    // original and break undo of a stamp.
    expect(identical(slot.piece!.image, bytes), isTrue);
  });

  testWidgets('Reset is dead until the piece is actually posed', (
    tester,
  ) async {
    final slot = CutPieceSlot()..hold(_piece());
    await pump(tester, tool: CanvasTool.cutStamp, slot: slot);
    final reset = find.byKey(const ValueKey<String>('cut-reset-button'));
    expect(tester.widget<OutlinedButton>(reset).onPressed, isNull);

    slot.updatePose(scalePercent: 250);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(reset).onPressed, isNotNull);
  });

  testWidgets('Reset clears the size AND both flips in one press', (
    tester,
  ) async {
    // This is why the panel has no separate "original size" button.
    final slot = CutPieceSlot()..hold(_piece());
    await pump(tester, tool: CanvasTool.cutStamp, slot: slot);
    slot.updatePose(
      scalePercent: 300,
      flipHorizontal: true,
      flipVertical: true,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('cut-reset-button')));
    await tester.pump();
    expect(slot.piece!.isPosed, isFalse);
  });

  testWidgets('the size readout follows the slider', (tester) async {
    final slot = CutPieceSlot()..hold(_piece(scalePercent: 175));
    await pump(tester, tool: CanvasTool.cutStamp, slot: slot);
    expect(find.text('Size 175%'), findsOneWidget);
  });

  testWidgets('paste and register are disabled without a host handler', (
    tester,
  ) async {
    // A host with no cel behind it shows the buttons dead rather than
    // hiding them, so the panel does not change shape under the hand.
    final slot = CutPieceSlot()..hold(_piece());
    await pump(tester, tool: CanvasTool.cutStamp, slot: slot);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey<String>('cut-paste-above-button')),
          )
          .onPressed,
      isNull,
    );

    var pasted = 0;
    await pump(
      tester,
      tool: CanvasTool.cutStamp,
      slot: slot,
      onPasteAbove: () => pasted += 1,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('cut-paste-above-button')),
    );
    expect(pasted, 1);
  });
}
