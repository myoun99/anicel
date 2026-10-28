import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';

/// **The recursion over a composite tree is ONE algorithm.**
///
/// Three hand-written pre-order walks sat over two sealed hierarchies —
/// the signature's `layers`, the stack view's `layers` and its
/// `_activeNodeFrameKey` (gone 2026-09-17 with the first-activation
/// stand-in, its only reader). These pin what the walks must answer: every
/// leaf in depth-first bottom → top order, nested folders and adjustments
/// descended into, and the non-leaf kinds contributing nothing of their
/// own. ↩️The stack view's `layers` was pinned here too, until the view went
/// (one-picture-per-frame ②-5b-1).
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
}
