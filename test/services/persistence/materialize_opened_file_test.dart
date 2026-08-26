import 'dart:io';

import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wait a cloud pick needs. Fetching a File Provider placeholder
/// takes time and the provider reports that by FAILING the read it has
/// just started (실측 08-27, iPhone + Google Drive: the first open said
/// 「잠시 후 다시 시도해 주세요」, the second opened the same file) — so the
/// materialiser asks again instead of handing the user a notice, which
/// is the app asking the user to be its retry loop.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('anicel-materialise');
  });

  tearDown(() {
    FolderPicker.debugCoordinatedReader = null;
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  /// A placeholder to every probe this code makes: an entry that is
  /// there and reads as nothing.
  String placeholder(String name) {
    final path = '${temp.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(const <int>[]);
    return path;
  }

  test('a pick that lands on the third ask opens from the staged copy', () async {
    final path = placeholder('late.tvpp');
    var asks = 0;
    FolderPicker.debugCoordinatedReader = ({
      required String sourcePath,
      required String destinationPath,
    }) async {
      asks += 1;
      if (asks < 3) {
        return false;
      }
      File(destinationPath).writeAsBytesSync(const [1, 2, 3]);
      return true;
    };

    final source = await FolderPicker.materializeOpenedFile(
      path,
      within: const Duration(seconds: 2),
      step: const Duration(milliseconds: 1),
    );

    expect(asks, 3, reason: 'the app retried; the user did not have to');
    expect(source.staged, isTrue);
    expect(File(source.path).readAsBytesSync(), const [1, 2, 3]);
    File(source.path).deleteSync();
  });

  test('a provider that finishes behind our back needs no staged copy', () async {
    final path = placeholder('arrives.anicel');
    var asks = 0;
    FolderPicker.debugCoordinatedReader = ({
      required String sourcePath,
      required String destinationPath,
    }) async {
      asks += 1;
      // What materialisation actually means: the bytes appear in the
      // PICK. The staged copy is only this app's fallback.
      File(sourcePath).writeAsBytesSync(const [7]);
      return false;
    };

    final source = await FolderPicker.materializeOpenedFile(
      path,
      within: const Duration(seconds: 2),
      step: const Duration(milliseconds: 1),
    );

    expect(asks, 1);
    expect(source.staged, isFalse);
    expect(source.path, path, reason: 'saves keep pointing at the real file');
  });

  test('a copy that is itself empty is not bytes — the wait goes on, and '
      'the failure comes only at the end', () async {
    final path = placeholder('never.tvpp');
    var asks = 0;
    FolderPicker.debugCoordinatedReader = ({
      required String sourcePath,
      required String destinationPath,
    }) async {
      asks += 1;
      // The provider "succeeds" and hands back nothing: a placeholder
      // copied is still a placeholder.
      File(destinationPath).writeAsBytesSync(const <int>[]);
      return true;
    };

    await expectLater(
      FolderPicker.materializeOpenedFile(
        path,
        within: const Duration(milliseconds: 20),
        step: const Duration(milliseconds: 5),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(asks, greaterThan(1), reason: 'one refusal is not an answer');
  });

  test('a pick with no entry gets the one ask, not the wait', () async {
    var asks = 0;
    FolderPicker.debugCoordinatedReader = ({
      required String sourcePath,
      required String destinationPath,
    }) async {
      asks += 1;
      return false;
    };

    await expectLater(
      FolderPicker.materializeOpenedFile(
        '${temp.path}${Platform.pathSeparator}gone.anicel',
        // Long enough that waiting would be obvious: nothing is on its
        // way to a path that does not exist.
        within: const Duration(seconds: 30),
        step: const Duration(seconds: 1),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(asks, 1);
  });
}
