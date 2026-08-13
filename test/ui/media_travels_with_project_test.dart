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
  tearDown(() async {
    try {
      await directory.delete(recursive: true);
    } on Object {
      // A locked file on Windows must not fail the suite.
    }
  });

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
    await editor.saveProjectToFile(projectPath);

    final source = writeMedia('bgm.wav', 40 * 1024);
    final expected = File(source).readAsBytesSync();
    editor.importMediaFiles([source], copyIntoProject: true);
    await editor.saveProjectToFile(projectPath);
    editor.dispose();

    // The whole point: the file the project was imported from is gone.
    File(source).deleteSync();

    final reopened = session();
    await reopened.openProjectFromFile(projectPath);
    final asset = reopened.mediaAssets.single;
    final sources = projectMediaSources(
      project: reopened.repository.requireProject(),
      projectFilePath: projectPath,
      mediaEntryNames: reopened.mediaEntryNames,
    );
    expect(sources[asset.path], isA<MediaArchiveBytes>());
    expect(sources[asset.path]!.readSync(), expected);
    reopened.dispose();
  });

  test('a movie stays outside, however big the project gets', () async {
    // The kind law where it costs something: a three-gigabyte reference
    // would make the project unopenable, so video is never carried.
    final editor = session();
    final projectPath = '${directory.path}/scene.anicel';
    await editor.saveProjectToFile(projectPath);

    final movie = writeMedia('reference.mp4', 2048);
    editor.importMediaFiles([movie], copyIntoProject: false);
    await editor.saveProjectToFile(projectPath);
    editor.dispose();

    final reopened = session();
    await reopened.openProjectFromFile(projectPath);
    expect(reopened.mediaAssets.single.kind, MediaAssetKind.video);
    expect(
      reopened.mediaEntryNames,
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
    await editor.saveProjectToFile(first);

    final source = writeMedia('voice.wav', 12 * 1024);
    final expected = File(source).readAsBytesSync();
    editor.importMediaFiles([source], copyIntoProject: true);
    await editor.saveProjectToFile(first);

    // Deleted BEFORE the save-as, deliberately. With the original still
    // sitting there the copy could be fed from it and the test would pass
    // without the archive-to-archive path ever running — which is exactly
    // what it did until a mutation said so. Now the first `.anicel` is the
    // only place those bytes exist.
    File(source).deleteSync();

    final second = '${directory.path}/second.anicel';
    await editor.saveProjectToFile(second);
    editor.dispose();

    // And now the file it was copied from is gone too; only the copy
    // remains.
    File(first).deleteSync();

    final reopened = session();
    await reopened.openProjectFromFile(second);
    final asset = reopened.mediaAssets.single;
    final sources = projectMediaSources(
      project: reopened.repository.requireProject(),
      projectFilePath: second,
      mediaEntryNames: reopened.mediaEntryNames,
    );
    expect(sources[asset.path]!.readSync(), expected);
    reopened.dispose();
  });

  test('saving twice does not rewrite the media area', () async {
    // Media is written once and never edited, so an asset already inside
    // is a survivor of the append like any untouched cel. Re-streaming it
    // would rewrite the project's whole media area to change one drawing.
    final editor = session();
    final projectPath = '${directory.path}/scene.anicel';
    await editor.saveProjectToFile(projectPath);
    final source = writeMedia('bgm.wav', 64 * 1024);
    editor.importMediaFiles([source], copyIntoProject: true);
    await editor.saveProjectToFile(projectPath);

    final afterFirst = File(projectPath).lengthSync();
    await editor.saveProjectToFile(projectPath);
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
    await editor.saveProjectToFile(projectPath);
    final source = writeMedia('shared.wav', 8 * 1024);
    editor.importMediaFiles([source], copyIntoProject: false);
    await editor.saveProjectToFile(projectPath);
    editor.dispose();

    final reopened = session();
    await reopened.openProjectFromFile(projectPath);
    expect(reopened.mediaEntryNames, isEmpty);
    // And it still resolves, by path, exactly as it always did.
    expect(reopened.mediaAssets.single.path, source.replaceAll('\\', '/'));
    reopened.dispose();
  });

  test('the entry name is stable, so a re-save finds the same bytes',
      () async {
    final source = writeMedia('a.wav', 100);
    expect(
      anicelMediaEntryName(source),
      anicelMediaEntryName(source),
    );
  });
}
