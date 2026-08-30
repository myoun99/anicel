import 'dart:typed_data';

import '../media/media_byte_source.dart';

/// Windowed access to a conform WAV (AUDIO-PRO R6).
///
/// A resident conform costs 4 bytes per sample per channel — 23 MB per
/// stereo minute, which on a tablet turns one long dialogue track into
/// the app's whole memory budget. Past a length threshold the PCM stays
/// out of memory and playback reads a sliding WINDOW of it; this reader is
/// the other half of that.
///
/// 🚨★★★**IT READS A [MediaByteSource], NOT A FILE, AND THAT IS THE WHOLE
/// POINT.** A conform now lives in three places — plain in the app
/// container, framed (compressed) in the app container, and inside the
/// `.anicel` the project travels as — and all three are already a
/// [MediaByteSource]. Handing this one the source instead of a path is
/// what makes those three the SAME code rather than three readers that
/// have to agree about int16 scaling forever.
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
/// ⛔The window size is the deadline. Halving [aheadSeconds] would halve
/// the margin this stands on.
///
/// The chunk walk mirrors [decodeConformWav]: order not assumed, unknown
/// chunks skipped. Only the header is parsed at open; the data chunk is
/// left where it is.
class ConformWavStreamReader {
  ConformWavStreamReader._(
    this._source,
    this.channels,
    this.sampleRate,
    this.length,
    this._dataStart,
  );

  final MediaByteSource _source;

  final int channels;
  final int sampleRate;

  /// Samples per channel in the data chunk.
  final int length;

  /// Byte offset of the first data sample, in the WAV's own bytes.
  final int _dataStart;

  static const int _riff = 0x46464952; // 'RIFF'
  static const int _wave = 0x45564157; // 'WAVE'
  static const int _fmt = 0x20746d66; // 'fmt '
  static const int _data = 0x61746164; // 'data'

  /// Opens the conform at [path] — framed or not, decided by its name.
  ///
  /// The convenience the callers that hold a path want; [over] is the one
  /// that does the work.
  static ConformWavStreamReader? open(String path) =>
      over(mediaAppFileSource(path));

  /// Parses [source]'s header, or returns null when it is not a 16-bit PCM
  /// WAV this project writes — a caller falling back to the resident path,
  /// never a crash.
  static ConformWavStreamReader? over(MediaByteSource source) {
    try {
      final sourceLength = source.lengthSync();
      if (sourceLength < 44) {
        return null;
      }
      final head = _read(source, 0, 12);
      if (head == null) {
        return null;
      }
      final headView = ByteData.sublistView(head);
      if (headView.getUint32(0, Endian.little) != _riff ||
          headView.getUint32(8, Endian.little) != _wave) {
        return null;
      }

      int? channels;
      int? sampleRate;
      int? bitsPerSample;
      int? dataStart;
      int? dataBytes;
      var offset = 12;
      while (offset + 8 <= sourceLength) {
        final header = _read(source, offset, 8);
        if (header == null) {
          break;
        }
        final view = ByteData.sublistView(header);
        final id = view.getUint32(0, Endian.little);
        final size = view.getUint32(4, Endian.little);
        final body = offset + 8;
        if (body + size > sourceLength) {
          break;
        }
        if (id == _fmt && size >= 16) {
          final fmt = _read(source, body, 16);
          if (fmt == null) {
            break;
          }
          final fmtView = ByteData.sublistView(fmt);
          channels = fmtView.getUint16(2, Endian.little);
          sampleRate = fmtView.getUint32(4, Endian.little);
          bitsPerSample = fmtView.getUint16(14, Endian.little);
        } else if (id == _data) {
          dataStart = body;
          dataBytes = size;
        }
        offset = body + size + (size.isOdd ? 1 : 0);
      }

      if (channels == null ||
          channels <= 0 ||
          sampleRate == null ||
          sampleRate <= 0 ||
          bitsPerSample != 16 ||
          dataStart == null ||
          dataBytes == null) {
        return null;
      }
      return ConformWavStreamReader._(
        source,
        channels,
        sampleRate,
        dataBytes ~/ (2 * channels),
        dataStart,
      );
    } on Object {
      // A source that will not read, or a framed entry no engine here can
      // decompress: the caller falls back exactly as for a foreign file.
      return null;
    }
  }

  /// Exactly [size] bytes at [position], or null on a short read.
  static Uint8List? _read(MediaByteSource source, int position, int size) {
    final buffer = Uint8List(size);
    return source.readIntoSync(buffer, position, size) < size ? null : buffer;
  }

  /// Reads [sampleCount] samples per channel starting at [startSample],
  /// interleaved float32. The window is CLAMPED into the file; asking past
  /// either end yields the samples that exist (possibly empty) — the
  /// schedule's source_start/length describe what came back.
  ///
  /// The int16 → float32 scale is 32768, matching [decodeConformWav]
  /// exactly: the same audio must never land at two levels depending on
  /// whether it streamed or sat resident.
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
        _dataStart + start * 2 * channels,
        wanted,
      );
      final got = read ~/ (2 * channels);
      final view = ByteData.sublistView(bytes, 0, got * 2 * channels);
      final samples = Float32List(got * channels);
      for (var index = 0; index < samples.length; index += 1) {
        samples[index] = view.getInt16(index * 2, Endian.little) / 32768.0;
      }
      return (startSample: start, samples: samples);
    } on Object {
      // A failed read (file replaced mid-run, drive gone) degrades to
      // silence for this window; the next refresh tries again.
      return (startSample: start, samples: Float32List(0));
    }
  }
}
