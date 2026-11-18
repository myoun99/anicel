import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart' show codeOfLines;

/// 🚨A MODEL FREEZES A COLLECTION THROUGH ONE HELPER — `frozenList`,
/// `frozenSet` and `frozenMap` (`lib/src/core/frozen_collections.dart`).
///
/// 🔬Card a-track-copy-wraps-its-unchanged-lists-anew (11-11): 34 model
/// files froze with `List.unmodifiable` and its kin, which copy a list a
/// model froze itself as readily as one from outside — so every copy gave
/// each collection it did not change a new identity, and whatever kept
/// work by that identity did the work again. The helper hands its own back.
///
/// ⛔THIS SCANS SOURCE: a model that freezes by hand passes every
/// behaviour test there is, until something keeps work by its identity.
void main() {
  test('🚨no model freezes a collection by hand', () {
    expect(
      {
        for (final file in dartFilesUnder('lib/src/models'))
          if (_freezesIn(file.readAsStringSync()) case final lines
              when lines.isNotEmpty)
            libPath(file): lines,
      },
      isEmpty,
      reason:
          'freeze through `frozenList` · `frozenSet` · `frozenMap` '
          '(`frozenMapOrSame` where the constructor builds the map from the '
          'one it was given) — `List.unmodifiable` copies a list a model '
          'froze itself, and a copy of the model then hands back a new one',
    );
  });

  test('the scan sees a planted freeze, typed or not, and not one in a '
      'comment', () {
    const planted = '''
final a = List.unmodifiable(items);
// ↩️It was Set.unmodifiable(items).
final b = Map<int, String>.unmodifiable(entries);
final c = frozenList(items);
''';
    expect(_freezesIn(planted), [1, 3]);
  });

  // 🔬Card a-thawed-cel-is-adopted-on-the-ui-thread (11-16): a mark kept in
  // an Expando — one entry for every frozen collection alive, the table
  // walked whole whenever it grew — held the UI 33.7 ms as a thawed cel's
  // surface froze its tiles. A mark in a table and a mark in the class
  // freeze alike: no behaviour tells them apart, so the source does.
  test('🚨the mark is the collection\'s class, not an entry in a table', () {
    final helpers = codeOfLines(
      File('lib/src/core/frozen_collections.dart').readAsStringSync(),
    );
    expect(helpers, isNot(contains('Expando')));
    expect(helpers, contains('extends UnmodifiableListView<E>'));
  });
}

/// The lines of [source] that freeze by hand, counted from 1.
List<int> _freezesIn(String source) => [
  for (final (index, line) in codeOfLines(source).split('\n').indexed)
    if (_freeze.hasMatch(line)) index + 1,
];

final _freeze = RegExp(r'\b(List|Set|Map)(<[^()=;]*>)?\.unmodifiable\(');
