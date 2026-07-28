import 'package:flutter_test/flutter_test.dart';
import '../helpers/json_round_trip.dart';
import 'package:anicel/src/models/rgba_color.dart';

void main() {
  group('RgbaColor', () {


    test('rejects r below 0', () {
      expect(() => RgbaColor(r: -1, g: 0, b: 0, a: 0), throwsArgumentError);
    });

    test('rejects r above 255', () {
      expect(() => RgbaColor(r: 256, g: 0, b: 0, a: 0), throwsArgumentError);
    });

    test('rejects g below 0', () {
      expect(() => RgbaColor(r: 0, g: -1, b: 0, a: 0), throwsArgumentError);
    });

    test('rejects g above 255', () {
      expect(() => RgbaColor(r: 0, g: 256, b: 0, a: 0), throwsArgumentError);
    });

    test('rejects b below 0', () {
      expect(() => RgbaColor(r: 0, g: 0, b: -1, a: 0), throwsArgumentError);
    });

    test('rejects b above 255', () {
      expect(() => RgbaColor(r: 0, g: 0, b: 256, a: 0), throwsArgumentError);
    });

    test('rejects a below 0', () {
      expect(() => RgbaColor(r: 0, g: 0, b: 0, a: -1), throwsArgumentError);
    });

    test('rejects a above 255', () {
      expect(() => RgbaColor(r: 0, g: 0, b: 0, a: 256), throwsArgumentError);
    });

    test('fromArgbInt converts 0xAARRGGBB to RGBA components', () {
      final color = RgbaColor.fromArgbInt(0x80FF3366);
      expect(color.a, 0x80);
      expect(color.r, 0xFF);
      expect(color.g, 0x33);
      expect(color.b, 0x66);
    });

    test('fromArgbInt rejects negative color', () {
      expect(() => RgbaColor.fromArgbInt(-1), throwsArgumentError);
    });

    test('fromArgbInt rejects color greater than 0xFFFFFFFF', () {
      expect(() => RgbaColor.fromArgbInt(0x100000000), throwsArgumentError);
    });

    test('toArgbInt returns 0xAARRGGBB', () {
      expect(RgbaColor(r: 255, g: 51, b: 102, a: 128).toArgbInt(), 0x80FF3366);
    });

    test('toRgbaBytes returns [r, g, b, a]', () {
      expect(RgbaColor.fromArgbInt(0x80FF3366).toRgbaBytes(), [
        255,
        51,
        102,
        128,
      ]);
    });

    test('copyWith updates r', () {
      expect(RgbaColor(r: 1, g: 2, b: 3, a: 4).copyWith(r: 9).r, 9);
    });

    test('copyWith updates g', () {
      expect(RgbaColor(r: 1, g: 2, b: 3, a: 4).copyWith(g: 9).g, 9);
    });

    test('copyWith updates b', () {
      expect(RgbaColor(r: 1, g: 2, b: 3, a: 4).copyWith(b: 9).b, 9);
    });

    test('copyWith updates a', () {
      expect(RgbaColor(r: 1, g: 2, b: 3, a: 4).copyWith(a: 9).a, 9);
    });

    test('equality includes all components', () {
      final base = RgbaColor(r: 1, g: 2, b: 3, a: 4);
      expect(base, RgbaColor(r: 1, g: 2, b: 3, a: 4));
      expect(base.copyWith(r: 9), isNot(base));
      expect(base.copyWith(g: 9), isNot(base));
      expect(base.copyWith(b: 9), isNot(base));
      expect(base.copyWith(a: 9), isNot(base));
    });

    test('hashCode is value-based', () {
      expect(
        RgbaColor(r: 1, g: 2, b: 3, a: 4).hashCode,
        RgbaColor(r: 1, g: 2, b: 3, a: 4).hashCode,
      );
    });

    test('toJson/fromJson round-trips', () {
      final color = RgbaColor(r: 255, g: 51, b: 102, a: 128);
      expectJsonRoundTrip(color, RgbaColor.fromJson);
    });


  });
}
