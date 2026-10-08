import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_mount.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart'
    show plannedAddLayerCommand;
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️I-73-one-head-Q2 (유저 2026-10-09 → `all`): 「넷 다 모든 컷에 함께」 —
/// the attach structure a track's contes wear as one head moves in every
/// cut: a re-ordering of the conte's rows, a row dragged onto the conte, a
/// row added inside an organizer folder of the group. (Letting a row go is
/// refused outright — I-73-one-head-Q1.)
///
/// Cuts a, b and c hold the same conte group, bottom first: `under`, the
/// conte, `over1`, `over2` — and a drawing row `cel` beside it. Cut d's
/// conte carries `over1` alone; a group shaped otherwise is left as it is.
void main() {
  const a = CutId('a');
  const b = CutId('b');
  const d = CutId('d');

  Layer row(
    String id, {
    LayerKind kind = LayerKind.storyboard,
    String? ridesOn,
    AttachedPlacement placement = AttachedPlacement.above,
    String? folderId,
  }) => Layer(
    id: LayerId(id),
    name: id.substring(2),
    kind: kind,
    frames: const [],
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
    attachedPlacement: placement,
    attachedMode: AttachedMode.free,
    folderId: folderId == null ? null : LayerId(folderId),
  );

  Cut cutOf(String id, {bool short = false}) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      row('$id-cel', kind: LayerKind.animation),
      if (!short)
        row(
          '$id-under',
          ridesOn: '$id-conte',
          placement: AttachedPlacement.below,
        ),
      row('$id-conte'),
      row('$id-over1', ridesOn: '$id-conte'),
      if (!short) row('$id-over2', ridesOn: '$id-conte'),
    ],
  );

  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('structure'),
        name: 'Structure',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [cutOf('a'), cutOf('b'), cutOf('c'), cutOf('d', short: true)],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  Cut cutIn(EditorSessionManager session, CutId id) => session.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .singleWhere((cut) => cut.id == id);

  /// [id]'s conte group, top row first, each row by its name and seat.
  List<String> groupOf(EditorSessionManager session, CutId id) => [
    for (final entry in conteGroupOf(cutIn(session, id)))
      '${entry.seat}:${entry.row.name}',
  ];

  void place(
    EditorSessionManager session,
    List<String> order, {
    required String moved,
    LayerAttachDrop attach = const LayerAttachDrop(),
  }) => session.cutCommandCoordinator.setLayerPlacement(
    cutId: a,
    order: [for (final id in order) LayerId(id)],
    movedIds: {LayerId(moved)},
    attach: attach,
  );

  /// The three cuts' group as the fixture holds it.
  const asItWas = ['2:over2', '1:over1', '0:conte', '-1:under'];

  group('a re-ordering of the conte\'s rows', () {
    const swapped = ['2:over1', '1:over2', '0:conte', '-1:under'];

    test('🚨is every cut\'s whose group holds the same seats — and undo takes '
        'it back from all of them', () {
      final session = open();

      place(session, [
        'a-cel',
        'a-under',
        'a-conte',
        'a-over2',
        'a-over1',
      ], moved: 'a-over1');

      expect(groupOf(session, a), swapped);
      expect(groupOf(session, b), swapped);
      expect(groupOf(session, const CutId('c')), swapped);
      expect(
        groupOf(session, d),
        ['1:over1', '0:conte'],
        reason: 'shaped otherwise',
      );

      session.undo();
      expect(groupOf(session, b), asItWas);
    });

    test('🚨across the conte, the row takes the other side in every cut', () {
      final session = open();

      place(
        session,
        ['a-cel', 'a-under', 'a-over1', 'a-conte', 'a-over2'],
        moved: 'a-over1',
        attach: const LayerAttachDrop(
          sideChange: (
            layerId: LayerId('a-over1'),
            placement: AttachedPlacement.below,
          ),
        ),
      );

      const crossed = ['1:over2', '0:conte', '-1:over1', '-2:under'];
      expect(groupOf(session, a), crossed);
      expect(groupOf(session, b), crossed);
      expect(
        cutIn(session, b).layers.byId(const LayerId('b-over1'))!
            .attachedPlacement,
        AttachedPlacement.below,
      );
    });
  });

  group('a row dragged onto the conte', () {
    test('🚨is born on the same seat of every cut\'s, empty, wearing its '
        'head', () {
      final session = open();

      place(
        session,
        ['a-under', 'a-conte', 'a-cel', 'a-over1', 'a-over2'],
        moved: 'a-cel',
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

      expect(
        groupOf(session, a),
        ['3:over2', '2:over1', '1:cel', '0:conte', '-1:under'],
        reason: '⛔전제',
      );
      expect(
        groupOf(session, b),
        ['3:over2', '2:over1', '1:cel', '0:conte', '-1:under'],
      );
      final born = conteRowAtSeat(cutIn(session, b), 1)!;
      expect(born.kind, LayerKind.animation, reason: 'the row\'s own kind');
      expect(born.frames, isEmpty);
      expect(
        groupOf(session, d),
        ['1:over1', '0:conte'],
        reason: 'its above side holds other seats',
      );

      session.undo();
      expect(groupOf(session, b), asItWas);
    });
  });

  test('🚨a row added inside an organizer folder of the group is born on its '
      'seat in every cut\'s — riding the conte there, with no folder', () {
    final session = open();
    // a's over2 filed into an organizer folder ORG, which stands over it.
    final aCut = cutIn(session, a);
    session.repository.replaceProject(
      session.repository.requireProject().copyWith(
        tracks: [
          session.repository.requireProject().tracks.single.copyWith(
            cuts: [
              aCut.copyWith(
                layers: [
                  for (final layer in aCut.layers)
                    if (layer.id == const LayerId('a-over2'))
                      layer.copyWith(folderId: const LayerId('a-org'))
                    else
                      layer,
                  row('a-org', kind: LayerKind.folder),
                ],
              ),
              for (final cut in session.repository
                  .requireProject()
                  .tracks
                  .single
                  .cuts
                  .skip(1))
                cut,
            ],
          ),
        ],
      ),
    );
    expect(groupOf(session, a), asItWas);

    // A new row filed in ORG, under over2: the group's second seat.
    final layers = cutIn(session, a).layers;
    session.cutCommandCoordinator.historyManager.execute(
      plannedAddLayerCommand(
        repository: session.repository,
        cutId: a,
        layer: row('a-new', ridesOn: 'a-conte', folderId: 'a-org'),
        insertionIndex: layers.indexWhere(
          (layer) => layer.id == const LayerId('a-over2'),
        ),
      ),
    );

    expect(
      groupOf(session, a),
      ['3:over2', '2:new', '1:over1', '0:conte', '-1:under'],
      reason: '⛔전제',
    );
    expect(
      groupOf(session, b),
      ['3:over2', '2:new', '1:over1', '0:conte', '-1:under'],
    );
    final born = conteRowAtSeat(cutIn(session, b), 2)!;
    expect(born.folderId, isNull, reason: 'b files nothing there');
    expect(born.attachedToLayerId, const LayerId('b-conte'));
  });
}
