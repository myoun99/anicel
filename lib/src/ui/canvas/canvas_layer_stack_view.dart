import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/collection_equality.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/playback_quality.dart';
import '../../models/project_background.dart';
import '../../models/transform_track.dart';
import '../../models/tile_coord.dart';
import '../debug/input_inspector.dart';
import '../debug/measurement_mode.dart';
import '../../core/dev_profile.dart';
import '../playback/layer_frame_image_cache.dart';
import 'active_layer_flat_projection.dart';
import 'bitmap_surface_painter.dart';
import '../../services/layer_pose_paint.dart';
import 'tiled_surface_compose.dart';
import 'bitmap_tile_image_cache.dart';
import '../../services/composite_effect_paint.dart';
import 'deferred_image_disposal.dart';
import 'display_buffer_cache.dart';
import 'display_resample.dart';
import 'selection_float_overlay.dart';
import 'subtree_image_composite.dart';
import 'static_composite_bake.dart';
import 'layer_image_draw.dart';
import 'paper_background.dart';
import 'viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import '../../services/cel_source_effect_pass.dart';

part 'layer_stack/layer_stack_paint_pass.dart';

/// One node of the editing canvas's composite tree.
///
/// The stack used to be two FLAT lists — below the active layer and above
/// it — painted by two sibling widgets with the interactive view between
/// them. A folder composites into one offscreen — a `ui.Image` its own walk
/// rasters — and one offscreen cannot span three sibling painters, so
/// drawing inside a blended folder could never match playback. The tree (with the ACTIVE layer as a node
/// of its own, [CanvasActiveLayerNode]) is what lets one painter close the
/// buffer it opened.
sealed class CanvasLayerStackNode {
  const CanvasLayerStackNode();
}

/// A cached layer image.
final class CanvasLayerImageNode extends CanvasLayerStackNode {
  const CanvasLayerImageNode(this.request);

  final CanvasLayerImageRequest request;
}

/// The ACTIVE layer's live surface — the one the brush is drawing into.
/// The painter delegates to the surface painter here, in place, so the
/// stroke lands inside whatever group buffer encloses it.
final class CanvasActiveLayerNode extends CanvasLayerStackNode {
  const CanvasActiveLayerNode({
    required this.opacity,
    this.frameKey,
    this.blendMode = LayerBlendMode.normal,
    this.pose,
    this.anchorPoint,
    this.effects = const [],
  });

  /// The active row's CEL — the same key its cached twin
  /// [CanvasLayerImageRequest.frameKey] carried the frame before this row
  /// became active. Null when the row has nothing exposed here (nothing to
  /// stand in for).
  ///
  /// This is what lets the stack keep the just-deactivated route's layer
  /// image as the FIRST-ACTIVATION stand-in: activation promotes a
  /// file-backed cel to a surface of all-fresh tile objects, the tile
  /// image cache has no images for them, and the sync/pixel budgets leave
  /// the rest of the cel SILENT for one frame. The held image is truth
  /// pixels for exactly this cel, so drawing it while zero decoded tile
  /// images exist closes the one-frame blank without a seam.
  final BrushFrameKey? frameKey;

  /// The active row's effective opacity (the interactive view used to
  /// apply this itself, through the panel's content-opacity wrap).
  final double opacity;

  /// The active row's composite blend — the SAME field its cached twin
  /// [CanvasLayerImageRequest.blendMode] carries, because being the row you
  /// are drawing on is not a reason to composite differently.
  ///
  /// 🚨It was missing entirely until now, which is ㊱'s shape one field over:
  /// the value never reached the painter because there was nowhere to put
  /// it, so a multiply row went back to srcOver the moment you stood on it
  /// and the editing canvas disagreed with playback about the same frame.
  final LayerBlendMode blendMode;

  final TransformPose? pose;
  final CanvasPoint? anchorPoint;

  /// The active row's effect chain (R6) — the layer you are DRAWING on
  /// shows its own effects, so a stroke lands in the picture you can see.
  /// A blur wraps the live surface in its own buffer for exactly as long as
  /// the effect is there.
  ///
  /// ★WHOLE on purpose, like [CanvasLayerImageRequest.effects]: the stack's
  /// `shouldRepaint` diffs this field, and splitting at construction would
  /// let a colour-key edit slip past that comparison. The halves are taken
  /// at USE, below.
  final List<ResolvedLayerEffect> effects;

  /// The PAINT half — everything the composite applies. The CPU half (the
  /// LEADING colour keys) is already on the surface: the session runs the
  /// same split and feeds `activeSourceEffects` with the other half.
  ///
  /// ⛔THE WHOLE CHAIN CANNOT GO TO THE PAINT, and this row was the last one
  /// handing it over. A leading key then ran TWICE — once on the cel bytes
  /// and again as a shader over the assembled picture. 🧪Delete and Keep are
  /// idempotent at Amount 100, which is exactly why it hid; at any lower
  /// Amount the two applications compound.
  List<ResolvedLayerEffect> get paintEffects => splitSourceEffects(effects).paint;
}

/// A FOLDER's group buffer: [children] compose into one buffer, then the
/// folder's opacity/blend land on it once (R27 #29).
final class CanvasLayerGroupNode extends CanvasLayerStackNode {
  const CanvasLayerGroupNode({
    required this.children,
    required this.opacity,
    required this.blendMode,
    this.effects = const [],
  });

  final List<CanvasLayerStackNode> children;
  final double opacity;
  final LayerBlendMode blendMode;

  /// The folder's effect chain (R6), applied once to the group buffer.
  final List<ResolvedLayerEffect> effects;
}

/// An ADJUSTMENT row's SCOPE (R6b): [children] compose into one buffer and
/// the row's [effects] filter it there — so a stroke drawn on a layer below
/// an adjustment reads through the grade while you draw it.
final class CanvasLayerAdjustmentNode extends CanvasLayerStackNode {
  const CanvasLayerAdjustmentNode({
    required this.children,
    required this.effects,
    required this.mix,
  });

  final List<CanvasLayerStackNode> children;
  final List<ResolvedLayerEffect> effects;

  /// The effect MIX (the row's opacity), 0…1.
  final double mix;
}

/// One non-active layer to composite around the interactive canvas.
class CanvasLayerImageRequest {
  const CanvasLayerImageRequest({
    required this.frameKey,
    required this.opacity,
    this.blendMode = LayerBlendMode.normal,
    this.pose,
    this.anchorPoint,
    this.tint,
    this.effects = const [],
  });

  final BrushFrameKey frameKey;

  /// EFFECTIVE opacity (static × animated Opacity sample).
  final double opacity;

  /// The layer's composite blend (R26 #30) — the editing stack paints it
  /// exactly like the composite routes.
  final LayerBlendMode blendMode;

  /// The layer's transform at the shown frame; null = identity. The stack
  /// paints it exactly like the composite routes — the ACTIVE layer shows
  /// its pose too, through the interactive view's draw-through wrap.
  final TransformPose? pose;

  /// The pose's anchor point; null = canvas center.
  final CanvasPoint? anchorPoint;

  /// ARGB tint MULTIPLIED over the artwork's colors (onion-skin Colors
  /// mode); null paints the artwork as-is.
  final int? tint;

  /// The row's effect chain (R6). Onion GHOSTS deliberately carry none:
  /// they are editing scaffolding, and the Colors-mode tint already owns
  /// this paint's colorFilter slot.
  ///
  /// ⛔THE WHOLE CHAIN, both halves. The two `shouldRepaint` comparisons
  /// diff this field, so splitting it here would let a color-key edit slip
  /// past them. The halves are taken at USE instead, below.
  final List<ResolvedLayerEffect> effects;

  /// The CPU half — the color keys, which the image cache bakes into the
  /// image it hands back rather than the paint applying them.
  ///
  /// ★This request names a cel by [frameKey] and has no surface of its own,
  /// which is why the split lives here as a getter while
  /// `CutFrameCompositeLayer` (which DOES carry a surface) applies the pass
  /// in its constructor. Same function underneath, two shapes because the
  /// two routes hold different things.
  List<ResolvedLayerEffect> get sourceEffects =>
      splitSourceEffects(effects).source;

  /// The paint half — everything that folds into a color filter or an image
  /// filter.
  List<ResolvedLayerEffect> get paintEffects => splitSourceEffects(effects).paint;
}

/// Paints the editing canvas's whole composite tree from the layer-frame
/// image cache, under the panel viewport transform — the ACTIVE layer
/// included, drawn in place through [activeSurfacePainter].
///
/// This is what makes the layers visible while editing, and (since the
/// merge) what lets a folder's group buffer wrap the layer you are drawing
/// on: one painter opens the `saveLayer` and closes it.
/// Paint-only: input always passes through to the canvas below.
class CanvasLayerStackView extends StatefulWidget {
  const CanvasLayerStackView({
    super.key,
    required this.nodes,
    required this.imageCache,
    required this.canvasSize,
    required this.viewport,
    this.activeSurfacePainter,
    this.floatOverlay,
    this.paintPaper = false,
    this.paperBackground = ProjectBackground.defaultBackground,
    this.debugDisableBake = false,
    this.debugDisableSingleBuffer = false,
    this.debugBufferCache,
  });

  /// 🚨A cache the TEST owns, so it can read how each frame was built.
  /// An optimisation that never runs looks exactly like one that works —
  /// this session shipped two that did not — so the counters are part of
  /// the contract rather than a debugging aid.
  @visibleForTesting
  final DisplayBufferCache? debugBufferCache;

  /// 🚨(v) 2단계 — turns the single composite buffer OFF, so a test can
  /// render the SAME tree both ways and compare the pixels.
  ///
  /// ⚠️The comparison is only an identity at 1:1. That is not a weakness of
  /// the test, it is the change: above and below 100% the buffer resamples
  /// ONCE where the direct walk resampled every layer separately, and the
  /// pixels are supposed to differ there. So parity pins the composite —
  /// order, blending, paper, pasteboard — and a separate test pins the
  /// sampling law.
  @visibleForTesting
  final bool debugDisableSingleBuffer;

  /// 🚨(v) — turns the static bake OFF so a test can render the SAME tree
  /// both ways and compare the pixels.
  ///
  /// ★That comparison is the only contract worth having here: an
  /// optimisation is allowed to be faster, never to draw something else.
  /// It is a field rather than a global so the two renders can sit in one
  /// test, side by side, with nothing global to reset between them.
  @visibleForTesting
  final bool debugDisableBake;

  /// The selection's floating pixels (TS1), drawn in the active layer's slot
  /// so the rows above it occlude them. Null = nothing to draw there.
  final SelectionFloatOverlay? floatOverlay;

  /// The composite tree, bottom → top.
  final List<CanvasLayerStackNode> nodes;

  /// Draws the ACTIVE layer's live surface wherever a
  /// [CanvasActiveLayerNode] sits in [nodes]; null paints nothing there
  /// (hosts that still mount their own interactive view).
  final BitmapSurfacePainter? activeSurfacePainter;

  /// Every cached-image request under [nodes], depth-first bottom → top.
  Iterable<CanvasLayerImageRequest> get layers sync* {
    Iterable<CanvasLayerImageRequest> walk(
      List<CanvasLayerStackNode> list,
    ) sync* {
      for (final node in list) {
        switch (node) {
          case CanvasLayerImageNode(:final request):
            yield request;
          case CanvasLayerGroupNode(:final children):
            yield* walk(children);
          case CanvasLayerAdjustmentNode(:final children):
            yield* walk(children);
          case CanvasActiveLayerNode():
            break;
        }
      }
    }

    yield* walk(nodes);
  }

  final LayerFrameImageCache imageCache;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;

  /// The below-stack paints the paper so the interactive view can skip its
  /// own opaque background.
  final bool paintPaper;

  /// The project background the paper paints with (R10-⑥) — solid color
  /// or the transparent checkerboard.
  final ProjectBackground paperBackground;

  @override
  State<CanvasLayerStackView> createState() => _CanvasLayerStackViewState();
}

class _CanvasLayerStackViewState extends State<CanvasLayerStackView> {
  /// Cache image identity → our clone (+ the canvas-space rect the image
  /// covers — grown past the canvas when the cel has pasteboard tiles).
  /// Clones survive cache eviction (the cache may dispose its image at any
  /// time; a clone shares pixels with an independent lifetime).
  final Map<
    BrushFrameKey,
    ({ui.Image source, ui.Image clone, Rect worldRect, int? revision})
  >
  _images = {};
  bool _preparing = false;
  bool _rerunRequested = false;

  /// Cels whose image could not be built, and the revision it failed at.
  ///
  /// Skipping the failure but FORGETTING it re-kicked the same broken
  /// build on every rebuild — for a file-backed cel whose bytes are
  /// unreachable that is a blocking open + throw per layer per sweep,
  /// which is a hot loop on an old tablet where master paid it once and
  /// then stopped drawing. The next CONTENT change (a new revision)
  /// retries; the failure itself is reported rather than swallowed. Same
  /// shape as the storyboard thumbnail store's, for the same reason.
  /// ⚠️A NULLABLE value on purpose. A cel can fail before it has any
  /// frame state at all, and recording nothing then would leave the retry
  /// exactly as hot as it was: `null == null` keeps it skipped, and the
  /// moment a revision appears the mismatch retries it.
  final Map<BrushFrameKey, (int, int?)> _failedRevisions = {};

  /// The cel revision a held image was captured at.
  ///
  /// ⛔It rides INSIDE the held record rather than in a map beside it. A
  /// second map would need clearing at all four `_dropImage` call sites, and
  /// 「지우는 곳을 하나 더 추가」 is not a fix — the two would drift the first
  /// time someone added a fifth.
  int? _revisionOf(BrushFrameKey key) =>
      widget.imageCache.frameStore.frameOrNull(key)?.sourceRevision;

  /// What a failure is recorded AGAINST: the store's whole-content
  /// generation, then the cel's own revision.
  ///
  /// ⚠️The generation is not decoration. A cel the FILESYSTEM refused
  /// does not change when the file comes back, so keying a non-content
  /// failure on a content revision alone would have left that row blank
  /// for ever with nothing the user could do. The generation bumps on a
  /// project OPEN — the one moment such a cel can plausibly have become
  /// readable — so reopening is a real recovery instead of a ritual.
  (int, int?) _failureKeyFor(BrushFrameKey key) => (
    widget.imageCache.frameStore.celContentRevision.value,
    widget.imageCache.frameStore.frameOrNull(key)?.sourceRevision,
  );

  bool _shouldSkipFailed(BrushFrameKey key) =>
      _failedRevisions.containsKey(key) &&
      _failedRevisions[key] == _failureKeyFor(key);

  void _noteFailure(
    BrushFrameKey key,
    Object error,
    StackTrace stack,
    String where,
  ) {
    _failedRevisions[key] = _failureKeyFor(key);
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'canvas layer stack',
        context: ErrorDescription(
          'building the layer image for cel ${key.frameId.value} ($where)',
        ),
      ),
    );
  }

  /// The FIRST-ACTIVATION stand-in (device report 2026-08-17): activation
  /// promotes a file-backed cel to a surface of all-fresh tile objects,
  /// [BitmapTileImageCache] keys images by tile identity so it has none of
  /// them, and the sync-upload/per-pixel budgets leave everything else
  /// SILENT — the picture disappeared for one frame per layer. The image
  /// this stack held for that very cel the frame before (the
  /// [CanvasLayerImageNode] route) is truth pixels for it, so the active
  /// slot draws it until EVERY tile's decode has landed — and dies the
  /// instant an edit could exist (overlay activity, a new surface
  /// instance; see [_ActiveLayerStandIn.shouldStandInFor]).
  _ActiveLayerStandIn? _activeStandIn;

  @override
  void initState() {
    super.initState();
    _syncActiveStandIn();
    _syncImagesWithCache();
    unawaited(_ensureImages());
  }

  @override
  void didUpdateWidget(covariant CanvasLayerStackView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A6: the pins live on the CACHE, so a swapped cache MOVES them —
    // released where they were taken (releasing on the new one would be
    // an unbalanced release of pins it never saw), retained on the cache
    // every later [_dropImage] will release against. The clones stay:
    // they outlive their source by design, and dropping them here would
    // blank every layer until the new cache decodes. ⛔No revision bump —
    // the picture did not change, and a bump here turned every cache
    // swap into a full recompose (measured: the stroke-patch contract
    // went to zero on a fixture with no images at all).
    if (!identical(oldWidget.imageCache, widget.imageCache)) {
      for (final key in _images.keys) {
        oldWidget.imageCache.releasePin(key, PlaybackQuality.full);
        widget.imageCache.retainPin(key, PlaybackQuality.full);
      }
    }
    // ⛔BEFORE the sweep: arming borrows the image the just-activated
    // layer held on the previous frame, and the sweep is exactly what
    // would drop it (the activated layer leaves the request set).
    _syncActiveStandIn();
    _syncImagesWithCache();
    unawaited(_ensureImages());
  }

  /// Arms the stand-in on the activation frame, keeps it while its window
  /// is open, and drops it the build after it dies.
  ///
  /// Arming asks the promoted surface itself: a stand-in exists only when
  /// ZERO of the surface's committed tiles have any picture yet — which is
  /// precisely the first-activation swap frame. A hot re-activation (tile
  /// objects still hold their decoded images) or an edited cel (commit
  /// adoption gave its tiles pictures) never arms.
  void _syncActiveStandIn() {
    final painter = widget.activeSurfacePainter;
    final key = _activeNodeFrameKey(widget.nodes);
    final current = _activeStandIn;
    if (current != null) {
      if (painter != null &&
          key == current.frameKey &&
          identical(painter.surface, current.surface) &&
          current.isLive) {
        return; // The same swap window, still open.
      }
      _activeStandIn = null;
    }
    if (painter == null || key == null) {
      return;
    }
    final held = _images[key];
    if (held == null) {
      return;
    }
    final surface = painter.surface;
    if (surface.tiles.isEmpty) {
      return;
    }
    // ⛔Captured ONCE: the surface is immutable, and `surface.tiles` is a
    // defensive whole-map copy per read — per-paint reads of it are the
    // measured 82.7ms cliff the painter's own walk had to leave behind.
    final tiles = List<BitmapTile>.of(surface.tiles.values);
    final tileImages = painter.tileImageCache;
    for (final tile in tiles) {
      if (tileImages.displayImageFor(tile) != null) {
        // Some picture already exists: not the first-activation frame.
        return;
      }
    }
    _activeStandIn = _ActiveLayerStandIn(
      frameKey: key,
      image: held.clone,
      worldRect: held.worldRect,
      surface: surface,
      tiles: tiles,
      tileImages: tileImages,
    );
  }

  /// The active node's cel key, wherever the node sits in the tree.
  static BrushFrameKey? _activeNodeFrameKey(List<CanvasLayerStackNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case CanvasActiveLayerNode(:final frameKey):
          return frameKey;
        case CanvasLayerGroupNode(:final children):
        case CanvasLayerAdjustmentNode(:final children):
          final inner = _activeNodeFrameKey(children);
          if (inner != null) {
            return inner;
          }
        case CanvasLayerImageNode():
          break;
      }
    }
    return null;
  }

  /// 🚨(v) — the recording of everything a stroke cannot change.
  final StaticCompositeBake _bake = StaticCompositeBake();
  late final DisplayBufferCache _bufferCache =
      widget.debugBufferCache ?? DisplayBufferCache();

  /// The bake, for tests that pin WHICH mechanism held the backdrop —
  /// a picture and a raster paint the same pixels by design (S7), so
  /// only the slot counters can say the predicate chose.
  @visibleForTesting
  StaticCompositeBake get debugBake => _bake;

  /// The bake key's own input, opened for the guard on [_holdImage].
  ///
  /// ⚠️A hatch rather than a bake assertion: the kept composite only records
  /// slots under a real paint pipeline, so a test that reached for
  /// `slotCount` would be measuring whether its own synthetic paint recorded
  /// anything — which is the instrument, not the law.
  @visibleForTesting
  int get debugImagesRevision => _imagesRevision;

  /// 🚨★★★ Bumped at EVERY `_images` mutation, and read into the bake's key.
  ///
  /// ⛔This is not belt-and-braces on top of the tree comparison. A recorded
  /// picture holds references to the `ui.Image` clones below, and those get
  /// `dispose()`d right here — replaying a picture after that is a dead
  /// handle. The tree comparison happens on the PAINTER's schedule and the
  /// dispose happens on the STATE's, so the two run at different moments;
  /// tying invalidation to the dispose ITSELF is what makes the window
  /// impossible rather than merely unlikely.
  int _imagesRevision = 0;

  void _dropImage(
    BrushFrameKey key,
    ({ui.Image source, ui.Image clone, Rect worldRect, int? revision}) held,
  ) {
    // A6: the pin travels with the clone — held pixels are declared
    // pixels, and the declaration ends exactly when the hold does.
    widget.imageCache.releasePin(key, PlaybackQuality.full);
    held.clone.dispose();
    _imagesRevision += 1;
  }

  /// The ONLY way an image enters [_images] — [_dropImage]'s twin.
  ///
  /// 🚨★★★The note on [_imagesRevision] says it moves at EVERY mutation, and
  /// it did not: a COLD adopt (nothing held yet) assigned straight into the
  /// map, so the bake's key was unchanged and the kept composite replayed
  /// without the layer that had just arrived. A drop bumped it and an adopt
  /// did not, which is the asymmetry that let a stale picture survive around
  /// a live one — 유저 2026-08-27, iPhone: 「**변형툴의 외곽에만** 그림이
  /// 남음 … 보기에만 그[렇다]」. The active layer paints live and the rest
  /// comes from the bake, so a stale bake shows up exactly as a ring of old
  /// drawing around a correct one.
  ///
  /// ⛔Assigning to `_images` anywhere else puts the hole back. Both are
  /// methods so that the map and its revision cannot be moved apart.
  void _holdImage(
    BrushFrameKey key,
    ({ui.Image source, ui.Image clone, Rect worldRect, int? revision}) held,
  ) {
    _images[key] = held;
    _imagesRevision += 1;
  }

  @override
  void dispose() {
    for (final entry in _images.entries) {
      widget.imageCache.releasePin(entry.key, PlaybackQuality.full);
      entry.value.clone.dispose();
    }
    _images.clear();
    _bake.dispose();
    _bufferCache.dispose();
    super.dispose();
  }

  /// Synchronous sweep BEFORE this frame's build: adopt every requested
  /// layer whose image is already valid in the cache and drop layers that
  /// left the request set.
  ///
  /// This is what keeps a layer switch flicker-free — the just-deactivated
  /// layer arrives here with a warm cache image (the prerender re-warms it
  /// after every stroke), and the async pass alone would paint it one frame
  /// late at best: the artwork visibly vanished and reappeared. The
  /// just-activated layer leaves the same frame, so it never double-draws
  /// under the interactive view.
  void _syncImagesWithCache() {
    labProbe('layerStackSyncSweep(${widget.layers.length})', _syncSweepBody);
  }

  /// Holds [image] for [key] unless it is the one already held — the pin,
  /// the clone and the revision together — and says whether the held set
  /// changed. The sync sweep and the async pass both adopt through here.
  bool _adoptImage(BrushFrameKey key, LayerFrameImage image, int? revision) {
    final held = _images[key];
    if (held != null && identical(held.source, image.image)) {
      return false;
    }
    if (held != null) _dropImage(key, held);
    widget.imageCache.retainPin(key, PlaybackQuality.full);
    _holdImage(key, (
      source: image.image,
      clone: image.image.clone(),
      worldRect: image.worldRect,
      revision: revision,
    ));
    return true;
  }

  void _syncSweepBody() {
    final wanted = <BrushFrameKey>{
      for (final layer in widget.layers) layer.frameKey,
      // The stand-in borrows the just-activated layer's held image, whose
      // request left the set on this very frame — hold it while the swap
      // window is open, or the sweep disposes the one truth the active
      // slot can draw.
      ?_activeStandIn?.frameKey,
    };
    for (final key in _images.keys.toList()) {
      if (!wanted.contains(key)) {
        _dropImage(key, _images.remove(key)!);
      }
    }
    // A row that left the stack takes its failure record with it — the
    // note exists to stop a per-rebuild retry, not to remember cels this
    // stack no longer shows.
    _failedRevisions.removeWhere((key, _) => !wanted.contains(key));
    for (final layer in widget.layers) {
      // Valid cache image, or a synchronous per-tile compose (the just-
      // deactivated layer's on-screen tiles are already decoded) — either
      // way the artwork paints THIS frame; only true cold misses fall to
      // the async pass.
      // 🚨Same law as the async pass — and this walk runs FIRST, so
      // without it the guard down there never gets its turn: the throw
      // lands here instead, out of a build/layout callback, and every
      // later layer in THIS sweep is skipped with it. One row's
      // unreachable cel is one row's.
      if (_shouldSkipFailed(layer.frameKey)) {
        continue;
      }
      // 🚨READ BEFORE THE PREPARE. The stamp has to name the revision the
      // picture was BUILT from, not the one standing when it finished — the
      // async twin awaits at this exact spot, and an edit landing during
      // that await would otherwise put a just-bumped revision on a picture
      // rendered before it, which the cold-miss guard below would then
      // never recognise as stale. Same order in both twins, one law.
      final revision = _revisionOf(layer.frameKey);
      final LayerFrameImage? image;
      try {
        image = widget.imageCache.prepareSyncOrNull(
          key: layer.frameKey,
          canvasSize: widget.canvasSize,
          quality: PlaybackQuality.full,
          sourceEffects: layer.sourceEffects,
        );
      } on Object catch (error, stack) {
        _noteFailure(layer.frameKey, error, stack, 'sync sweep');
        continue;
      }
      // The note means "the LAST attempt failed", not "one once did".
      // Left standing it outlives the failure, and a project open reseeds
      // every frame back to revision 1 — which makes an old note match
      // again and skips a cel that builds perfectly well.
      _failedRevisions.remove(layer.frameKey);
      if (image == null) {
        // 🚨★★★A COLD MISS IS NOT A LICENCE TO PAINT THE OLD PICTURE.
        //
        // Keeping the held image is right for a LAYER SWITCH — that is what
        // this sweep exists for, and the pixels have not changed, only the
        // cache went cold. It is wrong for an EDIT: the cel's content moved
        // on and what is still held is the drawing as it was BEFORE it.
        //
        // 유저 2026-08-27, iPhone: 「두번째 변형에서 화면 갱신(줌하거나 팬하거나
        // 그런거)하기 전까지 이전 변형하기 전 그림이 남아있었음」 — and on
        // Windows the same thing for exactly one frame, because a desktop
        // produces the next frame immediately while an idle phone does not
        // produce one at all until you touch the view. Two severities, one
        // cause.
        //
        // `sourceRevision` already separates the two: `markCelEdited` bumps
        // it on every surface write, a layer switch does not touch it. So a
        // held image whose revision no longer matches is stale and goes; one
        // that still matches stays, and the flicker-free switch is untouched.
        final held = _images[layer.frameKey];
        if (held != null && held.revision != revision) {
          _dropImage(layer.frameKey, _images.remove(layer.frameKey)!);
        }
        continue;
      }
      _adoptImage(layer.frameKey, image, revision);
    }
  }

  /// 🚨ONE ROW'S FAILURE IS ONE ROW'S. This walk is serial and the
  /// future it runs in is nobody's to await, so a throw here used
  /// to abandon the whole pass: every LATER layer's prepare was
  /// never called, and nothing said so. What the user sees is a
  /// stack where the first rows are drawn and the rest are blank
  /// until something happens to rebuild past the bad one — and
  /// which rows those are moves with the walk order.
  ///
  /// The prepare reaches STORAGE: a file-backed cel whose .anicel
  /// has moved throws from inside this call. That is a reason for
  /// one row to be missing, never a reason to stop drawing the
  /// others.
  /// Null when the view unmounted mid-await; else whether the held
  /// image for [layer] changed.
  Future<bool?> _refreshLayerImage(CanvasLayerImageRequest layer) async {
    if (_shouldSkipFailed(layer.frameKey)) {
      return false;
    }
    // Read BEFORE the await — see the sync twin for why the order is
    // the law and not a detail.
    final revision = _revisionOf(layer.frameKey);
    final LayerFrameImage? image;
    try {
      image = await widget.imageCache.prepare(
        key: layer.frameKey,
        canvasSize: widget.canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: layer.sourceEffects,
      );
    } on Object catch (error, stack) {
      if (!mounted) {
        return null;
      }
      _noteFailure(layer.frameKey, error, stack, 'async pass');
      return false;
    }
    // Same as the sync twin: a success retires the note.
    _failedRevisions.remove(layer.frameKey);
    if (!mounted) {
      return null;
    }
    final held = _images[layer.frameKey];
    if (image == null) {
      if (held != null) {
        _dropImage(layer.frameKey, held);
        _images.remove(layer.frameKey);
        return true;
      }
      return false;
    }
    return _adoptImage(layer.frameKey, image, revision);
  }

  Future<void> _ensureImages() async {
    if (_preparing) {
      // A rebuild changed the request set mid-flight; run once more after
      // the current pass so the stack converges on the latest layers.
      _rerunRequested = true;
      return;
    }
    _preparing = true;
    try {
      do {
        _rerunRequested = false;
        var changed = false;
        final wanted = <BrushFrameKey>{};
        for (final layer in List.of(widget.layers)) {
          wanted.add(layer.frameKey);
          final refreshed = await _refreshLayerImage(layer);
          if (refreshed == null) {
            return;
          }
          changed = changed || refreshed;
        }
        final standInHold = _activeStandIn?.frameKey;
        if (standInHold != null) {
          // The same hold the sync sweep applies — the async pass must not
          // drop what the paint phase is standing in with.
          wanted.add(standInHold);
        }
        for (final key in _images.keys.toList()) {
          if (!wanted.contains(key)) {
            _dropImage(key, _images.remove(key)!);
            changed = true;
          }
        }
        if (changed && mounted) {
          setState(() {});
        }
      } while (_rerunRequested && mounted);
    } finally {
      _preparing = false;
    }
  }

  /// The tree with each image request replaced by the clone we hold —
  /// requests whose image is not ready yet simply drop out, and a group
  /// left empty by that drops with them (an empty buffer is a wasted
  /// saveLayer).
  List<_PaintNode> _resolvedTree(List<CanvasLayerStackNode> nodes) {
    final out = <_PaintNode>[];
    for (final node in nodes) {
      switch (node) {
        case CanvasLayerImageNode(:final request):
          final held = _images[request.frameKey];
          if (held == null) {
            continue;
          }
          out.add(
            _PaintImage(
              image: held.clone,
              worldRect: held.worldRect,
              opacity: request.opacity,
              blendMode: request.blendMode,
              pose: request.pose,
              anchorPoint: request.anchorPoint,
              tint: request.tint,
              // The PAINT half only — the keys are already in the image the
              // cache handed back.
              effects: request.paintEffects,
            ),
          );
        case CanvasActiveLayerNode(
          :final opacity,
          :final blendMode,
          :final pose,
          :final anchorPoint,
        ):
          if (widget.activeSurfacePainter == null) {
            continue;
          }
          out.add(
            _PaintActiveSurface(
              opacity: opacity,
              blendMode: blendMode,
              pose: pose,
              anchorPoint: anchorPoint,
              // The PAINT half only — like the cached row above. A leading
              // key is already on the surface this node draws.
              effects: node.paintEffects,
              standIn: _activeStandIn,
            ),
          );
        case CanvasLayerGroupNode(
          :final children,
          :final opacity,
          :final blendMode,
          :final effects,
        ):
          final mapped = _resolvedTree(children);
          if (mapped.isEmpty) {
            continue;
          }
          out.add(
            _PaintGroup(
              children: mapped,
              opacity: opacity,
              blendMode: blendMode,
              effects: effects,
            ),
          );
        case CanvasLayerAdjustmentNode(
          :final children,
          :final effects,
          :final mix,
        ):
          final mapped = _resolvedTree(children);
          if (mapped.isEmpty) {
            continue;
          }
          out.add(
            _PaintAdjustment(children: mapped, effects: effects, mix: mix),
          );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _resolvedTree(widget.nodes);
    // 🚨(v) — the recordings survive only while everything they were
    // recorded against holds still.
    //
    // ⛔The set is deliberately the SAME one `shouldRepaint` compares, plus
    // [_imagesRevision]. Anything compared there and left out here is a slot
    // that keeps replaying after the thing it drew has changed — a stale
    // frame nobody can trace back to a cache, which is the failure mode
    // [[stale-tile-flicker-program]] is a whole file about.
    //
    // The ACTIVE surface is absent on purpose: a stroke step changes its
    // pixels and nothing else, and its pixels are the one thing never
    // recorded. That absence IS the optimisation.
    // 🚨★★★THE VIEWPORT IS NOT IN HERE, and that is not an oversight.
    //
    // It used to be, from the days when the buffer was `pasteboard ∩
    // visibleRect` — an extent the viewport moved directly. #1301 made the
    // extent CONTENT ∩ view, and the cache has compared the rect all along
    // (`imageFor(key, rect)` needs both). So the viewport reached these
    // pixels through the extent and nothing else, and the extent is already
    // the guard.
    //
    // 🧪Verified by walking every widget the buffer composites: the zoom's
    // `filterQuality` lands when the buffer is DRAWN, not inside it; group
    // rasters inside run at `rasterScale: 1`; `BitmapSurfacePainter` reads
    // its viewport only in the standalone `paint()`, never in
    // `paintContentInto`; `layerPoseViewportWrapMatrix` belongs to the brush
    // panel's `Transform`, not to any composite route.
    //
    // ⇒ Panning or zooming REPAINTS (shouldRepaint still compares the
    // viewport, and the CTM did change) but no longer RE-COMPOSITES while
    // the extent holds — which is exactly the posture where the page fits
    // the screen and the buffer is at its biggest.
    final compositeKey = Object.hash(
      _imagesRevision,
      widget.canvasSize,
      widget.paintPaper,
      widget.paperBackground,
      _LayerStackPainter.treeSignature(nodes),
    );
    _bake.keepFor(compositeKey);
    return IgnorePointer(
      // ⛔**THE `willChange: true` HINT IS GONE** — from this picture and
      // from the three siblings that copied it. The history stays because
      // the losing legs keep getting re-proposed:
      //
      //  · #1100 A/B — the 1px axis-aligned edge hop at pen-down / pen-up /
      //    layer switch / tool buttons was device-confirmed to be Skia's
      //    picture raster cache: it snaps a STABLE picture's layer to
      //    integral device translation and replays the cached raster there,
      //    while live repaints render at the fractional offset panel layout
      //    produced. Every engage/disengage moment flips between the two.
      //  · #1101 — in-picture pan snap. Fixed PAN jitter (our own
      //    fractional-phase blit, recorded inside the picture) and stays;
      //    could NOT fix the transition hop, because the cache snaps the
      //    picture LAYER's device offset, which panel layout owns and no
      //    in-picture transform can see.
      //  · #1103 — `willChange: true` here. Device-verified: ALL transition
      //    hops gone.
      //  · #1106 — replaced the hint with `IntegralLayerOffset`, a
      //    post-frame self-measuring wrapper that used to sit above the
      //    canvas content boundary in `brush_canvas_panel.dart` (deleted
      //    with the hints), and turned the cache back on.
      //    Device 2026-08-17: the hops CAME BACK
      //    (active-layer switch, tool change, wheel-click pan start — at
      //    zoom >= 100% only, the nearest-filter half of the display law).
      //    The wrapper's measurement is a post-frame chain, so the frame OF
      //    an ancestor layout change still paints with the PREVIOUS
      //    compensation — the exact frame those chrome actions produce —
      //    and on that frame the boundary sits fractional while this
      //    picture is stable-cached: the snap is live again.
      //
      //  · R11 — the quantization round, and why the hint is GONE as of
      //    this commit. R11 does not measure anything: every app-chosen
      //    offset from the window origin down is an integral count of
      //    device pixels IN LAYOUT, so a layout-change frame is already on
      //    the grid in that same frame. That is exactly the hole #1106 fell
      //    into, which is what makes this not a repeat of it —
      //    `canvas_boundary_on_grid_test.dart`'s "ON THE FRAME OF A LAYOUT
      //    CHANGE" group measures the uncompensated chain one single frame
      //    after a panel opens and after a UI-scale change, at 1.25, 1.35
      //    and the 1.5x0.9 product. The wrapper went in the same commit:
      //    with the chain integral in layout there is nothing left for a
      //    post-frame measurement to correct.
      //
      // ⚠️SCOPE — the hint was never this picture's alone. This
      // `CustomPaint` has no `RepaintBoundary` of its own, and
      // `RenderCustomPaint.paint` sets the hint on whatever layer is being
      // RECORDED, which is the `canvas-content-boundary` layer. It covered
      // the stage planes too. That is why the failure signature is "the
      // whole canvas contents shift together against the chrome", not "the
      // artwork shifts against its own paper".
      //
      // 🚨And with the artwork cacheable again, a canvas-space painter that
      // does NOT clip to its own box stops being harmlessly uncacheable and
      // starts sizing a cache entry from its display-list bounds. An
      // unclipped stage-plane quad once measured ~1 GB of picture cache on
      // an EMPTY project. `test/ui/brush/stage_planes_clip_test.dart` is
      // that guard, and its invariant is load-bearing now rather than tidy.
      //
      // 🚨The mechanism this block used to assert was also wrong. The
      // engine source says the hint suppresses raster CACHING but not the
      // snap: the snap applies whenever a cache entry exists, and the cache
      // key discards translation. The hint never did what the text claimed
      // — what it did was stop the entry from existing at all.
      //
      // ⚠️WATCH FOR — two symptoms, both WINDOWS only (Impeller carries no
      // raster cache, so none of this can happen on iPad or Android) and
      // both only at fractional display scaling; neither can occur at 100%
      // or 200%.
      //  (1) A JUMP. A hard edge of the drawing, or the paper border
      //      against the panel, hops 1px for an instant at zoom >= 100% —
      //      pen-down/up, active-layer switch, a tool button, wheel-click
      //      pan start, or alt-tabbing away and back (a focus switch purges
      //      the cache; the oldest repro, and the one no test can produce).
      //      That means the chain went fractional on some layout-change
      //      frame, i.e. the hint's half was wrong.
      //  (2) BLUR. Nothing jumps, but 1px ink edges and the paper border
      //      read soft at 125% or 1.35. That is the settled offset itself
      //      sitting half a pixel off — the WRAPPER's half — and it is the
      //      harder one to notice.
      // The retirement is one commit and reverts whole. The cheap positive
      // check that it did what it claims: Settings ▸ Frame Stats on
      // Windows, where `pictureCacheCount` should RISE.
      child: CustomPaint(
        painter: _LayerStackPainter(
          nodes: nodes,
          activeSurfacePainter: widget.activeSurfacePainter,
          floatOverlay: widget.floatOverlay,
          canvasSize: widget.canvasSize,
          viewport: widget.viewport,
          paintPaper: widget.paintPaper,
          paperBackground: widget.paperBackground,
          bake: widget.debugDisableBake ? null : _bake,
          bufferCache: widget.debugDisableBake ? null : _bufferCache,
          compositeKey: compositeKey,
          // ⓔ 5단계: the knee's s = zoom·DPR, and the DPR is the one the
          // ROOT MATRIX uses — the effective ratio. It still tracks
          // monitor moves (this build re-runs) and still answers per
          // view, where the raw PlatformDispatcher singleton does
          // neither; it additionally survives a UI scale, which MediaQuery
          // does not — MediaQuery keeps reporting the monitor's raw ratio
          // while the compositor works on the product.
          devicePixelRatio:
              EffectiveDevicePixelRatio.of(context),
          debugDisableSingleBuffer: widget.debugDisableSingleBuffer,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The painter's own node shape: the request tree with images resolved.
sealed class _PaintNode {
  const _PaintNode();
}

/// How many ops the engine replays to draw [list] — one per leaf, one
/// more per group's `saveLayer`. This is the S7 predicate's input: it is
/// a static fact of the node tree, so the backdrop decision needs no
/// clock and cannot flap within a key.
int _replayOpsOf(List<_PaintNode> list) {
  var ops = 0;
  for (final node in list) {
    ops += switch (node) {
      _PaintImage() => 1,
      _PaintActiveSurface() => 1,
      _PaintGroup(:final children) => 1 + _replayOpsOf(children),
      _PaintAdjustment(:final children) => 1 + _replayOpsOf(children),
    };
  }
  return ops;
}

final class _PaintImage extends _PaintNode {
  const _PaintImage({
    required this.image,
    required this.worldRect,
    required this.opacity,
    required this.blendMode,
    required this.pose,
    required this.anchorPoint,
    required this.tint,
    required this.effects,
  });

  final ui.Image image;
  final Rect worldRect;
  final double opacity;
  final LayerBlendMode blendMode;
  final TransformPose? pose;
  final CanvasPoint? anchorPoint;
  final int? tint;
  final List<ResolvedLayerEffect> effects;
}

/// The first-activation stand-in: the just-deactivated route's layer image,
/// plus everything needed to answer — at PAINT time, on every paint — "is
/// the swap window still open".
///
/// The window opens armed (zero pictures existed at arm time) and the latch
/// is ONE-WAY: it dies for good, never re-arms. What kills it —
/// - an overlay with anything to show, or a different surface instance,
///   INSTANTLY (those are the only doors an edit can arrive through);
/// - EVERY committed tile having a picture (the walk is whole from there).
///
/// ⛔Not "the first picture" (device report 2026-08-17, second round): an
/// any-decode death handed the walk a partially decoded surface, and the
/// budgets' silence re-appeared as per-tile holes. Holding through the
/// partial states is sound precisely because the window armed pre-edit —
/// the held image and the landing decodes are the same committed bytes,
/// and anything that could make them differ kills the window in the same
/// paint that shows it.
///
/// Paint-time, not build-time, because decodes land between builds: the
/// tile cache notifies, the painter repaints, and the very same repaint
/// must already answer with the walk once it can draw everything. A
/// build-time answer would keep serving the stand-in until some unrelated
/// rebuild came along.
class _ActiveLayerStandIn {
  _ActiveLayerStandIn({
    required this.frameKey,
    required this.image,
    required this.worldRect,
    required this.surface,
    required this.tiles,
    required this.tileImages,
  });

  final BrushFrameKey frameKey;

  /// The held clone from the state's `_images` — owned THERE (the wanted
  /// hold keeps the record alive while this object does), never disposed
  /// here.
  final ui.Image image;
  final Rect worldRect;

  /// The promoted surface this window belongs to, by identity.
  final BitmapSurface surface;

  /// The surface's committed tiles, captured once (the surface is
  /// immutable; `surface.tiles` is a defensive whole-map copy per read).
  final List<BitmapTile> tiles;

  final BitmapTileImageCache tileImages;

  bool _dead = false;

  /// Whether the window has not been killed yet (bookkeeping for the
  /// state's keep/drop decision — the paint-time question is
  /// [shouldStandInFor]).
  bool get isLive => !_dead;

  /// The paint-time predicate: draw the stand-in instead of the tile walk?
  bool shouldStandInFor(BitmapSurfacePainter painter) {
    if (_dead) {
      return false;
    }
    if (!identical(painter.surface, surface)) {
      _dead = true;
      return false;
    }
    final overlay = painter.overlayModel;
    if (overlay != null &&
        (overlay.hasStrokeContent ||
            overlay.stampImage != null ||
            overlay.settling ||
            overlay.hasStandIns ||
            (overlay.settleHoldTiles?.isNotEmpty ?? false))) {
      // In-flight ink (or a settle window) must reach the screen, and the
      // walk is the only body that draws it — and a settle window means
      // this was never the first-activation frame to begin with.
      _dead = true;
      return false;
    }
    // The window closes when EVERY committed tile has a picture — not on
    // the first one (device report 2026-08-17, second round: the one-way
    // any-decode latch handed off after the FIRST landing, and the walk
    // then showed the budgets' worth and left the rest as holes: "whole
    // picture blank" had merely become "some tiles blank").
    //
    // What keeps the longer hold truthful: this stand-in only ever ARMS
    // when zero pictures exist — pre-edit, so the held image IS the
    // committed bytes — and an edit can only arrive through the overlay
    // or through a commit's new surface instance, both of which kill the
    // window above INSTANTLY. So every decode that lands while it is open
    // is a decode of the very pixels already on screen; holding over a
    // partial set of them changes nothing per-pixel, and the handoff
    // below swaps to a walk that can draw every coordinate.
    for (final tile in tiles) {
      if (tileImages.displayImageFor(tile) == null) {
        return true;
      }
    }
    // Every tile can speak for itself now: the walk is whole from here,
    // and the stand-in must never outlive that.
    _dead = true;
    return false;
  }
}

final class _PaintActiveSurface extends _PaintNode {
  const _PaintActiveSurface({
    required this.opacity,
    required this.blendMode,
    required this.pose,
    required this.anchorPoint,
    required this.effects,
    this.standIn,
  });

  /// ㊱: the active row's display opacity. It reached the node all along and
  /// stopped here — the field did not exist, so the live surface drew at full
  /// strength while every OTHER row honoured its slider.
  final double opacity;

  /// The same story as [opacity], one field over and one round later: the
  /// blend had no field on the node either, so it could not stop here — it
  /// never started. See [CanvasActiveLayerNode.blendMode].
  final LayerBlendMode blendMode;

  final TransformPose? pose;
  final CanvasPoint? anchorPoint;
  final List<ResolvedLayerEffect> effects;

  /// The first-activation stand-in, or null outside the swap window.
  ///
  /// ⛔Deliberately absent from [_LayerStackPainter._treesMatch] and
  /// [_LayerStackPainter.treeSignature], for the same reason the active
  /// surface's pixels are: this IS active-slot content, its every visible
  /// change rides the tile cache's notification (arming coincides with the
  /// activation rebuild; the latch dies exactly when a decode notifies),
  /// and the bake never records the slot it is drawn in.
  final _ActiveLayerStandIn? standIn;
}

final class _PaintGroup extends _PaintNode {
  const _PaintGroup({
    required this.children,
    required this.opacity,
    required this.blendMode,
    required this.effects,
  });

  final List<_PaintNode> children;
  final double opacity;
  final LayerBlendMode blendMode;
  final List<ResolvedLayerEffect> effects;
}

final class _PaintAdjustment extends _PaintNode {
  const _PaintAdjustment({
    required this.children,
    required this.effects,
    required this.mix,
  });

  final List<_PaintNode> children;
  final List<ResolvedLayerEffect> effects;
  final double mix;
}

/// The CANVAS-SPACE rect [node] actually covers, its own pose applied.
///
/// 🚨THIS IS WHAT KEEPS THE COMPOSITE AT CANVAS RESOLUTION AT EVERY ZOOM.
///
/// The buffers used to be bounded by `pasteboard ∩ visibleRect`. Zoom out
/// far enough and that rect spans the whole pasteboard — 5×5 canvases,
/// 11700×8270 on a 2340×1654 page — which blows past [_maxBufferSide] and
/// drops the paint onto the SCREEN-resolution fallback. That fallback is
/// how the editing canvas stopped compositing the way playback, the camera
/// and the export do (유저 2026-08-15 accepted it at the time: 「무릎 아래는
/// 균일 필터, 겹침 색차 수용」 — accepted because bounding by the view was
/// the only tool on the table).
///
/// ★Content is not the pasteboard. It is [surfaceContentWorldRect]'s answer
/// — the canvas rect unioned with the tiles that actually exist — so an
/// ordinary page bounds to 2340×1654 and never reaches the cap. The
/// fallback stops being reachable, and one resolution serves every zoom.
///
/// ⛔RECOMPUTED, NEVER ACCUMULATED. A rect that only ever grew would be the
/// high-water mark of everything you had done — the "sticky / containment
/// 매칭 버퍼 rect" the composite plan rejects by name.
/// [draw] with [layer]'s opacity/blend/colour chain folded in, or [draw]
/// unchanged when a buffer is carrying the layer instead.
///
/// ⛔The draw keeps its OWN sampling. A layer paint says how the layer
/// composites, never how a picture is resampled — writing `filterQuality`
/// from it would be one paint answering two questions.
/// Whether the live layer's last paint handed its opacity/blend to the
/// individual draws instead of opening a buffer around them.
///
/// 🚨THE DECISION, NOT ITS PIXELS. Whether a buffer was opened is invisible
/// in a comparison — the two routes are the same pixels, which is the whole
/// point — so the only way to pin WHEN each one runs is to read the answer.
///
/// ⚠️Written under `assert`, so a release build pays nothing.
@visibleForTesting
bool? debugLiveLayerRodeTheDraws;

Paint _withLayerPaint(Paint draw, Paint? layer) {
  if (layer == null) {
    return draw;
  }
  return draw
    ..color = layer.color
    ..blendMode = layer.blendMode
    ..colorFilter = layer.colorFilter
    ..imageFilter = layer.imageFilter;
}

Rect _paintNodeExtent(
  _PaintNode node, {
  required CanvasSize canvasSize,
  required Rect Function() activeSurfaceExtent,
}) {
  Rect posed(Rect rect, TransformPose? pose, CanvasPoint? anchorPoint) {
    if (pose == null) {
      return rect;
    }
    return MatrixUtils.transformRect(
      layerPoseMatrix(pose, canvasSize, anchorPoint: anchorPoint),
      rect,
    );
  }

  switch (node) {
    case _PaintImage(:final worldRect, :final pose, :final anchorPoint):
      return posed(worldRect, pose, anchorPoint);
    case _PaintActiveSurface(:final pose, :final anchorPoint):
      return posed(activeSurfaceExtent(), pose, anchorPoint);
    case _PaintGroup(:final children):
    case _PaintAdjustment(:final children):
      var union = Rect.zero;
      for (final child in children) {
        final childRect = _paintNodeExtent(
          child,
          canvasSize: canvasSize,
          activeSurfaceExtent: activeSurfaceExtent,
        );
        if (childRect.isEmpty) {
          continue;
        }
        union = union.isEmpty ? childRect : union.expandToInclude(childRect);
      }
      return union;
  }
}

/// One composited canvas-resolution raster and where it belongs.
///
/// [rect] is in canvas space and is whole-pixel aligned, so the src/dst pair
/// of the final `drawImageRect` is exact: the ONE resample the display is
/// entitled to happens in the viewport transform and nowhere else.
class _DisplayBuffer {
  const _DisplayBuffer({
    required this.image,
    required this.rect,
    required this.pixelWidth,
    required this.pixelHeight,
    this.owned = true,
  });

  final ui.Image image;
  final Rect rect;
  final double pixelWidth;
  final double pixelHeight;

  /// Whether the caller disposes [image] after drawing it.
  ///
  /// ⛔False when the cache is holding it for the next paint — disposing
  /// there hands the following frame a dead handle, which is the hazard
  /// [[native-tile-pixel-lifetime]] and the bake's revision counter both
  /// exist to make structurally impossible rather than merely unlikely.
  final bool owned;
}

/// The geometry field probe's state — the numbers every buffer decision
/// depends on and nobody has ever measured on a device: the logical view,
/// the device pixel ratio, the zoom actually worked at, and what the
/// buffer costs there. The 1928×1200 that circulates is a comment in the
/// bake, not a measurement.
///
/// Public and outside the painter because the painter class is private and
/// a fresh object every frame — tests and a hands-on session need to reach
/// the histogram, and the dedupe line needs to outlive a frame.
abstract final class CanvasPaintGeometryProbe {
  /// The last emitted line — the dedupe key, held across frames.
  static String? lastLine;

  /// Paints per zoom bucket (percent, 10% steps), counted while the
  /// inspector is visible. Every byte figure in the composite plan hinges
  /// on "what zoom is actually worked at", and nobody has measured a
  /// distribution — "83%" is one observation and "400% is the working
  /// posture" is a sentence in a brief. This counter turns either into a
  /// fact.
  static final Map<int, int> zoomHistogram = <int, int>{};

  static void reset() {
    lastLine = null;
    zoomHistogram.clear();
  }
}

class _LayerStackPainter extends CustomPainter {
  _LayerStackPainter({
    required this.nodes,
    required this.activeSurfacePainter,
    required this.floatOverlay,
    required this.canvasSize,
    required this.viewport,
    required this.paintPaper,
    required this.paperBackground,
    this.bake,
    this.bufferCache,
    required this.compositeKey,
    this.devicePixelRatio = 1.0,
    this.debugDisableSingleBuffer = false,
  }) : super(
         // The knee A/B rides the repaint merge so flipping the switch
         // repaints the SAME view — the whole point of an in-build A/B
         // is two readings of one picture, not "pan until it rebuilds".
         repaint: Listenable.merge(<Listenable?>[
           activeSurfacePainter,
           floatOverlay,
           MeasurementMode.kneeAtOne,
         ]),
       );

  /// The last line the T12 probe in [paint] emitted. Static: a
  /// [CustomPainter] is a fresh object every frame, so an instance field
  /// would only ever compare against itself.
  static String? _lastStackProbe;

  final List<_PaintNode> nodes;

  /// 🚨(v) — the recording of everything a stroke cannot change.
  ///
  /// Owned by the STATE, not by this painter: a `CustomPainter` is a fresh
  /// object every frame, so a cache held here would be recorded and thrown
  /// away in the same breath. Null keeps the original walk.
  final StaticCompositeBake? bake;

  /// The kept composite buffer ([DisplayBufferCache]). Owned by the State,
  /// because a painter is a fresh object every frame.
  final DisplayBufferCache? bufferCache;

  /// What the bake was kept for. The buffer's key builds on it and adds the
  /// live surface, which the bake deliberately leaves out.
  final Object compositeKey;

  /// Draws the ACTIVE layer's live surface in place. Its own repaint
  /// Listenable (tile cache + stroke overlay) drives this painter too, so
  /// a stroke step still repaints without a widget rebuild.
  final BitmapSurfacePainter? activeSurfacePainter;

  /// TS1: the selection float, drawn in the active layer's slot. Merged into
  /// the repaint above for the same reason the surface painter is — a drag
  /// step has to reach the canvas without a widget rebuild.
  final SelectionFloatOverlay? floatOverlay;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;
  final bool paintPaper;
  final ProjectBackground paperBackground;

  /// See [CanvasLayerStackView.debugDisableSingleBuffer].
  final bool debugDisableSingleBuffer;

  /// The EFFECTIVE ratio at build time (monitor × UI scale) — the knee's
  /// `s = zoom·dpr` axis. A monitor move re-runs the build, so a fresh
  /// painter always carries the current value.
  final double devicePixelRatio;

  /// ⓔ 5단계 — set ONLY while the SCALED buffer records, consumed by the
  /// active-surface arm: below the knee every layer must be ONE image
  /// under one uniform filter, and this is the active layer's
  /// ([ActiveLayerFlatProjection]). Mutable painter state is safe here
  /// because a painter lives one frame and paint is single-threaded; it
  /// is cleared in the same call that set it, so the s=1 paths can never
  /// see it.
  ActiveLayerFlatImage? _activeFlatForRecording;

  /// #15 — the paper inset, in CANVAS px, the scaled recording draws
  /// with; null on every s=1 path. Same one-frame window and the same
  /// safety argument as [_activeFlatForRecording] above.
  ///
  /// In the scaled recording every element is resampled SEPARATELY at
  /// s < 1, so the paper's edge is analytic rect coverage (a ramp one
  /// buffer px wide) while the ink's edge over it is a bilinear window
  /// on canvas-resolution texels (a ramp s buffer px wide) — two
  /// rasterizations of the same geometric line that disagree in width
  /// and phase. Composited, the paper stays white where the ink has
  /// already thinned: a 1px bright ring around a canvas whose every
  /// pixel is opaque ink. The s=1 buffer cannot do this — paper and ink
  /// land jointly on integral canvas pixels and the display resample
  /// sees finished pixels — which is why the device saw the line appear
  /// exactly where the visible rect crosses [_maxBufferSide] and this
  /// path takes over (~29% on a ~2500px view) and vanish at ~32%.
  ///
  /// ONE BUFFER PIXEL bounds every edge mechanism this recording uses:
  /// analytic coverage reaches half a pixel past the line, a sampling
  /// window half a texel more — so a paper that ends one buffer pixel
  /// early sits entirely under the ink's solid region wherever ink
  /// covers the canvas, at every fractional phase. Where no ink covers,
  /// the plate ends one buffer pixel short against the pasteboard — a
  /// device-pixel concession, only below the knee.
  double? _paperInsetForRecording;

  /// The largest buffer side worth allocating, in canvas pixels.
  ///
  /// Not a quality setting — a floor under "is this still a good idea". A
  /// viewport zoomed far out over a 5×5 pasteboard asks for a buffer many
  /// times the screen, and rasterising that to resample it back down is
  /// strictly worse than letting each layer draw itself. The direct walk is
  /// always correct, so falling back to it costs only the sampling law, and
  /// only in a view where everything is tiny anyway.
  static const int _maxBufferSide = 8192;


  /// S7 — the fewest engine ops the backdrop raster must be collapsing
  /// before holding a visible-rect image is worth it. See
  /// `paintBackdropSplit` for the arithmetic; the short version is that
  /// per stroke step the raster saves (ops − 1) draws and costs one blit,
  /// so single-digit stacks save almost nothing while still paying the
  /// image's megabytes and a re-raster per key change. Eight is paper
  /// plus seven draws — comfortably past "almost nothing", far below the
  /// hundreds-of-layers case the raster exists for.
  static const int _backdropRasterMinReplayOps = 8;

  @override
  void paint(Canvas canvas, Size size) =>
      // The paint pass (Round 6): one paint of the stack, as its own object,
      // constructed PER PAINT — its geometry fields are `late final`, and a
      // painter can be asked to paint more than once.
      _LayerStackPaintPass(this).paint(canvas, size);

  /// The coordinates whose token moved from [last] to [now]: one [now]
  /// holds under a different token (or newly), and one [now] no longer
  /// holds at all.
  ///
  /// Identity per coordinate — for the overlay's tile images and the
  /// committed tiles alike. The overlay's tiles carry the stroke in
  /// flight, but they ACCUMULATE for the stroke's whole life (nothing
  /// leaves the map until pen-up), so "every overlay coordinate" is the
  /// bounding box of the WHOLE STROKE by the third dab: a long line paid
  /// its full length again on every step. The overlay replaces a tile's
  /// image only when a dab touched it, so an unchanged image object IS
  /// "this tile did not move". A coordinate the overlay LEFT has to lose
  /// its ink (pen-up, reset).
  static Iterable<TileCoord> _movedCoords(
    Map<Object, Object> last,
    Map<Object, Object> now,
  ) sync* {
    for (final entry in now.entries) {
      if (!identical(last[entry.key], entry.value)) {
        yield entry.key as TileCoord;
      }
    }
    for (final coord in last.keys) {
      if (!now.containsKey(coord)) {
        yield coord as TileCoord;
      }
    }
  }

  /// Where the LIVE surface changed since the kept buffer was made, in
  /// canvas space — or null when that cannot be answered.
  ///
  /// 🚨Null is the safe answer and it costs only a full re-raster, which is
  /// what every paint did before the cache existed. It is returned whenever
  /// the change cannot be located: the same three cases [_bufferKey] refuses
  /// to cache for, plus a surface whose tiles cannot be compared to the ones
  /// the buffer was made from.
  ///
  /// ⛔The rect is INFLATED by one pixel. A dab writes whole texels, but the
  /// composite around it does not have to land on them — a posed sibling or
  /// a rounded edge can put ink a fraction over the line, and a patch that
  /// trusted the exact rect would leave a hairline of the previous frame.
  /// One pixel is cheap and the alternative is a class of bug that only
  /// shows on some zoom levels.
  ({bool located, Rect? dirty}) _liveDirtyCanvasRect() {
    final surfacePainter = activeSurfacePainter;
    if (surfacePainter == null || !surfacePainter.drawsOnlyFromPublishedState) {
      return (located: false, dirty: null);
    }
    final overlay = surfacePainter.overlayModel;
    if (overlay != null && (overlay.hasStandIns || overlay.settling)) {
      return (located: false, dirty: null);
    }
    if (overlay?.stampImage != null) {
      return (located: false, dirty: null);
    }
    if (!_liveSurfaceIsSpatiallyStable(nodes)) {
      return (located: false, dirty: null);
    }
    final tileSize = surfacePainter.surface.tileSize.toDouble();
    Rect? dirty;
    void add(Rect rect) => dirty = dirty == null ? rect : dirty!.expandToInclude(rect);
    Rect rectOf(TileCoord coord) => Rect.fromLTWH(
      coord.x * tileSize,
      coord.y * tileSize,
      tileSize,
      tileSize,
    );
    // The overlay's tiles carry the stroke in flight — but they ACCUMULATE
    // for the stroke's whole life (nothing leaves the map until pen-up), so
    // "every overlay coordinate" is the bounding box of the WHOLE STROKE by
    // the third dab: a long line paid its full length again on every step.
    // Identity per coordinate instead, exactly like the committed loop
    // below — the overlay replaces a tile's image only when a dab touched
    // it, so an unchanged image object IS "this tile did not move".
    final cacheState = bufferCache!;
    final overlayNow = <TileCoord, Object>{
      ...overlay?.tileImages ?? const <TileCoord, ui.Image>{},
    };
    for (final coord in _movedCoords(
      cacheState.lastOverlayTokens,
      overlayNow,
    )) {
      add(rectOf(coord));
    }
    cacheState.lastOverlayTokens = overlayNow;
    // Committed tiles: a commit replaces the tile, and a decode replaces its
    // image. Both are identity changes on the same coordinate.
    final cache = surfacePainter.tileImageCache;
    final seen = <TileCoord, Object>{
      for (final entry in surfacePainter.surface.tiles.entries)
        entry.key: cache.imageFor(entry.value) ?? entry.value,
    };
    for (final coord in _movedCoords(cacheState.lastTileTokens, seen)) {
      add(rectOf(coord));
    }
    final hadTokens = cacheState.lastTileTokens.isNotEmpty;
    cacheState.lastTileTokens = seen;
    if (!hadTokens) {
      // Nothing to compare against — the first paint after a cold start.
      return (located: false, dirty: null);
    }
    return (located: true, dirty: dirty?.inflate(1));
  }

  /// Everything the composite depends on that the bake's key does not
  /// already carry — or null when this stack must not be cached at all.
  ///
  /// 🚨The bake deliberately leaves the live surface out: it never records
  /// it, so a stroke step cannot stale a recording. The BUFFER holds the
  /// live surface, so it needs every way that surface's pixels can move:
  ///
  ///  * the committed tiles, by identity — `BitmapSurface` is immutable, so
  ///    an edit is a new instance;
  ///  * their DECODED images, because a decode ARRIVING changes the screen
  ///    while the tile it came from never moved;
  ///  * the overlay's tile images and its stamp, by identity, which is how
  ///    an in-flight stroke reaches the canvas at all;
  ///  * the stand-in and settling passes, which redraw on their own clock.
  ///
  /// ⛔And null when the painter says it draws from state it does not
  /// publish ([BitmapSurfacePainter.drawsOnlyFromPublishedState]) — then no
  /// comparison here can be right, so nothing is kept. That is the same
  /// question the tiled buffer had to ask, and the answer that makes a
  /// cache honest: ask the thing you are caching where it changed, and do
  /// not cache what cannot say.
  Object? _bufferKey() {
    // ⛔A FLOATING SELECTION IS DRAWN INSIDE THIS BUFFER and moves under the
    // hand without touching anything else the key can see, so while one
    // exists nothing is kept. Caught by walking this painter's own body
    // asking "what else can change" — which is the discipline the two
    // reverts before this bought ([[cache-what-can-say-where-it-changed]]).
    // Shipping without it would have frozen the canvas for the whole drag.
    //
    // Not cheap-and-narrow (hash the float's value) on purpose: the float is
    // a transient editing state, so declining to cache costs only what the
    // uncached path already cost, and it cannot go stale.
    if (floatOverlay?.value != null) {
      return null;
    }
    final surfacePainter = activeSurfacePainter;
    if (surfacePainter == null) {
      // Nothing live: the bake's key already covers every pixel here.
      return compositeKey;
    }
    if (!surfacePainter.drawsOnlyFromPublishedState) {
      return null;
    }
    // ⛔ONE int, not a walk. This used to hash every tile's decoded image:
    // it costs a lookup per tile PER PAINT and — measured — never produced
    // a stable key, so the buffer paid the walk and missed anyway. The
    // cache's own revision says the same thing for free, because it is
    // bumped at exactly the moments the cache tells anyone it changed.
    var live = Object.hash(
      identityHashCode(surfacePainter.surface),
      surfacePainter.tileImageCache.revision,
    );
    final overlay = surfacePainter.overlayModel;
    if (overlay != null) {
      if (overlay.hasStandIns || overlay.settling) {
        return null;
      }
      live = Object.hash(live, identityHashCode(overlay.stampImage));
      for (final entry in overlay.tileImages.entries) {
        live = Object.hash(live, entry.key, identityHashCode(entry.value));
      }
    }
    // 🚨★★★F-33: the stamp ghost is part of what this buffer would hold, so
    // it has to be part of the key. Left out, the buffer caches a frame
    // WITHOUT the ghost and the ghost then stops following the pointer —
    // the silent failure this whole key exists to prevent, and the reason
    // the fill stamp above is in it too.
    //
    // Its own `==` is identity on the piece and the image plus value on the
    // rect and the opacity, which is exactly what a hover changes.
    live = Object.hash(live, surfacePainter.stampPreview?.value);
    return Object.hash(compositeKey, live);
  }

  /// Whether a change to the live surface lands where that surface is.
  ///
  /// ⛔False means no dirty rect drawn from the surface's own coordinates is
  /// correct. A POSE puts its pixels somewhere else entirely, and an effect
  /// that SPREADS — on the surface itself or on any folder enclosing it,
  /// because the stroke's pixels pass through those buffers — smears a dab
  /// past its own tile. Both are answered by re-rastering the whole buffer,
  /// which is what every paint did before any of this existed.
  static bool _liveSurfaceIsSpatiallyStable(List<_PaintNode> list) {
    for (final node in list) {
      if (node is _PaintActiveSurface) {
        return node.pose == null && !resolvedEffectsSpreadPixels(node.effects);
      }
      if (node is _PaintGroup && node.children.any(_enclosesActiveSurface)) {
        return !resolvedEffectsSpreadPixels(node.effects) &&
            _liveSurfaceIsSpatiallyStable(node.children);
      }
      if (node is _PaintAdjustment &&
          node.children.any(_enclosesActiveSurface)) {
        return !resolvedEffectsSpreadPixels(node.effects) &&
            _liveSurfaceIsSpatiallyStable(node.children);
      }
    }
    return false;
  }

  /// Whether the live surface is this node, or anywhere inside it.
  static bool _enclosesActiveSurface(_PaintNode node) => switch (node) {
    _PaintActiveSurface() => true,
    _PaintGroup(:final children) => children.any(_enclosesActiveSurface),
    _PaintAdjustment(:final children) => children.any(_enclosesActiveSurface),
    _PaintImage() => false,
  };

  @override
  bool shouldRepaint(covariant _LayerStackPainter oldDelegate) {
    return oldDelegate.canvasSize != canvasSize ||
        oldDelegate.viewport != viewport ||
        oldDelegate.paintPaper != paintPaper ||
        // The paper's COLOR is painted here (see the `paintPaper` branch), so
        // it belongs in the gate beside the flag that turns it on. It was the
        // one value this painter drew and did not compare: changing the
        // project background left the editing canvas on its old paper until
        // something unrelated moved. `ProjectBackground` compares by argb, so
        // this costs an int compare, not an identity miss every frame — and
        // the sibling `playback_frame_painter` already gates on it.
        oldDelegate.paperBackground != paperBackground ||
        // ⓔ 5단계: the knee's s reads this — a monitor move must repaint,
        // not stretch the old scaled buffer.
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        !identical(oldDelegate.activeSurfacePainter, activeSurfacePainter) ||
        !_treesMatch(oldDelegate.nodes, nodes);
  }

  static bool _treesMatch(List<_PaintNode> a, List<_PaintNode> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index += 1) {
      final x = a[index];
      final y = b[index];
      switch ((x, y)) {
        case (_PaintImage(), _PaintImage()):
          x as _PaintImage;
          y as _PaintImage;
          if (!identical(x.image, y.image) ||
              x.worldRect != y.worldRect ||
              x.opacity != y.opacity ||
              x.blendMode != y.blendMode ||
              x.pose != y.pose ||
              x.anchorPoint != y.anchorPoint ||
              x.tint != y.tint ||
              // R6: an effect edit changes the pixels and nothing else —
              // leaving it out here would repaint nothing (the whole tree
              // still "matches") and the canvas would go stale.
              !listEquals(x.effects, y.effects)) {
            return false;
          }
        case (_PaintActiveSurface(), _PaintActiveSurface()):
          x as _PaintActiveSurface;
          y as _PaintActiveSurface;
          // ㊱: the alpha belongs in the repaint gate too — a slider drag
          // changes NOTHING else about this node, so leaving it out would
          // paint the new value only when some unrelated fact moved (the
          // ㉘/㉞ shape: the value is right and the gate says "unchanged").
          if (x.opacity != y.opacity ||
              x.blendMode != y.blendMode ||
              x.pose != y.pose ||
              x.anchorPoint != y.anchorPoint ||
              !listEquals(x.effects, y.effects)) {
            return false;
          }
        case (_PaintGroup(), _PaintGroup()):
          x as _PaintGroup;
          y as _PaintGroup;
          if (x.opacity != y.opacity ||
              x.blendMode != y.blendMode ||
              !listEquals(x.effects, y.effects) ||
              !_treesMatch(x.children, y.children)) {
            return false;
          }
        case (_PaintAdjustment(), _PaintAdjustment()):
          x as _PaintAdjustment;
          y as _PaintAdjustment;
          // A new variant that falls to the default arm below would make
          // shouldRepaint answer true on EVERY frame the node is present —
          // a silent perf regression with no compile error. R6b's arm.
          if (x.mix != y.mix ||
              !listEquals(x.effects, y.effects) ||
              !_treesMatch(x.children, y.children)) {
            return false;
          }
        default:
          return false;
      }
    }
    return true;
  }

  /// 🚨(v) — [_treesMatch] as a VALUE, for the bake's key.
  ///
  /// ⛔It must fold in exactly what [_treesMatch] compares, and it lives
  /// here rather than beside the cache so the two are read together: a
  /// field added to a node and to `_treesMatch` but not to this one makes
  /// the recordings outlive the change they should have ended. The
  /// `default:` arm below is the same tripwire the comparison's is.
  ///
  /// ⚠️Images fold in by IDENTITY (`identityHashCode`), matching
  /// `identical()` above — two different decodes of the same artwork are
  /// two different pictures to draw.
  static int treeSignature(List<_PaintNode> list) {
    var hash = list.length;
    for (final node in list) {
      hash = Object.hash(hash, switch (node) {
        _PaintImage(
          :final image,
          :final worldRect,
          :final opacity,
          :final blendMode,
          :final pose,
          :final anchorPoint,
          :final tint,
          :final effects,
        ) =>
          Object.hash(
            identityHashCode(image),
            worldRect,
            opacity,
            blendMode,
            pose,
            anchorPoint,
            tint,
            Object.hashAll(effects),
          ),
        _PaintActiveSurface(
          :final opacity,
          :final blendMode,
          :final pose,
          :final anchorPoint,
          :final effects,
        ) =>
          Object.hash(
            opacity,
            blendMode,
            pose,
            anchorPoint,
            Object.hashAll(effects),
          ),
        _PaintGroup(
          :final opacity,
          :final blendMode,
          :final effects,
          :final children,
        ) =>
          Object.hash(
            opacity,
            blendMode,
            Object.hashAll(effects),
            treeSignature(children),
          ),
        _PaintAdjustment(:final mix, :final effects, :final children) =>
          Object.hash(mix, Object.hashAll(effects), treeSignature(children)),
      });
    }
    return hash;
  }
}

/// How many paints have fallen to the SCREEN-resolution buffer because a
/// canvas-resolution one would have exceeded the editing stack's buffer cap.
///
/// ★A COUNTER AND NOT A COMMENT. "Content bounds keep an ordinary page under
/// the cap at every zoom" is a claim about a number, and this is the number —
/// the one place the editing canvas stops compositing the way playback, the
/// camera and the export do.
@visibleForTesting
int debugCappedFallbacks = 0;
