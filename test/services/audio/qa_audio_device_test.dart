import 'dart:ffi' show Float, AllocatorAlloc;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';

import '../../helpers/native_engine_path.dart';

/// The device stage, driven for real.
///
/// miniaudio's NULL backend runs the actual callback on an actual thread
/// with no hardware, so everything below is genuinely exercised on a CI
/// runner with no sound card: the transport advances, the mixer is called,
/// the position moves, looping wraps on the sample.
///
/// What this canNOT prove is that a real device produces audible sound in
/// the right speaker — that needs hardware and a person. The line is drawn
/// here on purpose rather than left implied.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final available = libraryPath != null;
  final skip = available ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    try {
      QaAudioDevice.instance?.close();
      QaAudioDevice.instance?.captureStop();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  QaAudioDevice openNull({int sampleRate = 48000, int channels = 2}) {
    final device = QaAudioDevice.instance;
    expect(device, isNotNull, reason: 'the binary did not bind');
    final rate = device!.open(
      sampleRate: sampleRate,
      channels: channels,
      useNullBackend: true,
    );
    expect(rate, greaterThan(0), reason: 'the null device failed to open');
    return device;
  }

  /// Waits until [check] holds or the budget runs out. The callback runs
  /// on the device's own thread, so the test has to wait for real time
  /// rather than pump anything.
  Future<bool> waitFor(bool Function() check, {int millis = 3000}) async {
    final deadline = DateTime.now().add(Duration(milliseconds: millis));
    while (DateTime.now().isBefore(deadline)) {
      if (check()) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return check();
  }

  AudioMixSource constantSource(double value, int frames, int channels) {
    final data = Float32List(frames * channels);
    for (var index = 0; index < data.length; index += 1) {
      data[index] = value;
    }
    return AudioMixSource(samples: data, channels: channels);
  }

  group('device enumeration and selection (AUDIO-PRO R4)', () {
    test('the null backend enumerates, describes, and opens by index', () {
      final device = QaAudioDevice.instance!;
      final playback = device.devicesOf(capture: false, useNullBackend: true);
      expect(playback, isNotEmpty,
          reason: 'the null backend exposes its one fake device');
      expect(playback.first.name, isNotEmpty);

      final capture = device.devicesOf(capture: true, useNullBackend: true);
      expect(capture, isNotEmpty,
          reason: 'capture enumeration is R5 recording groundwork');

      // Open BY INDEX 0 — the same device the enumeration described.
      final rate = device.open(
        sampleRate: 48000,
        channels: 2,
        useNullBackend: true,
        deviceIndex: 0,
      );
      expect(rate, greaterThan(0));
      device.close();
    }, skip: skip);

    test('a bogus index FAILS instead of opening something else', () {
      final device = QaAudioDevice.instance!;
      expect(
        device.open(
          sampleRate: 48000,
          channels: 2,
          useNullBackend: true,
          deviceIndex: 999,
        ),
        0,
        reason: 'the fallback to default must be the CALLER\'s informed '
            'choice, never a silent substitution',
      );
      // And the deliberate fallback works.
      expect(
        device.open(sampleRate: 48000, channels: 2, useNullBackend: true),
        greaterThan(0),
      );
      device.close();
    }, skip: skip);

    test('name-to-index mapping finds the enumerated device; the helper '
        'maps null and missing names to the default', () {
      final device = QaAudioDevice.instance!;
      // Positive case against the NULL backend's own list (the production
      // helper enumerates the default backend, which differs on purpose).
      final playback = device.devicesOf(capture: false, useNullBackend: true);
      final index = playback.indexWhere(
        (entry) => entry.name == playback.first.name,
      );
      expect(index, 0);
      // The helper's fallback paths hold on any machine, sound card or
      // not: null and unattached names mean the system default.
      expect(audioOutputDeviceIndexByName(device, null), -1);
      expect(audioOutputDeviceIndexByName(device, 'no-such-speaker'), -1,
          reason: 'unplugged hardware falls back to the system default');
    }, skip: skip);
  });

  group('the device opens and reports itself', () {
    test('a null device opens, states its geometry, and closes', () {
      final device = openNull();
      expect(device.isOpen, isTrue);
      expect(device.sampleRate, 48000);
      expect(device.channels, 2);
      expect(
        device.latencySamples,
        greaterThan(0),
        reason: 'the latency report is what the picture gets pulled forward by',
      );
      device.close();
      expect(device.isOpen, isFalse);
    }, skip: skip);

    test('opening twice is idempotent rather than a second device', () {
      final device = openNull();
      expect(device.open(useNullBackend: true), device.sampleRate);
      expect(device.isOpen, isTrue);
    }, skip: skip);
  });

  group('the transport is the clock', () {
    test('the position advances only while playing', () async {
      final device = openNull();
      device.setSchedule(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 480000)],
        sources: [constantSource(0.25, 48000, 2)],
      );

      expect(device.positionSamples, 0);
      expect(device.isPlaying, isFalse);

      device.play(startSample: 0);
      expect(await waitFor(() => device.positionSamples > 0), isTrue,
          reason: 'the callback never ran — the transport is not the clock');

      device.stop();
      final parked = device.positionSamples;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        device.positionSamples,
        parked,
        reason: 'a stopped transport must not keep counting',
      );
    }, skip: skip);

    test('playback starts where it is told, not at zero', () async {
      final device = openNull();
      device.setSchedule(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 480000)],
        sources: [constantSource(0.25, 48000, 2)],
      );
      const start = 96000;
      device.play(startSample: start);
      expect(
        await waitFor(() => device.positionSamples > start),
        isTrue,
      );
      expect(device.positionSamples, greaterThanOrEqualTo(start));
    }, skip: skip);

    test('a seek moves the transport without restarting anything', () async {
      // Because the mixer BUILDS a mix rather than starting clips, seeking
      // is just a change of where the next block is read from.
      final device = openNull();
      device.setSchedule(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 4800000)],
        sources: [constantSource(0.25, 48000, 2)],
      );
      device.play(startSample: 0);
      expect(await waitFor(() => device.positionSamples > 0), isTrue);

      device.seek(1000000);
      expect(
        await waitFor(() => device.positionSamples >= 1000000),
        isTrue,
      );
      expect(device.isPlaying, isTrue, reason: 'a seek must not stop playback');
    }, skip: skip);

    test('the meter reads the pre-clip bus peak and zeroes on stop '
        '(AUDIO-PRO R2)', () async {
      final device = openNull();
      device.setSchedule(
        clips: const [
          // Gain 2.0 pushes the bus past unity: the meter must show the
          // PRE-CLIP peak (that is the whole point), while the device
          // output clamps.
          AudioMixClip(
            sourceIndex: 0,
            startSample: 0,
            endSample: 480000,
            gain: 2.0,
          ),
        ],
        sources: [constantSource(0.6, 48000, 2)],
      );
      device.play(startSample: 0, looping: true);
      expect(
        await waitFor(() => device.peakFor(0) > 1.0),
        isTrue,
        reason: 'a 1.2 bus peak must read past unity — clipping made visible',
      );
      expect(device.peakFor(1), greaterThan(1.0));

      device.stop();
      expect(device.peakFor(0), 0,
          reason: 'a stopped transport meters silence, not a frozen bar');
      expect(device.peakFor(1), 0);
    }, skip: skip);

    test('a stop point ends playback instead of running on', () async {
      final device = openNull();
      device.setSchedule(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 48000)],
        sources: [constantSource(0.25, 48000, 2)],
      );
      device.play(startSample: 0, stopSample: 24000);
      expect(await waitFor(() => !device.isPlaying), isTrue);
      expect(
        device.positionSamples,
        greaterThanOrEqualTo(24000),
        reason: 'it should reach the stop point, not fall short',
      );
    }, skip: skip);

    test('looping wraps on the sample, not the buffer boundary', () async {
      // The wrap has to land exactly, or every loop pass would drift by up
      // to a buffer — which is how a long session ends up out of sync.
      final device = openNull();
      device.setSchedule(
        clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 48000)],
        sources: [constantSource(0.25, 48000, 2)],
      );
      device.play(startSample: 0, stopSample: 12000, looping: true);
      expect(await waitFor(() => device.positionSamples > 0), isTrue);
      // It must keep playing and stay inside the loop window.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(device.isPlaying, isTrue);
      expect(
        device.positionSamples,
        lessThanOrEqualTo(12000),
        reason: 'a looping transport must never leave its window',
      );
    }, skip: skip);
  });

  group('the schedule handoff', () {
    test('a schedule can be set while stopped', () {
      final device = openNull();
      expect(
        device.setSchedule(
          clips: const [AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 100)],
          sources: [constantSource(0.5, 100, 2)],
        ),
        isTrue,
      );
    }, skip: skip);

    test('a schedule SWAPS while playing (AUDIO-PRO R3): the transport '
        'never stops, and the new mix is heard within a block', () async {
      final device = openNull();
      device.setSchedule(
        clips: const [
          AudioMixClip(sourceIndex: 0, startSample: 0, endSample: 4800000),
        ],
        sources: [constantSource(0.25, 48000, 2)],
      );
      device.play(startSample: 0, looping: true);
      expect(await waitFor(() => device.peakFor(0) > 0.2), isTrue);
      final before = device.positionSamples;

      // The live edit: a louder schedule lands mid-play.
      expect(
        device.setSchedule(
          clips: const [
            AudioMixClip(
              sourceIndex: 0,
              startSample: 0,
              endSample: 4800000,
            ),
          ],
          sources: [constantSource(0.6, 48000, 2)],
        ),
        isTrue,
        reason: 'live replacement is the point of the double buffer',
      );
      expect(device.isPlaying, isTrue, reason: 'the swap must not stop audio');
      expect(
        await waitFor(() => device.peakFor(0) > 0.55),
        isTrue,
        reason: 'the NEW schedule must be what the callback mixes',
      );
      expect(
        device.positionSamples,
        greaterThanOrEqualTo(before),
        reason: 'the clock never rewinds over a swap',
      );

      // Rapid successive swaps must stay safe (the handshake frees the
      // old slot each time).
      for (var round = 0; round < 10; round += 1) {
        expect(
          device.setSchedule(
            clips: const [
              AudioMixClip(
                sourceIndex: 0,
                startSample: 0,
                endSample: 4800000,
              ),
            ],
            sources: [constantSource(0.3 + round * 0.05, 48000, 2)],
          ),
          isTrue,
        );
      }
      expect(device.isPlaying, isTrue);
      device.stop();
    }, skip: skip);

    test('an empty schedule plays silence rather than failing', () async {
      final device = openNull();
      expect(
        device.setSchedule(clips: const [], sources: const []),
        isTrue,
      );
      device.play(startSample: 0);
      expect(await waitFor(() => device.positionSamples > 0), isTrue,
          reason: 'the clock must run even with nothing to play');
    }, skip: skip);
  });

  group('position to frame', () {
    test('the picture is pulled forward by the reported latency', () {
      // The position counts what has been HANDED to the device; what is
      // being heard is that minus the buffer still in flight.
      const rate = ProjectFrameRate.integer(24);
      final frame = audioClockFrame(
        positionSamples: 48000, // one second queued
        latencySamples: 2000,
        extraOffsetSamples: 0,
        sampleRate: 48000,
        frameRateNumerator: rate.numerator,
        frameRateDenominator: rate.denominator,
      );
      expect(frame, (48000 - 2000) * 24 ~/ 48000);
    });

    test('the user offset moves it either way', () {
      int at(int offset) => audioClockFrame(
        positionSamples: 48000,
        latencySamples: 0,
        extraOffsetSamples: offset,
        sampleRate: 48000,
        frameRateNumerator: 24,
        frameRateDenominator: 1,
      );
      expect(at(0), 24);
      expect(at(48000), 48);
      expect(at(-24000), 12);
    });

    test('23.976 converts through the exact fraction', () {
      const rate = ProjectFrameRate.ntsc(24);
      final frame = audioClockFrame(
        positionSamples: 48000,
        latencySamples: 0,
        extraOffsetSamples: 0,
        sampleRate: 48000,
        frameRateNumerator: rate.numerator,
        frameRateDenominator: rate.denominator,
      );
      // One second at 23.976 is frame 23, not 24 — the pulldown rate is
      // genuinely slower and the clock must not round that away.
      expect(frame, 23);
    });

    test('a position before anything is heard clamps at zero', () {
      expect(
        audioClockFrame(
          positionSamples: 100,
          latencySamples: 2000,
          extraOffsetSamples: 0,
          sampleRate: 48000,
          frameRateNumerator: 24,
          frameRateDenominator: 1,
        ),
        0,
      );
    });

    test('nonsense geometry returns zero rather than dividing by it', () {
      expect(
        audioClockFrame(
          positionSamples: 48000,
          latencySamples: 0,
          extraOffsetSamples: 0,
          sampleRate: 0,
          frameRateNumerator: 24,
          frameRateDenominator: 1,
        ),
        0,
      );
    });
  });

  group('capture (AUDIO-PRO R5)', () {
    test('the null backend captures: open, deliver, drain, stop', () async {
      final device = QaAudioDevice.instance!;
      final rate = device.captureStart(
        sampleRate: 48000,
        useNullBackend: true,
      );
      expect(rate, 48000,
          reason: 'the C converts to the asked rate; what lands in the '
              'ring needs no conform');
      expect(device.captureIsOpen, isTrue);
      expect(device.captureChannels, greaterThanOrEqualTo(1));
      expect(device.captureLatencySamples, greaterThan(0));

      // A second start while open must refuse, not stack devices.
      expect(
        device.captureStart(sampleRate: 48000, useNullBackend: true),
        0,
      );

      // The null backend delivers (silence) on its own thread; drain it.
      final scratch = calloc<Float>(48000);
      var drained = 0;
      try {
        final delivered = await waitFor(() {
          drained += device.captureRead(scratch, 48000);
          return drained > 4800; // >100 ms of mono audio
        });
        expect(delivered, isTrue,
            reason: 'the capture callback never delivered into the ring');
      } finally {
        calloc.free(scratch);
      }
      expect(device.captureDroppedFrames, 0,
          reason: 'a drained ring must not drop');

      device.captureStop();
      expect(device.captureIsOpen, isFalse);
    }, skip: skip);

    test('a bad device index fails rather than opening something else', () {
      final device = QaAudioDevice.instance!;
      // Refresh the enumeration so the index check has a live list.
      device.devicesOf(capture: true, useNullBackend: true);
      expect(
        device.captureStart(
          sampleRate: 48000,
          useNullBackend: true,
          deviceIndex: 9999,
        ),
        0,
      );
      expect(device.captureIsOpen, isFalse);
    }, skip: skip);

    test('capture runs BESIDE playback on one context '
        '(record along to the cut)', () async {
      final device = openNull();
      expect(
        device.captureStart(sampleRate: 48000, useNullBackend: true),
        48000,
        reason: 'a live playback device must not block the microphone',
      );
      expect(device.isOpen, isTrue);
      expect(device.captureIsOpen, isTrue);
      device.captureStop();
      expect(device.isOpen, isTrue,
          reason: 'closing the microphone must not stop playback');
    }, skip: skip);
  });

  group('AudioRecorder (AUDIO-PRO R5)', () {
    test('a take accumulates and stops clean', () async {
      final recorder = AudioRecorder(device: QaAudioDevice.instance);
      final rate = recorder.start(sampleRate: 48000, useNullBackend: true);
      expect(rate, 48000);
      expect(recorder.isRecording, isTrue);

      // Real time: the drain timer needs the event loop.
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final recording = recorder.stop();
      expect(recorder.isRecording, isFalse);
      expect(recording, isNotNull);
      expect(recording!.sampleRate, 48000);
      expect(recording.channels, greaterThanOrEqualTo(1));
      expect(recording.length, greaterThan(0),
          reason: 'the drain timer collected nothing');
      expect(recording.droppedFrames, 0);
      expect(QaAudioDevice.instance!.captureIsOpen, isFalse,
          reason: 'stop() must release the microphone');
    }, skip: skip);

    test('stopping without starting reports null, not a crash', () {
      final recorder = AudioRecorder(device: QaAudioDevice.instance);
      expect(recorder.stop(), isNull);
    }, skip: skip);

    test('a vanished saved microphone falls back to the default', () {
      final recorder = AudioRecorder(device: QaAudioDevice.instance);
      // Index 9999 cannot exist; the recorder retries with the system
      // default rather than failing the take (the R4 informed-fallback
      // contract, applied by the caller).
      QaAudioDevice.instance!.devicesOf(capture: true, useNullBackend: true);
      final rate = recorder.start(
        sampleRate: 48000,
        useNullBackend: true,
        deviceIndex: 9999,
      );
      expect(rate, 48000);
      expect(recorder.stop(), isNotNull);
    }, skip: skip);
  });
}
