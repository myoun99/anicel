import '../../models/brush_blend_mode.dart';
import '../../models/brush_preset_id.dart';
import '../../models/canvas_shape_kind.dart';
import 'brush_tool_state.dart';
import 'paint_tool_state_notifier.dart';

/// What a person's tools were holding when the project was saved (F-123):
/// the tool in hand, the brush each paint tool held, the tile each rail
/// group was left on, the outline each tracing verb drags, and the fill's
/// and the stamp's blend and opacity.
///
/// 유저 2026-09-13: 「저장시 마지막으로 고른 툴 상태(무슨 브러시인지, 무슨
/// 지우개인지, 채우기툴에서 뭐 골라져있는지 등) … 존재안하는게 있으면 해당
/// 분야만 초기값으로」.
///
/// ⛔NOT the colour and NOT the stabilizer: every tool shares those (the
/// notifier's own law), so they are not something one tool was holding.
///
/// 🚨EVERY PART ANSWERS FOR ITSELF. A name this build does not know, an
/// opacity out of range — that part reads as absent and keeps its default,
/// and the rest still lands. This reads names; which tile a group may hold
/// and which tools hold a brush are the notifier's and the workspace's laws,
/// and they apply them when the choice is resumed.
class ToolChoice {
  const ToolChoice({
    this.tool,
    this.presets = const {},
    this.railTiles = const {},
    this.selectShape,
    this.cutShape,
    this.fillShape,
    this.fillBlendMode,
    this.cutStampBlendMode,
    this.fillOpacity,
    this.cutStampOpacity,
  });

  final CanvasTool? tool;

  /// The brush each paint tool held, by the preset it came from.
  final Map<CanvasTool, BrushPresetId> presets;

  /// The tile each rail group was left on.
  final Map<CanvasTool, CanvasTool> railTiles;

  final CanvasShapeKind? selectShape;
  final CanvasShapeKind? cutShape;
  final CanvasShapeKind? fillShape;
  final BrushBlendMode? fillBlendMode;
  final BrushBlendMode? cutStampBlendMode;
  final double? fillOpacity;
  final double? cutStampOpacity;

  Map<String, Object?> toJson() => {
    if (tool != null) 'tool': tool!.name,
    if (presets.isNotEmpty)
      'presets': {
        for (final entry in presets.entries)
          entry.key.name: entry.value.value,
      },
    if (railTiles.isNotEmpty)
      'railTiles': {
        for (final entry in railTiles.entries)
          entry.key.name: entry.value.name,
      },
    if (selectShape != null) 'selectShape': selectShape!.name,
    if (cutShape != null) 'cutShape': cutShape!.name,
    if (fillShape != null) 'fillShape': fillShape!.name,
    if (fillBlendMode != null) 'fillBlendMode': fillBlendMode!.name,
    if (cutStampBlendMode != null)
      'cutStampBlendMode': cutStampBlendMode!.name,
    if (fillOpacity != null) 'fillOpacity': fillOpacity,
    if (cutStampOpacity != null) 'cutStampOpacity': cutStampOpacity,
  };

  /// The choice [json] holds; any part it does not hold readably is absent.
  static ToolChoice fromJson(Map<String, Object?> json) => ToolChoice(
    tool: _toolNamed(json['tool']),
    presets: {
      for (final entry in _entries(json['presets']))
        if (_toolNamed(entry.key) case final tool?)
          if (entry.value case final String id when id.isNotEmpty)
            tool: BrushPresetId(id),
    },
    railTiles: {
      for (final entry in _entries(json['railTiles']))
        ?_toolNamed(entry.key): ?_toolNamed(entry.value),
    },
    selectShape: _shapeNamed(json['selectShape']),
    cutShape: _shapeNamed(json['cutShape']),
    fillShape: _shapeNamed(json['fillShape']),
    fillBlendMode: BrushBlendMode.named(_string(json['fillBlendMode'])),
    cutStampBlendMode: BrushBlendMode.named(
      _string(json['cutStampBlendMode']),
    ),
    fillOpacity: _opacity(json['fillOpacity']),
    cutStampOpacity: _opacity(json['cutStampOpacity']),
  );
}

String? _string(Object? json) => json is String ? json : null;

CanvasTool? _toolNamed(Object? json) =>
    CanvasTool.values.asNameMap()[_string(json)];

CanvasShapeKind? _shapeNamed(Object? json) =>
    CanvasShapeKind.values.asNameMap()[_string(json)];

/// An opacity as written, or null when it is not one (a number from 0 to 1).
double? _opacity(Object? json) =>
    json is num && json >= 0 && json <= 1 ? json.toDouble() : null;

Iterable<MapEntry<Object?, Object?>> _entries(Object? json) =>
    json is Map ? json.entries : const [];

/// What [tools] is holding now, as a project carries it (F-123).
///
/// The tile of a rail group is written only where it is not the group's own
/// tool: [PaintToolStateNotifier.railEntry] answers the group itself for a
/// group never left on another tile, so writing it would say nothing.
ToolChoice toolChoiceOf(PaintToolStateNotifier tools) {
  final live = tools.value;
  final groups = {
    for (final tool in CanvasTool.values) canvasToolRailGroup(tool),
  };
  return ToolChoice(
    tool: live.tool,
    presets: {
      for (final tool in CanvasTool.values)
        if (canvasToolPaints(tool))
          tool: ?tools.presetHeldBy(tool),
    },
    railTiles: {
      for (final group in groups)
        if (tools.railEntry(group) case final tile when tile != group)
          group: tile,
    },
    selectShape: live.selectShape,
    cutShape: live.cutShape,
    fillShape: live.fillShape,
    fillBlendMode: live.fillBlendMode,
    cutStampBlendMode: live.cutStampBlendMode,
    fillOpacity: live.fillOpacity,
    cutStampOpacity: live.cutStampOpacity,
  );
}

/// Puts [choice] back into [tools] THROUGH ITS ONE SETTER, so the tools' own
/// laws decide what the file's words become (F-123): a tile is filed under
/// its own group and the stamp is never remembered, a paint tool's brush is
/// banked when another tool is taken up, and a pure switch hands a paint
/// tool back its banked brush.
///
/// [brushFor] answers the state holding [BrushPresetId]'s brush for that
/// tool — null when the library has no such preset, and then that tool keeps
/// what it holds while every other part still lands.
///
/// ⛔No second way into the notifier: a restore that wrote its bank and its
/// rail memory directly would be a second writer of both, and the laws above
/// would have to be spelled again beside it.
void resumeToolChoice(
  PaintToolStateNotifier tools,
  ToolChoice choice, {
  required BrushToolState? Function(
    BrushToolState from,
    CanvasTool tool,
    BrushPresetId preset,
  )
  brushFor,
}) {
  tools.value = tools.value.copyWith(
    selectShape: choice.selectShape,
    cutShape: choice.cutShape,
    fillShape: choice.fillShape,
    fillBlendMode: choice.fillBlendMode,
    cutStampBlendMode: choice.cutStampBlendMode,
    fillOpacity: choice.fillOpacity,
    cutStampOpacity: choice.cutStampOpacity,
  );
  for (final tile in choice.railTiles.values) {
    tools.value = tools.value.copyWith(tool: tile);
  }
  // The tool in hand takes its brush LAST, so the switch below finds it
  // already there and every other paint tool's brush already banked.
  final brushes = [
    for (final entry in choice.presets.entries)
      if (canvasToolPaints(entry.key) && entry.key != choice.tool) entry,
    for (final entry in choice.presets.entries)
      if (canvasToolPaints(entry.key) && entry.key == choice.tool) entry,
  ];
  for (final entry in brushes) {
    final brush = brushFor(tools.value, entry.key, entry.value);
    if (brush != null) {
      tools.value = brush;
    }
  }
  final tool = choice.tool;
  if (tool != null) {
    tools.value = tools.value.copyWith(tool: tool);
  }
}
