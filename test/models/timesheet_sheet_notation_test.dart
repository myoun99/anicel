import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/models/timesheet_info.dart';

TimesheetDocument _document({required List<Layer> layers}) {
  return TimesheetDocument.fromCut(
    cut: Cut(
      id: const CutId('cut-1'),
      name: 'Cut 1',
      layers: layers,
      duration: 24,
      canvasSize: const CanvasSize(width: 1280, height: 720),
    ),
    projectName: 'Project',
    fps: 24,
    instructionDefById: CameraInstructionSet.standard.defById,
  );
}

void main() {
  test('SE start cells carry the speaker name for the method-A name row', () {
    final document = _document(
      layers: [
        Layer(
          id: const LayerId('se-1'),
          name: 'S1',
          kind: LayerKind.se,
          frames: [
            Frame(
              id: const FrameId('se-f'),
              duration: 6,
              strokes: const [],
              name: '그건 아니라고 생각해',
              seName: '앨리스',
            ),
          ],
          timeline: {
            2: const TimelineExposure.drawing(FrameId('se-f'), length: 6),
          },
        ),
      ],
    );

    final seColumn = document.columns.firstWhere(
      (column) => column.kind == TimesheetColumnKind.se,
    );
    expect(seColumn.cells[2].seName, '앨리스');
    expect(seColumn.cells[2].label, '그건 아니라고 생각해');
    // Names never leak onto held rows or non-SE columns.
    expect(seColumn.cells[3].seName, isNull);
    final actionColumn = document.columns.firstWhere(
      (column) => column.kind == TimesheetColumnKind.action,
    );
    expect(actionColumn.cells.every((cell) => cell.seName == null), isTrue);
  });

  test('instruction writing rides EVERY covered row so the middle-row '
      'label survives page-half crossings', () {
    final document = _document(
      layers: [
        Layer(
          id: const LayerId('cam-1'),
          name: 'CAM 1',
          kind: LayerKind.instruction,
          frames: const [],
          timeline: const {},
          instructions: {
            2: const InstructionEvent(
              instructionId: 'pan',
              length: 5,
              valueA: 'A',
              valueB: 'B',
            ),
          },
        ),
      ],
    );

    final instructionColumn = document.columns
        .where((column) => column.kind == TimesheetColumnKind.camera)
        .elementAt(1);
    for (var row = 2; row < 7; row += 1) {
      expect(instructionColumn.cells[row].label, 'PAN', reason: 'row $row');
      expect(instructionColumn.cells[row].spanOffset, row - 2);
      expect(instructionColumn.cells[row].spanLength, 5);
    }
    expect(instructionColumn.cells[7].label, isNull);
  });

  test('held cells carry their span geometry (R4: the exposure-bar option '
      'gates on the comma offset) and the document mirrors the notation '
      'settings', () {
    final document = TimesheetDocument.fromCut(
      cut: Cut(
        id: const CutId('cut-holds'),
        name: 'Cut Holds',
        layers: [
          Layer(
            id: const LayerId('cel'),
            name: 'A',
            frames: [
              Frame(id: const FrameId('a1'), duration: 5, strokes: const []),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('a1'), length: 5),
            },
          ),
        ],
        duration: 24,
        canvasSize: const CanvasSize(width: 1280, height: 720),
      ),
      projectName: 'P',
      fps: 24,
      info: const TimesheetInfo(exposureBarThreshold: 3, seEmptyFill: false),
    );

    expect(document.exposureBarThreshold, 3);
    expect(document.seEmptyFill, isFalse);

    final actionColumn = document.columns.firstWhere(
      (column) => column.kind == TimesheetColumnKind.action,
    );
    for (var row = 1; row < 5; row += 1) {
      expect(actionColumn.cells[row].kind, TimesheetCellKind.held);
      expect(actionColumn.cells[row].spanOffset, row, reason: 'row $row');
      expect(actionColumn.cells[row].spanLength, 5);
    }
  });
}
