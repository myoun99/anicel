import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_pcm_scale.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';

import '../../helpers/decode_audio_file.dart';
import '../../helpers/native_call_watch.dart';
import '../../helpers/os_video_codec.dart';
import '../../helpers/temp_dir.dart';
import '../../ui/export/fake_ffmpeg_process.dart';

/// The OS video encoder, driven for real (AUDIO-PRO R7). On this runner's
/// OS the export goes through the system codec stack and produces an
/// actual MP4 — the strongest claim a test can make short of watching it.
/// On a platform with no OS encoder (Linux CI) the capability answer is
/// pinned false and the ffmpeg fallback keeps the export alive.
void main() {
  late Directory directory;
  late NativeCallWatch watch;

  // Watched from before each test's first call into the engine to after
  // the last one, the abort below: every test here calls it, and this
  // file's first movie stood twelve minutes unwatched on 10-21 (the board
  // card's ninth sighting), its clock stopped inside the call.
  setUp(() async {
    watch = await NativeCallWatch.start('the OS video encoder');
    directory = await Directory.systemTemp.createTemp('qa-video-enc-test');
  });

  tearDown(() async {
    watch.step('letting the encoder go');
    QaVideoEncoder.instance.abort();
    watch.stop();
    deleteTempQuietly(directory);
  });

  /// A frame whose color moves with [frame] so the encode has real motion.
  Uint8List rgbaFrame(int width, int height, int frame) {
    final bytes = Uint8List(width * height * 4);
    for (var index = 0; index < width * height; index += 1) {
      bytes[index * 4] = (index + frame * 8) % 256;
      bytes[index * 4 + 1] = (index * 2) % 256;
      bytes[index * 4 + 2] = 255 - frame * 8 % 256;
      bytes[index * 4 + 3] = 255;
    }
    return bytes;
  }

  bool looksLikeMp4(String path) {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length < 500) {
      return false;
    }
    // ftyp right after the first box size, moov somewhere (finalized).
    final ftyp =
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
    var moov = false;
    for (var index = 0; index + 4 <= bytes.length && !moov; index += 1) {
      moov =
          bytes[index] == 0x6D &&
          bytes[index + 1] == 0x6F &&
          bytes[index + 2] == 0x6F &&
          bytes[index + 3] == 0x76;
    }
    return ftyp && moov;
  }

  /// One flat 64x48 picture, for the movies whose subject is not the picture.
  Future<ui.Image> flatPicture() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFF336699), ui.BlendMode.src);
    return recorder.endRecording().toImage(64, 48);
  }

  test('the capability answer matches the OS', () {
    watch.step('the capability: asking for the encoder');
    final encoder = QaVideoEncoder.instance;
    expect(
      encoder.isSupported,
      osHasVideoEncoder,
      reason:
          'Windows/Apple encode natively; elsewhere the ffmpeg '
          'fallback carries the export',
    );
  });

  test('a real MP4 comes out: video + AAC audio, finalized and playable-'
      'shaped', () {
    watch.step('a real MP4: asking for the encoder');
    final encoder = osVideoEncoderOrSkip();
    if (encoder == null) {
      return;
    }
    final path = '${directory.path}/out.mp4';
    watch.step('a real MP4: opening the writer');
    expect(
      encoder.open(
        path: path,
        width: 64,
        height: 48,
        fpsNumerator: 24,
        fpsDenominator: 1,
        sampleRate: 48000,
        channels: 2,
      ),
      isTrue,
      reason: encoder.lastError,
    );
    const samplesPerFrame = 48000 ~/ 24;
    for (var frame = 0; frame < 24; frame += 1) {
      watch.step('a real MP4: writing frame $frame');
      expect(
        encoder.writeFrame(rgbaFrame(64, 48, frame)),
        isTrue,
        reason: 'frame $frame: ${encoder.lastError}',
      );
      final pcm = Int16List(samplesPerFrame * 2);
      for (var index = 0; index < samplesPerFrame; index += 1) {
        final value = (8000 * (index % 100) / 100).round();
        pcm[index * 2] = value;
        pcm[index * 2 + 1] = -value;
      }
      watch.step('a real MP4: writing the sound of frame $frame');
      expect(
        encoder.writeAudio(pcm, samplesPerFrame),
        isTrue,
        reason: 'audio $frame: ${encoder.lastError}',
      );
    }
    watch.step('a real MP4: finishing the movie');
    expect(encoder.finish(), isTrue, reason: encoder.lastError);
    expect(
      looksLikeMp4(path),
      isTrue,
      reason: 'the file is not a finalized MP4',
    );
    expect(File(path).lengthSync(), greaterThan(2000));
  });

  test('an ODD canvas encodes — H.264 needs even, the pad supplies it', () {
    watch.step('an odd canvas: asking for the encoder');
    final encoder = osVideoEncoderOrSkip();
    if (encoder == null) {
      return;
    }
    final path = '${directory.path}/odd.mp4';
    watch.step('an odd canvas: opening the writer');
    expect(
      encoder.open(
        path: path,
        width: 63,
        height: 47,
        fpsNumerator: 24,
        fpsDenominator: 1,
      ),
      isTrue,
      reason: encoder.lastError,
    );
    for (var frame = 0; frame < 6; frame += 1) {
      watch.step('an odd canvas: writing frame $frame');
      expect(encoder.writeFrame(rgbaFrame(63, 47, frame)), isTrue);
    }
    watch.step('an odd canvas: finishing the movie');
    expect(encoder.finish(), isTrue, reason: encoder.lastError);
    expect(looksLikeMp4(path), isTrue);
  });

  test('a second open while one is running refuses; abort cleans up', () {
    watch.step('a second open: asking for the encoder');
    final encoder = osVideoEncoderOrSkip();
    if (encoder == null) {
      return;
    }
    // 64x48, not smaller: the Microsoft H.264 encoder refuses tiny
    // resolutions (32x32 fails on a real machine) and that is the OS's
    // call, not this test's subject.
    watch.step('a second open: opening the first writer');
    expect(
      encoder.open(
        path: '${directory.path}/one.mp4',
        width: 64,
        height: 48,
        fpsNumerator: 24,
        fpsDenominator: 1,
      ),
      isTrue,
      reason: encoder.lastError,
    );
    watch.step('a second open: opening a second while it runs');
    expect(
      encoder.open(
        path: '${directory.path}/two.mp4',
        width: 64,
        height: 48,
        fpsNumerator: 24,
        fpsDenominator: 1,
      ),
      isFalse,
      reason: 'one export at a time, like the capture device',
    );
    watch.step('a second open: aborting the first');
    encoder.abort();
    // After the abort a fresh export opens again.
    watch.step('a second open: opening again after the abort');
    expect(
      encoder.open(
        path: '${directory.path}/three.mp4',
        width: 64,
        height: 48,
        fpsNumerator: 24,
        fpsDenominator: 1,
      ),
      isTrue,
      reason: encoder.lastError,
    );
    watch.step('a second open: aborting the third');
    encoder.abort();
  });

  test('the SERVICE takes the OS path end to end: rendered images and the '
      'mixed WAV land in one MP4', () async {
    if (osVideoEncoderOrSkip() == null) {
      return;
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    // The mixed master, as the export dialog writes it — a WAV
    // (`writeExportAudioMixWav`). 🪦It was written here with the conform
    // encoder, which is exactly what the service's reader wanted and the
    // dialog never wrote: from 08-30 every movie the OS encoder made from
    // the dialog's mix had no sound, and this stayed green (09-25). A tone,
    // so the AAC that comes back is not a DC offset its encoder may drop.
    final mixSamples = Float32List(48000);
    for (var index = 0; index < mixSamples.length; index += 1) {
      mixSamples[index] =
          0.2 * math.sin(2 * math.pi * 440 * (index ~/ 2) / 48000);
    }
    final mixPath = '${directory.path}/mix.wav';
    File(mixPath).writeAsBytesSync(
      wav16Bytes(int16PcmOf(mixSamples), sampleRate: 48000, channels: 2),
    );

    Future<ui.Image?> render(int index) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 64, 48),
        ui.Paint()..color = ui.Color.fromARGB(255, index * 10, 128, 200),
      );
      return recorder.endRecording().toImage(64, 48);
    }

    final service = VideoExportService(
      encoderResolver: () => QaVideoEncoder.instance,
    );
    final outputPath = '${directory.path}/service.mp4';
    watch.step('the service: exporting the movie');
    final summary = await service.exportVideo(
      count: 12,
      renderImage: render,
      outputFilePath: outputPath,
      frameRate: ProjectFrameRate.fps24,
      audioMixPath: mixPath,
    );
    expect(summary.written, 12);
    expect(summary.processed, 12);
    expect(looksLikeMp4(outputPath), isTrue);
    watch.step('the service: reading its sound back');
    final sound = decodeAudioFile(outputPath);
    expect(sound, isNotNull, reason: 'the movie went out without its sound');
    expect(
      sound!.samples.any((sample) => sample.abs() > 0.1),
      isTrue,
      reason: 'the mix\'s tone, not silence',
    );
  });

  test('🚨a movie\'s sound is led by what the caller says sounded before it — '
      'its first samples come back closer than behind silence', () async {
    final encoder = osVideoEncoderOrSkip();
    if (encoder == null) {
      return;
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    // 🗣️유저 2026-11-10 (board an-mp4-reopened-loses-its-first-9-ms-of-
    // sound-Q2): 「무음, 범위 앞에 소리가 있으면 그 소리」. A tone that was
    // already sounding and is on its peak where the movie begins: behind
    // silence that is the hardest first sample there is, behind its own
    // past an ordinary one.
    const rate = 48000;
    int toneAt(int sample) =>
        (12000 * math.cos(2 * math.pi * 750 * sample / rate)).round();
    Int16List toneFrom(int first, int count) {
      final pcm = Int16List(count * 2);
      for (var index = 0; index < count; index += 1) {
        pcm[index * 2] = pcm[index * 2 + 1] = toneAt(first + index);
      }
      return pcm;
    }

    final mixPath = '${directory.path}/mix.wav';
    File(mixPath).writeAsBytesSync(
      wav16Bytes(toneFrom(0, rate ~/ 2), sampleRate: rate, channels: 2),
    );
    final service = VideoExportService(
      encoderResolver: () => QaVideoEncoder.instance,
    );

    /// How far the first 128 samples of the movie written as [name] came
    /// back from the tone's.
    Future<double> headErrorOf(String name, SoundBefore? soundBefore) async {
      final outputPath = '${directory.path}/$name.mp4';
      watch.step('a led movie: exporting $name');
      final summary = await service.exportVideo(
        count: 12,
        renderImage: (_) => flatPicture(),
        outputFilePath: outputPath,
        frameRate: ProjectFrameRate.fps24,
        audioMixPath: mixPath,
        soundBefore: soundBefore,
      );
      expect(summary, (written: 12, processed: 12));
      watch.step('a led movie: reading the sound of $name back');
      final sound = decodeAudioFile(outputPath)!;
      var squares = 0.0;
      for (var index = 0; index < 128; index += 1) {
        final error =
            sound.samples[index * sound.channels] - toneAt(index) / 32768;
        squares += error * error;
      }
      return math.sqrt(squares / 128);
    }

    final asked = <int>[];
    final led = await headErrorOf('led', (samples) async {
      asked.add(samples);
      return toneFrom(-samples, samples);
    });
    expect(
      asked,
      encoder.audioLead == 0 ? isEmpty : [encoder.audioLead],
      reason: 'asked once, for exactly the frame the writer puts there',
    );
    if (encoder.audioLead == 0) {
      // A writer that leads a movie's sound itself is handed nothing, so
      // there are no two movies to tell apart.
      return;
    }
    final unled = await headErrorOf('unled', null);
    expect(
      led,
      lessThan(unled / 2),
      reason: '🔬2026-11-10, this tone through Media Foundation\'s AAC: '
          '0.0009 behind its own past, 0.0045 behind silence',
    );
  });


  test('🚨a job the OS refuses goes to ffmpeg with the frame the movie was '
      'sized by — no frame is rendered twice', () async {
    // Media Foundation writes no MOV; AVAssetWriter does, and takes the job.
    if (!Platform.isWindows) {
      return;
    }
    final ffmpeg = FakeFfmpegProcess();
    final rendered = <int>[];
    Future<ui.Image?> render(int index) {
      rendered.add(index);
      return flatPicture();
    }

    final service = VideoExportService(
      encoderResolver: () => QaVideoEncoder.instance,
      processStarter: (executable, arguments) async => ffmpeg,
    );
    watch.step('a refused job: exporting the movie');
    final summary = await service.exportVideo(
      count: 3,
      renderImage: render,
      outputFilePath: '${directory.path}/refused.mov',
      frameRate: ProjectFrameRate.fps24,
      container: ExportVideoContainer.mov,
    );

    expect(rendered, [0, 1, 2]);
    expect(summary, (written: 3, processed: 3));
    expect(ffmpeg.receivedFrameCount, 3);
    expect(ffmpeg.collectedStdin.length, 3 * 64 * 48 * 4);
  });

  test('🚨the OS encoder is handed a held frame again without its being '
      'read back — twelve frames of one picture are one readback', () async {
    if (osVideoEncoderOrSkip() == null) {
      return;
    }
    final held = await flatPicture();
    addTearDown(held.dispose);
    final service = VideoExportService(
      encoderResolver: () => QaVideoEncoder.instance,
    );
    final outputPath = '${directory.path}/held.mp4';
    final readBefore = VideoExportService.debugReadbacks;
    final handed = <ui.Image>[];

    watch.step('a held frame: exporting the movie');
    final summary = await service.exportVideo(
      count: 12,
      renderImage: (_) async {
        final again = held.clone();
        handed.add(again);
        return again;
      },
      outputFilePath: outputPath,
      frameRate: ProjectFrameRate.fps24,
    );

    expect(summary, (written: 12, processed: 12));
    expect(VideoExportService.debugReadbacks - readBefore, 1);
    expect(looksLikeMp4(outputPath), isTrue);
    expect(
      handed.every((image) => image.debugDisposed),
      isTrue,
      reason: 'each picture handed is let go of — the one kept to tell the '
          'next by, when the movie is finished',
    );
  });
}
