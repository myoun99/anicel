import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';
import 'package:anicel/src/ui/playback/audio_windowed_upload.dart';

/// The one door the transport and the scrubber both go through, so
/// streamed playback and streamed scrubbing drive the device on identical
/// geometry. Nothing named it (2026-09-05).
///
/// 🚨FALSE means "nothing was uploaded", and the caller's contract hangs
/// on it: no mix held, no device, an incomplete upload, or a device that
/// rejected the schedule all answer false so the caller LEAVES ANY OLD
/// SCHEDULE PLAYING rather than cutting the sound to silence. The window
/// must not move either — a centre that advanced on a failed upload would
/// tell the next poll there was nothing to re-center.
void main() {
  AudioConformStore store() {
    final conform = AudioConformStore(resolveConformPath: (_) => null);
    addTearDown(conform.dispose);
    return conform;
  }

  AudioStreamingWindow windowHolding(AudioMixSchedule? mix) =>
      AudioStreamingWindow()..mix = mix;

  bool upload(AudioStreamingWindow window, {int centerSample = 0}) =>
      window.upload(
        // ⛔No device is the case this bench can drive: the native one needs a
        // device run, and the point being pinned is what happens WITHOUT one.
        device: null,
        conformStore: store(),
        deviceRate: 48000,
        centerSample: centerSample,
      );

  test('🚨no device answers FALSE — the caller keeps the schedule that is '
      'still playing', () {
    final window = windowHolding(
      const AudioMixSchedule(clips: [], sourcePaths: []),
    );
    expect(upload(window), isFalse);
  });

  test('a window holding NO mix uploads nothing', () {
    expect(upload(windowHolding(null)), isFalse);
  });

  test('an empty mix with no device is still false — the device is checked '
      'before anything downstream is asked to work it out', () {
    final window = windowHolding(
      const AudioMixSchedule(clips: [], sourcePaths: []),
    );
    expect(upload(window, centerSample: 480000), isFalse);
  });

  test('⛔a failed upload leaves the window exactly where it was', () {
    final window = windowHolding(
      const AudioMixSchedule(clips: [], sourcePaths: []),
    );
    for (final centre in [0, 48000, 4800000]) {
      expect(upload(window, centerSample: centre), isFalse, reason: '$centre');
      expect(window.centerSample, 0, reason: 'the centre never moved');
      expect(window.hasStreaming, isFalse);
    }
  });

  test('the geometry has ONE home, and both surfaces read it there', () {
    expect(AudioStreamingWindow.backSeconds, 2);
    expect(AudioStreamingWindow.aheadSeconds, 30);
  });
}
