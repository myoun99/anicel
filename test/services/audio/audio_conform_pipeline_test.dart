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
      const layout = ProjectAssetLayout('/work/내작업/프로젝트.qap');
      expect(layout.assetsDirectory, '/work/내작업/프로젝트.assets');
      expect(layout.mediaDirectory, '/work/내작업/프로젝트.assets/Media');
      expect(
        layout.conformedDirectory,
        '/work/내작업/프로젝트.assets/Conformed',
      );
    });

    test('the conform path is derived from the media name, not recorded', () {
      // Nothing to keep in sync, and project.json stays small.
      const layout = ProjectAssetLayout('/work/p.qap');
      expect(
        layout.conformPathFor('/work/p.assets/Media/대사.m4a'),
        '/work/p.assets/Conformed/대사.m4a.wav',
      );
    });

    test('a windows path with backslashes resolves the same', () {
      const layout = ProjectAssetLayout(r'C:\work\p.qap');
      expect(layout.assetsDirectory, 'C:/work/p.assets');
      expect(
        layout.conformPathFor(r'C:\work\p.assets\Media\a.wav'),
        'C:/work/p.assets/Conformed/a.wav.wav',
      );
    });

    test('a project name containing dots keeps all but the last', () {
      const layout = ProjectAssetLayout('/work/ep.01.final.qap');
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
        AudioConformPipeline.fingerprintOf(source),
      );
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
