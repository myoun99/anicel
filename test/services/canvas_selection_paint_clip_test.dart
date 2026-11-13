// The first stroke on the engine compiles the executor and the stroke's
// kernels: 40 s on a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show gpuTileSide;
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_paint_clip.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/selection_clip.dart';

import '../helpers/surface_rgba_in_place.dart';

/// R26 #18: painting clips to the selection — the funnel names the
/// selection a stroke lands through, and the commit cuts it there, on the
/// engine (`cutOnTheEngineOnly`). Off the engine's grid what scales a
/// stroke's alpha is its opacity ceiling, by the one coverage rule.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      final clipped = solidBlock(bounds);
      applyCoverageToStrokeAlpha(
        pixels: clipped,
        mask: Uint8List.fromList([
          for (var y = 0; y < 4; y += 1)
            for (var x = 0; x < 4; x += 1) if (x < 2 || y < 2) 0 else 255,
        ]),
        pixelCount: 16,
      );
      expect(
        clipped[3],
        0,
        reason: '(0, 0) has no coverage: no alpha survives',
      );

      final scrubbed = Uint8List.fromList(clipped);
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
        commit(clipped).tileAt(TileCoord(x: 0, y: 0))!.pixels,
        commit(scrubbed).tileAt(TileCoord(x: 0, y: 0))!.pixels,
        reason: 'the colour behind α0 changed nothing',
      );
    },
  );

  group('rasterizeStrokeCoverage (no live raster available)', () {
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

    test('rasterizes the stroke\'s coverage on its own', () {
      final rasterized = rasterizeStrokeCoverage(
        dabs: [dab(20, 20)],
        canvasSize: const CanvasSize(width: 64, height: 64),
        tileSize: 32,
      )!;
      expect(rasterized.bounds.width, greaterThan(0));
      expect(alphaAt(rasterized.pixels, rasterized.bounds, 20, 20), 255);
    });

    test('ERASE dabs rasterize as coverage (the flag is re-applied at the '
        'composite, never inside the buffer)', () {
      final erased = rasterizeStrokeCoverage(
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

  group('applyCoverageToStrokeAlpha — the ONE coverage rule', () {
    // Every path that scales a stroke by its opacity ceiling off the
    // engine's grid calls this: the live pre-blend and the commit's buffer.
    // ↩️It was the selection's rule too till 2026-11-14 (a fill's stamp
    // bytes, the commit clip).
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
      applyCoverageToStrokeAlpha(
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
      applyCoverageToStrokeAlpha(
        pixels: pixels,
        mask: Uint8List.fromList([255, 255]),
        pixelCount: 2,
      );
      expect(pixels, before);
    });
  });

  group('clipStrokeCommitToSelection — ONE funnel for a selection and a '
      "sheet window's slice", () {
    const canvas = CanvasSize(width: 64, height: 64);
    BrushDab dab(double x, double y) => BrushDab(
      center: CanvasPoint(x: x, y: y),
      color: 0xFF0000FF,
      size: 6,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
    );
    BrushStrokeCommitData promotedOn(
      BitmapSurface base,
      List<BrushDab> dabs, {
      bool empty = false,
    }) => BrushStrokeCommitData(
      sourceDabs: dabs,
      promotedBase: base,
      promotedTiles: empty
          ? const []
          : [
              (
                coord: TileCoord(x: 0, y: 0),
                tile: BitmapTile.blank(size: 32),
              ),
            ],
    );

    test('promoted tiles pass straight through on the surface they were '
        'blended against — the kernel already masked them — and the '
        'stroke carries its selection all the same', () {
      final surface = BitmapSurface(canvasSize: canvas, tileSize: 32);
      final data = promotedOn(surface, [dab(10, 10)]);
      final clip = SelectionClip.outline(regionRect(0, 0, 20, 64));
      final passed = clipStrokeCommitToSelection(
        data,
        clip: clip,
        surface: surface,
      )!;
      expect(passed.promotedTiles, same(data.promotedTiles));
      expect(passed.promotedBase, same(surface));
      expect(
        passed.selection,
        same(clip),
        reason: 'a redo onto a cel that moved re-derives it from its dabs',
      );
      expect(
        clipStrokeCommitToSelection(
          promotedOn(surface, [dab(10, 10)], empty: true),
          clip: clip,
          surface: surface,
        ),
        isNull,
        reason: 'an empty promotion lands nothing',
      );
    });

    test('once something has landed on the cel in between, the commit cuts '
        'the stroke where it lands — the whole stroke never lands', () {
      // The selection cuts on the engine's grid (`cutOnTheEngineOnly`).
      final base = BitmapSurface(canvasSize: canvas, tileSize: gpuTileSide);
      final landedSince = BitmapSurface(
        canvasSize: canvas,
        tileSize: gpuTileSide,
      );
      final clip = SelectionClip.outline(regionRect(0, 0, 20, 64));
      final funneled = clipStrokeCommitToSelection(
        promotedOn(base, [dab(10, 10), dab(18, 10), dab(40, 10)]),
        clip: clip,
        surface: landedSince,
      )!;
      expect(funneled.selection, same(clip));
      expect(
        clipStrokeCommitToSelection(
          BrushStrokeCommitData(
            sourceDabs: [dab(10, 10)],
            promotedBase: base,
            promotedTiles: const [],
            end: CanvasPoint(x: 10, y: 10),
          ),
          clip: clip,
          surface: landedSince,
        )!.end,
        CanvasPoint(x: 10, y: 10),
        reason: 'funneled, it is the same stroke, and ended where it did '
            '(I-119)',
      );
      final landed = brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: landedSince,
        sequence: BrushDabSequence(funneled.sourceDabs),
        layerId: const LayerId('row'),
        frameId: const FrameId('cel'),
        promotedBase: funneled.promotedBase,
        promotedTiles: funneled.promotedTiles,
        selection: funneled.selection,
      ).afterSurface;
      int alpha(int x, int y) => (surfaceRgbaInPlace(landed, x, y) ?? 0) & 255;
      expect(alpha(10, 10), 255);
      expect(alpha(19, 10), 255);
      expect(alpha(20, 10), 0, reason: 'the dab straddling the edge is cut at it');
      expect(alpha(40, 10), 0, reason: 'the dab at x=40 lies outside it');
      expect(
        clipStrokeCommitToSelection(
          promotedOn(base, [dab(40, 10)]),
          clip: clip,
          surface: landedSince,
        ),
        isNull,
        reason: 'nothing of it reaches the selection',
      );
    });
  });
}
