// THE ACCENT PALETTE: A PRESET TAP APPLIES THAT ACCENT AT ONCE, AND THE
// SWATCH SHOWS IT.
//
// No test named this section (audit 2026-09-03). This pin drives it as a
// user does — one tap on a preset — and reads the swatch back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/dialogs/accent_settings_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;

void main() {
  testWidgets('a preset tap applies the accent and the swatch shows it', (
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
        home: Scaffold(body: AccentSettingsSection(session: session)),
      ),
    );
    Color swatchColor() {
      final box = tester.widget<Container>(
        find.byKey(const ValueKey<String>('settings-accent1-swatch')),
      );
      return (box.decoration! as ShapeDecoration).color!;
    }

    const preset = Color(0xFF5B9BD5);
    expect(swatchColor(), before.accent);
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-accent1-preset-ff5b9bd5')),
    );
    await tester.pumpAndSettle();
    expect(AppColors.accentSettings.value.accent, preset);
    expect(swatchColor(), preset);
  });
}
