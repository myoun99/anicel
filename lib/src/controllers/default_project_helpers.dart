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
