import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_mount.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🗣️I-122 (유저 2026-10-22): 「어태치 레이어 드래그로 순서 바꿀때 이름
/// 기본값인 상태 그대로라면 … 이름의 +1 +2같은 숫자도 새 순서에 맞춰서
/// 바뀌도록」 — and F-436 ③, the same day: a row attached to ANOTHER base
/// takes that base's name, 「장착하려는 대상에 맞춰서」.
///
/// Both doors that move a seat — a drag's placement and the menu's attach —
/// rename through the one law, in the write's own undo step.

const _track = TrackId('track-1');
const _cutId = CutId('cut-1');
const _above = AttachedPlacement.above;
const _below = AttachedPlacement.below;

Layer _base(String id) => Layer(id: LayerId(id), name: id, frames: const []);

Layer _rider(
  String id,
  String name,
  String base, [
  AttachedPlacement side = _above,
]) => Layer(
  id: LayerId(id),
  name: name,
  frames: const [],
  attachedToLayerId: LayerId(base),
  attachedPlacement: side,
);

class _Fixture {
  _Fixture(List<Layer> layers)
    : repository = ProjectRepository(
        initialProject: Project(
          id: const ProjectId('project-1'),
          name: 'Project',
          createdAt: DateTime.utc(2024),
          tracks: [
            Track(
              id: _track,
              name: 'Video',
              cuts: [
                Cut(
                  id: _cutId,
                  name: 'cut',
                  layers: layers,
                  duration: 8,
                  canvasSize: const CanvasSize(width: 1280, height: 720),
                ),
              ],
            ),
          ],
        ),
      ),
      history = HistoryManager() {
    coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: _cutId),
      historyManager: history,
    );
  }

  final ProjectRepository repository;
  final HistoryManager history;
  late final CutCommandCoordinator coordinator;

  List<Layer> get layers =>
      requireCut(repository.requireProject(), _cutId).layers;

  String nameOf(String id) =>
      layers.singleWhere((layer) => layer.id == LayerId(id)).name;

  /// [base]'s riders on [side], nearest the base first, by name.
  List<String> seatsOf(String base, AttachedPlacement side) {
    final rows = [
      for (final row in attachedLayersOf(LayerId(base), layers))
        if (row.attachedPlacement == side) row.name,
    ];
    return side == _above ? rows : rows.reversed.toList();
  }

  void move(
    List<String> order, {
    Set<String> moved = const {},
    LayerAttachDrop attach = const LayerAttachDrop(),
  }) => coordinator.setLayerPlacement(
    cutId: _cutId,
    order: [for (final id in order) LayerId(id)],
    movedIds: {for (final id in moved) LayerId(id)},
    attach: attach,
  );
}

LayerAttachDrop _mount(String row, String base, AttachedPlacement side) =>
    LayerAttachDrop(
      mounts: [(layerId: LayerId(row), baseId: LayerId(base), placement: side)],
    );

void main() {
  test('a drag that reorders a side hands the numbers out again by seat, '
      'the nearest the base the lowest', () {
    final fixture = _Fixture([
      _base('B'),
      _rider('r1', 'B+1', 'B'),
      _rider('r2', 'B+2', 'B'),
    ]);

    fixture.move(['B', 'r2', 'r1'], moved: {'r2'});

    expect(fixture.nameOf('r2'), 'B+1');
    expect(fixture.nameOf('r1'), 'B+2');
  });

  test('below the base the seats count down the stack', () {
    final fixture = _Fixture([
      _rider('r2', 'B-2', 'B', _below),
      _rider('r1', 'B-1', 'B', _below),
      _base('B'),
    ]);

    fixture.move(['r1', 'r2', 'B'], moved: {'r1'});

    expect(fixture.seatsOf('B', _below), ['B-1', 'B-2']);
    expect(fixture.nameOf('r2'), 'B-1', reason: 'r2 sits next to the base');
  });

  test('a name of the user\'s own stays as written, and takes no number', () {
    final fixture = _Fixture([
      _base('B'),
      _rider('r1', 'B+1', 'B'),
      _rider('s', 'Shadow', 'B'),
      _rider('r2', 'B+2', 'B'),
    ]);

    fixture.move(['B', 'r2', 's', 'r1'], moved: {'r2'});

    expect(fixture.seatsOf('B', _above), ['B+1', 'Shadow', 'B+2']);
    expect(fixture.nameOf('r2'), 'B+1');
  });

  test('a deleted row\'s gap stays a gap — the numbers move with the rows, '
      'they are not packed', () {
    final fixture = _Fixture([
      _base('B'),
      _rider('r1', 'B+1', 'B'),
      _rider('r3', 'B+3', 'B'),
    ]);

    fixture.move(['B', 'r3', 'r1'], moved: {'r3'});

    expect(fixture.nameOf('r3'), 'B+1');
    expect(fixture.nameOf('r1'), 'B+3');
  });

  test('🚨F-436 ③: a row dropped on another base takes that base\'s name, '
      'and a number its side does not wear yet', () {
    final fixture = _Fixture([
      _base('A'),
      _rider('a1', 'A+1', 'A'),
      _base('B'),
      _rider('b1', 'B+1', 'B'),
    ]);

    fixture.move(
      ['A', 'B', 'b1', 'a1'],
      moved: {'a1'},
      attach: _mount('a1', 'B', _above),
    );

    expect(fixture.nameOf('a1'), 'B+2');
    expect(fixture.nameOf('b1'), 'B+1');
  });

  test('a row carried across its base turns its sign with its side', () {
    final fixture = _Fixture([
      _rider('d', 'B-1', 'B', _below),
      _base('B'),
      _rider('u', 'B+1', 'B'),
    ]);

    fixture.move(
      ['B', 'u', 'd'],
      moved: {'d'},
      attach: const LayerAttachDrop(
        sideChanges: [(layerId: LayerId('d'), placement: _above)],
      ),
    );

    expect(fixture.seatsOf('B', _above), ['B+1', 'B+2']);
    expect(fixture.nameOf('d'), 'B+2');
  });

  test('the menu\'s attach renames as the drag does — one law, two doors', () {
    final fixture = _Fixture([
      _base('A'),
      _rider('a1', 'A+1', 'A'),
      _base('B'),
      _rider('b1', 'B+1', 'B'),
    ]);

    fixture.coordinator.setLayerAttachment(
      cutId: _cutId,
      attach: _mount('a1', 'B', _above),
    );

    expect(fixture.seatsOf('B', _above), ['B+1', 'B+2']);
    expect(fixture.nameOf('a1'), startsWith('B+'));
  });

  test('a group the write did not touch keeps its names, gap and order '
      'and all', () {
    final fixture = _Fixture([
      _base('B'),
      _rider('r1', 'B+1', 'B'),
      _rider('r2', 'B+2', 'B'),
      _base('C'),
      _rider('c3', 'C+3', 'C'),
      _rider('c1', 'C+1', 'C'),
    ]);

    fixture.move(['B', 'r2', 'r1', 'C', 'c3', 'c1'], moved: {'r2'});
    expect(fixture.seatsOf('C', _above), ['C+3', 'C+1']);

    // A base moved past another, its riders' seats unchanged.
    fixture.move(['C', 'c3', 'c1', 'B', 'r2', 'r1'], moved: {'C', 'c3', 'c1'});
    expect(fixture.seatsOf('C', _above), ['C+3', 'C+1']);
    expect(fixture.seatsOf('B', _above), ['B+1', 'B+2']);
  });

  test('ONE undo takes back the move and the names together', () {
    final fixture = _Fixture([
      _base('B'),
      _rider('r1', 'B+1', 'B'),
      _rider('r2', 'B+2', 'B'),
    ]);
    final steps = fixture.history.undoCount;

    fixture.move(['B', 'r2', 'r1'], moved: {'r2'});
    expect(fixture.history.undoCount, steps + 1);

    fixture.history.undo();
    expect([for (final layer in fixture.layers) layer.id.value], [
      'B',
      'r1',
      'r2',
    ]);
    expect(fixture.nameOf('r1'), 'B+1');
    expect(fixture.nameOf('r2'), 'B+2');
  });
}
