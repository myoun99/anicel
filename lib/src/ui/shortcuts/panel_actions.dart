import '../panels/workspace_panels_menu.dart';
import 'editor_action_registry.dart';

/// The action that shows or hides the panel of [tabId] — its row in the
/// settings menu's 패널 list.
String panelActionId(String tabId) => 'panel-$tabId';

/// Whether [actionId] names a panel's row — whether or not the workspace
/// has told of that panel yet (the settings come back before it mounts).
bool isPanelActionId(String actionId) => actionId.startsWith('panel-');

/// The workspace's panels as shortcut rows (I-40), in the 패널 list's order.
///
/// 🗣️유저 2026-09-18: 「설정의 패널 열기 닫기같은거든 뭐든 모든 버튼」. Which
/// panels there are is the workspace's to say (`WorkspacePanelsMenuController`
/// — the list the menu itself is drawn from), so these rows are made from
/// that list as the brush library's are from the library. Each is its menu
/// row ([EditorActionDefinition.menuRow]) and none ships with a key.
List<EditorActionDefinition> panelActionsOf(
  List<WorkspacePanelEntry> entries,
) => [
  for (final entry in entries)
    EditorActionDefinition(
      id: panelActionId(entry.tabId),
      label: entry.label,
      category: panelActionCategory,
      defaultActivators: const [],
      menuRow: true,
    ),
];
