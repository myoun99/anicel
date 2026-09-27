import 'package:flutter/widgets.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';

/// Where [rect] (canvas space) lies along [axis] on screen, with the pan
/// taken out: where it starts and how long it is. Under a rotation or a
/// flip it is the span of the mapped corners — the silhouette, not the raw
/// rect.
///
/// ONE projection for the two things that ask it: the pan bars
/// (`CanvasViewportPanMetrics`) and the view's limit ([viewHeldTo]) — so
/// the bar cannot offer a place the limit refuses.
({double start, double extent}) viewportSpan(
  Axis axis,
  CanvasViewport viewport,
  Rect rect,
) {
  final horizontal = axis == Axis.horizontal;
  if (!viewport.hasRotationOrFlip) {
    final start = horizontal ? rect.left : rect.top;
    final extent = horizontal ? rect.width : rect.height;
    return (start: start * viewport.zoom, extent: extent * viewport.zoom);
  }
  final unpanned = viewport.copyWith(panX: 0, panY: 0);
  var min = double.infinity;
  var max = double.negativeInfinity;
  for (final corner in [
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ]) {
    final mapped = unpanned.canvasToViewport(
      CanvasPoint(x: corner.dx, y: corner.dy),
    );
    final value = horizontal ? mapped.x : mapped.y;
    min = value < min ? value : min;
    max = value > max ? value : max;
  }
  return (start: min, extent: max - min);
}

/// [view] moved the least that keeps [limit] (canvas space) over [window]
/// (the panel's layout coordinates) — the pan only; the zoom, the rotation
/// and the flips are the view's own.
///
/// 🗣️F-201 (유저 2026-09-27): 「스크롤 최대치가 너무 커서? 그림이 밖으로
/// 빠져나가는데 좀 줄여서 … 다른 미디어 뷰어 프로그램이 그러니까」, answered
/// `edge` (F-201-pan-limit-Q1: 「끝이 화면 가장자리에 딱 닿는다」):
///
///  * along an axis where the paper is at least as long as the window,
///    neither of its edges comes inside the window's — you reach its end
///    and the view stops there;
///  * along one where it is shorter, it stands in the window's middle.
///
/// [view] itself when it already stands so — nothing is copied. ⚠️"So"
/// allows a float's dust: a view that went through the device-unit store
/// comes back a hair off where it was held, and holding it again would be
/// a write for nothing.
CanvasViewport viewHeldTo(
  CanvasViewport view, {
  required Rect limit,
  required Rect window,
}) {
  double held(Axis axis, double pan) {
    final span = viewportSpan(axis, view, limit);
    final horizontal = axis == Axis.horizontal;
    final low = horizontal ? window.left : window.top;
    final high = horizontal ? window.right : window.bottom;
    final middle = (low + high) / 2 - (span.start + span.extent / 2);
    final (first, last) = span.extent <= high - low
        ? (middle, middle)
        : (high - span.start - span.extent, low - span.start);
    if (pan >= first - _dust && pan <= last + _dust) {
      return pan;
    }
    return pan.clamp(first, last).toDouble();
  }

  final panX = held(Axis.horizontal, view.panX);
  final panY = held(Axis.vertical, view.panY);
  if (panX == view.panX && panY == view.panY) {
    return view;
  }
  return view.copyWith(panX: panX, panY: panY);
}

/// A millionth of a layout pixel — far below anything a view can show.
const double _dust = 1e-6;
