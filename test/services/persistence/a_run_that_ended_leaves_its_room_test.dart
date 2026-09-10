import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';

/// 🚨★★★**A ROOM STILL STANDING AT LAUNCH BELONGED TO A RUN THAT DIED, AND
/// IT GOES.** The app container's per-run room holds staged media on its
/// way INTO the next save and volatile payloads that die with the run. A
/// normal exit takes the whole room; a launch takes the whole room of every
/// run that is no longer here.
///
/// ⚠️**THIS FILE USED TO PIN THE OPPOSITE, AND THE REVERSAL IS THE POINT.**
/// Staged media was spared and rooms were aged out over 30 days (유저
/// 2026-08-26: 「30일좋고」) because a crashed run's carry was going to be
/// offered back. 유저 확정 2026-09-10 that it will not be: a room holds only
/// the cels that had COOLED — the hot ones died with the process — so it
/// could only ever return an arbitrary part of a picture. 「콜드셀만
/// 복구하는건 굉장히 어정쩡하다 … 그림이 전부 복구되는거라면 복구를
/// 생각했겠는데」. With nothing to offer back there is nothing to wait for,
/// and the two sweeps collapse into one.
///
/// ⚠️**WHAT THESE TESTS CANNOT REACH.** 「Is that other run still alive?」
/// is answered by trying to take its lock, and the honest case — a lock
/// held by a DIFFERENT process — needs a second process. This corpus
/// forbids that (`tests_do_not_race_the_code_test`: 「no test spawns a
/// process」), and faking it in-process would measure the wrong thing:
/// POSIX `fcntl` locks belong to the process, so one taken here would be
/// re-takeable here and the test would report the opposite of production.
/// What is pinned below is everything else: our OWN room is never swept
/// (that answer comes from an explicit identity check, not the lock), a
/// room with no lock at all counts as ended, and a lock nobody holds does
/// too.
void main() {
  Directory root() => Directory(SessionScratch.rootFolder());

  setUp(() {
    if (root().existsSync()) {
      root().deleteSync(recursive: true);
    }
  });

  tearDown(() {
    SessionScratch.deleteThisRunsFolder();
    try {
      root().deleteSync(recursive: true);
    } on Object {
      // A handle this test failed to release would keep Windows from
      // deleting the folder; the test that failed is the report.
    }
  });

  Directory endedRun(String name, {bool withLock = true}) {
    final folder = Directory('${SessionScratch.rootFolder()}/$name');
    Directory('${folder.path}/Staged').createSync(recursive: true);
    Directory('${folder.path}/Volatile').createSync(recursive: true);
    File('${folder.path}/Staged/carried.bin').writeAsBytesSync([1, 2, 3]);
    File('${folder.path}/Volatile/undo.bin').writeAsBytesSync([4, 5]);
    if (withLock) {
      // Written and CLOSED — the shape a crashed run leaves behind.
      File('${folder.path}/run.lock').writeAsStringSync(name);
    }
    return folder;
  }

  test('this run gets a room with both folders, and it is locked', () {
    SessionScratch.ensureThisRunsFolder();

    expect(Directory(SessionScratch.stagedFolder()).existsSync(), isTrue);
    expect(Directory(SessionScratch.volatileFolder()).existsSync(), isTrue);
    expect(
      File('${SessionScratch.thisRunsFolder()}/run.lock').existsSync(),
      isTrue,
    );
  });

  test('🚨★★★nothing builds the room until something actually needs it — a '
      'run that stages nothing leaves NOTHING', () {
    // 유저 확정 2026-09-10 (「애초에 안생기도록」). The editor used to call
    // `ensureThisRunsFolder` from `initState`, so every launch left a
    // locked, empty room behind — six of the seven on the author's machine
    // held nothing but their lock file.
    expect(
      Directory(SessionScratch.thisRunsFolder()).existsSync(),
      isFalse,
      reason: 'asking for the PATH must not build anything — that is the '
          'whole difference between an eager and a lazy room',
    );

    final staged = SessionScratch.stagedFolder();

    expect(
      Directory(staged).existsSync(),
      isTrue,
      reason: 'and the first real use builds and locks it',
    );
  });

  testWidgets('🚨★★★AND BOOTING THE WHOLE APP BUILDS NO ROOM — the launch '
      'that stages nothing leaves the container as it found it', (
    tester,
  ) async {
    final dead = endedRun('99030');

    await tester.pumpWidget(const AnicelApp());
    await tester.pump();

    expect(
      dead.existsSync(),
      isFalse,
      reason: 'the one thing a launch DOES owe the container: every room '
          'whose run has ended goes, whole',
    );
    expect(
      Directory(SessionScratch.thisRunsFolder()).existsSync(),
      isFalse,
      reason: '⛔and the one thing it must stop doing: `initState` built and '
          'locked this run\'s room whether or not a byte ever went into it, '
          'which is where the pile of empty rooms came from',
    );
  });

  test('⛔ the room is not named by pid alone — a reused id must not let a '
      'run adopt a dead run\'s room', () {
    // Walking into a crashed run's room means drawing with a stranger's
    // carried bytes, and then deleting them on the way out as our own.
    expect(
      SessionScratch.thisRunsFolder().split('/').last,
      isNot('$pid'),
      reason: 'the name has to be unrepeatable, and a pid is not',
    );
    expect(
      SessionScratch.thisRunsFolder().split('/').last,
      startsWith('$pid-'),
      reason: 'and it should still say which window this was',
    );
  });

  test('asking twice does not take the lock twice', () {
    SessionScratch.ensureThisRunsFolder();
    SessionScratch.ensureThisRunsFolder();
    expect(Directory(SessionScratch.stagedFolder()).existsSync(), isTrue);
  });

  test('🚨 a normal exit takes the whole room — staged AND volatile', () {
    SessionScratch.ensureThisRunsFolder();
    File('${SessionScratch.stagedFolder()}/a.bin').writeAsBytesSync([1]);
    File('${SessionScratch.volatileFolder()}/b.bin').writeAsBytesSync([2]);

    SessionScratch.deleteThisRunsFolder();

    expect(
      Directory(SessionScratch.thisRunsFolder()).existsSync(),
      isFalse,
      reason: 'the gate already asked before this ran: the work was saved '
          'or it was discarded, and staged bytes for a project the user '
          'threw away are not something to keep',
    );
  });

  test('🚨★★★the launch sweep takes an ended run\'s room WHOLE — its staged '
      'media goes with its undo payloads', () {
    final dead = endedRun('99001');
    SessionScratch.ensureThisRunsFolder();

    expect(SessionScratch.deleteFoldersOfRunsThatEnded(), 1);

    expect(
      dead.existsSync(),
      isFalse,
      reason: 'the reversal: staged media used to be spared here so recovery '
          'could offer it back, and recovery is gone',
    );
  });

  test('🚨★★★and it does not wait 30 days — a room that died a moment ago '
      'goes at the very next launch', () {
    final justDied = endedRun('99012');
    SessionScratch.ensureThisRunsFolder();

    expect(
      SessionScratch.deleteFoldersOfRunsThatEnded(),
      1,
      reason: 'the month bought the chance to tell a crash from an '
          'abandonment, and that only mattered while a crash was going to '
          'be offered back',
    );
    expect(justDied.existsSync(), isFalse);
  });

  test('⛔ the sweep never touches OUR room', () {
    SessionScratch.ensureThisRunsFolder();
    File('${SessionScratch.volatileFolder()}/live.bin').writeAsBytesSync([9]);
    File('${SessionScratch.stagedFolder()}/live.bin').writeAsBytesSync([9]);

    expect(SessionScratch.deleteFoldersOfRunsThatEnded(), 0);

    expect(
      File('${SessionScratch.volatileFolder()}/live.bin').existsSync(),
      isTrue,
      reason: 'taking bytes from the session that is still drawing with '
          'them is the one thing this sweep must never do — and now that '
          'it deletes the ROOM, getting this wrong costs the staged media '
          'too',
    );
    expect(
      File('${SessionScratch.stagedFolder()}/live.bin').existsSync(),
      isTrue,
    );
  });

  test('🚨★★★OUR room is spared BY NAME, not because we happen to hold its '
      'lock', () {
    // 🚨**THE OBVIOUS VERSION OF THIS TEST PASSES FOR THE WRONG REASON.**
    // Build the room the normal way and Windows spares it whichever guard
    // you delete: a byte-range lock this process holds is refused even to
    // this process, so the probe fails and the room reads as live. Three
    // mutants — both identity guards off, and each alone — all survived
    // that shape (2026-09-10).
    //
    // ⛔And the platform it passes on is the one where it does not matter.
    // POSIX `fcntl` locks belong to the PROCESS, so on iPad, Android, Mac
    // and Linux the probe takes our own lock happily and the name is the
    // ONLY thing standing between a live session and having its room —
    // staged media, cooled cels and all — deleted underneath it. That got
    // sharper this round: the sweep no longer waits, so a broken guard
    // costs the work immediately rather than in a month.
    //
    // So the room is built here WITHOUT its lock, which is the state the
    // guard alone can answer for.
    final mine = Directory(SessionScratch.thisRunsFolder());
    Directory('${mine.path}/Staged').createSync(recursive: true);
    File('${mine.path}/Staged/live.bin').writeAsBytesSync([9]);

    expect(SessionScratch.deleteFoldersOfRunsThatEnded(), 0);

    expect(
      File('${mine.path}/Staged/live.bin').existsSync(),
      isTrue,
      reason: 'a lockless room is 「ended」 to every other name — ours has to '
          'be answered before the lock is ever asked',
    );
  });

  test('a room with no lock at all counts as ended', () {
    // The shape a run leaves when it dies between creating the room and
    // taking its lock. Nothing is coming back for it.
    final dead = endedRun('99002', withLock: false);
    SessionScratch.ensureThisRunsFolder();

    expect(SessionScratch.deleteFoldersOfRunsThatEnded(), 1);
    expect(dead.existsSync(), isFalse);
  });

  test('every ended room goes in one pass, and a live one still stands', () {
    final a = endedRun('99020');
    final b = endedRun('99021');
    SessionScratch.ensureThisRunsFolder();

    expect(SessionScratch.deleteFoldersOfRunsThatEnded(), 2);
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
    expect(Directory(SessionScratch.thisRunsFolder()).existsSync(), isTrue);
  });
}
