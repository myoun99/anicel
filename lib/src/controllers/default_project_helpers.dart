import '../models/app_workspace_colors.dart';
import '../models/cut_id.dart';
import '../models/layer_section_defaults.dart';
import '../models/project.dart';
import '../models/project_id.dart';
import '../models/track.dart';
import '../models/track_id.dart';
import '../services/editing/default_cut_helpers.dart';
import '../services/editing/default_layer_helpers.dart';

Project createDefaultProject({DateTime? createdAt}) {
  return Project(
    id: const ProjectId('default-project'),
    name: 'Untitled Project',
    createdAt: createdAt ?? DateTime.now().toUtc(),
    tracks: [createDefaultTrack()],
  );
}

/// A NEW project — the one the app opens with and the one New Project opens
/// in a tab of its own (I-7): the default project under an id no other open
/// project has, its pasteboard seeded from the app-level default (all that
/// remains of the old app-state pasteboard — R3b promotion, R28 #9
/// reversed: the colour is project data now, and this is where「the default
/// for the next project」lands in one).
Project newUntitledProject() {
  final now = DateTime.now().toUtc();
  return createDefaultProject(createdAt: now).copyWith(
    id: ProjectId('project-${now.microsecondsSinceEpoch}-${_minted++}'),
    pasteboardArgb: AppWorkspaceColors.settings.value.pasteboardArgb,
  );
}

int _minted = 0;

Track createDefaultTrack({
  TrackId trackId = const TrackId('default-track'),
  String name = 'Track 1',
}) {
  return Track(
    id: trackId,
    name: name,
    cuts: [
      createDefaultCut(
        cutId: const CutId('default-cut-1'),
        // Bare numbers, the sheet convention (UI-R7 #3): cuts are '1',
        // '2', … — displays add no prefix.
        name: '1',
        layerId: defaultLayerIdForSequence(1),
      ),
    ],
    // The timesheet's SE rows are TRACK fixtures (global frame axis).
    seLayers: [
      createTrackSeLayer(trackId: trackId, slot: 1),
      createTrackSeLayer(trackId: trackId, slot: 2),
    ],
  );
}
