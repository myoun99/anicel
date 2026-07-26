import 'dart:convert';
import 'dart:typed_data';

import '../core/collection_equality.dart';
import 'brush_tip_mask.dart';

/// Edge length of the preview alpha the tip index carries inline.
///
/// 16 because that is exactly what `BrushTipPreview` renders — it averages a
/// mask into a 16x16 grid of cells — so a larger thumbnail would be sampled
/// straight back down and cost bytes for nothing.
const int brushTipThumbnailSide = 16;

/// One tip in the shared library.
///
/// The library is deliberately two-phase. [thumbnail] arrives with the
/// index, which is one small file; [mask] arrives when the tip's PNG has
/// decoded, which is asynchronous and per-file. A picker paints thumbnails
/// on the first frame and swaps in the real thing as it lands, rather than
/// showing a grid of holes that fill in under the user's hand.
class BrushTipEntry {
  BrushTipEntry({
    required this.id,
    required this.name,
    required this.size,
    required Uint8List thumbnail,
    this.mask,
    this.builtIn = false,
  }) : thumbnail = Uint8List.fromList(thumbnail);

  /// Library identity. It is also the PNG's FILE NAME, so it is restricted
  /// to a filename-safe alphabet (see `sanitizeBrushTipId`).
  final String id;

  /// Display name, independent of [id] — renaming a tip must not move its
  /// file or break the presets pointing at it.
  final String name;

  /// Edge length of the full-resolution mask, known from the index before
  /// the mask itself is read.
  final int size;

  /// [brushTipThumbnailSide]² alpha bytes.
  final Uint8List thumbnail;

  /// The full mask; `null` until the tip's image has been decoded.
  final BrushTipMask? mask;

  /// Generated tips ship with the app: they have no file on disk, cannot be
  /// deleted, and are re-created on every launch.
  final bool builtIn;

  bool get isLoaded => mask != null;

  BrushTipEntry copyWith({String? name, BrushTipMask? mask}) {
    return BrushTipEntry(
      id: id,
      name: name ?? this.name,
      size: size,
      thumbnail: thumbnail,
      mask: mask ?? this.mask,
      builtIn: builtIn,
    );
  }

  /// The index stores what the PNG cannot: the name, and a preview small
  /// enough to be worth inlining. [builtIn] and [mask] are never written —
  /// a built-in has no index row at all, and the mask IS the PNG.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'thumbnail': base64Encode(thumbnail),
  };

  factory BrushTipEntry.fromJson(Map<String, dynamic> json) => BrushTipEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    size: json['size'] as int,
    thumbnail: base64Decode(json['thumbnail'] as String),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrushTipEntry &&
          other.id == id &&
          other.name == name &&
          other.size == size &&
          other.builtIn == builtIn &&
          other.mask == mask &&
          listEquals(other.thumbnail, thumbnail);

  @override
  int get hashCode => Object.hash(id, name, size, builtIn, mask);

  @override
  String toString() =>
      'BrushTipEntry(id: $id, name: $name, size: $size, '
      'builtIn: $builtIn, loaded: $isLoaded)';
}
