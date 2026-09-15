import '../../models/bitmap_surface.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_frame_key.dart';
import '../brush_frame_editing_coordinator.dart';
import '../canvas_selection_region.dart';
import '../cache_invalidation_executor.dart';
import '../cels_ahead.dart';
import '../command.dart';
import '../undo_surface_snapshot.dart';
import 'cel_snapshot_restore.dart';

/// Adopts a CONFIRMED move session (R16-①, TVP-style) into app history
/// as ONE undoable step (R19 P3b surface-snapshot form).
///
/// The session's ERASE was committed raw the moment the move began (the
/// origin must vanish instantly, but nothing is undoable until the user
/// confirms); the stamp floated un-committed through every drag, nudge
/// and Ctrl+T. The first execute LANDS the stamp at its confirmed
/// position and captures the post surface; [preLiftSurface] — captured
/// by the host before the erase — is the undo target. One Ctrl+Z
/// restores the pre-lift picture byte-exactly, session and cache state
/// notwithstanding (the surfaces are self-contained references).
class BrushLiftMoveHistoryCommand
    implements
        Command,
        RetainedBytesCommand,
        ParkableCommand,
        PictureRestoringCommand {
  BrushLiftMoveHistoryCommand({
    required this.coordinator,
    required this.frameKey,
    required BitmapSurface preLiftSurface,
    required BrushDab stampDab,
    this.cacheInvalidationSink,
    this.regionBefore,
    this.restoreRegion,
    this.readRegion,
  }) : _preLiftSurface = preLiftSurface,
       _stampDab = stampDab;

  final BrushFrameEditingCoordinator coordinator;
  final BrushFrameKey frameKey;
  final CacheInvalidationSink? cacheInvalidationSink;

  /// The selection as the SESSION FOUND IT, and the way back to it.
  ///
  /// 🚨★★★UNDO PUTS THE SELECTION BACK TOO. 유저 2026-08-27: 「선택 후
  /// 변형툴 확정하고, 언두하면 그림만 돌리는게아니라 **선택도 이전 선택으로
  /// 되돌리기**. 그에 따라 결과적으로 변형툴ui도 바뀌는게 정상적인 구조겠지」.
  ///
  /// A transform moves two things — the pixels and the outline around them —
  /// and this entry only ever carried the pixels back. So an undo left the
  /// drawing where it started with the selection still wearing the shape the
  /// transform had given it, and the box on screen followed the selection.
  ///
  /// ⛔ONE entry, not two. A separate selection command would mean two
  /// undos for one confirm, and the user asked for one.
  ///
  /// ⚠️A CALLBACK rather than the selection channel itself: that channel
  /// lives in `ui/`, and a command in `services/` may not reach up there
  /// (`layer_dependency_direction_test`). The region type is a service type,
  /// so it travels fine.
  final CanvasSelectionRegion? regionBefore;
  final void Function(CanvasSelectionRegion? region)? restoreRegion;

  /// Reads the live selection — used ONCE, right after the landing.
  final CanvasSelectionRegion? Function()? readRegion;

  /// The shape the confirm left behind — what a REDO has to put back.
  CanvasSelectionRegion? _regionAfter;

  /// The pre-lift picture, held plainly until the landing: there is
  /// nothing to weigh it against yet — the erase is already committed and
  /// this still shares every tile with the live surface — and a snapshot
  /// that cannot name its neighbour cannot say what it owns.
  ///
  /// 🚨★★★**"UNTIL THE LANDING" WAS THE INTENT AND `final` WAS THE BUG.**
  /// It was never released, so a confirmed transform pinned its entire
  /// pre-lift surface for the life of the entry — and [parkPayload] then
  /// encoded those very tiles to disk, dropped the snapshot's references,
  /// reported ZERO, and freed nothing at all, because this field still
  /// held every one of them. The stack's budget saw the number fall and
  /// stopped spilling; the RAM never moved. That is the same defect
  /// [UndoSurfaceSnapshot] fixed one file over for the SHARED tiles, and
  /// here the fraction still pinned was 100%, not 35%.
  ///
  /// ⚠️It is the neighbour of [_stampDab], which is nulled two lines down
  /// with「the stamp's RGBA payload is megabytes」as the reason. This is
  /// the larger of the two.
  BitmapSurface? _preLiftSurface;

  /// Dropped after the landing — the stamp's RGBA payload is megabytes,
  /// and redo restores the post SURFACE instead (same retention
  /// discipline as BrushStrokeHistoryCommand).
  BrushDab? _stampDab;
  UndoSurfacePair? _surfaces;
  bool _landed = false;

  /// Diagnostic for the accumulation regression guard, the same shape
  /// `BrushStrokeHistoryCommand.retainsCommitPayload` is — and the reason
  /// this one exists is that nothing could see the leak from outside: the
  /// bill fell to zero on parking whether or not the picture was released,
  /// so every test stayed green while the RAM never moved.
  bool get retainsPreLiftSurface => _preLiftSurface != null;

  /// Zero until the landing, and then the pre-lift tiles the confirm left
  /// behind — the one law, asked of the snapshot that holds them.
  ///
  /// ⛔It used to be the STAMP rectangle, which is not a thing this
  /// command holds. Measured 2026-09-07: a 64×64 stamp reported 32 KB
  /// against 64 MiB actually retained (2048×), and a null stamp reported
  /// ZERO while holding a full-canvas surface — so the byte budget never
  /// fired on the very entries that killed the app.
  @override
  int estimatedRetainedBytes({required bool undone}) =>
      _surfaces?.residentBytes(undone: undone) ?? 0;

  /// Not landed yet: nothing of its own to move.
  @override
  Future<bool> parkPayload() => _surfaces?.park() ?? Future.value(true);

  @override
  void dropPayload() => _surfaces?.drop();

  /// Not landed yet: nothing to read — see [PictureRestoringCommand].
  @override
  void readAhead(CelsAhead cels, {required bool undo}) => cels.readSnapshot(
    frameKey,
    undo ? _surfaces?.before : _surfaces?.after,
    () => coordinator.currentSurfaceOf(frameKey),
  );

  @override
  void dropReadAhead() => _surfaces?.dropReadAhead();

  @override
  void visitHeldTiles(HeldTileVisitor visit, {required bool undone}) =>
      _surfaces?.visitHeldTiles(visit, undone: undone);

  @override
  String get description => 'Move selection';

  @override
  void execute() {
    if (_landed) {
      _restore(_surfaces?.after);
      restoreRegion?.call(_regionAfter);
      return;
    }
    // First execute = the confirm itself: land the floating stamp (the
    // base surface is the post-erase state throughout the session).
    coordinator.commitSourceStroke(
      sourceDabs: [_stampDab!],
      cacheInvalidationSink: cacheInvalidationSink,
    );
    _surfaces = UndoSurfacePair(
      key: frameKey,
      before: _preLiftSurface!,
      after: coordinator.currentSurfaceOf(frameKey),
    );
    // The pair owns the picture now, and it is the only thing that may:
    // it can weigh it, park it and give it back. Holding a second
    // reference here would make every one of those answers a lie.
    _preLiftSurface = null;
    _stampDab = null;
    _landed = true;
    // Read AFTER the landing, so a redo restores the shape the confirm
    // actually produced rather than the one it started from.
    _regionAfter = readRegion?.call();
  }

  @override
  void undo() {
    _restore(_surfaces?.before);
    restoreRegion?.call(regionBefore);
  }

  /// ⛔A payload that will not come back leaves the PIXELS alone — but the
  /// selection still travels, because the outline is held in memory here
  /// and putting it back is never the destructive half. That asymmetry is
  /// this command's own; the pixel half is [restoreCelSnapshot]'s.
  void _restore(UndoSurfaceSnapshot? snapshot) => restoreCelSnapshot(
    coordinator: coordinator,
    frameKey: frameKey,
    snapshot: snapshot,
    cacheInvalidationSink: cacheInvalidationSink,
  );
}
