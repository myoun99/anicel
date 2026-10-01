import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_selection_paint_clip.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';

import '../helpers/native_engine_path.dart';

/// 🚨★★★erase-live-and-dab-route-round-apart (2026-09-28): a stroke of
/// brush dabs that reaches the commit WITHOUT its live buffer — re-derived
/// from its dabs when the cel moved under the promotion, or laid down again
/// by 확정 — lands the bytes the live overlay showed, in every blend mode,
/// on both engines.
///
/// Laid on the cel dab by dab, the same stroke reached the same sum but
/// rounded after every dab: an eraser over paint kept alpha 11 where the
/// screen had shown 10. It is piled up on an empty surface and composited
/// once now, which is what the overlay does.
void main() {
  const canvasSize = CanvasSize(width: 192, height: 128);
  const tileSize = 64;
  const layerId = LayerId('l');
  const frameId = FrameId('f');
  final dllPath = nativeEngineLibraryPathOrNull();

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
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
    bool erase = false,
  }) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: color,
    size: size,
    opacity: opacity,
    flow: flow,
    hardness: hardness,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
    erase: erase,
  );

  /// Paint under the stroke — where the two routes' roundings part. (Over
  /// an empty cel they cannot: laying dabs on nothing IS piling them up.)
  BitmapSurface paintedBase() => materializeBrushDabSequenceOnBitmapSurface(
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

  /// Right, then back across its own ink: every pixel of the crossing is
  /// laid by several dabs, which is where rounding after each one shows.
  List<BrushDab> loopBack({required bool erase}) {
    final dabs = <BrushDab>[];
    var sequence = 0;
    for (var i = 0; i < 12; i += 1) {
      dabs.add(
        dab(x: 24.0 + i * 11.0, y: 52.5, sequence: sequence += 1, erase: erase),
      );
    }
    for (var i = 0; i < 12; i += 1) {
      dabs.add(
        dab(x: 156.0 - i * 11.0, y: 60.5, sequence: sequence += 1, erase: erase),
      );
    }
    return dabs;
  }

  /// A cut piece's picture: every alpha from 0 to 255 somewhere in it.
  BrushStampImage piece() {
    const width = 90;
    const height = 60;
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final i = (y * width + x) * 4;
        rgba[i] = 0x33;
        rgba[i + 1] = 0x88;
        rgba[i + 2] = 0xCC;
        rgba[i + 3] = (x * 255 ~/ (width - 1) + y) % 256;
      }
    }
    return BrushStampImage(id: 'piece', width: width, height: height, rgba: rgba);
  }

  BrushDab stampDab(
    BrushStampImage image, {
    required double opacity,
    bool erase = false,
    int sequence = 0,
  }) => BrushDab(
    center: CanvasPoint(x: 80, y: 50),
    color: 0xFF000000,
    size: image.width.toDouble(),
    opacity: opacity,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: sequence,
    erase: erase,
    stamp: image,
  );

  /// What the user watched: the live overlay piling the stroke up, then
  /// promoted onto [base] at pen-up.
  BitmapSurface live(
    List<BrushDab> dabs,
    BitmapSurface base,
    BrushBlendMode mode,
  ) {
    final rasterizer = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    rasterizer.blendFrom(dabs, from: 0);
    final promoted = rasterizer.promoteStrokeTiles(
      base: base,
      mode: mode,
      erase: mode == BrushBlendMode.erase,
    );
    rasterizer.clear();
    return base.putTiles([
      for (final entry in promoted) (coord: entry.coord, tile: entry.tile),
    ]);
  }

  /// The same stroke with nothing but its dabs — the payload a re-derived
  /// commit and 확정 carry.
  BitmapSurface rederived(
    List<BrushDab> dabs,
    BitmapSurface base,
    BrushBlendMode mode,
  ) => brushCommitResultForBrushDabSequenceOnBitmapSurface(
    surface: base,
    sequence: BrushDabSequence(dabs),
    layerId: layerId,
    frameId: frameId,
    blendMode: mode,
  ).afterSurface;

  void expectSameArtwork(
    BitmapSurface actual,
    BitmapSurface expected,
    String reason,
  ) {
    final coords = {...actual.tiles.keys, ...expected.tiles.keys};
    for (final coord in coords) {
      final a = actual.tiles[coord]?.pixels;
      final b = expected.tiles[coord]?.pixels;
      if (a == null || b == null) {
        // A tile present but empty is the same artwork as an absent one.
        expect(
          (a ?? b!).every((byte) => byte == 0),
          isTrue,
          reason: '$reason: $coord has ink on one side only',
        );
        continue;
      }
      for (var i = 0; i < a.length; i += 1) {
        if (a[i] != b[i]) {
          final pixel = i ~/ 4;
          fail(
            '$reason: $coord channel ${i % 4} at tile pixel '
            '(${pixel % tileSize}, ${pixel ~/ tileSize}) is ${a[i]}, '
            'the screen showed ${b[i]}',
          );
        }
      }
    }
  }

  void onEachEngine(String name, void Function() body) {
    test('$name — Dart engine', () {
      QaNativeEngine.debugResetForTests();
      QaNativeEngine.debugForceDartFallback = true;
      expect(QaNativeEngine.instance, isNull);
      body();
    });
    test('$name — native engine', () {
      if (dllPath == null) {
        markTestSkipped(nativeEngineMissingSkipReason);
        return;
      }
      QaNativeEngine.debugResetForTests();
      debugQaEngineLibraryPathOverride = dllPath;
      QaNativeEngine.debugForceDartFallback = false;
      expect(QaNativeEngine.instance, isNotNull);
      body();
    });
  }

  onEachEngine('every blend mode over paint: the stroke re-derived from its '
      'dabs is the stroke the overlay promoted', () {
    for (final mode in BrushBlendMode.values) {
      final dabs = loopBack(erase: mode == BrushBlendMode.erase);
      final base = paintedBase();
      expectSameArtwork(
        rederived(dabs, base, mode),
        live(dabs, base, mode),
        mode.name,
      );
    }
  });

  onEachEngine('the premise: the dabs piled up on an empty surface ARE the '
      'overlay\'s buffer, byte for byte', () {
    for (final erase in [false, true]) {
      final dabs = loopBack(erase: erase);
      final rasterizer = BrushLiveStrokeRasterizer(
        canvasSize: canvasSize,
        tileSize: tileSize,
      );
      rasterizer.blendFrom(dabs, from: 0);
      final piled = rasterizeStrokeForClipping(
        dabs: dabs,
        canvasSize: canvasSize,
        tileSize: tileSize,
      )!;
      expect(piled.bounds, rasterizer.strokeBounds, reason: 'erase=$erase');
      expect(
        piled.pixels,
        rasterizer.strokePixelsWithinBounds(),
        reason: 'erase=$erase',
      );
      rasterizer.clear();
    }
  });

  onEachEngine('a selection that covers the stroke lands the same bytes as '
      'none — one route with a clip, not two routes', () {
    final region = CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(left: 0, top: 0, right: 192, bottom: 128),
    );
    for (final mode in [BrushBlendMode.color, BrushBlendMode.erase]) {
      final dabs = loopBack(erase: mode == BrushBlendMode.erase);
      final base = paintedBase();
      final clipped = clipStrokeCommitToSelection(
        BrushStrokeCommitData(sourceDabs: dabs, blendMode: mode),
        region: region,
        surface: base,
      )!;
      expectSameArtwork(
        brushCommitResultForBrushDabSequenceOnBitmapSurface(
          surface: base,
          sequence: BrushDabSequence(dabs),
          layerId: layerId,
          frameId: frameId,
          prerasterizedStrokePixels: clipped.strokePixels,
          prerasterizedStrokeBounds: clipped.strokeBounds,
          blendMode: mode,
        ).afterSurface,
        rederived(dabs, base, mode),
        '${mode.name} with a selection',
      );
    }
  });

  onEachEngine('a STAMP still lands 1:1 — a pasted piece at 40% keeps its '
      'bytes, and a lift\'s landing still cuts the hole before it lays the '
      'piece', () {
    final image = piece();
    for (final erase in [false, true]) {
      final base = paintedBase();
      final stamp = stampDab(image, opacity: 0.4, erase: erase);
      expectSameArtwork(
        rederived(
          [stamp],
          base,
          erase ? BrushBlendMode.erase : BrushBlendMode.color,
        ),
        materializeBrushDabSequenceOnBitmapSurface(
          surface: base,
          sequence: BrushDabSequence([stamp]),
        ).surface,
        'a stamp at 40%${erase ? ', erasing' : ''}',
      );
    }

    // The landing is a PROGRAM: the hole first, then the piece over it.
    final base = paintedBase();
    final landing = [
      stampDab(image, opacity: 1, erase: true),
      stampDab(image, opacity: 1, sequence: 1),
    ];
    expectSameArtwork(
      rederived(landing, base, BrushBlendMode.color),
      materializeBrushDabSequenceOnBitmapSurface(
        surface: base,
        sequence: BrushDabSequence(landing),
      ).surface,
      'a lift landing',
    );
  });
}
