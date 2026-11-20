import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../helpers/the_apps_engine_let_go.dart';
import 'brush_canvas_test_helpers.dart';

/// 🗣️유저 2026-11-19 (cel-originals-are-held-twice-in-ram-and-on-the-gpu-Q2):
/// 「픽셀 대신 「한 일의 기록」을 들고, 잃으면 다시 그린다」 — through a real
/// pen stroke: the tiles the canvas hands over at pen-up are the engine's
/// alone, and a device that goes then takes them. Read once the app stands
/// on another engine, each is the stroke drawn again
/// (`StrokeLandsAgain`) — what the pen showed, not the cel it found.
///
/// On the app's own engine, which the test loses.
void main() {
  const canvasSize = CanvasSize(width: 48, height: 16);
  const tileSize = 128;

  /// Grey on the left, nothing on the right: paint for the pen to cross.
  BitmapSurface cel() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: tileSize,
        pixels: Uint8List.fromList([
          for (var y = 0; y < tileSize; y += 1)
            for (var x = 0; x < tileSize; x += 1)
              ...(x < 24 ? const [90, 90, 90, 200] : const [0, 0, 0, 0]),
        ]),
      ),
    },
  );

  const pen = BrushShape(
    size: 10,
    color: 0xFFFF0000,
    flow: 0.6,
    hardness: 0.5,
    correction: BrushCorrection.none,
  );

  Future<BrushStrokeCommitData> strokeAcross(
    WidgetTester tester,
    BitmapSurface cel,
  ) async {
    BrushStrokeCommitData? landed;
    final settings = BrushEditCanvasInputSettings.fromShape(pen);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: InteractiveBrushEditCanvasView(
              // Each stroke on a canvas of its own.
              key: UniqueKey(),
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

  testWidgets('a pen\'s stroke, its device gone as it landed, is drawn '
      'again on the next engine as the pen showed it', (tester) async {
    final found = cel();
    final shown = [
      for (final placed in (await strokeAcross(tester, found)).promotedTiles!)
        Uint8List.fromList(placed.tile.pixels),
    ];
    final lost = (await strokeAcross(tester, found)).promotedTiles!;
    expect(shown, isNotEmpty, reason: '⛔premise: the stroke lands');
    expect(
      shown.single,
      isNot(found.tiles.values.single.pixels),
      reason: '⛔premise: the stroke changes the tile',
    );
    expect(
      lost.single.tile.isOnlyOnEngine,
      isTrue,
      reason: '⛔premise: no copy of it is here',
    );

    theAppsEngineLostAndLetGo();

    expect(lost.single.tile.pixels, shown.single);
  });
}
