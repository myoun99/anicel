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
/// ⚠️Bytes, not a format. Whether a payload is compressed before it gets
/// here is the CALLER's decision — this store would be the wrong place to
/// make it, because the answer differs by what is being parked.
class VolatileScratchFiles {
  const VolatileScratchFiles._();

  /// Writes [bytes] under a name this run picks, and answers the path —
  /// or null when the room refused, in which case the caller must KEEP
  /// what it was going to park.
  ///
  /// ⚠️The name only has to be unique within one run's room, and the room
  /// is already unique per run ([SessionScratch]) — so a counter is
  /// enough, and there is nothing to record or to fall out of sync.
  ///
  /// ⛔**Statics are per-isolate in Dart**, as [SessionScratch] warns: a
  /// worker that called this would number from zero inside its own copy
  /// and overwrite this one's files. Undo spilling runs on the isolate
  /// that owns the history stack; anything else must be handed the PATH.
  static String? write(Uint8List bytes) =>
      ScratchFile.write('${SessionScratch.volatileFolder()}/${_next++}.undo',
          bytes);

  static int _next = 0;

  /// The bytes at [path], or null when they will not read.
  ///
  /// 🚨A null here is a LOST UNDO STEP, not a cache miss — the caller has
  /// already dropped what it parked. It has to say so rather than restore
  /// a blank.
  static Uint8List? read(String path) => ScratchFile.read(path);

  /// Removes [path] — called when an entry leaves the stack for good.
  static void remove(String path) => ScratchFile.remove(path);
}
