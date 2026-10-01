import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cut_verbs.dart';

/// 🗣️I-18 link-notice-Q1 (유저): 「겸용 변환 안내문을 목록으로」 — the 겸용
/// conversion's notice names the drawings it replaces, one line each, where
/// it used to give their count.
void main() {
  CutVerbs cutsOf(EditorSessionManager s) => s.cutVerbs;

  /// Cut [name] with one row 'A' showing a drawing named '1' (its own id)
  /// and, when [second], a drawing named '2' as well.
  Cut cut(String name, {bool second = false}) => Cut(
    id: CutId('cut-$name'),
    name: name,
    duration: 4,
    canvasSize: const CanvasSize(width: 32, height: 32),
    layers: [
      Layer(
        id: LayerId('cut-$name-a'),
        name: 'A',
        frames: [
          Frame(
            id: FrameId('cut-$name-one'),
            duration: 1,
            strokes: const [],
            name: '1',
          ),
          if (second)
            Frame(
              id: FrameId('cut-$name-two'),
              duration: 1,
              strokes: const [],
              name: '2',
            ),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('cut-$name-one'), length: 1),
          if (second)
            1: TimelineExposure.drawing(FrameId('cut-$name-two'), length: 1),
        },
      ),
    ],
  );

  test('the drawings the origin\'s replace are listed by their place in the '
      'target — cut, row, drawing', () {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('linked-notice'),
        name: 'Linked',
        createdAt: DateTime.utc(2026, 10, 1),
        tracks: [
          Track(
            id: const TrackId('v'),
            name: 'V',
            cuts: [cut('1', second: true), cut('2', second: true)],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);

    final preview = cutsOf(
      s,
    ).convertToLinkedCutPreviewData(const CutId('cut-2'))!;

    expect(preview.replacedDrawings, ['2 · A · 1', '2 · A · 2']);
  });
}
