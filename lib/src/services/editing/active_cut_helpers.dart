import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../project_lookup.dart';

/// The cut a session born for [project] stands on: the first cut of the
/// first video track that has one, else of any track — or null for a
/// project with no cut at all, which opens on its gap as a track the last
/// cut was deleted from stands (R28 #14: 「컷도 1개도 없는 상황 허용」).
///
/// ↩️It threw 「Project has no cuts」, so no session could be born for such
/// a project — one made for a file brought in as a new project, before its
/// file lands (I-156), among them.
CutId? defaultActiveCutIdFor(Project project) {
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

  return null;
}

/// The track owning [cutId], or `null` when no track holds it.
TrackId? trackIdOfCut(Project project, CutId? cutId) =>
    cutId == null ? null : cutPositionOf(project, cutId)?.trackId;
