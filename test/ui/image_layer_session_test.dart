import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/models/timeline_repeat.dart'
    show TimelineRunEdgeMode, TimelineRunEdgeSide;
import 'package:anicel/src/services/commands/convert_to_linked_cut_plan.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The IMAGE layer contract (§6-z23): one cel by definition, born
/// covering its cut, no second cel to create, an ordinary attach base.
void main() {
  test('addLayerOfKind(image) is born COVERING the cut — ONE real 1-frame '
      'cell plus a fixed end hold whose ghosts tile to the cut boundary '
      '(D22) — and create-drawing has nothing left to make', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final duration = s.requireActiveCut.duration;

    s.addLayerOfKind(LayerKind.image);
    final layer = s.activeLayer!;
    expect(layer.kind, LayerKind.image);
    expect(layer.frames, hasLength(1));
    expect(layer.timeline[0]!.length, 1, reason: '「블록은 1칸」');
    expect(layer.timeline[0]!.ghost, isFalse);
    var covered = 0;
    for (final exposure in layer.timeline.values) {
      expect(exposure.frameId, layer.frames.single.id);
      covered += exposure.length!;
    }
    expect(covered, duration, reason: 'real + hold ghosts tile the cut');
    expect(layer.runBehaviors, hasLength(1));
    expect(layer.runBehaviors.single.mode, TimelineRunEdgeMode.hold);
    expect(layer.runBehaviors.single.side, TimelineRunEdgeSide.end);
    expect(
      layer.frames.single.name,
      isNull,
      reason: 'no frame name by default — the layer name addresses the '
          'picture',
    );
    expect(s.canCreateDrawingAtCurrentFrame, isFalse);
  });

  test('the image row is EDGE-LESS: the session refuses a comma/edge drag '
      'on its block, and a bulk drag never elects it as the cut-sync '
      'anchor (D22)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);
    final imageId = s.activeLayer!.id;

    expect(
      s.beginExposureEdgeDrag(
        layerId: imageId,
        blockStartIndex: 0,
        edge: TimelineBlockEdge.end,
      ),
      isFalse,
      reason: 'no grips in the chrome, no drag in the session — one answer',
    );
  });

  test('an image layer carries attach rows like any drawing base', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);
    expect(s.canAddAttachedLayerToActive, isTrue);
    s.addAttachedLayer(AttachedPlacement.above);
    expect(s.activeLayer!.attachedToLayerId, isNotNull);
  });

  test('겸용: two image rows with the same layer name LINK their single '
      'unnamed cels by position (the image-layer exception to the '
      'unnamed-never-conflicts rule)', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.addLayerOfKind(LayerKind.image);
    final imageName = s.activeLayer!.name;
    final origin = s.requireActiveCut;

    // A second cut with an image row of the SAME NAME and its own cel.
    s.duplicateActiveCut();
    final target = s.requireActiveCut;
    expect(target.id, isNot(origin.id));

    final originImage = origin.layers.firstWhere(
      (l) => l.kind == LayerKind.image && l.name == imageName,
    );
    final targetImage = target.layers.firstWhere(
      (l) => l.kind == LayerKind.image && l.name == imageName,
    );
    // The duplicate minted fresh cel ids, both unnamed.
    expect(targetImage.frames.single.id, isNot(originImage.frames.single.id));
    expect(originImage.frames.single.name, isNull);

    final resolution = resolveLayerMerge(
      origin: originImage,
      target: targetImage,
    );
    expect(
      resolution.retargetedFrameIds,
      {targetImage.frames.single.id: originImage.frames.single.id},
      reason: 'single unnamed image cels match by position',
    );
    expect(resolution.joiningFrameIds, isEmpty);

    // A DRAWING layer's unnamed cels keep the old rule: join, not link.
    final originDrawing = Layer(
      id: originImage.id,
      name: 'A',
      frames: [
        Frame(
          id: originImage.frames.single.id,
          duration: 1,
          strokes: const [],
        ),
      ],
      timeline: const {},
    );
    final targetDrawing = Layer(
      id: targetImage.id,
      name: 'A',
      frames: [
        Frame(
          id: targetImage.frames.single.id,
          duration: 1,
          strokes: const [],
        ),
      ],
      timeline: const {},
    );
    final drawingResolution = resolveLayerMerge(
      origin: originDrawing,
      target: targetDrawing,
    );
    expect(drawingResolution.retargetedFrameIds, isEmpty);
    expect(drawingResolution.joiningFrameIds, [
      targetImage.frames.single.id,
    ]);
  });
}
