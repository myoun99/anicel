import 'package:flutter/foundation.dart';

import '../../models/brush_group.dart';
import '../../models/brush_group_id.dart';
import '../../models/brush_preset.dart';
import '../../models/brush_preset_id.dart';
import 'brush_press.dart';
import 'brush_tool_state.dart';

/// The brush library as a KEY reaches it (I-56): what it holds, for the
/// shortcut list to make rows of, and the two presses a row can make.
///
/// 🗣️유저 2026-10-01: 「브러시 그룹이나 브러시에도 단축키 명명가능하게.
/// 단축키리스트 등록」. The shell owns the keys and the workspace owns the
/// library, so this stands between them: the workspace says what the library
/// holds and lends the two presses, and the shell presses.
///
/// 🗣️F-319 (유저 2026-10-08): 「대체 무슨 방식으로 연결한거지? 그냥 브러시
/// 그룹 바꾸는거로하면 더 만들것도 없고 쉬울텐데. 법 이상한거 있으면 통일」.
/// ↩️A group's press had a THIRD lend, the library panel's own
/// (`enterTab`: 「the hand, AND the tab shown」), taken by whichever panel
/// mounted last — and there is a panel a paint tool, both kept alive, so
/// the key turned the tab of a panel that was not on screen. The tab shown
/// is one fact beside the hand now (`BrushLibraryLook`), and [openGroup] —
/// what a tap on the tab calls — settles both.
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

  /// A paint tool comes to hand holding a brush — the brush row's press in
  /// that tool's library. The workspace's, while it is mounted.
  void Function(CanvasTool tool, BrushPresetId preset)? takeUp;

  /// A paint tool comes to hand in a group (F-250) — the press of that
  /// group's tab in its library. The workspace's, while it is mounted.
  void Function(CanvasTool tool, BrushGroupId group)? openGroup;

  /// Presses what [press] names.
  void press(BrushPress press) {
    switch (press) {
      case BrushPresetPress(:final tool, :final preset):
        takeUp?.call(tool, preset);
      case BrushGroupPress(:final tool, :final group):
        openGroup?.call(tool, group);
    }
  }
}
