import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/models/xdts_viewer_sheet.dart';

/// The XDTS Viewer's sheets as its release names and sizes them (I-161), and
/// the one rate it reads.
void main() {
  test('🗣️I-161-Q8: both of the app\'s own sheets lay their ink on the A3 '
      '6-second sheet, and each of the viewer\'s on itself', () {
    expect(
      TimesheetSheetKind.sixSeconds.viewerSheet,
      XdtsViewerSheet.a3SixSeconds,
    );
    expect(
      TimesheetSheetKind.threeSeconds.viewerSheet,
      XdtsViewerSheet.a3SixSeconds,
    );
    for (final kind in TimesheetSheetKind.values) {
      if (kind.xdts case final sheet?) {
        expect(kind.viewerSheet, sheet);
      }
    }
  });

  test('every sheet of the viewer\'s is one the timesheet prints on '
      '(I-162) — one list, not two', () {
    expect({
      for (final kind in TimesheetSheetKind.values) ?kind.xdts,
    }, XdtsViewerSheet.values.toSet());
  });

  test('the labels are the templates\' own, as config.ini names them', () {
    expect(XdtsViewerSheet.values.map((sheet) => sheet.label), [
      'A3 size, 6 seconds sheet',
      'B4 size, 6 seconds sheet',
      'B4 size, 3 seconds sheet',
      'Ponoc 6 seconds sheet',
    ]);
  });

  test('a stored sheet reads back; none, or one this build lacks, is none', () {
    for (final sheet in XdtsViewerSheet.values) {
      expect(XdtsViewerSheet.fromJson(sheet.jsonValue), sheet);
    }
    expect(XdtsViewerSheet.fromJson(null), isNull);
    expect(XdtsViewerSheet.fromJson('a4-6s'), isNull);
  });

  test('🗣️I-161-Q7: the viewer reads a project counting 24 frames a second '
      '— 23.976 among them — and no other', () {
    expect(xdtsViewerReads(ProjectFrameRate.fps24.countingBase), isTrue);
    expect(
      xdtsViewerReads(const ProjectFrameRate.ntsc(24).countingBase),
      isTrue,
    );
    for (final rate in const [
      ProjectFrameRate.integer(12),
      ProjectFrameRate.integer(25),
      ProjectFrameRate.ntsc(30),
      ProjectFrameRate.integer(48),
    ]) {
      expect(xdtsViewerReads(rate.countingBase), isFalse);
    }
  });
}
