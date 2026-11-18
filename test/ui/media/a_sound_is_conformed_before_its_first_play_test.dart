import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**A SOUND IS CONFORMED BEFORE ITS FIRST PLAY — A MOVIE'S TOO.**
///
/// A run waits for its sound (playback-waits-for-its-sound), so a sound
/// whose conform starts at the press makes the press wait for all of it.
/// A project's open warms every path that can carry a sound
/// (`warmAudioConforms`); the pool's import and the viewer's open are the
/// other two ways a sound comes in, and they warm by the same question
/// (`mediaKindCanCarrySound`).
///
/// 🔬11-18 (card viewer-first-play-stalls, test VM): a 60 s 1080p24 movie
/// in the viewer turned its first page 5.4 s after the first press and
/// 0.1 s after the second — the pool's import warmed audio files alone,
/// and a movie opened from the viewer's own picker was warmed by nothing.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-sound-warm-test');
  });

  tearDown(() => deleteTempQuietly(directory));

  /// A session whose conforms are only recorded: the path each was asked
  /// for, in [asked].
  EditorSessionManager sessionHearing(List<String> asked) =>
      EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: AudioConformStore(
          resolveConformPath: (_) => null,
          runner: (request) async {
            asked.add(request.sourcePath);
            return const ConformResult(
              outcome: ConformOutcome.undecodable,
              error: 'test stub',
            );
          },
          log: (_) {},
        ),
      );

  test('the pool\'s import conforms what can carry a sound — a sound file '
      'and a movie — and nothing else', () async {
    final asked = <String>[];
    final session = sessionHearing(asked);
    addTearDown(session.dispose);
    String file(String name) =>
        (File('${directory.path}/$name')..writeAsBytesSync([0])).path;
    final sound = file('tone.wav');
    final movie = file('clip.mp4');

    await session.mediaPool.importMediaFiles([
      sound,
      movie,
      file('still.png'),
      file('board.pdf'),
    ], copyIntoProject: false);
    await pumpEventQueue();

    expect(
      asked.toSet(),
      {normalizedMediaPath(sound), normalizedMediaPath(movie)},
      reason: '🪦a movie\'s soundtrack waited for its first press',
    );
  });

  group('the viewer', () {
    late List<String> asked;
    late EditorSessionManager session;
    late MediaViewerSlot slot;

    setUp(() {
      asked = <String>[];
      session = sessionHearing(asked);
      slot = MediaViewerSlot();
    });

    tearDown(() {
      debugVideoDecodeBackend = null;
      slot.dispose();
      session.dispose();
    });

    Future<void> pumpViewer(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: slot.position,
              builder: (context, position, _) => MediaViewerTabHost(
                viewerId: 'media-viewer',
                session: session,
                request: slot.request,
                position: slot.position,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('🎯a movie it opens — come through no pool — is conformed '
        'before anything is pressed', (tester) async {
      debugVideoDecodeBackend = FakeVideoBackend(frameCount: 12);
      await pumpViewer(tester);

      slot.request.value = const MediaViewerRequest(
        path: 'C:/work/clip.mp4',
        kind: MediaAssetKind.video,
      );
      await settleLoadedPages(tester);

      expect(
        asked,
        ['C:/work/clip.mp4'],
        reason: '🪦its first press waited for the whole of its sound',
      );
    });

    testWidgets('a picture it opens asks for no conform', (tester) async {
      await pumpViewer(tester);

      slot.request.value = MediaViewerRequest(
        path: normalizedMediaPath('${directory.path}/still.png'),
        kind: MediaAssetKind.image,
      );
      await tester.pump();

      expect(asked, isEmpty);
    });
  });
}
