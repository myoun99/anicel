/// Dragging a rail ROW to move it — the gesture half of the row-order
/// round, riding the policy P2a put down.
///
/// The rail row itself is the handle (user, 2026-08-07): no new column, and
/// the pen/touch split the timeline's edit gestures already use decides the
/// conflict — the rail scrolls along the SAME axis the drag runs, so
/// something has to. Pen and mouse move the row; a finger scrolls, unless
/// the input policy has been flipped to make touch edit like the pen.
///
/// Long-press is not an option here and never was: it does not fire at all
/// inside a scroll view (measured, R10).
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import '../../models/layer_kind.dart';

import '../../models/layer.dart';
import '../../models/layer_effect.dart' show EffectId;
import '../../models/layer_id.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track_id.dart';
import '../../models/app_input_settings.dart' show AppInput;
import '../input/eager_pan_gesture_recognizer.dart';
import '../theme/app_theme.dart' show AppShapes;
import 'layer_drop_policy.dart';
import 'property_lane_model.dart';
import 'effect_lane_policy.dart' show effectGroupLaneId, parseEffectLaneId;
import 'held_row_pin.dart';
import 'row_control_surface.dart';
import 'timeline_edge_auto_pan.dart' show edgeAutoPanApply;

/// WHAT a row drag is moving. Two kinds share the gesture, the caret and
/// the device policy; what differs is the list they are re-ordering, and
/// that difference belongs here rather than in two copies of the widget.
sealed class LayerRowDragSubject {
  const LayerRowDragSubject();

  /// Whether a caret raised for [other] belongs on rows of THIS subject's
  /// kind — one layer stack for layer rows, one layer's chain for effects
  /// (a Blur dragged on layer A must raise no caret on layer B).
  bool sharesLaneWith(LayerRowDragSubject other);
}

/// A rail ROW: the layer stack's own order.
final class LayerRowSubject extends LayerRowDragSubject {
  const LayerRowSubject(this.layerId);

  final LayerId layerId;

  /// A file over the layer area raises a new row's caret in this lane too.
  @override
  bool sharesLaneWith(LayerRowDragSubject other) =>
      other is LayerRowSubject || other is MediaPlacementSubject;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerRowSubject && other.layerId == layerId;

  @override
  int get hashCode => Object.hash(LayerRowSubject, layerId);
}

/// A FILE from the pool over the layer area — not a row (유저 2026-09-11:
/// 「레이어 영역(가로선) → 새 레이어」). The caret it raises is a new row's,
/// so it shares the layer stack's lane; nothing lifts, because no row on
/// the rail is what the pointer holds.
final class MediaPlacementSubject extends LayerRowDragSubject {
  const MediaPlacementSubject();

  @override
  bool sharesLaneWith(LayerRowDragSubject other) => other is LayerRowSubject;

  @override
  bool operator ==(Object other) => other is MediaPlacementSubject;

  @override
  int get hashCode => (MediaPlacementSubject).hashCode;
}

/// A storyboard V ROW: the project's track order (R5 #9).
///
/// Its own kind rather than a [LayerRowSubject] over a carrier layer,
/// because the two must answer `sharesLaneWith` differently — a track
/// dragged on the storyboard must raise no caret among the SE rows one row
/// below it, and a carrier layer would have looked exactly like one.
///
/// The user's decision (2026-08-09): the track list IS the composite order,
/// so this drag moves the picture, not only the row.
final class TrackRowSubject extends LayerRowDragSubject {
  const TrackRowSubject(this.trackId);

  final TrackId trackId;

  @override
  bool sharesLaneWith(LayerRowDragSubject other) => other is TrackRowSubject;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackRowSubject && other.trackId == trackId;

  @override
  int get hashCode => Object.hash(TrackRowSubject, trackId);
}

/// An fx GROUP HEADER: one layer's effect chain. The Transform group is
/// never a subject — it is not a chain member, it is where the chain ends.
final class EffectRowSubject extends LayerRowDragSubject {
  const EffectRowSubject(this.layerId, this.effectId);

  final LayerId layerId;
  final EffectId effectId;

  @override
  bool sharesLaneWith(LayerRowDragSubject other) =>
      other is EffectRowSubject && other.layerId == layerId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EffectRowSubject &&
          other.layerId == layerId &&
          other.effectId == effectId;

  @override
  int get hashCode => Object.hash(EffectRowSubject, layerId, effectId);
}

/// ANY lane row, as a SELECTION anchor — a transform lane, an fx parameter,
/// an effect header being spanned rather than re-ordered.
///
/// 🚨B4-3 (유저): 「행의 **다른 fx끼리 넘어서 선택범위가 불가능.** 그 너머의
/// 다른 행 선택해야 그때서야 가능. **이런 다른규칙 삭제좀하자고.**」
///
/// ⚠️It answers [sharesLaneWith] false for everything, and that is the whole
/// difference: this subject can be selected FROM and never re-ordered, so it
/// must raise no caret anywhere. [EffectRowSubject] stays for the rows that
/// really do move a chain — being re-orderable is a capability some lanes
/// have, not a second kind of row.
final class LaneRowSubject extends LayerRowDragSubject {
  const LaneRowSubject(this.layerId, this.laneId);

  final LayerId layerId;
  final String laneId;

  @override
  bool sharesLaneWith(LayerRowDragSubject other) => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaneRowSubject &&
          other.layerId == layerId &&
          other.laneId == laneId;

  @override
  int get hashCode => Object.hash(LaneRowSubject, layerId, laneId);
}

/// T5: what a row drag's subject is CALLED in the selection's own words.
///
/// The two vocabularies existed side by side — the drag names a subject, the
/// selection names an address — and the seam between them was where 「이 종류는
/// 선택 못 함」 hid. Naming every subject makes the question disappear rather
/// than answering it per kind.
///
/// An fx header's address is its GROUP LANE, which is what the rail already
/// draws it as; nothing new is invented here.
///
/// ⚠️It lives BESIDE the subjects rather than on a rail, because both rails
/// have to give the same answer. It sat as a private method of the timeline's
/// host, which is why the storyboard's rail could not offer row selection at
/// all: the hooks that need it are optional, and a surface with no way to
/// name its subjects passed null for all of them and silently skipped the
/// select-first step (A5-3②).
TimelineRowAddress timelineRowAddressOfDragSubject(
  LayerRowDragSubject subject,
) => switch (subject) {
  LayerRowSubject(:final layerId) => LayerRowAddress(layerId),
  EffectRowSubject(:final layerId, :final effectId) => LaneRowAddress(
    layerId,
    effectGroupLaneId(effectId),
  ),
  TrackRowSubject(:final trackId) => TrackRowAddress(trackId),
  // B4-3: a lane anchors a selection at its OWN address. The fx header case
  // above lands on the same kind of address — it is reached through the
  // subject that can also re-order a chain.
  LaneRowSubject(:final layerId, :final laneId) => LaneRowAddress(
    layerId,
    laneId,
  ),
  // A file is not a row: no surface asks a selection about one.
  MediaPlacementSubject() => throw StateError('a pool file is not a row'),
};

/// A row drag in flight, as the rails draw it.
class LayerRowDragState {
  const LayerRowDragState({
    required this.subject,
    required this.caretSlot,
    required this.legal,
    this.joinLabel,
    this.onRowTarget,
  });

  /// What the pointer holds (whatever else travels with it is the policy's
  /// business, not the caret's).
  final LayerRowDragSubject subject;

  /// Where the caret sits, as a gap in the surface's LAYER row list: 0 is
  /// before the first, `length` after the last.
  final int caretSlot;

  /// Whether releasing here would move anything. An illegal landing draws
  /// no caret rather than a red one — the row simply stays put.
  final bool legal;

  /// What the drop would additionally DO, for the caret to say out loud:
  /// the folder the row would join. Null when the drop only re-orders.
  ///
  /// A structural change has to be visible before the release, not
  /// discovered after it.
  final String? joinLabel;

  /// R5 #15: the row the pointer is ON, when it is over a row's middle
  /// rather than near a boundary. Non-null replaces the caret entirely —
  /// the drop is "into this row" and the row lights instead, because a line
  /// between two rows cannot mean "inside one of them".
  final LayerId? onRowTarget;
}

/// What a rail needs to run a row drag. Null anywhere leaves the rows
/// display-only, which is what a passive host wants.
class TimelineRowDragHooks {
  const TimelineRowDragHooks({
    required this.drag,
    required this.onBegin,
    required this.onUpdate,
    required this.onRowTarget,
    this.onTrackUpdate,
    required this.onEffectUpdate,
    required this.onEnd,
    required this.onCancel,
    this.isInRowSelection,
    this.onSelectBegin,
    this.onSelectEnd,
    this.onPlacementHover,
    this.onPlacementLeave,
    this.acceptsPlacement,
  });

  final ValueListenable<LayerRowDragState?> drag;

  final void Function(LayerRowDragSubject subject) onBegin;

  /// The caret moved to a slot of the LAYER row list. [displayLayers] is
  /// the list the SURFACE renders, so the session can map the slot onto the
  /// model without guessing which way this rail runs.
  ///
  /// F-31②: [pointerInRow] is the row the pointer stands IN — null over a
  /// lane, or from a surface with no rail rows to name. The gap alone
  /// cannot say which side of a group's boundary the drag came to rest on;
  /// this is the half that can.
  final void Function(
    List<Layer> displayLayers,
    int slot, {
    LayerId? pointerInRow,
  })
  onUpdate;

  /// R5 #15: the pointer is ON [targetId] rather than between rows — the
  /// intent a caret has no gap to express (an empty folder's inside).
  ///
  /// [slot] travels with it as the FALLBACK, and it has to: a row whose
  /// middle means nothing (an ordinary drawing row cannot swallow anything)
  /// must still re-order, and only the model knows which rows those are.
  /// Sending both keeps that judgement in one place instead of teaching
  /// every rail what a folder is.
  final void Function(List<Layer> displayLayers, int slot, LayerId targetId)
  onRowTarget;

  /// R5 #9: the caret moved to a slot of the TRACK list. No display list
  /// travels with it — the storyboard renders tracks top-down in the
  /// project's own order, so the slot needs no translation.
  ///
  /// Null on every hook set that has no tracks to re-order, which is every
  /// surface except the storyboard.
  final void Function(int slot)? onTrackUpdate;

  /// The caret moved within one layer's effect CHAIN. [displayEffects] is
  /// that chain in the order this surface renders it — the rail lists it
  /// one way and the sheet the other, and the session infers which from
  /// the list rather than being told.
  final void Function(LayerId layerId, List<EffectId> displayEffects, int slot)
  onEffectUpdate;

  /// ⑨ (user, 2026-08-12): 「첫 드래그가 선택(1개/여러 개), 그 다음이 드래그.
  /// 타임라인 프레임과 **완전히 같은 순서**」.
  ///
  /// Whether a press on [subject] is already INSIDE the row selection. True
  /// makes this drag the MOVE, exactly as a pan starting inside a cell
  /// selection moves it; false makes it a fresh row SELECT.
  ///
  /// NULL is a third answer and it is load-bearing: "this subject does not
  /// take part in row selection at all". An fx HEADER is the case — its
  /// drag re-orders a chain, and reading `false` there would have turned
  /// every chain drag into a selection of nothing. A null hook says the
  /// same thing for a whole rail (no row selection here), so both the
  /// per-subject and the per-surface answer are one field.
  final bool? Function(LayerRowDragSubject subject)? isInRowSelection;

  /// ⑨: the select drag's anchor, at the press.
  ///
  /// Its UPDATE is not here but on the widget
  /// ([LayerRowDragTarget.onSelectCrossed]), for the same reason the caret's
  /// is: the span is a slice of what the RAIL draws, so the host closes over
  /// its own row list rather than every rail teaching this widget its order.
  final void Function(LayerRowDragSubject subject)? onSelectBegin;

  /// ⑨: the select drag's release. The span STAYS — this only closes the
  /// anchor, so the next press decides afresh whether it is inside.
  final VoidCallback? onSelectEnd;

  final VoidCallback onEnd;
  final VoidCallback onCancel;

  /// A file from the pool standing over the layer area at the gap [slot]
  /// of [displayLayers] — the caret the new row a drop makes would take
  /// (「레이어 영역(가로선) → 새 레이어」). Null on surfaces the pool cannot
  /// drop on.
  final void Function(List<Layer> displayLayers, int slot, String path)?
  onPlacementHover;

  /// That file left the layer area, or was let go on it.
  final VoidCallback? onPlacementLeave;

  /// Whether that file can land at that gap — the drop's own answer, which
  /// the drag's chip wears (「불가능 = 칩의 금지 표시」). Null is yes.
  final bool Function(List<Layer> displayLayers, int slot, String path)?
  acceptsPlacement;
}

/// The caret's thickness and colour, shared by every rail that draws one.
const double layerRowCaretThickness = 2;

/// One rail row, made draggable and able to show the caret on its own
/// edges.
///
/// The caret rides HERE rather than in an overlay of its own because the
/// rail's rows are the only thing that knows where a row boundary is —
/// windowed, virtualized and (on the storyboard) unequal in height. An
/// overlay would have to re-derive that geometry, and re-derived geometry
/// is the defect this rail keeps paying for (R9 #22, R9 #25).
///
/// [child] is passed through untouched, so a memoized row stays memoized:
/// only this thin wrapper rebuilds while a drag is in flight.
class LayerRowDragTarget extends StatelessWidget {
  const LayerRowDragTarget({
    super.key,
    required this.subject,
    required this.slotBefore,
    required this.rowExtent,
    required this.axis,
    required this.hooks,
    required this.onCrossed,
    this.onSelectCrossed,
    required this.child,
    this.isLastRow = false,
    this.grabOffsetWithinRun = 0,
    this.onGripTaken,
    this.onGripReleased,
  }) : canReorder = true;

  /// 🚨★★★A row that CANNOT BE REORDERED can still be SELECTED.
  ///
  /// 유저 F-16: 「다른 레이어에서 선택범위 시작해서 카메라나 트랜지션레이어로
  /// 선택범위 작동가능한데 **카메라나 트랜지션레이어에서 선택범위 시작하려하면
  /// 작동안함**」 — and the law they pinned when the ban was made: 「막으라고
  /// 한 것은 **드래그 이동뿐**」.
  ///
  /// ⛔Both rails used to answer this by mounting **no target at all**
  /// (`if (!kind.reordersInCut) return child;`), and the target
  /// carries BOTH halves of the drag — so 「이동 불가」 silently answered
  /// 「선택 불가」 too. **한 플래그가 두 질문에 답한 것이다.**
  ///
  /// This constructor takes only what SELECTING needs: no caret, no slot,
  /// no `onCrossed`. A select-only row therefore cannot be handed a move
  /// destination by accident — the invariant is in the shape.
  const LayerRowDragTarget.selectOnly({
    super.key,
    required this.subject,
    required this.rowExtent,
    required this.axis,
    required this.hooks,
    required this.onSelectCrossed,
    required this.child,
  }) : canReorder = false,
       grabOffsetWithinRun = 0,
       onGripTaken = null,
       onGripReleased = null,
       slotBefore = 0,
       isLastRow = false,
       onCrossed = _neverCrosses;

  static void _neverCrosses(int steps, int? onRow, int inRow) {}

  /// Whether this row may be MOVED. False rows still select.
  final bool canReorder;

  /// What this row would move if it were grabbed.
  final LayerRowDragSubject subject;

  /// The caret slot on this row's LEADING edge; the trailing edge is
  /// [slotBefore] + 1. Stated as a slot rather than an index because a
  /// caret lives between rows, not on one.
  final int slotBefore;

  /// This row's extent along the rail (its height on the timeline, its
  /// width on the sheet) — the drag counts rows in these, never in an
  /// assumed pitch.
  final double rowExtent;

  /// How much of [rowExtent] lies BEFORE this widget's own box.
  ///
  /// Zero everywhere the handle IS the run — every timeline rail row. The
  /// storyboard's V row is the exception and the reason this exists: its
  /// pitch is the whole track GROUP (S rows, the transition row, open
  /// lanes) while the widget the pointer grabs is the V label row sitting
  /// near that group's end. Measured, 2026-08-12: a press in the V row's
  /// middle reported 32 of a 154px run — a fifth of the way in, when the
  /// pointer was really four fifths down.
  ///
  /// It did not matter while the caret was a count of TRAVEL. Since ④ the
  /// caret is where the pointer IS, so the two boxes have to be the same
  /// box or the answer is off by most of a row.
  final double grabOffsetWithinRun;

  /// The rail's own direction.
  final Axis axis;

  final TimelineRowDragHooks? hooks;

  /// Reports the pointer's travel in ROWS. The surface turns that into a
  /// slot and tells the session — because the surface is what knows how its
  /// rows map onto the list being re-ordered. A layer row is one row per
  /// slot; an fx header may have its members twirled open between it and
  /// the next header, so counting rows here and slots there is the only
  /// arrangement that stays honest on both.
  ///
  /// [onRow] (R5 #15) is the row the pointer is INSIDE — its offset in rows
  /// from this one — when it sits in a row's middle band rather than near a
  /// boundary. Null means the pointer is near a boundary, which is a gap
  /// and therefore a caret. The two travel together so a surface cannot
  /// draw one answer and commit the other.
  final void Function(int crossedRows, int? onRow, int inRow) onCrossed;

  /// ⑨: the SELECT drag's travel, in whole rows from the pressed row.
  ///
  /// Beside [onCrossed] rather than inside the hooks for the same reason
  /// that one is: the host closes over the row list it drew, so this widget
  /// never has to know which way its rail runs.
  final void Function(int rowDelta)? onSelectCrossed;

  /// Whether this is the last row of the rail — only it can show the
  /// trailing caret, or two adjacent rows would both draw the same gap.
  final bool isLastRow;

  /// A5 (2026-08-17): the press landed here and its recognizer lives in
  /// this row's State — a host that windows its rows listens so it can
  /// keep this ONE row built while the window slides past it ("a press
  /// that lands on a control belongs to that control", the T30 law, needs
  /// the control to outlive the scroll). Fired at gesture begin; the
  /// release/cancel/unmount all fire [onGripReleased]. Hosts that build
  /// every row (storyboard, x-sheet headers) simply don't listen.
  final VoidCallback? onGripTaken;

  /// The other half of [onGripTaken].
  final VoidCallback? onGripReleased;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hooks = this.hooks;
    if (hooks == null) {
      return child;
    }
    return _LayerRowDragBody(
      subject: subject,
      canReorder: canReorder,
      slotBefore: slotBefore,
      rowExtent: rowExtent,
      axis: axis,
      hooks: hooks,
      onCrossed: onCrossed,
      onSelectCrossed: onSelectCrossed,
      isLastRow: isLastRow,
      grabOffsetWithinRun: grabOffsetWithinRun,
      onGripTaken: onGripTaken,
      onGripReleased: onGripReleased,
      child: child,
    );
  }
}

class _LayerRowDragBody extends StatefulWidget {
  const _LayerRowDragBody({
    required this.subject,
    required this.slotBefore,
    required this.rowExtent,
    required this.grabOffsetWithinRun,
    required this.axis,
    required this.hooks,
    required this.onCrossed,
    required this.canReorder,
    required this.isLastRow,
    this.onSelectCrossed,
    this.onGripTaken,
    this.onGripReleased,
    required this.child,
  });

  final LayerRowDragSubject subject;
  final int slotBefore;
  final double rowExtent;
  final double grabOffsetWithinRun;
  final Axis axis;
  final TimelineRowDragHooks hooks;
  final void Function(int crossedRows, int? onRow, int inRow) onCrossed;

  /// See [LayerRowDragTarget.canReorder] — false rows always select.
  final bool canReorder;
  final void Function(int rowDelta)? onSelectCrossed;
  final VoidCallback? onGripTaken;
  final VoidCallback? onGripReleased;
  final bool isLastRow;
  final Widget child;

  @override
  State<_LayerRowDragBody> createState() => _LayerRowDragBodyState();
}

class _LayerRowDragBodyState extends State<_LayerRowDragBody> {
  double _travelled = 0;

  /// Where inside this row the press landed, as a fraction of its extent.
  ///
  /// R5 #15 needs it: travel alone says how far the pointer went, not where
  /// it IS, and "inside a row's middle" is a question about where it is.
  /// Grabbing a row near its bottom edge and moving half a row lands the
  /// pointer in the NEXT row, which travel-from-the-grab cannot tell you.
  double _grabFraction = 0.5;

  /// True while this press landed on a CONTROL and so starts nothing.
  bool _onControl = false;

  void _begin(Offset localPosition, {required Offset globalPosition}) {
    // 🚨H1 (유저 2026-08-21): 「버튼쪽 탭다운해서 움직이면 선택범위
    // 작동해버리는데 … 버튼쪽 클릭하면 선택범위 작동 안 하도록. 그 외 부분.
    // 레이어이름영역이나 그 외 버튼 요소가 아닌 부분만 작동하도록」.
    //
    // The recognizer has to cover the WHOLE row — the name area and the
    // blank between controls are what you grab a row by, and neither is a
    // widget of its own — so the exclusion is asked at the PRESS instead
    // of carved out of the gesture's box. [RowControlSurface] is the mark
    // the rail's shared slot builder puts on every slot that holds
    // something; an empty slot is reserved space, not a button, and stays
    // grabbable.
    //
    // ⛔Decided ONCE here, like which drag this is: a gesture that changed
    // its mind halfway would be a row that starts moving because the
    // finger drifted off a button.
    _onControl = RowControlSurface.covers(context, globalPosition);
    if (_onControl) {
      return;
    }
    _travelled = 0;
    final extent = widget.rowExtent;
    final main = widget.axis == Axis.horizontal
        ? localPosition.dy
        : localPosition.dx;
    // Measured in the RUN, not in the grabbed widget — see
    // [LayerRowDragTarget.grabOffsetWithinRun]. The two are the same box
    // everywhere except the storyboard's V row.
    _grabFraction = extent > 0
        ? ((widget.grabOffsetWithinRun + main) / extent).clamp(0.0, 1.0)
        : 0.5;
    widget.onGripTaken?.call();
    // ⑨: which of the two drags this is, decided ONCE at the press and not
    // re-asked — the same reason the cells decide it at the press too
    // (their range gesture's `isInSelection`). A drag that changed its mind halfway
    // would be a row moving because the selection happened to grow under it.
    final inSelection = widget.hooks.isInRowSelection?.call(widget.subject);
    // 🚨A row that cannot be reordered ALWAYS takes the select half — the
    // ban is on moving, not on selecting (F-16). ⛔Without this the two
    // questions ride one flag again, just one layer down.
    // ↩️「ALWAYS」 until F-16-Q1: inside the selection it lifts (below).
    //
    // 🗣️F-16-Q1 = visual. 유저: 「추가로 드래그로직도 작동은 하도록. 어차피
    // 결과적으로 이동될곳 없어서 이동은 안되지만 통일감 내고싶음」 — so a row
    // that cannot be reordered takes the SAME fork as every other row: pressed
    // INSIDE the selection it is picked up and shows it, and on release it
    // settles where it was. No caret, no crossing, no move verb — the
    // select-only shape still cannot be handed a destination.
    if (!widget.canReorder && inSelection == true) {
      setState(() => _lifting = true);
      return;
    }
    _selecting = !widget.canReorder || inSelection == false;
    if (_selecting) {
      widget.hooks.onSelectBegin?.call(widget.subject);
      return;
    }
    _moving = true;
    widget.hooks.onBegin(widget.subject);
    widget.onCrossed(0, null, 0);
  }

  /// ⑨: true while this drag is growing the row SELECTION rather than
  /// moving rows.
  bool _selecting = false;

  /// F-16: true while an UNMOVABLE row is held inside the row selection —
  /// picked up and showing it, going nowhere. The row's own state: no move
  /// verb starts, so there is nothing to commit or cancel when it lets go.
  bool _lifting = false;

  /// True while this drag is MOVING rows — the flag [dispose] reads to know
  /// an open session verb would otherwise leak. Cleared before the hooks
  /// fire so the backstop cannot double-commit.
  bool _moving = false;

  /// The release, whichever drag this was. Cancel takes the same path: a
  /// select has nothing to roll back (the span it drew IS the result), and
  /// the move's own cancel is the hooks'.
  void _end({bool cancelled = false}) {
    // H1: a press that landed on a control started nothing, so there is no
    // grip to release and no verb to commit or cancel.
    if (_onControl) {
      _onControl = false;
      return;
    }
    widget.onGripReleased?.call();
    if (_lifting) {
      setState(() => _lifting = false);
      return;
    }
    if (_selecting) {
      _selecting = false;
      widget.hooks.onSelectEnd?.call();
      return;
    }
    if (!_moving) {
      return;
    }
    _moving = false;
    if (cancelled) {
      widget.hooks.onCancel();
      return;
    }
    widget.hooks.onEnd();
  }

  @override
  void dispose() {
    // A mid-drag unmount lands the operation AFTER the frame rather than
    // leaking an open session verb (R12-③ — the same backstop the range
    // gesture, the comma grip and the edit chrome already carry; this was
    // the ONE drag widget in the family missing it). Reached when the row
    // itself disappears mid-drag (layer deleted, panel torn down) — the
    // window sliding past the row no longer unmounts it, the host pins it.
    if (_selecting || _moving) {
      final hooks = widget.hooks;
      final selecting = _selecting;
      _selecting = false;
      _moving = false;
      widget.onGripReleased?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (selecting) {
          hooks.onSelectEnd?.call();
        } else {
          hooks.onEnd();
        }
      });
    }
    super.dispose();
  }

  /// The row the pointer sits in and how far through it, measured from this
  /// row's leading edge.
  ///
  /// This and the caret's gap are the SAME measurement read at two
  /// resolutions, and since ④ they cannot disagree: inside a boundary band
  /// the nearest gap IS that boundary (`within < 0.3` rounds to this row's
  /// own edge, `> 0.7` to the next one), and in the middle band the on-row
  /// drop answers instead so the gap is never consulted. They used to
  /// disagree — travel said "one place down" while the pointer was still in
  /// the middle band — and which one you got depended on which path ran.
  /// Which row the pointer is in, and whether it is in that row's MIDDLE.
  ///
  /// 🚨★★★TWO ANSWERS, NOT ONE. The middle band is the ON-ROW drop; the
  /// quarters at each end belong to the boundary, so a caret stays reachable
  /// everywhere without aiming. But a caret at a boundary still needs to know
  /// WHICH SIDE the pointer sits on — 유저 2026-08-29 (F-31②): 「어태치 경계
  /// 에 커서 가면 가로선 생기는 거, 그걸 커서 위치에 따라 영역을 반으로
  /// 나눠서 **어태치 안쪽이면** 어태치 유지한 채로 외곽에 두는 로직,
  /// **바깥쪽이면** 어태치 해제하는 로직」.
  ///
  /// The row the pointer is IN is that answer: standing in the group's last
  /// row means the inside half, standing in the row past it means the
  /// outside half. So [inRow] is reported at every position, and [onRow] is
  /// the narrower claim.
  ({int? onRow, int inRow}) _bandUnderPointer(double travelled) {
    final at = _grabFraction + travelled;
    final row = at.floor();
    final within = at - row;
    return (onRow: within >= 0.3 && within <= 0.7 ? row : null, inRow: row);
  }

  /// Scrolls the rail when the pointer reaches its edge, and folds what it
  /// scrolled back into the travel (user, 2026-08-09: the caret used to
  /// walk off the visible rows and land on a layer nobody could see).
  ///
  /// The content moving under a stationary pointer is the same thing as the
  /// pointer moving over stationary content — so the applied delta has to
  /// join [_travelled], or the caret would freeze the moment the rail began
  /// to scroll under it.
  ///
  /// Per POINTER MOVE, no timer: the ruler drag's edge pan is built the same
  /// way, and one convention beats two. Holding still at the edge therefore
  /// holds still; it is the reaching that scrolls.
  ///
  /// The apply tail is the shared [edgeAutoPanApply] (D42) — the rows
  /// stack ACROSS the timeline's axis, so the scrollable this drag pans is
  /// the perpendicular one.
  double _autoPanEdge(Offset globalPosition) => edgeAutoPanApply(
    context: context,
    globalPosition: globalPosition,
    axis: widget.axis == Axis.horizontal ? Axis.vertical : Axis.horizontal,
  );

  void _update(DragUpdateDetails details) {
    // H1: the press was a control's. Nothing began, so nothing moves —
    // and in particular the auto-pan below must not run, or dragging a
    // slider near the rail's edge would scroll the rail under it.
    if (_onControl) {
      return;
    }
    final delta = details.delta;
    _travelled += widget.axis == Axis.horizontal ? delta.dy : delta.dx;
    _travelled += _autoPanEdge(details.globalPosition);
    if (widget.rowExtent <= 0) {
      return;
    }
    // ④ (user, 2026-08-12): 「드롭은 커서 위치에 정확히 맞는다 — 아래 A / 위
    // B에서 B를 잡고 살짝 내리면 A 아래에 강조선이 떠서는 안 된다. 커서가 A
    // 아래에 가야 A 아래로 간다」.
    //
    // The caret is the gap the POINTER is nearest, not a count of travel.
    // Travel alone cannot answer it: half a row of travel used to commit a
    // step, so nudging a row down claimed the gap under its neighbour while
    // the pointer was still inside its own row.
    //
    // `at` is the pointer in ROWS from the dragged row's top edge, so the
    // gap it is nearest is simply its round. A row owns TWO of those gaps —
    // 0 above it and 1 below it — and neither is a move, which is the
    // asymmetry [slotForSteps] documents; it is absorbed here instead of
    // being carried in the caller's arithmetic.
    final travelled = _travelled / widget.rowExtent;
    // ⑨: a SELECT counts whole rows the pointer has entered — its span ends
    // ON a row, where a move's caret ends BETWEEN two. Same travel, two
    // readings, which is why this is not the caret's `steps`.
    if (_selecting) {
      widget.onSelectCrossed?.call((_grabFraction + travelled).floor());
      return;
    }
    final nearestGap = (_grabFraction + travelled).round();
    final steps = nearestGap > 1
        ? nearestGap - 1
        : (nearestGap < 0 ? nearestGap : 0);
    final band = _bandUnderPointer(travelled);
    widget.onCrossed(steps, band.onRow, band.inRow);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<LayerRowDragState?>(
      valueListenable: widget.hooks.drag,
      builder: (context, drag, child) {
        // A caret belongs on rows of the dragged subject's OWN kind: a Blur
        // travelling on layer A raises nothing on layer B's chain, and
        // nothing on the layer stack either.
        final showing =
            drag != null &&
                drag.legal &&
                widget.subject.sharesLaneWith(drag.subject)
            ? drag
            : null;
        // R5 #15: an ON-ROW drop has no caret — the row itself is the
        // landing, so the row lights and the gaps stay quiet.
        final onRow =
            showing != null &&
            showing.onRowTarget != null &&
            widget.subject == LayerRowSubject(showing.onRowTarget!);
        final caretShowing = showing != null && showing.onRowTarget == null;
        final leading = caretShowing && showing.caretSlot == widget.slotBefore;
        final trailing =
            caretShowing &&
            widget.isLastRow &&
            showing.caretSlot == widget.slotBefore + 1;
        final lifted = drag?.subject == widget.subject || _lifting;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The lifted row fades: the caret says where it is going, and
            // the row saying "not here any more" is the other half.
            Opacity(opacity: lifted ? 0.45 : 1, child: child),
            if (onRow) _swallowHighlight(colorScheme, showing.joinLabel),
            if (leading)
              _caret(colorScheme, atStart: true, label: showing.joinLabel),
            if (trailing)
              _caret(colorScheme, atStart: false, label: showing.joinLabel),
          ],
        );
      },
      child: _gestures(child: widget.child),
    );
  }

  Widget _gestures({required Widget child}) {
    return RawGestureDetector(
      // Translucent: the row's own taps (select the layer, the eye, the
      // sliders) keep firing — only the pan recognizer joins the arena.
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        EagerPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<EagerPanGestureRecognizer>(
              () => EagerPanGestureRecognizer(debugOwner: this),
              (recognizer) {
                // The rail SCROLLS along the same axis this drag runs, so
                // the device policy is what separates them: pen and mouse
                // move rows, a finger scrolls (UI-R22 #6).
                recognizer.supportedDevices = AppInput.timelineEditPanDevices;
                // PEN-11: RawGestureDetector does not inject these.
                recognizer.gestureSettings = MediaQuery.maybeGestureSettingsOf(
                  context,
                );
                recognizer.dragStartBehavior = DragStartBehavior.down;
                recognizer.onStart = (details) => _begin(
                  details.localPosition,
                  globalPosition: details.globalPosition,
                );
                recognizer.onUpdate = _update;
                // ⑨: a SELECT drag ends its own way. Falling through to the
                // move's end would run the DROP COMMIT for a gesture that
                // never proposed a drop.
                recognizer.onEnd = (_) => _end();
                recognizer.onCancel = () => _end(cancelled: true);
              },
            ),
      },
      child: child,
    );
  }

  /// The row that would SWALLOW the drop: an outline around the whole row
  /// rather than a line beside it (R5 #15).
  ///
  /// A caret answers "between which two", and this drop's answer is "inside
  /// this one" — so the shape has to change with the meaning, or a release
  /// over a folder would look exactly like a release under it. The label
  /// rides along for the same reason it rides the caret: what the drop does
  /// beyond moving has to be readable BEFORE the release.
  Widget _swallowHighlight(ColorScheme colorScheme, String? label) {
    return Positioned.fill(
      key: ValueKey<String>(
        'timeline-row-swallow-'
        '${switch (widget.subject) {
          LayerRowSubject(:final layerId) => layerId.value,
          EffectRowSubject(:final effectId) => effectId.value,
          TrackRowSubject(:final trackId) => trackId.value,
          // B4-3: a select-only lane never raises either of these — the
          // key exists so the switch stays exhaustive, not because a
          // caret or a swallow can be drawn for one.
          LaneRowSubject(:final layerId, :final laneId) =>
            '${layerId.value}:$laneId',
          // A file is never a row's subject — here for the same reason.
          MediaPlacementSubject() => 'placement',
        }}',
      ),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.16),
            border: Border.all(
              color: colorScheme.primary,
              width: layerRowCaretThickness,
            ),
          ),
          child: label == null
              ? null
              : Align(
                  alignment: widget.axis == Axis.horizontal
                      ? Alignment.centerRight
                      : Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: colorScheme.primary,
                        shape: AppShapes.control(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.1,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _caret(
    ColorScheme colorScheme, {
    required bool atStart,
    String? label,
  }) {
    final horizontal = widget.axis == Axis.horizontal;
    final bar = Container(
      width: horizontal ? double.infinity : layerRowCaretThickness,
      height: horizontal ? layerRowCaretThickness : double.infinity,
      color: colorScheme.primary,
    );
    final content = label == null
        ? bar
        : Stack(
            clipBehavior: Clip.none,
            alignment: horizontal ? Alignment.centerLeft : Alignment.topCenter,
            children: [
              bar,
              // The drop does something structural, so it says so BEFORE
              // the release.
              //
              // 🚨F-31① (유저 2026-08-28): 「가로선이 이상한 위치에 있다는
              // 거야 … 레이어영역의 중앙 위쪽? 에 그려져서 레이어랑 겹쳐」.
              //
              // It has to be POSITIONED, and that is the whole fix: a Stack
              // takes its size from its non-positioned children, so a badge
              // laid out beside the bar made the Stack badge-tall and the
              // 2px bar — aligned to the CENTRE of it — dropped half a
              // badge into the row it was supposed to sit on top of. The
              // line moved only when the drop had something to announce,
              // which is exactly the attach drags the report came from.
              //
              // With one axis pinned and the other left null, the stack's
              // own alignment still places the badge (centred across the
              // bar), it hangs off the line under `Clip.none`, and it can
              // no longer vote on where the line is.
              Positioned(
                left: horizontal ? 6 : null,
                top: horizontal ? null : 6,
                child: DecoratedBox(
                  // The app's own corner, not a circular one: a badge is a
                  // small control, and `app_shapes_coverage_test` is what
                  // keeps that from being decided per widget.
                  decoration: ShapeDecoration(
                    color: colorScheme.primary,
                    shape: AppShapes.control(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.1,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
    return Positioned(
      key: ValueKey<String>(
        'timeline-row-caret-${atStart ? 'before' : 'after'}-'
        '${switch (widget.subject) {
          LayerRowSubject(:final layerId) => layerId.value,
          EffectRowSubject(:final effectId) => effectId.value,
          TrackRowSubject(:final trackId) => trackId.value,
          // B4-3: a select-only lane never raises either of these — the
          // key exists so the switch stays exhaustive, not because a
          // caret or a swallow can be drawn for one.
          LaneRowSubject(:final layerId, :final laneId) =>
            '${layerId.value}:$laneId',
          // A file is never a row's subject — here for the same reason.
          MediaPlacementSubject() => 'placement',
        }}',
      ),
      left: horizontal ? 0 : (atStart ? -layerRowCaretThickness / 2 : null),
      right: horizontal ? 0 : (atStart ? null : -layerRowCaretThickness / 2),
      top: horizontal ? (atStart ? -layerRowCaretThickness / 2 : null) : 0,
      bottom: horizontal ? (atStart ? null : -layerRowCaretThickness / 2) : 0,
      child: content,
    );
  }
}

/// 🚨★★★재배치 불가 행의 답 — **두 레일이 같은 코드를 부른다.**
///
/// 유저 A5-4: 「카메라·트랜지션 = **드래그 불가**」. 유저 F-16: 「그런데
/// **카메라나 트랜지션레이어에서 선택범위 시작하려하면 작동안함** … 막으라고
/// 한 것은 **드래그 이동뿐**」.
///
/// ⛔두 레일이 각자 `if (!kind.reordersInCut) return child;` 를
/// 적고 있었고, 그 한 줄이 **이동 불가로 선택 불가까지** 답했다. x시트는
/// 가로 레일의 그 모양을 **베껴서** 같은 버그를 갖고 있었다 — 사본이라
/// 한쪽만 고치면 갈라진다.
///
/// 반환값 셋의 뜻:
/// • `null` — 이 행은 **움직일 수 있다**. 호출자가 평소의 이동 타깃을 만든다
/// • `child` — 선택 훅이 없는 표면이라 붙일 것이 없다
/// • 그 외 — **선택 전용** 타깃
Widget? unmovableRowSelectTarget({
  required LayerKind kind,
  required LayerId layerId,
  required double rowExtent,
  required Axis axis,
  required TimelineRowDragHooks? hooks,
  required void Function(int rowDelta) onSelectCrossed,
  required Widget child,
}) {
  if (kind.reordersInCut) {
    return null;
  }
  if (hooks == null || hooks.onSelectBegin == null) {
    return child;
  }
  return LayerRowDragTarget.selectOnly(
    subject: LayerRowSubject(layerId),
    rowExtent: rowExtent,
    axis: axis,
    hooks: hooks,
    onSelectCrossed: onSelectCrossed,
    child: child,
  );
}

/// A layer row's drag wrapper: the movable row's [LayerRowDragTarget], the
/// unmovable row's select-only target ([unmovableRowSelectTarget]), or the
/// target with no hooks when the host wired none: it renders the bare child
/// itself, and the rows stay countable by it (the rail always kept it).
///
/// 🚨ONE function for the rail and the sheet. The sheet used to copy the
/// rail's shape and drift behind it — A5-4 / F-16 (「카메라·트랜지션 =
/// 드래그 불가, 그런데 선택은 된다」) and F-31 (the caret counts the rows
/// the grid DREW, never `widget.layers`) were each fixed on the rail first
/// and found missing on the sheet later. The audit's clone scan
/// (2026-09-03) found the pair; this is the one that stays.
///
/// [dragRows] is a getter: the caret reads the rows drawn at build time,
/// the selection closures the rows drawn at EVENT time.
///
/// 🚨B4-3 (유저, 몇 번째인지 세지 않겠다고 했다) — **EVERY ROW JOINS A
/// SELECTION.**
///
/// > 「행의 **다른 fx끼리 넘어서 선택범위가 불가능.** 그 너머의 다른 행
/// > 선택해야 그때서야 가능. **이런 다른규칙 삭제좀하자고.**」
///
/// ⛔The span resolver never had a rule about lanes — it is a plain slice
/// of the drawn row list. What was missing is WIRING: a lane row that is
/// not an fx chain header got no drag target at all, and the one that IS
/// a header was given `onCrossed` and never `onSelectCrossed`, which is
/// the only thing that grows a selection during a drag. So a span
/// anchored on a lane simply never updated, and a span anchored anywhere
/// else could not stop on one.
///
/// ★A lane row cannot be RE-ORDERED unless it heads a chain, but every
/// row can be SELECTED. Those are two questions, and only the first one
/// ever needed an answer here — which is why a LANE row goes down its own
/// branch below rather than being refused a wrapper.
///
/// The sheet lists the stack RAW where the rail reverses it, and the
/// chain the other way round from the rail — neither is stated here.
/// Both are inferred by the policy from the lists themselves.
Widget layerRowDragWrapper({
  required TimelineDisplayRow row,
  required List<TimelineDisplayRow> Function() dragRows,
  required double rowExtent,
  required Axis axis,
  required TimelineRowDragHooks? hooks,
  required void Function(List<TimelineDisplayRow> rows, int rowDelta)?
  onRowSelectionSpan,
  HeldRowPin? pin,
  required Widget child,
}) {
  // The held row is PINNED in the row window while its grip is taken (the
  // window would otherwise unmount it mid-drag). Derived ONCE from the
  // row's address, whichever branch below takes the grip.
  final address = row.address;
  final onGripTaken = pin == null ? null : () => pin.take(address);
  final onGripReleased = pin == null ? null : () => pin.release(address);
  final lane = row.lane;
  if (lane != null) {
    return hooks == null
        ? child
        : _laneRowDragTarget(
            (row: row, lane: lane),
            hooks,
            (
              axis: axis,
              rowExtent: rowExtent,
              dragRows: dragRows,
              onRowSelectionSpan: onRowSelectionSpan,
              onGripTaken: onGripTaken,
              onGripReleased: onGripReleased,
            ),
            child: child,
          );
  }
  final unmovable = unmovableRowSelectTarget(
    kind: row.layer.kind,
    layerId: row.layer.id,
    rowExtent: rowExtent,
    axis: axis,
    hooks: hooks,
    onSelectCrossed: (rowDelta) => onRowSelectionSpan?.call(dragRows(), rowDelta),
    child: child,
  );
  if (unmovable != null) {
    return unmovable;
  }
  final caret = LayerRowCaret.of(dragRows(), row.layer.id);
  if (caret == null) {
    return child;
  }
  return LayerRowDragTarget(
    subject: LayerRowSubject(row.layer.id),
    slotBefore: caret.slot,
    rowExtent: rowExtent,
    axis: axis,
    hooks: hooks,
    onGripTaken: onGripTaken,
    onGripReleased: onGripReleased,
    isLastRow: caret.isLastRow,
    onCrossed: hooks == null
        ? (_, _, _) {}
        : (steps, onRow, inRow) {
      final slot = caret.slotFor(steps);
      final target = caret.onRowLayer(onRow);
      if (target != null) {
        hooks.onRowTarget(caret.layers, slot, target.id);
        return;
      }
      hooks.onUpdate(
        caret.layers,
        slot,
        pointerInRow: caret.onRowLayer(inRow)?.id,
      );
    },
    onSelectCrossed: hooks?.onSelectBegin == null
        ? null
        : (rowDelta) => onRowSelectionSpan?.call(dragRows(), rowDelta),
    child: child,
  );
}

/// A lane row that can join a SELECTION but cannot be RE-ORDERED.
///
/// 🚨B4-3 (유저): 「행의 **다른 fx끼리 넘어서 선택범위가 불가능.** 그 너머의
/// 다른 행 선택해야 그때서야 가능. **이런 다른규칙 삭제좀하자고.**」
///
/// ⛔TWO QUESTIONS, ONE ANSWER EACH. A lane row cannot be re-ordered unless
/// it heads an fx chain, but EVERY row can be selected — and the drag
/// target that says the first must still answer the second, or a span
/// anchored on a lane never updates and a span anchored elsewhere cannot
/// stop on one. [LayerRowDragTarget.onCrossed] is deliberately empty here:
/// this target exists for the select half alone.
///
/// ⚠️Both grids build it — the horizontal rail and the vertical sheet — so
/// the axis and the row extent are the caller's; everything else is the
/// law. Written per grid, one of them had `onCrossed` and no
/// `onSelectCrossed`, which is exactly the bug B4-3 named.
Widget _laneSelectOnlyDragTarget(
  ({TimelineDisplayRow row, String laneId}) lane,
  TimelineRowDragHooks hooks,
  ({Axis axis, double rowExtent, void Function(int rowDelta)? onSelectCrossed})
  wiring, {
  required Widget child,
}) {
  final onSelectCrossed = wiring.onSelectCrossed;
  if (hooks.onSelectBegin == null || onSelectCrossed == null) {
    return child;
  }
  return LayerRowDragTarget(
    subject: LaneRowSubject(lane.row.layer.id, lane.laneId),
    slotBefore: lane.row.layerIndex,
    rowExtent: wiring.rowExtent,
    axis: wiring.axis,
    hooks: hooks,
    isLastRow: false,
    onCrossed: (_, _, _) {},
    onSelectCrossed: onSelectCrossed,
    child: child,
  );
}

/// A LANE row's drag wrapper: the fx chain header's re-order target, or —
/// for every other lane row, and for a header the chain cannot place — the
/// select-only target above.
///
/// 🚨ONE function for the rail and the sheet, like the two targets above it
/// (the audit's clone scan, round 8, the grids' second-largest pair). Each
/// grid had spelled the whole thing: the same four gates (a group header,
/// an effect lane id, no parameter id, a slot that is still in the chain),
/// the same subject, the same `effectChainAfterCrossing` tail — and each
/// had to remember the select-only fallback afterwards. Both answers live
/// here now, so a caller cannot take one and forget the other.
///
/// ⛔The Transform group header is never a chain member: it is where the
/// chain ends. That is [parseEffectLaneId] answering null, not a rule of
/// this function's own — so it falls to select-only like any parameter
/// lane.
///
/// ★A lane row cannot be RE-ORDERED unless it heads a chain, but every row
/// can be SELECTED. Those are two questions, and only the first one ever
/// needed an answer here (B4-3).
///
/// R5 #15: an fx chain has no "inside a row" to drop into — an effect
/// holds nothing — so the on-row band is ignored and the caret stays the
/// only answer.
Widget _laneRowDragTarget(
  ({TimelineDisplayRow row, PropertyLaneRow lane}) subject,
  TimelineRowDragHooks hooks,
  ({
    Axis axis,
    double rowExtent,
    List<TimelineDisplayRow> Function() dragRows,
    void Function(List<TimelineDisplayRow> rows, int rowDelta)?
    onRowSelectionSpan,
    // The A5 grip: the rail PINS the held row in its window (the window
    // would otherwise unmount it mid-drag) and the sheet has nothing to
    // pin, so this is the caller's answer and not a rule of this function.
    VoidCallback? onGripTaken,
    VoidCallback? onGripReleased,
  })
  wiring, {
  required Widget child,
}) {
  final row = subject.row;
  final span = wiring.onRowSelectionSpan;
  // ONE derivation of the select half for both branches below.
  final onSelectCrossed = span == null
      ? null
      : (int rowDelta) => span(wiring.dragRows(), rowDelta);
  Widget selectOnly() => _laneSelectOnlyDragTarget(
    (row: row, laneId: subject.lane.laneId),
    hooks,
    (
      axis: wiring.axis,
      rowExtent: wiring.rowExtent,
      onSelectCrossed: onSelectCrossed,
    ),
    child: child,
  );

  final parsed = parseEffectLaneId(subject.lane.laneId);
  if (!subject.lane.isGroupHeader ||
      parsed == null ||
      parsed.parameterId != null) {
    return selectOnly();
  }
  final headers = effectHeaderRowsOf(wiring.dragRows(), row.layer.id);
  final slot = headers.indexWhere(
    (header) => header.effectId == parsed.effectId,
  );
  if (slot < 0) {
    return selectOnly();
  }
  return LayerRowDragTarget(
    subject: EffectRowSubject(row.layer.id, parsed.effectId),
    slotBefore: slot,
    rowExtent: wiring.rowExtent,
    axis: wiring.axis,
    hooks: hooks,
    onGripTaken: wiring.onGripTaken,
    onGripReleased: wiring.onGripReleased,
    isLastRow: slot == headers.length - 1,
    // An fx chain has no "inside a row" to drop into — an effect holds
    // nothing — so the on-row band is ignored here and the caret stays
    // the only answer (R5 #15).
    onCrossed: (steps, _, _) {
      final landed = effectChainAfterCrossing(headers, slot, steps);
      hooks.onEffectUpdate(row.layer.id, landed.effectIds, landed.slot);
    },
    // B4-3: the SELECT half, the same one every layer row already had.
    onSelectCrossed: hooks.onSelectBegin == null ? null : onSelectCrossed,
    child: child,
  );
}
