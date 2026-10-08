import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';

import '../../helpers/native_engine_path.dart';

/// 🚨★★★**THE VIEWER'S LEVEL, MEASURED WHERE IT IS HEARD** (F-289).
///
/// The transport's sound cell ends in one argument — the gain
/// [ViewerSound.play] mixes into the clip it uploads — and nothing on the
/// widget bench can see that line: every test above it runs a recorded
/// sound, and a level that reached the recorder and never the mix would
/// leave the whole suite green while the bar did nothing. So this drives
/// the device for real — miniaudio's null backend, the actual callback on
/// an actual thread — and reads the bus it mixes into.
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

  /// Two seconds of one steady level, so the peak of any block mixed from
  /// it IS the level it was mixed at.
  AudioConformStore steadyTone() => AudioConformStore(
    resolveConformPath: (_) => null,
    runner: (request) async => ConformResult(
      outcome: ConformOutcome.built,
      samples: Float32List(96000)..fillRange(0, 96000, 0.5),
      channels: 1,
      sampleRate: 48000,
      frames: 96000,
    ),
    log: (_) {},
  );

  Future<bool> waitFor(bool Function() check) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (check()) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return check();
  }

  test('a viewer\'s sound comes out as loud as it was started', () async {
    final store = steadyTone();
    store.resultFor(tone);
    await pumpEventQueue();
    expect(store.durationSecondsFor(tone), 2, reason: 'fixture: conformed');

    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: 48000, channels: 2, useNullBackend: true),
      greaterThan(0),
    );
    final sound = ViewerSound(
      conformStore: store,
      resolveDevice: () => QaAudioDevice.instance,
    );

    /// The bus's peak once the device has mixed a good way into the tone.
    Future<double> peakAt(double gain) async {
      expect(sound.play(tone, gain: gain), isTrue);
      expect(
        await waitFor(() => device.positionSamples > 9600),
        isTrue,
        reason: 'fixture: the device is running',
      );
      final peak = device.peakFor(0);
      sound.stop();
      return peak;
    }

    final full = await peakAt(1);
    expect(full, greaterThan(0.1), reason: 'fixture: the tone reaches the bus');
    expect(await peakAt(0.5), closeTo(full / 2, full * 0.02));
    expect(await peakAt(0.25), closeTo(full / 4, full * 0.02));
    expect(await peakAt(0), 0, reason: 'muted is silence, still running');
  }, skip: skip);
}
