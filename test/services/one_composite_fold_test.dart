import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/models/composite_tree.dart';

/// THE FOLD every composite route runs over the shared tree: map each
/// leaf, drop the leaf that resolved to nothing, and drop the group or
/// adjustment that mapping emptied — "an empty buffer is a wasted
/// saveLayer".
///
/// The rule was written out once per route. These pin it on the route
/// that can be driven without a canvas ([planCutFrameCompositeTree], whose
/// leaf mapping is "resolve a surface, or drop"), so the shared fold has
/// to keep answering exactly this.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  Layer drawing(String id, {String? folder}) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('frame-$id'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('frame-$id'), length: 4)},
    folderId: folder == null ? null : LayerId(folder),
  );

  Layer folderRow(String id, {String? parent}) => createFolderLayer(
    id: LayerId(id),
    name: id.toUpperCase(),
    parentId: parent == null ? null : LayerId(parent),
  ).copyWith(blendMode: LayerBlendMode.multiply);

  Layer adjustmentRow(String id, {String? folder}) =>
      createAdjustmentLayer(id: LayerId(id), name: id.toUpperCase()).copyWith(
        folderId: folder == null ? null : LayerId(folder),
        effects: [
          LayerEffect(
            id: const EffectId('fx'),
            kind: EffectKind.brightnessContrast,
            parameters: {'brightness': EffectParameter(value: 20)},
          ),
        ],
      );

  Cut cut(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: 24,
    canvasSize: canvasSize,
  );

  BitmapSurface surface() => BitmapSurface(canvasSize: canvasSize);

  /// A resolver that answers a surface for [withArtwork] and nothing for
  /// every other row — the "this cel has no pixels" case the fold drops.
  LayerFrameSurfaceResolver resolverFor(Set<String> withArtwork) =>
      (layer, frame) => withArtwork.contains(layer.id.value) ? surface() : null;

  List<CompositeNode<CutFrameCompositeLayer>> planOf(
    Cut source,
    Set<String> artwork,
  ) => planCutFrameCompositeTree(
    cut: source,
    frameIndex: 0,
    surfaceResolver: resolverFor(artwork),
  );

  group('a leaf that resolves to nothing drops', () {
    test('the row with no artwork is gone; its sibling stays, in order', () {
      final nodes = planOf(cut([drawing('a'), drawing('b'), drawing('c')]), {
        'a',
        'c',
      });
      expect(nodes, hasLength(2));
      expect([
        for (final node in nodes)
          (node as CompositeLeaf<CutFrameCompositeLayer>),
      ], hasLength(2));
    });

    test('every row missing leaves an empty plan, not an empty group', () {
      expect(planOf(cut([drawing('a'), drawing('b')]), const {}), isEmpty);
    });
  });

  group('a group the fold emptied drops with its members', () {
    test('a buffering folder whose only member has no artwork leaves NO '
        'node — an empty buffer is a wasted saveLayer', () {
      final nodes = planOf(
        cut([drawing('a', folder: 'f'), folderRow('f')]),
        const {},
      );
      expect(nodes, isEmpty);
    });

    test('the same folder keeps its node while ONE member survives', () {
      final nodes = planOf(
        cut([
          drawing('a', folder: 'f'),
          drawing('b', folder: 'f'),
          folderRow('f'),
        ]),
        {'b'},
      );
      final group = nodes.single as CompositeGroup<CutFrameCompositeLayer>;
      expect(group.children, hasLength(1));
      expect(group.blendMode, LayerBlendMode.multiply);
    });

    test('an outer folder drops when the inner one it held was emptied', () {
      final nodes = planOf(
        cut([
          drawing('a', folder: 'inner'),
          folderRow('inner', parent: 'outer'),
          folderRow('outer'),
        ]),
        const {},
      );
      expect(nodes, isEmpty);
    });
  });

  group('an adjustment scope the fold emptied drops too', () {
    test('nothing left below the row leaves no adjustment node', () {
      final nodes = planOf(cut([drawing('a'), adjustmentRow('adj')]), const {});
      expect(nodes, isEmpty);
    });

    test('the scope survives while something below it does', () {
      final nodes = planOf(
        cut([drawing('a'), drawing('b'), adjustmentRow('adj')]),
        {'b'},
      );
      final scope = nodes.single as CompositeAdjustment<CutFrameCompositeLayer>;
      expect(scope.children, hasLength(1));
      expect(scope.mix, 1);
    });
  });
}
