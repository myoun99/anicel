import 'dart:ui' as ui;

import '../../models/canvas_size.dart';

/// The pixel size one page rasters at: the caller's [outputSize] when it
/// names one, otherwise the page's natural size at [scale].
///
/// An explicit size WINS over the scale — the preview asks for a thumbnail
/// at a size it chose and must get exactly that, whatever run scale the
/// export settings carry.
({int width, int height}) offscreenRasterSize({
  required double naturalWidth,
  required double naturalHeight,
  required double scale,
  CanvasSize? outputSize,
}) => (
  width: outputSize?.width ?? (naturalWidth * scale).round(),
  height: outputSize?.height ?? (naturalHeight * scale).round(),
);

/// One offscreen raster: a recorder, a canvas handed to [paint], the
/// picture rasterised at [width] × [height] and disposed once the image
/// is in hand. The recorder lifetime the export renderers share (the
/// round-8 audit, 2026-09-06 — conte, envelope, timesheet and instruction
/// each wrote it; the conte and envelope copies returned the `toImage`
/// future without awaiting it and so disposed the picture before the
/// raster had read it).
///
/// [paint] runs ONCE per rendered page — the callback is per image, never
/// per pixel.
Future<ui.Image> rasterizeOffscreen({
  required int width,
  required int height,
  required void Function(ui.Canvas canvas) paint,
}) async {
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}
