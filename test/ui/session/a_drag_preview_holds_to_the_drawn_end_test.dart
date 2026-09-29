import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

import '../../helpers/run_edge_fixtures.dart';

/// 🗣️F-227 (유저 2026-09-29): 「타임라인패널에서도 홀드같은게 빨간엔드라인에서
/// 끝나는게아니라 여백엔드라인까지 가도록」.
///
/// What a drag SHOWS while it moves is what its release writes: a held
/// block's ghosts reach the drawn end in the live preview, not the red line
/// the commit would then correct — the preview reads the same end the
/// repository settles to.
void main() {
  const giving = CutId('a');
  const row = LayerId('row');

  Cut cut(CutId id, {List<Layer> layers = const []}) => Cut(
    id: id,
    name: id.value,
    duration: 48,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: layers,
  );

  Frame cel(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  /// A 4-frame block, then a 4-frame block that HOLDS to the end.
  final heldRow = Layer(
    id: row,
    name: 'A',
    frames: [cel('x'), cel('y')],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('x'), length: 4),
      10: const TimelineExposure.drawing(
        FrameId('y'),
        length: 4,
        endEdge: holdMark,
      ),
    },
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [
              cut(giving, layers: [heldRow]),
              cut(const CutId('b')),
            ],
          ),
        ],
      ),
    );
    // An O.L of 24 over the boundary: 12 frames of のりしろ past the end.
    s.transitions.updateTransitionInstructions({
      36: const InstructionEvent(instructionId: 'ol', length: 24),
    });
    return s;
  }

  test('a block moved mid-drag shows its row\'s hold through the のりしろ', () {
    final s = session();
    addTearDown(s.dispose);
    expect(
      s.drawingBlockMove.beginDrawingBlockMoveDrag(
        layerId: row,
        blockStartIndex: 0,
      ),
      isTrue,
    );
    s.drawingBlockMove.updateDrawingBlockMoveDrag(frameDelta: 2);
    final preview = s.dragPreview.value;
    expect(preview, isA<BlockMoveDragPreview>());
    final shown = (preview! as BlockMoveDragPreview).previewLayers[row]!;
    expect(
      authoredTimelineExtent(shown.timeline),
      60,
      reason: '48 + 12 — the end the release will write',
    );
    s.drawingBlockMove.endDrawingBlockMoveDrag();
    expect(
      authoredTimelineExtent(s.layerById(row)!.timeline),
      60,
      reason: 'and the release wrote it',
    );
  });
}
