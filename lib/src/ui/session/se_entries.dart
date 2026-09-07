import '../../services/project_lookup.dart' show requireLayerAnywhere;
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/se_name_tag.dart';
import '../../services/se_name_tag_plan.dart';
import '../../models/storyboard_timeline_layout.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'camera.dart';
import 'frame_verbs.dart';
import 'track_se_display.dart';

/// The SE ENTRIES AND NAME TAGS — creating and updating an SE entry, and
/// the name tag an SE row carries at a frame — as their own object.
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
    required TrackSeDisplay trackSe,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _camera = camera,
       _frameVerbs = frameVerbs,
       _trackSe = trackSe;

  final Camera _camera;
  final FrameVerbs _frameVerbs;
  final TrackSeDisplay _trackSe;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;

  /// Whether the active row can carry an on-canvas name tag (R5b): the
  /// SE rows, and only while a cut gives the canvas its geometry.
  bool get canEditActiveSeNameTag =>
      _selection.activeLayer?.kind == LayerKind.se &&
      _project.activeCutOrNull != null;

  /// Sets (or with null resets) the active SE row's name tag — one undo,
  /// reaching the TRACK-owned row through the anywhere seam.
  void setActiveSeNameTag(SeNameTag? tag) {
    final layer = _selection.activeLayer;
    if (layer == null || layer.kind != LayerKind.se) {
      return;
    }
    _project.cutCommandCoordinator.setSeNameTag(
      layerId: layer.id,
      seNameTag: tag,
    );
    _changes.notifyChanged();
  }

  /// A NAME TAG lane edit landing on [layerId] (R5 #7) — one undo.
  ///
  /// The tag's keys sit on the track-owned row's GLOBAL axis while the lane
  /// was read off a cut-local clone, so the frames convert on the way out,
  /// exactly as the transform track's do (#8). The lane helpers key at
  /// whatever frame the caller hands them, so the conversion belongs HERE —
  /// after the edit, before the commit.
  void setSeNameTagForLayer(LayerId layerId, SeNameTag? tag) {
    final keys = tag?.track;
    _project.cutCommandCoordinator.setSeNameTag(
      layerId: layerId,
      seNameTag: keys == null || !_project.isTrackSeLayerId(layerId)
          ? tag
          : tag!.copyWith(
              track: _trackSe.trackSeWindow.globalSeNameTagTrack(keys),
            ),
    );
    _changes.notifyChanged();
  }

  /// The ON-CANVAS name tags for a cut's local frame (R5b, §6-z15) — the
  /// one resolution every drawing surface asks (editing canvas, playback,
  /// the parked stack, export), so none of them can disagree. Works for
  /// ANY cut, not just the active one: it walks the owning track's global
  /// SE rows and converts through that cut's start.
  List<ResolvedSeNameTag> seNameTagsForCutFrame(Cut cut, int localFrameIndex) {
    // The over-end runway is a CLIPPED VIEW of the cut (UI-R9 #4): a
    // playhead past the last frame must never address the NEIGHBOUR
    // cut's SE window and put the next speaker over this picture. The
    // scrub preview already clamps this way, so drag and release agree.
    final maxLocal = cut.duration > 0 ? cut.duration - 1 : 0;
    final localFrame = localFrameIndex > maxLocal ? maxLocal : localFrameIndex;
    final project = _project.repository.requireProject();
    // Rows on the tracks BELOW this one: unconfigured defaults stack the
    // whole project's SE rows, so two covered tracks in the multitrack
    // stack never land on the same spot.
    var rowOffset = 0;
    for (final track in project.tracks) {
      // Cheap gate: most tracks hold no SE writing at all, and this runs
      // per painted frame per covered track.
      if (track.seLayers.isNotEmpty) {
        final start = cutGlobalStartFrameIn(track, cut.id);
        if (start != null) {
          return resolveSeNameTagsAt(
            trackSeLayers: track.seLayers,
            cutStartFrame: start,
            localFrameIndex: localFrame,
            canvas: cut.canvasSize,
            cameraFrame: _camera.cameraFrameSize,
            rowOffset: rowOffset,
          );
        }
      }
      rowOffset += track.seLayers.length;
    }
    return const [];
  }

  /// SE rows: the selected entry's speaker/effect name (the accent box).
  String? get selectedFrameSeName => _selection.selectedFrame?.seName;

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

  /// SE rows: updates the selected entry's dialogue (Frame.name) and
  /// speaker name in ONE undo step. Duplicates are allowed — the same
  /// dialogue can legitimately repeat on a sheet.
  void updateSelectedSeEntry({required String dialogue, String? seName}) {
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
      seName: seName,
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
    String? seName,
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
      seName: seName,
      updateSeName: true,
    );
    _changes.notifyChanged();
  }
}
