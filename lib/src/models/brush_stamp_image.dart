import 'dart:convert';
import 'dart:typed_data';

import 'canvas_point.dart';
import 'dirty_region.dart';

/// A lifted RGBA pixel rectangle a dab can stamp 1:1 onto the canvas —
/// the engine primitive behind selection MOVE's bitmap lift (R14-④):
/// the pixels inside a selection are cut out of their cel with an erase
/// mask dab and land at the destination as a stamp dab, both through the
/// ordinary stroke funnel (undo and serialization come free).
///
/// Unlike [BrushTipMask] (square, alpha-only, resampled to the dab size),
/// a stamp is an arbitrary width×height straight-alpha RGBA image drawn
/// WITHOUT resampling — [landingRect] says where.
///
/// Immutable; committed dabs reference the stamp object directly.
class BrushStampImage {
  BrushStampImage({
    required this.id,
    required this.width,
    required this.height,
    required Uint8List rgba,
  }) : _read = null {
    _checkNamedAndSized();
    _rgba = _checked(Uint8List.fromList(rgba));
  }

  /// A stamp whose bytes are held elsewhere and [rgba] reads the first time
  /// anything asks for them: the engine's picture of a stamp carried through
  /// a placement (`EngineStampPictures.carried`), which lands without them
  /// ever being read.
  BrushStampImage.read({
    required this.id,
    required this.width,
    required this.height,
    required Uint8List Function() rgba,
  }) : _read = rgba {
    _checkNamedAndSized();
  }

  void _checkNamedAndSized() {
    if (id.isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'BrushStampImage.id must not be empty.',
      );
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError.value(
        width <= 0 ? width : height,
        width <= 0 ? 'width' : 'height',
        'BrushStampImage dimensions must be greater than 0.',
      );
    }
  }

  Uint8List _checked(Uint8List rgba) {
    if (rgba.length != width * height * 4) {
      throw ArgumentError.value(
        rgba.length,
        'rgba',
        'BrushStampImage.rgba must hold width * height * 4 bytes.',
      );
    }
    return rgba;
  }

  /// Stable identifier (e.g. `lift-<timestamp>`).
  final String id;

  final int width;
  final int height;

  /// Row-major straight-alpha RGBA bytes.
  Uint8List get rgba => _rgba ??= _checked(_read!());
  final Uint8List Function()? _read;
  Uint8List? _rgba;

  /// Where this stamp lands for a dab centred at [center]: the stamp's
  /// straight-alpha pixels land 1:1 source-over centered on the dab
  /// (integer top-left from the center, so a lift-then-drop round trip is
  /// byte-exact at full opacity). Pixel (u, v) lands exactly on canvas
  /// pixel (left + u, top + v) where left/top derive from the dab center —
  /// a lift-then-drop round trip is byte-exact.
  ///
  /// 🚨ONE arithmetic for the commit's stamp blend, the fill preview, the
  /// float hold and the landed-ink painter (round 8 of the audit,
  /// 2026-09-06) — the float hold's comment used to say "by the same
  /// arithmetic the stamp blend uses", which is a clone confessing.
  /// Pasteboard coordinates are negative and land the same way; the clip
  /// against a wall is the CALLER's decision (pasteboard for the commit,
  /// canvas for the fill's settling bounds), not this rect's.
  DirtyRegion landingRect(CanvasPoint center) {
    final left = (center.x - width / 2).round();
    final top = (center.y - height / 2).round();
    return DirtyRegion(
      left: left,
      top: top,
      rightExclusive: left + width,
      bottomExclusive: top + height,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'width': width,
    'height': height,
    'rgba': base64Encode(rgba),
  };

  factory BrushStampImage.fromJson(Map<String, dynamic> json) {
    return BrushStampImage(
      id: json['id'] as String,
      width: json['width'] as int,
      height: json['height'] as int,
      rgba: base64Decode(json['rgba'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! BrushStampImage ||
        other.id != id ||
        other.width != width ||
        other.height != height) {
      return false;
    }
    for (var index = 0; index < rgba.length; index += 1) {
      if (other.rgba[index] != rgba[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, width, height, width * height * 4);

  @override
  String toString() =>
      'BrushStampImage(id: $id, width: $width, height: $height)';
}
