import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/collection_equality.dart';
import '../native/qa_native_engine.dart';

/// The tight box of a tile's ink, in TILE-LOCAL pixels. Exclusive on the
/// far edges, like every other rect in this codebase.
typedef TileInkBounds = ({
  int left,
  int top,
  int rightExclusive,
  int bottomExclusive,
});

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

  /// Adopts a NATIVE buffer as this tile's pixels WITHOUT copying —
  /// ownership transfers to the tile (freed by its finalizer). The commit
  /// hot path hands its blend scratch over through this: a full-canvas
  /// commit materializes with zero pixel copies out.
  ///
  /// Allocation contract: the buffer must come from
  /// [QaNativeEngine.tileAlloc] when the engine is loaded (the commit
  /// scratch does), from `malloc` otherwise — the finalizer choice below
  /// mirrors exactly that.
  factory BitmapTile.adoptNative({
    required int size,
    required Pointer<Uint8> pixels,
  }) {
    _validateSize(size);
    return BitmapTile._adopt(size, pixels);
  }

  BitmapTile._adopt(this.size, Pointer<Uint8> pixels)
    : _pixels = pixels,
      _view = pixels.asTypedList(bytesFor(size)) {
    final engine = QaNativeEngine.instance;
    (engine == null ? _mallocFinalizer : engine.tileFinalizer).attach(
      this,
      pixels.cast(),
      detach: this,
      externalSize: bytesFor(size),
    );
  }

  static Pointer<Uint8> _allocate(int byteLength) {
    final engine = QaNativeEngine.instance;
    if (engine != null) {
      return engine.tileAlloc(byteLength);
    }
    return malloc<Uint8>(byteLength);
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
  final Pointer<Uint8> _pixels;
  final Uint8List _view;

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
  bool get inkBoundsKnown => _inkBounds != null || !hasInk;

  /// Adopts a box computed elsewhere — the batched C scan, which answers
  /// for many tiles in one call and would otherwise throw its answers
  /// away.
  ///
  /// ⚠️A MEMO on an immutable object, not a mutation: the pixels decide
  /// the box, the pixels never change, so the only thing this can do is
  /// save the recompute. First writer wins, and every writer computes the
  /// same answer.
  void rememberInkBounds(TileInkBounds bounds) => _inkBounds ??= bounds;

  /// The reference scan: this tile's words, in Dart.
  ///
  /// ⛔**IT IS WRITTEN OUT, AND THE WORD LOOP STAYS.** It runs per PIXEL,
  /// and it is the twin the native parity test measures the C path
  /// against — a helper call inside it would cost on both counts. It used
  /// to live in `bitmap_surface_geometry`; it moved here so the batched C
  /// scan and the reference answer the same question in one place, and so
  /// the answer can be MEMOIZED where the pixels are.
  TileInkBounds _scanInkBounds() {
    var minX = size;
    var minY = size;
    var maxX = -1;
    var maxY = -1;
    // RGBA little-endian: alpha is the word's top byte.
    final words = _view.buffer.asUint32List(
      _view.offsetInBytes,
      size * size,
    );
    for (var y = 0; y < size; y += 1) {
      final rowStart = y * size;
      for (var x = 0; x < size; x += 1) {
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

  /// 🧪**IT COMPARES EVERY BYTE, AND NO HOT PATH ASKS** (counted
  /// 2026-09-09). `listEquals` over the whole view, and `hashCode`
  /// hashes it — which would matter if a tile were ever a Set element or
  /// a Map key, or if `BitmapSurface ==` ran per frame. Neither happens:
  /// `Set<BitmapTile>` and `Map<BitmapTile` have zero hits across lib and
  /// test, no surface is compared to another anywhere in lib, and the one
  /// place that could (`SelectionFloatPaint`) uses `identical` on purpose.
  ///
  /// ⚠️**BUT IT IS NOT DEAD — THE TESTS HOLD IT AS A CONTRACT** (an
  /// earlier note here said "a call site that does not exist", which was
  /// wrong). `expectJsonRoundTrip` compares a decoded tile with the
  /// original, `bitmap_surface_test` asks that two surfaces built in
  /// different insertion orders are equal, and the history builder tests
  /// compare whole surfaces. Value equality is what those measure; it
  /// simply never runs where a frame would feel it.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitmapTile &&

          other.size == size &&
          listEquals(other._view, _view);

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
