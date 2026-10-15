import 'dart:typed_data';

import 'png_writing.dart';

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
    ..add(pngSignature)
    ..add(
      pngHeader(
        width: width,
        height: height,
        colourType: palette == null ? pngRgba : pngIndexed,
      ),
    )
    ..add(pngChunk('acTL', [...pngUint32(frames.length), ...pngUint32(0)]));
  if (palette != null) {
    out
      ..add(pngChunk('PLTE', palette.rgb))
      ..add(pngChunk('tRNS', palette.alpha));
  }
  var sequence = 0;
  for (var index = 0; index < frames.length; index += 1) {
    final frame = frames[index];
    out.add(
      pngChunk('fcTL', [
        ...pngUint32(sequence++),
        ...pngUint32(width),
        ...pngUint32(height),
        ...pngUint32(0), // x offset
        ...pngUint32(0), // y offset
        ..._delay(frame.duration),
        0, // dispose: none — the next frame covers the canvas whole
        0, // blend: source — no frame leans on the one before it
      ]),
    );
    final pixels = palette == null
        ? _rgbaData(frame.rgba, width, height)
        : _indexedData(frame.rgba, width, height, palette.indexOf);
    out.add(
      index == 0
          ? pngChunk('IDAT', pixels)
          : pngChunk('fdAT', pixels, sequence: sequence++),
    );
  }
  out.add(pngChunk('IEND', const []));
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
Uint8List _indexedData(
  Uint8List rgba,
  int width,
  int height,
  int Function(int rgba) indexOf,
) {
  final pixels = ByteData.sublistView(rgba);
  final data = PngImageData(width: width, bytesPerPixel: 1, filtered: false);
  final row = Uint8List(width);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      row[x] = indexOf(pixels.getUint32((y * width + x) * 4));
    }
    data.add(row);
  }
  return data.finish();
}

/// RGBA rows, each under the filter that leaves it smallest.
Uint8List _rgbaData(Uint8List rgba, int width, int height) {
  final data = PngImageData(width: width, bytesPerPixel: 4);
  final stride = width * 4;
  for (var y = 0; y < height; y += 1) {
    data.add(Uint8List.sublistView(rgba, y * stride, (y + 1) * stride));
  }
  return data.finish();
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

Uint8List _u16(int value) =>
    (ByteData(2)..setUint16(0, value)).buffer.asUint8List();
