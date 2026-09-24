import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/media_pool.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**A FILE REGISTERED WITH KEEP IS HELD FROM THAT MOMENT — THE
/// IMPORT WINDOW'S POOL AS MUCH AS ANY DOOR.**
///
/// 유저 2026-08-30: 「품은 순간 데이터를 가지고있고 불변이었으면좋겠어서」.
/// The pool's `addMediaAssets` kept that promise and its test said so
/// (`carried_media_survives_the_original_test`) — but the import window and
/// the viewer's register button go through `importMediaFiles`, which
/// recorded the asset carried and held nothing, from the day staging landed
/// until 2026-09-24. Nothing measured it: every test of the promise called
/// the other verb.
void main() {
  late Directory root;
  late EditorSessionManager session;

  /// The pool under test, held by its own type — see
  /// `carried_media_survives_the_original_test`.
  late MediaPool pool;

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel-registered-carry');
    session = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${root.path}/Staged',
      ),
    );
    pool = session.mediaPool;
  });

  tearDown(() {
    session.dispose();
    deleteTempQuietly(root);
  });

  String aFile(String name) {
    final bytes = Uint8List(64 * 1024);
    for (var i = 0; i < bytes.length; i += 1) {
      bytes[i] = (i ~/ 7 + (i % 5)) & 0xFF;
    }
    final path = '${root.path}/$name'.replaceAll(r'\', '/');
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  List<int> heldBytesOf(String path) {
    final staged = stagedCopyIn(session, path)!;
    final source = MediaAppFileBytes(path: staged.path, framed: staged.framed);
    return staged.framed
        ? MediaFramedBytes(source).readSync()
        : source.readSync();
  }

  test('🎯the original can be deleted right after the window registers it '
      'kept inside, and the bytes are still there', () async {
    final path = aFile('board.png');
    final original = File(path).readAsBytesSync();

    await pool.importMediaFiles([path], copyIntoProject: true);
    File(path).deleteSync();

    expect(heldBytesOf(path), original);
    expect(pool.mediaAssets.single.carried, isTrue);
  });

  test('and editing the original afterwards does not change what the '
      'project holds', () async {
    final path = aFile('take.wav');
    final original = File(path).readAsBytesSync();

    await pool.importMediaFiles([path], copyIntoProject: true);
    File(path).writeAsBytesSync(Uint8List(16));

    expect(heldBytesOf(path), original);
  });

  test('⛔a REFERENCED registration holds nothing — a second copy nobody '
      'asked for is the other failure', () async {
    final path = aFile('board.png');

    await pool.importMediaFiles([path], copyIntoProject: false);

    expect(session.mediaStagingStore.holdsAnyCopyOf(path), isFalse);
    expect(pool.mediaAssets.single.carried, isFalse);
  });

  test('🚨the pool records nothing before the bytes are held — what lands '
      'meanwhile is kept, not written over', () async {
    final carried = aFile('board.png');
    final other = aFile('other.png');

    final registering = pool.importMediaFiles(
      [carried],
      copyIntoProject: true,
    );
    // A second registration that lands while the first is holding bytes.
    await pool.importMediaFiles([other], copyIntoProject: false);
    await registering;

    expect(
      [for (final asset in pool.mediaAssets) asset.path],
      unorderedEquals([carried, other]),
    );
  });
}
