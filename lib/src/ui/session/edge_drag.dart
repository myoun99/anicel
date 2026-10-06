import 'package:flutter/foundation.dart' show ValueNotifier;
import '../timeline/timeline_drag_preview.dart' show TimelineDragPreview;
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_coverage.dart' show TimelineBlockEdge;
import '../storyboard_layer_policy.dart';
import 'active_cut_controllers.dart';
import 'drags/cut_trim_drag.dart';
import 'drags/edge_drag_roles.dart';
import 'drags/exposure_edge_drag.dart';
import 'drags/transition_edge_drag.dart';
import 'exposure_verbs.dart';
import 'folders_and_attachments.dart';
import 'range_selections.dart';
import 'session_roles.dart';
import 'storyboard_cursor.dart';
import 'track_se_display.dart';
import 'transitions.dart';

/// The EDGE DRAGS' VERBS — an exposure's comma grip, a cut's end grip and a
/// transition's edge, on the timeline and on the storyboard — plus the
/// storyboard cursor's comma, which drives them.
///
/// 🚨The second collaborator carved out of `EditorSessionManager` (the
/// audit's SRP cut, 2026-09-02, after the frame-range move). Measured before
/// cutting: the family touched 24 session members and its eleven
/// `_edgeDrag*` fields were read from outside in one or two places each.
///
/// 🚨What it does NOT keep is those fields, nor the trim's eleven. Round
/// G5-2 (2026-09-10) gave both drags the shape their siblings in `drags/`
/// already had: a factory that answers null when the grip is refused, and an
/// object that holds the mid-drag state for the drag's lifetime only. This
/// class keeps exactly two things about a drag — whether there is one, and
/// which verb the strip's cut-edge continuations belong to.
class EdgeDragVerbs {
  EdgeDragVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required ValueNotifier<TimelineDragPreview?> dragPreview,
    required FoldersAndAttachments folders,
    required RetimeLaw retime,
    required RangeSelections rangeSelections,
    required StoryboardCursor storyboardCursor,
    required TrackSeDisplay trackSe,
    required Transitions transitions,
    required ExposureVerbs exposureVerbs,
  }) : _roles = (
         project: project,
         changes: changes,
         controllers: controllers,
         dragPreview: dragPreview,
       ),
       _beginRoles = (
         trackSe: trackSe,
         folders: folders,
         retime: retime,
         selection: selection,
         rangeSelections: rangeSelections,
       ),
       _selection = selection,
       _storyboardCursor = storyboardCursor,
       _transitions = transitions,
       _exposureVerbs = exposureVerbs;

  /// What a drag in flight is handed (see [EdgeDragRoles]).
  final EdgeDragRoles _roles;

  /// What a comma BEGIN is handed on top of that (see
  /// [ExposureBeginRoles]) — this class's map of the project, which no
  /// gesture keeps.
  final ExposureBeginRoles _beginRoles;

  /// What the transition grip reads for itself.
  final SelectionAccess _selection;
  final Transitions _transitions;

  /// What the comma press reads ([_setCommaAt]).
  final StoryboardCursor _storyboardCursor;
  final ExposureVerbs _exposureVerbs;

  TransitionEdgeDrag? _transitionEdgeDrag;

  /// Grabs [edge] of the transition span starting at [spanStartIndex]
  /// (GLOBAL frame); false when no span starts there — see
  /// [TransitionEdgeDrag.begin] for the active-track scoping rule.
  bool beginTransitionEdgeDrag({
    required int spanStartIndex,
    required TimelineBlockEdge edge,
    LayerId? layerId,
  }) {
    final drag = TransitionEdgeDrag.begin(
      layer: _selection.activeTrack.transitionLayer,
      spanStartIndex: spanStartIndex,
      edge: edge,
      layerId: layerId,
      preview: _roles.dragPreview,
      formsOf: _transitions.previewFormsOf,
      commitInstructions: _transitions.updateTransitionInstructions,
    );
    if (drag == null) {
      // A refused grip leaves an in-flight drag exactly as it was — the slot
      // is only ever cleared by the drag's own end/cancel.
      return false;
    }
    _transitionEdgeDrag = drag;
    return true;
  }

  void updateTransitionEdgeDrag(int cumulativeDelta) =>
      _transitionEdgeDrag?.update(cumulativeDelta);

  /// A grip on a row the CUT view draws: the row's own comma drag — except
  /// the transition row's mark, which drags the GLOBAL span it shows
  /// through the storyboard's own verb (transition-row-open-in-the-cut,
  /// 유저 2026-09-25: 「편집은 동일하게 타임라인에서 다 할수있고, 원본
  /// 데이터는 글로벌에서 가지고있음」). [blockStartIndex] is the block as
  /// the row DRAWS it, which on the transition row is a projection. An
  /// O.L's mark has no grips here (유저 2026-09-26), and refuses one.
  bool beginCutRowEdgeDrag({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
  }) {
    if (!_transitions.isTrackTransitionLayerId(layerId)) {
      return beginExposureEdgeDrag(
        layerId: layerId,
        blockStartIndex: blockStartIndex,
        edge: edge,
      );
    }
    final start = _transitions.transitionSpanStartEditableInCutAt(
      blockStartIndex,
    );
    return start != null &&
        beginTransitionEdgeDrag(
          spanStartIndex: start,
          edge: edge,
          layerId: layerId,
        );
  }

  /// Steps whichever cut-row drag [beginCutRowEdgeDrag] started — only one
  /// is ever in flight, and the other answers nothing.
  void updateCutRowEdgeDrag(int cumulativeDelta) {
    updateExposureEdgeDrag(cumulativeDelta);
    updateTransitionEdgeDrag(cumulativeDelta);
  }

  void endCutRowEdgeDrag() {
    endExposureEdgeDrag();
    endTransitionEdgeDrag();
  }

  void cancelCutRowEdgeDrag() {
    cancelExposureEdgeDrag();
    cancelTransitionEdgeDrag();
  }

  /// Commits the drag as ONE undo step through the row's own writer.
  void endTransitionEdgeDrag() {
    final drag = _transitionEdgeDrag;
    _transitionEdgeDrag = null;
    drag?.commit();
  }

  void cancelTransitionEdgeDrag() {
    final drag = _transitionEdgeDrag;
    _transitionEdgeDrag = null;
    drag?.cancel();
  }

  /// The exposure comma drag in flight, or null. ⛔The only thing this class
  /// keeps about one: what the press grabbed, the bulk and cut-sync captures
  /// and the result the release commits live on the object and die with the
  /// gesture.
  ExposureEdgeDrag? _exposureDrag;

  /// The cut trim in flight, or null.
  CutTrimDrag? _cutTrimDrag;

  /// Takes the drag a factory answered, or reports the refusal.
  ///
  /// ⚠️Assigned only on SUCCESS. The refused begin used to blank every
  /// comma field FIRST — so a grip that landed on a synced attach row, or on
  /// an image row, silently voided the drag already in flight: the release
  /// then committed nothing and the preview stayed on screen. The law is the
  /// transition arm's, written above, and now both obey it.
  bool _takeExposure(ExposureEdgeDrag? drag) {
    if (drag == null) {
      return false;
    }
    _exposureDrag = drag;
    return true;
  }

  /// Starts a comma drag on [edge] of the block starting at
  /// [blockStartIndex] (as DISPLAYED — cut-local); false when there is no
  /// such block. See [ExposureEdgeDrag.begin] for the instruction-span,
  /// track-SE and [blockStartIsGlobal] rules.
  bool beginExposureEdgeDrag({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    bool blockStartIsGlobal = false,
  }) => _takeExposure(
    ExposureEdgeDrag.begin(
      roles: _roles,
      beginRoles: _beginRoles,
      grip: (
        layerId: layerId,
        blockStartIndex: blockStartIndex,
        edge: edge,
        startIsGlobal: blockStartIsGlobal,
      ),
    ),
  );

  /// Applies the drag's current cumulative frame delta as a live preview —
  /// the repository is NOT touched.
  void updateExposureEdgeDrag(int cumulativeDelta) =>
      _exposureDrag?.update(cumulativeDelta);

  /// Commits the drag as a single undo step (no-op when nothing changed).
  void endExposureEdgeDrag() {
    final drag = _exposureDrag;
    _exposureDrag = null;
    drag?.commit();
  }

  /// Drops an in-flight drag preview without touching history.
  void cancelExposureEdgeDrag() {
    final drag = _exposureDrag;
    _exposureDrag = null;
    drag?.cancel();
  }

  /// Starts a comma drag on the block keyed [blockStartIndex] (cut-local) of
  /// [cutId]'s storyboard row — an INNER panel's trailing edge on the strip
  /// (see [ExposureEdgeDrag.beginStoryboardComma]). Returns false when the
  /// cut has no row, or no such drawing block.
  bool beginStoryboardCommaDrag({
    required CutId cutId,
    required int blockStartIndex,
  }) {
    final cut = _roles.project.cutById(cutId);
    if (cut == null) {
      return false;
    }
    if (!_takeExposure(
      ExposureEdgeDrag.beginStoryboardComma(
        roles: _roles,
        trackSe: _beginRoles.trackSe,
        cut: cut,
        blockStartIndex: blockStartIndex,
      ),
    )) {
      return false;
    }
    // Joins the cut-edge continuations ([updateCutEdgeDrag] and friends):
    // the strip's grips share one set of hooks, and which verb a drag
    // belongs to is the session's to remember, not the host's.
    _cutEdgeDragVerb = _CutEdgeDragVerb.comma;
    return true;
  }

  /// Which verb the in-flight cut-edge drag belongs to. One shape of edge,
  /// and where it sits decides what it re-times — the answer is taken at
  /// BEGIN and kept HERE, in the session the continuations already reach, so
  /// a host rebuild mid-drag cannot re-route the release onto a verb whose
  /// object was never built (the failure that sank the first #5 attempt).
  ///
  /// ⛔It is NOT "is there a drag": the timeline's own comma grips drive
  /// [_exposureDrag] without ever going through these hooks, so the two
  /// questions have two fields.
  _CutEdgeDragVerb? _cutEdgeDragVerb;

  /// Starts a cut edge drag on [cutId]'s [edge].
  ///
  /// - the TRAILING edge asks what it sits on (feedback #9): on a cut with a
  ///   storyboard row it is the LAST cell's comma and the cut's length
  ///   follows it (the always-synced pair); otherwise it trims the duration
  ///   ([CutTrimDrag.begin]);
  /// - the LEAD edge is one verb for every cut (R10 R4) — see
  ///   [CutTrimDrag.begin].
  ///
  /// The continuations ([updateCutEdgeDrag], [endCutEdgeDrag],
  /// [cancelCutEdgeDrag]) follow whichever verb began — they carry a delta
  /// and nothing else.
  bool beginCutEdgeDrag({
    required CutId cutId,
    required TimelineBlockEdge edge,
    int panelIndex = 0,
  }) {
    final cut = _roles.project.cutById(cutId);
    final row = cut == null ? null : storyboardLayerForCut(cut);
    // R10 R4: only the TRAILING edge still asks about the conte row, and its
    // two arms agree at the cut level. The LEAD edge does not ask any more —
    // one gesture, one meaning, whether or not the cut has been drawn on.
    // The row still bounds the drag, through [minimumCutDurationFor]: you
    // cannot trim past your own panels.
    //
    // ⛔MUTANT SURVIVES on this edge test, and the classification is NEVER
    // APPLIED (2026-09-08): every cut-edge fixture in the suite trims a cut
    // with NO conte row, so `row` is null and the arm is not reached at all.
    // A test that draws a panel first is what would kill it.
    if (cut != null && row != null && edge == TimelineBlockEdge.end) {
      if (_takeExposure(
        ExposureEdgeDrag.beginStoryboardLastComma(
          roles: _roles,
          trackSe: _beginRoles.trackSe,
          cut: cut,
        ),
      )) {
        _cutEdgeDragVerb = _CutEdgeDragVerb.comma;
        return true;
      }
    }
    final trim = CutTrimDrag.begin(
      roles: _roles,
      cutId: cutId,
      edge: edge,
      panelIndex: panelIndex,
    );
    if (trim == null) {
      return false;
    }
    _cutTrimDrag = trim;
    _cutEdgeDragVerb = _CutEdgeDragVerb.cutTrim;
    return true;
  }

  /// Applies the drag's cumulative frame delta to whichever verb
  /// [beginCutEdgeDrag] (or [beginStoryboardCommaDrag]) chose.
  void updateCutEdgeDrag(int cumulativeDelta) {
    switch (_cutEdgeDragVerb) {
      case null:
        return;
      case _CutEdgeDragVerb.cutTrim:
        _cutTrimDrag?.update(cumulativeDelta);
      case _CutEdgeDragVerb.comma:
        updateExposureEdgeDrag(cumulativeDelta);
    }
  }

  /// Commits whichever verb began, as a single undo step.
  void endCutEdgeDrag() {
    final verb = _cutEdgeDragVerb;
    _cutEdgeDragVerb = null;
    switch (verb) {
      case null:
        return;
      case _CutEdgeDragVerb.cutTrim:
        _endCutTrimDrag();
      case _CutEdgeDragVerb.comma:
        endExposureEdgeDrag();
    }
  }

  /// Drops whichever verb began without touching history.
  void cancelCutEdgeDrag() {
    final verb = _cutEdgeDragVerb;
    _cutEdgeDragVerb = null;
    switch (verb) {
      case null:
        return;
      case _CutEdgeDragVerb.cutTrim:
        _cancelCutTrimDrag();
      case _CutEdgeDragVerb.comma:
        cancelExposureEdgeDrag();
    }
  }

  void _endCutTrimDrag() {
    final drag = _cutTrimDrag;
    _cutTrimDrag = null;
    drag?.commit();
  }

  void _cancelCutTrimDrag() {
    final drag = _cutTrimDrag;
    _cutTrimDrag = null;
    drag?.cancel();
  }

  /// The storyboard's comma press: the selection's blocks, else THE BLOCK
  /// UNDER THE CURSOR takes length [comma] — one rule for every block kind
  /// (B8: 「컷블록 위 4 = 컷길이 4」, superseded by D28 2026-08-18 exactly
  /// where the cut carries a storyboard layer — its PANEL takes the comma
  /// then), each kind through the SAME machinery its own grips already
  /// commit with:
  ///
  /// - a CUT block rides the trailing-edge drag verbs, so a conte row's last
  ///   comma and the following gap behave exactly as if the edge had been
  ///   dragged to frame [comma];
  /// - a ROW's block — an S row's, a cel row's — takes the comma buttons'
  ///   own retime ([ExposureVerbs.retimeKeepingTheCutOnItsRow]), stated in
  ///   the row's commit keys;
  /// - a TRANSITION span rides its edge-drag verbs (the grips own length).
  void setCommaForStoryboardCursor(int comma) =>
      _setCommaAt(_storyboardCursor.storyboardCursorBlockOrNull, comma);

  /// The TIMELINE's comma press: the selection's blocks, else THE BLOCK
  /// UNDER ITS CURSOR ([StoryboardCursor.timelineCursorBlockOrNull]) — by
  /// the storyboard's own ladder and dispatch, so a block takes the comma
  /// whichever panel shows it (F-283, 유저 2026-10-04: 「블록이면 1,2,3,4 등
  /// 코마조절버튼 작동하는게 규칙임」).
  void setCommaForTimelineCursor(int comma) =>
      _setCommaAt(_storyboardCursor.timelineCursorBlockOrNull, comma);

  /// One press for both panels — THE selection's blocks
  /// ([ExposureVerbs.setCommaForSelection]: either axis, and a cell band
  /// that holds none ends the press there), else the block [cursorBlock]
  /// resolves, each kind through the machinery its own grips commit with.
  ///
  /// ↩️The panels differed in more than their cursor: the storyboard's
  /// press had the track-axis band's rung and the timeline's had none, and
  /// the timeline's cursor rung was a second resolver of its own (F-283).
  void _setCommaAt(StoryboardCursorBlock? Function() cursorBlock, int comma) {
    if (comma < 1 || _exposureVerbs.setCommaForSelection(comma)) {
      return;
    }
    switch (cursorBlock()) {
      case null:
        return;
      case StoryboardCursorCutBlock(:final cut):
        if (comma == cut.duration) {
          return; // A no-move drag must not land an undo step.
        }
        if (!beginCutEdgeDrag(cutId: cut.id, edge: TimelineBlockEdge.end)) {
          return;
        }
        updateCutEdgeDrag(comma - cut.duration);
        endCutEdgeDrag();
      case StoryboardCursorRowBlock(:final layerId, :final blockStartIndex):
        // The comma buttons' own retime — a conte row takes its cut along
        // (F-91 · F-100), every other row is re-timed alone.
        //
        // ↩️The S rows' arm returned here with no active cut — a copy of
        // the sentence H11 retired (유저 2026-08-22: 「각 행들은 독립적인
        // 글로벌행이라 뭐든 가능해야함」), which the gate and the delete had
        // already dropped: parked in a gap over a sound, the buttons were lit
        // and the press did nothing. The start is in the row's own keys and
        // the retime applies no lens — a gap changes nothing about them.
        _exposureVerbs.retimeKeepingTheCutOnItsRow({
          layerId: {blockStartIndex: comma},
        });
        _roles.changes.warmActiveCut();
        _roles.changes.notifyChanged();
      case StoryboardCursorTransitionSpan(
        :final spanStartIndex,
        :final spanLength,
      ):
        if (comma == spanLength) {
          return;
        }
        if (!beginTransitionEdgeDrag(
          spanStartIndex: spanStartIndex,
          edge: TimelineBlockEdge.end,
        )) {
          return;
        }
        updateTransitionEdgeDrag(comma - spanLength);
        endTransitionEdgeDrag();
      case StoryboardCursorStoryboardPanel(
        :final cut,
        :final panelStartIndex,
        :final panelLength,
      ):
        // D28: the panel rides the storyboard comma drag — ripple + the cut
        // length following the LAST panel's edge (feedback #9), one drag =
        // one undo, exactly as the strip's own grips commit.
        if (comma == panelLength) {
          return;
        }
        if (!beginStoryboardCommaDrag(
          cutId: cut.id,
          blockStartIndex: panelStartIndex,
        )) {
          return;
        }
        updateCutEdgeDrag(comma - panelLength);
        endCutEdgeDrag();
    }
  }
}

/// Which verb an in-flight cut-edge drag belongs to (feedback #5/#9). One
/// shape of edge, and where it sat when the drag began decides what it
/// re-times; the session keeps the answer so the continuations cannot be
/// re-routed by anything a live preview rebuilds.
enum _CutEdgeDragVerb {
  /// Both cut edges' plain duration/gap drags. R10 R4 folded the lead edge's
  /// second verb into this one: a conte row no longer changes what dragging
  /// a cut's front edge means, only how far it may go.
  cutTrim,

  /// ANY panel's trailing edge: that cell's comma, the later panels rippling
  /// glued and the cut's length riding the row end (feedback #9; the edge
  /// unification retired the division verb this replaced).
  comma,
}
