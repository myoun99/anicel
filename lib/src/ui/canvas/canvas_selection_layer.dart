import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'
    show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart';

import '../../core/point_bounds.dart';
import '../../models/bitmap_surface.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_dab_sequence.dart';
import '../../models/brush_stamp_image.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/drawing_guide.dart';
import '../../models/transform_values.dart';
import '../../models/viewport_point.dart';
import 'dart:math' as math;

import '../../models/app_input_settings.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../text/app_strings.dart';
import '../../services/bitmap_surface_brush_commit.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/guide_geometry.dart';
import '../../services/resample/resample_kernel.dart';
import '../../services/stamp_carry.dart';
import '../../services/transform_box_law.dart';
import '../../models/pasteboard_bounds.dart';
import '../brush/canvas_selection_commands.dart';
import '../brush/transform_tool_options.dart';
import 'box_chrome.dart' show SelectionTransformChrome;
import 'box_on_screen.dart';
import 'float_warp.dart';
import 'selection_ants_painter.dart';
import 'selection_drag.dart';
import 'transform_box.dart';
import 'selection_float_overlay.dart';
import 'bitmap_surface_painter.dart';
import 'tile_pyramid.dart';
import '../effective_device_pixel_ratio.dart';
import '../input/control_press_claim.dart';
import '../input/value_control_pointers.dart';
import '../widgets/app_icon_button.dart';
import 'canvas_press.dart';
import 'canvas_target_pill.dart';
import 'canvas_viewport_offset.dart';

/// The P9 selection interaction layer, mounted over the canvas while a
/// selection tool is active (Photoshop/CSP language):
///
/// - Dragging on empty ground draws a NEW region — rectangle marquee or
///   freehand lasso — shown as marching ants.
/// - Dragging INSIDE the region moves the selection's PIXELS (R19 pixel
///   model): the shape's raster lifts once (erase lands raw, the stamp
///   floats), every drag/Ctrl+T only moves the float, and the CONFIRM
///   adopts the whole session as ONE history entry.
/// - A click (degenerate drag) deselects; Ctrl+D arrives through
///   [selectionCommands].
/// - A move to another frame, row or cut KEEPS the region (F-86); the next
///   move lifts it afresh from the cel it then stands on.
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
    this.onFillShape,
    this.onDrawShape,
    this.onPressNeedsCel,
    this.symmetry,
    this.selectionCommands,
    this.onDragActiveChanged,
    this.onTransformDragActiveChanged,
    this.onLiftRequested,
    this.onLiftLanded,
    this.onLiftConfirmed,
    this.onLiftReverted,
    this.alwaysShowTransformBox = false,
    this.contentBoundsProvider,
    this.transformOptions = TransformToolOptions.defaults,
    this.floatOverlay,
    this.oneFingerAction,
    this.pillCover = EdgeInsets.zero,
  });

  /// The edges of this layer that something else stands on — the panels
  /// lying on the floor, the panel's own capsules — which the 확정/취소
  /// pill keeps out from under ([CanvasTargetPill.cover]). Zero = the
  /// whole layer is open.
  final EdgeInsets pillCover;

  /// Where the FLOAT's pixels go (TS1): the composite that draws the active
  /// layer reads this and draws them at that layer's depth, so the layers
  /// above occlude the live preview exactly as they occlude the committed
  /// result.
  ///
  /// Null = no composite behind this layer (the conte, the timesheet, the cut
  /// envelope, and tests that mount the layer alone). The float then draws
  /// itself here, from the same description — the mount point differs, the
  /// drawing does not.
  final SelectionFloatOverlay? floatOverlay;

  /// The host's own one-finger answer — a finger drives this layer only
  /// where that answer is draw ([AppInput.toolAcceptsPointer]). Null = the
  /// user's slot.
  final CanvasTouchDragAction? oneFingerAction;

  /// The transform tool's knobs: which of 일반/퍼스/메쉬 the box is in, how
  /// the resample turns pixels into other pixels (the tent mean that
  /// smooths, or the coverage argmax that copies source words through
  /// untouched so a two-value drawing stays two-valued), and the mesh grid
  /// size.
  ///
  /// All of it is a property of the TOOL, not a declaration about the
  /// layer's content — nothing here inspects the picture to decide.
  final TransformToolOptions transformOptions;

  ResampleMode get _resampleMode => transformOptions.resampleMode;

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

  /// A finished SHAPE FILL outline. Same arrangement as [onCutShape] and
  /// for the same reason: the host paints the outline, and the committed
  /// selection is not touched. The undo it leaves behind is the fill
  /// itself, arriving through the stroke funnel like any other mark.
  final ValueChanged<CanvasSelectionShape>? onFillShape;

  /// A finished SHAPE-TOOL drag (I-69): the path the host strokes with the
  /// brush in hand. The selection is not touched, and the undo it leaves
  /// behind is the stroke's — the same arrangement as [onFillShape].
  ///
  /// ⚠️A PATH, not an outline: the line is two ends with no inside, so it
  /// is no [CanvasSelectionShape] at all ([MarqueeDrag.path]).
  final ValueChanged<DrawnShapePath>? onDrawShape;

  /// Asks the host for a cel to draw on, for a press of the SHAPE tool on a
  /// frame that has none: true when one was made, false when none could be
  /// — and then the host has said why. Null where a cel is already there,
  /// or the host makes none.
  ///
  /// 🚨WHOEVER HEARS THE PRESS ASKS FOR THE CEL, AND ONLY ONE DOES (I-10).
  /// The shape tool's drag is this layer's, and this layer lies over the
  /// drawing view — which stands down on an empty frame and would have
  /// asked — so it asks in the view's stead, AT THE PRESS, as the text
  /// tool's layer does. The cel is there by the release, so the shape lands
  /// inside the event that lifts the pen and takes the block made for it
  /// into its own step of undo; asked at the release, the block would be
  /// settled as a step of its own before the shape could claim it.
  final bool Function()? onPressNeedsCel;

  /// The symmetry guide acting right now, in CANVAS coordinates — an
  /// outline drawn here is copied by it the same way a stroke is.
  ///
  /// ⚠️Canvas space, not the artwork space the drawing view's guides are
  /// mapped into: this layer's geometry never leaves canvas coordinates
  /// (see the class doc), so the axis must not either.
  final SymmetryShape? symmetry;

  final CanvasSelectionCommands? selectionCommands;

  /// Raised while a selection drag is in progress (the panel holds
  /// viewport gestures exactly like during a stroke).
  final ValueChanged<bool>? onDragActiveChanged;

  /// Raised while a TRANSFORM handle drag is in progress, which is the one
  /// case where touch must also stand down — see the touch branch of
  /// [_handlePointerDown] for why an extra finger there is ignored rather
  /// than obeyed.
  final ValueChanged<bool>? onTransformDragActiveChanged;

  /// R14-④/R15-④ bitmap lift: called ONCE per selection shape when the
  /// Move tool first drags it. The host commits the shape's
  /// ERASE (origin pixels vanish immediately) and returns that command's
  /// id plus the lifted STAMP dab, which the layer floats until the
  /// session confirms — so the original is never visible while moving and
  /// a reverted/zero-move session restores it exactly. Null return = the
  /// shape covers no pixels: the move is a no-op. R19 pixel model: every
  /// session lifts fresh from the CURRENT raster (a confirmed move's next
  /// move re-lifts the landed pixels — byte-identical by construction).
  ///
  /// 🪦Until 2026-09-17 the answer also carried `preLift`, the surface the
  /// lift copied from — the predecessor of every tile of the float built
  /// from this stamp (F-68), which was how that float painted on its first
  /// frame. A float's tiles picture themselves inside the paint now.
  final ({int liftToken, BrushDab stampDab})? Function(
    CanvasSelectionRegion region,
  )?
  onLiftRequested;

  /// Raw landing of the floating stamp at its pending position (no
  /// history entry) — the abandon fallback so a reset can never lose the
  /// float's pixels.
  final void Function(int liftToken, BrushDab stampDab)? onLiftLanded;

  /// CONFIRM of a move session (R16-①): the host lands [stampDab] and
  /// adopts the whole session (raw lift + landed stamp) as ONE history
  /// entry (BrushLiftMoveHistoryCommand).
  /// ⚠️The TRANSFORM travels with the stamp ([StampCarry]): the cels a
  /// range confirm reaches never floated anything, so they need the whole
  /// of it to apply to their own pixels — a displacement read off the stamp
  /// loses the scale and the rotation entirely (유저 2026-09-22, 실기), and
  /// the affine alone loses a quad's or a mesh's warp.
  final void Function(int liftToken, BrushDab stampDab, StampCarry? carry)?
  onLiftConfirmed;

  /// REVERT (R17-①): the host restores the pre-lift picture byte-exactly;
  /// nothing lands in history.
  final void Function(int liftToken)? onLiftReverted;


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

  /// Hands the finished outline to [CanvasSelectionLayer.onFillShape] to be
  /// painted, and — like [cut] — leaves the selection alone. Filling a
  /// shape you drew is not selecting it.
  fillShape,

  /// Hands the finished drag's PATH to [CanvasSelectionLayer.onDrawShape]
  /// to be stroked, and leaves the selection alone (I-69, the shape tool).
  drawShape,
}

/// Why a move session ended. ⛔Not a flag: the three are three different
/// things to tell the HOST, and the whole of F-164 was one of them being
/// told nothing.
enum _SessionEnd {
  /// The float lands and the session becomes ONE history entry.
  confirm,

  /// The user took it back — the picture returns to what it was.
  revert,

  /// The float is dropped without landing: its pixels belong to a cel the
  /// panel is no longer standing on (유저 확정 2026-09-17: a frame walk
  /// 「착지안하고 편집중 그대로 유지」), or nothing was done to them and they
  /// are the cel as it stands ([_CanvasSelectionLayerState._endLanded]).
  letGo,
}

/// One open move session, as ONE value.
///
/// ⛔[stamp] and [moved] are mutable because a drag changes them while the
/// session stays the same session; [token] and [startShape] are what the
/// session IS and cannot change without it being a different one.
class _MoveSession {
  _MoveSession({
    required this.token,
    required this.stamp,
    required this.startShape,
  }) : _lifted = stamp;

  /// The lift command owning this selection's pixels (R15-④).
  final int token;

  /// The stamp dab currently FLOATING — removed from the command so the
  /// base never shows it (no double image).
  BrushDab stamp;

  /// The float as it was lifted, to ask [holdsAChange] of.
  final BrushDab _lifted;

  /// Whether the float is anything but the pixels that were lifted — a
  /// session that holds none lands nothing
  /// ([_CanvasSelectionLayerState._endLanded]).
  ///
  /// ⛔Asked of the float itself. [landed] is written by the same fold and
  /// would read the same today, but it answers another question — what the
  /// range's other cels are to be put through — and one flag answering two
  /// is how a third writer breaks one of them.
  bool get holdsAChange => !identical(stamp, _lifted);

  /// The region as the session found it — the revert restores it, and the
  /// transform draws it as the green 「before」 outline (I-38).
  final CanvasSelectionRegion? startShape;

  /// True once the session actually MOVED.
  bool moved = false;

  /// What the confirm landed with, as a mapping of the canvas — for the
  /// cels the confirm reaches that this session never floated.
  ///
  /// 🚨★★★**THE OTHER CELS NEED THE WHOLE TRANSFORM, NOT ITS SHADOW.**
  /// 유저 2026-09-22, from a hands-on run: 「이동+확대하고 둘다 동시적용
  /// 해봤는데 **한쪽 값의 확대가 사라졌어. 이동은 남아있는데**」. The host
  /// could only read a DISPLACEMENT off the stamp it was handed — the
  /// scale and the rotation live in the affine and never travelled — so a
  /// pure ×2 moved the other cels by nothing at all.
  ///
  /// ↩️It was the box's AFFINE until 2026-10-06 — the whole of an 일반
  /// transform and the shadow of the other two: under 퍼스 and 메쉬 the
  /// affine is the identity while the corners or the grid carry the warp,
  /// so a warp confirmed over a range bent the cel you stood on and left
  /// the rest as they were (`a-warp-over-a-frame-range-lands-on-one-cel`).
  /// A [StampCarry] is whichever of the three the box was doing.
  ///
  /// ⚠️Recorded at the confirm because the box is cleared before the host
  /// hears about it, and the pivot has to be the box's — 유저: 「확대/축소의
  /// 기준점은 **항상 상자의 중심**」, and with a range live that is the one
  /// box on screen.
  StampCarry? landed;
}

/// 🚨★★★**WHAT AN INTERRUPTION DOES TO AN OPEN EDIT. THERE ARE TWO.**
///
/// 🗣️유저 2026-09-17: 「**프레임이동이나 레이어이동등은 착지시킬 이유가
/// 없는것들은 착지안하고 편집중 그대로 유지**. 근데 여기서 **다른 도구
/// 선택하는 등만 착지**시키는거고」 — and again on 09-22, because it was
/// still not true: 「변형중 프레임 이동 등 **가능한동작이면 가능하게 냅두고,
/// 불가능한 동작이면 마지막 변형대로 커밋**하라고 내가 말하지않았냐? **두개로
/// 딱 나누라고**?」 · 「**입구도 하나로 나누고 거기서 분기시키는게 깔끔**할거
/// 같긴한데 그런부분 맡길테니」.
///
/// ⛔**THE ENUM IS THE POINT, NOT THE NAMES.** An interruption cannot be
/// handled without picking one of these two, so a situation nobody has
/// thought of yet — a new panel, a new shortcut, a new host — still has to
/// say which it is, and there is no third thing for it to do by accident.
/// 유저: 「절대 다른 상황 생겨도 대처가능하게해」.
///
/// ⚠️`the_session_ends_two_ways_test` holds the other half: nothing may
/// end a session except through [_CanvasSelectionLayerState._interrupted].
enum SessionInterruption {
  /// The edit TRAVELS with the user — walking frames, layers or cuts.
  ///
  /// Nothing lands, because there is nothing to protect: a session writes
  /// to no cel until it is confirmed, and the box, its numbers and its
  /// region are what the user is still working on.
  carry,

  /// The edit CANNOT travel, so it lands exactly as the box shows it.
  ///
  /// 🚨★★★**IT LANDS, IT DOES NOT ASK.** ↩️A tool change over a pending
  /// move used to open a 확정/되돌리기 dialog (R17-①, `c5e7b8a7`, the CSP
  /// grammar) — a THIRD answer, and the one the user struck down twice on
  /// 09-22 with 「두개로 딱 나누라고」. The dialog also disagreed with the
  /// very same switch reaching this layer as a DISPOSE, which always
  /// landed silently: select→move asked, select→brush did not.
  land,
}

class _CanvasSelectionLayerState extends State<CanvasSelectionLayer>
    with SingleTickerProviderStateMixin
    implements FloatWarpHost {
  /// The live selection, mirrored from [CanvasSelectionCommands.region]
  /// (R28-S: the channel OWNS it, so it survives this layer unmounting on
  /// a tool switch — see the channel's own note).
  CanvasSelectionRegion? _region;

  /// Assigns the region and pushes it to the app-level channel. Callers
  /// wrap in setState; the channel's setter is idempotent, so the round
  /// trip back through [applyCommittedRegion] settles immediately.
  /// Installs [region] as the live shape, here and on the channel that
  /// owns it (R28-S).
  ///
  /// 🚨★★★[implicit] is the MOVE tool's whole-picture box — a shape the
  /// tool synthesized because nothing was selected (R26 #13). It draws and
  /// lifts like any other shape and **it is not a selection**, which the
  /// channel now says for every reader at once (F-108,
  /// `CanvasSelectionCommands.region`).
  ///
  /// ⛔The flag is SET HERE and nowhere else. It used to be a second line
  /// beside each call, and it went stale exactly the way a second line
  /// does: the confirm cleared it, and the undo that came afterwards then
  /// had nothing left to tell it the restored shape had never been chosen.
  void _setRegion(CanvasSelectionRegion? region, {bool implicit = false}) {
    _region = region;
    _shapeIsImplicitWholePicture = region != null && implicit;
    widget.selectionCommands?.setRegion(region, implicit: implicit);
  }

  /// The SAME shape, somewhere else.
  ///
  /// 🚨★★★**WHETHER A SHAPE IS A SELECTION IS A FACT ABOUT THE SHAPE, NOT
  /// ABOUT WHERE IT IS** (F-108). Every one of these callers is a transform
  /// landing the outline where the pixels went, and each of them called
  /// [_setRegion] with the default — so the MOVE TOOL's implicit
  /// whole-picture box was reinstalled as a REAL selection the moment the
  /// transform committed, right before the confirm that was supposed to end
  /// it. 🔬Measured: pending `region=null`, confirmed `region=4pts`.
  ///
  /// 🚨And it lands through the stage door (I-23): whatever a transform
  /// carries past the pasteboard wall is cut there, as the landing already
  /// cuts the pixels it carried. Only the LANDING — the box, its affine and
  /// the outline riding it keep their absolute values until then (the
  /// tool law: 「편집값은 절대값」).
  void _moveRegion(CanvasSelectionRegion region) => _setRegion(
    region.clippedTo(widget.canvasSize.pasteboardRect),
    implicit: _shapeIsImplicitWholePicture,
  );

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

  /// The implicit whole-picture shape of the cel you stand on
  /// ([CanvasSelectionShape.wholePicture], from the host's ink bounds).
  /// Lifting it lifts the whole picture (the tool guard upstream already
  /// refuses the MOVE tool when the cel has no picture at all).
  CanvasSelectionShape _wholeCanvasShape() => CanvasSelectionShape.wholePicture(
    widget.canvasSize,
    widget.contentBoundsProvider?.call(),
  );

  /// Installs [shape] as the live implicit whole-picture selection.
  /// Callers wrap in setState.
  CanvasSelectionRegion _adoptImplicitWholePictureShape(
    CanvasSelectionShape shape,
  ) {
    final region = CanvasSelectionRegion.shape(shape);
    _setRegion(region, implicit: true);
    _shapeNeedsLift = true;
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
  }

  /// The lift command owning this selection's pixels (R15-④), the stamp
  /// dab currently FLOATING (removed from the command so the base never
  /// shows it — no double image), and the command's dabs as they stood
  /// before the session opened (the transform `before` for re-opened
  /// sessions).
  ///
  /// R16-① (TVP-style): the stamp stays floating through EVERY drag —
  /// nothing lands and nothing is undoable until the user CONFIRMS
  /// (button, Enter, tool switch, deselect, undo/redo hook), which adopts
  /// the whole session as ONE history entry.
  /// 🚨★★★**THE SESSION IS ONE VALUE, AND THIS IS THE ONLY FIELD THAT HOLDS
  /// IT.** There is no such thing as half a session: the token, the float,
  /// whether it moved and the shape it started from begin together and end
  /// together.
  ///
  /// ↩️They were four fields, and the END was spelled in FOUR places that
  /// did not agree — one of them cleared three of the four and told the HOST
  /// nothing at all. That is F-164 (유저 2026-09-18): the host holds the
  /// hole this cel is drawn through, so a session it is never told about
  /// leaves that cel drawn through a hole for the rest of the run — 「돌아가면
  /// 그림사라져있는데 … **새로 선을 그어도 긋고나서 커밋하면 사라짐**」.
  ///
  /// ⛔So ending one goes through [_endSession] and nowhere else, and
  /// `a_move_session_has_one_owner_test` reads this file to keep it that
  /// way. 유저: 「절대로 낡지않을 구조로 튼튼하게」.
  _MoveSession? _session;

  BrushDab? get _pendingLiftStamp => _session?.stamp;

  /// True once the session actually MOVED — the ants turn red until the
  /// confirm (green = confirmed / untouched).
  bool get _moveSessionDirty => _session?.moved ?? false;

  /// The region as the session found it — the revert restores it.
  CanvasSelectionRegion? get _moveSessionStartShape => _session?.startShape;

  bool get _movePending => _session != null;

  /// 🚨★★★**THE ONLY PLACE A SESSION ENDS.** Whatever the reason — a
  /// confirm, a revert, or simply letting go because the panel walked to
  /// another cel — the HOST hears about it, because the host is what holds
  /// the hole the origin cel is being drawn through
  /// ([CanvasPanelLift.holedSurfaceFor]).
  ///
  /// ⛔This is the invariant made unrepresentable rather than remembered:
  /// the field is dropped HERE and nowhere else in this file, so
  /// there is no way to forget a session quietly. F-164 is what forgetting
  /// one cost — the cel kept drawing its hole, and everything drawn there
  /// afterwards was masked away on commit.
  ///
  /// Returns the session that ended, or null when there was none.
  _MoveSession? _endSession(_SessionEnd how) {
    final session = _session;
    if (session == null) {
      return null;
    }
    _session = null;
    _tellHost(() {
      switch (how) {
        case _SessionEnd.confirm:
          final confirm = widget.onLiftConfirmed;
          if (confirm != null) {
            confirm(session.token, session.stamp, session.landed);
          } else {
            // Headless hosts (focused tests): land without history.
            widget.onLiftLanded?.call(session.token, session.stamp);
          }
        case _SessionEnd.revert:
        case _SessionEnd.letGo:
          // The same call, and they are the same fact: a session writes
          // nothing to the cel until it lands (`314aa6e8`), so ending one
          // without landing is only ever 「close it」. ⛔Letting go used to
          // do this silently, which is the whole of F-164.
          widget.onLiftReverted?.call(session.token);
      }
    });
    return session;
  }

  /// 🚨★★★**TELLING THE HOST REBUILDS IT, AND ONE ENDING HAPPENS DURING A
  /// BUILD.** A frame walk lets go from inside `didUpdateWidget`
  /// ([_carrySessionToAnotherCel]), and a `setState` on the panel from
  /// there is the framework's own 「called during build」 error.
  ///
  /// ⚠️This is why the silent version looked like it worked: saying nothing
  /// cannot be mistimed. ⛔So the wait lives HERE, at the one door, rather
  /// than in each caller — a caller that had to remember is a caller that
  /// will forget, which is the shape F-164 already was.
  void _tellHost(VoidCallback say) {
    if (_disposing ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => say());
      return;
    }
    say();
  }

  /// This state is going away. ⚠️It is not 「is the session ending」 — it is
  /// 「can the host be told NOW」: dispose can run inside a build, so the
  /// history execute has to wait a frame either way.
  bool _disposing = false;

  /// REVERT (R17-①): the pixels — and the ants — return exactly to where
  /// the session found them; nothing lands in history.
  void _revertMoveSession() {
    final startShape = _moveSessionStartShape;
    if (_endSession(_SessionEnd.revert) == null) {
      return;
    }
    if (mounted) {
      setState(() {
        // R26 #13: an implicit whole-picture session reverts to NO
        // selection — the user never selected anything.
        if (_shapeIsImplicitWholePicture) {
          _setRegion(null);
          _shapeNeedsLift = false;
        } else {
          if (startShape != null) {
            _setRegion(startShape);
          }
          _shapeNeedsLift = true;
        }
        if (_transform == null) {
          _floatSurface = null;
        }
      });
    }
    _syncAnts();
  }

  /// LETTING GO: the float is dropped without landing, because its pixels
  /// belong to the cel being left behind.
  ///
  /// ⛔It is not a quieter revert — it is the same ending, and the host is
  /// told either way.
  void _letGoOfSession() => _endSession(_SessionEnd.letGo);

  /// CONFIRM (R16-①): lands the floating stamp and adopts the whole
  /// session as ONE history entry. Safe to call from any event context;
  /// never called inside a build phase (the tool-switch and dispose
  /// triggers defer post-frame). Afterwards the shape needs a fresh lift
  /// (R19 pixel model: the landed raster IS the content to move next).
  void _confirmMoveSession() {
    // 🚨★★★**EVERY CONFIRM FOLDS THE BOX IN FIRST, AND REMEMBERS IT.**
    //
    // ⛔Not only the box's own Enter. A confirm also arrives from a
    // deselect, from Ctrl+D and from a region that undo/redo put back —
    // and since the move became the affine's tx/ty there is no longer
    // anything in the STAMP for those paths to land. They used to work by
    // accident, because the drag had already walked the stamp over.
    //
    // ↩️A `landedWith` argument stood here for the one caller that had
    // folded and closed the box itself; the fold is one function now and
    // leaves what it landed with on the session ([_foldOpenBox]).
    _foldOpenBox();
    if (_endLanded() == null) {
      return;
    }
    void settle() {
      _shapeNeedsLift = true;
      // R26 #13: a confirmed implicit whole-picture session lands and
      // simply ends — back to no selection.
      if (_shapeIsImplicitWholePicture) {
        _setRegion(null);
        _shapeNeedsLift = false;
      }
    }

    if (mounted) {
      setState(() {
        settle();
        // The float goes with the session. Not under an open box — the
        // fold closes a box that changed anything, so one still open here
        // changed nothing and is the caller's to close.
        if (_transform == null) {
          _dropFloat();
        }
      });
    } else {
      settle();
    }
    _syncAnts();
  }

  /// Ends the session as LANDED: one undo entry when something was folded
  /// into it, and simply let go when nothing was.
  ///
  /// A float that was lifted and never changed is the picture as it stood —
  /// a session writes nothing to the cel until it lands — so there is
  /// nothing to land and nothing for an undo to step back to. ↩️Every
  /// landing confirmed, changed or not: opening a box and changing tool
  /// without touching it left an undo step that stepped back to the same
  /// picture, and a confirm taken just before an undo (the history's own
  /// hook) handed that undo an entry of nothing to consume (measured
  /// 2026-10-06, an untouched box under each ending).
  _MoveSession? _endLanded() => _endSession(
    _session?.holdsAChange ?? false ? _SessionEnd.confirm : _SessionEnd.letGo,
  );

  /// The drag running right now, or null — the ONE field that says which
  /// mode owns the pointer and what that mode is holding. See
  /// [SelectionDrag] for why it is one field and not three.
  SelectionDrag? _drag;

  /// The live drag when it is the marquee, for the three sites that want
  /// its outline. A projection of [_drag], never a second copy of it.
  MarqueeDrag? get _marqueeDrag {
    final drag = _drag;
    return drag is MarqueeDrag ? drag : null;
  }

  /// The move drag's screen-space delta, or zero when no move drag is live
  /// — which is also what the field this replaced held at rest.
  Offset get _moveScreenDelta => switch (_drag) {
    MoveDrag(:final screenDelta) => screenDelta,
    _ => Offset.zero,
  };

  /// The floating copy of the selected pixels (built once at drag start).
  BitmapSurface? _floatSurface;

  /// The float through the open warp, resampled and decoded for the
  /// screen — see [FloatResamplePreview]. Empty outside a warp session.
  late final FloatResamplePreview _preview = FloatResamplePreview(this);

  /// The drag so far in WHOLE CANVAS PIXELS — what a move can actually
  /// land on (TP5).
  ///
  /// 🚨The confirm rounds: the stamp lands at
  /// `(center - size/2).round()` (`bitmap_surface_brush_commit`), so a
  /// fractional centre snaps at commit time and the artwork stepped by up
  /// to half a pixel the moment you confirmed — 유저: *"확정하면 그림이
  /// 미세하게 바뀌거든? 살짝 움직이거나?"*. Invisible at 100% zoom and two
  /// screen pixels at 400%, which is why it read as "미세".
  ///
  /// So the rounding happens HERE, once, and everything that shows or
  /// commits the move reads this same value: the float, the ants, the
  /// confirm button and the landing. 유저 확정 A — *"바이트단위로 동일해야
  /// 하니까"*: a whole-pixel translation is a copy, and the preview is then
  /// showing the exact bytes the commit will write, at the exact place.
  ///
  /// The cost is deliberate: zoomed in, the drag steps by canvas pixels
  /// instead of gliding. That is the truth about where pixels can go.
  CanvasPoint get _moveCanvasDelta => TransformBoxLaw.wholePixels(
    widget.viewport.viewportDeltaToCanvasDelta(
      dx: _moveScreenDelta.dx,
      dy: _moveScreenDelta.dy,
    ),
  );

  // Ctrl+T free-transform session (P9b): the open box, or none — see
  // [TransformBox]. The per-drag solving context is NOT here — it lives on
  // [TransformDrag] and dies with the gesture.
  TransformBox? _box;

  /// The open box's affine; null when no box is up.
  SelectionAffine? get _transform => _box?.affine;


  late final AnimationController _ants = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  /// A finger resting on the glass while a transform handle is dragged —
  /// the modifier's TOUCH entrance.
  ///
  /// 🗣️유저 2026-09-22: 「수정자는 항상 그렇지만 **터치 입구도 존재하게**
  /// 하고싶으니 **터치발생하면 수정자 발생**하도록. **최대한 입구 단순하게
  /// 네이티브하게**해서」.
  ///
  /// ↩️**THIS REVERSES A 2026-08-13 DECISION, and that one's reasoning is
  /// kept because it is still true**: an extra finger during a transform
  /// drag was deliberately given NO meaning — 「변형 도중 터치 들어오면
  /// 변형 멈춰버리는데」 asked for it to stop cancelling the drag, and
  /// giving it a meaning was refused on the grounds that a PALM would then
  /// change the result, which is invisible, instead of the drag, which is
  /// not. 유저 asked for the meaning anyway on 09-22, with the tablet's
  /// missing Alt as the reason. ⛔So the risk is theirs and it is named,
  /// not forgotten.
  int? _modifierTouch;

  /// Whether the scale modifier is held — by key or by finger.
  ///
  /// ⚠️Read at EVERY solve, which is the whole of 유저's 「입구 하나로 하되
  /// 두개의 동작을 지원」: held before the press and pressed during the drag
  /// are the same question asked at the same place.
  bool get _scaleModifierHeld =>
      HardwareKeyboard.instance.isAltPressed || _modifierTouch != null;

  /// A selection the USER made.
  ///
  /// 🚨★★★**THE IMPLICIT WHOLE-PICTURE SHAPE IS NOT ONE** (R26 #13), and
  /// this field is where that stopped being true inside the layer.
  /// `d0d6089f` split the CHANNEL — `region` is what the user chose,
  /// `liveShape` is geometry — but `_region` here went on answering both,
  /// so the ants animated and drew around a box opened with no selection
  /// at all.
  ///
  /// 🗣️유저 2026-09-12 (F-108): 「선택툴 안하고 그냥 변형사용시 … 선택툴의
  /// 개미행렬이 남아있음 … 그러지않도록」, and again from a hands-on run on
  /// 2026-09-22: 「아직도 선택없이 변형시작하면 사각형에 뒤에 잘보면
  /// 개미행렬 있는데 … **구조적으로 생길수밖에 없는게 문제라면 구조를
  /// 바꾸라고**」.
  ///
  /// ⛔Not a second name beside the old one: the doc on the channel's
  /// `hasSelection` already said 「whether a live selection exists」, so
  /// this is the meaning it always claimed. A caller that wants 「is there
  /// a region at all」 asks `_region` and says so.
  bool get _hasSelection => _region != null && !_shapeIsImplicitWholePicture;

  /// Where the pointer is, in this layer's own coordinates — the far end of
  /// the polygon's rubber band (TS6).
  ///
  /// A notifier rather than state: the ants painter listens to it directly,
  /// so the band follows the pointer without rebuilding this layer. ⚠️Touch
  /// has no hover, so on a finger the band follows only while the contact is
  /// down (which is the whole aiming window there — a vertex is aimed on
  /// press and placed on release). A pen with hover follows continuously.
  final ValueNotifier<Offset?> _cursor = ValueNotifier<Offset?>(null);

  /// Mirrors the channel's open-trace length so a vertex added or taken
  /// back repaints this layer. The trace itself is never copied down here
  /// — the channel stays its only owner.
  int _polygonTracePoints = 0;

  @override
  void initState() {
    super.initState();
    // R28-S: adopt whatever the app already has selected — the region
    // outlives this layer (tool switches unmount it), so mounting must
    // pick it back up instead of starting empty.
    _region = widget.selectionCommands?.liveShape;
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
    final channelRegion = widget.selectionCommands?.liveShape;
    if (channelRegion == _region) {
      return;
    }
    setState(() {
      _region = channelRegion;
      _shapeNeedsLift = channelRegion != null;
      _shapeIsImplicitWholePicture = false;
      // 🚨★★★THIS DROPS A PENDING MOVE WITHOUT LANDING IT, and what makes
      // that safe is not visible from here. [_letGoOfSession] lets the
      // float go, so a pending session reaching this line loses the user's
      // unconfirmed edit. ↩️It lost their PIXELS while the lift's erase was
      // committed up front; a session writes nothing until it lands now
      // (`314aa6e8`), and the helpers this named are gone.
      //
      // What keeps it unreachable — each line one edit away from stopping
      // being true (re-checked 2026-10-01 for I-23: the 09-08 count of
      // 「exactly TWO callers」 no longer held):
      //  - `CanvasSelectionCommands.setRegion` has four callers. This
      //    layer's `_setRegion` echoes back equal and stops at the guard
      //    above. The channel's `applyRegion` hands the region on to
      //    [applyCommittedRegion], which confirms first — the path the
      //    selection history and the inverse take. The channel's
      //    `deselect` writes only while no layer is bound.
      //  - The one writer from outside is the lift command's
      //    `restoreRegion` (`canvas_panel_lift.dart`), and every undo/redo
      //    confirms first — `home_page.dart` wires
      //    `historyManager.onBeforeUndoRedo` to `confirmPendingMove`.
      //
      // ⛔So a NEW caller of `setRegion` opens this hole. If you are that
      // caller, go through `applyRegion`, or confirm the session first
      // (`_confirmMoveSession()`, the way the committed-region path below
      // does), rather than widening this comment.
      _letGoOfSession();
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
      oldWidget.selectionCommands?.unbind(this);
      oldWidget.selectionCommands?.removeListener(_adoptChannelRegion);
      _region = widget.selectionCommands?.liveShape;
      _shapeNeedsLift = _region != null;
      _bindCommands();
      widget.selectionCommands?.addListener(_adoptChannelRegion);
    }
    if (oldWidget.frameToken != widget.frameToken) {
      // Build-phase safety (R15-⑤): this runs inside didUpdateWidget —
      // the drag-end notify reaches ancestor setState and must defer.
      //
      // 🚨F-86 (유저 2026-09-12: 「선택툴 선택한채로 프레임이나 인덱스
      // 이동하면 사라지는데 뭘 하든 안사라지도록. 다른 컷 가도」): another
      // frame, row or cut KEEPS the region, and the next move lifts it
      // afresh from the cel it then stands on.
      //
      // 🚨★★★**AND IT DOES NOT LAND** (2026-09-17). 유저 asked for exactly
      // this split: 「프레임이동이나 레이어이동등은 **착지시킬 이유가
      // 없는것들은 착지안하고 편집중 그대로 유지**. 근데 여기서 **다른 도구
      // 선택하는 등만 착지**시키는거고」. Walking the sheet is not leaving
      // the session — the box stays open, the numbers it holds stay set,
      // and the next drag lifts them out of whatever cel is under it.
      //
      // ↩️This called the reset of the day, which LANDED a pending float.
      // ⚠️The paragraph that stood here said the landing was unreachable
      // 「because R15-⑤ refuses the seek while a selection interaction is
      // held」 — measured 2026-09-17, with a box open next-frame left the
      // playhead at 0 of 24. That refusal is gone now (a pending session
      // leaves nothing behind to protect, `314aa6e8`), so this path DOES
      // arrive holding a float, and landing it would write the user's edit
      // into the frame they were walking away from.
      //
      // ⛔Dropping the float costs nothing to undo, and that is the whole
      // reason this is allowed to be a drop: the session never wrote to
      // the cel. Before `314aa6e8` the erase was already committed and
      // letting go here would have left a hole with the pixels gone.
      _interrupted(SessionInterruption.carry);
    }
    // Picking another mode (or another grid size) over an OPEN box widens
    // or narrows it in place — the whole point of holding the warp as
    // offsets is that this costs no resample and loses no pixel.
    if (_transform != null &&
        (oldWidget.transformOptions.mode != widget.transformOptions.mode ||
            oldWidget.transformOptions.meshColumns !=
                widget.transformOptions.meshColumns ||
            oldWidget.transformOptions.meshRows !=
                widget.transformOptions.meshRows)) {
      setState(_syncOffsetsToMode);
      _preview.schedule();
      _syncAnts();
    }
    // 🧪The MODE picks which transform 적용 would replay, so it is news to
    // everything that shows whether 적용 can act. They hear the mode
    // themselves — and may ask before this layer has it, which is the
    // frame a button answered from the old mode and was never asked again
    // (confirm-button's ↵, measured).
    if (oldWidget.transformOptions.mode != widget.transformOptions.mode) {
      widget.selectionCommands?.notifySessionChanged();
    }
    // The preview is clipped to what is on screen, so MOVING the screen
    // changes what it has to compute. Nothing else would notice: the
    // resample is scheduled by pointer moves and mode switches, and a pan
    // is neither — the box would keep painting the window it was given
    // and the picture would simply be absent outside it.
    if (_transform != null && oldWidget.viewport != widget.viewport) {
      _preview.schedule();
    }
    if (oldWidget._resampleMode != widget._resampleMode) {
      // P3a: flipping the switch with a box already open re-resamples on
      // the spot. Waiting for the next drag would show the old kernel's
      // picture and land the new one's.
      _preview.schedule();
    }
    // Note what is NOT here: cancelling an open polygon trace on a tool
    // change. This layer does not mount for the painting tools, so on the
    // switch that matters most it is being DISPOSED rather than updated
    // and would never see it. The panel above watches the tool instead.
    // A TOOL CHANGE CANNOT CARRY THE EDIT, so it lands it — the second of
    // the two answers, through the one door.
    //
    // ⚠️Deferred post-frame because history commands must never run inside
    // the build phase, not because anything here is optional.
    //
    // ↩️R17-① asked instead (a 확정/되돌리기 dialog), and R27 #18 committed
    // an open BOX beside it — so one switch had two answers depending on
    // whether a box was open, and the very same switch to a painting tool
    // reached [dispose] and silently landed both. 유저 struck the dialog
    // down on 09-22: 「두개로 딱 나누라고」.
    if (oldWidget.tool != widget.tool) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _interrupted(SessionInterruption.land);
      });
    }
  }

  @override
  void dispose() {
    widget.selectionCommands?.removeListener(_adoptChannelRegion);
    widget.selectionCommands?.unbind(this);
    if (_drag != null) {
      _notifyDragActive(false);
    }
    // 🚨★★★**UNMOUNTING IS AN INTERRUPTION THAT CANNOT CARRY**, so it
    // takes the same door as every other one. A switch to a painting tool
    // arrives here rather than at [didUpdateWidget] — this layer does not
    // mount for those tools — and the two used to answer it differently.
    //
    // ⚠️`_disposing` is what makes the landing wait: dispose can run inside
    // a build, and the history execute must not. The interaction hold
    // still releases NOW, above, so a leak can never lock seeks.
    //
    // ↩️This spelled its own fold — `_preview.warped() ?? _pendingLiftStamp`,
    // with no identity guard and no region move — beside a function whose
    // doc already said 「every path that ends a session while a box is open
    // needs this」. Two implementations of one algorithm is a copy however
    // differently it reads, and these two had already drifted apart.
    _disposing = true;
    _interrupted(SessionInterruption.land);
    // The preview image is a GPU allocation and an in-flight decode holds
    // a callback into this state. Neither is reached by _clearTransform on
    // this path — dispose does not close the box, it folds it — so the
    // discard has to be explicit here or every tool switch during a
    // transform leaks a full-selection image.
    _preview.discard();
    _cursor.dispose();
    _ants.dispose();
    super.dispose();
  }

  void _bindCommands() {
    widget.selectionCommands?.bind(
      this,
      hasSelection: () => _hasSelection,
      deselect: _deselect,
      closePolygon: _closeOpenPolygon,
      transformActive: () => _transform != null,
      beginTransform: _beginTransform,
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
      confirmPendingMove: _confirmSession,
      revertPendingMove: _revertMoveSession,
      transformValues: _transformValuesNow,
      editTransformValues: _editTransformValues,
      undoTransformStep: _undoTransformStep,
      canUndoTransformStep: () => _box?.steps.isNotEmpty ?? false,
      beginTransformStep: _pushTransformStep,
      canEditTransform: _canEditTransform,
      flipTransform: _flipTransform,
      resetTransform: _resetTransform,
      applyTransform: _applyTransform,
      canApplyTransform: () => _applyAction() != null,
    );
  }

  /// 좌우반전 / 상하반전: a sign flip on one scale axis.
  ///
  /// It is a scale and not a separate verb, which is why it needs no
  /// special case in any mode: the offsets ride the same affine, so a
  /// mirrored perspective box mirrors its warp with the picture.
  /// Opens a transform box when there is not one, applies [edit] to it,
  /// and leaves the way every box edit leaves.
  ///
  /// ⛔THE ENTRY AND THE EXIT ARE THE LAW. Refuse when the row cannot be
  /// transformed; open a box when none is up; and on the way out resample
  /// the float AND re-run the ants. An edit that skipped the resample
  /// would leave the ants drawn around the OLD shape while the picture
  /// shows the new one.
  void _editTransform(SelectionAffine Function(SelectionAffine affine) edit) {
    if (!_canEditTransform()) {
      return;
    }
    if (_box == null) {
      _beginTransform();
    }
    final box = _box;
    if (box == null) {
      return;
    }
    setState(() {
      box.affine = edit(box.affine);
    });
    _preview.schedule();
    _syncAnts();
  }

  void _flipTransform({required bool horizontal}) => _editTransform(
    (affine) => horizontal
        ? affine.copyWith(sx: -affine.sx)
        : affine.copyWith(sy: -affine.sy),
  );

  /// 리셋: every value (유저 확정 08-13 "리셋은 전부") — the affine AND the
  /// warp. Resetting only the numbers would leave a box that reads 100%,
  /// 0° and still looks bent.
  void _resetTransform() {
    final box = _box;
    if (box == null) {
      return;
    }
    setState(() {
      box.affine = SelectionAffine(pivot: box.affine.pivot);
      box.warp.reset();
    });
    _preview.schedule();
    _syncAnts();
  }

  /// 적용 — the transform tool's half of 확정, and every door to it: the
  /// tool settings button, the box's ✓ and Enter (`ConfirmVerb`).
  ///
  /// 🗣️유저 2026-09-24 (confirm-button-Q2): 「변형도구=변형중이지 않으면
  /// 마지막 변형 재실행, 변형중이면 확정」. 변형 중 is [_sessionHasChanges]
  /// — the user's own word for it (08-27: 「변형중일땐. 그니까 변경사항이
  /// 있으면」). ↩️It asked [_boxIsTransformed] alone, so a session that held
  /// its change outside an open box replayed a transform over it.
  ///
  /// Otherwise it REPLAYS the last committed transform's values into the
  /// box and stops there, so the recalled values can be seen and adjusted;
  /// a second press is what applies them (유저 확정 08-13: "재현만.
  /// 두번째눌러야 적용").
  void _applyTransform() => _applyAction()?.call();

  /// What 적용 would do now, or null when it has nothing to do — the ONE
  /// answer both the press and the buttons' enablement read.
  VoidCallback? _applyAction() {
    if (!_canEditTransform()) {
      return null;
    }
    if (_sessionHasChanges) {
      return _confirmSession;
    }
    // 🚨THE ARMED MODE'S OWN MEMORY (유저 2026-08-29: 「툴마다 기억하는게
    // 다름」). One shared slot could only answer for whichever mode
    // committed last, so arming 일반 and pressing Enter replayed a 퍼스
    // warp — or did nothing at all, when that warp's affine was identity.
    final recall = widget.selectionCommands?.recallFor(_mode);
    if (recall == null || recall.isIdentity) {
      return null;
    }
    return () => _replayTransform(recall);
  }

  /// Lands the session: the open box first, then the move it rides.
  ///
  /// ⛔**BOTH HALVES.** A box that changed nothing is only closed and leaves
  /// the session pending, so the single branch Enter used to take made one
  /// confirm into two. With both, a warped box lands warped and an untouched
  /// box closes with its session in the one press.
  ///
  /// ↩️The box's ✓, wired straight to `_confirmMoveSession`, landed the
  /// UNWARPED lift: the artwork committed at its pre-transform position and
  /// size, the warped preview kept painting on top until something closed
  /// the box, and the wrong landing went into history.
  void _confirmSession() {
    if (_transform != null && !_foldOpenBox()) {
      // Untouched (or a degenerate quad): close the box, and a session
      // under it goes on pending.
      setState(_clearTransform);
    }
    if (_movePending) {
      _confirmMoveSession();
    } else {
      _syncAnts();
    }
  }

  void _replayTransform(TransformRecall recall) {
    // The replay is an EDIT of the box like any other, so it enters and
    // leaves through _editTransform (open a box when none is up; resample
    // and re-run the ants on the way out). The closure runs inside its
    // setState, so the offsets land in the same frame as the affine.
    _editTransform((affine) {
      // Only the part the armed mode can hold. A recall carrying a mesh
      // recorded on another grid has nowhere to put its interior points,
      // so it lands as the affine alone rather than as a guess.
      final warp = _box!.warp;
      if (warp.corners != null && recall.hasPerspective) {
        warp.corners = List.of(recall.cornerOffsets);
      }
      if (warp.mesh != null &&
          recall.hasMeshFor(columns: warp.meshColumns, rows: warp.meshRows)) {
        warp.mesh = List.of(recall.meshOffsets);
      }
      return affine.withValues(recall.values);
    });
  }

  /// Whether the open box would change any pixel.
  bool get _boxIsTransformed => _box?.isTransformed ?? false;

  /// Whether the session is holding changes that have not landed — the ONE
  /// question the ants, the transform box and the confirm button all draw
  /// (see `AppColors.selectionSession`).
  ///
  /// Two terms because a session has two ways to hold a change.
  /// [_moveSessionDirty] is set by a drag that carried the box, and by
  /// nothing else — ↩️it was also set where a box was closed onto the
  /// session, and those closings end the session on their next line now
  /// ([_foldOpenBox]). While a box is OPEN that flag is false however far
  /// the user has dragged a handle — 유저 2026-08-27: 「**변형중일땐**.
  /// 그니까 변경사항이 있으면 … 빨간색」. [_boxIsTransformed] is the answer
  /// for exactly that window and already existed; ⛔a second dirty flag
  /// would have been a second place to forget to clear.
  bool get _sessionHasChanges => _moveSessionDirty || _boxIsTransformed;

  /// Records what a commit just applied, for the next 재현.
  void _recordTransformRecall(TransformBox box) {
    final channel = widget.selectionCommands;
    if (channel == null) {
      return;
    }
    final affine = box.affine;
    final warp = box.warp;
    // ⛔Filed under the mode that MADE it, not into one shared slot. A 퍼스
    // commit must not become what 일반 replays: the two modes hold different
    // things (a quad versus an affine), and 유저 asked for them separately.
    channel.transformRecalls[_mode] = TransformRecall(
      // The values, not a result: a recall is replayed onto ANOTHER piece
      // of artwork, and 유저 확정 08-13 is "어떤 크기의 소재든 같은 값을
      // 변형주도록" — the same 120%, not the same number of pixels. ⛔Whole
      // ([TransformValues]): the box's own, with no pivot in it.
      values: affine.values,
      cornerOffsets: warp.corners == null ? const [] : List.of(warp.corners!),
      meshOffsets: warp.mesh == null ? const [] : List.of(warp.mesh!),
      meshColumns: warp.meshColumns,
      meshRows: warp.meshRows,
    );
  }

  /// Whether an edit would land on anything.
  ///
  /// 유저 확정 08-13 (피드백 ⑦): choosing the transform tool is always
  /// allowed — the refusal moved off the tool switch and onto the edit, so
  /// this is asked at the moment of the press, the numeric write or the
  /// apply, and it is asked of the cel that is active RIGHT NOW rather
  /// than the one that was active when the tool was picked (피드백 ⑥).
  ///
  /// It reads the INK bounds, not "does a cel exist". The existing
  /// tool-switch gate asked `celHasRenderableContent`, which is three map
  /// lookups and answers a different question: a cel that exists but is
  /// blank passed it, and the lift then came back empty and rolled the
  /// session back with nothing on screen to explain why.
  ///
  /// The provider memoizes on the surface instance, so asking every build
  /// costs a comparison — which is what "갱신되도록. 렉없이" requires.
  bool _canEditTransform() {
    if (widget.onLiftRequested == null) {
      return false;
    }
    // A session already open is its own answer: the pixels are in hand.
    if (_transform != null || _movePending) {
      return true;
    }
    final content = widget.contentBoundsProvider?.call();
    return content != null &&
        content.rightExclusive > content.left &&
        content.bottomExclusive > content.top;
  }

  /// Numeric transform input (R17-U tool settings): opens the session if
  /// none is up (Ctrl+T semantics — lift + box), then hands [change] the
  /// box's values and keeps what it answers. Enter/Escape keep their
  /// commit/revert meanings.
  void _editTransformValues(
    TransformValues Function(TransformValues now) change,
  ) => _editTransform((affine) => affine.withValues(change(affine.values)));

  /// 🚨★★★**THE ONE DOOR AN INTERRUPTION GOES THROUGH.**
  ///
  /// Every site that learns the world changed under an open edit calls
  /// this and names its bucket; the branch is here and nowhere else. See
  /// [SessionInterruption] for the two and why there are only two.
  ///
  /// ⛔It is safe to call with nothing open — both answers are no-ops on an
  /// empty session — so a caller never has to ask first, and a caller that
  /// forgot to ask can never be the bug.
  void _interrupted(SessionInterruption by) {
    switch (by) {
      case SessionInterruption.carry:
        _carrySessionToAnotherCel();
      case SessionInterruption.land:
        _landOpenSession();
    }
  }

  /// [SessionInterruption.land]: whatever the box shows becomes the cel.
  ///
  /// ⛔**THE FLOAT THIS LAYER PUBLISHED IS TAKEN BACK HERE**, for every
  /// landing and not just the dispose one. [_publishFloat] runs from BUILD,
  /// so an ending that does not rebuild — a dispose, or a land that closes
  /// the session in the same frame — leaves the composite holding a
  /// picture nobody owns, drawn over the one that just landed (유저
  /// 2026-09-22: 「캔버스 사라지고 이상해지는데」).
  void _landOpenSession() {
    // R27 #18: fold the box in FIRST, so whatever it showed is what lands
    // rather than the stamp's pre-transform place — through the fold 확정
    // itself takes ([_foldOpenBox]), which also closes the box.
    //
    // ↩️It folded the AFFINE alone and then went on to commit. A quad or a
    // mesh with every number at rest was not folded, so a switch to a
    // painting tool landed it unwarped (유저 2026-10-04, F-280: 「자유변형은
    // 취소되고 바뀜」); and under a switch that keeps this layer the commit
    // found the box still open over the folded stamp and ran the picture
    // through its transform a second time (measured 2026-10-06).
    _foldOpenBox();
    widget.floatOverlay?.value = null;
    if (_disposing) {
      // ⚠️SAME LANDING, NO UI TO UPDATE. The widget is going, so the part
      // of a commit that paints — closing the box, re-running the ants —
      // has nothing to paint on, and `setState` on a defunct element is an
      // assertion, not a no-op. The fold above already made the session
      // hold what the box showed, which is the whole of the landing.
      _endLanded();
      return;
    }
    _confirmSession();
  }

  /// Remembers where the box stands, just before an operation moves it
  /// ([TransformBox.pushStep]). With no box open there is nothing to step
  /// back to and nothing is pushed.
  void _pushTransformStep() => _box?.pushStep();

  /// Takes one operation back. False when there is nothing left to take —
  /// and then undo means what it always means, exactly as it does once a
  /// polygon trace runs out ([CanvasSelectionCommands.undoPolygonPoint]).
  bool _undoTransformStep() {
    final box = _box;
    if (box == null || box.steps.isEmpty) {
      return false;
    }
    setState(box.popStep);
    _publishTransformValues();
    _preview.schedule();
    _syncAnts();
    return true;
  }

  /// Walking to another cel with a session open: the box, the region and
  /// the numbers it holds all stay; only the FLOAT is let go, because its
  /// pixels belong to the cel being left behind.
  ///
  /// 🚨★★★유저 2026-09-17, splitting the verbs by hand: 「프레임이동이나
  /// 레이어이동등은 **착지시킬 이유가 없는것들은 착지안하고 편집중 그대로
  /// 유지**. 근데 여기서 **다른 도구 선택하는 등만 착지**시키는거고」. So a
  /// seek is not an ending — [_landOpenSession] is what endings go
  /// through, and this is deliberately not it.
  ///
  /// ⛔**THE TRANSFORM IS KEPT ON PURPOSE.** It is the 「편집값」 the user
  /// asked to survive the walk: scale the box on frame 1, step to frame 5,
  /// and the same scale is waiting there — applied to frame 5's own pixels,
  /// which [_shapeNeedsLift] is what arranges (F-86: 「the next move lifts
  /// it afresh from the cel it then stands on」).
  ///
  /// ⛔**AND LETTING THE FLOAT GO IS FREE, which is why this is allowed to
  /// be a drop at all.** A session writes nothing to the cel until it
  /// lands (`314aa6e8`), so there is no erase to take back. Before that,
  /// releasing here would have left the origin erased and the floating
  /// pixels gone — which is exactly why the seek was refused instead.
  void _carrySessionToAnotherCel() {
    // 🚨A SHAPE BEING TRACED BELONGS TO NO CEL UNTIL IT IS DRAWN (I-69), so
    // the walk does not take it out of the hand. And the cel it asked for
    // at its press ([CanvasSelectionLayer.onPressNeedsCel]) arrives as
    // exactly this — another frame under the layer. 🔬The Windows app,
    // 2026-10-08, 「프레임 자동 생성」 on: the block was made, the drag ended
    // with its arrival, and no shape was drawn.
    final tracesAShape =
        widget.tool == CanvasSelectionTool.drawShape && _drag is MarqueeDrag;
    final wasDragging = _drag != null && !tracesAShape;
    setState(() {
      if (!tracesAShape) {
        _endDrag(cancelled: true, notify: false);
      }
      _letGoOfSession();
      _shapeNeedsLift = _region != null;
    });
    // The resample on screen was computed from the cel we just left, and
    // an open box starts again HERE.
    if (_transform != null) {
      _startCarriedTransformHere();
    }
    if (wasDragging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _notifyDragActive(false);
        }
      });
    }
    _syncAnts();
  }

  /// 🚨★★★**THE NUMBERS ARRIVE AND THE PICTURE COMES WITH THEM** (F-164
  /// ③). 유저 2026-09-18: 「프레임2의 변형이 **시작되야하는데 시작되지도
  /// 않는** 문제」 · 「변형이 제대로 **프레임바뀌면 다음 프레임에 적용시작**
  /// 한다던가」.
  ///
  /// ↩️The box used to arrive open and EMPTY: [_shapeNeedsLift] was set and
  /// the pixels waited for a drag to notice them. 🧪Measured 2026-09-18 —
  /// Enter on the cel walked to moved nothing at all, which is exactly
  /// 유저's own next step (「그 상태에서 **엔터버튼으로 확정**시키고」). An
  /// open box was being reported as a started transform, and those are not
  /// the same thing.
  ///
  /// ⛔**THE SAME LIFT EVERY OTHER ENTRANCE TAKES**, not a second one:
  /// [_ensureLifted] is the one door, and its false IS 「불가능하면 그냥
  /// 무시」 — a cel with nothing under the outline does not start, and the
  /// walk is still allowed.
  ///
  /// ⚠️Through [_tellHost]: this runs inside `didUpdateWidget` and a lift
  /// rebuilds the host, which is the 「called during build」 error that
  /// door exists for.
  void _startCarriedTransformHere() {
    if (widget.onLiftRequested == null) {
      return;
    }
    _tellHost(() {
      if (!mounted || _transform == null) {
        return;
      }
      // ⛔THE SAME DOOR THE Ctrl+T ENTRANCE USES — 유저 2026-09-19: 「선택을
      // 하던 안하던 동작이 바뀌는게 없으니까 그점 유념해서 법 통일해줘」. A
      // drawn outline comes back unchanged; no selection comes back as
      // THIS cel's picture. There is no branch here to say which.
      CanvasSelectionRegion? here;
      setState(() => here = _regionToTransformHere());
      final region = here;
      if (region == null || !_ensureLifted(region)) {
        // 「불가능하면 그냥 무시」 — this cel has nothing under the outline.
        //
        // ⛔**AND NOTHING IS CLEARED.** [_clearFailedImplicitShape] is what
        // the ENTRANCES do, where a lift that finds nothing means the user
        // pressed on an empty canvas and no box should appear. Here a box
        // is already open and its numbers are an edit in progress: 🧪doing
        // that here turned 유저's ②「확정버튼도 사라지는문제」 red on the
        // very next run, because the button asks for a shape to draw.
        //
        // ⚠️Nothing to put back either: [_ensureLifted] leaves
        // [_shapeNeedsLift] set when it finds nothing, so the same outline
        // over this cel stays liftable if ink arrives under it.
        setState(() {});
        _syncAnts();
        return;
      }
      setState(() {
        // The numbers travel; the box is re-read from the region HERE.
        _aimTransformAt(region, keeping: _transform);
        _floatSurface = _buildFloatSurface();
      });
      _preview.schedule();
      _syncAnts();
    });
  }

  // --- Freedom above the affine: perspective and mesh ------------------
  //
  // The box's warp and its law live on [BoxWarp], and where that warp puts
  // the float on the canvas is [FloatWarp]; what stays here is where the
  // points sit on screen.

  TransformMode get _mode => widget.transformOptions.mode;
  int get _meshColumns => widget.transformOptions.meshColumns;
  int get _meshRows => widget.transformOptions.meshRows;

  /// The open box laid over the float as the layer holds it right now: the
  /// box, the pending stamp and the tool's knobs, read at the call.
  @override
  FloatWarp get floatWarp => FloatWarp(
    box: _box,
    float: _pendingLiftStamp,
    options: widget.transformOptions,
    pasteboard: widget.canvasSize.pasteboardRegion,
  );

  /// The box as the screen shows it now — its handles, what a press lands
  /// on and the chrome over it, read at the call. See [BoxOnScreen].
  BoxOnScreen get _onScreen => BoxOnScreen(
    viewport: widget.viewport,
    canvasSize: widget.canvasSize,
    mode: _mode,
    boxOpen: _transform != null,
    warp: floatWarp,
  );

  /// Brings the open box's warp in line with [_mode] and the armed grid
  /// ([BoxWarp.syncToMode]). Callers wrap in setState.
  void _syncOffsetsToMode() => _box?.warp.syncToMode(
    _mode,
    columns: _meshColumns,
    rows: _meshRows,
  );

  /// The canvas rectangle the user can actually SEE, or null when it
  /// cannot be worked out (no layout yet) — in which case the preview
  /// falls back to computing everything, which is what it always did.
  ///
  /// Padded, because the window is recomputed only when the resample key
  /// changes: a hair of slack means a small viewport nudge does not
  /// immediately expose an uncomputed edge.
  ///
  /// All four corners are mapped, not two: the canvas rotates and flips
  /// (P8), so the visible region's axis-aligned bounds are the bounds of
  /// the mapped corners rather than of two opposite ones.
  static const double _previewClipPadding = 96;

  SelectionVisibleRect? _visibleCanvasRect() {
    // The render object rather than `context.size`: this is reached from
    // `didUpdateWidget` (a mode switch re-resamples the open box), and
    // `BuildContext.size` throws while the owner is building. Asking the
    // box directly, and only when it `hasSize`, has no such rule — and
    // "no size yet" answers null, which means "do not clip", which is
    // what the tool did before any of this.
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    final size = box.size;
    if (size.isEmpty) {
      return null;
    }
    return canvasShownPadded(
      size,
      widget.viewport.viewportToCanvas,
      _previewClipPadding,
    );
  }

  /// The visible rect the PREVIEW clips to — or null, which means "do not
  /// clip", and which is the answer everywhere except mid-drag.
  ///
  /// Clipping is only safe while a handle is actually being dragged, and
  /// that is also the only time it is worth anything.
  ///
  /// Safe, because the viewport CANNOT move then: the panel holds mapped
  /// pans and wheel zooms behind `strokeActive` for the length of a
  /// selection drag, and touch behind `touchLocked`. Outside a drag the
  /// viewport moves freely — Fit, the zoom pill, the pan bars — and a
  /// window computed for where the user WAS is a window with a hole in
  /// it. Rescheduling on a viewport change does not close that hole
  /// either: the resample is synchronous but the decode is not, so the
  /// frames between a pan and the new image would paint the old window
  /// and nothing else. A drag cannot pan, so the question never arises.
  ///
  /// Worth anything, because a drag is the only thing that resamples
  /// dozens of times a second. At rest there is one resample, it computes
  /// the whole rect, and the commit reuses that very buffer — so the
  /// byte-identity path the tool has always had survives untouched.
  @override
  SelectionVisibleRect? previewVisibleRect() {
    if (_drag is! TransformDrag) {
      return null;
    }
    final rect = _visibleCanvasRect();
    if (rect == null) {
      return null;
    }
    final rounded = (
      left: rect.left.floorToDouble(),
      top: rect.top.floorToDouble(),
      right: rect.right.ceilToDouble(),
      bottom: rect.bottom.ceilToDouble(),
    );
    final out = floatWarp.outputRect();
    if (out == null) {
      return null;
    }
    // Everything already on screen: ask for no window at all, so the
    // buffer this produces is the one Enter can land.
    return selectionPreviewWindow(out: out, visible: rounded) == null
        ? null
        : rounded;
  }

  @override
  void previewChanged() {
    setState(() {});
  }

  /// Closes the transform box.
  ///
  /// [confirming] is passed by the three CONFIRM paths, and only by them:
  /// the session ends on the caller's next line, so the float is not
  /// rebuilt (a rebuild re-materializes the whole stamp — 651 ms of a
  /// 2,060 ms confirm frame on a 2340×1654 cel scaled to the pasteboard —
  /// to make tiles nothing will paint).
  ///
  /// 🪦Until 2026-09-17 a confirm also KEPT the decoded resample when it
  /// was what lands, so the base could compose the landing's tiles from
  /// it before their decodes arrived (a window of it counted too — 유저 법:
  /// 한 프레임 보이는 건 무조건 걸린다). A committed tile pictures itself
  /// inside the paint now, so the landing's first frame is whole with
  /// nothing handed over, and the resample goes with the box.
  void _clearTransform({bool confirming = false}) {
    // A drag still down when the box closes under it is NOT dropped here:
    // its release still has to lower the drag-active flags. What stops it
    // moving anything is that the box is gone, which
    // [_updateTransformDragGeometry] asks for itself — this used to say the
    // same thing by nulling five per-drag fields at a distance.
    //
    // ⛔The steps die with the box. A confirmed transform is ONE document
    // entry (유저: 「확정하면 변형 하나로서의 언두만 작동」) and a cancelled
    // one never happened, so there is nothing left for them to describe.
    // ↩️So does everything else the box held: they were thirteen fields
    // cleared here by name, and are one object dropped ([TransformBox]).
    _box = null;
    _preview.discard();
    if (confirming) {
      // The landing is warped and the float is not, so the float has
      // nothing to stay for.
      _floatSurface = null;
      return;
    }
    // A pending session's float must keep rendering — its pixels are NOT
    // in the base surface (they left with the lift's erase).
    _floatSurface = _movePending ? _buildFloatSurface() : null;
  }

  /// Ctrl+T: opens the free-transform box on the live selection (R19
  /// pixel model: the session lifts the shape's raster and the box
  /// manipulates the FLOAT; Enter resamples the stamp and confirms).
  /// 🚨★★★**WHAT A TRANSFORM OPENS ON, ASKED ON THE CEL IT IS OPENING
  /// ON** — and there is ONE answer, for Ctrl+T and for walking onto
  /// another cel alike.
  ///
  /// 🗣️유저 2026-09-19: 「**선택을 하던 안하던 동작이 바뀌는게 없으니까**
  /// 그점 유념해서 법 통일해줘」. So this is not 「the implicit case gets
  /// re-derived and the drawn one does not」 — that would be two laws
  /// wearing one name. It is one question, and the two kinds of region
  /// answer it differently because they ARE different things:
  ///
  /// · A region the user DREW is a place on the canvas. It says the same
  ///   thing on every cel, so asking again returns it unchanged.
  /// · No selection means 「the picture」 (R26 #13), and which picture that
  ///   is depends on the cel you are standing on. Asking again returns
  ///   THIS cel's.
  ///
  /// ⇒ the caller never branches, and the drawn case is the one where the
  /// answer happens not to move.
  CanvasSelectionRegion? _regionToTransformHere() {
    if (widget.tool != CanvasSelectionTool.move ||
        widget.onLiftRequested == null) {
      return _region;
    }
    final region = _region;
    if (region != null && !_shapeIsImplicitWholePicture) {
      return region;
    }
    return _adoptImplicitWholePictureShape(_wholeCanvasShape());
  }

  /// Points the box at [region] as it stands HERE — and keeps the numbers.
  ///
  /// 🗣️유저 2026-09-19: 「상자의 크기가 달라지는게 중요한게아니야. **중요한건
  /// 배율 회전 이동의 편집값이 그대로 전달되는거야**」. So the base box and
  /// the pivot are re-read from the region on this cel, and [keeping]'s
  /// scale, rotation and translation are carried over untouched.
  ///
  /// ⛔**THE PIVOT TRAVELS WITH THE BOX, NOT WITH THE NUMBERS.** Holding
  /// the cel-you-left's pivot would make the same 「×2」 land this cel's
  /// drawing somewhere off to one side — the numbers would read the same
  /// and not have been transferred, which is the very thing 유저 named.
  ///
  /// ⚠️A warp's per-point offsets are left alone: they are edit values too
  /// and they live in the box's own frame, so they travel with it. Only
  /// the mode decides how many there are, and a walk does not change it.
  /// With no box open, the aim is what opens one.
  void _aimTransformAt(
    CanvasSelectionRegion region, {
    SelectionAffine? keeping,
  }) {
    final bounds = _regionBounds(region);
    // ⛔WHOLE. It named the scales, the rotation and the move one by one,
    // and the cross — an edit value like the rest (유저 09-20: 「편집값은
    // 절대값이야」) — went back to the middle on every walk.
    final affine = SelectionAffine.of(
      bounds.center,
      keeping?.values ?? TransformValues.identity,
    );
    final box = _box;
    if (box == null) {
      _box = TransformBox(
        affine: affine,
        baseWidth: bounds.width,
        baseHeight: bounds.height,
      );
      return;
    }
    box
      ..affine = affine
      ..baseWidth = bounds.width
      ..baseHeight = bounds.height;
  }

  void _beginTransform() {
    // The quiet refusal (피드백 ⑦): with nothing to transform this simply
    // does not happen. No snackbar — one per tap on an empty layer is a
    // nag, and the flat controls already say it.
    if (!_canEditTransform()) {
      return;
    }
    // R26 #13: the MOVE tool with no selection opens the box on the WHOLE
    // picture (the Ctrl+T-family entrances included) — asked through the
    // one door, so this entrance and the walk cannot drift apart.
    CanvasSelectionRegion? region;
    setState(() => region = _regionToTransformHere());
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
    setState(() {
      _aimTransformAt(targetRegion);
      _box!.openedLift = !hadPendingLift;
      _syncOffsetsToMode();
      _floatSurface = _buildFloatSurface();
    });
    _syncAnts();
  }

  /// 🚨★★★**THE ONE FOLD — WHATEVER THE BOX SHOWS BECOMES THE SESSION.**
  ///
  /// The float is resampled through the open box (a pure translation stays
  /// byte-exact), the outline goes where the box put it, the transform is
  /// remembered for 재현, and the box closes. The session is still PENDING
  /// afterwards — ending it is the caller's — and it holds what the screen
  /// was showing. False when there is no box over a session, or the box
  /// changes no pixel: nothing was folded and the box is as it was.
  ///
  /// 🗣️유저 2026-10-04 (F-280): 「일반변형은 도중에 도구 바꾼다거나 하는
  /// 동작하면 확정되고 바뀌는데, 자유변형은 취소되고 바뀜. 동작이 서로 다르니
  /// 변형도구는 기본적으로 확정되고 바뀌도록. 기록도 남기는거 등 법 통일도」.
  ///
  /// 🗣️And of the first exit that forgot to fold at all (R28 #10): 「룰러로
  /// 다른데 갔다오면 변형된그림은 사라져있음」 — the transform was never
  /// wrong, it was discarded on the way out. Whatever the box showed is what
  /// lands, on every exit.
  ///
  /// ↩️There were three of these. Enter's commit knew all three shapes — a
  /// mesh, a quad, the affine — and was the only one that remembered the
  /// transform for 재현 or said what the confirm landed with. Every other
  /// ending (a tool change, an unmount, Ctrl+D) took a fold that knew the
  /// AFFINE alone, so a quad or a mesh with every number at rest landed
  /// unwarped, nothing was remembered, and a frame range's other cels were
  /// told nothing. Two implementations of one landing is a copy however
  /// differently it reads, and these had drifted as copies do.
  ///
  /// ⚠️No `setState`: the unmount lands through here, and a defunct element
  /// has nothing to rebuild. Every mounted caller ends or rebuilds on its
  /// next line.
  bool _foldOpenBox() {
    final box = _box;
    final session = _session;
    if (box == null || session == null) {
      return false;
    }
    final pending = session.stamp;
    // `_preview.warped()` returns the buffer the PREVIEW is already showing
    // when nothing has changed since, so the landing is the same bytes the
    // screen held rather than a second computation that ought to match.
    // Null is a box that changes no pixel; the stamp itself is a quad too
    // degenerate to warp through.
    final warped = _preview.warped() ?? pending;
    if (identical(warped, pending)) {
      return false;
    }
    // ⚠️Both read BEFORE the stamp is replaced: the quad and the mesh stand
    // on the stamp's own rect.
    final region = _region;
    final landedRegion = region == null ? null : _regionThroughOpenBox(region);
    final carry = floatWarp.carry;
    _recordTransformRecall(box);
    session
      ..stamp = warped
      ..landed = carry;
    if (landedRegion != null) {
      _moveRegion(landedRegion);
    }
    _clearTransform(confirming: true);
    return true;
  }

  /// Where [region] stands once the open box has had its way with it.
  CanvasSelectionRegion _regionThroughOpenBox(CanvasSelectionRegion region) {
    final warp = floatWarp;
    // R20-D3: a warped region collapses to its boundary polygon: the mesh
    // maps the LIFTED pixels, so what is selected afterwards is the warped
    // outline, not the old step list.
    final meshPoints = warp.meshPoints;
    if (meshPoints != null) {
      return CanvasSelectionRegion.shape(
        CanvasSelectionShape(warp.meshBoundary(meshPoints)),
      );
    }
    // R20-D2: an open quad carries the outline through its homography.
    final warpCorners = warp.warpCorners;
    if (warpCorners != null) {
      final base = warp.stampRectCorners();
      final h = base == null ? null : solveHomography(base, warpCorners);
      return h == null
          ? CanvasSelectionRegion.shape(CanvasSelectionShape(warpCorners))
          : region.mapped((point) => applyHomography(h, point));
    }
    return region.mapped(_box!.affine.apply);
  }

  /// Escape: discards the open transform. A lift the Ctrl+T itself
  /// opened (and that never moved otherwise) reverts whole — the picture
  /// returns byte-exactly.
  void _cancelTransform() {
    if (_transform == null) {
      return;
    }
    // ↩️`!_moveSessionDirty` stood here too, so a box that had been MOVED
    // only closed and left its float pending while a box that had been
    // scaled reverted whole — two answers to 「취소」 depending on which
    // handle you had used. That distinction was real only while the move
    // lived outside the affine: clearing the box now undoes the move with
    // everything else, so there is nothing left for the extra term to
    // protect. ⛔A session this box did NOT open still only loses the box
    // (`TransformBox.openedLift`), which is the case that term was mixed up
    // with.
    if ((_box?.openedLift ?? false) && _movePending) {
      setState(_clearTransform);
      _revertMoveSession();
      return;
    }
    setState(_clearTransform);
    _syncAnts();
  }

  /// The one door both drag-active signals leave by.
  ///
  /// The transform half is DERIVED from [_drag] rather than raised by
  /// hand at each site, so a future drag kind cannot forget to lower it —
  /// and a stuck touch lock is the kind of bug that only shows up as "the
  /// canvas stopped panning" an hour later.
  void _notifyDragActive(bool active) {
    widget.onDragActiveChanged?.call(active);
    final transform = active && _drag is TransformDrag;
    if (transform != _reportedTransformDrag) {
      _reportedTransformDrag = transform;
      widget.onTransformDragActiveChanged?.call(transform);
    }
  }

  bool _reportedTransformDrag = false;

  /// What the open box reads as, or null when no box is up (the settings
  /// fields then show the identity).
  ///
  /// The channels read the AFFINE, which every mode has — a quad or a mesh
  /// is displacements ON one, not a replacement for it. They used to blank
  /// out here, back when the warp WAS the whole state and there was no
  /// affine left to report.
  ///
  /// ⛔ONE computation, two readers: the pull ([CanvasSelectionCommands.
  /// transformValues]) and the live push ([_publishTransformValues]). A
  /// second spelling is how the panel and the box would come to disagree
  /// about the number they are both showing.
  TransformValues? _transformValuesNow() => _transform?.values;

  void _syncAnts() {
    final animate = _hasSelection || _drag is MarqueeDrag;
    if (animate && !_ants.isAnimating) {
      unawaited(_ants.repeat());
    } else if (!animate && _ants.isAnimating) {
      _ants.stop();
    }
    _publishTransformValues();
    // Every mutation path funnels through here — the settings panel's
    // numeric fields track the session via this (deferred) ping.
    widget.selectionCommands?.notifySessionChanged();
  }

  /// 🗣️유저 2026-09-18 (F-164): 「변형중에 툴도구의 X,Y값같은거 **실시간으로
  /// 바뀌게**」 — and 「**패널리빌드하지말고 글자만 바꾸게**」, which is why
  /// this is a notifier the digits read rather than a ping the panel
  /// rebuilds on.
  ///
  /// ⚠️Called from the drag as well as from [_syncAnts]: a transform drag
  /// deliberately does NOT funnel through the ants (a rebuild per pointer
  /// move on this layer is the R4 #3 hazard), so the numbers would
  /// otherwise sit still until the drag ended — which is the symptom.
  void _publishTransformValues() =>
      widget.selectionCommands?.publishTransformValues(_transformValuesNow());

  void _deselect() {
    // ⚠️「Is there anything to clear」, not 「did the user select」: Ctrl+D
    // over an implicit box still has to take the box away, and that shape
    // is deliberately not a selection.
    if (_region == null && _drag == null) {
      return;
    }
    // 🚨★★★**AN OPEN SESSION LANDS FIRST, AS 확정 LANDS IT** (F-280: 「변형
    // 도구는 기본적으로 확정되고 바뀌도록. 기록도 남기는거 등 법 통일도」) —
    // one undo entry of its own, then the deselect is another.
    //
    // ↩️It landed the float RAW here — 「no history」, the abandon fallback
    // a cel change used to need — so a Ctrl+D over a transform left a
    // picture no undo could bring back: one step back restored the outline
    // and the pixels stayed where they had landed (measured 2026-10-06). A
    // quad or a mesh with every number at rest landed unwarped besides.
    //
    // ↩️That was `_resetAll`, which also took a `keepRegion` for F-86's
    // frame, row and cut moves and a `deferDragNotify` for a reset run from
    // a build. Those moves CARRY the session (2026-09-17) and never came
    // here any more; what is left of the reset is the lines below.
    _confirmSession();
    // The outline as the landing left it — what the deselect's own entry
    // has to put back.
    final before = _region;
    // R26 #13: the implicit whole-picture shape was never a user
    // selection — dropping it records no history.
    final wasImplicit = _shapeIsImplicitWholePicture;
    final wasDragging = _drag != null;
    setState(() {
      _endDrag(cancelled: true, notify: wasDragging);
      // ⚠️Clearing it through [_setRegion] is what also tells the CHANNEL
      // it is gone; the line that used to sit under this one only told the
      // layer.
      _setRegion(null);
      _shapeNeedsLift = false;
    });
    _syncAnts();
    // Deselecting a real region is undoable, symmetric with selecting.
    if (before != null && !wasImplicit) {
      final commit = widget.onShapeCommitted;
      if (commit != null) {
        commit(before, null);
      }
    }
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
    if (lift == null) {
      // ⛔**A FAILED LIFT LEAVES [_shapeNeedsLift] ALONE.** It says 「the
      // pixels under this shape have not been lifted」, and after a lift
      // that found nothing they still have not been. Clearing it here made
      // one flag answer two questions — 「already lifted」 and 「we tried」
      // — and the entrances hid that by dropping the shape on the same
      // breath. The walk to another cel (F-164 ③) keeps its shape, so it
      // is the caller that shows the difference: the same outline over a
      // cel that later gains ink has to be liftable.
      _letGoOfSession();
      return false;
    }
    _shapeNeedsLift = false;
    // ⛔THE ONLY PLACE ONE BEGINS, as [_endSession] is the only place one
    // ends. A session is made whole or not at all.
    _session = _MoveSession(
      token: lift.liftToken,
      stamp: lift.stampDab,
      startShape: region,
    );
    return true;
  }

  /// Lets go of everything the float was — the surface, the centre it was
  /// materialized at, the decoded resample. Call inside a setState, and
  /// only once the landing has been handed to the base: the compose reads
  /// all three.
  ///
  /// All of it, always: a kept resample image that outlived the session
  /// would keep painting one transform state over every later edit.
  void _dropFloat() {
    _floatSurface = null;
    _floatSurfaceCentre = null;
    _floatSurfaceStamp = null;
    _preview.discard();
  }

  /// What is floating right now, in canvas space — see [SelectionFloatPaint].
  ///
  /// The two reasons to draw a float are unchanged; only where the drawing
  /// happens moved. A warp open ⇒ the resampled preview IS the result. A pure
  /// move ⇒ the untouched lift at an offset is byte-exact by short circuit.
  SelectionFloatPaint _floatPaint({
    required ui.Image? resampledImage,
    required BrushDab? resampledDab,
    required BitmapSurface? floatSurface,
    required SelectionAffine? transform,
  }) {
    final pasteboard = widget.canvasSize.pasteboardRect;
    if (resampledImage != null && resampledDab != null) {
      return SelectionFloatPaint(
        image: resampledImage,
        // The landing rect, computed the way the stamp blend computes it: the
        // dab centre rounded to an integer top-left. Previewing at the
        // unrounded position would put a sub-pixel Ctrl+T on screen half a
        // pixel from where it lands.
        imageLeft: (resampledDab.center.x - resampledImage.width / 2)
            .round()
            .toDouble(),
        imageTop: (resampledDab.center.y - resampledImage.height / 2)
            .round()
            .toDouble(),
        // The pasteboard wall, because the landing clips there too
        // (`bitmap_surface_brush_commit`): a selection dragged past the stage
        // edge loses those pixels on Enter, and a preview that kept showing
        // them would be promising something the commit will not deliver.
        clip: pasteboard,
      );
    }
    // ↩️`_drag is MoveDrag` stood here too, from when a move was its own
    // mechanism. An inside grab opens the box now, so that term could only
    // ever be true alongside the one beside it.
    if (floatSurface != null && (transform != null || _movePending)) {
      return SelectionFloatPaint(
        surface: BitmapSurfacePainter(
          surface: floatSurface,
          viewport: widget.viewport,
          showTransparentBackground: false,
          // The float is nobody's cel: its level tiles live in the
          // pyramid's one scope for floats. Not a scope of its own — the
          // pyramid keeps eight, and a session of transforms would push
          // out the `(layerId, frameId)` scopes the brush depends on.
          lineage: TilePyramid.noLineage,
        ),
        surfaceOffset: _floatDrawCanvasOffset,
      );
    }
    return SelectionFloatPaint();
  }

  /// Hands [paint] to the composite, if this layer has one behind it.
  ///
  /// Called from build: the underlay is built BEFORE this layer in the panel's
  /// stack, so the notification reaches a mounted painter and lands in the
  /// same frame. A repaint is all it triggers — no listener here calls
  /// setState — which is what makes a write during build safe.
  void _publishFloat(SelectionFloatPaint paint) {
    final overlay = widget.floatOverlay;
    if (overlay == null) {
      return;
    }
    overlay.value = paint.isEmpty ? null : paint;
  }

  CanvasPoint _toCanvas(Offset local) =>
      widget.viewport.viewportOffsetToCanvas(local);

  void _handlePointerDown(PointerDownEvent event) {
    // 🚨★★★**A PRESS THAT LANDED ON A CONTROL IS THAT CONTROL'S.**
    //
    // 🗣️유저 2026-09-22, saying it for the fifth time and calling it the
    // last: 「왜 **확정/취소버튼을 클릭하면서 드래그하면 회전이 작동**하지?
    // 버튼에 오는 동작은 **버튼이 무조건 가져가야하는거아냐**? … **마지막
    // 경고니까 다신 이딴식으로 하지마. 버튼에 오는 동작은 무조건 버튼꺼야**」.
    //
    // ⛔THE LAW AND ITS KEEPER BOTH ALREADY EXISTED — `control_press_claim`
    // and CLAUDE.md — and the confirm/cancel buttons wore the claim. What
    // was missing is this line: every OTHER surface that starts a drag from
    // the raw stream asks (`canvas_viewport_gesture_layer`,
    // `eager_pan_gesture_recognizer`, `rail_column_swipe`,
    // `instant_tap_region`) and this one did not. Its `Listener` is an
    // ANCESTOR of the buttons floating in it, so the press arrived here
    // after the button had taken it — and a press outside the box is the
    // rotation.
    //
    // ⚠️Ordering is what makes it work and it is not luck: pointer-down is
    // dispatched deepest-first, so the button's claim is already recorded
    // by the time this ancestor hears the same event.
    if (controlOwnsTap(event.pointer)) {
      return;
    }
    if (_drag != null) {
      // A second TOUCH is the navigate signal (same rule as strokes):
      // cancel the selection drag and let the gesture layer take over.
      //
      // EXCEPT while a transform handle is being dragged, where it is the
      // MODIFIER — neither cancel nor navigate. 유저 08-13 asked only that
      // it stop cancelling; 09-22 gave it the meaning. ⚠️The reasoning of
      // both decisions lives on [_modifierTouch] — read it before moving
      // this.
      if (event.kind == PointerDeviceKind.touch && _drag is! TransformDrag) {
        setState(() => _endDrag(cancelled: true, notify: true));
        _syncAnts();
      } else if (event.kind == PointerDeviceKind.touch) {
        _modifierTouch ??= event.pointer;
      }
      return;
    }
    // TS9 (유저: 1핑거가 플립모드인데도 선택툴고르고 터치하면 선택이 작동함.
    // 드로잉모드가 아닌이상은 툴이 작동하면 안되지): a finger drives a tool
    // only while the one-finger slot says draw. Declining QUIETLY is the
    // point — the panel's gesture layer is an ancestor and owns that touch,
    // and it can only take it if the event still reaches it.
    //
    // Below the second-touch branch above deliberately: that one is about a
    // drag already in progress, which a rejected pointer can never have
    // started.
    if (!AppInput.toolAcceptsPointer(
      event.kind,
      oneFinger: widget.oneFingerAction,
    )) {
      return;
    }
    // No tool this layer mounts for is one a pen's tail holds.
    if (!canvasPressIsTheTools(event, tailsToolInHand: (_) => false)) {
      return;
    }
    final canvasPoint = _toCanvas(event.localPosition);
    final pressed = _pressOnImplicitBox(event);
    if (pressed == null) {
      return;
    }
    final box = pressed.box;
    final insideImplicitBox = pressed.insideImplicitBox;
    if (box != null) {
      // The open box is modal: only the box's handles/inside react;
      // clicks elsewhere are inert until Enter/Escape closes the session.
      _beginTransformDrag(box, event, canvasPoint);
      return;
    }
    if (widget.tool == CanvasSelectionTool.move) {
      if (!_beginMovePress(
        event,
        canvasPoint,
        insideImplicitBox: insideImplicitBox,
      )) {
        return;
      }
    } else if (_tapsVertices) {
      // The polygon places points; it has no drag verb at all, so the
      // press only records where the tap aimed and the release decides
      // what it meant.
      setState(() {
        _drag = VertexTapDrag(
          pointer: event.pointer,
          tapStart: event.localPosition,
        );
      });
    } else {
      // The marquee tools ALWAYS draw a NEW polygon — even starting
      // inside the current region (moving lives on the Move tool). The
      // region already selected STAYS on screen through the drag (R26
      // #16: with add/subtract/intersect the user must see what the new
      // polygon is about to fold into — the PS/CSP read), and the RELEASE
      // records the combination as one undoable step. A pending move
      // session confirms first (R16-①: never revert, always confirm).
      //
      // The shape tool on a frame with no cel asks for one first
      // ([CanvasSelectionLayer.onPressNeedsCel]). A press refused traces
      // nothing: the host has said why, and there is nowhere to draw.
      if (widget.tool == CanvasSelectionTool.drawShape &&
          !(widget.onPressNeedsCel?.call() ?? true)) {
        return;
      }
      _confirmMoveSession();
      setState(() {
        _drag = MarqueeDrag(
          pointer: event.pointer,
          shapeKind: widget.shapeKind,
          // Nothing to stash for the verbs that never touch the region: the
          // drag leaves it alone, so a cancel has nothing to put back.
          before:
              widget.tool == CanvasSelectionTool.cut ||
                  widget.tool == CanvasSelectionTool.fillShape ||
                  widget.tool == CanvasSelectionTool.drawShape
              ? null
              : _region,
          at: canvasPoint,
        );
      });
    }
    _notifyDragActive(true);
    _syncAnts();
  }

  /// R17-U 핸들 상시: with the always-on box (Move tool), grabbing a
  /// scale/rotate HANDLE promotes the implicit box into a real session
  /// on the spot — the lift happens here, at the first interaction.
  ///
  /// Null when the press was refused (the lift failed); otherwise the
  /// session now open (the one already open, or the one this press opened)
  /// and — TP4 — whether the press landed inside the box the Move tool is
  /// DRAWING even though no session is open yet, which is a grab, whatever
  /// the selection's own outline says (유저: "변형툴 내부 사각형 안이라면
  /// 언제든 작동하도록").
  ({TransformBox? box, bool insideImplicitBox})? _pressOnImplicitBox(
    PointerDownEvent event,
  ) {
    final open = _box;
    if (open != null ||
        !widget.alwaysShowTransformBox ||
        widget.tool != CanvasSelectionTool.move ||
        widget.onLiftRequested == null) {
      return (box: open, insideImplicitBox: false);
    }
    // R26 #13: with NO selection the always-on box frames the WHOLE
    // picture — grabbing one of its handles opens the session on the
    // implicit whole-canvas shape.
    final implicitRegion =
        _region ?? CanvasSelectionRegion.shape(_wholeCanvasShape());
    final bounds = _regionBounds(implicitRegion);
    // The box already on screen, asked before it is open: a handle press
    // makes it the open one, anything else leaves it unopened.
    final candidate = TransformBox(
      affine: SelectionAffine(pivot: bounds.center),
      baseWidth: bounds.width,
      baseHeight: bounds.height,
    );
    final handle = _onScreen.hitTestTransformHandle(
      event.localPosition,
      candidate,
    );
    if (handle == null || handle == TransformHandle.inside) {
      // Inside/miss: fall through to the ordinary move-drag flow — but
      // remember WHICH (TP4). "Inside" is the box the user can see, and
      // the box is the promise: 유저 확정 (변형툴 라운드 ④) already said
      // 사각형(박스)을 잡아야 해당 기능, while the flow below asked the
      // REGION instead. A lasso's box has corners the outline does not
      // fill, and pressing there did nothing at all.
      return (
        box: null,
        insideImplicitBox: handle == TransformHandle.inside,
      );
    }
    if (_region == null) {
      setState(
        // The implicit region IS the whole-canvas shape on this branch
        // (`_region` is null), so it is one polygon.
        () => _adoptImplicitWholePictureShape(implicitRegion.singleShape!),
      );
    }
    final hadPendingLift = _pendingLiftStamp != null;
    if (!_ensureLifted(implicitRegion)) {
      setState(_clearFailedImplicitShape);
      _syncAnts();
      return null;
    }
    setState(() {
      _box = candidate..openedLift = !hadPendingLift;
      _syncOffsetsToMode();
      _floatSurface = _buildFloatSurface();
    });
    return (box: candidate, insideImplicitBox: false);
  }

  /// The MOVE tool drags the selected content; outside a REAL region it
  /// does nothing (R11-⑧). R26 #13 revises the no-selection half: with no
  /// region at all, a press inside the canvas targets the WHOLE picture
  /// through the implicit whole-canvas shape. False when the press was
  /// refused; true once the move drag is open.
  bool _beginMovePress(
    PointerDownEvent event,
    CanvasPoint canvasPoint, {
    required bool insideImplicitBox,
  }) {
    var targetShape = _region;
    if (targetShape == null) {
      // A press anywhere on the PASTEBOARD grabs the whole picture (PS
      // move grammar) — the implicit shape itself may be the tighter
      // ink bounds, which would make small drawings fiddly to grab.
      //
      // The pasteboard, not the canvas rect: the box this press opens
      // frames pasteboard ink now, and its HANDLES were already
      // grabbable out there (BoxOnScreen.hitTestTransformHandle has no such
      // gate), so a canvas-only gate meant the drawing you could see
      // framed was one you could not grab by pressing on it.
      final onStage = widget.canvasSize.containsPasteboardPoint(
        x: canvasPoint.x,
        y: canvasPoint.y,
      );
      if (widget.onLiftRequested == null || !onStage) {
        return false;
      }
      setState(() {
        targetShape = _adoptImplicitWholePictureShape(_wholeCanvasShape());
      });
    } else if (!targetShape.containsPoint(canvasPoint) &&
        !insideImplicitBox) {
      // TP4: inside the drawn box counts as a grab. What MOVES is still
      // the region's own pixels — the box widened the door, not the
      // thing being carried through it.
      return false;
    }
    final liftShape = targetShape;
    // ⚠️Read BEFORE the lift, and it is the same question `_beginTransform`
    // asks: did this gesture open the session, or ride one that was
    // already pending? 취소 needs it — a box that opened the lift reverts
    // the whole thing, one that rode a pending move only loses the box.
    final hadPendingLift = _pendingLiftStamp != null;
    // R14-④/R19 pixel model: the shape's PIXELS are the content — the
    // first gesture on a selection (or on a confirmed landing) lifts
    // them fresh from the current raster.
    if (liftShape == null ||
        widget.onLiftRequested == null ||
        !_ensureLifted(liftShape)) {
      setState(_clearFailedImplicitShape);
      _syncAnts();
      return false;
    }
    setState(() {
      // 🚨★★★**AN INSIDE GRAB IS A TRANSFORM WHOSE ONLY VALUE IS tx/ty.**
      // ↩️It used to be a second mechanism — the drag moved the lifted
      // stamp and the region while the affine sat at zero — so the panel's
      // X/Y never budged (유저 2026-09-22) and a confirm over a frame range
      // had only a displacement to hand the other cels. One box, one set of
      // numbers, and 「선택을 하던 안하던 … 다른 법 안두는게 절대규칙」.
      //
      // ⚠️Opening it here rather than refusing: with the Move tool the box
      // is already on screen (R17-U), so this is the moment the numbers
      // behind it start existing, not a new thing appearing.
      if (_box == null) {
        _aimTransformAt(liftShape);
        _box!.openedLift = !hadPendingLift;
        _syncOffsetsToMode();
      }
      final affine = _box!.affine;
      // ⚠️AFTER the box exists: an inside grab that opened it steps back
      // to the box as it opened, which is what the user sees.
      _pushTransformStep();
      _drag = MoveDrag(
        pointer: event.pointer,
        txAtStart: affine.tx,
        tyAtStart: affine.ty,
      );
      _floatSurface = _buildFloatSurface();
    });
    return true;
  }

  void _beginTransformDrag(TransformBox box, PointerDownEvent event, CanvasPoint canvasPoint) {
    final openTransform = box.affine;
    // 메쉬: the control points ARE the handles. Nothing else on the box
    // has a grid meaning, so a press is either a point or inside.
    final meshPlaced = floatWarp.placedMeshPoints;
    if (meshPlaced != null) {
      final pointIndex = _onScreen.hitTestPlacedPoint(
        event.localPosition,
        meshPlaced,
      );
      if (pointIndex == null &&
          !CanvasSelectionShape(
            floatWarp.meshBoundary(meshPlaced),
          ).containsPoint(canvasPoint)) {
        return;
      }
      _startTransformDrag(
        WarpPointDrag(
          pointer: event.pointer,
          startPointer: canvasPoint,
          points: pointIndex == null ? null : [pointIndex],
          startOffsets: List.of(box.warp.mesh ?? const []),
        ),
      );
      return;
    }
    // 퍼스: the four corners move freely — no modifier, because the MODE
    // is the door now (the Ctrl+corner gesture this replaces could not
    // be reached at all on a tablet). The edge handles and the rotate
    // knob keep their affine meaning underneath, which is where
    // non-uniform scaling lives.
    //
    // ↩️「The edge handles … keep their affine meaning」 stopped being true
    // with F-42-Q1 (an edge carries its two quad corners), and F-42's 08-31
    // report moved where they STAND too: the middle of their quad edge
    // ([BoxOnScreen.scaleHandleViewport]). The rotate knob keeps the affine
    // box's.
    final cornersPlaced = floatWarp.placedCorners;
    if (cornersPlaced != null) {
      final cornerIndex = _onScreen.hitTestPlacedPoint(
        event.localPosition,
        cornersPlaced,
      );
      if (cornerIndex != null) {
        _startTransformDrag(
          WarpPointDrag(
            pointer: event.pointer,
            startPointer: canvasPoint,
            points: [cornerIndex],
            startOffsets: List.of(box.warp.corners ?? const []),
          ),
        );
        return;
      }
      // A warped quad's inside is the quad, not the affine box the edge
      // handles frame — a press in the gap between them is a miss.
      if (!BoxWarp.offsetsAreZero(box.warp.corners) &&
          !CanvasSelectionShape(cornersPlaced).containsPoint(canvasPoint) &&
          _onScreen.hitTestTransformHandle(event.localPosition, box) ==
              TransformHandle.inside) {
        return;
      }
    }
    final handle = _onScreen.hitTestTransformHandle(event.localPosition, box);
    if (handle == null) {
      return;
    }
    // 🚨F-42 (유저 2026-08-29): 「오른쪽 중앙 조절시 **상하가 안바뀌게
    // 스냅되있는데 스냅해제. 자유롭게 바뀌게**」.
    //
    // ⛔IT WAS NEVER A SNAP — it was geometry. The edge handle drove an
    // affine one-axis SCALE, and a scale cannot move a point along the
    // axis it does not scale, so dragging the right handle up did
    // nothing however far the hand went. 유저 chose (F-42-Q1) to make the
    // handle carry the edge's two QUAD corners instead: in 퍼스 the box
    // is a quad and its edge is a pair of points, so this is the handle
    // finally meaning what the mode does.
    //
    // ⚠️The accepted cost: 「stretch one axis」 is no longer this handle's
    // job in 퍼스. It is two corners dragged together, which is the same
    // move with the same result and one more gesture.
    final edgePair = _mode == TransformMode.perspective
        ? BoxOnScreen.edgeCornerPair(handle)
        : null;
    if (edgePair != null && cornersPlaced != null) {
      _startTransformDrag(
        WarpPointDrag(
          pointer: event.pointer,
          startPointer: canvasPoint,
          points: edgePair,
          startOffsets: List.of(box.warp.corners ?? const []),
        ),
      );
      return;
    }
    _startTransformDrag(
      BoxHandleDrag(
        pointer: event.pointer,
        startPointer: canvasPoint,
        handle: handle,
        start: openTransform,
        // Only a rotation reads it, and it needs the angle the press
        // was at so the first move is a delta rather than a jump.
        modifierHeld: _scaleModifierHeld,
        lastAngle: handle == TransformHandle.rotate
            ? TransformBoxLaw.angleAbout(
                _turnCentreOf(openTransform),
                canvasPoint,
              )
            : 0,
      ),
    );
    return;
  }

  /// Begins a drag on the open box: the STEP first, then the drag.
  ///
  /// ⛔One place, because all four branches above already said the same
  /// three lines and the step has to be taken before the drag can move
  /// anything. A branch that forgot it would be a gesture the user could
  /// not take back, and nothing else would notice.
  void _startTransformDrag(TransformDrag drag) {
    _pushTransformStep();
    setState(() => _drag = drag);
    _notifyDragActive(true);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final drag = _drag;
    if (drag == null || event.pointer != drag.pointer) {
      return;
    }
    switch (drag) {
      case VertexTapDrag():
        // Nothing follows the pointer: the vertex was aimed on the way
        // down and only the release decides whether it lands.
        return;
      case MarqueeDrag():
        setState(() => drag.update(_toCanvas(event.localPosition)));
      case MoveDrag():
        setState(() {
          drag.screenDelta += event.delta;
          // ⚠️The rounding is [_moveCanvasDelta]'s and it is the whole of
          // 유저's 「캔버스쪽 직접 손으로 끌어서 이동하는거는 소수점은
          // 이동안되게. 즉 스냅. 15다음이 15.2 이런식말고 16되도록」 — the
          // TOTAL is rounded, not each step, so a slow drag cannot drift.
          // ⛔Typed values are not rounded: 「확대축소는 소수점 이동해도
          // 되는데」 splits by ENTRANCE, not by a mode.
          final moved = _moveCanvasDelta;
          final box = _box;
          if (box != null) {
            box.affine = box.affine.copyWith(
              tx: drag.txAtStart + moved.x,
              ty: drag.tyAtStart + moved.y,
            );
          }
          if (moved.x != 0 || moved.y != 0) {
            _session?.moved = true;
          }
        });
        _publishTransformValues();
        // ⛔A PURE TRANSLATION DOES NOT RESAMPLE. `transformStampDab`
        // carries it by moving the stamp's centre, so scheduling here
        // would decode the same megabyte image once per pointer move for
        // a picture that has not changed a pixel.
        if (_transform?.isPureTranslation == false) {
          _preview.schedule();
        }
      case TransformDrag():
        _updateTransformDrag(drag, _toCanvas(event.localPosition));
    }
  }

  /// Every branch below mutates the open warp, and every one of them must
  /// then ask the preview to catch up. Wrapping rather than sprinkling the
  /// call through five early returns is the difference between "the mesh
  /// preview stopped updating" being impossible and being a future bug.
  void _updateTransformDrag(TransformDrag drag, CanvasPoint pointer) {
    _updateTransformDragGeometry(drag, pointer);
    _preview.schedule();
  }

  void _updateTransformDragGeometry(TransformDrag drag, CanvasPoint pointer) {
    final box = _box;
    if (box == null) {
      // The box closed under the drag (Escape mid-gesture). The contact is
      // still down and its release still lowers the drag flags, but there
      // is nothing left to move — see [_clearTransform], which used to say
      // this by nulling this drag's fields from outside it.
      return;
    }
    switch (drag) {
      case WarpPointDrag():
        _dragWarpPoints(drag, box, pointer);
      case BoxHandleDrag():
        _dragBoxHandle(drag, box, pointer);
    }
    // ⚠️AFTER the branch: the re-base inside it reads the previous value.
    drag.lastPointer = pointer;
  }

  /// A control point drag — one corner in 퍼스, one grid point in 메쉬.
  ///
  /// The pointer is pulled back through the affine before it becomes a
  /// displacement, so a point dragged on a rotated box moves the way the
  /// hand did rather than along the box's own axes.
  void _dragWarpPoints(
    WarpPointDrag drag,
    TransformBox box,
    CanvasPoint pointer,
  ) {
    final dragPoints = drag.points;
    if (dragPoints == null) {
      return;
    }
    final startOffsets = drag.startOffsets;
    final affine = box.affine;
    final from = affine.applyInverse(drag.startPointer);
    final to = affine.applyInverse(pointer);
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    // ONE displacement, applied to every point the drag carries: an edge
    // handle moves its two corners by the same vector, so the edge stays
    // straight and its length is preserved unless a corner is dragged
    // afterwards.
    final moved = [
      for (var i = 0; i < startOffsets.length; i += 1)
        if (dragPoints.contains(i))
          CanvasPoint(
            x: startOffsets[i].x + dx,
            y: startOffsets[i].y + dy,
          )
        else
          startOffsets[i],
    ];
    setState(() {
      if (_mode == TransformMode.mesh) {
        box.warp.mesh = moved;
      } else {
        box.warp.corners = moved;
      }
    });
    _syncAnts();
  }

  void _dragBoxHandle(
    BoxHandleDrag drag,
    TransformBox box,
    CanvasPoint pointer,
  ) {
    final start = drag.start;
    switch (drag.handle) {
      case TransformHandle.inside:
        // A hand on the canvas moves in whole pixels, as the drag that
        // opened this box did ([TransformBoxLaw.wholePixels]).
        final moved = TransformBoxLaw.wholePixels(
          CanvasPoint(
            x: pointer.x - drag.startPointer.x,
            y: pointer.y - drag.startPointer.y,
          ),
        );
        setState(() {
          box.affine = start.copyWith(
            tx: start.tx + moved.x,
            ty: start.ty + moved.y,
          );
        });
      case TransformHandle.anchor:
        // 🚨★★★**THE ANCHOR MOVES BY THE SAME DELTA LAW AS EVERY OTHER
        // HANDLE** (F-127): it travels exactly as far as the hand has
        // since the press, so a press that lands 15px off centre does not
        // snap the cross under the pen.
        //
        // ⛔NOTHING CLAMPS IT. 유저 2026-09-20 on the edit values as a
        // whole: 「그 과정에서 **그림이 바깥으로 나가던 뭐던 쓸데없어**.
        // 그건 유저가 그렇게 하고싶지않으면 **생각해서 할일**이야」 — and
        // the anchor is an edit value like any other.
        setState(() {
          box.affine = start.copyWith(
            anchorX: start.anchorX + pointer.x - drag.startPointer.x,
            anchorY: start.anchorY + pointer.y - drag.startPointer.y,
          );
        });
      case TransformHandle.rotate:
        // Every box turns by the one turn law ([TransformBoxLaw.turn]):
        // wrapped deltas, canvas-space angles.
        final current = box.affine;
        final step = TransformBoxLaw.turn(
          centre: _turnCentreOf(current),
          pointer: pointer,
          lastAngle: drag.lastAngle,
        );
        drag.lastAngle = step.angle;
        setState(() {
          box.affine = current.copyWith(
            rotationDegrees: current.rotationDegrees + step.turned,
          );
        });
      case TransformHandle.topLeft:
      case TransformHandle.topRight:
      case TransformHandle.bottomRight:
      case TransformHandle.bottomLeft:
      case TransformHandle.topEdge:
      case TransformHandle.rightEdge:
      case TransformHandle.bottomEdge:
      case TransformHandle.leftEdge:
        // 🚨F-127 (유저 2026-09-13): 「펜만 … 꼭짓점 클릭시작하면 그 순간
        // 변형이 커진다거나? … 마우스는 그냥 클릭해도 클릭한다고 변형이
        // 바뀌지 않는데」. The handle used to be put UNDER the pointer, so a
        // press anywhere in the 16px grab radius jumped it there on the first
        // move — and a pen always moves. The inside drag and the rotation
        // were already deltas; the scale handles are too now.
        //
        // 🚨★★★**A MODIFIER THAT ARRIVES MID-DRAG RE-BASES, IT DOES NOT
        // RESET.** 유저 2026-09-22: 「확대/축소 중 수정자 들어오면 **위치값
        // 이나 확대축소 이런거 초기화같은거 하지말고** 해당 상황에서 수정자
        // 적용해서 **다음부터 적용**되도록」. The solve runs from the press
        // every move, so a changed anchor would re-solve the whole drag and
        // jump the picture. Moving the press to HERE keeps every number and
        // changes only what the next movement does.
        final held = _scaleModifierHeld;
        if (held != drag.modifierHeld) {
          drag
            ..modifierHeld = held
            ..start = box.affine
            ..startPointer = drag.lastPointer;
        }
        final from = drag.start;
        final grabbed = handleLocal(
          drag.handle,
          box.baseWidth,
          box.baseHeight,
        )!;
        // Which point stays put comes from [_scaleModifierHeld] and nothing
        // else: the box's centre by default, the opposite handle while the
        // modifier is held ([TransformBoxLaw.scaled]). The tablet is why the
        // modifier has two entrances — the pen is already on the handle, so
        // "hold Alt" there means a second hand on the glass, and that hand
        // IS the entrance.
        setState(
          () => box.affine = TransformBoxLaw.scaled(
            from,
            grabbed,
            TransformBoxLaw.pressDisplaced(
              from,
              grabbed,
              drag.startPointer,
              pointer,
            ),
            aboutCentre: !held,
            uniform: widget.transformOptions.isUniform,
          ),
        );
    }
    _publishTransformValues();
  }

  /// The TURN's fixed point: the anchor ([SelectionAffine.anchorCanvas]),
  /// which a turn leaves where it is.
  ///
  /// 🚨It was the BOX CENTRE (`apply(pivot)`) until 2026-09-25: right while
  /// the box turned about its centre, wrong from the day it turned about the
  /// anchor (09-20). The centre orbits the anchor, so each move read the
  /// hand against a centre the last move had carried off — the box lagged
  /// the hand, and a hand held still kept turning it (유저: 「십자 앵커 위치
  /// 바꾸고 사각형 바깥 조작해서 회전시킬때 아직도 전위치랑 현위치랑
  /// 순간이동」). Measured: a still pen turned it 2.3°.
  CanvasPoint _turnCentreOf(SelectionAffine affine) => affine.anchorCanvas;

  void _handlePointerUp(PointerUpEvent event) {
    // The modifier finger lifting is not the drag ending — it changes what
    // the NEXT move solves, and nothing else.
    if (event.pointer == _modifierTouch) {
      _modifierTouch = null;
      return;
    }
    final drag = _drag;
    if (drag == null || event.pointer != drag.pointer) {
      return;
    }
    // A release is the COMMIT half of [SelectionDrag]'s lifecycle, so the
    // end below is not a cancel — a finished marquee keeps what it folded
    // in rather than having its BEFORE region put back.
    switch (drag) {
      case MarqueeDrag():
        _finishMarquee(drag);
      case MoveDrag():
      case TransformDrag():
        // The session stays open across drags; Enter/Escape close it.
        //
        // ↩️A move used to LAND here — it walked the stamp and the region
        // over by the drag's delta on every release. The affine holds the
        // move now, so a release has nothing of its own to do and the two
        // drags end the same way, which is the point.
        break;
      case VertexTapDrag():
        _placeVertex(drag);
    }
    setState(() => _endDrag(cancelled: false, notify: true));
    _syncAnts();
  }

  /// A polygon tap has come off: close the trace if it aimed at the first
  /// vertex, otherwise extend it.
  void _placeVertex(VertexTapDrag drag) {
    final commands = widget.selectionCommands;
    final down = drag.tapStart;
    if (commands == null) {
      return;
    }
    final tapped = _toCanvas(down);
    final points = commands.polygonPoints;
    if (points.isNotEmpty && _aimsAtCloseTarget(down, points.first)) {
      // TS6: the ring is on offer from the FIRST vertex, so a tap on it
      // always ends the trace — closing it when three points enclose
      // something, and otherwise just abandoning it (유저: "1점상태나
      // 2점상태든 불가능할땐 그냥 취소시켜버리면 되잖아. 클튜도 그렇게해").
      //
      // That is what lets the ring appear immediately without promising a
      // tap that would do nothing: the promise is "this ends here", and it
      // is kept at every count.
      if (commands.canClosePolygon) {
        _closeOpenPolygon();
      } else {
        commands.abandonPolygon();
        _syncAnts();
      }
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
    if (event.pointer != _drag?.pointer) {
      return;
    }
    setState(() => _endDrag(cancelled: true, notify: true));
    _syncAnts();
  }

  /// [handle], for as long as this layer is in the tree.
  ///
  /// 🚨A POINTER GOES ON REPORTING TO THE LAYER ITS DOWN WAS HIT-TESTED ON,
  /// MOUNTED OR NOT. A change of tool takes this layer away, and one can
  /// come while a button is still down on it: a mapped button held for the
  /// eyedropper (F-299 — the press itself is what changes the tool), or a
  /// tool key pressed in the middle of a drag. The rest of that pointer's
  /// moves and its lift still arrive here, at a layer that has landed what
  /// it held and let go of everything ([dispose]); it reads nothing of
  /// them. ↩️It wrote the cursor's notifier after it was disposed, and
  /// would have rebuilt a defunct element for a drag still in hand.
  ///
  /// ⚠️Moves, lifts and cancels only: a DOWN and a hover are hit-tested
  /// afresh, so neither can reach a layer that is gone.
  void Function(E event) _whileMounted<E extends PointerEvent>(
    void Function(E event) handle,
  ) => (event) {
    if (mounted) {
      handle(event);
    }
  };

  /// Ends the live drag — dropping the object IS the end ([SelectionDrag]),
  /// so nothing here clears per-mode fields.
  ///
  /// NOT the committed selection, and NOT an open Ctrl+T session: its float
  /// persists between handle drags, and R16-①'s move SESSION survives the
  /// gesture (the float keeps rendering at its pending position until the
  /// user confirms).
  ///
  /// ⛔[cancelled] is the OTHER half of the lifecycle, and exactly one of
  /// the two closes a drag. A CANCELLED marquee leaves the region exactly
  /// as the drag found it; a finished one keeps what the release folded in.
  /// This used to be one path that read a stash [_finishMarquee] had
  /// emptied on its way past — the same fact in two places, and only the
  /// order of two calls kept them agreeing.
  void _endDrag({required bool cancelled, required bool notify}) {
    final drag = _drag;
    // Leaving a handle drag widens the preview back to the whole rect:
    // the clip is a drag-time measure, and at rest the box has to be
    // correct wherever the user looks next. It is also what lets the
    // commit reuse this buffer instead of computing a second one.
    final wasTransformDrag = drag is TransformDrag;
    if (cancelled && drag is MarqueeDrag && drag.before != null) {
      _setRegion(drag.before);
      _shapeNeedsLift = true;
    }
    _drag = null;
    if (_transform == null && !_movePending) {
      _floatSurface = null;
    }
    if (wasTransformDrag && _transform != null) {
      _preview.schedule();
    }
    if (notify && drag != null) {
      _notifyDragActive(false);
    }
  }

  /// The mode this drag folds under (R26 #16): the tool setting, unless
  /// the PS/CSP modifier chord overrides it for this one drag — Shift
  /// adds, Alt subtracts, Shift+Alt intersects. The modifiers are read at
  /// RELEASE, matching how both apps behave when you change your mind
  /// mid-drag. (Neither key means anything else on a marquee: Alt's held
  /// eyedropper stands down for the tools whose drag reads Alt
  /// (`canvasToolReadsAlt` — this one and the transform), and Shift/Alt
  /// only steer an OPEN transform box, never a marquee.)
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

  void _finishMarquee(MarqueeDrag drag) {
    if (widget.tool == CanvasSelectionTool.drawShape) {
      // The one verb that takes the PATH: a line has no outline to commit,
      // and what the drag traced is drawn rather than folded into anything.
      final path = drag.path();
      if (path != null) {
        widget.onDrawShape?.call(path);
      }
      return;
    }
    _commitDrawnOutline(drag.shape(), before: drag.before);
  }

  /// Where every finished outline lands, whoever traced it — a marquee
  /// drag, a lasso, or a closed polygon. The tracing is the only part that
  /// differs between shapes; what a finished outline MEANS is the verb's.
  void _commitDrawnOutline(
    CanvasSelectionShape? drawn, {
    required CanvasSelectionRegion? before,
  }) {
    // CUT and SHAPE FILL stop here: the outline goes to the slot or to the
    // paint, and the selection is left alone. 유저 확정: "잘라내기는
    // 잘라내기만이야. 그러니 선택으로 남지 않아" — the same law reads for
    // the shape fill, which fills what you drew rather than choosing it.
    // So there is no combine mode to apply, no history entry to record for
    // the region, and no stashed shape to consume.
    if (widget.tool == CanvasSelectionTool.cut) {
      if (drawn != null) {
        widget.onCutShape?.call(drawn);
      }
      return;
    }
    if (widget.tool == CanvasSelectionTool.fillShape) {
      if (drawn != null) {
        widget.onFillShape?.call(drawn);
      }
      return;
    }
    // R26 #16: the drawn polygon FOLDS into the region under the active
    // mode. A click (degenerate polygon) still deselects in 갱신 mode —
    // Photoshop's click-away — and is inert in the other three.
    final folded = CanvasSelectionRegion.combineCopies(
      before,
      _symmetryCopies(drawn),
      _marqueeMode(),
    );
    if (identical(folded, before)) {
      // Nothing folded (a click in add/subtract/intersect, or with nothing
      // selected): no history — and no door either, so a selection kept
      // from a larger cut's wall is not cut by a click.
      return;
    }
    // 🚨THE STAGE DOOR (I-23): what lands is cut at the pasteboard wall —
    // marquee, ellipse and lasso on release, the polygon on its close.
    final after = folded?.clippedTo(widget.canvasSize.pasteboardRect);
    if (before == after) {
      // The wall left nothing to change (an 추가 wholly past it).
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

  /// Every copy a symmetry guide makes of a drawn outline, the original
  /// first — the SAME list the brush replicates a stroke over, from the
  /// same [symmetryTransforms]. Empty for a degenerate drag, which is what
  /// [CanvasSelectionRegion.combineCopies] reads as a click.
  ///
  /// A copy that lands entirely off the canvas is kept, not dropped: a
  /// selection may extend past the edge (the pasteboard is a real place),
  /// and dropping it would make the mirror silently asymmetric.
  ///
  /// ⚠️Past the pasteboard WALL is another matter (I-23): the stage door in
  /// [_commitDrawnOutline] cuts every copy there alike, and drops one with
  /// nothing inside — the wall is the edge of the world for a mirror's
  /// copy as much as for the drag that made it.
  List<CanvasSelectionShape> _symmetryCopies(CanvasSelectionShape? drawn) {
    if (drawn == null) {
      return const [];
    }
    final symmetry = widget.symmetry;
    if (symmetry == null) {
      return [drawn];
    }
    return [
      for (final copy in symmetryTransforms(symmetry))
        if (copy.isIdentity)
          drawn
        else
          CanvasSelectionShape([
            for (final point in drawn.points) copy.apply(point),
          ]),
    ];
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
      _letGoOfSession();
      if (region == null) {
        _clearTransform();
      }
    });
    _syncAnts();
  }

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
    CanvasShapeKind.line => false,
  };

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

  /// The float's surface: the pending stamp's IMAGE materialized once, at
  /// the centre the stamp had then.
  ///
  /// Asked again for the same image, it answers with the same surface. A
  /// move changes the stamp's centre and not its pixels, and
  /// [_floatDrawCanvasOffset] carries the difference — so the float's
  /// tiles are made once per lift and pictured once. Every site that used
  /// to rebuild here (a second drag, Ctrl+T over a pending move, Escape
  /// out of it) was making new tile objects for the same pixels — the
  /// F-68 family's raw material, plus 651 ms to re-materialize a
  /// 2340×1654 cel scaled to the pasteboard. Only a different image
  /// builds: a fresh lift, or a warp folded into the stamp.
  BitmapSurface _buildFloatSurface() {
    final pending = _pendingLiftStamp;
    final existing = _floatSurface;
    if (existing != null &&
        pending != null &&
        identical(pending.stamp, _floatSurfaceStamp)) {
      return existing;
    }
    final surface = BitmapSurface(canvasSize: widget.canvasSize);
    // Recorded HERE so every build zeroes the drift by construction —
    // [_floatDrawCanvasOffset] measures from the place the surface was
    // actually materialized at, not from the lift, so a build mid-session
    // cannot leave an offset applied twice.
    _floatSurfaceCentre = pending?.center;
    _floatSurfaceStamp = pending?.stamp;
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

  /// The stamp IMAGE [_floatSurface] was materialized from — the identity
  /// [_buildFloatSurface] reuses the surface by.
  BrushStampImage? _floatSurfaceStamp;

  /// Where the float is drawn relative to its own surface: the live drag
  /// offset, plus the drift its stamp has accumulated since the surface was
  /// built — in CANVAS space (TS1).
  ///
  /// A move used to rebuild the surface at the new centre, which is what
  /// made the confirm frame blank: the rebuilt tiles were new objects with
  /// no decoded images, so the held float could paint only the painter's
  /// four-tile budget of the day and 44% of a wide landing was simply
  /// absent. The surface's tiles are pictured ONCE now and a translation
  /// is a translation — which still saves the rebuild and its pictures,
  /// though no paint can come out blank any more (2026-09-17).
  ///
  /// The drag delta is measured on SCREEN and the drift on the canvas, so the
  /// two have to meet somewhere; they used to meet in screen space because
  /// the float wrapped widgets. It draws inside a viewport-transformed canvas
  /// now, so they meet here instead — and the drag delta comes back through
  /// the same mapping that carried it out, rotation and flip included.
  CanvasPoint get _floatDrawCanvasOffset {
    // ⚠️Read off the AFFINE, not off the drag: the move lives there now,
    // so this is also what carries it between drags — the stamp no longer
    // moves and the drift below is zero until a warp folds into it.
    final affine = _transform;
    final dragged = affine == null
        ? CanvasPoint(x: 0, y: 0)
        : CanvasPoint(x: affine.appliedTx, y: affine.appliedTy);
    final from = _floatSurfaceCentre;
    final to = _pendingLiftStamp?.center;
    if (from == null || to == null) {
      return dragged;
    }
    return CanvasPoint(
      x: dragged.x + (to.x - from.x),
      y: dragged.y + (to.y - from.y),
    );
  }

  @override
  Widget build(BuildContext context) {
    final floatSurface = _floatSurface;
    final transform = _transform;
    final region = _region;
    final warpCorners = floatWarp.warpCorners;
    // The image and the dab it was decoded from travel together, so the
    // rect the preview draws into always belongs to the pixels in it.
    final resampledImage = _preview.image;
    final resampledDab = _preview.imageDab;
    // With an open Ctrl+T session the ants show the TRANSFORMED region
    // and the box chrome renders around the transformed base box. An
    // open QUAD (R20-D2) maps the region through the homography instead.
    final displayShape = _displayShape(transform, region, warpCorners);
    // R17-U 핸들 상시: with the Move tool a selection shows its box
    // chrome even before any session opens (identity affine around the
    // shape bounds; grabbing a handle opens the session at that moment).
    var chromeAffine = transform;
    var chromeWidth = _box?.baseWidth ?? 0;
    var chromeHeight = _box?.baseHeight ?? 0;
    if (chromeAffine == null &&
        widget.alwaysShowTransformBox &&
        widget.tool == CanvasSelectionTool.move &&
        _drag == null) {
      // R26 #13: no selection = the box frames the WHOLE picture (the
      // canvas rect) — grabbing a handle opens the implicit session.
      final bounds = _regionBounds(
        region ?? CanvasSelectionRegion.shape(_wholeCanvasShape()),
      );
      chromeAffine = SelectionAffine(pivot: bounds.center);
      chromeWidth = bounds.width;
      chromeHeight = bounds.height;
    }
    // 메쉬 chrome: the warped boundary with EVERY control point as a
    // handle. 퍼스 chrome: the quad, its four corners, AND the affine
    // box's edge handles and rotate knob underneath — those still work in
    // that mode, so hiding them would hide half the tool.
    //
    // Both read the PLACED points rather than the resample's, so the
    // handles are on screen from the moment the mode is armed instead of
    // appearing only once the first offset makes the warp real.
    final placedMesh = floatWarp.placedMeshPoints;
    final placedCorners = floatWarp.placedCorners;
    final chrome = _onScreen.transformChrome(
      placedMesh,
      placedCorners,
      chromeAffine,
      chromeWidth,
      chromeHeight,
    );
    // While a hold is up, whichever float is drawn is drawn ONLY over the
    // tiles the base cannot paint yet — screen space, because it wraps
    // the painters rather than living inside one of them, and both
    // painters apply the viewport themselves.
    // TS1: one description of what is floating, published for the composite
    // and used by the fallback painter below. Built here because this is
    // where every piece of it is already in scope.
    final floatPaint = _floatPaint(
      resampledImage: resampledImage,
      resampledDab: resampledDab,
      floatSurface: floatSurface,
      transform: transform,
    );
    _publishFloat(floatPaint);
    return Listener(
      key: const ValueKey<String>('canvas-selection-layer'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _cursor.value = event.localPosition;
        _handlePointerDown(event);
      },
      // TS6: hover feeds the rubber band. It is the ONLY thing hover does
      // here, and it writes a notifier rather than state — see [_cursor].
      onPointerHover: (event) => _cursor.value = event.localPosition,
      onPointerMove: _whileMounted((event) {
        _cursor.value = event.localPosition;
        _handlePointerMove(event);
      }),
      onPointerUp: _whileMounted(_handlePointerUp),
      onPointerCancel: _whileMounted(_handlePointerCancel),
      child: Stack(
        children: [
          // 🚨TS1: the float's PIXELS are not in this Stack any more. They
          // are published to [SelectionFloatOverlay] and drawn by whoever
          // draws the active layer, at that layer's depth — so the layers
          // above it occlude the preview exactly as they occlude the
          // committed result, which is what a live stroke has always got.
          // Everything below here is CHROME and stays on top.
          //
          // The fallback for hosts with no composite (the conte, the
          // timesheet, the cut envelope, and the tests that mount this
          // layer alone) is the same description drawn here instead —
          // one painting code path, two mount points.
          if (widget.floatOverlay == null && !floatPaint.isEmpty)
            _floatPreview(floatPaint, context),
          _antsLayer(displayShape, region, chrome),
          // R16-①: the CONFIRM button — in the pill under the box while
          // there is something to confirm.
          //
          // ↩️**IT ASKED `_movePending` ALONE**, and that was the same
          // stale premise the ants carried: when it was written a box could
          // not outlive its float, so 「a float is pending」 and 「there is
          // an edit to land」 were one fact. 유저 확정 2026-09-17 split them
          // — a frame walk lets the float go and KEEPS the box — and from
          // then on the button vanished on a box that was still open.
          //
          // 🗣️유저 2026-09-18 (F-164): 「그리고 **확정버튼도 사라지는**
          // 문제」.
          if ((_movePending || _transform != null) && displayShape != null)
            // 🚨★★★**THE WAY OUT CANNOT LEAVE THE SCREEN.** The bar sat
            // 34px ABOVE the box's top-right, which was safe only while a
            // scale grew the box down and right — it anchors on the corner
            // that never moved. ①센터 기준 makes every scale grow the box
            // UPWARD, so the bar climbs off the top on the first drag and
            // 유저's 「확정/취소만 버튼」 becomes unreachable on a tablet,
            // which has no Enter key to fall back on.
            //
            // ⚠️Its own [Positioned.fill]: the pill is laid out against
            // the layer's SIZE, and this is the only child that needs it.
            Positioned.fill(child: _confirmPill(displayShape, chrome)),
        ],
      ),
    );
  }

  /// 확정 and 취소, side by side in the pill under the box.
  ///
  /// 🗣️유저 2026-09-22: 「상자밖은 기본은 회전에 **확정/취소만 버튼** 만들면
  /// 쉽겟고」 — a press outside the box turns it now, so the way out cannot
  /// be a press outside the box any more. The pair is 클튜's 確定/
  /// キャンセル, which 유저 handed over as the reference.
  ///
  /// ⛔Cancel is wired to [_cancelTransform], which is Escape's own verb —
  /// one law, two entrances. It is not a second way of ending a session.
  Widget _confirmPill(
    CanvasSelectionRegion displayShape,
    SelectionTransformChrome? chrome,
  ) => CanvasTargetPill(
    keyValue: 'selection-confirm-pill',
    target: _pillTarget(displayShape, chrome),
    cover: widget.pillCover,
    children: [_confirmButton(displayShape), _cancelButton()],
  );

  /// What the pill stands under: the box's outline as the screen draws it,
  /// or the shape where no box is drawn.
  ///
  /// ⚠️The OUTLINE's bounds, not the shape's: a turned box reaches past the
  /// shape it carries, so a pill placed under the shape would sit on the
  /// box's lower corner. The handles stand on the outline and need no
  /// asking of their own.
  ///
  /// ⚠️No drag offset: with the move living in the affine, the chrome and
  /// the shape the caller hands are both already TRANSFORMED, so the pill
  /// already rides the box it is supposed to ride.
  Rect _pillTarget(
    CanvasSelectionRegion displayShape,
    SelectionTransformChrome? chrome,
  ) {
    if (chrome != null) {
      return pointsBounds(chrome.box);
    }
    final bounds = displayShape.selectedBounds;
    return pointsBounds([
      for (final (x, y) in [
        (bounds.left, bounds.top),
        (bounds.right, bounds.top),
        (bounds.right, bounds.bottom),
        (bounds.left, bounds.bottom),
      ])
        _mapCanvasToViewportOffset(CanvasPoint(x: x, y: y)),
    ]);
  }

  /// ⛔**THE APP'S ONE BUTTON** (「앱에 버튼은 한 종류」), reused rather than
  /// re-made — 유저 2026-09-22: 「확정/취소버튼은 **우리 ui 있는거
  /// 재사용할수있는거 하고** 아니면 우리스타일로 맞춰서 공용화해서 만들고」.
  ///
  /// ↩️It was a private Material + InkWell + [ControlPressClaim] circle in
  /// this file, wearing the session's red/green. That is a second button to
  /// keep in step with the app's forever, and the colour was chrome talking
  /// about chrome — which [AppIconButton] already refuses (see its
  /// `danger`). The pair says what it is with its ICON, and the box, the
  /// ink, the tooltip and the press law all come from the one widget.
  Widget _cancelButton() => AppIconButton(
    keyValue: 'selection-move-cancel',
    shortcuts: const [EditorActionIds.selectionTransformCancel],
    tooltip: AppText.strings.commonCancel,
    icon: const Icon(Icons.close),
    onPressed: _cancelTransform,
  );

  /// The box's ✓ is 적용 — [_applyTransform], the verb Enter and the tool
  /// settings button reach too (confirm-button: 「입구 하나」). ↩️It carried
  /// a branch of its own, and that is how Enter and this button came to
  /// answer the same box two ways.
  ///
  /// ⚠️[isSelected] is the ON state, and 「this session has changes」 is
  /// exactly that — the same fact the ants and the box already show in the
  /// session's red. The BUTTON says it the app's own way instead of
  /// wearing a colour of its own.
  Widget _confirmButton(CanvasSelectionRegion displayShape) => AppIconButton(
    keyValue: 'selection-move-confirm',
    shortcuts: const [EditorActionIds.confirm],
    tooltip: AppText.strings.commonApply,
    icon: const Icon(Icons.check),
    isSelected: _sessionHasChanges,
    onPressed: _applyAction() == null ? null : _applyTransform,
  );

  Positioned _antsLayer(CanvasSelectionRegion? displayShape, CanvasSelectionRegion? region, SelectionTransformChrome? chrome) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: SelectionAntsPainter(
            repaint: _ants,
            viewport: widget.viewport,
            // 🚨★★★**THE ANTS ARE THE SELECTION'S.** The box draws itself
            // (the chrome below), so a shape that is not a selection gets
            // no ants — which is F-108, said in the one place that draws
            // them rather than as a guard bolted onto each.
            committedRegion: _hasSelection ? displayShape : null,
            // I-38 (유저 2026-09-16): 「변형도구 사용시 기존의 실루엣을
            // 초록색 선으로 보여줌. **확정시 사라짐.** 즉 변형중에는
            // 보이도록」.
            //
            // ⛔The condition is the BOX, not the float: 「변형중」 is what
            // the user said, and a confirm closes the box, which is what
            // makes it go.
            // ⚠️Since 확정 became one verb (confirm-button) no door leaves a
            // session without its box — Enter on an untouched box used to —
            // so this states the law rather than guarding a case a user can
            // reach.
            //
            // 🗣️F-231 ① (유저 2026-09-29): 「기존 초록 프리뷰는 항상 사각형
            // 변형도구 실루엣만으로 작동됨. 이상한 쓸데없는 규칙 넣지말고
            // 기존거에 맞춰서 법 통일하고 잔재 삭제」 — the line is the
            // TRANSFORM TOOL's silhouette, the box it began from, whatever
            // shape the selection has.
            startShape: switch (_box) {
              null => null,
              final box => CanvasSelectionRegion.shape(
                _onScreen.startSilhouette(box),
              ),
            },
            // 🚨F-65: 「라이브로 선택중일땐 … 벡터로 보여도 상관없는데,
            // 선택 커밋될떈 픽셀에 제대로 안착한 상태로」.
            //
            // ★`identical` says exactly that, and says it without a
            // second opinion to keep in sync: every session that is
            // still moving the selection (transform, warp, mesh) hands
            // `displayShape` a NEW region above, and nothing else
            // does. When the outline has settled the two ARE the same
            // object.
            outlineIsLive: !identical(displayShape, region),
            // TP5: the ants step with the PIXELS, not with the
            // pointer — the outline has to be around the thing that
            // will land, or the confirm looks like it moved.
            //
            // ↩️A MoveDrag used to need an offset of its own here,
            // because the region stood still until the release landed
            // it. The move is the affine's now, so `displayShape` above
            // already carries it — and adding the drag on top would
            // step the ants twice.
            screenOffset: Offset.zero,
            // What the release will land: each copy cut at the wall by the
            // same door [_commitDrawnOutline] takes (I-23).
            marqueeShapes: [
              for (final copy in _symmetryCopies(_marqueeDrag?.shape()))
                ?copy.clippedTo(widget.canvasSize.pasteboardRect),
            ],
            openTrail: _tapsVertices
                ? (widget.selectionCommands?.polygonPoints ?? const [])
                : (_marqueeDrag?.openTrail ?? const []),
            // TS6: from the FIRST vertex, not from the third. It used
            // to wait for `canClosePolygon` so the ring never offered
            // a tap that would do nothing — and the answer to that was
            // not to hide it but to make the tap always mean
            // something (see [_placeVertex]): close if it can, drop
            // the trace if it cannot. Until this, the first point drew
            // nothing at all and there was no way to tell whether it
            // had landed.
            closeTarget:
                _tapsVertices &&
                    (widget.selectionCommands?.hasOpenPolygon ?? false)
                ? widget.selectionCommands!.polygonPoints.first
                : null,
            closeTargetArmed:
                widget.selectionCommands?.canClosePolygon ?? false,
            // The rubber band: the segment the next tap would lay.
            // Fed by a notifier the painter reads, NOT by setState —
            // a rebuild per pointer move on this layer is the R4 #3
            // hazard (it re-records the whole canvas picture), and the
            // ants painter is already repainting for its dashes.
            cursor: _tapsVertices ? _cursor : null,
            transformChrome: chrome,
            // 🚨★★★**THE SAME VALUE THE CONFIRM BUTTON WEARS**, which is
            // the whole of H28 (「the box says the same thing the ants
            // say」). ↩️It read `_movePending && _sessionHasChanges` until
            // F-164, and that extra term was a PREMISE that stopped being
            // true: when H28 was written a box could not outlive its
            // float, so 「there is a float」 and 「this is a live session」
            // were one fact. 유저 확정 2026-09-17 split them — a frame walk
            // lets the float go and KEEPS the box and its numbers — and
            // from then on the term quietly turned a box that would still
            // change pixels green.
            //
            // 🗣️유저 2026-09-18 (F-164): 「변형중에 다른프레임가면 변형
            // 실루엣 초록색되고 … **변형중이면 빨간색 유지**여야하고」.
            sessionHasChanges: _sessionHasChanges,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Positioned _floatPreview(SelectionFloatPaint floatPaint, BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          key: const ValueKey<String>('transform-resample-preview'),
          painter: SelectionFloatPainter(
            float: floatPaint,
            viewport: widget.viewport,
            // The pan-phase snap's device grid — same source the
            // ink view behind this fallback reads.
            devicePixelRatio: EffectiveDevicePixelRatio.of(context),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  CanvasSelectionRegion? _displayShape(SelectionAffine? transform, CanvasSelectionRegion? region, List<CanvasPoint>? warpCorners) {
    var displayShape = transform != null && region != null
        ? region.mapped(transform.apply)
        : region;
    if (warpCorners != null && region != null) {
      final base = floatWarp.stampRectCorners();
      final h = base == null ? null : solveHomography(base, warpCorners);
      displayShape = h == null
          ? CanvasSelectionRegion.shape(CanvasSelectionShape(warpCorners))
          : region.mapped((point) => applyHomography(h, point));
    }
    final meshPoints = floatWarp.meshPoints;
    if (meshPoints != null) {
      // Mesh session: the ants trace the grid's warped boundary.
      displayShape = CanvasSelectionRegion.shape(
        CanvasSelectionShape(floatWarp.meshBoundary(meshPoints)),
      );
    }
    return displayShape;
  }

  Offset _mapCanvasToViewportOffset(CanvasPoint point) =>
      widget.viewport.canvasToViewportOffset(point);
}

// (The fallback float painter moved to selection_float_overlay.dart, beside
// the description it draws — one file owns "what is floating and how it is
// drawn", and the pixel tests can name it.)

// (The hold's clip used to be a `ClipPath` around the float's widget, in
// screen space. TS1 turned the float into a canvas-space description, so the
// clip travels inside it and the clipper class is gone.)

/// The canvas a view [size] big shows through [toCanvas], [padding] wider
/// every way.
///
/// All four corners are mapped, not two: the canvas turns and flips, and
/// the bounds of a turned view are the bounds of its mapped corners.
/// ↩️It asked whether a corner mapped to a finite point, and answered null
/// if not — a check nothing could reach: a [CanvasPoint] refuses any other
/// (since 06-21, before the check came in on 08-13).
@visibleForTesting
SelectionVisibleRect canvasShownPadded(
  Size size,
  CanvasPoint Function(ViewportPoint corner) toCanvas,
  double padding,
) {
  final corners = [
    for (final corner in <ViewportPoint>[
      ViewportPoint(x: 0, y: 0),
      ViewportPoint(x: size.width, y: 0),
      ViewportPoint(x: size.width, y: size.height),
      ViewportPoint(x: 0, y: size.height),
    ])
      toCanvas(corner),
  ];
  final bounds = pointsBounds([
    for (final point in corners) Offset(point.x, point.y),
  ]);
  return (
    left: bounds.left - padding,
    top: bounds.top - padding,
    right: bounds.right + padding,
    bottom: bounds.bottom + padding,
  );
}
