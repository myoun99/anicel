import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

void main() {
  group('storyboardLayerForCut', () {
    test('returns null when no storyboard layer exists', () {
      final cut = _cut(layers: [_layer('anim-a', LayerKind.animation)]);

      expect(storyboardLayerForCut(cut), isNull);
    });

    test(
      'returns the ordinary Layer(kind: storyboard) when exactly one exists',
      () {
        final storyboardLayer = _layer('storyboard-a', LayerKind.storyboard);
        final cut = _cut(
          layers: [
            _layer('anim-below', LayerKind.animation),
            storyboardLayer,
            _layer('anim-above', LayerKind.animation),
          ],
        );

        expect(identical(storyboardLayerForCut(cut), storyboardLayer), isTrue);
      },
    );

    test('finds storyboard layer regardless of layer name', () {
      final storyboardLayer = _layer(
        'misleading-storyboard-kind',
        LayerKind.storyboard,
        name: 'Animation',
      );
      final cut = _cut(
        layers: [
          _layer(
            'misleading-animation-kind',
            LayerKind.animation,
            name: 'Storyboard',
          ),
          storyboardLayer,
        ],
      );

      expect(storyboardLayerForCut(cut)?.id, storyboardLayer.id);
    });

    test('finds storyboard layer regardless of raw layer position', () {
      final first = _layer('first-animation', LayerKind.animation);
      final storyboardLayer = _layer('middle-storyboard', LayerKind.storyboard);
      final last = _layer('last-animation', LayerKind.animation);
      final cut = _cut(layers: [first, storyboardLayer, last]);

      expect(storyboardLayerForCut(cut)?.id, storyboardLayer.id);
    });

    test('a cut that somehow holds two takes the FIRST as its row rather '
        'than throwing — the read is a painter\'s, and a throw there is a '
        'red screen where an editor should be', () {
      final cut = _cut(
        layers: [
          _layer('storyboard-a', LayerKind.storyboard),
          _layer('animation-a', LayerKind.animation),
          _layer('storyboard-b', LayerKind.storyboard),
        ],
      );

      expect(storyboardLayerForCut(cut)?.id.value, 'storyboard-a');
      // The duplicate is still findable, for whoever wants to SAY something
      // about it.
      expect(storyboardLayersOfCut(cut).map((layer) => layer.id.value), [
        'storyboard-a',
        'storyboard-b',
      ]);
      // And the verbs that could make a second one refuse.
      expect(cutAcceptsAnotherStoryboardLayer(cut), isFalse);
      expect(
        cutAcceptsAnotherStoryboardLayer(
          cut,
          exceptLayerId: const LayerId('storyboard-a'),
        ),
        isFalse,
        reason: 'the OTHER one still blocks it',
      );
    });

    test('a cut with none accepts one, and re-applying the kind to the row '
        'that already is one is not a second row', () {
      final empty = _cut(layers: [_layer('animation-a', LayerKind.animation)]);
      expect(cutAcceptsAnotherStoryboardLayer(empty), isTrue);

      final one = _cut(layers: [_layer('sb', LayerKind.storyboard)]);
      expect(cutAcceptsAnotherStoryboardLayer(one), isFalse);
      expect(
        cutAcceptsAnotherStoryboardLayer(
          one,
          exceptLayerId: const LayerId('sb'),
        ),
        isTrue,
      );
    });

    test('does not mutate the Cut', () {
      final cut = _cut(
        layers: [
          _layer('animation-a', LayerKind.animation),
          _layer('storyboard-a', LayerKind.storyboard),
        ],
      );
      final beforeJson = cut.toJson().toString();

      storyboardLayerForCut(cut);

      expect(cut.toJson().toString(), beforeJson);
    });
  });
}

Cut _cut({required List<Layer> layers}) {
  return Cut(
    id: const CutId('cut-a'),
    name: 'Cut A',
    duration: 24,
    canvasSize: const CanvasSize(width: 1280, height: 720),
    layers: layers,
  );
}

Layer _layer(String id, LayerKind kind, {String? name}) {
  return Layer(
    id: LayerId(id),
    name: name ?? id,
    kind: kind,
    frames: [Frame(id: FrameId('frame-$id'), duration: 1, strokes: const [])],
  );
}
