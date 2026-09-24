import 'dart:io';
import 'dart:typed_data';

import '../../native/qa_media_span.dart';
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

  /// A reader of these bytes that keeps its file open until it is closed
  /// ([MediaWindowReader]) — for a document that reads them window after
  /// window for as long as it is open.
  MediaWindowReader openWindowReader();

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

  /// Where the medium these bytes stand for is STORED — a span of a file,
  /// and whether it sits there FRAMED (compressed in blocks) — or null when
  /// there is no file to name.
  ///
  /// 🚨★★★**THE ANSWER TO 「decode this without holding it」.** Every native
  /// reader takes exactly this — the movie decoders, the sound decoder, and
  /// the span reader Dart's own framed reads go through ([QaMediaSpan]) —
  /// so anything that can name itself this way never has to become a
  /// `Uint8List` first, which is the difference between a movie's
  /// soundtrack being conformable and a three-gigabyte allocation.
  ///
  /// 🪦This was `range`, and it was null for a framed entry: 「those bytes
  /// are compressed blocks, not the container」, so a framed sound was
  /// assembled in memory and a framed movie could not be read at all. The
  /// engine reads framed spans itself now (board `carried-movie-compressed`,
  /// 2026-09-24), so being framed is a FIELD of the answer rather than a
  /// reason to have none.
  ///
  /// ⚠️It names the MEDIUM for the stored source and for [MediaFramedBytes]
  /// over it alike, so a reader handed either one reads the same thing. It
  /// lives on the source for the same reason [storedIsFramed] does — the
  /// source is the only thing that knows, and every caller that rebuilt
  /// this by hand was one archive-layout change from being wrong.
  MediaSpan? get span => null;

  /// The file these bytes ARE, whole, for a reader that opens a file by its
  /// path — or null when they are a stretch of one, or framed.
  ///
  /// A reader handed a path reads through the platform's own file access
  /// and never holds the bytes in the Dart heap first; anything else has to
  /// be read to it. Only the source knows which it is — see [span].
  String? get wholeFilePath => null;
}

/// Where a medium is stored: [length] bytes of the file at [path] from
/// [offset] — the medium's own bytes, or a framed blob of them when [framed]
/// ([MediaByteSource.span]).
typedef MediaSpan = ({String path, int offset, int length, bool framed});

/// Cheap facts about a source, from `stat` alone — the CHEAP half of "has
/// this source changed".
///
/// Not an identity — that is `ConformSourceFingerprint`, which reads the
/// bytes. This is a hint that lets the common case skip that read: if the
/// source still has the length and timestamp it had when the conform was
/// written, nothing has touched it on this machine and the conform stands.
///
/// A miss means nothing on its own. A copied, restored or re-synced file
/// gets a fresh timestamp with identical bytes, and that is exactly the
/// case a timestamp identity used to answer wrong — so a miss falls
/// through to the content hash rather than deciding anything.
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

/// The whole of [path] as a span, or null when there is no file there.
///
/// 🚨★★★**[MediaByteSource.span] MUST NOT THROW.** It is asked as a
/// QUESTION — 「can you be decoded in place?」 — and every caller treats null
/// as 「no」. A missing original is the ordinary case at exactly the call
/// sites that ask: the viewer asks precisely because the import original is
/// gone. Letting `lengthSync` throw out of a getter turned that into an
/// exception on a path whose whole job is to answer 「not this way」.
///
/// ⚠️A try rather than an `existsSync` in front: that is one stat instead of
/// two, and it is also the only version without a race between the two.
MediaSpan? _wholeFileSpan(String path, {required bool framed}) {
  try {
    return (
      path: path,
      offset: 0,
      length: File(path).lengthSync(),
      framed: framed,
    );
  } on Object {
    return null;
  }
}

/// A reader of a medium's bytes a window at a time that keeps ONE file
/// handle for its whole life — [close] it when done.
///
/// 🚨For a reader that goes back to the same bytes for as long as a
/// document is open — PDFium turning pages. [MediaByteSource.readIntoSync]
/// opens and closes the file for every window, and a document asks for
/// thousands of them; and a handle kept open is what keeps reading the
/// file it opened, where a fresh open per window would find whatever a
/// whole rewrite had put at that path (audit 2026-09-24).
abstract interface class MediaWindowReader {
  /// Fills [buffer] with up to [size] bytes from [position], and answers
  /// how many landed — [MediaByteSource.readIntoSync]'s shape.
  int readIntoSync(Uint8List buffer, int position, int size);

  void close();
}

/// The one IO primitive under every source that lives in a file — the
/// plain file, the app-support file and the archive entry, which reads
/// from its own [base] and is clamped to its own [length].
final class _FileWindowReader implements MediaWindowReader {
  _FileWindowReader(String path, {this.base = 0, this.length})
    : _file = File(path).openSync();

  final RandomAccessFile _file;
  final int base;
  final int? length;

  @override
  int readIntoSync(Uint8List buffer, int position, int size) {
    final limit = length;
    if (position < 0 || size <= 0 || (limit != null && position >= limit)) {
      return 0;
    }
    final wanted = limit == null || size < limit - position
        ? size
        : limit - position;
    _file.setPositionSync(base + position);
    return _file.readIntoSync(buffer, 0, wanted);
  }

  @override
  void close() => _file.closeSync();
}

/// [size] bytes from [position] through a [reader] opened for this one
/// read — what [MediaByteSource.readIntoSync] is for a source in a file.
int _readOnce(
  MediaWindowReader reader,
  Uint8List buffer,
  int position,
  int size,
) {
  try {
    return reader.readIntoSync(buffer, position, size);
  } finally {
    reader.close();
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

  /// A whole file IS a span — offset 0, its own length. ⛔Saying null here
  /// because 「it is not inside anything」 would make every caller carry a
  /// second path for the ordinary case.
  @override
  MediaSpan? get span => _wholeFileSpan(path, framed: false);

  @override
  String? get wholeFilePath => path;

  @override
  MediaWindowReader openWindowReader() => _FileWindowReader(path);

  @override
  int readIntoSync(Uint8List buffer, int position, int size) =>
      _readOnce(openWindowReader(), buffer, position, size);

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
/// ⚠️ **Not KEPT across a save — only HELD.** Offsets belong to one layout,
/// and a compaction rewrites the file — a source kept from before would
/// read a window of whatever now occupies those bytes, which is a project
/// that opens fine and plays the wrong sound. These are made from the
/// archive's current layout at the moment of use; a reader that goes on
/// reading one holds its entry (`ProjectFile.holdMediaBytes`), and a save
/// neither moves a held entry nor drops it.
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

  /// The entry where it lies, framed or not as its name says — the case the
  /// whole idea exists for: a movie carried inside the project file,
  /// decodable in place.
  @override
  MediaSpan get span => (
    path: archivePath,
    offset: dataOffset,
    length: length,
    framed: framed,
  );

  /// Clamped to the entry, so a caller asking past the end of its media
  /// gets a short read rather than the bytes of whatever follows it in the
  /// archive.
  @override
  MediaWindowReader openWindowReader() =>
      _FileWindowReader(archivePath, base: dataOffset, length: length);

  @override
  int readIntoSync(Uint8List buffer, int position, int size) =>
      _readOnce(openWindowReader(), buffer, position, size);

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
/// 🚨★★★**THE ENGINE'S READER DOES THE READING** ([QaMediaSpan]) — the one
/// every decoder reads a framed span through. 🪦This class used to walk the
/// blocks itself, keeping the index and the last block it decoded: a second
/// reader of one format, beside which the decoders would have needed a
/// third, so it went (board `carried-movie-compressed`, 2026-09-24).
///
/// ⚠️[knownCrc32] is deliberately null. ZIP's CRC describes the COMPRESSED
/// bytes; this class hands back the uncompressed ones, so answering with
/// it would hand the conform pipeline a checksum of something it never
/// sees — and that pipeline treats a mismatch as a torn read and retries.
class MediaFramedBytes extends MediaByteSource {
  MediaFramedBytes(this.stored);

  /// The source whose stored bytes are the framed blob this decodes.
  ///
  /// 🚨★★★**A WRAPPER THAT CANNOT NAME WHAT IT WRAPS IS OPAQUE TO EVERY
  /// READER, AND ONE OF THEM WAS A TEST HELPER.** `conformFilePathOrNull`
  /// asks 「which file did this conform land in」 by matching the source's
  /// kind, and it had no case for this one — so the moment the compressor
  /// was actually available and a conform came back FRAMED, it answered
  /// null and nine tests died on a `!`. They had never run with an engine,
  /// so nobody saw it (2026-09-08).
  ///
  /// ⛔This is not「a question production does not need」that the type was
  /// taught anyway: the class already derived its label from this source
  /// and then threw the source away, so it was answering the question badly
  /// rather than not at all.
  final MediaByteSource stored;

  /// [stored]'s span, FRAMED whatever [stored] says of itself — being
  /// handed to this class is what says its bytes are a framed blob.
  @override
  MediaSpan? get span {
    final at = stored.span;
    return at == null
        ? null
        : (path: at.path, offset: at.offset, length: at.length, framed: true);
  }

  /// The engine's reader over [span], or a throw that says which of three
  /// it was: the bytes are gone, this build has no engine to read them
  /// with, or they do not hold together.
  QaMediaSpan _openSpan() {
    final at = span;
    if (at == null) {
      throw FileSystemException('the stored bytes are not there', '$stored');
    }
    final opened = QaMediaSpan.open(
      at.path,
      offset: at.offset,
      length: at.length,
      framed: at.framed,
    );
    if (opened != null) {
      return opened;
    }
    // ⛔「No engine」 is something the user can act on, and must not reach
    // the screen as 「corrupt」 — the same line the cel reader draws.
    throw FormatException(
      QaMediaSpan.available
          ? 'this framed media entry does not hold together'
          : 'This media was compressed with zstd and no engine is available '
                'to read it.',
    );
  }

  @override
  int lengthSync() {
    final opened = _openSpan();
    try {
      return opened.size;
    } finally {
      opened.close();
    }
  }

  @override
  Uint8List readSync() {
    final opened = _openSpan();
    try {
      final out = Uint8List(opened.size);
      opened.readInto(out, 0, out.length);
      return out;
    } finally {
      opened.close();
    }
  }

  @override
  int readIntoSync(Uint8List buffer, int position, int size) =>
      _readOnce(openWindowReader(), buffer, position, size);

  /// The engine's reader, kept open — and its one decoded block with it, so
  /// a document that reads in windows far smaller than a block (PDFium asks
  /// for a few hundred bytes at a time) decodes each block once rather than
  /// once a window (audit 2026-09-24).
  @override
  MediaWindowReader openWindowReader() => _SpanWindowReader(_openSpan());

  @override
  bool existsSync() => stored.existsSync();

  @override
  MediaSourceStamp? statSync() => null;

  @override
  String toString() => 'MediaFramedBytes($stored)';
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

  /// The whole file, framed or not as its name says — the same answer as
  /// the archive entry next door, for the same reason.
  @override
  MediaSpan? get span => _wholeFileSpan(path, framed: framed);

  @override
  String? get wholeFilePath => framed ? null : path;

  @override
  MediaWindowReader openWindowReader() => _FileWindowReader(path);

  @override
  int readIntoSync(Uint8List buffer, int position, int size) =>
      _readOnce(openWindowReader(), buffer, position, size);

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

/// A medium's bytes a reader holds (`ProjectFile.holdMediaBytes`), how it
/// gives them back, and when — and how — they have [moved].
///
/// 🚨★★★**[moved] completes when the answer to 「where are these bytes」 is
/// somewhere else now** — a save absorbed the staged copy the reader holds
/// into the project file, or wrote that file anew elsewhere (a save-as) — or
/// is ABOUT to be, because a save is replacing the very file they are in. A
/// reader that keeps reading (a document the viewer shows, a movie a canvas
/// row decodes) opens again on the new answer, in the order the move says
/// ([HeldBytesMove]): held, the bytes would stay where they are for as long
/// as it lives — a staged copy on disk beside the entry that replaced it
/// (card `canvas-holds-staged-for-session`; 유저 08-27: 「사본 남으면 진짜
/// 용서안할게」), a file a save cannot replace (card
/// `rewrite-under-offset-readers`). A reader that is done in a moment never
/// looks.
typedef HeldMediaBytes = ({
  MediaByteSource source,
  void Function() release,
  Future<HeldBytesMove> moved,
});

/// How a reader's bytes moved ([HeldMediaBytes.moved]) — and so the order
/// it opens again in.
enum HeldBytesMove {
  /// A save put them somewhere else. Open the new answer FIRST, then let
  /// these go: nothing waits on the reader, and no frame waits on a closed
  /// one.
  elsewhere,

  /// A save is about to replace the very file they are in, and cannot while
  /// anything in this process holds it open — Windows refuses a rename onto
  /// an open file (measured with our own handle, `OpenProjectFile`; the
  /// engine opens without delete sharing too, `qa_open_path_read`). Let
  /// these go NOW: the save waits for it, and the next open waits for the
  /// save, then finds the new answer.
  replacing,
}

/// Where every reader asks for a medium's bytes —
/// `ProjectFile.holdMediaBytes`: the project's own copy first, then the file
/// it came from.
typedef HoldMediaBytes = Future<HeldMediaBytes> Function(String path);

/// All of [path]'s bytes, read while [hold] holds them — for a reader that
/// decodes a whole file at once (a picture, a Photoshop document).
Future<Uint8List> readHeldMediaBytes(HoldMediaBytes hold, String path) async {
  final held = await hold(path);
  try {
    return await held.source.read();
  } finally {
    held.release();
  }
}

/// [open] on the bytes [hold] answers for [path], HELD for as long as what it
/// opened lives — [keep] ties the hold to it: the release to run once it has
/// closed, and the move to follow ([HeldMediaBytes.moved]) — and given back
/// at once when nothing opens.
///
/// 🚨The one shape of 「a reader that keeps reading」: a document the viewer
/// shows, a PDF a placement renders page by page, a movie a canvas row or a
/// bake decodes frame by frame. Each is a different thing to CLOSE, and the
/// same thing to hold (유저 2026-09-11: 「파일 뭐든 관계없이 법 하나로」).
Future<K?> openOnHeldBytes<T extends Object, K extends Object>(
  HoldMediaBytes hold,
  String path,
  Future<T?> Function(MediaByteSource source) open,
  K Function(T opened, HeldMediaBytes held) keep,
) async {
  final held = await hold(path);
  final T? opened;
  try {
    opened = await open(held.source);
  } on Object {
    held.release();
    rethrow;
  }
  if (opened == null) {
    held.release();
    return null;
  }
  return keep(opened, held);
}

/// A medium read through the engine's reader ([QaMediaSpan]) a window at a
/// time, for as long as it is open — what [MediaFramedBytes.openWindowReader]
/// hands out.
final class _SpanWindowReader implements MediaWindowReader {
  _SpanWindowReader(this._span);

  final QaMediaSpan _span;

  @override
  int readIntoSync(Uint8List buffer, int position, int size) =>
      position < 0 || size <= 0 ? 0 : _span.readInto(buffer, position, size);

  @override
  void close() => _span.close();
}
