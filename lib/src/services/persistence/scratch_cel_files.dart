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
/// outside the hot tier, which is why the room they live in is the one
/// whose contents a crash leaves standing ([SessionScratch]) and not the
/// one that is wiped. Losing a cache costs time; losing this costs the
/// drawing.
///
/// ⚠️The name is DERIVED from the cel's archive entry name — the same rule
/// the staged media and the conform follow ("under a name derived by rule
/// … nothing recorded, nothing to fall out of sync"). A file that nothing
/// remembers cannot be remembered wrongly.
///
/// ⚠️The file mechanics are [ScratchFile]'s, shared with the volatile
/// room: what makes this store different is the ROOM and the type, not
/// how a byte reaches disk.
class ScratchCelFiles {
  const ScratchCelFiles._();

  /// The file [entryName]'s bytes go in. [entryName] is the cel's archive
  /// entry name, which is already base64url and already unique per cel.
  static String pathFor(String entryName) =>
      '${SessionScratch.stagedFolder()}/$entryName.cel';

  /// Writes [bytes] and answers the path, or null when the room refused.
  ///
  /// 🚨A refusal is not an error to throw: the caller is the cooling pass,
  /// and a cel that cannot be parked has to STAY HOT rather than be
  /// dropped. Every other outcome here loses a drawing.
  static String? write(String entryName, Uint8List bytes) =>
      ScratchFile.write(pathFor(entryName), bytes);

  /// The blob at [path], or null when it will not read — a torn write, a
  /// file somebody removed under us.
  static AnicelCelBlob? read(String path) {
    final bytes = ScratchFile.read(path);
    return bytes == null ? null : AnicelCelBlob(bytes);
  }

  /// Removes the file at [path]. Silent: the room goes with the run
  /// anyway, so a leftover costs nothing but space until then.
  static void remove(String path) => ScratchFile.remove(path);
}
