import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/a_fill_on_a_session.dart';
import '../../helpers/a_fill_on_the_engine.dart';
import '../../helpers/fill_pieces.dart';

/// 🚨I-36 — 「이 과정에서 법 다른거 통일」: the fill reads a POSED layer
/// through its pose, as the eyedropper has since R28 #7. P5+P6 skipped posed
/// layers in both tools as a 「v1」; only the fill kept the skip, so line art
/// with a transform key — or inside a folder with one — never walled a fill.
///
/// And the picture lies in the SEED's space: the artwork of the layer the
/// dab lands on. With that layer posed, the other layers are carried into
/// it.
///
/// Every case is a line row under a paint row, pressed as a canvas presses
/// it ([fillPressedOn]) standing on the paint row: each row posed by its
/// own keys, as the frame shows it.
void main() {
  opensTheEnginesScreens();
  const size = CanvasSize(width: 32, height: 32);
  const line = LayerId('line');
  const paint = LayerId('paint');

  /// Opaque black box outlines, each [side] wide from its (left, top), on
  /// a clear [canvas].
  BitmapSurface boxes(
    List<(int, int)> corners, {
    required int side,
    CanvasSize canvas = size,
  }) => celOfPixels(canvas, {
    for (final (left, top) in corners)
      for (var i = 0; i <= side; i += 1)
        for (final at in [
          (left + i, top),
          (left + i, top + side),
          (left, top + i),
          (left + side, top + i),
        ])
          at: const [0, 0, 0, 255],
  });

  /// One such outline, from ([left], [top]).
  BitmapSurface box({
    required int left,
    required int top,
    required int side,
    CanvasSize canvas = size,
  }) => boxes([(left, top)], side: side, canvas: canvas);

  /// An opaque black box outline [from]..[to] (inclusive) on a clear
  /// surface.
  BitmapSurface outline(int from, int to) =>
      box(left: from, top: from, side: to - from);

  /// The drawing row [id] (`drawingRow`), keyed to [scale] and to
  /// [position] over its cut.
  Layer row(String id, {CanvasPoint? scale, CanvasPoint? position}) =>
      drawingRow(id).copyWith(
        transformTrack: TransformTrack.empty().copyWith(
          scale: scale == null
              ? null
              : PropertyTrack<CanvasPoint>.empty().withKey(0, scale),
          position: position == null
              ? null
              : PropertyTrack<CanvasPoint>.empty().withKey(0, position),
        ),
      );

  /// The box of what a fill pressed at [seed] lays: on a frame of [rows]
  /// whose line row draws [drawn], standing on the paint row.
  ({int left, int top, int width, int height}) filledAt(
    CanvasPoint seed,
    List<Layer> rows,
    BitmapSurface drawn, {
    CanvasSize canvas = size,
    SymmetryShape? symmetry,
  }) => piecesBox(
    fillPressedOn(
          sessionOfRows(
            rows,
            canvasSize: canvas,
            cels: {(line, theCel): drawn},
            standOn: paint,
          ),
          seed,
          options: const FloodFillOptions(expandPx: 0, antiAlias: false),
          symmetry: symmetry,
        )?.dabsIn(0xFF3366CC) ??
        const [],
  );

  test('a posed line layer walls the fill where it is DRAWN — it used to be '
      'skipped, and the fill ran over the whole canvas', () {
    // Artwork box 12..19 scaled 2× about the canvas centre (16,16): drawn
    // over canvas 8..23, its inside canvas 10..21.
    final reach = filledAt(CanvasPoint(x: 16, y: 16), [
      row('line', scale: uniformScale(2)),
      row('paint'),
    ], outline(12, 19));
    expect(reach.width, lessThan(size.width), reason: 'the skip filled it all');
    expect(reach.width, inInclusiveRange(8, 12));
    expect(reach.height, inInclusiveRange(8, 12));
  });

  // A scale of zero — the frame a flip passes through (F-256-Q1) — is the
  // layer shown as nothing, so it walls nothing: the fill sees the picture
  // the screen shows.
  test('a line layer scaled to NOTHING walls nothing: the fill runs as if '
      'it were not there', () {
    final reach = filledAt(CanvasPoint(x: 16, y: 16), [
      row('line', scale: uniformScale(0)),
      row('paint'),
    ], outline(12, 19));
    expect((reach.width, reach.height), (size.width, size.height));
  });

  // The screen draws a posed layer filtered and the fill reads what the
  // screen shows — a line its layer shrinks thinner than a pixel still
  // shows there, faint, where a vote of the pixels under each would elect
  // the ground and open the wall.
  test('a line its layer shrinks thinner than a pixel walls the fill as it '
      'shows — faint, not voted away', () {
    // Artwork box 4..27 at 0.4× about the canvas centre (16,16): drawn
    // over canvas 11.2..20.8, its lines 0.4 px wide.
    final reach = filledAt(CanvasPoint(x: 16, y: 16), [
      row('line', scale: uniformScale(0.4)),
      row('paint'),
    ], outline(4, 27));
    expect(
      reach.width,
      lessThan(size.width),
      reason: 'the wall was voted away',
    );
    expect(reach.width, inInclusiveRange(7, 11));
    expect(reach.height, inInclusiveRange(7, 11));
  });

  test('the picture lies in the space the pen is in: a HALF-SIZED paint '
      'layer fills the line art\'s inside at its own scale', () {
    // Unposed box 8..23: inside canvas 9..22 (14). The paint layer is
    // posed 0.5× about the centre, so that inside is artwork 2..29 (28) in
    // its pixels — where the dab lands.
    final reach = filledAt(
      // Artwork (16,16) IS canvas (16,16) under a pose about the centre.
      CanvasPoint(x: 16, y: 16),
      [row('line'), row('paint', scale: uniformScale(0.5))],
      outline(8, 23),
    );
    expect(
      reach.width,
      greaterThan(20),
      reason: 'read in the canvas the region is 14 wide — half the pixels '
          'the paint layer needs to cover the inside',
    );
    expect(reach.width, lessThanOrEqualTo(28));
    expect(reach.height, greaterThan(20));
  });

  test('🚨a layer is read through the SEED\'s placement first and its own '
      'second: a line layer moved sideways walls a half-sized paint layer\'s '
      'fill where it is drawn', () {
    // The box, artwork 9..15 across and 13..19 down, moved 4 right: drawn
    // over canvas 13..19 both ways, its inside canvas 14..18. The paint
    // layer shows at half size about the centre (16, 16), so that inside is
    // its own pixels 12..21 both ways — 10 wide, its middle at 17.
    // ⚠️Read the other way round, the move is halved along with the paint
    // layer: the box walls 2 canvas pixels left of where it is drawn, and
    // the middle of what fills comes out at 13 across.
    final reach = filledAt(
      // Artwork (16, 16) IS canvas (16, 16) under a pose about the centre.
      CanvasPoint(x: 16, y: 16),
      [
        row('line', position: CanvasPoint(x: 20, y: 16)),
        row('paint', scale: uniformScale(0.5)),
      ],
      box(left: 9, top: 13, side: 6),
    );
    expect(reach.width, inInclusiveRange(8, 12));
    expect(reach.height, inInclusiveRange(8, 12));
    expect(reach.left + reach.width / 2, closeTo(17, 1.5));
    expect(reach.top + reach.height / 2, closeTo(17, 1.5));
  });

  test('a line layer moved sideways walls the fill where it is drawn, '
      'tiles away from where it lies', () {
    // A 512 canvas is four cel tiles a side. The box, artwork x 20..40 and
    // y 220..240, moved 300 right: drawn over canvas 320..340 across,
    // 220..240 down — two tiles across from the one that stores it.
    const big = CanvasSize(width: 512, height: 512);
    final reach = filledAt(
      CanvasPoint(x: 330, y: 230),
      [row('line', position: CanvasPoint(x: 556, y: 256)), row('paint')],
      box(left: 20, top: 220, side: 20, canvas: big),
      canvas: big,
    );
    expect(reach.width, lessThan(100), reason: 'the walls held');
    expect(reach.width, inInclusiveRange(17, 21));
    expect(reach.height, inInclusiveRange(17, 21));
  });

  // 🗣️F-256-Q1 (유저 2026-10-06): 「가른다 — AE 처럼 Scale X · Y」. A paint
  // layer can be stretched along one axis, and a symmetry is still the
  // canvas's: a stroke's copies and a fill's seeds are turned and mirrored
  // where the user sees them.
  test('🚨a symmetry copies the seed where the CANVAS turns it: under a paint '
      'layer stretched along one axis, each quarter turn of the seed fills '
      'the box the canvas shows a quarter turn round', () {
    const wide = CanvasSize(width: 64, height: 64);
    final middle = CanvasPoint(x: 32, y: 32);
    final reach = filledAt(
      // The middle of the right-hand box, (39, 32) on the canvas, in the
      // paint layer's own pixels.
      CanvasPoint(x: 46, y: 32),
      [
        row('line'),
        // The paint layer shows half as wide: its own x at 32 + (x − 32) / 2.
        row('paint', scale: CanvasPoint(x: 0.5, y: 1)),
      ],
      // Four boxes a quarter turn apart about the middle of the canvas — to
      // its right, below it, to its left and above it — each 5 across
      // inside.
      boxes([(36, 29), (29, 36), (22, 29), (29, 22)], side: 6, canvas: wide),
      canvas: wide,
      symmetry: SymmetryShape(
        axis: GuideAxis(origin: middle, angleDegrees: 90),
        lineCount: 4,
        lineSymmetry: false,
      ),
    );

    // The four insides and nothing else: 19 across and 19 down on the
    // canvas, so twice as many across in the paint layer's pixels.
    // ⚠️Turned in the paint layer's own pixels instead, the seed's quarter
    // turn shows at (32, 46) — under the lower box, in the open — and the
    // fill runs over the whole picture.
    expect(reach.height, inInclusiveRange(15, 23));
    expect(reach.width, inInclusiveRange(30, 46));
  });
}
