

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';

import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';



import 'package:anicel/src/services/media/video_decode_worker.dart';

import '../../helpers/fake_video_backend.dart';
import '../../helpers/recording_viewer_sound.dart';
import '../../helpers/settle_async.dart';

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
  late RecordingViewerSound sound;
  var opens = 0;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
    slot = MediaViewerSlot();
    sound = RecordingViewerSound(session.audioConformStore);
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
              position: slot.position,
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

  /// A run's tick at 24fps — the pumped time between real-time rounds, so
  /// the run moves on while the decoder works ([settleAsync]).
  const tick = Duration(milliseconds: 42);

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

  testWidgets('🚨a buffer that runs dry HOLDS the sound, and refilling '
      'brings BOTH back', (tester) async {
    // Nothing past the first frame will decode: the cushion cannot fill.
    final fake = await openMovie(tester, holdFrom: 1);
    await pressPlay(tester);
    expect(sound.holds, 0, reason: 'fixture: nothing has run dry yet');

    // ⚠️[settleAsync] here too, and that is not a formality: it gives the
    // decodes REAL time to land, so the frames that never arrive are the
    // ones the backend is holding rather than ones a pumped clock could
    // never have delivered anyway. Pumping alone would park this viewer
    // whatever the backend did, and the assertion below would be measuring
    // the bench instead of the law.
    await settleAsync(
      tester,
      () => sound.holds > 0,
      attempts: 150,
      step: tick,
    );

    expect(
      sound.holds,
      greaterThan(0),
      reason: 'the sound parks WITH the picture — 「로드할때까지 멈춰있어야지」 '
          'reaches the soundtrack, or the picture would owe it dropped '
          'frames later',
    );

    // 🚨AND IT STAYS PARKED WHILE THE FRAMES STAY HELD. ⛔The first tick of
    // ANY run parks — the cushion has not filled yet — so asserting a park
    // right after pressing play measures nothing about the buffer. What
    // separates 「waiting for these frames」 from 「waiting once, always」 is
    // that real time passes here and the playhead still does not move.
    await settleAsync(tester, () => slot.position.value > 0, step: tick);
    expect(
      slot.position.value,
      0,
      reason: 'held frames, held playhead — it did not walk past a frame '
          'that is not there',
    );

    // 🚨★★★**AND IT COMES BACK — TOGETHER.** The cushion refills, the sound
    // resumes from where the picture stands, and the playhead moves again.
    //
    // ⚠️[settleAsync], not more pumping: the refill is an image decode, and
    // a pumped clock never performs one. See that helper for the round this
    // cost.
    fake.held.clear();
    await settleAsync(
      tester,
      () => sound.resumes > 0,
      attempts: 150,
      step: tick,
    );

    expect(sound.resumes, greaterThan(0), reason: 'the sound picked back up');
    expect(
      slot.position.value,
      greaterThan(0),
      reason: 'and the picture moved WITH it — 「로드할때까지 멈춰있어야지」 is '
          'a WAIT, and a wait that never ends is not the law either',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('media-viewer-play-button')),
    );
    await tester.pump();
  });

  testWidgets('🚨a frame it cannot read is asked for ONCE PER TICK, not as '
      'fast as the decoder can refuse it', (tester) async {
    // 🪦Measured before the fix, with this exact fixture: `asked` came back
    // `[0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]` — eleven asks for one frame
    // across three ticks. Nothing was throttling it. The failure arm cleared
    // its own marker inside a `setState`, the rebuild asked for the same
    // page again, and that failed again: a loop whose speed was set by how
    // quickly the decoder could say no. On a corrupt frame or a slow decoder
    // that is a pegged CPU under a picture standing still — worst exactly
    // where it can least be afforded ([[old-device-support-policy]]).
    final fake = await openMovie(tester, holdFrom: 1);
    await pressPlay(tester);

    // 🪦FIRST GET TO THE STATE BEING MEASURED, and only with REAL time. A
    // first attempt counted asks straight after the press and measured
    // `asked == [0]` — the read-ahead had not reached the held frame at all,
    // because frame 0's own decode cannot COMPLETE inside the fake-async
    // zone and its marker therefore still said 「asking」. That is the trap
    // [settleAsync]'s header is about, walked into one more time:
    // the number would have been the bench's, not the viewer's.
    await settleAsync(
      tester,
      () => fake.asked.contains(1),
      attempts: 150,
      step: tick,
    );
    expect(
      fake.asked,
      contains(1),
      reason: 'fixture: the read-ahead has to actually reach the held frame '
          'before its retry rate can mean anything',
    );

    final before = fake.asked.length;
    // Ten ticks of the movie's own clock. The fake clock only moves on
    // `pump`, so this is EXACTLY ten however long the real waits take.
    const ticks = 10;
    for (var tick = 0; tick < ticks; tick += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 42));
    }

    final asks = fake.asked.length - before;
    expect(
      asks,
      lessThanOrEqualTo(ticks + 1),
      reason: 'the play tick is the retry clock — a frame that is not there '
          'is asked for at the rate the movie needs it and no faster '
          '(measured $asks asks over $ticks ticks: ${fake.asked})',
    );
    // ⛔And not zero either: 「로드할때까지 멈춰있어야지」 is a WAIT, so it has
    // to keep asking. A viewer that gave up would sail through the bound
    // above — this is the half that keeps the resume below possible.
    expect(asks, greaterThan(0), reason: 'it is still trying');
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
