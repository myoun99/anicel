import 'package:flutter/foundation.dart';

import '../../models/brush_group.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import 'brush_press.dart';

/// The brush library as a KEY reaches it (I-56): what it holds, for the
/// shortcut list to make rows of, and the two presses a row can make.
///
/// 🗣️유저 2026-10-01: 「브러시 그룹이나 브러시에도 단축키 명명가능하게.
/// 단축키리스트 등록」. The shell owns the keys and the workspace owns the
/// library, so this stands between them: the workspace says what the library
/// holds and takes a brush up, the library's panel — while it is on screen —
/// lends its own tab press, and the shell presses.
class BrushLibraryKeys extends ChangeNotifier {
  List<BrushGroup> get groups => _groups;
  List<BrushGroup> _groups = const [];

  List<BrushPreset> get presets => _presets;
  List<BrushPreset> _presets = const [];

  /// The library as it stands now. Tells its listeners.
  void show(List<BrushGroup> groups, List<BrushPreset> presets) {
    _groups = groups;
    _presets = presets;
    notifyListeners();
  }

  /// Takes a brush up for the tool in hand — the brush row's press. The
  /// workspace's, while it is mounted.
  ValueChanged<BrushPresetId>? takeUp;

  /// Opens a group for the tool in hand (F-250) — what a tab's press does
  /// to the hand. The workspace's, while it is mounted.
  ValueChanged<BrushGroupId>? openGroup;

  /// The tab's own press: the hand, AND the tab shown. The library panel's,
  /// while it is on screen; without it a group key still moves the hand.
  ValueChanged<BrushGroupId>? enterTab;

  /// Presses what [press] names.
  void press(BrushPress press) {
    switch (press) {
      case BrushPresetPress(:final preset):
        takeUp?.call(preset);
      case BrushGroupPress(:final group):
        (enterTab ?? openGroup)?.call(group);
    }
  }
}
