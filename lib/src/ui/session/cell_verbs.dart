import '../../models/attached_layer_resolve.dart';
import '../../models/brush_frame_key.dart';
import '../../models/frame.dart' show inbetweenMark;
import '../../models/layer_folder.dart';
import '../../models/layer.dart';
import '../../models/layer_kind.dart';
import '../../models/pixel_verb_subject.dart';
import '../../services/cel_pixel_overwrite.dart';
import '../../services/cel_pixel_region.dart';
import '../../services/cut_frame_composite_plan.dart' show layerPlacementAt;
import '../../services/layer_pose_matrix.dart' show LayerPoseSample;
import '../../services/commands/cel_pixel_overwrite_command.dart';
import '../timeline/timeline_cell_exposure_state.dart';
import 'render_caches.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import '../../services/canvas_selection.dart' show SelectionMaskOptions;
import '../../services/canvas_selection_region.dart';
import 'lane_verbs.dart';
import 'range_selections.dart';
import 'frame_clipboard.dart';
import 'transitions.dart';

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
    required ActiveCutControllers controllers,
    required SessionInternals internals,
    required RenderCaches renderCaches,
    required LaneVerbs laneVerbs,
    required RangeSelections rangeSelections,
    required FrameClipboard clipboard,
    required Transitions transitions,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _controllers = controllers,
       _internals = internals,
       _renderCaches = renderCaches,
       _laneVerbs = laneVerbs,
       _rangeSelections = rangeSelections,
       _clipboard = clipboard,
       _transitions = transitions;

  final FrameClipboard _clipboard;
  final Transitions _transitions;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final ActiveCutControllers _controllers;
  final SessionInternals _internals;
  final RenderCaches _renderCaches;
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
      final frame = _controllers.timelineController.resolveFrameForLayer(
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
      if (!_renderCaches.brushFrameStore.celHasRenderableContent(key)) {
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
    // Read ONCE, at the moment of the press — see [PixelVerbCanvas].
    final canvas = _internals.pixelVerbCanvas?.call();
    _project.historyManager.execute(
      CelPixelOverwriteCommand.forVerb(
        coordinator: coordinator,
        targets: _targetsFor(keys, canvas?.region),
        verb: verb,
        // 🚨WITHOUT THIS THE CANVAS DOES NOT REDRAW. The sink is optional on
        // `restoreSurfaceSnapshot`, and omitting it silently falls to a
        // no-op — the pixels change, every cache keeps serving the old
        // composite, and the edit appears only after leaving the frame and
        // coming back. 유저 2026-08-27: 「버튼 누르면 작동은하는데 캔버스쪽에서
        // 라이브로 갱신안되서 다른 프레임 갔다가 와야 반영되있어. 이런 캔버스
        // 조작은 바로바로 반영되야지」.
        cacheInvalidationSink: _renderCaches.cacheInvalidationHub,
        // Read at the MOMENT OF THE PRESS — the bar does not hold the brush
        // colour, it asks for it. ⛔The fallback is the brush's own default,
        // not white or transparent: a press with no publisher wired must
        // still do the thing the user asked for, in the colour they would
        // have got.
        argb: canvas?.argb ?? 0xFF000000,
        // 🚨THE SELECTION'S SOFTNESS TRAVELS WITH IT. A Ctrl+T lift on the
        // same marquee already honoured 확장·페더·AA and these four verbs
        // did not, so one outline meant two things. Read at the press for
        // the same reason the colour is (the panel can change it while the
        // popover is open). ⛔The fallback is `none`, which is also every
        // option's own default — a host with nothing wired behaves exactly
        // as it did. 유저 확정 2026-09-09 (`pixel-verbs-mask-options` = 가).
        options:
            canvas?.mask ?? SelectionMaskOptions.none,
      ),
    );
  }

  /// Where [key]'s row stands on the canvas at the frame you stand on — the
  /// placement the stack PAINTS it with ([layerPlacementAt]) — or null for
  /// an unplaced row, or a key on no row of the open cut.
  ///
  /// ⛔ONE ANSWER for every verb that restates a canvas outline on the cels a
  /// range names: the pixel verbs ([_targetsFor]) and the other cels a
  /// transform's confirm lands on (a-marquee-on-a-posed-row ④ — each cel
  /// crosses through its OWN row's placement, not the standing row's). The
  /// raw track value read before missed the anchor, the fx switch and every
  /// folder above the row.
  LayerPoseSample? placementOf(BrushFrameKey key) {
    final cut = _project.activeCutOrNull;
    final layer = cut?.layers.byId(key.layerId);
    if (cut == null || layer == null) {
      return null;
    }
    return layerPlacementAt(
      cut: cut,
      layer: layer,
      frameIndex: _selection.currentFrameIndex,
    );
  }

  /// The cels a press names, each carrying the marquee restated in its own
  /// layer's artwork space.
  ///
  /// 🚨THE SPACE AXIS, and it is one law for every cel the ladder named:
  /// 「선택 있으면 그 영역, 없으면 전체(페이스트보드 포함)」 — said three
  /// times now across ③·⑤·색 변환, so it is a law and not a preference.
  List<CelPixelTarget> _targetsFor(
    List<BrushFrameKey> keys,
    CanvasSelectionRegion? region,
  ) {
    final cut = _project.requireActiveCut;
    // ⚠️Mapped into each layer's OWN artwork space: a posed layer draws its
    // pixels somewhere else than the marquee was drawn, and the region has
    // to follow. An unposed layer — the overwhelming majority — gets it
    // back unchanged.
    CanvasSelectionRegion? onLayer(BrushFrameKey key) {
      if (region == null) {
        return region;
      }
      final placement = placementOf(key);
      return regionInArtworkSpace(
        region: region,
        pose: placement?.pose,
        anchorPoint: placement?.anchorPoint,
        canvasSize: cut.canvasSize,
      );
    }

    return [
      for (final key in keys) CelPixelTarget(key: key, region: onLayer(key)),
    ];
  }

  bool get hasActiveNonNegativeCell {
    return _selection.activeLayer != null &&
        _controllers.timelineController.currentFrameIndex >= 0;
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
      // F-87: keys, or a live range naming an fx header (which removes the
      // effect).
      _laneVerbs.laneVerbRangeHasSomethingToDelete ||
      // A live selection is deletable wherever the playhead stands (UI-R17
      // #2) — its blocks, and the transition spans it holds
      // (transition-row-range-in-the-cut).
      _rangeSelections.selectionBlockStartsByLayer() != null ||
      _transitions.selectionTransitionStartsByRow() != null;

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
    // 🚨F-87 (유저 2026-09-12: 「트랜스폼 헤더에 서있으면 … 키가 없을때
    // 삭제하면 레이어의 프레임이 삭제됨. 이런거 없도록」): a LANE row claims
    // the press the way a cell band does — with nothing on it this press may
    // take, the answer is nothing, never the cel of the layer the lane
    // belongs to (R10 #19 made the row its own subject; this rung had not
    // heard).
    if (_laneVerbs.laneVerbRange != null) {
      return false;
    }
    if (cellSelectionClaimsSubject) {
      return false;
    }
    final layer = _selection.activeLayer;
    // The transition row deletes the span its mark SHOWS, on the global row
    // (transition-row-open-in-the-cut) — its cells are a projection, which
    // no cut-local cel verb may read as its own. An O.L's mark is not the
    // cut's to delete (유저 2026-09-26).
    if (layer?.kind == LayerKind.transition) {
      return _transitions.transitionSpanStartEditableInCutAt(
            _controllers.timelineController.currentFrameIndex,
          ) !=
          null;
    }
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

    return _controllers.timelineController.canDeleteCellAt(
      layer: layer,
      frameIndex: _controllers.timelineController.currentFrameIndex,
    );
  }

  void deleteCellAtCurrentFrame() {
    // R10 #19: a property row is its own subject — see
    // [canDeleteCellAtCurrentFrame].
    final lane = _laneVerbs.laneVerbRange;
    // F-87: the lane row takes the whole press — an fx header's range removes
    // the effect, other lanes lose their keys, and nothing falls through to
    // the cel below when there is nothing to take.
    if (lane != null) {
      _laneVerbs.deleteForLaneSelection(lane);
      return;
    }
    // A live selection routes the delete to EVERY selected block on
    // EVERY spanned layer (UI-R17 #2/#8) and to the transition spans it
    // holds, in one composite undo; the leftover selection covers empty
    // cells so it clears with the delete.
    final selectionTargets = _rangeSelections.selectionBlockStartsByLayer();
    final transitionTargets = _transitions.selectionTransitionStartsByRow();
    if (selectionTargets != null || transitionTargets != null) {
      _project.historyManager.runAsOneStep('Delete selected cells', () {
        if (selectionTargets != null) {
          _controllers.timelineController.deleteBlocksForLayers(
            selectionTargets,
          );
        }
        if (transitionTargets != null) {
          _transitions.removeTransitionSpans(transitionTargets);
        }
      });
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
    if (layer.kind == LayerKind.transition) {
      final start = _transitions.transitionSpanStartEditableInCutAt(
        _controllers.timelineController.currentFrameIndex,
      );
      if (start != null) {
        _transitions.removeTransitionSpanAt(start);
      }
      return;
    }

    _controllers.timelineController.deleteCellForLayer(layerId: layer.id);
    _changes.notifyChanged();
  }

  // --- 링크 독립 (I-45): the frame-axis rung --------------------------------

  /// The runs a frame-axis 링크 독립 press means, one per row.
  ///
  /// ★DELETE'S TARGETS from the same press, read through the same claims
  /// (유저 2026-09-23: 「다른 편집버튼등의 로직 그대로 … 선택안하면
  /// 현재프레임, 선택하면 해당 선택한 소재가 기준」): a LANE row claims the
  /// press and has no cels (F-87); a band means every block it touches on
  /// every row it spans ([RangeSelections.selectionBlockStartsByLayer]); a
  /// band that touches none claims the press with nothing in it; with no
  /// band, the block under the playhead on the active row.
  ///
  /// ⚠️A row's blocks become ONE run, first start to last end — the band is
  /// contiguous, so everything between them is the band's too.
  List<UnlinkRun> _unlinkRuns() {
    if (_laneVerbs.laneVerbRange != null) {
      return const [];
    }
    final byLayer = _rangeSelections.selectionBlockStartsByLayer();
    if (byLayer == null) {
      if (cellSelectionClaimsSubject) {
        return const [];
      }
      final layer = _selection.activeLayer;
      if (layer == null || !rowHoldsLinks(layer)) {
        return const [];
      }
      final run = _controllers.timelineController.runAtPlayheadForLayer(
        layer.id,
      );
      return [(layer: layer, index: run.index, count: run.count)];
    }
    final runs = <UnlinkRun>[];
    for (final MapEntry(key: layerId, value: starts) in byLayer.entries) {
      final layer = _project.rangeLayerById(layerId);
      if (layer == null || !rowHoldsLinks(layer) || starts.isEmpty) {
        continue;
      }
      final first = starts.reduce((a, b) => a < b ? a : b);
      final last = starts.reduce((a, b) => a > b ? a : b);
      final end = last + (layer.timeline[last]?.length ?? 1);
      runs.add((layer: layer, index: first, count: end - first));
    }
    return runs;
  }

  /// Whether the frame axis holds a cel this press would give a copy of its
  /// own — the rung's gate, from the same runs its press takes.
  bool get canUnlinkCells =>
      _clipboard.sharedCelsIn(_unlinkRuns()).isNotEmpty;

  /// 링크 독립 on the frame axis ([FrameClipboard.unlinkRuns]).
  void unlinkCells() => _clipboard.unlinkRuns(_unlinkRuns());

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

    final frameIndex = _controllers.timelineController.currentFrameIndex;
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
            ? 'Held + $inbetweenMark: Paste / Copy / Rename / Mark'
            : 'Held + $inbetweenMark: Copy / Rename / Mark';
      case TimelineCellExposureState.uncovered:
        // Dots are block-owned: an empty cell offers no Mark (author an
        // unnamed frame first).
        return canPaste ? 'X: Paste / New Frame' : 'X: New Frame';
      case TimelineCellExposureState.markUncovered:
        return canPaste
            ? 'X + $inbetweenMark: Paste / New Frame / Mark'
            : 'X + $inbetweenMark: New Frame / Mark';
    }
  }

  String _cellStatusLabelForLayer(Layer layer) {
    final frameIndex = _controllers.timelineController.currentFrameIndex;
    final exposureState = _timeline.exposureStateForLayer(layer, frameIndex);
    return switch (exposureState) {
      TimelineCellExposureState.drawingStart =>
        _internals.drawingStartStatusForLayer(layer, frameIndex),
      TimelineCellExposureState.held => 'Held drawing',
      TimelineCellExposureState.markHeld =>
        'Held drawing + Mark $inbetweenMark',
      TimelineCellExposureState.uncovered => 'Empty (X)',
      TimelineCellExposureState.markUncovered =>
        'Empty (X) + Mark $inbetweenMark',
    };
  }
}
