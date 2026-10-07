import '../../models/brush_group_id.dart';
import '../../models/brush_preset_id.dart';

/// What a BRUSH action presses (I-56): a group's tab of the brush library,
/// or one brush in it.
///
/// 🗣️I-56 (유저 2026-10-01): 「브러시 그룹이나 브러시에도 단축키 명명가능하게.
/// 단축키리스트 등록」. The same shape as a tool's press (`ToolPress`): the
/// shortcut row says what it presses, and the key presses what the tab or the
/// brush row does.
sealed class BrushPress {
  const BrushPress();
}

/// A group's tab — 「그 그룹과 그 그룹에서 마지막으로 고른 브러시」 (F-250).
final class BrushGroupPress extends BrushPress {
  const BrushGroupPress(this.group);

  final BrushGroupId group;

  @override
  bool operator ==(Object other) =>
      other is BrushGroupPress && other.group == group;

  @override
  int get hashCode => Object.hash(BrushGroupPress, group);
}

/// One brush, and the tab it shows in — its group, or null for the root
/// section, which is not a group and has no press of its own.
final class BrushPresetPress extends BrushPress {
  const BrushPresetPress(this.preset, {required this.group});

  final BrushPresetId preset;
  final BrushGroupId? group;

  @override
  bool operator ==(Object other) =>
      other is BrushPresetPress &&
      other.preset == preset &&
      other.group == group;

  @override
  int get hashCode => Object.hash(BrushPresetPress, preset, group);
}
