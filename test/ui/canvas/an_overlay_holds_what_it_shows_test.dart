import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a live stroke's overlay holds of what it shows — one record a
/// coordinate, its picture, the tile it is of and the revision it shows:
/// pen-up takes a picture only at the revision it shows, a picture a
/// coordinate shows no more is let go, and a stroke is in hand for as long
/// as anything is shown.
void main() {
  const tileSize = 8;
  const canvas = CanvasSize(width: 32, height: 32);
  final coord = TileCoord(x: 0, y: 0);

  BrushDab dabAt(double x, int sequence) => BrushDab(
    center: CanvasPoint(x: x, y: 3.5),
    color: 0xFF102030,
    size: 2,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: sequence,
  );

  final base = BitmapSurface(canvasSize: canvas, tileSize: tileSize);

  ({ActiveStrokeOverlayModel overlay, BrushLiveStrokeRasterizer rasterizer})
  strokeStarted() {
    final overlay = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base;
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvas.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    return (overlay: overlay, rasterizer: rasterizer);
  }

  /// [dabs] flushed into [overlay] as the interactive view flushes them.
  void flush(
    ActiveStrokeOverlayModel overlay,
    BrushLiveStrokeRasterizer rasterizer,
    List<BrushDab> dabs,
  ) {
    final from = overlay.dabs.length;
    overlay.dabs.addAll(dabs);
    final region = rasterizer.blendFrom(overlay.dabs, from: from)!;
    overlay.updateRegion(source: rasterizer, region: region);
  }

  test('pen-up takes a picture only at the revision it shows', () {
    final (:overlay, :rasterizer) = strokeStarted();
    flush(overlay, rasterizer, [dabAt(2.5, 0)]);
    final picture = overlay.tileImages[coord]!;
    final promoted = rasterizer
        .promoteStrokeTiles(
          base: base,
          mode: BrushBlendMode.color,
          erase: false,
        )
        .single;

    expect(
      overlay.takeTileImageAt(coord, revision: promoted.revision + 1),
      isNull,
      reason: 'a picture a revision behind would show the wrong pixels for '
          'as long as the tile it is pinned to lives',
    );
    expect(overlay.tileImages[coord], same(picture));
    expect(
      overlay.takeTileImageAt(coord, revision: promoted.revision),
      same(picture),
    );
  });

  test('a picture a coordinate shows no more is let go', () {
    final (:overlay, :rasterizer) = strokeStarted();
    flush(overlay, rasterizer, [dabAt(2.5, 0)]);
    final before = overlay.tileImages[coord]!;
    flush(overlay, rasterizer, [dabAt(4.5, 1)]);
    final after = overlay.tileImages[coord]!;

    expect(after, isNot(same(before)));
    expect(before.debugDisposed, isTrue);
    expect(after.debugDisposed, isFalse);

    overlay.reset();

    expect(after.debugDisposed, isTrue);
  });

  test('a stroke is in hand while anything is shown, pictured or not', () {
    final (:overlay, :rasterizer) = strokeStarted();
    expect(overlay.strokeInHand, isFalse);

    flush(overlay, rasterizer, [dabAt(2.5, 0)]);
    expect(overlay.strokeInHand, isTrue, reason: 'owed');
    overlay.tileImages;
    expect(overlay.strokeInHand, isTrue, reason: 'pictured');

    overlay.reset();
    expect(overlay.strokeInHand, isFalse);
  });
}
