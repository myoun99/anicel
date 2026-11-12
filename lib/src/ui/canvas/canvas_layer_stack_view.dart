import 'package:flutter/widgets.dart';
import 'package:gpu_engine/gpu_engine.dart'
    show
        GpuComposite,
        GpuFloodPicture,
        GpuMask,
        GpuPlan,
        GpuPool,
        GpuScreen,
        GpuTarget,
        gpuTileBytes,
        gpuTileSide;

import '../../core/collection_equality.dart';
import '../../core/floor_math.dart';
import '../../core/tree_nodes.dart';
import '../../services/canvas_flood_fill.dart' show FloodFillRegion;
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
import 'active_stroke_overlay.dart' show OverlayMoveMark;
import 'bitmap_surface_painter.dart';
import '../../services/layer_pose_paint.dart';
import '../../services/composite_effect_paint.dart';
import 'display_resample.dart';
import 'landing_preview.dart';
import 'selection_float_overlay.dart';
import 'subtree_image_composite.dart';
import 'viewport_canvas_transform.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/cel_text_laying.dart' show celSurfaceWithTextsLaid;
import '../../services/guide_geometry.dart' show GuideTransform;
import '../../services/se_name_tag_plan.dart' show ResolvedSeNameTag;
import '../../services/playback/cut_frame_composite_signature.dart'
    show
        CompositeLayerSignature,
        CompositeNodeSignature,
        CompositeRowSignature,
        CutFrameCompositeSignature,
        SeNameTagRowSignature;
import 'tile_origin.dart';
import '../text/se_name_tag_paint.dart' show seNameTagExtent;
import '../../core/display_filter.dart' show filterQualityForDisplayScale;
import '../../models/dirty_region.dart';
import '../../native/app_gpu_engine.dart' show FrameKernelsToCome;
import '../../native/composite_tree_plan.dart';
import '../../native/engine_chain_holds.dart';
import '../../native/engine_letters.dart';
import '../../native/engine_range_mask.dart';
import '../../native/engine_row_pose.dart'
    show gpuRowInverse, gpuSamplingOf;
import '../../native/engine_tile_ledger.dart';
import '../../native/screen_texture.dart';
import 'fx_plugin_stages.dart';

part 'layer_stack/layer_stack_engine_screen.dart';
part 'layer_stack/layer_stack_frame_reading.dart';

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
  /// ★WHOLE, like [CanvasLayerImageRequest.effects]: the stack's
  /// `shouldRepaint` diffs this field, and the composite applies all of it
  /// — keys and plugins too, the chain's own. ↩️A plugin at the chain's
  /// head, after the keys before it, was run on the surface and taken out
  /// of the paint, until it was a step of the chain
  /// (float-warp-resamples-in-the-c-engine (2), 2026-11-11).
  final List<ResolvedLayerEffect> effects;

  /// The leading run of colour keys ([celSourceKeys]), which a float over
  /// the row asks after.
  List<ResolvedLayerEffect> get sourceEffects => celSourceKeys(effects);
}

/// A [LiftedCel] as the view draws it: the painter its surface is shown by,
/// and its float.
typedef _LiftedRowPaint = ({
  BitmapSurfacePainter surface,
  SelectionFloatOverlay? float,
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
  /// ⛔THE WHOLE CHAIN: the two `shouldRepaint` comparisons diff this
  /// field, and the composite applies all of it.
  final List<ResolvedLayerEffect> effects;

  /// The leading run of colour keys ([CanvasActiveLayerRow.sourceEffects]'s).
  List<ResolvedLayerEffect> get sourceEffects => celSourceKeys(effects);
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

/// An SE row's NAME TAG, a row of the frame's own picture (card
/// the-flutter-fx-chain-is-a-second-chain, 🗣️-Q1 유저 2026-11-12
/// 「가이드선이 이름표 위에 그려져도 된다 — 이름표를 엔진 그림 안으로」): its
/// plate in its own space ([seNameTagExtent]), laid by its placement —
/// normal, whatever the row's blend (🗣️F-387-Q5). It names no cel: it is
/// drawn from the tag alone.
///
/// Its opacity and its chain are the folder round it ([nameTagRows]): they
/// take the tag as ONE picture, as a folder's take its members — the box
/// under the name is not seen through the name, and a blur reads both
/// (🗣️F-387, 유저 2026-10-19: 「같은 fx인데 다른건 말이안됨. 다른것도
/// 확인해서 통일」).
///
/// ↩️Each route painted the tags over the frame it had composited — the
/// editing canvas, playback, the export and the parked track stack —, each
/// through a chain of its own beside the engine's: never baked into a
/// picture, so a rename made none again (R5b).
final class CanvasNameTagRow extends CanvasStackRow {
  const CanvasNameTagRow(this.tag);

  final ResolvedSeNameTag tag;
}

/// [tags] as a frame's rows ([CanvasNameTagRow]), bottom to top — laid
/// over every other row of it by whoever stacks the frame. None for a tag
/// at no strength.
///
/// A tag at less than full strength or through a chain is a folder round
/// its row, at its opacity through its chain — normal (🗣️F-387-Q5): the
/// tag laid on the canvas first and taken as one picture there, the way a
/// folder takes its members (🗣️F-387) — so its blur is the canvas's
/// pixels wherever the shot lays it, and repeats the canvas's edge.
List<CompositeNode<CanvasStackRow>> nameTagRows(
  List<ResolvedSeNameTag> tags,
) => [
  for (final tag in tags)
    if (tag.opacity > 0)
      switch (CompositeLeaf<CanvasStackRow>(CanvasNameTagRow(tag))) {
        final row when tag.opacity >= 1 && tag.effects.isEmpty => row,
        final row => CompositeGroup(
          children: [row],
          opacity: tag.opacity,
          blendMode: LayerBlendMode.normal,
          effects: tag.effects,
        ),
      },
];

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

/// What the live surface looked like, per coordinate: what shows each of
/// the overlay's (`ActiveStrokeOverlayModel.shownBy`) and the committed
/// tiles. Identity per coordinate is what lets the next look say WHERE the
/// surface changed ([StackedFrame.movedSince]).
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
/// (`BitmapSurfacePainter.landingPreview`), and the selection floated in
/// the live row's slot (`LiveRows.floatOverlay`) — told alike, each where
/// its slot draws it ([_SurfaceSlot.floated]).
/// ↩️The stamp's ghost was the first (F-33 drew it inside the painter),
/// until brush-fidelity-Q9 (유저 2026-10-18 「통일하면 좋음」) moved it to the
/// overlay's CPU pre-blended tiles, which [overlay] carries.
///
/// 🚨★★★AND THE ROWS A LIFT HOLDS BESIDE THE LIVE ONE, BY THE SAME LAW
/// ([lifted]): each by its cel, its surface's tiles and its float
/// ([LiftedRowTokens]).
///
/// ⛔A float moves under the hand without touching anything else a token
/// sees — not the tree, not the surface's tiles, not the overlay's —, so
/// untold, a picture patched past it would freeze the canvas for the whole
/// drag: found by walking the painter's own body asking 「what else can
/// change」 ([[cache-what-can-say-where-it-changed]],
/// `float_drag_is_never_cached_test`).
///
/// ↩️A float or a lift in hand told nothing, and while either was the
/// frame was drawn as it stands, whole, at every step
/// (`_FrameRows._liveCanBeTold`, from `e65f29037` 2026-08-15 — a session's
/// call, no one's word: 「declining to patch costs only what drawing the
/// frame as it stands costs」). 🔬What that cost on the Surface Pro 11
/// (profile, S5_BA cut 352, 68 rows, fitted, a box dragged 4 px every
/// 8 ms, 2026-11-12): a frame's build p50 22 ms, ≈19 ms of it the UI
/// thread waiting on the GPU for the whole frame composed again
/// (`GpuScreen.show`); composed over the box alone, 10–13 ms
/// (a-float-in-hand-draws-the-frame-as-it-stands).
typedef LiveSurfaceTokens = ({
  Map<Object, Object> overlay,
  OverlayMoveMark? overlayMoves,
  Map<Object, Object> tiles,
  List<({Object value, Rect rect})> previews,
  Map<BrushFrameKey, LiftedRowTokens> lifted,
});

/// A row a lift holds beside the live one, as [LiveSurfaceTokens.lifted]
/// tells it: its surface's tiles and its float — by value, beside where
/// its slot draws it — and the tiles of its cel as stored, what the row
/// shows before the lift takes it up and once the lift lets it go (null
/// where they are not in hand: such a change cannot be told).
typedef LiftedRowTokens = ({
  int tileSize,
  Map<Object, Object> tiles,
  Map<Object, Object>? stored,
  ({Object value, Rect rect})? float,
});

/// A row as a frame's body draws it from its cel's stored pixels
/// ([StackedFrame.of]): the layer, the tint an onion ghost wears over it
/// in Colors mode, whether it is a [ghost] ([CanvasGhostImageRequest]) —
/// and what it draws, as a frame's picture is signed by it (null where
/// that is not told: a node holding it is run afresh each time).
typedef StoredRow = ({
  CutFrameCompositeLayer layer,
  int? tint,
  bool ghost,
  CompositeLayerSignature? signature,
});

/// 🚨★★★A FRAME'S ONE PICTURE IS LAID FROM THE ROWS THE CANVAS STACKS
/// (one-picture-per-frame, D7-2-Q3=a — 「합성기는 하나」): [nodes], the
/// frame as a screen stacks it, over [extent] in world coordinates — the
/// paper as the root's bottom row, folders, adjustments, blends over their
/// backdrops, effects and poses — with every row from its own tiles, from
/// what [storedRowOf] hands for it — or, for a row a cel number is written
/// on with none, [bareRowOf]'s ([mapCompositeLeaves]), as for the row a pen
/// draws on with none. The engine lays it (`EngineStackScreen`): no second
/// compositor.
///
/// Under [live], the rows a canvas that stands holds live are shown as they
/// stand ([_liveRowOf]) — the frame AS IT STANDS, what its strokes patch
/// into the picture ([movedSince]).
///
/// The extent is the page and every row's content.
///
/// 🚨PAST ITS EXTENT A FRAME IS NOTHING, and the picture holds what lies
/// past the paper — what the rows lay over no paper, as they lay it. A
/// screen lays its pasteboard under it, in a colour each view sets for
/// itself (`BrushCanvasPanel.pasteboardColor`); laid into the picture, one
/// frame would be a picture per colour.
final class StackedFrame {
  factory StackedFrame.of(
    List<CompositeNode<CanvasStackRow>> nodes, {
    required FramePage page,
    required StoredRow? Function(CanvasStackRow row) storedRowOf,
    required StoredRow? Function(CanvasStackRow row) bareRowOf,
    ({LiveRows rows, LiftedRowPainters painters})? live,
  }) {
    _PaintRow? paintOf(StoredRow? row, CanvasStackRow of) => switch (row) {
      final stored? => _PaintCelSurface(
        stored,
        frameKey: switch (of) {
          CanvasActiveLayerRow(:final frameKey) => frameKey,
          CanvasLayerImageRequest(:final frameKey) => frameKey,
          CanvasNameTagRow() => null,
        },
      ),
      null => null,
    };
    final drawn = mapCompositeLeaves<CanvasStackRow, _PaintRow>(
      nodes,
      (row) {
        if (row case CanvasNameTagRow(:final tag)) {
          return _PaintNameTag(tag);
        }
        if (live != null) {
          if (_liveRowOf(row, live.rows, live.painters, storedRowOf)
              case final row?) {
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
      _FrameRows(
        nodes: drawn,
        activeSurfacePainter: live?.rows.activeSurfacePainter,
        floatOverlay: live?.rows.floatOverlay,
        liftedRows: liftedRows,
        canvasSize: page.canvasSize,
        pasteboardReach: page.pasteboardReach,
        paintPaper: page.paintPaper,
        paperBackground: page.paperBackground,
      ),
    );
  }

  StackedFrame._(this._painter);

  /// The rows and the page they stand on.
  final _FrameRows _painter;

  /// The world the frame covers, asked afresh each time: a stroke grows
  /// what the live row covers.
  Rect get extent => _FrameReading(_painter).frameExtent();

  /// What moves the live rows' pixels with no new frame — a stroke's step,
  /// a float's or a lift's drag — as it repaints the canvas's own stack.
  Listenable get changes => _FrameRows._liveListenable(
    _painter.activeSurfacePainter,
    _painter.floatOverlay,
    _painter.liftedRows,
  );

  /// What the live rows look like now, to measure their next change from
  /// ([_FrameRows._liveSurfaceTokens]) — nothing where nothing is drawn
  /// live.
  LiveSurfaceTokens get tokens => _painter._liveSurfaceTokens();

  /// Where the live row's pixels moved since [since], in world coordinates
  /// ([_FrameRows._liveDirtyCanvasRect]).
  ({bool located, Rect? dirty, LiveSurfaceTokens now}) movedSince(
    LiveSurfaceTokens since,
  ) => _painter._liveDirtyCanvasRect(since: since);

  /// Where this frame's onion ghosts ([CanvasGhostImageRequest]) show in
  /// it, in world coordinates — all a frame laid with its ghosts in place
  /// differs by from the same frame laid without them: each ghost's ink,
  /// told as a stroke's change of the live row is
  /// ([_FrameRows._whereAChangeShows]). Empty where none has ink;
  /// null where that cannot be told.
  Rect? get whereTheGhostsShow => _painter._whereTheGhostsShow();
}

/// Whether [nodes] hold a plugin's step — one run over what its chain made
/// before it, wherever it stands (`PluginEffect`, 🗣️I-132-Q34 a): a frame
/// drawn whole only by a recording that waits for its plugins
/// (`FxPluginStages`), and drawn as it stands with the step as if off.
bool waitsForItsPlugins(List<CompositeNode<CanvasStackRow>> nodes) =>
    preorderNodes(nodes).any(
      (node) => switch (node) {
        CompositeLeaf(payload: CanvasActiveLayerRow(:final effects)) ||
        CompositeLeaf(payload: CanvasLayerImageRequest(:final effects)) ||
        CompositeGroup(:final effects) ||
        CompositeAdjustment(:final effects) => _runsAPlugin(effects),
        _ => false,
      },
    );

bool _runsAPlugin(List<ResolvedLayerEffect> chain) => chain.any(
  (effect) => effect.kind == EffectKind.plugin && effect.run != null,
);

/// The painters the rows a lift holds beside the live one are drawn by
/// ([LiftedCel]), by cel — kept while a row's surface stays what it was: a
/// new painter is a new set of tile pictures, and a drag step changes
/// none. A screen keeps one across its paints.
final class LiftedRowPainters {
  final Map<
    BrushFrameKey,
    ({BitmapSurface surface, BitmapSurfacePainter painter})
  >
  _held = {};

  /// [lifted] as [request]'s row draws it.
  _LiftedRowPaint _of(CanvasLayerImageRequest request, LiftedCel lifted) {
    final held = _held[request.frameKey];
    if (held != null && identical(held.surface, lifted.surface)) {
      return (surface: held.painter, float: lifted.float);
    }
    final painter = BitmapSurfacePainter(
      // Shown as the row's image is, its texts laid; its chain rides the
      // row's paint.
      surface: lifted.surface,
      // The stack draws in canvas space, as for the live row.
      showTransparentBackground: false,
      lineage: request.frameKey.cel,
    );
    _held[request.frameKey] = (surface: lifted.surface, painter: painter);
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
/// it is drawn from what is stored ([storedRowOf]).
_PaintRow? _liveRowOf(
  CanvasStackRow row,
  LiveRows live,
  LiftedRowPainters painters,
  StoredRow? Function(CanvasStackRow row) storedRowOf,
) => switch (row) {
  // A row a lift holds beside the live one draws its lifted surface —
  // whether or not its image is held: that is the cel as it stands, and
  // the lift is what shows while the box is open (I-37 · F-329).
  final CanvasLayerImageRequest request
      when live.liftedRows.containsKey(request.frameKey) =>
    _PaintLiftedSurface(
      lifted: painters._of(request, live.liftedRows[request.frameKey]!),
      frameKey: request.frameKey,
      stored: switch (storedRowOf(request)) {
        null => null,
        // Laid as the row's own painter lays it ([_PaintCelSurface]).
        final stored => celSurfaceWithTextsLaid(stored.layer.surface),
      },
      opacity: request.opacity,
      blendMode: request.blendMode,
      placement: request.placement,
      effects: request.effects,
      keys: request.sourceEffects,
    ),
  final CanvasActiveLayerRow active when live.activeSurfacePainter != null =>
    _PaintActiveSurface(
      opacity: active.opacity,
      blendMode: active.blendMode,
      placement: active.placement,
      effects: active.effects,
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
final class _PaintPaper extends _PaintRow {
  const _PaintPaper();
}

/// An SE row's name tag ([CanvasNameTagRow]): its plate, made by the
/// engine's letters as a cel number's is (`EngineLetters.seNameTagPlate`).
final class _PaintNameTag extends _PaintRow {
  const _PaintNameTag(this.tag);

  final ResolvedSeNameTag tag;
}

/// A row drawn as a SURFACE — the live one, or one a lift holds beside it —
/// and what its layer composites with.
sealed class _SurfaceRow extends _PaintRow {
  const _SurfaceRow();

  double get opacity;
  LayerBlendMode get blendMode;
  LayerPlacement? get placement;
  List<ResolvedLayerEffect> get effects;

  /// The leading run of the row's chain — the colour keys still on its
  /// cel's own bytes and a plugin after them — which a float over it asks
  /// after ([SelectionFloatPaint.shownOn]).
  List<ResolvedLayerEffect> get keys;

  /// The tint an onion ghost wears over its cel ([CanvasLayerImageRequest.
  /// tint]) — none on a row a pen or a lift holds.
  int? get tint => null;
}

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

/// A row a folder's move session holds lifted ([LiftedCel]): its lifted
/// surface with its float over it — in its own slot, with its own row's
/// paint.
final class _PaintLiftedSurface extends _SurfaceRow {
  const _PaintLiftedSurface({
    required this.lifted,
    required this.frameKey,
    required this.stored,
    required this.opacity,
    required this.blendMode,
    required this.placement,
    required this.effects,
    required this.keys,
  });

  final _LiftedRowPaint lifted;

  /// The cel the lift holds ([LiveRows.liftedRows]).
  final BrushFrameKey frameKey;

  /// That cel's surface as stored, its texts laid — what the row shows with
  /// no lift on it — or null where it is not in hand.
  final BitmapSurface? stored;
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
/// ([CutFrameCompositeLayer]: its texts laid and a plugin at its chain's
/// head run on the surface, the rest of its chain — keys alone included —
/// left to the paint) — every row of a frame's one picture
/// ([StackedFrame]).
final class _PaintCelSurface extends _SurfaceRow {
  _PaintCelSurface(StoredRow row, {required this.frameKey})
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

  /// The cel its row names — or null for a row that names none.
  final BrushFrameKey? frameKey;

  /// That cel ([BrushFrameKey.cel]) — what the engine keeps its tiles
  /// under ([EngineTiles.lineage]).
  Object? get lineage => frameKey?.cel;
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

  /// None asked after: nothing floats over a frame's picture.
  @override
  List<ResolvedLayerEffect> get keys => const [];
}

/// What a [StackedFrame] is laid from: its rows and the page they stand on
/// — one reading of it is a [_FrameReading].
final class _FrameRows {
  _FrameRows({
    required this.nodes,
    this.activeSurfacePainter,
    this.floatOverlay,
    this.liftedRows = const {},
    required this.canvasSize,
    required this.pasteboardReach,
    required this.paintPaper,
    required this.paperBackground,
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
    for (final lifted in liftedRows.values) ...[lifted.surface, ?lifted.float],
  ]);

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
  final bool paintPaper;
  final ProjectBackground paperBackground;

  /// The coordinates whose token moved from [last] to [now]: one [now]
  /// holds under a different token (or newly), and one [now] no longer
  /// holds at all.
  ///
  /// Identity per coordinate — for what shows the overlay's and the
  /// committed tiles alike. The overlay's tiles carry the stroke in
  /// flight, but they ACCUMULATE for the stroke's whole life (nothing
  /// leaves the map until pen-up), so "every overlay coordinate" is the
  /// bounding box of the WHOLE STROKE by the third dab: a long line paid
  /// its full length again on every step. The overlay replaces what shows
  /// a coordinate only when a dab touched it, so an unchanged object IS
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

  /// What the live surface looks like NOW, per coordinate — and the rows a
  /// lift holds beside it. That is the answer that makes a patch honest: ask
  /// the thing you are patching where it changed, and do not patch what
  /// cannot say ([_liveDirtyCanvasRect]).
  ///
  /// ⛔Nothing drawn live is tokens of nothing, not none: a lift taken up
  /// where no row is under the pen — a folder's, picked on the timeline — is
  /// told against the frame the picture holds, as any other change.
  ///
  /// The overlay's tiles carry the stroke in flight — but they ACCUMULATE
  /// for the stroke's whole life (nothing leaves the map until pen-up), so
  /// "every overlay coordinate" is the bounding box of the WHOLE STROKE by
  /// the third dab: a long line paid its full length again on every step.
  /// Identity per coordinate instead, exactly like the committed tiles —
  /// the overlay replaces what shows a coordinate only when a dab touched
  /// it, so an unchanged object IS "this tile did not move".
  ///
  /// 🚨NO PICTURE IS ASKED FOR, to measure by: what shows a coordinate is
  /// the token (`ActiveStrokeOverlayModel.shownBy`). ↩️The overlay's
  /// pictures were, copied here — and the copy read each, which made one
  /// of every tile the step had moved: of a tile the engine laid, a wait
  /// for the GPU to read it back, for a picture this screen never drew
  /// (till 2026-11-12).
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
  LiveSurfaceTokens _liveSurfaceTokens() {
    final surfacePainter = activeSurfacePainter;
    final reading = _FrameReading(this);
    final overlay = surfacePainter?.overlayModel;
    // F-344: the text in hand floated over its hole is part of what the
    // live surface looks like, so it is part of the tokens — by value, with
    // the rect it covers, so a drag can be patched. ↩️F-130 put the stamp's
    // ghost here too; since brush-fidelity-Q9 it is the overlay's tiles.
    final landing = surfacePainter?.landingPreview?.value;
    // I-160: the range a held fill covers, drawn over the row — by value
    // too, so a press that moves to another region patches both.
    final range = overlay?.fillRange;
    return (
      overlay: overlay?.shownBy ?? const <TileCoord, Object>{},
      overlayMoves: overlay?.moveMark,
      tiles: _tilesOf(surfacePainter?.surface),
      previews: [
        ?_floatTold(reading._activeSlot),
        if (landing != null) (value: landing, rect: landing.drawnWorldRect),
        if (range != null) (value: range, rect: range.bounds),
      ],
      lifted: {
        for (final row in _liftedRowsIn(nodes))
          row.frameKey: (
            tileSize: row.lifted.surface.surface.tileSize,
            tiles: _tilesOf(row.lifted.surface.surface),
            stored: switch (row.stored) {
              null => null,
              final stored => _tilesOf(stored),
            },
            float: _floatTold(reading._slotOf(row)),
          ),
      },
    );
  }

  /// [surface]'s tiles, by coordinate — none for no surface.
  static Map<Object, Object> _tilesOf(BitmapSurface? surface) => {
    if (surface != null)
      for (final entry in surface.tiles.entries) entry.key: entry.value,
  };

  /// The float [slot] draws over its surface, by its value (its own `==`,
  /// exactly what a step of the hand changes) beside where the slot draws
  /// it ([_SurfaceSlot.floated]) — null where nothing floats.
  static ({Object value, Rect rect})? _floatTold(_SurfaceSlot? slot) =>
      switch ((slot?.float?.value, slot?.floated)) {
        (final value?, final rect?) => (value: value, rect: rect),
        _ => null,
      };

  /// The rows a lift holds beside the live one, wherever the folders put
  /// them.
  static List<_PaintLiftedSurface> _liftedRowsIn(
    List<CompositeNode<_PaintRow>> nodes,
  ) => [
    for (final node in preorderNodes(nodes))
      if (node case CompositeLeaf(payload: final _PaintLiftedSurface row)) row,
  ];

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
  ({bool located, Rect? dirty, LiveSurfaceTokens now})
  _liveDirtyCanvasRect({required LiveSurfaceTokens since}) {
    final now = _liveSurfaceTokens();
    Rect? shows;
    for (final (:moved, :isRow) in [
      (moved: _whereTheLiveRowMoved(since, now), isRow: _isTheLiveRow),
      for (final cel in {...since.lifted.keys, ...now.lifted.keys})
        (
          moved: _whereALiftedRowMoved(since.lifted[cel], now.lifted[cel]),
          isRow: (_PaintRow row) => _showsTheCel(row, cel),
        ),
    ]) {
      if (!moved.located) {
        return (located: false, dirty: null, now: now);
      }
      final rect = moved.rect;
      if (rect == null) {
        continue;
      }
      final here = _whereAChangeShows(
        nodes,
        rect,
        isRow,
        paper: canvasSize.canvasRect,
      );
      if (here == null) {
        return (located: false, dirty: null, now: now);
      }
      shows = shows?.expandToInclude(here) ?? here;
    }
    return (located: true, dirty: shows, now: now);
  }

  /// What of the live row moved from [kept] to [now], in its own space:
  /// the overlay's pictures, the tiles, and what its slot draws over them —
  /// not located where the row went from under the pen, told nowhere now.
  ({bool located, Rect? rect}) _whereTheLiveRowMoved(
    LiveSurfaceTokens kept,
    LiveSurfaceTokens now,
  ) {
    final painter = activeSurfacePainter;
    if (painter == null) {
      return (
        located:
            kept.tiles.isEmpty &&
            kept.overlay.isEmpty &&
            kept.previews.isEmpty,
        rect: null,
      );
    }
    var dirty = _whereTheOverlayMoved(kept, now);
    final tiles = tileCoordsWorldRect(
      _movedCoords(kept.tiles, now.tiles),
      painter.surface.tileSize,
    );
    if (tiles != null) {
      dirty = dirty?.expandToInclude(tiles) ?? tiles;
    }
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
    return (located: true, rect: dirty);
  }

  /// What of a row a lift holds moved from [kept] to [now], in its own
  /// space ([LiftedRowTokens]): its tiles, and its float where it WAS and
  /// where it IS (F-130) — or, where the lift took it up or let it go, what
  /// it shows on the one side against its cel as stored on the other.
  static ({bool located, Rect? rect}) _whereALiftedRowMoved(
    LiftedRowTokens? kept,
    LiftedRowTokens? now,
  ) {
    if (kept != null && now != null) {
      final floats = kept.float?.value == now.float?.value
          ? const <({Object value, Rect rect})>[]
          : [?kept.float, ?now.float];
      return (
        located: true,
        rect: _joined(
          tileCoordsWorldRect(
            _movedCoords(kept.tiles, now.tiles),
            now.tileSize,
          ),
          floats,
        ),
      );
    }
    final one = (now ?? kept)!;
    final stored = one.stored;
    if (stored == null) {
      return (located: false, rect: null);
    }
    return (
      located: true,
      rect: _joined(
        tileCoordsWorldRect(_movedCoords(stored, one.tiles), one.tileSize),
        [?one.float],
      ),
    );
  }

  /// [tiles] with every one of [floats]' rects.
  static Rect? _joined(
    Rect? tiles,
    List<({Object value, Rect rect})> floats,
  ) {
    var joined = tiles;
    for (final float in floats) {
      joined = joined?.expandToInclude(float.rect) ?? float.rect;
    }
    return joined;
  }

  /// What the overlay's pictures moved from [kept] to [now], in the live
  /// row's space: the pixels the stroke moved
  /// ([ActiveStrokeOverlayModel.movedSince]) where a change there shows
  /// there and nowhere else, and the tiles it moved anywhere else.
  ///
  /// 🚨A TILE IS WHAT A PICTURE IS MADE OF, NOT WHAT MOVED. ↩️A step of a
  /// 20 px line wrote about 46,000 texels into the frame's picture to change
  /// 2,300 (F-533). 🔬Main PC, 144 Hz, S5_BA cut 352, every row on, fitted,
  /// 300 px/s, in turn in one run, input to raster end p50 / p90. Under
  /// another session's tests, 20 px 38.1–39.4 / 54.8–61.2 → 34.8–37.7 /
  /// 45.7–55.5 ms and 300 px 48.9–55.0 / 60.3–79.0 → 44.0–49.9 / 59.0–66.7 ms,
  /// with 10–20% more steps. Quiet, 20 px 9.0–9.7 → 8.6–9.3 ms p50, 300 px
  /// 13.3–16.1 / 21–22 → 11.9–13.7 / 18 ms. Quiet at 60% the times do not
  /// move: there a step is held for the frame, and the raster has room.
  ///
  /// ⛔NOT THROUGH A POSE OR A SPREAD, where a change does not show as
  /// itself: those keep the tiles. A tile's quad holds all it shows, however
  /// a pose samples it; a dab's rect does not, and past it a row enlarged
  /// reads half a texel, as wide on the canvas as the row is enlarged. And a
  /// spread's raster is as large as the patch, which on Vulkan comes apart
  /// from the frame along the patch's edge
  /// (a-blur-under-a-clip-cuts-its-edge-on-vulkan): left on the tile, that
  /// edge stays off the ink.
  Rect? _whereTheOverlayMoved(LiveSurfaceTokens kept, LiveSurfaceTokens now) {
    final painter = activeSurfacePainter!;
    final tiles = tileCoordsWorldRect(
      _movedCoords(kept.overlay, now.overlay),
      painter.surface.tileSize,
    );
    final mark = kept.overlayMoves;
    if (tiles == null || mark == null) {
      return tiles;
    }
    final moved = painter.overlayModel?.movedSince(mark)?.rect;
    final showsAsItself =
        moved != null &&
        _whereTheRowShows(
              nodes,
              moved,
              _isTheLiveRow,
              paper: canvasSize.canvasRect,
            ) ==
            moved;
    return showsAsItself ? moved : tiles;
  }

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
        // (`_FrameReading._paintSurfaceRow`). ↩️It was not told until
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

  /// Whether [row] shows [cel]: lifted, or as stored, once a lift let it
  /// go.
  static bool _showsTheCel(_PaintRow row, BrushFrameKey cel) => switch (row) {
    _PaintLiftedSurface(:final frameKey) ||
    _PaintCelSurface(:final frameKey?) => frameKey == cel,
    _ => false,
  };

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
