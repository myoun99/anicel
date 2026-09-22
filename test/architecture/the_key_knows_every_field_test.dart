import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/selection_affine.dart';

/// 🚨★★★**A CACHE KEY THAT DOES NOT KNOW ABOUT A FIELD IS A CACHE THAT
/// ANSWERS THE WRONG PICTURE.**
///
/// 🗣️유저 2026-09-22: 「중심 십자가를 다른데 두고 **회전시키면** 작동은
/// 하는데 **엄청나게 깜빡이면서 원래위치랑 향하려는 위치 방향으로 서로
/// 순간이동**해」.
///
/// The resample cache spelled [SelectionAffine]'s fields by hand, in the
/// layer. The anchor arrived two days earlier and that string never heard
/// about it, so an affine that differed only in where the turn happens
/// hashed the same as one that did not — and the preview alternated between
/// the cached picture and a fresh one.
///
/// ⛔**THE FIX IS NOT 「I WILL REMEMBER NEXT TIME」**, which is what the hand
/// written list already was. The key moved onto the class, and this reads
/// the class's own declarations to make sure it stayed complete. A field
/// added without a line in `cacheKey` fails here, by name.
void main() {
  /// Every value field [SelectionAffine] declares, read off its source.
  ///
  /// ⚠️SOURCE, because Dart has no mirrors in a Flutter test and the
  /// question is 「what does this class hold」 — which only the declaration
  /// can answer. `final <type> <name>;` at one indent level, which is every
  /// field this class has ever had.
  List<String> declaredFields() {
    final source = File(
      'lib/src/services/selection_affine.dart',
    ).readAsStringSync();
    final body = source.substring(source.indexOf('class SelectionAffine'));
    return RegExp(r'^  final \w+ (\w+);', multiLine: true)
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toList();
  }

  test('cacheKey names every field the affine declares', () {
    final fields = declaredFields();
    expect(
      fields.length,
      greaterThanOrEqualTo(7),
      reason: '⛔전제: the source scan found the fields at all — $fields',
    );

    final source = File(
      'lib/src/services/selection_affine.dart',
    ).readAsStringSync();
    final start = source.indexOf('String get cacheKey');
    expect(start, isNonNegative, reason: 'the key still lives on the class');
    final key = source.substring(start, source.indexOf(';', start));

    final missing = fields.where((f) => !key.contains(f)).toList();
    expect(
      missing,
      isEmpty,
      reason:
          '⛔$missing changes the picture and the cache cannot see it. Add '
          'it to SelectionAffine.cacheKey — a resample computed for another '
          'value will be handed back in its place.',
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
}
