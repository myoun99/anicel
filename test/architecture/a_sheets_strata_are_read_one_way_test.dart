import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// THE STRATA A SHEET'S PRINT IS HANDED ARE READ ONE WAY: `drawsSheetLayer`
/// (`lib/src/models/sheet_paint_layer.dart`) — those it names, or every one
/// where it names none.
///
/// Two painters' `_draws`, the conte page's ink and its marks and the sheet
/// printer's marks each spelled it for themselves, and a sheet's Photoshop
/// rows (I-117) were about to spell it again. A behaviour test cannot see
/// the next copy: one that agrees passes every test the one reading does.
///
/// So the scan reads every file that names the strata for a set of them
/// read by hand.
void main() {
  const home = 'lib/src/models/sheet_paint_layer.dart';
  final byHand = RegExp(
    r'\?\.contains\([^)]*\)\s*\?\?\s*true'
    r'|==\s*null\s*\|\|\s*\w+!\.contains\(',
  );
  final sources = {
    for (final file in dartFilesUnder('lib'))
      libPath(file): file.readAsStringSync(),
  };

  test('no file but the strata\'s own reads a set of them by hand', () {
    expect(
      [
        for (final MapEntry(key: path, value: source) in sources.entries)
          if (path != home &&
              source.contains('SheetPaintLayer') &&
              byHand.hasMatch(source))
            path,
      ],
      isEmpty,
      reason: 'a print\'s strata are read `drawsSheetLayer(layers, layer)`',
    );
  });

  test('the scan sees what it guards: the strata\'s own file reads them so',
      () {
    final source = sources[home];
    expect(source, isNotNull, reason: '$home is gone — follow it here');
    expect(byHand.hasMatch(source!), isTrue);
  });
}
