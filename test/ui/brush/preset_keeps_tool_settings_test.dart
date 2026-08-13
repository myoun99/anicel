import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

/// **A preset owns the SHAPE.** Everything outside the shape survives because
/// it is never touched, rather than because someone listed it.
///
/// 🚨⛔READ THIS BEFORE USING THIS FILE AS T26's FIX. It is not one.
///
/// T26 is 유저's 「선택툴 올가미인상태에서 **브러시툴로 바꾸면 초기화**되 …
/// 다른 툴 다 무사한데 **브러시툴로만**」, and the round memo named
/// `withPresetSettings` as the culprit: it rebuilt the state from the
/// preset's shape and hand-listed eleven fields to carry back, so anything
/// off that list would die.
///
/// **Measured 2026-08-14: nothing was off that list.** Restoring the old body
/// as a mutation kills none of these tests — the eleven entries covered every
/// field `BrushToolState` holds. So the reported symptom comes from
/// somewhere else, and the likeliest place is the one the memo itself
/// flagged: the selection's COMBINE mode lives on `CanvasSelectionCommands`,
/// not here, so `BrushToolState` never had it to lose.
///
/// What this file is worth on its own: the list went from eleven entries to
/// two, and survival stopped depending on anyone remembering to add the
/// twelfth. That is maintenance, not the bug.
void main() {
  /// A state with a non-default value in EVERY field outside the shape, so a
  /// list that silently drops one cannot pass by luck.
  BrushToolState armed() => BrushToolState.fromShape(
    const BrushShape(size: 12),
    tool: CanvasTool.select,
    selectShape: CanvasShapeKind.lasso,
    cutShape: CanvasShapeKind.ellipse,
    fillShape: CanvasShapeKind.lasso,
    stabilizerStrength: 0.7,
    brushBlendMode: BrushBlendMode.multiply,
    fillBlendMode: BrushBlendMode.screen,
    cutStampBlendMode: BrushBlendMode.add,
  );

  BrushSettings preset() =>
      BrushSettings.fromShape(const BrushShape(size: 99, spacing: 0.5));

  test('applying a preset leaves every non-shape setting exactly as it was', () {
    final before = armed();
    final after = before.withPresetSettings(preset(), tool: CanvasTool.brush);

    // The user's own case first: the lasso he had armed on the select tool.
    expect(
      after.selectShape,
      CanvasShapeKind.lasso,
      reason: '「선택툴 올가미인상태에서 브러시툴로 바꾸면 초기화」 — this is it',
    );
    expect(after.cutShape, before.cutShape);
    expect(after.fillShape, before.fillShape);
    expect(after.stabilizerStrength, before.stabilizerStrength);
    expect(after.brushBlendMode, before.brushBlendMode);
    expect(after.fillBlendMode, before.fillBlendMode);
    expect(after.cutStampBlendMode, before.cutStampBlendMode);
  });

  test('and it really does apply the brush', () {
    final after = armed().withPresetSettings(
      preset(),
      tool: CanvasTool.brush,
    );
    expect(after.tool, CanvasTool.brush);
    expect(
      after.shape.spacing,
      0.5,
      reason: 'the preset owns the shape, so the shape changes',
    );
  });

  test('the four HAND values still win over the preset', () {
    // 「브러시 다른거 선택한다고 사이즈/블렌딩모드가 바뀌지 않음」 (R26 #10),
    // the stabilizer (P7) and the colour (R9 #2). The old list named these
    // explicitly; they survive now for the structural reason instead — they
    // live outside `shape`, so the preset never reaches them.
    final before = armed();
    final after = before.withPresetSettings(preset(), tool: CanvasTool.brush);
    expect(
      after.size,
      before.size,
      reason: 'a preset carrying size 99 must not resize the hand',
    );
    expect(after.color, before.color);
    expect(after.stabilizerStrength, before.stabilizerStrength);
    expect(after.brushBlendMode, before.brushBlendMode);
  });

  test('copyWith(shape:) lays a brush down and named arguments land on top', () {
    // The ordering `withPresetSettings` depends on, asked directly: a caller
    // may say "this brush, but at my size".
    final state = BrushToolState.fromShape(const BrushShape(size: 12));
    final swapped = state.copyWith(
      shape: const BrushShape(size: 99, spacing: 0.5),
      size: 40,
    );
    expect(swapped.shape.spacing, 0.5, reason: 'the shape came from the arg');
    expect(swapped.size, 40, reason: 'and the explicit size beat it');
  });
}
