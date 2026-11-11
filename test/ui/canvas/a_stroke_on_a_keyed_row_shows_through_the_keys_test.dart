// The first stroke compiles the executor and the stroke's kernels: 40 s on
// a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/cel_text_laying.dart'
    show celSurfaceWithTextsLaid;
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';

/// 🚨★★★A STROKE ON A ROW THAT KEYS ITS COLOURS SHOWS WHAT IT LANDS AS
/// WHILE THE PEN IS DOWN (card a-stroke-on-a-keyed-row-shows-its-tiles-
/// unkeyed — 유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안
/// 되」).
///
/// A coordinate the live overlay replaces shows the overlay's picture and
/// nothing else, so the picture is the tile the cel will hold there as the
/// row lays it. 🔬Shown otherwise, a keyed sheet's ground came up bare under
/// the pen until it lifted: 2,868 pixels apart on a keyed row, 0 on a bare
/// one (공통 2026-10-16, the whole app).
///
/// The keys are the row's, which the engine runs over the overlay's tiles
/// as over the cel's (`celSourceKeys`): the overlay is told no keys, so it
/// can make no keyed copy. ↩️It keyed each result tile, until the engine
/// keyed a row's stored bytes (float-warp-resamples-in-the-c-engine (1),
/// 2026-11-11) — and was told them still, for a plugin at a chain's head
/// that ran over what it showed, until that plugin was a step of the chain
/// ((2)): pins that it showed the stroke's own pictures on a keyed row, and
/// the whole cel through the plugin on a row that ran one, went with it.
///
/// The oracle is the cel as the row will lay it once the stroke lands —
/// the committed surface, its texts laid (`celSurfaceWithTextsLaid`),
/// pictured by the door's own premultiply — never a key spelled out again
/// here.
void main() {
  const tileSize = celTextTestTileSize;
  const ground = [64, 192, 96, 255];
  final sheet = TileCoord(x: 0, y: 0);
  final alsoSheet = TileCoord(x: 1, y: 0);
  final underText = TileCoord(x: 0, y: 1);
  final bare = TileCoord(x: 1, y: 1);

  /// A sheet: its ground, and a line of ink down it.
  final sheetTile = tileOf({
    for (var y = 0; y < tileSize; y += 1)
      for (var x = 0; x < tileSize; x += 1)
        (x, y): x == 1 ? const [20, 20, 20, 255] : ground,
  });
  final letters = tileOf({
    for (var x = 0; x < tileSize; x += 1) (x, 3): const [200, 30, 30, 255],
  });

  /// The cel a stroke lands on: three sheet tiles, a text over one.
  BitmapSurface cel() => drawingOf({
    sheet: sheetTile,
    alsoSheet: sheetTile,
    underText: sheetTile,
  }).withTexts([
    textOf(1, plate: {underText: letters}),
  ]);

  /// Columns over every tile — in a colour the keys keep, and in the very
  /// colour they key away.
  List<BrushDab> strokeDabs() {
    var sequence = 0;
    return [
      for (var x = 2; x < 2 * tileSize; x += 4)
        for (var y = 0; y < 2 * tileSize; y += 1)
          BrushDab(
            center: CanvasPoint(x: x + 0.5, y: y + 0.5),
            color: x % 8 == 2 ? 0xFF102030 : 0xFF40C060,
            size: 1,
            opacity: 1,
            flow: x % 8 == 2 ? 0.6 : 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: sequence++,
          ),
    ];
  }

  ActiveStrokeOverlayModel overlayOn(BitmapSurface base) {
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(model.dispose);
    return model;
  }

  /// The stroke flushed into [model] as the interactive view flushes it.
  BrushLiveStrokeRasterizer stroke(ActiveStrokeOverlayModel model) {
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: celTextTestCanvas.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    final dabs = strokeDabs();
    final region = rasterizer.blendFrom(dabs, from: 0)!;
    model.dabs.addAll(dabs);
    model.updateRegion(source: rasterizer, region: region);
    return rasterizer;
  }

  Future<List<int>> bytesOfPicture(ui.Image image) async =>
      (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

  /// [tile] as the door pictures it.
  List<int> pictured(BitmapTile tile) {
    final upload = BitmapTileImageCache.premultipliedTileUpload(tile);
    try {
      return Uint8List.fromList(upload.view);
    } finally {
      upload.free();
    }
  }

  Map<TileCoord, BitmapTile> promotedBy(
    BrushLiveStrokeRasterizer rasterizer,
    BitmapSurface base,
  ) => {
    for (final entry in rasterizer.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    ))
      entry.coord: entry.tile,
  };

  /// What the commit makes of [base] — the promoted tiles put, its texts
  /// carried — as a row lays it, its texts laid.
  BitmapSurface landedAsShown(
    BitmapSurface base,
    Map<TileCoord, BitmapTile> promoted,
  ) => celSurfaceWithTextsLaid(
    base.putMaterializedTiles([
      for (final entry in promoted.entries)
        (coord: entry.key, tile: entry.value),
    ]),
  );

  test('🚨a tile the stroke is changing on a keyed row is the bytes the '
      'committed tile will hold there', () async {
    final base = cel();
    final model = overlayOn(base);
    final promoted = promotedBy(stroke(model), base);
    expect(promoted.keys, containsAll([sheet, alsoSheet, underText, bare]));
    final landed = landedAsShown(base, promoted);
    final before = celSurfaceWithTextsLaid(base);

    for (final coord in promoted.keys) {
      final shown = await bytesOfPicture(model.tileImages[coord]!);

      expect(shown, pictured(landed.tileAt(coord)!), reason: '$coord');
      // Liveness: the stroke is in it.
      if (before.tileAt(coord) case final was?) {
        expect(shown, isNot(pictured(was)), reason: '$coord');
      }
    }
  });

  test('🚨pen-up hands each picture to the tile the row will SHOW: the very '
      'object the cel as shown holds once the stroke lands', () {
    final base = cel();
    final model = overlayOn(base);
    final promoted = promotedBy(stroke(model), base);
    final landed = landedAsShown(base, promoted);

    for (final MapEntry(key: coord, value: tile) in promoted.entries) {
      expect(
        model.tileShownFor(coord, tile),
        same(landed.tileAt(coord)),
        reason: '$coord: a picture handed to any other tile is one the next '
            'paint makes again — or, handed to the unkeyed tile, a ground '
            'that shows wherever that tile is drawn bare',
      );
    }
  });

  test('a FILL\'s result tiles are the bytes the committed tiles will hold '
      'too', () async {
    final base = cel();
    final model = overlayOn(base);
    final filled = tileFilledWith(ground);
    final inked = tileFilledWith(const [12, 34, 56, 255]);

    model.showResultTiles([
      PromotedStrokeTile(sheet, filled, 1),
      PromotedStrokeTile(underText, inked, 1),
    ]);

    final landed = landedAsShown(base, {sheet: filled, underText: inked});
    for (final coord in [sheet, underText]) {
      expect(
        await bytesOfPicture(model.tileImages[coord]!),
        pictured(landed.tileAt(coord)!),
        reason: '$coord',
      );
    }
    expect(
      await bytesOfPicture(model.tileImages[sheet]!),
      pictured(filled),
      reason: 'a fill in the key colour is the row\'s to key',
    );
  });

  test('the classic snapshot road — a source that is not the rasterizer — '
      'shows them too', () async {
    final base = cel();
    final model = overlayOn(base);

    model.updateRegion(
      source: _NoStroke(),
      region: DirtyRegion(
        left: 0,
        top: 0,
        rightExclusive: tileSize,
        bottomExclusive: tileSize * 2,
      ),
    );

    // No stroke at all, so the result is the cel's own tile — and the
    // picture is that tile as the row lays it.
    final shown = celSurfaceWithTextsLaid(base);
    for (final coord in [sheet, underText]) {
      expect(
        await bytesOfPicture(model.tileImages[coord]!),
        pictured(shown.tileAt(coord)!),
        reason: '$coord',
      );
    }
  });

  test('a dragged shape\'s stroke, made off screen and shown whole, shows '
      'them too', () async {
    final base = cel();
    final model = overlayOn(base);
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: celTextTestCanvas.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    final dabs = strokeDabs();
    final region = rasterizer.blendFrom(dabs, from: 0)!;

    expect(
      model.stageRegion(
        source: rasterizer,
        coords: region.toTileCoords(tileSize: tileSize).toList(),
      ),
      isTrue,
      reason: '⛔premise: the pre-blended road stages',
    );
    model.showStaged(dabs);

    final promoted = promotedBy(rasterizer, base);
    final landed = landedAsShown(base, promoted);
    for (final coord in promoted.keys) {
      expect(
        await bytesOfPicture(model.tileImages[coord]!),
        pictured(landed.tileAt(coord)!),
        reason: '$coord',
      );
    }
  });
}

/// A stroke source with nothing painted — every pixel transparent.
class _NoStroke implements ActiveStrokePixelSource {
  @override
  PasteboardWall get pasteboard =>
      celTextTestCanvas.pasteboardAt(PasteboardReach.whole);

  @override
  void copyRow(int x, int y, int count, Uint8List target, int targetOffset) {
    target.fillRange(targetOffset, targetOffset + count * 4, 0);
  }
}
