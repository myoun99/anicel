import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;

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
      sources[path] = MediaAppFileBytes(
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

/// Which of the project's media have a CONFORM to carry, and where its
/// bytes are right now.
///
/// 🚨★★★**TWO PLACES, IN THIS ORDER: THE CACHE, THEN THE ARCHIVE.** The
/// cache holds a conform this machine has built; the archive holds one the
/// project carried here from somewhere else. Asking only the cache — the
/// first shape of this — meant a machine that had just OPENED the project
/// answered「nothing」for every sound, and the save then swept every
/// conform the file was carrying. The journey carrying them exists to
/// serve was the one that destroyed them.
///
/// 🔑The settings live in the ENTRY NAME ([anicelConformEntryName]), so
///「built at other settings」and「not built here yet」stop being the same
/// answer: a stale conform is under a name this walk never asks for, and a
/// current one is under the name it does. What comes back IS the keep set
/// — the sweep is everything under `conform/` that is not a key of it.
///
/// ⛔Bytes are taken AS THEY ARE, framed or not — the same rule staged
/// media follows. Decompressing a conform to re-compress it into the
/// archive would burn the whole reason it was compressed.
///
/// ⚠️A conform whose source has since been replaced can still be carried
/// here; it is the pipeline that validates the fingerprint on read and
/// rebuilds. Deciding that twice is how two answers drift apart.
///
/// ⛔**CARRIED MEDIA ONLY**, which is why this walks
/// [projectArchivedMediaPaths] rather than every audio path the project
/// touches. A conform IS the audio — decoded, but every sample of it — so
/// carrying the conform of a REFERENCED sound would put that sound inside
/// the project after the user said to leave it linked. That the copy
/// would be in another format changes nothing about what it is.
ProjectConforms projectConformSources({
  required Project project,
  required String? Function(String poolPath) conformBasePathFor,
  required int sampleRate,
  required int speedNumerator,
  required int speedDenominator,
  String? projectFilePath,
}) {
  final wanted = projectArchivedMediaPaths(project);
  if (wanted.isEmpty) {
    return const ProjectConforms.none();
  }
  // The archive's current layout, read once — the same tail-only parse
  // `projectMediaSources` makes, and for the same reason: a conform
  // already inside is where its bytes are.
  AnicelZipLayout? layout;
  if (projectFilePath != null && File(projectFilePath).existsSync()) {
    try {
      layout = parseAnicelZipLayoutFile(projectFilePath);
    } on Object {
      layout = null; // A torn tail carries nothing forward; it rebuilds.
    }
  }

  final sources = <String, MediaByteSource>{};
  for (final path in wanted) {
    final names = anicelConformEntryNames(
      path,
      sampleRate: sampleRate,
      speedNumerator: speedNumerator,
      speedDenominator: speedDenominator,
    );
    String nameFor({required bool framed}) => anicelConformEntryName(
      path,
      sampleRate: sampleRate,
      speedNumerator: speedNumerator,
      speedDenominator: speedDenominator,
      framed: framed,
    );

    final base = conformBasePathFor(path);
    if (base != null) {
      final cached = mediaFramedOrPlainPaths(
        base,
      ).where((candidate) => File(candidate).existsSync()).firstOrNull;
      if (cached != null) {
        final framed = mediaEntryIsFramed(cached);
        sources[nameFor(framed: framed)] = MediaAppFileBytes(
          path: cached,
          framed: framed,
        );
        continue;
      }
    }
    // 🚨Not in the cache, but the project may already be carrying it —
    // which is the ORDINARY state on a machine that just opened the file,
    // and on one whose cache was emptied. Handing the archive's own bytes
    // back is what lets a full rewrite (Save As, a compaction) keep them
    // instead of dropping what it was not given.
    if (layout != null) {
      for (final name in names) {
        final entry = layout.entryNamed(name);
        if (entry != null) {
          sources[name] = MediaArchiveBytes(
            archivePath: projectFilePath!,
            dataOffset: entry.dataOffset,
            length: entry.length,
            entryCrc32: entry.crc32,
            framed: mediaEntryIsFramed(name),
          );
          break;
        }
      }
    }
  }
  return ProjectConforms(sources);
}

/// What a save should do about conforms: the entries to hold, and where
/// each one's bytes are right now.
///
/// 🚨★★★**ONE MAP, AND ITS KEYS ARE THE WHOLE ANSWER.** A conform entry
/// survives a save if and only if it is named here; everything else under
/// `conform/` is swept. That works because [entries] is resolved from BOTH
/// places a conform can be — the cache and the archive itself — so
/// "nothing here" really does mean "nothing this project should hold",
/// rather than "this machine has not built it yet".
///
/// 🪦An earlier shape carried a second set, `liveNames`, listing both
/// framed spellings per asset so an un-built conform would not be swept.
/// It was answering a question [entries] already answers, and it leaked:
/// a project saved once by a build WITHOUT zstd and again by one with it
/// would keep both the plain and the framed conform, since both spellings
/// were live. One field cannot disagree with itself.
///
/// ⚠️A separate TYPE rather than a bare map, because the map beside it in
/// every signature ([AnicelFileService.save]'s `mediaToStore`) is keyed by
/// POOL PATH. Two maps of the same Dart type meaning different things is
/// how a call site gets them the wrong way round.
@immutable
class ProjectConforms {
  const ProjectConforms(this.entries);

  /// Nothing to hold: every conform entry in the file is stale. The
  /// default for callers that do not manage conforms — recovery overlays
  /// and tests — which also never see a conform entry to sweep.
  const ProjectConforms.none() : entries = const {};

  /// **Archive ENTRY NAME** → where those bytes are right now: the cache,
  /// or the entry the project already carries.
  ///
  /// Keyed by the name rather than by the pool path because the name is
  /// what the writer needs, and deriving it there would mean deriving it
  /// again from settings that would have to be handed over separately.
  final Map<String, MediaByteSource> entries;
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
