import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';

void main() {
  group('audioMixScheduleFrom', () {
    test('converts frames with the rounding-UP half of the round-trip pair '
        '(29.97: frame 1 starts at sample 1601.6 → 1602)', () {
      const ntsc = ProjectFrameRate(
        numerator: 30000,
        denominator: 1001,
        countingBase: 30,
      );
      final converted = audioMixScheduleFrom(
        schedule: const [
          ScheduledAudioClip(
            filePath: 'a.wav',
            startFrame: 1,
            endFrameExclusive: 2,
          ),
        ],
        rate: ntsc,
        sampleRate: 48000,
      );
      expect(converted.clips.single.startSample, 1602);
      expect(converted.clips.single.endSample, 3204);
      // The clock's floor pairing reads back the scheduled frame exactly.
      expect(ntsc.sampleToFrame(1602, 48000), 1);
      expect(ntsc.sampleToFrame(1601, 48000), 0);
    });

    test('carries trim, gain and fades into sample units', () {
      const rate = ProjectFrameRate(
        numerator: 24,
        denominator: 1,
        countingBase: 24,
      );
      final converted = audioMixScheduleFrom(
        schedule: const [
          ScheduledAudioClip(
            filePath: 'a.wav',
            startFrame: 10,
            endFrameExclusive: 34,
            offsetFrames: 5,
            gain: 0.5,
            fadeInFrames: 2,
            fadeOutFrames: 3,
          ),
        ],
        rate: rate,
        sampleRate: 48000,
      );
      final clip = converted.clips.single;
      expect(clip.startSample, 10 * 2000);
      expect(clip.endSample, 34 * 2000);
      expect(clip.sourceOffset, 5 * 2000);
      expect(clip.gain, 0.5);
      expect(clip.fadeInSamples, 2 * 2000);
      expect(clip.fadeOutSamples, 3 * 2000);
    });

    test('shares one source per distinct path, in first-appearance order', () {
      const rate = ProjectFrameRate(
        numerator: 24,
        denominator: 1,
        countingBase: 24,
      );
      final converted = audioMixScheduleFrom(
        schedule: const [
          ScheduledAudioClip(filePath: 'b.wav', startFrame: 0, endFrameExclusive: 1),
          ScheduledAudioClip(filePath: 'a.wav', startFrame: 1, endFrameExclusive: 2),
          ScheduledAudioClip(filePath: 'b.wav', startFrame: 2, endFrameExclusive: 3),
        ],
        rate: rate,
        sampleRate: 48000,
      );
      expect(converted.sourcePaths, ['b.wav', 'a.wav']);
      expect(
        converted.clips.map((clip) => clip.sourceIndex).toList(),
        [0, 1, 0],
      );
    });
  });
}
