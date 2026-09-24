import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/project_media_sources.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/temp_dir.dart';

/// The point of the whole media move: a project stops depending on files
/// sitting where it last saw them.
///
/// Everything below deletes the original after saving. That is not an edge
/// case — it is what "travels with the project" means, and before this it
/// was the ordinary way a project lost its sound.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-media-travel');
  });
  tearDown(() => deleteTempQuietly(directory));

  EditorSessionManager session() => EditorSessionManager(
    initialProject: createDefaultProject(),
    audioConformStore: AudioConformStore(
      resolveConformPath: (_) => null,
      runner: (request) async => const ConformResult(
        outcome: ConformOutcome.undecodable,
        error: 'test stub',
      ),
      log: (_) {},
    ),
  );

  String writeMedia(String name, int length) {
    final path = '${directory.path}/$name';
    File(path).writeAsBytesSync(
      Uint8List.fromList(List<int>.generate(length, (i) => (i * 7) % 251)),
    );
    return path;
  }

  test('a sound survives its original being deleted', () async {
    final editor = session();
    final projectPath = '${directory.path}/scene.anicel';
    await editor.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);

    final source = writeMedia('bgm.wav', 40 * 1024);
    final expected = File(source).readAsBytesSync();
    await editor.mediaPool.importMediaFiles([source], copyIntoProject: true);
    await editor.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);
    editor.dispose();

    // The whole point: the file the project was imported from is gone.
    File(source).deleteSync();

    final reopened = session();
    await reopened.projectDoor.openProjectFromFile(projectPath);
    final asset = reopened.mediaPool.mediaAssets.single;
    final sources = projectMediaSources(
      project: reopened.repository.requireProject(),
      projectFilePath: projectPath,
      mediaInFile: reopened.projectFile.mediaInFile,
    );
    expect(sources[asset.carry], isA<MediaArchiveBytes>());
    // Read through the door every consumer uses: a carried file is held
    // FRAMED when it compresses, and the archive then holds its blob —
    // what the save streams is not what the file says.
    expect(
      reopened.projectFile.mediaByteSourceFor(asset.path).readSync(),
      expected,
    );
    reopened.dispose();
  });

  test('a movie imported as a REFERENCE stays outside', () async {
    // Not a kind ceiling — that died 2026-08-14, and the kind's default
    // went too on 2026-09-16 (decisions on seedImportSettings); a movie the
    // user asks to carry IS carried. This fixture says copyIntoProject:
    // false, so what it pins is that the reference answer is honoured:
    // carried is the whole answer, and here the answer is no.
    final editor = session();
    final projectPath = '${directory.path}/scene.anicel';
    await editor.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);

    final movie = writeMedia('reference.mp4', 2048);
    await editor.mediaPool.importMediaFiles([movie], copyIntoProject: false);
    await editor.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);
    editor.dispose();

    final reopened = session();
    await reopened.projectDoor.openProjectFromFile(projectPath);
    expect(reopened.mediaPool.mediaAssets.single.kind, MediaAssetKind.video);
    expect(
      reopened.projectFile.mediaInFile,
      isEmpty,
      reason: 'nothing about a movie is carried',
    );
    reopened.dispose();
  });

  test('SAVE AS carries the media into the copy', () async {
    // The reason this landed with the save wiring rather than after it:
    // a build where saves carry media but save-as does not is a build
    // that quietly makes copies with no sound.
    final editor = session();
    final first = '${directory.path}/first.anicel';
    await editor.projectDoor.saveProjectToFile(first, asked: SaveAsked.byAPerson);

    final source = writeMedia('voice.wav', 12 * 1024);
    final expected = File(source).readAsBytesSync();
    await editor.mediaPool.importMediaFiles([source], copyIntoProject: true);
    await editor.projectDoor.saveProjectToFile(first, asked: SaveAsked.byAPerson);

    // Deleted BEFORE the save-as, deliberately. With the original still
    // sitting there the copy could be fed from it and the test would pass
    // without the archive-to-archive path ever running — which is exactly
    // what it did until a mutation said so. Now the first `.anicel` is the
    // only place those bytes exist.
    File(source).deleteSync();

    final second = '${directory.path}/second.anicel';
    await editor.projectDoor.saveProjectToFile(second, asked: SaveAsked.byAPerson);
    editor.dispose();

    // And now the file it was copied from is gone too; only the copy
    // remains.
    File(first).deleteSync();

    final reopened = session();
    await reopened.projectDoor.openProjectFromFile(second);
    final asset = reopened.mediaPool.mediaAssets.single;
    final sources = projectMediaSources(
      project: reopened.repository.requireProject(),
      projectFilePath: second,
      mediaInFile: reopened.projectFile.mediaInFile,
    );
    expect(sources[asset.carry], isA<MediaArchiveBytes>());
    // Through the consumers' door — see the test above.
    expect(
      reopened.projectFile.mediaByteSourceFor(asset.path).readSync(),
      expected,
    );
    reopened.dispose();
  });

  test('saving twice does not rewrite the media area', () async {
    // Media is written once and never edited, so an asset already inside
    // is a survivor of the append like any untouched cel. Re-streaming it
    // would rewrite the project's whole media area to change one drawing.
    final editor = session();
    final projectPath = '${directory.path}/scene.anicel';
    await editor.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);
    final source = writeMedia('bgm.wav', 64 * 1024);
    await editor.mediaPool.importMediaFiles([source], copyIntoProject: true);
    await editor.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);

    final afterFirst = File(projectPath).lengthSync();
    await editor.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);
    final afterSecond = File(projectPath).lengthSync();
    editor.dispose();

    expect(
      afterSecond - afterFirst,
      lessThan(4 * 1024),
      reason: 'a second save must not append the sound again',
    );
  });

  test('a sound imported as a REFERENCE stays outside', () async {
    // The toggle still means something. Someone sharing an original with
    // another tool asked for a link, and a project that swallowed it
    // anyway would be answering a question nobody posed.
    final editor = session();
    final projectPath = '${directory.path}/scene.anicel';
    await editor.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);
    final source = writeMedia('shared.wav', 8 * 1024);
    await editor.mediaPool.importMediaFiles([source], copyIntoProject: false);
    await editor.projectDoor.saveProjectToFile(projectPath, asked: SaveAsked.byAPerson);
    editor.dispose();

    final reopened = session();
    await reopened.projectDoor.openProjectFromFile(projectPath);
    expect(reopened.projectFile.mediaInFile, isEmpty);
    // And it still resolves, by path, exactly as it always did.
    expect(reopened.mediaPool.mediaAssets.single.path, source.replaceAll('\\', '/'));
    reopened.dispose();
  });

  test('the entry name is stable, so a re-save finds the same bytes',
      () async {
    final editor = session();
    final source = writeMedia('a.wav', 100);
    await editor.mediaPool.importMediaFiles([source], copyIntoProject: true);
    final carry = editor.mediaPool.mediaAssets.single.carry!;
    editor.dispose();
    expect(
      anicelMediaEntryName(carry),
      anicelMediaEntryName((poolPath: carry.poolPath, token: carry.token)),
    );
  });
}
