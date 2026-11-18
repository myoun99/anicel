import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/windows_key_state.dart'
    show vkControl, vkMenu;
import 'package:anicel/src/services/input/modifier_keys.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_store.dart';
import '../../helpers/project_scratch_folder.dart';

void main() {
  for (final preset in ShortcutPreset.values) {
    test('${preset.name}\'s keys feed the shortcuts map; every registry '
        'action resolves', () {
      final bindings = EditorShortcutBindings()..setPreset(preset);
      addTearDown(bindings.dispose);
      // A move on the sheet is keyed by its TURNED form (F-241), which holds
      // the default it turns.
      final map = {
        for (final MapEntry(:key, :value) in bindings.shortcuts.entries)
          (key is SheetTurnedActivator ? key.timeline : key): value,
      };

      // One entry per key the preset gives an action, each dispatching its
      // action id — a HELD action excepted (I-15, pinned below).
      for (final definition in editorActionDefinitions.where((d) => !d.hold)) {
        for (final activator in presetActivators(preset, definition)) {
          final intent = map[activator];
          expect(intent, isA<EditorActionIntent>(), reason: definition.id);
          expect((intent! as EditorActionIntent).actionId, definition.id);
        }
      }
      expect(bindings.conflictedActionIds, isEmpty);
    });
  }

  test('🗣️I-103-Q2: the list holds the registry as this platform offers it, '
      'before anything else is told — no full screen on a tablet', () {
    final bindings = EditorShortcutBindings();
    addTearDown(bindings.dispose);
    expect(bindings.definitions, editorActionsHere());
    expect(
      editorActionsHere().map((action) => action.id),
      isNot(contains(EditorActionIds.fullScreen)),
      reason: '⛔premise: the suite runs as Android',
    );
    expect(bindings.definitionFor(EditorActionIds.fullScreen), isNull);
  });

  test('🗣️I-15: 「이동」 is HELD on Space — never an intent in the map — '
      'and playback lets Space go (its four-finger tap stays)', () {
    final bindings = EditorShortcutBindings();
    expect(
      editorActionDefinitions.where((d) => d.hold).map((d) => d.id),
      [
        EditorActionIds.canvasPanHold,
        EditorActionIds.canvasRotateHold,
        EditorActionIds.canvasLineHold,
        EditorActionIds.eyedropperHold,
      ],
      reason: 'the view\'s two held actions — the pan, and the turn (I-88) '
          '— the line from the last stroke (I-119), and the eyedropper '
          '(I-15, a key since F-603)',
    );
    final pan = bindings.activatorsFor(EditorActionIds.canvasPanHold);
    expect(pan, hasLength(1));
    expect(
      activatorsEqual(
        pan.single,
        const SingleActivator(LogicalKeyboardKey.space),
      ),
      isTrue,
    );
    expect(
      bindings.shortcuts.keys.whereType<SingleActivator>().where(
        (activator) => activator.trigger == LogicalKeyboardKey.space,
      ),
      isEmpty,
      reason: 'Space dispatches no intent — the hold takes it on the way',
    );
    final playback = bindings.definitionFor(EditorActionIds.playbackToggle)!;
    // ↩️F-261 (유저 2026-10-02): 「재생/정지버튼은 S로」 — a key again, and
    // still not Space — then 「재생을 쉬프트x」 once S walked down the sheet.
    expect(
      activatorsEqual(
        playback.defaultActivators.single,
        const SingleActivator(LogicalKeyboardKey.keyX, shift: true),
      ),
      isTrue,
    );
    expect(playback.defaultTouchGesture, 'fourFingerTap');
  });

  // a-key-is-the-character-it-types: the typed form exists for a binding
  // that NAMES a character. ⛔A binding with Shift names a KEY — Shift+. is
  // the `>` key's place — and on a layout that types `.` under Shift, the
  // `.` it types belongs to a binding that names `.`, not to the zoom: two
  // typed forms of one character would leave the press to map order.
  // Unobservable through the defaults, so it is pinned here. ↩️The zoom left
  // Shift+. in F-261; the rule holds for any binding recorded with Shift.
  test('a binding WITH Shift gets no typed form — only one that names a '
      'character does', () {
    expect(
      pressableForms(
        const SingleActivator(LogicalKeyboardKey.period, shift: true),
      ),
      hasLength(1),
    );
    expect(
      pressableForms(const SingleActivator(LogicalKeyboardKey.period)),
      hasLength(2),
      reason: '⛔전제: the same key without Shift does',
    );
  });

  test('overrides replace defaults, re-recording back to the default '
      'clears the override, unbinding is expressible', () {
    final bindings = EditorShortcutBindings();
    var notifies = 0;
    bindings.addListener(() => notifies += 1);

    const custom = SingleActivator(LogicalKeyboardKey.keyN);
    bindings.setActivators(EditorActionIds.frameNext, const [custom]);
    expect(notifies, 1);
    expect(bindings.isOverridden(EditorActionIds.frameNext), isTrue);
    expect(
      activatorsEqual(
        bindings.primaryActivatorFor(EditorActionIds.frameNext)!,
        custom,
      ),
      isTrue,
    );
    // The old default no longer dispatches this action.
    final map = bindings.shortcuts;
    expect(
      map.keys.any(
        (activator) =>
            activator is SingleActivator &&
            activator.trigger == LogicalKeyboardKey.keyN,
      ),
      isTrue,
    );

    // Setting the exact defaults back clears the override entirely — the
    // preset's, which are the registry's only where neither program names
    // the row (F-417).
    bindings.setActivators(
      EditorActionIds.frameNext,
      bindings.defaultActivatorsFor(EditorActionIds.frameNext),
    );
    expect(bindings.isOverridden(EditorActionIds.frameNext), isFalse);

    // An empty list = deliberately unbound.
    bindings.setActivators(EditorActionIds.frameNext, const []);
    expect(bindings.primaryActivatorFor(EditorActionIds.frameNext), isNull);

    bindings.resetAction(EditorActionIds.frameNext);
    expect(bindings.isOverridden(EditorActionIds.frameNext), isFalse);
  });

  test('conflicts surface both colliding actions', () {
    final bindings = EditorShortcutBindings();
    // Bind Next Frame to the eraser's default key.
    bindings.setActivators(EditorActionIds.frameNext, const [
      SingleActivator(LogicalKeyboardKey.keyE),
    ]);

    expect(
      bindings.conflictedActionIds,
      containsAll({EditorActionIds.frameNext, EditorActionIds.toolEraser}),
    );

    expect(
      bindings.resetAllChanges,
      isTrue,
      reason: 'a key recorded over the preset is something to reset',
    );
    bindings.resetAll();
    expect(bindings.conflictedActionIds, isEmpty);
    expect(
      bindings.resetAllChanges,
      isFalse,
      reason: 'the preset as it ships has nothing to reset (F-583)',
    );
  });

  test('a touch gesture recorded over the preset, with no key, is as much '
      'to reset as a key', () {
    final bindings = EditorShortcutBindings();
    addTearDown(bindings.dispose);
    expect(bindings.resetAllChanges, isFalse, reason: '⛔premise');

    bindings.setTouchGesture(EditorActionIds.undo, null);

    expect(bindings.resetAllChanges, isTrue);
    bindings.resetAll();
    expect(bindings.resetAllChanges, isFalse);
  });

  // 🗣️I-158 (유저 2026-11-04): 「펜(Y)이런식으로 이 텍스트를 버튼으로
  // 만들어서, 이걸로 할당하는 기능 … 그거 버튼누르면 올가미채우기의 키가
  // 사라지는식으로」.
  group('🗣️I-158: a clash', () {
    const spare = SingleActivator(LogicalKeyboardKey.f20);
    const other = SingleActivator(LogicalKeyboardKey.f19);
    const a = EditorActionIds.frameNext;
    const b = EditorActionIds.framePrevious;
    const c = EditorActionIds.toolEraser;
    List<String> keysOf(EditorShortcutBindings bindings, String id) => [
      for (final activator in bindings.activatorsFor(id))
        activatorKey(activator),
    ];

    test('names its key and its holders, in the registry\'s order', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      expect(bindings.keyClashes, isEmpty);
      bindings
        ..setActivators(b, const [spare])
        ..setActivators(a, const [spare, other]);

      final [clash] = bindings.keyClashes;
      expect(activatorKey(clash.key), activatorKey(spare));
      final registry = [for (final row in bindings.definitions) row.id];
      expect(clash.holders, unorderedEquals([a, b]));
      expect(
        clash.holders,
        [...clash.holders]..sort(
          (x, y) => registry.indexOf(x).compareTo(registry.indexOf(y)),
        ),
      );
      expect(bindings.conflictedActionIds, clash.holders.toSet());
    });

    test('given to one holder, leaves the others with the rest of their '
        'keys, and ends', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      bindings
        ..setActivators(a, const [spare, other])
        ..setActivators(b, const [spare])
        ..setActivators(c, const [spare]);
      var told = 0;
      bindings.addListener(() => told++);

      bindings.giveKeyTo(b, spare);

      expect(keysOf(bindings, b), [activatorKey(spare)]);
      expect(keysOf(bindings, a), [activatorKey(other)]);
      expect(keysOf(bindings, c), isEmpty);
      expect(bindings.keyClashes, isEmpty);
      expect(told, 1, reason: 'one change, told once');
    });

    test('given to an action that lost it, takes it back', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      bindings
        ..setActivators(a, const [spare])
        ..setActivators(b, const [spare])
        ..giveKeyTo(b, spare)
        ..giveKeyTo(a, spare);

      expect(keysOf(bindings, a), [activatorKey(spare)]);
      expect(keysOf(bindings, b), isEmpty);
    });

    test('given back to a holder as it shipped, records nothing over it', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      final shipped = bindings.activatorsFor(c).first;
      bindings.setActivators(a, [shipped]);

      bindings.giveKeyTo(c, shipped);

      expect(bindings.isOverridden(c), isFalse);
      expect(keysOf(bindings, a), isEmpty);
    });
  });

  test('overrides persist through the store and restore on launch; '
      'unknown actions and malformed entries are dropped', () async {
    final directory = await Directory.systemTemp.createTemp('shortcuts-test');
    deleteAfterSessionEnds(directory);
    final path = '${directory.path}/overrides.json';

    final store = ShortcutSettingsStore(filePath: path);
    final bindings = EditorShortcutBindings(store: store);
    bindings.setActivators(EditorActionIds.undo, const [
      SingleActivator(LogicalKeyboardKey.keyU, control: true, alt: true),
    ]);
    // 「No key」 is an answer like any other (F-318: the window's button
    // records it) — the default must not be back at the next launch.
    expect(
      bindings.activatorsFor(EditorActionIds.redo),
      isNotEmpty,
      reason: '⛔premise: redo ships with a key',
    );
    bindings.setActivators(EditorActionIds.redo, const []);
    // The persist is fire-and-forget from the caller's view; the exposed
    // chain says when it has actually hit disk.
    await bindings.pendingPersist;
    expect(File(path).existsSync(), isTrue);

    final restored = EditorShortcutBindings(
      store: ShortcutSettingsStore(filePath: path),
    );
    await restored.restore();
    final activator = restored.primaryActivatorFor(EditorActionIds.undo)!;
    expect(activator.trigger, LogicalKeyboardKey.keyU);
    expect(activator.control, isTrue);
    expect(activator.alt, isTrue);
    expect(activator.shift, isFalse);
    expect(restored.activatorsFor(EditorActionIds.redo), isEmpty);
    expect(restored.isOverridden(EditorActionIds.redo), isTrue);

    // Corrupt/unknown content never breaks the bindings.
    File(path).writeAsStringSync(
      '{"version":1,"overrides":{"no-such-action":[{"key":32}],'
      '"edit-undo":[{"bogus":true},{"key":${LogicalKeyboardKey.keyW.keyId}}]}}',
    );
    final sanitized = EditorShortcutBindings(
      store: ShortcutSettingsStore(filePath: path),
    );
    await sanitized.restore();
    expect(sanitized.definitionFor('no-such-action'), isNull);
    final undoActivators = sanitized.activatorsFor(EditorActionIds.undo);
    expect(undoActivators, hasLength(1));
    expect(undoActivators.single.trigger, LogicalKeyboardKey.keyW);
  });

  test('activator codec round-trips and labels read naturally', () {
    const activator = SingleActivator(
      LogicalKeyboardKey.keyZ,
      control: true,
      shift: true,
    );
    final restored = singleActivatorFromJson(singleActivatorToJson(activator))!;
    expect(activatorsEqual(restored, activator), isTrue);

    expect(singleActivatorLabel(activator), 'Ctrl+Shift+Z');
    expect(
      singleActivatorLabel(const SingleActivator(LogicalKeyboardKey.space)),
      'Space',
    );
    expect(
      singleActivatorLabel(
        const SingleActivator(LogicalKeyboardKey.comma, control: true),
      ),
      'Ctrl+,',
    );
    expect(
      singleActivatorLabel(const SingleActivator(LogicalKeyboardKey.arrowLeft)),
      '←',
    );
    // A NAMED key keeps its own case: upper-casing every label printed
    // ENTER and BACKSPACE.
    expect(
      singleActivatorLabel(const SingleActivator(LogicalKeyboardKey.backspace)),
      'Backspace',
    );
  });

  // 🗣️F-603 (유저 2026-11-16): 「단축키등록시 alt나 컨트롤키를 눌러도
  // 단축키등록안됨. 다 가능하게」.
  test('a key that is modifiers alone keeps through the file and reads as '
      'its modifiers — and one with none of them is no key', () {
    final ctrlAlt = modifiersAloneActivator(control: true, alt: true);
    final restored = singleActivatorFromJson(singleActivatorToJson(ctrlAlt))!;
    expect(activatorsEqual(restored, ctrlAlt), isTrue);
    expect(isModifiersAlone(restored), isTrue);

    expect(singleActivatorLabel(ctrlAlt, TargetPlatform.windows), 'Ctrl+Alt');
    expect(singleActivatorLabel(ctrlAlt, TargetPlatform.macOS), '⌃⌥');
    expect(
      singleActivatorLabel(
        modifiersAloneActivator(alt: true),
        TargetPlatform.windows,
      ),
      'Alt',
    );
    expect(
      singleActivatorFromJson({'key': modifiersAlone.keyId}),
      isNull,
      reason: 'modifiers alone with none of them held is malformed',
    );
    expect(
      activatorsEqual(
        modifiersAloneActivator(alt: true),
        modifiersAloneActivator(control: true, alt: true),
      ),
      isFalse,
      reason: 'Alt alone is not Ctrl+Alt',
    );
  });

  testWidgets('🚨a key that is modifiers alone presses a HELD action as they '
      'go down — every one held and no other — and a pressed one as they '
      'are let go alone (F-603-Q1)', (tester) async {
    final bindings = EditorShortcutBindings()
      ..setPreset(ShortcutPreset.anicel);
    final alt = modifiersAloneActivator(alt: true);
    bindings
      ..setActivators(EditorActionIds.canvasPanHold, [alt])
      ..setActivators(EditorActionIds.undo, [alt]);
    addTearDown(() => ModifierKeys.debugWindowsKeyDown = null);

    KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.altLeft,
      logicalKey: key,
      timeStamp: Duration.zero,
    );
    // The modifiers held, as Windows says (the record is a test's: empty).
    void hold(Set<int> virtualKeys) =>
        ModifierKeys.debugWindowsKeyDown = virtualKeys.contains;

    hold({vkMenu});
    final press = down(LogicalKeyboardKey.altRight);
    bindings.lone.hearKey(press);
    expect(bindings.presses(EditorActionIds.canvasPanHold, press), isTrue);
    expect(
      bindings.presses(EditorActionIds.undo, press),
      isFalse,
      reason: 'a pressed one is not pressed as they go down',
    );
    expect(
      bindings.shortcuts.keys.whereType<ModifiersDownActivator>(),
      isEmpty,
      reason: 'nor is a held one in the map the pressed actions run through',
    );
    expect(bindings.shortcuts.keys.whereType<ModifiersLetGoActivator>(), [
      isA<ModifiersLetGoActivator>(),
    ]);

    hold({});
    const release = KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.altRight,
      logicalKey: LogicalKeyboardKey.altRight,
      timeStamp: Duration.zero,
    );
    bindings.lone.hearKey(release);
    expect(bindings.presses(EditorActionIds.undo, release), isTrue);
    expect(
      bindings.presses(EditorActionIds.canvasPanHold, release),
      isFalse,
      reason: 'a held one let go is let go',
    );

    hold({vkMenu, vkControl});
    expect(
      bindings.presses(
        EditorActionIds.canvasPanHold,
        down(LogicalKeyboardKey.altLeft),
      ),
      isFalse,
      reason: 'Ctrl+Alt is not Alt alone',
    );
  });

  group('🗣️유저 2026-09-13: 「맥은 컨트롤키가 다르다 했던가? 쉬프트도?」', () {
    test('the registry\'s Ctrl is the platform\'s COMMAND key — ⌘ on macOS '
        'and iOS, Ctrl everywhere else — and Shift is Shift', () {
      const undo = SingleActivator(LogicalKeyboardKey.keyZ, control: true);
      const redo = SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      );
      for (final platform in const [TargetPlatform.macOS, TargetPlatform.iOS]) {
        final onApple = platformActivator(redo, platform);
        expect(onApple.meta, isTrue, reason: '$platform');
        expect(onApple.control, isFalse, reason: '$platform');
        expect(onApple.shift, isTrue, reason: 'Shift is the same key');
      }
      for (final platform in const [
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.android,
      ]) {
        expect(
          identical(platformActivator(undo, platform), undo),
          isTrue,
          reason: '$platform reads the registry as written',
        );
      }
      const plain = SingleActivator(LogicalKeyboardKey.keyB);
      expect(
        identical(platformActivator(plain, TargetPlatform.macOS), plain),
        isTrue,
        reason: 'a key with no command modifier is the same key everywhere',
      );
    });

    test('each platform WRITES a shortcut its own way', () {
      const saveAs = SingleActivator(
        LogicalKeyboardKey.keyS,
        shift: true,
        meta: true,
      );
      expect(singleActivatorLabel(saveAs, TargetPlatform.macOS), '⇧⌘S');
      expect(singleActivatorLabel(saveAs, TargetPlatform.iOS), '⇧⌘S');
      expect(
        singleActivatorLabel(
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ),
          TargetPlatform.windows,
        ),
        'Ctrl+Shift+S',
      );
      expect(
        singleActivatorLabel(
          const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
          TargetPlatform.windows,
        ),
        'Win+E',
      );
      expect(
        singleActivatorLabel(
          const SingleActivator(LogicalKeyboardKey.backspace),
          TargetPlatform.macOS,
        ),
        '⌫',
      );
    });

    test('on a Mac the live bindings, the map and the override store all '
        'speak ⌘', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final bindings = EditorShortcutBindings();
        final undo = bindings.primaryActivatorFor(EditorActionIds.undo)!;
        expect(undo.meta, isTrue);
        expect(undo.control, isFalse);
        expect(
          bindings.shortcuts.entries.any(
            (entry) =>
                entry.key is SingleActivator &&
                (entry.key as SingleActivator).trigger ==
                    LogicalKeyboardKey.keyZ &&
                (entry.key as SingleActivator).control &&
                !(entry.key as SingleActivator).shift,
          ),
          isFalse,
          reason: 'Ctrl+Z is not undo on a Mac',
        );
        // Recording ⌘Z by hand is recording the default, not an override.
        bindings.setActivators(EditorActionIds.undo, const [
          SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
        ]);
        expect(bindings.isOverridden(EditorActionIds.undo), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
