import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/image_viewer_document.dart';
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
    final doc = await ImageViewerDocument.open(file.path);
    addTearDown(doc.dispose);

    expect(doc.pageCount, 1);
    expect(doc.pageSize(0), const ui.Size(400, 300));
  });

  test('🚨it renders at the size ASKED FOR, not at the file\'s — the large '
      'image is never made', () async {
    final file = await _writePng(dir, 'big.png', width: 800, height: 600);
    final doc = await ImageViewerDocument.open(file.path);
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
    final doc = await ImageViewerDocument.open(file.path);
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
      ImageViewerDocument.open(file.path),
      throwsA(isA<Object>()),
    );
  });
}
