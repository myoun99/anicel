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
class ResizeCutCanvasCommand implements Command {
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

  /// Every cut this resize touched — the target and its 겸용 siblings.
  /// Undo has to walk the SAME list: the project snapshot restores the
  /// sizes, but the pixel shift lives in the brush store and has to be
  /// reversed cut by cut.
  List<CutId> _targets = const [];
  Map<CutId, Map<BrushFrameKey, BitmapSurface>> _previousBaked = const {};

  @override
  String get description =>
      'Resize canvas to ${canvasSize.width}x${canvasSize.height}';

  @override
  void execute() {
    final project = repository.requireProject();
    _previousProject = project;

    final offset = anchor.contentOffset(
      from: requireCut(project, cutId).canvasSize,
      to: canvasSize,
    );
    _contentDx = offset.dx;
    _contentDy = offset.dy;

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
      repository.updateCutCanvasSize(cutId: target, canvasSize: canvasSize);
      store?.translateCutContent(
        cutId: target,
        dx: _contentDx,
        dy: _contentDy,
      );
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
      brushFrameStore?.translateCutContent(
        cutId: target,
        dx: -_contentDx,
        dy: -_contentDy,
      );
      final previousBaked = _previousBaked[target];
      if (previousBaked != null) {
        // Reference restore SUPERSEDES the blit-back above: pixels the
        // forward blit clipped come back exactly.
        brushFrameStore?.restoreBakedForCut(target, previousBaked);
      }
    }
  }
}
