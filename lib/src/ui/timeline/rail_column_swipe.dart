import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragGestureRecognizer, DragStartBehavior, PointerDownEvent;
import 'package:flutter/material.dart';
import '../../services/history_manager.dart';
import '../input/control_press_claim.dart' show PressFireWatch;
import '../input/value_control_pointers.dart';
import 'layer_rail_columns.dart';
import 'layer_label_controls.dart'
    show
        LayerRailColumnWidths,
        RailSwipeColumnPointer,
        layerClipSlotWidth,
        layerFxSlotWidth,
        layerGraphSlotWidth,
        layerLanePinSlotWidth,
        layerOnionSlotWidth,
        layerVisibilitySlotWidth;
import '../widgets/axis_bar_gesture.dart'
    show isOwningDragAlong, owningDragAlong;
import 'axis_turn.dart' show partAcross, partAlong;
import 'timeline_row_edges.dart';
import 'timeline_visible_range.dart';

/// A column a rail can SWIPE: where its band sits on a given row, what
/// value a row shows there, and how to flip that row.
///
/// 🚨A band RESOLVER rather than a fixed x-range: a button at the end of a
/// row's NAME stands where that row's name ends — a layer row keeps its
/// fold slot last (F-29), a header has none — so where the column is
/// depends on the row under the press (I-89 Q1). That is also why the
/// swipe paints by column IDENTITY once it has latched — one drag can
/// cross rows whose buttons stand at different places without ever
/// leaving its column. ↩️It was asked the row's DEPTH, for the leading
/// columns the folder indent used to push (I-1); the indent lives in the
/// name now, and no band read it.
///
/// [valueOf] returns null for a row that HAS NO control in this column (an
/// attach row's sheet slot holds an arrow, a laneless row has no twirl).
/// Null is skipped: a swipe cannot paint what a tap could not.
typedef RailToggleColumn<TRow> = ({
  ({double start, double end}) Function(TRow row) bandAt,
  bool? Function(TRow row) valueOf,
  void Function(TRow row) toggle,
});

/// A row the swipe landed on: the subject, and the identity the sweep
/// dedupes by so one drag paints each row once.
typedef RailSwipeRow<TRow> = ({TRow row, Object id});

/// [RailColumnSwipe.rowsIn] for a strip whose rows sit at [edges]: the rows
/// a segment covers ([TimelineRowEdges.rowsIn] — every row from the one
/// holding one end to the one holding the other, ends included), among the
/// ones the window [built]: a row not built is not on screen to paint.
/// Room between rows covers none.
///
/// 🚨★★★BOTH TIMELINE GRIDS ARE THAT STRIP, AND WRITING IT TWICE IS A COPY
/// WHATEVER THE TEXT (유저: 「사본 남으면 진짜 용서안할게」). The rail's rows
/// and the x-sheet's columns are the same rail turned on its side, so they
/// had the same division in point form all along; splitting the point into
/// a segment (F-66) is only what made the clone long enough to see, and the
/// architecture ratchet named the pair the moment it did.
///
/// ↩️It divided by one row pitch until a header graph (I-89 ③) stood
/// taller than its lanes; the edges are where the window cut the rows.
///
/// ⛔The STORYBOARD rail walks its own layout: it stacks a transition row,
/// S rows and a V row at three heights with lane groups between them, and
/// builds each track's slots only as far as the walk reaches.
///
/// [rowAt] is the ONLY thing left that differs between the two grids: what
/// a row at an index IS, and what identity it carries.
List<RailSwipeRow<TRow>> railRowsAlong<TRow>({
  required double from,
  required double to,
  required TimelineRowEdges edges,
  required TimelineVisibleRange built,
  required RailSwipeRow<TRow> Function(int index) rowAt,
}) {
  final covered = edges.rowsIn(from, to);
  if (covered == null) {
    return const [];
  }
  final first = math.max(covered.first, built.startIndex);
  final last = math.min(covered.last, built.endIndexExclusive - 1);
  return [for (var index = first; index <= last; index += 1) rowAt(index)];
}

/// The history a sweep writes into, provided by the hosts that wire rails
/// to a session.
///
/// 🚨ONE SWEEP IS ONE UNDO (swipe-is-one-undo, 유저 08-28: 「일괄로 버튼
/// 조작하고 언두하면 바꼈던 레이어들 다 한번에 언두되야하는데 안됨」 — the
/// 「일괄조작」 of I-1 is this swipe). A sweep marks the history before its
/// first write and folds everything after it into one step when it lets
/// go ([HistoryGestures.foldSince]). Measured before: three rows swept, three
/// steps, and one Ctrl+Z took back one row.
///
/// It also takes back what a sweep painted when the cursor draws back over
/// it (F-182) — exactly, by retracting the row's own step
/// ([HistoryGestures.retractSince]).
///
/// Absent — a rail mounted on its own — a sweep writes row by row, and a
/// row it draws back from is pressed again.
class RailSweepHistory extends InheritedWidget {
  const RailSweepHistory({
    super.key,
    required this.history,
    required this.changed,
    required super.child,
  });

  final HistoryGestures history;

  /// Tells the host a take-back moved the document. The forward writes
  /// notify through their own verbs; a take-back has no verb of its own.
  final VoidCallback changed;

  /// Read at a press, a move and a release, not while building — so no
  /// dependency.
  static RailSweepHistory? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RailSweepHistory>();

  /// Runs [body] — ONE press that writes many rows, the legend's twirl-all
  /// over a rail whose twirls are the rows' (F-360) — as ONE undo step, the
  /// same 「다 한번에 언두」 as a sweep's ([HistoryGestures.runAsOneStep]).
  /// Absent, [body] writes row by row, as a sweep does.
  static void asOneStep(
    BuildContext context,
    String description,
    VoidCallback body,
  ) {
    final history = maybeOf(context)?.history;
    if (history == null) {
      body();
      return;
    }
    history.runAsOneStep(description, body);
  }

  @override
  bool updateShouldNotify(RailSweepHistory oldWidget) =>
      history != oldWidget.history;
}

/// One row a sweep painted: whether it pressed the row's control, and how
/// many history steps that press wrote — what taking it back has to undo.
typedef _Stroke<TRow> = ({Object id, TRow row, bool pressed, int steps});

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
/// a way to name the rows a stretch of rail holds.
class RailColumnSwipe<TRow> extends StatefulWidget {
  const RailColumnSwipe({
    super.key,
    required this.axis,
    required this.columns,
    required this.rowsIn,
    required this.child,
  });

  /// The axis the ROWS run along: down for a rail, across for the x-sheet
  /// (which is the same rail transposed — layers are columns there).
  final Axis axis;

  /// The swipeable columns, in any order — a press picks the first whose
  /// band holds it.
  final List<RailToggleColumn<TRow>> columns;

  /// The rows a SEGMENT of the rail covers, in layout order — every row
  /// whose extent meets the stretch between [from] and [to], either way
  /// round, spacers left out. A segment of no length is the row under a
  /// point, so it answers with exactly that one row (or none).
  ///
  /// 🚨★★★A SEGMENT, NOT A POINT, AND THAT IS F-66 (유저 2026-09-10):
  ///
  /// > 「레이어라벨의 fx나 비지블버튼의 **드래그 일괄조작**이 이상함. 해당
  /// > 위치에 커서가 가면 off로 구현한거같은데, 이 경우 **렉걸리는** 상태에서
  /// > 아래로 끌면 **중간에 조작이 안 걸리는 레이어가 생긴다**」
  ///
  /// It WAS a point — `rowAt(along)`, asked once per pointer move — and a
  /// pointer move is not a promise to visit every row on the way. Drop a
  /// frame and the cursor arrives five rows down having reported nothing in
  /// between, so five rows were never painted. 유저 named the fix in the
  /// same message: 「**마지막으로 위치한 커서 사이 레이어들** 조작시키는게
  /// 렉걸려도 문제없이 조작될듯」.
  ///
  /// ⛔A DROPPED FRAME MUST MAKE THE SEGMENT LONGER, NEVER SPARSER, which is
  /// why the host answers for a stretch rather than the widget sampling one.
  /// A sampler needs a step, a step needs to be shorter than the shortest
  /// row, and the storyboard rail alone stacks three row heights — the host
  /// is the only one that knows its own layout, and it walks it exactly.
  final List<RailSwipeRow<TRow>> Function(double from, double to) rowsIn;

  final Widget child;

  @override
  State<RailColumnSwipe<TRow>> createState() => _RailColumnSwipeState<TRow>();
}

class _RailColumnSwipeState<TRow> extends State<RailColumnSwipe<TRow>> {
  RailToggleColumn<TRow>? _column;
  bool? _targetValue;

  /// The rows this sweep holds, in the order it reached them: the pressed
  /// row first, then outward. A cursor drawing back takes them off the top
  /// — the newest are always the farthest out.
  final List<_Stroke<TRow>> _strokes = <_Stroke<TRow>>[];
  final Set<Object> _held = <Object>{};

  /// The sweep's drag — offered a press only when it landed on a column's
  /// button ([_offer]), and taken on that press's first movement, any way
  /// it goes.
  ///
  /// 🚨★★★F-475 (유저 2026-10-26): 「버튼에서 시작한 조작은 스크롤을
  /// 발동시키지않음 … 법 하나로 통일」. A column's button stands its press
  /// down for this drag (the strong claim — [RailSwipeColumnPointer]), so
  /// THIS is what holds the press against the scrollers, and it is the law
  /// every drag verb on a control keeps ([owningDragAlong]): taken on the
  /// first movement. ↩️It was a one-axis drag that waited for the device's
  /// slop along the rail, and a pull ACROSS the rail never reached it — the
  /// sheet's two-way drag (F-351) took it and scrolled the rows: 「비지블이나
  /// 어니언은 좌우로하면 위아래 스크롤이 발동」.
  ///
  /// ⛔EVERY DEVICE. ↩️A finger was left out (F-8: the rail had to scroll
  /// under a finger, and a sweep that took every press on the rail killed
  /// that), so a finger pulled from a column's button scrolled the rows —
  /// 유저 2026-08-29: 「터치 좌표가 버튼인데 거기서 움직였다고 스크롤이
  /// 발생하는게 심각한 버그야」. The sweep is offered a column's presses
  /// alone now, so a finger off the buttons still scrolls the rail.
  late DragGestureRecognizer _drag = _sweepDrag();

  /// The column the press the drag holds landed on.
  int _pressedColumn = -1;

  /// The history as it stood just before a column's button fired on this
  /// press ([PressFireWatch]) — the button writes its step before the
  /// sweep can hear the down.
  HistoryMark? _pressMark;

  /// Where the sweep under way folds from ([RailSweepHistory]).
  HistoryMark? _sweepMark;

  void _markPress() =>
      _pressMark = RailSweepHistory.maybeOf(context)?.history.mark;

  /// Where along the rail the press was — one end of the stretch the sweep
  /// holds; the cursor is the other.
  ///
  /// 🚨★★★THE SWEEP IS CONTINUOUS AND THE POINTER IS NOT. Every update
  /// holds the whole stretch from the press to where the cursor lands, so
  /// the rows an unreported move flew over are painted by the move that
  /// arrives (F-66). ⛔It is set on the PRESS, not on the first update: the
  /// recogniser reports its start where the press was
  /// ([DragStartBehavior.down]).
  double? _startAlong;

  /// Paints [row] to the target: pressed only if it DISAGREES — a swipe
  /// sets a value, it does not flip each row it passes, and on a tri-state
  /// column that is what keeps the third state out of the sweep's way.
  ///
  /// A row with NO control in this column reads null and is held without
  /// a press: not that it agrees, but that there is nothing there to
  /// disagree — a sheet swipe crossing an attach row leaves the arrow alone.
  _Stroke<TRow> _paint(RailSwipeRow<TRow> row) {
    final column = _column!;
    final value = column.valueOf(row.row);
    if (value == null || value == _targetValue) {
      return (id: row.id, row: row.row, pressed: false, steps: 0);
    }
    final history = RailSweepHistory.maybeOf(context)?.history;
    final before = history?.mark.pushed ?? 0;
    column.toggle(row.row);
    return (
      id: row.id,
      row: row.row,
      pressed: true,
      steps: (history?.mark.pushed ?? 0) - before,
    );
  }

  /// Puts [stroke]'s row back as it was before the sweep reached it.
  ///
  /// 🚨F-182 (유저 2026-09-25): 「레이어 라벨 버튼 드래그 일괄조작, 원래
  /// 위치로 돌아가면 원복하도록」. ⛔NOT by pressing it again when the press
  /// wrote a step: a tri-state row the sweep turned off would come back
  /// ON, not mixed. Its own step is RETRACTED — undone exactly, and never
  /// offered to redo. A control with no history (the onion, a solo, the
  /// camera's view) has two states, so pressing again is exact there.
  void _takeBack(_Stroke<TRow> stroke) {
    if (!stroke.pressed) {
      return;
    }
    final scope = RailSweepHistory.maybeOf(context);
    final mark = _sweepMark;
    if (stroke.steps > 0 && scope != null && mark != null) {
      for (var step = 0; step < stroke.steps; step += 1) {
        scope.history.retractSince(mark);
      }
      scope.changed();
      return;
    }
    _column!.toggle(stroke.row);
  }

  /// The coordinate that runs ALONG the rail — down the layer rail, ACROSS
  /// the x-sheet's layer columns. It names the row.
  double _along(Offset local) => partAlong(widget.axis, local);

  /// The coordinate that runs ACROSS the rail. It names the column.
  ///
  /// 🚨These two are the whole axis story. Everything else here — the latch,
  /// the held stretch, the "only rows that disagree" rule — is written in
  /// along/across and does not know which way the rail points.
  double _across(Offset local) => partAcross(widget.axis, local);

  /// The row under a POINT — the segment of no length, asked of the one
  /// resolver the host implements.
  ///
  /// ⛔The host is NOT asked twice, once for points and once for stretches.
  /// Two questions that must agree about where a row begins are two answers
  /// that will one day disagree ([[no-copy-to-share]]); a point is a segment
  /// whose ends meet.
  RailSwipeRow<TRow>? _rowAt(double along) {
    final rows = widget.rowsIn(along, along);
    return rows.isEmpty ? null : rows.first;
  }

  /// Holds exactly the stretch from the press to [along]: rows the cursor
  /// has drawn back from are taken back, newest first, and rows it has
  /// reached are painted, outward from the press.
  void _sweepTo(double along) {
    final start = _startAlong;
    if (start == null) {
      return;
    }
    final stretch = widget.rowsIn(start, along);
    final reached = {for (final row in stretch) row.id};
    // The pressed row stays whatever happens: it is the press's, not the
    // sweep's.
    while (_strokes.length > 1 && !reached.contains(_strokes.last.id)) {
      final stroke = _strokes.removeLast();
      _held.remove(stroke.id);
      _takeBack(stroke);
    }
    for (final row in along >= start ? stretch : stretch.reversed) {
      if (_held.add(row.id)) {
        _strokes.add(_paint(row));
      }
    }
  }

  /// The column whose slot on the row under [local] holds it, or -1.
  int _columnAt(Offset local) {
    final row = _rowAt(_along(local));
    if (row == null) {
      return -1;
    }
    final across = _across(local);
    for (var index = 0; index < widget.columns.length; index += 1) {
      final band = widget.columns[index].bandAt(row.row);
      if (across >= band.start && across <= band.end) {
        return index;
      }
    }
    return -1;
  }

  /// Offers the sweep [event]'s press — when a column's BUTTON took it, and
  /// only then.
  ///
  /// 🚨★★★WHAT WAS PRESSED DECIDES (유저 2026-08-30: 「클릭이 버튼이면
  /// 스크롤 절대 발생안하게한다」). A column's button takes the strong claim
  /// on its own down ([RailSwipeColumnPointer]), deeper than this, so by now
  /// it has said so. A press anywhere else on the rail — the name, a slot
  /// with no button, the slider — is not the sweep's: it scrolls, drags the
  /// row or is the slider's, as it would with no sweep here at all.
  void _offer(PointerDownEvent event) {
    if (!valueControlOwnsPointer(event.pointer)) {
      return;
    }
    final column = _columnAt(event.localPosition);
    if (column < 0) {
      return;
    }
    _pressedColumn = column;
    _drag.addPointer(event);
  }

  DragGestureRecognizer _sweepDrag() =>
      owningDragAlong(widget.axis, debugOwner: this)
        // 🚨I-1, measured: with the default `DragStartBehavior.start` a
        // swipe MISSES A ROW. The recogniser reports its start where it WON
        // the arena and drops the movement that won as a delta, so no update
        // ever names the row in between. `down` fixes both halves: the start
        // reports the press, and the first movement arrives as an update.
        // The reason the default exists — content must not jump by the slop
        // when the drag begins — does not apply to a gesture that moves
        // nothing and only paints the rows it passes.
        ..dragStartBehavior = DragStartBehavior.down
        ..onStart = ((details) =>
            _start(_pressedColumn, _along(details.localPosition)))
        ..onUpdate = ((details) => _sweepTo(_along(details.localPosition)))
        ..onEnd = ((_) => _end())
        ..onCancel = _end;

  /// Latches the sweep on [columnIndex], from the row under [alongPosition].
  ///
  /// 🚨★★★ITS BUTTON HAS ALREADY DONE THIS ROW. 유저 2026-08-30: 「버튼은
  /// 기본적으로 **누른순간 작동**하고 **누른채로 드래그시 일괄조작** 작동」.
  /// The press fired the button during the pointer-down — [_offer] takes
  /// only a press a column's button took — so the row already holds what was
  /// asked for, and the sweep spreads THAT. Painting it again toggles it
  /// straight back (measured: the row appeared twice in the toggle log).
  ///
  /// ⚠️So every column must read LIVE — a `valueOf` closing over a captured
  /// model object still reports the last frame and sweeps backwards (that is
  /// why `isLayerOnTimesheet` exists).
  ///
  /// ↩️A press BESIDE a button started a sweep too: a column's band was
  /// padded 4px past its slot either side 「so a thin band is easy to hit
  /// with a pen」 (the eye's first swipe, 2026-07-15 — nobody asked for it),
  /// and that press, which fired nothing, painted its own row first. The
  /// slots stand edge to edge, so the pad was the next button's: pressing
  /// the onion near the eye and pulling down swept the EYE column (F-475).
  void _start(int columnIndex, double alongPosition) {
    final row = _rowAt(alongPosition);
    if (row == null) {
      return;
    }
    final column = widget.columns[columnIndex];
    // A row carrying no control in this column has no value to latch —
    // pressing an attach row's arrow must not begin painting the sheet
    // column it stands in.
    final value = column.valueOf(row.row);
    if (value == null) {
      return;
    }
    _column = column;
    _targetValue = value;
    _strokes
      ..clear()
      ..add((id: row.id, row: row.row, pressed: false, steps: 0));
    _held
      ..clear()
      ..add(row.id);
    _startAlong = alongPosition;
    // The button's own step is the sweep's first.
    _sweepMark = _pressMark;
  }

  void _end() {
    final mark = _sweepMark;
    if (mark != null) {
      RailSweepHistory.maybeOf(
        context,
      )?.history.foldSince(mark, 'Sweep a rail column');
    }
    _sweepMark = null;
    _column = null;
    _targetValue = null;
    _strokes.clear();
    _held.clear();
    _startAlong = null;
  }

  @override
  void didUpdateWidget(RailColumnSwipe<TRow> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isOwningDragAlong(_drag, widget.axis)) {
      _drag.dispose();
      _drag = _sweepDrag();
    }
  }

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _offer,
    // ⛔Cleared on the way out: a stale mark would fold from a press that is
    // long gone.
    onPointerUp: (event) => _pressMark = null,
    onPointerCancel: (event) => _pressMark = null,
    child: PressFireWatch(beforeFire: _markPress, child: widget.child),
  );
}

/// What a rail can do with ONE toggle column on ONE row: read it, flip it.
///
/// Null [valueOf] on a row means that row has no control in this column —
/// see [RailToggleColumn].
typedef RailToggle<TRow> = ({
  bool? Function(TRow row) valueOf,
  void Function(TRow row) toggle,
});

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
///
/// 🗣️F-475 (유저 2026-10-26): 「클리핑버튼도 위아래 드래그로 여러 버튼
/// 동시조작 가능하게」. ↩️The clip toggle (I-92) came after this list and
/// never joined it — not left out, forgotten.
List<RailToggleColumn<TRow>> railSwipeColumns<TRow>({
  required double crossExtent,
  required double leadingOrigin,
  required LayerRailColumnWidths columns,
  required LayerRailOptionalColumns optionalColumns,
  ({RailToggle<TRow> toggle, double Function(TRow row) after})? graph,
  RailToggle<TRow>? visibility,
  RailToggle<TRow>? onion,
  RailToggle<TRow>? fx,
  RailToggle<TRow>? clip,
  RailToggle<TRow>? timesheet,
  RailToggle<TRow>? laneToggle,
  ({RailToggle<TRow> toggle, double inset})? lanePin,
}) {
  /// A LEADING column, read off the slot skeleton from the row's start.
  ({double start, double end}) Function(TRow row) leadingBand(
    LayerRailLeadingSlot slot,
  ) {
    // The row plate's left border comes before its first cell, so a column
    // measured from the row's edge is that much further in than the slot
    // skeleton alone says.
    final start = leadingOrigin + layerRailLeadingWidthTo(to: slot);
    final at = (start: start, end: start + layerRailLeadingSlotWidth(slot));
    return (_) => at;
  }

  /// Where [from] begins: everything from it onward is what sits to its
  /// right, read off the slot skeleton — so adding a column cannot put the
  /// bands out of date.
  double trailingEdge(LayerRailTrailingSlot from) =>
      crossExtent -
      layerRailEndPadding -
      layerRailTrailingWidth(
        columns: columns,
        from: from,
        optionalColumns: optionalColumns,
      );

  /// The column right before [after] — its slot, and nothing either side:
  /// the slots stand edge to edge, so anything past one is the next
  /// button's (F-475; the pad that was here is told at
  /// `_RailColumnSwipeState._start`).
  ({double start, double end}) Function(TRow row) trailingBand(
    LayerRailTrailingSlot after,
    double width,
  ) {
    final edge = trailingEdge(after);
    final at = (start: edge - width, end: edge);
    return (_) => at;
  }

  /// A MEMBER LANE's column, [inset] from the row's end — where its cell
  /// lays it, which no slot skeleton does. ⛔No slack either side: the
  /// chain, or the name a press stands on, is before it, and the value a
  /// gap after.
  ({double start, double end}) Function(TRow row) laneEndBand(
    double inset,
    double width,
  ) {
    final end = crossExtent - inset;
    final at = (start: end - width, end: end);
    return (_) => at;
  }

  /// A button at the END OF A ROW'S NAME (I-89 Q1), [after] short of the
  /// trailing run on that row — what its row lays past it there. ⛔No slack
  /// either side: the name, or a button of the name's, is before it, and a
  /// slot after.
  ({double start, double end}) Function(TRow row) nameEndBand(
    double Function(TRow row) after,
    double width,
  ) {
    final edge = trailingEdge(LayerRailTrailingSlot.clip);
    return (row) {
      final end = edge - after(row);
      return (start: end - width, end: end);
    };
  }

  RailToggleColumn<TRow> column(
    ({double start, double end}) Function(TRow row) bandAt,
    RailToggle<TRow> toggle,
  ) => (bandAt: bandAt, valueOf: toggle.valueOf, toggle: toggle.toggle);

  return [
    if (visibility != null)
      column(
        trailingBand(LayerRailTrailingSlot.opacity, layerVisibilitySlotWidth),
        visibility,
      ),
    if (onion != null)
      column(
        trailingBand(LayerRailTrailingSlot.visibility, layerOnionSlotWidth),
        onion,
      ),
    if (fx != null)
      column(trailingBand(LayerRailTrailingSlot.onion, layerFxSlotWidth), fx),
    if (clip != null)
      column(trailingBand(LayerRailTrailingSlot.fx, layerClipSlotWidth), clip),
    if (graph != null)
      column(nameEndBand(graph.after, layerGraphSlotWidth), graph.toggle),
    if (lanePin != null)
      column(
        laneEndBand(lanePin.inset, layerLanePinSlotWidth),
        lanePin.toggle,
      ),
    if (timesheet != null)
      column(leadingBand(LayerRailLeadingSlot.timesheet), timesheet),
    if (laneToggle != null)
      column(leadingBand(LayerRailLeadingSlot.laneToggle), laneToggle),
  ];
}
