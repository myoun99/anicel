import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../models/placed_tile.dart';
import '../../models/bitmap_surface.dart';
import '../../services/input/pen_sidecars.dart';
import '../brush/brush_tool_state.dart' show CanvasTool;
import '../../models/app_input_settings.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_edit_session_state.dart';
import '../../models/canvas_point.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/dirty_region.dart';
import '../../models/canvas_viewport.dart';
import '../../models/tile_coord.dart';
import '../../models/viewport_point.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../services/brush_dab_interpolator.dart';
import '../../services/brush_ground_color_mixing.dart';
import '../../services/brush_ground_color_sampling.dart';
import '../../services/straight_rgba_image.dart'
    show decodeStraightRgbaImage, decodedImageStillWanted;
import '../../services/brush_live_stroke_rasterizer.dart';
import '../../services/brush_stroke_dynamics.dart';
import '../../services/brush_tip_stamp_cache.dart';
import '../../services/brush_pressure_dynamics.dart';
import '../../services/brush_stroke_blend.dart'
    show applySelectionMaskToStrokeAlpha;
import '../../services/brush_stroke_commit_data.dart';
import '../../services/canvas_segment_clipper.dart';
import '../../services/canvas_selection_region.dart';
import '../../models/drawing_guide.dart';
import '../../services/guide_geometry.dart';
import '../../services/guide_stroke_input.dart';
import '../../services/stroke_stabilizer.dart';
import 'active_stroke_overlay.dart';
import 'bitmap_tile_image_cache.dart';
import '../../models/brush_edit_canvas_input_settings.dart';
import 'brush_edit_canvas_view.dart';
import 'canvas_touch_contacts.dart';

part 'brush_edit/brush_edit_stroke.dart';
part 'brush_edit/brush_edit_fill.dart';
part 'brush_edit/brush_edit_pressure.dart';
part 'brush_edit/brush_edit_overlay.dart';
part 'brush_edit/brush_edit_settling.dart';
part 'brush_edit/brush_edit_hold.dart';
part 'brush_edit/brush_edit_cel_press.dart';
part 'brush_edit/brush_edit_press.dart';

/// The committed-surface tiles inside [bounds] (every stored tile when the
/// bounds are unknown): the set whose decodes gate the settling overlay
/// handoff, so a just-committed stroke never trades its overlay for stale
/// pre-stroke tile images.
@visibleForTesting
List<PlacedTile> settlingTilesForBounds({
  required BitmapSurface surface,
  required DirtyRegion? bounds,
}) {
  if (bounds == null) {
    return [
      for (final entry in surface.tiles.entries)
        (coord: entry.key, tile: entry.value),
    ];
  }
  final box = bounds.tileRange(tileSize: surface.tileSize);
  return [
    for (final entry in surface.tiles.entries)
      if (entry.key.x >= box.firstX &&
          entry.key.x <= box.lastX &&
          entry.key.y >= box.firstY &&
          entry.key.y <= box.lastY)
        (coord: entry.key, tile: entry.value),
  ];
}

/// The PRE-stroke tile (null = the coordinate was empty) for every
/// committed-grid coordinate that [bounds] touches, pinned on the overlay
/// model so settling frames stay pixel-identical to the live stroke (see
/// [ActiveStrokeOverlayModel.settleHoldTiles]).
///
/// ⚠️ Its one caller is the FILL commit. This doc used to say "captured at
/// pen-up", which stopped being true when promotion took the pin off the
/// stroke path, and the stale sentence made the missing pin look like a
/// deliberate design rather than something dropped. Pen-up settles by
/// keeping the OVERLAY up instead — its tile images are the stroke a
/// revision behind, which is a better stand-in than the pre-stroke tile
/// because it is not missing the stroke.
@visibleForTesting
Map<TileCoord, BitmapTile?> preStrokeHoldTiles({
  required BitmapSurface surface,
  required DirtyRegion? bounds,
}) {
  if (bounds == null) {
    return {...surface.tiles};
  }
  final tiles = surface.tiles;
  return {
    for (final coord in tileCoordsIn(
      bounds.tileRange(tileSize: surface.tileSize),
    ))
      coord: tiles[coord],
  };
}

class InteractiveBrushEditCanvasView extends StatefulWidget {
  /// The commitment distance (the engine's lock slop — one number keeps
  /// the engine's navigate-lock and this view's cancel window agreeing).
  ///
  /// 🚨★★★HOW FAR A TOUCH MUST TRAVEL TO BE ITS OWN GESTURE, and the tap
  /// layer asks it too now — 유저 2026-08-27: 「손가락이 동시에 착지하는게
  /// 불가능하니까 … 그런 비슷한 방식으로 **통일**하는게 근본통일같은데」.
  /// It sat on the private State, which is why the third surface that
  /// needed it could not have it; it is the same number for all of them,
  /// so it lives where it can be asked rather than copied.
  static const double kTouchStrokeCommitSlop = 18;

  InteractiveBrushEditCanvasView({
    super.key,
    required this.sessionState,
    required this.layerId,
    required this.frameId,
    required this.inputSettings,
    required this.onSourceStrokeCommitted,
    this.showTransparentBackground = true,
    this.onActiveStrokeChanged,
    this.onAltPick,
    this.onTemporaryToolHold,
    this.onTemporaryToolRelease,
    this.onInvokeAction,
    this.fillDabAt,
    this.selectionRegion,
    this.overlayModel,
    this.paintsContent = true,
    this.editable = true,
    this.onPressNeedsCel,
    CanvasViewport? viewport,
    CutGuides? guides,
  }) : viewport = viewport ?? CanvasViewport(),
       guides = guides ?? CutGuides.empty;

  /// Whether the cel under the playhead can be drawn on at all.
  ///
  /// False = the playhead stands on an EMPTY frame. The view stays mounted
  /// and simply stands down: it takes no pointers (so the shell's refusal
  /// notice sees the press, exactly as it did when this widget was not
  /// built) and paints nothing.
  ///
  /// ★ It is a FLAG rather than an absent widget because mounting is the
  /// expensive part. Swapping this whole subtree for a blank box whenever
  /// the playhead crossed "no cel ↔ cel" cost a full mount + unmount per
  /// flip step — measured at ~35-40% of the crossing's excess, on top of
  /// the panel remount #861 removed. The sibling rule is already written
  /// above [key]: a frame flip must reset this view IN PLACE, never
  /// rebuild it.
  final bool editable;

  /// 🚨I-10 — WHOEVER HEARS THE PRESS IS THE ONLY ONE WHO CAN DRAW IT.
  ///
  /// 유저 (F-61): 「그릴때 자동생성은 되는데 **선이 안그려지고있음**」, against
  /// what the feature was asked for: 「빈 칸에서 펜다운하면 블록이 자동생성되고
  /// **그대로 스트로크 그려지기시작**」.
  ///
  /// ⛔The block used to be made by a `Listener` ABOVE this view, and a
  /// widget that appears afterwards can never draw the press that made it:
  /// Flutter routes the rest of a gesture to the hit path captured at
  /// pointer-DOWN, so the newly built view gets no moves and no up. The
  /// block appeared and the line never started — exactly the report.
  ///
  /// ⇒ The press lands HERE even while [editable] is false, and this is what
  /// it asks then: 「there is nothing under me — make a cel if you can」.
  /// True means one was made, and this view begins the stroke at that same
  /// down position the moment it becomes editable.
  ///
  /// ⚠️Null on the surfaces that have nothing to make (the conte, the
  /// timesheet, the cut envelope): they pass nothing and stand down exactly
  /// as before.
  final bool Function()? onPressNeedsCel;

  /// The cut's drawing guides. Empty (the default) leaves the stroke path
  /// exactly as it was — the ink surfaces that reuse this view (conte,
  /// timesheet, cut envelope) are not the cut's drawing canvas and pass
  /// nothing.
  final CutGuides guides;

  final BrushEditSessionState sessionState;
  final LayerId layerId;
  final FrameId frameId;
  final BrushEditCanvasInputSettings inputSettings;
  final ValueChanged<BrushStrokeCommitData> onSourceStrokeCommitted;
  final bool showTransparentBackground;
  final ValueChanged<bool>? onActiveStrokeChanged;

  /// Alt+pointer-down picks a color instead of starting a stroke (P5's
  /// temporary eyedropper); null disables the shortcut.
  final ValueChanged<CanvasPoint>? onAltPick;

  /// PEN-7a mapped-hold session: a secondary-button press switched the
  /// tool temporarily — the shell mirrors it on the tool notifier so the
  /// cursor/panels follow, and restores (or keeps) on release.
  final void Function(CanvasTool tool)? onTemporaryToolHold;
  final void Function({required bool keep})? onTemporaryToolRelease;

  /// PEN-11: one-shot mapped actions (undo/redo) dispatch through the
  /// registry funnel — fired at a mapped press, or at a HOVER button
  /// press for pens that report it (the S-Pen hover palm-rejection
  /// window blocks touch, so the pen carries its own undo).
  final void Function(String actionId)? onInvokeAction;

  /// FILL mode (R22-A): non-null while the fill tool is active — a
  /// primary tap builds the flood's stamp dab here and the view runs it
  /// through the STROKE pipeline: the overlay shows the filled region
  /// the very next frame (native stamp blend into the live rasterizer),
  /// the commit rides [onSourceStrokeCommitted], and the overlay holds
  /// until the committed tiles decode (the settling contract) — no more
  /// tile-by-tile reveal on big fills.
  final BrushDab? Function(CanvasPoint point, int color, SymmetryShape? symmetry)?
  fillDabAt;

  /// R26 #18: the live selection region (canvas coordinates). Non-null
  /// confines the stroke to it — the region goes to the RASTERIZER, which
  /// masks the accumulated stroke's alpha inside the pre-blend kernel, so
  /// the tiles the user sees and the tiles pen-up promotes are already
  /// clipped. (It used to be a painter clipPath over the overlay; that
  /// showed the right thing but cost the whole-coordinate replacement
  /// path — a clipped overlay cannot own a coordinate — so every selected
  /// stroke fell back to a per-frame isolation layer.)
  final CanvasSelectionRegion? selectionRegion;

  /// The live-stroke overlay. HOST-OWNED when non-null, which is what lets
  /// the editing canvas draw the active layer inside its composite tree: a
  /// folder composites into one offscreen, so the layer being drawn on has to
  /// be paintable by the same painter that opened it. Null keeps
  /// the view's own model (standalone hosts, tests).
  final ActiveStrokeOverlayModel? overlayModel;

  /// Whether this view PAINTS. False leaves it input-only — the merged
  /// stack painter draws the surface + overlay in tree order instead.
  /// Input is untouched either way: the Listener is this widget's.
  final bool paintsContent;

  /// Zoom/pan applied to the canvas display and input mapping. Viewport
  /// GESTURES (middle-drag pan, wheel zoom) live on the panel's
  /// [CanvasViewportGestureLayer], not here — this view only draws.
  final CanvasViewport viewport;

  @override
  State<InteractiveBrushEditCanvasView> createState() =>
      _InteractiveBrushEditCanvasViewState();
}

class _InteractiveBrushEditCanvasViewState
    extends State<InteractiveBrushEditCanvasView> {
  // ── what a pointer means: its own object, in its own file ────────────
  //
  // A collaborator (canvas/brush_edit/brush_edit_press.dart, a part of
  // this library). The four Listener callbacks below are its entry
  // points; the State keeps only the fields its siblings also read.
  late final _BrushEditPress _press = _BrushEditPress(this);

  int? _activeDrawingPointer;

  // The press that makes its cel first (Round 6).
  late final _BrushEditCelPress _celPress = _BrushEditCelPress(this);

  /// PEN-12 #4: the touch stroke's commitment tracking — sub-slop, a
  /// simultaneous second finger still converts the pair to navigation;
  /// committed, extra fingers are ignored (the mid-line vanish fix).
  Offset? _touchStrokeDownPosition;
  bool _touchStrokeCommitted = false;

  var _nextSequence = 0;
  final List<BrushDab> _collectedDabs = <BrushDab>[];
  var _breakCurrentVisibleSegment = false;
  CanvasPoint? _previousRawCanvasPosition;
  BrushEditCanvasInputSettings? _activeStrokeInputSettings;

  /// Normalized pressure (0..1) of the latest pointer sample. Devices without
  /// pressure report a zero range and are treated as full pressure, so a
  /// mouse draws exactly as before.
  double _currentPressure = 1.0;

  /// How the pen leaned at the latest sample: azimuth in degrees and a 0..1
  /// altitude, or null when nothing measured one.
  /// ⚠️ONE FIELD, not two. Azimuth without altitude is a lean in a direction
  /// nothing reported, and `BrushDab` refuses that pair outright — so the
  /// reading is present or absent as a whole. Null is what a mouse and a
  /// finger report, and it is NOT the same as an upright pen (유저 2026-09-09,
  /// `brush-tilt-no-device-Q1` 답 1).
  ({double azimuthDegrees, double altitude})? _currentTilt;

  /// How fast the pen travelled into the latest sample, 0..1 against the
  /// user's reference speed. A pen that has just landed — and every stroke's
  /// first dab — rests at 0.0.
  double _currentSpeed = 0.0;

  // The held button (Round 6): a mapped button standing in for a tool.
  late final _BrushEditHold _hold = _BrushEditHold(this);

  /// The contact that started as an ALT pick (TS7), so its moves keep
  /// sampling.
  ///
  /// Placement dynamics (scatter/jitter/direction rotation) for the active
  /// stroke; created at pointer-down from the stroke's settings snapshot.
  BrushStrokeDynamics? _strokeDynamics;

  /// Per-stroke randomness for the dual-mask phase; each dab samples the
  /// dual texture at its own random offset (stored on the dab, so replay
  /// is deterministic).
  final math.Random _dualPhaseRandom = math.Random();

  /// Latest known stroke direction (visual CCW degrees); kept across
  /// stationary events so direction-following tips do not snap back.
  double? _lastDirectionDegrees;

  /// Last dab of the UNTRANSFORMED interpolation chain. Interpolation must
  /// anchor on the base chain — anchoring on scattered/jittered dabs would
  /// wander the spacing.
  BrushDab? _previousBaseDab;

  /// Ground-colour mixing state for the stroke in flight, or null when the
  /// brush paints its own colour flat. Holds the reservoir, so it must see
  /// the dabs in stroke order.
  BrushGroundColorMixer? _groundMixer;

  /// Reads the cel as it stood when the stroke began. A stroke cannot change
  /// what is under it mid-flight from the mixer's point of view: the live
  /// tiles are rasterized a pointer-move at a time, so sampling them would
  /// race the batch that produced them.
  BrushGroundColorSampler? _groundSampler;

  /// Pull-string stabilization for the active stroke (P7): created at
  /// pointer-down when the strength is non-zero (rope = screen px / zoom,
  /// frozen per stroke); pen positions run through it BEFORE clipping and
  /// interpolation, so every downstream route sees the smoothed chain.
  StrokeStabilizer? _stabilizer;

  /// Perspective ray lock for the active stroke: created at pointer-down
  /// when a perspective guide is snapping, and fed AFTER the stabilizer —
  /// smoothing a snapped line would bend the straightness back out of it.
  PerspectiveSnapSession? _snapSession;

  /// The acting symmetry's copy transforms, frozen at pointer-down so an
  /// axis edited mid-stroke cannot tear the stroke in half. One identity
  /// entry (or none) means no replication.
  List<GuideTransform> _symmetryTransforms = const [];

  /// The last RAW pen position (pre-stabilization) — pen-up catches the
  /// brush up to it with a straight segment through the normal pipeline.
  CanvasPoint? _lastPenPosition;

  /// Live overlay state. Pointer moves blend new dabs into [_liveRasterizer]
  /// (the exact commit-rasterizer math) and re-decode the touched overlay
  /// tiles; decode completions repaint the canvas painter directly through
  /// this model — no widget rebuild per move, and the pixels on screen are
  /// the pixels the commit will keep.
  ///
  /// OWNED here only when the host does not supply one. A host that draws
  /// the active layer inside its own composite tree owns it instead (see
  /// [InteractiveBrushEditCanvasView.overlayModel]) — the stroke path
  /// below is identical either way, it just writes into a model somebody
  /// else can also paint from.
  late final ActiveStrokeOverlayModel _ownedOverlayModel =
      ActiveStrokeOverlayModel();

  // ── the stroke overlay: its own object, in its own file ─────────────
  //
  // A collaborator (canvas/brush_edit/brush_edit_overlay.dart, a part of this library).
  // The State keeps the entry points its pointer handlers call.
  late final _BrushEditOverlay _overlay = _BrushEditOverlay(this);

  BrushLiveStrokeRasterizer? _liveRasterizer;

  /// Dabs collected since the last rasterized batch. Pointer samples arrive
  /// far above the display rate (1000Hz mice, 240Hz pens); rasterizing per
  /// EVENT multiplied the blend work for zero visible benefit, so moves only
  /// queue dabs and one frame callback blends the batch. Dab generation,
  /// order and blend math are unchanged — the batch is byte-identical to
  /// per-event blending, and pen-up flushes synchronously before commit.
  final List<BrushDab> _pendingOverlayDabs = <BrushDab>[];
  bool _overlayFlushScheduled = false;

  // After pointer-up the overlay stays visible ("settling") until the
  // committed tiles finish decoding, so the stroke never flashes away while
  // the display switches to the materialized bitmap.
  // Settling (Round 6): the decode window after a stroke lands.
  late final _BrushEditSettling _settlingState = _BrushEditSettling(this);

  @override
  void initState() {
    super.initState();
    BitmapTileImageCache.instance.addListener(_onTileImagesChanged);
    CanvasTouchContacts.addMultiTouchListener(_press.handleSharedMultiTouch);
  }

  @override
  void didUpdateWidget(covariant InteractiveBrushEditCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The view no longer REMOUNTS per cel (R13-2): the old frameId-keyed
    // remount tore down and re-inflated this whole subtree on every frame
    // flip, and that element + render-tree rebuild summed to a 40-80ms
    // UI-thread hitch — the constant flip lag. A cel identity change now
    // resets the per-stroke state in place; everything else (session
    // state, stale scope) flows through the ordinary rebuild.
    if (oldWidget.layerId != widget.layerId ||
        oldWidget.frameId != widget.frameId) {
      // R13-4: this runs inside the build/update phase. The stroke-end
      // callback reaches ancestor setState (the panel's _strokeActive) —
      // firing it synchronously here threw "setState during build" (the
      // mid-stroke flip red screen). Reset silently, notify post-frame.
      final hadActiveStroke = _activeDrawingPointer != null;
      _stroke.clearStrokeInputState();
      _overlay.resetOverlay();
      // clear() before dropping: the live tiles are native-backed (R21)
      // and return to the engine's free list through it.
      _liveRasterizer?.clear();
      _liveRasterizer = null;
      if (hadActiveStroke) {
        final notify = widget.onActiveStrokeChanged;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notify?.call(false);
        });
      }
    }
  }

  @override
  void dispose() {
    BitmapTileImageCache.instance.removeListener(_onTileImagesChanged);
    _settlingState._settlingFallbackTimer?.cancel();
    // Only OUR model — a host-owned one outlives this view (it survives
    // the layer switches that rebuild us).
    if (widget.overlayModel == null) {
      _ownedOverlayModel.dispose();
    } else {
      _overlay._overlayModel.reset();
    }
    _liveRasterizer?.clear(); // Native tiles back to the engine (R21).
    // R26 #5: a view disposed mid-touch never sees its pointer-up — its
    // contacts must leave the app-wide census or ink stays blocked.
    _press.releaseTouchContacts();
    CanvasTouchContacts.removeMultiTouchListener(_press.handleSharedMultiTouch);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ONE TREE SHAPE, editable or not. It used to return a bare
    // `SizedBox.expand()` while standing down, and that is what made I-10's
    // second half impossible: a listener that appears only after the cel
    // exists cannot be in the hit path of the press that created it. The
    // listener is here either way now — TRANSLUCENT while standing down, so
    // what is under this view in the panel's Stack keeps receiving exactly
    // as it did when nothing was built at all.
    //
    // ⛔Still nothing PAINTED while standing down: the cel the playhead has
    // LEFT must not be drawn (the session state still points at it), which
    // is what the flag was written for.
    final canvasSize =
        widget.sessionState.canvasState.currentSurface.canvasSize;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : canvasSize.width.toDouble();
        final viewportHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : canvasSize.height.toDouble();

        return SizedBox(
          width: viewportWidth,
          height: viewportHeight,
          child: Listener(
            key: const ValueKey<String>(
              'interactive-brush-edit-canvas-view-listener',
            ),
            behavior: widget.editable
                ? HitTestBehavior.opaque
                : HitTestBehavior.translucent,
            onPointerDown: _press.pointerDown,
            onPointerMove: _press.pointerMove,
            onPointerUp: _press.pointerUp,
            onPointerCancel: _press.pointerCancel,
            onPointerHover: _hold.handlePointerHover,
            // paintsContent false: the merged stack painter draws this
            // surface in TREE order (inside whatever folder buffer holds
            // it) — this view stays for input alone. The listener above is
            // untouched, so the stroke path is identical.
            child: widget.paintsContent && widget.editable
                ? ClipRect(
                    key: const ValueKey<String>(
                      'interactive-brush-edit-canvas-clip',
                    ),
                    // The viewport transform is applied inside the painter
                    // (not by a Transform widget) so the canvas rasterizes
                    // at final device resolution in one picture —
                    // pixel-stable at fractional zoom.
                    child: BrushEditCanvasView(
                      sessionState: widget.sessionState,
                      viewport: widget.viewport,
                      showTransparentBackground:
                          widget.showTransparentBackground,
                      overlayModel: _overlay._overlayModel,
                      staleScope: (widget.layerId, widget.frameId),
                    ),
                  )
                : const SizedBox.expand(),
          ),
        );
      },
    );
  }

  // ── the stroke: its own object, in its own file ─────────────────────
  //
  // A collaborator (canvas/brush_edit/brush_edit_stroke.dart, a part of this library).
  // The State keeps the entry points its pointer handlers call.
  late final _BrushEditStroke _stroke = _BrushEditStroke(this);

  /// Whether the pen-tail mapping is engaged (the pen is turned
  /// tail-down). Not a button hold: it spans strokes until the pen is
  /// turned back over.
  bool _penTailActive = false;

  /// EVERY tool works anywhere on the pasteboard (Flash-style — the
  /// stage rectangle is a crop at composite time, not an input
  /// boundary): strokes, eyedropper picks and fill taps alike.
  bool _isInsidePasteboard(CanvasPoint localPosition) {
    final canvasSize =
        widget.sessionState.canvasState.currentSurface.canvasSize;
    return canvasSize.containsPasteboardPoint(
      x: localPosition.x,
      y: localPosition.y,
    );
  }

  CanvasPoint _canvasPositionFromLocal(Offset localPosition) {
    return widget.viewport.viewportToCanvas(
      ViewportPoint(x: localPosition.dx, y: localPosition.dy),
    );
  }

  /// Builds a dab carrying the base tool size/opacity and the current input
  /// pressure. Pressure scaling is applied after interpolation (see
  /// [_pressure.withPressureDynamics]) so each inserted dab scales by its own
  /// interpolated pressure rather than the segment endpoint's.
  BrushDab _dabFromPosition(
    CanvasPoint localPosition, {
    required int sequence,
  }) {
    final settings = _activeStrokeInputSettings ?? widget.inputSettings;
    final dualMask = settings.dualMask;
    return BrushDab(
      center: localPosition,
      color: settings.color,
      size: settings.size,
      // F-12: a dab carries only its OWN variation (the pressure curve and
      // the jitter multiply this). The tool's opacity is the accumulated
      // stroke's ceiling and rides `BrushDabSequence.opacity` instead —
      // per dab it is not a ceiling at all, since dabs pile up source-over
      // and any factor below 1 still converges on opaque.
      opacity: 1,
      flow: settings.flow,
      hardness: settings.hardness,
      pressure: _currentPressure,
      sequence: sequence,
      tiltAzimuthDegrees: _currentTilt?.azimuthDegrees ?? 0.0,
      tiltAltitude: _currentTilt?.altitude,
      speed: _currentSpeed,
      roundness: settings.roundness,
      angleDegrees: settings.angleDegrees,
      tipMask: settings.tipMask,
      dualMask: dualMask,
      dualMaskScale: settings.dualMaskScale,
      dualOffsetU: dualMask == null ? 0.0 : _dualPhaseRandom.nextDouble(),
      dualOffsetV: dualMask == null ? 0.0 : _dualPhaseRandom.nextDouble(),
      dualDensity: settings.dualDensity,
      textureMask: settings.textureMask,
      textureScale: settings.textureScale,
      textureDensity: settings.textureDensity,
      // 🚨THE EDGE STEP AND THE DUAL DENSITY WERE NOT HERE, and the panel
      // has been writing both for a while: 아웃 오브 the brush's settings,
      // into the shape, and no further. The only producer that ever carried
      // `antiAlias` onto a dab was `BrushDab.fromInputSample` — which
      // nothing in the app called — so the pin that watched it was green
      // while the canvas ignored the setting entirely.
      antiAlias: settings.antiAlias,
      erase: settings.erase,
    );
  }

  /// Scales freshly interpolated dabs by their pressure per the active
  /// stroke's pressure curves (BB-3). Returns the input unchanged when no
  /// curve is set, so the common no-pressure path stays allocation-free.
  /// Resolves the colour a mixing brush deposits, after the dynamics have
  /// settled each dab's final position — scatter moves dabs, and the ground
  /// has to be read where the dab actually lands.
  List<BrushDab> _withGroundMixing(List<BrushDab> dabs) {
    final mixer = _groundMixer;
    final sampler = _groundSampler;
    if (mixer == null || sampler == null) {
      return dabs;
    }
    return mixer.apply(dabs, sample: sampler);
  }

  // ── pressure and the stamp: their own object ────────────────────────
  //
  // A collaborator (canvas/brush_edit/brush_edit_pressure.dart, a part of this library).
  // The State keeps the entry points its pointer handlers call.
  late final _BrushEditPressure _pressure = _BrushEditPressure(this);

  final math.Random _spacingRandom = math.Random();

  /// Whether [buttons] is a drawing contact.
  ///
  void _onTileImagesChanged() {
    // BEFORE the settle gate: a stand-in outlives the window that made
    // it, so once a new stroke is live this is the only thing that lets
    // it go.
    _settlingState.releaseSettledStandIns();
    if (!_settlingState._settling || !mounted) {
      return;
    }
    final settling = _settlingState.settlingTiles();
    if (BitmapTileImageCache.instance.allDecoded([
      for (final placed in settling) placed.tile,
    ])) {
      _overlay.resetOverlay();
    } else {
      // Not done yet — start the next decode chunk off this notification
      // (the 50ms timer stays as the belt-and-braces fallback).
      _settlingState.requestSettlingDecodes();
    }
  }

  /// Creates or recycles the live stroke rasterizer for the current canvas.
  void _prepareLiveRasterizer() {
    final surface = widget.sessionState.canvasState.currentSurface;
    final canvasSize = surface.canvasSize;
    final existing = _liveRasterizer;
    // The stroke grid IS the cel grid (the promotion round's premise: a
    // result tile stands in for the committed tile at its coordinate).
    if (existing == null ||
        existing.canvasSize != canvasSize ||
        existing.tileSize != surface.tileSize) {
      existing?.clear(); // Native tiles return to the engine (R21).
      _liveRasterizer = BrushLiveStrokeRasterizer(
        canvasSize: canvasSize,
        tileSize: surface.tileSize,
      );
    } else {
      existing.clear();
    }
    // R26 #18: the selection reaches the KERNEL through the rasterizer.
    // Captured once per stroke — it cannot change mid-stroke (the
    // selection layer is not mounted while a painting tool is active).
    _liveRasterizer!.selectionRegion = widget.selectionRegion;
    // F-12: and so does the opacity ceiling, by the same route and with
    // the same "captured once per stroke" rule — the dabs carry only their
    // own variation now, so this is the only place the tool's opacity
    // enters the live pixels.
    _liveRasterizer!.strokeOpacity =
        (_activeStrokeInputSettings ?? widget.inputSettings).opacity;
  }

  /// Rasterizes [newDabs] into the live buffer (exact commit math) and
  /// re-decodes the touched overlay tiles.
  ///
  /// The overlay model snapshots and decodes each touched tile through the
  /// same premultiply + `decodeImageFromPixels` pipeline as the committed
  /// tiles, so the on-screen stroke rasterizes exactly like it will after
  /// commit; decode completions repaint the canvas painter directly.
  BrushDab? _pendingFillCommitDab;

  /// The touch pointer whose lift will run a fill, and where it landed.
  ///
  /// Both cleared together — see the second-finger branch, which is where a
  /// tap stops being this fill's gesture.
  int? _fillTapPointer;
  CanvasPoint? _fillTapSeed;

  // ── the fill: its own object, in its own file ───────────────────────
  //
  // A collaborator (canvas/brush_edit/brush_edit_fill.dart, a part of this library).
  // The State keeps the entry points its pointer handlers call.
  late final _BrushEditFill _fill = _BrushEditFill(this);

  int _fillOverlayToken = 0;

}
