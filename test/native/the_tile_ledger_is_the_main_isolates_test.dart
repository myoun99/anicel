import 'dart:isolate';

import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// A worker that opened the app's ledger would open an engine of its own
/// and read tiles there — stored over from the CPU's bytes today, nothing
/// at all once the engine's are the only ones (저장's review of the flip
/// lane, 11-09).
void main() {
  test('a worker that asks for the app\'s ledger is refused by name', () async {
    final answer = await Isolate.run(() {
      try {
        EngineTileLedger.instance;
        return 'opened';
      } on TileLedgerAskedOnAWorker {
        return 'refused';
      }
    });

    expect(answer, 'refused');
  });

  test('the main isolate is handed it', () {
    expect(EngineTileLedger.instance, isA<EngineTileLedger>());
  });
}
