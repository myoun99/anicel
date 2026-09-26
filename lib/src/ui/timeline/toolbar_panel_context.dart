import 'dart:async';

import 'package:flutter/widgets.dart' show BuildContext;

import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/cut_id.dart';
import '../../models/pill_subject.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart' show coveringDrawingBlockAt;
import '../../models/timeline_row_address.dart';
import '../../models/track_id.dart';
import '../editor_command_actions.dart' show createActiveInstance;
import '../editor_session_manager.dart';
import '../paste_with_its_media.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;

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
/// ([EditorSessionManager.storyboardStandingRow] ×
/// [EditorSessionManager.editingGlobalFrame]),
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

  /// The frame `＋`'s press — beside its gate (T25), because a KEY presses it
  /// too (I-19) and the key must do exactly what this panel's button does.
  void createInstance();

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

  /// The row the frame pill's shove (push/pull) aims at with nothing
  /// selected — null leaves the session's own rule (the active layer at the
  /// cut-local cell). One answer for the shove buttons and their keys.
  TimelineRowAddress? get shiftCurrentRow;

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

  PillSubject get deleteSubject;
  void deleteSelectionSubject();

  /// 🚨I-45 — the link-independent button: whether this panel's press would
  /// unlink anything, and the press. One answer for both (T25's law).
  bool get canUnlink;
  void unlink();
}

/// What each SHARED pill button does when it is pressed — null while it has
/// nothing to do.
///
/// ★ONE ANSWER FOR THE BUTTON AND ITS KEY (I-19). The pill lights from these
/// and fires them; Ctrl+X/C/V/B and Delete fire the same getters on the
/// context of the panel being worked in, so a key can never do what its
/// button would not. ↩️They fired the TIMELINE's context whichever panel you
/// were in (09-13, the one every bound film verb spoke to then — a session's
/// pick, not a ruling: the order was 「여러 단축키 기존 버튼에 연결」), and the
/// storyboard's pill answered differently from its own keys.
extension ToolbarSharedPresses on ToolbarPanelContext {
  void Function()? get cutPress => canCutRun ? cutRun : null;

  void Function()? get copyPress => canCopyFrame ? copyFrame : null;

  void Function()? get pasteIndependentPress =>
      canPasteIndependentFrame ? pasteIndependentFrame : null;

  void Function()? get pasteLinkedPress =>
      canPasteLinkedFrame ? pasteLinkedFrame : null;

  void Function()? get unlinkPress => canUnlink ? unlink : null;

  /// F: the ROWS rung asks first. It inherited that from the loose layer
  /// button this pill folded in — a delete that used to confirm must not
  /// stop confirming because its button moved, or because a key pressed it.
  /// The cell rung goes straight through, as it always has.
  void Function()? deletePress({void Function()? onDeleteRowSelection}) =>
      switch (deleteSubject) {
        PillSubject.nothing => null,
        PillSubject.layers when onDeleteRowSelection != null =>
          onDeleteRowSelection,
        _ => deleteSelectionSubject,
      };
}

/// The cut timeline's context: the session's own verbs, verbatim. Every
/// member is a one-line delegation on purpose — this panel's dispatch is
/// the baseline B8 pins, so the wrapper must add nothing to it.
class TimelineToolbarPanelContext implements ToolbarPanelContext {
  const TimelineToolbarPanelContext(this.session, {this.waitIn});

  final EditorSessionManager session;

  /// Where a paste that brings media from another project puts up its wait
  /// window ([pasteWithItsMedia]) — the widget the press came through.
  /// Without one (a test's context) the paste lands at once, recording no
  /// carried medium it has not held.
  final BuildContext? waitIn;

  // ⑥ 유저 2026-08-12: 「레이어 +버튼, 선택된 레이어 기준이아니라 애니메이션
  // 레이어 생성.」 — moved here verbatim from the button.
  @override
  void addLayer() => session.layerStack.addLayerOfKind(LayerKind.animation);

  @override
  bool canAddLayerOfKind(LayerKind kind) => session.layerStack.canAddLayerOfKind(kind);

  @override
  void addLayerOfKind(LayerKind kind) => session.layerStack.addLayerOfKind(kind);

  @override
  bool get canAddAttachedLayer => session.folders.canAddAttachedLayerToActive;

  @override
  void addAttachedLayer(
    AttachedPlacement placement, {
    AttachedMode mode = AttachedMode.synced,
  }) => session.folders.addAttachedLayer(placement, mode: mode);

  @override
  bool get servesActiveLayerVerbs => true;

  @override
  bool get canCreateInstance => session.canCreateInstance;

  @override
  void createInstance() => createActiveInstance(session);

  @override
  bool get canBlankExposure => session.exposureVerbs.canBlankExposureAtCurrentFrame;

  @override
  void blankExposure() => session.exposureVerbs.blankExposureAtCurrentFrame();

  @override
  bool get canToggleMark => session.layerMarks.canToggleMarkAtCurrentFrame;

  @override
  void toggleMark() => session.layerMarks.toggleMarkAtCurrentFrame();

  @override
  bool get canSetComma => session.exposureVerbs.canSetCommaForSelectionOrCurrent;

  @override
  void setComma(int comma) => session.exposureVerbs.setCommaForSelectionOrCurrent(comma);

  @override
  bool get canSelectRowSpan => session.rangeSelections.canSelectRowSpanForCurrentRow;

  @override
  void selectRowSpan() => session.rangeSelections.selectRowSpanForCurrentRow();

  @override
  TimelineRowAddress? get shiftCurrentRow => null;

  @override
  /// R5q1: CUTS are the storyboard's noun, so this panel's Edit does not
  /// reach for them — 「타임라인에서는 타임라인의 것을」.
  bool get canEditInstance =>
      session.cellInstances.editInstanceSubjectFor(cutsAreThisPanels: false) !=
      PillSubject.nothing;

  @override
  bool get canCutRun => session.clipboard.canCutRunAtCurrentFrame;

  @override
  void cutRun() => session.clipboard.cutRunAtCurrentFrame();

  @override
  bool get canCopyFrame => session.canCopyFrameAtCurrentFrame;

  @override
  void copyFrame() => session.copyFrameAtCurrentFrame();

  @override
  bool get canPasteIndependentFrame =>
      session.canPasteIndependentFrameAtCurrentFrame;

  @override
  void pasteIndependentFrame() {
    final context = waitIn;
    if (context == null) {
      session.pasteIndependentFrameAtCurrentFrame();
      return;
    }
    unawaited(
      pasteWithItsMedia(
        context,
        title: editorActionLabel(EditorActionIds.editPasteIndependent),
        board: session.clipboard,
        paste: session.pasteIndependentFrameAtCurrentFrame,
      ),
    );
  }

  @override
  bool get canPasteLinkedFrame => session.canPasteLinkedFrameAtCurrentFrame;

  @override
  void pasteLinkedFrame() => session.pasteLinkedFrameAtCurrentFrame();

  @override
  PillSubject get deleteSubject =>
      session.deleteSubjectFor(cutsAreThisPanels: false);

  @override
  void deleteSelectionSubject() =>
      session.deleteSelectionSubject(cutsAreThisPanels: false);

  @override
  bool get canUnlink => session.unlinkSubject != PillSubject.nothing;

  @override
  void unlink() => session.unlinkSelectionSubject();
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
  void addLayer() => session.layerStack.addLayerOfKind(LayerKind.se);

  @override
  bool canAddLayerOfKind(LayerKind kind) =>
      kind == LayerKind.se && session.layerStack.canAddLayerOfKind(kind);

  @override
  void addLayerOfKind(LayerKind kind) {
    if (!canAddLayerOfKind(kind)) {
      return;
    }
    session.layerStack.addLayerOfKind(kind);
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
    final row = session.storyboardStandingRow;
    return row is LayerRowAddress &&
        session.isTrackTransitionLayerId(row.layerId);
  }

  /// Create on this panel: the selection rungs (track S-row gaps, lane
  /// keys, the strip's cut-local range — all this panel's own selections),
  /// then the standing row — the transition row's one-verb fusion, or a
  /// fresh SE entry on the standing S row's empty cursor frame.
  @override
  bool get canCreateInstance {
    if (session.cellInstances.canCreateInstanceForSelection) {
      return true;
    }
    if (_standingOnTransitionRow) {
      // F-105 (유저 2026-09-15, 「통일 — 편집 버튼은 빈 칸에서 꺼진다」): the ＋
      // creates; opening a covered span is the Edit button's.
      return session.transitions.canCreateTransitionSpanAtPlayhead;
    }
    // D28: on the cut row with a storyboard layer, the ＋ divides the
    // panel under the cursor — the same one-resolver pair the dispatch
    // reads.
    if (session.storyboardCursor.canCreateStoryboardPanelAtCursor) {
      return true;
    }
    return session.storyboardCursor.canCreateSeEntryAtStoryboardCursor;
  }

  /// ⑬/B8 CREATE on this panel: the selection rungs first (this panel's own
  /// selections — the S-row range, a lane span, the strip's cut-local
  /// range), then the standing row. On the transition row the two verbs are
  /// one: `editTransitionSpanInstance` creates on an empty frame and edits
  /// on a covered one (「그게아니라 인스턴스편집버튼으로 작동하도록」); on
  /// an S row the `＋` authors a fresh entry at the cursor.
  ///
  /// ↩️The two verbs are two again (F-105, 유저 2026-09-15 「통일 — 편집
  /// 버튼은 빈 칸에서 꺼진다」 · 「만약 내가 말했던거라면 철회야」): on the
  /// transition row the `＋` creates, as it does on every row.
  ///
  /// Moved here from the host so the frame-`＋` KEY presses what this
  /// panel's button presses (I-19) when the storyboard is the panel being
  /// worked in.
  @override
  void createInstance() {
    if (session.cellInstances.createInstancesForSelection()) {
      return;
    }
    if (_standingOnTransitionRow) {
      session.transitions.createTransitionSpanAtPlayhead();
      return;
    }
    // D28: on the cut row with a storyboard layer, the ＋ divides the
    // panel under the cursor (self-gated by the one cursor resolver).
    if (session.storyboardCursor.canCreateStoryboardPanelAtCursor) {
      session.storyboardCursor.createStoryboardPanelAtCursor();
      return;
    }
    // Self-gated: only a standing S row with an EMPTY cursor frame authors.
    session.storyboardCursor.createSeEntryAtStoryboardCursor();
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
  bool get canSetComma => session.storyboardCursor.canSetCommaForStoryboardCursor;

  @override
  void setComma(int comma) => session.edgeDrag.setCommaForStoryboardCursor(comma);

  /// D40's one resolver (T25): the standing row's whole span on the
  /// track's global axis — a null layerId means the CUT row, whose span is
  /// selected through the one cut-select entry point on the trackId the
  /// row itself names (never [EditorSessionManager.selectedTrackId] — the
  /// stale re-key the select path already removed).
  ({LayerId? layerId, TrackId? trackId, int anchorFrame, int headFrame})?
  get _rowSpanTarget {
    switch (session.storyboardStandingRow) {
      case TrackRowAddress(:final trackId):
        final span = session.rowSpans.trackCutSpan(trackId);
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
        final span = session.rowSpans.trackRowAuthoredSpan(layerId);
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

  /// Which rail is asking: with nothing selected the frame pill's shove
  /// aims at the row THIS rail lights (a cut row shoves cuts, an S row
  /// shoves sounds), which is not the session's active-layer fallback.
  @override
  TimelineRowAddress? get shiftCurrentRow => session.selectedRow;

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
    // as it does in this class's [deleteSubject].
    //
    // The axis here is not the session's: THIS panel's press lands on the
    // STANDING ROW (a track, an S row, a lane, the transition fixture),
    // and a cut-local band never names one of those — so any band at all
    // names rows this press would miss. Without the guard it fell through
    // to the row rung below, where a TrackRowAddress cursor means "rename
    // the cut". Delete and Rename are documented as ONE ladder; splitting
    // them here left the same band dark on one button and aimed at the
    // cut on the other.
    if (session.cells.cellSelectionClaimsSubject) {
      return null;
    }
    switch (session.storyboardStandingRow) {
      case LayerRowAddress(:final layerId)
          when session.isTrackTransitionLayerId(layerId):
        // F-105 (유저 2026-09-15, 「통일 — 편집 버튼은 빈 칸에서 꺼진다」): Edit
        // opens a span covering the playhead; creating is the ＋'s.
        return session.transitions.transitionSpanAt(session.editingGlobalFrame) !=
                null
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
        return session.laneVerbs.canNameLaneKeys
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
  ///
  /// 🚨The cuts rung is a band that NAMES cuts — one over the V row
  /// ([StoryboardRows.storyboardSelectedCutIds]). It used to ask whether
  /// any band was up at all, from when the V row's was the only band this
  /// rail could sweep; once the S rows and the transition row swept bands
  /// of their own, a band over them deleted the cut the session stood in —
  /// a cut the band did not even cover (transition-row-range-in-the-cut,
  /// 2026-09-26).
  @override
  PillSubject get deleteSubject {
    if (session.storyboardRows.storyboardSelectedCutIds.isNotEmpty) {
      return PillSubject.cuts;
    }
    if (session.cells.canDeleteCellForSelection) {
      return PillSubject.cells;
    }
    // A live band claims the press even when it holds nothing this panel
    // may delete — the same guard the strip's comma verb already states.
    // Without it a band the collector refuses fell through to the cursor
    // rung, where a TRACK-ROW cursor means "delete the cut".
    if (_bandClaimsThePress) {
      return PillSubject.nothing;
    }
    return session.storyboardCursor.canDeleteBlockAtStoryboardCursor
        ? PillSubject.cells
        : PillSubject.nothing;
  }

  @override
  void deleteSelectionSubject() {
    if (session.storyboardRows.storyboardSelectedCutIds.isNotEmpty) {
      session.deleteSelectionSubject();
      return;
    }
    if (session.cells.canDeleteCellForSelection) {
      session.cells.deleteCellAtCurrentFrame();
      return;
    }
    if (_bandClaimsThePress) {
      return;
    }
    session.storyboardCursor.deleteBlockAtStoryboardCursor();
  }

  /// A cell band, or one of this rail's own.
  bool get _bandClaimsThePress =>
      session.cells.cellSelectionClaimsSubject ||
      session.trackFrameRangeSelection.value != null;

  /// The cuts this panel's 링크 독립 means: its EDIT TARGET's cuts rung —
  /// the selected cut range, else the cut under the cursor on a track row.
  ///
  /// ★The storyboard's ladder is [editTarget], so the three verbs this
  /// panel resolves for itself cannot disagree about which cut is meant.
  /// 「컷이나」 (I-45) is this panel's only noun for it: a track row's blocks
  /// are cuts, and an S row holds no pictures to link (F-115).
  List<CutId> get _unlinkCutIds {
    if (editTarget is! StoryboardEditCut) {
      return const [];
    }
    if (session.trackFrameRangeSelection.value != null) {
      return session.storyboardRows.storyboardSelectedCutIds;
    }
    final cut = session.activeCutOrNull;
    return cut == null ? const [] : [cut.id];
  }

  @override
  bool get canUnlink => _unlinkCutIds.any(session.cutVerbs.cutIsLinked);

  @override
  void unlink() => session.cutVerbs.unlinkCuts(_unlinkCutIds);
}
