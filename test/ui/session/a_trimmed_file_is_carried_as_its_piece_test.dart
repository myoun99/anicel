import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/movie_clock.dart';
import 'package:anicel/src/native/qa_audio_decoder.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/import/media_import_planner.dart'
    show ImportDestination;
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/native_engine_path.dart';

/// 🗣️유저 2026-09-11: 「자를때 원본 전체만 안들어가고 자른것만 안으로
/// 들어가도록」 — answered 2026-09-23: Q1 「잘라낸 동영상으로 다시 인코딩」,
/// Q2 「조각을 가리킨다 — 원본 경로는 출처로만 남긴다」, and 「비디오든
/// 이미지든 오디오든 관계없이 법 하나로」.
///
/// One law, every kind: the kept span becomes a PIECE of its own, the pool
/// names the piece, and the original is only where it came from. What
/// differs by kind is how it is cut — and each pin here asks the piece for
/// exactly what was kept, no more and no less.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-pieces');
  });

  tearDown(() async {
    PdfRenderService.debugResetForTests();
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly; leftovers live in systemTemp.
    }
  });

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  String inTemp(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  /// Three frames, one pixel each, black · white · black.
  Future<String> writeGif(String name) async {
    // [lzw] is the pixel's LZW code: 0x44 for palette 0, 0x4C for 1.
    List<int> frame(int lzw) => [
      0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, // graphic control
      0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, // image
      0x02, 0x02, lzw, 0x01, 0x00, // its one pixel
    ];
    final path = inTemp(name);
    await File(path).writeAsBytes([
      ...'GIF89a'.codeUnits,
      0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, // 1×1, two colours
      0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
      ...frame(0x44), ...frame(0x4C), ...frame(0x44),
      0x3B,
    ]);
    return path;
  }

  /// The first pixel of every frame [png] holds, and how long each shows.
  Future<List<(int, Duration)>> framesOf(Uint8List png) async {
    final codec = await ui.instantiateImageCodec(png);
    final frames = <(int, Duration)>[];
    for (var i = 0; i < codec.frameCount; i += 1) {
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      frames.add((data!.getUint8(0), frame.duration));
      frame.image.dispose();
    }
    codec.dispose();
    return frames;
  }

  testWidgets('🎯a trimmed GIF is carried as an APNG of only the frames it '
      'keeps — the pool names the piece, the original only where it came '
      'from', (tester) async {
    final s = session();
    final gif = await tester.runAsync(() => writeGif('walk.gif'));

    final cut = await tester.runAsync(
      () => s.trimmedPieces.cut(gif!, MediaAssetKind.image, inFrame: 1),
    );

    expect(cut?.frames, 2, reason: 'the second and third frames');
    final piece = cut!.path;
    expect(mediaFileName(piece), 'walk_2-3.png');
    expect(
      piece.startsWith(s.mediaStagingStore.directoryPath),
      isTrue,
      reason: 'its address is in the room only this app writes to',
    );
    final frames = await tester.runAsync(
      () => framesOf(File(piece).readAsBytesSync()),
    );
    expect(
      frames,
      [(0xFF, const Duration(milliseconds: 100)), (0x00, const Duration(milliseconds: 100))],
      reason: 'white then black — the second and third, and nothing else',
    );

    await tester.runAsync(() async {
      final landed = await s.importDoors.importImageFile(
        path: piece,
        destination: ImportDestination.activeCutLayer,
        copyIntoProject: true,
        sourcePath: gif,
      );
      expect(landed, isTrue);
      await s.trimmedPieces.secure(piece);
    });

    final project = s.repository.requireProject();
    final asset = project.mediaAssetByPath(normalizedMediaPath(piece))!;
    expect(asset.carried, isTrue);
    expect(asset.sourcePath, gif, reason: 'Q2: 원본 경로는 출처로만');
    expect(
      project.mediaAssetByPath(normalizedMediaPath(gif!)),
      isNull,
      reason: 'the original is not what the project carries',
    );
    expect(
      File(piece).existsSync(),
      isFalse,
      reason: 'the file the door read is gone — the staged copy is the only '
          'one (「사본 남으면 진짜 용서안할게」)',
    );
    expect(s.mediaStagingStore.find(piece), isNotNull);
    await tester.pumpAndSettle();
  });

  testWidgets('🎯a trimmed PDF is carried as a PDF of the kept pages, cut by '
      'the renderer from the original', (tester) async {
    final pdf = FakePdfDocument(pageSizes: List.filled(5, const ui.Size(8, 8)));
    PdfRenderService.debugOpenerOverride = (path) async => pdf;
    final asked = <(String, int, int)>[];
    PdfRenderService.debugPageSpanOverride = (path, first, count) async {
      asked.add((path, first, count));
      return Uint8List.fromList('%PDF-kept'.codeUnits);
    };
    final s = session();
    final source = inTemp('conte.pdf');
    await tester.runAsync(() => File(source).writeAsBytes(const [0x25, 0x50]));

    final cut = await tester.runAsync(
      () => s.trimmedPieces.cut(
        source,
        MediaAssetKind.pdf,
        inFrame: 1,
        outFrame: 3,
      ),
    );

    expect(asked, [(source, 1, 3)], reason: 'pages 2 to 4, from the original');
    expect(cut?.frames, 3);
    final piece = cut!.path;
    expect(mediaFileName(piece), 'conte_2-4.pdf');
    expect(File(piece).readAsStringSync(), '%PDF-kept');
    await tester.pumpAndSettle();
  });

  testWidgets('🚨a piece whose import did not land leaves nothing behind',
      (tester) async {
    final s = session();
    final gif = await tester.runAsync(() => writeGif('walk.gif'));
    final piece = (await tester.runAsync(
      () => s.trimmedPieces.cut(gif!, MediaAssetKind.image, outFrame: 0),
    ))!.path;

    s.trimmedPieces.discard(piece);

    expect(File(piece).existsSync(), isFalse);
    expect(s.mediaStagingStore.find(piece), isNull);
    await tester.pumpAndSettle();
  });

  group('with the engine', () {
    final libraryPath = nativeEngineLibraryPathOrNull();
    // `testWidgets` takes a bool, not a reason — the reason is
    // [nativeEngineMissingSkipReason].
    final skip = libraryPath == null;

    /// A stereo ramp, one sample a step, [seconds] long at 48kHz.
    String writeWav(String name, int seconds) {
      const rate = 48000;
      final samples = Int16List(rate * seconds * 2);
      for (var i = 0; i < samples.length; i += 1) {
        samples[i] = (i % 60000) - 30000;
      }
      final data = samples.buffer.asUint8List();
      final path = inTemp(name);
      File(path).writeAsBytesSync([
        ...wav16HeaderBytes(dataBytes: data.length, sampleRate: rate, channels: 2),
        ...data,
      ]);
      return path;
    }

    testWidgets('🎯a trimmed sound is carried as a WAV of exactly the '
        'samples its frames play', (tester) async {
      final s = session();
      final source = writeWav('line.wav', 2);
      final rate = s.projectSettings.projectFrameRate;

      final cut = await tester.runAsync(
        () => s.trimmedPieces.cut(
          source,
          MediaAssetKind.audio,
          inFrame: 6,
          outFrame: 17,
        ),
      );

      expect(cut?.frames, 12);
      final piece = cut!.path;
      expect(mediaFileName(piece), 'line_7-18.wav');
      final kept = QaAudioDecoder.instance!.decode(File(piece).readAsBytesSync())!;
      final all = QaAudioDecoder.instance!.decode(File(source).readAsBytesSync())!;
      int sampleAt(int frame) =>
          frame * rate.denominator * 48000 ~/ rate.numerator;
      final from = sampleAt(6) * 2;
      final to = sampleAt(18) * 2;
      expect(kept.sampleRate, 48000);
      expect(kept.channels, 2);
      expect(kept.samples.length, to - from, reason: 'frames 7..18, no more');
      expect(kept.samples.first, all.samples[from]);
      expect(kept.samples.last, all.samples[to - 1]);
      await tester.pumpAndSettle();
    }, skip: skip);

    testWidgets('🎯a trimmed movie is carried as an MP4 of the frames the '
        'project shows, one per project frame', (tester) async {
      final encoder = QaVideoEncoder.instance;
      if (encoder == null || !encoder.isSupported) {
        return;
      }
      final s = session();
      final rate = s.projectSettings.projectFrameRate;
      // Eight movie frames at 12fps, each its own flat red, over a sound —
      // the size and sound the other encoder fixtures use (the OS encoder
      // turns tiny frames away).
      final source = inTemp('take3.mp4');
      expect(
        encoder.open(
          path: source,
          width: 64,
          height: 48,
          fpsNumerator: 12,
          fpsDenominator: 1,
          sampleRate: 44100,
          channels: 2,
        ),
        isTrue,
        reason: encoder.lastError,
      );
      const samplesPerFrame = 44100 ~/ 12;
      for (var frame = 0; frame < 8; frame += 1) {
        final rgba = Uint8List(64 * 48 * 4);
        for (var i = 0; i < 64 * 48; i += 1) {
          rgba[i * 4] = 20 + frame * 30;
          rgba[i * 4 + 3] = 255;
        }
        expect(encoder.writeFrame(rgba), isTrue, reason: encoder.lastError);
        final pcm = Int16List(samplesPerFrame * 2);
        for (var i = 0; i < pcm.length; i += 1) {
          pcm[i] = (i * 37 + frame * 1000) % 20000 - 10000;
        }
        expect(
          encoder.writeAudio(pcm, samplesPerFrame),
          isTrue,
          reason: encoder.lastError,
        );
      }
      expect(encoder.finish(), isTrue, reason: encoder.lastError);

      final kept = await tester.runAsync(
        () => s.trimmedPieces.cut(
          source,
          MediaAssetKind.video,
          inFrame: 3,
          outFrame: 8,
        ),
      );

      expect(kept?.frames, 6);
      final decoder = QaVideoDecoder.instance!;
      final original = decoder.openDocument(source)!;
      final cut = decoder.openDocument(kept!.path)!;
      try {
        expect(cut.info.frameCount, 6, reason: 'project frames 4..9');
        expect(
          cut.info.fpsNumerator / cut.info.fpsDenominator,
          rate.numerator / rate.denominator,
          reason: 'at the project\'s own pace — frame n is frame n',
        );
        final clock = movieClockFor(
          projectRate: rate,
          audioSpeed: (numerator: 1, denominator: 1),
          movie: original.info,
        );
        for (var n = 0; n < 6; n += 1) {
          final shown = decoder.frameOf(original, clock.movieFrameAt(3 + n))!;
          final kept = decoder.frameOf(cut, n)!;
          expect(
            (kept[0] - shown[0]).abs(),
            lessThan(12),
            reason: 'piece frame $n is what project frame ${3 + n} showed',
          );
        }
      } finally {
        decoder.closeDocument(original);
        decoder.closeDocument(cut);
      }
      await tester.pumpAndSettle();
    }, skip: skip);
  });
}
