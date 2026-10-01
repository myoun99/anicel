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
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_selection_paint_clip.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';

import '../helpers/native_engine_path.dart';

/// 🚨★★★board `a-stamp-rounds-twice-inside-a-selection` (2026-09-28): a
/// stamp — a fill, a pasted or stamped piece — under 100% landed a level
/// apart inside a selection and out of one. Inside, it was rasterized onto
/// an empty surface first (its alpha rounded there at the dab's opacity),
/// then clipped and composited: a second rounding. It clips in its own
/// picture now and lands 1:1 either way (절대명령 2: 선택이 있든 없든 같은
/// 코드가 답한다).
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

  /// Paint under the stamp, where the two roundings part.
  BitmapSurface paintedBase() => materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
    sequence: BrushDabSequence([
      for (var i = 0; i < 7; i += 1)
        BrushDab(
          center: CanvasPoint(x: 18.5 + i * 22.0, y: 40.5 + (i.isEven ? 0 : 14)),
          color: 0xD0994411,
          size: 34,
          opacity: 1,
          flow: 1,
          hardness: 0.7,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: i,
        ),
    ]),
  ).surface;

  /// A 90×60 piece with every alpha from 0 to 255 in it, landing on
  /// x 35..125, y 20..80.
  BrushDab stamp({required double opacity, bool erase = false}) {
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
    return BrushDab(
      center: CanvasPoint(x: 80, y: 50),
      color: 0xFF000000,
      size: width.toDouble(),
      opacity: opacity,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      erase: erase,
      stamp: BrushStampImage(id: 'piece', width: width, height: height, rgba: rgba),
    );
  }

  CanvasSelectionRegion box(double left, double right) =>
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: left, top: 0, right: right, bottom: 128),
      );

  /// The stamp as the canvas panel lands it: through the commit funnel's
  /// clip when a selection is live, then the commit.
  BitmapSurface landed(
    BrushDab dab,
    BitmapSurface base,
    BrushBlendMode mode, {
    CanvasSelectionRegion? selection,
  }) {
    final raw = BrushStrokeCommitData(sourceDabs: [dab], blendMode: mode);
    final data = selection == null
        ? raw
        : clipStrokeCommitToSelection(raw, region: selection, surface: base)!;
    return brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: base,
      sequence: BrushDabSequence(data.sourceDabs),
      layerId: layerId,
      frameId: frameId,
      prerasterizedStrokePixels: data.strokePixels,
      prerasterizedStrokeBounds: data.strokeBounds,
      blendMode: mode,
    ).afterSurface;
  }

  /// The first channel where [a] and [b] disagree over the canvas at
  /// x in [fromX, toX), or null.
  String? firstDifference(
    BitmapSurface a,
    BitmapSurface b, {
    int fromX = 0,
    int toX = 192,
  }) {
    for (var y = 0; y < canvasSize.height; y += 1) {
      for (var x = fromX; x < toX; x += 1) {
        final coord = (x: x ~/ tileSize, y: y ~/ tileSize);
        final ta = a.tiles.entries
            .where((e) => e.key.x == coord.x && e.key.y == coord.y)
            .firstOrNull
            ?.value;
        final tb = b.tiles.entries
            .where((e) => e.key.x == coord.x && e.key.y == coord.y)
            .firstOrNull
            ?.value;
        final at = ((y % tileSize) * tileSize + x % tileSize) * 4;
        for (var c = 0; c < 4; c += 1) {
          final va = ta == null ? 0 : ta.pixels[at + c];
          final vb = tb == null ? 0 : tb.pixels[at + c];
          if (va != vb) {
            return '($x, $y) channel $c: $va vs $vb';
          }
        }
      }
    }
    return null;
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

  onEachEngine('a stamp at 40% lands the same bytes inside a selection that '
      'covers it as with none — painting, erasing, multiplying', () {
    for (final (erase, mode) in [
      (false, BrushBlendMode.color),
      (true, BrushBlendMode.erase),
      (false, BrushBlendMode.multiply),
    ]) {
      final base = paintedBase();
      final dab = stamp(opacity: 0.4, erase: erase);
      expect(
        firstDifference(
          landed(dab, base, mode, selection: box(0, 192)),
          landed(dab, base, mode),
        ),
        isNull,
        reason: mode.name,
      );
    }
  });

  onEachEngine('half a selection: inside, the stamp lands as it does with no '
      'selection; outside, the paint stands untouched', () {
    final base = paintedBase();
    final dab = stamp(opacity: 0.4);
    final clipped = landed(
      dab,
      base,
      BrushBlendMode.color,
      selection: box(0, 80),
    );
    expect(
      firstDifference(
        clipped,
        landed(dab, base, BrushBlendMode.color),
        toX: 80,
      ),
      isNull,
      reason: 'inside',
    );
    expect(
      firstDifference(clipped, base, fromX: 80),
      isNull,
      reason: 'outside',
    );
  });

  test('a stamp the selection cannot reach lands nothing at all', () {
    expect(
      clipStampDabToSelection(stamp(opacity: 0.4), region: box(150, 192)),
      isNull,
    );
  });
}
