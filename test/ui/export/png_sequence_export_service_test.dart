import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/export/png_sequence_export_service.dart';
import '../../helpers/project_scratch_folder.dart';

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
    deleteAfterSessionEnds(directory);
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

  group('a file whose image is the one before, handed again', () {
    late ui.Image picture;
    late List<ui.Image> handed;
    late int encoded;

    setUp(() async {
      picture = await smallImage();
      handed = [];
      encoded = 0;
    });

    tearDown(() => picture.dispose());

    /// Frames 0 and 1 are [picture] handed twice; frame 2 another picture.
    Future<ui.Image?> render(int index) async {
      final image = index < 2 ? picture.clone() : await smallImage();
      handed.add(image);
      return image;
    }

    /// An encoder that writes [mark] and how many images it has encoded.
    ExportImageEncoder encoderMarked(int mark) => (image) async {
      encoded += 1;
      return [mark, encoded];
    };

    List<int> bytesOf(Directory directory, int index) => File(
      '${directory.path}${Platform.pathSeparator}img_$index.png',
    ).readAsBytesSync();

    test('🎯is the bytes before it — encoded once', () async {
      final directory = tempDirectory();
      final encode = encoderMarked(7);
      final before = PngSequenceExportService.debugEncodes;

      final summary = await service.exportImages(
        count: 3,
        renderImage: render,
        fileNameFor: (index) => 'img_$index.png',
        directoryPath: directory.path,
        encoderFor: (_) => encode,
      );

      expect(summary, (written: 3, processed: 3));
      expect(encoded, 2, reason: 'frame 1 is frame 0 again; 2 is not');
      expect(PngSequenceExportService.debugEncodes - before, 2);
      expect(bytesOf(directory, 1), bytesOf(directory, 0));
      expect(bytesOf(directory, 2), isNot(bytesOf(directory, 0)));
    });

    test('under another encoder is encoded again', () async {
      final directory = tempDirectory();
      final first = encoderMarked(7);
      final second = encoderMarked(9);

      await service.exportImages(
        count: 2,
        renderImage: render,
        fileNameFor: (index) => 'img_$index.png',
        directoryPath: directory.path,
        encoderFor: (index) => index == 0 ? first : second,
      );

      expect(encoded, 2);
      expect(bytesOf(directory, 1), [9, 2]);
    });

    test('is let go at once, and the one kept to know it by when the run '
        'ends', () async {
      await service.exportImages(
        count: 3,
        renderImage: render,
        fileNameFor: (index) => 'img_$index.png',
        directoryPath: tempDirectory().path,
      );

      expect(handed, hasLength(3), reason: 'LIVENESS: three handed');
      expect([for (final image in handed) image.debugDisposed], [
        true,
        true,
        true,
      ]);
    });

    test('a run whose encode fails lets go of what it kept', () async {
      await expectLater(
        service.exportImages(
          count: 3,
          renderImage: render,
          fileNameFor: (index) => 'img_$index.png',
          directoryPath: tempDirectory().path,
          encoderFor: (index) =>
              (image) async => throw StateError('no encoder'),
        ),
        throwsStateError,
      );

      expect(handed.single.debugDisposed, isTrue);
    });
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
