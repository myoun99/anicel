import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/playback_rig.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three things the playback rig owes the session — that it is wired the
/// moment the session exists, that it goes down with it, and that the
/// preview quality is a setting rather than a field anyone may poke —
/// and none of them had an observer before this file: every body here
/// could be emptied and every suite stayed green.
/// The collaborator under test — named so `tool/mutation_run.dart` has a
/// suite to run for it.
PlaybackRig playbackRigOf(EditorSessionManager session) => session.playbackRig;

void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });

  tearDown(() => session.dispose());

  test('the transport is ATTACHED: the controller holds an audio clock to '
      'read, so a run can ride the samples instead of the wall clock', () {
    expect(
      session.playbackRig.playback.resolveAudioClock,
      isNotNull,
      reason:
          'attach() is what hands the controller that clock. Without it '
          'every run derives the picture from the wall clock and the '
          'device transport can never carry one',
    );
  });

  test('the session going down takes the rig with it — the transport stops '
      'being usable, which is what says nothing is still listening', () {
    final own = EditorSessionManager(initialProject: createDefaultProject());
    final transport = own.playbackRig.playback;
    own.dispose();
    expect(
      () => transport.globalFrameIndexListenable.addListener(() {}),
      throwsA(isA<FlutterError>()),
      reason:
          'a transport the session forgot to dispose keeps its ticker and '
          'every listener alive for the life of the app',
    );
  });

  test('the preview quality is a setting: a new one lands and announces, '
      'the same one changes nothing', () {
    var notices = 0;
    session.addListener(() => notices += 1);

    final rig = playbackRigOf(session);
    final other = rig.playbackQuality == PlaybackQuality.full
        ? PlaybackQuality.half
        : PlaybackQuality.full;
    rig.setPlaybackQuality(other);
    expect(rig.playbackQuality, other);
    expect(
      notices,
      greaterThan(0),
      reason: 'the canvas and the ruler both read the quality',
    );

    final after = notices;
    rig.setPlaybackQuality(other);
    expect(
      notices,
      after,
      reason:
          'setting the quality it already has is not an event — it would '
          're-warm the whole active cut for nothing',
    );
  });
}
