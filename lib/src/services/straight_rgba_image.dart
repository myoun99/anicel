import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../native/qa_native_engine.dart';

/// Straight-alpha [rgba] premultiplied for the display upload, with the
/// native scratch that owns those bytes when the engine took the pass —
/// release it once the decode is done, and never before.
///
/// ⛔THE NATIVE PASS AND THE DART FALLBACK ARE ONE DECISION, not two. The
/// second site to want premultiplied pixels wrote both branches out again,
/// which is how a rounding rule (`+127`, round-to-nearest, matching the C)
/// came to live in two places where only one of them said why.
({Uint8List pixels, QaStampScratch? scratch}) premultipliedStraightRgba(
  Uint8List rgba,
) {
  final native = QaNativeEngine.instance;
  if (native != null) {
    final scratch = native.premultipliedStampCopy(rgba);
    return (pixels: scratch.view, scratch: scratch);
  }
  final premultiplied = Uint8List.fromList(rgba);
  for (var i = 0; i < premultiplied.length; i += 4) {
    final alpha = premultiplied[i + 3];
    if (alpha == 255) {
      continue;
    }
    premultiplied[i] = (premultiplied[i] * alpha + 127) ~/ 255;
    premultiplied[i + 1] = (premultiplied[i + 1] * alpha + 127) ~/ 255;
    premultiplied[i + 2] = (premultiplied[i + 2] * alpha + 127) ~/ 255;
  }
  return (pixels: premultiplied, scratch: null);
}

/// Uploads STRAIGHT-alpha [rgba] as a display image.
///
/// Straight alpha is the app's storage convention and stays that way:
/// premultiplying a stored buffer would round the very colours the
/// byte-preserving paths exist to carry through untouched. So the multiply
/// happens on a COPY, for display only, and the caller's bytes are not
/// touched.
///
/// The copy and the multiply are ONE native pass into native memory — the
/// same fused kernel the fill overlay uses. As Dart (`Uint8List.fromList`
/// plus a per-pixel loop) it costs a second full-size allocation and a
/// second full traversal, which on a whole-picture buffer is tens of
/// megabytes; the Dart branch here is the no-engine fallback, not the
/// normal route.
///
/// 🚨★★★**IT ANSWERS. `ui.decodeImageFromPixels` DOES NOT.**
///
/// 🪦This was a `void` that took an `onDecoded` callback until 2026-09-08,
/// and its own header ended 「every caller needs an answer for the frames
/// before it fires」. The sentence was about the frames BEFORE — nobody had
/// asked what happens when it never fires at all. Read in the SDK source:
/// `decodeImageFromPixels` chains `ImmutableBuffer.fromUint8List().then(…)`
/// and, INSIDE that, a second `instantiateCodec().then(…).then(…)` which it
/// does not return. Neither chain carries an `onError`, a `catchError` or a
/// timeout, and the inner rejection cannot even reach the outer future. So
/// the callback fires exactly once on success and ZERO times on any
/// failure, and the caller is told nothing at all.
///
/// That is not theoretical on the platforms this ships to. On Skia — which
/// is what Windows runs, debug AND release — every decode failure funnels
/// into `Codec.getNextFrame`'s null-image branch, which completes with an
/// error into that dropped chain: a resize allocation that fails at the
/// TARGET size (the old tablets of [[old-device-support-policy]]), a buffer
/// whose length disagrees with `width * height * 4` (nothing validates
/// that), a lost GPU upload. Every caller here already wrapped this in a
/// `Completer` that had no `completeError` — seven of them, which is how
/// one unreadable movie frame could wedge the media viewer for the life of
/// its `State`.
///
/// ⚠️A `Future` cannot see the cases where the ENGINE never calls back at
/// all (an isolate torn down mid-decode; an iOS app backgrounded, where
/// Metal parks the upload in `tasks_awaiting_gpu_` with no time bound).
/// ⛔Do not answer those with a timeout: backgrounded is a wait that is
/// SUPPOSED to end when the app comes forward, and cancelling it would
/// throw away a frame that was going to arrive.
///
/// The returned image is the caller's to dispose, mounted or not.
Future<ui.Image> decodeStraightRgbaImage({
  required Uint8List rgba,
  required int width,
  required int height,

  /// The pixels to PRODUCE, when that is smaller than the buffer's own
  /// size. 🚨★★★「보이는 것만, 보이는 해상도로」 — a video frame arrives
  /// from the OS decoder at the movie's size (there is no smaller ask in
  /// the native API), but the picture the viewer KEEPS should be the size
  /// it draws. Passing these makes the big one transient instead of
  /// resident. Null means "the buffer's own size", which is every caller
  /// that came before.
  int? targetWidth,
  int? targetHeight,
}) async {
  final premultipliedCopy = premultipliedStraightRgba(rgba);
  try {
    return await uploadRawRgba(
      premultipliedCopy.pixels,
      width: width,
      height: height,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
  } finally {
    // 🚨THE `finally` IS THE FIX, not decoration. This lived inside the
    // decode callback, so a decode that failed never released the native
    // premultiply scratch — the one path where the bytes are native memory
    // rather than Dart heap, and therefore the one path where nothing else
    // ever reclaims them.
    premultipliedCopy.scratch?.free();
  }
}

/// The image [decode] produced, or null when it must not be used.
///
/// 🚨★★★**A DECODE THAT LANDS INTO A WIDGET HAS THREE ENDINGS AND ONLY ONE
/// OF THEM IS A PICTURE.** It can fail; it can succeed for an ask nobody
/// wants any more (the widget went away, or a newer request overtook it);
/// or it can arrive. The middle one is the dangerous one, because the image
/// is real engine memory and dropping the reference does not release it —
/// that is why this disposes it here rather than returning it for a caller
/// to remember to.
///
/// ⛔[onFailed] is NOT [wanted] returning false, and collapsing the two is
/// the mistake this signature exists to prevent: a stale ask should leave
/// the widget's bookkeeping alone, while a REFUSED one usually has to be
/// written down so the next attempt is allowed to happen at all.
///
/// 🪦Three `State`s wrote this dance out — the cut-piece preview, the import
/// preview and the media viewer's page render — each with its own staleness
/// token and its own idea of what a failure means. Two of them became
/// token-identical the moment the decode gained a failure path (the clone
/// ratchet named the pair on 2026-09-08), which is the third occurrence the
/// rule of three was waiting for.
Future<ui.Image?> decodedImageStillWanted(
  Future<ui.Image> decode, {
  required bool Function() wanted,
  void Function()? onFailed,
}) async {
  final ui.Image image;
  try {
    image = await decode;
  } on Object {
    onFailed?.call();
    return null;
  }
  if (wanted()) {
    return image;
  }
  image.dispose();
  return null;
}

/// Uploads PREMULTIPLIED raw RGBA as a `ui.Image`, disposing every
/// intermediate on the way.
///
/// ⛔THE FOUR DISPOSES ARE THE POINT. A codec, a descriptor and an
/// immutable buffer each hold engine memory until they are released, and
/// the two callers that wrote this out — the stroke preview and the
/// timeline tile store — each had to remember all four. One of them
/// forgetting is a leak that only shows up as growth.
///
/// ⚠️STRAIGHT alpha goes through [premultipliedStraightRgba] first: this
/// takes what the engine will draw, not what the app stores.
///
/// 🚨★★★**THIS IS `ui.decodeImageFromPixels`, WRITTEN SO IT CAN SAY NO.**
/// Step for step it is the same algorithm — buffer, raw descriptor, codec,
/// first frame, dispose all three — which under this repo's connascence
/// rule makes the two COPIES, not lookalikes. The difference that matters
/// is that this one `await`s each step, so every failure the SDK drops
/// (see [decodeStraightRgbaImage]) arrives here as a rejection the caller
/// can act on. That is why the callers moved here in 2026-09-08 rather
/// than the other way round.
Future<ui.Image> uploadRawRgba(
  Uint8List rgba, {
  required int width,
  required int height,

  /// 🚨Behaviourally identical to `decodeImageFromPixels`'s pair of the
  /// same name. Its `allowUpscaling` is a DART-SIDE clamp that is never
  /// sent to the engine, and at its default (`true`) the clamp block is
  /// skipped entirely — both functions then hand the same two numbers to
  /// the same `instantiateCodec`, which owns the `<= 0 → null` handling and
  /// the intrinsic-size fallback. Moving a caller here changes no pixel and
  /// no size; it changes only what happens when the decode fails.
  int? targetWidth,
  int? targetHeight,
}) async {
  final override = _debugUploader;
  if (override != null) {
    return override(
      rgba,
      width: width,
      height: height,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    // 🚨A REJECTION LEAKED ALL THREE until 2026-09-08, and the leak is
    // bigger than it looks: the engine registers each wrapper's finalizer
    // with `sizeof(*this)` as the external-size hint, so the GC is told a
    // few dozen bytes while an `ImmutableBuffer` retains the whole copy —
    // 8.3 MB for one 1080p RGBA frame. In a per-frame failure that is
    // growth nothing reclaims until an unrelated collection happens by.
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

/// Stands in for the engine's ASYNCHRONOUS upload in tests.
///
/// 🚨Not a convenience — it is [debugSyncImageUploadOverride]'s argument word
/// for word, for the same reason: a refusal road that nothing exercises is
/// not a road. The one fixture that stages a genuine refusal without a
/// device — a descriptor that lies about its buffer's length — reaches
/// [uploadRawRgba] only where the CALLER's bytes can lie, and the two
/// hottest callers build their own: a `BitmapTile` validates its own pixel
/// length, and the stroke overlay allocates `width * height * 4` itself. On
/// every machine this project develops and CIs on, the engine simply never
/// refuses.
///
/// ⚠️IT DOES NOT REPLACE THE GENUINE-REFUSAL TESTS. That the ENGINE rejects
/// is pinned against the real path by the lying-descriptor fixture in
/// `straight_rgba_image_test.dart`; that each CALLER survives a rejection is
/// pinned through here. Neither can do the other's job, and a seam that
/// became the only reason anything ever failed would be measuring itself.
///
/// ⚠️It sits UNDER [decodeStraightRgbaImage], so a test that installs it
/// still runs the real premultiply and its native scratch — only the engine
/// handoff is stood in for. That is what keeps the scratch-release
/// assertions honest.
@visibleForTesting
set debugRawRgbaUploader(
  Future<ui.Image> Function(
    Uint8List rgba, {
    required int width,
    required int height,
    int? targetWidth,
    int? targetHeight,
  })?
  uploader,
) => _debugUploader = uploader;

@visibleForTesting
Future<ui.Image> Function(
  Uint8List rgba, {
  required int width,
  required int height,
  int? targetWidth,
  int? targetHeight,
})?
get debugRawRgbaUploader => _debugUploader;

Future<ui.Image> Function(
  Uint8List rgba, {
  required int width,
  required int height,
  int? targetWidth,
  int? targetHeight,
})?
_debugUploader;
