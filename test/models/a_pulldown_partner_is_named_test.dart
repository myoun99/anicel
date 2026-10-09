import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/project_frame_rate.dart';

/// 🗣️import-movie-fps-mismatch-notice (유저 10-06: 「알리는게 좋겠어」 ·
/// 「셋다 맞고」): a movie at the project's pulldown partner — 23.976↔24,
/// 29.97↔30, 59.94↔60 — is named on import; any other difference is not.
void main() {
  const fps24 = ProjectFrameRate.fps24;
  const ntsc24 = ProjectFrameRate.ntsc(24);

  test('a movie at the other half of the pair is named, either way round, '
      'for every pair', () {
    expect(
      pulldownPartnerOf(fps24, (numerator: 24000, denominator: 1001)),
      ntsc24,
    );
    expect(pulldownPartnerOf(ntsc24, (numerator: 24, denominator: 1)), fps24);
    expect(
      pulldownPartnerOf(
        const ProjectFrameRate.integer(30),
        (numerator: 30000, denominator: 1001),
      ),
      const ProjectFrameRate.ntsc(30),
    );
    expect(
      pulldownPartnerOf(
        const ProjectFrameRate.ntsc(60),
        (numerator: 60, denominator: 1),
      ),
      const ProjectFrameRate.integer(60),
    );
  });

  test('a decoder\'s rounder spelling of 23.976 is 23.976', () {
    for (final movie in [
      (numerator: 2997, denominator: 125),
      (numerator: 23976, denominator: 1000),
    ]) {
      expect(pulldownPartnerOf(fps24, movie), ntsc24, reason: '$movie');
    }
    expect(
      pulldownPartnerOf(
        const ProjectFrameRate.integer(30),
        (numerator: 2997, denominator: 100),
      ),
      const ProjectFrameRate.ntsc(30),
    );
  });

  test('the same rate, another family, and a rate nowhere near are not '
      'named', () {
    for (final movie in [
      (numerator: 24, denominator: 1),
      (numerator: 2400, denominator: 100),
      (numerator: 30000, denominator: 1001),
      (numerator: 25, denominator: 1),
      (numerator: 23999, denominator: 1000),
      (numerator: 0, denominator: 1),
      (numerator: 24, denominator: 0),
    ]) {
      expect(pulldownPartnerOf(fps24, movie), isNull, reason: '$movie');
    }
  });

  test('a project at a rate of its own has no partner', () {
    const ownRate = ProjectFrameRate(
      numerator: 25,
      denominator: 2,
      countingBase: 12,
    );
    expect(
      pulldownPartnerOf(ownRate, (numerator: 12, denominator: 1)),
      isNull,
    );
  });

  test('a sound\'s frame keeps its moment across the change — the nearest '
      'frame that begins there', () {
    int at(int frame, ProjectFrameRate from, ProjectFrameRate to) =>
        frameAtSameTime(frame, from: from, to: to);

    expect(at(0, fps24, ntsc24), 0);
    expect(at(1000, fps24, ntsc24), 999, reason: '999.0009 → 999');
    expect(at(500, fps24, ntsc24), 500, reason: '499.5005 → 500');
    expect(at(1600, fps24, ntsc24), 1598, reason: '1598.4016 → 1598');
    expect(at(999, ntsc24, fps24), 1000, reason: '999.999 → 1000');
    expect(at(24, fps24, fps24), 24);
  });
}
