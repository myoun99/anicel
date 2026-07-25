import '../../models/brush_group.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';

/// Moves [movedId] to [targetGroupId], inserting before [insertBeforeId]
/// (which must already sit in [targetGroupId]) or appending after the group's
/// last member when no anchor is given. A `null` [targetGroupId] is the
/// root (ungrouped) section.
///
/// Pure list computation shared by the panel's drag-reorder handler so the
/// group-membership rules stay testable without widget drags. Returns the
/// original list when [movedId] is absent.
List<BrushPreset> moveBrushPresetInLibrary({
  required List<BrushPreset> presets,
  required BrushPresetId movedId,
  required BrushGroupId? targetGroupId,
  BrushPresetId? insertBeforeId,
}) {
  final movedIndex = presets.indexWhere((preset) => preset.id == movedId);
  if (movedIndex < 0) {
    return presets;
  }

  final moved = presets[movedIndex].copyWith(groupId: targetGroupId);
  final remaining = [
    for (final preset in presets)
      if (preset.id != movedId) preset,
  ];

  int insertIndex;
  if (insertBeforeId != null) {
    insertIndex = remaining.indexWhere((preset) => preset.id == insertBeforeId);
    if (insertIndex < 0) {
      insertIndex = remaining.length;
    }
  } else {
    final lastInGroup = remaining.lastIndexWhere(
      (preset) => preset.groupId == targetGroupId,
    );
    insertIndex = lastInGroup >= 0 ? lastInGroup + 1 : remaining.length;
  }

  return List<BrushPreset>.unmodifiable([
    ...remaining.take(insertIndex),
    moved,
    ...remaining.skip(insertIndex),
  ]);
}

/// Moves the group [movedId] before [insertBeforeId], or to the end of the
/// list when no anchor is given.
///
/// Group order is the library's display order all by itself, so reordering
/// groups never touches the preset list — the members ride along by id.
/// Returns the original list when [movedId] is absent.
List<BrushGroup> moveBrushGroupInLibrary({
  required List<BrushGroup> groups,
  required BrushGroupId movedId,
  BrushGroupId? insertBeforeId,
}) {
  final movedIndex = groups.indexWhere((group) => group.id == movedId);
  if (movedIndex < 0) {
    return groups;
  }

  final moved = groups[movedIndex];
  final remaining = [
    for (final group in groups)
      if (group.id != movedId) group,
  ];

  var insertIndex = remaining.length;
  if (insertBeforeId != null) {
    final anchorIndex = remaining.indexWhere(
      (group) => group.id == insertBeforeId,
    );
    if (anchorIndex >= 0) {
      insertIndex = anchorIndex;
    }
  }

  return List<BrushGroup>.unmodifiable([
    ...remaining.take(insertIndex),
    moved,
    ...remaining.skip(insertIndex),
  ]);
}
