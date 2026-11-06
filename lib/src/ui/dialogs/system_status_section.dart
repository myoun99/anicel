import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../diagnostics/memory_census.dart';
import '../editor_session_manager.dart';
import '../../models/app_gpu_settings.dart';
import '../../services/diagnostics/memory_black_box.dart';
import '../../services/runtime_path_report.dart';
import '../session/editor_app_settings.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_rows.dart';
import 'usage_stats_switch_row.dart';

/// Preferences ▸ System: the live runtime-path report — which
/// implementation each switchable subsystem is ACTUALLY running (native
/// engine vs Dart fallback, OS codecs vs ffmpeg, Wintab vs plain
/// pointer events).
///
/// User rule (07-22): every runtime-selected path that changes behavior
/// on a real device is listed here, with searchable technology names, so
/// both the developer and end users can see the silent choices and look
/// them up. Fallback rows tint amber — a packaging problem becomes a
/// visible state instead of a mystery slowdown.
///
/// Above the report, the usage statistics' switch (I-70-Q3: on or off any
/// time in 환경설정): what the app tells about itself, beside what it is
/// running — the tab that already answers 「what is going on inside the
/// app」, rather than a tab of its own for one row. And the GPU choice
/// ([GpuPreferenceRow] — 유저 「설정의 시스템같은데서」, board
/// `gpu-choice-in-preferences`): which GPU the app runs on is this tab's
/// question too.
class SystemStatusSection extends StatelessWidget {
  const SystemStatusSection({
    super.key,
    required this.openSessions,
    required this.appSettings,
  });

  /// Every open project — the census adds them all up (I-7).
  final Iterable<EditorSessionManager> openSessions;

  /// What the usage statistics' switch ([UsageStatsSwitchRow]) and the GPU
  /// choice ([GpuPreferenceRow]) set.
  final EditorAppSettings appSettings;

  @override
  Widget build(BuildContext context) {
    final entries = collectRuntimePathReport();
    return Column(
      key: const ValueKey<String>('system-status-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        UsageStatsSwitchRow(usageStats: appSettings.usageStats),
        GpuPreferenceRow(appSettings: appSettings),
        const SizedBox(height: 10),
        Text(
          AppText.strings.systemStatusHelp,
          style: TextStyle(fontSize: 11, color: AppColors.textDim),
        ),
        const SizedBox(height: 10),
        // ⚠️REVERSED, and the original reason is kept because it was not
        // wrong. It said: "Belongs here rather than in a panel of its own:
        // this section is already 'what is actually going on inside the
        // app right now', and memory is that question's other half."
        //
        // 유저 2026-08-28 asked for a Memory TAB, and for a reason that
        // outranks the tidiness argument: this line is for a developer
        // reading a diagnostics report, and the ask was for an END USER to
        // see what the app is holding — with a live bar and a per-item
        // breakdown, which is more than a row.
        //
        // ⛔The line STAYS, because "which subsystem is running and what is
        // it costing" is still one question. It just reads the same census
        // the tab does now, so the two can never disagree.
        _MemoryRow(openSessions: openSessions),
        const SizedBox(height: 10),
        for (final entry in entries) ...[
          _EntryRow(entry: entry),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// The GPU choice's row ([AppGpuSettings]) — on every platform, in the same
/// place; where the platform's Flutter takes no choice
/// ([AppGpu.choosableHere]) it stands dimmed and its tooltip says why
/// (gpu-choice-in-preferences-Q1, 유저 2026-11-06: 「맥 · 리눅스에도 줄은
/// 두되 흐리게(고를 수 없음)」 · 「호버 툴팁으로 이유 표시」). A tablet's
/// one GPU stands under the same law.
///
/// The engine takes the choice when it is made, before Dart runs, so a pick
/// this run did not start with ([AppGpu.startedWith]) says so in a WARNING
/// under the row (the card: 「재시작 필요는 경고로만」). Its line is kept while
/// there is nothing to warn of, so the report under it does not jump.
class GpuPreferenceRow extends StatelessWidget {
  const GpuPreferenceRow({super.key, required this.appSettings});

  final EditorAppSettings appSettings;

  static const pickerKey = 'settings-gpu-preference';
  static const nextLaunchKey = ValueKey<String>('settings-gpu-next-launch');

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppGpuSettings>(
        valueListenable: AppGpu.settings,
        builder: (context, settings, _) {
          final strings = AppText.strings;
          final started = AppGpu.startedWith;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              settingsEnumPickerRow(
                keyValue: pickerKey,
                label: strings.gpuPreferenceLabel,
                help: _helpHere(),
                value: settings.preference,
                values: AppGpuPreference.values,
                labelOf: _labelOf,
                onPicked: AppGpu.choosableHere ? _pick : null,
              ),
              Text(
                started != null && settings.preference != started
                    ? strings.gpuPreferenceNextLaunch
                    : '',
                key: nextLaunchKey,
                style: TextStyle(fontSize: 11, color: AppColors.danger),
              ),
            ],
          );
        },
      );

  void _pick(AppGpuPreference preference) =>
      appSettings.setGpuSettings(AppGpuSettings(preference: preference));

  /// What the row's tooltip says here: what the choice is where it can be
  /// made, and why it cannot where it cannot.
  static String _helpHere() {
    final strings = AppText.strings;
    if (AppGpu.choosableHere) return strings.gpuPreferenceHelp;
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => strings.gpuPreferenceNotOnMacOS,
      TargetPlatform.linux => strings.gpuPreferenceDriverPicks,
      _ => strings.gpuPreferenceOneGpu,
    };
  }

  static String _labelOf(AppGpuPreference preference) => switch (preference) {
    AppGpuPreference.auto => AppText.strings.gpuPreferenceAuto,
    AppGpuPreference.lowPower => AppText.strings.gpuPreferenceLowPower,
    AppGpuPreference.highPerformance =>
      AppText.strings.gpuPreferenceHighPerformance,
  };
}

/// What the app is holding, what the OS will still give it, and whether
/// the last run ended in the middle of something.
///
/// 🚨The third line is the point. A memory kill leaves no exception, no
/// crash report and nothing in App Store Connect — so an interrupted
/// entry from the previous launch is the ONLY place it can be read
/// (실기 08-27, iPhone: three kills, an iPad that survived the same file,
/// and no evidence anywhere).
///
/// The numbers refuse to guess. Where the platform does not answer they
/// say so rather than substituting the device's RAM, which is a
/// different question and the one that has been standing in for this.
class _MemoryRow extends StatelessWidget {
  const _MemoryRow({required this.openSessions});

  final Iterable<EditorSessionManager> openSessions;

  @override
  Widget build(BuildContext context) {
    // 🚨ONE CENSUS, shared with Preferences ▸ Memory. What it hands back is
    // the platform's own PRIVATE footprint — the same number that OS's task
    // manager shows next to the app — with RSS standing in only where no
    // native engine loaded at all.
    // ⛔This row once asked the engine directly and printed "not measured
    // here" on Windows and Linux, because ABI v29 answered only on Apple.
    // The engine answers everywhere now (2026-09-10) and the census stays
    // the ONE place that decides which number this is.
    final census = collectMemoryCensus(openSessions);
    final footprint = census.footprintBytes;
    final available = census.availableBytes;
    final interrupted = MemoryBlackBox.lastUnfinished;
    return Column(
      key: const ValueKey<String>('system-status-memory'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Memory  ${_mb(footprint)} in use · ${_mb(available)} still '
          'available to this app',
          style: TextStyle(fontSize: 12, color: AppColors.text),
        ),
        if (interrupted != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last run stopped during: $interrupted',
            key: const ValueKey<String>('system-status-memory-interrupted'),
            style: TextStyle(fontSize: 11, color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  static String _mb(int? bytes) => bytes == null
      ? 'not measured here'
      : '${(bytes / (1024 * 1024)).round()}MB';
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final RuntimePathEntry entry;

  @override
  Widget build(BuildContext context) {
    // Selection grammar: state reads through COLOR only (no check
    // marks) — primary = accent, fallback = amber.
    final stateColor = entry.isPrimary
        ? AppColors.accent
        : const Color(0xFFE0A030);
    return Container(
      key: ValueKey<String>('system-status-${entry.subsystem}'),
      padding: const EdgeInsets.all(8),
      decoration: ShapeDecoration(
        shape: AppShapes.container(
          AppShapes.wellRadius,
          side: BorderSide(color: AppColors.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.subsystem,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          // The active-path chip sits on its own line — the names are
          // long on purpose (searchable), so they wrap instead of clip.
          DecoratedBox(
            decoration: ShapeDecoration(
              shape: AppShapes.container(
                3,
                side: BorderSide(color: stateColor),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                entry.active,
                style: TextStyle(fontSize: 11, color: stateColor),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.detail,
            style: TextStyle(fontSize: 10.5, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}
