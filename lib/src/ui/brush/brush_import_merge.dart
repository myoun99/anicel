import '../../models/brush_group.dart';
import '../../models/brush_preset.dart';
import '../../services/brush_preset_file_service.dart';
import '../../services/brush_preset_id_mint.dart';

/// Folds a freshly decoded brush import into [library].
///
/// The imported brushes land in a group of their own named after the source
/// file (Clip Studio's sub-tool groups). The group's id is derived from that
/// name, so importing the same file again finds the same group — which keeps
/// whatever name and fold state the user gave it meanwhile.
///
/// 🚨AN IMPORT ONLY ADDS (유저 F-433, 2026-10-21: 「기존 같은 이름? 브러시인지
/// 다른 브러시인지 삭제되는데, 그러지 않도록」 · 「같은이름 존재가능」).
/// ↩️Re-importing a file used to REPLACE its group's contents, and a brush
/// whose id the library already held lost to the incoming copy wherever it
/// stood — so a pack exported from an edited built-in took the built-in
/// with it. Now everything already there stays where it is, and an incoming
/// id the library already holds is minted afresh by the one mint
/// ([BrushPresetIdMint]); two presets still never share an id (ids key the
/// rows).
BrushPresetLibraryData mergeImportedBrushPresets({
  required BrushPresetLibraryData library,
  required List<BrushPreset> imported,
  required String sourceName,
}) {
  final groupId = importedBrushGroupId(sourceName);
  final mint = BrushPresetIdMint(
    taken: [for (final preset in library.presets) preset.id.value],
  );
  final landed = [
    for (final preset in imported)
      preset.copyWith(id: mint.next(preset.id.value), groupId: groupId),
  ];
  final groups = library.groups.any((group) => group.id == groupId)
      ? library.groups
      : [...library.groups, BrushGroup(id: groupId, name: sourceName)];
  return (groups: groups, presets: [...library.presets, ...landed]);
}
