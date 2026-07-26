import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/floor_math.dart';
import '../../models/bitmap_surface.dart';
import '../../services/input/pen_sidecars.dart';
import '../brush/brush_tool_state.dart' show CanvasTool;
import '../input/app_input_settings.dart';
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
import '../../services/stroke_stabilizer.dart';
import 'active_stroke_overlay.dart';
import 'bitmap_tile_image_cache.dart';
import 'brush_edit_canvas_input_settings.dart';
import 'brush_edit_canvas_view.dart';
import 'canvas_touch_contacts.dart';

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
/// committed-grid coordinate that [bounds] touches; captured at pen-up
/// while the session surface is still pre-commit, and pinned on the
/// overlay model so settling frames stay pixel-identical to the live
/// stroke (see [ActiveStrokeOverlayModel.settleHoldTiles]).
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
  InteractiveBrushEditCanvasView({
    super.key,
    required this.sessionState,
    required this.layerId,
    required this.frameId,
    required this.inputSettings,
    required this.onSourceStrokeCommitted,
    this.dabInterpolator = const BrushDabInterpolator(),
    this.segmentClipper = const CanvasSegmentClipper(),
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
    CanvasViewport? viewport,
  }) : viewport = viewport ?? CanvasViewport();

  final BrushEditSessionState sessionState;
  final LayerId layerId;
  final FrameId frameId;
  final BrushEditCanvasInputSettings inputSettings;
  final ValueChanged<BrushStrokeCommitData> onSourceStrokeCommitted;
  final bool showTransparentBackground;
  final BrushDabInterpolator dabInterpolator;
  final CanvasSegmentClipper segmentClipper;
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
  final BrushDab? Function(CanvasPoint point, int color)? fillDabAt;

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
  /// folder's group buffer is one `saveLayer`, so the layer being drawn on
  /// has to be paintable by the same painter that opened it. Null keeps
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

  /// PEN-12 #4: the touch stroke's commitment tracking — sub-slop, a
  /// simultaneous second finger still converts the pair to navigation;
  /// committed, extra fingers are ignored (the mid-line vanish fix).
  Offset? _touchStrokeDownPosition;
  bool _touchStrokeCommitted = false;

  /// The commitment distance (the engine's lock slop — one number keeps
  /// the engine's navigate-lock and this view's cancel window agreeing).
  static const double kTouchStrokeCommitSlop = 18;

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

  /// The live mapped-hold session (PEN-7a): a secondary-button press
  /// whose canvas mapping switched the tool temporarily. One at a time;
  /// eyedropper holds pick continuously through the move stream.
  int? _mappedHoldPointer;
  CanvasPointerRelease? _mappedHoldRelease;
  bool _mappedHoldIsEyedropper = false;

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

  ActiveStrokeOverlayModel get _overlayModel =>
      widget.overlayModel ?? _ownedOverlayModel;

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
  bool _settling = false;
  Timer? _settlingFallbackTimer;

  /// Canvas region the settling stroke touched: only ITS tiles gate the
  /// overlay handoff (checking the whole surface stalled the drop on
  /// unrelated tiles, and the old flat 300ms give-up then revealed stale
  /// pre-stroke tiles — the "part of the stroke blinks" bug).
  DirtyRegion? _settlingBounds;

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
    _endStrokeInput();
    _resetOverlay();
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
      _clearStrokeInputState();
      _resetOverlay();
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
    _settlingFallbackTimer?.cancel();
    // Only OUR model — a host-owned one outlives this view (it survives
    // the layer switches that rebuild us).
    if (widget.overlayModel == null) {
      _ownedOverlayModel.dispose();
    } else {
      _overlayModel.reset();
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
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerUp,
            onPointerCancel: _handlePointerCancel,
            onPointerHover: _handlePointerHover,
            // paintsContent false: the merged stack painter draws this
            // surface in TREE order (inside whatever folder buffer holds
            // it) — this view stays for input alone. The listener above is
            // untouched, so the stroke path is identical.
            child: widget.paintsContent
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
                      overlayModel: _overlayModel,
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
        // Discard only a SUB-SLOP touch stroke — the first finger turned
        // out to be the start of a pinch, not a stroke (both fingers
        // landed together). A stylus/mouse stroke keeps drawing: extra
        // touch contacts alongside it are palm rests.
        if (touchStroke) {
          _endStrokeInput();
          _resetOverlay();
        }
        return;
      }
    }

    // PEN-7a: the CANVAS mapping for standard secondary inputs. Pen
    // side/barrel buttons, the S-Pen button and the mouse right button
    // all arrive as the RIGHT-CLICK bit; the pen upper button and the
    // wheel click as the MIDDLE bit. On canvas the user assigns what
    // they do (Input Settings ▸ Canvas); everywhere else the OS meaning
    // of the input rules untouched. The hold temporarily switches the
    // TOOL (the shared tool-switch path — cursor/panels follow free);
    // release springs back or keeps it per the mapping.
    var mappedErase = false;
    final mapping = _mappedPointerActionFor(event);
    if (mapping != null) {
      if (_multiTouchNavigation ||
          _activeDrawingPointer != null ||
          _mappedHoldPointer != null) {
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
          if (!_mappedButtonHeldSinceHover(event)) {
            widget.onInvokeAction?.call('edit-undo');
          }
          return;
        case CanvasPointerAction.redo:
          if (!_mappedButtonHeldSinceHover(event)) {
            widget.onInvokeAction?.call('edit-redo');
          }
          return;
        case CanvasPointerAction.eyedropper:
          _mappedHoldPointer = event.pointer;
          _mappedHoldRelease = mapping.release;
          _mappedHoldIsEyedropper = true;
          // The contact takes over a hover-engaged hold (R26 #19/#20):
          // one hold session, one release.
          _hoverToolHoldActive = false;
          _hoverToolHoldRelease = null;
          _hoverToolHoldButton = 0;
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
          _mappedHoldPointer = event.pointer;
          _mappedHoldRelease = mapping.release;
          _mappedHoldIsEyedropper = false;
          widget.onTemporaryToolHold?.call(CanvasTool.eraser);
        // Falls through into the normal stroke start below with the
        // erase-substituted settings snapshot.
      }
    }

    if (!mappedErase &&
        (_multiTouchNavigation ||
            _activeDrawingPointer != null ||
            !_isPrimaryButton(event.buttons))) {
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
      if (!startsInsidePasteboard || _pendingFillCommitDab != null) {
        // A deferred fill commit is one frame away — a second tap in
        // that window would interleave with it.
        return;
      }
      final dab = fillDabAt(canvasPosition, widget.inputSettings.color);
      if (dab == null) {
        return;
      }
      _handleFillDab(dab);
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
    _currentPressure = _normalizedPressure(event);
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
    _strokeDynamics = BrushStrokeDynamics(settings: strokeSettings);
    _lastDirectionDegrees = null;
    _previousBaseDab = null;
    _groundMixer = strokeSettings.shape.mixesGroundColor
        ? BrushGroundColorMixer(shape: strokeSettings.shape)
        : null;
    _resetOverlay();
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
    _overlayModel.configureTileSize(strokeSurface.tileSize);
    _overlayModel.erase = strokeSettings.erase;
    _overlayModel.blendMode = strokeSettings.blendMode;
    // R27 #4: EVERY stroke pre-blends its live tiles with the commit's
    // own kernels against the cel as it stands (user rule 07-23: ONE
    // display pipeline for all modes — color included). The GPU never
    // computes a pixel of the stroke composite, so pen-up cannot move a
    // byte in any mode. Revert switch if stroke feel regresses on
    // device: gate this on `blendMode != color` to give plain strokes
    // their classic stroke-only GPU-srcOver overlay back.
    _overlayModel.preBlendBase = strokeSurface;
    _collectedDabs.clear();
    _prepareLiveRasterizer();
    if (!startsInsidePasteboard) {
      return;
    }
    final initialDabs = _withPressureDynamics(
      widget.dabInterpolator.interpolate(
        previous: null,
        nextRaw: _dabFromPosition(canvasPosition, sequence: _nextSequence),
        firstSequence: _nextSequence,
        spacingRatio: _activeStrokeSpacing,
      ),
    );
    if (initialDabs.isNotEmpty) {
      _previousBaseDab = initialDabs.last;
    }
    // R20-B: dabs resolve through the tip-stamp cache HERE, at generation
    // — the overlay, the commit, undo replay and the .qap all see the
    // same resolved (quantized, prerotated-mask) dabs.
    final emitted = BrushTipStampCache.instance.resolveDabs(
      _withGroundMixing(
        _strokeDynamics!.apply(
          initialDabs,
          firstSequence: _nextSequence,
          directionDegrees: null,
        ),
      ),
    );
    _collectedDabs.addAll(emitted);
    _queueOverlayDabs(emitted);
    _nextSequence += emitted.length;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    // R27 #17: a mapped button can also rise DURING contact — some pen
    // drivers report the barrel bit a moment after the tip lands rather
    // than on the down event, and the hover edge above never sees it
    // then. Only picked up while nothing is drawing yet, so a live
    // stroke is never hijacked mid-line.
    _handleMappedButtonRiseDuringContact(event);
    // A held eyedropper mapping picks LIVE along the whole drag (PEN-7a:
    // '누르는 동안 해당 색을 뽑는다').
    if (event.pointer == _mappedHoldPointer && _mappedHoldIsEyedropper) {
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
            kTouchStrokeCommitSlop) {
      _touchStrokeCommitted = true;
    }

    _currentPressure = _normalizedPressure(event);
    final penPosition = _canvasPositionFromLocal(event.localPosition);
    _lastPenPosition = penPosition;
    // The stabilizer smooths BEFORE clipping/interpolation, so every
    // downstream consumer (overlay, commit, replay) sees one chain — the
    // three-route parity holds by construction (P7).
    _advanceStrokeTo(_stabilizer?.follow(penPosition) ?? penPosition);
  }

  void _advanceStrokeTo(CanvasPoint canvasPosition) {
    final previousRaw = _previousRawCanvasPosition;
    _previousRawCanvasPosition = canvasPosition;
    if (previousRaw == null) {
      return;
    }

    final canvasSize =
        widget.sessionState.canvasState.currentSurface.canvasSize;
    final clippedSegment = widget.segmentClipper.clip(
      previous: previousRaw,
      current: canvasPosition,
      canvasSize: canvasSize,
    );
    if (clippedSegment == null) {
      _breakCurrentVisibleSegment = true;
      return;
    }

    final previousDab =
        _breakCurrentVisibleSegment ||
            clippedSegment.startsNewVisibleSegment ||
            _previousBaseDab == null
        ? null
        : _previousBaseDab;
    final segmentStartDabs =
        clippedSegment.startsNewVisibleSegment ||
            _breakCurrentVisibleSegment ||
            _previousBaseDab == null
        ? _withPressureDynamics(
            widget.dabInterpolator.interpolate(
              previous: null,
              nextRaw: _dabFromPosition(
                clippedSegment.start,
                sequence: _nextSequence,
              ),
              firstSequence: _nextSequence,
              spacingRatio: _activeStrokeSpacing,
            ),
          )
        : const <BrushDab>[];
    final firstEndSequence = _nextSequence + segmentStartDabs.length;
    final endPrevious = segmentStartDabs.isNotEmpty
        ? segmentStartDabs.last
        : previousDab;
    final segmentEndDabs = _withPressureDynamics(
      widget.dabInterpolator.interpolate(
        previous: endPrevious,
        nextRaw: _dabFromPosition(
          clippedSegment.end,
          sequence: firstEndSequence,
        ),
        firstSequence: firstEndSequence,
        spacingRatio: _activeStrokeSpacing,
      ),
    );
    final baseDabs = <BrushDab>[...segmentStartDabs, ...segmentEndDabs];
    if (baseDabs.isEmpty) {
      return;
    }
    _previousBaseDab = baseDabs.last;

    _lastDirectionDegrees =
        strokeDirectionDegrees(from: previousRaw, to: canvasPosition) ??
        _lastDirectionDegrees;
    final emitted = BrushTipStampCache.instance.resolveDabs(
      _withGroundMixing(
        _strokeDynamics?.apply(
              baseDabs,
              firstSequence: _nextSequence,
              directionDegrees: _lastDirectionDegrees,
            ) ??
            baseDabs,
      ),
    );

    // No setState: pointer moves only QUEUE the new dabs (this runs at
    // pointer-sample frequency); the per-frame flush rasterizes the batch
    // and repaints the overlay layer directly, skipping widget rebuilds.
    _collectedDabs.addAll(emitted);
    _queueOverlayDabs(emitted);
    _nextSequence += emitted.length;
    _breakCurrentVisibleSegment = false;
  }

  void _queueOverlayDabs(List<BrushDab> newDabs) {
    if (newDabs.isEmpty) {
      return;
    }
    _pendingOverlayDabs.addAll(newDabs);
    if (_overlayFlushScheduled) {
      return;
    }
    _overlayFlushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _overlayFlushScheduled = false;
      if (mounted) {
        _flushPendingOverlayDabs();
      } else {
        _pendingOverlayDabs.clear();
      }
    });
    // Pointer samples can arrive while no frame is scheduled (nothing else
    // animating); make sure the flush frame actually happens.
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _flushPendingOverlayDabs() {
    if (_pendingOverlayDabs.isEmpty) {
      return;
    }
    final batch = List<BrushDab>.of(_pendingOverlayDabs);
    _pendingOverlayDabs.clear();
    _appendOverlayDabs(batch);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _lastContactButtons.remove(event.pointer);
    _forgetTouchPointer(event.pointer);
    _releaseMappedHold(event.pointer);
    if (event.pointer != _activeDrawingPointer) {
      return;
    }

    // Stabilizer catch-up (P7): the brush trails the pen by up to a rope
    // length — pen-up closes the gap with one straight segment through
    // the normal pipeline, so line ends land where the pen lifted.
    final lastPen = _lastPenPosition;
    if (_stabilizer != null && lastPen != null) {
      _advanceStrokeTo(lastPen);
    }

    final hadDabs = _collectedDabs.isNotEmpty;
    if (hadDabs) {
      // The commit reads the rasterizer's tiles — blend any dabs still
      // waiting on the per-frame flush first.
      _flushPendingOverlayDabs();
      _commitStroke();
    }

    _endStrokeInput();
    if (!hadDabs) {
      _resetOverlay();
    }
  }

  /// PROMOTION pen-up: the stroke is ALREADY blended into finished tiles
  /// (that is what has been on screen the whole time), so committing is
  /// installing them — no re-blend of the whole stroke, no re-decode, no
  /// "settling" window while a second decode lands.
  ///
  /// The order is what makes it invisible: promote the tiles, hand each
  /// one the overlay image that shows exactly its pixels, commit, then
  /// drop the overlay — all inside this one pointer event, so the very
  /// next frame paints committed tiles that already have their pictures.
  /// (The old route deferred a synchronous materialize by one frame and
  /// pinned the pre-stroke tiles until every post-commit decode landed;
  /// both existed only because commit re-derived what the screen already
  /// had.)
  void _commitStroke() {
    final rasterizer = _liveRasterizer;
    final base = _overlayModel.preBlendBase;
    final blendMode = (_activeStrokeInputSettings ?? widget.inputSettings)
        .blendMode;
    final erase = _overlayModel.erase;
    _liveRasterizer = null;
    if (rasterizer == null) {
      return;
    }
    final promotable = base != null && base.tileSize == rasterizer.tileSize;
    final promoted = promotable
        ? rasterizer.promoteStrokeTiles(
            base: base,
            mode: blendMode,
            erase: erase,
          )
        : const <PromotedStrokeTile>[];
    if (promotable) {
      // Hand the decoded images over BEFORE the commit: the painter must
      // never see an adopted tile without a picture (that is a frame of
      // stale content — the flicker the settle machinery existed for).
      // Only images at the promoted tile's own revision qualify; a
      // stale one would be pinned to that tile forever.
      for (final entry in promoted) {
        final image = _overlayModel.takeTileImageAt(
          entry.tile.coord,
          revision: entry.revision,
        );
        if (image != null) {
          BitmapTileImageCache.instance.adoptDecoded(
            entry.tile,
            image,
            staleScope: (widget.layerId, widget.frameId),
          );
        } else {
          // Its decode never landed (or landed a revision behind): start
          // one now. The coordinate was showing base pixels anyway, so
          // this is a continuation, not a regression.
          BitmapTileImageCache.instance.ensureDecoded(
            entry.tile,
            staleScope: (widget.layerId, widget.frameId),
          );
        }
      }
    }
    widget.onSourceStrokeCommitted(
      BrushStrokeCommitData(
        sourceDabs: List.of(_collectedDabs),
        // BB-1: the stroke's blend rides the payload — captured from the
        // stroke's settings SNAPSHOT, so a tool change can never flip a
        // committed stroke's mode.
        blendMode: blendMode,
        promotedBase: promotable ? base : null,
        promotedTiles: promotable
            ? [for (final entry in promoted) entry.tile]
            : null,
        // Without promotion (a host whose overlay grid differs from its
        // surface's) the classic payload still commits correctly: a
        // bounds-local row-major stroke buffer the commit composites.
        strokePixels: promotable ? null : rasterizer.strokePixelsWithinBounds(),
        strokeBounds: promotable ? null : rasterizer.strokeBounds,
      ),
    );
    rasterizer.clear();
    // Atomic: the overlay's remaining images retire in the same
    // notification that reveals the committed tiles.
    _resetOverlay();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _lastContactButtons.remove(event.pointer);
    _forgetTouchPointer(event.pointer);
    _releaseMappedHold(event.pointer);
    if (event.pointer != _activeDrawingPointer) {
      return;
    }

    _endStrokeInput();
    _resetOverlay();
  }

  void _forgetTouchPointer(int pointer) {
    _activeTouchPointers.remove(pointer);
    CanvasTouchContacts.remove(pointer);
    if (_activeTouchPointers.isEmpty) {
      _multiTouchNavigation = false;
    }
  }

  /// Every button bit that is NOT the primary contact (R27 #17 / R28).
  ///
  /// The mapping used to recognise EXACTLY `kSecondaryButton` and
  /// `kTertiaryButton`. A stylus barrel that a driver reports on any other
  /// bit — Windows Ink and the Wacom driver have several configurations —
  /// then fell through every branch in silence, which is the shape of the
  /// "와콤 펜은 우클릭버튼인거 확인했는데 툴이 아예 안 바뀜" report. Treating
  /// any non-primary bit as the secondary mapping costs nothing (the
  /// primary contact is the only one that draws) and stops the behaviour
  /// depending on which bit a driver happens to pick.
  static const int _nonPrimaryButtons = ~kPrimaryButton;

  /// The secondary-ish bits of [buttons]: null when only the primary (or
  /// nothing) is down.
  static int _mappedButtonBits(int buttons) => buttons & _nonPrimaryButtons;

  /// The canvas mapping row for a secondary-button press (PEN-7a); null =
  /// not a mapped press (primary drawing input, or touch).
  CanvasPointerMapping? _mappedPointerActionFor(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      return null;
    }
    return _mappingForButtons(_mappedButtonBits(event.buttons));
  }

  /// The mapping a set of non-primary [bits] drives: the wheel click owns
  /// the tertiary bit, and everything else reads as the secondary — the
  /// barrel button, whichever bit the driver puts it on.
  CanvasPointerMapping? _mappingForButtons(int bits) {
    if (bits == 0) {
      return null;
    }
    final settings = AppInput.settings.value;
    if ((bits & kTertiaryButton) != 0) {
      return settings.canvasWheelClick;
    }
    return settings.canvasRightClick;
  }

  /// Buttons seen on the latest HOVER event — the PEN-11 hover-press
  /// edge detector's memory (S-Pen/Wacom report barrel presses while
  /// hovering; a rising mapped button fires one-shot actions without
  /// needing contact — the S-Pen hover window blocks touch, so the pen
  /// carries its own undo).
  int _lastHoverButtons = 0;

  bool _mappedButtonHeldSinceHover(PointerDownEvent event) =>
      (_lastHoverButtons & _mappedButtonBits(event.buttons)) != 0;

  /// R26 #19/#20: a mapped HOLD tool (eyedropper) engaged from a hover
  /// button press — a Wacom barrel button pressed while the pen hovers
  /// never produced a pointer DOWN, so the mapping silently did nothing
  /// and no eyedropper UI appeared. The tool switches on the press edge
  /// and springs back on the release edge.
  bool _hoverToolHoldActive = false;
  CanvasPointerRelease? _hoverToolHoldRelease;
  int _hoverToolHoldButton = 0;

  void _handlePointerHover(PointerHoverEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }
    final previousButtons = _lastHoverButtons;
    final pressed = event.buttons & ~previousButtons;
    final released = previousButtons & ~event.buttons;
    _lastHoverButtons = event.buttons;
    if (_hoverToolHoldActive && (released & _hoverToolHoldButton) != 0) {
      final keep = _hoverToolHoldRelease == CanvasPointerRelease.keep;
      _hoverToolHoldActive = false;
      _hoverToolHoldRelease = null;
      _hoverToolHoldButton = 0;
      widget.onTemporaryToolRelease?.call(keep: keep);
    }
    final pressedBits = _mappedButtonBits(pressed);
    final mapping = _mappingForButtons(pressedBits);
    if (mapping == null) {
      return;
    }
    switch (mapping.action) {
      case CanvasPointerAction.undo:
        widget.onInvokeAction?.call('edit-undo');
      case CanvasPointerAction.eyedropper:
        // R26 #19/#20: engage the eyedropper on the HOVER press edge —
        // the pen barrel button is a right-click that never touches the
        // surface, and the tool switch is what brings the eyedropper's
        // cursor + live swatch up. The pick itself still happens on
        // contact (the mapped-down path below).
        if (!_hoverToolHoldActive && _mappedHoldPointer == null) {
          _hoverToolHoldActive = true;
          _hoverToolHoldRelease = mapping.release;
          _hoverToolHoldButton = pressedBits;
          widget.onTemporaryToolHold?.call(CanvasTool.eyedropper);
        }
      case CanvasPointerAction.redo:
        widget.onInvokeAction?.call('edit-redo');
      case CanvasPointerAction.eraser ||
          CanvasPointerAction.pan ||
          CanvasPointerAction.none:
        break;
    }
  }

  /// Buttons last seen on a CONTACT event, per pointer — the in-contact
  /// counterpart of [_lastHoverButtons] (R27 #17).
  final Map<int, int> _lastContactButtons = {};

  void _handleMappedButtonRiseDuringContact(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }
    final previous = _lastContactButtons[event.pointer] ?? 0;
    final pressed = event.buttons & ~previous;
    _lastContactButtons[event.pointer] = event.buttons;
    if (pressed == 0 ||
        _mappedHoldPointer != null ||
        _hoverToolHoldActive ||
        _activeDrawingPointer != null) {
      return;
    }
    final mapping = _mappingForButtons(_mappedButtonBits(pressed));
    if (mapping == null || mapping.action != CanvasPointerAction.eyedropper) {
      return;
    }
    _mappedHoldPointer = event.pointer;
    _mappedHoldRelease = mapping.release;
    _mappedHoldIsEyedropper = true;
    widget.onTemporaryToolHold?.call(CanvasTool.eyedropper);
    final pickPosition = _canvasPositionFromLocal(event.localPosition);
    if (_isInsidePasteboard(pickPosition)) {
      widget.onAltPick?.call(pickPosition);
    }
  }

  /// Ends an active mapped hold (pointer up/cancel): tells the shell to
  /// spring the tool back or keep it, per the mapping.
  void _releaseMappedHold(int pointer) {
    if (pointer != _mappedHoldPointer) {
      return;
    }
    final keep = _mappedHoldRelease == CanvasPointerRelease.keep;
    _mappedHoldPointer = null;
    _mappedHoldRelease = null;
    _mappedHoldIsEyedropper = false;
    widget.onTemporaryToolRelease?.call(keep: keep);
  }

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
  /// [_withPressureDynamics]) so each inserted dab scales by its own
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
      opacity: settings.opacity,
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

  List<BrushDab> _withPressureDynamics(List<BrushDab> dabs) {
    final settings = _activeStrokeInputSettings ?? widget.inputSettings;
    if (!settings.hasPressureDynamics) {
      return dabs;
    }
    return <BrushDab>[
      for (final dab in dabs)
        applyBrushPressureDynamics(
          dab,
          sizeCurve: settings.sizePressureCurve,
          opacityCurve: settings.opacityPressureCurve,
          flowCurve: settings.flowPressureCurve,
          hardnessCurve: settings.hardnessPressureCurve,
        ),
    ];
  }

  /// Normalizes a pointer's pressure into 0..1.
  ///
  /// Only stylus devices report meaningful pressure. A mouse claims a 0..1
  /// pressure range on some platforms while always reporting 0.0 — trusting
  /// it made pressure-sized strokes invisible — and touch pressure is
  /// unreliable across devices, so both paint at full pressure.
  ///
  /// Wintab sidecar (PEN-2): while the user has picked the Wintab tablet
  /// service and the driver stream is LIVE, the driver's pressure wins for
  /// EVERY kind — that is the point of the switch: a pen the OS pipeline
  /// misreports (touch, or mouse with Ink unchecked) paints with real
  /// pressure anyway. Stale/absent stream falls through unchanged.
  double _normalizedPressure(PointerEvent event) {
    // The response curve (PEN-3) shapes REAL pressure from either source
    // — the full-pressure fallbacks stay 1.0 through any gamma.
    final wintab = PenSidecars.freshContactPressure();
    if (wintab != null) {
      return AppInput.applyPressureCurve(wintab);
    }
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return 1.0;
    }
    final range = event.pressureMax - event.pressureMin;
    if (!range.isFinite || range <= 0.0) {
      return 1.0;
    }
    return AppInput.applyPressureCurve(
      ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0),
    );
  }

  /// Spacing for the segment about to be interpolated.
  ///
  /// Clip Studio rolls its interval randomness per dab. The interpolator is
  /// pure and shared, and a segment between two pointer samples almost
  /// always yields one or two dabs (it returns nothing at all when the move
  /// is shorter than one step), so rolling once per segment lands in the
  /// same place without threading a random source through it.
  double get _activeStrokeSpacing {
    final settings = _activeStrokeInputSettings ?? widget.inputSettings;
    final jitter = settings.spacingJitter;
    if (jitter <= 0.0) {
      return settings.spacing;
    }
    return settings.spacing * (1.0 - jitter * _spacingRandom.nextDouble());
  }

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

  void _endStrokeInput() {
    widget.onActiveStrokeChanged?.call(false);
    _clearStrokeInputState();
  }

  /// State-only stroke teardown — safe inside the build phase (no
  /// callbacks). [_endStrokeInput] is the pointer-event variant that also
  /// notifies synchronously.
  void _clearStrokeInputState() {
    _activeDrawingPointer = null;
    _touchStrokeDownPosition = null;
    _touchStrokeCommitted = false;
    _nextSequence = 0;
    _breakCurrentVisibleSegment = false;
    _previousRawCanvasPosition = null;
    _activeStrokeInputSettings = null;
    _currentPressure = 1.0;
    _strokeDynamics = null;
    _lastDirectionDegrees = null;
    _previousBaseDab = null;
    // The reservoir is per stroke: a new stroke starts with a clean brush.
    _groundMixer = null;
    _groundSampler = null;
    _stabilizer = null;
    _lastPenPosition = null;
    _collectedDabs.clear();
    _pendingOverlayDabs.clear();
  }

  /// Clears the visible overlay (live or settling) and its tile images.
  void _resetOverlay() {
    _settling = false;
    _settlingBounds = null;
    _settlingFallbackTimer?.cancel();
    _settlingFallbackTimer = null;
    // Invalidate any in-flight fill stamp decode (R23): applying it
    // after this reset would leave a ghost overlay with no settling to
    // clear it.
    _fillOverlayToken += 1;
    _overlayModel.reset();
  }

  /// How long the settling safety cap keeps waiting for tile decodes
  /// before force-dropping the overlay. Purely a stuck-state escape hatch:
  /// dropping EARLY is what used to blink parts of big strokes back to
  /// their pre-stroke tiles (the old 300ms flat timeout fired before slow
  /// decodes finished), so the deadline is generous and the periodic
  /// re-check below re-requests decodes instead of giving up.
  static const Duration _settlingDeadline = Duration(seconds: 2);
  static const Duration _settlingRecheckInterval = Duration(milliseconds: 50);

  void _beginSettling() {
    _settling = true;
    _settlingFallbackTimer?.cancel();
    var waited = Duration.zero;
    _settlingFallbackTimer = Timer.periodic(_settlingRecheckInterval, (timer) {
      if (!mounted || !_settling) {
        timer.cancel();
        return;
      }
      waited += _settlingRecheckInterval;
      if (waited >= _settlingDeadline) {
        timer.cancel();
        _resetOverlay();
        return;
      }
      // Belt and braces against a missed decode notification: re-request
      // the stroke tiles' decodes and re-run the handoff check.
      _requestSettlingDecodes();
      _onTileImagesChanged();
    });
    // Check after the parent rebuild delivers the post-commit session state;
    // checking synchronously would consult the pre-commit surface and clear
    // the overlay immediately, reintroducing the flash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestSettlingDecodes();
      _onTileImagesChanged();
    });
  }

  /// The committed-surface tiles the settling stroke touched (all tiles
  /// when the bounds are unknown).
  List<BitmapTile> _settlingTiles() {
    return settlingTilesForBounds(
      surface: widget.sessionState.canvasState.currentSurface,
      bounds: _settlingBounds,
    );
  }

  void _requestSettlingDecodes() {
    if (!_settling || !mounted) {
      return;
    }
    // Budgeted starts (R18 B-1): a canvas-covering stroke used to start
    // EVERY touched tile's decode in this one call — each start is a
    // synchronous tile copy + 65k-pixel premultiply, a pen-up hitch at
    // heavy sizes. Chunks chain instead: every decode completion notifies
    // the cache listener below, which re-requests the next chunk until
    // [allDecoded] releases the overlay (the overlay keeps the stroke on
    // screen throughout, so the handoff stays atomic and invisible).
    var budget = BitmapTileImageCache.decodeStartBudget;
    for (final tile in _settlingTiles()) {
      if (!BitmapTileImageCache.instance.needsDecodeStart(tile)) {
        continue;
      }
      BitmapTileImageCache.instance.ensureDecoded(
        tile,
        staleScope: (widget.layerId, widget.frameId),
      );
      budget -= 1;
      if (budget <= 0) {
        break;
      }
    }
  }

  void _onTileImagesChanged() {
    if (!_settling || !mounted) {
      return;
    }
    if (BitmapTileImageCache.instance.allDecoded(_settlingTiles())) {
      _resetOverlay();
    } else {
      // Not done yet — start the next decode chunk off this notification
      // (the 50ms timer stays as the belt-and-braces fallback).
      _requestSettlingDecodes();
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
  }

  /// Rasterizes [newDabs] into the live buffer (exact commit math) and
  /// re-decodes the touched overlay tiles.
  ///
  /// The overlay model snapshots and decodes each touched tile through the
  /// same premultiply + `decodeImageFromPixels` pipeline as the committed
  /// tiles, so the on-screen stroke rasterizes exactly like it will after
  /// commit; decode completions repaint the canvas painter directly.
  BrushDab? _pendingFillCommitDab;
  int _fillOverlayToken = 0;

  void _handleFillDab(BrushDab dab) {
    final stamp = dab.stamp;
    _resetOverlay();
    _overlayModel.erase = false;
    _overlayModel.blendMode = BrushBlendMode.color; // fills never blend
    final surface = widget.sessionState.canvasState.currentSurface;
    if (stamp != null) {
      final stampLeft = (dab.center.x - stamp.width / 2).round();
      final stampTop = (dab.center.y - stamp.height / 2).round();
      _settlingBounds = DirtyRegion(
        left: math.max(0, stampLeft),
        top: math.max(0, stampTop),
        rightExclusive: math.min(
          surface.canvasSize.width,
          stampLeft + stamp.width,
        ),
        bottomExclusive: math.min(
          surface.canvasSize.height,
          stampTop + stamp.height,
        ),
      );
      // R26 #18: a fill previews as ONE stamp image, so it does not pass
      // through the stroke pre-blend where the selection mask lives — the
      // mask goes onto the stamp's own bytes instead, once, before the
      // upload. The commit clips the same fill on its own buffer
      // (clipStrokePixelsToSelection), and both read the SAME scanline
      // mask, so the preview and the landed pixels agree at the boundary.
      final stampRgba = _maskedStampRgba(
        rgba: stamp.rgba,
        left: stampLeft,
        top: stampTop,
        width: stamp.width,
        height: stamp.height,
      );
      // The stamp is straight-alpha; the overlay pipeline (like the
      // tile images) uploads premultiplied. The fused C kernel does
      // 64MP in one pass — the same loop in Dart was seconds. The
      // scratch buffer is fresh per fill; the decode callback frees it.
      final engine = QaNativeEngine.instance;
      final Uint8List premultiplied;
      QaStampScratch? scratch;
      if (engine != null) {
        scratch = engine.premultipliedStampCopy(stampRgba);
        premultiplied = scratch.view;
      } else {
        premultiplied = _premultipliedCopyDart(stampRgba);
      }
      final token = _fillOverlayToken;
      ui.decodeImageFromPixels(
        premultiplied,
        stamp.width,
        stamp.height,
        ui.PixelFormat.rgba8888,
        (image) {
          scratch?.free();
          if (!mounted || token != _fillOverlayToken) {
            // The overlay was reset (settle handoff, frame switch, next
            // fill) before this decode landed — never painted, safe to
            // dispose directly.
            image.dispose();
            return;
          }
          _overlayModel.setStampOverlay(
            image,
            Offset(stampLeft.toDouble(), stampTop.toDouble()),
          );
        },
      );
    } else {
      // A stampless fill dab (synthetic/test): no overlay preview —
      // the deferred commit below still lands it identically.
      _settlingBounds = null;
    }
    // Pin the pre-fill tiles NOW: until the stamp image decodes the
    // canvas keeps showing the pre-fill picture (no flash), then the
    // overlay pops in complete.
    _overlayModel.holdPreStrokeTiles(
      preStrokeHoldTiles(surface: surface, bounds: _settlingBounds),
    );

    // Commit AFTER the tap frame renders: unconditional (never gated on
    // the decode callback — a fill must land even if the engine drops
    // the image), so the reveal and the commit jank overlap instead of
    // stacking.
    _pendingFillCommitDab = dab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runPendingFillCommit();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _runPendingFillCommit() {
    final dab = _pendingFillCommitDab;
    _pendingFillCommitDab = null;
    if (dab == null || !mounted) {
      return;
    }
    widget.onSourceStrokeCommitted(BrushStrokeCommitData(sourceDabs: [dab]));
    _beginSettling();
  }

  /// [rgba] with the live selection applied, or [rgba] itself when there
  /// is no selection (no copy, no scan).
  Uint8List _maskedStampRgba({
    required Uint8List rgba,
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    final region = widget.selectionRegion;
    if (region == null) {
      return rgba;
    }
    final masked = Uint8List.fromList(rgba);
    // The same rule the pre-blend kernel and the commit's clip run — a
    // fill only reaches a different function, never a different rule.
    applySelectionMaskToStrokeAlpha(
      pixels: masked,
      mask: region.maskFor(
        left: left,
        top: top,
        width: width,
        height: height,
      ),
      pixelCount: width * height,
    );
    return masked;
  }

  /// Fallback premultiply (engine absent) — same bytes as the overlay
  /// tile path: mul-div-255 rounding, alpha 0 zeroes the color.
  static Uint8List _premultipliedCopyDart(Uint8List rgba) {
    final bytes = Uint8List.fromList(rgba);
    for (var offset = 0; offset < bytes.length; offset += 4) {
      final alpha = bytes[offset + 3];
      if (alpha == 255) {
        continue;
      }
      if (alpha == 0) {
        bytes[offset] = 0;
        bytes[offset + 1] = 0;
        bytes[offset + 2] = 0;
        continue;
      }
      var product = bytes[offset] * alpha + 128;
      bytes[offset] = (product + (product >> 8)) >> 8;
      product = bytes[offset + 1] * alpha + 128;
      bytes[offset + 1] = (product + (product >> 8)) >> 8;
      product = bytes[offset + 2] * alpha + 128;
      bytes[offset + 2] = (product + (product >> 8)) >> 8;
    }
    return bytes;
  }

  void _appendOverlayDabs(List<BrushDab> newDabs) {
    if (newDabs.isEmpty) {
      return;
    }
    final rasterizer = _liveRasterizer;
    if (rasterizer == null) {
      return;
    }
    final from = _overlayModel.dabs.length;
    _overlayModel.dabs.addAll(newDabs);
    final region = rasterizer.blendFrom(_overlayModel.dabs, from: from);
    if (region != null) {
      _overlayModel.updateRegion(source: rasterizer, region: region);
    }
  }
}
