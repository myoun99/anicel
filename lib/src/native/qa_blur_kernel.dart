import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'native_scratch.dart';
import 'qa_engine_abi.dart';
import 'qa_native_engine.dart';

/// Mirror of the C `qa_blur_tile` (I-75, ABI 58) — one tile of the picture
/// a blur dab reads: the stroke's rewritten tile, or the cel's where there
/// is none yet. Sizeof is cross-checked before the kernels are used.
final class QaBlurTileStruct extends Struct {
  external Pointer<Uint16> own;
  external Pointer<Uint8> cel;
}

/// The blur brush's two C kernels (`qa_blur_dab`, `qa_blur_result_tile`)
/// — what `BrushBlurPicture` runs when the engine is loaded. Its own Dart
/// passes are the reference they match byte for byte.
class QaBlurKernel {
  QaBlurKernel._(this._blurDab, this._resultTile);

  final int Function(
    Pointer<QaDabSpecStruct> spec,
    Pointer<QaBlurTileStruct> tiles,
    int tilesWide,
    int tileX0,
    int tileY0,
    int tileSize,
    int left,
    int top,
    int rightExclusive,
    int bottomExclusive,
    int radius,
    Pointer<Uint8> scratch,
    int scratchBytes,
  )
  _blurDab;

  final int Function(
    Pointer<Uint16> own,
    Pointer<Uint8> cel,
    Pointer<Uint8> mask,
    int tileSize,
    Pointer<Uint8> out,
  )
  _resultTile;

  /// The table a dab reads its picture through, grown as dabs need.
  final _tiles = NativeScratch<QaBlurTileStruct>(
    (n) => calloc<QaBlurTileStruct>(n),
    bytesPerElement: sizeOf<QaBlurTileStruct>(),
  );

  /// What a dab's passes run through — megabytes at a large size, so held
  /// across a stroke's dabs rather than made for each, and let go at its
  /// end ([releaseScratch]).
  final _scratch = NativeScratch<Uint8>((n) => calloc<Uint8>(n));

  static QaBlurKernel? _instance;
  static bool _tried = false;

  /// The kernels, or null whenever the engine is not loaded — so a test
  /// that holds the engine back holds these back too.
  static QaBlurKernel? get instance {
    if (QaNativeEngine.instance == null) {
      return null;
    }
    if (!_tried) {
      _tried = true;
      _instance = _load();
    }
    return _instance;
  }

  static QaBlurKernel? _load() {
    final library = openQaEngineLibrary();
    if (library == null) {
      return null;
    }
    try {
      final tileSize = library
          .lookupFunction<Int32 Function(), int Function()>(
            'qa_blur_tile_sizeof',
          )
          .call();
      if (tileSize != sizeOf<QaBlurTileStruct>()) {
        return null;
      }
      return QaBlurKernel._(
        library.lookupFunction<
          Int64 Function(
            Pointer<QaDabSpecStruct>,
            Pointer<QaBlurTileStruct>,
            Int32,
            Int32,
            Int32,
            Int32,
            Int32,
            Int32,
            Int32,
            Int32,
            Int32,
            Pointer<Uint8>,
            Int64,
          ),
          int Function(
            Pointer<QaDabSpecStruct>,
            Pointer<QaBlurTileStruct>,
            int,
            int,
            int,
            int,
            int,
            int,
            int,
            int,
            int,
            Pointer<Uint8>,
            int,
          )
        >('qa_blur_dab'),
        library.lookupFunction<
          Int32 Function(
            Pointer<Uint16>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            Int32,
            Pointer<Uint8>,
          ),
          int Function(
            Pointer<Uint16>,
            Pointer<Uint8>,
            Pointer<Uint8>,
            int,
            Pointer<Uint8>,
          )
        >('qa_blur_result_tile'),
      );
    } on Object {
      return null;
    }
  }

  /// The table of [count] tiles a dab reads, to be filled before
  /// [blurDab] — valid until the next call.
  Pointer<QaBlurTileStruct> tiles(int count) => _tiles.ensure(count);

  /// Blurs the picture under the dab [spec] stages, over the rect it was
  /// clipped to, reading the [tiles] table — [tilesWide] a row from tile
  /// ([tileX0], [tileY0]).
  void blurDab(
    Pointer<QaDabSpecStruct> spec, {
    required int tilesWide,
    required int tileX0,
    required int tileY0,
    required int tileSize,
    required ({int left, int top, int rightExclusive, int bottomExclusive})
    rect,
    required int radius,
  }) {
    // The C names what it needs when the scratch is short, having written
    // nothing; the second call has it.
    var needs = _scratch.length;
    do {
      needs = _blurDab(
        spec,
        _tiles.pointer,
        tilesWide,
        tileX0,
        tileY0,
        tileSize,
        rect.left,
        rect.top,
        rect.rightExclusive,
        rect.bottomExclusive,
        radius,
        _scratch.ensure(needs),
        _scratch.length,
      );
    } while (needs > 0);
  }

  /// Lets the passes' scratch go — a stroke's end.
  void releaseScratch() => _scratch.release();

  /// The bytes the passes' scratch holds (the pin that a stroke's end lets
  /// it go).
  @visibleForTesting
  int get debugScratchBytes => _scratch.length;

  /// The finished tile into [out]: the cel ([cel], `nullptr` = nothing
  /// there) moved toward the rewritten [own] by [mask] (`nullptr` = all
  /// the way). Whether any pixel differs from the cel's.
  bool resultTile({
    required Pointer<Uint16> own,
    required Pointer<Uint8> cel,
    required Pointer<Uint8> mask,
    required int tileSize,
    required Pointer<Uint8> out,
  }) => _resultTile(own, cel, mask, tileSize, out) != 0;
}
