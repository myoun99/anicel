import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../project_lookup.dart';

CutId defaultActiveCutIdFor(Project project) {
  for (final track in project.tracks) {
    if (track.type != TrackType.video) {
      continue;
    }

    if (track.cuts.isNotEmpty) {
      return track.cuts.first.id;
    }
  }

  for (final track in project.tracks) {
    if (track.cuts.isNotEmpty) {
      return track.cuts.first.id;
    }
  }

  throw StateError('Project has no cuts.');
}

/// The track owning [cutId], or `null` when no track holds it.
TrackId? trackIdOfCut(Project project, CutId? cutId) =>
    cutId == null ? null : cutPositionOf(project, cutId)?.trackId;
