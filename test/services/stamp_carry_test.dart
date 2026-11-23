import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:anicel/src/services/stamp_carry.dart';

/// 🚨★★★**WHAT A BOX DID TO ITS FLOAT, ANY OTHER STAMP CAN BE CARRIED
/// THROUGH** (`a-warp-over-a-frame-range-lands-on-one-cel`, 2026-10-06).
///
/// A confirm over a frame range lands every cel of the range, each taking
/// the SAME transform on its own pixels (유저 2026-09-17 「동시적용은
/// 가능하게」 · H41 「아니면 각자 그림 전체적용」). ↩️Only the box's affine came
/// down to them, so a quad or a mesh — under which the affine is the
/// identity — bent the cel you stood on and nothing else.
///
/// The carry is the box's mapping of the CANVAS. These pin its two halves:
/// the float, which the box stands on, lands the bytes the transform
/// functions land; and a stamp standing anywhere else goes where the same
/// mapping sends that place.
void main() {
  const mode = ResampleMode.blend;

  /// A stamp standing at ([left], [top]), clear but for a 6×6 opaque block
  /// centred on each of [ink] (canvas points).
  BrushDab stampOver({
    required int left,
    required int top,
    required int width,
    required int height,
    required List<CanvasPoint> ink,
  }) {
    final rgba = Uint8List(width * height * 4);
    for (final spot in ink) {
      for (var dy = -3; dy < 3; dy += 1) {
        for (var dx = -3; dx < 3; dx += 1) {
          final x = spot.x.round() + dx - left;
          final y = spot.y.round() + dy - top;
          if (x < 0 || y < 0 || x >= width || y >= height) {
            fail('⛔fixture: ink at $spot is off the stamp');
          }
          rgba.setRange((y * width + x) * 4, (y * width + x) * 4 + 4, const [
            255,
            0,
            0,
            255,
          ]);
        }
      }
    }
    return BrushDab(
      center: CanvasPoint(x: left + width / 2, y: top + height / 2),
      color: 0xFF000000,
      size: (width > height ? width : height).toDouble(),
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      stamp: BrushStampImage(
        id: 'stamp-$left-$top-$width-$height',
        width: width,
        height: height,
        rgba: rgba,
      ),
    );
  }

  /// The centre of the ink in [dab] nearest [near], on the canvas — the
  /// alpha-weighted mean of what lies within [reach] of it.
  CanvasPoint inkNear(BrushDab dab, CanvasPoint near, {double reach = 14}) {
    final stamp = dab.stamp!;
    final left = dab.center.x - stamp.width / 2;
    final top = dab.center.y - stamp.height / 2;
    var weight = 0.0;
    var sumX = 0.0;
    var sumY = 0.0;
    for (var y = 0; y < stamp.height; y += 1) {
      for (var x = 0; x < stamp.width; x += 1) {
        final alpha = stamp.rgba[(y * stamp.width + x) * 4 + 3];
        if (alpha == 0) {
          continue;
        }
        final cx = left + x + 0.5;
        final cy = top + y + 0.5;
        if ((cx - near.x).abs() > reach || (cy - near.y).abs() > reach) {
          continue;
        }
        weight += alpha;
        sumX += alpha * cx;
        sumY += alpha * cy;
      }
    }
    expect(weight, greaterThan(0), reason: 'ink within $reach of $near');
    return CanvasPoint(x: sumX / weight, y: sumY / weight);
  }

  double apart(CanvasPoint a, CanvasPoint b) => a.distanceTo(b);

  /// The 6×6 block [stampOver] inks about [spot], as a selection.
  CanvasSelectionRegion blockAt(CanvasPoint spot) {
    final (x, y) = (spot.x.roundToDouble(), spot.y.roundToDouble());
    return CanvasSelectionRegion.shape(
      CanvasSelectionShape([
        CanvasPoint(x: x - 3, y: y - 3),
        CanvasPoint(x: x + 3, y: y - 3),
        CanvasPoint(x: x + 3, y: y + 3),
        CanvasPoint(x: x - 3, y: y + 3),
      ]),
    );
  }

  /// Every outline of [region], as its points.
  List<List<CanvasPoint>> ringsOf(CanvasSelectionRegion region) => [
    for (final step in region.steps)
      if (step is CanvasSelectionCopies)
        for (final shape in step.shapes) shape.points,
  ];

  /// The mean of [region]'s one outline's points.
  CanvasPoint middleOf(CanvasSelectionRegion region) {
    final [ring] = ringsOf(region);
    return CanvasPoint(
      x: ring.map((point) => point.x).reduce((a, b) => a + b) / ring.length,
      y: ring.map((point) => point.y).reduce((a, b) => a + b) / ring.length,
    );
  }

  void sameStamp(BrushDab got, BrushDab want, String why) {
    expect(got.center, want.center, reason: '$why — where it stands');
    expect(got.stamp!.width, want.stamp!.width, reason: why);
    expect(got.stamp!.height, want.stamp!.height, reason: why);
    expect(got.stamp!.rgba, want.stamp!.rgba, reason: '$why — its bytes');
  }

  // The float every case stands its box on: 100×100 at (100, 100).
  BrushDab float({List<CanvasPoint>? ink}) => stampOver(
    left: 100,
    top: 100,
    width: 100,
    height: 100,
    ink: ink ?? [CanvasPoint(x: 130, y: 140), CanvasPoint(x: 170, y: 160)],
  );

  group('an affine', () {
    test('carries any stamp through the affine itself', () {
      final affine = SelectionAffine(
        pivot: CanvasPoint(x: 150, y: 150),
        sx: 1.5,
        sy: 0.75,
        rotationDegrees: 20,
        tx: 12,
        ty: -7,
      );
      final other = stampOver(
        left: 40,
        top: 220,
        width: 60,
        height: 40,
        ink: [CanvasPoint(x: 60, y: 240)],
      );
      sameStamp(
        AffineCarry(affine, mode: mode).through(other),
        transformStampDab(other, affine, mode: mode),
        'another stamp',
      );
    });
  });

  group('a quad', () {
    // The float's corners, and where the box put them: the top-left pulled
    // out, the bottom-right pulled in.
    final base = stampCornersOf(float())!;
    final corners = [
      CanvasPoint(x: 88, y: 94),
      base[1],
      CanvasPoint(x: 190, y: 185),
      base[3],
    ];
    final carry = QuadCarry(base: base, corners: corners, mode: mode);

    test('the float lands the bytes the quad transform lands', () {
      sameStamp(
        carry.through(float()),
        transformStampDabQuad(float(), corners, mode: mode),
        'the float',
      );
    });

    test('🚨a stamp standing elsewhere goes where the SAME homography sends '
        'that place', () {
      // Off to the right of the box and below it, reaching past both.
      final spot = CanvasPoint(x: 250, y: 230);
      final other = stampOver(
        left: 180,
        top: 170,
        width: 120,
        height: 110,
        ink: [spot],
      );
      final h = solveHomography(base, corners)!;
      final sent = applyHomography(h, spot);
      expect(
        apart(sent, spot),
        greaterThan(6),
        reason: '⛔premise: the mapping moves this place',
      );

      final carried = carry.through(other);

      expect(apart(inkNear(carried, sent), sent), lessThan(1.5));
    });

    test('🚨a quad dragged whole carries every stamp by its step, byte for '
        'byte', () {
      // ⚠️NOT the 100×100 float: a homography solved for a whole drag of
      // THAT rect is exact, and one solved for this one is not (measured
      // 2026-10-06) — which is the case the carry's own check is for.
      final rest = stampCornersOf(
        stampOver(
          left: 23,
          top: 41,
          width: 57,
          height: 33,
          ink: [CanvasPoint(x: 50, y: 55)],
        ),
      )!;
      final gone = [
        for (final corner in rest)
          CanvasPoint(x: corner.x + 7, y: corner.y - 3),
      ];
      final other = stampOver(
        left: 10,
        top: 20,
        width: 40,
        height: 30,
        ink: [CanvasPoint(x: 30, y: 35)],
      );
      final solved = solveHomography(rest, gone)!;
      expect(
        {
          for (final corner in stampCornersOf(other)!)
            applyHomography(solved, corner).y - corner.y,
        },
        hasLength(greaterThan(1)),
        reason: '⛔premise: solved again, the drag is not ONE delta any more',
      );

      final carried = QuadCarry(
        base: rest,
        corners: gone,
        mode: mode,
      ).through(other);

      expect(carried.center, CanvasPoint(x: 37, y: 32));
      expect(identical(carried.stamp!.rgba, other.stamp!.rgba), isTrue);
    });

    test('🚨a quad too degenerate to warp through moves no selection, as it '
        'moves no pixel', () {
      // ↩️The selection became the quad itself.
      final flat = [
        for (var k = 0; k < 4; k += 1)
          CanvasPoint(x: 100.0 + k * 30, y: 100.0 + k * 30),
      ];
      final degenerate = QuadCarry(base: base, corners: flat, mode: mode);
      final standing = float();
      expect(
        solveHomography(base, flat),
        isNull,
        reason: '⛔premise: no homography takes the box there',
      );
      expect(
        identical(degenerate.through(standing), standing),
        isTrue,
        reason: '⛔premise: no pixel moves',
      );
      final selected = blockAt(CanvasPoint(x: 130, y: 140));

      expect(identical(degenerate.regionThrough(selected), selected), isTrue);
    });

    group('🚨a box pinched to a point carries a float past it', () {
      // a-small-float-in-steep-perspective-vanishes (검증/서피스 11-23): a
      // box on a selection's fractional bounds, its float the whole pixels
      // they round out to — and a grow past that —, its top edge pulled in
      // to a pixel or two. The horizon then lies a pixel or two under the
      // box, inside what the float holds past it. ↩️The float went back to
      // its own picture unwarped, and once was gone.
      final box = cornersOfStampRect((
        left: 1284.4,
        top: 700.4,
        width: 132,
        height: 110,
      ));
      const wall = (left: 1000.0, top: 500.0, right: 1700.0, bottom: 1100.0);
      /// The box with its top edge — its bottom edge, [under] — pulled in
      /// to [edge] px about its middle.
      List<CanvasPoint> pinchedTo(double edge, {bool under = false}) {
        final y = under ? 810.4 : 700.4;
        final left = CanvasPoint(x: 1350.4 - edge / 2, y: y);
        final right = CanvasPoint(x: 1350.4 + edge / 2, y: y);
        return under
            ? [box[0], box[1], right, left]
            : [left, right, box[2], box[3]];
      }

      // Ink in the half of the box away from the pinch, where it leaves
      // room.
      List<CanvasPoint> spotsUnder({bool under = false}) => [
        for (final x in [1310.0, 1350.0, 1390.0])
          CanvasPoint(x: x, y: under ? 716 : 795),
      ];
      BrushDab floatPastBy(int grow, {bool under = false}) => stampOver(
        left: 1284 - grow,
        top: 700 - grow,
        width: 133 + 2 * grow,
        height: 111 + 2 * grow,
        ink: spotsUnder(under: under),
      );

      /// [dab]'s pixel at canvas ([x], [y]) — clear off its stamp.
      List<int> pixelAt(BrushDab dab, int x, int y) {
        final made = dab.stamp!;
        final col = x - (dab.center.x - made.width / 2).round();
        final row = y - (dab.center.y - made.height / 2).round();
        if (col < 0 || row < 0 || col >= made.width || row >= made.height) {
          return const [0, 0, 0, 0];
        }
        final at = (row * made.width + col) * 4;
        return made.rgba.sublist(at, at + 4);
      }

      // Each edge over a float that stops short of the horizon and one
      // grown past it.
      for (final (edge, short, past, under) in [
        (1.0, 0, 2, false),
        (2.0, 0, 2, false),
        (4.0, 0, 4, false),
        (2.0, 0, 2, true),
      ]) {
        test('a${under ? ' bottom' : ' top'} edge of $edge px', () {
          final corners = pinchedTo(edge, under: under);
          final spots = spotsUnder(under: under);
          BrushDab floatPast(int grow) => floatPastBy(grow, under: under);
          final there = solveHomography(box, corners)!;
          double wAt(CanvasPoint at) =>
              there[6] * at.x + there[7] * at.y + there[8];
          // The side of the horizon the box is on, as w's sign.
          final front = wAt(box[0]).sign;
          List<double> wsOf(BrushDab float) => [
            for (final corner in stampCornersOf(float)!) wAt(corner) * front,
          ];
          expect(
            wsOf(floatPast(short)).where((w) => w <= 0),
            isEmpty,
            reason: '⛔premise: rounded out alone, the float stops short of '
                'the horizon (w <= 0 past it)',
          );
          expect(
            wsOf(floatPast(past)).where((w) => w <= 0),
            isNotEmpty,
            reason: '⛔premise: grown, it reaches past the horizon',
          );
          final carry = QuadCarry(
            base: box,
            corners: corners,
            mode: mode,
            within: wall,
          );
          final landed = [
            for (final grow in [short, past]) carry.through(floatPast(grow)),
          ];

          for (final (index, carried) in landed.indexed) {
            final why = index == 0 ? 'short of it' : 'past it';
            for (final spot in spots) {
              final sent = applyHomography(there, spot);
              expect(apart(sent, spot), greaterThan(6), reason: '⛔premise');
              expect(
                apart(inkNear(carried, sent, reach: 6), sent),
                lessThan(3),
                reason: '$why: the ink goes where the quad sends it',
              );
            }
            final made = carried.stamp!;
            final left = (carried.center.x - made.width / 2).round();
            final top = (carried.center.y - made.height / 2).round();
            expect(left, greaterThanOrEqualTo(wall.left), reason: why);
            expect(
              top + made.height,
              lessThanOrEqualTo(wall.bottom),
              reason: why,
            );
            if (index == 0) {
              continue;
            }
            // Past the horizon it lands without end away from the pinch,
            // cut there by the wall — and by the float's own edges on the
            // other three sides, however wide the wall is.
            final (near, far) = under
                ? (top + made.height, top)
                : (top, top + made.height);
            expect(far, under ? wall.top : wall.bottom);
            expect(near, closeTo(under ? 812 : 698, 4));
            expect(left, greaterThan(wall.left + 50));
            expect(left + made.width, lessThan(wall.right - 50));
          }
          // What the float holds in front of the horizon lands the same,
          // however far past it the float reaches: within the quad, and
          // nothing beyond (all it holds past the box is clear).
          for (var y = 690; y < 830; y += 1) {
            for (var x = 1270; x < 1430; x += 1) {
              final stops = pixelAt(landed[0], x, y);
              final reaches = pixelAt(landed[1], x, y);
              for (var channel = 0; channel < 4; channel += 1) {
                expect(
                  (stops[channel] - reaches[channel]).abs(),
                  lessThanOrEqualTo(1),
                  reason: '($x, $y) $channel',
                );
              }
              if (stops[3] != 0) {
                expect(x, inInclusiveRange(1283, 1417));
                expect(y, inInclusiveRange(699, 811));
              }
            }
          }
        });
      }

      test('what a float holds between the box and the horizon goes on to '
          'the wall', () {
        // Ink on the box's bottom edge, reaching a row past it — in front
        // of the horizon, under a pixel and a half further on.
        final edge = CanvasPoint(x: 1350, y: 811);
        final float = stampOver(
          left: 1280,
          top: 696,
          width: 141,
          height: 119,
          ink: [edge],
        );
        final corners = pinchedTo(2);
        final there = solveHomography(box, corners)!;
        expect(
          there[6] * 1350 + there[7] * 811.5 + there[8],
          greaterThan(0),
          reason: '⛔premise: the row past the box is in front of the horizon',
        );

        final carried = QuadCarry(
          base: box,
          corners: corners,
          mode: mode,
          within: wall,
        ).through(float);

        final made = carried.stamp!;
        final top = (carried.center.y - made.height / 2).round();
        expect(top + made.height, wall.bottom);
        var lowest = 0;
        for (var y = 0; y < made.height; y += 1) {
          for (var x = 0; x < made.width; x += 1) {
            if (made.rgba[(y * made.width + x) * 4 + 3] != 0) {
              lowest = math.max(lowest, top + y);
            }
          }
        }
        expect(lowest, greaterThan(wall.bottom - 10));
      });

      test('a picture wholly past the horizon lands nothing', () {
        // Another cel's, under the box — past the horizon a pixel and a
        // bit under it, where the mapping comes back from the far side.
        final under = stampOver(
          left: 1290,
          top: 830,
          width: 120,
          height: 60,
          ink: [CanvasPoint(x: 1350, y: 860)],
        );
        final corners = pinchedTo(2);
        final there = solveHomography(box, corners)!;
        expect(
          [
            for (final corner in stampCornersOf(under)!)
              there[6] * corner.x + there[7] * corner.y + there[8],
          ].every((w) => w < 0),
          isTrue,
          reason: '⛔premise: all of it lies past the horizon',
        );

        final carried = QuadCarry(
          base: box,
          corners: corners,
          mode: mode,
          within: wall,
        ).through(under);

        final rgba = carried.stamp!.rgba;
        expect([
          for (var i = 3; i < rgba.length; i += 4) rgba[i],
        ], everyElement(0));
      });

      test('a picture reaching the horizon asks for a wall to cut it at', () {
        expect(
          () => QuadCarry(
            base: box,
            corners: pinchedTo(2),
            mode: mode,
          ).through(floatPastBy(2)),
          throwsArgumentError,
        );
      });
    });
  });

  group('a mesh', () {
    final base = stampRectOf(float())!;

    /// A 2×2 grid over the float, each node at [at] of its base place.
    MeshCarry meshWhere(CanvasPoint Function(CanvasPoint base) at) => MeshCarry(
      (
        base: base,
        columns: 2,
        rows: 2,
        points: [
          for (var row = 0; row <= 2; row += 1)
            for (var column = 0; column <= 2; column += 1)
              at(CanvasPoint(x: 100.0 + column * 50, y: 100.0 + row * 50)),
        ],
      ),
      mode: mode,
    );

    // The middle node pulled, the edge left where it is.
    final bulge = meshWhere(
      (node) => node == CanvasPoint(x: 150, y: 150)
          ? CanvasPoint(x: 162, y: 141)
          : node,
    );

    test('the float lands the bytes the mesh transform lands', () {
      sameStamp(
        bulge.through(float()),
        transformStampDabMesh(
          float(),
          columns: 2,
          rows: 2,
          points: bulge.points,
          mode: mode,
        ),
        'the float',
      );
    });

    test('🚨inside the box, a bigger stamp is carried exactly as the float '
        'is', () {
      final ink = [CanvasPoint(x: 130, y: 140), CanvasPoint(x: 170, y: 160)];
      final onTheFloat = bulge.through(float(ink: ink));
      // The same ink, on a stamp that reaches 60 past the box on every side.
      final bigger = bulge.through(
        stampOver(left: 40, top: 40, width: 220, height: 220, ink: ink),
      );

      for (final spot in ink) {
        final want = inkNear(onTheFloat, spot, reach: 20);
        expect(
          apart(want, spot),
          greaterThan(2),
          reason: '⛔premise: the bulge moves this ink',
        );
        expect(apart(inkNear(bigger, want), want), lessThan(0.6));
      }
    });

    test('🚨past the box a stamp is carried ON the way the edge was going — '
        'not left where it was, not cut off (H41)', () {
      // The whole grid half again the size about its top-left corner: each
      // edge cell steps 75 where it stepped 50, so past the edge the canvas
      // goes on by the same rule.
      CanvasPoint grown(CanvasPoint p) => CanvasPoint(
        x: 100 + (p.x - 100) * 1.5,
        y: 100 + (p.y - 100) * 1.5,
      );
      final carry = meshWhere(grown);
      // 100 past the box on every side, with ink in each part: beside the
      // box, above and below it, and past a corner — where the grid goes on
      // along both of its ways at once.
      final spots = [
        CanvasPoint(x: 150, y: 150), // inside
        CanvasPoint(x: 30, y: 150), // left of it
        CanvasPoint(x: 270, y: 150), // right of it
        CanvasPoint(x: 150, y: 30), // above
        CanvasPoint(x: 150, y: 270), // below
        CanvasPoint(x: 30, y: 30), // past the top-left corner
        CanvasPoint(x: 270, y: 270), // past the bottom-right corner
      ];
      final wide = stampOver(
        left: 0,
        top: 0,
        width: 300,
        height: 300,
        ink: spots,
      );

      final carried = carry.through(wide);

      for (final spot in spots) {
        final sent = grown(spot);
        expect(
          apart(inkNear(carried, sent), sent),
          lessThan(1.5),
          reason: 'ink at $spot goes to $sent',
        );
      }
    });

    test('🚨a stamp reaching past the box by PART of a cell is carried to '
        'its last pixel', () {
      // 60 past a box whose cells are 50: one whole cell and a fifth of the
      // next. The ink stands in that last fifth, on each side.
      CanvasPoint grown(CanvasPoint p) => CanvasPoint(
        x: 100 + (p.x - 100) * 1.5,
        y: 100 + (p.y - 100) * 1.5,
      );
      final spots = [
        CanvasPoint(x: 45, y: 150), // left
        CanvasPoint(x: 255, y: 150), // right
        CanvasPoint(x: 150, y: 45), // above
        CanvasPoint(x: 150, y: 255), // below
      ];
      final reaching = stampOver(
        left: 40,
        top: 40,
        width: 220,
        height: 220,
        ink: spots,
      );

      final carried = meshWhere(grown).through(reaching);

      for (final spot in spots) {
        final sent = grown(spot);
        expect(
          apart(inkNear(carried, sent), sent),
          lessThan(1.5),
          reason: 'ink at $spot goes to $sent',
        );
      }
    });

    test('🚨a grid dragged whole carries every stamp by its step, byte for '
        'byte — the default 3×3 too', () {
      // ⚠️Three cells across a hundred: a cell is a third, and the grid
      // grown past its box for a stamp out here restates the drag with a
      // residue (measured 2026-10-06 — sixteen deltas for the one). On the
      // 2×2 the other cases use, every number is whole and nothing shows.
      final rest = meshRestGrid(base, columns: 3, rows: 3);
      final dragged = MeshCarry(
        (
          base: base,
          columns: 3,
          rows: 3,
          points: [
            for (final node in rest)
              CanvasPoint(x: node.x - 9, y: node.y + 4),
          ],
        ),
        mode: mode,
      );
      final other = stampOver(
        left: 300,
        top: 10,
        width: 50,
        height: 50,
        ink: [CanvasPoint(x: 320, y: 30)],
      );

      final carried = dragged.through(other);

      expect(carried.center, CanvasPoint(x: 316, y: 39));
      expect(identical(carried.stamp!.rgba, other.stamp!.rgba), isTrue);
    });

    test('a grid left at rest hands the stamp back as it is', () {
      final standing = float();

      final still = MeshCarry(
        (
          base: base,
          columns: 3,
          rows: 3,
          points: meshRestGrid(base, columns: 3, rows: 3),
        ),
        mode: mode,
      ).through(standing);

      expect(identical(still, standing), isTrue);
    });

    // 🚨A selection goes where its pixels go (card a-mesh-warp-turns-the-
    // selection-into-its-box, 2026-11-21): ↩️it became the grid's outer
    // ring, holding pixels the mesh never moved.
    test('🚨a selection goes where the mesh takes its pixels — a block of '
        'ink in each half of the cells around the node pulled', () {
      // Each block within one triangle of its cell, so its outline is its
      // four corners still: (top left, top right, bottom left) of the cell
      // or (top right, bottom right, bottom left).
      final spots = [
        CanvasPoint(x: 120, y: 115),
        CanvasPoint(x: 132, y: 132),
        CanvasPoint(x: 165, y: 125),
        CanvasPoint(x: 140, y: 175),
        CanvasPoint(x: 160, y: 160),
      ];
      final carried = bulge.through(float(ink: spots));
      final selected = [
        for (final spot in spots) middleOf(bulge.regionThrough(blockAt(spot))),
      ];

      expect(
        [for (final (at, spot) in spots.indexed) apart(selected[at], spot) > 2],
        [false, true, true, true, true],
        reason: '⛔premise: the pull moves all but the first',
      );
      for (final (at, spot) in spots.indexed) {
        expect(
          // Near enough to read this block's ink alone, not a neighbour's
          // the pull brought closer.
          apart(inkNear(carried, selected[at], reach: 6), selected[at]),
          lessThan(0.6),
          reason: 'the ink of $spot and its selection',
        );
      }
    });

    test('🚨an edge is cut where it crosses a diagonal of the cells, and '
        'bends there as the pixels do', () {
      final corner = MeshCarry(
        (
          base: (left: 0, top: 0, width: 10, height: 10),
          columns: 1,
          rows: 1,
          points: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 10, y: 0),
            CanvasPoint(x: 0, y: 10),
            CanvasPoint(x: 10, y: 20),
          ],
        ),
        mode: mode,
      );

      final through = corner.regionThrough(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape([
            CanvasPoint(x: 0, y: 4),
            CanvasPoint(x: 10, y: 4),
            CanvasPoint(x: 10, y: 6),
            CanvasPoint(x: 0, y: 6),
          ]),
        ),
      );

      // Cut at (6,4) and (4,6), on the diagonal: the bottom right corner
      // pulled 10 down bends each edge there, and moves nothing on its top
      // left.
      final want = [
        CanvasPoint(x: 0, y: 4),
        CanvasPoint(x: 6, y: 4),
        CanvasPoint(x: 10, y: 8),
        CanvasPoint(x: 10, y: 12),
        CanvasPoint(x: 4, y: 6),
        CanvasPoint(x: 0, y: 6),
      ];
      final [ring] = ringsOf(through);
      expect(ring.length, want.length, reason: '$ring');
      for (final (at, point) in want.indexed) {
        expect(apart(ring[at], point), lessThan(1e-9), reason: '$ring');
      }
    });

    test('🚨an edge is cut where it crosses a side between two cells, and '
        'bends there as the pixels do — the cells side by side, or one '
        'over the other', () {
      // Two cells side by side, the node at the bottom of the side between
      // them pulled 10 down; and the same laid the other way, each point's
      // x and y swapped — which the cells' diagonals are swapped onto.
      for (final sideBySide in [true, false]) {
        CanvasPoint at(double x, double y) => sideBySide
            ? CanvasPoint(x: x, y: y)
            : CanvasPoint(x: y, y: x);
        final nodes = [
          [at(0, 0), at(10, 0), at(20, 0)],
          [at(0, 10), at(10, 20), at(20, 10)],
        ];
        final twoCells = MeshCarry(
          (
            base: sideBySide
                ? (left: 0, top: 0, width: 20, height: 10)
                : (left: 0, top: 0, width: 10, height: 20),
            columns: sideBySide ? 2 : 1,
            rows: sideBySide ? 1 : 2,
            points: sideBySide
                ? [for (final row in nodes) ...row]
                : [
                    for (var column = 0; column < 3; column += 1)
                      for (final row in nodes) row[column],
                  ],
          ),
          mode: mode,
        );

        final through = twoCells.regionThrough(
          CanvasSelectionRegion.shape(
            CanvasSelectionShape([at(2, 6), at(18, 6), at(18, 7), at(2, 7)]),
          ),
        );

        // The long edges cut on the side (10 along) and on each cell's
        // diagonal (4 and 14 along the first, 13 and 3 along the second).
        final want = [
          at(2, 6),
          at(4, 6),
          at(10, 12),
          at(14, 12),
          at(18, 8),
          at(18, 9),
          at(13, 14),
          at(10, 14),
          at(3, 7),
          at(2, 7),
        ];
        final [ring] = ringsOf(through);
        expect(ring.length, want.length, reason: '$sideBySide: $ring');
        for (final (index, point) in want.indexed) {
          expect(
            apart(ring[index], point),
            lessThan(1e-9),
            reason: '$sideBySide: $ring',
          );
        }
      }
    });

    test('🚨past the box a selection goes where its pixels go — on the way '
        'the edge was going (H41)', () {
      // A block beside each side of the box, in the half of a cell past it
      // that the pulled node leads on to.
      final spots = [
        CanvasPoint(x: 60, y: 160), // left of it
        CanvasPoint(x: 160, y: 60), // above
        CanvasPoint(x: 240, y: 140), // right of it
        CanvasPoint(x: 140, y: 240), // below
      ];
      final carried = bulge.through(
        stampOver(left: 0, top: 0, width: 300, height: 300, ink: spots),
      );
      final selected = [
        for (final spot in spots) middleOf(bulge.regionThrough(blockAt(spot))),
      ];

      for (final (at, spot) in spots.indexed) {
        expect(
          apart(selected[at], spot),
          greaterThan(1),
          reason: '⛔premise: the bulge goes on past the box at $spot',
        );
        expect(
          apart(inkNear(carried, selected[at], reach: 6), selected[at]),
          lessThan(0.6),
          reason: 'the ink of $spot and its selection',
        );
      }
    });

    // Past the box a point is carried by the cell it is in, and a grid
    // grown by one cell carries the second cell's points by the first's —
    // so the grid is grown by ALL of the outline, as a stamp's is by all of
    // the stamp.
    test('🚨an outline reaching two cells past the box carries its far '
        'side where a block there carries it', () {
      CanvasSelectionRegion ring(List<(num, num)> points) =>
          CanvasSelectionRegion.shape(
            CanvasSelectionShape([
              for (final (x, y) in points)
                CanvasPoint(x: x.toDouble(), y: y.toDouble()),
            ]),
          );
      // The box is 100..200 and its cells are 50: on each side an outline
      // from 7 past it (the first cell) to 88 past it (the second), 6
      // across, its second point its far corner — and a block at the far
      // end whose outline starts at that corner, as the first point of a
      // carried outline is its first point carried.
      final sides = {
        'right of it': (
          outline: [(207, 137), (288, 137), (288, 143), (207, 143)],
          block: [(288, 137), (288, 143), (282, 143), (282, 137)],
        ),
        'left of it': (
          outline: [(93, 137), (12, 137), (12, 143), (93, 143)],
          block: [(12, 137), (12, 143), (18, 143), (18, 137)],
        ),
        'below': (
          outline: [(137, 207), (137, 288), (143, 288), (143, 207)],
          block: [(137, 288), (143, 288), (143, 282), (137, 282)],
        ),
        'above': (
          outline: [(137, 93), (137, 12), (143, 12), (143, 93)],
          block: [(137, 12), (143, 12), (143, 18), (137, 18)],
        ),
      };

      for (final MapEntry(key: side, value: (:outline, :block))
          in sides.entries) {
        final [carried] = ringsOf(bulge.regionThrough(ring(outline)));
        final want = ringsOf(bulge.regionThrough(ring(block))).single.first;

        expect(
          carried.map((point) => apart(point, want)).reduce(math.min),
          lessThan(1e-9),
          reason: 'the far corner of the outline $side goes where the same '
              'corner of a block there goes',
        );
      }
    });
  });

  group('nothing is resampled past the wall the carry was given', () {
    // Each of these takes the float's bottom-right out to (250, 250); the
    // wall stops at 180.
    const wall = (left: 0.0, top: 0.0, right: 180.0, bottom: 180.0);
    final corners = stampCornersOf(float())!;
    final carries = <String, StampCarry>{
      'an affine': AffineCarry(
        SelectionAffine(pivot: CanvasPoint(x: 150, y: 150), sx: 2, sy: 2),
        mode: mode,
        within: wall,
      ),
      'a quad': QuadCarry(
        base: corners,
        corners: [
          corners[0],
          corners[1],
          CanvasPoint(x: 250, y: 250),
          corners[3],
        ],
        mode: mode,
        within: wall,
      ),
      'a mesh': MeshCarry(
        (
          base: stampRectOf(float())!,
          columns: 1,
          rows: 1,
          points: [
            corners[0],
            corners[1],
            corners[3],
            CanvasPoint(x: 250, y: 250),
          ],
        ),
        mode: mode,
        within: wall,
      ),
    };
    for (final MapEntry(key: name, value: carry) in carries.entries) {
      test(name, () {
        final carried = carry.through(float());

        final stamp = carried.stamp!;
        expect(
          carried.center.x + stamp.width / 2,
          greaterThan(170),
          reason: '⛔premise: the picture reaches the wall',
        );
        expect(carried.center.x + stamp.width / 2, lessThanOrEqualTo(181));
        expect(carried.center.y + stamp.height / 2, lessThanOrEqualTo(181));
      });
    }
  });

  /// ↩️The mesh allocated its whole output rect and filled the part that
  /// was asked for — and a rect is allocated whether or not a pixel of it
  /// is written. A node pulled far away made the rect that far across.
  test('🚨a mesh node pulled far past the wall builds a buffer the size of '
      'what the wall lets in — not of how far it was pulled', () {
    final base = stampRectOf(float())!;
    final carry = MeshCarry(
      (
        base: base,
        columns: 2,
        rows: 2,
        points: [
          for (var row = 0; row <= 2; row += 1)
            for (var column = 0; column <= 2; column += 1)
              if (row == 2 && column == 2)
                CanvasPoint(x: 9000, y: 7000)
              else
                CanvasPoint(x: 100.0 + column * 50, y: 100.0 + row * 50),
        ],
      ),
      mode: mode,
      within: (left: 0, top: 0, right: 400, bottom: 300),
    );

    final carried = carry.through(float());

    final stamp = carried.stamp!;
    expect(stamp.width, lessThanOrEqualTo(301), reason: '100…400 at most');
    expect(stamp.height, lessThanOrEqualTo(201), reason: '100…300 at most');
    // …and what it does hold is the picture, where the mesh left it alone.
    expect(
      apart(
        inkNear(carried, CanvasPoint(x: 130, y: 140)),
        CanvasPoint(x: 130, y: 140),
      ),
      lessThan(1),
    );
  });
}
