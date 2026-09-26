import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import '../../helpers/temp_dir.dart';

/// 🚨★★★**THE SESSION HOLDS THE PROJECT FILE, AND LETS GO TO BE SAVED OVER.**
///
/// After a save a clean cel keeps only `{path, offset, length}` — the
/// `.anicel` IS the cold tier — so the user's own output file is the app's
/// backing store. Opening and closing around every read meant that between
/// two reads the app held nothing: deleting the file mid-session took the
/// work with it (유저 2026-08-31, 94 drawings).
///
/// ⚠️「It still works」 cannot see this: opening per read and holding one open
/// return the same bytes. What separates them is HOW MANY TIMES the file was
/// opened, so that is what is asserted — a test that only compared bytes
/// would pass with the whole class deleted.
void main() {
  late Directory scratch;

  setUp(() {
    OpenProjectFile.debugResetForTests();
    scratch = Directory.systemTemp.createTempSync('qa_handle');
  });

  tearDown(() {
    OpenProjectFile.debugResetForTests();
    deleteTempQuietly(scratch);
  });

  String write(String name, int fill, {int length = 4096}) {
    final path = '${scratch.path}${Platform.pathSeparator}$name';
    File(path).writeAsBytesSync(Uint8List(length)..fillRange(0, length, fill));
    return path;
  }

  test('reads come back from the right offset', () {
    final path = '${scratch.path}${Platform.pathSeparator}p.anicel';
    File(path).writeAsBytesSync(
      Uint8List.fromList(List.generate(256, (i) => i)),
    );

    expect(
      OpenProjectFile.instance.readAt(path, 10, 4),
      orderedEquals([10, 11, 12, 13]),
    );
    expect(
      OpenProjectFile.instance.readAt(path, 200, 2),
      orderedEquals([200, 201]),
    );
  });

  test('one open serves every read — the property nothing else can see', () {
    final path = write('p.anicel', 7);

    for (var i = 0; i < 20; i += 1) {
      OpenProjectFile.instance.readAt(path, i * 8, 8);
    }

    expect(
      OpenProjectFile.debugOpens,
      1,
      reason: 'twenty reads must cost one open — per-read opening is the '
          'state this class exists to leave, and the bytes look identical '
          'either way',
    );
    expect(OpenProjectFile.instance.isHolding(path), isTrue);
    expect(OpenProjectFile.instance.heldPaths, [path]);
  });

  /// ↩️This was 「a different project takes the handle with it」: reading
  /// another file let the first go, on the grounds that nobody had it open
  /// any more. With a project per tab (I-7) somebody does — the first tab —
  /// and its clean cels still read from that file. A project lets go of its
  /// file when IT closes (`the_opened_project_is_held_test`).
  test('two open projects hold two files — reading one never lets go of the '
      'other (I-7)', () {
    final first = write('a.anicel', 1);
    final second = write('b.anicel', 2);

    OpenProjectFile.instance.readAt(first, 0, 1);
    expect(OpenProjectFile.instance.readAt(second, 0, 1), orderedEquals([2]));

    expect(OpenProjectFile.debugOpens, 2);
    expect(
      OpenProjectFile.instance.isHolding(first),
      isTrue,
      reason: 'the first project is still open in its tab: letting its file '
          'go left it deletable under refs that still read it — the '
          '94-drawings loss this class exists to refuse',
    );
    expect(OpenProjectFile.instance.isHolding(second), isTrue);
    OpenProjectFile.instance.readAt(first, 0, 1);
    expect(
      OpenProjectFile.debugOpens,
      2,
      reason: 'and going back to it opens nothing',
    );
  });

  test('releaseFor only lets go of the file it names', () {
    final path = write('p.anicel', 7);
    OpenProjectFile.instance.readAt(path, 0, 1);

    OpenProjectFile.instance.releaseFor('${scratch.path}/somebody-else.anicel');
    expect(
      OpenProjectFile.instance.isHolding(path),
      isTrue,
      reason: 'a blanket release from whoever is about to write SOMETHING '
          'would drop the project file for a sidecar write — the protection '
          'would be off for exactly as long as a save takes',
    );

    OpenProjectFile.instance.releaseFor(path);
    expect(OpenProjectFile.instance.heldPaths, isEmpty);
  });

  test('a save can replace the file the session is holding, and the next '
      'read sees the NEW bytes', () {
    // 🚨★★★**THE ONE THE WHOLE `release` EXISTS FOR — and it fails two
    // different ways depending on the platform, which is why it is asserted
    // as「the next read sees the new bytes」rather than「the rename did not
    // throw」.**
    //
    // A full save and a compaction build a temp file and rename it onto the
    // project path (`_renameWithRetry`). With our handle still open:
    // · Windows REFUSES the rename (measured 2026-09-07, PathAccessException)
    //   — every full save would spend the retries and then throw, blaming a
    //   sync client;
    // · POSIX allows it, and the old handle keeps reading the OLD, now
    //   unlinked file — the save succeeds and the session serves stale
    //   pixels, which is worse than the throw.
    final path = write('p.anicel', 7);
    expect(OpenProjectFile.instance.readAt(path, 0, 1), orderedEquals([7]));

    final temp = write('p.anicel.tmp-1', 9);
    OpenProjectFile.instance.releaseFor(path);
    File(temp).renameSync(path);

    expect(
      OpenProjectFile.instance.readAt(path, 0, 1),
      orderedEquals([9]),
      reason: 'the file was replaced under us — reading 7 here means the '
          'session is still holding the file the save threw away',
    );
    expect(
      OpenProjectFile.debugOpens,
      2,
      reason: 'and it had to open again to see it',
    );
  });

  test('🚨 a read that fails opens again instead of poisoning the session', () {
    // Opening per read had one property worth keeping: a read that failed
    // failed ALONE. A session-long handle loses that — a share that blinks,
    // a cloud file evicted and rehydrated, a volume remounted, all leave a
    // descriptor that answers nothing, and without this every later cel
    // would fail against a file sitting there perfectly readable.
    final path = write('p.anicel', 7);
    expect(OpenProjectFile.instance.readAt(path, 0, 1), orderedEquals([7]));
    expect(OpenProjectFile.debugOpens, 1);

    OpenProjectFile.debugBreakHeldHandle(path);

    expect(
      OpenProjectFile.instance.readAt(path, 0, 1),
      orderedEquals([7]),
      reason: 'the file never went anywhere — only our descriptor did',
    );
    expect(
      OpenProjectFile.debugOpens,
      2,
      reason: 'and it got there by opening again, not by luck',
    );
  });

  test('a read that fails TWICE still throws — the retry is once, not a '
      'loop', () {
    // The save path already handles this throw: a cel whose only copy was
    // in a file that has since gone is skipped and counted. Retrying until
    // it works would turn a reported loss into a hang.
    final path = write('gone.anicel', 7);
    OpenProjectFile.instance.readAt(path, 0, 1);
    OpenProjectFile.debugBreakHeldHandle(path);
    File(path).deleteSync();

    expect(() => OpenProjectFile.instance.readAt(path, 0, 1), throwsA(anything));
  });

  test('releasing what was never held is a no-op, not a throw', () {
    OpenProjectFile.instance.releaseFor('${scratch.path}/never-opened');
    OpenProjectFile.instance.releaseAll();
    expect(OpenProjectFile.instance.heldPaths, isEmpty);
  });

  test('hold takes the handle before any read, and only once', () {
    final path = write('p.anicel', 7);

    OpenProjectFile.instance.hold(path);
    OpenProjectFile.instance.hold(path);

    expect(OpenProjectFile.instance.heldPaths, [path]);
    expect(OpenProjectFile.debugOpens, 1, reason: 'holding what is held opens nothing');
    expect(OpenProjectFile.instance.readAt(path, 0, 1), orderedEquals([7]));
    expect(
      OpenProjectFile.debugOpens,
      1,
      reason: 'the first read goes through the handle the hold took',
    );
  });

  test('holding what is not there is silent', () {
    OpenProjectFile.instance.hold('${scratch.path}/nowhere.anicel');
    expect(OpenProjectFile.instance.heldPaths, isEmpty);
  });

  test('🚨copyOut copies the held bytes through the descriptor — from the '
      'start, wherever the last read left it', () {
    final path = '${scratch.path}${Platform.pathSeparator}p.anicel';
    // Three buffers' worth, so the copy has to loop.
    final bytes = Uint8List(3 << 20);
    for (var i = 0; i < bytes.length; i += 1) {
      bytes[i] = i % 251;
    }
    File(path).writeAsBytesSync(bytes);
    OpenProjectFile.instance.readAt(path, 100, 4);
    final copy = '${scratch.path}${Platform.pathSeparator}copy.anicel';

    expect(OpenProjectFile.instance.copyOut(path, copy), copy);
    expect(File(copy).readAsBytesSync(), bytes);
    expect(File('$copy.part').existsSync(), isFalse);
  });

  test('copyOut answers null for a file it is not holding', () {
    final path = write('p.anicel', 7);
    final copy = '${scratch.path}${Platform.pathSeparator}c';
    expect(OpenProjectFile.instance.copyOut(path, copy), isNull);

    OpenProjectFile.instance.hold(path);
    expect(
      OpenProjectFile.instance.copyOut('${scratch.path}/other.anicel', copy),
      isNull,
    );
    expect(File(copy).existsSync(), isFalse);
  });

  test('a held file whose name went reads as vanished — and its descriptor '
      'still reads the bytes', () {
    final path = write('p.anicel', 7);
    OpenProjectFile.instance.hold(path);
    expect(OpenProjectFile.instance.heldNameVanished(path), isFalse);

    final vault = write('vault.anicel', 9);
    final gone = '${scratch.path}${Platform.pathSeparator}gone.anicel';
    OpenProjectFile.instance.debugHoldAs(vault, gone);

    expect(OpenProjectFile.instance.heldNameVanished(gone), isTrue);
    expect(
      OpenProjectFile.instance.readAt(gone, 0, 1),
      orderedEquals([9]),
      reason: 'the descriptor reads what the name used to point at',
    );
  });
}
