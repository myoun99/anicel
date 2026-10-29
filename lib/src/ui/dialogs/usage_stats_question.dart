import 'package:flutter/material.dart';

import '../../services/usage_stats/usage_stats.dart';
import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';

/// The question's window and its two answers.
final usageStatsQuestionKeys = confirmDialogKeys('usage-stats-question');

/// Asks whether to send the usage statistics (I-70) — while the person has
/// never answered it, here or with the switch in Preferences ▸ System
/// ([UsageStats.unanswered]).
///
/// 🗣️유저 2026-10-29 08:1x: 「따로 묻는 작은 창」 — a window of its own,
/// asked once, 「보내지 않기」 or 「보내기」, the answer remembered on the
/// device. ↩️It was the switch at the foot of the launch notice (I-70-Q3),
/// under the what's-new, where nobody scrolls.
///
/// 🗣️유저 08:2x: 「그림같은 데이터는 수집하지 않고 … 투명하게 써줘서
/// 안심할수있게」 — so it says what is sent and what never is in the
/// switch's own words ([AppStrings.usageStatsHelp]): one description, and
/// the window and the switch cannot say two things.
///
/// ⚠️A window closed with neither — the barrier, escape — is no answer, and
/// the next launch asks again.
Future<void> askUsageStatsIfUnanswered(
  BuildContext context,
  UsageStats usageStats,
) async {
  if (!await usageStats.unanswered() || !context.mounted) {
    return;
  }
  final strings = AppText.strings;
  final send = await askConfirm(
    context,
    ConfirmQuestion(
      keys: usageStatsQuestionKeys,
      title: strings.usageStatsTitle,
      titleIcon: Icons.insights_outlined,
      message: [
        strings.usageStatsAsk,
        strings.usageStatsHelp,
        strings.usageStatsChangeLater,
      ].join('\n\n'),
    ),
    accept: ConfirmChoice(strings.usageStatsDoSend),
    decline: ConfirmChoice(strings.usageStatsDontSend),
  );
  if (send != null) {
    usageStats.setEnabled(send);
  }
}
