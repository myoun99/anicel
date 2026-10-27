import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../widgets/app_window.dart';
import '../widgets/content_scrollbar.dart';
import 'audio_settings_section.dart';
import 'autosave_settings_section.dart';
import 'display_settings_section.dart';
import 'input_settings_dialog.dart' show InputSettingsSection;
import 'language_settings_dialog.dart' show LanguageSettingsSection;
import 'memory_settings_section.dart';
import 'system_status_section.dart';
import '../text/app_strings.dart';

/// SAVE-1: the unified Preferences dialog — Input, Autosave, Audio,
/// Language, Display and System (the runtime-path report)
/// as sections of ONE window (the old per-domain Edit menu entries
/// collapsed here; their dialogs remain as thin wrappers around the same
/// section widgets for tests and deep links).
///
/// Display is R11's: the interface scale — and the accent colour, a row of
/// it since F-480 (유저 2026-10-26: 「강조색상 탭, 이게 화면이랑 같이
/// 안있고 독립적으로 있는게 의문임. 화면탭에 넣도록」). ↩️Accent Colors was
/// a tab of its own, and Display a section beside it rather than a row
/// under it, since a scale filed under colour would be a setting nobody
/// could find.
enum PreferencesSection {
  input,
  autosave,
  audio,
  language,
  display,
  system,
  memory,
}

/// [openSessions] is every open project, the one on screen among them —
/// what the memory readouts add up (I-7).
Future<void> showPreferencesDialog(
  BuildContext context, {
  required EditorSessionManager session,
  required Iterable<EditorSessionManager> openSessions,
  PreferencesSection initialSection = PreferencesSection.input,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PreferencesDialog(
      session: session,
      openSessions: openSessions,
      initialSection: initialSection,
    ),
  );
}

class _PreferencesDialog extends StatefulWidget {
  const _PreferencesDialog({
    required this.session,
    required this.openSessions,
    required this.initialSection,
  });

  final EditorSessionManager session;
  final Iterable<EditorSessionManager> openSessions;
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
      PreferencesSection.display => strings.prefsDisplay,
      PreferencesSection.system => strings.prefsSystem,
      PreferencesSection.memory => strings.prefsMemory,
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
    PreferencesSection.display => DisplaySettingsSection(
      session: widget.session,
    ),
    PreferencesSection.system => SystemStatusSection(
      openSessions: widget.openSessions,
    ),
    PreferencesSection.memory => MemorySettingsSection(
      session: widget.session,
      openSessions: widget.openSessions,
    ),
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
      // 🗣️F-440 (유저 2026-10-23): 「환경설정창의 스크롤바, 스크롤바랑
      // 내용물이랑 위젯 겹치는데 공간 제대로 나누도록. 그러고 스크롤바 없는
      // 환경설정창도 항상 존재하도록 법 통일」 — the content's own lane, H35's
      // law ([ContentScrollbar]): reserved beside the content and there
      // whether the section overflows or not. ↩️The window scrolled its body
      // under the app root's bar, laid OVER the content and only while it
      // overflowed — and that bar was the thick one from F-409 (10-20) to
      // F-440, which now gives every bar but the floor's the thin one.
      scrollBody: false,
      bodyPadding: EdgeInsets.zero,
      body: ContentScrollbar(
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          primary: false,
          padding: AppWindow.defaultBodyPadding,
          child: _bodyOf(_section),
        ),
      ),
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
