import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨LISTENERS HELD BY WHAT THEY SHOW ARE KEPT IN ONE PLACE — `KeyedNotices`
/// (`lib/src/core/keyed_notices.dart`).
///
/// Card `conte-one-eye-repaints-every-track` (2026-11-08): the panel
/// pictures' landings by cut were about to be the third copy written by
/// hand — beside the timeline tiles' landings by row (I-22 ③) and the rows'
/// cel answers by row — so the three became one.
///
/// ⛔A behaviour test cannot hold this: a fourth copy written well tells
/// its painters perfectly. What gives one away is what it has to keep — a
/// map whose values are lists of listeners — so that is what is scanned for.
void main() {
  test('nothing under lib/ keeps a map of listeners but the one law, '
      'outside the ledger — and every ledger entry still keeps its map', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          ..._mapsOfListeners(libPath(file), file.readAsStringSync()),
      ],
      _notAnotherKeyedNotices.keys,
      unledgered:
          'listeners held by what they show are a `KeyedNotices` — hand out '
          'its `of`. A map of listeners that is something else goes in the '
          'ledger, with why',
      paidOff: 'these are gone — take them off the list',
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy(_notAnotherKeyedNotices);
  });

  test('the scan sees a planted map by its field, and not one in a '
      'comment', () {
    const planted = '''
final Map<LayerId, List<VoidCallback>> _rows = {};
final _shown = <String, Set<VoidCallback>>{};
// final Map<int, List<VoidCallback>> _said = {};
final Map<int, List<int>> _counts = {};
''';
    expect(_mapsOfListeners('planted.dart', planted), [
      'planted.dart: _rows',
      'planted.dart: _shown',
    ]);
  });
}

/// Maps of listeners that are not listeners held by what they show — and
/// the law's own.
const _notAnotherKeyedNotices = <String, String>{
  'lib/src/core/keyed_notices.dart: _listeners':
      'the one law — what every painter that shows a key listens through',
};

/// Each map of listeners [source] declares, by `path: field`, comments
/// apart.
List<String> _mapsOfListeners(String path, String source) => [
  for (final line in source.split('\n'))
    if (!line.trimLeft().startsWith('//') && _mapOfListeners.hasMatch(line))
      '$path: ${_field.firstMatch(line)?.group(1)}',
];

final _mapOfListeners = RegExp(
  r'Map<[^;]*,\s*(List|Set)<VoidCallback>>|'
  r'<[^<;]*,\s*(List|Set)<VoidCallback>>\{',
);
final _field = RegExp(r'(\w+)\s*=');
