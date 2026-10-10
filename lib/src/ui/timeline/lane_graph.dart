import 'package:flutter/foundation.dart'
    show ValueChanged, immutable, listEquals, mapEquals, setEquals;

/// What a grid's header graphs are told (I-89 ③), each by the key of the
/// group or the lane it was pressed on (`laneGroupKey`): a group's graph
/// on or off, and a lane pinned to every graph or let go.
typedef LaneGraphVerbs = ({
  ValueChanged<String> toggle,
  ValueChanged<String> togglePin,
});

/// What a header graph plots: the values, or how fast they change.
enum LaneGraphMode { value, speed }

/// How many rows tall a graph opens — before its grip says otherwise.
const int laneGraphOpeningRows = 7;

/// ONE group's open header graph (I-89 ③): how far it stands along the
/// rail, and what it plots.
@immutable
class LaneGraph {
  const LaneGraph({this.extent, this.mode = LaneGraphMode.value});

  /// The grip's extent; null until a grip has said one.
  final double? extent;

  final LaneGraphMode mode;

  /// How far the graph stands on a rail of [rowExtent] rows: the grip's,
  /// or [laneGraphOpeningRows] rows — so a graph nobody has sized follows
  /// the OS text size its rows do.
  double extentAt(double rowExtent) =>
      extent ?? laneGraphOpeningRows * rowExtent;

  LaneGraph copyWith({double? extent, LaneGraphMode? mode}) =>
      LaneGraph(extent: extent ?? this.extent, mode: mode ?? this.mode);

  @override
  bool operator ==(Object other) =>
      other is LaneGraph && other.extent == extent && other.mode == mode;

  @override
  int get hashCode => Object.hash(extent, mode);
}

/// THE RAIL'S HEADER GRAPHS (I-89 ③) — view state, as the twirls are: which
/// lane groups stand open as a graph, the lanes pinned to every graph, and
/// the one graph enlarged over the rest.
///
/// 🗣️유저 2026-10-10: 「그래프누르면 해당 fx에서만 작동하도록」 · 「그래프를
/// 누른 레일만 상태변경」 — [open] is keyed by the group (`laneGroupKey`), so
/// each turns on its own. 「ae의 그래프세트? … 남겨도 될거같긴한데」 — [pinned]
/// is AE's graph editor set: a pinned lane is drawn in every open graph, the
/// one way another group's lane reaches one.
@immutable
class LaneGraphsView {
  const LaneGraphsView({
    this.open = const {},
    this.pinned = const {},
    this.enlarged,
  });

  static const LaneGraphsView none = LaneGraphsView();

  /// The groups standing open as a graph, by `laneGroupKey`.
  final Map<String, LaneGraph> open;

  /// The pinned lanes, by the `laneGroupKey` of their own (layer, lane).
  final Set<String> pinned;

  /// The group whose graph is enlarged over every other row, or null.
  final String? enlarged;

  LaneGraphsView copyWith({
    Map<String, LaneGraph>? open,
    Set<String>? pinned,
    String? Function()? enlarged,
  }) => LaneGraphsView(
    open: open ?? this.open,
    pinned: pinned ?? this.pinned,
    enlarged: enlarged == null ? this.enlarged : enlarged(),
  );

  @override
  bool operator ==(Object other) =>
      other is LaneGraphsView &&
      mapEquals(other.open, open) &&
      setEquals(other.pinned, pinned) &&
      other.enlarged == enlarged;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in open.entries)
        Object.hash(key, value),
    ]),
    Object.hashAllUnordered(pinned),
    enlarged,
  );
}

/// Where a member lane sits in its group's open HEADER GRAPH (I-89 ③): the
/// group whose graph it is drawn in, that graph, and the lanes drawn in it.
///
/// 🗣️유저 2026-10-10: 「그래프누르면 해당 fx에서만 작동하도록」 — the graph
/// takes the place of the group it was pressed on, and only that group's.
/// The lane stays the row it was — what is stood on, selected and walked
/// is the timeline's law, unchanged (「서는곳 법 그대로」) — so a seat is a
/// fact about where the row is DRAWN, not a row of another kind.
@immutable
class TimelineGraphSeat {
  const TimelineGraphSeat({
    required this.groupKey,
    required this.graph,
    required this.lanes,
  });

  /// The group's view-state key (`laneGroupKey`): a header's — or, on the
  /// camera row, its own Transform group's, the row being that header (㉙).
  final String groupKey;

  final LaneGraph graph;

  /// The ids of the group's lanes seated in the graph, as the rail draws
  /// them — what its rows and its picture each read the drawn lanes off.
  final List<String> lanes;

  @override
  bool operator ==(Object other) =>
      other is TimelineGraphSeat &&
      other.groupKey == groupKey &&
      other.graph == graph &&
      listEquals(other.lanes, lanes);

  @override
  int get hashCode => Object.hash(groupKey, graph, Object.hashAll(lanes));
}
