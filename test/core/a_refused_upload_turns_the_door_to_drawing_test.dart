import 'dart:typed_data';

import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:flutter_test/flutter_test.dart';

/// The door's refusal turns the run's door to drawing for good ([pictureOf]
/// — a lost context): an engine that said yes to the probe and no to a tile
/// stops being asked. The test runner refuses every upload (it is Skia), so
/// here it is told it uploads, and every upload is refused. ↩️A file's
/// picture laid whole past the wall was uploaded through its own door, whose
/// refusal turned nothing (F-374-Q8 ⑦), until no row was made now
/// (one-picture-per-frame ②-5b-1).
void main() {
  tearDown(() => debugPictureOfUploads = null);

  test('an upload refused turns the run\'s door to drawing', () {
    debugPictureOfUploads = true;

    pictureOf(_Bytes(8, 8)).dispose();

    expect(pictureOfUploads, isFalse);
  });
}

class _Bytes implements PictureBytes {
  _Bytes(this.width, this.height);

  @override
  final int width;

  @override
  final int height;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) =>
      use(Uint8List(width * height * 4));

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) =>
      use(Uint8List(width * height * 4));
}
