import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../ui_scale.dart';
import '../widgets/app_window.dart';
import 'accent_settings_dialog.dart';
import 'display_settings_section.dart';
import 'language_settings_dialog.dart';

/// Opens the first launch's settings window, and keeps the scale it was
/// closed on.
///
/// 🗣️유저 2026-10-29 (I-144): 「초기실행시 게임처럼 ui배율 강조색 커서
/// 골라서 정할수있게」 — and (Q3) 「그런 앱설정을 한 창에서 한번에
/// 보여주고(나중에 바꿀수있다고 알림) 그다음 사용통계창」, because
/// 「처음에 뜨는창을 최대한 줄이고 간략화하고싶어서」. Then: 「첫설정창에
/// 프로그램언어 표기언어도 넣자」 — the languages first, so the rest is
/// read in the one picked. And (I-146): 「추가로 화면모드 다크/라이트
/// 고를수있게」 — the palette's row too, above the accent as in
/// Preferences. ↩️I-143-Q8 had answered 「안 넣는다」 an hour and a half
/// before.
///
/// The scale is written however the window closes: the one it shows on a
/// first launch is the device's default ([AppUiScale.firstRunScaleFor]),
/// and a person who saw it and went on has chosen it. The accent and the
/// cursor are written as they are picked, like everywhere else.
Future<void> showFirstRunSettings(
  BuildContext context,
  EditorSessionManager session,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) => FirstRunSettingsWindow(session: session),
  );
  session.setUiScale(AppUiScale.value.value);
}

/// The settings a person picks before anything else — the very rows of
/// Preferences ▸ Language and ▸ Display, and a line on where they change
/// later.
class FirstRunSettingsWindow extends StatelessWidget {
  const FirstRunSettingsWindow({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    void close() => Navigator.of(context).pop();
    return AppWindow(
      windowKey: const ValueKey<String>('first-run-settings'),
      title: strings.firstRunTitle,
      titleIcon: Icons.tune,
      onClose: close,
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LanguageSettingsSection(session: session),
          UiScaleRow(session: session),
          ColorModeRow(session: session),
          AccentSettingsRow(session: session),
          DrawingCursorRow(session: session),
          const SizedBox(height: 12),
          // 🗣️유저 (I-144-Q3): 「나중에 바꿀수있다고 알림」 — the one line
          // this window says, asked for by name.
          Text(
            strings.firstRunChangeLater,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        AppWindowAction(
          label: strings.firstRunStart,
          actionKey: const ValueKey<String>('first-run-settings-start'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: close,
        ),
      ],
    );
  }
}
