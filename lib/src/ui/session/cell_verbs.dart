import '../../models/attached_layer_resolve.dart';
import '../../models/brush_frame_key.dart';
import '../../models/layer_folder.dart';
import '../../models/layer.dart';
import '../../models/pixel_verb_subject.dart';
import '../../services/cel_pixel_overwrite.dart';
import '../../services/cel_pixel_region.dart';
import '../../services/commands/cel_pixel_overwrite_command.dart';
import '../timeline/timeline_cell_exposure_state.dart';
import 'session_roles.dart';
import 'lane_verbs.dart';
import 'range_selections.dart';
import 'frame_clipboard.dart';

/// The CELL VERBS — deleting the cell under the cursor or the selection,
/// the status text a cell shows, and the pixel verbs (the keys they act
/// on, whether one may run, running it) — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
class CellVerbs {
  CellVerbs({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required LaneVerbs laneVerbs,
    required RangeSelections rangeSelections,
    required FrameClipboard clipboard,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _internals = internals,
       _laneVerbs = laneVerbs,
       _rangeSelections = rangeSelections,
       _clipboard = clipboard;

  final FrameClipboard _clipboard;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final LaneVerbs _laneVerbs;
  final RangeSelections _rangeSelections;

  /// The cels a pixel verb would touch: a live frame range's whole block, or
  /// the one cel you are standing on.
  ///
  /// ⛔No row-selection rung. Selecting rows says which rows are selected, not
  /// 「recolour all of their drawings」 — 유저 2026-08-26: 「내가 비슷한얘기
  /// 옛날에 했다가 폐기했어」. A frame range is different in kind: it is drawn
  /// across the cels themselves.
  List<BrushFrameKey> pixelVerbCellKeys() {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    final byId = {for (final layer in _project.layers) layer.id: layer};
    final keys = <BrushFrameKey>[];
    // ⛔NO DEDUPE HERE. `CelPixelOverwriteCommand.execute` already skips a cel
    // it has done, keyed by `frameStore.canonicalKeyOf` — which is the RIGHT
    // key, because it resolves links, and mine could only compare
    // (layer, frame) ids. Two mechanisms for one invariant is the shape the
    // F-20 bug came in; the one that owns the surfaces owns this.
    void take(Layer layer, int? frameIndex) {
      // 🚨HIDDEN ROWS ARE NOT TOUCHED. 유저 2026-08-27: 「해당 두 버튼은
      // 비지블이 on인 레이어만 활성화되야함. **기본적으로 그림 조작하는건
      // 그런느낌인거지**」 — the reason is general, so it is stated as the
      // general thing: a pixel verb acts on what you can see.
      //
      // ⛔The row's own eye flag is NOT that question. It is half of it; the
      // other half is whether a folder above the row is switched off, and
      // `rowVisible` is the one door that folds both. Ratcheted by
      // `hidden_folder_is_hidden_test`, which caught this line reading the
      // raw flag — ⚠️and counts it in COMMENTS too, so the flag's name
      // cannot be written here even to say not to use it.
      if (!layerAcceptsBrushInput(layer) || !cut.layers.rowVisible(layer)) {
        return;
      }
      final frame = _timeline.timelineController.resolveFrameForLayer(
        layer: layer,
        frameIndex: frameIndex,
      );
      if (frame == null) {
        return;
      }
      final key = _internals.brushFrameKeyForCut(cut, layer.id, frame.id);
      // 🚨AND IT HAS TO HAVE A DRAWING IN IT. 유저 2026-08-27: 「색변환은
      // 레이어에 그림이 존재 해야 활성화시키는게 맞고. 픽셀삭제는 그림이
      // 있어야 활성화시키는게 맞고」.
      //
      // ⛔A frame EXISTING is not a drawing existing, and that gap is the
      // whole bug: 픽셀 비우기 leaves the frame and its tiles in place with
      // every alpha at zero, so this walk kept naming a cel with nothing in
      // it and the buttons stayed lit over an empty block. This is the same
      // question the block's tint asks, which is why it is that call and not
      // a second rule of its own.
      if (!_internals.brushFrameStore.celHasRenderableContent(key)) {
        return;
      }
      keys.add(key);
    }

    final range = _selection.frameRangeSelection.value;
    if (range != null) {
      final rows = range.layerIds.isEmpty ? [range.layerId] : range.layerIds;
      for (final layerId in rows) {
        final layer = byId[layerId];
        if (layer == null) {
          continue;
        }
        for (var i = range.startIndex; i < range.endIndexExclusive; i++) {
          take(layer, i);
        }
      }
      return keys;
    }
    // The playhead rung reads the ACTIVE layer, which F-20 (#1216) made the
    // one answer — a stored verb row naming a different layer is stale.
    final activeId = _selection.activeLayerId;
    final active = activeId == null ? null : byId[activeId];
    if (active != null) {
      take(active, null);
    }
    return keys;
  }

  /// Whether a pixel verb has anything to do — the buttons' gate, and the
  /// same question the press runs (T25: one answer behind both).
  bool get canRunPixelVerb =>
      _internals.pixelEditingCoordinator != null &&
      _internals.pixelVerbSubject != PixelVerbSubject.nothing;

  /// 색 변환 (`CelPixelChannel.colour`) and 픽셀 비우기 (`.alpha`) — one
  /// operation with the channel swapped, which is why they are one method.
  ///
  /// 🚨The colour's ALPHA is ignored, RGB only (유저 확정): 「알파만 남기고
  /// 색을 그대로 바꿔버리는거야. 그냥 진짜 색을 변환. 해당색으로. **문답무용**」.
  /// ⛔Do not ask whether turning a painted cel into a silhouette is alright —
  /// that IS the wanted behaviour, and the user said so having used it in
  /// TVPaint for years.
  ///
  /// One undo step across every cel, however many the ladder named.
  void runPixelVerb(CelPixelVerb verb) {
    final coordinator = _internals.pixelEditingCoordinator;
    if (coordinator == null) {
      return;
    }
    final keys = pixelVerbCellKeys();
    if (keys.isEmpty) {
      return;
    }
    // 🚨THE SPACE AXIS, and it is one law for every cel the ladder named:
    // 「선택 있으면 그 영역, 없으면 전체(페이스트보드 포함)」 — said three
    // times now across ③·⑤·색 변환, so it is a law and not a preference.
    final region = _internals.pixelSelectionRegion?.call();
    final size = _project.requireActiveCut.canvasSize;
    final frameIndex = _selection.currentFrameIndex;
    final byId = {for (final layer in _project.layers) layer.id: layer};
    final targets = <CelPixelTarget>[];
    for (final key in keys) {
      final layer = byId[key.layerId];
      targets.add(
        CelPixelTarget(
          key: key,
          // ⚠️Mapped into each layer's OWN artwork space: a posed layer draws
          // its pixels somewhere else than the marquee was drawn, and the
          // region has to follow. An unposed layer — the overwhelming
          // majority — gets it back unchanged.
          region: region == null || layer == null
              ? region
              : regionInArtworkSpace(
                  region: region,
                  pose: _timeline.layerPoseAtFrame(layer, frameIndex),
                  canvasSize: size,
                ),
        ),
      );
    }
    _project.historyManager.execute(
      CelPixelOverwriteCommand.forVerb(
        coordinator: coordinator,
        targets: targets,
        verb: verb,
        // 🚨WITHOUT THIS THE CANVAS DOES NOT REDRAW. The sink is optional on
        // `restoreSurfaceSnapshot`, and omitting it silently falls to a
        // no-op — the pixels change, every cache keeps serving the old
        // composite, and the edit appears only after leaving the frame and
        // coming back. 유저 2026-08-27: 「버튼 누르면 작동은하는데 캔버스쪽에서
        // 라이브로 갱신안되서 다른 프레임 갔다가 와야 반영되있어. 이런 캔버스
        // 조작은 바로바로 반영되야지」.
        cacheInvalidationSink: _internals.cacheInvalidationHub,
        // Read at the MOMENT OF THE PRESS — the bar does not hold the brush
        // colour, it asks for it. ⛔The fallback is the brush's own default,
        // not white or transparent: a press with no publisher wired must
        // still do the thing the user asked for, in the colour they would
        // have got.
        argb: _internals.pixelBrushColour?.call() ?? 0xFF000000,
      ),
    );
  }

  bool get hasActiveNonNegativeCell {
    return _selection.activeLayer != null &&
        _timeline.timelineController.currentFrameIndex >= 0;
  }

  /// The SELECTION-borne rungs of the cell delete, alone (B8): lane keys
  /// under the lane-verb context, or a live selection's real blocks —
  /// either axis. [deleteCellAtCurrentFrame] dispatches both before it ever
  /// asks the active layer, so a caller gated on THIS can hand the press to
  /// that verb without the active-layer rung becoming reachable.
  bool get canDeleteCellForSelection =>
      // R10 #19: the same rule Add follows — when the subject is a PROPERTY
      // row, Delete removes its keys, not a cel. It also closes a gap the
      // other way round: a live LANE span used to fall through to the cell
      // path and delete the active layer's cel instead of the keys under it.
      _laneVerbs.laneVerbRangeHasKeys ||
      // A live selection is deletable wherever the playhead stands (UI-R17
      // #2).
      _rangeSelections.selectionBlockStartsByLayer() != null;

  /// Whether a live CELL band owns the next cell-verb press.
  ///
  /// A band is a subject claim, not a hint: the row the user swept is the
  /// row the verb acts on, and a band holding nothing this verb may touch
  /// makes the press a NO-OP — never a redirect onto whatever row happens
  /// to be active (a cell drag never moves the active layer, so those are
  /// routinely different rows).
  ///
  /// This is what keeps the collector's `null` from meaning two things.
  /// It answers "no band at all"; the collector answers "nothing in the
  /// band is editable". Reading only the collector let a refused band
  /// fall through and delete an unselected row's drawing.
  bool get cellSelectionClaimsSubject =>
      _selection.frameRangeSelection.value != null;

  bool get canDeleteCellAtCurrentFrame {
    if (canDeleteCellForSelection) {
      return true;
    }
    if (cellSelectionClaimsSubject) {
      return false;
    }
    final layer = _selection.activeLayer;
    // SYNCED attach rows: cel removal is out of v1 scope (delete the row
    // or undo the creation) — cells are display material there. Free
    // attach rows delete cells like normal (UI-R21 #3).
    //
    // SINGLE-CEL (image) rows: the one picture IS the row (its cel is
    // born with it and there is no empty state in its world), so the row
    // is what you delete. Without this the button lit and did nothing —
    // the covering normalization rebuilt the cel from the same write, so
    // the press only cost a phantom undo entry (D22).
    if (layer == null ||
        isSyncedAttachedLayer(layer) ||
        layer.kind.holdsSingleCel) {
      return false;
    }

    return _timeline.timelineController.canDeleteCellAt(
      layer: layer,
      frameIndex: _timeline.timelineController.currentFrameIndex,
    );
  }

  void deleteCellAtCurrentFrame() {
    // R10 #19: a property row is its own subject — see
    // [canDeleteCellAtCurrentFrame].
    final lane = _laneVerbs.laneVerbRange;
    if (lane != null && _laneVerbs.removeLaneKeysForSelection(lane)) {
      return;
    }
    // A live selection routes the delete to EVERY selected block on
    // EVERY spanned layer (UI-R17 #2/#8, one composite undo); the
    // leftover selection covers empty cells so it clears with the delete.
    final selectionTargets = _rangeSelections.selectionBlockStartsByLayer();
    if (selectionTargets != null) {
      _timeline.timelineController.deleteBlocksForLayers(selectionTargets);
      // Whichever axis answered: the leftover span covers empty cells now.
      _selection.clearFrameRangeSelection();
      _selection.clearStoryboardCutSelection();
      _changes.notifyChanged();
      return;
    }
    if (cellSelectionClaimsSubject) {
      // The band holds nothing this verb may delete — that is a no-op,
      // not a licence to edit whatever row is active.
      return;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !canDeleteCellAtCurrentFrame) {
      return;
    }

    _timeline.timelineController.deleteCellForLayer(layerId: layer.id);
    _changes.notifyChanged();
  }

  String get currentCellStatusText {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return 'Cell: No layer';
    }

    return 'Cell: ${_cellStatusLabelForLayer(layer)}';
  }

  String get compactCellActionText {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return 'No layer';
    }

    final frameIndex = _timeline.timelineController.currentFrameIndex;
    final exposureState = _timeline.exposureStateForLayer(layer, frameIndex);
    final canPaste = _clipboard.canPasteLinkedFrameAtCurrentFrame;

    switch (exposureState) {
      case TimelineCellExposureState.drawingStart:
        return 'Drawing: Copy / Rename / Delete';
      case TimelineCellExposureState.held:
        return canPaste
            ? 'Held: Paste / Copy / Rename / Mark'
            : 'Held: Copy / Rename / Mark';
      case TimelineCellExposureState.markHeld:
        return canPaste
            ? 'Held + ●: Paste / Copy / Rename / Mark'
            : 'Held + ●: Copy / Rename / Mark';
      case TimelineCellExposureState.uncovered:
        // Dots are block-owned: an empty cell offers no Mark (author an
        // unnamed frame first).
        return canPaste ? 'X: Paste / New Frame' : 'X: New Frame';
      case TimelineCellExposureState.markUncovered:
        return canPaste
            ? 'X + ●: Paste / New Frame / Mark'
            : 'X + ●: New Frame / Mark';
    }
  }

  String _cellStatusLabelForLayer(Layer layer) {
    final frameIndex = _timeline.timelineController.currentFrameIndex;
    final exposureState = _timeline.exposureStateForLayer(layer, frameIndex);
    return switch (exposureState) {
      TimelineCellExposureState.drawingStart =>
        _internals.drawingStartStatusForLayer(layer, frameIndex),
      TimelineCellExposureState.held => 'Held drawing',
      TimelineCellExposureState.markHeld => 'Held drawing + Mark ●',
      TimelineCellExposureState.uncovered => 'Empty (X)',
      TimelineCellExposureState.markUncovered => 'Empty (X) + Mark ●',
    };
  }
}
