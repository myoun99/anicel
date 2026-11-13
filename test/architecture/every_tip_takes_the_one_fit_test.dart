import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨EVERY IMPORTED TIP TAKES THE ONE FIT (b1868baed, 2026-09-07: 「Every
/// coverage source ends its journey to a tip mask in one place」;
/// `brushTipMaskFromCoverage`): the image's, the cut piece's, the SUT's,
/// the pattern's — and the ABR's sampled tip, which squared its pixels as
/// they came and was left off the list as that law was written (card
/// an-abr-sampled-tip-skips-the-one-fit-every-tip-takes, 2026-11-13: a
/// 2500px tip stayed 2500²). ⛔A behaviour test proves the importers it
/// knows of; this scan proves no other squares a tip of its own.
void main() {
  const home = 'lib/src/services/brush_tip_coverage.dart';
  final squares = RegExp(r'\bBrushTipMask\.square\(');

  List<String> callers() => [
    for (final file in dartFilesUnder('lib/src'))
      if (file
          .readAsLinesSync()
          .any((line) =>
              !line.trimLeft().startsWith('//') && squares.hasMatch(line)))
        libPath(file),
  ];

  test('a tip mask is squared by the one fit alone', () {
    expect(
      callers().where((path) => !path.endsWith('models/brush_tip_mask.dart')),
      [home],
      reason: 'a tip squared elsewhere skips the fit to the tip size — '
          'make it through brushTipMaskFromCoverage',
    );
  });
}
