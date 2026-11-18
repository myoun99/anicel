import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_refusals.dart';
import 'package:anicel/src/services/diagnostics/gpu_loss_log.dart';

/// 🗣️H63 (관제 2026-11-18): a reset of the GPU leaves, in a file, why the
/// canvas engine's device went and what that engine had sent the GPU and
/// not had back. The app lets a gone engine go the turn after it first
/// hears of it ([EngineRefusals]) — so that engine's word is written
/// there, before it goes: what is written later is of the next.
void main() {
  late File log;

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
}
