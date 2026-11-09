import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';

/// 🚨A STROKE ON THE APP'S GRID IS THE ENGINE'S (flip lane ⓒ): its result is
/// a tile the engine laid, the same call showing it and finishing it (유저
/// 09-17 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const side = 128;
  const canvas = CanvasSize(width: 512, height: 512);
  const red = 0xFFC86432;
  final origin = TileCoord(x: 0, y: 0);

  BrushDab dab(double x, double y, {int color = red, double size = 40}) =>
      BrushDab(
        sequence: 0,
        pressure: 1,
        center: CanvasPoint(x: x, y: y),
        size: size,
        hardness: 1,
        opacity: 1,
        flow: 1,
        color: color,
        tipShape: BrushTipShape.square,
      );

  BrushLiveStrokeRasterizer rasterizer() => BrushLiveStrokeRasterizer(
    pasteboard: canvas.pasteboardAt(PasteboardReach.whole),
    tileSize: side,
  );

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvas, tileSize: side).putTiles([
        for (final MapEntry(key: coord, value: tile) in tiles.entries)
          (coord: coord, tile: tile),
      ]);

  BitmapTile solid(List<int> rgba) => BitmapTile(
    size: side,
    pixels: Uint8List.fromList([
      for (var at = 0; at < side * side; at++) ...rgba,
    ]),
  );

  List<int> at(Uint8List bytes, int x, int y) =>
      bytes.sublist((y * side + x) * 4, (y * side + x) * 4 + 4);

  List<PromotedStrokeTile> promoted(
    BrushLiveStrokeRasterizer stroke,
    BitmapSurface base, {
    BrushBlendMode mode = BrushBlendMode.color,
    bool erase = false,
  }) => stroke.promoteStrokeTiles(base: base, mode: mode, erase: erase);

  test('🚨a dab lands in a tile the engine made, on the tile under it', () {
    final base = surfaceOf({origin: solid([10, 20, 30, 255])});
    final stroke = rasterizer()..blendFrom([dab(64, 64)], from: 0);
    final tiles = promoted(stroke, base);
    expect(tiles.map((entry) => entry.coord), [origin]);
    final tile = tiles.single.tile;
    expect(tile.isOnEngine, isTrue);
    expect(tile.inkBoundsKnown || tile.hasInk, isTrue);
    expect(at(tile.pixels, 64, 64), [200, 100, 50, 255]);
    expect(at(tile.pixels, 5, 5), [10, 20, 30, 255]);
    stroke.clear();
  });

  test('🚨what the overlay shows is what pen-up lands, byte for byte', () {
    final base = surfaceOf({origin: solid([10, 20, 30, 200])});
    final stroke = rasterizer()..blendFrom([dab(64, 64), dab(90, 80)], from: 0);
    final live = stroke.preBlendedOverlayTiles(
      coords: [origin],
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    final shown = live.single!.landed!.pixels;
    expect(promoted(stroke, base).single.tile.pixels, shown);
    stroke.clear();
  });

  test('a stroke that leaves the cel as it was lands nothing', () {
    final base = surfaceOf({
      origin: solid([200, 100, 50, 255]),
    });
    final stroke = rasterizer()..blendFrom([dab(64, 64)], from: 0);
    expect(promoted(stroke, base), isEmpty);
    stroke.clear();
  });

  test('an eraser that takes the whole tile lands a blank one', () {
    final base = surfaceOf({origin: solid([10, 20, 30, 255])});
    final stroke = rasterizer()
      ..blendFrom([dab(64, 64, size: 400)], from: 0);
    final tile = promoted(stroke, base, erase: true).firstWhere(
      (entry) => entry.coord == origin,
    ).tile;
    expect(tile.isOnEngine, isFalse);
    expect(tile.hasInk, isFalse);
    stroke.clear();
  });

  test('★F-12 the ceiling scales the stroke once it has piled', () {
    final base = surfaceOf(const {});
    final stroke = rasterizer()
      ..strokeOpacity = 0.5
      ..blendFrom([dab(64, 64), dab(64, 64), dab(64, 64)], from: 0);
    final bytes = promoted(stroke, base).single.tile.pixels;
    expect(at(bytes, 64, 64)[3], inInclusiveRange(127, 128));
    stroke.clear();
  });

  test('a blend mode is the stroke\'s, laid on the cel', () {
    final base = surfaceOf({origin: solid([128, 128, 128, 255])});
    final stroke = rasterizer()
      ..blendFrom([dab(64, 64, color: 0xFF808080)], from: 0);
    final bytes = promoted(
      stroke,
      base,
      mode: BrushBlendMode.multiply,
    ).single.tile.pixels;
    expect(at(bytes, 64, 64)[0], inInclusiveRange(63, 65));
    expect(at(bytes, 5, 5), [128, 128, 128, 255]);
    stroke.clear();
  });

  test('the next stroke on a kept stroke starts from nothing', () {
    final base = surfaceOf(const {});
    final first = rasterizer()..blendFrom([dab(64, 64, size: 120)], from: 0);
    promoted(first, base);
    first.clear();
    final second = rasterizer()..blendFrom([dab(20, 20, size: 10)], from: 0);
    final bytes = promoted(second, base).single.tile.pixels;
    expect(at(bytes, 20, 20), [200, 100, 50, 255]);
    expect(at(bytes, 100, 100), [0, 0, 0, 0]);
    second.clear();
  });

  test('copyRow reads the stroke alone', () {
    final stroke = rasterizer()..blendFrom([dab(64, 64)], from: 0);
    final row = Uint8List(side * 4);
    stroke.copyRow(0, 64, side, row, 0);
    expect(row.sublist(64 * 4, 65 * 4), [200, 100, 50, 255]);
    expect(row.sublist(0, 4), [0, 0, 0, 0]);
    stroke.clear();
  });

  test('🚨a stroke that shows frame after frame keeps one slot a tile', () {
    final ledger = EngineTileLedger.instance;
    final base = surfaceOf({origin: solid([10, 20, 30, 255])});
    final overlay = ActiveStrokeOverlayModel(tileSize: side)
      ..erase = false
      ..blendMode = BrushBlendMode.color
      ..preBlendBase = base;
    addTearDown(overlay.dispose);
    final stroke = rasterizer();
    final dabs = <BrushDab>[];
    int? slots;
    for (var step = 0; step < 8; step += 1) {
      dabs.add(dab(30.0 + step, 64));
      final region = stroke.blendFrom(dabs)!;
      overlay.updateRegion(source: stroke, region: region);
      expect(overlay.shownTiles[origin]!.isOnEngine, isTrue);
      slots ??= ledger.slotCount;
      expect(ledger.slotCount, slots, reason: 'frame $step');
    }
    overlay.reset();
    expect(ledger.slotCount, slots! - 1);
    stroke.clear();
  });

  test('a tile retired reads no more', () {
    final ledger = EngineTileLedger.instance;
    final stroke = rasterizer()..blendFrom([dab(64, 64)], from: 0);
    final tile = promoted(stroke, surfaceOf(const {})).single.tile;
    ledger.retire(tile);
    expect(() => tile.pixels, throwsStateError);
    stroke.clear();
  });
}
