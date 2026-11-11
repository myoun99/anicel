// 🗣️gpu-same-formula-Q2 (유저 2026-11-05 「기기가 달라도 같아야 한다」): a
// Lab PSD's colours went through `math.pow`, which IEEE does not require to
// round correctly — another device's libm could move a byte. The power part
// of sRGB's transfer is found among where each byte begins now, and these
// pin both what it gives and that it gives it on every device.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/import/import_warning.dart';
import 'package:anicel/src/services/photoshop/psd_pixels.dart';

void main() {
  // Every L, and every a and b five apart, L slowest — 256 × 52 × 52.
  final steps = [for (var v = 0; v < 256; v += 5) v];
  final width = steps.length * steps.length;
  const height = 256;

  ({Uint8List l, Uint8List a, Uint8List b}) planes() {
    final l = Uint8List(width * height);
    final a = Uint8List(width * height);
    final b = Uint8List(width * height);
    var at = 0;
    for (var lightness = 0; lightness < height; lightness += 1) {
      for (final green in steps) {
        for (final blue in steps) {
          l[at] = lightness;
          a[at] = green;
          b[at] = blue;
          at += 1;
        }
      }
    }
    return (l: l, a: a, b: b);
  }

  Uint8List rgbaOf(({Uint8List l, Uint8List a, Uint8List b}) lab) =>
      psdPlanesToRgba(
        mode: PsdColorMode.lab,
        colorPlanes: [lab.l, lab.a, lab.b],
        alphaPlane: null,
        width: width,
        height: height,
        palette: null,
        warnings: <ImportWarning>[],
      );

  test('🎯a Lab picture comes out as the same bytes on every device', () {
    var hash = 0x811c9dc5;
    for (final byte in rgbaOf(planes())) {
      hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }

    // FNV-1a of the RGBA, written on the Surface Pro 11 (2026-11-11).
    expect(hash.toRadixString(16), '8f200e54');
  });

  test('each byte is sRGB\'s transfer of its Lab colour, as math.pow gives '
      'it', () {
    final lab = planes();
    final rgba = rgbaOf(lab);
    int byteOf(double c) {
      final shown = c <= 0.0031308
          ? 12.92 * c
          : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
      return (shown * 255).round().clamp(0, 255);
    }

    double inverse(double t) =>
        t > 6 / 29 ? t * t * t : 3 * (6 / 29) * (6 / 29) * (t - 4 / 29);
    var apart = 0;
    for (var at = 0; at < width * height; at += 1) {
      final fy = (lab.l[at] * 100 / 255 + 16) / 116;
      final x = 0.95047 * inverse(fy + (lab.a[at] - 128.0) / 500);
      final y = inverse(fy);
      final z = 1.08883 * inverse(fy - (lab.b[at] - 128.0) / 200);
      final wanted = [
        byteOf(3.2406 * x - 1.5372 * y - 0.4986 * z),
        byteOf(-0.9689 * x + 1.8758 * y + 0.0415 * z),
        byteOf(0.0557 * x - 0.2040 * y + 1.0570 * z),
      ];
      for (var channel = 0; channel < 3; channel += 1) {
        if (rgba[at * 4 + channel] != wanted[channel]) {
          apart += 1;
        }
      }
    }

    expect(apart, 0);
  });
}
