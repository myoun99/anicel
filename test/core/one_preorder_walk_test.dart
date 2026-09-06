import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';

/// **The recursion over a composite tree is ONE algorithm.**
///
/// Three hand-written pre-order walks sat over two sealed hierarchies —
/// the signature's `layers`, the stack view's `layers` and its
/// `_activeNodeFrameKey`. These pin what all three must answer: every leaf
/// in depth-first bottom → top order, nested folders and adjustments
/// descended into, and the non-leaf kinds contributing nothing of their
/// own.
void main() {
  CompositeLayerSignature leaf(String id) => CompositeLayerSignature(
    layerId: LayerId(id),
    frameId: FrameId('$id-cel'),
    opacity: 1,
    sourceRevision: 0,
  );

  group('the composite SIGNATURE walk', () {
    /// a, then a folder holding b and an adjustment holding c, then d.
    CutFrameCompositeSignature nested() => CutFrameCompositeSignature(
      canvasSize: const CanvasSize(width: 8, height: 8),
      quality: PlaybackQuality.full,
      nodes: [
        CompositeLeafSignature(leaf('a')),
        CompositeGroupSignature(
          opacity: 0.5,
          blendMode: LayerBlendMode.normal,
          children: [
            CompositeLeafSignature(leaf('b')),
            CompositeAdjustmentSignature(
              effects: const [],
              mix: 1,
              children: [CompositeLeafSignature(leaf('c'))],
            ),
          ],
        ),
        CompositeLeafSignature(leaf('d')),
      ],
    );

    test('flattens every leaf, depth-first bottom → top', () {
      expect(
        nested().layers.map((layer) => layer.layerId.value),
        ['a', 'b', 'c', 'd'],
      );
    });

    test('a folder holding only a folder still reaches the leaf', () {
      final buried = CutFrameCompositeSignature(
        canvasSize: const CanvasSize(width: 8, height: 8),
        quality: PlaybackQuality.full,
        nodes: [
          CompositeGroupSignature(
            opacity: 1,
            blendMode: LayerBlendMode.normal,
            children: [
              CompositeGroupSignature(
                opacity: 1,
                blendMode: LayerBlendMode.normal,
                children: [CompositeLeafSignature(leaf('deep'))],
              ),
            ],
          ),
        ],
      );
      expect(buried.layers.map((layer) => layer.layerId.value), ['deep']);
    });

    test('an EMPTY folder yields nothing of its own', () {
      final empty = CutFrameCompositeSignature(
        canvasSize: const CanvasSize(width: 8, height: 8),
        quality: PlaybackQuality.full,
        nodes: [
          CompositeGroupSignature(
            opacity: 1,
            blendMode: LayerBlendMode.normal,
            children: const [],
          ),
        ],
      );
      expect(empty.layers, isEmpty);
    });
  });

  group('the canvas STACK walk', () {
    CanvasLayerImageRequest request(String id) => CanvasLayerImageRequest(
      frameKey: BrushFrameKey(
        projectId: const ProjectId('p'),
        trackId: const TrackId('t'),
        cutId: const CutId('c'),
        layerId: LayerId(id),
        frameId: FrameId('$id-cel'),
      ),
      opacity: 1,
    );

    /// a, then a folder holding the ACTIVE row and an adjustment holding
    /// b, then c.
    CanvasLayerStackView view() => CanvasLayerStackView(
      canvasSize: const CanvasSize(width: 8, height: 8),
      imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
      viewport: CanvasViewport(),
      nodes: [
        CanvasLayerImageNode(request('a')),
        CanvasLayerGroupNode(
          opacity: 1,
          blendMode: LayerBlendMode.normal,
          children: [
            const CanvasActiveLayerNode(
              opacity: 1,
              frameKey: BrushFrameKey(
                projectId: ProjectId('p'),
                trackId: TrackId('t'),
                cutId: CutId('c'),
                layerId: LayerId('active'),
                frameId: FrameId('active-cel'),
              ),
            ),
            CanvasLayerAdjustmentNode(
              effects: const [],
              mix: 1,
              children: [CanvasLayerImageNode(request('b'))],
            ),
          ],
        ),
        CanvasLayerImageNode(request('c')),
      ],
    );

    test('flattens every image request, depth-first bottom → top', () {
      expect(
        view().layers.map((entry) => entry.frameKey.layerId.value),
        ['a', 'b', 'c'],
        reason: 'the ACTIVE node is not a cached image and yields nothing',
      );
    });

    test('an empty stack answers nothing', () {
      expect(
        CanvasLayerStackView(
          canvasSize: const CanvasSize(width: 8, height: 8),
          imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
          viewport: CanvasViewport(),
          nodes: const [],
        ).layers,
        isEmpty,
      );
    });
  });
}
