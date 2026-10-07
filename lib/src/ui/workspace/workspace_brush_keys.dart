part of '../editor_workspace.dart';

/// The brush library's half of its KEYS (I-56): the shell owns the keys and
/// this workspace owns the library, so it tells the shell's port what the
/// library holds and lends it the two presses a key can make — beside
/// [_WorkspaceBrushPresets], which takes a brush up, and
/// [_WorkspaceBrushGroups], which opens a group.
class _WorkspaceBrushKeys {
  _WorkspaceBrushKeys(this._state);

  final _EditorWorkspaceState _state;

  BrushLibraryKeys? get _port => _state.widget.brushKeys;

  /// From now on the port hears every change of the library and presses
  /// through this workspace. The library tells its listeners when it has
  /// loaded, so that is when the shortcut list first gets its brush rows.
  void attach() {
    _state._presetLibrary.addListener(_show);
    _port
      ?..takeUp = takeUp
      ..openGroup = _state._brushGroups.openGroup;
  }

  /// Before the library goes.
  void detach() {
    _state._presetLibrary.removeListener(_show);
    if (_port?.takeUp == takeUp) {
      _port
        ?..takeUp = null
        ..openGroup = null;
    }
  }

  void _show() =>
      _port?.show(_state._presetLibrary.groups, _state._presetLibrary.presets);

  /// The brush row's press for a KEY: the brush of [id], while the library
  /// holds one.
  void takeUp(BrushPresetId id) {
    final preset = _state._brushPresets._presetNamed(id);
    if (preset != null) {
      _state._brushPresets._applyPreset(preset);
    }
  }
}
