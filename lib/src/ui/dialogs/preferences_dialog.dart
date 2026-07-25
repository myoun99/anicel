import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../widgets/app_window.dart';
import 'accent_settings_dialog.dart' show AccentSettingsSection;
import 'audio_settings_section.dart';
import 'autosave_settings_section.dart';
import 'input_settings_dialog.dart' show InputSettingsSection;
import 'language_settings_dialog.dart' show LanguageSettingsSection;
import 'system_status_section.dart';
import '../text/app_strings.dart';

/// SAVE-1: the unified Preferences dialog — Input, Autosave, Audio,
/// Language, Accent Colors and System (the runtime-path report) as
/// sections of ONE window (the old per-domain Edit menu entries
/// collapsed here; their dialogs remain as thin wrappers around the same
/// section widgets for tests and deep links).
enum PreferencesSection { input, autosave, audio, language, accent, system }

Future<void> showPreferencesDialog(
  BuildContext context, {
  required EditorSessionManager session,
  PreferencesSection initialSection = PreferencesSection.input,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _PreferencesDialog(session: session, initialSection: initialSection),
  );
}

class _PreferencesDialog extends StatefulWidget {
  const _PreferencesDialog({
    required this.session,
    required this.initialSection,
  });

  final EditorSessionManager session;
  final PreferencesSection initialSection;

  @override
  State<_PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<_PreferencesDialog> {
  late PreferencesSection _section = widget.initialSection;

  static String _labelOf(PreferencesSection section) {
    final strings = AppText.strings;
    return switch (section) {
      PreferencesSection.input => strings.prefsInput,
      PreferencesSection.autosave => strings.prefsAutosave,
      PreferencesSection.audio => strings.prefsAudio,
      PreferencesSection.language => strings.prefsLanguage,
      PreferencesSection.accent => strings.prefsAccent,
      PreferencesSection.system => strings.prefsSystem,
    };
  }

  Widget _bodyOf(PreferencesSection section) => switch (section) {
    PreferencesSection.input => InputSettingsSection(session: widget.session),
    PreferencesSection.autosave => AutosaveSettingsSection(
      session: widget.session,
    ),
    PreferencesSection.audio => AudioSettingsSection(session: widget.session),
    PreferencesSection.language => LanguageSettingsSection(
      session: widget.session,
    ),
    PreferencesSection.accent => AccentSettingsSection(session: widget.session),
    PreferencesSection.system => const SystemStatusSection(),
  };

  @override
  Widget build(BuildContext context) {
    const sections = PreferencesSection.values;
    return AppWindow(
      windowKey: const ValueKey<String>('preferences-dialog'),
      title: AppText.strings.prefsTitle,
      titleIcon: Icons.tune_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 720,
      height: 520,
      tabs: [
        for (final section in sections)
          AppWindowTab(
            label: _labelOf(section),
            tabKey: ValueKey<String>('preferences-section-${section.name}'),
            onSelected: () => setState(() => _section = section),
          ),
      ],
      selectedTab: sections.indexOf(_section),
      body: _bodyOf(_section),
      actions: [
        AppWindowAction(
          label: AppText.strings.commonClose,
          actionKey: const ValueKey<String>('preferences-close'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
