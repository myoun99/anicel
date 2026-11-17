import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/mask_into_alpha.dart';
import '../../models/canvas_size.dart';
import '../../models/dirty_region.dart';
import '../persistence/brush_drawing_binary_codec.dart' show AnicelLaidCel;
import 'clip_container.dart' show ClipFormatException;
import 'clip_document.dart';
import 'clip_offscreen.dart';
import 'clip_placement.dart';
import 'tile_cutter.dart' show TileCutter, laidCelOf;

/// Where a layer's stored picture is and where its top-left stands.
///
/// [moveOnly] is false for a dropped picture its transform scales or
/// turns: only the move is drawn here, and the door says so.
typedef ClipPicture = ({
  ClipPictureSource source,
  int left,
  int top,
  bool moveOnly,
});

/// [layer]'s stored picture — a dropped picture's ORIGINAL where its
/// transform takes the original's top-left, and any other layer's render
/// where the layer stands. Null for a layer that stores none.
///
/// A dropped picture declares a render too, and the file never stores it
/// (all 22 of the samples' — read first, it came in as 「A / 1: 그림을 읽지
/// 못했습니다」 on a sample the user opened, 10-09); one with no original
/// falls to its render, which says so when it is not there either.
///
/// The transform is the picture's placement ([clipPlacementOf]): the
/// original's top-left lands where [clipPlaced] takes its corner, moved by
/// `LayerOffset`. The samples carry no scale or turn, so only the move is
/// drawn (MoArt reads the rest).
ClipPicture? clipPictureOf(ClipLayer layer) {
  final original = layer.kind == ClipLayerKind.picture ? layer.original : null;
  if (original == null) {
    return switch (layer.render) {
      final render? => (
        source: render,
        left: layer.left,
        top: layer.top,
        moveOnly: true,
      ),
      null => null,
    };
  }
  final placement = clipPlacementOf(layer.originalTransform);
  if (placement == null) {
    return (
      source: original,
      left: layer.offsetX,
      top: layer.offsetY,
      moveOnly: true,
    );
  }
  final corner = clipPlaced(placement, 0, 0);
  return (
    source: original,
    left: layer.offsetX + corner.x.round(),
    top: layer.offsetY + corner.y.round(),
    moveOnly: clipPlacementOnlyMoves(placement),
  );
}

/// A layer's mask as its picture is baked through it ([clipBakedMaskOf]).
typedef ClipBakedMask = ({ClipPictureSource source, int left, int top});

/// The mask [layer]'s picture is baked through, by the law Photoshop's is
/// ([applyMaskToAlpha]): a stored picture's or a vector layer's mask that
/// is on. Null for a layer with none on — and for one whose mask cannot be
/// baked, which the import names (`layerMaskNotApplied`): a folder's or a
/// text layer's, whose own picture is not baked here; one the file does not
/// hold the picture of; one that is not one byte a pixel.
ClipBakedMask? clipBakedMaskOf(ClipLayer layer) {
  final mask = layer.mask;
  final source = mask?.source;
  if (mask == null || source == null) {
    return null;
  }
  final bakesItsPicture = switch (layer.kind) {
    ClipLayerKind.raster || ClipLayerKind.picture || ClipLayerKind.vector =>
      true,
    ClipLayerKind.root ||
    ClipLayerKind.folder ||
    ClipLayerKind.paper ||
    ClipLayerKind.lettering ||
    ClipLayerKind.sound ||
    ClipLayerKind.fill ||
    ClipLayerKind.other => false,
  };
  if (!bakesItsPicture || !_isSingleChannel(source.attribute)) {
    return null;
  }
  return (source: source, left: mask.left, top: mask.top);
}

bool _isSingleChannel(Uint8List attribute) {
  try {
    return parseClipOffscreenAttribute(attribute).isSingleChannel;
  } on ClipFormatException {
    return false;
  }
}

/// A layer's mask as the file stores it — its offscreen's attribute and
/// blocks — and where its top-left stands on the canvas: what a worker is
/// given to bake a picture through it.
typedef ClipStoredMask = ({
  Uint8List attribute,
  Uint8List blocks,
  int left,
  int top,
});

/// Where a picture is baked: its top-left on a [canvasWidth] ×
/// [canvasHeight] canvas, in tiles of [tileSize], its alpha times [alpha] —
/// the bake that keeps a fainter cel fainter.
typedef ClipCelTarget = ({
  int left,
  int top,
  int canvasWidth,
  int canvasHeight,
  double alpha,
  int tileSize,
});

/// The picture [attribute] and [blocks] store, through [mask] and at
/// [target]'s alpha, laid as a cel on [target] — or null for a picture that
/// is not colour: a grey or monochrome layer, which this reader does not
/// turn into colour.
///
/// Pure, so it runs on a worker: the byte lists are all it is given.
AnicelLaidCel? clipCelLaid(
  Uint8List attribute,
  Uint8List blocks,
  ClipCelTarget target, {
  ClipStoredMask? mask,
}) {
  final shape = parseClipOffscreenAttribute(attribute);
  final rgba = clipColourRgba(shape, clipBlocksOf(blocks));
  if (rgba == null) {
    return null;
  }
  final picture = (rgba: rgba, width: shape.width, height: shape.height);
  if (mask != null) {
    _bakeMask(picture, target, mask);
  }
  return _laidOnCanvas(picture, target);
}

/// [picture] — straight RGBA, its own to change — laid on [target]'s canvas
/// at its alpha: the canvas's part of it, cut into the cel's tiles by the
/// cutter every picture a file holds is cut by ([TileCutter]). What falls
/// off the canvas is not laid, and a tile with no ink is not there at all —
/// the shape the drawing store gives an empty tile.
///
/// 🚨ONE CUTTER (F-608 ④, 2026-11-17). ↩️Till then it cut tiles of its own
/// (`_celTilesOf` · `_tileOf`) — [TileCutter]'s walk written a second time:
/// the rows of the picture's part on the canvas copied into tiles, a tile
/// left clear dropped — into tiles of the Dart heap, which the door then
/// copied again to bake.
AnicelLaidCel _laidOnCanvas(
  ({Uint8List rgba, int width, int height}) picture,
  ClipCelTarget target,
) {
  final size = target.tileSize;
  final canvas = DirtyRegion.fromXYWH(
    x: 0,
    y: 0,
    width: target.canvasWidth,
    height: target.canvasHeight,
  );
  final layout = (
    canvas: CanvasSize(width: target.canvasWidth, height: target.canvasHeight),
    tileSize: size,
    tiles: canvas.tileRange(tileSize: size),
    laid: null,
  );
  final on = DirtyRegion.fromXYWH(
    x: target.left,
    y: target.top,
    width: picture.width,
    height: picture.height,
  ).intersection(canvas);
  if (on == null) {
    return laidCelOf(layout, []);
  }
  final width = on.rightExclusive - on.left;
  final cut = (left: on.left, top: on.top, tileSize: size, tiles: layout.tiles);
  return laidCelOf(
    layout,
    TileCutter.cutting(cut, width, (row) {
      for (var y = on.top; y < on.bottomExclusive; y += 1) {
        final from =
            ((y - target.top) * picture.width + on.left - target.left) * 4;
        final pixels = Uint8List.sublistView(
          picture.rgba,
          from,
          from + width * 4,
        );
        _atAlpha(pixels, target.alpha);
        row(y - on.top, pixels);
      }
    }),
  );
}

/// [pixels]' alpha at [alpha], in place — the bake that keeps a fainter cel
/// fainter. A pixel it leaves with none is no pixel at all: clear, so a tile
/// of only such pixels is dropped as one the picture left clear.
void _atAlpha(Uint8List pixels, double alpha) {
  for (var i = 0; i < pixels.length; i += 4) {
    final a = (pixels[i + 3] * alpha).round();
    if (a == 0) {
      pixels
        ..[i] = 0
        ..[i + 1] = 0
        ..[i + 2] = 0
        ..[i + 3] = 0;
    } else {
      pixels[i + 3] = a;
    }
  }
}

/// [mask] multiplied into [picture]'s alpha where the picture stands on
/// [target] — nothing for a mask that is not one byte a pixel, which
/// [clipBakedMaskOf] never hands on.
void _bakeMask(
  ({Uint8List rgba, int width, int height}) picture,
  ClipCelTarget target,
  ClipStoredMask mask,
) {
  final shape = parseClipOffscreenAttribute(mask.attribute);
  final plane = clipMaskPlane(shape, clipBlocksOf(mask.blocks));
  if (plane == null) {
    return;
  }
  applyMaskToAlpha(
    picture.rgba,
    layerLeft: target.left,
    layerTop: target.top,
    layerWidth: picture.width,
    layerHeight: picture.height,
    mask: (
      plane: plane,
      left: mask.left,
      top: mask.top,
      width: shape.width,
      height: shape.height,
      defaultColor: shape.maskOutside,
    ),
  );
}

/// A layer mask's coverage as the engine lays a picture under one: a byte a
/// pixel over [width] × [height] canvas pixels from ([left], [top]), past
/// which it reads as nothing.
typedef ClipMaskPlane = ({
  Uint8List bytes,
  int left,
  int top,
  int width,
  int height,
});

/// [mask] as the engine lays a picture under it ([ClipMaskPlane]) wherever
/// that picture stands — [within], canvas pixels [left, top, right, bottom)
/// — or null for a mask that is not one byte a pixel, which
/// [clipBakedMaskOf] never hands on: what [_bakeMask] multiplies a stored
/// picture's alpha by, for a vector layer's picture the engine drew.
///
/// Pure, so it runs on a worker: the byte lists are all it is given.
///
/// ⚠️ITS OWN BOX, OR [within]: past its box a mask reads as the file says
/// ([ClipOffscreenShape.maskOutside]), and past a plane the engine reads
/// nothing — so a mask that shows what lies past it is spread over
/// [within], the rest of that read as it says, and one that hides it is
/// its box as it is.
ClipMaskPlane? clipMaskPlaneOver(
  ClipStoredMask mask,
  ({int left, int top, int right, int bottom}) within,
) {
  final shape = parseClipOffscreenAttribute(mask.attribute);
  final plane = clipMaskPlane(shape, clipBlocksOf(mask.blocks));
  if (plane == null) {
    return null;
  }
  final own = (
    bytes: plane,
    left: mask.left,
    top: mask.top,
    width: shape.width,
    height: shape.height,
  );
  if (shape.maskOutside == 0) {
    return own;
  }
  final width = within.right - within.left;
  final height = within.bottom - within.top;
  final bytes = Uint8List(width * height)
    ..fillRange(0, width * height, shape.maskOutside);
  final left = math.max(within.left, own.left);
  final right = math.min(within.right, own.left + own.width);
  final bottom = math.min(within.bottom, own.top + own.height);
  for (var y = math.max(within.top, own.top); y < bottom; y += 1) {
    if (left >= right) {
      break;
    }
    final from = (y - own.top) * own.width + left - own.left;
    bytes.setRange(
      (y - within.top) * width + left - within.left,
      (y - within.top) * width + right - within.left,
      plane,
      from,
    );
  }
  return (
    bytes: bytes,
    left: within.left,
    top: within.top,
    width: width,
    height: height,
  );
}
