import 'dart:typed_data';

import '../../core/on_a_worker.dart';
import '../../native/app_gpu_engine.dart' show appGpuExportKernels;
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
/// the file is a palette (with per-entry alpha), written whole on a worker:
/// its rows go under no filter. Only past that is it RGBA.
///
/// 🚨AN RGBA FRAME'S ROWS GO UNDER THEIR FILTERS ON THE ENGINE
/// (`GpuExport.pngStraight`, `png.wgsl` — the law every PNG this app writes
/// is filtered by), one frame at a time, its wait the engine thread's; a
/// worker only deflates them and lays out the file. ↩️Till 2026-11-16 the
/// worker filtered them itself, five filters tried on every row in Dart —
/// width × height × 4 bytes for each kept frame (card
/// the-trimmed-apng-filters-its-rows-in-dart).
Future<Uint8List> encodeAnimatedPng({
  required int width,
  required int height,
  required List<AnimatedPngFrame> frames,
}) async {
  if (frames.isEmpty) {
    throw ArgumentError.value(frames, 'frames', 'an animation needs a frame');
  }
  final indexed = await onAWorker(() => _indexedPng(width, height, frames));
  if (indexed != null) {
    return indexed;
  }
  final export = await appGpuExportKernels.ready;
  final rows = <Uint8List>[];
  for (final frame in frames) {
    final filtered = export.pngStraight(frame.rgba, width, height);
    await filtered.mapping();
    rows.add(filtered.takePngRows(width, height, 4));
  }
  return _rgbaPng(width, height, [
    for (var index = 0; index < frames.length; index += 1)
      (rows: rows[index], duration: frames[index].duration),
  ]);
}

/// [frames] — each its rows under their filters — deflated and laid out as
/// an RGBA animated PNG, on a worker.
///
/// ⚠️A function of its own so the worker's closure holds these alone: one
/// made in [encodeAnimatedPng] shares its scope with the frames' pixels the
/// palette's worker was handed, and would carry them over again.
Future<Uint8List> _rgbaPng(
  int width,
  int height,
  List<({Uint8List rows, Duration duration})> frames,
) => onAWorker(
  () => _animatedPng(
    width: width,
    height: height,
    colourType: pngRgba,
    frames: [
      for (final frame in frames)
        (data: pngDeflated(frame.rows), duration: frame.duration),
    ],
  ),
);

/// [frames] as a palette's animated PNG — or null past 256 colours.
Uint8List? _indexedPng(
  int width,
  int height,
  List<AnimatedPngFrame> frames,
) {
  final palette = _paletteOf(frames);
  if (palette == null) {
    return null;
  }
  return _animatedPng(
    width: width,
    height: height,
    colourType: pngIndexed,
    palette: (rgb: palette.rgb, alpha: palette.alpha),
    frames: [
      for (final frame in frames)
        (
          data: pngDeflated(
            pngUnfiltered(_indicesOf(frame.rgba, palette.indexOf), width),
          ),
          duration: frame.duration,
        ),
    ],
  );
}

/// The file of [frames] — each its image data, deflated, and how long it
/// stays up — of [colourType], led by [palette]'s entries where it is one.
Uint8List _animatedPng({
  required int width,
  required int height,
  required int colourType,
  ({List<int> rgb, List<int> alpha})? palette,
  required List<({Uint8List data, Duration duration})> frames,
}) {
  final out = BytesBuilder(copy: false)
    ..add(pngSignature)
    ..add(pngHeader(width: width, height: height, colourType: colourType))
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
    out.add(
      index == 0
          ? pngChunk('IDAT', frame.data)
          : pngChunk('fdAT', frame.data, sequence: sequence++),
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

/// [rgba]'s pixels as their palette entries, one byte each.
Uint8List _indicesOf(Uint8List rgba, int Function(int rgba) indexOf) {
  final pixels = ByteData.sublistView(rgba);
  final indices = Uint8List(rgba.length ~/ 4);
  for (var at = 0; at < indices.length; at += 1) {
    indices[at] = indexOf(pixels.getUint32(at * 4));
  }
  return indices;
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
