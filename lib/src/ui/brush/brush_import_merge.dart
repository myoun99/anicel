import '../../models/brush_group.dart';
import '../../models/brush_preset.dart';
import '../../services/brush_preset_file_service.dart';

/// Folds a freshly decoded brush import into [library].
///
/// The imported brushes land in a group of their own named after the source
/// file (Clip Studio's sub-tool groups). The group's id is derived from that
/// name, so re-importing the same file finds the same group and REPLACES its
/// contents — it does not pile up a second copy — while the group keeps
/// whatever name and fold state the user gave it meanwhile.
///
/// Two presets may never share an id (ids key the rows), so a preset that was
/// dragged OUT of the group before a re-import is replaced as well rather
/// than duplicated.
BrushPresetLibraryData mergeImportedBrushPresets({
  required BrushPresetLibraryData library,
  required List<BrushPreset> imported,
  required String sourceName,
}) {
  final groupId = importedBrushGroupId(sourceName);
  final grouped = [
    for (final preset in imported) preset.copyWith(groupId: groupId),
  ];
  final groups = library.groups.any((group) => group.id == groupId)
      ? library.groups
      : [...library.groups, BrushGroup(id: groupId, name: sourceName)];

  final importedIds = {for (final preset in grouped) preset.id};
  final presets = [
    for (final preset in library.presets)
      if (preset.groupId != groupId && !importedIds.contains(preset.id)) preset,
    ...grouped,
  ];
  return (groups: groups, presets: presets);
}
