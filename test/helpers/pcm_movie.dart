import 'dart:typed_data';

/// A QuickTime movie whose one track is uncompressed sound — the shape an
/// editor's reel has (H.264 or ProRes beside PCM) without the picture, which
/// the sound decoder never reads and nothing here could encode.
///
/// [samples] are interleaved 16-bit frames of [channels], stored the way
/// ffmpeg's `.mov` writer stores them: little-endian (`sowt`), or big-endian
/// (`twos`) when [bigEndian]; one chunk, the movie's boxes after the sound.
///
/// [edit] writes the sound track an edit list: play [edit.keep] frames from
/// frame [edit.from] — what an encoder writes when it put frames of its own
/// before the sound.
Uint8List pcmMovie(
  Int16List samples, {
  int channels = 2,
  int rate = 48000,
  bool bigEndian = false,
  ({int from, int keep})? edit,
}) {
  final frames = samples.length ~/ channels;
  final pcm = ByteData(samples.length * 2);
  for (var index = 0; index < samples.length; index += 1) {
    pcm.setInt16(
      index * 2,
      samples[index],
      bigEndian ? Endian.big : Endian.little,
    );
  }
  final head = [
    ..._box('ftyp', [..._tag('qt  '), ..._u32(0x200), ..._tag('qt  ')]),
    ..._box('wide', const []),
  ];
  // Where the first sample lands: past the head and the sound box's own
  // eight bytes.
  final soundAt = head.length + 8;
  const matrix = [0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000];
  final movie = _box('moov', [
    ..._box('mvhd', [
      ..._u32(0), // version, flags
      ..._u32(0), ..._u32(0), // created, modified
      ..._u32(rate), // time scale
      ..._u32(frames), // duration
      ..._u32(0x10000), // rate 1.0
      ..._u16(0x100), // volume 1.0
      ...List.filled(10, 0),
      for (final value in matrix) ..._u32(value),
      ...List.filled(24, 0), // preview, poster, selection, current
      ..._u32(2), // next track id
    ]),
    ..._box('trak', [
      ..._box('tkhd', [
        ..._u32(0xF), // enabled, in movie, in preview, in poster
        ..._u32(0), ..._u32(0), // created, modified
        ..._u32(1), // track id
        ..._u32(0),
        ..._u32(frames), // duration
        ...List.filled(8, 0),
        ..._u16(0), ..._u16(0), // layer, alternate group
        ..._u16(0x100), ..._u16(0), // volume
        for (final value in matrix) ..._u32(value),
        ..._u32(0), ..._u32(0), // width, height
      ]),
      if (edit != null)
        ..._box('edts', [
          ..._box('elst', [
            ..._u32(0),
            ..._u32(1),
            ..._u32(edit.keep), // in the movie's time scale, which is [rate]
            ..._u32(edit.from), // in the media's, which is [rate] too
            ..._u32(0x10000), // played at 1.0
          ]),
        ]),
      ..._box('mdia', [
        ..._box('mdhd', [
          ..._u32(0),
          ..._u32(0), ..._u32(0),
          ..._u32(rate),
          ..._u32(frames),
          ..._u16(0), ..._u16(0), // language, quality
        ]),
        ..._handler('mhlr', 'soun'),
        ..._box('minf', [
          ..._box('smhd', [..._u32(0), ..._u16(0), ..._u16(0)]),
          ..._handler('dhlr', 'url '),
          ..._box('dinf', [
            ..._box('dref', [
              ..._u32(0),
              ..._u32(1),
              ..._box('url ', _u32(1)), // the data is in this file
            ]),
          ]),
          ..._box('stbl', [
            ..._box('stsd', [
              ..._u32(0),
              ..._u32(1),
              ..._box(bigEndian ? 'twos' : 'sowt', [
                ...List.filled(6, 0),
                ..._u16(1), // data reference
                ..._u16(0), ..._u16(0), ..._u32(0), // version 0
                ..._u16(channels),
                ..._u16(16),
                ..._u16(0), ..._u16(0), // compression, packet size
                ..._u32(rate << 16),
              ]),
            ]),
            ..._box('stts', [
              ..._u32(0),
              ..._u32(1),
              ..._u32(frames), ..._u32(1), // every frame lasts one tick
            ]),
            ..._box('stsc', [
              ..._u32(0),
              ..._u32(1),
              ..._u32(1), ..._u32(frames), ..._u32(1),
            ]),
            ..._box('stsz', [
              ..._u32(0),
              ..._u32(channels * 2), // one frame's bytes
              ..._u32(frames),
            ]),
            ..._box('stco', [..._u32(0), ..._u32(1), ..._u32(soundAt)]),
          ]),
        ]),
      ]),
    ]),
  ]);
  return Uint8List.fromList([
    ...head,
    ..._u32(8 + pcm.lengthInBytes),
    ..._tag('mdat'),
    ...pcm.buffer.asUint8List(),
    ...movie,
  ]);
}

List<int> _handler(String type, String subtype) => _box('hdlr', [
      ..._u32(0),
      ..._tag(type),
      ..._tag(subtype),
      ..._u32(0), ..._u32(0), ..._u32(0), // manufacturer, flags, mask
      0, // an empty name
    ]);

List<int> _box(String type, List<int> body) =>
    [..._u32(8 + body.length), ..._tag(type), ...body];

List<int> _tag(String fourCharacters) => fourCharacters.codeUnits;

List<int> _u32(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

List<int> _u16(int value) => [(value >> 8) & 0xFF, value & 0xFF];
