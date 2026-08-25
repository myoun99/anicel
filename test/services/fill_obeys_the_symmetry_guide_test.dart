import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';

/// **A symmetry guide replicates FILLS, not just strokes.**
///
/// The guide feature shipped with strokes covered and its last two holes
/// written down: fill and selection. This is the fill half.
///
/// 🚨The mechanism is the whole point of the test. A fill lands as ONE
/// `stamp` dab — an RGBA image — and the stamp blend ignores angle, so
/// replicating the finished dab the way the stroke path replicates its dabs
/// would paste an *un-mirrored* copy of the left region onto the right. The
/// only thing that draws the right side's own shape is flooding the right
/// side, from the reflected SEED.
///
/// The fixture makes those two outcomes visibly different: the two boxes
/// below are mirror images in POSITION but the right one is not the left
/// one translated — the union's rectangle is the assertion.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 8);
  const tile = 4;

  /// A closed box outline, interior = the 2×2 inside it.
  Set<(int, int)> boxAt(int left) => {
    for (var x = left; x <= left + 3; x += 1) ...{(x, 2), (x, 5)},
    for (var y = 3; y <= 4; y += 1) ...{(left, y), (left + 3, y)},
  };

  /// Two boxes mirrored about x = 8: interiors (3..4, 3..4) and
  /// (11..12, 3..4).
  BitmapSurface twoBoxes() {
    final buffers = <TileCoord, Uint8List>{};
    for (final (x, y) in {...boxAt(2), ...boxAt(10)}) {
      final coord = TileCoord(x: x ~/ tile, y: y ~/ tile);
      final buffer = buffers.putIfAbsent(
        coord,
        () => Uint8List(tile * tile * 4),
      );
      buffer[((y % tile) * tile + (x % tile)) * 4 + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tile,
      tiles: {
        for (final entry in buffers.entries)
          entry.key: BitmapTile(
            coord: entry.key,
            size: tile,
            pixels: entry.value,
          ),
      },
    );
  }

  Cut cutWithInk() => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: [
      Layer(
        id: const LayerId('ink'),
        name: 'Ink',
        frames: [
          Frame(
            id: const FrameId('ink-frame'),
            duration: 1,
            strokes: const [],
          ),
        ],
        timeline: {
          0: TimelineExposure.drawing(const FrameId('ink-frame'), length: 1),
        },
      ),
    ],
    duration: 24,
    canvasSize: canvasSize,
  );

  /// A plain left/right mirror down the middle of the canvas.
  SymmetryShape mirrorDownTheMiddle() => SymmetryShape(
    axis: GuideAxis(origin: CanvasPoint(x: 8, y: 4), angleDegrees: 90),
    lineCount: 2,
  );

  /// The seed sits at a pixel CENTRE so its reflection lands on one too —
  /// 3.5 mirrors to 12.5, and both floor into a box interior.
  final seed = CanvasPoint(x: 3.5, y: 3.5);

  const exact = FloodFillOptions(expandPx: 0, antiAlias: false);

  test('fixture premise: without a guide the tap fills only its own box', () {
    final surface = twoBoxes();
    final dab = buildFillDab(
      cut: cutWithInk(),
      frameIndex: 0,
      surfaceResolver: (_, _) => surface,
      point: seed,
      color: 0xFF3366CC,
      options: exact,
    )!;

    expect((dab.stamp!.width, dab.stamp!.height), (2, 2));
    expect(dab.center, CanvasPoint(x: 4, y: 4));
  });

  test('under a mirror the tap fills the mirrored box too, as ONE dab', () {
    final surface = twoBoxes();
    final dab = buildFillDab(
      cut: cutWithInk(),
      frameIndex: 0,
      surfaceResolver: (_, _) => surface,
      point: seed,
      color: 0xFF3366CC,
      options: exact,
      symmetry: mirrorDownTheMiddle(),
    )!;

    final stamp = dab.stamp!;
    expect(
      (stamp.width, stamp.height),
      (10, 2),
      reason: 'x 3..12 — the two interiors and the gap between them, which '
          'is a rectangle a replicated 2×2 dab can never produce',
    );
    expect(dab.center, CanvasPoint(x: 8, y: 4));

    // Coverage: both interiors painted, the ink and the gap untouched.
    int alphaAt(int x, int y) => stamp.rgba[((y - 3) * 10 + (x - 3)) * 4 + 3];
    for (final (x, y) in <(int, int)>[
      (3, 3), (4, 3), (3, 4), (4, 4), // the seed's box
      (11, 3), (12, 3), (11, 4), (12, 4), // the mirror's box
    ]) {
      expect(alphaAt(x, y), 255, reason: 'filled at ($x, $y)');
    }
    for (final (x, y) in <(int, int)>[
      (5, 3), (7, 3), (8, 4), (10, 4), // outline and the space between
    ]) {
      expect(alphaAt(x, y), 0, reason: 'not filled at ($x, $y)');
    }
  });

  test('the mirrored copy carries the same colour, at full coverage', () {
    final surface = twoBoxes();
    final stamp = buildFillDab(
      cut: cutWithInk(),
      frameIndex: 0,
      surfaceResolver: (_, _) => surface,
      point: seed,
      color: 0xFF3366CC,
      options: exact,
      symmetry: mirrorDownTheMiddle(),
    )!.stamp!;

    final at = ((3 - 3) * 10 + (11 - 3)) * 4;
    expect(stamp.rgba.sublist(at, at + 4), [0x33, 0x66, 0xCC, 255]);
  });

  test('an OPEN copy is refused alone — it does not veto the seed side', () {
    // Judged per copy. An extended fill refuses a region that reaches the
    // apron wall; reflecting the seed about x = 2 puts one copy at x = 0.5,
    // out in the open surround. That copy is dropped and the seed's own
    // box still fills — the alternative, one bad mirror killing the tap,
    // would make the guide's own copies veto the stroke the user aimed.
    final surface = twoBoxes();
    var openReported = false;
    final dab = buildFillDab(
      cut: cutWithInk(),
      frameIndex: 0,
      surfaceResolver: (_, _) => surface,
      point: seed,
      color: 0xFF3366CC,
      options: const FloodFillOptions(
        expandPx: 0,
        antiAlias: false,
        extendBeyondCanvas: true,
      ),
      symmetry: SymmetryShape(
        axis: GuideAxis(origin: CanvasPoint(x: 2, y: 4), angleDegrees: 90),
        lineCount: 2,
      ),
      onOpenRegion: () => openReported = true,
    );

    expect(dab, isNotNull);
    expect(
      (dab!.stamp!.width, dab.stamp!.height),
      (2, 2),
      reason: 'only the enclosed copy survives',
    );
    expect(
      openReported,
      isFalse,
      reason: 'something did fill, so there is no leak to report',
    );
  });

  test('and when EVERY copy is open, the leak is reported once', () {
    final surface = twoBoxes();
    var reports = 0;
    final dab = buildFillDab(
      cut: cutWithInk(),
      frameIndex: 0,
      surfaceResolver: (_, _) => surface,
      // Out in the surround, which the apron leaves unbounded.
      point: CanvasPoint(x: 0.5, y: 0.5),
      color: 0xFF3366CC,
      options: const FloodFillOptions(
        expandPx: 0,
        antiAlias: false,
        extendBeyondCanvas: true,
      ),
      symmetry: mirrorDownTheMiddle(),
      onOpenRegion: () => reports += 1,
    );

    expect(dab, isNull);
    expect(reports, 1, reason: 'one tap, one notice — not one per copy');
  });
}
