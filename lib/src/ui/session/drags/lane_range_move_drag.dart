import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../models/key_range_shift.dart'
    show FrameStretch, frameStretched;
import '../../../models/layer_effect.dart';
import '../../../models/timeline_frame_range.dart';
import '../../timeline/property_lane_model.dart'
    show LaneKeyLandings, LaneKeyValues;
import '../../timeline/timeline_drag_preview.dart';
import '../lane_edit_subject.dart';
import '../lane_homes.dart';

/// What [subject]'s row is with [values] written into its keys — null
/// where none changes ([LaneVerbs.laneValuesWritten]).
typedef LaneValuesWrite =
    LaneEdit? Function(LaneEditSubject subject, LaneKeyValues values);

/// THE lane keys' move: [row]'s keys [span] holds on [laneIds], each moved
/// to the frame [to] gives it on its lane, home by home — ONE rigid group,
/// so a home whose landing is blocked blocks the move, and a home with no
/// key moving rides along. Null when blocked; empty where nothing moves.
///
/// 🚨H20: a drag on the lanes and a band's move carrying its swept lanes
/// both move keys by this ([LaneRangeMoveDrag], `FrameRangeMoveDrag`).
LaneEdit? laneSpanKeysMovedOn(
  LaneEditSubject row, {
  required List<String> laneIds,
  required TimelineLaneSelection span,
  required int Function(String laneId, int frame) to,
}) {
  var blocked = false;
  T? moved<T>(LaneHome<T> home) {
    if (!home.keyedOnWhere(
      (laneId, frame) => span.contains(frame) && to(laneId, frame) != frame,
    )) {
      return null;
    }
    final next = home.moved(span, to);
    blocked = blocked || next == null;
    return next;
  }

  final edit = rowLaneHomesEdited(row, rowLaneHomes(row, laneIds), moved);
  return blocked ? null : edit;
}

/// The lane-key range MOVE drag (UI-R23 #3 part 2).
///
/// Every spanned lane's ranged keys shift together by the same delta — one
/// rigid group, all-or-nothing across lanes (R26 #3) — and a blocked
/// landing HOLDS the last valid preview rather than snapping back (UI-R23
/// #10).
///
/// 🚨F-374: the group is every home the span holds lanes of
/// ([RowLaneHomes]) — the row's own transform, its reference fx, its effect
/// chain, its name tag — landed as ONE step, and a home whose landing is
/// blocked blocks the move. ↩️It moved ONE family, chosen by asking whether
/// an effect lane was in the span and then a name tag's, so the rest of a
/// span the rail drew across families stayed where it was. It had kept that
/// three-branch shape when it was moved off the session (2026-09-02): a
/// design change during a move was what that brief forbade.
///
/// And a header graph's key carries the keys' VALUES with it (I-3 ②,
/// AE's graph editor): written as the value editor writes each — the row
/// [LaneValuesWrite] hands back — and then shifted, in the one step. A
/// graph's box STRETCHES them (I-3 ⑥, AE's transform box): each key moved
/// as far as its frame stretched ([FrameStretch]) — the same one group, the
/// same block discipline, a shift being a stretch of none.
///
/// ⛔It does NOT sign `EditorDragSession`.
class LaneRangeMoveDrag {
  LaneRangeMoveDrag._({
    required LaneEditSubject subject,
    required TimelineLaneSelection selectionBefore,
    required List<String> laneIds,
    required LaneValuesWrite write,
    required ValueNotifier<TimelineDragPreview?> preview,
    required ValueNotifier<TimelineLaneSelection?> selection,
  }) : _subject = subject,
       _selectionBefore = selectionBefore,
       _laneIds = laneIds,
       _write = write,
       _preview = preview,
       _selection = selection;

  static const String _why = 'Move lane keys';

  final LaneEditSubject _subject;

  /// The span as it stood when the grip closed — what a cancel, and a
  /// step back to zero delta, restore the outline to.
  final TimelineLaneSelection _selectionBefore;

  /// The span's lanes, as the homes of the row's keys name them — what
  /// [_shiftedBy] finds the homes of on the row it shifts.
  final List<String> _laneIds;

  /// The keys' values written into a row ([LaneValuesWrite]).
  final LaneValuesWrite _write;

  final ValueNotifier<TimelineDragPreview?> _preview;
  final ValueNotifier<TimelineLaneSelection?> _selection;

  /// The last valid shift — what the release lands.
  LaneEdit? _shifted;

  /// Null when the selection covers no keys on ANY spanned lane — nothing
  /// to move, so no drag.
  static LaneRangeMoveDrag? begin({
    required TimelineLaneSelection selection,
    required LaneEditSubject subject,
    required List<String> Function(
      List<String> spanLaneIds, {
      List<LayerEffect> effects,
    })
    laneVerbTargets,
    required ValueNotifier<TimelineDragPreview?> preview,
    required ValueNotifier<TimelineLaneSelection?> selectionChannel,
    required LaneValuesWrite write,
  }) {
    final laneIds = laneVerbTargets(
      selection.spanLaneIds,
      effects: subject.effects,
    );
    if (!rowLaneHomesKeyedWhere(
      rowLaneHomes(subject, laneIds),
      selection.contains,
    )) {
      return null;
    }
    return LaneRangeMoveDrag._(
      subject: subject,
      selectionBefore: selection,
      laneIds: laneIds,
      write: write,
      preview: preview,
      selection: selectionChannel,
    );
  }

  /// Moves every spanned lane's ranged keys [frameDelta] frames on — after
  /// [stretch], where a graph's box stretches them (I-3 ⑥), and each where
  /// its [landings] say, where one corner of the box goes alone
  /// (graph-box-handles-more ⓐ) — their [values] written first, where a
  /// graph's key or box carries them, and previews the result. A blocked
  /// landing returns having changed nothing, which is what makes the last
  /// valid preview and outline hold.
  void update({
    required int frameDelta,
    FrameStretch? stretch,
    LaneKeyValues? values,
    LaneKeyLandings? landings,
  }) {
    int to(String laneId, int frame) =>
        landings?[laneId]?[frame] ??
        (stretch == null ? frame : frameStretched(stretch, frame)) +
            frameDelta;
    final written = values == null ? null : _write(_subject, values);
    final moved = laneSpanKeysMovedOn(
      written == null ? _subject : _subject.after(written),
      laneIds: _laneIds,
      span: _selectionBefore,
      to: to,
    );
    if (moved == null) {
      // Blocked landing: the last valid preview and outline HOLD.
      return;
    }
    final edit = written == null ? moved : written.then(moved);
    if (edit.isEmpty) {
      _shifted = null;
      _preview.value = null;
      _selection.value = _selectionBefore;
      return;
    }
    final shown = _subject.preview(edit);
    if (shown == null) {
      // A landing its home will not take — a camera key put out of its
      // cut: the last valid preview and outline HOLD.
      return;
    }
    _shifted = edit;
    _preview.value = shown;
    _rideSelection((frame) => to(_selectionBefore.laneId, frame), landings);
  }

  /// The step's selection ride: the outline follows the span's ends where
  /// [to] takes them — turned about, where a stretch turns them — and holds
  /// every key [landings] put down; never below 0.
  ///
  /// ⚖️Mine (graph-box-handles-more ⓐ): a corner gone alone moves the keys
  /// by as much as each stood near it, so no one frame's move is the
  /// span's — the outline keeps its ends and widens to the keys landed
  /// past them.
  void _rideSelection(
    int Function(int frame) to,
    LaneKeyLandings? landings,
  ) {
    final ends = [
      to(_selectionBefore.startIndex),
      to(_selectionBefore.endIndexExclusive - 1),
      for (final frames in landings?.values ?? const <Map<int, int>>[])
        ...frames.values,
    ];
    final newStart = ends.reduce(math.min);
    if (newStart < 0) {
      return;
    }
    _selection.value = TimelineLaneSelection(
      layerId: _selectionBefore.layerId,
      laneId: _selectionBefore.laneId,
      startIndex: newStart,
      endIndexExclusive: ends.reduce(math.max) + 1,
      laneIds: _selectionBefore.laneIds,
    );
  }

  /// Lands the move as ONE undo step; the selection stays on the landed
  /// span. A drag that never produced a valid shift puts the outline back
  /// where it started and writes nothing.
  void commit() {
    final shifted = _shifted;
    final landed = _selection.value;
    _shifted = null;
    _preview.value = null;
    if (shifted == null) {
      _selection.value = _selectionBefore;
      return;
    }
    _subject.commit(shifted, _why);
    _selection.value = landed;
  }

  /// Drops the preview and puts the outline back; history is untouched.
  void cancel() {
    _shifted = null;
    _preview.value = null;
    _selection.value = _selectionBefore;
  }
}
