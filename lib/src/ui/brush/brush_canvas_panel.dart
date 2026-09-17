import 'dart:async';
import 'dart:ui' as ui show Image;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';

import '../canvas/shown_cels.dart';
import '../debug/repaint_cause.dart';
import '../../services/command.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../../services/brush_stroke_commit_data.dart';
import '../../services/undo_surface_snapshot.dart';
import '../../models/layer_effect.dart';
import '../../models/bitmap_surface.dart';
import '../../models/cut_piece.dart' show CutPiece;
import '../../models/brush_dab.dart';
import '../../models/brush_frame_key.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_paint_clip.dart';
import '../../services/canvas_selection_region.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/canvas_size.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/drawing_guide.dart';
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
import '../canvas/canvas_touch_contacts.dart' show CanvasTouchContacts;
import 'promoted_touch_aim_policy.dart' show aimIsPromotedTouch;
import '../canvas/canvas_zoom_scale.dart';
import '../canvas/selection_ants_painter.dart';
import '../canvas/selection_float_overlay.dart';
import '../canvas/canvas_pan_hold.dart';
import '../canvas/canvas_viewport_gesture_layer.dart';
import '../canvas/flip_hud_controller.dart';
import '../canvas/flip_hud_overlay.dart';
import 'canvas_floor_insets.dart';
import '../../models/app_input_settings.dart';
import '../debug/input_inspector.dart' show InputInspector;
import '../../models/brush_blend_mode.dart';
import '../../services/cut_piece_lift.dart';
import '../../services/cut_piece_slot.dart';
import '../../services/cut_piece_stamp.dart';
import 'cut_piece_preview.dart';
import '../../models/project.dart' show defaultProjectBackdropArgb;
import '../../models/project_background.dart';
import '../canvas/paper_background.dart'
    show AlphaCheckerboardPainter, alphaPreviewEnabled, paintAlphaCheckerboard;
import '../sliced_value_listenable_builder.dart';
import '../theme/app_theme.dart';
import '../../models/app_workspace_colors.dart';
import '../widgets/color_swatch_button.dart';
import 'brush_cursor_geometry.dart' show brushCursorShape;
import 'brush_cursor_painter.dart' show brushCursorLook;
import 'eyedropper_swatch_painter.dart' show eyedropperSwatchLook;
import 'tool_cursor_look.dart';
import 'tool_cursor_sprite.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart';
import '../../services/layer_pose_paint.dart';
import 'brush_canvas_defaults.dart';
import 'brush_tool_state.dart';
import '../../core/dev_profile.dart';
import 'canvas_selection_commands.dart';
import 'transform_tool_options.dart';
import 'selection_shape_history_command.dart';
import 'canvas_view_commands.dart';
import 'canvas_viewport_pan_metrics.dart';
import 'canvas_visible_rect.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/superellipse_clip.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/panel_flyout.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../text/app_strings.dart';
import '../listenable_rebind.dart';
import '../repaint_props.dart';

part 'canvas_panel/canvas_panel_shell_bars.dart';
part 'canvas_panel/canvas_panel_selection.dart';
part 'canvas_panel/canvas_panel_tool_cursor.dart';
part 'canvas_panel/canvas_panel_tap.dart';
part 'canvas_panel/canvas_panel_lift.dart';
part 'canvas_panel/canvas_panel_viewport.dart';
part 'canvas_panel/viewport_bottom_bar_build.dart';
part 'canvas_panel/canvas_panel_build.dart';

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
/// TS1: the FLOAT rides along beside the active layer's painter, because it
/// belongs in the same slot of the same picture — the composite is the only
/// thing that can draw it with the layers above it on top.
typedef CanvasUnderlayBuilder =
    Widget Function(
      BuildContext context,
      CanvasViewport viewport,
      BitmapSurfacePainter? activeSurfacePainter,
      SelectionFloatOverlay floatOverlay,
    );

class BrushCanvasPanel extends StatefulWidget {
  const BrushCanvasPanel({
    super.key,
    required this.coordinator,
    this.celEditable = true,
    this.rowAcceptsStrokes = true,
    required this.availableFrameKeys,
    required this.cacheInvalidationSink,
    this.canvasSize = BrushCanvasDefaults.canvasSize,
    this.guides,
    this.brushToolState = BrushToolState.defaults,
    this.historyManager,
    this.takeStrokePrefixCommand,
    this.onPressNeedsCel,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.viewportOverlayBuilder,
    this.viewportUnderlayBuilder,
    this.activeStrokeOverlayModel,
    this.interactiveContentOpacity = 1.0,
    this.interactiveContentPose,
    this.activeSourceEffects = const <ResolvedLayerEffect>[],
    this.contentOverride,
    this.fitFocusRect,
    this.floorCover = EdgeInsets.zero,
    this.floorRailBand,
    this.floorBottomOverlaySpan = 0,
    this.autoFrame,
    this.unframedFit,
    this.contentStrokeActive,
    this.sampleColorAt,
    this.paperColor = ProjectBackground.defaultPaperArgb,
    this.paperNone = false,
    this.onPaperColorChanged,
    this.onPaperNone,
    this.pasteboardColor,
    this.pasteboardNone,
    this.onPasteboardColorChanged,
    this.onPasteboardNone,
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
    this.onEyedropperPick,
    this.fillDabAt,
    this.shapeFillDabFor,
    this.selectionMaskOptions,
    this.transformOptions,
    this.viewCommands,
    this.selectionCommands,
    this.cutPieceSlot,
    this.onCutContent,
    this.oneFingerAction,
    this.runsTheSelectedTool = true,
    this.onStrokeInputActiveChanged,
    this.onStrokeLanderChanged,
    this.onSelectionInteractionChanged,
    this.allowViewRotation = true,
    this.toolCursorsEnabled = true,
    this.toolInputEnabled = true,
    this.hasContentToView = true,
    this.bottomBarLeading = const <Widget>[],
    this.bottomBarSettings = const <PanelFlyoutEntry>[],
    this.pageStrip = const <Widget>[],
    this.bottomBarHostToken,
  }) : assert(
         coordinator != null || contentOverride != null,
         'Without a coordinator the panel needs a content override.',
       );

  /// Null only when [contentOverride] supplies the viewport content — the
  /// project has no editing coordinator AT ALL yet (nothing has ever been
  /// drawn). Standing on an empty FRAME is a different fact: see
  /// [celEditable].
  final BrushFrameEditingCoordinator? coordinator;

  /// Whether there IS a cel under the playhead — the frame this panel would
  /// paint and could be drawn on.
  ///
  /// Split from [coordinator] deliberately. The two used to be one — the
  /// host handed over a null coordinator on an empty frame — which meant
  /// the interactive canvas was BUILT AND DESTROYED every time a flip
  /// crossed "no cel ↔ cel". Every pixel verb still refuses on an empty
  /// frame; it asks [_editableCoordinator] instead of this field, so the
  /// guards read exactly as they did.
  ///
  /// ⛔This one, and ONLY this one, stands the interactive view down — a
  /// blank canvas is the honest answer to "there is nothing here", and a
  /// wrong answer to anything else. See [rowAcceptsStrokes].
  final bool celEditable;

  /// Whether the ROW the frame-axis verbs stand on takes strokes at all;
  /// false on a property lane (`MainCanvasBrushHost.rowAcceptsStrokes`).
  ///
  /// 🚨H19 (유저 2026-08-23): 「**서있는 곳이 fx행이면 현재 있는 레이어의
  /// 그림이 사라짐.** 대체 이딴규칙 누가만드는거지?」 — this used to arrive
  /// folded into [celEditable], which is the flag that blanks the view, so
  /// standing on an fx row painted an empty canvas over a cel that exists.
  ///
  /// ★"Is there a cel" decides what is PAINTED. "Does this row take strokes"
  /// decides what a press may DO. Only the second belongs on the verbs.
  final bool rowAcceptsStrokes;

  /// The coordinator for the verbs that EDIT PIXELS — null whenever this
  /// frame cannot be drawn on, which is the condition every one of those
  /// verbs was already written against.
  ///
  /// ⛔THE VERBS, AND NOTHING THAT PAINTS. Everything that DRAWS reads
  /// [celEditable] and [coordinator] directly — the interactive view, which
  /// stays mounted either way, and the surface painter that fills it. This
  /// getter folds in the ROW question, and painting is not a verb.
  /// 🗣️유저 2026-09-12: 「레이어에 서있을땐 그림 제대로 보이는데 트랜스폼에
  /// 서면 그림이 사라져」 — the painter read this, so standing on a property
  /// lane left the live row in the composite tree with nobody to paint it.
  /// H19 split the two questions; this keeps them split one layer down.
  BrushFrameEditingCoordinator? get _editableCoordinator =>
      celEditable && rowAcceptsStrokes ? coordinator : null;

  final List<BrushFrameKey> availableFrameKeys;
  final CacheInvalidationSink cacheInvalidationSink;
  final CanvasSize canvasSize;

  /// The active cut's drawing guides, in CANVAS space. Null (the default)
  /// draws with none — the hosts that embed this panel without a cut behind
  /// it pass nothing.
  final CutGuides? guides;

  final BrushToolState brushToolState;
  final HistoryManager? historyManager;

  /// A command this stroke must be UNDONE WITH — the block an I-10
  /// pen-down made on an empty cell.
  ///
  /// 유저 2026-08-30 chose **merged**: one stroke on an empty cell is
  /// ONE undo, block and ink together. The two halves are made at
  /// different moments (the block at pen-down, so the ink has
  /// somewhere to go; the stroke at pen-up), so they are composed
  /// here rather than grouped — `runAsOneStep` only spans one
  /// synchronous body.
  ///
  /// ⚠️TAKE, not read: it must be consumed exactly once. Null
  /// everywhere but the main canvas; the timesheet and conte hosts
  /// have no empty-cell press to make a block for.
  final Command? Function()? takeStrokePrefixCommand;

  /// I-10: what a press does when there is no cel under it — see
  /// [InteractiveBrushEditCanvasView.onPressNeedsCel], which is where it
  /// goes. The shell answers 「make one, or say why not」.
  final bool Function()? onPressNeedsCel;

  /// The view PUSHED by a caller that keeps it in its own `setState` — an
  /// input, re-applied whenever the caller changes it.
  ///
  /// ⚠️"Whenever the CALLER changed it", not "whenever it differs": the
  /// panel tracks the last value it was HANDED, so its own panning never
  /// compares as a caller edit and never gets reverted. Passing this a
  /// constant is therefore harmless — see the marker in [build].
  ///
  /// ⛔Prefer [viewportController] for new callers: this channel costs the
  /// caller a rebuild per pan frame.
  final CanvasViewport? viewport;

  /// The view, OWNED by the caller — the single copy, not a value to echo.
  ///
  /// ⛔A caller that passes this must not also pass [viewport]; the seed
  /// would be ignored, which is worse than an error.
  final ValueNotifier<CanvasViewport?>? viewportController;

  /// The view as the CALLER holds it, in DEVICE pixels.
  ///
  /// 🎯**Everything outside this panel speaks device units** — both
  /// channels above, this getter, and [onViewportChanged]. The panel
  /// projects into logical units for its painters and nowhere else, which
  /// is what lets a view sit in a closed tab, or a notifier nobody is
  /// listening to, and stay correct across a UI-scale change.
  ///
  /// ⚠️Non-null by construction: `null` means "nobody has framed this yet",
  /// and in device units that IS `CanvasViewport()` — one artwork pixel per
  /// device pixel. Callers get an answer instead of a null to resolve with
  /// a ratio they would have to go find.
  ///
  /// 🚨One place resolves the two channels, so nothing outside has to know
  /// which one a given host wired. It used to be open-coded as
  /// `panel.viewport!` in pins, and every one of them read a null the day
  /// its host moved to a controller — a stale oracle asserts about a
  /// default and passes while the real view sits somewhere else.
  CanvasViewport get publishedViewport =>
      (viewportController != null ? viewportController!.value : viewport) ??
      CanvasViewport();

  /// Fired when the panel moves the view, in DEVICE pixels — a side channel for owners that
  /// react (persisting elsewhere, re-framing a sibling), never the storage.
  final ValueChanged<CanvasViewport>? onViewportChanged;

  /// The host's OWN controls, at the head of the pill: the timesheet's
  /// sheet-mode toggles and page navigation, the conte's, the envelope's.
  ///
  /// They used to be split between two places — a status strip across the
  /// top for the toggles and the bottom bar for the page cluster. Both
  /// places are gone (R2 #13); a panel has one pill and everything it
  /// offers is in it.
  final List<Widget> bottomBarLeading;

  /// What this host adds to the pill's SETTINGS list — the verbs it owns
  /// that a hand does not reach for constantly (유저 확정 2026-08-13: the
  /// viewer's "register in the media pool" and "swap the two viewers").
  ///
  /// ★It is the same list the pill fills with 1:1, rotate/flip and the
  /// surface colours, and deliberately so: a panel that grew a settings
  /// surface of its own would undo the round that pulled every popup into
  /// one shell ([[ui-round-r6]]). The host's entries come FIRST — they are
  /// about the document, and the pill's are about looking at it.
  ///
  /// ⚠️A list is built once when it OPENS. An entry whose appearance can
  /// change while it is open has to be a [PanelFlyoutRow] carrying its own
  /// listenable; a plain [PanelFlyoutItem] is a snapshot, which is right
  /// for a command and wrong for a knob.
  final List<PanelFlyoutEntry> bottomBarSettings;

  /// Turning the pages of whatever this panel is showing, stacked in a
  /// capsule on the LEFT edge (유저 확정 2026-08-13 ⑥: 페이지 넘기기는 왼쪽
  /// 세로, 그리고 필요한 파일에서만).
  ///
  /// ★It is not in the pill because it was the pill's largest tenant —
  /// three controls, 132px of the shedding budget — so a rail-width panel
  /// was made to choose between turning pages and looking at the page. On
  /// an edge of its own it competes with nothing.
  ///
  /// Empty means no strip at all: a still image has no pages to turn, and
  /// a disabled cluster on a permanent capsule is a promise the panel
  /// cannot keep.
  final List<Widget> pageStrip;

  /// Equality token for [bottomBarLeading] AND [bottomBarSettings] — the
  /// bottom bar is memoized by its inputs (R13-3) and widget instances are
  /// rebuilt per host build, so the host names what its own controls
  /// actually DEPEND on. Null with a non-empty contribution means "rebuild
  /// the bar every time".
  ///
  /// ⚠️This covers the settings entries too, and it has to: those entries
  /// are CAPTURED in the trigger's closure, so a bar the memo served stale
  /// opens a list showing stale state (a register command still enabled
  /// for a file that has since joined the pool).
  final Object? bottomBarHostToken;

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
  /// What the MERGED-mode stack painter draws the active layer with.
  ///
  /// ⛔Built by the STATE, not here, and memoized — see
  /// `_BrushCanvasPanelState._activeSurfacePainter`. This used to mint a
  /// fresh instance per call and `CanvasLayerStackView.shouldRepaint`
  /// compares the field with `!identical(...)`, so the comparison could
  /// never answer false and every rebuild of this panel re-composited the
  /// whole stack.
  ({BitmapSurface surface, BrushFrameKey key, String fx})?
  _activeSurfaceIdentityFor(BrushFrameEditingCoordinator coordinator) {
    if (activeStrokeOverlayModel == null) {
      return null;
    }
    return (
      surface: coordinator.activeSessionState.canvasState.currentSurface,
      key: coordinator.activeFrameKey,
      // The colour keys' VALUES join the token: they change no surface and
      // no cel, so without them dragging Tolerance would keep serving the
      // painter built at the old value.
      fx: celSourceEffectSignature(activeSourceEffects).join(','),
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

  /// ⑩: what floats over the floor's BOTTOM edge without framing the
  /// artwork — the collapsed row. The horizontal panbar steps up by it, and
  /// nothing else does, because nothing else was being buried.
  final double floorBottomOverlaySpan;

  /// Playback-follow reframing: when the request's token changes between
  /// updates the panel reframes onto its rect (see
  /// [CanvasAutoFrameRequest]). Null never reframes — the user owns the
  /// viewport.
  final CanvasAutoFrameRequest? autoFrame;

  /// The framing to resolve an UNFRAMED view to (canvas space), instead of
  /// the 1:1 identity — playback's camera fit is the one that uses it.
  ///
  /// 🎯**A standing-in-front-of, not a reframe.** [autoFrame] is an EVENT:
  /// it fires, the panel writes the viewport, and an owner that wants the
  /// user's framing back afterwards has to have saved a copy and write it
  /// back. This is a STATE — while it is non-null the panel simply resolves
  /// `null` (see the `_viewport` getter) to a fit of this rect. The stored
  /// framing is never touched, so:
  ///
  ///  * the first frame that sees it is already fitted — there is no
  ///    post-frame write and so no frame of lag, and 유저 asked for exactly
  ///    that (「한프레임 늦추면 뭔가 시간적인 느낌이 이상해지지않을까」);
  ///  * ending it is dropping it, with no restore to run and no condition
  ///    that can make the restore not run;
  ///  * a save taken mid-playback persists the USER's framing, because the
  ///    fit was never in the object that gets saved.
  ///
  /// ⚠️It pairs with an owner handing over a DIFFERENT [viewportController]
  /// for the duration — the fit resolves only while the notifier in force
  /// reads null, so a pan during playback (D13 keeps pan/zoom live) writes
  /// that notifier and takes over from the fit exactly as it would from the
  /// identity. Re-arming the fit is `notifier.value = null`.
  final Rect? unframedFit;

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

  /// Whether the paper is ABSENT (F-114) — [paperColor] stays the kept
  /// colour for the next pick — and what 「없음」 does in its window. A null
  /// handler leaves the window's none button dead for the paper.
  final bool paperNone;
  final VoidCallback? onPaperNone;

  /// null = take it from [CanvasStageColors], which is what every panel
  /// inside the workspace does (유저, R4 #2). Pass a value only to mount
  /// this panel outside the shell — the dev fixtures and most tests.
  ///
  /// ⚠️It used to be a non-null parameter with a constant default, and the
  /// default is exactly what four of the five hosts silently got.
  final int? pasteboardColor;
  final ValueChanged<int>? onPasteboardColorChanged;

  /// The pasteboard's absence (F-114) and its 「없음」. null = from the
  /// scope, like [pasteboardColor].
  final bool? pasteboardNone;
  final VoidCallback? onPasteboardNone;

  /// The BACKDROP behind the pasteboard (R3b): the stage's floor — thinnable
  /// since F-114 — or the alpha checkerboard while the preview toggle is on.
  /// It is what lies BEYOND the pasteboard now, not merely under it. null =
  /// from the scope.
  final int? backdropArgb;

  /// 캔버스 색 바꾸는곳 제일오른쪽에 배경색 바꾸는 버튼도 (유저, R3 #4). The
  /// pill carried the paper and the pasteboard and stopped there, which
  /// left the third plane of the same stage reachable only from a dialog.
  /// Null hides the swatch, like the other two.
  final ValueChanged<int>? onBackdropColorChanged;

  /// The backdrop's absence (F-114) and its 「없음」. null = from the scope.
  final bool? backdropNone;
  final VoidCallback? onBackdropNone;

  /// An eyedropper pick — the tool's tap and drag, and a held mapped
  /// button's live pick alike. ONE pick (I-15): the Alt-only pick that stood
  /// beside it is gone, because Alt switches to the eyedropper tool now.
  final ValueChanged<int>? onEyedropperPick;

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
  final BrushDab? Function(
    CanvasPoint point,
    int color,
    SymmetryShape? symmetry,
  )?
  fillDabAt;

  /// Builds the dab for a finished SHAPE FILL outline. Supplied by the
  /// host for the same reason [fillDabAt] is — the fill's knobs live up
  /// there, and the panel commits whatever comes back. Null disables the
  /// shape fill.
  final BrushDab? Function(CanvasSelectionShape shape, int color)?
  shapeFillDabFor;

  /// R26 (C2): the Select tool's lift-time mask knobs — read at lift.
  /// Null/absent keeps the classic byte-preserving hard mask.
  final ValueListenable<SelectionMaskOptions>? selectionMaskOptions;

  /// The transform tool's settings — mode, scale anchor, resampler, mesh
  /// grid. Null keeps the defaults, which is what focused tests want.
  final ValueListenable<TransformToolOptions>? transformOptions;

  /// The app-level rotate/flip shortcut channel (P8); the panel binds its
  /// viewport-center handlers while mounted.
  final CanvasViewCommands? viewCommands;

  /// The app-level selection channel (P9: Ctrl+D, arrow nudges), bound by
  /// the selection layer while a selection tool is active.
  final CanvasSelectionCommands? selectionCommands;

  /// Where a finished cut lands. Null in hosts that do not offer the tool
  /// (the cut variants are then inert rather than crashing).
  final CutPieceSlot? cutPieceSlot;

  /// A finished cut outline, for a host whose content is not a cel
  /// ([contentOverride]): the host lifts the piece from what it SHOWS. Null
  /// = the cut reads the active cel into [cutPieceSlot].
  ///
  /// 🗣️I-14 (유저 2026-09-11): 「뷰어패널의 잘라내기툴 사용 가능하도록」 —
  /// the media viewer answers it, at the page's own size.
  final ValueChanged<CanvasSelectionShape>? onCutContent;

  /// What one finger does in THIS panel when the host answers the slot
  /// itself ([CanvasViewportGestureLayer.oneFingerAction]) — and the
  /// selection layer asks the tool door with the same answer
  /// ([AppInput.toolAcceptsPointer]), so a finger that pans here cannot also
  /// drag a cut. Null = the user's slot.
  ///
  /// ⚠️Those two read it and nothing else: the selection layer is the one
  /// tool layer a content host runs (the viewer lets the CUT through and no
  /// other tool). A host that lets another tool through asks that tool's
  /// layer the same way.
  final CanvasTouchDragAction? oneFingerAction;

  /// Whether this surface can run the SELECTED tool right now.
  ///
  /// 🗣️유저 2026-09-16 (F-80): 「작동 가능한 거면 해당 도구 작동시키고,
  /// 불가능하면 팬」 · 「법 통일할수있을거같은데」. It is ONE question, asked
  /// here, and every host answers it from what it already knows: the main
  /// canvas always runs the tool, a sheet runs it while its drawing is ON,
  /// and the viewer runs the CUT and nothing else (I-14 — it has nothing to
  /// draw on). False makes a plain primary press pan
  /// ([CanvasViewportGestureLayer.primaryPressPans]): a press no tool here
  /// can act on is a press asking to move the page.
  ///
  /// ⛔NOT [celEditable], NOT [rowAcceptsStrokes], and NOT 「there is no cel
  /// under the playhead」. Those say what is PAINTED and what a press may do
  /// to a ROW (H19 split them), and a press with no cel under it MAKES one
  /// ([onPressNeedsCel], I-10) — folding any of them in here would turn
  /// drawing on an empty frame into panning.
  ///
  /// ⚠️It does not decide what a FINGER does. That is [oneFingerAction],
  /// which the tool door reads as well, and the viewer pans on one finger
  /// even while the cut IS armed (I-14) — two questions, two answers.
  final bool runsTheSelectedTool;

  /// Stroke lifecycle for the host (R13-3): true at pen-down, false at
  /// stroke end/cancel — the session holds prerender warming while a
  /// stroke is live.
  final ValueChanged<bool>? onStrokeInputActiveChanged;

  /// This canvas view's stroke lander, published upward while it is
  /// mounted — see [InteractiveBrushEditCanvasView.onStrokeLanderChanged].
  final ValueChanged<StrokeLander?>? onStrokeLanderChanged;

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

  /// False stands down the layers a tool takes the pointer through — the tap
  /// layer (the eyedropper's pick, the stamp) and the selection layer
  /// (select, move, cut, shape fill) — so a press reaches the content. For
  /// content a press only STOPS: playback.
  ///
  /// 🚨T28-c (유저): 「뭘 누르든 입력이 존재하면 정지 … 입력 일 안함」. Playback
  /// swapped the content and left these layers to the tool alone, so over
  /// the playing picture the eyedropper picked a colour and the selection
  /// tools took the press, and nothing stopped (board
  /// `playback-tap-taken-by-tool-layer`).
  ///
  /// ⛔Not the media viewer's way of running no tool, handing the panel an
  /// inert [brushToolState]: to the panel that is a tool SWITCH (it abandons
  /// a polygon being traced) and the shell bars read the brush colour off
  /// it, while playing and stopping change no tool. Nor [toolCursorsEnabled]:
  /// the viewer shows no cursor and still runs the cut, and a cursor takes
  /// no press.
  final bool toolInputEnabled;

  /// False when the host has nothing on its stage yet — the media viewer
  /// with no file open (유저 F-77: 「뷰어패널 열린거 없으면 확대나 스크롤바같은
  /// 조작 버튼 비활성화」). Every view control keeps its place and goes
  /// disabled: fit, 1:1, the zoom steps, the zoom readout and both panbars.
  ///
  /// ⚠️Its own question. [allowViewRotation] answers "does this host have
  /// the control at all" (false HIDES it); this answers "is there a view to
  /// operate right now" (false DISABLES it in place).
  final bool hasContentToView;

  @override
  State<BrushCanvasPanel> createState() => _BrushCanvasPanelState();
}

/// The stand-in when no host owns the transform settings (focused tests).
/// Const in spirit — nothing ever writes it, so one instance for the
/// process is correct and it is never disposed.
final ValueNotifier<TransformToolOptions> _defaultTransformOptions =
    ValueNotifier(TransformToolOptions.defaults);

class _BrushCanvasPanelState extends State<BrushCanvasPanel>
    with SingleTickerProviderStateMixin {
  // The viewport (Round 6): own, owner's, published, and the editor size.
  late final _CanvasPanelViewport _viewportState = _CanvasPanelViewport(this);

  /// True while a brush stroke is in progress; the viewport gesture layer
  /// ignores wheel zooms and new pans so they cannot disturb the stroke.
  bool _strokeActive = false;

  /// True while a selection marquee/move drag is in progress (P9) — holds
  /// viewport gestures exactly like a stroke.
  bool _selectionDragActive = false;

  /// True while a transform HANDLE is being dragged. Narrower than
  /// [_selectionDragActive] on purpose: it is the only state in which
  /// touch is locked out of the viewport as well.
  bool _transformDragActive = false;

  CanvasAutoFrameRequest? _pendingAutoFrame;


  /// The AIM: the pointer's panel-local position, for every tool cursor —
  /// the brush ring, the bucket, the dropper and its swatch, the stamp's
  /// ghost. One writer (the census), every cursor a reader.
  ///
  /// The eyedropper used to have a second notifier beside this one, holding
  /// the position AND the colour sampled under it on every pointer event.
  /// F-130 retired it: the swatch reads this aim and samples in its own
  /// `paint`, once per frame (`eyedropper_swatch_painter.dart`).
  final ValueNotifier<Offset?> _toolCursorHover = ValueNotifier<Offset?>(null);

  /// 🚨★★★F-33: what the surface painter draws as the stamp's ghost.
  ///
  /// A notifier rather than a build-time value so a hover REPAINTS the
  /// painter without rebuilding it — a fresh painter per pointer position
  /// would break the memo that keeps the whole stack from recompositing
  /// ([_activeSurfacePainter]'s token).
  ///
  /// ⛔Holds a BORROWED image: [CutStampPreviewPublisher] clears this in
  /// the same dispose that frees it.
  final ValueNotifier<CutStampPreview?> _stampPreview =
      ValueNotifier<CutStampPreview?>(null);

  /// TS1: the channel the selection layer publishes its FLOAT on, and the
  /// composite underlay reads. Owned here because it outlives both — the
  /// selection layer is mounted and unmounted by tool changes, and the
  /// underlay is rebuilt by the host.
  final SelectionFloatOverlay _selectionFloat = SelectionFloatOverlay(null);

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
  late bool _stageBackdropNone;
  late bool _stagePasteboardNone;

  /// Whether this panel is the one LYING ON THE FLOOR — which decides
  /// whether its pill lays its whole vocabulary out or keeps it folded
  /// behind the gear (유저 확정 2026-08-13: 「바닥 둘만」).
  ///
  /// Read from the tree rather than taken as a parameter, for the reason
  /// [CanvasFloorInsets] was built on: five hosts mount this panel and the
  /// question is about WHERE, not about who mounted it.
  late bool _onFloor;

  /// The MERGED-mode surface painter, kept ALIVE across rebuilds.
  ///
  /// 🐛It was rebuilt on every call, and `CanvasLayerStackView` gates the
  /// entire stack composite on `!identical(oldDelegate.activeSurfacePainter,
  /// activeSurfacePainter)`. A fresh instance every build makes that test
  /// unconditionally true, so ANY rebuild of this panel — a pan frame, a
  /// tool switch, an unrelated notify — redrew the paper, every layer, the
  /// onion ghosts and a `saveLayer` per group buffer. Measured: ten
  /// rebuilds, ten distinct painters.
  ///
  /// ⚠️Reuse is not merely cheaper, it is more correct: the painter passes
  /// `repaint: Listenable.merge([...])` to `CustomPainter`, so a new one per
  /// frame also churned a subscription per frame.
  ///
  /// The token is what the painter DRAWS — the surface it reads and the cel
  /// it is scoped to. A commit swaps the surface and the memo falls.
  BitmapSurfacePainter? _memoActiveSurfacePainter;
  ({BitmapSurface surface, BrushFrameKey key, String fx})?
  _activeSurfacePainterToken;

  // ── the tool cursor: its own object, in its own file ────────────────
  //
  // A collaborator (brush/canvas_panel/canvas_panel_tool_cursor.dart, a part of this library).
  // The State keeps the entry points its build tree calls.
  late final _CanvasPanelToolCursor _toolCursor = _CanvasPanelToolCursor(this);

  BitmapSurfacePainter? _activeSurfacePainter() {
    // ★THE CEL QUESTION, NOT THE ROW'S (H19): a lane refuses the STROKE,
    // it does not empty the canvas.
    final coordinator = widget.celEditable ? widget.coordinator : null;
    final overlay = widget.activeStrokeOverlayModel;
    if (coordinator == null || overlay == null) {
      _memoActiveSurfacePainter = null;
      _activeSurfacePainterToken = null;
      ShownCels.instance.hide(this);
      return null;
    }
    final token = widget._activeSurfaceIdentityFor(coordinator);
    if (token == null) {
      _memoActiveSurfacePainter = null;
      _activeSurfacePainterToken = null;
      ShownCels.instance.hide(this);
      return null;
    }
    if (_memoActiveSurfacePainter != null &&
        token == _activeSurfacePainterToken) {
      return _memoActiveSurfacePainter;
    }
    _activeSurfacePainterToken = token;
    // The canvas says which cel it is drawing, and THROUGH what: the
    // colour keys make the tiles it paints other objects than the cel's
    // own, so a picture made ahead for the cel's own would go unused.
    ShownCels.instance.show(
      this,
      (token.key.layerId, token.key.frameId),
      painted: (surface) =>
          celSurfaceWithSourceEffects(surface, widget.activeSourceEffects),
    );
    return _memoActiveSurfacePainter = BitmapSurfacePainter(
      // ★DRAWN THROUGH THE KEYS. Cached per TILE, so a dab re-keys the one
      // tile it changed and the rest of the cel answers from memory.
      surface: celSurfaceWithSourceEffects(
        token.surface,
        widget.activeSourceEffects,
      ),
      overlayModel: overlay,
      // The stack painter applies the viewport itself, so the surface
      // painter draws in canvas space.
      showTransparentBackground: false,
      lineage: (token.key.layerId, token.key.frameId),
      stampPreview: _stampPreview,
    );
  }

  // ── the shell bars: their own object, in their own file ─────────────
  //
  // A collaborator (brush/canvas_panel/canvas_panel_shell_bars.dart, a part of this library).
  // The State keeps the entry points its build tree calls.
  late final _CanvasPanelShellBars _shellBars = _CanvasPanelShellBars(this);

  /// The door a collaborator rebuilds through - setState is protected,
  /// and a collaborator is not a subclass.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _viewportState.bindViewCommands();
    // 🚨D34 최종: a finger ANYWHERE drops the tool aim — see
    // [CanvasTouchContacts.addAppWideTouchListener] and [_handleAppWideTouch].
    CanvasTouchContacts.addAppWideTouchListener(_handleAppWideTouch);
    CanvasPanHold.held.addListener(_onPanHoldChanged);
    _viewportState._listenedViewport = _viewportState.viewportNotifier
      ..addListener(_viewportState.handleViewportMovedByOwner);
    widget.selectionCommands?.addListener(_selectionSeat.handleSelectionChannelChanged);
    _selectionSeat.bindSelectionHistoryRecorder();
    _bindCutPasteHandler();
    _bindCelPixelRevision();
    _syncIdleAnts();
  }

  /// The cel-edit signal this panel listens on, remembered so it can be
  /// released from the object it was taken on.
  ValueListenable<int>? _listenedCelPixels;

  /// 🚨★★★A CEL EDIT HAS TO REACH THE CANVAS THE SAME WAY WHOEVER MADE IT.
  ///
  /// A stroke commit worked because THIS panel makes it: `_commitSourceStroke`
  /// ends in `setState`, the build re-evaluates
  /// [_activeSurfacePainter], its token no longer matches the surface the
  /// store now holds, and the memo falls. Nothing about that is the stroke's
  /// — it is just that the initiator happened to be the widget that draws.
  ///
  /// 색 변환 and 픽셀 비우기 are pressed on the TIMELINE. They write the same
  /// surfaces through the same coordinator and fire the same invalidation,
  /// and every cache downstream honoured it — but no rebuild ever reached
  /// here, so the memo kept a painter bound to the PRE-EDIT surface and the
  /// canvas went on drawing pixels the store had already replaced.
  ///
  /// 유저 2026-08-27: 「여전히 해당 프레임에서 픽셀삭제누르면 반영안됨. 캔버스
  /// 여전히 그림 남아있음. **다만 타임라인 재 굽기 들어가는거보면 역시
  /// 데이터적으로는 삭제 잘 한거 맞음**」 — the data was right and only this
  /// widget had not been told. And 「인덱스 이동하거나 액티브레이어 바꾸거나
  /// 툴 바꾸거나」 cleared it because all three rebuild this panel, which is
  /// the same repair by accident.
  ///
  /// [BrushFrameStore.celPixelRevision] is the ONE thing every surface write
  /// bumps, `markCelEdited` being the only mutation signal there is. So the
  /// panel follows the fact rather than the caller.
  void _bindCelPixelRevision() {
    final next = widget.coordinator?.frameStore.celPixelRevision;
    if (identical(next, _listenedCelPixels)) {
      return;
    }
    _listenedCelPixels?.removeListener(_handleCelPixelsChanged);
    _listenedCelPixels = next?..addListener(_handleCelPixelsChanged);
  }

  void _handleCelPixelsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// The tool settings panel lives in another subtree, so the slot carries
  /// the verb and this panel — the only thing here that can reach a cel —
  /// fills it in while it is mounted.
  void _bindCutPasteHandler() {
    // Held in a field rather than compared as a tear-off: two tear-offs of
    // the same method are not reliably identical, and getting that wrong
    // silently leaves a verb pointing at a disposed State.
    _installedCutPasteHandler = pasteCutPieceAtOrigin;
    widget.cutPieceSlot?.pasteAtOriginHandler = _installedCutPasteHandler;
  }

  void Function()? _installedCutPasteHandler;

  CanvasZoomScale get _zoomScale => CanvasZoomScale.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shellBars.readStageColors();
    _onFloor = CanvasFloorInsets.isFloor(context);
    // ⛔Nothing here answers a RATIO change any more, deliberately. Holding
    // the percentage across one used to take a remembered scale, a re-zoom
    // around a chosen anchor, a value held through the build that noticed
    // it, and a post-frame commit to get the write out of that build — and
    // it still only worked while a panel was MOUNTED to run it. Storing the
    // view in device units makes the whole sequence a no-op: see
    // [_viewport].
  }

  // ── the selection seat: its own object, in its own file ─────────────
  //
  // A collaborator (brush/canvas_panel/canvas_panel_selection.dart, a part of this library).
  // The State keeps the entry points its build tree calls.
  late final _CanvasPanelSelection _selectionSeat = _CanvasPanelSelection(this);

  /// The region this panel last painted ants for — the rebuild guard.
  CanvasSelectionRegion? _paintedIdleRegion;

  /// The idle ants animate only when they are the ones on screen: the
  /// mounted selection layer runs its own ticker.
  void _syncIdleAnts() {
    _paintedIdleRegion = _selectionSeat.idleSelectionRegion;
    final show = _paintedIdleRegion != null;
    if (show && !_idleAnts.isAnimating) {
      unawaited(_idleAnts.repeat());
    } else if (!show && _idleAnts.isAnimating) {
      _idleAnts.stop();
    }
  }

  @override
  void dispose() {
    ShownCels.instance.hide(this);
    // From the REMEMBERED object, for the reason spelled out below about
    // the viewport: the widget's may already point somewhere else.
    _listenedCelPixels?.removeListener(_handleCelPixelsChanged);
    _listenedCelPixels = null;
    CanvasTouchContacts.removeAppWideTouchListener(_handleAppWideTouch);
    // ⛔ONLY the panel's own. `_viewportNotifier` may BE the owner's — the
    // whole point of the controller — and disposing that would kill the
    // view the moment a panel unmounts, taking every other reader of it
    // with it. Measured: "A ValueNotifier was used after being disposed"
    // on the first rail-group fold.
    //
    // ⚠️Unsubscribe FIRST, and from the REMEMBERED object: the owner's
    // notifier outlives this panel, so a listener left behind holds a dead
    // `State` and calls `setState` on it at the owner's next write.
    _viewportState._listenedViewport?.removeListener(_viewportState.handleViewportMovedByOwner);
    _viewportState._listenedViewport = null;
    _viewportState._ownViewport.dispose();
    // A mid-stroke teardown must release the session's warm hold — a
    // leaked hold would gate prerendering forever. Same for a mid-drag
    // selection interaction (R15-⑤: a leaked hold would block seeks).
    if (_strokeActive) {
      widget.onStrokeInputActiveChanged?.call(false);
    }
    if (_selectionDragActive) {
      widget.onSelectionInteractionChanged?.call(false);
    }
    CanvasPanHold.held.removeListener(_onPanHoldChanged);
    widget.selectionCommands?.removeListener(_selectionSeat.handleSelectionChannelChanged);
    widget.selectionCommands?.regionHistoryRecorder = null;
    // Leave no verb pointing at a dead State: the buttons must go dead
    // with the canvas rather than throw when pressed after it is gone.
    if (identical(
      widget.cutPieceSlot?.pasteAtOriginHandler,
      _installedCutPasteHandler,
    )) {
      widget.cutPieceSlot?.pasteAtOriginHandler = null;
    }
    _idleAnts.dispose();
    _selectionFloat.dispose();
    _toolCursorHover.dispose();
    _stampPreview.dispose();
    widget.viewCommands?.unbind(this);
    super.dispose();
  }

  /// I-15: the pan hold took the pointer — the tool's aim is nobody's until
  /// it lets go (a pointer that may not drive a tool may not aim it).
  void _onPanHoldChanged() {
    if (CanvasPanHold.held.value) {
      _forgetCanvasPointer();
    }
  }

  /// [sample] false on pointer DOWN: the tap layer's pick samples that
  /// same press, and sampling here too would double the composite read.
  /// Forgets where the pointer was, because it is no longer on the canvas.
  ///
  /// Without this the seeding below would draw a tool cursor at the last
  /// place the pointer WAS, after it had left.
  void _forgetCanvasPointer() {
    // The census's up/cancel arrive along the hit-test path cached at
    // DOWN, and Flutter keeps delivering them after this subtree
    // detaches — so an unmount mid-press lands here with the notifier
    // already disposed. Guarded at the WRITER rather than per caller:
    // every route in writes the same one, including any added later.
    if (!mounted) {
      return;
    }
    _toolCursor.setToolCursorHover(null, 'forget');
  }

  /// 🚨★★★D34 최종 (유저 2026-08-23, 실기): 「**커서는 일단 커서ui랑 같은곳에
  /// 있는게 최우선**이고, **터치는 커서 없애고 펜은 커서 보이는채로 유지**」
  ///
  /// A finger landed somewhere in the app. Windows has already dragged the
  /// real cursor to it (D34), so the ring standing at the old position is
  /// now a lie about where the pointer is — 「실제 커서는 물론 터치의 중앙에
  /// 있고」. The app cannot make the ring true, so it stops claiming.
  ///
  /// ⛔A DRAWING finger is exempt: there the finger IS the tool, the aim it
  /// writes is its own, and 「1핑거 드로잉일때 커서생기는건 ok」.
  ///
  /// ⚠️This supersedes the older 「a finger never displaces the cursor the
  /// pen put down」 — that rule was about not MOVING the ring to the
  /// finger, which still holds. Hiding it is the opposite: it refuses to
  /// point anywhere rather than pointing somewhere wrong. A hovering pen
  /// writes it back on its very next sample.
  void _handleAppWideTouch() {
    if (!mounted || AppInput.touchDraws) {
      return;
    }
    if (_toolCursorHover.value == null) {
      return;
    }
    // 🚨THE POSITION GOES TOO, and forgetting that is how the first attempt
    // failed. 유저 캡처 (2026-08-23):
    //
    //   aim touch-landed -> null       touch=1/0   ← cleared
    //   aim seed         -> (1769,464) touch=2/0   ← put straight back
    //
    // ⛔`_seedToolCursorIfNeeded` republishes `_lastCanvasPointer` on the
    // next build whenever the ring is null, so clearing the NOTIFIER alone
    // buys exactly one frame — 「터치 다운했을때 1프레임정도 사라지는거같은데
    // 그 뒤 다시 … 과거 자리에서 다시 생겨」.
    //
    // ⚠️And `_aimIsHeld` does not save it: Flutter still counts the mouse
    // as inside (`held=true` in the capture) because no `onExit` ever comes
    // — the OS cursor moved, the framework's idea of it did not.
    //
    // 🚨★This is the SAME asymmetry #1184 fixed on the MouseRegion exits,
    // reintroduced by me in the fix for it. A field with two writers has to
    // be cleared by both, every time.
    _toolCursor.setToolCursorHover(null, 'touch-landed');
  }

  // The tap (Round 6): press, slop, stamp drag, and the pointers holding aim.
  late final _CanvasPanelTap _tap = _CanvasPanelTap(this);

  /// Self-reporting devices (mouse, stylus) currently ON THE GLASS.
  ///
  /// The other kind of holder. A hovering pen writes the aim without ever
  /// pressing, so it is no member of [_pointersHoldingAim] — and a
  /// finger's lift was clearing the ring THAT pen owned, which Flutter
  /// had not asked anyone to clear because the pen has not exited.
  ///
  /// ⚠️A SET, not a flag. Flutter delivers enter/exit PER DEVICE, so a
  /// bool cannot say "someone is inside" when two are: a 2-in-1 with a
  /// pen and a mouse both hovering had the pen's exit turn the flag off
  /// while the mouse was still there, and every finger lift after that
  /// deleted the mouse's ring. Keyed by `event.device`, which is what
  /// Flutter's own bookkeeping uses — a hover has no stable pointer id.
  final Set<int> _hoverDevicesInside = <int>{};

  /// The census records a pointer only if that pointer could DRIVE a tool.
  ///
  /// 🚨★★유저 (2026-08-15 #2): 「브러시툴인채로 터치하면 브러시의 커서가
  /// 움직이는데 … 1핑거 터치 none으로해도 커서가 움직임. 커서 안움직이도록.
  /// **제대로 로직적으로**」.
  ///
  /// The finger was never taken for a brush — the stroke path refuses it
  /// (`interactive_brush_edit_canvas_view`), which is why nothing was drawn.
  /// This census simply asked nothing about the device and wrote the tool
  /// cursor's position for whatever moved, so the outline chased a finger
  /// that was flipping pages.
  ///
  /// ⛔So the fix is not a touch special case here: it is
  /// [AppInput.toolAcceptsPointer], the ONE door 유저 법 「드로잉모드가
  /// 아닌이상은 툴이 작동하면 안되지」 already lives behind. A cursor is where
  /// the tool is AIMED, so a pointer that may not drive the tool may not aim
  /// it either — and because every tool cursor reads this one writer, the
  /// brush outline, the bucket, the dropper and the stamp preview all inherit
  /// the answer rather than each having to remember the question.
  ///
  /// ⚠️Consequence, and it is the right one: on a pen-less tablet with the
  /// slot on flip/none, no brush outline ever appears. There is nothing being
  /// aimed. Lift a pen and it follows the pen.
  void _noteCanvasPointer(
    Offset localPosition, {
    required PointerDeviceKind kind,
  }) {
    // I-15: nor while the pan hold has the pointer — it drives no tool.
    if (!AppInput.toolAcceptsPointer(kind) || CanvasPanHold.held.value) {
      return;
    }
    // 🚨D34: and a MOUSE that a finger produced does not aim either.
    if (aimIsPromotedTouch(
      kind: kind,
      touchContacts: CanvasTouchContacts.appWideCount,
      touchDraws: AppInput.touchDraws,
    )) {
      return;
    }
    // The brush outline rides the same census — including the moves of a
    // stroke already in flight, which is most of what it has to follow.
    //
    // The FILL bucket rides it too. It had a tracker of its own writing the
    // same notifier from a layer mounted at arming time; the two never
    // disagreed, so this is hygiene rather than a fix — but it leaves ONE
    // sentence as the contract: the always-mounted census WRITES, everything
    // else READS.
    //
    // 🚨★★★THE AIM IS ONE VALUE NOW, and it is written unconditionally.
    // There used to be a second field, `_lastCanvasPointer`, holding the
    // same position for the moments no cursor was armed — and a cursor
    // ARMING later read it back through a build-time seed. Two fields that
    // had to move together, which is how D34 kept coming back: #1184 fixed
    // two clear sites that dropped only one of them, and #1189 fixed a
    // THIRD that I introduced in the fix for the first. See
    // [[make-the-invariant-unrepresentable]] — the cure for 「these two must
    // always be cleared together」 is not another clear site, it is one
    // field. A fourth site cannot get this wrong because there is nothing
    // left to get wrong.
    //
    // The cursors were always mounted behind their own `_brushCursorActive`
    // gates, so the value simply being there is what arms them — the seed
    // was doing by hand what the mount already does.
    _toolCursor.setToolCursorHover(localPosition, 'census:${kind.name}');
    if (_toolCursor.brushCursorActive ||
        _toolCursor.fillCursorActive ||
        // The stamp's piece preview reads the same census — one writer,
        // every cursor a reader.
        canvasToolStamps(widget.brushToolState.tool)) {
      // The frame this schedules is the one the whole raster program is
      // about: the pen moves over the canvas and, before the bakes, every
      // open panel was re-rastered for it. Naming it here is what lets
      // the Frame Stats readout say "this panel re-baked on `pointer`",
      // which is otherwise invisible — see [RepaintCause].
      RepaintCause.note('pointer');
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
    //
    // ⛔It used to SAMPLE the composite here as well, per event, and skip
    // the sample on pointer DOWN so the tap layer's own pick would not read
    // the composite twice. F-130 moved the sample into the swatch's `paint`
    // — once per frame, whatever the event rate — so there is nothing left
    // here to skip: the aim above is the whole of what an event writes.
  }

  @override
  void didUpdateWidget(covariant BrushCanvasPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The coordinator can be swapped under us; the signal travels with it.
    _bindCelPixelRevision();
    // A host that passes its own colours can change them without the scope
    // moving; `didChangeDependencies` alone would never hear that.
    if (oldWidget.backdropArgb != widget.backdropArgb ||
        oldWidget.pasteboardColor != widget.pasteboardColor ||
        oldWidget.backdropNone != widget.backdropNone ||
        oldWidget.pasteboardNone != widget.pasteboardNone) {
      _shellBars.readStageColors();
    }
    if (!identical(oldWidget.viewCommands, widget.viewCommands)) {
      oldWidget.viewCommands?.unbind(this);
      _viewportState.bindViewCommands();
    }
    // A host can hand over a DIFFERENT view to own — a document tab
    // swapping slots. Follow the new object, and stop hearing the old one.
    final notifier = _viewportState.viewportNotifier;
    if (!identical(_viewportState._listenedViewport, notifier)) {
      _viewportState._listenedViewport?.removeListener(_viewportState.handleViewportMovedByOwner);
      _viewportState._listenedViewport = notifier..addListener(_viewportState.handleViewportMovedByOwner);
    }
    rebindListener(
      oldWidget.selectionCommands,
      widget.selectionCommands,
      _selectionSeat.handleSelectionChannelChanged,
    );
    // 유저 확정: an open polygon trace survives a frame change and a CUT
    // change, but putting the TOOL or the SHAPE down cancels it.
    //
    // Watched here rather than in the selection layer, which is where the
    // trace is drawn: that layer does not mount for the painting tools, so
    // on "polygon half-drawn, user picks the brush" it is being disposed
    // rather than updated and a check inside it never runs.
    if (oldWidget.brushToolState.tool != widget.brushToolState.tool ||
        oldWidget.brushToolState.activeShapeKind !=
            widget.brushToolState.activeShapeKind) {
      widget.selectionCommands?.abandonPolygon();
    }
    _selectionSeat.bindSelectionHistoryRecorder();
    _syncIdleAnts();
    _followAutoFrame(oldWidget.autoFrame);
  }

  /// Carries out the host's auto-frame request when it is a NEW one —
  /// [previous] is the request the last build carried.
  void _followAutoFrame(CanvasAutoFrameRequest? previous) {
    final request = widget.autoFrame;
    if (request == null || request.token == previous?.token) {
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
        _viewportState._autoFrame(pending);
      }
    });
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

  // Named handlers (not closures) so the memoized bars capture stable
  // callbacks — a fresh closure per build would defeat nothing here, but
  // stale-capture bugs are impossible with tear-offs.
  @override
  // One build of the panel, as its own object (Round 6) — constructed PER
  // BUILD: its fields hold one build's state.
  Widget build(BuildContext context) => _PanelBuild(this).build(context);

  Positioned _idleSelectionAnts(CanvasSelectionRegion idleSelection) {
    return Positioned.fill(
      key: const ValueKey<String>(
        'canvas-idle-selection-ants',
      ),
      child: IgnorePointer(
        // ★ITS OWN LAYER. `_idleAnts`
        // is an `AnimationController`
        // on `repeat()`, so this
        // painter is asked to repaint
        // at DISPLAY RATE for as long
        // as a selection exists — with
        // no pointer input at all.
        // Without a boundary each tick
        // escalates out of the canvas
        // and re-records the whole
        // panel, which is a 60Hz tax
        // on anyone who has selected
        // something and walked away.
        child: RepaintBoundary(
          child: CustomPaint(
            painter:
                SelectionAntsPainter(
                  repaint:
                      _idleAnts,
                  viewport:
                      _viewportState._viewport,
                  committedRegion:
                      idleSelection,
                  screenOffset:
                      Offset.zero,
                  marqueeShapes:
                      const [],
                  // The IDLE
                  // ants: no
                  // tool is
                  // drawing, so
                  // there is no
                  // outline in
                  // progress.
                  openTrail:
                      const [],
                ),
            child:
                const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Positioned _selectionLayer(CanvasUnderlayBuilder? underlayBuilder) {
    return Positioned.fill(
      child: ValueListenableBuilder<TransformToolOptions>(
        valueListenable:
            widget
                .transformOptions ??
            _defaultTransformOptions,
        builder:
            (
              context,
              transformOptions,
              _,
            ) => CanvasSelectionLayer(
              tool: switch (widget
                  .brushToolState
                  .tool) {
                CanvasTool.move =>
                  CanvasSelectionTool
                      .move,
                CanvasTool.cut =>
                  CanvasSelectionTool
                      .cut,
                CanvasTool
                    .fillShape =>
                  CanvasSelectionTool
                      .fillShape,
                _ =>
                  CanvasSelectionTool
                      .select,
              },
              // The verb picks
              // the branch above;
              // the SHAPE rides
              // beside it, so
              // neither axis has
              // to enumerate the
              // other.
              shapeKind:
                  widget
                      .brushToolState
                      .activeShapeKind ??
                  CanvasShapeKind
                      .rect,
              // R17-U: Move = 이동+변형 통합 툴
              // — 핸들 상시.
              alwaysShowTransformBox:
                  widget
                      .brushToolState
                      .tool ==
                  CanvasTool.move,
              onShapeCommitted:
                  _selectionSeat.recordSelectionChange,
              // I-14: a host whose content is not a cel cuts from what it
              // shows.
              onCutShape:
                  widget.onCutContent ??
                  _cutPieceFromShape,
              oneFingerAction:
                  widget.oneFingerAction,
              onFillShape:
                  _fillDrawnShape,
              // CANVAS space,
              // unmapped: this
              // layer never
              // leaves it,
              // unlike the
              // drawing view
              // below whose
              // guides ride
              // into artwork
              // coordinates.
              symmetry: widget
                  .guides
                  ?.actingSymmetry,
              viewport: _viewportState._viewport,
              canvasSize: widget
                  .canvasSize,
              // No frame = a stable sentinel:
              // the selection survives until a
              // real frame context arrives.
              frameToken:
                  widget
                      .coordinator
                      ?.activeFrameKey ??
                  'selection-no-frame',
              selectionCommands:
                  widget
                      .selectionCommands,
              onTransformDragActiveChanged:
                  (active) {
                    if (_transformDragActive !=
                        active) {
                      setState(
                        () => _transformDragActive =
                            active,
                      );
                    }
                  },
              onDragActiveChanged: (active) {
                if (_selectionDragActive !=
                    active) {
                  widget
                      .onSelectionInteractionChanged
                      ?.call(
                        active,
                      );
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
                  _selectionSeat.handleSelectionLift,
              onLiftLanded:
                  _lift.handleLiftLanded,
              onLiftConfirmed:
                  _lift.handleLiftConfirmed,
              onLiftReverted:
                  _lift.handleLiftReverted,
              // R26 #13 follow-up: the implicit
              // whole-picture box frames the
              // cel's tight ink bounds.
              contentBoundsProvider:
                  _activeCelContentBounds,
              // Pending move sessions hold the
              // session's edit lock (seeks
              // refused) WITHOUT locking
              // viewport navigation.
              onMoveSessionPendingChanged:
                  widget
                      .onSelectionInteractionChanged,
              // The transform tool's whole knob
              // set. Read through the
              // listenable above, so changing
              // one mid session re-resamples
              // the open preview instead of
              // waiting for the next gesture.
              transformOptions:
                  transformOptions,
              // TS1: with a
              // composite behind
              // this layer the
              // float goes into
              // it; without one
              // the layer draws
              // its own.
              floatOverlay:
                  underlayBuilder ==
                      null
                  ? null
                  : _selectionFloat,
            ),
      ),
    );
  }

  /// The three regions below each do two things and nothing else: hide
  /// the system cursor while the tool's own cursor is up (the app draws
  /// every tool cursor — 유저, F-130: 「앱 커서만 최대한 가볍게」), and say
  /// when the pointer has gone.
  List<Widget> _brushCursorLayers() {
    return [
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
              HitTestBehavior
                  .translucent,
          // 🚨D34: through the ONE
          // writer, which clears the
          // POSITION too. Nulling the
          // notifier alone left
          // `_lastCanvasPointer` holding
          // the departed pointer, and the
          // build-time seed republished
          // it on the next rebuild — so
          // the ring came back where
          // nobody was pointing.
          onExit: (_) =>
              _forgetCanvasPointer(),
          child:
              const SizedBox.expand(),
        ),
      ),
    ];
  }

  List<Widget> _fillCursorLayers() {
    return [
      Positioned.fill(
        child: MouseRegion(
          cursor: SystemMouseCursors.none,
          opaque: false,
          hitTestBehavior:
              HitTestBehavior
                  .translucent,
          // 🚨D34: through the ONE
          // writer, which clears the
          // POSITION too. Nulling the
          // notifier alone left
          // `_lastCanvasPointer` holding
          // the departed pointer, and the
          // build-time seed republished
          // it on the next rebuild — so
          // the ring came back where
          // nobody was pointing.
          onExit: (_) =>
              _forgetCanvasPointer(),
          // ⛔No tracker of its own: the
          // census writes this notifier
          // for the fill tool now. This
          // region is left with the two
          // jobs only it can do — hiding
          // the system cursor, and
          // saying when the pointer has
          // gone.
          child: const SizedBox.expand(
            key: ValueKey<String>(
              'fill-cursor-tracker',
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _eyedropperCursorLayers() {
    return [
      Positioned.fill(
        child: MouseRegion(
          // R26 #22: the eyedropper wears its
          // OWN icon, not a crosshair — the
          // system cursor hides and the icon
          // rides the aim.
          cursor: SystemMouseCursors.none,
          opaque: false,
          hitTestBehavior:
              HitTestBehavior
                  .translucent,
          // One aim for the icon and the
          // swatch since F-130, so an exit
          // forgets it the way the other two
          // regions do.
          onExit: (_) =>
              _forgetCanvasPointer(),
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
    ];
  }

  Widget _buildViewportContent(BuildContext context) {
    final override = widget.contentOverride;
    if (override != null) {
      return override(context, _viewportState._viewport);
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
      viewport: _viewportState._viewport,
      // A held mapped button's live pick (PEN-7a) — the eyedropper's own
      // pick, because the tool IS the eyedropper while it is held.
      onHoldPick:
          widget.sampleColorAt == null || widget.onEyedropperPick == null
          ? null
          : (point) {
              final color = widget.sampleColorAt!(point);
              if (color != null) {
                widget.onEyedropperPick!(color);
              }
            },
      onPressNeedsCel: widget.onPressNeedsCel,
      onTemporaryToolHold: widget.onTemporaryToolHold,
      onTemporaryToolRelease: widget.onTemporaryToolRelease,
      // PEN-11: one-shot mapped actions (undo/redo) from pen buttons.
      onInvokeAction: widget.onInvokeAction,
      onSourceStrokeCommitted: _handleSourceStrokeCommitted,
      // R22-A: the FILL tool runs through the view's stroke pipeline
      // (the result tiles on the tap frame, landed like a pen-up) instead
      // of the panel tap layer.
      fillDabAt: widget.brushToolState.tool == CanvasTool.fill
          ? widget.fillDabAt
          : null,
      // R26 #18: the live stroke shows clipped to the selection, exactly
      // as the commit will clip it.
      selectionRegion: widget.selectionCommands?.region,
      onStrokeLanderChanged: widget.onStrokeLanderChanged,
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
      // Guides are stored in canvas space, but this view's strokes record
      // in artwork coordinates (the draw-through wrap below). They make the
      // same trip the pointers do, or the axis sits where the pen is not.
      guides: guidesInArtworkSpace(
        widget.guides ?? CutGuides.empty,
        widget.interactiveContentPose,
        widget.canvasSize,
      ),
    );
    // The draw-through wrap: display AND hit testing share one screen
    // matrix, so the active layer draws posed and pointers inverse-map to
    // artwork coordinates in lockstep (R3 ⑩ — always-applied transforms).
    final pose = widget.interactiveContentPose;
    final posedView = pose == null
        ? interactiveView
        : Transform(
            transform: layerPoseViewportWrapMatrix(
              pose.pose,
              widget.canvasSize,
              _viewportState._viewport,
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

  /// What is hidden from the artwork by the panels lying on it. Zero for a
  /// panel nothing lies on, which is every one but the floor.
  EdgeInsets get _framingInsets => widget.floorCover;

  void _handleSourceStrokeCommitted(BrushStrokeCommitData strokeData) {
    labProbe('penUpCommitHandler', () => _commitSourceStroke(strokeData));
  }

  // The lift (Round 6): anchors, the pre-landing surface, and how a lift ends.
  late final _CanvasPanelLift _lift = _CanvasPanelLift(this);

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

  /// A finished cut outline: lift the pixels under it into the slot.
  ///
  /// Reads the ACTIVE LAYER's committed surface and nothing else — no
  /// composite, no layer transform, no effects (유저 확정: "트랜스폼이나 이런
  /// 거 반영 안 한 진짜 순수 픽셀"). That is also why the piece can carry
  /// plain cel coordinates: the read and the eventual write are in the same
  /// space, so a posed layer cannot make them disagree.
  ///
  /// The surface is never written here. Cutting copies.
  void _cutPieceFromShape(CanvasSelectionShape shape) {
    final slot = widget.cutPieceSlot;
    final coordinator = widget._editableCoordinator;
    if (slot == null || coordinator == null) {
      return;
    }
    final piece = buildCutPiece(
      region: CanvasSelectionRegion.shape(shape),
      surface: coordinator.currentSurfaceOf(coordinator.activeFrameKey),
    );
    // Null = the outline covered no paint. Leave the slot alone rather
    // than blanking it: it survives frames, cuts and projects, so one
    // stray scrape must not be able to throw away what is in it.
    if (piece != null) {
      slot.hold(piece);
    }
  }

  /// TS7: the tap layer's press verb, continued while the pointer is held.
  ///
  /// One rule for both of its tools rather than a per-tool `if` at the call
  /// site: the stamp continues by SPACING (a stamp lands only when the
  /// pointer has travelled a whole piece), the eyedropper by sampling again.
  /// A tool whose press means something that must not repeat simply keeps no
  /// continue verb — which is why the fill is not in this list even though
  /// it is the other tap-shaped tool.
  void _continuePressVerb(PointerEvent event) {
    if (!AppInput.toolAcceptsPointer(event.kind)) {
      return;
    }
    final point = _viewportState.canvasPointOf(event);
    if (canvasToolStamps(widget.brushToolState.tool)) {
      _tap.dragStampTo(point);
      return;
    }
    if (widget.brushToolState.tool == CanvasTool.eyedropper) {
      _tap.toolTapHandler()?.call(point);
    }
  }

  /// Paint a finished shape-fill outline.
  ///
  /// Straight through the stroke funnel like the bucket's own dab, so the
  /// live selection clips it, undo covers it and serialization is free —
  /// the fill has landed this way since P6 and the shape fill is the same
  /// dab from a different source.
  void _fillDrawnShape(CanvasSelectionShape shape) {
    final build = widget.shapeFillDabFor;
    if (build == null || widget._editableCoordinator == null) {
      return;
    }
    final dab = build(shape, widget.brushToolState.color);
    if (dab == null) {
      return;
    }
    final blend = widget.brushToolState.activeBlendMode;
    _commitSourceStroke(
      BrushStrokeCommitData(
        // ERASE rides a flag on the DAB, not the blend mode: the
        // materializer reads `dab.erase` per dab and the erase blend takes
        // the plain path, so passing the mode alone would paint the shape
        // instead of clearing it. This is what makes 사각형/올가미 지우개
        // out of the erase entry in the blend list.
        sourceDabs: [
          if (blend == BrushBlendMode.erase) dab.copyWith(erase: true) else dab,
        ],
        blendMode: blend,
      ),
    );
  }

  /// Drop the held piece back where it was cut from.
  ///
  /// TS8: whether it lands over what is there or under it is the STAMP's
  /// BLEND, not a second button. 위/아래 was always COMPOSITE ORDER rather
  /// than a layer row (유저 확정), which is precisely what `color`/`behind`
  /// are — so the pair collapsed into the list every other tool already
  /// has, and every other mode came along with them.
  ///
  /// It presses at the STAMP's opacity like every other stamp route (유저
  /// 2026-08-15). Read from the stamp's own field rather than from
  /// [BrushToolState.activeOpacity]: today the button only exists inside the
  /// stamp tile so the two are the same number, but a shortcut added later
  /// would reach this from the brush — and then "active" would mean the 40%
  /// left over from shading, which is exactly the leak TP1's per-tool fields
  /// were built to make impossible.
  void pasteCutPieceAtOrigin() {
    final piece = widget.cutPieceSlot?.piece;
    if (piece == null || widget._editableCoordinator == null) {
      return;
    }
    _commitStampDabs([
      buildCutPasteDab(piece, opacity: widget.brushToolState.cutStampOpacity),
    ]);
  }

  /// Lands stamp dabs with the stamp tool's own blend.
  ///
  /// 🚨ERASE rides a flag on the DAB, not the blend mode — the materializer
  /// reads `dab.erase` per dab and the erase blend takes the plain path, so
  /// passing the mode alone paints the piece instead of clearing with it.
  /// This is the THIRD place that trap has been hit (bucket, shape fill,
  /// here), which is why all three stamp routes go through one method.
  void _commitStampDabs(List<BrushDab> dabs) {
    final blend = widget.brushToolState.activeBlendMode;
    _commitSourceStroke(
      BrushStrokeCommitData(
        sourceDabs: blend == BrushBlendMode.erase
            ? [for (final dab in dabs) dab.copyWith(erase: true)]
            : dabs,
        blendMode: blend,
      ),
    );
  }

  BitmapSurface? _contentBoundsSurface;
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  _contentBoundsCached;

  void _commitSourceStroke(BrushStrokeCommitData rawStrokeData) {
    // Only reachable from the interactive canvas, which requires the
    // coordinator to exist.
    final coordinator = widget._editableCoordinator!;
    final strokeData = _selectionSeat.clipStrokeToSelection(rawStrokeData);
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
          strokeOpacity: strokeData.strokeOpacity,
          promotedBase: strokeData.promotedBase,
          promotedTiles: strokeData.promotedTiles,
        );
        return;
      }
      final stroke = BrushStrokeHistoryCommand(
        coordinator: coordinator,
        strokeData: strokeData,
        cacheInvalidationSink: widget.cacheInvalidationSink,
      );
      final prefix = widget.takeStrokePrefixCommand?.call();
      historyManager.execute(
        prefix == null
            ? stroke
            // ⚠️The prefix ALREADY RAN at pen-down and re-running it is a
            // no-op: `UpdateLayerTimelineCommand` holds its before/after
            // from construction, so applying `after` twice writes the same
            // layer. The stroke runs for the first time here, into the
            // block that prefix made.
            : CompositeCommand(
                description: 'Draw on a new frame',
                commands: [prefix, stroke],
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
    this.pageStrip = const <Widget>[],
    this.bottomOverlaySpan = 0,
    this.railBand,
  });

  final Widget child;
  final Widget bottomBar;
  final Widget rightStripBar;

  /// The horizontal panbar, its own capsule on the top edge.
  final Widget horizontalStripBar;

  /// See [BrushCanvasPanel.pageStrip] — empty means no capsule at all.
  final List<Widget> pageStrip;

  // ⛔`strokeActive` and `contentStrokeActive` are GONE from this layout
  // (H3, 유저 2026-08-21). They existed for ONE consumer — the floor
  // controls' stroke fade — and carrying a live stroke signal down here
  // for a look that no longer exists is how a dead input survives a
  // deletion. The panel still knows both; nothing else here asked.

  /// What panels floating over this one hide from the artwork.
  ///
  /// The canvas fills the whole box — panels lie ON it, they do not take
  /// space from it — and the chrome floats, pulled in by this much so the
  /// pieces you reach for hug the part you can still see. Zero for a panel
  /// nothing is covering.
  final EdgeInsets cover;

  /// ⑩: what lies ON the artwork at the bottom edge (the collapsed row).
  /// The horizontal bar steps up by it; framing does not.
  final double bottomOverlaySpan;

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

  /// How wide the page strip's capsule stands (유저 확정 ⑥). Wide enough for
  /// the shared icon button's 26px minimum and the page readout stacked
  /// under it, narrow enough to read as an EDGE ornament rather than a
  /// second rail.
  static const double _pageStripWidth = 32;

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
        // ★THE CANVAS IS ITS OWN LAYER, and the shell's furniture is
        // another. This is where a cursor move's repaint stops.
        //
        // The deck round put the artwork behind a boundary so the cursor
        // could not re-record IT, and that held — but paint still climbed
        // out of the viewport once per move and re-recorded the floor, the
        // two panbar capsules and the pill. A boundary INSIDE the viewport
        // (between the ClipRect and the deck) was tried first and appeared
        // to do nothing, so it was removed and the remainder written off as
        // unexplained.
        //
        // 🚨It appeared to do nothing because the metric saturates: a
        // counting painter rises at most once per frame no matter how many
        // descendants dirtied, so with two sources above it, muting one
        // changes nothing that can be seen. Bisecting with a second
        // boundary OUTSIDE the panel located the real stopping point —
        // here, one level above everything the viewport owns. With this,
        // the inner one is genuinely redundant and stays gone.
        //
        // What it costs: the canvas composites into its own layer. That is
        // what it is FOR — the shell above and the artwork below now change
        // independently, which is the honest description of their
        // relationship.
        Positioned.fill(
          child: RepaintBoundary(
            child: KeyedSubtree(
              key: const ValueKey<String>('canvas-editor-panel-content'),
              child: child,
            ),
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
                    // ⑩: …and above whatever lies ON the artwork at that
                    // edge. The collapsed row frames nothing, so it is not
                    // in `insets` — but it is exactly where this bar was,
                    // which is what the user saw.
                    bottom: insets.bottom + bottomOverlaySpan + _capsuleMargin,
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
                children: [
                  // THE PAGE STRIP, at the LEFT CENTRE (유저 확정 ⑥).
                  //
                  // Same axis law the two bars follow: ALONG the edge it
                  // rides it holds the window's centre, and ACROSS that
                  // edge it sits on the edge. A rail opening on the right
                  // is not a reason for the page you are turning to walk
                  // left.
                  if (pageStrip.isNotEmpty)
                    Positioned(
                      left: _capsuleMargin,
                      top: _capsuleMargin,
                      bottom: _capsuleMargin,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _capsule(
                          colorScheme,
                          keyValue: 'canvas-page-strip',
                          width: _pageStripWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: pageStrip,
                          ),
                        ),
                      ),
                    ),
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
      child: SuperellipseClip(
        shape: shape,
        child: SizedBox(width: width, height: height, child: child),
      ),
    );
  }
}

/// The floor's controls, laid on the drawing.
///
/// The Stack takes pointers only where its children are, so the empty
/// middle — most of the screen — still belongs to the canvas.
///
/// ⛔THE STROKE FADE IS GONE (H3, 유저 2026-08-21: 「스트로크중에 캔버스
/// 패널의 알약 살짝 안보이게하는 기능 있는데, **삭제.** 다른 알약에도
/// 이런거있으면 삭제 … 진짜 그냥 **알약 불투명도 낮추는거만 심플하게 삭제**」).
///
/// It dropped to 0.16 for the duration of a stroke, argued for as "the
/// controls are in the way exactly then". They are not: the Stack already
/// leaves the artwork every pixel the controls do not cover, and chrome
/// that half-vanishes while the hand works reads as the app flickering
/// rather than as room being made.
///
/// ⚠️What is NOT removed, in the user's own breath: 「스트로크중 알약 위치로
/// 이동했다고 스트로크 끊는다거나 그런건 그대로 둠」. Whether reaching the
/// pill interrupts a stroke is a POINTER question and is untouched here.
class _FloatingCanvasControls extends StatelessWidget {
  const _FloatingCanvasControls({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(
    key: const ValueKey<String>('canvas-floating-controls'),
    children: children,
  );
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
/// It FOLDS from the outside in as the panel narrows — colours first (a
/// choice you make once a project), then rotate/flip, 1:1, the host's own
/// verbs, and last the zoom steps — and it never stands down entirely,
/// because with the docked bar gone it is the only home Fit has.
///
/// 🚨THE GEAR IS NOT A POLICY, IT IS WHERE THE FOLDED THINGS GO (유저 확정
/// 2026-08-13). Which controls a panel keeps out of its pill was a decision
/// for one day; the rule that replaced it has one axis:
///
///  * ON THE FLOOR ([onFloor]) the pill starts with EVERYTHING laid out
///    flat and folds only what will not fit, so a wide floor shows no gear
///    at all — there is nothing behind it.
///  * ANYWHERE ELSE the same groups start folded and never unfold, which
///    is bit-for-bit the bar a rail panel has today. A sub viewer stretched
///    as wide as the floor still keeps its gear (유저 확정: 「바닥 둘만」).
///
/// Both ends of that meet in the middle: fold a floor pill narrow enough
/// and it becomes the rail's bar, gear and all. Nothing is ever cut off and
/// nothing has to be guessed at — what left the pill is one tap away, in
/// the one place things that left the pill go.
class _CanvasViewportBottomBar extends StatelessWidget {
  static const double height = 28;

  /// ⛔`_wideLayoutMinWidth` and `_pillColorMinWidth` are GONE. They were
  /// the widths at which the pill let itself show the rotate/flip pair and
  /// the three surface swatches — a threshold per group, each swept by
  /// hand. The fold ladder below asks the same question by ADDING UP what
  /// the pill is being asked to hold, so a group added later gets an
  /// answer instead of a new constant.
  ///
  /// What one of the bar's OWN controls costs. Unlike [_leadingControlBudget]
  /// these are not budgets but measurements: the bar builds these widgets,
  /// so their widths are the widgets' own.
  static const double _ownIconWidth = 26; // AppIconButtonSize.bar.minWidth
  static const double _zoomReadoutWidth = 44; // the DragValueLabel's width
  static const double _rotationReadoutWidth = 40;
  static const double _swatchWidth = 18; // ColorSwatchButton.diameter
  static const double _swatchGap = 4;
  static const double _dividerWidth = 13; // 1px rule, 6px margin each side
  static const double _gearWidth = 28; // 16px glyph + 6px padding each side
  static const double _pillEnds = 8; // the 4px SizedBox at each end

  /// Slack on every fold decision, so a control that measures a pixel wider
  /// than its token folds one step early rather than escaping the capsule.
  /// The direction of the error is the whole point — see
  /// [_leadingControlBudget].
  static const double _foldSlack = 8;

  /// What one host control in [leading] adds to that threshold: the widest
  /// control in the shared vocabulary (a [DragValueLabel] readout) plus
  /// breathing room. The bar cannot measure widgets it did not build, so
  /// it budgets generously on purpose — over-budgeting only makes the bar
  /// scroll a little sooner, while under-budgeting OVERFLOWS.
  static const double _leadingControlBudget = 44;

  /// What the pill costs with NOTHING of the host's in it — the floor
  /// under which the host's controls have to go, so the two things that
  /// may never drop always have room. Measured: 26 for Fit, 28 for the
  /// gear and its hit padding, 13 for the divider between them, 8 for the
  /// pill's ends, and slack.
  ///
  /// ⚠️It went from 60 to 88 when the gear arrived. It has to: the gear
  /// never sheds, so anything that does not count it is promising space
  /// the pill has already spent — which is exactly how Fit ended up
  /// outside the capsule's clip in a 206..250px band once before.
  ///
  /// 🚨MEASURED, not reasoned, and the number is deliberately TIGHT. This
  /// constant decides whether the HOST's controls have to go, and that
  /// decision wants the opposite error from [_leadingControlBudget]: every
  /// pixel of slack here is a band of widths where a panel silently loses
  /// its page navigation. A reasoned 95 cost 7px of exactly that.
  ///
  /// The sweep that produced 88 is a test ("nothing the pill shows escapes
  /// the capsule, at any width"), walking 120..620px with 0/3/6 host
  /// controls. At 85 the pill overflows by 2px at 176px wide; at the
  /// pre-gear 60 the GEAR leaves the capsule in a 152..172px band with
  /// three host controls and a 228..248px band with six.
  static const double _essentialBudget = 88;

  /// The LEAST a host control can cost — the shared icon button's own
  /// minimum. [_leadingControlBudget] is its opposite and both are right,
  /// because the two decisions want opposite errors: deciding what the
  /// pill can AFFORD, budget high and shed a little early; deciding
  /// whether the host's own controls have to GO, budget low, because
  /// dropping the page navigation from a rail that could have held it is
  /// the worse mistake. Using the generous number for both took the
  /// timesheet's whole cluster away at its default width.
  static const double _leadingControlFloor = 26;

  /// Below this the pill drops the zoom readout and the two zoom steps,
  /// and below it MINUS the host's own controls it drops those too. It
  /// never drops Fit, and it never stands down: the docked bar that used
  /// to be the alternative is gone.
  static const double pillMinWidth = 190;

  const _CanvasViewportBottomBar({
    this.onFloor = false,
    this.leading = const <Widget>[],
    this.hostSettings = const <PanelFlyoutEntry>[],
    required this.viewport,
    required this.canvasSize,
    required this.paperColor,
    required this.paperNone,
    required this.onPaperColorChanged,
    required this.onPaperNone,
    required this.pasteboardColor,
    required this.pasteboardNone,
    required this.onPasteboardColorChanged,
    required this.onPasteboardNone,
    required this.backdropColor,
    required this.backdropNone,
    required this.currentColorOf,
    required this.onBackdropColorChanged,
    required this.onBackdropNone,
    required this.onViewportChanged,
    required this.onViewportChangeEnd,
    required this.liveViewport,
    required this.viewEnabled,
    required this.onZoomSet,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onReset,
    required this.onRotateCcw,
    required this.onRotateCw,
    required this.onRotateReset,
    required this.onRotateByDrag,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
  });

  /// Whether this pill is the FLOOR's — see the class doc. It is the one
  /// bit that decides whether a group starts on the pill or in the gear.
  final bool onFloor;

  /// R26 #41: host controls at the head of the pill.
  final List<Widget> leading;

  /// What the host puts in the gear rather than in the pill — see
  /// [BrushCanvasPanel.bottomBarSettings]. These cost the pill NOTHING:
  /// the gear is one button whether the list behind it holds three rows or
  /// ten, which is the whole reason a verb moves here.
  final List<PanelFlyoutEntry> hostSettings;

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

  /// Each plane's absence and its 「없음」 (F-114): the swatch slashes and
  /// the window dims its opacity bar while a plane is none.
  final bool paperNone;
  final VoidCallback? onPaperNone;
  final bool pasteboardNone;
  final VoidCallback? onPasteboardNone;
  final bool backdropNone;
  final VoidCallback? onBackdropNone;

  /// The tool's own colour, handed to every picker this bar opens for
  /// its 현재 색 반영 button (see [ColorSwatchButton.currentColorOf]).
  final int Function() currentColorOf;

  /// The SAME view as [viewport], as a signal the settings list can hold.
  /// The field is what this bar draws with; the listenable is what the
  /// overlay route redraws on.
  ///
  /// ⚠️Nullable, because the owner may not have framed the view yet — and
  /// "not framed" resolves to the IDENTITY, which depends on the effective
  /// ratio and therefore cannot be stored anywhere.
  final ValueListenable<CanvasViewport?> liveViewport;

  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback onViewportChangeEnd;

  /// Whether there is a view to operate — [BrushCanvasPanel.hasContentToView].
  /// False keeps fit, 1:1, the zoom steps and the readout in place, disabled.
  final bool viewEnabled;

  final ValueChanged<double> onZoomSet;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
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
  // One build of the bar, as its own object (Round 6) — constructed PER
  // BUILD: its fields hold one build's state, and the widget is const.
  Widget build(BuildContext context) => _BottomBarBuild(this).build(context);

  /// R26 #42: this bar's button style is now the app-wide default, so it
  /// lives in [AppIconButton] — this is just the local spelling.
  Widget _barIconButton({
    required String keyValue,
    required String tooltip,
    required Widget icon,
    required VoidCallback? onPressed,
    bool isSelected = false,
    List<String> shortcuts = const [],
  }) {
    return AppIconButton(
      keyValue: keyValue,
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      isSelected: isSelected,
      shortcuts: shortcuts,
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
    this.enabled = true,
  });
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;
  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback? onViewportChangeEnd;
  final bool enabled;
  @override
  Widget build(BuildContext context) => _CanvasViewportPanbar(
    axis: Axis.horizontal,
    viewport: viewport,
    editorViewportSize: editorViewportSize,
    canvasSize: canvasSize,
    onViewportChanged: onViewportChanged,
    onViewportChangeEnd: onViewportChangeEnd,
    enabled: enabled,
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
    this.enabled = true,
  });
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;
  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback? onViewportChangeEnd;
  final bool enabled;
  @override
  Widget build(BuildContext context) => _CanvasViewportPanbar(
    axis: Axis.vertical,
    viewport: viewport,
    editorViewportSize: editorViewportSize,
    canvasSize: canvasSize,
    onViewportChanged: onViewportChanged,
    onViewportChangeEnd: onViewportChangeEnd,
    enabled: enabled,
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
    required this.enabled,
  });
  final Axis axis;
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;
  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback? onViewportChangeEnd;

  /// F-77: false keeps the panbar in its place with nothing to pan.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = axis == Axis.horizontal;
    final metrics = CanvasViewportPanMetrics(
      axis: axis,
      viewport: viewport,
      editorViewportSize: editorViewportSize,
      canvasSize: canvasSize,
    );
    return SizedBox(
      key: ValueKey<String>(
        isHorizontal
            ? 'canvas-viewport-horizontal-scrollbar'
            : 'canvas-viewport-vertical-scrollbar',
      ),
      height: isHorizontal ? 14 : double.infinity,
      width: isHorizontal ? double.infinity : 14,
      child: AppScrollbar(
        axis: axis,
        offset: metrics.scrollOffset,
        viewportExtent: metrics.visibleExtent,
        contentExtent: metrics.scaledContentExtent,
        // The whole lane pans relatively: the canvas panbar has always
        // been a grab-anywhere 1:1 surface, not a jump-to-tap track.
        lanePress: AppScrollbarLanePress.relativeDrag,
        enabled: enabled,
        onOffsetChanged: (next) =>
            onViewportChanged(metrics.viewportForScroll(next)),
        onChangeEnd: onViewportChangeEnd,
      ),
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
///
/// 🚨★★★WHERE IT IS = THE DRAWING BOUND, [PasteboardBounds] (F-114, 유저
/// 2026-09-12: 「3x에서만 그려지는데 배경 색 설정하면 페이스트보드가 5x크기로
/// 보이고 … 그려지는건 제대로 3x인데. 법 나뉘어져있는거같으니 통일」). It
/// was a SHOWING number of its own — `Project.pasteboardMargin`, default 2.0
/// canvases per side, set in the project background window — kept apart on
/// the argument that at the drawing bound the backdrop only showed below
/// about 20% zoom. The bound became 3×3 at H2 (2026-08-22) while that number
/// stayed at five, so the plane showed a pasteboard two canvases wider than
/// anything could be drawn on. One wall now: the plane stops exactly where
/// ink stops.
class _StagePlanes extends StatelessWidget {
  const _StagePlanes({
    required this.backdropArgb,
    required this.pasteboardArgb,
    required this.backdropNone,
    required this.pasteboardNone,
    required this.paperNone,
    required this.canvasSize,
    required this.viewport,
    required this.child,
  });

  final int backdropArgb;
  final int pasteboardArgb;

  /// Which planes are ABSENT (F-114) — each shows the checkerboard where it
  /// would be.
  final bool backdropNone;
  final bool pasteboardNone;
  final bool paperNone;
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
                backdropNone: backdropNone,
                pasteboardNone: pasteboardNone,
                paperNone: paperNone,
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
///
/// 🚨F-114 (유저 2026-09-15: 「없음버튼 누르면 없는상태. 즉 해당 용지부분이
/// 체크무늬되도록. 페이스트보드도 백그라운드도 동일하게」): an ABSENT plane is
/// the checkerboard over exactly the region that plane would fill — one rule
/// for the three ([_paintPlane]). A paper that is there stays the layer
/// stack's to paint, alpha and all; an absent one paints nothing in the stack,
/// so its checkerboard is laid here, under the artwork.
class _StagePlanesPainter extends CustomPainter with RepaintOnProps {
  const _StagePlanesPainter({
    required this.backdrop,
    required this.pasteboard,
    required this.backdropNone,
    required this.pasteboardNone,
    required this.paperNone,
    required this.canvasSize,
    required this.viewport,
  });

  final Color backdrop;
  final Color pasteboard;
  final bool backdropNone;
  final bool pasteboardNone;
  final bool paperNone;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    // 🚨 Clip to our own box, because the quad below is built in VIEWPORT
    // coordinates and therefore reaches as far as the pasteboard does —
    // three canvas widths and heights, 7020 x 4962 units at the default cut
    // size (it was five, 11700 x 8270, when the figures below were
    // measured — the showing margin F-114 retired). A `CustomPaint` clips nothing on its own, so the
    // display list's BOUNDS became that whole quad, and the engine sizes
    // a raster cache entry from the bounds times the transform:
    //
    //   369 MiB  x  zoom²  x  dpr²
    //
    // ⚠️ That constant is the CUT canvas (`defaultCutCanvasSize`, 2340 x
    // 1654) — this painter is handed `widget.canvasSize`, not the
    // camera's 1920 x 1080. Working it from the camera size gives 197.75
    // MiB, which is what the commit adding this clip said, and misses by
    // a factor of two. With dpr since measured at 1.0 the corrected
    // figure lands within 5% of both real-app readings: 90% zoom predicts
    // 313 MB against 296 measured, 131% predicts 664 against 634.
    //
    // Measured on the real app: the picture cache ran to ~1 GB on an
    // EMPTY project and tracked zoom² exactly, with a cliff where the
    // allocation finally failed. One `drawPath`.
    //
    // Everything past this box is composited away anyway, so the app was
    // paying hundreds of megabytes to rasterize pixels it then threw out.
    // And by default it was not even a visible colour: `backdrop` and
    // `pasteboard` are BOTH `0xFF141517`, so the money went on painting
    // #141517 over #141517.
    //
    // This is a return to the convention, not an invention — four of the
    // five canvas-space painters already clip (`canvas_layer_stack_view`,
    // `editor_canvas_area` twice, `camera_frame_overlay`, whose comment
    // says in as many words that CustomPaint does not clip). This one was
    // the exception.
    canvas.save();
    canvas.clipRect(box);
    _paintPlane(canvas, box, null, (color: backdrop, none: backdropNone));
    _paintPlane(
      canvas,
      box,
      _quad(canvasSize.pasteboardRect),
      (color: pasteboard, none: pasteboardNone),
    );
    if (paperNone) {
      _paintPlane(
        canvas,
        box,
        _quad(canvasSize.canvasRect),
        (color: const Color(0x00000000), none: true),
      );
    }
    canvas.restore();
  }

  /// One plane over [region] — the whole [box] when null: the checkerboard
  /// when the plane is absent, otherwise its colour wherever that has any
  /// alpha. The plane rides as ONE value, its colour and whether it is there.
  ///
  /// ⚠️The box as a RECT, not a path: the backdrop is the box itself, and
  /// the clip test asks the first recorded path whether it escapes the box
  /// — the pasteboard's quad does, a box-shaped path cannot.
  static void _paintPlane(
    Canvas canvas,
    Rect box,
    Path? region,
    ({Color color, bool none}) plane,
  ) {
    final (:color, :none) = plane;
    if (none) {
      canvas.save();
      if (region != null) {
        canvas.clipPath(region);
      }
      paintAlphaCheckerboard(canvas, box);
      canvas.restore();
      return;
    }
    if (color.a <= 0) {
      return;
    }
    final paint = Paint()..color = color;
    if (region == null) {
      canvas.drawRect(box, paint);
    } else {
      canvas.drawPath(region, paint);
    }
  }

  /// [rect]'s four corners through the view transform, as a PATH: under
  /// rotation a plane is a quad, and a Rect would silently square it back up.
  Path _quad(Rect rect) {
    Offset at(double x, double y) {
      final point = viewport.canvasToViewport(CanvasPoint(x: x, y: y));
      return Offset(point.x, point.y);
    }

    return Path()
      ..moveTo(at(rect.left, rect.top).dx, at(rect.left, rect.top).dy)
      ..lineTo(at(rect.right, rect.top).dx, at(rect.right, rect.top).dy)
      ..lineTo(at(rect.right, rect.bottom).dx, at(rect.right, rect.bottom).dy)
      ..lineTo(at(rect.left, rect.bottom).dx, at(rect.left, rect.bottom).dy)
      ..close();
  }

  @override
  Object get props => (
    backdrop,
    pasteboard,
    backdropNone,
    pasteboardNone,
    paperNone,
    canvasSize,
    viewport,
  );
}

/// Which of the pill's foldable groups are OUT at a given width — the fold
/// ladder as a value the bar reads, instead of five flags mutated in the
/// middle of its build. (The audit's 2026-09-03 restructure; the ladder
/// and its comments moved verbatim from `_CanvasViewportBottomBar.build`.)
class _PillFold {
  const _PillFold({
    required this.showColors,
    required this.showViewControls,
    required this.showReset,
    required this.showHostVerbs,
    required this.showZoomSteps,
    required this.cramped,
    required this.anythingFolded,
  });

  final bool showColors;
  final bool showViewControls;
  final bool showReset;
  final bool showHostVerbs;
  final bool showZoomSteps;

  /// Below this the readout goes as well, and below THAT the host's
  /// own controls do — the two thresholds that were already here,
  /// and the reason a folded floor pill lands on exactly the bar a
  /// rail panel wears. Everything foldable is forced down with them,
  /// so the two ends of the rule meet instead of overlapping.
  final bool cramped;

  /// Whether the gear has anything to list.
  final bool anythingFolded;

  /// The ladder, run for [room] pixels of width.
  static _PillFold fit({
    required double room,
    required double owed,
    required bool onFloor,
    required bool hasLeading,
    required double colorsWidth,
    required bool hasViewControls,
    required double viewControlsWidth,
    required bool hostVerbsCanUnfold,
    required int hostVerbCount,
    required bool hostSettingsListed,
  }) {
    // WHERE EACH GROUP STARTS. The floor lays them all out; every
    // other panel starts where a floor pill ENDS UP once it has run
    // out of room, and stays there however wide it gets.
    var showColors = onFloor && colorsWidth > 0;
    var showViewControls = onFloor && hasViewControls;
    var showReset = onFloor;
    var showHostVerbs = onFloor && hostVerbsCanUnfold;
    var showZoomSteps = onFloor;

    bool anythingFolded() =>
        (colorsWidth > 0 && !showColors) ||
        (hasViewControls && !showViewControls) ||
        !showReset ||
        (hostSettingsListed && !showHostVerbs) ||
        (onFloor && !showZoomSteps);

    double pillWidth() {
      final clusters = <double>[
        if (hasLeading || showHostVerbs)
          owed +
              (showHostVerbs
                  ? hostVerbCount * _CanvasViewportBottomBar._ownIconWidth
                  : 0),
        _CanvasViewportBottomBar._ownIconWidth + // Fit, which never folds
            (showReset ? _CanvasViewportBottomBar._ownIconWidth : 0) +
            (showZoomSteps ? 2 * _CanvasViewportBottomBar._ownIconWidth : 0) +
            _CanvasViewportBottomBar._zoomReadoutWidth,
        if (showViewControls) viewControlsWidth,
        if (showColors) colorsWidth,
        if (anythingFolded()) _CanvasViewportBottomBar._gearWidth,
      ];
      return _CanvasViewportBottomBar._pillEnds +
          clusters.fold<double>(0, (sum, width) => sum + width) +
          _CanvasViewportBottomBar._dividerWidth * (clusters.length - 1) +
          _CanvasViewportBottomBar._foldSlack;
    }

    // THE FOLD LADDER (유저 확정 2026-08-13), outside in: the colours
    // are a choice you make once a project, and the zoom steps are
    // the last thing to go because they are the last thing that is
    // still about the view you are looking at right now.
    //
    // Re-asked after every fold rather than solved in one pass: the
    // gear appears the moment the first group folds and costs the
    // pill its own width, so the answer for the second group is not
    // the answer the first one was given.
    if (showColors && pillWidth() > room) {
      showColors = false;
    }
    if (showViewControls && pillWidth() > room) {
      showViewControls = false;
    }
    if (showReset && pillWidth() > room) {
      showReset = false;
    }
    if (showHostVerbs && pillWidth() > room) {
      showHostVerbs = false;
    }
    if (showZoomSteps && pillWidth() > room) {
      showZoomSteps = false;
    }

    final cramped = room < _CanvasViewportBottomBar.pillMinWidth + owed;
    if (cramped) {
      showColors = false;
      showViewControls = false;
      showReset = false;
      showHostVerbs = false;
      showZoomSteps = false;
    }
    return _PillFold(
      showColors: showColors,
      showViewControls: showViewControls,
      showReset: showReset,
      showHostVerbs: showHostVerbs,
      showZoomSteps: showZoomSteps,
      cramped: cramped,
      anythingFolded: anythingFolded(),
    );
  }
}
