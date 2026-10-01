part of '../editor_workspace.dart';

/// The BRUSH GROUP a paint tool opens on — F-250's memory, as its own object
/// beside [_WorkspaceBrushPresets], which takes the brush up.
///
/// 🗣️F-250 (유저 2026-10-01): 「브러시 그룹을 바꿀때(선택하던 뭐던), 해당
/// 그룹의 마지막으로 선택했던걸 기억해서 그거 자동선택되도록」 — the tool
/// rail's `railEntry` law, for brush groups: from outside, back to where it
/// was left; the first time, the group's own first.
class _WorkspaceBrushGroups {
  _WorkspaceBrushGroups(this._state);

  final _EditorWorkspaceState _state;

  /// The brush each paint tool last held in each group, by the tab it shows
  /// in — what opening that tab hands the tool back ([openGroup]).
  ///
  /// 🗣️F-250-group-memory-Q1 (유저 2026-10-01): 「도구마다 따로」 — a tool
  /// keeps its own memory, as it keeps its own brush (R11-④): the eraser
  /// opening a group it has never held anything in takes the group's first,
  /// whatever the brush tool last held there.
  final Map<(CanvasTool, BrushGroupId?), BrushPresetId> _lastInGroup = {};

  /// Files [preset] as the last brush [tool] held in the tab it shows in.
  /// Every road a brush is taken up by passes `followBrushTool`, which
  /// calls this.
  void remember(CanvasTool tool, BrushPreset preset) {
    final group = preset.groupShownAmong(_state._presetLibrary.groups);
    _lastInGroup[(tool, group)] = preset.id;
  }

  /// Opens [group]'s tab for the paint tool in hand — the library shows only
  /// while one is (`ToolLibraryPanel`): it takes up the brush it last held
  /// there, or the tab's first ([BrushPresetLibrary.presetEntering]) —
  /// unless the brush in hand already shows in that tab, which stays exactly
  /// where it is (`railEntry`: 안에 있으면 그대로).
  void openGroup(BrushGroupId? group) {
    final presets = _state._brushPresets;
    final state = _state._brushTool.value;
    final library = _state._presetLibrary;
    final heldId = state.presetId;
    final held = heldId == null ? null : presets._presetNamed(heldId);
    if (held != null && held.groupShownAmong(library.groups) == group) {
      return;
    }
    final entering = library.presetEntering(
      group,
      remembered: _lastInGroup[(state.tool, group)],
    );
    final preset = entering == null ? null : presets._presetNamed(entering);
    if (preset != null) {
      presets._applyPreset(preset);
    }
  }
}
