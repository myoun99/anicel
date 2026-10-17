import 'dart:ffi' show AllocatorAlloc, Float;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_mixer_reference.dart';
import 'package:anicel/src/ui/playback/audio_recorder.dart';

import '../../helpers/device_paced.dart';
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
      expect(audioDeviceIndexByName(device, capture: false, name: null), -1);
      expect(
        audioDeviceIndexByName(
          device,
          capture: false,
          name: 'no-such-speaker',
        ),
        -1,
        reason: 'unplugged hardware falls back to the system default',
      );
      // The capture side answers on the same two paths (R5), so the one
      // search is exercised on both kinds.
      expect(audioDeviceIndexByName(device, capture: true, name: null), -1);
      expect(
        audioDeviceIndexByName(device, capture: true, name: 'no-such-mic'),
        -1,
        reason: 'an unplugged microphone falls back to the system default',
      );

      // And it searches the SIDE it was asked for. Only real hardware can
      // show that: the helper enumerates the default backend on purpose,
      // and a runner with no sound card has two empty lists, where every
      // name answers -1 whichever side is read.
      final speakers = device.devicesOf(capture: false);
      final mics = device.devicesOf(capture: true);
      for (final (capture, list) in [(false, speakers), (true, mics)]) {
        if (list.isEmpty) {
          continue;
        }
        expect(
          audioDeviceIndexByName(
            device,
            capture: capture,
            name: list.first.name,
          ),
          0,
          reason: 'the first enumerated device on this side is index 0',
        );
        final other = capture ? speakers : mics;
        final onlyHere = list
            .map((entry) => entry.name)
            .where((name) => other.every((entry) => entry.name != name));
        if (onlyHere.isNotEmpty) {
          expect(
            audioDeviceIndexByName(
              device,
              capture: !capture,
              name: onlyHere.first,
            ),
            -1,
            reason: 'a name that exists only on one side is not found on '
                'the other — the kind axis really reaches the enumeration',
          );
        }
      }
    }, skip: skip);

    test('openAudioOutput opens on an unattached NAME — the fallback is to '
        'the system default, never to silence (AUDIO-PRO R4)', () {
      final device = QaAudioDevice.instance!;
      // 🚨ASK WHETHER THE DEFAULT OPENS, not whether anything enumerates.
      // A runner with no sound card still lists an ALSA default and then
      // refuses to open it, so the enumeration answered yes and this bench
      // failed for want of hardware (Linux CI, 2026-09-22 — the first guard
      // asked `devicesOf` and never fired). What is under test is WHICH
      // device the fallback picks, and that presupposes a default that
      // opens; where none does, there is nothing to fall back to.
      //
      // ⚠️It keeps its teeth: a machine whose default opens must also open
      // through the unattached name below, and a failure there is the
      // product's, not the runner's.
      if (device.open(sampleRate: 48000, channels: 2) <= 0) {
        markTestSkipped('no playback device opens on this machine');
        return;
      }
      device.close();
      expect(
        openAudioOutput(
          device,
          sampleRate: 48000,
          preferredName: 'no-such-speaker',
        ),
        isTrue,
        reason: 'the name resolves to -1, so the FIRST open is the default',
      );
      expect(device.isOpen, isTrue);
      device.close();

      expect(
        openAudioOutput(device, sampleRate: 48000, preferredName: null),
        isTrue,
        reason: 'no preference is the same default',
      );
      device.close();
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
      expect(
        await waitOnTheDevice(device, () => device.positionSamples > 0),
        isTrue,
        reason: 'the callback never ran — the transport is not the clock',
      );

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
        await waitOnTheDevice(device, () => device.positionSamples > start),
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
      expect(
        await waitOnTheDevice(device, () => device.positionSamples > 0),
        isTrue,
      );

      device.seek(1000000);
      expect(
        await waitOnTheDevice(device, () => device.positionSamples >= 1000000),
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
        await waitOnTheDevice(device, () => device.peakFor(0) > 1.0),
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
      expect(await waitOnTheDevice(device, () => !device.isPlaying), isTrue);
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
      expect(
        await waitOnTheDevice(device, () => device.positionSamples > 0),
        isTrue,
      );
      // It must keep playing and stay inside the loop window, a fifth of a
      // second of its own on. ↩️Of the wall, which a starved device can sit
      // through.
      final handed = Handed(device);
      await waitOnTheDevice(
        device,
        () => handed.samples >= 9600 || !device.isPlaying,
      );
      expect(device.isPlaying, isTrue);
      expect(
        device.positionSamples,
        lessThanOrEqualTo(12000),
        reason: 'a looping transport must never leave its window',
      );
    }, skip: skip);
  });

  // 유저 2026-10-08: 「늦게바뀌는건 좀 많이 신경쓰이는데. 근본/구조적으로
  // 어떻게 안되나」 — the device's count is a stair, and each callback now
  // says WHEN it climbed, so a reader can draw the line through it.
  group('each callback says when', () {
    test('🚨the point stands at the stair, stamped on the clock\'s own time '
        'and never after now', () async {
      final device = openNull();
      device.setSchedule(clips: const [], sources: const []);
      expect(device.clockPoint, isNull, reason: 'nothing has played yet');

      device.play(startSample: 0);
      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
        reason: 'no callback spoke',
      );

      final clock = device.readClock();
      final point = clock.point!;
      expect(point.positionSamples, greaterThan(0));
      expect(
        clock.stairSamples,
        greaterThanOrEqualTo(point.positionSamples),
        reason: 'read after its point, the stair is at it or past it',
      );
      expect(clock.nowMicros, greaterThanOrEqualTo(point.atMicros));
      expect(
        clock.nowMicros - point.atMicros,
        lessThan(Duration.microsecondsPerSecond),
        reason: 'stamped on the clock that says now, a moment ago',
      );
    }, skip: skip);

    test('the points move on with the stair, a step at a time', () async {
      final device = openNull();
      device.setSchedule(clips: const [], sources: const []);
      device.play(startSample: 0);
      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
      );

      final first = device.clockPoint!;
      expect(
        await waitOnTheDevice(
          device,
          () => device.clockPoint!.positionSamples > first.positionSamples,
        ),
        isTrue,
      );
      final next = device.clockPoint!;
      expect(next.atMicros, greaterThan(first.atMicros));
    }, skip: skip);

    test('🚨an arm drops the old run\'s point: until the new arm\'s first '
        'callback speaks there is only the stair', () async {
      final device = openNull();
      device.setSchedule(clips: const [], sources: const []);
      device.play(startSample: 0);
      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
      );

      // Armed again, far from where it was.
      const start = 2400000;
      device.play(startSample: start);
      final atOnce = device.clockPoint;
      expect(
        atOnce == null || atOnce.positionSamples >= start,
        isTrue,
        reason: 'a point of the run before, read as this run\'s, would put '
            'the picture 50 seconds back for a callback\'s time',
      );
      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
        reason: 'the new arm never spoke',
      );
      expect(device.clockPoint!.positionSamples, greaterThan(start));

      device.seek(96000);
      final afterSeek = device.clockPoint;
      expect(
        afterSeek == null || afterSeek.positionSamples < start,
        isTrue,
        reason: 'a seek is an arm too',
      );

      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
      );
      device.stop();
      expect(
        device.clockPoint,
        isNull,
        reason: 'a transport that was stopped has no run to have a point of',
      );

      // A device that is closed while it plays, and opened again.
      device.play(startSample: 0);
      expect(
        await waitOnTheDevice(device, () => device.clockPoint != null),
        isTrue,
      );
      device.close();
      final again = openNull();
      expect(
        again.clockPoint,
        isNull,
        reason: 'a device just opened has no run: what the one before it '
            'played is not its point',
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
      expect(
        await waitOnTheDevice(device, () => device.peakFor(0) > 0.2),
        isTrue,
      );
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
        await waitOnTheDevice(device, () => device.peakFor(0) > 0.55),
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
      expect(
        await waitOnTheDevice(device, () => device.positionSamples > 0),
        isTrue,
        reason: 'the clock must run even with nothing to play',
      );
    }, skip: skip);
  });

  group('the device plays its own PCM where it lies '
      '(play-press-first-frame-stall)', () {
    // Ten seconds, so a source runs out long after every wait below.
    const frames = 48000 * 10;

    List<AudioMixClip> clipsOver(int sources) => [
      for (var index = 0; index < sources; index += 1)
        AudioMixClip(sourceIndex: index, startSample: 0, endSample: frames),
    ];

    test('a list the device made is held by its maker and by each source '
        'that plays it, and by nothing a schedule leaves behind', () {
      final device = openNull();
      final made = device.newSamples(frames * 2)!;
      expect(device.debugHoldsOf(made), 1, reason: 'its maker');

      final source = AudioMixSource(samples: made, channels: 2);
      expect(
        device.setSchedule(clips: clipsOver(2), sources: [source, source]),
        isTrue,
      );
      expect(
        device.debugHoldsOf(made),
        3,
        reason: 'its maker and both sources of the slot playing it — the '
            'call let go of its own',
      );

      expect(device.setSchedule(clips: const [], sources: const []), isTrue);
      expect(
        device.debugHoldsOf(made),
        1,
        reason: 'the replaced slot let go of what it played',
      );
    }, skip: skip);

    test('a list the device made plays where it lies: what is written into '
        'it after the schedule is what is heard', () async {
      final device = openNull();
      final made = device.newSamples(frames * 2)!
        ..fillRange(0, frames * 2, 0.25);
      device.setSchedule(
        clips: clipsOver(1),
        sources: [AudioMixSource(samples: made, channels: 2)],
      );
      device.play(startSample: 0);
      expect(
        await waitOnTheDevice(device, () => device.peakFor(0) > 0.2),
        isTrue,
      );

      made.fillRange(0, made.length, 0.6);
      expect(
        await waitOnTheDevice(device, () => device.peakFor(0) > 0.55),
        isTrue,
        reason: 'the slot plays the buffer itself — nothing was copied',
      );
      device.stop();
    }, skip: skip);

    test('a list the device did not make plays as it was when scheduled — '
        'the callback never reads the Dart heap', () async {
      final device = openNull();
      final plain = Float32List(frames * 2)..fillRange(0, frames * 2, 0.25);
      device.setSchedule(
        clips: clipsOver(1),
        sources: [AudioMixSource(samples: plain, channels: 2)],
      );
      device.play(startSample: 0);
      expect(
        await waitOnTheDevice(device, () => device.peakFor(0) > 0.2),
        isTrue,
      );

      plain.fillRange(0, plain.length, 0.6);
      // For a third of a second of the device's own — ↩️of the wall, which a
      // starved device can sit through having played none of it.
      expect(
        await waitOnTheDevice(
          device,
          () => device.peakFor(0) > 0.3,
          budget: const Duration(milliseconds: 300),
        ),
        isFalse,
        reason: 'the schedule plays a copy made when it was set',
      );
      expect(device.peakFor(0), closeTo(0.25, 0.01));
      expect(device.debugHoldsOf(plain), -1);
      device.stop();
    }, skip: skip);
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
        final delivered = await waitOnTheDevice(device, () {
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

    // take-head-trims-at-the-playback-start (10-15): the playback's own
    // shape, so a take is placed by what the microphone had taken in when
    // its anchor was heard — both lines on one clock.
    test('🚨each capture callback says when: the frames the ring was given, '
        'stamped on the playback\'s clock — and a stopped capture says '
        'nothing', () async {
      final device = QaAudioDevice.instance!;
      expect(device.readCaptureClock().point, isNull,
          reason: 'nothing is capturing');
      expect(
        device.captureStart(sampleRate: 48000, useNullBackend: true),
        48000,
      );
      expect(
        await waitOnTheDevice(
          device,
          () => device.readCaptureClock().point != null,
        ),
        isTrue,
        reason: 'no capture callback spoke',
      );

      final clock = device.readCaptureClock();
      final point = clock.point!;
      expect(point.positionSamples, greaterThan(0));
      expect(
        clock.stairSamples,
        greaterThanOrEqualTo(point.positionSamples),
        reason: 'read after its point, the stair is at it or past it',
      );
      expect(clock.nowMicros, greaterThanOrEqualTo(point.atMicros));
      expect(
        clock.nowMicros - point.atMicros,
        lessThan(Duration.microsecondsPerSecond),
        reason: 'stamped on the clock that says now (the playback\'s), a '
            'moment ago',
      );
      expect(
        await waitOnTheDevice(
          device,
          () =>
              device.readCaptureClock().point!.positionSamples >
              point.positionSamples,
        ),
        isTrue,
        reason: 'the points move on with the frames given',
      );
      expect(
        await waitOnTheDevice(
          device,
          () => device.readCaptureClock().stairSamples > 9600,
        ),
        isTrue,
        reason: 'fixture: a fifth of a second taken in',
      );

      device.captureStop();
      expect(device.readCaptureClock().point, isNull);
      expect(device.readCaptureClock().stairSamples, 0);

      // Started again, a capture speaks of itself alone: until its own
      // first callback there is no point — not the last capture's.
      expect(
        device.captureStart(sampleRate: 48000, useNullBackend: true),
        48000,
      );
      final fresh = device.readCaptureClock().point;
      expect(
        fresh == null || fresh.positionSamples < 9600,
        isTrue,
        reason: 'the stopped capture\'s point, ${fresh?.positionSamples} '
            'frames, read as this one\'s',
      );
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
      final device = QaAudioDevice.instance!;
      final recorder = AudioRecorder(device: device);
      final rate = recorder.start(sampleRate: 48000, useNullBackend: true);
      expect(rate, 48000);
      expect(recorder.isRecording, isTrue);

      // Real time: the drain timer needs the event loop — for the
      // microphone's own 0.4s. ↩️0.4s of the wall, which a starved capture
      // can spend having taken in nothing.
      expect(
        await waitOnTheDevice(
          device,
          () => device.readCaptureClock().stairSamples >= 19200,
        ),
        isTrue,
        reason: 'the microphone took nothing in',
      );

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

    // take-head-trims-at-the-playback-start (10-15).
    test('🚨what the microphone had taken in at a moment: on the capture\'s '
        'line, and what it holds of its own on top', () async {
      final device = QaAudioDevice.instance!;
      final recorder = AudioRecorder(device: device);
      expect(recorder.capturedAt(device.clockNowMicros), isNull,
          reason: 'nothing is recording');
      expect(recorder.start(sampleRate: 48000, useNullBackend: true), 48000);
      expect(recorder.latencySamples, device.captureLatencySamples);
      bool spoke() => recorder.capturedAt(device.clockNowMicros) != null;
      expect(
        await waitOnTheDevice(device, spoke),
        isTrue,
        reason: 'no capture callback spoke',
      );

      final before = device.readCaptureClock();
      final taken = recorder.capturedAt(before.nowMicros)!;
      expect(
        taken,
        greaterThanOrEqualTo(before.stairSamples + recorder.latencySamples),
        reason: 'never behind what the ring had been given — and what the '
            'microphone holds is on top',
      );
      expect(
        taken,
        lessThan(before.stairSamples + 2 * recorder.latencySamples + 2400),
      );

      // The count runs with the time: a third of a second on, a third of a
      // second more taken in — read once the microphone has spoken a
      // fifteenth of a second past it, so a count read at the moment of
      // reading instead would be that much over. ↩️Read after 0.4s of the
      // wall, which a starved capture can sit through silent.
      final later = device.clockNowMicros + 333333;
      expect(
        await waitOnTheDevice(
          device,
          () =>
              (device.readCaptureClock().point?.atMicros ?? 0) >=
              later + 66667,
        ),
        isTrue,
        reason: 'the microphone stopped',
      );
      expect(
        recorder.capturedAt(later)! - taken,
        closeTo(
          (later - before.nowMicros) * 48000 ~/ Duration.microsecondsPerSecond,
          960,
        ),
      );
      recorder.stop();
      expect(recorder.capturedAt(device.clockNowMicros), isNull,
          reason: 'stopped, it takes nothing in');
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
