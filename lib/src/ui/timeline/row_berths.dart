import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/timeline_row_address.dart';
import 'memo_token.dart';
import 'property_lane_model.dart';

/// THE BERTHS a grid builds its rows in: which ELEMENTS a row's widgets
/// live in, kept apart from which layer the row shows.
///
/// 🚨I-57 (10-13, measured on the user's project): every row was keyed by
/// its layer, so a cut switch — each row a layer of the new cut — threw
/// away every row the window held and built them again, the rail and the
/// cells alike: twelve row roots and 1577 elements on every crossing a
/// scrub or a play made. Two rows of two cuts at one place are the same
/// widgets showing other values; only the key said otherwise. (Why the
/// keys were there at all is [Named]'s story.)
///
/// ONE berth law for both grids: the timeline's rows and the x-sheet's
/// columns, each with its rail — the sheet's columns were keyed by their
/// layers too, and its headers by nothing at all, which hands a header's
/// elements to the next layer whenever a row comes or goes.
///
/// ★Within one WORLD — a cut of a project — a berth follows its ROW, which
/// is what the layer keys did and what a drag's held row needs (A5): a row
/// that moves takes its elements along, and the rows a twirl opens leave
/// the rows below them where they were. A row that arrives takes a berth
/// no row of the world has had, so it never inherits a stranger's state.
///
/// ★Across worlds a row takes the berth of the row that stood at its
/// PLACE — the new cut's third row is built in the old cut's third row's
/// elements — unless a HAND is in the rows ([counting]). An edit in flight
/// (a press, a drag, a typed number) belongs to the layer it began on, so
/// the rows then build afresh, exactly as a layer key always made them.
///
/// ⚠️What a berth hands across is its elements' STATE, so no State in a
/// row may keep a layer's value past its build. Audited when berths came
/// in (10-13, every State a row of each kind holds, counted): gesture
/// states, which a hand in the rows keeps from crossing, and hover and
/// menu ids spelled with the layer's id, which name nothing in the next
/// layer's row. A State that caches what its layer shows drops it when
/// the layer changes.
class RowBerths {
  Object? _world;
  RowBerthMap _map = const RowBerthMap._({}, []);
  int _next = 0;

  /// The berth of every row of [rows] in [world].
  ///
  /// The same map comes back while nothing has moved, so a widget holding
  /// it compares equal.
  RowBerthMap berthsFor(
    List<TimelineDisplayRow> rows, {
    required Object world,
  }) {
    final previous = _map;
    final sameWorld = world == _world;
    final byPlace = !sameWorld && !_handsInTheRows();
    _world = world;
    final berthOf = <TimelineRowAddress, int>{};
    final order = List<int>.filled(rows.length, 0);
    for (var index = 0; index < rows.length; index += 1) {
      final address = rows[index].address;
      final berth = sameWorld
          ? previous._berthOf[address] ?? _next++
          : byPlace && index < previous._order.length
          ? previous._order[index]
          : _next++;
      berthOf[address] = berth;
      order[index] = berth;
    }
    if (sameWorld && listEquals(order, previous._order)) {
      return previous;
    }
    return _map = RowBerthMap._(berthOf, order);
  }

  /// [rows] — a surface the grid's rows stand on — with the hands in it
  /// counted: a pointer down on it, the keyboard's focus inside it.
  ///
  /// Every surface a grid's rows stand on is wrapped, and nothing else:
  /// the timeline's ruler is not, because a scrub there is how a cut
  /// switch is MADE, and it is the switch the rows are handed over for. (A
  /// row a drag holds is a pointer down on it — [HeldRowPin] is taken
  /// mid-drag.)
  Widget counting(Widget rows) => _CountedRows(berths: this, child: rows);

  final Set<int> _pointers = {};

  /// The surfaces' own nodes in the focus tree — each [_CountedRows] holds
  /// its own, because a node stands in ONE place: a second [Focus] given
  /// it takes it from the first without a word.
  final Set<FocusNode> _surfaces = {};

  bool _handsInTheRows() => _pointers.isNotEmpty || _focusInTheRows();

  /// Whether the keyboard's focus is inside the rows — a number being
  /// typed.
  ///
  /// ⛔Asked of the FOCUS tree, never the element tree: the focus can sit in
  /// a subtree being torn down — the text field of a project leaving the
  /// screen, the tree a test pumps over — whose element may no longer be
  /// asked for its ancestors (it asserted), while the focus tree has
  /// already parked its node at the root.
  bool _focusInTheRows() =>
      FocusManager.instance.primaryFocus?.ancestors.any(_surfaces.contains) ??
      false;
}

class _CountedRows extends StatefulWidget {
  const _CountedRows({required this.berths, required this.child});

  final RowBerths berths;
  final Widget child;

  @override
  State<_CountedRows> createState() => _CountedRowsState();
}

class _CountedRowsState extends State<_CountedRows> {
  /// Never focused itself, only stood over everything focusable in the
  /// surface.
  final FocusNode _node = FocusNode(
    debugLabel: 'the rows of a grid',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    widget.berths._surfaces.add(_node);
  }

  @override
  void didUpdateWidget(_CountedRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.berths, widget.berths)) {
      oldWidget.berths._surfaces.remove(_node);
      widget.berths._surfaces.add(_node);
    }
  }

  @override
  void dispose() {
    widget.berths._surfaces.remove(_node);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _node,
    includeSemantics: false,
    child: Listener(
      onPointerDown: (event) => widget.berths._pointers.add(event.pointer),
      onPointerUp: (event) => widget.berths._pointers.remove(event.pointer),
      onPointerCancel: (event) =>
          widget.berths._pointers.remove(event.pointer),
      child: widget.child,
    ),
  );
}

/// Where each row of one pass is built — [RowBerths.berthsFor]'s answer.
@immutable
final class RowBerthMap {
  const RowBerthMap._(this._berthOf, this._order);

  final Map<TimelineRowAddress, int> _berthOf;

  /// The berths in the rows' order.
  final List<int> _order;

  /// [row]'s element key. Every row the pass builds has one: the window
  /// and the held row are both cut from the rows the map was made for.
  RowBerthKey keyOf(TimelineDisplayRow row) =>
      RowBerthKey(_berthOf[row.address]!);
}

/// A row's element key: its berth, and nothing about what it shows.
@immutable
final class RowBerthKey extends LocalKey {
  const RowBerthKey(this.berth);

  final int berth;

  @override
  bool operator ==(Object other) =>
      other is RowBerthKey && other.berth == berth;

  @override
  int get hashCode => Object.hash(RowBerthKey, berth);

  @override
  String toString() => '[berth $berth]';
}

/// What a grid keeps of a kind of row, BERTH by berth ([keptWhileSame]):
/// the widget built in each berth, while the facts it was built from hold.
///
/// ONE keeping for every row memo of both grids — the rail's controls rows
/// and the cells rows, the timeline's and the x-sheet's. Each was keyed by
/// its row's LAYER, and three of the four were never let go of: every
/// layer of every cut a grid had shown stayed held, with the Layer it was
/// built from (I-57 ㉣, 10-13). A berth's entry lives while its berth
/// does: the memo holds the berths of the latest pass and no others.
///
/// A row whose facts name its layer (the cells') can only be handed back
/// to that layer; a row whose facts do not (the controls rows' face) is
/// handed back to whichever layer stands in its berth now, and acts
/// through [BerthRow].
final class KeptByBerth<F> {
  final Map<RowBerthKey, Kept<F>> _held = {};
  RowBerthMap? _heldFor;

  /// [row]'s widget in [berths] — the one held for its berth while [facts]
  /// are what it was built from, else [build]'s, held.
  Widget keep(
    RowBerthMap berths,
    TimelineDisplayRow row,
    F facts,
    Widget Function() build,
  ) {
    if (!identical(berths, _heldFor)) {
      _heldFor = berths;
      final live = berths._order.toSet();
      _held.removeWhere((key, _) => !live.contains(key.berth));
    }
    return keptWhileSame(_held, berths.keyOf(row), facts, build);
  }
}
