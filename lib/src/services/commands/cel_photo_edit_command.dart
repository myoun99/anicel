import '../../models/brush_frame_key.dart';
import '../../models/cel_photo.dart';
import '../../models/media_reference.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';
import '../undo_surface_snapshot.dart';
import 'cel_snapshot_step.dart';

/// A pool photo put on a sheet's ink (I-97), as one undo step: the photos
/// of the picture it lands on with it on top, the picture's pixels
/// untouched — a photo is a value of the picture (`BitmapSurface.photos`),
/// so the step is the picture before and after ([CelSnapshotStep]).
///
/// ⚠️THE SECOND OF ITS KIND: `CelTextEditCommand` lands an edit of a
/// picture's own values the same way — read as the picture stands when the
/// step lands, the pair kept. Not shared under the rule of three (CLAUDE.md
/// 절대명령 1): a third merges them.
class CelPhotoEditCommand with CelSnapshotStep implements Command {
  CelPhotoEditCommand.put({
    required this.coordinator,
    required this.frameKey,
    required MediaReference reference,
    this.cacheInvalidationSink,
  }) : _reference = reference;

  /// A photo put on a sheet — and the one step a drop folds into.
  static const String label = 'Place photo';

  @override
  final BrushFrameEditingCoordinator coordinator;
  final BrushFrameKey frameKey;
  @override
  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  String get description => label;

  /// The pool file, and where the photo stands on the picture.
  final MediaReference _reference;

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
    final photos = before.photos;
    coordinator.restoreSurfaceSnapshot(
      frameKey,
      before.withPhotos([
        ...photos,
        CelPhoto(id: nextCelPhotoId(photos), reference: _reference),
      ]),
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
