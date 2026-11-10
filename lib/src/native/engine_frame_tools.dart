import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';
import 'engine_letters.dart';

/// What a frame is laid on the engine with: the executor, and the letters
/// its cel numbers are set in.
typedef EngineFrameTools = ({GpuComposite composite, EngineLetters letters});

/// The app's, opened the first time anything asks, off the engine
/// [openAppGpuEngine] opens: a store of frames' pictures is made before the
/// engine is open, and what it is asked for waits for this.
Future<EngineFrameTools> get appEngineFrameTools => _tools ??= () async {
  await openAppGpuEngine();
  final composite = await debugCompositeOfTheTools();
  return _open = (
    composite: composite,
    letters: await EngineLetters.open(composite),
  );
}();
Future<EngineFrameTools>? _tools;

/// How [appEngineFrameTools] has its executor: compiled off this isolate.
/// A test seam: a widget test's clock is pumped, and lends a compile on
/// another isolate no real time to finish in (`flutter_test_config.dart`).
@visibleForTesting
Future<GpuComposite> Function() debugCompositeOfTheTools =
    appGpuCompositeKernels.warm;

/// [appEngineFrameTools] where they are open already: a store made after
/// that has no turn to wait before its first paint.
EngineFrameTools? get appEngineFrameToolsOpen => _open;
EngineFrameTools? _open;
