import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/project.dart';

/// Folder CREATION mirroring over 겸용 (linked) cuts: making a folder
/// around a set of layers makes the same folder around their counterparts,
/// because folder existence and membership are shared structure.
///
/// Everything AFTER creation rides the ordinary layer machinery: the folder
/// row is a layer, so its name mirrors through its own link-registry group
/// while its eye, static opacity, blend, FX lanes and twirl stay per-use —
/// the display three since T9 (유저 확정 2026-08-13), which retired 「레인만
/// 각자, 나머지는 하나」. No folder-specific mirror table survives.

/// The OTHER cuts where [memberLayerIds]'s new folder must also appear,
/// with each member resolved to its linked counterpart there. A cut
/// qualifies only when EVERY member has a counterpart in it (겸용 cuts
/// always do — partial matches mean the structure diverged, so we stand
/// down rather than guess).
List<({CutId cutId, Map<LayerId, LayerId> counterpartOf})> folderMirrorCuts(
  Project project, {
  required CutId cutId,
  required List<LayerId> memberLayerIds,
}) {
  if (memberLayerIds.isEmpty) {
    return const [];
  }
  // cut → (source member → counterpart) for every OTHER cut any member
  // links into.
  final byCut = <CutId, Map<LayerId, LayerId>>{};
  for (final memberId in memberLayerIds) {
    final group = project.linkRegistry.groupOf(
      cutId: cutId,
      layerId: memberId,
    );
    if (group == null) {
      continue;
    }
    for (final member in group.members) {
      if (member.cutId == cutId) {
        continue;
      }
      byCut.putIfAbsent(member.cutId, () => {})[memberId] = member.layerId;
    }
  }
  return [
    for (final entry in byCut.entries)
      if (entry.value.length == memberLayerIds.length)
        (cutId: entry.key, counterpartOf: entry.value),
  ];
}
