import 'dart:io';

import '../../core/build_stamp.dart';
import '../persistence/app_support_path.dart';

/// What the app was doing when a graphics device went — written the moment
/// the app hears it, and kept across runs.
///
/// 🗣️H63 (관제 2026-11-18, the user's release app frozen on its last
/// picture twice while the conte played — NVIDIA, nvlddmkm 153): one forced
/// run of the same file on a copy did not reset the device, so the next real
/// reset is to leave its own evidence. The user goes on working as before;
/// when it happens again, this file says which device's work stopped, what
/// was playing where, and on what canvas.
///
/// ⛔NOT `MemoryBlackBox`'s page, which the next launch reads once and
/// deletes: the loss's own question ends in 「save and start again」, and
/// that next launch would wipe it. This file is never reset — it keeps the
/// newest [kept] losses — and sits beside that one, a loose file at the
/// container root, for the same reason that one does.
abstract final class GpuLossLog {
  /// How many losses the file keeps, the newest last.
  static const int kept = 20;

  /// The line each loss starts with — what [write] counts losses by.
  static const String opening = '=== ';

  /// Where the log lives — test-redirected like every container path.
  static String logPath() =>
      testRedirectedAppSupportPath('gpu-loss-log.txt', sandbox: 'diagnostics');

  /// Writes one loss: [title] after its time, the build, then [lines] —
  /// and lets the oldest go past [kept].
  ///
  /// Synchronous and flushed: a process that a lost device takes down next
  /// must not take a queued write with it.
  static void write(String title, List<String> lines) {
    final stamp = DateTime.now();
    final block = [
      '$opening${stamp.toIso8601String()} '
          '(${stamp.toUtc().toIso8601String()}) $title',
      'build $buildStamp',
      ...lines,
    ];
    try {
      final file = File(logPath());
      file.parent.createSync(recursive: true);
      final before = file.existsSync()
          ? file.readAsLinesSync()
          : const <String>[];
      final kept = _newest(before, GpuLossLog.kept - 1);
      file.writeAsStringSync(
        '${[...kept, ...block].join('\n')}\n',
        flush: true,
      );
    } on Object {
      // A diagnostic that can fail the save after it is worse than none.
    }
  }

  /// [lines] from the start of their newest [losses] losses.
  static List<String> _newest(List<String> lines, int losses) {
    if (losses <= 0) {
      return const [];
    }
    var seen = 0;
    for (var index = lines.length - 1; index >= 0; index -= 1) {
      if (lines[index].startsWith(opening)) {
        seen += 1;
        if (seen == losses) {
          return lines.sublist(index);
        }
      }
    }
    return lines;
  }
}
