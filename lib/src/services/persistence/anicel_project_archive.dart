/// The .anicel container (P3): ONE self-contained ZIP — `project.json`
/// (timeline + metadata, with a formatVersion) and `cels/<n>.bin` (baked
/// tile rasters; deflate does the rest). Drawings live INSIDE the file
/// (user direction: no scattered sidecars); media stays EXTERNAL
/// Premiere-style, with save-directory-relative paths recorded so a Drive
/// folder opened on another machine relinks by itself.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/audio_clip.dart';
import '../../models/brush_frame_key.dart';
import '../../models/project.dart';
import 'brush_drawing_binary_codec.dart';

/// The project file's extension, without the dot — what a picker filter
/// wants. Every filter, suffix check and suggested filename reads it from
/// here; spelled out at each site instead, a rename would have to find
/// eight of them and would silently half-work if it missed one.
const String anicelProjectExtension = 'anicel';

/// The same thing with the dot, for `endsWith` and filename building.
const String anicelProjectSuffix = '.$anicelProjectExtension';

/// v3 (R20-A1 cold-cel tiering): cels persist as PRE-DEFLATED blobs
/// (`cels/<n>.celz`, STORE'd — the payload is already compressed). The
/// blob layout is identical to the in-RAM cold-cel form, so untouched
/// cold cels save with zero re-encode and opens keep every cel cold
/// (no pixel decode) until first access. The v1 command-drawing reader
/// is DELETED (R20-E3) and the v2 raw-cel reader retired with the format
/// bump: no production file of either version exists (user-confirmed);
/// legacy entries are simply ignored.
const int anicelFormatVersion = 3;

/// A parsed .anicel archive: the project (media paths NOT yet resolved — see
/// [remapProjectMediaPaths]), its baked cels in COLD form (headers parsed,
/// pixels still deflated) and the saved relative-path manifest
/// ({absolute path at save time: save-dir-relative path}).
class AnicelArchiveContents {
  const AnicelArchiveContents({
    required this.project,
    required this.cels,
    required this.mediaRelativePaths,
    this.grants = const [],
  });

  final Project project;
  final List<AnicelCelBlob> cels;
  final Map<String, String> mediaRelativePaths;

  /// Security-scoped tokens for the media this project REFERENCES, as
  /// they were written. Empty everywhere a path is durable on its own, and
  /// empty for every project written before they were kept.
  ///
  /// Raw JSON, for the same reason the writer takes raw JSON: the type
  /// that understands these cannot be imported here. The session decodes
  /// them.
  ///
  /// ⚠️ Not yet resolved either — a bookmark has to be handed back to the
  /// OS to become usable, and that answer may carry a DIFFERENT path (a
  /// bookmark follows a file that moved).
  final List<Map<String, Object?>> grants;
}

/// Everything media lives under, so the save path can tell an asset's
/// bytes from a cel's by name alone.
const String anicelMediaEntryPrefix = 'media/';

/// What fraction of the media a rewrite must copy for nothing has to be
/// reclaimed before that copying is worth doing.
///
/// A rewrite streams every asset through to the new file whether or not
/// anything about it changed, so a project carrying five hundred megabytes
/// of sound pays five hundred megabytes to reclaim whatever the cels left
/// behind. At five percent that asks for twenty-five megabytes of waste
/// before it will — and a project with NO media pays nothing, so the rule
/// leaves the old behaviour exactly where it was.
const double anicelMediaRewriteRatio = 0.05;

/// Whether an append would leave more dead bytes behind than it is worth,
/// given the file's size and what its live entries weigh.
///
/// 🔑 Media is out of the DENOMINATOR, not out of the garbage — it makes
/// none. An imported sound is written once and never shadowed, so it can
/// only dilute the ratio: five hundred megabytes of media beside ten of
/// cels turns eight megabytes of dead cel bytes into 1.6% of the file, and
/// compaction stops running at all while the cel area fills with garbage
/// indefinitely. Judging the part that actually rots keeps the threshold
/// meaning what it always meant.
///
/// A named function rather than four lines inside the save isolate,
/// because it is a rule and rules need somewhere to be checked.
bool anicelNeedsCompaction({
  required int fileLength,
  required Iterable<({String name, int length})> entries,
  double garbageRatio = 0.5,
  double mediaRewriteRatio = anicelMediaRewriteRatio,
}) {
  var activeBytes = 0;
  var activeMediaBytes = 0;
  for (final entry in entries) {
    activeBytes += entry.length;
    if (entry.name.startsWith(anicelMediaEntryPrefix)) {
      activeMediaBytes += entry.length;
    }
  }
  final garbageBytes = fileLength - activeBytes;
  // A floor as well as a ratio, and taking media out of the denominator is
  // what made it necessary. The rotting area is now just the cels and
  // `project.json`, which in a project that is mostly sound can be a few
  // kilobytes — so two superseded copies of `project.json` cross fifty
  // percent of it and ask for a rewrite that re-streams every megabyte of
  // media to reclaim four.
  //
  // Proportional to that copying rather than a flat number, deliberately:
  // a project with no media pays nothing to be rewritten, so it keeps
  // exactly the behaviour it always had, while one carrying half a
  // gigabyte has to be wasting a proportionate amount before it is worth
  // moving those bytes again.
  if (garbageBytes < activeMediaBytes * mediaRewriteRatio) {
    return false;
  }
  final rottingBytes = fileLength - activeMediaBytes;
  if (rottingBytes <= 0) {
    return false;
  }
  return garbageBytes > rottingBytes * garbageRatio;
}

/// The archive entry a piece of media is stored under.
///
/// Derived from the pool path so the same asset lands on the same name
/// every save — the entry has to be findable again after a compaction has
/// moved every byte in the file, and the only thing that survives that is
/// the name. The basename rides along ahead of the hash because a person
/// looking inside a `.anicel` with an unzip tool should be able to tell
/// what they are looking at.
///
/// ⚠️ Not derived from CONTENT. Two identical files imported under
/// different names are two assets to the pool, and giving them one entry
/// would make deleting either take the other's bytes with it.
String anicelMediaEntryName(String poolPath) {
  final normalized = poolPath.replaceAll('\\', '/');
  var hash = 0x811c9dc5;
  for (final unit in normalized.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final base = normalized.split('/').last;
  final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return '$anicelMediaEntryPrefix${hash.toRadixString(16).padLeft(8, '0')}'
      '-$safe';
}

/// The cel's STABLE archive entry name (R22-C): derived from the key
/// alone, so an incremental append of the same cel SHADOWS its previous
/// entry by name. Base64url over the NUL-joined key parts — reversible,
/// collision-free, and filename-safe regardless of what the ids contain.
String anicelCelEntryName(BrushFrameKey key) {
  final joined = [
    key.projectId.value,
    key.trackId.value,
    key.cutId.value,
    key.layerId.value,
    key.frameId.value,
  ].join('\u0000');
  final encoded = base64Url.encode(utf8.encode(joined)).replaceAll('=', '');
  return 'cels/$encoded.celz';
}

/// The `project.json` payload bytes — shared verbatim by the full-archive
/// builder and the incremental appender so both save paths write the
/// identical entry. [saveDirectory] (the file's parent, normalized with
/// forward slashes) keys the relative-path manifest: media living under
/// it is recorded relative, everything else stays absolute-only.
/// [grants] are the security-scoped tokens the project needs to reopen the
/// media it REFERENCES — top level, beside `mediaPaths`, because they are
/// bookkeeping about the machine rather than anything about the film.
///
/// ⛔ Deliberately not on [Project]. Apple re-issues a bookmark on every
/// resolve, so a grant that lived in the model would mark the project
/// dirty every time it was opened — an edit the user never made, and a
/// "save your changes?" they cannot explain.
///
/// 🔑 Taken as plain JSON rather than as the picker's grant type. This
/// runs inside the save isolate, and the type lives in a file that reaches
/// for `file_selector` and a `MethodChannel` — neither of which works
/// there. Deciding WHICH grants are worth keeping needs to know what the
/// project references, which is the session's business anyway; the format
/// writes down what it is handed.
Uint8List buildAnicelProjectJsonBytes({
  required Project project,
  String? saveDirectory,
  Set<String> mediaInArchive = const {},
  List<Map<String, Object?>> grants = const [],
}) {
  final mediaRelativePaths = <String, String>{};
  final mediaEntries = <String, String>{};
  for (final path in projectMediaPaths(project)) {
    // Two ways for the project to find its media again, and which one
    // applies is a property of the asset, not of the project: what lives
    // INSIDE travels with the file and can never be lost or moved, while
    // what stays outside is a path that may or may not still resolve.
    // Inside wins where both could describe the same asset — the copy the
    // project carries is the one it is sure of.
    if (mediaInArchive.contains(path)) {
      mediaEntries[path] = anicelMediaEntryName(path);
      continue;
    }
    if (saveDirectory != null) {
      final relative = _relativeTo(path, saveDirectory);
      if (relative != null) {
        mediaRelativePaths[path] = relative;
      }
    }
  }
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'formatVersion': anicelFormatVersion,
        'project': project.toJson(),
        if (mediaRelativePaths.isNotEmpty) 'mediaPaths': mediaRelativePaths,
        if (mediaEntries.isNotEmpty) 'mediaEntries': mediaEntries,
        if (grants.isNotEmpty) 'grants': grants,
      }),
    ),
  );
}

/// Builds the .anicel bytes whole, IN MEMORY.
///
/// No longer how a SAVE writes: `writeAnicelArchiveFile` streams entry by
/// entry so a full save never holds the project twice. This survives
/// because it can hand back BYTES without a file — which is what fixtures
/// want, and what `tool/cut_scale_project.dart` builds with.
///
/// ⚠️ Keep it byte-compatible with the streaming writer or fixtures stop
/// standing in for what production writes. Both are pinned against
/// `parseAnicelArchiveBytes`, which is what makes that checkable.
Uint8List buildAnicelArchiveBytes({
  required Project project,
  required List<AnicelCelBlob> cels,
  String? saveDirectory,
}) {
  // R22-C: EVERY entry is STORE'd — readers (and the file-backed cold
  // tier) address raw bytes by {offset, length} without inflating.
  final archive = Archive()
    ..add(
      ArchiveFile.bytes(
        'project.json',
        buildAnicelProjectJsonBytes(project: project, saveDirectory: saveDirectory),
      )..compression = CompressionType.none,
    );
  // v3: cel blobs are already deflated — STORE them as-is (an inner
  // deflate-of-deflate would only burn CPU). Entry names are stable per
  // key so later incremental appends shadow them.
  for (final cel in cels) {
    archive.add(
      ArchiveFile.bytes(anicelCelEntryName(cel.key), cel.bytes)
        ..compression = CompressionType.none,
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Parses .anicel bytes; throws [FormatException] on a newer format or a
/// missing project entry.
AnicelArchiveContents parseAnicelArchiveBytes(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  final projectEntry = archive.find('project.json');
  if (projectEntry == null) {
    throw const FormatException('Not an Anicel project (.anicel).');
  }
  final decoded =
      jsonDecode(utf8.decode(projectEntry.readBytes()!))
          as Map<String, dynamic>;
  if ((decoded['formatVersion'] as int? ?? 0) > anicelFormatVersion) {
    throw const FormatException(
      'This project was saved by a newer Anicel.',
    );
  }
  final project = Project.fromJson(decoded['project'] as Map<String, dynamic>);
  final mediaPathsJson = decoded['mediaPaths'];
  final mediaRelativePaths = <String, String>{
    if (mediaPathsJson is Map)
      for (final entry in mediaPathsJson.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
  };

  // v3 truth: cold cel blobs — header parse only, pixels stay deflated
  // until the store's first access. (v1 drawings/tips and v2 cels/*.bin
  // entries are ignored — readers deleted, no production file exists.)
  final cels = <AnicelCelBlob>[
    for (final file in archive.files)
      if (file.isFile && file.name.endsWith('.celz'))
        AnicelCelBlob(file.readBytes()!),
  ];

  final grantsJson = decoded['grants'];
  final grants = <Map<String, Object?>>[
    if (grantsJson is List)
      for (final entry in grantsJson)
        if (entry is Map)
          {
            for (final field in entry.entries)
              if (field.key is String) field.key as String: field.value,
          },
  ];

  return AnicelArchiveContents(
    project: project,
    cels: cels,
    mediaRelativePaths: mediaRelativePaths,
    grants: grants,
  );
}

/// Rewrites the project's media references ({old path: new path}) — the
/// pool entries AND every SE audio clip (cut- and track-owned) so links
/// stay consistent. Unmapped paths pass through.
Project remapProjectMediaPaths(Project project, Map<String, String> oldToNew) {
  if (oldToNew.isEmpty) {
    return project;
  }
  String remap(String path) => oldToNew[path] ?? path;
  List<AudioClip> remapClips(List<AudioClip> clips) => [
    for (final clip in clips) clip.copyWith(filePath: remap(clip.filePath)),
  ];

  return project.copyWith(
    mediaAssets: [
      for (final asset in project.mediaAssets)
        asset.copyWith(path: remap(asset.path)),
    ],
    tracks: [
      for (final track in project.tracks)
        track.copyWith(
          seLayers: [
            for (final layer in track.seLayers)
              layer.audioClips.isEmpty
                  ? layer
                  : layer.copyWith(audioClips: remapClips(layer.audioClips)),
          ],
          cuts: [
            for (final cut in track.cuts)
              cut.copyWith(
                layers: [
                  for (final layer in cut.layers)
                    layer.audioClips.isEmpty
                        ? layer
                        : layer.copyWith(
                            audioClips: remapClips(layer.audioClips),
                          ),
                ],
              ),
          ],
        ),
    ],
  );
}

/// The distinct media file paths a project references (pool + clips).
///
/// Public because the session asks the same question when it decides which
/// grants are still worth saving — the alternative was a second walk of
/// the same tree that could drift from this one.
Set<String> projectMediaPaths(Project project) {
  final paths = <String>{for (final asset in project.mediaAssets) asset.path};
  for (final track in project.tracks) {
    for (final layer in track.seLayers) {
      for (final clip in layer.audioClips) {
        paths.add(clip.filePath);
      }
    }
    for (final cut in track.cuts) {
      for (final layer in cut.layers) {
        for (final clip in layer.audioClips) {
          paths.add(clip.filePath);
        }
      }
    }
  }
  return paths;
}

/// [path] relative to [directory] when it lives underneath it (separator-
/// and case-insensitively on the drive prefix); null otherwise. Forward
/// slashes throughout so the manifest is portable across platforms.
String? _relativeTo(String path, String directory) {
  final normalizedPath = path.replaceAll('\\', '/');
  var normalizedDirectory = directory.replaceAll('\\', '/');
  if (!normalizedDirectory.endsWith('/')) {
    normalizedDirectory = '$normalizedDirectory/';
  }
  if (normalizedPath.toLowerCase().startsWith(
    normalizedDirectory.toLowerCase(),
  )) {
    return normalizedPath.substring(normalizedDirectory.length);
  }
  return null;
}
