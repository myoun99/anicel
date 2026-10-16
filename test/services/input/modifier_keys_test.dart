import 'package:anicel/src/native/windows_key_state.dart';
import 'package:anicel/src/services/input/modifier_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🗣️I-61 (유저 2026-10-16): 「마우스던 펜이던 터치묘화던 그림 그리는
/// 동작이라면 해야하는건데」 — whether a modifier is held is one answer for
/// every pointer, and on Windows the engine's record is not it: a pen's or
/// a finger's move lets go of Shift and Ctrl there with the key still down.
void main() {
  tearDown(() => ModifierKeys.debugWindowsKeyDown = null);

  testWidgets('what the engine\'s record holds is held', (tester) async {
    expect(ModifierKeys.isShiftPressed, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(ModifierKeys.isShiftPressed, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(ModifierKeys.isShiftPressed, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
    expect(ModifierKeys.isControlPressed, isTrue);
    expect(ModifierKeys.isShiftPressed, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);
  });

  testWidgets('🚨what Windows says is held is held though the record let go '
      'of it — each modifier by its own key', (tester) async {
    final heldBy = <bool Function(), List<int>>{
      () => ModifierKeys.isShiftPressed: [vkShift],
      () => ModifierKeys.isControlPressed: [vkControl],
      () => ModifierKeys.isAltPressed: [vkMenu],
      () => ModifierKeys.isMetaPressed: [vkLeftWindows, vkRightWindows],
    };
    for (final MapEntry(key: held, value: keys) in heldBy.entries) {
      for (final key in keys) {
        ModifierKeys.debugWindowsKeyDown = (asked) => asked == key;
        expect(held(), isTrue, reason: 'virtual key $key');
        for (final other in heldBy.keys) {
          if (other != held) {
            expect(other(), isFalse, reason: 'virtual key $key is not that');
          }
        }
      }
    }
    ModifierKeys.debugWindowsKeyDown = (_) => false;
    for (final held in heldBy.keys) {
      expect(held(), isFalse);
    }
  });

  testWidgets('the keyboard a shortcut reads is the record with what Windows '
      'holds put back', (tester) async {
    const space = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.space,
      logicalKey: LogicalKeyboardKey.space,
      timeStamp: Duration.zero,
    );
    const turn = SingleActivator(LogicalKeyboardKey.space, shift: true);
    const pan = SingleActivator(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);

    ModifierKeys.debugWindowsKeyDown = (key) => key == vkShift;
    expect(turn.accepts(space, ModifierKeys.keyboard), isTrue);
    expect(pan.accepts(space, ModifierKeys.keyboard), isFalse);
    expect(ModifierKeys.keyboard.isShiftPressed, isTrue);
    expect(
      ModifierKeys.keyboard.logicalKeysPressed,
      containsAll([LogicalKeyboardKey.keyA, LogicalKeyboardKey.shiftLeft]),
    );

    ModifierKeys.debugWindowsKeyDown = (_) => false;
    expect(turn.accepts(space, ModifierKeys.keyboard), isFalse);
    expect(pan.accepts(space, ModifierKeys.keyboard), isTrue);
    expect(ModifierKeys.keyboard.logicalKeysPressed, {LogicalKeyboardKey.keyA});
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
  });
}
