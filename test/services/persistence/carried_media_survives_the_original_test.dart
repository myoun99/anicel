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

  test('품기 stages the bytes at IMPORT, not at save', () {
    final path = compressibleFile('take.wav');

    session.addMediaAssets([path], carried: true);

    expect(
      session.mediaStagingStore.find(path),
      isNotNull,
      reason:
          'the promise is kept the moment the button is pressed — waiting '
          'for a save is exactly the old behaviour',
    );
  });

  test('⛔a REFERENCED import stages nothing', () {
    final path = compressibleFile('linked.wav');

    session.addMediaAssets([path]);

    expect(
      session.mediaStagingStore.find(path),
      isNull,
      reason:
          'the user said keep the link; copying anyway would be a second '
          'copy nobody asked for',
    );
  });

  test('the staged bytes are what a save writes, and the entry name says '
      'whether they are framed', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final path = compressibleFile('take.wav');
    session.addMediaAssets([path], carried: true);
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
      'are still there', () {
    final path = compressibleFile('take.wav');
    final original = File(path).readAsBytesSync();
    session.addMediaAssets([path], carried: true);

    // The whole reason carrying exists.
    File(path).deleteSync();

    final staged = session.mediaStagingStore.find(path)!;
    final source = MediaStagedBytes(path: staged.path, framed: staged.framed);
    final bytes = staged.framed
        ? MediaFramedBytes(source).readSync()
        : source.readSync();
    expect(bytes, original);
  });

  test('and editing the original after the import does not change what the '
      'project holds', () {
    final path = compressibleFile('take.wav');
    final original = File(path).readAsBytesSync();
    session.addMediaAssets([path], carried: true);

    File(path).writeAsBytesSync(Uint8List(64));

    final staged = session.mediaStagingStore.find(path)!;
    final source = MediaStagedBytes(path: staged.path, framed: staged.framed);
    expect(
      staged.framed ? MediaFramedBytes(source).readSync() : source.readSync(),
      original,
      reason:
          '⛔this is the exact defect the user named: 「첫저장전엔 원본이 '
          '바뀌면 바뀐게 저장된다는게아니야?」',
    );
  });

  test('a framed staged file still serves a WINDOW', () {
    if (!engineHere()) {
      markTestSkipped('no engine on this run');
      return;
    }
    final path = compressibleFile('take.wav');
    final original = File(path).readAsBytesSync();
    session.addMediaAssets([path], carried: true);
    final staged = session.mediaStagingStore.find(path)!;

    final framed = MediaFramedBytes(
      MediaStagedBytes(path: staged.path, framed: true),
    );
    final window = Uint8List(200);
    expect(framed.readIntoSync(window, 1000, 200), 200);
    expect(window, Uint8List.sublistView(original, 1000, 1200));
  });

  test(
    '🚨a consumer asking the session for bytes never learns about blocks',
    () {
      final path = compressibleFile('take.wav');
      final original = File(path).readAsBytesSync();
      session.addMediaAssets([path], carried: true);
      File(path).deleteSync();

      // What the conform pipeline and the missing-banner probe call.
      final source = session.mediaByteSourceFor(path);

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
}
