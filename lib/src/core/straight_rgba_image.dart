import 'dart:typed_data';
import 'dart:ui' as ui;

import '../native/qa_native_engine.dart';

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
}) {
  final native = QaNativeEngine.instance;
  final Uint8List premultiplied;
  QaStampScratch? scratch;
  if (native != null) {
    scratch = native.premultipliedStampCopy(rgba);
    premultiplied = scratch.view;
  } else {
    premultiplied = Uint8List.fromList(rgba);
    for (var i = 0; i < premultiplied.length; i += 4) {
      final alpha = premultiplied[i + 3];
      if (alpha == 255) {
        continue;
      }
      premultiplied[i] = (premultiplied[i] * alpha + 127) ~/ 255;
      premultiplied[i + 1] = (premultiplied[i + 1] * alpha + 127) ~/ 255;
      premultiplied[i + 2] = (premultiplied[i + 2] * alpha + 127) ~/ 255;
    }
  }
  ui.decodeImageFromPixels(
    premultiplied,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (image) {
      scratch?.free();
      onDecoded(image);
    },
  );
}
