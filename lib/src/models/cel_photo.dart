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
