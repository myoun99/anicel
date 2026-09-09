import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_pixel_blend_operation.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
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
import 'package:anicel/src/services/brush_dab_sequence_blend.dart';

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
  final canvasSize = surface.canvasSize;

  RgbaColor destinationAt(int x, int y) {
    if (!canvasSize.containsPasteboardPixel(x: x, y: y)) {
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
    if (!canvasSize.containsPasteboardPixel(x: operation.x, y: operation.y)) {
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
        existingTile ?? BitmapTile.blank(coord: coord, size: surface.tileSize);
    final updatedTile = materializedBitmapTileForOperations(
      tile: tile,
      operations: operationsByCoord[coord]!,
    );
    if (updatedTile == null) continue;
    updatedSurface = updatedSurface.putTiles([updatedTile]);
    dirtyTiles = dirtyTiles.add(coord);
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
  BrushTipMask? dualMask,
  double dualMaskScale = 1.0,
  double dualDensity = 1.0,
  double dualOffsetU = 0.0,
  double dualOffsetV = 0.0,
  BrushTipMask? textureMask,
  double textureScale = 1.0,
  double textureDensity = 1.0,
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
    dualMask: dualMask,
    dualMaskScale: dualMaskScale,
    dualDensity: dualDensity,
    dualOffsetU: dualOffsetU,
    dualOffsetV: dualOffsetV,
    textureMask: textureMask,
    textureScale: textureScale,
    textureDensity: textureDensity,
  );
}

/// Deterministic 8x8 gradient-with-holes mask for parity scenarios.
final BrushTipMask _testTipMask = BrushTipMask(
  id: 'parity-test-tip',
  size: 8,
  alpha: Uint8List.fromList([
    for (var index = 0; index < 64; index += 1)
      index % 7 == 0 ? 0 : ((index * 4 + 16) % 256),
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
      for (final step in BrushAntiAlias.values) {
        expectParity(
          surface: blankSurface(),
          sequence: strokeOf([
            dab(x: 40, y: 40, hardness: 0.0, antiAlias: step),
            dab(x: 80, y: 40, hardness: 0.6, antiAlias: step, sequence: 1),
          ]),
          reason: 'edge step ${step.name}',
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

    test('🚨a dual mask at PARTIAL density agrees across all three', () {
      // ⚠️The case above runs at density 1.0, which is the identity — it
      // exercises the plain multiply the dual mask always did, not the new
      // blend. Every transcription would still agree if one of them had
      // dropped the density term entirely. Only a value that is neither 0
      // nor 1 makes the three actually compare.
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(
            x: 40.4,
            y: 40.6,
            size: 18,
            hardness: 0.5,
            dualMask: _testTipMask,
            dualMaskScale: 0.7,
            dualDensity: 0.35,
            dualOffsetU: 0.31,
            dualOffsetV: 0.77,
            sequence: 0,
          ),
          // ...and with a texture on top, so the two density blends run in
          // the same pixel and their ORDER is pinned as well.
          dab(
            x: 52.2,
            y: 44.8,
            size: 18,
            dualMask: _testTipMask,
            dualMaskScale: 0.55,
            dualDensity: 0.8,
            textureMask: _testTipMask,
            textureScale: 1.3,
            textureDensity: 0.4,
            sequence: 1,
          ),
        ]),
        reason: 'the dual density blend must be one law in all three',
      );
    });

    test('dual-brush textured stroke across tip shapes', () {
      expectParity(
        surface: blankSurface(),
        sequence: strokeOf([
          dab(
            x: 40.4,
            y: 40.6,
            size: 16,
            hardness: 0.5,
            dualMask: _testTipMask,
            dualMaskScale: 0.7,
            dualOffsetU: 0.31,
            dualOffsetV: 0.77,
            sequence: 0,
          ),
          dab(
            x: 52.2,
            y: 44.8,
            size: 16,
            tipShape: BrushTipShape.square,
            dualMask: _testTipMask,
            dualMaskScale: 1.3,
            dualOffsetU: 0.9,
            dualOffsetV: 0.1,
            sequence: 1,
          ),
          dab(
            x: 60.7,
            y: 47.3,
            size: 16,
            tipMask: _testTipMask,
            dualMask: _testTipMask,
            dualMaskScale: 0.5,
            dualOffsetU: 0.5,
            dualOffsetV: 0.5,
            sequence: 2,
          ),
        ]),
        reason: 'dual brush texture',
      );
    });

    test('paper-textured stroke stays anchored to the canvas', () {
      // Two dabs at different positions must sample the SAME paper pattern
      // (canvas-anchored), combined here with pressure-free dual masking.
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
            dualMask: _testTipMask,
            dualMaskScale: 0.6,
            dualOffsetU: 0.25,
            dualOffsetV: 0.75,
            textureMask: _testTipMask,
            textureScale: 1.5,
            textureDensity: 0.4,
            sequence: 1,
          ),
        ]),
        reason: 'paper texture',
      );
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
  });
}
