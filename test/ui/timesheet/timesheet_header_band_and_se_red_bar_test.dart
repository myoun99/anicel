import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// The printed sheet's header band and the SE block's closing red bar,
/// measured as PIXELS of the rasterized sheet.
///
/// The audit's adversarial check (2026-09-02) found both unmeasured: the
/// header band pass and the red bar made to return early passed every
/// suite that names the painter, because those suites read the cell model
/// (`displayCellsFor`) and never the ink. This is the measure.
void main() {
  Layer animationLayer(String id) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('$id-f1'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f1'), length: 2)},
  );

  Layer seLayer({required int length}) => Layer(
    id: const LayerId('s'),
    name: 'S1',
    kind: LayerKind.se,
    frames: [Frame(id: const FrameId('s-f1'), duration: 1, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(const FrameId('s-f1'), length: length),
    },
  );

  final document = TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: '1',
      duration: 12,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      layers: [animationLayer('a'), seLayer(length: 3)],
    ),
    projectName: 'P',
    fps: 24,
  );
  final layout = TimesheetDocumentLayout(document: document);
  final painter = TimesheetDocumentPainter(
    document: document,
    layout: layout,
    face: const TextStyle(),
  );
  final width = (layout.paperLeft + layout.paperWidth + 8).ceil();
  const height = 512;

  Future<ByteData> rasterize(WidgetTester tester) async {
    final data = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(
        Canvas(recorder),
        Size(width.toDouble(), height.toDouble()),
      );
      final image = await recorder.endRecording().toImage(width, height);
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    return data!;
  }

  (int r, int g, int b) rgbAt(ByteData data, double x, double y) {
    final at = (y.floor() * width + x.floor()) * 4;
    return (data.getUint8(at), data.getUint8(at + 1), data.getUint8(at + 2));
  }

  int luminance((int, int, int) rgb) => (rgb.$1 + rgb.$2 + rgb.$3) ~/ 3;

  testWidgets('the header band prints its outline on the paper', (
    tester,
  ) async {
    final pixels = await rasterize(tester);
    final band = layout.headerBandRect(0);
    // Just inside the band's left edge, away from the centred labels: the
    // top rule is ink, and the paper a few pixels below it is not.
    final onRule = luminance(rgbAt(pixels, band.left + 3, band.top));
    final onPaper = luminance(rgbAt(pixels, band.left + 3, band.top + 10));
    expect(onPaper, greaterThan(230), reason: 'blank paper inside the box');
    expect(onRule, lessThan(onPaper - 40), reason: 'the band outline');
  });

  testWidgets('an SE block closes with the full-width red bar', (tester) async {
    final pixels = await rasterize(tester);
    final column = document.columns.indexWhere(
      (c) =>
          c.kind == TimesheetColumnKind.se && c.layerId == const LayerId('s'),
    );
    expect(column, isNonNegative);
    final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(column);
    final columnWidth = layout.columnWidthFor(TimesheetColumnKind.se);
    // The block runs frames 0..2; the bar sits on the last row's bottom.
    final y = layout.frameRowTop(2) + TimesheetDocumentLayout.rowHeight - 1;
    final (r, g, b) = rgbAt(pixels, left + columnWidth / 2, y);
    expect(r, greaterThan(150), reason: 'red');
    expect(r - g, greaterThan(60), reason: 'red, not a grey rule');
    expect(r - b, greaterThan(60), reason: 'red, not a grey rule');
  });

  // The bar is the block's CLOSE, not its decoration: a bar on every held
  // row reads as three blocks where there is one. The case above only ever
  // looked at the last row, so a red bar drawn on every row of the block
  // passed it (the cells-pass split's surviving mutant, 2026-09-04).
  testWidgets('the red bar closes the block ONCE — the rows before its end '
      'carry no bar', (tester) async {
    final pixels = await rasterize(tester);
    final column = document.columns.indexWhere(
      (c) =>
          c.kind == TimesheetColumnKind.se && c.layerId == const LayerId('s'),
    );
    final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(column);
    final columnWidth = layout.columnWidthFor(TimesheetColumnKind.se);
    for (final row in [0, 1]) {
      final y = layout.frameRowTop(row) + TimesheetDocumentLayout.rowHeight - 1;
      final (r, g, b) = rgbAt(pixels, left + columnWidth / 2, y);
      expect(
        r - g < 60 || r - b < 60,
        isTrue,
        reason:
            'row $row is inside the block, not its end — a bar here '
            'would read as a block closing on every comma',
      );
    }
  });
}
