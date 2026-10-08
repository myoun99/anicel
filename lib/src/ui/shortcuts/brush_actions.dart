import '../../models/brush_group.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import '../brush/brush_press.dart';
import '../brush/brush_tool_state.dart';
import 'editor_action_registry.dart';

/// The heading each paint tool's brush rows stand under in the shortcut
/// window — a heading a tool, since each has its own rows (F-319).
///
/// ⚠️Table keys: every language has a word for each (`shortcutCategory`).
/// ⚠️A tool that comes to hold a brush of its own ([canvasToolPaints]) gets
/// its line here: with none it has no heading to stand under, and
/// [brushActionsOf] fails on it out loud rather than filing its rows under
/// another tool's.
const Map<CanvasTool, String> brushActionCategories = {
  CanvasTool.brush: 'Brush Tool Brushes',
  CanvasTool.eraser: 'Eraser Tool Brushes',
};

/// The action that opens [group]'s tab in [tool]'s library.
///
/// ⚠️The tool's NAME is in the id, and the id is what a recorded key is
/// filed under: the brush tool's are the ids I-56 shipped (`brush-group-…`).
String brushGroupActionId(CanvasTool tool, BrushGroupId group) =>
    '${tool.name}-group-${group.value}';

/// The action that takes up [preset] for [tool].
String brushPresetActionId(CanvasTool tool, BrushPresetId preset) =>
    '${tool.name}-preset-${preset.value}';

/// The tools that hold a brush of their own, in the order their rows stand.
Iterable<CanvasTool> get _brushHolders =>
    CanvasTool.values.where(canvasToolPaints);

/// Whether [actionId] names a brush or a brush group of some paint tool's
/// library — whether or not the library holds one of that id right now.
///
/// ⚠️A key recorded for a brush is kept by this, not by the brush being
/// there: the library loads after the settings do, and a brush that was
/// deleted can come back (an undo, the same pack imported again). Its entry
/// presses nothing while no brush carries the id.
bool isBrushActionId(String actionId) => _brushHolders.any(
  (tool) =>
      actionId.startsWith('${tool.name}-group-') ||
      actionId.startsWith('${tool.name}-preset-'),
);

/// The brush library as shortcut rows (I-56) — once for each paint tool
/// (F-319), and each time in the library's own order: each group's tab,
/// then the brushes that show in it, and after the groups the brushes of
/// the root section.
///
/// 🗣️유저 2026-10-01: 「브러시 그룹이나 브러시에도 단축키 명명가능하게」. None
/// ships with a key — which brush is under which finger is the user's.
/// 🗣️유저 2026-10-08 (F-319): 「브러시 그룹은 도구가 두곳에 있으니까 두 곳
/// 나눠서 지정하도록」 — the brush tool's rows, then the eraser's.
/// ⚠️Which tab a brush shows in is the brush's own answer
/// ([BrushPreset.groupShownAmong]), the one the library's rail reads.
List<EditorActionDefinition> brushActionsOf(
  List<BrushGroup> groups,
  List<BrushPreset> presets,
) => [
  for (final tool in _brushHolders) ..._rowsOf(tool, groups, presets),
];

List<EditorActionDefinition> _rowsOf(
  CanvasTool tool,
  List<BrushGroup> groups,
  List<BrushPreset> presets,
) {
  final category = brushActionCategories[tool]!;
  EditorActionDefinition brush(BrushPreset preset, BrushGroupId? group) =>
      EditorActionDefinition(
        id: brushPresetActionId(tool, preset.id),
        label: preset.name,
        category: category,
        defaultActivators: const [],
        brushPress: BrushPresetPress(tool, preset.id, group: group),
      );
  return [
    for (final group in groups) ...[
      EditorActionDefinition(
        id: brushGroupActionId(tool, group.id),
        label: group.name,
        category: category,
        defaultActivators: const [],
        brushPress: BrushGroupPress(tool, group.id),
      ),
      for (final preset in presets)
        if (preset.groupShownAmong(groups) == group.id) brush(preset, group.id),
    ],
    for (final preset in presets)
      if (preset.groupShownAmong(groups) == null) brush(preset, null),
  ];
}
