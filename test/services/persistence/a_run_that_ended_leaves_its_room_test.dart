import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';

/// 🚨★★★**A FOLDER STILL STANDING AT LAUNCH IS EVIDENCE, NOT LITTER.**
///
/// The app container's per-run room holds two things with different
/// meanings: staged media on its way INTO the next save, and volatile
/// payloads that die with the run. A normal exit takes the whole room. So
/// a room that survives says its run ended without saying goodbye — and
/// what it was carrying is exactly what recovery has to offer back.
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
      //
      // 🚨CONTENT, not an empty file, and the mutation is why: opening a
      // 0-byte file for writing truncates nothing, so a probe that used
      // the truncating mode moved no mtime and the age test passed while
      // measuring nothing. With bytes here, the wrong mode is visible.
      final lock = File('${folder.path}/run.lock')..writeAsStringSync(name);
      // ⚠️And STAMPED IN THE PAST, because the assertion that nothing
      // moves this clock runs microseconds after the write: at the
      // filesystem's timestamp resolution「a moment ago」and「now」are the
      // same value, so a probe that DID move it looked innocent. An hour
      // back is outside any resolution and still far inside the 30 days.
      lock.setLastModifiedSync(
        DateTime.now().subtract(const Duration(hours: 1)),
      );
    }
    return folder;
  }

  test('this run gets a room with both folders, and it is locked', () {
    SessionScratch.ensureThisRunsFolder();

    expect(Directory(SessionScratch.stagedFolder()).existsSync(), isTrue);
    expect(Directory(SessionScratch.volatileFolder()).existsSync(), isTrue);
    expect(File('${SessionScratch.thisRunsFolder()}/run.lock').existsSync(),
        isTrue);
  });

  test('⛔ the room is not named by pid alone — a reused id must not let a '
      'run adopt a dead run\'s room', () {
    // Walking into a crashed run's room means drawing with a stranger's
    // carried bytes and then deleting the evidence recovery was going to
    // offer back.
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
          'threw away are not something to keep offering back',
    );
  });

  test('🚨 the launch sweep takes an ended run\'s VOLATILE and leaves its '
      'STAGED standing', () {
    final dead = endedRun('99001');
    SessionScratch.ensureThisRunsFolder();

    expect(SessionScratch.deleteVolatileFilesOfRunsThatEnded(), 1);

    expect(Directory('${dead.path}/Volatile').existsSync(), isFalse);
    expect(
      File('${dead.path}/Staged/carried.bin').existsSync(),
      isTrue,
      reason: 'a run that ended without deleting its own room CRASHED, and '
          'what it was carrying is what recovery has to be able to offer — '
          'undo payloads name a history that died with its isolate',
    );
  });

  test('⛔ the sweep never touches OUR room', () {
    SessionScratch.ensureThisRunsFolder();
    File('${SessionScratch.volatileFolder()}/live.bin').writeAsBytesSync([9]);

    SessionScratch.deleteVolatileFilesOfRunsThatEnded();

    expect(
      File('${SessionScratch.volatileFolder()}/live.bin').existsSync(),
      isTrue,
      reason: 'taking bytes from the session that is still drawing with '
          'them is the one thing this sweep must never do',
    );
  });

  test('a room with no lock at all counts as ended', () {
    // The shape a run leaves when it dies between creating the folders and
    // opening the lock. Nothing is coming back for it.
    final dead = endedRun('99002', withLock: false);
    SessionScratch.ensureThisRunsFolder();

    expect(SessionScratch.deleteVolatileFilesOfRunsThatEnded(), 1);
    expect(Directory('${dead.path}/Volatile').existsSync(), isFalse);
  });

  // The three claims `media_staging_store_test` used to pin on
  // `sweepAbandoned`, now asked of the room that replaced it.

  // ⚠️Aged by moving the CLOCK, not the folder: `Directory` has no
  // `setLastModified`, and the seam exists for exactly this.
  DateTime inDays(int days) => DateTime.now().add(Duration(days: days));

  test('a room nobody came back to for 30 days goes whole', () {
    final stale = endedRun('99010');
    SessionScratch.ensureThisRunsFolder();

    expect(SessionScratch.deleteFoldersOfEndedRunsOlderThan(now: inDays(40)), 1);
    expect(stale.existsSync(), isFalse);
  });

  test('🚨 and the launch that empties its Volatile does NOT reset its 30 '
      'days', () {
    // A directory's mtime is the last time anything inside it moved, so
    // ageing on the FOLDER would be reset by the volatile sweep that runs
    // beside this one at every launch — no room would ever reach thirty
    // days, and it would look like a working sweep the whole time.
    final stale = endedRun('99015');
    final lock = File('${stale.path}/run.lock');
    final born = lock.lastModifiedSync();
    SessionScratch.ensureThisRunsFolder();

    expect(SessionScratch.deleteVolatileFilesOfRunsThatEnded(), 1);

    expect(
      lock.lastModifiedSync(),
      born,
      reason: '🚨ASKING whether that run is still alive must not touch the '
          'only record of when it started — a probe that opens the lock '
          'for writing with truncation resets the clock, and then every '
          'room looks newborn at every launch',
    );
    // 🚨A moment the two candidate clocks DISAGREE about, which is the
    // only kind that measures anything here. The cutoff lands half an hour
    // ago: the lock still says an hour ago (older — sweep it), the FOLDER
    // says「just now」because deleting `Volatile/` touched it (younger —
    // keep it). Pushing the clock a plain 40 days ahead does not
    // discriminate: a folder stamped「now」is still well inside that.
    final halfAnHourAgo = DateTime.now()
        .add(const Duration(days: 30))
        .subtract(const Duration(minutes: 30));
    expect(
      SessionScratch.deleteFoldersOfEndedRunsOlderThan(now: halfAnHourAgo),
      1,
      reason: 'the age comes from the lock file, written once when the room '
          'was built and never touched again',
    );
    expect(stale.existsSync(), isFalse);
  });

  test('🚨 and nothing at all while the rooms are recent — this sweep can '
      'never be the thing that empties a live session', () {
    endedRun('99012');
    endedRun('99013');
    SessionScratch.ensureThisRunsFolder();

    expect(
      SessionScratch.deleteFoldersOfEndedRunsOlderThan(),
      0,
      reason: 'a crash a minute ago is exactly what recovery is for',
    );
  });

  test('the window is the recovery snapshots\' 30 days, not a second number '
      'to keep in step', () {
    final room = endedRun('99014');
    SessionScratch.ensureThisRunsFolder();

    expect(
      SessionScratch.deleteFoldersOfEndedRunsOlderThan(now: inDays(29)),
      0,
      reason: '29 days is inside it',
    );
    expect(room.existsSync(), isTrue);
    expect(SessionScratch.deleteFoldersOfEndedRunsOlderThan(now: inDays(31)), 1);
  });

  test('⛔ the 30-day sweep never takes OUR room either, however old it '
      'looks', () {
    SessionScratch.ensureThisRunsFolder();

    expect(
      SessionScratch.deleteFoldersOfEndedRunsOlderThan(now: inDays(400)),
      0,
    );
    expect(
      Directory(SessionScratch.thisRunsFolder()).existsSync(),
      isTrue,
      reason: 'a session left open for a year, or a machine whose clock '
          'jumped, must not be able to make a LIVE room look abandoned',
    );
  });
}
