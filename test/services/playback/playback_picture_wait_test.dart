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

  test('the default is every picture', () {
    expect(defaultPlaybackMode, PlaybackMode.everyPicture);
  });

  test('skipping frames, the clock never stands — whatever is there', () {
    mode = PlaybackMode.skipFrames;
    final w = wait()..runBegins();
    expect(w.holds(0), isFalse, reason: 'nothing is there, and it goes');
    there.add(0);
    expect(w.holds(0), isFalse);
  });

  test('showing every picture, the clock stands on a frame until its '
      'picture is there — and no longer', () {
    final w = wait()..runBegins();
    expect(w.holds(3), isTrue);

    there.add(3);
    expect(
      w.holds(3),
      isFalse,
      reason: 'its picture is all it waits for: what lies ahead may be empty',
    );
    expect(w.holds(4), isTrue, reason: 'each frame answers for itself');
  });

  test('rendering first, a run that begins stands until what lies ahead is '
      'filled — even on a frame whose picture is there', () {
    mode = PlaybackMode.renderFirst;
    there.add(0);
    final w = wait()..runBegins();
    expect(w.holds(0), isTrue, reason: 'it fills before it goes');

    filled = true;
    expect(w.holds(0), isFalse);
  });

  test('rendering first, a filled run goes on over every frame that is '
      'there, and stands again where one is not — until it is filled again, '
      'not merely until that picture comes', () {
    mode = PlaybackMode.renderFirst;
    there.addAll([0, 1]);
    filled = true;
    final w = wait()..runBegins();
    expect(w.holds(0), isFalse);

    // The window slid on and is filling again behind the scenes.
    filled = false;
    expect(w.holds(1), isFalse, reason: 'it is there, and the run is going');

    expect(w.holds(2), isTrue, reason: 'the playhead outran the window');
    there.add(2);
    expect(
      w.holds(2),
      isTrue,
      reason: 'one picture is a stutter: it waits for the fill',
    );
    filled = true;
    expect(w.holds(2), isFalse);
  });

  test('rendering first, being filled without the frame under the playhead '
      'is not enough to go', () {
    mode = PlaybackMode.renderFirst;
    filled = true;
    final w = wait()..runBegins();
    expect(w.holds(0), isTrue);
  });

  test('a run nobody makes pictures for never waits — it would wait for '
      'good', () {
    followed = false;
    for (final each in PlaybackMode.values) {
      mode = each;
      expect((wait()..runBegins()).holds(0), isFalse, reason: each.name);
    }
  });

  test('the mode is read as it stands: changed under a run that waits, the '
      'run need wait no longer', () {
    final w = wait()..runBegins();
    expect(w.holds(0), isTrue);
    mode = PlaybackMode.skipFrames;
    expect(w.holds(0), isFalse);
  });
}
