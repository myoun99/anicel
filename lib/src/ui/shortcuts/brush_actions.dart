import '../../models/brush_group.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../brush/brush_press.dart';
import 'editor_action_registry.dart';

/// The category the brush library's rows stand under in the shortcut window.
const String brushActionCategory = 'Brushes';

/// The action that opens [group]'s tab.
String brushGroupActionId(BrushGroupId group) => 'brush-group-${group.value}';

/// The action that takes up [preset].
String brushPresetActionId(BrushPresetId preset) =>
    'brush-preset-${preset.value}';

/// Whether [actionId] names a brush or a brush group — whether or not the
/// library holds one of that id right now.
///
/// ⚠️A key recorded for a brush is kept by this, not by the brush being
/// there: the library loads after the settings do, and a brush that was
/// deleted can come back (an undo, the same pack imported again). Its entry
/// presses nothing while no brush carries the id.
bool isBrushActionId(String actionId) =>
    actionId.startsWith('brush-group-') ||
    actionId.startsWith('brush-preset-');

/// The brush library as shortcut rows (I-56), in the library's own order:
/// each group's tab, then the brushes that show in it, and after the groups
/// the brushes of the root section.
///
/// 🗣️유저 2026-10-01: 「브러시 그룹이나 브러시에도 단축키 명명가능하게」. None
/// ships with a key — which brush is under which finger is the user's.
/// ⚠️Which tab a brush shows in is the brush's own answer
/// ([BrushPreset.groupShownAmong]), the one the library's rail reads.
List<EditorActionDefinition> brushActionsOf(
  List<BrushGroup> groups,
  List<BrushPreset> presets,
) {
  EditorActionDefinition brush(BrushPreset preset, BrushGroupId? group) =>
      EditorActionDefinition(
        id: brushPresetActionId(preset.id),
        label: preset.name,
        category: brushActionCategory,
        defaultActivators: const [],
        brushPress: BrushPresetPress(preset.id, group: group),
      );
  return [
    for (final group in groups) ...[
      EditorActionDefinition(
        id: brushGroupActionId(group.id),
        label: group.name,
        category: brushActionCategory,
        defaultActivators: const [],
        brushPress: BrushGroupPress(group.id),
      ),
      for (final preset in presets)
        if (preset.groupShownAmong(groups) == group.id) brush(preset, group.id),
    ],
    for (final preset in presets)
      if (preset.groupShownAmong(groups) == null) brush(preset, null),
  ];
}
