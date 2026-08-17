import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/media_asset.dart';
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
/// [requireLayerAnywhere] that answers null instead of throwing — for the
/// read paths (the storyboard's row-addressed editors) where a stale id is
/// a no-op, not a crash.
Layer? layerAnywhereOrNull(Project project, LayerId layerId) {
  for (final track in project.tracks) {
    for (final layer in track.seLayers) {
      if (layer.id == layerId) {
        return layer;
      }
    }
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
  return null;
}

Layer requireLayerAnywhere(Project project, LayerId layerId) {
  // The TRANSITION row is track-owned too, and it reaches a cut's row
  // list as a display clone — so an id arriving here from the rows the
  // user can see may well be that one; [layerAnywhereOrNull] walks them all.
  final layer = layerAnywhereOrNull(project, layerId);
  if (layer == null) {
    throw StateError('Layer not found: $layerId');
  }
  return layer;
}

/// Every path in [project] the audio conform can serve: the SE clips, which
/// are sound by construction, plus the media pool entries whose kind says
/// they are.
///
/// The kind filter is the whole point. The pool registers movies, stills and
/// PDFs too, and a conform request reads the WHOLE file into a `Uint8List`
/// before the decoder is handed anything to look at
/// (`audio_conform_pipeline.dart`'s `readAsBytesSync`) — so warming a pool
/// blind meant a 3GB reference video was read into memory on every project
/// open, and again on every frame-rate or sample-rate change, only to be
/// rejected for a reason its extension already gave away.
Set<String> projectAudioSourcePaths(Project project) => {
  for (final track in project.tracks)
    for (final layer in track.seLayers)
      for (final clip in layer.audioClips) clip.filePath,
  for (final asset in project.mediaAssets)
    if (asset.kind == MediaAssetKind.audio) asset.path,
};

/// Whether an asset of this [kind] is carried by DEFAULT.
///
/// Blender's rule as the starting point (user decision 2026-08-13): images
/// and sounds pack, video does not — a reference movie can be three
/// gigabytes, while a sound the project does not carry is a sound that
/// goes missing the first time someone moves a folder.
///
/// 🚨 It was a CEILING until 2026-08-14 and is now only a default (user
/// decision, same round as the video decoder): *"비디오도 그냥 유저가
/// 선택하게 하면 좋을거같은데. 참조만 강요하는게아니라."* A movie that a
/// person deliberately wants inside the file — a three-second reference
/// take, a trimmed clip — was refused by a rule that could not hear them.
///
/// What the ceiling protected against did not go away, it moved: the
/// import window says what carrying a file is about to cost, by name and
/// by size, BEFORE it costs it ([largeCarriedAssetBytes]). A warning the
/// user can answer beats a refusal they cannot.
///
/// A PREDICATE rather than a switch at each call site, so the next kind
/// answers here once instead of in every save path
/// ([[predicates-before-new-kind]]).
bool mediaKindCarriedByDefault(MediaAssetKind kind) => switch (kind) {
  MediaAssetKind.audio || MediaAssetKind.image || MediaAssetKind.pdf => true,
  MediaAssetKind.video => false,
};

/// The size at which carrying a file is worth saying out loud.
///
/// Dialogue audio runs to a few megabytes and a scanned timesheet
/// likewise, a storyboard PDF to a few tens — so this sits well clear of
/// ordinary work and catches the accident instead: the several-hundred-
/// megabyte master somebody meant to reference, doubling the project
/// without a word about it.
///
/// A WARNING and never a refusal (user direction). It is their file and
/// their disk; what they need is to know before the save, not to be
/// stopped at the door.
const int largeCarriedAssetBytes = 100 * 1024 * 1024;

/// Every pool path whose bytes the project should carry.
///
/// TWO questions, and both have to say yes. The KIND sets the ceiling —
/// video is never carried, whatever anyone picked — and the asset's own
/// [MediaAsset.carried] chooses underneath it, which is where the import
/// window's copy-or-reference answer lives. A sound left outside on
/// purpose, because the original is shared with another tool, stays
/// outside.
///
/// ⚠️ The POOL only. SE clips reference audio by path and are warmed by
/// [projectAudioSourcePaths], but a clip is not a registration — what the
/// project stores is what the pool holds, and a clip pointing at an
/// unregistered file stays a reference like any other.
Set<String> projectArchivedMediaPaths(Project project) => {
  // `carried` is the whole answer now. It used to be ANDed with the kind,
  // which meant a movie the user had explicitly asked the project to hold
  // was dropped on the way to the archive — the flag said yes and the save
  // said no, with nothing on screen explaining the disagreement.
  for (final asset in project.mediaAssets)
    if (asset.carried) asset.path,
};
