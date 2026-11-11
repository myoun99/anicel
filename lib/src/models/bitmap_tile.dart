import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../native/qa_native_engine.dart';

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

/// Where tile blocks come from, as one isolate tells another: the engine's
/// allocator by its functions' addresses, or `malloc` when that isolate runs
/// without one (both zero). [BitmapTile.blocks] reads it, [tileBlocksHere]
/// binds it.
///
/// 🚨A worker filling blocks for [BitmapTile.adoptNative] takes them from
/// the isolate that ADOPTS them: [BitmapTile._adopt] attaches the finalizer
/// by that isolate's engine, and the worker's own probe can answer otherwise.
typedef TileBlocks = ({int alloc, int free});

/// What fills tile blocks where [TileBlocks] were sent: where a block comes
/// from, and where it goes back when the work it was for fails.
typedef TileBlockHands = ({
  Pointer<Uint8> Function(int byteLength) allocate,
  void Function(Pointer<Uint8> block) free,
});

/// [blocks] bound in the isolate they were sent to.
TileBlockHands tileBlocksHere(TileBlocks blocks) {
  if (blocks.alloc == 0) {
    return (
      allocate: (byteLength) => malloc<Uint8>(byteLength),
      free: malloc.free,
    );
  }
  final engine = QaTileBlocksAt(alloc: blocks.alloc, free: blocks.free);
  return (allocate: engine.alloc, free: engine.free);
}

/// One immutable 4-byte-RGBA tile whose pixels live in NATIVE memory
/// (R19-Z zero-copy tile storage).
///
/// Why native: tile pixels dominated the Dart heap (hundreds of MB at
/// large canvas sizes — every GC walked them), every commit paid VM-speed
/// copies in AND out of the native blend scratch, and the C kernels
/// needed staging copies to get stable pointers. Native backing removes
/// the GC weight, lets the engine memcpy at full speed, and lets a
/// commit ADOPT its scratch buffer as the finished tile with ZERO copies
/// ([BitmapTile.adoptNative]).
///
/// Lifetime: a [NativeFinalizer] frees the buffer when the tile is
/// collected; [externalSize] keeps the GC honest about the real weight.
/// With the engine loaded, buffers come from the C free-list allocator
/// (R20-E1) and the finalizer parks them for reuse — tile churn (decode,
/// commit adoption, undo drops) recycles instead of malloc/freeing.
/// NOTE — Finalizable objects cannot cross isolates: the .anicel save/open
/// paths snapshot tiles to plain byte records at the isolate boundary.
class BitmapTile implements Finalizable {
  factory BitmapTile({
    required int size,
    required Uint8List pixels,
  }) {
    _validateSize(size);
    _validatePixelLength(pixels.length, size);
    final buffer = _allocate(pixels.length);
    buffer.asTypedList(pixels.length).setAll(0, pixels);
    return BitmapTile._adopt(size, buffer);
  }

  factory BitmapTile.blank({required int size}) {
    _validateSize(size);
    final length = bytesFor(size);
    final buffer = _allocate(length);
    buffer.asTypedList(length).fillRange(0, length, 0);
    return BitmapTile._adopt(size, buffer);
  }

  /// A tile whose pixels [write] lays into the tile's own fresh buffer,
  /// before anything else can read them — so it is as immutable as any
  /// tile once this returns. ⚠️[write] fills EVERY byte: the buffer is
  /// not cleared first.
  ///
  /// Bytes copied from elsewhere and rewritten land here with no copy on
  /// the Dart heap between: a live stroke's result shown as the cel will
  /// show it, 256 KB at every tile the stroke changes on every flush.
  factory BitmapTile.written({
    required int size,
    required void Function(Uint8List pixels) write,
  }) {
    _validateSize(size);
    final tile = BitmapTile._adopt(size, _allocate(bytesFor(size)));
    write(tile._view);
    return tile;
  }

  /// Adopts a NATIVE buffer as this tile's pixels WITHOUT copying —
  /// ownership transfers to the tile (freed by its finalizer). The commit
  /// hot path hands its blend scratch over through this: a full-canvas
  /// commit materializes with zero pixel copies out.
  ///
  /// Allocation contract: the buffer must come from
  /// [QaNativeEngine.tileAlloc] when the engine is loaded (the commit
  /// scratch does), from `malloc` otherwise — the finalizer choice below
  /// mirrors exactly that. A worker's blocks keep it by [tileBlocksHere]
  /// bound to this isolate's [blocks].
  factory BitmapTile.adoptNative({
    required int size,
    required Pointer<Uint8> pixels,
  }) {
    _validateSize(size);
    return BitmapTile._adopt(size, pixels);
  }

  BitmapTile._adopt(this.size, Pointer<Uint8> pixels) : _onEngine = null {
    _hold(pixels);
  }

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

  void _hold(Pointer<Uint8> pixels) {
    _block = pixels;
    _bytes = pixels.asTypedList(bytesFor(size));
    final engine = QaNativeEngine.instance;
    (engine == null ? _mallocFinalizer : engine.tileFinalizer).attach(
      this,
      pixels.cast(),
      detach: this,
      externalSize: bytesFor(size),
    );
  }

  /// Whether the engine made it: its pixels are there, and read here only
  /// for a caller that asks.
  bool get isOnEngine => _onEngine != null;

  /// Whether the engine holds the only copy of its pixels — none here to
  /// store again from, so its slot there is not one a full pool lets go.
  bool get isOnlyOnEngine => _onEngine != null && _bytes == null;

  /// Holds [bytes] — the pixels of a tile the engine alone holds
  /// ([isOnlyOnEngine]), read back by whoever holds its slot — as a read of
  /// its own would ([_readBack]).
  void keepBytesHere(Uint8List bytes) {
    assert(isOnlyOnEngine, 'its pixels are here already');
    _validatePixelLength(bytes.length, size);
    final block = _allocate(bytes.length);
    block.asTypedList(bytes.length).setAll(0, bytes);
    _hold(block);
  }

  /// Throws for a [size] no tile takes — what every constructor asks first.
  static void checkSize(int size) => _validateSize(size);

  static Pointer<Uint8> _allocate(int byteLength) {
    final engine = QaNativeEngine.instance;
    if (engine != null) {
      return engine.tileAlloc(byteLength);
    }
    return malloc<Uint8>(byteLength);
  }

  /// Where THIS isolate's tiles take their blocks from — [_allocate]'s
  /// choice, as a worker filling blocks for [adoptNative] here is told it.
  static TileBlocks get blocks {
    final engine = QaNativeEngine.instance;
    return engine == null
        ? (alloc: 0, free: 0)
        : (alloc: engine.tileAllocAddress, free: engine.tileFreeAddress);
  }

  static final NativeFinalizer _mallocFinalizer = NativeFinalizer(
    malloc.nativeFree,
  );

  static const int bytesPerPixel = 4;

  /// Bytes ONE tile of [size] occupies. The same product was written out
  /// in eight places across four files; a stale copy of it is an undo
  /// budget that lies about what it holds, so there is one place now.
  static int bytesFor(int size) => size * size * bytesPerPixel;


  final int size;

  /// Where a tile the engine made reads its pixels from; null for one made
  /// here, whose bytes are held from the start.
  final TilePixelsOnEngine? _onEngine;
  Pointer<Uint8>? _block;
  Uint8List? _bytes;

  Pointer<Uint8> get _pixels {
    _view;
    return _block!;
  }

  Uint8List get _view => _bytes ?? _readBack();

  Uint8List _readBack() {
    _hold(_allocate(bytesFor(size)));
    try {
      _onEngine!.readInto(this, _block!);
      return _bytes!;
    } catch (_) {
      // The block stays with the tile's finalizer; a garbage view must not.
      _block = null;
      _bytes = null;
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
  /// block back to the C tile pool, the pool handed it to the next
  /// allocation, and the copy then read/wrote another live buffer —
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
  bool get hasInk => _hasInk ??= _scanForInk();

  bool _scanForInk() {
    for (var i = bytesPerPixel - 1; i < _view.length; i += bytesPerPixel) {
      if (_view[i] != 0) {
        return true;
      }
    }
    return false;
  }

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
  /// and it is the twin the native parity test measures the C path
  /// against — a helper call inside it would cost on both counts. It used
  /// to live in `bitmap_surface_geometry`; it moved here so the batched C
  /// scan and the reference answer the same question in one place, and so
  /// the answer can be MEMOIZED where the pixels are. Since I-163 the loop
  /// itself is [inkBoundsOfWords] — one call per tile, outside the pixel
  /// loop — so a picture that is not a tile asks the same scan.
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

  /// Whether [other], a tile of this one's size, holds this one's pixels.
  bool _samePixelsAs(BitmapTile other) => holdsBytes(other._view);

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
