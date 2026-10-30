import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/tree_nodes.dart' show preorderNodes;
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
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';

/// 🗣️I-92 (유저 2026-10-24): a row CLIPS TO THE LAYER BELOW as a layer does
/// in Photoshop — it shows only where the base's picture is, and the group
/// takes the base's strength and blend (Q1 a); every clipped row in a run
/// clips to the first unclipped row under it (Q2 a); a folder clips, and is
/// a base, as in CLIP STUDIO (Q3 a).
///
/// Driven on the plan that needs no canvas ([planCutFrameCompositeTree]);
/// every route reads the same tree.
void main() {
  const canvasSize = CanvasSize(width: 4, height: 4);

  Layer drawing(
    String id, {
    String? folder,
    bool clips = false,
    double opacity = 1,
    bool visible = true,
    LayerBlendMode blend = LayerBlendMode.normal,
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('frame-$id'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('frame-$id'), length: 4)},
    folderId: folder == null ? null : LayerId(folder),
    clipsToBelow: clips,
    opacity: opacity,
    isVisible: visible,
    blendMode: blend,
  );

  Layer folderRow(
    String id, {
    bool clips = false,
    double opacity = 1,
  }) => createFolderLayer(id: LayerId(id), name: id.toUpperCase()).copyWith(
    clipsToBelow: clips,
    opacity: opacity,
  );

  Layer adjustmentRow(String id, {bool visible = true}) =>
      createAdjustmentLayer(id: LayerId(id), name: id.toUpperCase()).copyWith(
        isVisible: visible,
        effects: [
          LayerEffect(
            id: const EffectId('fx'),
            kind: EffectKind.brightnessContrast,
            parameters: {'brightness': EffectParameter(value: 20)},
          ),
        ],
      );

  Cut cutOf(List<Layer> layers) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: layers,
    duration: 24,
    canvasSize: canvasSize,
  );

  List<CompositeNode<CutFrameCompositeLayer>> planOf(
    List<Layer> layers, {
    Set<String>? artwork,
  }) => planCutFrameCompositeTree(
    cut: cutOf(layers),
    frameIndex: 0,
    reading: (
      // A surface per row, each its own — so a leaf says whose it is.
      surfaces: (layer, frame) =>
          artwork == null || artwork.contains(layer.id.value)
          ? (_surfaces[layer.id.value] ??=
                BitmapSurface(canvasSize: canvasSize))
          : null,
      plugins: null,
    ),
  );

  String whose(CompositeNode<CutFrameCompositeLayer> node) => switch (node) {
    _Leaf(:final payload) => _surfaces.entries
        .singleWhere((entry) => identical(entry.value, payload.surface))
        .key,
    _ => throw StateError('$node is not a row'),
  };

  setUp(_surfaces.clear);

  test('a clipped row joins the row under it, which paints whole while the '
      'group takes its strength and blend', () {
    final nodes = planOf([
      drawing('a', opacity: 0.5, blend: LayerBlendMode.add),
      drawing('b', clips: true),
    ]);
    final clip = nodes.single as _Clip;
    expect(whose(clip.base), 'a');
    final base = (clip.base as _Leaf).payload;
    expect((base.opacity, base.blendMode), (1.0, LayerBlendMode.normal));
    expect((clip.opacity, clip.blendMode), (0.5, LayerBlendMode.add));
    expect([for (final node in clip.scope) whose(node)], ['b']);
  });

  test('a run of clipped rows all clip to the first unclipped row under '
      'them (Q2 a)', () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', clips: true),
      drawing('c', clips: true),
      drawing('d'),
    ]);
    expect(nodes, hasLength(2));
    final clip = nodes.first as _Clip;
    expect(whose(clip.base), 'a');
    expect([for (final node in clip.scope) whose(node)], ['b', 'c']);
    expect(whose(nodes.last), 'd');
  });

  test('a clipped row in normal lays over the base once — no second picture '
      'of it', () {
    final nodes = planOf([drawing('a'), drawing('b', clips: true)]);
    expect(preorderNodes(nodes).whereType<_Opaque>(), isEmpty);
  });

  test('a clipped row in another blend reads the base\'s whole colour — the '
      'base under it opaque, once for the run', () {
    final nodes = planOf([
      drawing('a'),
      drawing('b', clips: true, blend: LayerBlendMode.multiply),
      drawing('c', clips: true, blend: LayerBlendMode.screen),
    ]);
    final clip = nodes.single as _Clip;
    final opaque = preorderNodes(clip.scope).whereType<_Opaque>().single;
    expect(
      identical(opaque.of, clip.base),
      isTrue,
      reason: 'the base itself, through every fold — a route that keeps a '
          'picture per row finds the base\'s',
    );
    expect(whose(opaque.of), 'a');
    final base = (opaque.of as _Leaf).payload;
    expect((base.opacity, base.blendMode), (1.0, LayerBlendMode.normal));
  });

  test('a clipped row with nothing under it in its folder shows nowhere '
      '(Q5 a)', () {
    expect(planOf([drawing('b', clips: true), drawing('c')]).map(whose), [
      'c',
    ]);
    expect(
      planOf([
        drawing('a'),
        drawing('b', folder: 'f', clips: true),
        folderRow('f'),
      ]).map(whose),
      ['a'],
      reason: 'a row of the folder under it is not under it in its folder',
    );
  });

  test('a clipped row over a base that paints nothing here shows nowhere', () {
    expect(
      planOf([drawing('a'), drawing('b', clips: true)], artwork: {'b'}),
      isEmpty,
      reason: 'no drawing at this frame',
    );
    expect(
      planOf([drawing('a', visible: false), drawing('b', clips: true)]),
      isEmpty,
      reason: 'a hidden base',
    );
  });

  test('a folder is a base: it buffers, even passing through and opaque — '
      'its picture is what cuts (Q3 a)', () {
    final nodes = planOf([
      drawing('x', folder: 'f'),
      drawing('y', folder: 'f'),
      folderRow('f'),
      drawing('c', clips: true),
    ]);
    final clip = nodes.single as _Clip;
    final group = clip.base as _Group;
    expect(group.children.map(whose), ['x', 'y']);
    expect(clip.scope.map(whose), ['c']);
  });

  test('a folder base paints whole while the group takes its strength', () {
    final nodes = planOf([
      drawing('x', folder: 'f'),
      folderRow('f', opacity: 0.25),
      drawing('c', clips: true),
    ]);
    final clip = nodes.single as _Clip;
    final group = clip.base as _Group;
    expect((group.opacity, group.blendMode), (1.0, LayerBlendMode.normal));
    expect(clip.opacity, 0.25);
  });

  test('a folder base composed over its backdrops is still one node with '
      'its opaque twin — the camera keeps one picture per row', () {
    final nodes = planOf([
      drawing('x', folder: 'f'),
      drawing('y', folder: 'f', blend: LayerBlendMode.multiply),
      folderRow('f'),
      drawing('c', clips: true, blend: LayerBlendMode.multiply),
    ]);
    final clip = nodes.single as _Clip;
    expect(
      (clip.base as _Group).children.single,
      isA<CompositeBackdropBlend<CutFrameCompositeLayer>>(),
      reason: '⛔fixture: the base\'s members were composed anew',
    );
    final opaque = preorderNodes(clip.scope).whereType<_Opaque>().single;
    expect(identical(opaque.of, clip.base), isTrue);
  });

  test('a folder clips: its picture goes into the base\'s group (Q3 a)', () {
    final nodes = planOf([
      drawing('a'),
      drawing('x', folder: 'g'),
      folderRow('g', clips: true),
    ]);
    final clip = nodes.single as _Clip;
    expect(whose(clip.base), 'a');
    expect((clip.scope.single as _Group).children.map(whose), ['x']);
  });

  test('over an adjustment row a clipped row is not cut — until the row is '
      'hidden (Q4 a)', () {
    final shown = planOf([
      drawing('a'),
      adjustmentRow('adj'),
      drawing('b', clips: true),
    ]);
    expect(shown.first, isA<_Adjustment>());
    expect(whose(shown.last), 'b');
    expect(
      planOf([
        drawing('a'),
        adjustmentRow('adj', visible: false),
        drawing('b', clips: true),
      ]).map(whose),
      ['a'],
    );
  });

  test('the frame\'s picture is keyed by whether a row clips', () {
    CutFrameCompositeSignature signatureOf({required bool clips}) =>
        computeCutFrameCompositeSignature(
          cut: cutOf([drawing('a'), drawing('b', clips: clips)]),
          frameIndex: 0,
          revisionOf: (_, _) => 1,
        );
    expect(signatureOf(clips: true), isNot(signatureOf(clips: false)));
    expect(signatureOf(clips: true), signatureOf(clips: true));
  });
}

final _surfaces = <String, BitmapSurface>{};

typedef _Leaf = CompositeLeaf<CutFrameCompositeLayer>;
typedef _Group = CompositeGroup<CutFrameCompositeLayer>;
typedef _Adjustment = CompositeAdjustment<CutFrameCompositeLayer>;
typedef _Clip = CompositeClip<CutFrameCompositeLayer>;
typedef _Opaque = CompositeOpaque<CutFrameCompositeLayer>;
