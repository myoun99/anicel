import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_refusals.dart';
import 'package:anicel/src/services/diagnostics/gpu_loss_log.dart';

import '../helpers/poll_until.dart';

/// 🗣️H63 (관제 2026-11-18): a reset of the GPU leaves, in a file, why the
/// canvas engine's device went and what that engine had sent the GPU and
/// not had back. The app lets a gone engine go the turn after it first
/// hears of it ([EngineRefusals]) — so that engine's word is written
/// there, before it goes: what is written later is of the next.
///
/// And wherever else the app hears that the GPU stopped (board
/// a-real-gpu-reset-went-unheard-on-the-main-pc, 2026-11-22): a wait past
/// its limit with the device standing, and a device gone that the app
/// stays on — each once a cause, as a cause is told once.
void main() {
  late File log;

  void hear(Object refused) =>
      FlutterError.reportError(FlutterErrorDetails(exception: refused));

  /// What [job] is refused by.
  GpuRefused refusedBy(void Function() job) {
    try {
      job();
    } on GpuRefused catch (refused) {
      return refused;
    }
    fail('not refused');
  }

  /// The losses written, each by the line it opens with.
  List<String> written() => log.existsSync()
      ? log
            .readAsLinesSync()
            .where((line) => line.startsWith(GpuLossLog.opening))
            .toList()
      : const [];

  /// What is written under the loss whose opening line ends in [title].
  List<String> writtenUnder(String title) {
    final lines = log.readAsLinesSync();
    final from = lines.indexWhere((line) => line.endsWith(title));
    final next = lines.indexWhere(
      (line) => line.startsWith(GpuLossLog.opening),
      from + 1,
    );
    return lines.sublist(from, next < 0 ? lines.length : next);
  }

  setUp(() {
    log = File(GpuLossLog.logPath());
    if (log.existsSync()) {
      log.deleteSync();
    }
    final reported = FlutterError.onError;
    final uncaught = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = reported;
      PlatformDispatcher.instance.onError = uncaught;
      EngineRefusals.debugForget();
      // No test leaves the app on a device that is gone.
      letTheGoneAppGpuEngineGo();
      if (log.existsSync()) {
        log.deleteSync();
      }
    });
    FlutterError.onError = (_) {};
    PlatformDispatcher.instance.onError = (_, _) => true;
  });

  test("the app's engine let go as its device went leaves why it went and "
      'what it had sent the GPU — its own word, not the next\'s', () async {
    EngineRefusals.install(openAnother: () async => letTheGoneAppGpuEngineGo());
    final gone = appGpuEngine;
    final pool = GpuPool(gone, 1 << 30);
    addTearDown(pool.free);
    final tile = calloc<Uint8>(gpuTileBytes);
    addTearDown(() => calloc.free(tile));
    pool.store(pool.cel(), [tile], (tile) => tile);
    await gone.done();
    gone.debugLose(forMemory: true);
    final had = gone.unfinishedSubmits.trimRight().split('\n');
    expect(had.first, startsWith('submit #'), reason: '⛔premise: it sent');
    expect(appGpuEngineIsGone, isTrue, reason: '⛔premise: it is gone');

    FlutterError.reportError(
      FlutterErrorDetails(exception: GpuRefused('a landing')),
    );
    await pumpEventQueue();
    expect(isTheAppsEngine(gone), isFalse, reason: '⛔premise: let go');

    final lines = log.readAsLinesSync();
    expect(lines.first, startsWith(GpuLossLog.opening));
    expect(lines.first, endsWith("the canvas engine's device went"));
    expect(lines, contains('engine gone=true went=${gone.wentBy.name}'));
    expect(lines, containsAllInOrder(had));
  });

  test('a wait past its limit, its device standing, leaves what the engine '
      'had sent the GPU at the first refusal heard once one is — whatever '
      'that refusal says, once a run, and nothing before one', () async {
    EngineRefusals.install();
    final engine = appGpuEngine;
    // ⚠️An engine's waits past their limit stay counted: this one goes
    // with the test, so the next finds another.
    addTearDown(() => engine.debugLose(forMemory: true));
    expect(appGpuEngineIsGone, isFalse, reason: '⛔premise: it stands');

    // What a body handed over unwaited says: no word of why.
    hear(GpuRefused('a landing was not finished'));
    await pumpEventQueue();
    expect(written(), isEmpty, reason: 'no wait was late');

    final late = refusedBy(engine.debugWaitPastItsLimit);
    expect(
      late.message,
      startsWith('the GPU did not finish within'),
      reason: '⛔premise: as the engine ends such a wait',
    );
    expect(appGpuEngineIsGone, isFalse, reason: '⛔premise: late, not gone');
    expect(written(), isEmpty, reason: 'at a refusal heard, not before');

    hear(GpuRefused('a landing was not finished'));
    await pumpEventQueue();
    const title = 'the GPU did not finish what the engine sent it';
    expect(written().single, endsWith(title));
    expect(
      writtenUnder(title),
      containsAllInOrder([
        'engine gone=false went=${GpuDeviceWent.unsaid.name}',
        'engine waits past their limit=1',
      ]),
    );

    hear(late);
    hear(GpuReadFailed('a read'));
    await pumpEventQueue();
    expect(written(), hasLength(1), reason: 'once a run');
  });

  test('a device gone that the app stays on — within a minute of the last '
      'opening — leaves what that engine had sent the GPU as well, once '
      'the one cause', () async {
    var now = DateTime(2026, 11, 22, 17);
    EngineRefusals.debugClockOverride = () => now;
    addTearDown(() => EngineRefusals.debugClockOverride = null);
    EngineRefusals.install(
      openAnother: () async {
        letTheGoneAppGpuEngineGo();
        await openAppGpuEngine();
      },
    );
    appGpuEngine.debugLose(forMemory: true);
    hear(GpuRefused('a landing'));
    await pumpEventQueue();
    expect(
      await pollUntil(() => appGpuEngineOpen.value != null),
      isTrue,
      reason: '⛔premise: the next is open',
    );
    await pumpEventQueue();
    expect(written(), hasLength(1), reason: '⛔premise: the first, let go');

    now = now.add(
      EngineRefusals.openAnotherApart - const Duration(seconds: 1),
    );
    final stayedOn = appGpuEngine..debugLose(forMemory: true);
    hear(GpuRefused('a landing'));
    await pumpEventQueue();
    expect(isTheAppsEngine(stayedOn), isTrue, reason: '⛔premise: stays');
    const title =
        "the canvas engine's device went, and none stands in its place";
    expect(written(), hasLength(2));
    expect(written().last, endsWith(title));
    expect(
      writtenUnder(title),
      contains('engine gone=true went=${stayedOn.wentBy.name}'),
    );

    hear(GpuReadFailed('a read'));
    hear(GpuRefused('a frame'));
    await pumpEventQueue();
    expect(written(), hasLength(2), reason: 'the one cause, written once');
  });
}
