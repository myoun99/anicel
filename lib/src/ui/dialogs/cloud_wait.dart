import 'package:flutter/foundation.dart';

import '../../services/persistence/folder_grant.dart' show FileArrival;
import '../text/cloud_wait_line.dart';

/// What a door says while a file it did not write is on its way.
///
/// One object for what a wait needs — a line that changes, a stop that is
/// live only while there is something to stop, and the question 「were we
/// stopped?」 — so the open door and the import window say the same thing
/// with the same words rather than each inventing its own.
///
/// The line NAMES THE CLOUD (유저 2026-08-27: 「프로바이더가 로컬로
/// 다운로드하는 걸 기다리고 있다고 명확히 표기하는 게 좋겠다」). 「여는 중」
/// across a download makes the app look slow for work the provider is
/// doing, and the person waiting cannot tell the two apart without being
/// told which one it is.
///
/// ↩️It was the open door's own (`_CloudWait`), and the import window kept
/// the same three things as fields and a status line of its own — until the
/// import ran behind the app's wait window too (F-282-Q1, 2026-10-08), where
/// the open door's wait already stood.
class CloudWait {
  /// The line the wait reads as — empty while nothing is being waited for.
  final ValueNotifier<String> status = ValueNotifier<String>('');

  /// Whether a file is being waited for right now — from [begin] or the
  /// first [report] to [ended]: the stretch of a run that can honestly be
  /// stopped (`AppProgressDialog.cancelLive`).
  final ValueNotifier<bool> waiting = ValueNotifier<bool>(false);

  bool _cancelled = false;

  /// The provider's word on the file: how long it has been waited for, and
  /// how much of it is here.
  void report(Duration waited, FileArrival arrival) {
    // The sentence is [cloudWaitLine]'s, for every door (F-141).
    status.value = cloudWaitLine(waited, arrival);
    waiting.value = true;
  }

  /// The wait is over — the bytes came, or the wait was stopped: the line
  /// has nothing left to say, and there is nothing to wait out.
  ///
  /// ⚠️A stop said as the bytes landed still stands: the open door's read
  /// asks [isCancelled] after the wait, and a person who pressed it meant
  /// it.
  void ended() {
    status.value = '';
    waiting.value = false;
  }

  /// A file's wait begins — before the provider has said anything, so the
  /// stop is live from the first moment (the import's own reading: it waits
  /// on a file per placement). A stop said to the wait before was for that
  /// one.
  void begin() {
    _cancelled = false;
    waiting.value = true;
  }

  void cancel() => _cancelled = true;

  bool isCancelled() => _cancelled;

  void dispose() {
    status.dispose();
    waiting.dispose();
  }
}
