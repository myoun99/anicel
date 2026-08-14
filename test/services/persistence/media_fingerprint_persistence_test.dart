import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32;
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

  /// Records the fingerprint the way production does — from the bytes.
  void fingerprint(EditorSessionManager s, String path) =>
      s.rememberMediaFingerprint(path, File(path).readAsBytesSync());

  test('🚨 remembering a fingerprint does NOT dirty the project', () async {
    final s = session();
    final movie = makeFile('참고영상.mp4', 7);
    s.importMediaFiles([movie], copyIntoProject: false);
    await s.saveProjectToFile(projectPath);
    expect(s.hasUnsavedChanges, isFalse, reason: 'a save leaves it clean');

    fingerprint(s, movie);

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
    fingerprint(s, movie);
    await s.saveProjectToFile(projectPath);
    s.dispose();

    final reopened = session();
    await reopened.openProjectFromFile(projectPath);

    final identity = reopened.recordedMediaIdentity(movie);
    expect(identity, isNotNull);
    expect(
      identity!.crc32,
      anicelCrc32(File(movie).readAsBytesSync()),
      reason: 'it has to be the CRC of the actual bytes, not merely some '
          'number that survived the round trip',
    );
    expect(identity.lengthBytes, 512);
    reopened.dispose();
  });

  test('🚨 both halves come from ONE read of the file', () async {
    // The length on the asset is imprinted at first registration and never
    // again; the CRC is re-taken whenever something reads the bytes. Weld
    // one to the other and an edited file is described as a revision that
    // never existed — and relink then rules OUT the very file it is
    // hunting, because the recorded length disagrees with what is on disk
    // and `compare` treats a length mismatch as decisive.
    final s = session();
    final movie = makeFile('참고영상.mp4', 7);
    s.importMediaFiles([movie], copyIntoProject: false);
    expect(s.recordedMediaIdentity(movie)!.lengthBytes, 512);

    // The file is edited in place: different size, different content.
    File(movie).writeAsBytesSync(List<int>.filled(900, 9));
    fingerprint(s, movie);

    final identity = s.recordedMediaIdentity(movie)!;
    expect(
      identity.lengthBytes,
      900,
      reason: 'the fingerprint answers with its OWN length, not the stale '
          'one the import imprinted',
    );
    expect(identity.crc32, anicelCrc32(File(movie).readAsBytesSync()));
    s.dispose();
  });

  test('🚨 a RELINK carries the fingerprint to the new path', () async {
    // The cruel case: relink is the feature fingerprints exist for, and it
    // is also a place a pool path changes. The store is keyed by path and
    // the save keeps only keys the pool still holds — so a relink that does
    // not move the key does not merely mislay the fact, the next save
    // DELETES it. The feature would work exactly once per asset.
    final s = session();
    final was = makeFile('참고영상.mp4', 7);
    s.importMediaFiles([was], copyIntoProject: false);
    fingerprint(s, was);
    final recorded = s.recordedMediaIdentity(was)!;

    final now = makeFile('옮긴영상.mp4', 7);
    s.relinkMediaAsset(was, now);
    await s.saveProjectToFile(projectPath);
    s.dispose();

    final reopened = session();
    await reopened.openProjectFromFile(projectPath);
    expect(
      reopened.recordedMediaIdentity(now),
      recorded,
      reason: 'the fingerprint has to follow the asset it describes',
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
    fingerprint(s, movie);
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
