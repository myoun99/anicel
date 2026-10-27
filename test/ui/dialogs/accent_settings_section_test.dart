// THE ACCENT PALETTE: A PRESET TAP APPLIES THAT ACCENT AT ONCE, AND THE
// PALETTE MARKS IT.
//
// No test named this section (audit 2026-09-03). This pin drives it as a
// user does — one tap on a preset — and reads the palette back. Since
// F-480 it is a row of the display tab (유저 2026-10-26: 「강조색상 탭 …
// 화면탭에 넣도록」).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/accent_settings_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;

void main() {
  testWidgets('a preset tap applies the accent and the palette marks it', (
    tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final before = AppColors.accentSettings.value;
    addTearDown(() => session.setAccentSettings(before));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AccentSettingsRow(session: session)),
      ),
    );
    Finder presetOf(Color color) => find.byKey(
      ValueKey<String>(
        'settings-accent1-preset-${color.toARGB32().toRadixString(16)}',
      ),
    );
    BorderSide edgeOf(Color color) {
      final box = tester.widget<Container>(
        find.descendant(of: presetOf(color), matching: find.byType(Container)),
      );
      final shape = (box.decoration! as ShapeDecoration).shape;
      return (shape as OutlinedBorder).side;
    }

    const preset = Color(0xFF5B9BD5);
    expect(edgeOf(preset), isNot(edgeOf(before.accent)), reason: '⛔전제');
    await tester.tap(presetOf(preset));
    await tester.pumpAndSettle();
    expect(AppColors.accentSettings.value.accent, preset);
    expect(
      edgeOf(preset),
      isNot(edgeOf(before.accent)),
      reason: 'the one picked wears the mark, the one before lets it go',
    );
    final marked = edgeOf(preset);
    await tester.tap(presetOf(before.accent));
    await tester.pumpAndSettle();
    expect(edgeOf(before.accent), marked);
  });
}
