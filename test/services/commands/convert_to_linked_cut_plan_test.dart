import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
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
}
