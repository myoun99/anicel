import 'dart:math' as math;

import '../core/path_names.dart' show fileNameOfPath, pathHash;
import 'media_identity.dart';

export 'media_identity.dart' show MediaIdentity, MediaIdentityMatch;

/// One 품기 of a file: the pool path it is at now, and WHICH carry
/// ([MediaAsset.carriedAs]).
///
/// Everything that keeps a carried file's bytes — the staged copy, the
/// project file's entry — is named from this ([mediaCarryName]), never from
/// the path alone.
typedef MediaCarry = ({String poolPath, String token});

/// A fresh [MediaAsset.carriedAs] for carrying [poolPath], one per 품기 —
/// the NAME its bytes are stored under for good,
/// `<path hash>-<random>-<file name>` ([mediaCarryName]).
///
/// ⚠️Minted, not derived. Not from the path — two carries of one path are
/// the whole reason this exists — and not from the content either: the
/// staged copy is written UNDER this name, so it has to exist before the
/// bytes are read, and hashing them first would read a multi-gigabyte
/// movie once more just to learn what to call it.
///
/// 🚨★★★**THE WHOLE NAME IS MINTED, NOT ONLY ITS RANDOM PART.** Until
/// 09-25 only the middle was, and the rest was derived from the path each
/// time it was asked for — so a relink, which moves an asset's path and
/// keeps its carry, gave the same bytes a new name: the staged copy was
/// RENAMED after it, an undo of the relink looked for the old name and
/// found nothing, and a save wrote the entry again under the new one
/// (audit 09-25). Minted whole, the name goes where the carry goes, and an
/// undo finds its bytes before a save and after one. The path's parts stay
/// in it so a person looking in the staging room, or inside a `.anicel`,
/// can tell what they are looking at.
String mintMediaCarry(String poolPath) => _carryName(
  poolPath,
  _carryTokens.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
);

final math.Random _carryTokens = math.Random.secure();

/// The name [carry]'s bytes are stored under — the staged copy's, and the
/// project file entry's behind `media/`.
///
/// A name minted whole ([mintMediaCarry]) is itself. A carry from before
/// that — `''` for the one a project had before carries had names, a bare
/// token for one minted before 09-25 — gets the name the same rule gives
/// it from the path it is at now, which is what those projects hold.
String mediaCarryName(MediaCarry carry) => carry.token.contains('-')
    ? carry.token
    : _carryName(carry.poolPath, carry.token);

String _carryName(String poolPath, String token) {
  final (:hash, :safe) = mediaNameParts(poolPath);
  return token.isEmpty ? '$hash-$safe' : '$hash-$token-$safe';
}

/// A pool path's two halves of every name its bytes are stored under: the
/// path's hash ([pathHash]) and its file name made safe for any file
/// system.
///
/// 🚨★★★**ONE DERIVATION FOR THE PROJECT FILE AND THE STAGING ROOM.** The
/// staged copy's name and the archive entry's were the same algorithm
/// written twice — the same hash, the same sanitising, the same token rule
/// — and were fixed side by side when carries got names (audit 09-25,
/// connascence). Carries ([mintMediaCarry]), conforms and the room's walk
/// for a path nobody holds all ask here.
({String hash, String safe}) mediaNameParts(String poolPath) {
  final normalized = normalizedMediaPath(poolPath);
  return (
    hash: pathHash(normalized).toRadixString(16).padLeft(8, '0'),
    safe: fileNameOfPath(
      normalized,
    ).replaceAll(RegExp('[^A-Za-z0-9._-]'), '_'),
  );
}

/// What a media pool entry holds.
enum MediaAssetKind {
  audio('audio'),
  image('image'),
  video('video'),
  pdf('pdf');

  const MediaAssetKind(this.jsonValue);

  final String jsonValue;

  String toJson() => jsonValue;

  /// Unknown or absent values decode to [audio] so files stay open-able
  /// across versions.
  static MediaAssetKind fromJson(Object? json) {
    for (final value in values) {
      if (value.jsonValue == json) {
        return value;
      }
    }
    return audio;
  }
}

/// How a placed picture meets the cut's canvas (§6-q: fit is a PLACEMENT
/// decision, not a registration one).
enum MediaFitMode {
  /// Stretch to the canvas, ignoring aspect (Premiere's Scale to Frame).
  stretch('stretch'),

  /// Fit inside the canvas keeping aspect (Set to Frame Size) — default.
  contain('contain'),

  /// 1:1, centered — the pasteboard keeps the overflow alive.
  none('none');

  const MediaFitMode(this.jsonValue);

  final String jsonValue;

  String toJson() => jsonValue;

  static MediaFitMode fromJson(Object? json) {
    for (final value in values) {
      if (value.jsonValue == json) {
        return value;
      }
    }
    return contain;
  }
}

/// One entry of the project's media pool (the Premiere/Resolve-style
/// browser): a file the project references, under a user-facing display
/// name.
///
/// The pool is keyed by the ABSOLUTE file path — clips reference sounds by
/// path ([AudioClip.filePath]), so an asset is that path's metadata plus
/// the browse/reuse surface. Relinking a moved file rewrites the path here
/// AND on every referencing clip in one undo step (the Resolve offline →
/// relink flow); nothing else about the link model changes.
///
/// PLACEMENT-PRESET fields (§6-l/§6-z10: asset = placement defaults,
/// instance = actual values): [offsetFrames], [lengthFrames] and [fitMode]
/// seed a placement and are user-editable per asset. SOURCE-TRACKING
/// fields ([sourcePath], [sourceStamp]) power the "original changed"
/// badge for COPIED assets (§6-g): the copy stays the truth, the badge
/// only offers re-import.
///
/// [identity] is the one that looks like source-tracking and is not. It
/// describes the file at [path] rather than the origin, it is recorded for
/// REFERENCES as much as copies, and it answers "which file is this?" so
/// relink can recognize one that moved. The stamp cannot do that job —
/// it carries an mtime precisely so it CAN notice a touched file, which is
/// the opposite requirement. Detection-only metadata ([sourceFps],
/// [frameCount], [pageCount]) is recorded at registration and never
/// forces a policy (§6-x).
class MediaAsset {
  MediaAsset({
    required String path,
    required this.name,
    this.kind = MediaAssetKind.audio,
    this.offsetFrames = 0,
    this.lengthFrames,
    this.fitMode = MediaFitMode.contain,
    this.sourcePath,
    this.sourceStamp,
    this.carriedAs,
    this.identity,
    this.sourceFps,
    this.frameCount,
    this.pageCount,
    this.dialogue,
  }) : path = normalizedMediaPath(path);

  /// Absolute file path — the pool key clips reference — in the one
  /// spelling [normalizedMediaPath] gives it, whatever door it came by.
  final String path;

  /// Display name WITHOUT the extension — the path keeps that; seeds with
  /// [mediaAssetDefaultName] and is user-editable. What a placement names
  /// the rows it makes with ([mediaAssetNameFor]).
  final String name;

  final MediaAssetKind kind;

  /// Placement default: source frames skipped before the block starts.
  final int offsetFrames;

  /// Placement default: block length; null = the source's own length
  /// (an image's default is decided at placement — §6-u: length is a
  /// placement property, not a source one).
  final int? lengthFrames;

  /// Placement default: how the picture meets the canvas.
  final MediaFitMode fitMode;

  /// The ORIGINAL path this asset was copied from (null = the asset was
  /// referenced in place, or predates tracking). Copies keep remembering
  /// their origin so the "original changed → re-import" badge works
  /// (§6-g) without giving up the copy's portability.
  ///
  /// 🚨★★★**ONLY A COPY HAS ONE, AND A RELINK NEVER WRITES ONE.** Source
  /// tracking is what a COPY carries so the badge has two paths to
  /// compare; a relink of a file that MOVED has only ever had one path,
  /// and the new location is not an origin.
  ///
  /// 🪦That used to be said by a `recordSource` flag on the relink command
  /// — and the flag answered two questions at once (「is this a copy?」 and
  /// 「write the origin?」), which is the shape this codebase treats as an
  /// invention. Nothing in `lib/` ever passed it `true`; one test did. The
  /// flag is gone and the answer is structural: `copyWith(path:)` keeps
  /// what it is not given, so a relink leaves whatever tracking was there
  /// and whoever MAKES a copy is the one that writes these two.
  final String? sourcePath;

  /// Change-detection stamp of the source at copy/registration time
  /// (mtime+size fingerprint); null = never stamped.
  ///
  /// ⚠️ Answers "did the original change?", NOT "is this the same file?".
  /// It carries a modification time, so it stops matching when a file is
  /// moved or restored — use [identity] for that question.
  final String? sourceStamp;

  /// Whether the project should CARRY this asset's bytes rather than
  /// point at them.
  ///
  /// The import window's copy-or-reference choice, kept as what the user
  /// meant rather than inferred from [sourcePath] — that field records
  /// where an asset CAME FROM, which is a different question and stops
  /// being a usable proxy the moment carrying no longer means copying a
  /// file somewhere first.
  ///
  /// 🔑 This flag is the WHOLE answer at save time. The kind stopped being
  /// a ceiling on 2026-08-14 and stopped picking even the import default on
  /// 2026-09-16, when the size warning that had taken the ceiling's place
  /// went too (user decisions, recorded on `seedImportSettings`): every file
  /// starts carried and can be linked.
  ///
  /// Assets from before this existed fall back to [sourcePath] being set,
  /// which is exactly the ones that WERE copied into the project: the old
  /// meaning of the same choice.
  bool get carried => carriedAs != null;

  /// Which 품기 this asset's bytes are ([mintMediaCarry]), or null when the
  /// project points at the file instead of carrying it ([carried]).
  ///
  /// 🚨★★★**ONE PATH CAN BE CARRIED TWICE, SO EACH CARRY HAS A NAME.**
  /// Remove a carried file from the pool, edit the original, carry the
  /// same path again before saving — and the project knows two sets of
  /// bytes for one path: the new copy, and the old one an undo of the
  /// removal has to bring back. Everything that found the bytes was keyed
  /// by the path, so the project file's OLD entry answered first: readers
  /// showed the old picture, and the save kept it and retired the new copy
  /// (card `recarry-after-remove-reads-the-old`). The staged copy and the
  /// entry are named from [carry] now, and this rides every undo with the
  /// rest of the asset — undoing back to the first carry finds the first
  /// carry's bytes.
  ///
  /// ⛔ONE field, not a second one beside a `carried` flag: a carried asset
  /// without a name for its bytes is the state this replaces, and two
  /// fields could say it.
  ///
  /// It IS the name the bytes are stored under ([mintMediaCarry]), so a
  /// relink — `copyWith(path:)` — takes it along unchanged.
  ///
  /// ⚠️`''` is the carry an asset had before carries had names — its bytes
  /// are under the name the path alone derives, which is what a project
  /// written then holds ([mediaCarryName]).
  final String? carriedAs;

  /// [carriedAs] with the path the asset is at now — what the bytes are
  /// found by ([mediaCarryName]).
  MediaCarry? get carry {
    final token = carriedAs;
    return token == null ? null : (poolPath: path, token: token);
  }

  /// What the file at [path] looked like when it was registered — the
  /// evidence relink compares a candidate against.
  ///
  /// Null for assets registered before this existed, and for anything the
  /// app could not stat. Never back-filled: it can only describe a file
  /// that was present at the time, and a missing reference is by definition
  /// no longer there to measure.
  final MediaIdentity? identity;

  /// Detected source frame rate (sequence/video kinds); detection only.
  final double? sourceFps;

  /// Detected source frame count (sequence/video kinds).
  final int? frameCount;

  /// Detected page count (pdf kind).
  final int? pageCount;

  /// SE dialogue seed (audio kind only — §6-z10's boundary: instance
  /// truth like gain/fades stays on [AudioClip]).
  final String? dialogue;

  MediaAsset copyWith({
    String? path,
    String? name,
    MediaAssetKind? kind,
    int? offsetFrames,
    int? lengthFrames,
    MediaFitMode? fitMode,
    String? sourcePath,
    String? sourceStamp,
    String? carriedAs,
    MediaIdentity? identity,
    double? sourceFps,
    int? frameCount,
    int? pageCount,
    String? dialogue,
  }) {
    return MediaAsset(
      path: path ?? this.path,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      offsetFrames: offsetFrames ?? this.offsetFrames,
      lengthFrames: lengthFrames ?? this.lengthFrames,
      fitMode: fitMode ?? this.fitMode,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceStamp: sourceStamp ?? this.sourceStamp,
      carriedAs: carriedAs ?? this.carriedAs,
      identity: identity ?? this.identity,
      sourceFps: sourceFps ?? this.sourceFps,
      frameCount: frameCount ?? this.frameCount,
      pageCount: pageCount ?? this.pageCount,
      dialogue: dialogue ?? this.dialogue,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'kind': kind.toJson(),
    if (offsetFrames != 0) 'offset': offsetFrames,
    if (lengthFrames != null) 'length': lengthFrames,
    if (fitMode != MediaFitMode.contain) 'fit': fitMode.toJson(),
    if (sourcePath != null) 'sourcePath': sourcePath,
    if (sourceStamp != null) 'sourceStamp': sourceStamp,
    if (carriedAs != null) 'carriedAs': carriedAs,
    if (identity != null) 'identity': identity!.toJson(),
    if (sourceFps != null) 'sourceFps': sourceFps,
    if (frameCount != null) 'frameCount': frameCount,
    if (pageCount != null) 'pageCount': pageCount,
    if (dialogue != null) 'dialogue': dialogue,
  };

  /// The stored name — except the one a build before 2026-09-12 wrote by
  /// default, the file name WITH its extension: that reads as today's default
  /// ([mediaAssetDefaultName]), and a name somebody typed stays what they
  /// typed.
  static String _storedName(Map<String, dynamic> json) {
    final path = json['path'] as String;
    final name = json['name'] as String;
    return name == mediaFileName(path) ? mediaAssetDefaultName(path) : name;
  }

  factory MediaAsset.fromJson(Map<String, dynamic> json) {
    return MediaAsset(
      path: json['path'] as String,
      name: _storedName(json),
      kind: MediaAssetKind.fromJson(json['kind']),
      offsetFrames: (json['offset'] as int?) ?? 0,
      lengthFrames: json['length'] as int?,
      fitMode: MediaFitMode.fromJson(json['fit']),
      sourcePath: json['sourcePath'] as String?,
      sourceStamp: json['sourceStamp'] as String?,
      // Absent in projects written before carries had names, which said
      // `carried` — and before THAT the same choice was spelled "was it
      // copied in?" — so those assets keep the answer they were given, as
      // the carry whose bytes are named by the path alone.
      // ⚠️Nobody asked for this reading, and there is no one's data to
      // keep (no production data since 08-25). It stays because it is one
      // expression while the builds being tested wrote these files: a
      // project one of them saved keeps its carried bytes in the next. The
      // same holds for [mediaCarryName]'s bare token. Both can go once no
      // build that wrote them is in use (audit 09-25).
      carriedAs:
          json['carriedAs'] as String? ??
          ((json['carried'] as bool? ?? json['sourcePath'] != null)
              ? ''
              : null),
      identity: MediaIdentity.fromJson(json['identity']),
      sourceFps: (json['sourceFps'] as num?)?.toDouble(),
      frameCount: json['frameCount'] as int?,
      pageCount: json['pageCount'] as int?,
      dialogue: json['dialogue'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaAsset &&
          other.path == path &&
          other.name == name &&
          other.kind == kind &&
          other.offsetFrames == offsetFrames &&
          other.lengthFrames == lengthFrames &&
          other.fitMode == fitMode &&
          other.sourcePath == sourcePath &&
          other.sourceStamp == sourceStamp &&
          other.carriedAs == carriedAs &&
          other.identity == identity &&
          other.sourceFps == sourceFps &&
          other.frameCount == frameCount &&
          other.pageCount == pageCount &&
          other.dialogue == dialogue;

  @override
  int get hashCode => Object.hash(
    path,
    name,
    kind,
    offsetFrames,
    lengthFrames,
    fitMode,
    sourcePath,
    sourceStamp,
    carriedAs,
    identity,
    sourceFps,
    frameCount,
    pageCount,
    dialogue,
  );

  @override
  String toString() => 'MediaAsset(path: $path, name: $name, kind: $kind)';
}

/// One spelling for every path the project records: forward slashes.
///
/// The media pool is keyed by path, so `C:\a\b.wav` and `C:/a/b.wav`
/// reaching it as written are two assets for one file — two rows, a
/// dedupe that does not, and a usage badge counting half the clips.
/// Paths arrive spelled however the OS handed them over.
///
/// 🚨★★★**THE MODELS SPELL IT, NOT THE DOORS.** Every key the pool is
/// looked up by — [MediaAsset.path], `MediaReference.assetPath`,
/// `AudioClip.filePath` — passes through here in its constructor. It used
/// to be each door's job to pass a path through first, and a door that did
/// not (the cut folder's `C:\…\cut/A1.png`) put a second spelling in the
/// pool: the project's own copy, asked for in the pool's spelling, was not
/// found, and the original was read instead (audit 2026-09-24,
/// `carried-bytes-audit-0924` ②). A question asked with a path from
/// outside — a picker, a drop — still spells it here first.
String normalizedMediaPath(String path) => path.replaceAll('\\', '/');

/// The asset kind [path]'s extension implies; null for unrecognized
/// extensions (the import sheet asks or refuses).
MediaAssetKind? mediaAssetKindForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1) {
    return null;
  }
  final extension = path.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'mp3' || 'wav' || 'm4a' || 'aac' || 'flac' || 'ogg' => MediaAssetKind.audio,
    // A Photoshop document is an image kind: merged it IS one picture, and
    // expanding it into layers is a placement decision the import window
    // makes, not a different kind of asset.
    'png' || 'jpg' || 'jpeg' || 'webp' || 'bmp' || 'gif' || 'psd' || 'psb' =>
      MediaAssetKind.image,
    'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' => MediaAssetKind.video,
    'pdf' => MediaAssetKind.pdf,
    _ => null,
  };
}

/// [path]'s file name: its last segment, of either separator style (the
/// model stays dart:io-free). What names a FILE — a message about it, a
/// window about it, a folder.
String mediaFileName(String path) {
  final segments = path.split(RegExp(r'[\\/]'));
  final name = segments.isEmpty ? path : segments.last;
  return name.isEmpty ? path : name;
}
/// The name of the folder [path] SITS IN: its second-to-last segment,
/// read in the one spelling [normalizedMediaPath] puts every path in. Null
/// when the path names nothing above itself.
///
/// ⛔Not `Directory(path).parent`, which answers with the PLATFORM's idea of
/// a separator — a path spelled `C:\a\b` read where `/` separates has no
/// parent at all, and the cut folder parse then handed `.` out as the
/// process name (Linux CI, 2026-09-21). One path, one spelling rule.
String? mediaParentFolderName(String path) {
  final segments = normalizedMediaPath(path)
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
  return segments.length < 2 ? null : segments[segments.length - 2];
}


/// [path]'s file name split at its extension: the NAME a person reads and
/// renames, and the extension that stays the file's.
///
/// ONE split for every place that shows the two apart — the import window's
/// file table, whose rule this was (the name is what gets cut short when
/// room runs out, the extension never is), and the media pool (유저
/// 2026-09-12: 「풀에서 이름이랑 확장자 나누고 이름변경시 이름만 변경」). A
/// name whose only dot starts it (`.env`) has no extension.
({String name, String extension}) mediaFileNameParts(String path) {
  final file = mediaFileName(path);
  final dot = file.lastIndexOf('.');
  return dot > 0
      ? (name: file.substring(0, dot), extension: file.substring(dot))
      : (name: file, extension: '');
}

/// The name a pool entry starts with: its file's name WITHOUT the extension
/// ([mediaFileNameParts]) — and so the name a placement gives the rows it
/// makes and the dialogue on a sound's block.
///
/// 🚨REVERSES 2026-09-11 (라운드 6 확인 ③ 「대사 = 파일 이름(확장자 포함)」):
/// 유저 2026-09-12 「해당 이름 대로 레이어 이름이나 이름/대사 만들어진다」.
String mediaAssetDefaultName(String path) => mediaFileNameParts(path).name;

/// The name a placement of the file at [path] gives what it makes — the
/// layer, the new cut, a sound's dialogue — when [entry] is that file's pool
/// entry: the entry's own name, which a rename changed; for a file the pool
/// has not seen, the name it would start with.
///
/// 🚨ONE answer for the landing and for the silhouette drawn while the file
/// hovers. Both rebuilt the name from the path, so a file renamed in the pool
/// was still placed under its file name.
String mediaAssetNameFor(MediaAsset? entry, String path) =>
    entry?.name ?? mediaAssetDefaultName(path);

/// Validates pool uniqueness: one entry per path.
void validateMediaAssetPaths(List<MediaAsset> assets) {
  final paths = <String>{};
  for (final asset in assets) {
    if (!paths.add(asset.path)) {
      throw ArgumentError.value(
        asset.path,
        'mediaAssets',
        'Media asset paths must be unique.',
      );
    }
  }
}

/// Immutable validated copy of [assets].
List<MediaAsset> immutableMediaAssetList(List<MediaAsset> assets) {
  validateMediaAssetPaths(assets);
  return List.unmodifiable(assets);
}
