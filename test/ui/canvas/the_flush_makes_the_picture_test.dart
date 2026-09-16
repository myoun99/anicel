import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';

/// 🚨★★★THE FLUSH MAKES THE PICTURE (유저 절대규칙 2026-09-17: 「보이는
/// 중이랑 결과랑 절대로 다르면 안 되」). Where the engine uploads
/// synchronously, the overlay's picture of a coordinate and the stroke
/// revision it shows are made inside the very call that pre-blended it —
/// so the pen-up handoff, which runs in the same handler as the final
/// flush, finds an image at every promoted tile's revision. The
/// asynchronous door gets the same bytes; only the moment differs.
void main() {
  const tileSize = 8;
  const canvasSize = CanvasSize(width: 32, height: 32);

  ui.Image solid() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, tileSize * 1.0, tileSize * 1.0),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(tileSize, tileSize);
    picture.dispose();
    return image;
  }

  List<BrushDab> strokeDabs() {
    var sequence = 0;
    return [
      for (var x = 2; x < 16; x += 4)
        for (var y = 0; y < 16; y += 1)
          BrushDab(
            center: CanvasPoint(x: x + 0.5, y: y + 0.5),
            color: 0xFF000000,
            size: 1,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: sequence++,
          ),
    ];
  }

  /// The stroke, pre-blended into [model] the way the interactive view
  /// does it; the rasterizer is handed back for the promotion.
  BrushLiveStrokeRasterizer stroke(ActiveStrokeOverlayModel model) {
    final rasterizer = BrushLiveStrokeRasterizer(
      canvasSize: canvasSize,
      tileSize: tileSize,
    );
    final dabs = strokeDabs();
    final region = rasterizer.blendFrom(dabs, from: 0)!;
    model.dabs.addAll(dabs);
    model.updateRegion(source: rasterizer, region: region);
    return rasterizer;
  }

  tearDown(() {
    debugSyncImageUploadOverride = null;
    debugRawRgbaUploader = null;
  });

  test('with the synchronous door the picture and its revision are there '
      'before updateRegion returns, and pen-up takes every one', () {
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(model.dispose);
    var uploads = 0;
    debugSyncImageUploadOverride = (pixels, width, height) {
      // The door probes itself once with a 1×1 upload; only tiles count.
      if (width == tileSize && height == tileSize) {
        uploads += 1;
      }
      return solid();
    };

    final rasterizer = stroke(model);

    expect(uploads, greaterThan(0));
    expect(
      model.tileImages,
      hasLength(uploads),
      reason: 'every upload is a picture the overlay holds, before '
          'updateRegion returned',
    );
    final promoted = rasterizer.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    expect(promoted, isNotEmpty);
    for (final entry in promoted) {
      expect(
        model.takeTileImageAt(entry.coord, revision: entry.revision),
        isNotNull,
        reason: '${entry.coord}: the handoff must find the image at the '
            'promoted tile\'s own revision — the miss this closes',
      );
    }
    expect(
      model.tileImages.length,
      uploads - promoted.length,
      reason: 'every promoted tile took its image; what stays is a tile '
          'the stroke touched without changing (its picture equals the '
          'base, and it is not promoted)',
    );
  });

  test('the synchronous door is handed the bytes the asynchronous door '
      'would have been', () async {
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    final viaSync = <Uint8List>[];
    final viaAsync = <Uint8List>[];

    debugSyncImageUploadOverride = (pixels, width, height) {
      // The door probes itself once with a 1×1 upload; only tiles count.
      // Copied INSIDE the call: the scratch is released when it returns.
      if (width == tileSize && height == tileSize) {
        viaSync.add(Uint8List.fromList(pixels));
      }
      return solid();
    };
    final syncModel = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(syncModel.dispose);
    stroke(syncModel);
    debugSyncImageUploadOverride = null;

    debugRawRgbaUploader = (rgba, {
      required width,
      required height,
      targetWidth,
      targetHeight,
    }) async {
      viaAsync.add(Uint8List.fromList(rgba));
      return solid();
    };
    final asyncModel = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(asyncModel.dispose);
    stroke(asyncModel);
    await asyncModel.waitForPendingDecodes();

    expect(viaSync, isNotEmpty);
    expect(viaAsync, hasLength(viaSync.length));
    // The tiles arrive in the same order on both doors (one batch, one
    // loop), so the lists compare pairwise.
    for (var i = 0; i < viaSync.length; i += 1) {
      expect(
        viaSync[i],
        viaAsync[i],
        reason: 'tile $i: the same premultiplied result bytes on both doors',
      );
    }
  });
}
