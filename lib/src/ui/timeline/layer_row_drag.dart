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

import '../../models/layer.dart';
import '../../models/layer_effect.dart' show EffectId;
import '../../models/layer_id.dart';
import '../../models/track_id.dart';
import '../input/app_input_settings.dart' show AppInput;
import '../input/eager_pan_gesture_recognizer.dart';
import '../theme/app_theme.dart' show AppShapes;
import 'timeline_edge_auto_pan.dart' show edgeAutoPanDelta;

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

  @override
  bool sharesLaneWith(LayerRowDragSubject other) => other is LayerRowSubject;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayerRowSubject && other.layerId == layerId;

  @override
  int get hashCode => Object.hash(LayerRowSubject, layerId);
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
  });

  final ValueListenable<LayerRowDragState?> drag;

  final void Function(LayerRowDragSubject subject) onBegin;

  /// The caret moved to a slot of the LAYER row list. [displayLayers] is
  /// the list the SURFACE renders, so the session can map the slot onto the
  /// model without guessing which way this rail runs.
  final void Function(List<Layer> displayLayers, int slot) onUpdate;

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
  });

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
  final void Function(int crossedRows, int? onRow) onCrossed;

  /// ⑨: the SELECT drag's travel, in whole rows from the pressed row.
  ///
  /// Beside [onCrossed] rather than inside the hooks for the same reason
  /// that one is: the host closes over the row list it drew, so this widget
  /// never has to know which way its rail runs.
  final void Function(int rowDelta)? onSelectCrossed;

  /// Whether this is the last row of the rail — only it can show the
  /// trailing caret, or two adjacent rows would both draw the same gap.
  final bool isLastRow;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hooks = this.hooks;
    if (hooks == null) {
      return child;
    }
    return _LayerRowDragBody(
      subject: subject,
      slotBefore: slotBefore,
      rowExtent: rowExtent,
      axis: axis,
      hooks: hooks,
      onCrossed: onCrossed,
      onSelectCrossed: onSelectCrossed,
      isLastRow: isLastRow,
      grabOffsetWithinRun: grabOffsetWithinRun,
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
    required this.isLastRow,
    this.onSelectCrossed,
    required this.child,
  });

  final LayerRowDragSubject subject;
  final int slotBefore;
  final double rowExtent;
  final double grabOffsetWithinRun;
  final Axis axis;
  final TimelineRowDragHooks hooks;
  final void Function(int crossedRows, int? onRow) onCrossed;
  final void Function(int rowDelta)? onSelectCrossed;
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

  void _begin(Offset localPosition) {
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
    // ⑨: which of the two drags this is, decided ONCE at the press and not
    // re-asked — the same reason the cells decide it at the press too
    // (their range gesture's `isInSelection`). A drag that changed its mind halfway
    // would be a row moving because the selection happened to grow under it.
    final inSelection = widget.hooks.isInRowSelection?.call(widget.subject);
    _selecting = inSelection == false;
    if (_selecting) {
      widget.hooks.onSelectBegin?.call(widget.subject);
      return;
    }
    widget.hooks.onBegin(widget.subject);
    widget.onCrossed(0, null);
  }

  /// ⑨: true while this drag is growing the row SELECTION rather than
  /// moving rows.
  bool _selecting = false;

  /// The release, whichever drag this was. Cancel takes the same path: a
  /// select has nothing to roll back (the span it drew IS the result), and
  /// the move's own cancel is the hooks'.
  void _end({bool cancelled = false}) {
    if (_selecting) {
      _selecting = false;
      widget.hooks.onSelectEnd?.call();
      return;
    }
    if (cancelled) {
      widget.hooks.onCancel();
      return;
    }
    widget.hooks.onEnd();
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
  int? _rowUnderPointer(double travelled) {
    final at = _grabFraction + travelled;
    final row = at.floor();
    final within = at - row;
    // The middle band is the ON-ROW one; the quarters at each end belong to
    // the boundaries, so a caret stays reachable everywhere without aiming.
    return within >= 0.3 && within <= 0.7 ? row : null;
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
  double _autoPanEdge(Offset globalPosition) {
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject();
    if (scrollable == null || viewport is! RenderBox || !viewport.hasSize) {
      return 0;
    }
    final local = viewport.globalToLocal(globalPosition);
    final horizontal = widget.axis == Axis.horizontal;
    final delta = edgeAutoPanDelta(
      horizontal ? local.dy : local.dx,
      horizontal ? viewport.size.height : viewport.size.width,
    );
    if (delta == 0) {
      return 0;
    }
    final position = scrollable.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final applied = target - position.pixels;
    if (applied == 0) {
      return 0;
    }
    position.jumpTo(target);
    return applied;
  }

  void _update(DragUpdateDetails details) {
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
    widget.onCrossed(steps, _rowUnderPointer(travelled));
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
        final leading =
            caretShowing && showing.caretSlot == widget.slotBefore;
        final trailing =
            caretShowing &&
            widget.isLastRow &&
            showing.caretSlot == widget.slotBefore + 1;
        final lifted = drag?.subject == widget.subject;
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
                recognizer.onStart = (details) =>
                    _begin(details.localPosition);
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
              Padding(
                padding: const EdgeInsets.only(left: 6),
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
