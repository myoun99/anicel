import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/convert_to_linked_cut_command.dart';
import 'package:anicel/src/services/commands/create_linked_cut_command.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/commands/cut_command_input_planner.dart';
import 'package:anicel/src/services/commands/import_media_command.dart';
import 'package:anicel/src/services/commands/link_duplicate_layer_command.dart';
import 'package:anicel/src/services/editing/cut_duplicate_helpers.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// A copy of rows names its own rows: the row an effect names
/// ([LayerEffect.layers] — a camera lens blur's blur map, 🗣️I-132-Q16 a)
/// is re-named at every site that copies rows, as the attach pointer is
/// beside it — the copy's where the row came along, the row it was where
/// the copy stands in the same cut, and none where neither is there.
void main() {
  const map = 'blurMapLayer';
  const a = CutId('a');
  const b = CutId('b');
  const track = TrackId('t');

  /// A camera lens blur naming [row] for its blur map.
  LayerEffect lensOn(String row, {String id = 'lens'}) => LayerEffect.defaults(
    id: EffectId(id),
    kind: EffectKind.cameraLensBlur,
  ).withLayer(map, LayerId(row));

  Layer row(
    String id, {
    List<LayerEffect> effects = const [],
    LayerKind kind = LayerKind.animation,
    String? on,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    kind: kind,
    effects: effects,
    onTimesheet: on == null,
    attachedToLayerId: on == null ? null : LayerId(on),
    attachedPlacement: AttachedPlacement.above,
  );

  /// The row [layer]'s first effect names.
  LayerId? namedBy(Layer layer) => layer.effects.first.layers[map];

  Cut cut(CutId id, List<Layer> layers) => Cut(
    id: id,
    name: id.value,
    layers: layers,
    duration: 4,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  ProjectRepository repositoryOf(
    List<Cut> cuts, {
    List<LayerLinkGroup> links = const [],
  }) => ProjectRepository(
    initialProject: Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 10, 29),
      tracks: [Track(id: track, name: 'V', cuts: cuts)],
      linkRegistry: LayerLinkRegistry(groups: links),
    ),
  );

  LayerLinkGroup linked(String id, String inA, String inB) => LayerLinkGroup(
    id: id,
    members: [
      LayerLinkMember(trackId: track, cutId: a, layerId: LayerId(inA)),
      LayerLinkMember(trackId: track, cutId: b, layerId: LayerId(inB)),
    ],
  );

  Layer rowIn(ProjectRepository repository, CutId cutId, String id) =>
      repository
          .requireProject()
          .tracks
          .single
          .cuts
          .firstWhere((cut) => cut.id == cutId)
          .layers
          .firstWhere((layer) => layer.id.value == id);

  test('a duplicated cut\'s rows name the copies; a row copied alone in '
      'its cut names the row it did', () {
    final source = cut(a, [row('map'), row('lens', effects: [lensOn('map')])]);
    final copy = duplicateCutAsIndependentCopy(
      source: source,
      newCutId: b,
      newName: 'b',
      layerIdMap: {
        const LayerId('map'): const LayerId('map·2'),
        const LayerId('lens'): const LayerId('lens·2'),
      },
      frameIdMap: const <FrameId, FrameId>{},
    );
    expect(namedBy(copy.layers.last), const LayerId('map·2'));

    final alone = duplicateLayerAsIndependentCopy(
      source: source.layers.last,
      newLayerId: const LayerId('lens·3'),
      newName: 'lens',
      frameIdMap: const {},
    );
    expect(namedBy(alone), const LayerId('map'));
  });

  test('a linked cut\'s rows name the copies, and none where the row they '
      'named does not come along', () {
    final repository = repositoryOf([
      cut(a, [
        row('map'),
        row('stays'),
        row('lens', effects: [lensOn('map')]),
        row('lens2', effects: [lensOn('stays', id: 'lens2')]),
      ]),
    ]);
    CreateLinkedCutCommand(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: a),
      sourceCutId: a,
      newCutId: b,
      newName: 'b',
      layerIdMap: {
        const LayerId('map'): const LayerId('map·2'),
        const LayerId('lens'): const LayerId('lens·2'),
        const LayerId('lens2'): const LayerId('lens2·2'),
      },
      newGroupIdBySource: {
        const LayerId('map'): 'g-map',
        const LayerId('lens'): 'g-lens',
        const LayerId('lens2'): 'g-lens2',
      },
      coveringFrameIdBySource: const {},
    ).execute();
    expect(namedBy(rowIn(repository, b, 'lens·2')), const LayerId('map·2'));
    expect(namedBy(rowIn(repository, b, 'lens2·2')), isNull);
    expect(namedBy(rowIn(repository, a, 'lens')), const LayerId('map'));
  });

  test('a link duplicate\'s copies name the group\'s copies, and a row out '
      'of the group the row it did', () {
    final repository = repositoryOf([
      cut(a, [
        row('out'),
        row('base', effects: [lensOn('rider')]),
        row('rider', on: 'base', effects: [lensOn('out', id: 'lens2')]),
      ]),
    ]);
    LinkDuplicateLayerCommand(
      repository: repository,
      cutId: a,
      sourceLayerId: const LayerId('base'),
      insertionIndex: 3,
      layerIdMap: {
        const LayerId('base'): const LayerId('base·2'),
        const LayerId('rider'): const LayerId('rider·2'),
      },
      newGroupIdBySource: {
        const LayerId('base'): 'g-base',
        const LayerId('rider'): 'g-rider',
      },
    ).execute();
    expect(namedBy(rowIn(repository, a, 'base·2')), const LayerId('rider·2'));
    expect(namedBy(rowIn(repository, a, 'rider·2')), const LayerId('out'));
  });

  test('a 겸용 change\'s copies name their counterparts — made before or '
      'after them — and none where the row reaches no row there', () {
    final repository = repositoryOf([
      // The lens below its map: its copy is made first.
      cut(a, [
        row('lens', effects: [lensOn('map')]),
        row('map'),
        row('lens2', effects: [lensOn('gone', id: 'lens2')]),
      ]),
      cut(b, [row('other')]),
    ]);
    final project = repository.requireProject();
    final cuts = project.tracks.single.cuts;
    final input = planConvertToLinkedCutCommandInput(
      project: project,
      originCut: cuts.first,
      targetCut: cuts.last,
    );
    ConvertToLinkedCutCommand(
      repository: repository,
      brushFrameStore: BrushFrameStore(),
      originCutId: a,
      targetCutId: b,
      unionLayerIdMap: input.unionLayerIdMap,
      newGroupIdBySource: input.newGroupIdBySource,
      coveringFrameIdBySource: input.coveringFrameIdBySource,
    ).execute();
    final registry = repository.requireProject().linkRegistry;
    LayerId? inB(String id) => registry.counterpartIn(
      cutId: a,
      layerId: LayerId(id),
      targetCutId: b,
    );
    expect(
      namedBy(rowIn(repository, b, inB('lens')!.value)),
      inB('map'),
      reason: 'fixture: the map came along',
    );
    expect(inB('map'), isNotNull);
    expect(namedBy(rowIn(repository, b, inB('lens2')!.value)), isNull);
    expect(namedBy(rowIn(repository, a, 'lens')), const LayerId('map'));
  });

  test('a row put in a 겸용 cut lands in its sibling naming the sibling\'s '
      'rows: a copy of its batch, or a row already linked there', () {
    final repository = repositoryOf(
      [
        cut(a, [row('shared-a')]),
        cut(b, [row('shared-b')]),
      ],
      links: [linked('link-0', 'shared-a', 'shared-b')],
    );
    final rows = [
      row('mask'),
      row('lens', effects: [lensOn('mask')]),
      row('lens2', effects: [lensOn('shared-a', id: 'lens2')]),
    ];
    ImportMediaCommand(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: a),
      targetCutId: a,
      newLayers: rows,
      layerPlans: planAddLayersCommandInput(
        project: repository.requireProject(),
        cutId: a,
        layers: rows,
      ),
    ).execute();
    final registry = repository.requireProject().linkRegistry;
    LayerId? inB(String id) => registry.counterpartIn(
      cutId: a,
      layerId: LayerId(id),
      targetCutId: b,
    );
    expect(namedBy(rowIn(repository, b, inB('lens')!.value)), inB('mask'));
    expect(inB('mask'), isNotNull);
    expect(
      namedBy(rowIn(repository, b, inB('lens2')!.value)),
      const LayerId('shared-b'),
    );
  });

  group('an effect edit in a 겸용 cut', () {
    ProjectRepository linkedRows(List<LayerEffect> celEffects) => repositoryOf(
      [
        cut(a, [
          row('map-a'),
          row('adj-a', kind: LayerKind.adjustment),
          row('cel-a', effects: celEffects),
        ]),
        cut(b, [
          row('map-b'),
          row('adj-b', kind: LayerKind.adjustment),
          row('cel-b', effects: celEffects),
        ]),
      ],
      links: [
        linked('g-map', 'map-a', 'map-b'),
        linked('g-adj', 'adj-a', 'adj-b'),
        linked('g-cel', 'cel-a', 'cel-b'),
      ],
    );

    void write(ProjectRepository repository, String id, LayerEffect effect) {
      final commands =
          CutCommandCoordinator(
            repository: repository,
            editingSession: EditingSessionState(activeCutId: a),
            historyManager: HistoryManager(),
          ).layerEffectsCommands(
            cutId: a,
            layerId: LayerId(id),
            effects: [effect],
          );
      for (final command in commands) {
        command.execute();
      }
    }

    test('an adjustment row\'s, whose values mirror, names the sibling\'s '
        'counterpart', () {
      final repository = linkedRows(const []);
      write(repository, 'adj-a', lensOn('map-a'));
      expect(namedBy(rowIn(repository, b, 'adj-b')), const LayerId('map-b'));
      expect(namedBy(rowIn(repository, a, 'adj-a')), const LayerId('map-a'));
    });

    test('a drawing row\'s keeps the sibling\'s own row — its values are '
        'its own — but an effect new there arrives naming the counterpart', () {
      final lens = LayerEffect.defaults(
        id: const EffectId('lens'),
        kind: EffectKind.cameraLensBlur,
      );
      final kept = linkedRows([lens]);
      write(kept, 'cel-a', lens.withLayer(map, const LayerId('map-a')));
      expect(namedBy(rowIn(kept, a, 'cel-a')), const LayerId('map-a'));
      expect(namedBy(rowIn(kept, b, 'cel-b')), isNull);

      final arrives = linkedRows(const []);
      write(arrives, 'cel-a', lensOn('map-a'));
      expect(namedBy(rowIn(arrives, b, 'cel-b')), const LayerId('map-b'));
    });
  });
}
