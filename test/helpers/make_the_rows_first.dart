import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Makes every row's picture [view] will ask its cache for, under REAL time
/// and at the level it asks them at ([rowQualityThrough]) — so the view's
/// first build holds every one.
///
/// 🚨A row's picture ends in a real decode, which a pumped clock never
/// finishes. Pumped and then settled with `pumpAndSettle` alone, the view
/// holds the rows whose pictures happened to land — on a busy machine not
/// all of them, and not the same ones on the two sides of a comparison
/// (the static bake and single buffer parity tests, 2026-10-10 · 10-11:
/// one side's first pixel the active layer's bare red).
Future<void> makeTheRowsFirst(
  WidgetTester tester,
  CanvasLayerStackView view,
) => tester.runAsync(() async {
  // ⛔One row after another, as the view's own walk.
  for (final row in view.layers) {
    await view.imageCache.prepare(
      key: row.frameKey,
      canvasSize: view.canvasSize,
      quality: rowQualityThrough(view.viewport, tester.view.devicePixelRatio),
      sourceEffects: row.sourceEffects,
      inkSuffices: row.inkSuffices,
    );
  }
});
