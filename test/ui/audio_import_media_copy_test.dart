import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The import's CARRY-or-reference choice, at the file level.
///
/// Carrying used to mean copying the file into `<project>.assets/Media/`,
/// which was the last thing left making a `.anicel` grow a sibling folder.
/// It now means the SAVE writes the bytes inside the archive, so an import
/// records the file where the user keeps it either way and the answer
/// lives in [MediaAsset.carried] alone.
///
/// That makes the pool entry the only place the choice is written down,
/// which is why every registration path is checked here. A site that
/// forgets to stamp it no longer leaves a stray copy behind as evidence —
/// it silently leaves the file outside the project instead.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-media-carry-test');
  });

  tearDown(() => directory.delete(recursive: true));

  EditorSessionManager sessionWithFakeConforms() => EditorSessionManager(
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

  Set<String> archived(EditorSessionManager session) =>
      projectArchivedMediaPaths(session.repository.requireProject());

  test('carrying copies NOTHING — the project records the original where '
      'the user keeps it, and grows no sibling folder', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final root = directory.path.replaceAll('\\', '/');

    final external = Directory('${directory.path}/외부소재')
      ..createSync(recursive: true);
    final source = File('${external.path}/발소리.wav')
      ..writeAsBytesSync([1, 2, 3, 4]);

    session.importMediaFiles([source.path], copyIntoProject: true);

    final asset = session.mediaAssets.single;
    expect(asset.path, '$root/외부소재/발소리.wav');
    expect(asset.carried, isTrue);
    expect(
      Directory('$root/scene.assets').existsSync(),
      isFalse,
      reason: 'the last site that made a .anicel grow a sibling',
    );
    expect(File(asset.path).readAsBytesSync(), [1, 2, 3, 4]);
    expect(
      archived(session),
      {'$root/외부소재/발소리.wav'},
      reason: 'the pool entry is what the save reads',
    );
    session.dispose();
  });

  test('a REFERENCE records the same path and asks the save for nothing',
      () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final source = File('${directory.path}/guide.wav')
      ..writeAsBytesSync([8, 9]);

    session.importMediaFiles([source.path], copyIntoProject: false);

    final asset = session.mediaAssets.single;
    expect(asset.path, source.path.replaceAll('\\', '/'));
    expect(asset.carried, isFalse);
    expect(archived(session), isEmpty);
    session.dispose();
  });

  test('an UNSAVED project carries just the same', () async {
    // It could not before: with nothing to sit beside, the copy degraded
    // to a reference and the user's answer was lost without a word. There
    // is no copy to fail now, so the choice survives until the first save
    // is there to honour it.
    final session = sessionWithFakeConforms();
    final source = File('${directory.path}/bgm.wav')..writeAsBytesSync([7]);

    session.importMediaFiles([source.path], copyIntoProject: true);

    expect(session.mediaAssets.single.carried, isTrue);
    expect(archived(session), {source.path.replaceAll('\\', '/')});
    session.dispose();
  });

  test('a movie the user asked to carry IS carried', () async {
    // The kind used to veto this at the archive, which meant the flag the
    // user set said yes and the save said no with nothing on screen
    // explaining the disagreement. The kind decides the DEFAULT now (a
    // movie starts as a reference) and the answer decides the bytes.
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final movie = File('${directory.path}/reference.mp4')
      ..writeAsBytesSync([0, 0, 0, 24]);

    session.importMediaFiles([movie.path], copyIntoProject: true);

    final asset = session.mediaAssets.single;
    expect(asset.kind, MediaAssetKind.video);
    expect(asset.carried, isTrue);
    expect(
      archived(session),
      contains(asset.path),
      reason: 'what the user answered is what the save writes',
    );
    session.dispose();
  });

  test('and a movie left alone stays outside', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final movie = File('${directory.path}/take02.mp4')
      ..writeAsBytesSync([0, 0, 0, 24]);

    session.importMediaFiles([movie.path], copyIntoProject: false);

    expect(session.mediaAssets.single.carried, isFalse);
    expect(archived(session), isEmpty);
    session.dispose();
  });

  test('importAudioFile hands back the source in the pool spelling', () {
    final session = sessionWithFakeConforms();
    final source = File('${directory.path}/voice.wav')
      ..writeAsBytesSync([1, 2, 3]);
    expect(
      session.importAudioFile(source.path),
      source.path.replaceAll('\\', '/'),
      reason: 'the pool is keyed by path, so a backslash spelling would be '
          'a second asset for one file',
    );
    session.dispose();
  });

  test('a missing file still registers — an import degrades, never refuses',
      () {
    final session = sessionWithFakeConforms();
    final missing = '${directory.path}/없는파일.wav';
    expect(session.importAudioFile(missing), missing.replaceAll('\\', '/'));
    session.dispose();
  });

  test('registering a reference marks it carried in ONE undo, and moves '
      'nothing on disk', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final root = directory.path.replaceAll('\\', '/');
    final outside = File('${directory.path}/guide.wav')
      ..writeAsBytesSync([4, 5, 6]);

    session.importMediaFiles([outside.path], copyIntoProject: false);
    expect(session.mediaAssets.single.carried, isFalse);

    expect(session.promoteMediaAssetIntoProject('$root/guide.wav'), isTrue);

    final promoted = session.mediaAssets.single;
    expect(promoted.carried, isTrue);
    expect(
      promoted.path,
      '$root/guide.wav',
      reason: 'same sound, same address — nothing to relink',
    );
    expect(File('$root/guide.wav').readAsBytesSync(), [4, 5, 6]);
    expect(archived(session), {'$root/guide.wav'});

    session.undo();
    expect(session.mediaAssets.single.carried, isFalse);
    expect(archived(session), isEmpty);
    session.dispose();
  });

  test('promoting something already carried changes nothing and spends no '
      'undo step', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final source = File('${directory.path}/bgm.wav')..writeAsBytesSync([7, 7]);
    session.importMediaFiles([source.path], copyIntoProject: true);
    final path = session.mediaAssets.single.path;

    expect(session.promoteMediaAssetIntoProject(path), isFalse);
    expect(session.mediaAssets.single.carried, isTrue);
    session.dispose();
  });

  test('promoting a MOVIE works — the kind chose the default, not the '
      'answer', () async {
    // It used to be refused by kind. The user reversed that on 08-14: a
    // three-second reference take is exactly the movie someone means to
    // put inside the file, and a menu entry that flips and does nothing
    // was the alternative.
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final movie = File('${directory.path}/참고.mp4')
      ..writeAsBytesSync([0, 0, 0, 24]);
    session.importMediaFiles([movie.path], copyIntoProject: false);
    final path = session.mediaAssets.single.path;

    expect(session.promoteMediaAssetIntoProject(path), isTrue);
    expect(session.mediaAssets.single.carried, isTrue);
    expect(
      session.promoteMediaAssetIntoProject(path),
      isFalse,
      reason: 'and there is nothing left to promote the second time',
    );
    session.dispose();
  });

  test('promoting an unknown path is refused', () async {
    final session = sessionWithFakeConforms();
    expect(session.promoteMediaAssetIntoProject('/nowhere/x.wav'), isFalse);
    session.dispose();
  });

  test('a REFERENCE is stamped with an identity', () async {
    // Relink's subject is precisely the reference — the asset that can go
    // missing — so it is the one that must carry evidence of which file
    // it was.
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final referenced = File('${directory.path}/guide.wav')
      ..writeAsBytesSync(List<int>.filled(321, 4));

    session.importMediaFiles([referenced.path], copyIntoProject: false);

    final asset = session.mediaAssets.single;
    expect(asset.identity, isNotNull);
    expect(asset.identity!.lengthBytes, 321);
    session.dispose();
  });

  test('a CARRIED asset is stamped too — it has an original on disk until '
      'the first save', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final source = File('${directory.path}/bgm.wav')
      ..writeAsBytesSync(List<int>.filled(77, 9));

    session.importMediaFiles([source.path], copyIntoProject: true);

    expect(session.mediaAssets.single.identity!.lengthBytes, 77);
    session.dispose();
  });

  test('import-to-browse stamps one too, and references by default', () async {
    // No window was answered here — it registers a file that was already
    // on disk, so it registers it as what it is.
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final foot = File('${directory.path}/foot.wav')
      ..writeAsBytesSync(List<int>.filled(12, 1));

    session.addMediaAssets([foot.path]);

    expect(session.mediaAssets.single.identity!.lengthBytes, 12);
    expect(session.mediaAssets.single.carried, isFalse);
    session.dispose();
  });

  test('the carry answer survives a save and reopen', () async {
    final session = sessionWithFakeConforms();
    final path = '${directory.path}/scene.anicel';
    await session.saveProjectToFile(path);
    final carriedFile = File('${directory.path}/발소리.wav')
      ..writeAsBytesSync(List<int>.filled(555, 2));
    final referenced = File('${directory.path}/guide.wav')
      ..writeAsBytesSync(List<int>.filled(40, 3));
    session.importMediaFiles([carriedFile.path], copyIntoProject: true);
    session.importMediaFiles([referenced.path], copyIntoProject: false);
    await session.saveProjectToFile(path);
    session.dispose();

    final reopened = sessionWithFakeConforms();
    await reopened.openProjectFromFile(path);
    MediaAsset assetEndingIn(String suffix) => reopened.mediaAssets.singleWhere(
      (asset) => asset.path.endsWith(suffix),
    );
    expect(assetEndingIn('/발소리.wav').carried, isTrue);
    expect(assetEndingIn('/guide.wav').carried, isFalse);
    expect(assetEndingIn('/발소리.wav').identity!.lengthBytes, 555);
    reopened.dispose();
  });
}
