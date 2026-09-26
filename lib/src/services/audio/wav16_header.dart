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
///
/// [wav16HeaderLength] bytes long; [readWav16Header] reads one back.
Uint8List wav16HeaderBytes({
  required int dataBytes,
  required int sampleRate,
  required int channels,
}) {
  final header = ByteData(wav16HeaderLength);
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

/// How long [wav16HeaderBytes]'s header is — where the samples start.
const int wav16HeaderLength = 44;

/// A header [wav16HeaderBytes] wrote, read back — or null when [head] is
/// not one: another program's WAV, with chunks of its own, is the
/// decoders' to read, not this.
///
/// 🚨For a sound this app WROTE and reads back by streaming: the export's
/// mix, which the OS encoder feeds into the movie. 🪦It was read as a
/// conform from 08-30, when a conform stopped being a WAV — the reader
/// said null, and every movie the OS encoder made had no sound (09-25).
({int sampleRate, int channels, int dataBytes})? readWav16Header(
  List<int> head,
) {
  if (head.length < wav16HeaderLength) {
    return null;
  }
  final view = ByteData.sublistView(Uint8List.fromList(head));
  bool says(int offset, String text) =>
      String.fromCharCodes(head.sublist(offset, offset + 4)) == text;
  if (!says(0, 'RIFF') ||
      !says(8, 'WAVE') ||
      !says(12, 'fmt ') ||
      !says(36, 'data') ||
      view.getUint16(20, Endian.little) != 1 ||
      view.getUint16(34, Endian.little) != 16) {
    return null;
  }
  return (
    sampleRate: view.getUint32(24, Endian.little),
    channels: view.getUint16(22, Endian.little),
    dataBytes: view.getUint32(40, Endian.little),
  );
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
