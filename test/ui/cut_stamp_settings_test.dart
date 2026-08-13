import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/straight_rgba_image.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/ui/brush/cut_piece_preview.dart';
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
    VoidCallback? onPasteAtOrigin,
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
              onCutPasteAtOrigin: onPasteAtOrigin,
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
      // TS8: ONE paste button. The pair that said Above/Below was spelling
      // a composite order, and the blend control says that now.
      'cut-paste-at-origin-button',
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
            find.byKey(const ValueKey<String>('cut-paste-at-origin-button')),
          )
          .onPressed,
      isNull,
    );

    var pasted = 0;
    await pump(
      tester,
      tool: CanvasTool.cutStamp,
      slot: slot,
      onPasteAtOrigin: () => pasted += 1,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('cut-paste-at-origin-button')),
    );
    expect(pasted, 1);
  });

  // TS4: 유저 — "커서에 달린 프리뷰, 너무 퀄리티가 심함. 해상도가 심각하게
  // 낮음. … 툴설정 프리뷰든 커서 프리뷰든 퀄리티 낮추지마. 원본그대로."
  //
  // The previews used to draw a 20-cell mosaic of alpha-weighted averages,
  // so a one-pixel detail came out as a quarter-strength 2×2 block. The
  // oracle is therefore a LONE pixel: averaging cannot reproduce it.
  group('the held piece previews at its own resolution', () {
    // 40 px so the retired mosaic's 20 cells would be 2×2 blocks — small
    // enough and the grid oversamples, which would let the old code pass.
    const side = 40;

    CutPiece pieceWithDot({
      bool flipHorizontal = false,
      bool flipVertical = false,
    }) {
      final rgba = Uint8List(side * side * 4);
      const dotX = 37;
      const dotY = 3;
      final offset = (dotY * side + dotX) * 4;
      rgba[offset] = 255;
      rgba[offset + 3] = 255;
      return CutPiece(
        image: BrushStampImage(id: 'dot', width: side, height: side, rgba: rgba),
        originLeft: 0,
        originTop: 0,
        flipHorizontal: flipHorizontal,
        flipVertical: flipVertical,
      );
    }

    /// The preview's own pixels, painted at 1:1.
    ///
    /// ⚠️`runAsync`: the image upload lands on the engine, and inside the
    /// fake-async zone its callback never fires — which is a HANG, not a
    /// failure, so this wrapper is not optional.
    Future<Uint8List> render(
      WidgetTester tester,
      CutPiece piece, {
      bool decoded = true,
    }) async {
      final bytes = await tester.runAsync(() async {
        ui.Image? image;
        if (decoded) {
          final completer = Completer<ui.Image>();
          decodeStraightRgbaImage(
            rgba: piece.image.rgba,
            width: piece.image.width,
            height: piece.image.height,
            onDecoded: completer.complete,
          );
          image = await completer.future;
        }
        final recorder = ui.PictureRecorder();
        final size = Size(side.toDouble(), side.toDouble());
        final canvas = Canvas(recorder, Offset.zero & size);
        paintCutPiece(canvas, Offset.zero & size, piece, image);
        final rendered = await recorder.endRecording().toImage(side, side);
        final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
        rendered.dispose();
        image?.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    List<int> at(Uint8List pixels, int x, int y) {
      final offset = (y * side + x) * 4;
      return pixels.sublist(offset, offset + 4);
    }

    testWidgets('a single source pixel lands as a single opaque pixel', (
      tester,
    ) async {
      final pixels = await render(tester, pieceWithDot());
      expect(at(pixels, 37, 3), [255, 0, 0, 255]);
      // Its neighbours stay empty: nothing was averaged into them, which is
      // the whole difference from the mosaic.
      expect(at(pixels, 36, 3), [0, 0, 0, 0]);
      expect(at(pixels, 37, 4), [0, 0, 0, 0]);
    });

    testWidgets('the flips are honoured without re-ordering any bytes', (
      tester,
    ) async {
      // Flipping is a canvas mirror here, not a second copy of the pixels:
      // the decoded image is the piece as cut, and it survives every knob.
      final pixels = await render(
        tester,
        pieceWithDot(flipHorizontal: true, flipVertical: true),
      );
      expect(at(pixels, side - 1 - 37, side - 1 - 3), [255, 0, 0, 255]);
      expect(at(pixels, 37, 3), [0, 0, 0, 0]);
    });

    testWidgets('nothing is drawn before the decode lands', (tester) async {
      // The app's standing answer for "no image yet" is silence, never a
      // degraded stand-in (the surface painter's fallback ladder ends the
      // same way). The window is one frame: the decode starts with the
      // piece, not with the look.
      final pixels = await render(tester, pieceWithDot(), decoded: false);
      expect(pixels.every((byte) => byte == 0), isTrue);
    });

    testWidgets('the widget hands its painter the decoded image', (
      tester,
    ) async {
      final seen = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 80,
            height: 80,
            child: CutPieceImageHost(
              piece: pieceWithDot(),
              builder: (context, image) {
                seen.add(image != null);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      expect(seen.first, isFalse, reason: 'the first frame has no image yet');
      // Let the real upload complete, then take the frame it asked for. The
      // loop is for the engine's sake, not the widget's: the upload was
      // started from inside the fake-async zone, so how many real turns its
      // callback needs is not something this test should pretend to know.
      for (var attempt = 0; attempt < 20 && seen.last == false; attempt += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(seen.last, isTrue, reason: 'and the decode arrives right after');
    });
  });
}
