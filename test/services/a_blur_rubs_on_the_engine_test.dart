// The first stroke compiles the executor and the stroke's kernels: 40 s on
// a machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_strokes.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/brush_stroke_landing.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/canvas_selection_paint_clip.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/selection_clip.dart';

/// 🗣️I-75 흐리기 ON THE ENGINE (flip lane ⓒ): on the app's grid a blur
/// stroke's picture is on the stroke's own pages and what it makes of a cel
/// is a tile the engine laid — the same call showing it and finishing it
/// (유저 09-17 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
///
/// The law is pinned byte for byte on the kernel (dab/blur_tests.rs).
///
/// ↩️Till 2026-11-14 a group here held the engine within a level of the CPU
/// route it replaced, dab kind by dab kind. That route is gone (the commit
/// lands on the engine's grid alone), and each kind's law is a kernel pin:
/// a square tip `a_dab_at_full_flow_puts_the_blur_itself` ·
/// `a_dab_moves_its_pixels_by_what_it_lays`, across tiles
/// `a_window_across_tiles_reads_each_by_its_slot`, along a stroke
/// `each_dab_reads_what_the_one_before_it_moved`, a soft round tip at part
/// flow and paper that multiplies `every_device_blurs_the_pinned_strokes`,
/// paper by height the dab's own `the_papers_height_cuts_where_it_stands_
/// below_the_dab` (the blur lays by the dab's `dab_paper`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const side = 128;
  const canvas = CanvasSize(width: 512, height: 512);
  final wall = canvas.pasteboardAt(PasteboardReach.whole);
  final origin = TileCoord(x: 0, y: 0);
  final beside = TileCoord(x: 1, y: 0);
  const ink = [40, 80, 160, 255];
  const nothing = [0, 0, 0, 0];

  BrushDab rubbing(
    double x,
    double y, {
    double size = 24,
    int sequence = 0,
  }) => BrushDab(
    sequence: sequence,
    pressure: 1,
    center: CanvasPoint(x: x, y: y),
    size: size,
    hardness: 1,
    opacity: 1,
    flow: 1,
    color: 0xFF000000,
    tipShape: BrushTipShape.square,
    blurs: true,
  );

  BrushLiveStrokeRasterizer rubbedOver(
    BitmapSurface base, {
    double opacity = 1,
    SelectionClip? selection,
  }) => BrushLiveStrokeRasterizer(pasteboard: wall, tileSize: side)
    ..selectionClip = selection
    ..strokeOpacity = opacity
    ..blurOver(base);

  BitmapSurface surfaceOf(Map<TileCoord, BitmapTile> tiles) =>
      BitmapSurface(canvasSize: canvas, tileSize: side).putTiles([
        for (final MapEntry(key: coord, value: tile) in tiles.entries)
          (coord: coord, tile: tile),
      ]);

  BitmapTile tileOf(List<int> Function(int x, int y) pixel) => BitmapTile(
    size: side,
    pixels: Uint8List.fromList([
      for (var y = 0; y < side; y++)
        for (var x = 0; x < side; x++) ...pixel(x, y),
    ]),
  );

  /// Ink on its left half, nothing on its right.
  BitmapTile edge() => tileOf((x, y) => x < 64 ? ink : nothing);

  List<int> at(Uint8List bytes, int x, int y) =>
      bytes.sublist((y * side + x) * 4, (y * side + x) * 4 + 4);

  List<PromotedStrokeTile> promoted(
    BrushLiveStrokeRasterizer stroke,
    BitmapSurface base,
  ) => stroke.promoteStrokeTiles(
    base: base,
    mode: BrushBlendMode.color,
    erase: false,
  );

  test('🚨a blur lands in a tile the engine made, moved under its dab '
      'alone', () {
    final base = surfaceOf({origin: edge()});
    final stroke = rubbedOver(base)..blendFrom([rubbing(64, 64)], from: 0);
    final tiles = promoted(stroke, base);
    expect(tiles.map((entry) => entry.coord), [origin]);
    final tile = tiles.single.tile;
    expect(tile.isOnEngine, isTrue);
    final bytes = tile.pixels;
    // The box's radius is a sixth of the dab's size: 4, its three boxes
    // reaching 12 — the dab's own half.
    final across = [for (var x = 52; x < 76; x++) at(bytes, x, 64)[3]];
    expect(across.first, 255);
    expect(across.last, 0);
    expect(across[12], allOf(greaterThan(0), lessThan(255)));
    for (var i = 1; i < across.length; i++) {
      expect(across[i], lessThanOrEqualTo(across[i - 1]));
    }
    expect(at(bytes, 51, 64), ink, reason: 'left of the dab: the cel');
    expect(at(bytes, 76, 64), nothing, reason: 'right of the dab: the cel');
    expect(at(bytes, 64, 51), nothing, reason: 'above the dab: the cel');
    stroke.clear();
  });

  test('what the pen shows is what lands', () {
    final base = surfaceOf({origin: edge()});
    final stroke = rubbedOver(base)..blendFrom([rubbing(64, 64)], from: 0);
    final shown = stroke.preBlendedOverlayTiles(
      coords: [origin],
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    expect(
      shown.single!.landed.pixels,
      promoted(stroke, base).single.tile.pixels,
    );
    stroke.clear();
  });

  test('on its way a stroke compares with nothing: a rub that moved nothing '
      'still shows a tile, its frame not waiting to find that out', () {
    final base = surfaceOf({origin: tileOf((x, y) => ink)});
    final stroke = rubbedOver(base)..blendFrom([rubbing(64, 64)], from: 0);
    final shown = stroke.preBlendedOverlayTiles(
      coords: [origin],
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    expect(shown.single!.landed, isNotNull);
    stroke.clear();
  });

  test('what the pen shows reads nothing back', () {
    final base = surfaceOf({origin: edge()});
    final ledger = EngineTileLedger.instance;
    final before = ledger.debugTileReads;
    final stroke = rubbedOver(base)..blendFrom([rubbing(64, 64)], from: 0);
    stroke.preBlendedOverlayTiles(
      coords: [origin],
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    promoted(stroke, base);
    expect(ledger.debugTileReads, before);
    stroke.clear();
  });

  test('a coordinate the blur has not rewritten shows nothing — though it '
      'read it', () {
    final base = surfaceOf({
      origin: tileOf((x, y) => nothing),
      beside: tileOf((x, y) => ink),
    });
    // Its right edge is the tile's; its blur reads 12 past it.
    final stroke = rubbedOver(base)..blendFrom([rubbing(116, 64)], from: 0);
    final shown = stroke.preBlendedOverlayTiles(
      coords: [origin, beside],
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
    );
    expect(shown.last, isNull);
    final tiles = promoted(stroke, base);
    expect(tiles.map((entry) => entry.coord), [origin]);
    final bytes = tiles.single.tile.pixels;
    expect(at(bytes, 127, 64)[3], greaterThan(0));
    expect(at(bytes, 103, 64), nothing);
    stroke.clear();
  });

  test('a tile the cel has none of reads as nothing', () {
    final base = surfaceOf({beside: tileOf((x, y) => ink)});
    final stroke = rubbedOver(base)..blendFrom([rubbing(116, 64)], from: 0);
    final bytes = promoted(stroke, base).single.tile.pixels;
    expect(at(bytes, 127, 64)[3], greaterThan(0));
    expect(at(bytes, 104, 64), nothing);
    stroke.clear();
  });

  test('a stroke that moved nothing lands nothing', () {
    final base = surfaceOf({origin: tileOf((x, y) => ink)});
    final stroke = rubbedOver(base)..blendFrom([rubbing(64, 64)], from: 0);
    expect(promoted(stroke, base), isEmpty);
    stroke.clear();
  });

  test('rubbing again blurs further (Q4), each dab reading what the one '
      'before left', () {
    final base = surfaceOf({origin: edge()});
    Uint8List rubbed(int times) {
      final stroke = rubbedOver(base)
        ..blendFrom([
          for (var i = 0; i < times; i++) rubbing(64, 64, sequence: i),
        ], from: 0);
      final bytes = promoted(stroke, base).single.tile.pixels;
      stroke.clear();
      return bytes;
    }

    final (once, twice) = (rubbed(1), rubbed(2));
    expect(at(twice, 60, 64)[3], lessThan(at(once, 60, 64)[3]));
    expect(at(twice, 68, 64)[3], greaterThan(at(once, 68, 64)[3]));
  });

  test('a stroke fed a move at a time is the stroke fed whole', () {
    final base = surfaceOf({origin: edge()});
    final dabs = [
      for (var i = 0; i < 6; i++)
        rubbing(50.0 + i * 4, 64, size: 18.0 + i * 6, sequence: i),
    ];
    final whole = rubbedOver(base)..blendFrom(dabs, from: 0);
    final moved = rubbedOver(base);
    for (var count = 1; count <= dabs.length; count++) {
      moved.blendFrom(dabs.sublist(0, count), from: count - 1);
    }
    expect(
      promoted(moved, base).single.tile.pixels,
      promoted(whole, base).single.tile.pixels,
    );
    whole.clear();
    moved.clear();
  });

  test('the next stroke reads the cel anew', () {
    final first = surfaceOf({origin: edge()});
    final stroke = rubbedOver(first)..blendFrom([rubbing(64, 64)], from: 0);
    promoted(stroke, first);
    stroke.clear();
    final second = surfaceOf({
      origin: tileOf((x, y) => y < 64 ? ink : nothing),
    });
    stroke
      ..blurOver(second)
      ..blendFrom([rubbing(64, 64)], from: 0);
    final bytes = promoted(stroke, second).single.tile.pixels;
    expect(at(bytes, 54, 64), at(bytes, 74, 64), reason: 'no edge across x');
    expect(at(bytes, 64, 54)[3], greaterThan(at(bytes, 64, 74)[3]));
    stroke.clear();
  });

  test('the slider caps how far a pixel moves, once', () {
    final base = surfaceOf({origin: edge()});
    int alpha(double opacity) {
      final stroke = rubbedOver(base, opacity: opacity)
        ..blendFrom([rubbing(64, 64)], from: 0);
      final value = at(promoted(stroke, base).single.tile.pixels, 68, 64)[3];
      stroke.clear();
      return value;
    }

    expect((alpha(0.5) - alpha(1) / 2).abs(), lessThanOrEqualTo(1));
  });

  test('a selection takes what it covers and no more', () {
    final base = surfaceOf({origin: edge()});
    final stroke = rubbedOver(
      base,
      selection: SelectionClip.outline(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: 0, top: 0, right: 200, bottom: 64),
        ),
      ),
    )..blendFrom([rubbing(64, 64)], from: 0);
    final bytes = promoted(stroke, base).single.tile.pixels;
    expect(at(bytes, 68, 60)[3], greaterThan(0));
    expect(at(bytes, 68, 70), nothing);
    stroke.clear();
  });

  test('what the blur kernels keep between strokes is counted and let go '
      'when memory is tight', () {
    final base = surfaceOf({origin: edge()});
    void rub() {
      final stroke = rubbedOver(base)..blendFrom([rubbing(64, 64)], from: 0);
      promoted(stroke, base);
      stroke.clear();
    }

    rub();
    final blurs = EngineStrokes.blurs;
    final kept = blurs.bytes;
    expect(kept, greaterThan(0));
    final counted = EngineStrokes.idleBytes;
    blurs.letGo();
    expect(EngineStrokes.idleBytes, counted - kept);
    rub();
    expect(blurs.bytes, greaterThan(0));
    EngineStrokes.letGoIdle();
    expect(blurs.bytes, 0);
    expect(EngineStrokes.idleBytes, 0);
  });

  test('a stroke re-derived from its dabs is the stroke watched', () {
    final base = surfaceOf({origin: edge()});
    final dabs = [
      for (var i = 0; i < 4; i++) rubbing(60.0 + i * 3, 64, sequence: i),
    ];
    final watched = rubbedOver(base)..blendFrom(dabs, from: 0);
    final landed = strokeLandedOn(base, BrushDabSequence(dabs));
    expect(
      landed.single.tile.pixels,
      promoted(watched, base).single.tile.pixels,
    );
    watched.clear();
  });

  // ↩️Pinned off the engine's grid till 2026-11-14 (`a_blur_brush_rubs_the_
  // picture_it_finds_test`), where the funnel laid the blur again through the
  // clip; a selection cuts on the engine alone now, at the commit.
  test('a stroke re-derived from its dabs under a selection is the stroke '
      'watched — the commit cuts it where it lands', () {
    final base = surfaceOf({origin: edge()});
    final clip = SelectionClip.outline(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 200, bottom: 64),
      ),
    );
    final dabs = [
      for (var i = 0; i < 4; i++) rubbing(60.0 + i * 3, 64, sequence: i),
    ];
    final watched = rubbedOver(base, selection: clip)..blendFrom(dabs, from: 0);
    final shown = promoted(watched, base).single;
    watched.clear();
    final funneled = clipStrokeCommitToSelection(
      BrushStrokeCommitData(sourceDabs: dabs),
      clip: clip,
      surface: base,
    )!;
    final landed = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: base,
      sequence: BrushDabSequence(funneled.sourceDabs),
      layerId: const LayerId('row'),
      frameId: const FrameId('cel'),
      selection: funneled.selection,
    ).afterSurface;

    expect(
      at(shown.tile.pixels, 68, 70),
      nothing,
      reason: 'fixture premise: the selection takes part',
    );
    expect(landed.tileAt(shown.coord)!.pixels, shown.tile.pixels);
  });
}
