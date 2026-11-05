import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/models/xdts_viewer_sheet.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// A sheet of the XDTS Viewer's is named by its paper and the seconds a
/// page holds (「A3 6초」, I-161-Q8) — the one name the export's picker and
/// the timesheet's paper picker (I-162) both give it.
void main() {
  test('each viewer sheet is its paper and the seconds a page holds', () {
    final korean = AppStrings.of(AppLanguage.ko);
    expect(
      [
        for (final sheet in XdtsViewerSheet.values)
          korean.xdtsViewerSheetName(sheet),
      ],
      ['A3 6초', 'B4 6초', 'B4 3초', 'Ponoc 6초'],
    );
  });

  test('the timesheet names a viewer sheet it prints on as the export '
      'does, in every language', () {
    for (final language in AppLanguage.values) {
      final strings = AppStrings.of(language);
      for (final kind in TimesheetSheetKind.values) {
        if (kind.xdts case final sheet?) {
          expect(
            strings.sheetKindName(kind),
            strings.xdtsViewerSheetName(sheet),
            reason: '$language · $kind',
          );
        }
      }
    }
  });
}
