import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../core/build_stamp.dart';
import '../../services/launch_notice.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/content_scrollbar.dart';
import '../widgets/markdown_subset.dart';
import '../widgets/settings_rows.dart' show SettingsSectionHeading;
import 'app_confirm_dialog.dart' show Fold;
import 'feedback_window.dart' show showFeedbackWindow;

/// Opens this build's launch notice — unless it was dismissed already
/// ([LaunchNotice.due]).
///
/// 🗣️유저 2026-10-28: 「앱 실행시 앱 설명 넣고싶어. 다음부터 표시안함버튼
/// 있고. 빌드당 한번기억」.
Future<void> showLaunchNoticeIfDue(
  BuildContext context,
  LaunchNotice notice,
) async {
  final content = await notice.due();
  if (content == null || !context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => LaunchNoticeWindow(
      content: content,
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
/// ↩️The usage statistics' switch stood under them (I-70-Q3: 「안내 창에서
/// 묻고 기본 꺼짐」), below the what's-new where nobody scrolls; 유저
/// 2026-10-29 08:1x moved the asking to a window of its own
/// (`askUsageStatsIfUnanswered`) — opened before this one since 19:5x
/// (I-144: 「안내창이 텍스트가 많아서 지치니까」).
class LaunchNoticeWindow extends StatelessWidget {
  const LaunchNoticeWindow({
    super.key,
    required this.content,
    required this.onDontShowAgain,
  });

  final LaunchNoticeContent content;

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

  /// What the window says: its sections one under another, and the
  /// feedback section's button under that section's words.
  ///
  /// 🗣️유저 2026-10-29 (I-144): 「첫 실행창 업데이트내역항목 접어두고
  /// 아래의 의견보내기항목을 그 위로 올리자」 — the feedback before the
  /// what's-new, and the what's-new folded under its own heading. ↩️The
  /// what's-new stood open between the notice and the feedback.
  Widget _sections(BuildContext context) {
    String text(LaunchNoticeSection section) =>
        content.textOf(AppText.language, section);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarkdownSubset(text(LaunchNoticeSection.notice)),
        const Divider(height: 24),
        MarkdownSubset(text(LaunchNoticeSection.feedback)),
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
        _whatsNew(text(LaunchNoticeSection.whatsNew)),
      ],
    );
  }

  /// The what's-new, folded under its file's own `## ` heading. A file that
  /// opens with no heading has nothing to fold under, and stands open.
  static Widget _whatsNew(String source) {
    final heading = MarkdownSubset.leadingHeadingOf(source);
    if (heading == null) {
      return MarkdownSubset(source);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Fold(
        toggleKey: const ValueKey<String>('launch-notice-whats-new'),
        startsOpen: false,
        heading: Flexible(child: SettingsSectionHeading(label: heading)),
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: MarkdownSubset(source, leadingHeading: false),
        ),
      ),
    );
  }
}
