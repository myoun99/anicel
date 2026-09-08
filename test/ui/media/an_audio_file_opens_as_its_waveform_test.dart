import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/audio_viewer_document.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🚨★★★**A SOUND HAS A PICTURE AND IT IS ITS WAVEFORM.**
///
/// 유저 2026-09-08: 「뷰어 소리 내는 범위는 싹 다야. **오디오파일도
/// 열려야하고.** 미디어풀에 들어가는건 전부. **통일적으로.** 오디오는 그래서
/// 파형을 보이게한다던가. **비디오 프로그램이랑 비슷한느낌으로**」.
///
/// The viewer used to answer 「이 종류의 미디어는 아직 표시할 수 없습니다」 for
/// every audio asset and stop there.
void main() {
  /// A two-second conform: 80 buckets a second is the store's own rate.
  AudioPeaks peaksOfSeconds(double seconds) => AudioPeaks(
    bucketsPerSecond: 80,
    peaks: Float32List.fromList([
      for (var bucket = 0; bucket < (80 * seconds).round(); bucket += 1)
        // A shape rather than a flat line, so a band that painted nothing
        // cannot be told apart from one that painted silence.
        bucket.isEven ? 0.9 : 0.2,
    ]),
  );

  group('the document', () {
    test('its page is as wide as the sound is long', () {
      final short = AudioViewerDocument(
        peaks: peaksOfSeconds(2),
        color: const Color(0xFF808080),
      );
      final long = AudioViewerDocument(
        peaks: peaksOfSeconds(4),
        color: const Color(0xFF808080),
      );

      expect(short.pageCount, 1);
      expect(
        long.pageSize(0).width,
        closeTo(short.pageSize(0).width * 2, 0.01),
        reason: 'twice the sound is twice the page — the duration is the '
            'only thing that decides the width',
      );
      expect(long.pageSize(0).height, short.pageSize(0).height);
    });

    test('⛔the pages do not turn by themselves — a waveform is not a movie', () {
      expect(
        AudioViewerDocument(
          peaks: peaksOfSeconds(2),
          color: const Color(0xFF808080),
        ).framesPerSecond,
        isNull,
      );
    });

    test('an empty conform is still a page the panel can lay out', () {
      final empty = AudioViewerDocument(
        peaks: AudioPeaks(bucketsPerSecond: 80, peaks: Float32List(0)),
        color: const Color(0xFF808080),
      );

      expect(empty.pageSize(0).width, greaterThan(0));
      expect(empty.pageSize(0).height, greaterThan(0));
    });

    /// ⚠️A plain `test`, not `testWidgets`: `Picture.toImage` never
    /// completes inside the widget tester's fake-async zone (measured — it
    /// hung the whole file), and the band's own tests already know this.
    test('it renders at exactly the pixels it was asked for, and paints '
        'the band', () async {
      final document = AudioViewerDocument(
        peaks: peaksOfSeconds(2),
        color: const Color(0xFFFFFFFF),
      );

      final image = await document.renderPage(0, width: 240, height: 64);
      addTearDown(image.dispose);

      expect(image.width, 240);
      expect(image.height, 64);
      final bytes = await image.toByteData();
      final drawn = bytes!.buffer.asUint8List().any((byte) => byte != 0);
      expect(
        drawn,
        isTrue,
        reason: 'an all-transparent page would mean the band never landed — '
            'the page IS the waveform, so nothing drawn is nothing shown',
      );
    });
  });

  group('the viewer', () {
    late MediaViewerSlot slot;
    EditorSessionManager? session;

    setUp(() => slot = MediaViewerSlot());

    tearDown(() {
      slot.dispose();
      session?.dispose();
    });

    /// A session whose conform store answers with [result] for anything.
    Future<void> pumpViewer(
      WidgetTester tester, {
      required ConformResult result,
    }) async {
      session = EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: AudioConformStore(
          resolveConformPath: (_) => null,
          runner: (request) async => result,
          log: (_) {},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session!,
              request: slot.request,
              position: 0,
            ),
          ),
        ),
      );
      slot.request.value = const MediaViewerRequest(
        path: 'C:/work/line.wav',
        kind: MediaAssetKind.audio,
        name: 'line',
      );
      await tester.pumpAndSettle();
    }

    ui.Image? drawnPage(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey<String>('media-viewer-page')),
      );
      return (paint.painter as dynamic).image as ui.Image?;
    }

    testWidgets('a readable sound draws its waveform, and says nothing', (
      tester,
    ) async {
      await pumpViewer(
        tester,
        result: ConformResult(
          outcome: ConformOutcome.built,
          peaks: peaksOfSeconds(2),
          samples: Float32List(2 * 48000),
          channels: 1,
          sampleRate: 48000,
          frames: 2 * 48000,
        ),
      );

      expect(drawnPage(tester), isNotNull);
      expect(
        find.byKey(const ValueKey<String>('media-viewer-message')),
        findsNothing,
        reason: '🪦the viewer used to answer 「표시할 수 없습니다」 here',
      );
    });

    testWidgets('a sound this build cannot read says SO — and not the '
        'generic 「this kind cannot be shown」', (tester) async {
      await pumpViewer(
        tester,
        result: const ConformResult(
          outcome: ConformOutcome.undecodable,
          error: 'no decoder',
        ),
      );

      final strings = AppText.strings;
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey<String>('media-viewer-message')),
            )
            .data,
        strings.mediaViewerNoAudioDecoder,
        reason: 'audio has a picture now, so an absence here is a conform '
            'that could not be built — the same shape the video arm has',
      );
    });
  });
}
