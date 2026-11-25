import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// The app's engine, its device gone ([GpuEngine.debugLose]) and the word
/// of it heard — the app's still, till it lets it go
/// ([letTheGoneAppGpuEngineGo]).
///
/// ⚠️A device that is gone is gone for its process: the test after finds
/// the next engine, or none till it asks.
GpuEngine theAppsEngineLost() {
  final gone = appGpuEngine..debugLose();
  // The word that a device is lost comes inside a wait: a read is one.
  expect(
    () => GpuStampPicture(gone, Uint8List(4), 1, 1).pixels(),
    throwsA(isA<GpuReadFailed>()),
  );
  return gone;
}

/// The engine that was the app's: its device gone ([theAppsEngineLost])
/// and the app's no more ([letTheGoneAppGpuEngineGo]) — what stands on it
/// told, and the next ask opening another.
GpuEngine theAppsEngineLostAndLetGo() {
  final gone = theAppsEngineLost();
  letTheGoneAppGpuEngineGo();
  return gone;
}

/// The app with no engine asked for yet, as a launch finds it — and so
/// nothing made on one: the engine it has, if anything has asked for one,
/// lost and let go ([theAppsEngineLostAndLetGo]), as a loss leaves the app.
/// What a test of the first ask, the first compile or the first opening
/// stands on, wherever its file runs in its process: 🔬seven files went
/// red bundled behind files that had opened the engine and compiled on it,
/// green alone (card bundled-files-find-the-engine-already-open,
/// 2026-11-23).
void theAppHasNoEngineYet() {
  if (debugAppGpuEngineAskedFor) {
    theAppsEngineLostAndLetGo();
  }
  expect(debugAppGpuEngineAskedFor, isFalse, reason: '⛔premise: none asked');
}
