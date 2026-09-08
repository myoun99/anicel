import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**AN ERASER THAT ARRIVES WITHOUT LIVE PIXELS ERASED NOTHING.**
/// A stroke that needs the whole buffer (a brush blend, or any opacity
/// under 100%) and has no live raster is rasterized onto an EMPTY surface
/// first — and there an erase dab erases nothing from nothing, so the
/// buffer came out all zero and the commit was a no-op.
///
/// ⛔The law was already written one file over, in
/// `rasterizeStrokeForClipping`: 「Erase dabs rasterize with the flag
/// flipped OFF: what is wanted here is the stroke's COVERAGE, which the
/// commit then re-applies as one erase stamp」. There were two
/// implementations of that one algorithm and only one of them knew it.
/// The commit builder calls the sibling now.
void main() {
  const canvas = CanvasSize(width: 8, height: 8);
  const layerId = LayerId('l');
  const frameId = FrameId('f');
  final origin = TileCoord(x: 0, y: 0);

  BrushDab dabAt(double x, double y, {bool erase = false}) => BrushDab(
    center: CanvasPoint(x: x + 0.5, y: y + 0.5),
    color: 0xFFFF0000,
    size: 1,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  ).copyWith(erase: erase);

  BitmapSurface painted() => materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(canvasSize: canvas, tileSize: 4),
    sequence: BrushDabSequence([dabAt(0, 0), dabAt(1, 1)]),
  ).surface;

  int alphaAt(BitmapSurface surface, int x, int y) {
    final tile = surface.tileAt(origin);
    if (tile == null) {
      return 0;
    }
    return tile.pixels[tile.byteOffsetForPixel(x: x, y: y) + 3];
  }

  /// The stroke opacity is what puts this on the whole-buffer route —
  /// `strokeOpacityCoverage(opacity) < 255` — with no prerasterized pixels
  /// to short-circuit it. A programmatic commit is exactly that shape.
  test('🚨a half-opacity eraser with no live raster actually removes ink', () {
    final before = painted();
    expect(alphaAt(before, 0, 0), greaterThan(0), reason: 'there is ink here');

    final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: before,
      sequence: BrushDabSequence([dabAt(0, 0, erase: true)], 0.5),
      layerId: layerId,
      frameId: frameId,
    );

    expect(
      result.hasChanges,
      isTrue,
      reason: 'an eraser over ink is never a no-op',
    );
    expect(
      alphaAt(result.afterSurface, 0, 0),
      lessThan(alphaAt(before, 0, 0)),
      reason: 'the ink under the eraser is thinner than it was',
    );
    expect(
      alphaAt(result.afterSurface, 1, 1),
      alphaAt(before, 1, 1),
      reason: 'and the ink the stroke never touched is untouched',
    );
  });

  test('the same eraser at full opacity — the route that always worked — '
      'still clears the pixel', () {
    final before = painted();

    final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: before,
      sequence: BrushDabSequence([dabAt(0, 0, erase: true)]),
      layerId: layerId,
      frameId: frameId,
    );

    expect(alphaAt(result.afterSurface, 0, 0), 0);
    expect(alphaAt(result.afterSurface, 1, 1), alphaAt(before, 1, 1));
  });

  test('a BLEND that needs the whole buffer takes the same route, and a '
      'painting stroke through it still lands', () {
    final before = painted();

    final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: before,
      sequence: BrushDabSequence([dabAt(2, 2)]),
      layerId: layerId,
      frameId: frameId,
      blendMode: BrushBlendMode.multiply,
    );

    expect(result.hasChanges, isTrue);
    expect(BitmapTile.bytesFor(4), 64);
  });
}
