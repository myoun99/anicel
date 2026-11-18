import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/tree_nodes.dart' show preorderNodes;
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';

/// 🗣️a-numbered-rows-ghost-resolves-its-chain-unsplit-Q1 a (유저
/// 2026-11-17 「그린다 — 고스트도 화면 그대로」): a numbered row's onion
/// ghost is laid as the row is (`celNumberedRow`) — its picture under the
/// links before the number, the letters of the drawing it ghosts over it,
/// the links after on the two — and a Colors tint taken last over all of
/// it, as on any ghost. ↩️A ghost took its chain unsplit: the debug build
/// asserted (`paintedEffectsOf`) and no picture of its frame was made.
///
/// Read off the trees the plan resolves: in place
/// ([resolveCutFrameCompositeTree]'s `ghostsOf`) and over the frame
/// ([ghostsAlone]).
void main() {
  const paper = CanvasSize(width: 8, height: 6);
  const red = 0xFFFF0000;

  LayerEffect number() =>
      LayerEffect(id: const EffectId('n'), kind: EffectKind.celNumber);

  LayerEffect hue() => LayerEffect(
    id: const EffectId('h'),
    kind: EffectKind.hueSaturation,
    parameters: {'hue': EffectParameter(value: 30)},
  );

  LayerEffect blur() => LayerEffect(
    id: const EffectId('b'),
    kind: EffectKind.blur,
    parameters: {'blurriness': EffectParameter(value: 3)},
  );

  /// Row A: drawing 1 over frames 0–1, drawing 2 over frames 2–3.
  Layer drawing(List<LayerEffect> effects) => Layer(
    id: const LayerId('a'),
    name: 'A',
    frames: [
      Frame(id: const FrameId('f1'), duration: 1, strokes: const [], name: '1'),
      Frame(id: const FrameId('f2'), duration: 1, strokes: const [], name: '2'),
    ],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('f1'), length: 2),
      2: const TimelineExposure.drawing(FrameId('f2'), length: 2),
    },
    effects: effects,
  );

  Cut cutOf(Layer row) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: [row],
    duration: 24,
    canvasSize: paper,
  );

  /// [row]'s ghost of drawing 2 seen from frame 0, its chain sampled there
  /// as `OnionSkin.ghostsAt` samples it.
  CutFrameCompositeGhost ghostOf(
    Layer row, {
    int? tint,
    double opacity = 0.5,
  }) => CutFrameCompositeGhost(
        layer: row,
        frameId: const FrameId('f2'),
        frameIndex: 2,
        opacity: opacity,
        tint: tint,
        effects: resolveLayerEffectsAt(
          effects: row.effects,
          frameIndex: 2,
          blocks: null,
          worn: null,
        ),
      );

  List<CompositeNode<CutFrameCompositeRow>> inPlace(
    CutFrameCompositeGhost ghost,
  ) => resolveCutFrameCompositeTree(
    cut: cutOf(ghost.layer),
    frameIndex: 0,
    ghostsOf: (_) => [ghost],
  );

  List<CompositeNode<CutFrameCompositeRow>> over(
    CutFrameCompositeGhost ghost,
  ) => ghostsAlone(cut: cutOf(ghost.layer), frameIndex: 0, ghosts: [ghost]);

  bool isTheGhost(CompositeNode<CutFrameCompositeRow> node) =>
      node is CompositeLeaf<CutFrameCompositeRow> &&
      node.payload is CutFrameCompositeGhost;

  /// The ghost's own nodes: the one subtree of [tree] whose leaf is it.
  CompositeNode<CutFrameCompositeRow> ghostIn(
    List<CompositeNode<CutFrameCompositeRow>> tree,
  ) => tree.singleWhere((node) => preorderNodes([node]).any(isTheGhost));

  List<String> kindsOf(List<ResolvedLayerEffect> effects) => [
    for (final effect in effects) effect.kind.jsonValue,
  ];

  bool numbered(List<ResolvedLayerEffect> effects) =>
      effects.any((effect) => effect.kind.drawsItsOwnPicture);

  /// Whether a node of [tree] would hand a paint a chain that holds a cel
  /// number — what `paintedEffectsOf` asserts no route does.
  bool holdsANumberUnsplit(List<CompositeNode<CutFrameCompositeRow>> tree) =>
      preorderNodes(tree).any(
        (node) => switch (node) {
          CompositeLeaf(:final payload) => numbered(payload.effects),
          CompositeGroup(:final effects) => numbered(effects),
          _ => false,
        },
      );

  final routes = [('in place', inPlace), ('over the frame', over)];
  for (final (route, treeOf) in routes) {
    group(route, () {
      test('the ghost of a numbered row writes the number of the drawing it '
          'ghosts, its chain split as the row\'s', () {
        final tree = treeOf(ghostOf(drawing([blur(), number(), hue()])));

        expect(holdsANumberUnsplit(tree), isFalse);
        final ghost = ghostIn(tree) as CompositeGroup<CutFrameCompositeRow>;
        expect(kindsOf(ghost.effects), ['hueSaturation'], reason: 'after');
        expect(ghost.opacity, 0.5);
        final [picture as CompositeLeaf<CutFrameCompositeRow>, letters] =
            ghost.children;
        expect(kindsOf(picture.payload.effects), ['blur'], reason: 'before');
        expect(
          (picture.payload.opacity, picture.payload.blendMode),
          (1.0, LayerBlendMode.normal),
        );
        final written = letters as CompositeCelNumber<CutFrameCompositeRow>;
        expect(identical(written.on, picture), isTrue);
        expect(written.letters.text, 'A2');
      });

      test('a tint is taken over the letters and the links after the '
          'number: the ghost\'s picture keeps none, its group the tint', () {
        final tree = treeOf(
          ghostOf(drawing([number(), hue()]), tint: red),
        );

        final ghost = ghostIn(tree) as CompositeGroup<CutFrameCompositeRow>;
        expect(ghost.tint, red);
        final picture = ghost.children.first as CompositeLeaf;
        expect((picture.payload as CutFrameCompositeGhost).tint, isNull);
      });

      test('a numbered ghost tinted is one picture though nothing else '
          'would make it one — full strength, nothing after its number', () {
        final tree = treeOf(
          ghostOf(drawing([number()]), tint: red, opacity: 1),
        );

        final ghost = ghostIn(tree) as CompositeGroup<CutFrameCompositeRow>;
        expect((ghost.tint, ghost.opacity), (red, 1.0));
        expect(ghost.effects, isEmpty);
      });

      test('a ghost of a row with no number is its leaf, tint and all', () {
        final tree = treeOf(ghostOf(drawing([blur()]), tint: red));

        final ghost = ghostIn(tree) as CompositeLeaf<CutFrameCompositeRow>;
        final payload = ghost.payload as CutFrameCompositeGhost;
        expect(payload.tint, red);
        expect(kindsOf(payload.effects), ['blur']);
      });
    });
  }

  test('a group\'s tint is part of its signature — a picture of a frame '
      'with its ghosts is keyed by it', () {
    const row = CompositeLayerSignature(
      layerId: LayerId('a'),
      frameId: FrameId('f2'),
      opacity: 1,
      sourceRevision: 0,
    );
    CutFrameCompositeSignature signed(int? tint) =>
        CutFrameCompositeSignature.of([
          CompositeGroup<CompositeRowSignature>(
            children: const [CompositeLeaf(row)],
            opacity: 0.5,
            blendMode: LayerBlendMode.normal,
            tint: tint,
          ),
        ], canvasSize: paper);

    expect(signed(red), signed(red));
    expect(signed(red), isNot(signed(null)));
    expect(signed(red), isNot(signed(0xFF00FF00)));
    // The group's own equality, too: a frame's signature parts on the
    // hash first and would hide one that forgot it.
    expect(signed(red).nodes.single, signed(red).nodes.single);
    expect(signed(red).nodes.single, isNot(signed(null).nodes.single));
  });
}
