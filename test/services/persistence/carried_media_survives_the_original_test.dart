import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/native/qa_cel_compressor.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

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

  setUp(() {
    root = Directory.systemTemp.createTempSync('anicel_carry_test');
    session = EditorSessionManager(
      initialProject: createDefaultProject(),
      mediaStagingStore: MediaStagingStore(
        directoryPath: '${root.path}/Staged',
      ),
    );
  });

  tearDown(() {
    session.dispose();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
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

    await session.addMediaAssets([path], carried: true);

    expect(
      session.mediaStagingStore.find(path),
      isNotNull,
      reason:
          'the promise is kept the moment the button is pressed — waiting '
          'for a save is exactly the old behaviour',
    );
  });

  test('⛔a REFERENCED import stages nothing', () async {
    final path = compressibleFile('linked.wav');

    await session.addMediaAssets([path]);

    expect(
      session.mediaStagingStore.find(path),
      isNull,
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
    await session.addMediaAssets([path], carried: true);
    final staged = session.mediaStagingStore.find(path)!;
    expect(staged.framed, isTrue, reason: 'fixture: this content compresses');

    expect(
      anicelMediaEntryName(path, framed: staged.framed),
      endsWith(mediaFramedEntrySuffix),
      reason: 'a reader must be able to tell without opening the entry',
    );
    expect(
      anicelMediaEntryName(path, framed: false),
      isNot(endsWith(mediaFramedEntrySuffix)),
    );
  });

  test('🚨the original can be deleted right after the import and the bytes '
      'are still there', () async {
    final path = compressibleFile('take.wav');
    final original = File(path).readAsBytesSync();
    await session.addMediaAssets([path], carried: true);

    // The whole reason carrying exists.
    File(path).deleteSync();

    final staged = session.mediaStagingStore.find(path)!;
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
    await session.addMediaAssets([path], carried: true);

    File(path).writeAsBytesSync(Uint8List(64));

    final staged = session.mediaStagingStore.find(path)!;
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
    await session.addMediaAssets([path], carried: true);
    final staged = session.mediaStagingStore.find(path)!;

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
      await session.addMediaAssets([path], carried: true);
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
        final pending = session.addMediaAssets([path], carried: true);

        expect(
          session.mediaAssets,
          isEmpty,
          reason:
              'the asset was registered before its bytes were secured — the '
              'entrance ran the command without awaiting the staging',
        );

        await pending;
        expect(session.mediaAssets, hasLength(1));
        expect(session.mediaStagingStore.find(path), isNotNull);
      },
    );

    test('🚨and neither does a promotion', () async {
      final path = compressibleFile('later.wav');
      await session.addMediaAssets([path]);
      expect(session.mediaAssets.single.carried, isFalse);

      final pending = session.promoteMediaAssetIntoProject(path);
      expect(
        session.mediaAssets.single.carried,
        isFalse,
        reason: 'promoted in the pool while its bytes were still being written',
      );

      expect(await pending, isTrue);
      expect(session.mediaAssets.single.carried, isTrue);
    });
  });

  group('promoting a reference is the same promise, made later', () {
    test('🚨promote stages the bytes, exactly as an import that carried '
        'from the start would have', () async {
      final path = compressibleFile('linked.wav');
      await session.addMediaAssets([path]);
      expect(
        session.mediaStagingStore.find(path),
        isNull,
        reason: 'fixture: a reference stages nothing',
      );

      expect(await session.promoteMediaAssetIntoProject(path), isTrue);

      expect(
        session.mediaStagingStore.find(path),
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
      await session.addMediaAssets([path]);
      await session.promoteMediaAssetIntoProject(path);

      File(path).deleteSync();

      final source = session.projectFile.mediaByteSourceFor(path);
      expect(source.existsSync(), isTrue);
      expect(source.readSync(), original);
    });

    test('promoting something already carried changes nothing', () async {
      final path = compressibleFile('take.wav');
      await session.addMediaAssets([path], carried: true);
      final staged = session.mediaStagingStore.find(path)!;

      expect(await session.promoteMediaAssetIntoProject(path), isFalse);
      expect(session.mediaStagingStore.find(path)!.path, staged.path);
    });
  });

  test('🚨a relink carries the staged bytes to the new path', () async {
    final from = compressibleFile('take.wav');
    final original = File(from).readAsBytesSync();
    await session.addMediaAssets([from], carried: true);
    expect(session.mediaStagingStore.find(from), isNotNull);

    final to = '${root.path}/moved.wav'.replaceAll(r'\', '/');
    File(to).writeAsBytesSync(original);
    await session.relinkMediaAsset(from, to);

    expect(
      session.mediaStagingStore.find(to),
      isNotNull,
      reason:
          '⛔the staged name is DERIVED from the pool path, so a relink '
          'that left it behind would make a carried asset look unstaged '
          'while its bytes waited under a name nothing points at',
    );
    expect(session.mediaStagingStore.find(from), isNull);

    File(to).deleteSync();
    expect(session.projectFile.mediaByteSourceFor(to).readSync(), original);
  });

  group('🚨relink: the two kinds know different things', () {
    test('a BY-HAND relink re-stages from the file the user picked', () async {
      final from = compressibleFile('take.wav');
      await session.addMediaAssets([from], carried: true);
      expect(session.mediaStagingStore.find(from), isNotNull);

      // A DIFFERENT file — nothing checked that it matches.
      final to = '${root.path}/other.wav'.replaceAll(r'\', '/');
      final otherBytes = Uint8List(180 * 1024);
      for (var i = 0; i < otherBytes.length; i += 1) {
        otherBytes[i] = (i ~/ 5 + 7) & 0xFF;
      }
      File(to).writeAsBytesSync(otherBytes);

      await session.relinkMediaAsset(from, to);

      expect(session.mediaStagingStore.find(from), isNull);
      final staged = session.mediaStagingStore.find(to);
      expect(staged, isNotNull, reason: 'the new file is held');

      final stored = staged!.readStoredSync();
      expect(
        staged.framed ? decompressMediaBlob(stored) : stored,
        otherBytes,
        reason:
            '⛔the bytes are the ONE THE USER PICKED. Moving the old staged '
            'blob over would keep serving the old picture under the new '
            "file's name, for ever, with the project insisting it was right",
      );
    });

    test('a BATCH relink moves the bytes, because the matcher checked '
        'identity first', () async {
      final from = compressibleFile('take.wav');
      final original = File(from).readAsBytesSync();
      await session.addMediaAssets([from], carried: true);

      // What the matcher proposes: the SAME content at a new location.
      final to = '${root.path}/moved/take.wav'.replaceAll(r'\', '/');
      Directory('${root.path}/moved').createSync();
      File(to).writeAsBytesSync(original);

      session.relinkMediaAssets({from: to});

      final staged = session.mediaStagingStore.find(to);
      expect(staged, isNotNull);
      final stored = staged!.readStoredSync();
      expect(staged.framed ? decompressMediaBlob(stored) : stored, original);
      expect(session.mediaStagingStore.find(from), isNull);
    });

    test('a by-hand relink of a REFERENCED asset stages nothing', () async {
      final from = compressibleFile('linked.wav');
      await session.addMediaAssets([from]);
      final to = '${root.path}/elsewhere.wav'.replaceAll(r'\', '/');
      File(to).writeAsBytesSync(File(from).readAsBytesSync());

      await session.relinkMediaAsset(from, to);

      expect(
        session.mediaStagingStore.find(to),
        isNull,
        reason: 'the user kept the link; relinking is not a promotion',
      );
    });
  });

  test('🚨a carried asset whose original is gone is NOT missing', () async {
    final path = compressibleFile('take.wav');
    await session.addMediaAssets([path], carried: true);
    File(path).deleteSync();

    session.refreshMediaExistence();

    expect(
      session.missingMediaPaths,
      isNot(contains(path)),
      reason:
          '⛔the project holds these bytes — deleting the original is the '
          'very act carrying exists to survive. A missing banner here '
          'feeds the relink hunt, whose "success" re-keys the asset away '
          'from the bytes it was promised',
    );
  });
}
