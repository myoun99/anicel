@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/worker_file_reads.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🚨Card a-thawed-cel-is-adopted-on-the-ui-thread: a kept cel's bytes are
/// read on a worker, through a handle of the worker's own
/// ([WorkerFileReads]) — 4.3 ms a cel on the UI thread where the user keeps
/// a project, 112 the longest. That handle is this process's, and Windows
/// refuses a rename onto a file the process holds open: so a file is
/// replaced only once no worker reads it, and a read asked meanwhile waits.
void main() {
  late Directory scratch;

  // The road production takes — a REAL worker. The corpus runs every
  // worker's job here (`flutter_test_config.dart`), where a read is over
  // before it is asked about.
  setUp(() {
    debugWorkersRunHere = false;
    scratch = Directory.systemTemp.createTempSync('qa_worker_reads');
  });
  tearDown(() {
    debugWorkersRunHere = true;
    deleteTempQuietly(scratch);
  });

  String write(String name, int fill, {int length = 4096}) {
    final path = '${scratch.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(Uint8List(length)..fillRange(0, length, fill));
    return path;
  }

  test('a read answers the stretch asked for, and is in flight until it '
      'does', () async {
    final path = '${scratch.path}${Platform.pathSeparator}p.anicel';
    File(path).writeAsBytesSync(
      Uint8List.fromList(List.generate(256, (i) => i)),
    );

    final read = WorkerFileReads.read(path, 10, 4);
    expect(
      WorkerFileReads.inFlight,
      1,
      reason: 'on its way to a worker before this turn ends',
    );

    expect(await read, orderedEquals([10, 11, 12, 13]));
    expect(WorkerFileReads.inFlight, 0);
  });

  test('a read that fails throws what it met, and is in flight no '
      'more', () async {
    final gone = '${scratch.path}${Platform.pathSeparator}never-written';

    await expectLater(
      WorkerFileReads.read(gone, 0, 4),
      throwsA(isA<FileSystemException>()),
    );

    expect(WorkerFileReads.inFlight, 0);
  });

  test('🚨a file is replaced once no worker reads it: the reads in flight '
      'end first, and read the file as it was', () async {
    final path = write('p.anicel', 7);
    final temp = write('p.anicel.tmp-1', 9);
    final reads = [
      for (var i = 0; i < 3; i += 1) WorkerFileReads.read(path, i, 1),
    ];
    expect(WorkerFileReads.inFlight, 3, reason: 'premise');
    int? readingAsItIsReplaced;

    await WorkerFileReads.replacing(path, () {
      readingAsItIsReplaced = WorkerFileReads.inFlight;
      // ⚠️On Windows this very line is the pin too: it throws under a
      // handle a worker still holds.
      File(temp).renameSync(path);
    });

    expect(readingAsItIsReplaced, 0);
    for (final read in reads) {
      expect(await read, orderedEquals([7]));
    }
    expect(File(path).readAsBytesSync().first, 9);
  });

  test('🚨a read asked while its file is being replaced waits, and reads '
      'what replaced it', () async {
    final path = write('p.anicel', 7);
    final temp = write('p.anicel.tmp-1', 9);
    // One in flight, so the replace has something to wait for.
    final before = WorkerFileReads.read(path, 0, 1);
    int? readingAsItIsReplaced;
    final replaced = WorkerFileReads.replacing(path, () {
      readingAsItIsReplaced = WorkerFileReads.inFlight;
      File(temp).renameSync(path);
    });

    final meanwhile = WorkerFileReads.read(path, 0, 1);
    expect(
      WorkerFileReads.inFlight,
      1,
      reason: 'the one asked meanwhile has not gone to a worker',
    );

    await replaced;
    expect(readingAsItIsReplaced, 0);
    expect(await before, orderedEquals([7]));
    expect(await meanwhile, orderedEquals([9]));
    expect(WorkerFileReads.inFlight, 0);
  });

  test('a read of ANOTHER file goes to its worker while one is being '
      'replaced', () async {
    final path = write('p.anicel', 7);
    final temp = write('p.anicel.tmp-1', 9);
    final other = write('other.anicel', 3);
    final before = WorkerFileReads.read(path, 0, 1);
    final replaced = WorkerFileReads.replacing(
      path,
      () => File(temp).renameSync(path),
    );

    final elsewhere = WorkerFileReads.read(other, 0, 1);
    expect(WorkerFileReads.inFlight, 2, reason: 'both on their way');

    expect(await elsewhere, orderedEquals([3]));
    await replaced;
    await before;
  });

  test('a file is replaced without waiting for a read of ANOTHER: a read '
      'that hangs on one file holds up no other file being saved', () async {
    final path = write('p.anicel', 7);
    final temp = write('p.anicel.tmp-1', 9);
    final other = write('other.anicel', 3);
    final elsewhere = WorkerFileReads.read(other, 0, 1);
    int? readingAsItIsReplaced;

    await WorkerFileReads.replacing(path, () {
      readingAsItIsReplaced = WorkerFileReads.inFlight;
      File(temp).renameSync(path);
    });

    expect(
      readingAsItIsReplaced,
      1,
      reason: 'the read of the other file, still on its way',
    );
    expect(await elsewhere, orderedEquals([3]));
    expect(File(path).readAsBytesSync().first, 9);
  });

  test('a replace that throws answers its throw, and the reads held off go '
      'on', () async {
    final path = write('p.anicel', 7);
    final before = WorkerFileReads.read(path, 0, 1);
    final replaced = WorkerFileReads.replacing<void>(
      path,
      () => throw const FileSystemException('refused'),
    );
    final meanwhile = WorkerFileReads.read(path, 0, 1);

    await expectLater(replaced, throwsA(isA<FileSystemException>()));

    expect(await before, orderedEquals([7]));
    expect(await meanwhile, orderedEquals([7]), reason: 'nothing replaced it');
  });

  test('🚨the save\'s rename goes through that door: a worker reading the '
      'file has ended when the file is replaced', () async {
    final path = write('p.anicel', 7);
    final temp = write('p.anicel.tmp-1', 9);
    final reading = WorkerFileReads.read(path, 0, 1);
    expect(WorkerFileReads.inFlight, 1, reason: 'premise');

    await AnicelFileService.replaceWithRetry(File(temp), path);

    expect(
      WorkerFileReads.inFlight,
      0,
      reason: 'renamed under a read still in flight — Windows refuses that, '
          'and the retries sleep on the thread the worker answers to',
    );
    expect(await reading, orderedEquals([7]), reason: 'the file as it was');
    expect(File(path).readAsBytesSync().first, 9);
  });
}
