import 'package:flutter/foundation.dart';
import '../../models/layer_folder.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timeline_run_behavior.dart';
import '../timeline/property_lane_model.dart'
    show folderAggregateRuns, folderGhostRuns;
import 'session_roles.dart';

/// [folder]'s row as the grids render it — its BAND: the folder carrying, as
/// an ordinary timeline, the blocks its [members] make together
/// ([folderAggregateRuns]) and, where none of them stands a block, the
/// ghosts they project ([folderGhostRuns]).
///
/// Its entries resolve to no Frame on purpose: nothing composites a folder
/// band, it only paints. A ghost is stamped the way a row's own is, so the
/// shared cells painter draws a hold's dash here as it does there. The
/// stamp's SIDE is the row's business — a band paints the mode, and
/// nothing reads its side.
Layer folderBandOf(Layer folder, Iterable<Layer> members) {
  final runs = folderAggregateRuns(members);
  FrameId celAt(int start) => FrameId('band:${folder.id.value}:$start');
  return folder.copyWith(
    timeline: {
      for (final run in runs)
        run.start: TimelineExposure.drawing(
          celAt(run.start),
          length: run.endExclusive - run.start,
        ),
      for (final ghost in folderGhostRuns(members, runs))
        ghost.start: TimelineExposure.drawing(
          celAt(ghost.start),
          length: ghost.endExclusive - ghost.start,
          ghostOf: TimelineRunEdgeGhost(
            side: TimelineRunEdgeSide.end,
            mode: ghost.mode,
          ),
        ),
    },
  );
}

/// The bands of the folders of [stack] that hold a row [shown] shows moved
/// — each as the band its rows make where the drag has them. A folder's row
/// is what its rows hold (F-311), so it follows the hand as they do.
Map<LayerId, Layer> folderBandsFollowing(
  List<Layer> stack,
  Map<LayerId, Layer> shown,
) {
  final index = LayerFolderIndex(stack);
  return {
    for (final folder in stack)
      if (folder.kind.groupsLayers)
        if (index.subtreeMembersOf(folder.id) case final members
            when members.any((member) => shown.containsKey(member.id)))
          folder.id: folderBandOf(folder, [
            for (final member in members) shown[member.id] ?? member,
          ]),
  };
}

/// The FOLDER BANDS — which layer a folder's band stands on, who its members
/// are and which runs it shows — as a cache that knows what it was built
/// from and rebuilds only when the layer list changes.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: three fields of its own and one
/// session member read (`layers`). It names the roles it needs in its constructor.
class FolderBands {
  FolderBands({required ProjectAccess project}) : _project = project;

  final ProjectAccess _project;

  /// The folder BAND cache (R10): a folder row's display clone, whose
  /// `timeline` IS its subtree's exposure union ([folderBandOf]).
  ///
  /// A folder Layer is empty — no frames, no timeline — so handing it to
  /// the shared cells painter paints a blank row, which is exactly what
  /// the X-sheet has been doing all along. Giving the clone the union as
  /// an ordinary timeline is what lets a folder row BE a cells row: the
  /// coverage question answers in O(log runs) off the standard raw value,
  /// with no per-cell walk and no new painter input.
  ///
  /// Identity is the whole point, and the same reason [_seDisplayCloneCache]
  /// exists: repaint, the tile bake key and the row memo all compare the
  /// Layer INSTANCE, and a folder's own instance does not move when a
  /// member is edited. Same union ⇒ the same clone back, so nothing
  /// re-records; a changed union ⇒ a new instance, so everything does.
  ///
  /// R5 #2: the key is the union AND the folder itself. The union alone was
  /// a cache key for the BAND, and the band is what this was written for —
  /// but the clone the rails render is the whole ROW, so every folder field
  /// that is not an exposure rode a key that could not see it change.
  /// Collapsing a folder, renaming it, picking a blend, flipping its eye:
  /// none of those move a member's exposure, so `listEquals` said "same"
  /// and handed back the clone from BEFORE the edit, forever. The rail row
  /// memo then compared that stale clone's fields and skipped its rebuild,
  /// which is why the twirl and the blend chip read as dead controls.
  /// A cache that stands in for a value must key on everything that value
  /// carries, not on the part it was built to summarise.
  final Map<
    LayerId,
    ({List<({int start, int endExclusive})> runs, Layer source, Layer band})
  >
  _folderBandCache = {};

  /// The stack the cache was filled from — a different stack identity means
  /// the members may have moved even where the runs did not.
  List<Layer>? _folderBandSource;

  final Map<LayerId, List<Layer>> _folderBandMembers = {};

  void _fillFolderBandCache() {
    final stack = _project.layers;
    if (identical(_folderBandSource, stack)) {
      return;
    }
    _folderBandSource = stack;
    _folderBandMembers.clear();
    final index = LayerFolderIndex(stack);
    for (final layer in stack) {
      if (!layer.kind.groupsLayers) {
        continue;
      }
      final members = index.subtreeMembersOf(layer.id);
      _folderBandMembers[layer.id] = members;
      final band = folderBandOf(layer, members);
      final cached = _folderBandCache[layer.id];
      // The FOLDER's own instance is half the key: the repository hands back
      // the same instance while nothing about the folder changed, and a new
      // one the moment anything did. The other half is everything the band
      // shows of its rows — the ghosts beside the blocks (F-311).
      if (cached != null &&
          identical(cached.source, layer) &&
          mapEquals(cached.band.timeline, band.timeline)) {
        continue;
      }
      _folderBandCache[layer.id] = (
        runs: [
          for (final entry in band.timeline.entries)
            if (!entry.value.ghost)
              (start: entry.key, endExclusive: entry.key + entry.value.length!),
        ],
        source: layer,
        band: band,
      );
    }
    _folderBandCache.removeWhere(
      (id, _) => !_folderBandMembers.containsKey(id),
    );
  }

  /// [folder]'s row as the grids should render it — the union band. Never
  /// leaves the display path: commands re-read the real layer by id.
  Layer folderBandLayerFor(Layer folder) {
    if (!folder.kind.groupsLayers) {
      return folder;
    }
    _fillFolderBandCache();
    return _folderBandCache[folder.id]?.band ?? folder;
  }

  /// The folder's subtree members — the empty-cel tint's union (R28 #11).
  List<Layer> folderBandMembersOf(LayerId folderId) {
    _fillFolderBandCache();
    return _folderBandMembers[folderId] ?? const [];
  }

  /// The folder's merged BLOCK runs — the range selection's snap lane, and
  /// what a drag on the row carries. No ghost is one (F-311).
  List<({int start, int endExclusive})> folderBandRunsOf(LayerId folderId) {
    _fillFolderBandCache();
    return _folderBandCache[folderId]?.runs ?? const [];
  }
}
