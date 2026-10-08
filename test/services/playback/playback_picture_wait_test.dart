import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/services/playback/playback_picture_wait.dart';

/// THE THREE SETTINGS OF ONE MECHANISM (유저 2026-10-08: 「세개 두면
/// 좋을거같긴하고」 · 「좋아 통일할거 통일하면서 권장대로가자. 기본값
/// 모든그림.」): how long a run's clock stands when the playhead reaches a
/// frame whose picture is not made — not at all, until that picture is, or
/// until everything ahead of it is.
void main() {
  var mode = PlaybackMode.everyPicture;

  /// The frames whose pictures are there.
  final there = <int>{};

  /// Whether a warmer follows the run at all.
  var followed = true;

  /// Whether everything ahead of the playhead is made, or no more fits.
  var filled = false;

  setUp(() {
    mode = PlaybackMode.everyPicture;
    there.clear();
    followed = true;
    filled = false;
  });

  PlaybackPictureWait wait() => PlaybackPictureWait(
    mode: () => mode,
    pictureIsThere: (frame) => followed ? there.contains(frame) : null,
    aheadIsFilled: () => filled,
  );

  /// The run was PUT on [frame]: play pressed there, the ruler dragged there.
  bool put(PlaybackPictureWait w, int frame) => w.holds(frame, placed: true);

  /// The run's clock reached [frame], or looks again at the frame it is on.
  bool reached(PlaybackPictureWait w, int frame) =>
      w.holds(frame, placed: false);

  test('the default is every picture', () {
    expect(defaultPlaybackMode, PlaybackMode.everyPicture);
  });

  test('skipping frames, the clock never stands — whatever is there, and '
      'however the run came to the frame', () {
    mode = PlaybackMode.skipFrames;
    final w = wait();
    expect(put(w, 0), isFalse, reason: 'nothing is there, and it goes');
    expect(reached(w, 1), isFalse);
    there.add(0);
    expect(put(w, 0), isFalse);
  });

  test('showing every picture, the clock stands on a frame until its '
      'picture is there — and no longer', () {
    final w = wait();
    expect(put(w, 3), isTrue);

    there.add(3);
    expect(
      reached(w, 3),
      isFalse,
      reason: 'its picture is all it waits for: what lies ahead may be empty',
    );
    expect(reached(w, 4), isTrue, reason: 'each frame answers for itself');
    expect(
      put(w, 3),
      isFalse,
      reason: 'put on a frame that is there, it goes at once',
    );
  });

  test('rendering first, a run that is put somewhere stands until what lies '
      'ahead is filled — even on a frame whose picture is there', () {
    mode = PlaybackMode.renderFirst;
    there.add(0);
    final w = wait();
    expect(put(w, 0), isTrue, reason: 'it fills before it goes');
    expect(reached(w, 0), isTrue, reason: 'looking again, still filling');

    filled = true;
    expect(reached(w, 0), isFalse);
  });

  test('🚨rendering first, being filled is not asked of a run that was just '
      'put: what was filled was filled for where it stood before', () {
    mode = PlaybackMode.renderFirst;
    there.addAll([0, 5]);
    filled = true;
    final w = wait();
    expect(put(w, 0), isTrue);
    expect(reached(w, 0), isFalse, reason: '⛔premise: it goes');

    // The ruler is dragged on: the answer still standing is the old place's.
    expect(put(w, 5), isTrue);
    expect(reached(w, 5), isFalse, reason: 'asked again, it is believed');
  });

  test('rendering first, a filled run goes on over every frame that is '
      'there, and stands again where one is not — until it is filled again, '
      'not merely until that picture comes', () {
    mode = PlaybackMode.renderFirst;
    there.addAll([0, 1]);
    filled = true;
    final w = wait();
    put(w, 0);
    expect(reached(w, 0), isFalse);

    // The window slid on and is filling again behind the scenes.
    filled = false;
    expect(
      reached(w, 1),
      isFalse,
      reason: 'it is there, and the run is going',
    );

    expect(reached(w, 2), isTrue, reason: 'the playhead outran the window');
    there.add(2);
    expect(
      reached(w, 2),
      isTrue,
      reason: 'one picture is a stutter: it waits for the fill',
    );
    filled = true;
    expect(reached(w, 2), isFalse);
  });

  test('rendering first, being filled without the frame under the playhead '
      'is not enough to go', () {
    mode = PlaybackMode.renderFirst;
    filled = true;
    final w = wait();
    expect(put(w, 0), isTrue);
    expect(reached(w, 0), isTrue);
  });

  test('a run nobody makes pictures for never waits — it would wait for '
      'good', () {
    followed = false;
    for (final each in PlaybackMode.values) {
      mode = each;
      expect(put(wait(), 0), isFalse, reason: each.name);
      expect(reached(wait(), 0), isFalse, reason: each.name);
    }
  });

  test('the mode is read as it stands: changed under a run that waits, the '
      'run need wait no longer', () {
    final w = wait();
    expect(put(w, 0), isTrue);
    mode = PlaybackMode.skipFrames;
    expect(reached(w, 0), isFalse);
  });

  test('the fill is render-first\'s alone: left under a run that was '
      'filling and picked again, the run is not found still filling', () {
    mode = PlaybackMode.renderFirst;
    there.add(0);
    final w = wait();
    expect(put(w, 0), isTrue, reason: '⛔premise: it is filling');

    mode = PlaybackMode.everyPicture;
    expect(reached(w, 0), isFalse, reason: '⛔premise: its picture is there');

    mode = PlaybackMode.renderFirst;
    expect(
      reached(w, 0),
      isFalse,
      reason: 'a run that is going goes on until a frame is not there',
    );
  });
}
