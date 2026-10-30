import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_mount.dart'
    show LayerAttachDrop;
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
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
import 'package:anicel/src/models/track_conte_laying.dart' show isConteFill;
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import '../../helpers/a_folder_made_by_hand.dart';

/// 🗣️F-343 (유저 2026-10-14): 「콘티행을 확실하게 글로벌행으로」 — the
/// track's conte structure, as the session's verbs and its history meet it.
///
/// A verb writes the cut it was given; the structure lays the rest. So an
/// UNDO must take back what the structure gave the other cuts for the step
/// — the step's own undo takes back only what it did in its cut — and a
/// step that writes cut by cut is laid once, when its last write is in
/// (`ConteStepScope`).
void main() {
  Layer conte(String cut) => Layer(
    id: LayerId('$cut-conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    frames: [Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
    },
  );

  Layer rider(
    String cut,
    String suffix, {
    AttachedPlacement placement = AttachedPlacement.above,
  }) => Layer(
    id: LayerId('$cut-$suffix'),
    name: placement == AttachedPlacement.above ? 'Over' : 'Under',
    kind: LayerKind.storyboard,
    attachedToLayerId: LayerId('$cut-conte'),
    attachedPlacement: placement,
    attachedMode: AttachedMode.free,
    frames: const [],
    timeline: const {},
  );

  Layer cel(String cut) => Layer(
    id: LayerId('$cut-cel'),
    name: 'A',
    frames: const [],
    timeline: const {},
  );

  Cut cutOf(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: layers,
  );

  EditorSessionManager sessionOf(List<Cut> cuts) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('conte-structure'),
        name: 'Conte structure',
        createdAt: DateTime.utc(2026, 10, 14),
        tracks: [Track(id: const TrackId('t1'), name: 'V1', cuts: cuts)],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  Project projectOf(EditorSessionManager session) =>
      session.repository.requireProject();

  Cut cutIn(EditorSessionManager session, String id) => projectOf(
    session,
  ).tracks.single.cuts.firstWhere((cut) => cut.id == CutId(id));

  /// A cut's conte group as `seat:name`, top row first — a row the
  /// structure gave the cut marked `*`.
  List<String> seats(EditorSessionManager session, String cut) => [
    for (final entry in conteGroupOf(cutIn(session, cut)))
      '${entry.seat}:${isConteFill(entry.row) ? '*' : ''}${entry.row.name}',
  ];

  void standOn(EditorSessionManager session, String cut, String layer) {
    session.selectCut(CutId(cut));
    session.selectLayer(LayerId(layer));
    expect(session.activeLayerId, LayerId(layer), reason: 'fixture: standing');
  }

  List<Cut> twoContes() => [
    cutOf('a', [cel('a'), conte('a'), rider('a', 'over')]),
    cutOf('b', [conte('b'), rider('b', 'over'), cel('b')]),
  ];

  group('an undo', () {
    test('of a row added to one cut\'s conte takes it from every cut — and '
        'the redo gives every cut the very rows it gave before', () {
      final session = sessionOf(twoContes());
      final before = projectOf(session);
      standOn(session, 'a', 'a-conte');

      session.folders.addAttachedLayer(AttachedPlacement.above);
      final added = projectOf(session);
      final given = conteGroupOf(cutIn(session, 'b')).first.row;
      expect(conteGroupOf(cutIn(session, 'b')), hasLength(3));
      expect(isConteFill(given), isTrue, reason: 'b was given the new row');

      session.undo();
      expect(projectOf(session), before);
      expect(seats(session, 'b'), ['1:Over', '0:Conte']);

      session.redo();
      expect(projectOf(session), added);
    });

    test('of a row DRAGGED onto one cut\'s conte takes it from every cut — '
        'the drag\'s own undo only lets it go in its cut', () {
      final session = sessionOf(twoContes());
      final before = projectOf(session);

      session.cutCommandCoordinator.setLayerPlacement(
        cutId: const CutId('a'),
        order: const [LayerId('a-conte'), LayerId('a-cel'), LayerId('a-over')],
        movedIds: {const LayerId('a-cel')},
        attach: const LayerAttachDrop(
          mounts: [
            (
              layerId: LayerId('a-cel'),
              baseId: LayerId('a-conte'),
              placement: AttachedPlacement.above,
            ),
          ],
        ),
      );
      expect(seats(session, 'b'), ['2:Over', '1:*A', '0:Conte']);

      session.undo();
      expect(projectOf(session), before);
    });

    test('of a 공정 folder made in one cut takes the folder from every cut',
        () {
      final session = sessionOf(twoContes());
      final before = projectOf(session);
      standOn(session, 'a', 'a-over');

      groupTheActiveAttachIntoAFolder(session);
      expect(
        [
          for (final layer in cutIn(session, 'b').layers)
            if (layer.kind.groupsLayers) isConteFill(layer),
        ],
        [true],
        reason: 'b was given the folder',
      );

      session.undo();
      expect(projectOf(session), before);
    });

    test('of a conte made in a cut takes what the structure gave it', () {
      final session = sessionOf([
        cutOf('a', [
          cel('a'),
          rider('a', 'under', placement: AttachedPlacement.below),
          conte('a'),
          rider('a', 'over'),
        ]),
        cutOf('c', [cel('c')]),
      ]);
      final before = projectOf(session);
      standOn(session, 'c', 'c-cel');

      session.layerStack.addLayerOfKind(LayerKind.storyboard);
      expect(seats(session, 'c'), ['1:*Over', '0:Conte', '-1:*Under']);

      session.undo();
      expect(projectOf(session), before);
    });
  });

  test('a row riding the conte, deleted, goes from every cut in one step — '
      'and the undo puts the structure back as it stood', () {
    final session = sessionOf(twoContes());
    final before = projectOf(session);
    final steps = session.historyManager.undoCount;

    session.cutCommandCoordinator.deleteLayer(
      cutId: const CutId('a'),
      layerId: const LayerId('a-over'),
    );

    expect(seats(session, 'a'), ['0:Conte']);
    expect(seats(session, 'b'), ['0:Conte']);
    expect(projectOf(session).tracks.single.conte.entries, isEmpty);
    expect(session.historyManager.undoCount, steps + 1);

    session.undo();
    expect(projectOf(session), before);
  });
}
