import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_stroke_landing.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/selection_clip.dart';

import '../helpers/a_mixing_stroke_on_the_engine.dart';
import '../helpers/the_apps_engine_let_go.dart';

/// 🗣️유저 2026-11-19 (cel-originals-are-held-twice-in-ram-and-on-the-gpu-Q2):
/// 「픽셀 대신 「한 일의 기록」을 들고, 잃으면 다시 그린다」 — a stroke's tiles
/// are the engine's alone as it lands, and the device that goes then takes
/// them. Each reads as itself all the same once the app stands on another
/// engine: the stroke's dabs laid again there, over the tile it landed on
/// (`StrokeLandsAgain`), byte for byte what the pen showed.
///
/// On the app's own engine, which each test loses: the one after it finds
/// the next.
void main() {
  const canvasSize = CanvasSize(width: 256, height: 128);
  const tileSize = 128;

  BrushDab dab(
    double x,
    double y, {
    int sequence = 0,
    bool erase = false,
    double size = 26,
  }) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: 0xB02266AA,
    size: size,
    opacity: 0.7,
    flow: 0.8,
    hardness: 0.45,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
    erase: erase,
  );

  /// Paint under the stroke, its bytes here: every tile of the canvas, a
  /// colour and an alpha that change from pixel to pixel.
  BitmapSurface paint() => aGroundOf(
    canvasSize,
    (x, y) =>
        ((40 + (x * 3 + y) % 200) << 24) | (0x99 << 16) | ((y * 2) << 8) | x,
  );

  /// Right across both tiles, then back across its own ink.
  List<BrushDab> loopBack({bool erase = false}) => [
    for (var i = 0; i < 20; i += 1) dab(24.0 + i * 11.0, 52.5, erase: erase),
    for (var i = 0; i < 20; i += 1) dab(232.0 - i * 11.0, 60.5, erase: erase),
  ].indexed.map((each) => each.$2.copyWith(sequence: each.$1)).toList();

  BrushLiveStrokeRasterizer rasterizer() => BrushLiveStrokeRasterizer(
    pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
    tileSize: tileSize,
  );

  /// The stroke as a pen draws it: its dabs piled a few at a time, as a
  /// pointer's moves come, and landed at pen-up over [base].
  Map<TileCoord, PromotedStrokeTile> drawn(
    List<BrushDab> dabs,
    BitmapSurface base,
    BrushBlendMode mode, {
    SelectionClip? selection,
    double opacity = 1,
  }) {
    final stroke = rasterizer()
      ..selectionClip = selection
      ..strokeOpacity = opacity;
    for (var from = 0; from < dabs.length; from += 7) {
      stroke.blendFrom(
        dabs.sublist(0, math.min(dabs.length, from + 7)),
        from: from,
      );
    }
    final promoted = stroke.promoteStrokeTiles(
      base: base,
      mode: mode,
      erase: mode == BrushBlendMode.erase,
      dabs: dabs,
    );
    stroke.clear();
    return {for (final tile in promoted) tile.coord: tile};
  }

  /// [draw]'s stroke drawn twice: the one read while its engine stands —
  /// what the pen showed — and the one whose device goes with its tiles
  /// the engine's alone, read once the app stands on the next engine.
  void expectDrawnAgain(
    Map<TileCoord, PromotedStrokeTile> Function() draw, {
    int tiles = 2,
  }) {
    final shown = {
      for (final MapEntry(:key, :value) in draw().entries)
        key: Uint8List.fromList(value.tile.pixels),
    };
    final lost = draw();
    expect(shown, hasLength(tiles), reason: '⛔premise: the stroke lands');
    expect(
      [for (final each in lost.values) each.tile.isOnlyOnEngine],
      everyElement(isTrue),
      reason: '⛔premise: no copy of them is here',
    );

    theAppsEngineLostAndLetGo();

    for (final MapEntry(key: coord, value: tile) in lost.entries) {
      expect(tile.tile.pixels, shown[coord], reason: 'the tile at $coord');
    }
  }

  test('a stroke over paint is drawn again as the pen showed it — and '
      'not as the paint it landed on', () {
    final base = paint();

    expectDrawnAgain(() => drawn(loopBack(), base, BrushBlendMode.color));

    for (final MapEntry(key: coord, value: tile) in drawn(
      loopBack(),
      base,
      BrushBlendMode.color,
    ).entries) {
      expect(
        tile.tile.pixels,
        isNot(base.tiles[coord]!.pixels),
        reason: '⛔premise: the stroke changes the tile at $coord',
      );
    }
  });

  test('an eraser\'s stroke is drawn again', () {
    final base = paint();

    expectDrawnAgain(
      () => drawn(loopBack(erase: true), base, BrushBlendMode.erase),
    );
  });

  test('a stroke under a ceiling, cut by a selection, is drawn again under '
      'both', () {
    final base = paint();
    final selection = SelectionClip.outline(
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 40, top: 30, right: 200, bottom: 58),
      ),
    );

    expectDrawnAgain(
      () => drawn(
        loopBack(),
        base,
        BrushBlendMode.color,
        selection: selection,
        opacity: 0.4,
      ),
    );
  });

  test('a mixing brush\'s stroke is drawn again, in the colours its steps '
      'resolved', () {
    final base = paint();
    BrushDab mixing(BrushDab dab) => dab.copyWith(
      mix: BrushDabMix(
        step: dab.sequence,
        center: dab.center,
        radius: 13,
        color: 0xFFC86432,
        refill: 0.12,
        laid: 0.3,
        density: 1,
        take: 0,
        share: 1,
        pick: 0.12,
        dry: false,
      ),
    );

    expectDrawnAgain(() {
      final dabs = [for (final dab in loopBack()) mixing(dab)];
      final stroke = rasterizer()..mixOver(base);
      for (var from = 0; from < dabs.length; from += 7) {
        stroke.blendFrom(
          dabs.sublist(0, math.min(dabs.length, from + 7)),
          from: from,
        );
      }
      final resolved = stroke.mixedAsResolved(dabs);
      expect(
        resolved.map((dab) => dab.mix),
        everyElement(isNull),
        reason: '⛔premise: every step ran and was read back',
      );
      final promoted = stroke.promoteStrokeTiles(
        base: base,
        mode: BrushBlendMode.color,
        erase: false,
        dabs: resolved,
      );
      stroke.clear();
      return {for (final tile in promoted) tile.coord: tile};
    });
  });

  test('a stroke on a stroke, neither kept anywhere but on the engine, is '
      'drawn again over the first drawn again', () {
    final base = paint();
    Map<TileCoord, PromotedStrokeTile> both() {
      final first = drawn(loopBack(), base, BrushBlendMode.color);
      final over = base.putTiles([
        for (final tile in first.values) (coord: tile.coord, tile: tile.tile),
      ]);
      return drawn(
        [for (final dab in loopBack(erase: true)) dab.copyWith(size: 12)],
        over,
        BrushBlendMode.erase,
      );
    }

    expectDrawnAgain(both);
  });

  test('a stroke laid from nothing but its dabs is drawn again as it was '
      'laid', () {
    final base = paint();

    expectDrawnAgain(
      () => {
        for (final placed in strokeLandedOn(
          base,
          BrushDabSequence(loopBack(), 0.6),
        ))
          placed.coord: PromotedStrokeTile(placed.coord, placed.tile, 0),
      },
    );
  });

  // ⏳A blur reads the cel all round each tile it lands: what draws it
  // again must hold that cel, not the tile under it alone. Till it does a
  // blur's tiles say nothing, and read as the tiles they landed on
  // (a_tile_lost_with_its_device_reads_as_what_it_landed_on_test.dart) —
  // drawn again by the dabs alone they would be paint.
  test('a blur\'s stroke says nothing yet of how it is drawn again', () {
    final base = paint();
    final dabs = [for (final dab in loopBack()) dab.copyWith(blurs: true)];
    final stroke = rasterizer()
      ..blurOver(base)
      ..blendFrom(dabs, from: 0);
    final promoted = stroke.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
      dabs: dabs,
    );
    stroke.clear();

    expect(promoted, isNotEmpty, reason: '⛔premise: the blur rubs the paint');
    expect([
      for (final tile in promoted)
        EngineTileLedger.instance.madeBy(tile.tile),
    ], everyElement(isNull));
  });

  test('asked for its slot by the ledger of the next engine — as the frame '
      'after asks — a lost tile is stored there drawn again', () {
    final base = paint();
    final shown = {
      for (final MapEntry(:key, :value) in drawn(
        loopBack(),
        base,
        BrushBlendMode.color,
      ).entries)
        key: Uint8List.fromList(value.tile.pixels),
    };
    final lost = drawn(loopBack(), base, BrushBlendMode.color);
    final gone = EngineTileLedger.instance;

    theAppsEngineLostAndLetGo();
    final next = EngineTileLedger.instance;
    expect(next, isNot(same(gone)), reason: '⛔premise: another engine');
    next.held(
      (hold) => hold.slotsOf(EngineTileLedger.landedCel, [
        for (final tile in lost.values) tile.tile,
      ]),
    );

    for (final MapEntry(key: coord, value: tile) in lost.entries) {
      expect(next.slotOf(tile.tile), isNotNull);
      expect(tile.tile.pixels, shown[coord], reason: 'the tile at $coord');
    }
  });
}
