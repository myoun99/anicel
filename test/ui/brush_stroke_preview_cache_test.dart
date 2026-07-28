import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_pressure_curve.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview.dart';
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

    final image = await cache.ensure(settings, 96, 24);
    expect(image.width, 96);
    expect(image.height, 24);

    final again = await cache.ensure(settings, 96, 24);
    expect(identical(again, image), isTrue, reason: 'cache hit, no raster');
    expect(identical(cache.imageFor(settings, 96, 24), image), isTrue);

    // A different size is its OWN entry.
    final other = await cache.ensure(settings, 48, 24);
    expect(identical(other, image), isFalse);
    expect(other.width, 48);
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

    // Pre-warm exactly the raster the 120x24 row resolves at DPR 1.
    await tester.runAsync(
      () => BrushStrokePreviewCache.instance.ensure(settings, 120, 24),
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
    expect(raw.image?.width, 120);
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
}
