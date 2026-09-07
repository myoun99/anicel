import 'package:flutter/foundation.dart';
import '../../models/layer_folder.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/timeline_exposure.dart';
import '../timeline/property_lane_model.dart' show folderAggregateRuns;
import 'session_roles.dart';

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
  /// `timeline` IS its subtree's exposure union.
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
      final runs = folderAggregateRuns(members);
      final cached = _folderBandCache[layer.id];
      // The FOLDER's own instance is half the key: the repository hands back
      // the same instance while nothing about the folder changed, and a new
      // one the moment anything did.
      if (cached != null &&
          identical(cached.source, layer) &&
          listEquals(cached.runs, runs)) {
        continue;
      }
      _folderBandCache[layer.id] = (
        runs: runs,
        source: layer,
        band: layer.copyWith(
          timeline: {
            for (final run in runs)
              run.start: TimelineExposure.drawing(
                // The union's entries are AUTHORED, not ghosts, and they
                // resolve to no Frame on purpose: nothing composites a
                // folder band, it only paints.
                FrameId('band:${layer.id.value}:${run.start}'),
                length: run.endExclusive - run.start,
              ),
          },
        ),
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

  /// The folder's merged exposure runs — the range selection's snap lane.
  List<({int start, int endExclusive})> folderBandRunsOf(LayerId folderId) {
    _fillFolderBandCache();
    return _folderBandCache[folderId]?.runs ?? const [];
  }
}
