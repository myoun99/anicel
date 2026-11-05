// THE 3-SECOND SHEET (유저 2026-09-25, 사진 TOEI_3sec; 「se나 캠은 우리
// 규칙대로」, timesheet-sheet-capacity-Q1 「3초 시트로 고정(6초 끔)」,
// timesheet-sheet-kind-scope-Q1 「컷마다 따로」): a cut keeps its own paper;
// the 3-second sheet is one strip of 72 rows across the same paper, its
// cells as wide as the 6-second sheet's and as many as fit — 19 ACTION and
// 19 CELL columns (유저 2026-10-08, F-252: 「셀 칸 하나 가로길이
// 유지한채로 그만큼 칸 더 많이 만들도록」; ↩️12 and 12 printed wider,
// timesheet-3s-columns-Q1); a cut with more cel rows in either block than
// the 6-second strip's eight prints on it whatever it chose.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/sheet_sources.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/models/xdts_sheet_form.dart';
import 'package:anicel/src/models/xdts_viewer_sheet.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// A cut of [cels] ACTION rows and [inbetweens] 動画 ones, the CELL
/// block's (F-406).
Cut _cut({
  required int cels,
  int inbetweens = 0,
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
    for (var index = 0; index < inbetweens; index += 1)
      Layer(
        id: LayerId('inbetween-$index'),
        name: 'IB$index',
        mark: const LayerMark(process: LayerProcess.inbetween),
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

  test('the 3-second sheet is a page of 72 rows in ONE strip, 19 ACTION and '
      '19 CELL columns; SE and CAM keep our own rule', () {
    final three = _sheet(_cut(cels: 3, kind: TimesheetSheetKind.threeSeconds));
    final six = _sheet(_cut(cels: 3));

    expect(three.sheetKind, TimesheetSheetKind.threeSeconds);
    expect((three.pageFrameCount, three.halfFrameCount), (72, 72));
    expect(
      (
        _count(three, TimesheetColumnKind.action),
        _count(three, TimesheetColumnKind.cel),
      ),
      (19, 19),
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

  test('a cut with more cel rows in either block than the 6-second strip '
      'holds prints on the 3-second sheet whatever it chose — past '
      'nineteen that block grows, the other does not', () {
    expect(_sheet(_cut(cels: 8)).sheetKind, TimesheetSheetKind.sixSeconds);
    expect(_sheet(_cut(cels: 9)).sheetKind, TimesheetSheetKind.threeSeconds);
    // F-406: the paper holds its wider block, not the two together.
    expect(
      _sheet(_cut(cels: 8, inbetweens: 8)).sheetKind,
      TimesheetSheetKind.sixSeconds,
    );
    expect(
      _sheet(_cut(cels: 1, inbetweens: 9)).sheetKind,
      TimesheetSheetKind.threeSeconds,
    );
    expect(
      sheetKindFits(TimesheetSheetKind.sixSeconds, celColumns: 9, fps: 24),
      isFalse,
    );
    expect(
      sheetKindFits(TimesheetSheetKind.threeSeconds, celColumns: 9, fps: 24),
      isTrue,
    );

    final crowded = _sheet(_cut(cels: 21));
    expect(_count(crowded, TimesheetColumnKind.action), 21);
    expect(_count(crowded, TimesheetColumnKind.cel), 19);
    final crowdedCells = _sheet(_cut(cels: 2, inbetweens: 21));
    expect(_count(crowdedCells, TimesheetColumnKind.action), 19);
    expect(_count(crowdedCells, TimesheetColumnKind.cel), 21);
  });

  test('🚨the 3-second sheet keeps the 6-second sheet\'s cell width, on '
      'the paper too, and prints as many cells as the two halves span — a '
      'twentieth would not fit', () {
    final six = TimesheetDocumentLayout(document: _sheet(_cut(cels: 3)));
    final three = TimesheetDocumentLayout(
      document: _sheet(_cut(cels: 3, kind: TimesheetSheetKind.threeSeconds)),
    );

    expect(three.halfStrips, [(half: 0, rowCount: 72)]);
    expect(six.halfStrips, hasLength(2));
    for (final kind in TimesheetColumnKind.values) {
      expect(
        three.columnWidthFor(kind),
        six.columnWidthFor(kind),
        reason: '$kind',
      );
    }
    expect(
      three.paperScale,
      six.paperScale,
      reason: 'the same rows on the same paper: a cell is as wide there too',
    );
    const cellPair =
        TimesheetDocumentLayout.actionColumnWidth +
        TimesheetDocumentLayout.celColumnWidth;
    expect(three.formWidth, lessThanOrEqualTo(six.formWidth));
    expect(
      three.formWidth + cellPair,
      greaterThan(six.formWidth),
      reason: 'one more ACTION and CELL pair would run past the halves',
    );
    // Frame 80: the second page's ninth row on the 3-second sheet, the
    // first page's right half on the 6-second one.
    expect(three.positionOfFrame(80), (page: 1, half: 0, row: 8));
    expect(six.positionOfFrame(80), (page: 0, half: 1, row: 8));
  });

  // I-81-Q1 (유저 2026-10-30): the timeline's page view 「그 컷의 X시트
  // 장을 따른다」 — the page the cut's sheet prints, crowded cels included.
  test('the page the timeline counts by is the page the sheet prints', () {
    for (final cut in [
      _cut(cels: 3),
      _cut(cels: 3, kind: TimesheetSheetKind.threeSeconds),
      _cut(cels: 9),
      _cut(cels: 1, inbetweens: 9),
      _cut(cels: 3, kind: TimesheetSheetKind.xdtsA3SixSeconds),
      _cut(cels: 9, kind: TimesheetSheetKind.xdtsB4ThreeSeconds),
    ]) {
      for (final fps in [24, 30]) {
        expect(
          sheetPageFramesOf(cut, fps),
          TimesheetDocument.fromCut(
            cut: cut,
            projectName: 'P',
            fps: fps,
          ).pageFrameCount,
          reason: '${cut.layers.length} rows at $fps fps',
        );
      }
    }
    expect(sheetPageFramesOf(_cut(cels: 3), 24), 144);
    expect(sheetPageFramesOf(_cut(cels: 9), 24), 72);
    expect(
      sheetPageFramesOf(
        _cut(cels: 9, kind: TimesheetSheetKind.xdtsB4ThreeSeconds),
        24,
      ),
      72,
    );
  });

  // I-162 (유저 2026-11-05): 「타임시트 서식에 우리식 3초/6초에 추가로 xdts의
  // 서식같은거 다 타입으로 구현하자 … 서식 바꾸면 xdts의 해당 서식에서
  // 보는거랑 똑같은 화면」.
  group('the XDTS Viewer\'s sheets', () {
    List<String> labels(TimesheetDocument sheet, TimesheetColumnKind kind) => [
      for (final column in sheet.columns)
        if (column.kind == kind) column.label,
    ];

    test('a cut keeps an XDTS sheet it chose, by its own key', () {
      for (final kind in TimesheetSheetKind.values) {
        final metadata = CutMetadata(sheetKind: kind);
        expect(CutMetadata.fromJson(metadata.toJson()), metadata);
      }
      expect(
        [
          for (final kind in TimesheetSheetKind.values)
            if (kind.xdts != null) kind.jsonValue,
        ],
        ['xdts-a3-6s', 'xdts-b4-3s', 'xdts-b4-6s', 'xdts-ponoc-6s'],
      );
    });

    test('every cel row prints in the CELL block, in order, and the ACTION '
        'block is the template\'s, blank — where the viewer prints our '
        'one-file XDTS (저장 2026-11-05)', () {
      final sheet = _sheet(
        _cut(
          cels: 2,
          inbetweens: 1,
          kind: TimesheetSheetKind.xdtsA3SixSeconds,
        ),
      );
      expect(sheet.sheetKind, TimesheetSheetKind.xdtsA3SixSeconds);
      expect(labels(sheet, TimesheetColumnKind.action), List.filled(7, ''));
      expect(labels(sheet, TimesheetColumnKind.cel), [
        'A',
        'B',
        'IB0',
        ...List.filled(5, ''),
      ]);
      expect(_count(sheet, TimesheetColumnKind.se), 1);
      expect(_count(sheet, TimesheetColumnKind.camera), 3);
      expect((sheet.pageFrameCount, sheet.halfFrameCount), (144, 72));
      expect(sheet.xdtsForm!.cellsColumns, 8);
      expect(sheet.books, isEmpty);
    });

    test('more cel rows than the CELL block holds widen it as the viewer '
        'does — no 3-second sheet in its place', () {
      final sheet = _sheet(
        _cut(cels: 6, inbetweens: 4, kind: TimesheetSheetKind.xdtsB4SixSeconds),
      );
      expect(sheet.sheetKind, TimesheetSheetKind.xdtsB4SixSeconds);
      expect(_count(sheet, TimesheetColumnKind.action), 4);
      expect(_count(sheet, TimesheetColumnKind.cel), 10);
      expect(sheet.xdtsForm!.cellsColumns, 10);
    });

    test('the paper a cut\'s ink is laid on is the viewer\'s, widened for '
        'every cel track its XDTS writes — from our own sheet too, whose '
        'blocks part the rows (I-161-Q2 · I-162 ②)', () {
      // Six ACTION rows and four 動画 rows: ten cel tracks in the file.
      final ours = _sheet(_cut(cels: 6, inbetweens: 4));
      expect(ours.xdtsForm, isNull);
      expect(ours.xdtsCelTracks, 10);
      final onA3 = ours.xdtsFormOn(XdtsViewerSheet.a3SixSeconds);
      expect(onA3.cellsColumns, 10);
      expect(
        (onA3.pageWidth, onA3.pageHeight),
        (
          XdtsSheetForm(XdtsViewerSheet.a3SixSeconds, cells: 0).pageWidth +
              2 * onA3.cellsColWidth * 2,
          4134,
        ),
        reason: 'two columns past the template\'s eight, in both bodies',
      );

      // On the viewer's own sheet the ink's paper IS the sheet's.
      final onB4 = _sheet(
        _cut(cels: 6, inbetweens: 4, kind: TimesheetSheetKind.xdtsB4SixSeconds),
      );
      expect(
        onB4.xdtsFormOn(XdtsViewerSheet.b4SixSeconds),
        same(onB4.xdtsForm),
      );
      expect(onB4.xdtsFormOn(XdtsViewerSheet.a3SixSeconds).cellsColumns, 10);
    });

    test('the B4 3-second sheet is one body of 72 rows, its camera block one '
        'column', () {
      final sheet = _sheet(
        _cut(cels: 3, kind: TimesheetSheetKind.xdtsB4ThreeSeconds),
      );
      expect((sheet.pageFrameCount, sheet.halfFrameCount), (72, 72));
      expect(_count(sheet, TimesheetColumnKind.action), 14);
      expect(_count(sheet, TimesheetColumnKind.cel), 14);
      expect(_count(sheet, TimesheetColumnKind.camera), 1);
    });

    test('off the viewer\'s 24 a second a cut that chose one prints on our '
        'sheets (I-162-Q3) — [xdtsViewerReads] is the rate', () {
      for (final kind in TimesheetSheetKind.values) {
        if (kind.xdts == null) {
          continue;
        }
        final at30 = TimesheetDocument.fromCut(
          cut: _cut(cels: 3, kind: kind),
          projectName: 'P',
          fps: 30,
        );
        expect(at30.sheetKind, TimesheetSheetKind.sixSeconds);
        expect(at30.xdtsForm, isNull);
        expect(
          TimesheetDocument.fromCut(
            cut: _cut(cels: 9, kind: kind),
            projectName: 'P',
            fps: 25,
          ).sheetKind,
          TimesheetSheetKind.threeSeconds,
        );
        expect(_sheet(_cut(cels: 3, kind: kind)).sheetKind, kind);
      }
    });
  });
}
