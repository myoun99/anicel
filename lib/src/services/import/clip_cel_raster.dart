import 'dart:math' as math;
import 'dart:typed_data';

import 'clip_document.dart';
import 'clip_offscreen.dart';
import 'clip_placement.dart';

/// One tile of a cel's picture: its place in tiles, and its straight RGBA.
typedef ClipCelTile = ({int x, int y, Uint8List pixels});

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

/// The picture [attribute] and [blocks] store, as cel tiles on [target] —
/// or null for a picture that is not colour: a grey or monochrome layer,
/// which this reader does not turn into colour.
///
/// Pure, so it runs on a worker: the two byte lists are all it is given.
List<ClipCelTile>? clipCelTiles(
  Uint8List attribute,
  Uint8List blocks,
  ClipCelTarget target,
) {
  final shape = parseClipOffscreenAttribute(attribute);
  final rgba = clipColourRgba(shape, clipBlocksOf(blocks));
  if (rgba == null) {
    return null;
  }
  return clipCelTilesOf(
    (rgba: rgba, width: shape.width, height: shape.height),
    target,
  );
}

/// [picture] — straight RGBA — as cel tiles on [target]: a stored picture
/// once decoded ([clipCelTiles]), and a vector layer once drawn.
///
/// What falls off the canvas is dropped, and a tile with no ink is not
/// there at all — the shape the drawing store gives an empty tile.
List<ClipCelTile> clipCelTilesOf(
  ({Uint8List rgba, int width, int height}) picture,
  ClipCelTarget target,
) {
  final size = target.tileSize;
  // The picture's part on the canvas, in canvas pixels.
  final on = (
    left: math.max(0, target.left),
    top: math.max(0, target.top),
    right: math.min(target.canvasWidth, target.left + picture.width),
    bottom: math.min(target.canvasHeight, target.top + picture.height),
  );
  final tiles = <ClipCelTile>[];
  for (var ty = on.top ~/ size; ty * size < on.bottom; ty += 1) {
    for (var tx = on.left ~/ size; tx * size < on.right; tx += 1) {
      final pixels = _tileOf(
        (rgba: picture.rgba, width: picture.width),
        target,
        (x: tx, y: ty),
        on,
      );
      if (pixels != null) {
        tiles.add((x: tx, y: ty, pixels: pixels));
      }
    }
  }
  return tiles;
}

/// [tile]'s pixels out of [picture] — only where [on], the picture's part
/// on the canvas, covers it. Null when nothing there has ink.
Uint8List? _tileOf(
  ({Uint8List rgba, int width}) picture,
  ClipCelTarget target,
  ({int x, int y}) tile,
  ({int left, int top, int right, int bottom}) on,
) {
  final size = target.tileSize;
  final x0 = tile.x * size;
  final y0 = tile.y * size;
  final right = math.min(on.right, x0 + size);
  final bottom = math.min(on.bottom, y0 + size);
  final pixels = Uint8List(size * size * 4);
  var inked = false;
  for (var y = math.max(on.top, y0); y < bottom; y += 1) {
    for (var x = math.max(on.left, x0); x < right; x += 1) {
      final from = ((y - target.top) * picture.width + x - target.left) * 4;
      final a = (picture.rgba[from + 3] * target.alpha).round();
      if (a == 0) {
        continue;
      }
      final to = ((y - y0) * size + x - x0) * 4;
      pixels
        ..[to] = picture.rgba[from]
        ..[to + 1] = picture.rgba[from + 1]
        ..[to + 2] = picture.rgba[from + 2]
        ..[to + 3] = a;
      inked = true;
    }
  }
  return inked ? pixels : null;
}
