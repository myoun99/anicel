import 'dart:io';

import '../../models/project.dart';
import '../persistence/anicel_incremental_writer.dart';
import '../persistence/anicel_project_archive.dart';
import '../project_lookup.dart';
import '../persistence/media_blob_codec.dart';
import '../persistence/media_staging_store.dart';
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
  MediaStagingStore? staging,
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
      // 🚨 A torn tail is NOT "nothing is inside". The crash contract says
      // an append crash destroys only the file's tail — the media entries'
      // bytes are still in the body — and the very next save is the HEAL
      // that consumes this answer to decide what streams forward.
      // Answering "nothing" here made that healing save rename a
      // media-less archive over the file that still physically held the
      // bytes: for an asset whose import original was gone (the whole
      // reason carrying exists), that was silent, permanent loss. The
      // local-header walk recovers what the tail no longer names.
      try {
        layout = recoverAnicelZipLayoutFile(projectFilePath);
      } on Object {
        layout = null;
      }
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
          framed: mediaEntryIsFramed(entryName),
        );
        continue;
      }
    }
    // Not inside yet — the file it was imported from is the source, and
    // this save is what brings it in.
    // Staged at 품기: the bytes the project already controls, already compressed
    // when that was worth it. They go in AS THEY ARE.
    final staged = staging?.find(path);
    if (staged != null) {
      sources[path] = MediaStagedBytes(
        path: staged.path,
        framed: staged.framed,
      );
      continue;
    }
    final file = MediaFileBytes(path);
    if (file.existsSync()) {
      sources[path] = file;
      continue;
    }
    // Recorded as INSIDE the project and found nowhere: refusing beats
    // certifying the loss. A save that proceeded here would write an
    // archive without the asset and rename it over whatever still held
    // the bytes — and the session would then forget the asset was ever
    // embedded. (An asset that was never carried in simply stays LEFT
    // OUT, per the doc above — that one is a findable absence the relink
    // flow exists for.)
    if (entryName != null) {
      throw StateError(
        'media "$path" is recorded inside the project, but neither the '
        'archive nor the original file holds its bytes — saving now would '
        'make that loss permanent',
      );
    }
  }
  return sources;
}

/// What the project should record as living inside it, after a save that
/// stored [sources].
Map<String, String> mediaEntryNamesFor(Map<String, MediaByteSource> sources) =>
    {
      for (final entry in sources.entries)
        entry.key: anicelMediaEntryName(
          entry.key,
          framed: entry.value.storedIsFramed,
        ),
    };
