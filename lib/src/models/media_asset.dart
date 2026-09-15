import 'media_identity.dart';

export 'media_identity.dart' show MediaIdentity, MediaIdentityMatch;

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

/// The fit a placed file's picture sits with: the pool entry's own, and
/// [MediaFitMode.contain] for a path no entry names.
///
/// ⚠️ONE ANSWER, because two places must agree about it: a movie kept as a
/// reference has each decoded frame fitted to the canvas with this, and
/// RASTERIZING that movie bakes the same frames as cels with it. Were they
/// to drift, baking would move the picture.
MediaFitMode mediaFitModeFor(List<MediaAsset> pool, String path) {
  for (final asset in pool) {
    if (asset.path == path) {
      return asset.fitMode;
    }
  }
  return MediaFitMode.contain;
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
  const MediaAsset({
    required this.path,
    required this.name,
    this.kind = MediaAssetKind.audio,
    this.offsetFrames = 0,
    this.lengthFrames,
    this.fitMode = MediaFitMode.contain,
    this.sourcePath,
    this.sourceStamp,
    this.carried = false,
    this.identity,
    this.sourceFps,
    this.frameCount,
    this.pageCount,
    this.dialogue,
  });

  /// Absolute file path — the pool key clips reference.
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
  /// 🔑 This flag is the WHOLE answer at save time. The kind only picks
  /// the import default ([mediaKindCarriedByDefault]: video starts as a
  /// reference, the rest start carried) — it stopped being a ceiling on
  /// 2026-08-14 (user decision, recorded on [mediaKindCarriedByDefault]),
  /// and the protection moved to the [largeCarriedAssetBytes] warning.
  ///
  /// Assets from before this existed fall back to [sourcePath] being set,
  /// which is exactly the ones that WERE copied into the project: the old
  /// meaning of the same choice.
  final bool carried;

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
    bool? carried,
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
      carried: carried ?? this.carried,
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
    if (carried) 'carried': true,
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
      // Absent in projects written before this existed, where the same
      // choice was spelled "was it copied in?" — so those assets keep the
      // answer they were given.
      carried: json['carried'] as bool? ?? json['sourcePath'] != null,
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
          other.carried == carried &&
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
    carried,
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
/// Paths arrive spelled however the OS handed them over, so every site
/// that records one passes it through here first.
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
