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
  final composite = GpuComposite(await openAppGpuEngine());
  return (composite: composite, letters: await EngineLetters.open(composite));
}();
Future<EngineFrameTools>? _tools;
