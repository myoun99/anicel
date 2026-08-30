import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';

/// 🚨★★★**품기 HOLDS THE BYTES FROM THE MOMENT IT IS PRESSED.**
///
/// Carrying used to be a promise kept only at save time: the flag said
/// 「this travels with the project」while the bytes were still the ones on
/// disk, so editing or deleting the original before the first save changed
/// or emptied what got saved. 유저 2026-08-30: 「품은 순간 데이터를
/// 가지고있고 **불변**이었으면좋겠어서」.
///
/// ⛔And the copy must not outlive its purpose — 유저 08-27: 「사본 남으면
/// **진짜 용서안할게**」. That is the other half of every test here.
void main() {
  late Directory root;
  late MediaStagingStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel_staging_test');
    store = MediaStagingStore(directoryPath: '${root.path}/Staged');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  /// A source file with compressible content.
  String sourceFile(String name, {int length = 200 * 1024}) {
    final random = Random(5);
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i += 1) {
      bytes[i] = (i ~/ 64 + random.nextInt(3)) & 0xFF;
    }
    final path = '${root.path}/$name'.replaceAll(r'\', '/');
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  String noiseFile(String name, {int length = 64 * 1024}) {
    final random = Random(9);
    final path = '${root.path}/$name'.replaceAll(r'\', '/');
    File(path).writeAsBytesSync(
      Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)),
      ),
    );
    return path;
  }

  bool engineHere() {
    final compressor = QaCelCompressor.instance;
    return compressor != null && compressor.isSupported;
  }

  test('an import copies the bytes, so losing the original costs nothing', () {
    final path = sourceFile('take.wav');
    final original = File(path).readAsBytesSync();

    final staged = store.stage(path);
    expect(staged, isNotNull);

    // 🚨THE WHOLE POINT: the original goes away and the project still has
    // what it was promised.
    File(path).deleteSync();

    final stored = staged!.readStoredSync();
    final back = staged.framed ? decompressMediaBlob(stored) : stored;
    expect(back, original);
  });

  test('and a change to the original after the import does not reach it', () {
    final path = sourceFile('take.wav');
    final original = File(path).readAsBytesSync();
    final staged = store.stage(path)!;

    File(path).writeAsBytesSync(Uint8List(16));

    final stored = staged.readStoredSync();
    expect(staged.framed ? decompressMediaBlob(stored) : stored, original);
  });

  test('staging twice keeps the FIRST bytes — the ones that were promised', () {
    final path = sourceFile('take.wav');
    final original = File(path).readAsBytesSync();
    store.stage(path);
    File(path).writeAsBytesSync(Uint8List(32));

    final again = store.stage(path)!;
    final stored = again.readStoredSync();
    expect(
      again.framed ? decompressMediaBlob(stored) : stored,
      original,
      reason:
          'the file on disk moved on; the staged copy is what「품기」meant '
          'at the moment it was pressed',
    );
  });

  test('compressible media is framed, and the entry says so by its name', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final staged = store.stage(sourceFile('take.wav'))!;
    expect(staged.framed, isTrue);
    expect(mediaEntryIsFramed(staged.path), isTrue);
    expect(
      staged.storedLength,
      lessThan(200 * 1024),
      reason: 'and it actually got smaller',
    );
  });

  test('media that will not shrink is staged as the FILE, byte for byte', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    // ⚠️Named `.png` deliberately: measured, PNG is the one common format
    // zstd cannot improve (0.0%), while JPEG (15–21%), PDF (up to 40%)
    // and MP4 (6.7%) all shrink and are framed. The bytes are noise
    // because that is what「will not shrink」actually looks like.
    final path = noiseFile('flat.png');
    final staged = store.stage(path)!;
    expect(staged.framed, isFalse);
    expect(
      staged.readStoredSync(),
      File(path).readAsBytesSync(),
      reason:
          '⛔nothing in front of it: a plain seek and an unzip tool both '
          'depend on a stored entry being the file',
    );
  });

  group('⛔the copy does not outlive its purpose', () {
    test('the save retires it', () {
      final path = sourceFile('take.wav');
      store.stage(path);
      expect(store.find(path), isNotNull);

      store.retire(path);

      expect(store.find(path), isNull);
      expect(store.list(), isEmpty, reason: 'no file left behind');
    });

    test('retiring something never staged is not an error', () {
      store.retire('${root.path}/never-imported.wav');
      expect(store.list(), isEmpty);
    });

    test('a launch sweep takes what is old enough to be unreachable', () {
      final old = sourceFile('abandoned.wav');
      final fresh = sourceFile('just-imported.wav');
      store.stage(old);
      store.stage(fresh);
      expect(store.list(), hasLength(2));
      // The old one was staged 40 days ago, as far as the clock is
      // concerned.
      File(
        store.find(old)!.path,
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 40)));

      final removed = store.sweepAbandoned();

      expect(removed, 1);
      expect(store.find(old), isNull);
      expect(
        store.find(fresh),
        isNotNull,
        reason: 'today\'s import is not abandoned',
      );
    });

    test('🚨and nothing at all when everything is recent — the sweep cannot '
        'be the thing that empties a live session', () {
      store.stage(sourceFile('a.wav'));
      store.stage(sourceFile('b.wav'));
      // ⛔The liveness-based sweep this replaced would have taken both:
      // at launch no project is open yet, so "claimed by an open project"
      // is empty and means nothing. Age is the question that can be asked
      // at the only moment it is safe to ask it.
      expect(store.sweepAbandoned(), 0);
      expect(store.list(), hasLength(2));
    });

    test('the window is the recovery snapshots\' 30 days, not a second '
        'number to keep in step', () {
      final path = sourceFile('take.wav');
      store.stage(path);
      File(
        store.find(path)!.path,
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 29)));
      expect(store.sweepAbandoned(), 0, reason: '29 days is inside it');
      File(
        store.find(path)!.path,
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 31)));
      expect(store.sweepAbandoned(), 1);
    });

    test('a half-written file is never mistaken for a staged one', () {
      final path = sourceFile('take.wav');
      final staged = store.stage(path)!;
      // The writer lands on a neighbour and renames, so nothing with the
      // real name can be partial. A `.part` left by a crash is ignored.
      File('${staged.path}.part').writeAsBytesSync(Uint8List(4));
      expect(store.list(), hasLength(1));
    });
  });

  test('a missing source stages nothing rather than an empty file', () {
    expect(store.stage('${root.path}/not-here.wav'), isNull);
    expect(store.list(), isEmpty);
  });

  test('two different sources with the same basename do not collide', () {
    Directory('${root.path}/a').createSync();
    Directory('${root.path}/b').createSync();
    final first = sourceFile('a/take.wav');
    final second = sourceFile('b/take.wav', length: 100 * 1024);

    store.stage(first);
    store.stage(second);

    expect(store.list(), hasLength(2));
    expect(store.find(first), isNotNull);
    expect(store.find(second), isNotNull);
    expect(store.find(first)!.path, isNot(store.find(second)!.path));
  });

  group('a relink takes the staged bytes with it', () {
    test('🚨the derived name follows the pool path', () {
      final from = sourceFile('take.wav');
      final original = File(from).readAsBytesSync();
      final staged = store.stage(from)!;
      final to = '${root.path}/moved.wav'.replaceAll(r'\', '/');

      store.rename(from, to);

      expect(
        store.find(from),
        isNull,
        reason: 'nothing is left under the old key',
      );
      final moved = store.find(to);
      expect(
        moved,
        isNotNull,
        reason:
            '⛔otherwise the asset looks unstaged — back to the promise '
            'being kept at save time — while its bytes wait under a name '
            'nothing points at',
      );
      expect(moved!.framed, staged.framed);
      final stored = moved.readStoredSync();
      expect(moved.framed ? decompressMediaBlob(stored) : stored, original);
      expect(store.list(), hasLength(1), reason: 'moved, not copied');
    });

    test('renaming something never staged does nothing', () {
      store.rename('${root.path}/never.wav', '${root.path}/other.wav');
      expect(store.list(), isEmpty);
    });

    test('a destination that already holds bytes is replaced', () {
      // The caller has just pointed the pool path at a different file, so
      // whatever was staged under it belongs to the asset being replaced.
      final from = sourceFile('take.wav');
      final to = sourceFile('other.wav', length: 120 * 1024);
      store.stage(from);
      store.stage(to);
      expect(store.list(), hasLength(2));

      store.rename(from, to);

      expect(store.list(), hasLength(1));
      expect(store.find(to), isNotNull);
      expect(store.find(from), isNull);
    });
  });
}
