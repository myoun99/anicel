import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_choice.dart';

/// F-123: what the tools were holding travels as names beside the project,
/// and every part of it answers for itself.
void main() {
  const choice = ToolChoice(
    tool: CanvasTool.fillShape,
    presets: {
      CanvasTool.brush: BrushPresetId('pencil'),
      CanvasTool.eraser: BrushPresetId('soft'),
    },
    railTiles: {CanvasTool.fill: CanvasTool.fillShape},
    selectShape: CanvasShapeKind.lasso,
    cutShape: CanvasShapeKind.rect,
    fillShape: CanvasShapeKind.ellipse,
    fillBlendMode: BrushBlendMode.multiply,
    cutStampBlendMode: BrushBlendMode.color,
    fillOpacity: 0.5,
    cutStampOpacity: 1.0,
  );

  test('a choice round-trips through its JSON, part by part', () {
    final back = ToolChoice.fromJson(choice.toJson());
    expect(back.tool, CanvasTool.fillShape);
    expect(back.presets, {
      CanvasTool.brush: const BrushPresetId('pencil'),
      CanvasTool.eraser: const BrushPresetId('soft'),
    });
    expect(back.railTiles, {CanvasTool.fill: CanvasTool.fillShape});
    expect(back.selectShape, CanvasShapeKind.lasso);
    expect(back.cutShape, CanvasShapeKind.rect);
    expect(back.fillShape, CanvasShapeKind.ellipse);
    expect(back.fillBlendMode, BrushBlendMode.multiply);
    expect(back.cutStampBlendMode, BrushBlendMode.color);
    expect(back.fillOpacity, 0.5);
    expect(back.cutStampOpacity, 1.0);
  });

  test('nothing chosen writes nothing', () {
    expect(const ToolChoice().toJson(), isEmpty);
  });

  test('🚨a part this build cannot read is ABSENT — the rest still lands', () {
    final back = ToolChoice.fromJson({
      'tool': 'airbrush',
      'presets': {'brush': 'pencil', 'smudge': 'x', 'eraser': ''},
      'railTiles': {'fill': 'bucket', 'cut': 'cutStamp'},
      'selectShape': 'star',
      'cutShape': 'rect',
      'fillBlendMode': 'glow',
      'fillOpacity': 1.5,
      'cutStampOpacity': 0.25,
    });
    expect(back.tool, isNull, reason: 'a tool this build does not have');
    expect(
      back.presets,
      {CanvasTool.brush: const BrushPresetId('pencil')},
      reason: 'an unknown tool and an empty id are both left out',
    );
    expect(
      back.railTiles,
      {CanvasTool.cut: CanvasTool.cutStamp},
      reason: 'a tile this build does not have is left out',
    );
    expect(back.selectShape, isNull);
    expect(back.cutShape, CanvasShapeKind.rect);
    expect(back.fillBlendMode, isNull);
    expect(back.fillOpacity, isNull, reason: 'past 1 is not an opacity');
    expect(back.cutStampOpacity, 0.25);
  });
}
