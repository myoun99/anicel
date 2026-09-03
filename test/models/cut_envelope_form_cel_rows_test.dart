// THE ANALOG CUT ENVELOPE PRINTS EIGHT CEL ROWS, IN THE NAME COLUMN AND IN
// EVERY STAFF COLUMN ALIKE.
//
// A survivor of the mutation campaign (2026-09-03): the row loops'
// `row < count` became `row <= count` and a ninth cel row appeared below
// the form. The count is the form's own (eight rows on the カット袋 the
// preset copies); this pins it through the box ids. The digital form has
// no cel rows.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/envelope/cut_envelope_presets.dart';

void main() {
  // `cel-<row>-name` in the name column, `cel-<row>-<head>` in the staff
  // columns: the row number is what they share.
  final celRow = RegExp(r'^cel-(\d+)-(.+)$');

  test('the analog form prints exactly eight cel rows in every column', () {
    final rowsByColumn = <String, List<int>>{};
    for (final box in CutEnvelopePresets.analog.boxes) {
      final match = celRow.firstMatch(box.id);
      if (match == null) {
        continue;
      }
      rowsByColumn
          .putIfAbsent(match.group(2)!, () => [])
          .add(int.parse(match.group(1)!));
    }
    expect(rowsByColumn, isNotEmpty, reason: 'fixture: cel rows exist');
    for (final entry in rowsByColumn.entries) {
      expect(entry.value..sort(), [0, 1, 2, 3, 4, 5, 6, 7], reason: entry.key);
    }
  });
}
