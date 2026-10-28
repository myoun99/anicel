import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart' show StrokeLander;
import '../canvas/view_hand.dart';
import '../canvas/stroke_in_flight.dart';

import '../../models/app_input_settings.dart';
import '../../models/layer_effect.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_frame_key.dart';
import '../playback/playback_frame_painter.dart';
import '../../models/brush_history_policy.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/drawing_guide.dart';
import '../../models/pasteboard_bounds.dart' show PasteboardSize;
import '../../models/canvas_viewport.dart';
import '../../models/project_background.dart';
import '../canvas/canvas_zoom_scale.dart';
import '../canvas/flip_hud_controller.dart';
import '../../services/command.dart';
import '../../services/brush_frame_edit_session_store.dart';
import '../../services/brush_frame_store.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/canvas_selection.dart' show SelectionMaskOptions;
import '../../services/canvas_selection_region.dart';
import '../../services/cut_piece_slot.dart';
import '../../services/last_stroke_slot.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/history_manager.dart';
import '../../services/piece_landing.dart';
import '../canvas/active_stroke_overlay.dart';
import '../../services/layer_pose_paint.dart';
import 'brush_canvas_panel.dart';
import 'canvas_floor_insets.dart';
import 'brush_editor_selection.dart';
import 'canvas_selection_commands.dart';
import 'cel_text_commands.dart';
import 'text_tool_options.dart';
import 'transform_tool_options.dart';
import 'canvas_view_commands.dart';
import 'brush_tool_state.dart';
import 'brush_edit_cache_invalidation_sink.dart';
import 'brush_canvas_defaults.dart';
import '../effective_device_pixel_ratio.dart';

/// Production main-canvas Brush host for HomePage integration.
///
/// The editor passes the active selection or a concrete [BrushFrameKey]. Missing
/// selection renders a safe placeholder instead of constructing fake editable
/// state. Drawing payload ownership remains in the coordinator/store boundary.
class MainCanvasBrushHost extends StatefulWidget {
  const MainCanvasBrushHost({
    super.key,
    this.activeFrameKey,
    this.selection,
    this.availableFrameKeys,
    this.canvasSize = BrushCanvasDefaults.canvasSize,
    this.guides,
    this.frameStore,
    this.cacheInvalidationSink,
    this.onCoordinatorChanged,
    this.historyManager,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.brushToolState,
    this.viewportOverlayBuilder,
    this.viewportControlsBuilder,
    this.viewportUnderlayBuilder,
    this.activeStrokeOverlayModel,
    this.interactiveContentOpacity = 1.0,
    this.interactiveContentPose,
    this.activeSourceEffects = const <ResolvedLayerEffect>[],
    this.contentOverride,
    this.toolInputEnabled = true,
    this.fitFocusRect,
    this.autoFrame,
    this.unframedFit,
    this.sampleColorAt,
    this.paperColor = ProjectBackground.defaultPaperArgb,
    this.paperNone = false,
    this.onPaperColorChanged,
    this.onPaperNone,
    this.pasteboardColor,
    this.pasteboardNone,
    this.onPasteboardColorChanged,
    this.onPasteboardNone,
    this.onPasteboardSizeChanged,
    this.onPasteboardInUseChanged,
    this.backdropArgb,
    this.backdropNone,
    this.onBackdropColorChanged,
    this.onBackdropNone,
    this.onTemporaryToolHold,
    this.onTemporaryToolRelease,
    this.onInvokeAction,
    this.onBrushSizeDragStart,
    this.onBrushSizeDragUpdate,
    this.onBrushSizeDragEnd,
    this.flipHud,
    this.leftPill,
    this.onEyedropperPick,
    this.fillDabsAt,
    this.shapeFillDabsFor,
    this.selectionMaskOptions,
    this.transformOptions,
    this.viewCommands,
    this.selectionCommands,
    this.textCommands,
    this.textToolOptions,
    this.cutPieceSlot,
    this.lastStroke,
    this.onStrokeInputActiveChanged,
    this.strokeLander,
    this.onSelectionInteractionChanged,
    this.onPressNeedsCel,
    this.markMakesItsOwnCel,
    this.onStrokeNeedsCel,
    this.standingFrameKeyOf,
    this.onAutoFrameSettled,
    this.takeStrokePrefixCommand,
    this.rowAcceptsStrokes = true,
    this.toolCursorsEnabled = true,
    this.transformTargetKeys,
    this.cellPlacementOf,
    this.transformCelsUnderfoot,
    this.pieceGround,
  });

  final BrushFrameKey? activeFrameKey;
  final BrushEditorSelection? selection;
  final List<BrushFrameKey>? availableFrameKeys;
  final CanvasSize canvasSize;

  /// The active cut's drawing guides, in canvas space — forwarded to the
  /// panel, which maps them into the layer's artwork space.
  final CutGuides? guides;

  /// Injectable stroke store (the session-owned one in production, so
  /// app-level commands can transform stroke data); defaults to a local one.
  final BrushFrameStore? frameStore;

  /// Injectable invalidation sink (the session hub in production, so
  /// playback caches hear about stroke edits); defaults to a local recorder.
  final CacheInvalidationSink? cacheInvalidationSink;

  /// 🚨Called when the live editing coordinator appears or is replaced, so a
  /// verb pressed OUTSIDE the canvas can act on the cels it owns.
  ///
  /// The PIXEL verbs (색 변환 · 픽셀 비우기) are pressed on the TIMELINE and
  /// write cel surfaces, and every surface write goes through this
  /// coordinator — it is what holds the editing session and the undo history
  /// that a second one would fight over.
  ///
  /// ⛔It is published UPWARD rather than threaded down as four more
  /// constructor arguments (workspace → tab host → toolbar → button). The
  /// session already owns `BrushFrameStore` and this host already takes it
  /// back as an injection, so 「the session holds the shared brush state」 is
  /// an existing fact rather than a new one.
  final ValueChanged<BrushFrameEditingCoordinator?>? onCoordinatorChanged;

  final HistoryManager? historyManager;
  final CanvasViewport? viewport;

  /// The view, OWNED by the caller — forwarded to
  /// [BrushCanvasPanel.viewportController].
  final ValueNotifier<CanvasViewport?>? viewportController;

  /// The view as the caller holds it, in DEVICE pixels — see
  /// [BrushCanvasPanel.publishedViewport] for why the two channels resolve
  /// in one place, and why the unit is the device's.
  CanvasViewport get publishedViewport =>
      (viewportController != null ? viewportController!.value : viewport) ??
      CanvasViewport();

  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// Forwarded to [BrushCanvasPanel.brushToolState] — heard, not handed
  /// over (H40 ②).
  final ValueListenable<BrushToolState>? brushToolState;

  /// Forwarded to [BrushCanvasPanel]: stacked over the canvas inside the
  /// editor viewport (e.g. the camera frame overlay).
  final Widget Function(BuildContext context, CanvasViewport viewport)?
  viewportOverlayBuilder;

  /// Forwarded to [BrushCanvasPanel]: the controls stacked over every tool
  /// layer (the standing row's transform box).
  final Widget Function(BuildContext context, CanvasViewport viewport)?
  viewportControlsBuilder;

  /// Forwarded to [BrushCanvasPanel]: painted under the interactive canvas
  /// (paper + layers below the active one) — or, in merged mode, the whole
  /// composite tree with the active layer inside it.
  final CanvasUnderlayBuilder? viewportUnderlayBuilder;

  /// Forwarded to [BrushCanvasPanel]: the host-owned live-stroke overlay
  /// that puts the canvas in MERGED mode (the active layer painted inside
  /// the composite tree, so folder buffers can enclose it).
  final ActiveStrokeOverlayModel? activeStrokeOverlayModel;

  /// Forwarded to [BrushCanvasPanel]: the active layer's display opacity.
  final double interactiveContentOpacity;

  /// Forwarded to [BrushCanvasPanel]: the active layer's pose sample (the
  /// draw-through wrap; null = identity).
  final LayerPlacement? interactiveContentPose;

  /// The CPU half of the ACTIVE row's effect chain — the colour keys the
  /// live surface has to be drawn THROUGH.
  ///
  /// 🚨The row you are drawing on is the one place the keys cannot arrive
  /// on their own: it is painted tile by tile from the coordinator's live
  /// surface, so it sees neither the composite plan nor the layer-frame
  /// image cache, which are the two places the pass runs. Handed down
  /// rather than re-resolved here, so the panel and the stack cannot come
  /// to different answers about the same row.
  final List<ResolvedLayerEffect> activeSourceEffects;

  /// Forwarded to [BrushCanvasPanel]: replaces the interactive canvas inside
  /// the panel shell (playback). Without an editable frame the host supplies
  /// its own blank-canvas override, so the paper always shows.
  final Widget Function(BuildContext context, CanvasViewport viewport)?
  contentOverride;

  /// Forwarded to [BrushCanvasPanel.toolInputEnabled]: false while the
  /// content takes no tool — playback.
  final bool toolInputEnabled;

  /// Forwarded to [BrushCanvasPanel]: canvas-space rect the Fit button
  /// frames instead of the whole canvas.
  final Rect? fitFocusRect;

  /// Forwarded to [BrushCanvasPanel]: the playback-follow reframe request
  /// (D12 — playback defaults to fit, one token per playing cut). Null
  /// never reframes — every other mount of this host stays byte-identical.
  final CanvasAutoFrameRequest? autoFrame;

  /// Forwarded to [BrushCanvasPanel.unframedFit]: the framing an unframed
  /// view resolves to instead of the 1:1 identity, which is how playback's
  /// camera fit stands in front of the user's own without writing over it.
  final Rect? unframedFit;

  /// Forwarded to [BrushCanvasPanel]: the P5 eyedropper's composite sampler
  /// and pick handlers, and the P6 fill dab builder.
  final int? Function(CanvasPoint point)? sampleColorAt;

  /// R28 #9 pass-through: the canvas paper (project) and the pasteboard,
  /// with their commit handlers.
  final int paperColor;
  final ValueChanged<int>? onPaperColorChanged;

  /// F-114 pass-through: the paper's absence and its 「없음」.
  final bool paperNone;
  final VoidCallback? onPaperNone;

  /// null = from [CanvasStageColors], the shell's one answer for every
  /// canvas panel (유저, R4 #2). Same contract as on [BrushCanvasPanel];
  /// this host only carries it through — the absence too.
  final int? pasteboardColor;
  final ValueChanged<int>? onPasteboardColorChanged;
  final bool? pasteboardNone;
  final VoidCallback? onPasteboardNone;
  final ValueChanged<PasteboardSize>? onPasteboardSizeChanged;
  final ValueChanged<bool>? onPasteboardInUseChanged;

  /// The BACKDROP behind the pasteboard (R3b). null = from the scope.
  final int? backdropArgb;
  final ValueChanged<int>? onBackdropColorChanged;
  final bool? backdropNone;
  final VoidCallback? onBackdropNone;

  /// PEN-7a mapped-hold pass-through (canvas right/wheel mappings).
  final void Function(CanvasTool tool)? onTemporaryToolHold;
  final void Function({required bool keep})? onTemporaryToolRelease;

  /// PEN-7b: control-mode touch slot pass-throughs.
  final void Function(String actionId)? onInvokeAction;
  final VoidCallback? onBrushSizeDragStart;
  final void Function(double upwardDelta, {required bool snap})?
  onBrushSizeDragUpdate;
  final VoidCallback? onBrushSizeDragEnd;

  /// The flip HUD's state, threaded down to the panel that mounts it.
  final FlipHudController? flipHud;

  /// See [BrushCanvasPanel.leftPill] — the brush's values, where the
  /// workspace stands them on the drawing.
  final CanvasEdgePill? leftPill;
  final ValueChanged<int>? onEyedropperPick;
  final List<BrushDab> Function(
    CanvasPoint point,
    int color,
    SymmetryShape? symmetry,
  )?
  fillDabsAt;

  /// Forwarded to [BrushCanvasPanel]: builds the stamp pieces of a drawn
  /// shape fill's area.
  final List<BrushDab> Function(CanvasSelectionRegion area, int color)?
  shapeFillDabsFor;

  /// Forwarded to [BrushCanvasPanel] (R26): the Select tool's lift-time
  /// mask knobs.
  final ValueListenable<SelectionMaskOptions>? selectionMaskOptions;

  /// Forwarded to [BrushCanvasPanel]: the transform tool's settings (mode,
  /// scale anchor, resampler, mesh grid).
  final ValueListenable<TransformToolOptions>? transformOptions;

  /// Forwarded to [BrushCanvasPanel]: the P8 rotate/flip shortcut channel.
  final CanvasViewCommands? viewCommands;

  /// Forwarded to [BrushCanvasPanel]: the P9 selection shortcut channel.
  final CanvasSelectionCommands? selectionCommands;

  /// Forwarded to [BrushCanvasPanel] (R9-rest): the text tool's channel and
  /// the next text's values.
  final CelTextCommands? textCommands;
  final ValueNotifier<TextToolOptions>? textToolOptions;

  /// Where a finished cut lands — threaded down to the canvas panel.
  final CutPieceSlot? cutPieceSlot;

  /// The last drawing action — threaded down to the canvas panel, which
  /// records it and lays it down again for 확정.
  final LastStrokeSlot? lastStroke;

  /// Forwarded to [BrushCanvasPanel]: stroke lifecycle (R13-3 warm hold).
  final ValueChanged<StrokeInFlight>? onStrokeInputActiveChanged;

  /// Forwarded to [BrushCanvasPanel]: where the canvas holds up what a
  /// save lands first — see [BrushCanvasPanel.strokeLander].
  final ViewHand<StrokeLander>? strokeLander;

  /// Forwarded to [BrushCanvasPanel]: selection-drag lifecycle — the
  /// prerender's warm hold (↩️F-196: no longer a
  /// seek lock, R15-⑤).
  final ValueChanged<bool>? onSelectionInteractionChanged;

  /// R26 #35: a paint attempt with NO editable cel under the playhead.
  /// The shell answers through the shared cursor notice ("no frame here"
  /// / "only the Action section can be drawn on") — the host cannot know
  /// WHICH refusal applies, so it only reports the attempt.
  /// 🚨WHAT A PRESS WITH NO CEL UNDER IT DOES — ONE QUESTION, ONE ANSWER.
  ///
  /// It used to be two callbacks (`onAutoCreateFrame`, then `onDrawRefused`
  /// if that returned false) spelled out at one call site. That reads as one
  /// question written in two places, and the moment there were TWO call
  /// sites — the view hears the empty-cel press itself now (I-10) — the
  /// shape would have made the shell explain a refusal for a cel it had just
  /// created.
  ///
  /// Returns true when a cel was made and the caller may draw into it. False
  /// means nothing was made, and the shell has already said why (or had
  /// nothing to say: a tool that marks nothing asks for no block and earns
  /// no notice).
  final bool Function()? onPressNeedsCel;

  /// Whether a mark pressed now makes a cel of its own although one stands
  /// under the playhead (I-113) — see
  /// [InteractiveBrushEditCanvasView.markMakesItsOwnCel]. A press it takes
  /// is the view's to ask about, so the panel's tool entrance stays quiet
  /// over it: the cel stands, and its row takes strokes
  /// (`_CanvasPanelTap.pressNoLayerHears`).
  final bool Function()? markMakesItsOwnCel;

  /// The same answer for a STROKE whatever tool is up — what 확정's 재입력
  /// asks on an empty cell (confirm-button). [onPressNeedsCel] is this after
  /// its tool question.
  final bool Function()? onStrokeNeedsCel;

  /// 🚨F-171 — where the editing stack STANDS before any cel exists: the
  /// cel the next press would make (`AutoFrameForStroke.frameIdForNextCel`).
  ///
  /// Asked when there is no editing stack and nothing under the playhead to
  /// key one to, so the editing view is mounted — and hears the press — from
  /// the first frame on, exactly as it does on any other empty cell. Null
  /// leaves the blank canvas standing in, as it does for a host that makes
  /// no cels.
  final BrushFrameKey? Function()? standingFrameKeyOf;

  /// Settles a block [onPressNeedsCel] made that no stroke claimed
  /// (I-10). Safe in either order against the stroke's own take.
  final VoidCallback? onAutoFrameSettled;

  /// The block [onPressNeedsCel] made, handed to the stroke it was
  /// made for so the two undo together (I-10).
  final Command? Function()? takeStrokePrefixCommand;

  /// Whether the row the frame-axis verbs are standing on takes strokes at
  /// all (user, 2026-08-08).
  ///
  /// False while you are standing on a PROPERTY LANE. Standing there used
  /// to leave drawing available on the layer underneath — "그림은 그릴 수
  /// 있을지라도 서있는건 하나" — and the user retired that: a lane is a row
  /// you can be ON, so being on it is not being on the layer, and a stroke
  /// aimed at a property has nowhere to land.
  ///
  /// It joins the SAME gate an empty frame goes through, so every pixel
  /// verb refuses for one reason and the shared cursor notice explains it.
  final bool rowAcceptsStrokes;

  /// Forwarded to [BrushCanvasPanel.toolCursorsEnabled]: false on a row the
  /// marking tools have nothing to do with — a property lane, the camera, a
  /// data or reference row (F-285).
  final bool toolCursorsEnabled;

  /// Which cels a transform confirm lands on (F-116-b) — passed straight
  /// through to the panel, which is where the law is written down.
  final List<BrushFrameKey> Function()? transformTargetKeys;

  /// Where each of those cels' rows stands on the canvas — passed straight
  /// through to the panel ([BrushCanvasPanel.cellPlacementOf]).
  final LayerPlacement? Function(BrushFrameKey key)? cellPlacementOf;

  /// What a transform takes up where you stand (I-37 · F-329) — passed
  /// straight through to the panel
  /// ([BrushCanvasPanel.transformCelsUnderfoot]).
  final List<({BrushFrameKey key, bool live})>? Function()?
  transformCelsUnderfoot;

  /// Where the cut tool's stamp lands (F-293) — passed straight through to
  /// the panel ([BrushCanvasPanel.pieceGround]).
  final PieceGround Function()? pieceGround;

  BrushFrameKey? get resolvedActiveFrameKey =>
      activeFrameKey ?? selection?.toBrushFrameKey();

  @override
  State<MainCanvasBrushHost> createState() => _MainCanvasBrushHostState();
}

class _MainCanvasBrushHostState extends State<MainCanvasBrushHost> {
  late final CacheInvalidationSink _cacheInvalidationSink =
      widget.cacheInvalidationSink ?? BrushEditCacheInvalidationSink();
  late final BrushFrameStore _frameStore =
      widget.frameStore ?? BrushFrameStore();

  late List<BrushFrameKey> _frameKeys = _resolveFrameKeys();
  BrushFrameEditingCoordinator? _coordinator;

  @override
  void initState() {
    super.initState();
    _selectResolvedFrame();
  }

  @override
  void didUpdateWidget(covariant MainCanvasBrushHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _frameKeys = _resolveFrameKeys();
    if (widget.canvasSize != oldWidget.canvasSize) {
      // Keep the coordinator (undo history included); the session
      // reseeds from the baked truth at the new size. R27: the resize
      // is scoped to the NEWLY resolved cut — on a cut switch its cels
      // already sit at this size (pure adoption), and other cuts' cels
      // are never touched (the old global resize clipped them).
      final cutId = _frameKeys.isNotEmpty ? _frameKeys.first.cutId : null;
      if (cutId != null) {
        _coordinator?.resizeCanvas(widget.canvasSize, cutId: cutId);
      } else {
        _coordinator?.adoptCanvasSize(widget.canvasSize);
      }
    }
    _selectResolvedFrame();
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = _coordinator;
    // 🚨H19 (유저 2026-08-23): 「**서있는 곳이 fx행이면 현재 있는 레이어의
    // 그림이 사라짐.** 대체 이딴규칙 누가만드는거지?」
    //
    // ⛔TWO DIFFERENT QUESTIONS WERE SHARING ONE FLAG, and one of them
    // answers with a blank screen:
    //   * IS THERE A CEL under the playhead — no cel, nothing to paint, so
    //     `InteractiveBrushEditCanvasView` stands down and draws nothing.
    //     That is correct, and it is what the flag was written for.
    //   * DOES THIS ROW TAKE STROKES — a property lane does not. But the
    //     cel is still THERE, and the canvas is where you look at it.
    //
    // `rowAcceptsStrokes` was folded into the first question, so standing
    // on an fx row blanked artwork that exists. They are separate now: the
    // CEL question decides what is PAINTED, the ROW question decides what a
    // press may DO.
    final hasCelUnderPlayhead = _frameKeys.isNotEmpty && coordinator != null;
    // The blank canvas is for having NO COORDINATOR — a project where
    // nothing has been drawn yet, so the panel has no editing stack to
    // show. It is deliberately NOT the answer to "the playhead is on an
    // empty frame": that used to swap the whole interactive canvas for a
    // blank box on every flip that crossed a block, mounting and
    // unmounting the editing view per step. The frame's emptiness travels
    // as `celEditable` now, and the view stands down in place.
    final contentOverride =
        widget.contentOverride ??
        (coordinator == null ? _blankCanvasContent : null);

    // ⛔Nothing wraps the panel CONDITIONALLY here. A [ValueKey] holds
    // identity only under the SAME parent, so a wrapper that came and went
    // with 「no cel ↔ cel」 tore `_BrushCanvasPanelState` down on every flip
    // that crossed it — mid-gesture the pointer kept going to the DISPOSED
    // render object, and the flip HUD ended for the rest of the drag. A
    // widget whose subtree carries live gesture state must not change shape
    // under it.
    //
    // ↩️A translucent Listener stood around the panel here for the press no
    // layer hears (I-10 · R26 #35) — an ancestor of every control on the
    // canvas, so a drag of the camera's box was told the row takes no
    // strokes (F-377). It is the panel's tool entrance now
    // (`_CanvasPanelTap.pressNoLayerHears`), where a press a control took
    // never arrives.
    //
    // 🗣️I-27 (유저 2026-09-13): 「최대 줌 제한기능 … 100% 넘어서 확대하지
    // 못하게 락」 — and, asked where it holds (I-27-Q1): 「그리기 캔버스만」.
    // This host IS the drawing canvas, so it is the one place that says
    // the lock to the view under it; the sheets and the viewers build the
    // same panel and say nothing.
    return ValueListenableBuilder<AppInputSettings>(
      valueListenable: AppInput.settings,
      builder: (context, settings, panel) => CanvasZoomCeiling(
        percent: settings.zoomCeiling,
        child: panel!,
      ),
      child: _buildPanel(coordinator, hasCelUnderPlayhead, contentOverride),
    );
  }

  Widget _buildPanel(
    BrushFrameEditingCoordinator? coordinator,
    bool hasCelUnderPlayhead,
    Widget Function(BuildContext, CanvasViewport)? contentOverride,
  ) {
    return BrushCanvasPanel(
      key: const ValueKey<String>('main-canvas-brush-host'),
      // Zero unless this host is lying on the app's floor — which is a
      // question about WHERE it is mounted, so the tree answers it. A host
      // opened in a rail column or the bottom panel is simply not under the
      // provider, and nothing lies on it.
      floorCover: CanvasFloorInsets.maybeOf(context)?.insets ?? EdgeInsets.zero,
      floorLeftRailBand: CanvasFloorInsets.maybeOf(context)?.leftRailBand,
      floorRightRailBand: CanvasFloorInsets.maybeOf(context)?.rightRailBand,
      // ⑩: what a control on the bottom edge has to clear.
      floorBottomOverlaySpan:
          CanvasFloorInsets.maybeOf(context)?.bottomOverlaySpan ?? 0,
      coordinator: coordinator,
      celEditable: hasCelUnderPlayhead,
      // H19: the row question, carried separately — the pixel verbs still
      // refuse on a property lane, the artwork still shows.
      rowAcceptsStrokes: widget.rowAcceptsStrokes,
      toolCursorsEnabled: widget.toolCursorsEnabled,
      availableFrameKeys: _frameKeys,
      transformTargetKeys: widget.transformTargetKeys,
      cellPlacementOf: widget.cellPlacementOf,
      transformCelsUnderfoot: widget.transformCelsUnderfoot,
      pieceGround: widget.pieceGround,
      cacheInvalidationSink: _cacheInvalidationSink,
      canvasSize: widget.canvasSize,
      guides: widget.guides,
      historyManager: widget.historyManager,
      takeStrokePrefixCommand: widget.takeStrokePrefixCommand,
      onPressNeedsCel: widget.onPressNeedsCel,
      markMakesItsOwnCel: widget.markMakesItsOwnCel,
      onStrokeNeedsCel: widget.onStrokeNeedsCel,
      onAutoFrameSettled: widget.onAutoFrameSettled,
      viewport: widget.viewport,
      viewportController: widget.viewportController,
      onViewportChanged: widget.onViewportChanged,
      brushToolState: widget.brushToolState,
      viewportOverlayBuilder: widget.viewportOverlayBuilder,
      viewportControlsBuilder: widget.viewportControlsBuilder,
      viewportUnderlayBuilder: widget.viewportUnderlayBuilder,
      activeStrokeOverlayModel: widget.activeStrokeOverlayModel,
      interactiveContentOpacity: widget.interactiveContentOpacity,
      interactiveContentPose: widget.interactiveContentPose,
      activeSourceEffects: widget.activeSourceEffects,
      contentOverride: contentOverride,
      toolInputEnabled: widget.toolInputEnabled,
      fitFocusRect: widget.fitFocusRect,
      autoFrame: widget.autoFrame,
      unframedFit: widget.unframedFit,
      sampleColorAt: widget.sampleColorAt,
      paperColor: widget.paperColor,
      paperNone: widget.paperNone,
      onPaperColorChanged: widget.onPaperColorChanged,
      onPaperNone: widget.onPaperNone,
      pasteboardColor: widget.pasteboardColor,
      pasteboardNone: widget.pasteboardNone,
      onPasteboardColorChanged: widget.onPasteboardColorChanged,
      onPasteboardNone: widget.onPasteboardNone,
      onPasteboardSizeChanged: widget.onPasteboardSizeChanged,
      onPasteboardInUseChanged: widget.onPasteboardInUseChanged,
      backdropArgb: widget.backdropArgb,
      backdropNone: widget.backdropNone,
      onBackdropColorChanged: widget.onBackdropColorChanged,
      onBackdropNone: widget.onBackdropNone,
      onTemporaryToolHold: widget.onTemporaryToolHold,
      onTemporaryToolRelease: widget.onTemporaryToolRelease,
      onInvokeAction: widget.onInvokeAction,
      onBrushSizeDragStart: widget.onBrushSizeDragStart,
      onBrushSizeDragUpdate: widget.onBrushSizeDragUpdate,
      onBrushSizeDragEnd: widget.onBrushSizeDragEnd,
      flipHud: widget.flipHud,
      leftPill: widget.leftPill,
      onEyedropperPick: widget.onEyedropperPick,
      fillDabsAt: widget.fillDabsAt,
      shapeFillDabsFor: widget.shapeFillDabsFor,
      selectionMaskOptions: widget.selectionMaskOptions,
      transformOptions: widget.transformOptions,
      viewCommands: widget.viewCommands,
      selectionCommands: widget.selectionCommands,
      textCommands: widget.textCommands,
      textToolOptions: widget.textToolOptions,
      cutPieceSlot: widget.cutPieceSlot,
      lastStroke: widget.lastStroke,
      onStrokeInputActiveChanged: widget.onStrokeInputActiveChanged,
      strokeLander: widget.strokeLander,
      onSelectionInteractionChanged: widget.onSelectionInteractionChanged,
    );
  }

  Widget _blankCanvasContent(BuildContext context, CanvasViewport viewport) {
    // With an underlay the paper AND the layers below the active one are
    // already painted underneath — drawing another opaque paper here buried
    // them (the "artwork exists but the canvas shows blank paper" bug
    // whenever the active layer had no frame at the playhead). Only the
    // standalone case paints its own paper.
    if (widget.viewportUnderlayBuilder != null) {
      return const SizedBox.expand(
        key: ValueKey<String>('main-canvas-brush-host-blank-canvas'),
      );
    }
    return CustomPaint(
      key: const ValueKey<String>('main-canvas-brush-host-blank-canvas'),
      painter: PlaybackFramePainter(
        canvasSize: widget.canvasSize,
        viewport: viewport,
        // The pan-phase snap's device grid — the blank-canvas paper must
        // sit exactly where the editing stack's paper lands.
        devicePixelRatio: EffectiveDevicePixelRatio.of(context),
      ),
      child: const SizedBox.expand(),
    );
  }

  List<BrushFrameKey> _resolveFrameKeys() {
    final explicitKeys = widget.availableFrameKeys;
    final activeKey = widget.resolvedActiveFrameKey;
    if (activeKey == null) {
      return const [];
    }
    if (explicitKeys == null || explicitKeys.isEmpty) {
      return [activeKey];
    }
    if (explicitKeys.contains(activeKey)) {
      return List<BrushFrameKey>.unmodifiable(explicitKeys);
    }
    return List<BrushFrameKey>.unmodifiable([...explicitKeys, activeKey]);
  }

  void _selectResolvedFrame() {
    if (_frameKeys.isEmpty) {
      _standWithoutACel();
      return;
    }
    final activeKey = widget.resolvedActiveFrameKey ?? _frameKeys.first;
    final coordinator = _coordinator;
    if (coordinator == null) {
      final made = _createCoordinator(initialFrameKey: activeKey);
      _coordinator = made;
      _publish(made);
      return;
    }
    coordinator.selectFrame(activeKey);
    _publish(coordinator);
  }

  /// 🚨F-171: with no stack and no cel, the stack STANDS on the cel the
  /// next press would make, so the editing view is there to hear it. A
  /// standing stack touches no frame (only [BrushFrameEditingCoordinator.
  /// selectFrame] does) and is not handed to the session until it stands on
  /// a real cel — until then there is nothing the session's verbs could act
  /// on.
  void _standWithoutACel() {
    if (_coordinator != null) {
      return;
    }
    final key = widget.standingFrameKeyOf?.call();
    if (key != null) {
      _coordinator = _createCoordinator(initialFrameKey: key);
    }
  }

  /// Hands the stack to the session the first time it stands on a cel.
  void _publish(BrushFrameEditingCoordinator coordinator) {
    if (identical(_published, coordinator)) {
      return;
    }
    _published = coordinator;
    widget.onCoordinatorChanged?.call(coordinator);
  }

  /// The stack the session was last handed — see [_publish].
  BrushFrameEditingCoordinator? _published;

  BrushFrameEditingCoordinator _createCoordinator({
    required BrushFrameKey initialFrameKey,
  }) {
    return BrushFrameEditingCoordinator(
      initialFrameKey: initialFrameKey,
      frameStore: _frameStore,
      sessionStore: BrushFrameEditSessionStore(canvasSize: widget.canvasSize),
      historyPolicy: const BrushHistoryPolicy(),
    );
  }
}
