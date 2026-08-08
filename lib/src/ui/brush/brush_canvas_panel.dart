import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;

import '../../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../../services/brush_stroke_commit_data.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_frame_key.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_paint_clip.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/resample/resample_kernel.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/viewport_point.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/commands/brush_lift_move_history_command.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/history_manager.dart';
import '../canvas/bitmap_surface_painter.dart';
import '../canvas/active_stroke_overlay.dart';
import '../canvas/canvas_selection_layer.dart';
import '../canvas/selection_ants_painter.dart';
import '../canvas/canvas_viewport_gesture_layer.dart';
import '../canvas/flip_hud_controller.dart';
import '../canvas/flip_hud_overlay.dart';
import 'canvas_floor_insets.dart';
import '../../models/project.dart'
    show defaultProjectBackdropArgb, defaultProjectPasteboardMargin;
import '../../models/project_background.dart';
import '../canvas/paper_background.dart'
    show AlphaCheckerboardPainter, alphaPreviewEnabled;
import '../theme/app_theme.dart';
import '../theme/app_workspace_colors.dart';
import '../widgets/color_swatch_button.dart';
import 'brush_cursor_overlay.dart';
import '../../core/floor_math.dart';
import '../../models/tile_coord.dart';
import '../canvas/bitmap_tile_image_cache.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart';
import '../canvas/layer_pose_paint.dart';
import 'brush_canvas_defaults.dart';
import 'brush_tool_state.dart';
import '../dev_profile.dart';
import 'canvas_selection_commands.dart';
import 'selection_shape_history_command.dart';
import 'canvas_view_commands.dart';
import 'canvas_viewport_pan_metrics.dart';
import 'canvas_visible_rect.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/drag_value_label.dart';
import '../text/app_strings.dart';

/// A playback-follow reframe request for [BrushCanvasPanel.autoFrame]:
/// whenever [token] changes between widget updates the panel reframes the
/// viewport around [rect] (canvas space) — Fit-style when [panOnly] is
/// false (the timesheet's page turn), or a minimal zoom-preserving pan
/// that just brings [rect] into view when true (continuous-view scroll
/// following the playhead row).
class CanvasAutoFrameRequest {
  const CanvasAutoFrameRequest({
    required this.token,
    required this.rect,
    this.panOnly = false,
  });

  final Object token;
  final Rect rect;
  final bool panOnly;
}

/// Reusable Brush canvas panel for the production main-canvas brush route.
///
/// This widget is route-agnostic and behaves as an embedded canvas panel for
/// the main editor canvas area. Temporary debug controls are intentionally not
/// part of this panel.
/// Builds the layer content painted under (and, in merged mode, around)
/// the interactive canvas. [activeSurfacePainter] is non-null only in
/// merged mode: draw it where the ACTIVE layer belongs in the composite
/// tree, so a folder's group buffer can enclose it.
typedef CanvasUnderlayBuilder =
    Widget Function(
      BuildContext context,
      CanvasViewport viewport,
      BitmapSurfacePainter? activeSurfacePainter,
    );

class BrushCanvasPanel extends StatefulWidget {
  const BrushCanvasPanel({
    super.key,
    required this.coordinator,
    this.celEditable = true,
    required this.availableFrameKeys,
    required this.cacheInvalidationSink,
    this.canvasSize = BrushCanvasDefaults.canvasSize,
    this.brushToolState = BrushToolState.defaults,
    this.historyManager,
    this.viewport,
    this.onViewportChanged,
    this.viewportOverlayBuilder,
    this.viewportUnderlayBuilder,
    this.activeStrokeOverlayModel,
    this.interactiveContentOpacity = 1.0,
    this.interactiveContentPose,
    this.contentOverride,
    this.fitFocusRect,
    this.floorCover = EdgeInsets.zero,
    this.floorRailBand,
    this.autoFrame,
    this.contentStrokeActive,
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
    this.allowViewRotation = true,
    this.toolCursorsEnabled = true,
    this.bottomBarLeading = const <Widget>[],
    this.bottomBarLeadingToken,
  }) : assert(
         coordinator != null || contentOverride != null,
         'Without a coordinator the panel needs a content override.',
       );

  /// Null only when [contentOverride] supplies the viewport content — the
  /// project has no editing coordinator AT ALL yet (nothing has ever been
  /// drawn). Standing on an empty FRAME is a different fact: see
  /// [celEditable].
  final BrushFrameEditingCoordinator? coordinator;

  /// Whether the frame under the playhead can be drawn on.
  ///
  /// Split from [coordinator] deliberately. The two used to be one — the
  /// host handed over a null coordinator on an empty frame — which meant
  /// the interactive canvas was BUILT AND DESTROYED every time a flip
  /// crossed "no cel ↔ cel". Every pixel verb still refuses on an empty
  /// frame; it asks [_editableCoordinator] instead of this field, so the
  /// guards read exactly as they did.
  final bool celEditable;

  /// The coordinator for the verbs that EDIT PIXELS — null whenever this
  /// frame cannot be drawn on, which is the condition every one of those
  /// verbs was already written against. Only the interactive view itself
  /// reads [coordinator] directly, because it stays mounted either way.
  BrushFrameEditingCoordinator? get _editableCoordinator =>
      celEditable ? coordinator : null;

  final List<BrushFrameKey> availableFrameKeys;
  final CacheInvalidationSink cacheInvalidationSink;
  final CanvasSize canvasSize;
  final BrushToolState brushToolState;
  final HistoryManager? historyManager;
  final CanvasViewport? viewport;
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// The host's OWN controls, at the head of the pill: the timesheet's
  /// sheet-mode toggles and page navigation, the conte's, the envelope's.
  ///
  /// They used to be split between two places — a status strip across the
  /// top for the toggles and the bottom bar for the page cluster. Both
  /// places are gone (R2 #13); a panel has one pill and everything it
  /// offers is in it.
  final List<Widget> bottomBarLeading;

  /// Equality token for [bottomBarLeading] — the bottom bar is memoized by
  /// its inputs (R13-3) and widget instances are rebuilt per host build,
  /// so the host names what its leading controls actually DEPEND on. Null
  /// with a non-empty leading list means "rebuild the bar every time".
  final Object? bottomBarLeadingToken;

  /// Optional layer stacked over the canvas inside the editor viewport,
  /// receiving the live viewport so it can transform canvas coordinates
  /// (e.g. the camera frame overlay, layers above the active one).
  final Widget Function(BuildContext context, CanvasViewport viewport)?
  viewportOverlayBuilder;

  /// Optional layer painted UNDER the interactive canvas (layers below the
  /// active one + the paper). When present, the interactive view skips its
  /// own opaque background so the underlay shows through.
  ///
  /// In MERGED mode ([activeStrokeOverlayModel] non-null) this paints the
  /// WHOLE stack, active layer included: the builder receives the active
  /// layer's [BitmapSurfacePainter] so it can draw the live surface at the
  /// right place in its composite tree.
  final CanvasUnderlayBuilder? viewportUnderlayBuilder;

  /// MERGED canvas mode: the host owns the live-stroke overlay and paints
  /// the active layer itself, inside its composite tree, so a folder's
  /// group buffer can enclose the layer being drawn on. The interactive
  /// view then runs input-only. Null keeps the classic split (the view
  /// owns its overlay and paints itself between the two stacks).
  final ActiveStrokeOverlayModel? activeStrokeOverlayModel;

  /// The active layer's painter for [viewportUnderlayBuilder] in merged
  /// mode — built here because the surface lives on the coordinator.
  BitmapSurfacePainter? _activeSurfacePainterFor(
    BrushFrameEditingCoordinator coordinator,
  ) {
    final overlay = activeStrokeOverlayModel;
    if (overlay == null) {
      return null;
    }
    final activeKey = coordinator.activeFrameKey;
    return BitmapSurfacePainter(
      surface: coordinator.activeSessionState.canvasState.currentSurface,
      overlayModel: overlay,
      // The stack painter applies the viewport itself, so the surface
      // painter draws in canvas space.
      showTransparentBackground: false,
      staleScope: (activeKey.layerId, activeKey.frameId),
    );
  }

  /// Display opacity of the interactive layer itself (the active layer's
  /// visibility/opacity preview); strokes still commit at full strength.
  final double interactiveContentOpacity;

  /// The active layer's geometric transform at the playhead (null =
  /// identity). The interactive view wraps in the pose's screen matrix so
  /// the layer shows POSED exactly like every composite route, while hit
  /// testing inverse-maps pointers — strokes record in original artwork
  /// coordinates (draw-through). Brush sizes are artwork-space: the live
  /// stroke and the committed composite stay pixel-identical.
  final LayerPoseSample? interactiveContentPose;

  /// Replaces the interactive canvas INSIDE the panel shell (title, zoom
  /// toolbar and panbars keep working) — playback and the blank-canvas
  /// placeholder render through this. Receives the live viewport.
  final Widget Function(BuildContext context, CanvasViewport viewport)?
  contentOverride;

  /// Canvas-space rectangle the Fit button frames instead of the whole
  /// canvas (e.g. the camera frame's bounds while the camera layer is
  /// active). Null keeps Fit on the canvas itself.
  final Rect? fitFocusRect;

  /// The edges of this panel's box that other panels are lying on.
  ///
  /// This is the concrete form of the split [canvasVisibleRect] describes —
  /// which parts of the box are covered, and therefore are not part of the
  /// window the artist looks through. Zero for a panel nothing is covering,
  /// which is every canvas surface but the floor.
  ///
  /// The PANELS only. This panel's own controls are capsules that float on
  /// the drawing rather than bands that reserve their thickness, so they do
  /// not deflate the window the way a panel does — Fit frames the artwork
  /// behind them, and a capsule that hides a corner of it is the price of
  /// not spending a strip of the screen on chrome that is idle most of the
  /// time.
  final EdgeInsets floorCover;

  /// WHERE the rail on this panel's right edge actually is, vertically —
  /// null when nothing is open there.
  ///
  /// [floorCover] says how much of the edge is unusable, which is the right
  /// question for FRAMING and the wrong one for the one control that lives
  /// on that edge: a short rail panel covers a band, and a scrollbar that
  /// steps aside for a panel nowhere near it reads as floating (유저, R3
  /// #5).
  final CanvasFloorBand? floorRailBand;

  /// Playback-follow reframing: when the request's token changes between
  /// updates the panel reframes onto its rect (see
  /// [CanvasAutoFrameRequest]). Null never reframes — the user owns the
  /// viewport.
  final CanvasAutoFrameRequest? autoFrame;

  /// Raised by contentOverride content that hosts its OWN brush input (the
  /// timesheet ink layer): while true, the panel's gesture layer holds
  /// navigation exactly as it does for the panel's own strokes.
  final ValueListenable<bool>? contentStrokeActive;

  /// Samples the VISIBLE composite color at a canvas point (P5); null
  /// disables the eyedropper tool and Alt-picks.
  final int? Function(CanvasPoint point)? sampleColorAt;

  /// R28 #9: the surface colors and their commit handlers. The paper is
  /// the PROJECT's (it goes out in exports); the pasteboard is the working
  /// environment around the stage. Null handlers hide the respective
  /// swatch.
  ///
  /// The paper stays a parameter because it belongs to the CUT on screen —
  /// a sheet panel and the drawing floor may legitimately differ. The two
  /// below describe the ROOM instead, and there is only one room.
  final int paperColor;
  final ValueChanged<int>? onPaperColorChanged;

  /// null = take it from [CanvasStageColors], which is what every panel
  /// inside the workspace does (유저, R4 #2). Pass a value only to mount
  /// this panel outside the shell — the dev fixtures and most tests.
  ///
  /// ⚠️It used to be a non-null parameter with a constant default, and the
  /// default is exactly what four of the five hosts silently got.
  final int? pasteboardColor;
  final ValueChanged<int>? onPasteboardColorChanged;

  /// How far past each canvas edge the pasteboard SHOWS, in canvas widths
  /// and heights ([Project.pasteboardMargin]). null = from the scope.
  final double? pasteboardMargin;

  /// The BACKDROP behind the pasteboard (R3b): the stage's opaque floor,
  /// or the alpha checkerboard while the preview toggle is on. It is what
  /// lies BEYOND the pasteboard now, not merely under it. null = from the
  /// scope.
  final int? backdropArgb;

  /// 캔버스 색 바꾸는곳 제일오른쪽에 배경색 바꾸는 버튼도 (유저, R3 #4). The
  /// pill carried the paper and the pasteboard and stopped there, which
  /// left the third plane of the same stage reachable only from a dialog.
  /// Null hides the swatch, like the other two.
  final ValueChanged<int>? onBackdropColorChanged;

  /// A committed eyedropper pick (switches back to the painting tool).
  final ValueChanged<int>? onEyedropperPick;

  /// An Alt+click TEMPORARY pick while painting: color only, the active
  /// tool stays (the CSP muscle-memory shortcut).
  final ValueChanged<int>? onAltColorPick;

  /// PEN-7a: the mapped-hold tool switch (canvas right/wheel-click
  /// mappings) — threaded through to the workspace's tool notifier.
  final void Function(CanvasTool tool)? onTemporaryToolHold;
  final void Function({required bool keep})? onTemporaryToolRelease;

  /// PEN-7b: control-mode touch slots — the flip action funnel and the
  /// brush-size drag protocol.
  final void Function(String actionId)? onInvokeAction;
  final VoidCallback? onBrushSizeDragStart;
  final void Function(double upwardDelta, {required bool snap})?
  onBrushSizeDragUpdate;
  final VoidCallback? onBrushSizeDragEnd;

  /// The flip HUD's state, when the host shows one. The panel mounts the
  /// overlay above the gesture layer so the window lands in the same
  /// coordinates the gesture reports its anchor in.
  final FlipHudController? flipHud;

  /// Builds the fill-region dab for a tap (P6); the panel commits it
  /// through the exact stroke funnel. Null disables the fill tool.
  final BrushDab? Function(CanvasPoint point, int color)? fillDabAt;

  /// R26 (C2): the Select tool's lift-time mask knobs — read at lift.
  /// Null/absent keeps the classic byte-preserving hard mask.
  final ValueListenable<SelectionMaskOptions>? selectionMaskOptions;

  /// P3a: which resampler a Ctrl+T commit runs through. Null keeps the
  /// smoothing default, which is what focused tests want.
  final ValueListenable<ResampleMode>? transformResampleMode;

  /// The app-level rotate/flip shortcut channel (P8); the panel binds its
  /// viewport-center handlers while mounted.
  final CanvasViewCommands? viewCommands;

  /// The app-level selection channel (P9: Ctrl+D, arrow nudges), bound by
  /// the selection layer while a selection tool is active.
  final CanvasSelectionCommands? selectionCommands;

  /// Stroke lifecycle for the host (R13-3): true at pen-down, false at
  /// stroke end/cancel — the session holds prerender warming while a
  /// stroke is live.
  final ValueChanged<bool>? onStrokeInputActiveChanged;

  /// Selection-drag lifecycle for the host (R15-⑤): the session blocks
  /// frame seeks/cut switches while a selection interaction is live.
  final ValueChanged<bool>? onSelectionInteractionChanged;

  /// False hides the rotate/flip toolbar controls and disables the
  /// rotation gestures — for hosts whose content layers speak zoom/pan
  /// only (the timesheet's ink and header-edit overlays).
  final bool allowViewRotation;

  /// False suppresses the tool cursors (brush tip outline, fill icon) —
  /// for strictly read-only hosts (the media viewer), where a paint
  /// cursor over undrawable content is a false affordance.
  final bool toolCursorsEnabled;

  @override
  State<BrushCanvasPanel> createState() => _BrushCanvasPanelState();
}

/// The stand-in when no host owns the resample mode (focused tests). Const
/// in spirit — nothing ever writes it, so one instance for the process is
/// correct and it is never disposed.
final ValueNotifier<ResampleMode> _defaultResampleMode = ValueNotifier(
  ResampleMode.blend,
);

class _BrushCanvasPanelState extends State<BrushCanvasPanel>
    with SingleTickerProviderStateMixin {
  late CanvasViewport _viewport = widget.viewport ?? CanvasViewport();
  CanvasViewport? _lastWidgetViewport;
  Size? _editorViewportSize;

  /// True while a brush stroke is in progress; the viewport gesture layer
  /// ignores wheel zooms and new pans so they cannot disturb the stroke.
  bool _strokeActive = false;

  /// True while a selection marquee/move drag is in progress (P9) — holds
  /// viewport gestures exactly like a stroke.
  bool _selectionDragActive = false;

  CanvasAutoFrameRequest? _pendingAutoFrame;

  /// True while Alt is held — the temporary eyedropper (R11-②): the cursor
  /// and hover swatch arm without switching tools.
  bool _altHeld = false;

  /// The pointer's viewport position + the composite color under it while
  /// the eyedropper cursor is armed; drives the hover swatch only.
  final ValueNotifier<({Offset position, int color})?> _eyedropperHover =
      ValueNotifier<({Offset position, int color})?>(null);

  /// R26 #23: the pointer position for tool cursors that draw an ICON but
  /// sample nothing (the fill bucket).
  final ValueNotifier<Offset?> _toolCursorHover = ValueNotifier<Offset?>(null);

  /// R28-S: the dash phase for the ants the panel paints when NO selection
  /// layer is mounted — the region belongs to the document, so it keeps
  /// showing while the brush/eraser/fill is armed (R26 #18).
  late final AnimationController _idleAnts = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  /// The stage's outer surfaces, RESOLVED: this panel's own parameters when
  /// it was given them, otherwise the shell's [CanvasStageColors].
  ///
  /// Resolved into fields rather than read at each use, because the reads
  /// happen inside memo builders called from `build` and one of them
  /// (`didUpdateWidget`) runs outside it — a scope lookup wants a lifecycle
  /// hook, not an arbitrary call site.
  late int _stageBackdropArgb;
  late int _stagePasteboardArgb;
  late double _stagePasteboardMargin;

  void _readStageColors() {
    final scope = CanvasStageColors.maybeOf(context);
    _stageBackdropArgb =
        widget.backdropArgb ??
        scope?.backdropArgb ??
        defaultProjectBackdropArgb;
    _stagePasteboardArgb =
        widget.pasteboardColor ??
        scope?.pasteboardArgb ??
        AppWorkspaceColors.defaultPasteboardArgb;
    _stagePasteboardMargin =
        widget.pasteboardMargin ??
        scope?.pasteboardMargin ??
        defaultProjectPasteboardMargin;
  }

  @override
  void initState() {
    super.initState();
    _bindViewCommands();
    _altHeld = HardwareKeyboard.instance.isAltPressed;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    widget.selectionCommands?.addListener(_handleSelectionChannelChanged);
    _bindSelectionHistoryRecorder();
    _syncIdleAnts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readStageColors();
  }

  /// One undoable selection step (R11-⑧) — the layer's marquee commits and
  /// the channel's layer-less Ctrl+D both land here, so a selection change
  /// is recorded the same way whatever tool is armed. Null while this
  /// panel has no history host (focused tests apply directly).
  void Function(CanvasSelectionRegion? before, CanvasSelectionRegion? after)?
  get _recordSelectionChange {
    final history = widget.historyManager;
    final commands = widget.selectionCommands;
    if (history == null || commands == null) {
      return null;
    }
    return (before, after) => history.execute(
      SelectionShapeHistoryCommand(
        channel: commands,
        before: before,
        after: after,
      ),
    );
  }

  void _bindSelectionHistoryRecorder() {
    widget.selectionCommands?.regionHistoryRecorder = _recordSelectionChange;
  }

  /// The region this panel last painted ants for — the rebuild guard.
  CanvasSelectionRegion? _paintedIdleRegion;

  void _handleSelectionChannelChanged() {
    if (!mounted) {
      return;
    }
    // The channel pings on EVERY selection mutation, including each step
    // of a marquee/move drag. Those all happen with a selection tool
    // armed, where the mounted layer draws and this panel has nothing to
    // redraw — so the guard keeps the notify structure (R27 #7/#20) out
    // of the drag loop and only rebuilds when the ants this panel owns
    // actually change.
    final next = _idleSelectionRegion;
    if (next == _paintedIdleRegion) {
      return;
    }
    setState(_syncIdleAnts);
  }

  /// The idle ants animate only when they are the ones on screen: the
  /// mounted selection layer runs its own ticker.
  void _syncIdleAnts() {
    _paintedIdleRegion = _idleSelectionRegion;
    final show = _paintedIdleRegion != null;
    if (show && !_idleAnts.isAnimating) {
      _idleAnts.repeat();
    } else if (!show && _idleAnts.isAnimating) {
      _idleAnts.stop();
    }
  }

  /// The region to paint when no selection layer is mounted (null while
  /// one is — it draws its own, session state included).
  CanvasSelectionRegion? get _idleSelectionRegion {
    if (canvasToolSelects(widget.brushToolState.tool)) {
      return null;
    }
    return widget.selectionCommands?.region;
  }

  @override
  void dispose() {
    // A mid-stroke teardown must release the session's warm hold — a
    // leaked hold would gate prerendering forever. Same for a mid-drag
    // selection interaction (R15-⑤: a leaked hold would block seeks).
    if (_strokeActive) {
      widget.onStrokeInputActiveChanged?.call(false);
    }
    if (_selectionDragActive) {
      widget.onSelectionInteractionChanged?.call(false);
    }
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    widget.selectionCommands?.removeListener(_handleSelectionChannelChanged);
    widget.selectionCommands?.regionHistoryRecorder = null;
    _idleAnts.dispose();
    _eyedropperHover.dispose();
    _toolCursorHover.dispose();
    widget.viewCommands?.unbind();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    final alt = HardwareKeyboard.instance.isAltPressed;
    if (alt != _altHeld && mounted) {
      setState(() => _altHeld = alt);
      if (!alt) {
        _eyedropperHover.value = null;
      }
    }
    return false;
  }

  /// R26 #23: the fill tool's own cursor icon (no sampling involved).
  bool get _fillCursorActive =>
      widget.toolCursorsEnabled &&
      widget.brushToolState.tool == CanvasTool.fill &&
      !_eyedropperCursorActive;

  /// The brush/eraser tip outline. Alt-held sampling takes the pointer over
  /// (the eyedropper is what the user is aiming with at that moment), and
  /// the selection tools own it outright.
  bool get _brushCursorActive =>
      widget.toolCursorsEnabled &&
      canvasToolPaints(widget.brushToolState.tool) &&
      !_eyedropperCursorActive;

  /// Whether the eyedropper cursor + hover swatch are armed: the tool
  /// itself, or Alt held over a painting tool (the temporary pick).
  bool get _eyedropperCursorActive {
    if (widget.sampleColorAt == null) {
      return false;
    }
    final tool = widget.brushToolState.tool;
    if (tool == CanvasTool.eyedropper) {
      return widget.onEyedropperPick != null;
    }
    return _altHeld && canvasToolPaints(tool) && widget.onAltColorPick != null;
  }

  /// R27 #17: the last pointer position seen on the canvas — hovers AND
  /// button-held moves alike.
  ///
  /// The eyedropper's icon and swatch only appeared once a fresh hover
  /// event reached their tracker. Entering the tool from a HELD button
  /// (the pen's barrel / right-click mapping) captures the pointer at the
  /// press, so no hover ever arrives — leaving the system cursor hidden
  /// (the tracker's `MouseCursor.none` is mounted regardless) and nothing
  /// drawn in its place: the "커서가 사라짐" report. Seeding from here on
  /// the first frame the cursor arms gives the icon somewhere to be.
  Offset? _lastCanvasPointer;

  /// Guards the seeding to once per arming.
  bool _eyedropperHoverSeeded = false;

  /// [sample] false on pointer DOWN: the tap layer's pick samples that
  /// same press, and sampling here too would double the composite read.
  /// Forgets where the pointer was, because it is no longer on the canvas.
  ///
  /// Without this the seeding below would draw a tool cursor at the last
  /// place the pointer WAS, after it had left.
  void _forgetCanvasPointer() {
    _lastCanvasPointer = null;
    _toolCursorHover.value = null;
    _eyedropperHover.value = null;
  }

  void _noteCanvasPointer(Offset localPosition, {bool sample = true}) {
    _lastCanvasPointer = localPosition;
    // The brush outline rides the same census — including the moves of a
    // stroke already in flight, which is most of what it has to follow.
    if (_brushCursorActive) {
      _toolCursorHover.value = localPosition;
    }
    if (!sample) {
      return;
    }
    // R28 #8: the ALWAYS-MOUNTED census drives the eyedropper cursor too.
    //
    // The cursor's own tracker mounts at the moment the tool arms, and
    // Flutter routes an in-flight pointer to the handlers captured at
    // pointer DOWN — so under a mapped HOLD (the pen barrel / right-click
    // switching to the eyedropper mid-press) that tracker never receives a
    // single move. R27 #17 seeded a starting position, which is why the
    // icon then sat wherever the seed put it and refused to follow: "커서가
    // 이상한데로 이동하고 안움직임". This layer was mounted before the press,
    // so it is in the route and keeps reporting.
    if (_eyedropperCursorActive) {
      _sampleEyedropperHover(localPosition);
    }
  }

  /// 🐛유저, R3 #8: 선택툴 누르고 필이나 지우개나 다른툴누르면 커서가 사라짐.
  ///
  /// A tool cursor hides the system one and draws itself at the last
  /// position the census reported — and the census only reports on real
  /// pointer EVENTS. Arming a cursor while the pointer sits still (which is
  /// exactly what pressing a tool button does) therefore hid the system
  /// cursor and drew nothing in its place, until the hand moved. Flutter
  /// synthesises enter/exit for a freshly mounted region but never a hover,
  /// so there is nothing to wait for: the position we already know IS the
  /// answer.
  void _seedToolCursorIfNeeded() {
    if (!_brushCursorActive && !_fillCursorActive) {
      return;
    }
    if (_toolCursorHover.value != null) {
      return;
    }
    _toolCursorHover.value = _lastCanvasPointer;
  }

  void _seedEyedropperHoverIfNeeded() {
    if (!_eyedropperCursorActive) {
      _eyedropperHoverSeeded = false;
      return;
    }
    if (_eyedropperHoverSeeded || _eyedropperHover.value != null) {
      return;
    }
    final position = _lastCanvasPointer;
    if (position == null) {
      return;
    }
    _eyedropperHoverSeeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _eyedropperCursorActive &&
          _eyedropperHover.value == null) {
        _sampleEyedropperHover(position);
      }
    });
  }

  void _sampleEyedropperHover(Offset localPosition) {
    final sample = widget.sampleColorAt;
    if (sample == null) {
      return;
    }
    final color = sample(
      _viewport.viewportToCanvas(
        ViewportPoint(x: localPosition.dx, y: localPosition.dy),
      ),
    );
    _eyedropperHover.value = color == null
        ? null
        : (position: localPosition, color: color);
  }

  void _bindViewCommands() {
    widget.viewCommands?.bind(
      rotateBy: _rotateAroundCenter,
      toggleFlipHorizontal: _toggleFlipHorizontal,
      toggleFlipVertical: _toggleFlipVertical,
      resetRotation: _resetRotation,
    );
  }

  @override
  void didUpdateWidget(covariant BrushCanvasPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A host that passes its own colours can change them without the scope
    // moving; `didChangeDependencies` alone would never hear that.
    if (oldWidget.backdropArgb != widget.backdropArgb ||
        oldWidget.pasteboardColor != widget.pasteboardColor ||
        oldWidget.pasteboardMargin != widget.pasteboardMargin) {
      _readStageColors();
    }
    if (!identical(oldWidget.viewCommands, widget.viewCommands)) {
      oldWidget.viewCommands?.unbind();
      _bindViewCommands();
    }
    if (!identical(oldWidget.selectionCommands, widget.selectionCommands)) {
      oldWidget.selectionCommands?.removeListener(
        _handleSelectionChannelChanged,
      );
      widget.selectionCommands?.addListener(_handleSelectionChannelChanged);
    }
    _bindSelectionHistoryRecorder();
    _syncIdleAnts();
    final request = widget.autoFrame;
    if (request == null || request.token == oldWidget.autoFrame?.token) {
      return;
    }
    // didUpdateWidget runs during the build phase — reframing notifies the
    // viewport's parent owner, so it must wait for the frame to end.
    final alreadyScheduled = _pendingAutoFrame != null;
    _pendingAutoFrame = request;
    if (alreadyScheduled) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = _pendingAutoFrame;
      _pendingAutoFrame = null;
      if (mounted && pending != null) {
        _autoFrame(pending);
      }
    });
  }

  void _autoFrame(CanvasAutoFrameRequest request) {
    final visible = _resolvedVisibleRect();
    final next = request.panOnly
        ? _viewportRevealing(request.rect, visible)
        : _fittedInto(visible, canvasRect: request.rect);
    if (next == _viewport) {
      return;
    }
    _setViewport(next);
  }

  /// Fits [canvasRect] into [visible], which is expressed in LAYOUT
  /// coordinates: the fit is computed in the window's own frame and then slid
  /// back, because pan is measured from the layout box's top-left. Fitting
  /// against the box instead would centre the artwork on the box and drop its
  /// lower edge under whatever floats there.
  CanvasViewport _fittedInto(Rect visible, {required Rect canvasRect}) {
    final fitted = CanvasViewport.fitToCanvasRect(
      left: canvasRect.left,
      top: canvasRect.top,
      width: canvasRect.width,
      height: canvasRect.height,
      viewportWidth: visible.width,
      viewportHeight: visible.height,
    );
    return fitted.copyWith(
      panX: fitted.panX + visible.left,
      panY: fitted.panY + visible.top,
    );
  }

  /// The minimal zoom-preserving pan that brings [rect] (canvas space)
  /// into the viewport with a small margin; when the rect cannot fully
  /// fit, its top-left edge wins. Under rotation/flip the rect's mapped
  /// AABB is what must land inside.
  CanvasViewport _viewportRevealing(Rect rect, Rect visible) {
    const margin = 24.0;
    var panX = _viewport.panX;
    var panY = _viewport.panY;
    final unpanned = _viewport.copyWith(panX: 0, panY: 0);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]) {
      final mapped = unpanned.canvasToViewport(
        CanvasPoint(x: corner.dx, y: corner.dy),
      );
      minX = math.min(minX, mapped.x);
      maxX = math.max(maxX, mapped.x);
      minY = math.min(minY, mapped.y);
      maxY = math.max(maxY, mapped.y);
    }
    // Reveal into the window, not into the box: the 24px breathing room is
    // worthless if it is measured against an edge that is covered.
    if (maxY + panY > visible.bottom - margin) {
      panY = visible.bottom - margin - maxY;
    }
    if (minY + panY < visible.top + margin) {
      panY = visible.top + margin - minY;
    }
    if (maxX + panX > visible.right - margin) {
      panX = visible.right - margin - maxX;
    }
    if (minX + panX < visible.left + margin) {
      panX = visible.left + margin - minX;
    }
    return _viewport.copyWith(panX: panX, panY: panY);
  }

  /// R13-3 shell memo: the panbars/zoom-rotate bar are a Material button
  /// forest that used to reconstruct on EVERY panel rebuild (each committed
  /// seek, tool switch, drag-preview notify). Their inputs are only the
  /// viewport geometry — memo by token, reuse the identical instances so
  /// the element tree prunes the whole subtree.
  /// ★TWO tokens, not one (유저, R3 #14: 프로그램 창 자체를 크기 조절하면 뭔가
  /// 느린데). The panbars are geometry and DO depend on the viewport's size;
  /// the pill does not read it at all. Sharing one token meant every frame
  /// of a window resize rebuilt the pill — thirteen icon buttons with their
  /// tooltips, overlay portals and gesture detectors — for a number it
  /// ignores.
  ({CanvasViewport viewport, Size viewportSize, CanvasSize canvasSize})?
  _panbarsToken;
  ({
    CanvasViewport viewport,
    CanvasSize canvasSize,
    bool rotation,
    int paper,
    int pasteboard,
    int backdrop,
    Object? leading,
  })?
  _pillToken;
  Widget? _memoRightStripBar;
  Widget? _memoHorizontalStripBar;
  Widget? _memoBottomBar;

  void _ensureShellBars() {
    final viewportSize = _resolvedEditorViewportSize();
    final panbarsToken = (
      viewport: _viewport,
      viewportSize: viewportSize,
      canvasSize: widget.canvasSize,
    );
    final pillToken = (
      viewport: _viewport,
      canvasSize: widget.canvasSize,
      rotation: widget.allowViewRotation,
      // The swatches the pill CARRIES. They were missing, so the pill
      // went on painting yesterday's paper colour until an unrelated pan or
      // resize happened to invalidate the memo — and tapping the swatch
      // opened the picker seeded with the stale value. The rule for this
      // token is the same in both directions: everything the pill SHOWS is
      // in it, and nothing it does not.
      paper: widget.paperColor,
      pasteboard: _stagePasteboardArgb,
      backdrop: _stageBackdropArgb,
      leading: widget.bottomBarLeadingToken,
      // ⛔ The panel TITLE is deliberately absent — and now unreachable, so
      // it cannot come back by accident (R2 #12 took the readout off every
      // canvas panel). Keeping the history because the shape of the bug is
      // worth recognising elsewhere: none of these bars showed the title,
      // but it sat in this token and read
      // "Project: … · Cut: … · Layer: … · Frame: <label>", so every step
      // that changed the frame label threw the memo away and rebuilt the
      // whole bar — 13 icon buttons with their tooltips, overlay portals,
      // ink and gesture detectors. Measured at 391 widget rebuilds a step,
      // against 24 for the panel's own spine.
      //
      // ⚠️ The dev fixture UNDERSTATES it. Two unnamed cels share a frame
      // label, so it only bit when the playhead crossed "no cel ↔ cel";
      // in a real cut every cel is named, and the label — so the bar —
      // changed on EVERY flip step.
    );
    // A leading list without a token can't be memoized (see
    // [bottomBarLeadingToken]) — rebuild rather than serve a stale bar.
    final memoizable =
        widget.bottomBarLeading.isEmpty || widget.bottomBarLeadingToken != null;
    if (panbarsToken != _panbarsToken || _memoRightStripBar == null) {
      _panbarsToken = panbarsToken;
      _memoRightStripBar = CanvasViewportVerticalScrollbar(
        viewport: _viewport,
        editorViewportSize: viewportSize,
        canvasSize: widget.canvasSize,
        onViewportChanged: _setViewportDuringPanbarDrag,
        onViewportChangeEnd: _syncViewportParent,
      );
      _memoHorizontalStripBar = CanvasViewportHorizontalScrollbar(
        viewport: _viewport,
        editorViewportSize: viewportSize,
        canvasSize: widget.canvasSize,
        onViewportChanged: _setViewportDuringPanbarDrag,
        onViewportChangeEnd: _syncViewportParent,
      );
    }
    if (memoizable && pillToken == _pillToken && _memoBottomBar != null) {
      return;
    }
    _pillToken = pillToken;
    _memoBottomBar = _CanvasViewportBottomBar(
      leading: widget.bottomBarLeading,
      viewport: _viewport,
      canvasSize: widget.canvasSize,
      paperColor: widget.paperColor,
      onPaperColorChanged: widget.onPaperColorChanged,
      pasteboardColor: _stagePasteboardArgb,
      onPasteboardColorChanged: widget.onPasteboardColorChanged,
      backdropColor: _stageBackdropArgb,
      onBackdropColorChanged: widget.onBackdropColorChanged,
      onViewportChanged: _setViewportDuringPanbarDrag,
      onViewportChangeEnd: _syncViewportParent,
      onZoomIn: _zoomInFromBar,
      onZoomOut: _zoomOutFromBar,
      onZoomSet: _setZoomFromLabel,
      onFit: _fitToView,
      onReset: _resetView,
      onRotateCcw: widget.allowViewRotation ? _rotateCcwFromBar : null,
      onRotateCw: widget.allowViewRotation ? _rotateCwFromBar : null,
      onRotateReset: widget.allowViewRotation ? _resetRotation : null,
      onRotateByDrag: widget.allowViewRotation ? _rotateByDrag : null,
      onFlipHorizontal: widget.allowViewRotation ? _toggleFlipHorizontal : null,
      onFlipVertical: widget.allowViewRotation ? _toggleFlipVertical : null,
    );
  }

  Widget _memoizedRightStripBar() {
    _ensureShellBars();
    return _memoRightStripBar!;
  }

  Widget _memoizedHorizontalStripBar() {
    _ensureShellBars();
    return _memoHorizontalStripBar!;
  }

  Widget _memoizedBottomBar() {
    _ensureShellBars();
    return _memoBottomBar!;
  }

  // Named handlers (not closures) so the memoized bars capture stable
  // callbacks — a fresh closure per build would defeat nothing here, but
  // stale-capture bugs are impossible with tear-offs.
  void _zoomInFromBar() => _zoomAroundCenter(1.25);
  void _zoomOutFromBar() => _zoomAroundCenter(0.8);
  void _rotateCcwFromBar() => _rotateAroundCenter(-15);
  void _rotateCwFromBar() => _rotateAroundCenter(15);

  @override
  Widget build(BuildContext context) {
    if (widget.viewport != null && widget.viewport != _lastWidgetViewport) {
      _viewport = widget.viewport!;
      _lastWidgetViewport = widget.viewport;
    }
    // R27 #17: a cursor that armed mid-gesture gets a starting position.
    _seedEyedropperHoverIfNeeded();
    _seedToolCursorIfNeeded();

    return Padding(
      key: const ValueKey<String>('brush-canvas-panel'),
      // Zero: panels sit flush against the dock and the timeline (the
      // shell draws its own chrome).
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fallbackSize = Size(
            widget.canvasSize.width.toDouble(),
            widget.canvasSize.height.toDouble(),
          );
          final boundedWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : fallbackSize.width;
          final boundedHeight = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : fallbackSize.height + _CanvasViewportBottomBar.height;

          return SizedBox(
            width: boundedWidth,
            height: boundedHeight,
            child: _CanvasEditorPanelShell(
              rightStripBar: _memoizedRightStripBar(),
              horizontalStripBar: _memoizedHorizontalStripBar(),
              bottomBar: _memoizedBottomBar(),
              // The capsules float INSIDE what the panels left over.
              cover: widget.floorCover,
              railBand: widget.floorRailBand,
              strokeActive: _strokeActive || _selectionDragActive,
              contentStrokeActive: widget.contentStrokeActive,
              child: LayoutBuilder(
                builder: (context, viewportConstraints) {
                  final viewportSize = Size(
                    viewportConstraints.maxWidth,
                    viewportConstraints.maxHeight,
                  );
                  _rememberEditorViewportSize(viewportSize);

                  final canvasView = _buildViewportContent(context);
                  final overlayBuilder = widget.viewportOverlayBuilder;
                  final underlayBuilder = widget.viewportUnderlayBuilder;
                  final contentStrokeActive = widget.contentStrokeActive;

                  // R26 #15: selection works with NO frame under the
                  // playhead too — the region is view state, and every
                  // pixel op (lift/fill/draw-inside) already guards the
                  // missing coordinator itself.
                  final selectionLayerActive = canvasToolSelects(
                    widget.brushToolState.tool,
                  );
                  // R28-S: with a painting tool armed the panel paints the
                  // committed region's ants itself (the interaction layer
                  // is not mounted, but the selection still exists).
                  final idleSelection = _idleSelectionRegion;

                  Widget gestureLayer(bool contentStrokeIsActive) {
                    final hud = widget.flipHud;
                    final layer = CanvasViewportGestureLayer(
                      viewport: _viewport,
                      onViewportChanged: _setViewport,
                      rotationEnabled: widget.allowViewRotation,
                      flipHud: hud,
                      // PEN-7b: the control-mode touch slots — flip
                      // dispatches shell actions, brush size drives the
                      // tool state (both threaded from the workspace).
                      onInvokeAction: widget.onInvokeAction,
                      onBrushSizeDragStart: widget.onBrushSizeDragStart,
                      onBrushSizeDragUpdate: widget.onBrushSizeDragUpdate,
                      onBrushSizeDragEnd: widget.onBrushSizeDragEnd,
                      strokeActive:
                          _strokeActive ||
                          _selectionDragActive ||
                          contentStrokeIsActive,
                      // Nothing drawn in the viewport (canvas, playback
                      // frames, camera overlay) may paint outside the panel.
                      child: ClipRect(
                        // The stage's outer planes (R3b): the BACKDROP
                        // fills the panel and the PASTEBOARD lies on it
                        // where the pasteboard actually is, RGBA and
                        // project data (R28 #9 reversed) — thinning it
                        // reveals the floor, on screen exactly as in an
                        // export. The alpha-preview toggle swaps BOTH for
                        // the checkerboard: an alpha export excludes them,
                        // so the preview must too.
                        child: _StagePlanes(
                          backdropArgb: _stageBackdropArgb,
                          pasteboardArgb: _stagePasteboardArgb,
                          pasteboardMargin: _stagePasteboardMargin,
                          canvasSize: widget.canvasSize,
                          viewport: _viewport,
                          // R27 #17: a passive census of where the pointer
                          // is — button-held moves included — so a cursor
                          // that arms mid-gesture knows where to appear.
                          // Translucent and handler-only: it consumes
                          // nothing.
                          child: MouseRegion(
                            // The census's other half: WHEN THE POINTER
                            // LEAVES. Everything below only ever learns
                            // where the pointer is; without an exit the
                            // last position stayed authoritative for ever,
                            // and a tool cursor armed afterwards would draw
                            // itself where the hand used to be.
                            opaque: false,
                            hitTestBehavior: HitTestBehavior.translucent,
                            onExit: (_) => _forgetCanvasPointer(),
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerHover: (event) =>
                                  _noteCanvasPointer(event.localPosition),
                              onPointerDown: (event) => _noteCanvasPointer(
                                event.localPosition,
                                sample: false,
                              ),
                              onPointerMove: (event) =>
                                  _noteCanvasPointer(event.localPosition),
                              child:
                                  overlayBuilder == null &&
                                      underlayBuilder == null &&
                                      _toolTapHandler() == null &&
                                      !selectionLayerActive &&
                                      idleSelection == null &&
                                      !_eyedropperCursorActive &&
                                      !_brushCursorActive
                                  ? canvasView
                                  : Stack(
                                      children: [
                                        if (underlayBuilder != null)
                                          Positioned.fill(
                                            child: underlayBuilder(
                                              context,
                                              _viewport,
                                              widget._editableCoordinator ==
                                                      null
                                                  ? null
                                                  : widget._activeSurfacePainterFor(
                                                      widget
                                                          ._editableCoordinator!,
                                                    ),
                                            ),
                                          ),
                                        Positioned.fill(child: canvasView),
                                        if (overlayBuilder != null)
                                          Positioned.fill(
                                            child: overlayBuilder(
                                              context,
                                              _viewport,
                                            ),
                                          ),
                                        // Non-painting tools (P5 eyedropper / P6
                                        // fill): one tap layer ABOVE the canvas
                                        // absorbs the pointer so no stroke starts.
                                        if (_toolTapHandler() != null)
                                          Positioned.fill(
                                            child: Listener(
                                              key: const ValueKey<String>(
                                                'canvas-tool-tap-layer',
                                              ),
                                              behavior: HitTestBehavior.opaque,
                                              onPointerDown: (event) {
                                                // PRIMARY contact only (R22-B):
                                                // the middle-button pan (the
                                                // ancestor gesture layer) used
                                                // to ALSO fire the tool here —
                                                // every pan click deposited a
                                                // stray fill, which is why one
                                                // fill sometimes took two undos.
                                                //
                                                // R28 #8: the EYEDROPPER is
                                                // exempt. Its whole point under a
                                                // mapped hold (pen barrel /
                                                // right-click) is that the held
                                                // NON-primary button is what
                                                // picks — the strict test meant
                                                // the mapping switched the tool
                                                // and then refused every press,
                                                // so it "제대로 작동하지도않고".
                                                // A pick writes no pixels, so
                                                // there is no stray-edit hazard
                                                // to guard against here.
                                                if (widget
                                                            .brushToolState
                                                            .tool !=
                                                        CanvasTool.eyedropper &&
                                                    event.buttons !=
                                                        kPrimaryButton) {
                                                  return;
                                                }
                                                _toolTapHandler()!(
                                                  _viewport.viewportToCanvas(
                                                    ViewportPoint(
                                                      x: event.localPosition.dx,
                                                      y: event.localPosition.dy,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        // Eyedropper cursor (R11-②): crosshair +
                                        // a hover swatch of the color under the
                                        // pointer — for the tool AND the Alt-held
                                        // temporary pick. Translucent: picks fall
                                        // through to the tap layer / canvas below.
                                        if (_eyedropperCursorActive) ...[
                                          Positioned.fill(
                                            child: MouseRegion(
                                              // R26 #22: the eyedropper wears its
                                              // OWN icon, not a crosshair — the
                                              // system cursor hides and the icon
                                              // below rides the pointer.
                                              cursor: SystemMouseCursors.none,
                                              opaque: false,
                                              hitTestBehavior:
                                                  HitTestBehavior.translucent,
                                              onExit: (_) =>
                                                  _eyedropperHover.value = null,
                                              // R28 #8: the swatch/icon is fed by
                                              // the panel's always-mounted pointer
                                              // census, not by a tracker mounted
                                              // here — one mounted at arming time
                                              // is outside an in-flight pointer's
                                              // route and hears nothing. This
                                              // region only hides the system
                                              // cursor and clears on exit.
                                              child: const SizedBox.expand(
                                                key: ValueKey<String>(
                                                  'eyedropper-hover-tracker',
                                                ),
                                              ),
                                            ),
                                          ),
                                          ValueListenableBuilder<
                                            ({Offset position, int color})?
                                          >(
                                            valueListenable: _eyedropperHover,
                                            builder: (context, hover, _) {
                                              if (hover == null) {
                                                return const SizedBox.shrink();
                                              }
                                              return Positioned(
                                                left: hover.position.dx + 14,
                                                top: hover.position.dy - 34,
                                                child: IgnorePointer(
                                                  child: Container(
                                                    key: const ValueKey<String>(
                                                      'eyedropper-hover-swatch',
                                                    ),
                                                    width: 26,
                                                    height: 26,
                                                    decoration: BoxDecoration(
                                                      color: Color(
                                                        0xFF000000 |
                                                            hover.color,
                                                      ),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 2,
                                                      ),
                                                      boxShadow: const [
                                                        BoxShadow(
                                                          color: Colors.black38,
                                                          blurRadius: 3,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                          // R26 #22: the eyedropper ICON as the
                                          // cursor. Its tip is the hot spot, so
                                          // the glyph hangs up-left of the point
                                          // being sampled.
                                          ValueListenableBuilder<
                                            ({Offset position, int color})?
                                          >(
                                            valueListenable: _eyedropperHover,
                                            builder: (context, hover, _) {
                                              if (hover == null) {
                                                return const SizedBox.shrink();
                                              }
                                              return Positioned(
                                                left: hover.position.dx - 3,
                                                top: hover.position.dy - 21,
                                                child: const IgnorePointer(
                                                  child: _ToolCursorIcon(
                                                    keyValue:
                                                        'eyedropper-cursor-icon',
                                                    icon: Icons.colorize,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                        // R26 #23: the fill tool wears the bucket.
                                        if (_fillCursorActive) ...[
                                          Positioned.fill(
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.none,
                                              opaque: false,
                                              hitTestBehavior:
                                                  HitTestBehavior.translucent,
                                              onExit: (_) =>
                                                  _toolCursorHover.value = null,
                                              child: Listener(
                                                key: const ValueKey<String>(
                                                  'fill-cursor-tracker',
                                                ),
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onPointerHover: (event) =>
                                                    _toolCursorHover.value =
                                                        event.localPosition,
                                                onPointerMove: (event) =>
                                                    _toolCursorHover.value =
                                                        event.localPosition,
                                              ),
                                            ),
                                          ),
                                          ValueListenableBuilder<Offset?>(
                                            valueListenable: _toolCursorHover,
                                            builder: (context, position, _) {
                                              if (position == null) {
                                                return const SizedBox.shrink();
                                              }
                                              return Positioned(
                                                left: position.dx - 3,
                                                top: position.dy - 20,
                                                child: const IgnorePointer(
                                                  child: _ToolCursorIcon(
                                                    keyValue:
                                                        'fill-cursor-icon',
                                                    icon:
                                                        Icons.format_color_fill,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                        // The painting tools wear their own
                                        // footprint: an outline of the tip that
                                        // follows the pointer, so a stroke can be
                                        // aimed before it starts.
                                        if (_brushCursorActive) ...[
                                          Positioned.fill(
                                            child: MouseRegion(
                                              key: const ValueKey<String>(
                                                'brush-cursor-region',
                                              ),
                                              // The outline IS the cursor, so
                                              // the system one steps aside.
                                              // Its POSITION comes from the
                                              // always-mounted census (R28
                                              // #8): a tracker mounted here
                                              // would sit outside an
                                              // in-flight stroke's route and
                                              // freeze the moment the pen
                                              // touched down.
                                              cursor: SystemMouseCursors.none,
                                              opaque: false,
                                              hitTestBehavior:
                                                  HitTestBehavior.translucent,
                                              onExit: (_) =>
                                                  _toolCursorHover.value = null,
                                              child: const SizedBox.expand(),
                                            ),
                                          ),
                                          ValueListenableBuilder<Offset?>(
                                            valueListenable: _toolCursorHover,
                                            builder: (context, position, _) {
                                              if (position == null) {
                                                return const SizedBox.shrink();
                                              }
                                              return BrushCursorOverlay(
                                                position: position,
                                                viewport: _viewport,
                                                size:
                                                    widget.brushToolState.size,
                                                roundness: widget
                                                    .brushToolState
                                                    .roundness,
                                                angleDegrees: widget
                                                    .brushToolState
                                                    .angleDegrees,
                                              );
                                            },
                                          ),
                                        ],
                                        // The P9 selection tools own the pointer
                                        // while active (marquee/lasso/move) —
                                        // strokes cannot start below the layer.
                                        if (selectionLayerActive)
                                          Positioned.fill(
                                            child: ValueListenableBuilder<ResampleMode>(
                                              valueListenable:
                                                  widget
                                                      .transformResampleMode ??
                                                  _defaultResampleMode,
                                              builder: (context, transformResampleMode, _) => CanvasSelectionLayer(
                                                tool: switch (widget
                                                    .brushToolState
                                                    .tool) {
                                                  CanvasTool.lasso =>
                                                    CanvasSelectionTool.lasso,
                                                  CanvasTool.move =>
                                                    CanvasSelectionTool.move,
                                                  _ => CanvasSelectionTool.rect,
                                                },
                                                // R17-U: Move = 이동+변형 통합 툴
                                                // — 핸들 상시.
                                                alwaysShowTransformBox:
                                                    widget
                                                        .brushToolState
                                                        .tool ==
                                                    CanvasTool.move,
                                                onShapeCommitted:
                                                    _recordSelectionChange,
                                                viewport: _viewport,
                                                canvasSize: widget.canvasSize,
                                                // No frame = a stable sentinel:
                                                // the selection survives until a
                                                // real frame context arrives.
                                                frameToken:
                                                    widget
                                                        .coordinator
                                                        ?.activeFrameKey ??
                                                    'selection-no-frame',
                                                selectionCommands:
                                                    widget.selectionCommands,
                                                onDragActiveChanged: (active) {
                                                  if (_selectionDragActive !=
                                                      active) {
                                                    widget
                                                        .onSelectionInteractionChanged
                                                        ?.call(active);
                                                    setState(
                                                      () =>
                                                          _selectionDragActive =
                                                              active,
                                                    );
                                                  }
                                                },
                                                // R14-④: the Move tool lifts the
                                                // selection's PIXELS (never whole
                                                // strokes) — 유저 direction ⑧b.
                                                onLiftRequested:
                                                    _handleSelectionLift,
                                                onLiftLanded: _handleLiftLanded,
                                                onLiftConfirmed:
                                                    _handleLiftConfirmed,
                                                onLiftReverted:
                                                    _handleLiftReverted,
                                                // R26 #13 follow-up: the implicit
                                                // whole-picture box frames the
                                                // cel's tight ink bounds.
                                                contentBoundsProvider:
                                                    _activeCelContentBounds,
                                                // The float stays up until the
                                                // committed surface can paint
                                                // what the session just landed —
                                                // its destination tiles are new
                                                // objects with no decoded image
                                                // for a frame or two, and the
                                                // base's stale fallback answers
                                                // for them with the tiles the
                                                // LIFT ERASED.
                                                committedRegionPendingTiles:
                                                    _committedRegionPendingTiles,
                                                // Pending move sessions hold the
                                                // session's edit lock (seeks
                                                // refused) WITHOUT locking
                                                // viewport navigation.
                                                onMoveSessionPendingChanged: widget
                                                    .onSelectionInteractionChanged,
                                                // P3a: which resampler a
                                                // transform runs through. Read
                                                // through the listenable above,
                                                // so flipping the switch mid
                                                // session re-resamples the open
                                                // preview instead of waiting for
                                                // the next gesture.
                                                resampleMode:
                                                    transformResampleMode,
                                              ),
                                            ),
                                          ),
                                        // R28-S: the selection is a DOCUMENT
                                        // fact, so its ants stay on screen under
                                        // every other tool too — that is what
                                        // makes "선택하고 다른 툴" legible (R26
                                        // #18). Purely decorative: the layer
                                        // above owns all interaction.
                                        if (idleSelection != null)
                                          Positioned.fill(
                                            key: const ValueKey<String>(
                                              'canvas-idle-selection-ants',
                                            ),
                                            child: IgnorePointer(
                                              child: CustomPaint(
                                                painter: SelectionAntsPainter(
                                                  repaint: _idleAnts,
                                                  viewport: _viewport,
                                                  committedRegion:
                                                      idleSelection,
                                                  screenOffset: Offset.zero,
                                                  marqueeShape: null,
                                                  lassoTrail: const [],
                                                ),
                                                child: const SizedBox.expand(),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    );
                    if (hud == null) {
                      return layer;
                    }
                    // Above the gesture layer, in the same box: the anchor
                    // the gesture reports is already in these coordinates.
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        layer,
                        FlipHudOverlay(controller: hud),
                      ],
                    );
                  }

                  return SizedBox.expand(
                    key: const ValueKey<String>('brush-canvas-editor-viewport'),
                    // Pan/zoom input lives on the panel — not the interactive
                    // canvas — so navigation keeps working when the viewport
                    // shows the blank paper or playback instead of a frame.
                    child: contentStrokeActive == null
                        ? gestureLayer(false)
                        : ValueListenableBuilder<bool>(
                            valueListenable: contentStrokeActive,
                            builder: (context, active, _) =>
                                gestureLayer(active),
                          ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildViewportContent(BuildContext context) {
    final override = widget.contentOverride;
    if (override != null) {
      return override(context, _viewport);
    }

    final coordinator = widget.coordinator!;
    final activeKey = coordinator.activeFrameKey;
    final interactiveView = InteractiveBrushEditCanvasView(
      // STABLE key (R13-2): keying by frameId remounted the whole
      // interactive subtree on every frame flip — the constant flip
      // hitch. Cel changes reset in place via didUpdateWidget.
      key: const ValueKey<String>('brush-canvas-view'),
      sessionState: coordinator.activeSessionState,
      layerId: activeKey.layerId,
      frameId: activeKey.frameId,
      inputSettings: widget.brushToolState.toInputSettings(),
      viewport: _viewport,
      // Alt+click = temporary eyedropper (P5): color only, the active
      // painting tool stays.
      onAltPick: widget.sampleColorAt == null || widget.onAltColorPick == null
          ? null
          : (point) {
              final color = widget.sampleColorAt!(point);
              if (color != null) {
                widget.onAltColorPick!(color);
              }
            },
      onTemporaryToolHold: widget.onTemporaryToolHold,
      onTemporaryToolRelease: widget.onTemporaryToolRelease,
      // PEN-11: one-shot mapped actions (undo/redo) from pen buttons.
      onInvokeAction: widget.onInvokeAction,
      onSourceStrokeCommitted: _handleSourceStrokeCommitted,
      // R22-A: the FILL tool runs through the view's stroke pipeline
      // (instant overlay + settling hold) instead of the panel tap layer.
      fillDabAt: widget.brushToolState.tool == CanvasTool.fill
          ? widget.fillDabAt
          : null,
      // R26 #18: the live stroke shows clipped to the selection, exactly
      // as the commit will clip it.
      selectionRegion: widget.selectionCommands?.region,
      onActiveStrokeChanged: (active) {
        if (_strokeActive != active) {
          widget.onStrokeInputActiveChanged?.call(active);
          setState(() => _strokeActive = active);
        }
      },
      // The underlay paints the paper (and the layers below); an opaque
      // background here would hide them.
      showTransparentBackground: widget.viewportUnderlayBuilder == null,
      // MERGED mode: the host owns the overlay model and paints this
      // surface itself, in composite-tree order, so a group buffer can
      // wrap the layer being drawn on. The view keeps the input.
      overlayModel: widget.activeStrokeOverlayModel,
      paintsContent: widget.activeStrokeOverlayModel == null,
      // An empty frame stands the view DOWN rather than unmounting it —
      // the mount was the expensive half of a flip that crosses a block.
      editable: widget.celEditable,
    );
    // The draw-through wrap: display AND hit testing share one screen
    // matrix, so the active layer draws posed and pointers inverse-map to
    // artwork coordinates in lockstep (R3 ⑩ — always-applied transforms).
    final pose = widget.interactiveContentPose;
    final Widget posedView = pose == null
        ? interactiveView
        : Transform(
            transform: layerPoseViewportWrapMatrix(
              pose.pose,
              widget.canvasSize,
              _viewport,
              anchorPoint: pose.anchorPoint,
            ),
            child: interactiveView,
          );
    if (widget.interactiveContentOpacity >= 1.0) {
      return posedView;
    }
    return Opacity(
      opacity: widget.interactiveContentOpacity.clamp(0.0, 1.0).toDouble(),
      child: posedView,
    );
  }

  void _rememberEditorViewportSize(Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    if (_editorViewportSize == size) {
      return;
    }
    final previous = _editorViewportSize;
    final insets = _framingInsets;
    // Both windows measured with the SAME cover, so the delta below is the
    // BOX's doing and nothing else. A cover that changed at the same time
    // is deliberately not counted — see [_reanchorAfterBoxChange].
    final before = previous == null
        ? null
        : canvasVisibleRect(previous, insets);
    _editorViewportSize = size;
    final after = canvasVisibleRect(size, insets);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (before != null) {
        _reanchorAfterBoxChange(before, after);
      }
      setState(() {});
    });
  }

  /// Keeps what you are looking at where you are looking when the BOX
  /// changes size.
  ///
  /// Pan is a pure screen-space translation applied after zoom, rotation and
  /// flip, so a window whose centre moved by a delta is answered by moving
  /// pan by exactly that delta — nothing has to be unprojected.
  ///
  /// Only the FLOOR does this, and only for the box. Two deliberate limits:
  ///
  ///  * A docked panel has always let the artwork sit still against its
  ///    top-left corner, and nothing is asking it to change. The floor is the
  ///    one surface that grows by hundreds of pixels the moment a dock opens
  ///    or the window resizes, which is where "the drawing walked into the
  ///    corner" comes from.
  ///  * A COVER change is left alone on purpose. When a panel opens over the
  ///    canvas the artwork does not move on screen — only the window onto it
  ///    shrinks — and sliding the picture out from under a panel the user
  ///    just opened, or shifting it on every frame of a splitter drag, is a
  ///    motion nobody asked for.
  void _reanchorAfterBoxChange(Rect before, Rect after) {
    final dx = after.center.dx - before.center.dx;
    final dy = after.center.dy - before.center.dy;
    if (dx == 0 && dy == 0) {
      return;
    }
    _setViewport(_viewport.translated(dx: dx, dy: dy));
  }

  void _setViewport(CanvasViewport viewport) {
    setState(() => _viewport = viewport.clamped());
    _syncViewportParent();
  }

  void _setViewportDuringPanbarDrag(CanvasViewport viewport) {
    setState(() => _viewport = viewport.clamped());
  }

  void _syncViewportParent() {
    _lastWidgetViewport = _viewport;
    widget.onViewportChanged?.call(_viewport);
  }

  void _zoomAroundCenter(double factor) {
    _zoomToAroundCenter(_viewport.zoom * factor);
  }

  /// Absolute-zoom twin of [_zoomAroundCenter] (the zoom label's inline
  /// percent entry commits through here).
  void _setZoomFromLabel(double zoom) {
    _zoomToAroundCenter(zoom);
  }

  void _zoomToAroundCenter(double nextZoom) {
    // The centre of what you can SEE, not of the box: anchoring on the box
    // walks the picture toward a covered edge one press at a time.
    final center = _resolvedVisibleRect().center;
    final anchor = ViewportPoint(x: center.dx, y: center.dy);
    setState(() {
      _viewport = _viewport.zoomedAround(nextZoom: nextZoom, anchor: anchor);
    });
    widget.onViewportChanged?.call(_viewport);
  }

  void _fitToView() {
    final canvasSize = widget.canvasSize;
    final target =
        widget.fitFocusRect ??
        Rect.fromLTWH(
          0,
          0,
          canvasSize.width.toDouble(),
          canvasSize.height.toDouble(),
        );
    setState(() {
      _viewport = _fittedInto(_resolvedVisibleRect(), canvasRect: target);
    });
    widget.onViewportChanged?.call(_viewport);
  }

  /// The panel's LAYOUT box — the surface you touch. Pan bars, the gesture
  /// layer and the shell memo want this one.
  Size _resolvedEditorViewportSize() {
    return _editorViewportSize ??
        Size(
          widget.canvasSize.width.toDouble(),
          widget.canvasSize.height.toDouble(),
        );
  }

  /// What is hidden from the artwork by the panels lying on it. Zero for a
  /// panel nothing lies on, which is every one but the floor.
  EdgeInsets get _framingInsets => widget.floorCover;

  /// The window you LOOK THROUGH, in layout coordinates. Every verb that
  /// frames the artwork wants this one — see [canvasVisibleRect].
  Rect _resolvedVisibleRect() =>
      canvasVisibleRect(_resolvedEditorViewportSize(), _framingInsets);

  void _resetView() {
    _setViewport(CanvasViewport());
  }

  ViewportPoint get _viewportCenterAnchor {
    final center = _resolvedVisibleRect().center;
    return ViewportPoint(x: center.dx, y: center.dy);
  }

  /// Rotates the VIEW by [degrees] around the viewport center (P8). The
  /// result snaps to 0° when within ±0.01° (float dust from gesture
  /// accumulations must not leave the AABB slow path armed forever).
  void _rotateAroundCenter(double degrees) {
    var next = _viewport.rotationDegrees + degrees;
    final normalized = ((next + 180) % 360) - 180;
    if (normalized.abs() < 0.01) {
      next = next - normalized;
    }
    _setViewport(
      _viewport.rotatedAround(
        nextRotationDegrees: next,
        anchor: _viewportCenterAnchor,
      ),
    );
  }

  void _toggleFlipHorizontal() {
    _setViewport(_viewport.flippedAround(anchor: _viewportCenterAnchor));
  }

  void _toggleFlipVertical() {
    _setViewport(
      _viewport.flippedVerticalAround(anchor: _viewportCenterAnchor),
    );
  }

  /// Straightens the rotation to 0° around the viewport center, keeping
  /// zoom/pan/flips (UI-R18 #20).
  void _resetRotation() {
    _setViewport(
      _viewport.rotatedAround(
        nextRotationDegrees: 0,
        anchor: _viewportCenterAnchor,
      ),
    );
  }

  /// The angle-label drag (UI-R18 #21): one degree per pixel, anchored to
  /// the viewport center.
  void _rotateByDrag(double deltaDegrees) {
    _rotateAroundCenter(deltaDegrees);
  }

  /// The tap action for the active NON-PAINTING tool; null while a
  /// painting tool is active (no tap layer mounts then).
  void Function(CanvasPoint point)? _toolTapHandler() {
    switch (widget.brushToolState.tool) {
      case CanvasTool.brush:
      case CanvasTool.eraser:
      // The selection/move tools mount their own drag layer, not the tap
      // layer.
      case CanvasTool.selectRect:
      case CanvasTool.lasso:
      case CanvasTool.move:
        return null;
      case CanvasTool.eyedropper:
        final sample = widget.sampleColorAt;
        final pick = widget.onEyedropperPick;
        if (sample == null || pick == null) {
          return null;
        }
        return (point) {
          final color = sample(point);
          if (color != null) {
            pick(color);
          }
        };
      case CanvasTool.fill:
        // R22-A: fill taps are handled by the interactive view's stroke
        // pipeline (fillDabAt) — instant overlay, settling hold, and the
        // same primary-button discipline as strokes. No tap layer.
        return null;
    }
  }

  void _handleSourceStrokeCommitted(BrushStrokeCommitData strokeData) {
    labProbe('penUpCommitHandler', () => _commitSourceStroke(strokeData));
  }

  /// Pre-lift surfaces by session token (R19 P3b): the immutable surface
  /// captured BEFORE a lift's erase — the confirm command's undo target
  /// and the revert's restore point. Reference-cheap.
  final Map<int, BitmapSurface> _liftAnchors = {};
  int _liftTokenSeq = 0;

  /// R16-① bitmap lift: commits [shape]'s ERASE — RAW, outside app
  /// history (the origin must vanish instantly, but nothing is undoable
  /// until the session CONFIRMS) — and returns a session token plus the
  /// lifted stamp dab, which floats until the confirm. Null when the
  /// R26 #13 follow-up: the active cel's tight ink bounds — the implicit
  /// whole-picture transform box frames exactly the picture, PS-style.
  /// Null (no coordinator, or a blank cel) falls back to the canvas rect
  /// inside the selection layer.
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  _activeCelContentBounds() {
    final coordinator = widget._editableCoordinator;
    if (coordinator == null) {
      return null;
    }
    final surface = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    // Memoized on the surface INSTANCE. `bitmapSurfaceContentBounds`
    // documents itself as "never a per-frame path", and that was false:
    // the selection layer calls this provider from `build` to frame the
    // always-on move box, so it ran once per rebuild — a full alpha scan
    // of every tile, preceded by `surface.tiles`, which is
    // `Map.unmodifiable(_tiles)` and copies the whole tile map on each
    // read. BitmapSurface is immutable with structural tile sharing (the
    // painter's shouldRepaint already relies on that), so identity is an
    // exact key: a changed cel is always a new instance.
    if (identical(surface, _contentBoundsSurface)) {
      return _contentBoundsCached;
    }
    final bounds = bitmapSurfaceContentBounds(surface);
    _contentBoundsSurface = surface;
    _contentBoundsCached = bounds;
    return bounds;
  }

  BitmapSurface? _contentBoundsSurface;
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  _contentBoundsCached;

  /// WHICH tiles the committed surface holds under this canvas rect have
  /// no decoded image yet — the tiles the selection layer keeps its float
  /// over until they arrive. Empty means the base can paint the lot.
  ///
  /// A coordinate with NO tile counts as ready: the surface has nothing to
  /// draw there, so waiting on it would wait forever.
  ///
  /// ⚠️ The set, not a bool. The base becomes paintable 32 tiles a paint,
  /// so a single yes/no made the float cover the whole landing until the
  /// last tile arrived — double-compositing every partial-alpha pixel
  /// under it, and, when the float could not paint, showing the user the
  /// convergence itself, tile by tile.
  Set<TileCoord> _committedRegionPendingTiles(
    int left,
    int top,
    int right,
    int bottom,
  ) {
    final coordinator = widget._editableCoordinator;
    if (coordinator == null) {
      return const <TileCoord>{};
    }
    final surface = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final size = surface.tileSize;
    final cache = BitmapTileImageCache.instance;
    // ⚠️ tileAt, NOT `surface.tiles[...]`. `tiles` is
    // `Map.unmodifiable(_tiles)` — a getter that COPIES the cel's whole
    // tile map on every call — so indexing it inside this walk made one
    // predicate O(coords × tiles) entry copies instead of O(coords) hash
    // lookups. Measured on the real surface at the 8192² the canvas dialog
    // allows (1024 tiles): 82.7 ms per walk against 28 µs, and the walk
    // that finds everything ready is by definition the complete one, so
    // that stall landed on the release frame of every confirm.
    //
    // floorDiv, not ~/: a stamp can land in the pasteboard, where the
    // coordinates are negative and truncation picks the wrong tile.
    final firstTx = floorDiv(left, size);
    final lastTx = floorDiv(right - 1, size);
    final lastTy = floorDiv(bottom - 1, size);
    var pending = const <TileCoord>{};
    for (var ty = floorDiv(top, size); ty <= lastTy; ty++) {
      for (var tx = firstTx; tx <= lastTx; tx++) {
        final coord = TileCoord(x: tx, y: ty);
        final tile = surface.tileAt(coord);
        if (tile != null && cache.imageFor(tile) == null) {
          if (identical(pending, const <TileCoord>{})) {
            pending = <TileCoord>{};
          }
          pending.add(coord);
        }
      }
    }
    return pending;
  }

  /// shape covers no pixels.
  ///
  /// [wholeTiles] names the coordinates the lift took ENTIRELY — the ones
  /// left with nothing behind — paired with the tiles that held them
  /// before. The float that is about to be built from this stamp holds,
  /// at those coordinates, exactly those pixels, so it can borrow them
  /// and paint on its first frame instead of waiting a decode round with
  /// four tiles' worth of fallback. Coordinates the lift only partly took
  /// are deliberately absent: see [BitmapTileImageCache.seedScope].
  ({int liftToken, BrushDab stampDab, Map<TileCoord, BitmapTile> wholeTiles})?
  _handleSelectionLift(CanvasSelectionRegion region) {
    final coordinator = widget._editableCoordinator;
    if (coordinator == null) {
      return null;
    }
    final preLift = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final lift = buildSelectionLiftDabs(
      region: region,
      surface: preLift,
      liftId: '${DateTime.now().microsecondsSinceEpoch}',
      options: widget.selectionMaskOptions?.value ?? SelectionMaskOptions.none,
    );
    if (lift == null) {
      return null;
    }
    final outcome = coordinator.commitSourceStroke(
      sourceDabs: [lift.eraseDab],
      cacheInvalidationSink: widget.cacheInvalidationSink,
    );
    if (outcome == null) {
      return null;
    }
    final token = ++_liftTokenSeq;
    _liftAnchors[token] = preLift;
    setState(() {});
    final after = coordinator.currentSurfaceOf(coordinator.activeFrameKey);
    final whole = <TileCoord, BitmapTile>{};
    // ⚠️ The LIFT'S tile range, not the whole cel. This walked
    // `preLift.tiles.entries` — one whole-map copy, then a full 256 KB
    // read per emptied tile — over every tile the cel had, including all
    // the ones the erase could not possibly have touched. A coordinate
    // outside the region's bounds cannot have been emptied by it, so the
    // answer is the same and the work is the lift's size instead of the
    // drawing's.
    final size = preLift.tileSize;
    final bounds = region.bounds;
    final lastTx = floorDiv(bounds.right.ceil() - 1, size);
    final lastTy = floorDiv(bounds.bottom.ceil() - 1, size);
    final firstTx = floorDiv(bounds.left.floor(), size);
    for (var ty = floorDiv(bounds.top.floor(), size); ty <= lastTy; ty += 1) {
      for (var tx = firstTx; tx <= lastTx; tx += 1) {
        final coord = TileCoord(x: tx, y: ty);
        final before = preLift.tileAt(coord);
        if (before == null) {
          continue;
        }
        // Untouched by the erase => structural sharing hands back the SAME
        // object, and a coordinate the lift did not take cannot be one it
        // took whole. Free, and it skips the byte scan entirely.
        final left = after.tileAt(coord);
        if (identical(left, before)) {
          continue;
        }
        // Emptied by the erase => the lift took this coordinate whole. The
        // erase does not drop emptied tiles, so the test is the alpha, not
        // the tile's absence. `isFullyTransparent` walks the tile's own
        // view; `tile.pixels` would be a 256 KB defensive COPY per call.
        if (left == null || left.isFullyTransparent) {
          whole[coord] = before;
        }
      }
    }
    // The base must stop answering for what the lift took. Its bucket
    // still holds the pre-erase tiles at these coordinates, so without
    // this it redraws the artwork in its ORIGINAL place while the float
    // draws it in the new one — two copies at the start, and on the
    // confirm frame a picture that is in the old place and absent from
    // the new one.
    //
    // Only the coordinates the lift took WHOLE: there the truth is
    // emptiness, so drawing nothing is right. A partially lifted
    // coordinate keeps its entry, because its surviving pixels are still
    // better than none.
    //
    // ⚠️ This was written once before and reverted, on the word of a test
    // that counted INK rather than looking at where it was. The base's
    // displaced copy is ink too, so removing it read as losing coverage.
    // The oracle asks about position now, and says the opposite.
    final activeKey = coordinator.activeFrameKey;
    BitmapTileImageCache.instance.invalidateCoords((
      activeKey.layerId,
      activeKey.frameId,
    ), whole.keys);
    return (liftToken: token, stampDab: lift.stampDab, wholeTiles: whole);
  }

  /// R16-① confirm: lands the floating stamp and adopts the whole move
  /// session (raw lift + landed stamp) into app history as ONE undo
  /// entry — a surface-snapshot command whose undo target is the exact
  /// pre-lift picture (R19 P3b).
  void _handleLiftConfirmed(int liftToken, BrushDab stampDab) {
    final coordinator = widget._editableCoordinator;
    final preLift = _liftAnchors.remove(liftToken);
    if (coordinator == null) {
      return;
    }
    // The setState rebuilds the interactive view onto the post-confirm
    // surface (R17-①b: without it the landed stamp stayed invisible —
    // white hole at the origin, nothing at the destination — until an
    // unrelated rebuild). Mounted guard: the layer's unmount path
    // confirms post-frame, possibly after this panel went with it.
    void run() {
      final historyManager = widget.historyManager;
      if (historyManager == null || preLift == null) {
        // Headless hosts (focused tests) or a lost anchor: land raw.
        coordinator.commitSourceStroke(
          sourceDabs: [stampDab],
          cacheInvalidationSink: widget.cacheInvalidationSink,
        );
        return;
      }
      historyManager.execute(
        BrushLiftMoveHistoryCommand(
          coordinator: coordinator,
          frameKey: coordinator.activeFrameKey,
          preLiftSurface: preLift,
          stampDab: stampDab,
          cacheInvalidationSink: widget.cacheInvalidationSink,
        ),
      );
    }

    if (mounted) {
      setState(run);
    } else {
      run();
    }
  }

  /// REVERT of a session (R17-①): the pre-lift surface snapshot restores
  /// the picture byte-exactly; nothing lands in history.
  void _handleLiftReverted(int liftToken) {
    final coordinator = widget._editableCoordinator;
    final preLift = _liftAnchors.remove(liftToken);
    if (coordinator == null || preLift == null) {
      return;
    }
    void run() {
      coordinator.restoreSurfaceSnapshot(
        coordinator.activeFrameKey,
        preLift,
        cacheInvalidationSink: widget.cacheInvalidationSink,
      );
    }

    if (mounted) {
      setState(run);
    } else {
      run();
    }
  }

  /// Raw landing of the floating stamp (no history entry) — the abandon
  /// fallback so a reset never loses the float's pixels. The base surface
  /// is the post-erase state throughout the session, so landing is a
  /// plain stamp commit.
  void _handleLiftLanded(int liftToken, BrushDab stampDab) {
    final coordinator = widget._editableCoordinator;
    _liftAnchors.remove(liftToken);
    if (coordinator == null) {
      return;
    }
    void run() {
      coordinator.commitSourceStroke(
        sourceDabs: [stampDab],
        cacheInvalidationSink: widget.cacheInvalidationSink,
      );
    }

    if (mounted) {
      setState(run);
    } else {
      run();
    }
  }

  /// R26 #18 ("선택하고 그리면 선택 내부만 그려진다"): a stroke that lands
  /// with a live selection is CLIPPED to it before it reaches the commit.
  ///
  /// The clip runs on the stroke's own straight-alpha buffer, where alpha
  /// 0 is every commit kernel's "leave the destination alone" input — so
  /// one pass covers brush, eraser, fill and every brush blend mode with
  /// no per-mode branches. Null return = the whole stroke fell outside
  /// the selection and there is nothing to commit.
  BrushStrokeCommitData? _clipStrokeToSelection(BrushStrokeCommitData data) {
    final region = widget.selectionCommands?.region;
    if (region == null) {
      return data;
    }
    if (data.promotedTiles != null) {
      // The stroke was pre-blended THROUGH the selection mask (R28): the
      // promoted tiles are already clipped, and re-deriving them here
      // would throw away the finished pixels to rasterize the dabs again.
      // An empty list means the whole stroke fell outside the selection.
      return data.promotedTiles!.isEmpty ? null : data;
    }
    var pixels = data.strokePixels;
    var bounds = data.strokeBounds;
    if (pixels == null || bounds == null) {
      // No live raster (programmatic strokes, a redo replaying dabs):
      // rasterize the coverage first so the clip has bytes to work on.
      final rasterized = rasterizeStrokeForClipping(
        dabs: data.sourceDabs,
        canvasSize: widget.canvasSize,
        tileSize: widget._editableCoordinator == null
            ? BitmapSurface(canvasSize: widget.canvasSize).tileSize
            : widget._editableCoordinator!
                  .currentSurfaceOf(widget._editableCoordinator!.activeFrameKey)
                  .tileSize,
      );
      if (rasterized == null) {
        return null;
      }
      pixels = rasterized.pixels;
      bounds = rasterized.bounds;
    }
    final clipped = clipStrokePixelsToSelection(
      pixels: pixels,
      bounds: bounds,
      region: region,
    );
    if (clipped == null) {
      return null;
    }
    return BrushStrokeCommitData(
      sourceDabs: data.sourceDabs,
      strokePixels: clipped.pixels,
      strokeBounds: clipped.bounds,
      blendMode: data.blendMode,
    );
  }

  void _commitSourceStroke(BrushStrokeCommitData rawStrokeData) {
    // Only reachable from the interactive canvas, which requires the
    // coordinator to exist.
    final coordinator = widget._editableCoordinator!;
    final strokeData = _clipStrokeToSelection(rawStrokeData);
    if (strokeData == null) {
      // Entirely outside the selection: nothing lands, nothing undoes.
      // The live overlay already showed it clipped, so the pen-up is
      // simply the overlay clearing.
      setState(() {});
      return;
    }
    setState(() {
      final historyManager = widget.historyManager;
      if (historyManager == null) {
        coordinator.commitSourceStroke(
          sourceDabs: strokeData.sourceDabs,
          cacheInvalidationSink: widget.cacheInvalidationSink,
          prerasterizedStrokePixels: strokeData.strokePixels,
          prerasterizedStrokeBounds: strokeData.strokeBounds,
          blendMode: strokeData.blendMode,
          promotedBase: strokeData.promotedBase,
          promotedTiles: strokeData.promotedTiles,
        );
        return;
      }
      historyManager.execute(
        BrushStrokeHistoryCommand(
          coordinator: coordinator,
          strokeData: strokeData,
          cacheInvalidationSink: widget.cacheInvalidationSink,
        ),
      );
    });
  }
}

/// EVERY canvas panel wears the same chrome: none.
///
/// The shell used to come in two shapes. The floor got capsules floating on
/// the artwork; every other canvas surface — the timesheet, the conte, the
/// envelope, the media viewer — got a framed panel with a status strip
/// across the top (the project name, the host's own buttons) and a bar
/// across the bottom (the scrollbar and the view controls). Two shapes for
/// the same thing, and the second one spent two rows of every paper panel
/// saying what the tab already said.
///
/// 유저, R2 #12·#13: the strip goes, the bar goes, the frame goes. What a
/// panel actually needs comes back as a pill on the artwork, exactly the way
/// the floor's does — so there is one canvas panel with one vocabulary, and
/// a paper panel differs from the drawing only in which buttons its pill
/// carries.
class _CanvasEditorPanelShell extends StatelessWidget {
  /// The strip holds exactly one thing — the vertical panbar — so its
  /// width IS that bar's hit lane.
  static const double rightStripWidth = AppScrollbarLane.medium;

  const _CanvasEditorPanelShell({
    required this.child,
    required this.bottomBar,
    required this.rightStripBar,
    required this.horizontalStripBar,
    required this.cover,
    this.railBand,
    this.strokeActive = false,
    this.contentStrokeActive,
  });

  final Widget child;
  final Widget bottomBar;
  final Widget rightStripBar;

  /// The horizontal panbar, its own capsule on the top edge.
  final Widget horizontalStripBar;

  /// The floor's controls fade while a stroke is in progress.
  ///
  /// Hover is not the answer this reaches for and cannot be: touch has no
  /// hover at all, and a pen hovers over the DRAWING rather than over the
  /// controls, so a hover-to-reveal cluster would be invisible exactly when
  /// the hand is working. What the app already knows is when a stroke is
  /// live, and that is the moment the controls are in the way.
  final bool strokeActive;
  final ValueListenable<bool>? contentStrokeActive;

  /// What panels floating over this one hide from the artwork.
  ///
  /// The canvas fills the whole box — panels lie ON it, they do not take
  /// space from it — and the chrome floats, pulled in by this much so the
  /// pieces you reach for hug the part you can still see. Zero for a panel
  /// nothing is covering.
  final EdgeInsets cover;

  /// The vertical band the rail on the right edge occupies — see
  /// [BrushCanvasPanel.floorRailBand].
  final CanvasFloorBand? railBand;

  /// How far a floating capsule sits in from the window's edge.
  ///
  /// ONE number for the pill and both panbars (유저, R4 #5: 그 패딩거리 다
  /// 통일되있는거 맞나? 통일하고, 지금보다 좀 더 가깝게). It already was one
  /// number — the three land within half a pixel of each other at every
  /// panel width, which is what `brush_canvas_panel_test` now pins — so the
  /// horizontal bar reading as further out was the capsule around it being
  /// 14px tall against the pill's 52, not the gap. The gap itself moved
  /// 8 → 6.
  static const double _capsuleMargin = 6;

  /// What a scrollbar capsule spans, as a share of the edge it rides —
  /// clamped, because the point of a capsule is that it says where you are
  /// and lets you drag back, not that it maps the whole pasteboard.
  static const double _capsuleTrackFraction = 0.34;
  static const double _capsuleTrackMin = 80;

  static const double _capsuleTrackMax = 260;

  double _capsuleTrack(double edge) {
    // Never wider than the edge it rides, and never so short that the thumb
    // has nowhere to travel — a scrollbar that cannot be dragged is not a
    // scrollbar, and dragging is the ONLY way back from a runaway pan.
    final room = math.max(0.0, edge - 2 * _capsuleMargin);
    final wanted = (edge * _capsuleTrackFraction).clamp(
      _capsuleTrackMin,
      _capsuleTrackMax,
    );
    return math.min(wanted, room);
  }

  /// Canvas everywhere, controls floating on the part of it you can see.
  ///
  /// Nothing here takes a band across the artwork. The chrome used to be
  /// three strips that reserved their own thickness; they are capsules that
  /// lie on the drawing now, pinned to the edges of the part of it you can
  /// still see, and pushed in when a panel opens.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      key: const ValueKey<String>('canvas-editor-panel-shell'),
      children: [
        // Nothing is meant to show through — the canvas paints its own
        // backdrop over the whole box — but the floor is the one surface
        // with no panel behind it, so it states its own floor colour rather
        // than borrowing whatever the route happens to be sitting on.
        Positioned.fill(
          child: ColoredBox(color: colorScheme.surfaceContainerLowest),
        ),
        Positioned.fill(
          child: KeyedSubtree(
            key: const ValueKey<String>('canvas-editor-panel-content'),
            child: child,
          ),
        ),
        // THE PANBARS ARE FURNITURE — but furniture in a room, not in the
        // wall.
        //
        // 🆕유저, R3 #5·#6, and it is the third pass over this: the bars now
        // CENTRE ON WHAT YOU CAN SEE. Both are placed inside the visible
        // rectangle rather than the panel's — the vertical one at the middle
        // of the visible HEIGHT (so docking the region at the bottom walks
        // it up, which is what "하단패널이 열린거에 따라 중앙계산" asked back),
        // the horizontal one at the middle of the visible WIDTH, on the
        // BOTTOM edge (패널열리면 위치바뀌는거 허용).
        //
        // ★And the vertical bar only steps IN from the edge when the rail is
        // actually beside it. A rail panel is as tall as it was left at, so
        // a short one covers a band, not an edge: stepping in for the whole
        // edge left the bar hanging in the middle of nothing.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, panel) {
              final insets = cover;
              final visibleTop = insets.top;
              final visibleBottom = math.max(
                visibleTop,
                panel.maxHeight - insets.bottom,
              );
              final track = _capsuleTrack(visibleBottom - visibleTop);
              final centre = (visibleTop + visibleBottom) / 2;
              final barTop = centre - track / 2;
              final intrudes = canvasFloorBandIntrudes(
                railBand,
                top: barTop,
                bottom: barTop + track,
              );
              final edge = intrudes
                  ? insets.right + _capsuleMargin
                  : _capsuleMargin;
              return Stack(
                children: [
                  Positioned(
                    right: edge,
                    top: barTop,
                    height: track,
                    child: _capsule(
                      colorScheme,
                      keyValue: 'canvas-panbar-vertical',
                      width: rightStripWidth,
                      height: track,
                      child: rightStripBar,
                    ),
                  ),
                  // 🆕유저 (R4): 가로스크롤바나 알약은 그냥 양옆에서
                  // 펼치든말든 중앙에. The two axes are NOT the same
                  // question, and the answer differs by axis rather than
                  // by widget:
                  //
                  //  * ALONG the edge it rides, the bar holds the window's
                  //    centre. A side panel opening is not a reason for
                  //    the thing you read to walk sideways — that is the
                  //    「읽는 것은 안 움직인다」 rule, and the earlier pass
                  //    over-applied "centre on what you can see" to it.
                  //  * ACROSS that edge it still yields, because there it
                  //    is not a matter of taste: a bar on the bottom edge
                  //    with the region docked below would be UNDER it.
                  Positioned(
                    left: _capsuleMargin,
                    right: _capsuleMargin,
                    bottom: insets.bottom + _capsuleMargin,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _capsule(
                        colorScheme,
                        keyValue: 'canvas-panbar-horizontal',
                        height: AppScrollbarLane.medium,
                        width: _capsuleTrack(panel.maxWidth),
                        child: horizontalStripBar,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Positioned(
          // The pill answers the same way the horizontal bar does (유저,
          // R4): it holds the window's centre across the axis it sits on,
          // and yields only on the axis that would bury it — the region
          // docked on TOP is above it, a rail beside it is not.
          left: 0,
          top: cover.top,
          right: 0,
          bottom: cover.bottom,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final window = Size(
                constraints.maxWidth.clamp(0.0, double.infinity),
                constraints.maxHeight.clamp(0.0, double.infinity),
              );
              return _FloatingCanvasControls(
                strokeActive: strokeActive,
                contentStrokeActive: contentStrokeActive,
                children: [
                  // THE PILL, at the TOP CENTRE (유저, R3 #6).
                  //
                  // ⛔It used to take the top corner away from the tool strip
                  // (R2 #14), which needed a rule about which hand the strip
                  // was under and an InheritedWidget to publish the answer.
                  // Centred, there is no side to choose, and the pill is the
                  // same distance from either hand.
                  //
                  // It sits ON the top edge now rather than one lane below
                  // it: the horizontal panbar used to own that edge and has
                  // moved to the bottom, so the row it was making way for is
                  // gone. Still NOT the timeline's edge, for the old reason
                  // — that edge moves on every resize and every threshold
                  // switch, and 좌우반전 gets pressed dozens of times an hour.
                  Positioned(
                    left: _capsuleMargin,
                    top: _capsuleMargin,
                    right: _capsuleMargin,
                    child: Align(
                      alignment: Alignment.topCenter,
                      // BOUNDED on purpose: an unbounded pill would offer
                      // itself everything, keep every control and overflow.
                      // The shedding is the whole reason it is measured.
                      //
                      // There is no floor under which the pill disappears.
                      // There used to be — below 190px it stood down, on
                      // the reading that a capsule around an empty row says
                      // nothing. With the docked bar gone the row is never
                      // empty: Fit is in it at every width, and the panel
                      // narrow enough to have lost the pill is the one that
                      // needed it most.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: math.max(
                            0.0,
                            window.width - 2 * _capsuleMargin,
                          ),
                        ),
                        child: _capsule(
                          colorScheme,
                          keyValue: 'canvas-view-pill',
                          height: _CanvasViewportBottomBar.height,
                          child: bottomBar,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// One floating control surface: opaque, superellipse, ringed in the
  /// backdrop.
  ///
  /// The ring is not decoration. What lies beside a capsule is the
  /// PASTEBOARD, a colour the user chooses, so no fill of ours can be
  /// relied on to contrast with it — the same reason the panbar lane has
  /// carried a hairline since the palette collapsed to three fills.
  Widget _capsule(
    ColorScheme colorScheme, {
    required String keyValue,
    required Widget child,
    double? width,
    double? height,
  }) {
    // The corner follows the SHORT axis, the way every control's does. A
    // capsule with neither axis stated would ask for an infinite radius, so
    // the fallback is the app's smallest corner rather than a crash.
    final short = math.min(width ?? double.infinity, height ?? double.infinity);
    final shape = short.isFinite
        ? AppShapes.control(short)
        : AppShapes.container(AppShapes.wellRadius);
    return DecoratedBox(
      key: ValueKey<String>(keyValue),
      decoration: ShapeDecoration(
        color: colorScheme.surface,
        shape: shape.copyWith(
          side: const BorderSide(color: AppColors.backdrop),
        ),
      ),
      child: ClipPath(
        clipper: AppShapes.clipper(shape),
        child: SizedBox(width: width, height: height, child: child),
      ),
    );
  }
}

/// The floor's controls, laid on the drawing and fading out of the way of
/// a stroke.
///
/// The Stack takes pointers only where its children are, so the empty
/// middle — most of the screen — still belongs to the canvas.
class _FloatingCanvasControls extends StatelessWidget {
  const _FloatingCanvasControls({
    required this.strokeActive,
    required this.contentStrokeActive,
    required this.children,
  });

  final bool strokeActive;
  final ValueListenable<bool>? contentStrokeActive;
  final List<Widget> children;

  static Widget _dim({required bool active, required Widget child}) =>
      AnimatedOpacity(
        key: const ValueKey<String>('canvas-floating-controls'),
        opacity: active ? 0.16 : 1,
        duration: const Duration(milliseconds: 120),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final stack = Stack(children: children);
    final content = contentStrokeActive;
    if (content == null) {
      return _dim(active: strokeActive, child: stack);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: content,
      builder: (context, contentActive, child) =>
          _dim(active: strokeActive || contentActive, child: child!),
      child: stack,
    );
  }
}

/// The pill: a canvas panel's whole vocabulary of controls, in a capsule
/// on the artwork.
///
/// ⚠️「뷰 컨트롤은 바닥에만」 is PARTLY REPEALED (유저, R2 #13). That law gave
/// the floor every view control and left the paper panels with two
/// scrollbars, on the reading that a timesheet is a page you read beside
/// the drawing rather than the drawing. In the hand it turned out a page
/// you read is a page you zoom, so Fit, 1:1 and the zoom steps come back
/// everywhere. What stays floor-only is ROTATE and FLIP: a sheet with a
/// form printed on it has no reason to be turned over.
///
/// It sheds from the outside in as the panel narrows — colours first
/// (a choice you make once a project), then rotate/flip, then the zoom
/// readout and steps — and it never stands down entirely, because with the
/// docked bar gone it is the only home Fit has.
class _CanvasViewportBottomBar extends StatelessWidget {
  static const double height = 28;

  /// At/above this width the bar shows every view control (fit, 1:1,
  /// rotate, flip). Below it the secondary rotate/flip controls drop out so
  /// the essentials stay reachable (rotation is still on R/Shift+R/H).
  static const double _wideLayoutMinWidth = 360;

  /// What one host control in [leading] adds to that threshold: the widest
  /// control in the shared vocabulary (a [DragValueLabel] readout) plus
  /// breathing room. The bar cannot measure widgets it did not build, so
  /// it budgets generously on purpose — over-budgeting only makes the bar
  /// scroll a little sooner, while under-budgeting OVERFLOWS.
  static const double _leadingControlBudget = 44;

  /// What Fit plus the pill's own padding and one divider costs — the
  /// floor under which even the host's controls have to go, so that the
  /// one control the pill may never drop always has room. Measured: 26 for
  /// the button, 13 for the divider, 8 for the pill's ends, and slack.
  static const double _essentialBudget = 60;

  /// The LEAST a host control can cost — the shared icon button's own
  /// minimum. [_leadingControlBudget] is its opposite and both are right,
  /// because the two decisions want opposite errors: deciding what the
  /// pill can AFFORD, budget high and shed a little early; deciding
  /// whether the host's own controls have to GO, budget low, because
  /// dropping the page navigation from a rail that could have held it is
  /// the worse mistake. Using the generous number for both took the
  /// timesheet's whole cluster away at its default width.
  static const double _leadingControlFloor = 26;

  /// Below this the pill drops the paper/pasteboard swatches. They are the
  /// least urgent thing it carries — a colour you set once per project,
  /// against controls you press dozens of times an hour — and they are
  /// still in the project settings.
  static const double _pillColorMinWidth = 470;

  /// Below this the pill drops the zoom readout and the two zoom steps,
  /// and below it MINUS the host's own controls it drops those too. It
  /// never drops Fit, and it never stands down: the docked bar that used
  /// to be the alternative is gone.
  static const double pillMinWidth = 190;

  const _CanvasViewportBottomBar({
    this.leading = const <Widget>[],
    required this.viewport,
    required this.canvasSize,
    required this.paperColor,
    required this.onPaperColorChanged,
    required this.pasteboardColor,
    required this.onPasteboardColorChanged,
    required this.backdropColor,
    required this.onBackdropColorChanged,
    required this.onViewportChanged,
    required this.onViewportChangeEnd,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomSet,
    required this.onFit,
    required this.onReset,
    required this.onRotateCcw,
    required this.onRotateCw,
    required this.onRotateReset,
    required this.onRotateByDrag,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
  });

  /// R26 #41: host controls at the head of the pill.
  final List<Widget> leading;

  final CanvasViewport viewport;

  // ⛔The pill does NOT take the viewport's SIZE. It never read it, and
  // taking it tied the pill's memo to a number that changes on every frame
  // of a window resize (유저, R3 #14).
  final CanvasSize canvasSize;

  /// R28 #9: the surface colors, right of the horizontal scrollbar where
  /// the user placed them. Null handlers hide the pair (hosts that own
  /// neither, e.g. the timesheet ink layer).
  final int paperColor;
  final ValueChanged<int>? onPaperColorChanged;
  final int pasteboardColor;
  final ValueChanged<int>? onPasteboardColorChanged;

  /// The third plane of the same stage (유저, R3 #4).
  final int backdropColor;
  final ValueChanged<int>? onBackdropColorChanged;

  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback onViewportChangeEnd;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final ValueChanged<double> onZoomSet;
  final VoidCallback onFit;
  final VoidCallback onReset;

  /// Null hides the rotate/flip controls (rotation-disabled hosts).
  final VoidCallback? onRotateCcw;
  final VoidCallback? onRotateCw;
  final VoidCallback? onRotateReset;
  final ValueChanged<double>? onRotateByDrag;
  final VoidCallback? onFlipHorizontal;
  final VoidCallback? onFlipVertical;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Normalized for display: multi-turn accumulation shows as its
    // visible angle.
    final rotationDegrees = (((viewport.rotationDegrees + 180) % 360) - 180)
        .round();

    Widget divider() => Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: colorScheme.outlineVariant,
    );

    // ROTATION/FLIP cluster (UI-R18 #20, left→right): rotate-left, the
    // ALWAYS-ON angle readout (drag = 1°/px, double-tap = type), rotate-
    // right, straighten, flip-H, flip-V. Rotate buttons accent by the
    // rotation SIGN (#18); flips accent while active (#19).
    final viewControls = <Widget>[
      if (onRotateCcw != null)
        _barIconButton(
          keyValue: 'canvas-viewport-rotate-ccw',
          tooltip: AppText.strings.viewRotateLeft,
          icon: const Icon(Icons.rotate_left),
          onPressed: onRotateCcw,
          isSelected: rotationDegrees < 0,
        ),
      if (onRotateByDrag != null)
        DragValueLabel(
          keyValue: 'canvas-viewport-rotation-label',
          text: '$rotationDegrees°',
          tooltip: AppText.strings.viewAngleDrag,
          width: 40,
          textStyle: const TextStyle(fontSize: 11),
          onDragDelta: onRotateByDrag!,
          onEditSubmit: (text) {
            final parsed = double.tryParse(text);
            if (parsed != null && onRotateByDrag != null) {
              onRotateByDrag!(parsed - viewport.rotationDegrees);
            }
          },
        ),
      if (onRotateCw != null)
        _barIconButton(
          keyValue: 'canvas-viewport-rotate-cw',
          tooltip: AppText.strings.viewRotateRight,
          icon: const Icon(Icons.rotate_right),
          onPressed: onRotateCw,
          isSelected: rotationDegrees > 0,
        ),
      if (onRotateReset != null)
        _barIconButton(
          keyValue: 'canvas-viewport-rotate-reset',
          tooltip: AppText.strings.viewStraighten,
          icon: const Icon(Icons.refresh),
          onPressed: onRotateReset,
        ),
      if (onFlipHorizontal != null)
        _barIconButton(
          keyValue: 'canvas-viewport-flip',
          tooltip: AppText.strings.viewFlipHorizontal,
          icon: const Icon(Icons.flip),
          onPressed: onFlipHorizontal,
          isSelected: viewport.flipHorizontal,
        ),
      if (onFlipVertical != null)
        _barIconButton(
          keyValue: 'canvas-viewport-flip-vertical',
          tooltip: AppText.strings.viewFlipVertical,
          icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)),
          onPressed: onFlipVertical,
          isSelected: viewport.flipVertical,
        ),
    ];

    // ZOOM cluster (UI-R18 #17/#20, left→right): fit, 1:1, −, the zoom
    // readout (drag = 1%/px, double-tap = type), +.
    final zoomCluster = <Widget>[
      _barIconButton(
        keyValue: 'canvas-viewport-fit',
        tooltip: AppText.strings.viewFitToView,
        icon: const Icon(Icons.fit_screen),
        onPressed: onFit,
      ),
      _barIconButton(
        keyValue: 'canvas-viewport-reset',
        tooltip: AppText.strings.viewResetView,
        icon: const Text(
          '1:1',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
        onPressed: onReset,
      ),
      _barIconButton(
        keyValue: 'canvas-viewport-zoom-out',
        tooltip: AppText.strings.viewZoomOut,
        icon: const Icon(Icons.zoom_out),
        onPressed: onZoomOut,
      ),
      DragValueLabel(
        keyValue: 'canvas-viewport-zoom-label',
        inputKeyValue: 'canvas-viewport-zoom-input',
        text: '${(viewport.zoom * 100).round()}%',
        tooltip: AppText.strings.viewZoomDrag,
        width: 44,
        textStyle: const TextStyle(fontSize: 12),
        onDragDelta: (units) => onZoomSet(
          ((viewport.zoom * 100 + units).clamp(10.0, 1600.0)) / 100,
        ),
        onEditSubmit: (text) {
          final parsed = double.tryParse(text.replaceAll('%', '').trim());
          if (parsed != null) {
            onZoomSet(parsed.clamp(10.0, 1600.0) / 100);
          }
        },
      ),
      _barIconButton(
        keyValue: 'canvas-viewport-zoom-in',
        tooltip: AppText.strings.viewZoomIn,
        icon: const Icon(Icons.zoom_in),
        onPressed: onZoomIn,
      ),
    ];

    /// What survives in a panel too narrow for the readout and the two
    /// zoom steps. Fit is the one control with no gesture that replaces
    /// it — a runaway view is walked back with Fit or with the panbars,
    /// and the panbars are only useful once you can see the paper.
    final essentialCluster = <Widget>[zoomCluster.first];

    // R28 #9: the surface colors sit immediately right of the scrollbar
    // ("색 바꾸는 버튼 위치는 밑의 가로스크롤바의 바로오른쪽에"). Both use the
    // shared round-swatch control, so the picker looks and behaves the
    // same here as anywhere else the app asks for a color.
    final onPaper = onPaperColorChanged;
    final onPasteboard = onPasteboardColorChanged;
    final onBackdrop = onBackdropColorChanged;
    final colorControls = <Widget>[
      if (onPaper != null)
        ColorSwatchButton(
          keyValue: 'canvas-paper-color-button',
          title: 'Canvas',
          tooltip: AppText.strings.viewCanvasColor,
          color: paperColor,
          onChanged: onPaper,
        ),
      if (onPasteboard != null) ...[
        const SizedBox(width: 4),
        ColorSwatchButton(
          keyValue: 'canvas-pasteboard-color-button',
          title: 'Pasteboard',
          tooltip: AppText.strings.viewPasteboardColor,
          color: pasteboardColor,
          onChanged: onPasteboard,
        ),
      ],
      // 제일오른쪽에 배경색 (유저, R3 #4) — outermost swatch for the
      // outermost plane, so the three read out from the paper in the same
      // order they are stacked on screen.
      if (onBackdrop != null) ...[
        const SizedBox(width: 4),
        ColorSwatchButton(
          keyValue: 'canvas-backdrop-color-button',
          title: 'Backdrop',
          tooltip: AppText.strings.viewBackdropColor,
          color: backdropColor,
          // The backdrop is opaque BY CONTRACT: it is the stage's final
          // answer, and an alpha there would only re-ask the question.
          onChanged: (argb) => onBackdrop(0xFF000000 | argb),
        ),
      ],
      if (onPaper != null || onPasteboard != null || onBackdrop != null)
        const SizedBox(width: 2),
    ];

    // Non-empty clusters joined by hairlines — so a host that supplies no
    // leading controls (or a rotation-disabled host with no view controls)
    // never shows a divider with nothing on one side.
    List<Widget> joined(List<List<Widget>> clusters) {
      final row = <Widget>[];
      for (final cluster in clusters) {
        if (cluster.isEmpty) {
          continue;
        }
        if (row.isNotEmpty) {
          row.add(divider());
        }
        row.addAll(cluster);
      }
      return row;
    }

    // THE PILL, and there is no longer a second shape. It has no scrollbar
    // to stretch — those float on the panel's own edges — so it is as wide
    // as what it holds, and SHEDS clusters rather than scrolling when the
    // panel cannot pay for them (띠는 스크롤하지 않는다: a scrolling strip
    // hands drags to its scroll arena before its children ever see them).
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.maxWidth;
          // EVERY threshold pays for the host's own controls first. They
          // are the panel's reason for having a pill at all — the page you
          // are on, the sheet you are reading — so the view controls shed
          // around them rather than the other way round. The bar cannot
          // measure widgets it did not build, so it budgets generously:
          // over-budgeting sheds a little early, under-budgeting OVERFLOWS
          // onto the artwork, which is what a narrow rail did.
          final owed = leading.length * _leadingControlBudget;
          final roomy = room >= _pillColorMinWidth + owed;
          final wide = room >= _wideLayoutMinWidth + owed;
          final cramped = room < pillMinWidth + owed;
          // Last of all the host's controls go too — but Fit never does.
          // With the docked bar gone this is its only home, and a panel
          // narrow enough to lose it is exactly the panel that needs it.
          //
          // ⚠️This threshold has to budget `owed` like the others. It did
          // not, and that left a band — measured at 206..250px of rail —
          // where the pill kept all seven of the timesheet's controls and
          // then pushed Fit out past the capsule's own clip: invisible and
          // unhittable, in the one panel width the comment above promises
          // it to. Below 206 `bare` finally tripped and it came back, so
          // the button blinked out and in as the rail was dragged.
          final bare =
              room < leading.length * _leadingControlFloor + _essentialBudget;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 4),
              ...joined([
                if (!bare) leading,
                cramped ? essentialCluster : zoomCluster,
                if (wide) viewControls,
                if (roomy) colorControls,
              ]),
              const SizedBox(width: 4),
            ],
          );
        },
      ),
    );
  }

  /// R26 #42: this bar's button style is now the app-wide default, so it
  /// lives in [AppIconButton] — this is just the local spelling.
  Widget _barIconButton({
    required String keyValue,
    required String tooltip,
    required Widget icon,
    required VoidCallback? onPressed,
    bool isSelected = false,
  }) {
    return AppIconButton(
      keyValue: keyValue,
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      isSelected: isSelected,
    );
  }
}

class CanvasEditorSelectionLabels {
  const CanvasEditorSelectionLabels({
    this.projectLabel = '-',
    this.cutLabel = '-',
    this.layerLabel = '-',
    this.frameLabel = '-',
  });

  final String projectLabel;
  final String cutLabel;
  final String layerLabel;
  final String frameLabel;

  String get title =>
      'Project: $projectLabel · Cut: $cutLabel · Layer: $layerLabel · Frame: $frameLabel';
}

class CanvasViewportHorizontalScrollbar extends StatelessWidget {
  const CanvasViewportHorizontalScrollbar({
    super.key,
    required this.viewport,
    required this.editorViewportSize,
    required this.canvasSize,
    required this.onViewportChanged,
    this.onViewportChangeEnd,
  });
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;
  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback? onViewportChangeEnd;
  @override
  Widget build(BuildContext context) => _CanvasViewportPanbar(
    axis: Axis.horizontal,
    viewport: viewport,
    editorViewportSize: editorViewportSize,
    canvasSize: canvasSize,
    onViewportChanged: onViewportChanged,
    onViewportChangeEnd: onViewportChangeEnd,
  );
}

class CanvasViewportVerticalScrollbar extends StatelessWidget {
  const CanvasViewportVerticalScrollbar({
    super.key,
    required this.viewport,
    required this.editorViewportSize,
    required this.canvasSize,
    required this.onViewportChanged,
    this.onViewportChangeEnd,
  });
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;
  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback? onViewportChangeEnd;
  @override
  Widget build(BuildContext context) => _CanvasViewportPanbar(
    axis: Axis.vertical,
    viewport: viewport,
    editorViewportSize: editorViewportSize,
    canvasSize: canvasSize,
    onViewportChanged: onViewportChanged,
    onViewportChangeEnd: onViewportChangeEnd,
  );
}

class _CanvasViewportPanbar extends StatelessWidget {
  const _CanvasViewportPanbar({
    required this.axis,
    required this.viewport,
    required this.editorViewportSize,
    required this.canvasSize,
    required this.onViewportChanged,
    this.onViewportChangeEnd,
  });
  final Axis axis;
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;
  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback? onViewportChangeEnd;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = axis == Axis.horizontal;
    return SizedBox(
      key: ValueKey<String>(
        isHorizontal
            ? 'canvas-viewport-horizontal-scrollbar'
            : 'canvas-viewport-vertical-scrollbar',
      ),
      height: isHorizontal ? 14 : double.infinity,
      width: isHorizontal ? double.infinity : 14,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = CanvasViewportPanMetrics(
            axis: axis,
            viewport: viewport,
            editorViewportSize: editorViewportSize,
            canvasSize: canvasSize,
            trackExtent: isHorizontal
                ? constraints.maxWidth
                : constraints.maxHeight,
          );
          return AppScrollbar(
            axis: axis,
            offset: metrics.scrollOffset,
            viewportExtent: metrics.visibleExtent,
            contentExtent: metrics.scaledContentExtent,
            minThumbExtent: CanvasViewportPanMetrics.minThumbExtent,
            // The whole lane pans relatively: the canvas panbar has always
            // been a grab-anywhere 1:1 surface, not a jump-to-tap track.
            lanePress: AppScrollbarLanePress.relativeDrag,
            onOffsetChanged: (next) =>
                onViewportChanged(metrics.viewportForScroll(next)),
            onChangeEnd: onViewportChangeEnd,
          );
        },
      ),
    );
  }
}

/// R26 #22/#23: a tool's own icon standing in for the mouse cursor —
/// white glyph with a dark halo so it reads on any artwork.
class _ToolCursorIcon extends StatelessWidget {
  const _ToolCursorIcon({required this.keyValue, required this.icon});

  final String keyValue;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: ValueKey<String>(keyValue),
      children: [
        Icon(icon, size: 22, color: Colors.black.withValues(alpha: 0.55)),
        Positioned(
          left: 1,
          top: 1,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ],
    );
  }
}

/// The stage's outer planes behind the artwork (R3b): the opaque backdrop
/// with the RGBA pasteboard over it — or the alpha checkerboard in place
/// of BOTH while [alphaPreviewEnabled] is on (an alpha export excludes
/// them, so the preview must too; only the paper's own alpha stays real).
/// Subscribed here so every BrushCanvasPanel shell (canvas, timesheet,
/// conte) follows the toggle without leaning on an ancestor rebuild.
///
/// ★THE PASTEBOARD IS A PLACE, NOT A WASH (유저, R2 #3). Both planes used
/// to fill the whole panel, one over the other — which is a stack for
/// ALPHA and says nothing about where either one is. An opaque pasteboard
/// therefore covered the backdrop everywhere and forever: the user had
/// three colours in the settings and could only ever see two of them, and
/// changing the pasteboard repainted what they meant by "the background".
/// The pasteboard is now drawn only where the pasteboard IS, and the
/// backdrop is what lies beyond it.
class _StagePlanes extends StatelessWidget {
  const _StagePlanes({
    required this.backdropArgb,
    required this.pasteboardArgb,
    required this.pasteboardMargin,
    required this.canvasSize,
    required this.viewport,
    required this.child,
  });

  final int backdropArgb;
  final int pasteboardArgb;

  /// How far past each canvas edge the pasteboard SHOWS, in canvas widths
  /// and heights. Its own number rather than the drawing bound's, because
  /// the two answer different questions — see [Project.pasteboardMargin].
  final double pasteboardMargin;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: alphaPreviewEnabled,
      builder: (context, preview, _) => preview
          ? CustomPaint(painter: const AlphaCheckerboardPainter(), child: child)
          : CustomPaint(
              painter: _StagePlanesPainter(
                backdrop: Color(backdropArgb),
                pasteboard: Color(pasteboardArgb),
                margin: pasteboardMargin,
                canvasSize: canvasSize,
                viewport: viewport,
              ),
              child: child,
            ),
    );
  }
}

/// Fills with the backdrop, then lays the pasteboard over the region it
/// occupies — a canvas-space rectangle, so it rides zoom, pan, rotation
/// and both flips like everything else on the stage.
class _StagePlanesPainter extends CustomPainter {
  const _StagePlanesPainter({
    required this.backdrop,
    required this.pasteboard,
    required this.margin,
    required this.canvasSize,
    required this.viewport,
  });

  final Color backdrop;
  final Color pasteboard;
  final double margin;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = backdrop);
    if (pasteboard.a <= 0 || margin < 0) {
      return;
    }
    final width = canvasSize.width.toDouble();
    final height = canvasSize.height.toDouble();
    final left = -margin * width;
    final top = -margin * height;
    final right = width + margin * width;
    final bottom = height + margin * height;
    // The four corners through the view transform, as a PATH: under
    // rotation the pasteboard is a quad, and a Rect would silently square
    // it back up.
    Offset at(double x, double y) {
      final point = viewport.canvasToViewport(CanvasPoint(x: x, y: y));
      return Offset(point.x, point.y);
    }

    final path = Path()
      ..moveTo(at(left, top).dx, at(left, top).dy)
      ..lineTo(at(right, top).dx, at(right, top).dy)
      ..lineTo(at(right, bottom).dx, at(right, bottom).dy)
      ..lineTo(at(left, bottom).dx, at(left, bottom).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = pasteboard);
  }

  @override
  bool shouldRepaint(covariant _StagePlanesPainter oldDelegate) =>
      oldDelegate.backdrop != backdrop ||
      oldDelegate.pasteboard != pasteboard ||
      oldDelegate.margin != margin ||
      oldDelegate.canvasSize != canvasSize ||
      oldDelegate.viewport != viewport;
}
