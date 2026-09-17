import 'dart:typed_data';
import 'dart:ui' as ui;

/// One rgba8888 image's worth of bytes that can become a picture, readable
/// STRAIGHT or PREMULTIPLIED. The door ([pictureOf]) reads the form THIS
/// engine takes and only that one, so a source makes each form on demand —
/// a fused native premultiply where the engine is loaded, the resident
/// straight result as it stands — and releases what it staged when [use]
/// returns.
abstract interface class PictureBytes {
  int get width;
  int get height;

  /// Straight-alpha rgba8888 rows, valid only inside [use].
  T readStraight<T>(T Function(Uint8List straight) use);

  /// Premultiplied rgba8888 rows — Skia's mul-div-255 rounding, the app's
  /// own `premultiplyRgbaInPlace` — valid only inside [use].
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use);
}

/// 🚨★★★THE ONE DOOR FROM BYTES TO A PICTURE — synchronous on every engine
/// (유저 절대규칙 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」).
///
/// A tile that has bytes and no picture gets its picture HERE, inside the
/// call, from its own bytes. Nothing waits a decode round any more, so
/// nothing has to stand in for the picture meanwhile: not the previous
/// tile at the coordinate, not a composition from the predecessor, not a
/// per-pixel frame, not a blank one. The whole stale-tile family was made
/// of waiting, and this is the door that ends the wait.
///
/// Two engines, one answer:
///  - IMPELLER (every platform we ship, Flutter 3.47.4): the premultiplied
///    bytes go up as they are through `ui.decodeImageFromPixelsSync`,
///    30-49 us for a 256 px tile. The pixels cross as a `Handle` and a
///    native call cannot hold a Dart handle past its own return, so the
///    bytes are consumed inside the call and the caller may release its
///    staging the moment [PictureBytes.readPremultiplied] returns. What
///    that argument does NOT exclude is the GPU upload finishing later —
///    the SDK says the image "might not be fully decoded yet" — and that
///    is fine, because by then the engine is working from its own copy.
///  - SKIA (the test runner, `flutter_tester` — the only Skia left): the
///    STRAIGHT bytes are drawn, a run of equal pixels at a time, into a
///    picture that `toImageSync` rasterizes now. Skia premultiplies the
///    paint colour with the same mul-div-255 rounding the app's own
///    premultiply uses (parity-pinned since R19), so the two doors make the
///    same bytes — `the_door_makes_the_same_picture_on_every_engine_test`.
///    ⛔Not from the premultiplied bytes: a paint colour is straight, and
///    un-premultiplying is lossy. That is why the interface reads either
///    form rather than taking one list.
///
/// Availability is a runtime probe (one 1×1 upload), not a platform check:
/// the question is what THIS engine can do, and an Impeller engine that
/// answers no mid-run (a lost context) takes the picture road for the
/// rest of the run rather than throw on a paint path.
///
/// It lives in `core/` so the runtime-path report can name it without
/// `services/` reaching up into `ui/`.
ui.Image pictureOf(PictureBytes bytes) {
  final width = bytes.width;
  final height = bytes.height;
  if (pictureOfUploads) {
    final uploaded = bytes.readPremultiplied(
      (premultiplied) => _uploadOrNull(premultiplied, width, height),
    );
    if (uploaded != null) {
      return uploaded;
    }
  }
  return bytes.readStraight(
    (straight) => _rasterizedStraight(straight, width, height),
  );
}

/// Whether [pictureOf] UPLOADS on this engine (Impeller) or DRAWS (Skia).
/// The parity test's oracle; the door itself is the same call either way.
bool get pictureOfUploads => _uploadsPremultiplied ??= _probe();

bool? _uploadsPremultiplied;

ui.Image? _uploadOrNull(Uint8List premultiplied, int width, int height) {
  try {
    return ui.decodeImageFromPixelsSync(
      premultiplied,
      width,
      height,
      ui.PixelFormat.rgba8888,
    );
  } on Object catch (_) {
    // The probe said yes and this said no. Stop asking rather than throw
    // on every coordinate of every paint.
    _uploadsPremultiplied = false;
    return null;
  }
}

/// ONE 1×1 upload decides it for the run.
bool _probe() {
  try {
    ui.decodeImageFromPixelsSync(
      Uint8List(4),
      1,
      1,
      ui.PixelFormat.rgba8888,
    ).dispose();
    return true;
  } on Object catch (_) {
    // A bare String on Skia — not an Exception, so this is deliberately
    // unqualified.
    return false;
  }
}

/// [straight] drawn a run of equal pixels at a time and rasterized now.
/// Fully transparent runs are left undrawn (a fresh picture is transparent
/// already); every other run is one non-antialiased rect in the run's
/// straight colour, which Skia premultiplies exactly once.
ui.Image _rasterizedStraight(Uint8List straight, int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..isAntiAlias = false
    ..style = ui.PaintingStyle.fill;
  var offset = 0;
  for (var y = 0; y < height; y += 1) {
    var x = 0;
    while (x < width) {
      final a = straight[offset + 3];
      if (a == 0) {
        x += 1;
        offset += 4;
        continue;
      }
      final r = straight[offset];
      final g = straight[offset + 1];
      final b = straight[offset + 2];
      final start = x;
      x += 1;
      offset += 4;
      while (x < width &&
          straight[offset] == r &&
          straight[offset + 1] == g &&
          straight[offset + 2] == b &&
          straight[offset + 3] == a) {
        x += 1;
        offset += 4;
      }
      paint.color = ui.Color.fromARGB(a, r, g, b);
      canvas.drawRect(
        ui.Rect.fromLTWH(
          start.toDouble(),
          y.toDouble(),
          (x - start).toDouble(),
          1,
        ),
        paint,
      );
    }
  }
  final picture = recorder.endRecording();
  try {
    return picture.toImageSync(width, height);
  } finally {
    picture.dispose();
  }
}
