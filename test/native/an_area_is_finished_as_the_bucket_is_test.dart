import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';

import '../helpers/a_canvas_standing_on_a_frame.dart';
import '../helpers/a_fill_on_the_engine.dart';
import '../helpers/fill_pieces.dart';

/// 🚨TWO SPELLINGS, HELD SHUT HERE (board
/// `an-areas-finish-is-a-second-spelling-of-the-floods`). A user has ONE
/// 「Expand」 and ONE 「Anti-alias」 for the bucket and for an area — the
/// shape tool's fill, its plain line — and since the bucket's flood runs on
/// the engine (2026-11-12) the two are finished by two spellings of those
/// passes: the bucket's by the engine's mask kernel (WGSL), an area's by
/// `dilateMask4` · `softenMaskBoundary` (Dart).
///
/// Each is asked through its own door, of the SAME pixels: a shape drawn in
/// one colour on clear ground and bucket-filled at tolerance 0 floods
/// exactly the shape, and the same shape is laid as an area. What the two
/// lay is the same bytes, pixel for pixel.
///
/// ↩️Till then the two spellings were Dart's and the C kernel's
/// (`qa_fill_finish_mask`), held mask for mask by `fill_gap_close_test`,
/// which skipped without a built DLL. This one cannot skip: a file that
/// cannot open the engine fails.
void main() {
  opensTheEnginesScreens();
  const canvasSize = CanvasSize(width: 64, height: 48);
  const color = 0xFF3366CC;

  /// Five rects (left, top, right and bottom exclusive), each holding a
  /// pixel of the one before — one 4-connected shape, corners and notches
  /// and all — kept far enough inside the canvas that no finish meets its
  /// edge.
  List<(int, int, int, int)> shapeOf(Random random) {
    final rects = <(int, int, int, int)>[];
    var (x, y) = (16 + random.nextInt(32), 16 + random.nextInt(16));
    for (var i = 0; i < 5; i += 1) {
      final left = max(10, x - random.nextInt(8));
      final top = max(10, y - random.nextInt(6));
      final right = min(54, x + 1 + random.nextInt(8));
      final bottom = min(38, y + 1 + random.nextInt(6));
      rects.add((left, top, right, bottom));
      x = left + random.nextInt(right - left);
      y = top + random.nextInt(bottom - top);
    }
    return rects;
  }

  /// [shape] drawn in one colour and bucket-filled from inside it.
  List<BrushDab> bucketOf(
    List<(int, int, int, int)> shape,
    FloodFillOptions options,
  ) {
    final (left, top, _, _) = shape.first;
    return fillRangeAt(
      canvasSize: canvasSize,
      pictureOver: fillPictureOfRows([
        fillRow(
          celOfPixels(canvasSize, {
            for (final (left, top, right, bottom) in shape)
              for (var y = top; y < bottom; y += 1)
                for (var x = left; x < right; x += 1)
                  (x, y): const [200, 30, 30, 255],
          }),
        ),
      ], canvasSize: canvasSize),
      point: CanvasPoint(x: left + 0.5, y: top + 0.5),
      options: options,
    )!.dabsIn(color);
  }

  /// [shape] laid as an area.
  List<BrushDab> areaOf(
    List<(int, int, int, int)> shape,
    FloodFillOptions options,
  ) => buildRegionFillDabs(
    region: CanvasSelectionRegion([
      for (final (at, (left, top, right, bottom)) in shape.indexed)
        CanvasSelectionStep(
          CanvasSelectionShape.rect(
            left: left.toDouble(),
            top: top.toDouble(),
            right: right.toDouble(),
            bottom: bottom.toDouble(),
          ),
          at == 0 ? SelectionCombineMode.replace : SelectionCombineMode.add,
        ),
    ]),
    color: color,
    options: options,
  );

  for (final expand in [0, 1, 3]) {
    for (final antiAlias in [false, true]) {
      test('expand $expand, anti-alias $antiAlias: an area lays the bytes '
          'the bucket lays of the same shape', () {
        final options = FloodFillOptions(
          tolerance: 0,
          expandPx: expand,
          antiAlias: antiAlias,
        );
        final random = Random(expand * 2 + (antiAlias ? 1 : 0));
        var ramped = false;
        for (var shapeAt = 0; shapeAt < 6; shapeAt += 1) {
          final shape = shapeOf(random);
          final bucket = bucketOf(shape, options);
          final area = areaOf(shape, options);
          for (var y = 0; y < canvasSize.height; y += 1) {
            for (var x = 0; x < canvasSize.width; x += 1) {
              final laid = piecesRgbaAt(area, x, y);
              expect(
                piecesRgbaAt(bucket, x, y),
                laid,
                reason: 'at ($x, $y) of shape $shapeAt, $shape',
              );
              ramped |= laid[3] > 0 && laid[3] < 255;
            }
          }
        }
        expect(
          ramped,
          antiAlias,
          reason: 'fixture: a ramp is what the anti-alias lays, and only it',
        );
      });
    }
  }
}
