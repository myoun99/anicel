import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show readAnicelZipLayoutFile;
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import '../../helpers/opened_session.dart';
import '../../helpers/temp_dir.dart';

/// 🗣️F-550-Q2 (유저 2026-11-04: 「원본에서 다시 품는다」) — a carry whose
/// name holds no bytes of its own is named anew when its file opens, reads
/// its original, and is carried from it by the next save.
///
/// FU.anicel held two carries from before carries had names (`''`): a
/// picture and a sound. Since edebae921 (10-08) stopped reading that shape,
/// both asked for the one entry `media/`, and the next save wrote each
/// original under it in turn and kept the last — the picture became the
/// sound. The file's format number was new, so nothing refused it.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('anicel_nameless'));
  tearDown(() => deleteTempQuietly(root));

  MediaAsset carried(
    String path,
    String? carriedAs, {
    DateTime? modified,
  }) => MediaAsset(
    path: path,
    name: mediaAssetDefaultName(path),
    kind: MediaAssetKind.image,
    carriedAs: carriedAs == null
        ? null
        : (token: carriedAs, modified: modified),
  );

  Project poolOf(List<MediaAsset> assets) =>
      createDefaultProject().copyWith(mediaAssets: assets);

  group('the name a carry is read with', () {
    test('a carry with no name, and one whose name another wears, is named '
        'anew — each its own name, and a name of the shape every name is '
        'minted in', () {
      final own = mintMediaCarry('/w/own.png');
      final twice = mintMediaCarry('/w/a.png');
      final named = projectWithEveryCarryNamed(
        poolOf([
          carried('/w/one.png', ''),
          carried('/w/two.png', ''),
          carried('/w/own.png', own),
          carried('/w/a.png', twice),
          carried('/w/b.png', twice),
          carried('/w/linked.png', null),
          // A bare token — the middle alone, minted before 09-25.
          carried('/w/token.png', '0a1b2c3d'),
        ]),
      );

      final names = [
        for (final asset in named.mediaAssets) asset.carriedAs?.token,
      ];
      expect(names[2], own, reason: 'a name of its own stays');
      expect(names[5], isNull, reason: 'a link carries nothing');
      final anew = [names[0], names[1], names[3], names[4], names[6]];
      expect(anew.toSet(), hasLength(5), reason: 'each its own');
      for (final name in anew) {
        expect(isOneStoredName(name!), isTrue, reason: name);
        expect(name, isNot(twice));
      }
    });

    test('a pool whose every carry has a name of its own is read as it '
        'is', () {
      final pool = poolOf([
        carried('/w/own.png', mintMediaCarry('/w/own.png')),
        carried('/w/linked.png', null),
      ]);
      expect(projectWithEveryCarryNamed(pool), same(pool));
    });

    test('a carry named anew keeps its date — the file it was carried from '
        'is as old as it was (F-589)', () {
      final when = DateTime(2026, 9, 2, 8, 15);
      final named = projectWithEveryCarryNamed(
        poolOf([carried('/w/one.png', '', modified: when)]),
      );

      final carry = named.mediaAssets.single.carriedAs!;
      expect(isOneStoredName(carry.token), isTrue, reason: 'named anew');
      expect(carry.modified, when);
    });

    test('the read says when it named a carry anew', () {
      List<int> documentOf(Project project) => utf8.encode(
        jsonEncode({
          'formatVersion': anicelFormatVersion,
          'project': project.toJson(),
        }),
      );

      final nameless = decodeAnicelProjectDocument(
        documentOf(poolOf([carried('/w/one.png', '')])),
      );
      expect(nameless.carriesNamedAnew, isTrue);
      final name = nameless.project.mediaAssets.single.carriedAs!.token;
      expect(isOneStoredName(name), isTrue);

      final named = decodeAnicelProjectDocument(
        documentOf(
          poolOf([carried('/w/own.png', mintMediaCarry('/w/own.png'))]),
        ),
      );
      expect(named.carriesNamedAnew, isFalse);
    });
  });

  group('a file holding two carries with no name', () {
    late String picture;
    late String sound;
    late String projectPath;
    final pictureBytes = Uint8List.fromList(List.generate(4096, (i) => i % 7));
    final soundBytes = Uint8List.fromList(List.generate(6000, (i) => i % 11));

    EditorSessionManager aSession(String room, Project project) =>
        EditorSessionManager(
          initialProject: project,
          mediaStagingStore: MediaStagingStore(
            directoryPath: '${root.path}/$room',
          ),
        );

    Future<void> saveTo(EditorSessionManager session) => session.projectDoor
        .saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);

    List<int> read(EditorSessionManager session, String path) =>
        session.projectFile.mediaByteSourceFor(path).readSync();

    setUp(() async {
      picture = normalizedMediaPath('${root.path}/_FU15_LO.png');
      sound = normalizedMediaPath('${root.path}/301-312.mp3');
      projectPath = '${root.path}/FU.anicel';
      File(picture).writeAsBytesSync(pictureBytes);
      File(sound).writeAsBytesSync(soundBytes);
      // FU's shape, written as it came to be: a session holding the two
      // carries with no name saves — and both go under `media/`.
      final writer = aSession(
        'Writer',
        poolOf([carried(picture, ''), carried(sound, '')]),
      );
      addTearDown(writer.dispose);
      await saveTo(writer);
      final layout = readAnicelZipLayoutFile(projectPath);
      expect(
        [
          for (final entry in layout.entries)
            if (entry.name.startsWith(anicelMediaEntryPrefix)) entry.name,
        ],
        [anicelMediaEntryPrefix],
        reason: '⛔전제: the two carries share the one entry, as FU\'s did',
      );
    });

    test('🗣️opened, each reads its own original — not the one entry they '
        'shared — and the session is unsaved', () async {
      final opened = await openedSession(
        projectPath,
        make: (project) => aSession('Opened', project),
      );
      addTearDown(opened.dispose);

      final names = {
        for (final asset in opened.mediaPool.mediaAssets)
          asset.carriedAs?.token,
      };
      expect(names, hasLength(2));
      expect(names.every((name) => isOneStoredName(name!)), isTrue);
      expect(read(opened, picture), pictureBytes);
      expect(read(opened, sound), soundBytes);
      expect(
        opened.projectFile.hasUnsavedChanges,
        isTrue,
        reason: 'what the file holds is not what the project says now',
      );
    });

    test('🗣️the next save carries each from its original — reopened with the '
        'originals gone, each is its own bytes', () async {
      final opened = await openedSession(
        projectPath,
        make: (project) => aSession('Opened', project),
      );
      addTearDown(opened.dispose);
      await saveTo(opened);
      File(picture).deleteSync();
      File(sound).deleteSync();

      final again = await openedSession(
        projectPath,
        make: (project) => aSession('Again', project),
      );
      addTearDown(again.dispose);

      expect(read(again, picture), pictureBytes);
      expect(read(again, sound), soundBytes);
      expect(again.projectFile.hasUnsavedChanges, isFalse);
    });

    test('an original that is gone opens as a missing file — for the relink '
        'hunt — not as the bytes another carry left', () async {
      File(picture).deleteSync();
      final opened = await openedSession(
        projectPath,
        make: (project) => aSession('Opened', project),
      );
      addTearDown(opened.dispose);
      opened.mediaPool.refreshMediaExistence();

      expect(opened.projectFile.projectHoldsMediaBytes(picture), isFalse);
      expect(opened.mediaPool.missingMediaPaths, contains(picture));
      expect(read(opened, sound), soundBytes);
    });
  });
}
