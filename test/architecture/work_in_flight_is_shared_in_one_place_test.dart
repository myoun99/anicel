import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨WORK ASKED FOR BY KEY WHILE IT RUNS IS SHARED IN ONE PLACE — `InFlight`
/// (`lib/src/core/in_flight.dart`).
///
/// Card `cel-thaw-holds-the-ui-thread` (2026-10-15): a cel's thaw ahead was
/// about to be the fifth copy written by hand — beside a movie frame's
/// decode, a face's files, a picture's open and a bake — and it fell into
/// the trap the movie decode had met a month before: an arrow handed to
/// `whenComplete` that waits on its own future for ever.
///
/// ⛔A behaviour test cannot hold this: a sixth copy written well shares its
/// runs perfectly. What gives one away is what it has to keep — a map whose
/// values are futures — so that is what is scanned for.
void main() {
  test('nothing under lib/ keeps a map of futures but the one law, outside '
      'the ledger — and every ledger entry still keeps its map', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          ..._mapsOfFutures(libPath(file), file.readAsStringSync()),
      ],
      _notAnotherInFlight.keys,
      unledgered:
          'work shared by key while it runs is an `InFlight` — `join` it. '
          'A map of futures that is something else goes in the ledger, with '
          'why',
      paidOff: 'these are gone — take them off the list',
    );
  });

  test('every ledger entry says why', () {
    expectEveryEntrySaysWhy(_notAnotherInFlight);
  });

  test('the scan sees a planted map by its field, and not one in a '
      'comment', () {
    const planted = '''
final Map<int, Future<void>> _opening = {};
final _decoding = <String, Future<int?>>{};
// final Map<int, Future<void>> _said = {};
final Map<int, int> _counts = {};
''';
    expect(_mapsOfFutures('planted.dart', planted), [
      'planted.dart: _opening',
      'planted.dart: _decoding',
    ]);
  });
}

/// Maps of futures that are not work shared in flight — and the law's own.
const _notAnotherInFlight = <String, String>{
  'lib/src/core/in_flight.dart: _runs': 'the one law — what every other joins',
  'lib/src/ui/session/movie_cel_hydrator.dart: _opened':
      'no run in flight: a movie\'s open is KEPT, a failed one with it, so a '
      'movie that would not open is not asked again at every frame',
  'lib/src/ui/media/shown_rasters.dart: _wanted':
      'no run in flight: what a surface asked for while it painted, NOT '
      'started — the renders it would start, of which one goes out when '
      'none is (ShownRasters.want, the 09-28 tablet crash); the one out is '
      'in _renders, and asked for again it is not started twice',
  'lib/src/ui/brush/drawing_cursor.dart: _lookCursorNames':
      'no run in flight: a look\'s cursor at a size is KEPT, as Windows keeps '
      'every cursor it is handed for the life of the window, and a refused '
      'one with it, so a look it would not take is not handed again at every '
      'hover (I-54, F-441)',
};

/// Each map of futures [source] declares, by `path: field`, comments apart.
List<String> _mapsOfFutures(String path, String source) => [
  for (final line in source.split('\n'))
    if (!line.trimLeft().startsWith('//') && _mapOfFutures.hasMatch(line))
      '$path: ${_field.firstMatch(line)?.group(1)}',
];

final _mapOfFutures = RegExp(r'Map<[^;]*,\s*Future<|<[^<;]*,\s*Future<.*>\{');
final _field = RegExp(r'(\w+)\s*=');
