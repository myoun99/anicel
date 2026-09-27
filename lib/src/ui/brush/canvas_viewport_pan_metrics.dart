import 'package:flutter/widgets.dart';

import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../widgets/app_scrollbar_lane.dart';
import 'canvas_view_limit.dart';

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
    this.limit,
  }) : visibleExtent = limit == null
           ? _visibleExtent(axis, editorViewportSize)
           : finiteNonNegativeExtent(_along(axis, limit.window).extent) {
    final limit = this.limit;
    if (limit != null) {
      // A canvas with a LIMIT (F-201): the bar spans the paper and nothing
      // past it, over the window the view is held in — so its two ends are
      // the two places the view stops ([viewHeldTo]).
      final bounds = viewportSpan(axis, viewport, limit.rect);
      scaledContentExtent = finiteNonNegativeExtent(bounds.extent);
      _contentOffset = bounds.start - _along(axis, limit.window).start;
    } else {
      // The canvas content's viewport-space AABB (pan excluded): under
      // rotation/flip the panbar tracks the rotated silhouette, not the
      // raw canvas rect. The scrollable CONTENT then spans paper×3 (UI-R18
      // #16, the pro-canvas convention): one full canvas of runway on each
      // side, so zoom-anchored pans stay inside the model (no snap on
      // thumb grab) and a canvas smaller than the panel still pans.
      final bounds = viewportSpan(axis, viewport, canvasSize.canvasRect);
      final runway = finiteNonNegativeExtent(bounds.extent);
      scaledContentExtent = finiteNonNegativeExtent(
        bounds.extent + 2 * runway,
      );
      _contentOffset = bounds.start - runway;
    }
    maxScroll = scrollRangeFor(
      contentExtent: scaledContentExtent,
      viewportExtent: visibleExtent,
    );
  }

  final Axis axis;
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;

  /// The view's limit and the window it is held in
  /// (`BrushCanvasPanel.viewLimit`) — null for a canvas that pans freely.
  final ({Rect rect, Rect window})? limit;

  late final double scaledContentExtent;
  final double visibleExtent;
  late final double maxScroll;

  /// The content AABB's start along [axis] relative to the pan (0 without
  /// rotation/flip, where the canvas origin IS the content start) — and,
  /// under a [limit], relative to the window's start as well.
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

  /// [rect]'s span along [axis], in its own coordinates.
  static ({double start, double extent}) _along(Axis axis, Rect rect) =>
      axis == Axis.horizontal
      ? (start: rect.left, extent: rect.width)
      : (start: rect.top, extent: rect.height);

  static double _visibleExtent(Axis axis, Size editorViewportSize) {
    final source = axis == Axis.horizontal
        ? editorViewportSize.width
        : editorViewportSize.height;
    return finiteNonNegativeExtent(source);
  }
}
