// The engine's Rust library carries the premultiplied copy
// (rust/src/lib.rs), and its name is found in that code asset — no library
// opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';

import 'gpu_engine_asset.dart';

/// [pixelCount] straight rgba pixels at [straight], premultiplied at
/// [into] in one pass (native/premultiply): four pixels a step where the
/// build has the SIMD. [into] may be [straight].
///
/// 🚨A SECOND SPELLING OF THE APP'S LAW (`premultiplyRgbaInPlace`), kept
/// for its speed and held to the law's bytes over every colour at every
/// alpha (a_tile_upload_is_the_apps_premultiply_test). Board card
/// `the-premultiply-is-spelled-twice-on-the-cpu` makes the two one; why it
/// stands till then is at the crate's head.
///
/// ↩️While it was the C engine's (till C ABI 83) it was looked up in a
/// binary an isolate might not have, and a tile's upload fell back to the
/// law where it was missing. `@Native` finds it in every isolate and every
/// build.
@Native<Void Function(Pointer<Uint8>, Pointer<Uint8>, Int32)>(
  symbol: 'qa_premultiply_rgba_copy',
)
external void premultiplyRgbaCopy(
  Pointer<Uint8> into,
  Pointer<Uint8> straight,
  int pixelCount,
);
