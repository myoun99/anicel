import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// UI-R10 #9: the sheet paints in two strata — the CONTENT stratum
/// substitutes in-flight drag previews per ACTION column (the UI-R9
/// patch overlay, replaced) — plus the sheet's ghost display rules
/// (#6/#11) and the CELL header mirror (#10).
void main() {
  Layer animationLayer(String id, {int length = 2}) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('$id-f1'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f1'), length: length)},
  );

  TimesheetDocument documentFor(List<Layer> layers) =>
      TimesheetDocument.fromCut(
        cut: Cut(
          id: const CutId('cut-1'),
          name: '1',
          duration: 12,
          canvasSize: const CanvasSize(width: 1920, height: 1080),
          layers: layers,
        ),
        projectName: 'P',
        fps: 24,
      );

  TimesheetDocumentPainter contentPainter(
    TimesheetDocument document,
    ValueNotifier<TimelineDragPreview?> channel,
  ) => TimesheetDocumentPainter(
    document: document,
    layout: TimesheetDocumentLayout(document: document),
    layers: const {SheetPaintLayer.content},
    dragPreview: channel,
  );

  test('the content stratum substitutes the drag preview for ITS column '
      'while the document stays stale', () {
    final document = documentFor([animationLayer('a'), animationLayer('b')]);
    final channel = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(channel.dispose);
    final painter = contentPainter(document, channel);

    // No drag: the document's own cells.
    expect(
      painter.displayCellsFor(document.columns[0])[2].kind,
      TimesheetCellKind.emptyRunStart,
    );

    // Mid-drag: block a grew 2 → 5.
    channel.value = ExposureEdgeDragPreview(
      previewLayer: animationLayer('a', length: 5),
    );
    final cells = painter.displayCellsFor(document.columns[0]);
    expect(cells[0].kind, TimesheetCellKind.drawing);
    for (var row = 1; row < 5; row += 1) {
      expect(cells[row].kind, TimesheetCellKind.held, reason: 'row $row');
    }
    expect(cells[5].kind, TimesheetCellKind.emptyRunStart);
    // The untargeted column and the DOCUMENT stay stale.
    expect(
      painter.displayCellsFor(document.columns[1]),
      same(document.columns[1].cells),
    );
    expect(document.columns[0].cells[2].kind, TimesheetCellKind.emptyRunStart);

    // Release clears the channel: back to the document.
    channel.value = null;
    expect(
      painter.displayCellsFor(document.columns[0]),
      same(document.columns[0].cells),
    );
  });

  test('SE columns substitute the drag preview too (UI-R18 #7) — the '
      'sheet recipe (no X runs, SE names) rides the preview', () {
    Layer seLayer({int length = 2}) => Layer(
      id: const LayerId('s'),
      name: 'S1',
      kind: LayerKind.se,
      frames: [
        Frame(id: const FrameId('s-f1'), duration: 1, strokes: const []),
      ],
      timeline: {
        0: TimelineExposure.drawing(const FrameId('s-f1'), length: length),
      },
    );
    final document = documentFor([animationLayer('a'), seLayer()]);
    final channel = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(channel.dispose);
    final painter = contentPainter(document, channel);

    // The first SE slot sits right after the ACTION block and carries the
    // layer id the preview channel matches on.
    final seColumn = document.columns[8];
    expect(seColumn.kind, TimesheetColumnKind.se);
    expect(seColumn.layerId, const LayerId('s'));
    // Base: past the entry the SE column stays BLANK (no X runs).
    expect(painter.displayCellsFor(seColumn)[3].kind, TimesheetCellKind.empty);

    // Mid-drag: the SE block grew 2 → 5 — row 3 goes held LIVE while the
    // document stays stale.
    channel.value = ExposureEdgeDragPreview(previewLayer: seLayer(length: 5));
    final cells = painter.displayCellsFor(seColumn);
    expect(cells[3].kind, TimesheetCellKind.held);
    expect(cells[5].kind, TimesheetCellKind.empty, reason: 'still no X runs');
    expect(seColumn.cells[3].kind, TimesheetCellKind.empty);
  });

  test('instruction (CAM) columns substitute the drag preview too '
      '(UI-R18 #7): the slot carries its layer id now', () {
    Layer instructionLayer({int length = 3}) => Layer(
      id: const LayerId('instr'),
      name: 'PAN',
      kind: LayerKind.instruction,
      frames: const [],
      instructions: {
        2: InstructionEvent(instructionId: 'pan', length: length, text: 'PAN'),
      },
    );
    final document = documentFor([animationLayer('a'), instructionLayer()]);
    final channel = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(channel.dispose);
    final painter = contentPainter(document, channel);

    // Camera slot 1 (after the CAM keyframe slot 0) hosts the instruction
    // row: columns = 8 action + 2 SE + 8 cel + [cam0, cam1].
    final instructionColumn = document.columns[19];
    expect(instructionColumn.kind, TimesheetColumnKind.camera);
    expect(instructionColumn.layerId, const LayerId('instr'));
    expect(
      painter.displayCellsFor(instructionColumn)[2].kind,
      TimesheetCellKind.instructionStart,
    );
    expect(
      painter.displayCellsFor(instructionColumn)[5].kind,
      TimesheetCellKind.empty,
    );

    // Mid-drag: the span grew 3 → 6, covering row 5 LIVE.
    channel.value = ExposureEdgeDragPreview(
      previewLayer: instructionLayer(length: 6),
    );
    final cells = painter.displayCellsFor(instructionColumn);
    expect(cells[5].kind, TimesheetCellKind.instructionSpan);
    expect(cells[7].kind, TimesheetCellKind.instructionEnd);
    expect(
      instructionColumn.cells[5].kind,
      TimesheetCellKind.empty,
      reason: 'the document stays stale until the release commits',
    );
  });

  test('a REPEAT ghost chain prints the CONVENTION (UI-R13 #4): the first '
      'row writes the cel it restarts on, the word runs from the next row '
      '— never the expanded numbers', () {
    final layer = rederiveRunBehaviors(
      animationLayer('a').copyWith(
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('a-f1'),
            side: TimelineRunEdgeSide.end,
            mode: TimelineRunEdgeMode.repeat,
          ),
        ],
      ),
      cutFrameCount: 8,
    );
    final cells = documentFor([layer]).columns[0].cells;

    expect(cells[2].kind, TimesheetCellKind.repeatStart);
    expect(
      cells[2].label,
      '○',
      reason: 'the repeat restarts on the (unnamed) first cel',
    );
    expect(cells[2].spanLength, 6, reason: 'chain [2,8)');
    for (var row = 3; row < 8; row += 1) {
      expect(cells[row].kind, TimesheetCellKind.repeatSpan, reason: '$row');
    }
    expect(
      cells[8].kind,
      TimesheetCellKind.emptyRunStart,
      reason: 'past the chain the X run restarts',
    );
  });

  test('a FRONT repeat writes its ghost frames VERBATIM on the sheet '
      '(UI-R14 #3): expanded cel numbers, never the repeat word', () {
    final frontRepeat = rederiveRunBehaviors(
      Layer(
        id: const LayerId('fr'),
        name: 'FR',
        frames: [
          Frame(
            id: const FrameId('fr-f1'),
            duration: 1,
            name: '7',
            strokes: const [],
          ),
        ],
        timeline: {
          4: const TimelineExposure.drawing(FrameId('fr-f1'), length: 2),
        },
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('fr-f1'),
            side: TimelineRunEdgeSide.start,
            mode: TimelineRunEdgeMode.repeat,
          ),
        ],
      ),
      cutFrameCount: 12,
    );
    final cells = documentFor([frontRepeat]).columns[0].cells;

    // The lead-in [0,4) cycles the 2f pattern: ghost starts at 0 and 2,
    // each printing its cel number with a held row under it — exactly
    // like authored cells, no repeat notation anywhere.
    expect(cells[0].kind, TimesheetCellKind.drawing);
    expect(cells[0].label, '7');
    expect(cells[1].kind, TimesheetCellKind.held);
    expect(cells[2].kind, TimesheetCellKind.drawing);
    expect(cells[2].label, '7');
    expect(cells[3].kind, TimesheetCellKind.held);
    expect(
      cells[4].kind,
      TimesheetCellKind.drawing,
      reason: 'the authored block',
    );
  });

  test('a FRONT hold MOVES the cel to row 1 FOR REAL: one run through the '
      'authored position, no second drawing start (UI-R12 #17)', () {
    final frontHold = rederiveRunBehaviors(
      Layer(
        id: const LayerId('b'),
        name: 'B',
        frames: [
          Frame(
            id: const FrameId('b-f1'),
            duration: 1,
            name: '5',
            strokes: const [],
          ),
        ],
        timeline: {
          4: const TimelineExposure.drawing(FrameId('b-f1'), length: 2),
        },
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('b-f1'),
            side: TimelineRunEdgeSide.start,
            mode: TimelineRunEdgeMode.hold,
          ),
        ],
      ),
      cutFrameCount: 12,
    );
    final cells = documentFor([frontHold]).columns[0].cells;

    expect(cells[0].kind, TimesheetCellKind.drawing);
    expect(cells[0].label, '5', reason: 'the name lives on row 1');
    expect(cells[0].spanLength, 6, reason: 'ONE run [0,6): chain + block');
    for (var row = 1; row < 6; row += 1) {
      expect(
        cells[row].kind,
        TimesheetCellKind.held,
        reason:
            'row $row — '
            'the hold line runs straight through the authored position '
            '(XDTS-facing data really moved; the timeline keeps frame 5)',
      );
      expect(cells[row].spanOffset, row);
    }
    expect(
      cells[4].label,
      anyOf(isNull, isEmpty),
      reason: 'no second start, no label',
    );
    expect(
      cells[6].kind,
      TimesheetCellKind.emptyRunStart,
      reason: 'past the run the X run restarts',
    );
  });

  test('one cel held from row 1 prints the hold word chain (止め, '
      'UI-R11 #15); multi-block layers do not', () {
    final single = rederiveRunBehaviors(
      animationLayer('a').copyWith(
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('a-f1'),
            side: TimelineRunEdgeSide.end,
            mode: TimelineRunEdgeMode.hold,
          ),
        ],
      ),
      cutFrameCount: 8,
    );
    final cells = documentFor([single]).columns[0].cells;
    // The hold word starts RIGHT AFTER the cel's first row (UI-R25 #1):
    // 1止め — the block's own held rows join the word span.
    expect(cells[1].kind, TimesheetCellKind.holdStart);
    expect(cells[1].spanLength, 7);
    for (var row = 2; row < 8; row += 1) {
      expect(cells[row].kind, TimesheetCellKind.empty, reason: '$row');
    }

    // Two blocks: the rear hold stays silent (no 止め).
    final multi = rederiveRunBehaviors(
      Layer(
        id: const LayerId('m'),
        name: 'M',
        frames: [
          Frame(id: const FrameId('m-1'), duration: 1, strokes: const []),
          Frame(id: const FrameId('m-2'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('m-1'), length: 1),
          1: const TimelineExposure.drawing(FrameId('m-2'), length: 1),
        },
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('m-2'),
            side: TimelineRunEdgeSide.end,
            mode: TimelineRunEdgeMode.hold,
          ),
        ],
      ),
      cutFrameCount: 8,
    );
    final multiCells = documentFor([multi]).columns[0].cells;
    expect(multiCells[2].kind, TimesheetCellKind.empty);
  });

  test('the CELL block mirrors the ACTION layer names as headers '
      '(UI-R10 #10)', () {
    final document = documentFor([animationLayer('a'), animationLayer('b')]);
    final celColumns = [
      for (final column in document.columns)
        if (column.kind == TimesheetColumnKind.cel) column,
    ];
    expect(celColumns[0].label, 'A');
    expect(celColumns[1].label, 'B');
    expect(celColumns[2].label, '');
    expect(
      celColumns[0].cells.every((c) => c.kind == TimesheetCellKind.empty),
      isTrue,
      reason: 'headers only — the content stays blank',
    );
  });
}
