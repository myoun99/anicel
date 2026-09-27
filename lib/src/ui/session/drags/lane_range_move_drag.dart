import 'package:flutter/foundation.dart';

import '../../../models/layer_effect.dart';
import '../../../models/se_name_tag.dart';
import '../../../models/timeline_frame_range.dart';
import '../../../models/transform_track.dart';
import '../../timeline/effect_lane_editing.dart'
    show effectLaneKeyFrames, effectsWithLaneSpanKeysShifted;
import '../../timeline/effect_lane_policy.dart' show parseEffectLaneId;
import '../../timeline/se_name_tag_lane_editing.dart'
    show seNameTagTrackWithLaneSpanKeysShifted;
import '../../timeline/se_name_tag_lane_policy.dart'
    show laneIsSeNameTag, seNameTagLaneKeyFrames;
import '../../timeline/timeline_drag_preview.dart';
import '../../timeline/transform_lane_editing.dart'
    show transformLaneKeyFrames, transformTrackWithLaneSpanKeysShifted;
import '../lane_edit_subject.dart';

/// The lane-key range MOVE drag (UI-R23 #3 part 2).
///
/// Every spanned lane's ranged keys shift together by the same delta — one
/// rigid group, all-or-nothing across lanes (R26 #3) — and a blocked
/// landing HOLDS the last valid preview rather than snapping back (UI-R23
/// #10).
///
/// ⛔It does NOT sign `EditorDragSession`, and it keeps the three-branch
/// shape it arrived with. The branching by lane family (effect chain /
/// name tag / transform track) is genuinely three different payloads with
/// three different commit verbs; folding them together is a design change,
/// and the split brief forbids making one during a move.
///
/// ⚠️Exactly one of the three shifted slots is ever set. They clear
/// together, because a stale payload would send the commit down a branch
/// the drag never took.
class LaneRangeMoveDrag {
  LaneRangeMoveDrag._({
    required LaneEditSubject subject,
    required TimelineLaneSelection selectionBefore,
    required List<String> Function(
      List<String> spanLaneIds, {
      List<LayerEffect> effects,
    })
    laneVerbTargets,
    required ValueNotifier<TimelineDragPreview?> preview,
    required ValueNotifier<TimelineLaneSelection?> selection,
  }) : _subject = subject,
       _selectionBefore = selectionBefore,
       _laneVerbTargets = laneVerbTargets,
       _preview = preview,
       _selection = selection;

  static const String _why = 'Move lane keys';

  final LaneEditSubject _subject;

  /// The span as it stood when the grip closed — what a cancel, and a
  /// step back to zero delta, restore the outline to.
  final TimelineLaneSelection _selectionBefore;

  final List<String> Function(
    List<String> spanLaneIds, {
    List<LayerEffect> effects,
  })
  _laneVerbTargets;

  final ValueNotifier<TimelineDragPreview?> _preview;
  final ValueNotifier<TimelineLaneSelection?> _selection;

  TransformTrack? _shifted;
  List<LayerEffect>? _shiftedEffects;
  SeNameTagTrack? _shiftedNameTag;

  /// Null when the selection covers no keys on ANY spanned lane — nothing
  /// to move, so no drag.
  ///
  /// ⚠️The family is decided ONCE here, the same way [update] decides it.
  /// Asking per lane would let this answer "there are keys" about a lane
  /// the step is not going to shift.
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
  }) {
    // R6: an EFFECT lane selection moves the effect chain's keys instead of
    // the transform track's — same rigid all-or-nothing group, same drag.
    final moveTargets = laneVerbTargets(
      selection.spanLaneIds,
      effects: subject.effects,
    );
    final isEffectSelection = moveTargets.any(
      (laneId) => parseEffectLaneId(laneId) != null,
    );
    // C①: the name-tag family is the third mode. Safe as an any() because
    // the span switch keeps a lane selection single-family.
    final isNameTagSelection =
        !isEffectSelection && moveTargets.any(laneIsSeNameTag);
    final nameTagKeys = subject.seNameTag?.track ?? SeNameTagTrack.empty();
    final keyed = moveTargets.any(
      (laneId) => isEffectSelection
          ? effectLaneKeyFrames(subject.effects, laneId).any(selection.contains)
          : isNameTagSelection
          ? seNameTagLaneKeyFrames(nameTagKeys, laneId).any(selection.contains)
          : transformLaneKeyFrames(
              subject.transformTrack,
              laneId,
            ).any(selection.contains),
    );
    if (!keyed) {
      return null;
    }
    return LaneRangeMoveDrag._(
      subject: subject,
      selectionBefore: selection,
      laneVerbTargets: laneVerbTargets,
      preview: preview,
      selection: selectionChannel,
    );
  }

  /// Shifts every spanned lane's ranged keys by [frameDelta] and previews
  /// the result. A blocked landing returns having changed nothing, which is
  /// what makes the last valid preview and outline hold.
  void update({required int frameDelta}) {
    if (frameDelta == 0) {
      _dropInFlight();
      _preview.value = null;
      _selection.value = _selectionBefore;
      return;
    }
    final targets = _laneVerbTargets(
      _selectionBefore.spanLaneIds,
      effects: _subject.effects,
    );
    if (targets.any((laneId) => parseEffectLaneId(laneId) != null)) {
      final shiftedEffects = effectsWithLaneSpanKeysShifted(
        _subject.effects,
        laneIds: targets,
        rangeStartIndex: _selectionBefore.startIndex,
        rangeEndIndexExclusive: _selectionBefore.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (shiftedEffects == null) {
        // Blocked landing: the last valid preview and outline HOLD.
        return;
      }
      _shiftedEffects = shiftedEffects;
      _preview.value = _subject.previewEffects(shiftedEffects);
      _rideSelection(frameDelta);
      return;
    }
    // C①: the name-tag family's branch — same rigid group, same hold.
    if (targets.any(laneIsSeNameTag)) {
      final tag = _subject.seNameTag;
      final previewNameTag = _subject.previewSeNameTag;
      if (tag == null || previewNameTag == null) {
        return;
      }
      final shiftedTag = seNameTagTrackWithLaneSpanKeysShifted(
        tag.track ?? SeNameTagTrack.empty(),
        laneIds: targets,
        rangeStartIndex: _selectionBefore.startIndex,
        rangeEndIndexExclusive: _selectionBefore.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (shiftedTag == null) {
        // Blocked landing: the last valid preview and outline HOLD.
        return;
      }
      _shiftedNameTag = shiftedTag;
      _preview.value = previewNameTag(tag.copyWith(track: shiftedTag));
      _rideSelection(frameDelta);
      return;
    }
    final shifted = transformTrackWithLaneSpanKeysShifted(
      _subject.transformTrack,
      laneIds: targets,
      rangeStartIndex: _selectionBefore.startIndex,
      rangeEndIndexExclusive: _selectionBefore.endIndexExclusive,
      frameDelta: frameDelta,
    );
    if (shifted == null) {
      // Blocked landing: the last valid preview and outline HOLD.
      return;
    }
    _shifted = shifted;
    _preview.value = _subject.previewTransform(shifted);
    _rideSelection(frameDelta);
  }

  /// The step's selection ride, one law for all three branches: the outline
  /// follows the shifted span (never below 0).
  void _rideSelection(int frameDelta) {
    final newStart = _selectionBefore.startIndex + frameDelta;
    if (newStart < 0) {
      return;
    }
    _selection.value = TimelineLaneSelection(
      layerId: _selectionBefore.layerId,
      laneId: _selectionBefore.laneId,
      startIndex: newStart,
      endIndexExclusive: _selectionBefore.endIndexExclusive + frameDelta,
      laneIds: _selectionBefore.laneIds,
    );
  }

  /// Lands the move as ONE undo step; the selection stays on the landed
  /// span. A drag that never produced a valid shift puts the outline back
  /// where it started and writes nothing.
  void commit() {
    final shifted = _shifted;
    final shiftedEffects = _shiftedEffects;
    final shiftedNameTag = _shiftedNameTag;
    final landed = _selection.value;
    _dropInFlight();
    _preview.value = null;

    if (shiftedEffects != null) {
      _subject.commitEffects(shiftedEffects, _why);
      _selection.value = landed;
      return;
    }
    if (shiftedNameTag != null) {
      final tag = _subject.seNameTag ?? const SeNameTag();
      _subject.commitSeNameTag?.call(
        tag.copyWith(track: shiftedNameTag),
        _why,
      );
      _selection.value = landed;
      return;
    }
    if (shifted == null) {
      _selection.value = _selectionBefore;
      return;
    }
    _subject.commitTransform(shifted, _why);
    _selection.value = landed;
  }

  /// Drops the preview and puts the outline back; history is untouched.
  void cancel() {
    _dropInFlight();
    _preview.value = null;
    _selection.value = _selectionBefore;
  }

  void _dropInFlight() {
    _shifted = null;
    _shiftedEffects = null;
    _shiftedNameTag = null;
  }
}
