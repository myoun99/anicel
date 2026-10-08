import 'dart:math' as math;
import 'dart:typed_data';

import 'clip_document.dart';
import 'clip_offscreen.dart';

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

/// [layer]'s stored picture — its render where the layer stands, or a
/// dropped picture's original where its transform takes the original's
/// top-left. Null for a layer that stores none.
///
/// The transform (`ResizableImageInfo`, big-endian — memory
/// `csp-clip-format-notes` §4): scale x · y at @40 · @48, the turn in
/// degrees at @56, the point the picture is placed at (px, py) at @64 ·
/// @72, and the point in the picture that goes there (cx, cy) at @80 ·
/// @88. A point (u, v) of the original lands at `(a·u + c·v + e, b·u + d·v
/// + f)` with `a = cos·sx, b = sin·sx, c = −sin·sy, d = cos·sy, e = px −
/// a·cx − c·cy, f = py − b·cx − d·cy`, moved by `LayerOffset`. The samples
/// carry no scale or turn, so only the move is drawn (MoArt reads the
/// rest).
ClipPicture? clipPictureOf(ClipLayer layer) {
  if (layer.render case final render?) {
    return (source: render, left: layer.left, top: layer.top, moveOnly: true);
  }
  final original = layer.original;
  if (original == null) {
    return null;
  }
  final transform = layer.originalTransform;
  if (transform == null || transform.length < 96) {
    return (
      source: original,
      left: layer.offsetX,
      top: layer.offsetY,
      moveOnly: true,
    );
  }
  final data = ByteData.sublistView(transform);
  final sx = data.getFloat64(40);
  final sy = data.getFloat64(48);
  final turn = data.getFloat64(56) * math.pi / 180;
  final a = math.cos(turn) * sx;
  final b = math.sin(turn) * sx;
  final c = -math.sin(turn) * sy;
  final d = math.cos(turn) * sy;
  final cx = data.getFloat64(80);
  final cy = data.getFloat64(88);
  const exact = 1e-6;
  return (
    source: original,
    left: layer.offsetX + (data.getFloat64(64) - a * cx - c * cy).round(),
    top: layer.offsetY + (data.getFloat64(72) - b * cx - d * cy).round(),
    moveOnly:
        (a - 1).abs() < exact &&
        b.abs() < exact &&
        c.abs() < exact &&
        (d - 1).abs() < exact,
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
/// What falls off the canvas is dropped, and a tile with no ink is not
/// there at all — the shape the drawing store gives an empty tile.
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
  final size = target.tileSize;
  // The picture's part on the canvas, in canvas pixels.
  final on = (
    left: math.max(0, target.left),
    top: math.max(0, target.top),
    right: math.min(target.canvasWidth, target.left + shape.width),
    bottom: math.min(target.canvasHeight, target.top + shape.height),
  );
  final tiles = <ClipCelTile>[];
  for (var ty = on.top ~/ size; ty * size < on.bottom; ty += 1) {
    for (var tx = on.left ~/ size; tx * size < on.right; tx += 1) {
      final pixels = _tileOf(
        (rgba: rgba, width: shape.width),
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
