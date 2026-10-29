import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// [job] run on a worker isolate ([Isolate.run]) — or, while
/// [debugWorkersRunHere], on this one: the same job either way, answered
/// through a future either way, so the ORDER a caller sees is the same.
Future<T> onAWorker<T>(FutureOr<T> Function() job) =>
    debugWorkersRunHere ? Future<T>.sync(job) : Isolate.run(job);

/// [job] on a worker ([onAWorker]), handed a `report` that tells
/// [onProgress] — on THIS isolate — how far it is, as 0–1.
///
/// 🗣️F-494 (유저 2026-10-28: 「하고있는 과정을 투명하게 … 퍼센테이지에
/// 반영하면서」): a worker's job hands back one value at its end and nothing
/// before, so a long one stood behind the wait window at 0% — a trimmed
/// movie's piece re-encoding (61 s of a 3.4GB file's two minutes), a
/// carried file's copy (56 s for that file whole). The closure crosses with
/// a [SendPort] in it, which is sendable, and the job reports into it.
///
/// A message that lands after the answer is not heard — the port closes
/// with the answer, and the bar's next word is the caller's.
///
/// ⚠️The save's `_reportingProgress` talks the same way, with a second
/// kind of message beside the fraction, and its `_SaveProgress` holds the
/// bar back as [_whenTheBarMoves] does; two, so not yet one (3의 규칙).
Future<T> onAWorkerReporting<T>(
  void Function(double fraction)? onProgress,
  FutureOr<T> Function(void Function(double fraction) report) job,
) async {
  if (onProgress == null) {
    return onAWorker(() => job(_heardByNobody));
  }
  if (debugWorkersRunHere) {
    return Future<T>.sync(() => job(_whenTheBarMoves(onProgress)));
  }
  final heard = ReceivePort();
  heard.listen((message) {
    if (message is double) {
      onProgress(message);
    }
  });
  try {
    return await Isolate.run(_reportingInto(heard.sendPort, job));
  } finally {
    heard.close();
  }
}

/// [job] reporting into [told] — the closure that crosses, made HERE and
/// not in [onAWorkerReporting].
///
/// 🚨★★★**A CLOSURE CARRIES ITS WHOLE SCOPE, NOT ONLY WHAT IT NAMES.** The
/// variables a scope's closures capture live in one context, so a closure
/// made beside the listener carries the listener's `onProgress` too — and
/// the import window's holds the window's state, futures and all, which no
/// isolate message carries. 🐞F-494's own regression (10-30, the release's
/// import window): every file 「파일 품기」 placed failed as 「열 수
/// 없습니다 — 손상됐거나 암호로 잠겨 있습니다」 — the send refused, and the
/// window reads any throw as that. A test corpus runs the job here
/// ([debugWorkersRunHere]) and a test's listener held a list, so nothing
/// saw it. The save met the same wall once (`AnicelFileService`'s
/// `reportsProgress`).
FutureOr<T> Function() _reportingInto<T>(
  SendPort told,
  FutureOr<T> Function(void Function(double fraction) report) job,
) =>
    () => job(_whenTheBarMoves(told.send));

void _heardByNobody(double fraction) {}

/// [report], told only when the bar moves by half a percent or reaches its
/// end: a 3.4GB copy at 512KB blocks reports thirteen thousand times, to
/// move the label by less than a digit each.
///
/// ⚠️The end is told ONCE: a job's last block lands on it and the job then
/// says it again (`writeMediaBlob`), and an end heard twice is what an end
/// announced early looks like from outside.
void Function(double fraction) _whenTheBarMoves(
  void Function(double fraction) report,
) {
  var told = -1.0;
  return (fraction) {
    if (told >= 1 || (fraction - told < 0.005 && fraction < 1)) {
      return;
    }
    told = fraction;
    report(fraction);
  };
}

/// Test seam: run every [onAWorker] job HERE instead of on a worker.
///
/// 🚨★★★**A `testWidgets` CLOCK NEVER LETS A REAL ISOLATE FINISH.** The
/// widget binding runs the body in a fake-async zone, so awaiting
/// [Isolate.run] is a hang, not a wait — every voice-take and import widget
/// test stopped at 「did not complete」 the moment staging moved off the UI
/// isolate. `tester.runAsync` is the other answer and it does not fit: those
/// tests pump between the await and the assertion.
///
/// ⚠️`flutter_test_config.dart` turns it ON for the whole suite, so each
/// worker's road needs a test that turns it back OFF — without one, nothing
/// would ever run the road production takes.
///
/// ↩️ONE SWITCH (2026-10-15): staged media and a trimmed piece's cut each
/// had their own, of the same shape for the same reason, and a cel thawed
/// ahead for playback would have been the third.
@visibleForTesting
bool debugWorkersRunHere = false;
