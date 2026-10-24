import 'dart:collection';
import 'dart:ui' as ui;

import '../core/collection_equality.dart';
import 'bitmap_tile.dart';
import 'canvas_size.dart';
import 'cel_photo.dart';
import 'cel_text.dart';
import 'dirty_region.dart';
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

/// Where a picture keeps one of its tiles: in the drawing ([text] null), or
/// in the plate of the text whose id is [text].
typedef KeptTilePlace = ({int? text, TileCoord coord});

/// A cel's PICTURE: its pixels, as tiles — and the texts set above them.
///
/// 🚨★★★**THE TEXTS ARE IN THE PICTURE'S OWN VALUE, AND THAT IS THE WHOLE
/// DESIGN OF THE TEXT TOOL** (유저 2026-10-06, R9-rest: 「주인은 셀임 … 셀의
/// 그림이랑 정확히 동일. 복사/링크도 같이감」). This is the value the app hands
/// about as 「a cel's picture」 — what a copy, a paste and an unlink carry
/// (`carrySurfaces`), what undo puts back (`restoreSurfaceSnapshot`), what a
/// canvas resize moves (`translateBitmapSurface`), what the store keeps in
/// its three tiers and counts a revision of. A text that lives here goes
/// everywhere the picture goes, by every road that already exists. Kept
/// beside it instead — on the timeline's frame, in a store of its own — each
/// of those roads would have had to be taught, and the one nobody taught is
/// a text left behind.
///
/// ⚠️[tiles] are the DRAWING alone: what a brush writes, an eraser takes
/// and a selection lifts. What a cel SHOWS is those with the texts laid over
/// them (`celSurfaceWithTextsLaid`), and nothing that draws or reads a
/// picture may take the tiles of a surface that still carries texts.
///
/// A sheet's ink keeps its PHOTOS here too, under the drawing (I-97,
/// [photos]) — for the same reason, by the same roads. ⚠️They are no pixels
/// of the picture: nothing that reads its tiles sees them, and the sheet's
/// ink is what draws them, from the pool's file.
///
/// And where a FILE's picture was laid on it ([laidBounds]) — the one thing
/// that keeps pixels past the pasteboard — by those roads again.
class BitmapSurface {
  BitmapSurface({
    required this.canvasSize,
    this.pasteboardReach = PasteboardReach.whole,
    this.tileSize = defaultCelTileSize,
    Map<TileCoord, BitmapTile> tiles = const {},
    List<CelText> texts = const [],
    List<CelPhoto> photos = const [],
    this.laidBounds,
  }) : _tiles = Map<TileCoord, BitmapTile>.unmodifiable(tiles),
       texts = List<CelText>.unmodifiable(texts),
       photos = List<CelPhoto>.unmodifiable(photos) {
    _validateTileSize(tileSize);
    _validateCanvasSize(canvasSize);
    for (final entry in _tiles.entries) {
      _validateTileEntry(entry.key, entry.value, this);
    }
    for (final text in this.texts) {
      _validatePlate(text, this);
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
  ///
  /// 🚨★★★**[texts] RIDES EVERY DERIVATION.** A commit builds its surface
  /// through here, and a derivation that let the texts fall would make one
  /// stroke delete every letter on the cel. It is `required` for that reason
  /// alone: nobody deriving a surface gets to forget the question. [photos]
  /// ride for the same reason (I-97): a stroke over a photo keeps it, and
  /// [laidBounds] (F-374-Q8): a stroke on a laid picture keeps it whole.
  BitmapSurface._derived({
    required this.canvasSize,
    required this.pasteboardReach,
    required this.tileSize,
    required Map<TileCoord, BitmapTile> tiles,
    required Iterable<PlacedTile> added,
    required this.texts,
    required this.photos,
    required this.laidBounds,
  }) : _tiles = UnmodifiableMapView(tiles) {
    for (final placed in added) {
      _validateTileEntry(placed.coord, placed.tile, this);
    }
  }

  /// [from]'s very tiles under other [texts] — the map itself, not a view
  /// of it: a text edit changes no pixel of the drawing, and wrapping the
  /// map once more per edit would make every later read walk the wrappers.
  BitmapSurface._withTexts(BitmapSurface from, List<CelText> texts)
    : canvasSize = from.canvasSize,
      pasteboardReach = from.pasteboardReach,
      tileSize = from.tileSize,
      _tiles = from._tiles,
      texts = List<CelText>.unmodifiable(texts),
      photos = from.photos,
      laidBounds = from.laidBounds {
    for (final text in this.texts) {
      // A text this surface already carried was checked when it came in.
      if (!from.texts.any((kept) => identical(kept, text))) {
        _validatePlate(text, this);
      }
    }
  }

  /// [from]'s very tiles and texts under other [photos] — nothing of the
  /// grid to check: a photo stands on the picture, not in its tiles.
  BitmapSurface._withPhotos(BitmapSurface from, List<CelPhoto> photos)
    : canvasSize = from.canvasSize,
      pasteboardReach = from.pasteboardReach,
      tileSize = from.tileSize,
      _tiles = from._tiles,
      texts = from.texts,
      photos = List<CelPhoto>.unmodifiable(photos),
      laidBounds = from.laidBounds;

  final CanvasSize canvasSize;

  /// How far past the paper this picture's pasteboard reaches — its
  /// project's ([PasteboardReach.of], I-109). With [canvasSize] it is the
  /// picture's WALL ([pasteboard]): what a tool writes stops there, and no
  /// tile is kept past it but where a file was laid ([laidBounds]).
  ///
  /// 🚨The picture carries it, as it carries its canvas size, so every pass
  /// that writes on it asks the same wall without being told it — a stroke,
  /// a fill, a paste, a text, a lift all land through the picture.
  final PasteboardReach pasteboardReach;

  final int tileSize;
  final Map<TileCoord, BitmapTile> _tiles;

  /// The texts set above the drawing, bottom → top — 유저 2026-10-02:
  /// 「텍스트의 수직축은 해당 레이어의 가장 위임. 새로운 텍스트일수록 위에
  /// 쌓임. 즉 그림/텍스트/텍스트 이런식」. Read-only.
  final List<CelText> texts;

  /// The photos laid UNDER the drawing, bottom → top — a sheet's ink's own
  /// (I-97; 유저 2026-10-15: 「사진으로 남게(셀의 텍스트처럼)」). Read-only.
  final List<CelPhoto> photos;

  /// Where a FILE's picture was laid on this one — the canvas pixels it
  /// covers, past the pasteboard where it is larger than the wall — or null
  /// where none was. Tiles are kept there too ([containsTileCoord]).
  ///
  /// 🗣️F-374-Q8 (유저 2026-10-17: 「맞춘다 — 참조 그림은 벽 밖까지 통째로」,
  /// asked after 「클튜 사진레이어 … 깔 때 밖부분 어떻게되지? 유지되있나?
  /// 그쪽에 맞춰서 설계하고싶음」): a reference's file is laid whole, at its
  /// own size, as Clip Studio's image material and Photoshop's smart object
  /// keep theirs — so a fit that shrinks it, or a move that brings its edge
  /// in, shows all of it. ↩️It was cut at the wall (Q4 · Q6 「셀 밖은
  /// 버린다」), and a fit showed the cut as an empty band.
  ///
  /// ⚠️Only a laid file goes past the wall: what a tool writes — a stroke,
  /// a fill, a paste, a text — is still cut at the pasteboard. And it is the
  /// picture's own value, as its texts and photos are, so it goes where the
  /// picture goes: a copy, an undo, a save, a canvas resize (which moves it
  /// with its pixels and never cuts it) — and a rasterize, which changes no
  /// pixel (F-374-Q7: what is seen stays as it is seen).
  final DirtyRegion? laidBounds;

  /// The canvas-space rect this picture keeps pixels in: the pasteboard,
  /// grown to take in [laidBounds] — what a painter of it clips to and walks
  /// its tiles under.
  ui.Rect get storableRect {
    final wall = pasteboard.rect;
    final laid = laidBounds;
    return laid == null ? wall : wall.expandToInclude(laid.rect);
  }

  /// This picture's wall: its canvas's pasteboard at its reach.
  PasteboardWall get pasteboard => canvasSize.pasteboardAt(pasteboardReach);

  /// This picture with [texts] in place of its own; the drawing is the
  /// same tiles. The surface itself when [texts] is the list it holds.
  BitmapSurface withTexts(List<CelText> texts) =>
      identical(texts, this.texts) ? this : BitmapSurface._withTexts(this, texts);

  /// This picture with [photos] in place of its own; the drawing and the
  /// texts are the same. The surface itself when [photos] is its own list.
  BitmapSurface withPhotos(List<CelPhoto> photos) =>
      identical(photos, this.photos)
      ? this
      : BitmapSurface._withPhotos(this, photos);

  /// Whether this picture holds nothing at all — no tile, no text and no
  /// photo. A tile may still be blank; that is [BitmapTile.hasInk]'s
  /// question.
  bool get holdsNothing => _tiles.isEmpty && texts.isEmpty && photos.isEmpty;

  /// Whether this picture has anything to SHOW — the question a cel's block,
  /// its row image and the pixel buttons ask of it
  /// (`BrushFrameStore.celHasRenderableContent`), and the one its blob's
  /// head keeps for a cel nobody decodes (`AnicelCelBlob.showsSomething`).
  ///
  /// ⛔It does NOT count ink (유저: 「잉크를 세는건 무거운거아니야?」).
  /// [BitmapTile.hasInk] caches per tile and `any` stops at the first one
  /// that has some — a drawn cel answers on its first tile, and only a cel
  /// that is entirely clear reads to the end, once.
  ///
  /// ★A TEXT IS PICTURE (유저 2026-10-06: 「셀의 그림이랑 정확히 동일」): a
  /// cel that carries one has something to show whatever its tiles hold, so
  /// every reader of this question — the row's image, the block's tint, the
  /// pixel buttons — counts it without being told about texts. A sheet's
  /// photo is kept with its picture the same way (I-97).
  bool get showsSomething =>
      texts.isNotEmpty ||
      photos.isNotEmpty ||
      _tiles.values.any((tile) => tile.hasInk);

  /// How many tiles this picture keeps in memory: the drawing's, and every
  /// text's plate.
  int get keptTileCount {
    var count = _tiles.length;
    for (final text in texts) {
      count += text.plate.length;
    }
    return count;
  }

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
  ///
  /// 🚨★★★**THE TEXTS' PLATES ARE TILES OF THE PICTURE TOO** (R9-rest,
  /// 2026-10-06). A text carries its pixels (`CelText.plate`), and an edit
  /// of one — a letter typed, a text moved — leaves the plate it replaced
  /// held by the undo entry and by nothing else. This asked the drawing
  /// alone, so a text edit weighed nothing however large its letters: the
  /// byte budget's old blind spot, open again for one kind of tile. So the
  /// answer says WHERE each tile is kept ([KeptTilePlace]) — a drawing
  /// tile and a plate tile can stand on one coordinate. ⚠️The timings above
  /// are of the walk before it took the plates in; a cel's texts add a
  /// handful of tiles to it, and that was not measured again.
  Map<KeptTilePlace, BitmapTile> keptTilesNotSharedWith(BitmapSurface? other) {
    final live = Set<Object>.identity();
    if (other != null) {
      live.addAll(other._tiles.values);
      for (final text in other.texts) {
        live.addAll(text.plate.values);
      }
    }
    return {
      for (final entry in _tiles.entries)
        if (!live.contains(entry.value))
          (text: null, coord: entry.key): entry.value,
      for (final text in texts)
        for (final entry in text.plate.entries)
          if (!live.contains(entry.value))
            (text: text.id, coord: entry.key): entry.value,
    };
  }

  /// Bytes THIS surface holds that [other] does not —
  /// [keptTilesNotSharedWith] weighed.
  int bytesNotSharedWith(BitmapSurface? other) =>
      keptTilesNotSharedWith(other).length * tileBytes;

  /// Every tile this picture keeps — the drawing's, then each text's plate
  /// — with where it keeps it: [keptTileCount] of them.
  Map<KeptTilePlace, BitmapTile> get keptTiles => keptTilesNotSharedWith(null);

  /// The tile kept at [place], or null where this picture keeps none.
  BitmapTile? keptTileAt(KeptTilePlace place) {
    final id = place.text;
    if (id == null) {
      return _tiles[place.coord];
    }
    for (final text in texts) {
      if (text.id == id) {
        return text.plate[place.coord];
      }
    }
    return null;
  }

  /// CANVAS-grid tile columns (tiles that cover the canvas rect from the
  /// origin). Pasteboard tiles live outside this grid — see
  /// [containsTileCoord] for the storable range.
  int get tileColumnCount => _ceilDiv(canvasSize.width, tileSize);

  int get tileRowCount => _ceilDiv(canvasSize.height, tileSize);

  int get tileCount => tileColumnCount * tileRowCount;

  /// Whether [coord] is storable: any tile intersecting the PASTEBOARD
  /// ([pasteboard]), negative coords included — or the picture a file laid
  /// here ([laidBounds]).
  bool containsTileCoord(TileCoord coord) => pictureKeepsTileAt(
    coord,
    wall: pasteboard,
    tileSize: tileSize,
    laid: laidBounds,
  );

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
      pasteboardReach: pasteboardReach,
      tileSize: tileSize,
      tiles: updated,
      added: tilesToPut,
      texts: texts,
      photos: photos,
      laidBounds: laidBounds,
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
      pasteboardReach: pasteboardReach,
      tileSize: tileSize,
      tiles: updated,
      added: kept,
      texts: texts,
      photos: photos,
      laidBounds: laidBounds,
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

  /// 🪦**`removeTile` LIVED HERE AND NOTHING EVER CALLED IT.** A surface
  /// does lose tiles — but through [putMaterializedTiles], which drops a
  /// tile whose ink is gone as part of the pass that emptied it, and
  /// through [resizeBitmapSurfaceCanvas], which drops what falls outside
  /// the new pasteboard. Both are the END of a pass that knows WHY the
  /// tile is going. A bare "remove this coordinate" is the same operation
  /// with the reason removed, and no caller ever wanted it. Deleted
  /// 2026-09-10.

  BitmapSurface copyWith({
    CanvasSize? canvasSize,
    PasteboardReach? pasteboardReach,
    int? tileSize,
    Map<TileCoord, BitmapTile>? tiles,
    List<CelText>? texts,
    List<CelPhoto>? photos,
    DirtyRegion? laidBounds,
  }) {
    return BitmapSurface(
      canvasSize: canvasSize ?? this.canvasSize,
      pasteboardReach: pasteboardReach ?? this.pasteboardReach,
      tileSize: tileSize ?? this.tileSize,
      tiles: tiles ?? _tiles,
      texts: texts ?? this.texts,
      photos: photos ?? this.photos,
      laidBounds: laidBounds ?? this.laidBounds,
    );
  }

  Map<String, dynamic> toJson() => {
    'canvasSize': canvasSize.toJson(),
    if (pasteboardReach != PasteboardReach.whole)
      'pasteboardReach': pasteboardReach.name,
    'tileSize': tileSize,
    // ⚠️The coordinate is written BESIDE the tile, not inside it — the
    // tile does not carry one. The durable representations already had
    // this shape (see AnicelCelEntry.tiles); the in-memory model was the
    // one that diverged.
    'tiles': [
      for (final entry in _tiles.entries)
        {'coord': entry.key.toJson(), 'tile': entry.value.toJson()},
    ],
    if (texts.isNotEmpty) 'texts': [for (final text in texts) text.toJson()],
    if (photos.isNotEmpty)
      'photos': [for (final photo in photos) photo.toJson()],
    if (laidBounds case final laid?) 'laid': laid.toJson(),
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
      pasteboardReach: PasteboardReach.values.byName(
        json['pasteboardReach'] as String? ?? PasteboardReach.whole.name,
      ),
      // ⛔NOT [defaultCelTileSize]. This answers a different question —
      // "what did a file written before the field existed use" — and the
      // answer is history, not policy. Following the current default would
      // read those old bytes at the wrong stride.
      tileSize: json['tileSize'] as int? ?? 256,
      tiles: tiles,
      texts: [
        for (final text in json['texts'] as List? ?? const [])
          CelText.fromJson(text as Map<String, dynamic>),
      ],
      photos: [
        for (final photo in json['photos'] as List? ?? const [])
          CelPhoto.fromJson(photo as Map<String, dynamic>),
      ],
      laidBounds: switch (json['laid']) {
        final Map<String, dynamic> laid => DirtyRegion.fromJson(laid),
        _ => null,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitmapSurface &&
          other.canvasSize == canvasSize &&
          other.pasteboardReach == pasteboardReach &&
          other.tileSize == tileSize &&
          mapEquals(other._tiles, _tiles) &&
          listEquals(other.texts, texts) &&
          listEquals(other.photos, photos) &&
          other.laidBounds == laidBounds;

  @override
  int get hashCode => Object.hash(
    canvasSize,
    pasteboardReach,
    tileSize,
    Object.hashAllUnordered(
      _tiles.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(texts),
    Object.hashAll(photos),
    laidBounds,
  );

  @override
  String toString() =>
      'BitmapSurface(canvasSize: $canvasSize, tileSize: $tileSize, '
      'storedTileCount: ${_tiles.length})';
}

int _ceilDiv(int value, int divisor) => (value + divisor - 1) ~/ divisor;

/// Whether a picture of [canvas], in tiles of [tileSize], keeps a tile at
/// [coord]: any tile that touches its pasteboard, or the picture a file
/// laid on it over [laid] ([BitmapSurface.laidBounds]).
///
/// The storability law in ONE spelling — a surface asks it of itself
/// ([BitmapSurface.containsTileCoord]), and a pass that builds one on
/// another canvas or at another place (a resize, a move) asks it of the
/// picture it builds.
bool pictureKeepsTileAt(
  TileCoord coord, {
  required PasteboardWall wall,
  required int tileSize,
  required DirtyRegion? laid,
}) =>
    tileRangeHolds(wall.tileRange(tileSize), coord) ||
    (laid != null && tileRangeHolds(laid.tileRange(tileSize: tileSize), coord));

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

/// A text's plate is tiles of ITS SURFACE's grid, so it answers to the law
/// the drawing's tiles answer to ([_validateTileEntry]) — laid over them
/// coordinate for coordinate, a plate of another size or off the pasteboard
/// would have nowhere to land.
void _validatePlate(CelText text, BitmapSurface surface) {
  for (final entry in text.plate.entries) {
    _validateTileEntry(entry.key, entry.value, surface);
  }
}
