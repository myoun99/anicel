import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_mixing_method.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_blur_stroke_landing.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import 'brush_canvas_test_helpers.dart';

/// 🗣️I-75 흐리기, through a real pen stroke: the canvas takes the blur up
/// at the press — the cel as it stands — and what it hands over at pen-up
/// is that cel rewritten, the same bytes its dabs re-derive.
void main() {
  const canvasSize = CanvasSize(width: 48, height: 16);
  const tileSize = 16;

  /// Black on the left, nothing on the right: an edge for the pen to rub.
  BitmapSurface edgeCel() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var tileX = 0; tileX < 3; tileX += 1)
        TileCoord(x: tileX, y: 0): BitmapTile(
          size: tileSize,
          pixels: Uint8List.fromList([
            for (var y = 0; y < tileSize; y += 1)
              for (var x = 0; x < tileSize; x += 1)
                ...(tileX * tileSize + x < 24
                    ? const [0, 0, 0, 255]
                    : const [0, 0, 0, 0]),
          ]),
        ),
    },
  );

  Future<BrushStrokeCommitData> strokeAcross(
    WidgetTester tester,
    BitmapSurface cel,
    BrushShape brush, {
    bool erase = false,
  }) async {
    BrushStrokeCommitData? landed;
    final settings = BrushEditCanvasInputSettings.fromShape(
      brush,
      erase: erase,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: InteractiveBrushEditCanvasView(
              celNow: () => cel,
              layerId: const LayerId('layer-a'),
              frameId: const FrameId('frame-a'),
              inputSettings: () => settings,
              onSourceStrokeCommitted: (data) => landed = data,
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      canvasGlobalOffset(tester, const Offset(14, 8)),
      pointer: 1,
    );
    await gesture.moveTo(canvasGlobalOffset(tester, const Offset(34, 8)));
    await gesture.up();
    await tester.pump();
    return landed!;
  }

  const blur = BrushShape(
    size: 10,
    // Red over black: a ground mixer, were one running, would lift the
    // black into the dabs.
    color: 0xFFFF0000,
    flow: 0.6,
    hardness: 0.5,
    mixesGroundColor: true,
    mixingMethod: BrushMixingMethod.blur,
    correction: BrushCorrection.none,
  );

  testWidgets('the pen lands the cel rewritten, as its dabs re-derive it', (
    tester,
  ) async {
    final cel = edgeCel();
    final landed = await strokeAcross(tester, cel, blur);

    expect(landed.sourceDabs, isNotEmpty);
    expect(landed.sourceDabs.every((dab) => dab.blurs), isTrue);
    expect(
      landed.sourceDabs.map((dab) => dab.color).toSet(),
      {0xFFFF0000},
      reason: 'a blur picks no colour up — no ground mixer runs under it',
    );
    expect(landed.promotedBase, same(cel));
    final shown = landed.promotedTiles!;
    expect(shown, isNotEmpty, reason: 'premise: the edge was smeared');

    final rederived = blurStrokeLandedOn(
      cel,
      landed.sourceDabs,
      opacity: landed.strokeOpacity,
    );
    expect(
      [for (final placed in shown) placed.coord],
      [for (final placed in rederived) placed.coord],
    );
    for (var i = 0; i < shown.length; i += 1) {
      expect(
        shown[i].tile.pixels,
        rederived[i].tile.pixels,
        reason: '${shown[i].coord}',
      );
    }
  });

  testWidgets('pressed as the eraser, a blur brush erases', (tester) async {
    final cel = edgeCel();
    final landed = await strokeAcross(tester, cel, blur, erase: true);

    expect(landed.sourceDabs.any((dab) => dab.blurs), isFalse);
    expect(landed.sourceDabs.every((dab) => dab.erase), isTrue);
  });
}
