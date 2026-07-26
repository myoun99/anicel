import 'dart:convert';
import 'dart:io';

import '../models/brush_tip_entry.dart';
import '../models/brush_tip_mask.dart';
import 'brush_tip_image_codec.dart';
import 'persistence/app_support_path.dart';

/// Reads and writes the shared brush tip library: a FOLDER of PNGs plus a
/// small index.
///
/// Clip Studio keeps the same three things — the image is a PNG, a catalog
/// maps brushes to it, and a thumbnail sits alongside so the palette can
/// draw without decoding the original (see `sut/sut_decoder.dart`, which
/// reads exactly that layout out of a `.sut`). The difference here is a
/// folder instead of a database, so the tips are files the user can look at,
/// copy and back up.
///
/// Tips are app state, not project data: an artwork's pixels are already
/// committed, so a missing tip costs a brush preset, never a drawing.
class BrushTipLibraryService {
  BrushTipLibraryService({String? directoryPath})
    : directoryPath = directoryPath ?? defaultBrushTipDirectoryPath();

  /// Folder holding `index.json` and one PNG per tip.
  final String directoryPath;

  static String defaultBrushTipDirectoryPath() =>
      appSupportFilePath('brush_tips');

  /// Index file format version.
  static const int indexVersion = 1;

  String get indexPath => '$directoryPath/index.json';

  String imagePathFor(String id) => '$directoryPath/$id.png';

  /// Reads the index — names, sizes and thumbnails, no image decoding.
  /// A missing or unreadable index means an empty library, never an error:
  /// the built-in tips are added by the caller and always exist.
  Future<List<BrushTipEntry>> loadIndex() async {
    try {
      final file = File(indexPath);
      if (!await file.exists()) {
        return const <BrushTipEntry>[];
      }
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final entries = decoded['tips'] as List<dynamic>;
      final seen = <String>{};
      return [
        for (final entry in entries)
          BrushTipEntry.fromJson(entry as Map<String, dynamic>),
      ].where((entry) => seen.add(entry.id)).toList();
    } catch (_) {
      return const <BrushTipEntry>[];
    }
  }

  /// Decodes one tip's image. Returns `null` when the file is gone or
  /// unreadable — a tip that cannot be read degrades to the parametric round
  /// tip with a warning, the same rule Clip Studio import already follows
  /// for a missing material.
  Future<BrushTipMask?> loadMask(String id) async {
    try {
      final file = File(imagePathFor(id));
      if (!await file.exists()) {
        return null;
      }
      return await decodeBrushTipImage(await file.readAsBytes(), id: id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveIndex(List<BrushTipEntry> entries) async {
    final file = File(indexPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': indexVersion,
        'tips': [
          for (final entry in entries)
            if (!entry.builtIn) entry.toJson(),
        ],
      }),
    );
  }

  /// Writes [mask] as this library's copy of a tip and returns its entry.
  /// The caller owns the index; this only puts the image on disk.
  Future<BrushTipEntry> writeImage(
    BrushTipMask mask, {
    required String name,
  }) async {
    final file = File(imagePathFor(mask.id));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await encodeBrushTipImage(mask), flush: true);
    return BrushTipEntry(
      id: mask.id,
      name: name,
      size: mask.size,
      thumbnail: brushTipThumbnailAlpha(mask, side: brushTipThumbnailSide),
      mask: mask,
    );
  }

  /// Removes a tip's image. A missing file is not an error — the index is
  /// the record that matters, and it is written by the caller.
  Future<void> deleteImage(String id) async {
    try {
      final file = File(imagePathFor(id));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // A tip that will not delete stays on disk; the index has already
      // dropped it, so it is invisible either way.
    }
  }
}

/// Folds an arbitrary string into the filename-safe alphabet tip ids use.
///
/// Ids become FILE NAMES, which presets never were: an id carrying a path
/// separator or `..` would write outside the library folder. Everything
/// outside `[a-z0-9-]` collapses to a single dash, and an id that empties
/// out falls back to `tip`.
String sanitizeBrushTipId(String id) {
  final buffer = StringBuffer();
  var lastWasDash = false;
  for (final rune in id.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    final safe =
        (rune >= 0x61 && rune <= 0x7A) || (rune >= 0x30 && rune <= 0x39);
    if (safe) {
      buffer.write(character);
      lastWasDash = false;
    } else if (!lastWasDash) {
      buffer.write('-');
      lastWasDash = true;
    }
  }
  final trimmed = buffer.toString().replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'tip' : trimmed;
}

/// Mints an id for a tip the user adds by hand.
///
/// The counter is not decoration: registering a folder of PNGs at once puts
/// several tips in the SAME millisecond, and two tips sharing an id would
/// mean two brushes sharing a file.
String nextUserBrushTipId({required int sequence}) =>
    'tip-${DateTime.now().millisecondsSinceEpoch}-$sequence';
