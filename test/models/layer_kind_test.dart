import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_kind.dart';

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
      expect(LayerKind.fromJson('image'), LayerKind.image);
      expect(LayerKind.fromJson('se'), LayerKind.se);
      expect(LayerKind.fromJson('camera'), LayerKind.camera);
    });

    test('the retired ART kind loads as animation (it always behaved as '
        'one — only the icon differed)', () {
      expect(LayerKind.fromJson('art'), LayerKind.animation);
    });

    test('throws for invalid JSON values', () {
      expect(() => LayerKind.fromJson('panel'), throwsArgumentError);
      expect(() => LayerKind.fromJson(0), throwsArgumentError);
      expect(() => LayerKind.fromJson(null), throwsArgumentError);
    });

    test('the COVERING kinds (storyboard, image) are the gapless ones, and '
        'the only ones that refuse repeat regions (design E)', () {
      for (final kind in [LayerKind.storyboard, LayerKind.image]) {
        expect(layerKindCoversWithoutGaps(kind), isTrue, reason: '$kind');
        expect(layerKindAcceptsRepeatRegions(kind), isFalse, reason: '$kind');
      }

      expect(layerKindCoversWithoutGaps(LayerKind.animation), isFalse);
      expect(layerKindAcceptsRepeatRegions(LayerKind.animation), isTrue);

      // Rows that hold no drawings at all take no repeat regions either —
      // the predicate answers for every kind, not just the two it names.
      for (final kind in [LayerKind.camera, LayerKind.folder]) {
        expect(layerKindAcceptsRepeatRegions(kind), isFalse, reason: '$kind');
      }
    });

    test('the IMAGE row: one cel by definition, no timesheet column, an '
        'attach-base drawing cel that still takes the brush at kind level',
        () {
      expect(layerKindHoldsSingleCel(LayerKind.image), isTrue);
      expect(layerKindTakesTimesheetColumn(LayerKind.image), isFalse);
      expect(layerKindIsDrawingCel(LayerKind.image), isTrue);
      expect(layerKindAcceptsBrushInput(LayerKind.image), isTrue);
      expect(layerKindExportsCels(LayerKind.image), isTrue);
      for (final kind in LayerKind.values) {
        if (kind != LayerKind.image) {
          expect(layerKindHoldsSingleCel(kind), isFalse, reason: '$kind');
        }
      }
    });
  });
}
