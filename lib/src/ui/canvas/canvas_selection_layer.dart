import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_dab_sequence.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/tile_coord.dart';
import '../../models/viewport_point.dart';
import 'dart:math' as math;

import '../../native/qa_native_engine.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../../services/bitmap_surface_brush_commit.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/resample/resample_kernel.dart';
import '../../models/pasteboard_bounds.dart';
import '../brush/canvas_selection_commands.dart';
import 'selection_ants_painter.dart';
import 'bitmap_surface_painter.dart';
import 'provisional_tile_pictures.dart';
import 'bitmap_tile_image_cache.dart';
import 'viewport_canvas_transform.dart';

/// The P9 selection interaction layer, mounted over the canvas while a
/// selection tool is active (Photoshop/CSP language):
///
/// - Dragging on empty ground draws a NEW region — rectangle marquee or
///   freehand lasso — shown as marching ants.
/// - Dragging INSIDE the region moves the selection's PIXELS (R19 pixel
///   model): the shape's raster lifts once (erase lands raw, the stamp
///   floats), every drag/nudge/Ctrl+T only moves the float, and the
///   CONFIRM adopts the whole session as ONE history entry.
/// - A click (degenerate drag) deselects; Ctrl+D and arrow nudges arrive
///   through [selectionCommands].
///
/// All region geometry lives in CANVAS coordinates, so the ants stay
/// glued to the artwork through pan/zoom/rotation.
class CanvasSelectionLayer extends StatefulWidget {
  const CanvasSelectionLayer({
    super.key,
    required this.tool,
    this.shapeKind = CanvasShapeKind.rect,
    required this.viewport,
    required this.canvasSize,
    required this.frameToken,
    this.onShapeCommitted,
    this.onCutShape,
    this.selectionCommands,
    this.onDragActiveChanged,
    this.onLiftRequested,
    this.onLiftLanded,
    this.onLiftConfirmed,
    this.onLiftReverted,
    this.onMoveSessionPendingChanged,
    this.alwaysShowTransformBox = false,
    this.contentBoundsProvider,
    this.committedRegionPendingTiles,
    this.composeCommittedRegionPictures,
    this.resampleMode = ResampleMode.blend,
  });

  /// Offers the host the picture the screen is showing over the landing
  /// rect, so the tiles the commit just created can draw THEMSELVES on the
  /// next frame instead of being covered for.
  ///
  /// The hold above is a cover: the float keeps painting where the base
  /// cannot. This is the other move — give the base a picture — and it is
  /// strictly better where it applies, because a covered tile is a second
  /// widget clipped over the canvas and an answered one is just the canvas.
  /// Whatever this cannot answer for, the hold still covers; the two are
  /// read through the same predicate, so a tile is never both.
  ///
  /// [paintInk] draws in CANVAS coordinates and reports whether it drew
  /// everything that belongs in the rect it was given.
  final void Function(
    int left,
    int top,
    int right,
    int bottom,
    ProvisionalInkPainter paintInk,
  )?
  composeCommittedRegionPictures;

  /// WHICH tiles of the canvas rect a session just landed into the host's
  /// committed surface cannot PAINT yet — the ones whose tile exists but
  /// has no decoded image. Empty means the base is ready everywhere.
  ///
  /// The float is kept over exactly those tiles until they arrive.
  /// Dropping it the moment the stamp is handed over left two frames with
  /// the artwork nowhere: the stamp's destination tiles are new objects,
  /// so they have no image yet, and the base painter's stale fallback
  /// answers with the tiles the LIFT ERASED. The float meanwhile holds
  /// exactly those bytes at exactly that place — that is P3a's
  /// preview/commit byte-identity contract — so keeping it one moment
  /// longer is not a patch over the gap, it is the picture.
  ///
  /// ⚠️ Tiles, not a yes/no. This began as a bool and released
  /// all-or-nothing, which cost twice over on a big landing. The base
  /// becomes paintable 32 tiles a paint, so while it converged the float
  /// still covered the WHOLE rect: partial-alpha pixels took a second
  /// source-over and feathered edges read darker (measured on a
  /// whole-picture move of a 2340×1654 cel: 208,234 pixels differing
  /// across two frames, every one darker). And when the hold could not
  /// engage, that same convergence was the user-visible "I can watch it
  /// apply tile by tile". A tile is drawn by the float or by the base,
  /// never both and never neither.
  ///
  /// A host that does not supply this clears the float immediately, which
  /// is the old behaviour; the focused tests rely on it.
  final Set<TileCoord> Function(int left, int top, int right, int bottom)?
  committedRegionPendingTiles;

  /// How a transform turns pixels into other pixels (P3a): the tent mean
  /// that smooths, or the coverage argmax that copies source words through
  /// untouched so a two-value drawing stays two-valued.
  ///
  /// This is a property of the RESAMPLE, not a declaration about the
  /// layer's content — nothing here inspects the picture to decide.
  final ResampleMode resampleMode;

  /// R26 #13 follow-up: the active cel's tight ink bounds (canvas
  /// coordinates, exclusive right/bottom) — the implicit whole-picture
  /// box frames exactly the picture, PS-style, instead of the canvas
  /// rect. Null (or a null result) falls back to the canvas rect.
  final ({int left, int top, int rightExclusive, int bottomExclusive})?
  Function()?
  contentBoundsProvider;

  /// R17-U (이동+Ctrl+T 통합, 핸들 상시): with the MOVE tool a selection
  /// shows its transform box immediately — grabbing a scale/rotate handle
  /// opens the session on the spot (the lift happens at that first
  /// interaction, never on mere display). Ctrl+T still works everywhere.
  final bool alwaysShowTransformBox;

  /// What a finished drag DOES with its outline — select, move, or cut.
  final CanvasSelectionTool tool;

  /// Which outline a drag traces. Ignored by [CanvasSelectionTool.move],
  /// which drags an existing region rather than tracing a new one.
  final CanvasShapeKind shapeKind;

  final CanvasViewport viewport;
  final CanvasSize canvasSize;

  /// Changes when the edited frame changes — the selection resets (a
  /// region has no meaning on another frame's pixels).
  final Object frameToken;

  /// A committed region change — marquee release, click-away, Ctrl+D —
  /// as (before, after); the host wraps it into the selection-shape
  /// history command (R11-⑧: selecting is undoable). Null applies changes
  /// directly with no history (focused tests).
  final void Function(
    CanvasSelectionRegion? before,
    CanvasSelectionRegion? after,
  )?
  onShapeCommitted;

  /// A finished CUT outline. Raised instead of [onShapeCommitted] while a
  /// cut variant is armed — the host lifts the pixels under it into the cut
  /// slot, and the committed selection is not touched at all.
  ///
  /// Deliberately not routed through [onShapeCommitted] with a flag: a cut
  /// is not a selection change, so it must not reach the selection history
  /// either. Ctrl+Z after a cut should undo whatever the user last DREW,
  /// not silently swallow one press.
  final ValueChanged<CanvasSelectionShape>? onCutShape;

  final CanvasSelectionCommands? selectionCommands;

  /// Raised while a selection drag is in progress (the panel holds
  /// viewport gestures exactly like during a stroke).
  final ValueChanged<bool>? onDragActiveChanged;

  /// R14-④/R15-④ bitmap lift: called ONCE per selection shape when the
  /// Move tool first drags (or nudges) it. The host commits the shape's
  /// ERASE (origin pixels vanish immediately) and returns that command's
  /// id plus the lifted STAMP dab, which the layer floats until the
  /// session confirms — so the original is never visible while moving and
  /// a reverted/zero-move session restores it exactly. Null return = the
  /// shape covers no pixels: the move is a no-op. R19 pixel model: every
  /// session lifts fresh from the CURRENT raster (a confirmed move's next
  /// move re-lifts the landed pixels — byte-identical by construction).
  ///
  /// `wholeTiles` names the coordinates the lift took ENTIRELY, paired
  /// with the tiles that held them before — the float about to be built
  /// holds exactly those pixels there, so it can borrow them and paint on
  /// its first frame. A host that has nothing to offer returns an empty
  /// map and the float waits for its own decodes, as it used to.
  final ({
    int liftToken,
    BrushDab stampDab,
    Map<TileCoord, BitmapTile> wholeTiles,
  })?
  Function(CanvasSelectionRegion region)?
  onLiftRequested;

  /// Raw landing of the floating stamp at its pending position (no
  /// history entry) — the abandon fallback so a reset can never lose the
  /// float's pixels.
  final void Function(int liftToken, BrushDab stampDab)? onLiftLanded;

  /// CONFIRM of a move session (R16-①): the host lands [stampDab] and
  /// adopts the whole session (raw lift + landed stamp) as ONE history
  /// entry (BrushLiftMoveHistoryCommand).
  final void Function(int liftToken, BrushDab stampDab)? onLiftConfirmed;

  /// REVERT (R17-①): the host restores the pre-lift picture byte-exactly;
  /// nothing lands in history.
  final void Function(int liftToken)? onLiftReverted;

  /// True while a move session awaits its confirm — the host holds the
  /// session's edit-interaction lock (seeks refused, warmer down) without
  /// locking viewport navigation.
  final ValueChanged<bool>? onMoveSessionPendingChanged;

  @override
  State<CanvasSelectionLayer> createState() => _CanvasSelectionLayerState();
}

/// What the layer DOES with a finished drag — the verb, never the shape.
///
/// Which outline the drag traces is [CanvasSelectionLayer.shapeKind], a
/// separate axis: [select] and [cut] each draw every shape, and they differ
/// only in where the outline goes afterwards.
enum CanvasSelectionTool {
  /// Folds the finished outline into the selection region.
  select,

  /// Drags the selected content (R11-⑧: selection and move are separate
  /// tools — a marquee drag never moves strokes anymore). It traces no
  /// outline, so it wears no shape.
  move,

  /// Hands the finished outline to [CanvasSelectionLayer.onCutShape] and
  /// leaves the committed region exactly as the drag found it.
  ///
  /// Riding this layer rather than a second one of its own is deliberate —
  /// the marquee/lasso geometry, the viewport mapping and the pointer
  /// arbitration here are the trickiest input code in the app, and a
  /// parallel copy would be the kind that drifts.
  cut,
}

enum _DragMode { none, marquee, move, transform, vertexTap }

/// The float the transform preview last resampled.
///
/// A test hook. It exists because the contract P3a is built around — "what
/// the preview showed is what Enter writes" — is otherwise unobservable
/// from outside: the preview holds a decoded image and the commit writes
/// bytes, and only the layer sees that both came from one buffer.
///
/// Written and cleared inside `assert(() { ... }())`, which is stripped in
/// release. `@visibleForTesting` is an analyzer annotation and removes
/// nothing from a build, so an unguarded assignment here would pin the
/// last transform's straight-alpha buffer — tens of megabytes for a
/// whole-picture Ctrl+T — for the rest of the process, in every shipped
/// app, released by nothing.
@visibleForTesting
BrushDab? debugLastResampledFloat;

/// Records [dab] for the test hook and returns true, so it can sit inside
/// an assert and vanish from release builds.
bool _recordResampledFloat(BrushDab? dab) {
  debugLastResampledFloat = dab;
  return true;
}

/// What a cached resample belongs to: the mode, the source buffer, and the
/// warp's numbers.
///
/// The source is compared by IDENTITY. A lift stamp's bytes never change
/// in place — a new lift means a new buffer — so identity is the exact
/// question, and comparing multi-megabyte cels by value on every drag
/// frame would cost more than the resample this is guarding.
class _ResampleKey {
  const _ResampleKey(this.mode, this.source, this.shape);

  final ResampleMode mode;
  final Uint8List source;
  final String shape;

  @override
  bool operator ==(Object other) =>
      other is _ResampleKey &&
      other.mode == mode &&
      identical(other.source, source) &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(mode, identityHashCode(source), shape);
}

/// Which part of the Ctrl+T box a drag grabbed.
enum _TransformHandle {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
  topEdge,
  rightEdge,
  bottomEdge,
  leftEdge,
  rotate,
  inside,
}

/// The grabbed handle's BASE-LOCAL coordinates (relative to the base box
/// center = the affine pivot); null for rotate/inside.
CanvasPoint? _handleLocal(_TransformHandle handle, double w, double h) {
  switch (handle) {
    case _TransformHandle.topLeft:
      return CanvasPoint(x: -w / 2, y: -h / 2);
    case _TransformHandle.topRight:
      return CanvasPoint(x: w / 2, y: -h / 2);
    case _TransformHandle.bottomRight:
      return CanvasPoint(x: w / 2, y: h / 2);
    case _TransformHandle.bottomLeft:
      return CanvasPoint(x: -w / 2, y: h / 2);
    case _TransformHandle.topEdge:
      return CanvasPoint(x: 0, y: -h / 2);
    case _TransformHandle.rightEdge:
      return CanvasPoint(x: w / 2, y: 0);
    case _TransformHandle.bottomEdge:
      return CanvasPoint(x: 0, y: h / 2);
    case _TransformHandle.leftEdge:
      return CanvasPoint(x: -w / 2, y: 0);
    case _TransformHandle.rotate:
    case _TransformHandle.inside:
      return null;
  }
}

class _CanvasSelectionLayerState extends State<CanvasSelectionLayer>
    with SingleTickerProviderStateMixin {
  /// The live selection, mirrored from [CanvasSelectionCommands.region]
  /// (R28-S: the channel OWNS it, so it survives this layer unmounting on
  /// a tool switch — see the channel's own note).
  CanvasSelectionRegion? _region;

  /// Assigns the region and pushes it to the app-level channel. Callers
  /// wrap in setState; the channel's setter is idempotent, so the round
  /// trip back through [applyCommittedRegion] settles immediately.
  void _setRegion(CanvasSelectionRegion? region) {
    _region = region;
    widget.selectionCommands?.setRegion(region);
  }

  /// True whenever the shape's pixels are NOT already floating: from a
  /// USER selection (marquee commit, shape channel apply) until a Move
  /// interaction lifts them, and again after every confirm (R19 pixel
  /// model — the next move re-lifts the landed raster, byte-identical).
  bool _shapeNeedsLift = false;

  /// R26 #13: true while [_region] is the IMPLICIT whole-canvas target the
  /// MOVE tool synthesized because no selection existed ("선택하지 않은
  /// 상황이어도 그림 전체를 이동"). The session's end — confirm or revert
  /// — returns to NO selection, and the implicit shape never records a
  /// selection history entry (the user never selected anything).
  bool _shapeIsImplicitWholePicture = false;

  /// The implicit whole-picture shape: the cel's tight INK bounds when
  /// the host provides them (PS-style — the box frames the picture), the
  /// full canvas rect otherwise. Lifting it lifts the whole picture (the
  /// tool guard upstream already refuses the MOVE tool when the cel has
  /// no picture at all).
  ///
  /// "The whole picture" means the whole PICTURE, pasteboard included.
  /// This used to clamp to the canvas rect, which was defended as "the
  /// same coverage the canvas-rect box had" — but the pasteboard is a
  /// first-class part of the drawing here, so a transform with nothing
  /// selected left the off-canvas ink standing still while the rest of
  /// the picture moved out from under it. The clamp stays, widened to
  /// the pasteboard: it is what keeps the box inside the finite wall
  /// every stage downstream (lift, resample, preview, commit) treats as
  /// the edge of the world.
  CanvasSelectionShape _wholeCanvasShape() {
    final width = widget.canvasSize.width.toDouble();
    final height = widget.canvasSize.height.toDouble();
    var left = 0.0, top = 0.0, right = width, bottom = height;
    final content = widget.contentBoundsProvider?.call();
    if (content != null) {
      final wallLeft = widget.canvasSize.pasteboardLeft.toDouble();
      final wallTop = widget.canvasSize.pasteboardTop.toDouble();
      final wallRight = widget.canvasSize.pasteboardRightExclusive.toDouble();
      final wallBottom = widget.canvasSize.pasteboardBottomExclusive.toDouble();
      left = content.left.toDouble().clamp(wallLeft, wallRight);
      top = content.top.toDouble().clamp(wallTop, wallBottom);
      right = content.rightExclusive.toDouble().clamp(wallLeft, wallRight);
      bottom = content.bottomExclusive.toDouble().clamp(wallTop, wallBottom);
      if (right <= left || bottom <= top) {
        left = 0;
        top = 0;
        right = width;
        bottom = height;
      }
    }
    return CanvasSelectionShape([
      CanvasPoint(x: left, y: top),
      CanvasPoint(x: right, y: top),
      CanvasPoint(x: right, y: bottom),
      CanvasPoint(x: left, y: bottom),
    ]);
  }

  /// Installs [shape] as the live implicit whole-picture selection.
  /// Callers wrap in setState.
  CanvasSelectionRegion _adoptImplicitWholePictureShape(
    CanvasSelectionShape shape,
  ) {
    final region = CanvasSelectionRegion.shape(shape);
    _setRegion(region);
    _shapeNeedsLift = true;
    _shapeIsImplicitWholePicture = true;
    return region;
  }

  /// An implicit shape whose lift found nothing rolls back to
  /// no-selection (no stray ants around an empty canvas).
  void _clearFailedImplicitShape() {
    if (!_shapeIsImplicitWholePicture) {
      return;
    }
    _setRegion(null);
    _shapeNeedsLift = false;
    _shapeIsImplicitWholePicture = false;
  }

  /// The lift command owning this selection's pixels (R15-④), the stamp
  /// dab currently FLOATING (removed from the command so the base never
  /// shows it — no double image), and the command's dabs as they stood
  /// before the session opened (the transform `before` for re-opened
  /// sessions).
  ///
  /// R16-① (TVP-style): the stamp stays floating through EVERY drag and
  /// nudge — nothing lands and nothing is undoable until the user
  /// CONFIRMS (button, Enter, tool switch, deselect, undo/redo hook),
  /// which adopts the whole session as ONE history entry.
  int? _liftToken;
  BrushDab? _pendingLiftStamp;

  /// True once the session actually MOVED — the ants turn red until the
  /// confirm (green = confirmed / untouched).
  bool _moveSessionDirty = false;

  /// The region as the session found it — the revert restores it.
  CanvasSelectionRegion? _moveSessionStartShape;

  bool get _movePending => _pendingLiftStamp != null;

  /// REVERT (R17-①): the pixels — and the ants — return exactly to where
  /// the session found them; nothing lands in history.
  void _revertMoveSession() {
    final id = _liftToken;
    final pending = _pendingLiftStamp;
    if (id == null || pending == null) {
      return;
    }
    widget.onLiftReverted?.call(id);
    final startShape = _moveSessionStartShape;
    if (mounted) {
      setState(() {
        // R26 #13: an implicit whole-picture session reverts to NO
        // selection — the user never selected anything.
        if (_shapeIsImplicitWholePicture) {
          _setRegion(null);
          _shapeIsImplicitWholePicture = false;
          _shapeNeedsLift = false;
        } else {
          if (startShape != null) {
            _setRegion(startShape);
          }
          _shapeNeedsLift = true;
        }
        _pendingLiftStamp = null;
        _liftToken = null;
        _moveSessionDirty = false;
        _moveSessionStartShape = null;
        if (_transform == null) {
          _floatSurface = null;
        }
      });
    }
    widget.onMoveSessionPendingChanged?.call(false);
    _syncAnts();
  }

  void _clearLiftState() {
    final wasPending = _movePending;
    _liftToken = null;
    _pendingLiftStamp = null;
    _moveSessionDirty = false;
    if (wasPending) {
      widget.onMoveSessionPendingChanged?.call(false);
    }
  }

  /// CONFIRM (R16-①): lands the floating stamp and adopts the whole
  /// session as ONE history entry. Safe to call from any event context;
  /// never called inside a build phase (the tool-switch and dispose
  /// triggers defer post-frame). Afterwards the shape needs a fresh lift
  /// (R19 pixel model: the landed raster IS the content to move next).
  void _confirmMoveSession() {
    final id = _liftToken;
    final pending = _pendingLiftStamp;
    if (id == null || pending == null) {
      return;
    }
    final confirm = widget.onLiftConfirmed;
    if (confirm != null) {
      confirm(id, pending);
    } else {
      // Headless hosts (focused tests): land without history.
      widget.onLiftLanded?.call(id, pending);
    }
    if (mounted) {
      setState(() {
        _pendingLiftStamp = null;
        _liftToken = null;
        _moveSessionDirty = false;
        _moveSessionStartShape = null;
        _shapeNeedsLift = true;
        // R26 #13: a confirmed implicit whole-picture session lands and
        // simply ends — back to no selection.
        if (_shapeIsImplicitWholePicture) {
          _setRegion(null);
          _shapeIsImplicitWholePicture = false;
          _shapeNeedsLift = false;
        }
        // NOT cleared here — see _holdFloatUntilCommittedCanPaint, called
        // once this setState has run.
      });
      if (_transform == null) {
        _holdFloatUntilCommittedCanPaint(pending);
      }
    } else {
      _pendingLiftStamp = null;
      _liftToken = null;
      _moveSessionDirty = false;
      _moveSessionStartShape = null;
      _shapeNeedsLift = true;
      if (_shapeIsImplicitWholePicture) {
        _setRegion(null);
        _shapeIsImplicitWholePicture = false;
        _shapeNeedsLift = false;
      }
    }
    widget.onMoveSessionPendingChanged?.call(false);
    _syncAnts();
  }

  /// The committed region as it stood when a marquee drag started — the
  /// undo record's BEFORE (a cancelled drag restores it).
  CanvasSelectionRegion? _shapeBeforeMarquee;

  _DragMode _dragMode = _DragMode.none;
  int? _activePointer;

  // Marquee-in-progress (canvas space).
  CanvasPoint? _marqueeStart;
  CanvasPoint? _marqueeCurrent;
  List<CanvasPoint> _lassoPoints = const [];

  // Move-in-progress: screen-space delta + the floating copy of the
  // selected strokes (built once at drag start).
  Offset _moveScreenDelta = Offset.zero;
  BitmapSurface? _floatSurface;

  // Ctrl+T free-transform session (P9b): the composite affine, the base
  // box it manipulates (the shape's AABB at session start; its center is
  // the affine pivot) and the per-drag solving context.
  SelectionAffine? _transform;
  double _baseBoxWidth = 0;
  double _baseBoxHeight = 0;
  _TransformHandle? _transformDragHandle;
  SelectionAffine? _transformDragStart;
  CanvasPoint? _transformDragStartPointer;
  double _transformLastAngle = 0;

  /// Screen-space hit slack around a handle (≥ touch-friendly).
  static const double _handleHitRadius = 16;

  /// How far the rotate knob sticks out of the top edge, screen pixels.
  static const double _rotateLeverLength = 28;

  late final AnimationController _ants = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  bool get _hasSelection => _region != null;

  /// Mirrors the channel's open-trace length so a vertex added or taken
  /// back repaints this layer. The trace itself is never copied down here
  /// — the channel stays its only owner.
  int _polygonTracePoints = 0;

  /// Where a vertex tap went DOWN — the point it will place.
  ///
  /// Down for the position, up for the commit: the aim is taken where the
  /// stylus landed, and nothing is placed until the hand comes off (유저
  /// 법: 선택은 탭 = 손 떼야). Taking the release position instead would
  /// slide the vertex out from under a finger that rolled.
  Offset? _vertexTapStart;

  @override
  void initState() {
    super.initState();
    // R28-S: adopt whatever the app already has selected — the region
    // outlives this layer (tool switches unmount it), so mounting must
    // pick it back up instead of starting empty.
    _region = widget.selectionCommands?.region;
    _shapeNeedsLift = _region != null;
    _bindCommands();
    widget.selectionCommands?.addListener(_adoptChannelRegion);
  }

  /// The channel is the region's OWNER (R28-S), so a write that did not
  /// come from this layer — a host installing a region, a history command
  /// executing while another tool was armed — must land here too. Writes
  /// that DID come from this layer echo back equal and stop at the guard.
  void _adoptChannelRegion() {
    if (!mounted) {
      return;
    }
    // An open polygon trace lives on the channel too, and undo/redo drive
    // it from the app rather than from here — so a vertex coming or going
    // has to repaint this layer even when the region did not move.
    final tracePoints = widget.selectionCommands?.polygonPoints.length ?? 0;
    if (tracePoints != _polygonTracePoints) {
      setState(() => _polygonTracePoints = tracePoints);
      _syncAnts();
    }
    final channelRegion = widget.selectionCommands?.region;
    if (channelRegion == _region) {
      return;
    }
    setState(() {
      _region = channelRegion;
      _shapeNeedsLift = channelRegion != null;
      _shapeIsImplicitWholePicture = false;
      _clearLiftState();
      if (channelRegion == null) {
        _clearTransform();
      }
    });
    _syncAnts();
  }

  @override
  void didUpdateWidget(covariant CanvasSelectionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selectionCommands, widget.selectionCommands)) {
      oldWidget.selectionCommands?.unbind();
      oldWidget.selectionCommands?.removeListener(_adoptChannelRegion);
      _region = widget.selectionCommands?.region;
      _shapeNeedsLift = _region != null;
      _bindCommands();
      widget.selectionCommands?.addListener(_adoptChannelRegion);
    }
    if (oldWidget.frameToken != widget.frameToken) {
      // Build-phase safety (R15-⑤): this runs inside didUpdateWidget —
      // the drag-end notify reaches ancestor setState and must defer.
      _resetAll(deferDragNotify: true);
    }
    if (oldWidget.resampleMode != widget.resampleMode) {
      // P3a: flipping the switch with a box already open re-resamples on
      // the spot. Waiting for the next drag would show the old kernel's
      // picture and land the new one's.
      _scheduleFloatResample();
    }
    // Note what is NOT here: cancelling an open polygon trace on a tool
    // change. This layer does not mount for the painting tools, so on the
    // switch that matters most it is being DISPOSED rather than updated
    // and would never see it. The panel above watches the tool instead.
    // R17-①: a context change over a pending move ASKS (CSP grammar) —
    // 확정 lands the session as one undo entry, 되돌리기 puts the pixels
    // back exactly. Deferred post-frame: dialogs and history commands
    // must never run inside the build phase.
    if (oldWidget.tool != widget.tool) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        // R27 #18: an open transform box must not outlive its tool. It
        // used to stay on screen after a switch — and, worse, the stale
        // `_transform != null` made the NEXT _beginTransform bail out at
        // its own guard, so the second transform did nothing and the
        // original picture just sat there. Committing folds the affine
        // into the session (identity just closes the box).
        if (_transform != null) {
          _commitTransform();
        }
        if (_movePending) {
          _promptPendingMove();
        }
      });
    }
  }

  /// The R17-① "확정시키겠습니까?" prompt. Modal: the session stays
  /// pending until a choice lands (dismissing = confirm, the safe
  /// default — pixels keep their moved position and stay undoable).
  Future<void> _promptPendingMove() async {
    if (!mounted || !_movePending) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        // Read at call time: this layer holds no session, so the program
        // language arrives through AppText — the wording was hardcoded
        // Korean before and ignored the language setting entirely.
        final strings = AppText.strings;
        return AppConfirmDialog(
          windowKey: const ValueKey<String>('selection-move-confirm-dialog'),
          title: strings.selectionMoveConfirmTitle,
          titleIcon: Icons.open_with_outlined,
          message: strings.selectionMoveConfirmBody,
          actions: [
            AppWindowAction(
              label: strings.selectionMoveRevert,
              actionKey: const ValueKey<String>('selection-move-revert-button'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppWindowAction(
              label: strings.selectionMoveApply,
              actionKey: const ValueKey<String>('selection-move-apply-button'),
              emphasis: AppWindowActionEmphasis.primary,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (!mounted || !_movePending) {
      return;
    }
    if (confirmed == false) {
      _revertMoveSession();
    } else {
      _confirmMoveSession();
    }
  }

  @override
  void dispose() {
    _cancelFloatHold();
    widget.selectionCommands?.removeListener(_adoptChannelRegion);
    widget.selectionCommands?.unbind();
    if (_dragMode != _DragMode.none) {
      widget.onDragActiveChanged?.call(false);
    }
    // R16-①: unmounting with a pending move (tool switched to a
    // non-selection tool) CONFIRMS it. The history execute defers
    // post-frame (dispose can run inside a build); the interaction hold
    // releases NOW so a leak can never lock seeks.
    // R27 #18: an OPEN transform box at unmount used to drop its affine —
    // the stamp landed back where it was LIFTED, so the transform read as
    // "did it commit or not?". Fold the affine in first: whatever the box
    // showed is what lands.
    // P3a: `_warpedFloat` covers the quad and the mesh too, which this
    // path never did — an unmount during a perspective or mesh session
    // used to land the UNwarped float.
    final pendingStamp = _pendingLiftStamp == null
        ? null
        : (_warpedFloat() ?? _pendingLiftStamp);
    final liftId = _liftToken;
    if (pendingStamp != null && liftId != null) {
      widget.onMoveSessionPendingChanged?.call(false);
      final onConfirmed = widget.onLiftConfirmed;
      final onLanded = widget.onLiftLanded;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (onConfirmed != null) {
          onConfirmed(liftId, pendingStamp);
        } else {
          onLanded?.call(liftId, pendingStamp);
        }
      });
    }
    // The preview image is a GPU allocation and an in-flight decode holds
    // a callback into this state. Neither is reached by _clearTransform on
    // this path — dispose does not close the box, it folds it — so the
    // discard has to be explicit here or every tool switch during a
    // transform leaks a full-selection image.
    _discardFloatResample();
    _ants.dispose();
    super.dispose();
  }

  void _bindCommands() {
    widget.selectionCommands?.bind(
      hasSelection: () => _hasSelection,
      nudge: _nudge,
      deselect: _deselect,
      closePolygon: _closeOpenPolygon,
      transformActive: () => _transform != null,
      beginTransform: _beginTransform,
      beginMeshTransform: _beginMeshTransform,
      // Enter: an open Ctrl+T commits; otherwise a pending move confirms
      // (R16-①'s keyboard confirm).
      commitTransform: () {
        if (_transform != null) {
          _commitTransform();
        } else {
          _confirmMoveSession();
        }
      },
      cancelTransform: _cancelTransform,
      applyRegion: applyCommittedRegion,
      movePending: () => _movePending,
      // The THIRD caller with the button's old wiring, and the worst of
      // them: `home_page.dart` binds this to `HistoryManager
      // .onBeforeUndoRedo`, which every undo and redo runs
      // unconditionally. Bare, it landed the unwarped lift as a fresh
      // entry that the same Ctrl+Z then popped — so one keypress consumed
      // itself, the warped landing was never written, and the box was left
      // OPEN with no float and `_transform` still set, which wedges the
      // next Ctrl+T against its own guard. Measured: transformActive true,
      // movePending false, a ghost float painter still mounted, and Escape
      // the only way out.
      confirmPendingMove: () {
        if (_transform != null) {
          _commitTransform();
        }
        if (_movePending) {
          _confirmMoveSession();
        }
      },
      revertPendingMove: _revertMoveSession,
      transformValues: () {
        final transform = _transform;
        // A quad/mesh session has no affine channels (R20-D2/D3) — the
        // numeric fields blank out rather than lie.
        if (transform == null || _warpCorners != null || _meshPoints != null) {
          return null;
        }
        return (
          tx: transform.tx,
          ty: transform.ty,
          rotationDegrees: transform.rotationDegrees,
          scale: transform.sx,
        );
      },
      setTransformValues: _setTransformValues,
    );
  }

  /// Numeric transform input (R17-U tool settings): opens the session if
  /// none is up (Ctrl+T semantics — lift + box), then sets the affine
  /// outright. Enter/Escape keep their commit/revert meanings.
  void _setTransformValues({
    required double tx,
    required double ty,
    required double rotationDegrees,
    required double scale,
  }) {
    if (_warpCorners != null || _meshPoints != null) {
      // Quad/mesh mode: the control points are the only channels.
      return;
    }
    if (_transform == null) {
      _beginTransform();
    }
    final transform = _transform;
    if (transform == null) {
      return;
    }
    setState(() {
      _transform = transform.copyWith(
        tx: tx,
        ty: ty,
        rotationDegrees: rotationDegrees,
        sx: scale,
        sy: scale,
      );
    });
    _scheduleFloatResample();
    _syncAnts();
  }

  void _resetAll({bool deferDragNotify = false}) {
    final wasDragging = _dragMode != _DragMode.none;
    setState(() {
      // A pending float must not lose its pixels: land it at its pending
      // position (raw, no history) before the bookkeeping clears. Pending
      // resets are rare by construction — the session holds the seek lock.
      //
      // R28 #10: fold an OPEN box's affine in FIRST. R27 #18 taught the
      // dispose path to do this, but a cel change resets through here —
      // and this path still landed the PRE-transform stamp and then threw
      // the affine away with _clearTransform below. That is the user's
      // "룰러로 다른데 갔다오면 변형된그림은 사라져있음": the transform was
      // never wrong, it was discarded on the way out. Whatever the box
      // showed is what lands, on every exit.
      _foldOpenTransformIntoPendingStamp();
      _landPendingLiftStamp();
      _cancelDrag(notify: wasDragging && !deferDragNotify);
      _setRegion(null);
      _shapeIsImplicitWholePicture = false; // R26 #13
      _clearLiftState();
      _clearTransform();
    });
    if (deferDragNotify && wasDragging) {
      final notify = widget.onDragActiveChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notify?.call(false);
      });
    }
    _syncAnts();
  }

  // --- Perspective quad session (R20-D2, PS Ctrl+corner) --------------
  //
  // Non-null = the open box is in QUAD mode: the four corners move
  // freely, the float previews through the forward homography, Enter
  // resamples through [transformStampDabQuad]. Entered by Ctrl-grabbing
  // a corner handle; Escape/commit semantics are the affine session's.
  List<CanvasPoint>? _warpCorners;
  int? _warpDragCorner; // null while dragging inside = translate all four.
  List<CanvasPoint>? _warpDragStartCorners;

  /// The pending stamp's canvas rect corners (TL/TR/BR/BL) — the quad's
  /// BASE. Initializing corners as affine(base) makes an untouched quad
  /// exactly identity for [transformStampDabQuad].
  List<CanvasPoint>? _stampRectCorners() {
    final pending = _pendingLiftStamp;
    final stamp = pending?.stamp;
    if (pending == null || stamp == null) {
      return null;
    }
    final left = pending.center.x - stamp.width / 2;
    final top = pending.center.y - stamp.height / 2;
    return [
      CanvasPoint(x: left, y: top),
      CanvasPoint(x: left + stamp.width, y: top),
      CanvasPoint(x: left + stamp.width, y: top + stamp.height),
      CanvasPoint(x: left, y: top + stamp.height),
    ];
  }

  static const List<_TransformHandle> _cornerHandles = [
    _TransformHandle.topLeft,
    _TransformHandle.topRight,
    _TransformHandle.bottomRight,
    _TransformHandle.bottomLeft,
  ];

  int? _hitTestWarpCorner(Offset local) {
    final corners = _warpCorners;
    if (corners == null) {
      return null;
    }
    for (var i = 0; i < 4; i += 1) {
      final mapped = widget.viewport.canvasToViewport(corners[i]);
      if ((local - Offset(mapped.x, mapped.y)).distance <= _handleHitRadius) {
        return i;
      }
    }
    return null;
  }

  // --- Mesh warp session (R20-D3) --------------------------------------
  //
  // Non-null = the open box is a MESH: a 3×3-cell control grid over the
  // lifted stamp's rect; points drag freely, Enter commits through
  // [transformStampDabMesh] (the SAME fixed-diagonal triangulation).
  List<CanvasPoint>? _meshPoints;
  static const int _meshColumns = 3;
  static const int _meshRows = 3;
  int? _meshDragIndex; // null while dragging inside = translate all.
  List<CanvasPoint>? _meshDragStartPoints;

  /// Opens the mesh session (tool settings' Mesh Warp button): rides the
  /// ordinary transform open (lift + box), then swaps the chrome to the
  /// control grid.
  void _beginMeshTransform() {
    if (_transform == null) {
      _beginTransform();
    }
    if (_transform == null || _meshPoints != null) {
      return;
    }
    final base = _stampRectCorners();
    if (base == null) {
      return;
    }
    final left = base[0].x, top = base[0].y;
    final width = base[1].x - base[0].x;
    final height = base[3].y - base[0].y;
    setState(() {
      _warpCorners = null;
      _meshPoints = [
        for (var row = 0; row <= _meshRows; row += 1)
          for (var column = 0; column <= _meshColumns; column += 1)
            CanvasPoint(
              x: left + column * width / _meshColumns,
              y: top + row * height / _meshRows,
            ),
      ];
    });
    _scheduleFloatResample();
    _syncAnts();
  }

  // ---------------------------------------------------------------
  // The transform preview (P3a).
  //
  // What is on screen while a box is open is the RESAMPLED float —
  // literally the bytes Enter will write — drawn at the rect it will
  // land in, with no filtering. It used to be a Skia transform of the
  // UNtransformed float: the affine and quad previews were a widget
  // `Transform` over tiles drawn at FilterQuality.none, and the mesh
  // preview was drawVertices through an ImageShader at
  // FilterQuality.medium. So the picture on screen was nearest where
  // the commit was bicubic, and smooth where the commit was hard.
  //
  // With a resampler that can elect to preserve colours exactly, that
  // gap stops being cosmetic: the whole reason to turn AA off is to
  // SEE what you are going to get, and a preview that shows something
  // else defeats the feature it is previewing.
  //
  // Byte identity is made structural rather than numerical. The commit
  // does not recompute — it reuses this exact dab when the key still
  // matches. Two computations that ought to agree is a weaker promise,
  // and its failure mode (native on one side, Dart on the other; two
  // radius floors) is silent.

  /// What a resampled float belongs to. Any change here means the cached
  /// result is stale.
  ///
  /// The source is compared by IDENTITY, not equality: the lift stamp's
  /// buffer is immutable for its lifetime, and a value comparison of a
  /// multi-megabyte cel on every drag frame would cost more than the
  /// resample it is guarding.
  _ResampleKey? _currentResampleKey() {
    final stamp = _pendingLiftStamp?.stamp;
    if (stamp == null) {
      return null;
    }
    final mesh = _meshPoints;
    final quad = _warpCorners;
    final affine = _transform;
    final shape = StringBuffer();
    if (mesh != null) {
      shape.write('m$_meshColumns,$_meshRows');
      for (final point in mesh) {
        shape.write(':${point.x},${point.y}');
      }
    } else if (quad != null) {
      shape.write('q');
      for (final point in quad) {
        shape.write(':${point.x},${point.y}');
      }
    } else if (affine != null && !affine.isIdentity) {
      shape.write(
        'a${affine.sx},${affine.sy},${affine.rotationDegrees},'
        '${affine.tx},${affine.ty},${affine.pivot.x},${affine.pivot.y}',
      );
    } else {
      // Identity, or no box at all: the untransformed float is already
      // the right picture and the resampler has nothing to do.
      return null;
    }
    return _ResampleKey(widget.resampleMode, stamp.rgba, shape.toString());
  }

  /// The float through whatever warp is open — the ONE place the three
  /// warp functions are called from during a session.
  BrushDab? _resampleOpenTransform() {
    final pending = _pendingLiftStamp;
    if (pending == null) {
      return null;
    }
    final mesh = _meshPoints;
    if (mesh != null) {
      return transformStampDabMesh(
        pending,
        columns: _meshColumns,
        rows: _meshRows,
        points: mesh,
        mode: widget.resampleMode,
      );
    }
    final quad = _warpCorners;
    if (quad != null) {
      return transformStampDabQuad(pending, quad, mode: widget.resampleMode);
    }
    final affine = _transform;
    if (affine != null && !affine.isIdentity) {
      return transformStampDab(pending, affine, mode: widget.resampleMode);
    }
    return null;
  }

  /// The cached resample, or a fresh one — what every commit path calls
  /// so that "what you saw" and "what landed" are the same object.
  BrushDab? _warpedFloat() {
    final key = _currentResampleKey();
    if (key == null) {
      return null;
    }
    final cached = _resampledFloat;
    if (cached != null && cached.key == key) {
      return cached.dab;
    }
    return _resampleOpenTransform();
  }

  ({_ResampleKey key, BrushDab dab})? _resampledFloat;

  /// The premultiplied copy for display, and the dab it was decoded FROM.
  ///
  /// Kept as a pair, and deliberately NOT compared against
  /// [_resampledFloat]: the newest resample is computed and stored before
  /// its decode is even requested, so a guard demanding the two agree
  /// would hide the preview for the whole time a decode is in flight —
  /// which is most of a drag. The float would blink back to its
  /// untransformed self on every pointer move.
  ///
  /// Showing the last COMPLETED resample instead is both the honest
  /// picture (it is a real state the transform passed through) and the
  /// whole point of coalescing. The last scheduling always runs, so the
  /// picture just before Enter is always the exact one.
  ui.Image? _resampledFloatImage;
  BrushDab? _resampledImageDab;
  int _resampleImageRequest = 0;
  bool _resampleInFlight = false;
  bool _resampleDirty = false;

  /// Ask for the preview to catch up.
  ///
  /// Safe to call from inside a setState: it never calls setState itself.
  /// The decode callback does, and that is always a later turn.
  void _scheduleFloatResample() {
    _resampleDirty = true;
    _runFloatResampleIfIdle();
  }

  /// Coalescing is the whole design. One resample may be in flight; every
  /// pointer move that arrives while it is only sets the dirty flag, and
  /// the decode callback runs the LAST state rather than each intermediate
  /// one. Without it a drag would queue one full-canvas resample per
  /// pointer event and fall further behind with every frame.
  ///
  /// It also degrades honestly. On a machine with no native engine the
  /// Dart reference is roughly fifteen times slower, so the preview
  /// updates a few times a second while the handles and the ants stay at
  /// 60 fps — and the state just before Enter is always the exact one,
  /// because the last scheduling always runs.
  void _runFloatResampleIfIdle() {
    if (_resampleInFlight || !_resampleDirty) {
      return;
    }
    final key = _currentResampleKey();
    if (key == null) {
      _resampleDirty = false;
      if (_resampledFloat != null || _resampledFloatImage != null) {
        _discardFloatResample();
      }
      return;
    }
    if (_resampledFloat?.key == key) {
      _resampleDirty = false;
      return;
    }
    _resampleDirty = false;
    final dab = _resampleOpenTransform();
    final stamp = dab?.stamp;
    if (dab == null || stamp == null) {
      return;
    }
    _resampledFloat = (key: key, dab: dab);
    assert(_recordResampledFloat(dab));

    // decodeImageFromPixels wants premultiplied bytes; the resampler
    // produces straight alpha, which is the app's storage convention and
    // must stay that way — premultiplying the RESULT would round the very
    // colours Pick exists to carry through untouched. So the copy is for
    // display only and the dab keeps its own bytes.
    //
    // The copy and the multiply are ONE native pass into native memory,
    // the same fused kernel the fill overlay uses. Doing it as a Dart
    // `Uint8List.fromList` plus a per-pixel loop cost a second full-size
    // allocation and a second full traversal on every frame of a drag,
    // which on a whole-picture transform is tens of megabytes per pointer
    // move. The scratch is freed in the decode callback, on every path.
    final native = QaNativeEngine.instance;
    final Uint8List premultiplied;
    QaStampScratch? scratch;
    if (native != null) {
      scratch = native.premultipliedStampCopy(stamp.rgba);
      premultiplied = scratch.view;
    } else {
      premultiplied = Uint8List.fromList(stamp.rgba);
      for (var i = 0; i < premultiplied.length; i += 4) {
        final alpha = premultiplied[i + 3];
        if (alpha == 255) {
          continue;
        }
        premultiplied[i] = (premultiplied[i] * alpha + 127) ~/ 255;
        premultiplied[i + 1] = (premultiplied[i + 1] * alpha + 127) ~/ 255;
        premultiplied[i + 2] = (premultiplied[i + 2] * alpha + 127) ~/ 255;
      }
    }
    final request = ++_resampleImageRequest;
    _resampleInFlight = true;
    ui.decodeImageFromPixels(
      premultiplied,
      stamp.width,
      stamp.height,
      ui.PixelFormat.rgba8888,
      (image) {
        scratch?.free();
        _resampleInFlight = false;
        if (!mounted || request != _resampleImageRequest) {
          image.dispose();
          return;
        }
        setState(() {
          _resampledFloatImage?.dispose();
          _resampledFloatImage = image;
          _resampledImageDab = dab;
        });
        _runFloatResampleIfIdle();
      },
    );
  }

  void _discardFloatResample() {
    _resampleImageRequest += 1; // Invalidate an in-flight decode.
    _resampleDirty = false;
    _resampledFloat = null;
    _resampledImageDab = null;
    _resampledFloatImage?.dispose();
    _resampledFloatImage = null;
    // The hook holds a whole resampled cel. Letting it outlive the session
    // that made it would keep that buffer resident for as long as the app
    // runs, which is the same defect in a debug build that the assert
    // guard prevents in a release one.
    assert(_recordResampledFloat(null));
  }

  int? _hitTestMeshPoint(Offset local) {
    final points = _meshPoints;
    if (points == null) {
      return null;
    }
    for (var i = 0; i < points.length; i += 1) {
      final mapped = widget.viewport.canvasToViewport(points[i]);
      if ((local - Offset(mapped.x, mapped.y)).distance <= _handleHitRadius) {
        return i;
      }
    }
    return null;
  }

  /// The mesh's outer boundary ring (top row → right column → bottom row
  /// reversed → left column reversed) — the warped region polygon.
  List<CanvasPoint> _meshBoundary(List<CanvasPoint> points) {
    CanvasPoint at(int column, int row) =>
        points[row * (_meshColumns + 1) + column];
    return [
      for (var column = 0; column <= _meshColumns; column += 1) at(column, 0),
      for (var row = 1; row <= _meshRows; row += 1) at(_meshColumns, row),
      for (var column = _meshColumns - 1; column >= 0; column -= 1)
        at(column, _meshRows),
      for (var row = _meshRows - 1; row >= 1; row -= 1) at(0, row),
    ];
  }

  /// Closes the transform box.
  ///
  /// [keepLandedPreview] is passed by the three CONFIRM paths, and only
  /// by them: the decoded resample is the picture that just landed, so it
  /// stays to cover the frames before the base can paint it, and the
  /// float surface is not rebuilt at all — see
  /// [_holdFloatUntilCommittedCanPaint] for what that rebuild cost and
  /// why what it built could not draw. The keep is conditional on the
  /// image being `identical`ly the dab that landed, so a decode that the
  /// confirm's synchronous recompute overtook is discarded as before.
  void _clearTransform({bool keepLandedPreview = false}) {
    final landed = _pendingLiftStamp;
    final keepPreview =
        keepLandedPreview &&
        landed != null &&
        identical(_resampledImageDab, landed);
    _transform = null;
    _transformOpenedLift = false;
    _baseBoxWidth = 0;
    _baseBoxHeight = 0;
    _transformDragHandle = null;
    _transformDragStart = null;
    _transformDragStartPointer = null;
    _warpCorners = null;
    _warpDragCorner = null;
    _warpDragStartCorners = null;
    _meshPoints = null;
    _meshDragIndex = null;
    _meshDragStartPoints = null;
    if (keepPreview) {
      // The image and the dab it was decoded from stay together and stay
      // paired; only the machinery that would replace them goes.
      _resampleImageRequest += 1; // Invalidate an in-flight decode.
      _resampleDirty = false;
      _resampledFloat = null;
      _floatSurface = null;
      return;
    }
    _discardFloatResample();
    // A pending session's float must keep rendering — its pixels are NOT
    // in the base surface (they left with the lift's erase).
    //
    // ⚠️ EXCEPT on a confirm whose preview could not be kept. There
    // `_floatContentReplaced()` has just emptied the float's stale scope,
    // so a surface built here has no decoded image and nothing to borrow
    // for any of its tiles — measured on a warm-cache Ctrl+T confirm, 20
    // tiles, 0 and 0. Building it re-materialises the entire warped stamp
    // (651 ms on a 2340×1654 cel scaled to the pasteboard) to produce
    // something that cannot draw. The other callers — Escape over a
    // pending move, a tool switch — did not empty the scope, and there
    // the previous generation is a legitimate predecessor.
    final canPaintIfBuilt = !keepLandedPreview;
    _floatSurface = _movePending && canPaintIfBuilt
        ? _buildFloatSurface()
        : null;
  }

  /// True when THIS Ctrl+T session opened the lift (Escape then reverts
  /// the whole session — pixels return byte-exactly, as if Ctrl+T never
  /// happened). False when Ctrl+T rode an already-pending move (Escape
  /// only closes the box; the pending float stays).
  bool _transformOpenedLift = false;

  /// Ctrl+T: opens the free-transform box on the live selection (R19
  /// pixel model: the session lifts the shape's raster and the box
  /// manipulates the FLOAT; Enter resamples the stamp and confirms).
  void _beginTransform() {
    var region = _region;
    // R26 #13: the MOVE tool with no selection opens the box on the
    // WHOLE picture (the Ctrl+T-family entrances included).
    if (region == null &&
        widget.tool == CanvasSelectionTool.move &&
        widget.onLiftRequested != null) {
      setState(() {
        region = _adoptImplicitWholePictureShape(_wholeCanvasShape());
      });
    }
    final targetRegion = region;
    if (targetRegion == null || _transform != null) {
      return;
    }
    if (widget.onLiftRequested == null) {
      return;
    }
    final hadPendingLift = _pendingLiftStamp != null;
    if (!_ensureLifted(targetRegion)) {
      setState(_clearFailedImplicitShape);
      _syncAnts();
      return;
    }
    final box = _regionBounds(targetRegion);
    setState(() {
      _transformOpenedLift = !hadPendingLift;
      _baseBoxWidth = box.width;
      _baseBoxHeight = box.height;
      _transform = SelectionAffine(pivot: box.center);
      _floatSurface = _buildFloatSurface();
    });
    _syncAnts();
  }

  /// Enter: resamples the floating stamp through the affine (pure
  /// translations stay byte-exact) and CONFIRMS the session as ONE undo
  /// entry; identity closes the box with the session still pending.
  void _commitTransform() {
    final affine = _transform;
    final region = _region;
    final pending = _pendingLiftStamp;
    if (affine == null || region == null) {
      return;
    }
    // R20-D3: an open mesh resamples through the triangulated warp.
    // `_warpedFloat` returns the buffer the PREVIEW is already showing
    // when nothing has changed since, so Enter lands the same bytes the
    // screen held rather than a second computation that ought to match.
    final meshPoints = _meshPoints;
    if (meshPoints != null && pending != null) {
      final warped = _warpedFloat() ?? pending;
      if (identical(warped, pending)) {
        setState(_clearTransform);
        _syncAnts();
        return;
      }
      final boundary = _meshBoundary(meshPoints);
      _floatContentReplaced();
      setState(() {
        _pendingLiftStamp = warped;
        // A warped region collapses to its boundary polygon: the mesh
        // maps the LIFTED pixels, so what is selected afterwards is the
        // warped outline, not the old step list.
        _setRegion(CanvasSelectionRegion.shape(CanvasSelectionShape(boundary)));
        _moveSessionDirty = true;
        _clearTransform(keepLandedPreview: true);
      });
      _confirmMoveSession();
      return;
    }
    // R20-D2: an open quad resamples through the homography instead.
    final warpCorners = _warpCorners;
    if (warpCorners != null && pending != null) {
      final warped = _warpedFloat() ?? pending;
      if (identical(warped, pending)) {
        // Untouched (or degenerate) quad: close the box, session pends on.
        setState(_clearTransform);
        _syncAnts();
        return;
      }
      final base = _stampRectCorners();
      final h = base == null ? null : solveHomography(base, warpCorners);
      _floatContentReplaced();
      setState(() {
        _pendingLiftStamp = warped;
        _setRegion(
          h == null
              ? CanvasSelectionRegion.shape(CanvasSelectionShape(warpCorners))
              : region.mapped((point) => _applyHomography(h, point)),
        );
        _moveSessionDirty = true;
        _clearTransform(keepLandedPreview: true);
      });
      _confirmMoveSession();
      return;
    }
    if (!affine.isIdentity && pending != null) {
      _floatContentReplaced();
      setState(() {
        _pendingLiftStamp = _warpedFloat() ?? pending;
        _setRegion(region.mapped(affine.apply));
        _moveSessionDirty = true;
        _clearTransform(keepLandedPreview: true);
      });
      _confirmMoveSession();
      return;
    }
    setState(_clearTransform);
    _syncAnts();
  }

  /// Escape: discards the open transform. A lift the Ctrl+T itself
  /// opened (and that never moved otherwise) reverts whole — the picture
  /// returns byte-exactly.
  void _cancelTransform() {
    if (_transform == null) {
      return;
    }
    if (_transformOpenedLift && !_moveSessionDirty && _movePending) {
      setState(_clearTransform);
      _revertMoveSession();
      return;
    }
    setState(_clearTransform);
    _syncAnts();
  }

  void _syncAnts() {
    final animate = _hasSelection || _dragMode == _DragMode.marquee;
    if (animate && !_ants.isAnimating) {
      _ants.repeat();
    } else if (!animate && _ants.isAnimating) {
      _ants.stop();
    }
    // Every mutation path funnels through here — the settings panel's
    // numeric fields track the session via this (deferred) ping.
    widget.selectionCommands?.notifySessionChanged();
  }

  void _deselect() {
    if (!_hasSelection && _dragMode == _DragMode.none) {
      return;
    }
    final before = _region;
    // R26 #13: the implicit whole-picture shape was never a user
    // selection — dropping it records no history.
    final wasImplicit = _shapeIsImplicitWholePicture;
    _resetAll();
    // Deselecting a real region is undoable, symmetric with selecting.
    if (before != null && !wasImplicit) {
      final commit = widget.onShapeCommitted;
      if (commit != null) {
        commit(before, null);
      }
    }
  }

  /// Arrow nudge: one canvas pixel per call, one undo entry per call.
  /// With an open Ctrl+T session the nudge rides the session's
  /// translation instead (committed with the transform).
  void _nudge(double dx, double dy) {
    final transform = _transform;
    if (transform != null) {
      setState(() {
        _transform = transform.copyWith(
          tx: transform.tx + dx,
          ty: transform.ty + dy,
        );
      });
      // The preview is a resampled bitmap now, not a matrix evaluated in
      // build, so a mutation that does not schedule a resample moves the
      // ants and the box while the PICTURE stays where it was — and Enter
      // then lands the ink where the outline is, not where the artwork
      // was drawn. Every path that changes the open warp has to say so.
      _scheduleFloatResample();
      return;
    }
    final region = _region;
    if (region == null || widget.onLiftRequested == null) {
      return;
    }
    if (!_ensureLifted(region)) {
      return;
    }
    _commitMove(dx: dx, dy: dy);
  }

  /// R14-④/R15-④: lifts the shape's pixels once per selection-or-confirm
  /// — the host commits the ERASE (origin vanishes) and hands back the
  /// stamp, which floats until the session confirms. False = nothing
  /// under the shape to move.
  bool _ensureLifted(CanvasSelectionRegion region) {
    if (!_shapeNeedsLift) {
      return _pendingLiftStamp != null;
    }
    final lift = widget.onLiftRequested!(region);
    _shapeNeedsLift = false;
    if (lift == null) {
      _clearLiftState();
      return false;
    }
    _liftToken = lift.liftToken;
    // A fresh lift is a picture this scope has never seen — except at the
    // coordinates it took whole, where the surface it copied from IS this
    // float's own previous generation. Emptying and then seeding says
    // both things in the right order.
    _floatContentReplaced();
    BitmapTileImageCache.instance.seedScope(
      _floatStaleScope,
      lift.wholeTiles,
    );
    _pendingLiftStamp = lift.stampDab;
    _moveSessionDirty = false;
    _moveSessionStartShape = region;
    widget.onMoveSessionPendingChanged?.call(true);
    return true;
  }

  /// The transform float's stale-fallback lineage — ONE object for every
  /// float this app ever lifts.
  ///
  /// A scope per generation would be worse than none: the cache retains
  /// eight and evicts the least recent, so a session of transforms would
  /// push out the `(layerId, frameId)` buckets the brush depends on.
  static final Object _floatStaleScope = Object();

  /// Empties [_floatStaleScope] — call wherever the float is about to
  /// hold a DIFFERENT picture, never where it holds the same one
  /// somewhere else.
  ///
  /// That distinction is the whole fix. `_floatSurface` is rebuilt from
  /// an empty surface at five sites, and three of them regenerate a
  /// float that already exists — a drag release, every arrow-key nudge,
  /// and Ctrl+T over a pending move. There the previous generation IS a
  /// legitimate predecessor and borrowing it is correct; refusing to
  /// borrow left a float wider than the painter's four-tile per-pixel
  /// budget three-quarters blank for a frame, and a held arrow key
  /// strobed it thirty times a second. Only a LIFT, and a warp that
  /// resamples the stamp, give the float a picture its scope has never
  /// seen.
  void _floatContentReplaced() {
    // A hold from the previous session must not survive into this one, or
    // it would clear the float that just replaced the one it was watching.
    _cancelFloatHold();
    BitmapTileImageCache.instance.resetScope(_floatStaleScope);
  }

  VoidCallback? _floatHold;

  void _cancelFloatHold() {
    // The clip goes with the hold. A leftover set would clip the NEXT
    // float — `_floatContentReplaced` cancels a hold precisely because a
    // new lift is taking the old one's place.
    _floatHoldTiles = null;
    final hold = _floatHold;
    if (hold == null) {
      return;
    }
    _floatHold = null;
    BitmapTileImageCache.instance.removeListener(hold);
  }

  /// Keeps the float on screen until the host's committed surface can
  /// paint what the session just landed.
  ///
  /// The stamp's destination tiles are brand-new objects, so they have no
  /// decoded image for a frame or two, and the base painter's stale
  /// fallback answers for them with the tiles the LIFT ERASED — emptiness
  /// where the artwork should be. Measured, the whole selection vanished
  /// for two frames on every confirm.
  ///
  /// Holding rather than opting out is the point: an opt-out only moves
  /// the base onto its per-pixel path, which covers four tiles a frame and
  /// leaves a full-canvas commit unpainted. The float already holds these
  /// exact bytes at this exact place, so it is the correct picture, not a
  /// stand-in for one.
  ///
  /// The hold covers exactly the tiles the base cannot paint yet, and
  /// shrinks as they arrive: see [CanvasSelectionLayer
  /// .committedRegionPendingTiles] for why a bool was not enough.
  ///
  /// On the Ctrl+T (warped) path what is held is the decoded RESAMPLE —
  /// one image of exactly the bytes that landed, at exactly the rect they
  /// landed in — rather than a float surface rebuilt from the warped
  /// stamp. That rebuild was two defects in one line: it re-materialised
  /// the whole stamp a second time (the confirm is already landing those
  /// same pixels; measured 651 ms of a 2,060 ms confirm frame on a
  /// 2340×1654 cel scaled to the pasteboard) and it produced all-new
  /// tiles with no cache entries, so what it built could not paint —
  /// measured 6 tiles, 0 decoded, 0 borrowable.
  ///
  /// ⚠️ The resample image is kept only when it IS what landed
  /// (`identical` on the dab it was decoded from). It is deliberately the
  /// last COMPLETED resample and a synchronous recompute on the confirm
  /// can overtake it, so holding it unconditionally would paint one
  /// transform state over another — a wrong picture where today there is
  /// an absent one. When it does not match, the old float rebuild still
  /// runs.
  void _holdFloatUntilCommittedCanPaint(BrushDab landed) {
    _cancelFloatHold();
    // The pending stamp is gone by now, so the float's drift has to come
    // from the dab that actually landed.
    _floatHoldCentre = landed.center;
    final stamp = landed.stamp;
    if (stamp == null) {
      setState(_releaseFloatHold);
      return;
    }
    // The landing rect, by the same arithmetic the stamp blend uses.
    final left = (landed.center.x - stamp.width / 2).round();
    final top = (landed.center.y - stamp.height / 2).round();
    final right = left + stamp.width;
    final bottom = top + stamp.height;
    // FIRST, and before the pending set is read: every coordinate this
    // answers for is one the base can now paint, so it drops out of the
    // hold instead of being covered — which is also what keeps the two
    // from compositing the same partial-alpha pixels twice. It runs even
    // when the host offers no pending-tile hook, because giving the base
    // a picture is worth doing whether or not anything is covering for it.
    final compose = widget.composeCommittedRegionPictures;
    if (compose != null) {
      final ink = _landedInkPainter(landed, left, top);
      if (ink != null) {
        compose(left, top, right, bottom, ink);
      }
    }
    final pendingTiles = widget.committedRegionPendingTiles;
    if (pendingTiles == null) {
      setState(_releaseFloatHold);
      return;
    }
    final initial = pendingTiles(left, top, right, bottom);
    if (initial.isEmpty) {
      setState(_releaseFloatHold);
      return;
    }
    void release() {
      if (!mounted) {
        _cancelFloatHold();
        return;
      }
      final still = pendingTiles(left, top, right, bottom);
      if (still.isEmpty) {
        _cancelFloatHold();
        setState(_releaseFloatHold);
        return;
      }
      if (still.length == _floatHoldTiles?.length) {
        // Same count means the same set here: tiles only ever leave it.
        return;
      }
      setState(() => _floatHoldTiles = still);
    }

    setState(() => _floatHoldTiles = initial);
    _floatHold = release;
    BitmapTileImageCache.instance.addListener(release);
  }

  /// The picture of the landing that this session is holding, ready to be
  /// composed into the base's new tiles — or null when it has none.
  ///
  /// The two branches are the two things a confirm can be holding, and
  /// they are the same two the hold itself draws:
  ///
  ///  - the decoded RESAMPLE, when it is `identical`ly the dab that
  ///    landed. One image of exactly the landed bytes at exactly the
  ///    landed rect.
  ///  - the FLOAT SURFACE, for a move, which is materialized once at
  ///    [_floatSurfaceCentre] and translated afterwards. The delta is
  ///    taken in CANVAS space from the centre the pixels were made at to
  ///    the centre they landed at — not [_floatDrawOffset], which is the
  ///    same journey in screen space and carries the viewport's rotation
  ///    and zoom with it.
  ///
  /// A live drag is not a landing: `_moveScreenDelta` is zeroed when the
  /// gesture ends, so a non-zero one here means the float is somewhere
  /// this arithmetic does not describe.
  ProvisionalInkPainter? _landedInkPainter(BrushDab landed, int left, int top) {
    final resampled = _resampledFloatImage;
    if (resampled != null && identical(_resampledImageDab, landed)) {
      return inkFromImage(
        resampled,
        Rect.fromLTWH(
          left.toDouble(),
          top.toDouble(),
          resampled.width.toDouble(),
          resampled.height.toDouble(),
        ),
      );
    }
    final float = _floatSurface;
    final from = _floatSurfaceCentre;
    final stamp = landed.stamp;
    if (float == null ||
        from == null ||
        stamp == null ||
        _moveScreenDelta != Offset.zero) {
      return null;
    }
    // ⚠️ The delta between the two ROUNDED placements, not the difference
    // of the centres. Both materializations put the stamp at
    // `(centre - size/2).round()`, so the pixels moved by a whole number
    // of pixels even when the centres differ by a fraction — and half a
    // pixel of drift would resample the float against the grid it is
    // supposed to line up with exactly.
    final floatLeft = (from.x - stamp.width / 2).round();
    final floatTop = (from.y - stamp.height / 2).round();
    return inkFromSurface(
      float,
      Offset((left - floatLeft).toDouble(), (top - floatTop).toDouble()),
    );
  }

  /// Drops everything the hold was keeping alive. Call inside a setState.
  ///
  /// Both, always: whichever of the two the confirm chose to hold, the
  /// other is already null, and a kept resample image that outlived its
  /// hold would keep painting over the base for the rest of the session.
  void _releaseFloatHold() {
    _floatHoldTiles = null;
    _floatHoldCentre = null;
    _floatSurface = null;
    _floatSurfaceCentre = null;
    _discardFloatResample();
  }

  /// While non-null, the float paints ONLY these tile coordinates — the
  /// ones the base surface cannot paint yet.
  Set<TileCoord>? _floatHoldTiles;

  /// [_floatHoldTiles] as one screen-space path, or null when nothing is
  /// held.
  ///
  /// The tile size comes from the float's own surface where there is one
  /// and from the host's committed geometry otherwise — the held resample
  /// is a single image with no grid of its own, and the tiles being waited
  /// on are the BASE's.
  ui.Path? _floatHoldClipPath() {
    final tiles = _floatHoldTiles;
    if (tiles == null || tiles.isEmpty) {
      return null;
    }
    final size = (_floatSurface ?? BitmapSurface(canvasSize: widget.canvasSize))
        .tileSize
        .toDouble();
    final path = ui.Path();
    for (final coord in tiles) {
      final topLeft = widget.viewport.canvasToViewport(
        CanvasPoint(x: coord.x * size, y: coord.y * size),
      );
      final bottomRight = widget.viewport.canvasToViewport(
        CanvasPoint(x: (coord.x + 1) * size, y: (coord.y + 1) * size),
      );
      path.addRect(
        Rect.fromLTRB(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y),
      );
    }
    return path;
  }

  /// R28 #10: resamples the pending stamp through an OPEN transform box,
  /// so an exit that lands the float lands what the box SHOWED.
  ///
  /// Every path that ends a session while a box is open needs this — the
  /// dispose path grew its own copy in R27 #18 and the cel-change reset
  /// did not, which is why a transform survived a tool switch but
  /// evaporated when the user navigated away and back.
  void _foldOpenTransformIntoPendingStamp() {
    final affine = _transform;
    final pending = _pendingLiftStamp;
    if (affine == null || pending == null || affine.isIdentity) {
      return;
    }
    _floatContentReplaced();
    _pendingLiftStamp = _warpedFloat() ?? pending;
    final region = _region;
    if (region != null) {
      _setRegion(region.mapped(affine.apply));
    }
  }

  /// Abandon fallback: land the floating stamp at its CURRENT pending
  /// position (raw, no history) so the pixels are never lost. Ordinary
  /// session ends go through the confirm.
  void _landPendingLiftStamp() {
    final id = _liftToken;
    final pending = _pendingLiftStamp;
    if (id == null || pending == null) {
      return;
    }
    widget.onLiftLanded?.call(id, pending);
    _pendingLiftStamp = null;
    _liftToken = null;
  }

  CanvasPoint _toCanvas(Offset local) =>
      widget.viewport.viewportToCanvas(ViewportPoint(x: local.dx, y: local.dy));

  void _handlePointerDown(PointerDownEvent event) {
    if (_activePointer != null) {
      // A second TOUCH is the navigate signal (same rule as strokes):
      // cancel the selection drag and let the gesture layer take over.
      if (event.kind == PointerDeviceKind.touch &&
          _dragMode != _DragMode.none) {
        setState(() => _cancelDrag(notify: true));
        _syncAnts();
      }
      return;
    }
    if (event.buttons != kPrimaryButton &&
        event.kind != PointerDeviceKind.touch) {
      return;
    }
    final canvasPoint = _toCanvas(event.localPosition);
    var transform = _transform;
    // R17-U 핸들 상시: with the always-on box (Move tool), grabbing a
    // scale/rotate HANDLE promotes the implicit box into a real session
    // on the spot — the lift happens here, at the first interaction.
    if (transform == null &&
        widget.alwaysShowTransformBox &&
        widget.tool == CanvasSelectionTool.move &&
        widget.onLiftRequested != null) {
      // R26 #13: with NO selection the always-on box frames the WHOLE
      // picture — grabbing one of its handles opens the session on the
      // implicit whole-canvas shape.
      final implicitRegion =
          _region ?? CanvasSelectionRegion.shape(_wholeCanvasShape());
      final box = _regionBounds(implicitRegion);
      _baseBoxWidth = box.width;
      _baseBoxHeight = box.height;
      final implicit = SelectionAffine(pivot: box.center);
      final handle = _hitTestTransformHandle(event.localPosition, implicit);
      if (handle != null && handle != _TransformHandle.inside) {
        if (_region == null) {
          setState(
            () => _adoptImplicitWholePictureShape(
              implicitRegion.steps.first.shape,
            ),
          );
        }
        final hadPendingLift = _pendingLiftStamp != null;
        if (!_ensureLifted(implicitRegion)) {
          _baseBoxWidth = 0;
          _baseBoxHeight = 0;
          setState(_clearFailedImplicitShape);
          _syncAnts();
          return;
        }
        setState(() {
          _transformOpenedLift = !hadPendingLift;
          _transform = implicit;
          _floatSurface = _buildFloatSurface();
        });
        transform = implicit;
      } else {
        // Inside/miss: fall through to the ordinary move-drag flow.
        _baseBoxWidth = 0;
        _baseBoxHeight = 0;
      }
    }
    if (transform != null) {
      // The open box is modal: only the box's handles/inside react;
      // clicks elsewhere are inert until Enter/Escape closes the session.
      final openTransform = transform;
      // R20-D3: an open MESH session hit-tests its control points +
      // inside the boundary only.
      final meshPoints = _meshPoints;
      if (meshPoints != null) {
        final pointIndex = _hitTestMeshPoint(event.localPosition);
        if (pointIndex == null &&
            !CanvasSelectionShape(
              _meshBoundary(meshPoints),
            ).containsPoint(canvasPoint)) {
          return;
        }
        _activePointer = event.pointer;
        setState(() {
          _dragMode = _DragMode.transform;
          _meshDragIndex = pointIndex;
          _meshDragStartPoints = List.of(meshPoints);
          _transformDragStartPointer = canvasPoint;
        });
        widget.onDragActiveChanged?.call(true);
        return;
      }
      // R20-D2: an open QUAD session hit-tests its corners + inside only
      // (rotate/edge handles have no meaning on a free quad).
      final warpCorners = _warpCorners;
      if (warpCorners != null) {
        final cornerIndex = _hitTestWarpCorner(event.localPosition);
        if (cornerIndex == null &&
            !CanvasSelectionShape(warpCorners).containsPoint(canvasPoint)) {
          return;
        }
        _activePointer = event.pointer;
        setState(() {
          _dragMode = _DragMode.transform;
          _warpDragCorner = cornerIndex;
          _warpDragStartCorners = List.of(warpCorners);
          _transformDragStartPointer = canvasPoint;
        });
        widget.onDragActiveChanged?.call(true);
        return;
      }
      final handle = _hitTestTransformHandle(
        event.localPosition,
        openTransform,
      );
      if (handle == null) {
        return;
      }
      // R20-D2: Ctrl+corner switches the box into the perspective quad
      // (the PS gesture) — corners initialize at the affine positions of
      // the pending stamp's rect, so an untouched quad stays identity.
      if (_cornerHandles.contains(handle) &&
          HardwareKeyboard.instance.isControlPressed) {
        final base = _stampRectCorners();
        if (base != null) {
          final corners = [
            for (final corner in base) openTransform.apply(corner),
          ];
          _activePointer = event.pointer;
          setState(() {
            _warpCorners = corners;
            _dragMode = _DragMode.transform;
            _warpDragCorner = _cornerHandles.indexOf(handle);
            _warpDragStartCorners = List.of(corners);
            _transformDragStartPointer = canvasPoint;
          });
          // Entering quad mode carries the affine's rotation and scale
          // into the corners, so the picture already differs from the
          // untransformed float — the preview must catch up before the
          // first drag move arrives.
          _scheduleFloatResample();
          widget.onDragActiveChanged?.call(true);
          return;
        }
      }
      _activePointer = event.pointer;
      setState(() {
        _dragMode = _DragMode.transform;
        _transformDragHandle = handle;
        _transformDragStart = openTransform;
        _transformDragStartPointer = canvasPoint;
        if (handle == _TransformHandle.rotate) {
          _transformLastAngle = _pointerAngleAbout(canvasPoint, openTransform);
        }
      });
      widget.onDragActiveChanged?.call(true);
      return;
    }
    final region = _region;
    if (widget.tool == CanvasSelectionTool.move) {
      // The MOVE tool drags the selected content; outside a REAL region
      // it does nothing (R11-⑧). R26 #13 revises the no-selection half:
      // with no region at all, a press inside the canvas targets the
      // WHOLE picture through the implicit whole-canvas shape.
      var targetShape = region;
      if (targetShape == null) {
        // A press anywhere on the PASTEBOARD grabs the whole picture (PS
        // move grammar) — the implicit shape itself may be the tighter
        // ink bounds, which would make small drawings fiddly to grab.
        //
        // The pasteboard, not the canvas rect: the box this press opens
        // frames pasteboard ink now, and its HANDLES were already
        // grabbable out there (_hitTestTransformHandle has no such
        // gate), so a canvas-only gate meant the drawing you could see
        // framed was one you could not grab by pressing on it.
        final onStage = widget.canvasSize.containsPasteboardPoint(
          x: canvasPoint.x,
          y: canvasPoint.y,
        );
        if (widget.onLiftRequested == null || !onStage) {
          return;
        }
        setState(() {
          targetShape = _adoptImplicitWholePictureShape(_wholeCanvasShape());
        });
      } else if (!targetShape.containsPoint(canvasPoint)) {
        return;
      }
      final liftShape = targetShape;
      // R14-④/R19 pixel model: the shape's PIXELS are the content — the
      // first gesture on a selection (or on a confirmed landing) lifts
      // them fresh from the current raster.
      if (liftShape == null ||
          widget.onLiftRequested == null ||
          !_ensureLifted(liftShape)) {
        setState(_clearFailedImplicitShape);
        _syncAnts();
        return;
      }
      _activePointer = event.pointer;
      setState(() {
        _dragMode = _DragMode.move;
        _moveScreenDelta = Offset.zero;
        _floatSurface = _buildFloatSurface();
      });
    } else if (_tapsVertices) {
      // The polygon places points; it has no drag verb at all, so the
      // press only records where the tap aimed and the release decides
      // what it meant.
      _activePointer = event.pointer;
      setState(() {
        _dragMode = _DragMode.vertexTap;
        _vertexTapStart = event.localPosition;
      });
    } else {
      // The marquee tools ALWAYS draw a NEW polygon — even starting
      // inside the current region (moving lives on the Move tool). The
      // region already selected STAYS on screen through the drag (R26
      // #16: with add/subtract/intersect the user must see what the new
      // polygon is about to fold into — the PS/CSP read), and the RELEASE
      // records the combination as one undoable step. A pending move
      // session confirms first (R16-①: never revert, always confirm).
      _confirmMoveSession();
      _activePointer = event.pointer;
      setState(() {
        _dragMode = _DragMode.marquee;
        // Nothing to stash while cutting: the drag never touches the
        // region, so there is nothing for a cancel to put back.
        _shapeBeforeMarquee = widget.tool == CanvasSelectionTool.cut
            ? null
            : _region;
        _marqueeStart = canvasPoint;
        _marqueeCurrent = canvasPoint;
        _lassoPoints = [canvasPoint];
      });
    }
    widget.onDragActiveChanged?.call(true);
    _syncAnts();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    switch (_dragMode) {
      case _DragMode.none:
        return;
      case _DragMode.vertexTap:
        // Nothing follows the pointer: the vertex was aimed on the way
        // down and only the release decides whether it lands.
        return;
      case _DragMode.marquee:
        setState(() {
          final canvasPoint = _toCanvas(event.localPosition);
          _marqueeCurrent = canvasPoint;
          if (_tracesPointerPath) {
            _lassoPoints = [..._lassoPoints, canvasPoint];
          }
        });
      case _DragMode.move:
        setState(() => _moveScreenDelta += event.delta);
      case _DragMode.transform:
        _updateTransformDrag(_toCanvas(event.localPosition));
    }
  }

  /// Every branch below mutates the open warp, and every one of them must
  /// then ask the preview to catch up. Wrapping rather than sprinkling the
  /// call through five early returns is the difference between "the mesh
  /// preview stopped updating" being impossible and being a future bug.
  void _updateTransformDrag(CanvasPoint pointer) {
    _updateTransformDragGeometry(pointer);
    _scheduleFloatResample();
  }

  void _updateTransformDragGeometry(CanvasPoint pointer) {
    // R20-D3 mesh drag: one control point follows the pointer, or
    // (inside) the whole grid translates.
    final meshStart = _meshDragStartPoints;
    if (_meshPoints != null && meshStart != null) {
      final startPointer = _transformDragStartPointer;
      if (startPointer == null) {
        return;
      }
      final dx = pointer.x - startPointer.x;
      final dy = pointer.y - startPointer.y;
      final index = _meshDragIndex;
      setState(() {
        _meshPoints = [
          for (var i = 0; i < meshStart.length; i += 1)
            index == null || index == i
                ? CanvasPoint(x: meshStart[i].x + dx, y: meshStart[i].y + dy)
                : meshStart[i],
        ];
      });
      _syncAnts();
      return;
    }
    // R20-D2 quad drag: one corner follows the pointer, or (inside) all
    // four translate together.
    final warpStart = _warpDragStartCorners;
    if (_warpCorners != null && warpStart != null) {
      final startPointer = _transformDragStartPointer;
      if (startPointer == null) {
        return;
      }
      final dx = pointer.x - startPointer.x;
      final dy = pointer.y - startPointer.y;
      final corner = _warpDragCorner;
      setState(() {
        _warpCorners = [
          for (var i = 0; i < 4; i += 1)
            corner == null || corner == i
                ? CanvasPoint(x: warpStart[i].x + dx, y: warpStart[i].y + dy)
                : warpStart[i],
        ];
      });
      _syncAnts();
      return;
    }
    final handle = _transformDragHandle;
    final start = _transformDragStart;
    final startPointer = _transformDragStartPointer;
    if (handle == null || start == null || startPointer == null) {
      return;
    }
    switch (handle) {
      case _TransformHandle.inside:
        setState(() {
          _transform = start.copyWith(
            tx: start.tx + pointer.x - startPointer.x,
            ty: start.ty + pointer.y - startPointer.y,
          );
        });
      case _TransformHandle.rotate:
        // Wrapped-delta accumulation (the camera lever rule): continuous
        // across the ±180° seam. Canvas-space angles, so the P8 view
        // rotation/flip never skews the feel.
        final current = _transform ?? start;
        final angle = _pointerAngleAbout(pointer, current);
        var delta = angle - _transformLastAngle;
        while (delta > 180) {
          delta -= 360;
        }
        while (delta < -180) {
          delta += 360;
        }
        _transformLastAngle = angle;
        setState(() {
          _transform = current.copyWith(
            rotationDegrees: current.rotationDegrees + delta,
          );
        });
      default:
        setState(() => _transform = _solveScaleDrag(start, handle, pointer));
    }
  }

  /// Solves the scale drag: the grabbed handle lands under the pointer
  /// while the anchor — the OPPOSITE handle, or the center with Alt —
  /// stays fixed (its motion folds into the translation). Shift locks the
  /// aspect on corner handles.
  SelectionAffine _solveScaleDrag(
    SelectionAffine start,
    _TransformHandle handle,
    CanvasPoint pointer,
  ) {
    final grabbed = _handleLocal(handle, _baseBoxWidth, _baseBoxHeight)!;
    final centerPivot = HardwareKeyboard.instance.isAltPressed;
    final anchorLocal = centerPivot
        ? CanvasPoint(x: 0, y: 0)
        : CanvasPoint(x: -grabbed.x, y: -grabbed.y);
    final anchorCanvas = start.apply(
      CanvasPoint(
        x: start.pivot.x + anchorLocal.x,
        y: start.pivot.y + anchorLocal.y,
      ),
    );
    final radians = start.rotationDegrees * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    // v = R(−θ)·(pointer − anchor): the pointer in the box's local frame.
    final dx = pointer.x - anchorCanvas.x;
    final dy = pointer.y - anchorCanvas.y;
    final vx = dx * cos + dy * sin;
    final vy = -dx * sin + dy * cos;

    var sx = start.sx;
    var sy = start.sy;
    if (grabbed.x != anchorLocal.x) {
      sx = vx / (grabbed.x - anchorLocal.x);
    }
    if (grabbed.y != anchorLocal.y) {
      sy = vy / (grabbed.y - anchorLocal.y);
    }
    if (HardwareKeyboard.instance.isShiftPressed &&
        grabbed.x != anchorLocal.x &&
        grabbed.y != anchorLocal.y) {
      final magnitude = math.max(sx.abs(), sy.abs());
      sx = sx.isNegative ? -magnitude : magnitude;
      sy = sy.isNegative ? -magnitude : magnitude;
    }
    sx = _clampScale(sx);
    sy = _clampScale(sy);

    // Anchor compensation: R·(S_old∘o − S_new∘o) folds into t.
    final dLocalX = start.sx * anchorLocal.x - sx * anchorLocal.x;
    final dLocalY = start.sy * anchorLocal.y - sy * anchorLocal.y;
    return start.copyWith(
      sx: sx,
      sy: sy,
      tx: start.tx + dLocalX * cos - dLocalY * sin,
      ty: start.ty + dLocalX * sin + dLocalY * cos,
    );
  }

  static double _clampScale(double scale) {
    if (scale.isNaN || !scale.isFinite) {
      return 0.01;
    }
    if (scale.abs() < 0.01) {
      return scale.isNegative ? -0.01 : 0.01;
    }
    return scale;
  }

  /// The pointer's canvas-space angle about the transformed box center.
  double _pointerAngleAbout(CanvasPoint pointer, SelectionAffine affine) {
    final center = affine.apply(affine.pivot);
    return math.atan2(pointer.y - center.y, pointer.x - center.x) *
        180 /
        math.pi;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    switch (_dragMode) {
      case _DragMode.none:
        break;
      case _DragMode.marquee:
        _finishMarquee();
      case _DragMode.move:
        _finishMove();
      case _DragMode.transform:
        // The session stays open across drags; Enter/Escape close it.
        break;
      case _DragMode.vertexTap:
        _placeVertex();
    }
    setState(() => _cancelDrag(notify: true));
    _syncAnts();
  }

  /// A polygon tap has come off: close the trace if it aimed at the first
  /// vertex, otherwise extend it.
  void _placeVertex() {
    final commands = widget.selectionCommands;
    final down = _vertexTapStart;
    _vertexTapStart = null;
    if (commands == null || down == null) {
      return;
    }
    final tapped = _toCanvas(down);
    final points = commands.polygonPoints;
    if (commands.canClosePolygon && _aimsAtCloseTarget(down, points.first)) {
      _closeOpenPolygon();
      return;
    }
    if (points.isEmpty) {
      // Starting a fresh outline, like the first press of a marquee drag:
      // a pending move confirms rather than reverts (R16-①).
      _confirmMoveSession();
    }
    commands.addPolygonPoint(tapped);
  }

  /// Closes an open polygon trace: the outline goes wherever this verb
  /// puts outlines, and the trace is over either way. False when there was
  /// nothing open — the confirm that asked then means what it usually
  /// means.
  ///
  /// Fewer than three vertices encloses nothing, so a confirm there ends
  /// the trace without committing anything rather than leaving it up.
  bool _closeOpenPolygon() {
    final commands = widget.selectionCommands;
    if (commands == null || !commands.hasOpenPolygon) {
      return false;
    }
    final drawn = commands.takePolygonShape();
    if (drawn != null) {
      _commitDrawnOutline(drawn, before: _region);
    }
    _syncAnts();
    return true;
  }

  /// Whether a tap at [local] (screen space) lands on the close ring drawn
  /// over [first].
  ///
  /// Screen space, matching the ring: the target must be the same size to
  /// the hand at every zoom, and it is drawn at a fixed screen radius.
  bool _aimsAtCloseTarget(Offset local, CanvasPoint first) {
    final mapped = widget.viewport.canvasToViewport(first);
    final dx = local.dx - mapped.x;
    final dy = local.dy - mapped.y;
    return dx * dx + dy * dy <=
        SelectionAntsPainter.closeTargetRadius *
            SelectionAntsPainter.closeTargetRadius;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) {
      return;
    }
    setState(() => _cancelDrag(notify: true));
    _syncAnts();
  }

  /// Clears drag bookkeeping (NOT the committed selection, and NOT an
  /// open Ctrl+T session — its float persists between handle drags).
  void _cancelDrag({required bool notify}) {
    final wasDragging = _dragMode != _DragMode.none;
    // R16-①: the move SESSION survives the gesture — the float keeps
    // rendering at its pending position until the user confirms.
    // A CANCELLED marquee leaves the region exactly as the drag found it
    // (a finished one consumed the stash in _finishMarquee).
    if (_dragMode == _DragMode.marquee && _shapeBeforeMarquee != null) {
      _setRegion(_shapeBeforeMarquee);
      _shapeNeedsLift = true;
    }
    _shapeBeforeMarquee = null;
    _dragMode = _DragMode.none;
    _activePointer = null;
    _marqueeStart = null;
    _marqueeCurrent = null;
    _lassoPoints = const [];
    _moveScreenDelta = Offset.zero;
    _transformDragHandle = null;
    _transformDragStart = null;
    _transformDragStartPointer = null;
    if (_transform == null && !_movePending) {
      _floatSurface = null;
    }
    if (notify && wasDragging) {
      widget.onDragActiveChanged?.call(false);
    }
  }

  /// The mode this drag folds under (R26 #16): the tool setting, unless
  /// the PS/CSP modifier chord overrides it for this one drag — Shift
  /// adds, Alt subtracts, Shift+Alt intersects. The modifiers are read at
  /// RELEASE, matching how both apps behave when you change your mind
  /// mid-drag. (Neither key means anything else on a marquee: Alt's
  /// temporary eyedropper is gated to painting tools, and Shift/Alt only
  /// steer an OPEN transform box, never a marquee.)
  SelectionCombineMode _marqueeMode() {
    final keyboard = HardwareKeyboard.instance;
    final shift = keyboard.isShiftPressed;
    final alt = keyboard.isAltPressed;
    if (shift && alt) {
      return SelectionCombineMode.intersect;
    }
    if (shift) {
      return SelectionCombineMode.add;
    }
    if (alt) {
      return SelectionCombineMode.subtract;
    }
    return widget.selectionCommands?.combineMode ??
        SelectionCombineMode.defaultMode;
  }

  void _finishMarquee() {
    final before = _shapeBeforeMarquee;
    _shapeBeforeMarquee = null;
    _commitDrawnOutline(_marqueeShape(), before: before);
  }

  /// Where every finished outline lands, whoever traced it — a marquee
  /// drag, a lasso, or a closed polygon. The tracing is the only part that
  /// differs between shapes; what a finished outline MEANS is the verb's.
  void _commitDrawnOutline(
    CanvasSelectionShape? drawn, {
    required CanvasSelectionRegion? before,
  }) {
    // The CUT verb stops here: the outline goes to the slot and the
    // selection is left alone. 유저 확정: "잘라내기는 잘라내기만이야. 그러니
    // 선택으로 남지 않아" — so there is no combine mode to apply, no
    // history entry to record (a cut is not a selection change), and no
    // stashed shape to consume.
    if (widget.tool == CanvasSelectionTool.cut) {
      if (drawn != null) {
        widget.onCutShape?.call(drawn);
      }
      return;
    }
    // R26 #16: the drawn polygon FOLDS into the region under the active
    // mode. A click (degenerate polygon) still deselects in 갱신 mode —
    // Photoshop's click-away — and is inert in the other three.
    final after = CanvasSelectionRegion.combine(before, drawn, _marqueeMode());
    if (before == null && after == null) {
      return;
    }
    if (before == after) {
      // Nothing folded (a click in add/subtract/intersect): no history.
      return;
    }
    // The change routes through ONE undoable step (R11-⑧: selecting is
    // an undoable action); without a history host it applies directly.
    final commit = widget.onShapeCommitted;
    if (commit != null) {
      commit(before, after);
    } else {
      applyCommittedRegion(after);
    }
  }

  /// Adopts a committed region — called by the selection history command
  /// on execute/undo/redo (and directly without a history host).
  void applyCommittedRegion(CanvasSelectionRegion? region) {
    if (!mounted) {
      return;
    }
    // A committed region change over a pending move confirms it first
    // (deselect, Ctrl+D, a new region from undo/redo — R16-①).
    _confirmMoveSession();
    setState(() {
      _setRegion(region);
      _shapeNeedsLift = region != null;
      _clearLiftState();
      if (region == null) {
        _clearTransform();
      }
    });
    _syncAnts();
  }

  /// Whether the active shape IS the pointer's path (points accumulate as
  /// the drag runs) rather than being derived from its two corners.
  ///
  /// Exhaustive on purpose: a new [CanvasShapeKind] fails to compile here
  /// until it has said which kind of drag it is.
  bool get _tracesPointerPath => switch (widget.shapeKind) {
    CanvasShapeKind.rect => false,
    CanvasShapeKind.ellipse => false,
    CanvasShapeKind.lasso => true,
    CanvasShapeKind.polygon => false,
  };

  /// Whether the active shape is TAPPED out vertex by vertex rather than
  /// dragged. The polygon is the only shape with no drag verb at all: a
  /// press places a point and the outline stays open until it is closed,
  /// which is why its trace has to outlive this widget (see
  /// [CanvasSelectionCommands.polygonPoints]).
  bool get _tapsVertices => switch (widget.shapeKind) {
    CanvasShapeKind.rect => false,
    CanvasShapeKind.ellipse => false,
    CanvasShapeKind.lasso => false,
    CanvasShapeKind.polygon => true,
  };

  /// The in-progress or final marquee polygon; null while degenerate.
  ///
  /// This is the one place a shape kind turns into geometry — every other
  /// site asks a predicate rather than branching on the kind itself.
  CanvasSelectionShape? _marqueeShape() {
    switch (widget.shapeKind) {
      case CanvasShapeKind.lasso:
        if (_lassoPoints.length < 3) {
          return null;
        }
        return CanvasSelectionShape(_lassoPoints);
      case CanvasShapeKind.polygon:
        // Tapped out, not dragged: its outline is the channel's open trace
        // and it is built when the trace CLOSES, not while a drag runs.
        return null;
      case CanvasShapeKind.rect:
      case CanvasShapeKind.ellipse:
        final start = _marqueeStart;
        final current = _marqueeCurrent;
        if (start == null || current == null) {
          return null;
        }
        // A click (or a drag too small to have meant one) is degenerate for
        // both box shapes — an ellipse in a 1px box is not a thinner
        // ellipse, it is nothing.
        if ((current.x - start.x).abs() < 2 &&
            (current.y - start.y).abs() < 2) {
          return null;
        }
        return widget.shapeKind == CanvasShapeKind.ellipse
            ? CanvasSelectionShape.ellipse(
                left: start.x,
                top: start.y,
                right: current.x,
                bottom: current.y,
              )
            : CanvasSelectionShape.rect(
                left: start.x,
                top: start.y,
                right: current.x,
                bottom: current.y,
              );
    }
  }

  void _finishMove() {
    if (_moveScreenDelta == Offset.zero) {
      return;
    }
    final canvasDelta = widget.viewport.viewportDeltaToCanvasDelta(
      dx: _moveScreenDelta.dx,
      dy: _moveScreenDelta.dy,
    );
    _commitMove(dx: canvasDelta.x, dy: canvasDelta.y);
  }

  void _commitMove({required double dx, required double dy}) {
    final region = _region;
    final pending = _pendingLiftStamp;
    if (region == null || pending == null || (dx == 0 && dy == 0)) {
      return;
    }
    // R16-① TVP move session: a drag/nudge only moves the FLOAT — nothing
    // lands and nothing is undoable until the confirm. The ants go red.
    setState(() {
      _pendingLiftStamp = pending.copyWith(
        center: CanvasPoint(x: pending.center.x + dx, y: pending.center.y + dy),
      );
      _moveSessionDirty = true;
      // ⚠️ NO rebuild. This used to re-materialize the whole stamp onto a
      // fresh surface at the new centre, on every drag release and every
      // arrow nudge — and the tiles it made were new objects with no
      // decoded images, so what replaced a float that could paint was one
      // that could not. Measured on the confirm frame of a wide move:
      // 44% of the landing absent. A move is a translation; the surface
      // stays where it was built and [_floatDrawOffset] carries it.
      _setRegion(region.translated(dx: dx, dy: dy));
    });
    _syncAnts();
  }

  static CanvasPoint _applyHomography(Float64List h, CanvasPoint point) {
    final w = h[6] * point.x + h[7] * point.y + h[8];
    if (w.abs() < 1e-12) {
      return point;
    }
    return CanvasPoint(
      x: (h[0] * point.x + h[1] * point.y + h[2]) / w,
      y: (h[3] * point.x + h[4] * point.y + h[5]) / w,
    );
  }

  /// A base-local point mapped through [affine] into viewport space.
  Offset _mapLocalToViewport(SelectionAffine affine, CanvasPoint local) {
    final canvasPoint = affine.apply(
      CanvasPoint(x: affine.pivot.x + local.x, y: affine.pivot.y + local.y),
    );
    final mapped = widget.viewport.canvasToViewport(canvasPoint);
    return Offset(mapped.x, mapped.y);
  }

  static const List<_TransformHandle> _scaleHandles = [
    _TransformHandle.topLeft,
    _TransformHandle.topRight,
    _TransformHandle.bottomRight,
    _TransformHandle.bottomLeft,
    _TransformHandle.topEdge,
    _TransformHandle.rightEdge,
    _TransformHandle.bottomEdge,
    _TransformHandle.leftEdge,
  ];

  Offset _rotateKnobOffset(SelectionAffine affine) =>
      _rotateKnobOffsetFor(affine, _baseBoxHeight);

  Offset _rotateKnobOffsetFor(SelectionAffine affine, double boxHeight) {
    final topMid = _mapLocalToViewport(
      affine,
      CanvasPoint(x: 0, y: -boxHeight / 2),
    );
    final centerMapped = widget.viewport.canvasToViewport(
      affine.apply(affine.pivot),
    );
    final direction = topMid - Offset(centerMapped.x, centerMapped.y);
    final distance = direction.distance;
    final unit = distance == 0 ? const Offset(0, -1) : direction / distance;
    return topMid + unit * _rotateLeverLength;
  }

  /// The transformed box as a canvas-space polygon (inside = translate).
  CanvasSelectionShape _transformedBoxShape(SelectionAffine affine) =>
      _boxShapeFor(affine, _baseBoxWidth, _baseBoxHeight);

  CanvasSelectionShape _boxShapeFor(
    SelectionAffine affine,
    double width,
    double height,
  ) {
    return CanvasSelectionShape([
      for (final corner in [
        CanvasPoint(x: -width / 2, y: -height / 2),
        CanvasPoint(x: width / 2, y: -height / 2),
        CanvasPoint(x: width / 2, y: height / 2),
        CanvasPoint(x: -width / 2, y: height / 2),
      ])
        affine.apply(
          CanvasPoint(
            x: affine.pivot.x + corner.x,
            y: affine.pivot.y + corner.y,
          ),
        ),
    ]);
  }

  /// The region's axis-aligned bounds (box geometry for the transform
  /// chrome — R17-U always-on handles use it without opening a session).
  ///
  /// [CanvasSelectionRegion.selectedBounds], never the coverage superset:
  /// the box has to frame what the ants trace, so a 삭제 that cuts an edge
  /// band off the selection pulls the box in with it (유저 실기 ㉝).
  ({double width, double height, CanvasPoint center}) _regionBounds(
    CanvasSelectionRegion region,
  ) {
    final bounds = region.selectedBounds;
    return (
      width: math.max(bounds.right - bounds.left, 1),
      height: math.max(bounds.bottom - bounds.top, 1),
      center: CanvasPoint(
        x: (bounds.left + bounds.right) / 2,
        y: (bounds.top + bounds.bottom) / 2,
      ),
    );
  }

  _TransformHandle? _hitTestTransformHandle(
    Offset local,
    SelectionAffine affine,
  ) {
    if ((local - _rotateKnobOffset(affine)).distance <= _handleHitRadius) {
      return _TransformHandle.rotate;
    }
    for (final handle in _scaleHandles) {
      final position = _mapLocalToViewport(
        affine,
        _handleLocal(handle, _baseBoxWidth, _baseBoxHeight)!,
      );
      if ((local - position).distance <= _handleHitRadius) {
        return handle;
      }
    }
    if (_transformedBoxShape(affine).containsPoint(_toCanvas(local))) {
      return _TransformHandle.inside;
    }
    return null;
  }

  /// The floating lift stamp rendered alone (the live float shown while
  /// moving) — the base no longer draws it, the float draws exactly it
  /// (R15-④), so there is never a double image.
  BitmapSurface _buildFloatSurface() {
    final surface = BitmapSurface(canvasSize: widget.canvasSize);
    final pending = _pendingLiftStamp;
    // Recorded HERE so every rebuild site zeroes the drift by
    // construction — [_floatDrawOffset] measures from the place the
    // surface was actually materialized at, not from the lift, so a
    // rebuild mid-session cannot leave an offset applied twice.
    _floatSurfaceCentre = pending?.center;
    if (pending == null) {
      return surface;
    }
    return materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: BrushDabSequence([pending]),
    ).surface;
  }

  /// Canvas-space centre [_floatSurface]'s pixels were materialized at.
  CanvasPoint? _floatSurfaceCentre;

  /// The landed centre while a hold is up — the pending stamp is gone by
  /// then, but the float still has to be drawn where it landed.
  CanvasPoint? _floatHoldCentre;

  /// Where the float is drawn relative to its own surface: the live drag
  /// offset, plus the drift its stamp has accumulated since the surface
  /// was built.
  ///
  /// A move used to rebuild the surface at the new centre, which is what
  /// made the confirm frame blank: the rebuilt tiles are new objects with
  /// no decoded images, so the held float could paint only the painter's
  /// four-tile budget and 44% of a wide landing was simply absent. The
  /// surface's tiles decode ONCE now and a translation is a translation.
  ///
  /// ⚠️ The drift is mapped through [CanvasViewport.canvasDeltaToViewportDelta],
  /// which carries rotation and flip, and it is applied INSIDE the hold's
  /// ClipPath: the clip is a screen-space mask over the base's not-yet-
  /// paintable tiles, and what has to fill it is whatever the float shows
  /// there AFTER the offset.
  Offset get _floatDrawOffset {
    final from = _floatSurfaceCentre;
    final to = _pendingLiftStamp?.center ?? _floatHoldCentre;
    if (from == null || to == null) {
      return _moveScreenDelta;
    }
    final drift = widget.viewport.canvasDeltaToViewportDelta(
      dx: to.x - from.x,
      dy: to.y - from.y,
    );
    return _moveScreenDelta + Offset(drift.x, drift.y);
  }

  @override
  Widget build(BuildContext context) {
    final floatSurface = _floatSurface;
    final transform = _transform;
    final region = _region;
    final warpCorners = _warpCorners;
    // The image and the dab it was decoded from travel together, so the
    // rect the preview draws into always belongs to the pixels in it.
    final resampledImage = _resampledFloatImage;
    final resampledDab = _resampledImageDab;
    // With an open Ctrl+T session the ants show the TRANSFORMED region
    // and the box chrome renders around the transformed base box. An
    // open QUAD (R20-D2) maps the region through the homography instead.
    var displayShape = transform != null && region != null
        ? region.mapped(transform.apply)
        : region;
    if (warpCorners != null && region != null) {
      final base = _stampRectCorners();
      final h = base == null ? null : solveHomography(base, warpCorners);
      displayShape = h == null
          ? CanvasSelectionRegion.shape(CanvasSelectionShape(warpCorners))
          : region.mapped((point) => _applyHomography(h, point));
    }
    final meshPoints = _meshPoints;
    if (meshPoints != null) {
      // Mesh session: the ants trace the grid's warped boundary.
      displayShape = CanvasSelectionRegion.shape(
        CanvasSelectionShape(_meshBoundary(meshPoints)),
      );
    }
    // R17-U 핸들 상시: with the Move tool a selection shows its box
    // chrome even before any session opens (identity affine around the
    // shape bounds; grabbing a handle opens the session at that moment).
    var chromeAffine = transform;
    var chromeWidth = _baseBoxWidth;
    var chromeHeight = _baseBoxHeight;
    if (chromeAffine == null &&
        widget.alwaysShowTransformBox &&
        widget.tool == CanvasSelectionTool.move &&
        _dragMode == _DragMode.none) {
      // R26 #13: no selection = the box frames the WHOLE picture (the
      // canvas rect) — grabbing a handle opens the implicit session.
      final bounds = _regionBounds(
        region ?? CanvasSelectionRegion.shape(_wholeCanvasShape()),
      );
      chromeAffine = SelectionAffine(pivot: bounds.center);
      chromeWidth = bounds.width;
      chromeHeight = bounds.height;
    }
    // Mesh chrome (R20-D3): the warped boundary with EVERY control point
    // as a handle. The float previews unwarped in v1 — the grid + ants
    // carry the warp read; Enter shows the exact result (the commit and
    // any future drawVertices preview share the same triangulation).
    // Quad chrome (R20-D2): the free quadrilateral with its four corner
    // handles only — edges and the rotate knob have no quad meaning.
    final chrome = meshPoints != null
        ? (
            box: [
              for (final point in _meshBoundary(meshPoints))
                _mapCanvasToViewportOffset(point),
            ],
            handles: [
              for (final point in meshPoints) _mapCanvasToViewportOffset(point),
            ],
            knob: null as Offset?,
          )
        : warpCorners != null
        ? (
            box: [
              for (final point in warpCorners)
                _mapCanvasToViewportOffset(point),
            ],
            handles: [
              for (final point in warpCorners)
                _mapCanvasToViewportOffset(point),
            ],
            knob: null as Offset?,
          )
        : chromeAffine == null
        ? null
        : (
            box: [
              for (final point in _boxShapeFor(
                chromeAffine,
                chromeWidth,
                chromeHeight,
              ).points)
                _mapCanvasToViewportOffset(point),
            ],
            handles: [
              for (final handle in _scaleHandles)
                _mapLocalToViewport(
                  chromeAffine,
                  _handleLocal(handle, chromeWidth, chromeHeight)!,
                ),
            ],
            knob: _rotateKnobOffsetFor(chromeAffine, chromeHeight) as Offset?,
          );
    // While a hold is up, whichever float is drawn is drawn ONLY over the
    // tiles the base cannot paint yet — screen space, because it wraps
    // the painters rather than living inside one of them, and both
    // painters apply the viewport themselves.
    final holdClip = _floatHoldClipPath();
    Widget clipToHold(Widget child) => holdClip == null
        ? child
        : ClipPath(clipper: _StaticPathClipper(holdClip), child: child);
    return Listener(
      key: const ValueKey<String>('canvas-selection-layer'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Stack(
        children: [
          // P3a: with a warp open the preview IS the resampled result,
          // drawn unfiltered at the rect it will land in. Affine, quad
          // and mesh alike — one painter, because there is no longer any
          // per-mode screen approximation to differ between them.
          if (resampledImage != null && resampledDab != null)
            Positioned.fill(
              child: IgnorePointer(
                child: clipToHold(
                  CustomPaint(
                  key: const ValueKey<String>('transform-resample-preview'),
                  painter: _ResampledFloatPainter(
                    image: resampledImage,
                    // The landing rect, computed the way the stamp blend
                    // computes it: the dab centre rounded to an integer
                    // top-left. Previewing at the unrounded position
                    // would put a sub-pixel Ctrl+T on screen half a pixel
                    // from where it lands.
                    left: (resampledDab.center.x - resampledImage.width / 2)
                        .round()
                        .toDouble(),
                    top: (resampledDab.center.y - resampledImage.height / 2)
                        .round()
                        .toDouble(),
                    viewport: widget.viewport,
                    canvasSize: widget.canvasSize,
                  ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            )
          // A pure MOVE drag has no warp: the translation is byte-exact
          // by short circuit, so a screen-space offset of the untouched
          // float IS the result and costs nothing.
          //
          // `_floatHold != null` is the fourth reason to draw it, and the
          // only one that outlives the session: after a confirm the stamp
          // has landed but its destination tiles have no decoded image
          // yet, so the base cannot paint what it was just handed. The
          // float can — it holds those exact bytes at that exact place —
          // and the hold releases the moment the base is ready. Without
          // this clause the session ends, `_movePending` goes false, and
          // the artwork is on screen nowhere for two frames.
          else if (floatSurface != null &&
              (_dragMode == _DragMode.move ||
                  transform != null ||
                  _movePending ||
                  _floatHold != null))
            Positioned.fill(
              child: IgnorePointer(
                child: clipToHold(
                  Transform(
                  transform: Matrix4.translationValues(
                    _floatDrawOffset.dx,
                    _floatDrawOffset.dy,
                    0,
                  ),
                  child: CustomPaint(
                    painter: BitmapSurfacePainter(
                      surface: floatSurface,
                      viewport: widget.viewport,
                      showTransparentBackground: false,
                      // ONE scope for every float this app ever lifts, and
                      // it is emptied when a lift gives the float new
                      // pixels — see [_floatStaleScope]. Without a scope
                      // at all, which is what this was, the float shared
                      // the null bucket with every float ever lifted, so
                      // opening a second transform painted the FIRST one's
                      // artwork at the first one's place and size:
                      // measured, 36 pixels of ink where this float's own
                      // surface is empty.
                      //
                      // ⚠️ That ghost is a DUPLICATE, not a move. The base
                      // painter's own fallback is on and its
                      // (layerId, frameId) bucket still holds the
                      // pre-erase tiles, so on the same frame it redraws
                      // the artwork in place — 48 ink pixels over a base
                      // surface that contains none. How much of the
                      // reported "teleport" this accounts for is still
                      // open; what is measured is the ghost. ⚠️ Both
                      // painters have to be recorded in ONE synchronous
                      // burst: an await between them lets the pending
                      // decodes land and the base reads zero, which is how
                      // an earlier version of this comment came to claim
                      // the base drew nothing.
                      staleScope: _floatStaleScope,
                    ),
                    child: const SizedBox.expand(),
                  ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: SelectionAntsPainter(
                  repaint: _ants,
                  viewport: widget.viewport,
                  committedRegion: displayShape,
                  screenOffset: _dragMode == _DragMode.move
                      ? _moveScreenDelta
                      : Offset.zero,
                  marqueeShape: _dragMode == _DragMode.marquee
                      ? _marqueeShape()
                      : null,
                  openTrail: _tapsVertices
                      ? (widget.selectionCommands?.polygonPoints ?? const [])
                      : _dragMode == _DragMode.marquee && _tracesPointerPath
                      ? _lassoPoints
                      : const [],
                  closeTarget:
                      _tapsVertices &&
                          (widget.selectionCommands?.canClosePolygon ?? false)
                      ? widget.selectionCommands!.polygonPoints.first
                      : null,
                  transformChrome: chrome,
                  movePendingDirty: _movePending && _moveSessionDirty,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // R16-①: the CONFIRM button — floats at the selection's top
          // right while a move session is pending.
          if (_movePending && displayShape != null)
            Positioned(
              left: _confirmButtonOffset(displayShape).dx,
              top: _confirmButtonOffset(displayShape).dy,
              child: Material(
                key: const ValueKey<String>('selection-move-confirm'),
                color: _moveSessionDirty
                    ? const Color(0xFFFF4444)
                    : const Color(0xFF2ECC71),
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  // The button is offered while a transform box is OPEN —
                  // its visibility test is `_movePending`, which says
                  // nothing about `_transform`. Wired straight to
                  // `_confirmMoveSession` it landed the unwarped lift: the
                  // artwork committed at its PRE-transform position and
                  // size, the warped preview kept painting on top until
                  // something closed the box, and the wrong landing went
                  // into history. Enter has branched on this since R16-①;
                  // the button never did.
                  //
                  // Both `if`s, not Enter's single branch. `_commitTransform`
                  // on an identity affine only closes the box and leaves
                  // the session pending, so Enter's form would make one tap
                  // of a button labelled "confirm" into two. With both, a
                  // warped box commits warped (the inner confirm fires and
                  // the outer no-ops on a null pending stamp) and an
                  // untouched box closes and confirms in one tap.
                  onTap: () {
                    if (_transform != null) {
                      _commitTransform();
                    }
                    if (_movePending) {
                      _confirmMoveSession();
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.check, size: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Confirm button anchor: just outside the selection bbox's top-right,
  /// following the live drag offset. Anchored to what is actually
  /// selected — the button rides the same corner the box draws.
  Offset _confirmButtonOffset(CanvasSelectionRegion region) {
    final bounds = region.selectedBounds;
    final mapped = _mapCanvasToViewportOffset(
      CanvasPoint(x: bounds.right, y: bounds.top),
    );
    final dragOffset = _dragMode == _DragMode.move
        ? _moveScreenDelta
        : Offset.zero;
    return mapped + dragOffset + const Offset(8, -34);
  }

  Offset _mapCanvasToViewportOffset(CanvasPoint point) {
    final mapped = widget.viewport.canvasToViewport(point);
    return Offset(mapped.x, mapped.y);
  }
}

/// The transform preview (P3a): the RESAMPLED float, drawn at the canvas
/// rect it will land in, through the ordinary viewport transform.
///
/// `FilterQuality.none` is not a performance choice — it is the contract.
/// The image already holds the destination pixels, one for one, so any
/// filtering here would show the user something other than the bytes Enter
/// is about to write. Zoomed in that means visible blocks, which is
/// correct: those blocks ARE the result. This replaced three different
/// screen approximations (a widget `Transform` for the affine, a
/// homography matrix for the quad, and a `drawVertices` mesh at
/// `FilterQuality.medium`), none of which agreed with the commit and none
/// of which agreed with each other.
class _ResampledFloatPainter extends CustomPainter {
  _ResampledFloatPainter({
    required this.image,
    required this.left,
    required this.top,
    required this.viewport,
    required this.canvasSize,
  });

  final ui.Image image;

  /// Canvas-space top-left of the landing rect.
  final double left;
  final double top;

  final CanvasViewport viewport;
  final CanvasSize canvasSize;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(viewportTransformMatrix(viewport).storage);
    // The pasteboard wall, because the landing clips there too
    // (`bitmap_surface_brush_commit`): a selection dragged past the stage
    // edge loses those pixels on Enter, and a preview that kept showing
    // them would be promising something the commit will not deliver.
    canvas.clipRect(
      Rect.fromLTRB(
        canvasSize.pasteboardLeft.toDouble(),
        canvasSize.pasteboardTop.toDouble(),
        canvasSize.pasteboardRightExclusive.toDouble(),
        canvasSize.pasteboardBottomExclusive.toDouble(),
      ),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(left, top, image.width.toDouble(), image.height.toDouble()),
      Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ResampledFloatPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.left != left ||
      oldDelegate.top != top ||
      oldDelegate.viewport != viewport ||
      oldDelegate.canvasSize != canvasSize;
}

/// Clips to a path the caller already computed in screen space.
///
/// The hold's path is rebuilt whenever the set of tiles the base cannot
/// paint changes, so identity is the right question to ask here: a new
/// path means new tiles.
class _StaticPathClipper extends CustomClipper<ui.Path> {
  const _StaticPathClipper(this.path);

  final ui.Path path;

  @override
  ui.Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant _StaticPathClipper oldClipper) =>
      !identical(oldClipper.path, path);
}
