// THE TWO CONTROLLERS THE ACTIVE CUT OWNS, AND THE ONE PLACE THEY ARE
// REPLACED.
//
// Its own object since round 8 (G2, 2026-09-07). Every other collaborator
// reads `layerController` and `timelineController`; exactly one thing
// WRITES them, and it writes both at once because they are one fact — the
// cut this session is editing. Keeping the pair and their rebuild apart
// is what let a caller hold a controller across a cut switch.
//
// ⛔What is NOT here is the session's REACTION to a rebuild: unseating a
// stranded verb row, republishing the drawn row, republishing the part of
// a track-global lane span this cut can see. Those touch the standing row
// and the selection, and `Standing` reads the controllers, so a rebuild
// that reached back out for them could not be built at all. They arrive
// as [onRebuilt].

import 'dart:math' as math;

import '../../controllers/layer_controller.dart';
import '../../controllers/timeline_controller.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import 'session_roles.dart';

/// The active cut's layer and timeline controllers, and the rebuild that
/// replaces them together.
class ActiveCutControllers {
  ActiveCutControllers({
    required ProjectAccess project,
    required SelectionAccess selection,
    required TimelineAccess timeline,
    required SessionInternals internals,
    required int Function() playbackFrameCount,
    required List<Layer> Function() trackSeDisplayLayers,
    required Layer Function() trackTransitionDisplayLayer,
    required void Function() onRebuilt,
  }) : _project = project,
       _selection = selection,
       _timeline = timeline,
       _internals = internals,
       _playbackFrameCount = playbackFrameCount,
       _trackSeDisplayLayers = trackSeDisplayLayers,
       _trackTransitionDisplayLayer = trackTransitionDisplayLayer,
       _onRebuilt = onRebuilt;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final TimelineAccess _timeline;
  final SessionInternals _internals;
  final int Function() _playbackFrameCount;

  /// Read LAZILY, not held: the display rows are another collaborator's,
  /// and that collaborator reads the controllers built here.
  final List<Layer> Function() _trackSeDisplayLayers;
  final Layer Function() _trackTransitionDisplayLayer;
  final void Function() _onRebuilt;

  static const FrameId _frameId = FrameId('default-frame');

  late LayerController layerController;
  late TimelineController timelineController;

  /// A frame index that exists in the active cut. The playhead's landing
  /// after a run and the controller's own start index are the same
  /// question, so they read one answer.
  int clampedFrameIndex(int frameIndex) {
    final maxIndex = math.max(0, _playbackFrameCount() - 1);
    return frameIndex.clamp(0, maxIndex);
  }

  void rebuild({LayerId? preferredActiveLayerId, int preferredFrameIndex = 0}) {
    final activeCutId = _timeline.editingSession.activeCutId;
    final initialActiveLayerId =
        _internals.activeCutHasLayer(preferredActiveLayerId)
        ? preferredActiveLayerId
        : null;

    layerController = LayerController(
      repository: _project.repository,
      historyManager: _project.historyManager,
      cutId: activeCutId,
      frameId: _frameId,
      initialActiveLayerId: initialActiveLayerId,
      trackSeDisplayLayers: _trackSeDisplayLayers,
      trackTransitionDisplayLayer: _trackTransitionDisplayLayer,
    );
    timelineController = TimelineController(
      repository: _project.repository,
      historyManager: _project.historyManager,
      cutId: activeCutId,
      initialFrameIndex: clampedFrameIndex(preferredFrameIndex),
      // Track-SE mutations shift to the global axis inside the controller;
      // reads keep flowing through the cut-local display clones.
      frameOffsetForLayer: (layerId) => _project.isTrackSeLayerId(layerId)
          ? _project.activeCutGlobalStartFrame
          : 0,
      trackSeLayers: () => _selection.activeTrack.seLayers,
    );
    _internals.editingFrameCursor.value = timelineController.currentFrameIndex;
    _onRebuilt();
  }
}
