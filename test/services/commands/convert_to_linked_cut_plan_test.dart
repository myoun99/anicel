import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/convert_to_linked_cut_plan.dart';

void main() {
  Frame frame(String id, {String? name}) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  Layer layer(String id, String name, List<Frame> frames) =>
      Layer(id: LayerId(id), name: name, frames: frames, timeline: const {});

  Cut cut(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    layers: layers,
    duration: 24,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  Project project(List<Cut> cuts) => Project(
    id: const ProjectId('p'),
    name: 'P',
    tracks: [Track(id: const TrackId('t'), name: 'V', cuts: cuts)],
    createdAt: DateTime.utc(2026),
  );

  group('resolveLayerMerge (원본 승리)', () {
    test('same id = shared already; same name different id = RETARGET; '
        'target-only and unnamed frames JOIN', () {
      final origin = layer('a', 'cel', [
        frame('f-shared'),
        frame('f-origin-1', name: '1'),
      ]);
      final target = layer('b', 'cel', [
        frame('f-shared'), // identical id — already one cel
        frame('f-target-1', name: '1'), // name conflict → retarget
        frame('f-target-2', name: '2'), // target-only name → join
        frame('f-unnamed'), // unnamed → join (no identity to clash)
      ]);

      final resolution = resolveLayerMerge(origin: origin, target: target);
      expect(resolution.retargetedFrameIds, {
        const FrameId('f-target-1'): const FrameId('f-origin-1'),
      });
      expect(resolution.joiningFrameIds, [
        const FrameId('f-target-2'),
        const FrameId('f-unnamed'),
      ]);
    });
  });

  group('planConvertToLinkedCut', () {
    test('name-matches layers, counts replacements and joins, and lists '
        'one-side-only layers for the union', () {
      final origin = cut('origin', [
        layer('a1', 'cel-A', [frame('f1', name: '1')]),
        layer('a2', 'only-origin', const []),
      ]);
      final target = cut('target', [
        layer('b1', 'cel-A', [frame('f2', name: '1'), frame('f3', name: '2')]),
        layer('b2', 'only-target', const []),
      ]);

      final plan = planConvertToLinkedCut(
        project: project([origin, target]),
        originCut: origin,
        targetCut: target,
      );

      expect(plan.layerPairs, [
        (originLayerId: const LayerId('a1'), targetLayerId: const LayerId('b1')),
      ]);
      expect(plan.originOnlyLayerIds, [const LayerId('a2')]);
      expect(plan.targetOnlyLayerIds, [const LayerId('b2')]);
      expect(plan.replacedFrameCount, 1, reason: 'name "1" conflicts');
      expect(plan.joiningFrameCount, 1, reason: 'name "2" joins');
      expect(plan.linksAnything, isTrue);
    });

    test('the SINGLETON kinds pair by KIND — one conte row and one camera '
        'row a cut, whatever they are called (F-84)', () {
      Layer row(String id, String name, LayerKind kind) => Layer(
        id: LayerId(id),
        name: name,
        frames: const [],
        timeline: const {},
        kind: kind,
      );
      final origin = cut('origin', [
        row('a-conte', 'B', LayerKind.storyboard),
        row('a-cam', 'Camera', LayerKind.camera),
      ]);
      final target = cut('target', [
        row('b-conte', 'Conte', LayerKind.storyboard),
        row('b-cam', 'Cam', LayerKind.camera),
      ]);

      final plan = planConvertToLinkedCut(
        project: project([origin, target]),
        originCut: origin,
        targetCut: target,
      );

      expect(plan.layerPairs, [
        (
          originLayerId: const LayerId('a-conte'),
          targetLayerId: const LayerId('b-conte'),
        ),
        (
          originLayerId: const LayerId('a-cam'),
          targetLayerId: const LayerId('b-cam'),
        ),
      ]);
      expect(
        plan.originOnlyLayerIds,
        isEmpty,
        reason: 'by name, each cut would gain a second conte and camera row',
      );
      expect(plan.targetOnlyLayerIds, isEmpty);
    });

    test('two unrelated cuts with nothing in common still union their '
        'layers (완전 미러)', () {
      final origin = cut('origin', [layer('a1', 'A', const [])]);
      final target = cut('target', [layer('b1', 'B', const [])]);
      final plan = planConvertToLinkedCut(
        project: project([origin, target]),
        originCut: origin,
        targetCut: target,
      );
      expect(plan.layerPairs, isEmpty);
      expect(plan.originOnlyLayerIds, [const LayerId('a1')]);
      expect(plan.targetOnlyLayerIds, [const LayerId('b1')]);
      expect(plan.linksAnything, isTrue);
    });
  });

  // 🗣️유저 2026-09-25: image rows stack under ONE name (BOOK, BOOK, …), and
  // namesakes pair 「레이어이름+프레임이름 통해서 같은거끼리 짝짓고, 아니면
  // 쌓인 순서대로」.
  group('rows sharing a NAME', () {
    Layer book(String id, [String? celName]) => Layer(
      id: LayerId(id),
      name: 'BOOK',
      kind: LayerKind.image,
      frames: [frame('$id-cel', name: celName)],
      timeline: const {},
    );

    List<(String, String)> pairsOf(ConvertToLinkedCutPlan plan) => [
      for (final pair in plan.layerPairs)
        (pair.originLayerId.value, pair.targetLayerId.value),
    ];

    test('pair by the PICTURE they hold first, whatever the stacking', () {
      final origin = cut('origin', [book('k1', 'BOOK1'), book('k2', 'BOOK2')]);
      final target = cut('target', [book('t1', 'BOOK2'), book('t2', 'BOOK1')]);
      final plan = planConvertToLinkedCut(
        project: project([origin, target]),
        originCut: origin,
        targetCut: target,
      );
      expect(pairsOf(plan), [('k1', 't2'), ('k2', 't1')]);
      expect(plan.originOnlyLayerIds, isEmpty);
      expect(plan.targetOnlyLayerIds, isEmpty);
    });

    test('and the rest in STACKING order — a namesake is never dropped for '
        'another', () {
      final origin = cut('origin', [book('k1'), book('k2'), book('k3')]);
      final target = cut('target', [book('t1'), book('t2')]);
      final plan = planConvertToLinkedCut(
        project: project([origin, target]),
        originCut: origin,
        targetCut: target,
      );
      expect(pairsOf(plan), [('k1', 't1'), ('k2', 't2')]);
      expect(plan.originOnlyLayerIds, [const LayerId('k3')]);
      expect(plan.targetOnlyLayerIds, isEmpty);
    });

    test('a 겸용 re-run finds its OWN partner by the link before any '
        'namesake — nothing to do, nothing to union', () {
      final origin = cut('origin', [book('k1'), book('k2')]);
      final target = cut('target', [book('t1'), book('t2')]);
      LayerLinkGroup linked(String id, String originId, String targetId) =>
          LayerLinkGroup(
            id: id,
            members: [
              LayerLinkMember(
                trackId: const TrackId('t'),
                cutId: const CutId('origin'),
                layerId: LayerId(originId),
              ),
              LayerLinkMember(
                trackId: const TrackId('t'),
                cutId: const CutId('target'),
                layerId: LayerId(targetId),
              ),
            ],
          );
      final plan = planConvertToLinkedCut(
        project: project([origin, target]).copyWith(
          linkRegistry: LayerLinkRegistry(
            groups: [linked('g1', 'k1', 't2'), linked('g2', 'k2', 't1')],
          ),
        ),
        originCut: origin,
        targetCut: target,
      );
      expect(
        pairsOf(plan),
        isEmpty,
        reason: 'stacking order would have re-paired k1 with t1',
      );
      expect(plan.originOnlyLayerIds, isEmpty);
      expect(plan.targetOnlyLayerIds, isEmpty);
      expect(plan.linksAnything, isFalse);
    });

    test('a namesake of ANOTHER kind is never a partner', () {
      final origin = cut('origin', [
        Layer(
          id: const LayerId('k-image'),
          name: 'A',
          kind: LayerKind.image,
          frames: [frame('ki', name: '1')],
          timeline: const {},
        ),
        layer('k-cel', 'A', [frame('kc', name: '1')]),
      ]);
      final target = cut('target', [
        layer('t-cel', 'A', [frame('tc', name: '1')]),
      ]);
      final plan = planConvertToLinkedCut(
        project: project([origin, target]),
        originCut: origin,
        targetCut: target,
      );
      expect(pairsOf(plan), [('k-cel', 't-cel')]);
      expect(plan.originOnlyLayerIds, [const LayerId('k-image')]);
    });
  });
}
