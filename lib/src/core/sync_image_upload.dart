import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'rgba_premultiply.dart';

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

/// Premultiplied rgba rows held in a list, as the door reads them
/// ([pictureOf]).
final class PremultipliedRows implements PictureBytes {
  PremultipliedRows(this._premultiplied, this.width, this.height)
    : _given = false;

  /// Rows handed over for one read, no one else holding them: read
  /// straight, they are made straight where they lie, not copied first.
  ///
  /// 🔬A test's screen is drawn through the door as each frame of it is
  /// laid, from bytes it has just read back and lets go after: 2026-11-17,
  /// main PC, the top strip test's file straightened its screens in 110 s
  /// of its 386, and in 40 s once the copy before it went (board
  /// ci-heaviest-files-draw-on-the-cpu).
  PremultipliedRows.given(this._premultiplied, this.width, this.height)
    : _given = true;

  final Uint8List _premultiplied;
  final bool _given;

  @override
  final int width;

  @override
  final int height;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) => use(
    _given
        ? straightRgbaInPlace(_premultiplied)
        : straightRgbaFor(_premultiplied),
  );

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) =>
      use(_premultiplied);
}

/// Straight rgba rows held in a list, as the door reads them: a floating
/// text's picture, and what a GPU fx plugin drew.
final class StraightRgbaRows implements PictureBytes {
  StraightRgbaRows(this._straight, this.width, this.height);

  final Uint8List _straight;

  @override
  final int width;

  @override
  final int height;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) => use(_straight);

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) =>
      use(premultipliedRgbaCopy(_straight));
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
/// 🆕A committed tile's picture may leave by a second outlet of this door
/// (frame-composite-draws-each-tile-on-its-own, 2026-10-28): where the
/// engine writes pages, its premultiplied bytes — this same read, inside
/// the call — go into a slot of a page that holds many tiles (`TilePages`
/// in `ui/canvas/`), not a texture of their own. Still synchronous, still
/// waiting for nothing: the slot is drawn the moment it is handed out.
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

/// A test's answer to the probe — the test runner draws (Skia), so an
/// engine that uploads is one it is told it is; null asks the probe again.
@visibleForTesting
set debugPictureOfUploads(bool? uploads) => _uploadsPremultiplied = uploads;

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
///
/// A run is told a pixel at a time, its four bytes compared as one word
/// ([_wordsOf]). 🔬2026-11-17, main PC: a test's screen is drawn through
/// here as each frame of it is laid, and the top strip test's file spent
/// 48 s of its 386 in this loop a byte at a time, 42 s a word at a time
/// (board ci-heaviest-files-draw-on-the-cpu).
ui.Image _rasterizedStraight(Uint8List straight, int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()
    ..isAntiAlias = false
    ..style = ui.PaintingStyle.fill;
  final words = _wordsOf(straight, width * height);
  var at = 0;
  for (var y = 0; y < height; y += 1) {
    final rowStart = at;
    final rowEnd = at + width;
    while (at < rowEnd) {
      final word = words[at];
      final start = at;
      at += 1;
      while (at < rowEnd && words[at] == word) {
        at += 1;
      }
      final offset = start * 4;
      final a = straight[offset + 3];
      if (a == 0) {
        continue;
      }
      paint.color = ui.Color.fromARGB(
        a,
        straight[offset],
        straight[offset + 1],
        straight[offset + 2],
      );
      canvas.drawRect(
        ui.Rect.fromLTWH(
          (start - rowStart).toDouble(),
          y.toDouble(),
          (at - start).toDouble(),
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

/// [bytes]' first [count] pixels, a word each — over the same memory where
/// it lies on a word's bound, else over a copy.
Uint32List _wordsOf(Uint8List bytes, int count) =>
    bytes.offsetInBytes % 4 == 0
    ? bytes.buffer.asUint32List(bytes.offsetInBytes, count)
    : Uint8List.fromList(bytes).buffer.asUint32List(0, count);
