import 'dart:async';
import 'dart:io';

import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/temp_dir.dart';

/// F-608 ① (유저 2026-11-16): a TVPaint file that lived only on Google
/// Drive was dropped in, and the window said only 「여는 중」 while it came
/// down. Drive on Windows tells an app nothing about such a file — its
/// attributes read Normal, and both ends answer at once — so the download
/// ran inside the door's own read, where no wait was watching.
///
/// [FolderPicker.readOpenedFile] reads the bytes in under the wait, and
/// every piece is an arrival. A piece is held here the way the cloud holds
/// one ([FolderPicker.debugReadPiece]).
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('anicel-read-in');
    FolderPicker.debugOperatingSystem = 'windows';
  });

  tearDown(() {
    FolderPicker.debugReadPiece = null;
    FolderPicker.debugOperatingSystem = null;
    deleteTempQuietly(temp);
  });

  String file(String name, List<int> bytes) {
    final path = '${temp.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// One byte per piece, so a six-byte file is six arrivals.
  Future<int> oneByte(RandomAccessFile file, List<int> into, int from) =>
      file.readInto(into, from, from + 1);

  test('🚨the read that brings the bytes in IS the wait — a piece that '
      'lands is an arrival, so the quiet runs from it', () async {
    final path = file('drive.tvpp', const [1, 2, 3, 4, 5, 6]);
    final held = Completer<void>();
    final spoke = Completer<void>();
    final told = <({Duration waited, Duration quiet})>[];
    FolderPicker.debugReadPiece = (file, into, from, to) async {
      if (from > 0) {
        await held.future;
      }
      return oneByte(file, into, from);
    };

    final reading = FolderPicker.readOpenedFile(
      path,
      onWaiting: (waited, quiet) {
        told.add((waited: waited, quiet: quiet));
        if (!spoke.isCompleted) {
          spoke.complete();
        }
      },
      isCancelled: () => false,
    );
    await spoke.future;
    held.complete();
    final read = await reading;

    expect(read.bytes, const [1, 2, 3, 4, 5, 6]);
    expect((read.path, read.staged), (path, false));
    expect(
      told.first.quiet,
      lessThan(told.first.waited),
      reason: 'the first piece landed before the wait spoke — the wait must '
          'know it, or a file still coming down reads as one that is not',
    );
  });

  test('🚨a stop during the read stops it: the piece in flight is the last '
      'one asked', () async {
    final path = file('stopped.tvpp', const [1, 2, 3, 4, 5, 6]);
    final held = Completer<void>();
    var asked = 0;
    var stop = false;
    FolderPicker.debugReadPiece = (file, into, from, to) async {
      asked += 1;
      if (from > 0) {
        await held.future;
      }
      return oneByte(file, into, from);
    };

    final reading = FolderPicker.readOpenedFile(
      path,
      onWaiting: (_, _) => stop = true,
      isCancelled: () => stop,
    );

    await expectLater(reading, throwsA(isA<MaterializeCancelled>()));
    held.complete();
    // Room for the four pieces a read that went on would ask for.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(asked, 2, reason: 'the first piece, and the one that was held');
  });

  /// F-608-Q2 (유저 2026-11-17): 「내려받는중에 퍼센테이지가 조금이라도
  /// 안느는게 문제」.
  test('🎯the read says how much of the file is in — before the first piece '
      'and after every one, so the window\'s percent moves while the file '
      'comes down', () async {
    final path = file('drive.tvpp', const [1, 2, 3, 4, 5, 6]);
    final told = <double>[];
    final held = Completer<void>();
    final third = Completer<void>();
    FolderPicker.debugReadPiece = (file, into, from, to) async {
      if (from == 2) {
        third.complete();
        await held.future;
      }
      return oneByte(file, into, from);
    };

    final reading = FolderPicker.readOpenedFile(
      path,
      onRead: told.add,
      isCancelled: () => false,
    );
    await third.future;
    expect(told, [0, 1 / 6, 2 / 6], reason: 'two pieces in, the third held');
    held.complete();
    await reading;

    expect(told, [0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1]);
  });

  test('a file that ends before its length is a read error, never short '
      'bytes', () async {
    final path = file('cut-short.tvpp', const [1, 2, 3]);
    FolderPicker.debugReadPiece = (file, into, from, to) async =>
        from == 0 ? oneByte(file, into, from) : 0;

    await expectLater(
      FolderPicker.readOpenedFile(path),
      throwsA(isA<FileSystemException>()),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('a file that is here is read whole, in one piece, at once', () async {
    final path = file('here.tvpp', List<int>.generate(70000, (i) => i % 251));
    final told = <Duration>[];

    final read = await FolderPicker.readOpenedFile(
      path,
      onWaiting: (waited, _) => told.add(waited),
      isCancelled: () => false,
    );

    expect(read.bytes, File(path).readAsBytesSync());
    expect(told, isEmpty, reason: 'an instant answer is not a wait');
  });
}
