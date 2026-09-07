import 'dart:ui' show ClipOp;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// 🚨THE SAME TRANSFORM THE DOCUMENT TOOK — the sheet's paper painter and
/// the playhead overlay on top of it must enter document space through
/// the identical clip and the identical snapped matrix, or the highlight
/// sits a sub-pixel off the rows it highlights.
///
/// That law was written in a comment and kept by hand in two bodies. This
/// reads the prologue off a spy canvas so it is measured instead.
class _PrologueSpy implements Canvas {
  final ops = <String>[];

  @override
  void save() => ops.add('save');

  @override
  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) => ops.add('clip ${rect.left} ${rect.top} ${rect.width} ${rect.height}');

  @override
  void translate(double dx, double dy) => ops.add('translate $dx $dy');

  @override
  void scale(double sx, [double? sy]) => ops.add('scale $sx ${sy ?? sx}');

  @override
  void rotate(double radians) => ops.add('rotate $radians');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

TimesheetDocument _document() => TimesheetDocument.fromCut(
  cut: Cut(
    id: const CutId('cut-1'),
    name: 'Cut 1',
    layers: const [],
    duration: 150,
    canvasSize: const CanvasSize(width: 1280, height: 720),
  ),
  projectName: 'Project',
  fps: 24,
);

/// Everything up to the first op that is not part of entering document
/// space — what the two painters have to agree on.
List<String> _prologue(List<String> ops) {
  const prologue = {'save', 'translate', 'scale', 'rotate', 'clip'};
  final head = <String>[];
  for (final op in ops) {
    if (!prologue.contains(op.split(' ').first)) {
      break;
    }
    head.add(op);
  }
  return head;
}

void main() {
  test('the paper and the playhead enter document space identically, and '
      'the pan is SNAPPED on the effective ratio', () {
    final document = _document();
    final layout = TimesheetDocumentLayout(document: document);
    // A fractional pan is the whole point: at ratio 2 it snaps to a half
    // logical pixel, and at ratio 1 it would snap to a whole one.
    final viewport = CanvasViewport(zoom: 1.5, panX: 10.3, panY: -4.4);
    const size = Size(800, 600);

    final paper = _PrologueSpy();
    TimesheetDocumentPainter(
      document: document,
      layout: layout,
      viewport: viewport,
      effectiveRatio: 2.0,
    ).paint(paper, size);

    final playhead = _PrologueSpy();
    TimesheetPlayheadPainter(
      document: document,
      layout: layout,
      resolvePlayheadFrame: () => 3,
      viewport: viewport,
      effectiveRatio: 2.0,
    ).paint(playhead, size);

    expect(_prologue(paper.ops), [
      'save',
      'clip 0.0 0.0 800.0 600.0',
      'translate 10.5 -4.5',
      'scale 1.5 1.5',
    ]);
    expect(
      _prologue(playhead.ops),
      _prologue(paper.ops),
      reason: 'one prologue, one grid',
    );
  });

  test('no viewport means no transform, but the clip still happens', () {
    final document = _document();
    final layout = TimesheetDocumentLayout(document: document);

    final paper = _PrologueSpy();
    TimesheetDocumentPainter(
      document: document,
      layout: layout,
    ).paint(paper, const Size(800, 600));

    expect(_prologue(paper.ops), [
      'save',
      'clip 0.0 0.0 800.0 600.0',
    ]);
  });
}
