import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;
import 'package:anicel/src/ui/brush/brush_stroke_preview_cache.dart';

/// UI-R18 R18-B: the stroke-preview raster moved into an app-wide LRU
/// image cache filled off the UI isolate — a preset rasterizes ONCE per
/// (settings, size), and rows draw the cached image thereafter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(BrushStrokePreviewCache.instance.clear);

  test('the sample rasterizer is deterministic and non-empty', () {
    final settings = BrushSettings(
      sizePressureCurve: BrushPressureCurve.identity(),
      opacityPressureCurve: BrushPressureCurve.identity(),
    );
    final first = rasterizeBrushStrokeSample(settings, 96, 24);
    final second = rasterizeBrushStrokeSample(settings, 96, 24);
    expect(first, equals(second));
    expect(first.any((value) => value > 0), isTrue);
  });

  test('ensure() rasterizes once per key and later lookups hit the SAME '
      'image', () async {
    final cache = BrushStrokePreviewCache.instance;
    final settings = BrushSettings();

    final sample = await cache.ensure(settings, 96, 24);
    expect(sample.image.width, 96);
    expect(sample.image.height, 24);

    final again = await cache.ensure(settings, 96, 24);
    expect(identical(again, sample), isTrue, reason: 'cache hit, no raster');
    expect(identical(cache.sampleFor(settings, 96, 24), sample), isTrue);

    // A different size is its OWN entry.
    final other = await cache.ensure(settings, 48, 24);
    expect(identical(other, sample), isFalse);
    expect(other.image.width, 48);
  });

  test('concurrent requests for one key share one raster', () async {
    final cache = BrushStrokePreviewCache.instance;
    final settings = BrushSettings(hardness: 0.4);

    final results = await Future.wait([
      cache.ensure(settings, 64, 16),
      cache.ensure(settings, 64, 16),
      cache.ensure(settings, 64, 16),
    ]);
    expect(identical(results[0], results[1]), isTrue);
    expect(identical(results[1], results[2]), isTrue);
  });

  testWidgets('a row with a warm cache paints the image on its FIRST '
      'build — no synchronous raster in the scroll path', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = BrushSettings();

    // Pre-warm exactly the raster the 120x24 row resolves at DPR 1 — the
    // width comes off the LADDER, not off the row.
    final rasterWidth = brushStrokePreviewRasterWidth(120, 1);
    await tester.runAsync(
      () => BrushStrokePreviewCache.instance.ensure(settings, rasterWidth, 24),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 24,
            child: BrushStrokePreview(settings: settings),
          ),
        ),
      ),
    );

    expect(find.byType(RawImage), findsOneWidget);
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image?.width, rasterWidth);
    expect(raw.image?.height, 24);
  });

  testWidgets('a COLD row mounts blank (layout held) and pops the image '
      'in when the async raster lands', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = BrushSettings(opacity: 0.7);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 120,
              height: 24,
              child: BrushStrokePreview(settings: settings),
            ),
          ),
        ),
      );
      expect(find.byType(RawImage), findsNothing);

      // Let the isolate raster + upload land, then rebuild.
      for (var attempt = 0; attempt < 200; attempt += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.byType(RawImage).evaluate().isNotEmpty) {
          break;
        }
      }
    });
    expect(find.byType(RawImage), findsOneWidget);
  });

  group('🚨the rasters run on a POOL that outlives them', () {
    test('the fan-out cap is a ceiling on LIVE workers, not on requests', () {
      // ⚠️Not a speed claim. The pool exists because a fresh isolate per
      // raster starts with every per-isolate static cold — the tip-stamp
      // cache, and (this is the point) `QaNativeEngine.instance`, which
      // would mean opening the engine library once per preset.
      expect(BrushStrokePreviewCache.rasterWorkersFor(1), 1);
      expect(BrushStrokePreviewCache.rasterWorkersFor(20), 4);
    });

    testWidgets('⛔a worker does NOT keep the 128 MB stamp budget it inherits', (
      tester,
    ) async {
      // The one thing a pool costs that `Isolate.run` did not: the tip-stamp
      // cache is a per-isolate static, and the isolate no longer dies. At the
      // stock 128 MB budget, four workers could sit on half a gigabyte in the
      // background — which the old-device policy does not allow.
      final cache = BrushStrokePreviewCache.instance;
      await tester.runAsync(
        () => cache.ensure(BrushSettings(hardness: 0.44), 32, 12),
      );
      expect(
        cache.workerStampByteBudget,
        lessThanOrEqualTo(16 * 1024 * 1024),
        reason: 'the worker has to shrink the budget it inherits',
      );
      expect(
        cache.workerStampByteBudget,
        greaterThan(0),
        reason: 'and not turn the cache off, which would re-render every dab',
      );
    });

    testWidgets('more requests than workers all finish, and no extra worker '
        'is spawned to serve them', (tester) async {
      final cache = BrushStrokePreviewCache.instance;
      final cap = BrushStrokePreviewCache.rasterWorkersFor(
        // The pool sizes itself off the machine; the pin is that whatever it
        // chose, the request count does not move it.
        20,
      );
      // Distinct settings so nothing shares a bake and every one really goes
      // to a worker.
      final requests = <Future<BrushStrokeSample>>[];
      await tester.runAsync(() async {
        for (var index = 0; index < 12; index += 1) {
          requests.add(
            cache.ensure(BrushSettings(hardness: 0.1 + index * 0.05), 48, 16),
          );
        }
        final samples = await Future.wait(requests);
        expect(samples, hasLength(12));
        for (final sample in samples) {
          expect(sample.image.width, 48);
        }
      });

      expect(
        cache.liveWorkerCount,
        lessThanOrEqualTo(cap),
        reason: 'twelve requests must not mint twelve isolates',
      );
      expect(
        cache.liveWorkerCount,
        greaterThan(0),
        reason: 'and the pool must actually have been used',
      );
    });
  });

  testWidgets('⛔a pool that lost its workers comes BACK', (tester) async {
    // The hazard a persistent pool has and `Isolate.run` did not: a worker
    // that goes away takes its slot with it. If the pool kept counting the
    // corpse against the cap, one crash would shrink it for the life of the
    // app — and if it handed the corpse out, the row would wait forever on a
    // reply nobody is going to send.
    final cache = BrushStrokePreviewCache.instance;
    await tester.runAsync(() async {
      await cache.ensure(BrushSettings(hardness: 0.31), 32, 12);
      expect(cache.liveWorkerCount, greaterThan(0));

      // A CRASH, not a shutdown: the pool is not told, so the corpse is still
      // in its list. ⚠️`shutdownWorkersForTests` empties the list itself and
      // so proves only that the pool can spawn from empty — a mutation that
      // let dead workers keep their slot walked straight through it.
      final before = cache.liveWorkerCount;
      cache.killOneWorkerForTests();

      final after = await cache.ensure(BrushSettings(hardness: 0.32), 32, 12);
      expect(after.image.width, 32);
      expect(
        cache.liveWorkerCount,
        lessThanOrEqualTo(before),
        reason: 'the corpse must not still be counted against the cap',
      );
      expect(
        cache.liveWorkerCount,
        greaterThan(0),
        reason: 'and a live one has to have taken its place',
      );

      cache.shutdownWorkersForTests();
      expect(cache.liveWorkerCount, 0);
      final revived = await cache.ensure(BrushSettings(hardness: 0.33), 32, 12);
      expect(revived.image.width, 32);
    });
  });

  group('🚨the bake is ONE job, and it is the isolate\'s', () {
    test('what comes back is the raster, widened — nothing is recomputed on '
        'this side', () {
      // The expansion and the ink measurement used to run HERE, once per
      // preset, in the frames the panel was trying to paint. They moved into
      // the isolate because `Isolate.run` TRANSFERS its result instead of
      // copying it, so the wider buffer is free on the wire. This pins that
      // the move changed the address of the work and nothing else.
      final settings = BrushSettings(hardness: 0.8, flow: 0.9);
      final alpha = rasterizeBrushStrokeSample(settings, 64, 20);

      final baked = bakeBrushStrokeSample(settings, 64, 20);

      expect(baked, hasLength(alpha.length * 4));
      for (var index = 0; index < alpha.length; index += 1) {
        final base = index * 4;
        expect(
          [
            baked[base],
            baked[base + 1],
            baked[base + 2],
            baked[base + 3],
          ],
          everyElement(alpha[index]),
          reason: 'premultiplied WHITE: every channel is the coverage',
        );
      }
    });

    test('🚨the fan-out leaves the UI isolate a core, and stops climbing '
        'where the measurement did', () {
      // 유저 2026-09-10: 「지금 브러시 로드가 매우 느리다」. A flat two queued
      // the whole roster behind two workers on a 20-core desktop, and — worse
      // — ran two beside the UI isolate on a two-core tablet.
      expect(BrushStrokePreviewCache.rasterWorkersFor(1), 1);
      expect(BrushStrokePreviewCache.rasterWorkersFor(2), 1);
      expect(BrushStrokePreviewCache.rasterWorkersFor(4), 3);
      // Measured on all 53 built-ins: 674 ms at 2, 419 ms at 4, 346 ms at 8.
      // The ceiling is where the curve flattened, not where the cores ran out.
      expect(BrushStrokePreviewCache.rasterWorkersFor(20), 4);
      for (var cores = 2; cores <= 64; cores += 1) {
        expect(
          BrushStrokePreviewCache.rasterWorkersFor(cores),
          lessThanOrEqualTo(cores - 1),
          reason: '$cores cores must not all go to rasters',
        );
      }
    });
  });

  group('🚨the raster width is a LADDER, not the row width', () {
    test('a splitter drag across a whole panel asks for a handful of '
        'rasters, not one per pixel', () {
      // 유저 2026-09-10: 「패널 스플리터로 조절할때마다 재로드인가
      // 재계산되던데」. The cache is keyed by (settings, width, height), so a
      // continuous width is a fresh key — and a fresh isolate raster — every
      // frame of the drag, for every visible row.
      final widths = <int>{
        for (var logical = 120; logical <= 420; logical += 1)
          brushStrokePreviewRasterWidth(logical.toDouble(), 1),
      };

      expect(
        widths.length,
        lessThan(12),
        reason: '301 row widths must collapse onto a few rungs',
      );
      expect(widths.length, greaterThan(1), reason: 'and not onto ONE rung');
    });

    test('every rung is at or above the row, so the draw only ever scales '
        'DOWN', () {
      for (var logical = 1; logical <= 400; logical += 7) {
        for (final dpr in [1.0, 1.5, 2.0]) {
          final raster = brushStrokePreviewRasterWidth(logical.toDouble(), dpr);
          expect(
            raster,
            greaterThanOrEqualTo((logical * dpr).floor()),
            reason: 'a rung below $logical @$dpr would upscale and blur',
          );
          expect(raster, greaterThan(0));
        }
      }
    });

    testWidgets('⛔a row that RESIZES never goes blank — the picture it has '
        'stays up while the next rung bakes', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = BrushSettings();

      Widget rowOf(double width) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            height: 24,
            child: BrushStrokePreview(settings: settings),
          ),
        ),
      );

      await tester.runAsync(
        () => BrushStrokePreviewCache.instance.ensure(
          settings,
          brushStrokePreviewRasterWidth(120, 1),
          24,
        ),
      );
      await tester.pumpWidget(rowOf(120));
      expect(find.byType(RawImage), findsOneWidget);

      // Two rungs wider: nothing is cached at that size yet.
      await tester.pumpWidget(rowOf(200));
      expect(
        find.byType(RawImage),
        findsOneWidget,
        reason: 'the drag must not flash an empty row',
      );
    });

    test('the device pixel ratio scales the rung, it does not create new '
        'ones', () {
      expect(
        brushStrokePreviewRasterWidth(120, 2),
        brushStrokePreviewRasterWidth(120, 1) * 2,
      );
    });
  });

  group('🚨H38: the name is written BLACK, dead centre', () {
    testWidgets('one ink over every ground, in the middle of the row', (
      tester,
    ) async {
      // 유저 2026-09-11: 「브러시 버튼도 지금 뒤 색에 따라 흰색이나
      // 검정색인데, 하나로 통일하고싶거든? 그냥 검정색통일. 공용슬라이더랑
      // 똑같이 검정색 통일하고 텍스트 위치도 중앙아래가 아니라 완전중앙으로」.
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Center(
            child: SizedBox(
              key: const ValueKey<String>('row'),
              width: 120,
              height: 24,
              child: BrushStrokePreview(
                settings: BrushSettings(hardness: 1, flow: 1, opacity: 1),
                name: 'Ink Pen',
              ),
            ),
          ),
        ),
      );

      final name = find.text('Ink Pen');
      expect(tester.widget<Text>(name).style?.color, AppColors.inkOnPaint);
      expect(
        tester.getCenter(name),
        tester.getCenter(find.byKey(const ValueKey<String>('row'))),
        reason: '「중앙아래가 아니라 완전중앙」',
      );
    });
  });
}
