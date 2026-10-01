import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';

/// A blank cel for `InteractiveBrushEditCanvasView.celNow`: made ONCE, where
/// this is called, and handed back every time the view asks — as a host's
/// cel stays the same object until an edit replaces it. A closure that made
/// a new surface per call would hand the view a different cel at every
/// read, which no host does.
BitmapSurface Function() blankCel(
  CanvasSize canvasSize, {
  required int tileSize,
}) {
  final cel = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
  return () => cel;
}
