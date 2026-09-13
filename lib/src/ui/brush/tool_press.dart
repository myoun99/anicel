import 'package:flutter/foundation.dart';

import '../../models/canvas_shape_kind.dart';
import '../text/app_strings.dart';
import 'brush_tool_state.dart';
import 'paint_tool_state_notifier.dart';
import 'transform_tool_options.dart';

/// What a rail button, a sub-tool tile and a tool shortcut all PRESS.
///
/// 🗣️유저 2026-09-13 (I-19): 「툴 내의 세부툴도 숏컷 지정 가능하게 하려고.
/// 툴 자체에 설정할수도있고 툴 내부의 세부툴도 설정가능하게」 — and of the
/// keys that had grown up beside the tools: 「변형툴처럼 법 통일해서
/// 잔재제거」.
///
/// ★ONE press per control. A tool action's registry row carries its press,
/// the rail and the tool library build their buttons out of presses, and all
/// three apply one through [pressTool]. A key cannot mean something its
/// button does not, and a button cannot exist without a row in the shortcut
/// list (`every_tool_and_tile_is_an_action_test`).
sealed class ToolPress {
  const ToolPress();
}

/// A rail button: its group, re-entered on the tile it was last left on
/// ([PaintToolStateNotifier.railEntry]).
final class RailToolPress extends ToolPress {
  const RailToolPress(this.group);

  final CanvasTool group;

  @override
  bool operator ==(Object other) =>
      other is RailToolPress && other.group == group;

  @override
  int get hashCode => Object.hash(RailToolPress, group);

  @override
  String toString() => 'RailToolPress(${group.name})';
}

/// A tile inside a tool — what the tool library lists.
sealed class SubToolPress extends ToolPress {
  const SubToolPress();
}

/// A tile that is a tool of its own: the bucket, the stamp.
final class ToolTilePress extends SubToolPress {
  const ToolTilePress(this.tool);

  final CanvasTool tool;

  @override
  bool operator ==(Object other) =>
      other is ToolTilePress && other.tool == tool;

  @override
  int get hashCode => Object.hash(ToolTilePress, tool);

  @override
  String toString() => 'ToolTilePress(${tool.name})';
}

/// A shape tile: its verb, tracing that outline.
final class ShapeTilePress extends SubToolPress {
  const ShapeTilePress(this.verb, this.shape);

  final CanvasTool verb;
  final CanvasShapeKind shape;

  @override
  bool operator ==(Object other) =>
      other is ShapeTilePress && other.verb == verb && other.shape == shape;

  @override
  int get hashCode => Object.hash(ShapeTilePress, verb, shape);

  @override
  String toString() => 'ShapeTilePress(${verb.name}, ${shape.name})';
}

/// A transform mode tile: the transform tool, in that mode.
final class TransformModePress extends SubToolPress {
  const TransformModePress(this.mode);

  final TransformMode mode;

  @override
  bool operator ==(Object other) =>
      other is TransformModePress && other.mode == mode;

  @override
  int get hashCode => Object.hash(TransformModePress, mode);

  @override
  String toString() => 'TransformModePress(${mode.name})';
}

/// The one write behind a rail button, a tile and a tool shortcut.
///
/// ⚠️Every tool change goes through the notifier's own setter, so its switch
/// guard (R26 #13) and its rail memory see a key exactly as they see a tap.
void pressTool(
  ToolPress press, {
  required PaintToolStateNotifier tool,
  required ValueNotifier<TransformToolOptions> transform,
}) {
  switch (press) {
    case RailToolPress(:final group):
      tool.value = tool.value.copyWith(tool: tool.railEntry(group));
    case ToolTilePress(tool: final armed):
      tool.value = tool.value.copyWith(tool: armed);
    case ShapeTilePress(:final verb, :final shape):
      tool.value = tool.value.withShapeKind(shape, forTool: verb);
    case TransformModePress(:final mode):
      // The mode FIRST, so a box the tool write opens opens in it. ⚠️A mode
      // is a SETTING: switching one mid-session widens or narrows the OPEN
      // box instead of confirming it — and with the tool already in hand
      // the tool write is an equal value, which the notifier does not
      // announce, so nothing on the way past confirms anything.
      transform.value = transform.value.copyWith(mode: mode);
      tool.value = tool.value.copyWith(tool: CanvasTool.move);
  }
}

/// A shape tile's name: its verb's template around the shape's name —
/// 「올가미 선택」, 「Sélection Lasso」.
///
/// ★COMPOSED, never tabled per tile. [CanvasShapeKind] warns that the verb ×
/// shape product grows like one — twelve labels in five languages for four
/// shapes — so each language tables the four shapes and the three verbs'
/// templates once. And a TEMPLATE rather than two words glued together: the
/// order belongs to the translator, and French puts the verb first.
String shapeTileLabel(
  CanvasTool verb,
  CanvasShapeKind shape, [
  AppStrings? strings,
]) {
  final s = strings ?? AppText.strings;
  final template = switch (verb) {
    CanvasTool.select => s.toolShapeSelectTemplate,
    CanvasTool.cut => s.toolShapeCutTemplate,
    CanvasTool.fillShape => s.toolShapeFillTemplate,
    _ => throw ArgumentError.value(verb, 'verb', 'traces no shape'),
  };
  return template.replaceAll('{shape}', switch (shape) {
    CanvasShapeKind.rect => s.toolShapeRect,
    CanvasShapeKind.ellipse => s.toolShapeEllipse,
    CanvasShapeKind.lasso => s.toolShapeLasso,
    CanvasShapeKind.polygon => s.toolShapePolygon,
  });
}
