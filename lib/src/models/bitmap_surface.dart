import 'dart:collection';

import '../core/collection_equality.dart';
import 'bitmap_tile.dart';
import 'canvas_size.dart';
import 'pasteboard_bounds.dart';
import 'placed_tile.dart';
import 'tile_coord.dart';

/// The edge length of a cel's tiles, in canvas pixels.
///
/// 🚨★★★**ONE NUMBER, AND IT WAS WRITTEN IN EIGHT PLACES.** The surface,
/// the edit-session store, the display cache service, the live stroke
/// rasterizer (whose own comment called its copy「the committed surface's
/// own default」), the stroke overlay, and three import paths each declared
/// `256` as their own default — and NOT ONE of their callers passes a tile
/// size, so they agreed only by everybody happening to type the same
/// number. A surface at one size with an overlay at another is not a slow
/// path, it is wrong pixels.
///
/// 🚨★★★**128, 유저 확정 2026-09-09**(「128로 통일해서 가자」). It was 256
/// from the first commit (`e1c5cdfa`, 2026-06-21) with no measurement and
/// no decision comment behind it. What decided it, measured on this repo:
///
/// | | 256 | **128** | 64 |
/// |---|---|---|---|
/// | commit, 20px dab | 0.37 ms | **0.36** | 2.13 |
/// | undo, 200-tap pass | 58.5 MiB | **17.2** | 5.9 |
/// | decode a whole cel | 49 ms | **31** | 103 |
/// | one paint | **0.287 ms** | 0.616 | 1.787 |
///
/// ⛔**64 loses on three of the four.** Waste is proportional to tile AREA,
/// so it wins on undo bytes — and pays 6.2x the paint and 2.1x the decode,
/// because our storage tile IS our GPU texture (one `ui.Image` per tile).
/// Krita, MyPaint and OpenToonz all use 64, but they decouple the two;
/// GIMP uses 128, which is where this landed.
const int defaultCelTileSize = 128;

class BitmapSurface {
  BitmapSurface({
    required this.canvasSize,
    this.tileSize = defaultCelTileSize,
    Map<TileCoord, BitmapTile> tiles = const {},
  }) : _tiles = Map<TileCoord, BitmapTile>.unmodifiable(tiles) {
    _validateTileSize(tileSize);
    _validateCanvasSize(canvasSize);
    for (final entry in _tiles.entries) {
      _validateTileEntry(entry.key, entry.value, this);
    }
  }

  /// A surface DERIVED from one whose tiles are already valid, with the
  /// same [canvasSize] and [tileSize] — so only [added] can be wrong, and
  /// only [added] is checked.
  ///
  /// 🚨★★★**EVERY EDIT PAID FOR EVERY TILE THE CEL HELD.** A commit builds
  /// a new surface, and the public constructor above re-validates the whole
  /// map and copies it — so the cost of putting ONE tile back was O(tiles
  /// the cel has), whatever the size of the edit. 🧪Measured, one 20px dab
  /// committed onto a cel holding: 400 tiles **0.64 ms** · 1,444 **2.13** ·
  /// 5,625 **10.54** · 22,500 **44.37**. Perfectly linear in tiles HELD,
  /// flat in tiles touched. Split at 6,400 tiles: map copy 3.19 ms,
  /// re-validation 5.51 ms.
  ///
  /// ⛔**THE LAW IS STILL [_validateTileEntry]'s, and only its** — this
  /// runs the same function, on the tiles that are actually new. A tile
  /// already in [from] was checked when it entered, against this very
  /// canvas size and tile size; asking again cannot learn anything.
  ///
  /// ⚠️[tiles] is ADOPTED, not copied: every caller builds it inline and
  /// lets go. That is the second half of the measured cost, and it is only
  /// safe because this constructor is private and no caller keeps the map.
  BitmapSurface._derived({
    required this.canvasSize,
    required this.tileSize,
    required Map<TileCoord, BitmapTile> tiles,
    required Iterable<PlacedTile> added,
  }) : _tiles = UnmodifiableMapView(tiles) {
    for (final placed in added) {
      _validateTileEntry(placed.coord, placed.tile, this);
    }
  }

  final CanvasSize canvasSize;
  final int tileSize;
  final Map<TileCoord, BitmapTile> _tiles;

  /// The tiles, read-only.
  ///
  /// 🚨★★★**THIS COPIED THE WHOLE MAP ON EVERY READ, AND IT IS READ ON
  /// EVERY HOT PATH THERE IS.** It was `Map.unmodifiable(_tiles)`, which
  /// the SDK documents as behaving like `Map.from` — a full rebuild per
  /// call. An audit found ~30 callers, and the ones that hurt are the ones
  /// asking trivial questions: `storeBakedSurface` copied the cel three
  /// times per commit to read `length`, `isEmpty`, and an `any` that its
  /// own decision comment says stops at the first inked tile — the copy
  /// ran in front of the short-circuit and made that reasoning false.
  ///
  /// ⛔The fix is NOT a family of copy-free accessors beside it. The field
  /// is already unmodifiable in both constructors — the public one copies
  /// (its caller may keep the map it passed), the derived one WRAPS
  /// (`UnmodifiableMapView`, O(1), over a map its caller built inline and
  /// let go of). So the getter can hand the field over as it is, and every
  /// caller stops paying without any of them changing.
  Map<TileCoord, BitmapTile> get tiles => _tiles;

  /// Bytes one of THIS surface's tiles occupies — the multiplier every
  /// undo-weight answer needs, taken from the tile rather than re-derived.
  int get tileBytes => BitmapTile.bytesFor(tileSize);

  /// The tiles THIS surface holds that [other] does not — what a snapshot
  /// of it is actually keeping alive while [other] is live.
  ///
  /// 🚨THE ONE ANSWER TO "WHAT DOES AN UNDO ENTRY HOLD". Tile maps are
  /// immutable and share structurally: wherever an edit did not reach,
  /// both surfaces hold the SAME object, and the live one keeps it alive
  /// on its own. Five commands used to answer this five ways and three
  /// answered wrong — one reported the STAMP rectangle (2048× out on a
  /// 64×64 stamp, zero when the stamp was null), so the byte budget never
  /// fired at all.
  ///
  /// ⛔Counting every tile instead is not conservative, it is wrong in the
  /// expensive direction: a top-left grow shares all of them, and billing
  /// it evicted the real history with phantom bytes.
  ///
  /// ⚠️A stroke that CREATES tiles owes nothing for them — [other] has
  /// them and this snapshot does not, and undoing restores their absence.
  /// Counting changed tiles instead over-reports exactly there.
  ///
  /// ⚠️THE SET, not a count, because the byte budget was never the only
  /// question: spilling has to WRITE exactly these tiles and leave the
  /// shared ones referenced. Two answers derived from one walk rather
  /// than two walks that could disagree about what "shared" means.
  /// 🧪**AND IT IS COMPUTED EAGERLY, PER SNAPSHOT — MEASURED, THEN KEPT**
  /// (2026-09-09). An undo PAIR builds two of these, so a pen-up pays for
  /// two identity sets and two walks. Cost against the tiles a cel holds:
  /// 135 → **28.1 µs**, 400 → **26.7**, 1,024 → **51.3**, 4,096 → **236**.
  /// A 1920×1080 cel at 128px holds 135 tiles of canvas grid and a 4096²
  /// one holds 1,024, so a commit spends 0.3–0.6% of a 60fps frame on the
  /// pair. Deferring the second half would need the surface it was
  /// measured against held on the side and released in step with the
  /// tiles — a second nullable meaning nothing measured asks for.
  Map<TileCoord, BitmapTile> tilesNotSharedWith(BitmapSurface? other) {
    final live = Set<Object>.identity()
      ..addAll(other?._tiles.values ?? const <BitmapTile>[]);
    return {
      for (final entry in _tiles.entries)
        if (!live.contains(entry.value)) entry.key: entry.value,
    };
  }

  /// Bytes THIS surface holds that [other] does not — [tilesNotSharedWith]
  /// weighed.
  int bytesNotSharedWith(BitmapSurface? other) =>
      tilesNotSharedWith(other).length * tileBytes;

  /// CANVAS-grid tile columns (tiles that cover the canvas rect from the
  /// origin). Pasteboard tiles live outside this grid — see
  /// [containsTileCoord] for the storable range.
  int get tileColumnCount => _ceilDiv(canvasSize.width, tileSize);

  int get tileRowCount => _ceilDiv(canvasSize.height, tileSize);

  int get tileCount => tileColumnCount * tileRowCount;

  /// Whether [coord] is storable: any tile intersecting the PASTEBOARD
  /// (canvas + one canvas size in every direction), negative coords
  /// included.
  bool containsTileCoord(TileCoord coord) {
    return coord.x >= canvasSize.pasteboardTileXMin(tileSize) &&
        coord.y >= canvasSize.pasteboardTileYMin(tileSize) &&
        coord.x < canvasSize.pasteboardTileXEndExclusive(tileSize) &&
        coord.y < canvasSize.pasteboardTileYEndExclusive(tileSize);
  }

  BitmapTile? tileAt(TileCoord coord) => _tiles[coord];

  /// Puts tiles — however few — in ONE map rebuild.
  ///
  /// ⛔THE BATCH IS THE ONLY PUT. A per-tile put copied the whole tile map
  /// per call, which is O(n²) across a full-canvas commit's n tiles (417ms
  /// of an 8000² fill was exactly this), so there is deliberately no
  /// one-tile form to reach for: `putTiles([tile])` is the n = 1 case and
  /// costs the same as the old single put did.
  ///
  /// ⛔THE STORABILITY LAW IS [_validateTileEntry]'s, and only its. This
  /// put re-typed the same two throws with the same two messages; the
  /// constructor every write goes through already applies them, so the
  /// copy was dead weight that could drift (a mutant that disabled the
  /// copy's bounds check survived every test, 2026-09-07).
  ///
  /// 🧪**AND THE MAP REBUILD IS O(TILES HELD) ON PURPOSE — MEASURED, THEN
  /// KEPT** (2026-09-09). Cost of `putTiles([one])` against the tiles the
  /// cel holds: 100 → **31.8 µs**, 400 → **37.3**, 1,600 → **141.7**,
  /// 6,400 → **595.6**. Linear, ~0.09 µs a tile. A 1920×1080 cel at 128px
  /// holds 135 tiles of canvas grid and a 4096² one holds 1,024, so a
  /// commit spends 0.2–0.5% of a 60fps frame here; 6,400 tiles needs an
  /// 8192² canvas inked corner to corner.
  ///
  /// ⛔**The only way to make it O(touched) is a persistent map (HAMT),
  /// and that is a trade, not a win.** It buys the write by turning
  /// [tileAt] — a hash lookup, run per tile per paint, which is far more
  /// often than a commit runs — into a trie walk. Paying a read that
  /// frequent to save a write this cheap is the wrong direction, and
  /// nothing measured says otherwise. Revisit if a real cel ever holds
  /// thousands of tiles.
  BitmapSurface putTiles(Iterable<PlacedTile> tilesToPut) {
    final updated = <TileCoord, BitmapTile>{..._tiles};
    for (final placed in tilesToPut) {
      updated[placed.coord] = placed.tile;
    }
    return BitmapSurface._derived(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: updated,
      added: tilesToPut,
    );
  }

  /// [putTiles] for a pass that MATERIALIZED these tiles — a commit tail,
  /// a geometry rebuild — where a tile with no ink left in it is dropped
  /// instead of stored.
  ///
  /// 🚨★★★**A TILE THE USER ERASED AWAY WAS KEPT AS 256 KB OF ZEROES.**
  /// Three passes materialize surfaces and each answered this its own way:
  /// the geometry rebuild filtered, the two commit tails did not. Erase a
  /// drawing to nothing and the cel still weighed what it did when it was
  /// drawn — in RAM, in the hot budget, and in every undo entry that
  /// snapshotted it.
  ///
  /// ⛔**AND IT IS DELIBERATELY NOT [putTiles]'s LAW.** The recipe rewrite
  /// ([overwriteCelPixels]) is the third caller and must NOT drop: its
  /// undo walks the tiles that exist, positionally, so a tile dropped by
  /// the forward pass is a tile the undo never visits — and 픽셀 비우기
  /// writes the alpha byte only, so the colour bytes a dropped tile
  /// carried away are gone with it and no recipe can name them. The
  /// difference is real and it is about UNDO: a commit's way back is a
  /// surface snapshot, which holds the emptied tile whole and by
  /// reference, so dropping it costs the commit nothing.
  BitmapSurface putMaterializedTiles(Iterable<PlacedTile> tilesToPut) {
    final updated = <TileCoord, BitmapTile>{..._tiles};
    // ⚠️Only what is actually STORED is checked. A blank tile is dropped,
    // and the storability law is about what a surface holds.
    final kept = <PlacedTile>[];
    for (final placed in tilesToPut) {
      final tile = placed.tile;
      if (tile.hasInk) {
        updated[placed.coord] = tile;
        kept.add(placed);
      } else {
        updated.remove(placed.coord);
      }
    }
    return BitmapSurface._derived(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: updated,
      added: kept,
    );
  }

  /// The end of a copy-on-write pass: the surface with [rebuilt] put back,
  /// or THIS VERY SURFACE when the pass wrote nothing.
  ///
  /// Handing the same object back is the structural-sharing half of the
  /// rewrite — callers test it with `identical`, and every tile the pass
  /// did not touch keeps its identity either way.
  BitmapSurface withRebuiltTiles(Map<TileCoord, BitmapTile> rebuilt) =>
      rebuilt.isEmpty
          ? this
          : putTiles([
              for (final entry in rebuilt.entries)
                (coord: entry.key, tile: entry.value),
            ]);

  BitmapSurface removeTile(TileCoord coord) {
    final nextTiles = Map<TileCoord, BitmapTile>.of(_tiles)..remove(coord);
    return BitmapSurface._derived(
      canvasSize: canvasSize,
      tileSize: tileSize,
      tiles: nextTiles,
      // Nothing new goes in, so nothing new needs checking.
      added: const [],
    );
  }

  BitmapSurface copyWith({
    CanvasSize? canvasSize,
    int? tileSize,
    Map<TileCoord, BitmapTile>? tiles,
  }) {
    return BitmapSurface(
      canvasSize: canvasSize ?? this.canvasSize,
      tileSize: tileSize ?? this.tileSize,
      tiles: tiles ?? _tiles,
    );
  }

  Map<String, dynamic> toJson() => {
    'canvasSize': canvasSize.toJson(),
    'tileSize': tileSize,
    // ⚠️The coordinate is written BESIDE the tile, not inside it — the
    // tile does not carry one. The durable representations already had
    // this shape (see AnicelCelEntry.tiles); the in-memory model was the
    // one that diverged.
    'tiles': [
      for (final entry in _tiles.entries)
        {'coord': entry.key.toJson(), 'tile': entry.value.toJson()},
    ],
  };

  factory BitmapSurface.fromJson(Map<String, dynamic> json) {
    final tiles = <TileCoord, BitmapTile>{};
    for (final tileJson in json['tiles'] as List? ?? const []) {
      final record = tileJson as Map<String, dynamic>;
      final coord = TileCoord.fromJson(
        record['coord'] as Map<String, dynamic>,
      );
      tiles[coord] = BitmapTile.fromJson(
        record['tile'] as Map<String, dynamic>,
      );
    }
    return BitmapSurface(
      canvasSize: CanvasSize.fromJson(
        json['canvasSize'] as Map<String, dynamic>,
      ),
      // ⛔NOT [defaultCelTileSize]. This answers a different question —
      // "what did a file written before the field existed use" — and the
      // answer is history, not policy. Following the current default would
      // read those old bytes at the wrong stride.
      tileSize: json['tileSize'] as int? ?? 256,
      tiles: tiles,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitmapSurface &&
          other.canvasSize == canvasSize &&
          other.tileSize == tileSize &&
          mapEquals(other._tiles, _tiles);

  @override
  int get hashCode => Object.hash(
    canvasSize,
    tileSize,
    Object.hashAllUnordered(
      _tiles.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() =>
      'BitmapSurface(canvasSize: $canvasSize, tileSize: $tileSize, '
      'storedTileCount: ${_tiles.length})';
}

int _ceilDiv(int value, int divisor) => (value + divisor - 1) ~/ divisor;

void _validateTileSize(int tileSize) {
  if (tileSize <= 0) {
    throw ArgumentError.value(
      tileSize,
      'tileSize',
      'BitmapSurface.tileSize must be greater than 0.',
    );
  }
}

void _validateCanvasSize(CanvasSize canvasSize) {
  if (canvasSize.width <= 0) {
    throw ArgumentError.value(
      canvasSize.width,
      'canvasSize.width',
      'BitmapSurface.canvasSize.width must be greater than 0.',
    );
  }
  if (canvasSize.height <= 0) {
    throw ArgumentError.value(
      canvasSize.height,
      'canvasSize.height',
      'BitmapSurface.canvasSize.height must be greater than 0.',
    );
  }
}

/// 🪦**IT USED TO CHECK `tile.coord == key` FIRST, AND THAT CHECK IS
/// GONE BECAUSE THE STATE IS.** A tile carried its own coordinate, so
/// a tile stored under a key it disagreed with was writable and had to
/// be refused at runtime. A tile has no coordinate now — the map key is
/// the only place a tile's place is written — so the disagreement
/// cannot be spelled and there is nothing left to refuse.
void _validateTileEntry(TileCoord key, BitmapTile tile, BitmapSurface surface) {
  if (tile.size != surface.tileSize) {
    throw ArgumentError.value(
      tile.size,
      'tile.size',
      'BitmapSurface tile size must match surface tileSize.',
    );
  }
  if (!surface.containsTileCoord(key)) {
    throw ArgumentError.value(
      key,
      'tiles',
      'BitmapSurface tile coord must be inside surface tile bounds.',
    );
  }
}
