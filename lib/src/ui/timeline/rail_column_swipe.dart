import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';

/// A column a rail can SWIPE: where its band sits at a given row depth,
/// what value a row shows there, and how to flip that row.
///
/// 🚨A band RESOLVER rather than a fixed x-range (I-1): a leading column
/// sits after the folder indent, so where it is depends on the row under
/// the press. That is also why the swipe paints by column IDENTITY once it
/// has latched — one drag can cross rows at different depths without ever
/// leaving its column.
///
/// [valueOf] returns null for a row that HAS NO control in this column (an
/// attach row's sheet slot holds an arrow, a laneless row has no twirl).
/// Null is skipped: a swipe cannot paint what a tap could not.
typedef RailToggleColumn<TRow> = ({
  ({double left, double right}) Function(int depth) bandAt,
  bool? Function(TRow row) valueOf,
  void Function(TRow row) toggle,
});

/// A row the swipe landed on: the subject, its indent depth, and the
/// identity the sweep dedupes by so one drag paints each row once.
typedef RailSwipeRow<TRow> = ({TRow row, int depth, Object id});

/// Turns a vertical drag that STARTS on a rail row's button into a
/// Krita-style paint-swipe down the rows.
///
/// 🚨I-1 (유저 2026-08-24): 「레이어의 버튼 조작하는거 **일괄조작** 넣고싶음
/// … 탭 다운 한 채로 아래로 드래그하면 **해당 다른 레이어들도 같은 버튼조작**
/// 되도록」.
///
/// ⛔It used to be the EYE and nothing else, with the eye's band typed in as
/// a constructor argument. The swipe was never about the eye — it is about a
/// COLUMN — so the column is the argument and the host lists the ones it has.
///
/// 🚨★★★AND IT IS NOT ABOUT THE TIMELINE EITHER. This lived inside the layer
/// grid's private state until 2026-08-29, which is why the storyboard rail —
/// the same buttons, laid out by the same [layerRailTrailingCells] — had no
/// swipe at all. 유저: 「타임라인이랑 왜 통일안한거지?」. Anything that lays
/// rows in a column can wear it now; what a host supplies is its columns and
/// a way to name the row at a rail-local y.
class RailColumnSwipe<TRow> extends StatefulWidget {
  const RailColumnSwipe({
    super.key,
    required this.columns,
    required this.rowAt,
    required this.child,
  });

  /// The swipeable columns, in any order — a press picks the first whose
  /// band holds it.
  final List<RailToggleColumn<TRow>> columns;

  /// The row at a rail-local y, or null for a spacer.
  final RailSwipeRow<TRow>? Function(double localY) rowAt;

  final Widget child;

  @override
  State<RailColumnSwipe<TRow>> createState() => _RailColumnSwipeState<TRow>();
}

class _RailColumnSwipeState<TRow> extends State<RailColumnSwipe<TRow>> {
  RailToggleColumn<TRow>? _column;
  bool? _targetValue;
  final Set<Object> _painted = <Object>{};

  void _paintAt(RailSwipeRow<TRow>? row) {
    final column = _column;
    final target = _targetValue;
    if (row == null || column == null || target == null) {
      return;
    }
    if (!_painted.add(row.id)) {
      return;
    }
    // Only rows that DISAGREE are touched: a swipe sets a value, it does not
    // flip each row it passes (drag back over one and it must not come
    // undone), and on a tri-state column it is what keeps the third state
    // out of the sweep's way.
    //
    // A row with NO control in this column reads null and is skipped for a
    // different reason: not that it agrees, but that there is nothing there
    // to disagree — a sheet swipe crossing an attach row must leave the
    // arrow it finds alone.
    final value = column.valueOf(row.row);
    if (value != null && value != target) {
      column.toggle(row.row);
    }
  }

  int _columnAt(Offset local) {
    final row = widget.rowAt(local.dy);
    if (row == null) {
      return -1;
    }
    for (var index = 0; index < widget.columns.length; index += 1) {
      final band = widget.columns[index].bandAt(row.depth);
      if (local.dx >= band.left && local.dx <= band.right) {
        return index;
      }
    }
    return -1;
  }

  bool _start(int columnIndex, double localY) {
    final row = widget.rowAt(localY);
    if (row == null) {
      return false;
    }
    final column = widget.columns[columnIndex];
    // A row carrying no control in this column has no value to latch, so
    // there is no swipe to start — pressing an attach row's arrow must not
    // begin painting the sheet column it stands in.
    final value = column.valueOf(row.row);
    if (value == null) {
      return false;
    }
    _column = column;
    _targetValue = !value;
    _painted.clear();
    _paintAt(row);
    return true;
  }

  void _end() {
    _column = null;
    _targetValue = null;
    _painted.clear();
  }

  @override
  Widget build(BuildContext context) {
    return _RailSwipeDetector(
      columnAt: _columnAt,
      onStart: _start,
      onUpdate: (localY) => _paintAt(widget.rowAt(localY)),
      onEnd: _end,
      child: widget.child,
    );
  }
}

/// The gesture half, kept apart from the painting half because it knows
/// nothing about rails: it reports which column a press is in and where
/// down the rail, and the state above decides what that means.
///
/// [onStart] latches (returns false to decline, e.g. the down landed on a
/// spacer, or between columns); [onUpdate] paints each crossed row; [onEnd]
/// clears. A vertical-drag recognizer, so single taps still reach the
/// buttons and the outer scroll keeps working — see [supportedDevices] for
/// the other half of that (F-8).
class _RailSwipeDetector extends StatefulWidget {
  const _RailSwipeDetector({
    required this.columnAt,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  /// Which COLUMN a press at this rail-local point is in, or -1 for none.
  final int Function(Offset local) columnAt;

  /// The press: which COLUMN it landed in, and where down the rail. Returns
  /// false to decline.
  final bool Function(int columnIndex, double localY) onStart;
  final ValueChanged<double> onUpdate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_RailSwipeDetector> createState() => _RailSwipeDetectorState();
}

class _RailSwipeDetectorState extends State<_RailSwipeDetector> {
  bool _engaged = false;
  int _pressedColumn = -1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      // 🚨F-8 (유저 2026-08-24: 「레이어영역도 … **터치로 스크롤할수있게**
      // 사양 통일」). The doc above claims the outer vertical scroll keeps
      // working outside the band; it did not, and a finger on the rail
      // scrolled nothing at all (measured — the frame area beside it moved
      // 90px on the same drag).
      //
      // ⛔A recognizer that has already WON cannot hand the gesture back:
      // declining inside `onVerticalDragStart` leaves the swipe undone and
      // the scroll dead, which is the shape this file's own neighbours are
      // warned about ([AppInput.toolPointerDevices]). The band check runs
      // after the arena is over, so it can only ever be the second half of
      // the answer.
      //
      // 결정 10 is the first half, already written and already read by every
      // other edit pan on this surface: a finger scrolls the timeline, and
      // becomes the pointer the moment one finger is the drawing hand.
      supportedDevices: AppInput.timelineEditPanDevices,
      // 🚨I-1, measured: with the default `DragStartBehavior.start` a swipe
      // MISSES A ROW, and which row depends on what you compare against.
      // The recognizer reports its start at the position where it WON the
      // arena — one slop-length, ~18px, past the press on a 28px row — and
      // it deliberately drops the movement that won as a delta, so no update
      // ever names the row in between. Press the top row's toggle and drag:
      // either the row you pressed or the row under the slop went unpainted.
      //
      // `down` is the answer rather than a remembered press position,
      // because it fixes BOTH halves: the start reports the press, and the
      // slop movement arrives as an update. The reason the default exists —
      // content must not jump by the slop when the drag begins — does not
      // apply to a gesture that moves nothing and only paints the rows it
      // passes.
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragDown: (details) {
        _pressedColumn = widget.columnAt(details.localPosition);
        _engaged = _pressedColumn >= 0;
      },
      onVerticalDragStart: (details) {
        if (!_engaged) {
          return;
        }
        _engaged = widget.onStart(_pressedColumn, details.localPosition.dy);
      },
      onVerticalDragUpdate: (details) {
        if (_engaged) {
          widget.onUpdate(details.localPosition.dy);
        }
      },
      onVerticalDragEnd: (_) {
        if (_engaged) {
          widget.onEnd();
        }
        _engaged = false;
      },
      onVerticalDragCancel: () {
        if (_engaged) {
          widget.onEnd();
        }
        _engaged = false;
      },
      child: widget.child,
    );
  }
}
