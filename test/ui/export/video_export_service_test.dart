import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';

import 'fake_ffmpeg_process.dart';

/// The frame walk and the ffmpeg pipe — the service with no OS encoder
/// (a test never binds one): the first frame that renders sizes the movie,
/// ffmpeg is started for a movie that size, and every frame goes down the
/// pipe as its own raw bytes.
void main() {
  /// Every frame made here: a run lets go of each one it is handed,
  /// however it ends.
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

  /// A [width]×[height] frame, all of it [color].
  Future<ui.Image?> frame({
    int width = 4,
    int height = 2,
    ui.Color color = const ui.Color(0xFF204060),
  }) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
    final image = await recorder.endRecording().toImage(width, height);
    made.add(image);
    return image;
  }

  Future<ui.Image?> noImage(int index) => Future<ui.Image?>.value();

  /// The service over [process], writing down what ffmpeg was started with.
  ({VideoExportService service, List<List<String>> started}) over(
    FakeFfmpegProcess process,
  ) {
    final started = <List<String>>[];
    return (
      service: VideoExportService(
        processStarter: (executable, arguments) async {
          started.add([executable, ...arguments]);
          return process;
        },
      ),
      started: started,
    );
  }

  test('ffmpeg is told the rate, the size of the frames and where the movie '
      'goes — and takes every frame', () async {
    final process = FakeFfmpegProcess();
    final (:service, :started) = over(process);

    final summary = await service.exportVideo(
      count: 3,
      renderImage: (_) => frame(),
      outputFilePath: 'C:/out/take.mp4',
      frameRate: const ProjectFrameRate.integer(12),
    );

    final [executable, ...arguments] = started.single;
    expect(executable, 'ffmpeg');
    expect(
      arguments,
      containsAllInOrder(['-video_size', '4x2', '-framerate', '12', '-i', '-']),
    );
    expect(arguments.last, 'C:/out/take.mp4');
    expect(summary, (written: 3, processed: 3));
    expect(process.receivedFrameCount, 3);
    expect(process.collectedStdin.length, 3 * 4 * 2 * 4);
    expect(process.killed, isFalse);
  });

  test('🚨a frame goes down the pipe as its own pixels — RGBA with the '
      'alpha STRAIGHT, as the pipe is told they are', () async {
    final process = FakeFfmpegProcess();
    final (:service, started: _) = over(process);

    await service.exportVideo(
      count: 1,
      // Half clear: premultiplied it is (128, 0, 0, 128).
      renderImage: (_) => frame(color: const ui.Color(0x80FF0000)),
      outputFilePath: 'out.mov',
      frameRate: ProjectFrameRate.fps24,
    );

    expect(process.collectedStdin.toBytes(), [
      for (var pixel = 0; pixel < 4 * 2; pixel += 1) ...[255, 0, 0, 128],
    ]);
  });

  test('the frames that render nothing before the first that does are '
      'walked, and the movie is the size of that first one', () async {
    final process = FakeFfmpegProcess();
    final (:service, :started) = over(process);
    final progress = <int>[];

    final summary = await service.exportVideo(
      count: 4,
      renderImage: (index) => index < 2 ? noImage(index) : frame(width: 6),
      outputFilePath: 'out.mp4',
      frameRate: ProjectFrameRate.fps24,
      onProgress: (completed, _) => progress.add(completed),
    );

    expect(started.single, containsAllInOrder(['-video_size', '6x2']));
    expect(summary, (written: 2, processed: 4));
    expect(progress, [1, 2, 3, 4]);
  });

  test('a run that renders nothing starts no encoder and says so', () async {
    final (:service, :started) = over(FakeFfmpegProcess());

    await expectLater(
      service.exportVideo(
        count: 3,
        renderImage: noImage,
        outputFilePath: 'out.mp4',
        frameRate: ProjectFrameRate.fps24,
      ),
      throwsA(
        isA<VideoExportException>().having(
          (error) => error.message,
          'message',
          contains('nothing rendered'),
        ),
      ),
    );
    expect(started, isEmpty);
  });

  test('a run of no frames is no run', () async {
    final (:service, :started) = over(FakeFfmpegProcess());
    var rendered = 0;

    final summary = await service.exportVideo(
      count: 0,
      renderImage: (_) {
        rendered += 1;
        return frame();
      },
      outputFilePath: 'out.mp4',
      frameRate: ProjectFrameRate.fps24,
    );

    expect(summary, (written: 0, processed: 0));
    expect(rendered, 0);
    expect(started, isEmpty);
  });

  group('buildFfmpegArguments', () {
    test('without audio the command is the video alone: raw RGBA frames of '
        'the size it is told, off the pipe', () {
      final args = VideoExportService.buildFfmpegArguments(
        frameRate: ProjectFrameRate.fps24,
        outputFilePath: 'out.mp4',
        width: 1920,
        height: 1080,
      );

      expect(
        args,
        containsAllInOrder([
          '-f',
          'rawvideo',
          '-pixel_format',
          'rgba',
          '-video_size',
          '1920x1080',
          '-framerate',
          '24',
          '-i',
          '-',
        ]),
      );
      expect(args, isNot(contains('image2pipe')));
      expect(args, contains('-vf'));
      expect(args, isNot(contains('-filter_complex')));
      expect(args, isNot(contains('-shortest')));
      expect(args.last, 'out.mp4');
    });

    test('with a finished mix WAV, ffmpeg only encodes: one audio input, '
        'no filter graph, aac out (EXPORT-AUDIO — our mixer already did '
        'the mixing)', () {
      final args = VideoExportService.buildFfmpegArguments(
        frameRate: ProjectFrameRate.fps24,
        outputFilePath: 'out.mp4',
        width: 1920,
        height: 1080,
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
        renderImage: (_) => frame(),
        outputFilePath: 'out.mp4',
        frameRate: ProjectFrameRate.fps24,
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
    final (:service, started: _) = over(process);

    await expectLater(
      service.exportVideo(
        count: 1,
        renderImage: (_) => frame(),
        outputFilePath: 'out.mp4',
        frameRate: ProjectFrameRate.fps24,
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

  test('🚨a pipe that breaks mid-run is a failed run, in ffmpeg\'s own '
      'words — the frames after it are never rendered', () async {
    final process = FakeFfmpegProcess(
      exitCodeValue: 1,
      stderrText: 'Error writing trailer\n',
      breaksAtFrame: 2,
    );
    final (:service, started: _) = over(process);
    var rendered = 0;

    await expectLater(
      service.exportVideo(
        count: 5,
        renderImage: (_) {
          rendered += 1;
          return frame();
        },
        outputFilePath: 'out.mp4',
        frameRate: ProjectFrameRate.fps24,
      ),
      throwsA(
        isA<VideoExportException>().having(
          (error) => error.message,
          'message',
          allOf(contains('ffmpeg failed (exit 1)'), contains('trailer')),
        ),
      ),
    );
    expect(rendered, 2);
    expect(process.receivedFrameCount, 1);
  });

  test('🚨a frame of another size ends the run before it reaches the pipe: '
      'raw, it would be read at the movie\'s size', () async {
    final process = FakeFfmpegProcess();
    final (:service, started: _) = over(process);

    await expectLater(
      service.exportVideo(
        count: 3,
        renderImage: (index) => frame(width: index == 1 ? 2 : 4),
        outputFilePath: 'out.mp4',
        frameRate: ProjectFrameRate.fps24,
      ),
      throwsA(
        isA<VideoExportException>().having(
          (error) => error.message,
          'message',
          contains('frame 2 is 2x2 in a movie of 4x2'),
        ),
      ),
    );
    expect(process.collectedStdin.length, 4 * 2 * 4);
  });

  test('cancelling before any frame starts no encoder', () async {
    final (:service, :started) = over(FakeFfmpegProcess());

    final summary = await service.exportVideo(
      count: 5,
      renderImage: (_) => frame(),
      outputFilePath: 'out.mp4',
      frameRate: ProjectFrameRate.fps24,
      isCancelled: () => true,
    );

    expect(started, isEmpty);
    expect(summary, (written: 0, processed: 0));
  });

  test('cancelling while nothing has rendered yet starts no encoder, and '
      'reports how far the walk got', () async {
    final (:service, :started) = over(FakeFfmpegProcess());
    var rendered = 0;

    final summary = await service.exportVideo(
      count: 5,
      renderImage: (index) {
        rendered += 1;
        return noImage(index);
      },
      outputFilePath: 'out.mp4',
      frameRate: ProjectFrameRate.fps24,
      isCancelled: () => rendered >= 2,
    );

    expect(summary, (written: 0, processed: 2));
    expect(started, isEmpty);
  });

  test('🚨cancelling mid-run keeps the movie as far as it got: the pipe is '
      'closed for ffmpeg to finish it, and what ffmpeg says of a short '
      'movie is not the run\'s failure', () async {
    // Exit 1: ffmpeg's own word on a stream cut short.
    final process = FakeFfmpegProcess(exitCodeValue: 1);
    final (:service, started: _) = over(process);
    var rendered = 0;

    final summary = await service.exportVideo(
      count: 5,
      renderImage: (_) {
        rendered += 1;
        return frame();
      },
      outputFilePath: 'out.mp4',
      frameRate: ProjectFrameRate.fps24,
      isCancelled: () => rendered >= 2,
    );

    expect(summary, (written: 2, processed: 2));
    expect(process.receivedFrameCount, 2);
    expect(process.killed, isFalse);
  });

  test('🚨a frame that is the frame before it — the SAME image, handed again '
      '— is not read back: it goes down the pipe as the bytes read then', () async {
    final process = FakeFfmpegProcess();
    final (:service, started: _) = over(process);
    final held = (await frame())!;
    addTearDown(held.dispose);
    final other = (await frame(color: const ui.Color(0xFF000000)))!;
    final readBefore = VideoExportService.debugReadbacks;

    final summary = await service.exportVideo(
      count: 4,
      // 0 and 1 are one picture, 2 is another, 3 is the first again — each
      // handed as a picture of the run's own to let go of.
      renderImage: (index) async {
        if (index == 2) {
          return other;
        }
        final again = held.clone();
        made.add(again);
        return again;
      },
      outputFilePath: 'out.mp4',
      frameRate: ProjectFrameRate.fps24,
    );

    expect(summary, (written: 4, processed: 4));
    expect(process.receivedFrameCount, 4);
    expect(
      VideoExportService.debugReadbacks - readBefore,
      3,
      reason: 'frame 1 is frame 0 and is not read; frame 3 follows another '
          'picture, and is',
    );
    final bytes = process.collectedStdin.toBytes();
    const size = 4 * 2 * 4;
    final first = bytes.sublist(0, size);
    expect(bytes.sublist(size, 2 * size), first);
    expect(bytes.sublist(2 * size, 3 * size), isNot(first));
    expect(bytes.sublist(3 * size), first);
  });
}
