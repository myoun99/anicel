import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/link_mirror.dart'
    show linkedCutSiblings;
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show defaultCutDuration;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 🗣️F-555 (유저 2026-11-04): 「겸용컷 만들때, 컷버튼의 겸용컷 작성은
/// 지금처럼 빈 타임라인인채로 만드는거 ok. 다만 컷블록을 복사하고
/// 링크붙여넣기할땐 같은 타임라인인채로 만들도록」 · F-555-Q1: 「디렉션까지도
/// 복사. 완전 글로벌인 se행만 복사안하는것임. 콘티도 물론 복사하는거고」 — a
/// linked paste is the copy put down as it stands and made a 겸용 of its
/// source: its length, timing, camera keys and direction rows the copy's,
/// its pictures linked by name.
void main() {
  // A drawn cel's picture is warmed in the quiet the binding keeps.
  TestWidgetsFlutterBinding.ensureInitialized();
  const v = TrackId('v');
  const size = CanvasSize(width: 32, height: 32);
  const row = LayerId('cut-10-a');
  const named = FrameId('a-named');
  const unnamed = FrameId('a-unnamed');

  Frame cel(FrameId id, {String? name}) =>
      Frame(id: id, duration: 1, strokes: const [], name: name);

  /// Cut 10 — six frames: a drawing row showing a NAMED cel and an
  /// UNNAMED one, a direction row with a span, and a camera that zooms —
  /// and cut 11 of four.
  Project twoCuts() => Project(
    id: const ProjectId('linked-paste'),
    name: 'Cuts',
    createdAt: DateTime.utc(2026, 11, 4),
    tracks: [
      Track(
        id: v,
        name: 'V',
        cuts: [
          Cut(
            id: const CutId('cut-10'),
            name: '10',
            duration: 6,
            canvasSize: size,
            camera: CutCamera(
              keyframes: {
                0: CameraPose(center: CanvasPoint(x: 16, y: 16)),
                5: CameraPose(center: CanvasPoint(x: 16, y: 16), zoom: 1.5),
              },
            ),
            layers: [
              Layer(
                id: row,
                name: 'A',
                frames: [cel(named, name: '1'), cel(unnamed)],
                timeline: const {
                  0: TimelineExposure.drawing(named, length: 3),
                  3: TimelineExposure.drawing(unnamed, length: 3),
                },
              ),
              Layer(
                id: const LayerId('cut-10-direction'),
                name: 'D',
                kind: LayerKind.instruction,
                frames: const [],
                timeline: const {},
              ),
            ],
          ),
          Cut(
            id: const CutId('cut-11'),
            name: '11',
            duration: 4,
            canvasSize: size,
            layers: [
              Layer(
                id: const LayerId('cut-11-a'),
                name: 'A',
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: twoCuts());
    addTearDown(s.dispose);
    return s;
  }

  StoryboardToolbarPanelContext standOnV(EditorSessionManager s, int frame) {
    s.selectGlobalFrame(frame);
    s.selectTrackRow(v);
    return StoryboardToolbarPanelContext(s);
  }

  Cut cutNamed(EditorSessionManager s, String name) => s.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .singleWhere((cut) => cut.name == name);

  /// Cut 10's direction row.
  Layer directionOf(Cut cut) =>
      cut.layers.singleWhere((one) => one.kind == LayerKind.instruction);

  /// Both cels of cut 10 inked, a direction block on its frame 0, and cut
  /// 10 copied.
  EditorSessionManager copiedTen() {
    final s = session();
    final ten = cutNamed(s, '10');
    for (final (index, frame) in [named, unnamed].indexed) {
      inkCel(
        s,
        s.brushFrameKeyForCut(ten, row, frame),
        canvasSize: size,
        at: CanvasPoint(x: 8.0 + index * 10, y: 8),
        size: 4,
      );
    }
    s.selectGlobalFrame(0);
    s.selectLayer(directionOf(ten).id);
    s.instructionVerbs.createDefaultInstructionEventAtCurrentFrame();
    expect(
      directionOf(cutNamed(s, '10')).instructions,
      isNotEmpty,
      reason: '⛔전제: a direction block',
    );
    standOnV(s, 1).copyFrame();
    return s;
  }

  test('a linked paste is the copy as it stands — its length, timing, '
      'camera keys and direction rows — and a 겸용 of its source', () {
    expect(defaultCutDuration, isNot(6), reason: '⛔전제: a new cut is not 6');
    final s = copiedTen();
    final pill = standOnV(s, 7);
    expect(pill.canPasteLinkedFrame, isTrue);
    final steps = s.historyManager.undoCount;

    pill.pasteLinkedFrame();

    final project = s.repository.requireProject();
    expect([for (final cut in project.tracks.single.cuts) cut.name], [
      '10',
      '11',
      '12',
    ], reason: 'named on from the cut in front of it (I-150-Q5)');
    final ten = cutNamed(s, '10');
    final made = cutNamed(s, '12');
    expect(linkedCutSiblings(project, cutId: made.id), [ten.id]);
    expect(made.duration, 6);
    expect(made.camera.keyframes.keys, [0, 5]);
    expect(made.camera.keyframes[5]!.zoom, 1.5);

    final drawing = made.layers.singleWhere((one) => one.name == 'A');
    final exposures = drawing.timeline;
    expect(exposures.keys, [0, 3]);
    expect(
      exposures[0]!.frameId,
      named,
      reason: 'a named cel is the source\'s — the same picture',
    );
    expect([for (final one in exposures.values) one.length], [3, 3]);

    final direction = directionOf(made);
    final sourceDirection = directionOf(ten);
    expect(direction.id, isNot(sourceDirection.id));
    expect(direction.instructions.keys, sourceDirection.instructions.keys);
    expect(
      [for (final span in direction.instructions.values) span.instructionId],
      [
        for (final span in sourceDirection.instructions.values)
          span.instructionId,
      ],
    );
    expect(
      project.linkRegistry.groupOf(cutId: made.id, layerId: direction.id),
      isNull,
      reason: 'the direction row copied, not linked — each cut\'s own',
    );
    expect(s.historyManager.undoCount, steps + 1, reason: 'ONE step');

    s.undo();
    expect([
      for (final cut in s.repository.requireProject().tracks.single.cuts)
        cut.name,
    ], ['10', '11']);
    expect(
      s.repository.requireProject().linkRegistry.groups,
      isEmpty,
      reason: 'the link undone with the cut',
    );
  });

  test('🗣️F-278 「이름이 없으면 독립적인 그림」: an unnamed cel comes '
      'across its own picture, and the named one\'s copy is never kept — '
      'the source\'s replaces it', () {
    final s = copiedTen();
    final store = s.renderCaches.brushFrameStore;
    final ten = cutNamed(s, '10');
    final sourceUnnamed = store.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(ten, row, unnamed),
    );
    expect(sourceUnnamed, isNotNull, reason: '⛔전제: inked');

    standOnV(s, 7).pasteLinkedFrame();

    final made = cutNamed(s, '12');
    final drawing = made.layers.singleWhere((one) => one.name == 'A');
    final own = drawing.timeline[3]!.frameId!;
    expect(own, isNot(unnamed), reason: 'a cel of its own');
    expect(
      drawing.frames.singleWhere((frame) => frame.id == own).name,
      isNull,
    );
    expect(
      store.bakedSurfaceOrNull(s.brushFrameKeyForCut(made, drawing.id, own)),
      isNotNull,
      reason: 'its picture came along',
    );
    expect(
      store.bakedSurfaceOrNull(s.brushFrameKeyForCut(made, drawing.id, named)),
      same(
        store.bakedSurfaceOrNull(s.brushFrameKeyForCut(ten, row, named)),
      ),
      reason: 'the named cel reads the source\'s picture',
    );
    expect(
      store.celKeysOfCut(made.id),
      isEmpty,
      reason: 'the copy keeps no cel under its own cut: the unnamed one '
          'joined the shared bank, the named one\'s copy was never stored',
    );
  });

  test('the cut button\'s 겸용컷 작성 still starts empty — a new cut\'s '
      'length, no timing', () {
    final s = session();
    standOnV(s, 1);
    s.cutVerbs.createLinkedCutFromActiveCut();

    final made = s.requireActiveCut;
    expect(made.id, isNot(const CutId('cut-10')));
    expect(made.duration, defaultCutDuration);
    expect(
      made.layers.singleWhere((one) => one.name == 'A').timeline,
      isEmpty,
    );
  });

  test('the verb is ONE step on its own — whoever presses it', () {
    final s = session();
    final ten = cutNamed(s, '10');
    final steps = s.historyManager.undoCount;

    s.cutCommandCoordinator.createLinkedCutAsItStands(
      ten,
      sourceCutId: ten.id,
      landing: (trackId: v, index: 2, leadingGapFrames: 0),
      carry: (_, _) {},
    );

    final project = s.repository.requireProject();
    final made = project.tracks.single.cuts.last;
    expect(linkedCutSiblings(project, cutId: made.id), [ten.id]);
    expect(s.historyManager.undoCount, steps + 1);
    s.undo();
    expect(s.repository.requireProject().tracks.single.cuts, hasLength(2));
  });

  // 🗣️F-559 (유저 2026-11-04): 「컷블록 링크붙여넣기로 타임라인 같은
  // 겸용컷만들때, 언두하고 리두하면 다시 생겨야하는데 안생김.
  // 독립붙여넣기도 동일」.
  for (final linked in [true, false]) {
    final paste = linked ? 'linked' : 'independent';
    test('undone and done again, an $paste paste of a cut comes back '
        'whole — its cut, its timing and its pictures', () {
      final s = copiedTen();
      final pill = standOnV(s, 7);
      linked ? pill.pasteLinkedFrame() : pill.pasteIndependentFrame();
      List<String> names() => [
        for (final cut in s.repository.requireProject().tracks.single.cuts)
          cut.name,
      ];
      final pasted = names();
      expect(pasted, hasLength(3), reason: '⛔전제: the paste made a cut');
      final made = cutNamed(s, pasted.last);
      final drawing = made.layers.singleWhere((one) => one.name == 'A');
      final store = s.renderCaches.brushFrameStore;
      Object? pictures(Cut cut) => [
        for (final cel in drawing.timeline.values)
          store.bakedSurfaceOrNull(
            s.brushFrameKeyForCut(cut, drawing.id, cel.frameId!),
          ),
      ];
      final shown = pictures(made);
      expect(shown, everyElement(isNotNull), reason: '⛔전제: pictures');

      s.undo();
      expect(names(), ['10', '11'], reason: '⛔전제: undone');

      s.redo();
      expect(names(), pasted, reason: '「다시 생겨야하는데」');
      final again = cutNamed(s, pasted.last);
      expect(again.id, made.id);
      expect(again.duration, made.duration);
      expect(
        again.layers.singleWhere((one) => one.name == 'A').timeline,
        drawing.timeline,
      );
      expect(pictures(again), everyElement(isNotNull));
    });
  }
}
