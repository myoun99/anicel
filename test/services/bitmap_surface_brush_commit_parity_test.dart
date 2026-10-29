import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/separable_blend_mode.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_pixel_blend_operation.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_texture_mode.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_tile_set.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/bitmap_tile_operation_materialization.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_dab_kernel.dart' show NativeDabBatcher;
import 'package:anicel/src/services/brush_dab_sequence_blend.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';

import '../helpers/native_engine_path.dart';

/// Reference implementation of the stroke-commit rasterization, built from the
/// retained per-pixel-operation pipeline (`brushPixelBlendOperationsForDabSequence`
/// + `materializedBitmapTileForOperations`). This mirrors the pre-optimization
/// commit path and acts as the oracle for the fast scratch-buffer path in
/// `materializeBrushDabSequenceOnBitmapSurface`.
BrushSurfaceMaterialization referenceMaterialize({
  required BitmapSurface surface,
  required BrushDabSequence sequence,
}) {
  final transparent = RgbaColor(r: 0, g: 0, b: 0, a: 0);
  // The oracle clips at the PASTEBOARD, exactly like the fast path —
  // painting past the canvas edge is in-bounds now.
  final wall = surface.canvasSize.pasteboardAt(PasteboardReach.whole);

  RgbaColor destinationAt(int x, int y) {
    if (!wall.containsPixel(x: x, y: y)) {
      return transparent;
    }

    final tileX = floorDiv(x, surface.tileSize);
    final tileY = floorDiv(y, surface.tileSize);
    final tile = surface.tileAt(TileCoord(x: tileX, y: tileY));
    if (tile == null) return transparent;

    return readRgbaColorFromBitmapTile(
      tile: tile,
      x: x - tileX * surface.tileSize,
      y: y - tileY * surface.tileSize,
    );
  }

  final operations = brushPixelBlendOperationsForDabSequence(
    sequence: sequence,
    destinationAt: destinationAt,
  );

  final operationsByCoord = <TileCoord, List<BrushPixelBlendOperation>>{};
  for (final operation in operations) {
    if (!wall.containsPixel(x: operation.x, y: operation.y)) {
      continue;
    }

    final coord = TileCoord(
      x: floorDiv(operation.x, surface.tileSize),
      y: floorDiv(operation.y, surface.tileSize),
    );
    operationsByCoord.putIfAbsent(coord, () => []).add(operation);
  }

  var updatedSurface = surface;
  var dirtyTiles = DirtyTileSet.empty();
  final coords = operationsByCoord.keys.toList()
    ..sort((a, b) {
      final yComparison = a.y.compareTo(b.y);
      if (yComparison != 0) return yComparison;
      return a.x.compareTo(b.x);
    });
  for (final coord in coords) {
    final existingTile = surface.tileAt(coord);
    final tile =
        existingTile ?? BitmapTile.blank(size: surface.tileSize);
    final updatedTile = materializedBitmapTileForOperations(
      coord: coord,
      tile: tile,
      operations: operationsByCoord[coord]!,
    );
    if (updatedTile == null) continue;
    updatedSurface = updatedSurface.putTiles([
      (coord: coord, tile: updatedTile),
    ]);
    dirtyTiles = dirtyTiles.addAll([coord]);
  }

  return BrushSurfaceMaterialization(
    surface: updatedSurface,
    dirtyTiles: dirtyTiles,
  );
}

BrushDab dab({
  required double x,
  required double y,
  double size = 12,
  int color = 0xFF336699,
  double opacity = 0.8,
  double flow = 0.7,
  double hardness = 0.5,
  BrushTipShape tipShape = BrushTipShape.round,
  int sequence = 0,
  double roundness = 1.0,
  double angleDegrees = 0.0,
  BrushTipMask? tipMask,
  BrushDualView? dual,
  bool second = false,
  BrushTipMask? textureMask,
  double textureScale = 1.0,
  double textureDensity = 1.0,
  BrushTextureMode textureMode = BrushTextureMode.multiply,
  BrushAntiAlias antiAlias = BrushAntiAlias.high,
}) {
  return BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: color,
    size: size,
    opacity: opacity,
    flow: flow,
    hardness: hardness,
    tipShape: tipShape,
    pressure: 1.0,
    sequence: sequence,
    antiAlias: antiAlias,
    roundness: roundness,
    angleDegrees: angleDegrees,
    tipMask: tipMask,
    dual: dual,
    second: second,
    textureMask: textureMask,
    textureScale: textureScale,
    textureDensity: textureDensity,
    textureMode: textureMode,
  );
}

/// A dab of a stroke's second tip as `BrushSecondStroke` lays it: black,
/// opacity and flow 1, piled on the second plane under [dual].
BrushDab secondDab({
  required double x,
  required double y,
  required BrushDualView dual,
  double size = 12,
  double hardness = 0.5,
  double flow = 1.0,
  int sequence = 0,
  BrushTipMask? tipMask,
}) => dab(
  x: x,
  y: y,
  size: size,
  color: 0xFF000000,
  opacity: 1.0,
  flow: flow,
  hardness: hardness,
  sequence: sequence,
  tipMask: tipMask,
  dual: dual,
  second: true,
);

/// Deterministic 8x8 gradient-with-holes mask for parity scenarios.
final BrushTipMask _testTipMask = BrushTipMask(
  id: 'parity-test-tip',
  size: 8,
  alpha: Uint8List.fromList([
    for (var index = 0; index < 64; index += 1)
      if (index % 7 == 0) 0 else ((index * 4 + 16) % 256),
  ]),
);

/// An 8x8 mask inked in its top half only: a dab of it leaves its lower rows
/// untouched.
final BrushTipMask _upperHalfTipMask = BrushTipMask(
  id: 'parity-test-upper-half',
  size: 8,
  alpha: Uint8List.fromList([
    for (var index = 0; index < 64; index += 1) if (index < 32) 220 else 0,
  ]),
);

BrushDabSequence strokeOf(List<BrushDab> dabs) => BrushDabSequence(dabs);

/// 🚨★★★THE THREE TRANSCRIPTIONS ARE COMPARED IN ONE RUN, NOT ONE PER MACHINE.
///
/// The fast path picks the C kernel when the engine loads and the Dart kernel
/// (`blendDabTilesDart`) when it does not, so a single call has only ever
/// compared TWO of the three. That left the Dart kernel unpinned on a machine
/// with the engine built and the C kernel unpinned on one without — and with
/// origin frozen there is no second machine to cover the other half.
///
/// 🧪Measured 2026-09-09: dropping the density term from the dual blend in
/// `brush_dab_kernel.dart` ALONE — the C and the reference left correct —
/// passed this entire suite, and the overlay parity suite too. It fails on
/// `(Dart kernel)` now.
///
/// ⚠️The C route asserts the engine actually LOADED. A path that exists but
/// fails to load would quietly run the Dart kernel twice, and two identical
/// routes agreeing is the shape of a green that measures nothing.
typedef _FastRoute = ({String name, bool forceDart});

const _FastRoute _dartKernelRoute = (name: 'Dart kernel', forceDart: true);
const _FastRoute _cKernelRoute = (name: 'C kernel', forceDart: false);

final List<_FastRoute> _fastRoutes = _resolveFastRoutes();

List<_FastRoute> _resolveFastRoutes() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  if (libraryPath == null) {
    return const [_dartKernelRoute];
  }
  debugQaEngineLibraryPathOverride = libraryPath;
  return const [_dartKernelRoute, _cKernelRoute];
}

void expectParity({
  required BitmapSurface surface,
  required BrushDabSequence sequence,
  required String reason,
}) {
  final reference = referenceMaterialize(surface: surface, sequence: sequence);
  for (final route in _fastRoutes) {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = route.forceDart;
    if (!route.forceDart) {
      expect(
        QaNativeEngine.instance,
        isNotNull,
        reason: 'the C route must really be the C kernel',
      );
    }
    final fast = materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: sequence,
    );
    expect(
      fast.dirtyTiles,
      reference.dirtyTiles,
      reason: '$reason: dirtyTiles (${route.name})',
    );
    expect(
      fast.surface,
      reference.surface,
      reason: '$reason: surface pixels (${route.name})',
    );
  }
  QaNativeEngine.debugResetForTests();
  QaNativeEngine.debugForceDartFallback = false;
}

void main() {
  const canvasSize = CanvasSize(width: 200, height: 160);

  BitmapSurface blankSurface({int tileSize = 64}) {
    return BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
  }

  group('materializeBrushDabSequenceOnBitmapSurface parity with reference', () {
    test('🚨the routes this machine actually compares', () {
      // Every case below is only as wide as this list. A suite that quietly
      // dropped to one route would still be green, so the count is stated
      // here where a reader sees it — and CI, which sets QA_REQUIRE_NATIVE,
      // FAILS instead of narrowing.
      expect(_fastRoutes, contains(_dartKernelRoute));
      if (_fastRoutes.contains(_cKernelRoute)) {
        return;
      }
      if (nativeEngineRequired) {
        fail(nativeEngineMissingSkipReason);
      }
      markTestSkipped(nativeEngineMissingSkipReason);
    });

    test('single soft round dab on blank surface', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([dab(x: 40, y: 40)]),
        reason: 'single dab',
      );
    });

    test('overlapping stroke with partial opacity and flow', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          for (var i = 0; i < 12; i += 1)
            dab(x: 30.0 + i * 3.0, y: 30.0 + i * 2.0, sequence: i),
        ]),
        reason: 'overlapping stroke',
      );
    });

    test('dabs overhanging canvas corners paint the pasteboard identically', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 0, y: 0, size: 20, sequence: 0),
          dab(x: 199.5, y: 159.5, size: 20, sequence: 1),
          dab(x: -3, y: 80, size: 16, sequence: 2),
        ]),
        reason: 'pasteboard edge painting',
      );
    });

    test('dabs overhanging the pasteboard edge are clipped identically', () {
      // blankSurface is 200×160 → pasteboard x ∈ [-200, 400).
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: -198, y: 40, size: 20, sequence: 0),
          dab(x: 398, y: 120, size: 20, sequence: 1),
          dab(x: 40, y: -158, size: 20, sequence: 2),
        ]),
        reason: 'pasteboard edge clipping',
      );
    });

    test('square tip stroke', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 50, y: 50, tipShape: BrushTipShape.square, sequence: 0),
          dab(x: 55, y: 53, tipShape: BrushTipShape.square, sequence: 1),
        ]),
        reason: 'square tip',
      );
    });

    test('hardness extremes 0.0 and 1.0', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 40, y: 40, hardness: 0.0, sequence: 0),
          dab(x: 80, y: 40, hardness: 1.0, sequence: 1),
        ]),
        reason: 'hardness extremes',
      );
    });

    test('🚨every EDGE step agrees across all three transcriptions', () {
      // The edge remap had to be written into all three transcriptions at the
      // same point in the cascade, and this is the pin that says it was — one
      // dab per step, so a step written into only one of them fails here with
      // the step named. `expectParity` walks every route, so all three are
      // compared in this one run.
      //
      // 🧪Measured 2026-09-08: `+ 0.5` -> `+ 0.6` in the C kernel alone,
      // rebuilt, and this went red on `edge step low` — so the C really is
      // what the C route runs.
      //
      // I-50: the hard nib and the near-hard ellipse are the tips whose edge
      // the step WIDENS (the step pulls the hard radius in); the soft two
      // keep their own ramp.
      for (final step in BrushAntiAlias.values) {
        expectParity(
          surface: blankSurface(),
          sequence: strokeOf([
            dab(x: 40, y: 40, hardness: 0.0, antiAlias: step),
            dab(x: 80, y: 40, hardness: 0.6, antiAlias: step, sequence: 1),
            dab(x: 120, y: 40, hardness: 1.0, antiAlias: step, sequence: 2),
            dab(
              x: 160.3,
              y: 40.6,
              size: 17,
              hardness: 0.95,
              roundness: 0.55,
              angleDegrees: 30,
              antiAlias: step,
              sequence: 3,
            ),
          ]),
          reason: 'edge step ${step.name}',
        );
      }
    });

    test('🚨a small circle\'s SQUARE read agrees across all three '
        'transcriptions', () {
      // Up to a radius of 2.5 a circle's tables are square (Q6 b,
      // `RoundTipProfile.rowLength`): each size at a spread of sub-pixel
      // phases, hard and soft, alone and overlapping — so what piles is read
      // off the square pile table too — and a 6px dab beside them, read
      // along its radius.
      for (final step in BrushAntiAlias.values) {
        expectParity(
          surface: blankSurface(),
          sequence: strokeOf([
            for (final (i, size) in [0.7, 1.0, 1.5, 2.0, 3.0, 5.0].indexed)
              for (final (k, phase) in [0.0, 0.23, 0.5, 0.81].indexed)
                dab(
                  x: 12.0 + i * 24 + k * 5 + phase,
                  y: 20.0 + k * 9 + phase * 0.7,
                  size: size,
                  hardness: k.isEven ? 1.0 : 0.5,
                  antiAlias: step,
                  sequence: i * 4 + k,
                ),
            for (var k = 0; k < 6; k += 1)
              dab(
                x: 30.0 + k * 0.37,
                y: 90.31,
                size: 1.5,
                antiAlias: step,
                sequence: 24 + k,
              ),
            dab(x: 160.4, y: 120.7, size: 6, antiAlias: step, sequence: 30),
          ]),
          reason: 'square read, edge step ${step.name}',
        );
      }
    });

    test('full opacity and flow overwrite path', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 60, y: 60, opacity: 1.0, flow: 1.0, hardness: 1.0),
        ]),
        reason: 'opaque dab',
      );
    });

    test('stroke crossing tile boundaries', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          for (var i = 0; i < 10; i += 1)
            dab(x: 50.0 + i * 12.0, y: 60.0 + i * 6.0, size: 18, sequence: i),
        ]),
        reason: 'multi-tile stroke',
      );
    });

    test('second stroke over an already painted surface', () {
      final firstStroke = strokeOf([
        for (var i = 0; i < 8; i += 1)
          dab(x: 40.0 + i * 6.0, y: 50.0, sequence: i),
      ]);
      final painted = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(),
        sequence: firstStroke,
      ).surface;

      expectParity(
        surface: painted,
        sequence: strokeOf([
          for (var i = 0; i < 8; i += 1)
            dab(
              x: 44.0 + i * 6.0,
              y: 52.0,
              color: 0xCC994411,
              opacity: 0.5,
              sequence: i,
            ),
        ]),
        reason: 'paint over painted',
      );
    });

    test('non-effective dabs produce no changes in either path', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 40, y: 40, opacity: 0.0, sequence: 0),
          dab(x: 50, y: 40, flow: 0.0, sequence: 1),
          dab(x: 60, y: 40, color: 0x00FFFFFF, sequence: 2),
          dab(x: 70, y: 40, size: 0, sequence: 3),
        ]),
        reason: 'non-effective dabs',
      );
    });

    test('elliptical soft tip stroke on fractional centers', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          for (var i = 0; i < 6; i += 1)
            dab(
              x: 40.37 + i * 7.13,
              y: 44.81 + i * 3.41,
              size: 18,
              roundness: 0.4,
              angleDegrees: 30,
              sequence: i,
            ),
        ]),
        reason: 'elliptical soft tip',
      );
    });

    test('hard elliptical tip and thin roundness extremes', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(
            x: 60.5,
            y: 60.5,
            size: 24,
            hardness: 1.0,
            roundness: 0.05,
            angleDegrees: 137.0,
            sequence: 0,
          ),
          dab(
            x: 100.2,
            y: 70.7,
            size: 24,
            hardness: 0.0,
            roundness: 0.6,
            angleDegrees: 90.0,
            sequence: 1,
          ),
        ]),
        reason: 'elliptical extremes',
      );
    });

    // ⛔The rotated-rectangle parity case went with the path it pinned. A
    // square dab is the fill and stamp verbs' "cover exactly this rect" and
    // `BrushDab` now refuses to build one that is squashed or rotated, so
    // the case could no longer be constructed — the pin for that law is
    // `a square dab cannot be rotated or squashed` in the dab tests.

    test('sampled tip stroke on fractional centers', () {
      expect(_testTipMask.alpha.any((value) => value > 0), isTrue);
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          for (var i = 0; i < 5; i += 1)
            dab(
              x: 40.37 + i * 6.13,
              y: 44.81 + i * 3.41,
              size: 18,
              tipMask: _testTipMask,
              sequence: i,
            ),
        ]),
        reason: 'sampled tip',
      );
    });

    test('sampled tip rotated, squashed, and crossing tiles', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          for (var i = 0; i < 6; i += 1)
            dab(
              x: 50.0 + i * 12.0,
              y: 58.0 + i * 5.0,
              size: 22,
              roundness: 0.5,
              angleDegrees: 30,
              tipMask: _testTipMask,
              sequence: i,
            ),
        ]),
        reason: 'sampled tip rotated across tiles',
      );
    });

    test('🚨a dual stroke at PARTIAL density agrees across all three', () {
      // ⚠️Density 1 is where the lerp collapses: every transcription would
      // still agree if one of them had dropped the density term entirely.
      // Only a value that is neither 0 nor 1 makes the three compare.
      const view = BrushDualView(density: 0.35);
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 40.4, y: 40.6, size: 18, dual: view, sequence: 0),
          // ...with a texture under one of them, so the paper's blend runs
          // in the first tip's coverage and the view after it.
          dab(
            x: 52.2,
            y: 44.8,
            size: 18,
            dual: view,
            textureMask: _testTipMask,
            textureScale: 1.3,
            textureDensity: 0.4,
            sequence: 1,
          ),
          secondDab(x: 43.1, y: 41.9, dual: view, tipMask: _testTipMask),
          secondDab(x: 49.7, y: 43.2, dual: view, size: 9, flow: 0.6),
        ]),
        reason: 'the dual density blend must be one law in all three',
      );
    });

    test('🚨a dual stroke shows the same bytes in any order of its dabs', () {
      // THE SECOND TIP IS A STROKE OF ITS OWN: the view is a function of the
      // two planes, and each plane piles its own dabs — so where the second
      // tip's dabs fall among the first's changes nothing. ⛔A per-dab dual
      // (the second tip's pattern laid under every first-tip dab) fails
      // this: the first dab's mark would be cut by the pattern it found.
      const view = BrushDualView(density: 0.8);
      final firsts = [
        for (var i = 0; i < 5; i += 1)
          dab(x: 36.0 + i * 4.0, y: 40.0 + i * 2.0, size: 16, dual: view),
      ];
      final seconds = [
        for (var i = 0; i < 4; i += 1)
          secondDab(
            x: 38.5 + i * 5.0,
            y: 41.0 + i * 2.5,
            dual: view,
            size: 10,
            tipMask: _testTipMask,
          ),
      ];
      final orders = {
        'first tip, then second': [...firsts, ...seconds],
        'second tip, then first': [...seconds, ...firsts],
        'interleaved': [
          for (var i = 0; i < firsts.length; i += 1) ...[
            firsts[i],
            if (i < seconds.length) seconds[i],
          ],
        ],
      };
      BitmapSurface? landed;
      for (final MapEntry(key: order, value: dabs) in orders.entries) {
        expectParity(
          surface: blankSurface(),
          sequence: strokeOf(dabs),
          reason: 'dual stroke, $order',
        );
        final surface = materializeBrushDabSequenceOnBitmapSurface(
          surface: blankSurface(),
          sequence: strokeOf(dabs),
        ).surface;
        expect(surface, landed ?? surface, reason: order);
        landed = surface;
      }
    });

    test('a second tip shows nothing where the first tip laid nothing', () {
      const view = BrushDualView(compositeMode: SeparableBlendMode.screen);
      final landed = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 30, y: 30, size: 10, dual: view),
          secondDab(x: 90, y: 90, dual: view, size: 20),
        ]),
      );
      final alone = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(),
        sequence: strokeOf([dab(x: 30, y: 30, size: 10)]),
      );
      expect(landed.dirtyTiles, alone.dirtyTiles);
      expect(
        landed.surface.tileAt(TileCoord(x: 1, y: 1)),
        isNull,
        reason: 'the second tip alone at (90, 90) shows no ink',
      );
    });

    test('a tile the second tip never reaches shows nothing and is not '
        'dirty', () {
      // Multiply at density 1 under an empty second plane shows nothing:
      // the first tip's dabs there move the plane under a view that stays
      // put, so the tile is no change — in the bytes AND the change set,
      // which the kernels report from the view, not from the dabs.
      const view = BrushDualView();
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 30, y: 30, size: 14, dual: view),
          dab(x: 100, y: 30, size: 14, dual: view, sequence: 1),
          secondDab(x: 30, y: 30, dual: view, size: 20),
        ]),
        reason: 'a first-tip dab beyond the second tip',
      );
      final landed = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 30, y: 30, size: 14, dual: view),
          dab(x: 100, y: 30, size: 14, dual: view, sequence: 1),
          secondDab(x: 30, y: 30, dual: view, size: 20),
        ]),
      );
      expect(landed.dirtyTiles.coords.toSet(), {TileCoord(x: 0, y: 0)});
    });

    test('🚨the second tip cuts the PILED first stroke once, not per dab', () {
      // Two first-tip dabs on one spot under one second-tip level of a half:
      // the stroke shows the pile of the two halved — 0.8 piled twice is
      // 0.96, halved 0.48 — where a second tip under EACH dab would pile
      // two halved dabs, 1 − (1 − 0.4)² = 0.64.
      const view = BrushDualView();
      BrushDab first(int sequence) => dab(
        x: 40,
        y: 40,
        size: 8,
        hardness: 1,
        opacity: 1,
        flow: 0.8,
        dual: view,
        sequence: sequence,
      );
      final sequence = strokeOf([
        first(0),
        first(1),
        secondDab(
          x: 40,
          y: 40,
          dual: view,
          size: 30,
          hardness: 1,
          flow: 0.5,
        ),
      ]);
      expectParity(
        surface: blankSurface(),
        sequence: sequence,
        reason: 'a second tip at a half',
      );
      final tile = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(),
        sequence: sequence,
      ).surface.tileAt(TileCoord(x: 0, y: 0))!;
      final centre = readRgbaColorFromBitmapTile(tile: tile, x: 40, y: 40);
      expect(centre.a, closeTo(0.48 * 255, 1));
    });

    test('a second tip that covers the first fully shows it unchanged', () {
      // Multiply at density 1 under a second plane at 1 is the identity:
      // the view rounds from the plane where a plain stroke rounds from the
      // double, so a level may part where a channel sits on a half.
      const view = BrushDualView();
      final firsts = [
        for (var i = 0; i < 6; i += 1)
          dab(
            x: 34.0 + i * 3.0,
            y: 38.0 + i * 1.5,
            size: 14,
            tipMask: _testTipMask,
            sequence: i,
          ),
      ];
      final plain = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(),
        sequence: strokeOf(firsts),
      );
      final viewed = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(),
        sequence: strokeOf([
          for (final first in firsts) first.copyWith(dual: view),
          secondDab(x: 42, y: 42, dual: view, size: 60, hardness: 1),
        ]),
      );
      expect(viewed.dirtyTiles, plain.dirtyTiles);
      final coord = TileCoord(x: 0, y: 0);
      final want = plain.surface.tileAt(coord)!;
      final got = viewed.surface.tileAt(coord)!;
      var parted = 0;
      for (var y = 0; y < 64; y += 1) {
        for (var x = 0; x < 64; x += 1) {
          final a = readRgbaColorFromBitmapTile(tile: want, x: x, y: y);
          final b = readRgbaColorFromBitmapTile(tile: got, x: x, y: y);
          final apart = [
            (a.r - b.r).abs(),
            (a.g - b.g).abs(),
            (a.b - b.b).abs(),
            (a.a - b.a).abs(),
          ].reduce(math.max);
          expect(apart, lessThanOrEqualTo(1), reason: '($x, $y)');
          if (apart > 0) {
            parted += 1;
          }
        }
      }
      expect(parted, lessThan(64), reason: 'a level apart only on a half');
    });

    test('🚨every dual COMPOSITE MODE agrees across all three transcriptions',
        () {
      // v33. Ours multiplied and only multiplied while both source formats
      // carried a mode — Clip Studio's `DualBrushCompositeMode` (the 合成
      // モード index; 1 and 12 in the user's own files) and Photoshop's
      // `dualBrush.BlnM` (eight codes across 765 brushes).
      //
      // 🚨THE WHOLE TABLE, one stroke each, because the C switch and the two
      // Dart transcriptions are three separate spellings of the same
      // formulas and a mode nobody drives is a mode nobody has compared.
      // `add` is here for a reason of its own: it is NOT in the B(Cs, Cd)
      // table on either side — Skia's `plus` is a premultiplied saturating
      // add — so it takes a branch of its own in all three, and it is one
      // of the two modes actually found in a real file.
      for (final mode in SeparableBlendMode.values) {
        // ⛔NEITHER 0 NOR 1: at density 0 the mode cannot show and at 1 the
        // lerp collapses, so either would pass with the whole branch
        // deleted.
        final view = BrushDualView(compositeMode: mode, density: 0.6);
        expectParity(
          surface: blankSurface(),
          sequence: strokeOf([
            dab(x: 41.3, y: 39.7, size: 20, hardness: 0.45, dual: view),
            dab(x: 47.8, y: 42.1, size: 14, dual: view, sequence: 1),
            secondDab(x: 39.2, y: 38.4, dual: view, tipMask: _testTipMask),
            secondDab(x: 46.6, y: 43.5, dual: view, size: 8, flow: 0.7),
          ]),
          reason: 'the dual composite mode ${mode.name} must be one law in '
              'all three',
        );
      }
    });

    test('🚨the paper\'s HEIGHT agrees across all three transcriptions', () {
      // v53 (F-451). The paper cuts the coverage instead of multiplying it:
      // a soft round, a sampled tip turned and squashed, and a third that
      // overlaps both. ⛔NEITHER DENSITY IS 0 OR 1: the reach is the
      // density times the coverage, and only a partial one moves the
      // paper's floor through the texels that the band then grades.
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(
            x: 40.4,
            y: 40.6,
            size: 22,
            hardness: 0.3,
            textureMask: _testTipMask,
            textureScale: 1.3,
            textureDensity: 0.85,
            textureMode: BrushTextureMode.height,
            sequence: 0,
          ),
          dab(
            x: 55.7,
            y: 47.2,
            size: 26,
            tipMask: _testTipMask,
            roundness: 0.4,
            angleDegrees: 33,
            textureMask: _testTipMask,
            textureScale: 0.7,
            textureDensity: 0.55,
            textureMode: BrushTextureMode.height,
            sequence: 1,
          ),
          dab(
            x: 47.1,
            y: 58.3,
            size: 20,
            textureMask: _testTipMask,
            textureScale: 1.1,
            textureDensity: 0.7,
            textureMode: BrushTextureMode.height,
            sequence: 2,
          ),
        ]),
        reason: 'the paper\'s height must be one law in all three',
      );
    });

    test('a dual stroke across tip shapes', () {
      const view = BrushDualView(density: 0.9);
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 40.4, y: 40.6, size: 16, dual: view),
          dab(
            x: 52.2,
            y: 44.8,
            size: 16,
            tipShape: BrushTipShape.square,
            dual: view,
            sequence: 1,
          ),
          dab(
            x: 60.7,
            y: 47.3,
            size: 16,
            tipMask: _testTipMask,
            dual: view,
            sequence: 2,
          ),
          for (var i = 0; i < 4; i += 1)
            secondDab(
              x: 41.0 + i * 6.3,
              y: 41.5 + i * 2.1,
              dual: view,
              size: 9,
              tipMask: _testTipMask,
            ),
        ]),
        reason: 'dual stroke',
      );
    });

    test('paper-textured stroke stays anchored to the canvas', () {
      // Two dabs at different positions must sample the SAME paper pattern
      // (canvas-anchored).
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(
            x: 44.3,
            y: 41.2,
            size: 18,
            hardness: 0.5,
            textureMask: _testTipMask,
            textureScale: 0.9,
            textureDensity: 0.85,
            sequence: 0,
          ),
          dab(
            x: 58.9,
            y: 47.6,
            size: 18,
            tipMask: _testTipMask,
            textureMask: _testTipMask,
            textureScale: 1.5,
            textureDensity: 0.4,
            sequence: 1,
          ),
        ]),
        reason: 'paper texture',
      );
    });

    // 🚨A HALF ROUNDS AWAY FROM ZERO IN EVERY TRANSCRIPTION — the engine's
    // arithmetic contract (Dart's round() is llround). The C kernel rounds a
    // channel inline now (`qa_round_byte`), and only an exact half can tell
    // that from rounding a half to even: a hard dab at flow 0.5 over opaque
    // ink lands every channel on (source + destination) / 2 exactly, so
    // (100 + 53) / 2 = 76.5 must come out 77, not 76.
    // The C kernel blends a masked tip two pixels at a time only when it has
    // no texture mask and its tile shows no second plane (board
    // `brush-kernel-next` ①): a tip under a paper texture must stay on the
    // loop that multiplies the paper in, and the pairs must take every edge
    // step the scalar loop takes.
    test('a masked tip under a paper texture alone blends the same bytes', () {
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          for (var i = 0; i < 4; i += 1)
            dab(
              x: 61.3 + i * 9.1,
              y: 57.8 + i * 4.4,
              size: 64,
              tipMask: _testTipMask,
              textureMask: _upperHalfTipMask,
              textureScale: 1.3,
              textureDensity: 0.7,
              sequence: i,
            ),
        ]),
        reason: 'masked tip, texture only',
      );
    });

    test('every EDGE step agrees on a masked tip, two pixels at a time', () {
      for (final antiAlias in BrushAntiAlias.values) {
        expectParity(
          surface: blankSurface(tileSize: 256),
          sequence: strokeOf([
            for (var i = 0; i < 3; i += 1)
              dab(
                x: 64.7 + i * 12.3,
                y: 60.2 + i * 5.1,
                size: 58,
                hardness: 0.4,
                tipMask: _testTipMask,
                antiAlias: antiAlias,
                sequence: i,
              ),
          ]),
          reason: 'masked tip edge $antiAlias',
        );
      }
    });

    test('a channel that lands on an exact half rounds away from zero', () {
      final opaque = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(
            x: 40,
            y: 40,
            size: 30,
            color: 0xFF351E00,
            opacity: 1,
            flow: 1,
            hardness: 1,
          ),
        ]),
      ).surface;
      expectParity(
        surface: opaque,
        sequence: strokeOf([
          dab(
            x: 40.5,
            y: 40.5,
            size: 20,
            color: 0xFF641507,
            opacity: 1,
            flow: 0.5,
            hardness: 1,
          ),
        ]),
        reason: 'exact halves',
      );
      final pixel = readRgbaColorFromBitmapTile(
        tile: materializeBrushDabSequenceOnBitmapSurface(
          surface: opaque,
          sequence: strokeOf([
            dab(
              x: 40.5,
              y: 40.5,
              size: 20,
              color: 0xFF641507,
              opacity: 1,
              flow: 0.5,
              hardness: 1,
            ),
          ]),
        ).surface.tileAt(TileCoord(x: 0, y: 0))!,
        x: 40,
        y: 40,
      );
      expect([pixel.r, pixel.g, pixel.b, pixel.a], [77, 26, 4, 255]);
    });

    test('translucent color over translucent destination', () {
      final base = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(x: 45, y: 45, color: 0x40FF0000, opacity: 0.9, flow: 0.9),
        ]),
      ).surface;

      expectParity(
        surface: base,
        sequence: strokeOf([
          dab(x: 47, y: 46, color: 0x8000FF00, opacity: 0.6, flow: 0.8),
        ]),
        reason: 'translucent over translucent',
      );
    });

    // 🚨A DAB CUT INTO ROW BANDS BLENDS THE SAME BYTES (2026-09-24, board
    // `preset-spacing-minimum`). The C kernel cuts a dab of at least two
    // bands' worth of pixels into bands of whole rows when it covers fewer
    // tiles than that — which no dab above does, on 64-pixel tiles. These
    // reach it: 256-pixel tiles, dabs of 100 to 300 px, spans of every
    // height where a dab straddles the tile corner at the origin.
    test('a dab cut into row bands blends the same bytes', () {
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          dab(x: 100.3, y: 80.6, size: 100, hardness: 0.3, sequence: 0),
          dab(x: 6.5, y: 4.5, size: 150, hardness: 0.8, sequence: 1),
          dab(
            x: 120.2,
            y: 70.1,
            size: 130,
            hardness: 1,
            roundness: 0.4,
            angleDegrees: 30,
            sequence: 2,
          ),
          dab(
            x: 90.7,
            y: 60.2,
            size: 300,
            opacity: 0.5,
            flow: 0.4,
            sequence: 3,
          ),
        ]),
        reason: 'banded round and elliptical dabs',
      );
    });

    test('a banded dab reads its lattices by row the same way', () {
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          dab(
            x: 80.37,
            y: 70.81,
            size: 120,
            roundness: 0.6,
            angleDegrees: 20,
            tipMask: _testTipMask,
            sequence: 0,
          ),
          dab(
            x: 110.2,
            y: 64.9,
            size: 140,
            hardness: 0.5,
            textureMask: _testTipMask,
            textureScale: 1.5,
            textureDensity: 0.4,
            sequence: 1,
          ),
        ]),
        reason: 'banded sampled tip and texture',
      );
    });

    test('a banded dual stroke shows its view band by band the same way', () {
      // The C batch rebuilds the view over each band's rows once its dabs
      // have landed; a wide unrotated masked tip — the pairs' shape — lays
      // its planes only, since the tile shows the view.
      const view = BrushDualView(
        compositeMode: SeparableBlendMode.overlay,
        density: 0.7,
      );
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          dab(
            x: 80.37,
            y: 70.81,
            size: 120,
            tipMask: _testTipMask,
            dual: view,
          ),
          dab(x: 110.2, y: 64.9, size: 140, dual: view, sequence: 1),
          secondDab(
            x: 95.6,
            y: 68.2,
            dual: view,
            size: 130,
            tipMask: _testTipMask,
          ),
        ]),
        reason: 'banded dual stroke',
      );
    });

    test('a tile whose last band changes nothing is still reported changed', () {
      // The tip is inked in its top half only, so the dab's lower bands
      // change nothing while its upper ones do — a fold that let the last
      // band speak for its tile would drop the tile from the dirty set.
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          dab(
            x: 100,
            y: 80,
            size: 120,
            hardness: 1,
            tipMask: _upperHalfTipMask,
            sequence: 0,
          ),
        ]),
        reason: 'the fold keeps a band that changed',
      );
    });

    // A call carries at most `NativeDabBatcher.maxDabs` dabs, and one more
    // starts the next batch: a pixel-step stroke longer than that crosses
    // the cut with every row still under the dabs before it.
    test('a stroke longer than one batch blends the same bytes', () {
      expect(NativeDabBatcher.maxDabs, lessThan(150));
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          for (var i = 0; i < 150; i += 1)
            dab(
              x: 40.25 + i * 0.8,
              y: 60.5 + i * 0.35,
              size: 48,
              opacity: 0.6,
              flow: 0.3,
              sequence: i,
            ),
        ]),
        reason: 'a stroke across batches',
      );
    });

    test('dabs of different tips share a batch and keep their order', () {
      // A pen stroke's tip is resolved per quantized size, so its mask
      // changes every few dabs — and they still ride one call.
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          for (var i = 0; i < 12; i += 1)
            dab(
              x: 70.4 + i * 3.1,
              y: 66.2 + i * 1.7,
              size: 90,
              hardness: 0.6,
              tipMask: switch (i % 3) {
                0 => _testTipMask,
                1 => _upperHalfTipMask,
                _ => null,
              },
              sequence: i,
            ),
        ]),
        reason: 'mixed tips in one batch',
      );
    });

    test('a batch ends where its masks would outgrow the upload cache', () {
      // Every dab a tip of its own: the batch cuts once the next one would
      // upload past what the engine's mask cache holds at once, and the
      // next call lands on what the first left.
      final tips = [
        for (var k = 0; k < 11; k += 1)
          BrushTipMask(
            id: 'parity-distinct-$k',
            size: 8,
            alpha: Uint8List.fromList([
              for (var index = 0; index < 64; index += 1)
                (index * (k + 3) + k * 29) % 256,
            ]),
          ),
      ];
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          for (var i = 0; i < tips.length; i += 1)
            dab(
              x: 72.6 + i * 4.3,
              y: 61.9 + i * 2.2,
              size: 96,
              tipMask: tips[i],
              sequence: i,
            ),
        ]),
        reason: 'a batch cut at the mask allowance',
      );
    });

    // 🚨A ROW VISITS ONLY THE PIXELS ITS TIP ROWS CAN INK (ABI 39, board
    // `brush-kernel-next` ②). The C kernel narrows each pixel row of an
    // unrotated tip to the columns its two mask rows ink, and skips a row
    // whose two rows are bare. The pixels it leaves out must be exactly the
    // ones the loop threw away at coverage 0: fractional centres put the
    // edge pixel — the one whose second texel is the first inked — half on
    // the ink.
    test('a tip with bare margins blends the same bytes', () {
      final margins = BrushTipMask(
        id: 'parity-bare-margins',
        size: 16,
        alpha: Uint8List.fromList([
          for (var y = 0; y < 16; y += 1)
            for (var x = 0; x < 16; x += 1)
              if (y >= 5 && y < 11 && x >= 3 && x < 12)
                40 + (x * 13 + y * 7) % 200
              else
                0,
        ]),
      );
      final ring = BrushTipMask(
        id: 'parity-bare-ring',
        size: 12,
        alpha: Uint8List.fromList([
          for (var y = 0; y < 12; y += 1)
            for (var x = 0; x < 12; x += 1)
              if ((x == 2 || x == 9) && y >= 2 && y < 10 ||
                  (y == 2 || y == 9) && x >= 2 && x < 10)
                230
              else
                0,
        ]),
      );
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          for (var i = 0; i < 6; i += 1)
            dab(
              x: 60.37 + i * 9.61,
              y: 58.13 + i * 4.29,
              size: [23.0, 57.5, 118.0][i % 3],
              tipMask: i.isEven ? margins : ring,
              sequence: i,
            ),
        ]),
        reason: 'tips with bare margins and a hole',
      );
    });

    test('round tips prerendered per size — the canvas path — blend the same '
        'bytes', () {
      // Every canvas dab is resolved to a mask like these before it is
      // blended, and a round one is bare in its corners.
      final cache = BrushTipStampCache();
      expectParity(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          for (var i = 0; i < 8; i += 1)
            cache.resolveDab(
              dab(
                x: 70.21 + i * 7.3,
                y: 64.77 + i * 3.1,
                size: 9.5 + i * 17.25,
                hardness: i.isEven ? 0.25 : 0.9,
                sequence: i,
              ),
            ),
        ]),
        reason: 'resolved round tips',
      );
    });

    test('🚨two colours crossing take the colour blend on every road — the '
        'own-colour road is only for a dab over its own colour', () {
      // ABI 40 (`qa_dab_over_own_colour`): a dab over nothing or over its own
      // colour skips the colour blend, and every other pixel must still pay
      // it — on the scalar loop, two pixels at a time (masked tips), and in
      // the reference. One colour alone cannot tell the roads apart.
      final cache = BrushTipStampCache();
      const colours = [0xFFCC2211, 0xFF1144DD, 0x9922AA44];
      for (final masked in [false, true]) {
        expectParity(
          surface: blankSurface(tileSize: 256),
          sequence: strokeOf([
            for (var i = 0; i < 9; i += 1)
              () {
                final one = dab(
                  x: 72.4 + i * 6.1,
                  y: 70.9 + (i % 3) * 4.2,
                  size: 24 + i * 2.5,
                  hardness: i.isEven ? 0.3 : 0.8,
                  color: colours[i % colours.length],
                  // Both the opaque road and the settling one.
                  opacity: i.isEven ? 1.0 : 0.8,
                  flow: 0.6,
                  sequence: i,
                );
                return masked ? cache.resolveDab(one) : one;
              }(),
          ]),
          reason: masked ? 'masked, two colours' : 'analytic, two colours',
        );
      }
    });

    test('🚨a dab laying its share agrees across all three transcriptions', () {
      // ABI 41 (`stampShareOf`, `qa_dab_even`): a dab laid closer than a
      // tenth of its size lays its share through a table, on the opaque
      // road and the settling one, painting and erasing, on the scalar loop
      // and two pixels at a time. A dab without a path step lays whole, so
      // the cases above never reach the table.
      final cache = BrushTipStampCache();
      final painted = materializeBrushDabSequenceOnBitmapSurface(
        surface: blankSurface(tileSize: 256),
        sequence: strokeOf([
          for (var i = 0; i < 6; i += 1)
            dab(x: 52.0 + i * 9.0, y: 66.0, size: 30, sequence: i),
        ]),
      ).surface;
      for (final masked in [false, true]) {
        for (final erase in [false, true]) {
          expectParity(
            surface: erase ? painted : blankSurface(tileSize: 256),
            sequence: strokeOf([
              for (var i = 0; i < 14; i += 1)
                () {
                  final one = dab(
                    x: 58.3 + i * 1.7,
                    y: 64.9 + (i % 3) * 0.6,
                    size: 34 + i * 2.0,
                    hardness: i.isEven ? 0.2 : 0.9,
                    color: i % 4 == 3 ? 0xFF22AA66 : 0xFF3355CC,
                    opacity: i % 3 == 0 ? 1.0 : 0.7,
                    flow: 0.45,
                    sequence: i,
                  ).copyWith(pathStep: i == 0 ? null : 1.7);
                  return (masked ? cache.resolveDab(one) : one).copyWith(
                    erase: erase,
                  );
                }(),
            ]),
            reason: '${masked ? 'masked' : 'analytic'}, '
                '${erase ? 'erasing' : 'painting'}, laying a share',
          );
        }
      }
    });

    test('🚨a hard dab at full flow lays its share of a whole stamp alike — '
        'the table read at a = 1', () {
      // A laid alpha of exactly 1 reads the table's last pair: the opaque
      // road through the pair path (qa_d2_even), the settling one through
      // the scalar (qa_dab_even) — the two clamps at the table's end.
      final cache = BrushTipStampCache();
      for (final masked in [false, true]) {
        expectParity(
          surface: blankSurface(tileSize: 256),
          sequence: strokeOf([
            for (var i = 0; i < 10; i += 1)
              () {
                final one = dab(
                  x: 60.2 + i * 1.3,
                  y: 70.4,
                  size: 40,
                  hardness: 1,
                  opacity: i.isEven ? 1.0 : 0.6,
                  flow: 1,
                  sequence: i,
                ).copyWith(pathStep: i == 0 ? null : 1.3);
                return masked ? cache.resolveDab(one) : one;
              }(),
          ]),
          reason: '${masked ? 'masked' : 'analytic'}, full flow',
        );
      }
    });
  });
}
