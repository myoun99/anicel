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
    /// corner — over [float], once its picture is made.
    Future<void> standOver(
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
      await tester.pumpWidget(
        onAScreen(
          screen,
          size: viewSize,
          under: const Color(0xFF00FF00),
          view: standingOn(
            run,
            picture: picture,
            nodes: nodes,
            viewport: CanvasViewport(),
            live: (
              activeSurfacePainter: painterOf(solid(blue)),
              floatOverlay: float,
              liftedRows: const {},
            ),
          ),
        ),
      );
      final shown = run.pictures.keyOfStack(nodes, picture);
      expect(
        await settleAsync(tester, () => store.bytesOf(shown) != null),
        isTrue,
        reason: 'LIVENESS: the frame\'s picture is made',
      );
      await lendBothClocks(tester, rounds: 2);
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
