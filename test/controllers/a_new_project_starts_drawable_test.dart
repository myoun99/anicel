import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨F-211 (유저 2026-09-28): 「프로젝트 실행 초기값은 초기컷/해당 초기레이어에
/// A라는 레이어 있는상태로 ok. 다만 여기서 **1번인덱스에 프레임도 만들어서
/// 키자마자 그리는게 가능하도록** 하고싶음. 신규유저 배려. 그렇지만 **새 컷
/// 생성의 초기값은 프레임도 없고 나아가서 A라는 기본 레이어도 존재안하도록**」.
///
/// Two defaults that used to be one (`createDefaultCut`, for both): a new
/// PROJECT opens with layer A and its first cel, ready to be drawn on; a new
/// CUT opens with its fixtures and nothing else.
void main() {
  Cut firstCutOf(Project project) => project.tracks.first.cuts.first;

  List<Layer> drawingRows(Cut cut) => [
    for (final layer in cut.layers)
      if (layer.kind == LayerKind.animation) layer,
  ];

  EditorSessionManager sessionOn(Project project) {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    return session;
  }

  group('a new project', () {
    test('opens with layer A holding ONE cel on the cut\'s first frame', () {
      final rowA = drawingRows(firstCutOf(newUntitledProject())).single;

      expect(rowA.name, 'A');
      expect(rowA.frames, hasLength(1));
      final cel = rowA.frames.single;
      expect(cel.strokes, isEmpty);
      expect(cel.name, isNull, reason: 'an unnamed drawing, as ＋ makes one');
      expect(rowA.timeline.keys, [0], reason: 'the first frame');
      expect(rowA.timeline[0]!.frameId, cel.id);
      expect(rowA.timeline[0]!.length, 1, reason: 'one comma, as ＋ makes');
    });

    test('that cel is the ＋ press\'s own — the row a press on the bare '
        'project makes, cel id aside', () {
      final pressed = sessionOn(createDefaultProject());
      pressed.createDrawingAtCurrentFrame();
      final byPress = drawingRows(pressed.requireActiveCut).single;
      final born = drawingRows(
        sessionOn(newUntitledProject()).requireActiveCut,
      ).single;

      expect(born.frames, hasLength(byPress.frames.length));
      expect(born.frames.single.duration, byPress.frames.single.duration);
      expect(born.frames.single.name, byPress.frames.single.name);
      expect(
        [
          for (final entry in born.timeline.entries)
            (entry.key, entry.value.length, entry.value.ghost),
        ],
        [
          for (final entry in byPress.timeline.entries)
            (entry.key, entry.value.length, entry.value.ghost),
        ],
        reason: 'the same exposures — the held ghost behind it included',
      );
    });

    test('is drawable the moment it opens: you stand on a cel', () {
      final session = sessionOn(newUntitledProject());

      expect(session.activeLayer?.name, 'A');
      expect(session.currentFrameIndex, 0);
      expect(
        session.selectedFrame,
        isNotNull,
        reason: '「키자마자 그리는게 가능하도록」 — a stroke has a cel to land on',
      );
      expect(
        session.selectedFrame!.id,
        session.activeLayer!.frames.single.id,
        reason: 'the cel layer A was born with',
      );
    });

    test('⛔the bare default the tests build on stays bare', () {
      final rowA = drawingRows(firstCutOf(createDefaultProject())).single;

      expect(rowA.frames, isEmpty);
      expect(rowA.timeline, isEmpty);
    });

    test('two new projects are two projects, each with a cel of its own', () {
      final a = newUntitledProject();
      final b = newUntitledProject();

      expect(a.id, isNot(b.id));
      expect(
        drawingRows(firstCutOf(a)).single.frames.single.id,
        isNot(drawingRows(firstCutOf(b)).single.frames.single.id),
      );
    });
  });

  group('a new cut', () {
    test('opens with its fixtures and NO drawing row — no layer A, no '
        'frame', () {
      final session = sessionOn(newUntitledProject());
      final first = session.requireActiveCut.id;

      session.cutVerbs.createCut();

      final made = session.requireActiveCut;
      expect(made.id, isNot(first), reason: '⛔전제: a new cut, stood on');
      expect(
        [for (final layer in made.layers) layer.kind],
        [LayerKind.instruction, LayerKind.camera],
      );
      expect(
        [for (final layer in made.layers) ...layer.frames],
        isEmpty,
      );
    });

    test('and the cut it was made beside keeps its layer A and its cel', () {
      final session = sessionOn(newUntitledProject());
      final first = session.requireActiveCut.id;

      session.cutVerbs.createCut();

      final kept = session.activeTrack.cuts.firstWhere(
        (cut) => cut.id == first,
      );
      expect(drawingRows(kept).single.frames, hasLength(1));
    });

    test('the row ＋ layer makes in it is the row a project starts with — '
        'its name, its kind, its label, and no cel', () {
      final session = sessionOn(createDefaultProject());
      final projects = drawingRows(session.requireActiveCut).single;

      session.cutVerbs.createCut();
      session.layerStack.addLayerOfKind(LayerKind.animation);

      final added = drawingRows(session.requireActiveCut).single;
      expect(added.id, isNot(projects.id), reason: '⛔전제: another row');
      expect(
        (added.name, added.kind, added.mark),
        (projects.name, projects.kind, projects.mark),
      );
      expect(
        projects.mark,
        LayerMark.bornOfKind(LayerKind.animation),
        reason: 'LIVENESS — its kind\'s label (F-76), not two bare rows '
            'agreeing',
      );
      expect(added.frames, isEmpty);
      expect(added.timeline, isEmpty);
    });

    test('one undo takes it back', () {
      final session = sessionOn(newUntitledProject());
      final cuts = session.activeTrack.cuts.length;

      session.cutVerbs.createCut();
      session.undo();

      expect(session.activeTrack.cuts, hasLength(cuts));
    });
  });
}
