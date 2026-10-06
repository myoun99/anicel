import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/transform_values.dart';
import 'package:anicel/src/services/selection_affine.dart';

/// 🚨★★★**A LIST OF A TRANSFORM'S VALUES THAT DOES NOT KNOW ABOUT ONE OF
/// THEM ANSWERS FOR A DIFFERENT TRANSFORM.**
///
/// 🗣️유저 2026-09-22: 「중심 십자가를 다른데 두고 **회전시키면** 작동은
/// 하는데 **엄청나게 깜빡이면서 원래위치랑 향하려는 위치 방향으로 서로
/// 순간이동**해」.
///
/// The resample cache spelled the affine's fields by hand, in the layer.
/// The anchor arrived two days earlier and that string never heard about
/// it, so an affine that differed only in where the turn happens hashed the
/// same as one that did not — and the preview alternated between the cached
/// picture and a fresh one.
///
/// 🗣️And 유저 2026-10-03 (F-265), of the same disease in another list:
/// 「변형으로 좌우반전하고, 다음프레임에서 기록된 내역대로 하려고 엔터누르니
/// 좌우반전이아니라 좌우/상하반전이 됨」 — the record 재현 replays spelled
/// four of the values, with ONE scale.
///
/// ⛔**THE FIX IS NOT 「I WILL REMEMBER NEXT TIME」**, which is what a hand
/// written list already is. The values are one object now
/// ([TransformValues]) and every door carries it whole; what is left to
/// spell by hand is spelled on the two classes themselves, and this reads
/// their own declarations to make sure each list stayed complete. A value
/// added without a line in one of them fails here, by name.
void main() {
  final valuesSource = File(
    'lib/src/models/transform_values.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final affineSource = File(
    'lib/src/services/selection_affine.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  /// Every field a class declares, read off its source.
  ///
  /// ⚠️SOURCE, because Dart has no mirrors in a Flutter test and the
  /// question is 「what does this class hold」 — which only the declaration
  /// can answer. `final <type> <name>;` at one indent level, which is every
  /// field either class has ever had.
  List<String> declaredFields(String source, String className) {
    final body = source.substring(source.indexOf('class $className'));
    return RegExp(
      r'^  final \w+ (\w+);',
      multiLine: true,
    ).allMatches(body).map((m) => m.group(1)!).toList();
  }

  /// One member's text: from [opener] to the first [closer] after it.
  String member(String source, String opener, String closer) {
    final start = source.indexOf(opener);
    expect(start, isNonNegative, reason: '⛔전제: `$opener` is still there');
    return source.substring(start, source.indexOf(closer, start));
  }

  List<String> missingFrom(String text, List<String> names) => [
    for (final name in names)
      if (!RegExp('\\b$name\\b').hasMatch(text)) name,
  ];

  final values = declaredFields(valuesSource, 'TransformValues');

  test('⛔전제: the scan finds the values at all', () {
    expect(values.length, greaterThanOrEqualTo(7), reason: '$values');
  });

  // Each of these is a list of the values written out by hand. ⚠️Not
  // `isIdentity` — it leaves the anchor out on purpose (the cross moved
  // alone changes no pixel).
  const lists = <String, (String opener, String closer)>{
    'cacheKey': ('String get cacheKey', ';'),
    'copyWith': ('TransformValues copyWith({', '\n  }\n'),
    'operator ==': ('bool operator ==', ';'),
    'hashCode': ('int get hashCode', ';'),
    'toString': ('String toString()', ';'),
  };

  for (final list in lists.entries) {
    test('TransformValues.${list.key} names every value', () {
      expect(
        missingFrom(member(valuesSource, list.value.$1, list.value.$2), values),
        isEmpty,
        reason:
            '⛔a value TransformValues.${list.key} does not know about: two '
            'transforms that differ in it would be answered as one.',
      );
    });
  }

  test('the affine\'s cacheKey names the place and the values', () {
    final fields = declaredFields(affineSource, 'SelectionAffine');
    expect(fields, containsAll(<String>['pivot', 'values']));
    expect(
      missingFrom(member(affineSource, 'String get cacheKey', ';'), fields),
      isEmpty,
      reason:
          '⛔a field changes the picture and the cache cannot see it. Add it '
          'to SelectionAffine.cacheKey — a resample computed for another '
          'value will be handed back in its place.',
    );
  });

  test('the affine\'s long constructor and its copyWith can say every value',
      () {
    expect(
      missingFrom(
        member(affineSource, '  SelectionAffine({', '  /// [values] aimed'),
        values,
      ),
      isEmpty,
    );
    expect(
      missingFrom(
        member(affineSource, 'SelectionAffine copyWith({', '\n  );\n'),
        values,
      ),
      isEmpty,
    );
  });

  /// The behaviour the ratchet stands in for, stated once so the scan is
  /// not the only thing saying it.
  test('🚨two affines that differ ONLY in the anchor are different keys', () {
    final pivot = CanvasPoint(x: 100, y: 50);
    final turnedAtTheCentre = SelectionAffine(
      pivot: pivot,
      rotationDegrees: 30,
    );
    final turnedElsewhere = SelectionAffine(
      pivot: pivot,
      rotationDegrees: 30,
      anchorX: 30,
      anchorY: -40,
    );

    expect(
      turnedAtTheCentre.apply(pivot).x,
      isNot(closeTo(turnedElsewhere.apply(pivot).x, 1e-9)),
      reason: '⛔전제: they really do draw different pictures',
    );
    expect(turnedAtTheCentre.cacheKey, isNot(turnedElsewhere.cacheKey));
  });

  test('🚨two sets of values that differ in ONE value are two sets — to '
      'equality, to the hash and to the key', () {
    const base = TransformValues(
      sx: 2,
      sy: 3,
      rotationDegrees: 20,
      tx: 5,
      ty: 7,
      anchorX: 11,
      anchorY: 13,
    );
    final others = [
      base.copyWith(sx: -2),
      base.copyWith(sy: -3),
      base.copyWith(rotationDegrees: 21),
      base.copyWith(tx: 6),
      base.copyWith(ty: 8),
      base.copyWith(anchorX: 12),
      base.copyWith(anchorY: 14),
    ];
    expect(base.copyWith(), base, reason: '⛔전제: equal when nothing differs');
    expect(base.copyWith().hashCode, base.hashCode);
    for (final other in others) {
      expect(other, isNot(base), reason: '$other');
      expect(other.cacheKey, isNot(base.cacheKey), reason: '$other');
      expect('$other', isNot('$base'));
    }
    expect(
      others.map((other) => other.hashCode).toSet().length,
      others.length,
      reason: 'and no two of them hash alike',
    );
  });

  test('an affine hands its values back whole, and takes others whole', () {
    final pivot = CanvasPoint(x: 100, y: 50);
    const values = TransformValues(
      sx: -1,
      sy: 1.5,
      rotationDegrees: 20,
      tx: 5,
      ty: 7,
      anchorX: 11,
      anchorY: 13,
    );
    final affine = SelectionAffine.of(pivot, values);
    expect(affine.values, same(values));
    expect(
      SelectionAffine(pivot: pivot).withValues(values).values,
      same(values),
    );
    expect(
      SelectionAffine(
        pivot: pivot,
        sx: -1,
        sy: 1.5,
        rotationDegrees: 20,
        tx: 5,
        ty: 7,
        anchorX: 11,
        anchorY: 13,
      ).values,
      values,
      reason: 'the long way round says the same thing',
    );
    expect(affine.copyWith(ty: 9).values, values.copyWith(ty: 9));
    expect(affine.copyWith(ty: 9).pivot, same(pivot));
  });
}
