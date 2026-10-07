import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨A DIRECTION WRITES NOTHING INTO THE SHEET'S MEMO (I-72).
///
/// 유저 2026-10-05: 「디렉션레이어, 작성하거나 하면 타임시트용지에 해당 지시
/// 적어주는데 그 동작 잔재 안남도록 싹 삭제. 앞으론 디렉션레이어 만든게
/// 타임시트 용지의 메모란에 텍스트로 추가되지않음」. A new span wrote its
/// shorthand ('C⋈D O.L') into the cut note in the same undo step; the note is
/// the person's alone now.
void main() {
  const direction = LayerId('cam-1');

  EditorSessionManager session(String note) {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 7),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('c'),
                name: '12',
                duration: 24,
                canvasSize: const CanvasSize(width: 640, height: 360),
                metadata: CutMetadata(pageNotes: [note]),
                layers: [
                  Layer(
                    id: direction,
                    name: 'CAM 1',
                    kind: LayerKind.instruction,
                    frames: const [],
                    timeline: const {},
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    return s;
  }

  for (final note in ['N', '']) {
    test('🎯a new O.L span leaves the note as it was (「$note」)', () {
      final s = session(note);
      s.instructionVerbs.upsertInstructionEventAt(
        direction,
        0,
        const InstructionEvent(
          instructionId: 'ol',
          length: 6,
          valueA: 'C',
          valueB: 'D',
        ),
        createLengthFrames: 6,
      );

      expect(
        s.instructionVerbs.instructionSpanAt(direction, 0),
        isNotNull,
        reason: 'LIVENESS: the span was laid',
      );
      expect(s.cutVerbs.activeCutNoteOf(0), note);

      s.undo();
      expect(s.instructionVerbs.instructionSpanAt(direction, 0), isNull);
      expect(s.cutVerbs.activeCutNoteOf(0), note);
    });
  }
}
