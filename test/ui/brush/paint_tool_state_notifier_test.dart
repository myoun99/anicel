import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';

/// R11-④: the brush and the eraser keep separate settings — switching
/// stashes the outgoing paint tool and restores the incoming one; color
/// and the stabilizer stay shared.
void main() {
  test('brush ⇄ eraser round trip restores each tool\'s own settings', () {
    final notifier = PaintToolStateNotifier(
      BrushToolState.defaults.copyWith(size: 30, color: 0xFF112233),
    );
    addTearDown(notifier.dispose);

    // Pure switch to the eraser: first visit inherits the brush settings.
    notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);
    expect(notifier.value.size, 30);

    // Resize the eraser, then switch back: the brush keeps ITS size.
    notifier.value = notifier.value.copyWith(size: 80);
    notifier.value = notifier.value.copyWith(tool: CanvasTool.brush);
    expect(notifier.value.size, 30);

    // And the eraser remembers 80 on return.
    notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);
    expect(notifier.value.size, 80);
  });

  test('color and stabilizer stay SHARED across the switch', () {
    final notifier = PaintToolStateNotifier(
      BrushToolState.defaults.copyWith(size: 30),
    );
    addTearDown(notifier.dispose);
    notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);
    notifier.value = notifier.value.copyWith(tool: CanvasTool.brush);

    // Change color + stabilizer on the brush, then switch: both carry.
    notifier.value = notifier.value.copyWith(
      color: 0xFF00CC44,
      stabilizerStrength: 42,
    );
    notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);
    expect(notifier.value.color, 0xFF00CC44);
    expect(notifier.value.stabilizerStrength, 42);
  });

  test('an assignment carrying new settings wins over the bank (preset '
      'application landing on the brush)', () {
    final notifier = PaintToolStateNotifier(
      BrushToolState.defaults.copyWith(size: 30),
    );
    addTearDown(notifier.dispose);
    // Bank the brush at size 30, hop to the eyedropper.
    notifier.value = notifier.value.copyWith(tool: CanvasTool.eyedropper);

    // A preset lands on the brush WITH its own payload — not a pure tool
    // switch, so the bank must not clobber it.
    notifier.value = BrushToolState.defaults.copyWith(
      tool: CanvasTool.brush,
      size: 99,
    );
    expect(notifier.value.size, 99);
  });

  test('non-paint tools carry the current settings through unchanged', () {
    final notifier = PaintToolStateNotifier(
      BrushToolState.defaults.copyWith(size: 30),
    );
    addTearDown(notifier.dispose);
    notifier.value = notifier.value.copyWith(tool: CanvasTool.fill);
    expect(notifier.value.size, 30);
    notifier.value = notifier.value.copyWith(tool: CanvasTool.select);
    expect(notifier.value.size, 30);
  });
}
