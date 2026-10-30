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
import 'package:anicel/src/ui/quiet_turns.dart';
import 'package:anicel/src/ui/timeline/timeline_edge_auto_pan.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_window.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/exposure_of.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/poll_until.dart';
import 'tile_store_idle.dart';
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

  Layer rowLayer(String id, {int length = 2}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: {
      for (var start = 0; start < frames; start += 4)
        start: TimelineExposure.drawing(FrameId('$id-f'), length: length),
    },
  );

  /// Where a run of all [frames] turns the axis next from where [bucket]
  /// stands it — the page law's own answer ([nextPageScrollOffset]), on an
  /// axis built to [frames].
  TimelineNextPage turnFrom(ValueListenable<int> bucket) {
    final spanPx = timelineFrameWindowSpanFor(cell) * cell;
    final offset = nextPageScrollOffset(
      (offset: bucket.value * spanPx, viewport: viewport),
      extent: cell,
      runSteps: frames,
    );
    return (
      bucket: timelineFrameWindowBucketOf(offset: offset, cellExtent: cell),
      builtFrames: frames,
    );
  }

  TimelineRowCellsPainter painterFor(
    String id,
    ValueListenable<int> bucket, {
    int builtFrames = frames,
    TimelineNextPage? Function()? nextPage,
    int length = 2,
  }) => TimelineRowCellsPainter(
    layer: rowLayer(id, length: length),
    geometry: testFrameGeometry(
      viewExtentPx: viewport,
      frameCellExtent: cell,
      frameEndIndexExclusive: builtFrames,
    ),
    crossAxisExtent: 28,
    exposureStateForLayer: exposureOf,
    colorScheme: const ColorScheme.dark(),
    baseTextStyle: const TextStyle(fontSize: 11),
    tileStore: store,
    substrateGeneration: 'warm',
    windowBucket: bucket,
    nextPage: nextPage ?? () => turnFrom(bucket),
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

  /// Every span [painter] asks for on the page its axis turns to next.
  List<(int, int)> nextPageOf(TimelineRowCellsPainter painter) =>
      painter.tileSpansOfThePage(painter.nextPage!()!);

  /// The spans of [painter]'s next page its paint does not ask for now —
  /// the ones a warm-up of that page rasters, in the order it takes them.
  List<(int, int)> coldOfTheNextPage(TimelineRowCellsPainter painter) {
    final (:shown, :ahead) = painter.tileSpans;
    return [
      for (final span in nextPageOf(painter))
        if (!shown.contains(span) && !ahead.contains(span)) span,
    ];
  }

  /// Whether every span [painter] would show on its next page is a fresh
  /// tile already — asked for, it is handed over and nothing is queued.
  bool nextPageIsWarm(TimelineRowCellsPainter painter) {
    final next = nextPageOf(painter);
    expect(next, isNotEmpty, reason: '⛔premise: a page to turn to');
    for (final (start, end) in next) {
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

  test('🚨a row\'s page is every span its paint asks for once the axis stands '
      'there — cut where the axis is built to there, past the end it is '
      'built to now', () {
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    // The last page: the turn stands the axis in bucket 28 and builds it
    // to 130 frames, past the 120 it is built to.
    const turn = (bucket: 28, builtFrames: 130);
    final painter = painterFor('pages', bucket);
    final turned = ValueNotifier<int>(turn.bucket);
    addTearDown(turned.dispose);
    final there = painterFor(
      'pages',
      turned,
      builtFrames: turn.builtFrames,
    );

    final (:shown, :ahead) = there.tileSpans;
    final page = painter.tileSpansOfThePage(turn);
    expect(page, [...shown, ...ahead]);
    expect(
      page.last,
      (128, 130),
      reason: 'the span at the end is cut where the turn builds the axis to',
    );
  });

  test('🚨an axis is asked where its turn stands it once a warm-up, however '
      'many rows it lays', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    var asked = 0;
    TimelineNextPage owner() {
      asked += 1;
      return turnFrom(bucket);
    }

    final rows = [
      for (var row = 0; row < 3; row += 1)
        painterFor('laid-$row', bucket, nextPage: owner),
    ];
    for (final painter in rows) {
      show(painter);
      paintRow(painter);
    }
    await tileStoreIdle(store);

    store.warmTheNextPage(tiles: 64);
    await tileStoreIdle(store);

    expect(asked, 1);
    for (final painter in rows) {
      expect(nextPageIsWarm(painter), isTrue, reason: painter.layer.id.value);
    }
  });

  test('a row that windows off no bucket has no page to turn to', () {
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final unbucketed = TimelineRowCellsPainter(
      layer: rowLayer('whole'),
      geometry: testFrameGeometry(
        viewExtentPx: viewport,
        frameCellExtent: cell,
        frameEndIndexExclusive: frames,
      ),
      crossAxisExtent: 28,
      exposureStateForLayer: exposureOf,
      colorScheme: const ColorScheme.dark(),
      baseTextStyle: const TextStyle(fontSize: 11),
      tileStore: store,
      nextPage: () => turnFrom(bucket),
    );
    expect(
      unbucketed.tileSpansOfThePage(turnFrom(bucket)),
      isEmpty,
      reason: 'it paints every span already',
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
    await tileStoreIdle(store);
    final shownRepaints = repaints();

    store.warmTheNextPage(tiles: 16);
    await tileStoreIdle(store);

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
    await tileStoreIdle(store);
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
    await tileStoreIdle(store);

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
    await tileStoreIdle(store);

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
    await tileStoreIdle(store);

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
    await tileStoreIdle(store);
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
    await tileStoreIdle(store);
    expect(uploads, 1, reason: 'the shown one, and the next page waits');
    store.warmTheNextPage(tiles: 64);
    await tileStoreIdle(store);

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
    await tileStoreIdle(store);
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
    await tileStoreIdle(store);
    expect(uploads, 1, reason: 'the span past the window, at rest');
    final rest = {...queued.skip(1), ...coldOfTheNextPage(painter)};
    store.warmTheNextPage(tiles: 64);
    await tileStoreIdle(store);

    expect(uploads, 1 + rest.length, reason: 'and not again with the rest');
  });

  test('a span a paint bakes in its ask is taken off the next page\'s '
      'warm-up — not baked again with the rest (F-314)', () async {
    if (!available) {
      markTestSkipped('qa_engine.dll not built');
      return;
    }
    final bucket = ValueNotifier<int>(0);
    addTearDown(bucket.dispose);
    final before = painterFor('baked', bucket);
    show(before);
    paintRow(before);
    await tileStoreIdle(store);
    store.warmTheNextPage(tiles: 64);
    await tileStoreIdle(store);
    // An edit: every tile of the row, the next page's too, shows the row
    // before it. The paint bakes its own spans in its asks.
    final after = painterFor('baked', bucket, length: 3);
    paintRow(after);
    store.warmTheNextPage(tiles: 0);
    await tileStoreIdle(store);
    var uploads = 0;
    debugRawRgbaUploader =
        (rgba, {required width, required height, targetWidth, targetHeight}) {
          uploads += 1;
          return Future.value(tiny());
        };
    addTearDown(() => debugRawRgbaUploader = null);

    // Queued, none rastered yet: a paint asks for one of them.
    final queued = coldOfTheNextPage(after);
    expect(queued.length, greaterThan(1), reason: '⛔premise: more to warm');
    final (start, end) = queued.first;
    expect(
      store.tileFor(
        painter: after,
        spanStartIndex: start,
        spanEndIndexExclusive: end,
        devicePixelRatio: 1,
      ),
      isNotNull,
    );
    expect(uploads, 0, reason: '⛔premise: baked in the ask');
    store.warmTheNextPage(tiles: 64);
    await tileStoreIdle(store);

    expect(
      uploads,
      queued.length - 1,
      reason: 'the rest of the page once each, and not the span the paint '
          'baked',
    );
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
      store.quietTurns = QuietTurns(
        clock: QuietClock(
          quiet: () => quiet,
          now: () => clock,
          wait: (duration) {
            final begun = Completer<void>();
            waits.add((duration, begun));
            return begun.future;
          },
        ),
      );
    });

    tearDown(() {
      store.quietTurns = QuietTurns.instance;
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
      await tileStoreIdle(store);
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
      await tileStoreIdle(store);
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
      await pollUntil(() => waits.isNotEmpty);

      final (:shown, :ahead) = painter.tileSpans;
      expect(uploads, shown.length, reason: 'the shown spans, at once');
      expect(waits.single.$1, const Duration(microseconds: 5000));
      clock = 5000;
      waits.single.$2.complete();
      await tileStoreIdle(store);
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
      await pollUntil(() => waits.isNotEmpty);
      final shownBefore = painter.tileSpans.shown.length;
      final waiting = painter.tileSpans.ahead.single;
      expect(uploads, shownBefore, reason: '⛔premise: it waits for the quiet');

      // The row scrolls a span on before the quiet begins.
      bucket.value = 1;
      expect(painter.tileSpans.shown, contains(waiting), reason: '⛔premise');
      paintRow(painter);
      await pollUntil(() => uploads != shownBefore);
      expect(uploads, shownBefore + 1, reason: 'shown now: at once');
      clock = 5000;
      waits.single.$2.complete();
      await tileStoreIdle(store);

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
      await tileStoreIdle(store);
      expect(uploads, 1, reason: 'a second 30ms span would end at 60ms');

      quiet = (fromMicros: clock, untilMicros: clock + 1000000);
      store.warmTheNextPage(tiles: 4);
      await tileStoreIdle(store);
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
      await tileStoreIdle(store);
      expect(uploads, 1, reason: '⛔premise: a 30ms span learned');

      quiet = (fromMicros: clock, untilMicros: clock + 25000);
      store.warmTheNextPage(tiles: 4);
      await tileStoreIdle(store);

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
      await tileStoreIdle(store);
      expect(uploads, 1, reason: '⛔premise: a 30ms span learned');

      quiet = (fromMicros: 0, untilMicros: clock - 1);
      store.warmTheNextPage(tiles: 4);
      await tileStoreIdle(store);
      expect(uploads, 1, reason: 'it is over');

      quiet = (fromMicros: clock, untilMicros: clock + 25000);
      store.warmTheNextPage(tiles: 4);
      await tileStoreIdle(store);
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
      await tileStoreIdle(store);

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
      await tileStoreIdle(store);

      expect(uploads, 2);
      expect(waits, isEmpty);
    });

    test('🚨while frames are held, a span waits for the GPU to be done with '
        'the one before it — where a run has no quiet yet as well', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      await shownRow('gpu');
      final gpu = Completer<void>();
      addTearDown(() {
        if (!gpu.isCompleted) {
          gpu.complete();
        }
      });
      store.quietTurns = QuietTurns(
        clock: QuietClock(
          quiet: () => null,
          now: () => clock,
          wait: (_) async {},
          held: () => true,
          gpuDone: () => gpu.future,
        ),
      );

      store.warmTheNextPage(tiles: 2);
      await pollUntil(() => uploads > 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(uploads, 1, reason: 'the GPU is not done with the first');

      gpu.complete();
      await tileStoreIdle(store);
      expect(uploads, 2);
    });

    test('🚨while frames are held, a warm-up asks for its next span once the '
        'GPU is done with the one before — a job that asked meanwhile goes '
        'first', () async {
      if (!available) {
        markTestSkipped('qa_engine.dll not built');
        return;
      }
      await shownRow('fair');
      final gpu = Completer<void>();
      addTearDown(() {
        if (!gpu.isCompleted) {
          gpu.complete();
        }
      });
      final turns = QuietTurns(
        clock: QuietClock(
          quiet: () => null,
          now: () => clock,
          wait: (_) async {},
          held: () => true,
          gpuDone: () => gpu.future,
        ),
      );
      store.quietTurns = turns;

      store.warmTheNextPage(tiles: 2);
      await pollUntil(() => uploads > 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final other = turns.inThisQuiet(QuietSpan(), gone: () => false);
      gpu.complete();
      final turn = await other;
      expect(uploads, 1, reason: 'the job that asked first goes first');

      await turn!.landed();
      await tileStoreIdle(store);
      expect(uploads, 2);
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
      await tileStoreIdle(store);
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
