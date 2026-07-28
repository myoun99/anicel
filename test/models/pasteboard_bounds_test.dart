import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';

void main() {
  group('floorDiv', () {
    test('matches ~/ for non-negative values', () {
      expect(floorDiv(0, 256), 0);
      expect(floorDiv(255, 256), 0);
      expect(floorDiv(256, 256), 1);
      expect(floorDiv(511, 256), 1);
    });

    test('floors negative values (where ~/ truncates)', () {
      expect(floorDiv(-1, 256), -1);
      expect(floorDiv(-255, 256), -1);
      expect(floorDiv(-256, 256), -1);
      expect(floorDiv(-257, 256), -2);
    });

    test('ceilDiv is the exclusive-range companion', () {
      expect(ceilDiv(1, 256), 1);
      expect(ceilDiv(256, 256), 1);
      expect(ceilDiv(257, 256), 2);
      expect(ceilDiv(-1, 256), 0);
      expect(ceilDiv(-256, 256), -1);
    });
  });

  group('PasteboardBounds', () {
    const canvas = CanvasSize(width: 1920, height: 1080);

    test('extends two canvas sizes in every direction (5x5)', () {
      expect(canvas.pasteboardLeft, -3840);
      expect(canvas.pasteboardTop, -2160);
      expect(canvas.pasteboardRightExclusive, 5760);
      expect(canvas.pasteboardBottomExclusive, 3240);
    });

    test('containsPasteboardPixel covers pasteboard, rejects beyond', () {
      expect(canvas.containsPasteboardPixel(x: 0, y: 0), isTrue);
      expect(canvas.containsPasteboardPixel(x: -3840, y: -2160), isTrue);
      expect(canvas.containsPasteboardPixel(x: 5759, y: 3239), isTrue);
      expect(canvas.containsPasteboardPixel(x: -3841, y: 0), isFalse);
      expect(canvas.containsPasteboardPixel(x: 0, y: 3240), isFalse);
    });

    test('tile range covers exactly the pasteboard rect', () {
      expect(canvas.pasteboardTileXMin(256), floorDiv(-3840, 256));
      expect(canvas.pasteboardTileYMin(256), floorDiv(-2160, 256));
      expect(canvas.pasteboardTileXEndExclusive(256), ceilDiv(5760, 256));
      expect(canvas.pasteboardTileYEndExclusive(256), ceilDiv(3240, 256));
    });
  });

  group('BitmapSurface pasteboard tiles', () {
    BitmapSurface surface() => BitmapSurface(
      canvasSize: const CanvasSize(width: 1000, height: 500),
      tileSize: 256,
    );

    test('containsTileCoord accepts negative pasteboard coords', () {
      expect(surface().containsTileCoord(TileCoord(x: -1, y: -1)), isTrue);
      // Left pasteboard edge (5x5): -2000 → tile floor(-2000/256) = -8.
      expect(surface().containsTileCoord(TileCoord(x: -8, y: 0)), isTrue);
      expect(surface().containsTileCoord(TileCoord(x: -9, y: 0)), isFalse);
      // Top pasteboard edge: -1000 → tile floor(-1000/256) = -4.
      expect(surface().containsTileCoord(TileCoord(x: 0, y: -4)), isTrue);
      expect(surface().containsTileCoord(TileCoord(x: 0, y: -5)), isFalse);
    });

    test('containsTileCoord accepts right/bottom overflow tiles', () {
      // Right pasteboard edge: 3000 exclusive → last tile
      // ceil(3000/256)-1 = 11.
      expect(surface().containsTileCoord(TileCoord(x: 11, y: 0)), isTrue);
      expect(surface().containsTileCoord(TileCoord(x: 12, y: 0)), isFalse);
      // Bottom pasteboard edge: 1500 exclusive → last tile 5.
      expect(surface().containsTileCoord(TileCoord(x: 0, y: 5)), isTrue);
      expect(surface().containsTileCoord(TileCoord(x: 0, y: 6)), isFalse);
    });

    test('putTile stores a pasteboard tile', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: -1, y: -1), size: 256);
      final updated = surface().putTile(tile);
      expect(updated.tileAt(TileCoord(x: -1, y: -1)), tile);
    });
  });
}
