import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../core/build_stamp.dart';
import '../../services/launch_notice.dart';
import '../../services/usage_stats/usage_stats.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/content_scrollbar.dart';
import '../widgets/markdown_subset.dart';
import 'feedback_window.dart' show showFeedbackWindow;
import 'usage_stats_switch_row.dart';

/// Opens this build's launch notice — unless it was dismissed already
/// ([LaunchNotice.due]).
///
/// 🗣️유저 2026-10-28: 「앱 실행시 앱 설명 넣고싶어. 다음부터 표시안함버튼
/// 있고. 빌드당 한번기억」.
Future<void> showLaunchNoticeIfDue(
  BuildContext context,
  LaunchNotice notice, {
  required UsageStats usageStats,
}) async {
  final content = await notice.due();
  if (content == null || !context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => LaunchNoticeWindow(
      content: content,
      usageStats: usageStats,
      onDontShowAgain: () => unawaited(notice.dismiss(content)),
    ),
  );
}

/// The launch notice: the pre-release notice, what changed in this build
/// and where feedback goes, in the program language — each section the
/// bundled file's words ([LaunchNoticeSection]).
///
/// The feedback section's button is the ⚙ menu's 「의견 보내기」 row: its
/// window and its name (I-139), one action wherever it is pressed.
///
/// Under them, the usage statistics' switch: 🗣️I-70-Q3 (유저 2026-10-29)
/// 「안내 창에서 묻고 기본 꺼짐」 — Preferences ▸ System's row, the same one.
class LaunchNoticeWindow extends StatelessWidget {
  const LaunchNoticeWindow({
    super.key,
    required this.content,
    required this.usageStats,
    required this.onDontShowAgain,
  });

  final LaunchNoticeContent content;

  /// What the consent row turns on or off ([UsageStatsSwitchRow]).
  final UsageStats usageStats;

  /// 「다음부터 표시 안 함」 — the window closes either way.
  final VoidCallback onDontShowAgain;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    void close() => Navigator.of(context).pop();
    return AppWindow(
      windowKey: const ValueKey<String>('launch-notice'),
      // 🗣️app-version-shown (유저 2026-10-29): 「안내 창 제목 옆」 — the
      // build beside the title, as the release stamped it (`dev` where
      // nobody did). The stamp alone: the version NAME (pubspec's) is not
      // something the app can read without a package for it.
      title: '${strings.launchNoticeTitle} · $buildStamp',
      titleIcon: Icons.info_outline,
      onClose: close,
      width: 560,
      // The content's own lane, as Preferences scrolls (F-440).
      scrollBody: false,
      bodyPadding: EdgeInsets.zero,
      body: ContentScrollbar(
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          primary: false,
          padding: AppWindow.defaultBodyPadding,
          child: _sections(context),
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.launchNoticeDontShowAgain,
          actionKey: const ValueKey<String>('launch-notice-dont-show-again'),
          onPressed: () {
            onDontShowAgain();
            close();
          },
        ),
        AppWindowAction(
          label: strings.commonClose,
          actionKey: const ValueKey<String>('launch-notice-close'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: close,
        ),
      ],
    );
  }

  /// What the window says: its sections one under another, the feedback
  /// section's button under that section's words, and the usage
  /// statistics' switch last.
  Widget _sections(BuildContext context) {
    Widget section(LaunchNoticeSection section) =>
        MarkdownSubset(content.textOf(AppText.language, section));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section(LaunchNoticeSection.notice),
        const Divider(height: 24),
        section(LaunchNoticeSection.whatsNew),
        const Divider(height: 24),
        section(LaunchNoticeSection.feedback),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: AppWindowActionButton(
            AppWindowAction(
              label: editorActionLabel(EditorActionIds.sendFeedback),
              actionKey: const ValueKey<String>('launch-notice-send-feedback'),
              onPressed: () => showFeedbackWindow(context),
            ),
          ),
        ),
        const Divider(height: 24),
        UsageStatsSwitchRow(usageStats: usageStats),
      ],
    );
  }
}
