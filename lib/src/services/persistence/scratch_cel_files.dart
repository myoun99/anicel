import 'dart:typed_data';

import 'brush_drawing_binary_codec.dart';
import 'scratch_file.dart';
import 'session_scratch.dart';

/// Where a cooled cel's bytes live while they wait for the save that
/// absorbs them: one file per cel in the run's 이사대기 room.
///
/// 🚨★★★**THE COLD TIER STOPPED BEING A RAM TIER.** A cel that cools is
/// unsaved work — the archive does not hold it yet — so it used to be
/// pinned in memory as a compressed blob, and a project big enough to
/// exceed the hot budget simply carried the overflow in RAM instead. That
/// is the ceiling this removes: cooled cels now weigh a path and a length.
///
/// ⛔**Not「a cache」.** These bytes are the only copy of that picture
/// outside the hot tier while the run lasts — losing one mid-session costs
/// the drawing, not time — which is why the cooling pass treats a refusal
/// as 「stay hot」 rather than a drop, and why the save retires each file
/// only once it has adopted that cel (`BrushFrameStore._dropCold`).
///
/// 🚨★★★**BUT THEY DO NOT SURVIVE THE RUN, AND THAT IS NOW DELIBERATE.**
/// This doc used to say the room was 「the one whose contents a crash
/// leaves standing」, on the way to a round that would offer them back. It
/// will not happen: a room holds only the cels that had COOLED — the hot
/// ones died with the process — so what it could return is an arbitrary
/// part of a picture. 유저 확정 2026-09-10: 「콜드셀만 복구하는건 굉장히
/// 어정쩡하다 … 그림이 전부 복구되는거라면 복구를 생각했겠는데」. The room
/// of an ended run goes at the next launch
/// ([SessionScratch.deleteFoldersOfRunsThatEnded]).
///
/// ⚠️So the thing that protects a long session's work is the AUTOSAVE
/// TICK writing the project file, not this store. That is the same answer
/// the recovery sidecars got when they were deleted in 2026-09-08.
///
/// ⚠️The name is DERIVED from the cel's archive entry name, and then made
/// NEW for every park ([newPath]): no two parks wear one name, so a file a
/// cel lets go can be removed off the UI thread ([ScratchFile.letGo])
/// without ever taking a later park's bytes. ↩️It was the entry name alone
/// (2026-09-07: 「nothing recorded, nothing to fall out of sync」, for a room
/// a crash would offer back — given up 09-10, below) — but every park's
/// path IS recorded, in its ref, and a cel that cooled, thawed and cooled
/// again wrote the same name twice (card
/// a-pasteboard-undo-runs-on-the-ui-thread).
///
/// ⚠️The file mechanics are [ScratchFile]'s, shared with the volatile
/// room: what makes this store different is the ROOM and the type, not
/// how a byte reaches disk.
class ScratchCelFiles {
  const ScratchCelFiles._();

  /// A name no other store's files will wear — one per store that cools.
  ///
  /// 🚨★★★The room is the RUN's, and a run holds a store per open project
  /// (I-7, 유저 2026-09-26) — plus a conte, an envelope and a timesheet ink
  /// store in each. [entryName] is unique per cel only WITHIN a store: two
  /// untitled projects share a project id, and the ink stores' keys are
  /// constants. Without this prefix one tab's cooling overwrote another's
  /// parked cel, and its drop deleted it — unsaved work, gone.
  static String newNamespace() => 's${_namespaces++}';

  static int _namespaces = 0;

  /// A file no park has worn yet for [entryName]'s bytes in the store that
  /// owns [namespace] — a new one each call. [entryName] is the cel's
  /// archive entry name, already base64url.
  ///
  /// ⚠️Asked on the isolate that owns the store, as [newNamespace] is: a
  /// worker counts from nothing, so its names would be that isolate's
  /// again. A worker that parks is handed its path (`cutCelInWorker`).
  static String newPath(String namespace, String entryName) =>
      '${SessionScratch.stagedFolder()}/$namespace-$entryName.${_parks++}.cel';

  static int _parks = 0;

  /// Writes [bytes] to a [newPath] and answers it, or null when the room
  /// refused.
  ///
  /// 🚨A refusal is not an error to throw: the caller is the cooling pass,
  /// and a cel that cannot be parked has to STAY HOT rather than be
  /// dropped. Every other outcome here loses a drawing.
  static String? write(String namespace, String entryName, Uint8List bytes) =>
      ScratchFile.write(newPath(namespace, entryName), bytes);

  /// The blob at [path], or null when it will not read — a torn write, a
  /// file somebody removed under us.
  ///
  /// ⚠️This one earns its place by TYPING the bytes; there is no
  /// `remove` beside it because removing takes a path, and a path
  /// already says which room it came from. [ScratchFile.letGo] serves
  /// both tenants — a per-room name for the same verb is the shape that
  /// lets one of them quietly start meaning "and the other room too".
  static AnicelCelBlob? read(String path) {
    final bytes = ScratchFile.read(path);
    return bytes == null ? null : AnicelCelBlob(bytes);
  }
}
