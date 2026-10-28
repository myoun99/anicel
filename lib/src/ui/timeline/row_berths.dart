import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../models/timeline_row_address.dart';
import '../widgets/anchored_popup.dart' show AnchoredPopupsOpenFrom;
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
  /// counted: a pointer down on it, a popup opened from inside it.
  ///
  /// Every surface a grid's rows stand on is wrapped, and nothing else:
  /// the timeline's ruler is not, because a scrub there is how a cut
  /// switch is MADE, and it is the switch the rows are handed over for. (A
  /// row a drag holds is a pointer down on it — [HeldRowPin] is taken
  /// mid-drag.)
  Widget counting(Widget rows) => _CountedRows(berths: this, child: rows);

  final Set<int> _pointers = {};

  /// The popups open from the rows ([AnchoredPopupsOpenFrom]): a number
  /// typed on a pencil's pad, a pick in a row's popover — an edit in
  /// flight that no pointer on the rows and no focus inside them shows,
  /// a popup being a route over everything.
  ///
  /// ↩️It was the keyboard's focus inside the rows — a number typed in
  /// the row's own field — until I-134 (2026-10-27) moved every typed
  /// number onto a pad, and nothing in a row took the keyboard any more.
  final Set<Object> _popups = {};

  bool _handsInTheRows() => _pointers.isNotEmpty || _popups.isNotEmpty;
}

class _CountedRows extends StatelessWidget {
  const _CountedRows({required this.berths, required this.child});

  final RowBerths berths;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnchoredPopupsOpenFrom(
    open: berths._popups,
    child: Listener(
      onPointerDown: (event) => berths._pointers.add(event.pointer),
      onPointerUp: (event) => berths._pointers.remove(event.pointer),
      onPointerCancel: (event) => berths._pointers.remove(event.pointer),
      child: child,
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
/// No row's facts name its layer: a row is handed back to whichever layer
/// stands in its berth now, and acts through [BerthRow] — the controls rows
/// by their face, the cells rows by their shape, drawing what the berth
/// shows ([BerthRow.shows]).
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
