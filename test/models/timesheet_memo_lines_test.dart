import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timesheet_document.dart';

const _ol = CameraInstructionDef(
  id: 'ol',
  name: 'O.L',
  iconKey: 'overlap',
  markType: CameraInstructionMarkType.ol,
);
const _pan = CameraInstructionDef(id: 'pan', name: 'PAN', iconKey: 'pan');

void main() {
  group('timesheetMemoInstructionLine', () {
    test('full form: endpoints, mark glyph, label, memo', () {
      const event = InstructionEvent(
        instructionId: 'ol',
        length: 6,
        valueA: 'C',
        valueB: 'D',
        memo: 'カットO.L',
      );
      expect(timesheetMemoInstructionLine(event, _ol), 'C⋈D O.L カットO.L');
    });

    test('blank parts drop out; bar defs use the arrow glyph', () {
      expect(
        timesheetMemoInstructionLine(
          const InstructionEvent(instructionId: 'ol', length: 6, valueA: 'A'),
          _ol,
        ),
        'A⋈ O.L',
      );
      expect(
        timesheetMemoInstructionLine(
          const InstructionEvent(
            instructionId: 'pan',
            length: 12,
            valueA: 'A',
            valueB: 'B',
          ),
          _pan,
        ),
        'A→B PAN',
      );
    });

    test('free event text wins over the vocabulary name; a dangling def '
        'falls back to bar + raw id', () {
      expect(
        timesheetMemoInstructionLine(
          const InstructionEvent(
            instructionId: 'pan',
            length: 4,
            text: 'メモリPAN',
            memo: 'ゆっくり',
          ),
          _pan,
        ),
        '→ メモリPAN ゆっくり',
      );
      expect(
        timesheetMemoInstructionLine(
          const InstructionEvent(instructionId: 'gone', length: 4),
          null,
        ),
        '→ gone',
      );
    });
  });

  test('fromCut derives NO instruction lines — the shorthand writes itself '
      'into the (editable) cut note at creation instead (R5-⑥)', () {
    final cut = Cut(
      id: const CutId('memo-cut'),
      name: 'Memo Cut',
      duration: 24,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: [
        Layer(
          id: const LayerId('cel'),
          name: 'A',
          frames: const [],
          timeline: const {},
        ),
        Layer(
          id: const LayerId('cam-1'),
          name: 'CAM 1',
          kind: LayerKind.instruction,
          frames: const [],
          timeline: const {},
          instructions: {
            0: const InstructionEvent(
              instructionId: 'ol',
              length: 6,
              valueA: 'C',
              valueB: 'D',
              memo: 'カットO.L',
            ),
          },
        ),
      ],
    );

    final document = TimesheetDocument.fromCut(
      cut: cut,
      projectName: 'P',
      fps: 24,
      instructionDefById: CameraInstructionSet.standard.defById,
    );

    // The memo band prints only the cut note; the instruction event alone
    // contributes nothing derived.
    expect(document.memoText, cut.metadata.note);
  });
}
