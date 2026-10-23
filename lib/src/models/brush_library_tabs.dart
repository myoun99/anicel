import 'brush_group.dart';
import 'brush_preset.dart';

/// A brush library's tabs, in order: the groups as the library lists them,
/// then the root section (a null group) last — folders first, loose items
/// after, the way a file tree reads. The root section gets a tab only when
/// something is actually in it: a library whose brushes are all filed shows
/// no leftovers tab.
///
/// A library with no groups has NO tabs: a lone "Default" tab would be a
/// control with nothing to choose between, taking width from the brushes.
///
/// ONE LIST for the rail the panel draws and for the tab a deleted group's
/// tools enter, the one beside it in that rail (F-426).
List<BrushGroup?> brushLibraryTabs(
  List<BrushPreset> presets,
  List<BrushGroup> groups,
) => groups.isEmpty
    ? const <BrushGroup?>[]
    : [
        ...groups,
        if (presets.any((preset) => preset.groupShownAmong(groups) == null))
          null,
      ];
