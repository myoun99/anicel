import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The fingerprint's LIFE: recorded for free, kept out of the project,
/// written to the file, and read back pointing at the right asset.
///
/// 🔑 The one that matters most is the dirty test. The whole reason these
/// live outside `Project` is that recording one is not something the user
/// did — a viewer showing a picture must not make the title bar say the
/// project is unsaved. Put them in the project and everything else still
/// works; that property is the only thing that breaks, silently, and the
/// user would just see save prompts they did not earn.
void main() {
  late Directory directory;
  late String projectPath;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa-fingerprint-');
    projectPath = '${directory.path.replaceAll('\\', '/')}/scene.anicel';
  });

  tearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // Windows handles.
    }
  });

  EditorSessionManager session() =>
      EditorSessionManager(initialProject: createDefaultProject());

  Map<String, dynamic> projectJsonOf(String archivePath) {
    final archive = ZipDecoder().decodeBytes(
      File(archivePath).readAsBytesSync(),
    );
    return jsonDecode(
          utf8.decode(archive.findFile('project.json')!.readBytes()!),
        )
        as Map<String, dynamic>;
  }

  String makeFile(String name, int fill, {int length = 512}) {
    final path = '${directory.path.replaceAll('\\', '/')}/$name';
    File(path)
      ..createSync()
      ..writeAsBytesSync(List<int>.filled(length, fill));
    return path;
  }

  test('🚨 remembering a fingerprint does NOT dirty the project', () async {
    final s = session();
    final movie = makeFile('참고영상.mp4', 7);
    s.importMediaFiles([movie], copyIntoProject: false);
    await s.saveProjectToFile(projectPath);
    expect(s.hasUnsavedChanges, isFalse, reason: 'a save leaves it clean');

    s.rememberMediaFingerprint(movie, 0x1234abcd);

    expect(
      s.hasUnsavedChanges,
      isFalse,
      reason: 'looking at a file is not editing the project — a save prompt '
          'here is the failure this design exists to prevent',
    );
    s.dispose();
  });

  test('it survives a save and an open, still pointing at its asset', () async {
    final s = session();
    final movie = makeFile('참고영상.mp4', 7);
    s.importMediaFiles([movie], copyIntoProject: false);
    s.rememberMediaFingerprint(movie, 0x1234abcd);
    await s.saveProjectToFile(projectPath);
    s.dispose();

    final reopened = session();
    await reopened.openProjectFromFile(projectPath);

    final identity = reopened.recordedMediaIdentity(movie);
    expect(identity, isNotNull);
    expect(identity!.crc32, 0x1234abcd);
    expect(
      identity.lengthBytes,
      512,
      reason: 'the length still comes from the asset, the CRC from beside it',
    );
    reopened.dispose();
  });

  test('an asset REMOVED from the pool takes its fingerprint with it', () async {
    // Otherwise the file grows one row per asset the project has ever
    // held, and a path the project stopped using keeps describing bytes
    // nothing asks about.
    final s = session();
    final movie = makeFile('참고영상.mp4', 7);
    s.importMediaFiles([movie], copyIntoProject: false);
    s.rememberMediaFingerprint(movie, 0x1234abcd);
    await s.saveProjectToFile(projectPath);

    s.removeMediaAsset(movie);
    await s.saveProjectToFile(projectPath);
    s.dispose();

    final reopened = session();
    await reopened.openProjectFromFile(projectPath);
    expect(reopened.debugMediaFingerprints.isEmpty, isTrue);
    reopened.dispose();
  });

  test('a project with no fingerprints writes no key, and still opens', () async {
    // Every project written before this existed. The absence has to be an
    // ordinary state, not a missing field somebody has to handle.
    final s = session();
    s.importMediaFiles([makeFile('참고영상.mp4', 7)], copyIntoProject: false);
    await s.saveProjectToFile(projectPath);
    s.dispose();

    expect(
      projectJsonOf(projectPath).containsKey('mediaCrcs'),
      isFalse,
      reason: 'nothing to say, so nothing written',
    );

    final reopened = session();
    await reopened.openProjectFromFile(projectPath);
    expect(reopened.debugMediaFingerprints.isEmpty, isTrue);
    reopened.dispose();
  });

  // ⚠️ "an import fingerprints for free" is asserted in
  // `test/ui/media_import_session_test.dart` instead — that file already
  // has the binding and the real PNG an image import needs, and a second
  // copy of that harness here would be a worse test in a worse place.
}
