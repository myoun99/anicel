import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★THE ONE DOOR MAKES THE SAME BYTES ON EVERY ENGINE (shown ≡ result,
/// 2026-09-17). On Impeller [pictureOf] uploads the premultiplied bytes as
/// they are; on Skia — this harness — it DRAWS the straight bytes and lets
/// Skia premultiply. The two are one picture only if Skia's rounding is
/// the app's own, and this pins that over every alpha and a spread of
/// colours, run by run: a tile drawn here reads back byte for byte as the
/// bytes the upload road would have sent.
///
/// ⚠️`flutter_tester` answers the upload probe with NO (it is Skia), so the
/// draw road is what runs here — the `isFalse` below pins that this file
/// is exercising it, and not passing by uploading.
void main() {
  /// [width] × [height] straight rgba8888 with every alpha 0..255 along the
  /// rows, colours varied per pixel, and runs of equal pixels laid in so
  /// the run-length draw has both singletons and runs to get right.
  Uint8List straightSweep(int width, int height) {
    final straight = Uint8List(width * height * 4);
    var i = 0;
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        final run = (x ~/ 3) * 3; // every three pixels share a colour
        final alpha = (y * width + run) % 256;
        straight[i] = (run * 37 + y * 11) % 256;
        straight[i + 1] = (run * 91 + y * 5) % 256;
        straight[i + 2] = (run * 13 + y * 101) % 256;
        straight[i + 3] = alpha;
        i += 4;
      }
    }
    return straight;
  }

  Future<Uint8List> readBack(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  }

  test('this harness draws — the road under test', () {
    expect(pictureOfUploads, isFalse);
  });

  test('the drawn picture is the premultiplied bytes, byte for byte', () async {
    const width = 48;
    const height = 48; // 48 × 48 = 2304 pixels: every alpha nine times over
    final straight = straightSweep(width, height);
    final expected = premultipliedRgbaCopy(straight);
    final bytes = _Bytes(straight, width, height);
    final image = pictureOf(bytes);
    addTearDown(image.dispose);
    expect(image.width, width);
    expect(image.height, height);
    final actual = await readBack(image);
    expect(actual.length, expected.length);
    final wrong = <String>[];
    for (var i = 0; i < expected.length && wrong.length < 8; i += 4) {
      if (actual[i] != expected[i] ||
          actual[i + 1] != expected[i + 1] ||
          actual[i + 2] != expected[i + 2] ||
          actual[i + 3] != expected[i + 3]) {
        final pixel = i ~/ 4;
        wrong.add(
          '(${pixel % width},${pixel ~/ width}) straight '
          '${straight.sublist(i, i + 4)} → drawn ${actual.sublist(i, i + 4)} '
          'expected ${expected.sublist(i, i + 4)}',
        );
      }
    }
    expect(wrong, isEmpty, reason: 'the door rounds differently: $wrong');
    // The draw road read the straight bytes and only those.
    expect(bytes.straightReads, 1);
    expect(bytes.premultipliedReads, 0);
  });

  test('a picture is made per call — two calls, two images', () {
    final straight = straightSweep(8, 8);
    final first = pictureOf(_Bytes(straight, 8, 8));
    final second = pictureOf(_Bytes(straight, 8, 8));
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    expect(identical(first, second), isFalse);
  });
}

class _Bytes implements PictureBytes {
  _Bytes(this.straight, this.width, this.height);

  final Uint8List straight;
  @override
  final int width;
  @override
  final int height;

  int straightReads = 0;
  int premultipliedReads = 0;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) {
    straightReads += 1;
    return use(straight);
  }

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) {
    premultipliedReads += 1;
    return use(premultipliedRgbaCopy(straight));
  }
}
