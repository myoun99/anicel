import '../../models/composite_tree.dart';
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../brush/brush_editor_selection.dart';
import '../canvas/canvas_layer_stack_view.dart';
import 'active_cut_controllers.dart';
import 'editing_stack_map.dart';
import 'opacity_verbs.dart';
import 'session_roles.dart';
import 'track_se_display.dart';

/// THE EDITING CANVAS AT THE PLAYHEAD: what it draws, and which cel the
/// brush is allowed to touch inside it.
///
/// One subject, because one law answers both. [layerAcceptsBrushInput]
/// decides whether the active row stands in the tree as a live surface or
/// composites read-only as a cached image ([EditingStackMap]) — and the
/// SAME predicate decides whether [activeBrushEditorSelection] hands the
/// brush a target at all. Asking it in two objects is how the canvas would
/// come to draw a live row nothing could draw on.
///
/// [rasterizeActiveLayer] is the verb that CHANGES that answer: a media
/// reference has no editable cel until its derived content is baked into
/// ordinary ones.
///
/// A collaborator (round 8, G4-2): it takes the roles it needs plus its
/// siblings, and the session names it — a forwarder on the host would be a
/// second name for the same verb.
class EditingCanvas {
  EditingCanvas({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required ActiveCutControllers controllers,
    required OpacityVerbs opacityVerbs,
    required TrackSeDisplay trackSe,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _internals = internals,
       _controllers = controllers,
       _opacityVerbs = opacityVerbs,
       _trackSe = trackSe;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final ActiveCutControllers _controllers;
  final OpacityVerbs _opacityVerbs;
  final TrackSeDisplay _trackSe;

  /// The editing canvas's composite TREE at the playhead — the same tree
  /// playback and export composite, with the ACTIVE layer standing in it
  /// as a [CanvasActiveLayerRow] instead of a cached image.
  ///
  /// That node is the whole point: the stack used to be two flat lists
  /// painted around the interactive view, so a folder's group buffer —
  /// one `saveLayer` — could never span the layer you were drawing on.
  /// Now one painter opens the buffer, draws the live surface inside it,
  /// and closes it.
  ///
  /// [activeLayerOpacity] is the active row's display opacity (0 while
  /// hidden; includes its animated Opacity); its pose rides separately
  /// through `layerCanvasPoseSample` into the interactive draw-through
  /// wrap, so it is repeated on the node for the merged painter.
  ({
    List<CompositeNode<CanvasStackRow>> nodes,
    double activeLayerOpacity,
    List<ResolvedLayerEffect> activeSourceEffects,
  })
  get stack {
    final cut = _project.activeCutOrNull;
    final activeLayerId = _selection.activeLayerId;
    if (cut == null) {
      return (
        nodes: const <CompositeNode<CanvasStackRow>>[],
        activeLayerOpacity: 1.0,
        activeSourceEffects: const <ResolvedLayerEffect>[],
      );
    }

    final frameIndex = _controllers.timelineController.currentFrameIndex;
    // Opacity drag preview (R4 #4/#6, DISPLAY only): the dragged rows'
    // static opacity substitutes in before the shared visit, so the canvas
    // follows the drag without any repo write per move.
    final preview = _opacityVerbs.dragPreview.value;
    final stackCut = preview == null
        ? cut
        : cut.copyWith(layers: _withOpacityPreview(cut.layers, preview));

    final drawn = stackAt(
      cut: cut,
      stackCut: stackCut,
      frameIndex: frameIndex,
      drawingLayerId: activeLayerId,
    );
    final nodes = <CompositeNode<CanvasStackRow>>[
      ...drawn.nodes,
      // Track-owned SE rows join as their cut-local display clones — they
      // composite read-only like before the ownership move (their
      // transform tracks are stripped, so the plain resolve path
      // suffices). They live outside the cut's stack, so they land at the
      // top level.
      ..._trackSeDisplayNodes(cut, frameIndex: frameIndex, preview: preview),
    ];
    return (
      nodes: List.unmodifiable(nodes),
      activeLayerOpacity: drawn.activeLayerOpacity,
      activeSourceEffects: drawn.activeSourceEffects,
    );
  }

  /// [cut]'s composite tree at [frameIndex] with [drawingLayerId] standing
  /// in it as the live row — the editing canvas's at the playhead ([stack])
  /// and a conte picture's while its brush is on, one walk for both: the
  /// row a pen draws on is drawn where the composite puts it.
  ///
  /// [stackCut] is [cut] as it composites right now (the canvas's opacity
  /// drag preview). The live row stands in the tree only when it takes
  /// brush input; otherwise it composites like any other.
  ({
    List<CompositeNode<CanvasStackRow>> nodes,
    double activeLayerOpacity,
    List<ResolvedLayerEffect> activeSourceEffects,
  })
  stackAt({
    required Cut cut,
    Cut? stackCut,
    required int frameIndex,
    required LayerId? drawingLayerId,
  }) {
    final shown = stackCut ?? cut;
    final walk = EditingStackMap(
      opacityVerbs: _opacityVerbs,
      internals: _internals,
      cut: cut,
      stackCut: shown,
      frameIndex: frameIndex,
      activeLayerId: drawingLayerId,
    );
    final drawing = drawingLayerId == null
        ? null
        : shown.layers.byId(drawingLayerId);
    final nodes = walk.mapTree(
      resolveCutFrameCompositeTree(
        cut: shown,
        frameIndex: frameIndex,
        liveLayerId: drawing != null && layerAcceptsBrushInput(drawing)
            ? drawingLayerId
            : null,
      ),
    );
    return (
      nodes: nodes,
      activeLayerOpacity: walk.activeLayerOpacity,
      activeSourceEffects: walk.activeSourceEffects,
    );
  }

  /// [source] with the DRAGGED rows' opacity substituted in — display
  /// only, so the canvas follows an opacity drag without a repo write per
  /// move.
  static List<Layer> _withOpacityPreview(
    List<Layer> source,
    ({Set<LayerId> layerIds, double opacity}) preview,
  ) => [
    for (final layer in source)
      if (preview.layerIds.contains(layer.id) && layer.kind.hasPictureOpacity)
        layer.copyWith(opacity: preview.opacity)
      else
        layer,
  ];

  /// The track's SE rows as cut-local display clones, read-only.
  Iterable<CompositeNode<CanvasStackRow>> _trackSeDisplayNodes(
    Cut cut, {
    required int frameIndex,
    required ({Set<LayerId> layerIds, double opacity})? preview,
  }) sync* {
    final rows = preview == null
        ? _trackSe.trackSeDisplayLayers
        : _withOpacityPreview(_trackSe.trackSeDisplayLayers, preview);
    for (final layer in rows) {
      if (!layer.isVisible || layer.opacity <= 0) {
        continue;
      }
      final opacity = layer.transformEnabled
          ? resolveLayerEffectiveOpacityAt(layer: layer, frameIndex: frameIndex)
          : layer.opacity.clamp(0.0, 1.0).toDouble();
      // The ANIMATED opacity reaching zero, which the flag above cannot
      // see (that one reads the row's static value). ⚠️Untested: it needs
      // a transform track whose opacity curve hits 0 while the row's own
      // stays above it (2026-09-05).
      if (opacity <= 0) {
        continue;
      }
      final frame = resolveExposedFrameAt(layer, frameIndex);
      if (frame == null) {
        continue;
      }
      yield CompositeLeaf(
        CanvasLayerImageRequest(
          frameKey: _internals.brushFrameKeyForCut(cut, layer.id, frame.id),
          opacity: opacity,
          pose: null,
          anchorPoint: null,
        ),
      );
    }
  }

  BrushEditorSelection? get activeBrushEditorSelection {
    // Ghost repeat instances resolve to their ANCHOR cel deliberately
    // (UI-R19b, user decision): drawing with the playhead on a ghost
    // edits the source cel — the light-table workflow. Delete alone
    // stays refused on ghosts.
    final selectedFrame = _selection.selectedFrame;
    return selectedFrame == null
        ? null
        : brushEditorSelectionFor(selectedFrame.id);
  }

  /// The active layer's brush target at [frameId] — every gate a stroke
  /// target answers (the row takes brush input, it is shown, there is a
  /// cut), asked in ONE place whether the cel exists yet or not.
  ///
  /// 🚨F-171: [activeBrushEditorSelection] asks it for the cel under the
  /// playhead; the canvas asks it for the cel a press there WOULD make
  /// (`AutoFrameForStroke.frameIdForNextCel`), so the editing stack can
  /// stand before the first cel exists — and a hidden or data row gets no
  /// stack to stand, for the same reasons it gets no stroke.
  BrushEditorSelection? brushEditorSelectionFor(FrameId frameId) {
    final activeLayer = _selection.activeLayer;
    if (activeLayer == null) {
      return null;
    }
    // R6-④: SE/instruction cels are data rows — no editable brush target,
    // so the canvas never accepts strokes on them (the drawn stack still
    // composites them read-only). A media-REFERENCE layer (§6-z23) shows
    // a library asset: no strokes until it is rasterized.
    if (!layerAcceptsBrushInput(activeLayer)) {
      return null;
    }
    // R4 #1: a hidden layer takes no strokes either — you would be drawing
    // into something the canvas doesn't show. Flip the eye back on (or use
    // the solo mode) to draw.
    //
    // 🚨AND THE FOLDER'S EYE COUNTS (유저 2026-08-13: 「숨긴 폴더는 안에
    // 있는 레이어들도 숨김상태인거일거잖아. 그러면 브러시 막는거지」). The
    // reason R4 #1 gives — you would be drawing into something the canvas
    // doesn't show — is the SAME reason one folder up, and asking only the
    // row's own eye is how a stroke went on landing in a folder the user had
    // switched off.
    if (!_project.layers.rowVisible(activeLayer)) {
      return null;
    }

    final cutId = _timeline.editingSession.activeCutId;
    if (cutId == null) {
      return null; // Gap state: no cut, no brush target.
    }
    return BrushEditorSelection(
      projectId: _project.repository.requireProject().id,
      trackId: _selection.selectedTrackId,
      cutId: cutId,
      layerId: activeLayer.id,
      frameId: frameId,
    );
  }

  /// Rasterize (§6-f): the ONE verb for every derived-content layer.
  /// Reference layers null [Layer.mediaReference] (the pixels are already
  /// the cels) and their asset stays in the pool (유저 2026-09-11: 「구워도
  /// 풀에 남음」).
  bool get canRasterizeActiveLayer =>
      _selection.activeLayer?.mediaReference != null;

  void rasterizeActiveLayer() {
    final layer = _selection.activeLayer;
    if (layer == null || layer.mediaReference == null) {
      return;
    }
    rasterizeLayerReferences([layer.id]);
  }

  /// Rasterizes every REFERENCE row among [layerIds] as ONE undo step.
  ///
  /// The reference button's popover hands over the rows its press acts on
  /// (`RowSelection.rowsActedOnBy`: 「선택 안에서 누르면 선택 전체, 밖에서
  /// 누르면 그것만」), and one gesture undoes as one — through the history's
  /// `runAsOneStep`, as the row verbs do. A row that points at no file lands
  /// nothing, and the active row stays where it is.
  void rasterizeLayerReferences(Iterable<LayerId> layerIds) {
    final cutId = _timeline.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _project.historyManager.runAsOneStep('Rasterize layers', () {
      for (final layerId in layerIds) {
        _project.cutCommandCoordinator.rasterizeLayerReference(
          cutId: cutId,
          layerId: layerId,
        );
      }
    });
    _changes.refreshAfterCutCommand(
      preferredActiveLayerId: _selection.activeLayer?.id,
    );
    _changes.notifyChanged();
  }
}
