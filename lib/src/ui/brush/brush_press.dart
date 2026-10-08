import '../../models/brush_group_id.dart';
import '../../models/brush_preset_id.dart';
import 'brush_tool_state.dart';

/// What a BRUSH action presses (I-56): a group's tab of a paint tool's brush
/// library, or one brush in it.
///
/// 🗣️I-56 (유저 2026-10-01): 「브러시 그룹이나 브러시에도 단축키 명명가능하게.
/// 단축키리스트 등록」. The same shape as a tool's press (`ToolPress`): the
/// shortcut row says what it presses, and the key presses what the tab or the
/// brush row does.
///
/// 🗣️F-319 (유저 2026-10-08): 「브러시 그룹은 도구가 두곳에 있으니까 두 곳
/// 나눠서 지정하도록. 브러시도구의 브러시그룹/브러시 변경. 지우개도구의
/// 브러시그룹/브러시변경」 — so a press says WHOSE library it is in ([tool]):
/// each paint tool holds a brush of its own (R11-④), and a key is put on
/// 「the eraser's G pen」, not on 「the G pen of whatever is in hand」.
/// ↩️It named no tool, and went to the paint tool in hand — the brush tool
/// when none was.
sealed class BrushPress {
  const BrushPress(this.tool);

  /// The paint tool whose library the press is in — the tool it brings to
  /// hand.
  final CanvasTool tool;
}

/// A group's tab — 「그 그룹과 그 그룹에서 마지막으로 고른 브러시」 (F-250).
final class BrushGroupPress extends BrushPress {
  const BrushGroupPress(super.tool, this.group);

  final BrushGroupId group;

  @override
  bool operator ==(Object other) =>
      other is BrushGroupPress && other.tool == tool && other.group == group;

  @override
  int get hashCode => Object.hash(BrushGroupPress, tool, group);
}

/// One brush, and the tab it shows in — its group, or null for the root
/// section, which is not a group and has no press of its own.
final class BrushPresetPress extends BrushPress {
  const BrushPresetPress(super.tool, this.preset, {required this.group});

  final BrushPresetId preset;
  final BrushGroupId? group;

  @override
  bool operator ==(Object other) =>
      other is BrushPresetPress &&
      other.tool == tool &&
      other.preset == preset &&
      other.group == group;

  @override
  int get hashCode => Object.hash(BrushPresetPress, tool, preset, group);
}
