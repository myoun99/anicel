import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';

/// The live stroke is CPU-rasterized with the same math as the commit path,
/// so the pixels on screen while drawing must be byte-identical to the
/// committed pixels — for every hardness, tip shape, and fractional center.
/// These tests lock that unification:
///
/// 1. `BrushLiveStrokeRasterizer` output == `materialize...` output, exactly.
/// 2. The pen-up composite fast path == full re-rasterization onto a painted
///    base, within one rounding step (source-over associativity).
/// 3. The overlay's decoded tile images — drawn through the production
///    painter exactly like committed tiles — reproduce the buffer's
///    premultiplied bytes: initial decode, mid-decode coalescing, and the
///    source-over composite onto committed artwork.

BrushDab _dab({
  required double x,
  required double y,
  double size = 10,
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
  double dualOffsetU = 0.0,
  double dualOffsetV = 0.0,
  BrushTipMask? textureMask,
  double textureScale = 1.0,
  double textureDensity = 1.0,
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
    roundness: roundness,
    angleDegrees: angleDegrees,
    tipMask: tipMask,
    dualMask: dualMask,
    dualMaskScale: dualMaskScale,
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

const int _canvasWidth = 40;
const int _canvasHeight = 40;
const _canvasSize = CanvasSize(width: _canvasWidth, height: _canvasHeight);

/// Canvas-wide straight-alpha bytes of the sparse live rasterizer.
Uint8List _rasterizerBytes(BrushLiveStrokeRasterizer rasterizer) {
  final bytes = Uint8List(_canvasWidth * _canvasHeight * 4);
  for (var y = 0; y < _canvasHeight; y += 1) {
    rasterizer.copyRow(0, y, _canvasWidth, bytes, y * _canvasWidth * 4);
  }
  return bytes;
}

Uint8List _liveBufferFor(List<BrushDab> dabs) {
  final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
  rasterizer.blendFrom(dabs, from: 0);
  return _rasterizerBytes(rasterizer);
}

/// Canvas-wide straight-alpha bytes of the materialized surface.
Uint8List _materializedBytes(
  List<BrushDab> dabs, {
  BitmapSurface? baseSurface,
}) {
  final result = materializeBrushDabSequenceOnBitmapSurface(
    surface:
        baseSurface ?? BitmapSurface(canvasSize: _canvasSize, tileSize: 64),
    sequence: BrushDabSequence(dabs),
  );
  return _surfaceBytes(result.surface);
}

Uint8List _surfaceBytes(BitmapSurface surface) {
  final bytes = Uint8List(_canvasWidth * _canvasHeight * 4);
  final tile = surface.tileAt(TileCoord(x: 0, y: 0));
  if (tile == null) {
    return bytes;
  }
  final tilePixels = tile.pixels;
  for (var y = 0; y < _canvasHeight; y += 1) {
    for (var x = 0; x < _canvasWidth; x += 1) {
      final tileOffset = (y * tile.size + x) * 4;
      final outOffset = (y * _canvasWidth + x) * 4;
      for (var channel = 0; channel < 4; channel += 1) {
        bytes[outOffset + channel] = tilePixels[tileOffset + channel];
      }
    }
  }
  return bytes;
}

void _expectExact(Uint8List actual, Uint8List expected, String reason) {
  expect(actual.length, expected.length);
  for (var index = 0; index < actual.length; index += 1) {
    if (actual[index] != expected[index]) {
      final pixel = index ~/ 4;
      fail(
        '$reason: channel ${index % 4} at pixel '
        '(${pixel % _canvasWidth}, ${pixel ~/ _canvasWidth}) is '
        '${actual[index]}, expected ${expected[index]}.',
      );
    }
  }
}

void _expectClose(
  Uint8List actual,
  Uint8List expected,
  String reason, {
  required int tolerance,
}) {
  expect(actual.length, expected.length);
  for (var index = 0; index < actual.length; index += 1) {
    final difference = (actual[index] - expected[index]).abs();
    if (difference > tolerance) {
      final pixel = index ~/ 4;
      fail(
        '$reason: channel ${index % 4} at pixel '
        '(${pixel % _canvasWidth}, ${pixel ~/ _canvasWidth}) differs by '
        '$difference (actual ${actual[index]}, expected ${expected[index]}).',
      );
    }
  }
}

void main() {
  group('live stroke rasterizer matches the commit rasterizer exactly', () {
    final scenarios = <String, List<BrushDab>>{
      'hard round dab on fractional center': [
        _dab(x: 9.13, y: 8.62, hardness: 1.0, opacity: 1.0, flow: 1.0),
      ],
      'soft round dab on fractional center': [
        _dab(x: 14.37, y: 12.81, size: 16, hardness: 0.3),
      ],
      'fully soft dab': [_dab(x: 14.5, y: 14.5, hardness: 0.0, size: 16)],
      'square tip dab': [_dab(x: 11.4, y: 9.7, tipShape: BrushTipShape.square)],
      'overlapping translucent stroke': [
        for (var i = 0; i < 6; i += 1)
          _dab(
            x: 7.37 + i * 3.21,
            y: 9.81 + i * 1.43,
            color: 0x8040A0C0,
            sequence: i,
          ),
      ],
      'canvas edge overhang': [
        _dab(x: 0.6, y: 0.4, size: 14, sequence: 0),
        _dab(x: 38.7, y: 38.9, size: 14, sequence: 1),
      ],
      'soft elliptical tip on fractional center': [
        _dab(
          x: 14.37,
          y: 12.81,
          size: 16,
          hardness: 0.3,
          roundness: 0.4,
          angleDegrees: 30,
        ),
      ],
      'hard thin elliptical tip': [
        _dab(
          x: 19.5,
          y: 19.5,
          size: 24,
          hardness: 1.0,
          opacity: 1.0,
          flow: 1.0,
          roundness: 0.05,
          angleDegrees: 137,
        ),
      ],
      'rotated rectangle tip': [
        _dab(
          x: 18.4,
          y: 17.7,
          size: 16,
          tipShape: BrushTipShape.square,
          roundness: 0.5,
          angleDegrees: 45,
        ),
      ],
      'sampled tip on fractional center': [
        _dab(x: 14.37, y: 12.81, size: 16, tipMask: _testTipMask),
      ],
      'paper-textured translucent stroke (canvas-anchored)': [
        for (var i = 0; i < 3; i += 1)
          _dab(
            x: 9.6 + i * 5.2,
            y: 13.1 + i * 2.3,
            size: 12,
            color: 0x9040A0C0,
            hardness: 0.6,
            textureMask: _testTipMask,
            textureScale: 0.8,
            textureDensity: 0.9,
            sequence: i,
          ),
      ],
      'paper texture combined with dual mask and sampled tip': [
        _dab(
          x: 16.4,
          y: 15.8,
          size: 14,
          tipMask: _testTipMask,
          dualMask: _testTipMask,
          dualMaskScale: 0.7,
          dualOffsetU: 0.4,
          dualOffsetV: 0.6,
          textureMask: _testTipMask,
          textureScale: 1.2,
          textureDensity: 0.5,
        ),
      ],
      'dual-brush textured soft round dab': [
        _dab(
          x: 13.4,
          y: 12.7,
          size: 14,
          hardness: 0.5,
          dualMask: _testTipMask,
          dualMaskScale: 0.6,
          dualOffsetU: 0.31,
          dualOffsetV: 0.77,
        ),
      ],
      'dual mask over sampled tip, translucent overlap': [
        for (var i = 0; i < 3; i += 1)
          _dab(
            x: 10.3 + i * 4.1,
            y: 12.2 + i * 1.7,
            size: 12,
            color: 0x9040A0C0,
            tipMask: _testTipMask,
            dualMask: _testTipMask,
            dualMaskScale: 1.4,
            dualOffsetU: 0.1 * (i + 1),
            dualOffsetV: 0.9 - 0.2 * i,
            sequence: i,
          ),
      ],
      'sampled tip rotated and squashed, overlapping stroke': [
        for (var i = 0; i < 4; i += 1)
          _dab(
            x: 9.2 + i * 4.3,
            y: 11.6 + i * 2.1,
            size: 14,
            color: 0x9040A0C0,
            roundness: 0.6,
            angleDegrees: 30,
            tipMask: _testTipMask,
            sequence: i,
          ),
      ],
    };

    scenarios.forEach((name, dabs) {
      test(name, () {
        _expectExact(_liveBufferFor(dabs), _materializedBytes(dabs), name);
      });
    });
  });

  group('pen-up composite fast path matches full re-rasterization', () {
    test('stroke over painted base within one rounding step', () {
      final baseDabs = [
        for (var i = 0; i < 5; i += 1)
          _dab(x: 8.5 + i * 4.0, y: 12.5, color: 0xCC994411, sequence: i),
      ];
      final base = materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(canvasSize: _canvasSize, tileSize: 64),
        sequence: BrushDabSequence(baseDabs),
      ).surface;

      final strokeDabs = [
        for (var i = 0; i < 5; i += 1)
          _dab(x: 10.2 + i * 3.6, y: 13.4, color: 0x9040A0C0, sequence: i),
      ];
      final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
      rasterizer.blendFrom(strokeDabs, from: 0);

      final composite = compositeStrokePixelsOntoBitmapSurface(
        surface: base,
        strokePixels: rasterizer.strokePixelsWithinBounds()!,
        bounds: rasterizer.strokeBounds!,
      );
      final reference = materializeBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: BrushDabSequence(strokeDabs),
      );

      expect(composite.dirtyTiles.isNotEmpty, isTrue);
      // Source-over is associative in real arithmetic but the two routes
      // quantize at different points (per-dab onto base vs stroke buffer
      // then one composite), so translucent overlaps drift by a rounding
      // step per overlapping dab. The painted pixel SET must match exactly;
      // channel values may drift slightly. What the user saw while drawing
      // is the buffer, and the commit composites exactly that buffer, so
      // the on-screen/committed unification itself is exact by construction.
      final compositeBytes = _surfaceBytes(composite.surface);
      final referenceBytes = _surfaceBytes(reference.surface);
      for (var index = 3; index < compositeBytes.length; index += 4) {
        expect(
          compositeBytes[index] > 0,
          referenceBytes[index] > 0,
          reason: 'painted pixel set must match at byte ',
        );
      }
      _expectClose(
        compositeBytes,
        referenceBytes,
        'composite vs re-rasterize',
        tolerance: 8,
      );
    });

    test('erase stroke with hard square dabs is exact', () {
      // Binary coverage (square tip, hardness 1, full opacity/flow) has no
      // per-dab quantization: buffer-then-one-destination-out equals the
      // per-dab destination-out route byte for byte.
      final baseDabs = [
        for (var i = 0; i < 5; i += 1)
          _dab(
            x: 8.5 + i * 4.0,
            y: 12.5,
            color: 0xFF994411,
            opacity: 1.0,
            flow: 1.0,
            hardness: 1.0,
            sequence: i,
          ),
      ];
      final base = materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(canvasSize: _canvasSize, tileSize: 64),
        sequence: BrushDabSequence(baseDabs),
      ).surface;

      final eraseDabs = [
        for (var i = 0; i < 4; i += 1)
          _dab(
            x: 10.0 + i * 3.0,
            y: 12.0,
            size: 6,
            opacity: 1.0,
            flow: 1.0,
            hardness: 1.0,
            tipShape: BrushTipShape.square,
            sequence: i,
          ).copyWith(erase: true),
      ];
      final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
      rasterizer.blendFrom(eraseDabs, from: 0);

      final composite = compositeStrokePixelsOntoBitmapSurface(
        surface: base,
        strokePixels: rasterizer.strokePixelsWithinBounds()!,
        bounds: rasterizer.strokeBounds!,
        erase: true,
      );
      final reference = materializeBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: BrushDabSequence(eraseDabs),
      );

      expect(composite.dirtyTiles.isNotEmpty, isTrue);
      _expectExact(
        _surfaceBytes(composite.surface),
        _surfaceBytes(reference.surface),
        'erase composite vs per-dab erase',
      );
    });

    test('translucent erase drifts at most a rounding step per overlap', () {
      final baseDabs = [
        for (var i = 0; i < 5; i += 1)
          _dab(
            x: 8.5 + i * 4.0,
            y: 12.5,
            color: 0xFF994411,
            opacity: 1.0,
            flow: 1.0,
            hardness: 1.0,
            sequence: i,
          ),
      ];
      final base = materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(canvasSize: _canvasSize, tileSize: 64),
        sequence: BrushDabSequence(baseDabs),
      ).surface;

      final eraseDabs = [
        for (var i = 0; i < 5; i += 1)
          _dab(x: 10.2 + i * 3.6, y: 13.4, sequence: i).copyWith(erase: true),
      ];
      final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
      rasterizer.blendFrom(eraseDabs, from: 0);

      final composite = compositeStrokePixelsOntoBitmapSurface(
        surface: base,
        strokePixels: rasterizer.strokePixelsWithinBounds()!,
        bounds: rasterizer.strokeBounds!,
        erase: true,
      );
      final reference = materializeBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: BrushDabSequence(eraseDabs),
      );

      // Same quantization-point argument as the paint fast path above; the
      // committed pixels are exactly the erase the user watched (the buffer
      // drives both the overlay preview and the commit).
      _expectClose(
        _surfaceBytes(composite.surface),
        _surfaceBytes(reference.surface),
        'erase composite vs per-dab erase',
        tolerance: 8,
      );
    });

    test('opaque stroke over blank base is exact', () {
      final strokeDabs = [
        for (var i = 0; i < 4; i += 1)
          _dab(
            x: 9.3 + i * 4.1,
            y: 11.8,
            opacity: 1.0,
            flow: 1.0,
            hardness: 1.0,
            sequence: i,
          ),
      ];
      final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
      rasterizer.blendFrom(strokeDabs, from: 0);

      final composite = compositeStrokePixelsOntoBitmapSurface(
        surface: BitmapSurface(canvasSize: _canvasSize, tileSize: 64),
        strokePixels: rasterizer.strokePixelsWithinBounds()!,
        bounds: rasterizer.strokeBounds!,
      );

      _expectExact(
        _surfaceBytes(composite.surface),
        _materializedBytes(strokeDabs),
        'opaque composite',
      );
    });
  });

  group('overlay tile images decode as the live buffer', () {
    // Renders the overlay exactly the way production does: through
    // BitmapSurfacePainter, over the given surface.
    Future<Uint8List> paintedCanvasBytes(
      ActiveStrokeOverlayModel model, {
      BitmapSurface? baseSurface,
    }) async {
      final recorder = ui.PictureRecorder();
      BitmapSurfacePainter(
        surface:
            baseSurface ?? BitmapSurface(canvasSize: _canvasSize, tileSize: 64),
        overlayModel: model,
        showTransparentBackground: false,
        // The shared tile-image cache's stale fallback is keyed by
        // COORDINATE within a scope; without a distinct scope per paint,
        // a not-yet-decoded tile here can show a PREVIOUS test's artwork
        // at the same coordinate (the per-pixel fallback is skipped when
        // a stale image exists). A fresh scope forces the deterministic
        // per-pixel path.
        staleScope: Object(),
      ).paint(
        Canvas(recorder),
        const Size(_canvasWidth * 1.0, _canvasHeight * 1.0),
      );
      final image = await recorder.endRecording().toImage(
        _canvasWidth,
        _canvasHeight,
      );
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return byteData!.buffer.asUint8List();
    }

    void updateRegion(
      ActiveStrokeOverlayModel model,
      BrushLiveStrokeRasterizer rasterizer,
      DirtyRegion region,
    ) {
      model.updateRegion(source: rasterizer, region: region);
    }

    test('decoded overlay tiles equal the premultiplied buffer', () async {
      final dabs = [
        _dab(x: 9.13, y: 8.62, size: 12, hardness: 0.4),
        _dab(x: 12.4, y: 10.1, size: 12, hardness: 0.4, sequence: 1),
      ];
      final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
      final region = rasterizer.blendFrom(dabs, from: 0)!;

      // A small tile size makes the stroke span several overlay tiles.
      final model = ActiveStrokeOverlayModel(tileSize: 16);
      addTearDown(model.dispose);
      updateRegion(model, rasterizer, region);
      await model.waitForPendingDecodes();
      expect(model.hasStrokeContent, isTrue);
      expect(model.tileImages.length, greaterThan(1));

      _expectExact(
        await paintedCanvasBytes(model),
        _premultipliedCanvasBytes(_rasterizerBytes(rasterizer)),
        'decoded overlay',
      );
    });

    test(
      'tiles touched while decoding re-decode with the newest content',
      () async {
        // Two overlapping translucent batches pushed back to back: the
        // second update lands while the first decode is still in flight, so
        // the shared tiles must re-snapshot the newer buffer state once the
        // running decode finishes (stale content would blend the overlap
        // wrong or drop the second batch).
        final firstBatch = [_dab(x: 9.5, y: 9.5, size: 12, color: 0x8040A0C0)];
        final secondBatch = [
          _dab(x: 12.5, y: 10.5, size: 12, color: 0x80C04010, sequence: 1),
        ];
        final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
        final model = ActiveStrokeOverlayModel(tileSize: 16);
        addTearDown(model.dispose);

        final firstRegion = rasterizer.blendFrom(firstBatch, from: 0)!;
        updateRegion(model, rasterizer, firstRegion);
        final allDabs = [...firstBatch, ...secondBatch];
        final secondRegion = rasterizer.blendFrom(allDabs, from: 1)!;
        updateRegion(model, rasterizer, secondRegion);
        await model.waitForPendingDecodes();

        _expectExact(
          await paintedCanvasBytes(model),
          _premultipliedCanvasBytes(_rasterizerBytes(rasterizer)),
          'coalesced decode',
        );
      },
    );

    test(
      'overlay composites onto committed artwork with source-over',
      () async {
        final baseDabs = [
          _dab(
            x: 6.5,
            y: 6.5,
            size: 6,
            color: 0xFF994411,
            opacity: 1.0,
            flow: 1.0,
            hardness: 1.0,
          ),
        ];
        final base = materializeBrushDabSequenceOnBitmapSurface(
          surface: BitmapSurface(canvasSize: _canvasSize, tileSize: 64),
          sequence: BrushDabSequence(baseDabs),
        ).surface;

        final strokeDabs = [
          _dab(
            x: 20.5,
            y: 20.5,
            size: 6,
            color: 0xFF2266AA,
            opacity: 1.0,
            flow: 1.0,
            hardness: 1.0,
          ),
        ];
        final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
        final region = rasterizer.blendFrom(strokeDabs, from: 0)!;
        final model = ActiveStrokeOverlayModel(tileSize: 16);
        addTearDown(model.dispose);
        updateRegion(model, rasterizer, region);
        await model.waitForPendingDecodes();

        final painted = await paintedCanvasBytes(model, baseSurface: base);
        int offsetOf(int x, int y) => (y * _canvasWidth + x) * 4;
        // Committed artwork outside the stroke stays visible below the
        // overlay layer...
        expect(painted[offsetOf(6, 6) + 3], 255);
        expect(painted[offsetOf(6, 6)], 0x99);
        // ...and the live stroke paints its own pixels above it.
        expect(painted[offsetOf(20, 20) + 3], 255);
        expect(painted[offsetOf(20, 20)], 0x22);
      },
    );

    test(
      'R27 #4: a PRE-BLENDED stroke displays byte-identically to the '
      'committed surface — multiply / behind / erase, translucent inks '
      'over translucent base',
      () async {
        // Translucent everything: exactly where the old GPU-float preview
        // drifted ±1/255 from the integer commit.
        final baseDabs = [
          _dab(
            x: 12.5,
            y: 12.5,
            size: 14,
            color: 0xB0994411,
            opacity: 0.8,
            flow: 0.9,
            hardness: 0.5,
          ),
        ];
        final base = materializeBrushDabSequenceOnBitmapSurface(
          surface: BitmapSurface(canvasSize: _canvasSize, tileSize: 64),
          sequence: BrushDabSequence(baseDabs),
        ).surface;

        for (final mode in const [
          BrushBlendMode.color,
          BrushBlendMode.multiply,
          BrushBlendMode.behind,
          BrushBlendMode.erase,
        ]) {
          final strokeDabs = [
            _dab(
              x: 16.5,
              y: 14.2,
              size: 12,
              color: 0x902266AA,
              opacity: 0.7,
              flow: 0.8,
              hardness: 0.4,
            ),
          ];
          final rasterizer = BrushLiveStrokeRasterizer(
            canvasSize: _canvasSize,
          );
          final region = rasterizer.blendFrom(strokeDabs, from: 0)!;

          // On screen AFTER PEN-UP: the committed surface, no overlay.
          final committed = compositeStrokePixelsOntoBitmapSurface(
            surface: base,
            strokePixels: rasterizer.strokePixelsWithinBounds()!,
            bounds: rasterizer.strokeBounds!,
            erase: mode == BrushBlendMode.erase,
            blendMode: mode,
          );
          final emptyOverlay = ActiveStrokeOverlayModel();
          addTearDown(emptyOverlay.dispose);
          final committedDisplay = await paintedCanvasBytes(
            emptyOverlay,
            baseSurface: committed.surface,
          );

          // PROMOTION round: BOTH display routes must hold the parity —
          // the ALIGNED grid (overlay tile == surface tile: the base
          // pass skips replaced coordinates, srcOver result tiles, no
          // isolation layer) and the MISMATCHED grid (isolation layer +
          // BlendMode.src replacement).
          for (final overlayTileSize in const [64, 16]) {
            final model = ActiveStrokeOverlayModel(tileSize: overlayTileSize)
              ..blendMode = mode
              ..erase = mode == BrushBlendMode.erase
              ..preBlendBase = base;
            addTearDown(model.dispose);
            updateRegion(model, rasterizer, region);
            await model.waitForPendingDecodes();
            expect(model.preBlended, isTrue);

            final route = overlayTileSize == 64
                ? 'aligned replacement route'
                : 'isolation fallback route';
            _expectExact(
              await paintedCanvasBytes(model, baseSurface: base),
              committedDisplay,
              '${mode.name} ($route): live display == committed display',
            );
          }
        }
      },
    );

    test(
      'a pre-blended tile at the PASTEBOARD EDGE still covers its whole '
      'coordinate — the base pass skipped that tile, so a clamped image '
      'would cut a transparent strip through committed artwork',
      () async {
        // The overlay grid divides the canvas but NOT the pasteboard
        // (3× the canvas), so the last coordinate is a partial rect: 40×3
        // = 120 wide, and a 32px grid puts the wall mid-tile.
        const overlayTile = 32;
        final base = materializeBrushDabSequenceOnBitmapSurface(
          surface: BitmapSurface(canvasSize: _canvasSize, tileSize: overlayTile),
          sequence: BrushDabSequence([
            _dab(
              x: 113.5,
              y: 12.5,
              size: 20,
              color: 0xFF994411,
              opacity: 1,
              flow: 1,
              hardness: 1,
            ),
          ]),
        ).surface;
        final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
        final region = rasterizer.blendFrom([
          _dab(x: 112.5, y: 14.5, size: 10, color: 0xFF2266AA),
        ], from: 0)!;

        final model = ActiveStrokeOverlayModel(tileSize: overlayTile)
          ..preBlendBase = base;
        addTearDown(model.dispose);
        model.updateRegion(source: rasterizer, region: region);
        await model.waitForPendingDecodes();

        expect(model.tileImages, isNotEmpty);
        for (final entry in model.tileImages.entries) {
          expect(
            entry.value.width,
            overlayTile,
            reason: '${entry.key}: a pre-blended tile is never clamped',
          );
          expect(entry.value.height, overlayTile);
        }
      },
    );

    test('reset clears the tile images and dabs', () async {
      final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
      final dabs = [_dab(x: 8.5, y: 8.5)];
      final region = rasterizer.blendFrom(dabs, from: 0)!;
      final model = ActiveStrokeOverlayModel(tileSize: 16);
      addTearDown(model.dispose);
      model.dabs.addAll(dabs);
      updateRegion(model, rasterizer, region);
      await model.waitForPendingDecodes();
      expect(model.hasStrokeContent, isTrue);

      model.reset();

      expect(model.hasStrokeContent, isFalse);
      expect(model.tileImages, isEmpty);
      expect(model.dabs, isEmpty);
    });

    test(
      'a decode landing after reset is discarded, not resurrected',
      () async {
        final rasterizer = BrushLiveStrokeRasterizer(canvasSize: _canvasSize);
        final dabs = [_dab(x: 8.5, y: 8.5)];
        final region = rasterizer.blendFrom(dabs, from: 0)!;
        final model = ActiveStrokeOverlayModel(tileSize: 16);
        addTearDown(model.dispose);
        updateRegion(model, rasterizer, region);

        // Reset while the decode is still in flight (pointer cancel / next
        // stroke starting): the late image must be dropped.
        model.reset();
        await model.waitForPendingDecodes();

        expect(model.hasStrokeContent, isFalse);
        expect(model.tileImages, isEmpty);
      },
    );
  });
}

/// Full-canvas expected bytes: the straight-alpha buffer premultiplied the
/// way Skia rasterizes the region pictures (mul-div-255 rounding).
Uint8List _premultipliedCanvasBytes(Uint8List straight) {
  final out = Uint8List(straight.length);
  for (var offset = 0; offset < straight.length; offset += 4) {
    final alpha = straight[offset + 3];
    if (alpha == 0) {
      continue;
    }
    out[offset] = _mul255Round(straight[offset], alpha);
    out[offset + 1] = _mul255Round(straight[offset + 1], alpha);
    out[offset + 2] = _mul255Round(straight[offset + 2], alpha);
    out[offset + 3] = alpha;
  }
  return out;
}

int _mul255Round(int value, int alpha) {
  final product = value * alpha + 128;
  return (product + (product >> 8)) >> 8;
}
