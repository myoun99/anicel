import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/collection_equality.dart';
import '../../core/tree_nodes.dart';
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
import '../../models/project_background.dart';
import '../../models/tile_coord.dart';
import '../debug/input_inspector.dart';
import '../../core/dev_profile.dart';
import '../playback/frame_picture_store.dart' show FrameDrawing;
import 'bitmap_surface_painter.dart';
import '../../services/layer_pose_paint.dart';
import 'tiled_surface_compose.dart';
import '../../services/composite_effect_paint.dart';
import 'display_resample.dart';
import 'selection_float_overlay.dart';
import 'composite_tree_paint.dart';
import 'subtree_image_composite.dart';
import 'layer_image_draw.dart';
import 'paper_background.dart';
import 'viewport_canvas_transform.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/cel_surface_as_shown.dart';
import '../../services/playback/cut_frame_composite_signature.dart'
    show CompositeLayerSignature, CutFrameCompositeSignature;
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

  /// The row's effect chain (R6) — an onion ghost's too
  /// ([CanvasGhostImageRequest]): ✅유저 2026-08-27 (I-8-Q5) 「a ghost shows
  /// the pixels the screen shows」. ↩️Ghosts carried none while the Colors
  /// tint owned the paint's one colour-filter slot, which read as a design
  /// ("editing scaffolding") until `resolveCompositeEffectPaint` folded the
  /// two.
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

/// An onion row's GHOST — one of its cels before or after the frame, at its
/// peg's strength and tint — laid in the frame's own tree directly under
/// the row's drawing (`OnionSkinPlacement.inPlace`, onion-ghosts-in-place)
/// or with the other ghosts alone over the frame. Drawn as every row is,
/// from its cel; told apart only where a frame with its ghosts is laid
/// over the frame without them ([StackedFrame.whereTheGhostsShow]).
class CanvasGhostImageRequest extends CanvasLayerImageRequest {
  const CanvasGhostImageRequest({
    required super.frameKey,
    required super.opacity,
    super.blendMode,
    super.tint,
    super.effects,
  });
}

/// What a frame is drawn ON — the four a [StackedFrame] draws its nodes on:
/// the page's size, how far its pasteboard reaches, whether it
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

/// A row as a frame's body draws it from its cel's stored pixels
/// ([StackedFrame.of]): the layer, the tint an onion ghost wears over it
/// in Colors mode, whether it is a [ghost] ([CanvasGhostImageRequest]) —
/// and what it draws, as a frame's picture is signed by it (null where
/// that is not told: a node holding it is drawn afresh each time,
/// [HeldNodePictures]).
typedef StoredRow = ({
  CutFrameCompositeLayer layer,
  int? tint,
  bool ghost,
  CompositeLayerSignature? signature,
});

/// Where a frame's picture keeps the pictures its nodes are drawn into
/// ([HeldSubtreeRasters]) — whether the frame drawn here keeps the ones it
/// draws whole: the frame laid for a screen that stands on it, every row
/// in hand; a stroke's step patched into it only finds them — and what it
/// does with what lies below its pen ([below]).
typedef HeldNodePictures = ({
  HeldSubtreeRasters rasters,
  bool keeps,
  BelowThePen below,
});

/// 🚨★★★A FRAME'S ONE PICTURE IS DRAWN BY THE CANVAS'S OWN BODY
/// (one-picture-per-frame, D7-2-Q3=a — 「합성기는 하나」): [nodes], the
/// frame as a screen stacks it, composed over [FrameDrawing.extent] in
/// world coordinates as a miss composes the display buffer whole at 100% —
/// the paper as the root's bottom row, folders, adjustments, blends over
/// their backdrops, effects and poses — with every row drawn from its own
/// tiles, by the body the live row is drawn with ([_PaintCelSurface], from
/// what [storedRowOf] hands for it) — or, for a row a cel number is written
/// on with none, [bareRowOf]'s ([mapCompositeLeaves]), as for the row a pen
/// draws on with none. No second compositor: a frame's picture is what the
/// canvas would show of it.
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
    required StoredRow? Function(CanvasStackRow row) storedRowOf,
    required StoredRow? Function(CanvasStackRow row) bareRowOf,
    ({LiveRows rows, LiftedRowPainters painters})? live,
    HeldNodePictures? held,
  }) {
    _PaintRow? paintOf(StoredRow? row, CanvasStackRow of) => switch (row) {
      final stored? => _PaintCelSurface(
        stored,
        drawnOn: of is CanvasActiveLayerRow,
      ),
      null => null,
    };
    final drawn = mapCompositeLeaves<CanvasStackRow, _PaintRow>(
      nodes,
      (row) {
        if (live != null) {
          if (_liveRowOf(row, live.rows, live.painters) case final row?) {
            return row;
          }
        }
        // The row a pen draws on stands with nothing stored on it, as it is
        // drawn live: what lies below it is known before its first stroke
        // ([SubtreeHolding.drawnOn]).
        return paintOf(
          storedRowOf(row) ??
              (row is CanvasActiveLayerRow ? bareRowOf(row) : null),
          row,
        );
      },
      bare: (row) => paintOf(bareRowOf(row), row),
    );
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
            held: held,
          ),
    );
  }

  StackedFrame._(this._through)
    : _painter = _through(CanvasViewport(), 1, false);

  /// The body seen through a view, at a device's ratio — and, for a parity
  /// test, without the single buffer
  /// ([_LayerStackPainter.debugDisableSingleBuffer]).
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
  /// composed at the frame's own resolution, as its one picture is laid,
  /// and resampled as the picture is; the paper cut on the device's grid
  /// (F-67-paper-edge) — what the frame's picture shows of it (D7-2-Q2
  /// 「항상 원본 한장으로」; F-215 「on하든off하든 바뀌는게 없어야」). ⛔Not
  /// [drawing] through the view: that is the picture's raster, cut on the
  /// canvas's grid — an absent paper's checkerboard and the paper's own
  /// edge parted by a blended column.
  ///
  /// 🔬At the display's level (2026-10-25), the frame the conte's brush is
  /// switched on in cut each row's edge on the screen's grid, and the
  /// picture that landed after it blended it: 172 pixels, up to 28/255, at
  /// 1/6. So did every patch landing on a canvas zoomed out, at each step
  /// of a stroke.
  ///
  /// ⚠️What it costs, known and kept: zoomed out, a frame drawn whole as it
  /// stands — a float's drag, the stroke steps of a posed or bleeding row —
  /// is a buffer of the canvas's size at each paint, the cost the knee was
  /// dropped for ([_LayerStackPainter._maxBufferSide]). ⛔Not answered by
  /// going back to the levels: 유저 (D7-2-Q2, 2026-10-24) 「배율이 어떻든 항상
  /// 원본 한장 … 100%랑 통일하되, 그런 문제는 통일한 이후 극한으로
  /// 해결하고싶어」, 10-25 「원본기준으로 해서 쓸데없는 소재 없애고 거기서 극한
  /// 최적화 해야지」 — the cost is card one-picture-per-frame's to solve on
  /// this road.
  void paintOnScreen(
    Canvas canvas,
    Size size, {
    required CanvasViewport viewport,
    required double devicePixelRatio,
    @visibleForTesting bool debugDisableSingleBuffer = false,
  }) => labProbe(
    'layerStackPaint',
    // The paint pass (Round 6): one paint of the stack, as its own object,
    // constructed PER PAINT — its geometry fields are `late final`.
    () => _LayerStackPaintPass(
      _through(viewport, devicePixelRatio, debugDisableSingleBuffer),
    ).paint(canvas, size),
  );

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

  /// Where this frame's onion ghosts ([CanvasGhostImageRequest]) show in
  /// it, in world coordinates — all a frame laid with its ghosts in place
  /// differs by from the same frame laid without them: each ghost's ink,
  /// told as a stroke's change of the live row is
  /// ([_LayerStackPainter._whereAChangeShows]). Empty where none has ink;
  /// null where that cannot be told.
  Rect? get whereTheGhostsShow => _painter._whereTheGhostsShow();
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

/// The painter's own node shape: the request tree with images resolved.
sealed class _PaintRow {
  const _PaintRow();
}

/// The PAPER the rows are laid on, as the bottom row of the root scope
/// ([onUnderlay]): where an advanced blend composes over its backdrop,
/// the paper is in that backdrop, as a GPU blend reads it off the target
/// (brush-fidelity-Q4).
///
/// The pass paints it ([_LayerStackPaintPass._paintPaperInto]) — it knows
/// the edge — from the painter's own fields (`paintPaper`,
/// `paperBackground`).
final class _PaintPaper extends _PaintRow {
  const _PaintPaper();
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

  /// The tint an onion ghost wears over its cel ([CanvasLayerImageRequest.
  /// tint]) — none on a row a pen or a lift holds.
  int? get tint => null;

  _SurfaceRowPaint get paint => (
    opacity: opacity,
    blendMode: blendMode,
    placement: placement,
    effects: effects,
    tint: tint,
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
}

/// A cel drawn from its OWN TILES, as the plan hands it
/// ([CutFrameCompositeLayer]: its texts laid and its leading keys run on
/// the surface, the rest of its chain left to the paint) — every row of a
/// frame's one picture ([StackedFrame]), by the body the live row is
/// drawn with.
final class _PaintCelSurface extends _SurfaceRow {
  _PaintCelSurface(StoredRow row, {required this.drawnOn})
    : painter = BitmapSurfacePainter(
        surface: row.layer.surface,
        // The stack lays its own paper.
        showTransparentBackground: false,
      ),
      opacity = row.layer.opacity,
      blendMode = row.layer.blendMode,
      placement = row.layer.placement,
      effects = row.layer.effects,
      tint = row.tint,
      ghost = row.ghost,
      signature = row.signature;

  final BitmapSurfacePainter painter;

  /// What it draws ([StoredRow.signature]).
  final CompositeLayerSignature? signature;

  /// Whether it is an onion ghost ([StoredRow.ghost]).
  final bool ghost;

  /// Whether it is the row a pen draws on — the active layer's
  /// ([CanvasActiveLayerRow]), drawn from what is stored until a stroke
  /// holds it live ([_PaintActiveSurface]): what lies below it is held as
  /// one picture for the steps to come ([SubtreeHolding.drawnOn]).
  final bool drawnOn;
  @override
  final double opacity;
  @override
  final LayerBlendMode blendMode;
  @override
  final LayerPlacement? placement;
  @override
  final List<ResolvedLayerEffect> effects;
  @override
  final int? tint;

  /// None left to show a float through: the plan ran them on the surface,
  /// and nothing floats over a frame's picture.
  @override
  List<ResolvedLayerEffect> get keys => const [];
}

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

/// What a [StackedFrame] is drawn by: its rows and the page they stand on,
/// seen through a view — one paint of it is a [_LayerStackPaintPass].
final class _LayerStackPainter {
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
    this.held,
  });

  /// Where the frame's picture finds its nodes' pictures drawn before, and
  /// whether it keeps the ones it draws whole ([StackedFrame.of]).
  final HeldNodePictures? held;

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

  /// The last line the T12 probe in [_LayerStackPaintPass.paint] emitted.
  /// Static: a painter is a fresh object every frame, so an instance field
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

  /// 🚨(v) 2단계 — turns the single composite buffer OFF, so a test can
  /// render the SAME tree both ways and compare the pixels.
  ///
  /// ⚠️The comparison is only an identity at 1:1. That is not a weakness of
  /// the test, it is the change: above and below 100% the buffer resamples
  /// ONCE where the direct walk resampled every layer separately, and the
  /// pixels are supposed to differ there. So parity pins the composite —
  /// order, blending, paper, pasteboard — and a separate test pins the
  /// sampling law.
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
  /// that cannot be said: no live row, or one drawn from state it does not
  /// publish
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
  /// when the picture it is patched into last took it in — in canvas space
  /// ([_whereAChangeShows]), plus what it looks like now, for the next
  /// measure.
  ///
  /// 🎯[since] IS WHAT THE PICTURE HOLDS, not what the last paint drew.
  /// ↩️The display buffer's real base was a paint or three older than its
  /// head, and a dirty rect measured from the head's tokens left the steps
  /// between them out of the patch — a stroke with holes in it.
  ///
  /// 🚨`located: false` is the safe answer, and it costs only drawing the
  /// frame as it stands. It is the answer whenever the change cannot be
  /// located ([_liveSurfaceTokens]).
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
    if (dirty == null) {
      return (located: true, dirty: null, now: now);
    }
    final shows = _whereAChangeShows(
      nodes,
      dirty,
      _isTheLiveRow,
      paper: canvasSize.canvasRect,
    );
    return (located: shows != null, dirty: shows, now: now);
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

  /// Where a change at [rect] of the pixels of the row [isRow] picks shows
  /// in the composite of [list] ([_whereTheRowShows]) — or null where that
  /// cannot be told. The live surface a stroke's step changes
  /// ([_isTheLiveRow]), or an onion ghost a frame laid over its film adds
  /// ([_whereTheGhostsShow]): one question, one answer.
  ///
  /// ⛔The rect is INFLATED by one pixel. A dab writes whole texels, but the
  /// composite around it does not have to land on them — a posed sibling or
  /// a rounded edge can put ink a fraction over the line, and a patch that
  /// trusted the exact rect would leave a hairline of the previous frame.
  /// One pixel is cheap and the alternative is a class of bug that only
  /// shows on some zoom levels.
  static Rect? _whereAChangeShows(
    List<CompositeNode<_PaintRow>> list,
    Rect rect,
    bool Function(_PaintRow row) isRow, {
    required Rect paper,
  }) => _whereTheRowShows(list, rect, isRow, paper: paper)?.inflate(1);

  /// Where [rect] of the row [isRow] picks shows in the composite of [list]
  /// — or null where that cannot be told, or the row is not in it.
  ///
  /// An effect that SPREADS on a folder or an adjustment enclosing the
  /// surface — the stroke's pixels pass through its buffer — smears a dab
  /// past its own tile by as far as its chain reads past a pixel: the
  /// plan's `outsetPixels`, the number every buffer of the walk is grown by
  /// ([effectBufferBounds]). ↩️It drew the frame as it stands, whole, at
  /// every step, until the cost of a frame drawn as it stands was cut on
  /// the canvas's own resolution (one-picture-per-frame, 유저 2026-10-25
  /// 「원본 기준 위에서 푼다」). [paper] is where the paper lies, which a
  /// radial blur's reach is read from ([resolveCompositeEffectPlan]).
  ///
  /// Each node it stands in: a row read by another's chain stands where it
  /// lies and in the node that reads it ([CompositeReadsRows]).
  static Rect? _whereTheRowShows(
    List<CompositeNode<_PaintRow>> list,
    Rect rect,
    bool Function(_PaintRow row) isRow, {
    required Rect paper,
  }) {
    Rect? shows;
    for (final node in list.where((node) => holdsRow(node, isRow))) {
      final here = _whereItShowsIn(node, rect, isRow, paper: paper);
      if (here == null) {
        return null;
      }
      shows = shows?.expandToInclude(here) ?? here;
    }
    return shows;
  }

  /// [_whereTheRowShows] in [node], which holds the row.
  static Rect? _whereItShowsIn(
    CompositeNode<_PaintRow> node,
    Rect rect,
    bool Function(_PaintRow row) isRow, {
    required Rect paper,
  }) {
    Rect? inside() =>
        _whereTheRowShows(node.children, rect, isRow, paper: paper);
    switch (node) {
      case CompositeLeaf(payload: final _SurfaceRow row):
        // A chain of the row's own that spreads is told by its spread, as a
        // folder's is: the row reads it off a raster on the canvas's grid
        // (`_LayerStackPaintPass._paintSurfaceRow`). ↩️It was not told until
        // that raster (nested-folder-buffers-read-past-the-view-Q1 = c,
        // 2026-10-27): its blur rode a `saveLayer` the patch's clip cut,
        // and at 200% the patch came apart from the frame along the
        // stroke's tile by a band 2.5 canvas pixels wide.
        return _spreadThroughItsPose(row, rect, paper);
      case CompositeGroup(:final effects):
      case CompositeAdjustment(:final effects):
        return switch (inside()) {
          final at? => _spreadBy(effects, at, paper),
          null => null,
        };
      // A blend composes pixel by pixel: a dab moves the composite where it
      // lands and nowhere else, so only what the row passes through decides.
      case CompositeBackdropBlend():
      // So does a clip: the base's alpha cuts pixel by pixel, and the base
      // made opaque is the base's own pixels.
      case CompositeClip():
        return inside();
      case final CompositeReadsRows<_PaintRow> reads:
        return _whereReadShows(reads, rect, isRow, paper: paper);
      // Holding no row: nothing of theirs is told here.
      case CompositeLeaf():
      case CompositeOpaque():
      case CompositeCelNumber():
        return null;
    }
  }

  /// Where [rect] of the row [isRow] picks shows through [node]: in the
  /// node that reads, where it stands in it, and where the rows it reads
  /// hold it — read where it shows, pixel for pixel (🗣️I-132-Q21 a), so
  /// changed there and as far past as the reader's chain reads past a
  /// pixel ([_readerSpreads]).
  static Rect? _whereReadShows(
    CompositeReadsRows<_PaintRow> node,
    Rect rect,
    bool Function(_PaintRow row) isRow, {
    required Rect paper,
  }) {
    final CompositeReadsRows(node: reader, :rows) = node;
    final read = [for (final drawn in rows.values) ...drawn];
    final parts = [
      if (holdsRow(reader, isRow))
        _whereItShowsIn(reader, rect, isRow, paper: paper),
      if (read.any((drawn) => holdsRow(drawn, isRow)))
        switch (_whereTheRowShows(read, rect, isRow, paper: paper)) {
          final at? => _readerSpreads(reader, at, paper),
          null => null,
        },
    ];
    return parts.contains(null)
        ? null
        : parts.nonNulls.reduce((all, part) => all.expandToInclude(part));
  }

  /// [at] — where what [reader]'s chain reads changed — as far past as that
  /// chain reads past a pixel; null where that cannot be told: a posed
  /// row's, whose chain of its own reads past a pixel as a reader's does
  /// ([_spreadThroughItsPose]).
  static Rect? _readerSpreads(
    CompositeNode<_PaintRow> reader,
    Rect at,
    Rect paper,
  ) => switch (reader) {
    CompositeLeaf(payload: final _SurfaceRow row) =>
      row.placement == null ? _spreadBy(row.effects, at, paper) : null,
    CompositeGroup(:final effects) ||
    CompositeAdjustment(:final effects) => _spreadBy(effects, at, paper),
    // Only a row, a folder or an adjustment reads rows.
    CompositeLeaf() ||
    CompositeBackdropBlend() ||
    CompositeClip() ||
    CompositeOpaque() ||
    CompositeCelNumber() ||
    CompositeReadsRows() => null,
  };

  /// [rect] — a change in [row]'s artwork — where it shows on the canvas:
  /// grown by as far as its own chain reads past a pixel on an unposed row;
  /// through its pose where the pose keeps the axes
  /// ([GuideTransform.keepsTheAxes]) and the row wears no chain of its own
  /// and blends normal; null otherwise — told nothing, the frame drawn as
  /// it stands.
  ///
  /// ⛔A POSED ROW'S OWN CHAIN OR BLEND IS NOT TOLD. 🔬A blur of its own on
  /// a row enlarged 2.5× came apart from the frame laid whole by 1–2/255
  /// over the whole of its spread at every view — its raster as large as
  /// the patch, as a blur under a clip comes apart by the size of what it
  /// reads (a-blur-under-a-clip-cuts-its-edge-on-vulkan-Q1); the same row
  /// adding (`plus`) by up to 8/255 along a line of the patch (the tester's
  /// Vulkan, 2026-10-30).
  ///
  /// ⛔A TURN THAT LEAVES THE AXES IS NOT TOLD. 🔬Impeller covers an edge
  /// that does not lie along the pixel grid by what falls on each side of
  /// it, and where a sample lies on it depends on the size of the raster it
  /// is drawn into — not on where the raster's origin is (the tester's
  /// Vulkan, 2026-10-30: four tiles of one page turned by 30° and enlarged
  /// 2.5×, by one `drawAtlas` or a `drawImageRect` each, drawn again from
  /// another origin into a raster of the same size 0 apart, into one of
  /// another size 5–6 pixels apart by up to 8/255; the tester's Skia, which
  /// cuts an edge by a pixel's centre, a pixel by 32). A patch is a raster
  /// of its own size, so on a turned row its tiles' seams came apart from
  /// the frame laid whole — a few pixels on them at every view, patched
  /// where the step moved or over the whole picture alike. A pose that
  /// keeps the axes lays every edge along the grid, and its patch is the
  /// frame laid whole (moved, halved, stretched, enlarged, flipped, turned
  /// a quarter, at half opacity, in a blurred folder: 0 apart, and the
  /// 1/255 the tester halves a level by at 50% on a 1.5 screen).
  /// ↩️Every pose was refused until then (2026-10-27).
  static Rect? _spreadThroughItsPose(_SurfaceRow row, Rect rect, Rect paper) =>
      switch (row.placement) {
        null => _spreadBy(row.effects, rect, paper),
        final placed
            when placed.keepsTheAxes &&
                row.effects.isEmpty &&
                row.blendMode == LayerBlendMode.normal =>
          MatrixUtils.transformRect(placementMatrix(placed), rect),
        _ => null,
      };

  /// [rect] grown by as far as [effects] read past a pixel, on [paper].
  static Rect _spreadBy(
    List<ResolvedLayerEffect> effects,
    Rect rect,
    Rect paper,
  ) => effectBufferBounds(
    rect,
    resolveCompositeEffectPlan(effects, paper: paper).outsetPixels,
  );

  /// Whether [row] is the live surface ([holdsRow]) — not a lifted row:
  /// that only shows, and nothing draws into it.
  static bool _isTheLiveRow(_PaintRow row) => row is _PaintActiveSurface;

  /// [StackedFrame.whereTheGhostsShow]: where each ghost's ink shows
  /// ([_whereAChangeShows]), together.
  Rect? _whereTheGhostsShow() {
    var shows = Rect.zero;
    for (final node in preorderNodes(nodes)) {
      if (node case CompositeLeaf(
        payload: final _PaintCelSurface ghost,
      ) when ghost.ghost) {
        final ink = ghost.painter.drawnWorldRect;
        if (ink.isEmpty) {
          continue;
        }
        final where = _whereAChangeShows(
          nodes,
          ink,
          (row) => identical(row, ghost),
          paper: canvasSize.canvasRect,
        );
        if (where == null) {
          return null;
        }
        shows = shows.isEmpty ? where : shows.expandToInclude(where);
      }
    }
    return shows;
  }
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
