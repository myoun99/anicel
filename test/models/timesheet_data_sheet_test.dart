import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timesheet_document.dart';

/// UI-R24 #1: the DATA sheet — the timesheet's export-source view. Ghost
/// chains render VERBATIM (the per-entry labels XDTS/TDTS write) instead
/// of the notation shorthand; holds stay holds (labels never tile down
/// held rows).
Layer _repeatLayer() {
  var layer = Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: [
      Frame(id: const FrameId('c1'), name: '1', duration: 1, strokes: const []),
      Frame(id: const FrameId('c2'), name: '2', duration: 1, strokes: const []),
    ],
    timeline: const {
      0: TimelineExposure.drawing(FrameId('c1'), length: 2),
      2: TimelineExposure.drawing(FrameId('c2'), length: 2),
    },
    runBehaviors: const [
      TimelineRunBehavior(
        anchorFrameId: FrameId('c1'),
        side: TimelineRunEdgeSide.end,
        mode: TimelineRunEdgeMode.repeat,
      ),
    ],
  );
  layer = rederiveRunBehaviors(layer, cutFrameCount: 12);
  return layer;
}

TimesheetDocument _document(Layer layer, {required bool dataSheet}) {
  return TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: 'Cut 1',
      layers: [layer],
      duration: 12,
      canvasSize: const CanvasSize(width: 1280, height: 720),
    ),
    projectName: 'Project',
    fps: 24,
    dataSheet: dataSheet,
  );
}

void main() {
  test('a rear repeat prints the NOTATION word normally and the VERBATIM '
      'export labels in DATA mode — holds stay holds, never tiled', () {
    final layer = _repeatLayer();
    // The derived timeline: 1(2) 2(2) then repeat ghosts 1(2) 2(2)…
    expect(layer.timeline[4]!.ghost, isTrue);

    final notation = _document(layer, dataSheet: false).columns.first.cells;
    expect(notation[0].kind, TimesheetCellKind.drawing);
    expect(notation[0].label, '1');
    expect(notation[4].kind, TimesheetCellKind.repeatStart);
    expect(notation[5].kind, TimesheetCellKind.repeatSpan);

    final data = _document(layer, dataSheet: true).columns.first.cells;
    // The authored blocks are untouched…
    expect(data[0].kind, TimesheetCellKind.drawing);
    expect(data[0].label, '1');
    expect(data[2].label, '2');
    // …and the ghost chain prints its concrete per-entry labels exactly
    // where XDTS writes its value changes.
    expect(data[4].kind, TimesheetCellKind.drawing);
    expect(data[4].label, '1');
    expect(data[6].kind, TimesheetCellKind.drawing);
    expect(data[6].label, '2');
    expect(data[8].label, '1');
    expect(data[10].label, '2');
    // Held rows remain HELD — the label never tiles down the hold.
    expect(data[1].kind, TimesheetCellKind.held);
    expect(data[5].kind, TimesheetCellKind.held);
  });

  test('R26 #26: a rear HOLD prints the hold word normally and, in DATA '
      'mode, ONE cel at the run start with held rows after it', () {
    var layer = Layer(
      id: const LayerId('h'),
      name: 'H',
      frames: [
        Frame(
          id: const FrameId('cel'),
          name: '1',
          duration: 1,
          strokes: const [],
        ),
      ],
      timeline: const {
        0: TimelineExposure.drawing(FrameId('cel'), length: 2),
      },
      runBehaviors: const [
        TimelineRunBehavior(
          anchorFrameId: FrameId('cel'),
          side: TimelineRunEdgeSide.end,
          mode: TimelineRunEdgeMode.hold,
        ),
      ],
    );
    layer = rederiveRunBehaviors(layer, cutFrameCount: 12);
    expect(layer.timeline[2]!.ghost, isTrue);

    final notation = _document(layer, dataSheet: false).columns.first.cells;
    // The hold word starts RIGHT AFTER the cel's first row (UI-R25 #1):
    // 1止め — the block's own held row joins the word span, and the rest
    // of the column is blank paper.
    expect(notation[1].kind, TimesheetCellKind.holdStart);
    expect(notation[1].spanLength, 11);
    expect(notation[2].kind, TimesheetCellKind.empty);

    final data = _document(layer, dataSheet: true).columns.first.cells;
    // R26 #26: a hold is the SAME cel exposed longer — the real data is
    // ONE drawing at row 0 held to the cut end, never a second label at
    // the ghost's start.
    expect(data[0].kind, TimesheetCellKind.drawing);
    expect(data[0].label, '1');
    expect(data[0].spanLength, 12, reason: 'the run swallows the hold');
    for (var row = 1; row < 12; row += 1) {
      expect(data[row].kind, TimesheetCellKind.held, reason: 'row $row');
      expect(data[row].label, isNull, reason: 'row $row prints no cel');
    }
  });

  test('R26 #26: a FRONT + REAR hold around one block is ONE cel in DATA '
      'mode — the label prints at the fused run start only', () {
    var layer = Layer(
      id: const LayerId('h'),
      name: 'H',
      frames: [
        Frame(
          id: const FrameId('cel'),
          name: '1',
          duration: 1,
          strokes: const [],
        ),
      ],
      timeline: const {
        4: TimelineExposure.drawing(FrameId('cel'), length: 2),
      },
      runBehaviors: const [
        TimelineRunBehavior(
          anchorFrameId: FrameId('cel'),
          side: TimelineRunEdgeSide.start,
          mode: TimelineRunEdgeMode.hold,
        ),
        TimelineRunBehavior(
          anchorFrameId: FrameId('cel'),
          side: TimelineRunEdgeSide.end,
          mode: TimelineRunEdgeMode.hold,
        ),
      ],
    );
    layer = rederiveRunBehaviors(layer, cutFrameCount: 12);

    final data = _document(layer, dataSheet: true).columns.first.cells;
    final drawingRows = [
      for (var row = 0; row < 12; row += 1)
        if (data[row].kind == TimesheetCellKind.drawing) row,
    ];
    expect(
      drawingRows,
      <int>[0],
      reason: 'one cel, at the first row of the fused run',
    );
    expect(data[0].label, '1');
    for (var row = 1; row < 12; row += 1) {
      expect(data[row].kind, TimesheetCellKind.held, reason: 'row $row');
    }
  });
}
