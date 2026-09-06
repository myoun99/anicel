import '../../controllers/timeline_controller.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart';
import '../timeline/timeline_cell_exposure_state.dart';
import 'session_roles.dart';
import 'camera.dart';

/// The EXPOSURE VERBS — blanking an exposure, lengthening and shortening
/// the selected one, and a layer's exposure state — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
class ExposureVerbs {
  ExposureVerbs({
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required Camera camera,
  }) : _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _camera = camera;

  final Camera _camera;

  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;

  /// The timesheet "X here" action: blanks the covering block's hold so the
  /// current cell (and the rest of the old hold) becomes empty.
  ///
  /// ⛔Renamed off "cut" in T3 — see [blankExposureAtCurrentFrame].
  /// 🚨결정 14 ①ⓑ (유저 확정 2026-08-22) — **X BLANKS EXACTLY THE SWEPT
  /// CELLS.**
  ///
  /// The rows the band names, each with the swept span. The playhead X
  /// truncates a block at the pressed frame; over a band that would blank
  /// PAST the sweep, so the swept cells go empty and the block's tail stays
  /// where it stands (see [TimelineController.blankableSpanInBand]).
  Map<LayerId, ({int start, int endExclusive})> _blankableSpanForSelection() =>
      _selection.bandRowsForSelection(
        _blankable,
        (ids, selection) => _timeline.timelineController.blankableSpanInBand(
          layerIds: ids,
          startIndex: selection.startIndex,
          endExclusive: selection.endIndexExclusive,
        ),
      );

  /// Whether an X can blank [layer]'s exposure at all.
  ///
  /// ⛔ONE PREDICATE FOR THE BAND AND THE PLAYHEAD. SYNCED attach rows have
  /// no timing of their own (the base owns it); free attach rows cut
  /// exposures like any drawing layer (UI-R21 #3). SINGLE-CEL (image) rows
  /// hold one covering block by definition — an X-here would be reverted
  /// by the covering normalization.
  static bool _blankable(Layer layer) =>
      layerKindHoldsDrawings(layer.kind) &&
      !layerKindHoldsSingleCel(layer.kind) &&
      !isSyncedAttachedLayer(layer);

  bool get canBlankExposureForSelection =>
      _blankableSpanForSelection().isNotEmpty;

  bool get canBlankExposureAtCurrentFrame => _selection.bandOrActiveRow(
    canBlankExposureForSelection,
    _blankable,
    (layer) => _timeline.timelineController.canCutExposureAt(
      layer: layer,
      frameIndex: _timeline.timelineController.currentFrameIndex,
    ),
  );

  /// The timesheet "X here" — ⛔NOT the clipboard's cut.
  ///
  /// 🚨T3 rename: this was `cutExposureAtCurrentFrame` while 「잘라내기」 was
  /// a word nothing in the app used. Now that [_internals.cutRunAtCurrentFrame] exists,
  /// two different verbs would answer to "cut". The UI never said 「cut」
  /// here — the button is `×` (`blank-exposure-button`, tooltip `tlBlankX`)
  /// — so the code name follows the button and the new verb takes the word
  /// the user gave it.
  void blankExposureAtCurrentFrame() {
    final banded = _blankableSpanForSelection();
    if (banded.isNotEmpty) {
      _timeline.timelineController.blankSpansForLayers(banded);
      _changes.notifyChanged();
      return;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !canBlankExposureAtCurrentFrame) {
      return;
    }

    _timeline.timelineController.cutExposureForLayer(layerId: layer.id);
    _changes.notifyChanged();
  }

  /// The toolbar +/- buttons are one-frame comma adjustments of the
  /// selected block's end edge (the same op the drag grips use).
  void increaseSelectedExposure() => _shiftSelectedExposureEnd(1);

  void decreaseSelectedExposure() => _shiftSelectedExposureEnd(-1);

  void _shiftSelectedExposureEnd(int delta) {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return;
    }
    final block = _timeline.timelineController.blockForLayerAt(layer: layer);
    if (block == null) {
      return;
    }

    _timeline.timelineController.shiftExposureEdge(
      layerId: layer.id,
      blockStartIndex: block.startIndex,
      edge: TimelineBlockEdge.end,
      delta: delta,
    );
    _changes.notifyChanged();
  }

  TimelineCellExposureState exposureStateForLayer(Layer layer, int frameIndex) {
    if (layerKindGroupsLayers(layer.kind)) {
      // R10: a folder row is a CELLS row whose coverage is the subtree
      // union, carried by its band clone's own timeline. HELD, never
      // drawingStart — a held cell prints no glyph, so the band stays
      // nameless (L5) without touching the shared marker table, and the
      // block chrome still wraps the whole merged run because the segment
      // rule bounds on coverage rather than on starts.
      return coveringDrawingBlockAt(layer.timeline, frameIndex) != null
          ? TimelineCellExposureState.held
          : TimelineCellExposureState.uncovered;
    }
    if (layer.kind == LayerKind.camera) {
      // The camera row's cells mirror [activeCutCameraTrack] — the ONE
      // preview-aware answer (lane move, block ride, or committed), the
      // same track the member lanes and the union markers read (B4), so
      // the row follows any drag while the repository stays untouched.
      return _camera.activeCutCameraTrack?.keyframeAt(frameIndex) != null
          ? TimelineCellExposureState.drawingStart
          : TimelineCellExposureState.uncovered;
    }

    if (_timeline.timelineController.isDrawingStartForLayer(
      layer: layer,
      frameIndex: frameIndex,
    )) {
      return TimelineCellExposureState.drawingStart;
    }

    final held = _timeline.timelineController.isHeldExposureForLayer(
      layer: layer,
      frameIndex: frameIndex,
    );
    // Block-owned dots live on held cells only (offsets 1..length-1), so
    // markUncovered is never produced anymore — the enum value survives
    // solely for exhaustive switches over legacy-visual states.
    if (held &&
        _timeline.timelineController.hasMarkAt(
          layer: layer,
          frameIndex: frameIndex,
        )) {
      return TimelineCellExposureState.markHeld;
    }
    return held
        ? TimelineCellExposureState.held
        : TimelineCellExposureState.uncovered;
  }

  bool get canDecreaseSelectedExposure {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return false;
    }
    final block = _timeline.timelineController.blockForLayerAt(layer: layer);
    return block != null && block.length > 1;
  }

  bool get canIncreaseSelectedExposure {
    final layer = _selection.activeLayer;
    if (layer == null) {
      return false;
    }
    return _timeline.timelineController.blockForLayerAt(layer: layer) != null;
  }
}
