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
  final entryCount = data.getUint16(eocd + 10, Endian.little);
  final centralOffset = data.getUint32(eocd + 16, Endian.little);

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
    final localOffset = data.getUint32(cursor + 42, Endian.little);
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
    final entryCount = tailData.getUint16(eocd + 10, Endian.little);
    final centralOffset = tailData.getUint32(eocd + 16, Endian.little);
    final eocdAbsolute = fileLength - tailLength + eocd;
    if (centralOffset > eocdAbsolute) {
      throw const FormatException('Corrupt central directory.');
    }

    raf.setPositionSync(centralOffset);
    final central = raf.readSync(eocdAbsolute - centralOffset);
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
      final localOffset = data.getUint32(cursor + 42, Endian.little);
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

int anicelCrc32(Uint8List bytes) {
  var c = 0xFFFFFFFF;
  for (var i = 0; i < bytes.length; i += 1) {
    c = _crcTable[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Appends [newEntries] ({name: raw bytes, STORE'd}) to the .anicel at
/// [path] IN PLACE: new locals write from the old central directory's
/// offset, then the merged central directory (old actives minus shadowed
/// names minus [removeNames], plus the new entries) and a fresh EOCD
/// close the file. [removeNames] deletes entries outright (a cel that
/// became empty or moved away) — their bytes turn to garbage like any
/// shadowed entry, reclaimed at the next compaction. Returns the
/// resulting layout (offsets valid for the rewritten file).
AnicelZipLayout appendAnicelEntries({
  required String path,
  required Map<String, Uint8List> newEntries,
  Set<String> removeNames = const {},
}) {
  final file = File(path);
  // Tail-only parse: the append must not scale with file size.
  final layout = parseAnicelZipLayoutFile(path);

  final survivors = [
    for (final entry in layout.entries)
      if (!newEntries.containsKey(entry.name) &&
          !removeNames.contains(entry.name))
        entry,
  ];

  final builder = BytesBuilder(copy: false);
  final appended = <AnicelZipEntry>[];
  var writeOffset = layout.centralDirectoryOffset;

  Uint8List localHeader(String name, Uint8List bytes, int crc) {
    final nameBytes = Uint8List.fromList(name.codeUnits);
    final header = ByteData(30);
    header.setUint32(0, _localSignature, Endian.little);
    header.setUint16(4, 20, Endian.little); // version needed
    header.setUint16(6, 0, Endian.little); // flags
    header.setUint16(8, 0, Endian.little); // method 0 = STORE
    header.setUint32(10, 0, Endian.little); // dos time/date
    header.setUint32(14, crc, Endian.little);
    header.setUint32(18, bytes.length, Endian.little);
    header.setUint32(22, bytes.length, Endian.little);
    header.setUint16(26, nameBytes.length, Endian.little);
    header.setUint16(28, 0, Endian.little);
    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(nameBytes);
    return out.takeBytes();
  }

  for (final entry in newEntries.entries) {
    final crc = anicelCrc32(entry.value);
    final header = localHeader(entry.key, entry.value, crc);
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

  // Central directory over survivors + appended.
  final centralOffset = writeOffset;
  final central = BytesBuilder(copy: false);
  final all = [...survivors, ...appended];
  for (final entry in all) {
    final nameBytes = Uint8List.fromList(entry.name.codeUnits);
    final record = ByteData(46);
    record.setUint32(0, _centralSignature, Endian.little);
    record.setUint16(4, 20, Endian.little); // version made by
    record.setUint16(6, 20, Endian.little); // version needed
    record.setUint16(8, 0, Endian.little);
    record.setUint16(10, 0, Endian.little); // method STORE
    record.setUint32(12, 0, Endian.little); // time/date
    record.setUint32(16, entry.crc32, Endian.little);
    record.setUint32(20, entry.length, Endian.little);
    record.setUint32(24, entry.length, Endian.little);
    record.setUint16(28, nameBytes.length, Endian.little);
    record.setUint32(42, entry.localHeaderOffset, Endian.little);
    central
      ..add(record.buffer.asUint8List())
      ..add(nameBytes);
  }
  final centralBytes = central.takeBytes();
  final eocd = ByteData(22);
  eocd.setUint32(0, _eocdSignature, Endian.little);
  eocd.setUint16(8, all.length, Endian.little);
  eocd.setUint16(10, all.length, Endian.little);
  eocd.setUint32(12, centralBytes.length, Endian.little);
  eocd.setUint32(16, centralOffset, Endian.little);

  // One sequential write: truncate at the old central directory, then
  // locals + central + EOCD.
  final raf = file.openSync(mode: FileMode.append);
  try {
    raf.truncateSync(layout.centralDirectoryOffset);
    raf.setPositionSync(layout.centralDirectoryOffset);
    raf.writeFromSync(builder.takeBytes());
    raf.writeFromSync(centralBytes);
    raf.writeFromSync(eocd.buffer.asUint8List());
    raf.flushSync();
  } finally {
    raf.closeSync();
  }

  return AnicelZipLayout(entries: all, centralDirectoryOffset: centralOffset);
}
