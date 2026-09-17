import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';

import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';

/// 🚨★★★**THE OVERLAY PASS DREW EVERY COORDINATE THE STROKE EVER
/// TOUCHED.** The committed pass walks `tilesUnderRect(surface,
/// visibleRect)` and has since the walk went visible-only; the overlay
/// pass beside it iterated its whole image map. Overlay tiles ACCUMULATE
/// — nothing leaves the map until pen-up — so by the third dab that map
/// is the bounding box of the WHOLE stroke, and a long line paid its
/// full length in `drawImage` calls on every frame of every dab.
///
/// ⚠️**A PIXEL TEST CANNOT SEE THIS.** Everything past the clip is
/// composited away either way, so a screenshot is identical before and
/// after — which is exactly why the two passes could disagree for so
/// long. The assertion has to be about what the painter RECORDS, so this
/// drives it with a spy canvas and asks which coordinates reached
/// `drawImage`.
class _SpyCanvas implements Canvas {
  _SpyCanvas(this._clip);

  final Rect _clip;
  final List<Offset> imageOffsets = <Offset>[];

  @override
  Rect getLocalClipBounds() => _clip;

  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) {
    imageOffsets.add(offset);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const tileSize = 64;
  const canvasSize = CanvasSize(width: 512, height: 128);

  /// An overlay holding decoded images at two coordinates: one inside the
  /// clip below, one far outside it.
  Future<ActiveStrokeOverlayModel> overlayWithTwoTiles() async {
    final rasterizer = BrushLiveStrokeRasterizer(canvasSize: canvasSize);
    final model = ActiveStrokeOverlayModel(tileSize: tileSize);
    addTearDown(model.dispose);

    // One dab in tile (0, 0), one in tile (6, 0) — 384 canvas px apart.
    for (final centre in [
      CanvasPoint(x: 32, y: 32),
      CanvasPoint(x: 416, y: 32),
    ]) {
      final dab = BrushDab(
        center: centre,
        size: 16,
        opacity: 1.0,
        flow: 1.0,
        hardness: 0.5,
        pressure: 1.0,
        color: 0xFF000000,
        sequence: 0,
        tipShape: BrushTipShape.round,
      );
      rasterizer.blendFrom([dab], from: 0);
      model.dabs.add(dab);
      model.updateRegion(
        source: rasterizer,
        region: DirtyRegion(
          left: (centre.x - 8).floor(),
          top: (centre.y - 8).floor(),
          rightExclusive: (centre.x + 8).ceil(),
          bottomExclusive: (centre.y + 8).ceil(),
        ),
      );
    }

    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (model.tileImages.length >= 2) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      model.tileImages.length,
      2,
      reason: 'setup: the overlay must hold both coordinates',
    );
    return model;
  }

  test('the overlay pass draws only the tiles under the visible rect', () async {
    final model = await overlayWithTwoTiles();
    // Anti-vacuity: the far tile genuinely lies outside the clip, so a
    // pass that draws it is drawing something it did not have to.
    final far = model.tileImages.keys.reduce((a, b) => a.x > b.x ? a : b);
    expect(far.x * tileSize, greaterThan(128));

    final canvas = _SpyCanvas(const Rect.fromLTWH(0, 0, 128, 128));
    BitmapSurfacePainter(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
      overlayModel: model,
      showTransparentBackground: false,
      lineage: Object(),
    ).paintContentInto(canvas);

    expect(
      canvas.imageOffsets.map((offset) => offset.dx),
      everyElement(lessThan(128)),
      reason: 'a coordinate past the clip must never reach drawImage',
    );
    expect(
      canvas.imageOffsets,
      isNotEmpty,
      reason: 'and the visible one must still be drawn',
    );
  });
}
