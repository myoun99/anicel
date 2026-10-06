import 'dart:convert';
import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';

/// The grid the cel-text tests stand on: small tiles, so a test can name
/// every pixel it cares about and a failure prints something readable.
const int celTextTestTileSize = 8;
const CanvasSize celTextTestCanvas = CanvasSize(width: 32, height: 32);

/// A tile of [celTextTestTileSize] holding [pixels] — `(x, y)` to straight
/// RGBA — and nothing anywhere else.
BitmapTile tileOf(Map<(int, int), List<int>> pixels) {
  final bytes = Uint8List(BitmapTile.bytesFor(celTextTestTileSize));
  for (final entry in pixels.entries) {
    final offset =
        (entry.key.$2 * celTextTestTileSize + entry.key.$1) *
        BitmapTile.bytesPerPixel;
    bytes.setRange(offset, offset + 4, entry.value);
  }
  return BitmapTile(size: celTextTestTileSize, pixels: bytes);
}

/// A tile every pixel of which is [rgba].
BitmapTile tileFilledWith(List<int> rgba) => tileOf({
  for (var y = 0; y < celTextTestTileSize; y += 1)
    for (var x = 0; x < celTextTestTileSize; x += 1) (x, y): rgba,
});

/// A drawing on the test grid — tiles alone, no texts.
BitmapSurface drawingOf(Map<TileCoord, BitmapTile> tiles) => BitmapSurface(
  canvasSize: celTextTestCanvas,
  tileSize: celTextTestTileSize,
  tiles: tiles,
);

/// A text that says [words] and bakes to [plate]. What it says does not
/// have to match the plate: nothing that carries, lays or saves a text
/// reads its settings to find its pixels.
CelText textOf(
  int id, {
  String words = 'text',
  Map<TileCoord, BitmapTile> plate = const {},
  CanvasPoint? anchor,
}) => CelText(
  id: id,
  content: CelTextContent(
    spans: [CelTextSpan(text: words, style: const TextLetterStyle())],
    anchor: anchor ?? CanvasPoint(x: 0, y: 0),
  ),
  plate: plate,
);

/// One pixel of [surface]'s tile at [coord], as straight RGBA — null where
/// the surface holds no tile there.
List<int>? pixelOf(BitmapSurface surface, TileCoord coord, int x, int y) {
  final tile = surface.tileAt(coord);
  if (tile == null) {
    return null;
  }
  final offset = (y * surface.tileSize + x) * BitmapTile.bytesPerPixel;
  return tile.readPixels(
    (_, view) => List<int>.from(view.sublist(offset, offset + 4)),
  );
}

/// Every byte of [surface]'s tile at [coord] — null where it holds none.
List<int>? bytesOf(BitmapSurface surface, TileCoord coord) =>
    surface.tileAt(coord)?.pixels;

/// [json] written out as JSON text and read back — what a file does to it,
/// so a value that only survives as a Dart map does not pass for saved.
Map<String, dynamic> throughJson(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
