import 'dart:io';

import 'app_support_path.dart';

/// The app container's PER-RUN room: `<container>/Sessions/<pid>/`.
///
/// 🚨★★★**THE APP CONTAINER HAS THREE KINDS OF TENANT, AND THIS IS TWO OF
/// THEM** (유저 2026-09-07): **이사대기** — bytes waiting to move INTO the
/// project file at the next save; **휘발성** — bytes that mean nothing once
/// this run ends (undo payloads); and **유저설정**, which is everything
/// already beside this folder and is not ours.
///
/// [appSupportFilePath] states the price of admission — 「what a new tenant
/// owes is a LIFETIME」 — so here is this one's, and it is the shortest in
/// the container: **one run of the app.** A folder still standing when the
/// app starts is not a leftover to tidy silently, it is the evidence that
/// a run ended without saying goodbye.
///
/// ⛔**NOT beside the project file.** The rule this facility partly
/// reverses (`fdd328ba`, R22-C) was written with TWO reasons — 「no temp
/// files, no drive-sync pollution」 — and only the first is being taken
/// back. Scratch beside a `.anicel` lands in the user's Drive or Dropbox
/// folder and gets uploaded, byte for byte, over and over.
///
/// 🚨**A pid is not an identity — a LOCK is.** Operating systems reuse
/// process ids, so 「is 4312 running?」 answers 「something is」. Each run
/// holds [_lockName] open and locked for its whole life instead: a folder
/// whose lock can be taken is a folder whose owner is gone, on Windows and
/// POSIX alike, with no list of live sessions to be handed and get wrong.
/// (The staged-media sweep this replaces refused a live set for exactly
/// that reason and had to fall back on age; the refusal is kept and the
/// answer is better — see [deleteFoldersOfEndedRunsOlderThan].)
///
/// ⚠️**AND THE TEST CORPUS CANNOT REACH THAT ANSWER.** A lock held by a
/// DIFFERENT process needs a second process, and this repo forbids a test
/// spawning one (`tests_do_not_race_the_code_test`). Faking it in-process
/// would measure the opposite of production: POSIX `fcntl` locks belong to
/// the process, so a lock taken in the test is re-takeable by the test.
/// What IS pinned is every other branch — our own room by an explicit
/// identity check rather than the lock, a missing lock file, and a lock
/// nobody holds. Read the two lines below with that in mind.
///
/// ⛔And one POSIX trap that follows from the same semantics: **closing
/// ANY descriptor on a file drops every lock this process holds on it.**
/// Nothing else opens [_lockName] — keep it that way.
class SessionScratch {
  const SessionScratch._();

  /// `<container>/Sessions` — the parent of every run's room.
  static String rootFolder() =>
      testRedirectedAppSupportPath('Sessions', sandbox: 'sessions');

  /// The file whose lock says 「this run is still here」.
  static const String _lockName = 'run.lock';

  /// Where the carried-media bytes wait for the save that absorbs them.
  ///
  /// 🚨**ASKING FOR IT BUILDS AND LOCKS THE ROOM** ([ensureThisRunsFolder],
  /// idempotent). ⛔Not a convenience: a path inside a room that does not
  /// exist is a lie, and worse, a room with folders but no lock reads to
  /// every OTHER run as 「that one ended」 — a second instance would delete
  /// the volatile payloads of a session that is still drawing. The staging
  /// store creates its directory on first write, so without this the hole
  /// opens exactly when the user carries their first import.
  static String stagedFolder() {
    ensureThisRunsFolder();
    return '${thisRunsFolder()}/Staged';
  }

  /// Where bytes that die with the run go — undo payloads today. Builds and
  /// locks the room for the same reason [stagedFolder] does.
  static String volatileFolder() {
    ensureThisRunsFolder();
    return '${thisRunsFolder()}/Volatile';
  }

  static String thisRunsFolder() => '${rootFolder()}/$_runId';

  /// This run's room NAME: the pid, and the moment this run first asked.
  ///
  /// 🚨★★★**THE PID ALONE WOULD MAKE US ADOPT A DEAD RUN'S ROOM.** Ids are
  /// reused: a run that crashed as 4312 leaves a room full of staged media
  /// that recovery is supposed to offer back, and the next run to be handed
  /// 4312 would walk straight into it — drawing with a stranger's carried
  /// bytes, and then deleting that evidence on its way out as though it
  /// were its own. The timestamp makes the name unrepeatable; the pid stays
  /// because a person looking in the container should be able to tell which
  /// window this was.
  ///
  /// ⚠️`static final`, so it is computed once and every later call agrees —
  /// a room whose name moved would be a room nothing could let go of.
  ///
  /// ⛔**AND STATICS ARE PER-ISOLATE IN DART, so this name means nothing
  /// inside an `Isolate.run`.** Anything that writes into the room from a
  /// worker must be handed the PATH, resolved here first — which is what
  /// `MediaStagingStore.stageCarriedBytes` already does ("Scalars only.
  /// The closure crosses an isolate boundary"). A worker that asked for
  /// the folder itself would quietly build a second room, lock it, and
  /// leave it behind as a crash that never happened.
  static final String _runId = '$pid-${DateTime.now().microsecondsSinceEpoch}';

  /// Creates this run's room and takes its lock, once.
  ///
  /// ⚠️Idempotent and cheap to call from every entry point, because there
  /// is no single 「the app started」 in this codebase that a test also
  /// goes through.
  static void ensureThisRunsFolder() {
    if (_held != null) {
      return;
    }
    final room = thisRunsFolder();
    Directory('$room/Staged').createSync(recursive: true);
    Directory('$room/Volatile').createSync(recursive: true);
    final lock = File('$room/$_lockName');
    // 🚨**IT HAS CONTENT ON PURPOSE.** The name is what a person reading
    // the container needs, and — the reason it is not optional — an EMPTY
    // lock file makes the truncation hazard in [_runHasEnded] invisible:
    // opening a 0-byte file for writing truncates nothing, so nothing
    // moves its mtime and a probe that got the mode wrong would look
    // correct on every platform until the day it did not. With bytes in
    // it, getting that mode wrong is measurable.
    lock.writeAsStringSync(_runId);
    final handle = lock.openSync(mode: FileMode.append);
    handle.lockSync(FileLock.exclusive);
    _held = handle;
  }

  static RandomAccessFile? _held;

  /// Deletes THIS run's room — the staged media waiting to be saved and the
  /// volatile payloads — on a normal exit.
  ///
  /// ⛔Named for what it removes rather than 「clears the scratch」: the two
  /// folders have different meanings and a verb that says neither is how a
  /// later reader deletes the wrong one.
  ///
  /// 🚨Both really do die here. By the time a normal exit reaches this, the
  /// gate has already asked: the work was saved (and the save retired what
  /// it absorbed) or it was discarded, and staged bytes for a project the
  /// user threw away are not something to keep offering back.
  static void deleteThisRunsFolder() {
    final handle = _held;
    _held = null;
    handle?.closeSync();
    _deleteFolder(Directory(thisRunsFolder()));
  }

  /// Deletes the VOLATILE folder of every run that is no longer here.
  ///
  /// ⛔Staged media is deliberately left standing: a run that ended without
  /// deleting its own room crashed, and what it was carrying is exactly
  /// what recovery has to be able to offer. Undo payloads have no such
  /// second life — they name a history that died with its isolate.
  ///
  /// ⚠️Called once per launch. Answers how many folders it emptied.
  static int deleteVolatileFilesOfRunsThatEnded() {
    var swept = 0;
    for (final folder in _foldersOfRunsThatEnded()) {
      if (_deleteFolder(Directory('${folder.path}/Volatile'))) {
        swept += 1;
      }
    }
    return swept;
  }

  /// Deletes the WHOLE room of every ended run older than [olderThan].
  ///
  /// 🚨**THIS IS WHERE THE 30-DAY RULE WENT** (유저 2026-08-26: 「30일좋고」),
  /// and it now measures the right thing. It used to sweep staged FILES by
  /// age, on the reasoning that 「a staged file is written once and never
  /// touched, so an old one belongs to a project that was never saved」 —
  /// true, but it could not tell a crash from an abandonment and so had to
  /// wait a month before touching either. A room says which: a room whose
  /// run ended crashed, and one that has sat there a month crashed and was
  /// never come back for.
  ///
  /// ⚠️Called ONCE PER LAUNCH — and it is the container's ONLY sweep now
  /// that the recovery snapshots are gone. A live room is never a
  /// candidate, so the old caveat 「a session open longer than the window
  /// must not have its own bytes taken」 is now structural rather than a
  /// rule about when to call.
  static int deleteFoldersOfEndedRunsOlderThan({
    Duration olderThan = const Duration(days: 30),
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(olderThan);
    var swept = 0;
    for (final folder in _foldersOfRunsThatEnded()) {
      if (!_startedBefore(folder, cutoff)) {
        continue;
      }
      if (_deleteFolder(folder)) {
        swept += 1;
      }
    }
    return swept;
  }

  /// When that run STARTED, read from its lock file rather than its folder.
  ///
  /// 🚨★★★**A DIRECTORY'S MTIME IS NOT WHEN THE RUN BEGAN — IT IS THE LAST
  /// TIME ANYTHING INSIDE IT MOVED.** Removing `Volatile/` changes the
  /// parent's mtime, and [deleteVolatileFilesOfRunsThatEnded] does exactly
  /// that at every launch. Ageing on the folder would therefore reset the
  /// clock on each start and no room would ever reach thirty days: it would
  /// look like a working sweep and quietly keep everything for ever.
  ///
  /// The lock file is written once, when the room is built, and nothing
  /// touches it again. ⚠️A room with no lock file at all cannot say when it
  /// began, so it is not aged out here — it is the shape a run that died
  /// mid-creation leaves, it holds nothing, and the volatile sweep already
  /// treats it as ended.
  static bool _startedBefore(Directory folder, DateTime cutoff) {
    final stat = FileStat.statSync('${folder.path}/$_lockName');
    return stat.type != FileSystemEntityType.notFound &&
        stat.modified.isBefore(cutoff);
  }

  // 🪦**NO 「delete THAT room」 VERB YET, ON PURPOSE.** The roadmap's
  // 「복구 안 함」 answer needs one, but nothing can call it correctly until
  // a room can say WHICH project it was carrying — that is the round that
  // makes the leftover rooms the recovery target. (`Recovery/` itself is
  // already gone — its snapshots were deleted in 2026-09-08.)
  // A seam nobody calls is a seam that drifts from the only caller it will
  // ever have.

  static Iterable<Directory> _foldersOfRunsThatEnded() sync* {
    final root = Directory(rootFolder());
    if (!root.existsSync()) {
      return;
    }
    final mine = thisRunsFolder();
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory || entity.path.replaceAll(r'\', '/') == mine) {
        continue;
      }
      if (_runHasEnded(entity)) {
        yield entity;
      }
    }
  }

  /// Whether [folder]'s owner is gone — asked by TAKING the lock, not by
  /// looking the pid up.
  ///
  /// ⚠️A room with no lock file at all counts as ended: it was created by
  /// a run that died between `createSync` and `openSync`, and nothing is
  /// coming back for it.
  static bool _runHasEnded(Directory folder) {
    if (folder.path.replaceAll(r'\', '/') == thisRunsFolder()) {
      return false;
    }
    final lock = File('${folder.path}/$_lockName');
    if (!lock.existsSync()) {
      return true;
    }
    RandomAccessFile? probe;
    try {
      // 🚨★★★**`append`, NEVER `write` — `write` TRUNCATES.** Truncating is
      // a write, a write moves the file's mtime, and that mtime is the only
      // record of when the room was built ([_startedBefore]). Probing with
      // `write` would reset every room's age on every launch, so no room
      // would ever reach thirty days — and the sweep would look like it was
      // working the whole time. `append` opens for writing (which an
      // exclusive lock needs) and writes nothing.
      probe = lock.openSync(mode: FileMode.append);
      probe.lockSync(FileLock.exclusive);
      probe.unlockSync();
      return true;
    } on Object {
      // Held by a live run — on Windows the open itself is refused, on
      // POSIX the lock is.
      return false;
    } finally {
      try {
        probe?.closeSync();
      } on Object {
        // Already gone; nothing to close.
      }
    }
  }

  static bool _deleteFolder(Directory folder) {
    if (!folder.existsSync()) {
      return false;
    }
    try {
      folder.deleteSync(recursive: true);
      return true;
    } on Object {
      // Locked by a sync client or an open handle: the next launch retries.
      // The same swallow the two launch sweeps already share — a folder
      // that will not go must not stop the ones after it.
      return false;
    }
  }
}
