import 'dart:io';

import '../../models/project.dart';
import '../persistence/anicel_incremental_writer.dart';
import '../persistence/anicel_project_archive.dart';
import '../project_lookup.dart';
import 'media_byte_source.dart';

/// Where each piece of media the project should CARRY can be read from
/// right now.
///
/// The answer moves. An asset just imported is a file on disk; the same
/// asset after one save is a range inside the `.anicel`; and during a
/// save-as it is a range inside the OLD `.anicel` while the new one is
/// being written. One walk answers all three, which is what lets save-as
/// carry media without a copy step of its own — the writer streams from
/// wherever each source happens to point.
///
/// 🔑 Resolved fresh at every save rather than remembered. Offsets belong
/// to one layout and a compaction rewrites the file; a source kept from
/// before would read a window of whatever moved into those bytes, which is
/// a project that opens fine and plays the wrong sound.
///
/// An asset that is neither in the archive nor on disk is LEFT OUT rather
/// than guessed at. It is already missing, the relink flow exists for
/// exactly that, and writing a zero-length entry over its name would turn
/// a findable absence into a permanent one.
Map<String, MediaByteSource> projectMediaSources({
  required Project project,
  required String? projectFilePath,
  required Map<String, String> mediaEntryNames,
}) {
  final wanted = projectArchivedMediaPaths(project);
  if (wanted.isEmpty) {
    return const {};
  }

  // The archive's current layout, read once for the whole walk. Tail-only,
  // so this costs a central-directory read rather than a pass over the
  // project.
  AnicelZipLayout? layout;
  if (projectFilePath != null && File(projectFilePath).existsSync()) {
    try {
      layout = parseAnicelZipLayoutFile(projectFilePath);
    } on Object {
      // A torn tail is the save path's problem to heal; here it just means
      // nothing can be claimed to be inside yet.
      layout = null;
    }
  }

  final sources = <String, MediaByteSource>{};
  for (final path in wanted) {
    final entryName = mediaEntryNames[path];
    if (entryName != null && layout != null) {
      final entry = layout.entryNamed(entryName);
      if (entry != null) {
        sources[path] = MediaArchiveBytes(
          archivePath: projectFilePath!,
          dataOffset: entry.dataOffset,
          length: entry.length,
          entryCrc32: entry.crc32,
        );
        continue;
      }
    }
    // Not inside yet — the file it was imported from is the source, and
    // this save is what brings it in.
    final file = MediaFileBytes(path);
    if (file.existsSync()) {
      sources[path] = file;
    }
  }
  return sources;
}

/// What the project should record as living inside it, after a save that
/// stored [sources].
Map<String, String> mediaEntryNamesFor(Iterable<String> sources) => {
  for (final path in sources) path: anicelMediaEntryName(path),
};
