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
/// **What blocking COSTS, measured** (유저 asked: 「4mb마다 압축하는방식,
/// 압축률 줄어드나 혹시?」). Against compressing each file whole, level 9:
///
/// | | 4MB blocks |
/// |---|---|
/// | MP4 6.3MB ×2 | **+0.00%** |
/// | PDF 3.1MB | **+0.00%** |
/// | PDF 4.2MB | +0.02% |
/// | PDF 6.4MB | +0.10% |
/// | PNG 38MB | +0.00% |
/// | **a 17.5MB CEL** | **+2.97%** (1MB: +9.68%, 256KB: +10.98%) |
///
/// 🚨**The cel is the outlier, and it is not media.** A tile raster repeats
/// across the whole file, so zstd loses real history at a block boundary.
/// Media compresses LOCALLY — a PDF's streams, a JPEG's scans, a movie's
/// frames — so a boundary costs it essentially nothing.
///
/// 🚨★★★**AND THE BLOCK SIZE IS DECIDED BY THE READ, NOT BY THE RATIO.**
///
/// The table above measures ONE axis — how much a boundary costs the
/// compressed size — and 4MB won it, so 4MB is what this constant held.
/// That was measuring the wrong thing. A block exists to serve a WINDOW,
/// and what a window pays is DECOMPRESSION. Measured on a real 3.84MB
/// conform (the user's own MP3, level 9, Release engine, best of two
/// passes, buffers allocated outside the loop):
///
/// | block | decompress | size cost vs whole |
/// |---|---|---|
/// | 256KB | 585 · 548 MB/s | +1.33% |
/// | **512KB** | **608 · 610 MB/s** | **+1.07%** |
/// | 1MB | 502 · 667 MB/s | +0.66% |
/// | 2MB | 206 · 194 MB/s | ~+0.3% |
/// | 4MB | **91 · 118 MB/s** | +0.00% |
///
/// ⇒ **A cliff between 1MB and 2MB, and 4MB sat on the wrong side of it.**
/// A 100KB read cost 40ms at 4MB and costs 1.7ms at 512KB — 23×, from the
/// speed and from decompressing an eighth as much to serve the same bytes.
///
/// 🔑**The cause is CACHE, which is why the number is 512KB and not 1MB.**
/// Level 9 matches against a 2MB window; once the block is big enough that
/// the window stops living in cache, every match is a memory round trip.
/// A machine with LESS cache meets that cliff SOONER — and the devices
/// this app promises not to lag on are exactly the ones with less
/// ([[old-device-support-policy]]). 512KB and 1MB decompress the same
/// within noise, so the tie goes to the one with room underneath it.
///
/// ⛔**Parallel block decompression is NOT the answer to this** and was
/// considered: the bottleneck this measures is memory bandwidth, so cores
/// pulling at once contend for the same cache instead of scaling.
///
/// ⚠️The size is written in every entry's header, so entries already
/// written at 4MB keep reading — [MediaBlobHeader.blockBytes] is the
/// reader's authority, never this constant.
///
/// 유저 2026-08-30, told the measurement: 「4mb 아니어도 되고 1퍼센트
/// 용량늘어나는거 전혀 문업없으니까 알아서 판단한 크기로 통일해줘」.
///
/// 🚨**AND THE FORMAT DOES NOT DECIDE — THE MEASUREMENT DOES.**
///
/// This paragraph used to say「a PNG, a JPEG, an MP4 or a PDF is already
/// compressed, zstd returns ~1.00× on them」. 유저 2026-08-30 doubted it —
/// 「전에 근데 pdf나 mp4도 압축하면 줄어든다 하지않았나」 — and they were
/// right. What I had written as measured was a GUESS about file formats.
/// Measured, on real files, at level 9:
///
/// | | saved |
/// |---|---|
/// | PDF ×6 | 3.0 · 5.3 · 17.2 · 23.4 · 36.9 · **40.0%** |
/// | WAV ×3 (the user's own recordings) | **38%** |
/// | JPEG ×2 | 14.6 · **21.5%** |
/// | MP4 ×2 | **6.7%** |
/// | PNG ×6 | **0.0%** |
///
/// Only PNG is genuinely incompressible. A PDF wraps compressed streams in
/// an uncompressed object structure, a JPEG's entropy coding leaves plenty
/// on the table, and even H.264 gives a few percent.
///
/// ⇒ [compressMediaBlob] tries and keeps the result only when it actually
/// got smaller ([mediaCompressionWorthIt]). A rule about file EXTENSIONS
/// would have thrown away 40% of a conte and 21% of a photo.
///
/// 🚨And it makes the framing matter MORE, not less: the formats that
/// shrink are the big ones a window exists for. A 3GB movie at 6.7% is
/// 200MB, and it is exactly the file that must not be decompressed whole
/// to read a second of it.
library;

import 'dart:typed_data';

import '../../native/qa_cel_compressor.dart';
import 'anicel_payload_codec.dart';

/// Uncompressed bytes per block, for entries written from now on.
///
/// ⛔**A READER MUST NOT USE THIS.** Ask the entry — [MediaBlobHeader]
/// carries the size it was written at, and the value here has changed
/// once already. See the doc above for the measurement that chose it.
const int mediaBlockBytes = 512 * 1024;

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
/// ⚠️MY judgement, not a measurement — but the measurements around it are
/// real (see the table at the top of this file). Observed ratios spread
/// from 0.60 to 1.00 with no gap, so this is NOT a line between two
/// clusters; it is the point past which a decompression on every read
/// stops paying for itself.
///
/// 🚨At 0.95 a PDF that saved 5.3% is still taken and a PNG that saved
/// nothing is not. If that turns out to be the wrong place, the thing to
/// move is this number — the decision itself is right, because it asks
/// each FILE rather than believing something about its extension.
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
///
/// [blockBytes] is the size THIS entry is written at, and it is recorded in
/// the entry's own header. It is a parameter rather than a constant read
/// here because the constant has moved once already and will read back
/// entries written at the old size forever — a reader that assumed it
/// would serve the wrong bytes, so the format is built so that assuming it
/// is not even possible.
Uint8List? compressMediaBlob(
  Uint8List bytes, {
  int blockBytes = mediaBlockBytes,
}) {
  final compressor = QaCelCompressor.instance;
  if (compressor == null || !compressor.isSupported || bytes.isEmpty) {
    return null;
  }
  final blocks = <Uint8List>[];
  var packed = 0;
  for (var at = 0; at < bytes.length; at += blockBytes) {
    final end = at + blockBytes > bytes.length ? bytes.length : at + blockBytes;
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
    blockBytes: blockBytes,
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
