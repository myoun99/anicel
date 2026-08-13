import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'photoshop_byte_reader.dart';

/// The pixel half of the document reader: channel planes in, straight RGBA
/// out. Kept apart from `psd_reader.dart` so the structure parse stays a
/// walk over records and the colour maths stays in one place.

/// Photoshop's colour modes, by the code stored in the file header.
enum PsdColorMode {
  bitmap(0),
  grayscale(1),
  indexed(2),
  rgb(3),
  cmyk(4),
  multichannel(7),
  duotone(8),
  lab(9);

  const PsdColorMode(this.code);

  final int code;

  static PsdColorMode fromCode(int code) {
    for (final mode in values) {
      if (mode.code == code) {
        return mode;
      }
    }
    throw FormatException('Unknown Photoshop colour mode $code.');
  }

  /// How many planes carry colour (the rest are alpha and masks).
  int get colorPlaneCount => switch (this) {
    PsdColorMode.bitmap ||
    PsdColorMode.grayscale ||
    PsdColorMode.indexed ||
    PsdColorMode.duotone ||
    PsdColorMode.multichannel => 1,
    PsdColorMode.rgb || PsdColorMode.lab => 3,
    PsdColorMode.cmyk => 4,
  };
}

/// Bytes one scanline of a [width]-wide plane occupies at [depth].
int psdBytesPerRow({required int width, required int depth}) =>
    depth == 1 ? (width + 7) >> 3 : width * (depth >> 3);

/// Reads one channel plane and normalises it to 8 bits per sample.
///
/// [payloadLength] is what the record said this channel occupies AFTER its
/// two-byte compression tag — the ZIP branches need it because a deflate
/// stream does not announce its own length here.
///
/// Everything above 8 bits comes down to 8: the cel store is 8-bit RGBA, so
/// a 16-bit document is not refused, it is stepped down (and the caller
/// says so out loud).
Uint8List readPsdChannelPlane(
  PhotoshopByteReader reader, {
  required int width,
  required int height,
  required int depth,
  required bool psb,
  required int payloadLength,
  required List<String> warnings,
}) {
  if (width <= 0 || height <= 0) {
    return Uint8List(0);
  }
  final compression = reader.readUint16();
  final bytesPerRow = psdBytesPerRow(width: width, depth: depth);
  final Uint8List raw;
  switch (compression) {
    case 0:
      raw = Uint8List.fromList(reader.readBytes(bytesPerRow * height));
    case 1:
      raw = decodePackBitsScanlines(
        reader,
        bytesPerRow: bytesPerRow,
        height: height,
        scanlineCountBytes: psb ? 4 : 2,
      );
    case 2:
    case 3:
      final deflated = reader.readBytes(payloadLength - 2);
      final inflated = Uint8List.fromList(ZLibDecoder().convert(deflated));
      raw = inflated.length >= bytesPerRow * height
          ? Uint8List.sublistView(inflated, 0, bytesPerRow * height)
          : (Uint8List(bytesPerRow * height)..setAll(0, inflated));
      if (compression == 3) {
        _undoPrediction(
          raw,
          width: width,
          height: height,
          depth: depth,
          bytesPerRow: bytesPerRow,
          warnings: warnings,
        );
      }
    default:
      throw FormatException('Unknown Photoshop compression $compression.');
  }
  return psdPlaneToEightBit(
    raw,
    width: width,
    height: height,
    depth: depth,
    bytesPerRow: bytesPerRow,
  );
}

/// ZIP-with-prediction stores each sample as its delta from the one before
/// it on the same row.
void _undoPrediction(
  Uint8List raw, {
  required int width,
  required int height,
  required int depth,
  required int bytesPerRow,
  required List<String> warnings,
}) {
  if (depth == 8) {
    for (var y = 0; y < height; y += 1) {
      final start = y * bytesPerRow;
      for (var x = 1; x < width; x += 1) {
        raw[start + x] = (raw[start + x] + raw[start + x - 1]) & 0xFF;
      }
    }
    return;
  }
  if (depth == 16) {
    final view = ByteData.sublistView(raw);
    for (var y = 0; y < height; y += 1) {
      final start = y * bytesPerRow;
      for (var x = 1; x < width; x += 1) {
        final previous = view.getUint16(start + (x - 1) * 2);
        final current = view.getUint16(start + x * 2);
        view.setUint16(start + x * 2, (current + previous) & 0xFFFF);
      }
    }
    return;
  }
  // 32-bit prediction transposes the float bytes before delta-coding them,
  // and no animation PSD has ever arrived that way. Saying so beats
  // guessing: the plane reads as noise otherwise, which looks like our bug.
  warnings.add('32-bit predicted channel data is not supported.');
}

Uint8List psdPlaneToEightBit(
  Uint8List raw, {
  required int width,
  required int height,
  required int depth,
  required int bytesPerRow,
}) {
  final samples = Uint8List(width * height);
  switch (depth) {
    case 1:
      for (var y = 0; y < height; y += 1) {
        final rowStart = y * bytesPerRow;
        for (var x = 0; x < width; x += 1) {
          final bit = (raw[rowStart + (x >> 3)] >> (7 - (x & 7))) & 1;
          // Bitmap mode is ink coverage: a set bit is black.
          samples[y * width + x] = bit == 1 ? 0 : 255;
        }
      }
    case 8:
      for (var y = 0; y < height; y += 1) {
        samples.setRange(
          y * width,
          y * width + width,
          raw,
          y * bytesPerRow,
        );
      }
    case 16:
      final view = ByteData.sublistView(raw);
      for (var y = 0; y < height; y += 1) {
        final rowStart = y * bytesPerRow;
        for (var x = 0; x < width; x += 1) {
          samples[y * width + x] = view.getUint16(rowStart + x * 2) >> 8;
        }
      }
    case 32:
      final view = ByteData.sublistView(raw);
      for (var y = 0; y < height; y += 1) {
        final rowStart = y * bytesPerRow;
        for (var x = 0; x < width; x += 1) {
          final value = view.getFloat32(rowStart + x * 4);
          final scaled = (value * 255).round();
          samples[y * width + x] = scaled < 0 ? 0 : (scaled > 255 ? 255 : scaled);
        }
      }
    default:
      throw FormatException('Unsupported Photoshop bit depth $depth.');
  }
  return samples;
}

/// Turns colour planes into straight (un-premultiplied) RGBA8.
///
/// A mode we cannot reproduce exactly is CONVERTED rather than refused —
/// the user's rule is "follow CSP", which opens these and changes their
/// colour rather than turning them away. [warnings] is where that gets
/// said; the import window shows it beside the file.
Uint8List psdPlanesToRgba({
  required PsdColorMode mode,
  required List<Uint8List> colorPlanes,
  required Uint8List? alphaPlane,
  required int width,
  required int height,
  required Uint8List? palette,
  required List<String> warnings,
}) {
  final pixelCount = width * height;
  final rgba = Uint8List(pixelCount * 4);
  Uint8List plane(int index) => index < colorPlanes.length
      ? colorPlanes[index]
      : Uint8List(pixelCount);

  switch (mode) {
    case PsdColorMode.rgb:
      final r = plane(0);
      final g = plane(1);
      final b = plane(2);
      for (var i = 0; i < pixelCount; i += 1) {
        rgba[i * 4] = r[i];
        rgba[i * 4 + 1] = g[i];
        rgba[i * 4 + 2] = b[i];
      }
    case PsdColorMode.grayscale:
    case PsdColorMode.duotone:
    case PsdColorMode.bitmap:
      final v = plane(0);
      for (var i = 0; i < pixelCount; i += 1) {
        rgba[i * 4] = v[i];
        rgba[i * 4 + 1] = v[i];
        rgba[i * 4 + 2] = v[i];
      }
      if (mode == PsdColorMode.duotone) {
        warnings.add('Duotone read as grayscale.');
      }
    case PsdColorMode.multichannel:
      final v = plane(0);
      for (var i = 0; i < pixelCount; i += 1) {
        rgba[i * 4] = v[i];
        rgba[i * 4 + 1] = v[i];
        rgba[i * 4 + 2] = v[i];
      }
      warnings.add('Multichannel read as grayscale of its first channel.');
    case PsdColorMode.indexed:
      final index = plane(0);
      if (palette == null || palette.length < 768) {
        warnings.add('Indexed colour without a palette read as grayscale.');
        for (var i = 0; i < pixelCount; i += 1) {
          rgba[i * 4] = index[i];
          rgba[i * 4 + 1] = index[i];
          rgba[i * 4 + 2] = index[i];
        }
      } else {
        for (var i = 0; i < pixelCount; i += 1) {
          final entry = index[i];
          rgba[i * 4] = palette[entry];
          rgba[i * 4 + 1] = palette[256 + entry];
          rgba[i * 4 + 2] = palette[512 + entry];
        }
      }
    case PsdColorMode.cmyk:
      // Photoshop stores CMYK inverted: 255 means no ink.
      final c = plane(0);
      final m = plane(1);
      final y = plane(2);
      final k = plane(3);
      for (var i = 0; i < pixelCount; i += 1) {
        final ink = 255 - k[i];
        rgba[i * 4] = _clampByte(255 - (255 - c[i]) - ink);
        rgba[i * 4 + 1] = _clampByte(255 - (255 - m[i]) - ink);
        rgba[i * 4 + 2] = _clampByte(255 - (255 - y[i]) - ink);
      }
      warnings.add('CMYK converted to RGB without a profile — colour shifts.');
    case PsdColorMode.lab:
      final l = plane(0);
      final a = plane(1);
      final b = plane(2);
      for (var i = 0; i < pixelCount; i += 1) {
        final rgb = _labToRgb(l[i] * 100 / 255, a[i] - 128.0, b[i] - 128.0);
        rgba[i * 4] = rgb.$1;
        rgba[i * 4 + 1] = rgb.$2;
        rgba[i * 4 + 2] = rgb.$3;
      }
      warnings.add('Lab converted to RGB without a profile — colour shifts.');
  }

  if (alphaPlane == null) {
    for (var i = 0; i < pixelCount; i += 1) {
      rgba[i * 4 + 3] = 255;
    }
  } else {
    for (var i = 0; i < pixelCount; i += 1) {
      rgba[i * 4 + 3] = alphaPlane[i];
    }
  }
  return rgba;
}

/// Multiplies a layer mask into the alpha of [rgba], which is what "bake the
/// mask" means: the covered pixels stop existing.
///
/// The mask carries its OWN rectangle in document space, and anything
/// outside it is [defaultColor] — a black default hides everything the mask
/// does not reach, so ignoring the rectangle is not a small error.
void applyPsdMaskToAlpha(
  Uint8List rgba, {
  required int layerLeft,
  required int layerTop,
  required int layerWidth,
  required int layerHeight,
  required Uint8List mask,
  required int maskLeft,
  required int maskTop,
  required int maskWidth,
  required int maskHeight,
  required int defaultColor,
}) {
  for (var y = 0; y < layerHeight; y += 1) {
    final maskY = layerTop + y - maskTop;
    for (var x = 0; x < layerWidth; x += 1) {
      final maskX = layerLeft + x - maskLeft;
      final inside =
          maskX >= 0 && maskY >= 0 && maskX < maskWidth && maskY < maskHeight;
      final coverage = inside ? mask[maskY * maskWidth + maskX] : defaultColor;
      if (coverage == 255) {
        continue;
      }
      final index = (y * layerWidth + x) * 4 + 3;
      rgba[index] = (rgba[index] * coverage) ~/ 255;
    }
  }
}

int _clampByte(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

/// Lab is defined against a white point; sRGB against D65. The conversion
/// below uses D65 straight through, which is the "no profile" answer the
/// warning beside it announces.

(int, int, int) _labToRgb(double l, double a, double b) {
  final fy = (l + 16) / 116;
  final fx = fy + a / 500;
  final fz = fy - b / 200;
  double inverse(double t) =>
      t > 6 / 29 ? t * t * t : 3 * (6 / 29) * (6 / 29) * (t - 4 / 29);
  // D65, the white point sRGB is defined against.
  final x = 0.95047 * inverse(fx);
  final y = 1.00000 * inverse(fy);
  final z = 1.08883 * inverse(fz);
  double gamma(double c) => c <= 0.0031308
      ? 12.92 * c
      : 1.055 * math.pow(c < 0 ? 0 : c, 1 / 2.4) - 0.055;
  final r = gamma(3.2406 * x - 1.5372 * y - 0.4986 * z);
  final g = gamma(-0.9689 * x + 1.8758 * y + 0.0415 * z);
  final bl = gamma(0.0557 * x - 0.2040 * y + 1.0570 * z);
  return (
    _clampByte((r * 255).round()),
    _clampByte((g * 255).round()),
    _clampByte((bl * 255).round()),
  );
}
