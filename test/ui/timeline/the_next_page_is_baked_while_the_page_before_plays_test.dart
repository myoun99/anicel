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
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';
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

  /// The spans of [painter]'s next page its paint does not ask for now —
  /// the ones a warm-up of that page rasters, in the order it takes them.
  List<(int, int)> coldOfTheNextPage(TimelineRowCellsPainter painter) {
    final (:shown, :ahead) = painter.tileSpans;
    return [
      for (final span in painter.tileSpansOfTheNextPage)
        if (!shown.contains(span) && !ahead.contains(span)) span,
    ];
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

  test('🚨a row\'s next page is every span its paint asks for once the page '
      'turns, wherever in its bucket the viewport stood — and past the last '
      'frame, the first page', () {
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final painter = painterFor('pages', bucket);
    final span = timelineFrameWindowSpanFor(cell);

    for (var at = 0; at < 3; at += 1) {
      bucket.value = at;
      final next = painter.tileSpansOfTheNextPage.toSet();
      for (var px = at * span * cell; px < (at + 1) * span * cell; px += 1) {
        // The turn stands the frame under the far edge at the window's
        // start ([pageScrollOffset]).
        final left = ((px + viewport) / cell).floor();
        bucket.value = timelineFrameWindowBucketOf(
          offset: left * cell,
          cellExtent: cell,
        );
        final (:shown, :ahead) = painter.tileSpans;
        expect(
          next.containsAll([...shown, ...ahead]),
          isTrue,
          reason: 'bucket $at, the viewport at ${px}px',
        );
        bucket.value = at;
      }
    }

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
    final (start, end) = coldOfTheNextPage(painter).first;
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
    // Every shown span but the last landed: none waits in the queue, one
    // is still being rastered.
    final shown = painter.tileSpans.shown.length;
    for (var landed = 0; landed < shown - 1; landed += 1) {
      held.removeAt(0).complete(tiny());
      await pumpEventQueue();
    }
    expect(uploads, shown, reason: '⛔premise: the last shown span is out');

    store.warmTheNextPage(tiles: 16);
    await pumpEventQueue();

    expect(uploads, shown, reason: 'the warm-up waits for the shown spans');
    while (store.debugBusy) {
      if (held.isNotEmpty) {
        held.removeAt(0).complete(tiny());
      }
      await pumpEventQueue();
    }
    expect(
      uploads,
      shown + painter.tileSpans.ahead.length,
      reason: 'the spans past the window go on once they are rastered, and '
          'the next page only when it is asked for again',
    );
  });

  test('🚨the span past each edge of the window is warmed: rastered, and its '
      'landing repaints nothing', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final painter = painterFor('ahead', bucket);
    final repaints = show(painter);
    paintRow(painter);
    await idle();

    final (:shown, :ahead) = painter.tileSpans;
    expect(ahead, isNotEmpty, reason: '⛔premise: a span past the window');
    expect(
      repaints(),
      shown.length,
      reason: 'only a shown span\'s landing repaints the row',
    );
    for (final (start, end) in ahead) {
      expect(
        store.tileFor(
          painter: painter,
          spanStartIndex: start,
          spanEndIndexExclusive: end,
          devicePixelRatio: 1,
        ),
        isNotNull,
        reason: 'the span past the window is warm',
      );
    }
  });

  test('🚨at rest every span past the windows is warmed, not the few a run '
      'asks for each frame', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    // Away from the first frame: a span past both edges of every window.
    final bucket = ValueNotifier<int>(2);
    addTearDown(bucket.dispose);
    final painters = [
      for (var row = 0; row < 5; row += 1) painterFor('rest-$row', bucket),
    ];
    for (final painter in painters) {
      show(painter);
      paintRow(painter);
    }
    await idle();

    final ahead = [
      for (final painter in painters)
        for (final span in painter.tileSpans.ahead) (painter, span),
    ];
    expect(ahead.length, greaterThan(6), reason: '⛔premise: past a frame\'s');
    for (final (painter, (start, end)) in ahead) {
      expect(
        store.tileFor(
          painter: painter,
          spanStartIndex: start,
          spanEndIndexExclusive: end,
          devicePixelRatio: 1,
        ),
        isNotNull,
        reason: '${painter.layer.id.value}, the span from $start',
      );
    }
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
    final cold = coldOfTheNextPage(painter);
    expect(cold.length, greaterThan(1), reason: '⛔premise: more to warm');
    final (start, end) = cold.first;
    store.tileFor(
      painter: painter,
      spanStartIndex: start,
      spanEndIndexExclusive: end,
      devicePixelRatio: 1,
    );
    await idle();
    expect(uploads, 1, reason: 'the shown one, and the next page waits');
    store.warmTheNextPage(tiles: 64);
    await idle();

    expect(
      uploads,
      cold.length,
      reason: 'each span of the next page once, the one the paint took over '
          'with them',
    );
  });

  test('a span the next page\'s warm-up holds is rastered once when a paint '
      'asks for it past its window', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final painter = painterFor('moved-up', bucket);
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

    // Queued, none rastered yet.
    store.warmTheNextPage(tiles: 0);
    final queued = coldOfTheNextPage(painter);
    // The row scrolls a span on: the first of them is past its window now.
    bucket.value = 1;
    expect(painter.tileSpans.ahead, contains(queued.first), reason: '⛔premise');
    paintRow(painter);
    await idle();
    expect(uploads, 1, reason: 'the span past the window, at rest');
    final rest = {...queued.skip(1), ...coldOfTheNextPage(painter)};
    store.warmTheNextPage(tiles: 64);
    await idle();

    expect(uploads, 1 + rest.length, reason: 'and not again with the rest');
  });

  group('🚨a warm span is rastered in the quiet between two held frames', () {
    var clock = 0;
    ({int fromMicros, int untilMicros})? quiet;
    final waits = <(Duration, Completer<void>)>[];
    var uploads = 0;

    setUp(() {
      clock = 0;
      quiet = null;
      waits.clear();
      uploads = 0;
      store.warmUpQuiet = WarmUpQuiet(
        quiet: () => quiet,
        now: () => clock,
        wait: (duration) {
          final begun = Completer<void>();
          waits.add((duration, begun));
          return begun.future;
        },
      );
    });

    tearDown(() {
      store.warmUpQuiet = const WarmUpQuiet();
      debugRawRgbaUploader = null;
    });

    /// A row shown and painted, its shown spans landed; every upload after
    /// it counted, each [taking] that long on the warm-up's clock.
    Future<TimelineRowCellsPainter> shownRow(
      String id, {
      int taking = 0,
    }) async {
      final bucket = ValueNotifier<int>(0);
      addTearDown(bucket.dispose);
      final painter = painterFor(id, bucket);
      show(painter);
      paintRow(painter);
      await idle();
      debugRawRgbaUploader =
          (rgba, {required width, required height, targetWidth, targetHeight}) {
            uploads += 1;
            clock += taking;
            return Future.value(tiny());
          };
      return painter;
    }

    test('nothing is uploaded before the quiet begins — and in it the '
        'warm-up goes on', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      final painter = await shownRow('quiet');
      quiet = (fromMicros: 5000, untilMicros: 1000000);

      store.warmTheNextPage(tiles: 64);
      await pumpEventQueue();

      expect(uploads, 0, reason: 'the quiet has not begun');
      expect(waits.single.$1, const Duration(microseconds: 5000));
      clock = 5000;
      waits.single.$2.complete();
      await idle();
      expect(nextPageIsWarm(painter), isTrue);
    });

    test('🚨the span past the window waits for the quiet as well — only the '
        'shown spans are rastered at once', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      debugRawRgbaUploader =
          (rgba, {required width, required height, targetWidth, targetHeight}) {
            uploads += 1;
            return Future.value(tiny());
          };
      final bucket = ValueNotifier<int>(0);
      addTearDown(bucket.dispose);
      final painter = painterFor('ahead-quiet', bucket);
      show(painter);
      quiet = (fromMicros: 5000, untilMicros: 1000000);

      paintRow(painter);
      for (var turn = 0; turn < 200 && waits.isEmpty; turn += 1) {
        await pumpEventQueue();
      }

      final (:shown, :ahead) = painter.tileSpans;
      expect(uploads, shown.length, reason: 'the shown spans, at once');
      expect(waits.single.$1, const Duration(microseconds: 5000));
      clock = 5000;
      waits.single.$2.complete();
      await idle();
      expect(uploads, shown.length + ahead.length);
    });

    test('a span past the window that a scroll shows before the quiet is '
        'rastered at once, and once', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      debugRawRgbaUploader =
          (rgba, {required width, required height, targetWidth, targetHeight}) {
            uploads += 1;
            return Future.value(tiny());
          };
      final bucket = ValueNotifier<int>(0);
      addTearDown(bucket.dispose);
      final painter = painterFor('ahead-shown', bucket);
      show(painter);
      quiet = (fromMicros: 5000, untilMicros: 1000000);
      paintRow(painter);
      for (var turn = 0; turn < 200 && waits.isEmpty; turn += 1) {
        await pumpEventQueue();
      }
      final shownBefore = painter.tileSpans.shown.length;
      final waiting = painter.tileSpans.ahead.single;
      expect(uploads, shownBefore, reason: '⛔premise: it waits for the quiet');

      // The row scrolls a span on before the quiet begins.
      bucket.value = 1;
      expect(painter.tileSpans.shown, contains(waiting), reason: '⛔premise');
      paintRow(painter);
      for (var turn = 0; turn < 200 && uploads == shownBefore; turn += 1) {
        await pumpEventQueue();
      }
      expect(uploads, shownBefore + 1, reason: 'shown now: at once');
      clock = 5000;
      waits.single.$2.complete();
      await idle();

      expect(
        uploads,
        shownBefore + 1 + painter.tileSpans.ahead.length,
        reason: 'and the warm-up takes the span past the new edge only',
      );
    });

    test('a span that would land past the quiet\'s end waits for the next '
        'quiet', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      final painter = await shownRow('fits', taking: 30000);
      expect(
        coldOfTheNextPage(painter).length,
        greaterThanOrEqualTo(2),
        reason: '⛔premise: two spans to warm',
      );
      quiet = (fromMicros: 0, untilMicros: 50000);

      store.warmTheNextPage(tiles: 4);
      await idle();
      expect(uploads, 1, reason: 'a second 30ms span would end at 60ms');

      quiet = (fromMicros: clock, untilMicros: clock + 1000000);
      store.warmTheNextPage(tiles: 4);
      await idle();
      expect(uploads, greaterThan(1), reason: 'the next quiet takes it on');
    });

    test('a span longer than a quiet once does not shut the warm-up out for '
        'good', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      await shownRow('decays', taking: 30000);
      quiet = (fromMicros: 0, untilMicros: 50000);
      store.warmTheNextPage(tiles: 4);
      await idle();
      expect(uploads, 1, reason: '⛔premise: a 30ms span learned');

      quiet = (fromMicros: clock, untilMicros: clock + 25000);
      store.warmTheNextPage(tiles: 4);
      await idle();

      expect(uploads, 2, reason: 'a quiet of 25ms still takes one');
    });

    test('a quiet that is over turns the warm-up away and shortens nothing '
        '— the next held frame\'s quiet asks for the span it '
        'learned', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      await shownRow('over', taking: 30000);
      quiet = (fromMicros: 0, untilMicros: 1000000);
      store.warmTheNextPage(tiles: 1);
      await idle();
      expect(uploads, 1, reason: '⛔premise: a 30ms span learned');

      quiet = (fromMicros: 0, untilMicros: clock - 1);
      store.warmTheNextPage(tiles: 4);
      await idle();
      expect(uploads, 1, reason: 'it is over');

      quiet = (fromMicros: clock, untilMicros: clock + 25000);
      store.warmTheNextPage(tiles: 4);
      await idle();
      expect(uploads, 1, reason: 'a 30ms span does not fit 25ms');
    });

    test('🚨a quiet with no room holds the warm-up back — a run that leaves '
        'none is not leave to run beside its frames', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      await shownRow('no-room');
      quiet = (fromMicros: 9000, untilMicros: 4000);

      store.warmTheNextPage(tiles: 4);
      await idle();

      expect(uploads, 0);
      expect(waits, isEmpty, reason: 'nothing to wait for in it either');
    });

    test('with nothing held there is no quiet to wait for', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      await shownRow('free');

      store.warmTheNextPage(tiles: 2);
      await idle();

      expect(uploads, 2);
      expect(waits, isEmpty);
    });
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
