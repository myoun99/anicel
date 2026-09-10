@Tags(['benchmark'])
library;

/// WHAT OPENING THE BRUSH LIBRARY COSTS — the probe behind H31's second half
/// (유저 2026-09-10: 「지금 브러시 로드가 매우 느리다」).
///
/// It prints and asserts nothing: the numbers below are what a deliberate
/// lone run reported on a 20-core desktop in the test VM, and they are here
/// so the next round starts from measurements instead of from a hunch.
///
/// 2026-09-10, all 53 built-ins:
///   roster + every mask it names ............................  27 ms
///   the tip library's 12 thumbnails ..........................  92 ms
///   every preview baked, list-sized (2 workers, before) ...... 148 ms
///   every preview baked, list-sized (after) ..................  95 ms
///   every preview baked, DPR-2 four-column cell (before) ..... 362 ms
///   every preview baked, DPR-2 four-column cell (after) ...... 228 ms
///   every preview baked, DPR-2 one-column cell (before) ...... 674 ms
///   every preview baked, DPR-2 one-column cell (after) ....... 402 ms
///   the same bakes again, all cache hits .....................   1 ms
///
/// ⚠️THE PANEL SHOWS ONE GROUP AT A TIME, so the numbers above are the whole
/// roster and the user waits for a fraction of it. The panel's own first
/// frame measured 63-86 ms warm, and its idle frames 0.03 ms — it is not
/// repainting behind your back.
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_tip_defaults.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('COLD: what merely reaching the roster costs', () {
    final masks = Stopwatch()..start();
    final presets = defaultBrushPresets;
    final tipped = presets.where((p) => p.settings.tipMask != null).length;
    masks.stop();
    // ignore: avoid_print
    print(
      'defaultBrushPresets (generates every mask it names): '
      '${masks.elapsedMilliseconds} ms  [$tipped of ${presets.length} tipped]',
    );

    final tips = Stopwatch()..start();
    final entries = defaultBrushTipEntries.length;
    tips.stop();
    // ignore: avoid_print
    print(
      'defaultBrushTipEntries ($entries thumbnails): '
      '${tips.elapsedMilliseconds} ms',
    );
  });

  test('the raster itself, one preset at a time, on this isolate', () async {
    const width = 160;
    const height = 34;
    final presets = defaultBrushPresets;

    // Warm the tip-stamp cache the way a second open would find it.
    rasterizeBrushStrokeSample(presets.first.settings, width, height);

    final rows = <(String, int)>[];
    final wall = Stopwatch()..start();
    for (final preset in presets) {
      final one = Stopwatch()..start();
      rasterizeBrushStrokeSample(preset.settings, width, height);
      one.stop();
      rows.add((preset.name, one.elapsedMicroseconds));
    }
    wall.stop();

    rows.sort((a, b) => b.$2.compareTo(a.$2));
    // ignore: avoid_print
    print(
      'INLINE ${presets.length} presets @ ${width}x$height: '
      '${wall.elapsedMilliseconds} ms',
    );
    for (final row in rows.take(6)) {
      // ignore: avoid_print
      print('  ${(row.$2 / 1000).toStringAsFixed(1)} ms  ${row.$1}');
    }

    final spawn = Stopwatch()..start();
    for (var index = 0; index < 8; index += 1) {
      await Isolate.run(() => 1 + 1);
    }
    spawn.stop();
    // ignore: avoid_print
    print(
      'ISOLATE.run x8 (empty body): ${spawn.elapsedMilliseconds} ms '
      '=> ${(spawn.elapsedMicroseconds / 8000).toStringAsFixed(1)} ms each',
    );
  });

  test('THE REAL PATH: every row through the cache, as the panel asks', () async {
    final presets = defaultBrushPresets;

    for (final size in <(int, int, String)>[
      (160, 34, 'DPR 1, list row'),
      (320, 68, 'DPR 2, four-column cell'),
      (640, 68, 'DPR 2, one-column cell'),
    ]) {
      BrushStrokePreviewCache.instance.clear();
      final wall = Stopwatch()..start();
      await Future.wait([
        for (final preset in presets)
          BrushStrokePreviewCache.instance.ensure(
            preset.settings,
            size.$1,
            size.$2,
          ),
      ]);
      wall.stop();
      // ignore: avoid_print
      print(
        'CACHE.ensure x${presets.length} @ ${size.$1}x${size.$2} '
        '(${size.$3}): ${wall.elapsedMilliseconds} ms',
      );
    }

    final again = Stopwatch()..start();
    await Future.wait([
      for (final preset in presets)
        BrushStrokePreviewCache.instance.ensure(preset.settings, 640, 68),
    ]);
    again.stop();
    // ignore: avoid_print
    print('CACHE.ensure again (all hits): ${again.elapsedMilliseconds} ms');
  });
}
