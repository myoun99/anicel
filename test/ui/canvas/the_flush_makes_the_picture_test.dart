import 'dart:typed_data';
import 'dart:ui' as ui;

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
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';

/// 🚨★★★THE READ MAKES THE PICTURE (유저 절대규칙 2026-09-17: 「보이는
/// 중이랑 결과랑 절대로 다르면 안 되」). The overlay's picture of a
/// coordinate and the stroke revision it shows are made inside the very
/// call that pre-blended it, on every engine — so the pen-up handoff,
/// which runs in the same handler as the final flush, finds an image at
/// every promoted tile's revision, and the picture holds the pre-blended
/// result bytes exactly. ↩️That call was the flush until F-533; a flush
/// nothing reads pictures nothing now.
void main() {
  const tileSize = 8;
  const canvasSize = CanvasSize(width: 32, height: 32);

  List<BrushDab> strokeDabs() {
    var sequence = 0;
    return [
      for (var x = 2; x < 16; x += 4)
        for (var y = 0; y < 16; y += 1)
          BrushDab(
            center: CanvasPoint(x: x + 0.5, y: y + 0.5),
            color: 0xFF000000,
            size: 1,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: sequence++,
          ),
    ];
  }

  /// The stroke, pre-blended into [model] the way the interactive view
  /// does it; the rasterizer is handed back for the promotion.
  BrushLiveStrokeRasterizer stroke(ActiveStrokeOverlayModel model) {
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    final dabs = strokeDabs();
    final region = rasterizer.blendFrom(dabs, from: 0)!;
    model.dabs.addAll(dabs);
    model.updateRegion(source: rasterizer, region: region);
    return rasterizer;
  }

  test('the picture and its revision are there at the first read, and '
      'pen-up takes every one', () {
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(model.dispose);

    final rasterizer = stroke(model);

    final pictured = model.tileImages.length;
    expect(pictured, greaterThan(0), reason: 'the flush pictured the tiles');
    final promoted = rasterizer.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    expect(promoted, isNotEmpty);
    for (final entry in promoted) {
      expect(
        model.takeTileImageAt(entry.coord, revision: entry.revision),
        isNotNull,
        reason: '${entry.coord}: the handoff must find the image at the '
            'promoted tile\'s own revision — the miss this closes',
      );
    }
    expect(
      model.tileImages.length,
      pictured - promoted.length,
      reason: 'every promoted tile took its image; what stays is a tile '
          'the stroke touched without changing (its picture equals the '
          'base, and it is not promoted)',
    );
  });

  test('flushes pictures nothing until a read, which pictures the stroke as '
      'it stands then, once', () {
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(model.dispose);
    final source = _CountedStroke(
      pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    final dabs = strokeDabs();
    var told = 0;
    model.addListener(() => told += 1);
    for (var from = 0; from < dabs.length; from += 16) {
      final region = source.blendFrom(
        dabs.sublist(0, from + 16),
        from: from,
      )!;
      model.updateRegion(source: source, region: region);
    }
    expect(told, 4, reason: 'each flush is heard, once');
    expect(source.preBlends, 0);
    expect(model.strokeInHand, isTrue);
    expect(source.preBlends, 0, reason: 'asking after a stroke reads nothing');

    final pictures = model.tileImages;
    expect(source.preBlends, 1, reason: 'every flush\'s tiles in one call');
    expect(pictures, isNotEmpty);
    expect(model.tileImages, pictures);
    expect(source.preBlends, 1, reason: 'nothing moved since');
    expect(told, 4, reason: 'a read in a paint tells no painter to paint');

    final blended = source.preBlendedOverlayTile(
      tileX: 0,
      tileY: 0,
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    )!;
    expect(
      model.takeTileImageAt(TileCoord(x: 0, y: 0), revision: blended.revision),
      isNotNull,
      reason: 'at the revision of the last flush',
    );
  });

  test('a stroke let go owes nothing: no read pictures it', () {
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(model.dispose);
    final source = _CountedStroke(
      pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    model.updateRegion(
      source: source,
      region: source.blendFrom(strokeDabs(), from: 0)!,
    );
    model.reset();

    expect(model.strokeInHand, isFalse);
    expect(model.tileImages, isEmpty);
    expect(source.preBlends, 0);
  });

  test('a fill shown over a stroke owed lies on top of it', () {
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(model.dispose);
    final source = _CountedStroke(
      pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
      tileSize: tileSize,
    );
    model.updateRegion(
      source: source,
      region: source.blendFrom(strokeDabs(), from: 0)!,
    );

    final coord = TileCoord(x: 0, y: 0);
    model.showResultTiles([
      PromotedStrokeTile(coord, BitmapTile.blank(size: tileSize), 77),
    ]);
    expect(
      model.takeTileImageAt(coord, revision: 77),
      isNotNull,
      reason: 'a read after it does not lay the stroke back over the fill',
    );
  });

  test('the picture holds the pre-blended result bytes exactly', () async {
    final base = BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);
    final model = ActiveStrokeOverlayModel(tileSize: tileSize)
      ..preBlendBase = base
      ..blendMode = BrushBlendMode.color;
    addTearDown(model.dispose);
    final rasterizer = stroke(model);

    final coord = TileCoord(x: 0, y: 0);
    final image = model.tileImages[coord];
    expect(image, isNotNull, reason: 'the stroke touches tile 0,0');
    final blended = rasterizer.preBlendedOverlayTile(
      tileX: coord.x,
      tileY: coord.y,
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    )!;
    final expected = blended.readPremultiplied(Uint8List.fromList);
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    // ⛔Mutation: picture the straight bytes as if premultiplied, or a
    // stale tile → the readback is not the result.
    expect(data!.buffer.asUint8List(), expected);
  });
}

/// A live stroke that says how many times it was pre-blended for pictures.
class _CountedStroke extends BrushLiveStrokeRasterizer {
  _CountedStroke({required super.pasteboard, required super.tileSize});

  int preBlends = 0;

  @override
  List<PreBlendedOverlayTile?> preBlendedOverlayTiles({
    required List<TileCoord> coords,
    required BitmapSurface base,
    required BrushBlendMode mode,
    required bool erase,
  }) {
    preBlends += 1;
    return super.preBlendedOverlayTiles(
      coords: coords,
      base: base,
      mode: mode,
      erase: erase,
    );
  }
}
