import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';

import '../helpers/a_word_that_waits.dart';

/// 🔬WHAT A WIDGET TEST OPENED ON THE APP'S ENGINE IS HANDED TO THE TEST
/// AFTER IT (card an-engine-setup-hangs-in-a-batch, 2026-11-23): the engine
/// itself, the frames' tools and a set of kernels warmed. Each was handed
/// as the future it had been made by, and a done future answers what
/// listens to it from then on in the zone it was made in — a widget test's
/// faked clock, which nobody pumps once that test ends. The shell's test
/// opened the engine so, and every file bundled after it stood in its
/// `setUpAll(openAppGpuEngine)` for good (보드/인프라: 12 minutes a file, 3
/// of 3; `MadeOnce` has the measurement).
void main() {
  // Read where no test's clock holds them: the tools' letters are set in
  // them, and a widget test's clock lends their files no time to be read.
  readTheEnginesFacesFirst();

  // First in the file: nothing has opened the engine yet.
  testWidgets('the engine, the frames\' tools and a set of kernels, made '
      'in a widget test', (tester) async {
    expect(
      debugAppGpuEngineAskedFor,
      isFalse,
      reason: '⛔premise: made here, in this test\'s zone',
    );
    unawaited(openAppGpuEngine());
    // Open before the kernels ask for it, or they would open one of their
    // own at once (`appGpuEngine`).
    await tester.pump();
    expect(appGpuEngineOpen.value, isNotNull, reason: '⛔premise: opened');
    unawaited(appEngineFrameTools);
    unawaited(appGpuGridKernels.warm());
    await tester.pumpWidget(const SizedBox());

    expect(appEngineFrameToolsOpen, isNotNull, reason: '⛔premise: open');
    expect(appGpuGridKernels.compiled, isNotNull, reason: '⛔premise');
  });

  test('are handed to the test after it, which waits for them in real '
      'time', () async {
    for (final (what, asked) in <(String, Future<Object?> Function())>[
      ('the engine', openAppGpuEngine),
      ('the frames\' tools', () => appEngineFrameTools),
      ('the kernels', appGpuGridKernels.warm),
    ]) {
      expect(await _answered(asked()), isTrue, reason: what);
    }
  });
}

/// Whether [future] answers a listener within ten seconds — as an `await`
/// listens, by `then`, and not by `timeout`, which takes a done future by
/// a way of its own.
Future<bool> _answered(Future<Object?> future) {
  final answer = Completer<bool>();
  final watch = Timer(const Duration(seconds: 10), () {
    if (!answer.isCompleted) {
      answer.complete(false);
    }
  });
  unawaited(
    future.then((_) {
      if (!answer.isCompleted) {
        watch.cancel();
        answer.complete(true);
      }
    }),
  );
  return answer.future;
}
