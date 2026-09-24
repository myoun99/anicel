import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import '../../helpers/os_file_modes.dart';
import '../../helpers/temp_dir.dart';

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

  tearDown(() => deleteTempQuietly(root));

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

  test(
    'an import copies the bytes, so losing the original costs nothing',
    () async {
      final path = sourceFile('take.wav');
      final original = File(path).readAsBytesSync();

      final staged = await store.stage(path);
      expect(staged, isNotNull);

      // 🚨THE WHOLE POINT: the original goes away and the project still has
      // what it was promised.
      File(path).deleteSync();

      expect(mediaAppFileSource(staged!.path).readSync(), original);
    },
  );

  test(
    'and a change to the original after the import does not reach it',
    () async {
      final path = sourceFile('take.wav');
      final original = File(path).readAsBytesSync();
      final staged = (await store.stage(path))!;

      File(path).writeAsBytesSync(Uint8List(16));

      expect(mediaAppFileSource(staged.path).readSync(), original);
    },
  );

  test(
    'staging twice keeps the FIRST bytes — the ones that were promised',
    () async {
      final path = sourceFile('take.wav');
      final original = File(path).readAsBytesSync();
      await store.stage(path);
      File(path).writeAsBytesSync(Uint8List(32));

      final again = (await store.stage(path))!;
      expect(
        mediaAppFileSource(again.path).readSync(),
        original,
        reason:
            'the file on disk moved on; the staged copy is what「품기」meant '
            'at the moment it was pressed',
      );
    },
  );

  test(
    'compressible media is framed, and the entry says so by its name',
    () async {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      final staged = (await store.stage(sourceFile('take.wav')))!;
      expect(staged.framed, isTrue);
      expect(mediaEntryIsFramed(staged.path), isTrue);
      expect(
        staged.storedLength,
        lessThan(200 * 1024),
        reason: 'and it actually got smaller',
      );
    },
  );

  test(
    'media that will not shrink is staged as the FILE, byte for byte',
    () async {
      if (!engineHere()) {
        markTestSkipped('no engine on this run');
        return;
      }
      // ⚠️Named `.png` deliberately: measured, PNG is the one common format
      // zstd cannot improve (0.0%), while JPEG (15–21%), PDF (up to 40%)
      // and MP4 (6.7%) all shrink and are framed. The bytes are noise
      // because that is what「will not shrink」actually looks like.
      final path = noiseFile('flat.png');
      final staged = (await store.stage(path))!;
      expect(staged.framed, isFalse);
      expect(
        File(staged.path).readAsBytesSync(),
        File(path).readAsBytesSync(),
        reason:
            '⛔nothing in front of it: a plain seek and an unzip tool both '
            'depend on a stored entry being the file',
      );
    },
  );

  group('⛔the copy does not outlive its purpose', () {
    test('the save retires it', () async {
      final path = sourceFile('take.wav');
      await store.stage(path);
      expect(store.find(path), isNotNull);

      store.retire(path);

      expect(store.find(path), isNull);
      expect(store.list(), isEmpty, reason: 'no file left behind');
    });

    test('retiring something never staged is not an error', () async {
      store.retire('${root.path}/never-imported.wav');
      expect(store.list(), isEmpty);
    });

    test('🚨a copy a reader holds open outlives the save that absorbs it, '
        'and goes when the last reader lets go', () async {
      final path = sourceFile('conte.pdf');
      await store.stage(path);
      final first = store.hold(path);
      final second = store.hold(path);

      store.retire(path);
      expect(
        store.list(),
        hasLength(1),
        reason: 'Windows refuses to delete a file a reader holds open',
      );
      first();
      expect(store.list(), hasLength(1), reason: 'one reader is left');
      second();

      expect(store.find(path), isNull);
      expect(store.list(), isEmpty, reason: 'no file left behind');
    });

    test('⛔a copy whose retirement waits on its reader is NOT the staged '
        'copy — a save absorbed it', () async {
      final path = sourceFile('conte.pdf');
      await store.stage(path);
      final letGo = store.hold(path);

      store.retire(path);

      expect(store.find(path), isNull, reason: 'only its reader is finishing');
      expect(store.list(), hasLength(1), reason: 'on disk, for that reader');
      letGo();
      expect(store.list(), isEmpty);
    });

    test('🚨carried AGAIN while the old copy waits: the new copy is the one '
        'kept when the old reader lets go', () async {
      final path = sourceFile('conte.pdf');
      await store.stage(path);
      final letGo = store.hold(path);
      store.retire(path);
      final edited = Uint8List.fromList(
        List<int>.generate(64 * 1024, (i) => (i * 7) & 0xFF),
      );
      File(path).writeAsBytesSync(edited);

      await store.stage(path);
      letGo();

      final kept = store.find(path);
      expect(kept, isNotNull, reason: 'letting go takes its OWN copy only');
      expect(mediaAppFileSource(kept!.path).readSync(), edited);
    });

    test('🚨a take written again under the name whose old copy waits: the '
        'new take is the one kept when the old reader lets go', () async {
      // A take has no original — the staged file is the only copy, so
      // losing it here is losing the performance.
      final path = '${root.path}/S1_T01.wav'.replaceAll(r'\', '/');
      final first = Uint8List.fromList(
        List<int>.generate(64 * 1024, (i) => (i * 3) & 0xFF),
      );
      final second = Uint8List.fromList(
        List<int>.generate(64 * 1024, (i) => (i * 7 + 1) & 0xFF),
      );
      await store.stageCarriedBytesInMemory(path, first);
      final letGo = store.hold(path);
      store.retire(path);

      await store.stageCarriedBytesInMemory(path, second);
      letGo();

      final kept = store.find(path);
      expect(kept, isNotNull, reason: 'letting go takes its OWN copy only');
      expect(mediaAppFileSource(kept!.path).readSync(), second);
    });

    test('a copy held under the OS spelling of its path is the copy the save '
        'retires', () async {
      final path = sourceFile('take.wav');
      await store.stage(path);
      final letGo = store.hold(path.replaceAll('/', r'\'));

      store.retire(path);

      expect(store.list(), hasLength(1), reason: 'held — one key, not two');
      letGo();
      expect(store.list(), isEmpty);
    });

    test('a copy the OS will not let go of stays for the run\'s room — and '
        'letting go does not throw into the reader\'s close', () async {
      final path = sourceFile('conte.pdf');
      final staged = (await store.stage(path))!;
      final letGo = store.hold(path);
      store.retire(path);
      if (!setUndeletable(staged.path, on: true)) {
        markTestSkipped('this user can delete anything (root)');
        return;
      }
      addTearDown(() => setUndeletable(staged.path, on: false));

      expect(letGo, returnsNormally);
      expect(File(staged.path).existsSync(), isTrue);
    });

    test('a hold let go of with no retirement pending takes nothing', () async {
      final path = sourceFile('conte.pdf');
      await store.stage(path);

      store.hold(path)();

      expect(store.find(path), isNotNull, reason: 'the save has not come');
      store.retire(path);
      expect(store.find(path), isNull, reason: 'held by no one, it goes');
    });

    // 🪦**THE SWEEP TESTS MOVED WITH THE SWEEP, AND THEN TWO OF THEM WERE
    // REVERSED.** They pinned `sweepAbandoned` — 30 days, nothing taken
    // while everything is recent, the window shared with recovery
    // snapshots. The lifetime is the RUN'S ROOM now, and 유저 확정
    // 2026-09-10 dropped both the month and the recovery it was waiting
    // for: a room whose run has ended goes at the next launch, staged
    // media and all. What survives of the three is the claim that a LIVE
    // room is never touched. All of it is pinned in
    // `a_run_that_ended_leaves_its_room_test`, where the thing that
    // answers it lives. ⛔A claim with no test is what this note exists to
    // prevent someone concluding.

    test('a half-written file is never mistaken for a staged one', () async {
      final path = sourceFile('take.wav');
      final staged = (await store.stage(path))!;
      // The writer lands on a neighbour and renames, so nothing with the
      // real name can be partial. A `.part` left by a crash is ignored.
      File('${staged.path}.part').writeAsBytesSync(Uint8List(4));
      expect(store.list(), hasLength(1));
    });
  });

  test('a missing source stages nothing rather than an empty file', () async {
    expect(await store.stage('${root.path}/not-here.wav'), isNull);
    expect(store.list(), isEmpty);
  });

  test('two different sources with the same basename do not collide', () async {
    Directory('${root.path}/a').createSync();
    Directory('${root.path}/b').createSync();
    final first = sourceFile('a/take.wav');
    final second = sourceFile('b/take.wav', length: 100 * 1024);

    await store.stage(first);
    await store.stage(second);

    expect(store.list(), hasLength(2));
    expect(store.find(first), isNotNull);
    expect(store.find(second), isNotNull);
    expect(store.find(first)!.path, isNot(store.find(second)!.path));
  });

  group('a relink takes the staged bytes with it', () {
    test('🚨the derived name follows the pool path', () async {
      final from = sourceFile('take.wav');
      final original = File(from).readAsBytesSync();
      final staged = (await store.stage(from))!;
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
      expect(mediaAppFileSource(moved.path).readSync(), original);
      expect(store.list(), hasLength(1), reason: 'moved, not copied');
    });

    test('renaming something never staged does nothing', () async {
      store.rename('${root.path}/never.wav', '${root.path}/other.wav');
      expect(store.list(), isEmpty);
    });

    test('a destination that already holds bytes is replaced', () async {
      // The caller has just pointed the pool path at a different file, so
      // whatever was staged under it belongs to the asset being replaced.
      final from = sourceFile('take.wav');
      final to = sourceFile('other.wav', length: 120 * 1024);
      await store.stage(from);
      await store.stage(to);
      expect(store.list(), hasLength(2));

      store.rename(from, to);

      expect(store.list(), hasLength(1));
      expect(store.find(to), isNotNull);
      expect(store.find(from), isNull);
    });
  });

  /// 🚨★★★**THE ROAD PRODUCTION ACTUALLY TAKES.**
  ///
  /// `flutter_test_config.dart` turns [MediaStagingStore.debugStageInline]
  /// ON for the whole suite, because a `testWidgets` clock is fake and
  /// awaiting a real isolate there is a hang rather than a wait. That is
  /// the right trade for the widget tests — and it would leave the shipping
  /// path with **no coverage at all** if nothing turned it back off.
  ///
  /// This is that something. It is a plain `test`, so the clock is real and
  /// the isolate genuinely runs.
  group('across a real isolate', () {
    setUp(() => MediaStagingStore.debugStageInline = false);
    tearDown(() => MediaStagingStore.debugStageInline = true);

    test('🚨the bytes land, and they are the source\'s own', () async {
      final path = sourceFile('take.wav');
      final original = File(path).readAsBytesSync();

      final staged = (await store.stage(path))!;

      expect(File(staged.path).existsSync(), isTrue);
      // ⛔Through the un-framing source, not the file: the file holds the
      // STORED bytes on purpose, so a save can stream them into the archive
      // without a decode-and-re-encode.
      expect(
        mediaAppFileSource(staged.path).readSync(),
        original,
        reason: 'the isolate wrote the same file the inline road does',
      );
    });

    test('a batch crosses ONCE and every file comes back', () async {
      final paths = [
        sourceFile('a.wav'),
        sourceFile('b.wav'),
        sourceFile('c.wav'),
      ];

      final staged = await store.stageCarriedBytes(paths);

      expect(staged, hasLength(3));
      expect(store.list(), hasLength(3));
      for (final one in staged) {
        expect(File(one.path).existsSync(), isTrue);
      }
    });
  });
}
