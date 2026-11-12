import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:typed_data';

import 'qa_engine_abi.dart';

/// The native engine core's FFI bindings (R18 A-track).
///
/// LOAD-FALLBACK DISCIPLINE: every native function has a Dart REFERENCE
/// implementation that remains the source of truth for semantics. When
/// the library cannot be loaded (flutter_tester, an unsupported platform,
/// a packaging problem) callers silently use the Dart path — the app
/// never breaks, it just runs at Dart speed. Byte-parity between the two
/// is pinned by tests, so the native path can never silently diverge.
///
/// Tests can point at a locally built binary with the QA_ENGINE_PATH
/// environment variable.
///
/// Which binary, and which ABI generation it must speak, are decided once
/// in `qa_engine_abi.dart` — see [kQaEngineAbiVersion] for the bump
/// checklist.
class QaNativeEngine {
  QaNativeEngine._(this._premultiplyRgbaCopy);

  final void Function(Pointer<Uint8> dst, Pointer<Uint8> src, int pixelCount)
  _premultiplyRgbaCopy;

  static QaNativeEngine? _instance;
  static bool _loadAttempted = false;

  /// Test hook: the parity test's reference side, forcing Dart even when
  /// a binary loads. Which binary is [debugQaEngineLibraryPathOverride],
  /// shared by every loader.
  static bool debugForceDartFallback = false;

  static void debugResetForTests() {
    _instance = null;
    _loadAttempted = false;
  }

  /// The loaded engine, or null (Dart fallback). Load happens once.
  static QaNativeEngine? get instance {
    if (debugForceDartFallback) {
      return null;
    }
    if (!_loadAttempted) {
      _loadAttempted = true;
      _instance = _tryLoad();
    }
    return _instance;
  }

  static QaNativeEngine? _tryLoad() {
    final library = openQaEngineLibrary();
    if (library == null) {
      return null;
    }
    try {
      final premultiplyRgbaCopy = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, Pointer<Uint8>, Int32),
            void Function(Pointer<Uint8>, Pointer<Uint8>, int)
          >('qa_premultiply_rgba_copy');
      return QaNativeEngine._(premultiplyRgbaCopy);
    } on Object {
      return null;
    }
  }

  /// R25: fused premultiplied copy of an already-NATIVE tile buffer
  /// (the live rasterizer's stroke tiles) — one C call replaces the
  /// overlay's per-tile Dart row-copy + premultiply loops. Free the
  /// scratch in the decode callback.
  QaStampScratch premultipliedTileScratch(
    Pointer<Uint8> source,
    int pixelCount,
  ) {
    final buffer = malloc<Uint8>(pixelCount * 4);
    _premultiplyRgbaCopy(buffer, source, pixelCount);
    return QaStampScratch._(buffer.asTypedList(pixelCount * 4), buffer);
  }
}


/// A fresh premultiplied stamp buffer (R23 fill overlay): [view] feeds
/// `ui.decodeImageFromPixels`, and [free] releases it.
///
/// ⛔**NOT in the decode callback.** This line used to say that, and it was
/// the bug: `ui.decodeImageFromPixels` does not invoke its callback when it
/// REFUSES, so a failed decode leaked the whole scratch. All four call sites
/// were moved to a `finally` (see [debugLiveCount], and the note beside the
/// one in `straight_rgba_image.dart` — "THE `finally` IS THE FIX") and this
/// sentence outlived them, telling the next reader to put it back.
class QaStampScratch {
  QaStampScratch._(this.view, this._buffer) {
    _live += 1;
  }

  final Uint8List view;
  final Pointer<Uint8> _buffer;

  /// The raw buffer — a kernel writing INTO this scratch needs it.
  Pointer<Uint8> get pointer => _buffer;

  void free() {
    malloc.free(_buffer);
    _live -= 1;
  }

  static int _live = 0;

  /// How many of these are alive right now.
  ///
  /// 🧪★★★**A LEAK HERE IS INVISIBLE TO EVERYTHING ELSE.** This is a bare
  /// `malloc` with no `NativeFinalizer` behind it, so an unfreed scratch is
  /// not reclaimed by the GC, does not show up in Dart heap numbers, and
  /// costs a whole stamp — 256 KB at the production tile size, megabytes at
  /// whole-canvas. Four call sites freed it inside a decode CALLBACK, which
  /// `ui.decodeImageFromPixels` does not invoke when it refuses; every one
  /// of them now frees in a `finally` instead, and without a count the
  /// difference between those two shapes is something no test can see.
  ///
  /// ⛔Read it around an operation, never as an absolute: this is a
  /// process-wide counter and other work holds scratches at the same time.
  @visibleForTesting
  static int get debugLiveCount => _live;
}
