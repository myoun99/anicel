import 'app_gpu_engine.dart';
import 'engine_cel_pixels.dart';
import 'engine_frame_tools.dart';
import 'engine_strokes.dart';

/// Every set of kernels the app compiles ahead of its first use, off this
/// isolate, one after another: the engine compiles one at a time
/// (`Engine::compiling`), so a set asked for by what needs it now — a grid
/// shown, a frame with an effect chain — waits behind the one compiling
/// and no more.
///
/// 🗣️관제 2026-11-10 18:14 (gpu-canonical-store ⑦): 「선 = UI 스레드가 직접
/// 하는 커널 컴파일 0개(시작 · S5 열기)」 — 🔬eleven kernels were, 15.2–15.5 s
/// of a stopped UI as S5 opened, Surface Pro 11.
///
/// In the order a launch meets them: the frame's own first — nothing is
/// shown on the canvas till they are there —, then what a pen, a colour
/// verb and a paste would else compile at their first press, then the
/// grids' (their rows draw themselves meanwhile) and the effect chains'
/// (a frame that names one waits, [FrameKernelsToCome]).
Future<void> compileAppKernelsAhead() async {
  final tools = await appEngineFrameTools;
  await EngineStrokes.warm();
  await EngineCelPixels.warm();
  await appGpuStampLandingKernels.warm();
  await appGpuGridKernels.warm();
  await tools.composite.compileChains();
}
