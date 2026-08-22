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

    /// 🚨H2 (유저 확정 2026-08-22): 「페이스트보드 **최대치 3x3으로 두는건
    /// 일단 하는거야. 자동확장만 아이디어로서 남기고**」
    ///
    /// ⚠️This used to assert 5×5 (two canvases per edge). The numbers below
    /// are ONE canvas per edge, and they are written out rather than derived
    /// so that a change to [pasteboardCanvasesPerEdge] has to come here and
    /// say what it means.
    test('extends ONE canvas size in every direction (3x3)', () {
      expect(canvas.pasteboardLeft, -1920);
      expect(canvas.pasteboardTop, -1080);
      expect(canvas.pasteboardRightExclusive, 3840);
      expect(canvas.pasteboardBottomExclusive, 2160);
      expect(
        canvas.pasteboardRightExclusive - canvas.pasteboardLeft,
        canvas.width * 3,
        reason: 'three canvases across — that IS the 3×3',
      );
      expect(
        canvas.pasteboardBottomExclusive - canvas.pasteboardTop,
        canvas.height * 3,
      );
    });

    test('containsPasteboardPixel covers pasteboard, rejects beyond', () {
      expect(canvas.containsPasteboardPixel(x: 0, y: 0), isTrue);
      expect(canvas.containsPasteboardPixel(x: -1920, y: -1080), isTrue);
      expect(canvas.containsPasteboardPixel(x: 3839, y: 2159), isTrue);
      expect(canvas.containsPasteboardPixel(x: -1921, y: 0), isFalse);
      expect(canvas.containsPasteboardPixel(x: 0, y: 2160), isFalse);
    });

    test('tile range covers exactly the pasteboard rect', () {
      expect(canvas.pasteboardTileXMin(256), floorDiv(-1920, 256));
      expect(canvas.pasteboardTileYMin(256), floorDiv(-1080, 256));
      expect(canvas.pasteboardTileXEndExclusive(256), ceilDiv(3840, 256));
      expect(canvas.pasteboardTileYEndExclusive(256), ceilDiv(2160, 256));
    });
  });

  group('BitmapSurface pasteboard tiles', () {
    BitmapSurface surface() => BitmapSurface(
      canvasSize: const CanvasSize(width: 1000, height: 500),
      tileSize: 256,
    );

    test('containsTileCoord accepts negative pasteboard coords', () {
      expect(surface().containsTileCoord(TileCoord(x: -1, y: -1)), isTrue);
      // Left pasteboard edge (3×3, H2): -1000 → tile floor(-1000/256) = -4.
      expect(surface().containsTileCoord(TileCoord(x: -4, y: 0)), isTrue);
      expect(surface().containsTileCoord(TileCoord(x: -5, y: 0)), isFalse);
      // Top pasteboard edge: -500 → tile floor(-500/256) = -2.
      expect(surface().containsTileCoord(TileCoord(x: 0, y: -2)), isTrue);
      expect(surface().containsTileCoord(TileCoord(x: 0, y: -3)), isFalse);
    });

    test('containsTileCoord accepts right/bottom overflow tiles', () {
      // Right pasteboard edge: 2000 exclusive → last tile
      // ceil(2000/256)-1 = 7.
      expect(surface().containsTileCoord(TileCoord(x: 7, y: 0)), isTrue);
      expect(surface().containsTileCoord(TileCoord(x: 8, y: 0)), isFalse);
      // Bottom pasteboard edge: 1000 exclusive → last tile 3.
      expect(surface().containsTileCoord(TileCoord(x: 0, y: 3)), isTrue);
      expect(surface().containsTileCoord(TileCoord(x: 0, y: 4)), isFalse);
    });

    test('putTile stores a pasteboard tile', () {
      final tile = BitmapTile.blank(coord: TileCoord(x: -1, y: -1), size: 256);
      final updated = surface().putTile(tile);
      expect(updated.tileAt(TileCoord(x: -1, y: -1)), tile);
    });
  });
}
