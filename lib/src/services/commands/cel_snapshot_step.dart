import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../cels_ahead.dart';
import '../command.dart';
import '../undo_surface_snapshot.dart';
import 'cel_snapshot_restore.dart';

/// THE HALF OF A HISTORY STEP THAT HOLDS ONE CEL'S PICTURE, BEFORE AND
/// AFTER — what it owes the byte budget, how it parks and comes back, what
/// it reads ahead, and how it puts either side on the cel.
///
/// A stroke, a confirmed move and an edit of a cel's texts each change one
/// cel and keep the pair ([UndoSurfacePair]); how each LANDS is its own, and
/// everything it does with the pair afterwards is this.
///
/// ↩️The stroke and the move each spelled these six out, word for word but
/// for a field's name (`BrushStrokeHistoryCommand`,
/// `BrushLiftMoveHistoryCommand`). The text edit would have been the third
/// (R9-rest, 2026-10-06), which is where two copies of a law become one.
mixin CelSnapshotStep
    implements RetainedBytesCommand, ParkableCommand, PictureRestoringCommand {
  BrushFrameEditingCoordinator get coordinator;
  CacheInvalidationSink? get cacheInvalidationSink;

  /// The cel's picture on either side of the step — null until the step has
  /// landed, and for one that changed nothing: such a step holds nothing,
  /// reads nothing and puts nothing back.
  UndoSurfacePair? get surfaces;

  /// ONE image of the changed tiles is this step's; the other end of every
  /// link is somebody else's — the half the cel is NOT showing, which only
  /// the stack knows ([RetainedBytesCommand.estimatedRetainedBytes]).
  @override
  int estimatedRetainedBytes({required bool undone}) =>
      surfaces?.residentBytes(undone: undone) ?? 0;

  @override
  Future<bool> parkPayload() => surfaces?.park() ?? Future.value(true);

  @override
  void dropPayload() => surfaces?.drop();

  /// What an undo (or a redo) would put back — see
  /// [PictureRestoringCommand].
  @override
  void readAhead(CelsAhead cels, {required bool undo}) {
    final pair = surfaces;
    if (pair == null) {
      return;
    }
    cels.readSnapshot(
      pair.key,
      undo ? pair.before : pair.after,
      () => coordinator.currentSurfaceOf(pair.key),
    );
  }

  @override
  void dropReadAhead() => surfaces?.dropReadAhead();

  @override
  void visitHeldTiles(HeldTileVisitor visit, {required bool undone}) =>
      surfaces?.visitHeldTiles(visit, undone: undone);

  /// Puts the picture the step started from back on its cel.
  void restoreBefore() => _restore(surfaces?.before);

  /// Puts the picture the step ended on back on its cel — a redo.
  void restoreAfter() => _restore(surfaces?.after);

  void _restore(UndoSurfaceSnapshot? snapshot) {
    final pair = surfaces;
    if (pair == null) {
      return;
    }
    restoreCelSnapshot(
      coordinator: coordinator,
      frameKey: pair.key,
      snapshot: snapshot,
      cacheInvalidationSink: cacheInvalidationSink,
    );
  }
}

/// A [CelSnapshotStep] that lands as ONE edit of the cel's picture: [edited]
/// reads the picture as it stands when the step lands, the pair is kept, a
/// redo puts its after back and an undo its before. An edit that changes
/// nothing keeps nothing: such a step holds, reads and puts back nothing.
///
/// ↩️A text's edit and a photo's each spelled this out, word for word but for
/// what they edit; a paste's picture on a synced row (F-545) was the third
/// (CLAUDE.md 절대명령 1).
mixin CelPictureEditStep on CelSnapshotStep implements Command {
  BrushFrameKey get frameKey;

  /// [picture] as this edit leaves it — [picture] itself where it changes
  /// nothing.
  BitmapSurface edited(BitmapSurface picture);

  UndoSurfacePair? _surfaces;
  bool _landed = false;

  @override
  UndoSurfacePair? get surfaces => _surfaces;

  @override
  void execute() {
    if (_landed) {
      restoreAfter();
      return;
    }
    _landed = true;
    final before = coordinator.currentSurfaceOf(frameKey);
    final after = edited(before);
    if (identical(after, before)) {
      return;
    }
    coordinator.restoreSurfaceSnapshot(
      frameKey,
      after,
      cacheInvalidationSink: cacheInvalidationSink,
    );
    _surfaces = UndoSurfacePair(
      key: frameKey,
      before: before,
      after: coordinator.currentSurfaceOf(frameKey),
    );
  }

  @override
  void undo() => restoreBefore();
}
