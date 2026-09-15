@Tags(['benchmark'])
library;

import 'dart:io' show Platform, ProcessInfo;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/native/native_scratch.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_tip_stamp_cache.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/collect_garbage.dart';
import '../../helpers/device_viewport.dart';

/// 🔬C-ipad-crash ① (유저 2026-09-14): 「2000x1400정도의 소재를 2배크게,
/// 작게 변형을 반복해봤는데 반복시마다 약 150mb가 늘어남 … 2200mb정도에서 다음
/// 변형시 앱이 튕김」.
///
/// ⛔NOT a correctness test — it prints, per round, what every holder the
/// memory census can name is holding after a scale-up and a scale-down, and
/// what is left of the footprint once they are all taken away (`unnamed`,
/// the panel's 「엔진·폰트·프레임워크」), so the one that grows is named by a
/// number instead of a guess. Run it with
/// `flutter test --run-skipped --tags benchmark <this file>`.
///
/// Knobs, one axis each: `TRANSFORM_PROBE_ROUNDS` (6), `TRANSFORM_PROBE_ZOOM`
/// (0.3 — the whole picture on screen) and `TRANSFORM_PROBE_CLEAR_HISTORY=1`
/// (the history let go after every round — what undo holds, released).
///
/// The selection is the picture's own ink box handed to the layer's region
/// door in CANVAS space, and the scale goes through the NUMERIC channel
/// (the tool settings' percentage) — so no marquee corner and no handle has
/// to be on screen. ⛔A handle dragged off the test surface is a pointer
/// that hits nothing, and a box that opens and closes on nothing passes
/// every other line here (the first cut of this probe did exactly that
/// from round 4 at 0.3). What it DOES assert is that each step really
/// scaled the picture: the box opened and closed, the surface was replaced,
/// the history took the step, and the picture's own ink box changed by the
/// factor.
void main() {
  final rounds = int.parse(
    Platform.environment['TRANSFORM_PROBE_ROUNDS'] ?? '6',
  );
  final renderZoom = double.parse(
    Platform.environment['TRANSFORM_PROBE_ZOOM'] ?? '0.3',
  );
  final clearHistory =
      Platform.environment['TRANSFORM_PROBE_CLEAR_HISTORY'] == '1';

  BrushDab square(double x, double y) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xFF3060C0,
    size: 40,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 16)),
      );
      await tester.pump();
    }
  }

  String mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  testWidgets('C-ipad-crash ①: what grows when a big picture is scaled up '
      'and back down, round after round', (tester) async {
    // The device runs the native kernels and the native upload cache; a
    // probe on the Dart fallback would measure a different set of holders.
    // `flutter_test_config.dart` points every test at the built engine —
    // this only refuses to run without it.
    expect(
      QaNativeEngine.instance,
      isNotNull,
      reason: 'fixture: the engine loaded, so its holders are the real ones',
    );
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final store = BrushFrameStore();
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: frameKeys.first,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: defaultCutCanvasSize,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    );
    final history = HistoryManager();
    final commands = CanvasSelectionCommands();
    final transformOptions = ValueNotifier(TransformToolOptions.defaults);
    addTearDown(transformOptions.dispose);

    // A 2000×1400 opaque picture centred on the default 2340×1654 canvas.
    coordinator.commitSourceStroke(
      sourceDabs: [
        for (var y = 147.0; y <= 1507; y += 36)
          for (var x = 190.0; x <= 2150; x += 36) square(x, y),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            canvasSize: defaultCutCanvasSize,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            historyManager: history,
            brushToolState: BrushToolState.defaults.copyWith(
              tool: CanvasTool.select,
            ),
            selectionCommands: commands,
            viewport: seedFromRender(tester, CanvasViewport(zoom: renderZoom)),
            transformOptions: transformOptions,
          ),
        ),
      ),
    );
    await tester.pump();
    await settle(tester);

    ({int width, int height}) picture() {
      final bounds = bitmapSurfaceContentBounds(
        coordinator.currentSurfaceOf(coordinator.activeFrameKey),
      );
      expect(bounds, isNotNull, reason: 'the picture is still on the cel');
      return (
        width: bounds!.rightExclusive - bounds.left,
        height: bounds.bottomExclusive - bounds.top,
      );
    }

    Future<Map<String, int>> holdings() async {
      // A finalizer's callback is a message AFTER the collection, and an
      // image it releases is disposed three frame boundaries later — so
      // the reading waits for both before it looks.
      await tester.runAsync(() async {
        await collectGarbage();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      for (var i = 0; i < 4; i += 1) {
        await tester.pump();
      }
      final engine = QaNativeEngine.instance;
      // The census's own rows, as far as a panel without a session has
      // them — layer images, playback frames and the viewers need one.
      return {
        'footprint': engine?.processFootprintBytes ?? ProcessInfo.currentRss,
        'tileImages': BitmapTileImageCache.liveImageBytes,
        'undo': history.retainedBytes,
        'drawings': store.hotBakedBytes + store.liftedPixelBytes,
        'uploads': engine?.nativeUploadBytes ?? 0,
        'brushTips': BrushTipStampCache.instance.residentBytes,
        'enginePool': engine?.tilePoolParkedBytes ?? 0,
        'scratch': NativeScratch.liveBytes,
        'imageCache': PaintingBinding.instance.imageCache.currentSizeBytes,
        'panelRasters': StaticRaster.censusBytes,
      };
    }

    int unnamedOf(Map<String, int> holding) => holding.entries.fold(
      holding['footprint']!,
      (left, entry) => entry.key == 'footprint' ? left : left - entry.value,
    );

    void report(String label, Map<String, int> now, Map<String, int> base) {
      final size = picture();
      final unnamed = unnamedOf(now);
      final unnamedWas = unnamedOf(base);
      // ignore: avoid_print
      print(
        '$label ${[
          for (final MapEntry(:key, :value) in now.entries)
            '$key=${mb(value)}(${value >= base[key]! ? '+' : ''}'
                '${mb(value - base[key]!)})',
        ].join(' ')} unnamed=${mb(unnamed)}'
        '(${unnamed >= unnamedWas ? '+' : ''}${mb(unnamed - unnamedWas)})'
        ' picture=${size.width}x${size.height}',
      );
    }

    // One numeric scale: the picture's own ink box selected (in canvas
    // space, through the layer's region door — no marquee on screen),
    // Ctrl+T, the percentage set outright, Enter.
    Future<void> scale(double factor) async {
      commands.deselect();
      await tester.pump();
      final bounds = bitmapSurfaceContentBounds(
        coordinator.currentSurfaceOf(coordinator.activeFrameKey),
      )!;
      final left = bounds.left - 2.0;
      final top = bounds.top - 2.0;
      final right = bounds.rightExclusive + 2.0;
      final bottom = bounds.bottomExclusive + 2.0;
      commands.applyRegion(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape([
            CanvasPoint(x: left, y: top),
            CanvasPoint(x: right, y: top),
            CanvasPoint(x: right, y: bottom),
            CanvasPoint(x: left, y: bottom),
          ]),
        ),
      );
      await tester.pump();
      final was = picture();
      final before = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
      final steps = history.revision;
      commands.beginTransform();
      await tester.pump();
      commands.setTransformValues(
        tx: 0,
        ty: 0,
        rotationDegrees: 0,
        scale: factor,
      );
      await tester.pump();
      expect(commands.transformActive, isTrue, reason: 'the box opened');
      commands.commitTransform();
      await tester.pump();
      await settle(tester);
      expect(commands.transformActive, isFalse, reason: 'Enter closed it');
      expect(
        identical(
          coordinator.currentSurfaceOf(coordinator.activeFrameKey),
          before,
        ),
        isFalse,
        reason: 'the landing replaced the cel',
      );
      expect(history.revision, isNot(steps), reason: 'the step was recorded');
      final now = picture();
      expect(
        now.width / was.width,
        closeTo(factor, 0.03),
        reason: 'the picture really scaled ×$factor: '
            '${was.width}×${was.height} → ${now.width}×${now.height}',
      );
    }

    final base = await holdings();
    report('start  ', base, base);
    var previous = base;
    for (var round = 1; round <= rounds; round += 1) {
      // Read after EACH step, not each round: a jump that lands on one
      // step is named by that step.
      for (final factor in const [2.0, 0.5]) {
        final watch = Stopwatch()..start();
        await scale(factor);
        watch.stop();
        if (factor == 0.5 && clearHistory) {
          history.clear();
          await tester.pump();
        }
        final now = await holdings();
        report('round $round ×$factor', now, previous);
        // ignore: avoid_print
        print(
          '    took=${watch.elapsedMilliseconds}ms '
          'rss=${mb(ProcessInfo.currentRss)} '
          'available=${mb(QaNativeEngine.instance?.availableMemoryBytes ?? 0)}',
        );
        previous = now;
      }
    }
    report('total  ', previous, base);

    // ⚠️A FINALIZER'S RELEASE ARRIVES LATE (tile-count-gc-flake, 09-15):
    // `tileImages` comes down in a finalizer callback, a message after the
    // collection. A count still climbing after the undo budget capped could
    // be that lag rather than a holder, so the last reading waits it out —
    // several collections, real time, frames — and says which it was.
    for (var wait = 0; wait < 5; wait += 1) {
      await tester.runAsync(() async {
        await collectGarbage();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var i = 0; i < 4; i += 1) {
        await tester.pump();
      }
    }
    final settled = await holdings();
    report('settled', settled, previous);
  });
}
