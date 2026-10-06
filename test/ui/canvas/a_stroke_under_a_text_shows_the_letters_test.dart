import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_text_fixture.dart';

/// 🚨★★★A STROKE UNDER A TEXT SHOWS THE LETTERS WHILE THE PEN IS DOWN
/// (R9-rest, the text tool — 유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑
/// 절대로 다르면 안 되」).
///
/// A coordinate the live overlay replaces shows the overlay's picture and
/// nothing else. The stroke's result there is the DRAWING — what the commit
/// stores — and a cel's texts are laid over its drawing when it is shown.
/// So the overlay's picture has to be that result with the texts laid over
/// it: the very bytes the committed tile will show, or every tile a stroke
/// touched would lose its letters until the pen came up.
///
/// The oracle is the tile the commit shows — the promoted tile laid by the
/// one fold (`celTileWithPlatesLaid`), premultiplied by the door's own
/// premultiply — never a blend spelled out again here.
void main() {
  const tileSize = celTextTestTileSize;
  final underText = TileCoord(x: 0, y: 0);
  final alsoUnderText = TileCoord(x: 1, y: 0);
  final bare = TileCoord(x: 0, y: 1);

  // Letters of every strength, so a picture that dropped them, or laid
  // them twice, cannot equal the oracle by accident.
  final letters = tileOf({
    for (var x = 0; x < tileSize; x += 1) ...{
      (x, 1): [200, 30, 30, 255],
      (x, 3): [30, 200, 30, 128],
      (x, 5): [30, 30, 200, 9],
    },
  });
  final ink = tileOf({
    for (var y = 0; y < tileSize; y += 1) ...{
      (1, y): [90, 90, 90, 255],
      (6, y): [240, 240, 10, 140],
    },
  });

  /// The cel a stroke lands on: ink on three tiles, a text over two.
  BitmapSurface cel() => drawingOf({
    underText: ink,
    alsoUnderText: ink,
    bare: ink,
  }).withTexts([
    textOf(1, plate: {underText: letters, alsoUnderText: letters}),
  ]);

  List<BrushDab> strokeDabs() {
    var sequence = 0;
    return [
      for (var x = 2; x < 16; x += 4)
        for (var y = 0; y < 16; y += 1)
          BrushDab(
            center: CanvasPoint(x: x + 0.5, y: y + 0.5),
            color: 0xFF102030,
            size: 1,
            opacity: 1,
            flow: 0.6,
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
      canvasSize: celTextTestCanvas,
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

  test('🚨a tile the stroke is changing under a text shows the '
      'stroke AND the letters — the bytes the committed tile will show', () async {
    final base = cel();
    final model = overlayOn(base);
    final rasterizer = stroke(model);
    final promoted = promotedBy(rasterizer, base);
    expect(promoted.keys, containsAll([underText, alsoUnderText, bare]));
    final plates = celTextPlatesOver(base)!;

    for (final coord in [underText, alsoUnderText]) {
      final laid = celTileWithPlatesLaid(
        promoted[coord],
        plates[coord]!,
        tileSize,
      )!;
      final shown = await bytesOfPicture(model.tileImages[coord]!);

      expect(shown, pictured(laid), reason: '$coord');
      // Liveness, both ways: the letters ARE in it, and so is the stroke.
      expect(shown, isNot(pictured(promoted[coord]!)), reason: '$coord');
      expect(
        shown,
        isNot(pictured(celTileWithPlatesLaid(ink, plates[coord]!, tileSize)!)),
        reason: '$coord',
      );
    }
  });

  test('a tile under no text shows the stroke\'s result as it is', () async {
    final base = cel();
    final model = overlayOn(base);
    final promoted = promotedBy(stroke(model), base);

    expect(
      await bytesOfPicture(model.tileImages[bare]!),
      pictured(promoted[bare]!),
    );
  });

  test('🚨pen-up hands each picture to the tile that will SHOW it: the '
      'very object the cel\'s laid surface holds once the stroke lands', () {
    final base = cel();
    final model = overlayOn(base);
    final promoted = promotedBy(stroke(model), base);

    // The commit: the promoted tiles put, the texts carried.
    final committed = base.putMaterializedTiles([
      for (final entry in promoted.entries)
        (coord: entry.key, tile: entry.value),
    ]);
    final shown = celSurfaceWithTextsLaid(committed);

    for (final coord in [underText, alsoUnderText]) {
      expect(
        model.tileShownFor(coord, promoted[coord]!),
        same(shown.tileAt(coord)),
        reason: '$coord: a picture handed to any other tile is one the next '
            'paint makes again — or, handed to the bare drawing\'s tile, '
            'letters that outlive their text',
      );
      expect(
        model.tileShownFor(coord, promoted[coord]!),
        isNot(same(promoted[coord])),
        reason: '$coord',
      );
    }
    expect(model.tileShownFor(bare, promoted[bare]!), same(promoted[bare]));
  });

  test('a FILL\'s result tiles are shown under the texts too', () async {
    final base = cel();
    final model = overlayOn(base);
    final filled = tileFilledWith([12, 34, 56, 255]);
    final plates = celTextPlatesOver(base)!;

    model.showResultTiles([
      PromotedStrokeTile(underText, filled, 1),
      PromotedStrokeTile(bare, filled, 1),
    ]);

    expect(
      await bytesOfPicture(model.tileImages[underText]!),
      pictured(
        celTileWithPlatesLaid(filled, plates[underText]!, tileSize)!,
      ),
    );
    expect(
      await bytesOfPicture(model.tileImages[underText]!),
      isNot(pictured(filled)),
      reason: 'the letters are over the fill',
    );
    expect(await bytesOfPicture(model.tileImages[bare]!), pictured(filled));
  });

  test('the classic snapshot road — a source that is not the '
      'rasterizer — shows them too', () async {
    final base = cel();
    final model = overlayOn(base);
    final plates = celTextPlatesOver(base)!;

    model.updateRegion(
      source: _NoStroke(),
      region: DirtyRegion(
        left: 0,
        top: 0,
        rightExclusive: tileSize,
        bottomExclusive: tileSize,
      ),
    );

    // No stroke at all, so the result is the cel's own tile — and the
    // picture is that tile as the cel shows it.
    expect(
      await bytesOfPicture(model.tileImages[underText]!),
      pictured(celTileWithPlatesLaid(ink, plates[underText]!, tileSize)!),
    );
  });

  test('a cel with no text asks nothing of the laying: every picture is '
      'the stroke\'s own, and every tile shows as itself', () {
    final base = drawingOf({underText: ink});
    final model = overlayOn(base);
    final promoted = promotedBy(stroke(model), base);

    expect(celTextPlatesOver(base), isNull);
    for (final entry in promoted.entries) {
      expect(model.tileShownFor(entry.key, entry.value), same(entry.value));
    }
  });
}

/// A stroke source with nothing painted — every pixel transparent.
class _NoStroke implements ActiveStrokePixelSource {
  @override
  int get canvasWidth => celTextTestCanvas.width;

  @override
  int get canvasHeight => celTextTestCanvas.height;

  @override
  void copyRow(int x, int y, int count, Uint8List target, int targetOffset) {
    target.fillRange(targetOffset, targetOffset + count * 4, 0);
  }
}
