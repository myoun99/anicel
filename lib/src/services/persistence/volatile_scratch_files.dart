import 'dart:io';
import 'dart:typed_data';

import 'scratch_file.dart';
import 'session_scratch.dart';

/// Where an undo payload's bytes go when the byte budget would otherwise
/// DELETE it: one file per payload in the run's 휘발성 room.
///
/// 🚨★★★**THE BUDGET STOPS THROWING WORK AWAY.** Over-budget undo pixels
/// used to be removed from the deep end of the stack — the entry went
/// with them and the user's third-from-last edit simply stopped being
/// undoable. Of the five tools the audit read, not one answers a byte
/// ceiling that way: Krita swaps its undo tiles out FIRST (they are the
/// pages nothing but history is holding), OpenToonz parks them in the
/// image cache's disk tier, Photoshop pages them to the scratch file it
/// already uses for the document. 유저 확정 2026-09-07 (`cold-tier`).
///
/// ⛔**A DIFFERENT ROOM FROM THE COOLED CELS, AND THAT IS THE WHOLE
/// POINT.** A cooled cel is unsaved work waiting to move INTO the project
/// file, so it lives in 이사대기 and a crash must leave it standing. An
/// undo payload names a history that dies with its isolate: it belongs in
/// 휘발성, which the next run sweeps. Putting them in one room would let
/// the save's own deletion take undo down with it — and it would not look
/// like a bug, because the save would succeed, the file would be intact,
/// and only pressing Ctrl+Z would show what had gone.
///
/// 🚨★★★**WRITING IS THE ONLY ROOM-AWARE VERB, AND THAT IS DELIBERATE.**
/// Reading and removing take a PATH, and a path already says which room
/// it came from — so [ScratchFile.read] and [ScratchFile.remove] serve
/// both tenants and this class does not wrap them. Wrapping would have
/// put a second name on each verb per room, which is exactly the shape
/// that lets one of them quietly start meaning "and the other room too".
///
/// ⚠️Bytes, not a format. Whether a payload is compressed before it gets
/// here is the CALLER's decision — this store would be the wrong place to
/// make it, because the answer differs by what is being parked.
class VolatileScratchFiles {
  const VolatileScratchFiles._();

  /// How large this room may get, in bytes. Zero (the default) means no
  /// ceiling, which is what a run that never set one gets.
  ///
  /// 🚨★★★**IT IS THE UNDO BYTE BUDGET, AND THE SAME NUMBER, BECAUSE
  /// PARKING IS THAT BUDGET SPENT SOMEWHERE ELSE.** Everything in this
  /// room is a payload that would be in RAM if the budget had room for
  /// it — so what it may weigh on disk is what it was allowed to weigh in
  /// memory, and asking it to weigh MORE would be asking the ceiling to
  /// mean two things. 유저 확정 2026-09-10. [HistoryManager.byteBudget]
  /// sets both, from one call, so the two cannot drift apart.
  ///
  /// ⚠️Compression makes it generous rather than tight: a parked payload
  /// measures 35-47x smaller than the RAM it left, so a full 200-entry
  /// stack of ordinary strokes is about a megabyte against a budget of
  /// hundreds. It is a wall, not a leash — the case it exists for is the
  /// picture that will not compress.
  ///
  /// ⛔It does NOT follow memory pressure down. Pressure is the OS saying
  /// RAM is tight, and this room is not RAM; lowering it there would shed
  /// the user's history to relieve something it was never holding.
  ///
  /// 🚨With a project per tab (I-7) there is a stack per project and ONE
  /// room, so the room weighs what the STACKS were allowed: the sum of
  /// their budgets ([allow]). A room sized for one stack made each tab's
  /// parking crowd the others', and a stack refused by a full room DROPS
  /// entries — one tab's history spent on another's.
  static int ceilingBytes = 0;

  /// Each undo stack's budget, by stack — [ceilingBytes] is their sum.
  static final Map<Object, int> _allowances = {};

  /// [stack] may park [bytes] in this room — its undo budget, set in the
  /// same call ([HistoryManager.byteBudget]).
  static void allow(Object stack, int bytes) {
    _allowances[stack] = bytes;
    ceilingBytes = _allowances.values.fold(0, (sum, each) => sum + each);
  }

  /// [stack] is gone; the room stops holding a place for it.
  static void forget(Object stack) {
    if (_allowances.remove(stack) != null) {
      ceilingBytes = _allowances.values.fold(0, (sum, each) => sum + each);
    }
  }

  /// Writes [bytes] under a name this run picks, and answers the path —
  /// or null when the room refused, in which case the caller must KEEP
  /// what it was going to park.
  ///
  /// 🚨★★★**A FULL ROOM REFUSES, AND REFUSING IS ALREADY A LAW.** There
  /// is no second deletion path here: `HistoryManager._parkDeepEnd` reads
  /// a refusal, stands the spill down and calls `_shedOverBudget`, which
  /// is the one place that drops entries — 「Deleting is what happens when
  /// the room refuses, and only then」. A ceiling is simply one more
  /// reason to refuse, alongside a disk that will not take the write.
  ///
  /// ⚠️The room MEASURES itself rather than counting: files leave through
  /// [ScratchFile.remove], which takes a path and does not report to any
  /// room (see the class note above on why that stays true). A counter
  /// here would drift the first time an entry fell off the stack. Reading
  /// the directory costs one `listSync` of at most a couple of hundred
  /// entries, and only on a park — which happens when the byte budget is
  /// already exceeded, not per stroke.
  ///
  /// ⚠️The name only has to be unique within one run's room, and the room
  /// is already unique per run ([SessionScratch]) — so a counter is
  /// enough, and there is nothing to record or to fall out of sync. That
  /// is the difference from the cooled cels, whose names are DERIVED from
  /// the archive entry so a crash can still say which picture they were:
  /// an undo payload has no such second life, so its name means nothing
  /// on purpose.
  ///
  /// ⛔**Statics are per-isolate in Dart**, as [SessionScratch] warns: a
  /// worker that called this would number from zero inside its own copy
  /// and overwrite this one's files. Undo spilling runs on the isolate
  /// that owns the history stack; anything else must be handed the PATH.
  static String? write(Uint8List bytes) {
    final folder = SessionScratch.volatileFolder();
    if (!_roomHasSpaceFor(bytes.length, folder)) {
      return null;
    }
    return ScratchFile.write('$folder/${_next++}.undo', bytes);
  }

  static bool _roomHasSpaceFor(int bytes, String folder) {
    final ceiling = ceilingBytes;
    if (ceiling <= 0) {
      return true;
    }
    return _roomBytes(folder) + bytes <= ceiling;
  }

  /// What the room weighs right now. A room that will not list — it was
  /// swept, or never created — weighs nothing, which is the same answer
  /// an empty one gives and the one that lets the write proceed.
  static int _roomBytes(String folder) {
    try {
      var total = 0;
      for (final entity in Directory(folder).listSync(followLinks: false)) {
        if (entity is File) {
          total += entity.statSync().size;
        }
      }
      return total;
    } on Object {
      return 0;
    }
  }

  static int _next = 0;
}
