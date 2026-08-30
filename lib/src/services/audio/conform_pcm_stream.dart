import 'dart:typed_data';

import '../media/media_byte_source.dart';
import 'conform_pcm_codec.dart';

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
  ConformPcmStreamReader._(this._source, this._header);

  final MediaByteSource _source;
  final ConformHeader _header;

  int get channels => _header.channels;
  int get sampleRate => _header.sampleRate;

  /// Samples per channel.
  int get length => _header.frames;

  /// Opens the conform at [path] — framed or not, decided by its name.
  ///
  /// The convenience the callers that hold a path want; [over] is the one
  /// that does the work.
  static ConformPcmStreamReader? open(String path) =>
      over(mediaAppFileSource(path));

  /// Parses [source]'s header, or returns null when it is not a conform
  /// this project wrote — a caller falling back to the resident path,
  /// never a crash.
  static ConformPcmStreamReader? over(MediaByteSource source) {
    try {
      final head = Uint8List(ConformHeader.length);
      if (source.readIntoSync(head, 0, head.length) < head.length) {
        return null;
      }
      final header = ConformHeader.parse(head);
      // ⛔The file has to actually HOLD what the header claims. A restore
      // killed mid-write leaves a short file, and reading windows out of
      // one would serve silence from beyond the end rather than saying the
      // conform is unusable — which is what makes rebuilding it the
      // caller's automatic answer.
      if (source.lengthSync() < header.totalBytes) {
        return null;
      }
      return ConformPcmStreamReader._(source, header);
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
        ConformHeader.length + start * 2 * channels,
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
