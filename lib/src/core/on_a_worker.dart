import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// [job] run on a worker isolate ([Isolate.run]) — or, while
/// [debugWorkersRunHere], on this one: the same job either way, answered
/// through a future either way, so the ORDER a caller sees is the same.
Future<T> onAWorker<T>(FutureOr<T> Function() job) =>
    debugWorkersRunHere ? Future<T>.sync(job) : Isolate.run(job);

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
