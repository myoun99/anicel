import '../../models/attached_layer_resolve.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/pill_subject.dart';
import '../../models/timeline_frame_range.dart';
import '../../services/command.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'camera.dart';
import 'instructions.dart';
import 'lane_verbs.dart';
import 'layer_verbs.dart';
import 'track_se_display.dart';
import 'frame_verbs.dart';
import 'cell_verbs.dart';

/// The CELL INSTANCES — creating instances for a selection, whether the
/// active cell holds one, and the subject an instance edit acts on — as
/// their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
class CellInstances {
  CellInstances({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required FrameIds frameIds,
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required Camera camera,
    required Instructions instructionVerbs,
    required LaneVerbs laneVerbs,
    required LayerVerbs layerVerbs,
    required TrackSeDisplay trackSe,
    required FrameVerbs frameVerbs,
    required CellVerbs cells,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _internals = internals,
       _camera = camera,
       _instructionVerbs = instructionVerbs,
       _laneVerbs = laneVerbs,
       _layerVerbs = layerVerbs,
       _trackSe = trackSe,
       _frameVerbs = frameVerbs,
       _cells = cells;

  final FrameVerbs _frameVerbs;
  final CellVerbs _cells;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;
  final Camera _camera;
  final Instructions _instructionVerbs;
  final LaneVerbs _laneVerbs;
  final LayerVerbs _layerVerbs;
  final TrackSeDisplay _trackSe;

  /// UI-R25 #3: Add with a LIVE selection fills the WHOLE selection —
  /// wherever creation is possible, kind by kind (the rule: anywhere
  /// selectable creates). Returns true when a selection owned the press.
  ///
  /// - Cell selection: every spanned row fills its EMPTY gaps inside the
  ///   range — drawing/SE/direction rows with a new cel per gap (exposure =
  ///   gap, ONE undo across all rows; on a direction row each is a span of
  ///   the vocabulary's first entry, R27), the camera row with a pose key
  ///   frozen on every unkeyed frame (one undo).
  /// - Lane selection: the lane freezes a key on every unkeyed frame of
  ///   the range (one undo) — the navigator toggle's range form.
  bool createInstancesForSelection() {
    // #16 — THE TRACK RANGE SPEAKS FIRST, like it does for delete and
    // edit (유저: 「스토리보드패널에서 S행의 프레임생성이 안됨」). The S-row
    // drag writes trackFrameRangeSelection and its claim CLEARS the
    // cut-local selection this verb used to read, so creation fell
    // through to the stale active layer — the wrong row entirely. The
    // ladder rung was simply missing.
    final trackRange = _selection.trackFrameRangeSelection.value;
    if (trackRange != null &&
        _trackSe.createTrackSeEntriesForRange(trackRange)) {
      return true;
    }
    // R10 #19: a live lane SPAN, or the property row you are STANDING on
    // as a one-frame span at the playhead — one verb either way, which is
    // what makes a group HEADER key its whole member set and an effect
    // lane key its chain without a second code path (the user's
    // "카메라레이어랑 같은 동작이지? 로직 통일화해서").
    final lane = _laneVerbs.laneVerbRange;
    if (lane != null) {
      _laneVerbs.createLaneKeysForSelection(lane);
      return true;
    }
    final selection = _selection.frameRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final displayById = {for (final layer in _project.layers) layer.id: layer};
    final fills =
        <
          LayerId,
          List<({int startIndex, int length, FrameId frameId, String? name})>
        >{};
    // R26 #1: every row of the selection composes into ONE undo step.
    // Camera goes FIRST — its undo restores a whole-project snapshot, so it
    // must be the last command undone (CompositeCommand undoes in reverse).
    final cameraCommands = <Command>[];
    for (final layerId in selection.spanLayerIds) {
      final layer = displayById[layerId];
      if (layer == null) {
        continue;
      }
      if (layer.kind == LayerKind.camera) {
        final command = _camera.cameraKeysCommandForRange(selection);
        if (command != null) {
          cameraCommands.add(command);
        }
        continue;
      }
      // A direction row fills its gaps the way every cel row does: its
      // spans are its blocks (R27), and a bare one takes the ＋'s span at
      // the write — so it had no branch of its own to keep.
      final layerFills = _authoredFillsFor(layer, selection);
      if (layerFills.isNotEmpty) {
        fills[layer.id] = layerFills;
      }
    }
    final commands = <Command>[
      ...cameraCommands,
      if (fills.isNotEmpty)
        ..._controllers.timelineController.drawingFramesCommandsForLayers(
          fills,
        ),
    ];
    if (commands.isNotEmpty) {
      _project.historyManager.execute(
        commands.length == 1
            ? commands.single
            : CompositeCommand(
                description: 'Create selected cells',
                commands: commands,
              ),
      );
      if (cameraCommands.isNotEmpty) {
        _changes.refreshAfterCutCommand();
      }
    }
    _changes.notifyChanged();
    return true;
  }

  /// The blank cels [selection] authors on [layer]: one per empty gap,
  /// each with a fresh frame id — none on a row that takes no authored
  /// cels, a synced mirror, or a covering row.
  List<({int startIndex, int length, FrameId frameId, String? name})>
  _authoredFillsFor(Layer layer, TimelineFrameRangeSelection selection) {
    if (!layer.kind.takesAuthoredCels || isSyncedAttachedLayer(layer)) {
      return const []; // Synced mirrors follow their base; nothing to author.
    }
    // R9 #9: a COVERING row is one cel edge to edge — there is no "add a
    // frame" in its world, so a selection that happens to span it must
    // pass over it rather than author into it. Until now nothing happened
    // by luck (the covering normalization leaves no empty gap to fill),
    // and #1 is about to put folders — and so their image members — into
    // range selections on purpose. Say it instead of relying on it.
    if (layer.kind.coversWithoutGaps) {
      return const [];
    }
    final layerFills =
        <({int startIndex, int length, FrameId frameId, String? name})>[];
    for (final gap in _internals.emptyGapsInRange(layer, selection)) {
      layerFills.add((
        startIndex: gap.startIndex,
        length: gap.length,
        frameId: _frameIds.mintFrameId(layer.id),
        name: null,
      ));
    }
    return layerFills;
  }

  /// #16 — creation on the TRACK axis: the S rows the range names get one
  /// blank dialogue entry per uncovered run, in one undo step. Returns
  /// false when the range names no track SE row (a cut-row range is the
  /// cut pill's business, #18) — the verb then falls down its ladder.
  ///
  /// Track SE timelines are GLOBAL-keyed, and the fills carry explicit
  /// indexes, so no cut-start lens is involved — the same reason the
  /// storyboard could never reach these rows through the cut-local
  /// selection object.
  /// #17 잔여 — THE CREATE BUTTON'S ONE SENTENCE (T25). Mirrors
  /// [createActiveInstance]'s ladder rung for rung: the selection rungs
  /// first (track S rows → lane span → cut-local range), then the
  /// current-frame capability the kind dispatch actually has.
  ///
  /// The toolbar used to keep its OWN switch, and it disagreed with the
  /// dispatch in both directions: it did not know the selection rungs
  /// (the S-row range #16 just taught the verb), and its `_ => true` arm
  /// lit the button on folder/adjustment/transition rows whose dispatch
  /// is a documented no-op — the #18 lie, one pill over.
  bool get canCreateInstance {
    if (canCreateInstanceForSelection) {
      return true;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !_cells.hasActiveNonNegativeCell) {
      return false;
    }
    return switch (layer.kind) {
      LayerKind.se => _frameVerbs.canCreateDrawingAtCurrentFrame,
      // F-107 (유저 2026-09-12): 「콘티레이어에선 불가능한 버튼 비활성화 …
      // 그 외도 있나 확인」. These rows' press is
      // [EditorSessionManager.createDrawingAtCurrentFrame], which refuses a
      // block's FIRST cell (nothing there to divide) and a picture row whose
      // one cel exists (D22) — the catch-all lit the ＋ over both.
      LayerKind.animation ||
      LayerKind.storyboard ||
      LayerKind.image => _frameVerbs.canCreateDrawingAtCurrentFrame,
      LayerKind.folder || LayerKind.adjustment || LayerKind.transition => false,
      _ => true,
    };
  }

  /// 🚨★★★I-9: whether the ACTIVE CELL already holds something.
  ///
  /// 유저 확정 2026-08-29 (I-9-Q2 = `all-kinds`): 「빈 칸 더블클릭 = 만들기」
  /// on EVERY row kind, each through the create verb it already has. So one
  /// gesture carries two meanings, and this is the fork: an empty cell
  /// CREATES ([createActiveInstance]), a filled one OPENS its editor.
  ///
  /// ⚠️Deliberately NOT [canCreateInstance] and not `!canCreate…`. Those
  /// ask 「is there room to make one」, which on a drawing row is true on a
  /// FILLED cell too (an exposure can always be cut). This asks the only
  /// question the fork needs: 「is something here」.
  ///
  /// The switch is exhaustive on purpose — a new [LayerKind] stops the
  /// compiler here rather than silently landing in a default arm, which is
  /// the guard that keeps this and [createActiveInstance] from drifting.
  bool get activeCellHoldsAnInstance {
    final layer = _selection.activeLayer;
    if (layer == null || !_cells.hasActiveNonNegativeCell) {
      // No cell at all is not an empty cell: there is nowhere to create.
      return true;
    }
    final frameIndex = _controllers.timelineController.currentFrameIndex;
    return switch (layer.kind) {
      LayerKind.camera =>
        _project.activeCutOrNull?.camera.keyframeAt(frameIndex) != null,
      LayerKind.instruction =>
        _instructionVerbs.instructionSpanAt(layer.id, frameIndex) != null,
      // ⛔Read-only inside a cut and nothing to author on a row that holds
      // no cel of its own: reporting FULL keeps the fork from offering a
      // creation their own verbs already refuse.
      LayerKind.transition || LayerKind.folder || LayerKind.adjustment => true,
      LayerKind.se ||
      LayerKind.animation ||
      LayerKind.storyboard ||
      LayerKind.image => _selection.selectedFrame != null,
    };
  }

  /// The SELECTION rungs of [canCreateInstance], alone — the panel-shared
  /// half (B8). [createInstancesForSelection] is their dispatch, rung for
  /// rung; the storyboard's toolbar context reads THIS and then asks its
  /// own standing row, where the timeline falls to the active layer.
  bool get canCreateInstanceForSelection {
    final trackRange = _selection.trackFrameRangeSelection.value;
    if (trackRange != null &&
        _trackSe.trackSeCreationGaps(trackRange).isNotEmpty) {
      return true;
    }
    if (_laneVerbs.laneVerbRange != null) {
      return true;
    }
    return _selection.frameRangeSelection.value != null;
  }

  /// 🚨T25 — whether the CELL under the playhead has an instance editor.
  ///
  /// ⚠️Kind-aware, because 「인스턴스」 is not one thing: a drawing cell's is
  /// its NAME, a camera or direction cell's is the key/event dialog, an SE
  /// cell's is the entry — or the creation of one. This lived in the
  /// toolbar as a private getter while the button was hard-wired to cells;
  /// [editInstanceSubject] asked [_frameVerbs.canRenameFrameAtCurrentFrame] instead, and
  /// the two disagreed for every non-drawing kind. The button stayed lit and
  /// the press did nothing, which is the worst of the three possible
  /// answers. One question, one getter.
  ///
  /// ⛔The HOST's answer is deliberately not folded in: the storyboard's
  /// standing row is separate state from its drawing target (유저
  /// 2026-07-27), so no session getter can see it.
  bool get canEditCellInstanceAtCurrentFrame {
    // A live band CLAIMS this press exactly as it claims Delete's — the
    // two are documented as ONE ladder ([editInstanceSubject]), so a band
    // that leaves Delete with nothing must not leave Rename pointed at
    // the active row instead. There is no selection-wide rename to route
    // to, so a claiming band whose rows hold no editable block simply
    // ends the ladder.
    if (_selection.bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = _selection.activeLayer;
    if (layer == null) {
      return false;
    }
    // Standing on a LANE row, the instance is that lane's KEY — which the
    // owning layer's kind cannot answer. A lane cell with no key has none;
    // the camera row answers here too, being its transform header (F-17).
    if (_laneVerbs.laneVerbRange != null) {
      return _laneVerbs.canNameLaneKeys;
    }
    return switch (layer.kind) {
      // Reached only under a band that holds more than the camera: the band
      // claims the press as cells, and a camera cell's own instance is its
      // key, answered above.
      LayerKind.camera => false,
      // 🚨F-105 (유저 2026-09-12: 「se행만 현재 인덱스 비어있을때 편집버튼이
      // 활성화되는데다가, 누르면 프레임이 생김. 대체 누가 이딴거
      // 만들라했는지? 기존 로직대로 법 통일하고 삭제」): the button EDITS what
      // the cell holds. These two lit on an EMPTY cell — the SE row because a
      // drawing COULD be created there, the direction row on any cell — and
      // their editors created. Creating is the double tap's fork (I-9) and
      // the ＋'s ([createActiveInstance]), never this button's.
      LayerKind.instruction || LayerKind.se =>
        _cells.hasActiveNonNegativeCell && activeCellHoldsAnInstance,
      _ => _frameVerbs.canRenameFrameAtCurrentFrame,
    };
  }

  /// 🚨T25 — WHAT the one Edit Instance button would rename right now.
  ///
  /// 유저 확정 2026-08-14: 「인스턴스 편집 버튼도 공통버튼으로 이동. 그래서
  /// **선택범위 통해 동사통일화** 가능하게.」
  ///
  /// ★The shared pill's ONE ladder ([pillSubjectOn]) — this verb supplies
  /// only what its rungs may rename.
  PillSubject get editInstanceSubject =>
      editInstanceSubjectFor(cutsAreThisPanels: true);

  /// [editInstanceSubject], asked of a PANEL.
  ///
  /// 🚨R5q1 (유저 2026-08-25, 답 1번): 「삭제·편집도 패널을 따라 대상을
  /// 바꾼다 — 스토리보드에서는 스토리보드의 것을, 타임라인에서는 타임라인의
  /// 것을 지운다」, matching the law D28 already gave 커서·코마·＋.
  ///
  /// ⚠️This narrows ⑰ (2026-08-12), which said the verb asks WHAT IS
  /// SELECTED and never which button was pressed. It still does — what the
  /// panel decides is which selections are ITS nouns, and CUTS are the
  /// storyboard's. The two later rulings (D28, then this) win on the
  /// repo's own tie-break: 확정이 둘이면 나중 것이 이긴다.
  PillSubject editInstanceSubjectFor({required bool cutsAreThisPanels}) =>
      pillSubjectOn(
        cuts:
            cutsAreThisPanels &&
            _selection.trackFrameRangeSelection.value != null,
        layers: () => _layerVerbs.renameableSelectedLayerIds().isNotEmpty,
        cells: () => canEditCellInstanceAtCurrentFrame,
      );
}
