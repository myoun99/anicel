import 'package:flutter/material.dart';

import '../../models/app_language.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../widgets/settings_rows.dart';

/// The two-language settings (UI-R10 #7): program language (the app
/// chrome) and notation language (what prints on the timesheet and other
/// submission artifacts). Changes apply and persist immediately.
/// Dialog-free: SAVE-1 made the Preferences dialog its one home (the
/// standalone dialog that wrapped it went with its caller).
///
/// 🗣️F-480 (유저 2026-10-26): 「언어쪽도 똑같이 왼쪽 텍스트 오른쪽 버튼」 —
/// each a picker row ([SettingsPickerRow]). ↩️Each label stood over a
/// picker as wide as the window's middle.
class LanguageSettingsSection extends StatelessWidget {
  const LanguageSettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguageSettings>(
      valueListenable: session.languageSettings,
      builder: (context, settings, _) {
        final strings = AppStrings.of(settings.programLanguage);
        // F-2: what each language is for is a TOOLTIP. Two language
        // pickers a row apart really do need telling apart, so the words
        // survive — they just stop taking a line of the window each.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            settingsEnumPickerRow(
              keyValue: 'settings-program-language',
              label: strings.programLanguageLabel,
              help: strings.programLanguageHelp,
              value: settings.programLanguage,
              values: AppLanguage.values,
              labelOf: (language) => language.displayName,
              onPicked: (language) => session.setLanguageSettings(
                settings.copyWith(programLanguage: language),
              ),
            ),
            settingsEnumPickerRow(
              keyValue: 'settings-notation-language',
              label: strings.notationLanguageLabel,
              help: strings.notationLanguageHelp,
              value: settings.notationLanguage,
              values: AppLanguage.values,
              labelOf: (language) => language.displayName,
              onPicked: (language) => session.setLanguageSettings(
                settings.copyWith(notationLanguage: language),
              ),
            ),
          ],
        );
      },
    );
  }
}
