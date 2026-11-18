// ONE OUTWARD SNAP FOR EVERY RASTER GRID.
//
// A display level's grid, the pyramid's grid counted from a surface's
// content origin and a sub-tree image's grid at its device scale each wrote
// out the same snap. `rectOutwardOnGrid` is that snap once; the formulas
// below are the copies it replaced, kept here as the reference it must
// match to the bit. ↩️The pyramid's, counted from an origin of its own, went
// with the last grid counted so (the-flutter-fx-chain-is-a-second-chain).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/display_resample.dart';

/// `wholeLevelPixelsOutward` as it was: divide by the level's step.
ui.Rect _levelCopy(ui.Rect bounds, int level) {
  final step = (1 << level).toDouble();
  return ui.Rect.fromLTRB(
    (bounds.left / step).floorToDouble() * step,
    (bounds.top / step).floorToDouble() * step,
    (bounds.right / step).ceilToDouble() * step,
    (bounds.bottom / step).ceilToDouble() * step,
  );
}

/// `_planSubtreeRaster`'s destination as it was: multiply by the scale.
ui.Rect _subtreeCopy(ui.Rect bounds, double scale) => ui.Rect.fromLTRB(
  (bounds.left * scale).floorToDouble() / scale,
  (bounds.top * scale).floorToDouble() / scale,
  (bounds.right * scale).ceilToDouble() / scale,
  (bounds.bottom * scale).ceilToDouble() / scale,
);


void main() {
  final random = math.Random(20261001);
  ui.Rect anyRect() {
    final left = (random.nextDouble() - 0.5) * 4000;
    final top = (random.nextDouble() - 0.5) * 4000;
    return ui.Rect.fromLTWH(
      left,
      top,
      random.nextDouble() * 900,
      random.nextDouble() * 900,
    );
  }

  /// [anyRect] on whole pixels — what a tile rect is.
  ui.Rect anyWholeRect() {
    final r = anyRect();
    return ui.Rect.fromLTRB(
      r.left.floorToDouble(),
      r.top.floorToDouble(),
      r.right.ceilToDouble(),
      r.bottom.ceilToDouble(),
    );
  }

  test('a display level snaps where dividing by its step put it', () {
    for (var i = 0; i < 4000; i += 1) {
      final bounds = i.isEven
          ? anyRect()
          : anyWholeRect().translate(0.5, -0.25);
      final level = i % 7;
      expect(
        wholeLevelPixelsOutward(bounds, level),
        _levelCopy(bounds, level),
        reason: '$bounds at level $level',
      );
    }
  });

  test('a sub-tree grid at any device scale snaps where it did', () {
    for (var i = 0; i < 4000; i += 1) {
      final bounds = anyRect();
      final scale = 0.05 + random.nextDouble() * 7.95;
      expect(
        rectOutwardOnGrid(bounds, scale),
        _subtreeCopy(bounds, scale),
        reason: '$bounds at $scale',
      );
    }
  });

  test('a rect already on the grid stays where it is', () {
    const onGrid = ui.Rect.fromLTRB(-8, 16, 24, 40);
    expect(rectOutwardOnGrid(onGrid, 0.25), onGrid);
  });
}
