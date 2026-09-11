import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/movie_clock.dart';
import 'package:anicel/src/models/project_frame_rate.dart';

/// 「영상의 시간은 소리와 같은 시계로」 (유저 2026-09-11): a project frame is
/// a TIME, and the movie shows the frame that holds it — never frame for
/// frame, and a pulldown pull moves the picture exactly as it moves sound.
void main() {
  const oneToOne = (numerator: 1, denominator: 1);
  const movie24 = (numerator: 24, denominator: 1);
  const movie23976 = (numerator: 24000, denominator: 1001);

  test('the same rate on both sides is frame for frame', () {
    const clock = MovieClock(
      projectRate: ProjectFrameRate.fps24,
      audioSpeed: oneToOne,
      movieRate: movie24,
    );
    expect([for (var n = 0; n < 5; n++) clock.movieFrameAt(n)], [
      0,
      1,
      2,
      3,
      4,
    ]);
    expect(clock.projectFramesCovering(720), 720, reason: '30 s = 720 cels');
  });

  test('a 23.976 take in a 24 project keeps REAL time — one frame behind '
      'after 1001 frames, the way its soundtrack is', () {
    const clock = MovieClock(
      projectRate: ProjectFrameRate.fps24,
      audioSpeed: oneToOne,
      movieRate: movie23976,
    );
    expect(clock.movieFrameAt(24), 23, reason: 'at 1.000 s frame 24 is not up');
    expect(clock.movieFrameAt(1001), 1000);
    expect(clock.projectFramesCovering(1000), 1001);
  });

  test('with the pull a 23.976→24 change applied, the take is frame for '
      'frame again — the picture moves exactly as the sound did', () {
    final pull = audioPullBetween(
      const ProjectFrameRate.ntsc(24),
      ProjectFrameRate.fps24,
    )!;
    final clock = MovieClock(
      projectRate: ProjectFrameRate.fps24,
      audioSpeed: pull,
      movieRate: movie23976,
    );
    expect([for (final n in [1, 24, 1001, 86400]) clock.movieFrameAt(n)], [
      1,
      24,
      1001,
      86400,
    ]);
    expect(clock.projectFramesCovering(1000), 1000);
  });

  test('a slower movie HOLDS and a faster one SKIPS', () {
    const twelve = MovieClock(
      projectRate: ProjectFrameRate.fps24,
      audioSpeed: oneToOne,
      movieRate: (numerator: 12, denominator: 1),
    );
    expect([for (var n = 0; n < 5; n++) twelve.movieFrameAt(n)], [
      0,
      0,
      1,
      1,
      2,
    ]);
    const thirty = MovieClock(
      projectRate: ProjectFrameRate.fps24,
      audioSpeed: oneToOne,
      movieRate: (numerator: 30, denominator: 1),
    );
    expect([for (var n = 0; n < 5; n++) thirty.movieFrameAt(n)], [
      0,
      1,
      2,
      3,
      5,
    ]);
    expect(twelve.projectFramesCovering(3), 6);
    expect(thirty.projectFramesCovering(5), 4);
  });

  test('before the start, and on a rate that measures nothing, it is frame 0',
      () {
    const clock = MovieClock(
      projectRate: ProjectFrameRate.fps24,
      audioSpeed: oneToOne,
      movieRate: (numerator: 0, denominator: 1),
    );
    expect(clock.movieFrameAt(-3), 0);
    expect(clock.movieFrameAt(10), 0);
    expect(clock.projectFramesCovering(10), 0);
  });
}
