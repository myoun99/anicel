import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/tree_nodes.dart';
import '../../core/collection_equality.dart';
import '../../models/brush_frame_key.dart';
import '../../models/canvas_point.dart';
import '../../models/composite_tree.dart';
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
import '../../core/dev_profile.dart';
import '../playback/layer_frame_image_cache.dart';
import 'bitmap_surface_painter.dart';
import '../../services/layer_pose_paint.dart';
import 'tiled_surface_compose.dart';
import '../../services/composite_effect_paint.dart';
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
import 'raster_picture.dart';
import 'tile_origin.dart';

part 'layer_stack/layer_stack_paint_pass.dart';

/// One ROW that paints in the editing canvas's composite tree: a cached
/// layer image ([CanvasLayerImageRequest]) or the ACTIVE layer's live
/// surface.
///
/// The stack used to be two FLAT lists — below the active layer and above
/// it — painted by two sibling widgets with the interactive view between
/// them. A folder composites into one offscreen — a `ui.Image` its own walk
/// rasters — and one offscreen cannot span three sibling painters, so
/// drawing inside a blended folder could never match playback. The tree (with the ACTIVE layer as a node
/// of its own, [CanvasActiveLayerRow]) is what lets one painter close the
/// buffer it opened.
sealed class CanvasStackRow {
  const CanvasStackRow();
}

/// The ACTIVE layer's live surface — the one the brush is drawing into.
/// The painter delegates to the surface painter here, in place, so the
/// stroke lands inside whatever group buffer encloses it.
final class CanvasActiveLayerRow extends CanvasStackRow {
  const CanvasActiveLayerRow({
    required this.opacity,
    this.frameKey,
    this.blendMode = LayerBlendMode.normal,
    this.pose,
    this.anchorPoint,
    this.effects = const [],
  });

  /// The CEL this row is drawing — the same key its cached twin
  /// [CanvasLayerImageRequest.frameKey] asks the image cache with. Null
  /// when the row has nothing exposed here.
  ///
  /// 🚨What it is for: the build in which this cel LEAVES the active slot
  /// (a layer switch; a step to the next frame with onion skin on) it
  /// arrives in the stack as an image request, and it was on screen a frame
  /// ago — so the sweep composes its image inside that build instead of
  /// letting the row go blank until an asynchronous one lands
  /// (`_syncSweepBody`, 유저 절대규칙 「보이는 중이랑 결과랑 절대로 다르면 안
  /// 되」). 🪦A field of this name stood here until 2026-09-17 for the
  /// opposite direction — finding the image to hold over a cel ENTERING the
  /// slot, the first-activation stand-in — and went with it.
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

/// One non-active layer to composite around the interactive canvas.
class CanvasLayerImageRequest extends CanvasStackRow {
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

  /// Whether this row's image may be stored as its ink alone — asked of the
  /// same pose, blend and chain the draw is handed ([inkCropDrawsTheSame]).
  bool get inkSuffices => inkCropDrawsTheSame(
    pose: pose,
    blendMode: blendMode,
    effects: paintEffects,
  );
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
    this.onBufferBytes,
  });

  /// 🚨A cache the TEST owns, so it can read how each frame was built.
  /// An optimisation that never runs looks exactly like one that works —
  /// this session shipped two that did not — so the counters are part of
  /// the contract rather than a debugging aid.
  @visibleForTesting
  final DisplayBufferCache? debugBufferCache;

  /// Told how many bytes the display buffer holds, whenever that changes
  /// (and 0 when this view goes away). The memory census cannot reach a
  /// widget State, so the owner that CAN be reached writes it down — the
  /// same push the media viewers use.
  final void Function(int bytes)? onBufferBytes;

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
  final List<CompositeNode<CanvasStackRow>> nodes;

  /// Draws the ACTIVE layer's live surface wherever a
  /// [CanvasActiveLayerRow] sits in [nodes]; null paints nothing there
  /// (hosts that still mount their own interactive view).
  final BitmapSurfacePainter? activeSurfacePainter;

  /// Every cached-image request under [nodes], depth-first bottom → top.
  Iterable<CanvasLayerImageRequest> get layers sync* {
    for (final node in preorderNodes(nodes)) {
      // Still exhaustive: a new leaf kind fails to compile until it says
      // whether it is a cached image.
      switch (node) {
        case CompositeLeaf(payload: final CanvasLayerImageRequest request):
          yield request;
        case CompositeLeaf(payload: CanvasActiveLayerRow()):
        case CompositeGroup():
        case CompositeAdjustment():
          break;
      }
    }
  }

  /// The cels the ACTIVE rows under [nodes] are drawing
  /// ([CanvasActiveLayerRow.frameKey]) — what the next build's sweep reads
  /// off the widget it replaces, to know which cels were on screen as
  /// tiles a frame ago.
  Iterable<BrushFrameKey> get activeCels sync* {
    for (final node in preorderNodes(nodes)) {
      if (node case CompositeLeaf(
        payload: CanvasActiveLayerRow(:final frameKey?),
      )) {
        yield frameKey;
      }
    }
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
  final Map<BrushFrameKey, _HeldImage> _images = {};
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

  @override
  void initState() {
    super.initState();
    // ONE number for the census: the display buffer AND the bake beside it
    // are both this view holding a raster of itself (2026-09-11 — the
    // bake's visible-rect raster had been counted by nobody).
    _bufferCache.onHeldBytesChanged = (bytes) {
      _bufferBytes = bytes;
      _reportHeldBytes();
    };
    _bake.onHeldBytesChanged = _reportHeldBytes;
    // The first sweep runs in [didChangeDependencies]: the level it asks
    // images at needs the effective ratio, which is a dependency.
    InputInspector.visible.addListener(_rebuildForInspector);
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
      for (final entry in _images.entries) {
        oldWidget.imageCache.releasePin(entry.key, entry.value.quality);
        widget.imageCache.retainPin(entry.key, entry.value.quality);
      }
    }
    _syncImagesWithCache(leftTheActiveSlot: oldWidget.activeCels.toSet());
    unawaited(_ensureImages());
  }

  /// 🚨(v) — the recording of everything a stroke cannot change.
  final StaticCompositeBake _bake = StaticCompositeBake();

  /// The display buffer's last reported bytes — kept so a change in the
  /// bake can be reported in the same sum.
  int _bufferBytes = 0;

  void _reportHeldBytes() =>
      widget.onBufferBytes?.call(_bufferBytes + _bake.heldBytes);
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

  /// The buffer this view actually composites with — the one it made, or
  /// the one a test handed it. F-130's benchmark reads its miss counters
  /// off the REAL app, where nothing can pass `debugBufferCache` in: a hover
  /// that composites the whole buffer again is invisible in every pixel and
  /// only a counter can say it happened.
  @visibleForTesting
  DisplayBufferCache get debugBufferCacheInUse => _bufferCache;

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

  void _dropImage(BrushFrameKey key, _HeldImage held) {
    // A6: the pin travels with the clone — held pixels are declared
    // pixels, and the declaration ends exactly when the hold does.
    widget.imageCache.releasePin(key, held.quality);
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
  void _holdImage(BrushFrameKey key, _HeldImage held) {
    _images[key] = held;
    _imagesRevision += 1;
  }

  /// Handles a settle replaced ([_settleHeldImage]), kept until the build
  /// that replaces the painter drawing with them ([_releaseSettled]).
  final List<ui.Image> _superseded = <ui.Image>[];

  /// [image] takes the place of [held] for [key] WITHOUT moving
  /// [_imagesRevision] — the third way into [_images], and the only one that
  /// leaves the composite standing.
  ///
  /// 🚨★★★A SETTLE IS NOT A NEW PICTURE. The row a layer select drops out of
  /// the active slot is composed in the build as a DEFERRED image and
  /// settles one frame later into the plain snapshot of the same picture
  /// ([LayerFrameImage.content] is how the cache says so). Taken as a new
  /// picture, it bumped the revision, broke the composite key, and the whole
  /// display buffer rastered a second time for pixels it already had —
  /// 🔬measured 2026-09-23, F-130 `solo` arm, 24 drawn rows: two full buffer
  /// rasters per select, the second one pure repetition (229ms of 520 in the
  /// test VM's software raster). 유저 (via the board/integration session's
  /// measurement, board `I-19`): 「솔로 버벅임」, layer select included.
  ///
  /// ⛔The revision's own law still holds: a recording never outlives a
  /// clone it references. The replaced clone is not disposed here — the
  /// painter on screen draws with it until the next build, which the
  /// settle asks for — so it is PARKED ([_superseded]) and goes in that
  /// build, with every bake slot that may replay it ([_releaseSettled]).
  ///
  /// ⚠️What stays behind is the display buffer's kept image: it drew the
  /// deferred picture and pins it (`raster_picture.dart`) until the buffer
  /// is next composed — one picture of the row held that much longer, in
  /// place of a whole-buffer raster.
  void _settleHeldImage(
    BrushFrameKey key,
    _HeldImage held,
    LayerFrameImage image,
  ) {
    _superseded.add(held.clone);
    _images[key] = (
      source: image.image,
      clone: image.image.clone(),
      worldRect: held.worldRect,
      extent: held.extent,
      revision: held.revision,
      quality: held.quality,
      content: held.content,
    );
  }

  /// Lets the handles a settle replaced go, in the build whose painter
  /// draws with their successors — and with them the bake's slots, which
  /// may have recorded one ([StaticCompositeBake]: a picture that outlives
  /// a dispose replays a dead handle).
  void _releaseSettled() {
    if (_superseded.isEmpty) {
      return;
    }
    for (final clone in _superseded) {
      clone.dispose();
    }
    _superseded.clear();
    _bake.invalidate();
  }

  @override
  void dispose() {
    InputInspector.visible.removeListener(_rebuildForInspector);
    for (final entry in _images.entries) {
      widget.imageCache.releasePin(entry.key, entry.value.quality);
      entry.value.clone.dispose();
    }
    _images.clear();
    _releaseSettled();
    // The buffer and the bake go with this view; the books must not keep
    // charging for a canvas nobody is looking at any more. Unhooked FIRST,
    // or disposing them would report their last bytes after this zero.
    _bufferCache.onHeldBytesChanged = null;
    _bake.onHeldBytesChanged = null;
    widget.onBufferBytes?.call(0);
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
  /// once the editor goes idle after a stroke) or, when the switch beats
  /// the prerender, has its image composed right here
  /// ([leftTheActiveSlot]); the async pass alone would paint it one frame
  /// late at best: the artwork visibly vanished and reappeared. The
  /// just-activated layer leaves the same frame, so it never double-draws
  /// under the interactive view.
  ///
  /// [leftTheActiveSlot] is the cels the widget this build replaces was
  /// drawing as ACTIVE rows ([CanvasLayerStackView.activeCels]) — empty
  /// for the first sweep, which replaces nothing.
  void _syncImagesWithCache({
    Set<BrushFrameKey> leftTheActiveSlot = const {},
  }) {
    labProbe(
      'layerStackSyncSweep(${widget.layers.length})',
      () => _syncSweepBody(leftTheActiveSlot),
    );
  }

  /// Holds [image] for [key] unless it is the one already held — the pin,
  /// the clone and the revision together — and says whether the held set
  /// changed, a settle's new handle included ([_settleHeldImage]). The sync
  /// sweep and the async pass both adopt through here.
  bool _adoptImage(
    BrushFrameKey key,
    LayerFrameImage image,
    int? revision,
    PlaybackQuality quality,
  ) {
    final held = _images[key];
    if (held != null && identical(held.source, image.image)) {
      return false;
    }
    if (held != null && identical(held.content, image.content)) {
      _settleHeldImage(key, held, image);
      // Changed, so the next build hands the painter the new handle and
      // lets the old one go. It repaints nothing: the rows match by
      // content, and the composite keeps what it drew.
      return true;
    }
    if (held != null) _dropImage(key, held);
    widget.imageCache.retainPin(key, quality);
    _holdImage(key, (
      source: image.image,
      clone: image.image.clone(),
      worldRect: image.worldRect,
      extent: image.extent,
      revision: revision,
      quality: quality,
      content: image.content,
    ));
    return true;
  }

  /// The quality — the level of the display's pyramid — this view asks the
  /// other layers' images at: the level the display buffer composes at
  /// ([displayLevelOf]), read from the viewport and the effective ratio.
  /// Full at or above 100%, as always; half at 50–100% on screen, quarter
  /// below, so a level buffer draws them 1:1 instead of reducing a
  /// canvas-resolution picture by more than a bilinear window can hold.
  PlaybackQuality get _quality => PlaybackQuality.forLevel(
    displayLevelOf(displayScaleOf(widget.viewport.zoom, _devicePixelRatio)),
  );

  /// The effective ratio this view composes at ([EffectiveDevicePixelRatio]),
  /// read where dependencies change — so [_quality] is right from the first
  /// sweep, which therefore runs there and not in [initState].
  double _devicePixelRatio = 1;
  bool _dependenciesSeen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = EffectiveDevicePixelRatio.of(context);
    if (_dependenciesSeen && ratio == _devicePixelRatio) {
      return;
    }
    _dependenciesSeen = true;
    _devicePixelRatio = ratio;
    _syncImagesWithCache();
    unawaited(_ensureImages());
  }

  /// Whether [key]'s cel was on screen a frame ago and is about to be
  /// asked for as an image it may not have: it just LEFT the active slot,
  /// or the image this row holds is of the cel before an EDIT
  /// (`sourceRevision` moves on every surface write and on nothing else).
  /// Such a row's image is composed inside the sweep
  /// ([LayerFrameImageCache.prepareSyncOrNull]'s `makePictures`).
  bool _wasOnScreen(
    BrushFrameKey key,
    int? revision,
    Set<BrushFrameKey> leftTheActiveSlot,
  ) {
    final held = _images[key];
    return leftTheActiveSlot.contains(key) ||
        (held != null && held.revision != revision);
  }

  void _syncSweepBody(Set<BrushFrameKey> leftTheActiveSlot) {
    final wanted = <BrushFrameKey>{
      for (final layer in widget.layers) layer.frameKey,
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
      // Valid cache image, or a synchronous per-tile compose — either way
      // the artwork paints THIS frame. A cel that was on screen a frame ago
      // is composed whatever it takes ([_wasOnScreen]); any other row only
      // when it is free, and a true cold miss falls to the async pass.
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
      final quality = _quality;
      final LayerFrameImage? image;
      try {
        image = widget.imageCache.prepareSyncOrNull(
          key: layer.frameKey,
          canvasSize: widget.canvasSize,
          quality: quality,
          sourceEffects: layer.sourceEffects,
          makePictures: _wasOnScreen(
            layer.frameKey,
            revision,
            leftTheActiveSlot,
          ),
          inkSuffices: layer.inkSuffices,
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
        //
        // 🚨Since 2026-09-17 an edited row does not usually get HERE: the
        // same mismatch is what makes the prepare above compose the new
        // picture inside this sweep ([_wasOnScreen]), so the frame after
        // an edit shows the edit — not the old drawing, and not the blank
        // this drop used to leave until the async build landed (「빈 것이
        // 정직하다」 was the best answer while a picture could not be had in
        // the frame). What still arrives is an edited cel with nothing to
        // compose — emptied, or recorded at another canvas size — and for
        // that one the drop is simply true.
        final held = _images[layer.frameKey];
        if (held != null && held.revision != revision) {
          _dropImage(layer.frameKey, _images.remove(layer.frameKey)!);
        }
        continue;
      }
      _adoptImage(layer.frameKey, image, revision, quality);
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
    final quality = _quality;
    final LayerFrameImage? image;
    try {
      image = await widget.imageCache.prepare(
        key: layer.frameKey,
        canvasSize: widget.canvasSize,
        quality: quality,
        sourceEffects: layer.sourceEffects,
        inkSuffices: layer.inkSuffices,
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
    return _adoptImage(layer.frameKey, image, revision, quality);
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
  /// saveLayer — [mapCompositeLeaves] carries that law for every route).
  List<CompositeNode<_PaintRow>> _resolvedTree(
    List<CompositeNode<CanvasStackRow>> nodes,
  ) => mapCompositeLeaves(nodes, _paintRowFor);

  _PaintRow? _paintRowFor(CanvasStackRow row) {
    switch (row) {
      case final CanvasLayerImageRequest request:
        final held = _images[request.frameKey];
        if (held == null) {
          return null;
        }
        return _PaintImage(
          image: held.clone,
          content: held.content,
          worldRect: held.worldRect,
          extent: held.extent,
          opacity: request.opacity,
          blendMode: request.blendMode,
          pose: request.pose,
          anchorPoint: request.anchorPoint,
          tint: request.tint,
          // The PAINT half only — the keys are already in the image the
          // cache handed back.
          effects: request.paintEffects,
        );
      case final CanvasActiveLayerRow active:
        if (widget.activeSurfacePainter == null) {
          return null;
        }
        return _PaintActiveSurface(
          opacity: active.opacity,
          blendMode: active.blendMode,
          pose: active.pose,
          anchorPoint: active.anchorPoint,
          // The PAINT half only — like the cached row above. A leading
          // key is already on the surface this node draws.
          effects: active.paintEffects,
        );
    }
  }

  /// 🔬F-67 (2026-09-11): where this stack's top-left lands on the DEVICE
  /// grid, printed to the input inspector once per change.
  ///
  /// 유저 F-67: 「툴을 바꾸거나 선을 그리기 시작하거나 화면을 팬으로 이동할때,
  /// 그 때만 … 일부 정해진 픽셀이 반픽셀 움직였다가 돌아오는 현상」, at zoom
  /// ≥ 100% on the drawing. Three mechanisms were measured and cleared in
  /// the test shell — the route flip inside the buffer (byte-identical), the
  /// pan snap (whole device pixels), the display filter (`none` at ≥1) — and
  /// the one left is the one a shell cannot see: THIS widget's own device
  /// offset, which layout owns. R11 put it on the grid at 1.25 and 1.35 in
  /// the shell; the real app's panel set, ruler widths and UI scale are
  /// what the shell does not have. When the fraction here is not 0 on the
  /// frame the pixels move, #1100's mechanism (a stable picture replayed at
  /// an integral offset, a live repaint at the fractional one) is the
  /// cause; when it is 0, it is not, and the search moves on. Either way it
  /// is a number rather than a guess.
  ///
  /// Post-frame, because layout has to have run; deduplicated, because a
  /// probe that prints every frame is one nobody reads; behind the
  /// inspector's visibility, because release builds are the ones that get
  /// reported and this must cost nothing when it is off.
  void _noteBoundaryOnGrid(BuildContext context) {
    if (!InputInspector.visible.value) {
      return;
    }
    final ratio = EffectiveDevicePixelRatio.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) {
        return;
      }
      final device = box.localToGlobal(Offset.zero) * ratio;
      String fraction(double v) => (v - v.floorToDouble()).toStringAsFixed(3);
      // PINNED, not noted: a layout fact, read whenever the card is looked
      // at — the noted line scrolled off under the paint probes before the
      // hands-on screenshot was taken.
      InputInspector.pin(
        'grid',
        'grid device=(${device.dx.toStringAsFixed(2)}, '
        '${device.dy.toStringAsFixed(2)}) '
        'frac=(${fraction(device.dx)}, ${fraction(device.dy)}) '
        'ratio=${ratio.toStringAsFixed(3)}',
      );
    });
  }

  /// The card is opened AFTER this view settled, most of the time — and a
  /// layout fact is only measured on a build. So a rebuild follows the
  /// toggle, and the pin is there when the card is.
  void _rebuildForInspector() {
    if (InputInspector.visible.value && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _noteBoundaryOnGrid(context);
    final nodes = _resolvedTree(widget.nodes);
    // This build's painter draws with a settle's new handles, so the ones
    // they replaced can go ([_settleHeldImage]).
    _releaseSettled();
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
    // `filterQuality` lands when the buffer is DRAWN, not inside it, and
    // group rasters inside run at the buffer's own scale.
    // `BitmapSurfacePainter` reads its viewport only in the standalone
    // `paint()`, never in `paintContentInto`; `layerPoseViewportWrapMatrix`
    // belongs to the brush panel's `Transform`, not to any composite route.
    //
    // 🚨WHAT A RECORDING DOES CARRY OF THE ZOOM IS IN THE KEY (2026-09-16,
    // closing defect candidate ⓐ of the tile-commit-path audit): the LEVEL
    // the buffer composes at ([displayLevelOf] — the recordings draw level
    // images 1:1 and the backdrop raster is made in level pixels), and the
    // filter class the leaf draws take ([filterQualityForDisplayScale]).
    // Both are coarse functions of the zoom — a step at 100% and at each
    // halving — so a pan or a zoom inside a level keeps every slot, and a
    // slot recorded at one level never replays at another.
    //
    // ⇒ Panning or zooming REPAINTS (shouldRepaint still compares the
    // viewport, and the CTM did change) but no longer RE-COMPOSITES while
    // the extent and the level hold — which is exactly the posture where
    // the page fits the screen and the buffer is at its biggest.
    final displayScale = displayScaleOf(
      widget.viewport.zoom,
      EffectiveDevicePixelRatio.of(context),
    );
    final compositeKey = Object.hash(
      _imagesRevision,
      widget.canvasSize,
      widget.paintPaper,
      widget.paperBackground,
      _treeSignature(nodes),
      displayLevelOf(displayScale),
      filterQualityForDisplayScale(displayScale),
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
      //   ⛔(R13) That framing covers the raster-cache half ONLY, and the
      //   device contradicted it as a whole: the F-67 hop happened at 100%
      //   scaling and on the iPad too. The sampling tie R13 names below
      //   hops between ANY two paths that resolve it differently — cached
      //   vs live, buffer vs walk — and it is closed at the render snap,
      //   not here. Read the two symptoms as the layout-chain half only.
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
      //
      //  · R12 (2026-09-11) — the hint is BACK on the two DRAWING pictures
      //    (this one and `BrushEditCanvasView`'s), and only those. F-67
      //    (유저 09-10): the hop returned — pen-down/up, tool change, pan,
      //    at zoom >= 100% only — and the hands-on read the pinned probe
      //    on the frame it happened: `grid device=(40, 40) frac=(0.000,
      //    0.000) ratio=1.000`. The chain was on the grid, at 100%
      //    scaling — the case the block above says CANNOT hop. And the
      //    shell probe (`the_canvas_raster_holds_still_through_a_stroke`)
      //    says this boundary's OWN raster is byte-identical through
      //    pen-down, mid-stroke and pen-up at 110%. So what flips is not
      //    our picture and not the translation: the engine's cached raster
      //    of this display list differs from its live one for a reason the
      //    snap theory does not name, and the only switch that makes the
      //    flip impossible is the one #1103 device-verified — no cache
      //    entry, so nothing to flip into. What the cache bought here is
      //    gone anyway: with the display buffer this display list is the
      //    paper and ONE image blit, replayed for next to nothing. The
      //    playback pictures keep the cache — they change every tick and a
      //    hold is the case where caching is a win, not a hop.
      //
      //  · R13 (2026-09-11, the same day) — the hint is GONE again, and this
      //    time the mechanism is measured rather than argued. The device
      //    confirmed a prediction zoom by zoom: the hop lives exactly at the
      //    scales z = p/q with p odd and q even (105·110·115·125·130·135·
      //    150·175·250%) and at none of the others (100·120·140·160·180·
      //    200·300·400%). Above 1:1 the display samples at `none`, device
      //    pixel i reads texel `floor((i + 0.5 - t) / s)`, and a WHOLE-pixel
      //    render translation t puts one column in every q exactly on a
      //    texel boundary — a tie that float rounding decides, differently
      //    on the engine's cached and live paths. The fix is the snap's
      //    phase (`samplingPhaseFor` in `viewport_canvas_transform.dart`):
      //    the translation lands on whole + phase pixels, every sample stays
      //    off the boundary, and cached and live read the same texel. With
      //    no tie left there is nothing for this hint to hide, so the
      //    picture is cacheable like every other and R11's reasoning about
      //    the layout chain stands as it was.
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
          // The display scale is zoom·DPR, and the DPR is the one the
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

/// A cel image the stack holds: the cache's image, our clone of it (which
/// survives the cache letting go), the canvas-space rect it covers, the
/// revision it was built from, and the quality — the level of the pyramid
/// — it was asked at, which is what its pin is released at.
typedef _HeldImage = ({
  ui.Image source,
  ui.Image clone,
  Rect worldRect,
  // The rect the whole content image covers ([LayerFrameImage.extent]).
  Rect extent,
  int? revision,
  PlaybackQuality quality,
  // What the pixels ARE ([LayerFrameImage.content]) — what the paint tree
  // and the composite key compare, so a settle changes neither.
  Object content,
});

/// The painter's own node shape: the request tree with images resolved.
sealed class _PaintRow {
  const _PaintRow();

  /// Whether [other] draws the same picture as this row — the repaint
  /// gate's question, field by field, images by IDENTITY.
  bool matches(_PaintRow other);

  /// 🚨(v) — [matches] as a VALUE, for the bake's key.
  ///
  /// ⛔It must fold in exactly what [matches] compares, and it lives on the
  /// same node so the two are read together: a field added to a node and
  /// to [matches] but not to this one makes the recordings outlive the
  /// change they should have ended. A new node type has to write both —
  /// the sealed class demands them — which is the tripwire the comparison's
  /// `default:` arm used to be (R6b).
  ///
  /// ⚠️Images fold in by IDENTITY (`identityHashCode`), matching
  /// `identical()` in [matches] — two different decodes of the same
  /// artwork are two different pictures to draw.
  int get signature;
}

/// How many ops the engine replays to draw [list] — one per leaf, one
/// more per group's `saveLayer`. This is the S7 predicate's input: it is
/// a static fact of the node tree, so the backdrop decision needs no
/// clock and cannot flap within a key.
int _replayOpsOf(List<CompositeNode<_PaintRow>> list) {
  var ops = 0;
  for (final node in list) {
    ops += switch (node) {
      CompositeLeaf<_PaintRow>() => 1,
      CompositeGroup<_PaintRow>(:final children) => 1 + _replayOpsOf(children),
      CompositeAdjustment<_PaintRow>(:final children) =>
        1 + _replayOpsOf(children),
    };
  }
  return ops;
}

final class _PaintImage extends _PaintRow {
  const _PaintImage({
    required this.image,
    required this.content,
    required this.worldRect,
    required this.extent,
    required this.opacity,
    required this.blendMode,
    required this.pose,
    required this.anchorPoint,
    required this.tint,
    required this.effects,
  });

  final ui.Image image;

  /// The rect the whole content image covers — [worldRect] itself, or more
  /// when the cache stored the ink alone ([LayerFrameImage.extent]). What the
  /// row stands for when a folder asks how far its buffer reaches.
  final Rect extent;

  /// What [image]'s pixels ARE ([LayerFrameImage.content]) — the one thing
  /// [matches] and [signature] compare about the picture.
  ///
  /// ⛔Not `identical(image, …)`, which is what they compared until
  /// 2026-09-23: a settle hands over a new handle to the same pixels, and
  /// the handle's identity is what broke the composite key and rastered the
  /// display buffer a second time
  /// ([_CanvasLayerStackViewState._settleHeldImage]). Every compose makes a
  /// new token, so a new PICTURE still moves both.
  final Object content;
  final Rect worldRect;
  final double opacity;
  final LayerBlendMode blendMode;
  final TransformPose? pose;
  final CanvasPoint? anchorPoint;
  final int? tint;
  final List<ResolvedLayerEffect> effects;

  @override
  bool matches(_PaintRow other) =>
      other is _PaintImage &&
      identical(content, other.content) &&
      worldRect == other.worldRect &&
      extent == other.extent &&
      opacity == other.opacity &&
      blendMode == other.blendMode &&
      pose == other.pose &&
      anchorPoint == other.anchorPoint &&
      tint == other.tint &&
      // R6: an effect edit changes the pixels and nothing else — leaving
      // it out here would repaint nothing (the whole tree still "matches")
      // and the canvas would go stale.
      listEquals(effects, other.effects);

  @override
  int get signature => Object.hash(
    identityHashCode(content),
    worldRect,
    extent,
    opacity,
    blendMode,
    pose,
    anchorPoint,
    tint,
    Object.hashAll(effects),
  );
}

/// 🪦The first-activation stand-in (device report 2026-08-17 → 2026-09-17)
/// held the just-deactivated route's layer image over the active slot
/// until every tile of the promoted surface had decoded: activation
/// promotes a file-backed cel to a surface of all-fresh tile objects, and
/// the picture disappeared for one frame per layer. A committed tile
/// pictures itself inside the paint now, so the walk is whole on the
/// activation frame itself and nothing stands in. (The active row's
/// `frameKey` named the cel so this could find the image to hold; it has
/// another reader now — see [CanvasActiveLayerRow.frameKey].)
final class _PaintActiveSurface extends _PaintRow {
  const _PaintActiveSurface({
    required this.opacity,
    required this.blendMode,
    required this.pose,
    required this.anchorPoint,
    required this.effects,
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

  // ㊱: the alpha belongs in the repaint gate too — a slider drag changes
  // NOTHING else about this node, so leaving it out would paint the new
  // value only when some unrelated fact moved (the ㉘/㉞ shape: the value
  // is right and the gate says "unchanged").
  @override
  bool matches(_PaintRow other) =>
      other is _PaintActiveSurface &&
      opacity == other.opacity &&
      blendMode == other.blendMode &&
      pose == other.pose &&
      anchorPoint == other.anchorPoint &&
      listEquals(effects, other.effects);

  @override
  int get signature =>
      Object.hash(opacity, blendMode, pose, anchorPoint, Object.hashAll(effects));
}

/// Whether [a] draws the same picture as [b] — the STRUCTURE compared
/// here, the painted row's own fields by [_PaintRow.matches].
bool _nodesMatch(CompositeNode<_PaintRow> a, CompositeNode<_PaintRow> b) =>
    switch (a) {
      CompositeLeaf<_PaintRow>(:final payload) =>
        b is CompositeLeaf<_PaintRow> && payload.matches(b.payload),
      CompositeGroup<_PaintRow>(
        :final children,
        :final opacity,
        :final blendMode,
        :final effects,
      ) =>
        b is CompositeGroup<_PaintRow> &&
            opacity == b.opacity &&
            blendMode == b.blendMode &&
            listEquals(effects, b.effects) &&
            _treesMatch(children, b.children),
      CompositeAdjustment<_PaintRow>(
        :final children,
        :final effects,
        :final mix,
      ) =>
        b is CompositeAdjustment<_PaintRow> &&
            mix == b.mix &&
            listEquals(effects, b.effects) &&
            _treesMatch(children, b.children),
    };

/// 🚨(v) — [_nodesMatch] as a VALUE, for the bake's key.
///
/// ⛔It must fold in exactly what [_nodesMatch] compares, and it sits
/// directly beside it so the two are read together: a field compared there
/// and left out here makes the recordings outlive the change they should
/// have ended.
int _nodeSignature(CompositeNode<_PaintRow> node) => switch (node) {
  CompositeLeaf<_PaintRow>(:final payload) => payload.signature,
  CompositeGroup<_PaintRow>(
    :final children,
    :final opacity,
    :final blendMode,
    :final effects,
  ) =>
    Object.hash(
      opacity,
      blendMode,
      Object.hashAll(effects),
      _treeSignature(children),
    ),
  CompositeAdjustment<_PaintRow>(
    :final children,
    :final effects,
    :final mix,
  ) =>
    Object.hash(mix, Object.hashAll(effects), _treeSignature(children)),
};

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

/// 🪦`debugActiveSlotDraw` (F-67, 2026-09-10 → 2026-09-17) said which of
/// the active slot's draws a paint used, because the FLAT projection, the
/// first-activation STAND-IN and the TILES did not sample alike and a
/// comparison could not say which it had compared. The tiles are the one
/// draw left, so there is nothing to tell apart.

/// The CANVAS-SPACE rect [node] actually covers, its own pose applied.
///
/// 🚨THIS IS WHAT KEEPS THE COMPOSITE AT CANVAS RESOLUTION AT EVERY ZOOM.
///
/// The buffers used to be bounded by `pasteboard ∩ visibleRect`. Zoom out
/// far enough and that rect spans the whole pasteboard — 5×5 canvases then,
/// 11700×8270 on a 2340×1654 page — which blew past [_maxBufferSide] and
/// dropped the paint onto the fallback past the cap (since H2's 3×3,
/// 2026-08-22, that page's pasteboard is 7020×4962 and fits; a page more
/// than 2730 on a side still does not). That fallback is how the editing
/// canvas stopped compositing the way playback, the camera and the export
/// do (유저 2026-08-15 accepted it at the time: 「무릎 아래는
/// 균일 필터, 겹침 색차 수용」 — accepted because bounding by the view was
/// the only tool on the table; the screen-resolution "knee" that served the
/// fallback from 2026-08-16 went with the level buffer on 2026-09-16, and
/// past the cap the direct walk is the net).
///
/// ★Content is not the pasteboard. For a cached row it is
/// [surfaceContentWorldRect]'s answer — the canvas rect unioned with the
/// tiles that actually exist — so an ordinary page bounds to 2340×1654 and
/// never reaches the cap. The fallback stops being reachable, and one
/// resolution serves every zoom. For the ACTIVE row it is whatever the caller
/// measures it by ([activeSurfaceExtent]): everything the slot draws for the
/// display buffer — its committed surface alone cut every live draw at the
/// edge of the ink already landed (F-85) — and that committed surface for the
/// bake, which never records the live slot (review 2026-09-15).
///
/// ⛔RECOMPUTED, NEVER ACCUMULATED. A rect that only ever grew would be the
/// high-water mark of everything you had done — the "sticky / containment
/// 매칭 버퍼 rect" the composite plan rejects by name.
Rect _paintNodeExtent(
  CompositeNode<_PaintRow> node, {
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
    // The rect the row stands for, not the part of it that holds the ink: a
    // folder's buffer — and so where its blur is worked out — reaches as far
    // as it did when every image was whole.
    case CompositeLeaf(
      payload: _PaintImage(:final extent, :final pose, :final anchorPoint),
    ):
      return posed(extent, pose, anchorPoint);
    case CompositeLeaf(
      payload: _PaintActiveSurface(:final pose, :final anchorPoint),
    ):
      return posed(activeSurfaceExtent(), pose, anchorPoint);
    case CompositeGroup(:final children):
    case CompositeAdjustment(:final children):
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
  /// The last emitted geometry line — the dedupe key, held across frames.
  static String? lastLine;

  /// The last emitted buffer-counter cadence key (full composes, patches
  /// in 32s, carries) — the counters line is deduped apart from the
  /// geometry line so a stroke can be watched without touching the zoom.
  static String? lastCounters;

  /// Paints per zoom bucket (percent, 10% steps), counted while the
  /// inspector is visible. Every byte figure in the composite plan hinges
  /// on "what zoom is actually worked at", and nobody has measured a
  /// distribution — "83%" is one observation and "400% is the working
  /// posture" is a sentence in a brief. This counter turns either into a
  /// fact.
  static final Map<int, int> zoomHistogram = <int, int>{};

  static void reset() {
    lastLine = null;
    lastCounters = null;
    // Every dedupe key the paint pass keeps — the T12 line's too, or a
    // test that runs after another one sees no T12 line at all: the
    // probes are static on purpose (a painter is rebuilt every frame).
    _LayerStackPainter._lastStackProbe = null;
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
         repaint: Listenable.merge(<Listenable?>[
           activeSurfacePainter,
           floatOverlay,
         ]),
       );

  /// The last line the T12 probe in [paint] emitted. Static: a
  /// [CustomPainter] is a fresh object every frame, so an instance field
  /// would only ever compare against itself.
  static String? _lastStackProbe;

  final List<CompositeNode<_PaintRow>> nodes;

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

  /// The EFFECTIVE ratio at build time (monitor × UI scale) — the display
  /// scale's axis (`zoom·dpr`, [displayScaleOf]). A monitor move re-runs
  /// the build, so a fresh painter always carries the current value.
  final double devicePixelRatio;

  /// The largest buffer side worth allocating, in the buffer's own pixels.
  ///
  /// Not a quality setting — the safety net (유저 결정 2026-09-16). Below
  /// 100% the buffer is a level of the artwork and at most 4× the screen,
  /// so this binds only on a window past 16384 device pixels; at or above
  /// 100% only on one past the cap itself. Past it the direct walk draws,
  /// which is always correct and costs only the sampling law.
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
  void paint(Canvas canvas, Size size) => labProbe(
    'layerStackPaint',
    // The paint pass (Round 6): one paint of the stack, as its own object,
    // constructed PER PAINT — its geometry fields are `late final`, and a
    // painter can be asked to paint more than once.
    () => _LayerStackPaintPass(this).paint(canvas, size),
  );

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

  /// What the live surface looks like NOW, per coordinate — or null when
  /// that cannot be said: the same three cases [_bufferKey] refuses to
  /// cache for, plus a surface whose tiles cannot be compared to the ones
  /// a buffer was made from.
  ///
  /// The overlay's tiles carry the stroke in flight — but they ACCUMULATE
  /// for the stroke's whole life (nothing leaves the map until pen-up), so
  /// "every overlay coordinate" is the bounding box of the WHOLE STROKE by
  /// the third dab: a long line paid its full length again on every step.
  /// Identity per coordinate instead, exactly like the committed tiles —
  /// the overlay replaces a tile's image only when a dab touched it, so an
  /// unchanged image object IS "this tile did not move".
  ///
  /// Committed tiles: a commit replaces the tile — an identity change on
  /// its coordinate.
  ///
  /// 🚨★★★**AND THIS WALK IS PER TILE, NOT PER SURFACE.** The rect is what
  /// gets repainted, so a coordinate missed here is a coordinate left
  /// showing the frame before — a stroke's commit swaps the tiles it
  /// touched and nothing else, and only a walk that sees each tile's
  /// identity can name exactly those. (Until 2026-09-17 the walk also had
  /// to see each tile's PICTURE, because a decode could land between two
  /// paints and change what a tile drew; a picture is made from its bytes
  /// inside the paint now, so the tile's identity is the whole story.)
  LiveSurfaceTokens? _liveSurfaceTokens() {
    final surfacePainter = activeSurfacePainter;
    if (surfacePainter == null || !surfacePainter.drawsOnlyFromPublishedState) {
      return null;
    }
    final overlay = surfacePainter.overlayModel;
    if (!_liveSurfaceIsSpatiallyStable(nodes)) {
      return null;
    }
    // F-130: the stamp's ghost is part of what the live surface looks like
    // (F-33 draws it inside this painter), so it is part of the tokens —
    // by value, with the rect it covers, so a hover can be patched.
    final ghost = surfacePainter.stampPreview?.value;
    return (
      overlay: <TileCoord, Object>{
        ...overlay?.tileImages ?? const <TileCoord, ui.Image>{},
      },
      tiles: <TileCoord, Object>{
        for (final entry in surfacePainter.surface.tiles.entries)
          entry.key: entry.value,
      },
      ghost: ghost == null ? null : (value: ghost, rect: ghost.canvasRect),
    );
  }

  /// Where the LIVE surface changed since the base this paint will draw
  /// was made, in canvas space — measured against [since], the tokens
  /// stored WITH that base — plus what the surface looks like now, for the
  /// buffer this paint is about to store.
  ///
  /// 🎯[since] IS THE BASE'S, NOT THE HEAD'S. The cache's real base is a
  /// paint or three older than its head (`DisplayBufferCache._realBase`),
  /// so a dirty rect measured from the head's tokens would leave the steps
  /// between them out of the patch — a stroke with holes in it. The
  /// caller asks the cache which base it will draw and passes that base's
  /// tokens; the head's own tokens are only the fallback for a compose
  /// that starts from nothing.
  ///
  /// 🚨`located: false` is the safe answer and it costs only a full
  /// re-raster, which is what every paint did before the cache existed. It
  /// is the answer whenever the change cannot be located
  /// ([_liveSurfaceTokens]), and whenever nothing is kept to measure from —
  /// a cold start, or a buffer stored without a snapshot.
  ///
  /// ⛔The rect is INFLATED by one pixel. A dab writes whole texels, but the
  /// composite around it does not have to land on them — a posed sibling or
  /// a rounded edge can put ink a fraction over the line, and a patch that
  /// trusted the exact rect would leave a hairline of the previous frame.
  /// One pixel is cheap and the alternative is a class of bug that only
  /// shows on some zoom levels.
  ({bool located, Rect? dirty, LiveSurfaceTokens? now})
  _liveDirtyCanvasRect({required LiveSurfaceTokens since}) {
    final now = _liveSurfaceTokens();
    if (now == null) {
      return (located: false, dirty: null, now: null);
    }
    final kept = since;
    // Nothing to compare against — the first paint after a cold start, or
    // a kept image made without a snapshot. ⛔THE SENTINEL, BY IDENTITY,
    // and not `kept.tiles.isEmpty` as it used to read: an empty cel's
    // snapshot is empty too, and it is a perfectly good base — the stamp's
    // usual target is an empty cel, and reading its snapshot as 「none」
    // refused the ghost's patch on every move there (F-130, measured).
    if (identical(kept, noLiveSurfaceTokens)) {
      return (located: false, dirty: null, now: now);
    }
    var dirty = tileCoordsWorldRect(
      _movedCoords(
        kept.overlay,
        now.overlay,
      ).followedBy(_movedCoords(kept.tiles, now.tiles)),
      activeSurfacePainter!.surface.tileSize,
    );
    // F-130: a ghost that moved (or came, or went) dirties where it WAS and
    // where it IS — the old place has to be repainted without it.
    final ghostWas = kept.ghost;
    final ghostNow = now.ghost;
    if (ghostWas?.value != ghostNow?.value) {
      for (final ghost in [ghostWas, ghostNow]) {
        if (ghost != null) {
          dirty = dirty?.expandToInclude(ghost.rect) ?? ghost.rect;
        }
      }
    }
    return (located: true, dirty: dirty?.inflate(1), now: now);
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
  ///  * the overlay's tile images and its stamp, by identity, which is how
  ///    an in-flight stroke reaches the canvas at all.
  ///
  /// 🪦Until 2026-09-17 there were two more: the tiles' DECODED images (a
  /// decode arriving changed the screen while the tile it came from never
  /// moved) and the stand-in and settling passes, which redrew on their own
  /// clock. A tile's picture is made from its bytes inside the paint now, so
  /// nothing arrives later and nothing stands in.
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
    // surface's identity says the same thing for free: a tile's picture
    // is made from its bytes inside the paint that needs it, so what a
    // surface draws can change only when the surface does.
    var live = identityHashCode(surfacePainter.surface);
    final overlay = surfacePainter.overlayModel;
    if (overlay != null) {
      for (final entry in overlay.tileImages.entries) {
        live = Object.hash(live, entry.key, identityHashCode(entry.value));
      }
    }
    // 🚨★★★F-33: the stamp ghost is part of what this buffer would hold, so
    // it has to be part of the key. Left out, the buffer caches a frame
    // WITHOUT the ghost and the ghost then stops following the pointer —
    // the silent failure this whole key exists to prevent.
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
  static bool _liveSurfaceIsSpatiallyStable(
    List<CompositeNode<_PaintRow>> list,
  ) {
    for (final node in list) {
      if (node case CompositeLeaf(payload: final _PaintActiveSurface active)) {
        return active.pose == null &&
            !resolvedEffectsSpreadPixels(active.effects);
      }
      if (node is CompositeGroup<_PaintRow> &&
          node.children.any(_enclosesActiveSurface)) {
        return !resolvedEffectsSpreadPixels(node.effects) &&
            _liveSurfaceIsSpatiallyStable(node.children);
      }
      if (node is CompositeAdjustment<_PaintRow> &&
          node.children.any(_enclosesActiveSurface)) {
        return !resolvedEffectsSpreadPixels(node.effects) &&
            _liveSurfaceIsSpatiallyStable(node.children);
      }
    }
    return false;
  }

  /// Whether the live surface is this node, or anywhere inside it.
  static bool _enclosesActiveSurface(CompositeNode<_PaintRow> node) =>
      switch (node) {
        CompositeLeaf(payload: _PaintActiveSurface()) => true,
        CompositeGroup(:final children) =>
          children.any(_enclosesActiveSurface),
        CompositeAdjustment(:final children) =>
          children.any(_enclosesActiveSurface),
        CompositeLeaf(payload: _PaintImage()) => false,
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
        // The display scale — and the level — read this: a monitor move
        // must repaint, not stretch the old buffer.
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        !identical(oldDelegate.activeSurfacePainter, activeSurfacePainter) ||
        !_treesMatch(oldDelegate.nodes, nodes);
  }
}

/// Whether [a] and [b] draw the same picture, node for node
/// ([_nodesMatch]).
bool _treesMatch(
  List<CompositeNode<_PaintRow>> a,
  List<CompositeNode<_PaintRow>> b,
) => listsMatch(a, b, _nodesMatch);

/// [_treesMatch] as a VALUE, for the bake's key — the nodes' signatures
/// folded in order ([_nodeSignature]).
int _treeSignature(List<CompositeNode<_PaintRow>> list) {
  var hash = list.length;
  for (final node in list) {
    hash = Object.hash(hash, _nodeSignature(node));
  }
  return hash;
}

/// How many paints have fallen to the direct walk because the buffer would
/// have exceeded the editing stack's buffer cap — the safety net.
///
/// ★A COUNTER AND NOT A COMMENT. "Content bounds and the level keep every
/// ordinary view under the cap" is a claim about a number, and this is the
/// number — the one place the editing canvas stops compositing the way
/// playback, the camera and the export do.
@visibleForTesting
int debugCappedFallbacks = 0;
