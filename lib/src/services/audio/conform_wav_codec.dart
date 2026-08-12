/// The conformed-audio container (audio program 2B).
///
/// A conform is what a professional tool makes when you import compressed
/// audio: the file decoded once, at the project's sample rate, as plain
/// PCM. Pro Tools converts MP3/AAC on import outright; Premiere writes a
/// `.cfa` and plays from that. Nobody decodes a compressed frame inside the
/// audio callback, because a variable-length codec cannot promise to finish
/// in time and the callback cannot wait.
///
/// This writes a STANDARD WAV rather than a private format, on purpose:
/// any audio tool can open it, which makes a suspect conform something you
/// can listen to instead of something you have to reason about.
///
/// The source fingerprint rides in a custom `qacf` RIFF chunk. RIFF readers
/// skip chunks they do not know, so the file stays ordinary — and the
/// conform carries its own provenance instead of needing a second file
/// beside it that could go missing on its own.
///
/// Both directions run OFF the realtime thread — conforming happens at
/// import, loading happens when the timeline opens. Nothing here is
/// reachable from the audio callback.
library;

import 'dart:convert';
import 'dart:typed_data';

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

/// A decoded conform: interleaved samples plus what they mean.
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

  /// Null when the file carries no `qacf` chunk (hand-made WAV, or one
  /// written by another tool).
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

/// Thrown when bytes are not a WAV this project can read.
class ConformFormatException implements Exception {
  const ConformFormatException(this.message);
  final String message;
  @override
  String toString() => 'ConformFormatException: $message';
}

const int _riff = 0x46464952; // 'RIFF' little-endian
const int _wave = 0x45564157; // 'WAVE'
const int _fmt = 0x20746d66; // 'fmt '
const int _data = 0x61746164; // 'data'
const int _qacf = 0x66636171; // 'qacf' — our provenance chunk
const int _formatPcm = 1;
const int _formatExtensible = 0xFFFE;

/// Encodes [samples] as a 16-bit PCM WAV.
///
/// Values outside [-1, 1] clip: this is a fixed-point container, and unlike
/// the mix bus it has no headroom to offer. Conforms are decoded source
/// material, so anything out of range came in that way.
Uint8List encodeConformWav({
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

  final fingerprintBytes = fingerprint == null
      ? null
      : Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'sourceLength': fingerprint.sourceLength,
              'sourceCrc32': fingerprint.sourceCrc32,
              if (sourceStat != null)
                'sourceModifiedMicros': sourceStat.sourceModifiedMicros,
              // Unity speed stays out of the JSON: pre-④ conforms carry
              // no keys, and byte-identical output for the common case is
              // worth keeping.
              if (speedNumerator != speedDenominator) ...{
                'speedNumerator': speedNumerator,
                'speedDenominator': speedDenominator,
              },
            }),
          ),
        );
  // RIFF chunks are word-aligned: an odd-length payload carries a pad byte
  // that is NOT counted in the chunk size.
  final fingerprintPadded = fingerprintBytes == null
      ? 0
      : fingerprintBytes.length + (fingerprintBytes.length.isOdd ? 1 : 0);
  final fingerprintChunk = fingerprintBytes == null
      ? 0
      : 8 + fingerprintPadded;

  final dataBytes = samples.length * 2;
  final dataPadded = dataBytes + (dataBytes.isOdd ? 1 : 0);
  final total = 12 + 24 + fingerprintChunk + 8 + dataPadded;
  final out = Uint8List(total);
  final view = ByteData.view(out.buffer);
  var offset = 0;

  view.setUint32(offset, _riff, Endian.little);
  view.setUint32(offset + 4, total - 8, Endian.little);
  view.setUint32(offset + 8, _wave, Endian.little);
  offset += 12;

  final byteRate = sampleRate * channels * 2;
  view.setUint32(offset, _fmt, Endian.little);
  view.setUint32(offset + 4, 16, Endian.little);
  view.setUint16(offset + 8, _formatPcm, Endian.little);
  view.setUint16(offset + 10, channels, Endian.little);
  view.setUint32(offset + 12, sampleRate, Endian.little);
  view.setUint32(offset + 16, byteRate, Endian.little);
  view.setUint16(offset + 20, channels * 2, Endian.little); // block align
  view.setUint16(offset + 22, 16, Endian.little); // bits per sample
  offset += 24;

  if (fingerprintBytes != null) {
    view.setUint32(offset, _qacf, Endian.little);
    view.setUint32(offset + 4, fingerprintBytes.length, Endian.little);
    out.setRange(offset + 8, offset + 8 + fingerprintBytes.length, fingerprintBytes);
    offset += 8 + fingerprintPadded;
  }

  view.setUint32(offset, _data, Endian.little);
  view.setUint32(offset + 4, dataBytes, Endian.little);
  offset += 8;
  for (var index = 0; index < samples.length; index += 1) {
    var value = samples[index];
    if (value > 1.0) {
      value = 1.0;
    } else if (value < -1.0) {
      value = -1.0;
    }
    // 32768, not 32767 — see the note on the decoder below.
    var scaled = (value * 32768.0).round();
    if (scaled > 32767) {
      scaled = 32767;
    }
    view.setInt16(offset + index * 2, scaled, Endian.little);
  }
  return out;
}

/// Decodes a 16-bit PCM WAV written by [encodeConformWav] — and, as far as
/// it can, one written by anything else.
///
/// Chunk order is NOT assumed. Real-world WAVs carry `LIST`, `fact`, `bext`
/// and vendor chunks in whatever order the writer felt like, so this walks
/// the chunk table rather than trusting fmt-then-data.
ConformAudio decodeConformWav(Uint8List bytes) {
  if (bytes.length < 12) {
    throw const ConformFormatException('too short to be a WAV');
  }
  final view = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
  if (view.getUint32(0, Endian.little) != _riff ||
      view.getUint32(8, Endian.little) != _wave) {
    throw const ConformFormatException('not a RIFF/WAVE file');
  }

  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? format;
  int? dataStart;
  int? dataLength;
  ConformSourceFingerprint? fingerprint;
  ConformSourceStat? sourceStat;
  var speedNumerator = 1;
  var speedDenominator = 1;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = view.getUint32(offset, Endian.little);
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (size < 0 || body + size > bytes.length) {
      // A truncated tail: keep whatever complete chunks we already read
      // rather than throwing away a recoverable file.
      break;
    }
    switch (id) {
      case _fmt:
        if (size >= 16) {
          format = view.getUint16(body, Endian.little);
          channels = view.getUint16(body + 2, Endian.little);
          sampleRate = view.getUint32(body + 4, Endian.little);
          bitsPerSample = view.getUint16(body + 14, Endian.little);
        }
      case _data:
        dataStart = body;
        dataLength = size;
      case _qacf:
        try {
          final decoded =
              jsonDecode(utf8.decode(bytes.sublist(body, body + size)))
                  as Map<String, dynamic>;
          final length = decoded['sourceLength'] as int;
          fingerprint = ConformSourceFingerprint(
            sourceLength: length,
            // A conform written before the fingerprint became content-based
            // carries only `sourceModifiedMicros`, and there is no way to
            // derive a hash from a timestamp. The cast throws, which lands in
            // the catch below as "unknown" — and unknown already means stale,
            // so those conforms rebuild once and never again.
            sourceCrc32: decoded['sourceCrc32'] as int,
          );
          // The stat HINT is optional on purpose: absent it, the reuse check
          // falls through to reading the source, which is a slow answer
          // rather than a wrong one.
          final modified = decoded['sourceModifiedMicros'] as int?;
          sourceStat = modified == null
              ? null
              : ConformSourceStat(
                  sourceLength: length,
                  sourceModifiedMicros: modified,
                );
          speedNumerator = (decoded['speedNumerator'] as int?) ?? 1;
          speedDenominator = (decoded['speedDenominator'] as int?) ?? 1;
        } on Object {
          // An unreadable provenance chunk means "unknown", never a
          // failed open: the audio is still perfectly good.
          fingerprint = null;
          sourceStat = null;
        }
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }

  if (channels == null || sampleRate == null || bitsPerSample == null) {
    throw const ConformFormatException('missing fmt chunk');
  }
  if (format != _formatPcm && format != _formatExtensible) {
    throw ConformFormatException('unsupported WAV format tag $format');
  }
  if (bitsPerSample != 16) {
    throw ConformFormatException(
      'expected 16-bit PCM, found $bitsPerSample-bit — conforms are '
      'written 16-bit by encodeConformWav',
    );
  }
  if (channels <= 0) {
    throw const ConformFormatException('fmt chunk declares no channels');
  }
  if (dataStart == null || dataLength == null) {
    throw const ConformFormatException('missing data chunk');
  }

  final sampleCount = dataLength ~/ 2;
  final samples = Float32List(sampleCount);
  for (var index = 0; index < sampleCount; index += 1) {
    // 32768 — the industry convention, and what dr_wav uses (it multiplies
    // by the literal 0.000030517578125f). Matching it is not cosmetic:
    // every OTHER format arrives through dr_libs, so a conform read with
    // a different scale than an imported WAV would put the same audio at
    // two different levels depending on which path it took.
    //
    // It also makes a unity-gain clip round trip BIT-EXACTLY through the
    // whole chain: raw ÷ 32768 → mix → × 32768 → the same raw sample. The
    // 32767 convention loses that, being off by one LSB at full scale.
    samples[index] =
        view.getInt16(dataStart + index * 2, Endian.little) / 32768.0;
  }
  return ConformAudio(
    samples: samples,
    channels: channels,
    sampleRate: sampleRate,
    fingerprint: fingerprint,
    sourceStat: sourceStat,
    speedNumerator: speedNumerator,
    speedDenominator: speedDenominator,
  );
}

/// Whether [conform] was made from a source that still looks like [current]
/// — the check that decides between reusing a conform and rebuilding it.
///
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
