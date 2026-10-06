import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/bitmap_surface.dart';
import '../../native/qa_pen_ledger.dart';
import '../../services/input/pen_lean.dart';
import '../../services/input/pen_sidecars.dart';
import '../debug/input_inspector.dart';
import '../brush/brush_tool_state.dart' show CanvasTool;
import '../../models/app_input_settings.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/brush_dab.dart';
import '../../models/brush_input_source.dart';
import '../../models/canvas_point.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/canvas_viewport.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../services/brush_dab_interpolator.dart';
import '../../services/brush_ground_color_mixing.dart';
import '../../services/brush_ground_color_sampling.dart';
import '../../services/brush_fill_promotion.dart';
import '../../services/brush_live_stroke_rasterizer.dart';
import '../../services/brush_stroke_dynamics.dart';
import '../../services/brush_tip_stamp_cache.dart';
import '../../services/brush_pressure_dynamics.dart';
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
import 'canvas_press.dart';
import 'canvas_tool_holds.dart';
import 'canvas_touch_contacts.dart';
import 'shown_cels.dart';
import 'canvas_viewport_offset.dart';

part 'brush_edit/brush_edit_stroke.dart';
part 'brush_edit/brush_edit_opening.dart';
part 'brush_edit/brush_edit_fill.dart';
part 'brush_edit/brush_edit_pressure.dart';
part 'brush_edit/brush_edit_overlay.dart';
part 'brush_edit/brush_edit_hold.dart';
part 'brush_edit/brush_edit_cel_press.dart';
part 'brush_edit/brush_edit_press.dart';

/// Every dab a stroke on this canvas LAYS, in order, the moment it lays it —
/// null records nothing. A test sets a list here to ask WHEN a sample
/// reached the canvas, which the committed stroke cannot say (H43: a press
/// that waits for nothing must not be held, and a stroke that waited lands
/// the moment its last reading comes).
@visibleForTesting
List<BrushDab>? debugStrokeDabsLaid;

/// Lands the stroke the pen is in the middle of, if any, and answers
/// whether anything landed — [BrushEditPress.landActiveStroke] handed out
/// so a caller that is not a pointer event can perform the same landing.
///
/// ⚠️A FUNCTION rather than the press object: what leaves this view is the
/// one verb a save needs, not a handle onto its input state.
typedef StrokeLander = bool Function();

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
    required this.celNow,
    required this.layerId,
    required this.frameId,
    required this.inputSettings,
    required this.onSourceStrokeCommitted,
    this.showTransparentBackground = true,
    this.onActiveStrokeChanged,
    this.onStrokeLanderChanged,
    this.onTemporaryToolHold,
    this.onTemporaryToolRelease,
    this.toolHolds,
    this.fillDabAt,
    this.selectionRegion,
    this.overlayModel,
    this.paintsContent = true,
    this.editable = true,
    this.rowAcceptsStrokes = true,
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

  /// Whether the ROW the playhead stands on takes strokes — false on a
  /// property lane (`MainCanvasBrushHost.rowAcceptsStrokes`).
  ///
  /// 🗣️F-196 (유저 2026-09-27): 「fx행에 서있는데 그림이 그려지고 커밋시
  /// 사라짐. … 안그려져야 하는곳은 통일해서 선 안나오게」. H19 split this from
  /// [editable] one layer up, and this view only ever heard [editable] — so
  /// on a lane over a cel it began the stroke, drew the live line, and the
  /// commit was refused at pen-up.
  ///
  /// ★Two questions, two flags, as H19 has them: [editable] says whether
  /// there is a cel (what is PAINTED, and whether a press asks for one);
  /// this says whether a press may DRAW. ⛔Folding it into [editable] would
  /// stand the view down on a lane, and standing down paints nothing.
  final bool rowAcceptsStrokes;

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

  /// The cel's pixels AS THEY STAND — asked at the moment they are used,
  /// never kept from the last build.
  ///
  /// 🚨★★★F-233 (유저 2026-09-29: 「언두 빠르게하면서 다시 빠르게
  /// 스트로크하면서 하다보면 … 언두된 스트로크가 다시 1프레임 보였다가
  /// 사라지는상황」). An undo, a redo or a stroke just landed changes the cel
  /// inside its own event, and this view learns of it at the next build. It
  /// used to hold the cel as a SNAPSHOT of that build, so a pen that landed
  /// in between began its stroke on the cel the last frame showed: the
  /// undone stroke came back inside every tile the new one touched until
  /// the pen lifted, and a stroke just lifted vanished under the next. The
  /// commit and the undo already read the cel as it stands
  /// (`BrushFrameEditingCoordinator.currentSurfaceOf`); a host hands this
  /// view the same question, and there is no snapshot left to read.
  final BitmapSurface Function() celNow;
  final LayerId layerId;
  final FrameId frameId;

  /// The brush in hand, read AT THE MOMENT it is used — a stroke's first
  /// point snapshots it for the whole stroke, a fill and a pressure curve
  /// read it when they run.
  ///
  /// A getter and not a value (H40 ②, 2026-09-24): handed over as a value,
  /// every brush change — a preset pick, each frame of a settings slider
  /// drag, a colour notch — rebuilt this view and the whole panel around
  /// it, and relaid out the panel's shell, so the chrome over the canvas
  /// repainted for a number it does not show.
  final ValueGetter<BrushEditCanvasInputSettings> inputSettings;
  final ValueChanged<BrushStrokeCommitData> onSourceStrokeCommitted;
  final bool showTransparentBackground;
  final ValueChanged<bool>? onActiveStrokeChanged;

  /// Handed this view's [StrokeLander] while it is mounted, and null when
  /// it goes — the same publish-upward shape `onCoordinatorChanged` uses,
  /// on the same route as [onActiveStrokeChanged].
  ///
  /// 🚨★★★**A SAVE HAS TO BE ABLE TO LAND THE PEN.** Press Ctrl+S with the
  /// pen still down and the stroke reaches the cel AFTER the save took its
  /// snapshot, so the file the user just asked for does not have the line
  /// they were drawing when they asked (`BrushFrameStore.adoptSavedFile`
  /// keeps it dirty on purpose, so it is not lost — it is just not in
  /// THAT file). 유저 2026-09-10: 「그냥 스트로크 커밋시키고 저장로직
  /// 발동시키면 되는거아닌가?」
  ///
  /// ⛔The lander is the view's own [BrushEditPress.landActiveStroke] and
  /// nothing else — a save that ended the stroke its own way would be that
  /// four-step ordering written twice.
  final ValueChanged<StrokeLander?>? onStrokeLanderChanged;

  /// PEN-7a mapped-hold session: the pen's tail, or a button mapped to the
  /// eraser, switched the tool temporarily — the shell mirrors it on the
  /// tool notifier so the cursor/panels follow, and restores (or keeps) on
  /// release.
  ///
  /// ↩️A held PICK and the history verbs came through this view too
  /// (`onHoldPick` — 🪦`onAltPick` before I-15 — and `onInvokeAction`,
  /// PEN-11). They draw nothing, and the view hears a press only while a
  /// drawing tool is armed over a cel, so a button mapped to the eyedropper
  /// was dead under every other tool (F-299). The panel reads them now,
  /// where every press on the canvas passes.
  final void Function(CanvasTool tool)? onTemporaryToolHold;
  final void Function({required bool keep})? onTemporaryToolRelease;

  /// Who holds the tool besides the hand on the keys ([CanvasToolHolds]) —
  /// the panel's, so its reader of mapped buttons and this view's reading
  /// of the pen's tail each see the other. Null = this view keeps its own
  /// (a sheet's ink: no button holds a pick there).
  final CanvasToolHolds? toolHolds;

  /// FILL mode (R22-A): non-null while the fill tool is active — a
  /// primary tap builds the flood's stamp dab here and the view runs it
  /// as a stroke of one dab (`promoteFillDab`): the overlay shows the
  /// result tiles the very next frame and the commit lands them through
  /// [onSourceStrokeCommitted] with their pictures already made — no
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
  PenLean? _currentTilt;

  /// How fast the pen travelled into the latest sample, 0..1 against the
  /// user's reference speed. A pen that has just landed — and every stroke's
  /// first dab — rests at 0.0.
  double _currentSpeed = 0.0;

  // The held button (Round 6): a mapped button the eraser stands in for.
  late final _BrushEditHold _hold = _BrushEditHold(this);

  /// Placement dynamics (scatter/jitter/direction rotation) for the active
  /// stroke; created at pointer-down from the stroke's settings snapshot.
  BrushStrokeDynamics? _strokeDynamics;

  /// Per-stroke randomness for the dual-mask phase; each dab samples the
  /// dual texture at its own random offset (stored on the dab, so replay
  /// is deterministic). Rolled from the stroke's press ([_BrushEditStroke]).
  math.Random _dualPhaseRandom = math.Random();

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

  /// Live overlay state. Pointer moves blend new dabs into [_liveRasterizer]
  /// (the exact commit-rasterizer math) and picture the touched overlay
  /// tiles inside the same call; the model's notification repaints the
  /// canvas painter directly — no widget rebuild per move, and the pixels
  /// on screen are the pixels the commit will keep.
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

  @override
  void initState() {
    super.initState();
    CanvasTouchContacts.addMultiTouchListener(_press.handleSharedMultiTouch);
    widget.onStrokeLanderChanged?.call(_press.landActiveStroke);
  }

  @override
  void didUpdateWidget(covariant InteractiveBrushEditCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The view no longer REMOUNTS per cel (R13-2): the old frameId-keyed
    // remount tore down and re-inflated this whole subtree on every frame
    // flip, and that element + render-tree rebuild summed to a 40-80ms
    // UI-thread hitch — the constant flip lag. A cel identity change now
    // resets the per-stroke state in place; everything else (session
    // state, lineage) flows through the ordinary rebuild.
    if (oldWidget.layerId != widget.layerId ||
        oldWidget.frameId != widget.frameId) {
      _endStrokeAfterTheFrame();
      _overlay.resetOverlay();
      // clear() before dropping: the live tiles are native-backed (R21)
      // and return to the engine's free list through it.
      _liveRasterizer?.clear();
      _liveRasterizer = null;
    }
  }

  /// Ends a stroke in flight from OUTSIDE a pointer event — its cel changed
  /// under the pen, or the view is going — and says so after the frame.
  ///
  /// R13-4: this runs inside the build/update phase. The stroke-end
  /// callback reached ancestor setState (the panel's _strokeActive then;
  /// since 2026-09-26 the session's input flag, whose listeners still
  /// rebuild widgets) — firing it synchronously threw "setState during
  /// build" (the mid-stroke flip red screen). Reset silently, notify
  /// post-frame.
  ///
  /// 🚨F-232: the teardown reset silently and never said so, trusting the
  /// panel's own dispose to — but a view can go while its panel stays, and
  /// then the host kept 「the pen is down」 until some later stroke ended:
  /// every seek refused, and every undo whose edit lay on another frame
  /// walking nowhere.
  void _endStrokeAfterTheFrame() {
    final hadActiveStroke = _activeDrawingPointer != null;
    _stroke.clearStrokeInputState();
    if (hadActiveStroke) {
      final notify = widget.onActiveStrokeChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notify?.call(false);
      });
    }
  }

  @override
  void dispose() {
    // ⛔FIRST, and before anything this view owns is torn down: a lander
    // still published after that point would land a stroke into freed
    // rasterizer tiles. Nulling it is the only thing that says 「there is
    // no pen here any more」.
    widget.onStrokeLanderChanged?.call(null);
    // A view taken away mid-stroke still hears the rest of the gesture —
    // Flutter routes it along the path the press found — and must not land
    // it: what it would land on is torn down right here.
    _endStrokeAfterTheFrame();
    ShownCels.instance.hide(this);
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
    // The canvas says which cel it draws — only while it draws one; the
    // merged stack draws it otherwise, and says so itself.
    if (widget.paintsContent && widget.editable) {
      ShownCels.instance.show(this, (widget.layerId, widget.frameId));
    } else {
      ShownCels.instance.hide(this);
    }
    // ⚠️ONE TREE SHAPE, editable or not. It used to return a bare
    // `SizedBox.expand()` while standing down, and that is what made I-10's
    // second half impossible: a listener that appears only after the cel
    // exists cannot be in the hit path of the press that created it. The
    // listener is here either way now — TRANSLUCENT while standing down, so
    // what is under this view in the panel's Stack keeps receiving exactly
    // as it did when nothing was built at all.
    //
    // ⛔Still nothing PAINTED while standing down: the cel the playhead has
    // LEFT must not be drawn ([celNow] answers with it until the host
    // builds again), which is what the flag was written for.
    final canvasSize = widget.celNow().canvasSize;
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
                      surface: widget.celNow(),
                      viewport: widget.viewport,
                      showTransparentBackground:
                          widget.showTransparentBackground,
                      overlayModel: _overlay._overlayModel,
                      lineage: (widget.layerId, widget.frameId),
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

  /// What the stroke's contact has read so far, and what it holds until it
  /// has (H43).
  late final _BrushEditOpening _opening = _BrushEditOpening(this);

  /// Who holds the tool besides the hand on the keys — the host's when it
  /// handed one. [CanvasToolHolds.penTail] is this view's to write: whether
  /// the pen-tail mapping is engaged (the pen is turned tail-down). Not a
  /// button hold: it spans strokes until the pen is turned back over.
  late final CanvasToolHolds _ownToolHolds = CanvasToolHolds();
  CanvasToolHolds get _toolHolds => widget.toolHolds ?? _ownToolHolds;

  /// EVERY tool works anywhere on the pasteboard (Flash-style — the
  /// stage rectangle is a crop at composite time, not an input
  /// boundary): strokes, eyedropper picks and fill taps alike.
  bool _isInsidePasteboard(CanvasPoint localPosition) {
    final canvasSize = widget.celNow().canvasSize;
    return canvasSize.containsPasteboardPoint(
      x: localPosition.x,
      y: localPosition.y,
    );
  }

  CanvasPoint _canvasPositionFromLocal(Offset localPosition) =>
      widget.viewport.viewportOffsetToCanvas(localPosition);

  /// Builds a dab carrying the base tool size/opacity and the current input
  /// pressure. Pressure scaling is applied after interpolation (see
  /// [_pressure.withPressureDynamics]) so each inserted dab scales by its own
  /// interpolated pressure rather than the segment endpoint's.
  BrushDab _dabFromPosition(
    CanvasPoint localPosition, {
    required int sequence,
  }) {
    final settings = _activeStrokeInputSettings ?? widget.inputSettings();
    final dualMask = settings.dualMask;
    return BrushDab(
      center: localPosition,
      color: settings.color,
      size: settings.size,
      // F-12: a dab carries only its OWN variation (the pressure curve and
      // the jitter multiply this). The tool's opacity is the accumulated
      // stroke's ceiling and rides `BrushDabSequence.opacity` instead.
      // F-205 (유저 2026-09-28): the variation is a ceiling too — a dab
      // settles at its opacity where dabs pile up (`qa_dab_source_alpha`).
      // ↩️Per dab it multiplied like flow, and a light press piled up to the
      // full slider wherever the stroke crossed itself.
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
      dualCompositeMode: settings.dualCompositeMode,
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

  /// Rolled from the stroke's press, as [_dualPhaseRandom] is.
  math.Random _spacingRandom = math.Random();

  /// Creates or recycles the live stroke rasterizer for the current canvas.
  void _prepareLiveRasterizer() {
    final surface = widget.celNow();
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
        (_activeStrokeInputSettings ?? widget.inputSettings()).opacity;
  }

  /// A fill shown and not yet committed: its dab, the surface its result
  /// tiles were made against, and those tiles ([_BrushEditFill]). The
  /// post-frame commit lands them; a second tap while this is set is the
  /// busy case.
  ({BrushDab dab, BitmapSurface base, List<PromotedStrokeTile> tiles})?
  _pendingFill;

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
}
