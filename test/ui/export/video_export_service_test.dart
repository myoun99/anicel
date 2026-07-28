import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';

import 'fake_ffmpeg_process.dart';

void main() {
  // Frames render as null throughout: these tests cover the process
  // plumbing; real image piping is covered by the export dialog tests.
  Future<ui.Image?> noImage(int index) => Future<ui.Image?>.value();

  test('passes fps and the output path to ffmpeg', () async {
    final process = FakeFfmpegProcess();
    String? capturedExecutable;
    List<String>? capturedArguments;
    final service = VideoExportService(
      processStarter: (executable, arguments) async {
        capturedExecutable = executable;
        capturedArguments = arguments;
        return process;
      },
    );

    final summary = await service.exportVideo(
      count: 3,
      renderImage: noImage,
      outputFilePath: 'C:/out/take.mp4',
      frameRate: const ProjectFrameRate.integer(12),
    );

    expect(capturedExecutable, 'ffmpeg');
    final arguments = capturedArguments!;
    final framerateIndex = arguments.indexOf('-framerate');
    expect(framerateIndex, isNot(-1));
    expect(arguments[framerateIndex + 1], '12');
    expect(arguments.last, 'C:/out/take.mp4');
    expect(summary, (written: 0, processed: 3));
  });

  group('buildFfmpegArguments', () {
    test('without audio the command is the original video-only shape', () {
      final args = VideoExportService.buildFfmpegArguments(
        frameRate: const ProjectFrameRate.integer(24),
        outputFilePath: 'out.mp4',
      );

      expect(args, containsAllInOrder(['-f', 'image2pipe', '-i', '-']));
      expect(args, contains('-vf'));
      expect(args, isNot(contains('-filter_complex')));
      expect(args, isNot(contains('-shortest')));
      expect(args.last, 'out.mp4');
    });

    test('with a finished mix WAV, ffmpeg only encodes: one audio input, '
        'no filter graph, aac out (EXPORT-AUDIO — our mixer already did '
        'the mixing)', () {
      final args = VideoExportService.buildFfmpegArguments(
        frameRate: const ProjectFrameRate.integer(24),
        outputFilePath: 'out.mp4',
        audioMixPath: 'C:/tmp/mix.wav',
      );

      expect(args, containsAllInOrder(['-i', '-', '-i', 'C:/tmp/mix.wav']));
      expect(args, isNot(contains('-filter_complex')));
      expect(args, isNot(contains('-ss')));
      expect(args, isNot(contains('adelay')));
      expect(args, contains('-vf'));
      expect(args, containsAllInOrder(['-map', '0:v', '-map', '1:a']));
      expect(args, containsAllInOrder(['-c:a', 'aac', '-shortest']));
      expect(args.last, 'out.mp4');
    });
  });

  test('missing ffmpeg surfaces an install hint', () async {
    final service = VideoExportService(
      processStarter: (executable, arguments) =>
          throw ProcessException(executable, arguments),
    );

    await expectLater(
      service.exportVideo(
        count: 1,
        renderImage: noImage,
        outputFilePath: 'out.mp4',
        frameRate: const ProjectFrameRate.integer(24),
      ),
      throwsA(
        isA<VideoExportException>().having(
          (error) => error.message,
          'message',
          contains('ffmpeg not found'),
        ),
      ),
    );
  });

  test('a non-zero ffmpeg exit surfaces the stderr tail', () async {
    final process = FakeFfmpegProcess(
      exitCodeValue: 1,
      stderrText: 'Unknown encoder libx264\n',
    );
    final service = VideoExportService(
      processStarter: (executable, arguments) async => process,
    );

    await expectLater(
      service.exportVideo(
        count: 1,
        renderImage: noImage,
        outputFilePath: 'out.mp4',
        frameRate: const ProjectFrameRate.integer(24),
      ),
      throwsA(
        isA<VideoExportException>().having(
          (error) => error.message,
          'message',
          contains('Unknown encoder libx264'),
        ),
      ),
    );
  });

  test('cancelling before any frame kills ffmpeg without an error', () async {
    final process = FakeFfmpegProcess(exitCodeValue: 1);
    final service = VideoExportService(
      processStarter: (executable, arguments) async => process,
    );

    final summary = await service.exportVideo(
      count: 5,
      renderImage: noImage,
      outputFilePath: 'out.mp4',
      frameRate: const ProjectFrameRate.integer(24),
      isCancelled: () => true,
    );

    expect(process.killed, isTrue);
    expect(summary, (written: 0, processed: 0));
  });

  test('cancelling mid-run reports the processed frame count', () async {
    final process = FakeFfmpegProcess();
    final service = VideoExportService(
      processStarter: (executable, arguments) async => process,
    );
    var rendered = 0;

    final summary = await service.exportVideo(
      count: 5,
      renderImage: (index) {
        rendered += 1;
        return noImage(index);
      },
      outputFilePath: 'out.mp4',
      frameRate: const ProjectFrameRate.integer(24),
      isCancelled: () => rendered >= 2,
    );

    // No frame bytes ever reached ffmpeg (null renders), so the cancel
    // takes the kill path rather than finalizing a partial video.
    expect(summary.processed, 2);
    expect(process.killed, isTrue);
  });
}
