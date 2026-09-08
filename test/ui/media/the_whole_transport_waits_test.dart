

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';

import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';



import 'package:anicel/src/services/media/video_decode_worker.dart';

import '../../helpers/fake_video_backend.dart';

/// 🚨★★★**THE WHOLE TRANSPORT WAITS — SOUND INCLUDED.**
///
/// 유저 2026-08-31 gave this viewer its law: 「유지하지말고 **로드할때까지
/// 멈춰있어야지**」, because a held picture cannot be told apart from a hold
/// the animator DREW. Once a movie plays its soundtrack beside that
/// picture, the law has to reach the sound — the alternative proves it:
/// letting the sound run on while the picture parks means the picture must
/// later CATCH UP by dropping frames, and dropping frames is what the user
/// rejected for this surface in the first place.
///
/// ⚠️This file exists because the bench is BLIND to sound. A widget test
/// never gets an audio device (`audioOutputUnlessTesting`), so every call
/// the panel makes into [ViewerSound] is a no-op and deleting any of them
/// leaves the rest of the suite green. The panel takes an injectable
/// [ViewerSound] for exactly this — the same seam its file picker has.
///
/// 🪦This file carried a paragraph headed 「WHAT IS STILL NOT MEASURED HERE」
/// for one round: the hold-and-resume needs a document that turns pages AND
/// carries sound, a fake PDF carries none, and a real movie could not be
/// opened on the bench. Half of that was wrong —
/// `debugVideoDecodeBackend` had been there all along. What actually
/// blocked it was `VideoViewerDocument` asking a DIFFERENT object whether a
/// reader existed, so the injected backend was never reached. The
/// capability moved onto the backend and the paragraph is now a test.
void main() {
  late EditorSessionManager session;
  late MediaViewerSlot slot;
  late _RecordingSound sound;
  var opens = 0;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    sound = _RecordingSound(session.audioConformStore);
    opens = 0;
  });

  tearDown(() {
    debugVideoDecodeBackend = null;
    slot.dispose();
    session.dispose();
  });

  /// A REAL movie document of [pages] frames at 24fps, decoded by a fake
  /// backend.
  ///
  /// 🚨★★★It was a fake PDF until 2026-09-08, because a movie could not be
  /// opened on the bench at all — and a PDF carries no sound, so the half
  /// of the law about the SOUND could not be reached. See
  /// [FakeVideoBackend].
  /// ⚠️[holdFrom] is set BEFORE the open, not after: the viewer buffers
  /// ahead while the document lands, so a frame held afterwards is already
  /// in the cache and the buffer never runs dry (measured — the first
  /// version of the dry-buffer test below passed nothing because of it).
  Future<FakeVideoBackend> openMovie(
    WidgetTester tester, {
    int pages = 12,
    int? holdFrom,
  }) async {
    opens += 1;
    slot.request.value = null;
    slot.position.value = 0;
    final fake = FakeVideoBackend(frameCount: pages);
    if (holdFrom != null) {
      for (var frame = holdFrom; frame < pages; frame += 1) {
        fake.held.add(frame);
      }
    }
    debugVideoDecodeBackend = fake;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: slot.position,
            builder: (context, position, _) => MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: position,
              onPositionChanged: (next) => slot.position.value = next,
              sound: sound,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    slot.request.value = MediaViewerRequest(
      // A movie, so `mediaKindCanCarrySound` says it can hold a soundtrack.
      path: 'C:/work/clip-$opens.mp4',
      kind: MediaAssetKind.video,
      name: 'clip',
    );
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> pressPlay(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
    );
    await tester.pump();
  }

  /// The door itself. ⛔Without this the tests below can pass for the wrong
  /// reason: the play button appears for anything that CARRIES sound, so a
  /// movie that never opened still gets one.
  testWidgets('a movie opens, and its frames are what the viewer pages '
      'through', (tester) async {
    final fake = await openMovie(tester);

    expect(find.text('1 / 12'), findsOneWidget);
    expect(
      fake.asked,
      isNotEmpty,
      reason: 'the viewer asked the backend for a frame — the arm is '
          'reachable on the bench at last',
    );
  });


  testWidgets('pressing play starts the soundtrack', (tester) async {
    await openMovie(tester);
    await pressPlay(tester);

    expect(
      sound.played,
      ['C:/work/clip-1.mp4'],
      reason: '🪦the viewer was completely silent until 2026-09-08 — a movie '
          'turned its pages and its soundtrack was never asked for',
    );
  });

  testWidgets('🚨a buffer that runs dry HOLDS the sound — and does NOT '
      'come back (a pinned bug)', (tester) async {
    // Nothing past the first frame will decode: the cushion cannot fill.
    final fake = await openMovie(tester, holdFrom: 1);
    await pressPlay(tester);
    expect(sound.holds, 0, reason: 'fixture: nothing has run dry yet');

    // 24fps is 41.6ms, so one pump of 42 sits on the boundary — the
    // neighbouring file drives ten for the same reason.
    for (var tick = 0; tick < 3; tick += 1) {
      await tester.pump(const Duration(milliseconds: 42));
    }
    expect(
      sound.holds,
      greaterThan(0),
      reason: 'the sound parks WITH the picture — 「로드할때까지 멈춰있어야지」 '
          'reaches the soundtrack, or the picture would owe it dropped '
          'frames later',
    );
    expect(slot.position.value, 0, reason: 'and the playhead did not move');

    // 🚨★★★**AND IT DOES NOT COME BACK.** Releasing every held frame and
    // pumping THREE HUNDRED ticks leaves `resumes` at zero and the playhead
    // at 0 — 실측 2026-09-08, the first time this arm could be driven at
    // all. So 「로드할때까지 멈춰있어야지」 is currently 「멈춰만 있는다」, and
    // now that sound parks with the picture it parks forever too.
    //
    // ⛔This test asserts the park and STOPS THERE on purpose. The refill
    // walks forward because each landing rebuilds and the rebuild asks for
    // the next raster; a parked tick rebuilds nothing, so once every
    // outstanding render has failed the chain has no link left. That is a
    // guess about the cause — kicking `_fillPlaybackBuffer` from the parked
    // tick was tried and changed nothing — so it is written down rather
    // than fixed blind. `viewer-parks-forever-after-a-dry-buffer` on the
    // board carries it.
    fake.held.clear();
    for (var tick = 0; tick < 300 && sound.resumes == 0; tick += 1) {
      await tester.pump(const Duration(milliseconds: 42));
    }
    expect(
      sound.resumes,
      0,
      reason: '⚠️PINNING A BUG, not a law: the day this goes red the viewer '
          'has learned to come back, and the assertion becomes '
          'greaterThan(0) — with the playhead moving beside it',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
    );
    await tester.pump();
  });

  testWidgets('stopping the run stops the sound', (tester) async {
    await openMovie(tester);
    await pressPlay(tester);
    final before = sound.stops;

    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
    );
    await tester.pump();

    expect(
      sound.stops,
      greaterThan(before),
      reason: '🧪this is the line the previous round could only write a note '
          'beside: on the bench a sound left playing is invisible, and this '
          'seam is what makes it visible',
    );
  });
}

/// A [ViewerSound] that records what it was asked to do, and reports that
/// it is carrying — so the panel takes the paths a real device would.
class _RecordingSound extends ViewerSound {
  _RecordingSound(AudioConformStore store) : super(conformStore: store);

  final List<String> played = [];
  int holds = 0;
  int resumes = 0;
  int stops = 0;

  @override
  bool get isCarrying => played.isNotEmpty;

  @override
  bool play(String sourcePath, {double fromSeconds = 0}) {
    played.add(sourcePath);
    return true;
  }

  @override
  void hold() => holds += 1;

  @override
  void resume(double fromSeconds) => resumes += 1;

  @override
  void stop() {
    stops += 1;
    played.clear();
  }

  /// A clock that stands still: the tests here drive the PICTURE, and a
  /// position that ran on its own would decide when the run ends.
  @override
  double? get positionSeconds => 0;

  @override
  bool get ended => false;
}
