import 'dart:io';
import 'dart:typed_data';

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
}

/// Cheap facts about a source, from `stat` alone.
class MediaSourceStamp {
  const MediaSourceStamp({required this.lengthBytes, required this.modifiedMicros});

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
  });

  final String archivePath;

  /// Offset of the entry's raw bytes in [archivePath].
  final int dataOffset;
  final int length;

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
