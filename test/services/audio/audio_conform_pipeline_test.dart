import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_resampler_reference.dart';
import 'package:anicel/src/services/audio/conform_wav_codec.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa_conform_');
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

  Float32List ramp(int frames, int channels) {
    final out = Float32List(frames * channels);
    for (var index = 0; index < out.length; index += 1) {
      out[index] = (index % 200) / 200.0 - 0.5;
    }
    return out;
  }

  /// A pipeline whose decoder just reads our own conform WAVs — enough to
  /// exercise every decision without a native binary.
  AudioConformPipeline pipelineFor({
    int projectSampleRate = 48000,
    List<String>? resampleLog,
  }) {
    return AudioConformPipeline(
      projectSampleRate: projectSampleRate,
      decode: (bytes) {
        try {
          final audio = decodeConformWav(bytes);
          return (
            samples: audio.samples,
            channels: audio.channels,
            sampleRate: audio.sampleRate,
          );
        } on Object {
          return null;
        }
      },
      resample:
          ({
            required samples,
            required channels,
            required inputRate,
            required outputRate,
          }) {
            resampleLog?.add('$inputRate→$outputRate');
            return resampleAudioReference(
              samples: samples,
              channels: channels,
              inputRate: inputRate,
              outputRate: outputRate,
            ).samples;
          },
    );
  }

  String writeSource(String name, {int rate = 48000, int channels = 1}) {
    final path = '${temp.path}/$name';
    File(path).writeAsBytesSync(
      encodeConformWav(
        samples: ramp(2400, channels),
        channels: channels,
        sampleRate: rate,
      ),
    );
    return path;
  }

  group('layout', () {
    test('assets sit beside the project, not inside it', () {
      const layout = ProjectAssetLayout('/work/내작업/프로젝트.anicel');
      expect(layout.assetsDirectory, '/work/내작업/프로젝트.assets');
      expect(layout.mediaDirectory, '/work/내작업/프로젝트.assets/Media');
      expect(
        layout.conformedDirectory,
        '/work/내작업/프로젝트.assets/Conformed',
      );
    });

    test('the conform path is derived from the media name, not recorded', () {
      // Nothing to keep in sync, and project.json stays small.
      const layout = ProjectAssetLayout('/work/p.anicel');
      expect(
        layout.conformPathFor('/work/p.assets/Media/대사.m4a'),
        '/work/p.assets/Conformed/대사.m4a.wav',
      );
    });

    test('a windows path with backslashes resolves the same', () {
      const layout = ProjectAssetLayout(r'C:\work\p.anicel');
      expect(layout.assetsDirectory, 'C:/work/p.assets');
      expect(
        layout.conformPathFor(r'C:\work\p.assets\Media\a.wav'),
        'C:/work/p.assets/Conformed/a.wav.wav',
      );
    });

    test('a project name containing dots keeps all but the last', () {
      const layout = ProjectAssetLayout('/work/ep.01.final.anicel');
      expect(layout.assetsDirectory, '/work/ep.01.final.assets');
    });
  });

  group('name collisions', () {
    test('a second file of the same name gets a suffix, not an overwrite', () {
      final taken = <String>{'/m/a.wav'};
      expect(
        AudioConformPipeline.uniqueNameIn(
          '/m',
          'a.wav',
          exists: taken.contains,
        ),
        'a-1.wav',
      );
      taken.add('/m/a-1.wav');
      expect(
        AudioConformPipeline.uniqueNameIn(
          '/m',
          'a.wav',
          exists: taken.contains,
        ),
        'a-2.wav',
      );
    });

    test('a free name is used as-is', () {
      expect(
        AudioConformPipeline.uniqueNameIn('/m', 'b.wav', exists: (_) => false),
        'b.wav',
      );
    });

    test('an extensionless name still deduplicates', () {
      expect(
        AudioConformPipeline.uniqueNameIn('/m', 'sound', exists: (p) => p == '/m/sound'),
        'sound-1',
      );
    });
  });

  group('building a conform', () {
    test('a source at the project rate is conformed without resampling', () {
      final log = <String>[];
      final source = writeSource('same.wav', rate: 48000);
      final result = pipelineFor(resampleLog: log).ensureConform(
        sourcePath: source,
        conformPath: '${temp.path}/Conformed/same.wav.wav',
      );

      expect(result.outcome, ConformOutcome.built);
      expect(result.sampleRate, 48000);
      expect(log, isEmpty, reason: 'no filter should run at equal rates');
      expect(File(result.conformPath!).existsSync(), isTrue);
      expect(result.peaks!.peaks, isNotEmpty);
    });

    test('a 44.1k source is resampled to the project rate', () {
      final log = <String>[];
      final source = writeSource('rate.wav', rate: 44100);
      final result = pipelineFor(resampleLog: log).ensureConform(
        sourcePath: source,
        conformPath: '${temp.path}/Conformed/rate.wav.wav',
      );

      expect(result.outcome, ConformOutcome.built);
      expect(result.sampleRate, 48000);
      expect(log, ['44100→48000']);

      // And the file on disk really is at the project rate.
      final written = decodeConformWav(
        File(result.conformPath!).readAsBytesSync(),
      );
      expect(written.sampleRate, 48000);
    });

    test('the conform carries the source fingerprint', () {
      final source = writeSource('fp.wav');
      final result = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: '${temp.path}/Conformed/fp.wav.wav',
      );
      final written = decodeConformWav(
        File(result.conformPath!).readAsBytesSync(),
      );
      expect(written.fingerprint, isNotNull);
      expect(
        written.fingerprint,
        AudioConformPipeline.fingerprintOf(File(source).readAsBytesSync()),
      );
    });

    test('a source that only got a new TIMESTAMP still reuses its conform', () {
      // The fingerprint used to be {length, lastModified}, which answers
      // "is this the same file on this disk". Copying a project to another
      // machine — or restoring one from a backup — hands every source a
      // fresh timestamp and rebuilt the entire cache for nothing. A conform
      // is 12x the size of its source, so that is the expensive answer to
      // the wrong question.
      final source = writeSource('touched.wav');
      final conformPath = '${temp.path}/Conformed/touched.wav.wav';
      expect(
        pipelineFor().ensureConform(
          sourcePath: source,
          conformPath: conformPath,
        ).outcome,
        ConformOutcome.built,
      );

      File(source).setLastModifiedSync(
        File(source).lastModifiedSync().add(const Duration(days: 30)),
      );

      expect(
        pipelineFor().ensureConform(
          sourcePath: source,
          conformPath: conformPath,
        ).outcome,
        ConformOutcome.reused,
        reason: 'the bytes never moved, so neither did the answer',
      );
    });

    test('a source rewritten to the SAME LENGTH with different bytes is '
        'caught', () {
      // Length alone cannot separate these, and the stat hint only says
      // "look closer" — the content is what decides. Without that, the
      // stale conform plays the old sound against the new drawing.
      final source = writeSource('swapped.wav');
      final conformPath = '${temp.path}/Conformed/swapped.wav.wav';
      pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: conformPath,
      );

      final other = writeSource('other.wav', rate: 44100);
      final swapped = File(other).readAsBytesSync();
      expect(
        swapped.length,
        File(source).lengthSync(),
        reason: 'the fixture only proves anything at equal length',
      );
      File(source).writeAsBytesSync(swapped);
      // Advanced explicitly: a real edit lands minutes after the conform,
      // but the two writes here are microseconds apart and can share a
      // timestamp, which would leave the test measuring clock resolution
      // instead of the reuse decision.
      File(source).setLastModifiedSync(
        File(source).lastModifiedSync().add(const Duration(minutes: 1)),
      );

      expect(
        pipelineFor().ensureConform(
          sourcePath: source,
          conformPath: conformPath,
        ).outcome,
        ConformOutcome.built,
      );
    });

    test('an edit that also RESTORES the timestamp slips through — the '
        'accepted price of not reading every source on every open', () {
      // Pinned rather than fixed, so nobody "corrects" it later without
      // knowing what it costs. Reading the bytes unconditionally is the
      // only way to catch this, and that is a full read of every original
      // on every project open — on the devices where a large allocation
      // gets the app killed. Writing a file moves its timestamp, so
      // reaching this needs the timestamp deliberately put back.
      final source = writeSource('restored.wav');
      final conformPath = '${temp.path}/Conformed/restored.wav.wav';
      // Stamped explicitly on BOTH sides rather than captured and put back:
      // reading a timestamp and restoring it does not round-trip on every
      // filesystem (it does on NTFS and does not on ext4), so a captured
      // value would make this test measure timestamp precision instead of
      // the reuse decision. Writing the same literal twice truncates the
      // same way wherever it runs.
      const stamp = 1767225600000000; // 2026-01-01T00:00:00Z, whole seconds
      final stampedAt = DateTime.fromMicrosecondsSinceEpoch(
        stamp,
        isUtc: true,
      );
      File(source).setLastModifiedSync(stampedAt);
      pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: conformPath,
      );

      final statBefore = AudioConformPipeline.statOf(source);

      final other = writeSource('other2.wav', rate: 44100);
      File(source).writeAsBytesSync(File(other).readAsBytesSync());
      File(source).setLastModifiedSync(stampedAt);

      // The fixture's own precondition, asserted so a filesystem that
      // stamps differently reports THAT rather than accusing the reuse
      // decision. Without it, "the hint missed" and "the fixture never
      // set up a hit" look identical from the failure message.
      expect(
        AudioConformPipeline.statOf(source),
        statBefore,
        reason: 'the edit had to leave the stat identical to mean anything',
      );

      expect(
        pipelineFor().ensureConform(
          sourcePath: source,
          conformPath: conformPath,
        ).outcome,
        ConformOutcome.reused,
        reason: 'the hint matched, so the bytes were never looked at',
      );
    });

    test('the fingerprint covers the WHOLE file, not a prefix', () {
      // A prefix hash would pass every other fixture here — the WAV header
      // is where the small ones differ. Real audio diverges deep in the
      // PCM, so a source re-recorded at the same length would keep playing
      // the old conform forever.
      final source = writeSource('deep.wav');
      final bytes = File(source).readAsBytesSync();
      final before = AudioConformPipeline.fingerprintOf(bytes);

      final tail = Uint8List.fromList(bytes)
        ..[bytes.length - 1] = bytes[bytes.length - 1] ^ 0xFF;
      expect(
        AudioConformPipeline.fingerprintOf(tail),
        isNot(before),
        reason: 'a change in the LAST byte has to move the fingerprint',
      );

      final middle = Uint8List.fromList(bytes)
        ..[bytes.length ~/ 2] = bytes[bytes.length ~/ 2] ^ 0xFF;
      expect(AudioConformPipeline.fingerprintOf(middle), isNot(before));
    });

    test('a source that is THERE but unreadable is transient, not missing', () {
      // A cloud placeholder that has not hydrated reads as a failure while
      // stat succeeds. Calling that "missing" spends one of the store's
      // three attempts on a file that is fine, and three of them silence
      // the clip for the rest of the session — silently, including in an
      // export. A DIRECTORY at the source path reproduces the shape that
      // matters: something is there, and reading it throws.
      final source = '${temp.path}/placeholder.wav';
      Directory(source).createSync(recursive: true);

      final result = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: '${temp.path}/Conformed/placeholder.wav.wav',
      );

      expect(result.outcome, ConformOutcome.sourceUnreadable);
      expect(result.isTransientFailure, isTrue);
    });

    test('the directory is created when it does not exist', () {
      final source = writeSource('deep.wav');
      final result = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: '${temp.path}/a/b/c/deep.wav.wav',
      );
      expect(result.outcome, ConformOutcome.built);
      expect(File(result.conformPath!).existsSync(), isTrue);
    });

    test('peaks come from the conform, so no ffmpeg is involved', () {
      // The reason waveforms have never appeared on a tablet.
      final source = writeSource('peaks.wav', channels: 2);
      final result = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: '${temp.path}/Conformed/peaks.wav.wav',
      );
      expect(result.peaks, isNotNull);
      expect(result.peaks!.peaks, isNotEmpty);
      expect(result.channels, 2);
    });
  });

  group('reuse and staleness', () {
    test('a conform at another rate is stale even with a matching source '
        '(the project rate is a SETTING now — EXPORT-AUDIO ③)', () {
      final source = writeSource('ratechange.wav', rate: 44100);
      final conform = '${temp.path}/Conformed/ratechange.wav.wav';

      expect(
        pipelineFor(projectSampleRate: 44100)
            .ensureConform(sourcePath: source, conformPath: conform)
            .outcome,
        ConformOutcome.built,
      );

      // Same source, same fingerprint — but the project moved to 48k.
      final rebuilt = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: conform,
      );
      expect(rebuilt.outcome, ConformOutcome.built,
          reason: '44.1k PCM on a 48k schedule would shift every clip');
      expect(rebuilt.sampleRate, 48000);
      expect(
        decodeConformWav(File(conform).readAsBytesSync()).sampleRate,
        48000,
      );
    });

    test('a matching conform is reused instead of rebuilt', () {
      final log = <String>[];
      final source = writeSource('reuse.wav', rate: 44100);
      final conform = '${temp.path}/Conformed/reuse.wav.wav';
      final pipeline = pipelineFor(resampleLog: log);

      expect(pipeline.ensureConform(sourcePath: source, conformPath: conform)
          .outcome, ConformOutcome.built);
      log.clear();

      final second = pipeline.ensureConform(
        sourcePath: source,
        conformPath: conform,
      );
      expect(second.outcome, ConformOutcome.reused);
      expect(log, isEmpty, reason: 'reuse must not redo the work');
      expect(second.peaks, isNotNull);
    });

    test('a replaced source rebuilds the conform', () {
      final source = writeSource('stale.wav');
      final conform = '${temp.path}/Conformed/stale.wav.wav';
      final pipeline = pipelineFor();
      pipeline.ensureConform(sourcePath: source, conformPath: conform);

      // Replace the original with different content and a later mtime.
      File(source).writeAsBytesSync(
        encodeConformWav(
          samples: ramp(4800, 1),
          channels: 1,
          sampleRate: 48000,
        ),
      );
      File(source).setLastModifiedSync(
        DateTime.now().add(const Duration(seconds: 5)),
      );

      expect(
        pipeline.ensureConform(sourcePath: source, conformPath: conform)
            .outcome,
        ConformOutcome.built,
        reason: 'the source changed, so the old conform must not be trusted',
      );
    });

    test('a conform with no fingerprint is treated as stale', () {
      // Written by another tool: nothing is known about where it came
      // from, and guessing wrong plays the wrong sound.
      final source = writeSource('foreign.wav');
      final conform = '${temp.path}/Conformed/foreign.wav.wav';
      Directory('${temp.path}/Conformed').createSync(recursive: true);
      File(conform).writeAsBytesSync(
        encodeConformWav(
          samples: ramp(100, 1),
          channels: 1,
          sampleRate: 48000,
        ),
      );

      expect(
        pipelineFor().ensureConform(sourcePath: source, conformPath: conform)
            .outcome,
        ConformOutcome.built,
      );
    });

    test('a corrupt conform is rebuilt rather than failing the import', () {
      final source = writeSource('corrupt.wav');
      final conform = '${temp.path}/Conformed/corrupt.wav.wav';
      Directory('${temp.path}/Conformed').createSync(recursive: true);
      File(conform).writeAsStringSync('this is not a wav');

      expect(
        pipelineFor().ensureConform(sourcePath: source, conformPath: conform)
            .outcome,
        ConformOutcome.built,
      );
    });
  });

  group('failures name themselves', () {
    test('a missing source says so', () {
      final result = pipelineFor().ensureConform(
        sourcePath: '${temp.path}/nope.wav',
        conformPath: '${temp.path}/Conformed/nope.wav.wav',
      );
      expect(result.outcome, ConformOutcome.sourceMissing);
      expect(result.error, isNotNull);
      expect(result.isUsable, isFalse);
    });

    test('an unrecognized container says so', () {
      final path = '${temp.path}/mystery.xyz';
      File(path).writeAsBytesSync(Uint8List.fromList(List.filled(64, 7)));
      final result = pipelineFor().ensureConform(
        sourcePath: path,
        conformPath: '${temp.path}/Conformed/mystery.xyz.wav',
      );
      expect(result.outcome, ConformOutcome.undecodable);
      expect(result.error, isNotNull);
      expect(result.isUsable, isFalse);
    });
  });
}
