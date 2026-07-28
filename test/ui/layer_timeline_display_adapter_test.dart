import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_display_adapter.dart';

void main() {
  group('horizontalLayerDisplayOrder', () {
    test('empty list returns an empty defensive list', () {
      final layers = <Layer>[];

      final displayLayers = horizontalLayerDisplayOrder(layers);

      expect(displayLayers, isEmpty);
      expect(identical(displayLayers, layers), isFalse);
    });

    test('one layer returns one layer with the same object reference', () {
      final layer = _layer(id: 'layer-a', name: 'A');
      final layers = [layer];

      final displayLayers = horizontalLayerDisplayOrder(layers);

      expect(displayLayers, hasLength(1));
      expect(identical(displayLayers.single, layer), isTrue);
    });

    test('multiple layers reverse raw order into visual stack order', () {
      final layerA = _layer(id: 'layer-a', name: 'A');
      final layerB = _layer(id: 'layer-b', name: 'B');
      final layerC = _layer(id: 'layer-c', name: 'C');

      final displayLayers = horizontalLayerDisplayOrder([
        layerA,
        layerB,
        layerC,
      ]);

      expect(displayLayers, [same(layerC), same(layerB), same(layerA)]);
    });

    test('keeps D directly above A for raw A D B C order', () {
      final layerA = _layer(id: 'layer-a', name: 'A');
      final layerD = _layer(id: 'layer-d', name: 'D');
      final layerB = _layer(id: 'layer-b', name: 'B');
      final layerC = _layer(id: 'layer-c', name: 'C');

      final displayLayers = horizontalLayerDisplayOrder([
        layerA,
        layerD,
        layerB,
        layerC,
      ]);

      expect(displayLayers, [
        same(layerC),
        same(layerB),
        same(layerD),
        same(layerA),
      ]);
    });

    test('returned list is not the same list instance as input', () {
      final layers = [_layer(id: 'layer-a', name: 'A')];

      final displayLayers = horizontalLayerDisplayOrder(layers);

      expect(identical(displayLayers, layers), isFalse);
    });

    test('returned list contains the same Layer object references', () {
      final layerA = _layer(id: 'layer-a', name: 'A');
      final layerB = _layer(id: 'layer-b', name: 'B');
      final layers = [layerA, layerB];

      final displayLayers = horizontalLayerDisplayOrder(layers);

      expect(identical(displayLayers[0], layerB), isTrue);
      expect(identical(displayLayers[1], layerA), isTrue);
    });

    test(
      'mutating the returned list does not mutate the original input list',
      () {
        final layerA = _layer(id: 'layer-a', name: 'A');
        final layerB = _layer(id: 'layer-b', name: 'B');
        final layers = [layerA, layerB];

        final displayLayers = horizontalLayerDisplayOrder(layers);
        displayLayers.removeAt(0);

        expect(layers, [same(layerA), same(layerB)]);
        expect(displayLayers, [same(layerA)]);
      },
    );

    test('animation and storyboard layers are both preserved', () {
      final animation = _layer(id: 'layer-animation', name: 'Animation');
      final storyboard = _layer(
        id: 'layer-storyboard',
        name: 'Storyboard',
        kind: LayerKind.storyboard,
      );

      final displayLayers = horizontalLayerDisplayOrder([
        animation,
        storyboard,
      ]);

      expect(displayLayers, [same(storyboard), same(animation)]);
      expect(displayLayers.map((layer) => layer.kind), [
        LayerKind.storyboard,
        LayerKind.animation,
      ]);
    });

    test('does not sort by name', () {
      final zLayer = _layer(id: 'layer-z', name: 'Z');
      final aLayer = _layer(id: 'layer-a', name: 'A');
      final mLayer = _layer(id: 'layer-m', name: 'M');

      final displayLayers = horizontalLayerDisplayOrder([
        zLayer,
        aLayer,
        mLayer,
      ]);

      expect(displayLayers.map((layer) => layer.name), ['M', 'A', 'Z']);
      expect(displayLayers, [same(mLayer), same(aLayer), same(zLayer)]);
    });

    test('does not sort by LayerKind', () {
      final storyboardA = _layer(
        id: 'layer-storyboard-a',
        name: 'Storyboard A',
        kind: LayerKind.storyboard,
      );
      final animation = _layer(id: 'layer-animation', name: 'Animation');
      final storyboardB = _layer(
        id: 'layer-storyboard-b',
        name: 'Storyboard B',
        kind: LayerKind.storyboard,
      );

      final displayLayers = horizontalLayerDisplayOrder([
        storyboardA,
        animation,
        storyboardB,
      ]);

      expect(displayLayers.map((layer) => layer.kind), [
        LayerKind.storyboard,
        LayerKind.animation,
        LayerKind.storyboard,
      ]);
      expect(displayLayers, [
        same(storyboardB),
        same(animation),
        same(storyboardA),
      ]);
    });

    test('raw A B order displays B above A', () {
      final layerA = _layer(id: 'layer-a', name: 'A');
      final layerB = _layer(id: 'layer-b', name: 'B');

      final displayLayers = horizontalLayerDisplayOrder([layerA, layerB]);

      expect(displayLayers.map((layer) => layer.name), ['B', 'A']);
      expect(displayLayers, [same(layerB), same(layerA)]);
    });
  });
}

Layer _layer({
  required String id,
  required String name,
  LayerKind kind = LayerKind.animation,
}) {
  return Layer(id: LayerId(id), name: name, frames: const [], kind: kind);
}
