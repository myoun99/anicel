import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';

/// 🚨★★★THE FLUSH MAKES THE PICTURE (유저 절대규칙 2026-09-17: 「보이는
/// 중이랑 결과랑 절대로 다르면 안 되」). The overlay's picture of a
/// coordinate and the stroke revision it shows are made inside the very
/// call that pre-blended it, on every engine — so the pen-up handoff,
/// which runs in the same handler as the final flush, finds an image at
/// every promoted tile's revision, and the picture holds the pre-blended
/// result bytes exactly.
void main() {
  const tileSize = 8;
  const canvasSize = CanvasSize(width: 32, height: 32);

  List<BrushDab> strokeDabs() {
    var sequence = 0;
    return [
      for (var x = 2; x < 16; x += 4)
        for (var y = 0; y < 16; y += 1)
          BrushDab(
            center: CanvasPoint(x: x + 0.5, y: y + 0.5),
            color: 0xFF000000,
            size: 1,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: sequence++,
          ),
    ];
  }

  /// The stroke, pre-blended into [model] the way the interactive view
  /// does it; the rasterizer is handed back for the promotion.
  BrushLiveStrokeRasterizer stroke(ActiveStrokeOverlayModel model) {
    final rasterizer = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    final dabs = strokeDabs();
    final region = rasterizer.blendFrom(dabs, from: 0)!;
    model.dabs.addAll(dabs);
    model.updateRegion(source: rasterizer, region: region);
    return rasterizer;
  }

  test('the picture and its revision are there before updateRegion returns, '
      'and pen-up takes every one', () {
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(model.dispose);

    final rasterizer = stroke(model);

    final pictured = model.tileImages.length;
    expect(pictured, greaterThan(0), reason: 'the flush pictured the tiles');
    final promoted = rasterizer.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    expect(promoted, isNotEmpty);
    for (final entry in promoted) {
      expect(
        model.takeTileImageAt(entry.coord, revision: entry.revision),
        isNotNull,
        reason: '${entry.coord}: the handoff must find the image at the '
            'promoted tile\'s own revision — the miss this closes',
      );
    }
    expect(
      model.tileImages.length,
      pictured - promoted.length,
      reason: 'every promoted tile took its image; what stays is a tile '
          'the stroke touched without changing (its picture equals the '
          'base, and it is not promoted)',
    );
  });

  test('the picture holds the pre-blended result bytes exactly', () async {
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(model.dispose);
    final rasterizer = stroke(model);

    final coord = TileCoord(x: 0, y: 0);
    final image = model.tileImages[coord];
    expect(image, isNotNull, reason: 'the stroke touches tile 0,0');
    final blended = rasterizer.preBlendedOverlayTile(
      tileX: coord.x,
      tileY: coord.y,
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    )!;
    final expected = blended.readPremultiplied(Uint8List.fromList);
    blended.free();
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    // ⛔Mutation: picture the straight bytes as if premultiplied, or a
    // stale tile → the readback is not the result.
    expect(data!.buffer.asUint8List(), expected);
  });
}
