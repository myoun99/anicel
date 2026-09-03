// A SHEET COLUMN STARTS INSIDE ITS CUT, AND AN UNCOVERED RUN GETS ITS X.
//
// Two survivors of the mutation campaign (2026-09-03): a column's
// `crossesCutEnd` default flipped to true unnoticed, and the layer pass's
// `covered` array filled with true — which paints every cell as drawn and
// loses the timesheet X — also unnoticed. These pins say what the paper
// shows.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';

void main() {
  test('a column built with only the required fields neither crosses the '
      'cut end nor spills in at the start', () {
    const column = TimesheetColumn(
      kind: TimesheetColumnKind.action,
      label: 'A',
      cells: [],
    );
    expect(column.crossesCutEnd, isFalse);
    expect(column.spillsInAtStart, isFalse);
  });

  test('the first uncovered row after a drawing is the X cell, the rest of '
      'the run stays blank', () {
    final layer = Layer(
      id: const LayerId('l'),
      name: 'A',
      frames: [Frame(id: const FrameId('a'), duration: 1, strokes: const [])],
      timeline: {0: const TimelineExposure.drawing(FrameId('a'), length: 2)},
    );
    final cut = Cut(
      id: const CutId('c'),
      name: '1',
      layers: [layer],
      duration: 6,
      canvasSize: const CanvasSize(width: 32, height: 32),
    );
    final document = TimesheetDocument.fromCut(
      cut: cut,
      projectName: 'P',
      fps: 24,
      info: TimesheetInfo.empty,
    );
    final column = document.columns.firstWhere(
      (column) => column.kind == TimesheetColumnKind.action,
    );
    final kinds = [for (final cell in column.cells.take(6)) cell.kind];
    expect(kinds[0], TimesheetCellKind.drawing);
    expect(kinds[2], TimesheetCellKind.emptyRunStart);
    expect(kinds.sublist(3), everyElement(TimesheetCellKind.empty));
  });
}
