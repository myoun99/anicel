import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/models/transition_geometry.dart';
import 'package:anicel/src/services/export/xdts_viewer_ink.dart';

/// The XDTS Viewer's ink folder, as its sources read it (I-161): where the
/// pictures go, what each is called and sized, and the settings beside them.
void main() {
  test('the folder is the file\'s name less .xdts, less a genga or douga '
      'sheet\'s suffix in any case, with _xdts after it', () {
    expect(xdtsInkFolderName('TS301.xdts'), 'TS301_xdts');
    expect(xdtsInkFolderName('c12_genga_ts.xdts'), 'c12_xdts');
    expect(xdtsInkFolderName('c12_DOUGA_TS.xdts'), 'c12_xdts');
  });

  test('a page\'s picture counts from 1 — 0 is a sheet\'s back', () {
    expect(xdtsInkPageFileName(0), '1.png');
    expect(xdtsInkPageFileName(2), '3.png');
  });

  test('each sheet of the app lays its ink on the viewer sheet of its '
      'seconds, at the viewer\'s 250 dpi', () {
    expect(
      XdtsViewerSheet.of(TimesheetSheetKind.threeSeconds),
      XdtsViewerSheet.b4ThreeSeconds,
    );
    expect(
      XdtsViewerSheet.of(TimesheetSheetKind.sixSeconds),
      XdtsViewerSheet.a3SixSeconds,
    );
    expect(XdtsViewerSheet.b4ThreeSeconds.pixelSize, (
      width: 2530,
      height: 3583,
    ));
    expect(XdtsViewerSheet.a3SixSeconds.pixelSize, (width: 2923, height: 4134));
  });

  test('the settings name the template, the cells area and each end\'s '
      'O.L — twice the のりしろ the sheet draws there', () {
    expect(
      xdtsViewerConfig(
        sheet: XdtsViewerSheet.b4ThreeSeconds,
        handles: const CutTransitionHandles(head: 6, tail: 3),
      ),
      '[General]\n'
      'Version=1.3.0\n'
      '\n'
      '[FormatSettings]\n'
      'TemplateName="B4 size, 3 seconds sheet"\n'
      'ExportArea=Cells\n'
      'StartOverlapFrameLength=12\n'
      'EndOverlapFrameLength=6\n',
    );
  });
}
