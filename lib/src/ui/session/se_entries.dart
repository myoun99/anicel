import '../../services/project_lookup.dart' show requireLayerAnywhere;
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/se_line_type.dart';
import '../../models/track_transitions.dart' show cutDrawnFrameCount;
import '../../services/camera_projection_matrix.dart' show shotPlacement;
import '../../services/layer_pose_matrix.dart' show LayerPlacement;
import '../../services/se_name_tag_plan.dart';
import '../timeline/timeline_drag_preview.dart'
    show TimelineDragPreview, globalLayersShowingDragPreview;
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'camera.dart';
import 'frame_verbs.dart';
import 'project_settings.dart';

/// The SE ENTRIES AND NAME TAGS — creating and updating an SE entry, and
/// the name tags an SE row puts on the canvas at a frame — as their own
/// object.
///
/// ⛔The name tag SETTERS are gone (F-102, 2026-09-15). `setSeNameTagForLayer`
/// took a tag edited against the cut-local clone and converted its keys
/// through the cut window, which lost every key the clone had dropped — a
/// lane edit writes the tag through `LaneVerbs` now, on the row the project
/// holds. `setActiveSeNameTag` and `canEditActiveSeNameTag` had no caller
/// left in the app.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: nothing of its own; the rest
/// reads none of it. It names the roles it needs in its constructor.
class SeEntries {
  SeEntries({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required FrameIds frameIds,
    required ActiveCutControllers controllers,
    required Camera camera,
    required FrameVerbs frameVerbs,
    required ProjectSettings projectSettings,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _camera = camera,
       _frameVerbs = frameVerbs,
       _projectSettings = projectSettings;

  final Camera _camera;
  final FrameVerbs _frameVerbs;

  /// Where each cut's own frames stand on its track
  /// ([ProjectSettings.projectAxis]) — the name tags' one question of it.
  final ProjectSettings _projectSettings;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;

  /// The ON-CANVAS name tags for a cut's local frame (R5b, §6-z15) — the
  /// one resolution every drawing surface asks (editing canvas, playback,
  /// the parked stack, export), so none of them can disagree. Works for
  /// ANY cut, not just the active one: it reads the owning track's global
  /// SE rows at the frame of the track the cut's own frame shows.
  ///
  /// [preview] is a drag in flight — an SE row's tag or pose scrubbed, its
  /// handle dragged (F-195), its lines moved or stretched
  /// (canvas-follows-block-moves) — which the EDITING canvas shows as it
  /// goes. The routes that render a committed film pass none.
  List<ResolvedSeNameTag> seNameTagsForCutFrame(
    Cut cut,
    int localFrameIndex, {
    TimelineDragPreview? preview,
  }) {
    // A frame the film PLAYS — the cut's place and the のりしろ an O.L asks
    // before and after it — shows what is heard then: in a margin, the
    // other cut's speaker (I-73-ol-index-space-Q1, 유저 2026-10-09: 「그 칸이
    // 재생되는 시각의 것」), so an O.L played through carries one tag on.
    // The runway past that is a CLIPPED VIEW of the cut (UI-R9 #4): a
    // playhead there must never address the NEIGHBOUR cut's SE window and
    // put the next speaker over this picture, so it is held to the cut
    // ([TrackFrameAxis.clampedToCutGlobalOf]), as before.
    //
    // ↩️The margins were held to the cut too — the storyboard's playhead
    // clamp, which they shared — until Q1.
    //
    // ↩️The cut's frame was added to the cut's PLACE on the track. A cut
    // an O.L arrives into counts its own frames from its のりしろ before
    // that, so every tag in it stood that margin early — on the editing
    // canvas, in playback and in an export alike (I-73-ol-index-space,
    // 🧪2026-10-09: with a 12-frame O.L the speaker of the track's frame
    // 30 showed on the cut's frame 6, which plays at 24, and was gone by
    // the frame that plays at 30).
    final axis = _projectSettings.projectAxis();
    final drawn = cutDrawnFrameCount(
      _project.repository.requireProject(),
      cut.id,
    );
    final plays =
        drawn != null && localFrameIndex >= 0 && localFrameIndex < drawn;
    final shown = plays
        ? axis.globalOf(cut.id, localFrameIndex)
        : axis.clampedToCutGlobalOf(cut.id, localFrameIndex);
    final trackId = axis.entryFor(cut.id)?.trackId;
    final track = trackId == null ? null : _project.trackById(trackId);
    // Most tracks hold no SE writing at all, and this runs per painted
    // frame per covered track.
    if (shown == null || track == null || track.seLayers.isEmpty) {
      return const [];
    }
    return resolveSeNameTagsAt(
      trackSeLayers: globalLayersShowingDragPreview(track.seLayers, preview),
      globalFrame: shown,
      cameraFrame: _camera.cameraFrameSize,
      shot: shotForCutFrame(cut, localFrameIndex),
    );
  }

  /// Where [cut]'s SHOT lies on its canvas at its frame [localFrameIndex] —
  /// the space its SE rows' name tags stand in ([ResolvedSeNameTag.shot]),
  /// through the camera that frame is shown through
  /// ([Camera.cameraPoseShowingCut]). The canvas's handle on a tag stands
  /// in it too.
  LayerPlacement shotForCutFrame(Cut cut, int localFrameIndex) =>
      shotPlacement(
        _camera.cameraPoseShowingCut(cut, localFrameIndex),
        _camera.cameraFrameSize,
      );

  /// SE rows: the selected entry's speaker/effect name (the accent box).
  String? get selectedFrameSeName => _selection.selectedFrame?.seName;

  /// The selected entry's delivery (I-20) — what the SE dialog opens on.
  SeLineType get selectedFrameSeType =>
      _selection.selectedFrame?.seType ?? SeLineType.on;

  /// Creates an SE entry at the current cell carrying [name] (the sheet's
  /// dialogue text) and the optional [seName] (speaker/effect, the accent
  /// box) in ONE undo step. The entry takes [lengthFrames] (the dialog's
  /// length input); null falls back to filling to the cut end (legacy).
  ///
  /// The cut end no longer clamps the length (SE globalization): a sound
  /// may run past it — the `~` crossing mark says so — and the NEXT
  /// entry bounds the length in the controller, on the global axis, so
  /// the neighbouring cuts' sounds count as walls too.
  void createSeEntryAtCurrentFrame({
    required String name,
    String? seName,
    int? lengthFrames,
  }) {
    final layer = _selection.activeLayer;
    if (layer == null ||
        layer.kind != LayerKind.se ||
        !_frameVerbs.canCreateDrawingAtCurrentFrame) {
      return;
    }

    final remaining =
        _project.requireActiveCut.duration -
        _controllers.timelineController.currentFrameIndex;
    final toCutEnd = remaining < 1 ? 1 : remaining;
    final requested = lengthFrames ?? toCutEnd;
    _controllers.timelineController.createDrawingFrameForLayer(
      layerId: layer.id,
      frameId: _frameIds.mintFrameId(layer.id),
      length: requested < 1 ? 1 : requested,
      name: name,
      seName: seName,
    );
    _changes.notifyChanged();
  }

  /// SE rows: updates the selected entry's dialogue (Frame.name), speaker
  /// name and delivery (I-20) in ONE undo step. Duplicates are allowed — the
  /// same dialogue can legitimately repeat on a sheet.
  void updateSelectedSeEntry({
    required String dialogue,
    String? seName,
    required SeLineType seType,
  }) {
    final layer = _selection.activeLayer;
    final frame = _selection.selectedFrame;
    if (layer == null ||
        frame == null ||
        !_frameVerbs.canRenameFrameAtCurrentFrame) {
      return;
    }
    updateSeEntryForLayer(
      layer.id,
      frame.id,
      dialogue: dialogue,
      fields: (seName: seName, seType: seType),
    );
  }

  /// The same edit addressed by ROW + ENTRY instead of by standing (B6
  /// 2026-08-17): the storyboard's SE editor commits here, because that
  /// rail's standing row never moves the drawing target (유저 2026-07-27)
  /// and so [_selection.activeLayer]/[_selection.selectedFrame] cannot carry its answer. The
  /// timeline's [updateSelectedSeEntry] funnels into this too — one commit
  /// body, two addressings.
  void updateSeEntryForLayer(
    LayerId layerId,
    FrameId frameId, {
    required String dialogue,
    required SeEntryFields fields,
  }) {
    final layer = requireLayerAnywhere(
      _project.repository.requireProject(),
      layerId,
    );
    if (layer.kind != LayerKind.se) {
      return;
    }
    _controllers.timelineController.renameFrameForLayer(
      layerId: layerId,
      frameId: frameId,
      name: dialogue,
      allowDuplicateName: true,
      seEntry: fields,
    );
    _changes.notifyChanged();
  }
}
