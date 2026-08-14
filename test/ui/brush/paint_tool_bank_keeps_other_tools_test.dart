import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';

/// 🚨★★★ 유저 #14 (2026-08-14, 다른 세션 진단): 「선택툴에서 **올가미 선택하고
/// 브러시가면 초기화**되는거」.
///
/// The paint-tool bank (R11-④) remembers the brush's and the eraser's own
/// stroke settings so switching between them does not retune either. But it
/// stored and restored the WHOLE [BrushToolState], with only `color` and
/// `stabilizerStrength` carved out as shared — so returning to the brush
/// replayed a snapshot from before, and every OTHER tool's field went back
/// with it.
///
/// 🔬The reset fires on **turning the brush on**, not on returning to
/// select: the app starts on the brush, so the bank holds a
/// `selectShape: rect` snapshot from the very first frame, and it lands the
/// moment you go back.
///
/// 🚨★★This is the THIRD time this round that a hand-written list of what
/// to carry has gone stale as fields were added — `withMask` passed three
/// and reset the shapes, `withPresetSettings` dropped them, and now this.
/// ⇒ The fix inverts the direction of the list: build from the LIVE state
/// and pull back only what the bank exists to remember. A field added
/// tomorrow is then shared by default, which is a mild wrong; under the old
/// direction it silently reverted, which is this bug.
void main() {
  /// The bank restores on a PURE tool switch, which is what a rail tap is.
  BrushToolState roundTripThroughBrush(BrushToolState onSelect) {
    final notifier = PaintToolStateNotifier(
      BrushToolState.defaults.copyWith(tool: CanvasTool.brush),
    );
    addTearDown(notifier.dispose);
    // Stand on the brush first, so the bank has the starting snapshot it
    // has in the real app.
    notifier.value = notifier.value.copyWith(tool: CanvasTool.brush);
    notifier.value = onSelect;
    notifier.value = notifier.value.copyWith(tool: CanvasTool.brush);
    return notifier.value;
  }

  test('the lasso survives a trip to the brush', () {
    final after = roundTripThroughBrush(
      BrushToolState.defaults.copyWith(
        tool: CanvasTool.select,
        selectShape: CanvasShapeKind.lasso,
      ),
    );

    expect(after.selectShape, CanvasShapeKind.lasso);
  });

  test('the CUT tool\'s shape survives too — 도형은 동사별로 기억', () {
    final after = roundTripThroughBrush(
      BrushToolState.defaults.copyWith(
        tool: CanvasTool.cut,
        cutShape: CanvasShapeKind.lasso,
      ),
    );

    expect(after.cutShape, CanvasShapeKind.lasso);
  });

  test('and the fill\'s', () {
    final after = roundTripThroughBrush(
      BrushToolState.defaults.copyWith(
        tool: CanvasTool.fillShape,
        fillShape: CanvasShapeKind.lasso,
      ),
    );

    expect(after.fillShape, CanvasShapeKind.lasso);
  });

  /// ⚠️Measured only as far as the shapes by the session that found this;
  /// the blends ride the same restore, so they are pinned here rather than
  /// left to be rediscovered.
  test('the other tools\' BLENDS ride the same restore', () {
    final after = roundTripThroughBrush(
      BrushToolState.defaults.copyWith(
        tool: CanvasTool.fillShape,
        fillBlendMode: BrushBlendMode.multiply,
        cutStampBlendMode: BrushBlendMode.multiply,
      ),
    );

    expect(after.fillBlendMode, BrushBlendMode.multiply);
    expect(after.cutStampBlendMode, BrushBlendMode.multiply);
  });

  /// ⛔The bank must still do its job: this is the half that stops the fix
  /// from being "delete the bank".
  test('the BRUSH\'s own settings still come back — that is what the bank '
      'is for', () {
    final notifier = PaintToolStateNotifier(
      BrushToolState.defaults.copyWith(tool: CanvasTool.brush),
    );
    addTearDown(notifier.dispose);

    notifier.value = notifier.value.copyWith(
      tool: CanvasTool.brush,
      size: 42,
      brushBlendMode: BrushBlendMode.multiply,
    );
    notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);
    notifier.value = notifier.value.copyWith(tool: CanvasTool.brush);

    expect(notifier.value.size, 42);
    expect(notifier.value.brushBlendMode, BrushBlendMode.multiply);
  });
}
