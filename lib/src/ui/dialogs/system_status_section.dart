import 'package:flutter/material.dart';

import '../diagnostics/memory_census.dart';
import '../editor_session_manager.dart';
import '../../services/diagnostics/memory_black_box.dart';
import '../../services/runtime_path_report.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';

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
class SystemStatusSection extends StatelessWidget {
  const SystemStatusSection({super.key, required this.openSessions});

  /// Every open project — the census adds them all up (I-7).
  final Iterable<EditorSessionManager> openSessions;

  @override
  Widget build(BuildContext context) {
    final entries = collectRuntimePathReport();
    return Column(
      key: const ValueKey<String>('system-status-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppText.strings.systemStatusHelp,
          style: const TextStyle(fontSize: 11, color: AppColors.textDim),
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
          style: const TextStyle(fontSize: 12, color: AppColors.text),
        ),
        if (interrupted != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last run stopped during: $interrupted',
            key: const ValueKey<String>('system-status-memory-interrupted'),
            style: const TextStyle(fontSize: 11, color: AppColors.danger),
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
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.subsystem,
            style: const TextStyle(
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
            style: const TextStyle(fontSize: 10.5, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}
