import 'dart:convert';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:flutter_test/flutter_test.dart';

Project projectWithMediaPaths(List<String> paths) =>
    createDefaultProject().copyWith(
      mediaAssets: [
        for (final path in paths)
          MediaAsset(path: path, name: mediaAssetDefaultName(path)),
      ],
    );

/// The archive learning to hold media: what an asset's entry is called,
/// which of the two manifests describes it, and when a file full of media
/// is worth compacting.
///
/// Nothing writes media into a `.anicel` yet — that is the next change.
/// This is the container being able to.
void main() {
  group('entry names', () {
    test('the same asset lands on the same name every save', () {
      // It has to: a compaction moves every byte in the file, and the name
      // is the only thing that survives that.
      expect(
        anicelMediaEntryName('/work/C-045/대사.m4a'),
        anicelMediaEntryName('/work/C-045/대사.m4a'),
      );
    });

    test('different assets never share one', () {
      // Sharing would make deleting either take the other's bytes.
      expect(
        anicelMediaEntryName('/work/a/A1.png'),
        isNot(anicelMediaEntryName('/work/b/A1.png')),
      );
    });

    test('a windows path is the same asset as its forward-slash spelling', () {
      expect(
        anicelMediaEntryName(r'C:\work\a.wav'),
        anicelMediaEntryName('C:/work/a.wav'),
      );
    });

    test('the name is readable and safe inside a zip', () {
      // Someone opening a .anicel with an unzip tool should be able to tell
      // what they are looking at, without the name being able to escape the
      // media folder or upset a filesystem.
      final name = anicelMediaEntryName('/work/내 작업/대사 01.m4a');
      expect(name, startsWith(anicelMediaEntryPrefix));
      expect(name, contains('.m4a'));
      expect(name.substring(anicelMediaEntryPrefix.length), isNot(contains('/')));
      expect(RegExp(r'^media/[0-9a-f]{8}-[A-Za-z0-9._-]+$').hasMatch(name), isTrue,
          reason: name);
    });
  });

  group('the two manifests', () {
    Map<String, dynamic> jsonFor(
      List<String> mediaPaths, {
      Set<String> inArchive = const {},
      String? saveDirectory,
    }) {
      final project = projectWithMediaPaths(mediaPaths);
      return jsonDecode(
        utf8.decode(
          buildAnicelProjectJsonBytes(
            project: project,
            saveDirectory: saveDirectory,
            mediaInArchive: inArchive,
          ),
        ),
      ) as Map<String, dynamic>;
    }

    test('media inside is recorded by ENTRY, not by path', () {
      final decoded = jsonFor(
        ['/work/scene.assets/Media/bgm.wav'],
        inArchive: {'/work/scene.assets/Media/bgm.wav'},
        saveDirectory: '/work',
      );
      expect(decoded['mediaEntries'], {
        '/work/scene.assets/Media/bgm.wav':
            anicelMediaEntryName('/work/scene.assets/Media/bgm.wav'),
      });
      // And ONLY by entry: a path recorded as well would let a stale file
      // at the old location win over the copy the project carries.
      expect(decoded.containsKey('mediaPaths'), isFalse);
    });

    test('media outside keeps the relative path it always had', () {
      final decoded = jsonFor(
        ['/work/scene.assets/Media/bgm.wav'],
        saveDirectory: '/work',
      );
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
        inArchive: {'/work/in.wav'},
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

    test('half the cel area dead is the threshold, as it always was', () {
      expect(
        anicelNeedsCompaction(fileLength: 100, entries: [cel(49)]),
        isTrue,
      );
      expect(
        anicelNeedsCompaction(fileLength: 100, entries: [cel(51)]),
        isFalse,
      );
    });

    test('🔑 media cannot dilute the ratio into never compacting', () {
      // The whole reason this is a named rule. 500MB of media beside 10MB
      // of cels, 8MB of them dead: against the file that is 1.6% and
      // compaction never runs again while the cel area fills with garbage.
      const mediaBytes = 500 * 1024 * 1024;
      const liveCels = 2 * 1024 * 1024;
      const deadCels = 8 * 1024 * 1024;
      final entries = [media(mediaBytes), cel(liveCels)];
      const fileLength = mediaBytes + liveCels + deadCels;

      expect(
        anicelNeedsCompaction(fileLength: fileLength, entries: entries),
        isTrue,
        reason: '8MB dead against 10MB of cel area is well past half',
      );
      // The measurement that would have said otherwise.
      expect((fileLength - mediaBytes - liveCels) / fileLength, lessThan(0.02));
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
