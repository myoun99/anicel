import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/brush_frame_key.dart';
import '../models/tile_coord.dart';
import 'undo_surface_snapshot.dart';

/// Commands whose undo or redo puts a cel's picture back from a SNAPSHOT —
/// so the step can be read before it is taken, and the pictures it will
/// show made ready first (undo-held-tile-pictures, stage 1).
///
/// 🚨★★★**READ, NOT APPLIED.** A parked payload read ahead is held
/// provisionally ([UndoSurfaceSnapshot.readAhead]) and adopted by the step
/// only against the very surface it leaned on — so a walk here that
/// guessed a cel wrong costs warmed pictures, never a wrong one.
///
/// ⚠️A command that COMPUTES what it puts back — a pixel verb re-running
/// its recipe, a resize re-running its blit — cannot answer before it
/// runs, and reads nothing for that direction.
abstract interface class PictureRestoringCommand {
  /// Reads what this step would put back into [cels], in the order the
  /// step would put it back.
  void readAhead(CelsAhead cels, {required bool undo});

  /// Gives back every read-ahead copy this command holds.
  void dropReadAhead();

  /// Visits every tile this entry alone holds in RAM on the side the cel is
  /// NOT showing ([undone] read the way `RetainedBytesCommand` reads it) —
  /// the tiles a picture made for them could only ever be drawn for by
  /// stepping here (undo-held-tile-pictures, stage 2).
  void visitHeldTiles(HeldTileVisitor visit, {required bool undone});
}

/// Called with each tile an undo entry holds alone, and where it lies.
typedef HeldTileVisitor = void Function(TileCoord coord, BitmapTile tile);

/// Gives back every read-ahead copy a RUN of commands holds — a
/// composite's children and, when the budget runs short, the stacks.
void dropReadAheadOf(Iterable<Object> commands) {
  for (final command in commands.whereType<PictureRestoringCommand>()) {
    command.dropReadAhead();
  }
}

/// One cel across one step: as it stands now, and as the step would leave
/// it.
typedef CelStep = ({BitmapSurface? now, BitmapSurface next});

/// The cels one history step would leave, read before it is taken.
///
/// A composite's children run one after another, so what a later child
/// leans on is what an earlier one put back — [readSnapshot] answers from
/// here first, and from the cel as it stands otherwise.
class CelsAhead {
  CelsAhead({required bool Function(BrushFrameKey key) wants})
    : _wants = wants;

  /// Only cels somebody is LOOKING at are worth reading: a parked payload
  /// comes back through a synchronous disk read, and a cel nobody shows
  /// would pay it for pictures nobody draws.
  final bool Function(BrushFrameKey key) _wants;

  final Map<BrushFrameKey, CelStep> _cels = {};

  /// Every cel the step would put a snapshot back on, of those [_wants] let
  /// through.
  Map<BrushFrameKey, CelStep> get cels => _cels;

  /// Reads [snapshot] as the step would put it back on [key]. [live] is the
  /// cel as it stands, for when nothing earlier in this step put it back —
  /// and it must be the SAME reader the step itself uses, or the step will
  /// not recognise the surface this leaned on and reads the file again.
  void readSnapshot(
    BrushFrameKey key,
    UndoSurfaceSnapshot? snapshot,
    BitmapSurface? Function() live,
  ) {
    if (snapshot == null || !_wants(key)) {
      return;
    }
    final earlier = _cels[key];
    final now = earlier == null ? live() : earlier.now;
    final next = snapshot.readAhead(earlier == null ? now : earlier.next);
    if (next != null) {
      _cels[key] = (now: now, next: next);
    }
  }
}
