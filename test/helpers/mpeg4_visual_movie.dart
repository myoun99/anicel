import 'dart:typed_data';

import 'movie_boxes.dart';

/// A QuickTime movie whose one track is MPEG-4 Visual (Part 2, `mp4v`) —
/// the codec a camera or an old editor writes, which nothing in this app
/// can encode: [frames] intra pictures of [width]×[height], each one flat
/// grey at [lumaOf] its index (chroma neutral), every sample [sampleTicks]
/// long on a clock of [timeScale] — 23.976 unless said.
///
/// The pictures are real: every macroblock is coded intra with its DC alone
/// and the DC predicted from its neighbours, so a decoder hands back the
/// grey that was asked for, and a frame read from the wrong place shows it.
/// The bitstream names its own clock as the container does (a resolution of
/// [timeScale], each picture [sampleTicks] after the last) and, as a
/// camera's does, no fixed rate.
Uint8List mpeg4VisualMovie({
  required int frames,
  int width = 64,
  int height = 48,
  int timeScale = 24000,
  int sampleTicks = 1001,
  int Function(int frame)? lumaOf,
}) {
  final pictures = [
    for (var frame = 0; frame < frames; frame += 1)
      _intraPicture(
        width: width,
        height: height,
        resolution: timeScale,
        ticks: frame * sampleTicks,
        ticksBefore: frame == 0 ? 0 : (frame - 1) * sampleTicks,
        luma: lumaOf?.call(frame) ?? 128,
      ),
  ];
  final data = [for (final picture in pictures) ...picture];
  final head = [
    ...box('ftyp', [...tag('qt  '), ...u32(0x200), ...tag('qt  ')]),
    ...box('wide', const []),
  ];
  final mdatHeader = [...u32(8 + data.length), ...tag('mdat')];
  final dataAt = head.length + mdatHeader.length;
  final duration = frames * sampleTicks;
  const matrix = [0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000];
  final configuration = _configuration(
    width: width,
    height: height,
    resolution: timeScale,
  );
  final decoderConfig = [
    0x20, // Visual ISO/IEC 14496-2
    0x11, // a visual stream, downstream
    0, 0, 0, // buffer size
    ...u32(0), ...u32(0), // max and average bit rate
    0x05, configuration.length, ...configuration,
  ];
  final elementary = [
    ...u16(1), // ES_ID
    0, // no dependence, no URL, no OCR stream
    0x04, decoderConfig.length, ...decoderConfig,
    0x06, 1, 0x02, // SL config: predefined for MP4
  ];
  final track = box('trak', [
    ...box('tkhd', [
      ...u32(0xF), // enabled, in movie, in preview, in poster
      ...u32(0), ...u32(0), // created, modified
      ...u32(1),
      ...u32(0),
      ...u32(duration),
      ...List.filled(8, 0),
      ...u16(0), ...u16(0), // layer, alternate group
      ...u16(0), ...u16(0), // volume
      for (final value in matrix) ...u32(value),
      ...u32(width << 16), ...u32(height << 16),
    ]),
    ...box('mdia', [
      ...box('mdhd', [
        ...u32(0),
        ...u32(0), ...u32(0), // created, modified
        ...u32(timeScale),
        ...u32(duration),
        ...u16(0), ...u16(0), // language, quality
      ]),
      ...handlerBox('mhlr', 'vide'),
      ...box('minf', [
        ...box('vmhd', [...u32(1), ...u16(0), ...u16(0), ...u16(0), ...u16(0)]),
        ...handlerBox('dhlr', 'url '),
        ...box('dinf', [
          ...box('dref', [
            ...u32(0),
            ...u32(1),
            ...box('url ', u32(1)), // the data is in this file
          ]),
        ]),
        ...box('stbl', [
          ...box('stsd', [
            ...u32(0),
            ...u32(1),
            ...box('mp4v', [
              ...List.filled(6, 0),
              ...u16(1), // data reference
              ...u16(0), ...u16(0), // version, revision
              ...u32(0), ...u32(0), ...u32(0), // vendor, qualities
              ...u16(width), ...u16(height),
              ...u32(0x480000), ...u32(0x480000), // 72 dpi each way
              ...u32(0), // data size
              ...u16(1), // frames per sample
              ...List.filled(32, 0), // an empty compressor name
              ...u16(24), // depth
              ...u16(0xFFFF), // no colour table
              ...box('esds', [
                ...u32(0),
                0x03, elementary.length, ...elementary,
              ]),
            ]),
          ]),
          ...box('stts', [
            ...u32(0),
            ...u32(1),
            ...u32(frames), ...u32(sampleTicks),
          ]),
          ...box('stsc', [
            ...u32(0),
            ...u32(1),
            ...u32(1), ...u32(frames), ...u32(1),
          ]),
          ...box('stsz', [
            ...u32(0),
            ...u32(0), // sizes differ: one each
            ...u32(frames),
            for (final picture in pictures) ...u32(picture.length),
          ]),
          ...box('stco', [...u32(0), ...u32(1), ...u32(dataAt)]),
        ]),
      ]),
    ]),
  ]);
  final movie = box('moov', [
    ...box('mvhd', [
      ...u32(0),
      ...u32(0), ...u32(0), // created, modified
      ...u32(timeScale),
      ...u32(duration),
      ...u32(0x10000), // rate 1.0
      ...u16(0x100), // volume 1.0
      ...List.filled(10, 0),
      for (final value in matrix) ...u32(value),
      ...List.filled(24, 0), // preview, poster, selection, current
      ...u32(2), // next track id
    ]),
    ...track,
  ]);
  return Uint8List.fromList([...head, ...mdatHeader, ...data, ...movie]);
}

/// The sequence, object and layer headers a decoder is configured from
/// (the decoder specific info): Simple Profile, rectangular, progressive.
List<int> _configuration({
  required int width,
  required int height,
  required int resolution,
}) =>
    (_Bits()
          ..put(0x000001B0, 32) // visual object sequence
          ..put(0x01, 8) // Simple Profile, level 1
          ..put(0x000001B5, 32) // visual object
          ..put(0, 1) // no identifier
          ..put(1, 4) // video
          ..put(0, 1) // no signal type
          ..alignToStartCode()
          ..put(0x00000100, 32) // video object 0
          ..put(0x00000120, 32) // video object layer 0
          ..put(0, 1) // not random accessible
          ..put(1, 8) // Simple Object
          ..put(0, 1) // no layer identifier: version 1
          ..put(1, 4) // square pixels
          ..put(0, 1) // no control parameters
          ..put(0, 2) // rectangular
          ..put(1, 1)
          ..put(resolution, 16) // ticks a second
          ..put(1, 1)
          ..put(0, 1) // no fixed rate
          ..put(1, 1)
          ..put(width, 13)
          ..put(1, 1)
          ..put(height, 13)
          ..put(1, 1)
          ..put(0, 1) // progressive
          ..put(1, 1) // no overlapped motion
          ..put(0, 1) // no sprite
          ..put(0, 1) // 8 bits
          ..put(0, 1) // H.263 quantisation
          ..put(1, 1) // no complexity estimation
          ..put(1, 1) // no resync markers
          ..put(0, 1) // not partitioned
          ..put(0, 1) // not scalable
          ..alignToStartCode())
        .bytes;

/// One intra picture at [ticks] of a [resolution]-a-second clock, every
/// macroblock flat at [luma] with neutral chroma.
///
/// At a quantiser of 4 the DC scaler is 8 for both planes, so a DC level IS
/// the sample value, and every block outside the picture predicts 1024/8 =
/// 128: the first luma block carries [luma] - 128 and every block after it
/// predicts exactly what it holds, so it carries nothing.
List<int> _intraPicture({
  required int width,
  required int height,
  required int resolution,
  required int ticks,
  required int ticksBefore,
  required int luma,
}) {
  final bits = _Bits()
    ..put(0x000001B6, 32)
    ..put(0, 2); // intra
  // A one for every second boundary since the picture before, then a zero.
  final seconds = ticks ~/ resolution - ticksBefore ~/ resolution;
  for (var second = 0; second < seconds; second += 1) {
    bits.put(1, 1);
  }
  bits
    ..put(0, 1)
    ..put(1, 1)
    ..put(ticks % resolution, (resolution - 1).bitLength.clamp(1, 16))
    ..put(1, 1)
    ..put(1, 1) // coded
    ..put(0, 3) // the DC table throughout
    ..put(4, 5); // quantiser
  final macroblocks = ((width + 15) ~/ 16) * ((height + 15) ~/ 16);
  for (var macroblock = 0; macroblock < macroblocks; macroblock += 1) {
    bits
      ..put(1, 1) // intra, no chroma coefficients
      ..put(0, 1) // no AC prediction
      ..put(0x3, 4); // no luma coefficients
    for (var block = 0; block < 6; block += 1) {
      final difference = macroblock == 0 && block == 0 ? luma - 128 : 0;
      final size = difference.abs().bitLength;
      final (code, length) = block < 4 ? _lumaDcSize[size] : _chromaDcSize[size];
      bits.put(code, length);
      if (size > 0) {
        // Negative differences are sent as their ones' complement.
        bits.put(difference > 0 ? difference : difference + (1 << size) - 1,
            size);
      }
    }
  }
  return (bits..alignToStartCode()).bytes;
}

/// The DC size codes, (code, length) by size — ISO/IEC 14496-2 tables B-13
/// (luminance) and B-14 (chrominance).
const _lumaDcSize = [
  (3, 3), (3, 2), (2, 2), (2, 3), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7),
];
const _chromaDcSize = [
  (3, 2), (2, 2), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8),
];

/// Bits written most significant first.
final class _Bits {
  final _bytes = <int>[];
  var _pending = 0;
  var _count = 0;

  void put(int value, int width) {
    for (var bit = width - 1; bit >= 0; bit -= 1) {
      _pending = (_pending << 1) | ((value >> bit) & 1);
      _count += 1;
      if (_count == 8) {
        _bytes.add(_pending);
        _pending = 0;
        _count = 0;
      }
    }
  }

  /// A zero, then ones to the byte — a whole byte of them when already on
  /// one — so the next start code is aligned.
  void alignToStartCode() {
    put(0, 1);
    while (_count != 0) {
      put(1, 1);
    }
  }

  List<int> get bytes => _bytes;
}
