import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/services/media/project_media_sources.dart'
    show mediaLeftBehind;
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show parseAnicelZipLayoutFile, writeAnicelArchiveFile;
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show anicelMediaEntryPrefix, buildAnicelProjectEntry;
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';
import '../../helpers/opened_session.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**OPENING SOMEBODY'S PROJECT AND SAVING IT TOUCHES NOTHING OUTSIDE
/// THE ROOM** (card `a-name-read-from-a-file-becomes-a-path`, 유저
/// 2026-10-06: 「그건만 지금고치자」).
///
/// The whole journey, with a file written the way no build of this app
/// writes one: it NAMES things outside the room — an entry it says it
/// holds, a carry it says an asset is — and the first save made a file out
/// there of the one and deleted the file out there of the other.
///
/// ⚠️The verbs are pinned one by one in
/// `a_name_read_from_a_file_stays_in_the_room_test`; this is the walk a
/// person takes, so a door that reached the disk some other way would show
/// here.
void main() {
  late Directory root;
  late Directory outside;
  EditorSessionManager? session;

  final secret = Uint8List.fromList(List<int>.generate(2048, (i) => i & 0xFF));

  /// Noise, so whoever keeps it keeps it as it is — nothing to shrink.
  final noise = Random(7);
  final sound = Uint8List.fromList(
    List<int>.generate(4096, (_) => noise.nextInt(256)),
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel_crafted_project_test');
    outside = Directory('${root.path}/outside')..createSync();
    Directory('${root.path}/work').createSync();
  });

  tearDown(() {
    session?.dispose();
    session = null;
    deleteTempQuietly(root);
  });

  /// The room is two folders under [root], so a name that climbs twice
  /// lands beside it — in [outside].
  EditorSessionManager aSession(Project project) => EditorSessionManager(
    initialProject: project,
    mediaStagingStore: MediaStagingStore(
      directoryPath: '${root.path}/room/Staged',
    ),
    audioConformStore: soundConformStore(),
  );

  String inWork(String file) => normalizedMediaPath('${root.path}/work/$file');

  List<String> outsideNow() => [
    for (final entity in outside.listSync())
      entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
  ]..sort();

  /// A project file holding [assets], saying it holds [mediaEntryNames]
  /// (pool path → entry) and holding [entries] under exactly those names.
  String crafted({
    required List<MediaAsset> assets,
    Map<String, String> mediaEntryNames = const {},
    Map<String, List<int>> entries = const {},
  }) {
    final path = inWork('scene.anicel');
    writeAnicelArchiveFile(
      path: path,
      entries: [
        buildAnicelProjectEntry(
          project: createDefaultProject().copyWith(mediaAssets: assets),
          mediaEntryNames: mediaEntryNames,
        ),
        for (final MapEntry(key: name, value: bytes) in entries.entries)
          (name: name, bytes: Uint8List.fromList(bytes)),
      ],
    );
    return path;
  }

  /// The bytes of every media entry the project file at [path] holds.
  List<Uint8List> mediaKeptIn(String path) {
    final file = File(path).openSync();
    try {
      return [
        for (final entry in parseAnicelZipLayoutFile(path).entries)
          if (entry.name.startsWith(anicelMediaEntryPrefix))
            (file..setPositionSync(entry.dataOffset)).readSync(entry.length),
      ];
    } finally {
      file.closeSync();
    }
  }

  Future<void> openAndSave(String path) async {
    final opened = session = await openedSession(path, make: aSession);
    await opened.projectDoor.saveProjectToFile(
      path,
      asked: SaveAsked.byAPerson,
    );
  }

  test('🚨an entry the document says it holds, named out of the room, is '
      'not written out there by the save that leaves it behind', () async {
    final reference = inWork('ref.wav');
    File(reference).writeAsBytesSync(sound);
    const planted = '$anicelMediaEntryPrefix../../outside/planted-1.bin';
    final path = crafted(
      assets: [MediaAsset(path: reference, name: 'ref')],
      mediaEntryNames: {reference: planted},
      entries: {planted: secret},
    );
    expect(
      parseAnicelZipLayoutFile(path).entryNamed(planted),
      isNotNull,
      reason: 'the premise: the file holds an entry under that name',
    );

    await openAndSave(path);

    expect(outsideNow(), isEmpty);
  });

  test('🚨a carry named out of the room is not read as the room\'s copy, '
      'and the file out there is still there after the save', () async {
    final original = inWork('take.wav');
    File(original).writeAsBytesSync(sound);
    File('${outside.path}/victim-1.bin').writeAsBytesSync(secret);
    const escaping = '../../outside/victim-1.bin';
    final path = crafted(
      assets: [MediaAsset(path: original, name: 'take', carriedAs: escaping)],
    );

    await openAndSave(path);

    expect(outsideNow(), ['victim-1.bin']);
    expect(File('${outside.path}/victim-1.bin').readAsBytesSync(), secret);
    expect(
      mediaKeptIn(path),
      [sound],
      reason:
          'what the project keeps for that asset is the file it was '
          'carried from — not the one its name pointed at',
    );
  });

  test('a name the document lists that is not under the media folder is '
      'not a media entry a save leaves behind', () {
    const minted = '${anicelMediaEntryPrefix}1a2b3c4d-9f8e7d6c-take.wav';
    const climbing = '$anicelMediaEntryPrefix../../outside/planted-1.bin';
    final path = crafted(
      assets: const [],
      entries: {
        'x': secret,
        'cels/ab-cd.celz': secret,
        climbing: secret,
        minted: secret,
      },
    );

    final left = mediaLeftBehind(
      projectFilePath: path,
      mediaInFile: {'x', 'cels/ab-cd.celz', climbing, minted, 'media/gone-1'},
      mediaToStore: const {},
    );

    expect(
      [for (final entry in left) entry.name],
      ['../../outside/planted-1.bin', '1a2b3c4d-9f8e7d6c-take.wav'],
      reason: 'cut of their folder, and the room judges what is left',
    );
  });
}
