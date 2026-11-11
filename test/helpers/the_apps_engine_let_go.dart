import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';

/// The engine that was the app's: its device gone ([GpuEngine.debugLose])
/// and the app's no more ([letTheGoneAppGpuEngineGo]) — what stands on it
/// told, and the next ask opening another.
///
/// ⚠️A device that is gone is gone for its process: the test after finds
/// the next engine, or none till it asks.
GpuEngine theAppsEngineLostAndLetGo() {
  final gone = appGpuEngine..debugLose();
  // The word that a device is lost comes inside a wait: a read is one.
  expect(
    () => GpuStampPicture(gone, Uint8List(4), 1, 1).pixels(),
    throwsA(isA<GpuReadFailed>()),
  );
  letTheGoneAppGpuEngineGo();
  return gone;
}
