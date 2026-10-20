import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🗣️F-398 (유저 2026-10-18): 「관련 링크안되는것들 다른것도 조사 법 통일」 —
/// a cut converted to 겸용 with a cut that already has a sibling: the rows
/// the origin takes in from it are added rows there, and the sibling takes
/// them too.
void main() {
  const origin = CutId('origin');
  const sibling = CutId('sibling');
  const target = CutId('target');

  Layer row(String id, String name) =>
      Layer(id: LayerId(id), name: name, frames: const []);

  Cut cut(CutId id, List<Layer> layers) => Cut(
    id: id,
    name: id.value,
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  LayerLinkMember member(CutId cutId, String layer) => LayerLinkMember(
    trackId: const TrackId('t'),
    cutId: cutId,
    layerId: LayerId(layer),
  );

  List<LayerId> idsIn(ProjectRepository repository, CutId id) => [
    for (final layer
        in repository
            .requireProject()
            .tracks
            .single
            .cuts
            .firstWhere((cut) => cut.id == id)
            .layers)
      layer.id,
  ];

  test('a row only the target holds lands in the origin\'s sibling too, '
      'linked with it — and the undo takes it back', () {
    final repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 21),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              cut(origin, [row('a-origin', 'A')]),
              cut(sibling, [row('a-sibling', 'A')]),
              cut(target, [row('a-target', 'A'), row('b-target', 'B')]),
            ],
          ),
        ],
        linkRegistry: LayerLinkRegistry(
          groups: [
            LayerLinkGroup(
              id: 'link-a',
              members: [
                member(origin, 'a-origin'),
                member(sibling, 'a-sibling'),
              ],
            ),
          ],
        ),
      ),
    );
    final history = HistoryManager();
    final coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: origin),
      historyManager: history,
      brushFrameStore: BrushFrameStore(),
    );

    coordinator.convertCutToLinked(originCutId: origin, targetCutId: target);

    final registry = repository.requireProject().linkRegistry;
    final inOrigin = registry.counterpartIn(
      cutId: target,
      layerId: const LayerId('b-target'),
      targetCutId: origin,
    );
    final inSibling = registry.counterpartIn(
      cutId: target,
      layerId: const LayerId('b-target'),
      targetCutId: sibling,
    );
    expect(inOrigin, isNotNull, reason: '⛔전제: the origin took it');
    expect(idsIn(repository, sibling), [const LayerId('a-sibling'), inSibling]);
    expect(inSibling, isNot(inOrigin));
    expect(
      registry
          .groupOf(cutId: target, layerId: const LayerId('a-target'))
          ?.members
          .map((member) => member.layerId),
      unorderedEquals([
        const LayerId('a-origin'),
        const LayerId('a-sibling'),
        const LayerId('a-target'),
      ]),
      reason: 'the pair joined the group the sibling stands in already',
    );

    history.undo();
    expect(idsIn(repository, sibling), [const LayerId('a-sibling')]);
    expect(idsIn(repository, origin), [const LayerId('a-origin')]);

    history.redo();
    expect(idsIn(repository, sibling).last, inSibling, reason: 'the same row');
  });

  test('a target the origin is 겸용 with already is no sibling of its own: '
      'its row is not copied into it again', () {
    final repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 21),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              cut(origin, [row('a-origin', 'A')]),
              cut(target, [row('a-target', 'A'), row('b-target', 'B')]),
            ],
          ),
        ],
        linkRegistry: LayerLinkRegistry(
          groups: [
            LayerLinkGroup(
              id: 'link-a',
              members: [member(origin, 'a-origin'), member(target, 'a-target')],
            ),
          ],
        ),
      ),
    );
    final coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: origin),
      historyManager: HistoryManager(),
      brushFrameStore: BrushFrameStore(),
    );

    coordinator.convertCutToLinked(originCutId: origin, targetCutId: target);

    expect(idsIn(repository, target), [
      const LayerId('a-target'),
      const LayerId('b-target'),
    ]);
    expect(idsIn(repository, origin), hasLength(2), reason: 'B came over');
  });
}
