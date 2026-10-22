import 'package:flutter/widgets.dart' show Axis, Offset, Rect;

import 'axis_turn.dart' show offsetAlong, partAcross, partAlong;

/// A HANDLE of a header graph's box round the keys it has picked (I-3 ⑥,
/// AE's transform box): the end of the box it stands at along the frames,
/// and the end across them — -1 the box's start, 1 its end, 0 the middle of
/// a side.
typedef LaneGraphBoxHandle = ({int along, int across});

/// The box's eight handles, its corners and its sides' middles, in the
/// order they are drawn.
const List<LaneGraphBoxHandle> laneGraphBoxHandles = [
  (along: -1, across: -1),
  (along: 0, across: -1),
  (along: 1, across: -1),
  (along: 1, across: 0),
  (along: 1, across: 1),
  (along: 0, across: 1),
  (along: -1, across: 1),
  (along: -1, across: 0),
];

/// Where [handle] stands on [box], on a graph whose frames run along
/// [axis].
Offset laneGraphBoxHandleAt(LaneGraphBoxHandle handle, Rect box, Axis axis) {
  double at(int end, double low, double high) => switch (end) {
    < 0 => low,
    > 0 => high,
    _ => (low + high) / 2,
  };
  return offsetAlong(
    axis,
    along: at(
      handle.along,
      partAlong(axis, box.topLeft),
      partAlong(axis, box.bottomRight),
    ),
    across: at(
      handle.across,
      partAcross(axis, box.topLeft),
      partAcross(axis, box.bottomRight),
    ),
  );
}

/// The lowest and the highest of something a box holds.
typedef LaneGraphSpan = ({double low, double high});

/// What stands [of] of the way across [span] — its low at 0, its high at 1.
double laneGraphSpanAt(LaneGraphSpan span, double of) =>
    span.low * (1 - of) + span.high * of;

/// How far of the way across [span] [at] stands — [laneGraphSpanAt] read
/// back; null where [span] has no width.
double? laneGraphSpanOf(LaneGraphSpan span, double at) =>
    span.high == span.low ? null : (at - span.low) / (span.high - span.low);

/// A POINT between the keys a box holds (graph-box-handles-more ⓓ): how
/// far of the way from the lowest of them to the highest it stands, along
/// the frames and across them — 0 the lowest, 1 the highest.
typedef LaneGraphBoxPoint = ({double along, double across});

/// Where the box's ANCHOR POINT stands until the hand moves it: in the
/// middle — AE's 「an anchor point appears in the center」.
const LaneGraphBoxPoint laneGraphBoxMiddle = (along: 0.5, across: 0.5);

/// A box's handle TAKEN (I-3 ⑥): which one, and what the keys it holds
/// stood at — the [times] of the first and the last of them, on the graph's
/// frames, and how far [across] the graph their marks stood — and where
/// the box's anchor point stood between them ([pivot]).
typedef LaneGraphBoxHeld = ({
  LaneGraphBoxHandle handle,
  LaneGraphSpan times,
  LaneGraphSpan across,
  LaneGraphBoxPoint pivot,
});

/// Where the hand has pulled the end of the box its handle stands at to:
/// the time along the frames, and the point across them.
typedef LaneGraphBoxNow = ({double time, double across});

/// What a stretch is held to while it is pulled: whether it goes about
/// the box's anchor point (Ctrl held — ⌘ on a Mac) and whether a corner
/// keeps the box's shape (Shift) — AE's.
typedef LaneGraphBoxKeys = ({bool pivoted, bool square});

/// What a box's handle pulled stretches its keys by, each way: how far
/// [factor] times as far from [anchor] as they stood — a factor of 1 where
/// it stretches nothing that way.
typedef LaneGraphBoxPull = ({
  ({double anchor, double factor}) time,
  ({double anchor, double factor}) across,
});

/// What [held]'s handle pulled to [now] stretches the keys it holds by
/// (I-3 ⑥, AE's transform box): each way the handle stands at an end of,
/// from that end about the box's other — or, [LaneGraphBoxKeys.pivoted],
/// about its anchor point — and a corner, [LaneGraphBoxKeys.square], both ways
/// by the one that has gone further. A side's middle stretches the one way
/// alone; past the other end, the factor goes under 0 and turns them
/// about.
LaneGraphBoxPull laneGraphBoxPulled(
  LaneGraphBoxHeld held,
  LaneGraphBoxNow now,
  LaneGraphBoxKeys keys,
) {
  final (:handle, :times, :across, :pivot) = held;
  final time = _pulled(
    handle.along,
    times,
    now.time,
    about: keys.pivoted ? pivot.along : null,
  );
  final crossed = _pulled(
    handle.across,
    across,
    now.across,
    about: keys.pivoted ? pivot.across : null,
  );
  if (!keys.square || handle.along == 0 || handle.across == 0) {
    return (time: time, across: crossed);
  }
  final factor = (time.factor - 1).abs() >= (crossed.factor - 1).abs()
      ? time.factor
      : crossed.factor;
  return (
    time: (anchor: time.anchor, factor: factor),
    across: (anchor: crossed.anchor, factor: factor),
  );
}

/// One way of [laneGraphBoxPulled]: [span]'s [end] pulled to [now] — about
/// the point [about] of the way across it, or its other end.
({double anchor, double factor}) _pulled(
  int end,
  LaneGraphSpan span,
  double now, {
  required double? about,
}) {
  final (:low, :high) = span;
  final anchor = about == null
      ? (end > 0 ? low : high)
      : laneGraphSpanAt(span, about);
  final edge = end > 0 ? high : low;
  return (
    anchor: anchor,
    factor: end == 0 || edge == anchor ? 1 : (now - anchor) / (edge - anchor),
  );
}
