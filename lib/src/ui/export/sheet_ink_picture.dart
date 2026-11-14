import 'dart:ui' as ui;

import '../../models/bitmap_surface.dart';
import '../../models/pasteboard_bounds.dart';
import '../../services/brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import '../../services/cel_text_laying.dart' show celSurfaceWithTextsLaid;
import '../../services/straight_rgba_image.dart'
    show decodeStraightRgbaImageOnAWorker;
import '../canvas/chained_picture.dart' show chainedPictureOf;

/// [surface]'s ink over its canvas as an export's sheet shows it — with the
/// texts it carries laid over it ([celSurfaceWithTextsLaid]) — its straight
/// pixels premultiplied on a worker and uploaded
/// ([decodeStraightRgbaImageOnAWorker]), as the picture a sheet lays
/// reduced (`paintSheetInkWindow`) and so with its chain
/// ([chainedPictureOf]). The caller's to dispose.
///
/// ↩️It was composed from its tiles' pictures, a block that had none
/// premultiplied by the C engine (`composeTiledSurfaceImage`) — until an
/// export left the C premultiply (export-on-engine ⑶-2b, 2026-11-12).
Future<ui.Image> sheetInkPictureOf(BitmapSurface surface) async {
  final canvas = surface.canvasSize;
  final uploaded = await decodeStraightRgbaImageOnAWorker(
    rgba: bitmapSurfaceRegionPixels(
      celSurfaceWithTextsLaid(surface),
      canvas.canvasRegion,
    ),
    width: canvas.width,
    height: canvas.height,
  );
  try {
    return chainedPictureOf(uploaded);
  } finally {
    // Safe once drawn into the render: the draw holds its own claim.
    uploaded.dispose();
  }
}
