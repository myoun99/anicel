import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';

void main() {
  group('Layer.kind', () {
    test('defaults to animation kind', () {
      expect(_layer().kind, LayerKind.animation);
    });

    test('copyWith changes kind and preserves other fields', () {
      final layer = _layer();

      final storyboardLayer = layer.copyWith(kind: LayerKind.storyboard);

      expect(storyboardLayer.kind, LayerKind.storyboard);
      expect(storyboardLayer.id, layer.id);
      expect(storyboardLayer.name, layer.name);
      expect(storyboardLayer.frames, layer.frames);
      expect(storyboardLayer.timeline, layer.timeline);
      expect(storyboardLayer.isVisible, layer.isVisible);
      expect(storyboardLayer.opacity, layer.opacity);
    });

    test('equality and hashCode include kind', () {
      final animationLayer = _layer();
      final storyboardLayer = _layer(kind: LayerKind.storyboard);

      expect(storyboardLayer, isNot(animationLayer));
      expect(storyboardLayer.hashCode, isNot(animationLayer.hashCode));
      expect(
        storyboardLayer,
        animationLayer.copyWith(kind: LayerKind.storyboard),
      );
    });

    test('JSON round-trip preserves kind', () {
      final layer = _layer(kind: LayerKind.storyboard);

      final restoredLayer = Layer.fromJson(layer.toJson());

      expect(restoredLayer, layer);
      expect(restoredLayer.kind, LayerKind.storyboard);
      expect(layer.toJson()['kind'], 'storyboard');
    });

    test('old JSON without kind defaults to animation', () {
      final json = _layer(kind: LayerKind.storyboard).toJson()..remove('kind');

      final restoredLayer = Layer.fromJson(json);

      expect(restoredLayer.kind, LayerKind.animation);
    });

    test('fromJson throws for invalid kind JSON', () {
      final json = _layer().toJson()..['kind'] = 'panel';

      expect(() => Layer.fromJson(json), throwsArgumentError);
    });
  });

  group('Layer.onTimesheet and Layer.mark', () {
    test('default to on-timesheet with no mark', () {
      final layer = _layer();

      expect(layer.onTimesheet, isTrue);
      expect(layer.mark, LayerMark.none);
    });

    test('copyWith changes the flags and preserves other fields', () {
      final layer = _layer();

      final updated = layer.copyWith(onTimesheet: false, mark: LayerMark.blue);

      expect(updated.onTimesheet, isFalse);
      expect(updated.mark, LayerMark.blue);
      expect(updated.id, layer.id);
      expect(updated.name, layer.name);
      expect(updated.frames, layer.frames);
      expect(updated.timeline, layer.timeline);
      expect(updated.kind, layer.kind);
    });

    test('equality and hashCode include both flags', () {
      final layer = _layer();

      expect(layer.copyWith(onTimesheet: false), isNot(layer));
      expect(layer.copyWith(mark: LayerMark.red), isNot(layer));
      expect(
        layer.copyWith(mark: LayerMark.red).hashCode,
        isNot(layer.hashCode),
      );
      expect(layer.copyWith(mark: LayerMark.red), _layer(mark: LayerMark.red));
    });

    test('JSON round-trip preserves both flags', () {
      final layer = _layer(mark: LayerMark.green).copyWith(onTimesheet: false);

      final restoredLayer = Layer.fromJson(layer.toJson());

      expect(restoredLayer, layer);
      expect(restoredLayer.onTimesheet, isFalse);
      expect(restoredLayer.mark, LayerMark.green);
      expect(layer.toJson()['onTimesheet'], false);
      expect(layer.toJson()['mark'], 'green');
    });

    test('old JSON without the keys defaults to on-timesheet, no mark', () {
      final json = _layer().toJson()
        ..remove('onTimesheet')
        ..remove('mark');

      final restoredLayer = Layer.fromJson(json);

      expect(restoredLayer.onTimesheet, isTrue);
      expect(restoredLayer.mark, LayerMark.none);
    });

    test('fromJson throws for invalid mark JSON', () {
      final json = _layer().toJson()..['mark'] = 'magenta';

      expect(() => Layer.fromJson(json), throwsArgumentError);
    });
  });
}

Layer _layer({
  LayerKind kind = LayerKind.animation,
  LayerMark mark = LayerMark.none,
}) {
  return Layer(
    id: const LayerId('layer-1'),
    name: 'Line',
    frames: [
      Frame(id: const FrameId('frame-1'), duration: 2, strokes: const []),
    ],
    isVisible: false,
    opacity: 0.5,
    kind: kind,
    mark: mark,
  );
}
