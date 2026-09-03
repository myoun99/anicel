import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/floor_math.dart';
import '../../core/rgba_premultiply.dart';
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
import '../../services/brush_live_stroke_rasterizer.dart';
import '../../services/brush_stroke_dynamics.dart';
import '../../services/brush_tip_stamp_cache.dart';
import '../../services/brush_pressure_dynamics.dart';
import '../../services/brush_stroke_blend.dart'
    show applySelectionMaskToStrokeAlpha;
import '../../services/brush_stroke_commit_data.dart';
import '../../native/qa_native_engine.dart';
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

/// The committed-surface tiles inside [bounds] (every stored tile when the
/// bounds are unknown): the set whose decodes gate the settling overlay
/// handoff, so a just-committed stroke never trades its overlay for stale
/// pre-stroke tile images.
@visibleForTesting
List<BitmapTile> settlingTilesForBounds({
  required BitmapSurface surface,
  required DirtyRegion? bounds,
}) {
  if (bounds == null) {
    return surface.tiles.values.toList();
  }
  final tileSize = surface.tileSize;
  // floorDiv: stroke bounds reach negative (pasteboard) space.
  final minX = floorDiv(bounds.left, tileSize);
  final maxX = floorDiv(bounds.rightExclusive - 1, tileSize);
  final minY = floorDiv(bounds.top, tileSize);
  final maxY = floorDiv(bounds.bottomExclusive - 1, tileSize);
  return [
    for (final tile in surface.tiles.values)
      if (tile.coord.x >= minX &&
          tile.coord.x <= maxX &&
          tile.coord.y >= minY &&
          tile.coord.y <= maxY)
        tile,
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
    return {for (final tile in surface.tiles.values) tile.coord: tile};
  }
  final tileSize = surface.tileSize;
  // floorDiv: stroke bounds reach negative (pasteboard) space.
  final minX = floorDiv(bounds.left, tileSize);
  final maxX = floorDiv(bounds.rightExclusive - 1, tileSize);
  final minY = floorDiv(bounds.top, tileSize);
  final maxY = floorDiv(bounds.bottomExclusive - 1, tileSize);
  final tiles = surface.tiles;
  return {
    for (var y = minY; y <= maxY; y += 1)
      for (var x = minX; x <= maxX; x += 1)
        TileCoord(x: x, y: y): tiles[TileCoord(x: x, y: y)],
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
  int? _activeDrawingPointer;

  // The press that makes its cel first (Round 6).
  late final _BrushEditCelPress _celPress = _BrushEditCelPress(this);

  /// PEN-12 #4: the touch stroke's commitment tracking — sub-slop, a
  /// simultaneous second finger still converts the pair to navigation;
  /// committed, extra fingers are ignored (the mid-line vanish fix).
  Offset? _touchStrokeDownPosition;
  bool _touchStrokeCommitted = false;

  /// Live touch contacts. A second finger switches the interaction to
  /// viewport navigation (handled by the panel's gesture layer): the
  /// in-progress stroke is cancelled without committing, and no new stroke
  /// starts until every finger lifts — a quick pinch never leaves marks.
  final Set<int> _activeTouchPointers = <int>{};
  bool _multiTouchNavigation = false;
  var _nextSequence = 0;
  final List<BrushDab> _collectedDabs = <BrushDab>[];
  var _breakCurrentVisibleSegment = false;
  CanvasPoint? _previousRawCanvasPosition;
  BrushEditCanvasInputSettings? _activeStrokeInputSettings;

  /// Normalized pressure (0..1) of the latest pointer sample. Devices without
  /// pressure report a zero range and are treated as full pressure, so a
  /// mouse draws exactly as before.
  double _currentPressure = 1.0;

  // The held button (Round 6): a mapped button standing in for a tool.
  late final _BrushEditHold _hold = _BrushEditHold(this);

  /// The contact that started as an ALT pick (TS7), so its moves keep
  /// sampling.
  ///
  /// 유저 확정 — one law for every dropper: 「클릭중이면 색 바뀌도록 …
  /// 같은법으로. 드래그중 계속샘플」. The mapped hold above has always done
  /// this ('누르는 동안 해당 색을 뽑는다', PEN-7a) and the eyedropper TOOL now
  /// does it on the tap layer; Alt was the third door, and it was the one
  /// still picking once per press.
  int? _altPickPointer;

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
    CanvasTouchContacts.addMultiTouchListener(_handleSharedMultiTouch);
  }

  /// R26 #5: a second finger landed SOMEWHERE on the ink surfaces — maybe
  /// on a sibling view, whose pointer this view will never see. A live
  /// sub-slop touch stroke here is really the first half of a pinch, so
  /// it stands down exactly as it would for a local second contact.
  void _handleSharedMultiTouch() {
    final drawingPointer = _activeDrawingPointer;
    if (drawingPointer == null ||
        !_activeTouchPointers.contains(drawingPointer)) {
      return; // No touch stroke here (a pen stroke keeps drawing).
    }
    if (_touchStrokeCommitted) {
      return; // A committed line survives extra fingers (PEN-12 #4).
    }
    _multiTouchNavigation = true;
    _stroke.endStrokeInput();
    _overlay.resetOverlay();
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
    CanvasTouchContacts.removeAll(_activeTouchPointers);
    CanvasTouchContacts.removeMultiTouchListener(_handleSharedMultiTouch);
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
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerUp,
            onPointerCancel: _handlePointerCancel,
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

  void _handlePointerDown(PointerDownEvent event) {
    // (No deferred stroke commit to land first: pen-up commits inside its
    // own event now — R25-④'s one-frame deferral existed to hide a
    // synchronous re-materialize that the promotion round deleted.)
    if (event.kind == PointerDeviceKind.touch) {
      // PEN-12 #4: a finger draws exactly when the ONE-FINGER touch slot
      // says draw (the old control/draw mode collapsed into the slot);
      // otherwise the panel's gesture layer owns every touch.
      if (!AppInput.touchDraws) {
        return;
      }
      _activeTouchPointers.add(event.pointer);
      CanvasTouchContacts.add(event.pointer);
      // R26 #5: the census is APP-WIDE — the timesheet mounts one ink
      // view per sheet window, so the second finger often lands on a
      // SIBLING view. Counting locally let both of them draw.
      if (CanvasTouchContacts.count >= 2) {
        final drawingPointer = _activeDrawingPointer;
        final touchStroke =
            drawingPointer != null &&
            _activeTouchPointers.contains(drawingPointer);
        // PEN-12 #4: a COMMITTED stroke survives extra fingers — palm
        // rests and habitual pinches must never vanish a live line. The
        // newcomer is simply ignored (no navigation, no modifier).
        if (touchStroke && _touchStrokeCommitted) {
          return;
        }
        _multiTouchNavigation = true;
        // A waiting FILL tap goes with them, and for the same reason: the
        // first finger turned out to be the start of a pinch. Nothing was
        // drawn and nothing entered history, so this is a forget rather
        // than an undo — which is the whole point of making the fill wait.
        _fill.forgetFillTap();
        // Discard only a SUB-SLOP touch stroke — the first finger turned
        // out to be the start of a pinch, not a stroke (both fingers
        // landed together). A stylus/mouse stroke keeps drawing: extra
        // touch contacts alongside it are palm rests.
        if (touchStroke) {
          _stroke.endStrokeInput();
          _overlay.resetOverlay();
        }
        return;
      }
    }

    if (!widget.editable) {
      _celPress.pressAsksForACel(event);
      return;
    }

    // PEN-7a: the CANVAS mapping for standard secondary inputs. Pen
    // side/barrel buttons, the S-Pen button and the mouse right button
    // all arrive as the RIGHT-CLICK bit; the pen upper button and the
    // wheel click as the MIDDLE bit. On canvas the user assigns what
    // they do (Input Settings ▸ Canvas); everywhere else the OS meaning
    // of the input rules untouched. The hold temporarily switches the
    // TOOL (the shared tool-switch path — cursor/panels follow free);
    // release springs back or keeps it per the mapping.
    // The pen TAIL settles first: it is a state rather than a press, and
    // a live tail hold suppresses the button rows below. Its erase has to
    // reach this stroke's settings snapshot directly — the tool switch it
    // requests is asynchronous, and the stroke starts now.
    _overlay.syncPenTailMapping();
    var mappedErase = _overlay.penTailErases;
    final mapping = _hold.mappedPointerActionFor(event);
    if (mapping != null) {
      if (_multiTouchNavigation ||
          _activeDrawingPointer != null ||
          _hold._mappedHoldPointer != null) {
        return;
      }
      switch (mapping.action) {
        case CanvasPointerAction.none:
        // Pan belongs to the panel's viewport gesture layer — this view
        // only stands down so no stroke competes with it.
        case CanvasPointerAction.pan:
          return;
        case CanvasPointerAction.undo:
          // Skip when the button press already fired during hover (the
          // hover edge below) and the tip then touched with it held.
          if (!_hold.mappedButtonHeldSinceHover(event)) {
            widget.onInvokeAction?.call('edit-undo');
          }
          return;
        case CanvasPointerAction.redo:
          if (!_hold.mappedButtonHeldSinceHover(event)) {
            widget.onInvokeAction?.call('edit-redo');
          }
          return;
        case CanvasPointerAction.eyedropper:
          _hold._mappedHoldPointer = event.pointer;
          _hold._mappedHoldRelease = mapping.release;
          _hold._mappedHoldIsEyedropper = true;
          // The contact takes over a hover-engaged hold (R26 #19/#20):
          // one hold session, one release.
          _hold._hoverToolHoldActive = false;
          _hold._hoverToolHoldRelease = null;
          _hold._hoverToolHoldButton = 0;
          widget.onTemporaryToolHold?.call(CanvasTool.eyedropper);
          final pickPosition = _canvasPositionFromLocal(event.localPosition);
          // The eyedropper picks anywhere on the pasteboard, like Flash
          // (off-canvas artwork is real artwork).
          if (_isInsidePasteboard(pickPosition)) {
            widget.onAltPick?.call(pickPosition);
          }
          return;
        case CanvasPointerAction.eraser:
          mappedErase = true;
          _hold._mappedHoldPointer = event.pointer;
          _hold._mappedHoldRelease = mapping.release;
          _hold._mappedHoldIsEyedropper = false;
          widget.onTemporaryToolHold?.call(CanvasTool.eraser);
        // Falls through into the normal stroke start below with the
        // erase-substituted settings snapshot.
      }
    }

    if (!mappedErase &&
        (_multiTouchNavigation ||
            _activeDrawingPointer != null ||
            !_isPrimaryButton(_hold.effectiveButtons(event)))) {
      return;
    }

    final canvasPosition = _canvasPositionFromLocal(event.localPosition);
    // The pasteboard is EVERY tool's input boundary (user feedback +
    // Flash parity): strokes, the eyedropper and fill taps all work on
    // off-canvas artwork; only the pasteboard wall stops them.
    final startsInsidePasteboard = _isInsidePasteboard(canvasPosition);

    // Alt+click = temporary eyedropper (P5): pick, never stroke.
    final onAltPick = widget.onAltPick;
    if (onAltPick != null && HardwareKeyboard.instance.isAltPressed) {
      // TS7: remembered, so the drag that follows keeps sampling.
      _altPickPointer = event.pointer;
      if (startsInsidePasteboard) {
        onAltPick(canvasPosition);
      }
      return;
    }

    // FILL tap (R22-A / R23): the flood's stamp becomes ONE overlay
    // image at the commit's exact placement, and the commit itself
    // DEFERS past the tap frame — the finished fill shows while the
    // heavy commit (~0.5s at 8K) runs behind a complete-looking
    // picture; settling then holds the overlay until the committed
    // tiles decode. (The R22-A live-raster blend re-snapshotted and
    // re-decoded thousands of 128px overlay tiles — the 8K
    // settle-frame stall.)
    final fillDabAt = widget.fillDabAt;
    if (fillDabAt != null) {
      // Off-canvas fill taps flow through: the default (stage-bounded)
      // raster answers null for them, the extended raster fills — the
      // fill's own boundary options decide, not the pointer.
      // The busy half of this used to be here too; it now lives in
      // [_runFillTap], which is the only place that can be sure.
      if (!startsInsidePasteboard) {
        return;
      }
      // The seed and the axis come from the same pair the STROKE path uses
      // — this view's own position and its own guides, both already in the
      // space the pointer is in. Reading the symmetry from the project
      // instead would put the mirror where the pen is not under a pose.
      // 🚨★★★A TOUCH FILL RESOLVES ON THE LIFT, NOT ON THE TOUCH.
      //
      // 유저 2026-08-27, iPhone: 「필 툴인 채로 … undo가 작동안함. 브러시툴
      // 에서는 잘 작동함. 1핑거 플립모드로 전환하면 또 잘 작동함」 — a
      // two-finger undo tap put its FIRST finger down, the fill committed a
      // history entry nobody asked for, and the undo that followed spent
      // itself on that instead of on the user's work.
      //
      // ★The law is already here, thirty lines up: when a second finger
      // arrives, a touch stroke that has not passed slop is DISCARDED —
      // "the first finger turned out to be the start of a pinch, not a
      // stroke". That branch is exactly why the brush tool works and this
      // one did not: a zero-length stroke has nothing to commit, while the
      // fill had already flooded, revealed and queued its commit.
      //
      // ⛔The fix cannot be 「commit, then undo it when the second finger
      // shows」 — [[no-optimistic-commit-then-revert]], 유저: 「한 프레임
      // 보이는 건 무조건 걸린다」. So the REVEAL waits with the commit; a
      // tap that turns out to be a pinch never draws anything at all.
      //
      // Pen and mouse are untouched: they cannot be half of a pinch, and
      // the instant reveal is the whole point of R22-A.
      if (event.kind == PointerDeviceKind.touch) {
        _fillTapPointer = event.pointer;
        _fillTapSeed = canvasPosition;
        return;
      }
      _fill.runFillTap(canvasPosition);
      return;
    }

    _activeDrawingPointer = event.pointer;
    // PEN-12 #4: a TOUCH stroke starts UNCOMMITTED — until it crosses the
    // touch slop a simultaneous second finger may still turn the pair
    // into navigation (cancelling only an invisible dot); once committed
    // the stroke owns the screen and extra fingers are ignored.
    _touchStrokeDownPosition = event.kind == PointerDeviceKind.touch
        ? event.localPosition
        : null;
    _touchStrokeCommitted = false;
    // The stroke's settings snapshot — every downstream dab reads it, so
    // the mapped-eraser substitution here flips the WHOLE stroke. The
    // substitution forces the BLEND to erase too (R27 #4 in passing): the
    // eraser tool locks its mode, but this path kept the brush's — a
    // mapped-erase press with a separable brush blend would have taken
    // the commit's blend branch and PAINTED instead of erasing.
    final strokeSettings = mappedErase
        ? widget.inputSettings.copyWith(
            erase: true,
            blendMode: BrushBlendMode.erase,
          )
        : widget.inputSettings;
    _activeStrokeInputSettings = strokeSettings;
    _currentPressure = _pressure.normalizedPressure(event);
    widget.onActiveStrokeChanged?.call(true);
    _nextSequence = 0;
    _breakCurrentVisibleSegment = !startsInsidePasteboard;
    _previousRawCanvasPosition = canvasPosition;
    _lastPenPosition = canvasPosition;
    final stabilizerStrength = strokeSettings.stabilizerStrength;
    _stabilizer = stabilizerStrength > 0
        ? StrokeStabilizer(
            ropeLength: stabilizerStrength / widget.viewport.zoom,
            start: canvasPosition,
          )
        : null;
    // Guides are read ONCE per stroke. Both are frozen here rather than
    // consulted per sample so an edit landing mid-stroke cannot bend the
    // line that is already down.
    _snapSession = PerspectiveSnapSession.maybeStart(
      guides: widget.guides,
      start: canvasPosition,
      zoom: widget.viewport.zoom,
    );
    final symmetry = widget.guides.actingSymmetry;
    _symmetryTransforms = symmetry == null
        ? const []
        : symmetryTransforms(symmetry);
    _strokeDynamics = BrushStrokeDynamics(settings: strokeSettings);
    _lastDirectionDegrees = null;
    _previousBaseDab = null;
    _groundMixer = strokeSettings.shape.mixesGroundColor
        ? BrushGroundColorMixer(shape: strokeSettings.shape)
        : null;
    _overlay.beginStrokeOverlay();
    // Overlay stroke configuration AFTER the reset — reset() clears
    // preBlendBase, so setting it earlier silently disabled the whole
    // pre-blend pipeline for real pointer strokes (the R27 #4 ordering
    // bug: every parity test staged the model manually and never caught
    // it). The overlay must display in the stroke's blend mode from the
    // first dab.
    final strokeSurface = widget.sessionState.canvasState.currentSurface;
    _groundSampler = _groundMixer == null
        ? null
        : bitmapSurfaceGroundSampler(strokeSurface);
    _overlay._overlayModel.configureTileSize(strokeSurface.tileSize);
    _overlay._overlayModel.erase = strokeSettings.erase;
    _overlay._overlayModel.blendMode = strokeSettings.blendMode;
    // R27 #4: EVERY stroke pre-blends its live tiles with the commit's
    // own kernels against the cel as it stands (user rule 07-23: ONE
    // display pipeline for all modes — color included). The GPU never
    // computes a pixel of the stroke composite, so pen-up cannot move a
    // byte in any mode. Revert switch if stroke feel regresses on
    // device: gate this on `blendMode != color` to give plain strokes
    // their classic stroke-only GPU-srcOver overlay back.
    _overlay._overlayModel.preBlendBase = strokeSurface;
    _collectedDabs.clear();
    _prepareLiveRasterizer();
    if (!startsInsidePasteboard) {
      return;
    }
    final initialDabs = _pressure.withPressureDynamics(
      const BrushDabInterpolator().interpolate(
        previous: null,
        nextRaw: _dabFromPosition(canvasPosition, sequence: _nextSequence),
        firstSequence: _nextSequence,
        spacingRatio: _stroke.activeStrokeSpacing,
      ),
    );
    if (initialDabs.isNotEmpty) {
      _previousBaseDab = initialDabs.last;
    }
    // R20-B: dabs resolve through the tip-stamp cache HERE, at generation
    // — the overlay, the commit, undo replay and the .anicel all see the
    // same resolved (quantized, prerotated-mask) dabs.
    //
    // ⚠️ Symmetry replicates HERE TOO. This is the stroke's FIRST dab, laid
    // at pointer-down rather than through [_advanceStrokeTo], and it is a
    // separate emission site — replicating only the move path left every
    // symmetric stroke's copies one dab short at the start, a notch right
    // where the pen landed.
    final emitted = BrushTipStampCache.instance.resolveDabs(
      replicateDabs(
        _withGroundMixing(
          _strokeDynamics!.apply(
            initialDabs,
            firstSequence: _nextSequence,
            directionDegrees: null,
          ),
        ),
        _symmetryTransforms,
        firstSequence: _nextSequence,
      ),
    );
    _collectedDabs.addAll(emitted);
    _overlay.queueOverlayDabs(emitted);
    _nextSequence += emitted.length;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _celPress.resumePressThatMadeTheCel(event.pointer);
    if (!widget.editable) {
      return; // Standing down: inert, exactly as when nothing was built.
    }
    // R27 #17: a mapped button can also rise DURING contact — some pen
    // drivers report the barrel bit a moment after the tip lands rather
    // than on the down event, and the hover edge above never sees it
    // then. Only picked up while nothing is drawing yet, so a live
    // stroke is never hijacked mid-line.
    _hold.handleMappedButtonRiseDuringContact(event);
    // A held eyedropper mapping picks LIVE along the whole drag (PEN-7a:
    // '누르는 동안 해당 색을 뽑는다').
    if (event.pointer == _hold._mappedHoldPointer && _hold._mappedHoldIsEyedropper) {
      final pickPosition = _canvasPositionFromLocal(event.localPosition);
      if (_isInsidePasteboard(pickPosition)) {
        widget.onAltPick?.call(pickPosition);
      }
      return;
    }
    // TS7: the ALT pick does the same. Alt is re-read rather than assumed —
    // letting go of the key mid-drag ends the sampling, which is the same
    // moment the crosshair goes away.
    if (event.pointer == _altPickPointer) {
      if (!HardwareKeyboard.instance.isAltPressed) {
        return;
      }
      final pickPosition = _canvasPositionFromLocal(event.localPosition);
      if (_isInsidePasteboard(pickPosition)) {
        widget.onAltPick?.call(pickPosition);
      }
      return;
    }
    if (event.pointer != _activeDrawingPointer) {
      return;
    }
    final touchStrokeDown = _touchStrokeDownPosition;
    if (!_touchStrokeCommitted &&
        touchStrokeDown != null &&
        (event.localPosition - touchStrokeDown).distance >=
            InteractiveBrushEditCanvasView.kTouchStrokeCommitSlop) {
      _touchStrokeCommitted = true;
    }

    _currentPressure = _pressure.normalizedPressure(event);
    final penPosition = _canvasPositionFromLocal(event.localPosition);
    _lastPenPosition = penPosition;
    // The stabilizer smooths BEFORE clipping/interpolation, so every
    // downstream consumer (overlay, commit, replay) sees one chain — the
    // three-route parity holds by construction (P7).
    _stroke.advanceStrokeThroughGuides(
      _stabilizer?.follow(penPosition) ?? penPosition,
    );
  }

  // ── the stroke: its own object, in its own file ─────────────────────
  //
  // A collaborator (canvas/brush_edit/brush_edit_stroke.dart, a part of this library).
  // The State keeps the entry points its pointer handlers call.
  late final _BrushEditStroke _stroke = _BrushEditStroke(this);

  void _handlePointerUp(PointerUpEvent event) {
    // A TAP on an empty cel is a dot, so the press still begins here — and
    // then this same event ends it: one dab, one undo entry.
    _celPress.resumePressThatMadeTheCel(event.pointer);
    if (_celPress._pendingCelPress?.pointer == event.pointer) {
      _celPress._pendingCelPress = null; // Never resumed; nothing is left to draw.
    }
    if (!widget.editable) {
      return;
    }
    _hold._lastContactButtons.remove(event.pointer);
    _forgetTouchPointer(event.pointer);
    _hold.releaseMappedHold(event.pointer);
    if (event.pointer == _altPickPointer) {
      _altPickPointer = null;
    }
    // The lone finger lifted with nobody having joined it: the tap was this
    // fill's after all. ⛔BEFORE the drawing-pointer gate below — a fill tap
    // never becomes the drawing pointer, so that gate would drop it.
    final fillSeed = _fillTapSeed;
    if (event.pointer == _fillTapPointer && fillSeed != null) {
      _fill.runFillTap(fillSeed);
      return;
    }
    if (event.pointer != _activeDrawingPointer) {
      return;
    }

    // Stabilizer catch-up (P7): the brush trails the pen by up to a rope
    // length — pen-up closes the gap with one straight segment through
    // the normal pipeline, so line ends land where the pen lifted.
    final lastPen = _lastPenPosition;
    if (_stabilizer != null && lastPen != null) {
      _stroke.advanceStrokeThroughGuides(lastPen);
    }
    // A stroke can lift before it travelled far enough to name a ray; the
    // snap settles on the best guess it has rather than swallowing a short
    // flick. Runs AFTER the catch-up so the extra travel counts towards the
    // decision.
    final session = _snapSession;
    if (session != null) {
      for (final snapped in session.finish()) {
        _stroke.advanceStrokeTo(snapped);
      }
    }

    final hadDabs = _collectedDabs.isNotEmpty;
    if (hadDabs) {
      // The commit reads the rasterizer's tiles — blend any dabs still
      // waiting on the per-frame flush first.
      _overlay.flushPendingOverlayDabs();
      _stroke.commitStroke();
    }

    _stroke.endStrokeInput();
    if (!hadDabs) {
      _overlay.resetOverlay();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_celPress._pendingCelPress?.pointer == event.pointer) {
      _celPress._pendingCelPress = null;
    }
    if (!widget.editable) {
      return;
    }
    _hold._lastContactButtons.remove(event.pointer);
    if (event.pointer == _fillTapPointer) {
      _fill.forgetFillTap();
    }
    _forgetTouchPointer(event.pointer);
    _hold.releaseMappedHold(event.pointer);
    if (event.pointer == _altPickPointer) {
      _altPickPointer = null;
    }
    if (event.pointer != _activeDrawingPointer) {
      return;
    }

    _stroke.endStrokeInput();
    _overlay.resetOverlay();
  }

  void _forgetTouchPointer(int pointer) {
    _activeTouchPointers.remove(pointer);
    CanvasTouchContacts.remove(pointer);
    if (_activeTouchPointers.isEmpty) {
      _multiTouchNavigation = false;
    }
  }

  /// The mapping a set of non-primary [bits] drives: the wheel click owns
  /// the tertiary bit, and everything else reads as the secondary — the
  /// barrel button, whichever bit the driver puts it on.
  CanvasPointerMapping? _mappingForButtons(int bits) {
    // A live tail hold owns the tool: the two mappings share one hold
    // slot, and whichever engaged first keeps it. Letting a barrel press
    // take the tool mid-flip would leave the tail with nothing to spring
    // back to when the pen is finally turned upright.
    if (bits == 0 || _penTailActive) {
      return null;
    }
    final settings = AppInput.settings.value;
    if ((bits & kTertiaryButton) != 0) {
      return settings.canvasWheelClick;
    }
    return settings.canvasRightClick;
  }

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
      tipShape: settings.tipShape,
      pressure: _currentPressure,
      sequence: sequence,
      roundness: settings.roundness,
      angleDegrees: settings.angleDegrees,
      tipMask: settings.tipMask,
      dualMask: dualMask,
      dualMaskScale: settings.dualMaskScale,
      dualOffsetU: dualMask == null ? 0.0 : _dualPhaseRandom.nextDouble(),
      dualOffsetV: dualMask == null ? 0.0 : _dualPhaseRandom.nextDouble(),
      textureMask: settings.textureMask,
      textureScale: settings.textureScale,
      textureDensity: settings.textureDensity,
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
  /// R28: a MASK test, not equality. A barrel button held while the tip
  /// touches down reports `primary | barrel`, and the old `== primary`
  /// test read that as "not drawing" — so on a driver that does ride the
  /// barrel bit into contact, the pen went dead instead of picking. The
  /// mapped-press path runs first and claims those pointers, so anything
  /// still reaching here with the primary bit down is a real stroke.
  bool _isPrimaryButton(int buttons) => (buttons & kPrimaryButton) != 0;

  void _onTileImagesChanged() {
    // BEFORE the settle gate: a stand-in outlives the window that made
    // it, so once a new stroke is live this is the only thing that lets
    // it go.
    _settlingState.releaseSettledStandIns();
    if (!_settlingState._settling || !mounted) {
      return;
    }
    if (BitmapTileImageCache.instance.allDecoded(_settlingState.settlingTiles())) {
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
