import 'dart:async';

import 'package:anicel/src/services/persistence/thaw_in_worker.dart';

/// [body] run while every worker's turn is taken ([celThawTurns]) — as by a
/// frame's other rows: no thaw can start — and the turns given back after
/// it, whatever it did.
Future<void> whileNoWorkerIsFree(Future<void> Function() body) async {
  final held = Completer<void>();
  final holding = [
    for (var i = 0; i < celThawTurns.atOnce; i += 1)
      celThawTurns.run(() => held.future),
  ];
  try {
    await body();
  } finally {
    held.complete();
    await Future.wait(holding);
  }
}
