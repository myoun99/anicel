import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuInk;

import 'app_gpu_engine.dart';
import 'engine_cel_pixels.dart';
import 'engine_floods.dart';
import 'engine_frame_tools.dart';
import 'engine_strokes.dart';

/// Every set of kernels the app compiles ahead of its first use, off this
/// isolate, one after another: the engine compiles one at a time
/// (`Engine::compiling`), so a set asked for by what needs it now — a
/// frame with an effect chain — waits behind the one compiling and no
/// more; a grid's, which no row waits for, behind what a hand needs
/// ([appGpuGridKernels]).
///
/// 🗣️관제 2026-11-10 18:14 (gpu-canonical-store ⑦): 「선 = UI 스레드가 직접
/// 하는 커널 컴파일 0개(시작 · S5 열기)」 — 🔬eleven kernels were, 15.2–15.5 s
/// of a stopped UI as S5 opened, Surface Pro 11.
///
/// In the order a launch meets them: the scan that finds a cel's ink — a
/// selection may be made before the canvas comes —, the frame's own —
/// nothing is shown on the canvas till they are there —, then what a hand
/// on the canvas would else compile at its first press — a pen's stroke, a
/// colour verb and a selection's lift, a paste, the bucket's fill, a blur
/// brush's stroke —, then the grids' (their rows draw themselves meanwhile),
/// the effect chains' (a frame that names one waits, [FrameKernelsToCome])
/// and the kernels a blur stroke goes by strips with (it goes a pass a
/// dispatch meanwhile).
///
/// 🗣️관제 2026-11-11 04:09 (④): 「첫 획 · 첫 들어올리기에서도 UI 스레드가
/// 직접 하는 커널 컴파일 0, `ink_box` 포함」. 🔬Surface Pro 11, 11-11: the
/// scan was in no list, and compiled where a selection was first made
/// (0.16–0.62 s of a stopped UI at any time of a launch); ↩️the blur
/// brush's ten went with the stroke's three, ahead of all a lift needs —
/// 🔬7.1–7.4 s of them on the Surface, where all a hand needs is 0.96–1.22 s.
///
/// Till what a hand needs is compiled, the passes a composite compiles
/// apart for the plans on screen wait ([GpuEngine.whileCompilesApartWait]):
/// 🗣️관제 2026-11-11 06:00 「선은 첫 획 · 첫 들어올리기의 멈춤 자체다 … 손이
/// 쓰는 커널 → composite 전용 패스」. 🔬Each of them a second of the one
/// compiler, asked for as the canvas first shows, they stood between every
/// two of a hand's kernels: a stroke was ready 2.2–2.6 s after the canvas
/// came and a lift 3.5 s (Surface Pro 11, 11-11 05:59). A frame on screen
/// runs on the pass that takes any plan meanwhile, as it does till its own
/// is compiled. ⛔The effect chains' are not held: a frame that waits for
/// one is not on screen yet.
///
/// 🗣️관제 2026-11-11 06:42: 「블러 브러시도 손이 쓰는 도구라 같은 선이
/// 걸린다」 · 「`ink_box` 컴파일은 12 ms 다. 풀 패스 둘 앞에 두면 첫 캔버스가
/// 얼마 늦는지 재서, 무시할 크기면 앞으로 옮겨라」. 🔬Surface Pro 11, 06:41:
/// a selection made as the frame's own compiled waited 0.2–1.5 s for the
/// scan behind them; a blur stroke before the list was through stopped the
/// app 7.0–10.1 s (`EngineStrokes.warmBlurStrips`).
Future<void> compileAppKernelsAhead() async {
  final EngineFrameTools tools;
  try {
    final engine = await openAppGpuEngine();
    tools = await engine.whileCompilesApartWait(() async {
      // The ledger's scan is its own; the engine keeps the kernel it is
      // made of (`Kernels`, rust/src/device.rs), so one compiled here is
      // every ledger's.
      (await GpuInk.opening(engine)).free();
      final opened = await appEngineFrameTools;
      await EngineStrokes.warm();
      await EngineCelPixels.warm();
      await appGpuStampLandingKernels.warm();
      await EngineFloods.warm();
      await EngineStrokes.warmBlurs();
      return opened;
    });
  } finally {
    // What a hand needs is compiled — or will not be, which whoever asked
    // for this list hears: the app is let go either way. Held on, it could
    // not be saved from.
    _getsReady.value = false;
  }
  await appGpuGridKernels.warm();
  await tools.composite.compileChains();
  await EngineStrokes.warmBlurStrips();
}

/// Whether the app still gets ready what a hand needs of its engine: from
/// a launch's word that it does ([holdTheAppForItsEngine]) till the kernels
/// a hand needs are compiled, or will not be.
///
/// 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「준비가 끝난 뒤에 그림을
/// 띄운다 — 그때까지 고리」 · 「애초에 타임라인같은거도 포함해서 고리띄우고
/// 모든 조작 막음. 서피스에서 느린건 해당문제 차차 속도 빠르게해서 개선」 —
/// ONE fact for all that hold the app meanwhile: a frame keeps its picture
/// from the screen (`FramePictureView`), the app stands behind its one wait
/// window, which takes the editor's input
/// (`HomePage._waitForTheEngineBehindTheWindow` — what the 「고리」 of
/// these words came to, 🗣️유저 2026-11-11 채팅: 「그거 공용창 띄워서 입력
/// 막게하는게 베스트」), and the windows a launch opens of itself wait, a
/// handed file's door among them ([onceTheAppIsLetGo],
/// 🗣️gpu-canonical-store-Q17 · Q18).
///
/// 🗣️관제 2026-11-11 08:25: 「「준비가 끝난」 = 손이 쓰는 커널 전부, 블러
/// 묶음 넷까지(그래야 고리가 걷힌 뒤 어느 도구도 안 멈춘다) … 띠 여섯은
/// 가벼운 길이 같은 그림을 그리니 기다리지 않는다」 — what
/// [compileAppKernelsAhead] compiles under its hold, and no more.
/// 🔬Surface Pro 11, 11-11 07:17: ready 1.20–1.79 s after the canvas could
/// first show (7.1–7.6 s into a launch).
///
/// False where no launch said so: a test's app compiles nothing ahead and
/// is held for nothing.
ValueListenable<bool> get appEngineGetsReady => _getsReady;
final ValueNotifier<bool> _getsReady = ValueNotifier(false);

/// A launch's word, before its first frame, that it compiles its kernels
/// ahead ([compileAppKernelsAhead]): the app is held from that frame on
/// ([appEngineGetsReady]), till that list lets it go.
void holdTheAppForItsEngine() => _getsReady.value = true;

/// Once the app is let go ([appEngineGetsReady]) — at once where it is
/// held for nothing.
///
/// 🗣️유저 2026-11-11, gpu-canonical-store-Q17 「시작할 때 뜨는 창도 준비가
/// 끝난 뒤에 띄운다」 · Q18 「열기도 준비가 끝난 뒤에 시작한다」 — a window
/// no hand on the editor asked for, a launch's own or a handed file's door,
/// waits for this (`HomePage._windowsMayOpen`).
Future<void> onceTheAppIsLetGo() {
  if (!_getsReady.value) {
    return Future.value();
  }
  final letGo = Completer<void>();
  void heard() {
    if (!_getsReady.value) {
      _getsReady.removeListener(heard);
      letGo.complete();
    }
  }

  _getsReady.addListener(heard);
  return letGo.future;
}

/// Test seam: the app let go, as [compileAppKernelsAhead] lets it.
@visibleForTesting
void debugLetTheAppGo() => _getsReady.value = false;
