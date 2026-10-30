import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
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

/// 🗣️brush-fidelity-Q4 (유저 2026-10-17 「레이어까지 같이」): a row whose
/// blend the GPU lacks — ↩️and since a-blurred-folder-cut-by-the-view-
/// moves-on-vulkan (10-22, 「골은 b」) a row in ANY advanced blend, the
/// GPU's own too — is composed over everything below it in its SCOPE
/// ([composeOverTheirBackdrops]) — the scope an adjustment row reads: out
/// through pass-through folders, never into a buffering one. And the paper
/// goes in once, under the lowest backdrop a blend reads ([onUnderlay]).
///
/// Driven on the plan that needs no canvas ([planCutFrameCompositeTree]);
/// every route reads the same tree.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  Layer drawing(
    String id, {
    String? folder,
    LayerBlendMode blend = LayerBlendMode.normal,
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('frame-$id'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('frame-$id'), length: 4)},
    folderId: folder == null ? null : LayerId(folder),
    blendMode: blend,
  );

  Layer folderRow(String id, LayerBlendMode blend) =>
      createFolderLayer(id: LayerId(id), name: id.toUpperCase())
          .copyWith(blendMode: blend);

  Layer adjustmentRow(String id) =>
      createAdjustmentLayer(id: LayerId(id), name: id.toUpperCase()).copyWith(
        effects: [
          LayerEffect(
            id: const EffectId('fx'),
            kind: EffectKind.brightnessContrast,
            parameters: {'brightness': EffectParameter(value: 20)},
          ),
        ],
      );

  List<CompositeNode<CutFrameCompositeLayer>> planOf(
    List<Layer> layers, {
    Set<String>? artwork,
  }) => planCutFrameCompositeTree(
    plugins: null,
    cut: Cut(
      id: const CutId('cut'),
      name: 'Cut',
      layers: layers,
      duration: 24,
      canvasSize: canvasSize,
    ),
    frameIndex: 0,
    surfaceResolver: (layer, frame) =>
        artwork == null || artwork.contains(layer.id.value)
        ? BitmapSurface(canvasSize: canvasSize)
        : null,
  );

  // ↩️'a row the GPU has a blend for stays a row' — multiply did, until
  // every advanced blend went over its backdrop in the shader
  // (a-blurred-folder-cut-by-the-view-moves-on-vulkan Q3 · Q4). What the
  // GPU lays in place is all that stays a row.
  test('a row in normal or add stays a row', () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', blend: LayerBlendMode.add),
      drawing('c'),
    ]);
    expect(nodes, everyElement(isA<_Leaf>()));
  });

  test('a row in a blend the GPU has gathers as the rest do', () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', blend: LayerBlendMode.multiply),
    ]);
    final blend = nodes.single as _Blend;
    expect(blend.blendMode, LayerBlendMode.multiply);
    expect(blend.backdrop, hasLength(1));
  });

  test('a row in an advanced blend gathers everything below it, and paints '
      'normal inside', () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', blend: LayerBlendMode.subtract),
      drawing('c'),
    ]);
    final blend = nodes.first as _Blend;
    expect(nodes, hasLength(2));
    expect(blend.blendMode, LayerBlendMode.subtract);
    expect(blend.backdrop, hasLength(1));
    final source = blend.source as _Leaf;
    expect(
      source.payload.blendMode,
      LayerBlendMode.normal,
      reason: 'the blend applies once, between the two pictures',
    );
    expect(nodes.last, isA<_Leaf>());
  });

  test('a second one gathers the first with everything else below it', () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', blend: LayerBlendMode.subtract),
      drawing('c', blend: LayerBlendMode.divide),
    ]);
    final outer = nodes.single as _Blend;
    expect(outer.blendMode, LayerBlendMode.divide);
    final inner = outer.backdrop.single as _Blend;
    expect(inner.blendMode, LayerBlendMode.subtract);
    expect(inner.backdrop, hasLength(1));
  });

  test('its scope reaches out through a pass-through folder', () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', folder: 'f'),
      drawing('c', folder: 'f', blend: LayerBlendMode.linearBurn),
      folderRow('f', LayerBlendMode.passThrough),
    ]);
    final blend = nodes.single as _Blend;
    expect(
      blend.backdrop,
      hasLength(2),
      reason: '통과: what lies below the folder is below the row too',
    );
  });

  test('and stops at a buffering one, whose buffer is a picture of its own',
      () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', folder: 'f'),
      drawing('c', folder: 'f', blend: LayerBlendMode.linearBurn),
      // ↩️A multiply folder stood here; it is a blend of its own now, which
      // gathers the row below it too. Normal buffers and gathers nothing.
      folderRow('f', LayerBlendMode.normal),
    ]);
    expect(nodes, hasLength(2));
    final group = nodes.last as _Group;
    final blend = group.children.single as _Blend;
    expect(blend.backdrop, hasLength(1), reason: 'b alone — never a');
  });

  test('a buffering folder in such a blend is the row: its buffer, painted '
      'normal, over what lies below the folder', () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', folder: 'f'),
      folderRow('f', LayerBlendMode.vividLight),
    ]);
    final blend = nodes.single as _Blend;
    expect(blend.blendMode, LayerBlendMode.vividLight);
    final source = blend.source as _Group;
    expect(source.blendMode, LayerBlendMode.normal);
    expect(blend.backdrop, hasLength(1));
  });

  test('an adjustment below it is part of what it reads', () {
    final nodes = planOf([
      drawing('a'),
      adjustmentRow('adj'),
      drawing('b', blend: LayerBlendMode.hardMix),
    ]);
    final blend = nodes.single as _Blend;
    expect(blend.backdrop.single, isA<_Adjustment>());
  });

  test('a row with no artwork leaves what it would have read where it was',
      () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', blend: LayerBlendMode.subtract),
    ], artwork: {'a'});
    expect(nodes.single, isA<_Leaf>());
  });

  group('the underlay goes in once', () {
    test('under the list when nothing reads it', () {
      final nodes = onUnderlay(<CompositeNode<String>>[
        const CompositeLeaf('a'),
        const CompositeLeaf('b'),
      ], 'paper');
      expect([
        for (final node in nodes) (node as CompositeLeaf<String>).payload,
      ], ['paper', 'a', 'b']);
    });

    test('under the lowest backdrop a blend reads, at every depth — and '
        'nowhere else', () {
      const inner = CompositeBackdropBlend<String>(
        backdrop: [CompositeLeaf('a')],
        source: CompositeLeaf('b'),
        blendMode: LayerBlendMode.subtract,
      );
      final nodes = onUnderlay(<CompositeNode<String>>[
        const CompositeBackdropBlend<String>(
          backdrop: [inner],
          source: CompositeLeaf('c'),
          blendMode: LayerBlendMode.divide,
        ),
        const CompositeLeaf('d'),
      ], 'paper');
      final leaves = _leavesInOrder(nodes).toList();
      expect(leaves, ['paper', 'a', 'b', 'c', 'd']);
      final outer = nodes.first as CompositeBackdropBlend<String>;
      final deepest = outer.backdrop.single as CompositeBackdropBlend<String>;
      expect(
        (deepest.backdrop.first as CompositeLeaf<String>).payload,
        'paper',
      );
      expect(nodes.last, isA<CompositeLeaf<String>>());
    });
  });
}

Iterable<String> _leavesInOrder(List<CompositeNode<String>> nodes) sync* {
  for (final node in nodes) {
    if (node case CompositeLeaf(:final payload)) {
      yield payload;
    }
    yield* _leavesInOrder(node.children);
  }
}

typedef _Leaf = CompositeLeaf<CutFrameCompositeLayer>;
typedef _Group = CompositeGroup<CutFrameCompositeLayer>;
typedef _Adjustment = CompositeAdjustment<CutFrameCompositeLayer>;
typedef _Blend = CompositeBackdropBlend<CutFrameCompositeLayer>;
