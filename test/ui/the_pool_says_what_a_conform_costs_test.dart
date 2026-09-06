import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the media pool's conform column reads, and the two laws under it:
/// the CACHE file answers first, and the map the panel draws is MEMOISED,
/// so a conform built after the panel last asked stays invisible until
/// something says the answer moved.
///
/// 🚨Neither had an observer before this file. The panel takes both
/// numbers as widget arguments, so the session-side query was reachable
/// only through a running app — deleting its body left every suite green,
/// which is exactly the shape [[adversarial-verify-is-not-optional]]
/// calls evidence of nothing.
void main() {
  late Directory directory;
  late EditorSessionManager session;
  late String sourcePath;
  final planted = <String>[];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('qa_conform_size_');
    sourcePath = '${directory.path.replaceAll('\\', '/')}/take.wav';
    File(sourcePath).writeAsBytesSync(List<int>.filled(2048, 7));
    session = EditorSessionManager(initialProject: createDefaultProject());
  });

  tearDown(() {
    session.dispose();
    for (final path in planted) {
      try {
        File(path).deleteSync();
      } on Object {
        // Already gone: one case deletes it on purpose.
      }
    }
    planted.clear();
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // Windows handles.
    }
  });

  /// A conform of [bytes] bytes where the cache would put one, under the
  /// PLAIN spelling — a build with no engine writes that one.
  String plantConform(int bytes) {
    final base = session.projectFile.conformPathFor(sourcePath)!;
    final onDisk = mediaFramedOrPlainPaths(base).last;
    final file = File(onDisk)..parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(bytes, 3));
    planted.add(onDisk);
    return onDisk;
  }

  test('a conform on disk answers with what it takes, and no conform '
      'answers nothing', () {
    expect(
      session.projectFile.conformStoredBytesFor(sourcePath),
      isNull,
      reason: 'a sound nobody has conformed costs no disk yet',
    );
    final onDisk = plantConform(1234);
    expect(session.projectFile.conformStoredBytesFor(sourcePath), 1234);
    File(onDisk).deleteSync();
    expect(session.projectFile.conformStoredBytesFor(sourcePath), isNull);
  });

  test('a carried asset reports what its STAGED copy takes, which is the '
      'size the disk actually lost', () async {
    await session.addMediaAssets([sourcePath], carried: true);
    final staged = session.mediaStagingStore.find(sourcePath)!;
    expect(
      session.projectFile.mediaStoredBytesFor(sourcePath),
      staged.storedLength,
      reason:
          '유저 2026-08-30: 「아무튼 실제크기」 — not the length the file had '
          'when it was registered',
    );
    expect(session.projectFile.mediaStoredBytes, {
      sourcePath: staged.storedLength,
    });
  });

  test('the map the panel draws is memoised, and only an invalidation '
      'lets a freshly built conform into it', () async {
    await session.addMediaAssets([sourcePath]);
    expect(session.projectFile.conformStoredBytes, isEmpty);
    plantConform(4096);
    expect(
      session.projectFile.conformStoredBytes,
      isEmpty,
      reason:
          'a row must not stat the disk to draw itself — the map is held '
          'until something says it moved',
    );
    session.projectFile.invalidateConformStoredBytes();
    expect(session.projectFile.conformStoredBytes, {sourcePath: 4096});
  });
}
