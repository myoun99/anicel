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
///
/// The XDTS is the same sheet in its digital form, and the export gathered
/// its inputs on its own too: when the sheet's track rows came to count
/// from the cut's own frame 0, that gathering would have had to learn the
/// のりしろ by itself (I-73-ol-sheet-columns). `cutXdtsContent` gathers it
/// beside the printed sheet.
void main() {
  /// The files under `lib` that make [call], less the one defining it.
  List<String> callersOf(RegExp call, {required String definedIn}) => [
    for (final entity in dartFilesUnder('lib'))
      if (!entity.path.replaceAll(r'\', '/').endsWith(definedIn) &&
          call.hasMatch(entity.readAsStringSync()))
        entity.path.replaceAll(r'\', '/'),
  ];

  test('only cutSheetDocument builds a cut\'s sheet document', () {
    expect(
      callersOf(
        RegExp(r'\bTimesheetDocument\.fromCut\('),
        definedIn: 'lib/src/models/timesheet_document.dart',
      ),
      [endsWith('lib/src/ui/timesheet/cut_sheet_document.dart')],
      reason:
          'a cut\'s sheet is cutSheetDocument\'s — print through it, so '
          'what the panel shows is what the export writes',
    );
  });

  test('only cutXdtsContent builds a cut\'s XDTS', () {
    expect(
      callersOf(
        RegExp(r'\bbuildXdtsContent\('),
        definedIn: 'lib/src/services/export/xdts_builder.dart',
      ),
      [endsWith('lib/src/ui/timesheet/cut_sheet_document.dart')],
      reason:
          'a cut\'s XDTS is cutXdtsContent\'s — write it through that, so '
          'it reads the story the printed sheet reads',
    );
  });
}
