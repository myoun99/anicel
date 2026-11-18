import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/selection_affine.dart';
import 'package:anicel/src/ui/canvas/transform_box.dart';

/// 리셋 is out where it would change nothing (F-583) and lit where it would
/// (I-176) — and what it would change is every value it puts back
/// ([TransformBox.reset]), not only what moves a pixel
/// ([TransformBox.isTransformed]).
void main() {
  final pivot = CanvasPoint(x: 100, y: 50);

  TransformBox box({double sx = 1, double anchorX = 0}) => TransformBox(
    affine: SelectionAffine(pivot: pivot, sx: sx, anchorX: anchorX),
    baseWidth: 40,
    baseHeight: 20,
  );

  test('a box as it opened has nothing to reset', () {
    expect(box().resetChanges, isFalse);
  });

  test('a scale is something to reset', () {
    expect(box(sx: 2).resetChanges, isTrue);
  });

  test('a moved anchor is something to reset, though it moves no pixel', () {
    final moved = box(anchorX: 7);
    expect(moved.isTransformed, isFalse, reason: 'no pixel moves');
    expect(moved.resetChanges, isTrue, reason: 'the reset puts it back');
  });

  test('a bent warp is something to reset', () {
    final bent = box()
      ..warp.corners = [
        CanvasPoint(x: 3, y: 0),
        for (var i = 0; i < 3; i++) CanvasPoint(x: 0, y: 0),
      ];
    expect(bent.resetChanges, isTrue);
  });

  test('after the reset there is nothing left to reset, about the same pivot',
      () {
    final reset = box(sx: 2, anchorX: 7)..reset();
    expect(reset.resetChanges, isFalse);
    expect(reset.affine.pivot, pivot);
  });
}
