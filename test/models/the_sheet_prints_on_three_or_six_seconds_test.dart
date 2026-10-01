// THE 3-SECOND SHEET (유저 2026-09-25, 사진 TOEI_3sec; timesheet-3s-columns-Q1
// 「사진대로 ACTION 12 · CELL 12」 + 「se나 캠은 우리 규칙대로」,
// timesheet-sheet-capacity-Q1 「3초 시트로 고정(6초 끔)」,
// timesheet-sheet-kind-scope-Q1 「컷마다 따로」): a cut keeps its own paper;
// the 3-second sheet is one strip of 72 rows across the same paper, 12
// ACTION and 12 CELL columns printed wider; a cut with more cel layers than
// the 6-second strip's eight prints on it whatever it chose.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

Cut _cut({
  required int cels,
  TimesheetSheetKind kind = TimesheetSheetKind.sixSeconds,
}) => Cut(
  id: const CutId('cut'),
  name: '1',
  duration: 24,
  canvasSize: const CanvasSize(width: 1920, height: 1080),
  metadata: CutMetadata(sheetKind: kind),
  layers: [
    for (var index = 0; index < cels; index += 1)
      Layer(
        id: LayerId('cel-$index'),
        name: String.fromCharCode(65 + index),
        frames: const [],
      ),
  ],
);

TimesheetDocument _sheet(Cut cut) =>
    TimesheetDocument.fromCut(cut: cut, projectName: 'P', fps: 24);

int _count(TimesheetDocument document, TimesheetColumnKind kind) =>
    document.columns.where((column) => column.kind == kind).length;

void main() {
  test('a cut keeps its own paper — the 6-second sheet unless it says '
      'otherwise, written to the file only when it does', () {
    expect(const CutMetadata().sheetKind, TimesheetSheetKind.sixSeconds);
    expect(const CutMetadata().toJson().containsKey('sheetKind'), isFalse);

    const three = CutMetadata(sheetKind: TimesheetSheetKind.threeSeconds);
    expect(three.toJson()['sheetKind'], '3s');
    expect(CutMetadata.fromJson(three.toJson()), three);
    expect(three, isNot(const CutMetadata()));
  });

  test('the 3-second sheet is a page of 72 rows in ONE strip, 12 ACTION and '
      '12 CELL columns; SE and CAM keep our own rule', () {
    final three = _sheet(_cut(cels: 3, kind: TimesheetSheetKind.threeSeconds));
    final six = _sheet(_cut(cels: 3));

    expect(three.sheetKind, TimesheetSheetKind.threeSeconds);
    expect((three.pageFrameCount, three.halfFrameCount), (72, 72));
    expect(
      (
        _count(three, TimesheetColumnKind.action),
        _count(three, TimesheetColumnKind.cel),
      ),
      (12, 12),
    );
    expect(six.sheetKind, TimesheetSheetKind.sixSeconds);
    expect((six.pageFrameCount, six.halfFrameCount), (144, 72));
    expect(
      (
        _count(six, TimesheetColumnKind.action),
        _count(six, TimesheetColumnKind.cel),
      ),
      (8, 8),
    );
    for (final kind in [TimesheetColumnKind.se, TimesheetColumnKind.camera]) {
      expect(_count(three, kind), _count(six, kind), reason: '$kind');
    }
  });

  test('a cut with more cel layers than the 6-second strip holds prints on '
      'the 3-second sheet whatever it chose — past twelve its ACTION block '
      'grows, its CELL block does not', () {
    expect(_sheet(_cut(cels: 8)).sheetKind, TimesheetSheetKind.sixSeconds);
    expect(_sheet(_cut(cels: 9)).sheetKind, TimesheetSheetKind.threeSeconds);
    expect(
      sheetKindFits(TimesheetSheetKind.sixSeconds, celColumns: 9),
      isFalse,
    );
    expect(
      sheetKindFits(TimesheetSheetKind.threeSeconds, celColumns: 9),
      isTrue,
    );

    final crowded = _sheet(_cut(cels: 14));
    expect(_count(crowded, TimesheetColumnKind.action), 14);
    expect(_count(crowded, TimesheetColumnKind.cel), 12);
  });

  test('the 3-second sheet lays its one strip across the SAME paper, its '
      'columns about half again as wide — what the two halves and the gap '
      'between them span', () {
    final six = TimesheetDocumentLayout(document: _sheet(_cut(cels: 3)));
    final three = TimesheetDocumentLayout(
      document: _sheet(_cut(cels: 3, kind: TimesheetSheetKind.threeSeconds)),
    );

    expect(three.halfStrips, [(half: 0, rowCount: 72)]);
    expect(six.halfStrips, hasLength(2));
    expect(three.paperWidth, closeTo(six.paperWidth, 1e-9));
    const halves = 2 * (24 + 496) + 24;
    expect(
      three.columnWidthFor(TimesheetColumnKind.action) /
          six.columnWidthFor(TimesheetColumnKind.action),
      closeTo((halves - 24) / 688, 1e-9),
    );
    // Frame 80: the second page's ninth row on the 3-second sheet, the
    // first page's right half on the 6-second one.
    expect(three.positionOfFrame(80), (page: 1, half: 0, row: 8));
    expect(six.positionOfFrame(80), (page: 0, half: 1, row: 8));
  });
}
