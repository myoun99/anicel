import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/brush_frame_store.dart';

/// [tile]'s pixels as the engine alone holds them, as a landing leaves a
/// tile: what a read has to ask the GPU for. Its ink is known, as the
/// engine tells a tile it lands (`EngineTileLedger.rememberInk`) — a scan
/// for it reads the pixels here, and a read then gives those and asks the
/// GPU for nothing.
BitmapTile tileOnEngine(BitmapTile tile) =>
    EngineTileLedger.instance.debugOnEngine(tile)
      ..rememberInkBounds(tile.inkBounds);

/// The bytes of every tile [surfaces] keep come here, as their copies do
/// once the hand rests (`EngineTileLedger.copyHereABatch`) — what a test
/// that weighs tiles asks first: a tile the engine alone holds weighs
/// nothing here (`BitmapTile.ownBytes`), and a test's ledger asks for no
/// copy by itself (`EngineTileLedger.copiesAtRest`).
void theCopiesComeOf(Iterable<BitmapSurface> surfaces) {
  for (final surface in surfaces) {
    _theirBytesCome(surface.keptTiles.values);
  }
}

/// [theCopiesComeOf] every cel [store] holds hot.
void theCopiesComeOfTheHotCelsOf(BrushFrameStore store) {
  final tiles = Set<Object>.identity();
  store.addHotTilesTo(tiles);
  _theirBytesCome(tiles.cast<BitmapTile>());
}

void _theirBytesCome(Iterable<BitmapTile> tiles) {
  for (final tile in tiles) {
    tile.readPixels((_, _) {});
  }
}

/// [surface], every tile of it the engine's alone ([tileOnEngine]).
BitmapSurface surfaceOnEngine(BitmapSurface surface) =>
    surface.withRebuiltTiles({
      for (final MapEntry(:key, :value) in surface.tiles.entries)
        key: tileOnEngine(value),
    });

/// A tile of [value] at every byte landed by [ledger] on each of [unders]
/// — a row of a cel's, null where there is no tile to land on — stored as
/// a kernel stores what it lands, with no kernel to compile ([tilesOf]);
/// [again], where the landing says how it is made once more
/// (`LandsAgain`). A hand's, unless [ofTheHand] says it is a picture's
/// made as a frame is (`EngineTileLedger.land`). Told the box [telling]
/// where given ([tilesLike]).
List<BitmapTile> landedOn(
  EngineTileLedger ledger,
  List<BitmapTile?> unders,
  int value, {
  LandsAgain? again,
  bool ofTheHand = true,
  GpuInkBox? telling,
}) => [
  for (final landed in ledger.land(
    [
      for (final (column, under) in unders.indexed)
        (column: column, row: 0, under: under),
    ],
    by: tilesOf(value, telling: telling),
    ofTheHand: ofTheHand,
    compared: true,
    again: again,
  ))
    landed.tile!,
];

/// What lands a tile of [value] at every byte for each tile asked, as a
/// kernel stores what it lands, with no kernel to compile.
LandedBy tilesOf(int value, {GpuInkBox? telling}) => tilesLike(
  BitmapTile.written(
    size: gpuTileSide,
    write: (pixels) => pixels.fillRange(0, gpuTileBytes, value),
  ),
  telling: telling,
);

/// What lands [tile]'s bytes for each tile asked, as [tilesOf] does — and
/// tells each the box its ink fills, as a landing that compares is told:
/// or [telling], a box no scan of it would find, where a test tells what
/// its maker said from what is found once that is forgotten.
LandedBy tilesLike(BitmapTile tile, {GpuInkBox? telling}) => (
  pool,
  cel,
  asked,
) {
  final ink = tile.inkBounds;
  final box =
      telling ??
      (ink == null
          ? null
          : (
              left: ink.left,
              top: ink.top,
              right: ink.rightExclusive,
              bottom: ink.bottomExclusive,
            ));
  // A tile, not bytes of this call's: the store's copy reads them once it
  // returns, holding what keeps them (GpuPool.store).
  return [
    for (final at in pool.store(cel, [
      for (final _ in asked) tile,
    ], (tile) => tile.readPixels((pointer, _) => pointer)))
      (change: GpuChange.inked, tile: at, box: box),
  ];
};

/// A tile of bytes of its own — nothing but its first pixel, barely there:
/// not of one colour, every tile of which shares that colour's slot on the
/// engine and its picture (`BitmapTile.pixelsKey`). What a test that fills
/// or counts slots or pictures asks for: each of these is one. Of the
/// engine's side where no [size] is given.
BitmapTile aTileOfItsOwn({int? size}) => BitmapTile.written(
  size: size ?? gpuTileSide,
  write: (pixels) => pixels
    ..fillRange(0, pixels.length, 0)
    ..[BitmapTile.bytesPerPixel - 1] = 1,
);
