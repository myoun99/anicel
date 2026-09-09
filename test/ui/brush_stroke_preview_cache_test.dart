import 'package:flutter/material.dart';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview.dart';
import 'package:anicel/src/ui/theme/text_on_ground.dart';
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

  group('🚨the name is written on what the SAMPLE put behind it', () {
    test('coverage reads 0 on a bare sample and 1 on a solid one', () {
      expect(
        brushStrokeNameGroundCoverage(Uint8List(64 * 32), width: 64, height: 32),
        0.0,
      );
      expect(
        brushStrokeNameGroundCoverage(
          Uint8List(64 * 32)..fillRange(0, 64 * 32, 255),
          width: 64,
          height: 32,
        ),
        1.0,
      );
    });

    test('⛔it measures the NAME\'s band, not the whole picture', () {
      // Ink only in the top quarter — above where the name sits. A whole-
      // picture mean would report a quarter covered; the band reports none,
      // which is the difference between white ink and black ink.
      const width = 64;
      const height = 32;
      final topOnly = Uint8List(width * height);
      topOnly.fillRange(0, width * (height ~/ 4), 255);

      expect(
        brushStrokeNameGroundCoverage(topOnly, width: width, height: height),
        0.0,
      );
    });

    testWidgets('🚨the row WRITES with the law\'s ink, not a theme colour', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      // A solid brush, so the band under the name really is covered — the
      // case that was invisible: white-ish text on a white-ish stroke.
      final settings = BrushSettings(hardness: 1, flow: 1, opacity: 1);
      const rowGround = Color(0xFF202020);
      final rasterWidth = brushStrokePreviewRasterWidth(120, 1);

      await tester.runAsync(
        () => BrushStrokePreviewCache.instance.ensure(
          settings,
          rasterWidth,
          24,
        ),
      );
      final coverage = BrushStrokePreviewCache.instance
          .sampleFor(settings, rasterWidth, 24)!
          .nameGroundCoverage;
      expect(
        coverage,
        greaterThan(0.5),
        reason: 'fixture premise: this brush really does cover the band',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Center(
            child: SizedBox(
              width: 120,
              height: 24,
              child: BrushStrokePreview(
                settings: settings,
                name: 'Ink Pen',
                nameGround: rowGround,
              ),
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('Ink Pen'));
      final strokeInk = ThemeData.dark().colorScheme.onSurface;
      expect(
        text.style?.color,
        textOnColor(Color.lerp(rowGround, strokeInk, coverage)!),
      );
      expect(
        text.style?.color,
        isNot(strokeInk),
        reason: 'the old ink was the same family the stroke is tinted with',
      );
    });

    test('a bright stroke and a bare row take OPPOSITE inks', () {
      const rowGround = Color(0xFF202020);
      const strokeInk = Color(0xFFF0F0F0);

      final onStroke = textOnColor(
        Color.lerp(rowGround, strokeInk, 1.0)!,
      );
      final offStroke = textOnColor(
        Color.lerp(rowGround, strokeInk, 0.0)!,
      );

      expect(onStroke, textOnLightGroundColor);
      expect(offStroke, textOnDarkGroundColor);
      expect(
        onStroke,
        isNot(offStroke),
        reason: 'this is the whole reason the coverage has to be measured',
      );
    });
  });
}
