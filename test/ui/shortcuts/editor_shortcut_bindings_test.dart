import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_store.dart';
import '../../helpers/project_scratch_folder.dart';

void main() {
  test('defaults feed the shortcuts map; every registry action resolves', () {
    final bindings = EditorShortcutBindings();
    final map = bindings.shortcuts;

    // One entry per default activator, each dispatching its action id — a
    // HELD action excepted (I-15, pinned below).
    for (final definition in editorActionDefinitions.where((d) => !d.hold)) {
      for (final activator in definition.defaultActivators) {
        final intent = map[activator];
        expect(intent, isA<EditorActionIntent>());
        expect((intent! as EditorActionIntent).actionId, definition.id);
      }
    }
    expect(bindings.conflictedActionIds, isEmpty);
  });

  test('🗣️I-15: 「이동」 is HELD on Space — never an intent in the map — '
      'and playback lets Space go (its four-finger tap stays)', () {
    final bindings = EditorShortcutBindings();
    expect(
      editorActionDefinitions.where((d) => d.hold).map((d) => d.id),
      [EditorActionIds.canvasPanHold],
      reason: 'the one held action',
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
    expect(playback.defaultActivators, isEmpty);
    expect(playback.defaultTouchGesture, 'fourFingerTap');
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

    // Setting the exact defaults back clears the override entirely.
    bindings.setActivators(
      EditorActionIds.frameNext,
      bindings.definitionFor(EditorActionIds.frameNext)!.defaultActivators,
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

    bindings.resetAll();
    expect(bindings.conflictedActionIds, isEmpty);
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
