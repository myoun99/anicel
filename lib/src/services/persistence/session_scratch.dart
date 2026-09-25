import 'dart:io';

import 'app_support_path.dart';
import 'same_file.dart';

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
/// the container: **one run of the app.** A room still standing when the
/// app starts belonged to a run that ended without saying goodbye, and it
/// goes at once — see [deleteFoldersOfRunsThatEnded] for why nothing is
/// kept back from it any more.
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
/// answer is better — see [deleteFoldersOfRunsThatEnded].)
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

  /// Where the FAILED COPIES (실패본) live — the work of a save its project
  /// file refused (`FailedSaveCopies`). Builds and locks the room for the
  /// same reason [stagedFolder] does; the folder itself is made by the
  /// first write into it.
  ///
  /// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file Q1·Q2): what a
  /// refused save wrote waits in the app's room, NOT beside the user's
  /// file, and for THIS RUN ONLY — 「이번 실행 동안만 — 앱을 닫으면
  /// 사라진다」. The lifetime is this room's, cut short for a copy by the
  /// first save its own project file takes.
  static String unsavedFolder() {
    ensureThisRunsFolder();
    return '${thisRunsFolder()}/Unsaved';
  }

  static String thisRunsFolder() => '${rootFolder()}/$_runId';

  /// This run's room NAME: the pid, and the moment this run first asked.
  ///
  /// 🚨★★★**THE PID ALONE WOULD MAKE US ADOPT A DEAD RUN'S ROOM.** Ids are
  /// reused: a run that crashed as 4312 leaves a room full of staged media,
  /// and the next run to be handed 4312 would walk straight into it —
  /// drawing with a stranger's carried bytes, and then deleting them on its
  /// way out as though it were its own. The timestamp makes the name
  /// unrepeatable; the pid stays
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
  /// 🚨★★★**NOBODY CALLS THIS AT LAUNCH ANY MORE — A RUN THAT STAGES
  /// NOTHING LEAVES NO ROOM AT ALL.** It used to run unconditionally from
  /// the editor's `initState`, so every launch built and locked a room
  /// whether or not one byte ever went into it; six of the seven rooms on
  /// the author's machine held nothing but their lock file. 유저 확정
  /// 2026-09-10: 「애초에 안생기도록」. The two folder getters below already
  /// call this, so the room now appears at the first REAL use.
  ///
  /// 🚨★★★**AND THAT IS ALSO WHAT KEEPS THE SWEEP OFF A LIVE ROOM.**
  /// [deleteFoldersOfRunsThatEnded] no longer waits for an age, so the
  /// window between 「the room exists」 and 「its lock is held」 is a window
  /// in which another launching instance would judge this room dead. Two
  /// things close it: the lock is taken BEFORE the room holds anything (see
  /// the order below), and the sweep runs at LAUNCH while this now runs at
  /// first use — usually minutes apart, and never in the same instant the
  /// way two `initState`s were.
  ///
  /// ⚠️Idempotent and cheap to call from every entry point, because there
  /// is no single 「the app started」 in this codebase that a test also
  /// goes through.
  static void ensureThisRunsFolder() {
    if (_held != null) {
      return;
    }
    final room = thisRunsFolder();
    // ⛔**THE LOCK LANDS BEFORE THE ROOM HOLDS ANYTHING.** `createSync`
    // with `recursive` builds the room and the lock file in one call, and
    // the lock is taken on the next — so the only state another instance
    // can ever see without a lock is an empty directory. Creating `Staged`
    // and `Volatile` first (which is what this did) meant a room could
    // stand there looking complete, and unlocked, for as long as three
    // filesystem calls.
    final lock = File('$room/$_lockName')..createSync(recursive: true);
    final handle = lock.openSync(mode: FileMode.append);
    handle.lockSync(FileLock.exclusive);
    // 🚨**IT HAS CONTENT ON PURPOSE**, and the content is written UNDER the
    // lock. The name is what a person reading the container needs, and —
    // the reason it is not optional — an EMPTY lock file makes the
    // truncation hazard in [_runHasEnded] invisible: opening a 0-byte file
    // for writing truncates nothing, so a probe that got the mode wrong
    // would look correct on every platform until the day it did not. With
    // bytes in it, getting that mode wrong is measurable.
    handle.writeStringSync(_runId);
    _held = handle;
    Directory('$room/Staged').createSync();
    Directory('$room/Volatile').createSync();
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

  /// Deletes the WHOLE room of every run that is no longer here. The
  /// container's ONE sweep. Answers how many rooms went.
  ///
  /// 🚨★★★**THE 30-DAY RULE IS GONE, AND SO IS RECOVERY** (유저 확정
  /// 2026-09-10, reversing their own 「30일좋고」 of 2026-08-26). The month
  /// existed to tell a crash from an abandonment, and that distinction only
  /// ever mattered because a crashed run's room was going to be OFFERED
  /// BACK. It cannot be, and the user weighed exactly why: a room holds the
  /// cels that had COOLED, never the hot ones, so what it could hand back
  /// is an arbitrary part of a drawing — 「콜드셀만 복구하는건 굉장히
  /// 어정쩡하다 … 그림이 전부 복구되는거라면 복구를 생각했겠는데」. With
  /// nothing to offer back there is nothing to wait for.
  ///
  /// ⛔**SO THE STAGED MEDIA GOES TOO**, which the volatile-only sweep this
  /// replaces deliberately spared. That is the reversal, stated plainly so
  /// nobody restores the sparing as a bug fix.
  ///
  /// ⚠️Two sweeps stood here, one taking `Volatile/` at once and one taking
  /// the room after a month. Once the month goes they are the same rule
  /// written twice — the room's deletion already takes `Volatile/` with it
  /// — and the pair would drift the first time either learned something.
  ///
  /// 🚨**IT IS NOT A LEAK-FINDER, and must never become one.** The obvious
  /// sweep — 「delete anything no open project claims」 — is still refused
  /// for the reason `MediaStagingStore` recorded: at launch nothing is open
  /// yet, so the live set is empty and it would take everything. This asks
  /// one question, 「is that run still here」, and the lock answers it.
  ///
  /// ⚠️Called ONCE PER LAUNCH. A live room is never a candidate, so 「a
  /// session open longer than the window must not have its own bytes
  /// taken」 is structural rather than a rule about when to call.
  static int deleteFoldersOfRunsThatEnded() {
    var swept = 0;
    for (final folder in _foldersOfRunsThatEnded()) {
      if (_deleteFolder(folder)) {
        swept += 1;
      }
    }
    return swept;
  }

  static Iterable<Directory> _foldersOfRunsThatEnded() sync* {
    final root = Directory(rootFolder());
    if (!root.existsSync()) {
      return;
    }
    for (final entity in root.listSync(followLinks: false)) {
      // ⛔**OUR OWN ROOM IS EXCLUDED IN [_runHasEnded], AND ONLY THERE.**
      // The same name comparison stood here too until 2026-09-10, and
      // mutation showed what that costs: with either copy present the
      // other could be deleted outright and every test stayed green, so
      // neither was pinned and either could rot unnoticed. The predicate
      // is the semantic home — 「has that run ended」 about the run asking
      // is 「no」 — and this loop is just a loop.
      if (entity is Directory && _runHasEnded(entity)) {
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
    if (namesTheSameFile(folder.path, thisRunsFolder())) {
      return false;
    }
    final lock = File('${folder.path}/$_lockName');
    if (!lock.existsSync()) {
      return true;
    }
    RandomAccessFile? probe;
    try {
      // 🚨★★★**`append`, NEVER `write` — `write` TRUNCATES.** On POSIX the
      // open SUCCEEDS on a lock file a live run holds (only the lock is
      // refused, on the line below), so `write` would empty that run's lock
      // file before we ever learn it is alive — and an empty lock file is
      // the one shape that makes a mode mistake here invisible, which is
      // why [ensureThisRunsFolder] puts bytes in it on purpose. `append`
      // opens for writing (which an exclusive lock needs) and writes
      // nothing.
      //
      // ⚠️It also used to guard the room's AGE, which was read from this
      // file's mtime; the age is gone with the 30-day rule
      // ([deleteFoldersOfRunsThatEnded]) and the mode still matters for the
      // reason above.
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
