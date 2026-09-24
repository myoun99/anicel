import 'dart:convert';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';
import 'package:flutter_test/flutter_test.dart';

Project projectWithMediaPaths(List<String> paths) =>
    createDefaultProject().copyWith(
      mediaAssets: [
        for (final path in paths)
          MediaAsset(path: path, name: mediaAssetDefaultName(path)),
      ],
    );

/// A carry of [path] — the first one, unless [token] says which.
MediaCarry carryOf(String path, [String token = 'c1']) =>
    (poolPath: path, token: token);

/// The archive holding media: what an asset's entry is called, which of
/// the two manifests describes it, and when a file full of media is worth
/// compacting.
///
/// 🪦This used to end「Nothing writes media into a `.anicel` yet — that is
/// the next change」. It has been the ordinary way a project carries its
/// sound for a long time, and a conform rides beside it now.
void main() {
  group('entry names', () {
    test('the same asset lands on the same name every save', () {
      // It has to: a compaction moves every byte in the file, and the name
      // is the only thing that survives that.
      expect(
        anicelMediaEntryName(carryOf('/work/C-045/대사.m4a')),
        anicelMediaEntryName(carryOf('/work/C-045/대사.m4a')),
      );
    });

    test('different assets never share one', () {
      // Sharing would make deleting either take the other's bytes.
      expect(
        anicelMediaEntryName(carryOf('/work/a/A1.png')),
        isNot(anicelMediaEntryName(carryOf('/work/b/A1.png'))),
      );
    });

    test('🚨two carries of one path are two names — an entry means one set '
        'of bytes for good', () {
      // Media is written once and never edited: a save finding the name in
      // the file writes nothing. Carried again after a removal, the same
      // path under one name kept the OLD bytes (card
      // `recarry-after-remove-reads-the-old`).
      expect(
        anicelMediaEntryName(carryOf('/work/a.wav', 'c1')),
        isNot(anicelMediaEntryName(carryOf('/work/a.wav', 'c2'))),
      );
      expect(
        anicelMediaEntryNames(carryOf('/work/a.wav', 'c1')),
        isNot(contains(anicelMediaEntryName(carryOf('/work/a.wav', 'c2')))),
      );
    });

    test('the carry a project had before carries had names keeps the name '
        'the path alone gave — the one its file holds', () {
      const path = '/work/C-045/대사.m4a';
      expect(
        anicelMediaEntryName(carryOf(path, '')),
        anicelMediaEntryName(carryOf(path, 'c1')).replaceFirst('-c1-', '-'),
      );
      expect(
        RegExp(
          r'^media/[0-9a-f]{8}-[A-Za-z0-9._-]+$',
        ).hasMatch(anicelMediaEntryName(carryOf(path, ''))),
        isTrue,
      );
    });

    test('both spellings of one carry, framed first', () {
      final carry = carryOf('/work/a.wav');
      expect(anicelMediaEntryNames(carry), [
        anicelMediaEntryName(carry, framed: true),
        anicelMediaEntryName(carry),
      ]);
    });

    test('a windows path is the same asset as its forward-slash spelling', () {
      expect(
        anicelMediaEntryName(carryOf(r'C:\work\a.wav')),
        anicelMediaEntryName(carryOf('C:/work/a.wav')),
      );
    });

    test('the name is readable and safe inside a zip', () {
      // Someone opening a .anicel with an unzip tool should be able to tell
      // what they are looking at, without the name being able to escape the
      // media folder or upset a filesystem.
      final name = anicelMediaEntryName(
        carryOf('/work/내 작업/대사 01.m4a'),
      );
      expect(name, startsWith(anicelMediaEntryPrefix));
      expect(name, contains('.m4a'));
      expect(
        name.substring(anicelMediaEntryPrefix.length),
        isNot(contains('/')),
      );
      expect(
        RegExp(r'^media/[0-9a-f]{8}-[A-Za-z0-9._-]+$').hasMatch(name),
        isTrue,
        reason: name,
      );
    });

    String conformAt(
      String asset, {
      int sampleRate = 48000,
      int speedNumerator = 1,
      int speedDenominator = 1,
      bool framed = false,
    }) => anicelConformEntryName(
      asset,
      sampleRate: sampleRate,
      speedNumerator: speedNumerator,
      speedDenominator: speedDenominator,
      framed: framed,
    );

    test('🚨a CONFORM carries the SETTINGS it was built at', () {
      // ⛔This is not decoration. The sweep asks「is this entry one the
      // project may hold right now」, and without the settings in the name
      // that question collapses into「is there a conform in the cache」 —
      // which is ALSO false on a machine that has merely just opened the
      // file, so every carried conform would be swept on the first save
      // there. See [anicelConformEntryName].
      const asset = '/work/내 작업/대사 01.m4a';
      expect(conformAt(asset), contains('48000'));
      expect(
        conformAt(asset, sampleRate: 44100),
        isNot(conformAt(asset)),
        reason: 'a 44.1k conform is not a 48k one, and the NAME says so',
      );
      expect(
        conformAt(asset, speedNumerator: 1001, speedDenominator: 1000),
        isNot(conformAt(asset)),
        reason: 'the NTSC pull changes every sample; it is not the same file',
      );
    });

    test('an asset and its CONFORM share a hash and differ by prefix', () {
      // One derivation, two prefixes. Sharing the hash is what lets a
      // reader line the two up without recording anything; the separate
      // prefix is what lets the save drop one and keep the other.
      const asset = '/work/내 작업/대사 01.m4a';
      final media = anicelMediaEntryName(carryOf(asset));
      final conform = conformAt(asset);
      expect(conform, startsWith(anicelConformEntryPrefix));
      expect(
        conform.substring(anicelConformEntryPrefix.length),
        startsWith(media.substring(anicelMediaEntryPrefix.length, 8)),
        reason:
            'same asset, same hash — only the settings and the folder '
            'differ',
      );
      expect(conformAt(asset, framed: true), endsWith(mediaFramedEntrySuffix));
      expect(
        conformAt('/work/other.m4a'),
        isNot(conform),
        reason: 'two sounds must not share one conform entry',
      );
    });

    test('both spellings of one conform, and nothing else', () {
      const asset = '/work/대사.m4a';
      final names = anicelConformEntryNames(
        asset,
        sampleRate: 48000,
        speedNumerator: 1,
        speedDenominator: 1,
      );
      expect(names, hasLength(2));
      expect(names, contains(conformAt(asset)));
      expect(names, contains(conformAt(asset, framed: true)));
    });
  });

  group('the two manifests', () {
    /// The manifest for [mediaPaths], [inArchive] naming the entry each one
    /// held inside is stored under.
    Map<String, dynamic> jsonFor(
      List<String> mediaPaths, {
      Map<String, String> inArchive = const {},
      String? saveDirectory,
    }) {
      final project = projectWithMediaPaths(mediaPaths);
      return jsonDecode(
            utf8.decode(
              buildAnicelProjectJsonBytes(
                project: project,
                saveDirectory: saveDirectory,
                mediaEntryNames: inArchive,
              ),
            ),
          )
          as Map<String, dynamic>;
    }

    test('media inside is recorded by ENTRY, not by path', () {
      const bgm = '/work/scene.assets/Media/bgm.wav';
      final decoded = jsonFor(
        [bgm],
        inArchive: {bgm: anicelMediaEntryName(carryOf(bgm))},
        saveDirectory: '/work',
      );
      expect(decoded['mediaEntries'], {
        bgm: anicelMediaEntryName(carryOf(bgm)),
      });
      // And ONLY by entry: a path recorded as well would let a stale file
      // at the old location win over the copy the project carries.
      expect(decoded.containsKey('mediaPaths'), isFalse);
    });

    test('🚨a FRAMED entry is recorded under the name the archive holds — '
        'its suffix and all', () {
      // 2026-08-31 → 09-24 the manifest wrote the unframed name here, and a
      // reopened project looked for media the file did not have.
      const bgm = '/work/bgm.wav';
      final framed = anicelMediaEntryName(carryOf(bgm), framed: true);
      expect(framed, endsWith(mediaFramedEntrySuffix), reason: 'fixture');

      final decoded = jsonFor(
        [bgm],
        inArchive: {bgm: framed},
        saveDirectory: '/work',
      );

      expect(decoded['mediaEntries'], {bgm: framed});
    });

    test('media outside keeps the relative path it always had', () {
      final decoded = jsonFor([
        '/work/scene.assets/Media/bgm.wav',
      ], saveDirectory: '/work');
      expect(decoded['mediaPaths'], {
        '/work/scene.assets/Media/bgm.wav': 'scene.assets/Media/bgm.wav',
      });
      expect(decoded.containsKey('mediaEntries'), isFalse);
    });

    test('a project can hold some of each', () {
      // Which one applies is a property of the ASSET — video is
      // reference-only by kind, and a user may keep anything else linked.
      final decoded = jsonFor(
        ['/work/in.wav', '/work/out.mp4'],
        inArchive: {
          '/work/in.wav': anicelMediaEntryName(carryOf('/work/in.wav')),
        },
        saveDirectory: '/work',
      );
      expect((decoded['mediaEntries'] as Map).keys, ['/work/in.wav']);
      expect((decoded['mediaPaths'] as Map).keys, ['/work/out.mp4']);
    });

    test('an asset outside the save folder is in neither', () {
      // Unchanged: the relative manifest only ever described what lives
      // under the project, and the absolute path carries the rest.
      final decoded = jsonFor(['/elsewhere/ref.mp4'], saveDirectory: '/work');
      expect(decoded.containsKey('mediaPaths'), isFalse);
      expect(decoded.containsKey('mediaEntries'), isFalse);
    });
  });

  group('when to compact', () {
    ({String name, int length}) cel(int length) =>
        (name: 'cels/x.celz', length: length);
    ({String name, int length}) media(int length) =>
        (name: '${anicelMediaEntryPrefix}0badf00d-a.wav', length: length);
    ({String name, int length}) conform(int length) =>
        (name: '${anicelConformEntryPrefix}0badf00d-a.wav', length: length);

    test('🚨a CONFORM counts as media here, or an audio project stops '
        'compacting', () {
      // The exclusion is about bulk a rewrite copies FOR NOTHING, and a
      // carried conform is the bulkiest thing an audio project holds — an
      // hour of dialogue is ~428MB compressed against a cel area of tens.
      // Left in the denominator it dilutes the ratio exactly as media did.
      const conformBytes = 500 * 1024 * 1024;
      final mostlyConform = [conform(conformBytes), cel(2048)];
      expect(
        anicelNeedsCompaction(
          fileLength: conformBytes + 2048 + 4096,
          entries: mostlyConform,
        ),
        isFalse,
        reason: '4KB of dead project.json is not worth 500MB of copying',
      );
      expect(
        anicelNeedsCompaction(
          fileLength: conformBytes + 2048 + 2048,
          entries: mostlyConform,
        ),
        isFalse,
      );
      // And a cel area that IS mostly garbage still asks, which is the
      // half the exclusion exists to protect.
      expect(
        anicelNeedsCompaction(
          fileLength: conformBytes + 2048 + 40 * 1024 * 1024,
          entries: mostlyConform,
        ),
        isTrue,
        reason:
            'measured against the FILE this disappears into rounding — '
            'which is the bug the media exclusion was written to fix, and '
            'a conform is larger than the media',
      );
    });

    test('half the cel area dead is the threshold, as it always was', () {
      // A project with no media is untouched by the rewrite floor below —
      // it costs nothing to rewrite, so it keeps exactly the rule it had.
      expect(
        anicelNeedsCompaction(fileLength: 100, entries: [cel(49)]),
        isTrue,
      );
      expect(
        anicelNeedsCompaction(fileLength: 100, entries: [cel(51)]),
        isFalse,
      );
    });

    test('🔑 a rewrite has to be worth the bytes it moves for nothing', () {
      // Taking media out of the denominator made this necessary. The
      // rotting area is now just cels and `project.json`, which in a
      // project that is mostly sound can be a few kilobytes — so two
      // superseded copies of `project.json` cross fifty percent of it and
      // ask for a rewrite that re-streams half a gigabyte to reclaim four.
      const mediaBytes = 500 * 1024 * 1024;
      final mostlySound = [media(mediaBytes), cel(2048)];
      expect(
        anicelNeedsCompaction(
          fileLength: mediaBytes + 2048 + 4096,
          entries: mostlySound,
        ),
        isFalse,
        reason: '4KB of dead project.json is not worth 500MB of copying',
      );
      // Proportionate waste, and it runs as before.
      expect(
        anicelNeedsCompaction(
          fileLength: mediaBytes + 2048 + 40 * 1024 * 1024,
          entries: mostlySound,
        ),
        isTrue,
      );
    });

    test('🔑 media cannot dilute the ratio into never compacting', () {
      // The whole reason this is a named rule. Measured against the FILE,
      // a cel area that is mostly garbage disappears into the rounding of
      // a project carrying half a gigabyte of sound, and compaction never
      // runs again while that area fills up forever.
      const mediaBytes = 500 * 1024 * 1024;
      const liveCels = 2 * 1024 * 1024;
      const deadCels = 30 * 1024 * 1024;
      final entries = [media(mediaBytes), cel(liveCels)];
      const fileLength = mediaBytes + liveCels + deadCels;

      expect(
        anicelNeedsCompaction(fileLength: fileLength, entries: entries),
        isTrue,
        reason: '30MB dead against 32MB of cel area is well past half',
      );
      // The measurement that would have said otherwise: against the whole
      // file the same waste is under six percent.
      expect(deadCels / fileLength, lessThan(0.06));
    });

    test('media alone never asks to be compacted', () {
      // It is written once and never shadowed, so there is nothing to
      // reclaim — and the divisor would be zero.
      expect(
        anicelNeedsCompaction(fileLength: 1000, entries: [media(1000)]),
        isFalse,
      );
    });

    test('a file smaller than its own media does not divide by a negative', () {
      // Defensive: a truncated file must answer "no" rather than throw or
      // decide by accident.
      expect(
        anicelNeedsCompaction(fileLength: 10, entries: [media(1000)]),
        isFalse,
      );
    });
  });
}
