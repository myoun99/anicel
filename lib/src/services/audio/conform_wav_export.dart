import 'dart:io';
import 'dart:typed_data';

import '../media/media_byte_source.dart';
import '../persistence/media_blob_codec.dart';
import 'conform_pcm_codec.dart';
import 'wav16_header.dart';

/// Uncompressed bytes moved per copy. Big enough that the syscalls are not
/// the cost, small enough that an hour of dialogue never lands in memory.
const int _copyBytes = 512 * 1024;

/// Writes the conform at [conformPath] to [destinationPath] as a plain
/// 16-bit WAV — the file any audio tool opens.
///
/// 🚨★★★**THIS IS WHAT COMPRESSION TOOK AWAY, HANDED BACK ON DEMAND.** A
/// conform used to BE a WAV, so「open it in anything」was a property of the
/// cache file. 유저 2026-08-30 gave that up knowingly and named the
/// replacement in the same breath: 「다른 앱으로 들을 필요성을 못느끼겟고
/// 그럴거면 **압축해제시켜서 내보내기 기능 만들면 되는거아닌가?**」.
///
/// ⚡**No sample is converted.** A conform's payload is already interleaved
/// int16 at the project rate — exactly what a 16-bit WAV holds — so this is
/// a header swap and a copy. Going through float32 and back would be slower
/// and would round twice for nothing.
///
/// 🚨**And it STREAMS.** An hour of stereo dialogue at 48kHz is 691MB of
/// PCM; building the WAV in memory would have re-created, in a brand new
/// place, the exact allocation the carry and staging rounds spent
/// themselves removing. One 512KB buffer crosses, however long the take.
///
/// ⛔The header comes from [wav16HeaderBytes] rather than being written
/// here. That function exists because「the app writes a WAV」has to be one
/// place, and an exporter that could disagree with it is how two spellings
/// of a format begin.
///
/// Answers false when [conformPath] does not hold a conform this build can
/// read — the caller says so on screen rather than leaving a broken file.
Future<bool> writeConformAsWav({
  required String conformPath,
  required String destinationPath,
}) async {
  // ⛔Framed-first, through the ONE function that knows a file this app
  // wrote may wear either name. Deciding it here — or asking the caller to
  // hand over the right spelling — is how the conform reader and this one
  // would come to disagree about the same file.
  final resolved = mediaFramedOrPlainPaths(
    conformPath,
  ).where((candidate) => File(candidate).existsSync()).firstOrNull;
  if (resolved == null) {
    return false;
  }
  final source = mediaAppFileSource(resolved);
  final head = Uint8List(ConformHeader.length);
  final ConformHeader header;
  try {
    if (source.readIntoSync(head, 0, head.length) < head.length) {
      return false;
    }
    header = ConformHeader.parse(head);
  } on Object {
    return false;
  }
  final out = File(destinationPath).openSync(mode: FileMode.write);
  try {
    out.writeFromSync(
      wav16HeaderBytes(
        dataBytes: header.dataBytes,
        sampleRate: header.sampleRate,
        channels: header.channels,
      ),
    );
    final buffer = Uint8List(_copyBytes);
    var at = 0;
    while (at < header.dataBytes) {
      final want = header.dataBytes - at < _copyBytes
          ? header.dataBytes - at
          : _copyBytes;
      final got = source.readIntoSync(buffer, ConformHeader.length + at, want);
      if (got <= 0) {
        // The conform is shorter than its own header claims. What is
        // written so far is honest audio; the caller is told it failed so
        // nothing presents a truncated file as a finished export.
        return false;
      }
      out.writeFromSync(buffer, 0, got);
      at += got;
    }
  } finally {
    out.closeSync();
  }
  return true;
}
