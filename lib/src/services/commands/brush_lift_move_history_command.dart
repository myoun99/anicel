import '../../models/bitmap_surface.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_frame_key.dart';
import '../brush_frame_editing_coordinator.dart';
import '../canvas_selection_region.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';
import '../undo_retained_bytes.dart';

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
class BrushLiftMoveHistoryCommand implements Command, RetainedBytesCommand {
  BrushLiftMoveHistoryCommand({
    required this.coordinator,
    required this.frameKey,
    required BitmapSurface preLiftSurface,
    required BrushDab stampDab,
    this.cacheInvalidationSink,
    this.regionBefore,
    this.restoreRegion,
    this.readRegion,
  }) : _preSurface = preLiftSurface,
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

  final BitmapSurface _preSurface;

  /// Dropped after the landing — the stamp's RGBA payload is megabytes,
  /// and redo restores the post SURFACE instead (same retention
  /// discipline as BrushStrokeHistoryCommand).
  BrushDab? _stampDab;
  late BitmapSurface _postSurface;
  bool _landed = false;

  /// Zero until the landing, because there is nothing to weigh yet: the
  /// erase is already committed and [_preSurface] still shares every tile
  /// with the live surface. Set once, at the landing, by the one law.
  ///
  /// ⛔It used to be the STAMP rectangle, which is not a thing this
  /// command holds. Measured 2026-09-07: a 64×64 stamp reported 32 KB
  /// against 64 MiB actually retained (2048×), and a null stamp reported
  /// ZERO while holding a full-canvas surface — so the byte budget never
  /// fired on the very entries that killed the app.
  int _retainedBytes = 0;

  @override
  int get estimatedRetainedBytes => _retainedBytes;

  @override
  String get description => 'Move selection';

  @override
  void execute() {
    if (_landed) {
      coordinator.restoreSurfaceSnapshot(
        frameKey,
        _postSurface,
        cacheInvalidationSink: cacheInvalidationSink,
      );
      restoreRegion?.call(_regionAfter);
      return;
    }
    // First execute = the confirm itself: land the floating stamp (the
    // base surface is the post-erase state throughout the session).
    coordinator.commitSourceStroke(
      sourceDabs: [_stampDab!],
      cacheInvalidationSink: cacheInvalidationSink,
    );
    _postSurface = coordinator.currentSurfaceOf(frameKey);
    _retainedBytes = uniquelyRetainedTileBytes(_preSurface, _postSurface);
    _stampDab = null;
    _landed = true;
    // Read AFTER the landing, so a redo restores the shape the confirm
    // actually produced rather than the one it started from.
    _regionAfter = readRegion?.call();
  }

  @override
  void undo() {
    coordinator.restoreSurfaceSnapshot(
      frameKey,
      _preSurface,
      cacheInvalidationSink: cacheInvalidationSink,
    );
    restoreRegion?.call(regionBefore);
  }
}
