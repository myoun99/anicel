import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/audio/audio_resampler_reference.dart';
import 'package:anicel/src/services/audio/conform_pcm_codec.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32;
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import '../../helpers/conform_file_path.dart';
import '../../helpers/project_scratch_folder.dart';
import '../../helpers/temp_dir.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa_conform_');
  });

  tearDown(() => deleteTempQuietly(temp));

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
      decode: (source) {
        final bytes = source.readSync();
        try {
          final audio = decodeConform(bytes);
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
      encodeConform(
        samples: ramp(2400, channels),
        channels: channels,
        sampleRate: rate,
      ),
    );
    return path;
  }

  group('layout', () {
    /// The cache as an ordinary project uses it, so a test about something
    /// else does not have to say so three times.
    ///
    /// Built per call, not held: the root is a live setting, and a layout
    /// captured once would quietly answer with the root from before a test
    /// changed it.
    ConformCacheLayout layoutAt48k() => ConformCacheLayout.forAudio(
      sampleRate: 48000,
      speedNumerator: 1,
      speedDenominator: 1,
    );

    test('assets sit beside the project, not inside it', () {
      const layout = ProjectAssetLayout('/work/내작업/프로젝트.anicel');
      expect(layout.assetsDirectory, '/work/내작업/프로젝트.assets');
      expect(layout.mediaDirectory, '/work/내작업/프로젝트.assets/Media');
    });

    test('the conform path is derived from the source, not recorded', () {
      // Nothing to keep in sync, and project.json stays small. The source
      // name stays in front so the cache folder is legible; the hash is
      // what makes the entry unique.
      const layout = ConformCacheLayout(
        directory: '/cache',
        sampleRate: 48000,
        speedNumerator: 1,
        speedDenominator: 1,
      );
      expect(
        layout.conformPathFor('/work/p.assets/Media/대사.m4a'),
        startsWith('/cache/대사.m4a.'),
      );
      expect(
        layout.conformPathFor('/work/p.assets/Media/대사.m4a'),
        endsWith('.wav'),
      );
    });

    test('a windows path with backslashes resolves the same', () {
      const layout = ProjectAssetLayout(r'C:\work\p.anicel');
      expect(layout.assetsDirectory, 'C:/work/p.assets');
      expect(
        layoutAt48k().conformPathFor(r'C:\work\p\대사.m4a'),
        layoutAt48k().conformPathFor('C:/work/p/대사.m4a'),
      );
    });

    test('a project name containing dots keeps all but the last', () {
      const layout = ProjectAssetLayout('/work/ep.01.final.anicel');
      expect(layout.assetsDirectory, '/work/ep.01.final.assets');
    });

    test('the legacy sibling is REPORTED, never removed', () async {
      // Nothing writes there any more, so the folder is dead weight — but
      // it holds the user's originals until a save takes them inside, and
      // the app does not delete the user's files (user direction). All
      // this answers is whether there is something to say.
      final root = await Directory.systemTemp.createTemp('qa-legacy-assets');
      deleteAfterSessionEnds(root);
      final project = '${root.path.replaceAll('\\', '/')}/scene.anicel';
      final layout = ProjectAssetLayout(project);
      expect(layout.hasLegacyAssetsDirectory, isFalse);

      Directory('${layout.assetsDirectory}/Media').createSync(recursive: true);
      expect(layout.hasLegacyAssetsDirectory, isTrue);
      expect(
        Directory(layout.assetsDirectory).existsSync(),
        isTrue,
        reason: 'asking must not be the same as clearing',
      );
    });

    test('the conform cache is NOT beside the project', () {
      // The whole point of the move: a twelve-times-the-source cache must
      // not land in whatever cloud folder the project happens to be in,
      // and the single-file format has no siblings to put it in either.
      expect(
        layoutAt48k().conformPathFor('/work/내작업/대사.m4a'),
        isNot(startsWith('/work/내작업')),
      );
    });

    test('the cache is keyed by the SOURCE, so a rename, a move or a Save '
        'As orphans nothing', () {
      // The old key was the project path: Save As minted a fresh folder
      // and abandoned every conform the project had built. Nobody
      // collected them, and on an iPad nobody could even see them.
      expect(
        layoutAt48k().conformPathFor('/x/대사.m4a'),
        layoutAt48k().conformPathFor('/x/대사.m4a'),
      );
      expect(
        layoutAt48k().conformPathFor('/x/대사.m4a'),
        startsWith('${AppSave.conformRootDirectory}/대사.m4a.'),
      );
    });

    test('two projects using the same sound share one conform', () {
      // They used to build a copy each, at twelve times the source.
      final other = ConformCacheLayout.forAudio(
        sampleRate: 48000,
        speedNumerator: 1,
        speedDenominator: 1,
      );
      expect(
        layoutAt48k().conformPathFor('/shared/발소리.wav'),
        other.conformPathFor('/shared/발소리.wav'),
      );
    });

    test('two sounds of the same NAME do not share one', () {
      expect(
        layoutAt48k().conformPathFor('/a/발소리.wav'),
        isNot(layoutAt48k().conformPathFor('/b/발소리.wav')),
      );
    });

    test('the RATE and the SPEED are in the key, not only in the file', () {
      // A 44.1k conform against a 48k schedule slides every clip, and a
      // pull-down difference drifts by a thousandth — small enough to
      // survive a listen and wrong by the end of a reel. Both are recorded
      // inside the conform so a mismatch is caught either way; keying on
      // them means the two never meet, and a project that switches back
      // and forth keeps both instead of rebuilding at every change.
      final at441 = ConformCacheLayout.forAudio(
        sampleRate: 44100,
        speedNumerator: 1,
        speedDenominator: 1,
      );
      final pulled = ConformCacheLayout.forAudio(
        sampleRate: 48000,
        speedNumerator: 1001,
        speedDenominator: 1000,
      );
      const source = '/x/대사.m4a';
      expect({
        layoutAt48k().conformPathFor(source),
        at441.conformPathFor(source),
        pulled.conformPathFor(source),
      }, hasLength(3));
    });

    test('🚨 a conform waits in THIS RUN\'S room, and the address is built '
        'from there', () {
      // 🪦Two tests used to stand here: one drove a `conformDirectory`
      // setting and checked the root followed it, one checked an unset
      // setting fell back to the container. The setting is gone — a
      // conform is decoded PCM waiting to move into the project file at
      // the next save, which is a LIFETIME, and the room whose lifetime
      // that is has no reason to be somewhere the user picked.
      expect(AppSave.conformRootDirectory, SessionScratch.stagedFolder());
      expect(
        layoutAt48k().conformPathFor('/x/a.wav'),
        startsWith('${SessionScratch.stagedFolder()}/'),
      );
    });

    test('the root is redirected under test', () {
      // Without this a test run writes into the real user's app folder and
      // reads whatever a previous run left there.
      expect(
        AppSave.conformRootDirectory,
        contains(Directory.systemTemp.path.replaceAll('\\', '/')),
      );
    });

    test('🚨 the cache a SESSION uses is assembled, not just available', () {
      // The law (where the root is, how a name is built) is covered above
      // and the WIRING is a different question: every test that builds a
      // session injects its own conform store, so nothing observes the
      // path the app actually resolves. A previous round noticed exactly
      // this and named the composition to give it an observer; re-keying
      // by source moved the composition and would have left it unwatched
      // again.
      //
      // A session with NO injected store is the only way to see it.
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final project = session.repository.requireProject();

      expect(
        session.audioConformStore.resolveConformPath('/x/대사.m4a'),
        ConformCacheLayout.forAudio(
          sampleRate: project.audioSampleRate,
          speedNumerator: project.audioSpeedNumerator,
          speedDenominator: project.audioSpeedDenominator,
        ).conformPathFor('/x/대사.m4a'),
        reason: 'the session must compose the same address the layout does',
      );
      expect(
        session.audioConformStore.resolveConformPath('/x/대사.m4a'),
        isNotNull,
        reason:
            'and an UNSAVED project caches like any other now — the '
            'old key was the project path, so a project with no name got '
            'no cache and re-decoded its audio every launch',
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
      expect(File(conformFilePathOrNull(result.conformBytes)!).existsSync(), isTrue);
      expect(result.peaks!.peaks, isNotEmpty);
    });

    test('an unwritable cache costs a re-decode, never the sound', () {
      // The cache root is a setting now and Preferences invites the user to
      // put it on another drive, so "the cache cannot be written" is a
      // configuration away: an unplugged volume, a deleted folder, a macOS
      // scope that did not survive a relaunch. The decoded PCM is already
      // in hand when the write fails — dropping it silences the clip for
      // the session and silences it in an export, over a cache.
      final source = writeSource('uncacheable.wav', rate: 48000);
      // A FILE where the cache wants a directory: createSync(recursive)
      // throws on every platform.
      final blocker = '${temp.path}/blocker';
      File(blocker).writeAsBytesSync(const [0]);

      final result = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: '$blocker/nested/uncacheable.wav.wav',
      );

      expect(result.outcome, ConformOutcome.built);
      expect(result.isUsable, isTrue);
      expect(result.samples, isNotNull);
      expect(result.samples!.isNotEmpty, isTrue);
      expect(result.peaks!.peaks, isNotEmpty);
      expect(result.sampleRate, 48000);
      // Cached NOWHERE, and says why — a caller must not go looking for a
      // file that was never written.
      expect(result.conformBytes, isNull);
      expect(result.error, contains('could not cache'));
    });

    test('an uncacheable source is retried, not remembered as broken', () {
      // Self-healing: the next ensure tries the write again, which is what
      // lets a volume coming back fix itself. A failure that spent the
      // store's attempt budget could never do that.
      final source = writeSource('retry.wav', rate: 48000);
      final blocker = '${temp.path}/blocker2';
      File(blocker).writeAsBytesSync(const [0]);
      final conformPath = '$blocker/nested/retry.wav.wav';

      expect(
        pipelineFor()
            .ensureConform(sourcePath: source, conformPath: conformPath)
            .isUsable,
        isTrue,
      );

      // The obstruction goes away; the same call now caches.
      File(blocker).deleteSync();
      final second = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: conformPath,
      );
      expect(second.outcome, ConformOutcome.built);
      // The name gains `.z` when the write compressed, so the assertion is
      // that it landed AT this address — not that it wears the plain
      // spelling of it.
      expect(conformFilePathOrNull(second.conformBytes), startsWith(conformPath));
      expect(second.error, isNull);
      expect(File(conformFilePathOrNull(second.conformBytes)!).existsSync(), isTrue);
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
      final written = decodeConform(
        result.conformBytes!.readSync(),
      );
      expect(written.sampleRate, 48000);
    });

    test('the conform carries the source fingerprint', () {
      final source = writeSource('fp.wav');
      final result = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: '${temp.path}/Conformed/fp.wav.wav',
      );
      final written = decodeConform(
        result.conformBytes!.readSync(),
      );
      expect(written.fingerprint, isNotNull);
      expect(
        written.fingerprint,
        AudioConformPipeline.fingerprintOf(File(source).readAsBytesSync()),
      );
    });

    test('⛔ a REUSE writes NOTHING — it reports the file it read and '
        'leaves it alone', () {
      // 🪦This used to assert the opposite half: a reuse TOUCHED the
      // conform's mtime, because eviction order was「least recently
      // wanted」and the mtime was the only record of wanting. There is no
      // eviction any more — a conform lives in the run's scratch until the
      // save absorbs it and the room goes when the run does — so a write
      // on the read path would be a write for nobody, on a file that in
      // the other half of its life is a range inside a read-only archive.
      final source = writeSource('warm.wav');
      final conformPath = '${temp.path}/Conformed/warm.wav.wav';
      final built = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: conformPath,
      );
      expect(built.outcome, ConformOutcome.built);
      // 🚨The file the write LANDED on, which gains `.z` when it
      // compressed. Touching the base name instead would leave the real
      // entry looking cold — and it would look like this test passed,
      // because the base name would not exist to contradict it.
      final onDisk = conformFilePathOrNull(built.conformBytes)!;
      final cold = DateTime.now().subtract(const Duration(days: 30));
      File(onDisk).setLastModifiedSync(cold);

      final reused = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: conformPath,
      );
      expect(reused.outcome, ConformOutcome.reused);
      expect(
        conformFilePathOrNull(reused.conformBytes),
        onDisk,
        reason: 'a reuse reports the file it actually read',
      );

      expect(
        // ⚠️Still cold, not「exactly the stamp we set」: the filesystem
        // stores this truncated to the second, so an equality here fails
        // on the microseconds and says nothing about the behaviour.
        File(
          onDisk,
        ).lastModifiedSync().isBefore(DateTime.now().subtract(const Duration(days: 29))),
        isTrue,
        reason: 'reading is not writing. A conform that is a range inside '
            'the project file has no mtime to keep warm, so a read path '
            'that moved one would be doing it for exactly half its homes '
            'and for nobody at all.',
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
        pipelineFor()
            .ensureConform(sourcePath: source, conformPath: conformPath)
            .outcome,
        ConformOutcome.built,
      );

      File(source).setLastModifiedSync(
        File(source).lastModifiedSync().add(const Duration(days: 30)),
      );

      expect(
        pipelineFor()
            .ensureConform(sourcePath: source, conformPath: conformPath)
            .outcome,
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
      pipelineFor().ensureConform(sourcePath: source, conformPath: conformPath);

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
        pipelineFor()
            .ensureConform(sourcePath: source, conformPath: conformPath)
            .outcome,
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
      final stampedAt = DateTime.fromMicrosecondsSinceEpoch(stamp, isUtc: true);
      File(source).setLastModifiedSync(stampedAt);
      pipelineFor().ensureConform(sourcePath: source, conformPath: conformPath);

      final statBefore = MediaFileBytes(source).statSync();

      final other = writeSource('other2.wav', rate: 44100);
      File(source).writeAsBytesSync(File(other).readAsBytesSync());
      File(source).setLastModifiedSync(stampedAt);

      // The fixture's own precondition, asserted so a filesystem that
      // stamps differently reports THAT rather than accusing the reuse
      // decision. Without it, "the hint missed" and "the fixture never
      // set up a hit" look identical from the failure message.
      expect(
        MediaFileBytes(source).statSync(),
        statBefore,
        reason: 'the edit had to leave the stat identical to mean anything',
      );

      expect(
        pipelineFor()
            .ensureConform(sourcePath: source, conformPath: conformPath)
            .outcome,
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
      expect(File(conformFilePathOrNull(result.conformBytes)!).existsSync(), isTrue);
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
        pipelineFor(
          projectSampleRate: 44100,
        ).ensureConform(sourcePath: source, conformPath: conform).outcome,
        ConformOutcome.built,
      );

      // Same source, same fingerprint — but the project moved to 48k.
      final rebuilt = pipelineFor().ensureConform(
        sourcePath: source,
        conformPath: conform,
      );
      expect(
        rebuilt.outcome,
        ConformOutcome.built,
        reason: '44.1k PCM on a 48k schedule would shift every clip',
      );
      expect(rebuilt.sampleRate, 48000);
      expect(decodeConform(File(conform).readAsBytesSync()).sampleRate, 48000);
    });

    test('a matching conform is reused instead of rebuilt', () {
      final log = <String>[];
      final source = writeSource('reuse.wav', rate: 44100);
      final conform = '${temp.path}/Conformed/reuse.wav.wav';
      final pipeline = pipelineFor(resampleLog: log);

      expect(
        pipeline
            .ensureConform(sourcePath: source, conformPath: conform)
            .outcome,
        ConformOutcome.built,
      );
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
        encodeConform(samples: ramp(4800, 1), channels: 1, sampleRate: 48000),
      );
      File(
        source,
      ).setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));

      expect(
        pipeline
            .ensureConform(sourcePath: source, conformPath: conform)
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
        encodeConform(samples: ramp(100, 1), channels: 1, sampleRate: 48000),
      );

      expect(
        pipelineFor()
            .ensureConform(sourcePath: source, conformPath: conform)
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
        pipelineFor()
            .ensureConform(sourcePath: source, conformPath: conform)
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

  group('carried media reads from the archive', () {
    /// [wav] embedded at an offset inside a container file — the shape of
    /// a STORE'd archive entry, without needing a whole .anicel here.
    MediaArchiveBytes embedded(String name, Uint8List wav, {int? crc}) {
      final container = '${temp.path}/$name';
      final junk = List<int>.filled(8, 0xEE);
      File(container).writeAsBytesSync([...junk, ...wav], flush: true);
      return MediaArchiveBytes(
        archivePath: container,
        dataOffset: junk.length,
        length: wav.length,
        entryCrc32: crc ?? anicelCrc32(wav),
      );
    }

    test('a deleted import original is not "missing" when the bytes are an '
        'archive range', () {
      // The very act carrying exists to survive. The pipeline used to ask
      // the filesystem regardless, so the clip fell to sourceMissing,
      // burned the retry budget, and stayed silent for the session and
      // the export while the bytes sat inside the project.
      final original = writeSource('대사.wav');
      final wav = File(original).readAsBytesSync();
      final source = embedded('project.anicel', wav);
      File(original).deleteSync();

      final result = pipelineFor().ensureConform(
        sourcePath: original,
        conformPath: null,
        source: source,
      );

      expect(result.outcome, isNot(ConformOutcome.sourceMissing));
      expect(result.isUsable, isTrue, reason: 'decoded from the archive');
    });

    test('an archive range that no longer matches its CRC retries instead '
        'of decoding whatever moved into the window', () {
      // Offsets are resolved when the request is built; a compaction can
      // move every byte before the read happens. The entry CRC is the
      // tripwire, and the miss is TRANSIENT — the next attempt resolves
      // fresh offsets — never a decode of the wrong sound.
      final original = writeSource('take.wav');
      final wav = File(original).readAsBytesSync();
      final source = embedded('stale.anicel', wav, crc: 0x12345678);

      final result = pipelineFor().ensureConform(
        sourcePath: original,
        conformPath: null,
        source: source,
      );

      expect(result.outcome, ConformOutcome.sourceUnreadable);
      expect(result.isUsable, isFalse);
    });
  });
}
