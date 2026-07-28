import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';
import 'package:anicel/src/ui/export/video_export_service.dart';

import '../../helpers/native_engine_path.dart';

/// The OS video encoder, driven for real (AUDIO-PRO R7). On this runner's
/// OS the export goes through the system codec stack and produces an
/// actual MP4 — the strongest claim a test can make short of watching it.
/// On a platform with no OS encoder (Linux CI) the capability answer is
/// pinned false and the ffmpeg fallback keeps the export alive.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final available = libraryPath != null;
  final skip = available ? false : nativeEngineMissingSkipReason;
  // The encoder paths exist on Windows and Apple today (Android is a
  // device-only story by nature).
  final osHasEncoder = Platform.isWindows || Platform.isMacOS;

  late Directory directory;

  setUp(() async {
    QaVideoEncoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    directory = await Directory.systemTemp.createTemp('qa-video-enc-test');
  });

  tearDown(() async {
    QaVideoEncoder.instance?.abort();
    QaVideoEncoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    await directory.delete(recursive: true);
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
    final ftyp = bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
    var moov = false;
    for (var index = 0; index + 4 <= bytes.length && !moov; index += 1) {
      moov = bytes[index] == 0x6D &&
          bytes[index + 1] == 0x6F &&
          bytes[index + 2] == 0x6F &&
          bytes[index + 3] == 0x76;
    }
    return ftyp && moov;
  }

  test('the capability answer matches the OS', () {
    final encoder = QaVideoEncoder.instance;
    expect(encoder, isNotNull, reason: 'the binary did not bind');
    expect(encoder!.isSupported, osHasEncoder,
        reason: 'Windows/Apple encode natively; elsewhere the ffmpeg '
            'fallback carries the export');
  }, skip: skip);

  test('a real MP4 comes out: video + AAC audio, finalized and playable-'
      'shaped', () {
    if (!osHasEncoder) {
      return;
    }
    final encoder = QaVideoEncoder.instance!;
    final path = '${directory.path}/out.mp4';
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
      expect(encoder.writeFrame(rgbaFrame(64, 48, frame)), isTrue,
          reason: 'frame $frame: ${encoder.lastError}');
      final pcm = Int16List(samplesPerFrame * 2);
      for (var index = 0; index < samplesPerFrame; index += 1) {
        final value = (8000 * (index % 100) / 100).round();
        pcm[index * 2] = value;
        pcm[index * 2 + 1] = -value;
      }
      expect(encoder.writeAudio(pcm, samplesPerFrame), isTrue,
          reason: 'audio $frame: ${encoder.lastError}');
    }
    expect(encoder.finish(), isTrue, reason: encoder.lastError);
    expect(looksLikeMp4(path), isTrue,
        reason: 'the file is not a finalized MP4');
    expect(File(path).lengthSync(), greaterThan(2000));
  }, skip: skip);

  test('an ODD canvas encodes — H.264 needs even, the pad supplies it', () {
    if (!osHasEncoder) {
      return;
    }
    final encoder = QaVideoEncoder.instance!;
    final path = '${directory.path}/odd.mp4';
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
      expect(encoder.writeFrame(rgbaFrame(63, 47, frame)), isTrue);
    }
    expect(encoder.finish(), isTrue, reason: encoder.lastError);
    expect(looksLikeMp4(path), isTrue);
  }, skip: skip);

  test('a second open while one is running refuses; abort cleans up', () {
    if (!osHasEncoder) {
      return;
    }
    final encoder = QaVideoEncoder.instance!;
    // 64x48, not smaller: the Microsoft H.264 encoder refuses tiny
    // resolutions (32x32 fails on a real machine) and that is the OS's
    // call, not this test's subject.
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
    encoder.abort();
    // After the abort a fresh export opens again.
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
    encoder.abort();
  }, skip: skip);

  test('the SERVICE takes the OS path end to end: rendered images and the '
      'mixed WAV land in one MP4', () async {
    if (!osHasEncoder) {
      return;
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    // The mixed master, as the export dialog writes it.
    final mixSamples = Float32List(48000);
    for (var index = 0; index < mixSamples.length; index += 1) {
      mixSamples[index] = 0.2;
    }
    final mixPath = '${directory.path}/mix.wav';
    File(mixPath).writeAsBytesSync(
      encodeConformWav(samples: mixSamples, channels: 2, sampleRate: 48000),
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
    final summary = await service.exportVideo(
      count: 12,
      renderImage: render,
      outputFilePath: outputPath,
      frameRate: const ProjectFrameRate.integer(24),
      audioMixPath: mixPath,
    );
    expect(summary.written, 12);
    expect(summary.processed, 12);
    expect(looksLikeMp4(outputPath), isTrue);
  }, skip: skip);
}
