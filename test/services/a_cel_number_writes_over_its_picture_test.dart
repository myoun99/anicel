import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/tree_nodes.dart' show preorderNodes;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_number_letters.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/playback/cut_frame_composite_signature.dart';

/// 🗣️I-65 (유저 2026-10-24): a CEL NUMBER fx writes the row's name and the
/// drawing's number over the picture (Q1 a: 「A1 — 이름 없는 그림은 A●」),
/// as one step of the chain — the fx before it on the picture alone, the
/// fx after it on the picture and the letters (08-07: 「체인 위치 고정
/// 반대」) — standing where its own Position and Scale put it, the row's
/// rest at the paper's middle while they hold no key (Q2 메모 · 08-07).
///
/// Driven on the plan that needs no canvas ([planCutFrameCompositeTree]);
/// every route reads the same tree.
void main() {
  const paper = CanvasSize(width: 8, height: 6);

  LayerEffect blur(String id) => LayerEffect(
    id: EffectId(id),
    kind: EffectKind.blur,
    parameters: {'blurriness': EffectParameter(value: 3)},
  );

  LayerEffect number(
    String id, {
    TransformTrack? stand,
    bool enabled = true,
    int? ink,
  }) => LayerEffect(
    id: EffectId(id),
    kind: EffectKind.celNumber,
    enabled: enabled,
    stand: stand,
    colors: {
      if (ink != null) 'ink': PropertyTrack<int>.empty().withKey(0, ink),
    },
  );

  Layer drawing({
    String name = 'A',
    String? frameName = '1',
    List<LayerEffect> effects = const [],
    double opacity = 1,
    LayerBlendMode blend = LayerBlendMode.normal,
    LayerKind kind = LayerKind.animation,
  }) => Layer(
    id: const LayerId('a'),
    name: name,
    kind: kind,
    frames: [
      Frame(
        id: const FrameId('f'),
        duration: 1,
        strokes: const [],
        name: frameName,
      ),
    ],
    timeline: {0: const TimelineExposure.drawing(FrameId('f'), length: 4)},
    effects: effects,
    opacity: opacity,
    blendMode: blend,
  );

  Cut cutOf(Layer layer) => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: [layer],
    duration: 24,
    canvasSize: paper,
  );

  final surface = BitmapSurface(canvasSize: paper);

  List<CompositeNode<CutFrameCompositeLayer>> planOf(Layer layer) =>
      planCutFrameCompositeTree(
        plugins: null,
        cut: cutOf(layer),
        frameIndex: 0,
        surfaceResolver: (_, _) => surface,
      );

  List<String> kindsOf(List<ResolvedLayerEffect> effects) => [
    for (final effect in effects) effect.kind.jsonValue,
  ];

  test('a row with no number is its leaf', () {
    final nodes = planOf(drawing(effects: [blur('b')]));
    expect(nodes.single, isA<_Leaf>());
    expect(kindsOf((nodes.single as _Leaf).payload.effects), ['blur']);
  });

  test('a numbered row is a group: its picture under the fx before the '
      'number, the letters over it on that very row, the fx after on the '
      'two — and its strength and blend once, on the group', () {
    final nodes = planOf(
      drawing(
        effects: [blur('before'), number('n'), blur('after')],
        opacity: 0.5,
        blend: LayerBlendMode.add,
      ),
    );
    final group = nodes.single as _Group;
    expect((group.opacity, group.blendMode), (0.5, LayerBlendMode.add));
    expect(kindsOf(group.effects), ['blur']);
    final [row as _Leaf, letters as _Number] = group.children;
    final picture = row.payload;
    expect((picture.opacity, picture.blendMode), (1.0, LayerBlendMode.normal));
    expect(kindsOf(picture.effects), ['blur']);
    // ⚠️THE SAME NODE — a route asks it where the row lies.
    expect(identical(letters.on, row), isTrue);
    // The row stands in the tree once: the letters are no second place of
    // it.
    expect(preorderNodes(nodes).whereType<_Leaf>(), hasLength(1));
  });

  test('a numbered row in a blend read over its backdrop blends the picture '
      'and the letters as one', () {
    final nodes = planOf(
      drawing(effects: [number('n')], blend: LayerBlendMode.multiply),
    );
    final blended = nodes.single as CompositeBackdropBlend;
    expect(blended.blendMode, LayerBlendMode.multiply);
    final group = blended.source as _Group;
    expect(group.blendMode, LayerBlendMode.normal);
    expect(group.children.last, isA<_Number>());
  });

  test('the blur before the number is the picture\'s alone, the one after '
      'is the group\'s', () {
    final before = planOf(drawing(effects: [blur('b'), number('n')]));
    final after = planOf(drawing(effects: [number('n'), blur('b')]));
    final [row as _Leaf, _ as _Number] = before;
    expect(kindsOf(row.payload.effects), ['blur']);
    final afterGroup = after.single as _Group;
    expect(kindsOf(afterGroup.effects), ['blur']);
    expect(
      kindsOf((afterGroup.children.first as _Leaf).payload.effects),
      isEmpty,
    );
  });

  // 🚨The folder's law (`folderNeedsCompositeBuffer`): one picture only
  // where the two do not distribute.
  test('a numbered row that changes nothing of how the two land is no '
      'group — the letters lie over the row in their place, as a folder '
      'that changes nothing is no group', () {
    final nodes = planOf(drawing(effects: [blur('before'), number('n')]));
    final [row as _Leaf, letters as _Number] = nodes;
    expect(identical(letters.on, row), isTrue);
    expect(
      (row.payload.opacity, row.payload.blendMode),
      (1.0, LayerBlendMode.normal),
    );
    expect(preorderNodes(nodes).whereType<_Group>(), isEmpty);
  });

  test('its strength alone makes the two one picture, and so does its '
      'blend alone', () {
    final faint = planOf(drawing(effects: [number('n')], opacity: 0.5));
    final added = planOf(
      drawing(effects: [number('n')], blend: LayerBlendMode.add),
    );
    for (final (says, nodes, opacity, blendMode) in [
      ('a strength below 1', faint, 0.5, LayerBlendMode.normal),
      ('a blend other than normal', added, 1.0, LayerBlendMode.add),
    ]) {
      final group = nodes.single as _Group;
      expect(
        (group.opacity, group.blendMode),
        (opacity, blendMode),
        reason: says,
      );
      expect(group.children.last, isA<_Number>(), reason: says);
    }
  });

  // I-92-Q3 a: what clips or is clipped to is cut or cuts as one picture.
  test('a numbered row clipped to, or clipping, is one picture with its '
      'letters', () {
    final numbered = drawing(effects: [number('n')]);
    final other = drawing(name: 'B').copyWith(id: const LayerId('b'));
    List<CompositeNode<CutFrameCompositeLayer>> planOfRows(
      List<Layer> layers,
    ) => planCutFrameCompositeTree(
      plugins: null,
      cut: cutOf(numbered).copyWith(layers: layers),
      frameIndex: 0,
      surfaceResolver: (_, _) => surface,
    );
    final asBase = planOfRows([
      numbered,
      other.copyWith(clipsToBelow: true),
    ]).single as CompositeClip<CutFrameCompositeLayer>;
    expect(asBase.base, isA<_Group>(), reason: 'clipped to');
    final asClipping = planOfRows([
      other,
      numbered.copyWith(clipsToBelow: true),
    ]).single as CompositeClip<CutFrameCompositeLayer>;
    expect(asClipping.scope.last, isA<_Group>(), reason: 'clipping');

    // Two numbers with nothing between them that changes how they land are
    // still the one picture — not a picture of the first inside it.
    final twice = planOfRows([
      drawing(effects: [number('one'), number('two')]),
      other.copyWith(clipsToBelow: true),
    ]).single as CompositeClip<CutFrameCompositeLayer>;
    final [row as _Leaf, first as _Number, second as _Number] =
        (twice.base as _Group).children;
    expect(identical(first.on, row) && identical(second.on, row), isTrue);
  });

  test('a second number is a group around the first, which keeps the row\'s '
      'strength off it', () {
    final nodes = planOf(
      drawing(
        effects: [number('one'), blur('mid'), number('two')],
        opacity: 0.25,
      ),
    );
    final outer = nodes.single as _Group;
    final [inner as _Group, second as _Number] = outer.children;
    expect((inner.opacity, inner.blendMode), (1.0, LayerBlendMode.normal));
    expect(kindsOf(inner.effects), ['blur']);
    expect(outer.opacity, 0.25);
    expect(kindsOf(outer.effects), isEmpty);
    final [row as _Leaf, first as _Number] = inner.children;
    expect(identical(first.on, row), isTrue);
    expect(identical(second.on, row), isTrue);
  });

  // 🗣️I-65-Q4 (유저 2026-10-24): 「fx 를 단 행만 적는다 — 어태치는 번호 없이
  // 나머지 fx 만 입는다」.
  test('a row attached to the numbered one wears the rest of its chain, and '
      'no number', () {
    final base = drawing(effects: [blur('before'), number('n'), blur('after')]);
    final attach = Layer(
      id: const LayerId('b'),
      name: 'A影',
      frames: base.frames,
      timeline: base.timeline,
      attachedToLayerId: base.id,
      // Its own exposures — a synced row needs links to its base's cels.
      attachedMode: AttachedMode.free,
    );
    final cut = cutOf(base).copyWith(layers: [base, attach]);
    final worn = resolveLayerEffectsAt(
      effects: chainWornBy(cut, attach),
      frameIndex: 0,
    );
    expect(kindsOf(worn), ['blur', 'blur']);
    expect(chainWornBy(cut, base), base.effects);
    final nodes = planCutFrameCompositeTree(
      plugins: null,
      cut: cut,
      frameIndex: 0,
      surfaceResolver: (_, _) => surface,
    );
    // The number is the base's: one group, and the attached row a leaf.
    expect(nodes.whereType<_Group>(), hasLength(1));
    final rider = nodes.whereType<_Leaf>().single;
    expect(kindsOf(rider.payload.effects), ['blur', 'blur']);
    final drawn = layerDrawingAt(cut: cut, layer: attach, frameIndex: 0)!;
    expect(kindsOf(drawn.render.effects), ['blur', 'blur']);
  });

  test('a number switched off writes nothing — the row is its leaf', () {
    final nodes = planOf(drawing(effects: [number('n', enabled: false)]));
    expect(nodes.single, isA<_Leaf>());
  });

  test('on a block with nothing drawn the letters are written all the '
      'same, on the row standing bare — which paints nothing, and stands '
      'nowhere else in the tree (F-481)', () {
    List<CompositeNode<CutFrameCompositeLayer>> blankPlanOf(Layer layer) =>
        planCutFrameCompositeTree(
          plugins: null,
          cut: cutOf(layer),
          frameIndex: 0,
          surfaceResolver: (_, _) => null,
        );
    expect(blankPlanOf(drawing()), isEmpty, reason: 'no number: it drops');
    final nodes = blankPlanOf(drawing(effects: [number('n')]));
    final [letters as _Number] = nodes;
    expect(letters.letters.text, 'A1');
    expect(letters.on.payload.surface.showsSomething, isFalse);
    expect(preorderNodes(nodes).whereType<_Leaf>(), isEmpty);
  });

  CelNumberLetters lettersOf(Layer layer) =>
      preorderNodes(planOf(layer)).whereType<_Number>().single.letters;

  test('the letters say the row\'s name and the drawing\'s number (Q1 a)', () {
    expect(lettersOf(drawing(effects: [number('n')])).text, 'A1');
    expect(
      lettersOf(drawing(name: 'BG', frameName: '12', effects: [number('n')]))
          .text,
      'BG12',
    );
    expect(
      celNumberText(
        rowName: 'A',
        drawingName: null,
        kind: LayerKind.animation,
      ),
      'A${celNumberOrMark(null, kind: LayerKind.animation)}',
    );
    expect(
      lettersOf(drawing(frameName: null, effects: [number('n')])).text,
      'A●',
      reason:
          'the unnamed head\'s mark, mark 2 until another is picked (F-489) '
          '— ↩️「A○」 from F-469 「기본마크, 앞으로 마크1 사용」',
    );
  });

  test('unkeyed, the letters stand where a row stands at rest — the '
      'paper\'s middle — at the text tool\'s size', () {
    final letters = lettersOf(drawing(effects: [number('n')]));
    expect(letters.center, CanvasPoint(x: 4, y: 3));
    expect(letters.scale, CanvasPoint(x: 1, y: 1));
  });

  test('keyed, they stand where the number\'s own Position and Scale put '
      'them', () {
    final stand = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>.empty().withKey(
        0,
        CanvasPoint(x: 1, y: 2),
      ),
      scale: PropertyTrack<CanvasPoint>.empty().withKey(
        0,
        CanvasPoint(x: 2, y: 0.5),
      ),
    );
    final letters = lettersOf(drawing(effects: [number('n', stand: stand)]));
    expect(letters.center, CanvasPoint(x: 1, y: 2));
    expect(letters.scale, CanvasPoint(x: 2, y: 0.5));
  });

  test('they are written in the number\'s ink — the text tool\'s black '
      'where it is unkeyed', () {
    final colour = RgbaColor(r: 200, g: 10, b: 30, a: 255).toArgbInt();
    expect(
      lettersOf(drawing(effects: [number('n', ink: colour)])).color,
      colour,
    );
    expect(
      lettersOf(drawing(effects: [number('n')])).color,
      0xFF000000,
      reason: 'unkeyed',
    );
  });

  test('the frame\'s picture is keyed by what the letters say and where '
      'they stand', () {
    CutFrameCompositeSignature signatureOf(Layer layer) =>
        computeCutFrameCompositeSignature(
          cut: cutOf(layer),
          frameIndex: 0,
          revisionOf: (_, _) => 1,
        );
    final plain = signatureOf(drawing(effects: [number('n')]));
    expect(signatureOf(drawing(effects: [number('n')])), plain);
    for (final (says, other) in [
      ('another row name', drawing(name: 'B', effects: [number('n')])),
      ('another drawing', drawing(frameName: '2', effects: [number('n')])),
      ('another colour', drawing(effects: [number('n', ink: 0xFFFF0000)])),
      ('no number', drawing()),
    ]) {
      final signature = signatureOf(other);
      expect(signature, isNot(plain), reason: says);
      // ⚠️The nodes too, each by its own equality: the whole signature
      // parts on its hash before it walks them.
      expect(signature.nodes, isNot(plain.nodes), reason: says);
    }
  });
}

typedef _Leaf = CompositeLeaf<CutFrameCompositeLayer>;
typedef _Group = CompositeGroup<CutFrameCompositeLayer>;
typedef _Number = CompositeCelNumber<CutFrameCompositeLayer>;
