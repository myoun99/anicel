import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/collection_equality.dart';
import '../native/qa_native_engine.dart';
import 'tile_coord.dart';

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
    required TileCoord coord,
    required int size,
    required Uint8List pixels,
  }) {
    _validateSize(size);
    _validatePixelLength(pixels.length, size);
    final buffer = _allocate(pixels.length);
    buffer.asTypedList(pixels.length).setAll(0, pixels);
    return BitmapTile._adopt(coord, size, buffer);
  }

  factory BitmapTile.blank({required TileCoord coord, required int size}) {
    _validateSize(size);
    final length = size * size * bytesPerPixel;
    final buffer = _allocate(length);
    buffer.asTypedList(length).fillRange(0, length, 0);
    return BitmapTile._adopt(coord, size, buffer);
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
    required TileCoord coord,
    required int size,
    required Pointer<Uint8> pixels,
  }) {
    _validateSize(size);
    return BitmapTile._adopt(coord, size, pixels);
  }

  BitmapTile._adopt(this.coord, this.size, Pointer<Uint8> pixels)
    : _pixels = pixels,
      _view = pixels.asTypedList(size * size * bytesPerPixel) {
    final engine = QaNativeEngine.instance;
    (engine == null ? _mallocFinalizer : engine.tileFinalizer).attach(
      this,
      pixels.cast(),
      detach: this,
      externalSize: size * size * bytesPerPixel,
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

  final TileCoord coord;
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

  /// Copies the pixel bytes into [target] without the intermediate copy
  /// the [pixels] getter makes.
  void copyPixelsInto(Uint8List target) {
    target.setRange(0, _view.length, _view);
  }

  bool get isFullyTransparent {
    for (final byte in _view) {
      if (byte != 0) return false;
    }
    return true;
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

  BitmapTile copyWith({TileCoord? coord, int? size, Uint8List? pixels}) {
    return BitmapTile(
      coord: coord ?? this.coord,
      size: size ?? this.size,
      pixels: pixels ?? _view,
    );
  }

  Map<String, dynamic> toJson() => {
    'coord': coord.toJson(),
    'size': size,
    'pixels': _view.toList(),
  };

  factory BitmapTile.fromJson(Map<String, dynamic> json) {
    return BitmapTile(
      coord: TileCoord.fromJson(json['coord'] as Map<String, dynamic>),
      size: json['size'] as int,
      pixels: Uint8List.fromList((json['pixels'] as List).cast<int>()),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitmapTile &&
          other.coord == coord &&
          other.size == size &&
          listEquals(other._view, _view);

  @override
  int get hashCode => Object.hash(coord, size, Object.hashAll(_view));

  @override
  String toString() =>
      'BitmapTile(coord: $coord, size: $size, pixelLength: ${_view.length})';
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
