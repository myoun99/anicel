import '../../models/brush_frame_key.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../undo_surface_snapshot.dart';

/// Puts a snapshot's picture back on the cel it was taken from — or
/// leaves that cel exactly as it is.
///
/// 🚨★★★**A PAYLOAD THAT WILL NOT COME BACK LEAVES THE PICTURE ALONE.**
/// A parked snapshot answers null when its file is gone or when the cel
/// can no longer supply the tiles it shares, and the shared half on its
/// own is a surface with holes where the drawing was. Painting that over
/// the cel would erase the very drawing the undo step exists to protect,
/// so a refusal is the honest answer: nothing moves, and the user still
/// has their picture.
///
/// ⚠️**[live] IS THE CEL AS IT STANDS**, which is the surface the snapshot
/// was measured against: the stack steps LIFO, so at the moment an entry
/// is undone the cel is its post-surface, and at the moment it is redone
/// the cel is its pre-surface.
///
/// ⛔A stroke and a confirmed move wrote this twice, and after the read
/// gained its [live] argument the two bodies were token-identical — the
/// clone scan said so on the next run. They were the same algorithm well
/// before that; the only difference had been the name of a field.
void restoreCelSnapshot({
  required BrushFrameEditingCoordinator coordinator,
  required BrushFrameKey frameKey,
  required UndoSurfaceSnapshot? snapshot,
  CacheInvalidationSink? cacheInvalidationSink,
}) {
  final surface = snapshot?.surfaceOver(coordinator.currentSurfaceOf(frameKey));
  if (surface == null) {
    return;
  }
  coordinator.restoreSurfaceSnapshot(
    frameKey,
    surface,
    cacheInvalidationSink: cacheInvalidationSink,
  );
}
