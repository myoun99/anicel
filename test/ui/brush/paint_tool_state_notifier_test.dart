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

  group('railEntry — the tile a tool group re-enters on', () {
    test('a group answers with the tile it was last left on', () {
      // 유저 2026-08-15: "필 툴은 아직도 다른 툴 이동하면 모드 선택한게
      // 초기화됨." Leaving the fill for the brush used to throw the choice
      // away, because "which tile" IS the tool and the tool is what the
      // switch replaced.
      final notifier = PaintToolStateNotifier(BrushToolState.defaults);
      addTearDown(notifier.dispose);

      // Never used: the group's own default.
      expect(notifier.railEntry(CanvasTool.fill), CanvasTool.fill);
      expect(notifier.railEntry(CanvasTool.cut), CanvasTool.cut);

      notifier.value = notifier.value.copyWith(tool: CanvasTool.fillShape);
      notifier.value = notifier.value.copyWith(tool: CanvasTool.cutStamp);
      notifier.value = notifier.value.copyWith(tool: CanvasTool.brush);

      expect(notifier.railEntry(CanvasTool.fill), CanvasTool.fillShape);
      expect(notifier.railEntry(CanvasTool.cut), CanvasTool.cutStamp);

      // …and it follows the tile back, rather than preferring the shapes.
      notifier.value = notifier.value.copyWith(tool: CanvasTool.fill);
      notifier.value = notifier.value.copyWith(tool: CanvasTool.eraser);
      expect(notifier.railEntry(CanvasTool.fill), CanvasTool.fill);
    });

    test('the state it was CONSTRUCTED with counts as a visit', () {
      // The setter only sees changes; a shell that starts on a tile would
      // otherwise have to move off it once before the memory existed.
      final notifier = PaintToolStateNotifier(
        BrushToolState.defaults.copyWith(tool: CanvasTool.fillShape),
      );
      addTearDown(notifier.dispose);
      expect(notifier.railEntry(CanvasTool.fill), CanvasTool.fillShape);
    });

    test('a REFUSED switch leaves the memory where it was', () {
      // The guard keeps the outgoing tool, so nothing has moved — recording
      // the refused tool would send the button somewhere it cannot go.
      final notifier = PaintToolStateNotifier(
        BrushToolState.defaults.copyWith(tool: CanvasTool.fill),
      );
      addTearDown(notifier.dispose);
      notifier.switchGuard = (tool) =>
          tool == CanvasTool.fillShape ? 'no' : null;

      notifier.value = notifier.value.copyWith(tool: CanvasTool.fillShape);
      expect(notifier.value.tool, CanvasTool.fill, reason: 'refused');
      expect(notifier.railEntry(CanvasTool.fill), CanvasTool.fill);
    });
  });
}
