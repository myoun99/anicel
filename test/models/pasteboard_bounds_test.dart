import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
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

  group('PasteboardWall at the whole reach', () {
    const canvas = CanvasSize(width: 1920, height: 1080);
    final wall = canvas.pasteboardAt(PasteboardReach.whole);

    /// 🚨H2 (유저 확정 2026-08-22): 「페이스트보드 **최대치 3x3으로 두는건
    /// 일단 하는거야. 자동확장만 아이디어로서 남기고**」
    ///
    /// ⚠️This used to assert 5×5 (two canvases per edge). The numbers below
    /// are ONE canvas per edge, and they are written out rather than derived
    /// so that a change to what the whole reach means has to come here and
    /// say what it means.
    test('extends ONE canvas size in every direction (3x3)', () {
      expect(wall.left, -1920);
      expect(wall.top, -1080);
      expect(wall.rightExclusive, 3840);
      expect(wall.bottomExclusive, 2160);
      expect(
        wall.rightExclusive - wall.left,
        canvas.width * 3,
        reason: 'three canvases across — that IS the 3×3',
      );
      expect(wall.bottomExclusive - wall.top, canvas.height * 3);
    });

    test('containsPixel covers the pasteboard, rejects beyond', () {
      expect(wall.containsPixel(x: 0, y: 0), isTrue);
      expect(wall.containsPixel(x: -1920, y: -1080), isTrue);
      expect(wall.containsPixel(x: 3839, y: 2159), isTrue);
      expect(wall.containsPixel(x: -1921, y: 0), isFalse);
      expect(wall.containsPixel(x: 0, y: 2160), isFalse);
    });

    test('region and canvasRegion are the two walls as rects', () {
      expect(
        wall.region,
        DirtyRegion(
          left: -1920,
          top: -1080,
          rightExclusive: 3840,
          bottomExclusive: 2160,
        ),
      );
      expect(
        canvas.canvasRegion,
        DirtyRegion(
          left: 0,
          top: 0,
          rightExclusive: 1920,
          bottomExclusive: 1080,
        ),
      );
    });

    test('tile range covers exactly the pasteboard rect', () {
      expect(wall.tileRange(256), (
        firstX: floorDiv(-1920, 256),
        lastX: ceilDiv(3840, 256) - 1,
        firstY: floorDiv(-1080, 256),
        lastY: ceilDiv(2160, 256) - 1,
      ));
    });
  });

  group('the pasteboard sizes (I-109-Q3: 1.5x · 2x · 3x)', () {
    const canvas = CanvasSize(width: 1920, height: 1080);

    /// The label IS the whole stage's side over the paper's — Q1's 「용지
    /// 대비」, read off the wall rather than off the name.
    for (final (size, across) in [
      (PasteboardSize.oneAndAHalf, 1.5),
      (PasteboardSize.two, 2.0),
      (PasteboardSize.three, 3.0),
    ]) {
      test('${size.label} is $across papers across and down', () {
        final wall = canvas.pasteboardAt(size.reach);
        expect((wall.rightExclusive - wall.left) / canvas.width, across);
        expect((wall.bottomExclusive - wall.top) / canvas.height, across);
        expect(wall.left, -(wall.rightExclusive - canvas.width));
        expect(wall.top, -(wall.bottomExclusive - canvas.height));
      });
    }

    test('a reach that does not divide the side is rounded OUT', () {
      // 1919 / 4 = 479.75: the wall stands at 480, never inside the size
      // picked.
      const odd = CanvasSize(width: 1919, height: 1081);
      final wall = odd.pasteboardAt(PasteboardReach.quarter);
      expect(wall.left, -480);
      expect(wall.rightExclusive, 1919 + 480);
      expect(wall.top, -271);
      expect(wall.bottomExclusive, 1081 + 271);
    });

    test('off, the wall is the paper itself — at any size', () {
      for (final size in PasteboardSize.values) {
        final reach = PasteboardReach.of(size: size, inUse: false);
        expect(reach, PasteboardReach.none);
        expect(canvas.pasteboardAt(reach).region, canvas.canvasRegion);
        expect(canvas.pasteboardAt(reach).rect, canvas.canvasRect);
      }
    });

    test('in use, the reach is the size\'s', () {
      for (final size in PasteboardSize.values) {
        expect(PasteboardReach.of(size: size, inUse: true), size.reach);
      }
    });

    test('two walls are equal when their canvas and reach are', () {
      expect(
        canvas.pasteboardAt(PasteboardReach.half),
        canvas.pasteboardAt(PasteboardReach.half),
      );
      expect(
        canvas.pasteboardAt(PasteboardReach.half),
        isNot(canvas.pasteboardAt(PasteboardReach.whole)),
      );
    });
  });

  group('BitmapSurface pasteboard tiles', () {
    BitmapSurface surface({
      PasteboardReach reach = PasteboardReach.whole,
    }) => BitmapSurface(
      canvasSize: const CanvasSize(width: 1000, height: 500),
      pasteboardReach: reach,
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

    test('a smaller reach keeps its tiles inside ITS wall', () {
      // 1.5x round 1000 × 500: 250 and 125 past each edge — tiles -1 to 4
      // across, -1 to 2 down.
      final small = surface(reach: PasteboardReach.quarter);
      expect(
        small.pasteboard,
        small.canvasSize.pasteboardAt(PasteboardReach.quarter),
      );
      expect(small.containsTileCoord(TileCoord(x: -1, y: -1)), isTrue);
      expect(small.containsTileCoord(TileCoord(x: -2, y: 0)), isFalse);
      expect(small.containsTileCoord(TileCoord(x: 4, y: 2)), isTrue);
      expect(small.containsTileCoord(TileCoord(x: 5, y: 0)), isFalse);
      expect(small.containsTileCoord(TileCoord(x: 0, y: 3)), isFalse);
      final off = surface(reach: PasteboardReach.none);
      expect(off.containsTileCoord(TileCoord(x: -1, y: 0)), isFalse);
      expect(off.containsTileCoord(TileCoord(x: 3, y: 1)), isTrue);
      expect(off.containsTileCoord(TileCoord(x: 4, y: 0)), isFalse);
    });

    test('putTiles stores a pasteboard tile', () {
      final tile = BitmapTile.blank(size: 256);
      final updated = surface().putTiles([
        (coord: TileCoord(x: -1, y: -1), tile: tile),
      ]);
      expect(updated.tileAt(TileCoord(x: -1, y: -1)), tile);
    });

    test('a surface keeps its reach through JSON and copies', () {
      final half = surface(reach: PasteboardReach.half);
      expect(
        BitmapSurface.fromJson(half.toJson()).pasteboardReach,
        PasteboardReach.half,
      );
      expect(half.copyWith().pasteboardReach, PasteboardReach.half);
      expect(half, isNot(surface()));
      // The whole reach is what an older surface meant: it is not written.
      expect(surface().toJson().containsKey('pasteboardReach'), isFalse);
    });
  });

  group('Project pasteboard (I-109)', () {
    Project project() => Project(
      id: const ProjectId('p'),
      name: 'p',
      tracks: const [],
      createdAt: DateTime.utc(2026),
    );

    test('a new project has the 3x pasteboard, in use', () {
      expect(project().pasteboardSize, PasteboardSize.three);
      expect(project().pasteboardInUse, isTrue);
      expect(project().pasteboardReach, PasteboardReach.whole);
    });

    test('size and use round-trip through JSON under their own keys', () {
      final set = project().copyWith(
        pasteboardSize: PasteboardSize.oneAndAHalf,
        pasteboardInUse: false,
      );
      final json = set.toJson();
      expect(json['pasteboardSize'], 'oneAndAHalf');
      expect(json['pasteboardOff'], isTrue);
      // ⛔The retired SHOWING margin's key (F-114) is never written again:
      // a file that still carried it means something else by it.
      expect(json.containsKey('pasteboardMargin'), isFalse);
      final back = Project.fromJson(json);
      expect(back.pasteboardSize, PasteboardSize.oneAndAHalf);
      expect(back.pasteboardInUse, isFalse);
      expect(back.pasteboardReach, PasteboardReach.none);
    });

    test('the default is not written', () {
      final json = project().toJson();
      expect(json.containsKey('pasteboardSize'), isFalse);
      expect(json.containsKey('pasteboardOff'), isFalse);
    });
  });
}
