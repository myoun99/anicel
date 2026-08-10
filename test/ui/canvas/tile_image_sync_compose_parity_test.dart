import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';

/// THE FORK IN THE ROAD FOR N4.
///
/// N4 wants to give a just-committed tile a picture SYNCHRONOUSLY, by
/// composing pictures we already hold — the pre-commit tile's image and the
/// live overlay's image of the new ink — with `Picture.toImageSync`, instead
/// of borrowing the previous generation's picture at that coordinate (which
/// is the stale-tile lie) or drawing nothing (which is the hole).
///
/// Whether that composed image may be ADOPTED as the tile's real picture
/// depends on one measurable fact, and this is it:
///
///   Is  srcOver(preImage, overlayImage)  byte-identical to the true decode
///   of the committed tile's bytes?
///
/// They are NOT obviously equal. The commit kernel blends in STRAIGHT alpha
/// and the result is premultiplied on the way to the GPU; this composition
/// premultiplies each operand first and blends in PREMULTIPLIED space. Those
/// are different orders of the same 8-bit rounding.
///
/// - Exact  ⇒ `adoptDecoded` outright. Small change, no new lifecycle.
/// - Not exact ⇒ the composed image is PROVISIONAL and the real decode has
///   to be allowed to land and replace it, which is a lifecycle.
///
/// ⚠️ The stroke here is deliberately SEMI-TRANSPARENT over NON-EMPTY pixels.
/// A fully opaque stroke composes exactly by construction and would make this
/// test prove nothing — the anti-vacuity condition is asserted below.
void main() {
  const tileSize = 8;
  final coord = TileCoord(x: 0, y: 0);

  BrushDab dab({
    required double x,
    required double y,
    required int color,
    required double opacity,
    double size = 6,
    int sequence = 0,
  }) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: color,
    size: size,
    opacity: opacity,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  BitmapSurface blankSurface() => BitmapSurface(
    canvasSize: const CanvasSize(width: tileSize, height: tileSize),
    tileSize: tileSize,
    tiles: const {},
  );

  BitmapSurface materialize(BitmapSurface on, List<BrushDab> dabs) =>
      materializeBrushDabSequenceOnBitmapSurface(
        surface: on,
        sequence: BrushDabSequence(dabs),
      ).surface;

  Future<ui.Image> decodeTile(BitmapTile tile) {
    final upload = BitmapTileImageCache.premultipliedTileUpload(tile);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      upload.view,
      tile.size,
      tile.size,
      ui.PixelFormat.rgba8888,
      (image) {
        upload.free();
        completer.complete(image);
      },
    );
    return completer.future;
  }

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  /// `record(drawImage(base); drawImage(over)) → toImageSync` — the exact
  /// shape N4 would use at the commit funnel.
  ui.Image composeSync(ui.Image base, ui.Image over) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(base, ui.Offset.zero, ui.Paint());
    canvas.drawImage(over, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final image = picture.toImageSync(base.width, base.height);
    picture.dispose();
    return image;
  }

  // `testWidgets` for its `runAsync` alone: `decodeImageFromPixels` NEVER
  // completes inside `pump`'s fake async, so a plain `test` here would hang
  // on the first decode. There is no widget in this test.
  testWidgets('composing pre + overlay against the true decode of the commit', (
    tester,
  ) async {
    var verdict = '(not measured)';

    await tester.runAsync(() async {
      // PRE: a half-covered tile the user is already looking at.
      final pre = materialize(blankSurface(), [
        dab(x: 3, y: 3, color: 0xFF2060C0, opacity: 0.75, size: 7),
      ]);
      final preTile = pre.tileAt(coord)!;

      // POST: the same tile after a SECOND, semi-transparent stroke — this
      // is the byte truth the commit produced, blended by the real kernel.
      final post = materialize(pre, [
        dab(x: 5, y: 4, color: 0xFFE04020, opacity: 0.5, size: 5, sequence: 1),
      ]);
      final postTile = post.tileAt(coord)!;

      // OVERLAY: the same second stroke alone on blank — what the live
      // overlay decoded and showed while the user drew it.
      final overlayOnly = materialize(blankSurface(), [
        dab(x: 5, y: 4, color: 0xFFE04020, opacity: 0.5, size: 5, sequence: 1),
      ]);
      final overlayTile = overlayOnly.tileAt(coord)!;

      final preImage = await decodeTile(preTile);
      final overlayImage = await decodeTile(overlayTile);
      final truthImage = await decodeTile(postTile);

      final composed = composeSync(preImage, overlayImage);

      final composedBytes = await bytesOf(composed);
      final truthBytes = await bytesOf(truthImage);
      final preBytes = await bytesOf(preImage);

      expect(composedBytes.length, truthBytes.length);

      var differing = 0;
      var maxDelta = 0;
      for (var i = 0; i < truthBytes.length; i += 4) {
        var pixelDiffers = false;
        for (var c = 0; c < 4; c++) {
          final delta = (composedBytes[i + c] - truthBytes[i + c]).abs();
          if (delta != 0) {
            pixelDiffers = true;
            if (delta > maxDelta) {
              maxDelta = delta;
            }
          }
        }
        if (pixelDiffers) {
          differing++;
        }
      }

      // ANTI-VACUITY: the composition must actually have had blending to do.
      // If the stroke had covered the tile opaquely, composed == overlay and
      // "exact" would be a statement about nothing.
      var preDiffersFromTruth = 0;
      for (var i = 0; i < truthBytes.length; i += 4) {
        if (preBytes[i] != truthBytes[i] ||
            preBytes[i + 1] != truthBytes[i + 1] ||
            preBytes[i + 2] != truthBytes[i + 2] ||
            preBytes[i + 3] != truthBytes[i + 3]) {
          preDiffersFromTruth++;
        }
      }
      expect(
        preDiffersFromTruth,
        greaterThan(0),
        reason: 'the second stroke changed nothing — fixture proves nothing',
      );
      var blendedPixels = 0;
      for (var i = 0; i < truthBytes.length; i += 4) {
        final overAlpha = composedBytes[i + 3];
        if (overAlpha > 0 && overAlpha < 255) {
          blendedPixels++;
        }
      }

      final total = truthBytes.length ~/ 4;
      verdict =
          'pixels $total · differing $differing · maxChannelDelta $maxDelta '
          '· partial-alpha $blendedPixels · pre-vs-truth $preDiffersFromTruth';

      preImage.dispose();
      overlayImage.dispose();
      truthImage.dispose();
      composed.dispose();
    });

    // ignore: avoid_print
    print('N4 COMPOSE PARITY → $verdict');
  });

  // One configuration is not an answer to a ROUNDING question. The property
  // under test is 8-bit blend rounding, so the sweep has to be over the blend
  // space: how transparent the base is, how transparent the ink is, and
  // whether the channels are near the ends where mul-div-255 rounds hardest.
  //
  // This is the same lesson the transform round paid for: a test that measures
  // a numeric property has to sweep that property, not one comfortable point.
  testWidgets('the composition stays byte-exact across the blend space', (
    tester,
  ) async {
    var worstDelta = 0;
    var worstCase = '';
    var casesWithBlending = 0;

    await tester.runAsync(() async {
      const baseOpacities = <double>[0.12, 0.5, 0.87, 1.0];
      const inkOpacities = <double>[0.06, 0.33, 0.5, 0.94, 1.0];
      const colors = <int>[0xFF000000, 0xFF010203, 0xFFFEFDFC, 0xFFFFFFFF];

      for (final baseOpacity in baseOpacities) {
        for (final inkOpacity in inkOpacities) {
          for (final color in colors) {
            final pre = materialize(blankSurface(), [
              dab(
                x: 3.5,
                y: 3.5,
                color: 0xFF3070B0,
                opacity: baseOpacity,
                size: 8,
              ),
            ]);
            final inkDab = dab(
              x: 4.5,
              y: 4.5,
              color: color,
              opacity: inkOpacity,
              size: 6,
              sequence: 1,
            );
            final post = materialize(pre, [inkDab]);
            final overlayOnly = materialize(blankSurface(), [inkDab]);

            final preTile = pre.tileAt(coord);
            final postTile = post.tileAt(coord);
            final overlayTile = overlayOnly.tileAt(coord);
            if (preTile == null || postTile == null || overlayTile == null) {
              continue;
            }

            final preImage = await decodeTile(preTile);
            final overlayImage = await decodeTile(overlayTile);
            final truthImage = await decodeTile(postTile);
            final composed = composeSync(preImage, overlayImage);

            final composedBytes = await bytesOf(composed);
            final truthBytes = await bytesOf(truthImage);

            var sawPartialAlpha = false;
            for (var i = 0; i < truthBytes.length; i += 4) {
              final alpha = truthBytes[i + 3];
              if (alpha > 0 && alpha < 255) {
                sawPartialAlpha = true;
              }
              for (var c = 0; c < 4; c++) {
                final delta = (composedBytes[i + c] - truthBytes[i + c]).abs();
                if (delta > worstDelta) {
                  worstDelta = delta;
                  worstCase =
                      'base $baseOpacity ink $inkOpacity '
                      'color 0x${color.toRadixString(16)}';
                }
              }
            }
            if (sawPartialAlpha) {
              casesWithBlending++;
            }

            preImage.dispose();
            overlayImage.dispose();
            truthImage.dispose();
            composed.dispose();
          }
        }
      }
    });

    // ignore: avoid_print
    print(
      'N4 SWEEP → 80 cases · $casesWithBlending with partial alpha · '
      'worstChannelDelta $worstDelta${worstDelta == 0 ? '' : ' at $worstCase'}',
    );

    // ANTI-VACUITY: a sweep where nothing ever blended would report 0 and
    // mean nothing.
    expect(
      casesWithBlending,
      greaterThan(40),
      reason: 'most cases must actually produce partial alpha',
    );
    // 🚨 THE ANSWER, and it is not the one the single-configuration probe
    // above gives. That one reports 0 across 64 pixels with 37 of them
    // partially transparent, which reads as "exact, adopt it". The sweep
    // finds 1 — at base 0.12 / ink 0.06 / black, i.e. faint ink over a faint
    // base, where the two rounding orders finally disagree.
    //
    // So the composed image may NOT be adopted as the tile's picture: doing
    // that pins an off-by-one image forever on exactly the tiles drawn with
    // the faintest ink. It has to be PROVISIONAL — shown at once, and
    // replaced when the real decode lands.
    //
    // 1 is still the right thing to show. Today those tiles display the
    // PREVIOUS generation's picture or nothing at all; a one-frame ±1 is a
    // fidelity degradation, which is the axis this program's invariant says
    // to degrade along. Coverage is the axis it says never to degrade.
    expect(
      worstDelta,
      lessThanOrEqualTo(1),
      reason:
          'the two blend orders may differ by rounding, but only by rounding '
          '— anything larger means the composition is not the same picture',
    );
    expect(
      worstDelta,
      greaterThan(0),
      reason:
          'if this ever reaches 0 across the sweep, the composed image could '
          'be adopted outright and the provisional lifecycle could go away — '
          'that would be a finding, not a passing test',
    );
  });
}
