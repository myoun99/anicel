import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import '../input/value_control_pointers.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'layer_rail_columns.dart';
import 'layer_label_controls.dart'
    show layerFxSlotWidth, layerOnionSlotWidth, layerVisibilitySlotWidth;
import '../widgets/axis_gesture_detector.dart';

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
  ({double start, double end}) Function(int depth) bandAt,
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
    required this.axis,
    required this.columns,
    required this.rowAt,
    required this.child,
  });

  /// The axis the ROWS run along: down for a rail, across for the x-sheet
  /// (which is the same rail transposed — layers are columns there).
  final Axis axis;

  /// The swipeable columns, in any order — a press picks the first whose
  /// band holds it.
  final List<RailToggleColumn<TRow>> columns;

  /// The row at a rail-local position ALONG the rail, or null for a spacer.
  final RailSwipeRow<TRow>? Function(double alongPosition) rowAt;

  final Widget child;

  @override
  State<RailColumnSwipe<TRow>> createState() => _RailColumnSwipeState<TRow>();
}

class _RailColumnSwipeState<TRow> extends State<RailColumnSwipe<TRow>> {
  RailToggleColumn<TRow>? _column;
  bool? _targetValue;
  final Set<Object> _painted = <Object>{};

  /// The pointer that opened this gesture — the latch asks whether a control
  /// claimed it. No drag callback carries the id, so a Listener reads it.
  int? _downPointer;

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

  /// The coordinate that runs ALONG the rail — down the layer rail, ACROSS
  /// the x-sheet's layer columns. It names the row.
  double _along(Offset local) =>
      widget.axis == Axis.vertical ? local.dy : local.dx;

  /// The coordinate that runs ACROSS the rail. It names the column.
  ///
  /// 🚨These two are the whole axis story. Everything else here — the latch,
  /// the painted set, the "only rows that disagree" rule — is written in
  /// along/across and does not know which way the rail points.
  double _across(Offset local) =>
      widget.axis == Axis.vertical ? local.dx : local.dy;

  int _columnAt(Offset local) {
    final row = widget.rowAt(_along(local));
    if (row == null) {
      return -1;
    }
    final across = _across(local);
    for (var index = 0; index < widget.columns.length; index += 1) {
      final band = widget.columns[index].bandAt(row.depth);
      if (across >= band.start && across <= band.end) {
        return index;
      }
    }
    return -1;
  }

  bool _start(int columnIndex, double alongPosition) {
    final row = widget.rowAt(alongPosition);
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
    // 🚨★★★DID ITS OWN BUTTON ALREADY DO THIS ROW?
    //
    // 유저 2026-08-30: 「버튼은 기본적으로 **누른순간 작동**하고 **누른채로
    // 드래그시 일괄조작** 작동」. A press that landed ON the button fired it
    // during the pointer-down, so the row already holds what was asked for —
    // and the sweep spreads THAT. Painting it again toggles it straight back
    // (measured: the row appeared twice in the toggle log).
    //
    // ⛔A press inside the band but OFF the button — the 4px tolerance a thin
    // column carries for a pen — fired nothing, so that row still has to be
    // painted and the target is the opposite of what it reads.
    //
    // ⚠️THE VALUE CANNOT TELL THESE APART, so the CLAIM does. A button
    // claims the pointer on its own down, deeper than this detector, so by
    // now it has claimed if it was pressed at all. ⚠️And every column must
    // read LIVE for this to hold — a `valueOf` closing over a captured model
    // object still reports the last frame and sweeps backwards (that is why
    // `isLayerOnTimesheet` exists).
    final pointer = _downPointer;
    final pressedItsButton = pointer != null && controlOwnsTap(pointer);
    _targetValue = pressedItsButton ? value : !value;
    _painted.clear();
    if (pressedItsButton) {
      _painted.add(row.id);
    } else {
      _paintAt(row);
    }
    return true;
  }

  void _end() {
    _column = null;
    _targetValue = null;
    _painted.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) => _downPointer = event.pointer,
      // ⛔Cleared on the way out: a stale id would let the NEXT press be read
      // as 「a button already did this」 when nothing claimed at all.
      onPointerUp: (event) => _downPointer = null,
      onPointerCancel: (event) => _downPointer = null,
      child: _RailSwipeDetector(
        axis: widget.axis,
        columnAt: _columnAt,
        alongOf: _along,
        onStart: _start,
        onUpdate: (along) => _paintAt(widget.rowAt(along)),
        onEnd: _end,
        child: widget.child,
      ),
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
    required this.axis,
    required this.alongOf,
    required this.columnAt,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  /// Which way the rows run — the only thing here that knows about axes.
  final Axis axis;

  /// The coordinate ALONG the rail, out of a rail-local point.
  final double Function(Offset local) alongOf;

  /// Which COLUMN a press at this rail-local point is in, or -1 for none.
  final int Function(Offset local) columnAt;

  /// The press: which COLUMN it landed in, and where ALONG the rail. Returns
  /// false to decline.
  final bool Function(int columnIndex, double alongPosition) onStart;
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

    void down(DragDownDetails details) {
      _pressedColumn = widget.columnAt(details.localPosition);
      _engaged = _pressedColumn >= 0;
    }

    void start(DragStartDetails details) {
      if (!_engaged) {
        return;
      }
      _engaged = widget.onStart(
        _pressedColumn,
        widget.alongOf(details.localPosition),
      );
    }

    void update(DragUpdateDetails details) {
      if (_engaged) {
        widget.onUpdate(widget.alongOf(details.localPosition));
      }
    }

    void end(DragEndDetails _) {
      if (_engaged) {
        widget.onEnd();
      }
      _engaged = false;
    }

    void cancel() {
      if (_engaged) {
        widget.onEnd();
      }
      _engaged = false;
    }

    return AxisGestureDetector(
      axis: widget.axis,
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
      // 🚨ONE recogniser family, chosen by the axis — the law this rail
      // wrote down first; [AxisGestureDetector] is where it lives now, for
      // every axis drag.
      onDragDown: down,
      onDragStart: start,
      onDragUpdate: update,
      onDragEnd: end,
      onDragCancel: cancel,
      child: widget.child,
    );
  }
}

/// What a rail can do with ONE toggle column on ONE row: read it, flip it.
///
/// Null [valueOf] on a row means that row has no control in this column —
/// see [RailToggleColumn].
typedef RailToggle<TRow> = ({
  bool? Function(TRow row) valueOf,
  void Function(TRow row) toggle,
});

/// The rail's trailing padding past its last column.
const double _railTrailingPadding = 8.0;

/// 🚨★★★EVERY TOGGLE BUTTON A RAIL MOUNTS IS SWIPEABLE, AND THE LIST OF
/// WHICH IS NOT A PER-RAIL DECISION.
///
/// 유저 2026-08-29: 「그건 **버튼이면 다 가능**하도록」 · 「**로직적으로 다른
/// 규칙 두지말고 통일**」.
///
/// Before this, each rail hand-wrote its own column list, and the two lists
/// disagreed: the storyboard's rail mounted a timesheet toggle and a lane
/// twirl that no swipe could reach, while the layer rail swiped both. That
/// is the drift a maintained list always ends in, and the widget that wears
/// the claim already carried a note begging the two be kept in step.
///
/// ⇒ There is ONE construction. A rail passes what it can toggle; WHICH
/// columns exist, WHERE their bands fall and IN WHAT ORDER they are asked
/// are answered here for every rail at once. A column a rail cannot toggle
/// is absent because its argument is null, never because a list forgot it.
///
/// ⛔The controls left out are left out by KIND, not by rail: the mark chip,
/// the type button, the blend picker and the mute button all open flyouts
/// (the mute button is named a toggle and is not one — it opens the mixer),
/// and the opacity field is a slider. None has a value a sweep could paint.
/// If one ever gains a boolean, it gains a parameter here and both rails get
/// it in the same commit.
List<RailToggleColumn<TRow>> railSwipeColumns<TRow>({
  required double crossExtent,
  required double leadingOrigin,
  bool hasOnionColumn = false,
  bool hasBlendColumn = false,
  RailToggle<TRow>? visibility,
  RailToggle<TRow>? onion,
  RailToggle<TRow>? fx,
  RailToggle<TRow>? timesheet,
  RailToggle<TRow>? laneToggle,
}) {
  /// A LEADING column's x depends on the row: the nesting indent falls
  /// between the mark and the twirl, so the twirl and the sheet toggle move
  /// one whole slot per level. A rail that does not nest passes rows of
  /// depth 0 and gets the same band every time.
  ({double start, double end}) Function(int depth) leadingBand(
    LayerRailLeadingSlot slot,
  ) => (depth) {
    // The row plate's left border comes before its first cell, so a column
    // measured from the row's edge is that much further in than the slot
    // skeleton alone says.
    final start = leadingOrigin + layerRailLeadingWidthTo(to: slot);
    return (start: start, end: start + layerRailLeadingSlotWidth(slot));
  };

  /// Everything from [after] onward is what sits to this column's right,
  /// read off the slot skeleton — so adding a column cannot put the bands
  /// out of date.
  ({double start, double end}) Function(int depth) trailingBand(
    LayerRailTrailingSlot after,
    double width,
  ) {
    final edge =
        crossExtent -
        _railTrailingPadding -
        layerRailTrailingWidth(
          from: after,
          hasOnionColumn: hasOnionColumn,
          hasBlendColumn: hasBlendColumn,
        );
    // A little tolerance so a thin band is easy to hit with a pen.
    //
    // ⛔None on the leading bands: the twirl and the sheet toggle are
    // ADJACENT, so a padded band could only ever eat into its neighbour.
    // The trailing bands can afford the slack because it is what makes a
    // thin column easy to hit, and that argument stops applying the moment
    // the 4px belongs to another control.
    final at = (start: edge - width - 4, end: edge + 4);
    return (_) => at;
  }

  RailToggleColumn<TRow> column(
    ({double start, double end}) Function(int depth) bandAt,
    RailToggle<TRow> toggle,
  ) => (bandAt: bandAt, valueOf: toggle.valueOf, toggle: toggle.toggle);

  return [
    if (visibility != null)
      column(
        trailingBand(LayerRailTrailingSlot.mute, layerVisibilitySlotWidth),
        visibility,
      ),
    if (onion != null)
      column(
        trailingBand(LayerRailTrailingSlot.visibility, layerOnionSlotWidth),
        onion,
      ),
    if (fx != null)
      column(trailingBand(LayerRailTrailingSlot.onion, layerFxSlotWidth), fx),
    if (timesheet != null)
      column(leadingBand(LayerRailLeadingSlot.timesheet), timesheet),
    if (laneToggle != null)
      column(leadingBand(LayerRailLeadingSlot.laneToggle), laneToggle),
  ];
}
