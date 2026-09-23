import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/image_viewer_document.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/media/video_viewer_document.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/project_scratch_folder.dart';

/// I-14: a cut reads a BOX of a page at the page's own size
/// (`ViewerDocument.readRegionRgba`). These pin the real documents' reads:
/// the image's — a whole decode, then the box — and the movie's, straight
/// out of the frame's bytes. ⚠️The PDF's is PDFium's own region render,
/// which flutter_tester cannot load; that one is checked on a device.
void main() {
  /// Page pixel (x, y) of the test pictures: red x·10, green y·10.
  List<int> pixelAt(int x, int y) => [x * 10, y * 10, 77, 255];

  Uint8List painted(int width, int height) {
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        rgba.setAll((y * width + x) * 4, pixelAt(x, y));
      }
    }
    return rgba;
  }

  List<int> box(int left, int top, int width, int height) => [
    for (var y = top; y < top + height; y += 1)
      for (var x = left; x < left + width; x += 1) ...pixelAt(x, y),
  ];

  testWidgets('an image reads the box byte for byte, at its own size', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('anicel-region-read');
    deleteAfterSessionEnds(dir);
    final read = await tester.runAsync(() async {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        painted(16, 12),
        16,
        12,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${dir.path}/page.png')
        ..writeAsBytesSync(png!.buffer.asUint8List());
      final document = await ImageViewerDocument.open(file.path);
      try {
        return await document.readRegionRgba(
          0,
          (left: 3, top: 2, width: 5, height: 4),
        );
      } finally {
        await document.dispose();
      }
    });
    expect(read, box(3, 2, 5, 4));
  });

  test('a movie reads the box straight out of the frame\'s bytes', () async {
    final backend = FakeVideoBackend(
      width: 16,
      height: 12,
      paint: (_) => painted(16, 12),
    );
    debugVideoDecodeBackend = backend;
    addTearDown(() => debugVideoDecodeBackend = null);
    final document = (await VideoViewerDocument.open('reference.mp4'))!;
    final read = await document.readRegionRgba(
      3,
      (left: 3, top: 2, width: 5, height: 4),
    );
    await document.dispose();
    expect(read, box(3, 2, 5, 4));
    expect(backend.asked, [3], reason: 'the frame the page names');
  });
}
