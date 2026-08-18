import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/delete_subject.dart';
import '../../models/edit_instance_subject.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart' show coveringDrawingBlockAt;
import '../../models/timeline_row_address.dart';
import '../../models/track_id.dart';
import '../editor_session_manager.dart';

/// B8 (2026-08-17): 상단 버튼의 패널 스코프 — the shared toolbar's layer,
/// frame, shared and fx verbs dispatch AGAINST THE PANEL THEY ARE PRESSED
/// IN, and the toolbar asks its host panel through THIS interface instead
/// of hard-reading the cut timeline's context.
///
/// The cut buttons are deliberately NOT here: the cut noun's verbs were
/// already panel-correct (the cut group keeps reading the session), and B8
/// names them as the exception.
///
/// ★One law, two speakers. The TIMELINE's answers are the session's
/// cut-local, active-layer verbs — every delegation byte-identical to what
/// the toolbar read before this interface existed. The STORYBOARD's answers
/// are its own standing row crossed with the track-global playhead
/// ([EditorSessionManager.selectedRow] × [EditorSessionManager.editingGlobalFrame]),
/// because that rail's standing row is separate state from the cut's
/// drawing target (유저 2026-07-27) — the reason every session getter the
/// toolbar used to read answered about the WRONG panel from over there.
///
/// 🚨T25's law holds per member: a button's enablement and what its press
/// DOES must come from one answer, so every `can*` here has its verb beside
/// it and the storyboard's edit gate and edit dispatch share one resolver
/// ([StoryboardToolbarPanelContext.editTarget]).
abstract class ToolbarPanelContext {
  // --- LAYER pill -----------------------------------------------------------

  /// The bare `＋`: ONE kind, always, no looking first (⑥'s law) — the
  /// timeline makes an animation layer, the storyboard an S row.
  void addLayer();

  /// The `＋` band's per-kind gate and verb — the same pair, so a lit entry
  /// and a working press cannot come apart.
  bool canAddLayerOfKind(LayerKind kind);
  void addLayerOfKind(LayerKind kind);

  /// The attach entries (W5): riders on the CUT's active layer, which only
  /// the timeline panel can name.
  bool get canAddAttachedLayer;
  void addAttachedLayer(AttachedPlacement placement, {AttachedMode mode});

  /// Whether the session's ACTIVE-LAYER menu verbs (the layer menu, the
  /// frame menu's duplicates, the fx list) are THIS panel's own subject.
  ///
  /// The storyboard answers false and those entries grey out honestly: its
  /// rows are tracks, S rows and the transition fixture, and none of them
  /// is the cut's active layer — a lit entry there would edit a row the
  /// panel is not even showing.
  bool get servesActiveLayerVerbs;

  // --- FRAME pill -----------------------------------------------------------

  bool get canCreateInstance;

  bool get canBlankExposure;
  void blankExposure();

  bool get canToggleMark;
  void toggleMark();

  /// The 1/2/3/4/N comma press: the selection's blocks, else THE BLOCK
  /// UNDER THIS PANEL'S CURSOR — on the storyboard that is the standing
  /// row's block at the global playhead, cut blocks included (컷블록 위
  /// 4 = 컷길이 4 — superseded by D28 where the cut carries a storyboard
  /// layer: its PANEL takes the comma then), one rule for every block
  /// kind.
  bool get canSetComma;
  void setComma(int comma);

  /// D40: select the standing row's WHOLE authored span — first authored
  /// cell through last — as a range selection. On the storyboard the
  /// standing row may be the cut row, whose blocks are its cuts (컷블록도
  /// 동일 작동).
  bool get canSelectRowSpan;
  void selectRowSpan();

  // --- SHARED pill ----------------------------------------------------------

  bool get canEditInstance;

  bool get canCutRun;
  void cutRun();

  bool get canCopyFrame;
  void copyFrame();

  bool get canPasteIndependentFrame;
  void pasteIndependentFrame();

  bool get canPasteLinkedFrame;
  void pasteLinkedFrame();

  DeleteSubject get deleteSubject;
  void deleteSelectionSubject();
}

/// The cut timeline's context: the session's own verbs, verbatim. Every
/// member is a one-line delegation on purpose — this panel's dispatch is
/// the baseline B8 pins, so the wrapper must add nothing to it.
class TimelineToolbarPanelContext implements ToolbarPanelContext {
  const TimelineToolbarPanelContext(this.session);

  final EditorSessionManager session;

  // ⑥ 유저 2026-08-12: 「레이어 +버튼, 선택된 레이어 기준이아니라 애니메이션
  // 레이어 생성.」 — moved here verbatim from the button.
  @override
  void addLayer() => session.addLayerOfKind(LayerKind.animation);

  @override
  bool canAddLayerOfKind(LayerKind kind) => session.canAddLayerOfKind(kind);

  @override
  void addLayerOfKind(LayerKind kind) => session.addLayerOfKind(kind);

  @override
  bool get canAddAttachedLayer => session.canAddAttachedLayerToActive;

  @override
  void addAttachedLayer(
    AttachedPlacement placement, {
    AttachedMode mode = AttachedMode.synced,
  }) => session.addAttachedLayer(placement, mode: mode);

  @override
  bool get servesActiveLayerVerbs => true;

  @override
  bool get canCreateInstance => session.canCreateInstance;

  @override
  bool get canBlankExposure => session.canBlankExposureAtCurrentFrame;

  @override
  void blankExposure() => session.blankExposureAtCurrentFrame();

  @override
  bool get canToggleMark => session.canToggleMarkAtCurrentFrame;

  @override
  void toggleMark() => session.toggleMarkAtCurrentFrame();

  @override
  bool get canSetComma => session.canSetCommaForSelectionOrCurrent;

  @override
  void setComma(int comma) => session.setCommaForSelectionOrCurrent(comma);

  @override
  bool get canSelectRowSpan => session.canSelectRowSpanForCurrentRow;

  @override
  void selectRowSpan() => session.selectRowSpanForCurrentRow();

  @override
  bool get canEditInstance =>
      session.editInstanceSubject != EditInstanceSubject.nothing;

  @override
  bool get canCutRun => session.canCutRunAtCurrentFrame;

  @override
  void cutRun() => session.cutRunAtCurrentFrame();

  @override
  bool get canCopyFrame => session.canCopyFrameAtCurrentFrame;

  @override
  void copyFrame() => session.copyFrameAtCurrentFrame();

  @override
  bool get canPasteIndependentFrame =>
      session.canPasteIndependentFrameAtCurrentFrame;

  @override
  void pasteIndependentFrame() => session.pasteIndependentFrameAtCurrentFrame();

  @override
  bool get canPasteLinkedFrame => session.canPasteLinkedFrameAtCurrentFrame;

  @override
  void pasteLinkedFrame() => session.pasteLinkedFrameAtCurrentFrame();

  @override
  DeleteSubject get deleteSubject => session.deleteSubject;

  @override
  void deleteSelectionSubject() => session.deleteSelectionSubject();
}

/// What the storyboard's Edit Instance press opens — resolved ONCE
/// ([StoryboardToolbarPanelContext.editTarget]) so the button's enablement
/// and the host's dialog dispatch cannot drift apart (T25's lesson: two
/// predicates that disagree leave a lit button whose press does nothing).
sealed class StoryboardEditTarget {
  const StoryboardEditTarget();
}

/// The cut's instance: the selection's cuts, or the cut block under the
/// cursor — the same rename dialog the shared ladder's cuts rung opens.
class StoryboardEditCut extends StoryboardEditTarget {
  const StoryboardEditCut();
}

/// The SE block under the cursor on the standing S row, addressed on the
/// global axis (the #1113 door, [editSeEntryInstance]).
class StoryboardEditSeEntry extends StoryboardEditTarget {
  const StoryboardEditSeEntry({
    required this.layerId,
    required this.globalFrame,
  });

  final LayerId layerId;
  final int globalFrame;
}

/// The transition span under the cursor (or its creation on an empty
/// frame — that row's one-verb law, 유저 2026-08-11).
class StoryboardEditTransitionSpan extends StoryboardEditTarget {
  const StoryboardEditTransitionSpan();
}

/// A lane row's instance is its KEY — the same rename the timeline's lane
/// standing opens; lane state is session-shared, so this panel serves it
/// too.
class StoryboardEditLaneKey extends StoryboardEditTarget {
  const StoryboardEditLaneKey();
}

/// The storyboard's context: the standing row crossed with the track-global
/// playhead. Selections speak first, exactly as they do on the timeline's
/// ladders — and the selections this panel writes (the cut range, the S-row
/// range, the strip's cut-local range, lane spans) are the same session
/// objects, so those rungs delegate.
class StoryboardToolbarPanelContext implements ToolbarPanelContext {
  const StoryboardToolbarPanelContext(this.session);

  final EditorSessionManager session;

  /// The rail's ONE addable kind: an S row (track-owned SE). V tracks and
  /// the transition row are fixtures nothing can add ("disable" is the
  /// honest state B8 names), and the cut-scoped kinds belong to the
  /// timeline panel's stack, which this panel does not show.
  @override
  void addLayer() => session.addLayerOfKind(LayerKind.se);

  @override
  bool canAddLayerOfKind(LayerKind kind) =>
      kind == LayerKind.se && session.canAddLayerOfKind(kind);

  @override
  void addLayerOfKind(LayerKind kind) {
    if (!canAddLayerOfKind(kind)) {
      return;
    }
    session.addLayerOfKind(kind);
  }

  @override
  bool get canAddAttachedLayer => false;

  @override
  void addAttachedLayer(
    AttachedPlacement placement, {
    AttachedMode mode = AttachedMode.synced,
  }) {}

  @override
  bool get servesActiveLayerVerbs => false;

  bool get _standingOnTransitionRow {
    final row = session.selectedRow;
    return row is LayerRowAddress &&
        session.isTrackTransitionLayerId(row.layerId);
  }

  /// Create on this panel: the selection rungs (track S-row gaps, lane
  /// keys, the strip's cut-local range — all this panel's own selections),
  /// then the standing row — the transition row's one-verb fusion, or a
  /// fresh SE entry on the standing S row's empty cursor frame.
  @override
  bool get canCreateInstance {
    if (session.canCreateInstanceForSelection) {
      return true;
    }
    if (_standingOnTransitionRow) {
      return session.transitionSpanAt(session.editingGlobalFrame) != null ||
          session.canCreateTransitionSpanAtPlayhead;
    }
    // D28: on the cut row with a storyboard layer, the ＋ divides the
    // panel under the cursor — the same one-resolver pair the dispatch
    // reads.
    if (session.canCreateStoryboardPanelAtCursor) {
      return true;
    }
    return session.canCreateSeEntryAtStoryboardCursor;
  }

  // An exposure X and a cell mark are cut-local, active-layer notions with
  // no row-addressed verb on this axis — greyed out honestly rather than
  // dispatched against the other panel's context.
  @override
  bool get canBlankExposure => false;

  @override
  void blankExposure() {}

  @override
  bool get canToggleMark => false;

  @override
  void toggleMark() {}

  @override
  bool get canSetComma => session.canSetCommaForStoryboardCursor;

  @override
  void setComma(int comma) => session.setCommaForStoryboardCursor(comma);

  /// D40's one resolver (T25): the standing row's whole span on the
  /// track's global axis — a null layerId means the CUT row, whose span is
  /// selected through the one cut-select entry point on the trackId the
  /// row itself names (never [EditorSessionManager.selectedTrackId] — the
  /// stale re-key the select path already removed).
  ({LayerId? layerId, TrackId? trackId, int anchorFrame, int headFrame})?
  get _rowSpanTarget {
    switch (session.selectedRow) {
      case TrackRowAddress(:final trackId):
        final span = session.trackCutSpan(trackId);
        if (span == null) {
          return null;
        }
        return (
          layerId: null,
          trackId: trackId,
          anchorFrame: span.startFrame,
          headFrame: span.endFrameExclusive - 1,
        );
      case LayerRowAddress(:final layerId):
        final span = session.trackRowAuthoredSpan(layerId);
        if (span == null) {
          return null;
        }
        return (
          layerId: layerId,
          trackId: null,
          anchorFrame: span.startFrame,
          headFrame: span.endFrameExclusive - 1,
        );
      case LaneRowAddress():
        // Lane keys are points with no block snap — no span to select.
        return null;
    }
  }

  @override
  bool get canSelectRowSpan => _rowSpanTarget != null;

  @override
  void selectRowSpan() {
    final target = _rowSpanTarget;
    if (target == null) {
      return;
    }
    final layerId = target.layerId;
    if (layerId == null) {
      session.updateStoryboardCutSelectionByFrame(
        anchorGlobalFrame: target.anchorFrame,
        headGlobalFrame: target.headFrame,
        trackId: target.trackId,
      );
      return;
    }
    session.updateTrackRowRangeSelectionByFrame(
      layerId: layerId,
      anchorGlobalFrame: target.anchorFrame,
      headGlobalFrame: target.headFrame,
    );
  }

  /// THE one resolver behind the edit button: what the press would open.
  /// [canEditInstance] and the host's dispatch both read this.
  StoryboardEditTarget? get editTarget {
    // The selection speaks first — the shared ladder's own order.
    if (session.trackFrameRangeSelection.value != null) {
      return const StoryboardEditCut();
    }
    // …and a live CELL band speaks before the standing row does, exactly
    // as it does in this class's [deleteSubject]. This panel owns no
    // cell-rename dispatch, so a band holding nothing ENDS the ladder —
    // without this it fell through to the row rung below, where a
    // TrackRowAddress cursor means "rename the cut". Delete and Rename
    // are documented as ONE ladder; splitting them here would leave the
    // same band dark on one button and aimed at the cut on the other.
    if (session.cellSelectionClaimsButHoldsNothing) {
      return null;
    }
    switch (session.selectedRow) {
      case LayerRowAddress(:final layerId)
          when session.isTrackTransitionLayerId(layerId):
        return session.transitionSpanAt(session.editingGlobalFrame) != null ||
                session.canCreateTransitionSpanAtPlayhead
            ? const StoryboardEditTransitionSpan()
            : null;
      case LayerRowAddress(:final layerId):
        final layer = session.trackSeGlobalLayerById(layerId);
        final frame = session.editingGlobalFrame;
        if (layer == null ||
            frame < 0 ||
            coveringDrawingBlockAt(layer.timeline, frame) == null) {
          return null;
        }
        return StoryboardEditSeEntry(layerId: layerId, globalFrame: frame);
      case LaneRowAddress():
        return session.canNameLaneKeys
            ? const StoryboardEditLaneKey()
            : null;
      case TrackRowAddress():
        return session.editingPlayheadInGap || session.activeCutOrNull == null
            ? null
            : const StoryboardEditCut();
    }
  }

  @override
  bool get canEditInstance => editTarget != null;

  // The cell clipboard (cut / copy / the two pastes) addresses the active
  // layer at the cut-local playhead — the timeline panel's noun; no
  // global-axis clipboard exists to dispatch instead.
  @override
  bool get canCutRun => false;

  @override
  void cutRun() {}

  @override
  bool get canCopyFrame => false;

  @override
  void copyFrame() {}

  @override
  bool get canPasteIndependentFrame => false;

  @override
  void pasteIndependentFrame() {}

  @override
  bool get canPasteLinkedFrame => false;

  @override
  void pasteLinkedFrame() {}

  /// Delete's ladder, said of this panel: the cut selection (the session's
  /// own cuts rung), the selection-borne cell rungs (lane keys, selected
  /// blocks — this panel's lanes and strips write those), then THE BLOCK
  /// UNDER THE CURSOR, whatever its kind.
  @override
  DeleteSubject get deleteSubject {
    if (session.trackFrameRangeSelection.value != null) {
      return DeleteSubject.cuts;
    }
    if (session.canDeleteCellForSelection) {
      return DeleteSubject.cells;
    }
    // A live CELL band claims the press even when it holds nothing this
    // panel may delete — the same guard the strip's comma verb already
    // states. Without it a band the collector refuses fell through to the
    // cursor rung, where a TRACK-ROW cursor means "delete the cut".
    if (session.cellSelectionClaimsSubject) {
      return DeleteSubject.nothing;
    }
    return session.canDeleteBlockAtStoryboardCursor
        ? DeleteSubject.cells
        : DeleteSubject.nothing;
  }

  @override
  void deleteSelectionSubject() {
    if (session.trackFrameRangeSelection.value != null) {
      session.deleteSelectionSubject();
      return;
    }
    if (session.canDeleteCellForSelection) {
      session.deleteCellAtCurrentFrame();
      return;
    }
    if (session.cellSelectionClaimsSubject) {
      return;
    }
    session.deleteBlockAtStoryboardCursor();
  }
}
