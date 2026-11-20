// Compiles the stamp landing's kernels: tens of seconds on a busy machine.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart';
import 'package:anicel/src/services/resample/selection_resample.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/poll_until.dart';

/// 🚨A RESAMPLE WAITS FOR NO TURN OF THE ENGINE'S THREAD HERE (card
/// a-tip-thumbnail-waits-for-the-engines-turn, 2026-11-18): its picture is
/// handed up, carried and read on a worker ([resampleOnTheEngine]) —
/// 🗣️tip-coverage-is-a-second-r1-Q1 (유저 2026-11-12: 「엔진이 열리면 기다리지
/// 않고 받아 둔다」). 🔬Before, only the read was the worker's: the tips'
/// thumbnails a launch makes stood in line here behind the band's fill —
/// 77 ms of hands-up and 15 of carriage as the first stroke went (S5_BA cut
/// 352, main PC, k1340).
void main() {
  test('🚨a resample asked while the engine\'s thread stands still leaves '
      'this isolate free — and reads as it would once the thread goes '
      'on', () async {
    final workersRanHere = debugWorkersRunHere;
    debugWorkersRunHere = false;
    addTearDown(() => debugWorkersRunHere = workersRanHere);
    // ⛔premise: the engine open and the landing's kernels compiled — as
    // the app has them ahead (`compileAppKernelsAhead`).
    await openAppGpuEngine();
    await appGpuStampLandingKernels.ready;
    const side = 4;
    final source = Uint8List.fromList([
      for (var at = 0; at < side * side; at += 1) ...[at, 2 * at, 3 * at, 255],
    ]);
    // The longest this isolate went without a turn of its own while the
    // resample was on its way — the gap its answer ends in too: a wait
    // here that ends in the answer runs on to the await below, and no tick
    // comes after it.
    var longest = Duration.zero;
    var since = Stopwatch()..start();
    void aTurn() {
      if (since.elapsed > longest) {
        longest = since.elapsed;
      }
      since = Stopwatch()..start();
    }

    final turns = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => aTurn(),
    );
    addTearDown(turns.cancel);
    appGpuEngine.debugStandStill(const Duration(seconds: 2));
    final asked = Stopwatch()..start();

    final carried = await patiently(
      resampleOnTheEngine(
        src: source,
        srcWidth: side,
        srcHeight: side,
        dstWidth: side,
        dstHeight: side,
        transform: ResampleTransform.identity(),
        mode: ResampleMode.blend,
      ),
    );
    aTurn();
    turns.cancel();

    expect(
      asked.elapsed,
      greaterThan(const Duration(seconds: 1)),
      reason: '⛔premise: the carriage waited for the thread that stood still',
    );
    expect(
      longest,
      lessThan(const Duration(seconds: 1)),
      reason: 'a wait for the engine\'s thread here',
    );
    expect(carried, source, reason: 'LIVENESS: carried as it lies');
  });
}
