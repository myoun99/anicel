import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/windows_key_state.dart'
    show vkControl, vkLeftWindows;
import 'package:anicel/src/services/input/modifier_keys.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';

/// 🗣️H65 (유저 2026-11-21): 「아이패드에서 키보드 블루투스로 연결해서 쓰는데
/// 일반키보드거든? 윈도우 기준 키보드?」, then 「뭐 설정안해도 먹히는게
/// 편해서」 — H65-Q1 「both」: a command is pressed with Ctrl or with ⌘ on
/// every device, and written as the device writes it. A key held AS IT IS
/// wins over another's other command form.
void main() {
  late EditorShortcutBindings bindings;

  setUp(() => bindings = EditorShortcutBindings()..setPreset(
    ShortcutPreset.tvpaint,
  ));
  tearDown(() {
    bindings.dispose();
    ModifierKeys.debugWindowsKeyDown = null;
  });

  const z = LogicalKeyboardKey.keyZ;
  const c = LogicalKeyboardKey.keyC;

  /// The app's keys over [body], every action they run told in [ran].
  Future<void> pumpKeys(
    WidgetTester tester,
    List<String> ran, {
    Widget body = const Focus(autofocus: true, child: SizedBox()),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts.manager(
          manager: EditorShortcutManager(shortcuts: bindings.shortcuts),
          child: Actions(
            actions: <Type, Action<Intent>>{
              EditorActionIntent: CallbackAction<EditorActionIntent>(
                onInvoke: (intent) => ran.add(intent.actionId),
              ),
            },
            child: Scaffold(body: body),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressWith(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  testWidgets('Ctrl+Z and ⌘Z are both undo, on every device', (tester) async {
    final ran = <String>[];
    await pumpKeys(tester, ran);

    await pressWith(tester, LogicalKeyboardKey.controlLeft, z);
    await pressWith(tester, LogicalKeyboardKey.metaLeft, z);

    expect(ran, [EditorActionIds.undo, EditorActionIds.undo]);
  }, variant: TargetPlatformVariant.all());

  testWidgets('a key held as it is wins: ⌃Z recorded on an iPad is its '
      'action\'s, and ⌘Z stays undo', (tester) async {
    bindings.setActivators(EditorActionIds.cutNew, const [
      SingleActivator(z, control: true),
    ]);
    final ran = <String>[];
    await pumpKeys(tester, ran);

    await pressWith(tester, LogicalKeyboardKey.controlLeft, z);
    await pressWith(tester, LogicalKeyboardKey.metaLeft, z);

    expect(ran, [EditorActionIds.cutNew, EditorActionIds.undo]);
    expect(
      bindings.conflictedActionIds,
      isNot(contains(EditorActionIds.undo)),
      reason: 'the other form is no key of undo\'s to clash',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('written as the device writes it: an iPad shows undo\'s one '
      'key, ⌘Z', (tester) async {
    final keys = bindings.activatorsFor(EditorActionIds.undo);
    expect(
      keys.where((key) => key.trigger == z).map(singleActivatorLabel),
      ['⌘Z'],
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  test('the held keys and the playback gate ask the same: presses', () {
    KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyZ,
      logicalKey: key,
      timeStamp: Duration.zero,
    );
    // The modifiers held, as Windows says (the record is a test's: empty).
    void hold(Set<int> virtualKeys) =>
        ModifierKeys.debugWindowsKeyDown = virtualKeys.contains;

    hold({vkControl});
    expect(bindings.presses(EditorActionIds.undo, down(z)), isTrue);
    hold({vkLeftWindows});
    expect(bindings.presses(EditorActionIds.undo, down(z)), isTrue);

    bindings.setActivators(EditorActionIds.cutNew, const [
      SingleActivator(z, meta: true),
    ]);
    expect(
      bindings.presses(EditorActionIds.undo, down(z)),
      isFalse,
      reason: '⌘Z is held as it is by another action',
    );
    expect(bindings.presses(EditorActionIds.cutNew, down(z)), isTrue);
  });

  testWidgets('🚨in a text field the other form is the field\'s: Ctrl+C in '
      'a rename box on an iPad copies no frame', (tester) async {
    expect(
      bindings
          .activatorsFor(EditorActionIds.editCopy)
          .any((key) => key.trigger == c && key.meta && !key.control),
      isTrue,
      reason: '⛔fixture premise: copy is ⌘C on an iPad',
    );
    final ran = <String>[];
    await pumpKeys(
      tester,
      ran,
      body: const TextField(autofocus: true),
    );

    await pressWith(tester, LogicalKeyboardKey.controlLeft, c);
    await pressWith(tester, LogicalKeyboardKey.metaLeft, c);

    expect(ran, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('outside a field Ctrl+C on an iPad is copy', (tester) async {
    final ran = <String>[];
    await pumpKeys(tester, ran);

    await pressWith(tester, LogicalKeyboardKey.controlLeft, c);

    expect(ran, [EditorActionIds.editCopy]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
