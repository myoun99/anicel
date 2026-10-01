import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/recording_viewer_sound.dart';

/// 🚨★★★**A PRESS PICKS THE SOUND UP WHERE THE PLAYHEAD STANDS**
/// (import-preview-plays-silent, 2026-09-29).
///
/// The viewer's own playhead says so — 「where the playhead STANDS is what
/// tells you where a second press would resume from」 — and every press
/// started the sound at 0 all the same: a movie played from a page played
/// its picture from the page and its sound from the top, and a paused
/// sound started over. A run also never moved its streaming window, so a
/// sound past two minutes went silent half a minute in; every tick now asks
/// the window to follow ([ViewerSound.keepStreaming]).
void main() {
  late MediaViewerSlot slot;
  late RecordingViewerSound sound;
  EditorSessionManager? session;

  setUp(() => slot = MediaViewerSlot());

  tearDown(() {
    debugVideoDecodeBackend = null;
    slot.dispose();
    session?.dispose();
    session = null;
  });

  Future<void> pumpViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: slot.position,
            builder: (context, position, _) => MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session!,
              request: slot.request,
              position: slot.position,
              sound: sound,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> press(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
    );
    await tester.pump();
  }

  group('a movie', () {
    Future<void> openMovie(WidgetTester tester) async {
      session = EditorSessionManager(initialProject: createDefaultProject());
      sound = RecordingViewerSound(session!.audioConformStore);
      debugVideoDecodeBackend = FakeVideoBackend(frameCount: 12);
      await pumpViewer(tester);
      slot.request.value = const MediaViewerRequest(
        path: 'C:/work/clip.mp4',
        kind: MediaAssetKind.video,
        name: 'clip',
      );
      await tester.pumpAndSettle();
    }

    testWidgets('🎯played from page 6 of a 24fps movie, the sound starts at '
        'page 6', (tester) async {
      await openMovie(tester);
      slot.position.value = 6;
      await tester.pump();

      await press(tester);

      expect(sound.from, [6 / 24], reason: '🪦it started at 0');
      await press(tester);
    });

    testWidgets('played from its last page, a movie starts over — the sound '
        'from the top with it', (tester) async {
      await openMovie(tester);
      slot.position.value = 11;
      await tester.pump();

      await press(tester);

      expect(slot.position.value, 0);
      expect(sound.from, [0]);
      await press(tester);
    });

    testWidgets('every tick of a run asks the stream to follow', (
      tester,
    ) async {
      await openMovie(tester);
      await press(tester);
      for (var tick = 0; tick < 3; tick += 1) {
        await tester.pump(const Duration(milliseconds: 42));
      }

      expect(sound.keeps, greaterThanOrEqualTo(3));
      await press(tester);
    });
  });

  group('a sound', () {
    const seconds = 4.0;

    Future<void> openSound(WidgetTester tester) async {
      session = EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: AudioConformStore(
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
        ),
      );
      sound = RecordingViewerSound(session!.audioConformStore);
      await pumpViewer(tester);
      slot.request.value = const MediaViewerRequest(
        path: 'C:/work/line.wav',
        kind: MediaAssetKind.audio,
        name: 'line',
      );
      await tester.pumpAndSettle();
      expect(
        session!.audioConformStore.durationSecondsFor('C:/work/line.wav'),
        seconds,
        reason: 'fixture: the conform has landed and knows its length',
      );
    }

    testWidgets('🎯paused at 1.5 s, a sound resumes at 1.5 s', (tester) async {
      await openSound(tester);
      await press(tester);
      expect(sound.from, [0]);

      sound.at = 1.5;
      await tester.pump(const Duration(milliseconds: 16));
      await press(tester);
      await press(tester);

      expect(sound.from, [0, 1.5], reason: '🪦it started over at 0');
      await press(tester);
    });

    testWidgets('🎯a NEW sound starts from its own top, not where the last '
        'one stood', (tester) async {
      await openSound(tester);
      await press(tester);
      sound.at = 1.5;
      await tester.pump(const Duration(milliseconds: 16));
      await press(tester);

      slot.request.value = const MediaViewerRequest(
        path: 'C:/work/other.wav',
        kind: MediaAssetKind.audio,
        name: 'other',
      );
      await tester.pumpAndSettle();
      await press(tester);

      expect(
        sound.from,
        [0, 0],
        reason: '🪦where the playhead stood was kept across files — a fact '
            'about a sound that is no longer shown',
      );
      await press(tester);
    });

    testWidgets('a sound that ran to its end starts over from the top', (
      tester,
    ) async {
      await openSound(tester);
      await press(tester);
      // The last tick that reads the device reads it a tick short of the
      // end; the next finds it ended.
      sound.at = seconds - 0.01;
      await tester.pump(const Duration(milliseconds: 16));
      sound.hasEnded = true;
      await tester.pump(const Duration(milliseconds: 16));

      await press(tester);

      expect(
        sound.from,
        [0, 0],
        reason: 'the playhead stood ON the end, so the press starts over — '
            'a press from a tick short would play one tick and stop',
      );
      await press(tester);
    });
  });
}
