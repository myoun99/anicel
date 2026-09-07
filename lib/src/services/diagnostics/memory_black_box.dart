import 'dart:io';


import '../../native/qa_native_engine.dart';
import '../persistence/app_support_path.dart';

/// What the app was holding when it died.
///
/// 🚨A memory kill leaves NO TRACE, and that is the whole reason this
/// exists. iOS terminates an app that exceeds its allowance without an
/// exception, without a crash report, and without anything in App Store
/// Connect — memory terminations are not "crashes" and are never
/// collected there. On 2026-08-27 a save on an iPhone killed the app
/// three times over, the same file and the same press survived on an
/// iPad, and after all of it there was not one line of evidence anywhere
/// on the device or the server. The only instrument that survives a
/// silent kill is one that writes BEFORE the kill.
///
/// So this leaves a breadcrumb around the work most likely to be the
/// last thing the app ever does, flushed to disk as it goes. At the next
/// launch an unclosed entry says two things a crash report would have:
/// that the app died in the middle of that work, and how big it had
/// grown when it did.
///
/// ⚠️It measures rather than guesses. [QaNativeEngine.processFootprintBytes]
/// is the number a jetsam report calls `rpages × pageSize`, and
/// [QaNativeEngine.availableMemoryBytes] on iOS is what the OS will still
/// hand out — neither is the device's RAM, which is what the cel budget
/// has been scaled from and is why that budget may be twice what the
/// process is allowed.
abstract final class MemoryBlackBox {
  /// Where the log lives: the app's own container, because a file the user
  /// has to go and find is a file nobody reads. Kept out of the project so
  /// it survives moving or deleting it.
  ///
  /// ⛔**A LOOSE FILE AT THE CONTAINER ROOT, AND THAT IS THE HONEST
  /// ADDRESS.** The rooms beside it are named for LIFETIMES — `Settings/`
  /// lives for ever, `Sessions/<run>/` for one run — and this is neither:
  /// it is written by one run and read by the NEXT one, exactly once,
  /// before [reset] turns the page. It borrowed `Recovery/` until the
  /// snapshots that named that folder were deleted; one file does not earn
  /// a room of its own, so it says its own name instead.
  ///
  /// ⚠️Test-redirected like every other container path: a test run must
  /// not append to — or reset — the developer's own log.
  static String logPath() =>
      testRedirectedAppSupportPath('memory-log.txt', sandbox: 'diagnostics');

  /// Test seam for the platform numbers. ⚠️Reset in
  /// `test/flutter_test_config.dart`.
  static ({int? footprint, int? available}) Function()? debugReading;

  static ({int? footprint, int? available}) _read() {
    final override = debugReading;
    if (override != null) {
      return override();
    }
    final engine = QaNativeEngine.instance;
    return (
      footprint: engine?.processFootprintBytes,
      available: engine?.availableMemoryBytes,
    );
  }

  /// Notes that [what] is starting, and how much room there was.
  ///
  /// Synchronous and flushed on purpose: an async write that is still
  /// queued when the process is killed records nothing, which is the one
  /// outcome this must not have.
  static void begin(String what) => _append('BEGIN $what');

  /// Notes that [what] finished. An entry with no END is the signature of
  /// a kill — nothing else in the app leaves one.
  static void end(String what) => _append('END   $what');

  static void _append(String line) {
    final reading = _read();
    final stamp = DateTime.now().toUtc().toIso8601String();
    final footprint = _mb(reading.footprint);
    final available = _mb(reading.available);
    try {
      final file = File(logPath());
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '$stamp $line footprint=$footprint available=$available\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // A diagnostic that can fail a save is worse than no diagnostic.
    }
  }

  static String _mb(int? bytes) =>
      bytes == null ? '?' : '${(bytes / (1024 * 1024)).round()}MB';

  /// What the PREVIOUS launch was doing when it stopped, read once at
  /// startup and held for whoever shows it. Null on a clean start.
  static String? lastUnfinished;

  /// The last entry that never got its END, or null when the log is clean
  /// — read at launch, which is the only moment anybody can be told.
  static String? unfinishedEntry() {
    try {
      final file = File(logPath());
      if (!file.existsSync()) {
        return null;
      }
      final lines = file.readAsLinesSync().where((l) => l.isNotEmpty).toList();
      // Walk backwards: the last BEGIN with no END after it is the work
      // that was interrupted. Anything older has already been answered.
      for (var i = lines.length - 1; i >= 0; i -= 1) {
        if (lines[i].contains(' END   ')) {
          return null;
        }
        if (lines[i].contains(' BEGIN ')) {
          return lines[i];
        }
      }
    } on Object {
      // Unreadable: the same as having nothing to report.
    }
    return null;
  }

  /// Starts a fresh page, so a launch's log is about THIS launch.
  ///
  /// Called at startup, AFTER [unfinishedEntry] has been read — the
  /// previous page has said what it had to say by then, and keeping it
  /// would make every later launch re-report a kill that was already
  /// reported once.
  static void reset() {
    try {
      final file = File(logPath());
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on Object {
      // Nothing to clear, or a file we may not touch.
    }
  }
}
