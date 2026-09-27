import 'package:flutter/foundation.dart' show ValueNotifier;
import 'drags/lane_range_move_drag.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../timeline/timeline_drag_preview.dart' show TimelineDragPreview;
import 'session_roles.dart';
import 'lane_verbs.dart';

/// The LANE RANGE MOVE DRAG — sliding a selected range of a transform,
/// effect or camera lane along the frames — as its own object: the drag
/// in flight and the steps of it.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: three fields of its own and
/// fourteen session members touched. It names the roles it needs in
/// its constructor.
///
/// ↩️F-195 (2026-09-27): WHAT a selection edits — its subject, the preview
/// forms, and the camera track this object used to park for the lane
/// provider — is [LaneVerbs.laneEditSubjectOf] now, the one answer every
/// lane edit takes. The camera's in-flight track rides the preview channel
/// itself ([LaneEditPreview.camera]), so nothing is parked here any more.
class LaneRangeMoveDragVerbs {
  LaneRangeMoveDragVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ValueNotifier<TimelineDragPreview?> dragPreview,
    required LaneVerbs laneVerbs,
  }) : _project = project,
       _selection = selection,
       _dragPreview = dragPreview,
       _laneVerbs = laneVerbs;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ValueNotifier<TimelineDragPreview?> _dragPreview;
  final LaneVerbs _laneVerbs;

  /// The lane range move in flight, or null (UI-R23 #3 part 2). ⛔The only
  /// thing this class keeps about one: the drag-start snapshot and the last
  /// valid shifted payload live on the object and die with the gesture.
  LaneRangeMoveDrag? _laneMoveDrag;

  /// Starts moving the current lane selection; false when there is none or
  /// it covers no keys on ANY spanned lane (nothing to move).
  bool beginLaneRangeMoveDrag() {
    final selection = _selection.laneRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final layer = _laneVerbs.laneVerbLayerFor(selection.layerId);
    // An attach row's keys are its base's; a camera row's live on the open
    // cut, and with no cut open there is nothing for them to live on.
    if (layer == null ||
        isAttachedLayer(layer) ||
        (layer.kind == LayerKind.camera && _project.activeCutOrNull == null)) {
      return false;
    }
    // ⚠️Assigned only on SUCCESS: a refused begin must not touch a drag
    // already in flight.
    final drag = LaneRangeMoveDrag.begin(
      selection: selection,
      subject: _laneVerbs.laneEditSubjectOf(layer),
      laneVerbTargets: _laneVerbs.laneVerbTargets,
      preview: _dragPreview,
      selectionChannel: _selection.laneRangeSelection,
    );
    if (drag == null) {
      return false;
    }
    _laneMoveDrag = drag;
    return true;
  }

  /// A lane-move drag step: shifts EVERY spanned lane's ranged keys by
  /// [frameDelta] (R26 #3 — one rigid group, all-or-nothing across lanes)
  /// and previews via [_dragPreview]. A blocked landing HOLDS the last valid
  /// preview (UI-R23 #10 — no snap-back).
  void updateLaneRangeMoveDrag({required int frameDelta}) =>
      _laneMoveDrag?.update(frameDelta: frameDelta);

  /// Commits the lane move as ONE undo step; the selection stays on the
  /// landed span.
  void endLaneRangeMoveDrag() {
    final drag = _laneMoveDrag;
    _laneMoveDrag = null;
    drag?.commit();
  }

  /// Drops an in-flight lane-move preview, restoring the selection.
  void cancelLaneRangeMoveDrag() {
    final drag = _laneMoveDrag;
    _laneMoveDrag = null;
    drag?.cancel();
  }
}
