import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_pixel_blend_operation.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/services/brush_dab_sequence_blend.dart';

void main() {
  final transparent = RgbaColor(r: 0, g: 0, b: 0, a: 0);
  final red = RgbaColor(r: 255, g: 0, b: 0, a: 255);
  final blue = RgbaColor(r: 0, g: 0, b: 255, a: 255);

  BrushDab onePixelDab({
    int color = 0xFFFF0000,
    double opacity = 1,
    double flow = 1,
    int sequence = 0,
  }) {
    return BrushDab(
      center: CanvasPoint(x: 10.5, y: 10.5),
      color: color,
      size: 1,
      opacity: opacity,
      flow: flow,
      hardness: 1,
      tipShape: BrushTipShape.round,
      pressure: 1,
      sequence: sequence,
    );
  }

  BrushDab squareDab() {
    return BrushDab(
      center: CanvasPoint(x: 1, y: 1),
      color: 0xFFFF0000,
      size: 2,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
    );
  }

  group('brushPixelBlendOperationsForDab', () {
    test('returns empty list for non-effective dab', () {
      expect(
        brushPixelBlendOperationsForDab(
          dab: onePixelDab(opacity: 0),
          destinationAt: (_, _) => transparent,
        ),
        isEmpty,
      );
    });

    test(
      'returns one operation for one-pixel dab over transparent destination',
      () {
        expect(
          brushPixelBlendOperationsForDab(
            dab: onePixelDab(),
            destinationAt: (_, _) => transparent,
          ),
          [
            BrushPixelBlendOperation(
              x: 10,
              y: 10,
              before: transparent,
              after: red,
            ),
          ],
        );
      },
    );

    test('skips no-op transparent source alpha', () {
      expect(
        brushPixelBlendOperationsForDab(
          dab: onePixelDab(color: 0x00FF0000),
          destinationAt: (_, _) => transparent,
        ),
        isEmpty,
      );
    });

    test('uses destinationAt for before color', () {
      final values = brushPixelBlendOperationsForDab(
        dab: onePixelDab(opacity: 0.5),
        destinationAt: (_, _) => blue,
      );
      expect(values.single.before, blue);
    });

    test('returns unmodifiable list', () {
      final values = brushPixelBlendOperationsForDab(
        dab: onePixelDab(),
        destinationAt: (_, _) => transparent,
      );
      expect(
        () => values.add(
          BrushPixelBlendOperation(x: 1, y: 1, before: transparent, after: red),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('brushPixelBlendOperationsForDabSequence', () {
    test('returns empty list for empty sequence', () {
      expect(
        brushPixelBlendOperationsForDabSequence(
          sequence: BrushDabSequence(),
          destinationAt: (_, _) => transparent,
        ),
        isEmpty,
      );
    });

    test('processes dabs in sequence order', () {
      final values = brushPixelBlendOperationsForDabSequence(
        sequence: BrushDabSequence([
          onePixelDab(color: 0xFFFF0000, sequence: 0),
          onePixelDab(color: 0xFF0000FF, sequence: 1),
        ]),
        destinationAt: (_, _) => transparent,
      );
      expect(values[0].after, red);
      expect(values[1].after, blue);
    });

    test('preserves row-major order inside each dab', () {
      final values = brushPixelBlendOperationsForDabSequence(
        sequence: BrushDabSequence([squareDab()]),
        destinationAt: (_, _) => transparent,
      );
      expect(values.map((value) => (value.x, value.y)), [
        (0, 0),
        (1, 0),
        (0, 1),
        (1, 1),
      ]);
    });

    test(
      'accumulates before color from earlier operations on the same pixel',
      () {
        final values = brushPixelBlendOperationsForDabSequence(
          sequence: BrushDabSequence([
            onePixelDab(color: 0xFFFF0000, sequence: 0),
            onePixelDab(color: 0xFF0000FF, opacity: 0.5, sequence: 1),
          ]),
          destinationAt: (_, _) => transparent,
        );
        expect(values[0].before, transparent);
        expect(values[0].after, red);
        expect(values[1].before, red);
        expect(values[1].after, RgbaColor(r: 128, g: 0, b: 128, a: 255));
      },
    );

    test('does not re-read destinationAt after a pixel was changed', () {
      var reads = 0;
      brushPixelBlendOperationsForDabSequence(
        sequence: BrushDabSequence([
          onePixelDab(color: 0xFFFF0000, sequence: 0),
          onePixelDab(color: 0xFF0000FF, sequence: 1),
        ]),
        destinationAt: (_, _) {
          reads += 1;
          return transparent;
        },
      );
      expect(reads, 1);
    });

    test('skips no-op operations', () {
      final values = brushPixelBlendOperationsForDabSequence(
        sequence: BrushDabSequence([
          onePixelDab(color: 0x00FF0000, sequence: 0),
          onePixelDab(color: 0xFFFF0000, sequence: 1),
        ]),
        destinationAt: (_, _) => transparent,
      );
      expect(values, hasLength(1));
      expect(values.single.after, red);
    });

    test('returns unmodifiable list', () {
      final values = brushPixelBlendOperationsForDabSequence(
        sequence: BrushDabSequence([onePixelDab()]),
        destinationAt: (_, _) => transparent,
      );
      expect(
        () => values.add(
          BrushPixelBlendOperation(x: 1, y: 1, before: transparent, after: red),
        ),
        throwsUnsupportedError,
      );
    });

    test('does not mutate BrushDabSequence', () {
      final sequence = BrushDabSequence([onePixelDab()]);
      final before = BrushDabSequence(sequence.dabs);
      brushPixelBlendOperationsForDabSequence(
        sequence: sequence,
        destinationAt: (_, _) => transparent,
      );
      expect(sequence, before);
    });

    test('does not mutate BrushDab', () {
      final dab = onePixelDab();
      final before = dab.copyWith();
      brushPixelBlendOperationsForDabSequence(
        sequence: BrushDabSequence([dab]),
        destinationAt: (_, _) => transparent,
      );
      expect(dab, before);
    });

    test('does not mutate destination RgbaColor values', () {
      final destination = RgbaColor(r: 1, g: 2, b: 3, a: 4);
      final before = destination.copyWith();
      brushPixelBlendOperationsForDabSequence(
        sequence: BrushDabSequence([onePixelDab(opacity: 0.5)]),
        destinationAt: (_, _) => destination,
      );
      expect(destination, before);
    });
  });
}
