import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timesheet_document.dart';

/// THE MEMO BAND PRINTS THE CUT NOTE, AND NOTHING A DIRECTION WRITES (I-72,
/// 유저 2026-10-05: 「앞으론 디렉션레이어 만든게 타임시트 용지의 메모란에
/// 텍스트로 추가되지않음」). The session side — a new span writes nothing into
/// the note — is `a_direction_writes_nothing_into_the_sheet_memo_test`.
void main() {
  test('fromCut derives no instruction lines: the memo band is the cut note '
      'alone', () {
    final cut = Cut(
      id: const CutId('memo-cut'),
      name: 'Memo Cut',
      duration: 24,
      canvasSize: const CanvasSize(width: 640, height: 360),
      metadata: const CutMetadata(note: 'N'),
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

    expect(document.memoText, 'N');
  });
}
