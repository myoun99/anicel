import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';

void main() {
  group('BrushTipShape', () {
    test('round serializes to round', () {
      expect(BrushTipShape.round.toJson(), 'round');
    });

    test('square serializes to square', () {
      expect(BrushTipShape.square.toJson(), 'square');
    });

    test('fromJson parses round', () {
      expect(BrushTipShape.fromJson('round'), BrushTipShape.round);
    });

    test('fromJson parses square', () {
      expect(BrushTipShape.fromJson('square'), BrushTipShape.square);
    });

    test('fromJson throws FormatException for unknown value', () {
      expect(() => BrushTipShape.fromJson('triangle'), throwsFormatException);
    });
  });
}
