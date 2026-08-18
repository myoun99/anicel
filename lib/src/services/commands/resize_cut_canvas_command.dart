import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_resize_anchor.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_id.dart';
import '../../models/project.dart';
import '../brush_frame_store.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'link_mirror.dart';

/// Resizes a cut's canvas — and every 겸용 sibling's with it.
///
/// The siblings are not a courtesy: linked cuts share ONE physical cel, so
/// the same bitmap is shown in both. Different canvas sizes would put that
/// one picture in two differently-shaped frames, which was already
/// incoherent before guides existed — guides only made it visible, because
/// an axis stored in canvas coordinates means two different places when the
/// canvases disagree.
class ResizeCutCanvasCommand implements Command, RetainedBytesCommand {
  ResizeCutCanvasCommand({
    required this.repository,
    required this.cutId,
    required this.canvasSize,
    this.anchor = CanvasResizeAnchor.topLeft,
    this.brushFrameStore,
  });

  final ProjectRepository repository;
  final CutId cutId;
  final CanvasSize canvasSize;
  final CanvasResizeAnchor anchor;

  /// When set, the cut's brush strokes are shifted so the artwork stays
  /// pinned to [anchor] (the project model only stores the cut size; stroke
  /// data lives in the app-level brush store).
  final BrushFrameStore? brushFrameStore;

  Project? _previousProject;
  double _contentDx = 0;
  double _contentDy = 0;
  double _centreDx = 0;
  double _centreDy = 0;

  /// Every cut this resize touched — the target and its 겸용 siblings.
  /// Undo has to walk the SAME list: the project snapshot restores the
  /// sizes, but the pixel shift lives in the brush store and has to be
  /// reversed cut by cut.
  List<CutId> _targets = const [];
  Map<CutId, Map<BrushFrameKey, BitmapSurface>> _previousBaked = const {};
  int _retainedBytes = 0;

  /// The undo payload's weight (R19 P3b): after the forward blit the
  /// pre-resize tiles live ONLY in the reference snapshot, so the
  /// history stack's byte-trim must see them — a large cut's resize
  /// used to pin its whole baked set invisibly (adversarial review).
  @override
  int get estimatedRetainedBytes => _retainedBytes;

  @override
  String get description =>
      'Resize canvas to ${canvasSize.width}x${canvasSize.height}';

  @override
  void execute() {
    final project = repository.requireProject();
    _previousProject = project;

    final fromSize = requireCut(project, cutId).canvasSize;
    final offset = anchor.contentOffset(from: fromSize, to: canvasSize);
    // Rounded ONCE, before both consumers: the raster blit can only move
    // whole pixels, and a model moved by the exact .5 of an odd-delta
    // centre anchor would sit half a pixel off the picture forever
    // (adversarial review). The centre's own movement stays exact — it
    // is a model-only quantity (the null-anchor law below).
    _contentDx = offset.dx.roundToDouble();
    _contentDy = offset.dy.roundToDouble();
    _centreDx = (canvasSize.width - fromSize.width) / 2;
    _centreDy = (canvasSize.height - fromSize.height) / 2;

    _targets = [cutId, ...linkedCutSiblings(project, cutId: cutId)];

    // R19 bake-only: the raster blit clips pixels shifted off-canvas, so
    // the exact undo restores the pre-resize baked surfaces by reference
    // (immutable — the snapshot is free).
    final store = brushFrameStore;
    if (store != null) {
      _previousBaked = {
        for (final target in _targets) target: store.bakedSurfacesForCut(target),
      };
    }

    for (final target in _targets) {
      // ONE model write per cut: the new size plus the content follow —
      // camera keyframes, guides, text anchors and layer transform
      // coordinates move with the picture (D5: the old command moved
      // only the raster, so a resize left every canvas-coordinate model
      // where it was).
      repository.resizeCutCanvasContent(
        cutId: target,
        canvasSize: canvasSize,
        dx: _contentDx,
        dy: _contentDy,
        centreDx: _centreDx,
        centreDy: _centreDy,
      );
      // One-pass raster adoption (D5): crop/extend AND anchor offset in
      // a single blit against the NEW canvas, completed HERE for the
      // target and every 겸용 sibling. The widget half's resize path
      // degenerates to pure adoption — no state it depends on (active
      // cut, live selection, a mounted host) can leave a cel behind at
      // the old size any more.
      store?.adoptCutCanvasSize(
        cutId: target,
        canvasSize: canvasSize,
        dx: _contentDx,
        dy: _contentDy,
      );
    }

    // The undo payload's HONEST weight: only tiles the live surfaces no
    // longer hold are uniquely retained by the snapshot. The anchored
    // blit allocates fresh buffers (full count); a top-left GROW shares
    // every tile with the live surface (near zero); a shrink retains
    // exactly the clipped ones. Counting the whole snapshot regardless
    // let one large top-left grow evict the entire real undo history
    // with phantom bytes (adversarial review).
    _retainedBytes = 0;
    if (store != null) {
      for (final surfaces in _previousBaked.values) {
        for (final entry in surfaces.entries) {
          final live = store.hotBakedSurfaceOrNull(entry.key);
          final liveTiles = Set<Object>.identity();
          if (live != null) {
            liveTiles.addAll(live.tiles.values);
          }
          for (final tile in entry.value.tiles.values) {
            if (!liveTiles.contains(tile)) {
              _retainedBytes +=
                  entry.value.tileSize * entry.value.tileSize * 4;
            }
          }
        }
      }
    }
  }

  @override
  void undo() {
    final previousProject = _previousProject;
    if (previousProject == null) {
      throw StateError('Command has not been executed.');
    }

    repository.replaceProject(previousProject);
    for (final target in _targets) {
      final previousBaked = _previousBaked[target];
      if (previousBaked != null) {
        // Reference restore alone: the snapshot carries the exact
        // pre-resize surfaces, old canvas size included (the model was
        // restored whole above), so pixels the forward blit clipped
        // come back exactly — a reverse blit would only be overwritten.
        brushFrameStore?.restoreBakedForCut(target, previousBaked);
      }
    }
  }
}
