import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/waveform_painter.dart';
import 'package:anicel/src/ui/import/import_preview.dart';
import 'package:anicel/src/ui/media/audio_viewer_document.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

import '../../helpers/the_file_itself.dart';

/// 🚨A SOUND IN THE IMPORT WINDOW IS ITS WAVEFORM, AND IT CAN BE TRIMMED
/// (유저 2026-09-11, 미디어 배치 라운드: 「놓으면 배치 창이 열리고, 거기서
/// 가져올 구간을 줄이면 블록도 그만큼 줄어든다」). A sound used to fall to the
/// still decode and run over ONE frame: no picture, and no range to shorten.
void main() {
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

  testWidgets('the transport runs over the frames the sound lasts, with its '
      'IN/OUT ends', (tester) async {
    await pump(tester);

    expect(bar(tester).frameCount, 48);
    expect(bar(tester).showRange, isTrue);
  });

  testWidgets('its frames are the PROJECT\'s', (tester) async {
    await pump(tester, frameRate: const ProjectFrameRate.integer(12));

    expect(bar(tester).frameCount, 24);
  });

  testWidgets('its picture is the viewer\'s waveform in the viewer\'s ink, '
      'on no checker', (tester) async {
    await pump(tester);

    final band = tester.widget<CustomPaint>(
      find.byKey(const ValueKey<String>('import-preview-waveform')),
    );
    final painter = band.painter! as WaveformPainter;
    expect(painter.peaks, same(twoSeconds));
    expect(painter.color, AudioViewerDocument.ink);
    expect(
      find.byKey(const ValueKey<String>('import-preview-checker')),
      findsNothing,
      reason: 'a sound has no open alpha to show',
    );
  });

  testWidgets('the span IN/OUT keep is washed on the band, frame for frame', (
    tester,
  ) async {
    await pump(tester, inFrame: 12, outFrame: 23);

    final band = tester.getRect(
      find.byKey(const ValueKey<String>('import-preview-waveform')),
    );
    final wash = tester.getRect(
      find.byKey(const ValueKey<String>('import-preview-kept-span')),
    );
    final perFrame = band.width / 48;
    expect(wash.left - band.left, closeTo(12 * perFrame, 0.01));
    expect(wash.width, closeTo(12 * perFrame, 0.01));
    expect(
      (bar(tester).inFrame, bar(tester).outFrame),
      (12, 23),
      reason: 'the wash and the transport read one span',
    );
    final washBox = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('import-preview-kept-span')),
    );
    expect(
      (washBox.decoration as BoxDecoration).color,
      TransportBar.rangeWash,
      reason: 'washed as the transport washes its range',
    );
  });

  testWidgets('⛔where IN/OUT do not bite, the wash is clear — and still '
      'there, so nothing pops in when they do', (tester) async {
    await pump(tester, rangeEditable: false);

    final wash = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('import-preview-kept-span')),
    );
    expect((wash.decoration as BoxDecoration).color, isNull);
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

    expect(
      find.byKey(const ValueKey<String>('import-preview-waveform')),
      findsNothing,
    );
    expect(bar(tester).frameCount, 1);
  });
}
