import 'package:flutter/widgets.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../widgets/app_scrollbar_lane.dart';

/// The canvas panbar's AXIS PROJECTION: what the rotated, flipped, zoomed
/// canvas spans along one axis, and how the viewport's pan reads as a
/// scroll offset over that span.
///
/// ⛔It does NOT compute a thumb. The thumb law — proportional extent, the
/// app-wide minimum, the travel and the start — is `AppScrollbarGeometry`,
/// which `AppScrollbar` builds for itself from [visibleExtent],
/// [scaledContentExtent] and [scrollOffset]. This class carried a second
/// copy of that arithmetic, so every panbar build ran it TWICE and the
/// copy answered nobody but its own test.
class CanvasViewportPanMetrics {
  CanvasViewportPanMetrics({
    required this.axis,
    required this.viewport,
    required this.editorViewportSize,
    required this.canvasSize,
  }) : visibleExtent = _visibleExtent(axis, editorViewportSize) {
    // The canvas content's viewport-space AABB (pan excluded): under
    // rotation/flip the panbar tracks the rotated silhouette, not the raw
    // canvas rect. The scrollable CONTENT then spans paper×3 (UI-R18
    // #16, the pro-canvas convention): one full canvas of runway on each
    // side, so zoom-anchored pans stay inside the model (no snap on
    // thumb grab) and a canvas smaller than the panel still pans.
    final bounds = _contentBounds(axis, viewport, canvasSize);
    final runway = finiteNonNegativeExtent(bounds.extent);
    scaledContentExtent = finiteNonNegativeExtent(bounds.extent + 2 * runway);
    _contentOffset = bounds.start - runway;
    maxScroll = scrollRangeFor(
      contentExtent: scaledContentExtent,
      viewportExtent: visibleExtent,
    );
  }

  final Axis axis;
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;
  late final double scaledContentExtent;
  final double visibleExtent;
  late final double maxScroll;

  /// The content AABB's start along [axis] relative to the pan (0 without
  /// rotation/flip, where the canvas origin IS the content start).
  late final double _contentOffset;

  /// The viewport's position along [axis] in scroll-offset space
  /// (0..[maxScroll]) — the seam the shared scrollbar drives through.
  double get scrollOffset {
    final pan = axis == Axis.horizontal ? viewport.panX : viewport.panY;
    return (-(pan + _contentOffset)).clamp(0.0, maxScroll).toDouble();
  }

  /// The offset-space inverse of [scrollOffset]: only THIS axis's pan is
  /// written. Never clamp the other axis here — the canvas pans freely (a
  /// zoomed-in paper may sit at a positive pan), and a both-axes clamp used
  /// to snap the paper left-aligned the moment the vertical bar was touched.
  CanvasViewport viewportForScroll(double scroll) {
    if (maxScroll <= 0) {
      return viewport;
    }
    final clamped = scroll.clamp(0.0, maxScroll).toDouble();
    return axis == Axis.horizontal
        ? viewport.copyWith(panX: -clamped - _contentOffset)
        : viewport.copyWith(panY: -clamped - _contentOffset);
  }

  static ({double start, double extent}) _contentBounds(
    Axis axis,
    CanvasViewport viewport,
    CanvasSize canvasSize,
  ) {
    if (!viewport.hasRotationOrFlip) {
      final source = axis == Axis.horizontal
          ? canvasSize.width
          : canvasSize.height;
      return (start: 0, extent: source * viewport.zoom);
    }
    final unpanned = viewport.copyWith(panX: 0, panY: 0);
    final width = canvasSize.width.toDouble();
    final height = canvasSize.height.toDouble();
    double? min;
    double? max;
    for (final corner in [
      CanvasPoint(x: 0, y: 0),
      CanvasPoint(x: width, y: 0),
      CanvasPoint(x: width, y: height),
      CanvasPoint(x: 0, y: height),
    ]) {
      final mapped = unpanned.canvasToViewport(corner);
      final value = axis == Axis.horizontal ? mapped.x : mapped.y;
      min = min == null || value < min ? value : min;
      max = max == null || value > max ? value : max;
    }
    return (start: min!, extent: max! - min);
  }

  static double _visibleExtent(Axis axis, Size editorViewportSize) {
    final source = axis == Axis.horizontal
        ? editorViewportSize.width
        : editorViewportSize.height;
    return finiteNonNegativeExtent(source);
  }
}
