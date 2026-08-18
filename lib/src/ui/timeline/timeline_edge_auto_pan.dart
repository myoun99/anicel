import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// How far a drag at [pos] has pushed past either end of a [extent]-long
/// axis, once it enters the [edge]-wide band at either end: negative near
/// the start, positive near the end, zero in the middle. The caller adds
/// this to its scroll offset to auto-pan.
///
/// Every timeline and storyboard edge-scroll shares this 24px band, so the
/// band width and the past-the-edge math live here once.
///
/// The band NARROWS with the viewport, never past a quarter of it, so half
/// the viewport is always neutral middle.
///
/// R10 R6 made small viewports reachable for the first time — the x-sheet's
/// frame rail is 66–96px at real dock heights and can be smaller — and a
/// fixed 24px band there is most of the rail: two of them leave 18px of
/// middle in a 66px rail, so a plain press (the rail scrubs from
/// `onPointerDown`, not only from a drag) reads as an edge push and the
/// playhead runs away under a stationary pen. Zeroing only below 48px, as
/// the first fix did, was a cliff rather than an answer: it left every
/// viewport a user can actually produce on the wrong side of it.
/// The scroll offset that brings `[start, start + extent)` inside a
/// [viewport]-long window currently at [offset], or [offset] unchanged when
/// it is already there.
///
/// R5 (user, 2026-08-09): the arrow keys walk rows and frames, and the walk
/// used to leave the viewport behind — you kept selecting things you could
/// not see. NEAREST-EDGE reveal, like every list in every editor: it moves
/// the least it can, so a step that only just goes off screen brings the
/// view along by one step instead of re-centring and losing your place.
///
/// [margin] keeps a sliver of the neighbour visible past the revealed item,
/// which is what makes a walk read as a walk rather than as a series of
/// jumps to the very edge. A margin the viewport cannot afford stands down
/// instead of fighting itself.
double revealScrollOffset({
  required double offset,
  required double viewport,
  required double start,
  required double extent,
  double margin = 0,
}) {
  if (viewport <= 0) {
    return offset;
  }
  final pad = math.min(margin, math.max(0.0, (viewport - extent) / 2));
  if (start - pad < offset) {
    return start - pad;
  }
  final end = start + extent + pad;
  if (end > offset + viewport) {
    return end - viewport;
  }
  return offset;
}

double edgeAutoPanDelta(double pos, double extent, {double edge = 24.0}) {
  if (extent <= 0) {
    return 0;
  }
  final band = math.min(edge, extent / 4);
  if (pos > extent - band) {
    return pos - (extent - band);
  }
  if (pos < band) {
    return pos - band;
  }
  return 0;
}

/// The ONE apply tail every drag-borne edge pan shares (D42): find the
/// nearest [axis] scrollable above [context], read the pointer in its
/// viewport's frame, ask [edgeAutoPanDelta], clamp into the scroll extent,
/// jump, and return what was actually applied.
///
/// The caller MUST fold the returned delta back into its travel — the
/// content moving under a stationary pointer is the same thing as the
/// pointer moving over stationary content, so a travel that ignores it
/// freezes the moment the view begins to scroll.
///
/// Per POINTER MOVE, no timer (the row drag's convention): holding still
/// at the edge holds still; it is the reaching that scrolls. Clamped at
/// BOTH extents — the ruler/rail scrubs that deliberately overshoot to
/// grow frames (UI-R12 #16) keep their own tails.
double edgeAutoPanApply({
  required BuildContext context,
  required Offset globalPosition,
  required Axis axis,
}) {
  final scrollable = Scrollable.maybeOf(context, axis: axis);
  final viewport = scrollable?.context.findRenderObject();
  if (scrollable == null || viewport is! RenderBox || !viewport.hasSize) {
    return 0;
  }
  final local = viewport.globalToLocal(globalPosition);
  final horizontal = axis == Axis.horizontal;
  final delta = edgeAutoPanDelta(
    horizontal ? local.dx : local.dy,
    horizontal ? viewport.size.width : viewport.size.height,
  );
  if (delta == 0) {
    return 0;
  }
  final position = scrollable.position;
  final target = (position.pixels + delta).clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  final applied = target - position.pixels;
  if (applied == 0) {
    return 0;
  }
  position.jumpTo(target);
  return applied;
}
