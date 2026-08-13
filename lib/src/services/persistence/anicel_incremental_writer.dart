/// Incremental .anicel appender (R22-C): the container is ordinary ZIP with
/// every entry STORE'd (cel blobs carry their own deflate), which makes
/// appends trivial and spec-legal — new local entries write over the old
/// central directory's position, then a fresh central directory + EOCD
/// close the file. Standard readers (including our own
/// `parseAnicelArchiveBytes`) see only the LATEST central directory, so a
/// re-saved `project.json` or a superseded cel simply shadows its old
/// bytes (garbage until compaction rewrites the file whole).
///
/// Crash contract: the central-directory rewrite is the only destructive
/// step. `appendAnicelEntries` first reads the old central directory into
/// memory; a crash mid-append leaves a file without a valid EOCD tail —
/// the caller keeps compaction (full atomic rewrite) as the recovery and
/// the periodic durability point.
library;

import 'dart:io';
import 'dart:typed_data';

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
  AnicelZipLayout({required this.entries, required this.centralDirectoryOffset});

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
bool anicelAlwaysZip64 = true;

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
    throw const FormatException('ZIP64 end record not found where the '
        'locator points.');
  }
  return (
    entryCount: tail.getUint64(index + 32, Endian.little),
    centralOffset: tail.getUint64(index + 48, Endian.little),
    centralLength: tail.getUint64(index + 40, Endian.little),
  );
}

/// The local header offset a central record names, following its ZIP64
/// extra field when the fixed field is all-ones.
int _centralLocalOffset(ByteData data, int cursor, int extraStart,
    int extraLength) {
  final fixed = data.getUint32(cursor + 42, Endian.little);
  if (fixed != _zip32Max) {
    return fixed;
  }
  // Walk the extra fields for id 0x0001. The 64-bit values inside appear
  // in a FIXED order — uncompressed size, compressed size, local header
  // offset — and only for the fields that were all-ones. This writer only
  // ever flags the offset, but a file from another tool may flag sizes
  // too, so the sizes are skipped by looking at what is flagged.
  var walk = extraStart;
  final end = extraStart + extraLength;
  while (walk + 4 <= end) {
    final id = data.getUint16(walk, Endian.little);
    final size = data.getUint16(walk + 2, Endian.little);
    if (id == _zip64ExtraId) {
      var at = walk + 4;
      if (data.getUint32(cursor + 24, Endian.little) == _zip32Max) {
        at += 8; // uncompressed size
      }
      if (data.getUint32(cursor + 20, Endian.little) == _zip32Max) {
        at += 8; // compressed size
      }
      if (at + 8 <= end) {
        return data.getUint64(at, Endian.little);
      }
      break;
    }
    walk += 4 + size;
  }
  throw const FormatException('Central record flags a ZIP64 offset with '
      'no extra field to hold it.');
}

/// Parses the central directory of [bytes] (a complete .anicel). Throws
/// [FormatException] when no EOCD is found (torn append — the caller
/// falls back to recovery/compaction).
AnicelZipLayout parseAnicelZipLayout(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  // EOCD: scan back over a possible comment (max 64KB + 22).
  final scanFloor = bytes.length - 22 - 65535 < 0
      ? 0
      : bytes.length - 22 - 65535;
  var eocd = -1;
  for (var i = bytes.length - 22; i >= scanFloor; i -= 1) {
    if (data.getUint32(i, Endian.little) == _eocdSignature) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) {
    throw const FormatException('No ZIP end-of-central-directory found.');
  }
  final zip64 = _readZip64End(data, eocd, tailStart: 0);
  final entryCount = zip64?.entryCount ?? data.getUint16(eocd + 10, Endian.little);
  final centralOffset =
      zip64?.centralOffset ?? data.getUint32(eocd + 16, Endian.little);

  final entries = <AnicelZipEntry>[];
  var cursor = centralOffset;
  for (var i = 0; i < entryCount; i += 1) {
    if (data.getUint32(cursor, Endian.little) != _centralSignature) {
      throw const FormatException('Corrupt central directory.');
    }
    final crc = data.getUint32(cursor + 16, Endian.little);
    final compressedSize = data.getUint32(cursor + 20, Endian.little);
    final nameLength = data.getUint16(cursor + 28, Endian.little);
    final extraLength = data.getUint16(cursor + 30, Endian.little);
    final commentLength = data.getUint16(cursor + 32, Endian.little);
    final localOffset = _centralLocalOffset(
      data,
      cursor,
      cursor + 46 + nameLength,
      extraLength,
    );
    final name = String.fromCharCodes(
      bytes.sublist(cursor + 46, cursor + 46 + nameLength),
    );
    // Local header: fixed 30 bytes + its own name/extra lengths.
    final localNameLength = data.getUint16(localOffset + 26, Endian.little);
    final localExtraLength = data.getUint16(localOffset + 28, Endian.little);
    entries.add(
      AnicelZipEntry(
        name: name,
        localHeaderOffset: localOffset,
        dataOffset: localOffset + 30 + localNameLength + localExtraLength,
        length: compressedSize,
        crc32: crc,
      ),
    );
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return AnicelZipLayout(entries: entries, centralDirectoryOffset: centralOffset);
}

/// Parses the layout straight from the FILE with tail-only reads (EOCD
/// scan window + central directory + 4 bytes per local header) — a
/// multi-gigabyte project must never load whole just to append a few
/// cels or list its entries.
AnicelZipLayout parseAnicelZipLayoutFile(String path) {
  final raf = File(path).openSync();
  try {
    final fileLength = raf.lengthSync();
    if (fileLength < 22) {
      throw const FormatException('No ZIP end-of-central-directory found.');
    }
    final tailLength = fileLength < 22 + 65535 ? fileLength : 22 + 65535;
    raf.setPositionSync(fileLength - tailLength);
    final tail = raf.readSync(tailLength);
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
    final tailStart = fileLength - tailLength;
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

    raf.setPositionSync(centralOffset);
    final central = raf.readSync(centralEnd - centralOffset);
    final data = ByteData.sublistView(central);
    final entries = <AnicelZipEntry>[];
    var cursor = 0;
    for (var i = 0; i < entryCount; i += 1) {
      if (cursor + 46 > central.length ||
          data.getUint32(cursor, Endian.little) != _centralSignature) {
        throw const FormatException('Corrupt central directory.');
      }
      final crc = data.getUint32(cursor + 16, Endian.little);
      final compressedSize = data.getUint32(cursor + 20, Endian.little);
      final nameLength = data.getUint16(cursor + 28, Endian.little);
      final extraLength = data.getUint16(cursor + 30, Endian.little);
      final commentLength = data.getUint16(cursor + 32, Endian.little);
      final localOffset = _centralLocalOffset(
        data,
        cursor,
        cursor + 46 + nameLength,
        extraLength,
      );
      final name = String.fromCharCodes(
        central.sublist(cursor + 46, cursor + 46 + nameLength),
      );
      raf.setPositionSync(localOffset + 26);
      final localLengths = ByteData.sublistView(raf.readSync(4));
      entries.add(
        AnicelZipEntry(
          name: name,
          localHeaderOffset: localOffset,
          dataOffset:
              localOffset +
              30 +
              localLengths.getUint16(0, Endian.little) +
              localLengths.getUint16(2, Endian.little),
          length: compressedSize,
          crc32: crc,
        ),
      );
      cursor += 46 + nameLength + extraLength + commentLength;
    }
    return AnicelZipLayout(
      entries: entries,
      centralDirectoryOffset: centralOffset,
    );
  } finally {
    raf.closeSync();
  }
}

/// Torn-tail RECOVERY (R24-D1): an append crash destroys only the tail
/// (the central directory + EOCD are rewritten last), never entry data
/// — so the file is reconstructable by walking LOCAL headers from the
/// front. Same-name entries resolve last-wins (the shadowing rule the
/// central directory encodes), a torn final entry is dropped, and the
/// LAST complete entry is CRC-verified (the only one a torn write can
/// have half-filled; verifying every entry would read whole gigabytes).
/// Entries deleted by removeNames may resurrect (their old locals still
/// exist) — for crash recovery, too much beats lost.
///
/// The returned centralDirectoryOffset is the end of the last complete
/// entry, so the file stays append-able; the next FULL save (which the
/// service forces because the tail no longer parses) rewrites the file
/// whole and heals it.
AnicelZipLayout recoverAnicelZipLayoutFile(String path) {
  final raf = File(path).openSync();
  try {
    final fileLength = raf.lengthSync();
    final byName = <String, AnicelZipEntry>{};
    final order = <String>[];
    var cursor = 0;
    var lastCompleteEnd = 0;
    String? lastName;
    AnicelZipEntry? shadowedByLast;
    while (cursor + 30 <= fileLength) {
      raf.setPositionSync(cursor);
      final header = raf.readSync(30);
      final data = ByteData.sublistView(header);
      if (data.getUint32(0, Endian.little) != _localSignature) {
        break; // Central-directory remnant or torn garbage: stop.
      }
      final crc = data.getUint32(14, Endian.little);
      final compressedSize = data.getUint32(18, Endian.little);
      final nameLength = data.getUint16(26, Endian.little);
      final extraLength = data.getUint16(28, Endian.little);
      final dataOffset = cursor + 30 + nameLength + extraLength;
      final entryEnd = dataOffset + compressedSize;
      if (entryEnd > fileLength) {
        break; // Torn final entry: its data never fully landed.
      }
      final name = String.fromCharCodes(raf.readSync(nameLength));
      if (!byName.containsKey(name)) {
        order.add(name);
      }
      shadowedByLast = byName[name];
      byName[name] = AnicelZipEntry(
        name: name,
        localHeaderOffset: cursor,
        dataOffset: dataOffset,
        length: compressedSize,
        crc32: crc,
      );
      lastName = name;
      lastCompleteEnd = entryEnd;
      cursor = entryEnd;
    }
    // The last complete entry is the only one a torn write can have
    // corrupted content-wise (data lands before the tail rewrite);
    // verify it and drop on mismatch.
    if (lastName != null) {
      final last = byName[lastName]!;
      if (last.localHeaderOffset + 30 <= fileLength &&
          last.dataOffset + last.length == lastCompleteEnd) {
        raf.setPositionSync(last.dataOffset);
        final bytes = raf.readSync(last.length);
        if (anicelCrc32(bytes) != last.crc32) {
          // Corrupt final entry: its earlier shadowed version (if any)
          // wins again, exactly as if the torn append never happened.
          if (shadowedByLast != null) {
            byName[lastName] = shadowedByLast;
          } else {
            byName.remove(lastName);
            order.remove(lastName);
          }
          lastCompleteEnd = last.localHeaderOffset;
        }
      }
    }
    return AnicelZipLayout(
      entries: [for (final name in order) byName[name]!],
      centralDirectoryOffset: lastCompleteEnd,
    );
  } finally {
    raf.closeSync();
  }
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

/// Appends [newEntries] ({name: raw bytes, STORE'd}) to the .anicel at
/// [path] IN PLACE: new locals write from the old central directory's
/// offset, then the merged central directory (old actives minus shadowed
/// names minus [removeNames], plus the new entries) and a fresh EOCD
/// close the file. [removeNames] deletes entries outright (a cel that
/// became empty or moved away) — their bytes turn to garbage like any
/// shadowed entry, reclaimed at the next compaction. Returns the
/// resulting layout (offsets valid for the rewritten file).
/// One entry appended by streaming rather than by handing over bytes.
///
/// 🚨 The reason it exists: [appendAnicelEntries] takes a `Uint8List` per
/// entry, which is right for a cel — small, and already deflated in hand —
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

AnicelZipLayout appendAnicelEntries({
  required String path,
  required Map<String, Uint8List> newEntries,
  Set<String> removeNames = const {},
  List<AnicelStreamedEntry> streamedEntries = const [],
}) {
  final file = File(path);
  // Tail-only parse: the append must not scale with file size.
  final layout = parseAnicelZipLayoutFile(path);

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
  var writeOffset = layout.centralDirectoryOffset;

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
  // must not have already truncated the archive to find that out.
  final streamedCrcs = <int>[];
  for (final entry in streamedEntries) {
    var running = anicelCrc32Start;
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
      running = anicelCrc32Update(running, buffer, read);
      position += read;
    }
    streamedCrcs.add(anicelCrc32Finish(running));
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
  final centralBytes = _centralDirectoryBytes(all);
  final eocd = _eocdBytes(
    entryCount: all.length,
    centralLength: centralBytes.length,
    centralOffset: centralOffset,
  );

  // One sequential write: truncate at the old central directory, then
  // locals + streamed locals + central + EOCD.
  final raf = file.openSync(mode: FileMode.append);
  try {
    raf.truncateSync(layout.centralDirectoryOffset);
    raf.setPositionSync(layout.centralDirectoryOffset);
    raf.writeFromSync(builder.takeBytes());
    for (var i = 0; i < streamedEntries.length; i += 1) {
      final entry = streamedEntries[i];
      raf.writeFromSync(_localHeaderBytes(
        entry.name,
        entry.length,
        streamedCrcs[i],
      ));
      // Chunked on purpose: one buffer, reused, whatever the asset weighs.
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
        raf.writeFromSync(buffer, 0, read);
        position += read;
      }
    }
    raf.writeFromSync(centralBytes);
    raf.writeFromSync(eocd);
    raf.flushSync();
  } finally {
    raf.closeSync();
  }

  return AnicelZipLayout(entries: all, centralDirectoryOffset: centralOffset);
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
/// blobs carry their own deflate — so a length is known before its bytes
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
    // already deflated, so holding one at a time costs nothing; an
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

      var running = anicelCrc32Start;
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
        running = anicelCrc32Update(running, buffer, read);
        raf.writeFromSync(buffer, 0, read);
        position += read;
      }
      final crc = anicelCrc32Finish(running);
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

/// Identifies the .anicel at [path] well enough to refuse a recovery
/// overlay that was not built against it.
///
/// A recovery snapshot holds only what changed since the last save, so it
/// is meaningless — worse, quietly wrong — laid over a different base. The
/// stamp is the file's length plus a CRC-32 of its central directory and
/// EOCD, which is a TAIL-ONLY read: a multi-gigabyte project must not be
/// hashed whole to answer "is this the file I was built from".
///
/// Content-derived rather than a counter, so it cannot be made to agree by
/// copying, restoring or re-syncing a project — the failure mode a
/// generation number has is that two different files can carry the same
/// one. The central directory names every entry with its offset, length
/// and CRC, so any change to the archive moves it.
///
/// Returns null when the file cannot be read or has no valid tail; the
/// caller treats that as "no base to check against".
String? anicelBaseStamp(String path) {
  try {
    final raf = File(path).openSync();
    try {
      final length = raf.lengthSync();
      final layout = parseAnicelZipLayoutFile(path);
      raf.setPositionSync(layout.centralDirectoryOffset);
      final tail = raf.readSync(length - layout.centralDirectoryOffset);
      return '$length:${anicelCrc32(tail).toRadixString(16)}';
    } finally {
      raf.closeSync();
    }
  } on Object {
    return null;
  }
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
  final header = ByteData(30);
  header.setUint32(0, _localSignature, Endian.little);
  header.setUint16(4, 20, Endian.little); // version needed
  header.setUint16(6, 0, Endian.little); // flags
  header.setUint16(8, 0, Endian.little); // method 0 = STORE
  header.setUint32(10, 0, Endian.little); // dos time/date
  header.setUint32(14, crc, Endian.little);
  header.setUint32(18, length, Endian.little);
  header.setUint32(22, length, Endian.little);
  header.setUint16(26, nameBytes.length, Endian.little);
  header.setUint16(28, 0, Endian.little);
  final out = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(nameBytes);
  return out.takeBytes();
}

Uint8List _centralDirectoryBytes(List<AnicelZipEntry> entries) {
  final central = BytesBuilder(copy: false);
  for (final entry in entries) {
    final nameBytes = Uint8List.fromList(entry.name.codeUnits);
    // A single entry over 4GB would need its SIZES in a ZIP64 extra too,
    // and nothing this app writes can reach that: a cel is a tile sheet
    // and the only media that travels inside is audio, images and PDFs
    // (video is a reference by the kind rule). Refused loudly rather than
    // handled, because a silently truncated size is a file that opens and
    // reads the wrong bytes.
    if (entry.length > _zip32Max) {
      throw StateError(
        'entry "${entry.name}" is ${entry.length} bytes; the writer does '
        'not emit ZIP64 sizes',
      );
    }
    final needsOffset64 = entry.localHeaderOffset > _zip32Max;
    final extra = needsOffset64 ? ByteData(12) : null;
    if (extra != null) {
      // ZIP64 Extended Information: only the fields that read 0xFFFFFFFF
      // above appear, in the spec's order. Here that is the local header
      // offset alone.
      extra.setUint16(0, _zip64ExtraId, Endian.little);
      extra.setUint16(2, 8, Endian.little); // payload size
      extra.setUint64(4, entry.localHeaderOffset, Endian.little);
    }
    final record = ByteData(46);
    record.setUint32(0, _centralSignature, Endian.little);
    record.setUint16(4, 20, Endian.little); // version made by
    record.setUint16(6, needsOffset64 ? 45 : 20, Endian.little);
    record.setUint16(8, 0, Endian.little);
    record.setUint16(10, 0, Endian.little); // method STORE
    record.setUint32(12, 0, Endian.little); // time/date
    record.setUint32(16, entry.crc32, Endian.little);
    record.setUint32(20, entry.length, Endian.little);
    record.setUint32(24, entry.length, Endian.little);
    record.setUint16(28, nameBytes.length, Endian.little);
    record.setUint16(30, extra?.lengthInBytes ?? 0, Endian.little);
    record.setUint32(
      42,
      needsOffset64 ? _zip32Max : entry.localHeaderOffset,
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
  final needs64 = anicelAlwaysZip64 ||
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
