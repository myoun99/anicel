import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';

import 'a_shown_surface.dart';


/// What an engine screen of [composite]'s, laying cel numbers in [letters],
/// shows of [frame] through [viewport] — at rest where none —, [size]
/// texels, one a device pixel: its fingerprint. The screen and its target
/// are freed at the test's end.
int engineScreenShown(
  StackedFrame frame, {
  required GpuComposite composite,
  required EngineLetters letters,
  required (int, int) size,
  CanvasViewport? viewport,
}) {
  final screen = EngineStackScreen(composite, letters);
  addTearDown(screen.free);
  screen.compose(frame);
  final (columns, rows) = size;
  final target = shownSurfaceOf(columns, rows);
  addTearDown(target.free);
  screen.show(
    target,
    size,
    viewport: viewport ?? CanvasViewport(),
    devicePixelRatio: 1,
  );
  return target.fingerprint();
}
