import '../../models/brush_group.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../../services/brush_preset_file_service.dart';
import '../../services/brush_preset_id_mint.dart';

/// A brush import folded into the library, and where each brush of the file
/// landed: the id the file gave it → the id it holds in the library.
typedef BrushImportLanding = ({
  BrushPresetLibraryData library,
  Map<String, BrushPresetId> landedAs,
});

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
BrushImportLanding mergeImportedBrushPresets({
  required BrushPresetLibraryData library,
  required List<BrushPreset> imported,
  required String sourceName,
}) {
  final groupId = importedBrushGroupId(sourceName);
  final mint = BrushPresetIdMint(
    taken: [for (final preset in library.presets) preset.id.value],
  );
  final landedAs = <String, BrushPresetId>{};
  final landed = [
    for (final preset in imported)
      preset.copyWith(
        id: _landing(landedAs, preset.id.value, mint),
        groupId: groupId,
      ),
  ];
  final groups = library.groups.any((group) => group.id == groupId)
      ? library.groups
      : [...library.groups, BrushGroup(id: groupId, name: sourceName)];
  return (
    library: (groups: groups, presets: [...library.presets, ...landed]),
    landedAs: landedAs,
  );
}

/// The id the brush the file calls [inFile] lands under, written into
/// [landedAs] — the first brush of an id keeps the answer, since a file
/// that gives two brushes one id cannot say which its settings are for.
BrushPresetId _landing(
  Map<String, BrushPresetId> landedAs,
  String inFile,
  BrushPresetIdMint mint,
) {
  final id = mint.next(inFile);
  landedAs.putIfAbsent(inFile, () => id);
  return id;
}
