import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';
import 'package:anicel/src/ui/brush/tool_choice.dart';

/// 🚨★★F-123: THE TOOLS COME BACK HOLDING WHAT THEY HELD.
///
/// 유저 2026-09-13: 「저장시 마지막으로 고른 툴 상태(무슨 브러시인지, 무슨
/// 지우개인지, 채우기툴에서 뭐 골라져있는지 등) … 존재안하는게 있으면 해당
/// 분야만 초기값으로」.
///
/// Through a real notifier: the choice is read off it and put back through
/// its one setter, so what these pins see is what the tools' own laws made
/// of the file's words.
void main() {
  BrushPreset preset(String id, double size) => BrushPreset(
    id: BrushPresetId(id),
    name: id,
    settings: BrushSettings(size: size),
  );
  final library = {'pencil': preset('pencil', 4), 'soft': preset('soft', 60)};

  /// The workspace's answer, reduced to a library lookup.
  BrushToolState? brushFor(
    BrushToolState from,
    CanvasTool tool,
    BrushPresetId id,
  ) {
    final found = library[id.value];
    return found == null ? null : from.withPreset(found, tool: tool);
  }

  test('what the tools hold reads back as one choice', () {
    final tools = PaintToolStateNotifier(BrushToolState.defaults);
    addTearDown(tools.dispose);
    tools.value = brushFor(
      tools.value,
      CanvasTool.brush,
      const BrushPresetId('pencil'),
    )!;
    tools.value = brushFor(
      tools.value,
      CanvasTool.eraser,
      const BrushPresetId('soft'),
    )!;
    tools.value = tools.value.withShapeKind(
      CanvasShapeKind.ellipse,
      forTool: CanvasTool.fillShape,
    );
    tools.value = tools.value.copyWith(tool: CanvasTool.select);

    final choice = toolChoiceOf(tools);
    expect(choice.tool, CanvasTool.select);
    expect(choice.presets, {
      CanvasTool.brush: const BrushPresetId('pencil'),
      CanvasTool.eraser: const BrushPresetId('soft'),
    });
    expect(
      choice.railTiles[CanvasTool.fill],
      CanvasTool.fillShape,
      reason: 'the fill group was left on the shape fill',
    );
    expect(choice.fillShape, CanvasShapeKind.ellipse);
  });

  test('🚨a choice resumed into fresh tools lands every part', () {
    final tools = PaintToolStateNotifier(BrushToolState.defaults);
    addTearDown(tools.dispose);
    resumeToolChoice(
      tools,
      const ToolChoice(
        tool: CanvasTool.eraser,
        presets: {
          CanvasTool.brush: BrushPresetId('pencil'),
          CanvasTool.eraser: BrushPresetId('soft'),
        },
        railTiles: {CanvasTool.fill: CanvasTool.fillShape},
        fillShape: CanvasShapeKind.ellipse,
        fillOpacity: 0.5,
      ),
      brushFor: brushFor,
    );

    expect(tools.value.tool, CanvasTool.eraser);
    expect(tools.value.presetId, const BrushPresetId('soft'));
    expect(tools.value.size, 60);
    expect(tools.railEntry(CanvasTool.fill), CanvasTool.fillShape);
    expect(tools.value.fillShape, CanvasShapeKind.ellipse);
    expect(tools.value.fillOpacity, 0.5);

    // The brush was banked holding its own brush, not the eraser's.
    tools.value = tools.value.copyWith(tool: CanvasTool.brush);
    expect(tools.value.presetId, const BrushPresetId('pencil'));
    expect(tools.value.size, 4);
  });

  test('a preset the library no longer has leaves THAT tool as it was — the '
      'rest still lands', () {
    final tools = PaintToolStateNotifier(BrushToolState.defaults);
    addTearDown(tools.dispose);
    resumeToolChoice(
      tools,
      const ToolChoice(
        tool: CanvasTool.brush,
        presets: {
          CanvasTool.brush: BrushPresetId('deleted'),
          CanvasTool.eraser: BrushPresetId('soft'),
        },
      ),
      brushFor: brushFor,
    );

    expect(tools.value.tool, CanvasTool.brush);
    expect(
      tools.value.presetId,
      isNull,
      reason: 'the deleted brush does not land — the tool keeps its own',
    );
    expect(tools.presetHeldBy(CanvasTool.eraser), const BrushPresetId('soft'));
  });
}
