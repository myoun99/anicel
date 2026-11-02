import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/cel_photo.dart';
import '../../models/media_reference.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';
import 'cel_snapshot_step.dart';

/// An edit of the photos a sheet's picture carries (I-97), as one undo
/// step: the picture before and after, its pixels untouched — a photo is a
/// value of the picture (`BitmapSurface.photos`), so the step is the
/// picture on either side ([CelSnapshotStep]). A pool photo put on a sheet
/// ([CelPhotoEditCommand.put]), and the media pool's edits of a sheet it
/// may not have open — the photos of a file taken out of the pool (F-118),
/// or of one found somewhere else.
class CelPhotoEditCommand
    with CelSnapshotStep, CelPictureEditStep
    implements Command {
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
  @override
  final BrushFrameKey frameKey;
  @override
  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  final String description;

  final List<CelPhoto> Function(List<CelPhoto> photos) _photos;

  @override
  BitmapSurface edited(BitmapSurface picture) {
    final photos = _photos(picture.photos);
    return identical(photos, picture.photos)
        ? picture
        : picture.withPhotos(photos);
  }
}
