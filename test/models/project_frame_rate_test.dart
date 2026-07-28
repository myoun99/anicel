import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';

void main() {
  group('the fraction', () {
    test('NTSC rates are the exact ratio, not a decimal', () {
      const rate = ProjectFrameRate.ntsc(24);
      expect(rate.numerator, 24000);
      expect(rate.denominator, 1001);
      expect(rate.countingBase, 24, reason: 'the sheet still counts 24');
      expect(rate.isInteger, isFalse);
      expect(rate.approximateFps, closeTo(23.976, 0.001));
    });

    test('counting base is what integer-frame surfaces read', () {
      // The point of the split: 23.976 and 24 COUNT identically, so the
      // grid, the 6f lines and the sheet rows are untouched by the rate.
      expect(
        const ProjectFrameRate.ntsc(24).countingBase,
        const ProjectFrameRate.integer(24).countingBase,
      );
      expect(const ProjectFrameRate.ntsc(30).countingBase, 30);
    });

    test('labels read the way an editor writes them', () {
      expect(const ProjectFrameRate.integer(24).label, '24 fps');
      expect(const ProjectFrameRate.ntsc(24).label, '23.976 fps');
      expect(const ProjectFrameRate.ntsc(30).label, '29.97 fps');
      expect(const ProjectFrameRate.ntsc(60).label, '59.94 fps');
    });

    test('ffmpeg gets the fraction it understands', () {
      expect(const ProjectFrameRate.integer(24).ffmpegRateArgument, '24');
      expect(
        const ProjectFrameRate.ntsc(24).ffmpegRateArgument,
        '24000/1001',
      );
    });
  });

  group('frames to samples', () {
    test('is exact at 48kHz', () {
      const rate = ProjectFrameRate.integer(24);
      expect(rate.frameToSample(0, 48000), 0);
      expect(rate.frameToSample(1, 48000), 2000);
      expect(rate.frameToSample(24, 48000), 48000);
    });

    test('does not drift across a three-hour timeline', () {
      // The mixer's core promise: clip starts land within ±1 sample no
      // matter how far into the movie they are. A double would have lost
      // whole samples by here.
      const rate = ProjectFrameRate.ntsc(24);
      const sampleRate = 48000;
      const threeHoursOfFrames = 24 * 60 * 60 * 3;
      final sample = rate.frameToSample(threeHoursOfFrames, sampleRate);
      // frame × 48000 × 1001 ÷ 24000, computed independently.
      expect(sample, threeHoursOfFrames * sampleRate * 1001 ~/ 24000);
      // And the round trip lands back on the same frame.
      expect(rate.sampleToFrame(sample, sampleRate), threeHoursOfFrames);
    });

    test('a frame start never lands inside the previous frame', () {
      // At 29.97 frame 1 begins at sample 1601.6. Truncating to 1601 puts
      // the clip a sample early — inside frame 0 — and the audio clock
      // would then report frame 0 for a position we scheduled as frame 1.
      const rate = ProjectFrameRate.ntsc(30);
      expect(rate.frameToSample(1, 48000), 1602);
      expect(rate.sampleToFrame(1602, 48000), 1);
      expect(
        rate.sampleToFrame(1601, 48000),
        0,
        reason: 'sample 1601 genuinely still belongs to frame 0',
      );
    });

    test('round trips every frame of a long run', () {
      for (final rate in const [
        ProjectFrameRate.integer(24),
        ProjectFrameRate.ntsc(24),
        ProjectFrameRate.integer(30),
        ProjectFrameRate.ntsc(30),
      ]) {
        for (final frame in const [0, 1, 999, 100000, 5184000]) {
          expect(
            rate.sampleToFrame(rate.frameToSample(frame, 48000), 48000),
            frame,
            reason: '$rate lost frame $frame in the sample round trip',
          );
        }
      }
    });
  });

  group('seconds to frames', () {
    test('an exactly-N-second file does not gain a frame of silence', () {
      // The old `.ceil()` on `2.0 * 24` saw 48.000000000000004 and
      // invented a 49th frame. From an exact ratio there is nothing to
      // round.
      const rate = ProjectFrameRate.integer(24);
      // 2 seconds expressed as 80 buckets at 40 buckets/second.
      expect(rate.framesCoveringExactSeconds(80, 40), 48);
      expect(rate.framesCoveringSeconds(2.0), 48);
    });

    test('a partial frame still rounds up — audio is never truncated', () {
      const rate = ProjectFrameRate.integer(24);
      // 2.01 seconds = 48.24 frames: the 49th frame has audio in it.
      expect(rate.framesCoveringSeconds(2.01), 49);
      // 81 buckets at 40/s = 2.025s = 48.6 frames.
      expect(rate.framesCoveringExactSeconds(81, 40), 49);
    });

    test('float noise does not buy a frame the file does not have', () {
      const rate = ProjectFrameRate.integer(24);
      expect(rate.framesCoveringSeconds(1.0), 24);
      expect(rate.framesCoveringSeconds(0.5), 12);
      expect(rate.framesCoveringSeconds(3.0), 72);
    });

    test('empty and nonsense inputs stay at zero', () {
      const rate = ProjectFrameRate.integer(24);
      expect(rate.framesCoveringSeconds(0), 0);
      expect(rate.framesCoveringSeconds(-1), 0);
      expect(rate.framesCoveringSeconds(double.nan), 0);
      expect(rate.framesCoveringExactSeconds(10, 0), 0);
    });
  });

  group('frames to time', () {
    test('frame starts are exact at 24', () {
      const rate = ProjectFrameRate.integer(24);
      expect(rate.frameStart(0), Duration.zero);
      expect(rate.frameStart(24), const Duration(seconds: 1));
      expect(rate.frameStartSeconds(12), 0.5);
    });

    test('an NTSC frame start carries its 1001/1000 stretch', () {
      const rate = ProjectFrameRate.ntsc(24);
      // 24 frames of 23.976 take 1.001 seconds, exactly.
      expect(rate.frameStart(24), const Duration(milliseconds: 1001));
      expect(rate.frameStartSeconds(24), closeTo(1.001, 1e-9));
    });

    test('negative and zero elapsed clamp to frame 0', () {
      const rate = ProjectFrameRate.integer(24);
      expect(rate.frameAtElapsed(Duration.zero), 0);
      expect(rate.frameAtElapsed(const Duration(seconds: -5)), 0);
    });
  });

  group('serialization', () {
    test('round trips through JSON', () {
      for (final rate in ProjectFrameRate.presets) {
        expect(
          ProjectFrameRate.fromJson(rate.toJson()),
          rate,
          reason: '$rate did not survive a JSON round trip',
        );
      }
    });

    test('a file carrying only the fraction recovers its counting base', () {
      // Hand-edited or older files may lack the explicit base; every
      // real-world rate rounds to it.
      expect(
        ProjectFrameRate.fromJson(const {
          'numerator': 24000,
          'denominator': 1001,
        }),
        const ProjectFrameRate.ntsc(24),
      );
      expect(
        ProjectFrameRate.fromJson(const {'numerator': 30, 'denominator': 1}),
        const ProjectFrameRate.integer(30),
      );
    });
  });

  test('presets cover the standard rates and carry no duplicates', () {
    expect(ProjectFrameRate.presets.toSet(), hasLength(
      ProjectFrameRate.presets.length,
    ));
    expect(
      ProjectFrameRate.presets,
      containsAll(const [
        ProjectFrameRate.integer(24),
        ProjectFrameRate.ntsc(24),
        ProjectFrameRate.integer(30),
        ProjectFrameRate.ntsc(30),
      ]),
    );
  });
}
