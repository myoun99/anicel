import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';

/// R26 #18, display half: with a selection, what the pen SHOWS while
/// drawing is confined to it — and is the same bytes the commit lands.
///
/// The selection reaches the PRE-BLEND KERNEL now (it scales the
/// accumulated stroke's alpha), not a painter clipPath. That is what
/// makes these two things true at once, which the clip could never do:
///
///  * outside the selection a result tile equals the base, so the tile
///    still owns its whole coordinate and the painter keeps the
///    replacement fast path (the clip forced a per-frame isolation layer
///    on every selected stroke);
///  * live and committed pixels come out of ONE masked blend, so the
///    boundary cannot disagree — there is no second clipping rule left to
///    keep in sync.
void main() {
  const canvasSize = CanvasSize(width: 40, height: 40);
  const tileSize = 64; // one tile covers the canvas: the aligned grid.

  BrushDab dab(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFF000000,
    size: 8,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  /// The selection: the LEFT half of the canvas.
  final leftHalf = CanvasSelectionRegion.shape(
    CanvasSelectionShape.rect(left: 0, top: 0, right: 20, bottom: 40),
  );

  /// Paper the base so "the base survives outside the selection" is a
  /// visible fact and not just transparency.
  BitmapSurface paintedBase() => materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
    sequence: BrushDabSequence([
      BrushDab(
        center: CanvasPoint(x: 20, y: 20),
        color: 0xFFCC2222,
        size: 40,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
      ),
    ]),
  ).surface;

  /// A horizontal stroke straddling the selection's right edge (x = 20).
  List<BrushDab> straddlingStroke() => [
    for (var x = 6; x <= 34; x += 4) dab(x.toDouble(), 20),
  ];

  Future<Uint8List> paintedBytes({
    required BitmapSurface surface,
    required ActiveStrokeOverlayModel overlay,
  }) async {
    final recorder = ui.PictureRecorder();
    BitmapSurfacePainter(
      surface: surface,
      overlayModel: overlay,
      showTransparentBackground: false,
      // A fresh scope keeps another test's tile at the same coordinate out
      // of the stale-image fallback (the parity suite's rule).
      staleScope: Object(),
    ).paint(Canvas(recorder), const Size(40, 40));
    final image = await recorder.endRecording().toImage(40, 40);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// Draws [dabs] through a rasterizer carrying [region] and returns the
  /// live overlay plus that rasterizer, so a test can take the COMMIT
  /// from the very same stroke.
  Future<(ActiveStrokeOverlayModel, BrushLiveStrokeRasterizer)> liveStroke({
    required BitmapSurface base,
    required List<BrushDab> dabs,
    CanvasSelectionRegion? region,
    BrushBlendMode mode = BrushBlendMode.color,
  }) async {
    final rasterizer = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    )..selectionRegion = region;
    final dirty = rasterizer.blendFrom(dabs, from: 0)!;
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..blendMode = mode
      ..erase = mode == BrushBlendMode.erase
      ..preBlendBase = base;
    addTearDown(model.dispose);
    model.updateRegion(source: rasterizer, region: dirty);
    await model.waitForPendingDecodes();
    return (model, rasterizer);
  }

  int alphaAt(Uint8List pixels, int x, int y) => pixels[(y * 40 + x) * 4 + 3];
  int redAt(Uint8List pixels, int x, int y) => pixels[(y * 40 + x) * 4];

  test(
    'the live stroke shows only inside the selection, and the base '
    'survives outside it — on the ALIGNED grid, where the overlay owns '
    'whole coordinates',
    () async {
      final base = paintedBase();
      final (overlay, rasterizer) = await liveStroke(
        base: base,
        dabs: straddlingStroke(),
        region: leftHalf,
      );
      addTearDown(rasterizer.clear);

      final painted = await paintedBytes(surface: base, overlay: overlay);
      expect(redAt(painted, 10, 20), lessThan(64), reason: 'stroke inside');
      expect(
        redAt(painted, 30, 20),
        greaterThan(160),
        reason: 'the red base survived outside the selection',
      );
      expect(alphaAt(painted, 30, 20), 255, reason: 'no hole punched');
    },
  );

  test(
    'live == committed with a selection: one masked blend feeds both, so '
    'the boundary cannot disagree',
    () async {
      for (final mode in const [
        BrushBlendMode.color,
        BrushBlendMode.multiply,
        BrushBlendMode.erase,
      ]) {
        final base = paintedBase();
        final (overlay, rasterizer) = await liveStroke(
          base: base,
          dabs: straddlingStroke(),
          region: leftHalf,
          mode: mode,
        );
        final live = await paintedBytes(surface: base, overlay: overlay);

        final committed = base.putTiles([
          for (final entry in rasterizer.promoteStrokeTiles(
            base: base,
            mode: mode,
            erase: mode == BrushBlendMode.erase,
          ))
            entry.tile,
        ]);
        rasterizer.clear();
        final empty = ActiveStrokeOverlayModel(tileSize: tileSize);
        addTearDown(empty.dispose);
        final after = await paintedBytes(surface: committed, overlay: empty);

        expect(live, after, reason: '${mode.name}: live display == committed');
      }
    },
  );

  test('a composite region folds through the mask — a subtracted hole '
      'keeps the base', () async {
    final base = paintedBase();
    final withHole = leftHalf
        .combinedWith(
          CanvasSelectionShape.rect(left: 0, top: 0, right: 40, bottom: 40),
          SelectionCombineMode.add,
        )!
        .combinedWith(
          CanvasSelectionShape.rect(left: 14, top: 0, right: 26, bottom: 40),
          SelectionCombineMode.subtract,
        )!;
    final (overlay, rasterizer) = await liveStroke(
      base: base,
      dabs: straddlingStroke(),
      region: withHole,
    );
    addTearDown(rasterizer.clear);

    final painted = await paintedBytes(surface: base, overlay: overlay);
    expect(redAt(painted, 8, 20), lessThan(64), reason: 'left of the hole');
    expect(redAt(painted, 20, 20), greaterThan(160), reason: 'in the hole');
    expect(redAt(painted, 32, 20), lessThan(64), reason: 'right of the hole');
  });

  test('a selection that covers everything paints what NO selection '
      'paints, byte for byte', () async {
    final base = paintedBase();
    final (masked, rasterizerA) = await liveStroke(
      base: base,
      dabs: straddlingStroke(),
      region: CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(
          left: -100,
          top: -100,
          right: 200,
          bottom: 200,
        ),
      ),
    );
    addTearDown(rasterizerA.clear);
    final (plain, rasterizerB) = await liveStroke(
      base: base,
      dabs: straddlingStroke(),
    );
    addTearDown(rasterizerB.clear);

    expect(
      await paintedBytes(surface: base, overlay: masked),
      await paintedBytes(surface: base, overlay: plain),
    );
  });

  test(
    'a stroke entirely outside the selection shows nothing and promotes '
    'nothing — the commit must not touch a tile the stroke could not reach',
    () async {
      final base = paintedBase();
      final (overlay, rasterizer) = await liveStroke(
        base: base,
        dabs: [for (var x = 26; x <= 34; x += 4) dab(x.toDouble(), 20)],
        region: leftHalf,
      );
      addTearDown(rasterizer.clear);

      expect(overlay.tileImages, isEmpty, reason: 'nothing to show');
      expect(
        rasterizer.promoteStrokeTiles(
          base: base,
          mode: BrushBlendMode.color,
          erase: false,
        ),
        isEmpty,
      );
    },
  );
}
