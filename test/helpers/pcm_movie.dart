import 'dart:typed_data';

/// A QuickTime movie whose one track is uncompressed sound — the shape an
/// editor's reel has (H.264 or ProRes beside PCM) without the picture, which
/// the sound decoder never reads and nothing here could encode.
///
/// [samples] are interleaved 16-bit frames of [channels], stored the way
/// ffmpeg's `.mov` writer stores them: little-endian (`sowt`), or big-endian
/// (`twos`) when [bigEndian]; one chunk, the movie's boxes after the sound.
///
/// [edits] writes the sound track an edit list — each plays `keep` frames
/// from frame `from`, and a `from` of -1 is an empty edit (`keep` frames of
/// nothing): what an encoder writes when it put frames of its own before the
/// sound. [long] writes the shape a long movie takes: version-1 headers and
/// edits, and the sound box with a 64-bit size. [timecodeFirst] puts a
/// timecode track with an edit list of its own before the sound track, as
/// editors' reels have. The movie's clock ticks [movieScale] a second (the
/// rate unless said — QuickTime's own is 600); an edit's `keep` is written
/// in it, its `from` in the sound's own clock, the rate.
Uint8List pcmMovie(
  Int16List samples, {
  int channels = 2,
  int rate = 48000,
  bool bigEndian = false,
  List<({int from, int keep})>? edits,
  bool long = false,
  bool timecodeFirst = false,
  int? movieScale,
}) {
  final frames = samples.length ~/ channels;
  final movieClock = movieScale ?? rate;
  int onTheMovieClock(int count) => count * movieClock ~/ rate;
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
  final mdatHeader = long
      ? [..._u32(1), ..._tag('mdat'), ..._u64(16 + pcm.lengthInBytes)]
      : [..._u32(8 + pcm.lengthInBytes), ..._tag('mdat')];
  // Where the first sample lands: past the head and the sound box's header.
  final soundAt = head.length + mdatHeader.length;
  const matrix = [0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000];
  // The dates and the duration, wide in a version-1 header.
  List<int> times(int scale, int duration) => long
      ? [..._u64(0), ..._u64(0), ..._u32(scale), ..._u64(duration)]
      : [..._u32(0), ..._u32(0), ..._u32(scale), ..._u32(duration)];
  final version = long ? 0x01000000 : 0;
  List<int> editList(List<({int from, int keep})> list) => _box('edts', [
        ..._box('elst', [
          ..._u32(version),
          ..._u32(list.length),
          for (final edit in list) ...[
            // The length in the movie's time scale, the start in the
            // media's.
            if (long)
              ..._u64(onTheMovieClock(edit.keep))
            else
              ..._u32(onTheMovieClock(edit.keep)),
            if (long) ..._u64(edit.from) else ..._u32(edit.from),
            ..._u32(0x10000), // played at 1.0
          ],
        ]),
      ]);
  List<int> trackHeader(int id) => _box('tkhd', [
        ..._u32(0xF), // enabled, in movie, in preview, in poster
        ..._u32(0), ..._u32(0), // created, modified
        ..._u32(id),
        ..._u32(0),
        ..._u32(onTheMovieClock(frames)), // duration
        ...List.filled(8, 0),
        ..._u16(0), ..._u16(0), // layer, alternate group
        ..._u16(0x100), ..._u16(0), // volume
        for (final value in matrix) ..._u32(value),
        ..._u32(0), ..._u32(0), // width, height
      ]);
  final timecode = _box('trak', [
    ...trackHeader(1),
    ...editList([(from: 7, keep: 100)]),
    ..._box('mdia', [
      ..._box('mdhd', [..._u32(version), ...times(rate, 0), ..._u32(0)]),
      ..._handler('mhlr', 'tmcd'),
      ..._box('minf', [
        ..._box('stbl', [
          ..._box('stsd', [..._u32(0), ..._u32(0)]),
          ..._box('stts', [..._u32(0), ..._u32(0)]),
          ..._box('stsc', [..._u32(0), ..._u32(0)]),
          ..._box('stsz', [..._u32(0), ..._u32(0), ..._u32(0)]),
          ..._box('stco', [..._u32(0), ..._u32(0)]),
        ]),
      ]),
    ]),
  ]);
  final sound = _box('trak', [
    ...trackHeader(timecodeFirst ? 2 : 1),
    if (edits != null) ...editList(edits),
    ..._box('mdia', [
      ..._box('mdhd', [
        ..._u32(version),
        ...times(rate, frames),
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
  ]);
  final movieBody = [
    ..._box('mvhd', [
      ..._u32(version),
      ...times(movieClock, onTheMovieClock(frames)),
      ..._u32(0x10000), // rate 1.0
      ..._u16(0x100), // volume 1.0
      ...List.filled(10, 0),
      for (final value in matrix) ..._u32(value),
      ...List.filled(24, 0), // preview, poster, selection, current
      ..._u32(timecodeFirst ? 3 : 2), // next track id
    ]),
    if (timecodeFirst) ...timecode,
    ...sound,
  ];
  return Uint8List.fromList([
    ...head,
    ...mdatHeader,
    ...pcm.buffer.asUint8List(),
    ..._box('moov', movieBody),
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

List<int> _u64(int value) => [..._u32(value >> 32), ..._u32(value)];

List<int> _u32(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

List<int> _u16(int value) => [(value >> 8) & 0xFF, value & 0xFF];
