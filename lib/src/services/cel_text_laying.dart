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
/// picture stamped there at full strength would — [stampLaidOver], the
/// commit's own landing of a picture, the engine's on its grid — so 「a
/// text」 and 「those pixels drawn」 are the same bytes, and turning a text
/// into drawing is keeping this result. ↩️Until 2026-11-13 it was the CPU's
/// stamp blend over the drawing's bytes, read back from the engine for it,
/// after every stamp and stroke had gone to the engine (the CPU audit).
///
/// ⛔NEVER STORED. Like a row's colour keys this is a view made when a cel
/// is shown; the truth is the surface with its texts.
///
/// 🚨★★★EVERY ROUTE THAT DRAWS A CEL LAYS ITS TEXTS HERE
/// ([celSurfaceWithTextsLaid]) — the shared plan (`CutFrameCompositeLayer`:
/// playback, export, the camera), the editing stack's row images, the row
/// being drawn on and the conte's live picture — and the row's chain runs
/// over what it lays, keys and plugins alike. ↩️The keys and a plugin at a
/// chain's head ran with it at one seam, `celSurfaceAsShown`, guarded so no
/// route took them without the texts, until the engine ran the chain
/// (float-warp-resamples-in-the-c-engine (1)(2), 2026-11-11).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/floor_math.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_stamp_image.dart';
import '../models/cel_text.dart';
import '../models/tile_coord.dart';
import 'bitmap_surface_brush_commit.dart' show stampLaidOver;

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
  final shown = celTilesWithPlatesLaid(
    surface,
    {
      for (final coord in celTextPlatesOver(surface)!.keys)
        coord: surface.tileAt(coord),
    },
    [for (final text in surface.texts) (plate: text.plate, dx: 0, dy: 0)],
  );
  final result = surface.withTexts(const []).withRebuiltTiles({
    for (final MapEntry(:key, :value) in shown.entries)
      key: ?value,
  });
  _laidSurfaces[surface] = result;
  return result;
}

/// [surface] with the text [id] it carries TURNED INTO DRAWING: no text of
/// the surface any more, its pixels the drawing's own where they lay.
/// [surface] itself when it carries no such text.
///
/// 🗣️유저 2026-10-06: 「텍스트 그림으로 굳히기 아이디어 좋네 … 나중에
/// 도구설정에 등장시키기로」.
///
/// 🚨THE TEXT NAMED, AND NO OTHER — 유저 2026-10-07, asked which
/// (`R9-rest-Q5`): 「고른 텍스트만 굳힌다」. Its plate lands on the drawing
/// as it would with no other text on the cel ([celSurfaceWithTextsLaid] of
/// the surface carrying it alone — the header's promise kept, 「turning a
/// text into drawing is keeping this result」), and every other text is set
/// over that again, in the order they were in.
///
/// ⚠️SO THE CEL SHOWS THE SAME BYTES ONLY WHERE NO TEXT UNDER IT SHARED ITS
/// PIXELS. The drawing is under every text (유저 2026-10-02:
/// 「그림/텍스트/텍스트」): a text that stood UNDER the one turned is over it
/// from then on wherever the two share a pixel — in front of its letters,
/// and the box at its back, if it has one, in front of them too. That was
/// put to 유저 as this answer's cost, beside the other answer (turn the
/// covered ones with it and change nothing on screen), and this is the one
/// taken. ⛔Do not 「keep the picture」 by turning a text nobody picked.
///
/// ↩️For a few hours of 2026-10-07, before the answer, this did turn the
/// covered ones (`_turnedWith` — the answer this session had recommended).
BitmapSurface celSurfaceWithTextAsDrawing(BitmapSurface surface, int id) {
  final at = surface.texts.indexWhere((text) => text.id == id);
  if (at < 0) {
    return surface;
  }
  return celSurfaceWithTextsLaid(
    surface.withTexts([surface.texts[at]]),
  ).withTexts([...surface.texts]..removeAt(at));
}

/// The plates laid over each coordinate of [surface], bottom → top — every
/// text's plate that has a tile there, in the texts' order. Null when it
/// carries no text.
///
/// What a live stroke asks for the cel it is drawn on: the tiles it is
/// still changing have to show the letters over them too
/// ([celTileWithPlatesLaid]), or a stroke passing under a text would wipe
/// the letters off every tile it touched until the pen came up.
Map<TileCoord, List<Map<TileCoord, BitmapTile>>>? celTextPlatesOver(
  BitmapSurface surface,
) {
  if (surface.texts.isEmpty) {
    return null;
  }
  return _platesOver[surface] ??= {
    for (final coord in {
      for (final text in surface.texts) ...text.plate.keys,
    })
      coord: [
        for (final text in surface.texts)
          if (text.plate.containsKey(coord)) text.plate,
      ],
  };
}

/// What [coord] SHOWS on [grid]'s cel: [under] — the drawing's tile there,
/// or null where it has none — with [plates] laid over it bottom → top
/// ([celTextPlatesOver]'s). Null when nothing is there at all: no tile, and
/// no ink in any plate.
BitmapTile? celTileWithPlatesLaid(
  BitmapSurface grid,
  TileCoord coord,
  BitmapTile? under,
  List<Map<TileCoord, BitmapTile>> plates,
) => celTilesWithPlatesLaid(grid, {coord: under}, [
  for (final plate in plates) (plate: plate, dx: 0, dy: 0),
])[coord];

/// What [unders]' coordinates SHOW on [grid]'s cel — each the drawing's
/// tile there, or null where it has none — with [plates] laid over them
/// bottom → top, each moved by its whole pixels: what each becomes, null
/// where nothing is there at all. A plate lays only on the coordinates
/// asked.
///
/// 🚨★★★THE ONE FOLD. A cel's laid surface, the tile a pen-up hands its
/// picture to, the picture a fill's result shows before it lands and where
/// a carried text will land all ask this, so they cannot lay a text more
/// ways than one.
///
/// A plate lands once for all the coordinates it lays on ([stampLaidOver]:
/// one picture, one landing — the engine answers a landing at once, and a
/// landing a tile was a wait a tile). What a coordinate became under a
/// plate before is not laid again ([_laidOver]).
Map<TileCoord, BitmapTile?> celTilesWithPlatesLaid(
  BitmapSurface grid,
  Map<TileCoord, BitmapTile?> unders,
  List<CelTextPixels> plates,
) {
  final shown = {...unders};
  for (final plate in plates) {
    final asked = plate.dx == 0 && plate.dy == 0
        ? _unknownUnderItsTiles(shown, plate.plate)
        : _underItsMove(shown, plate, grid.tileSize);
    if (asked.isEmpty) {
      continue;
    }
    final (:stamp, :left, :top) = _stampOf(plate.plate, grid.tileSize);
    final laid = stampLaidOver(
      grid,
      stamp,
      left: left + plate.dx,
      top: top + plate.dy,
      unders: asked,
    );
    for (final MapEntry(:key, :value) in laid.entries) {
      shown[key] = value;
      if (plate.dx == 0 && plate.dy == 0 && value != null) {
        _remember(asked[key], plate.plate[key]!, value);
      }
    }
  }
  return shown;
}

/// What [plate], not moved, still has to land on of [shown]: each
/// coordinate it has a tile at whose answer is not known, with what is
/// under it. [shown] takes every answer that is known.
Map<TileCoord, BitmapTile?> _unknownUnderItsTiles(
  Map<TileCoord, BitmapTile?> shown,
  Map<TileCoord, BitmapTile> plate,
) {
  final asked = <TileCoord, BitmapTile?>{};
  for (final MapEntry(key: coord, value: tile) in plate.entries) {
    if (!shown.containsKey(coord) || !tile.hasInk) {
      // ⚠️A plate tile with no ink lays nothing: over a tile it leaves it,
      // and over an empty coordinate a stamp that lays nothing makes no
      // tile.
      continue;
    }
    final under = shown[coord];
    final known = _laidOver(under, tile);
    if (known != null) {
      shown[coord] = known;
    } else {
      asked[coord] = under;
    }
  }
  return asked;
}

/// The coordinates of [shown] that [plate], moved by its whole pixels,
/// reaches with a tile that holds ink, with what is under each.
Map<TileCoord, BitmapTile?> _underItsMove(
  Map<TileCoord, BitmapTile?> shown,
  CelTextPixels plate,
  int tileSize,
) {
  final asked = <TileCoord, BitmapTile?>{};
  for (final MapEntry(key: coord, value: tile) in plate.plate.entries) {
    if (!tile.hasInk) {
      continue;
    }
    final left = coord.x * tileSize + plate.dx;
    final top = coord.y * tileSize + plate.dy;
    final across = {
      floorDiv(left, tileSize),
      floorDiv(left + tileSize - 1, tileSize),
    };
    final down = {
      floorDiv(top, tileSize),
      floorDiv(top + tileSize - 1, tileSize),
    };
    for (final x in across) {
      for (final y in down) {
        final reached = TileCoord(x: x, y: y);
        if (shown.containsKey(reached)) {
          asked[reached] = shown[reached];
        }
      }
    }
  }
  return asked;
}

/// What [plate] over [under] was known to make — null when it is not known.
///
/// 🚨REMEMBERED PER PAIR OF TILES, which is what lets a person draw on a
/// cel that carries text: a stroke commits a new surface, but it makes one
/// new tile per coordinate it touched and every other tile is the object it
/// was. Remembered per surface alone, each dab would lay every text again
/// over the whole cel.
///
/// Over an empty coordinate a plate that holds nothing behind alpha 0 makes
/// ITSELF — a baked plate holds nothing there (the engine hands its pixels
/// back that way), so a text over bare paper costs no second copy of its
/// pixels. Only a plate that does carry a colour where it has no ink is
/// landed, onto nothing, to be rid of it. ↩️It cleared those pixels in a
/// walk of its own until the clone ratchet named that walk as the colour
/// keys' (`_keyedTile`, 90 → 91, 2026-10-06). The stamp already says what
/// lands over nothing.
BitmapTile? _laidOver(BitmapTile? under, BitmapTile plate) {
  if (under == null) {
    return _laidAlone[plate] ??
        (_holdsColourBehindNothing(plate) ? null : plate);
  }
  final remembered = _laidPairs[under];
  if (remembered == null) {
    return null;
  }
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
  return null;
}

/// That [plate] over [under] made [laid].
void _remember(BitmapTile? under, BitmapTile plate, BitmapTile laid) {
  if (under == null) {
    _laidAlone[plate] = laid;
    return;
  }
  final remembered = _laidPairs[under] ??= <_LaidPair>[];
  remembered.insert(0, (plate: plate, laid: laid));
  if (remembered.length > _pairsKeptPerTile) {
    remembered.removeLast();
  }
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

/// [plate] as one picture over the box of its tiles, and where its top-left
/// pixel lies on the grid — made once for it: a plate is the object it is,
/// and a text carried lands the same one at each step of the hand.
({BrushStampImage stamp, int left, int top}) _stampOf(
  Map<TileCoord, BitmapTile> plate,
  int tileSize,
) => _stamps[plate] ??= () {
  final left = plate.keys.map((coord) => coord.x).reduce(math.min);
  final top = plate.keys.map((coord) => coord.y).reduce(math.min);
  final right = plate.keys.map((coord) => coord.x).reduce(math.max);
  final bottom = plate.keys.map((coord) => coord.y).reduce(math.max);
  final width = (right - left + 1) * tileSize;
  final height = (bottom - top + 1) * tileSize;
  const bytes = BitmapTile.bytesPerPixel;
  final rgba = Uint8List(width * height * bytes);
  final row = tileSize * bytes;
  for (final MapEntry(key: coord, value: tile) in plate.entries) {
    tile.readPixels((_, view) {
      final x = (coord.x - left) * row;
      for (var y = 0; y < tileSize; y += 1) {
        final at = ((coord.y - top) * tileSize + y) * width * bytes + x;
        rgba.setRange(at, at + row, view, y * row);
      }
    });
  }
  _platesMade += 1;
  return (
    stamp: BrushStampImage(
      id: 'cel-text-plate-$_platesMade',
      width: width,
      height: height,
      rgba: rgba,
    ),
    left: left * tileSize,
    top: top * tileSize,
  );
}();

/// The plates made into pictures so far — what keeps each one's id its own.
int _platesMade = 0;

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
final Expando<Map<TileCoord, List<Map<TileCoord, BitmapTile>>>> _platesOver =
    Expando<Map<TileCoord, List<Map<TileCoord, BitmapTile>>>>(
      'celTextPlatesOver',
    );

/// What each drawing tile made under the plates laid over it lately.
final Expando<List<_LaidPair>> _laidPairs = Expando<List<_LaidPair>>(
  'celTextLaidPairs',
);

/// What each plate tile is over an empty coordinate, once landed there.
final Expando<BitmapTile> _laidAlone = Expando<BitmapTile>(
  'celTextLaidAlone',
);

/// Each plate as one picture ([_stampOf]).
final Expando<({BrushStampImage stamp, int left, int top})> _stamps =
    Expando<({BrushStampImage stamp, int left, int top})>('celTextPlateStamps');
