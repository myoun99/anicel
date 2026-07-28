import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';

void main() {
  group('BrushDabSequence', () {
    BrushDab dab(int sequence, {int color = 0xFF000000}) => BrushDab(
      center: CanvasPoint(x: sequence.toDouble(), y: sequence.toDouble()),
      color: color,
      size: 4,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.round,
      pressure: 1,
      sequence: sequence,
    );

    test('empty sequence has length 0', () {
      expect(BrushDabSequence().length, 0);
    });

    test('constructor stores dabs in order', () {
      expect(BrushDabSequence([dab(0), dab(1)]).dabs, [dab(0), dab(1)]);
    });

    test('constructor defensively copies input dabs', () {
      final input = [dab(0)];
      final sequence = BrushDabSequence(input);
      input.add(dab(1));
      expect(sequence.dabs, [dab(0)]);
    });

    test('dabs getter is unmodifiable', () {
      expect(
        () => BrushDabSequence([dab(0)]).dabs.add(dab(1)),
        throwsUnsupportedError,
      );
    });

    test('isEmpty is true for empty sequence', () {
      expect(BrushDabSequence().isEmpty, isTrue);
    });

    test('isNotEmpty is true for non-empty sequence', () {
      expect(BrushDabSequence([dab(0)]).isNotEmpty, isTrue);
    });

    test('firstOrNull returns null for empty sequence', () {
      expect(BrushDabSequence().firstOrNull, isNull);
    });

    test('lastOrNull returns null for empty sequence', () {
      expect(BrushDabSequence().lastOrNull, isNull);
    });

    test('firstOrNull returns first dab', () {
      expect(BrushDabSequence([dab(0), dab(1)]).firstOrNull, dab(0));
    });

    test('lastOrNull returns last dab', () {
      expect(BrushDabSequence([dab(0), dab(1)]).lastOrNull, dab(1));
    });

    test('add returns new sequence with dab appended', () {
      expect(BrushDabSequence([dab(0)]).add(dab(1)).dabs, [dab(0), dab(1)]);
    });

    test('add does not mutate original', () {
      final original = BrushDabSequence([dab(0)]);
      original.add(dab(1));
      expect(original.dabs, [dab(0)]);
    });

    test('addAll returns new sequence with dabs appended', () {
      expect(BrushDabSequence([dab(0)]).addAll([dab(1), dab(2)]).dabs, [
        dab(0),
        dab(1),
        dab(2),
      ]);
    });

    test('equality is order-sensitive', () {
      expect(
        BrushDabSequence([dab(0), dab(1)]),
        BrushDabSequence([dab(0), dab(1)]),
      );
      expect(
        BrushDabSequence([dab(0), dab(1)]),
        isNot(BrushDabSequence([dab(1), dab(0)])),
      );
    });

    test('hashCode is order-sensitive', () {
      expect(
        BrushDabSequence([dab(0), dab(1)]).hashCode,
        isNot(BrushDabSequence([dab(1), dab(0)]).hashCode),
      );
    });

    test('toJson/fromJson round-trips', () {
      final sequence = BrushDabSequence([dab(0), dab(1)]);
      expectJsonRoundTrip(sequence, BrushDabSequence.fromJson);
    });

    test('toJson/fromJson preserves dab color', () {
      final sequence = BrushDabSequence([dab(0, color: 0x80FF3366)]);
      expect(
        BrushDabSequence.fromJson(sequence.toJson()).dabs.single.color,
        0x80FF3366,
      );
    });
  });
}
