import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/playback/audio_playback_schedule.dart';
import 'package:anicel/src/ui/playback/audio_windowed_upload.dart';

/// The one door the transport and the scrubber both go through, so
/// streamed playback and streamed scrubbing drive the device on identical
/// geometry. Nothing named it (2026-09-05).
///
/// 🚨NULL means "nothing was uploaded", and the caller's contract hangs on
/// it: no device, an incomplete upload, or a device that rejected the
/// schedule all answer null so the caller LEAVES ANY OLD SCHEDULE PLAYING
/// rather than cutting the sound to silence.
void main() {
  AudioConformStore store() {
    final conform = AudioConformStore(resolveConformPath: (_) => null);
    addTearDown(conform.dispose);
    return conform;
  }

  bool? upload({required AudioMixSchedule mix, int centerSample = 0}) =>
      uploadWindowedSchedule(
        // ⛔No device is the case this bench can drive: the native one needs a
        // device run, and the point being pinned is what happens WITHOUT one.
        device: null,
        mix: mix,
        conformStore: store(),
        deviceRate: 48000,
        centerSample: centerSample,
      );

  test('🚨no device answers NULL, not false — false would read as "uploaded, '
      'nothing streaming" and the caller would drop a schedule that is '
      'still playing', () {
    expect(
      upload(
        mix: const AudioMixSchedule(clips: [], sourcePaths: []),
      ),
      isNull,
    );
  });

  test('an empty mix with no device is still null — the device is checked '
      'FIRST, so nothing downstream is asked to work it out', () {
    expect(
      upload(
        mix: const AudioMixSchedule(clips: [], sourcePaths: []),
        centerSample: 480000,
      ),
      isNull,
    );
  });

  test('the window arguments do not change that — a null device is null at '
      'any position', () {
    for (final centre in [0, 48000, 4800000]) {
      expect(
        upload(
          mix: const AudioMixSchedule(clips: [], sourcePaths: []),
          centerSample: centre,
        ),
        isNull,
        reason: 'centre $centre',
      );
    }
  });
}
