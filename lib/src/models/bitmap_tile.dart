import 'dart:ffi';
import 'dart:typed_data';

import '../native/tile_blocks.dart';

/// The tight box of a tile's ink, in TILE-LOCAL pixels. Exclusive on the
/// far edges, like every other rect in this codebase.
typedef TileInkBounds = ({
  int left,
  int top,
  int rightExclusive,
  int bottomExclusive,
});

/// The tight box of the ink in [words] — RGBA pixels, [width] by [height],
/// one little-endian word each, so alpha is the word's top byte. A box
/// with nothing in it (`rightExclusive <= left`) where no alpha is above 0.
///
/// The tile's own scan ([BitmapTile.inkBounds]) and a picture's that is
/// not a tile — what the cut tool's 「표시」 frames (I-163) — are this loop,
/// and why it stays written out is said at the tile's scan.
TileInkBounds inkBoundsOfWords(
  Uint32List words, {
  required int width,
  required int height,
}) {
  var minX = width;
  var minY = height;
  var maxX = -1;
  var maxY = -1;
  for (var y = 0; y < height; y += 1) {
    final rowStart = y * width;
    for (var x = 0; x < width; x += 1) {
      final word = words[rowStart + x];
      if (word == 0 || (word & 0xff000000) == 0) {
        continue;
      }
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  return (
    left: minX,
    top: minY,
    rightExclusive: maxX + 1,
    bottomExclusive: maxY + 1,
  );
}

/// What reads the pixels of a tile the engine made
/// ([BitmapTile.onEngine]): the engine's tile ledger, which a model cannot
/// import.
abstract interface class TilePixelsOnEngine {
  /// Reads [tile]'s pixels into [into], a tile's bytes.
  void readInto(BitmapTile tile, Pointer<Uint8> into);
}

/// What reads the pixels of a tile the engine holds and its cel's kept
/// bytes hold besides — a shell of a cel a look let go of
/// (`BrushFrameStore.keepShellOf`, card `let-go-cels-keep-their-gpu-tiles`):
/// where the engine let its slot go, it reads them where the cel is kept.
/// So the tiles it reads are never the engine's alone
/// ([BitmapTile.isOnlyOnEngine]): a full pool lets their slots go as
/// freely as those of a tile whose bytes are here.
abstract interface class TilePixelsKeptBesides implements TilePixelsOnEngine {}

/// The word every pixel of [pixels] — RGBA, four bytes each — is, or null
/// where two differ (or there is none): a word as this machine reads four
/// bytes, which is how [BitmapTile.ofOneColour] lays it back.
///
/// 🚨THE ONE ASKER OF 「IS THIS TILE ONE COLOUR」, on whichever isolate the
/// bytes are: a tile made of bytes asks it of them, and a worker laying a
/// cel asks it before it takes a block (`layCelEntry`). A tile a person
/// drew on answers at the first pixel that differs, which is almost always
/// near the start; only a tile that IS one colour is read whole, and that
/// read is in place of the block it would have copied them into.
///
/// Through a [ByteData] because [pixels] may lie anywhere in a file's
/// payload, not on a word's edge — and two pixels at a time, against the
/// word twice over: 🔬a tile of 128² that is one colour answers in 6.7 µs
/// so, 13.5 µs a pixel at a time (2026-11-15, the Surface, compiled ahead;
/// copying it was 2.4). A last odd pixel is asked alone.
int? oneWordOf(Uint8List pixels) {
  if (pixels.length < BitmapTile.bytesPerPixel) {
    return null;
  }
  final words = ByteData.sublistView(pixels);
  final first = words.getUint32(0, Endian.host);
  // The word in both halves, so which half a machine reads first is all
  // one.
  final twice = (first << 32) | first;
  const pair = BitmapTile.bytesPerPixel * 2;
  final pairsEnd = pixels.length - pixels.length % pair;
  var at = 0;
  for (; at < pairsEnd; at += pair) {
    if (words.getInt64(at, Endian.host) != twice) {
      return null;
    }
  }
  for (; at < pixels.length; at += BitmapTile.bytesPerPixel) {
    if (words.getUint32(at, Endian.host) != first) {
      return null;
    }
  }
  return first;
}

/// Whether any pixel of [pixels] — RGBA, four bytes each — shows: its
/// alpha, the fourth byte, is not zero.
///
/// 🚨THE ONE ASKER OF 「DOES THIS TILE SHOW ANYTHING」, on whichever isolate
/// the bytes are, as [oneWordOf] is of its colour: a tile asks it of its
/// own bytes once ([BitmapTile.hasInk]), and a worker laying a cel asks it
/// beside [oneWordOf] (`LaidPixels`), so what it lays comes home knowing
/// ([BitmapTile.adoptNative]).
///
/// 🔬Card `a-picture-lay-holds-the-raster-thread` (the Surface, profile,
/// FNK_02 cut 59, 2026-11-17): a look letting go of its cels asked it of
/// every tile it shelled (`EngineTileLedger._shellOf`) and knew none —
/// some 27,000 tiles a sweep of the onion on, 108–156 ms of the UI
/// isolate's, outside every frame; nine in ten had ink.
bool anyInkIn(Uint8List pixels) {
  const step = BitmapTile.bytesPerPixel;
  for (var at = step - 1; at < pixels.length; at += step) {
    if (pixels[at] != 0) {
      return true;
    }
  }
  return false;
}

/// Where a tile's pixels lie on this side: a block the tile alone holds, or
/// its colour's.
///
/// 🚨ONE FIELD OF THE TILE, TWO SHAPES (관제 2026-11-15, card
/// `a-file-keeps-all-clear-tiles-in-its-cels`: 「블록을 쥔다 / 낱말 하나다를
/// 한 필드의 두 꼴로」). A block pointer that may be null beside a word
/// that may be unset would let a tile be written with both, or with
/// neither — and every reader would have to know which pair means what.
sealed class _PixelsHere {
  /// The block the engine reads directly.
  Pointer<Uint8> get block;

  /// The same bytes, never written through.
  Uint8List get view;
}

/// A block one tile holds alone, freed as that tile is collected
/// ([TileBlocks.freeWith], asked by the tile).
///
/// Its address and not a [Pointer]: a pointer kept is one more object a
/// tile for the collector to walk (card
/// `a-thawed-cel-is-adopted-on-the-ui-thread` — the tiles alive are what
/// its pauses are made of), and one made for a read is gone with the read.
final class _OwnBlock implements _PixelsHere {
  _OwnBlock(Pointer<Uint8> block, int byteLength, this.weighedBy)
    : _address = block.address,
      view = block.asTypedList(byteLength);

  final int _address;

  /// The weight this block is a part of, where its tile was made with
  /// others at once ([TileWeight]): held so that it goes with the last of
  /// them.
  ///
  /// 🚨READ BY NOTHING, AND SO AN ENTRY POINT: the AOT compiler takes away
  /// a field nothing reads, and the weight with it — told, then let go at
  /// the next collection while its tiles stood. 🔬`dart compile exe` (저장
  /// 2026-11-16): of 100 values held by such a field alone, none lived
  /// through a churn of collections — 100 under the JIT, and 100 in the exe
  /// with this pragma. Tests run on the JIT, so only a pin on the source
  /// sees it (`a_tile_weight_is_held_in_aot_test.dart`).
  @pragma('vm:entry-point')
  final TileWeight? weighedBy;

  @override
  final Uint8List view;

  @override
  Pointer<Uint8> get block => Pointer.fromAddress(_address);
}

/// The pixels of every tile of one colour and one size: a tile's worth of
/// one word, ONE block however many tiles show it, freed when the last of
/// them is collected.
///
/// Found by its size and word among those alive on this isolate ([of]) —
/// held weakly there, so the tiles are all that keep it. A colour whose
/// last tile went is laid again by the next tile of it.
final class _ColourBlock implements _PixelsHere, Finalizable {
  _ColourBlock._(this.block, int tileSize, int word)
    : view = block.asTypedList(BitmapTile.bytesFor(tileSize)) {
    block
        .cast<Uint32>()
        .asTypedList(tileSize * tileSize)
        .fillRange(0, tileSize * tileSize, word);
    TileBlocks.freeWith(this, block, view.length);
  }

  /// The block of [word] for tiles of [tileSize]: the one alive, or a new
  /// one.
  factory _ColourBlock.of(int tileSize, int word) {
    final key = tileSize * _words + word;
    final alive = _alive[key]?.target;
    if (alive != null) {
      return alive;
    }
    final laid = _ColourBlock._(
      TileBlocks.alloc(BitmapTile.bytesFor(tileSize)),
      tileSize,
      word,
    );
    _alive[key] = WeakReference(laid);
    _forgets.attach(laid, key);
    return laid;
  }

  /// How many words there are: a key is a tile size and a word, side by
  /// side.
  static const int _words = 0x100000000;

  static final Map<int, WeakReference<_ColourBlock>> _alive = {};

  /// Takes a collected block's entry out of [_alive] — unless a new block
  /// of the same colour took the key first.
  static final Finalizer<int> _forgets = Finalizer((key) {
    if (_alive[key]?.target == null) {
      _alive.remove(key);
    }
  });

  @override
  final Pointer<Uint8> block;

  @override
  final Uint8List view;

  /// Whether the colour has any alpha — what every tile of it answers
  /// [BitmapTile.hasInk] with, unread. Alpha is a pixel's fourth byte,
  /// whichever way the machine reads a word.
  bool get hasInk => view[BitmapTile.bytesPerPixel - 1] != 0;
}

/// One immutable 4-byte-RGBA tile whose pixels live in NATIVE memory
/// (R19-Z zero-copy tile storage).
///
/// Why native: tile pixels dominated the Dart heap (hundreds of MB at
/// large canvas sizes — every GC walked them). Native backing removes the
/// GC weight, and lets a worker that lays a cel hand its blocks over as
/// the finished tiles with ZERO copies ([BitmapTile.adoptNative]).
/// ↩️Till 2026-11-12 the C brush was the rest of the reason: every commit
/// paid VM-speed copies in AND out of its native blend scratch, its
/// kernels needed staging copies to get stable pointers, and a commit
/// adopted its scratch buffer as the finished tile.
///
/// Lifetime: the buffer is freed when the tile is collected, and its real
/// weight told to the GC ([TileBlocks.freeWith]).
/// Buffers come from the engine's lists ([TileBlocks], R20-E1) and the
/// finalizer parks them there for reuse — tile churn (decode, the engine's
/// tiles read back, undo drops) recycles instead of malloc/freeing.
///
/// 🚨A TILE OF ONE COLOUR HOLDS NO BLOCK OF ITS OWN (2026-11-15, card
/// `a-file-keeps-all-clear-tiles-in-its-cels`). Where every pixel of it is
/// one word its pixels are that colour's block, one for every tile of the
/// colour alive ([_ColourBlock]). The tile says so as it is made — of
/// bytes ([BitmapTile.new], [BitmapTile.written]: [oneWordOf]) or of the
/// word a worker found in them ([BitmapTile.ofOneColour]) — and never
/// after, so what it weighs ([ownBytes]) cannot change under a ledger that
/// added it. Every reader reads it as any tile ([readPixels]).
/// 🔬Why: a user's file (2026-11-15; 1,328 cels, 192,463 tiles) kept
/// 37,756 tiles with no alpha at all — a picture brought in on its white,
/// the white taken off by a destructive verb, the emptied tiles kept each
/// in its place for the undo that walks them
/// (`BitmapSurface.putMaterializedTiles`) — and 30,625 of those were one
/// word, 30,536 a white with no alpha. In one cut 27,912 such tiles were
/// 1.7 GiB of the 4.2 GiB its cels weighed hot, on a machine whose hot
/// cels may weigh 4.3. Another 8,753 tiles were one OPAQUE colour.
/// ⛔Not asked of its ink: whether a tile shows anything ([hasInk]) is
/// another question, and a tile of one opaque colour is one colour too.
/// ⛔The tile stays where it is, with its colour: the undo that walks a
/// cel's tiles, and whatever reads a colour behind no alpha, find what
/// they found.
/// ⚠️A tile the engine made ([BitmapTile.onEngine]) is never one: its
/// bytes come here after it was made, and after it was weighed.
///
/// NOTE — Finalizable objects cannot cross isolates: the .anicel save/open
/// paths snapshot tiles to plain byte records at the isolate boundary.
class BitmapTile implements Finalizable {
  factory BitmapTile({
    required int size,
    required Uint8List pixels,
    TileWeight? weighedBy,
  }) {
    _validateSize(size);
    _validatePixelLength(pixels.length, size);
    final word = oneWordOf(pixels);
    if (word != null) {
      return BitmapTile.ofOneColour(size: size, word: word);
    }
    final buffer = TileBlocks.alloc(pixels.length);
    buffer.asTypedList(pixels.length).setAll(0, pixels);
    return BitmapTile._adopt(size, buffer, weighedBy);
  }

  factory BitmapTile.blank({required int size}) =>
      BitmapTile.ofOneColour(size: size, word: 0);

  /// A tile every pixel of which is [word] ([oneWordOf]'s): it holds its
  /// colour's block and none of its own.
  factory BitmapTile.ofOneColour({required int size, required int word}) {
    _validateSize(size);
    return BitmapTile._ofColour(size, _ColourBlock.of(size, word));
  }

  /// A tile whose pixels [write] lays into a fresh buffer, before anything
  /// else can read them — so it is as immutable as any tile once this
  /// returns. ⚠️[write] fills EVERY byte: the buffer is not cleared first.
  ///
  /// Bytes copied from elsewhere and rewritten land here with no copy on
  /// the Dart heap between: a live stroke's result shown as the cel will
  /// show it, 256 KB at every tile the stroke changes on every flush.
  factory BitmapTile.written({
    required int size,
    required void Function(Uint8List pixels) write,
  }) {
    _validateSize(size);
    final length = bytesFor(size);
    final buffer = TileBlocks.alloc(length);
    final int? word;
    try {
      final pixels = buffer.asTypedList(length);
      write(pixels);
      word = oneWordOf(pixels);
    } on Object {
      // No tile holds it yet, so nothing else would give it back.
      TileBlocks.free(buffer);
      rethrow;
    }
    if (word == null) {
      return BitmapTile._adopt(size, buffer);
    }
    TileBlocks.free(buffer);
    return BitmapTile.ofOneColour(size: size, word: word);
  }

  /// Adopts a NATIVE buffer as this tile's pixels WITHOUT copying —
  /// ownership transfers to the tile (freed by its finalizer). A cel laid
  /// on a worker comes home through this (`laidCelSurface`): its tiles
  /// stand with zero pixel copies on this isolate.
  /// Made with the rest of its cel at once, it is weighed with them
  /// ([TileWeight]); alone, by itself.
  ///
  /// Allocation contract: the buffer comes from [TileBlocks.alloc],
  /// whichever isolate asked — the finalizer gives it back there.
  ///
  /// ⚠️Adopted unread: whether its pixels are one colour, and whether they
  /// show anything ([hasInk]), were the worker's to ask before it took the
  /// block (`layCelEntry`, through `LaidPixels`), and asking here would
  /// read on the thread the worker was there to spare. [hasInk] is the
  /// worker's answer ([anyInkIn]).
  factory BitmapTile.adoptNative({
    required int size,
    required Pointer<Uint8> pixels,
    required bool hasInk,
    TileWeight? weighedBy,
  }) {
    _validateSize(size);
    return BitmapTile._adopt(size, pixels, weighedBy, hasInk);
  }

  BitmapTile._adopt(
    this.size,
    Pointer<Uint8> pixels, [
    TileWeight? weighedBy,
    bool? hasInk,
  ]) : _onEngine = null,
       _hasInk = hasInk {
    _hold(pixels, weighedBy);
  }

  BitmapTile._ofColour(this.size, _ColourBlock colour)
    : _onEngine = null,
      _here = colour,
      _hasInk = colour.hasInk,
      _inkBounds = colour.hasInk
          ? (left: 0, top: 0, rightExclusive: size, bottomExclusive: size)
          : null;

  /// A tile whose pixels are the engine's alone: [on] reads them here only
  /// for a caller that asks for bytes. [hasInk] where its maker knows.
  ///
  /// ⏳A caller still on the CPU reads a copy that stays with the tile, flip
  /// lane ⓒ's bridge: each writer moved to the engine is one less, and ⓔ
  /// deletes the bytes with the last.
  BitmapTile.onEngine({
    required this.size,
    required TilePixelsOnEngine on,
    bool? hasInk,
  }) : _onEngine = on,
       _hasInk = hasInk {
    _validateSize(size);
  }

  void _hold(Pointer<Uint8> pixels, [TileWeight? weighedBy]) {
    final bytes = bytesFor(size);
    _here = _OwnBlock(pixels, bytes, weighedBy);
    TileBlocks.freeWith(this, pixels, bytes, weighedBy: weighedBy);
  }

  /// Whether the engine made it: its pixels are there, and read here only
  /// for a caller that asks.
  bool get isOnEngine => _onEngine != null;

  /// Whether the engine holds the only copy of its pixels — none here to
  /// store again from, so its slot there is not one a full pool lets go. A
  /// shell's are kept besides ([TilePixelsKeptBesides]).
  bool get isOnlyOnEngine =>
      _onEngine != null && _onEngine is! TilePixelsKeptBesides && _here == null;

  /// Holds [bytes] — the pixels of a tile the engine alone holds
  /// ([isOnlyOnEngine]), read back by whoever holds its slot — as a read of
  /// its own would ([_readBack]).
  void keepBytesHere(Uint8List bytes) {
    assert(isOnlyOnEngine, 'its pixels are here already');
    _validatePixelLength(bytes.length, size);
    final block = TileBlocks.alloc(bytes.length);
    block.asTypedList(bytes.length).setAll(0, bytes);
    _hold(block);
  }

  /// Throws for a [size] no tile takes — what every constructor asks first.
  static void checkSize(int size) => _validateSize(size);

  static const int bytesPerPixel = 4;

  /// Bytes ONE tile of [size] occupies. The same product was written out
  /// in eight places across four files; a stale copy of it is an undo
  /// budget that lies about what it holds, so there is one place now.
  static int bytesFor(int size) => size * size * bytesPerPixel;

  /// What this tile holds that no other does: a tile's bytes, and nothing
  /// where its pixels are its colour's block — the one answer for whoever
  /// weighs tiles (the hot cels, an undo entry, the memory census).
  ///
  /// A colour's block itself is in nobody's sum: one tile's bytes for each
  /// colour alive.
  /// ⚠️A tile the engine made weighs a tile's bytes wherever they lie, as
  /// it did before this was asked.
  int get ownBytes => _here is _ColourBlock ? 0 : bytesFor(size);

  /// What a store of this tile's pixels elsewhere is found by: the tile
  /// itself, or — where its pixels are its colour's block — that block,
  /// the one object every tile of the colour alive holds ([_ColourBlock]).
  /// The engine's tile ledger keys its slots by it
  /// (`EngineTileLedger._slotNow`): the tiles of one colour are one slot.
  ///
  /// Never changes while the tile lives: a tile is of one colour as it is
  /// made and never after, and one the engine made is never one
  /// ([BitmapTile.onEngine]). The same identity [==] reads unread
  /// ([_samePixelsAs]) — no pixel is compared to find it.
  Object get pixelsKey => switch (_here) {
    final _ColourBlock colour => colour,
    _ => this,
  };

  final int size;

  /// Where a tile the engine made reads its pixels from; null for one made
  /// here, whose bytes are held from the start.
  final TilePixelsOnEngine? _onEngine;

  /// Its pixels on this side; null while the engine holds the only copy
  /// ([isOnlyOnEngine]).
  _PixelsHere? _here;

  _PixelsHere get _read => _here ?? _readBack();

  Pointer<Uint8> get _pixels => _read.block;

  Uint8List get _view => _read.view;

  _PixelsHere _readBack() {
    _hold(TileBlocks.alloc(bytesFor(size)));
    final read = _here!;
    try {
      _onEngine!.readInto(this, read.block);
      return read;
    } catch (_) {
      // The block stays with the tile's finalizer; a garbage view must not.
      _here = null;
      rethrow;
    }
  }

  /// A defensive COPY of the pixel bytes (cold paths: codec, json,
  /// stamp/lift builds). Hot paths use [readPixels]/[copyPixelsInto].
  Uint8List get pixels => Uint8List.fromList(_view);

  /// Runs [body] with the tile's native buffer — the pointer the engine
  /// reads directly (blend staging, premultiply) and a view over the same
  /// bytes, with no Dart-side copy. NEVER written through: tiles are
  /// immutable.
  ///
  /// THIS IS THE ONLY WAY TO REACH THE BYTES, and the reason is lifetime.
  /// A raw `nativePixels` getter used to exist; pulling the pointer (or an
  /// `asTypedList` view of it) into a local does NOT keep the tile alive —
  /// [Finalizable] protects a RECEIVER for the duration of a call, not a
  /// value that outlives the getter. A tile whose only reference was such
  /// a local could be collected mid-read: its [NativeFinalizer] handed the
  /// block back to the lists ([TileBlocks]), the lists handed it to the
  /// next ask, and the copy then read/wrote another live buffer —
  /// an access violation when the block had been unmapped, silent pixel
  /// corruption when it had not. (Found the hard way: the stroke
  /// promotion round raised tile churn enough to make it reproducible,
  /// but the hazard shipped with R27 #4c's pre-blend and with every
  /// `bitmapSurfaceRegionPixels` call before it.)
  ///
  /// Inside [body] the tile is the receiver of an executing method, so it
  /// — and its buffer — are alive for the whole call. Do not let the
  /// pointer or the view escape [body] unless the caller keeps the TILE
  /// itself reachable for as long as they are used.
  T readPixels<T>(T Function(Pointer<Uint8> pointer, Uint8List view) body) {
    return body(_pixels, _view);
  }

  bool? _hasInk;

  /// Whether ANY pixel of this tile is not fully transparent.
  ///
  /// 🚨Cached, and cheap for the reason that matters: a tile a person drew
  /// on answers on its first opaque byte, which is almost always near the
  /// start. Only a tile that is ENTIRELY clear pays a full read, and it pays
  /// it once — tiles are immutable, so the answer cannot go stale, and the
  /// tiles a clear rebuilds are new objects that compute it fresh.
  ///
  /// ⛔This is not 「count the ink」. 유저 2026-08-27: 「잉크를 세는건
  /// 무거운거아니야?」 — it is, which is why nothing here counts anything.
  ///
  /// 🪦**IT HAD A TWIN, `isFullyTransparent`, AND THE TWIN WAS WORSE ON
  /// EVERY AXIS.** The twin read every byte instead of every fourth,
  /// cached nothing, and asked a STRICTER question — all bytes zero rather
  /// than all alphas zero — so a tile whose alpha had been cleared while
  /// its colour bytes stayed behind read as "still has something" to one
  /// and "blank" to the other. Nothing wants the stricter question:
  /// source-over draws nothing at alpha 0 whatever the colour bytes say,
  /// and all five of the twin's callers were asking「is there anything to
  /// draw here」. Deleted 2026-09-08; the callers ask this.
  ///
  /// ⚠️A tile a worker laid comes home with it ([BitmapTile.adoptNative]):
  /// the worker asked its bytes ([anyInkIn]), so this thread reads none.
  bool get hasInk => _hasInk ??= anyInkIn(_view);

  TileInkBounds? _inkBounds;

  /// The tight box of this tile's ink, in TILE-LOCAL pixels — null when
  /// the tile has none.
  ///
  /// 🚨★★★**EVERY COMMIT RESCANNED EVERY PIXEL THE CEL HELD.** The
  /// surface-level scan ([bitmapSurfaceContentBounds]) is memoized by its
  /// callers ON THE SURFACE INSTANCE, and a commit MAKES a new instance —
  /// so the memo missed exactly when it mattered and the answer was
  /// rebuilt from scratch while the user drew. Almost none of that work
  /// was new: a commit replaces a handful of tiles and the rest are the
  /// SAME OBJECTS, whose ink cannot have moved because a tile is
  /// immutable. Memoized here, an unchanged tile answers in O(1) and only
  /// the tiles the stroke actually touched are scanned.
  ///
  /// ⛔**NOT a second [hasInk].** That one answers on its first opaque
  /// byte, which for a drawn-on tile is almost immediately; this one has
  /// to read every pixel to know the extent. Folding them would make the
  /// cheap question pay the expensive question's price. They agree by
  /// construction instead — no ink, no box — which is why `??=` is enough
  /// here with no "computed yet" flag beside it.
  TileInkBounds? get inkBounds {
    if (!hasInk) {
      return null;
    }
    return _inkBounds ??= _scanInkBounds();
  }

  /// Whether [inkBounds] can answer without reading pixels — what a
  /// BATCHED scan asks so it stages only the tiles that still owe one.
  bool get inkBoundsKnown => _inkBounds != null || _hasInk == false;

  /// Adopts what the engine found ([EngineTileLedger.rememberInk]), a box or
  /// null for no ink at all — a batched scan, which answers
  /// for many tiles in one call and would otherwise throw its answers
  /// away.
  ///
  /// ⚠️A MEMO on an immutable object, not a mutation: the pixels decide
  /// the box, the pixels never change, so the only thing this can do is
  /// save the recompute. First writer wins, and every writer computes the
  /// same answer.
  void rememberInkBounds(TileInkBounds? bounds) {
    _hasInk ??= bounds != null;
    _inkBounds ??= bounds;
  }

  /// Forgets what was known of its ink ([hasInk], [inkBounds]).
  ///
  /// 🚨A TILE IS IMMUTABLE BUT FOR ONE EVENT, AND THIS IS THAT EVENT'S: the
  /// engine held the only copy of its pixels ([isOnlyOnEngine]) and its
  /// device went with them, so the tile reads as the picture it landed on
  /// (`EngineTileLedger`, 🗣️gpu-canonical-store-Q11, 유저 2026-11-10:
  /// 「RAM 에 사본을 두고 앱을 유지한다」) — and what its maker said of its
  /// ink was said of the pixels that are gone.
  void forgetInk() {
    assert(isOnEngine, 'only a tile the engine made loses its pixels');
    _hasInk = null;
    _inkBounds = null;
  }

  /// The reference scan: this tile's words, in Dart.
  ///
  /// ⛔**IT IS WRITTEN OUT, AND THE WORD LOOP STAYS.** It runs per PIXEL,
  /// and a helper call inside it would cost there. It used to live in
  /// `bitmap_surface_geometry`; it moved here so the answer can be
  /// MEMOIZED where the pixels are. Since I-163 the loop itself is
  /// [inkBoundsOfWords] — one call per tile, outside the pixel loop — so a
  /// picture that is not a tile asks the same scan. ↩️Till ABI 74 it was
  /// also the twin a native parity test measured a batched C scan against;
  /// the engine finds a cel's ink now (`EngineTileLedger.rememberInk`).
  TileInkBounds _scanInkBounds() => inkBoundsOfWords(
    _view.buffer.asUint32List(_view.offsetInBytes, size * size),
    width: size,
    height: size,
  );

  /// Copies the pixel bytes into [target] without the intermediate copy
  /// the [pixels] getter makes.
  void copyPixelsInto(Uint8List target) {
    target.setRange(0, _view.length, _view);
  }

  int byteOffsetForPixel({required int x, required int y}) {
    if (x < 0) {
      throw ArgumentError.value(
        x,
        'x',
        'BitmapTile pixel x must be greater than or equal to 0.',
      );
    }
    if (y < 0) {
      throw ArgumentError.value(
        y,
        'y',
        'BitmapTile pixel y must be greater than or equal to 0.',
      );
    }
    if (x >= size) {
      throw ArgumentError.value(x, 'x', 'BitmapTile pixel x must be < size.');
    }
    if (y >= size) {
      throw ArgumentError.value(y, 'y', 'BitmapTile pixel y must be < size.');
    }
    return (y * size + x) * bytesPerPixel;
  }

  /// A tile with new PIXELS.
  ///
  /// 🪦**IT USED TO TAKE A COORDINATE, AND THAT WAS THE EXPENSIVE**
  /// **SPELLING OF A RENAME.** Moving a tile to another coordinate
  /// through here allocated a native buffer and memcpy'd the whole tile
  /// to change two integers — 64 KB at 128px, over every cel of a cut,
  /// on an anchored canvas resize. It was answered first by a
  /// buffer-sharing `rebasedTo` (2026-09-09) and then by this: a tile
  /// has no coordinate at all, so a shift is a map-key rewrite that
  /// keeps the very same object — and with it every decoded picture
  /// the image cache holds under it.
  BitmapTile copyWith({int? size, Uint8List? pixels}) {
    return BitmapTile(

      size: size ?? this.size,
      pixels: pixels ?? _view,
    );
  }

  Map<String, dynamic> toJson() => {

    'size': size,
    'pixels': _view.toList(),
  };

  factory BitmapTile.fromJson(Map<String, dynamic> json) {
    return BitmapTile(

      size: json['size'] as int,
      pixels: Uint8List.fromList((json['pixels'] as List).cast<int>()),
    );
  }

  /// 🧪**IT COMPARES EVERY PIXEL — A WORD AT A TIME, SINCE 2026-10-06.**
  /// ↩️Until then it was `listEquals` over the bytes, a closure call for
  /// each of a tile's quarter-million, under the heading 「NO HOT PATH
  /// ASKS」 (counted 2026-09-09). One asks now: a text's bake keeps the
  /// tiles of its last plate that came out the same (`bakeCelTextPlate`,
  /// R9-rest) — once per tile per bake, while the person types — and a
  /// tile that did not change is exactly the one that pays the whole walk.
  ///
  /// `hashCode` still hashes every byte, which would matter if a tile were
  /// ever a Set element or a Map key, or if `BitmapSurface ==` ran per
  /// frame. Neither happens: `Set<BitmapTile>` and `Map<BitmapTile` have
  /// zero hits across lib and test, no surface is compared to another on a
  /// frame's path, and the one place that could (`SelectionFloatPaint`)
  /// uses `identical` on purpose.
  ///
  /// ⚠️**THE TESTS HOLD IT AS A CONTRACT TOO** (an earlier note here said
  /// "a call site that does not exist", which was wrong).
  /// `expectJsonRoundTrip` compares a decoded tile with the original,
  /// `bitmap_surface_test` asks that two surfaces built in different
  /// insertion orders are equal, and the history builder tests compare
  /// whole surfaces.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitmapTile && other.size == size && _samePixelsAs(other);

  /// Whether [other], a tile of this one's size, holds this one's pixels —
  /// unread where the two are of one colour, and so hold one block.
  bool _samePixelsAs(BitmapTile other) =>
      (_here != null && identical(_here, other._here)) ||
      holdsBytes(other._view);

  /// Whether [bytes], a tile's worth lying on a word's edge, are this
  /// tile's pixels.
  bool holdsBytes(Uint8List bytes) {
    // RGBA: one 32-bit word is one pixel.
    final count = size * size;
    final mine = _view.buffer.asUint32List(_view.offsetInBytes, count);
    final theirs = bytes.buffer.asUint32List(bytes.offsetInBytes, count);
    for (var i = 0; i < count; i += 1) {
      if (mine[i] != theirs[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(size, Object.hashAll(_view));

  @override
  String toString() =>
      'BitmapTile(size: $size, pixelLength: ${_view.length})';
}

/// What [tiles] hold that no other tile does, in all — each as it says of
/// itself ([BitmapTile.ownBytes]): THE sum for whoever weighs tiles.
int ownBytesOf(Iterable<BitmapTile> tiles) {
  var bytes = 0;
  for (final tile in tiles) {
    bytes += tile.ownBytes;
  }
  return bytes;
}

void _validateSize(int size) {
  if (size <= 0) {
    throw ArgumentError.value(
      size,
      'size',
      'BitmapTile.size must be greater than 0.',
    );
  }
}

void _validatePixelLength(int length, int size) {
  final expected = size * size * BitmapTile.bytesPerPixel;
  if (length != expected) {
    throw ArgumentError.value(
      length,
      'pixels',
      'BitmapTile.pixels length must equal size * size * 4 ($expected).',
    );
  }
}

/// How a reader is handed tiles' bytes: each of [tiles] in order, a view
/// good only inside [use].
typedef TileBytesOf =
    void Function(List<BitmapTile> tiles, void Function(Uint8List bytes) use);

/// [tiles]' own bytes, each read where it lies ([BitmapTile.readPixels]):
/// the tile is the receiver there, so its buffer cannot be finalized out
/// from under the view.
void readTilesInPlace(
  List<BitmapTile> tiles,
  void Function(Uint8List bytes) use,
) {
  for (final tile in tiles) {
    tile.readPixels((_, view) => use(view));
  }
}
