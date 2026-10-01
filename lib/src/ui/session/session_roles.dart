// The roles the editor session plays for its collaborators (round 8 of
// the audit, 2026-09-06). A collaborator names the roles it needs in its
// constructor and nothing else of the session is visible to it; the
// session is the one class that implements them all.
//
// 🚨EVERY MEMBER HERE IS ONE A COLLABORATOR ALREADY READ OR CALLED when the
// session was one class in 41 files (tool/refactor/session_map.dart
// measured it). Adding a member is widening the seam; the direction of
// travel is narrower roles, and a member no collaborator uses is deleted.

import 'package:flutter/foundation.dart';
import '../../services/editing/editing_session_state.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/cut.dart';
import '../../models/transform_track.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track.dart';
import '../../models/track_frame_range.dart';
import '../../models/track_id.dart';
import '../../models/track_frame_axis.dart';
import '../../services/commands/cut_command_coordinator.dart';
import '../../services/history_manager.dart';
import '../../services/project_repository.dart';
import '../timeline/timeline_cell_exposure_state.dart';

abstract interface class ProjectAccess {
  int get activeCutFrameCount;
  int get activeCutDrawnFrameCount;
  Layer? commitLayerById(LayerId layerId);
  CutCommandCoordinator get cutCommandCoordinator;
  HistoryManager get historyManager;
  Layer? layerById(LayerId layerId);
  Layer? rangeLayerById(LayerId layerId);
  ProjectRepository get repository;
  Track? trackById(TrackId trackId);
  int get activeCutGlobalStartFrame;
  CutId? get activeCutId;
  Cut? get activeCutOrNull;
  Cut? cutById(CutId cutId);
  BrushFrameKey brushFrameKeyForCut(Cut cut, LayerId layerId, FrameId frameId);
  bool isTrackSeLayerId(LayerId layerId);
  int rowAxisOffset(LayerId layerId);
  bool isTrackTransitionLayerId(LayerId layerId);
  List<Layer> get layers;
  Cut get requireActiveCut;
  Track? trackOwningCut(CutId cutId);
  Layer? trackSeGlobalLayerById(LayerId layerId);
}

abstract interface class SelectionAccess {
  Map<LayerId, T> bandRowsForSelection<T>(
    bool Function(Layer layer) accepts,
    Map<LayerId, T> Function(
      List<LayerId> ids,
      TimelineFrameRangeSelection selection,
    )
    inBand,
  );
  Layer? get activeLayer;
  LayerId? get activeLayerId;
  Track get activeTrack;
  bool get bandNamesRowsThisPressWouldMiss;
  bool bandOrActiveRow(
    bool bandAnswers,
    bool Function(Layer layer) accepts,
    bool Function(Layer layer) atPlayhead,
  );
  void clearAllSelections();
  void clearFrameRangeSelection();
  void clearRowSelection();
  void clearStoryboardCutSelection();
  void clearTimelineSelections();
  int get currentFrameIndex;
  int get editingGlobalFrame;
  ValueNotifier<TimelineFrameRangeSelection?> get frameRangeSelection;
  ValueNotifier<TimelineLaneSelection?> get laneRangeSelection;
  ValueNotifier<List<TimelineRowAddress>> get rowSelection;
  void selectFrameIndex(int frameIndex);
  void selectGlobalFrame(int globalFrame, {TrackFrameAxis? onAxis});
  Frame? get selectedFrame;
  TimelineRowAddress get storyboardStandingRow;
  TrackId get selectedTrackId;
  ValueNotifier<TrackFrameRangeSelection?> get trackFrameRangeSelection;
}

abstract interface class ChangeSink {
  void notifyChanged();
  void refreshAfterCutCommand({
    LayerId? preferredActiveLayerId,
    int? preferredFrameIndex,
    bool reveal = false,
    bool filterSparesStanding = true,
  });
  void refreshLiveAudioSchedule();
  void warmActiveCut();
}

/// THE RETIME LAW — whether a row's timing is its own to move, asked two
/// ways: [standsDownFromRetime] by the RESHAPING verbs, [blockMoveEligible]
/// by a block MOVE. One law's two halves, so one role (the audit's
/// nineteenth family, 2026-09-28): the first had been sorted into
/// `ChangeSink` by the role generator, the second sat among the session's
/// internals, and the session's own comments already read one through the
/// other.
abstract interface class RetimeLaw {
  bool blockMoveEligible(LayerId layerId);
  bool standsDownFromRetime(LayerId layerId);
}

abstract interface class FrameIds {
  FrameId mintFrameId(LayerId layerId);
}

abstract interface class TimelineAccess {
  EditingSessionState get editingSession;
  TimelineCellExposureState exposureStateForLayer(Layer layer, int frameIndex);
  CanvasPoint layerAnchorPointAtFrame(Layer layer, int frameIndex);
  TransformPose layerPoseAtFrame(Layer layer, int frameIndex);
  TrackFrameAxis trackFrameAxis();
}
