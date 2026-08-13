import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../models/canvas_point.dart';
import 'bitmap_surface_painter.dart';

/// What a selection MOVE or TRANSFORM is holding, described in CANVAS space
/// so that whoever draws the active layer can draw it AT THAT LAYER'S DEPTH.
///
/// 🚨TS1 (유저: 변형 도중에 다른 레이어에 그려진 게 무시되서 라이브로 안보임 …
/// 변형중인 레이어 위에 흰 선으로 그린게있으면 그 선에 의해 가려져야하는데
/// 안가려짐): the float used to be a widget in the selection layer's own
/// Stack, which sits ABOVE the whole composite picture — so nothing could
/// ever occlude it, and the layers above only took effect once the pixels
/// landed in the cel. Live STROKES never had that problem because the merged
/// canvas draws them through the active layer's own painter, inside the one
/// picture that holds every layer. This is how the float gets into the same
/// place.
///
/// CANVAS space, not screen space: the slot's canvas arrives already
/// viewport-transformed (that is why the surface painter is asked for
/// `paintContentInto` there), so a screen-space offset would be wrong by the
/// zoom. The selection layer converts its drag delta on the way in.
///
/// The chrome does NOT come along — ants, handles and the confirm button stay
/// above everything, because they are about the drawing rather than part of
/// it.
@immutable
class SelectionFloatPaint {
  SelectionFloatPaint({
    this.surface,
    CanvasPoint? surfaceOffset,
    this.image,
    this.imageLeft = 0,
    this.imageTop = 0,
    this.clip,
    this.holdClip,
  }) : surfaceOffset = surfaceOffset ?? CanvasPoint(x: 0, y: 0);

  /// The float's own surface (a pure MOVE: the translation is byte-exact, so
  /// drawing the untouched lift at an offset IS the result).
  final BitmapSurfacePainter? surface;
  final CanvasPoint surfaceOffset;

  /// The resampled preview (an open warp: the preview IS the result, drawn
  /// unfiltered at the rect it will land in).
  final ui.Image? image;
  final double imageLeft;
  final double imageTop;

  /// The pasteboard wall, in canvas coordinates. The landing clips there too,
  /// so a preview that kept showing pixels past it would promise something
  /// the commit will not deliver.
  final Rect? clip;

  /// While a post-commit HOLD is up, the float is drawn ONLY over the tiles
  /// the base cannot paint yet. Canvas coordinates, like everything here.
  final ui.Path? holdClip;

  bool get isEmpty => surface == null && image == null;

  void paintInto(Canvas canvas) {
    if (isEmpty) {
      return;
    }
    canvas.save();
    final hold = holdClip;
    if (hold != null) {
      canvas.clipPath(hold);
    }
    final bounds = clip;
    if (bounds != null) {
      canvas.clipRect(bounds);
    }
    final image = this.image;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(
          imageLeft,
          imageTop,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false,
      );
    } else {
      canvas.translate(surfaceOffset.x, surfaceOffset.y);
      surface!.paintContentInto(canvas);
    }
    canvas.restore();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionFloatPaint &&
          identical(other.surface, surface) &&
          other.surfaceOffset.x == surfaceOffset.x &&
          other.surfaceOffset.y == surfaceOffset.y &&
          identical(other.image, image) &&
          other.imageLeft == imageLeft &&
          other.imageTop == imageTop &&
          other.clip == clip &&
          identical(other.holdClip, holdClip);

  @override
  int get hashCode => Object.hash(
    identityHashCode(surface),
    surfaceOffset.x,
    surfaceOffset.y,
    identityHashCode(image),
    imageLeft,
    imageTop,
    clip,
    identityHashCode(holdClip),
  );
}

/// The channel between the selection layer (which owns the float) and the
/// composite that draws it. Null value = nothing floating.
typedef SelectionFloatOverlay = ValueNotifier<SelectionFloatPaint?>;
