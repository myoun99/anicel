import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/tree_nodes.dart' show preorderNodes;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/canvas_point.dart';
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
    parameters: {'blurX': EffectParameter(value: 3)},
  );

  LayerEffect number(
    String id, {
    TransformTrack? stand,
    bool enabled = true,
    (int, int, int) rgb = (0, 0, 0),
  }) => LayerEffect(
    id: EffectId(id),
    kind: EffectKind.celNumber,
    enabled: enabled,
    parameters: {
      'red': EffectParameter(value: rgb.$1.toDouble()),
      'green': EffectParameter(value: rgb.$2.toDouble()),
      'blue': EffectParameter(value: rgb.$3.toDouble()),
    },
    stand: stand,
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
    final beforeGroup = before.single as _Group;
    final afterGroup = after.single as _Group;
    expect(kindsOf(beforeGroup.effects), isEmpty);
    expect(kindsOf((beforeGroup.children.first as _Leaf).payload.effects), [
      'blur',
    ]);
    expect(kindsOf(afterGroup.effects), ['blur']);
    expect(
      kindsOf((afterGroup.children.first as _Leaf).payload.effects),
      isEmpty,
    );
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

  test('a number switched off writes nothing — the row is its leaf', () {
    final nodes = planOf(drawing(effects: [number('n', enabled: false)]));
    expect(nodes.single, isA<_Leaf>());
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

  test('they are written in the number\'s colour, opaque', () {
    final letters = lettersOf(
      drawing(effects: [number('n', rgb: (200, 10, 30))]),
    );
    expect(
      letters.color,
      RgbaColor(r: 200, g: 10, b: 30, a: 255).toArgbInt(),
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
      ('another colour', drawing(effects: [number('n', rgb: (255, 0, 0))])),
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
