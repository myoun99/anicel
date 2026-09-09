import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**A TILE THE USER ERASED AWAY WAS KEPT AS 256 KB OF ZEROES.**
/// Three passes materialize a surface and each answered this its own way:
/// the geometry rebuild filtered blank tiles out, the two commit tails
/// stored them. Erase a drawing to nothing and the cel still weighed what
/// it did when it was drawn — in RAM, in the hot budget, and inside every
/// undo entry that snapshotted it.
///
/// ⛔The law is [BitmapSurface.putMaterializedTiles]'s and deliberately NOT
/// [BitmapSurface.putTiles]'s: see that doc for why the recipe rewrite
/// must keep storing what it emptied.
void main() {
  const canvas = CanvasSize(width: 4, height: 4);
  final origin = TileCoord(x: 0, y: 0);

  BrushDab dabAt(double x, double y, {bool erase = false}) => BrushDab(
    center: CanvasPoint(x: x + 0.5, y: y + 0.5),
    color: 0xFFFF0000,
    size: 1,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  ).copyWith(erase: erase);

  BitmapSurface commit(BitmapSurface onto, BrushDab dab) =>
      materializeBrushDabSequenceOnBitmapSurface(
        surface: onto,
        sequence: BrushDabSequence([dab]),
      ).surface;

  BitmapSurface empty() => BitmapSurface(canvasSize: canvas, tileSize: 2);

  test('erasing the last ink out of a tile DROPS the tile', () {
    final painted = commit(empty(), dabAt(0, 0));
    expect(painted.tileAt(origin), isNotNull, reason: 'a drawn tile is here');

    final erased = commit(painted, dabAt(0, 0, erase: true));

    expect(
      erased.tileAt(origin),
      isNull,
      reason: 'nothing is left to draw here, so nothing is left to hold',
    );
    expect(erased.tiles, isEmpty);
  });

  test('but a tile with ink still somewhere in it stays whole', () {
    final painted = commit(commit(empty(), dabAt(0, 0)), dabAt(1, 1));

    final erased = commit(painted, dabAt(0, 0, erase: true));

    expect(erased.tileAt(origin), isNotNull);
    expect(erased.tileAt(origin)!.hasInk, isTrue);
  });

  test('the dirty set still NAMES the coordinate it dropped — that is what '
      'tells the tile cache to forget the picture it had', () {
    final painted = commit(empty(), dabAt(0, 0));

    final result = materializeBrushDabSequenceOnBitmapSurface(
      surface: painted,
      sequence: BrushDabSequence([dabAt(0, 0, erase: true)]),
    );

    expect(result.surface.tileAt(origin), isNull);
    expect(result.dirtyTiles.contains(origin), isTrue);
  });

  test('⛔putTiles does NOT drop — the recipe rewrite walks the tiles that '
      'exist, and cannot visit one the forward pass took away', () {
    final blank = BitmapTile(
      size: 2,
      pixels: Uint8List(BitmapTile.bytesFor(2)),
    );

    expect(empty().putTiles([(coord: origin, tile: blank)]).tileAt(origin), isNotNull);
    expect(empty().putMaterializedTiles([(coord: origin, tile: blank)]).tileAt(origin), isNull);
  });

  /// 🚨THE THIRD PATH, AND IT SURVIVED THE FIRST PIN. A pen-up whose live
  /// overlay already blended the finished tiles commits by INSTALLING
  /// them, not by re-running the dabs — a second commit tail, on its own
  /// line, that no test above reaches. Routing it through the same law and
  /// then deleting that routing left every service and model test green.
  test('the PROMOTION fast path drops what it emptied too', () {
    final painted = commit(empty(), dabAt(0, 0));
    final blanked = BitmapTile(
      size: 2,
      pixels: Uint8List(BitmapTile.bytesFor(2)),
    );

    final result = brushCommitResultForBrushDabSequenceOnBitmapSurface(
      surface: painted,
      sequence: BrushDabSequence([dabAt(0, 0, erase: true)]),
      layerId: const LayerId('l'),
      frameId: const FrameId('f'),
      promotedBase: painted,
      promotedTiles: [(coord: TileCoord(x: 0, y: 0), tile: blanked)],
    );

    expect(result.afterSurface.tileAt(origin), isNull);
    expect(
      result.dirtyTiles.contains(origin),
      isTrue,
      reason: 'the cache still has to forget the picture it was showing',
    );
  });

  test('a materializing put REMOVES a tile that was already there', () {
    final painted = commit(empty(), dabAt(0, 0));
    final blank = BitmapTile(
      size: 2,
      pixels: Uint8List(BitmapTile.bytesFor(2)),
    );

    expect(painted.putMaterializedTiles([(coord: origin, tile: blank)]).tiles, isEmpty);
  });
}
