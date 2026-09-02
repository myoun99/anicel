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
class LanguageSettingsSection extends StatelessWidget {
  const LanguageSettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguageSettings>(
      valueListenable: session.languageSettings,
      builder: (context, settings, _) {
        final strings = AppStrings.of(settings.programLanguage);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LanguageRow(
              key: const ValueKey<String>('settings-program-language'),
              label: strings.programLanguageLabel,
              help: strings.programLanguageHelp,
              value: settings.programLanguage,
              onChanged: (language) => session.setLanguageSettings(
                settings.copyWith(programLanguage: language),
              ),
            ),
            const SizedBox(height: 16),
            _LanguageRow(
              key: const ValueKey<String>('settings-notation-language'),
              label: strings.notationLanguageLabel,
              help: strings.notationLanguageHelp,
              value: settings.notationLanguage,
              onChanged: (language) => session.setLanguageSettings(
                settings.copyWith(notationLanguage: language),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    super.key,
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String help;
  final AppLanguage value;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    // F-2: the caption under the picker is a TOOLTIP now. Two language
    // pickers a few pixels apart really do need telling apart, so the words
    // survive — they just stop taking two lines of the window each.
    return settingsHelpTooltip(
      help,
      SizedBox(
        width: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            DropdownButton<AppLanguage>(
              value: value,
              isExpanded: true,
              items: [
                for (final language in AppLanguage.values)
                  DropdownMenuItem(
                    key: ValueKey<String>('language-option-${language.name}'),
                    value: language,
                    child: Text(language.displayName),
                  ),
              ],
              onChanged: (language) {
                if (language != null) {
                  onChanged(language);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
