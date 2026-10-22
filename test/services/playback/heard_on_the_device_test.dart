import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/services/playback/device_clock_line.dart';
import 'package:anicel/src/services/playback/heard_on_the_device.dart';

/// Where a listener is at the moment a frame is SHOWN: the device's line
/// read now, carried on at the device's rate to that moment on the device's
/// clock — the frame clock's moment moved across by the two clocks' own
/// difference.
void main() {
  const rate = 48000;

  /// A device that handed [handed] samples at device time 1s, read at
  /// [nowMicros] on its own clock.
  DeviceClockReading readAt(int nowMicros, {int handed = 48000}) => (
    point: (positionSamples: handed, atMicros: 1000000),
    stairSamples: handed,
    nowMicros: nowMicros,
  );

  test('🚨a moment after now is the count now, carried on to it at the '
      'device\'s rate', () {
    final heard = HeardOnTheDevice(frameClockNow: () => 1010000)
      ..arm(deviceRate: rate, carriesFor: 4800);
    final now = heard.heard(
      readAt(1010000),
      latencySamples: 0,
      userOffsetSamples: 0,
    );
    final shown = heard.heard(
      readAt(1010000),
      frameTime: const Duration(microseconds: 1030000),
      latencySamples: 0,
      userOffsetSamples: 0,
    );
    expect(shown - now, 960, reason: 'twenty milliseconds on, at 48k');
  });

  test('🚨a positive correction shows the picture LATER, as the settings say: '
      'sound that reaches the ear late is an earlier sample heard (board '
      'av-offset-sign-is-backwards)', () {
    const wireless = AudioSyncSettings(offset: 100);
    int heardWith(int userOffsetSamples) =>
        (HeardOnTheDevice(frameClockNow: () => 1010000)
              ..arm(deviceRate: rate, carriesFor: 4800))
            .heard(
              readAt(1010000),
              latencySamples: 0,
              userOffsetSamples: userOffsetSamples,
            );
    final offset = wireless.offsetSamples(
      sampleRate: rate,
      frameRateNumerator: 24,
      frameRateDenominator: 1,
    );
    expect(
      heardWith(offset),
      heardWith(0) - rate ~/ 10,
      reason: 'a tenth of a second back is heard: the frame shown at this '
          'moment is the one a tenth of a second back',
    );
  });

  test('🚨the moment is moved onto the device\'s clock by the two clocks\' '
      'own difference', () {
    // The device's clock stands 5ms ahead of the frame clock.
    final heard = HeardOnTheDevice(frameClockNow: () => 1005000)
      ..arm(deviceRate: rate, carriesFor: 4800);
    final atNow = heard.heard(
      readAt(1010000),
      frameTime: const Duration(microseconds: 1005000),
      latencySamples: 0,
      userOffsetSamples: 0,
    );
    final read = heard.heard(
      readAt(1010000),
      latencySamples: 0,
      userOffsetSamples: 0,
    );
    expect(atNow, read, reason: 'the frame clock\'s now is the device\'s now');
  });

  // 유저 2026-10-15 (F-364): 「재생중에, 아직 초록바가 안된 곳으로,
  // 초록바가 차기 시작하는곳으로 재생헤드가 점프해버려서 거기서 재생되는
  // 버그」 — a reading that steps back is the lap wrapping to a playhead.
  group('🚨never a step back — only the fold into the lap goes back', () {
    test('a moment that goes back — the vblank claims started again on an '
        'earlier vblank — leaves what is heard where it got to, until the '
        'moment passes it', () {
      final heard = HeardOnTheDevice(frameClockNow: () => 1010000)
        ..arm(deviceRate: rate, carriesFor: 4800);
      int shownAt(int frameMicros) => heard.heard(
        readAt(1010000),
        frameTime: Duration(microseconds: frameMicros),
        latencySamples: 0,
        userOffsetSamples: 0,
      );

      final ahead = shownAt(1060000);
      expect(
        shownAt(1018000),
        ahead,
        reason: '42ms back — a whole film frame at 24fps',
      );
      expect(shownAt(1070000), ahead + 480, reason: 'on from where it got');
    });

    test('the line dipping where its highest point grows old leaves what is '
        'heard where it got to', () {
      const step = 480;
      const t = 5000000;
      int ms(num milliseconds) => (milliseconds * 1000).round();
      final heard = HeardOnTheDevice()..arm(deviceRate: rate, carriesFor: 1440);
      int read(({int positionSamples, int atMicros}) at, int now) =>
          heard.heard(
            (point: at, stairSamples: at.positionSamples, nowMicros: now),
            latencySamples: 0,
            userOffsetSamples: 0,
          );
      // One callback on time, and then every one of them 2ms late: their
      // points lie on a line 96 samples under the first.
      read((positionSamples: step, atMicros: t), t);
      ({int positionSamples, int atMicros}) late(int k) =>
          (positionSamples: step + k * step, atMicros: t + ms(10 * k + 2));
      for (var k = 1; k <= 49; k += 1) {
        read(late(k), late(k).atMicros);
      }
      expect(read(late(49), t + ms(501.9)), step + 24091);

      expect(
        read(late(50), late(50).atMicros),
        step + 24091,
        reason: 'the first point is forgotten and the lower line says 24480 '
            'here; what is heard does not go back',
      );
    });

    test('a new arm is another run: what was heard under the one before is '
        'not this one\'s', () {
      final heard = HeardOnTheDevice(frameClockNow: () => 1010000)
        ..arm(deviceRate: rate, carriesFor: 4800);
      heard.heard(
        readAt(1010000, handed: 96000),
        latencySamples: 0,
        userOffsetSamples: 0,
      );

      heard.arm(deviceRate: rate, carriesFor: 4800);

      expect(
        heard.heard(readAt(1010000), latencySamples: 0, userOffsetSamples: 0),
        48480,
      );
    });

    test('the fold into the lap is the one way back', () {
      // A loop of 100ms from the top, and the device's own count wrapping.
      const lap = 4800;
      final heard = HeardOnTheDevice()
        ..arm(deviceRate: rate, carriesFor: 1440, lapSamples: lap);
      int read(int position, int at) => heard.heard(
        (
          point: (positionSamples: position, atMicros: at),
          stairSamples: position,
          nowMicros: at,
        ),
        latencySamples: 0,
        userOffsetSamples: 0,
      );

      expect(read(4320, 1090000), 4320);
      expect(read(480, 1110000), 480, reason: 'a lap on, at its top');
    });
  });

  // board a-start-is-heard-ahead-of-its-first-picture: a run started ON its
  // first sample was heard ahead of its first picture by however long the
  // frame took to be shown past what the device holds — and the frames in
  // between were never shown.
  group('🚨the lead: a run\'s first sample is heard as its first picture is '
      'shown', () {
    test('what the device plays until the frame is shown, less what it '
        'holds and less the user\'s correction', () {
      final heard = HeardOnTheDevice(frameClockNow: () => 1010000)
        ..arm(deviceRate: rate, carriesFor: 4800);
      expect(
        heard.leadFor(
          deviceNowMicros: 1010000,
          frameTime: const Duration(microseconds: 1060000),
          latencySamples: 480,
          userOffsetSamples: -960,
        ),
        2400 - 480 + 960,
        reason: 'fifty milliseconds at 48k, less ten held — and sound that '
            'reaches the ear early (a negative correction) is led further',
      );
    });

    test('🚨a run started that far ahead reads its first sample at the look '
        'that starts it', () {
      final heard = HeardOnTheDevice(frameClockNow: () => 1010000)
        ..arm(deviceRate: rate, carriesFor: 4800);
      const shown = Duration(microseconds: 1060000);
      final lead = heard.leadFor(
        deviceNowMicros: 1010000,
        frameTime: shown,
        latencySamples: 480,
        userOffsetSamples: 0,
      );
      const first = 96000;
      expect(
        heard.heard(
          // Started, and no callback has spoken yet: only the stair.
          (point: null, stairSamples: first - lead, nowMicros: 1010000),
          frameTime: shown,
          latencySamples: 480,
          userOffsetSamples: 0,
        ),
        first,
        reason: 'started ON its first sample, it read 1920 samples on',
      );
    });

    test('none where the device holds more than the frame waits — and none '
        'without a moment it is shown', () {
      final heard = HeardOnTheDevice(frameClockNow: () => 1010000)
        ..arm(deviceRate: rate, carriesFor: 4800);
      expect(
        heard.leadFor(
          deviceNowMicros: 1010000,
          frameTime: const Duration(microseconds: 1020000),
          latencySamples: 960,
          userOffsetSamples: 0,
        ),
        0,
        reason: 'heard ten milliseconds after it is shown, it is not led on '
            'into the frames before it',
      );
      expect(
        heard.leadFor(
          deviceNowMicros: 1010000,
          frameTime: null,
          latencySamples: 0,
          userOffsetSamples: -960,
        ),
        960,
        reason: 'no moment: only the correction leads',
      );
    });
  });

  // take-head-trims-at-the-playback-start (10-15): a take is placed by the
  // moment its anchor was heard.
  group('🚨one who LISTENS reads now — not held to how far a picture got', () {
    test('the line now, less the latency, and less the user\'s '
        'correction', () {
      final heard = HeardOnTheDevice(frameClockNow: () => 1010000)
        ..arm(deviceRate: rate, carriesFor: 4800);
      expect(
        heard.heardNow(
          readAt(1010000),
          latencySamples: 1440,
          userOffsetSamples: 480,
        ),
        48480 - 1440 - 480,
        reason: 'handed 48000 at 1s, ten milliseconds on',
      );
    });

    test('a picture\'s reading at the moment its frame is shown — ahead of '
        'now — does not carry the listener\'s with it', () {
      final heard = HeardOnTheDevice(frameClockNow: () => 1010000)
        ..arm(deviceRate: rate, carriesFor: 4800);
      final shown = heard.heard(
        readAt(1010000),
        frameTime: const Duration(microseconds: 1040000),
        latencySamples: 0,
        userOffsetSamples: 0,
      );
      expect(shown, 48480 + 1440, reason: 'fixture: thirty milliseconds on');

      expect(
        heard.heardNow(
          readAt(1010000),
          latencySamples: 0,
          userOffsetSamples: 0,
        ),
        48480,
        reason: 'what is heard NOW, the furthest a picture got held out',
      );
    });
  });
}
