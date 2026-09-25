import 'dart:typed_data';

/// A plain 44-byte 16-bit PCM WAV header.
///
/// 🚨★★★**THE ONE PLACE THIS APP WRITES A WAV.** The audio export builds a
/// real WAV because the file leaves the app and something else opens it; a
/// CONFORM does not, and stopped pretending to on 2026-08-30 (see
/// [ConformHeader]). Keeping the two apart is the point — the export's
/// format is a promise to other programs, and the conform's is a promise to
/// this one.
///
/// ⚠️Tests that need a foreign WAV — the native decoder's, and the cache
/// collector's「this is somebody else's file」fixtures — build one from
/// here. They used to reach for the conform encoder, which worked only
/// while a conform happened to BE a WAV, and would otherwise have been a
/// second hand-rolled header living in the test tree.
///
/// Sizes are exact: every caller knows its length before the first sample.
Uint8List wav16HeaderBytes({
  required int dataBytes,
  required int sampleRate,
  required int channels,
}) {
  final header = ByteData(44);
  void ascii(int offset, String text) {
    for (var index = 0; index < text.length; index += 1) {
      header.setUint8(offset + index, text.codeUnitAt(index));
    }
  }

  const bytesPerSample = 2;
  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  header.setUint16(32, channels * bytesPerSample, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);
  return header.buffer.asUint8List();
}

/// [pcm] — interleaved 16-bit samples — as a whole WAV file: the header
/// above, then the samples.
///
/// For a sound this app MADE and holds whole: a recorded take, the
/// count-in's beep, the piece a trimmed sound is carried as. The export
/// streams an hour, so it writes the header itself and the samples after.
///
/// 🪦A take and the beep were written by the CONFORM encoder, from when a
/// conform was a WAV. It stopped being one on 08-30 and nothing told them:
/// every take was a file no decoder reads — no waveform, no sound (유저
/// 09-25, card `F-178` ⑥).
Uint8List wav16Bytes(
  Int16List pcm, {
  required int sampleRate,
  required int channels,
}) {
  final data = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
  return (BytesBuilder(copy: false)
        ..add(
          wav16HeaderBytes(
            dataBytes: data.length,
            sampleRate: sampleRate,
            channels: channels,
          ),
        )
        ..add(data))
      .takeBytes();
}
