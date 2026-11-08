import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';

import 'a_shown_surface.dart';
import 'native_call_watch.dart';

/// The engine a file of the screen's pins draws on — its composite and the
/// letters cel numbers are laid in —, opened before the file's first test
/// and freed after its last, under a watch on the native calls made on it
/// ([NativeCallWatch]), each test and each step of a screen shown named.
///
/// 🔬Twice a file of these ended in its first test with nothing said and
/// was green run again (flip lane ⓐ-3, 2026-11-08, the main PC): the float
/// pins in a batch of 18 suites, the frame pins alone — no driver reset
/// in the system log, no crash in the application log. The reporter names
/// such a test only as its run ends, so whether it stood or its process
/// ended is not known. The engine waits for the GPU with no limit
/// (device.rs `wait`): a wait that never ends would stop the isolate and
/// every timer in it, which the watch outlives.
final class EngineScreenPins {
  /// Opens the engine for the file of pins [file] names.
  EngineScreenPins(String file) {
    setUpAll(() async {
      final watch = _watch = await NativeCallWatch.start(file);
      watch.step('opening the engine');
      composite = GpuComposite(appGpuEngine);
      letters = await EngineLetters.open(composite);
    });
    setUp(() => _watch.step('a test, past the screen'));
    tearDownAll(() {
      composite.free();
      _watch.stop();
    });
  }

  late final GpuComposite composite;
  late final EngineLetters letters;
  late final NativeCallWatch _watch;

  /// What a screen of [composite]'s shows of [frame] through [viewport] —
  /// at rest where none —, [size] texels, one a device pixel: its
  /// fingerprint. The screen and its target are freed at the test's end.
  int shown(
    StackedFrame frame, {
    required (int, int) size,
    CanvasViewport? viewport,
  }) {
    _watch.step('composing a frame on a screen');
    final screen = EngineStackScreen(composite, letters);
    addTearDown(screen.free);
    screen.compose(frame);
    final (columns, rows) = size;
    final target = shownSurfaceOf(columns, rows);
    addTearDown(target.free);
    _watch.step('showing the screen');
    screen.show(
      target,
      size,
      viewport: viewport ?? CanvasViewport(),
      devicePixelRatio: 1,
    );
    _watch.step('taking what it shows');
    final shown = target.fingerprint();
    _watch.step('a test, past the screen');
    return shown;
  }
}
