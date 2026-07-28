import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// R7-①/R8-① pins: a NAMELESS bar endpoint carries the solid triangle
/// mark (real Japanese sheets) with the duration line running through its
/// cell to meet it; named endpoints keep their empty cells for the
/// writing. The apex points INTO the span at both ends (sheet: start ▼ /
/// end ▲ — R8 direction fix), bases flush on the span edges, and on the
/// row overlay the cap fills half the cell along the time axis and half
/// the row across it. Same rule on the row overlay (timeline/X-sheet) and
/// the printed sheet.
void main() {
  const cellExtent = 48.0;
  const crossExtent = 30.0;
  const spanCells = 5;

  Layer instructionLayer({String? valueA, String? valueB}) => Layer(
    id: const LayerId('cam-1'),
    name: 'CAM 1',
    kind: LayerKind.instruction,
    frames: const [],
    timeline: const {},
    instructions: {
      0: InstructionEvent(
        instructionId: 'pan',
        length: spanCells,
        valueA: valueA,
        valueB: valueB,
      ),
    },
  );

  testWidgets('row overlay: nameless endpoints get solid triangle caps and '
      'the line extends to them; named endpoints keep their cells empty', (
    tester,
  ) async {
    Future<CustomPainter> pumpMarkPainter({
      String? valueA,
      String? valueB,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: cellExtent * spanCells,
            height: crossExtent,
            child: TimelineFixedFrameSpanLayer(
              geometry: const TimelineFrameGeometry(
                frameCellExtent: cellExtent,
                frameStartIndex: 0,
                frameEndIndexExclusive: spanCells,
              ),
              crossAxisExtent: crossExtent,
              axis: Axis.horizontal,
              children: timelineRowInstructionOverlays(
                layer: instructionLayer(valueA: valueA, valueB: valueB),
                frameStartIndex: 0,
                frameEndIndexExclusive: spanCells,
                axis: Axis.horizontal,
                defById: CameraInstructionSet.standard.defById,
              ),
            ),
          ),
        ),
      );
      final paint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byKey(
            const ValueKey<String>('timeline-instruction-cam-1-0'),
          ),
          matching: find.byType(CustomPaint),
        ),
      );
      return paint.painter!;
    }

    Future<ByteData> rasterize(CustomPainter painter) async {
      final data = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        painter.paint(
          Canvas(recorder),
          const Size(cellExtent * spanCells, crossExtent),
        );
        final image = await recorder.endRecording().toImage(
          (cellExtent * spanCells).toInt(),
          crossExtent.toInt(),
        );
        return image.toByteData(format: ui.ImageByteFormat.rawRgba);
      });
      return data!;
    }

    const width = 240;
    const midCross = 15;
    int alphaAt(ByteData data, int x, int y) =>
        data.getUint8((y * width + x) * 4 + 3);

    final nameless = await rasterize(await pumpMarkPainter());
    expect(
      alphaAt(nameless, 4, midCross),
      isNot(0),
      reason: 'start cap triangle in the first cell',
    );
    expect(
      alphaAt(nameless, width - 4, midCross),
      isNot(0),
      reason: 'end cap triangle in the last cell',
    );
    expect(
      alphaAt(nameless, width ~/ 2, midCross),
      isNot(0),
      reason: 'the line runs between the caps',
    );
    // Direction (R8-①): the caps are WIDE on the span edge and taper to
    // their apex inward — off-center ink near the edges, none near the
    // apexes (cap length = half a cell = 24px here, cross half = 7.5).
    expect(
      alphaAt(nameless, 2, midCross - 5),
      isNot(0),
      reason: 'start cap: wide at the span edge',
    );
    expect(
      alphaAt(nameless, 22, midCross - 5),
      0,
      reason: 'start cap: tapered near its apex',
    );
    expect(
      alphaAt(nameless, width - 2, midCross - 5),
      isNot(0),
      reason: 'end cap: wide at the span edge',
    );
    expect(
      alphaAt(nameless, width - 22, midCross - 5),
      0,
      reason: 'end cap: tapered near its apex',
    );

    final named = await rasterize(
      await pumpMarkPainter(valueA: 'A', valueB: 'B'),
    );
    expect(
      alphaAt(named, 4, midCross),
      0,
      reason: 'named endpoints keep their cells empty for the writing',
    );
    expect(alphaAt(named, width - 4, midCross), 0);
    expect(
      alphaAt(named, width ~/ 2, midCross),
      isNot(0),
      reason: 'the between-cells line is unchanged',
    );
  });

  test(
    'printed sheet: nameless bar endpoints get the same triangle caps',
    () async {
      TimesheetDocument document({String? valueA, String? valueB}) =>
          TimesheetDocument.fromCut(
            cut: Cut(
              id: const CutId('cut-1'),
              name: 'Cut 1',
              layers: [instructionLayer(valueA: valueA, valueB: valueB)],
              duration: 24,
              canvasSize: const CanvasSize(width: 1280, height: 720),
            ),
            projectName: 'Project',
            fps: 24,
            instructionDefById: CameraInstructionSet.standard.defById,
          );

      Future<ByteData> paintSheet(TimesheetDocument doc) async {
        final layout = TimesheetDocumentLayout(document: doc);
        final recorder = ui.PictureRecorder();
        TimesheetDocumentPainter(
          document: doc,
          layout: layout,
        ).paint(Canvas(recorder), layout.documentSize);
        final image = await recorder.endRecording().toImage(
          layout.documentSize.width.toInt(),
          layout.documentSize.height.toInt(),
        );
        final layoutWidth = image.width;
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(layoutWidth, layout.documentSize.width.toInt());
        return data;
      }

      final doc = document();
      final layout = TimesheetDocumentLayout(document: doc);
      final imageWidth = layout.documentSize.width.toInt();
      bool darkAt(ByteData data, double x, double y) =>
          data.getUint8((y.round() * imageWidth + x.round()) * 4) < 100;

      var instructionColumn = -1;
      for (var index = 0; index < doc.columns.length; index += 1) {
        if (doc.columns[index].kind == TimesheetColumnKind.camera &&
            doc.columns[index].cells[0].kind ==
                TimesheetCellKind.instructionStart) {
          instructionColumn = index;
        }
      }
      expect(instructionColumn, isNot(-1));
      final centerX =
          layout.halfLeft(0, 0) +
          layout.columnLeftInHalf(instructionColumn) +
          layout.columnWidthFor(TimesheetColumnKind.camera) / 2;
      final spanTop = layout.frameRowTop(0);
      final spanBottom =
          layout.frameRowTop(spanCells - 1) + TimesheetDocumentLayout.rowHeight;

      final nameless = await paintSheet(doc);
      expect(
        darkAt(nameless, centerX, spanTop + 3),
        isTrue,
        reason: 'start cap ▼: wide right under the span top edge',
      );
      expect(
        // R8-① direction pin: the END cap is ▲ — wide right ABOVE the
        // span bottom edge (this very sample point was the thin apex tip
        // under the old, wrong ▼ orientation).
        darkAt(nameless, centerX, spanBottom - 3),
        isTrue,
        reason: 'end cap ▲: wide right above the span bottom edge',
      );

      final named = await paintSheet(document(valueA: 'A', valueB: 'B'));
      expect(
        darkAt(named, centerX, spanTop + 16.4),
        isFalse,
        reason: 'a named first row keeps its cell bar-free below the writing',
      );
    },
  );
}
