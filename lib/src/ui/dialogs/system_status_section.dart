import 'package:flutter/material.dart';

import '../../native/qa_native_engine.dart';
import '../../services/diagnostics/memory_black_box.dart';
import '../../services/runtime_path_report.dart';
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
  const SystemStatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = collectRuntimePathReport();
    return Column(
      key: const ValueKey<String>('system-status-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Which implementation each subsystem is running right now. '
          'Fallback paths keep the app working but usually run slower — '
          'the names are searchable if you want the details.',
          style: TextStyle(fontSize: 11, color: AppColors.textDim),
        ),
        const SizedBox(height: 10),
        // Belongs here rather than in a panel of its own: this section is
        // already "what is actually going on inside the app right now",
        // and memory is that question's other half.
        const _MemoryRow(),
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
  const _MemoryRow();

  @override
  Widget build(BuildContext context) {
    final engine = QaNativeEngine.instance;
    final footprint = engine?.processFootprintBytes;
    final available = engine?.availableMemoryBytes;
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
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(4),
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
            decoration: BoxDecoration(
              border: Border.all(color: stateColor),
              borderRadius: BorderRadius.circular(3),
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
