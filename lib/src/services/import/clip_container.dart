import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Thrown when a file cannot be read as a CLIP STUDIO PAINT document.
class ClipFormatException implements Exception {
  const ClipFormatException(this.message);

  final String message;

  @override
  String toString() => 'ClipFormatException: $message';
}

/// Where a run of bytes lies in a file.
typedef ClipPlace = ({int offset, int length});

/// Where a CLIP STUDIO PAINT file (.clip) keeps its parts — found by walking
/// its chunks once, so the pictures can be read one at a time instead of the
/// whole file at once (a cut's file holds every cel's pixels).
///
/// ## Format (measured 2026-10-06 on five files, memory `csp-clip-format-notes`)
///
/// Big-endian throughout:
///
///   "CSFCHUNK" · u64 file size · u64 offset of the first chunk (24)
///   chunk := 8-character kind · u64 body size · body
///     CHNKHead  u64 0x100 · u64 where CHNKSQLi stands · u64 16 · 16-byte id
///     CHNKExta  u64 id length · id ("extrnlid" + 32 hex) · u64 size · data
///     CHNKSQLi  a whole SQLite 3 database — the document's structure
///     CHNKFoot  (empty)
///
/// Walked to its end, the chain lands exactly on the end of the file.
final class ClipContainer {
  const ClipContainer._({required this.database, required this.externals});

  /// The embedded database: the layers, the timelines, where each external
  /// chunk is.
  final ClipPlace database;

  /// Every external chunk's data — pixels, a track's animation, a sound —
  /// by the id the database names it with.
  final Map<String, ClipPlace> externals;

  static const _magic = 'CSFCHUNK';

  /// [file]'s chunks, walked from the head to the end.
  static ClipContainer indexOf(RandomAccessFile file) {
    final length = file.lengthSync();
    final head = _read(file, 0, 24, length);
    if (ascii.decode(head.sublist(0, 8), allowInvalid: true) != _magic) {
      throw const ClipFormatException('not a CLIP STUDIO PAINT file');
    }
    final view = ByteData.sublistView(head);
    var at = view.getUint64(16);
    ClipPlace? database;
    final externals = <String, ClipPlace>{};
    while (at < length) {
      final chunk = ByteData.sublistView(_read(file, at, 16, length));
      final kind = ascii.decode(
        Uint8List.sublistView(chunk, 0, 8),
        allowInvalid: true,
      );
      final size = chunk.getUint64(8);
      final body = at + 16;
      if (body + size > length) {
        throw ClipFormatException('the $kind chunk at $at runs past the end');
      }
      switch (kind) {
        case 'CHNKSQLi':
          database = (offset: body, length: size);
        case 'CHNKExta':
          final idLength = ByteData.sublistView(
            _read(file, body, 8, length),
          ).getUint64(0);
          final id = ascii.decode(
            _read(file, body + 8, idLength, length),
            allowInvalid: true,
          );
          final dataAt = body + 8 + idLength + 8;
          final dataSize = ByteData.sublistView(
            _read(file, body + 8 + idLength, 8, length),
          ).getUint64(0);
          if (dataAt + dataSize > body + size) {
            throw ClipFormatException('the data of $id runs past its chunk');
          }
          externals[id] = (offset: dataAt, length: dataSize);
      }
      at = body + size;
    }
    if (database == null) {
      throw const ClipFormatException('the file holds no database');
    }
    return ClipContainer._(database: database, externals: externals);
  }

  static Uint8List _read(RandomAccessFile file, int at, int count, int end) {
    if (at + count > end) {
      throw ClipFormatException('the file ends inside a chunk at $at');
    }
    file.setPositionSync(at);
    return file.readSync(count);
  }
}

/// The bytes at [place] in [file].
Uint8List readClipPlace(RandomAccessFile file, ClipPlace place) {
  file.setPositionSync(place.offset);
  final bytes = file.readSync(place.length);
  if (bytes.length != place.length) {
    throw ClipFormatException(
      'the file ends inside the data at ${place.offset}',
    );
  }
  return bytes;
}
