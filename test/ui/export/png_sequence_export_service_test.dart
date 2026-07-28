import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/export/png_sequence_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = PngSequenceExportService();

  Future<ui.Image> smallImage() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 2, 2),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImage(2, 2);
    } finally {
      picture.dispose();
    }
  }

  Directory tempDirectory() {
    final directory = Directory.systemTemp.createTempSync('png_export_svc');
    addTearDown(() => directory.deleteSync(recursive: true));
    return directory;
  }

  List<String> fileNames(Directory directory) =>
      directory
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toList()
        ..sort();

  test('writes each rendered image and skips null renders', () async {
    final directory = tempDirectory();

    final summary = await service.exportImages(
      count: 3,
      renderImage: (index) async => index == 1 ? null : await smallImage(),
      fileNameFor: (index) => 'img_$index.png',
      directoryPath: directory.path,
      onProgress: (completed, total) {},
    );

    expect(summary, (written: 2, processed: 3));
    expect(fileNames(directory), ['img_0.png', 'img_2.png']);
    for (final file in directory.listSync().whereType<File>()) {
      expect(file.lengthSync(), greaterThan(0));
    }
  });

  test('cancellation stops before the next render', () async {
    final directory = tempDirectory();
    var rendered = 0;

    final summary = await service.exportImages(
      count: 5,
      renderImage: (index) async {
        rendered += 1;
        return smallImage();
      },
      fileNameFor: (index) => 'img_$index.png',
      directoryPath: directory.path,
      isCancelled: () => rendered >= 1,
    );

    expect(summary, (written: 1, processed: 1));
    expect(rendered, 1);
    expect(fileNames(directory), ['img_0.png']);
  });
}
