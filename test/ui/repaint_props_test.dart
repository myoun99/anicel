// A PAINTER NAMES ITS INPUTS ONCE. `props` is the comparison, so a field
// that changes repaints and a rebuilt-but-equal painter does not — and a
// field that must compare by identity says so in `props`, where the one
// `shouldRepaint` below cannot silently deep-compare it instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/repaint_props.dart';
import 'package:anicel/src/ui/timeline/memo_token.dart';

class _ValuePainter extends CustomPainter with RepaintOnProps {
  const _ValuePainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  Object get props => (color, width);

  @override
  void paint(Canvas canvas, Size size) {}
}

class _IdentityPainter extends CustomPainter with RepaintOnProps {
  const _IdentityPainter(this.surface);

  final List<int> surface;

  @override
  Object get props => (ByIdentity(surface),);

  @override
  void paint(Canvas canvas, Size size) {}
}

class _ListPainter extends CustomPainter with RepaintOnProps {
  const _ListPainter(this.corners);

  final List<Offset> corners;

  @override
  Object get props => (ByList(corners),);

  @override
  void paint(Canvas canvas, Size size) {}
}

void main() {
  group('RepaintOnProps', () {
    test('a changed field repaints', () {
      const old = _ValuePainter(color: Color(0xFF000000), width: 1);
      expect(
        const _ValuePainter(
          color: Color(0xFFFFFFFF),
          width: 1,
        ).shouldRepaint(old),
        isTrue,
      );
      expect(
        const _ValuePainter(
          color: Color(0xFF000000),
          width: 2,
        ).shouldRepaint(old),
        isTrue,
      );
    });

    test('an equal but distinct painter does not repaint', () {
      final old = _ValuePainter(color: const Color(0xFF102030), width: 1.5);
      final rebuilt = _ValuePainter(color: const Color(0xFF102030), width: 1.5);
      expect(identical(old, rebuilt), isFalse);
      expect(rebuilt.shouldRepaint(old), isFalse);
    });

    test('an identity-compared field repaints for an equal-by-value one', () {
      // THE LAW `ByIdentity` EXISTS FOR: these two lists are equal element
      // for element, and the painter still repaints, because the field was
      // declared to compare by identity (its `==` would cost more than the
      // repaint it saves).
      final first = <int>[1, 2, 3];
      final second = <int>[1, 2, 3];
      expect(
        _IdentityPainter(first).shouldRepaint(_IdentityPainter(first)),
        isFalse,
      );
      expect(
        _IdentityPainter(second).shouldRepaint(_IdentityPainter(first)),
        isTrue,
      );
    });

    test('a list-compared field ignores a rebuilt list with equal items', () {
      const a = Offset(1, 2);
      const b = Offset(3, 4);
      expect(_ListPainter([a, b]).shouldRepaint(_ListPainter([a, b])), isFalse);
      expect(_ListPainter([a]).shouldRepaint(_ListPainter([a, b])), isTrue);
    });
  });

  group('ByList / ByMap', () {
    test('ByList compares element-wise and in order', () {
      expect(const ByList([1, 2, 3]), const ByList([1, 2, 3]));
      expect(
        const ByList([1, 2, 3]).hashCode,
        const ByList([1, 2, 3]).hashCode,
      );
      expect(const ByList([1, 2, 3]), isNot(const ByList([3, 2, 1])));
      expect(const ByList([1, 2]), isNot(const ByList([1, 2, 3])));
    });

    test('ByMap compares keys and values, not identity', () {
      expect(const ByMap({'a': 1, 'b': 2}), const ByMap({'b': 2, 'a': 1}));
      expect(
        const ByMap({'a': 1, 'b': 2}).hashCode,
        const ByMap({'b': 2, 'a': 1}).hashCode,
      );
      expect(const ByMap({'a': 1}), isNot(const ByMap({'a': 2})));
    });
  });
}
