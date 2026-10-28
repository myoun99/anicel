part of '../storyboard_panel.dart';

/// THE ROWS' WINDOW — the rail's rows and the strips' built only where the
/// rows' view stands, cut by the timeline's own window
/// ([TimelineRowEdges.window]) over the rail's one table
/// ([_StoryboardRailRows.windowTable]).
///
/// 🚨Card frame-panels-build-in-one-frame ② (관제 2026-10-28: the same
/// window code, never a storyboard window of its own). ↩️Every row of every
/// track was built, scrolled out of sight or not: on S5_BA's cut 352 with
/// every row shown, 671 of the panel's 2,375 elements stood in rows nobody
/// could see.
///
/// 🚨A collaborator of `_StoryboardPanelState`, as [_StoryboardScroll] is.
/// It reaches the State through `_state`.
class _StoryboardRowsWindow {
  _StoryboardRowsWindow(this._state);

  final _StoryboardPanelState _state;

  /// Moves when the scroll carries the rows into another window: the rail
  /// and every track's strips rebuild on it, and nothing else does.
  final ValueNotifier<int> bucket = ValueNotifier<int>(0);

  /// The row a pointer holds, built wherever the window stands: the State
  /// a gesture lives in goes with its row, and a row the window let go of
  /// mid-drag would drop the drag ([HeldRowPin], the timeline's A5).
  final HeldRowPin held = HeldRowPin();

  /// The window the rows were last laid for ([_tokenOf]).
  int _laid = -1;

  void dispose() => bucket.dispose();

  /// The scroll moved: the rows are laid again when the window they stand
  /// in did.
  ///
  /// ⚠️Compared against the window last LAID, not against the last one
  /// heard: a pass that lays other rows moves the windows under a scroll
  /// that stands still.
  void handleScroll() {
    final token = _tokenOf(_now());
    if (token != _laid) {
      _laid = token;
      bucket.value += 1;
    }
  }

  /// Track [trackIndex]'s rows as this pass lays them.
  _WindowedRows rowsOf(int trackIndex) {
    final table = _state._railRows.windowTable;
    final window = _now();
    _laid = _tokenOf(window);
    return _WindowedRows(
      table,
      window,
      held,
      table.firstSlots[trackIndex],
    );
  }

  /// The rows the view stands over now, or null while it has no extent —
  /// before the panel is laid out, when every row is built.
  TimelineVisibleRange? _now() {
    final edges = _state._railRows.windowTable.edges;
    final controller = _state._verticalController;
    final position = controller.hasClients ? controller.position : null;
    final viewport = position != null && position.hasViewportDimension
        ? position.viewportDimension
        : _state._middleViewportHeight;
    if (viewport <= 0) {
      return null;
    }
    final scrolled = position != null && position.hasPixels
        ? position.pixels
        : _state._keptLayerAxis?.value ?? 0;
    return edges.window(
      scrollOffset: scrolled
          .clamp(0.0, math.max(0.0, edges.total - viewport))
          .toDouble(),
      viewportExtent: viewport,
    );
  }

  int _tokenOf(TimelineVisibleRange? window) {
    if (window == null) {
      return -1;
    }
    final count = _state._railRows.windowTable.edges.count;
    return window.startIndex * (count + 1) + window.endIndexExclusive;
  }
}

/// The rail's rows as the window cuts them: [edges] over every track's
/// [slots], a head row joined with the lanes twirled under it, and where
/// each track's rows begin among them.
typedef _RowsWindowTable = ({
  TimelineRowEdges edges,
  List<_StoryboardRailSlot> slots,
  List<int> firstSlots,
});

/// What one unit of rows builds — a head row and the lanes twirled under
/// it — called only when the window builds it.
typedef _RowUnit = List<Widget> Function();

/// One track's rows as the window lays them, section after section in the
/// order the table lays them.
final class _WindowedRows {
  _WindowedRows(this._table, this._window, this._held, this._slot);

  final _RowsWindowTable _table;
  final TimelineVisibleRange? _window;
  final HeldRowPin _held;
  int _slot;

  /// [units] where they stand: each built while a row of it stands in the
  /// window or a pointer holds it, and a run of the others one spacer as
  /// tall as they lie.
  List<Widget> lay(List<_RowUnit> units) {
    final laid = <Widget>[];
    var gap = 0.0;
    for (final unit in units) {
      final first = _slot;
      final last = _table.edges.unitOf(first).last;
      _slot = last + 1;
      final head = _headOf(first);
      if (_builds(first, last) || (head != null && _held.held == head)) {
        if (gap > 0) {
          laid.add(SizedBox(height: gap));
          gap = 0;
        }
        laid.add(_holdable(head, first, unit()));
      } else {
        gap += _table.edges.startOf(last + 1) - _table.edges.startOf(first);
      }
    }
    if (gap > 0) {
      laid.add(SizedBox(height: gap));
    }
    return laid;
  }

  bool _builds(int first, int last) => switch (_window) {
    null => true,
    final window =>
      first < window.endIndexExclusive && last >= window.startIndex,
  };

  /// The address a unit's head row is stood on by, or null for a row nobody
  /// stands on (an S slot with no layer).
  TimelineRowAddress? _headOf(int first) {
    final slot = _table.slots[first];
    return _standingAddressOf(slot) ?? slot.display?.address;
  }

  /// [rows] in one column, held while a pointer is down on them
  /// ([_StoryboardRowsWindow.held]) and keyed by their head, so a spacer
  /// coming and going above them leaves each row its own element.
  Widget _holdable(TimelineRowAddress? head, int first, List<Widget> rows) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
    if (head == null) {
      return KeyedSubtree(key: ValueKey<int>(first), child: column);
    }
    return Listener(
      key: ValueKey<TimelineRowAddress>(head),
      onPointerDown: (_) => _held.take(head),
      onPointerUp: (_) => _held.release(head),
      onPointerCancel: (_) => _held.release(head),
      child: column,
    );
  }
}
