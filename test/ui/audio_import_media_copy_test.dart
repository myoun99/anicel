import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/audio/audio_conform_pipeline.dart';
import 'package:anicel/src/ui/audio/audio_conform_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Copy-on-import (audio program wiring): an imported sound is copied into
/// `<project>.assets/Media/` so the project folder owns its sounds — with
/// byte-identical re-imports REUSED and name collisions unique-suffixed,
/// never overwritten.
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
    expect(session.importAudioFile(source.path), source.path);
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

    final imported = session.importAudioFile(source.path);
    expect(imported, '$mediaDirectory/발소리.wav');
    expect(File(imported).readAsBytesSync(), [1, 2, 3, 4]);

    // Re-importing the same bytes reuses the copy — no -1 stacking.
    expect(session.importAudioFile(source.path), imported);

    // A DIFFERENT sound with the same name walks to a unique name.
    final rival = Directory('${directory.path}/다른폴더')
      ..createSync(recursive: true);
    final clashing = File('${rival.path}/발소리.wav')
      ..writeAsBytesSync([9, 9, 9, 9]);
    final importedRival = session.importAudioFile(clashing.path);
    expect(importedRival, '$mediaDirectory/발소리-1.wav');
    expect(File(imported).readAsBytesSync(), [1, 2, 3, 4]); // untouched

    // Importing a path already under Media/ (the browser re-offering a
    // pool entry) is a no-op copy.
    expect(session.importAudioFile(imported), imported);
    session.dispose();
  });

  test('the media browser import registers the COPY in the pool', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final source = File('${directory.path}/bgm.wav')
      ..writeAsBytesSync([5, 6, 7]);

    session.importMediaFiles([source.path]);
    expect(
      session.mediaAssets.map((asset) => asset.path),
      ['${directory.path.replaceAll('\\', '/')}/scene.assets/Media/bgm.wav'],
    );
    session.dispose();
  });

  test('a failed copy falls back to referencing the original '
      '(import must degrade, never refuse)', () async {
    final session = sessionWithFakeConforms();
    await session.saveProjectToFile('${directory.path}/scene.anicel');
    final missing = '${directory.path}/없는파일.wav';
    expect(session.importAudioFile(missing), missing);
    session.dispose();
  });
}
