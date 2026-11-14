import 'package:gpu_engine/gpu_engine.dart';

import 'app_gpu_engine.dart';
import 'engine_letters.dart';

/// What a frame is laid on the engine with: the executor, and the letters
/// its cel numbers are set in.
typedef EngineFrameTools = ({GpuComposite composite, EngineLetters letters});

/// The app's, opened the first time anything asks, off the engine
/// [openAppGpuEngine] opens: a store of frames' pictures is made before the
/// engine is open, and what it is asked for waits for this. Opened again
/// on the next engine, once the app lets this one go
/// ([KeptOnTheAppsEngine]).
Future<EngineFrameTools> get appEngineFrameTools => _tools.of(_opened);
final _tools = KeptOnTheAppsEngine<Future<EngineFrameTools>>();

Future<EngineFrameTools> _opened() async {
  final engine = await openAppGpuEngine();
  final composite = await appGpuCompositeKernels.warm();
  final letters = await EngineLetters.open(composite);
  if (!isTheAppsEngine(engine)) {
    // The app let that engine go while these opened on it.
    return appEngineFrameTools;
  }
  return _open.of(() => (composite: composite, letters: letters));
}

/// [appEngineFrameTools] where they are open already: a store made after
/// that has no turn to wait before its first paint.
EngineFrameTools? get appEngineFrameToolsOpen => _open.orNull;
final _open = KeptOnTheAppsEngine<EngineFrameTools>();
