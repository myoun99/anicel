part of '../editor_session_manager.dart';

/// The STORYBOARD ROWS — the row the storyboard stands on, the rail rows
/// it shows, the cut selection swept across them, and the next cut in
/// storyboard order — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: one field of its own and twelve
/// session members touched. It reaches the session through `_session`.
class _StoryboardRows {
  _StoryboardRows(this._session);

  final EditorSessionManager _session;

  /// The storyboard rail's own selected row, as picked. Null = never
  /// picked, which reads as the selected track's V row.
  TimelineRowAddress? _storyboardRow;

  /// 🚨★★★THE CLAIM READS THE STORE, the way [_session.claimTimelineRow] does.
  ///
  /// ⛔It used to read [_session.selectedRow], and that getter answers a DIFFERENT
  /// question: 「which RAIL row is lit」. A lane is a subject (R10 #19) but
  /// never a rail row, so the getter collapses it to the track — and this
  /// claim, which fires on the host's OUTERMOST pointer-down, therefore ran
  /// last on every press and un-stood you from the lane the press had just
  /// stood on. One getter answering two questions, which is the shape
  /// CLAUDE.md names: 「한 플래그가 두 질문에 답하는 것도 발명이다」.
  ///
  /// 🚨It looked fine for a year because of an accident of timing: a finger
  /// stood on the RELEASE, after this claim, so the lane survived. A mouse
  /// never did — pressing a storyboard lane band with a mouse has been
  /// leaving the ring on the track row all along, and only lifting the
  /// finger's carve-out (터치 묘화 ON) made a test say so.
  ///
  /// ⛔But only a lane THIS RAIL SHOWS. A timeline lane also passes through
  /// [_session.selectRow], and claiming one here would leave the storyboard's flip
  /// counting drawings instead of cuts — the very law this claim exists to
  /// keep (「touching the storyboard hands the flip its rail's row」).
  /// [_session._trackSe.trackOwnedRailOwner] is the question already asked of a lane's
  /// carrier elsewhere, so no new rule is written here.
  void claimStoryboardRow() {
    final stored = _storyboardRow;
    _session._verbRow =
        stored is LaneRowAddress &&
            _session._trackSe.trackOwnedRailOwner(stored.layerId) != null
        ? stored
        : _session.selectedRow;
    _session._publishCurrentRow();
  }

  /// Stores the rail's row. Returns whether the ANSWER moved — the store
  /// and the answer differ, since a row the rail no longer shows resolves
  /// back to the track row.
  bool storeStoryboardRow(TimelineRowAddress row) {
    final before = _session.selectedRow;
    _storyboardRow = row;
    // Picking a rail row is also engaging it, so the verb follows (R10
    // #13). The reverse does not hold — see [_verbRow].
    _session._verbRow = row;
    _session._publishCurrentRow();
    return _session.selectedRow != before;
  }

  /// The cut after [cutId] in storyboard order, or null at the end.
  CutId? nextCutIdInStoryboardOrder(CutId cutId) {
    final layout = _session._projectLayout();
    for (var index = 0; index < layout.length; index += 1) {
      if (layout[index].cutId == cutId) {
        return index + 1 < layout.length ? layout[index + 1].cutId : null;
      }
    }
    return null;
  }

  /// The cuts the storyboard selection covers — DERIVED from the range, in
  /// track order.
  List<CutId> get storyboardSelectedCutIds {
    final selection = _session.trackFrameRangeSelection.value;
    if (selection == null ||
        !selection.coversRow(TrackRowAddress(selection.trackId))) {
      return const [];
    }
    return _session
        ._axisForTrack(selection.trackId)
        .cutsIn(selection.startFrame, selection.endFrameExclusive);
  }

  /// A cut-select drag step stated on the track's GLOBAL FRAME axis — the
  /// timeline's range grammar, cuts as the blocks. Dragging from anywhere
  /// inside one cut to anywhere inside another selects both whole, and a
  /// span that only crosses a gap selects nothing there.
  ///
  /// This is the ONLY cut-select entry point: the storyboard's cut row now
  /// mounts the shared range gesture, which speaks frames, so the ordinal
  /// form it used to need is gone.
  ///
  /// [trackId] names the row the drag is on; omitting it means the selected
  /// track (the panel always knows, the session's own callers rarely do).
  void updateStoryboardCutSelectionByFrame({
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TrackId? trackId,
    TimelineRowAddress? headRow,
  }) {
    final row = trackId ?? _session.selectedTrackId;
    _session._rangeSelections._updateTrackRangeSelection(
      trackId: row,
      anchorRow: TrackRowAddress(row),
      anchorGlobalFrame: anchorGlobalFrame,
      headGlobalFrame: headGlobalFrame,
      headRow: headRow,
    );
  }

  /// The storyboard rail's rows for [trackId], in the order the panel
  /// stacks them: the SE rows top-down (highest slot first — slot 0 sits
  /// just above the cut row), then the CUT row at the bottom.
  ///
  /// A range drag walks THIS list (feedback #14, the timeline's Excel-style
  /// cross-row select), so the list order IS the visual order — a positive
  /// row delta must mean "downward on screen". It used to lead with the
  /// cut row, which inverted every cross-row drag: dragging from an S row
  /// down toward the V row walked the list AWAY from it (the real-device
  /// "row-span select does nothing" report).
  ///
  /// Only track-GLOBAL rows are on it — the strip is a cut-owned row on
  /// the other axis, so it cannot be reached by a row delta, and the clamp
  /// below is therefore the whole of the kind guard (the row-move
  /// precedent: what is not on the list is unreachable, so there is
  /// nothing to refuse).
  List<TimelineRowAddress> storyboardRailRows(TrackId trackId) {
    final track = _session._trackById(trackId);
    return [
      // The TRANSITION row heads the group on screen, so it heads the list: a
      // row delta walks this in VISUAL order, and a row missing from it is
      // unreachable — which is what left a cross-row drag unable to start on
      // it or arrive at it (user 2026-08-11).
      if (track != null) LayerRowAddress(track.transitionLayer.id),
      if (track != null)
        for (final layer in track.seLayers.reversed) LayerRowAddress(layer.id),
      TrackRowAddress(trackId),
    ];
  }

  void clearStoryboardCutSelection() {
    if (_session.trackFrameRangeSelection.value != null) {
      _session.trackFrameRangeSelection.value = null;
    }
  }
}
