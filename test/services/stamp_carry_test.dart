import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/canvas_selection.dart';
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

    test('a quad dragged whole carries every stamp by its step, byte for '
        'byte', () {
      final dragged = QuadCarry(
        base: base,
        corners: [
          for (final corner in base)
            CanvasPoint(x: corner.x + 7, y: corner.y - 3),
        ],
        mode: mode,
      );
      final other = stampOver(
        left: 10,
        top: 20,
        width: 40,
        height: 30,
        ink: [CanvasPoint(x: 30, y: 35)],
      );

      final carried = dragged.through(other);

      expect(carried.center, CanvasPoint(x: 37, y: 32));
      expect(identical(carried.stamp!.rgba, other.stamp!.rgba), isTrue);
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

    test('a grid dragged whole carries every stamp by its step, byte for '
        'byte', () {
      final dragged = meshWhere(
        (node) => CanvasPoint(x: node.x - 9, y: node.y + 4),
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
  });

  group('nothing is resampled past the wall the carry was given', () {
    // Each of these takes the float's bottom-right out to (250, 250); the
    // wall stops at 180.
    const SelectionVisibleRect wall = (
      left: 0,
      top: 0,
      right: 180,
      bottom: 180,
    );
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
