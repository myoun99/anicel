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

/// What the hand holds down while it pulls a handle — the three AE's
/// transform box reads: Ctrl (⌘ on a Mac), Alt (⌥) and Shift.
typedef LaneGraphBoxKeys = ({bool control, bool alt, bool shift});

/// What a box's handle pulled makes of the keys it holds: along the frames,
/// [time] — how far [factor] times as far from [anchor] as they stood, a
/// factor of 1 where they do not go; across the graph, where the lowest of
/// them and the highest go at the box's first frames and at its last —
/// the two alike while the box stays a box, apart where one side of it is
/// pulled ([laneGraphBoxAcrossOf]; the highest under the lowest where it
/// is turned over).
typedef LaneGraphBoxPull = ({
  ({double anchor, double factor}) time,
  ({LaneGraphSpan first, LaneGraphSpan last}) across,
});

/// What [held]'s handle pulled to [now] makes of the keys it holds (I-3 ⑥,
/// AE's transform box): each way the handle stands at an end of, it
/// stretches them from that end about the box's other — about its anchor
/// point with Ctrl held — and a corner with Shift held both ways by the one
/// that has gone further. A side's middle stretches the one way alone;
/// past the other end, the factor goes under 0 and turns them about. A
/// corner with Ctrl and Alt held pulls its side alone ([_sidePulled]).
LaneGraphBoxPull laneGraphBoxPulled(
  LaneGraphBoxHeld held,
  LaneGraphBoxNow now,
  LaneGraphBoxKeys keys,
) {
  final (:handle, :times, :across, :pivot) = held;
  final corner = handle.along != 0 && handle.across != 0;
  if (corner && keys.control && keys.alt) {
    return _sidePulled(held, now.across, together: keys.shift);
  }
  final time = _pulled(
    handle.along,
    times,
    now.time,
    about: keys.control ? pivot.along : null,
  );
  final crossed = _pulled(
    handle.across,
    across,
    now.across,
    about: keys.control ? pivot.across : null,
  );
  final factor = !keys.shift || !corner
      ? null
      : (time.factor - 1).abs() >= (crossed.factor - 1).abs()
      ? time.factor
      : crossed.factor;
  double stretched(double at) =>
      crossed.anchor + (at - crossed.anchor) * (factor ?? crossed.factor);
  final spread = (
    low: stretched(across.low),
    high: stretched(across.high),
  );
  return (
    time: (anchor: time.anchor, factor: factor ?? time.factor),
    across: (first: spread, last: spread),
  );
}

/// A corner pulled with Ctrl and Alt held (graph-box-handles-more ⓑ ⓒ):
/// the side of the box it stands at goes across the graph, and the other
/// side stays. Its two corners go apart or together about its middle, as
/// far as the hand has gone — AE's 「To taper keyframe values vertically,
/// Ctrl+Alt-drag」 — or, with Shift held too, both with the hand: 「To move
/// one side of the bounding box up or down, Ctrl+Alt+Shift-drag」. Nothing
/// goes along the frames.
///
/// ⚖️Mine (AE's help says the shape, not the sums): the taper goes about
/// the side's middle, not the box's anchor point — Ctrl is taken by the
/// taper itself.
LaneGraphBoxPull _sidePulled(
  LaneGraphBoxHeld held,
  double now, {
  required bool together,
}) {
  final (:handle, :times, :across, pivot: _) = held;
  final moved = now - (handle.across > 0 ? across.high : across.low);
  final apart = handle.across > 0 ? moved : -moved;
  final pulled = together
      ? (low: across.low + moved, high: across.high + moved)
      : (low: across.low - apart, high: across.high + apart);
  return (
    time: (anchor: times.low, factor: 1),
    across: handle.along > 0
        ? (first: across, last: pulled)
        : (first: pulled, last: across),
  );
}

/// Where across the graph a mark that stood [across] at [time] in [held]'s
/// box stands once [pull]ed — the box as four corners, the mark kept where
/// it stood between them (graph-box-handles-more): as far of the way
/// across the span it goes over as it stood across the box's, that span
/// as far of the way from the box's first end's to its last end's as the
/// mark stood along the frames.
///
/// ⚠️Mine: keys all on one frame stand at both ends at once, and go with
/// the end the hand has; keys all as high stand in the middle of a side.
double laneGraphBoxAcrossOf(
  LaneGraphBoxHeld held,
  LaneGraphBoxPull pull, {
  required double time,
  required double across,
}) {
  final along =
      laneGraphSpanOf(held.times, time) ?? (held.handle.along > 0 ? 1.0 : 0.0);
  final of = laneGraphSpanOf(held.across, across) ?? 0.5;
  final (:first, :last) = pull.across;
  final ends = (
    low: laneGraphSpanAt(first, of),
    high: laneGraphSpanAt(last, of),
  );
  return laneGraphSpanAt(ends, along);
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
