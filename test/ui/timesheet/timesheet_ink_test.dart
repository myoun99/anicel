import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_ink_keys.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_layer.dart';

const _cutId = CutId('cut-1');

TimesheetDocument _document({int duration = 150}) {
  return TimesheetDocument.fromCut(
    cut: Cut(
      id: _cutId,
      name: 'Cut 1',
      layers: const [],
      duration: duration,
      canvasSize: const CanvasSize(width: 1280, height: 720),
    ),
    projectName: 'Project',
    fps: 24,
  );
}

BrushStrokeCommitData _oneDabStroke({double x = 20, double y = 20}) {
  return BrushStrokeCommitData(
    sourceDabs: [
      BrushDab(
        center: CanvasPoint(x: x, y: y),
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
  );
}

void main() {
  group('timesheetInkWindows', () {
    test('one window per page, the whole paper — the ink is the paper\'s '
        '(F-252)', () {
      final document = _document();
      final layout = TimesheetDocumentLayout(document: document);
      final windows = timesheetInkWindows(
        layout: layout,
        cutId: _cutId,
      );

      expect(layout.pageIndexes, [0, 1], reason: 'fixture: two pages');
      expect(windows.map((window) => window.key), [
        timesheetInkPageKey(_cutId, 0),
        timesheetInkPageKey(_cutId, 1),
      ]);
      for (final (page, window) in windows.indexed) {
        expect(window.documentRect, layout.pageRect(page));
        expect(window.inkOffset, Offset.zero);
        expect(window.plane, isNull, reason: 'one plane');
      }
    });

    test('inkViewport composes the panel transform, window placement and '
        'ink scale into one exact mapping', () {
      final document = _document();
      final layout = TimesheetDocumentLayout(document: document);
      final windows = timesheetInkWindows(
        layout: layout,
        cutId: _cutId,
      );
      final panel = CanvasViewport(zoom: 2, panX: 7, panY: 9);

      // The second page's window: ink pixel (x, y) must land where the
      // document paints doc point (rect.left + x/s, rect.top + y/s) — s the
      // paper's pixels a sheet unit takes.
      final window = windows[1];
      final ink = window.inkViewport(panel);
      const inkPoint = Offset(10, 40);
      final screenX = ink.panX + ink.zoom * (window.inkOffset.dx + inkPoint.dx);
      final screenY = ink.panY + ink.zoom * (window.inkOffset.dy + inkPoint.dy);
      final docX = window.documentRect.left + inkPoint.dx / layout.paperScale;
      final docY = window.documentRect.top + inkPoint.dy / layout.paperScale;
      expect(screenX, closeTo(panel.panX + panel.zoom * docX, 1e-9));
      expect(screenY, closeTo(panel.panY + panel.zoom * docY, 1e-9));

      final screenRect = window.screenRect(panel);
      expect(
        screenRect.topLeft,
        Offset(
          panel.panX + panel.zoom * window.documentRect.left,
          panel.panY + panel.zoom * window.documentRect.top,
        ),
      );
      expect(screenRect.width, panel.zoom * window.documentRect.width);
    });
  });

  group('TimesheetInkController', () {
    test('syncGeometry sizes the page surface: the paper, pixel for pixel',
        () {
      final layout = TimesheetDocumentLayout(document: _document());
      final controller = TimesheetInkController();
      controller.syncGeometry(layout);

      // F-294 (유저 2026-10-05): 「1754x2480을 기본으로 할것」.
      expect(
        controller.pageSurfaceSize,
        const CanvasSize(width: 1754, height: 2480),
      );
      final state = controller.sessionStateFor(
        null,
        timesheetInkPageKey(_cutId, 0),
      );
      expect(
        state.canvasState.currentSurface.canvasSize,
        controller.pageSurfaceSize,
      );
    });

    test('commitStroke goes through the app history: one undo step per '
        'stroke, redo restores it', () {
      final layout = TimesheetDocumentLayout(document: _document());
      final controller = TimesheetInkController();
      controller.syncGeometry(layout);
      final historyManager = HistoryManager();
      final page0 = timesheetInkPageKey(_cutId, 0);
      final page1 = timesheetInkPageKey(_cutId, 1);

      controller.commitStroke(
        plane: null,
        key: page0,
        strokeData: _oneDabStroke(),
        historyManager: historyManager,
      );
      controller.commitStroke(
        plane: null,
        key: page1,
        strokeData: _oneDabStroke(x: 100, y: 30),
        historyManager: historyManager,
      );

      expect(controller.hasInkFor(null, page0), isTrue);
      expect(controller.hasInkFor(null, page1), isTrue);

      historyManager.undo();
      expect(
        controller.hasInkFor(null, page1),
        isFalse,
        reason: 'the LAST stroke (the second page) undoes first',
      );
      expect(controller.hasInkFor(null, page0), isTrue);

      historyManager.undo();
      expect(controller.hasInkFor(null, page0), isFalse);

      historyManager.redo();
      expect(controller.hasInkFor(null, page0), isTrue);
    });
  });

  group('TimesheetInkLayer', () {
    testWidgets('a stroke on the column grid and one on the memo band both '
        'land on the page\'s paper; undo removes them one at a time', (
      tester,
    ) async {
      final document = _document(duration: 24);
      final layout = TimesheetDocumentLayout(document: document);
      final controller = TimesheetInkController();
      controller.syncGeometry(layout);
      final historyManager = HistoryManager();
      final strokeActive = ValueNotifier<bool>(false);
      addTearDown(strokeActive.dispose);
      final documentSize = layout.documentSize;

      await tester.binding.setSurfaceSize(
        Size(documentSize.width + 40, documentSize.height + 40),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: documentSize.width,
                height: documentSize.height,
                child: TimesheetInkLayer(
                  controller: controller,
                  layout: layout,
                  cutId: _cutId,
                  brushToolState: ValueNotifier(BrushToolState.defaults),
                  historyManager: historyManager,
                  viewport: CanvasViewport(),
                  strokeActive: strokeActive,
                ),
              ),
            ),
          ),
        ),
      );

      final layerBox = tester.getTopLeft(find.byType(TimesheetInkLayer));
      Future<void> stroke(Offset docStart, Offset docEnd) async {
        final gesture = await tester.startGesture(
          layerBox + docStart,
          pointer: 7,
        );
        await tester.pump();
        expect(strokeActive.value, isTrue);
        await gesture.moveTo(layerBox + docEnd);
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(strokeActive.value, isFalse);
      }

      final page0 = timesheetInkPageKey(_cutId, 0);
      // Inside the page-0 half-0 column grid.
      final gridPoint = Offset(
        layout.halfLeft(0, 0) + 30,
        layout.halfRowsTop(0) + 30,
      );
      await stroke(gridPoint, gridPoint + const Offset(24, 10));
      expect(controller.hasInkFor(null, page0), isTrue);

      // On the Direction memo band (under the header, left of the memo
      // box).
      final memoBand = layout.memoBandRect(0);
      await stroke(
        memoBand.topLeft + const Offset(30, 40),
        memoBand.topLeft + const Offset(80, 60),
      );
      expect(historyManager.undoCount, 2, reason: 'two strokes, two steps');

      historyManager.undo();
      expect(
        controller.hasInkFor(null, page0),
        isTrue,
        reason: 'the grid\'s stroke is still on the paper',
      );
      historyManager.undo();
      expect(controller.hasInkFor(null, page0), isFalse);
    });
  });
}
