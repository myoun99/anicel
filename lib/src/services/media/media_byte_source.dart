import 'dart:io';
import 'dart:typed_data';

import '../persistence/anicel_incremental_writer.dart' show AnicelZipEntry;
import '../persistence/media_blob_codec.dart';

/// Where a media file's bytes actually are.
///
/// One named answer for a question that had four call sites and four
/// answers, all of them `File(path).readAsBytes()`. That was correct while
/// every piece of media was a file on disk. Once audio, images and PDFs
/// live inside the `.anicel` itself, "the bytes for this asset" stops being
/// a path and becomes a range in an archive — and the callers should not
/// each learn that.
///
/// 🔑 **Plain data, deliberately, and not a callback.** Audio conforming
/// runs inside `Isolate.run`, which can carry values across but not a
/// closure over the session. So the request has to arrive holding the way
/// to read itself. That constraint is also what makes the archive variant
/// the same shape as `AnicelCelFileRef` — path, offset, length — which is
/// what lets compaction stream media through without re-encoding it.
sealed class MediaByteSource {
  const MediaByteSource();

  /// The bytes, or a throw. Sync because the two callers that matter are
  /// already sync inside an isolate; the async wrapper is [read].
  Uint8List readSync();

  Future<Uint8List> read() async => readSync();

  /// How many bytes there are, without reading them.
  int lengthSync();

  /// Fills [buffer] with up to [size] bytes starting at [position], and
  /// answers how many landed — the shape `PdfDocument.openCustom` asks for.
  ///
  /// 🚨 This is why "give me the bytes" was not enough. A PDF opened by
  /// PATH is read page by page by PDFium; handing it a `Uint8List` instead
  /// pulls the whole document into memory (and hashes it, to name it), and
  /// a hundred-page conte is exactly the case the viewer is written to
  /// avoid — on the devices where a big allocation gets the app killed.
  /// So a source has to be able to serve a WINDOW, not just a whole file,
  /// and the archive variant will answer this straight out of the entry's
  /// byte range.
  int readIntoSync(Uint8List buffer, int position, int size);

  /// Whether the source is there at all.
  ///
  /// 🚨 Separate from [statSync] on purpose, and it did not start that way.
  /// While every source was a file, "no stat" and "not there" were the same
  /// sentence. An archive entry breaks that: it plainly exists and has no
  /// stat to give. Leaving them fused would have had the conform pipeline
  /// report every piece of audio inside the project as a MISSING SOURCE.
  bool existsSync();

  /// The cheap facts, or null when this kind of source has none to offer.
  ///
  /// The conform pipeline is the reason this exists. Every other consumer
  /// asks for bytes; that one asks whether it can avoid reading them, and
  /// answers with size-and-mtime first because a full read of every
  /// original on every open is what it used to cost.
  ///
  /// Null means "no hint", NOT "missing" — ask [existsSync] for that. A
  /// source with no hint is not a source in trouble; an archive entry
  /// skips straight to the content answer, which it happens to have for
  /// free.
  MediaSourceStamp? statSync();

  /// A content hash already known without reading anything, or null.
  ///
  /// Always null for a file — nothing on a filesystem knows its own
  /// checksum. An archive entry does: ZIP records a CRC-32 per entry in
  /// the header it has to write anyway, so the expensive half of the
  /// identity question comes back free once media moves inside.
  int? get knownCrc32 => null;

  /// Whether the bytes this source hands out are a framed blob rather than
  /// the file itself.
  ///
  /// 🚨The ENTRY NAME must then carry [mediaFramedEntrySuffix] — see
  /// [MediaBlobHeader]. It lives on the source because the source is the
  /// only thing that knows: a save asks each one what it is handing over
  /// and names the entry accordingly, rather than deciding twice.
  bool get storedIsFramed => false;

  /// Where these bytes live as a plain span of a file, or null when they
  /// are not one.
  ///
  /// 🚨★★★**THE ANSWER TO 「decode this without holding it」.** The native
  /// decoders take a path plus an offset and a length, so anything that can
  /// name itself this way never has to become a `Uint8List` first — which is
  /// the difference between a movie's soundtrack being conformable and a
  /// three-gigabyte allocation.
  ///
  /// ⛔Null is an ANSWER, not a gap: a framed entry is stored in compressed
  /// blocks, so the bytes at that span are not the container and reading
  /// them as one would decode noise. Callers fall back to [readSync], which
  /// is correct there and only there.
  ///
  /// ⚠️It lives on the source for the same reason [storedIsFramed] does —
  /// the source is the only thing that knows. Every caller that rebuilt this
  /// triple by hand was one archive-layout change from being wrong.
  ({String path, int offset, int length})? get range => null;
}

/// Cheap facts about a source, from `stat` alone.
class MediaSourceStamp {
  const MediaSourceStamp({
    required this.lengthBytes,
    required this.modifiedMicros,
  });

  final int lengthBytes;
  final int modifiedMicros;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaSourceStamp &&
          other.lengthBytes == lengthBytes &&
          other.modifiedMicros == modifiedMicros;

  @override
  int get hashCode => Object.hash(lengthBytes, modifiedMicros);
}

/// The whole of [path] as a range, or null when there is no file there.
///
/// 🚨★★★**[MediaByteSource.range] MUST NOT THROW.** It is asked as a
/// QUESTION — 「can you be decoded in place?」 — and every caller treats null
/// as 「no」. A missing original is the ordinary case at exactly the call
/// sites that ask: the viewer asks precisely because the import original is
/// gone. Letting `lengthSync` throw out of a getter turned that into an
/// exception on a path whose whole job is to answer 「not this way」.
///
/// ⚠️A try rather than an `existsSync` in front: that is one stat instead of
/// two, and it is also the only version without a race between the two.
({String path, int offset, int length})? _wholeFileRange(String path) {
  try {
    return (path: path, offset: 0, length: File(path).lengthSync());
  } on Object {
    return null;
  }
}

/// A file on disk — every source today, and still the answer for the media
/// that stays outside once the rest moves in (video is reference-only by
/// kind, and the user may keep anything else linked too).
class MediaFileBytes extends MediaByteSource {
  const MediaFileBytes(this.path);

  final String path;

  @override
  Uint8List readSync() => File(path).readAsBytesSync();

  @override
  int lengthSync() => File(path).lengthSync();

  /// A whole file IS a range — offset 0, its own length. ⛔Saying null here
  /// because 「it is not inside anything」 would make every caller carry a
  /// second path for the ordinary case.
  @override
  ({String path, int offset, int length})? get range => _wholeFileRange(path);

  @override
  int readIntoSync(Uint8List buffer, int position, int size) {
    final handle = File(path).openSync();
    try {
      handle.setPositionSync(position);
      return handle.readIntoSync(buffer, 0, size);
    } finally {
      handle.closeSync();
    }
  }

  /// Asks the PATH rather than through `File`: `File(dir).existsSync()`
  /// answers false for a directory, which would report "nothing here" for a
  /// path that plainly has something at it — and the difference between
  /// "gone" and "there but unreadable right now" is what keeps a cloud file
  /// still downloading from spending the conform store's retry budget.
  @override
  bool existsSync() {
    try {
      return FileStat.statSync(path).type != FileSystemEntityType.notFound;
    } on Object {
      return false;
    }
  }

  @override
  MediaSourceStamp? statSync() {
    try {
      final stat = FileStat.statSync(path);
      if (stat.type == FileSystemEntityType.notFound) {
        return null;
      }
      return MediaSourceStamp(
        lengthBytes: stat.size,
        modifiedMicros: stat.modified.microsecondsSinceEpoch,
      );
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MediaFileBytes && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'MediaFileBytes($path)';
}

/// A byte range inside a `.anicel` — media that travels with the project.
///
/// The same shape as `AnicelCelFileRef`, and for the same reason: entries
/// are STORE'd, so the range IS the payload and a save can stream it
/// through to the next file without re-encoding a thing.
///
/// ⚠️ **Not held across a save.** Offsets belong to one layout, and a
/// compaction rewrites the file — a source kept from before would read a
/// window of whatever now occupies those bytes, which is a project that
/// opens fine and plays the wrong sound. These are made from the archive's
/// current layout at the moment of use, so there is nothing to go stale.
class MediaArchiveBytes extends MediaByteSource {
  const MediaArchiveBytes({
    required this.archivePath,
    required this.dataOffset,
    required this.length,
    this.entryCrc32,
    this.framed = false,
  });

  /// The source for one archive ENTRY — the one place that turns a parsed
  /// zip entry into a byte source.
  ///
  /// The entry carries its own name, so `framed` is derived where the name
  /// lives instead of at each call site: four of them spelled this out, and
  /// a fifth would have been one more chance for the flag to be read from
  /// somewhere other than the name.
  factory MediaArchiveBytes.ofEntry({
    required String archivePath,
    required AnicelZipEntry entry,
  }) => MediaArchiveBytes(
    archivePath: archivePath,
    dataOffset: entry.dataOffset,
    length: entry.length,
    entryCrc32: entry.crc32,
    framed: mediaEntryIsFramed(entry.name),
  );

  final String archivePath;

  /// Offset of the entry's raw bytes in [archivePath].
  final int dataOffset;
  final int length;

  /// Whether this entry's bytes are a framed blob — set from its NAME by
  /// whoever built the source, because the name is what says so.
  final bool framed;

  /// The CRC-32 ZIP already wrote in the entry header.
  final int? entryCrc32;

  @override
  Uint8List readSync() {
    final buffer = Uint8List(length);
    final read = readIntoSync(buffer, 0, length);
    return read == length ? buffer : Uint8List.sublistView(buffer, 0, read);
  }

  @override
  int lengthSync() => length;

  /// Existence is the ENTRY's, not the file's: a source is only built from
  /// a layout that named it, so the question is whether the archive is
  /// still there to read.
  @override
  bool existsSync() => File(archivePath).existsSync();

  /// No stat, and that is not a problem — see [MediaByteSource.statSync].
  /// The expensive half of the identity question comes back free instead.
  @override
  MediaSourceStamp? statSync() => null;

  @override
  int? get knownCrc32 => entryCrc32;

  @override
  bool get storedIsFramed => framed;

  /// ⛔Null when [framed] — those bytes are compressed blocks, not the
  /// container. Otherwise this is the case the whole idea exists for: a
  /// movie carried inside the project file, decodable in place.
  @override
  ({String path, int offset, int length})? get range =>
      framed ? null : (path: archivePath, offset: dataOffset, length: length);

  /// Clamped to the entry, so a caller asking past the end of its media
  /// gets a short read rather than the bytes of whatever follows it in the
  /// archive.
  @override
  int readIntoSync(Uint8List buffer, int position, int size) {
    if (position < 0 || position >= length || size <= 0) {
      return 0;
    }
    final available = length - position;
    final wanted = size < available ? size : available;
    final handle = File(archivePath).openSync();
    try {
      handle.setPositionSync(dataOffset + position);
      return handle.readIntoSync(buffer, 0, wanted);
    } finally {
      handle.closeSync();
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaArchiveBytes &&
          other.archivePath == archivePath &&
          other.dataOffset == dataOffset &&
          other.length == length &&
          other.entryCrc32 == entryCrc32;

  @override
  int get hashCode => Object.hash(archivePath, dataOffset, length, entryCrc32);

  @override
  String toString() => 'MediaArchiveBytes($archivePath@$dataOffset+$length)';
}

/// A framed media entry, seen as the file it holds.
///
/// 🚨★★★**THIS IS WHY MEDIA COMPRESSES IN BLOCKS AND NOT AS ONE FRAME.**
/// [stored] hands out the entry's compressed bytes — a range in the
/// .anicel, or a staged file in the app container. This turns a request
/// for「bytes 300..400 of the audio」into a read of only the blocks that
/// range lands in, so a hundred-page conte and a three-gigabyte movie are
/// still read a piece at a time. See [MediaBlobHeader].
///
/// ⚠️[knownCrc32] is deliberately null. ZIP's CRC describes the COMPRESSED
/// bytes; this class hands back the uncompressed ones, so answering with
/// it would hand the conform pipeline a checksum of something it never
/// sees — and that pipeline treats a mismatch as a torn read and retries.
class MediaFramedBytes extends MediaByteSource {
  /// Over an entry that some other source hands out.
  MediaFramedBytes(MediaByteSource stored)
    : this.reading(
        readStored: stored.readIntoSync,
        storedExists: stored.existsSync,
        label: '$stored',
      );

  /// 🚨Takes a READ FUNCTION rather than a source, because that is all it
  /// needs and [MediaByteSource] is sealed — a test cannot subclass one to
  /// count what was asked for, and counting is the only way to tell this
  /// class from one that quietly pulls the whole entry.
  MediaFramedBytes.reading({
    required this.readStored,
    required this.storedExists,
    this.label = 'framed',
  });

  /// Fills a buffer from the STORED bytes — header first, then blocks.
  final int Function(Uint8List buffer, int position, int size) readStored;
  final bool Function() storedExists;
  final String label;

  MediaBlobHeader? _header;

  /// Read once and kept: it is the index, and re-reading it per window
  /// would put a seek in front of every read this class exists to make
  /// cheap.
  MediaBlobHeader get header {
    final known = _header;
    if (known != null) {
      return known;
    }
    final prefix = Uint8List(MediaBlobHeader.prefixLength);
    if (readStored(prefix, 0, prefix.length) < prefix.length) {
      throw const FormatException('framed media entry is short');
    }
    final length = MediaBlobHeader.headerLengthOf(prefix);
    final bytes = Uint8List(length);
    if (readStored(bytes, 0, length) < length) {
      throw const FormatException('framed media index is short');
    }
    return _header = MediaBlobHeader.parse(bytes);
  }

  @override
  int lengthSync() => header.totalLength;

  @override
  Uint8List readSync() {
    final out = Uint8List(header.totalLength);
    final read = readIntoSync(out, 0, out.length);
    return read == out.length ? out : Uint8List.sublistView(out, 0, read);
  }

  @override
  int readIntoSync(Uint8List buffer, int position, int size) {
    final index = header;
    final range = index.blocksFor(position, size);
    if (range == null) {
      return 0;
    }
    var wrote = 0;
    for (var i = range.first; i <= range.last; i += 1) {
      final compressed = Uint8List(index.blockLengths[i]);
      final got = readStored(compressed, index.offsetOf(i), compressed.length);
      if (got < compressed.length) {
        throw const FormatException('framed media block is short');
      }
      final block = decompressMediaBlock(compressed);
      // Where this block sits in the FILE, intersected with what was
      // asked for. The first block usually starts before `position` and
      // the last usually runs past the end of the request.
      final blockStart = i * index.blockBytes;
      final from = position > blockStart ? position - blockStart : 0;
      final wanted = size - wrote;
      final available = block.length - from;
      final take = wanted < available ? wanted : available;
      if (take <= 0) {
        break;
      }
      buffer.setRange(wrote, wrote + take, block, from);
      wrote += take;
    }
    return wrote;
  }

  @override
  bool existsSync() => storedExists();

  @override
  MediaSourceStamp? statSync() => null;

  @override
  String toString() => 'MediaFramedBytes($label)';
}

/// A file the app staged in its own container when the media was 품기'd.
///
/// 🚨★★★**THE ONLY COPY THE PROJECT CONTROLS UNTIL THE FIRST SAVE.** An
/// import used to leave the bytes where they were and read them again at
/// save time, so editing or deleting the original in between changed or
/// emptied what got saved. `MediaStagingStore` copies them at the moment
/// 품기 is pressed — compressed when that is worth it — and this is how a
/// save reads them back.
///
/// ⚠️Its bytes may be [framed]; the save writes them AS THEY ARE and names
/// the entry accordingly. Decoding a staged blob only to re-encode it
/// would burn the whole point of having compressed it at import.
///
/// 🚨★★★**AND A CONFORM IS THE SAME KIND OF FILE**, which is why this is
/// not called `MediaStagedBytes` any more. Both are files THIS APP wrote
/// into its own space, both may be framed, and both have the same answer
/// to [statSync] — see below. Two classes for that would have been two
/// spellings of one thing, and the second one would have been the one that
/// forgot [storedIsFramed].
class MediaAppFileBytes extends MediaByteSource {
  const MediaAppFileBytes({required this.path, required this.framed});

  final String path;
  final bool framed;

  @override
  bool get storedIsFramed => framed;

  @override
  Uint8List readSync() => File(path).readAsBytesSync();

  @override
  int lengthSync() => File(path).lengthSync();

  /// ⛔Null when [framed]: the file then holds compressed blocks, and the
  /// bytes at that span are not the container. Same rule as the archive
  /// entry next door, for the same reason.
  @override
  ({String path, int offset, int length})? get range =>
      framed ? null : _wholeFileRange(path);

  @override
  int readIntoSync(Uint8List buffer, int position, int size) {
    final handle = File(path).openSync();
    try {
      handle.setPositionSync(position);
      return handle.readIntoSync(buffer, 0, size);
    } finally {
      handle.closeSync();
    }
  }

  @override
  bool existsSync() => File(path).existsSync();

  /// No stat offered: this file's mtime is when WE wrote it — the import,
  /// or the conform build — not anything about the media it stands for,
  /// and [statSync] exists to answer "has the source changed underneath
  /// us". Offering a mtime that answers a different question is how a
  /// cache serves stale audio.
  @override
  MediaSourceStamp? statSync() => null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaAppFileBytes &&
          other.path == path &&
          other.framed == framed;

  @override
  int get hashCode => Object.hash(path, framed);

  @override
  String toString() => 'MediaAppFileBytes($path${framed ? " framed" : ""})';
}

/// The source a CONSUMER should read: a framed entry seen as the file it
/// holds, anything else as itself.
///
/// 🚨★★★**ONE PLACE DECIDES WHETHER TO DECODE.** The rule is three words
/// — decode if framed — which is exactly the size of rule that gets
/// written again at the next call site and then drifts. It was already
/// spelled twice before this existed, and both spellings had to be right
/// for a carried asset to come back as its own bytes.
///
/// ⛔The SAVE deliberately does not call this. It wants the entry as it
/// sits, so it can stream a staged blob into the archive without decoding
/// and re-encoding it — see `projectMediaSources`, which hands out stored
/// sources on purpose.
MediaByteSource mediaSourceDecodingFrames(MediaByteSource stored) =>
    stored.storedIsFramed ? MediaFramedBytes(stored) : stored;

/// The readable bytes of a file THIS APP wrote at [path] — a staged import
/// copy, or a conform.
///
/// 🚨★★★**THE NAME DECIDES, AND ONLY HERE.** Framed-or-not is written into
/// the file's name ([mediaFramedEntrySuffix]) exactly as it is into an
/// archive entry's, so「is this compressed」and「how do I read it」are one
/// question with one answer. Spelling it at the call site is how the
/// conform reader and the staging reader would come to disagree.
MediaByteSource mediaAppFileSource(String path) => mediaSourceDecodingFrames(
  MediaAppFileBytes(path: path, framed: mediaEntryIsFramed(path)),
);
