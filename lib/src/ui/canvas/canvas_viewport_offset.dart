import 'dart:ui' show Offset;

import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../../models/viewport_point.dart';

/// The viewport's canvas-to-screen map both ways, in the [Offset] that
/// painters, hit tests and pointer events work in.
///
/// ⛔One place for it: ten sites each spelled
/// [CanvasViewport.canvasToViewport] and then `Offset(mapped.x, mapped.y)`,
/// and six wrapped a pointer's position in a [ViewportPoint] to go back —
/// five of them as private helpers of their own. The model keeps its own
/// point types and no `dart:ui`, so the conversion lives on this side of it.
extension CanvasViewportOffset on CanvasViewport {
  Offset canvasToViewportOffset(CanvasPoint point) {
    final mapped = canvasToViewport(point);
    return Offset(mapped.x, mapped.y);
  }

  CanvasPoint viewportOffsetToCanvas(Offset local) =>
      viewportToCanvas(ViewportPoint(x: local.dx, y: local.dy));
}
