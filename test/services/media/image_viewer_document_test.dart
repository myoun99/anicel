import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/image_viewer_document.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/viewer_document.dart';
import '../../helpers/psd_fixture.dart';
import '../../helpers/temp_dir.dart';

/// The answer to 유저 2026-08-29「한장짜리면 결국 그대로 올라가는건
/// 어쩔수없는거지?」 — no. A still image is a one-page document that
/// renders at the size it is asked for, and asking is the whole point.

Future<File> _writePng(
  Directory dir,
  String name, {
  required int width,
  required int height,
}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final image = recorder.endRecording().toImageSync(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${dir.path}/$name')
    ..writeAsBytesSync(data!.buffer.asUint8List());
  return file;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('image-doc-test'));
  tearDown(() => deleteTempQuietly(dir));

  test('a still image is a ONE-page document that knows its own size', () async {
    final file = await _writePng(dir, 'a.png', width: 400, height: 300);
    final doc = await ImageViewerDocument.open(MediaFileBytes(file.path));
    addTearDown(doc.dispose);

    expect(doc.pageCount, 1);
    expect(doc.pageSize(0), const ui.Size(400, 300));
  });

  test('🚨it renders at the size ASKED FOR, not at the file\'s — the large '
      'image is never made', () async {
    final file = await _writePng(dir, 'big.png', width: 800, height: 600);
    final doc = await ImageViewerDocument.open(MediaFileBytes(file.path));
    addTearDown(doc.dispose);

    final small = await doc.renderPage(0, width: 200, height: 150);
    addTearDown(small.dispose);
    expect(small.width, 200);
    expect(small.height, 150);
    // ⛔The point is NOT that it can be scaled down afterwards — a decode
    // at 800×600 would still have existed. The document reports the
    // original size while never producing it.
    expect(doc.pageSize(0), const ui.Size(800, 600));
  });

  test('the same page can be asked again SHARPER — that is what keeps the '
      'encoded file open', () async {
    final file = await _writePng(dir, 'z.png', width: 640, height: 480);
    final doc = await ImageViewerDocument.open(MediaFileBytes(file.path));
    addTearDown(doc.dispose);

    final coarse = await doc.renderPage(0, width: 80, height: 60);
    expect(coarse.width, 80);
    coarse.dispose();
    final fine = await doc.renderPage(0, width: 640, height: 480);
    expect(fine.width, 640);
    fine.dispose();
  });

  test('a file that is not an image fails to OPEN rather than rendering '
      'something wrong', () async {
    final file = File('${dir.path}/not-an-image.png')
      ..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
    await expectLater(
      ImageViewerDocument.open(MediaFileBytes(file.path)),
      throwsA(isA<Object>()),
    );
  });

  group('🚨a Photoshop document opens as its COMPOSITE — no codec reads '
      'one, so it is asked for first', () {
    /// An 8×6 document whose composite says where each pixel is: red
    /// counts across, green down.
    Uint8List layout() => buildPsd(
      width: 8,
      height: 6,
      compositePlanes: [
        Uint8List.fromList([
          for (var y = 0; y < 6; y += 1)
            for (var x = 0; x < 8; x += 1) x * 30,
        ]),
        Uint8List.fromList([
          for (var y = 0; y < 6; y += 1)
            for (var x = 0; x < 8; x += 1) y * 40,
        ]),
        Uint8List(48)..fillRange(0, 48, 7),
      ],
    );

    List<int> at(int x, int y) => [x * 30, y * 40, 7, 255];

    Future<void> expectTheComposite(ViewerDocument doc) async {
      expect(doc.pageCount, 1);
      expect(doc.pageSize(0), const ui.Size(8, 6));
      final small = await doc.renderPage(0, width: 4, height: 2);
      addTearDown(small.dispose);
      expect(
        (small.width, small.height),
        (4, 2),
        reason: 'EXACTLY the size asked, a squashed ask included',
      );
      final whole = await doc.renderPage(0, width: 8, height: 6);
      addTearDown(whole.dispose);
      final pixels = (await whole.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();
      expect(pixels.sublist((2 * 8 + 3) * 4, (2 * 8 + 4) * 4), at(3, 2));
      // The cut tool's read, at the page's own size.
      expect(
        await doc.readRegionRgba(0, (left: 1, top: 2, width: 3, height: 2)),
        [
          for (var y = 2; y < 4; y += 1)
            for (var x = 1; x < 4; x += 1) ...at(x, y),
        ],
      );
    }

    test('from a file of its own', () async {
      final file = File('${dir.path}/layout.psd')
        ..writeAsBytesSync(layout());
      final doc = await ImageViewerDocument.open(MediaFileBytes(file.path));
      addTearDown(doc.dispose);

      await expectTheComposite(doc);
    });

    test('and from bytes the project carries', () async {
      final bytes = layout();
      final archive = File('${dir.path}/project.anicel')
        ..writeAsBytesSync([0, 0, 0, ...bytes]);
      final doc = await ImageViewerDocument.open(
        MediaArchiveBytes(
          archivePath: archive.path,
          dataOffset: 3,
          length: bytes.length,
        ),
      );
      addTearDown(doc.dispose);

      await expectTheComposite(doc);
    });

    test('and a document saved without one says so', () async {
      final file = File('${dir.path}/no-composite.psd')
        ..writeAsBytesSync(buildPsd(width: 8, height: 6));
      await expectLater(
        ImageViewerDocument.open(MediaFileBytes(file.path)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('without a composite image'),
          ),
        ),
      );
    });
  });
}
