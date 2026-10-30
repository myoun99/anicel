import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../models/brush_frame_key.dart';
import '../../models/canvas_resize_anchor.dart';
import '../../models/canvas_size.dart';
import '../../models/conte/conte_ink_keys.dart'
    show conteInkRowIdOf, conteInkRowKey;
import '../../models/cut.dart';
import '../../models/drawing_guide.dart';
import '../../models/cut_id.dart';
import '../../models/cut_metadata.dart';
import '../../models/envelope/cut_envelope_ink_keys.dart'
    show envelopeInkKeyOfCut;
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../../models/track_id.dart';
import '../../models/timesheet_document.dart' show sheetArtistMark;
import '../../models/timesheet_ink_keys.dart' show timesheetInkKeyOfCut;
import '../../services/brush_frame_store.dart' show BrushFrameStore;
import '../../services/command.dart' show WorkAhead;
import '../../services/commands/convert_to_linked_cut_plan.dart';
import '../../services/commands/link_mirror.dart' show linkedCutSiblings;
import '../../services/persistence/cel_places.dart' show rowOwnerName;
import '../../services/project_lookup.dart' show cutPositionOf;
import '../../services/commands/set_cut_guides_command.dart';
import '../envelope/cut_envelope_builder.dart' show cutEnvelopeInkOwner;
import '../text/place_lines.dart' show drawingPlaceLines;
import 'active_cut_edits.dart';
import 'cut_placement.dart';
import 'independent_clip_mint.dart' show carryBakedPictures, carrySurfaces;
import 'render_caches.dart';
import 'session_roles.dart';
import 'storyboard_rows.dart';

/// The CUT VERBS — creating, deleting, duplicating and renaming
/// the active cut, linking it, resizing its canvas, its note and guides —
/// as their own object. Each is a command over the repository; the session
/// stays the facade that names them.
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
    required StoryboardRows storyboardRows,
    required ActiveCutEdits activeCut,
    required CutPlacement placement,
    required RenderCaches renderCaches,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
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

  /// The cut [createCut] makes when it is told nothing — what the new cut
  /// window offers (I-100): the name the cut takes where it lands, and the
  /// new cut's canvas, A4 200dpi. Null where the ＋ has no place for one.
  Cut? get plannedNewCut {
    final plan = _placement.cutCreationPlan;
    if (plan == null) {
      return null;
    }
    return _project.cutCommandCoordinator.plannedCut(
      trackId: plan.trackId,
      placement: _landingOf(plan),
    );
  }

  /// Makes a cut where the ＋ has its place ([CutPlacement.cutCreationPlan]),
  /// named [name] at [canvasSize] — what the new cut window confirms.
  ///
  /// 🗣️I-100 (유저 2026-10-14): 「새 컷 만들때, 지금 현재컷? 기준으로 크기
  /// 정하는데, 그게아니라 앞으로는 컷 만들기 버튼 누르면 컷 생성창 열려서,
  /// 거기서 이름(기본값 넣어줌), 캔버스 사이즈(기본값 a4 200dpi) 정하도록.
  /// 거기서 정한값으로 만들어짐」. ↩️A new cut took the active cut's canvas,
  /// as new scenes in TVPaint/Clip Studio take the project's.
  void createCut({String? name, CanvasSize? canvasSize}) {
    final plan = _placement.cutCreationPlan;
    if (plan == null) {
      return;
    }
    _project.cutCommandCoordinator.createCut(
      trackId: plan.trackId,
      canvasSize: canvasSize,
      placement: _landingOf(plan),
      name: name,
    );
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

  static ({int? index, int leadingGapFrames, int? duration})? _landingOf(
    ({TrackId trackId, int? index, int leadingGapFrames, int? duration}) plan,
  ) => plan.index == null
      ? null
      : (
          index: plan.index,
          leadingGapFrames: plan.leadingGapFrames,
          duration: plan.duration,
        );

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

  /// What [resizeActiveCutCanvas] will make of the pictures kept in files,
  /// worked out ahead on the machine's workers — what its wait window holds
  /// up first.
  Future<void> resizeActiveCutCanvasAhead(
    CanvasSize canvasSize, {
    CanvasResizeAnchor anchor = CanvasResizeAnchor.center,
    void Function(double done)? report,
  }) => _activeCut.aheadOfActiveCut(
    (cutId) => _project.cutCommandCoordinator.resizeCutCanvasAhead(
      cutId: cutId,
      canvasSize: canvasSize,
      anchor: anchor,
      report: report,
    ),
  );

  /// The active cut's canvas at [canvasSize], the picture moved by
  /// [contentOffset] — what a canvas adjusted on the canvas lands (I-79).
  void placeActiveCutCanvas(
    CanvasSize canvasSize, {
    required ({double dx, double dy}) contentOffset,
  }) => _activeCut.onActiveCut(
    (cutId) => _project.cutCommandCoordinator.placeCutCanvas(
      cutId: cutId,
      canvasSize: canvasSize,
      contentOffset: contentOffset,
    ),
  );

  /// What [placeActiveCutCanvas] will make of the pictures kept in files,
  /// worked out ahead on the machine's workers — what its wait window holds
  /// up first.
  Future<void> placeActiveCutCanvasAhead(
    CanvasSize canvasSize, {
    required ({double dx, double dy}) contentOffset,
    void Function(double done)? report,
  }) => _activeCut.aheadOfActiveCut(
    (cutId) => _project.cutCommandCoordinator.placeCutCanvasAhead(
      cutId: cutId,
      canvasSize: canvasSize,
      contentOffset: contentOffset,
      report: report,
    ),
  );

  /// ⑰'s law, applied to 복제: the selected cuts, else the cut you stand
  /// on — copied as ONE block right after the last of them, in the order
  /// they stand, in ONE undo, standing on the last copy.
  ///
  /// 🗣️F-455-Q1 (유저 2026-10-23): 「선택한 컷 전부」 — 「레이어랑 똑같이
  /// 선택한 묶음 뒤에 차례로」. The cut you stand on is a block of one and
  /// goes the same way (CLAUDE.md 절대명령 2: no law split by how much is
  /// selected). ↩️It copied the active cut alone, onto the track's end.
  void duplicateActiveCut() => _activeCut.onActiveCut((cutId) {
    // The selection is a band's cuts, in track order.
    final chosen = _storyboardRows.storyboardSelectedCutIds;
    final block = chosen.isEmpty ? [cutId] : chosen;
    final last = cutPositionOf(
      _project.repository.requireProject(),
      block.last,
    );
    if (last == null) {
      return;
    }
    _project.historyManager.runAsOneStep('Duplicate cuts', () {
      for (final (offset, source) in block.indexed) {
        _duplicateCut(
          source,
          last.trackId,
          index: last.cutIndex + 1 + offset,
        );
      }
    });
  });

  /// Duplicates [cutId] into [trackId] at [index], pictures and all: the
  /// copy mints every row and cel afresh, and a picture lives under its
  /// cel's key, so each one follows its cel over (F-62's law at the cut's
  /// scale). ↩️Nothing did until 2026-09-26 — a duplicated cut came out
  /// with every drawing blank (measured; card
  /// `duplicates-lose-their-pictures`).
  void _duplicateCut(CutId cutId, TrackId trackId, {required int index}) {
    final source = _project.cutById(cutId)!;
    final copy = _project.cutCommandCoordinator.duplicateCut(
      sourceCutId: cutId,
      targetTrackId: trackId,
      index: index,
    );
    final into = _project.cutById(copy.cutId)!;
    final store = _renderCaches.brushFrameStore;
    for (final row in source.layers) {
      carryBakedPictures(
        project: _project,
        store: store,
        cut: into,
        to: copy.rows[row.id]!,
        minted: {for (final cel in row.frames) cel.id: copy.minted[cel.id]!},
        pictureOf: (cel) => store.bakedSurfaceOrNull(
          _project.brushFrameKeyForCut(source, row.id, cel),
        ),
      );
    }
    _carrySheetInk(from: cutId, to: copy.cutId);
  }

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
  /// sibling, so it owns its own.
  void _carrySheetInk({required CutId from, required CutId to}) {
    void carry(
      BrushFrameStore store,
      CutId owner,
      BrushFrameKey? Function(BrushFrameKey key) inCopy,
    ) => carrySurfaces(
      sources: store.bakedSurfacesForCut(owner).entries,
      surfaceOf: (written) => written.value,
      keyOfCopy: (written) => inCopy(written.key),
      keep: (key, surface, _) => store.storeBakedSurface(key, surface),
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
    carry(
      _renderCaches.timesheetInkStore,
      from,
      (key) => timesheetInkKeyOfCut(key, to),
    );
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

  /// The active cut's memo on page [page] of its timesheet (F-301).
  String? activeCutNoteOf(int page) =>
      _project.activeCutOrNull?.metadata.noteOf(page);

  /// Names [cutId]'s [stage] worker — the one a paper's box prints: the
  /// timesheet's name box the 러프원화 ([sheetArtistMark]), an envelope's
  /// staff box its own stage (I-127-Q1) — on it and its 겸용 siblings, as
  /// 컷 설정 names a stage (I-112: the box and the setting are one name).
  /// The cut is the one the paper prints (I-127). A name changes no cut's
  /// shape, so — as there — the repaint is the whole of the reaction.
  void setCutStaffName(CutId cutId, LayerMark stage, String name) =>
      _activeCut.onCutQuietly(
        cutId,
        (cutId) => _project.cutCommandCoordinator.setCutStaffNames(
          cutIds: [cutId],
          names: {stage: name},
        ),
      );

  /// [cutId]'s scene, typed into the box a paper prints it in (F-291).
  void setCutScene(CutId cutId, String scene) => _activeCut.onCutQuietly(
    cutId,
    (cutId) =>
        _project.cutCommandCoordinator.setCutScene(cutId: cutId, scene: scene),
  );

  void updateActiveCutNote({required int page, required String note}) =>
      _activeCut.onActiveCut((cutId) => _writeNote(cutId, page, note));

  /// [cutId]'s memo on page [page] of its timesheet — the cut the paper
  /// prints (I-127).
  void updateCutNote({
    required CutId cutId,
    required int page,
    required String note,
  }) => _activeCut.onCut(cutId, (cutId) => _writeNote(cutId, page, note));

  void _writeNote(CutId cutId, int page, String note) =>
      _project.cutCommandCoordinator.updateCutNote(
        cutId: cutId,
        page: page,
        note: note,
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

  /// The first addressed cut's metadata — its own staff names and the folds
  /// 컷 설정 opens on, what that window shows, as the cut button shows the
  /// first addressed cut's 색 라벨 — or null with no cut to address, so the
  /// window stands down (the gap state).
  CutMetadata? get addressedCutMetadata {
    final cutIds = addressedCutIds;
    return cutIds.isEmpty ? null : _project.cutById(cutIds.first)?.metadata;
  }

  /// Names each stage of [names] on every addressed cut — and on each one's
  /// 겸용 siblings — and opens [openFolds] on every addressed cut's own, as
  /// ONE undo step; every other stage keeps each cut's own (컷 설정's save).
  void setAddressedCutStaff(
    Map<LayerMark, String> names, {
    Set<LayerProcess>? openFolds,
  }) {
    final cutIds = addressedCutIds;
    if (cutIds.isEmpty) {
      return;
    }
    _project.cutCommandCoordinator.setCutStaffNames(
      cutIds: cutIds,
      names: names,
      openFolds: openFolds,
    );
    _changes.notifyChanged();
  }

  /// The active cut named [newName] — and put in [scene] where one is given,
  /// as the cut rename window gives it (F-291) — as ONE undo step.
  void renameActiveCut(String newName, {String? scene}) =>
      _activeCut.onActiveCut(
        (cutId) => _project.cutCommandCoordinator.nameCut(
          cutId: cutId,
          name: newName,
          scene: scene,
        ),
      );

  /// Names each cut of [names] — ONE undo step. 자동 이름 지정's cuts (I-18,
  /// targets-Q4 「컷마다 따로 연번」): every cut takes a number of its own, a
  /// 겸용 cut too — a name does not travel along a link.
  void renameCuts(Map<CutId, String> names) {
    _project.cutCommandCoordinator.renameCuts(names);
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
  }

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

  /// Which guide the guide tool is editing.
  ///
  /// UI state, like the active layer — the CUT stores the guides, not which
  /// one is under the hand. It lives here rather than in a widget because
  /// two of them need it (the tool panels and the canvas overlay), and two
  /// copies of a selection are two answers waiting to disagree. (It moved
  /// here from the session with the guides it points into — the audit's
  /// twentieth family, 2026-09-29.)
  GuideId? get selectedGuideId => _selectedGuideId;
  GuideId? _selectedGuideId;

  set selectedGuideId(GuideId? id) {
    if (_selectedGuideId == id) return;
    _selectedGuideId = id;
    _changes.notifyChanged();
  }

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
      replacedDrawings: [
        for (final MapEntry(key: layerId, value: frames)
            in plan.replacedFrames.entries)
          ...drawingPlaceLines(
            project,
            layerId,
            frames,
            framePlace: _project.framePlaceLabel,
          ),
      ],
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

  /// What [convertActiveCutToLinked] works out ahead — the active cut's
  /// canvas taken by [targetCutId]
  /// ([CutCommandCoordinator.convertCutToLinkedAhead]); null when nothing.
  WorkAhead? convertActiveCutToLinkedAhead(CutId targetCutId) {
    final originCutId = _timeline.editingSession.activeCutId;
    if (originCutId == null || originCutId == targetCutId) {
      return null;
    }
    return _project.cutCommandCoordinator.convertCutToLinkedAhead(
      originCutId: originCutId,
      targetCutId: targetCutId,
    );
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

  /// The LINKED cuts (겸용 — [linkedCutSiblings]), which wear the link icon
  /// on their blocks (I-25: 「링크컷이 발생해있는 경우, 모든 컷에 적용」).
  Set<CutId> get linkedCutIds {
    final project = _project.repository.requireProject();
    return {
      for (final track in project.tracks)
        for (final cut in track.cuts)
          if (linkedCutSiblings(project, cutId: cut.id).isNotEmpty) cut.id,
    };
  }

  /// The cuts [cutId] is linked with, named as a place line names them — the
  /// link window's list (I-25).
  List<String> linkedCutLines(CutId cutId) {
    final project = _project.repository.requireProject();
    return [
      for (final siblingId in linkedCutSiblings(project, cutId: cutId))
        if (cutPositionOf(project, siblingId) case final position?)
          rowOwnerName(track: position.track, cut: position.cut),
    ];
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
