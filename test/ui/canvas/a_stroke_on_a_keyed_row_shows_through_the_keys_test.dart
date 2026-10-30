import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/cel_surface_as_shown.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_tile_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cel_text_fixture.dart';

/// 🚨★★★A STROKE ON A ROW THAT KEYS ITS COLOURS SHOWS THROUGH THE KEYS
/// WHILE THE PEN IS DOWN (card a-stroke-on-a-keyed-row-shows-its-tiles-
/// unkeyed — 유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안
/// 되」).
///
/// A coordinate the live overlay replaces shows the overlay's picture and
/// nothing else, and a row's colour keys filter a cel's tiles as it is
/// shown. 🔬Shown unkeyed, a keyed sheet's ground came up bare under the pen
/// until it lifted: 2,868 pixels apart on a keyed row, 0 on a bare one
/// (공통 2026-10-16, the whole app).
///
/// The oracle is the cel as the row will show it once the stroke lands —
/// the committed surface through the seam (`celSurfaceAsShown`), pictured
/// by the door's own premultiply — never a key spelled out again here.
void main() {
  const tileSize = celTextTestTileSize;
  const ground = [64, 192, 96, 255];
  final sheet = TileCoord(x: 0, y: 0);
  final alsoSheet = TileCoord(x: 1, y: 0);
  final underText = TileCoord(x: 0, y: 1);
  final bare = TileCoord(x: 1, y: 1);

  /// The ground keyed away — a sheet's paper, the everyday case.
  final keyed = [
    ResolvedLayerEffect(
      kind: EffectKind.colorKey,
      values: const [0, 0xFF40C060, 10, 100],
    ),
  ];

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
      for (var x = 2; x < 16; x += 4)
        for (var y = 0; y < 16; y += 1)
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

  ActiveStrokeOverlayModel overlayOn(
    BitmapSurface base,
    List<ResolvedLayerEffect> effects,
  ) {
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..sourceEffects = effects
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
  /// carried — as a row through [effects] shows it.
  BitmapSurface landedAsShown(
    BitmapSurface base,
    Map<TileCoord, BitmapTile> promoted,
    List<ResolvedLayerEffect> effects,
  ) => celSurfaceAsShown(
    base.putMaterializedTiles([
      for (final entry in promoted.entries)
        (coord: entry.key, tile: entry.value),
    ]),
    effects,
  );

  test('🚨a tile the stroke is changing on a keyed row shows it through the '
      'keys — the bytes the committed tile will show', () async {
    final base = cel();
    final model = overlayOn(base, keyed);
    final promoted = promotedBy(stroke(model), base);
    expect(promoted.keys, containsAll([sheet, alsoSheet, underText, bare]));
    final landed = landedAsShown(base, promoted, keyed);
    final unkeyed = landedAsShown(base, promoted, const []);
    final before = celSurfaceAsShown(base, keyed);

    for (final coord in promoted.keys) {
      final shown = await bytesOfPicture(model.tileImages[coord]!);

      expect(shown, pictured(landed.tileAt(coord)!), reason: '$coord');
      // Liveness, both ways: the keys took something there, and the stroke
      // is in it.
      expect(shown, isNot(pictured(unkeyed.tileAt(coord)!)), reason: '$coord');
      if (before.tileAt(coord) case final was?) {
        expect(shown, isNot(pictured(was)), reason: '$coord');
      }
    }
  });

  test('🚨pen-up hands each picture to the tile the row will SHOW: the very '
      'object the cel as shown holds once the stroke lands', () {
    final base = cel();
    final model = overlayOn(base, keyed);
    final promoted = promotedBy(stroke(model), base);
    final landed = landedAsShown(base, promoted, keyed);

    for (final MapEntry(key: coord, value: tile) in promoted.entries) {
      expect(
        model.tileShownFor(coord, tile),
        same(landed.tileAt(coord)),
        reason: '$coord: a picture handed to any other tile is one the next '
            'paint makes again — or, handed to the unkeyed tile, a ground '
            'that shows wherever that tile is drawn bare',
      );
      expect(model.tileShownFor(coord, tile), isNot(same(tile)));
    }
  });

  test('a FILL\'s result tiles are shown through the keys too', () async {
    final base = cel();
    final model = overlayOn(base, keyed);
    final filled = tileFilledWith(ground);
    final inked = tileFilledWith(const [12, 34, 56, 255]);

    model.showResultTiles([
      PromotedStrokeTile(sheet, filled, 1),
      PromotedStrokeTile(underText, inked, 1),
    ]);

    final landed = landedAsShown(base, {sheet: filled, underText: inked}, keyed);
    for (final coord in [sheet, underText]) {
      expect(
        await bytesOfPicture(model.tileImages[coord]!),
        pictured(landed.tileAt(coord)!),
        reason: '$coord',
      );
    }
    expect(
      await bytesOfPicture(model.tileImages[sheet]!),
      isNot(pictured(filled)),
      reason: 'a fill in the key colour is keyed away',
    );
  });

  test('the classic snapshot road — a source that is not the rasterizer — '
      'shows through them too', () async {
    final base = cel();
    final model = overlayOn(base, keyed);

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
    // picture is that tile as the row shows it.
    final shown = celSurfaceAsShown(base, keyed);
    for (final coord in [sheet, underText]) {
      expect(
        await bytesOfPicture(model.tileImages[coord]!),
        pictured(shown.tileAt(coord)!),
        reason: '$coord',
      );
    }
  });

  test('a dragged shape\'s stroke, made off screen and shown whole, shows '
      'through them too', () async {
    final base = cel();
    final model = overlayOn(base, keyed);
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
    final landed = landedAsShown(base, promoted, keyed);
    for (final coord in promoted.keys) {
      expect(
        await bytesOfPicture(model.tileImages[coord]!),
        pictured(landed.tileAt(coord)!),
        reason: '$coord',
      );
    }
  });

  test('a stroke drawn ALONE over the cel, not in its place, is pictured as '
      'it is — the painter shows the cel\'s own tile through the keys under '
      'it', () async {
    ActiveStrokeOverlayModel aloneThrough(List<ResolvedLayerEffect> effects) {
      final model = ActiveStrokeOverlayModel(tileSize: tileSize)
        ..sourceEffects = effects
        ..blendMode = BrushBlendMode.color;
      addTearDown(model.dispose);
      return model;
    }

    final onKeyed = aloneThrough(keyed);
    final onBare = aloneThrough(const []);
    stroke(onKeyed);
    stroke(onBare);

    expect(onKeyed.preBlended, isFalse, reason: '⛔premise: the stroke alone');
    expect(onKeyed.tileImages, isNotEmpty);
    for (final MapEntry(key: coord, value: image)
        in onKeyed.tileImages.entries) {
      expect(
        await bytesOfPicture(image),
        await bytesOfPicture(onBare.tileImages[coord]!),
        reason: '$coord: its columns in the key colour are the stroke\'s own',
      );
    }
  });

  test('a row whose keys key nothing asks nothing of them: every picture is '
      'the stroke\'s own, and every tile shows as itself', () async {
    final base = drawingOf({sheet: sheetTile, alsoSheet: sheetTile});
    for (final effects in [
      const <ResolvedLayerEffect>[],
      [
        ResolvedLayerEffect(
          kind: EffectKind.colorKey,
          values: const [0, 0xFF40C060, 10, 0],
        ),
      ],
    ]) {
      final model = overlayOn(base, effects);
      final promoted = promotedBy(stroke(model), base);

      for (final MapEntry(key: coord, value: tile) in promoted.entries) {
        expect(model.tileShownFor(coord, tile), same(tile), reason: '$coord');
        expect(
          await bytesOfPicture(model.tileImages[coord]!),
          pictured(tile),
          reason: '$coord',
        );
      }
    }
  });

  group('🗣️I-132-Q32 b: on a row whose chain runs a plugin', () {
    final shifted = [shiftingFxPluginEffect()];

    Future<void> expectShows(
      ActiveStrokeOverlayModel model,
      BitmapSurface landed,
      BitmapSurface base,
    ) async {
      final before = celSurfaceAsShown(base, shifted);
      final coords = {...landed.tiles.keys, ...before.tiles.keys};
      expect(model.tileImages.keys.toSet(), coords);
      for (final coord in coords) {
        expect(
          await bytesOfPicture(model.tileImages[coord]!),
          landed.tileAt(coord) == null
              ? List.filled(tileSize * tileSize * 4, 0)
              : pictured(landed.tileAt(coord)!),
          reason: '$coord',
        );
      }
      expect(model.handsTilesOver, isFalse);
    }

    test('a stroke shows the whole cel it makes, run through the plugin — '
        'every coordinate, the ones it never touched too', () async {
      final base = cel();
      final model = overlayOn(base, shifted);
      final promoted = promotedBy(stroke(model), base);

      await expectShows(model, landedAsShown(base, promoted, shifted), base);
      expect(model.handsTilesOver, isFalse);
    });

    test('so does a fill — and a coordinate the plugin leaves clear shows '
        'clear where the cel showed ink', () async {
      final base = cel();
      final model = overlayOn(base, shifted);
      final blank = BitmapTile.blank(size: tileSize);

      model.showResultTiles([PromotedStrokeTile(sheet, blank, 1)]);

      final landed = landedAsShown(base, {sheet: blank}, shifted);
      expect(celSurfaceAsShown(base, shifted).tileAt(sheet), isNotNull);
      await expectShows(model, landed, base);
    });

    test('a shape is not made ahead a few tiles at a time', () {
      final model = overlayOn(cel(), shifted);
      final rasterizer = BrushLiveStrokeRasterizer(
        pasteboard: celTextTestCanvas.pasteboardAt(PasteboardReach.whole),
        tileSize: tileSize,
      );
      rasterizer.blendFrom(strokeDabs(), from: 0);

      expect(model.stageRegion(source: rasterizer, coords: [sheet]), isFalse);
      expect(model.stagedCount, 0);
    });
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
