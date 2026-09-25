import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaCarry;
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_conform_runner.dart';
import 'package:anicel/src/services/audio/audio_peaks_extractor.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import '../../helpers/temp_dir.dart';

ConformResult _usableResult() => ConformResult(
  outcome: ConformOutcome.built,
  conformBytes: mediaAppFileSource('/tmp/conformed/a.wav.wav'),
  peaks: AudioPeaks(bucketsPerSecond: 80, peaks: Float32List.fromList([1.0])),
  samples: Float32List.fromList([0.1, 0.2, 0.3, 0.4]),
  channels: 2,
  sampleRate: 48000,
  frames: 2,
);

void main() {
  test('kicks ONE conform per path, caches the landed result and notifies '
      'listeners', () async {
    final requests = <ConformRequest>[];
    final store = AudioConformStore(
      resolveConformPath: (path) => '/tmp/conformed/$path.wav',
      runner: (request) async {
        requests.add(request);
        return _usableResult();
      },
      log: (_) {},
    );
    var notified = 0;
    store.addListener(() => notified += 1);

    expect(store.resultFor('a.wav'), isNull);
    expect(store.resultFor('a.wav'), isNull); // pending — no second kick
    await pumpEventQueue();

    expect(requests, hasLength(1));
    expect(requests.single.conformPath, '/tmp/conformed/a.wav.wav');
    expect(notified, 1);
    expect(store.resultFor('a.wav')?.isUsable, isTrue);
    expect(store.samplesFor('a.wav'), hasLength(4));
    expect(store.peaksFor('a.wav')?.peaks, hasLength(1));
    // Duration comes from the EXACT sample count, not the peaks buckets.
    expect(store.durationSecondsFor('a.wav'), 2 / 48000);
    store.dispose();
  });

  test('undecodable is a definitive answer: no retry, blank waveform, '
      'no length — the platform players still carry playback', () async {
    var runs = 0;
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async {
        runs += 1;
        return const ConformResult(
          outcome: ConformOutcome.undecodable,
          error: 'no decoder recognized this file',
        );
      },
      log: (_) {},
    );

    store.resultFor('voice.xyz');
    await pumpEventQueue();
    expect(runs, 1);
    expect(store.resultFor('voice.xyz')?.outcome, ConformOutcome.undecodable);
    expect(store.peaksFor('voice.xyz'), isNull);
    expect(store.durationSecondsFor('voice.xyz'), isNull);
    store.resultFor('voice.xyz');
    await pumpEventQueue();
    expect(runs, 1, reason: 'the same bytes will not decode differently');
    store.dispose();
  });

  test('transient failures retry on a fresh lookup after the delay, up to '
      'the attempt budget', () async {
    var runs = 0;
    var now = DateTime(2026, 7, 21);
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async {
        runs += 1;
        return const ConformResult(
          outcome: ConformOutcome.sourceMissing,
          error: 'the source file is missing',
        );
      },
      now: () => now,
      log: (_) {},
    );

    store.resultFor('gone.wav');
    await pumpEventQueue();
    expect(runs, 1);

    // Inside the delay: gated.
    store.resultFor('gone.wav');
    await pumpEventQueue();
    expect(runs, 1);

    // Past the delay: retries — twice more, then the budget is spent.
    now = now.add(const Duration(seconds: 3));
    store.resultFor('gone.wav');
    await pumpEventQueue();
    expect(runs, 2);
    now = now.add(const Duration(seconds: 3));
    store.resultFor('gone.wav');
    await pumpEventQueue();
    expect(runs, 3);
    now = now.add(const Duration(seconds: 3));
    store.resultFor('gone.wav');
    await pumpEventQueue();
    expect(runs, 3);

    // invalidate() grants a fresh budget.
    store.invalidate('gone.wav');
    store.resultFor('gone.wav');
    await pumpEventQueue();
    expect(runs, 4);
    store.dispose();
  });

  test('samplesAtRate: the project rate is the samples themselves; another '
      'rate kicks ONE async conversion and serves it once landed', () async {
    final resampled = <(int, int)>[];
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => _usableResult(),
      resampleRunner: (request) async {
        resampled.add((request.inputRate, request.outputRate));
        return Float32List.fromList([0.9]);
      },
      log: (_) {},
    );
    store.resultFor('a.wav');
    await pumpEventQueue();

    // Project rate: the conform PCM itself, no conversion.
    expect(store.samplesAtRate('a.wav', 48000), hasLength(4));
    expect(resampled, isEmpty);

    // Device rate mismatch: null now (the transport stands down this run),
    // conversion kicked once, served after it lands.
    expect(store.samplesAtRate('a.wav', 44100), isNull);
    expect(store.samplesAtRate('a.wav', 44100), isNull);
    await pumpEventQueue();
    expect(resampled, [(48000, 44100)]);
    expect(store.samplesAtRate('a.wav', 44100), hasLength(1));
    store.dispose();
  });

  test('a project-rate change makes cached entries stale on their own — '
      'undo and redo self-heal without hooks', () async {
    var projectRate = 48000;
    final requested = <int>[];
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      resolveProjectSampleRate: () => projectRate,
      runner: (request) async {
        requested.add(request.projectSampleRate);
        return ConformResult(
          outcome: ConformOutcome.built,
          samples: Float32List(4),
          channels: 1,
          sampleRate: request.projectSampleRate,
          frames: 4,
        );
      },
      log: (_) {},
    );

    store.resultFor('a.wav');
    await pumpEventQueue();
    expect(store.resultFor('a.wav')?.sampleRate, 48000);

    projectRate = 44100; // the setting moved (or an undo moved it back)
    expect(
      store.resultFor('a.wav'),
      isNull,
      reason: 'the 48k entry is stale by definition — re-kicked',
    );
    await pumpEventQueue();
    expect(store.resultFor('a.wav')?.sampleRate, 44100);
    expect(requested, [48000, 44100]);
    store.dispose();
  });

  test('🚨a path the pool names ANOTHER carry at is stale on its own — the '
      'sound of the first carry does not answer for the second', () async {
    MediaCarry? carry = (poolPath: 'a.wav', token: 'c1');
    final conformedAs = <String?>[];
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      resolveCarry: (_) => carry,
      runner: (request) async {
        conformedAs.add(carry?.token);
        return ConformResult(
          outcome: ConformOutcome.built,
          samples: Float32List(4),
          channels: 1,
          sampleRate: request.projectSampleRate,
          frames: conformedAs.length,
        );
      },
      log: (_) {},
    );

    store.resultFor('a.wav');
    await pumpEventQueue();
    expect(store.resultFor('a.wav')?.frames, 1);

    carry = (poolPath: 'a.wav', token: 'c2'); // removed, carried again
    expect(store.resultFor('a.wav'), isNull, reason: 're-kicked');
    // (Whether it STREAMS is asked of a streaming entry — below, with the
    // streaming policy; this one never streamed, so it could not say.)
    await pumpEventQueue();
    expect(store.resultFor('a.wav')?.frames, 2);

    carry = (poolPath: 'a.wav', token: 'c1'); // and undone back
    expect(store.samplesFor('a.wav'), isNull);
    await pumpEventQueue();
    expect(store.resultFor('a.wav')?.frames, 3);

    carry = null; // left for a link to the file itself
    expect(store.durationSecondsFor('a.wav'), isNull);
    await pumpEventQueue();
    expect(conformedAs, ['c1', 'c2', 'c1', null]);
    store.dispose();
  });

  test('with no carry to ask, a path keeps its conform as it always did',
      () async {
    var runs = 0;
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async {
        runs += 1;
        return _usableResult();
      },
      log: (_) {},
    );
    store.resultFor('a.wav');
    await pumpEventQueue();
    store.resultFor('a.wav');
    await pumpEventQueue();
    expect(runs, 1);
    store.dispose();
  });

  test('a rate conversion lands only on the entry it was made from',
      () async {
    MediaCarry? carry = (poolPath: 'a.wav', token: 'c1');
    final resampled = Completer<Float32List>();
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      resolveCarry: (_) => carry,
      runner: (request) async => _usableResult(),
      resampleRunner: (request) => resampled.future,
      log: (_) {},
    );
    store.resultFor('a.wav');
    await pumpEventQueue();
    expect(store.samplesAtRate('a.wav', 44100), isNull, reason: 'kicked');

    carry = (poolPath: 'a.wav', token: 'c2');
    store.resultFor('a.wav');
    await pumpEventQueue();
    resampled.complete(Float32List.fromList([9, 9, 9, 9]));
    await pumpEventQueue();

    expect(
      store.samplesAtRate('a.wav', 44100),
      isNot(Float32List.fromList([9, 9, 9, 9])),
      reason: 'the first carry\'s conversion must not play for the second',
    );
    store.dispose();
  });

  test('a conform that lands after the pool moved to another carry is the '
      'FIRST carry\'s — it answers for nothing', () async {
    MediaCarry? carry = (poolPath: 'a.wav', token: 'c1');
    final gate = Completer<void>();
    var runs = 0;
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      resolveCarry: (_) => carry,
      runner: (request) async {
        runs += 1;
        if (runs == 1) {
          await gate.future;
        }
        return _usableResult();
      },
      log: (_) {},
    );
    store.resultFor('a.wav'); // kicked for c1, and still running
    await pumpEventQueue();
    carry = (poolPath: 'a.wav', token: 'c2'); // removed, carried again
    gate.complete();
    await pumpEventQueue();

    expect(
      store.resultFor('a.wav'),
      isNull,
      reason:
          'made of c1\'s bytes — the carry is the one read with them, not '
          'the one the pool names when the result lands',
    );
    await pumpEventQueue();
    expect(runs, 2, reason: 'kicked again, for c2');
    store.dispose();
  });

  test('a carry changed under a FAILURE lets it go — the first carry\'s '
      'missing file does not stand for the second', () async {
    MediaCarry? carry = (poolPath: 'gone.wav', token: 'c1');
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      resolveCarry: (_) => carry,
      runner: (request) async => const ConformResult(
        outcome: ConformOutcome.sourceMissing,
        error: 'the source file is missing',
      ),
      log: (_) {},
    );
    store.resultFor('gone.wav');
    await pumpEventQueue();
    expect(store.failureFor('gone.wav'), isNotNull, reason: 'the premise');

    carry = (poolPath: 'gone.wav', token: 'c2');

    expect(store.failureFor('gone.wav'), isNull);
    store.dispose();
  });

  test('warmPaths kicks every unknown path once', () async {
    final seen = <String>[];
    final store = AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async {
        seen.add(request.sourcePath);
        return _usableResult();
      },
      log: (_) {},
    );
    store.warmPaths(['a.wav', 'b.wav']);
    store.warmPaths(['a.wav']); // pending — not kicked again
    await pumpEventQueue();
    expect(seen, ['a.wav', 'b.wav']);
    store.dispose();
  });

  group('streaming policy (AUDIO-PRO R6)', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('qa-store-stream');
    });

    tearDown(() => deleteTempQuietly(directory));

    /// A conform WAV on disk plus the runner result describing it, LONGER
    /// than the streaming threshold (a tiny sample rate keeps the fixture
    /// small — the threshold is in seconds, and the policy reads the
    /// result's own rate).
    (String, ConformResult) longConform() {
      const sampleRate = 100;
      const frames =
          sampleRate * AudioConformStore.streamingThresholdSeconds + 50;
      final samples = Float32List(frames);
      for (var index = 0; index < frames; index += 1) {
        samples[index] = (index % 100) / 100.0;
      }
      final conformPath = '${directory.path}/long.wav.wav';
      File(conformPath).writeAsBytesSync(
        encodeConform(samples: samples, channels: 1, sampleRate: sampleRate),
      );
      return (
        conformPath,
        ConformResult(
          outcome: ConformOutcome.built,
          conformBytes: mediaAppFileSource(conformPath),
          peaks: AudioPeaks(
            bucketsPerSecond: 80,
            peaks: Float32List.fromList([1.0]),
          ),
          samples: samples,
          channels: 1,
          sampleRate: sampleRate,
          frames: frames,
        ),
      );
    }

    test('past the threshold the PCM is dropped: length and peaks answer, '
        'samples stream from disk', () async {
      final (conformPath, result) = longConform();
      final store = AudioConformStore(
        resolveConformPath: (_) => conformPath,
        // The fixture's tiny rate IS the project rate — otherwise the
        // entry reads as stale (a rate change) and gets re-kicked.
        projectSampleRate: 100,
        runner: (request) async => result,
        log: (_) {},
      );
      store.resultFor('long.wav');
      await pumpEventQueue();

      expect(store.isStreaming('long.wav'), isTrue);
      expect(
        store.samplesFor('long.wav'),
        isNull,
        reason: 'the whole point: no resident PCM for a long file',
      );
      expect(
        store.peaksFor('long.wav')?.peaks,
        isNotEmpty,
        reason: 'the waveform must not disappear with the samples',
      );
      expect(store.durationSecondsFor('long.wav'), result.frames / 100);

      final reader = store.streamReaderFor('long.wav');
      expect(reader, isNotNull);
      expect(reader!.length, result.frames);
      final window = reader.readWindow(500, 100);
      for (var index = 0; index < 100; index += 1) {
        expect(
          window.samples[index],
          closeTo(result.samples![500 + index], 1e-4),
          reason: 'streamed sample ${500 + index} diverged from the decode',
        );
      }
      expect(
        identical(store.streamReaderFor('long.wav'), reader),
        isTrue,
        reason: 'one cached reader, not one open file per read',
      );

      store.invalidate('long.wav');
      expect(store.isStreaming('long.wav'), isFalse);
      store.dispose();
    });

    test('🚨a carry changed under a STREAMING entry lets it go at whatever is '
        'asked first — the stream and its reader are the first carry\'s',
        () async {
      final (conformPath, result) = longConform();
      MediaCarry? carry;
      Future<AudioConformStore> streaming() async {
        carry = (poolPath: 'long.wav', token: 'c1');
        final store = AudioConformStore(
          resolveConformPath: (_) => conformPath,
          projectSampleRate: 100,
          resolveCarry: (_) => carry,
          runner: (request) async => result,
          log: (_) {},
        );
        addTearDown(store.dispose);
        store.resultFor('long.wav');
        await pumpEventQueue();
        expect(store.isStreaming('long.wav'), isTrue, reason: 'the premise');
        expect(store.streamReaderFor('long.wav'), isNotNull);
        return store;
      }

      final asked = await streaming();
      carry = (poolPath: 'long.wav', token: 'c2'); // removed, carried again
      expect(asked.isStreaming('long.wav'), isFalse);

      final read = await streaming();
      carry = (poolPath: 'long.wav', token: 'c2');
      expect(
        read.streamReaderFor('long.wav'),
        isNull,
        reason: 'the reader cached for c1 does not stream c2',
      );
    });

    test('a SHORT conform stays resident and a memory-only long one does '
        'too (nothing on disk to stream from)', () async {
      final store = AudioConformStore(
        resolveConformPath: (_) => null,
        // No conformPath: unsaved project — even a huge decode stays
        // resident because there is no disk copy of record.
        runner: (request) async => ConformResult(
          outcome: ConformOutcome.built,
          samples: Float32List(
            48000 * (AudioConformStore.streamingThresholdSeconds + 5),
          ),
          channels: 1,
          sampleRate: 48000,
          frames: 48000 * (AudioConformStore.streamingThresholdSeconds + 5),
        ),
        log: (_) {},
      );
      store.resultFor('huge-unsaved.wav');
      await pumpEventQueue();
      expect(store.isStreaming('huge-unsaved.wav'), isFalse);
      expect(store.samplesFor('huge-unsaved.wav'), isNotNull);
      store.dispose();
    });
  });
}
