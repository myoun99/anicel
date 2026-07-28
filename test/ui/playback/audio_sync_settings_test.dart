import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/playback/audio_sync_settings.dart';

void main() {
  test('device choices round-trip by NAME, defaulting to the system '
      'device (AUDIO-PRO R4)', () {
    const settings = AudioSyncSettings(
      outputDeviceName: 'Speakers (USB DAC)',
      inputDeviceName: 'Rode NT-USB',
    );
    final reopened = AudioSyncSettings.fromJson(settings.toJson());
    expect(reopened.outputDeviceName, 'Speakers (USB DAC)');
    expect(reopened.inputDeviceName, 'Rode NT-USB');

    // Defaults stay out of the JSON, and copyWith can CLEAR back to the
    // system default (null is a real value here, not an omission).
    expect(
      AudioSyncSettings.defaults.toJson().containsKey('outputDevice'),
      isFalse,
    );
    final cleared = settings.copyWith(
      outputDeviceName: null,
      inputDeviceName: null,
    );
    expect(cleared.outputDeviceName, isNull);
    expect(cleared.inputDeviceName, isNull);
    // And an untouched copyWith keeps them.
    expect(settings.copyWith(offset: 5).outputDeviceName, 'Speakers (USB DAC)');
  });

  group('the offset converts to samples exactly', () {
    test('milliseconds', () {
      const settings = AudioSyncSettings(offset: 100);
      expect(
        settings.offsetSamples(
          sampleRate: 48000,
          frameRateNumerator: 24,
          frameRateDenominator: 1,
        ),
        4800,
      );
    });

    test('frames, at an integer rate', () {
      const settings = AudioSyncSettings(offset: 2, unit: AvOffsetUnit.frames);
      expect(
        settings.offsetSamples(
          sampleRate: 48000,
          frameRateNumerator: 24,
          frameRateDenominator: 1,
        ),
        4000,
        reason: 'two frames at 24fps is 1/12 s',
      );
    });

    test('frames, at 23.976 — the fraction is not rounded away', () {
      const rate = ProjectFrameRate.ntsc(24);
      const settings = AudioSyncSettings(offset: 24, unit: AvOffsetUnit.frames);
      // 24 frames of 23.976 take 1.001 s exactly.
      expect(
        settings.offsetSamples(
          sampleRate: 48000,
          frameRateNumerator: rate.numerator,
          frameRateDenominator: rate.denominator,
        ),
        48048,
      );
    });

    test('a negative offset pulls the picture earlier', () {
      const settings = AudioSyncSettings(offset: -50);
      expect(
        settings.offsetSamples(
          sampleRate: 48000,
          frameRateNumerator: 24,
          frameRateDenominator: 1,
        ),
        -2400,
      );
    });

    test('nonsense geometry yields zero rather than dividing by it', () {
      const settings = AudioSyncSettings(offset: 10, unit: AvOffsetUnit.frames);
      expect(
        settings.offsetSamples(
          sampleRate: 0,
          frameRateNumerator: 24,
          frameRateDenominator: 1,
        ),
        0,
      );
      expect(
        settings.offsetSamples(
          sampleRate: 48000,
          frameRateNumerator: 0,
          frameRateDenominator: 1,
        ),
        0,
      );
    });
  });

  group('display', () {
    test('a frame offset also reads in milliseconds', () {
      const settings = AudioSyncSettings(offset: 12, unit: AvOffsetUnit.frames);
      expect(
        settings.offsetMilliseconds(
          frameRateNumerator: 24,
          frameRateDenominator: 1,
        ),
        500,
      );
    });

    test('a millisecond offset reports itself unchanged', () {
      const settings = AudioSyncSettings(offset: 37);
      expect(
        settings.offsetMilliseconds(
          frameRateNumerator: 24,
          frameRateDenominator: 1,
        ),
        37,
      );
    });
  });

  group('limits', () {
    test('a typo is clamped rather than accepted as a setup', () {
      // Accepting 5000 ms silently would look exactly like a sync bug.
      expect(AudioSyncSettings.clampOffset(5000, AvOffsetUnit.milliseconds), 500);
      expect(
        AudioSyncSettings.clampOffset(-5000, AvOffsetUnit.milliseconds),
        -500,
      );
      expect(AudioSyncSettings.clampOffset(999, AvOffsetUnit.frames), 60);
    });

    test('a real-world value passes through', () {
      // Bluetooth headphones commonly sit 150–300 ms behind.
      expect(
        AudioSyncSettings.clampOffset(220, AvOffsetUnit.milliseconds),
        220,
      );
    });
  });

  group('persistence', () {
    test('round trips through JSON', () {
      for (final settings in const [
        AudioSyncSettings(),
        AudioSyncSettings(offset: 120),
        AudioSyncSettings(offset: -3, unit: AvOffsetUnit.frames),
      ]) {
        expect(AudioSyncSettings.fromJson(settings.toJson()), settings);
      }
    });

    test('a hand-edited file is clamped on read, not trusted', () {
      expect(
        AudioSyncSettings.fromJson(const {
          'avOffset': 99999,
          'avOffsetUnit': 'milliseconds',
        }).offset,
        500,
      );
    });

    test('an unknown unit falls back rather than throwing', () {
      final settings = AudioSyncSettings.fromJson(const {
        'avOffset': 10,
        'avOffsetUnit': 'furlongs',
      });
      expect(settings.unit, AvOffsetUnit.milliseconds);
      expect(settings.offset, 10);
    });

    test('an empty map yields the defaults', () {
      expect(
        AudioSyncSettings.fromJson(const {}),
        AudioSyncSettings.defaults,
      );
    });
  });

  group('the inspector reports what is actually applied', () {
    test('the picture shift is the automatic correction plus the residual', () {
      const report = AudioSyncReport(
        deviceOpen: true,
        deviceSampleRate: 48000,
        deviceChannels: 2,
        reportedLatencySamples: 1440, // 30 ms of buffer
        userOffsetSamples: 4800, // 100 ms the device could not report
        frameRateNumerator: 24,
        frameRateDenominator: 1,
      );
      expect(report.reportedLatencyMillis, 30);
      expect(report.userOffsetMillis, 100);
      expect(report.appliedOffsetSamples, 4800 - 1440);
      expect(report.appliedOffsetMillis, 70);
    });

    test('the shift is also reported in frames — the visible unit', () {
      // Under one frame is invisible; that is the bar the automatic
      // correction has to clear on its own.
      const report = AudioSyncReport(
        deviceOpen: true,
        deviceSampleRate: 48000,
        deviceChannels: 2,
        reportedLatencySamples: 2000,
        frameRateNumerator: 24,
        frameRateDenominator: 1,
      );
      expect(report.appliedOffsetFrames, closeTo(-1.0, 0.001));
    });

    test('a closed device says so instead of reporting zeros', () {
      const report = AudioSyncReport(deviceOpen: false);
      expect(report.summary, contains('not open'));
      expect(report.summary, contains('platform player'));
    });

    test('the summary is one pasteable line', () {
      const report = AudioSyncReport(
        deviceOpen: true,
        deviceSampleRate: 48000,
        deviceChannels: 2,
        reportedLatencySamples: 1440,
        userOffsetSamples: 0,
        frameRateNumerator: 24,
        frameRateDenominator: 1,
      );
      expect(report.summary, contains('48000Hz 2ch'));
      expect(report.summary, contains('reported latency 30ms'));
      expect(report.summary, contains('frames'));
      expect(report.summary.split('\n'), hasLength(1));
    });

    test('a device with no rate does not divide by it', () {
      const report = AudioSyncReport(deviceOpen: true);
      expect(report.reportedLatencyMillis, 0);
      expect(report.appliedOffsetFrames, 0);
    });
  });
}
