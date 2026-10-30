import 'package:flutter/foundation.dart' show ValueNotifier;
import '../../models/brush_frame_key.dart';
import '../../models/composite_tree.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/fx_plugin_binding.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/transform_pose.dart';
import '../../services/cut_frame_composite_plan.dart';
import '../brush/brush_editor_selection.dart';
import '../canvas/canvas_layer_stack_view.dart';
import '../timeline/timeline_drag_preview.dart'
    show TimelineDragPreview, cutShowingDragPreview, layersShowingDragPreview;
import '../track_effect_paint_policy.dart' show underTheCutsFx;
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
/// [rasterizeLayerReferences] is the verb that CHANGES that answer: a media
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
    required ValueNotifier<TimelineDragPreview?> dragPreview,
    required ActiveCutControllers controllers,
    required OpacityVerbs opacityVerbs,
    required TrackSeDisplay trackSe,
    required List<ResolvedLayerEffect> Function(CutId cutId, int frameIndex)
    cutEffectsAt,
    required TransformPose? Function(BrushFrameKey key) movieLaidAt,
    required Map<LayerId, List<CutFrameCompositeGhost>> Function(
      Cut cut,
      int frameIndex,
      TimelineDragPreview? dragPreview,
    )
    ghostsAt,
    required FxPluginBinding Function(Cut cut) pluginsIn,
  }) : _ghostsAt = ghostsAt,
       _pluginsIn = pluginsIn,
       _cutEffectsAt = cutEffectsAt,
       _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _dragPreview = dragPreview,
       _controllers = controllers,
       _opacityVerbs = opacityVerbs,
       _trackSe = trackSe,
       _movieLaidAt = movieLaidAt;

  /// Where a movie cel's installed picture was laid
  /// (`MovieCelHydrator.laidAt`) — the stack moves it to where its row's
  /// reference fx stands now ([EditingStackMap]).
  final TransformPose? Function(BrushFrameKey key) _movieLaidAt;

  /// What runs the plugins a cut's chains run on this canvas
  /// (`EditorSessionManager.fxPluginsIn`).
  final FxPluginBinding Function(Cut cut) _pluginsIn;

  /// Each onion row's ghosts at a cut's frame (`OnionSkin.ghostsAt`).
  final Map<LayerId, List<CutFrameCompositeGhost>> Function(
    Cut cut,
    int frameIndex,
    TimelineDragPreview? dragPreview,
  )
  _ghostsAt;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;
  final ValueNotifier<TimelineDragPreview?> _dragPreview;
  final ActiveCutControllers _controllers;
  final OpacityVerbs _opacityVerbs;
  final TrackSeDisplay _trackSe;

  /// The V row's fx over [cutId]'s finished picture at its own frame
  /// [frameIndex], sampled on the track's axis and bypassed by the row's fx
  /// switch — the one chain playback, the track stack and the file filter
  /// the cut through.
  final List<ResolvedLayerEffect> Function(CutId cutId, int frameIndex)
  _cutEffectsAt;

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
  get stack => _stackAtThePlayhead(_selection.activeLayerId);

  /// [stack] with each onion row's ghosts directly under its drawing
  /// (`OnionSkinPlacement.inPlace`) — the one picture a canvas standing in
  /// place shows, and the one its pen's steps are patched into.
  ({
    List<CompositeNode<CanvasStackRow>> nodes,
    double activeLayerOpacity,
    List<ResolvedLayerEffect> activeSourceEffects,
  })
  get stackWithItsGhosts =>
      _stackAtThePlayhead(_selection.activeLayerId, ghostsInPlace: true);

  /// The onion ghosts a canvas standing on [cut]'s frame [frameIndex] lays
  /// over its picture (`OnionSkinPlacement.onTop`), each onion row's in
  /// stack order — drawn as the same ghosts are in place.
  List<CompositeNode<CanvasStackRow>> ghostsOverAt(Cut cut, int frameIndex) {
    final dragPreview = _dragPreview.value;
    return EditingStackMap(
      opacityVerbs: _opacityVerbs,
      project: _project,
      cut: cut,
      stackCut: cut,
      dragPreview: dragPreview,
      frameIndex: frameIndex,
      activeLayerId: null,
      movieLaidAt: _movieLaidAt,
      plugins: _pluginsIn(cut),
    ).mapTree(
      readingTheirRows(
        [
          for (final ghosts in _ghostsAt(cut, frameIndex, dragPreview).values)
            for (final ghost in ghosts)
              CompositeLeaf<CutFrameCompositeRow>(ghost),
        ],
        cut: cut,
        frameIndex: frameIndex,
        liveLayerId: null,
      ),
    );
  }

  /// [stack] as a RUN shows it: the same tree with no row standing live. A
  /// run draws on nothing, so the frame is the picture the warmer made of
  /// it ahead of the playhead (`FramePictures`), keyed by this tree — the
  /// picture the canvas shows of the frame standing still
  /// (one-picture-per-frame).
  ({
    List<CompositeNode<CanvasStackRow>> nodes,
    double activeLayerOpacity,
    List<ResolvedLayerEffect> activeSourceEffects,
  })
  get playingStack => _stackAtThePlayhead(null);

  /// [cut]'s frame [frameIndex] as a RUN shows it, wherever it is shown: the
  /// composite tree under the V row's fx with no row standing live — what
  /// the track stack draws for a cut it shows (the whole film, a gap's
  /// parking, an O.L's partner), and the tree the warmer makes a frame's
  /// picture of ahead of the playhead (`FramePictures.stackOf`); the
  /// canvas's own at the playhead is [playingStack], which also follows a
  /// drag in flight.
  ///
  /// ⚠️The track's SE rows join the open cut's frames only: their clones are
  /// the open cut's window ([TrackSeDisplay.trackSeWindow]), and another
  /// cut's would stand where they do not.
  ///
  /// [ghostsInPlace] asks it as a canvas standing in place shows it
  /// ([stackWithItsGhosts]) — what the warmer lays ahead of a scrub.
  List<CompositeNode<CanvasStackRow>> playedStackAt(
    Cut cut,
    int frameIndex, {
    bool ghostsInPlace = false,
  }) => [
        ..._underTheCutsFx(
          cut,
          frameIndex,
          stackAt(
            cut: cut,
            frameIndex: frameIndex,
            drawingLayerId: null,
            ghosts: ghostsInPlace ? _ghostsAt(cut, frameIndex, null) : null,
          ).nodes,
        ),
        if (cut.id == _project.activeCutOrNull?.id)
          ..._trackSeDisplayNodes(
            cut,
            frameIndex: frameIndex,
            dragPreview: null,
            preview: null,
          ),
      ];

  ({
    List<CompositeNode<CanvasStackRow>> nodes,
    double activeLayerOpacity,
    List<ResolvedLayerEffect> activeSourceEffects,
  })
  _stackAtThePlayhead(LayerId? drawingLayerId, {bool ghostsInPlace = false}) {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return (
        nodes: const <CompositeNode<CanvasStackRow>>[],
        activeLayerOpacity: 1.0,
        activeSourceEffects: const <ResolvedLayerEffect>[],
      );
    }

    final frameIndex = _controllers.timelineController.currentFrameIndex;
    // A drag in flight — a block, a comma, several rows, a file pushing its
    // neighbours, a lane value (F-195) — substitutes its rows in before the
    // shared visit, so the picture follows the hand with no repo write per
    // move, exactly as the opacity drag below always has
    // (canvas-follows-block-moves, 유저 2026-09-28 「따라가게」).
    final dragPreview = _dragPreview.value;
    final shownCut = cutShowingDragPreview(cut, dragPreview);
    // Opacity drag preview (R4 #4/#6, DISPLAY only): the dragged rows'
    // static opacity substitutes in before the shared visit, so the canvas
    // follows the drag without any repo write per move.
    final preview = _opacityVerbs.dragPreview.value;
    final stackCut = preview == null
        ? shownCut
        : shownCut.copyWith(
            layers: _withOpacityPreview(shownCut.layers, preview),
          );

    final drawn = stackAt(
      cut: cut,
      stackCut: stackCut,
      dragPreview: dragPreview,
      frameIndex: frameIndex,
      drawingLayerId: drawingLayerId,
      ghosts: ghostsInPlace ? _ghostsAt(cut, frameIndex, dragPreview) : null,
    );
    final nodes = <CompositeNode<CanvasStackRow>>[
      ..._underTheCutsFx(stackCut, frameIndex, drawn.nodes),
      // Track-owned SE rows join as their cut-local display clones — they
      // composite read-only like before the ownership move (their
      // transform tracks are stripped, so the plain resolve path
      // suffices). They live outside the cut's stack, so they land at the
      // top level.
      ..._trackSeDisplayNodes(
        cut,
        frameIndex: frameIndex,
        dragPreview: dragPreview,
        preview: preview,
      ),
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
  /// [stackCut] is [cut] as it composites right now (the drag in flight, the
  /// canvas's opacity drag preview); [cut] is what the brush holds. The live
  /// row stands in the tree only when it takes brush input and shows the cel
  /// the brush holds; otherwise it composites like any other. [dragPreview]
  /// is the drag [stackCut] shows, if any ([EditingStackMap.dragPreview]);
  /// [ghosts], each onion row's where they lie in place.
  ({
    List<CompositeNode<CanvasStackRow>> nodes,
    double activeLayerOpacity,
    List<ResolvedLayerEffect> activeSourceEffects,
  })
  stackAt({
    required Cut cut,
    Cut? stackCut,
    TimelineDragPreview? dragPreview,
    required int frameIndex,
    required LayerId? drawingLayerId,
    Map<LayerId, List<CutFrameCompositeGhost>>? ghosts,
  }) {
    final shown = stackCut ?? cut;
    final walk = EditingStackMap(
      opacityVerbs: _opacityVerbs,
      project: _project,
      cut: cut,
      stackCut: shown,
      dragPreview: dragPreview,
      frameIndex: frameIndex,
      activeLayerId: drawingLayerId,
      movieLaidAt: _movieLaidAt,
      plugins: _pluginsIn(cut),
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
        ghostsOf: ghosts == null ? null : (row) => ghosts[row.id] ?? const [],
      ),
    );
    return (
      nodes: nodes,
      activeLayerOpacity: walk.activeLayerOpacity,
      activeSourceEffects: walk.activeSourceEffects,
    );
  }

  /// [cutNodes] under the V row's fx ([_cutEffectsAt]), as every route that
  /// draws the cut lays it ([underTheCutsFx]).
  ///
  /// 🚨THE CANVAS WAS THE ONE ROUTE WITHOUT IT (playback-plays-the-screen-
  /// material, 10-09): playback, the parked track stack and both exports
  /// filtered the cut through the V row's chain, and the canvas you stand on
  /// showed it bare — so the same frame read two ways the moment a run
  /// began (유저 절대규칙 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
  ///
  /// ⛔Here and not in [stackAt]: a conte picture's live stack walks that
  /// too, and its printed picture is the cut's composite, which carries no
  /// V row.
  ///
  /// Its plugins run as the cut's rows' do (🗣️I-132-Q34 a), reading [cut]'s
  /// rows at [frameIndex].
  List<CompositeNode<CanvasStackRow>> _underTheCutsFx(
    Cut cut,
    int frameIndex,
    List<CompositeNode<CanvasStackRow>> cutNodes,
  ) => underTheCutsFx(
    cutNodes,
    _pluginsIn(cut)(
      _cutEffectsAt(cut.id, frameIndex),
      cut: cut,
      frameIndex: frameIndex,
    ),
  );

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

  /// The track's SE rows as cut-local display clones, read-only — a dragged
  /// one as the drag in flight shows it.
  Iterable<CompositeNode<CanvasStackRow>> _trackSeDisplayNodes(
    Cut cut, {
    required int frameIndex,
    required TimelineDragPreview? dragPreview,
    required ({Set<LayerId> layerIds, double opacity})? preview,
  }) sync* {
    final shown = layersShowingDragPreview(
      _trackSe.trackSeDisplayLayers,
      dragPreview,
    );
    final rows = preview == null
        ? shown
        : _withOpacityPreview(shown, preview);
    for (final layer in rows) {
      if (!layer.isVisible || layer.opacity <= 0) {
        continue;
      }
      final opacity = resolveLayerEffectiveOpacityAt(
        layer: layer,
        frameIndex: frameIndex,
      );
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
          frameKey: _project.brushFrameKeyForCut(cut, layer.id, frame.id),
          opacity: opacity,
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
    if (activeLayer == null || activeRowStrokeRefusal != null) {
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

  /// WHY the active row takes no stroke — null when it takes one.
  ///
  /// 🗣️F-242 (유저 2026-09-29): 「그림 못그리는 이유 명확화. 지금 비지블off인
  /// 프레임에서 그리려해도 프레임이 존재안한다고 뜨는데 그런부분 원인 제대로
  /// 메시지 띄워주기」. The cursor notice chose its words from a second copy
  /// of these gates that knew two answers — 「not drawable」 and 「no
  /// frame」 — so a cel on a hidden row was reported MISSING. The gates are
  /// asked here once: [brushEditorSelectionFor] refuses on any answer, and
  /// the notice names the answer it got.
  StrokeRefusal? get activeRowStrokeRefusal {
    final activeLayer = _selection.activeLayer;
    // R6-④: SE/instruction cels are data rows — no editable brush target,
    // so the canvas never accepts strokes on them (the drawn stack still
    // composites them read-only). A media-REFERENCE layer (§6-z23) shows
    // a library asset: no strokes until it is rasterized.
    if (activeLayer == null || !layerAcceptsBrushInput(activeLayer)) {
      return StrokeRefusal.notDrawable;
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
      return StrokeRefusal.hidden;
    }
    return null;
  }

  /// Rasterize (§6-f): the ONE verb for every derived-content layer.
  /// Reference layers null [Layer.mediaReference] (the pixels are already
  /// the cels) and their asset stays in the pool (유저 2026-09-11: 「구워도
  /// 풀에 남음」).
  bool get canRasterizeActiveLayer =>
      _selection.activeLayer?.mediaReference != null;

  /// Rasterizes every REFERENCE row among [layerIds] as ONE undo step —
  /// each whose move its own transform carries (`rasterizeReferenceRows`
  /// hands the rest to the bakes).
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

/// Why a row takes no stroke ([EditingCanvas.activeRowStrokeRefusal]).
enum StrokeRefusal {
  /// The row cannot hold a drawing at all — its kind takes no brush input,
  /// or it shows a library asset that waits for a rasterize.
  notDrawable,

  /// The row can hold one, but its eye (or a folder's above it) is off.
  hidden,
}
