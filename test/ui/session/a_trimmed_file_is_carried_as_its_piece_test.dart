import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/kept_span.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/movie_clock.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/services/import/media_import_planner.dart'
    show ImportDestination;
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/decode_audio_file.dart';
import '../../helpers/fake_pdf_document.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/temp_dir.dart';

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

  tearDown(() {
    PdfRenderService.debugResetForTests();
    deleteTempQuietly(tempDir);
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
      s.trimmedPieces.secure(piece);
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
    PdfRenderService.debugOpenerOverride = (_) async => pdf;
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

  testWidgets('🚨a piece whose bytes nothing holds is not let go of — '
      'staging skips a file it cannot open, and letting the piece go then '
      'would lose the only copy of its bytes', (tester) async {
    final s = session();
    final gif = await tester.runAsync(() => writeGif('walk.gif'));
    final piece = (await tester.runAsync(
      () => s.trimmedPieces.cut(gif!, MediaAssetKind.image, outFrame: 0),
    ))!.path;
    expect(s.mediaStagingStore.find(piece), isNull, reason: 'the premise');

    s.trimmedPieces.secure(piece);

    expect(File(piece).existsSync(), isTrue);
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
      final kept = decodeAudioFile(piece)!;
      final all = decodeAudioFile(source)!;
      final from = rate.frameToSample(6, 48000) * 2;
      final to = rate.frameToSample(18, 48000) * 2;
      expect(kept.sampleRate, 48000);
      expect(kept.channels, 2);
      expect(kept.samples.length, to - from, reason: 'frames 7..18, no more');
      expect(kept.samples.first, all.samples[from]);
      expect(kept.samples.last, all.samples[to - 1]);
      await tester.pumpAndSettle();
    }, skip: skip);

    testWidgets('🚨a sound is cut in its OWN time — at 1001/1000 project frame '
        'f plays source time f / rate × 1001/1000, and the piece starts there '
        '(cut from the conform instead, it would be sped twice)', (
      tester,
    ) async {
      final s = EditorSessionManager(
        initialProject: createDefaultProject().copyWith(
          audioSpeedNumerator: 1001,
          audioSpeedDenominator: 1000,
        ),
      );
      addTearDown(s.dispose);
      final source = writeWav('line.wav', 2);
      final rate = s.projectSettings.projectFrameRate;

      final cut = await tester.runAsync(
        () => s.trimmedPieces.cut(
          source,
          MediaAssetKind.audio,
          inFrame: 24,
          outFrame: 35,
        ),
      );

      final kept = decodeAudioFile(cut!.path)!;
      final all = decodeAudioFile(source)!;
      // 24 project frames are 1.001 seconds of source: 48048 samples.
      int sampleAt(int frame) =>
          frame * rate.denominator * 1001 * 48000 ~/ (rate.numerator * 1000);
      expect(sampleAt(24), 48048, reason: 'the premise: a whole sample');
      expect(
        kept.samples.first,
        all.samples[sampleAt(24) * 2],
        reason: 'one second of project time is 1.001 seconds of source',
      );
      expect(kept.samples.length, (sampleAt(36) - sampleAt(24)) * 2);
      await tester.pumpAndSettle();
    }, skip: skip);

    testWidgets('🚨a frame that starts between two samples starts where the '
        'MIXER starts it — rounded up, never a sample of the frame before '
        '(29.97: frame 1 begins at sample 1601.6)', (tester) async {
      const rate = ProjectFrameRate.ntsc(30);
      final s = EditorSessionManager(
        initialProject: createDefaultProject().copyWith(frameRate: rate),
      );
      addTearDown(s.dispose);
      final source = writeWav('line.wav', 1);

      final cut = await tester.runAsync(
        () => s.trimmedPieces.cut(
          source,
          MediaAssetKind.audio,
          inFrame: 1,
          outFrame: 3,
        ),
      );

      final kept = decodeAudioFile(cut!.path)!;
      final all = decodeAudioFile(source)!;
      expect(rate.frameToSample(1, 48000), 1602, reason: 'the premise');
      expect(
        kept.samples.first,
        all.samples[1602 * 2],
        reason: 'sample 1601 is still frame 0 — the mixer starts frame 1 at '
            '1602, and so does its piece',
      );
      expect(
        kept.samples.length,
        (rate.frameToSample(4, 48000) - 1602) * 2,
        reason: 'up to where the mixer starts frame 4',
      );
      await tester.pumpAndSettle();
    }, skip: skip);

    testWidgets('🚨a sound whose last frame the window counts only because its '
        'peaks round up is carried as EVERY frame of the span — silence past '
        'its end — and the door keeps all of them', (tester) async {
      final s = session();
      final rate = s.projectSettings.projectFrameRate;
      // 51800 samples: 25.9 frames of sound at 24fps, which the conform's
      // 80-a-second buckets round up to 87 × 600 = 52200 — past frame 26's
      // end, so the window counts 27 frames.
      const rateHz = 48000;
      final samples = Int16List(51800 * 2);
      for (var i = 0; i < samples.length; i += 1) {
        samples[i] = 5000;
      }
      final data = samples.buffer.asUint8List();
      final source = inTemp('tail.wav');
      File(source).writeAsBytesSync([
        ...wav16HeaderBytes(
          dataBytes: data.length,
          sampleRate: rateHz,
          channels: 2,
        ),
        ...data,
      ]);
      final peaks = await tester.runAsync(
        () => s.audioConformStore.ensurePeaksFor(normalizedMediaPath(source)),
      );
      expect(
        peaks!.durationFrames(rate),
        greaterThan(rate.framesCoveringExactSeconds(51800, rateHz)),
        reason: 'the premise: the window counts a frame the samples do not '
            'reach',
      );
      final counted = peaks.durationFrames(rate);

      final cut = await tester.runAsync(
        () => s.trimmedPieces.cut(source, MediaAssetKind.audio, inFrame: 20),
      );

      expect(cut?.frames, counted - 20, reason: 'to the last frame it counts');
      final kept = decodeAudioFile(cut!.path)!;
      expect(
        kept.samples.length,
        (rate.frameToSample(counted, rateHz) -
                rate.frameToSample(20, rateHz)) *
            2,
        reason: 'every frame of the span, whole',
      );
      expect(kept.samples.last, 0.0, reason: 'silence past the sound\'s end');

      final start = s.activeCutGlobalStartFrame;
      await tester.runAsync(
        () => s.importDoors.importSoundFile(
          path: cut.path,
          copyIntoProject: true,
          outFrame: cut.frames - 1,
          sourcePath: source,
        ),
      );
      expect(
        s.activeTrack.seLayers.first.timeline[start]?.length,
        cut.frames,
        reason: 'the block is the span the window showed — a piece that '
            'stopped at the last sample would measure a frame short, and the '
            'door would keep one less',
      );
      await tester.pumpAndSettle();
    }, skip: skip);

    /// How far apart two neighbouring frames' reds are in [writeMovie] —
    /// and therefore how far a piece frame may drift and still be THAT
    /// frame rather than its neighbour (see [cutsWhatTheProjectShows]).
    const redStep = 30;

    /// Eight movie frames at [fps], each its own flat red, over a sound —
    /// the size and sound the other encoder fixtures use (the OS encoder
    /// turns tiny frames away).
    void writeMovie(
      QaVideoEncoder encoder,
      String path,
      ({int numerator, int denominator}) fps,
    ) {
      expect(
        encoder.open(
          path: path,
          width: 64,
          height: 48,
          fpsNumerator: fps.numerator,
          fpsDenominator: fps.denominator,
          sampleRate: 44100,
          channels: 2,
        ),
        isTrue,
        reason: encoder.lastError,
      );
      final samplesPerFrame =
          44100 * fps.denominator ~/ fps.numerator;
      for (var frame = 0; frame < 8; frame += 1) {
        final rgba = Uint8List(64 * 48 * 4);
        for (var i = 0; i < 64 * 48; i += 1) {
          rgba[i * 4] = 20 + frame * redStep;
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
    }

    /// Cuts IN 3 .. OUT 8 of such a movie in a project whose sounds play at
    /// [speed], holds the piece against what the project showed — the span
    /// and the frames the movie's own clock gives, at [pace] frames a
    /// second — and answers how many frames it kept; null when this machine
    /// has no encoder to cut with.
    Future<int?> cutsWhatTheProjectShows(
      WidgetTester tester, {
      required ({int numerator, int denominator}) fps,
      required ({int numerator, int denominator}) speed,
      required double pace,
    }) async {
      final encoder = QaVideoEncoder.instance;
      if (encoder == null || !encoder.isSupported) {
        return null;
      }
      final s = EditorSessionManager(
        initialProject: createDefaultProject().copyWith(
          audioSpeedNumerator: speed.numerator,
          audioSpeedDenominator: speed.denominator,
        ),
      );
      addTearDown(s.dispose);
      final rate = s.projectSettings.projectFrameRate;
      final source = inTemp('take3.mp4');
      writeMovie(encoder, source, fps);

      final kept = await tester.runAsync(
        () => s.trimmedPieces.cut(
          source,
          MediaAssetKind.video,
          inFrame: 3,
          outFrame: 8,
        ),
      );

      final decoder = QaVideoDecoder.instance!;
      final original = decoder.openDocument(source)!;
      final clock = movieClockFor(
        projectRate: rate,
        audioSpeed: speed,
        movie: original.info,
      );
      final span = KeptSpan(
        length: clock.projectFramesCovering(original.info.frameCount),
        inFrame: 3,
        outFrame: 8,
      );
      expect(kept?.frames, span.count, reason: 'what the placement keeps');
      final cut = decoder.openDocument(kept!.path)!;
      try {
        expect(cut.info.frameCount, span.count);
        expect(
          cut.info.fpsNumerator / cut.info.fpsDenominator,
          closeTo(pace, 1e-3),
          reason: 'at the project\'s rate in the movie\'s own time — frame n '
              'is frame n',
        );
        for (var n = 0; n < span.count; n += 1) {
          final at = span.first + n;
          final movieFrame = clock.movieFrameAt(at);
          final shown = decoder.frameOf(original, movieFrame)!;
          final piece = decoder.frameOf(cut, n)!;
          // ⚠️The question is WHICH frame, so the bound is half the step
          // between neighbouring reds: nearer than that is this frame and
          // no other. A neighbour would sit ~30 away.
          // 🪦The Apple engine landed a flat red 13 away here and it was
          // read as that encoder's noise (2026-09-24, first run on a Mac).
          // It was the writer's colour matrix — a loss that grows with the
          // red, 17 at red 200 — and it is pinned where it lives, by the
          // colour test below. The reds go into the reason so a failure
          // says which it is.
          expect(
            (piece[0] - shown[0]).abs(),
            lessThan(redStep ~/ 2),
            reason: 'piece frame $n is what project frame $at showed — '
                'red ${piece[0]} in the piece, ${shown[0]} in the take, '
                '${20 + movieFrame * redStep} written',
          );
        }
      } finally {
        decoder.closeDocument(original);
        decoder.closeDocument(cut);
      }
      await tester.pumpAndSettle();
      return span.count;
    }

    /// How far a flat red may move through ONE encode and one decode.
    ///
    /// ⚠️Measured, not chosen: Media Foundation brings every red of
    /// [writeMovie] back within 3 (2026-09-24). A writer and reader that
    /// disagree about the YCbCr matrix lose a share of the red instead —
    /// BT.709 in and BT.601 out keeps 0.9136 of it, 17 short at red 200 —
    /// and this bound is what tells that loss from a codec's noise.
    const colourSlack = 8;

    testWidgets('🚨a frame the app writes comes back the colour it was '
        'written — one encode and one decode, on every engine', (
      tester,
    ) async {
      final encoder = QaVideoEncoder.instance;
      if (encoder == null || !encoder.isSupported) {
        return;
      }
      final source = inTemp('colours.mp4');
      writeMovie(encoder, source, (numerator: 12, denominator: 1));
      final decoder = QaVideoDecoder.instance!;
      final movie = decoder.openDocument(source)!;
      try {
        for (var frame = 0; frame < 8; frame += 1) {
          final written = 20 + frame * redStep;
          final red = decoder.frameOf(movie, frame)![0];
          expect(
            (red - written).abs(),
            lessThan(colourSlack),
            reason: 'frame $frame was written red $written and came back '
                '$red — a loss that grows with the red is the writer and '
                'the reader using two matrices',
          );
        }
      } finally {
        decoder.closeDocument(movie);
      }
      await tester.pumpAndSettle();
    }, skip: skip);

    testWidgets('🎯a trimmed movie is carried as an MP4 of the frames the '
        'project shows, one per project frame', (tester) async {
      final kept = await cutsWhatTheProjectShows(
        tester,
        fps: (numerator: 12, denominator: 1),
        speed: (numerator: 1, denominator: 1),
        pace: 24,
      );
      if (kept != null) {
        expect(kept, 6, reason: 'project frames 4..9 of a 12fps take');
      }
    }, skip: skip);

    testWidgets('🚨with the 1001/1000 pull on, a 23.976 take in a 24 project '
        'is cut FRAME FOR FRAME — the piece runs at 24000/1001, and its span '
        'is the pulled clock\'s, not the wall clock\'s', (tester) async {
      final kept = await cutsWhatTheProjectShows(
        tester,
        fps: (numerator: 24000, denominator: 1001),
        speed: (numerator: 1001, denominator: 1000),
        pace: 24000 / 1001,
      );
      if (kept != null) {
        expect(
          kept,
          5,
          reason: 'its eight frames ARE project frames 0..7 (MovieClock: 「a '
              '23.976→24 change keeps every frame where it was」), so OUT 8 '
              'stops at 7 — without the pull they would cover nine, and each '
              'project frame would show the take\'s frame before',
        );
      }
    }, skip: skip);
  });
}
