import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/tree_nodes.dart';
import '../../core/collection_equality.dart';
import '../../services/cut_frame_composite_plan.dart'
    show CutFrameCompositeLayer;
import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../models/composite_tree.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/playback_quality.dart';
import '../../models/project_background.dart';
import '../../models/tile_coord.dart';
import '../debug/input_inspector.dart';
import '../../core/dev_profile.dart';
import '../playback/frame_picture_store.dart' show FrameDrawing;
import '../playback/layer_frame_image_cache.dart';
import 'bitmap_surface_painter.dart';
import '../../services/layer_pose_paint.dart';
import 'tiled_surface_compose.dart';
import '../../services/composite_effect_paint.dart';
import 'display_resample.dart';
import 'image_pieces.dart';
import 'selection_float_overlay.dart';
import 'subtree_image_composite.dart';
import 'layer_image_draw.dart';
import 'paper_background.dart';
import 'viewport_canvas_transform.dart';
import '../effective_device_pixel_ratio.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/cel_surface_as_shown.dart';
import 'raster_picture.dart';
import 'tile_origin.dart';
import 'tile_pyramid.dart';
import '../text/cel_number_paint.dart' show paintCelNumber;

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
    this.placement,
    this.effects = const [],
  });

  /// The CEL this row is drawing — the same key its cached twin
  /// [CanvasLayerImageRequest.frameKey] asks the image cache with. Null
  /// when the row has nothing exposed here.
  ///
  /// 🚨What it is for: the frame's one picture — the row is drawn from its
  /// cel's stored layer when nothing holds it live (`storedRowOf`), and the
  /// cel the pen is on is the one a landing stroke moves the picture to
  /// (`FramePictureView._celDrawnOn`).
  ///
  /// ↩️It let the stack's sweep compose a cel that LEFT the active slot
  /// inside that build instead of letting the row go blank until an
  /// asynchronous image landed (유저 절대규칙 「보이는 중이랑 결과랑 절대로
  /// 다르면 안 되」) — until the frame's one picture drew the rows
  /// (one-picture-per-frame ②-5a).
  ///
  /// 🪦A field of this name stood here until 2026-09-17 for the opposite
  /// direction — finding the image to hold over a cel ENTERING the slot,
  /// the first-activation stand-in — and went with it.
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

  final LayerPlacement? placement;

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

  /// The CPU half — the leading colour keys, which the session puts on the
  /// surface this row draws ([CanvasLayerImageRequest.sourceEffects]'s
  /// split, for the row a pen is on).
  List<ResolvedLayerEffect> get sourceEffects =>
      splitSourceEffects(effects).source;
}

/// A [LiftedCel] as the view draws it: the painter its surface is shown by,
/// and its float.
typedef _LiftedRowPaint = ({
  BitmapSurfacePainter surface,
  SelectionFloatOverlay float,
});

/// One non-active layer to composite around the interactive canvas.
class CanvasLayerImageRequest extends CanvasStackRow {
  const CanvasLayerImageRequest({
    required this.frameKey,
    required this.opacity,
    this.blendMode = LayerBlendMode.normal,
    this.placement,
    this.tint,
    this.effects = const [],
  });

  final BrushFrameKey frameKey;

  /// EFFECTIVE opacity (static × animated Opacity sample).
  final double opacity;

  /// The layer's composite blend (R26 #30) — the editing stack paints it
  /// exactly like the composite routes.
  final LayerBlendMode blendMode;

  /// Where the layer lies at the shown frame; null = identity. The stack
  /// paints it exactly like the composite routes — the ACTIVE layer shows
  /// its placement too, through the interactive view's draw-through wrap.
  final LayerPlacement? placement;

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
  /// same placement and chain the draw is handed
  /// ([inkCropDrawsTheSame]).
  bool get inkSuffices => inkCropDrawsTheSame(
    placement: placement,
    effects: paintEffects,
  );
}

/// The quality — the level of the display's pyramid — a stack seen through
/// [viewport] on a screen of [devicePixelRatio] asks its rows' images at:
/// the level its display buffer composes at ([displayLevelOf]). Full at or
/// above 100%, as always; half at 50–100% on screen, quarter below, so a
/// level buffer draws them 1:1 instead of reducing a canvas-resolution
/// picture by more than a bilinear window can hold.
///
/// ↩️The warmer's answer too, for the rows it made ahead of a stack
/// (`CanvasLook.qualityAt`), until a run's frame became one picture.
PlaybackQuality rowQualityThrough(
  CanvasViewport viewport,
  double devicePixelRatio,
) => PlaybackQuality.forLevel(
  displayLevelOf(displayScaleOf(viewport.zoom, devicePixelRatio)),
);

/// What a frame is drawn ON — the four a [CanvasLayerStackView] draws its
/// nodes on: the page's size, how far its pasteboard reaches, whether it
/// paints paper and which paper. One value because a frame's one picture
/// is KEYED by them (`FramePictureKey`): a picture drawn on one page is
/// not the picture of another.
typedef FramePage = ({
  CanvasSize canvasSize,
  PasteboardReach pasteboardReach,
  bool paintPaper,
  ProjectBackground paperBackground,
});

/// What a canvas that stands draws LIVE in a frame: the row a pen is on, by
/// [activeSurfacePainter]; the selection's float in that row's slot
/// ([floatOverlay]); and the rows a folder's move session holds lifted
/// ([liftedRows]) — by the cel each row names. Every other row is drawn
/// from what is stored.
typedef LiveRows = ({
  BitmapSurfacePainter? activeSurfacePainter,
  SelectionFloatOverlay? floatOverlay,
  Map<BrushFrameKey, LiftedCel> liftedRows,
});

/// What the live surface looked like, per coordinate: the overlay's tile
/// images and the committed tiles. Identity per coordinate is what lets the
/// next look say WHERE the surface changed ([StackedFrame.movedSince]).
///
/// 🚨★★★F-130: AND WHAT THE PAINTER DRAWS OVER THE SURFACE. The picture
/// holds it, and tokens that do not know a preview cannot say where it
/// went — ↩️the display buffer missed without saying where and fell
/// through to a full raster of the whole canvas once per pointer move,
/// measured on the stamp's ghost at 25 full composes for 25 moves. A
/// preview is one of [previews]: BY VALUE (its own `==`, exactly what a
/// move changes) beside the rect it covered, so the next look can patch
/// where it was and where it is. A record rather than the preview's own
/// type, so what measures a change does not import a tool's.
///
/// F-344: the text in hand, floated over its hole by the same painter
/// (`BitmapSurfacePainter.landingPreview`) — the one preview there is now.
/// ↩️The stamp's ghost was the first (F-33 drew it inside the painter),
/// until brush-fidelity-Q9 (유저 2026-10-18 「통일하면 좋음」) moved it to the
/// overlay's CPU pre-blended tiles, which [overlay] carries.
typedef LiveSurfaceTokens = ({
  Map<Object, Object> overlay,
  Map<Object, Object> tiles,
  List<({Object value, Rect rect})> previews,
});

/// 🚨★★★A FRAME'S ONE PICTURE IS DRAWN BY THE CANVAS'S OWN BODY
/// (one-picture-per-frame, D7-2-Q3=a — 「합성기는 하나」): [nodes], the
/// frame as a screen stacks it, composed over [FrameDrawing.extent] in
/// world coordinates as a miss composes the display buffer whole at 100% —
/// the paper as the root's bottom row, folders, adjustments, blends over
/// their backdrops, effects and poses — with every row drawn from its own
/// tiles, by the body the live row is drawn with ([_PaintCelSurface], from
/// what [storedRowOf] hands for it). No second compositor: a frame's
/// picture is what the canvas would show of it.
///
/// Under [live], the rows a canvas that stands holds live are drawn as it
/// draws them ([_liveRowOf]) — the frame AS IT STANDS, what a still
/// canvas shows while its picture is not there and what its strokes patch
/// into the picture ([movedSince]).
///
/// The extent is what the buffer covers with the whole pasteboard in view:
/// the page and every row's content.
///
/// 🚨[FrameDrawing.outside] IS NOTHING, and the picture holds what the
/// buffer holds past the paper — what the rows lay over no paper, as they
/// lay it. A screen lays its pasteboard under the buffer, in a colour each
/// view sets for itself (`BrushCanvasPanel.pasteboardColor`); laid into the
/// picture, one frame would be a picture per colour.
final class StackedFrame {
  factory StackedFrame.of(
    List<CompositeNode<CanvasStackRow>> nodes, {
    required FramePage page,
    required CutFrameCompositeLayer? Function(CanvasStackRow row) storedRowOf,
    ({LiveRows rows, LiftedRowPainters painters})? live,
  }) {
    final drawn = mapCompositeLeaves<CanvasStackRow, _PaintRow>(nodes, (row) {
      if (live != null) {
        if (_liveRowOf(row, live.rows, live.painters) case final row?) {
          return row;
        }
      }
      return switch (storedRowOf(row)) {
        final layer? => _PaintCelSurface(layer),
        null => null,
      };
    });
    final liftedRows =
        live?.painters._drawn(live.rows.liftedRows) ??
        const <BrushFrameKey, _LiftedRowPaint>{};
    return StackedFrame._(
      (viewport, devicePixelRatio, debugDisableSingleBuffer) =>
          _LayerStackPainter(
            nodes: drawn,
            activeSurfacePainter: live?.rows.activeSurfacePainter,
            floatOverlay: live?.rows.floatOverlay,
            liftedRows: liftedRows,
            canvasSize: page.canvasSize,
            pasteboardReach: page.pasteboardReach,
            viewport: viewport,
            paintPaper: page.paintPaper,
            paperBackground: page.paperBackground,
            devicePixelRatio: devicePixelRatio,
            debugDisableSingleBuffer: debugDisableSingleBuffer,
            composedAtTheDisplayLevel: false,
          ),
    );
  }

  StackedFrame._(this._through)
    : _painter = _through(CanvasViewport(), 1, false);

  /// The body seen through a view, at a device's ratio — and, for a parity
  /// test, without the single buffer ([CanvasLayerStackView.
  /// debugDisableSingleBuffer]).
  final _LayerStackPainter Function(
    CanvasViewport viewport,
    double devicePixelRatio,
    bool debugDisableSingleBuffer,
  )
  _through;

  /// The body in world coordinates — what the picture is drawn by.
  final _LayerStackPainter _painter;

  /// The frame as it stands drawn ON THE SCREEN, through [viewport] — by
  /// the walk the canvas's own stack takes there, under the display's laws:
  /// each row at the display's level, the paper cut on the device's grid
  /// (F-67-paper-edge) — what the frame's picture shows of it, to the
  /// display's sampling. ⛔Not [drawing] through the view: that is the
  /// picture's raster, cut on the canvas's grid — an absent paper's
  /// checkerboard and the paper's own edge parted by a blended column.
  void paintOnScreen(
    Canvas canvas,
    Size size, {
    required CanvasViewport viewport,
    required double devicePixelRatio,
    @visibleForTesting bool debugDisableSingleBuffer = false,
  }) => _LayerStackPaintPass(
    _through(viewport, devicePixelRatio, debugDisableSingleBuffer),
  ).paint(canvas, size);

  /// The frame as the store lays it — its extent asked afresh each time:
  /// a stroke grows what the live row covers.
  FrameDrawing get drawing => (
    extent: _LayerStackPaintPass(_painter).frameExtent(),
    outside: const ui.Color(0x00000000),
    // A pass per paint, as the painter's own: its geometry is read once.
    draw: (canvas) => _LayerStackPaintPass(_painter).paintFrame(canvas),
  );

  /// What moves the live rows' pixels with no new frame — a stroke's step,
  /// a float's or a lift's drag — as it repaints the canvas's own stack.
  Listenable get changes => _LayerStackPainter._liveListenable(
    _painter.activeSurfacePainter,
    _painter.floatOverlay,
    _painter.liftedRows,
  );

  /// Whether where a change of the live rows lands can be told
  /// ([movedSince]) — as a canvas that stands asks before it patches its
  /// picture ([_LayerStackPainter._liveCanBeTold]).
  bool get steady => _painter._liveCanBeTold;

  /// What the live row looks like now, to measure its next change from —
  /// null where it cannot be told ([_LayerStackPainter._liveSurfaceTokens]).
  LiveSurfaceTokens? get tokens => _painter._liveSurfaceTokens();

  /// Where the live row's pixels moved since [since], in world coordinates
  /// ([_LayerStackPainter._liveDirtyCanvasRect]).
  ({bool located, Rect? dirty, LiveSurfaceTokens? now}) movedSince(
    LiveSurfaceTokens since,
  ) => _painter._liveDirtyCanvasRect(since: since);
}

/// The painters the rows a lift holds beside the live one are drawn by
/// ([LiftedCel]), by cel — kept while a row's surface and keys stay what
/// they were: a new painter is a new set of tile pictures, and a drag step
/// changes neither. A screen keeps one across its paints.
final class LiftedRowPainters {
  final Map<
    BrushFrameKey,
    ({BitmapSurface surface, List<double> keys, BitmapSurfacePainter painter})
  >
  _held = {};

  /// [lifted] as [request]'s row draws it.
  _LiftedRowPaint _of(CanvasLayerImageRequest request, LiftedCel lifted) {
    final keys = celSourceEffectSignature(request.sourceEffects);
    final held = _held[request.frameKey];
    if (held != null &&
        identical(held.surface, lifted.surface) &&
        listEquals(held.keys, keys)) {
      return (surface: held.painter, float: lifted.float);
    }
    final painter = BitmapSurfacePainter(
      // Shown as the row's image is: its texts laid, then its row's keys —
      // the CPU half of the chain; the paint half rides the row's paint.
      surface: celSurfaceAsShown(lifted.surface, request.sourceEffects),
      // The stack draws in canvas space, as for the live row.
      showTransparentBackground: false,
      lineage: (request.frameKey.layerId, request.frameKey.frameId),
    );
    _held[request.frameKey] = (
      surface: lifted.surface,
      keys: keys,
      painter: painter,
    );
    return (surface: painter, float: lifted.float);
  }

  /// The painters as [lifted] draws them — none for a cel it no longer
  /// holds.
  Map<BrushFrameKey, _LiftedRowPaint> _drawn(
    Map<BrushFrameKey, LiftedCel> lifted,
  ) {
    _held.removeWhere((key, _) => !lifted.containsKey(key));
    return {
      for (final MapEntry(:key, :value) in _held.entries)
        key: (surface: value.painter, float: lifted[key]!.float),
    };
  }
}

/// [row] as a canvas that stands draws it live ([LiveRows]), or null where
/// it is drawn from what is stored.
_PaintRow? _liveRowOf(
  CanvasStackRow row,
  LiveRows live,
  LiftedRowPainters painters,
) => switch (row) {
  // A row a lift holds beside the live one draws its lifted surface —
  // whether or not its image is held: that is the cel as it stands, and
  // the lift is what shows while the box is open (I-37 · F-329).
  final CanvasLayerImageRequest request
      when live.liftedRows.containsKey(request.frameKey) =>
    _PaintLiftedSurface(
      lifted: painters._of(request, live.liftedRows[request.frameKey]!),
      opacity: request.opacity,
      blendMode: request.blendMode,
      placement: request.placement,
      // The PAINT half only, as the live row's: the lifted surface's
      // painter carries the row's leading keys.
      effects: request.paintEffects,
      keys: request.sourceEffects,
    ),
  final CanvasActiveLayerRow active when live.activeSurfacePainter != null =>
    _PaintActiveSurface(
      opacity: active.opacity,
      blendMode: active.blendMode,
      placement: active.placement,
      // The PAINT half only — like a cached row. A leading key is already
      // on the surface this node draws.
      effects: active.paintEffects,
      keys: active.sourceEffects,
    ),
  _ => null,
};

/// Paints a composite tree of cels' IMAGES from the layer-frame image cache,
/// under the panel viewport transform — the onion ghosts over the frame's
/// one picture, which `FramePictureView` draws with the rows a pen, a float
/// or a lift holds live in it.
///
/// ↩️It painted the editing canvas's whole tree, the ACTIVE layer drawn in
/// place through its live painter — one painter opening a folder's group
/// buffer around the layer being drawn on and closing it — until a canvas
/// that stands showed the frame's one picture (one-picture-per-frame ②-3)
/// and the live rows went with it (②-5a, 2026-10-25).
/// Paint-only: input always passes through to the canvas below.
class CanvasLayerStackView extends StatefulWidget {
  const CanvasLayerStackView({
    super.key,
    required this.nodes,
    required this.imageCache,
    required this.canvasSize,
    this.pasteboardReach = PasteboardReach.whole,
    required this.viewport,
    this.paintPaper = false,
    this.paperBackground = ProjectBackground.defaultBackground,
    this.drawnLive = const {},
    this.debugDisableSingleBuffer = false,
  });

  /// The cels the canvas under these rows draws live — its active rows'
  /// ([CanvasActiveLayerRow.frameKey]). A row of one of them that comes in
  /// at the next build was on screen a frame ago, and its image is composed
  /// on the spot: the cel you were just drawing, a ghost behind the frame
  /// you stepped to.
  final Set<BrushFrameKey> drawnLive;

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

  /// The composite tree, bottom → top.
  final List<CompositeNode<CanvasStackRow>> nodes;

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
        case CompositeBackdropBlend():
        case CompositeClip():
        case CompositeOpaque():
        case CompositeCelNumber():
          break;
      }
    }
  }

  final LayerFrameImageCache imageCache;
  final CanvasSize canvasSize;

  /// How far past [canvasSize] the pictures here may reach (I-109): the
  /// wall of their store — the project's for the floor's, whole for a
  /// sheet's ink. Nothing past it is painted.
  final PasteboardReach pasteboardReach;
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

  /// The cel revision a held image was captured at.
  ///
  /// ⛔It rides INSIDE the held record rather than in a map beside it. A
  /// second map would need clearing at all four `_dropImage` call sites, and
  /// 「지우는 곳을 하나 더 추가」 is not a fix — the two would drift the first
  /// time someone added a fifth.
  int? _revisionOf(BrushFrameKey key) =>
      widget.imageCache.frameStore.frameOrNull(key)?.sourceRevision;

  /// Whether [key]'s cel could not be read at the content it holds now
  /// ([LayerFrameImageCache.unreadable]) — a row skipped, not opened again.
  bool _unreadable(BrushFrameKey key) => widget.imageCache.unreadable.has(key);

  /// A row whose image could not be built, reported — the cache has noted
  /// its cel ([LayerFrameImageCache.unreadable]).
  void _reportFailure(
    BrushFrameKey key,
    Object error,
    StackTrace stack,
    String where,
  ) {
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
    // The first sweep runs in [didChangeDependencies]: the level it asks
    // images at needs the effective ratio, which is a dependency.
    widget.imageCache.frameStore.addRekeyListener(_travelWithTheirCels);
    widget.imageCache.frameStore.addCopyListener(_shareWithTheirCopies);
  }

  /// What this view holds of a cel is held under the key a rekey moved its
  /// pixels to as well ([BrushFrameStore.addRekeyListener]) — the same
  /// picture, so the frame it lands on draws it as the frame before did: an
  /// image row adopts it.
  ///
  /// ⛔UNDER BOTH KEYS until the next sweep keeps the one its rows ask for:
  /// a paint before this view's rebuild still asks under the key the move
  /// left.
  void _travelWithTheirCels(
    List<(BrushFrameKey from, BrushFrameKey to)> pairs,
  ) {
    for (final (from, to) in pairs) {
      final held = _images[from];
      if (held != null) {
        _holdAlsoUnder(to, held, revision: held.revision);
      }
    }
  }

  /// What this view holds of a cel is held for its COPY as well
  /// ([BrushFrameStore.addCopyListener]) — the very pixels, so the same
  /// picture: a row that turns to the copy draws it as it drew the source,
  /// on the frame it turns (F-275). Only a picture of the source as it
  /// stands is one of the copy, stamped with the copy's own revision.
  void _shareWithTheirCopies(
    List<(BrushFrameKey from, BrushFrameKey to)> pairs,
  ) {
    for (final (from, to) in pairs) {
      final held = _images[from];
      if (held != null && held.revision == _revisionOf(from)) {
        _holdAlsoUnder(to, held, revision: _revisionOf(to));
      }
    }
  }

  /// [held] held under [to] as well, at [revision] — a clone, pinned there.
  void _holdAlsoUnder(
    BrushFrameKey to,
    _HeldImage held, {
    required int? revision,
  }) {
    final there = _images.remove(to);
    if (there != null) {
      _dropImage(to, there);
    }
    widget.imageCache.retainPin(to, held.quality);
    _images[to] = (
      source: held.source,
      clone: held.clone.clones(),
      worldRect: held.worldRect,
      extent: held.extent,
      revision: revision,
      quality: held.quality,
      content: held.content,
      laidBack: LaidBackWhole(),
    );
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
      oldWidget.imageCache.frameStore.removeRekeyListener(
        _travelWithTheirCels,
      );
      widget.imageCache.frameStore.addRekeyListener(_travelWithTheirCels);
      oldWidget.imageCache.frameStore.removeCopyListener(
        _shareWithTheirCopies,
      );
      widget.imageCache.frameStore.addCopyListener(_shareWithTheirCopies);
    }
    _syncImagesWithCache(shownAlready: oldWidget.drawnLive);
    unawaited(_ensureImages());
  }

  /// Lets go of what this view held for [key] — in the build that replaces
  /// the painter drawing with it ([_superseded]), as a settle's handles go.
  ///
  /// ⛔Not at once: the async pass drops a row's image and asks for the
  /// build only once every row is through, and a sibling repainting the
  /// layer meanwhile — the frame's one picture under the ghosts, at each
  /// stroke step — repaints this view with the painter it has, which drew
  /// a disposed image (2026-10-25). ↩️The kept display buffer hid it: the
  /// painter drew the buffer, not the rows.
  void _dropImage(BrushFrameKey key, _HeldImage held) {
    _dropped.add((cache: widget.imageCache, key: key, held: held));
  }

  /// The handles a settle replaced ([_settleHeldImage]) — the painter on
  /// screen may still draw with them — let go in the build that replaces
  /// it ([_releaseSuperseded]).
  final List<ImagePiece> _superseded = <ImagePiece>[];

  /// The images let go ([_dropImage]), kept as [_superseded] is — each with
  /// the cache its pin was taken on, which a cache swap meanwhile does not
  /// move ([didUpdateWidget] moves the pins of [_images]).
  final List<_DroppedImage> _dropped = <_DroppedImage>[];

  /// Lets go of [held], pinned on [cache] for [key].
  static void _letGo(
    LayerFrameImageCache cache,
    BrushFrameKey key,
    _HeldImage held,
  ) {
    // A6: the pin travels with the clone — held pixels are declared
    // pixels, and the declaration ends exactly when the hold does.
    cache.releasePin(key, held.quality);
    held.clone.disposeAll();
    held.laidBack.dispose();
  }

  /// [image] takes the place of [held] for [key] as the same picture — the
  /// only way into [_images] that leaves the stack on screen standing.
  ///
  /// 🚨★★★A SETTLE IS NOT A NEW PICTURE. A row is composed in the build as
  /// a DEFERRED image and settles one frame later into the plain snapshot of
  /// the same picture ([LayerFrameImage.content] is how the cache says so).
  /// Taken as a new picture it repaints — ↩️and, while the buffer was kept,
  /// it broke the composite key and the whole display buffer rastered a
  /// second time for pixels it already had: 🔬measured 2026-09-23, F-130
  /// `solo` arm, 24 drawn rows: two full buffer rasters per select, the
  /// second one pure repetition (229ms of 520 in the test VM's software
  /// raster). 유저 (via the board/integration session's measurement, board
  /// `I-19`): 「솔로 버벅임」, layer select included.
  ///
  /// ⛔The replaced clone is not disposed here — the painter on screen draws
  /// with it until the next build, which the settle asks for — so it is
  /// PARKED ([_superseded]) and goes in that build ([_releaseSuperseded]).
  void _settleHeldImage(
    BrushFrameKey key,
    _HeldImage held,
    LayerFrameImage image,
  ) {
    _superseded.addAll(held.clone);
    _images[key] = (
      source: image.pieces,
      clone: image.pieces.clones(),
      worldRect: held.worldRect,
      extent: held.extent,
      revision: held.revision,
      quality: held.quality,
      content: held.content,
      // The same pixels, so the same whole.
      laidBack: held.laidBack,
    );
  }

  /// Lets go of what a settle replaced and what was dropped, in the build
  /// whose painter draws with what took their place.
  void _releaseSuperseded() {
    _superseded.disposeAll();
    _superseded.clear();
    for (final (:cache, :key, :held) in _dropped) {
      _letGo(cache, key, held);
    }
    _dropped.clear();
  }

  @override
  void dispose() {
    widget.imageCache.frameStore.removeRekeyListener(_travelWithTheirCels);
    widget.imageCache.frameStore.removeCopyListener(_shareWithTheirCopies);
    for (final MapEntry(:key, value: held) in _images.entries) {
      _letGo(widget.imageCache, key, held);
    }
    _images.clear();
    _releaseSuperseded();
    super.dispose();
  }

  /// Synchronous sweep BEFORE this frame's build: adopt every requested
  /// layer whose image is already valid in the cache and drop layers that
  /// left the request set — so a row whose image is warm paints THIS frame;
  /// the async pass alone would paint it one frame late at best.
  ///
  /// [shownAlready] is the cels on screen already that this view holds no
  /// image of: the ones the canvas under the widget this build replaces
  /// drew live ([CanvasLayerStackView.drawnLive]).
  void _syncImagesWithCache({
    Set<BrushFrameKey> shownAlready = const {},
  }) {
    labProbe(
      'layerStackSyncSweep(${widget.layers.length})',
      () => _syncSweepBody(shownAlready),
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
    if (held != null && identical(held.source, image.pieces)) {
      return false;
    }
    if (held != null && identical(held.content, image.content)) {
      _settleHeldImage(key, held, image);
      // Changed, so the next build hands the painter the new handle and
      // lets the old one go. It repaints nothing: the rows match by
      // content.
      return true;
    }
    if (held != null) _dropImage(key, held);
    widget.imageCache.retainPin(key, quality);
    _images[key] = (
      source: image.pieces,
      clone: image.pieces.clones(),
      worldRect: image.worldRect,
      extent: image.extent,
      revision: revision,
      quality: quality,
      content: image.content,
      laidBack: LaidBackWhole(),
    );
    return true;
  }

  /// The quality this view asks the other layers' images at
  /// ([rowQualityThrough]).
  PlaybackQuality get _quality =>
      rowQualityThrough(widget.viewport, _devicePixelRatio);

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
  /// asked for as an image it may not have: the canvas under this stack
  /// drew it live ([shownAlready] — the onion's ghost of the cel just drawn,
  /// a step after), or the image this row holds is of the cel before an
  /// EDIT (`sourceRevision` moves on every surface write and on nothing
  /// else). Such a row's image is composed inside the sweep
  /// ([LayerFrameImageCache.prepareSyncOrNull]'s `makePictures`).
  ///
  /// ↩️So was every row of a view taking over what another route showed
  /// (`alreadyShown`, F-215) — read on this thread by the frame's one
  /// picture since it took the conte's live picture over
  /// (`FramePictureView.alreadyShown`).
  bool _wasOnScreen(
    BrushFrameKey key,
    int? revision,
    Set<BrushFrameKey> shownAlready,
  ) {
    final held = _images[key];
    return shownAlready.contains(key) ||
        (held != null && held.revision != revision);
  }

  void _syncSweepBody(Set<BrushFrameKey> shownAlready) {
    _adoptWhatIsThere(shownAlready);
    final asked = {for (final layer in widget.layers) layer.frameKey};
    for (final key in _images.keys.toList()) {
      if (!asked.contains(key)) {
        _dropImage(key, _images.remove(key)!);
      }
    }
  }

  /// Adopts every requested row whose image is valid in the cache now — or
  /// composes the ones that may not wait ([_wasOnScreen]).
  void _adoptWhatIsThere(Set<BrushFrameKey> shownAlready) {
    for (final layer in widget.layers) {
      // Valid cache image, or a synchronous per-tile compose — either way
      // the artwork paints THIS frame. A row on screen a frame ago — drawn
      // live under this stack, or held from before an edit — is composed
      // whatever it takes ([_wasOnScreen]); any other row
      // only when it is free, and a true cold miss falls to the async pass.
      // 🚨Same law as the async pass — and this walk runs FIRST, so
      // without it the guard down there never gets its turn: the throw
      // lands here instead, out of a build/layout callback, and every
      // later layer in THIS sweep is skipped with it. One row's
      // unreachable cel is one row's.
      if (_unreadable(layer.frameKey)) {
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
          makePictures: _wasOnScreen(layer.frameKey, revision, shownAlready),
          inkSuffices: layer.inkSuffices,
        );
      } on Object catch (error, stack) {
        _reportFailure(layer.frameKey, error, stack, 'sync sweep');
        continue;
      }
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
    if (_unreadable(layer.frameKey)) {
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
      _reportFailure(layer.frameKey, error, stack, 'async pass');
      return false;
    }
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
        // ⛔ONE ROW AFTER ANOTHER, on purpose: a row's making holds its cel's
        // tile pictures until its raster lands, and asked for at once a
        // frame of thirteen rows held thirteen cels' worth — for no gain
        // (measured 10-10, camera view, profile: the warm's whole cut made
        // +0.3–15% LATER, when it made rows as this does).
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
          pieces: held.clone,
          content: held.content,
          worldRect: held.worldRect,
          extent: held.extent,
          laidBack: held.laidBack,
          opacity: request.opacity,
          blendMode: request.blendMode,
          placement: request.placement,
          tint: request.tint,
          // The PAINT half only — the keys are already in the image the
          // cache handed back.
          effects: request.paintEffects,
        );
      // Drawn live by the frame's picture's view (`FramePictureView`), not
      // from an image of its cel.
      case CanvasActiveLayerRow():
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _resolvedTree(widget.nodes);
    // This build's painter draws with what took the place of a settle's
    // handles and of the images dropped, so those can go ([_superseded]).
    _releaseSuperseded();
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
          canvasSize: widget.canvasSize,
          pasteboardReach: widget.pasteboardReach,
          viewport: widget.viewport,
          paintPaper: widget.paintPaper,
          paperBackground: widget.paperBackground,
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
  List<ImagePiece> source,
  List<ImagePiece> clone,
  Rect worldRect,
  // The rect the whole content image covers ([LayerFrameImage.extent]).
  Rect extent,
  int? revision,
  PlaybackQuality quality,
  // What the pixels ARE ([LayerFrameImage.content]) — what the paint tree
  // compares, so a settle changes nothing.
  Object content,
  // The whole these pixels stand for, once a draw has laid it back — kept
  // while they are held, disposed with the clone.
  LaidBackWhole laidBack,
});

/// A held image let go, waiting for the build that replaces the painter
/// drawing with it ([_CanvasLayerStackViewState._dropped]).
typedef _DroppedImage = ({
  LayerFrameImageCache cache,
  BrushFrameKey key,
  _HeldImage held,
});

/// The painter's own node shape: the request tree with images resolved.
sealed class _PaintRow {
  const _PaintRow();

  /// Whether [other] draws the same picture as this row — the repaint
  /// gate's question, field by field, images by IDENTITY.
  bool matches(_PaintRow other);
}

/// The PAPER the rows are laid on, as the bottom row of the root scope
/// ([onUnderlay]): where an advanced blend composes over its backdrop,
/// the paper is in that backdrop, as a GPU blend reads it off the target
/// (brush-fidelity-Q4).
///
/// The pass paints it ([_LayerStackPaintPass._paintPaperInto]) — it knows
/// the level and the edge — from the painter's own fields, which the repaint
/// gate already carries (`paintPaper`, `paperBackground`); so there is
/// nothing of its own to compare.
final class _PaintPaper extends _PaintRow {
  const _PaintPaper();

  @override
  bool matches(_PaintRow other) => other is _PaintPaper;
}

final class _PaintImage extends _PaintRow {
  const _PaintImage({
    required this.pieces,
    required this.content,
    required this.worldRect,
    required this.extent,
    required this.laidBack,
    required this.opacity,
    required this.blendMode,
    required this.placement,
    required this.tint,
    required this.effects,
  });

  /// The image and where its pixels belong — one piece, or several past the
  /// side this engine holds (`piecesOver`).
  final List<ImagePiece> pieces;

  /// The rect the whole content image covers — [worldRect] itself, or more
  /// when the cache stored the ink alone ([LayerFrameImage.extent]). What the
  /// row stands for when a folder asks how far its buffer reaches.
  final Rect extent;

  /// Where the whole of [pieces] is kept once a draw lays it back — the held
  /// image's own. Out of [matches]: it is [content]'s whole, so it changes
  /// exactly when [content] does.
  final LaidBackWhole laidBack;

  /// What [pieces]' pixels ARE ([LayerFrameImage.content]) — the one thing
  /// [matches] compares about the picture.
  ///
  /// ⛔Not `identical(image, …)`, which is what it compared until
  /// 2026-09-23: a settle hands over a new handle to the same pixels, and
  /// the handle's identity is what repainted the stack — ↩️and, while the
  /// buffer was kept, broke the composite key and rastered it a second
  /// time ([_CanvasLayerStackViewState._settleHeldImage]). Every compose
  /// makes a new token, so a new PICTURE still repaints.
  final Object content;
  final Rect worldRect;
  final double opacity;
  final LayerBlendMode blendMode;
  final LayerPlacement? placement;
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
      placement == other.placement &&
      tint == other.tint &&
      // R6: an effect edit changes the pixels and nothing else — leaving
      // it out here would repaint nothing (the whole tree still "matches")
      // and the canvas would go stale.
      listEquals(effects, other.effects);
}

/// A row drawn as a SURFACE — the live one, or one a lift holds beside it —
/// and what its layer composites with, for the one body that draws both
/// ([_LayerStackPaintPass._paintSurfaceRow]).
sealed class _SurfaceRow extends _PaintRow {
  const _SurfaceRow();

  double get opacity;
  LayerBlendMode get blendMode;
  LayerPlacement? get placement;
  List<ResolvedLayerEffect> get effects;

  /// The CPU half of the row's chain — the leading colour keys its cel is
  /// shown through — which a float over it asks after
  /// ([SelectionFloatPaint.shownOn]).
  List<ResolvedLayerEffect> get keys;

  _SurfaceRowPaint get paint => (
    opacity: opacity,
    blendMode: blendMode,
    placement: placement,
    effects: effects,
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
final class _PaintActiveSurface extends _SurfaceRow {
  const _PaintActiveSurface({
    required this.opacity,
    required this.blendMode,
    required this.placement,
    required this.effects,
    required this.keys,
  });

  /// ㊱: the active row's display opacity. It reached the node all along and
  /// stopped here — the field did not exist, so the live surface drew at full
  /// strength while every OTHER row honoured its slider.
  @override
  final double opacity;

  /// The same story as [opacity], one field over and one round later: the
  /// blend had no field on the node either, so it could not stop here — it
  /// never started. See [CanvasActiveLayerNode.blendMode].
  @override
  final LayerBlendMode blendMode;

  @override
  final LayerPlacement? placement;
  @override
  final List<ResolvedLayerEffect> effects;
  @override
  final List<ResolvedLayerEffect> keys;

  // ㊱: the alpha belongs in the repaint gate too — a slider drag changes
  // NOTHING else about this node, so leaving it out would paint the new
  // value only when some unrelated fact moved (the ㉘/㉞ shape: the value
  // is right and the gate says "unchanged").
  @override
  bool matches(_PaintRow other) =>
      other is _PaintActiveSurface &&
      opacity == other.opacity &&
      blendMode == other.blendMode &&
      placement == other.placement &&
      listEquals(effects, other.effects) &&
      listEquals(keys, other.keys);
}

/// A row a folder's move session holds lifted ([LiftedCel]): drawn by
/// its lifted surface with its float over it, by the same body the active
/// row is drawn with — in its own slot, with its own row's paint.
final class _PaintLiftedSurface extends _SurfaceRow {
  const _PaintLiftedSurface({
    required this.lifted,
    required this.opacity,
    required this.blendMode,
    required this.placement,
    required this.effects,
    required this.keys,
  });

  final _LiftedRowPaint lifted;
  @override
  final double opacity;
  @override
  final LayerBlendMode blendMode;
  @override
  final LayerPlacement? placement;
  @override
  final List<ResolvedLayerEffect> effects;
  @override
  final List<ResolvedLayerEffect> keys;

  // The surface and the float by IDENTITY, as an image is: the float's
  // value moves under the hand without this node changing, which is why a
  // frame holding a lifted row patches nothing ([_LayerStackPainter.
  // _liveCanBeTold]) and repaints on each float ([_LayerStackPainter.
  // _liveListenable]).
  @override
  bool matches(_PaintRow other) =>
      other is _PaintLiftedSurface &&
      identical(lifted.surface, other.lifted.surface) &&
      identical(lifted.float, other.lifted.float) &&
      opacity == other.opacity &&
      blendMode == other.blendMode &&
      placement == other.placement &&
      listEquals(effects, other.effects) &&
      listEquals(keys, other.keys);
}

/// A cel drawn from its OWN TILES, as the plan hands it
/// ([CutFrameCompositeLayer]: its texts laid and its leading keys run on
/// the surface, the rest of its chain left to the paint) — every row of a
/// frame's one picture ([StackedFrame]), by the body the live row is
/// drawn with.
final class _PaintCelSurface extends _SurfaceRow {
  _PaintCelSurface(CutFrameCompositeLayer layer)
    : painter = BitmapSurfacePainter(
        surface: layer.surface,
        // The stack lays its own paper.
        showTransparentBackground: false,
      ),
      opacity = layer.opacity,
      blendMode = layer.blendMode,
      placement = layer.placement,
      effects = layer.effects;

  final BitmapSurfacePainter painter;
  @override
  final double opacity;
  @override
  final LayerBlendMode blendMode;
  @override
  final LayerPlacement? placement;
  @override
  final List<ResolvedLayerEffect> effects;

  /// None left to show a float through: the plan ran them on the surface,
  /// and nothing floats over a frame's picture.
  @override
  List<ResolvedLayerEffect> get keys => const [];

  @override
  bool matches(_PaintRow other) =>
      other is _PaintCelSurface &&
      identical(painter.surface, other.painter.surface) &&
      opacity == other.opacity &&
      blendMode == other.blendMode &&
      placement == other.placement &&
      listEquals(effects, other.effects);
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
      CompositeBackdropBlend<_PaintRow>(
        :final backdrop,
        :final source,
        :final blendMode,
      ) =>
        b is CompositeBackdropBlend<_PaintRow> &&
            blendMode == b.blendMode &&
            _nodesMatch(source, b.source) &&
            _treesMatch(backdrop, b.backdrop),
      CompositeClip<_PaintRow>(
        :final base,
        :final scope,
        :final opacity,
        :final blendMode,
      ) =>
        b is CompositeClip<_PaintRow> &&
            opacity == b.opacity &&
            blendMode == b.blendMode &&
            _nodesMatch(base, b.base) &&
            _treesMatch(scope, b.scope),
      CompositeOpaque<_PaintRow>(:final of) =>
        b is CompositeOpaque<_PaintRow> && _nodesMatch(of, b.of),
      CompositeCelNumber<_PaintRow>(:final on, :final letters) =>
        b is CompositeCelNumber<_PaintRow> &&
            letters == b.letters &&
            _nodesMatch(on, b.on),
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

/// The geometry field probe's state — the numbers every buffer decision
/// depends on and nobody has ever measured on a device: the logical view,
/// the device pixel ratio, the zoom actually worked at, and what the
/// buffer costs there. ↩️The 1928×1200 that circulated was a comment in the
/// bake, not a measurement.
///
/// Public and outside the painter because the painter class is private and
/// a fresh object every frame — tests and a hands-on session need to reach
/// the histogram, and the dedupe line needs to outlive a frame.
abstract final class CanvasPaintGeometryProbe {
  /// The last emitted geometry line — the dedupe key, held across frames.
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
    this.activeSurfacePainter,
    this.floatOverlay,
    this.liftedRows = const {},
    required this.canvasSize,
    required this.pasteboardReach,
    required this.viewport,
    required this.paintPaper,
    required this.paperBackground,
    this.devicePixelRatio = 1.0,
    this.debugDisableSingleBuffer = false,
    this.composedAtTheDisplayLevel = true,
  });

  /// What moves the live rows' pixels: the live row's surface and stroke,
  /// the float, and each lifted row's surface and float — a drag step
  /// reaches the canvas without a widget rebuild ([StackedFrame.changes]).
  ///
  /// ↩️It was this painter's own `repaint`, while the canvas's stack drew
  /// the live rows (until one-picture-per-frame ②-5a).
  static Listenable _liveListenable(
    BitmapSurfacePainter? activeSurfacePainter,
    SelectionFloatOverlay? floatOverlay,
    Map<BrushFrameKey, _LiftedRowPaint> liftedRows,
  ) => Listenable.merge(<Listenable?>[
    activeSurfacePainter,
    floatOverlay,
    for (final lifted in liftedRows.values) ...[lifted.surface, lifted.float],
  ]);

  /// The last line the T12 probe in [paint] emitted. Static: a
  /// [CustomPainter] is a fresh object every frame, so an instance field
  /// would only ever compare against itself.
  static String? _lastStackProbe;

  final List<CompositeNode<_PaintRow>> nodes;

  /// Draws the ACTIVE layer's live surface in place. Its own repaint
  /// Listenable (tile cache + stroke overlay) is in [_liveListenable], so a
  /// stroke step still repaints without a widget rebuild.
  final BitmapSurfacePainter? activeSurfacePainter;

  /// TS1: the selection float, drawn in the active layer's slot. In
  /// [_liveListenable] for the same reason the surface painter is — a drag
  /// step has to reach the canvas without a widget rebuild.
  final SelectionFloatOverlay? floatOverlay;

  /// See [LiveRows], as this frame draws them.
  final Map<BrushFrameKey, _LiftedRowPaint> liftedRows;
  final CanvasSize canvasSize;
  final PasteboardReach pasteboardReach;
  final CanvasViewport viewport;
  final bool paintPaper;
  final ProjectBackground paperBackground;

  /// See [CanvasLayerStackView.debugDisableSingleBuffer].
  final bool debugDisableSingleBuffer;

  /// Whether below 100% this stack is composed at the display's level
  /// ([displayLevelOf]; `below_100_the_buffer_is_a_level_test`) — the
  /// onion's ghosts — or at the frame's own resolution, as its one picture
  /// is laid, and resampled as the picture is: a frame drawn as it stands
  /// ([StackedFrame.paintOnScreen]) shows what its picture will (D7-2-Q2
  /// 「항상 원본 한장으로」; F-215 「on하든off하든 바뀌는게 없어야」).
  ///
  /// 🔬At the display's level (2026-10-25), the frame the conte's brush is
  /// switched on in cut each row's edge on the screen's grid, and the
  /// picture that landed after it blended it: 172 pixels, up to 28/255, at
  /// 1/6. So does every patch landing on a canvas zoomed out, at each step
  /// of a stroke.
  ///
  /// ⚠️What it costs, known and kept: zoomed out, a frame drawn whole as it
  /// stands — a float's drag, the stroke steps of a posed or bleeding row —
  /// is a buffer of the canvas's size at each paint, the cost the knee was
  /// dropped for ([_maxBufferSide]). ⛔Not answered by going back to the
  /// levels: 유저 (D7-2-Q2, 2026-10-24) 「배율이 어떻든 항상 원본 한장 …
  /// 100%랑 통일하되, 그런 문제는 통일한 이후 극한으로 해결하고싶어」 — the
  /// cost is card one-picture-per-frame's to solve on this road.
  final bool composedAtTheDisplayLevel;

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
  /// that cannot be said: no live row, a live row whose change does not
  /// land where its tiles are ([_liveSurfaceIsSpatiallyStable]), or one
  /// drawn from state it does not publish
  /// ([BitmapSurfacePainter.drawsOnlyFromPublishedState]) — then no
  /// comparison here can be right. That is the answer that makes a patch
  /// honest: ask the thing you are patching where it changed, and do not
  /// patch what cannot say.
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
    // F-344: the text in hand floated over its hole is part of what the
    // live surface looks like, so it is part of the tokens — by value, with
    // the rect it covers, so a drag can be patched. ↩️F-130 put the stamp's
    // ghost here too; since brush-fidelity-Q9 it is the overlay's tiles.
    final landing = surfacePainter.landingPreview?.value;
    return (
      overlay: <TileCoord, Object>{
        ...overlay?.tileImages ?? const <TileCoord, ui.Image>{},
      },
      tiles: <TileCoord, Object>{
        for (final entry in surfacePainter.surface.tiles.entries)
          entry.key: entry.value,
      },
      previews: [
        if (landing != null) (value: landing, rect: landing.drawnWorldRect),
      ],
    );
  }

  /// Where the LIVE surface changed since [since] — what it looked like
  /// when the picture it is patched into last took it in — in canvas space,
  /// plus what it looks like now, for the next measure.
  ///
  /// 🎯[since] IS WHAT THE PICTURE HOLDS, not what the last paint drew.
  /// ↩️The display buffer's real base was a paint or three older than its
  /// head, and a dirty rect measured from the head's tokens left the steps
  /// between them out of the patch — a stroke with holes in it.
  ///
  /// 🚨`located: false` is the safe answer, and it costs only drawing the
  /// frame as it stands. It is the answer whenever the change cannot be
  /// located ([_liveSurfaceTokens]).
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
    var dirty = tileCoordsWorldRect(
      _movedCoords(
        kept.overlay,
        now.overlay,
      ).followedBy(_movedCoords(kept.tiles, now.tiles)),
      activeSurfacePainter!.surface.tileSize,
    );
    // F-130: a preview that moved (or came, or went) dirties where it WAS
    // and where it IS — the old place is repainted without it. The stamp's
    // ghost was the first (now the overlay's tiles); F-344's text in hand.
    final were = kept.previews;
    final are = now.previews;
    if (!listEquals(
      [for (final preview in were) preview.value],
      [for (final preview in are) preview.value],
    )) {
      for (final preview in [...were, ...are]) {
        dirty = dirty?.expandToInclude(preview.rect) ?? preview.rect;
      }
    }
    return (located: true, dirty: dirty?.inflate(1), now: now);
  }

  /// Whether what the live rows draw can change only where their tokens
  /// say ([_liveSurfaceTokens]) — what a frame's one picture a still canvas
  /// patches stands on (`StackedFrame.steady`).
  ///
  /// ⛔A FLOATING SELECTION IS DRAWN IN THE LIVE ROW'S SLOT and moves under
  /// the hand without touching anything else a token can see, so while one
  /// exists nothing is patched: the frame is drawn as it stands. Caught by
  /// walking this painter's own body asking "what else can change" — which
  /// is the discipline the two reverts before this bought
  /// ([[cache-what-can-say-where-it-changed]]). Shipping without it would
  /// have frozen the canvas for the whole drag.
  ///
  /// Not cheap-and-narrow (hash the float's value) on purpose: the float is
  /// a transient editing state, so declining to patch costs only what
  /// drawing the frame as it stands costs, and it cannot go stale.
  /// A folder's lift (I-37) floats on each of its rows — the same reason,
  /// as many times as it has rows.
  ///
  /// ⛔A live row drawn from anything but what it published is not asked
  /// here: it has no tokens at all ([_liveSurfaceTokens]), and a canvas
  /// holding none draws its frame as it stands. Asked here too, one
  /// question had two answers and a mutant of either survived.
  bool get _liveCanBeTold => floatOverlay?.value == null && liftedRows.isEmpty;

  /// Whether a change to the live surface lands where that surface is.
  ///
  /// ⛔False means no dirty rect drawn from the surface's own coordinates is
  /// correct. A POSE puts its pixels somewhere else entirely, and an effect
  /// that SPREADS — on the surface itself or on any folder enclosing it,
  /// because the stroke's pixels pass through those buffers — smears a dab
  /// past its own tile. Both are answered by drawing the frame as it stands,
  /// whole.
  static bool _liveSurfaceIsSpatiallyStable(
    List<CompositeNode<_PaintRow>> list,
  ) {
    for (final node in list) {
      if (node case CompositeLeaf(payload: final _PaintActiveSurface active)) {
        return active.placement == null &&
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
      // A blend composes pixel by pixel: a dab moves the composite where it
      // lands and nowhere else, so only what the row passes through decides.
      if (node is CompositeBackdropBlend<_PaintRow> &&
          node.children.any(_enclosesActiveSurface)) {
        return _liveSurfaceIsSpatiallyStable(node.children);
      }
      // So does a clip: the base's alpha cuts pixel by pixel, and the base
      // made opaque is the base's own pixels.
      if (node is CompositeClip<_PaintRow> &&
          node.children.any(_enclosesActiveSurface)) {
        return _liveSurfaceIsSpatiallyStable(node.children);
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
        CompositeBackdropBlend(:final children) =>
          children.any(_enclosesActiveSurface),
        CompositeClip(:final children) => children.any(_enclosesActiveSurface),
        // The base it paints again stands in the clip already, and the row
        // a cel number is written on as its own leaf.
        CompositeOpaque() || CompositeCelNumber() => false,
        CompositeLeaf(payload: _PaintImage()) => false,
        // A lifted row only shows; nothing draws into it.
        CompositeLeaf(payload: _PaintLiftedSurface()) => false,
        CompositeLeaf(payload: _PaintCelSurface()) => false,
        CompositeLeaf(payload: _PaintPaper()) => false,
      };

  @override
  bool shouldRepaint(covariant _LayerStackPainter oldDelegate) {
    return oldDelegate.canvasSize != canvasSize ||
        oldDelegate.pasteboardReach != pasteboardReach ||
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
        !_treesMatch(oldDelegate.nodes, nodes);
  }
}

/// Whether [a] and [b] draw the same picture, node for node
/// ([_nodesMatch]).
bool _treesMatch(
  List<CompositeNode<_PaintRow>> a,
  List<CompositeNode<_PaintRow>> b,
) => listsMatch(a, b, _nodesMatch);

/// How many paints have fallen to the direct walk because the buffer would
/// have exceeded the editing stack's buffer cap — the safety net.
///
/// ★A COUNTER AND NOT A COMMENT. "Content bounds and the level keep every
/// ordinary view under the cap" is a claim about a number, and this is the
/// number — the one place the editing canvas stops compositing the way
/// playback, the camera and the export do.
@visibleForTesting
int debugCappedFallbacks = 0;

/// The level ([displayLevelOf]) the last buffer a stack composed was
/// composed at — 0 at canvas resolution. A level path that silently stops
/// running looks exactly like one that works, and this is what says which
/// level a paint actually composed at. ↩️It was the display buffer's own
/// (`DisplayBufferCache.lastBufferLevel`), until nothing kept a buffer
/// (one-picture-per-frame ②-5a).
///
/// ⚠️Written under `assert`, so a release build pays nothing.
@visibleForTesting
int? debugLastBufferLevel;
