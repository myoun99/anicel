import 'dart:ui' show Paragraph;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/timesheet/timesheet_words_in.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// The sheet's writing never drops out (tiny-glyphs-shrink-not-vanish).
///
/// 🗣️The user's rule for the glyphs: 「엄청 작아지는 한이 있어도 절대 안
/// 사라지도록」. The sheet stopped painting every header, memo and cell
/// text below 35% device zoom — a cutoff nobody asked for (f3dd6f6f,
/// 「for overview panning」). The type shrinks with the paper now.
///
/// Counted off a spy canvas: every text the sheet writes is a paragraph,
/// and with culling off the same sheet has the same writing at any zoom.
class _WritingSpy implements Canvas {
  int paragraphs = 0;

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) => paragraphs += 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

TimesheetDocument _document() {
  Layer cel(String id) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: const [])],
    timeline: {
      for (var f = 0; f < 48; f += 6)
        f: TimelineExposure.drawing(FrameId('$id-f'), length: 6),
    },
  );
  return TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: '1',
      duration: 48,
      canvasSize: const CanvasSize(width: 1920, height: 1080),
      layers: [cel('a'), cel('b')],
    ),
    projectName: 'P',
    fps: 24,
  );
}

void main() {
  late bool culling;

  setUp(() {
    culling = TimesheetDocumentPainter.debugDisableCulling;
    TimesheetDocumentPainter.debugDisableCulling = true;
  });
  tearDown(() => TimesheetDocumentPainter.debugDisableCulling = culling);

  int writingAt(double zoom, {double effectiveRatio = 1.0}) {
    final document = _document();
    final spy = _WritingSpy();
    TimesheetDocumentPainter(
      words: timesheetWordsIn(AppLanguage.en),
      face: const TextStyle(),
      document: document,
      layout: TimesheetDocumentLayout(document: document),
      viewport: CanvasViewport(zoom: zoom, panX: 0, panY: 0),
      effectiveRatio: effectiveRatio,
    ).paint(spy, const Size(1200, 1600));
    return spy.paragraphs;
  }

  test('an overview zoom writes everything a working zoom writes', () {
    final working = writingAt(1.0);
    expect(working, greaterThan(0), reason: 'fixture: the sheet has writing');

    expect(writingAt(0.2), working);
    expect(writingAt(0.05), working);
  });

  test('⛔the device ratio and the UI scale take no writing away either', () {
    expect(writingAt(0.3, effectiveRatio: 0.5), writingAt(1.0));
  });
}
