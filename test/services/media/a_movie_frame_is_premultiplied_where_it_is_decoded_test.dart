import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/rgba_premultiply.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/services/import/cel_picture.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/media/video_viewer_document.dart';
import 'package:anicel/src/services/straight_rgba_image.dart';

import '../../helpers/fake_video_backend.dart';

/// 🚨A movie frame shown is premultiplied WHERE IT IS DECODED, not on the
/// isolate that paints it (viewer-frame-premultiply-on-the-worker).
/// 🔬2026-11-07: premultiplying a 1080p frame took 13–17 ms on the UI
/// isolate, C or Dart, a frame of the viewer's play — a third of 24fps.
///
/// What is pinned: the worker's frame arm hands the form asked, by the
/// app's one law, through the buffer it keeps; the viewer and the picture
/// a movie row or a bake makes ask for that form and upload it as it comes;
/// a picture past the engine's side keeps the straight frame.
void main() {
  const width = 4;
  const height = 2;

  /// Straight RGBA with every alpha a different partial one, so a
  /// premultiply shows in every pixel and a second one would too.
  Uint8List straight(int seed) => Uint8List.fromList([
    for (var pixel = 0; pixel < width * height; pixel += 1) ...[
      (seed + pixel * 31) % 256,
      (seed * 7 + pixel * 13) % 256,
      200,
      20 + pixel * 29,
    ],
  ]);

  group('the worker\'s frame arm', () {
    test('hands a frame premultiplied by the app\'s one law', () {
      final frame = straight(5);
      expect(
        transferOfFrame(frame, premultiplied: true).materialize().asUint8List(),
        premultipliedRgbaCopy(frame),
      );
      expect(frame, straight(5), reason: 'the decoder\'s scratch is read');
    });

    test('hands a frame straight as it is', () {
      expect(
        transferOfFrame(straight(9), premultiplied: false)
            .materialize()
            .asUint8List(),
        straight(9),
      );
    });

    test('a frame made in the kept buffer is its own, and the one before '
        'stays its own', () {
      final first = transferOfFrame(straight(1), premultiplied: true);
      final second = transferOfFrame(straight(2), premultiplied: true);
      expect(
        second.materialize().asUint8List(),
        premultipliedRgbaCopy(straight(2)),
      );
      expect(
        first.materialize().asUint8List(),
        premultipliedRgbaCopy(straight(1)),
        reason: 'the transfer copied the first out before the second came',
      );
    });
  });

  group('what shows a frame asks for it premultiplied', () {
    late _Asked backend;
    late List<Uint8List> uploaded;
    final previousSide = debugPictureSideLimit;

    setUp(() {
      backend = _Asked(straight(3));
      uploaded = [];
      debugVideoDecodeBackend = backend;
      debugRawRgbaUploader =
          (rgba, {required width, required height, targetWidth, targetHeight}) {
            uploaded.add(Uint8List.fromList(rgba));
            return Future<ui.Image>.error(const _Uploaded());
          };
    });

    tearDown(() {
      debugVideoDecodeBackend = null;
      debugRawRgbaUploader = null;
      debugPictureSideLimit = previousSide;
    });

    test('the viewer uploads the frame as its decoder\'s side '
        'premultiplied it', () async {
      final document = await VideoViewerDocument.open(
        const MediaFileBytes('C:/work/clip.mp4'),
      );
      await expectLater(
        document!.renderPage(2, width: width, height: height),
        throwsA(isA<_Uploaded>()),
      );
      expect(backend.forms, ['premultiplied 2']);
      expect(uploaded, [premultipliedRgbaCopy(straight(3))]);
    });

    test('a movie row\'s or a bake\'s picture of a frame does too', () async {
      debugPictureSideLimit = 16;
      await expectLater(
        pictureOfMovieFrame(backend, 1, 2, backend.info),
        throwsA(isA<_Uploaded>()),
      );
      expect(backend.forms, ['premultiplied 2']);
      expect(uploaded, [premultipliedRgbaCopy(straight(3))]);
    });

    test('past the engine\'s side the picture keeps the straight '
        'frame', () async {
      debugPictureSideLimit = width - 1;
      final picture = await pictureOfMovieFrame(backend, 1, 2, backend.info);
      expect(backend.forms, ['straight 2']);
      expect(picture, isA<PixelsPicture>());
      expect(await picture!.straightRgba(), straight(3));
      expect(uploaded, isEmpty);
    });
  });
}

final class _Uploaded implements Exception {
  const _Uploaded();
}

/// A movie of one painted frame that records which FORM was asked for.
final class _Asked extends FakeVideoBackend {
  _Asked(this.painted) : super(width: 4, height: 2, paint: (_) => painted);

  final Uint8List painted;

  final List<String> forms = [];

  QaVideoInfo get info => QaVideoInfo(
    width: width,
    height: height,
    frameCount: frameCount,
    fpsNumerator: fpsNumerator,
    fpsDenominator: fpsDenominator,
  );

  @override
  Future<Uint8List?> frame(int token, int index) async {
    forms.add('straight $index');
    return Uint8List.fromList(painted);
  }

  @override
  Future<Uint8List?> premultipliedFrame(int token, int index) async {
    forms.add('premultiplied $index');
    return premultipliedRgbaCopy(painted);
  }
}
