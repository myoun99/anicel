import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_picture_place.dart';
import '../../models/canvas_size.dart';
import '../../models/cut_content_translation.dart'
    show ResizeWalk, laidShiftOf, resizeWalk;
import '../../models/cut_id.dart';
import '../../models/media_asset.dart' show MediaFitMode;
import '../../models/project.dart';
import '../bitmap_surface_geometry.dart' show CelFit, CelTextSetter;
import '../brush_frame_store.dart';
import '../cels_ahead.dart';
import '../command.dart';
import '../guide_geometry.dart' show GuideTransform;
import '../import/raster_cel_import.dart' show celFitted, fitPose;
import '../project_lookup.dart';
import '../project_repository.dart';
import '../undo_surface_snapshot.dart';
import 'link_mirror.dart';

/// Resizes a cut's canvas — and every 겸용 sibling's with it.
///
/// The siblings are not a courtesy: linked cuts share ONE physical cel, so
/// the same bitmap is shown in both. Different canvas sizes would put that
/// one picture in two differently-shaped frames, which was already
/// incoherent before guides existed — guides only made it visible, because
/// an axis stored in canvas coordinates means two different places when the
/// canvases disagree.
class ResizeCutCanvasCommand
    implements
        Command,
        RetainedBytesCommand,
        ParkableCommand,
        PictureRestoringCommand,
        WorksAheadCommand {
  ResizeCutCanvasCommand({
    required this.repository,
    required this.cutId,
    required this.canvasSize,
    this.place = PictureMovedBy.none,
    this.brushFrameStore,
    this.setText,
  });

  final ProjectRepository repository;
  final CutId cutId;
  final CanvasSize canvasSize;

  /// Where the picture goes on the new canvas. Kept to an anchor or moved
  /// by an offset, it is born as it was, nothing in it changed — as every
  /// resize did (🗣️I-180-Q4 메모: 「내용물 변경안하는걸 옵션으로 두고 싶음.
  /// 지금이랑 같은 법인거지」). Fitted (I-180), it stands as an import's
  /// picture would ([fitPose]), and everything that stands on it goes with
  /// it by the same scale.
  ///
  /// ↩️It was an offset beside a fit, the offset read only when the fit
  /// was born — one place now, so a fit cannot carry an offset.
  final CanvasPicturePlace place;

  /// How far the picture moves on [project]'s cut: where the old canvas's
  /// top left lands on the new one ([CanvasPicturePlace.offsetFrom]).
  ({double dx, double dy}) contentOffsetOn(Project project) =>
      place.offsetFrom(requireCut(project, cutId).canvasSize, canvasSize);

  /// When set, the cut's brush strokes are shifted by the offset (the
  /// project model only stores the cut size; stroke data lives in the
  /// app-level brush store).
  final BrushFrameStore? brushFrameStore;

  /// How a fit sets each cel's texts again from their grown numbers
  /// (`celTextsFitted`) — handed in from where letters are laid out. A fit
  /// of a cel with texts and none to set them throws, and is not taken.
  final CelTextSetter? setText;

  Project? _previousProject;
  double _contentDx = 0;
  double _contentDy = 0;
  double _centreDx = 0;
  double _centreDy = 0;

  /// The cuts a resize of [cutId] touches: it and every 겸용 sibling — what
  /// [execute] walks, and what is worked out ahead of it
  /// ([BrushFrameStore.moveCutCelsAhead]).
  static List<CutId> targetsOf(Project project, CutId cutId) => [
    cutId,
    ...linkedCutSiblings(project, cutId: cutId),
  ];

  /// What a fitted [place] carries the cut by on [project] — the walk its
  /// model goes by, and how each cel is laid ([CelFit]) — or null for a
  /// born one, which moves it by its offset as every resize did.
  ///
  /// The picture stands as an import's would on the new canvas ([fitPose]):
  /// the old canvas's centre on the new one's, scaled on each axis by the
  /// fit. A drawing's cels are laid anew by that scale; a reference's file
  /// stays laid 1:1 and moves by whole pixels ([laidShiftOf]), its scale
  /// going into its pose and fx (F-374-Q1).
  ({ResizeWalk walk, CelFit Function(BrushFrameKey key) fitOf})? _fitOn(
    Project project,
  ) {
    final fit = place.fit;
    if (fit == MediaFitMode.born) {
      return null;
    }
    final from = requireCut(project, cutId).canvasSize;
    final pose = fitPose(picture: from, canvas: canvasSize, fit: fit);
    final sx = pose.scaleX;
    final sy = pose.scaleY;
    final dx = pose.center.x - sx * from.width / 2;
    final dy = pose.center.y - sy * from.height / 2;
    // Centred, so the old centre lands on the new one, and that is where
    // the content map takes it too.
    final walk = resizeWalk(
      sx: sx,
      sy: sy,
      dx: dx,
      dy: dy,
      centreDx: dx,
      centreDy: dy,
    );
    final drawn = (
      canvasSize: canvasSize,
      move: GuideTransform(sx, 0, 0, sy, dx, dy),
    );
    return (
      walk: walk,
      fitOf: (key) {
        final reference = layerAnywhereOrNull(
          project,
          key.layerId,
        )?.mediaReference;
        if (reference == null) {
          return drawn;
        }
        final shift = laidShiftOf(reference.laid, walk);
        return (
          canvasSize: canvasSize,
          move: GuideTransform(
            1,
            0,
            0,
            1,
            shift.dx.toDouble(),
            shift.dy.toDouble(),
          ),
        );
      },
    );
  }

  /// Every cel of the cut moved as [execute] moves it — the whole pixels it
  /// rounds its offset to — on the machine's workers
  /// ([BrushFrameStore.moveCutCelsAhead]), or laid as a fit lays it
  /// ([BrushFrameStore.fitCutCelsAhead], which [execute] cannot do without):
  /// the first run's work, and the redo's, which runs the resize again
  /// ([parkPayload]). The undo puts the pictures back by reference and has
  /// none.
  @override
  WorkAhead? workAhead({required bool undo}) {
    final store = brushFrameStore;
    if (undo || store == null) {
      return null;
    }
    return (report) {
      final project = repository.requireProject();
      if (_fitOn(project) case final fitted?) {
        return store.fitCutCelsAhead(
          targetsOf(project, cutId),
          fitted.fitOf,
          lay: (cel, fit) => celFitted(cel, fit, setText: setText),
          report: report,
        );
      }
      final offset = contentOffsetOn(project);
      return store.moveCutCelsAhead(
        targetsOf(project, cutId),
        (
          canvasSize: canvasSize,
          dx: offset.dx.round(),
          dy: offset.dy.round(),
        ),
        report: report,
      );
    };
  }

  /// Every cut this resize touched — the target and its 겸용 siblings.
  /// Undo has to walk the SAME list: the project snapshot restores the
  /// sizes, but the pixel shift lives in the brush store and has to be
  /// reversed cut by cut.
  List<CutId> _targets = const [];
  Map<CutId, Map<BrushFrameKey, UndoSurfaceSnapshot>> _previousBaked = const {};

  /// The undo payload's weight (R19 P3b): after the forward blit the
  /// pre-resize tiles live ONLY in the reference snapshot, so the
  /// history stack's byte-trim must see them — a large cut's resize
  /// used to pin its whole baked set invisibly (adversarial review).
  @override
  /// ⛔[undone] changes nothing here: this holds the PRE-resize surfaces
  /// and nothing else, so there is no other half to name.
  int estimatedRetainedBytes({required bool undone}) {
    var total = 0;
    for (final surfaces in _previousBaked.values) {
      for (final snapshot in surfaces.values) {
        total += snapshot.residentBytes;
      }
    }
    return total;
  }

  /// ⚠️Pre-surfaces only, and that is the whole payload: redo RE-RUNS the
  /// resize rather than restoring a post-surface, so there is no second
  /// end to move.
  @override
  Future<bool> parkPayload() => UndoSurfaceSnapshot.parkAll(_snapshots);

  @override
  void dropPayload() => UndoSurfaceSnapshot.dropAll(_snapshots);

  /// The UNDO half only: a redo re-runs the blit, and what a blit leaves
  /// cannot be read before it runs. The reader is the one [undo] uses, so
  /// the step recognises what this leaned on.
  @override
  void readAhead(CelsAhead cels, {required bool undo}) {
    final store = brushFrameStore;
    if (!undo || store == null) {
      return;
    }
    for (final surfaces in _previousBaked.values) {
      for (final entry in surfaces.entries) {
        cels.readSnapshot(
          entry.key,
          entry.value,
          () => store.bakedSurfaceOrNull(entry.key),
        );
      }
    }
  }

  @override
  void dropReadAhead() {
    for (final snapshot in _snapshots) {
      snapshot.dropReadAhead();
    }
  }

  /// ⛔[undone] changes nothing here, for the reason [estimatedRetainedBytes]
  /// gives: the entry holds the PRE-resize surfaces and nothing else.
  @override
  void visitHeldTiles(HeldTileVisitor visit, {required bool undone}) {
    for (final snapshot in _snapshots) {
      snapshot.visitResidentOwnedTiles(visit);
    }
  }

  Iterable<UndoSurfaceSnapshot> get _snapshots => [
    for (final surfaces in _previousBaked.values) ...surfaces.values,
  ];

  @override
  String get description =>
      'Resize canvas to ${canvasSize.width}x${canvasSize.height}';

  @override
  void execute() {
    final project = repository.requireProject();
    _previousProject = project;

    final fromSize = requireCut(project, cutId).canvasSize;
    // Rounded ONCE, before both consumers: the raster blit can only move
    // whole pixels, and a model moved by the exact .5 of an odd-delta
    // centre anchor would sit half a pixel off the picture forever
    // (adversarial review). The centre's own movement stays exact — it
    // is a model-only quantity (the null-anchor law below).
    final offset = contentOffsetOn(project);
    _contentDx = offset.dx.roundToDouble();
    _contentDy = offset.dy.roundToDouble();
    _centreDx = (canvasSize.width - fromSize.width) / 2;
    _centreDy = (canvasSize.height - fromSize.height) / 2;
    // Before the model moves: a reference's file is moved from where it
    // is laid now ([laidShiftOf]).
    final fitted = _fitOn(project);
    final walk =
        fitted?.walk ??
        resizeWalk(
          dx: _contentDx,
          dy: _contentDy,
          centreDx: _centreDx,
          centreDy: _centreDy,
        );

    _targets = targetsOf(project, cutId);

    // R19 bake-only: the raster blit clips pixels shifted off-canvas, so
    // the exact undo restores the pre-resize baked surfaces by reference
    // (immutable — the snapshot is free).
    final store = brushFrameStore;
    // A fit's pixels were laid ahead, or the step writes nothing.
    if (fitted != null) {
      store?.requireFittedAhead(_targets, fitted.fitOf);
    }
    final previousSurfaces = <CutId, Map<BrushFrameKey, BitmapSurface>>{
      if (store != null)
        for (final target in _targets) target: store.bakedSurfacesForCut(target),
    };

    for (final target in _targets) {
      // ONE model write per cut: the new size plus the content follow —
      // camera keyframes, guides, text anchors and layer transform
      // coordinates move with the picture (D5: the old command moved
      // only the raster, so a resize left every canvas-coordinate model
      // where it was).
      repository.resizeCutCanvasContent(
        cutId: target,
        canvasSize: canvasSize,
        walk: walk,
      );
      // One-pass raster adoption (D5): crop/extend AND anchor offset in
      // a single blit against the NEW canvas, completed HERE for the
      // target and every 겸용 sibling. The widget half's resize path
      // degenerates to pure adoption — no state it depends on (active
      // cut, live selection, a mounted host) can leave a cel behind at
      // the old size any more.
      if (fitted != null) {
        store?.adoptCutCanvasFit(cutId: target, fitOf: fitted.fitOf);
      } else {
        store?.adoptCutCanvasSize(
          cutId: target,
          canvasSize: canvasSize,
          dx: _contentDx,
          dy: _contentDy,
        );
      }
    }

    // 🚨PAIRED WITH THE LIVE SURFACE ONLY NOW, after the blit — the
    // snapshot's honest weight is the tiles the live surfaces no longer
    // hold, and before the blit they hold all of them. The anchored blit
    // allocates fresh buffers (full count); a top-left GROW shares every
    // tile with the live surface (near zero); a shrink retains exactly
    // the clipped ones. Counting the whole snapshot regardless let one
    // large top-left grow evict the entire real undo history with
    // phantom bytes (adversarial review).
    //
    // This command wrote that rule first and the rest of the stack now
    // shares it — [BitmapSurface.keptTilesNotSharedWith] IS this loop,
    // lifted.
    _previousBaked = {
      for (final cut in previousSurfaces.entries)
        cut.key: {
          for (final entry in cut.value.entries)
            entry.key: UndoSurfaceSnapshot(
              key: entry.key,
              snapshot: entry.value,
              sharedWith: store!.hotBakedSurfaceOrNull(entry.key),
            ),
        },
    };
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
        //
        // ⛔A cel whose parked payload will not read back is LEFT OUT
        // rather than restored half-made: the others come back, and the
        // one that did not keeps the pixels it has instead of losing them
        // to a surface with holes in it.
        brushFrameStore?.restoreBakedForCut(target, {
          for (final entry in previousBaked.entries)
            // ⚠️`bakedSurfaceOrNull`, NOT the hot-only reader the measure
            // above uses. That one refuses to materialize on purpose — an
            // accounting question must not pull a cel hot as a side
            // effect — but this is a READ, and a cel that cooled since the
            // resize would answer null there and be silently left out of
            // its own undo.
            entry.key: ?entry.value.surfaceOver(
              () => brushFrameStore?.bakedSurfaceOrNull(entry.key),
            ),
        });
      }
    }
  }
}
