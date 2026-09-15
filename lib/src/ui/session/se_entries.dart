import '../../services/project_lookup.dart' show requireLayerAnywhere;
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../services/se_name_tag_plan.dart';
import '../../models/storyboard_timeline_layout.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'camera.dart';
import 'frame_verbs.dart';

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
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _camera = camera,
       _frameVerbs = frameVerbs;

  final Camera _camera;
  final FrameVerbs _frameVerbs;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;

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
    // ⚠️MUTANT SURVIVES, equivalent (2026-09-08): `>` → `>=` clamps a frame
    // that already IS [maxLocal] to itself.
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
