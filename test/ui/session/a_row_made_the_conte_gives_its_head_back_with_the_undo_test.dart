import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️F-424 (유저 2026-10-21): 「기존 레이어 콘티레이어 변경하고 언두하면
/// 색라벨도 돌아오도록」. A row made a cut's conte wears its track's head
/// (I-73) — label, name, opacity — and the undo that takes it out of the
/// conte gives it back the head it wore of its own.
void main() {
  const lo = LayerMark(process: LayerProcess.layout);
  const sb = LayerMark(process: LayerProcess.conte);

  Layer cel({required bool drawn}) => Layer(
    id: const LayerId('a-cel'),
    name: 'A',
    mark: lo,
    opacity: 0.5,
    frames: drawn
        ? [Frame(id: const FrameId('a-f'), duration: 12, strokes: const [])]
        : const [],
    timeline: drawn
        ? {0: const TimelineExposure.drawing(FrameId('a-f'), length: 12)}
        : const {},
  );

  Cut cutOf(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: layers,
  );

  /// Track `t1`: cut `a` with the row, and — when [headed] — cut `b` with
  /// a conte wearing the track's head, and cut `c` with none.
  EditorSessionManager sessionOf({required bool drawn, bool headed = true}) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('head-back'),
        name: 'Head back',
        createdAt: DateTime.utc(2026, 10, 21),
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'V1',
            cuts: [
              cutOf('a', [cel(drawn: drawn)]),
              if (headed) ...[
                cutOf('b', [
                  Layer(
                    id: const LayerId('b-conte'),
                    name: 'Conte',
                    kind: LayerKind.storyboard,
                    mark: sb,
                    frames: [
                      Frame(
                        id: const FrameId('b-panel'),
                        duration: 12,
                        strokes: const [],
                      ),
                    ],
                    timeline: {
                      0: const TimelineExposure.drawing(
                        FrameId('b-panel'),
                        length: 12,
                      ),
                    },
                  ),
                ]),
                cutOf('c', [
                  Layer(
                    id: const LayerId('c-cel'),
                    name: 'C',
                    frames: const [],
                  ),
                ]),
              ],
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.selectCut(const CutId('a'));
    session.selectLayer(const LayerId('a-cel'));
    return session;
  }

  Cut cut(EditorSessionManager session, String id) => session.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == CutId(id));

  Layer row(EditorSessionManager session) =>
      cut(session, 'a').layers.byId(const LayerId('a-cel'))!;

  (LayerKind, LayerMark, String, double) worn(EditorSessionManager session) {
    final layer = row(session);
    return (layer.kind, layer.mark, layer.name, layer.opacity);
  }

  for (final drawn in const [true, false]) {
    final which = drawn ? 'a drawn row' : 'an empty row';
    test('🚨$which made the conte wears its track\'s head — and one undo '
        'gives it its own back, a redo the head again', () {
      final session = sessionOf(drawn: drawn);

      session.layerSwitches.toggleTargetLayerKind();
      expect(worn(session), (LayerKind.storyboard, sb, 'Conte', 1.0));

      session.undo();
      expect(worn(session), (LayerKind.animation, lo, 'A', 0.5));

      session.redo();
      expect(worn(session), (LayerKind.storyboard, sb, 'Conte', 1.0));
    });
  }

  test('an empty row made the FIRST conte keeps what it wears — the blank '
      'panel is all it takes', () {
    final session = sessionOf(drawn: false, headed: false);

    session.layerSwitches.toggleTargetLayerKind();

    expect(worn(session), (LayerKind.storyboard, lo, 'A', 0.5));
    expect(row(session).frames, hasLength(1));
    expect(row(session).timeline.values.single.length, 12);
  });

  test('⛔a row the step MADE goes with its undo, head and all', () {
    final session = sessionOf(drawn: true);
    session.selectCut(const CutId('c'));
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    expect(
      storyboardLayerForCut(cut(session, 'c'))?.mark,
      sb,
      reason: '⛔전제: born wearing the head',
    );

    session.undo();
    expect(storyboardLayerForCut(cut(session, 'c')), isNull);

    session.redo();
    expect(storyboardLayerForCut(cut(session, 'c'))?.mark, sb);
  });

  test('what the step itself wrote on the row is its own undo\'s: the head '
      'comes off what the head put on, and only that', () {
    final session = sessionOf(drawn: true);
    const key = LayerMark(process: LayerProcess.key);

    session.historyManager.runAsOneStep('Mark and make the conte', () {
      session.layerMarks.setLayerMark(const LayerId('a-cel'), key);
      session.layerSwitches.toggleTargetLayerKind();
    });
    expect(worn(session), (LayerKind.storyboard, sb, 'Conte', 1.0));

    session.undo();
    expect(worn(session), (LayerKind.animation, lo, 'A', 0.5));
  });
}
