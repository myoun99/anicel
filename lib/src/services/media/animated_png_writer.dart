import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import '../persistence/anicel_incremental_writer.dart'
    show anicelCrc32Finish, anicelCrc32Start, anicelCrc32Update;

/// One picture of an animation: straight RGBA, top-down, row after row, and
/// how long it stays up.
typedef AnimatedPngFrame = ({Uint8List rgba, Duration duration});

/// An animated PNG of [frames], every one [width] × [height] — the piece a
/// trimmed animated image is carried as.
///
/// 🗣️유저 2026-09-23: 「비디오든 이미지든 오디오든 관계없이 법 하나로」 —
/// a trimmed file that is carried brings only its span. For a moving
/// picture the span has to come back as a moving picture this app READS,
/// frame for frame and delay for delay, whatever it was made from (a GIF,
/// an animated WebP). APNG is the one such format it can also WRITE without
/// losing a pixel: lossless, any colour, straight alpha — measured to decode
/// frame for frame with its delays through the engine's own codec.
///
/// Every frame is written whole (no sub-rectangles, no blending), so each
/// one stands on its own exactly as it was decoded.
///
/// ⚠️INDEXED WHEN IT CAN BE. A GIF is at most 256 colours a frame, and its
/// trimmed span is usually far fewer in all; written as RGBA it would come
/// back several times the size of the file it was cut from — the opposite
/// of why it was cut. When every frame together uses 256 colours or fewer
/// the file is a palette (with per-entry alpha); only past that is it RGBA.
Uint8List encodeAnimatedPng({
  required int width,
  required int height,
  required List<AnimatedPngFrame> frames,
}) {
  if (frames.isEmpty) {
    throw ArgumentError.value(frames, 'frames', 'an animation needs a frame');
  }
  final palette = _paletteOf(frames);
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(
      _chunk('IHDR', [
        ..._u32(width),
        ..._u32(height),
        8, // bit depth
        if (palette == null) 6 else 3, // RGBA : indexed
        0, 0, 0, // compression, filter, interlace
      ]),
    )
    ..add(_chunk('acTL', [..._u32(frames.length), ..._u32(0)]));
  if (palette != null) {
    out
      ..add(_chunk('PLTE', palette.rgb))
      ..add(_chunk('tRNS', palette.alpha));
  }
  var sequence = 0;
  for (var index = 0; index < frames.length; index += 1) {
    final frame = frames[index];
    out.add(
      _chunk('fcTL', [
        ..._u32(sequence++),
        ..._u32(width),
        ..._u32(height),
        ..._u32(0), // x offset
        ..._u32(0), // y offset
        ..._delay(frame.duration),
        0, // dispose: none — the next frame covers the canvas whole
        0, // blend: source — no frame leans on the one before it
      ]),
    );
    final pixels = ZLibCodec().encode(
      palette == null
          ? _filteredRgba(frame.rgba, width, height)
          : _indexed(frame.rgba, width, height, palette.indexOf),
    );
    out.add(
      index == 0
          ? _chunk('IDAT', pixels)
          : _chunk('fdAT', pixels, sequence: sequence++),
    );
  }
  out.add(_chunk('IEND', const []));
  return out.takeBytes();
}

/// Every colour the frames use, as a PNG palette — or null past 256.
({List<int> rgb, List<int> alpha, int Function(int rgba) indexOf})? _paletteOf(
  List<AnimatedPngFrame> frames,
) {
  final indices = <int, int>{};
  for (final frame in frames) {
    final pixels = ByteData.sublistView(frame.rgba);
    for (var at = 0; at + 3 < frame.rgba.length; at += 4) {
      final colour = pixels.getUint32(at);
      if (indices.containsKey(colour)) {
        continue;
      }
      if (indices.length == 256) {
        return null;
      }
      indices[colour] = indices.length;
    }
  }
  final rgb = <int>[];
  final alpha = <int>[];
  for (final colour in indices.keys) {
    rgb
      ..add(colour >> 24 & 0xFF)
      ..add(colour >> 16 & 0xFF)
      ..add(colour >> 8 & 0xFF);
    alpha.add(colour & 0xFF);
  }
  return (rgb: rgb, alpha: alpha, indexOf: (colour) => indices[colour]!);
}

/// Palette rows, unfiltered — the PNG spec's own advice for indexed images.
Uint8List _indexed(
  Uint8List rgba,
  int width,
  int height,
  int Function(int rgba) indexOf,
) {
  final pixels = ByteData.sublistView(rgba);
  final out = Uint8List(height * (width + 1));
  var at = 0;
  for (var y = 0; y < height; y += 1) {
    out[at++] = 0;
    for (var x = 0; x < width; x += 1) {
      out[at++] = indexOf(pixels.getUint32((y * width + x) * 4));
    }
  }
  return out;
}

/// RGBA rows, each under the filter that leaves it smallest (the usual
/// minimum-sum-of-differences guess).
Uint8List _filteredRgba(Uint8List rgba, int width, int height) {
  const bpp = 4;
  final stride = width * bpp;
  final out = Uint8List(height * (stride + 1));
  final candidate = Uint8List(stride);
  final best = Uint8List(stride);
  for (var y = 0; y < height; y += 1) {
    final row = y * stride;
    final above = row - stride;
    var bestType = 0;
    var bestCost = -1;
    for (var type = 0; type < 5; type += 1) {
      var cost = 0;
      for (var i = 0; i < stride; i += 1) {
        final value = rgba[row + i];
        final left = i >= bpp ? rgba[row + i - bpp] : 0;
        final up = y > 0 ? rgba[above + i] : 0;
        final upLeft = y > 0 && i >= bpp ? rgba[above + i - bpp] : 0;
        final predicted = switch (type) {
          0 => 0,
          1 => left,
          2 => up,
          3 => (left + up) >> 1,
          _ => _paeth(left, up, upLeft),
        };
        final filtered = (value - predicted) & 0xFF;
        candidate[i] = filtered;
        cost += filtered < 128 ? filtered : 256 - filtered;
      }
      if (bestCost < 0 || cost < bestCost) {
        bestCost = cost;
        bestType = type;
        best.setAll(0, candidate);
      }
    }
    final at = y * (stride + 1);
    out[at] = bestType;
    out.setRange(at + 1, at + 1 + stride, best);
  }
  return out;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) {
    return a;
  }
  return pb <= pc ? b : c;
}

/// A frame's delay as fcTL's fraction: milliseconds over a thousand, or —
/// past what sixteen bits of milliseconds can say — whole hundredths.
List<int> _delay(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  if (milliseconds <= 0xFFFF) {
    return [..._u16(milliseconds), ..._u16(1000)];
  }
  final hundredths = (milliseconds / 10).round();
  return [..._u16(hundredths > 0xFFFF ? 0xFFFF : hundredths), ..._u16(100)];
}

/// A PNG chunk: length, type, [data] — led by [sequence] when there is one
/// (an fdAT's number) — and the CRC over all of it but the length.
///
/// ⚠️Folded piece by piece, never spread into one list: a frame's pixels
/// are megabytes, and a literal that spread them would build a list of that
/// many boxed integers to checksum it.
Uint8List _chunk(String type, List<int> data, {int? sequence}) {
  final parts = [
    Uint8List.fromList(type.codeUnits),
    if (sequence != null) _u32(sequence),
    if (data is Uint8List) data else Uint8List.fromList(data),
  ];
  var crc = anicelCrc32Start;
  var length = 0;
  for (final part in parts.skip(1)) {
    length += part.length;
  }
  for (final part in parts) {
    crc = anicelCrc32Update(crc, part);
  }
  final out = BytesBuilder(copy: false)..add(_u32(length));
  for (final part in parts) {
    out.add(part);
  }
  return (out..add(_u32(anicelCrc32Finish(crc)))).takeBytes();
}

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

Uint8List _u16(int value) =>
    (ByteData(2)..setUint16(0, value)).buffer.asUint8List();
