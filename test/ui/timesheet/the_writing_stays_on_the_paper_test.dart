// 🗣️F-252 (유저 2026-10-01): 「잉크는 용지에 귀속됨. 더이상 칸에 귀속되지않음.
// 내용물이 뭐가 바뀌던 독립적. 콘티넌스뷰로 바뀌던 컷길이가 바뀌던」 — and
// F-252-Q1 (10-08): 「잔재 싹 삭제」.
//
// THE WRITING STAYS ON THE PAPER: a page's ink is that page's paper, pixel
// for pixel, whatever the sheet prints on it — the 3- or the 6-second
// sheet, a longer or a shorter cut. ↩️It stayed on its CELLS
// (timesheet-sheet-kind-ink-Q1, 09-27: 「프레임을 따라 옮겨 붙인다」), on a
// frame-anchored plane of its own; F-252 reversed that.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/models/timesheet_sheet_kind.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';

const _cutId = CutId('cut');

TimesheetDocumentLayout _layout(
  TimesheetSheetKind kind, {
  required int duration,
}) => TimesheetDocumentLayout(
  document: TimesheetDocument.fromCut(
    cut: Cut(
      id: _cutId,
      name: '1',
      duration: duration,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      metadata: CutMetadata(sheetKind: kind),
      layers: const [],
    ),
    projectName: 'P',
    fps: 24,
  ),
);

void main() {
  test('a page\'s window is the whole paper on either sheet and at any '
      'length — the same surface, the same pixel under the same spot', () {
    for (final kind in TimesheetSheetKind.values) {
      for (final duration in [24, 200]) {
        final layout = _layout(kind, duration: duration);
        final paper = layout.paperPixelSize;
        final windows = timesheetInkWindows(layout: layout, cutId: _cutId);
        expect(windows, hasLength(layout.pageIndexes.length));
        for (final page in layout.pageIndexes) {
          final window = windows[page];
          final rect = layout.pageRect(page);
          final what = '$kind, $duration frames, page $page';
          expect(window.key, timesheetInkPageKey(_cutId, page), reason: what);
          expect(window.documentRect, rect, reason: what);
          final middle = window.placement.pixelOf(rect.center);
          expect(middle.dx, closeTo(paper.width / 2, 1e-6), reason: what);
          expect(middle.dy, closeTo(paper.height / 2, 1e-6), reason: what);
          final corner = window.placement.pixelOf(rect.bottomRight);
          expect(corner.dx, closeTo(paper.width * 1.0, 1e-6), reason: what);
          expect(corner.dy, closeTo(paper.height * 1.0, 1e-6), reason: what);
        }
      }
    }
  });

  test('a stroke stays put through a sheet switch and a cut that shrinks '
      'and grows back: its page\'s surface is never rebuilt, and a page the '
      'cut no longer prints keeps its writing until it prints again', () {
    final controller = TimesheetInkController();
    addTearDown(controller.dispose);
    final history = HistoryManager();
    final six = _layout(TimesheetSheetKind.sixSeconds, duration: 200);
    expect(six.pageIndexes, [0, 1], reason: '⛔전제: two pages');
    controller.syncGeometry(six);
    final second = timesheetInkPageKey(_cutId, 1);
    controller.commitStroke(
      plane: null,
      key: second,
      strokeData: BrushStrokeCommitData(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: 100, y: 100),
            color: 0xFF000000,
            size: 4,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ],
      ),
      historyManager: history,
    );
    final written = controller.surfaceFor(null, second);
    expect(written, isNotNull, reason: '⛔CONTROL: written');

    final short = _layout(TimesheetSheetKind.sixSeconds, duration: 24);
    for (final layout in [
      _layout(TimesheetSheetKind.threeSeconds, duration: 200),
      short,
      six,
    ]) {
      controller.syncGeometry(layout);
      expect(
        identical(controller.surfaceFor(null, second), written),
        isTrue,
        reason: 'the paper is the same paper',
      );
    }
    expect(
      timesheetInkWindows(layout: short, cutId: _cutId).map((w) => w.key),
      [timesheetInkPageKey(_cutId, 0)],
      reason: 'the short cut prints one page, and shows no window for the '
          'second — its writing waited on the surface above',
    );
  });
}
