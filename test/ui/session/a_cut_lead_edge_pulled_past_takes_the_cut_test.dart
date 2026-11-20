import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart'
    show movieEndFrames;
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart'
    show projectWithTimelineDragPreview;

/// 🗣️I-179 (유저 2026-11-19): 「프레임블록 앞엣지의 새 규칙 … 자기 자신
/// 없애고 뒤의 블록들도 없앨수있게 … 이건 블록을 사용하는거라면 모든것에 법
/// 통일적용. 컷블록이든 뭐든 … 컷블록은 앞엣지 조절해서 컷 삭제 되는게 의도」
/// — a cut's front edge pulled back past the cut deletes it, the way the
/// cut delete does, in the drag's own undo step.
void main() {
  const a = CutId('a');
  const b = CutId('b');
  const c = CutId('c');

  Cut cutOf(CutId id, int duration, {int gap = 0, List<int> keys = const []}) =>
      Cut(
        id: id,
        name: id.value,
        duration: duration,
        leadingGapFrames: gap,
        canvasSize: const CanvasSize(width: 640, height: 360),
        camera: CutCamera(
          keyframes: {
            for (final frame in keys)
              frame: CameraPose(center: CanvasPoint(x: 320.0 + frame, y: 180)),
          },
        ),
        layers: [
          Layer(id: LayerId('${id.value}-cel'), name: 'A', frames: const []),
          Layer(
            id: LayerId('${id.value}-cam'),
            name: 'Camera',
            kind: LayerKind.camera,
            frames: const [],
          ),
        ],
      );

  EditorSessionManager open(List<Cut> cuts, {int trailing = 0}) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('sweep'),
        name: 'Sweep',
        createdAt: DateTime.utc(2026, 11, 19),
        tracks: [Track(id: const TrackId('t'), name: 'V', cuts: cuts)],
        trailingFrames: trailing,
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  List<CutId> cutsOf(Project project) => [
    for (final cut in project.tracks.single.cuts) cut.id,
  ];
  List<CutId> cutsOn(EditorSessionManager s) =>
      cutsOf(s.repository.requireProject());
  int durationOf(EditorSessionManager s, CutId id) => s.cutById(id)!.duration;
  int gapOf(EditorSessionManager s, CutId id) =>
      s.cutById(id)!.leadingGapFrames;
  int movieEnd(EditorSessionManager s) =>
      movieEndFrames(s.repository.requireProject());

  void pull(EditorSessionManager s, CutId id, int frames) {
    expect(
      s.edgeDrag.beginCutEdgeDrag(cutId: id, edge: TimelineBlockEdge.start),
      isTrue,
    );
    s.edgeDrag.updateCutEdgeDrag(frames);
    s.edgeDrag.endCutEdgeDrag();
  }

  test('pulled past a cut whole, the cut is gone and the cut glued in front '
      'ends where it ended — one undo puts it back', () {
    final s = open([cutOf(a, 10), cutOf(b, 8), cutOf(c, 6)]);
    final end = movieEnd(s);

    pull(s, b, 8);
    expect(cutsOn(s), [a, c]);
    expect(durationOf(s, a), 18);
    expect(durationOf(s, c), 6);
    expect(gapOf(s, c), 0);
    expect(movieEnd(s), end);

    s.historyManager.undo();
    expect(cutsOn(s), [a, b, c]);
    expect([durationOf(s, a), durationOf(s, b), durationOf(s, c)], [10, 8, 6]);
    expect([gapOf(s, b), gapOf(s, c)], [0, 0]);
    expect(s.repository.requireProject().trailingFrames, 0);

    s.historyManager.redo();
    expect(cutsOn(s), [a, c]);
    expect(durationOf(s, a), 18);
    expect(movieEnd(s), end);
  });

  test('the edge sweeps on into the cut behind, which starts where it '
      'stands and ends where it ended', () {
    final s = open([cutOf(a, 10), cutOf(b, 8), cutOf(c, 6)]);
    final end = movieEnd(s);

    pull(s, b, 10);

    expect(cutsOn(s), [a, c]);
    expect(durationOf(s, a), 20);
    expect(durationOf(s, c), 4);
    expect(movieEnd(s), end);
  });

  test('a cut not glued to the one in front leaves its gap and its frames '
      'empty — nothing behind moves', () {
    final s = open([cutOf(a, 10), cutOf(b, 8, gap: 3), cutOf(c, 6)]);
    final end = movieEnd(s);

    pull(s, b, 8);

    expect(cutsOn(s), [a, c]);
    expect(durationOf(s, a), 10, reason: 'not glued, it does not follow');
    expect(gapOf(s, c), 11);
    expect(movieEnd(s), end);
  });

  test('the last cut pulled past whole leaves the movie\'s end line where '
      'it was (⑱), and the undo gives the trailing gap back', () {
    final s = open([cutOf(a, 10), cutOf(b, 8, gap: 2)], trailing: 5);
    expect(movieEnd(s), 25);

    pull(s, b, 8);
    expect(cutsOn(s), [a]);
    expect(s.repository.requireProject().trailingFrames, 15);
    expect(movieEnd(s), 25);

    s.historyManager.undo();
    expect(cutsOn(s), [a, b]);
    expect(s.repository.requireProject().trailingFrames, 5);
  });

  test('the cut in front glued to the last one grows to the end, and the '
      'end line asks nothing more of the trailing gap', () {
    final s = open([cutOf(a, 10), cutOf(b, 8)], trailing: 5);

    pull(s, b, 8);

    expect(cutsOn(s), [a]);
    expect(durationOf(s, a), 18);
    expect(s.repository.requireProject().trailingFrames, 5);
    expect(movieEnd(s), 23);
  });

  test('the hand shows the cut gone and the end line where the release '
      'leaves it — and pulled back, the cut is there again', () {
    final s = open([cutOf(a, 10), cutOf(b, 8, gap: 2)], trailing: 5);
    Project previewed() => projectWithTimelineDragPreview(
      s.repository.requireProject(),
      s.dragPreview.value,
    );

    s.edgeDrag.beginCutEdgeDrag(cutId: b, edge: TimelineBlockEdge.start);
    s.edgeDrag.updateCutEdgeDrag(8);
    expect(cutsOf(previewed()), [a]);
    expect(movieEndFrames(previewed()), 25);
    expect(cutsOn(s), [a, b], reason: 'nothing is written mid-drag');

    s.edgeDrag.updateCutEdgeDrag(7);
    expect(cutsOf(previewed()), [a, b]);
    expect(previewed().tracks.single.cuts.last.duration, 1);

    s.edgeDrag.updateCutEdgeDrag(8);
    s.edgeDrag.endCutEdgeDrag();
    expect(cutsOn(s), [a]);
    expect(movieEnd(s), 25);
  });

  test('a trim no cut leaves by shows the end line where the release '
      'leaves it — ⑱ holds the line only for cuts that go', () {
    final s = open([cutOf(a, 10), cutOf(b, 8, gap: 2)], trailing: 5);
    Project previewed() => projectWithTimelineDragPreview(
      s.repository.requireProject(),
      s.dragPreview.value,
    );

    s.edgeDrag.beginCutEdgeDrag(cutId: b, edge: TimelineBlockEdge.end);
    s.edgeDrag.updateCutEdgeDrag(-3);
    expect(movieEndFrames(previewed()), 22);

    s.edgeDrag.endCutEdgeDrag();
    expect(durationOf(s, b), 5, reason: 'LIVENESS: the trim landed');
    expect(movieEnd(s), 22);
  });

  test('a cut\'s camera keys hold the edge at their floor until it has '
      'passed the cut whole — then the cut goes, keys and all', () {
    // b's keys 0, 4 and 7 ask a frame each: b may shrink to 3. c, behind
    // it, is not asked — it never moved.
    final s = open([
      cutOf(a, 10),
      cutOf(b, 8, keys: [0, 4, 7]),
      cutOf(c, 5),
    ]);

    pull(s, b, 6);
    expect(durationOf(s, b), 3);
    s.historyManager.undo();

    pull(s, b, 7);
    expect(durationOf(s, b), 3, reason: 'held at the floor');
    s.historyManager.undo();

    pull(s, b, 8);
    expect(cutsOn(s), [a, c]);
    expect(durationOf(s, a), 18);
  });

  test('swept into from the cut in front, a cut with keys keeps their '
      'floor too', () {
    final s = open([cutOf(a, 10), cutOf(b, 8, keys: [0, 4, 7])]);

    pull(s, a, 16);

    expect(cutsOn(s), [b]);
    expect(durationOf(s, b), 3);
    expect(gapOf(s, b), 15, reason: 'its end held: 10 + 8 - 3');
  });

  test('the cut the session stands in can go, and the session stands in '
      'a cut that stays', () {
    final s = open([cutOf(a, 10), cutOf(b, 8), cutOf(c, 6)]);
    s.selectCut(b);
    expect(s.activeCutId, b);

    pull(s, b, 8);

    expect(cutsOn(s), [a, c]);
    expect(s.activeCutId, isIn([a, c]));
  });
}
