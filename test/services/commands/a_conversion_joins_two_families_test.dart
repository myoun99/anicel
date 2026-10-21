import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
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
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🗣️F-398 (유저 2026-10-18): 「관련 링크안되는것들 다른것도 조사 법 통일」 —
/// ⑤ a cut converted to 겸용 with a cut that is 겸용 already: the two
/// families become one. A row stands in one link group, the target's
/// siblings take what the target takes, and every picture is read where it
/// lies — before the conversion, after it and after its undo.
void main() {
  const track = TrackId('t');
  const origin = CutId('origin');
  const sibling = CutId('sibling');
  const target = CutId('target');
  const targetSibling = CutId('target-sibling');

  Frame frame(String id, String name) =>
      Frame(id: FrameId(id), name: name, duration: 1, strokes: const []);

  /// An 'A' row drawing [frames], each exposed in turn from frame 0.
  Layer rowA(String id, List<Frame> frames) => Layer(
    id: LayerId(id),
    name: 'A',
    frames: frames,
    timeline: {
      for (final (index, drawn) in frames.indexed)
        index * 3: TimelineExposure.drawing(drawn.id, length: 3),
    },
  );

  Layer row(String id, String name) =>
      Layer(id: LayerId(id), name: name, frames: const []);

  Cut cut(CutId id, List<Layer> layers) => Cut(
    id: id,
    name: id.value,
    layers: layers,
    duration: 12,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  LayerLinkMember member(CutId cutId, String layer) =>
      LayerLinkMember(trackId: track, cutId: cutId, layerId: LayerId(layer));

  LayerLinkGroup group(String id, List<LayerLinkMember> members) =>
      LayerLinkGroup(id: id, members: members);

  final originFrames = [frame('f-o1', '1')];
  final targetFrames = [frame('f-t1', '1'), frame('f-t2', '2')];

  /// Two families: the origin and its sibling share A and C, the target and
  /// its sibling share A and B — the target's sibling holding A's pictures
  /// ([targetSiblingFirst]) or the target holding them.
  ProjectRepository twoFamilies({
    bool targetSiblingFirst = true,
    bool originSiblingFirst = false,
  }) {
    final originA = member(origin, 'a-origin');
    final siblingA = member(sibling, 'a-sibling');
    final targetA = member(target, 'a-target');
    final targetSiblingA = member(targetSibling, 'a-target-sibling');
    return ProjectRepository(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 10, 21),
        tracks: [
          Track(
            id: track,
            name: 'V',
            cuts: [
              cut(origin, [
                rowA('a-origin', originFrames),
                row('c-origin', 'C'),
              ]),
              cut(sibling, [
                rowA('a-sibling', originFrames),
                row('c-sibling', 'C'),
              ]),
              cut(target, [
                rowA('a-target', targetFrames),
                row('b-target', 'B'),
              ]),
              cut(targetSibling, [
                rowA('a-target-sibling', targetFrames),
                row('b-target-sibling', 'B'),
              ]),
            ],
          ),
        ],
        linkRegistry: LayerLinkRegistry(
          groups: [
            group(
              'link-a',
              originSiblingFirst
                  ? [siblingA, originA]
                  : [originA, siblingA],
            ),
            group('link-c', [
              member(origin, 'c-origin'),
              member(sibling, 'c-sibling'),
            ]),
            group(
              'link-target-a',
              targetSiblingFirst
                  ? [targetSiblingA, targetA]
                  : [targetA, targetSiblingA],
            ),
            group('link-target-b', [
              member(target, 'b-target'),
              member(targetSibling, 'b-target-sibling'),
            ]),
          ],
        ),
      ),
    );
  }

  /// A store that reads a cel where its row's group keeps it, as the
  /// session wires it.
  BrushFrameStore storeOf(ProjectRepository repository) => BrushFrameStore()
    ..setLinkResolver(
      (key) =>
          repository.currentProject?.linkRegistry.canonicalCelKey(key) ?? key,
    );

  BrushFrameKey keyOf(CutId cutId, String layer, String frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('p'),
        trackId: track,
        cutId: cutId,
        layerId: LayerId(layer),
        frameId: FrameId(frameId),
      );

  void convert(
    ProjectRepository repository,
    HistoryManager history,
    BrushFrameStore store,
  ) => CutCommandCoordinator(
    repository: repository,
    editingSession: EditingSessionState(activeCutId: origin),
    historyManager: history,
    brushFrameStore: store,
  ).convertCutToLinked(originCutId: origin, targetCutId: target);

  List<Layer> layersIn(ProjectRepository repository, CutId id) => repository
      .requireProject()
      .tracks
      .single
      .cuts
      .firstWhere((cut) => cut.id == id)
      .layers;

  Layer layerIn(ProjectRepository repository, CutId id, String layer) =>
      layersIn(repository, id).firstWhere((it) => it.id == LayerId(layer));

  LayerLinkRegistry registryOf(ProjectRepository repository) =>
      repository.requireProject().linkRegistry;

  test('🚨every row stands in one link group: the A rows of both families '
      'are one group, the origin\'s pictures first', () {
    final repository = twoFamilies();
    convert(repository, HistoryManager(), storeOf(repository));

    final registry = registryOf(repository);
    final memberships = <(CutId, LayerId), int>{};
    for (final linked in registry.groups) {
      for (final each in linked.members) {
        memberships.update(
          (each.cutId, each.layerId),
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    expect(
      {
        for (final entry in memberships.entries)
          if (entry.value > 1) entry.key,
      },
      isEmpty,
    );
    final family = registry.groupOf(
      cutId: target,
      layerId: const LayerId('a-target'),
    )!;
    expect(family.members.map((each) => each.layerId), [
      const LayerId('a-origin'),
      const LayerId('a-sibling'),
      const LayerId('a-target-sibling'),
      const LayerId('a-target'),
    ]);
  });

  test('the target\'s sibling wears the pictures the target wears — a '
      'drawing the origin\'s supersedes is the origin\'s there too', () {
    final repository = twoFamilies();
    convert(repository, HistoryManager(), storeOf(repository));

    for (final (cutId, layer) in [
      (target, 'a-target'),
      (targetSibling, 'a-target-sibling'),
    ]) {
      final row = layerIn(repository, cutId, layer);
      expect(row.timeline[0]!.frameId, const FrameId('f-o1'), reason: layer);
      expect(row.timeline[3]!.frameId, const FrameId('f-t2'), reason: layer);
      expect(row.frames.map((drawn) => drawn.id.value), ['f-o1', 'f-t2']);
    }
  });

  test('a row only the origin holds lands in the target\'s sibling too, '
      'linked with the rest of its group', () {
    final repository = twoFamilies();
    convert(repository, HistoryManager(), storeOf(repository));

    final registry = registryOf(repository);
    final copy = registry.counterpartIn(
      cutId: origin,
      layerId: const LayerId('c-origin'),
      targetCutId: targetSibling,
    );
    expect(copy, isNotNull);
    expect(
      layersIn(repository, targetSibling).map((it) => it.id),
      contains(copy),
    );
    expect(
      registry
          .groupOf(cutId: origin, layerId: const LayerId('c-origin'))!
          .members
          .map((each) => each.cutId),
      unorderedEquals([origin, sibling, target, targetSibling]),
    );
    expect(
      registry
          .groupOf(cutId: target, layerId: const LayerId('b-target'))!
          .members
          .map((each) => each.cutId),
      unorderedEquals([target, targetSibling, origin, sibling]),
      reason: 'the target\'s sibling had B already — no second copy',
    );
  });

  for (final targetSiblingFirst in [true, false]) {
    final keeper = targetSiblingFirst ? 'the target\'s sibling' : 'the target';
    test('a drawing the target brings is read on both families\' rows when '
        '$keeper kept it — and where it was again after the undo', () {
      final repository = twoFamilies(targetSiblingFirst: targetSiblingFirst);
      final store = storeOf(repository);
      final history = HistoryManager();
      final lay = store.getOrCreateFrame(keyOf(target, 'a-target', 'f-t2')).key;
      expect(
        lay.cutId,
        targetSiblingFirst ? targetSibling : target,
        reason: '⛔premise: it lies where its family keeps it',
      );

      convert(repository, history, store);
      for (final (cutId, layer) in [
        (origin, 'a-origin'),
        (target, 'a-target'),
        (targetSibling, 'a-target-sibling'),
      ]) {
        expect(
          store.frameOrNull(keyOf(cutId, layer, 'f-t2'))?.key,
          keyOf(origin, 'a-origin', 'f-t2'),
          reason: '$layer reads it where the origin keeps its pictures',
        );
      }

      history.undo();
      expect(store.frameOrNull(keyOf(target, 'a-target', 'f-t2'))?.key, lay);
      expect(
        store.frameOrNull(keyOf(origin, 'a-origin', 'f-t2')),
        isNull,
        reason: 'the origin\'s row lets go of it again',
      );
    });
  }

  test('…and when the origin is not the one of its family that keeps the '
      'pictures, the drawing goes where the family keeps them', () {
    final repository = twoFamilies(originSiblingFirst: true);
    final store = storeOf(repository);
    store.getOrCreateFrame(keyOf(target, 'a-target', 'f-t2'));

    convert(repository, HistoryManager(), store);

    for (final (cutId, layer) in [
      (origin, 'a-origin'),
      (sibling, 'a-sibling'),
      (target, 'a-target'),
    ]) {
      expect(
        store.frameOrNull(keyOf(cutId, layer, 'f-t2'))?.key,
        keyOf(sibling, 'a-sibling', 'f-t2'),
        reason: layer,
      );
    }
  });

  test('one undo gives every cut its rows and the registry its groups '
      'back', () {
    final repository = twoFamilies();
    final before = repository.requireProject();
    final history = HistoryManager();
    convert(repository, history, storeOf(repository));

    history.undo();

    final after = repository.requireProject();
    expect(after.linkRegistry, before.linkRegistry);
    for (final cutId in [origin, sibling, target, targetSibling]) {
      expect(
        layersIn(repository, cutId),
        before.tracks.single.cuts.firstWhere((it) => it.id == cutId).layers,
        reason: cutId.value,
      );
    }
  });
}
