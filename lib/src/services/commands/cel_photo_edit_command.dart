import '../../models/brush_frame_key.dart';
import '../../models/cel_photo.dart';
import '../../models/media_reference.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';
import '../undo_surface_snapshot.dart';
import 'cel_snapshot_step.dart';

/// An edit of the photos a sheet's picture carries (I-97), as one undo
/// step: the picture before and after, its pixels untouched — a photo is a
/// value of the picture (`BitmapSurface.photos`), so the step is the
/// picture on either side ([CelSnapshotStep]). A pool photo put on a sheet
/// ([CelPhotoEditCommand.put]), and the media pool's edits of a sheet it
/// may not have open — the photos of a file taken out of the pool (F-118),
/// or of one found somewhere else.
///
/// ⚠️THE SECOND OF ITS KIND: `CelTextEditCommand` lands an edit of a
/// picture's own values the same way — read as the picture stands when the
/// step lands, the pair kept. Not shared under the rule of three (CLAUDE.md
/// 절대명령 1): a third merges them.
class CelPhotoEditCommand with CelSnapshotStep implements Command {
  /// [photos] made of the photos [frameKey]'s picture carries as the step
  /// lands — the picture as it is then, not as it was when this was built.
  CelPhotoEditCommand({
    required this.coordinator,
    required this.frameKey,
    required this.description,
    required List<CelPhoto> Function(List<CelPhoto> photos) photos,
    this.cacheInvalidationSink,
  }) : _photos = photos;

  /// A pool photo put on top of the picture's, under an id one past the
  /// largest there.
  CelPhotoEditCommand.put({
    required BrushFrameEditingCoordinator coordinator,
    required BrushFrameKey frameKey,
    required MediaReference reference,
    CacheInvalidationSink? cacheInvalidationSink,
  }) : this(
         coordinator: coordinator,
         frameKey: frameKey,
         description: label,
         photos: (photos) => [
           ...photos,
           CelPhoto(id: nextCelPhotoId(photos), reference: reference),
         ],
         cacheInvalidationSink: cacheInvalidationSink,
       );

  /// A photo put on a sheet — and the one step a drop folds into.
  static const String label = 'Place photo';

  @override
  final BrushFrameEditingCoordinator coordinator;
  final BrushFrameKey frameKey;
  @override
  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  final String description;

  final List<CelPhoto> Function(List<CelPhoto> photos) _photos;

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
    final photos = _photos(before.photos);
    if (identical(photos, before.photos)) {
      // Nothing to keep: a step that changed nothing holds nothing.
      return;
    }
    coordinator.restoreSurfaceSnapshot(
      frameKey,
      before.withPhotos(photos),
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
