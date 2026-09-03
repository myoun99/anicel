// A SHEET COLUMN NEITHER CROSSES THE CUT END NOR SPILLS IN UNLESS TOLD SO.
//
// A survivor of the mutation campaign (2026-09-03): the `crossesCutEnd`
// default flipped to true and every column printed a cut-end crossing.
// The constructor defaults are the contract; this pins them.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/timesheet_document.dart';

void main() {
  test('a column defaults to staying inside its cut', () {
    const column = TimesheetColumn(
      kind: TimesheetColumnKind.cel,
      label: 'A',
      cells: [],
    );
    expect(column.crossesCutEnd, isFalse);
    expect(column.spillsInAtStart, isFalse);
  });
}
