import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/project.dart';
import '../models/track.dart';

/// Read-only lookups into the `Project` -> `Track` -> `Cut` -> `Layer`
/// hierarchy, shared by the edit commands and coordinator that previously each
/// carried a private copy of the same track/cut walk.

/// Returns the cut matching [cutId] anywhere in [project]. Throws a [StateError]
/// if no cut matches.
Cut requireCut(Project project, CutId cutId) {
  for (final track in project.tracks) {
    for (final cut in track.cuts) {
      if (cut.id == cutId) {
        return cut;
      }
    }
  }

  throw StateError('Cut not found: $cutId');
}

/// Returns the track containing the cut matching [cutId]. Throws a
/// [StateError] if no track holds it.
Track requireTrackOfCut(Project project, CutId cutId) {
  for (final track in project.tracks) {
    for (final cut in track.cuts) {
      if (cut.id == cutId) {
        return track;
      }
    }
  }

  throw StateError('No track holds cut: $cutId');
}

/// Returns the layer matching [layerId] within the cut matching [cutId]. Throws
/// a [StateError] if the cut or the layer is missing.
Layer requireLayer(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
}) {
  final cut = requireCut(project, cutId);
  for (final layer in cut.layers) {
    if (layer.id == layerId) {
      return layer;
    }
  }

  throw StateError('Layer not found in cut $cutId: $layerId');
}

/// The cut holding [layerId], or null for track-owned SE rows (and
/// unknown ids). Layer ids are globally unique.
CutId? cutIdOfLayer(Project project, LayerId layerId) {
  for (final track in project.tracks) {
    for (final cut in track.cuts) {
      for (final layer in cut.layers) {
        if (layer.id == layerId) {
          return cut.id;
        }
      }
    }
  }
  return null;
}

/// Returns the layer matching [layerId] anywhere in [project] — cut layers
/// AND the tracks' track-owned SE rows (the same reach as the repository's
/// updateLayerAnywhere seam). Layer ids are globally unique, so the flag
/// commands (mark/timesheet/fill-reference) resolve through this instead of
/// the cut-scoped [requireLayer], which track SE rows are not in.
Layer requireLayerAnywhere(Project project, LayerId layerId) {
  for (final track in project.tracks) {
    for (final layer in track.seLayers) {
      if (layer.id == layerId) {
        return layer;
      }
    }
    // The TRANSITION row is track-owned too, and it reaches a cut's row
    // list as a display clone — so an id arriving here from the rows the
    // user can see may well be this one.
    if (track.transitionLayer.id == layerId) {
      return track.transitionLayer;
    }
    for (final cut in track.cuts) {
      for (final layer in cut.layers) {
        if (layer.id == layerId) {
          return layer;
        }
      }
    }
  }

  throw StateError('Layer not found: $layerId');
}
