/// 🚨★★★**MEDIA COMPRESSES IN BLOCKS, BECAUSE A WHOLE FRAME CANNOT SERVE
/// A WINDOW.**
///
/// Cels and `project.json` are compressed whole: they are read whole, so a
/// single zstd frame is exactly right. Media is not. `MediaArchiveBytes`
/// seeks to `dataOffset + position` inside the .anicel and reads a RANGE —
/// that is how a hundred-page conte is read a page at a time instead of
/// landing in memory, and it is the answer to 유저 2026-08-27: 「3기가
/// 영상파일도 볼거라서 결국 그게 그대로 메모리에 올라가면 문제되는데」.
///
/// ⛔A zstd frame has no random access. Compressing an entry whole would
/// buy 38% on audio and take the window away from every format, so this
/// compresses in fixed blocks and writes down where each one landed. A
/// read of n bytes decompresses only the blocks it touches.
///
/// **The measurement that chose [mediaBlockBytes]** — the same cels and
/// the user's own recordings, level 9, against compressing each file
/// whole:
///
/// | | 4MB blocks | 1MB | 256KB |
/// |---|---|---|---|
/// | a 17.5MB cel (very compressible) | **+2.97%** | +9.68% | +10.98% |
/// | a 0.4MB WAV | 0% | 0% | 0% |
///
/// Blocking is not free on large compressible data — zstd loses the
/// history it would have had across the boundary — so the block is as big
/// as a window can afford rather than as small as it can be.
///
/// 🚨**AND SOME MEDIA MUST NOT BE COMPRESSED AT ALL.** A PNG, a JPEG, an
/// MP4 or a PDF is already compressed: zstd returns ~1.00× on them and
/// every future read would pay a decompression for nothing. Those keep
/// their plain entry name and their bytes verbatim, so a window into them
/// stays the plain seek it is today.
library;

import 'dart:typed_data';

import '../../native/qa_cel_compressor.dart';
import 'anicel_payload_codec.dart';

/// Uncompressed bytes per block. See the doc above for the measurement.
const int mediaBlockBytes = 4 * 1024 * 1024;

/// What a framed entry's name ends with.
///
/// 🚨★★★**THE NAME SAYS IT, not a byte at the front** — the same answer
/// `project.json.z` already gives, and for a sharper reason here: an entry
/// the app stores verbatim must BE the file, byte for byte, so that
/// `MediaArchiveBytes` can hand out a plain byte range and a person with
/// an unzip tool gets a file that opens. A one-byte codec prefix on every
/// entry would cost both of those to describe the case that does not need
/// describing.
const String mediaFramedEntrySuffix = '.z';

/// Whether the entry called [entryName] holds a framed blob rather than
/// the file's own bytes.
bool mediaEntryIsFramed(String entryName) =>
    entryName.endsWith(mediaFramedEntrySuffix);

/// The smallest saving worth paying a decompression for, as a fraction of
/// the original.
///
/// ⚠️MY judgement, not a measurement (2026-08-30). What IS measured is the
/// shape of the two populations: the user's WAV recordings come back at
/// 0.62 of their size, and already-compressed formats at 0.99–1.00.
/// Nothing observed lands near this line, so it separates two clusters
/// rather than splitting one — which is why a crude threshold is safe
/// here. Move it only with a file that actually falls between them.
const double mediaCompressionWorthIt = 0.95;

/// What a framed entry says about itself, before its blocks.
///
/// Layout, little-endian:
///
/// ```
/// u32  blockBytes   uncompressed bytes per block
/// u64  totalLength  uncompressed length of the whole file
/// u32  blockCount
/// u32  ×blockCount  compressed length of each block, in order
/// ```
///
/// 🚨[blockCount] sits at a FIXED offset so a reader can learn the header's
/// own length from a [prefixLength] prefix and then read exactly the rest.
/// The point is that a reader never has to hold the entry to find its way
/// around it — which is the whole reason this format exists.
class MediaBlobHeader {
  const MediaBlobHeader({
    required this.blockBytes,
    required this.totalLength,
    required this.blockLengths,
  });

  /// Bytes to read before [headerLengthOf] can say how long the header is.
  static const int prefixLength = 16;

  final int blockBytes;
  final int totalLength;

  /// Compressed length of each block, in order.
  final List<int> blockLengths;

  int get blockCount => blockLengths.length;

  /// Byte length of the whole header, blocks excluded.
  int get length => prefixLength + 4 * blockCount;

  /// Where block [index]'s compressed bytes start, from the entry's first
  /// byte.
  int offsetOf(int index) {
    var at = length;
    for (var i = 0; i < index; i += 1) {
      at += blockLengths[i];
    }
    return at;
  }

  /// The header's own bytes.
  Uint8List toBytes() {
    final bytes = Uint8List(length);
    final view = ByteData.sublistView(bytes);
    view.setUint32(0, blockBytes, Endian.little);
    view.setUint64(4, totalLength, Endian.little);
    view.setUint32(12, blockCount, Endian.little);
    for (var i = 0; i < blockCount; i += 1) {
      view.setUint32(prefixLength + 4 * i, blockLengths[i], Endian.little);
    }
    return bytes;
  }

  /// How many bytes the header occupies, from a [prefixLength] prefix.
  static int headerLengthOf(Uint8List prefix) {
    if (prefix.length < prefixLength) {
      throw const FormatException('framed media prefix is short');
    }
    final count = ByteData.sublistView(prefix).getUint32(12, Endian.little);
    return prefixLength + 4 * count;
  }

  /// Parses a header from [bytes], which must hold at least [length] of
  /// them.
  static MediaBlobHeader parse(Uint8List bytes) {
    if (bytes.length < prefixLength) {
      throw const FormatException('framed media header is short');
    }
    final view = ByteData.sublistView(bytes);
    final blockBytes = view.getUint32(0, Endian.little);
    final totalLength = view.getUint64(4, Endian.little);
    final count = view.getUint32(12, Endian.little);
    if (blockBytes <= 0 || bytes.length < prefixLength + 4 * count) {
      throw const FormatException('framed media header is malformed');
    }
    return MediaBlobHeader(
      blockBytes: blockBytes,
      totalLength: totalLength,
      blockLengths: [
        for (var i = 0; i < count; i += 1)
          view.getUint32(prefixLength + 4 * i, Endian.little),
      ],
    );
  }

  /// The blocks a read of [size] bytes at [position] touches, as an
  /// inclusive index range — or null when the range is empty.
  ({int first, int last})? blocksFor(int position, int size) {
    if (size <= 0 || position >= totalLength) {
      return null;
    }
    final end = position + size > totalLength ? totalLength : position + size;
    return (first: position ~/ blockBytes, last: (end - 1) ~/ blockBytes);
  }
}

/// Compresses [bytes] for a media entry, or answers null when it is not
/// worth it — an already-compressed format, or a build with no zstd.
///
/// ⛔The deflate floor is deliberately NOT used here, unlike
/// [compressAnicelPayload]. A cel MUST be readable by any build because it
/// is the picture; a media entry has an alternative that costs nothing —
/// storing the file as it is — so a build without zstd simply stores, and
/// no .anicel ever needs a library to give its media back.
Uint8List? compressMediaBlob(Uint8List bytes) {
  final compressor = QaCelCompressor.instance;
  if (compressor == null || !compressor.isSupported || bytes.isEmpty) {
    return null;
  }
  final blocks = <Uint8List>[];
  var packed = 0;
  for (var at = 0; at < bytes.length; at += mediaBlockBytes) {
    final end = at + mediaBlockBytes > bytes.length
        ? bytes.length
        : at + mediaBlockBytes;
    final block = compressor.compress(
      Uint8List.sublistView(bytes, at, end),
      level: anicelZstdLevel,
    );
    if (block == null) {
      return null; // The engine gave up mid-file: store the original.
    }
    blocks.add(block);
    packed += block.length;
  }
  final header = MediaBlobHeader(
    blockBytes: mediaBlockBytes,
    totalLength: bytes.length,
    blockLengths: [for (final block in blocks) block.length],
  );
  final total = header.length + packed;
  // 🚨Judged on the WHOLE entry including its index, because that is what
  // the file pays. A saving the block index eats is not a saving.
  if (total >= bytes.length * mediaCompressionWorthIt) {
    return null;
  }
  final out = Uint8List(total);
  out.setAll(0, header.toBytes());
  var at = header.length;
  for (final block in blocks) {
    out.setAll(at, block);
    at += block.length;
  }
  return out;
}

/// The whole file back from a framed entry.
///
/// For a WINDOW, do not call this — read the header, ask
/// [MediaBlobHeader.blocksFor] which blocks the range touches, and
/// decompress only those. This is for the callers that genuinely want
/// every byte.
Uint8List decompressMediaBlob(Uint8List entry) {
  final header = MediaBlobHeader.parse(entry);
  final out = Uint8List(header.totalLength);
  var wrote = 0;
  var at = header.length;
  for (var i = 0; i < header.blockCount; i += 1) {
    final block = decompressMediaBlock(
      Uint8List.sublistView(entry, at, at + header.blockLengths[i]),
    );
    out.setAll(wrote, block);
    wrote += block.length;
    at += header.blockLengths[i];
  }
  if (wrote != header.totalLength) {
    throw const FormatException('framed media entry is short');
  }
  return out;
}

/// One block's bytes back.
///
/// Throws when this build cannot read zstd — the file is fine, this BUILD
/// cannot open it, and saying so beats a length mismatch further down.
Uint8List decompressMediaBlock(Uint8List block) {
  final compressor = QaCelCompressor.instance;
  final out = compressor == null || !compressor.isSupported
      ? null
      : compressor.decompress(block);
  if (out == null) {
    throw const FormatException(
      'This media was compressed with zstd and no engine is available to '
      'read it.',
    );
  }
  return out;
}
