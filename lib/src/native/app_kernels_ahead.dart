import 'package:gpu_engine/gpu_engine.dart' show GpuInk;

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
/// shown on the canvas till they are there —, then what a hand on the
/// canvas would else compile at its first press — a pen's stroke, the scan
/// that finds a cel's ink, a colour verb and a selection's lift, a paste —,
/// then the grids' (their rows draw themselves meanwhile), the effect
/// chains' (a frame that names one waits, [FrameKernelsToCome]) and the
/// blur brush's.
///
/// 🗣️관제 2026-11-11 04:09 (④): 「첫 획 · 첫 들어올리기에서도 UI 스레드가
/// 직접 하는 커널 컴파일 0, `ink_box` 포함」. 🔬Surface Pro 11, 11-11: the
/// scan was in no list, and compiled where a selection was first made
/// (0.16–0.62 s of a stopped UI at any time of a launch); ↩️the blur
/// brush's ten went with the stroke's three, ahead of all a lift needs —
/// 🔬a third of the whole list's compile time (main PC, 11-11).
Future<void> compileAppKernelsAhead() async {
  final tools = await appEngineFrameTools;
  await EngineStrokes.warm();
  // The ledger's scan is its own; the engine keeps the kernel it is made
  // of (`Kernels`, rust/src/device.rs), so one compiled here is every
  // ledger's.
  (await GpuInk.opening(appGpuEngine)).free();
  await EngineCelPixels.warm();
  await appGpuStampLandingKernels.warm();
  await appGpuGridKernels.warm();
  await tools.composite.compileChains();
  await EngineStrokes.warmBlurs();
}
