/// A layer's link to an EXTERNAL media source (§6-z23, the two-axis
/// model): the layer KIND says what the row is (image vs animation), and
/// THIS field alone says whether its pixels come from a library asset.
/// Null = a normal drawn layer.
///
/// The predicate the import design settled on — "cannot draw with the
/// brush + can rasterize" — IS `mediaReference != null`, on any kind:
/// an image layer referencing a still, an animation layer referencing a
/// sequence/GIF/video/PDF. RASTERIZING never changes the kind — it bakes
/// pixels into the cels and nulls this field, nothing else.
///
/// [assetPath] is the media pool's key (the absolute file path — the same
/// identity [AudioClip.filePath] uses; relinks rewrite it in the same
/// walk). [frameOffset] is how many source frames are skipped before the
/// layer's first frame — the time mapping for sequence/video sources,
/// [AudioClip.offsetFrames]'s exact analogue; stills ignore it.
class MediaReference {
  const MediaReference({required this.assetPath, this.frameOffset = 0});

  final String assetPath;
  final int frameOffset;

  MediaReference copyWith({String? assetPath, int? frameOffset}) =>
      MediaReference(
        assetPath: assetPath ?? this.assetPath,
        frameOffset: frameOffset ?? this.frameOffset,
      );

  Map<String, dynamic> toJson() => {
    'path': assetPath,
    if (frameOffset != 0) 'offset': frameOffset,
  };

  factory MediaReference.fromJson(Map<String, dynamic> json) =>
      MediaReference(
        assetPath: json['path'] as String,
        frameOffset: (json['offset'] as int?) ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaReference &&
      other.assetPath == assetPath &&
      other.frameOffset == frameOffset;

  @override
  int get hashCode => Object.hash(assetPath, frameOffset);

  @override
  String toString() => 'MediaReference($assetPath, offset: $frameOffset)';
}
