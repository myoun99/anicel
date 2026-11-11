import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/shape_tool_options.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/plain_line_region.dart';

import '../helpers/a_canvas_standing_on_a_frame.dart';
import '../helpers/a_fill_on_the_engine.dart';
import '../helpers/fill_pieces.dart';
import '../helpers/surface_rgba_in_place.dart';

void main() {
  opensTheEnginesScreens();
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// A closed box outline (2,2)..(5,5) — interior = (3..4, 3..4).
  Set<(int, int)> boxOutline() => {
    for (var x = 2; x <= 5; x += 1) ...{(x, 2), (x, 5)},
    for (var y = 3; y <= 4; y += 1) ...{(2, y), (5, y)},
  };

  /// What a fill reads of a frame of one row whose [ink] pixels — off the
  /// canvas too — are opaque black.
  FillPictureOver pictureOf(Set<(int, int)> ink) => fillPictureOfRows([
    fillRow(
      celOfPixels(canvasSize, {
        for (final at in ink) at: const [0, 0, 0, 255],
      }),
    ),
  ], canvasSize: canvasSize);

  // What the flood itself encloses — its tolerance, its growth under the
  // line, its ramp, its gaps — is the engine kernel's, pinned beside it
  // (`kernels/flood/tests.rs`). Here: what a range of it is, and how it is
  // laid.
  group('a fill range laid', () {
    test('wraps the region as COLOR STAMP pieces — a region inside one tile '
        'is one, centred on it (R15-⑥: exact bytes, no tip-mask '
        'resampling)', () {
      final dab = fillRangeAt(
        canvasSize: canvasSize,
        pictureOver: pictureOf(boxOutline()),
        point: CanvasPoint(x: 3, y: 3),
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!.dabsIn(0xFF3366CC).single;

      expect(dab.size, 2);
      expect(dab.center, CanvasPoint(x: 4, y: 4));
      expect(dab.color, 0xFF3366CC);
      expect(dab.opacity, 1);
      final stamp = dab.stamp!;
      expect((stamp.width, stamp.height), (2, 2));
      for (var index = 0; index < 4; index += 1) {
        expect(
          stamp.rgba.sublist(index * 4, index * 4 + 4),
          [0x33, 0x66, 0xCC, 255],
          reason: 'fill color at full mask coverage, byte-exact',
        );
      }
    });

    test('a seed off the canvas fills nothing, and reads no picture', () {
      expect(
        fillRangeAt(
          canvasSize: canvasSize,
          pictureOver: (_) => fail('nothing is pressed: nothing to read'),
          point: CanvasPoint(x: -1, y: 0),
        ),
        isNull,
      );
    });

    // Board `an-area-dab-costs-its-box`: every fill lands as stamp pieces
    // cut on the cel's tiles (the area's: `an_area_is_laid_where_it_reaches_
    // test.dart`).
    test('a ring\'s fill is four pieces — a whole tile empty in its middle '
        'carries nothing — and lays exactly the ring', () {
      // Two outlines: a frame round the page, and a box whose inside holds
      // the whole of tile (1, 1) — so the fill between them is a ring with
      // a hole a tile wide.
      const canvas = CanvasSize(width: 320, height: 320);
      bool isInk(int x, int y) {
        bool outline(int from, int to) =>
            (x >= from && x <= to && (y == from || y == to)) ||
            (y >= from && y <= to && (x == from || x == to));
        return outline(10, 300) || outline(120, 264);
      }

      final pieces =
          fillRangeAt(
            canvasSize: canvas,
            pictureOver: fillPictureOfRows([
              fillRow(
                celOfPixels(canvas, {
                  for (var y = 0; y < canvas.height; y += 1)
                    for (var x = 0; x < canvas.width; x += 1)
                      if (isInk(x, y)) (x, y): const [0, 0, 0, 255],
                }),
              ),
            ], canvasSize: canvas),
            point: CanvasPoint(x: 50.5, y: 50.5),
            options: const FloodFillOptions(expandPx: 0, antiAlias: false),
          )?.dabsIn(0xFF336699) ??
          const [];
      expect(pieces, hasLength(4), reason: 'rows 0 and 2 whole, row 1 split');
      for (var y = 0; y < canvas.height; y += 1) {
        for (var x = 0; x < canvas.width; x += 1) {
          final inRing =
              x > 10 &&
              x < 300 &&
              y > 10 &&
              y < 300 &&
              !(x >= 120 && x <= 264 && y >= 120 && y <= 264);
          expect(
            piecesAlphaAt(pieces, x, y),
            inRing ? 255 : 0,
            reason: '($x, $y)',
          );
        }
      }
      for (final piece in pieces) {
        final landing = piece.stamp!.landingRect(piece.center);
        expect(
          landing.left >= 256 ||
              landing.rightExclusive <= 128 ||
              landing.bottomExclusive <= 128 ||
              landing.top >= 256,
          isTrue,
          reason: 'tile (1, 1) is all hole: no piece carries it',
        );
      }
    });

    group('Fill Beyond Canvas (pasteboard)', () {
      /// A closed box from (-3,2) to (4,5): walls cross the canvas's left
      /// edge; interior = x in [-2, 3], y in [3, 4].
      Set<(int, int)> boxAcrossLeftEdge() => {
        for (var x = -3; x <= 4; x += 1) ...{(x, 2), (x, 5)},
        for (var y = 3; y <= 4; y += 1) ...{(-3, y), (4, y)},
      };

      const past = FloodFillOptions(
        expandPx: 0,
        antiAlias: false,
        extendBeyondCanvas: true,
      );

      test('a closed region crossing the canvas edge fills whole, off-canvas '
          'pixels included', () {
        final dab = fillRangeAt(
          canvasSize: canvasSize,
          pictureOver: pictureOf(boxAcrossLeftEdge()),
          point: CanvasPoint(x: 0, y: 3),
          options: past,
        )!.dabsIn(0xFF3366CC).single;

        // Interior 6×2 at world (-2, 3) → center (1, 4). It crosses the
        // cel grid at x = 0, and a run of neighbouring tiles is ONE piece.
        final stamp = dab.stamp!;
        expect((stamp.width, stamp.height), (6, 2));
        expect(dab.center, CanvasPoint(x: 1, y: 4));
        expect(dab.size, 6);
      });

      test('the same region WITHOUT the option clips at the canvas edge '
          '(default boundary unchanged)', () {
        final dab = fillRangeAt(
          canvasSize: canvasSize,
          pictureOver: pictureOf(boxAcrossLeftEdge()),
          point: CanvasPoint(x: 0, y: 3),
          options: const FloodFillOptions(expandPx: 0, antiAlias: false),
        )!.dabsIn(0xFF3366CC).single;

        // Canvas boundary is the wall: interior x in [0, 3] only.
        expect((dab.stamp!.width, dab.stamp!.height), (4, 2));
        expect(dab.center, CanvasPoint(x: 2, y: 4));
      });

      test('an OPEN region refuses to fill and reports the leak', () {
        var leaked = false;
        final dab =
            fillRangeAt(
              canvasSize: canvasSize,
              pictureOver: pictureOf(const {}),
              point: CanvasPoint(x: 3, y: 3),
              options: past,
              onOpenRegion: () => leaked = true,
            )?.dabsIn(0xFF3366CC) ??
            const [];

        expect(dab, isEmpty);
        expect(leaked, isTrue);
      });

      test('🚨I-160: an OPEN range says so when it is LAID, not when it is '
          'flooded — a press resting on it has filled nothing yet', () {
        var leaked = 0;
        final range = fillRangeAt(
          canvasSize: canvasSize,
          pictureOver: pictureOf(const {}),
          point: CanvasPoint(x: 3, y: 3),
          options: past,
          onOpenRegion: () => leaked += 1,
        )!;

        expect(range.open, isTrue);
        expect(leaked, 0, reason: 'flooded, not laid');
        expect(
          range.covers(CanvasPoint(x: 3, y: 3)),
          isTrue,
          reason: 'a press moving over it does not flood it again',
        );
        expect(
          range.coveredWithin(null),
          isNull,
          reason: 'nothing is marked where nothing fills',
        );
        expect(range.dabsIn(0xFF3366CC), isEmpty);
        expect(leaked, 1, reason: 'the lift says why nothing filled');
      });

      test('🚨I-160 「연속 채우기」: ranges joined lay as one — an open one '
          'adds nothing to lay, and is said only when every one was open', () {
        var leaked = 0;
        final open = fillRangeAt(
          canvasSize: canvasSize,
          pictureOver: pictureOf(const {}),
          point: CanvasPoint(x: 3, y: 3),
          options: past,
          onOpenRegion: () => leaked += 1,
        )!;
        FillRange square(int left) => FillRange.over(
          FloodFillRegion(
            left: left,
            top: 0,
            width: 2,
            height: 2,
            mask: Uint8List(4)..fillRange(0, 4, 255),
          ),
        );

        final both = square(0).joining(square(6));
        expect(both.covers(CanvasPoint(x: 1, y: 1)), isTrue);
        expect(both.covers(CanvasPoint(x: 7, y: 1)), isTrue);
        expect(both.covers(CanvasPoint(x: 4, y: 1)), isFalse);
        final region = both.region!;
        expect((region.left, region.width, region.height), (0, 8, 2));
        expect(
          [for (var x = 0; x < 8; x += 1) region.mask[x]],
          [255, 255, 0, 0, 0, 0, 255, 255],
          reason: 'both laid, and nothing between them',
        );

        final closed = square(0);
        final passed = closed.joining(open);
        expect(
          identical(passed.region, closed.region),
          isTrue,
          reason: 'an open region adds nothing to lay',
        );
        expect(
          passed.covers(CanvasPoint(x: 3, y: 3)),
          isTrue,
          reason: 'but a press passing over it does not flood it again',
        );
        expect(passed.dabsIn(0xFF3366CC), isNotEmpty);
        expect(leaked, 0, reason: 'something filled: nothing to say');

        expect(open.joining(open).dabsIn(0xFF3366CC), isEmpty);
        expect(leaked, 1, reason: 'every region open: said once');
      });

      test('the same open tap WITHOUT the option floods to the canvas wall '
          'as before', () {
        final dab = fillRangeAt(
          canvasSize: canvasSize,
          pictureOver: pictureOf(const {}),
          point: CanvasPoint(x: 3, y: 3),
          options: const FloodFillOptions(expandPx: 0, antiAlias: false),
        )!.dabsIn(0xFF3366CC).single;

        expect((dab.stamp!.width, dab.stamp!.height), (8, 8));
      });

      /// 🚨I-109: the apron is as wide as the pasteboard in use — at 1.5x
      /// the 8 × 8 canvas's wall stands 2 past each edge, x in [-2, 10).
      group('at the pasteboard\'s size', () {
        List<BrushDab> fill(
          Set<(int, int)> ink, {
          required CanvasPoint at,
          required PasteboardReach reach,
          void Function()? onOpenRegion,
        }) =>
            fillRangeAt(
              canvasSize: canvasSize,
              pictureOver: pictureOf(ink),
              point: at,
              options: past,
              onOpenRegion: onOpenRegion,
              pasteboardReach: reach,
            )?.dabsIn(0xFF3366CC) ??
            const [];

        test('a box whose wall stands past the pasteboard\'s is open', () {
          var leaked = false;
          final dabs = fill(
            boxAcrossLeftEdge(),
            at: CanvasPoint(x: 0, y: 3),
            reach: PasteboardReach.quarter,
            onOpenRegion: () => leaked = true,
          );
          expect(dabs, isEmpty);
          expect(leaked, isTrue);
        });

        test('a box closed inside it fills, off-canvas pixels included', () {
          final dab = fill(
            {
              for (var x = -2; x <= 4; x += 1) ...{(x, 2), (x, 5)},
              for (var y = 3; y <= 4; y += 1) ...{(-2, y), (4, y)},
            },
            at: CanvasPoint(x: 0, y: 3),
            reach: PasteboardReach.quarter,
          ).single;
          expect((dab.stamp!.width, dab.stamp!.height), (5, 2));
          expect(dab.center, CanvasPoint(x: 1.5, y: 4));
        });

        test('off, the fill beyond the canvas is the fill inside it', () {
          var leaked = false;
          final dab = fill(
            const {},
            at: CanvasPoint(x: 3, y: 3),
            reach: PasteboardReach.none,
            onOpenRegion: () => leaked = true,
          ).single;
          expect((dab.stamp!.width, dab.stamp!.height), (8, 8));
          expect(leaked, isFalse);
        });
      });
    });

    test(
      'committed through the stroke funnel the mask lands 1:1 unattenuated',
      () {
        // The parity pin: hardness=1, opacity/flow=1 and dab size = mask
        // size must reproduce the region EXACTLY on the committed surface —
        // no falloff, no resampling drift.
        final dabs =
            fillRangeAt(
              canvasSize: canvasSize,
              pictureOver: pictureOf(boxOutline()),
              point: CanvasPoint(x: 3, y: 3),
              options: const FloodFillOptions(expandPx: 0, antiAlias: false),
            )?.dabsIn(0xFF3366CC) ??
            const [];

        final coordinator = BrushFrameEditingCoordinator(
          initialFrameKey: const BrushFrameKey(
            projectId: ProjectId('project'),
            trackId: TrackId('track'),
            cutId: CutId('cut'),
            layerId: LayerId('fill'),
            frameId: FrameId('fill-frame'),
          ),
          frameStore: BrushFrameStore(),
          sessionStore: BrushFrameEditSessionStore(
            canvasSize: canvasSize,
            tileSize: 4,
          ),
          historyPolicy: const BrushHistoryPolicy(),
        );
        coordinator.commitSourceStroke(sourceDabs: dabs);

        final committed = coordinator.frameStore.bakedSurfaceOrNull(
          coordinator.activeFrameKey,
        )!;

        for (var y = 0; y < 8; y += 1) {
          for (var x = 0; x < 8; x += 1) {
            final inside = x >= 3 && x <= 4 && y >= 3 && y <= 4;
            expect(
              surfaceRgbaInPlace(committed, x, y),
              inside ? 0x3366CCFF : 0,
              reason: 'pixel ($x, $y)',
            );
          }
        }
      },
    );
  });

  // What the shape tool lays without the brush (I-69): its fill is one
  // outline — the group below — and its plain line an area of many pieces
  // with a hole in the middle.
  group('buildRegionFillDabs', () {
    // A rectangle (10,10)–(40,30) drawn six wide: the band runs three
    // either side of the trace.
    CanvasSelectionRegion ring() => plainLineRegion(
      points: [
        CanvasPoint(x: 10, y: 10),
        CanvasPoint(x: 40, y: 10),
        CanvasPoint(x: 40, y: 30),
        CanvasPoint(x: 10, y: 30),
      ],
      closed: true,
      width: 6,
      corners: ShapeCorners.sharp,
    )!;

    test('an area of many pieces is laid as ONE: whole across where they '
        'meet, and its hole stays a hole', () {
      final dabs = buildRegionFillDabs(
        region: ring(),
        color: 0xFF3366CC,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      );

      // Along the top band, from the corner piece on one side across both
      // ends of the side's own box to the corner piece on the other.
      for (var x = 7; x <= 42; x += 1) {
        expect(piecesAlphaAt(dabs, x, 7), 255, reason: 'the outer row at $x');
        expect(piecesAlphaAt(dabs, x, 12), 255, reason: 'the inner row at $x');
      }
      expect(piecesAlphaAt(dabs, 6, 10), 0, reason: 'three wide and no more');
      expect(piecesAlphaAt(dabs, 25, 13), 0, reason: 'the hole begins');
      expect(piecesAlphaAt(dabs, 25, 20), 0, reason: 'the hole');
      expect({for (final piece in dabs) piece.color}, {0xFF3366CC});
    });

    test('the edge is softened once, round the whole area — a join inside '
        'it is not an edge', () {
      final dabs = buildRegionFillDabs(
        region: ring(),
        color: 0xFF000000,
        options: const FloodFillOptions(expandPx: 0, antiAlias: true),
      );

      for (var x = 8; x <= 41; x += 1) {
        expect(piecesAlphaAt(dabs, x, 9), 255, reason: 'in the band at $x');
        expect(piecesAlphaAt(dabs, x, 10), 255, reason: 'in the band at $x');
      }
      expect(
        piecesAlphaAt(dabs, 25, 7),
        inExclusiveRange(0, 255),
        reason: 'an edge',
      );
      expect(piecesAlphaAt(dabs, 25, 12), inExclusiveRange(0, 255));
    });

    test('an area that covers no pixel lays nothing', () {
      // A sliver between two rows of pixel centres.
      final dabs = buildRegionFillDabs(
        region: CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: 0, top: 0.6, right: 10, bottom: 1.4),
        ),
        color: 0xFF000000,
      );
      expect(dabs, isEmpty);
    });
  });

  /// A shape fill: one outline, filled as the fill tool lays it.
  List<BrushDab> shapeFill({
    required CanvasSelectionShape shape,
    required int color,
    double opacity = 1.0,
    FloodFillOptions options = const FloodFillOptions(),
  }) => buildRegionFillDabs(
    region: CanvasSelectionRegion.shape(shape),
    color: color,
    opacity: opacity,
    options: options,
  );

  group('a shape fill', () {
    test('fills the outline with the colour, corners and all', () {
      // 유저 확정: 올가미 채우기는 A — 내부에 뭐가 있든 채운다. There is no
      // picture in this test at all, which is the point: a shape fill has
      // no seed, no tolerance and nothing to read.
      final dabs = shapeFill(
        shape: CanvasSelectionShape.rect(
          left: 10,
          top: 10,
          right: 40,
          bottom: 30,
        ),
        color: 0xFF3366CC,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      );
      expect(piecesAlphaAt(dabs, 25, 20), 255, reason: 'the middle');
      expect(
        piecesAlphaAt(dabs, 11, 11),
        255,
        reason: 'a corner is inside a box',
      );
      expect(piecesAlphaAt(dabs, 5, 20), 0, reason: 'outside stays out');
      final stamp = dabs.single.stamp!;
      expect(stamp.rgba[3 * 4 + 0], anyOf(0, 0x33));
      expect({for (final piece in dabs) piece.color}, {0xFF3366CC});
    });

    // TP1: 유저 — "필 툴도 불투명도 설정하면 그거대로 채워지게".
    test('the fill carries an opacity, and defaults to full', () {
      // The coverage MASK is untouched by opacity — a half-opaque fill is
      // still the same shape. What carries it is the dab, because the
      // stroke funnel multiplies a stamp dab by `BrushDab.opacity`; that
      // multiply is why the cut stamp had to hard-code 1 before every tool
      // had a field of its own.
      final shape = CanvasSelectionShape.rect(
        left: 0,
        top: 0,
        right: 10,
        bottom: 10,
      );
      const options = FloodFillOptions(expandPx: 0, antiAlias: false);
      final full = shapeFill(
        shape: shape,
        color: 0xFF000000,
        options: options,
      );
      expect({for (final piece in full) piece.opacity}, {1.0},
          reason: 'unasked is unchanged');

      final half = shapeFill(
        shape: shape,
        color: 0xFF000000,
        opacity: 0.5,
        options: options,
      );
      expect({for (final piece in half) piece.opacity}, {0.5});
      expect(
        piecesAlphaAt(half, 5, 5),
        piecesAlphaAt(full, 5, 5),
        reason: 'the mask is the shape, not the strength',
      );
    });

    test('the ellipse loses the box corners it was drawn in', () {
      final dabs = shapeFill(
        shape: CanvasSelectionShape.ellipse(
          left: 0,
          top: 0,
          right: 60,
          bottom: 60,
        ),
        color: 0xFF000000,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      );
      expect(piecesAlphaAt(dabs, 30, 30), 255);
      expect(piecesAlphaAt(dabs, 2, 2), 0);
    });

    test('an outline enclosing nothing fills nothing', () {
      // Three collinear points have no area — the same rule that makes a
      // lasso dragged in a straight line cut nothing.
      final dabs = shapeFill(
        shape: CanvasSelectionShape([
          CanvasPoint(x: 0, y: 0),
          CanvasPoint(x: 10, y: 0),
          CanvasPoint(x: 20, y: 0),
        ]),
        color: 0xFF000000,
      );
      expect(dabs, isEmpty);
    });

    test('anti-alias softens the edge and leaves the inside alone', () {
      // 유저 확정 ②: AA follows the fill, on by default. It is the SAME
      // post-pass the flood uses — that is why it needed no rasterizer.
      final shape = CanvasSelectionShape.rect(
        left: 10,
        top: 10,
        right: 40,
        bottom: 30,
      );
      final hard = shapeFill(
        shape: shape,
        color: 0xFF000000,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      );
      final soft = shapeFill(
        shape: shape,
        color: 0xFF000000,
        options: const FloodFillOptions(expandPx: 0, antiAlias: true),
      );
      expect(piecesAlphaAt(hard, 10, 20), 255);
      expect(piecesAlphaAt(soft, 10, 20), lessThan(255));
      expect(piecesAlphaAt(soft, 10, 20), greaterThan(0));
      expect(piecesAlphaAt(soft, 25, 20), 255, reason: 'only the edge softens');
    });
  });
}
