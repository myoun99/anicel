import 'dart:io';
import 'dart:typed_data';

import '../../core/mask_into_alpha.dart';
import '../../core/srgb_byte.dart';
import 'photoshop_byte_reader.dart';
import '../../models/import/import_warning.dart';

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
  required List<ImportWarning> warnings,
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
  required List<ImportWarning> warnings,
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
  warnings.add(
    const ImportWarning(
      'psd32Bit',
      '32-bit predicted channel data is not supported.',
    ),
  );
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
          samples[y * width + x] = _eightBitOf(
            view.getFloat32(rowStart + x * 4),
          );
        }
      }
    default:
      throw FormatException('Unsupported Photoshop bit depth $depth.');
  }
  return samples;
}

/// A 32-bit sample [value] (1.0 = full) as 8 bits, cut to 0…255.
///
/// 🧭관제 (gpu-export-path ③, 2026-11-05): a sample that is no number
/// stands at the end it leans to — NaN and −∞ 0, +∞ 255 — where `round`
/// used to throw and take the whole import with it.
int _eightBitOf(double value) {
  if (value.isNaN || value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 255;
  }
  return (value * 255).round();
}

/// Turns colour planes into straight (un-premultiplied) RGBA8: the whole
/// picture, packed by [PsdPlanes] — what the composite is read as.
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
  required List<ImportWarning> warnings,
}) {
  final rgba = Uint8List(width * height * 4);
  PsdPlanes(
    mode: mode,
    colorPlanes: colorPlanes,
    alphaPlane: alphaPlane,
    width: width,
    height: height,
    palette: palette,
    warnings: warnings,
  ).packInto(rgba, from: 0, count: width * height);
  return rgba;
}

/// A picture as its file holds it — a plane a channel, [width] × [height] —
/// packed into straight RGBA8 a run of pixels at a time ([packInto]): the
/// whole of it, or a row of a layer as it is cut into tiles.
///
/// 🚨★★**A LAYER IS NEVER PACKED WHOLE TO BE CUT** (card
/// psd-planes-pack-on-the-engine, 2026-11-16): its rows go into the tile
/// cutter packed one at a time, as a PNG's and a JPEG's go in as they are
/// inflated (`cutFileInWorker`). 🔬Packing a layer whole was 27–29 % of
/// laying an 8K document of four layers out as cels (Surface, profile),
/// but what packing it a row at a time saves is the whole RGBA only: the
/// worker's pack and cut of three 8K layers and a small one went 1,136 →
/// 1,068 ms (−6 %, the two turn about in one process), the same tiles.
/// Of the rest the cutter is 772 ms, the pack about 300 — packing is not
/// where the time is. ⛔A pixel written as one word was SLOWER (110 ms an
/// 8K layer against 66–70 — its alpha asked through a closure), and four
/// a load faster by a fifth only.
/// ⛔Not on the engine, as the card first said: what this makes is cut on
/// the worker it runs on, which has no engine.
final class PsdPlanes {
  /// Says once, into [warnings], what a mode it can only convert loses.
  PsdPlanes({
    required this.mode,
    required List<Uint8List> colorPlanes,
    required Uint8List? alphaPlane,
    required this.width,
    required this.height,
    required Uint8List? palette,
    required List<ImportWarning> warnings,
  }) : _colour = colorPlanes,
       _alpha = alphaPlane,
       _palette = palette != null && palette.length >= 768 ? palette : null {
    final said = switch (mode) {
      PsdColorMode.duotone => const ImportWarning(
        'psdDuotone',
        'Duotone read as grayscale.',
      ),
      PsdColorMode.multichannel => const ImportWarning(
        'psdMultichannel',
        'Multichannel read as grayscale of its first channel.',
      ),
      PsdColorMode.indexed when _palette == null => const ImportWarning(
        'psdIndexedNoPalette',
        'Indexed colour without a palette read as grayscale.',
      ),
      PsdColorMode.cmyk => const ImportWarning(
        'psdCmyk',
        'CMYK converted to RGB without a profile — colour shifts.',
      ),
      PsdColorMode.lab => const ImportWarning(
        'psdLab',
        'Lab converted to RGB without a profile — colour shifts.',
      ),
      _ => null,
    };
    if (said != null) {
      warnings.add(said);
    }
  }

  final PsdColorMode mode;
  final int width;
  final int height;
  final List<Uint8List> _colour;
  final Uint8List? _alpha;

  /// Null where the file gave none, or one short of its 768 bytes.
  final Uint8List? _palette;

  Uint8List _plane(int index) => index < _colour.length
      ? _colour[index]
      : Uint8List(width * height);

  /// Pixels [from] to [from] + [count] — counted row after row across the
  /// planes — packed into [rgba] from its first byte.
  void packInto(Uint8List rgba, {required int from, required int count}) {
    final end = from + count;
    void grey(Uint8List v) {
      for (var i = from, o = 0; i < end; i += 1, o += 4) {
        rgba[o] = v[i];
        rgba[o + 1] = v[i];
        rgba[o + 2] = v[i];
      }
    }

    switch (mode) {
      case PsdColorMode.rgb:
        final r = _plane(0);
        final g = _plane(1);
        final b = _plane(2);
        for (var i = from, o = 0; i < end; i += 1, o += 4) {
          rgba[o] = r[i];
          rgba[o + 1] = g[i];
          rgba[o + 2] = b[i];
        }
      case PsdColorMode.grayscale:
      case PsdColorMode.duotone:
      case PsdColorMode.bitmap:
      case PsdColorMode.multichannel:
        grey(_plane(0));
      case PsdColorMode.indexed:
        final index = _plane(0);
        final palette = _palette;
        if (palette == null) {
          grey(index);
        } else {
          for (var i = from, o = 0; i < end; i += 1, o += 4) {
            final entry = index[i];
            rgba[o] = palette[entry];
            rgba[o + 1] = palette[256 + entry];
            rgba[o + 2] = palette[512 + entry];
          }
        }
      case PsdColorMode.cmyk:
        // Photoshop stores CMYK inverted: 255 means no ink.
        final c = _plane(0);
        final m = _plane(1);
        final y = _plane(2);
        final k = _plane(3);
        for (var i = from, o = 0; i < end; i += 1, o += 4) {
          final ink = 255 - k[i];
          rgba[o] = _clampByte(255 - (255 - c[i]) - ink);
          rgba[o + 1] = _clampByte(255 - (255 - m[i]) - ink);
          rgba[o + 2] = _clampByte(255 - (255 - y[i]) - ink);
        }
      case PsdColorMode.lab:
        final l = _plane(0);
        final a = _plane(1);
        final b = _plane(2);
        for (var i = from, o = 0; i < end; i += 1, o += 4) {
          final rgb = _labToRgb(l[i] * 100 / 255, a[i] - 128.0, b[i] - 128.0);
          rgba[o] = rgb.$1;
          rgba[o + 1] = rgb.$2;
          rgba[o + 2] = rgb.$3;
        }
    }

    final alpha = _alpha;
    if (alpha == null) {
      for (var o = 3; o < count * 4; o += 4) {
        rgba[o] = 255;
      }
    } else {
      for (var i = from, o = 3; i < end; i += 1, o += 4) {
        rgba[o] = alpha[i];
      }
    }
  }
}

int _clampByte(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);

/// A layer's picture as its file holds it: its [planes], their top-left at
/// ([left], [top]) in the document, and the [mask] that is on — baked into
/// alpha as each row is packed.
final class PsdLayerPicture {
  const PsdLayerPicture(
    this.planes, {
    required this.left,
    required this.top,
    this.mask,
  });

  final PsdPlanes planes;
  final int left;
  final int top;
  final LayerMask? mask;

  /// Its [crop] — in its own pixels — a row at a time: each packed and its
  /// mask baked into ONE buffer, handed to [row] with its index from 0 —
  /// and the next row's once [row] returns, so [row] takes what it keeps.
  void rows(
    ({int left, int top, int width, int height}) crop, {
    required void Function(int y, Uint8List rgba) row,
  }) {
    final buffer = Uint8List(crop.width * 4);
    for (var y = 0; y < crop.height; y += 1) {
      planes.packInto(
        buffer,
        from: (crop.top + y) * planes.width + crop.left,
        count: crop.width,
      );
      _bake(buffer, left + crop.left, top + crop.top + y);
      row(y, buffer);
    }
  }

  /// Every pixel of it, row after row — packed whole, each time it is
  /// asked. ⚠️The import never asks: it cuts [rows].
  Uint8List rgba() {
    final width = planes.width;
    final whole = Uint8List(width * planes.height * 4);
    planes.packInto(whole, from: 0, count: width * planes.height);
    for (var y = 0; y < planes.height; y += 1) {
      _bake(
        Uint8List.sublistView(whole, y * width * 4, (y + 1) * width * 4),
        left,
        top + y,
      );
    }
    return whole;
  }

  void _bake(Uint8List row, int left, int top) {
    final mask = this.mask;
    if (mask == null) {
      return;
    }
    applyMaskToAlphaRow(row, left: left, top: top, mask: mask);
  }
}

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
  return (
    srgbByteOf(3.2406 * x - 1.5372 * y - 0.4986 * z),
    srgbByteOf(-0.9689 * x + 1.8758 * y + 0.0415 * z),
    srgbByteOf(0.0557 * x - 0.2040 * y + 1.0570 * z),
  );
}
