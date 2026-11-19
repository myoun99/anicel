// Every kernel the app has is compiled before the first test, on a machine
// this busy.
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:io';
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
import 'package:anicel/src/native/engine_floods.dart';
import 'package:anicel/src/native/engine_frame_tools.dart';
import 'package:anicel/src/native/engine_selection_masks.dart';
import 'package:anicel/src/native/engine_strokes.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';

import '../helpers/an_effect_sampled.dart';
import '../helpers/tiles_on_the_engine.dart';

/// 🚨★THE THREAD THE APP'S FRAMES ARE BUILT ON COMPILES NO KERNEL (🗣️관제
/// 2026-11-10 18:14, gpu-canonical-store ⑦: 「선 = UI 스레드가 직접 하는 커널
/// 컴파일 0개(시작 · S5 열기)」): once the list the app compiles ahead is
/// through ([compileAppKernelsAhead]), a pen put down — a second while one
/// stroke is out too —, the blur brush, the scan that finds a cel's ink, a
/// colour verb, a paste, a grid's tile and a sound's wave drawn and laid on
/// a screen, and a
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
  // isolate's turns while the list ran: with what a blur stroke needs — one
  // of a hand's, all asked for at once — still to come, and once the grids'
  // were in.
  final heldBeforeAHandsWereIn = <bool>[];
  final heldOnceTheGridsWereIn = <bool>[];
  // Whether the app was held for its engine ([appEngineGetsReady]), looked
  // at so too while a hand's were still to come — and what was compiled the
  // moment it was let go.
  final appHeldBeforeAHandsWereIn = <bool>[];
  ({bool aHandsAreIn, bool theGridsAreIn})? whenTheAppWasLetGo;

  // Whether the folder the app's engine keeps its shaders in was empty
  // before the engine opened.
  var nothingWasKeptAtFirst = false;

  setUpAll(() async {
    // The run's own container in place of the machine's folder
    // (flutter_test_config.dart): that one holds what earlier runs kept,
    // and would answer 「kept for the next launch」 whatever this run's
    // engine did.
    debugAppShaderFolder = null;
    final folder = Directory(appShaderFolder());
    nothingWasKeptAtFirst = !folder.existsSync() || folder.listSync().isEmpty;
    AppKernels.debugCompileHere = false;
    final before = debugKernelsCompiledHere;
    final looking = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final engine = appGpuEngineOpen.value;
      if (engine == null) {
        return;
      }
      final held = engine.debugCompilesApartHeld > 0;
      if (!EngineStrokes.debugBlursCompiled) {
        heldBeforeAHandsWereIn.add(held);
        appHeldBeforeAHandsWereIn.add(appEngineGetsReady.value);
      }
      if (appGpuGridKernels.compiled != null) {
        heldOnceTheGridsWereIn.add(held);
      }
    });
    // As the app's first grid screen asks, the engine just open: before the
    // list has held (`TimelineGridScreenHost`).
    final grids = appGpuGridKernels.warm();
    // As a launch says it, before its first frame (`main`).
    holdTheAppForItsEngine();
    void letGo() => whenTheAppWasLetGo ??= (
      aHandsAreIn: EngineStrokes.debugBlursCompiled,
      theGridsAreIn: appGpuGridKernels.compiled != null,
    );
    appEngineGetsReady.addListener(letGo);
    await compileAppKernelsAhead();
    appEngineGetsReady.removeListener(letGo);
    await grids;
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
  /// one inked tile — and showing them, which it does: its laying and its
  /// show are handed to the engine unwaited, and what they build is this
  /// thread's once they have run ([GpuEngine.done]).
  Future<int> builtHereShowing(
    List<CompositeNode<CanvasStackRow>> nodes,
  ) async {
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
    final before = debugKernelsCompiledHere;
    final composed = screen.compose(frame);
    screen.show(target, view, viewport: CanvasViewport(), devicePixelRatio: 1);
    final shown = appGpuEngine.done();
    await composed;
    await shown;
    final built = debugKernelsCompiledHere - before;
    expect(target.fingerprint(), isNot(bare), reason: 'the frame is shown');
    return built;
  }

  test('⛔premise: a kernel built on this thread is counted', () {
    // On an engine of its own: the app's keeps the grids' from the list,
    // and what an engine keeps is no thread's to build.
    final engine = GpuEngine.onFirstAdapter();
    addTearDown(engine.close);
    late final GpuGridBatch batch;
    expect(builtHereBy(() => batch = GpuGridBatch(engine)), greaterThan(0));
    batch.free();
  });

  test('the list builds none on this thread', () {
    expect(builtByTheList, 0);
  });

  // 🗣️유저 2026-11-13 (the-wait-window-stands-seven-seconds-on-the-surface-Q1,
  // 「디스크 캐시」): what the list compiled is kept for the next launch, in
  // the app's folder for it (rust/vendor/wgpu-hal, compile_cache.rs).
  test(
    'what the list compiled is kept for the next launch',
    () {
      expect(nothingWasKeptAtFirst, isTrue, reason: '⛔premise: none before');
      final kept = Directory(appShaderFolder()).listSync().whereType<File>();
      expect(kept, isNotEmpty);
    },
    skip: Platform.isWindows ? false : 'what is kept is what DXC made',
  );

  // 🗣️관제 2026-11-11 06:00 · 06:07 (④): 「손이 쓰는 커널 → composite 전용
  // 패스」, 「잡은 것은 모든 길에서 놓여야 한다」.
  // 🔬The grids' kernels, asked for by a screen as the engine opened, stood
  // ahead of a stroke's: 0.43–0.59 s of the lay pass on the Surface Pro 11
  // (2026-11-11 06:41) — they wait with what the engine compiles apart.
  test('what the engine compiles apart is held till what a hand needs is '
      'compiled, and no longer — the grids\' a screen asked for as the '
      'engine opened come after it', () {
    expect(heldBeforeAHandsWereIn, isNotEmpty, reason: '⛔premise: looked');
    expect(heldBeforeAHandsWereIn, everyElement(isTrue));
    expect(heldOnceTheGridsWereIn, isNotEmpty, reason: '⛔premise: looked');
    expect(heldOnceTheGridsWereIn, everyElement(isFalse));
    expect(appGpuEngine.debugCompilesApartHeld, 0);
  });

  // 🗣️gpu-canonical-store-Q15 (유저 2026-11-11): 「준비가 끝난 뒤에 그림을
  // 띄운다 — 그때까지 고리」 · 🗣️관제 08:25: 「「준비가 끝난」 = 손이 쓰는 커널
  // 전부, 블러 묶음 넷까지 … 띠 여섯은 … 기다리지 않는다」.
  test('the app is held from a launch\'s word till what a hand needs is '
      'compiled, and let go there — the grids\', the chains\' and the blur '
      'brush\'s strips still to come', () {
    expect(appHeldBeforeAHandsWereIn, isNotEmpty, reason: '⛔premise: looked');
    expect(appHeldBeforeAHandsWereIn, everyElement(isTrue));
    expect(
      whenTheAppWasLetGo,
      (aHandsAreIn: true, theGridsAreIn: false),
      reason: 'let go as the last a hand needs was in, behind which the '
          'grids\' compile waits',
    );
    expect(appEngineGetsReady.value, isFalse);
  });

  test('a pen put down builds none, nor the blur brush', () {
    expect(
      builtHereBy(() => EngineStrokes.giveBack(EngineStrokes.take())),
      0,
    );
    expect(builtHereBy(() => EngineStrokes.blurs), 0);
  });

  test('the blur brush goes by strips once the list is through', () {
    expect(EngineStrokes.blurs.debugGoesByStrips, isTrue);
  });

  // F-610 (2026-11-19): the fold's kernels are the list's, handed to a
  // fold compiled — what its body compiled on the engine's thread would
  // be counted here once it had run —, and the engine keeps the unfold
  // for the read that first meets a tile lying folded.
  test('a fold of the ledger\'s tiles builds none, nor the read of a tile '
      'that lies folded', () async {
    expect(appGpuFoldKernels.compiled, isNotNull, reason: '⛔premise');
    final ledger = EngineTileLedger.instance;
    final tile = landedOn(ledger, [null], 9).single;
    final (bytes, before) = (ledger.pool.bytes, debugKernelsCompiledHere);
    while (await ledger.foldABatch()) {}
    await appGpuEngine.done();
    expect(
      ledger.pool.bytes,
      greaterThan(bytes),
      reason: '⛔premise: a page of folded tiles is the pool\'s',
    );
    expect(tile.pixels.toSet(), {9});
    expect(debugKernelsCompiledHere - before, 0);
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

  // As a selection's float is carried through a mesh
  // (`EngineStampPictures.meshed`): the mesh's own two passes and the
  // warp's.
  test('a float carried through a mesh builds none', () {
    final float = GpuStampPicture(appGpuEngine, Uint8List(2 * 2 * 4), 2, 2);

    expect(
      builtHereBy(
        () => appGpuStampLanding.meshed(
          float,
          at: (0, 0),
          columns: 1,
          rows: 1,
          source: const [0, 0, 2, 0, 0, 2, 2, 2],
          destination: const [0, 0, 2, 0, 0, 2, 3, 3],
          radiusFloor: 1,
          sampling: GpuSampling.blend,
          window: (0, 0, 4, 4),
        ),
      ),
      0,
    );
  });

  test('the bucket\'s fill builds none', () {
    expect(builtHereBy(() => EngineFloods.kernels), 0);
  });

  test('a stroke under a selection builds none for its mask', () {
    expect(builtHereBy(() => EngineSelectionMasks.kernels), 0);
  });

  test('a grid tile drawn and laid on a screen builds none', () {
    final screen = ScreenTexture.surfaceOf(appGpuEngine, 1, 1);
    addTearDown(screen.free);
    final bare = screen.fingerprint();

    expect(
      builtHereBy(() {
        final (:batch, :lay) = appGpuGridKernels.kept;
        final picture = batch.picture(1, 1)!;
        addTearDown(picture.free);
        batch.draw(
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

  test("a sound's wave drawn and laid on a screen builds none", () {
    final peaks = GpuWavePeaks(appGpuEngine, [
      Uint16List.fromList([65535, 65535]),
    ]);
    final screen = ScreenTexture.surfaceOf(appGpuEngine, 4, 8);
    addTearDown(screen.free);
    final bare = screen.fingerprint();

    expect(
      builtHereBy(() {
        final (:batch, :lay) = appGpuGridKernels.kept;
        final picture = batch.picture(4, 8)!;
        addTearDown(picture.free);
        batch.wave(picture, peaks, (
          along0: 0,
          length: 4,
          vertical: false,
          frameQ8: 256,
          fpsNumerator: 1,
          fpsDenominator: 1,
          bucketsPerSecond: 1,
          leadingFrames: 0,
          acrossQ8: 8 * 256,
          gainQ16: 65536,
          rgba: 0xFFFFFFFF,
        ));
        lay.lay(screen, (0, 0, 4, 8), [
          (picture: picture, from: (0, 0, 4, 8), onto: (0, 0, 4, 8)),
        ]);
      }),
      0,
    );
    expect(screen.fingerprint(), isNot(bare), reason: 'the wave is laid');
  });

  test('a frame shown on a screen builds none', () async {
    expect(await builtHereShowing(const [row]), 0);
  });

  // As a file's frame is made (`frameOnTheEngine`): its ground laid, and a
  // frame shown on a screen of this platform's laid over it.
  test('a frame laid for a file builds none', () {
    final export = appGpuExportKernels.compiled!;
    final surface = ScreenTexture.surfaceOf(appGpuEngine, 2, 1);
    addTearDown(surface.free);

    expect(
      builtHereBy(() {
        final frame = export.blank(2, 1, ground: 0xFFFFFFFF);
        final shown = export.shown(surface, 2, 1);
        export.lay(frame, shown);
        shown.free();
        frame.free();
      }),
      0,
    );
  });

  // What a file's writer turns its frame into bytes by
  // (`still_frame_bytes.dart`, `video_export_service.dart`,
  // `conte_pdf_writer.dart`; `animated_png_writer.dart`, handed its frames
  // as straight bytes), each handed a frame as a file's is made
  // (`frameOnTheEngine`) and a frame shown on a screen of this
  // platform's: the app hands them the first alone today, and the
  // bindings take the second.
  final conversions = <String, void Function(GpuExport, GpuShown)>{
    'a movie\'s frame turned to NV12': (export, frame) => export
        .nv12(
          frame,
          2,
          2,
          frameWidth: 2,
          frameHeight: 2,
          stride: GpuExport.nv12RowBytes(2),
        )
        .free(),
    'a picture put over its ground': (export, frame) =>
        export.overGround(frame, 2, 2, 0xFFFFFF).free(),
    'a GIF\'s clear pixels found': (export, frame) =>
        export.clear(frame, 2, 2, 128).free(),
    'a picture asked whether it is opaque': (export, frame) =>
        export.opaque(frame, 2, 2),
    'a picture turned straight': (export, frame) =>
        export.straight(frame, 2, 2).free(),
    'a PNG\'s rows of four bytes a pixel filtered': (export, frame) =>
        export.pngRgba(frame, 2, 2).free(),
    'a PNG\'s rows of three bytes a pixel filtered': (export, frame) {
      final rgb = export.overGround(frame, 2, 2, 0xFFFFFF);
      export.pngRgb(rgb, 2, 2).free();
      rgb.free();
    },
    'an animated PNG\'s frame filtered straight': (export, frame) =>
        export.pngStraight(Uint8List(2 * 2 * 4), 2, 2).free(),
  };
  for (final MapEntry(key: kind, value: convert) in conversions.entries) {
    test('$kind builds none', () {
      final export = appGpuExportKernels.compiled!;
      final surface = ScreenTexture.surfaceOf(appGpuEngine, 2, 2);
      addTearDown(surface.free);

      expect(
        builtHereBy(() {
          for (final frame in [
            export.blank(2, 2, ground: 0xFFFFFFFF),
            export.shown(surface, 2, 2),
          ]) {
            convert(export, frame);
            frame.free();
          }
        }),
        0,
      );
    });
  }

  test('a frame whose folder is blurred waits for no kernel, and builds '
      'none', () async {
    expect(
      await builtHereShowing([
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
