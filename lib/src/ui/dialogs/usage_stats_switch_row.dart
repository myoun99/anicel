import 'package:flutter/material.dart';

import '../../services/usage_stats/usage_stats.dart';
import '../text/app_strings.dart';
import '../widgets/settings_rows.dart';

/// The usage statistics' one switch (I-70), wherever it stands.
///
/// 🗣️I-70-Q3 (유저 2026-10-29): 「안내 창에서 묻고 기본 꺼짐」, and on or off
/// any time in 환경설정 — so the launch notice asks with this row and
/// Preferences ▸ System keeps it: ONE widget on ONE [UsageStats.enabled],
/// and the two places cannot say different things.
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
