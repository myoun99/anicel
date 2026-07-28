import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/touch_shortcuts.dart';

/// R11-⑨: multi-finger touch shortcuts — the gesture recognizer, the
/// per-action bindings (defaults + overrides + persistence payload) and
/// the conflict surface.
void main() {
  group('TouchShortcutLayer', () {
    Future<List<TouchGesture>> pumpAndPerform(
      WidgetTester tester, {
      required int fingers,
      Duration hold = Duration.zero,
      Offset drift = Offset.zero,
    }) async {
      final fired = <TouchGesture>[];
      await tester.pumpWidget(
        MaterialApp(
          home: TouchShortcutLayer(
            onGesture: fired.add,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      );
      final gestures = [
        for (var finger = 0; finger < fingers; finger += 1)
          await tester.startGesture(Offset(100.0 + finger * 60, 200)),
      ];
      if (drift != Offset.zero) {
        await gestures.first.moveBy(drift);
      }
      if (hold > Duration.zero) {
        await tester.pump(hold);
      }
      for (final gesture in gestures) {
        // The recognizer measures EVENT timestamps; test events default to
        // zero, so the hold rides the up-event's stamp.
        await gesture.up(timeStamp: hold);
      }
      await tester.pump();
      return fired;
    }

    testWidgets('two/three/four-finger taps resolve', (tester) async {
      expect(await pumpAndPerform(tester, fingers: 2), [
        TouchGesture.twoFingerTap,
      ]);
      expect(await pumpAndPerform(tester, fingers: 3), [
        TouchGesture.threeFingerTap,
      ]);
      expect(await pumpAndPerform(tester, fingers: 4), [
        TouchGesture.fourFingerTap,
      ]);
    });

    testWidgets('a held release resolves to the hold gesture', (tester) async {
      expect(
        await pumpAndPerform(
          tester,
          fingers: 2,
          hold: const Duration(milliseconds: 700),
        ),
        [TouchGesture.twoFingerLongPress],
      );
    });

    testWidgets('movement (a pinch) and single fingers fire nothing', (
      tester,
    ) async {
      expect(
        await pumpAndPerform(tester, fingers: 2, drift: const Offset(60, 0)),
        isEmpty,
      );
      expect(await pumpAndPerform(tester, fingers: 1), isEmpty);
    });
  });

  group('touch bindings', () {
    test('defaults: two-finger tap = undo, three-finger tap = redo, '
        'four-finger tap = play/pause (PEN-7b)', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);
      expect(
        bindings.actionIdForTouchGesture(TouchGesture.twoFingerTap),
        EditorActionIds.undo,
      );
      expect(
        bindings.actionIdForTouchGesture(TouchGesture.threeFingerTap),
        EditorActionIds.redo,
      );
      expect(
        bindings.actionIdForTouchGesture(TouchGesture.fourFingerTap),
        EditorActionIds.playbackToggle,
      );
    });

    test('overrides bind, unbind and reset; conflicts surface', () {
      final bindings = EditorShortcutBindings();
      addTearDown(bindings.dispose);

      bindings.setTouchGesture(
        EditorActionIds.playbackToggle,
        TouchGesture.fourFingerTap,
      );
      expect(
        bindings.actionIdForTouchGesture(TouchGesture.fourFingerTap),
        EditorActionIds.playbackToggle,
      );

      // Binding the same gesture elsewhere surfaces BOTH as conflicted.
      bindings.setTouchGesture(
        EditorActionIds.onionSkinToggle,
        TouchGesture.fourFingerTap,
      );
      expect(
        bindings.touchConflictedActionIds,
        containsAll([
          EditorActionIds.playbackToggle,
          EditorActionIds.onionSkinToggle,
        ]),
      );

      // Explicit unbind kills a DEFAULT binding.
      bindings.setTouchGesture(EditorActionIds.undo, null);
      expect(
        bindings.actionIdForTouchGesture(TouchGesture.twoFingerTap),
        isNull,
      );
      bindings.resetAction(EditorActionIds.undo);
      expect(
        bindings.actionIdForTouchGesture(TouchGesture.twoFingerTap),
        EditorActionIds.undo,
      );
    });
  });
}
