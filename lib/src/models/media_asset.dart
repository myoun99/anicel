import '../core/collection_equality.dart';

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
/// only offers re-import. Detection-only metadata ([sourceFps],
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
    this.sourceFps,
    this.frameCount,
    this.pageCount,
    this.dialogue,
  });

  /// Absolute file path — the pool key clips reference.
  final String path;

  /// Display name; seeds with the file name and is user-editable.
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
  final String? sourcePath;

  /// Change-detection stamp of the source at copy/registration time
  /// (mtime+size fingerprint); null = never stamped.
  final String? sourceStamp;

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
    if (sourceFps != null) 'sourceFps': sourceFps,
    if (frameCount != null) 'frameCount': frameCount,
    if (pageCount != null) 'pageCount': pageCount,
    if (dialogue != null) 'dialogue': dialogue,
  };

  factory MediaAsset.fromJson(Map<String, dynamic> json) {
    return MediaAsset(
      path: json['path'] as String,
      name: json['name'] as String,
      kind: MediaAssetKind.fromJson(json['kind']),
      offsetFrames: (json['offset'] as int?) ?? 0,
      lengthFrames: json['length'] as int?,
      fitMode: MediaFitMode.fromJson(json['fit']),
      sourcePath: json['sourcePath'] as String?,
      sourceStamp: json['sourceStamp'] as String?,
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
    sourceFps,
    frameCount,
    pageCount,
    dialogue,
  );

  @override
  String toString() => 'MediaAsset(path: $path, name: $name, kind: $kind)';
}

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
    'png' || 'jpg' || 'jpeg' || 'webp' || 'bmp' || 'gif' =>
      MediaAssetKind.image,
    'mp4' || 'mov' || 'avi' || 'mkv' || 'webm' => MediaAssetKind.video,
    'pdf' => MediaAssetKind.pdf,
    _ => null,
  };
}

/// The default display name for [path]: its file name (last segment of
/// either separator style — the model stays dart:io-free).
String mediaAssetDefaultName(String path) {
  final segments = path.split(RegExp(r'[\\/]'));
  final name = segments.isEmpty ? path : segments.last;
  return name.isEmpty ? path : name;
}

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

/// Convenience equality for pool lists (command no-op guards).
bool mediaAssetListEquals(List<MediaAsset> a, List<MediaAsset> b) =>
    listEquals(a, b);
