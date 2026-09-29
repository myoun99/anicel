import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_preview.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/recording_viewer_sound.dart';
import '../../helpers/settle_async.dart';

/// 🚨★★★**THE IMPORT WINDOW'S PLAY BUTTON PLAYS — sound and all.**
///
/// 유저 2026-09-27: 「임포트창에서 재생해도 소리안나고 재생되는지도
/// 모르겟네. 뷰어패널이랑 통일할거하면서 소리나게」. The button was
/// `onPlayPause: () {}` under a note saying playback would come 「the day a
/// video arrives」; the video arrived and the button went on doing nothing.
/// It runs the media viewer's own run now ([MediaRun]) over the viewer's
/// own document and pages — so what these pin is that the WINDOW'S way of
/// counting (a movie in the frames a placement counts, a sound in the
/// project's frames over its length) reaches that run intact.
void main() {
  late EditorSessionManager session;
  late RecordingViewerSound sound;

  /// A sound conform that answers at once: four seconds of it.
  const seconds = 4.0;
  AudioConformStore fourSeconds() => AudioConformStore(
    resolveConformPath: (_) => null,
    runner: (request) async => ConformResult(
      outcome: ConformOutcome.built,
      peaks: AudioPeaks(
        bucketsPerSecond: 80,
        peaks: Float32List((80 * seconds).round()),
      ),
      samples: Float32List((seconds * 48000).round()),
      channels: 1,
      sampleRate: 48000,
      frames: (seconds * 48000).round(),
    ),
    log: (_) {},
  );

  setUp(() {
    session = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: fourSeconds(),
    );
    sound = RecordingViewerSound(session.audioConformStore);
  });

  tearDown(() {
    debugVideoDecodeBackend = null;
    PdfRenderService.debugResetForTests();
    session.dispose();
  });

  /// A run's tick at 24fps — pumped between the real-time rounds a decode
  /// needs ([settleAsync]).
  const tick = Duration(milliseconds: 42);

  TransportBar bar(WidgetTester tester) =>
      tester.widget<TransportBar>(find.byType(TransportBar));

  Future<void> show(
    WidgetTester tester,
    String path, {
    ProjectFrameRate frameRate = ProjectFrameRate.fps24,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 360,
            child: ImportPreview(
              session: session,
              sound: sound,
              path: path,
              inFrame: 0,
              outFrame: null,
              rangeEditable: true,
              onRangeChanged: (_, _) {},
              soundPeaks: session.audioConformStore.ensurePeaksFor,
              holdBytes: session.projectFile.holdMediaBytes,
              frameRate: frameRate,
            ),
          ),
        ),
      ),
    );
    await settleAsync(tester, () => bar(tester).frameCount > 1);
  }

  Future<void> press(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('transport-play')));
    await tester.pump();
  }

  group('a movie', () {
    const movie = 'C:/work/clip.mp4';

    testWidgets('🚨the button RUNS it: the bar says so, the playhead walks, '
        'and the sound starts where the playhead stands', (tester) async {
      debugVideoDecodeBackend = FakeVideoBackend(frameCount: 12);
      await show(tester, movie);
      expect(bar(tester).frameCount, 12, reason: 'fixture: 12 frames at 24');

      await press(tester);

      expect(bar(tester).playing, isTrue);
      expect(sound.played, [movie]);
      expect(sound.from, [0]);
      expect(
        await settleAsync(
          tester,
          () => bar(tester).currentFrame > 0,
          attempts: 150,
          step: tick,
        ),
        isTrue,
        reason: 'the playhead walks as the frames land',
      );

      await press(tester);
      expect(bar(tester).playing, isFalse);
      expect(sound.isCarrying, isFalse, reason: 'and the sound stops with it');
    });

    testWidgets('a seek while it plays picks the sound up at the new '
        'instant, and the run goes on from there', (tester) async {
      debugVideoDecodeBackend = FakeVideoBackend(frameCount: 12);
      await show(tester, movie);
      await press(tester);

      bar(tester).onSeek(6);
      await tester.pump();

      expect(sound.from, [0, 6 / 24]);
      expect(bar(tester).playing, isTrue);
      expect(bar(tester).currentFrame, 6);
      await press(tester);
    });

    testWidgets('⛔a seek to the LAST frame while it plays stands there — '
        '「from the top」 answers a press of play, not a hand', (tester) async {
      debugVideoDecodeBackend = FakeVideoBackend(frameCount: 12);
      await show(tester, movie);
      await press(tester);

      bar(tester).onSeek(11);
      await tester.pump();

      expect(bar(tester).currentFrame, 11);
      expect(sound.from, [0, 11 / 24]);
      await press(tester);
    });

    testWidgets('a path spelled with backslashes plays the sound the window '
        'conformed — by the key the pool and the conform store use', (
      tester,
    ) async {
      debugVideoDecodeBackend = FakeVideoBackend(frameCount: 12);
      await show(tester, r'C:\work\clip.mp4');

      await press(tester);

      expect(sound.played, [movie]);
      await press(tester);
    });

    testWidgets('🎯in a 12fps project it counts the PROJECT\'s frames — the '
        'ones a placement counts — and its sound starts at their instant', (
      tester,
    ) async {
      debugVideoDecodeBackend = FakeVideoBackend(frameCount: 12);
      await show(tester, movie, frameRate: const ProjectFrameRate.integer(12));
      expect(bar(tester).frameCount, 6, reason: 'half a second at 12');

      bar(tester).onSeek(3);
      await tester.pump();
      await press(tester);

      expect(sound.from, [3 / 12], reason: 'frame 3 at 12 is 0.25 seconds in');
      await press(tester);
    });
  });

  group('a sound', () {
    const line = 'C:/snd/line.wav';

    testWidgets('🚨it plays, and the bar follows the DEVICE\'s clock', (
      tester,
    ) async {
      await show(tester, line);
      expect(bar(tester).frameCount, 96, reason: 'fixture: 4 s at 24');

      await press(tester);
      expect(bar(tester).playing, isTrue);
      expect(sound.from, [0]);

      sound.at = 1.0;
      await tester.pump(const Duration(milliseconds: 16));
      expect(bar(tester).currentFrame, 24, reason: 'one second in, at 24');
      await press(tester);
    });

    testWidgets('a seek while it plays picks it up at the frame\'s instant', (
      tester,
    ) async {
      await show(tester, line);
      await press(tester);

      bar(tester).onSeek(12);
      await tester.pump();

      expect(sound.from, [0, 0.5]);
      expect(bar(tester).currentFrame, 12);
      await press(tester);
    });

    testWidgets('paused, a seek moves where the NEXT press starts', (
      tester,
    ) async {
      await show(tester, line);

      bar(tester).onSeek(36);
      await tester.pump();
      await press(tester);

      expect(sound.from, [1.5]);
      await press(tester);
    });
  });

  testWidgets('a document that turns its own pages plays with nothing to '
      'hear', (tester) async {
    PdfRenderService.debugOpenerOverride = (_) async => FakePdfDocument(
      pageSizes: List.filled(6, const ui.Size(64, 36)),
      framesPerSecond: 24,
    );
    await show(tester, 'C:/work/flip.pdf');

    await press(tester);

    expect(bar(tester).playing, isTrue);
    expect(sound.played, isEmpty, reason: 'a PDF carries no sound');
    expect(
      await settleAsync(
        tester,
        () => bar(tester).currentFrame > 0,
        attempts: 150,
        step: tick,
      ),
      isTrue,
    );
    await press(tester);
  });

  testWidgets('⛔a PDF has nothing to play: the button is where it always '
      'is, and off', (tester) async {
    PdfRenderService.debugOpenerOverride = (_) async =>
        FakePdfDocument(pageSizes: List.filled(3, const ui.Size(595, 842)));
    await show(tester, 'C:/work/conte.pdf');

    expect(find.byKey(const ValueKey<String>('transport-play')), findsOneWidget);
    expect(bar(tester).onPlayPause, isNull);
  });
}
