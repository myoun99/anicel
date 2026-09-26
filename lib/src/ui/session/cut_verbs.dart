import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../models/brush_frame_key.dart';
import '../../models/canvas_resize_anchor.dart';
import '../../models/canvas_size.dart';
import '../../models/conte/conte_ink_keys.dart'
    show conteInkRowIdOf, conteInkRowKey;
import '../../models/cut.dart';
import '../../models/drawing_guide.dart';
import '../../models/cut_id.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart'
    show envelopeInkKeyOfCut;
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../../models/timesheet_ink_keys.dart' show timesheetInkKeyOfCut;
import '../../services/brush_frame_store.dart' show BrushFrameStore;
import '../../services/commands/convert_to_linked_cut_plan.dart';
import '../../services/project_lookup.dart' show cutPositionOf;
import '../../services/commands/set_cut_guides_command.dart';
import '../../services/commands/cut_reorder_planner.dart';
import '../envelope/cut_envelope_builder.dart' show cutEnvelopeInkOwner;
import 'active_cut_controllers.dart';
import 'active_cut_edits.dart';
import 'cut_placement.dart';
import 'independent_clip_mint.dart' show carryBakedPictures, carrySurfaces;
import 'render_caches.dart';
import 'session_roles.dart';
import 'storyboard_rows.dart';

/// The CUT VERBS — creating, deleting, duplicating, renaming and moving
/// the active cut, linking it, resizing its canvas, its note, guides and
/// thumbnail frame — as their own object. Each is a command over the
/// repository; the session stays the facade that names them.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: nothing of its own and twelve
/// session members touched; the rest reads none of it. It names the
/// roles it needs in its constructor.
class CutVerbs {
  CutVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required StoryboardRows storyboardRows,
    required ActiveCutEdits activeCut,
    required CutPlacement placement,
    required RenderCaches renderCaches,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _controllers = controllers,
       _internals = internals,
       _storyboardRows = storyboardRows,
       _activeCut = activeCut,
       _placement = placement,
       _renderCaches = renderCaches;

  /// Where a duplicated cut's pictures are, and go.
  final RenderCaches _renderCaches;

  final ActiveCutEdits _activeCut;

  final CutPlacement _placement;

  final StoryboardRows _storyboardRows;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;

  void createCut() {
    final plan = _placement.cutCreationPlan;
    if (plan == null) {
      return;
    }
    _project.cutCommandCoordinator.createCut(
      trackId: plan.trackId,
      // New cuts inherit the active cut's canvas size, like new scenes in
      // TVPaint/Clip Studio inherit the project size.
      canvasSize: _project.activeCutOrNull?.canvasSize,
      placement: plan.index == null
          ? null
          : (
              index: plan.index,
              leadingGapFrames: plan.leadingGapFrames,
              duration: plan.duration,
            ),
    );
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  void resizeActiveCutCanvas(
    CanvasSize canvasSize, {
    CanvasResizeAnchor anchor = CanvasResizeAnchor.center,
  }) => _activeCut.onActiveCut(
    (cutId) => _project.cutCommandCoordinator.resizeCutCanvas(
      cutId: cutId,
      canvasSize: canvasSize,
      anchor: anchor,
    ),
  );

  /// Duplicates the active cut, pictures and all: the copy mints every row
  /// and cel afresh, and a picture lives under its cel's key, so each one
  /// follows its cel over (F-62's law at the cut's scale). ↩️Nothing did
  /// until 2026-09-26 — a duplicated cut came out with every drawing blank
  /// (measured; card `duplicates-lose-their-pictures`).
  void duplicateActiveCut() => _activeCut.onActiveCut((cutId) {
    final source = _project.requireActiveCut;
    final copy = _project.cutCommandCoordinator.duplicateCut(
      sourceCutId: cutId,
      targetTrackId: _selection.selectedTrackId,
    );
    final into = _project.cutById(copy.cutId)!;
    final store = _renderCaches.brushFrameStore;
    for (final row in source.layers) {
      carryBakedPictures(
        internals: _internals,
        store: store,
        cut: into,
        to: copy.rows[row.id]!,
        minted: {for (final cel in row.frames) cel.id: copy.minted[cel.id]!},
        pictureOf: (cel) => store.bakedSurfaceOrNull(
          _internals.brushFrameKeyForCut(source, row.id, cel),
        ),
      );
    }
    _carrySheetInk(from: cutId, to: copy.cutId);
  });

  /// The sheets' handwriting of a duplicated cut, onto its copy: the conte
  /// cells' block by block — each copied block keeps its handwriting id, on
  /// the copy's cut — the envelope's and the timesheet's box by box and band
  /// by band. From there the copy's is its own.
  ///
  /// 🗣️유저 2026-09-26 (cut-duplicate-sheet-ink-Q1): 「따라간다 — 복제는
  /// 전부 복사」. Each sheet's ink is owned the way the load prunes it
  /// (`_InkOwners`): a conte cell by its block, the others by their cut —
  /// the envelope's by the cut that OWNS the envelope, the representative
  /// when [from] shares one ([cutEnvelopeInkOwner]); the copy is no
  /// sibling, so it owns its own. The conte's paper plane belongs to no cut
  /// and stays where it is.
  void _carrySheetInk({required CutId from, required CutId to}) {
    void carry(
      BrushFrameStore store,
      CutId owner,
      BrushFrameKey? Function(BrushFrameKey key) inCopy,
    ) => carrySurfaces(
      store: store,
      sources: store.bakedSurfacesForCut(owner).entries,
      surfaceOf: (written) => written.value,
      keyOfCopy: (written) => inCopy(written.key),
    );

    carry(_renderCaches.conteInkRowStore, from, (key) {
      final block = conteInkRowIdOf(key);
      return block == null ? null : conteInkRowKey(to, block);
    });
    carry(
      _renderCaches.envelopeInkStore,
      cutEnvelopeInkOwner(_project.repository.requireProject(), from),
      (key) => envelopeInkKeyOfCut(key, to),
    );
    for (final store in [
      _renderCaches.timesheetInkStripStore,
      _renderCaches.timesheetInkPageStore,
    ]) {
      carry(store, from, (key) => timesheetInkKeyOfCut(key, to));
    }
  }

  void deleteActiveCut() {
    // With a cut RANGE selection live, the delete command acts on the
    // whole run instead of the active cut (UI-R18 #1).
    if (_storyboardRows.storyboardSelectedCutIds.isNotEmpty) {
      deleteSelectedCuts();
      return;
    }
    _activeCut.onActiveCut(
      (cutId) => _project.cutCommandCoordinator.deleteCut(cutId: cutId),
    );
  }

  CutPosition? get _activeCutPositionOrNull {
    final cutId = _timeline.editingSession.activeCutId;
    if (cutId == null) {
      return null;
    }
    return cutPositionOf(_project.repository.requireProject(), cutId);
  }

  CutPosition get _activeCutPosition {
    final position = _activeCutPositionOrNull;
    if (position == null) {
      throw StateError(
        'Active Cut not found: ${_timeline.editingSession.activeCutId}',
      );
    }
    return position;
  }

  bool get canMoveActiveCutLeft => _canMoveActiveCut(CutMoveDirection.left);

  bool get canMoveActiveCutRight => _canMoveActiveCut(CutMoveDirection.right);

  void moveActiveCutLeft() => _moveActiveCut(CutMoveDirection.left);

  void moveActiveCutRight() => _moveActiveCut(CutMoveDirection.right);

  bool _canMoveActiveCut(CutMoveDirection direction) {
    final position = _activeCutPositionOrNull;
    return position != null &&
        _internals.cutReorderPlanner.canMove(position, direction);
  }

  /// ⛔ONE MOVE, WITH A SIGN. The two verbs used to be written out, guard
  /// and command and refresh each, so a step that stopped refreshing after
  /// the reorder would have done it in one direction only.
  void _moveActiveCut(CutMoveDirection direction) {
    final position = _activeCutPosition;
    if (!_internals.cutReorderPlanner.canMove(position, direction)) {
      return;
    }
    _project.cutCommandCoordinator.reorderCut(
      trackId: position.trackId,
      cutId: position.cutId,
      newIndex: _internals.cutReorderPlanner.moveTargetIndex(
        position,
        direction,
      ),
    );
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  String? get activeCutNote => _project.activeCutOrNull?.metadata.note;

  void updateActiveCutNote(String note) => _activeCut.onActiveCut(
    (cutId) =>
        _project.cutCommandCoordinator.updateCutNote(cutId: cutId, note: note),
  );

  /// The cuts a pick in the cut button is about: the ones the storyboard's
  /// range covers, or — with no range up — the active cut. ONE list either
  /// way, so the pick runs the same code with or without a selection (유저
  /// 2026-09-26: 「선택범위 한상태로 조작가능한거 물론이고」).
  List<CutId> get addressedCutIds {
    final selected = _storyboardRows.storyboardSelectedCutIds;
    if (selected.isNotEmpty) {
      return selected;
    }
    final active = _timeline.editingSession.activeCutId;
    return active == null ? const [] : [active];
  }

  /// The 색 라벨 the cut button shows: the first addressed cut's.
  LayerMark get addressedCutMark {
    final cutIds = addressedCutIds;
    return cutIds.isEmpty
        ? LayerMark.none
        : _project.cutById(cutIds.first)?.metadata.mark ?? LayerMark.none;
  }

  /// Sets the 색 라벨 of every addressed cut — and of each one's 겸용
  /// siblings — as ONE undo step. A label changes no cut's shape, so the
  /// repaint is the whole of the reaction.
  void setAddressedCutMark(LayerMark mark) {
    final cutIds = addressedCutIds;
    if (cutIds.isEmpty) {
      return;
    }
    _project.cutCommandCoordinator.setCutMark(cutIds: cutIds, mark: mark);
    _changes.notifyChanged();
  }

  /// Whether the active cut's storyboard thumbnail is pinned to the
  /// playhead frame (drives the toolbar toggle's state).
  bool get isActiveCutThumbnailPinnedHere =>
      _project.activeCutOrNull?.metadata.thumbnailFrameIndex ==
          _controllers.timelineController.currentFrameIndex &&
      _project.activeCutOrNull?.metadata.thumbnailFrameIndex != null;

  /// Pins the active cut's storyboard thumbnail to the playhead frame, or
  /// releases the pin back to the first frame when pressed on the pinned
  /// frame itself (toggle; one undo step either way).
  void toggleActiveCutThumbnailFrame() {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return;
    }
    final frame = _controllers.timelineController.currentFrameIndex;
    final pinned = cut.metadata.thumbnailFrameIndex;
    _project.cutCommandCoordinator.updateCutThumbnailFrame(
      cutId: cut.id,
      frameIndex: pinned == frame ? null : frame,
    );
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  void renameActiveCut(String newName) => _activeCut.onActiveCut(
    (cutId) => _project.cutCommandCoordinator.renameCut(
      cutId: cutId,
      newName: newName,
    ),
  );

  /// The active cut's drawing guides — empty when parked in a gap.
  ///
  /// ⛔What is WRITTEN: what the brush snaps to and what is saved. A drag in
  /// flight is not in it ([activeCutGuidesForDisplay]) — two questions, two
  /// getters.
  CutGuides get activeCutGuides =>
      _project.activeCutOrNull?.guides ?? CutGuides.empty;

  /// 🚨★★★THE GUIDE DRAG IN FLIGHT — shown, not written.
  ///
  /// 유저 (guide-sym): 「대칭자나 퍼스자 등 해당 자에 대한 위치이동 등 **편집도
  /// 전부 언두 기록**」. 🧪Measured, it was the opposite of a missing entry:
  /// ONE drag of the settings panel's line-count slider pushed ELEVEN,
  /// because every sample committed.
  ///
  /// ★The law the canvas's handle layer already kept and the opacity bars
  /// keep (`OpacityVerbs`): a drag PREVIEWS and a release COMMITS. The
  /// handle layer's preview lived in the canvas area's own State, so the
  /// panel — another subtree — had nowhere to preview to and committed
  /// instead. It is here now, one of it, for both.
  final ValueNotifier<CutGuides?> guidesDragPreview =
      ValueNotifier<CutGuides?>(null);

  /// What the guides look like right now, a drag in flight included — what
  /// the overlay draws and nothing else reads.
  CutGuides get activeCutGuidesForDisplay =>
      guidesDragPreview.value ?? activeCutGuides;

  /// Shows [guides] without writing anything: a drag in flight.
  void previewActiveCutGuides(CutGuides guides) =>
      guidesDragPreview.value = guides;

  /// Writes the active cut's guides, fanning out to its 겸용 siblings in one
  /// undoable step (see [SetCutGuidesCommand]).
  ///
  /// A drag calls this once, at release; its samples went to
  /// [previewActiveCutGuides].
  void setActiveCutGuides(CutGuides guides) {
    // ⚠️The preview goes either way — also when the drag ended on the value
    // it began from and nothing is written: left up, it would pin the
    // canvas to a picture nothing ever replaces.
    guidesDragPreview.value = null;
    final cut = _project.activeCutOrNull;
    if (cut == null || cut.guides == guides) {
      return;
    }
    _project.historyManager.execute(
      SetCutGuidesCommand(
        repository: _project.repository,
        cutId: cut.id,
        guides: guides,
      ),
    );
    _changes.notifyChanged();
  }

  /// 겸용컷 생성: a new cut whose drawing layers are all LINKED to the
  /// active cut's (empty timelines — same pictures, own timing).
  void createLinkedCutFromActiveCut() => _activeCut.onActiveCut(
    (cutId) =>
        _project.cutCommandCoordinator.createLinkedCut(sourceCutId: cutId),
  );

  /// 겸용 변경 preview: what linking the active cut with [targetCutId]
  /// would do (drives the confirmation dialog's 안내문). Null when there
  /// is no active cut or the target is the active cut itself.
  ConvertToLinkedCutPlan? convertToLinkedCutPreview(CutId targetCutId) {
    final originCutId = _timeline.editingSession.activeCutId;
    if (originCutId == null || originCutId == targetCutId) {
      return null;
    }
    return _project.cutCommandCoordinator.convertToLinkedCutPreview(
      originCutId: originCutId,
      targetCutId: targetCutId,
    );
  }

  /// Cuts the active cut can 겸용-convert WITH (every other cut, all
  /// tracks — dialog picker data).
  List<({CutId id, String name})> get convertToLinkedCutCandidates {
    final activeCutId = _timeline.editingSession.activeCutId;
    if (activeCutId == null) {
      return const [];
    }
    return [
      for (final track in _project.repository.requireProject().tracks)
        for (final cut in track.cuts)
          if (cut.id != activeCutId) (id: cut.id, name: cut.name),
    ];
  }

  /// [convertToLinkedCutPreview] resolved to display strings for the
  /// 안내문 dialog. Null under the preview's own null conditions.
  ConvertToLinkedCutPreviewData? convertToLinkedCutPreviewData(
    CutId targetCutId,
  ) {
    final plan = convertToLinkedCutPreview(targetCutId);
    final originCut = _project.activeCutOrNull;
    if (plan == null || originCut == null) {
      return null;
    }
    final project = _project.repository.requireProject();
    final targetCut = cutPositionOf(project, targetCutId)?.cut;
    if (targetCut == null) {
      return null;
    }
    String layerName(Cut cut, LayerId layerId) =>
        cut.layers.firstWhere((layer) => layer.id == layerId).name;
    return ConvertToLinkedCutPreviewData(
      targetCutName: targetCut.name,
      linkingLayerNames: [
        for (final pair in plan.layerPairs)
          layerName(originCut, pair.originLayerId),
      ],
      layerNamesAppearingInTarget: [
        for (final id in plan.originOnlyLayerIds) layerName(originCut, id),
      ],
      layerNamesAppearingInOrigin: [
        for (final id in plan.targetOnlyLayerIds) layerName(targetCut, id),
      ],
      replacedFrameCount: plan.replacedFrameCount,
      joiningFrameCount: plan.joiningFrameCount,
      linksAnything: plan.linksAnything,
      canvasSizesDiffer: originCut.canvasSize != targetCut.canvasSize,
    );
  }

  /// 겸용 변경: links the active cut (origin — 원본 승리) with
  /// [targetCutId]. Callers confirm through the preview dialog first.
  void convertActiveCutToLinked(CutId targetCutId) {
    final originCutId = _timeline.editingSession.activeCutId;
    if (originCutId == null || originCutId == targetCutId) {
      return;
    }
    _project.cutCommandCoordinator.convertCutToLinked(
      originCutId: originCutId,
      targetCutId: targetCutId,
    );
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  /// Whether the selection can delete: cuts selected AND at least one
  /// cut survives (the project never empties).
  bool get canDeleteSelectedCuts {
    // ★The selection needs no filtering for cuts that still EXIST:
    // [StoryboardRows.storyboardSelectedCutIds] reads the CURRENT layout,
    // so a cut another command deleted since the drag painted the range
    // is simply not in it.
    final selection = _storyboardRows.storyboardSelectedCutIds;
    if (selection.isEmpty) {
      return false;
    }
    var total = 0;
    for (final track in _project.repository.requireProject().tracks) {
      total += track.cuts.length;
    }
    return total > selection.length;
  }

  /// Deletes every selected cut as ONE undo step (UI-R18 #1: the cut
  /// delete button acts on the selection).
  void deleteSelectedCuts() {
    if (!canDeleteSelectedCuts) {
      return;
    }
    _project.cutCommandCoordinator.deleteCuts(
      cutIds: _storyboardRows.storyboardSelectedCutIds,
    );
    _selection.clearStoryboardCutSelection();
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  /// Whether any row of [cutId] shares its pictures through a link — what
  /// the link-independent button asks of a cut (I-45: 「프레임 독립시키거나
  /// 레이어나 컷이나」).
  bool cutIsLinked(CutId cutId) {
    final cut = _project.cutById(cutId);
    if (cut == null) {
      return false;
    }
    final registry = _project.repository.requireProject().linkRegistry;
    return cut.layers.any(
      (layer) => registry.isLinked(cutId: cutId, layerId: layer.id),
    );
  }

  /// 독립시키기 for every linked row of every cut in [cutIds] — ONE undo
  /// step. A row's whole attach group forks at once, so the members after it
  /// find nothing left and stand down (the coordinator's own guard).
  void unlinkCuts(Iterable<CutId> cutIds) {
    final linked = [
      for (final cutId in cutIds)
        if (cutIsLinked(cutId)) cutId,
    ];
    if (linked.isEmpty) {
      return;
    }
    _project.historyManager.runAsOneStep('Unlink cuts', () {
      for (final cutId in linked) {
        final layers = _project.cutById(cutId)?.layers ?? const [];
        for (final layer in layers) {
          _project.cutCommandCoordinator.unlinkLayer(
            cutId: cutId,
            layerId: layer.id,
          );
        }
      }
    });
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  /// Releases the guide drag preview; the session's teardown calls it.
  void dispose() => guidesDragPreview.dispose();
}
