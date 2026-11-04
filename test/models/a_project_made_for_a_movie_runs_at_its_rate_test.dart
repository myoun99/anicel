import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';

/// 🗣️I-156-Q2 (유저 2026-11-04: 「그 동영상의 fps」 · 「아무튼 fps기준으로
/// 정해짐」): a movie brought in as a NEW PROJECT gives the project its rate.
void main() {
  test('a movie at an NTSC rate makes an NTSC project, however its decoder '
      'spells it', () {
    for (final (movie, rate) in [
      ((numerator: 24000, denominator: 1001), const ProjectFrameRate.ntsc(24)),
      ((numerator: 2997, denominator: 125), const ProjectFrameRate.ntsc(24)),
      ((numerator: 23976, denominator: 1000), const ProjectFrameRate.ntsc(24)),
      ((numerator: 30000, denominator: 1001), const ProjectFrameRate.ntsc(30)),
      ((numerator: 60000, denominator: 1001), const ProjectFrameRate.ntsc(60)),
    ]) {
      expect(projectRateOfMovie(movie), rate, reason: '$movie');
    }
  });

  test('a movie at a whole rate makes a project at that rate — one the '
      'presets do not list too', () {
    for (final (movie, fps) in [
      ((numerator: 24, denominator: 1), 24),
      ((numerator: 2400, denominator: 100), 24),
      ((numerator: 25, denominator: 1), 25),
      ((numerator: 30, denominator: 1), 30),
      ((numerator: 120, denominator: 1), 120),
    ]) {
      expect(
        projectRateOfMovie(movie),
        ProjectFrameRate.integer(fps),
        reason: '$movie',
      );
    }
  });

  test('a rate that is neither takes the whole rate nearest it', () {
    expect(
      projectRateOfMovie((numerator: 239, denominator: 10)),
      ProjectFrameRate.fps24,
    );
  });

  test('a movie that names no rate leaves the new project its own', () {
    for (final movie in [
      (numerator: 0, denominator: 1),
      (numerator: 24, denominator: 0),
      (numerator: 1, denominator: 3),
    ]) {
      expect(projectRateOfMovie(movie), isNull, reason: '$movie');
    }
  });
}
