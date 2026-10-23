import 'dart:developer' show Timeline;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_sync_settings.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';
import 'package:anicel/src/ui/playback/audio_windowed_upload.dart';

import '../../helpers/device_paced.dart';
import '../../helpers/native_engine_path.dart';

/// 🚨★★★**THE VIEWER HEARS WHAT THE CANVAS HEARS**
/// (viewer-plays-by-the-one-playback-law ④-b).
///
/// A movie's pictures follow its sound (`MediaRun`), and the sound's clock
/// is the canvas's reading of the same device ([ViewerSound.heardAt] —
/// `HeardOnTheDevice`): what the device was handed, less what it still
/// holds to play, with the user's own correction on top. ↩️The viewer read
/// what had been HANDED: its picture ran ahead of what was heard by the
/// device's latency, and a correction set in the settings never reached it.
///
/// Driven for real — miniaudio's null backend, the actual callback on an
/// actual thread — as the transport's own pins are.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  const tone = 'C:/work/tone.wav';
  const rate = 48000;

  /// [frames] samples of a steady tone.
  AudioConformStore toneOf(int frames) => AudioConformStore(
    resolveConformPath: (_) => null,
    runner: (request) async => ConformResult(
      outcome: ConformOutcome.built,
      samples: Float32List(frames)..fillRange(0, frames, 0.5),
      channels: 1,
      sampleRate: rate,
      frames: frames,
    ),
    log: (_) {},
  );

  Future<(QaAudioDevice, ViewerSound)> playing({
    int correction = 0,
    double fromSeconds = 0,
    int frames = 2 * rate,
    bool look = true,
  }) async {
    final store = toneOf(frames);
    store.resultFor(tone);
    await pumpEventQueue();
    expect(
      store.durationSecondsFor(tone),
      frames / rate,
      reason: 'fixture: conformed',
    );
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: rate, channels: 2, useNullBackend: true),
      greaterThan(0),
    );
    final sound = ViewerSound(
      conformStore: store,
      resolveDevice: () => QaAudioDevice.instance,
      resolveUserOffsetSamples: (_) => correction,
    );
    expect(sound.play(tone, fromSeconds: fromSeconds), isA<OutputArmed>());
    if (look) {
      sound.heardAt(); // the run's first look starts the device
    }
    return (device, sound);
  }

  /// play-press-first-frame-stall (10-15): the canvas's law, here too — a
  /// device started at the press played on through everything before the
  /// run's first look, and the picture met the sound frames in.
  test('🚨the sound starts on the run\'s first look, not at the press — a '
      'first look that comes late still reads where play was pressed',
      () async {
    final (device, sound) = await playing(fromSeconds: 1, look: false);
    // What comes before the first look.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(device.isPlaying, isFalse, reason: 'the press only arms it');

    // The look starts the device and then reads it: from where play was
    // pressed, never past what the device has been handed — the clock's
    // own law (`DeviceClockLine`), whatever the device did in between.
    // ↩️Read as exactly 1, a look the machine was busy through failed
    // (1.02 — 960 samples — in a loaded gate run, 저장 10-15). ↩️Held to the
    // look's own time and the latency, it failed again (1.0512 on a loaded
    // mac runner, 10-24): the null device runs on a timer from its open,
    // and a worker that fell behind hands every period it owes at once as
    // the run starts (miniaudio's `ma_device_write__null` waits only while
    // it is ahead). Real hardware never takes more than its buffer.
    final heard = sound.heardAt()!.seconds;
    final handed = device.readClock().stairSamples / rate;
    expect(
      heard,
      inInclusiveRange(1, handed),
      reason: 'heard from where play was pressed, and no further than handed',
    );
    expect(device.isPlaying, isTrue, reason: 'the first look starts it');
    sound.stop();
  }, skip: skip);

  /// A run that parks in the look it goes on in (`MediaRun`: resume, then
  /// hold) holds a sound that has not started yet — and the parked run
  /// goes on looking every tick.
  test('🚨a sound held before its first look never starts — the looks of a '
      'parked run find nothing to start', () async {
    final (device, sound) = await playing(fromSeconds: 1, look: false);
    sound.hold();

    sound.keepStreaming(frameTime: null); // the parked run's next look
    expect(sound.heardAt()!.seconds, 1, reason: 'held where it was pressed');
    expect(device.isPlaying, isFalse, reason: 'held before it was looked at');

    sound.resume(1);
    sound.keepStreaming(frameTime: null);
    expect(device.isPlaying, isTrue, reason: 'going on, the next look starts');
    sound.stop();
  }, skip: skip);

  // board a-start-is-heard-ahead-of-its-first-picture — the canvas's law,
  // here too: the run's first sample is heard as its first look's frame is
  // shown, whichever of the viewer's two looks comes first.
  group('🚨the sound\'s first sample is heard as the first look\'s frame is '
      'shown', () {
    /// When a look's frame is shown: [ahead] from now, on the FRAME clock —
    /// the clock the engine's frame times are on, which the sound reads them
    /// on (`HeardOnTheDevice`, `FrameTimeOnDevice`). ↩️It was the device's
    /// clock, the frame clock's own on Windows alone: on the Mac runners the
    /// frame clock stood further ahead of it than the 300ms looked ahead,
    /// and the lead came out nothing (release 10-22, macOS · TestFlight).
    Duration shownIn(Duration ahead) =>
        Duration(microseconds: Timeline.now) + ahead;

    test('the look that reads the clock first', () async {
      final (device, sound) = await playing(fromSeconds: 1, look: false);
      const ahead = Duration(milliseconds: 300);
      final heard = sound.heardAt(frameTime: shownIn(ahead))!.seconds;
      final handed = device.positionSamples;

      // ↩️1.05 — a callback's time on at most — is the bound a starved null
      // device breaks as it starts (the test above has why).
      expect(
        heard,
        inInclusiveRange(1, handed / rate + ahead.inMicroseconds / 1e6),
        reason: 'read where play was pressed — no further than handed, and '
            'played on until the frame is shown',
      );
      expect(
        handed,
        lessThan(rate),
        reason: 'the device stands ahead of the sound\'s first sample — '
            '↩️started on it, it was heard 0.3s less what it holds ahead',
      );
      sound.stop();
    }, skip: skip);

    test('the look that keeps the sound streaming first — as a run\'s tick '
        'looks (`MediaRun`)', () async {
      final (device, sound) = await playing(fromSeconds: 1, look: false);
      sound.keepStreaming(
        frameTime: shownIn(const Duration(milliseconds: 300)),
      );
      expect(device.isPlaying, isTrue, reason: '⛔premise: it started');
      expect(device.positionSamples, lessThan(rate));
      sound.stop();
    }, skip: skip);
  });

  test('🚨what the viewer reads is HEARD: the device\'s latency off what it '
      'was handed, and the user\'s own correction on', () async {
    // A tenth of a second, so it shows past any one callback.
    const correction = rate ~/ 10;
    final (device, sound) = await playing(correction: correction);
    expect(
      await waitOnTheDevice(
        device,
        () => device.clockPoint != null && device.positionSamples > rate ~/ 5,
      ),
      isTrue,
      reason: 'fixture: the device is running and saying when',
    );

    final before = device.positionSamples;
    final heard = sound.heardAt()!.seconds * rate;
    final after = device.positionSamples;

    // The line stands at the stair or past it, by no more than the device
    // carries — so one reading, between a stair read before it and one
    // read after, is held between the two (the transport's own bound).
    expect(
      heard,
      inInclusiveRange(
        before - device.latencySamples - correction,
        after - correction,
      ),
      reason: 'handed $before..$after, latency ${device.latencySamples}, '
          'correction $correction — without the correction it would be a '
          'tenth of a second on',
    );
    sound.stop();
  }, skip: skip);

  test('🚨the end is told by what is HEARD — once the last sample has been '
      'played out, and not before it has been handed', () async {
    // A fifth of a second, so it runs out well inside the wait.
    const frames = rate ~/ 5;
    final (device, sound) = await playing(frames: frames);

    expect(
      await waitOnTheDevice(device, () => sound.heardAt()?.ended ?? false),
      isTrue,
      reason: 'a sound played to its end is over',
    );
    expect(
      device.positionSamples,
      greaterThanOrEqualTo(frames),
      reason: 'and by then the device had been handed all of it',
    );
    expect(device.latencySamples, greaterThan(0), reason: 'fixture: it holds');
    // Long past what the device held at its end: the line has run on
    // through it, and stopped where the sound did.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      sound.heardAt()!.seconds * rate,
      closeTo(frames, 0.5),
      reason: 'what is heard stands AT the end — the device\'s latency off '
          'the line it reads, which runs on past what was handed only as far '
          'as the device held',
    );
    sound.stop();
  }, skip: skip);

  testWidgets('🚨a session\'s viewer sound takes the user\'s correction the '
      'canvas takes — read in one place, the rig', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.appSettings.audioSyncSettings.value = const AudioSyncSettings(
      offset: 80,
    );

    final sound = ViewerSound.ofSession(session);

    expect(
      sound.resolveUserOffsetSamples(rate),
      rate * 80 ~/ 1000,
      reason: 'eighty milliseconds at 48k',
    );
    expect(
      sound.resolveUserOffsetSamples(rate),
      session.playbackRig.userOffsetSamples(rate),
      reason: 'the canvas\'s own number',
    );
  });

  test('🚨a press reads where it was pressed while the device\'s latency '
      'drains — never behind it', () async {
    final (device, sound) = await playing(fromSeconds: 1);
    expect(device.latencySamples, greaterThan(0), reason: 'fixture: it holds');

    final heard = sound.heardAt()!.seconds;

    expect(
      heard,
      greaterThanOrEqualTo(1),
      reason: 'the playhead does not step back at a press — handed less '
          'what the device holds would put it ${device.latencySamples} '
          'samples behind where play was pressed',
    );
    sound.stop();
  }, skip: skip);

  test('🚨a viewer going silent leaves another player\'s sound alone — it '
      'silences its own run only', () async {
    final (device, sound) = await playing(fromSeconds: 1);
    expect(device.isPlaying, isTrue, reason: 'fixture: the viewer sounds');
    expect(device.play(startSample: 0), isNonZero, reason: 'another\'s');

    sound.stop();
    expect(
      device.isPlaying,
      isTrue,
      reason: '↩️the viewer stopped the output whatever played',
    );
  }, skip: skip);
}
