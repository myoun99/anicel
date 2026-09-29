import 'dart:ui' show Offset;

import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';

/// The viewport's canvas-to-screen map, answered as the [Offset] that
/// painters and hit tests work in.
///
/// ⛔One place for it: ten sites each spelled
/// [CanvasViewport.canvasToViewport] and then `Offset(mapped.x, mapped.y)`,
/// three of them as private helpers of their own. The model keeps its own
/// point types and no `dart:ui`, so the conversion lives on this side of it.
extension CanvasViewportOffset on CanvasViewport {
  Offset canvasToViewportOffset(CanvasPoint point) {
    final mapped = canvasToViewport(point);
    return Offset(mapped.x, mapped.y);
  }
}
