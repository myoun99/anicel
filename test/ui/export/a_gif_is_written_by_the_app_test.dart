import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';

import '../../helpers/project_scratch_folder.dart';

/// 🗣️I-152 (유저 2026-11-03): 「동영상 출력? 에 gif 추가 … 아무튼 형식으로
/// 새롭게 gif를 넣고싶음」.
///
/// A GIF is the app's own movie: no OS encoder and no ffmpeg is asked for
/// one, so every machine writes it — a picture a held drawing, shown as
/// long as it is held.
void main() {
  /// Every frame made here: a run lets go of each one it is handed.
  final made = <ui.Image>[];

  tearDown(() {
    expect(
      [
        for (final (index, image) in made.indexed)
          if (!image.debugDisposed) index,
      ],
      isEmpty,
      reason: 'frames still held when the run was over',
    );
    made.clear();
  });

  const red = ui.Color(0xFFE02010);
  const green = ui.Color(0xFF10C030);
  const blue = ui.Color(0xFF2040E0);

  /// A 4×2 frame, all of it [color].
  Future<ui.Image> frame(ui.Color color) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
    final image = await recorder.endRecording().toImage(4, 2);
    made.add(image);
    return image;
  }

  /// [image] handed again, as the renderer hands a held frame.
  ui.Image held(ui.Image image) {
    final again = image.clone();
    made.add(again);
    return again;
  }

  /// The service, failing the test if it asks ffmpeg or an OS encoder.
  final service = VideoExportService(
    processStarter: (executable, arguments) =>
        throw StateError('ffmpeg was started for a GIF'),
    encoderResolver: () => throw StateError('an OS encoder was asked'),
  );

  File outputIn(String name) {
    final folder = Directory.systemTemp.createTempSync('qa-gif');
    deleteAfterSessionEnds(folder);
    return File('${folder.path}${Platform.pathSeparator}$name');
  }

  /// The GIF at [file]: each picture's hundredths and colour.
  List<_Picture> picturesOf(File file) {
    final bytes = file.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(6)), 'GIF89a');
    final gif = img.decodeGif(bytes)!;
    return [
      for (final picture in gif.frames)
        (
          hundredths: picture.frameDuration ~/ 10,
          r: picture.getPixel(1, 1).r.toInt(),
          g: picture.getPixel(1, 1).g.toInt(),
          b: picture.getPixel(1, 1).b.toInt(),
          a: picture.getPixel(1, 1).a.toInt(),
        ),
    ];
  }

  /// A picture of about [color] — cut to a palette, so near it.
  Matcher about(ui.Color color) => isA<_Picture>()
      .having((p) => p.r, 'r', closeTo((color.r * 255).round(), 12))
      .having((p) => p.g, 'g', closeTo((color.g * 255).round(), 12))
      .having((p) => p.b, 'b', closeTo((color.b * 255).round(), 12));

  test('🚨every machine writes it: nothing but the app is asked — a GIF89a '
      'of the frames, each shown its frame\'s time as the GIF counts it, '
      'in hundredths that add up to the film\'s', () async {
    final file = outputIn('film.gif');
    final colors = [red, green, blue];
    final summary = await service.exportVideo(
      count: 3,
      renderImage: (index) => frame(colors[index]),
      outputFilePath: file.path,
      frameRate: const ProjectFrameRate.integer(12),
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
    );

    expect(summary, (written: 3, processed: 3));
    final pictures = picturesOf(file);
    expect([for (final p in pictures) p.hundredths], [8, 9, 8]);
    expect(pictures, [about(red), about(green), about(blue)]);
  });

  test('🚨a frame that is the picture before it goes in as no picture of its '
      'own: the picture is shown as long as it is held', () async {
    final file = outputIn('held.gif');
    final first = await frame(red);
    final last = await frame(blue);
    final frames = [first, held(first), held(first), last];
    final summary = await service.exportVideo(
      count: 4,
      renderImage: (index) async => frames[index],
      outputFilePath: file.path,
      frameRate: ProjectFrameRate.fps24,
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
    );

    expect(summary.written, 4, reason: 'every frame of the film is in it');
    final pictures = picturesOf(file);
    // 24 fps: the frames start at 0, 4.17, 8.33, 12.5 and end at 16.67.
    expect([for (final p in pictures) p.hundredths], [13, 4]);
    expect(pictures, [about(red), about(blue)]);
  });

  test('a picture held for less than a GIF can show is let go, and the next '
      'takes its time — the film keeps its length', () async {
    final file = outputIn('quick.gif');
    final colors = [red, green, blue];
    await service.exportVideo(
      count: 3,
      renderImage: (index) => frame(colors[index]),
      outputFilePath: file.path,
      frameRate: const ProjectFrameRate.integer(60),
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
    );

    final pictures = picturesOf(file);
    // 60 fps: the frames start at 0, 1.67, 3.33 and end at 5 — the green
    // one stands from 2 to 3, under the two hundredths a GIF shows.
    expect([for (final p in pictures) p.hundredths], [2, 3]);
    expect(pictures, [about(red), about(blue)]);
  });

  test('a GIF is opaque: a frame that leaves its ground clear is no '
      'transparent colour of it', () async {
    final file = outputIn('clear.gif');
    await service.exportVideo(
      count: 1,
      renderImage: (_) => frame(const ui.Color(0x00000000)),
      outputFilePath: file.path,
      frameRate: ProjectFrameRate.fps24,
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
    );

    expect(picturesOf(file).single.a, 255);
  });

  test('🚨cancelled mid-run, the GIF keeps the frames it got to', () async {
    final file = outputIn('stopped.gif');
    var rendered = 0;
    final colors = [red, green, blue];
    final summary = await service.exportVideo(
      count: 3,
      renderImage: (index) {
        rendered += 1;
        return frame(colors[index]);
      },
      outputFilePath: file.path,
      frameRate: const ProjectFrameRate.integer(12),
      container: ExportVideoContainer.gif,
      codec: ExportVideoCodec.gif,
      isCancelled: () => rendered >= 2,
    );

    expect(summary, (written: 2, processed: 2));
    expect([for (final p in picturesOf(file)) p.hundredths], [8, 9]);
  });

  test('every machine may pick it: no encoder and no ffmpeg stands between '
      'the window and a GIF', () {
    final availability = ExportFormatAvailability(
      encoderResolver: () => null,
      ffmpegCheck: () async => false,
      jpgSupported: true,
    );
    addTearDown(availability.dispose);
    expect(
      availability.videoAllowed(
        ExportVideoContainer.gif,
        ExportVideoCodec.gif,
      ),
      isTrue,
    );
    expect(
      availability.videoAllowed(
        ExportVideoContainer.mp4,
        ExportVideoCodec.h264,
      ),
      isFalse,
      reason: 'LIVENESS — a movie the machine writes, with nothing to write it',
    );
  });
}

/// One picture of a GIF: how long it is shown, and its colour.
typedef _Picture = ({int hundredths, int r, int g, int b, int a});
