import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/build_stamp.dart';
import '../../native/device_description.dart';
import '../../services/feedback/feedback_forms.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// Opens [FeedbackWindow]; the chosen form opens through [open] — the
/// system browser unless a test hands its own.
Future<void> showFeedbackWindow(
  BuildContext context, {
  Future<void> Function(Uri) open = openInBrowser,
  DeviceDescription Function() describe = DeviceDescriptions.read,
}) => showDialog<void>(
  context: context,
  builder: (context) => FeedbackWindow(open: open, describe: describe),
);

/// The system browser, not a view inside the app: Google refuses its
/// sign-in in an embedded view, and the file form needs one.
Future<void> openInBrowser(Uri link) async {
  await launchUrl(link, mode: LaunchMode.externalApplication);
}

/// 🗣️I-139-Q2 (유저 2026-10-28): 「의견 보내기」 is ONE row, and this window
/// chooses between the two forms — text alone, or with screenshots and
/// videos behind Google's sign-in. Either opens with the device and the
/// build already answered ([FeedbackForm.prefilled]).
class FeedbackWindow extends StatelessWidget {
  const FeedbackWindow({super.key, required this.open, required this.describe});

  final Future<void> Function(Uri) open;
  final DeviceDescription Function() describe;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    void choose(FeedbackForm form) {
      Navigator.of(context).pop();
      unawaited(open(form.prefilled(describe(), buildStamp)));
    }

    return AppWindow(
      windowKey: const ValueKey<String>('feedback-window'),
      title: editorActionLabel(EditorActionIds.sendFeedback),
      titleIcon: Icons.feedback_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 420,
      body: const SizedBox.shrink(),
      bodyPadding: EdgeInsets.zero,
      actions: [
        AppWindowAction(
          label: strings.feedbackTextOnly,
          actionKey: const ValueKey<String>('feedback-text-only'),
          onPressed: () => choose(FeedbackForm.text),
        ),
        AppWindowAction(
          label: strings.feedbackWithFiles,
          actionKey: const ValueKey<String>('feedback-with-files'),
          onPressed: () => choose(FeedbackForm.files),
        ),
      ],
    );
  }
}
