import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuShown;
import 'package:anicel/src/ui/export/png_sequence_export_service.dart';

import '../../helpers/a_film_frame_on_the_engine.dart';
import '../../helpers/png_chunks.dart';
import '../../helpers/project_scratch_folder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = PngSequenceExportService();

  Future<GpuShown> smallFrame() =>
      filmFrameIn(const ui.Color(0xFF000000), width: 2, height: 2);

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

  test('writes each rendered frame and skips null renders', () async {
    final directory = tempDirectory();

    final summary = await service.exportImages(
      count: 3,
      renderImage: (index) async => index == 1 ? null : await smallFrame(),
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

  // Red half covered is red at half its alpha in a file that keeps its
  // colour straight: not the darker red the engine keeps it as.
  test('🎯the default is a PNG of four channels, its colour straight, and '
      'the sRGB stamp', () async {
    final directory = tempDirectory();
    await service.exportImages(
      count: 1,
      renderImage: (_) => filmFrameIn(const ui.Color(0x80FF0000)),
      fileNameFor: (_) => 'half.png',
      directoryPath: directory.path,
    );

    final png = File(
      '${directory.path}${Platform.pathSeparator}half.png',
    ).readAsBytesSync();
    expect(pngColourTypeOf(png), 6, reason: 'RGBA');
    expect(
      [for (final chunk in pngChunksOf(png)) chunk.type],
      ['IHDR', 'sRGB', 'gAMA', 'cHRM', 'IDAT', 'IEND'],
      reason: 'C1-v1: every PNG handed out says its colours are sRGB',
    );
    final codec = await ui.instantiateImageCodec(png);
    final picture = (await codec.getNextFrame()).image;
    final straight = await picture.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    picture.dispose();
    codec.dispose();
    expect(Uint8List.sublistView(straight!, 0, 4), [255, 0, 0, 128]);
  });

  group('a file whose frame is the one before, handed again', () {
    late GpuShown held;
    late int encoded;

    setUp(() async {
      held = await smallFrame();
      encoded = 0;
    });

    /// Frames 0 and 1 are [held] handed twice; frame 2 another frame.
    Future<GpuShown?> render(int index) async =>
        index < 2 ? held : await smallFrame();

    /// An encoder that writes [mark] and how many frames it has encoded.
    ExportImageEncoder encoderMarked(int mark) => (frame) async {
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

    test('a run whose encode fails says so', () async {
      await expectLater(
        service.exportImages(
          count: 3,
          renderImage: render,
          fileNameFor: (index) => 'img_$index.png',
          directoryPath: tempDirectory().path,
          encoderFor: (index) =>
              (frame) async => throw StateError('no encoder'),
        ),
        throwsStateError,
      );
    });
  });

  test('cancellation stops before the next render', () async {
    final directory = tempDirectory();
    var rendered = 0;

    final summary = await service.exportImages(
      count: 5,
      renderImage: (index) async {
        rendered += 1;
        return smallFrame();
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
