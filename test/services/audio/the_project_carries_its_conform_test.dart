import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

/// 🚨★★★**WHAT `conform-in-project` = always ACTUALLY BUYS.**
///
/// 유저 2026-08-30 chose to carry conforms inside the `.anicel`: 「일단
/// 넣은채로 통일하고 추후 진행하면서 옵션으로 뺄지 판단. 레이트 변경 등
/// 죽은파일만 깔끔하게 잘 걷어낼것」.
///
/// The payoff is one thing and it is measurable: on a machine whose cache
/// is empty, the sound plays without being decoded and resampled first.
/// ⛔So「it opens」is not the assertion. These COUNT DECODES, because a
/// pipeline that quietly re-decoded would produce identical audio and have
/// thrown the entire feature away.
///
/// The other half is that carrying is not trusting: a carried conform
/// faces the same source-fingerprint and settings checks a locally built
/// one does, because deciding staleness twice is how two answers drift.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel_carried_conform');
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

  Float32List ramp(int frames) {
    final out = Float32List(frames);
    for (var index = 0; index < frames; index += 1) {
      out[index] = (index % 4096) / 4096.0 - 0.5;
    }
    return out;
  }

  /// A source file the fake decoder below understands.
  String writeSource(String name, {int rate = 48000, int frames = 90000}) {
    final path = '${root.path}/$name'.replaceAll(r'\', '/');
    File(path).writeAsBytesSync(
      encodeConformWav(samples: ramp(frames), channels: 1, sampleRate: rate),
    );
    return path;
  }

  /// A pipeline whose decoder reads our own conform WAVs, and COUNTS how
  /// many times it was asked to.
  ({AudioConformPipeline pipeline, List<int> decodes}) pipelineAt(
    int projectSampleRate,
  ) {
    final decodes = <int>[];
    return (
      decodes: decodes,
      pipeline: AudioConformPipeline(
        projectSampleRate: projectSampleRate,
        decode: (bytes) {
          decodes.add(bytes.length);
          final audio = decodeConformWav(bytes);
          return (
            samples: audio.samples,
            channels: audio.channels,
            sampleRate: audio.sampleRate,
          );
        },
        // Identity: this file is about what gets decoded, not about the
        // filter. The resampler has its own parity pins.
        resample:
            ({
              required samples,
              required channels,
              required inputRate,
              required outputRate,
            }) => samples,
      ),
    );
  }

  /// The conform bytes as the project would CARRY them — read from the
  /// cache exactly as the save streams them, framed or not.
  MediaByteSource carriedFrom(String conformOnDisk) => MediaAppFileBytes(
    path: conformOnDisk,
    framed: mediaEntryIsFramed(conformOnDisk),
  );

  test('🚨a carried conform is restored instead of decoded again', () {
    final source = writeSource('대사.wav');
    final firstCache = '${root.path}/cache-a/대사.wav.aaaa1111.wav'.replaceAll(
      r'\',
      '/',
    );

    final first = pipelineAt(48000);
    final built = first.pipeline.ensureConform(
      sourcePath: source,
      conformPath: firstCache,
    );
    expect(built.outcome, ConformOutcome.built);
    expect(first.decodes, hasLength(1), reason: 'fixture: it was built');
    final carried = carriedFrom(built.conformPath!);

    // Another machine: same project, same sound, EMPTY cache.
    final secondCache = '${root.path}/cache-b/대사.wav.aaaa1111.wav'.replaceAll(
      r'\',
      '/',
    );
    final second = pipelineAt(48000);
    final opened = second.pipeline.ensureConform(
      sourcePath: source,
      conformPath: secondCache,
      carriedConform: carried,
    );

    expect(opened.outcome, ConformOutcome.reused);
    expect(
      second.decodes,
      isEmpty,
      reason:
          '⛔THE WHOLE POINT. A decode here means the project carried '
          'hundreds of megabytes and bought nothing.',
    );
    expect(
      opened.conformPath,
      built.conformPath!.replaceFirst('cache-a', 'cache-b'),
      reason: 'restored under the name its framedness calls for',
    );
    expect(opened.samples, isNotNull);
    expect(opened.frames, built.frames);
  });

  test('⛔but it is not TRUSTED: a source that changed rebuilds', () {
    final source = writeSource('대사.wav');
    final firstCache = '${root.path}/cache-a/대사.wav.aaaa1111.wav'.replaceAll(
      r'\',
      '/',
    );
    final built = pipelineAt(
      48000,
    ).pipeline.ensureConform(sourcePath: source, conformPath: firstCache);
    final carried = carriedFrom(built.conformPath!);

    // The user replaced the recording between the two machines.
    File(source).writeAsBytesSync(
      encodeConformWav(samples: ramp(45000), channels: 1, sampleRate: 48000),
    );

    final second = pipelineAt(48000);
    final opened = second.pipeline.ensureConform(
      sourcePath: source,
      conformPath: '${root.path}/cache-b/대사.wav.aaaa1111.wav'.replaceAll(
        r'\',
        '/',
      ),
      carriedConform: carried,
    );
    expect(opened.outcome, ConformOutcome.built);
    expect(
      second.decodes,
      hasLength(1),
      reason:
          'the carried one faces the same fingerprint check a local one '
          'does — deciding staleness twice is how two answers drift',
    );
    expect(opened.frames, 45000);
  });

  test('⛔nor at another RATE: the settings check still runs', () {
    final source = writeSource('대사.wav', rate: 44100);
    final built = pipelineAt(44100).pipeline.ensureConform(
      sourcePath: source,
      conformPath: '${root.path}/cache-a/대사.wav.bbbb2222.wav'.replaceAll(
        r'\',
        '/',
      ),
    );
    expect(built.sampleRate, 44100);

    // The project's rate moved. `ConformCacheLayout` keys on it, so this
    // is a different address — but the carried entry is named by the pool
    // path alone, so the STALE bytes can still arrive here. They must not
    // be believed.
    final second = pipelineAt(48000);
    final opened = second.pipeline.ensureConform(
      sourcePath: source,
      conformPath: '${root.path}/cache-b/대사.wav.cccc3333.wav'.replaceAll(
        r'\',
        '/',
      ),
      carriedConform: carriedFrom(built.conformPath!),
    );
    expect(opened.outcome, ConformOutcome.built);
    expect(opened.sampleRate, 48000);
    expect(second.decodes, hasLength(1));
  });

  test('framed bytes are carried and restored AS THEY ARE', () {
    final compressor = QaCelCompressor.instance;
    if (compressor == null || !compressor.isSupported) {
      markTestSkipped('no engine on this run');
      return;
    }
    final source = writeSource('대사.wav', frames: 400000);
    final built = pipelineAt(48000).pipeline.ensureConform(
      sourcePath: source,
      conformPath: '${root.path}/cache-a/대사.wav.aaaa1111.wav'.replaceAll(
        r'\',
        '/',
      ),
    );
    expect(
      built.conformPath,
      endsWith(mediaFramedEntrySuffix),
      reason: 'fixture: PCM compresses, so the cache write framed it',
    );
    final carriedBytes = File(built.conformPath!).readAsBytesSync();

    final second = pipelineAt(48000);
    final opened = second.pipeline.ensureConform(
      sourcePath: source,
      conformPath: '${root.path}/cache-b/대사.wav.aaaa1111.wav'.replaceAll(
        r'\',
        '/',
      ),
      carriedConform: carriedFrom(built.conformPath!),
    );
    expect(second.decodes, isEmpty);
    expect(opened.conformPath, endsWith(mediaFramedEntrySuffix));
    expect(
      File(opened.conformPath!).readAsBytesSync(),
      carriedBytes,
      reason:
          '⛔byte for byte. Decompressing a carried conform only to '
          'compress it again would burn the reason it was compressed.',
    );
  });

  test('a restore that cannot be written costs a decode, never the sound', () {
    final source = writeSource('대사.wav');
    final built = pipelineAt(48000).pipeline.ensureConform(
      sourcePath: source,
      conformPath: '${root.path}/cache-a/대사.wav.aaaa1111.wav'.replaceAll(
        r'\',
        '/',
      ),
    );
    // A file where the cache directory should be: nothing can be created
    // under it, which is the shape of an unplugged drive or a revoked
    // sandbox scope.
    final blocker = '${root.path}/blocked'.replaceAll(r'\', '/');
    File(blocker).writeAsBytesSync(const [0]);

    final second = pipelineAt(48000);
    final opened = second.pipeline.ensureConform(
      sourcePath: source,
      conformPath: '$blocker/nested/대사.wav.aaaa1111.wav',
      carriedConform: carriedFrom(built.conformPath!),
    );
    expect(
      opened.isUsable,
      isTrue,
      reason: 'the restore is an optimisation; the decode is the fallback',
    );
    expect(second.decodes, hasLength(1));
    expect(opened.samples, isNotNull);
  });
}
