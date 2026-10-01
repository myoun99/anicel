import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_cache_invalidation.dart';
import '../../models/brush_frame_key.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/media_reference.dart';
import '../brush_frame_store.dart';
import '../cache_invalidation_executor.dart';
import '../cels_ahead.dart';
import '../command.dart';
import '../import/raster_cel_import.dart' show bakeCelSurface;
import '../project_lookup.dart';
import '../project_repository.dart';
import '../undo_surface_snapshot.dart';

/// I-47 (유저 2026-09-25 · Q1 2026-09-27 「창 없이 바로 바꾼다 (언두 하나)」):
/// a REFERENCE row shows another file. Its reference and the pictures that
/// came from the file change as ONE step, and nothing else about the row
/// does — its name, its transform, its frames.
///
/// A still's cel holds the picture its file was baked into, so the new
/// picture goes into THE SAME CEL (the door bakes [pictures] before this is
/// built) and this keeps the old one for the undo: an [UndoSurfacePair] per
/// cel, the shape a stroke and a confirmed move hold. ⛔Not a new cel:
/// linked cuts share ONE physical cel (`ResizeCutCanvasCommand`), and a new
/// id in the bank would sweep a sibling's exposures of the old one away
/// (`UpdateLayerTimelineCommand`). A movie's one cel holds no pixels — it is
/// decoded as it is shown — so it hands over no pictures, and the reference
/// is all that moves.
///
/// ⚠️Through the STORE, the way an import bakes a cel and a resize restores
/// one — not through the canvas's editing coordinator, which exists only
/// once the canvas has stood on a drawn cel, and a row of references can be
/// all a project has. An editing session follows the store
/// (`BrushFrameEditingCoordinator._storeMovedPast`), so the canvas shows
/// what is written here either way.
class SwapLayerReferenceCommand
    implements
        Command,
        RetainedBytesCommand,
        ParkableCommand,
        PictureRestoringCommand {
  SwapLayerReferenceCommand({
    required this.repository,
    required this.cutId,
    required this.layerId,
    required this.reference,
    required this.store,
    Map<BrushFrameKey, BitmapSurface> pictures = const {},
    this.cacheInvalidationSink,
  }) : _pictures = pictures;

  final ProjectRepository repository;
  final CutId cutId;
  final LayerId layerId;

  /// What the row points at once the swap is done.
  final MediaReference reference;

  /// Where the cels' pictures are.
  final BrushFrameStore store;

  /// Without it the canvas keeps drawing the old picture until the playhead
  /// leaves the frame (`PixelVerbs.runPixelVerb` says so for its verbs).
  final CacheInvalidationSink? cacheInvalidationSink;

  /// The pictures the first execute puts in — let go of once [_surfaces]
  /// holds them.
  Map<BrushFrameKey, BitmapSurface>? _pictures;

  List<UndoSurfacePair> _surfaces = const [];
  MediaReference? _before;

  @override
  String get description => 'Swap layer reference';

  @override
  void execute() {
    final pictures = _pictures;
    if (pictures == null) {
      for (final pair in _surfaces) {
        _restore(pair.after);
      }
    } else {
      _before = requireLayer(
        repository.requireProject(),
        cutId: cutId,
        layerId: layerId,
      ).mediaReference;
      _surfaces = [
        for (final MapEntry(key: key, value: picture) in pictures.entries)
          UndoSurfacePair(
            key: key,
            before:
                store.bakedSurfaceOrNull(key) ??
                BitmapSurface(
                  canvasSize: picture.canvasSize,
                  tileSize: picture.tileSize,
                ),
            after: picture,
          ),
      ];
      _pictures = null;
      pictures.forEach(_put);
    }
    _point(reference);
  }

  @override
  void undo() {
    for (final pair in _surfaces) {
      _restore(pair.before);
    }
    _point(_before);
  }

  void _point(MediaReference? to) => repository.updateLayer(
    layerId: layerId,
    update: (layer) => layer.copyWith(mediaReference: to),
  );

  /// Puts [snapshot]'s picture back — or leaves the cel as it is when a
  /// parked payload will not come back (`restoreCelSnapshot` says why a
  /// surface with holes must not be painted over a drawing).
  void _restore(UndoSurfaceSnapshot snapshot) {
    final surface = snapshot.surfaceOver(store.bakedSurfaceOrNull(snapshot.key));
    if (surface != null) {
      _put(snapshot.key, surface);
    }
  }

  void _put(BrushFrameKey key, BitmapSurface surface) {
    bakeCelSurface(store, key, surface);
    cacheInvalidationSink?.invalidateBrushFrame(
      BrushFrameCacheInvalidation.wholeFrame(key),
    );
  }

  Iterable<UndoSurfaceSnapshot> get _snapshots => [
    for (final pair in _surfaces) ...[pair.before, pair.after],
  ];

  @override
  int estimatedRetainedBytes({required bool undone}) => _surfaces.fold(
    0,
    (sum, pair) => sum + pair.residentBytes(undone: undone),
  );

  @override
  Future<bool> parkPayload() => UndoSurfaceSnapshot.parkAll(_snapshots);

  @override
  void dropPayload() => UndoSurfaceSnapshot.dropAll(_snapshots);

  @override
  void readAhead(CelsAhead cels, {required bool undo}) {
    for (final pair in _surfaces) {
      final key = pair.before.key;
      cels.readSnapshot(
        key,
        undo ? pair.before : pair.after,
        () => store.bakedSurfaceOrNull(key),
      );
    }
  }

  @override
  void dropReadAhead() {
    for (final pair in _surfaces) {
      pair.dropReadAhead();
    }
  }

  @override
  void visitHeldTiles(HeldTileVisitor visit, {required bool undone}) {
    for (final pair in _surfaces) {
      pair.visitHeldTiles(visit, undone: undone);
    }
  }
}
