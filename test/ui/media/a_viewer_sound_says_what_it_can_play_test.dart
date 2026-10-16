import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_audio_device.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/media/viewer_sound.dart';
import 'package:anicel/src/ui/playback/audio_windowed_upload.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/temp_dir.dart';

/// playback-waits-for-its-sound (유저 2026-10-16, se-fallback-opens-the-
/// original-path-Q2: 「소리가 준비될 때까지 기다린다」 · 「재생못하거나 하는
/// 상황에선 제대로 메시지라던가 뭔가 표시」): what the media viewer's sound
/// answers a press — on the output, on its way (and the run waits for it,
/// `MediaRun`), or never (and the run goes on without it). ↩️A sound not
/// ready stood down silently, and a sound alone did not play at all.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  late Directory directory;

  setUp(() async {
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
    directory = await Directory.systemTemp.createTemp('qa-viewer-answers');
  });

  tearDown(() {
    try {
      QaAudioDevice.instance?.close();
    } on Object {
      // A device that never opened is fine to "close".
    }
    QaAudioDevice.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    deleteTempQuietly(directory);
  });

  test('🚨a sound whose conform is under way is on its way — and once it '
      'lands as one that will never play, it is refused', () async {
    final conform = Completer<ConformResult>();
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) => conform.future,
      log: (_) {},
    );
    addTearDown(store.dispose);
    final sound = ViewerSound(
      conformStore: store,
      resolveDevice: () => QaAudioDevice.instance,
    );

    expect(sound.play('voice.wav'), isA<OutputComing>());
    expect(sound.isCarrying, isFalse);

    conform.complete(
      const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'fixture',
      ),
    );
    await pumpEventQueue();
    expect(sound.play('voice.wav'), isA<OutputRefused>());
    expect(sound.isCarrying, isFalse);
  });

  test('🚨a sound whose stream will not open is refused — not carried as '
      'silence', () async {
    const rate = 8000;
    const frames = rate * (conformStreamingThresholdSeconds + 1);
    final device = QaAudioDevice.instance!;
    expect(
      device.open(sampleRate: rate, channels: 2, useNullBackend: true),
      rate,
    );
    final conformPath = '${directory.path}/broken.wav.wav';
    File(conformPath).writeAsBytesSync(const [1, 2, 3, 4]);
    final store = AudioConformStore(
      resolveConformPath: (_) => conformPath,
      projectSampleRate: rate,
      runner: (request) async => ConformResult(
        outcome: ConformOutcome.built,
        conformBytes: mediaAppFileSource(conformPath),
        channels: 1,
        sampleRate: rate,
        frames: frames,
      ),
      log: (_) {},
    );
    addTearDown(store.dispose);
    store.resultFor('broken.wav');
    await pumpEventQueue();
    expect(store.isStreaming('broken.wav'), isTrue, reason: 'fixture');
    final sound = ViewerSound(
      conformStore: store,
      resolveDevice: () => QaAudioDevice.instance,
    );
    addTearDown(sound.stop);

    expect(sound.play('broken.wav'), isA<OutputRefused>());
    expect(sound.isCarrying, isFalse);
  }, skip: skip);
}
