import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';
import 'cel_snapshot_step.dart';

/// A cel's whole picture replaced as one undo step: [frameKey]'s cel takes
/// [picture], its pixels with their texts and photos, and keeps its id, its
/// name and its blocks — what a paste lays on a synced attach row
/// (`picturesPastedOnSyncedRow`, F-545).
class CelPictureReplaceCommand
    with CelSnapshotStep, CelPictureEditStep
    implements Command {
  CelPictureReplaceCommand({
    required this.coordinator,
    required this.frameKey,
    required this.description,
    required BitmapSurface picture,
    this.cacheInvalidationSink,
  }) : _picture = picture;

  @override
  final BrushFrameEditingCoordinator coordinator;
  @override
  final BrushFrameKey frameKey;
  @override
  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  final String description;

  final BitmapSurface _picture;

  @override
  BitmapSurface edited(BitmapSurface picture) => _picture;
}
