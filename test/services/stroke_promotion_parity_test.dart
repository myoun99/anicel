import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';

import '../helpers/native_engine_path.dart';

/// PROMOTION round: pen-up ADOPTS the tiles the live overlay already
/// blended, instead of blending the whole stroke a second time. That is
/// only allowed to be a performance change — the pixels the surface ends
/// up holding must be the SAME BYTES the re-blending commit produces, in
/// every blend mode, on both engines.
///
/// The cases that could break it, each pinned below:
///  * a stroke that crosses its OWN ink (loop-back) — the one shape that
///    would expose a promoted tile being fed back in as blend input;
///  * a coordinate promoted mid-stroke and then painted over again (the
///    result must re-blend, not ship stale);
///  * a memory budget so small that results are dropped behind the brush
///    (pen-up must re-blend exactly those);
///  * tiles the stroke touched but did not change (they must stay out of
///    the commit entirely, keeping their identity and their image).
void main() {
  const canvasSize = CanvasSize(width: 192, height: 128);
  const tileSize = 64;

  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
    BrushLiveStrokeRasterizer.residentResultByteBudget = 96 * 1024 * 1024;
  });

  BrushDab dab({
    required double x,
    required double y,
    double size = 26,
    int color = 0xB02266AA,
    double opacity = 0.7,
    double flow = 0.8,
    double hardness = 0.45,
    int sequence = 0,
  }) {
    return BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: color,
      size: size,
      opacity: opacity,
      flow: flow,
      hardness: hardness,
      tipShape: BrushTipShape.round,
      pressure: 1,
      sequence: sequence,
    );
  }

  /// A painted base — a REAL surface, so no pixel carries colour under
  /// alpha 0 (the invariant both blend kernels maintain).
  BitmapSurface paintedBase() {
    return materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
      sequence: BrushDabSequence([
        for (var i = 0; i < 7; i += 1)
          dab(
            x: 18.5 + i * 22.0,
            y: 40.5 + (i.isEven ? 0 : 14),
            size: 34,
            color: 0xD0994411,
            opacity: 0.9,
            flow: 1.0,
            hardness: 0.7,
            sequence: i,
          ),
      ]),
    ).surface;
  }

  /// A stroke that runs right, then comes BACK across its own ink — the
  /// loop-back case. If a promoted (already blended) tile were ever fed
  /// back into the blend as if it were the base, this is the shape that
  /// shows it: the crossing would land at double density.
  List<BrushDab> loopBackStroke() {
    final dabs = <BrushDab>[];
    var sequence = 0;
    for (var i = 0; i < 12; i += 1) {
      dabs.add(dab(x: 24.0 + i * 11.0, y: 52.5, sequence: sequence += 1));
    }
    for (var i = 0; i < 12; i += 1) {
      dabs.add(dab(x: 156.0 - i * 11.0, y: 60.5, sequence: sequence += 1));
    }
    return dabs;
  }

  /// Every pixel of [surface], tile by tile — the comparison unit for
  /// "these two surfaces are the same artwork".
  Map<TileCoord, Uint8List> surfaceBytes(BitmapSurface surface) {
    return {
      for (final entry in surface.tiles.entries) entry.key: entry.value.pixels,
    };
  }

  void expectSameArtwork(
    BitmapSurface actual,
    BitmapSurface expected,
    String reason,
  ) {
    final actualBytes = surfaceBytes(actual);
    final expectedBytes = surfaceBytes(expected);
    // A tile that is present but fully transparent is the same artwork as
    // an absent one; compare on that basis so "the commit created a tile
    // it did not need to" is not reported as a pixel difference.
    final coords = {...actualBytes.keys, ...expectedBytes.keys};
    for (final coord in coords) {
      final a = actualBytes[coord];
      final b = expectedBytes[coord];
      if (a == null || b == null) {
        final present = a ?? b!;
        expect(
          present.every((byte) => byte == 0),
          isTrue,
          reason: '$reason: $coord exists on one side only and has ink',
        );
        continue;
      }
      for (var i = 0; i < a.length; i += 1) {
        if (a[i] != b[i]) {
          final pixel = i ~/ 4;
          fail(
            '$reason: $coord channel ${i % 4} at tile pixel '
            '(${pixel % tileSize}, ${pixel ~/ tileSize}) is ${a[i]}, '
            'expected ${b[i]}',
          );
        }
      }
    }
  }

  /// Drives the stroke the way the interactive view does — dabs arrive in
  /// batches and each batch pre-blends the tiles it touched (that is what
  /// makes results resident and, crucially, STALE when the next batch
  /// lands on the same coordinate).
  BrushLiveStrokeRasterizer drawWithLivePreBlend({
    required List<BrushDab> dabs,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
    int batchSize = 4,
  }) {
    final rasterizer = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    final blended = <BrushDab>[];
    for (var start = 0; start < dabs.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, dabs.length);
      blended.addAll(dabs.sublist(start, end));
      final region = rasterizer.blendFrom(blended, from: start);
      if (region == null) {
        continue;
      }
      for (final coord in region.toTileCoords(tileSize: tileSize)) {
        rasterizer
            .preBlendedOverlayTile(
              tileX: coord.x,
              tileY: coord.y,
              base: base,
              mode: mode,
              erase: erase,
            )
            ?.free();
      }
    }
    return rasterizer;
  }

  BitmapSurface referenceCommit({
    required BrushLiveStrokeRasterizer rasterizer,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
  }) {
    return compositeStrokePixelsOntoBitmapSurface(
      surface: base,
      strokePixels: rasterizer.strokePixelsWithinBounds()!,
      bounds: rasterizer.strokeBounds!,
      erase: erase,
      blendMode: mode,
    ).surface;
  }

  void runPromotionParity({required String label}) {
    for (final mode in BrushBlendMode.values) {
      final base = paintedBase();
      final erase = mode == BrushBlendMode.erase;
      final dabs = loopBackStroke();

      final live = drawWithLivePreBlend(
        dabs: dabs,
        base: base,
        mode: mode,
        erase: erase,
      );
      final promoted = live.promoteStrokeTiles(
        base: base,
        mode: mode,
        erase: erase,
      );
      final promotedSurface = base.putTiles([
        for (final entry in promoted) entry.tile,
      ]);
      live.clear();

      final reference = drawWithLivePreBlend(
        dabs: dabs,
        base: base,
        mode: mode,
        erase: erase,
      );
      final referenceSurface = referenceCommit(
        rasterizer: reference,
        base: base,
        mode: mode,
        erase: erase,
      );
      reference.clear();

      expectSameArtwork(
        promotedSurface,
        referenceSurface,
        '$label ${mode.name}: promoted tiles == re-blending commit',
      );
    }
  }

  test(
    'promoted tiles == the re-blending commit, every mode, loop-back '
    'stroke, Dart engine',
    () {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = true;
      expect(QaNativeEngine.instance, isNull);
      runPromotionParity(label: 'dart');
    },
  );

  test(
    'promoted tiles == the re-blending commit, every mode, loop-back '
    'stroke, NATIVE engine',
    () {
      if (dllPath == null) {
        markTestSkipped(nativeEngineMissingSkipReason);
        expect(nativeEngineRequired, isFalse, reason: 'CI must build one');
        return;
      }
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = dllPath;
      QaNativeEngine.debugForceDartFallback = false;
      expect(QaNativeEngine.instance, isNotNull);
      runPromotionParity(label: 'native');
    },
  );

  test(
    'a starved resident budget still promotes the right pixels — dropped '
    'results simply re-blend at pen-up',
    () {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = true;
      // Room for ONE tile: every coordinate the brush leaves behind is
      // dropped, so pen-up re-blends nearly the whole stroke.
      BrushLiveStrokeRasterizer.residentResultByteBudget =
          tileSize * tileSize * 4;

      final base = paintedBase();
      const mode = BrushBlendMode.multiply;
      final dabs = loopBackStroke();

      final live = drawWithLivePreBlend(
        dabs: dabs,
        base: base,
        mode: mode,
        erase: false,
      );
      expect(
        live.residentResultTileCount,
        lessThanOrEqualTo(2),
        reason: 'the budget must actually bite',
      );
      final promotedSurface = base.putTiles([
        for (final entry in live.promoteStrokeTiles(
          base: base,
          mode: mode,
          erase: false,
        ))
          entry.tile,
      ]);
      live.clear();

      final reference = drawWithLivePreBlend(
        dabs: dabs,
        base: base,
        mode: mode,
        erase: false,
      );
      final referenceSurface = referenceCommit(
        rasterizer: reference,
        base: base,
        mode: mode,
        erase: false,
      );
      reference.clear();

      expectSameArtwork(
        promotedSurface,
        referenceSurface,
        'starved budget: promoted == re-blended',
      );
    },
  );

  test(
    'a coordinate promoted after being painted over again ships the NEW '
    'pixels, not the stale resident result',
    () {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = true;
      final base = paintedBase();
      const mode = BrushBlendMode.color;

      final rasterizer = BrushLiveStrokeRasterizer(
        canvasSize: canvasSize,
        tileSize: tileSize,
      );
      final first = [dab(x: 40.5, y: 40.5, sequence: 0)];
      rasterizer.blendFrom(first, from: 0);
      // Displayed: the coordinate's result is now resident at revision R.
      rasterizer
          .preBlendedOverlayTile(
            tileX: 0,
            tileY: 0,
            base: base,
            mode: mode,
            erase: false,
          )
          ?.free();

      // A second dab lands on the SAME coordinate without being displayed
      // (the decode had not come back yet) — the resident result is now a
      // revision behind, and promoting it verbatim would drop this ink.
      final both = [...first, dab(x: 46.5, y: 44.5, sequence: 1)];
      rasterizer.blendFrom(both, from: 1);

      final promotedSurface = base.putTiles([
        for (final entry in rasterizer.promoteStrokeTiles(
          base: base,
          mode: mode,
          erase: false,
        ))
          entry.tile,
      ]);
      final referenceSurface = referenceCommit(
        rasterizer: rasterizer,
        base: base,
        mode: mode,
        erase: false,
      );
      rasterizer.clear();

      expectSameArtwork(
        promotedSurface,
        referenceSurface,
        'stale resident result must re-blend before promotion',
      );
    },
  );

  test(
    'a touched-but-unchanged coordinate is never promoted — its tile keeps '
    'its identity (and its decoded image)',
    () {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = true;
      final base = paintedBase();

      // A fully transparent stroke: it touches tiles but changes nothing.
      final rasterizer = BrushLiveStrokeRasterizer(
        canvasSize: canvasSize,
        tileSize: tileSize,
      );
      rasterizer.blendFrom([
        dab(x: 40.5, y: 40.5, color: 0x00FFFFFF, sequence: 0),
      ], from: 0);

      final promoted = rasterizer.promoteStrokeTiles(
        base: base,
        mode: BrushBlendMode.color,
        erase: false,
      );
      rasterizer.clear();

      expect(promoted, isEmpty);
    },
  );

  test('an empty-base coordinate promotes a brand new tile', () {
    QaNativeEngine.debugResetForTests();
    QaNativeEngine.debugForceDartFallback = true;
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);

    final rasterizer = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    rasterizer.blendFrom([
      dab(x: 40.5, y: 40.5, opacity: 1, flow: 1, hardness: 1, sequence: 0),
    ], from: 0);
    final promoted = rasterizer.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    final referenceSurface = referenceCommit(
      rasterizer: rasterizer,
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    rasterizer.clear();

    expect(promoted, isNotEmpty);
    expectSameArtwork(
      base.putTiles([for (final entry in promoted) entry.tile]),
      referenceSurface,
      'stroke onto empty canvas',
    );
    for (final entry in promoted) {
      expect(entry.tile, isA<BitmapTile>());
      expect(entry.tile.size, tileSize);
    }
  });
}
