import 'package:flutter/material.dart';

import '../../services/usage_stats/usage_stats.dart';
import '../text/app_strings.dart';
import '../widgets/settings_rows.dart';

/// The usage statistics' one switch (I-70), in Preferences ▸ System.
///
/// 🗣️I-70-Q3 (유저 2026-10-29): on or off any time in 환경설정 — on the
/// [UsageStats.enabled] the question at launch answers
/// (`askUsageStatsIfUnanswered`), and pressing it is an answer too: the
/// question is not asked after it. ↩️The launch notice asked with this row
/// until 유저 08:1x chose 「따로 묻는 작은 창」.
///
/// What it sends is its tooltip — no caption under the control (F-2).
class UsageStatsSwitchRow extends StatelessWidget {
  const UsageStatsSwitchRow({super.key, required this.usageStats});

  final UsageStats usageStats;

  static const tileKey = ValueKey<String>('settings-usage-stats');

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: usageStats.enabled,
    builder: (context, on, _) => SettingsSwitchRow(
      tileKey: tileKey,
      label: AppText.strings.usageStatsSend,
      help: AppText.strings.usageStatsHelp,
      value: on,
      onChanged: usageStats.setEnabled,
    ),
  );
}
