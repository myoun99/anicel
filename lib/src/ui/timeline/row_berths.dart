import 'package:flutter/foundation.dart';

import '../../models/timeline_row_address.dart';
import 'property_lane_model.dart';

/// THE BERTHS a windowed grid builds its rows in: which ELEMENTS a row's
/// widgets live in, kept apart from which layer the row shows.
///
/// 🚨I-57 (10-13, measured on the user's project): every row was keyed by
/// its layer, so a cut switch — each row a layer of the new cut — threw
/// away every row the window held and built them again, the rail and the
/// cells alike: twelve row roots and 1577 elements on every crossing a
/// scrub or a play made. Two rows of two cuts at one place are the same
/// widgets showing other values; only the key said otherwise. (Why the
/// keys were there at all is [Named]'s story.)
///
/// ★Within one WORLD — a cut of a project — a berth follows its ROW, which
/// is what the layer keys did and what a drag's held row needs (A5): a row
/// that moves takes its elements along, and the rows a twirl opens leave
/// the rows below them where they were. A row that arrives takes a berth
/// no row of the world has had, so it never inherits a stranger's state.
///
/// ★Across worlds a row takes the berth of the row that stood at its
/// PLACE — the new cut's third row is built in the old cut's third row's
/// elements — unless a hand is in the rows. An edit in flight (a press, a
/// drag, a typed number) belongs to the layer it began on, so the rows
/// then build afresh, exactly as a layer key always made them.
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
  /// [handsOn] is asked only when the world has changed: whether an edit
  /// is in flight in the rows. The same map comes back while nothing has
  /// moved, so a widget holding it compares equal.
  RowBerthMap berthsFor(
    List<TimelineDisplayRow> rows, {
    required Object world,
    required bool Function() handsOn,
  }) {
    final previous = _map;
    final sameWorld = world == _world;
    final byPlace = !sameWorld && !handsOn();
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
