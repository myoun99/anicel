import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_settings_store.dart';

void main() {
  test('defaults feed the shortcuts map; every registry action resolves', () {
    final bindings = EditorShortcutBindings();
    final map = bindings.shortcuts;

    // One entry per default activator, each dispatching its action id.
    for (final definition in editorActionDefinitions) {
      for (final activator in definition.defaultActivators) {
        final intent = map[activator];
        expect(intent, isA<EditorActionIntent>());
        expect((intent! as EditorActionIntent).actionId, definition.id);
      }
    }
    expect(bindings.conflictedActionIds, isEmpty);
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
    addTearDown(() => directory.delete(recursive: true));
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
  });
}
