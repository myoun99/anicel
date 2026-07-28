import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/rgba_color.dart';
import 'package:anicel/src/services/rgba_blend.dart';

void main() {
  group('rgbaDestinationOut', () {
    final destination = RgbaColor(r: 200, g: 100, b: 50, a: 255);

    test('removes destination alpha by the effective source alpha', () {
      final result = rgbaDestinationOut(
        source: RgbaColor(r: 0, g: 0, b: 0, a: 255),
        destination: destination,
        opacity: 0.5,
        flow: 1,
      );

      expect(result.a, 128);
      expect(result.r, 200);
      expect(result.g, 100);
      expect(result.b, 50);
    });

    test('full effective alpha zeroes the pixel', () {
      final result = rgbaDestinationOut(
        source: RgbaColor(r: 0, g: 0, b: 0, a: 255),
        destination: destination,
        opacity: 1,
        flow: 1,
      );

      expect(result, RgbaColor(r: 0, g: 0, b: 0, a: 0));
    });

    test('non-effective source leaves the destination untouched', () {
      for (final result in [
        rgbaDestinationOut(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          destination: destination,
          opacity: 1,
          flow: 1,
        ),
        rgbaDestinationOut(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 255),
          destination: destination,
          opacity: 0,
          flow: 1,
        ),
        rgbaDestinationOut(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 255),
          destination: destination,
          opacity: 1,
          flow: 0,
        ),
      ]) {
        expect(result, destination);
      }
    });

    test('erasing a transparent destination stays transparent', () {
      final result = rgbaDestinationOut(
        source: RgbaColor(r: 0, g: 0, b: 0, a: 255),
        destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
        opacity: 0.5,
        flow: 1,
      );

      expect(result.a, 0);
    });
  });

  group('effectiveSourceAlpha', () {
    test('returns source alpha multiplied by opacity and flow', () {
      expect(
        effectiveSourceAlpha(
          source: RgbaColor(r: 10, g: 20, b: 30, a: 128),
          opacity: 0.5,
          flow: 0.25,
        ),
        closeTo((128 / 255.0) * 0.5 * 0.25, 0.0000001),
      );
    });

    test('returns 0 for transparent source', () {
      expect(
        effectiveSourceAlpha(
          source: RgbaColor(r: 10, g: 20, b: 30, a: 0),
          opacity: 1,
          flow: 1,
        ),
        0,
      );
    });

    test('returns 0 when opacity is 0', () {
      expect(
        effectiveSourceAlpha(
          source: RgbaColor(r: 10, g: 20, b: 30, a: 255),
          opacity: 0,
          flow: 1,
        ),
        0,
      );
    });

    test('returns 0 when flow is 0', () {
      expect(
        effectiveSourceAlpha(
          source: RgbaColor(r: 10, g: 20, b: 30, a: 255),
          opacity: 1,
          flow: 0,
        ),
        0,
      );
    });

    test('rejects negative opacity', () {
      expect(
        () => effectiveSourceAlpha(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: -0.1,
          flow: 1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects opacity above 1', () {
      expect(
        () => effectiveSourceAlpha(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1.1,
          flow: 1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-finite opacity', () {
      expect(
        () => effectiveSourceAlpha(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: double.nan,
          flow: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => effectiveSourceAlpha(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: double.infinity,
          flow: 1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative flow', () {
      expect(
        () => effectiveSourceAlpha(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: -0.1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects flow above 1', () {
      expect(
        () => effectiveSourceAlpha(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: 1.1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-finite flow', () {
      expect(
        () => effectiveSourceAlpha(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => effectiveSourceAlpha(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: double.infinity,
        ),
        throwsArgumentError,
      );
    });
  });

  group('rgbaSourceOver', () {
    test('returns destination when source alpha is 0', () {
      final destination = RgbaColor(r: 1, g: 2, b: 3, a: 4);
      expect(
        rgbaSourceOver(
          source: RgbaColor(r: 255, g: 0, b: 0, a: 0),
          destination: destination,
          opacity: 1,
          flow: 1,
        ),
        destination,
      );
    });

    test('returns destination when opacity is 0', () {
      final destination = RgbaColor(r: 1, g: 2, b: 3, a: 4);
      expect(
        rgbaSourceOver(
          source: RgbaColor(r: 255, g: 0, b: 0, a: 255),
          destination: destination,
          opacity: 0,
          flow: 1,
        ),
        destination,
      );
    });

    test('returns destination when flow is 0', () {
      final destination = RgbaColor(r: 1, g: 2, b: 3, a: 4);
      expect(
        rgbaSourceOver(
          source: RgbaColor(r: 255, g: 0, b: 0, a: 255),
          destination: destination,
          opacity: 1,
          flow: 0,
        ),
        destination,
      );
    });

    test('blends opaque source over transparent destination', () {
      expect(
        rgbaSourceOver(
          source: RgbaColor(r: 255, g: 0, b: 0, a: 255),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: 1,
        ),
        RgbaColor(r: 255, g: 0, b: 0, a: 255),
      );
    });

    test('blends half-alpha source over transparent destination', () {
      expect(
        rgbaSourceOver(
          source: RgbaColor(r: 255, g: 0, b: 0, a: 128),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: 1,
        ),
        RgbaColor(r: 255, g: 0, b: 0, a: 128),
      );
    });

    test('blends half-alpha source over opaque destination', () {
      expect(
        rgbaSourceOver(
          source: RgbaColor(r: 255, g: 0, b: 0, a: 128),
          destination: RgbaColor(r: 0, g: 0, b: 255, a: 255),
          opacity: 1,
          flow: 1,
        ),
        RgbaColor(r: 128, g: 0, b: 127, a: 255),
      );
    });

    test('preserves fully transparent result as 0,0,0,0', () {
      expect(
        rgbaSourceOver(
          source: RgbaColor(r: 10, g: 20, b: 30, a: 0),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: 1,
        ),
        RgbaColor(r: 0, g: 0, b: 0, a: 0),
      );
    });

    test('rejects invalid opacity', () {
      expect(
        () => rgbaSourceOver(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: -0.1,
          flow: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => rgbaSourceOver(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1.1,
          flow: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => rgbaSourceOver(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: double.nan,
          flow: 1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid flow', () {
      expect(
        () => rgbaSourceOver(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: -0.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => rgbaSourceOver(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: 1.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => rgbaSourceOver(
          source: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          destination: RgbaColor(r: 0, g: 0, b: 0, a: 0),
          opacity: 1,
          flow: double.infinity,
        ),
        throwsArgumentError,
      );
    });

    test('clamps rounded component values to 0..255', () {
      expect(
        rgbaSourceOver(
          source: RgbaColor(r: 255, g: 255, b: 255, a: 255),
          destination: RgbaColor(r: 255, g: 255, b: 255, a: 255),
          opacity: 1,
          flow: 1,
        ),
        RgbaColor(r: 255, g: 255, b: 255, a: 255),
      );
    });

    test('returns a new RgbaColor value', () {
      final source = RgbaColor(r: 200, g: 100, b: 50, a: 128);
      final destination = RgbaColor(r: 50, g: 100, b: 200, a: 128);
      final result = rgbaSourceOver(
        source: source,
        destination: destination,
        opacity: 0.5,
        flow: 0.5,
      );

      expect(result, isA<RgbaColor>());
      expect(identical(result, source), isFalse);
      expect(identical(result, destination), isFalse);
    });
  });
}
