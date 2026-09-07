// THE PRINTED SHEET'S SE DIALOGUE IS SPREAD DOWN ITS WHOLE BLOCK, and it
// goes through the same placer the timeline overlay uses.
//
// The screen half of that claim was pinned by pixels; the print half was
// not. A print placer that stacked every glyph at the top of the span, or
// stopped after the first, passed every sheet suite — those read the cell
// MODEL, never the ink.
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

void main() {
  Layer animationLayer() => Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: [Frame(id: const FrameId('a-f1'), duration: 1, strokes: const [])],
    timeline: const {0: TimelineExposure.drawing(FrameId('a-f1'), length: 2)},
  );

  // Five glyphs over an eight-row block: enough that a placer which never
  // advanced would leave the tail rows blank.
  Layer seLayer() => Layer(
    id: const LayerId('s'),
    name: 'S1',
    kind: LayerKind.se,
    frames: [
      Frame(
        id: const FrameId('s-f1'),
        duration: 1,
        strokes: const [],
        name: 'あいうえお',
      ),
    ],
    timeline: const {0: TimelineExposure.drawing(FrameId('s-f1'), length: 8)},
  );

  final document = TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: '1',
      duration: 12,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      layers: [animationLayer(), seLayer()],
    ),
    projectName: 'P',
    fps: 24,
  );
  final layout = TimesheetDocumentLayout(document: document);
  final painter = TimesheetDocumentPainter(document: document, layout: layout);
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

  int inkIn(ByteData data, Rect rect) {
    var n = 0;
    for (var y = rect.top.floor(); y < rect.bottom.ceil(); y += 1) {
      for (var x = rect.left.floor(); x < rect.right.ceil(); x += 1) {
        final at = (y * width + x) * 4;
        final r = data.getUint8(at);
        final g = data.getUint8(at + 1);
        final b = data.getUint8(at + 2);
        // Dark ink only — the rules and washes around it are light.
        if (data.getUint8(at + 3) > 0 && (r + g + b) ~/ 3 < 120) {
          n += 1;
        }
      }
    }
    return n;
  }

  testWidgets('the dialogue reaches the LAST rows of its block, not just '
      'the first — the fit spreads it over the whole span', (tester) async {
    final pixels = await rasterize(tester);
    final column = document.columns.indexWhere(
      (c) =>
          c.kind == TimesheetColumnKind.se && c.layerId == const LayerId('s'),
    );
    expect(column, isNonNegative);
    final left = layout.halfLeft(0, 0) + layout.columnLeftInHalf(column);
    final columnWidth = layout.columnWidthFor(TimesheetColumnKind.se);
    const rowHeight = TimesheetDocumentLayout.rowHeight;

    Rect rows(int from, int toExclusive) => Rect.fromLTWH(
      left + 1,
      layout.frameRowTop(from),
      columnWidth - 2,
      (toExclusive - from) * rowHeight,
    );

    // The block runs frames 0..7. Both halves carry glyphs.
    expect(inkIn(pixels, rows(1, 4)), greaterThan(0), reason: 'upper half');
    expect(
      inkIn(pixels, rows(5, 8)),
      greaterThan(0),
      reason: 'a placer that never advanced would leave the tail blank',
    );
  });
}
