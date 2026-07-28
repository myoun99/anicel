import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_layer_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';

void main() {
  group('celLayerNameForIndex', () {
    test('creates zero-based cel-style names', () {
      expect(celLayerNameForIndex(0), 'A');
      expect(celLayerNameForIndex(1), 'B');
      expect(celLayerNameForIndex(25), 'Z');
      expect(celLayerNameForIndex(26), 'AA');
      expect(celLayerNameForIndex(27), 'AB');
      expect(celLayerNameForIndex(52), 'BA');
    });

    test('rejects negative indexes', () {
      expect(() => celLayerNameForIndex(-1), throwsArgumentError);
    });
  });

  group('nextCelLayerNameForCut', () {
    test('is cut-local', () {
      final cut1 = _cut(layers: [_layer('A'), _layer('B'), _layer('C')]);
      final cut2 = _cut(id: 'cut-2', layers: [_layer('A')]);

      expect(nextCelLayerNameForCut(cut1), 'D');
      expect(nextCelLayerNameForCut(cut2), 'B');
    });

    test('fills the smallest missing cel name', () {
      final cut = _cut(layers: [_layer('A'), _layer('B'), _layer('D')]);

      expect(nextCelLayerNameForCut(cut), 'C');
    });

    test('counts storyboard layers as used cel names', () {
      final cut = _cut(
        layers: [
          _layer('A'),
          _layer('B', kind: LayerKind.storyboard),
          _layer('D'),
        ],
      );

      expect(nextCelLayerNameForCut(cut), 'C');
    });
  });

  group('defaultLayerIdForSequence', () {
    test('creates production default layer ids', () {
      expect(defaultLayerIdForSequence(2), const LayerId('default-layer-2'));
      expect(defaultLayerIdForSequence(3).value, isNot(startsWith('sample-')));
    });

    test('rejects non-positive sequences', () {
      expect(() => defaultLayerIdForSequence(0), throwsArgumentError);
    });
  });

  test('createDefaultAnimationLayer creates an all-empty (X) layer', () {
    final cut = _cut(layers: [_layer('A'), _layer('B')]);

    final layer = createDefaultAnimationLayer(
      layerId: const LayerId('new-layer'),
      cut: cut,
    );

    expect(layer.name, 'C');
    expect(layer.kind, LayerKind.animation);
    expect(layer.frames, isEmpty);
    expect(layer.timeline, isEmpty);
  });
}

Cut _cut({String id = 'cut-1', List<Layer> layers = const []}) => Cut(
  id: CutId(id),
  name: id,
  layers: layers,
  duration: 1,
  canvasSize: const CanvasSize(width: 1280, height: 720),
);

Layer _layer(String name, {LayerKind kind = LayerKind.animation}) =>
    Layer(id: LayerId('layer-$name'), name: name, frames: const [], kind: kind);
