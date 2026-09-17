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
/// The window a reveal measures against: where it is scrolled to, and how
/// long it is.
typedef ScrollWindow = ({double offset, double viewport});

/// The item a reveal is for: where it starts, how long it is, and how much
/// of its neighbour to keep visible past it.
typedef RevealedItem = ({double start, double extent, double margin});

double revealScrollOffset(ScrollWindow window, RevealedItem item) {
  if (window.viewport <= 0) {
    return window.offset;
  }
  final pad = math.min(
    item.margin,
    math.max(0.0, (window.viewport - item.extent) / 2),
  );
  if (item.start - pad < window.offset) {
    return item.start - pad;
  }
  final end = item.start + item.extent + pad;
  if (end > window.offset + window.viewport) {
    return end - window.viewport;
  }
  return window.offset;
}

/// The scroll offset that PAGES a [window] to [item] — it stands at the
/// window's start, or the window does not move at all.
///
/// 🚨F-110 (유저 2026-09-12): 「재생시에도 플레이헤드 밖 나갈때 스크롤하도록.
/// **룰러 드래그랑은 다르게 다음 페이지? 로 간다는 느낌**임. 뭐냐면 넘어가면
/// **룰러가 왼쪽에 오도록 스크롤바 한번만 이동**」.
///
/// ⛔THE OPPOSITE OF [revealScrollOffset], ON PURPOSE. A walk moves the
/// least it can, so a step that only just goes off screen brings the view
/// along by one step and you keep your place. Playback is not walking: the
/// playhead crosses the whole window every few seconds, and a nearest-edge
/// reveal would drag the view under it continuously. One jump per window,
/// and the frame that left stands at the start of the new one.
///
/// ⚠️[RevealedItem.margin] is NOT read here, and that is the decision, not
/// an oversight: a margin is exactly what makes a walk read as a walk
/// rather than as a jump to the very edge, and this IS the jump to the very
/// edge — 유저 asked for the ruler to come to the left. The type is shared
/// because the callers already hold one and the two laws must be swappable
/// at a call site.
double pageScrollOffset(ScrollWindow window, RevealedItem item) {
  if (window.viewport <= 0) {
    return window.offset;
  }
  final inside =
      item.start >= window.offset &&
      item.start + item.extent <= window.offset + window.viewport;
  return inside ? window.offset : item.start;
}

/// Applies [law] to [controller]'s live position, within the scrollable's
/// own range, and not at all when it would not move.
///
/// ⛔The tail is written ONCE. [jumpToReveal] and [jumpToPage] differ in the
/// offset they ask for and in nothing else; two copies of a clamp-and-jump
/// is how the two laws start disagreeing about the range.
void _jumpUsing(
  ScrollController controller,
  RevealedItem item,
  double Function(ScrollWindow window, RevealedItem item) law,
) {
  final position = controller.position;
  final target = law((
    offset: position.pixels,
    viewport: position.viewportDimension,
  ), item).clamp(position.minScrollExtent, position.maxScrollExtent);
  if (target != position.pixels) {
    controller.jumpTo(target);
  }
}

/// Jumps [controller] the least it can ([revealScrollOffset]) so [item] is
/// on screen with its margin of the neighbour, within the scrollable's own
/// range — and not at all when it already is.
void jumpToReveal(ScrollController controller, RevealedItem item) =>
    _jumpUsing(controller, item, revealScrollOffset);

/// Turns the page under [controller] so [item] stands at the window's start
/// ([pageScrollOffset]), within the scrollable's own range — and not at all
/// when it is already inside.
void jumpToPage(ScrollController controller, RevealedItem item) =>
    _jumpUsing(controller, item, pageScrollOffset);

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

/// The OVERSHOOTING twin of [edgeAutoPanApply]'s tail: pans [controller]
/// by [delta] with no upper clamp, so a ruler or rail scrub reaches past
/// the last built cell (UI-R12 #16) and the growth listener materializes
/// the frames the overshot view needs — while the scrollbar and the
/// scroll physics stay clamped at the built extent.
///
/// ⛔THREE SCRUBS "KEEP THEIR OWN TAIL", AND IT IS ONE TAIL. The clamped
/// apply above cannot serve them, but "floor at zero, jump only when it
/// moved" is the same sentence in the ruler, the rail and the
/// storyboard strip — and the one that lost the floor would scroll to a
/// negative offset the moment a scrub crossed the left edge.
void edgeAutoPanOvershoot(ScrollController controller, double delta) {
  if (delta == 0 || !controller.hasClients) {
    return;
  }
  final position = controller.position;
  final target = math.max(0.0, position.pixels + delta);
  if (target != position.pixels) {
    controller.jumpTo(target);
  }
}

/// One axis of a grid's reveal: the scrollable that runs it, how long one
/// step along it is, and which step the selection stands on — NEGATIVE when
/// the selection is not drawn on this axis, which is the answer
/// [indexOfDisplayRow] and every other row walk already gives.
typedef RevealedStep = ({ScrollController controller, double extent, int at});

/// Brings the SELECTION back into view on BOTH of a grid's axes (R5, user
/// 2026-08-09): the frame under the cursor along the frame axis, the row it
/// stands on along the rail.
///
/// One row/cell of margin, so a walk keeps a neighbour in sight and reads as
/// a walk rather than as a jump to the edge.
///
/// 🚨ONE function for both grids. The timeline runs the frames across and
/// the rows down, the X-sheet runs the frames down and the columns across,
/// and each spelled the whole thing (the audit's clone scan, round 8). An
/// axis is a [RevealedStep] here, so neither grid states an orientation at
/// all — it hands its two scrollables in whichever order it holds them.
///
/// An axis with no clients, a non-positive extent or a negative
/// [RevealedStep.at] is left where it is; the other still moves.
void revealSelectionOnBothAxes(RevealedStep first, RevealedStep second) {
  for (final axis in [first, second]) {
    if (_axisCanMove(axis)) {
      jumpToReveal(axis.controller, _itemOf(axis));
    }
  }
}

/// Whether an axis can be moved at all: a scrollable with no clients, a
/// non-positive extent, or a step that is not drawn on this axis
/// ([RevealedStep.at] negative, which is what every row walk answers) is
/// left exactly where it is.
bool _axisCanMove(RevealedStep axis) =>
    axis.at >= 0 && axis.extent > 0 && axis.controller.hasClients;

/// Where a step stands along its axis, with ONE step of margin — the margin
/// a walk reads by and a page ignores on purpose ([pageScrollOffset]).
RevealedItem _itemOf(RevealedStep axis) => (
  start: axis.at * axis.extent,
  extent: axis.extent,
  margin: axis.extent,
);

/// Turns the page under ONE axis so the playhead's frame stands at the
/// window's start, and not at all while it is already inside (F-110).
///
/// 🚨유저 2026-09-12: 「재생시에도 플레이헤드 밖 나갈때 스크롤하도록. **룰러
/// 드래그랑은 다르게 다음 페이지? 로 간다는 느낌**임. 뭐냐면 넘어가면 **룰러가
/// 왼쪽에 오도록 스크롤바 한번만 이동**」.
///
/// ⛔ONE axis, where the reveal takes two, and that is the difference and
/// not an omission: a reveal answers 「the selection moved」, which is a
/// place on both of a grid's axes at once. A playback tick moves the
/// playhead along the FRAME axis and nothing else — the rows do not move
/// while a cut plays. Handing a second axis here would mean inventing a
/// row for the tick to stand on.
///
/// Every surface that follows the playhead calls THIS — the timeline's
/// frames, the x-sheet's (which run down, not across) and the storyboard's
/// global strip — so the page law has one home, as the walk does.
void pageToPlayhead(RevealedStep axis) {
  if (_axisCanMove(axis)) {
    jumpToPage(axis.controller, _itemOf(axis));
  }
}
