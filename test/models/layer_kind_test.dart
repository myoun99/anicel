import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';

void main() {
  group('LayerKind', () {
    test('serializes stable strings', () {
      expect(LayerKind.animation.toJson(), 'animation');
      expect(LayerKind.storyboard.toJson(), 'storyboard');
      expect(LayerKind.se.toJson(), 'se');
      expect(LayerKind.camera.toJson(), 'camera');
    });

    test('deserializes stable strings', () {
      expect(LayerKind.fromJson('animation'), LayerKind.animation);
      expect(LayerKind.fromJson('storyboard'), LayerKind.storyboard);
      expect(LayerKind.fromJson('se'), LayerKind.se);
      expect(LayerKind.fromJson('camera'), LayerKind.camera);
    });

    test('throws for invalid JSON values', () {
      expect(() => LayerKind.fromJson('panel'), throwsArgumentError);
      expect(() => LayerKind.fromJson(0), throwsArgumentError);
      expect(() => LayerKind.fromJson(null), throwsArgumentError);
    });

    test('the STORYBOARD row is the gapless one, and the only one that '
        'refuses repeat regions (design E)', () {
      expect(layerKindCoversWithoutGaps(LayerKind.storyboard), isTrue);
      expect(layerKindAcceptsRepeatRegions(LayerKind.storyboard), isFalse);

      for (final kind in [LayerKind.animation, LayerKind.art]) {
        expect(layerKindCoversWithoutGaps(kind), isFalse, reason: '$kind');
        expect(layerKindAcceptsRepeatRegions(kind), isTrue, reason: '$kind');
      }

      // Rows that hold no drawings at all take no repeat regions either —
      // the predicate answers for every kind, not just the two it names.
      for (final kind in [LayerKind.camera, LayerKind.folder]) {
        expect(layerKindAcceptsRepeatRegions(kind), isFalse, reason: '$kind');
      }
    });
  });
}
