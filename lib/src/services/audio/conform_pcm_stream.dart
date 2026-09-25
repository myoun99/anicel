import 'dart:typed_data';

import '../media/media_byte_source.dart';
import 'conform_pcm_codec.dart';
import 'wav16_header.dart';

/// Windowed access to a conform (AUDIO-PRO R6).
///
/// A resident conform costs 4 bytes per sample per channel — 23 MB per
/// stereo minute, which on a tablet turns one long dialogue track into
/// the app's whole memory budget. Past a length threshold the PCM stays
/// out of memory and playback reads a sliding WINDOW of it; this reader is
/// the other half of that.
///
/// 🚨★★★**IT READS A [MediaByteSource], NOT A FILE, AND THAT IS THE WHOLE
/// POINT.** A conform lives in three places — plain in the app container,
/// framed (compressed) in the app container, and inside the `.anicel` the
/// project travels as — and all three are already a [MediaByteSource].
/// Handing this one the source instead of a path is what makes those three
/// the SAME code rather than three readers that have to agree about int16
/// scaling forever.
///
/// 🚨★★★**AND THE HEADER IS PARSED BY [ConformHeader], NOT HERE.** This
/// class used to carry its own copy of the WAV chunk walk, and said so:
/// 「The chunk walk mirrors [decodeConform]: order not assumed, unknown
/// chunks skipped」. Two spellings of one law, and this repo's own log says
/// what those do — the failure would be one path opening a conform the
/// other refuses, which a round-trip test cannot see because each path
/// agrees with itself. A fixed header removed the walk from both.
///
/// ⛔It holds no OS handle. That is deliberate, not an oversight: the old
/// reader kept a `RandomAccessFile` open for its whole life, and on
/// Windows that made the cache collector's deletes fail — so the biggest
/// entries survived the emptying that existed to reclaim them. Reads go
/// through [MediaByteSource.readIntoSync], which opens and closes around
/// each one. The cost is tens of microseconds against a read measured in
/// megabytes, and there is nothing left to close.
///
/// Reads are synchronous and run on the CONTROL side (the schedule
/// refresh and the scrubber's re-centre), never the audio callback — the
/// realtime thread only ever touches memory the C side already owns.
///
/// 🚨**WHICH IS WHAT MAKES COMPRESSION SAFE HERE** (유저 2026-08-30:
/// 「재생시 압축해제때문에 오디오가 싱크 안맞으면 절대 안되니 그부분만
/// 철저히」). A framed window costs a decompression of the blocks it lands
/// in — a 30-second stereo window is ~5.8MB across twelve 512KB blocks,
/// about 10ms at the measured 600 MB/s. That is spent on the control side
/// building the NEXT window, half a window ahead of the playhead; the
/// callback plays a `Float32List` that was already materialised. A late
/// window would be silence, never a slip: the schedule's
/// `source_start`/`length` describe what actually came back, so a short
/// read shortens the source rather than shifting it.
///
/// ⛔The window size is the deadline. Halving `aheadSeconds` would halve
/// the margin this stands on.
class ConformPcmStreamReader {
  ConformPcmStreamReader._(
    this._source, {
    required ({int channels, int sampleRate, int frames}) layout,
    required int dataOffset,
  }) : channels = layout.channels,
       sampleRate = layout.sampleRate,
       length = layout.frames,
       _dataOffset = dataOffset;

  final MediaByteSource _source;

  /// Where the samples start — after whichever header the file wears.
  final int _dataOffset;

  final int channels;
  final int sampleRate;

  /// Samples per channel.
  final int length;

  /// Opens the conform at [path] — framed or not, decided by its name.
  ///
  /// The convenience the callers that hold a path want; [over] is the one
  /// that does the work.
  static ConformPcmStreamReader? open(String path) =>
      over(mediaAppFileSource(path));

  /// Parses [source]'s header, or returns null when it is not a conform
  /// this project wrote — a caller falling back to the resident path,
  /// never a crash.
  static ConformPcmStreamReader? over(MediaByteSource source) =>
      _over(source, ConformHeader.length, (head) {
        final header = ConformHeader.parse(head);
        return (
          channels: header.channels,
          sampleRate: header.sampleRate,
          frames: header.frames,
        );
      });

  /// A WAV this app wrote ([readWav16Header]) — the export's mix, which the
  /// OS encoder streams into the movie: the same interleaved 16-bit samples
  /// a conform holds, after another header.
  ///
  /// 🪦The mix was opened with [open] from 08-30, when a conform stopped
  /// being a WAV — so it came back null, and every movie the OS encoder
  /// made went out without its sound (09-25).
  static ConformPcmStreamReader? overWav16(MediaByteSource source) =>
      _over(source, wav16HeaderLength, (head) {
        final wav = readWav16Header(head);
        if (wav == null || wav.channels <= 0) {
          return null;
        }
        return (
          channels: wav.channels,
          sampleRate: wav.sampleRate,
          frames: wav.dataBytes ~/ (2 * wav.channels),
        );
      });

  /// A reader over [source] once its first [headLength] bytes say what it
  /// holds ([layoutOf], null for 「not this kind of file」), or null.
  static ConformPcmStreamReader? _over(
    MediaByteSource source,
    int headLength,
    ({int channels, int sampleRate, int frames})? Function(Uint8List head)
    layoutOf,
  ) {
    try {
      final head = Uint8List(headLength);
      if (source.readIntoSync(head, 0, head.length) < head.length) {
        return null;
      }
      final layout = layoutOf(head);
      // ⛔The file has to actually HOLD what the header claims. A restore
      // killed mid-write leaves a short file, and reading windows out of
      // one would serve silence from beyond the end rather than saying the
      // conform is unusable — which is what makes rebuilding it the
      // caller's automatic answer.
      if (layout == null ||
          source.lengthSync() <
              headLength + layout.frames * 2 * layout.channels) {
        return null;
      }
      return ConformPcmStreamReader._(
        source,
        layout: layout,
        dataOffset: headLength,
      );
    } on Object {
      // A source that will not read, or a framed entry no engine here can
      // decompress: the caller falls back exactly as for a foreign file.
      return null;
    }
  }

  /// Reads [sampleCount] samples per channel starting at [startSample],
  /// interleaved float32. The window is CLAMPED into the file; asking past
  /// either end yields the samples that exist (possibly empty) — the
  /// schedule's source_start/length describe what came back.
  ({int startSample, Float32List samples}) readWindow(
    int startSample,
    int sampleCount,
  ) {
    var start = startSample;
    if (start < 0) {
      start = 0;
    }
    if (start > length) {
      start = length;
    }
    var count = sampleCount;
    if (count < 0) {
      count = 0;
    }
    if (start + count > length) {
      count = length - start;
    }
    if (count == 0) {
      return (startSample: start, samples: Float32List(0));
    }
    try {
      final wanted = count * 2 * channels;
      final bytes = Uint8List(wanted);
      final read = _source.readIntoSync(
        bytes,
        _dataOffset + start * 2 * channels,
        wanted,
      );
      final got = read ~/ (2 * channels);
      return (
        startSample: start,
        // 🔑Through the codec's own converter, so the streamed path and the
        // resident decode cannot land the same audio at two levels.
        samples: conformPcmToFloat32(
          Uint8List.sublistView(bytes, 0, got * 2 * channels),
          got * channels,
        ),
      );
    } on Object {
      // A failed read (file replaced mid-run, drive gone) degrades to
      // silence for this window; the next refresh tries again.
      return (startSample: start, samples: Float32List(0));
    }
  }
}
