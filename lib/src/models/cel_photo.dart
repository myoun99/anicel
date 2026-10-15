import 'media_reference.dart';

/// A PHOTO laid in a sheet's ink (I-97): a still of the media pool, kept as
/// itself — never as the pixels it once made — under the drawing of the
/// picture that carries it.
///
/// 🗣️유저 2026-10-15 (I-97-Q1): 「사진으로 남게(셀의 텍스트처럼)」 — it lives in
/// the picture's own value, as a cel's texts do (`BitmapSurface.photos`), so
/// it goes wherever that picture goes: a copy, an undo, a sheet that changes
/// size. The pen draws over it and the eraser does not take it.
///
/// What it shows is the pool file itself, where [reference] stands it on
/// the picture's grid — the very shape a reference row gives a pool picture
/// on the canvas (`picturePlacement`), so it is drawn from the file at the
/// resolution it is seen at.
class CelPhoto {
  const CelPhoto({required this.id, required this.reference});

  /// Which photo of its picture this is. A photo keeps it through every
  /// edit, so the one picked is the same one before and after.
  final int id;

  /// The pool file, where it stands on the picture's grid, and its own
  /// size in its own pixels.
  final MediaReference reference;

  CelPhoto withReference(MediaReference reference) =>
      CelPhoto(id: id, reference: reference);

  Map<String, dynamic> toJson() => {'id': id, 'reference': reference.toJson()};

  factory CelPhoto.fromJson(Map<String, dynamic> json) => CelPhoto(
    id: json['id'] as int,
    reference: MediaReference.fromJson(
      json['reference'] as Map<String, dynamic>,
    ),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelPhoto && other.id == id && other.reference == reference;

  @override
  int get hashCode => Object.hash(id, reference);

  @override
  String toString() => 'CelPhoto($id, ${reference.assetPath})';
}

/// The pool files [photos] name — each once, in the order they first
/// appear: what a picture's photos USE of the media pool (I-97), and the
/// index a saved cel's head carries for the readers that read nothing else
/// (`AnicelCelBlob.photoPaths`).
List<String> celPhotoPaths(Iterable<CelPhoto> photos) => [
  ...{for (final photo in photos) photo.reference.assetPath},
];

/// [photos] with each one whose file [moves] names standing on the file
/// where it went — [moves] maps an old path to its new one, in the pool's
/// spelling, as `projectWithMediaMoved` takes them; [photos] itself when
/// none moved.
List<CelPhoto> celPhotosMoved(
  List<CelPhoto> photos,
  Map<String, String> moves,
) {
  if (!photos.any((photo) => moves.containsKey(photo.reference.assetPath))) {
    return photos;
  }
  return [
    for (final photo in photos)
      if (moves[photo.reference.assetPath] case final to?)
        photo.withReference(photo.reference.copyWith(assetPath: to))
      else
        photo,
  ];
}

/// The id a photo added to [photos] takes: one past the largest there.
///
/// ⚠️THE SECOND OF ITS KIND: `nextCelTextId` mints a cel's text ids the
/// same way. Not shared under the rule of three (CLAUDE.md 절대명령 1).
int nextCelPhotoId(Iterable<CelPhoto> photos) {
  var largest = 0;
  for (final photo in photos) {
    if (photo.id > largest) {
      largest = photo.id;
    }
  }
  return largest + 1;
}
