import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/editing_session_state.dart';
import 'package:anicel/src/models/attached_layer_mount.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 장착·분리 through the coordinator: the MODE decided across every 겸용 use,
/// the per-cut links and per-cut bake, and one undo step for the group.

const _track = TrackId('track-1');
const _cut1 = CutId('cut-1');
const _cut2 = CutId('cut-2');

Layer _row(
  String id, {
  List<(int start, int length, String cel)> blocks = const [],
  Map<String, String> links = const {},
  String? attachedTo,
  AttachedMode mode = AttachedMode.synced,
}) {
  final cels = <String>{for (final block in blocks) block.$3, ...links.values};
  return Layer(
    id: LayerId(id),
    name: id,
    frames: [
      for (final cel in cels)
        Frame(id: FrameId(cel), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final block in blocks)
        block.$1: TimelineExposure.drawing(FrameId(block.$3), length: block.$2),
    },
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    attachedMode: mode,
    baseFrameLinks: {
      for (final entry in links.entries)
        FrameId(entry.key): FrameId(entry.value),
    },
  );
}

Cut _cut(CutId id, List<Layer> layers) => Cut(
  id: id,
  name: id.value,
  layers: layers,
  duration: 8,
  canvasSize: const CanvasSize(width: 1280, height: 720),
);

LayerLinkRegistry _registry(List<(String, String, String)> pairs) {
  return LayerLinkRegistry(
    groups: [
      for (final (group, a, b) in pairs)
        LayerLinkGroup(
          id: group,
          members: [
            LayerLinkMember(trackId: _track, cutId: _cut1, layerId: LayerId(a)),
            LayerLinkMember(trackId: _track, cutId: _cut2, layerId: LayerId(b)),
          ],
        ),
    ],
  );
}

class _Fixture {
  _Fixture(Project project)
    : repository = ProjectRepository(initialProject: project),
      history = HistoryManager() {
    coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: _cut1),
      historyManager: history,
    );
  }

  final ProjectRepository repository;
  final HistoryManager history;
  late final CutCommandCoordinator coordinator;

  Project get project => repository.requireProject();

  Layer layer(CutId cutId, String id) =>
      requireLayer(project, cutId: cutId, layerId: LayerId(id));

  List<(int, int, String)> blocks(CutId cutId, String id) => [
    for (final entry in layer(cutId, id).timeline.entries)
      if (!entry.value.ghost)
        (entry.key, entry.value.length!, entry.value.frameId!.value),
  ];
}

_Fixture _fixture({
  required List<Layer> cut1,
  List<Layer>? cut2,
  LayerLinkRegistry? registry,
}) {
  return _Fixture(
    Project(
      id: const ProjectId('project-1'),
      name: 'Project',
      createdAt: DateTime.utc(2024),
      linkRegistry: registry ?? LayerLinkRegistry.empty,
      tracks: [
        Track(
          id: _track,
          name: 'Video',
          cuts: [
            _cut(_cut1, cut1),
            if (cut2 != null) _cut(_cut2, cut2),
          ],
        ),
      ],
    ),
  );
}

LayerAttachDrop _mount(String row, String base, [AttachedPlacement? side]) =>
    LayerAttachDrop(
      // ⑦ made this a list — a folder drop mounts every member it carries.
      // One rider is still the ordinary case.
      mounts: [
        (
          layerId: LayerId(row),
          baseId: LayerId(base),
          placement: side ?? AttachedPlacement.above,
        ),
      ],
    );

void main() {
  group('the MODE is decided across every use', () {
    test('SYNCED when the row already exposes what the base does — and the '
        'links are COMPLETE, so the always-mirror pass publishes no empty '
        'cel', () {
      final fixture = _fixture(
        cut1: [
          _row('base', blocks: [(0, 2, 'b1'), (2, 1, 'b2')]),
          _row('row', blocks: [(0, 2, 'r1'), (2, 1, 'r2')]),
        ],
      );
      final celsBefore = fixture.layer(_cut1, 'row').frames.length;

      fixture.coordinator.setLayerAttachment(
        cutId: _cut1,
        attach: _mount('row', 'base'),
      );

      final row = fixture.layer(_cut1, 'row');
      expect(row.attachedToLayerId, const LayerId('base'));
      expect(row.attachedMode, AttachedMode.synced);
      expect(row.timeline, isEmpty, reason: 'the base owns the timing now');
      expect(row.baseFrameLinks, {
        const FrameId('b1'): const FrameId('r1'),
        const FrameId('b2'): const FrameId('r2'),
      });
      // THE oracle for completeness: a forgotten link does not stay
      // forgotten — the repository mints `attach-mirror-…` for it.
      expect(row.frames, hasLength(celsBefore));
      expect(
        row.frames.where((frame) => frame.id.value.startsWith('attach-mirror')),
        isEmpty,
      );
    });

    test('FREE when the row has timing of its own — and that timing survives', () {
      final fixture = _fixture(
        cut1: [
          _row('base', blocks: [(0, 2, 'b1'), (2, 1, 'b2')]),
          _row('row', blocks: [(4, 3, 'r1')]),
        ],
      );

      fixture.coordinator.setLayerAttachment(
        cutId: _cut1,
        attach: _mount('row', 'base'),
      );

      final row = fixture.layer(_cut1, 'row');
      expect(row.attachedMode, AttachedMode.free);
      expect(row.baseFrameLinks, isEmpty);
      expect(fixture.blocks(_cut1, 'row'), [(4, 3, 'r1')]);
    });

    test('an EMPTY row on an EMPTY base is SYNCED — nothing to lose', () {
      final fixture = _fixture(
        cut1: [_row('base'), _row('row')],
      );
      fixture.coordinator.setLayerAttachment(
        cutId: _cut1,
        attach: _mount('row', 'base'),
      );
      expect(fixture.layer(_cut1, 'row').attachedMode, AttachedMode.synced);
    });

    test('ONE 겸용 sibling disagreeing makes the WHOLE mount free — the cut '
        'where the row has real work does not get it replaced', () {
      final fixture = _fixture(
        cut1: [
          _row('base', blocks: [(0, 2, 'b1')]),
          _row('row', blocks: [(0, 2, 'r1')]), // agrees here
        ],
        cut2: [
          _row('base2', blocks: [(0, 2, 'b1')]),
          _row('row2', blocks: [(3, 1, 'r1')]), // its own rhythm
        ],
        registry: _registry([
          ('g-base', 'base', 'base2'),
          ('g-row', 'row', 'row2'),
        ]),
      );

      fixture.coordinator.setLayerAttachment(
        cutId: _cut1,
        attach: _mount('row', 'base'),
      );

      expect(fixture.layer(_cut1, 'row').attachedMode, AttachedMode.free);
      expect(fixture.layer(_cut2, 'row2').attachedMode, AttachedMode.free);
      expect(fixture.blocks(_cut2, 'row2'), [(3, 1, 'r1')]);
    });

    test('the relation MIRRORS onto the sibling — pointing at the sibling\'s '
        'own base — as ONE undo step', () {
      final fixture = _fixture(
        cut1: [
          _row('base', blocks: [(0, 2, 'b1')]),
          _row('row', blocks: [(0, 2, 'r1')]),
        ],
        cut2: [
          _row('base2', blocks: [(0, 2, 'b1')]),
          _row('row2', blocks: [(0, 2, 'r1')]),
        ],
        registry: _registry([
          ('g-base', 'base', 'base2'),
          ('g-row', 'row', 'row2'),
        ]),
      );

      fixture.coordinator.setLayerAttachment(
        cutId: _cut1,
        attach: _mount('row', 'base', AttachedPlacement.below),
      );

      expect(fixture.history.undoCount, 1);
      expect(fixture.layer(_cut2, 'row2').attachedToLayerId, const LayerId('base2'));
      expect(
        fixture.layer(_cut2, 'row2').attachedPlacement,
        AttachedPlacement.below,
      );
      expect(fixture.layer(_cut1, 'row').attachedMode, AttachedMode.synced);
      expect(fixture.layer(_cut2, 'row2').attachedMode, AttachedMode.synced);

      fixture.history.undo();

      expect(fixture.layer(_cut1, 'row').attachedToLayerId, isNull);
      expect(fixture.layer(_cut2, 'row2').attachedToLayerId, isNull);
      expect(fixture.blocks(_cut1, 'row'), [(0, 2, 'r1')]);
      expect(fixture.blocks(_cut2, 'row2'), [(0, 2, 'r1')]);
    });

    test('a sibling the BASE does not reach is left alone and does not vote', () {
      final fixture = _fixture(
        cut1: [
          _row('base', blocks: [(0, 2, 'b1')]),
          _row('row', blocks: [(0, 2, 'r1')]),
        ],
        cut2: [
          // No counterpart for the base here, and this row's own rhythm
          // would have forced FREE if the cut counted as a use.
          _row('row2', blocks: [(5, 1, 'r1')]),
        ],
        registry: _registry([('g-row', 'row', 'row2')]),
      );

      fixture.coordinator.setLayerAttachment(
        cutId: _cut1,
        attach: _mount('row', 'base'),
      );

      expect(fixture.layer(_cut1, 'row').attachedMode, AttachedMode.synced);
      expect(fixture.layer(_cut2, 'row2').attachedToLayerId, isNull);
    });
  });

  group('detaching', () {
    test('BAKES each cut against ITS OWN base — one cut\'s rhythm is never '
        'dressed onto another', () {
      final fixture = _fixture(
        cut1: [
          _row('base', blocks: [(0, 2, 'b1'), (2, 1, 'b2')]),
          _row('row', attachedTo: 'base', links: {'b1': 'r1', 'b2': 'r2'}),
        ],
        cut2: [
          // Same cel bank, re-exposed to a different rhythm (겸용).
          _row('base2', blocks: [(1, 1, 'b1'), (4, 3, 'b2')]),
          _row('row2', attachedTo: 'base2', links: {'b1': 'r1', 'b2': 'r2'}),
        ],
        registry: _registry([
          ('g-base', 'base', 'base2'),
          ('g-row', 'row', 'row2'),
        ]),
      );

      fixture.coordinator.setLayerAttachment(
        cutId: _cut1,
        attach: LayerAttachDrop(detachIds: {const LayerId('row')}),
        description: 'Detach layer',
      );

      expect(fixture.layer(_cut1, 'row').attachedToLayerId, isNull);
      expect(fixture.layer(_cut2, 'row2').attachedToLayerId, isNull);
      expect(fixture.blocks(_cut1, 'row'), [(0, 2, 'r1'), (2, 1, 'r2')]);
      expect(fixture.blocks(_cut2, 'row2'), [(1, 1, 'r1'), (4, 3, 'r2')]);
      expect(fixture.history.undoCount, 1);
    });

    test('undo puts the row back on the base, mirror and all', () {
      final fixture = _fixture(
        cut1: [
          _row('base', blocks: [(0, 2, 'b1'), (2, 1, 'b2')]),
          _row('row', attachedTo: 'base', links: {'b1': 'r1', 'b2': 'r2'}),
        ],
      );

      fixture.coordinator.setLayerAttachment(
        cutId: _cut1,
        attach: LayerAttachDrop(detachIds: {const LayerId('row')}),
      );
      fixture.history.undo();

      final row = fixture.layer(_cut1, 'row');
      expect(row.attachedToLayerId, const LayerId('base'));
      expect(row.attachedMode, AttachedMode.synced);
      expect(row.timeline, isEmpty);
      expect(row.baseFrameLinks, hasLength(2));
      expect(
        row.frames.where((frame) => frame.id.value.startsWith('attach-mirror')),
        isEmpty,
        reason: 'the links were complete, so nothing had to be minted',
      );
    });

    test('a row that rides nothing is not an undo entry', () {
      final fixture = _fixture(cut1: [_row('base'), _row('row')]);
      fixture.coordinator.setLayerAttachment(
        cutId: _cut1,
        attach: LayerAttachDrop(detachIds: {const LayerId('row')}),
      );
      expect(fixture.history.undoCount, 0);
    });
  });

  test('a move and the attach change it made are ONE undo step', () {
    final fixture = _fixture(
      cut1: [
        _row('base', blocks: [(0, 2, 'b1')]),
        _row('over', attachedTo: 'base', links: {'b1': 'o1'}),
        _row('row', blocks: [(0, 2, 'r1')]),
      ],
    );

    // What a drop strictly inside the group commits: the order AND the mount.
    fixture.coordinator.setLayerPlacement(
      cutId: _cut1,
      order: const [LayerId('base'), LayerId('row'), LayerId('over')],
      movedIds: {const LayerId('row')},
      attach: _mount('row', 'base'),
      description: 'Move layer',
    );

    expect(fixture.history.undoCount, 1);
    expect(
      requireCut(fixture.project, _cut1).layers.map((layer) => layer.id.value),
      ['base', 'row', 'over'],
    );
    expect(fixture.layer(_cut1, 'row').attachedToLayerId, const LayerId('base'));

    fixture.history.undo();

    expect(
      requireCut(fixture.project, _cut1).layers.map((layer) => layer.id.value),
      ['base', 'over', 'row'],
    );
    expect(fixture.layer(_cut1, 'row').attachedToLayerId, isNull);
  });
}
