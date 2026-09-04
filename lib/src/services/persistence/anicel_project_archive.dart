/// The .anicel container (P3): ONE self-contained ZIP — `project.json`
/// (timeline + metadata, with a formatVersion), `cels/<n>.bin` (baked tile
/// rasters, compressed — zstd or the deflate floor) and `media/<hash>-<name>` (the assets
/// the project carries).
///
/// Drawings AND media live INSIDE the file — user direction, no scattered
/// sidecars. WHICH media travels is [MediaAsset.carried] and nothing else:
/// the import window sets it, and the kind only chooses that flag's
/// DEFAULT (video starts as a reference, the rest start carried).
///
/// 🪦This paragraph used to say「decided by KIND … video stays a
/// reference」. That ceiling died 2026-08-14 — a movie the user had
/// explicitly asked the project to hold was being dropped on the way to
/// the archive, the flag saying yes while the save said no. The size
/// protection moved to the [largeCarriedAssetBytes] warning, which is a
/// warning and never a refusal: it is their file and their disk.
///
/// A referenced file keeps a save-directory-relative path so a Drive
/// folder opened on another machine relinks by itself, and its
/// security-scoped token rides along in `grants` so the next launch can
/// still open it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/audio_clip.dart';
import '../../models/brush_frame_key.dart';
import '../../models/project.dart';
import '../media/media_fingerprints.dart';
import 'anicel_payload_codec.dart';
import 'brush_drawing_binary_codec.dart';
import 'media_blob_codec.dart';

/// The project file's extension, without the dot — what a picker filter
/// wants. Every filter, suffix check and suggested filename reads it from
/// here; spelled out at each site instead, a rename would have to find
/// eight of them and would silently half-work if it missed one.
const String anicelProjectExtension = 'anicel';

/// The same thing with the dot, for `endsWith` and filename building.
const String anicelProjectSuffix = '.$anicelProjectExtension';

/// v3 (R20-A1 cold-cel tiering): cels persist as PRE-COMPRESSED blobs
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
/// pixels still compressed) and the saved relative-path manifest
/// ({absolute path at save time: save-dir-relative path}).
class AnicelArchiveContents {
  const AnicelArchiveContents({
    required this.project,
    required this.cels,
    required this.mediaRelativePaths,
    this.grants = const [],
    this.mediaFingerprints = const MediaFingerprints.empty(),
  });

  final Project project;
  final List<AnicelCelBlob> cels;
  final Map<String, String> mediaRelativePaths;

  /// What the project knows about its media's CONTENT, for telling one
  /// `A1.png` from another when a reference has to be found again. Empty
  /// for every project written before they were kept.
  final MediaFingerprints mediaFingerprints;

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

/// Where a carried CONFORM lives — the decoded, resampled PCM of a piece
/// of the project's audio.
///
/// 🚨★★★**A SEPARATE PREFIX BECAUSE IT IS A DIFFERENT KIND OF THING.**
/// Media is the user's content and cannot be rebuilt; a conform is derived
/// and can. Sharing `media/` would have made「which of these can I drop」
/// a question nothing could answer, and dropping is the whole reason the
/// settings-change sweep exists.
const String anicelConformEntryPrefix = 'conform/';

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
/// 🚨**CONFORMS COUNT AS MEDIA HERE**, and the reason is the sentence
/// above rather than what they are. What the exclusion is really about is
/// bulk a rewrite has to copy FOR NOTHING, and a carried conform is the
/// bulkiest thing in an audio project — an hour of dialogue is ~428MB
/// compressed against a cel area of a few tens. Leaving it in the
/// denominator is the same bug the media exclusion was written to fix,
/// only larger.
///
/// ⚠️Unlike media, a conform CAN be shadowed: it is derived, and a rebuilt
/// one is re-streamed under the same name. That garbage is counted like
/// any other — it is only the denominator this changes — so a conform that
/// really was replaced still asks for the compaction that reclaims it.
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
    if (entry.name.startsWith(anicelMediaEntryPrefix) ||
        entry.name.startsWith(anicelConformEntryPrefix)) {
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
///
/// 🚨[framed] appends [mediaFramedEntrySuffix]. The name is what tells a
/// reader whether the entry holds a framed blob or the file itself — see
/// [MediaBlobHeader] for why it is the name and not a byte at the front.
String anicelMediaEntryName(String poolPath, {bool framed = false}) =>
    _anicelPoolEntryName(anicelMediaEntryPrefix, poolPath, framed: framed);

/// The archive entry a piece of media's CONFORM is stored under.
///
/// The same derivation as [anicelMediaEntryName] under a different prefix,
/// so one asset's audio and its conform sit side by side and are found the
/// same way. 유저 2026-08-30 chose to carry these (`conform-in-project` =
/// always): opening the project on another machine plays immediately
/// instead of decoding every sound first.
///
/// 🚨★★★**THE SETTINGS ARE IN THE NAME, AND THAT IS WHAT MAKES THE SWEEP
/// SAFE.** A conform's contents depend on the project's sample rate and
/// audio speed, so an entry built under others is dead — and the sweep has
/// to be able to say so without reading anything.
///
/// 🪦The first shape of this left them OUT and swept by「is there a
/// conform at the current settings' cache path」. That question has two
/// meanings and they are not the same: **the cache is also empty on a
/// machine that has only just opened the project.** Open it somewhere new,
/// draw one stroke, save — and every conform the file carried would have
/// been swept as dead, on the exact journey carrying them exists to serve.
/// One condition answering two questions is the shape this repo has been
/// burned by before ([[never-invent-a-convenience-rule]]).
///
/// With the settings in the name, the two separate cleanly:
///
/// - **settings changed** → the current settings' name is nowhere, so
///   nothing is carried under it and the old name is not one this project
///   may hold. Removed.
/// - **not built here yet** → the name is the same one the archive already
///   holds, so the entry survives untouched, and the save streams nothing.
///
/// ⚠️Which also means the ONE conform per asset that this promises is a
/// property of the SWEEP, not of the name: nothing stops a file holding
/// two, and the incremental save is what takes the other away.
String anicelConformEntryName(
  String poolPath, {
  required int sampleRate,
  required int speedNumerator,
  required int speedDenominator,
  bool framed = false,
}) => _anicelPoolEntryName(
  anicelConformEntryPrefix,
  poolPath,
  framed: framed,
  // Readable rather than folded into the hash: someone looking inside a
  // `.anicel` should be able to see WHY there are two conforms of one
  // sound, and the answer is right there in the name.
  infix: '$sampleRate-${speedNumerator}x$speedDenominator',
);

/// Every name [poolPath]'s conform may legitimately wear at these settings
/// — both spellings, because whether it compressed is a property of the
/// bytes.
List<String> anicelConformEntryNames(
  String poolPath, {
  required int sampleRate,
  required int speedNumerator,
  required int speedDenominator,
}) => [
  for (final framed in const [true, false])
    anicelConformEntryName(
      poolPath,
      sampleRate: sampleRate,
      speedNumerator: speedNumerator,
      speedDenominator: speedDenominator,
      framed: framed,
    ),
];

/// One derivation for both, so a media entry and its conform can never
/// disagree about which asset they belong to.
String _anicelPoolEntryName(
  String prefix,
  String poolPath, {
  required bool framed,
  String infix = '',
}) {
  final normalized = poolPath.replaceAll('\\', '/');
  var hash = 0x811c9dc5;
  for (final unit in normalized.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final base = normalized.split('/').last;
  final safe = base.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
  return '$prefix${hash.toRadixString(16).padLeft(8, '0')}'
      '${infix.isEmpty ? '' : '-$infix'}'
      '-$safe${framed ? mediaFramedEntrySuffix : ''}';
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
/// The entry the project manifest lives in.
///
/// 🚨★★★**Two names, and the reader prefers the compressed one.** The
/// JSON compresses ~14× (measured: 53,910 → 3,899 on a small project with
/// deflate, before zstd; the file service notes it「can be megabytes」on a
/// large one), but the archive STOREs every entry on purpose — the
/// incremental appender needs `bytes == the payload` to hand out file
/// refs. So the compression goes INSIDE our format, exactly the way a
/// `.celz` carries its own.
///
/// ⛔The suffix is not decoration: a person opening a `.anicel` with an
/// unzip tool should be able to tell what they are looking at, and
/// `project.json` holding compressed bytes would lie to them.
const String anicelProjectEntryName = 'project.json';
const String anicelProjectEntryNameCompressed = 'project.json.z';

/// The entry a save should WRITE: the compressed one, always.
///
/// The bytes are a codec byte followed by the payload — the same shape a
/// cel blob's tail has, through the same [compressAnicelPayload], so zstd
/// and the deflate floor are chosen in ONE place for both.
///
/// Old files keep their uncompressed `project.json` and still open. The
/// reader takes whichever it finds, preferring the compressed name so an
/// incremental append can shadow the old entry without a compaction.
({String name, Uint8List bytes}) buildAnicelProjectEntry({
  required Project project,
  String? saveDirectory,
  Set<String> mediaInArchive = const {},
  List<Map<String, Object?>> grants = const [],
  Map<String, Object?> mediaCrcs = const {},
}) {
  final compressed = compressAnicelPayload(
    buildAnicelProjectJsonBytes(
      project: project,
      saveDirectory: saveDirectory,
      mediaInArchive: mediaInArchive,
      grants: grants,
      mediaCrcs: mediaCrcs,
    ),
  );
  return (
    name: anicelProjectEntryNameCompressed,
    bytes: Uint8List.fromList([compressed.codec, ...compressed.bytes]),
  );
}

/// The manifest bytes an entry holds — decompressed when the entry is the
/// compressed one, handed back as-is when it is an old `project.json`.
///
/// 🚨ONE function, because every reader asks the same question and the
/// NAME is the only thing that answers it. A reader that forgot would put
/// compressed bytes into `jsonDecode` and report a corrupt project — which
/// is exactly what happened to the ownership check on the save path, and
/// it turned every save into a full rewrite without failing anything.
Uint8List decodeAnicelProjectEntryBytes(String name, Uint8List bytes) {
  if (name != anicelProjectEntryNameCompressed) {
    return bytes;
  }
  // ⛔`bytes.first` on an empty entry is `StateError: No element`, and
  // `_showFileError` puts whatever is thrown on the screen verbatim. A
  // truncated archive is a thing that happens; answering it with a Dart
  // collection error tells the person nothing about their file.
  if (bytes.isEmpty) {
    throw const FormatException(
      'this project has an empty manifest — the file is truncated',
    );
  }
  return decompressAnicelPayload(bytes.first, Uint8List.sublistView(bytes, 1));
}

/// writes down what it is handed.
Uint8List buildAnicelProjectJsonBytes({
  required Project project,
  String? saveDirectory,
  Set<String> mediaInArchive = const {},
  List<Map<String, Object?>> grants = const [],

  /// Pool path → CRC-32 hex, for the assets somebody has read the bytes of.
  /// Kept out of `project` on purpose — see [MediaFingerprints].
  Map<String, Object?> mediaCrcs = const {},
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
        if (mediaCrcs.isNotEmpty) 'mediaCrcs': mediaCrcs,
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
/// ⚠️ Keep it READ-compatible with the streaming writer or fixtures stop
/// standing in for what production writes. Not byte-compatible, and that
/// is deliberate: production always writes the ZIP64 records
/// (`anicelAlwaysZip64`) while `ZipEncoder` here writes plain ZIP — so a
/// fixture built here also exercises the "older (plain) files still
/// open" half of the reader contract (zip64_test: "a reader opens both
/// shapes, whichever wrote the file"). Both writers are pinned against
/// `parseAnicelArchiveBytes`, which is what makes all of it checkable.
Uint8List buildAnicelArchiveBytes({
  required Project project,
  required List<AnicelCelBlob> cels,
  String? saveDirectory,
  List<Map<String, Object?>> grants = const [],
  Map<String, Object?> mediaCrcs = const {},
}) {
  // R22-C: EVERY entry is STORE'd — readers (and the file-backed cold
  // tier) address raw bytes by {offset, length} without inflating.
  final projectEntry = buildAnicelProjectEntry(
    project: project,
    saveDirectory: saveDirectory,
    grants: grants,
    mediaCrcs: mediaCrcs,
  );
  final archive = Archive()
    ..add(
      ArchiveFile.bytes(projectEntry.name, projectEntry.bytes)
        ..compression = CompressionType.none,
    );
  // v3: cel blobs carry their own compression — STORE them as-is (an
  // inner deflate over a zstd frame would only burn CPU). Entry names are
  // stable per key so later incremental appends shadow them.
  for (final cel in cels) {
    archive.add(
      ArchiveFile.bytes(anicelCelEntryName(cel.key), cel.bytes)
        ..compression = CompressionType.none,
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

/// The project a `.anicel`'s `project.json` bytes hold, with its format
/// version already checked, plus the raw document for the fields around it.
///
/// ⛔BOTH READERS COME THROUGH HERE. The streaming open and the
/// whole-archive parse each decoded, version-checked and rebuilt the
/// project on their own; a reader that lost the check would open a file
/// saved by a NEWER Anicel and silently drop everything it did not
/// understand — which is a project the user then saves back, shortened.
({Project project, Map<String, dynamic> json}) decodeAnicelProjectDocument(
  List<int> projectBytes,
) {
  final decoded = jsonDecode(utf8.decode(projectBytes)) as Map<String, dynamic>;
  if ((decoded['formatVersion'] as int? ?? 0) > anicelFormatVersion) {
    throw const FormatException('This project was saved by a newer Anicel.');
  }
  return (
    project: Project.fromJson(decoded['project'] as Map<String, dynamic>),
    json: decoded,
  );
}

/// A document field read as a `{string: string}` map — anything that is
/// not a string pair is not one, and is left out rather than throwing.
Map<String, String> anicelStringMapField(Object? json) => {
  if (json is Map)
    for (final entry in json.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
};

/// Parses .anicel bytes; throws [FormatException] on a newer format or a
/// missing project entry.
AnicelArchiveContents parseAnicelArchiveBytes(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  // The compressed entry wins when both are present: an incremental append
  // shadows an old `project.json` by adding `project.json.z` beside it,
  // and until a compaction rewrites the file the stale one is still there.
  final compressed = archive.find(anicelProjectEntryNameCompressed);
  final projectEntry = compressed ?? archive.find(anicelProjectEntryName);
  if (projectEntry == null) {
    throw const FormatException('Not an Anicel project (.anicel).');
  }
  final projectBytes = decodeAnicelProjectEntryBytes(
    projectEntry.name,
    projectEntry.readBytes()!,
  );
  final document = decodeAnicelProjectDocument(projectBytes);
  final project = document.project;
  final decoded = document.json;
  final mediaRelativePaths = anicelStringMapField(decoded['mediaPaths']);

  // v3 truth: cold cel blobs — header parse only, pixels stay compressed
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
    mediaFingerprints: MediaFingerprints.fromJson(decoded['mediaCrcs']),
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
