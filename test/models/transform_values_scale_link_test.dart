import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/transform_values.dart';

/// 🗣️F-256-Q2 (유저 2026-10-06): 「연동 스위치(AE 의 사슬) — 켜면 한 칸을
/// 바꿀 때 다른 칸도 같은 비율로」, of the option that read 「지금의 가로 ·
/// 세로 비율과 반전은 지킨다」 — and 「이걸 트랜스폼등 fx에도 적용하고싶음」.
///
/// The rule lives on the values so that every place that links two scales
/// asks the same one (`TransformValues.withScaleX` · `withScaleY`).
void main() {
  // Every value differs from every other, and from the identity: a write
  // that restated a neighbour's would move something.
  const box = TransformValues(
    sx: 2,
    sy: -1,
    rotationDegrees: 20,
    tx: 6,
    ty: -9,
    anchorX: 4,
    anchorY: -3,
  );

  test('unlinked, a scale set along one axis is that axis and nothing else',
      () {
    expect(box.withScaleX(3, linked: false), box.copyWith(sx: 3));
    expect(box.withScaleY(0.5, linked: false), box.copyWith(sy: 0.5));
  });

  test('🚨linked, the other axis is carried by the same ratio — and keeps '
      'its own sign', () {
    expect(
      box.withScaleX(3, linked: true),
      box.copyWith(sx: 3, sy: -1.5),
      reason: '200% → 300% is half again; the mirrored 100% is a mirrored '
          '150%',
    );
    expect(
      box.withScaleY(-4, linked: true),
      box.copyWith(sx: 8, sy: -4),
      reason: 'four times, from the other row',
    );
  });

  test('🚨linked, a MINUS mirrors the axis it was typed into and no other',
      () {
    expect(box.withScaleX(-2, linked: true), box.copyWith(sx: -2));
    expect(
      box.withScaleY(1, linked: true),
      box.copyWith(sy: 1),
      reason: 'the mirror taken back off: the other axis is where it was',
    );
    expect(
      box.withScaleX(-3, linked: true),
      box.copyWith(sx: -3, sy: -1.5),
      reason: 'mirrored AND half again: the size carries, the sign does not',
    );
  });

  test('a scale standing on zero has no ratio to carry', () {
    const flat = TransformValues(sx: 0, sy: 0.5);

    expect(flat.withScaleX(2, linked: true), flat.copyWith(sx: 2));
  });
}
