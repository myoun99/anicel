import 'package:flutter/foundation.dart'
    show ValueChanged, immutable, listEquals, mapEquals, setEquals;

/// What a grid's header graphs are told (I-89 ③), each by the key of the
/// group or the lane it was pressed on (`laneGroupKey`): a group's graph
/// on or off, a lane pinned to every graph or let go, what a graph plots,
/// how far it stands along the rail, a graph enlarged over every other
/// row or let back, its pen taken up or put down, its transform box
/// shown or hidden, and its snap turned on or off.
typedef LaneGraphVerbs = ({
  ValueChanged<String> toggle,
  ValueChanged<String> togglePin,
  void Function(String groupKey, LaneGraphMode mode) plot,
  void Function(String groupKey, double extent) resize,
  ValueChanged<String> enlarge,
  ValueChanged<String> pen,
  ValueChanged<String> transformBox,
  ValueChanged<String> snap,
});

/// What a header graph plots: the values, or how fast they change — a
/// lane's together, as one speed (I-89-Q5 B).
enum LaneGraphMode { value, speed }

/// How many rows tall a graph opens — before its grip says otherwise.
const int laneGraphOpeningRows = 7;

/// How far a row stands while a graph is enlarged over it — a lane, or an
/// other graph whole: the thin strip of the mock's 5판 (「크게 보기는 다른
/// 행을 얇은 띠로 접어 패널 대부분을 이 그래프에 줍니다」).
const double laneGraphFoldedExtent = 8;

/// The most a graph stands along a rail whose view is [view] long, its
/// rows [rowExtent] each: the view less its header's row — what an
/// ENLARGED graph stands (I-89 ③D), so its header and it fill the panel,
/// and the most its grip pulls it to: the mock's grip stops where its
/// enlarged graph stands (`Math.min(360, …)` · `big ? 360`), ONE value.
double laneGraphMostExtent(double view, double rowExtent) =>
    view - rowExtent > 0 ? view - rowExtent : 0;

/// ONE group's open header graph (I-89 ③): how far it stands along the
/// rail, what it plots, whether it is enlarged over the rest, whether its
/// pen is up, whether its transform box is shown, and whether its snap is
/// on.
@immutable
class LaneGraph {
  const LaneGraph({
    this.extent,
    this.mode = LaneGraphMode.value,
    this.enlarged = false,
    this.pen = false,
    this.transformBox = true,
    this.snap = false,
  });

  /// The grip's extent; null until a grip has said one.
  final double? extent;

  final LaneGraphMode mode;

  /// Whether it is ENLARGED over every other row (I-89 ③D, the mock's 5판)
  /// — it stands as far as the view lets one ([laneGraphMostExtent]), and
  /// every other row is folded to a strip. Kept with the graph, as its
  /// extent and its mode are: a graph shut is let back with it, and every
  /// use of its row wears it (F-302). ⛔A key of its own, beside
  /// [LaneGraphsView.open], outlived the graph it named and followed no
  /// row.
  final bool enlarged;

  /// Whether its PEN is up (I-3 ④, AE's pen in the graph editor): a press
  /// on one of its lines puts a key there, the value it holds kept — what
  /// a Ctrl+click does with no pen ([LaneGraphPicture]). A finger has no
  /// Ctrl, so a switch.
  ///
  /// ⚠️Mine: one graph's, beside [enlarged] in its tools and kept as that
  /// is — with the graph, on every use of its row (F-302). AE's pen is the
  /// one tool of the window; this app's graph tools are each graph's own.
  final bool pen;

  /// Whether its TRANSFORM BOX is shown (AE's 「Show Transform Box」,
  /// graph-box-handles-more ⓔ): the box round the keys picked, with its
  /// handles and the carry from inside it — hidden, the keys picked are
  /// carried from a key, and a drag inside where it stood draws a new box.
  /// Shown on a graph nobody has turned it off on, as AE's is.
  ///
  /// ⚠️Mine: one graph's and kept as [pen] is — AE's is one switch of the
  /// window.
  final bool transformBox;

  /// Whether its SNAP is on (AE's 「Snap」 in its graph editor,
  /// graph-key-drag-snaps): a key carried snaps to the times and the values
  /// of the keys about it, to the playhead and to the frames' two ends,
  /// with a line drawn where it snaps — and Ctrl held (⌘ on a Mac) turns
  /// it the other way for as long as it is held ([LaneGraphPicture]).
  ///
  /// ⚠️Mine: off, as AE's snap button starts — and one graph's, kept as
  /// [pen] is.
  final bool snap;

  /// How far the graph stands on a rail of [rowExtent] rows: the grip's,
  /// or [laneGraphOpeningRows] rows — so a graph nobody has sized follows
  /// the OS text size its rows do.
  double extentAt(double rowExtent) =>
      extent ?? laneGraphOpeningRows * rowExtent;

  LaneGraph copyWith({
    double? extent,
    LaneGraphMode? mode,
    bool? enlarged,
    bool? pen,
    bool? transformBox,
    bool? snap,
  }) => LaneGraph(
    extent: extent ?? this.extent,
    mode: mode ?? this.mode,
    enlarged: enlarged ?? this.enlarged,
    pen: pen ?? this.pen,
    transformBox: transformBox ?? this.transformBox,
    snap: snap ?? this.snap,
  );

  @override
  bool operator ==(Object other) =>
      other is LaneGraph &&
      other.extent == extent &&
      other.mode == mode &&
      other.enlarged == enlarged &&
      other.pen == pen &&
      other.transformBox == transformBox &&
      other.snap == snap;

  @override
  int get hashCode =>
      Object.hash(extent, mode, enlarged, pen, transformBox, snap);
}

/// THE RAIL'S HEADER GRAPHS (I-89 ③) — a view setting, kept in the file
/// beside the project as the zooms are (F-360-Q1): which lane groups stand
/// open as a graph, and the lanes pinned to every graph.
///
/// 🗣️유저 2026-10-10: 「그래프누르면 해당 fx에서만 작동하도록」 · 「그래프를
/// 누른 레일만 상태변경」 — [open] is keyed by the group (`laneGroupKey`), so
/// each turns on its own. 「ae의 그래프세트? … 남겨도 될거같긴한데」 — [pinned]
/// is AE's graph editor set: a pinned lane is drawn in every open graph, the
/// one way another group's lane reaches one.
@immutable
class LaneGraphsView {
  const LaneGraphsView({this.open = const {}, this.pinned = const {}});

  static const LaneGraphsView none = LaneGraphsView();

  /// The groups standing open as a graph, by `laneGroupKey`.
  final Map<String, LaneGraph> open;

  /// The pinned lanes, by the `laneGroupKey` of their own (layer, lane).
  final Set<String> pinned;

  LaneGraphsView copyWith({
    Map<String, LaneGraph>? open,
    Set<String>? pinned,
  }) => LaneGraphsView(open: open ?? this.open, pinned: pinned ?? this.pinned);

  @override
  bool operator ==(Object other) =>
      other is LaneGraphsView &&
      mapEquals(other.open, open) &&
      setEquals(other.pinned, pinned);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in open.entries)
        Object.hash(key, value),
    ]),
    Object.hashAllUnordered(pinned),
  );
}

/// Where a member lane sits in its group's open HEADER GRAPH (I-89 ③): the
/// group whose graph it is drawn in, that graph, the lanes seated in it,
/// and which of them the row selection and the pins name.
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
    required this.picked,
    required this.pinned,
  });

  /// The group's view-state key (`laneGroupKey`): a header's — or, on the
  /// camera row, its own Transform group's, the row being that header (㉙).
  final String groupKey;

  final LaneGraph graph;

  /// The ids of the group's lanes seated in the graph, as the rail draws
  /// them — what its rows and its picture each read the drawn lanes off.
  final List<String> lanes;

  /// Those of [lanes] in the row selection, in the same order.
  final List<String> picked;

  /// Those of [lanes] pinned to every graph ([LaneGraphsView.pinned]), in
  /// the same order.
  final List<String> pinned;

  @override
  bool operator ==(Object other) =>
      other is TimelineGraphSeat &&
      other.groupKey == groupKey &&
      other.graph == graph &&
      listEquals(other.lanes, lanes) &&
      listEquals(other.picked, picked) &&
      listEquals(other.pinned, pinned);

  @override
  int get hashCode => Object.hash(
    groupKey,
    graph,
    Object.hashAll(lanes),
    Object.hashAll(picked),
    Object.hashAll(pinned),
  );
}
