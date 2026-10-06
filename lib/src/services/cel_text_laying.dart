/// What a cel SHOWS: its drawing with the texts it carries laid over it.
///
/// 🚨★★★WHY THE TEXTS BECOME TILES, AND NOT A PICTURE DRAWN AFTER THEM
/// (R9-rest, 2026-10-06 — 유저: 「셀의 그림이랑 정확히 동일」). A cel reaches the
/// screen by two roads that composite in different orders: the row being
/// drawn on puts its tiles straight onto what is below it, every other row
/// is one image of the whole cel, and below 100% each halves what it has.
/// A text drawn as its own picture after the tiles would meet the backdrop
/// at a different step on each road — a rounding apart at full size, and a
/// different halving below it — so one cel would be two pictures (유저
/// 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」). Laid into
/// the tiles first, there is one set of bytes and every road that draws or
/// reads tiles has them: the canvas, playback, export, an onion skin, a
/// thumbnail, the fill's boundary and the eyedropper's pick.
///
/// ★THE LAYING IS A STAMP. A text's plate lands on the drawing exactly as a
/// picture stamped there at full strength would — [BrushStampBlitter], the
/// one landing every stamp and every normal stroke already runs — so 「a
/// text」 and 「those pixels drawn」 are the same bytes, and turning a text
/// into drawing is keeping this result.
///
/// ⛔NEVER STORED. Like the colour keys beside it (`cel_source_effect_pass`)
/// this is a view made when a cel is shown; the truth is the surface with
/// its texts. Both run at one seam — `celSurfaceAsShown`.
library;

import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/tile_coord.dart';
import 'brush_stamp_span_kernel.dart';

/// [surface]'s drawing with every text it carries laid over it, bottom to
/// top — a surface that carries no texts, whose tiles are the cel as shown.
/// [surface] itself when it carries none, which is nearly every cel: one
/// field read, and nothing else happens.
///
/// A coordinate no text reaches keeps the drawing's own tile, the same
/// object, so the pictures made for it stay in use.
BitmapSurface celSurfaceWithTextsLaid(BitmapSurface surface) {
  if (surface.texts.isEmpty) {
    return surface;
  }
  final cached = _laidSurfaces[surface];
  if (cached != null) {
    return cached;
  }
  final laid = <TileCoord, BitmapTile>{};
  for (final entry in celTextPlatesOver(surface)!.entries) {
    final tile = celTileWithPlatesLaid(
      surface.tileAt(entry.key),
      entry.value,
      surface.tileSize,
    );
    if (tile != null) {
      laid[entry.key] = tile;
    }
  }
  final result = surface.withTexts(const []).withRebuiltTiles(laid);
  _laidSurfaces[surface] = result;
  return result;
}

/// The plates laid over each coordinate of [surface], bottom → top — every
/// text's tile there, in the texts' order. Null when it carries no text.
///
/// What a live stroke asks for the cel it is drawn on: the tiles it is
/// still changing have to show the letters over them too
/// ([layPlatesOverStraight]), or a stroke passing under a text would wipe
/// the letters off every tile it touched until the pen came up.
Map<TileCoord, List<BitmapTile>>? celTextPlatesOver(BitmapSurface surface) {
  if (surface.texts.isEmpty) {
    return null;
  }
  return _platesOver[surface] ??= {
    for (final coord in {
      for (final text in surface.texts) ...text.plate.keys,
    })
      coord: [
        for (final text in surface.texts) ?text.plate[coord],
      ],
  };
}

/// What a coordinate SHOWS: [under] — the drawing's tile there, or null
/// where it has none — with [plates] laid over it bottom → top. Null when
/// nothing is there at all: no tile, and no ink in any plate.
///
/// 🚨★★★THE ONE FOLD. A cel's laid surface, the picture a fill's result
/// shows before it lands and the tile a pen-up hands its picture to all ask
/// this, so the three cannot lay a text three ways.
BitmapTile? celTileWithPlatesLaid(
  BitmapTile? under,
  List<BitmapTile> plates,
  int tileSize,
) {
  var laid = under;
  for (final plate in plates) {
    if (laid != null) {
      laid = _laidOver(laid, plate, tileSize);
    } else if (plate.hasInk) {
      // ⚠️Only a plate WITH ink: a blank plate tile over an empty
      // coordinate lays nothing, and a stamp that lays nothing makes no
      // tile.
      laid = _laidOverNothing(plate, tileSize);
    }
  }
  return laid;
}

/// The same laying over a tile's bytes that are not a tile yet: [straight]
/// — one tile of straight rgba, written IN PLACE — with [plates] stamped
/// over it bottom → top.
///
/// A live stroke's result is bytes in the rasterizer's own staging until
/// the pen comes up; what it shows meanwhile has to be those bytes under
/// the cel's texts, and equal to the last byte to what
/// [celTileWithPlatesLaid] makes of the tile they become — which is why
/// both end in [_stamp].
void layPlatesOverStraight(
  Uint8List straight,
  List<BitmapTile> plates,
  int tileSize,
) {
  for (final plate in plates) {
    _stamp(straight, plate, tileSize);
  }
}

/// [plate] stamped onto [pixels] at full strength, in place — THE landing,
/// and the stamp tool's own ([BrushStampBlitter]). Whether a byte changed.
bool _stamp(Uint8List pixels, BitmapTile plate, int tileSize) =>
    plate.readPixels(
      (_, view) => BrushStampBlitter(
        rgba: view,
        dabOpacity: 1.0,
        erase: false,
      ).blendSpanInPlace(pixels, 0, 0, tileSize * tileSize),
    );

/// [plate] laid over an empty coordinate — what the stamp makes there: it
/// skips a pixel of alpha 0 and writes every other, as it is, over nothing.
///
/// A baked plate holds nothing behind alpha 0 (the engine hands its pixels
/// back that way), and for such a plate the stamp's answer is the plate
/// ITSELF: a text over bare paper costs no second copy of its pixels. Only
/// a plate that does carry a colour where it has no ink is run through the
/// stamp, onto a blank tile, to be rid of it.
///
/// ↩️It cleared those pixels in a walk of its own until the clone ratchet
/// named that walk as the colour keys' (`_keyedTile`, 90 → 91, 2026-10-06).
/// The stamp already says what lands over nothing.
BitmapTile _laidOverNothing(BitmapTile plate, int tileSize) =>
    _laidAlone[plate] ??= _holdsColourBehindNothing(plate)
        ? _stampedOnBlank(plate, tileSize)
        : plate;

BitmapTile _stampedOnBlank(BitmapTile plate, int tileSize) {
  final pixels = Uint8List(BitmapTile.bytesFor(tileSize));
  _stamp(pixels, plate, tileSize);
  return BitmapTile(size: tileSize, pixels: pixels);
}

/// Whether any pixel of [tile] with no alpha still carries a colour.
bool _holdsColourBehindNothing(BitmapTile tile) => tile.readPixels((_, view) {
  // RGBA little-endian: alpha is the word's top byte.
  final words = view.buffer.asUint32List(
    view.offsetInBytes,
    view.length ~/ BitmapTile.bytesPerPixel,
  );
  for (var i = 0; i < words.length; i += 1) {
    if (words[i] != 0 && (words[i] & 0xff000000) == 0) {
      return true;
    }
  }
  return false;
});

/// [plate] stamped over [under] at full strength.
///
/// 🚨REMEMBERED PER PAIR OF TILES, which is what lets a person draw on a
/// cel that carries text: a stroke commits a new surface, but it makes one
/// new tile per coordinate it touched and every other tile is the object it
/// was. Remembered per surface alone, each dab would lay every text again
/// over the whole cel.
BitmapTile _laidOver(BitmapTile under, BitmapTile plate, int tileSize) {
  final remembered = _laidPairs[under] ??= <_LaidPair>[];
  for (var i = 0; i < remembered.length; i += 1) {
    final pair = remembered[i];
    if (identical(pair.plate, plate)) {
      if (i != 0) {
        remembered
          ..removeAt(i)
          ..insert(0, pair);
      }
      return pair.laid;
    }
  }
  final pixels = under.pixels;
  final changed = _stamp(pixels, plate, tileSize);
  // A plate with no ink over this coordinate changes nothing: the
  // drawing's own tile, the same object, with the pictures it has.
  final laid = changed ? BitmapTile(size: tileSize, pixels: pixels) : under;
  remembered.insert(0, (plate: plate, laid: laid));
  if (remembered.length > _pairsKeptPerTile) {
    remembered.removeLast();
  }
  return laid;
}

/// A plate and the tile it made over the tile this is remembered under.
typedef _LaidPair = ({BitmapTile plate, BitmapTile laid});

/// How many plates' results one drawing tile keeps. One is the cel on
/// screen; the rest are the same drawing under OTHER texts — a copied cel
/// shown beside its source, an onion skin of it — which with a single slot
/// would lay the tile again on every frame, each one evicting the other.
const int _pairsKeptPerTile = 4;

/// The laid surface each source surface made. Surfaces are immutable, so
/// identity is the key and an edited cel — a new object — misses; the entry
/// goes when its source does.
final Expando<BitmapSurface> _laidSurfaces = Expando<BitmapSurface>(
  'celTextLaidSurfaces',
);

/// The plates over each coordinate, per source surface
/// ([celTextPlatesOver]) — asked on every flush of a live stroke.
final Expando<Map<TileCoord, List<BitmapTile>>> _platesOver =
    Expando<Map<TileCoord, List<BitmapTile>>>('celTextPlatesOver');

/// What each drawing tile made under the plates laid over it lately.
final Expando<List<_LaidPair>> _laidPairs = Expando<List<_LaidPair>>(
  'celTextLaidPairs',
);

/// What each plate tile is over an empty coordinate.
final Expando<BitmapTile> _laidAlone = Expando<BitmapTile>(
  'celTextLaidAlone',
);
