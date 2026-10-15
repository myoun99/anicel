import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';

/// The pumped app's live shortcut bindings, as its scope hands them down.
EditorShortcutBindings appShortcuts(WidgetTester tester) => tester
    .widget<EditorShortcutScope>(find.byType(EditorShortcutScope))
    .notifier!;

/// Puts the pumped app on the anicel preset — the registry's own keys, the
/// ones a test that presses them was written against. An install opens on
/// Clip Studio's (🗣️I-63-Q5, 유저 2026-10-09).
Future<void> useAnicelKeys(WidgetTester tester) async {
  appShortcuts(tester).setPreset(ShortcutPreset.anicel);
  await tester.pump();
}
