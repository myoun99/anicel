// A MEMO TOKEN SAYS, PER FIELD, HOW IT COMPARES — by identity, by set
// contents — and the record then compares itself. No field can be left
// out of the comparison, because there is no hand-written comparison.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/timeline/memo_token.dart';

void main() {
  group('ByIdentity', () {
    test('the same instance matches; an equal-by-value one does not', () {
      final a = [1, 2];
      final b = [1, 2];
      expect(a, b, reason: 'the lists compare equal by value');
      expect(ByIdentity(a), ByIdentity(a));
      expect(ByIdentity(a), isNot(ByIdentity(b)));
      expect(ByIdentity(a).hashCode, ByIdentity(a).hashCode);
    });

    test('null wraps, and matches only null', () {
      expect(const ByIdentity<Object?>(null), const ByIdentity<Object?>(null));
      final something = <int>[];
      expect(
        ByIdentity<Object?>(something),
        isNot(const ByIdentity<Object?>(null)),
      );
    });

    test('a record of tokens compares field-wise through them', () {
      final shared = ValueNotifier<int>(0);
      addTearDown(shared.dispose);
      final a = (layer: ByIdentity(shared), active: true);
      final b = (layer: ByIdentity(shared), active: true);
      final c = (layer: ByIdentity(shared), active: false);
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('BySet', () {
    test('a rebuilt set with the same members matches', () {
      expect(const BySet({1, 2, 3}), const BySet({3, 2, 1}));
      expect(const BySet({1, 2, 3}).hashCode, const BySet({3, 2, 1}).hashCode);
      expect(const BySet({1, 2}), isNot(const BySet({1, 2, 3})));
    });
  });
}
