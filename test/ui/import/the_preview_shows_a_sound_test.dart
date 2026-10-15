import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_preview.dart';
import 'package:anicel/src/ui/media/waveform_marks_painter.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/import_preview_probe.dart';
import '../../helpers/the_file_itself.dart';

/// 🚨A SOUND IN THE IMPORT WINDOW IS ITS WAVEFORM, AND IT CAN BE TRIMMED
/// (유저 2026-09-11, 미디어 배치 라운드: 「놓으면 배치 창이 열리고, 거기서
/// 가져올 구간을 줄이면 블록도 그만큼 줄어든다」). A sound used to fall to the
/// still decode and run over ONE frame: no picture, and no range to shorten.
void main() {
  late EditorSessionManager session;

  setUp(
    () => session = EditorSessionManager(
      initialProject: createDefaultProject(),
    ),
  );
  tearDown(() => session.dispose());

  /// Two seconds at the conform's 80 buckets a second: 48 frames at 24.
  final twoSeconds = AudioPeaks(
    bucketsPerSecond: 80,
    peaks: Float32List.fromList([
      for (var bucket = 0; bucket < 160; bucket += 1)
        if (bucket.isEven) 0.9 else 0.2,
    ]),
  );

  Future<void> pump(
    WidgetTester tester, {
    int inFrame = 0,
    int? outFrame,
    bool rangeEditable = true,
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
              path: 'C:/snd/door.wav',
              inFrame: inFrame,
              outFrame: outFrame,
              rangeEditable: rangeEditable,
              onRangeChanged: (_, _) {},
              soundPeaks: (_) async => twoSeconds,
              holdBytes: theFileItself,
              frameRate: frameRate,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  TransportBar bar(WidgetTester tester) =>
      tester.widget<TransportBar>(find.byType(TransportBar));

  /// The marks over the band — its playhead and the span kept — or null
  /// while no sound is on show.
  WaveformMarksPainter? marks(WidgetTester tester) {
    final layer = find.byKey(const ValueKey<String>('import-preview-marks'));
    return layer.evaluate().isEmpty
        ? null
        : tester.widget<CustomPaint>(layer).painter as WaveformMarksPainter?;
  }

  testWidgets('the transport runs over the frames the sound lasts, with its '
      'IN/OUT ends', (tester) async {
    await pump(tester);

    expect(bar(tester).frameCount, 48);
    expect(bar(tester).range!.onChanged, isNotNull);
  });

  testWidgets('🎯a MOVIE that brings its sound alone shows the sound it '
      'brings — its waveform, over the frames the sound lasts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            height: 360,
            child: ImportPreview(
              session: session,
              path: 'C:/mov/take.mp4',
              opensAsSound: true,
              inFrame: 0,
              outFrame: null,
              rangeEditable: true,
              onRangeChanged: (_, _) {},
              soundPeaks: (_) async => twoSeconds,
              holdBytes: theFileItself,
              frameRate: ProjectFrameRate.fps24,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(marks(tester), isNotNull, reason: 'its band is on show');
    expect(bar(tester).frameCount, 48, reason: 'two seconds at 24');
  });

  testWidgets('⛔a sound that answers after the row turned back to its '
      'picture is not shown — the same file, opened the other way', (
    tester,
  ) async {
    // No reader: the picture's load settles at once, on nothing.
    debugVideoDecodeBackend = FakeVideoBackend(supported: false);
    addTearDown(() => debugVideoDecodeBackend = null);
    final answer = Completer<AudioPeaks?>();
    Widget preview({required bool asSound}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: 360,
          child: ImportPreview(
            session: session,
            path: 'C:/mov/take.mp4',
            opensAsSound: asSound,
            inFrame: 0,
            outFrame: null,
            rangeEditable: true,
            onRangeChanged: (_, _) {},
            soundPeaks: (_) => answer.future,
            holdBytes: theFileItself,
            frameRate: ProjectFrameRate.fps24,
          ),
        ),
      ),
    );

    await tester.pumpWidget(preview(asSound: true));
    await tester.pumpWidget(preview(asSound: false));
    answer.complete(twoSeconds);
    await tester.pump();
    await tester.pump();

    expect(marks(tester), isNull);
  });

  testWidgets('its frames are the PROJECT\'s', (tester) async {
    await pump(tester, frameRate: const ProjectFrameRate.integer(12));

    expect(bar(tester).frameCount, 24);
  });

  testWidgets('its picture is the viewer\'s waveform page — the band the '
      'viewer opens a sound as — on no checker', (tester) async {
    await pump(tester);

    expect(
      [for (final page in tester.importPreviewPage!.pages) page.rect],
      [Offset.zero & const Size(200, 256)],
      reason: 'two seconds of the viewer\'s band: 100 pixels a second, 256 '
          'tall (`AudioViewerDocument`, through the viewer\'s door)',
    );
    expect(
      tester.importPreviewCheckered,
      isFalse,
      reason: 'a sound has no open alpha to show',
    );
  });

  testWidgets('the span IN/OUT keep is washed on the band, frame for frame', (
    tester,
  ) async {
    await pump(tester, inFrame: 12, outFrame: 23);

    expect(
      marks(tester)!.kept,
      (from: 0.5, to: 1.0),
      reason: 'frames 12 to 23 at 24: from half a second to the end of the '
          'first',
    );
    expect(
      (bar(tester).range!.inFrame, bar(tester).range!.outFrame),
      (12, 23),
      reason: 'the wash and the transport read one span',
    );
  });

  testWidgets('⛔where IN/OUT do not bite, the wash is clear — and still '
      'there, so nothing pops in when they do', (tester) async {
    await pump(tester, rangeEditable: false);

    expect(marks(tester), isNotNull, reason: 'the layer is there');
    expect(marks(tester)!.kept, isNull, reason: 'and washes nothing');
  });

  testWidgets('⛔a sound that answers after the window moved on is not '
      'shown', (tester) async {
    final answer = Completer<AudioPeaks?>();
    Widget preview(String? path) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 480,
          height: 360,
          child: ImportPreview(
            session: session,
            path: path,
            inFrame: 0,
            outFrame: null,
            rangeEditable: true,
            onRangeChanged: (_, _) {},
            soundPeaks: (_) => answer.future,
            holdBytes: theFileItself,
            frameRate: ProjectFrameRate.fps24,
          ),
        ),
      ),
    );

    await tester.pumpWidget(preview('C:/snd/door.wav'));
    await tester.pumpWidget(preview(null));
    answer.complete(twoSeconds);
    // The answer lands in a microtask the first pump flushes AFTER its
    // frame; only the second pump draws what that answer changed.
    await tester.pump();
    await tester.pump();

    expect(marks(tester), isNull);
    expect(bar(tester).frameCount, 1);
  });
}
