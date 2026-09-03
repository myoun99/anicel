// TWO RESOLVED EFFECTS ARE THE SAME EFFECT WHEN KIND AND VALUES MATCH.
//
// The caches compare resolved effects to decide whether a composite can be
// reused. The mutation campaign (2026-09-03) turned the kind comparison in
// `==` into `!=` — a blur equalled a hue shift with the same numbers — and
// nothing noticed. These pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/layer_effect.dart';

void main() {
  test('same kind and values: equal, and one hash', () {
    final a = ResolvedLayerEffect(kind: EffectKind.blur, values: [1, 2]);
    final b = ResolvedLayerEffect(kind: EffectKind.blur, values: [1, 2]);
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
  });

  test('a different kind with the same values is a different effect', () {
    final blur = ResolvedLayerEffect(kind: EffectKind.blur, values: [1, 2]);
    final hue = ResolvedLayerEffect(
      kind: EffectKind.hueSaturation,
      values: [1, 2],
    );
    expect(blur, isNot(equals(hue)));
  });

  test('the same kind with different values is a different effect', () {
    final a = ResolvedLayerEffect(kind: EffectKind.blur, values: [1, 2]);
    final b = ResolvedLayerEffect(kind: EffectKind.blur, values: [1, 3]);
    expect(a, isNot(equals(b)));
  });
}
