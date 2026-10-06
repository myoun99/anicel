import 'dart:async';
import 'dart:typed_data';

import 'package:anicel/src/services/font_library_service.dart';

/// THE FONT LIBRARY, KEPT IN MEMORY — for a widget test, whose clock does
/// not turn the disk's: every answer comes back in the same turn of the
/// test's own queue.
///
/// ⚠️What the real library does with a disk is measured on a disk
/// (`font_library_service_test`); this stands in for its PLACE, not for its
/// behaviour.
class FontLibraryInMemory implements FontLibraryService {
  /// The files, by the names the library minted for them.
  final Map<String, Uint8List> files = {};

  /// The index as it was last written.
  List<FontLibraryEntry> index = [];

  /// Whether a file handed over is refused, as a disk that is full would.
  bool refusesWrites = false;

  /// Every file read, in order.
  final List<String> read = [];

  /// While set, a read does not come back — the test holds a face on its
  /// way, and lets it arrive by completing this.
  Completer<void>? gate;

  /// While set, the index does not come back: it was read as it stood when
  /// it was asked for, and is handed over when this completes.
  Completer<void>? indexGate;

  /// How many times the index was read.
  int indexReads = 0;

  @override
  String get directoryPath => 'memory://fonts';

  @override
  String get indexPath => '$directoryPath/index.json';

  @override
  Future<List<FontLibraryEntry>> loadIndex() async {
    indexReads += 1;
    final asItStood = List.of(index);
    await indexGate?.future;
    return asItStood;
  }

  @override
  Future<void> saveIndex(List<FontLibraryEntry> entries) async {
    index = List.of(entries);
  }

  @override
  Future<void> writeFont(String file, Uint8List bytes) async {
    if (refusesWrites) {
      throw StateError('the disk is full');
    }
    files[file] = bytes;
  }

  @override
  Future<Uint8List?> readFont(String file) async {
    read.add(file);
    await gate?.future;
    return files[file];
  }

  @override
  Future<void> deleteFont(String file) async {
    files.remove(file);
  }
}
