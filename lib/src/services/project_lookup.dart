import '../models/attached_layer_resolve.dart';
import '../models/cel_bank_lanes.dart';
import '../models/cut.dart';
import '../models/track_id.dart';
import '../models/cut_id.dart';
import '../models/layer.dart';
import '../models/layer_id.dart';
import '../models/media_asset.dart';
import '../models/project.dart';
import '../models/timeline_exposure.dart';
import '../models/track.dart';

/// Read-only lookups into the `Project` -> `Track` -> `Cut` -> `Layer`
/// hierarchy, shared by the edit commands and coordinator that previously each
/// carried a private copy of the same track/cut walk.

/// Where a cut lives: the track holding it and its INDEX in that track.
///
/// Everything else a caller asks about a cut's place is a projection of
/// those two — the track id, the cut itself, how many cuts the track has.
/// Reorder needs the index, delete needs the index and the neighbour,
/// every other caller needs the track or the cut, and they are all one
/// find.
class CutPosition {
  const CutPosition({required this.track, required this.cutIndex});

  final Track track;
  final int cutIndex;

  TrackId get trackId => track.id;
  Cut get cut => track.cuts[cutIndex];
  CutId get cutId => cut.id;
  int get cutCount => track.cuts.length;
}

/// Where the cut with [cutId] lives, or null when no track holds it.
///
/// THE ONE WALK. The cut, its track and its index are three projections of
/// the same find, not three finds: a caller that needs several takes them
/// from one answer.
CutPosition? cutPositionOf(Project project, CutId cutId) {
  for (final track in project.tracks) {
    final cutIndex = track.cuts.indexWhere((cut) => cut.id == cutId);
    if (cutIndex != -1) {
      return CutPosition(track: track, cutIndex: cutIndex);
    }
  }
  return null;
}

/// [cutPositionOf], throwing a [StateError] when no cut matches.
CutPosition requireCutPosition(Project project, CutId cutId) =>
    cutPositionOf(project, cutId) ??
    (throw StateError('Cut not found: $cutId'));

/// Returns the cut matching [cutId] anywhere in [project]. Throws a [StateError]
/// if no cut matches.
Cut requireCut(Project project, CutId cutId) =>
    requireCutPosition(project, cutId).cut;

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

/// The whole ATTACH GROUP [layerId] belongs to, inside [cutId]'s cut —
/// with the track and cut that were walked to find it.
///
/// 🚨ONE LAW, and it had been written twice. Both link-group commands
/// (링크 복제 and 독립시키기) opened with the same eight lines: find the
/// cut, find the layer, resolve its attach BASE, take the group slice,
/// and throw when the slice comes back empty. Neither of them is about
/// resolving a group — they are about what to do with one — and a second
/// copy of a lookup that throws is where the two messages drift.
///
/// ⚠️A group is never legitimately empty: [attachBaseIdOf] answers the
/// layer's own id when it is not attached to anything, so the slice
/// always holds at least that layer. An empty one means the base names a
/// layer this cut does not have.
({Track track, Cut cut, LayerId baseId, List<Layer> members})
requireAttachedGroup(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
}) {
  final position = requireCutPosition(project, cutId);
  final source = requireLayer(project, cutId: cutId, layerId: layerId);
  final baseId = attachBaseIdOf(source);
  final members = attachedGroupSlice(baseId, position.cut.layers);
  if (members.isEmpty) {
    throw StateError('Attach base not found: $baseId');
  }
  return (
    track: position.track,
    cut: position.cut,
    baseId: baseId,
    members: members,
  );
}

/// The exposure BLOCK starting at [blockStartIndex] on [layer] — the one a
/// memo is addressed to. Throws when no block starts there, and when the
/// cell is a GHOST: a ghost exposure is rederived by the run pass, so a
/// memo written on it would be gone on the next derive. The repository's
/// write and the coordinator's pre-history check both ask this before
/// touching a memo, in these words.
TimelineExposure requireMemoBlockAt(Layer layer, int blockStartIndex) {
  final entry = layer.timeline[blockStartIndex];
  if (entry == null || !entry.isDrawing) {
    throw StateError(
      'No exposure block starts at $blockStartIndex on ${layer.id}.',
    );
  }
  if (entry.ghost) {
    throw StateError(
      'A ghost exposure is rederived, so it cannot hold a memo '
      '(${layer.id} at $blockStartIndex).',
    );
  }
  return entry;
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

/// The lanes of every OTHER use of ([cutId], [layerId])'s cel bank — its
/// 겸용 siblings in other cuts and its link-duplicated twins in its own —
/// or [CelBankLanes.unshared] when the row is not linked (F-136).
CelBankLanes celBankLanesOf(
  Project project, {
  required CutId cutId,
  required LayerId layerId,
}) {
  final group = project.linkRegistry.groupOf(cutId: cutId, layerId: layerId);
  if (group == null) {
    return CelBankLanes.unshared;
  }
  return CelBankLanes([
    for (final member in group.members)
      if (member.cutId != cutId || member.layerId != layerId)
        requireLayer(
          project,
          cutId: member.cutId,
          layerId: member.layerId,
        ).timeline,
  ]);
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
  for (final layer in projectLayersAnywhere(project)) {
    if (layer.id == layerId) {
      return layer;
    }
  }
  return null;
}

/// Every layer [project] holds, wherever it lives: each track's own SE
/// rows, its transition row, then every cut's layers — in that order, which
/// is the order [layerAnywhereOrNull] finds by.
///
/// 🚨★★★ONE WALK FOR 「every layer in the project」 (F-131, 2026-09-15). It
/// was written out three times — finding a layer by id, collecting the ids
/// in use, editing a layer by id — and the collecting one walked CUT layers
/// only. So a new row could be minted the id of a track SE row (both come
/// from the same `default-layer-N` counter, which restarts every session),
/// and the finder, which checks SE rows first, then sent the new row's
/// writes to the SE row: frames and an attach arrow appeared on S3. The
/// finder and the collector read this walk now. [updateLayerAnywhere]
/// rebuilds the tree and cannot, so its reach is pinned against this walk
/// by test.
Iterable<Layer> projectLayersAnywhere(Project project) sync* {
  for (final track in project.tracks) {
    yield* track.seLayers;
    yield track.transitionLayer;
    for (final cut in track.cuts) {
      yield* cut.layers;
    }
  }
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

/// Whether a file of this [kind] can hold sound at all.
///
/// 🚨★★★**A MOVIE HAS A SOUNDTRACK. A STILL DOES NOT.** That is a fact about
/// the formats, not a preference — a PNG has nowhere to put an audio track —
/// and it is the whole rule behind which pool entries the conform is offered.
///
/// 🪦What stood here before was `kind == audio`, and it was a SCAR. A conform
/// used to read the whole container into a `Uint8List` before any decoder
/// saw it, so warming a pool blind meant a 3GB reference video read into
/// memory on every project open — the filter made that stop, and it also
/// made a movie's sound unreachable. 「The importer cannot see video audio」
/// stood as a bug for months while its cause sat here looking like a
/// decision. The cause is gone: the decoder takes a path plus a span
/// ([MediaByteSource.range]), and the identity check in front of it streams.
///
/// ⛔Dropping the filter ENTIRELY was the first attempt and it was wrong in
/// the other direction: a still with no conform can never match one, so
/// every open would fingerprint every PNG and PDF in the pool, forever, to
/// learn what its format already says. A predicate rather than the old
/// inline test, so a new kind has to answer this instead of inheriting an
/// answer nobody chose for it.
bool mediaKindCanCarrySound(MediaAssetKind kind) => switch (kind) {
  MediaAssetKind.audio || MediaAssetKind.video => true,
  MediaAssetKind.image || MediaAssetKind.pdf => false,
};

/// Every path in [project] the audio conform can serve: the SE clips, which
/// are sound by construction, plus the pool entries whose kind can hold it —
/// a movie among them, because a movie has a soundtrack.
Set<String> projectAudioSourcePaths(Project project) => {
  for (final track in project.tracks)
    for (final layer in track.seLayers)
      for (final clip in layer.audioClips) clip.filePath,
  for (final asset in project.mediaAssets)
    if (mediaKindCanCarrySound(asset.kind)) asset.path,
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
/// ONE question: the asset's own [MediaAsset.carried], where the import
/// window's copy-or-reference answer lives. The kind only chose the
/// DEFAULT of that answer at import ([mediaKindCarriedByDefault]) — the
/// old kind ceiling died 2026-08-14, see the decision there. A sound left
/// outside on purpose, because the original is shared with another tool,
/// stays outside.
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

/// Every layer id the project already holds, as raw strings.
///
/// The set a MINT is checked against: a counter alone cannot answer
/// "is this id free?", because the project can arrive from disk holding
/// ids the counter never issued. One walk, handed to a caller minting
/// many ids so it does not re-walk per id.
///
/// ⚠️The walk is [projectLayersAnywhere] — the tracks' SE and transition
/// rows included. Until F-131 this set held cut layers only, and a mint
/// checked against it could hand out an SE row's id.
Set<String> projectLayerIdValues(Project project) => {
  for (final layer in projectLayersAnywhere(project)) layer.id.value,
};
