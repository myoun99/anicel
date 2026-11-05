import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/models/xdts_viewer_sheet.dart';

/// The XDTS Viewer's sheets as its release names and sizes them (I-161), and
/// the one rate it reads.
void main() {
  test('🗣️I-161-Q8: both of the app\'s own sheets lay their ink on the A3 '
      '6-second sheet', () {
    for (final kind in TimesheetSheetKind.values) {
      expect(XdtsViewerSheet.of(kind), XdtsViewerSheet.a3SixSeconds);
    }
  });

  test('each sheet is its paper at the viewer\'s 250 dpi — Ponoc\'s on '
      'JIS B4 like the B4 ones', () {
    expect(XdtsViewerSheet.a3SixSeconds.pixelSize, (width: 2923, height: 4134));
    for (final b4 in [
      XdtsViewerSheet.b4SixSeconds,
      XdtsViewerSheet.b4ThreeSeconds,
      XdtsViewerSheet.ponocSixSeconds,
    ]) {
      expect(b4.pixelSize, (width: 2530, height: 3583));
    }
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
