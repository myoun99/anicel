/// These cases raster tiles for real and wait for them to land, which under
/// a loaded machine crosses the test package's default 30s — see the head of
/// `timeline_grid_tile_store_test.dart` for the bound and the open round.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/services/straight_rgba_image.dart'
    show debugRawRgbaUploader;
import 'package:anicel/src/ui/timeline/timeline_edge_auto_pan.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/exposure_of.dart';
import '../../helpers/native_engine_path.dart';
import 'timeline_frame_geometry_probe.dart';

/// 🚨A RUN'S NEXT PAGE IS BAKED WHILE IT PLAYS THE PAGE BEFORE (유저
/// 2026-10-11: 「144hz든 몇이든 확실하게 근본/구조적으로 해결하도록」).
///
/// A page turn used to bring every row's next spans under the window cold,
/// and their rasters, word bakes and uploads came all at once in the frames
/// after the turn — the raster thread held 20–35ms and a film frame shown a
/// refresh late at every turn of the first loop. The page after the one
/// shown is now asked for a few spans at a time, after each frame the run
/// changes its film frame in, and its landings repaint nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dllPath = nativeEngineLibraryPathOrNull();
  final available = dllPath != null;
  final store = TimelineGridTileStore.instance;

  // 120 frames at 24px, a 240px viewport: ten frames a page, four to a span
  // (`timelineFrameWindowSpanFor`).
  const frames = 120;
  const cell = 24.0;
  const viewport = 240.0;

  Layer rowLayer(String id) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: {
      for (var start = 0; start < frames; start += 4)
        start: TimelineExposure.drawing(FrameId('$id-f'), length: 2),
    },
  );

  TimelineRowCellsPainter painterFor(String id, ValueListenable<int> bucket) =>
      TimelineRowCellsPainter(
        layer: rowLayer(id),
        geometry: testFrameGeometry(
          frameCellExtent: cell,
          frameEndIndexExclusive: frames,
        ),
        crossAxisExtent: 28,
        exposureStateForLayer: exposureOf,
        colorScheme: const ColorScheme.dark(),
        baseTextStyle: const TextStyle(fontSize: 11),
        tileStore: store,
        substrateGeneration: 'warm',
        windowBucket: bucket,
        viewportMainExtent: viewport,
      );

  void paintRow(TimelineRowCellsPainter painter) {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(frames * cell, 28));
    recorder.endRecording().dispose();
  }

  /// A painter shown on screen: it counts the repaints its landings ask.
  int Function() show(TimelineRowCellsPainter painter) {
    var repaints = 0;
    void onRepaint() => repaints += 1;
    painter.addListener(onRepaint);
    addTearDown(() => painter.removeListener(onRepaint));
    return () => repaints;
  }

  /// A tile's pixels as a held or counted upload hands them back: any image
  /// will do for the store.
  ui.Image tiny() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(Rect.zero, Paint());
    return recorder.endRecording().toImageSync(1, 1);
  }

  Future<void> idle() async {
    while (store.debugBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// Whether every span [painter] would show on its next page is a fresh
  /// tile already — asked for, it is handed over and nothing is queued.
  bool nextPageIsWarm(TimelineRowCellsPainter painter) {
    for (final (start, end) in painter.tileSpansOfTheNextPage) {
      final tile = store.tileFor(
        painter: painter,
        spanStartIndex: start,
        spanEndIndexExclusive: end,
        devicePixelRatio: 1,
      );
      if (tile == null || store.debugBusy) {
        return false;
      }
    }
    return true;
  }

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
    store.clear();
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
    store.clear();
  });

  test('a row\'s next page is the viewport\'s frames from where its window '
      'ends — and past the last frame, the first', () {
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final painter = painterFor('pages', bucket);
    final window = painter.visibleFrameWindow();

    final next = painter.tileSpansOfTheNextPage;
    expect(next.first.$1, lessThanOrEqualTo(window.endIndexExclusive));
    expect(next.last.$2, greaterThanOrEqualTo(window.endIndexExclusive + 10));

    bucket.value = 1000;
    expect(
      painter.tileSpansOfTheNextPage.first.$1,
      0,
      reason: 'a looping run turns back to its first page',
    );
  });

  test('🚨the next page is baked, and its landings repaint nothing', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final painter = painterFor('row', bucket);
    final repaints = show(painter);
    paintRow(painter);
    await idle();
    final shownRepaints = repaints();

    store.warmTheNextPage(tiles: 16);
    await idle();

    expect(nextPageIsWarm(painter), isTrue);
    expect(
      repaints(),
      shownRepaints,
      reason: 'a tile a page away repaints no row',
    );
  });

  test('a warm tile a paint asked for while it was in flight tells the row '
      'when it lands', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final painter = painterFor('asked', bucket);
    final repaints = show(painter);
    paintRow(painter);
    await idle();
    final before = repaints();

    store.warmTheNextPage(tiles: 1);
    // The next page's first span is the one past the window a paint keeps
    // warm itself; the warm-up's first is the one after it.
    final (start, end) = painter.tileSpansOfTheNextPage[1];
    // The page turns before the warm tile lands: a paint asks for it.
    store.tileFor(
      painter: painter,
      spanStartIndex: start,
      spanEndIndexExclusive: end,
      devicePixelRatio: 1,
    );
    await idle();

    expect(repaints(), before + 1);
  });

  test('while a shown span waits, a warm-up starts nothing — what is on the '
      'screen is rastered first', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    var uploads = 0;
    final held = <Completer<ui.Image>>[];
    debugRawRgbaUploader =
        (rgba, {required width, required height, targetWidth, targetHeight}) {
          uploads += 1;
          final landing = Completer<ui.Image>();
          held.add(landing);
          return landing.future;
        };
    addTearDown(() => debugRawRgbaUploader = null);
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final painter = painterFor('first', bucket);
    show(painter);
    paintRow(painter);
    await pumpEventQueue();
    expect(uploads, 1, reason: '⛔premise: a shown span is out');

    store.warmTheNextPage(tiles: 16);
    await pumpEventQueue();

    expect(uploads, 1, reason: 'the warm-up waits for the shown spans');
    while (held.isNotEmpty) {
      held.removeAt(0).complete(tiny());
      await pumpEventQueue();
    }
    final shownUploads = uploads;
    await idle();
    expect(uploads, shownUploads, reason: 'and starts only when asked again');
  });

  test('a span a paint takes over from the warm-up is rastered once', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final painter = painterFor('once', bucket);
    show(painter);
    paintRow(painter);
    await idle();
    var uploads = 0;
    debugRawRgbaUploader =
        (rgba, {required width, required height, targetWidth, targetHeight}) {
          uploads += 1;
          return Future.value(tiny());
        };
    addTearDown(() => debugRawRgbaUploader = null);

    // Queued, none rastered yet: the shown paint below takes one over.
    store.warmTheNextPage(tiles: 0);
    final (start, end) = painter.tileSpansOfTheNextPage[1];
    store.tileFor(
      painter: painter,
      spanStartIndex: start,
      spanEndIndexExclusive: end,
      devicePixelRatio: 1,
    );
    await idle();
    final afterTheShownOne = uploads;
    store.warmTheNextPage(tiles: 64);
    await idle();

    expect(
      uploads,
      afterTheShownOne + painter.tileSpansOfTheNextPage.length - 2,
      reason: 'every span of the next page but the one past the window a '
          'paint keeps warm and the one the paint took over',
    );
  });

  testWidgets('🚨the page law warms the next page after the frame it turns in '
      '— every surface that follows the playhead', (tester) async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final painter = painterFor('law', bucket);
    show(painter);
    await tester.runAsync(() async {
      paintRow(painter);
      await idle();
    });
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: const SizedBox(width: frames * cell, height: 10),
        ),
      ),
    );

    pageToPlayhead((controller: controller, extent: cell, at: 2));
    await tester.pump();

    expect(store.debugBusy, isTrue, reason: 'the next page is being baked');
  });
}
