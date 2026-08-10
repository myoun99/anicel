import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// The engine's SYNCHRONOUS bytes-to-image upload, where there is one.
///
/// `ui.decodeImageFromPixelsSync` is IMPELLER ONLY. On Skia it throws a
/// bare `String`, so availability is a runtime probe rather than a
/// platform check — and Windows runs Skia in every build, debug included,
/// so on the machine this is written on the answer is always no.
///
/// Why it matters enough to have its own module: it is the only way to
/// give a tile that has BYTES and no picture a picture within the frame.
/// Composing one from pictures already on the GPU covers a lot, but every
/// operand has to already be an image, and the cases that remain — a
/// transform confirm whose resample has not landed, a lift's first frame,
/// a coordinate nothing ever decoded — have no such operand. Without this
/// they wait a decode round, and waiting is what the whole stale-tile
/// family is made of.
///
/// It lives in `core/` so the runtime-path report can name it without
/// `services/` reaching up into `ui/`.
bool get syncImageUploadSupported => _supported ??= _probe();

bool? _supported;

/// Uploads [pixels] (premultiplied rgba8888) as an image, or returns null
/// where the engine cannot. NEVER throws: a caller on a paint path has no
/// useful response to an unimplemented engine call.
///
/// ⚠️ Callers may pass a window onto NATIVE memory and release it the
/// moment this returns, which is only safe because the engine cannot read
/// the list afterwards: `_decodeImageFromPixelsSync` takes the pixels as a
/// `Handle`, and a native call has no way to hold a Dart handle past its
/// own return, so the bytes must be consumed inside it. What that argument
/// does NOT exclude is the GPU upload finishing later — the SDK says the
/// image "might not be fully decoded yet" — and that is fine, because by
/// then the engine is working from its own copy, not ours. If this is ever
/// wrong the symptom is an access violation, not a wrong picture.
ui.Image? uploadImageSync(Uint8List pixels, int width, int height) {
  if (!syncImageUploadSupported) {
    return null;
  }
  try {
    return _upload(pixels, width, height);
  } catch (_) {
    // The probe said yes and this said no. Stop asking rather than throw
    // on every undrawable coordinate of every paint.
    _supported = false;
    return null;
  }
}

/// ONE 1×1 upload decides it for the run.
bool _probe() {
  try {
    _upload(Uint8List(4), 1, 1)?.dispose();
    return true;
  } catch (_) {
    // A bare String on Skia — not an Exception, so this is deliberately
    // unqualified.
    return false;
  }
}

ui.Image? _upload(Uint8List pixels, int width, int height) {
  final override = _debugOverride;
  if (override != null) {
    return override(pixels, width, height);
  }
  return ui.decodeImageFromPixelsSync(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
  );
}

/// Stands in for the engine's synchronous upload in tests.
///
/// 🚨 Not a convenience. Every developer machine on this project runs
/// Skia in every build, and so does CI, so without an injection point the
/// entire synchronous-upload path would be exercised by nothing but its
/// own null return — a test that skips itself on the only machine that
/// runs it is not a test.
///
/// Setting it re-opens the probe, so the availability answer is always
/// about the uploader that is actually installed.
@visibleForTesting
set debugSyncImageUploadOverride(
  ui.Image? Function(Uint8List pixels, int width, int height)? uploader,
) {
  _debugOverride = uploader;
  _supported = null;
}

@visibleForTesting
ui.Image? Function(Uint8List pixels, int width, int height)?
get debugSyncImageUploadOverride => _debugOverride;

ui.Image? Function(Uint8List pixels, int width, int height)? _debugOverride;
