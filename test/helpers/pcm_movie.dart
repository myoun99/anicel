import 'dart:typed_data';

import 'movie_boxes.dart';

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
    ...box('ftyp', [...tag('qt  '), ...u32(0x200), ...tag('qt  ')]),
    ...box('wide', const []),
  ];
  final mdatHeader = long
      ? [...u32(1), ...tag('mdat'), ...u64(16 + pcm.lengthInBytes)]
      : [...u32(8 + pcm.lengthInBytes), ...tag('mdat')];
  // Where the first sample lands: past the head and the sound box's header.
  final soundAt = head.length + mdatHeader.length;
  const matrix = [0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000];
  // The dates and the duration, wide in a version-1 header.
  List<int> times(int scale, int duration) => long
      ? [...u64(0), ...u64(0), ...u32(scale), ...u64(duration)]
      : [...u32(0), ...u32(0), ...u32(scale), ...u32(duration)];
  final version = long ? 0x01000000 : 0;
  List<int> editList(List<({int from, int keep})> list) => box('edts', [
        ...box('elst', [
          ...u32(version),
          ...u32(list.length),
          for (final edit in list) ...[
            // The length in the movie's time scale, the start in the
            // media's.
            if (long)
              ...u64(onTheMovieClock(edit.keep))
            else
              ...u32(onTheMovieClock(edit.keep)),
            if (long) ...u64(edit.from) else ...u32(edit.from),
            ...u32(0x10000), // played at 1.0
          ],
        ]),
      ]);
  List<int> trackHeader(int id) => box('tkhd', [
        ...u32(0xF), // enabled, in movie, in preview, in poster
        ...u32(0), ...u32(0), // created, modified
        ...u32(id),
        ...u32(0),
        ...u32(onTheMovieClock(frames)), // duration
        ...List.filled(8, 0),
        ...u16(0), ...u16(0), // layer, alternate group
        ...u16(0x100), ...u16(0), // volume
        for (final value in matrix) ...u32(value),
        ...u32(0), ...u32(0), // width, height
      ]);
  final timecode = box('trak', [
    ...trackHeader(1),
    ...editList([(from: 7, keep: 100)]),
    ...box('mdia', [
      ...box('mdhd', [...u32(version), ...times(rate, 0), ...u32(0)]),
      ...handlerBox('mhlr', 'tmcd'),
      ...box('minf', [
        ...box('stbl', [
          ...box('stsd', [...u32(0), ...u32(0)]),
          ...box('stts', [...u32(0), ...u32(0)]),
          ...box('stsc', [...u32(0), ...u32(0)]),
          ...box('stsz', [...u32(0), ...u32(0), ...u32(0)]),
          ...box('stco', [...u32(0), ...u32(0)]),
        ]),
      ]),
    ]),
  ]);
  final sound = box('trak', [
    ...trackHeader(timecodeFirst ? 2 : 1),
    if (edits != null) ...editList(edits),
    ...box('mdia', [
      ...box('mdhd', [
        ...u32(version),
        ...times(rate, frames),
        ...u16(0), ...u16(0), // language, quality
      ]),
      ...handlerBox('mhlr', 'soun'),
      ...box('minf', [
        ...box('smhd', [...u32(0), ...u16(0), ...u16(0)]),
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
            ...box(bigEndian ? 'twos' : 'sowt', [
              ...List.filled(6, 0),
              ...u16(1), // data reference
              ...u16(0), ...u16(0), ...u32(0), // version 0
              ...u16(channels),
              ...u16(16),
              ...u16(0), ...u16(0), // compression, packet size
              ...u32(rate << 16),
            ]),
          ]),
          ...box('stts', [
            ...u32(0),
            ...u32(1),
            ...u32(frames), ...u32(1), // every frame lasts one tick
          ]),
          ...box('stsc', [
            ...u32(0),
            ...u32(1),
            ...u32(1), ...u32(frames), ...u32(1),
          ]),
          ...box('stsz', [
            ...u32(0),
            ...u32(channels * 2), // one frame's bytes
            ...u32(frames),
          ]),
          ...box('stco', [...u32(0), ...u32(1), ...u32(soundAt)]),
        ]),
      ]),
    ]),
  ]);
  final movieBody = [
    ...box('mvhd', [
      ...u32(version),
      ...times(movieClock, onTheMovieClock(frames)),
      ...u32(0x10000), // rate 1.0
      ...u16(0x100), // volume 1.0
      ...List.filled(10, 0),
      for (final value in matrix) ...u32(value),
      ...List.filled(24, 0), // preview, poster, selection, current
      ...u32(timecodeFirst ? 3 : 2), // next track id
    ]),
    if (timecodeFirst) ...timecode,
    ...sound,
  ];
  return Uint8List.fromList([
    ...head,
    ...mdatHeader,
    ...pcm.buffer.asUint8List(),
    ...box('moov', movieBody),
  ]);
}
