@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨A CUT'S SHEET IS BUILT IN ONE PLACE.
///
/// The timesheet panel and the export each gathered the sheet's inputs on
/// their own, and the export's gathering stopped short: its sheets printed
/// no O.L and no のりしろ length while the panel printed both
/// (export-sheet-lacks-transitions, 2026-09-30). `cutSheetDocument` is
/// where the inputs are gathered now; this holds the next printer to it.
void main() {
  test('only cutSheetDocument builds a cut\'s sheet document', () {
    final builders = <String>[];
    for (final entity in dartFilesUnder('lib')) {
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('lib/src/models/timesheet_document.dart')) {
        // The factory itself.
        continue;
      }
      if (_built.hasMatch(entity.readAsStringSync())) {
        builders.add(path);
      }
    }
    expect(
      builders,
      [endsWith('lib/src/ui/timesheet/cut_sheet_document.dart')],
      reason:
          'a cut\'s sheet is cutSheetDocument\'s — print through it, so '
          'what the panel shows is what the export writes',
    );
  });
}

final _built = RegExp(r'\bTimesheetDocument\.fromCut\(');
