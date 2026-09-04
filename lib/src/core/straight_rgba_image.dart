import 'dart:typed_data';
import 'dart:ui' as ui;

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
/// normal route. The scratch is freed on every path, inside the decode
/// callback.
///
/// [onDecoded] always receives the image, mounted or not — disposing it is
/// the caller's business, because only the caller knows whether the result
/// is still wanted.
///
/// ⚠️There is no synchronous route to a `ui.Image` on Skia (see
/// `syncImageUploadSupported`), which is why this is a callback and why
/// every caller needs an answer for the frames before it fires.
void decodeStraightRgbaImage({
  required Uint8List rgba,
  required int width,
  required int height,
  required void Function(ui.Image image) onDecoded,

  /// The pixels to PRODUCE, when that is smaller than the buffer's own
  /// size. 🚨★★★「보이는 것만, 보이는 해상도로」 — a video frame arrives
  /// from the OS decoder at the movie's size (there is no smaller ask in
  /// the native API), but the picture the viewer KEEPS should be the size
  /// it draws. Passing these makes the big one transient instead of
  /// resident. Null means "the buffer's own size", which is every caller
  /// that came before.
  int? targetWidth,
  int? targetHeight,
}) {
  final premultipliedCopy = premultipliedStraightRgba(rgba);
  final premultiplied = premultipliedCopy.pixels;
  final scratch = premultipliedCopy.scratch;
  ui.decodeImageFromPixels(
    premultiplied,
    width,
    height,
    ui.PixelFormat.rgba8888,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    (image) {
      scratch?.free();
      onDecoded(image);
    },
  );
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
Future<ui.Image> uploadRawRgba(
  Uint8List rgba, {
  required int width,
  required int height,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: width,
    height: height,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  return frame.image;
}
