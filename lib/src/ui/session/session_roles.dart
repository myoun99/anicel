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
import 'drags/drawing_block_move_drag.dart';
import 'attach_fx_confirm.dart';
import 'editor_app_settings.dart';
import '../../services/editing/editing_session_state.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/cut.dart';
import '../../models/transform_track.dart';
import '../../models/cut_id.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/pixel_verb_subject.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/canvas_selection.dart' show SelectionMaskOptions;
import '../../services/canvas_selection_region.dart';
import '../../models/layer_id.dart';
import '../../models/onion_skin_settings.dart';
import '../../models/delete_subject.dart';
import '../../models/timeline_frame_range.dart';
import '../../models/timeline_row_address.dart';
import '../../models/track.dart';
import '../../models/track_frame_range.dart';
import '../../models/track_id.dart';
import '../../models/track_se_window.dart';
import '../../models/track_frame_axis.dart';
import '../../services/commands/cut_command_coordinator.dart';
import '../../services/commands/cut_reorder_planner.dart';
import '../../services/history_manager.dart';
import '../../services/project_repository.dart';
import '../timeline/timeline_cell_exposure_state.dart';
import '../timeline/timeline_drag_preview.dart';

abstract interface class ProjectAccess {
  int get activeCutFrameCount;
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
  int? get gapGlobalFrame;
  set gapGlobalFrame(int? value);
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
  int get currentFrameIndex;
  int get editingGlobalFrame;
  ValueNotifier<TimelineFrameRangeSelection?> get frameRangeSelection;
  ValueNotifier<TimelineLaneSelection?> get laneRangeSelection;
  ValueNotifier<List<TimelineRowAddress>> get rowSelection;
  void selectFrameIndex(int frameIndex);
  void selectGlobalFrame(int globalFrame, {TrackFrameAxis? onAxis});
  Frame? get selectedFrame;
  TimelineRowAddress get selectedRow;
  TrackId get selectedTrackId;
  ValueNotifier<TrackFrameRangeSelection?> get trackFrameRangeSelection;
}

abstract interface class ChangeSink {
  void notifyChanged();
  void refreshAfterCutCommand({
    LayerId? preferredActiveLayerId,
    int? preferredFrameIndex,
  });
  void refreshLiveAudioSchedule();
  bool standsDownFromRetime(LayerId layerId);
  void warmActiveCut();
}

abstract interface class FrameIds {
  FrameId mintFrameId(LayerId layerId);
  String nextFrameId(LayerId layerId);
}

abstract interface class TimelineAccess {
  TrackFrameAxis axisForTrack(TrackId trackId);
  EditingSessionState get editingSession;
  TimelineCellExposureState exposureStateForLayer(Layer layer, int frameIndex);
  TransformPose layerPoseAtFrame(Layer layer, int frameIndex);
  TrackFrameAxis trackFrameAxis();
}

/// The canvas-side facts a PIXEL VERB press needs, read together at the
/// moment of the press.
///
/// 🚨★★★**ONE MEMBER, NOT THREE.** They were three fields on
/// [SessionInternals], published by one method and read by one collaborator
/// — and the comment over the publisher already called them 「the canvas-side
/// facts the PIXEL verbs need」, which is a name. Adding the mask as a fourth
/// field would have widened the seam the ratchet below is closing; folding
/// them narrows it by two.
///
/// ⚠️Read at the PRESS, all three at once: the marquee survives tool
/// switches, the colour changes under the pointer, and the tool settings
/// panel can move the mask while the popover is open, so a value captured
/// when the editor opened would be none of them.
typedef PixelVerbCanvas = ({
  CanvasSelectionRegion? region,
  int argb,
  SelectionMaskOptions mask,
});

/// What collaborators still reach into the session for beyond the
/// roles above — the measured remainder of the coupling, and a list
/// that only shrinks: each member either moves into the one
/// collaborator that uses it, becomes a role, or is injected as the
/// sibling it really is. ⛔Nothing is added here.
abstract interface class SessionInternals {
  bool activeCutHasLayer(LayerId? layerId);
  EditorAppSettings get appSettings;
  DrawingBlockMoveDrag? get blockMoveDrag;
  set blockMoveDrag(DrawingBlockMoveDrag? value);
  bool blockMoveEligible(LayerId layerId);
  int commitBlockStart(LayerId layerId, int displayStart);
  CutReorderPlanner get cutReorderPlanner;
  bool get disposed;
  String drawingStartStatusForLayer(Layer layer, int frameIndex);
  List<({int startIndex, int length})> emptyGapsInRange(
    Layer layer,
    TimelineFrameRangeSelection selection,
  );
  void followPlaybackCut();
  Layer? get targetLayerForKindToggle;
  AttachFxConfirmController get attachFxConfirm;
  BrushFrameKey brushFrameKeyForCut(Cut cut, LayerId layerId, FrameId frameId);
  bool get canCreateInstance;
  bool Function()? get canvasHasSelection;
  void Function()? get clearCanvasSelection;
  TimelineRowAddress get currentRow;
  ValueNotifier<TimelineRowAddress?> get currentRowListenable;
  DeleteSubject get deleteSubject;
  ValueNotifier<TimelineDragPreview?> get dragPreview;
  ValueNotifier<int> get editingFrameCursor;
  bool get editingInteractionBusy;
  bool get editingPlayheadInGap;
  ValueNotifier<bool> get frameScrubActive;
  double get lastMasterOpacity;
  set lastMasterOpacity(double value);
  CanvasPoint layerAnchorPointAtFrame(Layer layer, int frameIndex);
  double layerOpacityAtFrame(Layer layer, int frameIndex);
  ValueNotifier<Set<LayerId>> get onionSkinLayerIds;
  ValueNotifier<OnionSkinSettings> get onionSkinSettings;
  ValueNotifier<({Set<LayerId> layerIds, double opacity})?>
  get opacityDragPreview;
  PixelVerbCanvas Function()? get pixelVerbCanvas;
  BrushFrameEditingCoordinator? get pixelEditingCoordinator;
  PixelVerbSubject get pixelVerbSubject;
  bool resetLaneGroup(LayerId layerId, String headerLaneId);
  ValueNotifier<int> get revealSelectionTick;
  bool rowIsSelected(TimelineRowAddress row);
  ValueNotifier<bool> get scrubOutOfTerritory;
  void selectLayer(LayerId layerId);
  void selectTrackCutAtPlayhead(TrackId trackId);
  void selectTrackRow(TrackId trackId);
  ValueNotifier<bool> get selectionInteractionActive;
  ValueNotifier<Set<LayerId>> get soloedSeLayerIds;
  void standOnRow(
    TimelineRowAddress row, {
    int? frameIndex,
    int? globalFrameIndex,
    bool takesLayerActive = true,
  });
  ValueNotifier<({TrackId trackId, double opacity})?>
  get trackOpacityDragPreview;
  TrackSeWindow get trackSeWindow;
  ValueNotifier<Layer?> get transitionEdgeDragPreview;
  void updateActiveCutCameraTrack(
    TransformTrack track, {
    String description = 'Edit camera keyframes',
  });
  void updateLayerTransformEnabled(
    LayerId layerId, {
    required bool enabled,
    String description = 'Toggle transform FX',
  });
  void updateLayerTransformTrack(
    LayerId layerId,
    TransformTrack track, {
    String description = 'Edit layer transform',
  });
}
