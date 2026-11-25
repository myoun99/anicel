import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🚨A CONFORM TELLS HOW FAR IT HAS READ THE FILE as it goes — the bytes
/// read of the bytes to read (F-608-Q2), its decoder's reads counted by the
/// engine (🗣️유저 11-23, decoder-reads-skip-the-percent-Q2 「디코더가 읽은
/// 바이트를 센다」) — across the worker it runs on, to whoever waits for its
/// sound: the import window's percent while a sound is made. ↩️The decoder
/// read the file where the window could not see it: a 910 MB movie on the
/// cloud stood 47 s at one number (🔬저장 11-23).
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-conform-read');
  });

  tearDown(() {
    debugWorkersRunHere = true;
    deleteTempQuietly(directory);
  });

  /// Four seconds of a mono sound on disk, at the project's rate: many of
  /// the conform's windows.
  ConformRequest aSound({void Function(double fraction)? onReading}) {
    final pcm = Int16List(48000 * 4);
    for (var index = 0; index < pcm.length; index += 1) {
      pcm[index] = (index % 200 - 100) * 90;
    }
    final path = '${directory.path}/a.wav';
    File(path).writeAsBytesSync(
      wav16Bytes(pcm, sampleRate: 48000, channels: 1),
    );
    return ConformRequest(
      sourcePath: path,
      conformPath: null,
      onReading: onReading,
    );
  }

  test('a conform on its worker tells how far it has read: rising, the '
      "decoder's half and then the fingerprint's, to the whole", () async {
    final heard = <double>[];
    // The road production takes: a real isolate, the engine's decoder.
    debugWorkersRunHere = false;

    final result = await runConformInIsolate(aSound(onReading: heard.add));

    expect(result.isUsable, isTrue, reason: result.error);
    expect(heard, isNotEmpty);
    for (var i = 1; i < heard.length; i += 1) {
      expect(heard[i], greaterThanOrEqualTo(heard[i - 1]), reason: '$heard');
    }
    expect(heard.where((f) => f > 0 && f <= 0.5), isNotEmpty,
        reason: "the decoder's reads: $heard");
    expect(heard.where((f) => f > 0.5 && f < 1), isNotEmpty,
        reason: "the fingerprint's reads: $heard");
    expect(heard.last, 1);
  });

  test('the decode of a source read before (its fingerprint first) is the '
      'second half', () {
    final heard = <double>[];
    final request = aSound();
    AudioConformPipeline pipeline({void Function(double)? onRead}) =>
        AudioConformPipeline(
          decode: openAudioSource,
          resample: (
              {required channels, required inputRate, required outputRate}) =>
              throw StateError('the sound is at the project rate'),
          onRead: onRead,
        );
    final made = pipeline().ensureConform(
      sourcePath: request.sourcePath,
      conformPath: '${directory.path}/a.conform',
    );
    expect(made.isUsable, isTrue, reason: made.error);
    // The file touched: the stat no longer says it is the same, so the
    // fingerprint is read first, finds it so, and the conform is reused.
    final file = File(request.sourcePath);
    file.setLastModifiedSync(
      file.lastModifiedSync().add(const Duration(seconds: 5)),
    );

    pipeline(onRead: heard.add).ensureConform(
      sourcePath: request.sourcePath,
      conformPath: '${directory.path}/a.conform',
    );

    expect(heard, isNotEmpty);
    expect(heard.every((f) => f <= 0.5), isTrue,
        reason: 'the fingerprint, the first of two reads: $heard');
    expect(heard.last, 0.5);
  });

  test('whoever waits for the sound hears how far its conform has read — '
      'one who comes once it began hears the last word at once', () async {
    final told = Completer<void Function(double)>();
    final landing = Completer<ConformResult>();
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) {
        told.complete(request.onReading);
        return landing.future;
      },
    );
    addTearDown(store.dispose);
    final first = <double>[];
    final second = <double>[];

    final waited = store.ensurePeaksFor('a.wav', onReading: first.add);
    final tell = await told.future;
    tell(0.25);
    final joined = store.ensurePeaksFor('a.wav', onReading: second.add);
    tell(0.5);
    landing.complete(const ConformResult(outcome: ConformOutcome.undecodable));
    await Future.wait([waited, joined]);
    tell(0.75);

    expect(first, [0.25, 0.5]);
    expect(second, [0.25, 0.5]);
  });
}
