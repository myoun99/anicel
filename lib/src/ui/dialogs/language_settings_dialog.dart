import 'package:flutter/material.dart';

import '../../models/app_language.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// The two-language settings dialog (UI-R10 #7): program language (the
/// app chrome) and notation language (what prints on the timesheet and
/// other submission artifacts). Changes apply and persist immediately.
Future<void> showLanguageSettingsDialog(
  BuildContext context, {
  required EditorSessionManager session,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _LanguageSettingsDialog(session: session),
  );
}

class _LanguageSettingsDialog extends StatelessWidget {
  const _LanguageSettingsDialog({required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguageSettings>(
      valueListenable: session.languageSettings,
      builder: (context, settings, _) {
        final strings = AppStrings.of(settings.programLanguage);
        return AppWindow(
          windowKey: const ValueKey<String>('language-settings-dialog'),
          title: strings.languageSettingsTitle,
          titleIcon: Icons.translate_outlined,
          onClose: () => Navigator.of(context).pop(),
          width: 420,
          body: LanguageSettingsSection(session: session),
          actions: [
            AppWindowAction(
              label: strings.commonClose,
              actionKey: const ValueKey<String>('settings-language-close'),
              emphasis: AppWindowActionEmphasis.primary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}

/// The language-settings CONTENT, dialog-free (SAVE-1: the Preferences
/// dialog embeds it as a section; the standalone dialog wraps it).
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
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
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
          const SizedBox(height: 2),
          Text(
            help,
            style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
