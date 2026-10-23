import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/audio/conform_pcm_stream.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/audio/sound_cannot_play.dart';
import '../../helpers/temp_dir.dart';

/// playback-says-the-sound-it-cannot-play (유저 2026-10-17: 「이유(형식 ·
/// 파일 없음 · 출력)는 툴팁으로」): the conform store is the one place a run
/// and a sound's cell ask why a sound cannot be played
/// ([AudioConformStore.cannotPlayAt]) — each reason here is one a cell says.
void main() {
  ConformResult usable() => ConformResult(
    outcome: ConformOutcome.built,
    conformBytes: mediaAppFileSource('/tmp/conformed/a.wav.wav'),
    peaks: AudioPeaks(bucketsPerSecond: 80, peaks: Float32List.fromList([1])),
    samples: Float32List.fromList([0.1, 0.2, 0.3, 0.4]),
    channels: 2,
    sampleRate: 48000,
    frames: 2,
  );

  /// What [cannotPlayAt] says of a sound whose conform answers [result],
  /// asked once it has landed — and, first, while it is under way.
  Future<(SoundCannotPlay?, SoundCannotPlay?)> says(
    ConformResult result, {
    int sampleRate = 48000,
    bool conversionFails = false,
  }) async {
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => result,
      resampleRunner: conversionFails
          ? (request) async => throw StateError('fixture')
          : null,
      log: (_) {},
    );
    addTearDown(store.dispose);
    final underWay = store.cannotPlayAt('a.wav', sampleRate);
    for (var turn = 0; turn < 4; turn += 1) {
      await pumpEventQueue();
      store.cannotPlayAt('a.wav', sampleRate);
    }
    return (underWay, store.cannotPlayAt('a.wav', sampleRate));
  }

  ConformResult failed(ConformOutcome outcome) =>
      ConformResult(outcome: outcome, error: 'fixture');

  test('a sound that plays says nothing — and nothing while it is on its '
      'way', () async {
    expect(await says(usable()), (null, null));
  });

  final reasons = <String, (ConformOutcome, SoundCannotPlay)>{
    'a file that is not there': (
      ConformOutcome.sourceMissing,
      SoundCannotPlay.missing,
    ),
    'a file not read yet (a cloud copy coming down)': (
      ConformOutcome.sourceUnreadable,
      SoundCannotPlay.notReadYet,
    ),
    'a format no decoder reads': (
      ConformOutcome.undecodable,
      SoundCannotPlay.format,
    ),
    'a conversion that failed': (
      ConformOutcome.writeFailed,
      SoundCannotPlay.conform,
    ),
  };
  for (final MapEntry(key: name, value: (outcome, why)) in reasons.entries) {
    test('$name says so — once it has landed, not while it is on its way',
        () async {
      final (underWay, landed) = await says(failed(outcome));
      expect(underWay, isNull, reason: 'a run waits for it while it comes');
      expect(landed, why);
    });
  }

  test('a sound not brought to the output\'s rate says the rate — and '
      'plays at the project\'s', () async {
    expect(
      (await says(usable(), sampleRate: 44100, conversionFails: true)).$2,
      SoundCannotPlay.deviceRate,
    );
    expect((await says(usable(), sampleRate: 48000)).$2, isNull);
  });

  group('a streamed conform', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('qa-cannot-play');
    });
    tearDown(() => deleteTempQuietly(directory));

    /// A conform long enough to stream, at a tiny rate that is the
    /// project's — `audio_conform_store_test`'s fixture.
    Future<AudioConformStore> streamed() async {
      const sampleRate = 100;
      const frames = sampleRate * conformStreamingThresholdSeconds + 50;
      final conformPath = '${directory.path}/long.wav.wav';
      File(conformPath).writeAsBytesSync(
        encodeConform(
          samples: Float32List(frames),
          channels: 1,
          sampleRate: sampleRate,
        ),
      );
      final store = AudioConformStore(
        resolveConformPath: (_) => conformPath,
        projectSampleRate: sampleRate,
        runner: (request) async => ConformResult(
          outcome: ConformOutcome.built,
          conformBytes: mediaAppFileSource(conformPath),
          peaks: AudioPeaks(
            bucketsPerSecond: 80,
            peaks: Float32List.fromList([1]),
          ),
          channels: 1,
          sampleRate: sampleRate,
          frames: frames,
        ),
        log: (_) {},
      );
      addTearDown(store.dispose);
      store.resultFor('long.wav');
      await pumpEventQueue();
      expect(store.isStreaming('long.wav'), isTrue, reason: 'premise');
      return store;
    }

    test('plays at the project\'s rate, and says the rate at another',
        () async {
      final store = await streamed();
      expect(store.cannotPlayAt('long.wav', 100), isNull);
      expect(store.cannotPlayAt('long.wav', 48000), SoundCannotPlay.deviceRate);
    });

    test('says the conversion when its bytes cannot be read', () async {
      final store = await streamed();
      File('${directory.path}/long.wav.wav').writeAsBytesSync([0, 1, 2]);
      expect(store.cannotPlayAt('long.wav', 100), SoundCannotPlay.conform);
    });
  });
}
