import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/windows_key_state.dart'
    show vkControl, vkMenu;
import 'package:anicel/src/services/input/modifier_keys.dart';
import 'package:anicel/src/ui/shortcuts/lone_modifiers.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart'
    show singleActivatorLabel;

/// 🗣️F-603-Q1 (유저 2026-11-16): 「뗐을 때 — 그 사이에 다른 키나 클릭이
/// 없었으면 발동」 — and I-19-zoom-key-playback before it: modifiers let go
/// with nothing after them were a press of their own.
///
/// The keys held are what Windows says ([ModifierKeys] — the record is a
/// test's, empty): each event below is only WHEN they are asked.
void main() {
  late LoneModifiers lone;
  var held = <int>{};

  setUp(() {
    lone = LoneModifiers();
    held = {};
    ModifierKeys.debugWindowsKeyDown = (key) => held.contains(key);
  });
  tearDown(() => ModifierKeys.debugWindowsKeyDown = null);

  KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
  KeyEvent up(LogicalKeyboardKey key) => KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
  String? named(SingleActivator? pressed) =>
      pressed == null ? null : singleActivatorLabel(pressed);

  const ctrl = LogicalKeyboardKey.controlLeft;
  const alt = LogicalKeyboardKey.altLeft;

  testWidgets('a modifier let go with nothing after it is pressed — at its '
      'release, and at no other event', (tester) async {
    held = {vkControl};
    expect(lone.hearKey(down(ctrl)), isNull, reason: 'not at its press');
    held = {};
    final release = up(ctrl);
    expect(named(lone.hearKey(release)), 'Ctrl');
    expect(named(lone.pressedAt(release)), 'Ctrl');
    expect(
      lone.pressedAt(up(ctrl)),
      isNull,
      reason: 'only the event it was found at',
    );
    expect(lone.hearKey(up(ctrl)), isNull, reason: 'once');
  });

  testWidgets('a key\'s down after it, or a pointer\'s press, and it is no '
      'press — a hover is nothing after it', (tester) async {
    held = {vkControl};
    lone.hearKey(down(ctrl));
    expect(lone.hearKey(down(LogicalKeyboardKey.keyZ)), isNull);
    lone.hearKey(up(LogicalKeyboardKey.keyZ));
    held = {};
    expect(lone.hearKey(up(ctrl)), isNull, reason: 'Ctrl+Z');

    held = {vkControl};
    lone.hearKey(down(ctrl));
    lone.hearPointer(const PointerDownEvent());
    held = {};
    expect(lone.hearKey(up(ctrl)), isNull, reason: 'a Ctrl+click');

    held = {vkControl};
    lone.hearKey(down(ctrl));
    lone.hearPointer(const PointerHoverEvent());
    held = {};
    expect(named(lone.hearKey(up(ctrl))), 'Ctrl', reason: 'a hover');
  });

  testWidgets('every modifier held as the last went down is the press, '
      'whichever is let go first — and the rest let go press nothing', (
    tester,
  ) async {
    held = {vkControl};
    lone.hearKey(down(ctrl));
    held = {vkControl, vkMenu};
    lone.hearKey(down(alt));
    held = {vkMenu};
    expect(named(lone.hearKey(up(ctrl))), 'Ctrl+Alt');
    held = {};
    expect(lone.hearKey(up(alt)), isNull);
  });

  testWidgets('🚨a key-up the engine makes up under a pen, the key still '
      'down, is no release — and the release it drops is found at the next '
      'event, a pointer\'s too', (tester) async {
    held = {vkControl};
    lone.hearKey(down(ctrl));
    expect(lone.hearKey(up(ctrl)), isNull, reason: 'Windows holds it');
    held = {};
    expect(named(lone.hearPointer(const PointerHoverEvent())), 'Ctrl');
  });

  testWidgets('forgotten, the modifiers held are no press when let go', (
    tester,
  ) async {
    held = {vkControl};
    lone.hearKey(down(ctrl));
    lone.forget();
    held = {};
    expect(lone.hearKey(up(ctrl)), isNull);
  });
}
