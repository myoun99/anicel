import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_paint_clip.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';

/// R26 #18: painting clips to the selection. The clip runs on the
/// stroke's own straight-alpha buffer, which is why one pass covers every
/// brush blend mode (alpha 0 = "destination survives" for all of them).
void main() {
  CanvasSelectionRegion regionRect(double l, double t, double r, double b) =>
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: l, top: t, right: r, bottom: b),
      );

  /// A solid opaque red block covering [bounds].
  Uint8List solidBlock(DirtyRegion bounds) {
    final pixels = Uint8List(bounds.width * bounds.height * 4);
    for (var i = 0; i < bounds.width * bounds.height; i += 1) {
      pixels[i * 4] = 255;
      pixels[i * 4 + 3] = 255;
    }
    return pixels;
  }

  int alphaAt(Uint8List pixels, DirtyRegion bounds, int x, int y) =>
      pixels[((y - bounds.top) * bounds.width + (x - bounds.left)) * 4 + 3];

  test('pixels inside the region survive, pixels outside are zeroed', () {
    final bounds = DirtyRegion.fromLTBR(
      left: 0,
      top: 0,
      rightExclusive: 20,
      bottomExclusive: 20,
    );
    final clipped = clipStrokePixelsToSelection(
      pixels: solidBlock(bounds),
      bounds: bounds,
      region: regionRect(5, 5, 15, 15),
    )!;
    expect(alphaAt(clipped.pixels, bounds, 10, 10), 255);
    expect(alphaAt(clipped.pixels, bounds, 2, 2), 0);
    expect(alphaAt(clipped.pixels, bounds, 17, 17), 0);
  });

  test(
    'colour left behind α0 cannot reach the canvas — the commit is '
    'identical to one whose excluded texels were zeroed outright',
    () {
      // The mask scales ALPHA and leaves RGB alone, because that is what
      // the pre-blend kernel does and the two must be one rule. Safe
      // because alpha 0 is every commit kernel's "destination survives"
      // input: none of them read the colour behind it. This pins that
      // property rather than the byte pattern, so the rule can stay
      // unified without anyone having to trust a comment.
      final bounds = DirtyRegion.fromLTBR(
        left: 0,
        top: 0,
        rightExclusive: 4,
        bottomExclusive: 4,
      );
      final clipped = clipStrokePixelsToSelection(
        pixels: solidBlock(bounds),
        bounds: bounds,
        region: regionRect(2, 2, 4, 4),
      )!;
      expect(
        clipped.pixels[3],
        0,
        reason: '(0, 0) is outside the selection: no alpha survives',
      );

      final scrubbed = Uint8List.fromList(clipped.pixels);
      for (var i = 0; i < bounds.width * bounds.height; i += 1) {
        if (scrubbed[i * 4 + 3] == 0) {
          scrubbed[i * 4] = 0;
          scrubbed[i * 4 + 1] = 0;
          scrubbed[i * 4 + 2] = 0;
        }
      }

      BitmapSurface commit(Uint8List pixels) => materializeBrushDabSequenceOnBitmapSurface(
        surface: BitmapSurface(
          canvasSize: const CanvasSize(width: 8, height: 8),
          tileSize: 8,
        ),
        sequence: BrushDabSequence([
          BrushDab(
            center: CanvasPoint(x: 2, y: 2),
            color: 0xFF000000,
            size: 4,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: 0,
            stamp: BrushStampImage(
              id: 'clip-test-${pixels.hashCode}',
              width: bounds.width,
              height: bounds.height,
              rgba: pixels,
            ),
          ),
        ]),
      ).surface;

      expect(
        commit(clipped.pixels).tileAt(TileCoord(x: 0, y: 0))!.pixels,
        commit(scrubbed).tileAt(TileCoord(x: 0, y: 0))!.pixels,
        reason: 'the colour behind α0 changed nothing',
      );
    },
  );

  test('a stroke entirely outside the selection clips to NOTHING', () {
    final bounds = DirtyRegion.fromLTBR(
      left: 0,
      top: 0,
      rightExclusive: 4,
      bottomExclusive: 4,
    );
    expect(
      clipStrokePixelsToSelection(
        pixels: solidBlock(bounds),
        bounds: bounds,
        region: regionRect(50, 50, 60, 60),
      ),
      isNull,
    );
  });

  test('the composite region clips through the SAME fold (hole stays out)', () {
    final bounds = DirtyRegion.fromLTBR(
      left: 0,
      top: 0,
      rightExclusive: 20,
      bottomExclusive: 20,
    );
    final region = regionRect(
      0,
      0,
      20,
      20,
    ).combinedWith(
      CanvasSelectionShape.rect(left: 8, top: 8, right: 12, bottom: 12),
      SelectionCombineMode.subtract,
    )!;
    final clipped = clipStrokePixelsToSelection(
      pixels: solidBlock(bounds),
      bounds: bounds,
      region: region,
    )!;
    expect(alphaAt(clipped.pixels, bounds, 2, 2), 255);
    expect(alphaAt(clipped.pixels, bounds, 10, 10), 0, reason: 'in the hole');
  });

  group('rasterizeStrokeForClipping (no live raster available)', () {
    BrushDab dab(double x, double y, {bool erase = false}) => BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: 0xFF0000FF,
      size: 6,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
      erase: erase,
    );

    test('rasterizes coverage the clip can then cut', () {
      final rasterized = rasterizeStrokeForClipping(
        dabs: [dab(20, 20)],
        canvasSize: const CanvasSize(width: 64, height: 64),
        tileSize: 32,
      )!;
      expect(rasterized.bounds.width, greaterThan(0));
      final clipped = clipStrokePixelsToSelection(
        pixels: rasterized.pixels,
        bounds: rasterized.bounds,
        region: regionRect(0, 0, 20, 64),
      );
      // The dab straddles x = 20, so the left half survives the clip.
      expect(clipped, isNotNull);
    });

    test('ERASE dabs rasterize as coverage (the flag is re-applied at the '
        'composite, never inside the buffer)', () {
      final erased = rasterizeStrokeForClipping(
        dabs: [dab(20, 20, erase: true)],
        canvasSize: const CanvasSize(width: 64, height: 64),
        tileSize: 32,
      );
      // Erasing an EMPTY scratch surface would produce nothing at all; the
      // helper flips the flag so the coverage is there to clip.
      expect(erased, isNotNull);
      expect(
        erased!.pixels.any((byte) => byte != 0),
        isTrue,
        reason: 'coverage, not an empty buffer',
      );
    });
  });

  group('applySelectionMaskToStrokeAlpha — the ONE selection rule', () {
    // Every path that confines a stroke to a selection calls this: the
    // live pre-blend's Dart route, the commit clip above, and a fill's
    // stamp bytes. The C kernel's qa_mask_alpha is a transcription of it
    // (pinned in stroke_overlay_pre_blend_parity_test.dart).
    test('scales alpha by coverage with Skia mul-div-255 rounding', () {
      // The case the old rules only agreed on by accident. "Zero the
      // texel outside" and "scale alpha" are the same thing at coverage
      // 0 and 255 — the whole disagreement lives in between, which is
      // exactly where the selection tool's feather/AA knobs will put it.
      final pixels = Uint8List.fromList([
        10, 20, 30, 200, //
        10, 20, 30, 200,
        10, 20, 30, 200,
        10, 20, 30, 0,
      ]);
      applySelectionMaskToStrokeAlpha(
        pixels: pixels,
        mask: Uint8List.fromList([255, 128, 0, 128]),
        pixelCount: 4,
      );

      int mul255Round(int value, int alpha) {
        final product = value * alpha + 128;
        return (product + (product >> 8)) >> 8;
      }

      expect(pixels[3], 200, reason: 'full coverage leaves alpha alone');
      expect(pixels[7], mul255Round(200, 128), reason: 'half coverage');
      expect(pixels[11], 0, reason: 'zero coverage');
      expect(pixels[15], 0, reason: 'no alpha to scale');
      expect(
        [pixels[4], pixels[5], pixels[6]],
        [10, 20, 30],
        reason: 'colour is never touched — the kernel does not touch it '
            'either, and alpha 0 hides it from every commit kernel',
      );
    });

    test('a full-coverage mask is a no-op, byte for byte', () {
      final pixels = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final before = Uint8List.fromList(pixels);
      applySelectionMaskToStrokeAlpha(
        pixels: pixels,
        mask: Uint8List.fromList([255, 255]),
        pixelCount: 2,
      );
      expect(pixels, before);
    });
  });
}
