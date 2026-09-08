// EXPORT-AUDIO ③: THE SESSION'S AUDIO-RATE SETTER HAS A RANGE, AND IT IS
// THE SETTER'S — NOT THE MODEL'S.
//
// The model already falls back to the default for nonsense (see
// test/models/project_audio_sample_rate_test.dart). This is the OTHER
// guard: 8000..192000 at the session verb, so a rate outside it never
// becomes an undo step at all. Nothing tested it until the cluster moved
// into [ProjectAudio] (G3, 2026-09-07) and a mutant walked straight
// through the ceiling.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_audio.dart';

void main() {
  late EditorSessionManager session;

  setUp(() {
    session = EditorSessionManager(initialProject: createDefaultProject());
  });
  tearDown(() => session.dispose());

  ProjectAudio audioSettings() => session.projectAudio;
  int rate() => audioSettings().projectAudioSampleRate;

  test('a rate inside the range lands as one undo step', () {
    final before = rate();
    audioSettings().setProjectAudioSampleRate(44100);
    expect(rate(), 44100);
    expect(session.canUndo, isTrue);
    session.undo();
    expect(rate(), before);
  });

  test('the floor and the ceiling are exact, and outside them nothing '
      'happens — not even an undo step', () {
    // The two ends themselves are ACCEPTED.
    audioSettings().setProjectAudioSampleRate(8000);
    expect(rate(), 8000);
    audioSettings().setProjectAudioSampleRate(192000);
    expect(rate(), 192000);

    // One step outside either end is refused, and the rate stays where the
    // last accepted call left it.
    audioSettings().setProjectAudioSampleRate(7999);
    expect(rate(), 192000);
    audioSettings().setProjectAudioSampleRate(192001);
    expect(rate(), 192000);
    audioSettings().setProjectAudioSampleRate(0);
    expect(rate(), 192000);
  });

  test('setting the rate it already has spends no undo step', () {
    final before = rate();
    audioSettings().setProjectAudioSampleRate(before);
    expect(
      session.canUndo,
      isFalse,
      reason: 'a no-op rate change must not stack an entry the user has to '
          'undo twice past',
    );
  });
}
