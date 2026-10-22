import 'dart:typed_data';

import 'package:anicel/src/core/sync_image_upload.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-374-Q8 ⑦: a file's picture laid whole is uploaded as ONE picture
/// ([wholePictureUploadedOrNull]), and its refusal is its own. The door's
/// refusal turns the run's door to drawing for good ([pictureOf] — a lost
/// context) — and a scan drawn a run of pixels at a time, every tile after
/// it, is no road at all. The test runner refuses every upload (it is
/// Skia), so here it is told it uploads, and every upload is refused.
void main() {
  tearDown(() => debugPictureOfUploads = null);

  test('a whole picture refused leaves the run\'s door as it was — the '
      'door\'s own refusal turns it', () {
    debugPictureOfUploads = true;

    expect(wholePictureUploadedOrNull(_Bytes(8, 8)), isNull);
    expect(pictureOfUploads, isTrue);

    pictureOf(_Bytes(8, 8)).dispose();
    expect(pictureOfUploads, isFalse, reason: 'premise: the door\'s turns');
  });

  test('where the engine draws, a whole picture is not drawn either', () {
    debugPictureOfUploads = false;
    var read = false;

    expect(wholePictureUploadedOrNull(_Bytes(8, 8, read: () => read = true)),
        isNull);
    expect(read, isFalse, reason: 'its bytes are not read for nothing');
  });
}

class _Bytes implements PictureBytes {
  _Bytes(this.width, this.height, {this.read});

  @override
  final int width;

  @override
  final int height;

  final void Function()? read;

  @override
  T readStraight<T>(T Function(Uint8List straight) use) {
    read?.call();
    return use(Uint8List(width * height * 4));
  }

  @override
  T readPremultiplied<T>(T Function(Uint8List premultiplied) use) {
    read?.call();
    return use(Uint8List(width * height * 4));
  }
}
