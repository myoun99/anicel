// Every kernel the app has is compiled before the first test, on a machine
// this busy.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/app_kernels_ahead.dart';
import 'package:anicel/src/native/engine_cel_pixels.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/native/engine_strokes.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';

import '../helpers/an_effect_sampled.dart';

/// 🚨★THE THREAD THE APP'S FRAMES ARE BUILT ON COMPILES NO KERNEL (🗣️관제
/// 2026-11-10 18:14, gpu-canonical-store ⑦: 「선 = UI 스레드가 직접 하는 커널
/// 컴파일 0개(시작 · S5 열기)」): once the list the app compiles ahead is
/// through ([compileAppKernelsAhead]), a pen put down — a second while one
/// stroke is out too —, the blur brush, the scan that finds a cel's ink, a
/// colour verb, a paste, a grid's tile drawn and laid on a screen, and a
/// frame shown — one with an effect chain too — build none where they are
/// asked, each screen laid as this platform lays its own
/// ([ScreenTexture.bgra]); and the list builds none here itself.
///
/// Counted is every kernel this thread waited on the compile of
/// ([debugKernelsCompiledHere]), whether the driver kept it from an earlier
/// run or not — never one the engine has, which is no one's wait
/// (rust/src/device.rs, `Kernels`).
void main() {
  // The letters read their faces from the bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 256, height: 128);
  const side = 128;
  const view = (64, 48);
  const cel = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('inked'),
    frameId: FrameId('f'),
  );
  const row = CompositeLeaf<CanvasStackRow>(
    CanvasLayerImageRequest(frameKey: cel, opacity: 1),
  );
  final blur = fx(EffectKind.blur, {'blurriness': 24});
  late int builtByTheList;
  // Whether what the engine compiles apart was held, looked at between this
  // isolate's turns while the list ran: with what a paste needs — the last
  // of a hand's — still to come, and once the grids' were in.
  final heldBeforeAHandsWereIn = <bool>[];
  final heldOnceTheGridsWereIn = <bool>[];

  setUpAll(() async {
    AppKernels.debugCompileHere = false;
    final before = debugKernelsCompiledHere;
    final looking = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final engine = appGpuEngineOpen.value;
      if (engine == null) {
        return;
      }
      final held = engine.debugCompilesApartHeld > 0;
      if (appGpuStampLandingKernels.compiled == null) {
        heldBeforeAHandsWereIn.add(held);
      }
      if (appGpuGridKernels.compiled != null) {
        heldOnceTheGridsWereIn.add(held);
      }
    });
    await compileAppKernelsAhead();
    looking.cancel();
    builtByTheList = debugKernelsCompiledHere - before;
  });

  /// How many kernels [use] built on this thread.
  int builtHereBy(void Function() use) {
    final before = debugKernelsCompiledHere;
    use();
    return debugKernelsCompiledHere - before;
  }

  /// How many a screen built on this thread laying [nodes] — over a cel of
  /// one inked tile — and showing them, which it does.
  int builtHereShowing(List<CompositeNode<CanvasStackRow>> nodes) {
    final (:composite, :letters) = appEngineFrameToolsOpen!;
    final screen = EngineStackScreen(composite, letters);
    addTearDown(screen.free);
    final target = ScreenTexture.surfaceOf(appGpuEngine, view.$1, view.$2);
    addTearDown(target.free);
    final bare = target.fingerprint();
    final frame = stackedFrameOf(
      nodes,
      page: (
        canvasSize: canvas,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: true,
        paperBackground: const ProjectBackground.color(0xFF30A060),
      ),
      surfaceOf: (_) => BitmapSurface(
        canvasSize: canvas,
        tileSize: side,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            size: side,
            pixels: Uint8List(side * side * 4)
              ..fillRange(0, side * side * 4, 255),
          ),
        },
      ),
      revisionOf: (_) => 1,
    );
    final built = builtHereBy(() {
      screen.compose(frame);
      screen.show(
        target,
        view,
        viewport: CanvasViewport(),
        devicePixelRatio: 1,
      );
    });
    expect(target.fingerprint(), isNot(bare), reason: 'the frame is shown');
    return built;
  }

  test('⛔premise: a kernel built on this thread is counted', () {
    // On an engine of its own: the app's keeps the grids' from the list,
    // and what an engine keeps is no thread's to build.
    final engine = GpuEngine.onFirstAdapter();
    addTearDown(engine.close);
    late final GpuGrid grid;
    expect(builtHereBy(() => grid = GpuGrid(engine)), greaterThan(0));
    grid.free();
  });

  test('the list builds none on this thread', () {
    expect(builtByTheList, 0);
  });

  // 🗣️관제 2026-11-11 06:00 · 06:07 (④): 「손이 쓰는 커널 → composite 전용
  // 패스」, 「잡은 것은 모든 길에서 놓여야 한다」.
  test('what the engine compiles apart is held till what a hand needs is '
      'compiled, and no longer', () {
    expect(heldBeforeAHandsWereIn, isNotEmpty, reason: '⛔premise: looked');
    expect(heldBeforeAHandsWereIn, everyElement(isTrue));
    expect(heldOnceTheGridsWereIn, isNotEmpty, reason: '⛔premise: looked');
    expect(heldOnceTheGridsWereIn, everyElement(isFalse));
    expect(appGpuEngine.debugCompilesApartHeld, 0);
  });

  test('a pen put down builds none, nor the blur brush', () {
    expect(
      builtHereBy(() => EngineStrokes.giveBack(EngineStrokes.take())),
      0,
    );
    expect(builtHereBy(() => EngineStrokes.blurs), 0);
  });

  // 🗣️관제 2026-11-11 04:09 (④): 「첫 획 · 첫 들어올리기에서도 UI 스레드가
  // 직접 하는 커널 컴파일 0, `ink_box` 포함」.
  test('a pen put down while another stroke is out builds none', () {
    final out = EngineStrokes.take();
    expect(EngineStrokes.debugIdle, 0, reason: '⛔premise: none kept');
    late final GpuStroke another;
    expect(builtHereBy(() => another = EngineStrokes.take()), 0);
    EngineStrokes.giveBack(another);
    EngineStrokes.giveBack(out);
  });

  test('the scan that finds a cel\'s ink builds none', () {
    expect(builtHereBy(() => GpuInk(appGpuEngine).free()), 0);
  });

  test('a colour verb builds none', () {
    expect(builtHereBy(() => EngineCelPixels.pass), 0);
  });

  test('a paste builds none', () {
    expect(builtHereBy(() => appGpuStampLanding), 0);
  });

  test('a grid tile drawn and laid on a screen builds none', () {
    final picture = GpuGridPicture(appGpuEngine, 1, 1);
    addTearDown(picture.free);
    final screen = ScreenTexture.surfaceOf(appGpuEngine, 1, 1);
    addTearDown(screen.free);
    final bare = screen.fingerprint();

    expect(
      builtHereBy(() {
        final (:tiles, :lay) = appGpuGridKernels.kept;
        tiles.draw(
          picture,
          (TimelineGridTileOpWriter()..fillRect(
                0,
                0,
                1,
                1,
                timelineGridPackRgba(const Color(0xFFFF0000)),
              ))
              .build(),
        );
        lay.lay(screen, (0, 0, 1, 1), [
          (picture: picture, from: (0, 0, 1, 1), onto: (0, 0, 1, 1)),
        ]);
      }),
      0,
    );
    expect(screen.fingerprint(), isNot(bare), reason: 'the tile is laid');
  });

  test('a frame shown on a screen builds none', () {
    expect(builtHereShowing(const [row]), 0);
  });

  test('a frame whose folder is blurred waits for no kernel, and builds '
      'none', () {
    expect(
      builtHereShowing([
        CompositeGroup(
          children: const [row],
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          effects: [blur],
        ),
      ]),
      0,
    );
  });
}
