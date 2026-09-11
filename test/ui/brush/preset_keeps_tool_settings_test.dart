import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_preset.dart';
import 'package:anicel/src/models/brush_preset_id.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/services/brush_hand_overlay.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

/// **A preset owns the SHAPE.** Everything outside the shape survives because
/// it is never touched, rather than because someone listed it.
///
/// 🚨⛔READ THIS BEFORE USING THIS FILE AS T26's FIX. It is not one.
///
/// T26 is 유저's 「선택툴 올가미인상태에서 **브러시툴로 바꾸면 초기화**되 …
/// 다른 툴 다 무사한데 **브러시툴로만**」, and the round memo named
/// `withPreset` as the culprit: it rebuilt the state from the
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
    fillBlendMode: BrushBlendMode.screen,
    cutStampBlendMode: BrushBlendMode.add,
  );

  BrushPreset preset() => BrushPreset(
    id: const BrushPresetId('under-test'),
    name: 'under test',
    settings: BrushSettings.fromShape(
      const BrushShape(
        size: 99,
        spacing: 0.5,
        blendMode: BrushBlendMode.multiply,
      ),
    ),
  );

  test('applying a preset leaves every non-shape setting exactly as it was', () {
    final before = armed();
    final after = before.withPreset(preset(), tool: CanvasTool.brush);

    // The user's own case first: the lasso he had armed on the select tool.
    expect(
      after.selectShape,
      CanvasShapeKind.lasso,
      reason: '「선택툴 올가미인상태에서 브러시툴로 바꾸면 초기화」 — this is it',
    );
    expect(after.cutShape, before.cutShape);
    expect(after.fillShape, before.fillShape);
    expect(after.stabilizerStrength, before.stabilizerStrength);
    expect(
      after.fillBlendMode,
      before.fillBlendMode,
      reason: 'the fill has no preset for a blend to arrive from',
    );
    expect(after.cutStampBlendMode, before.cutStampBlendMode);
  });

  test('and it really does apply the brush', () {
    final after = armed().withPreset(
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

  test('the HAND values that still win over the preset', () {
    // The stabilizer (P7) and the colour (R9 #2) — they live outside `shape`,
    // so the preset never reaches them, and that structural reason is why
    // they need no list of their own.
    final before = armed();
    final after = before.withPreset(preset(), tool: CanvasTool.brush);
    expect(after.color, before.color);
    expect(after.stabilizerStrength, before.stabilizerStrength);
  });

  test('the BLEND is not one of them either — it rides in the shape now', () {
    // ⛔R26 #10's other half 「블렌딩모드가 바뀌지 않음」, retired 2026-09-08:
    // 「툴/손 설정 구분 없애고 모든 설정이 내보낼때 나르도록. 브러시든
    // 지우개든 블렌드 모드를 나른단거야」.
    final before = BrushToolState.fromShape(
      const BrushShape(blendMode: BrushBlendMode.screen),
    );
    expect(
      before.withPreset(preset(), tool: CanvasTool.brush).blendMode,
      BrushBlendMode.multiply,
      reason: 'the preset carries 乗算 and the brush wears it',
    );
  });

  test('SIZE is no longer one of them — a brush wears its own (H25)', () {
    // 🚨This test used to read `expect(after.size, before.size)` and quote
    // R26 #10 「브러시 다른거 선택한다고 사이즈/블렌딩모드가 바뀌지 않음」.
    // H25 (유저 2026-08-23) asks the opposite and was answered:
    // 「브러시 고르고 브러시크기 설정하면 다음에 같은 브러시 선택할때 해당
    // 브러시크기 남아있도록」. Later ruling wins; the older one is still
    // quoted at `withPreset`, because a reader who does not know it
    // existed would find this a bug.
    final before = armed();

    expect(
      before.withPreset(preset(), tool: CanvasTool.brush).size,
      isNot(before.size),
      reason: 'the preset carries size 99 and the brush wears it',
    );
    expect(
      before
          .withPreset(
            preset(),
            tool: CanvasTool.brush,
            held: brushSettingsUnderHand(preset().settings, {'size': 33.0}),
          )
          .size,
      33,
      reason: 'unless the hand has set one ON THIS BRUSH before',
    );
  });

  test('copyWith(shape:) lays a brush down and named arguments land on top', () {
    // The ordering `withPreset` depends on, asked directly: a caller
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
