import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The import's copy-or-reference choice, at the file level.
///
/// COPY is the Pro Tools/Logic rule — the project folder owns its sounds,
/// so a Drive folder opened on another machine has them — with
/// byte-identical re-imports REUSED and name collisions unique-suffixed,
/// never overwritten. REFERENCE is the default the import window offers:
/// nothing is duplicated and the project points at the file where the user
/// keeps it.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qa-media-copy-test');
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

  test('an unsaved project references the original in place '
      '(nowhere to copy beside yet)', () {
    final session = sessionWithFakeConforms();
    final source = File('${directory.path}/voice.wav')
      ..writeAsBytesSync([1, 2, 3]);
    // Same file, spelled the one way the pool spells paths — a degraded
    // copy is a reference, and references normalize like everything else.
    expect(
      session.importAudioFile(source.path, copyIntoProject: true),
      source.path.replaceAll('\\', '/'),
    );
    session.dispose();
  });

  test('a saved project copies imports into Media/, reuses byte-identical '
      're-imports and unique-names true collisions', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    // The asset layout normalizes to forward slashes (fine on Windows too).
    final mediaDirectory =
        '${directory.path.replaceAll('\\', '/')}/scene.assets/Media';

    final external = Directory('${directory.path}/외부소재')
      ..createSync(recursive: true);
    final source = File('${external.path}/발소리.wav')
      ..writeAsBytesSync([1, 2, 3, 4]);

    final imported = session.importAudioFile(
      source.path,
      copyIntoProject: true,
    );
    expect(imported, '$mediaDirectory/발소리.wav');
    expect(File(imported).readAsBytesSync(), [1, 2, 3, 4]);

    // Re-importing the same bytes reuses the copy — no -1 stacking.
    expect(
      session.importAudioFile(source.path, copyIntoProject: true),
      imported,
    );

    // A DIFFERENT sound with the same name walks to a unique name.
    final rival = Directory('${directory.path}/다른폴더')
      ..createSync(recursive: true);
    final clashing = File('${rival.path}/발소리.wav')
      ..writeAsBytesSync([9, 9, 9, 9]);
    final importedRival = session.importAudioFile(
      clashing.path,
      copyIntoProject: true,
    );
    expect(importedRival, '$mediaDirectory/발소리-1.wav');
    expect(File(imported).readAsBytesSync(), [1, 2, 3, 4]); // untouched

    // Importing a path already under Media/ (the browser re-offering a
    // pool entry) is a no-op copy.
    expect(session.importAudioFile(imported, copyIntoProject: true), imported);
    session.dispose();
  });

  test('REFERENCE leaves the file where it is, even with somewhere to copy '
      'it to', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final mediaDirectory = Directory(
      '${directory.path.replaceAll('\\', '/')}/scene.assets/Media',
    );

    final external = Directory('${directory.path}/외부소재')
      ..createSync(recursive: true);
    final source = File('${external.path}/발소리.wav')
      ..writeAsBytesSync([1, 2, 3, 4]);

    expect(
      session.importAudioFile(source.path, copyIntoProject: false),
      source.path.replaceAll('\\', '/'),
    );
    // Nothing was written beside the project: the whole point of the
    // reference default is that a 3GB source costs 0 bytes to import.
    expect(mediaDirectory.existsSync(), isFalse);
    session.dispose();
  });

  test('the media browser import registers the COPY in the pool, and the '
      'REFERENCE keeps the original path', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final root = directory.path.replaceAll('\\', '/');
    final copied = File('${directory.path}/bgm.wav')
      ..writeAsBytesSync([5, 6, 7]);
    final referenced = File('${directory.path}/guide.wav')
      ..writeAsBytesSync([8, 9]);

    session.importMediaFiles([copied.path], copyIntoProject: true);
    session.importMediaFiles([referenced.path], copyIntoProject: false);

    expect(session.mediaAssets.map((asset) => asset.path), [
      '$root/scene.assets/Media/bgm.wav',
      '$root/guide.wav',
    ]);
    // Source tracking is what a COPY carries so the "original changed"
    // badge has two paths to compare; a reference is its own original.
    expect(
      session.mediaAssets.map((asset) => asset.sourcePath),
      [copied.path.replaceAll('\\', '/'), null],
      reason: 'both ends of the comparison in the recorded spelling — '
          'otherwise every reference on Windows looks like a copy',
    );
    session.dispose();
  });

  test('a failed copy falls back to referencing the original '
      '(import must degrade, never refuse)', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final missing = '${directory.path}/없는파일.wav';
    expect(
      session.importAudioFile(missing, copyIntoProject: true),
      missing.replaceAll('\\', '/'),
    );
    session.dispose();
  });

  test('registering a reference in the project copies it, relinks the pool '
      'and records where it came from — in ONE undo', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final root = directory.path.replaceAll('\\', '/');
    final outside = File('${directory.path}/guide.wav')
      ..writeAsBytesSync([4, 5, 6]);

    session.importMediaFiles([outside.path], copyIntoProject: false);
    expect(session.mediaAssets.single.path, '$root/guide.wav');

    expect(session.promoteMediaAssetIntoProject('$root/guide.wav'), isTrue);

    final promoted = session.mediaAssets.single;
    expect(promoted.path, '$root/scene.assets/Media/guide.wav');
    expect(File(promoted.path).readAsBytesSync(), [4, 5, 6]);
    expect(promoted.sourcePath, '$root/guide.wav');
    expect(
      promoted.sourceStamp,
      isNotNull,
      reason: 'a copy carries the stamp its "original changed" badge needs',
    );

    session.undo();
    expect(session.mediaAssets.single.path, '$root/guide.wav');
    expect(
      session.mediaAssets.single.sourcePath,
      isNull,
      reason: 'the promotion took the source tracking with it',
    );
    session.dispose();
  });

  test('promoting something already in the project changes nothing and '
      'spends no undo step', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final source = File('${directory.path}/bgm.wav')
      ..writeAsBytesSync([7, 7]);
    session.importMediaFiles([source.path], copyIntoProject: true);
    final inside = session.mediaAssets.single.path;

    expect(session.promoteMediaAssetIntoProject(inside), isFalse);
    expect(session.mediaAssets.single.path, inside);
    session.dispose();
  });

  test('the pool kind is detected either way — a referenced movie is still '
      'a movie', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final movie = File('${directory.path}/reference.mp4')
      ..writeAsBytesSync([0, 0, 0, 24]);

    session.importMediaFiles([movie.path], copyIntoProject: false);

    expect(session.mediaAssets.single.kind, MediaAssetKind.video);
    expect(
      session.mediaAssets.single.path,
      movie.path.replaceAll('\\', '/'),
      reason: 'the 3GB case: a referenced movie is not copied anywhere',
    );
    session.dispose();
  });

  test('a REFERENCE is stamped with an identity, not just a copy', () async {
    // The gap this closes. `sourceStamp` answers "did the original we
    // copied from change?", so it is stamped for copies only — and relink's
    // subject is precisely the reference, which has no original to compare
    // against and used to carry nothing at all.
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final referenced = File('${directory.path}/guide.wav')
      ..writeAsBytesSync(List<int>.filled(321, 4));

    session.importMediaFiles([referenced.path], copyIntoProject: false);

    final asset = session.mediaAssets.single;
    expect(asset.sourcePath, isNull, reason: 'a reference has no origin');
    expect(asset.sourceStamp, isNull, reason: 'nothing was copied');
    expect(asset.identity, isNotNull, reason: 'but it can still go missing');
    expect(asset.identity!.lengthBytes, 321);
    session.dispose();
  });

  test('a COPY is stamped too, and the two fields stay different', () async {
    // Both are recorded and they are not interchangeable: identity
    // describes the file at `path` (the copy, which relink would have to
    // find), the stamp describes the origin it came from.
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final source = File('${directory.path}/bgm.wav')
      ..writeAsBytesSync(List<int>.filled(77, 9));

    session.importMediaFiles([source.path], copyIntoProject: true);

    final asset = session.mediaAssets.single;
    expect(asset.sourcePath, source.path.replaceAll('\\', '/'));
    expect(asset.sourceStamp, isNotNull);
    expect(asset.identity!.lengthBytes, 77);
    expect(
      asset.sourceStamp,
      isNot(asset.identity!.toJson()),
      reason: 'the stamp carries an mtime; identity must not',
    );
    session.dispose();
  });

  test('import-to-browse stamps one too', () async {
    // A fourth registration path that carried no evidence whatsoever.
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final foot = File('${directory.path}/foot.wav')
      ..writeAsBytesSync(List<int>.filled(12, 1));

    session.addMediaAssets([foot.path]);

    expect(session.mediaAssets.single.identity!.lengthBytes, 12);
    session.dispose();
  });

  test('an identity survives a save and reopen', () async {
    // It is worthless if it does not: the whole point is to still be there
    // when the file is not.
    final session = sessionWithFakeConforms();
    final path = '${directory.path}/scene.anicel';
    await session.saveProjectToFile(path);
    final referenced = File('${directory.path}/guide.wav')
      ..writeAsBytesSync(List<int>.filled(555, 2));
    session.importMediaFiles([referenced.path], copyIntoProject: false);
    await session.saveProjectToFile(path);
    session.dispose();

    final reopened = sessionWithFakeConforms();
    await reopened.openProjectFromFile(path);
    expect(reopened.mediaAssets.single.identity!.lengthBytes, 555);
    reopened.dispose();
  });
}
