import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;

import '../../models/media_asset.dart' show MediaCarry;
import '../../models/project.dart';
import '../persistence/anicel_incremental_writer.dart';
import '../persistence/anicel_project_archive.dart';
import '../project_lookup.dart';
import '../persistence/media_blob_codec.dart';
import '../persistence/media_staging_store.dart';
import 'media_byte_source.dart';

/// Where a medium's bytes were found ([storedMediaBytesFor]).
enum MediaBytesAt {
  /// An entry of the project file.
  archive,

  /// The copy 품기 staged in the app container, not yet absorbed.
  staged,

  /// The file it was imported from.
  original,
}

/// Where [carry]'s STORED bytes are right now — THE order every reader and
/// the save look in: its entry in the project file's [layout], then the
/// copy [staging] holds, then the file it came from.
///
/// 🚨★★★**ONE ORDER, WRITTEN ONCE.** The save's walk ([projectMediaSources])
/// and the readers' question (`ProjectFile.holdMediaBytes`) each spelled
/// this out, and they had drifted: only the save recovered a torn tail, so
/// after a crash a reader fell back to an original the save knew better
/// than to trust (audit 2026-09-24, `carried-bytes-audit-0924`).
///
/// 🚨★★★**ASKED BY CARRY, NOT BY PATH.** Both places are named from the
/// carry ([anicelMediaEntryName], [MediaStagingStore.stagedNameFor]), so
/// the bytes of an earlier carry of the same path — still in the file, or
/// still staged, for an undo to bring back — are not an answer to this one
/// (card `recarry-after-remove-reads-the-old`).
///
/// STORED, not readable: a framed entry comes back framed — the save
/// streams it forward as it is, and a reader decodes it
/// ([mediaSourceDecodingFrames]). Either spelling of the entry answers:
/// whether it compressed is a property of the bytes.
({MediaByteSource stored, MediaBytesAt at}) storedMediaBytesFor(
  MediaCarry carry, {
  required AnicelZipLayout? layout,
  required String? archivePath,
  required MediaStagingStore? staging,
}) {
  if (layout != null && archivePath != null) {
    for (final name in anicelMediaEntryNames(carry)) {
      final entry = layout.entryNamed(name);
      if (entry != null) {
        return (
          stored: MediaArchiveBytes.ofEntry(
            archivePath: archivePath,
            entry: entry,
          ),
          at: MediaBytesAt.archive,
        );
      }
    }
  }
  // Staged at 품기: the bytes the project already controls, already
  // compressed when that was worth it.
  final staged = staging?.find(carry);
  if (staged != null) {
    return (
      stored: MediaAppFileBytes(path: staged.path, framed: staged.framed),
      at: MediaBytesAt.staged,
    );
  }
  return (stored: MediaFileBytes(carry.poolPath), at: MediaBytesAt.original);
}

/// Whether [entryNames] — the media entries a project file is known to
/// hold — include [carry]'s, under either spelling.
bool mediaEntryHeld(Set<String> entryNames, MediaCarry carry) =>
    anicelMediaEntryNames(carry).any(entryNames.contains);

/// The layout of the project file at [projectFilePath] as a reader should
/// see it — its tail's directory, or the last one that committed when a
/// crash tore the tail — or null when there is nothing to read.
///
/// 🚨 A torn tail is NOT "nothing is inside". The crash contract says a
/// crashed save leaves the last committed directory and everything it names
/// intact — the media entries' bytes are still in the body — and the very
/// next save is the HEAL that consumes this answer to decide what streams
/// forward. Answering "nothing" here made that healing save rename a
/// media-less archive over the file that still physically held the bytes:
/// for an asset whose import original was gone (the whole reason carrying
/// exists), that was silent, permanent loss. The recovery finds what the
/// torn tail no longer names.
AnicelZipLayout? readableAnicelLayout(String? projectFilePath) {
  if (projectFilePath == null || !File(projectFilePath).existsSync()) {
    return null;
  }
  try {
    return parseAnicelZipLayoutFile(projectFilePath);
  } on Object {
    try {
      return recoverAnicelZipLayoutFile(projectFilePath);
    } on Object {
      return null;
    }
  }
}

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
///
/// Keyed by the CARRY: each one's entry is named from it
/// ([anicelMediaEntryName]), and [mediaInFile] is the entries the project
/// file is known to hold.
Map<MediaCarry, MediaByteSource> projectMediaSources({
  required Project project,
  required String? projectFilePath,
  required Set<String> mediaInFile,
  MediaStagingStore? staging,
}) {
  final wanted = projectMediaCarries(project);
  if (wanted.isEmpty) {
    return const {};
  }
  // The archive's current layout, read once for the whole walk. Tail-only,
  // so this costs a central-directory read rather than a pass over the
  // project.
  final layout = readableAnicelLayout(projectFilePath);
  final sources = <MediaCarry, MediaByteSource>{};
  for (final carry in wanted) {
    final (:stored, :at) = storedMediaBytesFor(
      carry,
      layout: layout,
      archivePath: projectFilePath,
      staging: staging,
    );
    // The staged copy goes in AS IT IS; the original only while it is there.
    if (at != MediaBytesAt.original || stored.existsSync()) {
      sources[carry] = stored;
      continue;
    }
    // Recorded as INSIDE the project and found nowhere: refusing beats
    // certifying the loss. A save that proceeded here would write an
    // archive without the asset and rename it over whatever still held
    // the bytes — and the session would then forget the asset was ever
    // embedded. (An asset that was never carried in simply stays LEFT
    // OUT, per the doc above — that one is a findable absence the relink
    // flow exists for.)
    if (mediaEntryHeld(mediaInFile, carry)) {
      throw StateError(
        'media "${carry.poolPath}" is recorded inside the project, but '
        'neither the archive nor the original file holds its bytes — '
        'saving now would make that loss permanent',
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
          sources[name] = MediaArchiveBytes.ofEntry(
            archivePath: projectFilePath!,
            entry: entry,
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
/// stored [sources]: pool path → the entry its carry was written under.
///
/// ⚠️Keyed by the PATH for the manifest, where that is safe — a saved
/// project names one carry per path. The session keeps only the names
/// ([mediaEntryHeld]): within a session one path can have been carried
/// twice.
Map<String, String> mediaEntryNamesFor(
  Map<MediaCarry, MediaByteSource> sources,
) => {
  for (final entry in sources.entries)
    entry.key.poolPath: anicelMediaEntryName(
      entry.key,
      framed: entry.value.storedIsFramed,
    ),
};
