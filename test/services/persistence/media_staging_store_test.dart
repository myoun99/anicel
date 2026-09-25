import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/path_names.dart';
import 'package:anicel/src/models/media_asset.dart'
    show MediaCarry, mediaNameParts, mintMediaCarry;
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

  /// A carry of [path] — the first one, unless [token] says which.
  MediaCarry carry(String path, [String token = 'c1']) =>
      (poolPath: path, token: token);

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

      final staged = await store.stage(carry(path));
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
      final staged = (await store.stage(carry(path)))!;

      File(path).writeAsBytesSync(Uint8List(16));

      expect(mediaAppFileSource(staged.path).readSync(), original);
    },
  );

  test(
    'staging twice keeps the FIRST bytes — the ones that were promised',
    () async {
      final path = sourceFile('take.wav');
      final original = File(path).readAsBytesSync();
      await store.stage(carry(path));
      File(path).writeAsBytesSync(Uint8List(32));

      final again = (await store.stage(carry(path)))!;
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
      final staged = (await store.stage(carry(sourceFile('take.wav'))))!;
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
      final staged = (await store.stage(carry(path)))!;
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
      await store.stage(carry(path));
      expect(store.find(carry(path)), isNotNull);

      store.retire(carry(path));

      expect(store.find(carry(path)), isNull);
      expect(store.list(), isEmpty, reason: 'no file left behind');
    });

    test('retiring something never staged is not an error', () async {
      store.retire(carry('${root.path}/never-imported.wav'));
      expect(store.list(), isEmpty);
    });

    test('🚨a copy a reader holds open outlives the save that absorbs it, '
        'and goes when the last reader lets go', () async {
      final path = sourceFile('conte.pdf');
      await store.stage(carry(path));
      final first = store.hold(carry(path));
      final second = store.hold(carry(path));

      store.retire(carry(path));
      expect(
        store.list(),
        hasLength(1),
        reason: 'Windows refuses to delete a file a reader holds open',
      );
      first();
      expect(store.list(), hasLength(1), reason: 'one reader is left');
      second();

      expect(store.find(carry(path)), isNull);
      expect(store.list(), isEmpty, reason: 'no file left behind');
    });

    test('⛔a copy whose retirement waits on its reader is NOT the staged '
        'copy — a save absorbed it', () async {
      final path = sourceFile('conte.pdf');
      await store.stage(carry(path));
      final letGo = store.hold(carry(path));

      store.retire(carry(path));

      expect(
        store.find(carry(path)),
        isNull,
        reason: 'only its reader is finishing',
      );
      expect(store.list(), hasLength(1), reason: 'on disk, for that reader');
      letGo();
      expect(store.list(), isEmpty);
    });

    test('🚨carried AGAIN while the old copy waits: the new carry has a copy '
        'of its own, untouched when the old reader lets go', () async {
      final path = sourceFile('conte.pdf');
      final original = File(path).readAsBytesSync();
      await store.stage(carry(path));
      final letGo = store.hold(carry(path));
      store.retire(carry(path));
      final edited = Uint8List.fromList(
        List<int>.generate(64 * 1024, (i) => (i * 7) & 0xFF),
      );
      File(path).writeAsBytesSync(edited);

      await store.stage(carry(path, 'c2'));
      expect(
        store.list(),
        hasLength(2),
        reason: 'the old copy is still its reader\'s; the new one is new',
      );
      letGo();

      final kept = store.find(carry(path, 'c2'));
      expect(kept, isNotNull, reason: 'letting go takes its OWN copy only');
      expect(mediaAppFileSource(kept!.path).readSync(), edited);
      expect(store.find(carry(path)), isNull);
      expect(store.list(), hasLength(1));
      expect(original, isNot(edited), reason: 'the premise: they differ');
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
      await store.stageCarriedBytesInMemory(carry(path), first);
      final letGo = store.hold(carry(path));
      store.retire(carry(path));

      await store.stageCarriedBytesInMemory(carry(path, 'c2'), second);
      letGo();

      final kept = store.find(carry(path, 'c2'));
      expect(kept, isNotNull, reason: 'letting go takes its OWN copy only');
      expect(mediaAppFileSource(kept!.path).readSync(), second);
    });

    test('⛔a carry\'s bytes are taken ONCE: staging it again while its copy '
        'waits on a reader writes nothing over that copy', () async {
      final path = sourceFile('conte.pdf');
      final original = File(path).readAsBytesSync();
      final staged = (await store.stage(carry(path)))!;
      final letGo = store.hold(carry(path));
      store.retire(carry(path));
      File(path).writeAsBytesSync(Uint8List(64));

      expect(await store.stage(carry(path)), isNull);
      expect(
        await store.stageCarriedBytesInMemory(carry(path), Uint8List(8)),
        isNull,
      );

      expect(
        mediaAppFileSource(staged.path).readSync(),
        original,
        reason: 'the reader still reads what the carry was',
      );
      letGo();
      expect(store.list(), isEmpty, reason: 'and it goes when let go');
    });

    test('two carries of one path are two copies, each found by its own '
        'name', () async {
      final path = sourceFile('take.wav');
      final first = File(path).readAsBytesSync();
      await store.stage(carry(path));
      File(path).writeAsBytesSync(Uint8List.fromList(List.filled(4096, 7)));

      await store.stage(carry(path, 'c2'));

      expect(mediaAppFileSource(store.find(carry(path))!.path).readSync(), [
        ...first,
      ]);
      expect(
        mediaAppFileSource(store.find(carry(path, 'c2'))!.path).readSync(),
        List.filled(4096, 7),
      );
      store.retire(carry(path, 'c2'));
      expect(store.find(carry(path)), isNotNull, reason: 'retires its own');
    });

    test('any carry of a path is a copy of it, live or waiting on its '
        'reader — and no other path\'s is', () async {
      final path = sourceFile('take.wav');
      expect(store.holdsAnyCopyOf(path), isFalse);
      await store.stage(carry(path, 'c7'));
      expect(store.holdsAnyCopyOf(path), isTrue);
      expect(store.holdsAnyCopyOf(sourceFile('other.wav')), isFalse);
      expect(store.holdsAnyCopyOf('${root.path}/ake.wav'), isFalse);
      expect(
        store.holdsAnyCopyOf('${root.path}/elsewhere/take.wav'),
        isFalse,
        reason: 'the same file name in another folder is another path',
      );

      final letGo = store.hold(carry(path, 'c7'));
      store.retire(carry(path, 'c7'));
      expect(store.holdsAnyCopyOf(path), isTrue, reason: 'still on disk');
      letGo();
      expect(store.holdsAnyCopyOf(path), isFalse);
    });

    test('a copy that shares only the path\'s hash is not a copy of the path '
        '— the file\'s name says whose it is', () async {
      final path = sourceFile('take.wav');
      final (:hash, safe: _) = mediaNameParts(path);
      Directory('${root.path}/Staged').createSync(recursive: true);
      // What only a collision could put there — the name's back end is the
      // only witness left, and it had none (audit 09-25).
      File('${root.path}/Staged/$hash-c9-other.wav').writeAsBytesSync([1]);

      expect(store.holdsAnyCopyOf(path), isFalse);
    });

    test('a copy is staged under its carry\'s name — the path alone gives '
        'the name of a carry from before names were minted', () async {
      final path = sourceFile('take.wav');
      final minted = mintMediaCarry(path);

      final legacy = (await store.stage(carry(path, '')))!;
      final named = (await store.stage(carry(path, minted)))!;

      expect(
        fileNameOfPath(legacy.path),
        matches(RegExp(r'^[0-9a-f]{8}-take\.wav(\.z)?$')),
      );
      expect(fileNameOfPath(named.path), startsWith(minted));
    });

    test('a copy held under the OS spelling of its path is the copy the save '
        'retires', () async {
      final path = sourceFile('take.wav');
      await store.stage(carry(path));
      final letGo = store.hold(carry(path.replaceAll('/', r'\')));

      store.retire(carry(path));

      expect(store.list(), hasLength(1), reason: 'held — one key, not two');
      letGo();
      expect(store.list(), isEmpty);
    });

    test('a copy the OS will not let go of stays for the run\'s room — and '
        'letting go does not throw into the reader\'s close', () async {
      final path = sourceFile('conte.pdf');
      final staged = (await store.stage(carry(path)))!;
      final letGo = store.hold(carry(path));
      store.retire(carry(path));
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
      await store.stage(carry(path));

      store.hold(carry(path))();

      expect(
        store.find(carry(path)),
        isNotNull,
        reason: 'the save has not come',
      );
      store.retire(carry(path));
      expect(
        store.find(carry(path)),
        isNull,
        reason: 'held by no one, it goes',
      );
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
      final staged = (await store.stage(carry(path)))!;
      // The writer lands on a neighbour and renames, so nothing with the
      // real name can be partial. A `.part` left by a crash is ignored.
      File('${staged.path}.part').writeAsBytesSync(Uint8List(4));
      expect(store.list(), hasLength(1));
    });
  });

  test('a missing source stages nothing rather than an empty file', () async {
    expect(await store.stage(carry('${root.path}/not-here.wav')), isNull);
    expect(store.list(), isEmpty);
  });

  test('two different sources with the same basename do not collide', () async {
    Directory('${root.path}/a').createSync();
    Directory('${root.path}/b').createSync();
    final first = sourceFile('a/take.wav');
    final second = sourceFile('b/take.wav', length: 100 * 1024);

    await store.stage(carry(first));
    await store.stage(carry(second));

    expect(store.list(), hasLength(2));
    expect(store.find(carry(first)), isNotNull);
    expect(store.find(carry(second)), isNotNull);
    expect(
      store.find(carry(first))!.path,
      isNot(store.find(carry(second))!.path),
    );
  });

  /// 🚨★★★**WHAT A SAVE LEAVES BEHIND, THE ROOM KEEPS** (유저 2026-09-25 「이번
  /// 실행의 앱 룸으로 옮겨 둔다」): the entry is copied out of the project
  /// file under the name it wears there — and found as its carry's copy.
  group('what a save leaves behind, the room keeps', () {
    /// A stand-in project file: [entry] between bytes that are not it.
    ({String path, int offset}) fileHolding(Uint8List entry) {
      final path = '${root.path}/scene.anicel'.replaceAll(r'\', '/');
      File(path).writeAsBytesSync([
        ...List<int>.filled(333, 7),
        ...entry,
        ...List<int>.filled(99, 9),
      ]);
      return (path: path, offset: 333);
    }

    /// Everything in the room's folder, `.part` neighbours included.
    List<String> inTheRoom() => [
      for (final entity in Directory('${root.path}/Staged').listSync())
        fileNameOfPath(entity.path),
    ];

    test('🚨the entry lands under its carry\'s name, and is that carry\'s '
        'copy', () async {
      final source = sourceFile('take.wav');
      final bytes = File(source).readAsBytesSync();
      final minted = mintMediaCarry(source);
      final (:path, :offset) = fileHolding(bytes);

      await store.keepLeftBehind(path, [
        (name: minted, offset: offset, length: bytes.length),
      ]);

      final kept = store.find(carry(source, minted));
      expect(kept, isNotNull, reason: 'the undo asks the room by the carry');
      expect(
        File(kept!.path).readAsBytesSync(),
        bytes,
        reason: 'the entry\'s bytes, not the file around them',
      );
      expect(kept.framed, isFalse);
    });

    test('a framed entry stays framed — the room keeps what the file '
        'stored', () async {
      final source = sourceFile('take.wav');
      final bytes = File(source).readAsBytesSync();
      final minted = mintMediaCarry(source);
      final (:path, :offset) = fileHolding(bytes);

      await store.keepLeftBehind(path, [
        (
          name: '$minted$mediaFramedEntrySuffix',
          offset: offset,
          length: bytes.length,
        ),
      ]);

      expect(store.find(carry(source, minted))?.framed, isTrue);
    });

    test('⛔a copy that ended short is not kept — a short file never wears '
        'the name', () async {
      final source = sourceFile('take.wav');
      final bytes = File(source).readAsBytesSync();
      final minted = mintMediaCarry(source);
      final (:path, :offset) = fileHolding(bytes);

      await store.keepLeftBehind(path, [
        (name: minted, offset: offset, length: bytes.length + 4096),
      ]);

      expect(store.find(carry(source, minted)), isNull);
      expect(inTheRoom(), isEmpty, reason: 'and no neighbour is left either');
    });

    test('🚨a copy waiting on its reader to retire is kept — the reader '
        'letting go does not take it', () async {
      final source = sourceFile('conte.pdf');
      final minted = mintMediaCarry(source);
      final c = carry(source, minted);
      final staged = (await store.stage(c))!;
      final stored = File(staged.path).readAsBytesSync();
      final letGo = store.hold(c);
      store.retire(c);
      expect(store.find(c), isNull, reason: 'the premise: it is retiring');
      final (:path, :offset) = fileHolding(stored);

      await store.keepLeftBehind(path, [
        (
          name: fileNameOfPath(staged.path),
          offset: offset,
          length: stored.length,
        ),
      ]);
      letGo();

      expect(
        store.find(c)?.path,
        staged.path,
        reason: 'those are the bytes the save leaves behind',
      );
      expect(inTheRoom(), hasLength(1), reason: 'kept, not copied again');
    });

    test('a copy already in the room is not made again — a carried movie is '
        'gigabytes', () async {
      final source = sourceFile('take.wav');
      final bytes = File(source).readAsBytesSync();
      final minted = mintMediaCarry(source);
      final (:path, :offset) = fileHolding(bytes);
      final entry = (name: minted, offset: offset, length: bytes.length);
      await store.keepLeftBehind(path, [entry]);
      final heard = <double>[];

      await store.keepLeftBehind(path, [entry], onProgress: heard.add);

      expect(heard, isEmpty, reason: 'nothing was copied the second time');
      expect(store.find(carry(source, minted)), isNotNull);
    });

    test('its bar runs from nothing to all of it, and never back', () async {
      final first = sourceFile('a.wav');
      final second = sourceFile('b.wav', length: 3 * 1024 * 1024);
      final one = File(first).readAsBytesSync();
      final two = File(second).readAsBytesSync();
      final (:path, :offset) = fileHolding(
        Uint8List.fromList([...one, ...two]),
      );
      final heard = <double>[];

      await store.keepLeftBehind(
        path,
        [
          (name: mintMediaCarry(first), offset: offset, length: one.length),
          (
            name: mintMediaCarry(second),
            offset: offset + one.length,
            length: two.length,
          ),
        ],
        onProgress: heard.add,
      );

      expect(heard.length, greaterThan(2), reason: 'a block at a time');
      for (var i = 1; i < heard.length; i += 1) {
        expect(heard[i], greaterThanOrEqualTo(heard[i - 1]));
      }
      expect(heard.last, 1);
    });
  });

  group('a relink moves the asset, not its bytes', () {
    test('🚨a carry minted at one path is found at the next — one copy, '
        'answering both', () async {
      final from = sourceFile('take.wav');
      final original = File(from).readAsBytesSync();
      final minted = mintMediaCarry(from);
      final staged = (await store.stage(carry(from, minted)))!;
      final to = '${root.path}/moved.wav'.replaceAll(r'\', '/');

      final moved = store.find(carry(to, minted));

      expect(
        moved?.path,
        staged.path,
        reason:
            '🪦the name followed the path, so a relink RENAMED the copy — and '
            'an undo of it looked for the old name and found nothing',
      );
      expect(mediaAppFileSource(moved!.path).readSync(), original);
      expect(store.find(carry(from, minted))?.path, staged.path);
      expect(store.list(), hasLength(1));
    });

    test('a carry from before names were minted is found by the path it is '
        'at', () async {
      final from = sourceFile('take.wav');
      await store.stage(carry(from, 'c1'));
      final to = '${root.path}/moved.wav'.replaceAll(r'\', '/');

      expect(store.find(carry(to, 'c1')), isNull);
      expect(store.find(carry(from, 'c1')), isNotNull);
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

      final staged = (await store.stage(carry(path)))!;

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

      final staged = await store.stageCarriedBytes([
        for (final path in paths) carry(path),
      ]);

      expect(staged, hasLength(3));
      expect(store.list(), hasLength(3));
      for (final one in staged) {
        expect(File(one.path).existsSync(), isTrue);
      }
    });
  });
}
