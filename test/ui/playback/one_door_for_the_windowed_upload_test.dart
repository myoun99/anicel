import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';
import 'package:anicel/src/ui/playback/audio_windowed_upload.dart';

/// The one door the transport and the scrubber both go through, so
/// streamed playback and streamed scrubbing drive the device by one upload,
/// each over its own reach. Nothing named it (2026-09-05).
///
/// 🚨ANYTHING BUT [OutputArmed] means "nothing was uploaded", and the
/// caller's contract hangs on it: no mix held, no device, or a device that
/// rejected the schedule answer [OutputRefused], a source still landing
/// [OutputComing], and the caller LEAVES ANY OLD SCHEDULE PLAYING rather
/// than cutting the sound to silence. The window must not move either — a
/// centre that advanced on a failed upload would tell the next poll there
/// was nothing to re-center. ↩️All of them answered false
/// (playback-waits-for-its-sound: a run waits for what is coming, and
/// plays without what is refused).
void main() {
  AudioConformStore store() {
    final conform = AudioConformStore(resolveConformPath: (_) => null);
    addTearDown(conform.dispose);
    return conform;
  }

  AudioStreamingWindow windowHolding(AudioMixSchedule? mix) =>
      AudioStreamingWindow()..mix = mix;

  OutputArm upload(AudioStreamingWindow window, {int centerSample = 0}) =>
      window.upload(
        // ⛔No device is the case this bench can drive: the native one needs a
        // device run, and the point being pinned is what happens WITHOUT one.
        device: null,
        conformStore: store(),
        deviceRate: 48000,
        centerSample: centerSample,
      );

  test('🚨no device is REFUSED — the caller keeps the schedule that is '
      'still playing', () {
    final window = windowHolding(
      const AudioMixSchedule(clips: [], sourcePaths: []),
    );
    expect(upload(window), isA<OutputRefused>());
  });

  test('a window holding NO mix uploads nothing', () {
    expect(upload(windowHolding(null)), isA<OutputRefused>());
  });

  test('an empty mix with no device is still refused — the device is '
      'checked before anything downstream is asked to work it out', () {
    final window = windowHolding(
      const AudioMixSchedule(clips: [], sourcePaths: []),
    );
    expect(upload(window, centerSample: 480000), isA<OutputRefused>());
  });

  test('⛔a failed upload leaves the window exactly where it was', () {
    final window = windowHolding(
      const AudioMixSchedule(clips: [], sourcePaths: []),
    );
    for (final centre in [0, 48000, 4800000]) {
      expect(
        upload(window, centerSample: centre),
        isA<OutputRefused>(),
        reason: '$centre',
      );
      expect(window.centerSample, 0, reason: 'the centre never moved');
      expect(window.hasStreaming, isFalse);
    }
  });

  test('each reach has ONE home, and a window that says none plays', () {
    expect(AudioStreamingWindow.playing, (backSeconds: 2, aheadSeconds: 30));
    expect(AudioStreamingWindow.scrubbing, (backSeconds: 1, aheadSeconds: 2));
    expect(AudioStreamingWindow().reach, AudioStreamingWindow.playing);
  });
}
