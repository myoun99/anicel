/// Incremental .anicel appender (R22-C): the container is ordinary ZIP with
/// every entry STORE'd (cel blobs carry their own compression), which makes
/// appends trivial and spec-legal — new local entries and a fresh central
/// directory + EOCD go on the END of the file. Standard readers (including
/// our own `parseAnicelArchiveBytes`) see only the LATEST central
/// directory, so a re-saved `project.json` or a superseded cel simply
/// shadows its old bytes — dead until [compactAnicelInPlace] packs the live
/// ones down over them.
///
/// 🚨★★★CRASH CONTRACT (유저 2026-09-23: 「전부 재사용으로 하고싶은데
/// 거기서 저장중 크래시만 어떻게 안전책 만들수없나?」): at every instant,
/// the newest complete directory in the file names only bytes that are
/// intact. Nothing a committed directory names is ever written over — a
/// save commits first (its directory APPENDED after the old one, which
/// stays whole until the new one has landed), and only then writes into
/// bytes that directory has let go of. A crash therefore opens as the
/// state before the save or the state after it
/// ([recoverAnicelZipLayoutFile]).
///
/// 🪦Until 2026-09-23 the append truncated at the old directory and wrote
/// over it, so a crash left NO directory and the open path had to rebuild
/// one by walking local headers — which only works while the file is in
/// append order, and the push-down is what stops it being so.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'anicel_project_archive.dart';

/// One parsed central-directory record we care about.
class AnicelZipEntry {
  AnicelZipEntry({
    required this.name,
    required this.localHeaderOffset,
    required this.dataOffset,
    required this.length,
    required this.crc32,
  });

  final String name;
  final int localHeaderOffset;

  /// Offset of the entry's RAW bytes (STORE'd, so bytes == the payload).
  final int dataOffset;
  final int length;
  final int crc32;
}

/// The parsed tail of a .anicel: every ACTIVE entry (latest central
/// directory) plus the offset where the central directory begins — the
/// append position.
class AnicelZipLayout {
  AnicelZipLayout({
    required this.entries,
    required this.centralDirectoryOffset,
  });

  final List<AnicelZipEntry> entries;
  final int centralDirectoryOffset;

  AnicelZipEntry? entryNamed(String name) {
    for (final entry in entries) {
      if (entry.name == name) {
        return entry;
      }
    }
    return null;
  }

  /// The project manifest, preferring the compressed name — an append can
  /// shadow an old `project.json` by adding `project.json.z` beside it, so
  /// both may be present until a compaction rewrites the file.
  AnicelZipEntry? projectEntry() =>
      entryNamed(anicelProjectEntryNameCompressed) ??
      entryNamed(anicelProjectEntryName);
}

const int _eocdSignature = 0x06054b50;
const int _centralSignature = 0x02014b50;
const int _localSignature = 0x04034b50;
const int _zip64EndSignature = 0x06064b50;
const int _zip64LocatorSignature = 0x07064b50;

/// The ZIP64 Extended Information extra field's header id.
const int _zip64ExtraId = 0x0001;

/// What a plain ZIP field can say. Above these the value is written as
/// all-ones and the truth moves into a ZIP64 record.
const int _zip16Max = 0xFFFF;
const int _zip32Max = 0xFFFFFFFF;

/// Whether EVERY archive gets ZIP64 records, or only the ones that need
/// them.
///
/// ✅ **On.** Every archive carries the ZIP64 records, whatever its size.
///
/// 🔑 The reason this costs nothing is the rule in `_eocdBytes` below: a
/// sentinel goes into a plain field only when the TRUTH does not fit
/// there, never merely because ZIP64 records exist. So an archive that
/// happens to fit is still read correctly by a reader that has never
/// heard of ZIP64 — it takes the real count at the real offset and never
/// looks at the extra records behind it. What an older build loses is
/// exactly the files that genuinely overflow, and those it could not have
/// opened under any writer.
///
/// ⛔ The alternative — emit them only when needed — was the first
/// version, and its cost is a format that CHANGES SHAPE MID-LIFE: a
/// project crosses 65,535 entries during an append and the record layout
/// has to change under a file that already exists, at that exact moment.
/// This repo has been caught by threshold bands before ("only breaks
/// between 206 and 250 pixels wide"), and a band nobody reaches in
/// testing is the worst kind.
///
/// The switch stays because it is the one-line revert if some reader in
/// the wild turns out to disagree, and because it is how the OTHER shape
/// stays under test — see the group that pins it false.
///
/// The const is the SHIPPED default, initializer-only so the two cannot
/// drift; it exists because tests reset the mutable switch, so only the
/// const can pin what production actually starts with.
const bool anicelAlwaysZip64Shipped = true;

bool anicelAlwaysZip64 = anicelAlwaysZip64Shipped;

/// The value at which a per-entry 32-bit field (entry SIZES, local header
/// OFFSET) moves into that entry's ZIP64 extra, leaving the sentinel in
/// the fixed field.
///
/// 🔑 유저 결정 2026-08-26 (Q-save-4gb-carry: 「클라우드 무거워지는 건
/// 무거운 파일 품은 유저가 감수할 문제고 **zip64로 통일화**」): a >4GB
/// file CAN be carried — the format stretches instead of the writer
/// refusing. Before this, an entry past 4GB threw at save time, and since
/// the kind ceiling fell (08-14) a user could reach that throw by
/// importing a big movie as Keep: every save failed for ever with no
/// un-carry verb. Same sentinel-only-on-overflow law as the EOCD fields
/// above: the fixed field carries the TRUTH whenever it fits, so ordinary
/// archives stay byte-identical and readable by pre-ZIP64 readers.
///
/// `>=` rather than `>` because the sentinel VALUE itself cannot be
/// stored plain — a field holding a literal 0xFFFFFFFF reads as flagged.
///
/// Mutable because 4GB fixtures are not a thing a test suite can write:
/// tests lower it to force the ZIP64 shape onto small entries, and the
/// shipped const pins what production starts with (the test config resets
/// the mutable one).
const int anicelZip64FieldLimitShipped = 0xFFFFFFFF;

int anicelZip64FieldLimit = anicelZip64FieldLimitShipped;

/// Reads the ZIP64 entry count and central-directory offset when the
/// plain EOCD is flying all-ones flags, or null when it is not.
///
/// [tail] holds the bytes ending at the plain EOCD, and [eocd] is that
/// record's offset within it. The locator sits immediately before the
/// EOCD and points at the ZIP64 record; [tailStart] is where [tail] began
/// in the file, so an absolute pointer can be turned back into an index.
({int entryCount, int centralOffset, int centralLength})? _readZip64End(
  ByteData tail,
  int eocd, {
  required int tailStart,
}) {
  final locator = eocd - 20;
  if (locator < 0 ||
      tail.getUint32(locator, Endian.little) != _zip64LocatorSignature) {
    return null;
  }
  final absolute = tail.getUint64(locator + 8, Endian.little);
  final index = absolute - tailStart;
  if (index < 0 ||
      index + 56 > tail.lengthInBytes ||
      tail.getUint32(index, Endian.little) != _zip64EndSignature) {
    // The locator says the record is outside the window we read. Every
    // writer puts it immediately before the locator, so this means a file
    // built by something else in a shape this reader has not learned —
    // louder than quietly reading a truncated count.
    throw const FormatException(
      'ZIP64 end record not found where the '
      'locator points.',
    );
  }
  return (
    entryCount: tail.getUint64(index + 32, Endian.little),
    centralOffset: tail.getUint64(index + 48, Endian.little),
    centralLength: tail.getUint64(index + 40, Endian.little),
  );
}

/// The ZIP64 extra field (id 0x0001) inside an extra block: where its
/// payload starts and how long that payload says it is, or null when the
/// block does not carry one.
///
/// ⛔THREE READERS WALKED FOR IT SEPARATELY — the central record's offset
/// and its size, and a local header's size — and they did not agree on the
/// bounds: one checked the payload's own declared length before reading a
/// value out of it and the other only checked the block's end. They share
/// this walk now, and each states its own bound against BOTH.
({int at, int length})? _zip64Extra(ByteData data, int start, int end) {
  var walk = start;
  while (walk + 4 <= end) {
    final id = data.getUint16(walk, Endian.little);
    final size = data.getUint16(walk + 2, Endian.little);
    if (id == _zip64ExtraId) {
      return (at: walk + 4, length: size);
    }
    walk += 4 + size;
  }
  return null;
}

/// Which 64-bit value a central record's ZIP64 extra is being asked for.
enum _Zip64CentralField {
  /// The entry's compressed length.
  compressedSize('size', fixedAt: 20),

  /// Where the entry's LOCAL header begins.
  localOffset('offset', fixedAt: 42);

  const _Zip64CentralField(this.noun, {required this.fixedAt});

  /// What the 32-bit field is called when it has to say it is missing.
  final String noun;

  /// The 32-bit field's offset from the record's start — all-ones there
  /// is what sends the reader to the extra.
  final int fixedAt;
}

/// The value a central record names for [want], following its ZIP64 extra
/// field when the fixed field is all-ones.
///
/// ⛔THE ORDER IS FIXED AND THE SKIPS ARE THE LAW. The 64-bit values
/// appear as uncompressed size, compressed size, local header offset —
/// and ONLY for the fields flagged all-ones, so a reader has to skip by
/// what is flagged, not by what it expects. Since the ZIP64 size round
/// (유저 08-26: 4GB 초과도 품는다) this writer flags sizes too, and a
/// foreign file may flag one of a pair. Written out per field, the reader
/// that forgets a skip returns the PREVIOUS field's eight bytes and calls
/// them an offset — which points the next read into the middle of an
/// entry.
int _centralZip64Field(
  ByteData data,
  int cursor,
  ({int start, int length}) extraField,
  _Zip64CentralField want,
) {
  final fixed = data.getUint32(cursor + want.fixedAt, Endian.little);
  if (fixed != _zip32Max) {
    return fixed;
  }
  final end = extraField.start + extraField.length;
  final extra = _zip64Extra(data, extraField.start, end);
  if (extra != null) {
    var at = extra.at;
    if (data.getUint32(cursor + 24, Endian.little) == _zip32Max) {
      at += 8; // uncompressed size
    }
    if (want == _Zip64CentralField.localOffset &&
        data.getUint32(cursor + 20, Endian.little) == _zip32Max) {
      at += 8; // compressed size
    }
    if (at + 8 <= extra.at + extra.length && at + 8 <= end) {
      return data.getUint64(at, Endian.little);
    }
  }
  throw FormatException(
    'Central record flags a ZIP64 ${want.noun} with '
    'no extra field to hold it.',
  );
}

/// The compressed size out of a LOCAL header's ZIP64 extra, or null when
/// no well-formed one is there. Local extras carry both sizes whenever
/// either is flagged (spec), uncompressed first.
int? _localZip64CompressedSize(Uint8List extraBytes) {
  final data = ByteData.sublistView(extraBytes);
  final extra = _zip64Extra(data, 0, extraBytes.length);
  if (extra == null || extra.length < 16 || extra.at + 16 > extraBytes.length) {
    return null;
  }
  return data.getUint64(extra.at + 8, Endian.little);
}

/// The buffer a central directory is being read out of: two views of the
/// SAME bytes and how far they go. The whole archive for the in-memory
/// parse, the central directory alone for the streaming one — one thing
/// either way, which is why it travels as one.
typedef _CentralBlock = ({ByteData data, Uint8List bytes, int limit});

/// One central-directory record at [cursor], and where the next one starts.
///
/// ⛔BOUNDS FIRST, READS SECOND. A garbage length or offset behind a
/// surviving EOCD (out-of-order page writeback, external corruption) must
/// fall out as the [FormatException] the callers catch — their
/// `on FormatException` IS the recovery — and never as a RangeError that
/// escapes them and refuses a salvageable file.
///
/// [cursor] is in [block]'s own coordinates; [fileLength] is the archive's
/// full length either way, because a local header offset is always
/// absolute. [localHeaderLengths] is the one thing the two parsers
/// genuinely do differently: one already holds the whole file, the other
/// seeks and reads four bytes. (Both now reach it through the one
/// `readAt` the shared parse takes, so that difference is the SOURCE's,
/// not a second parser's.)
({AnicelZipEntry entry, int nextCursor}) _readCentralEntry(
  _CentralBlock block,
  int cursor, {
  required int fileLength,
  required int Function(int localOffset) localHeaderLengths,
}) {
  final data = block.data;
  final limit = block.limit;
  if (cursor < 0 ||
      cursor + 46 > limit ||
      data.getUint32(cursor, Endian.little) != _centralSignature) {
    throw const FormatException('Corrupt central directory.');
  }
  final crc = data.getUint32(cursor + 16, Endian.little);
  final nameLength = data.getUint16(cursor + 28, Endian.little);
  final extraLength = data.getUint16(cursor + 30, Endian.little);
  final commentLength = data.getUint16(cursor + 32, Endian.little);
  if (cursor + 46 + nameLength + extraLength + commentLength > limit) {
    throw const FormatException('Corrupt central directory.');
  }
  final extraField = (start: cursor + 46 + nameLength, length: extraLength);
  final compressedSize = _centralZip64Field(
    data,
    cursor,
    extraField,
    _Zip64CentralField.compressedSize,
  );
  final localOffset = _centralZip64Field(
    data,
    cursor,
    extraField,
    _Zip64CentralField.localOffset,
  );
  final name = String.fromCharCodes(
    block.bytes.sublist(cursor + 46, cursor + 46 + nameLength),
  );
  // Local header: fixed 30 bytes + its own name/extra lengths.
  if (localOffset < 0 || localOffset + 30 > fileLength) {
    throw const FormatException('Corrupt central directory.');
  }
  return (
    entry: AnicelZipEntry(
      name: name,
      localHeaderOffset: localOffset,
      dataOffset: localOffset + 30 + localHeaderLengths(localOffset),
      length: compressedSize,
      crc32: crc,
    ),
    nextCursor: cursor + 46 + nameLength + extraLength + commentLength,
  );
}

/// Parses the central directory of [bytes] (a complete .anicel). Throws
/// [FormatException] whenever the tail cannot be parsed — no EOCD (torn
/// append) OR a corrupt record behind a surviving EOCD. One exception
/// type on purpose: the production fallbacks (`on FormatException` at the
/// open and incremental-save sites) are the recovery, and a RangeError
/// escaping them turned a salvageable file into one that refused to open.
AnicelZipLayout parseAnicelZipLayout(Uint8List bytes) =>
    _parseAnicelZipLayoutFrom(
      length: bytes.length,
      readAt: (offset, count) {
        // ⛔BOUNDS FIRST here too: a garbage offset must be the
        // [FormatException] the callers catch, never a RangeError out of
        // `sublistView`. No copy — the window is a view.
        if (offset < 0 || count < 0 || offset + count > bytes.length) {
          throw const FormatException('Corrupt central directory.');
        }
        return Uint8List.sublistView(bytes, offset, offset + count);
      },
    );

/// Parses the layout straight from the FILE with tail-only reads (EOCD
/// scan window + central directory + 4 bytes per local header) — a
/// multi-gigabyte project must never load whole just to append a few
/// cels or list its entries.
AnicelZipLayout parseAnicelZipLayoutFile(String path) => _readingFile(
  path,
  (length, readAt) =>
      _parseAnicelZipLayoutFrom(length: length, readAt: readAt),
);

/// [read] over the file at [path]: its length, and reads by seek — what the
/// parse and the recovery both need from a file and nothing more.
T _readingFile<T>(String path, T Function(int length, _ReadAt readAt) read) {
  final raf = File(path).openSync();
  try {
    return read(raf.lengthSync(), (offset, count) {
      raf.setPositionSync(offset);
      return raf.readSync(count);
    });
  } finally {
    raf.closeSync();
  }
}

/// THE parse, over any byte source.
///
/// [readAt] is asked for the tail window once, the central directory once,
/// and four bytes per entry — the reason the file variant can answer
/// without loading the archive. Whether those bytes come from a buffer
/// already in hand or from a seek is the only difference between the two
/// entry points, so it is the only thing they hand in.
AnicelZipLayout _parseAnicelZipLayoutFrom({
  required int length,
  required _ReadAt readAt,
}) {
  if (length < 22) {
    throw const FormatException('No ZIP end-of-central-directory found.');
  }
  // EOCD: scan back over a possible comment (max 64KB + 22).
  final tailLength = length < 22 + 65535 ? length : 22 + 65535;
  final tailStart = length - tailLength;
  final tail = readAt(tailStart, tailLength);
  final tailData = ByteData.sublistView(tail);
  var eocd = -1;
  for (var i = tail.length - 22; i >= 0; i -= 1) {
    if (tailData.getUint32(i, Endian.little) == _eocdSignature) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) {
    throw const FormatException('No ZIP end-of-central-directory found.');
  }
  // 🚨THE DIRECTORY IS THE LAST THING IN A FINISHED FILE. A save writes its
  // entries AFTER the committed directory and its own directory after
  // them, so bytes past an EOCD are a save that did not finish — and the
  // EOCD found here is then the PREVIOUS save's. Taking it as the file
  // would open a state the file is halfway out of, and an append onto it
  // would write over the unfinished save's bytes before anything decided
  // they were garbage. Refused, the open path takes the recovery
  // ([recoverAnicelZipLayoutFile]) and a save takes the whole write, which
  // heals the file.
  final commentLength = tailData.getUint16(eocd + 20, Endian.little);
  if (tailStart + eocd + 22 + commentLength != length) {
    throw const FormatException(
      'Bytes after the end-of-central-directory: a save did not finish.',
    );
  }
  final zip64 = _readZip64End(tailData, eocd, tailStart: tailStart);
  final entryCount =
      zip64?.entryCount ?? tailData.getUint16(eocd + 10, Endian.little);
  final centralOffset =
      zip64?.centralOffset ?? tailData.getUint32(eocd + 16, Endian.little);
  // With ZIP64 the central directory ends at the ZIP64 record rather
  // than at the plain EOCD — reading to the EOCD would swallow the
  // ZIP64 record and locator as if they were another entry.
  final centralEnd = zip64 == null
      ? tailStart + eocd
      : centralOffset + zip64.centralLength;
  if (centralOffset > centralEnd) {
    throw const FormatException('Corrupt central directory.');
  }

  final central = readAt(centralOffset, centralEnd - centralOffset);
  final data = ByteData.sublistView(central);
  final entries = <AnicelZipEntry>[];
  var cursor = 0;
  for (var i = 0; i < entryCount; i += 1) {
    final read = _readCentralEntry(
      (data: data, bytes: central, limit: central.length),
      cursor,
      fileLength: length,
      localHeaderLengths: (localOffset) {
        final localLengths = ByteData.sublistView(readAt(localOffset + 26, 4));
        if (localLengths.lengthInBytes < 4) {
          throw const FormatException('Corrupt central directory.');
        }
        return localLengths.getUint16(0, Endian.little) +
            localLengths.getUint16(2, Endian.little);
      },
    );
    entries.add(read.entry);
    cursor = read.nextCursor;
  }
  return AnicelZipLayout(
    entries: entries,
    centralDirectoryOffset: centralOffset,
  );
}

/// Opens a file whose tail does not parse — the state a crashed save left.
///
/// 🚨★★★THE NEWEST DIRECTORY STILL WHOLE IS THE LAST SAVE THAT FINISHED.
/// The crash contract (library doc) keeps every committed directory's
/// bytes intact until a newer directory has landed after it, so scanning
/// back from the end for the first EOCD whose directory parses — and whose
/// every entry starts with its own local header — finds exactly the state
/// the last completed save left.
///
/// Then the save that died. If everything after that directory is a
/// COMPLETE run of entries, each CRC-true, ending where the next directory
/// begins, that save wrote all of its entries and died writing the
/// directory that would have committed them: they win, last-wins by name,
/// and the work is not lost. A run that ends anywhere else is a save that
/// died partway through its entries, and it is ignored — the state before
/// it is whole, and half of a save laid over it would be neither state.
/// ⚠️In the committing case the names that save REMOVED come back (the
/// directory that would have said so is what did not land) — for crash
/// recovery, too much beats lost (R24-D1).
///
/// Only when no directory is whole does the old walk run
/// ([_walkFromTheFront]) — a file this build did not leave that way, or one
/// an older build did. The next save cannot append onto any of these (the
/// tail still does not parse), so it writes the file whole and heals it.
AnicelZipLayout recoverAnicelZipLayoutFile(String path) => _readingFile(
  path,
  (length, readAt) => _recoverFrom(length: length, readAt: readAt),
);

/// [recoverAnicelZipLayoutFile] over bytes already in hand — the same
/// recovery, so a test can open every state a crash can leave without a
/// file per state.
@visibleForTesting
AnicelZipLayout recoverAnicelZipLayout(Uint8List bytes) => _recoverFrom(
  length: bytes.length,
  readAt: (offset, count) {
    final start = offset < 0 ? 0 : (offset > bytes.length ? bytes.length : offset);
    final end = start + count > bytes.length ? bytes.length : start + count;
    return Uint8List.sublistView(bytes, start, end);
  },
);

/// Up to [count] bytes of a byte source from [offset]. A file hands back
/// fewer where it ends (and the recovery reads bytes in hand the same way);
/// the in-memory parse refuses such a read outright.
typedef _ReadAt = Uint8List Function(int offset, int count);

/// THE recovery, over any byte source.
AnicelZipLayout _recoverFrom({required int length, required _ReadAt readAt}) {
  final committed = _newestWholeDirectory(readAt, length);
  if (committed == null) {
    return _walkFromTheFront(readAt, length);
  }
  final landed = _runADyingCommitWrote(
    readAt,
    from: committed.end,
    length: length,
  );
  if (landed == null || landed.entries.isEmpty) {
    return committed.layout;
  }
  final byName = {
    for (final entry in committed.layout.entries) entry.name: entry,
  };
  for (final entry in landed.entries) {
    byName[entry.name] = entry;
  }
  return AnicelZipLayout(
    entries: [...byName.values],
    centralDirectoryOffset: landed.end,
  );
}

/// The newest directory in the source that is whole, and where its EOCD
/// ends — or null when there is none.
///
/// Scans back from the end in windows, so a crash that left a long run of
/// unfinished bytes behind the directory costs a read of those bytes and
/// no more.
({AnicelZipLayout layout, int end})? _newestWholeDirectory(
  _ReadAt readAt,
  int length,
) {
  const window = 64 * 1024;
  // Candidates are where an EOCD could START; a whole one is 22 bytes.
  var high = length - 22;
  while (high >= 0) {
    final low = high - window + 1 < 0 ? 0 : high - window + 1;
    // Three bytes past [high] so a signature starting AT it reads whole.
    final bytes = readAt(low, high + 4 - low);
    final data = ByteData.sublistView(bytes);
    for (var i = high - low; i >= 0; i -= 1) {
      if (i + 4 > bytes.length ||
          data.getUint32(i, Endian.little) != _eocdSignature) {
        continue;
      }
      final end = low + i + 22;
      final layout = _wholeDirectoryEndingAt(readAt, end);
      if (layout != null) {
        return (layout: layout, end: end);
      }
    }
    high = low - 1;
  }
  return null;
}

/// The directory whose EOCD ends at [end], when it is one a save of this
/// format committed — parsed as if the source stopped there, and every
/// entry it names beginning with its own local header.
///
/// ⚠️The local-header check is what makes an OLD directory fail. A
/// directory the push-down has since moved past can still parse — its
/// bytes were never overwritten — while the entries it names were; the
/// header that should open each one is someone else's bytes now.
AnicelZipLayout? _wholeDirectoryEndingAt(_ReadAt readAt, int end) {
  final AnicelZipLayout layout;
  try {
    layout = _parseAnicelZipLayoutFrom(
      length: end,
      readAt: (offset, count) {
        if (offset < 0 || count < 0 || offset + count > end) {
          throw const FormatException('Outside the candidate directory.');
        }
        return readAt(offset, count);
      },
    );
  } on FormatException {
    return null;
  }
  for (final entry in layout.entries) {
    if (entry.dataOffset + entry.length > layout.centralDirectoryOffset) {
      return null;
    }
    final header = readAt(entry.localHeaderOffset, 30 + entry.name.length);
    if (header.length < 30 + entry.name.length ||
        ByteData.sublistView(header).getUint32(0, Endian.little) !=
            _localSignature ||
        String.fromCharCodes(header, 30) != entry.name) {
      return null;
    }
  }
  return layout;
}

/// The entries a save wrote after [from] when it got as far as starting
/// the directory that would have committed them — every one whole and
/// CRC-true, and a central-directory record begun right behind the last.
/// Null for any other shape: a save that died among its entries.
///
/// ⚠️"Begun" is three bytes: `PK\x01` already says central record where a
/// local header would read `PK\x03`, while one or two bytes could be
/// either — and a file that ends exactly after an entry could have had
/// more entries coming.
({List<AnicelZipEntry> entries, int end})? _runADyingCommitWrote(
  _ReadAt readAt, {
  required int from,
  required int length,
}) {
  final entries = <AnicelZipEntry>[];
  var cursor = from;
  while (cursor < length) {
    final head = readAt(cursor, 4);
    if (head.length >= 3 &&
        head[0] == 0x50 &&
        head[1] == 0x4B &&
        head[2] == 0x01 &&
        (head.length < 4 || head[3] == 0x02)) {
      return (entries: entries, end: cursor);
    }
    final entry = _localEntryAt(readAt, cursor, length);
    if (entry == null || !_crcHolds(readAt, entry)) {
      return null;
    }
    entries.add(entry);
    cursor = entry.dataOffset + entry.length;
  }
  return null;
}

/// The whole local entry at [cursor], or null when there is none — no
/// local signature, or a header or data that runs past [length].
AnicelZipEntry? _localEntryAt(_ReadAt readAt, int cursor, int length) {
  if (cursor + 30 > length) {
    return null;
  }
  final header = readAt(cursor, 30);
  if (header.length < 30) {
    return null;
  }
  final data = ByteData.sublistView(header);
  if (data.getUint32(0, Endian.little) != _localSignature) {
    return null; // A directory remnant or torn garbage.
  }
  final crc = data.getUint32(14, Endian.little);
  var compressedSize = data.getUint32(18, Endian.little);
  final nameLength = data.getUint16(26, Endian.little);
  final extraLength = data.getUint16(28, Endian.little);
  final dataOffset = cursor + 30 + nameLength + extraLength;
  if (dataOffset > length) {
    return null; // Torn inside the header's own name/extra.
  }
  final name = String.fromCharCodes(readAt(cursor + 30, nameLength));
  if (compressedSize == _zip32Max) {
    // An entry past [anicelZip64FieldLimit]: the truth lives in the local
    // ZIP64 extra (both sizes, per spec). A flagged size with no extra is
    // not a shape any writer of this format makes — unparseable like any
    // other.
    final size = _localZip64CompressedSize(
      readAt(cursor + 30 + nameLength, extraLength),
    );
    if (size == null) {
      return null;
    }
    compressedSize = size;
  }
  if (dataOffset + compressedSize > length) {
    return null; // Torn: its data never fully landed.
  }
  return AnicelZipEntry(
    name: name,
    localHeaderOffset: cursor,
    dataOffset: dataOffset,
    length: compressedSize,
    crc32: crc,
  );
}

/// Whether [entry]'s bytes still checksum to what its header recorded,
/// read in chunks so a gigabyte of media never sits in memory at once.
bool _crcHolds(_ReadAt readAt, AnicelZipEntry entry) {
  var running = anicelCrc32Start;
  var done = 0;
  while (done < entry.length) {
    final left = entry.length - done;
    final chunk = readAt(
      entry.dataOffset + done,
      left < _streamChunkBytes ? left : _streamChunkBytes,
    );
    if (chunk.isEmpty) {
      return false;
    }
    running = anicelCrc32Update(running, chunk);
    done += chunk.length;
  }
  return anicelCrc32Finish(running) == entry.crc32;
}

/// The last resort (R24-D1, from before directories were kept whole):
/// LOCAL headers walked from the front. Same-name entries resolve
/// last-wins (the shadowing rule the central directory encodes), a torn
/// final entry is dropped, and the LAST complete entry is CRC-verified
/// (the only one a torn write can have half-filled; verifying every entry
/// would read whole gigabytes). Entries deleted by removeNames may
/// resurrect (their old locals still exist) — for crash recovery, too much
/// beats lost.
///
/// ⚠️It trusts file ORDER to say which copy is newest, and a stale copy
/// left in a gap the push-down could not fill breaks that — so it runs
/// only when no directory is whole.
///
/// The returned centralDirectoryOffset is the end of the last complete
/// entry.
AnicelZipLayout _walkFromTheFront(_ReadAt readAt, int length) {
  final byName = <String, AnicelZipEntry>{};
  final order = <String>[];
  var cursor = 0;
  var lastCompleteEnd = 0;
  String? lastName;
  AnicelZipEntry? shadowedByLast;
  while (true) {
    final entry = _localEntryAt(readAt, cursor, length);
    if (entry == null) {
      break;
    }
    if (!byName.containsKey(entry.name)) {
      order.add(entry.name);
    }
    shadowedByLast = byName[entry.name];
    byName[entry.name] = entry;
    lastName = entry.name;
    lastCompleteEnd = entry.dataOffset + entry.length;
    cursor = lastCompleteEnd;
  }
  // The last complete entry is the only one a torn write can have
  // corrupted content-wise; verify it and drop on mismatch.
  if (lastName != null) {
    final last = byName[lastName]!;
    if (!_crcHolds(readAt, last)) {
      // Corrupt final entry: its earlier shadowed version (if any) wins
      // again, exactly as if the torn append never happened.
      if (shadowedByLast != null) {
        byName[lastName] = shadowedByLast;
      } else {
        byName.remove(lastName);
        order.remove(lastName);
      }
      lastCompleteEnd = last.localHeaderOffset;
    }
  }
  return AnicelZipLayout(
    entries: [for (final name in order) byName[name]!],
    centralDirectoryOffset: lastCompleteEnd,
  );
}

/// CRC-32 (ZIP polynomial), table-driven.
final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i += 1) {
    var c = i;
    for (var k = 0; k < 8; k += 1) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[i] = c;
  }
  return table;
}

int anicelCrc32(Uint8List bytes) =>
    anicelCrc32Finish(anicelCrc32Update(anicelCrc32Start, bytes));

/// The running value a chunked CRC starts from.
///
/// Split out so a source too big to hold can still be checksummed: ZIP
/// wants the CRC in the local header, which is written BEFORE the data,
/// so a streamed entry passes over its bytes twice — once to fold them
/// into this, once to copy them. Two reads of a warm file beat one
/// allocation the size of the file, which is what a gigabyte of audio
/// would otherwise cost on the device least able to afford it.
const int anicelCrc32Start = 0xFFFFFFFF;

/// How much of a streamed entry is held at once. One buffer, reused, so
/// appending a gigabyte of audio costs this much memory and not a
/// gigabyte.
const int _streamChunkBytes = 256 * 1024;

/// How many times [appendAnicelEntries] reads each streamed entry end to
/// end: once to checksum it before the file is touched, once to copy the
/// bytes in.
///
/// 🚨 Declared because it is not a private detail — anything measuring the
/// work of a save has to know, and the one thing that did got it wrong.
/// Counting an append's media as a single traversal made a progress bar
/// reach 100% at the end of the CRC pass, before a byte was written, and
/// then hold there through the entire copy. The number of passes is a fact
/// about this function; a caller cannot infer it, so this states it.
const int anicelAppendStreamPasses = 2;

/// The same count for [writeAnicelArchiveFile], which is ONE: it writes a
/// placeholder CRC ahead of the data and seeks back to patch it, so the
/// bytes go past exactly once. ⚠️ Deliberately a separate constant — the
/// two writers differ here, and a single shared number would be wrong for
/// one of them.
const int anicelArchiveStreamPasses = 1;

/// Folds [chunk] into a running CRC. Only the first [length] bytes count,
/// so a caller reusing one buffer for a short final read does not have to
/// trim it first.
int anicelCrc32Update(int running, Uint8List chunk, [int? length]) {
  var c = running;
  final end = length ?? chunk.length;
  for (var i = 0; i < end; i += 1) {
    c = _crcTable[(c ^ chunk[i]) & 0xFF] ^ (c >> 8);
  }
  return c;
}

/// Turns a running CRC into the value ZIP records.
int anicelCrc32Finish(int running) => (running ^ 0xFFFFFFFF) & 0xFFFFFFFF;

/// One entry appended by streaming rather than by handing over bytes.
///
/// 🚨 The reason it exists: [appendAnicelEntries] takes a `Uint8List` per
/// entry, which is right for a cel — small, and already compressed in hand —
/// and wrong for media. A two-hundred-megabyte import would put two
/// hundred megabytes on the heap to append it, which is the cost this
/// round already took out of the full-save path and would otherwise walk
/// straight back in through the incremental one.
class AnicelStreamedEntry {
  const AnicelStreamedEntry({
    required this.name,
    required this.length,
    required this.readInto,
  });

  final String name;

  /// Known up front, because a ZIP local header states it before the data
  /// and this writer does not use data descriptors.
  final int length;

  /// Fills [buffer] from [position], answering how many bytes landed —
  /// `MediaByteSource.readIntoSync`'s shape, so a source can be passed
  /// straight in.
  final int Function(Uint8List buffer, int position, int size) readInto;
}

/// Reads [entry] to its end in chunks, handing every one to [onChunk].
///
/// ⛔THREE PLACES STREAM AN ENTRY and they must read it the same way: the
/// append checksums before the file is touched, the append's write pass
/// only writes (the CRC is already known), and the full write does both
/// at once. One buffer, reused, whatever the asset weighs — and a source
/// that ends early is a [StateError] naming how far it got, not a silent
/// short file.
void _readStreamedEntry(
  AnicelStreamedEntry entry,
  void Function(Uint8List buffer, int read) onChunk,
) {
  final buffer = Uint8List(_streamChunkBytes);
  var position = 0;
  while (position < entry.length) {
    final wanted = entry.length - position;
    final read = entry.readInto(
      buffer,
      position,
      wanted < buffer.length ? wanted : buffer.length,
    );
    if (read <= 0) {
      throw StateError(
        'media entry "${entry.name}" ended after $position of '
        '${entry.length} bytes',
      );
    }
    onChunk(buffer, read);
    position += read;
  }
}

/// [entry]'s CRC-32, with every chunk handed to [onChunk] on the way past.
///
/// ⛔THE CRC UPDATES BEFORE THE CHUNK GOES OUT. The full write patches the
/// header from this afterwards, so a writer that emitted first and
/// checksummed later would still be correct — but only by accident, and
/// the append relies on the order to checksum WITHOUT writing at all.
int _streamedEntryCrc(
  AnicelStreamedEntry entry, {
  void Function(Uint8List buffer, int read)? onChunk,
}) {
  var running = anicelCrc32Start;
  _readStreamedEntry(entry, (buffer, read) {
    running = anicelCrc32Update(running, buffer, read);
    onChunk?.call(buffer, read);
  });
  return anicelCrc32Finish(running);
}

/// Where a ref's bytes went, keyed elsewhere by the DATA offset they were
/// at — what a session applies to every cel ref it holds into the file
/// (`BrushFrameStore.relocateFileRefs`).
typedef AnicelRelocation = ({int dataOffset, int length});

/// One live entry as a piece of the file: its local header and the data
/// behind it, which move together or not at all.
typedef AnicelLiveSpan = ({int offset, int size});

/// One copy of the push-down, front to back.
typedef AnicelCompactionMove = ({int from, int to, int size});

/// Who reads the file while [compactAnicelInPlace] moves bytes under it,
/// and how each is kept from reading what moved in.
///
/// 🚨★★★[move] RUNS BETWEEN A ROUND'S COMMIT AND THE NEXT ROUND'S FIRST
/// WRITE, AND IS AWAITED. The session reads cels straight out of this file
/// by offset while the save runs in another isolate, so bytes a round has
/// moved away from are garbage only once no ref points at them any more.
/// [move] is handed every move of the round (old data offset → new) and
/// must not complete until the refs have moved.
///
/// 🚨[holding] names what CANNOT move with its bytes: an entry a reader
/// holds a document open on, which it reads by offset frame after frame
/// (the viewer's carried movie). Those entries stay where they are
/// ([planAnicelPushDown]'s `staying`).
typedef AnicelReaders = ({
  Future<void> Function(Map<int, AnicelRelocation> moved) move,
  Set<String> holding,
});

/// Appends [newEntries] ({name: raw bytes, STORE'd}) and [streamedEntries]
/// to the .anicel at [path], IN PLACE: the new locals and a fresh central
/// directory (old actives minus shadowed names minus [removeNames], plus
/// the new entries) + EOCD go after the committed directory. [removeNames]
/// deletes entries outright (a cel that became empty or moved away) —
/// their bytes go dead like any shadowed entry, for [compactAnicelInPlace]
/// to take back. Returns the resulting layout.
///
/// 🚨★★★THIS IS THE 떼기 커밋 (deleting-save-compacts-Q1, 유저 2026-09-23:
/// 「떼기 커밋 → 구멍 뒤 살아 있는 바이트를 구멍으로 → 꼬리 자르기」). It
/// writes over NOTHING: the old directory stays whole behind the new
/// entries until the new directory has landed after them, so a crash
/// anywhere in here opens as the file before this save. From then on the
/// old directory is dead bytes like any shadowed entry.
AnicelZipLayout appendAnicelEntries({
  required String path,
  required Map<String, Uint8List> newEntries,
  Set<String> removeNames = const {},
  List<AnicelStreamedEntry> streamedEntries = const [],
}) {
  final file = File(path);
  // Tail-only parse: the append must not scale with file size. ⚠️Strict —
  // it refuses a file whose directory is not its last byte (a save that
  // did not finish), and the caller's answer to that is the whole write.
  final layout = parseAnicelZipLayoutFile(path);
  final committedEnd = file.lengthSync();

  final streamedNames = {for (final entry in streamedEntries) entry.name};
  final survivors = [
    for (final entry in layout.entries)
      if (!newEntries.containsKey(entry.name) &&
          !streamedNames.contains(entry.name) &&
          !removeNames.contains(entry.name))
        entry,
  ];

  final builder = BytesBuilder(copy: false);
  final appended = <AnicelZipEntry>[];
  var writeOffset = committedEnd;

  for (final entry in newEntries.entries) {
    final crc = anicelCrc32(entry.value);
    final header = _localHeaderBytes(entry.key, entry.value.length, crc);
    appended.add(
      AnicelZipEntry(
        name: entry.key,
        localHeaderOffset: writeOffset,
        dataOffset: writeOffset + header.length,
        length: entry.value.length,
        crc32: crc,
      ),
    );
    builder
      ..add(header)
      ..add(entry.value);
    writeOffset += header.length + entry.value.length;
  }

  // Streamed entries are checksummed BEFORE the file is touched. Their
  // headers state a CRC, and a source that turns out to be unreadable
  // must not have already written into the archive to find that out.
  final streamedCrcs = <int>[];
  for (final entry in streamedEntries) {
    streamedCrcs.add(_streamedEntryCrc(entry));
  }

  var streamOffset = writeOffset;
  for (var i = 0; i < streamedEntries.length; i += 1) {
    final entry = streamedEntries[i];
    final header = _localHeaderBytes(entry.name, entry.length, streamedCrcs[i]);
    appended.add(
      AnicelZipEntry(
        name: entry.name,
        localHeaderOffset: streamOffset,
        dataOffset: streamOffset + header.length,
        length: entry.length,
        crc32: streamedCrcs[i],
      ),
    );
    streamOffset += header.length + entry.length;
  }

  // Central directory over survivors + appended.
  final centralOffset = streamOffset;
  final all = [...survivors, ...appended];

  // One sequential write after the committed end: locals + streamed
  // locals + central + EOCD.
  final raf = file.openSync(mode: FileMode.append);
  try {
    raf.setPositionSync(committedEnd);
    _write(raf, builder.takeBytes());
    for (var i = 0; i < streamedEntries.length; i += 1) {
      final entry = streamedEntries[i];
      _write(raf, _localHeaderBytes(entry.name, entry.length, streamedCrcs[i]));
      _readStreamedEntry(
        entry,
        (buffer, read) => _write(raf, buffer, 0, read),
      );
    }
    _write(raf, _directoryBytes(all, centralOffset: centralOffset));
    _durable(raf);
  } finally {
    raf.closeSync();
  }

  return AnicelZipLayout(entries: all, centralDirectoryOffset: centralOffset);
}

/// The push-down, planned whole: every live span slides down into the dead
/// bytes in front of it, in file order — which spans move where, and where
/// the live bytes end once they have.
///
/// 🗣️유저 2026-09-23 (deleting-save-compacts-Q1) chose 「한 번에 밀어
/// 내리기」 over the per-save budget (「점진 — 저장마다 예산(16MB)만큼」), so
/// there is no budget: the save that compacts packs everything it can. The
/// bound is the one the user named — 「지금의 전체저장보다는
/// 안늘어날거아냐」: it copies the live bytes behind the first hole, never
/// more than the whole write copied.
///
/// ⚠️A span whose hole in front is SMALLER than itself stays where it is.
/// Its new home would overlap its old one, and the crash contract forbids
/// writing over bytes the committed directory names — its own included.
/// The hole in front of it stays dead; what comes after packs against it.
///
/// 🚨A span that starts at one of [staying] stays where it is too, however
/// big the hole in front of it: something is reading it by OFFSET right now
/// (`ProjectFile.holdMediaBytes` — a carried movie the viewer decodes frame
/// after frame, a carried PDF it reads a page at a time, from where the
/// save found them). Moving it would hand
/// that reader whatever the next round wrote there. Its hole waits for the
/// first save after the reader lets go — deferred, not given up.
({List<AnicelCompactionMove> moves, int end}) planAnicelPushDown(
  List<AnicelLiveSpan> live, {
  Set<int> staying = const {},
}) {
  final sorted = [...live]..sort((a, b) => a.offset.compareTo(b.offset));
  final moves = <AnicelCompactionMove>[];
  var cursor = 0;
  for (final span in sorted) {
    if (!staying.contains(span.offset) &&
        span.offset > cursor &&
        cursor + span.size <= span.offset) {
      moves.add((from: span.offset, to: cursor, size: span.size));
      cursor += span.size;
    } else {
      cursor = span.offset + span.size;
    }
  }
  return (moves: moves, end: cursor);
}

/// [moves] cut into rounds, each ending where the next move would land on
/// bytes a move of the SAME round is leaving: the committed directory still
/// names those until the round's own directory lands, so that move waits.
///
/// Rounds grow as the push-down climbs — each directory frees what the
/// round before it vacated — so garbage spread evenly through a file takes
/// on the order of log(entries) rounds, and one big hole takes one.
List<List<AnicelCompactionMove>> anicelCompactionRounds(
  List<AnicelCompactionMove> moves,
) {
  final rounds = <List<AnicelCompactionMove>>[];
  var round = <AnicelCompactionMove>[];
  // The first move of [round] whose vacated bytes end after the current
  // destination starts. Destinations only climb, so it only advances.
  var watch = 0;
  for (final move in moves) {
    while (watch < round.length &&
        round[watch].from + round[watch].size <= move.to) {
      watch += 1;
    }
    if (watch < round.length && round[watch].from < move.to + move.size) {
      rounds.add(round);
      round = [];
      watch = 0;
    }
    round.add(move);
  }
  if (round.isNotEmpty) {
    rounds.add(round);
  }
  return rounds;
}

/// The rest of the save the user chose: the live bytes behind each hole
/// slide down into it, and the dead tail is cut off (deleting-save-
/// compacts-Q1). In place — no temp file, and nothing replaced.
///
/// [layout] is the directory just committed ([appendAnicelEntries]'s
/// result). The push-down ([planAnicelPushDown]) runs in rounds
/// ([anicelCompactionRounds]); each round copies, then commits a directory
/// naming where its entries went, appended at the end — only after that
/// may the next round write over the bytes they left. Last, the directory
/// moves down to where the live bytes end and the file is cut behind it.
///
/// The crash contract keeps the file safe from the save; [readers] keeps
/// the session safe from it ([AnicelReaders]).
///
/// [onProgress] hears the fraction of the moving bytes copied so far.
Future<AnicelZipLayout> compactAnicelInPlace({
  required String path,
  required AnicelZipLayout layout,
  required AnicelReaders readers,
  void Function(double fraction)? onProgress,
}) async {
  final plan = _pushDownOf(layout, holding: readers.holding);
  final total = plan.moves.fold<int>(0, (sum, move) => sum + move.size);
  var copied = 0;
  var entries = layout.entries;
  var committedDirectory = layout.centralDirectoryOffset;
  final raf = File(path).openSync(mode: FileMode.append);
  try {
    final buffer = Uint8List(_streamChunkBytes);
    for (final round in anicelCompactionRounds(plan.moves)) {
      for (final move in round) {
        _copyDown(raf, move, buffer);
        copied += move.size;
        onProgress?.call(copied / total);
      }
      _durable(raf);
      final movedTo = {for (final move in round) move.from: move.to};
      final moved = <int, AnicelRelocation>{};
      entries = [
        for (final entry in entries)
          if (movedTo[entry.localHeaderOffset] case final to?)
            _landedAt(entry, to, moved)
          else
            entry,
      ];
      committedDirectory = _commitDirectoryAtTheEnd(raf, entries);
      await readers.move(moved);
    }

    // The cut: the directory comes down to where the live bytes end, and
    // everything behind it goes.
    final directory = _directoryBytes(entries, centralOffset: plan.end);
    if (plan.end < committedDirectory) {
      if (plan.end + directory.length > committedDirectory) {
        // Its new home reaches into the committed directory itself — commit
        // once more at the end first, so the one written over is no longer
        // the newest.
        committedDirectory = _commitDirectoryAtTheEnd(raf, entries);
      }
      raf.setPositionSync(plan.end);
      _write(raf, directory);
      _durable(raf);
      _truncate(raf, plan.end + directory.length);
      _durable(raf);
      committedDirectory = plan.end;
    }
  } finally {
    raf.closeSync();
  }
  return AnicelZipLayout(
    entries: entries,
    centralDirectoryOffset: committedDirectory,
  );
}

/// The push-down of [layout]'s entries, each span its local header and
/// data — the entries in [holding] where they are.
({List<AnicelCompactionMove> moves, int end}) _pushDownOf(
  AnicelZipLayout layout, {
  required Set<String> holding,
}) => planAnicelPushDown(
  [
    for (final entry in layout.entries)
      (
        offset: entry.localHeaderOffset,
        size: entry.dataOffset - entry.localHeaderOffset + entry.length,
      ),
  ],
  staying: {
    for (final entry in layout.entries)
      if (holding.contains(entry.name)) entry.localHeaderOffset,
  },
);

/// [entry] as it reads once its span has moved to [to]; the move is noted
/// in [moved] for the refs that still point at the old bytes.
AnicelZipEntry _landedAt(
  AnicelZipEntry entry,
  int to,
  Map<int, AnicelRelocation> moved,
) {
  final dataOffset = to + (entry.dataOffset - entry.localHeaderOffset);
  moved[entry.dataOffset] = (dataOffset: dataOffset, length: entry.length);
  return AnicelZipEntry(
    name: entry.name,
    localHeaderOffset: to,
    dataOffset: dataOffset,
    length: entry.length,
    crc32: entry.crc32,
  );
}

/// Copies [move] front to back through [buffer]. The destination always
/// lies wholly in front of the source ([planAnicelPushDown] leaves a span
/// whose home would overlap it where it is), so the copy never reads a
/// byte it has written.
void _copyDown(
  RandomAccessFile raf,
  AnicelCompactionMove move,
  Uint8List buffer,
) {
  var done = 0;
  while (done < move.size) {
    final left = move.size - done;
    raf.setPositionSync(move.from + done);
    final read = raf.readIntoSync(
      buffer,
      0,
      left < buffer.length ? left : buffer.length,
    );
    if (read <= 0) {
      throw FileSystemException(
        'a live entry ended early while being moved',
        raf.path,
      );
    }
    raf.setPositionSync(move.to + done);
    _write(raf, buffer, 0, read);
    done += read;
  }
}

/// A round's commit: a directory over [entries] written at the end of the
/// file and made durable. Answers where it starts.
int _commitDirectoryAtTheEnd(
  RandomAccessFile raf,
  List<AnicelZipEntry> entries,
) {
  final at = raf.lengthSync();
  raf.setPositionSync(at);
  _write(raf, _directoryBytes(entries, centralOffset: at));
  _durable(raf);
  return at;
}

/// A durability barrier: what was written before it reaches the disk before
/// anything written after it can. The phases of a save lean on that order —
/// a directory must not land ahead of the copies it names, nor a copy ahead
/// of the directory that let go of its bytes.
void _durable(RandomAccessFile raf) => raf.flushSync();

/// A central directory over [entries] and the records that close it, as it
/// reads starting at [centralOffset].
Uint8List _directoryBytes(
  List<AnicelZipEntry> entries, {
  required int centralOffset,
}) {
  final central = _centralDirectoryBytes(entries);
  return (BytesBuilder(copy: false)
        ..add(central)
        ..add(
          _eocdBytes(
            entryCount: entries.length,
            centralLength: central.length,
            centralOffset: centralOffset,
          ),
        ))
      .takeBytes();
}

/// 🧪Hears every change a save makes to the project file, in the order it
/// makes them.
///
/// The crash tests replay a prefix of this onto the file as it was before
/// the save — exactly what a process that died at that byte leaves behind:
/// writes land in order, and a truncation is all or nothing.
@visibleForTesting
abstract interface class AnicelWriteWatcher {
  /// [bytes] were written starting at [at].
  void wrote(int at, List<int> bytes);

  /// The file was cut to [length].
  void cut(int length);
}

/// Null in production.
@visibleForTesting
AnicelWriteWatcher? anicelDebugWriteWatcher;

/// Every write a save makes into the project file goes through here, so
/// the crash tests hear every one of them.
void _write(
  RandomAccessFile raf,
  List<int> bytes, [
  int start = 0,
  int? end,
]) {
  final stop = end ?? bytes.length;
  anicelDebugWriteWatcher?.wrote(
    raf.positionSync(),
    bytes.sublist(start, stop),
  );
  raf.writeFromSync(bytes, start, stop);
}

/// [RandomAccessFile.truncateSync], heard like [_write].
void _truncate(RandomAccessFile raf, int length) {
  anicelDebugWriteWatcher?.cut(length);
  raf.truncateSync(length);
}

/// Writes a COMPLETE .anicel to [path], one entry at a time.
///
/// The full-save counterpart of [appendAnicelEntries], and it exists for
/// memory rather than speed: building the archive as one `Uint8List` and
/// handing it back from the save isolate held the whole project twice —
/// once built, once copied across the port — before a byte reached the
/// disk. On a tablet that is the allocation the OS kills the app over, and
/// the save most likely to be running is the one that fires as the app
/// goes to the background.
///
/// [entries] is pulled LAZILY, so a caller that resolves each cel as it is
/// asked for keeps exactly one cel resident. Every entry is STORE'd — cel
/// blobs carry their own compression — so a length is known before its bytes
/// are written and nothing needs a second pass.
AnicelZipLayout writeAnicelArchiveFile({
  required String path,
  required Iterable<({String name, Uint8List bytes})> entries,
  Iterable<AnicelStreamedEntry> streamedEntries = const [],
}) {
  final written = <AnicelZipEntry>[];
  var offset = 0;
  final raf = File(path).openSync(mode: FileMode.write);
  try {
    for (final entry in entries) {
      final crc = anicelCrc32(entry.bytes);
      final header = _localHeaderBytes(entry.name, entry.bytes.length, crc);
      raf.writeFromSync(header);
      raf.writeFromSync(entry.bytes);
      written.add(
        AnicelZipEntry(
          name: entry.name,
          localHeaderOffset: offset,
          dataOffset: offset + header.length,
          length: entry.bytes.length,
          crc32: crc,
        ),
      );
      offset += header.length + entry.bytes.length;
    }
    // Media last, and streamed. A cel resolves to a small blob that is
    // already compressed, so holding one at a time costs nothing; an
    // imported sound can weigh more than the rest of the project put
    // together, and this path is what a backgrounding tablet runs with the
    // least headroom to spare.
    //
    // Unlike the append, this writes into a TEMP file nobody has yet — so
    // a short source can fail mid-write without endangering anything, and
    // the checksum rides along with the copy instead of costing a second
    // pass over every asset on every full save.
    for (final entry in streamedEntries) {
      final headerOffset = offset;
      // Placeholder header: the CRC is not known until the bytes have
      // gone by, and a full rewrite can afford to seek back four bytes
      // where a sequential append could not.
      final placeholder = _localHeaderBytes(entry.name, entry.length, 0);
      raf.writeFromSync(placeholder);
      offset += placeholder.length;

      final crc = _streamedEntryCrc(
        entry,
        onChunk: (buffer, read) => raf.writeFromSync(buffer, 0, read),
      );
      final resume = raf.positionSync();
      raf.setPositionSync(headerOffset + 14);
      raf.writeFromSync(_uint32(crc));
      raf.setPositionSync(resume);

      written.add(
        AnicelZipEntry(
          name: entry.name,
          localHeaderOffset: headerOffset,
          dataOffset: headerOffset + placeholder.length,
          length: entry.length,
          crc32: crc,
        ),
      );
      offset += entry.length;
    }
    final centralBytes = _centralDirectoryBytes(written);
    raf.writeFromSync(centralBytes);
    raf.writeFromSync(
      _eocdBytes(
        entryCount: written.length,
        centralLength: centralBytes.length,
        centralOffset: offset,
      ),
    );
    raf.flushSync();
  } finally {
    raf.closeSync();
  }
  return AnicelZipLayout(entries: written, centralDirectoryOffset: offset);
}

/// A STORE'd local file header + its name. [length] is both sizes: no
/// compression happens at the ZIP layer.
/// Four little-endian bytes — what a seek-back patch of a header field
/// writes. The offset it goes to (14) is the CRC's, per the layout in
/// [_localHeaderBytes] directly below.
Uint8List _uint32(int value) {
  final out = ByteData(4)..setUint32(0, value, Endian.little);
  return out.buffer.asUint8List();
}

Uint8List _localHeaderBytes(String name, int length, int crc) {
  final nameBytes = Uint8List.fromList(name.codeUnits);
  final size64 = length >= anicelZip64FieldLimit;
  // The spec requires a local header's ZIP64 extra to carry BOTH sizes
  // whenever either fixed field is flagged — unlike the central record,
  // where only the flagged fields appear.
  final extra = size64 ? ByteData(20) : null;
  if (extra != null) {
    extra.setUint16(0, _zip64ExtraId, Endian.little);
    extra.setUint16(2, 16, Endian.little); // payload size
    extra.setUint64(4, length, Endian.little); // uncompressed
    extra.setUint64(12, length, Endian.little); // compressed (STORE)
  }
  final header = ByteData(30);
  header.setUint32(0, _localSignature, Endian.little);
  header.setUint16(4, size64 ? 45 : 20, Endian.little); // version needed
  header.setUint16(6, 0, Endian.little); // flags
  header.setUint16(8, 0, Endian.little); // method 0 = STORE
  header.setUint32(10, 0, Endian.little); // dos time/date
  header.setUint32(14, crc, Endian.little);
  header.setUint32(18, size64 ? _zip32Max : length, Endian.little);
  header.setUint32(22, size64 ? _zip32Max : length, Endian.little);
  header.setUint16(26, nameBytes.length, Endian.little);
  header.setUint16(28, extra?.lengthInBytes ?? 0, Endian.little);
  final out = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(nameBytes);
  if (extra != null) {
    out.add(extra.buffer.asUint8List());
  }
  return out.takeBytes();
}

Uint8List _centralDirectoryBytes(List<AnicelZipEntry> entries) {
  final central = BytesBuilder(copy: false);
  for (final entry in entries) {
    final nameBytes = Uint8List.fromList(entry.name.codeUnits);
    // This used to REFUSE an entry past 4GB ("the writer does not emit
    // ZIP64 sizes") — 유저 08-26 (Q-save-4gb-carry): the format stretches
    // instead, see [anicelZip64FieldLimit]. The sentinel law still holds:
    // a silently truncated size would be a file that opens and reads the
    // wrong bytes, so an oversize field moves WHOLE into the extra.
    final size64 = entry.length >= anicelZip64FieldLimit;
    final offset64 = entry.localHeaderOffset >= anicelZip64FieldLimit;
    // ZIP64 Extended Information: only the fields that read 0xFFFFFFFF
    // in the fixed record appear, in the spec's order — uncompressed
    // size, compressed size, local header offset.
    final payload = (size64 ? 16 : 0) + (offset64 ? 8 : 0);
    final extra = payload > 0 ? ByteData(4 + payload) : null;
    if (extra != null) {
      extra.setUint16(0, _zip64ExtraId, Endian.little);
      extra.setUint16(2, payload, Endian.little);
      var at = 4;
      if (size64) {
        extra.setUint64(at, entry.length, Endian.little); // uncompressed
        extra.setUint64(at + 8, entry.length, Endian.little); // compressed
        at += 16;
      }
      if (offset64) {
        extra.setUint64(at, entry.localHeaderOffset, Endian.little);
      }
    }
    final record = ByteData(46);
    record.setUint32(0, _centralSignature, Endian.little);
    record.setUint16(4, 20, Endian.little); // version made by
    record.setUint16(6, size64 || offset64 ? 45 : 20, Endian.little);
    record.setUint16(8, 0, Endian.little);
    record.setUint16(10, 0, Endian.little); // method STORE
    record.setUint32(12, 0, Endian.little); // time/date
    record.setUint32(16, entry.crc32, Endian.little);
    record.setUint32(20, size64 ? _zip32Max : entry.length, Endian.little);
    record.setUint32(24, size64 ? _zip32Max : entry.length, Endian.little);
    record.setUint16(28, nameBytes.length, Endian.little);
    record.setUint16(30, extra?.lengthInBytes ?? 0, Endian.little);
    record.setUint32(
      42,
      offset64 ? _zip32Max : entry.localHeaderOffset,
      Endian.little,
    );
    central
      ..add(record.buffer.asUint8List())
      ..add(nameBytes);
    if (extra != null) {
      central.add(extra.buffer.asUint8List());
    }
  }
  return central.takeBytes();
}

/// The end of the archive: a ZIP64 record + locator when the plain one
/// cannot say the truth, then always the plain EOCD.
///
/// 🚨 The plain EOCD's fields are 16 and 32 bits, and `ByteData.setUint16`
/// TRUNCATES rather than throwing — so before this existed, entry 65,536
/// wrote a count of 0 and the reader opened the project with nothing in
/// it. Silent, and at 1500 cuts (this app's stated target, one entry per
/// cel) it is reachable rather than theoretical.
///
/// Written only when needed, so every archive that fits in plain ZIP is
/// byte-identical to what this wrote before — the widest reader support,
/// and no churn in the fixtures.
Uint8List _eocdBytes({
  required int entryCount,
  required int centralLength,
  required int centralOffset,
}) {
  final needs64 =
      anicelAlwaysZip64 ||
      entryCount > _zip16Max ||
      centralOffset > _zip32Max ||
      centralLength > _zip32Max;
  // 🔑 A sentinel goes in a field only when the TRUTH does not fit there,
  // never merely because a ZIP64 record exists. That is what the spec
  // says, and it buys something concrete: an archive that carries ZIP64
  // records but whose values all fit is still readable by a reader that
  // has never heard of ZIP64 — it reads the real count at the real
  // offset and never looks at the extra records sitting behind it.
  //
  // Which is why flipping `anicelAlwaysZip64` is cheaper than it looks:
  // the older builds only lose the files that genuinely overflow, and
  // those they could not have opened under any writer.
  final countField = entryCount > _zip16Max ? _zip16Max : entryCount;
  final eocd = ByteData(22);
  eocd.setUint32(0, _eocdSignature, Endian.little);
  eocd.setUint16(8, countField, Endian.little);
  eocd.setUint16(10, countField, Endian.little);
  eocd.setUint32(
    12,
    centralLength > _zip32Max ? _zip32Max : centralLength,
    Endian.little,
  );
  eocd.setUint32(
    16,
    centralOffset > _zip32Max ? _zip32Max : centralOffset,
    Endian.little,
  );
  if (!needs64) {
    return eocd.buffer.asUint8List();
  }
  final zip64End = ByteData(56);
  zip64End.setUint32(0, _zip64EndSignature, Endian.little);
  // Size of this record MINUS the 12 bytes up to and including this field.
  zip64End.setUint64(4, 44, Endian.little);
  zip64End.setUint16(12, 45, Endian.little); // version made by
  zip64End.setUint16(14, 45, Endian.little); // version needed
  zip64End.setUint32(16, 0, Endian.little); // this disk
  zip64End.setUint32(20, 0, Endian.little); // disk with central directory
  zip64End.setUint64(24, entryCount, Endian.little);
  zip64End.setUint64(32, entryCount, Endian.little);
  zip64End.setUint64(40, centralLength, Endian.little);
  zip64End.setUint64(48, centralOffset, Endian.little);

  final locator = ByteData(20);
  locator.setUint32(0, _zip64LocatorSignature, Endian.little);
  locator.setUint32(4, 0, Endian.little); // disk with the ZIP64 EOCD
  locator.setUint64(8, centralOffset + centralLength, Endian.little);
  locator.setUint32(16, 1, Endian.little); // total disks

  return (BytesBuilder(copy: false)
        ..add(zip64End.buffer.asUint8List())
        ..add(locator.buffer.asUint8List())
        ..add(eocd.buffer.asUint8List()))
      .takeBytes();
}
