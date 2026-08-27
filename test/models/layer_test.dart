import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';

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

      final updated = layer.copyWith(onTimesheet: false, mark: const LayerMark(process: LayerProcess.conte));

      expect(updated.onTimesheet, isFalse);
      expect(updated.mark, const LayerMark(process: LayerProcess.conte));
      expect(updated.id, layer.id);
      expect(updated.name, layer.name);
      expect(updated.frames, layer.frames);
      expect(updated.timeline, layer.timeline);
      expect(updated.kind, layer.kind);
    });

    test('equality and hashCode include both flags', () {
      final layer = _layer();

      expect(layer.copyWith(onTimesheet: false), isNot(layer));
      expect(layer.copyWith(mark: const LayerMark(process: LayerProcess.layout)), isNot(layer));
      expect(
        layer.copyWith(mark: const LayerMark(process: LayerProcess.layout)).hashCode,
        isNot(layer.hashCode),
      );
      expect(layer.copyWith(mark: const LayerMark(process: LayerProcess.layout)), _layer(mark: const LayerMark(process: LayerProcess.layout)));
    });

    test('JSON round-trip preserves both flags', () {
      final layer = _layer(mark: const LayerMark(process: LayerProcess.art)).copyWith(onTimesheet: false);

      final restoredLayer = Layer.fromJson(layer.toJson());

      expect(restoredLayer, layer);
      expect(restoredLayer.onTimesheet, isFalse);
      expect(restoredLayer.mark, const LayerMark(process: LayerProcess.art));
      expect(layer.toJson()['onTimesheet'], false);
      expect(layer.toJson()['mark'], {'process': 'art'});
    });

    test('old JSON without the keys defaults to on-timesheet, no mark', () {
      final json = _layer().toJson()
        ..remove('onTimesheet')
        ..remove('mark');

      final restoredLayer = Layer.fromJson(json);

      expect(restoredLayer.onTimesheet, isTrue);
      expect(restoredLayer.mark, LayerMark.none);
    });

    test('a mark JSON this build does not know reads as NO label rather '
        'than refusing the project', () {
      // ⛔It used to throw, and that was right while a mark was one of eight
      // colour words: an unknown word meant a corrupt file. A mark is a
      // 공정/수정 pair now, and the shape a stored 'red' takes is not
      // corrupt — it is a project written before the colour label existed.
      //
      // 🚨Guessing a stage from a colour would INVENT data: a layer marked
      // "red" could have been any stage, so there is nothing to recover.
      // Refusing to open the project over a label would be worse than
      // opening it without one, which is what this does.
      for (final unknown in <Object>['magenta', 'red', 42]) {
        final json = _layer().toJson()..['mark'] = unknown;
        expect(
          Layer.fromJson(json).mark,
          LayerMark.none,
          reason: 'stored mark $unknown',
        );
      }
    });

    test('a mark whose stage this build knows survives, revise and all', () {
      final json = _layer().toJson()
        ..['mark'] = {'process': 'layout', 'revise': 'animation-director'};

      expect(
        Layer.fromJson(json).mark,
        const LayerMark(
          process: LayerProcess.layout,
          revise: LayerRevise.animationDirector,
        ),
      );
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
