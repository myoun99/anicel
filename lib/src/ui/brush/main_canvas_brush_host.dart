import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/brush_dab.dart';
import '../../models/brush_frame_key.dart';
import '../playback/playback_frame_painter.dart';
import '../../models/brush_history_policy.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/project_background.dart';
import '../canvas/flip_hud_controller.dart';
import '../../services/brush_frame_edit_session_store.dart';
import '../../services/brush_frame_store.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/canvas_selection.dart' show SelectionMaskOptions;
import '../../services/resample/resample_kernel.dart' show ResampleMode;
import '../../services/cache_invalidation_executor.dart';
import '../../services/history_manager.dart';
import '../canvas/active_stroke_overlay.dart';
import '../canvas/layer_pose_paint.dart';
import '../input/app_input_settings.dart' show AppInput;
import 'brush_canvas_panel.dart';
import 'canvas_floor_insets.dart';
import 'brush_editor_selection.dart';
import 'canvas_selection_commands.dart';
import 'canvas_view_commands.dart';
import 'brush_tool_state.dart';
import 'brush_edit_cache_invalidation_sink.dart';
import 'brush_canvas_defaults.dart';

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
    this.frameStore,
    this.cacheInvalidationSink,
    this.historyManager,
    this.viewport,
    this.onViewportChanged,
    this.brushToolState = BrushToolState.defaults,
    this.viewportOverlayBuilder,
    this.viewportUnderlayBuilder,
    this.activeStrokeOverlayModel,
    this.interactiveContentOpacity = 1.0,
    this.interactiveContentPose,
    this.contentOverride,
    this.fitFocusRect,
    this.sampleColorAt,
    this.paperColor = ProjectBackground.defaultPaperArgb,
    this.onPaperColorChanged,
    this.pasteboardColor,
    this.pasteboardMargin,
    this.onPasteboardColorChanged,
    this.backdropArgb,
    this.onBackdropColorChanged,
    this.onTemporaryToolHold,
    this.onTemporaryToolRelease,
    this.onInvokeAction,
    this.onBrushSizeDragStart,
    this.onBrushSizeDragUpdate,
    this.onBrushSizeDragEnd,
    this.flipHud,
    this.onEyedropperPick,
    this.onAltColorPick,
    this.fillDabAt,
    this.selectionMaskOptions,
    this.transformResampleMode,
    this.viewCommands,
    this.selectionCommands,
    this.onStrokeInputActiveChanged,
    this.onSelectionInteractionChanged,
    this.onDrawRefused,
  });

  final BrushFrameKey? activeFrameKey;
  final BrushEditorSelection? selection;
  final List<BrushFrameKey>? availableFrameKeys;
  final CanvasSize canvasSize;

  /// Injectable stroke store (the session-owned one in production, so
  /// app-level commands can transform stroke data); defaults to a local one.
  final BrushFrameStore? frameStore;

  /// Injectable invalidation sink (the session hub in production, so
  /// playback caches hear about stroke edits); defaults to a local recorder.
  final CacheInvalidationSink? cacheInvalidationSink;

  final HistoryManager? historyManager;
  final CanvasViewport? viewport;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  final BrushToolState brushToolState;

  /// Forwarded to [BrushCanvasPanel]: stacked over the canvas inside the
  /// editor viewport (e.g. the camera frame overlay).
  final Widget Function(BuildContext context, CanvasViewport viewport)?
  viewportOverlayBuilder;

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
  final LayerPoseSample? interactiveContentPose;

  /// Forwarded to [BrushCanvasPanel]: replaces the interactive canvas inside
  /// the panel shell (playback). Without an editable frame the host supplies
  /// its own blank-canvas override, so the paper always shows.
  final Widget Function(BuildContext context, CanvasViewport viewport)?
  contentOverride;

  /// Forwarded to [BrushCanvasPanel]: canvas-space rect the Fit button
  /// frames instead of the whole canvas.
  final Rect? fitFocusRect;

  /// Forwarded to [BrushCanvasPanel]: the P5 eyedropper's composite sampler
  /// and pick handlers, and the P6 fill dab builder.
  final int? Function(CanvasPoint point)? sampleColorAt;

  /// R28 #9 pass-through: the canvas paper (project) and the pasteboard,
  /// with their commit handlers.
  final int paperColor;
  final ValueChanged<int>? onPaperColorChanged;

  /// null = from [CanvasStageColors], the shell's one answer for every
  /// canvas panel (유저, R4 #2). Same contract as on [BrushCanvasPanel];
  /// this host only carries it through.
  final int? pasteboardColor;

  /// How far past the canvas the pasteboard SHOWS, in canvas widths and
  /// heights ([Project.pasteboardMargin]). null = from the scope.
  final double? pasteboardMargin;
  final ValueChanged<int>? onPasteboardColorChanged;

  /// The BACKDROP behind the pasteboard (R3b). null = from the scope.
  final int? backdropArgb;
  final ValueChanged<int>? onBackdropColorChanged;

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
  final ValueChanged<int>? onEyedropperPick;
  final ValueChanged<int>? onAltColorPick;
  final BrushDab? Function(CanvasPoint point, int color)? fillDabAt;

  /// Forwarded to [BrushCanvasPanel] (R26): the Select tool's lift-time
  /// mask knobs.
  final ValueListenable<SelectionMaskOptions>? selectionMaskOptions;

  /// Forwarded to [BrushCanvasPanel] (P3a): which resampler a transform
  /// commit runs through.
  final ValueListenable<ResampleMode>? transformResampleMode;

  /// Forwarded to [BrushCanvasPanel]: the P8 rotate/flip shortcut channel.
  final CanvasViewCommands? viewCommands;

  /// Forwarded to [BrushCanvasPanel]: the P9 selection shortcut channel.
  final CanvasSelectionCommands? selectionCommands;

  /// Forwarded to [BrushCanvasPanel]: stroke lifecycle (R13-3 warm hold).
  final ValueChanged<bool>? onStrokeInputActiveChanged;

  /// Forwarded to [BrushCanvasPanel]: selection-drag lifecycle (R15-⑤
  /// seek lock).
  final ValueChanged<bool>? onSelectionInteractionChanged;

  /// R26 #35: a paint attempt with NO editable cel under the playhead.
  /// The shell answers through the shared cursor notice ("no frame here"
  /// / "only the Action section can be drawn on") — the host cannot know
  /// WHICH refusal applies, so it only reports the attempt.
  final VoidCallback? onDrawRefused;

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
    final hasEditableFrame = _frameKeys.isNotEmpty && coordinator != null;
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

    final onDrawRefused = widget.onDrawRefused;
    // R26 #35: without an editable cel a paint press does nothing at all
    // — the passive Listener above the panel turns that silence into the
    // shared cursor notice. Translucent: it observes, never consumes, so
    // viewport navigation over the paper keeps working.
    //
    // ★ ALWAYS mounted; only the CALLBACK stands down. Wrapping it
    // conditionally moved the panel between two parents, and a [ValueKey]
    // holds identity only under the SAME parent — so every flip that
    // crossed "no cel ↔ cel" tore down `_BrushCanvasPanelState` and built
    // a fresh one. Mid-gesture that is worse than it sounds: the pointer
    // in flight keeps being delivered to the DISPOSED render object (a
    // "ValueNotifier used after being disposed" assertion per move, and
    // silence rather than an assert in release), while the gesture layer's
    // own `dispose` ends the flip HUD for the rest of the drag — the
    // window vanished the moment a flip landed on a block and never came
    // back until the finger lifted. A widget whose subtree carries live
    // gesture state must not change shape under it.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: hasEditableFrame || onDrawRefused == null
          ? null
          : (event) {
              if (event.buttons != 0 && (event.buttons & kPrimaryButton) == 0) {
                return;
              }
              final tool = widget.brushToolState.tool;
              if (!canvasToolPaints(tool) && tool != CanvasTool.fill) {
                return; // Eyedropper/selection/pan have their own meaning.
              }
              // R27 #15: only a press that would actually DRAW earns the
              // notice. A finger whose one-finger slot is flip/pan/none is
              // navigating, not drawing — telling it "no frame here" was
              // noise on every page flip.
              if (event.kind == PointerDeviceKind.touch &&
                  !AppInput.touchDraws) {
                return;
              }
              onDrawRefused();
            },
      child: _buildPanel(coordinator, hasEditableFrame, contentOverride),
    );
  }

  Widget _buildPanel(
    BrushFrameEditingCoordinator? coordinator,
    bool hasEditableFrame,
    Widget Function(BuildContext, CanvasViewport)? contentOverride,
  ) {
    return BrushCanvasPanel(
      key: const ValueKey<String>('main-canvas-brush-host'),
      // Zero unless this host is lying on the app's floor — which is a
      // question about WHERE it is mounted, so the tree answers it. A host
      // opened in a rail column or the bottom panel is simply not under the
      // provider, and nothing lies on it.
      floorCover: CanvasFloorInsets.maybeOf(context)?.insets ?? EdgeInsets.zero,
      floorRailBand: CanvasFloorInsets.maybeOf(context)?.rightRailBand,
      coordinator: coordinator,
      celEditable: hasEditableFrame,
      availableFrameKeys: _frameKeys,
      cacheInvalidationSink: _cacheInvalidationSink,
      canvasSize: widget.canvasSize,
      historyManager: widget.historyManager,
      viewport: widget.viewport,
      onViewportChanged: widget.onViewportChanged,
      brushToolState: widget.brushToolState,
      viewportOverlayBuilder: widget.viewportOverlayBuilder,
      viewportUnderlayBuilder: widget.viewportUnderlayBuilder,
      activeStrokeOverlayModel: widget.activeStrokeOverlayModel,
      interactiveContentOpacity: widget.interactiveContentOpacity,
      interactiveContentPose: widget.interactiveContentPose,
      contentOverride: contentOverride,
      fitFocusRect: widget.fitFocusRect,
      sampleColorAt: widget.sampleColorAt,
      paperColor: widget.paperColor,
      onPaperColorChanged: widget.onPaperColorChanged,
      pasteboardColor: widget.pasteboardColor,
      pasteboardMargin: widget.pasteboardMargin,
      onPasteboardColorChanged: widget.onPasteboardColorChanged,
      backdropArgb: widget.backdropArgb,
      onBackdropColorChanged: widget.onBackdropColorChanged,
      onTemporaryToolHold: widget.onTemporaryToolHold,
      onTemporaryToolRelease: widget.onTemporaryToolRelease,
      onInvokeAction: widget.onInvokeAction,
      onBrushSizeDragStart: widget.onBrushSizeDragStart,
      onBrushSizeDragUpdate: widget.onBrushSizeDragUpdate,
      onBrushSizeDragEnd: widget.onBrushSizeDragEnd,
      flipHud: widget.flipHud,
      onEyedropperPick: widget.onEyedropperPick,
      onAltColorPick: widget.onAltColorPick,
      fillDabAt: widget.fillDabAt,
      selectionMaskOptions: widget.selectionMaskOptions,
      transformResampleMode: widget.transformResampleMode,
      viewCommands: widget.viewCommands,
      selectionCommands: widget.selectionCommands,
      onStrokeInputActiveChanged: widget.onStrokeInputActiveChanged,
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
        image: null,
        canvasSize: widget.canvasSize,
        viewport: viewport,
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
      return;
    }
    final activeKey = widget.resolvedActiveFrameKey ?? _frameKeys.first;
    final coordinator = _coordinator;
    if (coordinator == null) {
      _coordinator = _createCoordinator(initialFrameKey: activeKey);
      return;
    }
    coordinator.selectFrame(activeKey);
  }

  BrushFrameEditingCoordinator _createCoordinator({
    required BrushFrameKey initialFrameKey,
  }) {
    return BrushFrameEditingCoordinator(
      initialFrameKey: initialFrameKey,
      frameStore: _frameStore,
      sessionStore: BrushFrameEditSessionStore(canvasSize: widget.canvasSize),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 24,
        deferredBakeRatio: 0,
      ),
    );
  }
}
