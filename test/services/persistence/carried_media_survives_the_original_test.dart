import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/project_media_sources.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/media_pool.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import '../../helpers/staged_carry.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**품기 END TO END: THE ORIGINAL GOES AWAY AND THE PROJECT STILL
/// HAS IT.**
///
/// Every piece of this exists somewhere else — the staging store, the
/// block codec, the framed reader, the entry name. This is the one that
/// says they are actually joined up, in the order a person does them:
/// import, save, delete the original, read it back.
void main() {
  late Directory root;
  late EditorSessionManager session;

  /// The pool under test, held BY ITS OWN TYPE (2026-09-08).
  ///
  /// 🚨`tool/mutation_run.dart` picks a file's witnesses by which tests
  /// IMPORT it. A collaborator only ever spelled `session.mediaPool` is one
  /// the campaign reports UNNAMED and never runs a mutant against — every
  /// 품기 law below lives in that file and had no way of saying so.
  late MediaPool pool;

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel_carry_test');
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

  /// A file that compresses, so the framed path is the one under test.
  String compressibleFile(String name) {
    final bytes = Uint8List(300 * 1024);
    for (var i = 0; i < bytes.length; i += 1) {
      bytes[i] = (i ~/ 9 + (i % 4)) & 0xFF;
    }
    final path = '${root.path}/$name'.replaceAll(r'\', '/');
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  bool engineHere() {
    final compressor = QaCelCompressor.instance;
    return compressor != null && compressor.isSupported;
  }

  test('품기 stages the bytes at IMPORT, not at save', () async {
    final path = compressibleFile('take.wav');

    await pool.addMediaAssets([path], carried: true);

    expect(
      stagedCopyIn(session, path),
      isNotNull,
      reason:
          'the promise is kept the moment the button is pressed — waiting '
          'for a save is exactly the old behaviour',
    );
  });

  test('⛔a REFERENCED import stages nothing', () async {
    final path = compressibleFile('linked.wav');

    await pool.addMediaAssets([path]);

    expect(
      session.mediaStagingStore.holdsAnyCopyOf(path),
      isFalse,
      reason:
          'the user said keep the link; copying anyway would be a second '
          'copy nobody asked for',
    );
  });

  test('the staged bytes are what a save writes, and the entry name says '
      'whether they are framed', () async {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final path = compressibleFile('take.wav');
    await pool.addMediaAssets([path], carried: true);
    final staged = stagedCopyIn(session, path)!;
    expect(staged.framed, isTrue, reason: 'fixture: this content compresses');

    expect(
      anicelMediaEntryName(carryIn(session, path)!, framed: staged.framed),
      endsWith(mediaFramedEntrySuffix),
      reason: 'a reader must be able to tell without opening the entry',
    );
    expect(
      anicelMediaEntryName(carryIn(session, path)!, framed: false),
      isNot(endsWith(mediaFramedEntrySuffix)),
    );
  });

  test('🚨a FRAMED carry survives a save and a reopen with its original gone '
      '— the manifest names the entry the archive holds', () async {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final path = compressibleFile('take.wav');
    final original = File(path).readAsBytesSync();
    await pool.addMediaAssets([path], carried: true);
    expect(stagedCopyIn(session, path)!.framed, isTrue,
        reason: 'fixture: this content compresses');
    final projectPath = '${root.path}/scene.anicel';
    await session.projectDoor.saveProjectToFile(
      projectPath,
      asked: SaveAsked.byAPerson,
    );
    File(path).deleteSync();

    final reopened = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${root.path}/Reopened',
      ),
    );
    addTearDown(reopened.dispose);
    await reopened.projectDoor.openProjectFromFile(projectPath);

    // What every consumer reads through — the decoder over the framed entry.
    expect(reopened.projectFile.mediaByteSourceFor(path).readSync(), original);
    // And what the next save streams: found, so the save does not refuse.
    final sources = projectMediaSources(
      project: reopened.repository.requireProject(),
      projectFilePath: projectPath,
      mediaInFile: reopened.projectFile.mediaInFile,
    );
    expect(sources[carryIn(reopened, path)]!.storedIsFramed, isTrue);
  });

  test('🚨the original can be deleted right after the import and the bytes '
      'are still there', () async {
    final path = compressibleFile('take.wav');
    final original = File(path).readAsBytesSync();
    await pool.addMediaAssets([path], carried: true);

    // The whole reason carrying exists.
    File(path).deleteSync();

    final staged = stagedCopyIn(session, path)!;
    final source = MediaAppFileBytes(path: staged.path, framed: staged.framed);
    final bytes = staged.framed
        ? MediaFramedBytes(source).readSync()
        : source.readSync();
    expect(bytes, original);
  });

  test('and editing the original after the import does not change what the '
      'project holds', () async {
    final path = compressibleFile('take.wav');
    final original = File(path).readAsBytesSync();
    await pool.addMediaAssets([path], carried: true);

    File(path).writeAsBytesSync(Uint8List(64));

    final staged = stagedCopyIn(session, path)!;
    final source = MediaAppFileBytes(path: staged.path, framed: staged.framed);
    expect(
      staged.framed ? MediaFramedBytes(source).readSync() : source.readSync(),
      original,
      reason:
          '⛔this is the exact defect the user named: 「첫저장전엔 원본이 '
          '바뀌면 바뀐게 저장된다는게아니야?」',
    );
  });

  test('a framed staged file still serves a WINDOW', () async {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final path = compressibleFile('take.wav');
    final original = File(path).readAsBytesSync();
    await pool.addMediaAssets([path], carried: true);
    final staged = stagedCopyIn(session, path)!;

    final framed = MediaFramedBytes(
      MediaAppFileBytes(path: staged.path, framed: true),
    );
    final window = Uint8List(200);
    expect(framed.readIntoSync(window, 1000, 200), 200);
    expect(window, Uint8List.sublistView(original, 1000, 1200));
  });

  test(
    '🚨a consumer asking the session for bytes never learns about blocks',
    () async {
      final path = compressibleFile('take.wav');
      final original = File(path).readAsBytesSync();
      await pool.addMediaAssets([path], carried: true);
      File(path).deleteSync();

      // What the conform pipeline and the missing-banner probe call.
      final source = session.projectFile.mediaByteSourceFor(path);

      expect(source.existsSync(), isTrue, reason: 'the project owns it now');
      expect(
        source.lengthSync(),
        original.length,
        reason: 'the FILE\'s length',
      );
      expect(source.readSync(), original);

      final window = Uint8List(128);
      expect(source.readIntoSync(window, 500, 128), 128);
      expect(window, Uint8List.sublistView(original, 500, 628));
    },
  );

  /// 🚨★★★**THE ORDER, NOT JUST THE OUTCOME.**
  ///
  /// Securing the bytes moved into an isolate so a carried movie stops
  /// freezing the app, which turned every entrance into a `Future`. The
  /// outcome tests above still pass if someone drops the internal `await` —
  /// they only look after everything settled — and nothing in the analyzer
  /// objects, because a dropped `Future` inside a `void` statement is
  /// legal Dart.
  ///
  /// What breaks is the promise 유저 2026-08-30 actually asked for: 「품은
  /// 순간 데이터를 가지고있고 **불변**이었으면좋겠어서」. The pool must not
  /// hold an asset whose bytes are still being written.
  ///
  /// So this asserts the ONE thing only the ordering can produce: at the
  /// moment the entrance hands back its future — before any waiting — the
  /// pool has not been told yet.
  group('the pool waits for the bytes', () {
    test(
      '🚨an import that carries registers NOTHING before the bytes land',
      () async {
        final path = compressibleFile('slow.wav');
        final pending = pool.addMediaAssets([path], carried: true);

        expect(
          pool.mediaAssets,
          isEmpty,
          reason:
              'the asset was registered before its bytes were secured — the '
              'entrance ran the command without awaiting the staging',
        );

        await pending;
        expect(pool.mediaAssets, hasLength(1));
        expect(stagedCopyIn(session, path), isNotNull);
      },
    );

    test('🚨and neither does a promotion', () async {
      final path = compressibleFile('later.wav');
      await pool.addMediaAssets([path]);
      expect(pool.mediaAssets.single.carried, isFalse);

      final pending = pool.promoteMediaAssetIntoProject(path);
      expect(
        pool.mediaAssets.single.carried,
        isFalse,
        reason: 'promoted in the pool while its bytes were still being written',
      );

      expect(await pending, isTrue);
      expect(pool.mediaAssets.single.carried, isTrue);
    });
  });

  group('promoting a reference is the same promise, made later', () {
    test('🚨promote stages the bytes, exactly as an import that carried '
        'from the start would have', () async {
      final path = compressibleFile('linked.wav');
      await pool.addMediaAssets([path]);
      expect(
        session.mediaStagingStore.holdsAnyCopyOf(path),
        isFalse,
        reason: 'fixture: a reference stages nothing',
      );

      expect(
        await pool.promoteMediaAssetIntoProject(path),
        isTrue,
      );

      expect(
        stagedCopyIn(session, path),
        isNotNull,
        reason:
            '⛔this verb is the user saying「keep this inside」, which is the '
            'same sentence the import window says — so it must mean the '
            'same thing, or one entrance stays on the old behaviour where '
            'deleting the original before the save quietly emptied it',
      );
    });

    test('and the bytes survive the original after promoting', () async {
      final path = compressibleFile('linked.wav');
      final original = File(path).readAsBytesSync();
      await pool.addMediaAssets([path]);
      await pool.promoteMediaAssetIntoProject(path);

      File(path).deleteSync();

      final source = session.projectFile.mediaByteSourceFor(path);
      expect(source.existsSync(), isTrue);
      expect(source.readSync(), original);
    });

    test('promoting something already carried changes nothing', () async {
      final path = compressibleFile('take.wav');
      await pool.addMediaAssets([path], carried: true);
      final staged = stagedCopyIn(session, path)!;

      expect(
        await pool.promoteMediaAssetIntoProject(path),
        isFalse,
      );
      expect(stagedCopyIn(session, path)!.path, staged.path);
    });
  });

  test('🚨a relinked carry is held at the new path', () async {
    final from = compressibleFile('take.wav');
    final original = File(from).readAsBytesSync();
    await pool.addMediaAssets([from], carried: true);
    expect(stagedCopyIn(session, from), isNotNull);

    final to = '${root.path}/moved.wav'.replaceAll(r'\', '/');
    File(to).writeAsBytesSync(original);
    await pool.relinkMediaAsset(from, to);

    expect(
      stagedCopyIn(session, to),
      isNotNull,
      reason:
          '⛔a carried asset that looked unstaged after a relink would be '
          'back to the promise being kept at save time',
    );

    File(to).deleteSync();
    expect(session.projectFile.mediaByteSourceFor(to).readSync(), original);
  });

  test('a file picked in the OS\'s spelling is relinked in the pool\'s — '
      'and re-staged under it (audit 2026-09-24 ②)', () async {
    final from = compressibleFile('take.wav');
    await pool.addMediaAssets([from], carried: true);
    final to = '${root.path}/moved.wav'.replaceAll(r'\', '/');
    File(to).writeAsBytesSync(File(from).readAsBytesSync());

    await pool.relinkMediaAsset(from, to.replaceAll('/', r'\'));

    expect(
      session.repository.requireProject().mediaAssets.map((a) => a.path),
      [to],
    );
    expect(
      stagedCopyIn(session, to),
      isNotNull,
      reason: 'the carried asset is staged under the key the pool holds',
    );
  });

  group('🚨relink: the two kinds know different things', () {
    /// A DIFFERENT file — nothing checks that it matches.
    ({String path, Uint8List bytes}) otherFile(String name) {
      final bytes = Uint8List(180 * 1024);
      for (var i = 0; i < bytes.length; i += 1) {
        bytes[i] = (i ~/ 5 + 7) & 0xFF;
      }
      final path = '${root.path}/$name'.replaceAll(r'\', '/');
      File(path).writeAsBytesSync(bytes);
      return (path: path, bytes: bytes);
    }

    test('a BY-HAND relink carries the file the user picked, as a carry of '
        'its own', () async {
      final from = compressibleFile('take.wav');
      await pool.addMediaAssets([from], carried: true);
      final before = carryIn(session, from)!;
      final other = otherFile('other.wav');

      await pool.relinkMediaAsset(from, other.path);

      expect(
        carryIn(session, other.path)!.token,
        isNot(before.token),
        reason:
            '⛔kept, the carry\'s one name would mean two sets of bytes — '
            'the old file\'s, which an undo reads, and the picked one\'s',
      );
      final staged = stagedCopyIn(session, other.path);
      expect(staged, isNotNull, reason: 'the new file is held');
      expect(
        mediaAppFileSource(staged!.path).readSync(),
        other.bytes,
        reason:
            '⛔the bytes are the ONE THE USER PICKED. Moving the old staged '
            'blob over would keep serving the old picture under the new '
            "file's name, for ever, with the project insisting it was right",
      );
    });

    test('🚨an undo of a by-hand relink reads the bytes the asset had — the '
        'old carry\'s copy stays for it (audit 09-25)', () async {
      final from = compressibleFile('take.wav');
      final original = File(from).readAsBytesSync();
      await pool.addMediaAssets([from], carried: true);
      final before = carryIn(session, from)!;
      await pool.relinkMediaAsset(from, otherFile('other.wav').path);
      File(from).deleteSync();

      session.undo();

      expect(carryIn(session, from), before);
      expect(
        session.projectFile.mediaByteSourceFor(from).readSync(),
        original,
        reason:
            '🪦the relink retired this copy, and the undo found only the '
            'original — gone here, as it is when a relink is needed',
      );
    });

    test('and after a save: the save takes the carry the pool names, and '
        'leaves the one the undo brings back', () async {
      final from = compressibleFile('take.wav');
      final original = File(from).readAsBytesSync();
      await pool.addMediaAssets([from], carried: true);
      await pool.relinkMediaAsset(from, otherFile('other.wav').path);
      File(from).deleteSync();
      await session.projectDoor.saveProjectToFile(
        '${root.path}/scene.anicel',
        asked: SaveAsked.byAPerson,
      );

      session.undo();

      expect(
        session.projectFile.mediaByteSourceFor(from).readSync(),
        original,
      );
    });

    test('a by-hand relink the pool refuses moves nothing — not the facts, '
        'not the bytes', () async {
      final from = compressibleFile('take.wav');
      final taken = otherFile('taken.wav');
      await pool.addMediaAssets([from, taken.path], carried: true);
      session.mediaFingerprints
        ..rememberMediaFingerprint(from, File(from).readAsBytesSync())
        ..rememberMediaFingerprint(taken.path, taken.bytes);
      final facts = [
        session.mediaFingerprints.recordedMediaIdentity(from),
        session.mediaFingerprints.recordedMediaIdentity(taken.path),
      ];
      final carries = [carryIn(session, from), carryIn(session, taken.path)];
      final copies = session.mediaStagingStore.list().length;

      // The path is another asset's: the coordinator refuses.
      await pool.relinkMediaAsset(from, taken.path);

      expect(
        [carryIn(session, from), carryIn(session, taken.path)],
        carries,
      );
      expect(
        [
          session.mediaFingerprints.recordedMediaIdentity(from),
          session.mediaFingerprints.recordedMediaIdentity(taken.path),
        ],
        facts,
        reason:
            '🪦the fingerprints moved whatever the pool said, onto the other '
            'asset\'s path — the very facts a relink is decided by',
      );
      expect(
        session.mediaStagingStore.list(),
        hasLength(copies),
        reason: 'the copy taken for a carry that never came is gone again',
      );
      expect(stagedCopyIn(session, from), isNotNull);
    });

    test('a BATCH relink keeps the carry, because the matcher checked '
        'identity first — the same copy, under the same name', () async {
      final from = compressibleFile('take.wav');
      final original = File(from).readAsBytesSync();
      await pool.addMediaAssets([from], carried: true);

      // What the matcher proposes: the SAME content at a new location.
      final to = '${root.path}/moved/take.wav'.replaceAll(r'\', '/');
      Directory('${root.path}/moved').createSync();
      File(to).writeAsBytesSync(original);

      final before = carryIn(session, from)!;
      pool.relinkMediaAssets({from: to});

      expect(carryIn(session, to)!.token, before.token);
      final staged = stagedCopyIn(session, to);
      expect(staged, isNotNull);
      expect(mediaAppFileSource(staged!.path).readSync(), original);
      expect(
        session.mediaStagingStore.find(before)!.path,
        staged.path,
        reason:
            '🪦the copy was RENAMED after the new path, and an undo of the '
            'relink looked for the old name and found nothing',
      );
      expect(session.mediaStagingStore.list(), hasLength(1));
    });

    test('a batch move the pool refuses moves no facts', () async {
      final from = compressibleFile('take.wav');
      final taken = otherFile('taken.wav');
      await pool.addMediaAssets([from, taken.path]);
      session.mediaFingerprints
        ..rememberMediaFingerprint(from, File(from).readAsBytesSync())
        ..rememberMediaFingerprint(taken.path, taken.bytes);
      final facts = [
        session.mediaFingerprints.recordedMediaIdentity(from),
        session.mediaFingerprints.recordedMediaIdentity(taken.path),
      ];

      pool.relinkMediaAssets({from: taken.path});

      expect([
        session.mediaFingerprints.recordedMediaIdentity(from),
        session.mediaFingerprints.recordedMediaIdentity(taken.path),
      ], facts);
    });

    test('a by-hand relink of a REFERENCED asset stages nothing', () async {
      final from = compressibleFile('linked.wav');
      await pool.addMediaAssets([from]);
      final to = '${root.path}/elsewhere.wav'.replaceAll(r'\', '/');
      File(to).writeAsBytesSync(File(from).readAsBytesSync());

      await pool.relinkMediaAsset(from, to);

      expect(
        session.mediaStagingStore.holdsAnyCopyOf(to),
        isFalse,
        reason: 'the user kept the link; relinking is not a promotion',
      );
    });
  });

  test('🚨a carried asset whose original is gone is NOT missing', () async {
    final path = compressibleFile('take.wav');
    await pool.addMediaAssets([path], carried: true);
    File(path).deleteSync();

    pool.refreshMediaExistence();

    expect(
      pool.missingMediaPaths,
      isNot(contains(path)),
      reason:
          '⛔the project holds these bytes — deleting the original is the '
          'very act carrying exists to survive. A missing banner here '
          'feeds the relink hunt, whose "success" re-keys the asset away '
          'from the bytes it was promised',
    );
  });
}
