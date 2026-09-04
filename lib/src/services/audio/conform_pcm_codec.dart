/// The conformed-audio container (audio program 2B).
///
/// A conform is what a professional tool makes when you import compressed
/// audio: the file decoded once, at the project's sample rate, as plain
/// PCM. Pro Tools converts MP3/AAC on import outright; Premiere writes a
/// `.cfa` and plays from that. Nobody decodes a compressed frame inside the
/// audio callback, because a variable-length codec cannot promise to finish
/// in time and the callback cannot wait.
///
/// 🪦**This used to write a WAV**, and the reason written down for it was
/// 「a standard WAV rather than a private format, on purpose: any audio tool
/// can open it, which makes a suspect conform something you can listen to
/// instead of something you have to reason about」. Compressing the cache
/// killed that: what lands on disk is a zstd block blob
/// ([writeMediaBlob]), so no tool opens it as anything.
///
/// 유저 2026-08-30 asked the question that follows from it — 「애초에 다른
/// 프로그램에서 열 이유가 없다면 wav로 디코드? 할 이유가있나?」 — and the
/// audit found the costume was buying exactly one thing (an ownership tag
/// for the cache collector) while costing two chunk walks that had to
/// agree. See [ConformHeader] for the layout that replaced it and for what
/// stayed identical: every PCM byte.
///
/// ⚠️Listening to a conform elsewhere is an EXPORT now, and it does not
/// exist yet — this comment must not pretend it does. The capability is one
/// line (`conformPcmToFloat32`, or a 44-byte WAV header in front of the
/// PCM, which `export_audio_mix.dart` already writes for the mix); what is
/// missing is a place to put it.
///
/// The source fingerprint rides in the header rather than beside the file,
/// so a conform carries its own provenance and there is no second file to
/// go missing on its own.
///
/// Both directions run OFF the realtime thread — conforming happens at
/// import, loading happens when the timeline opens. Nothing here is
/// reachable from the audio callback.
library;

import 'dart:typed_data';
import '../../models/audio_pcm_scale.dart';

/// What a conformed file records about the source it came from, so a
/// replaced original is detected rather than silently played stale.
///
/// CONTENT, not metadata. This used to be `{length, lastModified}`, which
/// answers "is this the same file on this disk" — a question that goes
/// wrong in both directions. Copying a project made every conform look
/// stale and rebuilt the lot for nothing, and an original edited in place
/// that kept its size and timestamp looked fresh. Neither survives being
/// carried to another machine, which is the case that matters once a
/// project is a single file you hand someone.
///
/// The hash is CRC-32, the same one ZIP stores for every entry, chosen so
/// that moving audio INSIDE the `.anicel` makes this free: the container
/// has already computed it and keeps it in the entry header, so the
/// fingerprint becomes a header read instead of a pass over the bytes.
class ConformSourceFingerprint {
  const ConformSourceFingerprint({
    required this.sourceLength,
    required this.sourceCrc32,
  });

  /// The original file's length in bytes. Kept alongside the hash as a
  /// cheap disambiguator — CRC-32 is 32 bits, and this is cache
  /// validation, not integrity.
  final int sourceLength;

  /// CRC-32 of the original's bytes.
  final int sourceCrc32;

  bool matches(ConformSourceFingerprint other) =>
      sourceLength == other.sourceLength && sourceCrc32 == other.sourceCrc32;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConformSourceFingerprint &&
          other.sourceLength == sourceLength &&
          other.sourceCrc32 == sourceCrc32;

  @override
  int get hashCode => Object.hash(sourceLength, sourceCrc32);

  @override
  String toString() =>
      'ConformSourceFingerprint(length: $sourceLength, '
      'crc32: $sourceCrc32)';
}

/// The CHEAP half of "has this source changed": what `stat` says.
///
/// Not an identity — that is [ConformSourceFingerprint], which reads the
/// bytes. This is a hint that lets the common case skip that read: if the
/// source still has the length and timestamp it had when the conform was
/// written, nothing has touched it on this machine and the conform stands.
///
/// A miss means nothing on its own. A copied, restored or re-synced file
/// gets a fresh timestamp with identical bytes, and that is exactly the
/// case a timestamp identity used to answer wrong — so a miss falls
/// through to the content hash rather than deciding anything.
class ConformSourceStat {
  const ConformSourceStat({
    required this.sourceLength,
    required this.sourceModifiedMicros,
  });

  final int sourceLength;
  final int sourceModifiedMicros;

  bool matches(ConformSourceStat other) =>
      sourceLength == other.sourceLength &&
      sourceModifiedMicros == other.sourceModifiedMicros;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConformSourceStat &&
          other.sourceLength == sourceLength &&
          other.sourceModifiedMicros == sourceModifiedMicros;

  @override
  int get hashCode => Object.hash(sourceLength, sourceModifiedMicros);

  @override
  String toString() =>
      'ConformSourceStat(length: $sourceLength, '
      'modified: $sourceModifiedMicros)';
}

/// A decoded conform: interleaved samples plus what they mean.
///
/// 🪦This line used to sit above [ConformSourceStat], which was inserted
/// underneath it — so the stat class wore two opening sentences and this
/// class had none.
class ConformAudio {
  const ConformAudio({
    required this.samples,
    required this.channels,
    required this.sampleRate,
    this.fingerprint,
    this.sourceStat,
    this.speedNumerator = 1,
    this.speedDenominator = 1,
  });

  /// Interleaved by channel, normalized to [-1, 1].
  ///
  /// float32 in memory even though the file stores int16: the mixer sums in
  /// double and reads floats, and int16 → float32 is EXACT (float32 carries
  /// a 24-bit mantissa, so every 16-bit value lands on itself). Half the
  /// disk, none of the loss.
  final Float32List samples;

  final int channels;
  final int sampleRate;

  /// Null when the header carries no fingerprint — which counts as STALE,
  /// because nothing is known about what those samples came from.
  final ConformSourceFingerprint? fingerprint;

  /// What `stat` said about the source when this was written, so a reuse
  /// can be decided without reading it. Null on conforms written before
  /// the hint existed — which costs one read, not a rebuild.
  final ConformSourceStat? sourceStat;

  /// The audio speed this conform was rendered at (EXPORT-AUDIO ④): 1001/
  /// 1000 is the NTSC pull that keeps frame alignment across a 23.976↔24
  /// change. Unity on every conform written before the field existed —
  /// absent keys read as 1/1.
  final int speedNumerator;
  final int speedDenominator;

  /// Samples per channel.
  int get length => channels <= 0 ? 0 : samples.length ~/ channels;

  /// Exact duration in seconds as a ratio — callers wanting frames should
  /// go through `ProjectFrameRate.framesCoveringExactSeconds(length,
  /// sampleRate)` rather than dividing here, so no double ever enters the
  /// timing path.
  ({int numerator, int denominator}) get durationSeconds =>
      (numerator: length, denominator: sampleRate <= 0 ? 1 : sampleRate);
}

/// Thrown when bytes are not a conform this project can read.
class ConformFormatException implements Exception {
  const ConformFormatException(this.message);
  final String message;
  @override
  String toString() => 'ConformFormatException: $message';
}

/// 🚨★★★**THE CONFORM'S OWN HEADER — ONE FIXED LAYOUT, PARSED IN ONE PLACE.**
///
/// A conform used to be a WAV: `RIFF`/`WAVE` with `fmt `, a private `qacf`
/// chunk holding the provenance as JSON, and `data`. The reason written down
/// for that was 「any audio tool can open it, which makes a suspect conform
/// something you can listen to instead of something you have to reason
/// about」 — and compressing the cache killed it. The bytes on disk are a
/// zstd block blob; nothing opens them as a WAV, so the costume bought
/// nothing and cost two chunk walks that had to agree.
///
/// 유저 2026-08-30, told exactly that: 「애초에 다른프로그램에서 열 이유가
/// 없다면 wav로 디코드? 할 이유가있나?」 — and, on being shown what changes:
/// 「사본 없어지는건 좋아. 구조적으로 깔끔해지는게 좋네」.
///
/// ⛔**The audio did not change.** Same interleaved 16-bit PCM, same order,
/// same 32768 scale. What went away is the envelope: a chunk table that had
/// to be WALKED (twice — [decodeConform] and `ConformPcmStreamReader` each
/// had their own walk, and the stream reader's doc said so out loud) plus a
/// JSON blob for four integers.
///
/// ```
///  0   8  'QACONF01'          magic + version
///  8   4  sampleRate          u32
/// 12   2  channels            u16
/// 14   2  flags               u16   1 = fingerprint, 2 = source stat
/// 16   8  frames              u64   samples PER CHANNEL
/// 24   4  speedNumerator      u32
/// 28   4  speedDenominator    u32
/// 32   8  sourceLength        u64
/// 40   4  sourceCrc32         u32
/// 44   4  (reserved, 0)
/// 48   8  sourceModifiedMicros i64
/// 56   8  (reserved, 0)
/// 64  ..  int16 LE, interleaved
/// ```
///
/// 🔑**64 is not a round number for looks.** The PCM starting on a 64-byte
/// boundary is what lets a reader take an `Int16List.view` over it instead
/// of pulling every sample through `ByteData.getInt16` — and a buffer that
/// begins even keeps that view legal.
///
/// 🚨**The magic is also the OWNERSHIP PROOF** the cache collector needs.
/// That collector may run in a folder the user chose, so it only deletes
/// what it can prove is ours; it used to prove it by finding `RIFF`+`WAVE`
/// +`qacf` together, which is an ASSUMPTION that no other tool writes that
/// combination. This file's own history says what such assumptions cost —
/// a dated render `믹스.20260813.wav` was once counted as cache and evicted.
/// Eight bytes nobody else writes is proof rather than a guess.
class ConformHeader {
  const ConformHeader({
    required this.sampleRate,
    required this.channels,
    required this.frames,
    required this.speedNumerator,
    required this.speedDenominator,
    this.fingerprint,
    this.sourceStat,
  });

  /// Bytes before the first sample. Fixed — that is the whole point.
  static const int length = 64;

  static const List<int> magic = [
    0x51, 0x41, 0x43, 0x4f, 0x4e, 0x46, 0x30, 0x31, // QACONF01
  ];

  static const int _flagFingerprint = 1;
  static const int _flagSourceStat = 2;

  final int sampleRate;
  final int channels;

  /// Samples per channel. The PCM is `frames * channels` int16 values.
  final int frames;

  final int speedNumerator;
  final int speedDenominator;
  final ConformSourceFingerprint? fingerprint;
  final ConformSourceStat? sourceStat;

  /// Bytes of PCM this header claims.
  int get dataBytes => frames * channels * 2;

  /// What the whole file must weigh for the claim to be honest.
  int get totalBytes => length + dataBytes;

  Uint8List toBytes() {
    final out = Uint8List(length);
    out.setRange(0, magic.length, magic);
    final view = ByteData.sublistView(out);
    view.setUint32(8, sampleRate, Endian.little);
    view.setUint16(12, channels, Endian.little);
    view.setUint16(
      14,
      (fingerprint == null ? 0 : _flagFingerprint) |
          (sourceStat == null ? 0 : _flagSourceStat),
      Endian.little,
    );
    view.setUint64(16, frames, Endian.little);
    view.setUint32(24, speedNumerator, Endian.little);
    view.setUint32(28, speedDenominator, Endian.little);
    view.setUint64(32, fingerprint?.sourceLength ?? 0, Endian.little);
    view.setUint32(40, fingerprint?.sourceCrc32 ?? 0, Endian.little);
    view.setInt64(48, sourceStat?.sourceModifiedMicros ?? 0, Endian.little);
    return out;
  }

  /// Parses the first [length] bytes, or throws.
  ///
  /// ⛔Every caller goes through here. The reason this class exists is that
  /// the two readers used to walk the chunk table separately, and a log of
  /// this repo's own bugs says what two spellings of one law do.
  static ConformHeader parse(Uint8List bytes) {
    if (bytes.length < length) {
      throw const ConformFormatException('too short to be a conform');
    }
    for (var i = 0; i < magic.length; i += 1) {
      if (bytes[i] != magic[i]) {
        throw const ConformFormatException('not a conform this app wrote');
      }
    }
    final view = ByteData.sublistView(bytes, 0, length);
    final sampleRate = view.getUint32(8, Endian.little);
    final channels = view.getUint16(12, Endian.little);
    final flags = view.getUint16(14, Endian.little);
    final frames = view.getUint64(16, Endian.little);
    if (sampleRate <= 0) {
      throw const ConformFormatException('conform declares no sample rate');
    }
    if (channels <= 0) {
      throw const ConformFormatException('conform declares no channels');
    }
    final sourceLength = view.getUint64(32, Endian.little);
    final hasFingerprint = flags & _flagFingerprint != 0;
    return ConformHeader(
      sampleRate: sampleRate,
      channels: channels,
      frames: frames,
      speedNumerator: view.getUint32(24, Endian.little),
      speedDenominator: view.getUint32(28, Endian.little),
      fingerprint: hasFingerprint
          ? ConformSourceFingerprint(
              sourceLength: sourceLength,
              sourceCrc32: view.getUint32(40, Endian.little),
            )
          : null,
      sourceStat: flags & _flagSourceStat == 0
          ? null
          : ConformSourceStat(
              sourceLength: sourceLength,
              sourceModifiedMicros: view.getInt64(48, Endian.little),
            ),
    );
  }
}

/// Whether [head] starts with the conform magic — the cheap half of「is this
/// file ours」, and all the cache collector needs before it counts or deletes
/// something in a folder the user chose.
bool looksLikeConform(List<int> head) {
  if (head.length < ConformHeader.magic.length) {
    return false;
  }
  for (var i = 0; i < ConformHeader.magic.length; i += 1) {
    if (head[i] != ConformHeader.magic[i]) {
      return false;
    }
  }
  return true;
}

/// Encodes [samples] as a conform: [ConformHeader] then interleaved 16-bit
/// PCM.
///
/// Values outside [-1, 1] clip: this is a fixed-point container, and unlike
/// the mix bus it has no headroom to offer. Conforms are decoded source
/// material, so anything out of range came in that way.
Uint8List encodeConform({
  required Float32List samples,
  required int channels,
  required int sampleRate,
  ConformSourceFingerprint? fingerprint,
  ConformSourceStat? sourceStat,
  int speedNumerator = 1,
  int speedDenominator = 1,
}) {
  if (channels <= 0) {
    throw const ConformFormatException('channels must be positive');
  }
  if (sampleRate <= 0) {
    throw const ConformFormatException('sampleRate must be positive');
  }
  // ⚠️The stat rides ONLY alongside a fingerprint. It is the cheap half of
  // one question — 「has the source changed」 — and on its own it cannot
  // answer it: a conform written before the fingerprint was content-based
  // carried a timestamp and nothing to derive a hash from, and those had to
  // be treated as unknown. Storing a stat with no fingerprint would put that
  // state back within reach.
  final header = ConformHeader(
    sampleRate: sampleRate,
    channels: channels,
    frames: samples.length ~/ channels,
    speedNumerator: speedNumerator,
    speedDenominator: speedDenominator,
    fingerprint: fingerprint,
    sourceStat: fingerprint == null ? null : sourceStat,
  );
  final out = Uint8List(ConformHeader.length + header.dataBytes);
  out.setRange(0, ConformHeader.length, header.toBytes());
  final view = ByteData.sublistView(out, ConformHeader.length);
  final count = header.frames * channels;
  for (var index = 0; index < count; index += 1) {
    view.setInt16(
      index * 2,
      int16FromUnitSample(samples[index]),
      Endian.little,
    );
  }
  return out;
}

/// 16-bit PCM to float32, at the one scale this app uses.
///
/// 🚨**32768, not 32767** — the industry convention, and what dr_wav uses (it
/// multiplies by the literal 0.000030517578125f). Matching it is not
/// cosmetic: every OTHER format arrives through dr_libs, so a conform read
/// with a different scale than an imported WAV would put the same audio at
/// two different levels depending on which path it took. It also makes a
/// unity-gain clip round trip BIT-EXACTLY through the whole chain: raw ÷
/// 32768 → mix → × 32768 → the same raw sample. The 32767 convention loses
/// that, being off by one LSB at full scale.
///
/// 🔑ONE function, because two spellings of a scale is exactly the shape
/// that puts the same audio at two levels. The whole-file decode and the
/// window read both land here.
///
/// ⚡[Int16List.view] where the buffer allows it: pulling every sample
/// through `ByteData.getInt16` measured 5.04ms for a 32-second stereo window
/// against 4.33ms this way (best of 12, `dart run`). A view needs an EVEN
/// byte offset — [ConformHeader.length] is 64, so a buffer that starts even
/// always qualifies — and the `ByteData` path stays for the ones that do not
/// rather than as a claim that they cannot happen.
Float32List conformPcmToFloat32(Uint8List pcm, int sampleCount) {
  final out = Float32List(sampleCount);
  const scale = 1.0 / 32768.0;
  if (pcm.offsetInBytes.isEven) {
    final src = Int16List.view(pcm.buffer, pcm.offsetInBytes, sampleCount);
    for (var index = 0; index < sampleCount; index += 1) {
      out[index] = src[index] * scale;
    }
    return out;
  }
  final view = ByteData.sublistView(pcm);
  for (var index = 0; index < sampleCount; index += 1) {
    out[index] = view.getInt16(index * 2, Endian.little) * scale;
  }
  return out;
}

/// Decodes a conform written by [encodeConform].
///
/// ⛔A file that is not one — a foreign WAV, a half-written restore, bytes
/// this build cannot decompress — throws rather than being interpreted. The
/// caller's answer to a throw is always the same and always safe: rebuild.
/// That is also what makes writing a restore straight to its final name
/// safe, with no `.part` neighbour to leak.
ConformAudio decodeConform(Uint8List bytes) {
  final header = ConformHeader.parse(bytes);
  if (bytes.length < header.totalBytes) {
    throw const ConformFormatException(
      'conform is short of the PCM it '
      'claims',
    );
  }
  return ConformAudio(
    samples: conformPcmToFloat32(
      Uint8List.sublistView(bytes, ConformHeader.length, header.totalBytes),
      header.frames * header.channels,
    ),
    channels: header.channels,
    sampleRate: header.sampleRate,
    fingerprint: header.fingerprint,
    sourceStat: header.sourceStat,
    speedNumerator: header.speedNumerator,
    speedDenominator: header.speedDenominator,
  );
}

/// A conform with NO fingerprint counts as stale: it was not written by us,
/// so nothing is known about what it came from, and guessing wrong means
/// playing the wrong audio against someone's drawing.
bool conformMatchesSource(
  ConformAudio conform,
  ConformSourceFingerprint current,
) {
  final fingerprint = conform.fingerprint;
  return fingerprint != null && fingerprint.matches(current);
}
