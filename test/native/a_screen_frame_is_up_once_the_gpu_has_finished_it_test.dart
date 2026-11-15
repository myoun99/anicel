import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show TextureLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/services/bitmap_tile_rgba.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/engine_screen_texture.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../helpers/a_canvas_standing_on_a_frame.dart';
import '../helpers/a_shown_surface.dart';
import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/settle_async.dart';

/// 🚨★★★A SCREEN'S FRAME IS PUT UP ONCE THE GPU HAS FINISHED IT — the last
/// one up standing meanwhile — and the thread that builds the app's frames
/// waits for none of it.
///
/// 🗣️a-float-in-hand-draws-the-frame-as-it-stands-Q2 (유저 2026-11-12):
/// 「z로 직선 그을때나 같은 규칙. ui로서는 바로 작동하지만 정확함을 요구하는
/// 그림은 끝나는대로 준비함 … 어긋나는거 ok」 — the shape tool's law
/// (`LaidWhole`, I-69-Q4ⓒ), on a screen. ↩️Every frame waited for the GPU on
/// that thread: 🔬on the Surface Pro 11 ≈19 ms of a frame's 22, a float
/// dragged over the whole of S5 cut 352.
void main() {
  opensTheEnginesScreens();

  group('a screen\'s frames', () {
    const before = 3;
    const after = 4;
    final reportTo = FlutterError.onError;
    final reported = <FlutterErrorDetails>[];
    late GpuSurface surface;

    setUp(() {
      reported.clear();
      FlutterError.onError = reported.add;
      surface = shownSurfaceOf(4, 4);
    });
    tearDown(() {
      FlutterError.onError = reportTo;
      surface.free();
    });

    /// A screen on [surface] whose frames the GPU finishes as the test says
    /// — each frame's [gates] in order — and how it told it put one up.
    ({ScreenTexture screen, List<Completer<void>> gates, List<bool> told})
    aScreen() {
      final gates = <Completer<void>>[];
      final told = <bool>[];
      final screen = ScreenTexture.debugOnSurface(
        surface,
        id: before,
        nextId: after,
        done: () {
          final gate = Completer<void>();
          gates.add(gate);
          return gate.future;
        },
      )..putUp = ({required behind}) => told.add(behind);
      return (screen: screen, gates: gates, told: told);
    }

    test('a frame drawn is not shown till the GPU has finished it', () async {
      final (:screen, :gates, :told) = aScreen();
      var drawn = 0;

      screen.present((_) => drawn++);

      expect(drawn, 1);
      expect(screen.textureId.value, before, reason: 'the one before stands');
      expect(screen.showsAFrame, isFalse);
      expect(told, isEmpty);

      gates.single.complete();
      await pumpEventQueue();

      expect(screen.textureId.value, after);
      expect(screen.showsAFrame, isTrue);
      expect(told, [false], reason: 'nothing was asked for meanwhile');
    });

    test('🚨asked for while one is on the GPU, nothing is drawn — once that '
        'one is up the asker is told it is behind, and draws the newest '
        'where it presents again', () async {
      final (:screen, :gates, :told) = aScreen();
      final drawn = <String>[];

      screen.present((_) => drawn.add('first'), drawnFor: 'first');
      screen.present((_) => drawn.add('second'), drawnFor: 'second');
      screen.present((_) => drawn.add('third'), drawnFor: 'third');

      expect(drawn, ['first'], reason: 'one frame on the GPU at a time');
      gates.single.complete();
      await pumpEventQueue();

      expect(told, [true]);
      expect(screen.shownFor, 'first', reason: 'what is up is what was drawn');
      screen.present((_) => drawn.add('newest'), drawnFor: 'newest');
      expect(drawn, ['first', 'newest']);
    });

    test('a frame the GPU could not finish leaves the one before it up, by '
        'name — and the next asked for is drawn', () async {
      final (:screen, :gates, :told) = aScreen();
      var drawn = 0;
      final failure = GpuRefused('the GPU did not finish within 30s');

      screen.present((_) => drawn++);
      gates.single.completeError(failure);
      await pumpEventQueue();

      expect(screen.textureId.value, before);
      expect(reported.map((details) => details.exception), [failure]);
      expect(told, [false]);
      screen.present((_) => drawn++);
      expect(drawn, 2);
    });

    test('a frame the GPU could not finish, another asked for meanwhile, '
        'tells the asker it is behind', () async {
      final (:screen, :gates, :told) = aScreen();
      screen.present((_) {});
      screen.present((_) {});

      gates.single.completeError(GpuRefused('the graphics device is gone'));
      await pumpEventQueue();

      expect(told, [true]);
    });

    test('freed while a frame is on the GPU, it is put up nowhere', () async {
      final (:screen, :gates, :told) = aScreen();
      screen.present((_) {});

      unawaited(screen.free());
      gates.single.complete();
      await pumpEventQueue();

      expect(told, isEmpty);
    });

    test('freed while a frame is on the GPU that it cannot finish, nothing '
        'is told of it — but the failure is reported by name', () async {
      final (:screen, :gates, :told) = aScreen();
      final failure = GpuRefused('the graphics device is gone');
      screen.present((_) {});

      unawaited(screen.free());
      gates.single.completeError(failure);
      await pumpEventQueue();

      expect(told, isEmpty);
      expect(reported.map((details) => details.exception), [failure]);
    });

    // A show is handed to the engine unwaited (`GpuScreen.show`), and what
    // refused it is told to the first done its thread asks after it: the
    // screen asks its own in the turn it drew (the-ui-thread-never-enters-
    // the-driver B1-a, 2026-11-15).
    test('🚨a frame whose show the engine refused is reported by the '
        'screen that drew it — not by who asks the engine next', () async {
      final screen = ScreenTexture.debugOnSurface(
        surface,
        done: appGpuEngine.done,
      );
      // Shown before anything is composed on it: refused by name.
      final shown = GpuScreen(appGpuComposite, (0, 0, 4, 4));
      addTearDown(shown.free);
      Future<void>? next;

      screen.present((target) {
        shown.show(
          target,
          inverse: const [1, 0, 0, 1, 0, 0],
          scale: 1,
          sampling: GpuSampling.nearest,
          rect: (0, 0, 4, 4),
        );
        // Who asks the engine next: in this turn, once the screen's is.
        scheduleMicrotask(() => next = appGpuEngine.done());
      });
      await pumpEventQueue();

      await expectLater(next, completes);
      expect(
        reported.map((details) => '${details.exception}'),
        [contains('shown before anything is composed')],
      );
      expect(screen.showsAFrame, isFalse, reason: 'nothing put up');
    });
  });

  // On an engine of the test's own: a device that is gone is gone for its
  // process, and the app has one.
  group('the engine says when the GPU is done', () {
    late GpuEngine engine;
    setUp(() => engine = GpuEngine.onFirstAdapter());
    tearDown(() => engine.close());

    test('with no wait for it here', () async {
      final waits = debugWaitsHere;

      await engine.done();

      expect(debugWaitsHere, waits);
    });

    test('a device gone is told by name', () async {
      engine.debugLose();

      await expectLater(
        engine.done(),
        throwsA(
          isA<GpuRefused>().having(
            (refused) => refused.message,
            'message',
            contains('gone'),
          ),
        ),
      );
    });
  });

  test('🚨a wait on an engine closed meanwhile is told so by name, reading '
      'nothing of the engine gone', () async {
    final engine = GpuEngine.onFirstAdapter()..debugLose();
    await expectLater(
      engine.done(),
      throwsA(isA<GpuRefused>()),
      reason: '⛔premise: the device is gone, and a wait says so',
    );
    // Told after the engine has closed, whenever its thread tells it: the
    // isolate goes on to the close before it reads a word it was told.
    final ending = engine.done();
    engine.close();

    await expectLater(
      ending,
      throwsA(
        isA<GpuRefused>().having(
          (refused) => refused.message,
          'message',
          contains('closed'),
        ),
      ),
    );
  });

  group('a canvas', () {
    const canvasSize = CanvasSize(
      width: defaultCelTileSize,
      height: defaultCelTileSize,
    );
    const viewSize = Size(defaultCelTileSize * 1.0, defaultCelTileSize * 1.0);
    final red = RgbaColor(r: 255, g: 0, b: 0, a: 255);
    final blue = RgbaColor(r: 0, g: 0, b: 255, a: 255);
    final screen = GlobalKey();
    const key = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('l'),
      frameId: FrameId('f'),
    );
    final picture = (
      cut: Cut(
        id: key.cutId,
        name: 'c',
        duration: 1,
        canvasSize: canvasSize,
        layers: const [],
      ),
      frameIndex: 0,
      paintPaper: false,
      ghosts: FrameGhosts.none,
    );
    final nodes = [
      const CompositeLeaf<CanvasStackRow>(
        CanvasActiveLayerRow(opacity: 1, frameKey: key),
      ),
    ];

    BitmapSurface solid(RgbaColor color) => BitmapSurface(
      canvasSize: canvasSize,
      tileSize: defaultCelTileSize,
      tiles: {
        TileCoord(x: 0, y: 0): writeRgbaColorToBitmapTile(
          tile: BitmapTile.blank(size: defaultCelTileSize),
          x: 0,
          y: 0,
          color: color,
        ),
      },
    );

    BitmapSurfacePainter painterOf(BitmapSurface surface) =>
        BitmapSurfacePainter(
          surface: surface,
          showTransparentBackground: false,
        );

    /// The canvas standing on [nodes] — the cel [key] keeps blue at the
    /// corner — over [float], once its picture is made: answers how the
    /// same canvas is seen through another view.
    Future<Future<void> Function(CanvasViewport view)> standOver(
      WidgetTester tester,
      SelectionFloatOverlay float,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final cels = BrushFrameStore();
      keepInAFile(cels, {key: solid(blue)});
      final images = LayerFrameImageCache(frameStore: cels);
      addTearDown(images.dispose);
      final store = aStoreOfPictures();
      addTearDown(store.dispose);
      final run = runOver(
        images,
        store,
        canvasSize: canvasSize,
        stackOf: (_) => nodes,
      );
      final LiveRows live = (
        activeSurfacePainter: painterOf(solid(blue)),
        floatOverlay: float,
        liftedRows: const {},
      );
      Widget seenThrough(CanvasViewport view) => onAScreen(
        screen,
        size: viewSize,
        under: const Color(0xFF00FF00),
        view: standingOn(
          run,
          picture: picture,
          nodes: nodes,
          viewport: view,
          live: live,
        ),
      );
      await tester.pumpWidget(seenThrough(CanvasViewport()));
      final shown = run.pictures.keyOfStack(nodes, picture);
      expect(
        await settleAsync(tester, () => store.bytesOf(shown) != null),
        isTrue,
        reason: 'LIVENESS: the frame\'s picture is made',
      );
      await lendBothClocks(tester, rounds: 2);
      return (view) => tester.pumpWidget(seenThrough(view));
    }

    SelectionFloatPaint redAt(double at) => SelectionFloatPaint(
      surface: painterOf(solid(red)),
      surfaceOffset: CanvasPoint(x: at, y: at),
    );

    bool redOn(Shot shot, int at) => shot.rgba[(at * shot.width + at) * 4] > 200;

    /// Every screen the canvas opens is on a surface of its own, each frame
    /// drawn on it put up once [done] has ended — as the app's are.
    void screensFinishedBy(Future<void> Function() done) {
      final opener = debugOpenEngineScreen;
      addTearDown(() => debugOpenEngineScreen = opener);
      debugOpenEngineScreen = (_, width, height) async {
        final surface = shownSurfaceOf(width, height);
        final id = shownScreens.length + 1;
        shownScreens[id] = surface;
        return ScreenTexture.debugOnSurface(surface, id: id, done: done);
      };
    }

    /// Where each layer a screen is shown by from here on was laid, in
    /// the order they were — shown as the app shows them, read back by
    /// none.
    List<Rect> layersLaid() {
      final laid = <Rect>[];
      final shows = debugLayerOfScreen;
      addTearDown(() => debugLayerOfScreen = shows);
      debugLayerOfScreen =
          ({required rect, required textureId, required filterQuality}) {
            laid.add(rect);
            return TextureLayer(
              rect: rect,
              textureId: textureId,
              filterQuality: filterQuality,
            );
          };
      return laid;
    }

    /// The GPU finishing each frame at once till [hold] is called, then
    /// as the test opens each frame's gate, in order.
    ({List<Completer<void>> gates, void Function() hold}) aGpuHeld() {
      var holding = false;
      final gates = <Completer<void>>[];
      screensFinishedBy(() {
        if (!holding) {
          return Future.value();
        }
        gates.add(Completer<void>());
        return gates.last.future;
      });
      return (gates: gates, hold: () => holding = true);
    }

    // 🗣️유저 2026-11-15 (card a-pan-moves-the-overlays-before-the-canvas):
    // 「캔버스 화면 팬으로 움직일때 카메라 오버레이? 위젯이랑 캔버스랑
    // 어긋나거든? … 이런 캔버스에 보이는건 동일하게 했으면좋겟는데」 — what
    // Flutter draws over the picture is drawn for the view as it stands,
    // every frame; the frame up is laid where it was drawn for, a pan away.
    testWidgets('🚨a pan moves the frame up with the view, drawing nothing '
        'while the frame drawn last serves it — and past that, the frame '
        'that comes up stands where it was drawn for', (tester) async {
      final (:gates, :hold) = aGpuHeld();
      final float = SelectionFloatOverlay(null);
      addTearDown(float.dispose);
      final seenThrough = await standOver(tester, float);
      final laid = layersLaid();
      await seenThrough(CanvasViewport());
      await tester.pump();
      // Where a frame drawn for the view as it stands is laid.
      final home = laid.last;
      expect(
        home.left < 0 && home.top < 0,
        isTrue,
        reason: '⛔premise: the screen holds room before the box — $home',
      );
      expect(
        home.right > viewSize.width && home.bottom > viewSize.height,
        isTrue,
        reason: '⛔premise: and past it — $home',
      );
      hold();

      // Within what the screen spares of its box.
      await seenThrough(CanvasViewport(panX: 10, panY: 6));
      expect(gates, isEmpty, reason: 'a pan the frame up serves drew one');
      expect(
        laid.last,
        home.shift(const Offset(10, 6)),
        reason: 'the frame up did not move with the view',
      );

      // Past it — as far as the frame up still holds the box's corner.
      final far = -home.left;
      await seenThrough(CanvasViewport(panX: far, panY: 6));
      expect(gates, hasLength(1), reason: 'the next frame is asked for');
      expect(
        laid.last,
        home.shift(Offset(far, 6)),
        reason: 'what is up moves on with the view meanwhile',
      );

      await seenThrough(CanvasViewport(panX: far + 20, panY: 6));
      expect(gates, hasLength(1), reason: 'the frame on the GPU serves it');
      expect(laid.last, home.shift(Offset(far + 20, 6)));

      gates.last.complete();
      await tester.pump();
      await tester.pump();
      expect(gates, hasLength(1), reason: 'a frame up that serves drew one');
      expect(
        laid.last,
        home.shift(const Offset(20, 0)),
        reason: 'the frame drawn a step back stands a step from the view',
      );
    });

    testWidgets('a view turned draws every step of a pan: it pans by parts '
        'of a pixel, and a frame moved by whole ones would stand off what '
        'is drawn over it', (tester) async {
      final (:gates, :hold) = aGpuHeld();
      final float = SelectionFloatOverlay(null);
      addTearDown(float.dispose);
      final seenThrough = await standOver(tester, float);
      await seenThrough(CanvasViewport(rotationDegrees: 30));
      await tester.pump();
      hold();

      await seenThrough(
        CanvasViewport(rotationDegrees: 30, panX: 10.4, panY: 6),
      );

      expect(gates, hasLength(1));
    });

    testWidgets('a zoom since the frame up was drawn moves it nowhere: it '
        'stands as drawn till the next is up', (tester) async {
      final (:gates, :hold) = aGpuHeld();
      final float = SelectionFloatOverlay(null);
      addTearDown(float.dispose);
      final seenThrough = await standOver(tester, float);
      final laid = layersLaid();
      await seenThrough(CanvasViewport());
      await tester.pump();
      final home = laid.last;
      hold();

      await seenThrough(CanvasViewport(zoom: 2, panX: 10, panY: 6));

      expect(gates, hasLength(1), reason: '⛔premise: the step is on the GPU');
      expect(laid.last, home);
    });

    testWidgets('what a pan shows is the picture through the view, the '
        'screen\'s room past the box shown nowhere', (tester) async {
      final float = SelectionFloatOverlay(null);
      addTearDown(float.dispose);
      final seenThrough = await standOver(tester, float);
      bool blueAt(Shot shot, int x, int y) {
        final at = (y * shot.width + x) * 4;
        return shot.rgba[at + 2] > 200 && shot.rgba[at + 1] < 50;
      }

      final stood = await shotOf(tester, screen);
      expect(
        blueAt(stood, 0, 0) && !blueAt(stood, 1, 1),
        isTrue,
        reason: 'drawn with room about it, the view\'s corner is the box\'s',
      );

      await seenThrough(CanvasViewport(panX: 10, panY: 6));
      await tester.pump();

      final shot = await shotOf(tester, screen);
      expect(blueAt(shot, 10, 6), isTrue, reason: 'the cel\'s corner, panned');
      expect(blueAt(shot, 0, 0), isFalse, reason: 'it stood where it was');
      expect(blueAt(shot, 11, 7), isFalse, reason: 'one pixel of it alone');
    });

    testWidgets('🚨a float dragged over it waits for no GPU on the thread '
        'that paints it', (tester) async {
      var drawn = 0;
      screensFinishedBy(() {
        drawn++;
        return Future.value();
      });
      final float = SelectionFloatOverlay(null);
      addTearDown(float.dispose);
      await standOver(tester, float);
      // The test's own layer reads a screen back to show it, and a read
      // waits for the GPU: none is read while the drag is counted.
      final shows = debugLayerOfScreen;
      addTearDown(() => debugLayerOfScreen = shows);
      debugLayerOfScreen = TextureLayer.new;

      final (waits, drawnBefore) = (debugWaitsHere, drawn);
      for (final at in [0.0, 1.0, 2.0]) {
        float.value = redAt(at);
        await tester.pump();
      }

      expect(debugWaitsHere, waits, reason: 'a step of the drag waited here');
      expect(drawn - drawnBefore, 3, reason: '⛔premise: each step was drawn');
    });

    testWidgets('🚨a step of the drag while a frame is on the GPU is drawn '
        'once that one is up — and a frame up with nothing newer draws '
        'nothing more', (tester) async {
      // The GPU finishes at once, till the test holds it.
      var holding = false;
      final gates = <Completer<void>>[];
      screensFinishedBy(() {
        if (!holding) {
          return Future.value();
        }
        gates.add(Completer<void>());
        return gates.last.future;
      });
      final float = SelectionFloatOverlay(null);
      addTearDown(float.dispose);
      await standOver(tester, float);
      holding = true;

      float.value = redAt(0);
      await tester.pump();
      expect(gates, hasLength(1), reason: 'the step is on the GPU');
      float.value = redAt(2);
      await tester.pump();
      expect(gates, hasLength(1), reason: 'one frame on the GPU at a time');

      gates.last.complete();
      await tester.pump();
      await tester.pump();
      expect(gates, hasLength(2), reason: 'the newest step, drawn once up');

      gates.last.complete();
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
      }
      expect(gates, hasLength(2), reason: 'a frame put up drew another');
      final last = await shotOf(tester, screen);
      expect(redOn(last, 2) && !redOn(last, 0), isTrue, reason: 'the newest');
    });
  });
}
