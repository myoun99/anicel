import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/brush_shape.dart';
import 'package:anicel/src/ui/brush/brush_stroke_preview_cache.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';

/// 🚨THE FINEST SPACING IS 1% OF THE TIP (유저 2026-09-24: 「간격 최소치 너무
/// 높지않나? 더 작게 해도 될거같은데 클튜나 포토샵 참고해서」) — Photoshop's
/// floor, and the one the ABR import already reads. 5% stood here and raised
/// every finer brush to it on the way into the tool.
void main() {
  test('a brush keeps a spacing down to 1%, and no finer', () {
    expect(BrushShape.minSpacing, 0.01);
    expect(BrushToolState(spacing: 0.02).spacing, 0.02);
    expect(BrushToolState(spacing: 0.01).spacing, 0.01);
    expect(BrushToolState(spacing: 0.004).spacing, BrushShape.minSpacing);
    expect(
      BrushToolState.fromBrushSettings(
        BrushSettings(size: 60, spacing: 0.02),
      ).spacing,
      0.02,
      reason: 'an imported 2% brush arrives at 2%',
    );
  });

  test('the preview steps where the canvas steps — 1% and 1.5% of a large '
      'tip are different strokes', () {
    // A 140 px row: the preview's tip is about 87 px, so 1% steps one pixel
    // and 1.5% about 1.3. A preview that floored spacing at 2% of its own
    // drew the two alike.
    const width = 400;
    const height = 140;
    final settings = BrushSettings(size: 40, hardness: 0.3, flow: 0.2);
    final one = rasterizeBrushStrokeSample(
      settings.copyWith(spacing: 0.01),
      width,
      height,
    );
    final oneAndAHalf = rasterizeBrushStrokeSample(
      settings.copyWith(spacing: 0.015),
      width,
      height,
    );
    // One alpha byte per pixel.
    var differ = 0;
    for (var i = 0; i < one.length; i += 1) {
      if (one[i] != oneAndAHalf[i]) differ += 1;
    }
    expect(differ, greaterThan(0));
  });
}
