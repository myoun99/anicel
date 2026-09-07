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

  /// Writes [bytes] under a name this run picks, and answers the path —
  /// or null when the room refused, in which case the caller must KEEP
  /// what it was going to park.
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
  static String? write(Uint8List bytes) => ScratchFile.write(
        '${SessionScratch.volatileFolder()}/${_next++}.undo',
        bytes,
      );

  static int _next = 0;
}
