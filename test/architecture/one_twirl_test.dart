import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨THE TWIRL IS ONE WIDGET — `LayerFoldTwirl` (I-57 ①).
///
/// Four hand-made twirls had drifted apart: the timeline row's lane twirl
/// was an icon button with a tooltip, the storyboard rows' were `InkWell`s
/// in a colour of their own with none, the lane group header's an `InkWell`
/// with a circle of its own. ⛔SO THIS SCANS SOURCE, as the eye's ledger
/// does: two twirls that agree today pass any behaviour test.
///
/// The SHUT glyph is what only a twirl draws — the open one is every
/// dropdown's caret, so it is the shut one that is counted.
void main() {
  test('only the one twirl draws the twirl', () {
    // A word boundary: `Icons.arrow_right_alt` is an instruction's arrow.
    final shut = RegExp(r'Icons\.arrow_right\b');
    final hits = <String>[
      for (final file in dartFilesUnder('lib'))
        if (shut.hasMatch(file.readAsStringSync())) libPath(file),
    ];
    expect(
      hits,
      ['lib/src/ui/timeline/layer_rail_columns.dart'],
      reason:
          'a file that draws the twirl itself is a second twirl. Use '
          '`LayerFoldTwirl`',
    );
  });
}
