import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨A MODEL FREEZES A COLLECTION THROUGH ONE HELPER — `frozenList`,
/// `frozenSet` and `frozenMap` (`lib/src/core/frozen_collections.dart`).
///
/// 🔬Card a-track-copy-wraps-its-unchanged-lists-anew (11-11): 33 model
/// files froze with `List.unmodifiable` and its kin, which copy a list a
/// model froze itself as readily as one from outside — so every copy gave
/// each collection it did not change a new identity, and whatever kept
/// work by that identity did the work again. The helper hands its own back.
///
/// ⛔THIS SCANS SOURCE: a model that freezes by hand passes every
/// behaviour test there is, until something keeps work by its identity.
void main() {
  test('🚨no model freezes a collection by hand, outside the ledger', () {
    final found = <String, int>{};
    final hits = <String, List<int>>{};
    for (final file in dartFilesUnder('lib/src/models')) {
      final path = libPath(file);
      final lines = _freezesIn(file.readAsStringSync());
      if (lines.isNotEmpty) {
        found[path] = lines.length;
        hits[path] = lines;
      }
    }
    expectCountsMatchLedger(
      found,
      {for (final MapEntry(:key, :value) in _ledger.entries) key: value.count},
      grew:
          'freeze through `frozenList` · `frozenSet` · `frozenMap` '
          '(`frozenMapOrSame` where the constructor builds the map from the '
          'one it was given) — `List.unmodifiable` copies a list a model '
          'froze itself, and a copy of the model then hands back a new one',
      paidOff: 'these freeze through the helper now — take the line out',
      hits: hits,
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy({
      for (final MapEntry(:key, :value) in _ledger.entries) key: value.why,
    });
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
}

/// The lines of [source] that freeze by hand, counted from 1.
List<int> _freezesIn(String source) => [
  for (final (index, line) in codeOfLines(source).split('\n').indexed)
    if (_freeze.hasMatch(line)) index + 1,
];

final _freeze = RegExp(r'\b(List|Set|Map)(<[^()=;]*>)?\.unmodifiable\(');

const _ledger = <String, ({int count, String why})>{
  'lib/src/models/composite_tree.dart': (
    count: 19,
    why:
        'on the transition list (관제 11-11: bitmap_tile · brush_stamp_image '
        '· composite_tree · layer_blend_mode) — another lane is moving it, '
        'and nothing here touches it until that lane lands.',
  ),
};
