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
    test('paged: page ink under two strip half windows per page, the halves '
        'sharing one band surface', () {
      final document = _document();
      final layout = TimesheetDocumentLayout(document: document);
      final windows = timesheetInkWindows(
        layout: layout,
        pagedLayout: layout,
        cutId: _cutId,
      );

      // 2 page windows first (bottom of the stack), then 2 halves × 2 pages.
      expect(windows, hasLength(6));
      expect(
        windows.take(2).every((w) => w.plane == TimesheetInkPlane.page),
        isTrue,
      );
      expect(windows[0].documentRect, layout.pageRect(0));
      expect(windows[0].inkOffset, Offset.zero);

      final strips = windows.skip(2).toList();
      expect(strips.every((w) => w.plane == TimesheetInkPlane.strip), isTrue);
      expect(strips[0].key, strips[1].key, reason: 'one band, two halves');
      expect(strips[0].key == strips[2].key, isFalse, reason: 'page 2 band');
      expect(
        strips[0].documentRect.topLeft,
        Offset(layout.halfLeft(0, 0), layout.halfRowsTop(0)),
      );
      expect(
        strips[1].documentRect.topLeft,
        Offset(layout.halfLeft(0, 1), layout.halfRowsTop(0)),
      );
      expect(strips[0].inkOffset, Offset.zero);
      expect(
        strips[1].inkOffset,
        Offset(
          0,
          document.halfFrameCount *
              TimesheetDocumentLayout.rowHeight *
              TimesheetInkController.inkScale,
        ),
        reason: 'the right half windows the band below row 72',
      );
    });

    test('continuous: page 1 ink in the paged paper geometry + the bands '
        'stacked down the strip', () {
      final document = _document();
      final layout = TimesheetDocumentLayout(
        document: document,
        continuous: true,
      );
      final pagedLayout = TimesheetDocumentLayout(document: document);
      final windows = timesheetInkWindows(
        layout: layout,
        pagedLayout: pagedLayout,
        cutId: _cutId,
      );

      expect(windows, hasLength(3));
      expect(windows[0].plane, TimesheetInkPlane.page);
      expect(windows[0].documentRect.height, pagedLayout.paperHeight);
      expect(windows[0].documentRect.width, pagedLayout.paperWidth);

      final bandHeight =
          document.pageFrameCount * TimesheetDocumentLayout.rowHeight;
      expect(windows[1].plane, TimesheetInkPlane.strip);
      expect(
        windows[1].documentRect.topLeft,
        Offset(layout.halfLeft(0, 0), layout.halfRowsTop(0)),
      );
      expect(
        windows[2].documentRect.top,
        layout.halfRowsTop(0) + bandHeight,
        reason: 'band 2 continues seamlessly below band 1',
      );
      expect(windows[1].inkOffset, Offset.zero);
      expect(windows[2].inkOffset, Offset.zero);
    });

    test('inkViewport composes the panel transform, window placement and '
        'ink scale into one exact mapping', () {
      final document = _document();
      final layout = TimesheetDocumentLayout(document: document);
      final windows = timesheetInkWindows(
        layout: layout,
        pagedLayout: layout,
        cutId: _cutId,
      );
      final panel = CanvasViewport(zoom: 2, panX: 7, panY: 9);

      // The page-0 right-half strip window: ink pixel (x, inkOffset.y + d)
      // must land where the document paints doc point (rect.left + x/2,
      // rect.top + d/2).
      final window = windows[3];
      final ink = window.inkViewport(panel);
      const inkPoint = Offset(10, 40);
      final screenX = ink.panX + ink.zoom * (window.inkOffset.dx + inkPoint.dx);
      final screenY = ink.panY + ink.zoom * (window.inkOffset.dy + inkPoint.dy);
      final docX =
          window.documentRect.left +
          inkPoint.dx / TimesheetInkController.inkScale;
      final docY =
          window.documentRect.top +
          inkPoint.dy / TimesheetInkController.inkScale;
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
    test('syncGeometry sizes the band and page surfaces at inkScale', () {
      final document = _document();
      final layout = TimesheetDocumentLayout(document: document);
      final controller = TimesheetInkController();
      controller.syncGeometry(layout);

      expect(
        controller.stripBandSurfaceSize,
        CanvasSize(
          width: (layout.halfWidth * TimesheetInkController.inkScale).ceil(),
          height:
              document.pageFrameCount *
              TimesheetDocumentLayout.rowHeight.toInt() *
              TimesheetInkController.inkScale,
        ),
      );
      expect(
        controller.pageSurfaceSize,
        CanvasSize(
          width: (layout.paperWidth * TimesheetInkController.inkScale).ceil(),
          height: (layout.paperHeight * TimesheetInkController.inkScale).ceil(),
        ),
      );

      final state = controller.sessionStateFor(
        TimesheetInkPlane.strip,
        TimesheetInkController.stripBandKey(_cutId, 0),
      );
      expect(
        state.canvasState.currentSurface.canvasSize,
        controller.stripBandSurfaceSize,
      );
    });

    test('commitStroke goes through the app history: one undo step per '
        'stroke, redo restores it', () {
      final layout = TimesheetDocumentLayout(document: _document());
      final controller = TimesheetInkController();
      controller.syncGeometry(layout);
      final historyManager = HistoryManager();
      final band0 = TimesheetInkController.stripBandKey(_cutId, 0);
      final page0 = TimesheetInkController.pageKey(_cutId, 0);

      controller.commitStroke(
        plane: TimesheetInkPlane.strip,
        key: band0,
        strokeData: _oneDabStroke(),
        historyManager: historyManager,
      );
      controller.commitStroke(
        plane: TimesheetInkPlane.page,
        key: page0,
        strokeData: _oneDabStroke(x: 100, y: 30),
        historyManager: historyManager,
      );

      expect(controller.hasInkFor(TimesheetInkPlane.strip, band0), isTrue);
      expect(controller.hasInkFor(TimesheetInkPlane.page, page0), isTrue);

      historyManager.undo();
      expect(
        controller.hasInkFor(TimesheetInkPlane.page, page0),
        isFalse,
        reason: 'the LAST stroke (page plane) undoes first',
      );
      expect(controller.hasInkFor(TimesheetInkPlane.strip, band0), isTrue);

      historyManager.undo();
      expect(controller.hasInkFor(TimesheetInkPlane.strip, band0), isFalse);

      historyManager.redo();
      expect(controller.hasInkFor(TimesheetInkPlane.strip, band0), isTrue);
    });
  });

  group('TimesheetInkLayer', () {
    testWidgets('a stroke on the column grid lands on the strip plane; one '
        'on the memo band lands on the page plane; undo removes both', (
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
                  pagedLayout: layout,
                  cutId: _cutId,
                  brushToolState: BrushToolState.defaults,
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

      // Inside the page-0 half-0 column grid → strip plane.
      final gridPoint = Offset(
        layout.halfLeft(0, 0) + 30,
        layout.halfRowsTop(0) + 30,
      );
      await stroke(gridPoint, gridPoint + const Offset(24, 10));

      final band0 = TimesheetInkController.stripBandKey(_cutId, 0);
      final page0 = TimesheetInkController.pageKey(_cutId, 0);
      expect(controller.hasInkFor(TimesheetInkPlane.strip, band0), isTrue);
      expect(controller.hasInkFor(TimesheetInkPlane.page, page0), isFalse);

      // On the Direction memo band (under the header, left of the memo
      // box) → page plane.
      final memoBand = layout.memoBandRect(0);
      await stroke(
        memoBand.topLeft + const Offset(30, 40),
        memoBand.topLeft + const Offset(80, 60),
      );
      expect(controller.hasInkFor(TimesheetInkPlane.page, page0), isTrue);
      expect(controller.hasInkFor(TimesheetInkPlane.strip, band0), isTrue);

      historyManager.undo();
      historyManager.undo();
      expect(controller.hasInkFor(TimesheetInkPlane.strip, band0), isFalse);
      expect(controller.hasInkFor(TimesheetInkPlane.page, page0), isFalse);
    });
  });
}
