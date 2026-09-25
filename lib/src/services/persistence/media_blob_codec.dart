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
/// ⇒ [writeMediaBlob] tries and keeps the result only when it actually
/// got smaller ([mediaCompressionWorthIt]). A rule about file EXTENSIONS
/// would have thrown away 40% of a conte and 21% of a photo.
///
/// 🚨And it makes the framing matter MORE, not less: the formats that
/// shrink are the big ones a window exists for. A 3GB movie at 6.7% is
/// 200MB, and it is exactly the file that must not be decompressed whole
/// to read a second of it.
library;

import 'dart:io';
import 'dart:math' show Random;
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

/// The name [basePath] takes when it is [framed] and when it is not.
String mediaPathFramed(String basePath, {required bool framed}) =>
    framed ? '$basePath$mediaFramedEntrySuffix' : basePath;

/// Both names [basePath] can be on disk under, **framed first**.
///
/// 🚨★★★**THE ORDER IS THE LAW, AND IT LIVES HERE ONCE.** Whether a file
/// this app wrote got compressed is decided per FILE, by measurement
/// ([mediaCompressionWorthIt]) — so every store that writes one has to be
/// able to find it either way, and every one of them was spelling the same
/// two-line loop. Framed comes first because that is what a build with an
/// engine writes; a plain file under the same base name is either an older
/// write or a file that would not shrink.
///
/// ⚠️Callers that WRITE must remove the other spelling. A rebuild that
/// flips framedness would otherwise leave both, and the stale one is the
/// one this order finds.
List<String> mediaFramedOrPlainPaths(String basePath) => [
  mediaPathFramed(basePath, framed: true),
  basePath,
];

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
///
/// ⛔**THIS SIDE ONLY WRITES IT.** The one reader is the engine's
/// (`qa_media_span.c`, reached from Dart as `QaMediaSpan`), which every
/// decoder and every Dart read of a framed medium goes through. 🪦A Dart
/// parser, block map and whole-entry decoder lived here too, and went when
/// the engine's became the only one (2026-09-24): a format with two readers
/// is two chances for them to disagree about a boundary.
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
}

/// Writes the entry for [length] bytes at [basePath] — framed when framing
/// actually pays — and answers where it landed.
///
/// 🚨★★★**IT NEVER HOLDS THE ASSET, AND IT IS THE ONLY THING THAT WRITES
/// THIS FORMAT.**
///
/// The first version took the whole file as one `Uint8List` and built every
/// compressed block beside it before judging the total — on a 4GB movie
/// that is the asset twice over, resident at once, on the UI isolate, to
/// settle a question the first few blocks already answer. 유저 2026-08-27
/// named the shape this must not have — 「3기가 영상파일도 볼거라서 결국
/// 그게 그대로 메모리에 올라가면 문제되는데」 — about READS, and the write
/// had it anyway. This holds one block in and one block out, whatever the
/// file weighs.
///
/// ⛔That version is DELETED rather than kept for the callers that could
/// afford it. Two writers of one format drift, and this one is read back
/// byte by byte — see `test/helpers/framed_media_fixture.dart`, which
/// builds its fixtures by calling this and reading the file, so the tests
/// measure the layout that ships.
///
/// ⚡**It also stops once framing cannot win.** The index length is known
/// before the first read ([MediaBlobHeader.prefixLength] plus four bytes a
/// block, and the block count follows from [length]), so the weight a
/// framed entry has to come in under is known too, and the loop abandons
/// framing the moment the blocks behind it have spent that allowance.
///
/// ⚠️**Do not read that as「a PNG costs a handful of blocks」— I wrote that
/// first and then measured it.** Noise compresses to about 1.00×, so the
/// allowance ([mediaCompressionWorthIt], 0.95) is not spent until most of
/// the file has gone through: **95.0% of a noise file was compressed
/// before the exit fired** (20 blocks of 64KB, measured). The exit saves
/// the last few percent and the writes that would have been thrown away.
/// It is NOT a sampling heuristic and must not become one — the top of
/// this file records why the decision asks each FILE rather than believing
/// something about it.
///
/// ⚠️So an entry that ends up stored is READ TWICE — once trying, once
/// copying. That is disk, and the alternative it replaced was holding the
/// asset and every compressed block of it in memory at the same time.
///
/// [readInto] is `MediaByteSource.readIntoSync`'s shape — the one the
/// archive writer already streams through — so a caller holding an open
/// handle passes it straight in rather than reopening once a block.
({String path, bool framed}) writeMediaBlob({
  required String basePath,
  required int length,
  required int Function(Uint8List buffer, int position, int size) readInto,
  int blockBytes = mediaBlockBytes,
}) {
  // ⛔Written to a neighbour and renamed, and here that is not only about
  // torn files: framedness is not known until the last block, so the bytes
  // have to be somewhere nameless while it is still being decided.
  //
  // 🚨The neighbour is THIS write's alone. Two open projects conforming one
  // source (I-7, 유저 2026-09-26) build the same conform at the same time,
  // from isolates whose statics do not see each other — a shared `.part`
  // let each truncate the other's half-written bytes.
  final part = File(
    '$basePath.${DateTime.now().microsecondsSinceEpoch}-'
    '${_partNames.nextInt(1 << 32)}.part',
  );
  part.parent.createSync(recursive: true);
  final out = part.openSync(mode: FileMode.write);
  bool framed;
  try {
    framed = _writeFramedBlocks(out, length, readInto, blockBytes);
    if (!framed) {
      out.setPositionSync(0);
      out.truncateSync(0);
      _writeVerbatim(out, length, readInto, blockBytes);
    }
  } finally {
    out.closeSync();
  }
  final path = mediaPathFramed(basePath, framed: framed);
  // Windows refuses a rename onto an existing name, and a rebuild — a
  // conform whose settings changed, a re-staged asset — lands on one.
  final existing = File(path);
  if (existing.existsSync()) {
    existing.deleteSync();
  }
  try {
    part.renameSync(path);
  } on FileSystemException {
    // The other writer of the same blob renamed between the delete and
    // this rename: what stands there is this file's twin, whole.
    if (!File(path).existsSync()) {
      rethrow;
    }
    part.deleteSync();
  }
  return (path: path, framed: framed);
}

final Random _partNames = Random();

/// [writeMediaBlob]'s [readInto] over bytes that are already in memory.
///
/// The conform pipeline is why this exists: its PCM was just computed, so
/// it has no file to stream from — but the compressed blocks are still
/// worth never holding, and the writer only asks for a window at a time.
int Function(Uint8List, int, int) mediaBytesReader(Uint8List bytes) =>
    (buffer, position, size) {
      final end = position + size > bytes.length
          ? bytes.length
          : position + size;
      final got = end - position;
      if (got <= 0) {
        return 0;
      }
      buffer.setRange(0, got, bytes, position);
      return got;
    };

/// Fills [buffer] from [at], looping because a source promises only「up
/// to」[want] bytes. Answers how many landed — short only at the end.
int _fill(
  Uint8List buffer,
  int at,
  int want,
  int Function(Uint8List, int, int) readInto,
) {
  var got = 0;
  while (got < want) {
    final read = readInto(
      Uint8List.sublistView(buffer, got),
      at + got,
      want - got,
    );
    if (read <= 0) {
      break;
    }
    got += read;
  }
  return got;
}

/// The framed road: the index's room is reserved, the blocks are appended,
/// and the index is written into that room last — the only order that does
/// not need every block's length before the first one is compressed.
///
/// False means「do not frame this」, and the caller writes the same file
/// verbatim over the top. Every exit takes it: no engine, a short source, a
/// block the engine refused, or an allowance already spent.
bool _writeFramedBlocks(
  RandomAccessFile out,
  int length,
  int Function(Uint8List, int, int) readInto,
  int blockBytes,
) {
  final compressor = QaCelCompressor.instance;
  if (compressor == null || !compressor.isSupported || length <= 0) {
    return false;
  }
  final blockCount = (length + blockBytes - 1) ~/ blockBytes;
  final headerLength = MediaBlobHeader.prefixLength + 4 * blockCount;
  // 🚨The INDEX is spent before a byte is compressed, so it comes out of
  // the allowance first — judged on the WHOLE entry, the way the in-memory
  // codec judges it, because that is what the file pays.
  var allowance = (length * mediaCompressionWorthIt).floor() - headerLength;
  if (allowance <= 0) {
    return false;
  }
  out.setPositionSync(headerLength);
  final buffer = Uint8List(blockBytes);
  final blockLengths = <int>[];
  var at = 0;
  while (at < length) {
    final want = length - at < blockBytes ? length - at : blockBytes;
    if (_fill(buffer, at, want, readInto) != want) {
      return false; // The source ran short — verbatim says what is there.
    }
    final block = compressor.compress(
      Uint8List.sublistView(buffer, 0, want),
      level: anicelZstdLevel,
    );
    if (block == null) {
      return false;
    }
    allowance -= block.length;
    if (allowance < 0) {
      return false;
    }
    out.writeFromSync(block);
    blockLengths.add(block.length);
    at += want;
  }
  out.setPositionSync(0);
  out.writeFromSync(
    MediaBlobHeader(
      blockBytes: blockBytes,
      totalLength: length,
      blockLengths: blockLengths,
    ).toBytes(),
  );
  return true;
}

/// The verbatim road, in the same block-sized bites. What this writes IS
/// the asset, byte for byte — that is what lets a stored entry be handed
/// out later as a plain byte range.
///
/// 🪦`copyMediaBytesToFile` was this road for bytes going OUT — a carried
/// conform restored without holding it whole. The restore went on 09-07
/// (a conform is read where it lies) and it stayed with no caller but its
/// tests; the one copy out of the project file now is the room keeping
/// what a save leaves behind, which streams through
/// `ScratchFile.writeStreamed` (09-25).
void _writeVerbatim(
  RandomAccessFile out,
  int length,
  int Function(Uint8List, int, int) readInto,
  int chunkBytes,
) {
  final buffer = Uint8List(chunkBytes);
  var at = 0;
  while (at < length) {
    final want = length - at < chunkBytes ? length - at : chunkBytes;
    final got = _fill(buffer, at, want, readInto);
    if (got <= 0) {
      break;
    }
    out.writeFromSync(buffer, 0, got);
    at += got;
  }
}
