import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_audio_spans.dart';
import 'package:anicel/src/models/se_sound.dart';
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

    test('carries trim, gain and the volume line into sample units', () {
      const rate = ProjectFrameRate.fps24;
      final converted = audioMixScheduleFrom(
        schedule: const [
          ScheduledAudioClip(
            filePath: 'a.wav',
            startFrame: 10,
            endFrameExclusive: 34,
            offsetFrames: 5,
            gain: 0.5,
            volume: [(frame: 0, gain: 0.0), (frame: 3, gain: 0.8)],
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
      expect([for (final point in clip.envelope) point.sample], [0, 3 * 2000]);
      expect([for (final point in clip.envelope) point.gain], [0.0, 0.8]);
    });

    test('shares one source per distinct path, in first-appearance order', () {
      const rate = ProjectFrameRate.fps24;
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

  // 🗣️I-145-Q1 (유저 2026-10-30): 「따로 한 값 — 두 입구」 — the row's
  // Total over its keys, a pro tool's fader over its track keys.
  test('a span carries the clip\'s gain times the row\'s Total, and the '
      'keyed volume beside it', () {
    final span = SeAudioSpan(
      clip: AudioClip(
        filePath: 'a.wav',
        frameId: const FrameId('f'),
        gain: 1.5,
      ),
      clipIndex: 0,
      startFrame: 2,
      lengthFrames: 8,
    );
    final scheduled = ScheduledAudioClip.ofSpan(
      span,
      startFrame: 2,
      endFrameExclusive: 10,
      clippedLead: 0,
      sound: SeSound(
        totalVolume: 0.5,
        volume: PropertyTrack<double>(
          keys: {2: const PropertyKey(0.0), 6: const PropertyKey(1.0)},
        ),
      ),
    );
    expect(scheduled.gain, 0.75);
    expect(scheduled.volume, [
      (frame: 0, gain: 0.0),
      (frame: 4, gain: 1.0),
      (frame: 8, gain: 1.0),
    ], reason: 'the keys stay the keys');
  });
}
