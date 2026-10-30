import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerDeviceKind, PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;

import '../canvas/shown_cels.dart';
import '../canvas/stroke_in_flight.dart';
import '../canvas/view_hand.dart';
import '../timeline/memo_token.dart'
    show ByIdentity, ByList, Kept, keptWhileSame;
import '../timeline/axis_turn.dart' show sizedAlong;
import '../debug/repaint_cause.dart';
import '../../services/command.dart';
import '../../services/input/modifier_keys.dart';
import '../../services/input/pen_pose.dart';
import '../../services/input/pen_sidecars.dart';
import '../../services/cel_source_effect_pass.dart';
import '../../services/cel_surface_as_shown.dart';
import '../../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds, celTextPlateSurface;
import '../../services/bitmap_surface_brush_commit.dart'
    show materializeBrushDabSequenceOnBitmapSurface;
import '../../services/brush_stroke_blend.dart'
    show bitmapSurfaceRegionPixels;
import '../../services/brush_stroke_commit_data.dart';
import '../../services/undo_surface_snapshot.dart';
import '../../models/layer_effect.dart';
import '../../models/bitmap_surface.dart';
import '../../models/bitmap_tile.dart';
import '../../models/cel_text.dart';
import '../../models/tile_coord.dart';
import '../../models/cut_piece.dart' show CutPiece;
import '../../models/brush_dab.dart';
import '../../models/brush_dab_sequence.dart';
import '../../models/brush_edit_canvas_input_settings.dart';
import '../../models/brush_frame_key.dart';
import '../../models/dirty_region.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_paint_clip.dart';
import '../../services/canvas_selection_region.dart';
import '../../services/cel_pixel_region.dart' show regionInArtworkSpace;
import '../../services/selection_placement.dart';
import '../../services/stamp_carry.dart';
import '../../models/canvas_point.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/shape_tool_options.dart';
import '../../services/canvas_flood_fill.dart'
    show FloodFillOptions, regionFillPieces;
import '../../services/plain_line_region.dart';
import '../../services/mark_under_a_pixel.dart';
import '../../models/canvas_size.dart';
import '../../models/pasteboard_bounds.dart';
import '../../models/drawing_guide.dart';
import '../../services/guide_stroke_input.dart' show ShiftLine, StrokeLock;
import '../../models/canvas_viewport.dart';
import '../../models/viewport_point.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/commands/brush_lift_move_history_command.dart';
import '../../services/commands/brush_stroke_history_command.dart';
import '../../services/piece_landing.dart';
import '../../services/cache_invalidation_executor.dart';
import '../../services/history_manager.dart';
import '../canvas/bitmap_surface_painter.dart';
import '../canvas/active_stroke_overlay.dart';
import '../canvas/canvas_selection_layer.dart';
import '../canvas/canvas_touch_contacts.dart' show CanvasTouchContacts;
import 'promoted_touch_aim_policy.dart' show aimIsPromotedTouch;
import '../canvas/canvas_zoom_scale.dart';
import '../canvas/selection_ants_painter.dart';
import '../canvas/landing_preview.dart';
import '../canvas/selection_float_overlay.dart';
import '../canvas/canvas_line_hold.dart';
import '../canvas/canvas_view_hold.dart';
import '../canvas/canvas_press.dart';
import '../canvas/canvas_tool_holds.dart';
import '../canvas/canvas_viewport_gesture_layer.dart';
import '../canvas/flip_hud_controller.dart';
import '../canvas/flip_hud_overlay.dart';
import 'canvas_floor_insets.dart';
import 'pasteboard_reach_row.dart';
import '../../models/app_input_settings.dart';
import '../debug/input_inspector.dart' show InputInspector;
import '../../services/cut_piece_lift.dart';
import '../../services/cut_piece_slot.dart';
import '../../services/last_stroke_slot.dart';
import '../../services/cut_piece_stamp.dart';
import 'cut_into_the_hand.dart';
import 'cut_piece_preview.dart';
import '../../models/project.dart' show defaultProjectBackdropArgb;
import '../../models/project_background.dart';
import '../canvas/stage_planes_painter.dart';
import '../effective_device_pixel_ratio.dart';
import '../sliced_value_listenable_builder.dart';
import '../theme/app_theme.dart';
import '../../models/app_workspace_colors.dart';
import '../widgets/color_swatch_button.dart';
import '../../services/brush_poised_tip.dart';
import 'brush_cursor_geometry.dart' show brushCursorShape;
import 'brush_cursor_painter.dart' show brushCursorLook, crosshairCursorLook;
import 'drawing_cursor.dart';
import 'eyedropper_swatch_painter.dart' show eyedropperSwatchLook;
import 'tool_cursor_look.dart';
import 'tool_cursor_sprite.dart';
import '../canvas/interactive_brush_edit_canvas_view.dart';
import '../canvas/selection_drag.dart'
    show DrawnShapePath, MarqueeDrag, drawnCopiesOf, guideCarriesOf;
import '../../services/layer_pose_paint.dart';
import '../../services/layer_pose_matrix.dart' show placedRectBounds;
import 'brush_canvas_defaults.dart';
import 'brush_tool_state.dart';
import '../../core/dev_profile.dart';
import 'canvas_selection_commands.dart';
import 'cel_text_commands.dart';
import 'text_tool_options.dart';
import 'transform_tool_options.dart';
import '../canvas/text/cel_text_stage.dart';
import '../canvas/text/cel_text_tool.dart';
import '../canvas/text/cel_text_float.dart';
import '../canvas/text/cel_text_tool_layer.dart';
import 'selection_shape_history_command.dart';
import 'canvas_book.dart';
import 'canvas_view_commands.dart';
import 'canvas_view_limit.dart';
import 'canvas_viewport_pan_metrics.dart';
import 'canvas_visible_rect.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_scrollbar.dart';
import '../canvas/canvas_capsule.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/page_turn_bar.dart';
import '../widgets/tick_layer.dart';
import '../text/readout_text.dart' show columnValueOf, readoutText;
import '../widgets/panel_flyout.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../text/app_strings.dart';
import '../text/text_measure.dart';
import '../listenable_rebind.dart';
import '../input/hit_gate.dart';
import '../input/value_control_pointers.dart';
import '../canvas/canvas_viewport_offset.dart';

part 'canvas_panel/canvas_panel_shell_bars.dart';
part 'canvas_panel/canvas_panel_selection.dart';
part 'canvas_panel/canvas_panel_tool_cursor.dart';
part 'canvas_panel/canvas_panel_tap.dart';
part 'canvas_panel/canvas_panel_lift.dart';
part 'canvas_panel/canvas_panel_mapped_buttons.dart';
part 'canvas_panel/canvas_panel_text.dart';
part 'canvas_panel/canvas_panel_line.dart';
part 'canvas_panel/canvas_panel_book.dart';
part 'canvas_panel/canvas_panel_viewport.dart';
part 'canvas_panel/viewport_bottom_bar_build.dart';
part 'canvas_panel/canvas_panel_build.dart';
part 'canvas_panel/canvas_panel_control_holds.dart';

/// What the row being drawn on shows its cel through, as a painter made
/// for the cel holds it: its colour keys' values, and the plugin its chain
/// runs ([celSourcePlugin]) — a plugin's picture moves with its frame and
/// the rows it reads, none of which changes the cel.
typedef _ShownThrough = ({String keys, ResolvedLayerEffect? plugin});

/// A reframe request for [BrushCanvasPanel.autoFrame]: whenever [token]
/// changes between widget updates the panel fits the viewport around
/// [rect] (canvas space) — the media viewer's framing of a document it
/// opens — or, given a [view], stands there instead.
class CanvasAutoFrameRequest {
  const CanvasAutoFrameRequest({
    required this.token,
    required this.rect,
    this.view,
  });

  final Object token;
  final Rect rect;

  /// The view the owner kept for this document, in DEVICE pixels as the
  /// owner's notifier holds it (F-382: the view a viewer left a file at).
  /// In a book it stands at the page the reader is on: a page turned since
  /// the view was kept is a turn, at the zoom the view was kept at.
  final CanvasViewport? view;
}

/// What stands under a canvas panel whose document you move through — the
/// transport's rows under one that runs in time, the page turner under a
/// book ([BrushCanvasPanel.transport]).
///
/// The [height] travels with the widget because the panel has to know it
/// without laying anything out: its lanes stand on the band, and nothing it
/// frames may lie under it.
class CanvasTransportBand {
  const CanvasTransportBand({required this.height, required this.child});

  /// The band under a BOOK, [page] the page it stands on: its page turner
  /// ([PageTurnBar], F-383). None below two pages — 유저 확정 ⑥ (2026-08-13)
  /// is about a page turner that could never turn: 「a still image gets no
  /// strip rather than a permanently disabled one」.
  static CanvasTransportBand? ofPages(
    BuildContext context, {
    required String keyPrefix,
    required TurnedPage page,
    required ValueChanged<int>? onTurnTo,
  }) => page.count <= 1
      ? null
      : CanvasTransportBand(
          height: PageTurnBar.heightIn(context),
          child: PageTurnBar(
            keyPrefix: keyPrefix,
            page: page,
            onTurnTo: onTurnTo,
          ),
        );

  final double height;
  final Widget child;
}

/// What stands on a canvas panel's LEFT edge, in the middle of the room
/// there ([BrushCanvasPanel.leftPill]) — the brush's values on the
/// drawing (I-34).
///
/// The [width] travels with the widget for [CanvasTransportBand.height]'s
/// reason: nothing the panel frames may lie under it, and framing is read
/// before anything is laid out.
class CanvasEdgePill {
  const CanvasEdgePill({required this.width, required this.child});

  final double width;
  final Widget child;
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
      CanvasFloats floats,
    );

/// What floats on the canvas while a box is open, for the composite to draw
/// where each belongs: the float of the row this canvas edits, in that
/// row's slot (`LiveRows.floatOverlay`) — and the cels a lift holds beside
/// it, a folder's rows or a range's, each in its own row
/// (`LiveRows.liftedRows`, I-37 · F-329).
typedef CanvasFloats = ({
  SelectionFloatOverlay liveRow,
  Map<BrushFrameKey, LiftedCel> liftedRows,
});

class BrushCanvasPanel extends StatefulWidget {
  const BrushCanvasPanel({
    super.key,
    required this.coordinator,
    this.celEditable = true,
    this.rowAcceptsStrokes = true,
    this.transformTargetKeys,
    this.cellPlacementOf,
    this.transformCelsUnderfoot,
    this.pieceGround,
    required this.availableFrameKeys,
    required this.cacheInvalidationSink,
    this.canvasSize = BrushCanvasDefaults.canvasSize,
    this.guides,
    this.brushToolState,
    this.historyManager,
    this.takeStrokePrefixCommand,
    this.onPressNeedsCel,
    this.markMakesItsOwnCel,
    this.onStrokeNeedsCel,
    this.onAutoFrameSettled,
    this.viewport,
    this.viewportController,
    this.onViewportChanged,
    this.viewportOverlayBuilder,
    this.viewportControlsBuilder,
    this.viewportUnderlayBuilder,
    this.activeStrokeOverlayModel,
    this.interactiveContentOpacity = 1.0,
    this.interactiveContentPose,
    this.activeSourceEffects = const <ResolvedLayerEffect>[],
    this.contentOverride,
    this.contentShapeTargetAt,
    this.contentTakesPressAt,
    this.fitFocusRect,
    this.floorCover = EdgeInsets.zero,
    this.floorLeftRailBand,
    this.floorRightRailBand,
    this.floorBottomOverlaySpan = 0,
    this.autoFrame,
    this.unframedFit,
    this.viewLimit,
    this.book,
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
    this.onPasteboardSizeChanged,
    this.onPasteboardInUseChanged,
    this.canvasBase = false,
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
    this.onCutContent,
    this.oneFingerAction,
    this.runsTheSelectedTool = true,
    this.onStrokeInputActiveChanged,
    this.strokeLander,
    this.onSelectionInteractionChanged,
    this.allowViewRotation = true,
    this.toolCursorsEnabled = true,
    this.toolInputEnabled = true,
    this.hasContentToView = true,
    this.oneToOneOnPill = false,
    this.bottomBarLeading = const <Widget>[],
    this.bottomBarSettings = const <PanelFlyoutEntry>[],
    this.transport,
    this.leftPill,
    this.documentName,
    this.documentAbsent = false,
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

  /// 🚨★★★**WHICH CELS A CONFIRM LANDS ON** — the frame range's whole
  /// block, or just the cel you stand on.
  ///
  /// 🗣️유저 2026-09-17: 「몇 행에 걸쳐서 적용하던 **동시적용은 가능하게**.
  /// **적용시만 각 행에 따라 불가능하면 그냥 무시**하는방식」 · 2026-09-18:
  /// 「**여러프레임 확정가능**하게한다던가」. Rows and frames are ONE law and
  /// the session already writes it — `PixelVerbs.pixelVerbCellKeys`, which
  /// skips a hidden row, an empty cel or a row that takes no brush.
  ///
  /// ⛔A FUNCTION, not a list: the range changes under this panel, and a
  /// list would be the state as it stood when the panel was built.
  ///
  /// ⚠️Null = the cel you stand on, which is also what the ladder answers
  /// with no range live. That is why there is no 「여러 개일 때만」 branch
  /// anywhere below: the many-cel path IS the one-cel path. Hosts with no
  /// cel ladder at all (the viewer, the sheet) simply pass nothing.
  final List<BrushFrameKey> Function()? transformTargetKeys;

  /// Where each cel of [transformTargetKeys] stands on the canvas — its
  /// row's placement, the one the pixel verbs restate an outline through
  /// (`PixelVerbs.placementOf`). A range over several rows lands each cel
  /// through its OWN row's placement (a-marquee-on-a-posed-row ④).
  ///
  /// ⚠️Null (a host with no rows behind it — the focused tests) crosses
  /// every cel through the standing row's, the one the lift crossed.
  final LayerPlacement? Function(BrushFrameKey key)? cellPlacementOf;

  /// What a transform takes up where you stand: every cel its confirm lands
  /// on that shows at the playhead — a FOLDER's rows, a frame RANGE's rows —
  /// each marked `live` when it is the cel this canvas edits
  /// (`PixelVerbs.transformCelsUnderfoot`). Null when that cel is all there
  /// is, and a lift takes up the cel this canvas edits.
  ///
  /// 🗣️유저 2026-10-02 (I-37): 「폴더 전체를 하나로 들도록」 · F-329 (10-10):
  /// 「변형중에도 라이브로 선택된 다른행의 프레임도 변형중인거 보이도록」.
  /// ⛔A FUNCTION, not a list, for [transformTargetKeys]'s reason: the
  /// playhead and the rows change under this panel.
  final List<({BrushFrameKey key, bool live})>? Function()?
  transformCelsUnderfoot;

  /// 🚨★★★**WHERE THE CUT TOOL'S STAMP LANDS** — the ground 픽셀 붙여넣기
  /// lands on, read by the session that reads it for the paste
  /// (`PixelVerbs.pieceGround`): the cels the ladder names, each row's
  /// placement, the selection and its softness.
  ///
  /// 🗣️F-293 (유저 2026-10-05): 「잘라내기도구의 스탬프, 여러 프레임 선택해서
  /// 여러프레임 붙여넣을수있도록. **색편집의 픽셀붙여넣기랑 법 통일**」.
  ///
  /// ⛔The WHOLE ground, not its cels alone ([transformTargetKeys] hands the
  /// transform a list and the panel reads the rest itself): the stamp and
  /// the paste are one verb held by two buttons, and four facts assembled in
  /// two places is how one range comes to mean two sets of cels.
  ///
  /// ⚠️Null (a host with no session behind it — the focused tests) lands on
  /// the cel you stand on, through what this panel holds
  /// ([_BrushCanvasPanelState._pieceGround]).
  final PieceGround Function()? pieceGround;
  final List<BrushFrameKey> availableFrameKeys;
  final CacheInvalidationSink cacheInvalidationSink;
  final CanvasSize canvasSize;

  /// The active cut's drawing guides, in CANVAS space. Null (the default)
  /// draws with none — the hosts that embed this panel without a cut behind
  /// it pass nothing.
  final CutGuides? guides;

  /// The brush in hand as the workspace holds it — HEARD, not handed over
  /// (H40 ②, 2026-09-24).
  ///
  /// A value here rebuilt this panel on every brush change — each preset
  /// pick, each frame of a settings slider drag, each colour notch — and a
  /// rebuild relays out the shell's `LayoutBuilder`s, so the pill, both
  /// panbars and the edges repainted for numbers they do not show. The
  /// panel now rebuilds for what changes its own tree (the tool and its
  /// shape), the brush cursor listens for its own footprint, and every verb
  /// reads the brush at the moment it acts.
  ///
  /// Null holds no tool of the workspace's: the panel runs
  /// [BrushToolState.defaults].
  final ValueListenable<BrushToolState>? brushToolState;

  /// What of the brush a canvas builds its TREE from: the tool (which
  /// cursors are mounted, which verb a press runs, whether the guide handles
  /// are up) and the selection tools' shape. The ONE answer — this panel
  /// and the host above it rebuild on it and on nothing else of the brush.
  static (CanvasTool, CanvasShapeKind?) structureOf(BrushToolState brush) =>
      (brush.tool, brush.activeShapeKind);
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

  /// I-113: whether a mark pressed now makes a cel of its own although one
  /// stands under the playhead — see
  /// [InteractiveBrushEditCanvasView.markMakesItsOwnCel], which is where it
  /// goes; the layers over the view ask it in the view's stead
  /// ([_BrushCanvasPanelState._markDoorOverTheView]).
  final bool Function()? markMakesItsOwnCel;

  /// The same answer for a stroke whatever tool is up — the door 확정's
  /// 재입력 takes on an empty cell (`MainCanvasBrushHost.onStrokeNeedsCel`).
  final bool Function()? onStrokeNeedsCel;

  /// Settles a block [onStrokeNeedsCel] made that no stroke claimed —
  /// the tool's entrance does it at a press's end (I-10,
  /// `_PanelBuild._toolEntrance`).
  final VoidCallback? onAutoFrameSettled;

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
  /// sheet-mode toggles, the conte's, the envelope's.
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

  /// What moves you through the document, under the horizontal panbar — a
  /// docked panel's band below its lanes, the floor's capsule below its
  /// bar: the transport of one that RUNS IN TIME, the page turner of a book
  /// ([CanvasTransportBand.ofPages]).
  ///
  /// 🗣️F-289 (유저 2026-10-06): 「왼쪽알약말고 제대로 뷰어패널의 가로스크롤바
  /// 아래에 재생버튼같은거 일반적인 미디어플레이어같은거 만들고싶어」, and
  /// then how a panel knows which it wears: 「이 캔버스 베이스패널은 형식에
  /// 따라 나누기로하자. 뷰어패널이라도 pdf면 타임시트나 콘티용지패널이랑 같은
  /// 알약쓰고, 한장짜리면 그 알약조차 없애고, 동영상같은거면 아래에 재생ui
  /// 넣고」. So a panel wears what its DOCUMENT is, and the host says which
  /// by what it hands over: the transport for one that runs, the turner for
  /// one that turns pages, nothing for a single picture.
  ///
  /// 🗣️F-383 (유저 2026-10-17): the turner stands here too — 「밑에
  /// 알약말고 비디오파일일때 처럼 공간만들고 거기다 기존 버튼 배치」. ↩️It
  /// stood in a capsule of its own on the LEFT edge (유저 확정 2026-08-13 ⑥:
  /// 페이지 넘기기는 왼쪽 세로, 그리고 필요한 파일에서만), out of the pill whose
  /// largest tenant it had been.
  ///
  /// It hides the artwork as a lane does, so framing keeps out from under
  /// it (`_framingInsets`).
  final CanvasTransportBand? transport;

  /// What stands on the LEFT edge: the brush's values on the drawing panel
  /// (I-34, 유저 2026-10-18: 「캔버스 패널의 왼쪽 중앙 알약 만들어서 거기로
  /// 이동」). Null stands nothing there.
  ///
  /// It is seated as the page strip that stood on this edge was
  /// ([_LeftEdgeSeat]): in the middle of the room between the pill's band
  /// and the file's name, and past the left rail where the rail is beside
  /// it. It is cover to framing as that strip was (F-346).
  final CanvasEdgePill? leftPill;

  /// The name of the FILE shown, written at the artwork's lower left over
  /// the horizontal panbar. Null writes nothing.
  ///
  /// 🗣️F-289 (유저 2026-10-06), choosing the place: 「그냥 제안한대로
  /// 동영상뷰어던 뭐던 해당 위치 고정으로 두자」 — one place whatever the
  /// document is — and which panels have one: 「타임시트패널/콘티패널에는
  /// 파일이름 의미없으니까 없도록. 컷봉투패널도 똑같음」. A paper panel shows
  /// no file, so it hands none.
  final String? documentName;

  /// Whether [documentName] names something that is NOT a file — the export
  /// window's picture of a drawing its run does not write (drawn so in the
  /// F-289 mock: the name stays in its place, in the ink of what is off).
  final bool documentAbsent;

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

  /// Optional CONTROLS stacked over every tool layer — the standing row's
  /// transform box (F-222). On top, so a press that lands on one of them is
  /// its own whatever tool is armed (「컨트롤 위에서 시작한 제스처는 그
  /// 컨트롤의 것이다」), and it says which presses those are: a press it does
  /// not claim falls to the tool beneath.
  final Widget Function(BuildContext context, CanvasViewport viewport)?
  viewportControlsBuilder;

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
  /// fresh instance per call and the stack's `shouldRepaint` compared the
  /// field with `!identical(...)` (↩️as `FramePictureView`'s live rows are
  /// compared now, `_sameLive`), so the comparison could never answer false
  /// and every rebuild of this panel re-composited the whole stack.
  ({BitmapSurface surface, BrushFrameKey key, _ShownThrough fx})?
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
      fx: (
        keys: celSourceEffectSignature(activeSourceEffects).join(','),
        plugin: celSourcePlugin(activeSourceEffects),
      ),
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

  /// Replaces the interactive canvas INSIDE the panel shell (title, zoom
  /// toolbar and panbars keep working) — playback and the blank-canvas
  /// placeholder render through this. Receives the live viewport.
  final Widget Function(BuildContext context, CanvasViewport viewport)?
  contentOverride;

  /// The view a shape tool's press at [global] (a point on the screen)
  /// lands its shape in, where [contentOverride] is not one cel — a
  /// sheet's window (F-420): the shape is the same drag and the same
  /// landing as on the canvas, on the cel that content draws there. Null
  /// at a point where nothing takes it — the press then traces nothing.
  final ContentShapeTarget? Function(Offset global)? contentShapeTargetAt;

  /// Whether a press at [global] is [contentOverride]'s own before any
  /// tool's — a sheet's photo (I-97-Q3: 「브러시 허용이면 어느 도구든 사진을
  /// 누르면 집는다」). The tool's layer over the content is not hit there.
  final bool Function(Offset global)? contentTakesPressAt;

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
  /// The PANELS only. This panel's own capsules are added where framing
  /// reads the window (`_framingInsets`): the pill, the transport and the
  /// left pill are cover there, the panbars float on the drawing.
  /// ↩️None was until 2026-09-30 — a capsule hiding a corner of the artwork
  /// was the price of not spending a strip of the screen on idle chrome.
  /// The user took that back for the pill (「판정을 알약까지 포함해서
  /// 판정」, [_CanvasEditorPanelShell.pillBandIn]) and then for the page
  /// strip that stood on the left edge (F-346).
  final EdgeInsets floorCover;

  /// WHERE the rail on each side edge actually is, vertically — null when
  /// nothing is open there.
  ///
  /// [floorCover] says how much of the edge is unusable, which is the right
  /// question for FRAMING and the wrong one for the control that lives on
  /// that edge — the vertical panbar on the right, the [leftPill] on the
  /// left: a short rail panel covers a band, and a control that steps aside
  /// for a panel nowhere near it reads as floating (유저, R3 #5).
  /// ↩️The left rail's band was asked for the page strip on that edge, gone
  /// with the strip under the bars (F-383), and asked again for the brush
  /// pill there (I-34).
  final CanvasFloorBand? floorLeftRailBand;

  /// See [floorLeftRailBand].
  final CanvasFloorBand? floorRightRailBand;

  /// ⑩: what floats over the floor's BOTTOM edge without framing the
  /// artwork — the collapsed row. The horizontal panbar steps up by it, and
  /// nothing else does, because nothing else was being buried.
  final double floorBottomOverlaySpan;

  /// Host-driven reframing: when the request's token changes between
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

  /// THE VIEW'S LIMIT (canvas space) — the paper the view stops at; null
  /// for a canvas that pans freely, which is the drawing canvas.
  ///
  /// 🗣️F-201 (유저 2026-09-27): 「스크롤 최대치가 너무 커서? 그림이 밖으로
  /// 빠져나가는데 좀 줄여서 … 다른 미디어 뷰어 프로그램이 그러니까」,
  /// answered `edge` (F-201-pan-limit-Q1: 「끝이 화면 가장자리에 딱
  /// 닿는다」) — see [viewHeldTo] for the law.
  ///
  /// 🎯**Held in the one store, not at each road.** A drag, a pinch, the
  /// wheel, a pan bar, a pill press, a fit, an owner's write — every road
  /// that moves the view ends in `_CanvasPanelViewport`, so it is held
  /// there: the read shows the view held in the window you look through,
  /// the write stores it held, and a write that came from outside (the
  /// owner's) or a window or a limit that changed under a stored view is
  /// put back the same way. The pan bars span the limit and nothing past
  /// it.
  final Rect? viewLimit;

  /// THE BOOK — this canvas's pages laid one under another, and the page
  /// its reader is on (F-201); null for a canvas without pages. Writing
  /// the reader's page turns to it, the view moving there; the panel
  /// writes it back as the view leaves it (`_CanvasPanelBook`), and Fit
  /// frames it when no [fitFocusRect] is given.
  final CanvasBook? book;

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

  /// Sets the pasteboard's size and whether it is there (I-109) — the two
  /// the pasteboard's colour window carries. Their values come from the
  /// scope ([CanvasStageColors]).
  final ValueChanged<PasteboardSize>? onPasteboardSizeChanged;
  final ValueChanged<bool>? onPasteboardInUseChanged;

  /// Whether this is a CANVAS-BASE panel — a sheet, the viewer, the cut
  /// envelope, the export preview: a page shown on the canvas panel, not
  /// the drawing floor. Its stage is not the drawing's room:
  ///
  /// - it has NO PASTEBOARD plane (유저 2026-09-25, F-179: 「타임시트패널등
  ///   캔버스 베이스 패널엔 페이스트보드가 없다는 뜻임」) — its paper is a
  ///   printed page, not a canvas with a drawing bound around it;
  /// - its backdrop is BLACK, whatever the project's is (유저 2026-10-03,
  ///   F-272: 「캔버스 베이스 패널들은 배경색 캔버스의 배경색 따라가는데, 그냥
  ///   검정색 고정/통일」). ↩️It reverses F-179's other half, 「배경색은 캔버스
  ///   패널의 배경색 따라가도록」, and R4 #2 before it.
  ///
  /// ONE flag for the two: both are said of the same panels, and a panel
  /// with its pasteboard off that still followed the project's backdrop is
  /// the very state F-272 was about.
  ///
  /// ⛔Not [pasteboardNone]: that one is the plane being ABSENT, which shows
  /// the checkerboard where it would be. A sheet has no such plane to be
  /// absent.
  final bool canvasBase;

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

  /// Builds the fill region's stamp pieces for a tap (P6); the panel
  /// commits them through the exact stroke funnel. Null disables the fill
  /// tool.
  final List<BrushDab> Function(
    CanvasPoint point,
    int color,
    SymmetryShape? symmetry,
  )?
  fillDabsAt;

  /// Builds the stamp pieces of a finished SHAPE FILL — the AREA it fills,
  /// its outline and every copy a guide made of it together. Supplied by
  /// the host for the same reason [fillDabsAt] is — the fill's knobs live
  /// up there, and the panel commits whatever comes back. Null disables
  /// the shape fill.
  final List<BrushDab> Function(CanvasSelectionRegion area, int color)?
  shapeFillDabsFor;

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

  /// The app-level text channel (R9-rest): the panel binds the hand it
  /// holds texts with, so the tool settings and the keys reach the text on
  /// the canvas. Null in a host that is not the app's canvas.
  final CelTextCommands? textCommands;

  /// What the next text set with the text tool starts as — and what setting
  /// a text leaves it as ([CelTextToolHost.options]). Null keeps the
  /// defaults.
  final ValueNotifier<TextToolOptions>? textToolOptions;

  /// Where a finished cut lands. Null in hosts that do not offer the tool
  /// (the cut variants are then inert rather than crashing).
  final CutPieceSlot? cutPieceSlot;

  /// The last drawing action: every stroke this canvas lands is held here,
  /// and 확정 lays it down again through the same funnel. Null in hosts
  /// that are not the cut's canvas — 재입력 lays on 「지금 레이어·지금
  /// 프레임」, which only that canvas has.
  final LastStrokeSlot? lastStroke;

  /// A finished cut outline — with every copy a symmetry guide made of it,
  /// as one region ([CanvasSelectionLayer.onCutOutline]) — for a host whose
  /// content is not a cel ([contentOverride]): the host lifts the piece from
  /// what it SHOWS. Null = the cut reads the active cel into [cutPieceSlot].
  ///
  /// 🗣️I-14 (유저 2026-09-11): 「뷰어패널의 잘라내기툴 사용 가능하도록」 —
  /// the media viewer answers it, at the page's own size.
  final ValueChanged<CanvasSelectionRegion>? onCutContent;

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

  /// Stroke lifecycle for the host (R13-3): the stroke at pen-down,
  /// [StrokeInFlight.none] at stroke end/cancel — the session holds
  /// prerender warming while a stroke is live, and counts the cel a
  /// painting stroke draws as drawn (F-482).
  final ValueChanged<StrokeInFlight>? onStrokeInputActiveChanged;

  /// Where this panel holds up what a save lands first while it is
  /// mounted — the stroke its view's pen is in and the text in hand
  /// ([_landWorkInFlight]); see
  /// [InteractiveBrushEditCanvasView.strokeLander].
  final ViewHand<StrokeLander>? strokeLander;

  /// Selection-drag lifecycle for the host: the session holds prerender
  /// warming while it is live, as it does for a stroke. ↩️F-196: it also
  /// blocked frame seeks and cut switches (R15-⑤) — only a stroke does now.
  final ValueChanged<bool>? onSelectionInteractionChanged;

  /// False hides the rotate/flip toolbar controls and disables the
  /// rotation gestures — for hosts whose content layers speak zoom/pan
  /// only (the timesheet's ink and header-edit overlays).
  final bool allowViewRotation;

  /// False suppresses the marking tools' cursors (the drawing cursor, the
  /// fill's bucket, the text tool's caret) where the content under them
  /// cannot be drawn on — a
  /// paint cursor there is a false affordance: a strictly read-only host
  /// (the media viewer), and on the drawing canvas a row that is no drawing
  /// surface (the camera, a property lane, a data or reference row).
  ///
  /// 🗣️F-285 (유저 2026-10-17): 「카메라 레이어에선 그냥 기본커서로. 이런식으로
  /// 도구가 연관이 없는 곳에선 기본커서」 — the system's default stands there.
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

  /// Whether the pill keeps its 1:1 out where it is seen, as the floor's
  /// does — folded only for room — instead of behind the gear.
  ///
  /// 🗣️F-315 (유저 2026-10-08): 「뷰어패널에 1:1 보기버튼 넣고, 그거 동일하게
  /// 다른 임포트/익스포트창에서도 뷰어패널 기반으로 쓰고있으니 법 통일해서
  /// 적용되도록」 — the panels that show a FILE, where a pixel of it is what
  /// is looked at: the viewer and the export window's preview.
  final bool oneToOneOnPill;

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

  // The book (F-201): the page its reader is on, kept true to the view.
  late final _CanvasPanelBook _bookState = _CanvasPanelBook(this);

  /// The brush stroke in progress, if any; while one is, the viewport
  /// gesture layer ignores wheel zooms and new pans so they cannot disturb
  /// the stroke.
  StrokeInFlight _stroke = StrokeInFlight.none;

  bool get _strokeActive => _stroke != StrokeInFlight.none;

  /// True while a selection marquee/move drag is in progress (P9) — holds
  /// viewport gestures exactly like a stroke.
  bool _selectionDragActive = false;

  /// True while a drag that takes a finger as its MODIFIER is in progress
  /// — a transform handle's, a shape being drawn. Narrower than
  /// [_selectionDragActive] on purpose: it is the only state in which
  /// touch is locked out of the viewport as well.
  bool _modifierTouchDragActive = false;

  /// True while the text tool follows a press — a text moved, sized or
  /// turned, letters selected, a box traced: the viewport's gestures hold
  /// as they do for a stroke.
  bool _textDragActive = false;

  CanvasAutoFrameRequest? _pendingAutoFrame;


  /// The AIM: the pointer's panel-local position, for every tool cursor —
  /// the brush ring, the bucket, the dropper and its swatch, the stamp's
  /// ghost. One writer (the census), every cursor a reader.
  ///
  /// The eyedropper used to have a second notifier beside this one, holding
  /// the position AND the colour sampled under it on every pointer event.
  /// F-130 retired it: the swatch reads this aim and samples in its own
  /// `paint`, once per frame (`eyedropper_swatch_painter.dart`).
  final ValueNotifier<_Aim?> _toolCursorHover = ValueNotifier<_Aim?>(null);

  /// How the pen at the aim is held — its lean and its twist — for the brush
  /// outline, which shows the tip that pose lays down (F-176-Q7, 유저
  /// 2026-10-21 「펜을 따라 바뀐다」). Written beside the aim by the same
  /// census, from the same event; a mouse writes no pose.
  final ValueNotifier<PenPose> _penPose = ValueNotifier<PenPose>((
    lean: null,
    twist: null,
  ));

  /// 🚨★★★F-33: the stamp's AIM — what a click there would press — which
  /// the ghost is laid from ([_showStampGhost]). A notifier, so a hover
  /// re-lays the ghost without rebuilding the panel.
  ///
  /// ↩️It was what the surface painter drew as the ghost — a listenable so a
  /// hover repainted the painter instead of making a new one per position
  /// ([_activeSurfacePainter]'s token) — holding an image borrowed from the
  /// piece, until brush-fidelity-Q9 (유저 2026-10-18 「통일하면 좋음」) moved
  /// the stamp ghost to the overlay's CPU pre-blended tiles.
  final ValueNotifier<CutStampPreview?> _stampPreview =
      ValueNotifier<CutStampPreview?>(null);

  /// TS1: the channel the selection layer publishes its FLOAT on, and the
  /// composite underlay reads. Owned here because it outlives both — the
  /// selection layer is mounted and unmounted by tool changes, and the
  /// underlay is rebuilt by the host.
  final SelectionFloatOverlay _selectionFloat = SelectionFloatOverlay(null);

  /// Where a float lifted off the active row shows ([LiftedFloat.showsOn]):
  /// with a composite behind this canvas it goes into it, at that row's
  /// depth; without one the selection layer draws it itself.
  SelectionFloatOverlay? get _activeRowFloatSlot =>
      widget.viewportUnderlayBuilder == null ? null : _selectionFloat;

  /// R28-S: the dash phase for the ants the panel paints when NO selection
  /// layer is mounted — the region belongs to the document, so it keeps
  /// showing while the brush/eraser/fill is armed (R26 #18).
  late final AnimationController _idleAnts = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  /// The stage's outer surfaces, RESOLVED: this panel's own parameters when
  /// it was given them, otherwise the shell's [CanvasStageColors] — and
  /// black on a [BrushCanvasPanel.canvasBase] panel, whatever either says.
  ///
  /// Resolved into fields rather than read at each use, because the reads
  /// happen inside memo builders called from `build` and one of them
  /// (`didUpdateWidget`) runs outside it — a scope lookup wants a lifecycle
  /// hook, not an arbitrary call site.
  late int _stageBackdropArgb;
  late int _stagePasteboardArgb;
  late bool _stageBackdropNone;
  late bool _stagePasteboardNone;
  late PasteboardSize _stagePasteboardSize;
  late bool _stagePasteboardInUse;

  /// How far the pasteboard reaches past the paper (I-109).
  PasteboardReach get _stagePasteboardReach => PasteboardReach.of(
    size: _stagePasteboardSize,
    inUse: _stagePasteboardInUse,
  );

  /// The wall of the canvas this panel edits — what its tools keep to.
  PasteboardWall get _stagePasteboard =>
      widget.canvasSize.pasteboardAt(_stagePasteboardReach);

  /// Whether this panel is the one LYING ON THE FLOOR — which decides
  /// whether its pill lays its whole vocabulary out or keeps it folded
  /// behind the gear (유저 확정 2026-08-13: 「바닥 둘만」).
  ///
  /// Read from the tree rather than taken as a parameter, for the reason
  /// [CanvasFloorInsets] was built on: five hosts mount this panel and the
  /// question is about WHERE, not about who mounted it.
  late bool _onFloor;

  /// How thick this panel's bars are — the panbars and any bar inside it,
  /// which the panel tells through [AppScrollbarLaneScope].
  ///
  /// 🗣️F-440 (유저 2026-10-23): 「뒷 배경에 깔리는 패널만 두꺼운 스크롤바
  /// 사용. 나중에 콘티용지패널을 뒤에 깔수있게 할거기 때문에 입구를
  /// 그런식으로 설계」 — so the answer is the FLOOR's ([_onFloor]): whatever
  /// panel lies there takes the thick bar, and the same panel docked takes
  /// the lane its seat gives (the thin one, outside any scope). ⛔Not a
  /// second scope at the workspace's floor: the floor would then be said
  /// twice, and a floor stood up without one would draw the thin bar.
  late double _lane;

  /// The MERGED-mode surface painter, kept ALIVE across rebuilds.
  ///
  /// 🐛It was rebuilt on every call, and the stack gated its entire
  /// composite on `!identical(oldDelegate.activeSurfacePainter,
  /// activeSurfacePainter)` — as `FramePictureView` now stands its live rows
  /// again on the same test (`_sameLive`). A fresh instance every build makes
  /// that test unconditionally true, so ANY rebuild of this panel — a pan
  /// frame, a
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
  ({BitmapSurface surface, BrushFrameKey key, _ShownThrough fx})?
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
      _text.floatOver(null);
      ShownCels.instance.hide(this);
      return null;
    }
    // The overlay shows its pictures in place of this painter's tiles, so
    // through the chain they are shown through below.
    overlay.sourceEffects = widget.activeSourceEffects;
    final identity = widget._activeSurfaceIdentityFor(coordinator);
    // 🚨★★★**AN OPEN MOVE SESSION IS PART OF WHAT THIS PAINTER DRAWS**, so
    // it is part of the token: the hole is a derived surface the session
    // holds, and opening or closing one has to drop the memo exactly as a
    // commit does. ⛔Substituting it AFTER the comparison would serve the
    // cel's own pixels for one more frame — the flash 유저 named as the
    // absolute condition of this round: 「조작 전/중/후가 빈 프레임
    // 존재안하고 눈에 보이는 결과가 달라지지 않는건 절대조건」.
    //
    // ⛔And only the interactive painter reads it. The cel itself is
    // untouched, so every other surface that shows this drawing — the
    // timeline's thumbnail, the storyboard, playback, a neighbour's onion
    // skin — keeps showing the picture as it stands, which is what an
    // uncommitted edit should look like from outside the tool.
    //
    // 🚨AND SO IS A TEXT THE TEXT TOOL HOLDS (R9-rest): the cel with that
    // text laid in as it is shown — typed, dragged or set differently, and
    // not on its cel until it lands (`CelTextSession`). The two never meet:
    // each is its own tool's, and another tool in hand lands either.
    final held = identity == null
        ? null
        : _lift.holedSurfaceFor(identity.key) ??
              _text.shownSurfaceFor(identity.key, identity.surface);
    // F-344: what floats over the text tool's hole, made for the cel this
    // painter draws.
    _text.floatOver(identity);
    final token = identity == null || held == null
        ? identity
        : (surface: held, key: identity.key, fx: identity.fx);
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
    // The canvas says which cel it is drawing, and THROUGH what: the texts
    // laid over it and the colour keys make the tiles it paints other
    // objects than the cel's own, so a picture made ahead for the cel's own
    // would go unused.
    ShownCels.instance.show(
      this,
      (token.key.layerId, token.key.frameId),
      painted: (surface) =>
          celSurfaceAsShown(surface, widget.activeSourceEffects),
    );
    return _memoActiveSurfacePainter = BitmapSurfacePainter(
      // ★DRAWN THROUGH THE SEAM — the texts laid, then the keys. Both are
      // cached per TILE, so a dab re-lays and re-keys the one tile it
      // changed and the rest of the cel answers from memory.
      surface: celSurfaceAsShown(token.surface, widget.activeSourceEffects),
      overlayModel: overlay,
      // The stack painter applies the viewport itself, so the surface
      // painter draws in canvas space.
      showTransparentBackground: false,
      lineage: (token.key.layerId, token.key.frameId),
      landingPreview: _text.float,
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

  /// The brush in hand NOW — see [BrushCanvasPanel.brushToolState].
  BrushToolState get _brush =>
      widget.brushToolState?.value ?? BrushToolState.defaults;

  /// The brush as a stroke, a fill or a pressure curve reads it when it
  /// runs — the view's getter, a tear-off of this State.
  BrushEditCanvasInputSettings _inputSettingsNow() => _brush.toInputSettings();

  /// The door a layer over the drawing view asks in the view's stead — the
  /// shape tool's and the text tool's — answering 「go on」: on a frame with
  /// no cel by making one, on a held cel that gives way by making its own
  /// (I-113), and at once on a cel that stays.
  ///
  /// 🚨WHOEVER HEARS THE PRESS ASKS FOR THE CEL, AND ONLY ONE DOES (I-10).
  /// The drawing view stands down in place, or would draw, under a layer
  /// that takes the press. Where a cel IS there and its row takes no marks,
  /// or nothing stands here at all, the tool's entrance speaks
  /// ([_CanvasPanelTap.pressNoLayerHears]) and this is null — a second
  /// question would say it twice.
  bool Function()? get _markDoorOverTheView {
    final door = widget.onPressNeedsCel;
    if (widget.coordinator == null || door == null) {
      return null;
    }
    if (!widget.celEditable) {
      return door;
    }
    final ownCel = widget.markMakesItsOwnCel;
    if (!widget.rowAcceptsStrokes || ownCel == null) {
      return null;
    }
    return () => !ownCel() || door();
  }

  /// The structure the last build was made for — see
  /// [BrushCanvasPanel.structureOf].
  ///
  /// ⚠️Taken in [initState], not by a lazy initializer: the first read is
  /// the first CHANGE, and a lazy one would take the new brush as the old.
  late (CanvasTool, CanvasShapeKind?) _builtFor;

  /// A brush change reaches the tree only when the tool or its shape moved.
  void _handleBrushChanged() {
    // The line from the last stroke is the painting tools' (I-119): it goes
    // with them, and comes back with them while its key is held.
    _line.refresh();
    if (_followStructure() && mounted) {
      setState(() {});
    }
  }

  /// Whether the tool or its shape moved since the last build — and if so,
  /// cancels the polygon being traced.
  ///
  /// 유저 확정: an open polygon trace survives a frame change and a CUT
  /// change, but putting the TOOL or the SHAPE down cancels it.
  ///
  /// Watched here rather than in the selection layer, which is where the
  /// trace is drawn: that layer does not mount for the painting tools, so
  /// on "polygon half-drawn, user picks the brush" it is being disposed
  /// rather than updated and a check inside it never runs.
  bool _followStructure() {
    final structure = BrushCanvasPanel.structureOf(_brush);
    if (structure == _builtFor) {
      return false;
    }
    _builtFor = structure;
    widget.selectionCommands?.abandonPolygon();
    return true;
  }

  @override
  void initState() {
    super.initState();
    _saveKeeper?.up(_landWorkInFlight);
    _viewportState.bindViewCommands();
    _hearTheHand();
    _stampPreview.addListener(_showStampGhost);
    // The softness is read where it is used, so nothing rebuilds this panel
    // when it moves — the one thing the ghost is made of that it has to
    // hear for itself ([_askTheGhostAgain]).
    widget.selectionMaskOptions?.addListener(_askTheGhostAgain);
    CanvasViewHold.held.addListener(_onViewHoldChanged);
    _line.bind();
    _viewportState._listenedViewport = _viewportState.viewportNotifier
      ..addListener(_viewportState.handleViewportMovedByOwner);
    _bookState.bind();
    widget.selectionCommands?.addListener(_selectionSeat.handleSelectionChannelChanged);
    _text.bind();
    _builtFor = BrushCanvasPanel.structureOf(_brush);
    widget.brushToolState?.addListener(_handleBrushChanged);
    _selectionSeat.bindSelectionHistoryRecorder();
    _bindCutPasteHandler();
    _installedReinputHandler = _reinputLastStroke;
    widget.lastStroke?.reinputHandler = _installedReinputHandler;
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

  /// Held in a field for [_installedCutPasteHandler]'s reason.
  void Function()? _installedReinputHandler;

  CanvasZoomScale get _zoomScale => CanvasZoomScale.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shellBars.readStageColors();
    _onFloor = CanvasFloorInsets.isFloor(context);
    _lane = _onFloor
        ? AppScrollbarLane.thick
        : AppScrollbarLaneScope.of(context);
    _pillBand = _CanvasEditorPanelShell.pillBandIn(context);
    // ⛔Nothing here answers a RATIO change any more, deliberately. Holding
    // the percentage across one used to take a remembered scale, a re-zoom
    // around a chosen anchor, a value held through the build that noticed
    // it, and a post-frame commit to get the write out of that build — and
    // it still only worked while a panel was MOUNTED to run it. Storing the
    // view in device units makes the whole sequence a no-op: see
    // [_viewport].
    //
    // 🆕A lock on zooming in that was set, moved or lifted holds a stored
    // view elsewhere (I-27) — stored after the frame, for the reason a new
    // limit is (`didUpdateWidget`): the owner hears the write, and this is
    // its build.
    final ceiling = CanvasZoomCeiling.of(context);
    if (ceiling != _ceilingHeldTo) {
      _ceilingHeldTo = ceiling;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _viewportState._holdTheStoredView();
        }
      });
    }
  }

  /// The lock the stored view was last held to ([CanvasZoomCeiling]).
  double? _ceilingHeldTo;

  // ── the selection seat: its own object, in its own file ─────────────
  //
  // A collaborator (brush/canvas_panel/canvas_panel_selection.dart, a part of this library).
  // The State keeps the entry points its build tree calls.
  late final _CanvasPanelSelection _selectionSeat = _CanvasPanelSelection(this);

  /// The region this panel last painted ants for — the rebuild guard.
  CanvasSelectionRegion? _paintedIdleRegion;

  /// The selection as the last build handed it to the drawing view, which
  /// clips a stroke to it — so that a region changed since can be told
  /// from one that has not
  /// ([_CanvasPanelSelection.handleSelectionChannelChanged]).
  CanvasSelectionRegion? _strokeClipAsBuilt;

  /// The idle ants animate only when they are the ones on screen: the
  /// mounted selection layer runs its own ticker.
  void _syncIdleAnts() {
    _paintedIdleRegion = _selectionSeat.idleSelectionRegion;
    _runPanelAnts();
  }

  /// The ants this panel paints march while any are on screen — the idle
  /// selection's, or the line from the last stroke's (I-119), which rides
  /// the same phase.
  void _runPanelAnts() {
    final show = _paintedIdleRegion != null || _line.trails.value.isNotEmpty;
    if (show && !_idleAnts.isAnimating) {
      unawaited(_idleAnts.repeat());
    } else if (!show && _idleAnts.isAnimating) {
      _idleAnts.stop();
    }
  }

  @override
  void dispose() {
    _saveKeeper?.down(_landWorkInFlight);
    ShownCels.instance.hide(this);
    // From the REMEMBERED object, for the reason spelled out below about
    // the viewport: the widget's may already point somewhere else.
    _listenedCelPixels?.removeListener(_handleCelPixelsChanged);
    _listenedCelPixels = null;
    _stopHearingTheHand();
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
    // The reader's page is the owner's too, for the same reason.
    _bookState.unbind();
    // A mid-stroke teardown must release the session's warm hold — a
    // leaked hold would gate prerendering forever (and a stroke's would
    // hold the playhead). Same for a mid-drag selection interaction.
    if (_strokeActive) {
      widget.onStrokeInputActiveChanged?.call(StrokeInFlight.none);
    }
    if (_selectionDragActive) {
      widget.onSelectionInteractionChanged?.call(false);
    }
    CanvasViewHold.held.removeListener(_onViewHoldChanged);
    widget.selectionCommands?.removeListener(_selectionSeat.handleSelectionChannelChanged);
    _stopAskingTheGhost();
    // What the text tool held lands on the way out, and its channel goes
    // quiet.
    _text.dispose();
    widget.brushToolState?.removeListener(_handleBrushChanged);
    _selectionSeat.unbindSelectionHistoryRecorder();
    // Leave no verb pointing at a dead State: the buttons must go dead
    // with the canvas rather than throw when pressed after it is gone.
    if (identical(
      widget.cutPieceSlot?.pasteAtOriginHandler,
      _installedCutPasteHandler,
    )) {
      widget.cutPieceSlot?.pasteAtOriginHandler = null;
    }
    if (identical(
      widget.lastStroke?.reinputHandler,
      _installedReinputHandler,
    )) {
      widget.lastStroke?.reinputHandler = null;
    }
    _line.unbind();
    _idleAnts.dispose();
    _selectionFloat.dispose();
    _toolCursorHover.dispose();
    _penPose.dispose();
    _stampPreview.dispose();
    _controlHolds.dispose();
    widget.viewCommands?.unbind(this);
    super.dispose();
  }

  /// I-15 · I-88: a view hold took the pointer — the tool's aim is nobody's until
  /// it lets go (a pointer that may not drive a tool may not aim it).
  void _onViewHoldChanged() {
    if (CanvasViewHold.held.value != null) {
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

  // What a mapped button does that is not drawing (F-299): the history
  // verbs and the pick it holds the eyedropper for, under every tool.
  late final _CanvasPanelMappedButtons _mappedButtons =
      _CanvasPanelMappedButtons(this);

  /// Who holds the tool besides the hand on the keys: the pen's tail, which
  /// the drawing view reads, and a button held for a pick, which
  /// [_mappedButtons] reads — each sees the other here.
  final CanvasToolHolds _toolHolds = CanvasToolHolds();

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

  /// The pointers a control over the tools holds — while one does, the
  /// tool's entrance takes none ([_ControlHolds]).
  final _ControlHolds _controlHolds = _ControlHolds();

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
  void _noteCanvasPointer(PointerEvent event) {
    final kind = event.kind;
    // I-15 · I-88: nor while a view hold has the pointer — it drives no tool.
    if (!AppInput.toolAcceptsPointer(kind) ||
        CanvasViewHold.held.value != null) {
      return;
    }
    // 🚨D34: and a MOUSE that a finger produced does not aim either — a
    // pen the OS calls a mouse is the pen while its driver says it is
    // down ([PenSidecars.kindOf]), and writes under a resting palm.
    if (aimIsPromotedTouch(
      kind: PenSidecars.kindOf(kind),
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
    _toolCursor.setToolCursorHover(
      (at: event.localPosition, kind: kind),
      'census:${kind.name}',
    );
    // How the pen at the aim is held, off the same event — what the brush
    // outline turns and stretches by (F-176-Q7).
    _penPose.value = penPoseOf(event);
    if (_toolCursor.drawsAtTheAim(kind) ||
        // The stamp's piece preview reads the same census — one writer,
        // every cursor a reader.
        canvasToolStamps(_brush.tool)) {
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
    if (oldWidget.canvasBase != widget.canvasBase ||
        oldWidget.backdropArgb != widget.backdropArgb ||
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
    // A host can hand over another reader (F-201).
    _bookState.bind();
    // A new limit holds a stored view elsewhere (F-201) — stored after the
    // frame, because the owner hears the write and this is its build.
    if (widget.viewLimit != oldWidget.viewLimit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _viewportState._holdTheStoredView();
        }
      });
    }
    rebindListener(
      oldWidget.selectionCommands,
      widget.selectionCommands,
      _selectionSeat.handleSelectionChannelChanged,
    );
    rebindListener(
      oldWidget.selectionMaskOptions,
      widget.selectionMaskOptions,
      _askTheGhostAgain,
    );
    _text.bind();
    // A host can hand over another brush to hear (the viewer's cut tool per
    // shape); the build this update leads to is the rebuild.
    rebindListener(
      oldWidget.brushToolState,
      widget.brushToolState,
      _handleBrushChanged,
    );
    _followStructure();
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
  ///
  /// 🚨EVERY framing this panel makes comes through here — the Fit button,
  /// an owner's auto-frame and the unframed first read — so this is where a
  /// fitted zoom lands on the grid the pill writes
  /// ([CanvasZoomScale.landedToFit], F-122).
  CanvasViewport _fittedInto(Rect visible, {required Rect canvasRect}) {
    final fitted = CanvasViewport.fitToCanvasRect(
      left: canvasRect.left,
      top: canvasRect.top,
      width: canvasRect.width,
      height: canvasRect.height,
      viewportWidth: visible.width,
      viewportHeight: visible.height,
      zoomLanding: _zoomScale.landedToFit,
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
  Widget build(BuildContext context) {
    // What rebuilds this panel is what moves the ghost's makings: a cel
    // written (the pixel signal's rebuild), the marquee (the ants'), the
    // cel stood on and the rows' placements (the host's).
    _askTheGhostAgain();
    return _PanelBuild(this).build(context);
  }

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
                  openTrails:
                      const [],
                ),
            child:
                const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Positioned _selectionLayer() {
    return Positioned.fill(
      child: _asideForTheContent(ValueListenableBuilder<TransformToolOptions>(
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
              tool: switch (_brush.tool) {
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
                CanvasTool.shape =>
                  CanvasSelectionTool
                      .drawShape,
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
                  _brush.activeShapeKind ??
                  CanvasShapeKind
                      .rect,
              // R17-U: Move = 이동+변형 통합 툴
              // — 핸들 상시.
              alwaysShowTransformBox:
                  _brush.tool ==
                  CanvasTool.move,
              onShapeCommitted:
                  _selectionSeat.recordSelectionChange,
              // I-14: a host whose content is not a cel cuts from what it
              // shows.
              onCutOutline:
                  widget.onCutContent ??
                  _cutPieceFrom,
              oneFingerAction:
                  widget.oneFingerAction,
              onFillOutline:
                  _fillDrawnOutline,
              onDrawShape:
                  _drawTracedShape,
              onDrawShapeDragged:
                  _showTracedShape,
              shapeKeepsRatio:
                  _brush.shapeOptions.ratioLock,
              // 🚨WHOEVER HEARS THE PRESS ASKS FOR THE CEL, AND ONLY ONE
              // DOES (I-10) — the text layer's door too. Content that is not
              // one cel answers with the cel under the press (F-420).
              onPressNeedsCel: _shapePressNeedsCel(context),
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
              guides: widget.guides,
              shiftLine: _shiftLine,
              viewport: _viewportState._viewport,
              pasteboard: _stagePasteboard,
              frameToken: _whatALiftTakesUp,
              selectionCommands:
                  widget
                      .selectionCommands,
              // No setState for either: the gesture layer asks both
              // when an event arrives (see its `strokeActive`).
              onModifierTouchDragActiveChanged:
                  (active) => _modifierTouchDragActive = active,
              onDragActiveChanged: (active) {
                if (_selectionDragActive !=
                    active) {
                  widget
                      .onSelectionInteractionChanged
                      ?.call(
                        active,
                      );
                  _selectionDragActive = active;
                }
              },
              // R14-④: the Move tool lifts the
              // selection's PIXELS (never whole
              // strokes) — 유저 direction ⑧b.
              onLiftRequested:
                  _selectionSeat.handleSelectionLift,
              onLiftConfirmed:
                  _lift.handleLiftConfirmed,
              onLiftReverted:
                  _lift.handleLiftReverted,
              // R26 #13 follow-up: the implicit
              // whole-picture box frames the
              // cel's tight ink bounds.
              contentBoundsProvider:
                  _inkBoundsUnderfoot,
              // ⛔A PENDING MOVE NO LONGER HOLDS THE EDIT LOCK, and the
              // callback that said so went with it (2026-09-17). R15-⑤ is
              // about a gesture IN FLIGHT — 「the playhead moves when the
              // pen lifts, never under it」 — and a pending session is a
              // state: the hand is already off it. What kept it locked was
              // that the lift committed its erase, so leaving the frame
              // left a HOLE behind; `314aa6e8` stopped writing anything
              // until the landing, and with nothing left behind there is
              // nothing to refuse a seek for. 유저 2026-09-12: 「타임라인쪽
              // 조작이 안먹힘. 룰러쪽 선택해도 드래그안되고 화살표이동도
              // 안먹고」 (F-116, and the same complaint on F-86).
              // The transform tool's whole knob
              // set. Read through the
              // listenable above, so changing
              // one mid session re-resamples
              // the open preview instead of
              // waiting for the next gesture.
              transformOptions:
                  transformOptions,
            ),
      )),
    );
  }

  /// [layer], a tool's over the content, not hit where the content takes
  /// the press itself ([BrushCanvasPanel.contentTakesPressAt]) — so the
  /// press falls through to it.
  Widget _asideForTheContent(Widget layer) => Builder(
    builder: (gate) => HitGate(
      admits: (position) {
        final takes = widget.contentTakesPressAt;
        final box = gate.findRenderObject();
        return takes == null ||
            box is! RenderBox ||
            !takes(box.localToGlobal(position));
      },
      child: layer,
    ),
  );

  Widget _buildViewportContent(BuildContext context) {
    final override = widget.contentOverride;
    if (override != null) {
      return override(context, _viewportState._viewport);
    }

    final coordinator = widget.coordinator!;
    final activeKey = coordinator.activeFrameKey;
    final liveSelection = widget.selectionCommands?.region;
    _strokeClipAsBuilt = liveSelection;
    final interactiveView = InteractiveBrushEditCanvasView(
      // STABLE key (R13-2): keying by frameId remounted the whole
      // interactive subtree on every frame flip — the constant flip
      // hitch. Cel changes reset in place via didUpdateWidget.
      key: const ValueKey<String>('brush-canvas-view'),
      celNow: () => coordinator.currentSurfaceOf(activeKey),
      layerId: activeKey.layerId,
      frameId: activeKey.frameId,
      inputSettings: _inputSettingsNow,
      viewport: _viewportState._viewport,
      onPressNeedsCel: widget.onPressNeedsCel,
      markMakesItsOwnCel: widget.markMakesItsOwnCel,
      // The pen's tail and a button mapped to the eraser — the holds that
      // DRAW. A held pick and the history verbs are [_mappedButtons]'.
      onTemporaryToolHold: widget.onTemporaryToolHold,
      onTemporaryToolRelease: widget.onTemporaryToolRelease,
      toolHolds: _toolHolds,
      onSourceStrokeCommitted: _handleSourceStrokeCommitted,
      // R22-A: the FILL tool runs through the view's stroke pipeline
      // (the result tiles on the tap frame, landed like a pen-up) instead
      // of the panel tap layer.
      fillDabsAt: _brush.tool == CanvasTool.fill
          ? widget.fillDabsAt
          : null,
      // R26 #18: the live stroke shows clipped to the selection, exactly
      // as the commit will clip it — in the row's own artwork, where this
      // view draws (a-marquee-on-a-posed-row).
      selectionRegion: switch (liveSelection) {
        null => null,
        final selection => _selectionSeat.regionOnTheRow(selection),
      },
      strokeLander: _viewLander,
      // I-69: the shape tool has the view draw what its drag traced.
      shapeShow: _shapeShow,
      onActiveStrokeChanged: (stroke) {
        if (_stroke != stroke) {
          widget.onStrokeInputActiveChanged?.call(stroke);
          // ⛔NOT a setState (2026-09-26): nothing the panel draws reads
          // this — the gesture layer asks for it when an event arrives —
          // and the rebuild it forced rebuilt the whole canvas panel on
          // every pen-down and pen-up.
          _stroke = stroke;
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
      // H19's other question, carried down (F-196): the row decides what a
      // press may DO, so a lane over a cel draws no line at all.
      rowAcceptsStrokes: widget.rowAcceptsStrokes,
      // Guides stand on the canvas, and this view's strokes record in
      // artwork coordinates (the draw-through wrap below): what a guide
      // measures makes the same trip the pointers do, or the axis sits
      // where the pen is not.
      guides: widget.guides ?? CutGuides.empty,
      guideSpace: guideSpaceOf(widget.interactiveContentPose),
      shiftLine: _shiftLine,
    );
    // The draw-through wrap: display AND hit testing share one screen
    // matrix, so the active layer draws posed and pointers inverse-map to
    // artwork coordinates in lockstep (R3 ⑩ — always-applied transforms).
    //
    // ⛔ALWAYS a Transform — the identity while the row stands unposed. The
    // wrap used to come and go with the pose, and a view that changes parent
    // is a view mounted again: the expensive half of a flip. Since F-195 the
    // canvas follows a handle drag as it goes, so an unposed row paid that
    // mount on the first step of every drag and again when a drag went away.
    // An identity Transform paints its child in place (a translation by
    // zero: no layer), so standing still costs nothing.
    final placement = widget.interactiveContentPose;
    final posedView = Transform(
      transform: placement == null
          ? Matrix4.identity()
          : placementViewportWrapMatrix(placement, _viewportState._viewport),
      child: interactiveView,
    );
    // ⛔WRAPPED AT 1 TOO (F-419): a wrap that came and went as the active
    // row's opacity crossed 1 changed the view's parent, so Flutter built
    // the view anew each time — its stroke in flight dropped, and its hands
    // handed over again (the old view's goodbye came last and took the
    // shape tool away for the session). At 1 an Opacity paints its child
    // straight, with no layer of its own.
    return Opacity(
      opacity: widget.interactiveContentOpacity.clamp(0.0, 1.0).toDouble(),
      child: posedView,
    );
  }

  /// What is hidden from the artwork: the panels lying on the floor, a
  /// docked panel's own lanes — its panbars stand on the artwork's right and
  /// bottom edges (F-209) — the pill's band across the top edge
  /// ([_CanvasEditorPanelShell.pillBandIn]), and the transport under a
  /// document you move through ([_CanvasEditorPanelShell.transportCover]) —
  /// a book's page turner as a movie's player (F-383) — and the left pill's
  /// band down the left edge ([_CanvasEditorPanelShell.leftPillBandOf]).
  /// Framing keeps out from under all of it as it keeps out from under a
  /// panel.
  ///
  /// ⚠️The left pill's band adds to the floor's left cover only where the
  /// pill has stepped past the left rail ([_leftPillBesideRail]). On the
  /// box's own left edge it is the larger of the two, not their sum:
  /// framing counts a rail's band as its whole edge, so a rail there
  /// already covers the pill — the page strip's law on that edge.
  EdgeInsets get _framingInsets {
    final covered =
        widget.floorCover +
        (_onFloor
            ? EdgeInsets.zero
            : _CanvasEditorPanelShell.dockedLanesOf(_lane)) +
        EdgeInsets.only(
          top: _pillBand,
          bottom: _CanvasEditorPanelShell.transportCover(
            widget.transport,
            onFloor: _onFloor,
            floorOverlay: widget.floorBottomOverlaySpan,
          ),
        );
    final pill = _CanvasEditorPanelShell.leftPillBandOf(widget.leftPill);
    return covered.copyWith(
      left: _leftPillBesideRail
          ? covered.left + pill
          : math.max(covered.left, pill),
    );
  }

  /// [_CanvasEditorPanelShell.pillBandIn], measured where the words it is
  /// sized by are known — and again whenever they change.
  late double _pillBand;

  /// Whether the left pill stood past the left rail when it was last laid
  /// out — what its seat decided ([_LeftEdgeSeat]), kept because framing is
  /// read before the layout that places it.
  bool _leftPillBesideRail = false;

  void _rememberLeftPillBeside(bool beside) {
    if (beside == _leftPillBesideRail) {
      return;
    }
    _leftPillBesideRail = beside;
    // Learned in a layout, after this frame's build framed the view with
    // the answer before it: the next build frames with this one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _rebuild(() {});
      }
    });
  }

  void _handleSourceStrokeCommitted(BrushStrokeCommitData strokeData) {
    labProbe('penUpCommitHandler', () => _commitSourceStroke(strokeData));
    _line.heard(strokeData);
  }

  // The lift (Round 6): anchors, the pre-landing surface, and how a lift ends.
  late final _CanvasPanelLift _lift = _CanvasPanelLift(this);

  // The text tool (R9-rest): the hand it holds a text with, and its layer.
  late final _CanvasPanelText _text = _CanvasPanelText(this);

  // The line from the last stroke (I-119): its start, its press, its ants.
  late final _CanvasPanelLine _line = _CanvasPanelLine(this);

  /// What a session of the selection layer belongs to
  /// ([CanvasSelectionLayer.frameToken]) — the cels a lift takes up here
  /// ([BrushCanvasPanel.transformCelsUnderfoot]), or the cel this canvas
  /// edits. When it changes, an open box walks.
  ///
  /// 🚨THE CELS UNDERFOOT, not the edited one (I-37): stood on a folder, the
  /// playhead moves the cels underfoot while the cel this canvas edits stays
  /// put, and a box keyed on that one did not walk — it went on showing the
  /// frame it was opened on, lifted, over the frame it stood on.
  ///
  /// No frame = a stable sentinel: the selection survives until a real
  /// frame context arrives.
  Object get _whatALiftTakesUp =>
      switch (widget.transformCelsUnderfoot?.call()) {
        final cels? => ByList(cels),
        null => widget.coordinator?.activeFrameKey ?? 'selection-no-frame',
      };

  /// The cels a lift takes up where you stand, each with the placement its
  /// row shows it at, and whether it is the cel this canvas edits — the live
  /// row. Past that one, every cel the transform lands on that shows at the
  /// playhead ([BrushCanvasPanel.transformCelsUnderfoot]): stood on a
  /// FOLDER, the cel of each drawing row inside it, none of them live
  /// (I-37); with a frame RANGE across rows, each row's cel there (F-329).
  /// Empty where nothing can be lifted.
  ///
  /// ⚠️The rows not live only into a COMPOSITE: a cel the canvas does not
  /// edit is drawn by the composite, and with none behind this canvas the
  /// lift would have nowhere to show the rows it took up.
  List<({BrushFrameKey key, LayerPlacement? placement, bool live})>
  _celsUnderfoot() {
    final coordinator = widget._editableCoordinator;
    final underfoot = widget.transformCelsUnderfoot?.call();
    final placementOf = widget.cellPlacementOf;
    return [
      if (coordinator != null)
        (
          key: coordinator.activeFrameKey,
          placement: widget.interactiveContentPose,
          live: true,
        ),
      if (underfoot != null && widget.viewportUnderlayBuilder != null)
        for (final cel in underfoot)
          if (!cel.live)
            (key: cel.key, placement: placementOf?.call(cel.key), live: false),
    ];
  }

  /// R26 #13 follow-up: the tight ink bounds of what a lift takes up where
  /// you stand ([_celsUnderfoot]) — the implicit whole-picture transform box
  /// frames exactly the picture, PS-style, and on a FOLDER all of its rows'
  /// together (I-37: 「변형도구 실루엣은 전체를 기준으로」). Null (no
  /// coordinator, or blank cels) falls back to the canvas rect inside the
  /// selection layer.
  ///
  /// 🚨ON THE CANVAS, where each row shows its ink (a-marquee-on-a-posed-
  /// row): the box is drawn around what the user SEES, and a posed row's ink
  /// sits somewhere else in its own artwork.
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  _inkBoundsUnderfoot() {
    final coordinator = widget.coordinator;
    if (coordinator == null) {
      return null;
    }
    ({int left, int top, int rightExclusive, int bottomExclusive})? held;
    final asked = Set<BitmapSurface>.identity();
    for (final under in _celsUnderfoot()) {
      final surface = coordinator.currentSurfaceOf(under.key);
      asked.add(surface);
      final shown = _whereTheRowShows(_inkOf(surface), under.placement);
      if (shown == null) {
        continue;
      }
      held = held == null
          ? shown
          : (
              left: math.min(held.left, shown.left),
              top: math.min(held.top, shown.top),
              rightExclusive: math.max(
                held.rightExclusive,
                shown.rightExclusive,
              ),
              bottomExclusive: math.max(
                held.bottomExclusive,
                shown.bottomExclusive,
              ),
            );
    }
    _inkMemo.removeWhere((surface, _) => !asked.contains(surface));
    return held;
  }

  /// [surface]'s ink bounds in its own artwork.
  ///
  /// Memoized on the surface INSTANCE. `bitmapSurfaceContentBounds`
  /// documents itself as "never a per-frame path", and that was false: the
  /// selection layer calls this provider from `build` to frame the always-on
  /// move box, so it ran once per rebuild — a full alpha scan of every tile,
  /// preceded by `surface.tiles`, which is `Map.unmodifiable(_tiles)` and
  /// copies the whole tile map on each read. BitmapSurface is immutable with
  /// structural tile sharing (the painter's shouldRepaint already relies on
  /// that), so identity is an exact key: a changed cel is always a new
  /// instance.
  ({int left, int top, int rightExclusive, int bottomExclusive})? _inkOf(
    BitmapSurface surface,
  ) => _inkMemo.putIfAbsent(surface, () => bitmapSurfaceContentBounds(surface));

  /// [_inkOf]'s answers, for the surfaces asked about last.
  final Map<
    BitmapSurface,
    ({int left, int top, int rightExclusive, int bottomExclusive})?
  >
  _inkMemo = Map.identity();

  /// [bounds] — a row's ink in its own artwork — as the canvas shows it at
  /// [placement]: the box around the four corners the placement carries
  /// them to. An unplaced row's come back as they are.
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  _whereTheRowShows(
    ({int left, int top, int rightExclusive, int bottomExclusive})? bounds,
    LayerPlacement? placement,
  ) {
    if (bounds == null || placement == null) {
      return bounds;
    }
    final shown = placedRectBounds(
      placement,
      Rect.fromLTRB(
        bounds.left.toDouble(),
        bounds.top.toDouble(),
        bounds.rightExclusive.toDouble(),
        bounds.bottomExclusive.toDouble(),
      ),
    );
    return (
      left: shown.left.floor(),
      top: shown.top.floor(),
      rightExclusive: shown.right.ceil(),
      bottomExclusive: shown.bottom.ceil(),
    );
  }

  /// A finished cut outline — with every copy a symmetry guide made of it,
  /// as one region — lifted into the slot as ONE piece, every side in it
  /// (유저 답 the-cut-preview-shows-copies-it-does-not-cut-Q1).
  ///
  /// Reads the ACTIVE LAYER's committed surface and nothing else — no
  /// composite, no layer transform, no effects (유저 확정: "트랜스폼이나 이런
  /// 거 반영 안 한 진짜 순수 픽셀"). That is also why the piece can carry
  /// plain cel coordinates: the read and the eventual write are in the same
  /// space, so a posed layer cannot make them disagree.
  ///
  /// The surface is never written by the read. Cutting copies — and then,
  /// with the tool's 「원본 삭제」 on, takes what it copied ([_takeOffTheCel]).
  void _cutPieceFrom(CanvasSelectionRegion outline) {
    final slot = widget.cutPieceSlot;
    // ★THE CEL QUESTION, NOT THE ROW'S (H19): a cut COPIES — it reads the
    // cel and writes nothing — so a lane, which refuses the STROKE, does
    // not refuse it. 🗣️F-222-box-Q4 「선택 · 잘라내기만 빼고 모든 도구」
    // leaves the cut its canvas on an fx row; through the verbs' guard it
    // drew its outline there and silently cut nothing.
    final coordinator = widget.celEditable ? widget.coordinator : null;
    // The outline is drawn on the canvas; the pixels are the row's own
    // (a-marquee-on-a-posed-row) — and the PIECE stays those pure pixels in
    // the row's own coordinates, as confirmed above.
    final onTheRow = _selectionSeat.regionOnTheRow(outline);
    if (slot == null) {
      return;
    }
    final read = coordinator == null || onTheRow == null
        ? null
        : readCutPiece(
            region: onTheRow,
            surface: coordinator.currentSurfaceOf(coordinator.activeFrameKey),
          );
    // Null = no cel under the outline, or no paint inside it: the slot is
    // left alone and the cut says it found nothing, as every cut does
    // (F-254: 「잘라내기도구로 빈 곳에 그렸을때도 동일하게」).
    cutIntoTheHand(read?.piece, slot.hold);
    if (read != null && _brush.cutDeletesSource) {
      _takeOffTheCel(read);
    }
  }

  /// The cut tool's 「원본 삭제」 (I-90): what [read] cut leaves the cel you
  /// stand on, as one undo ([cutPixelsTaken]).
  ///
  /// ★THE ROW'S QUESTION this time ([_editableCoordinator], H19): taking
  /// pixels off is a write, and a row that refuses the stroke refuses it —
  /// the copy above still lands in the hand.
  void _takeOffTheCel(CutRead read) {
    final coordinator = widget._editableCoordinator;
    final historyManager = widget.historyManager;
    if (coordinator == null || historyManager == null) {
      return;
    }
    historyManager.execute(
      cutPixelsTaken(
        coordinator: coordinator,
        key: coordinator.activeFrameKey,
        read: read,
        cacheInvalidationSink: widget.cacheInvalidationSink,
      ),
    );
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
    if (canvasToolStamps(_brush.tool)) {
      _tap.dragStampTo(point);
      return;
    }
    if (_brush.tool == CanvasTool.eyedropper) {
      _tap.toolTapHandler()?.call(point);
    }
  }

  /// The drawing view's [ShapeShow] while it is mounted — how a shape being
  /// dragged shows its actual result, and lands as shown
  /// ([_showTracedShape], [_drawTracedShape]). ⛔Kept by [ViewHand]'s count,
  /// not the last word: the view is built anew whenever the active row's
  /// opacity crosses 1 (the wrap in [_buildViewportContent]), and the old
  /// view's goodbye comes after the new one's hello (F-419).
  final ViewHand<ShapeShow> _shapeShow = ViewHand();

  /// The drawing view's [StrokeLander] while it is mounted, counted as
  /// [_shapeShow] is.
  final ViewHand<StrokeLander> _viewLander = ViewHand();

  /// The line Shift holds on this canvas (I-121) — ONE for every path the
  /// hand draws here, the stroke's, the lasso's and the stamp's, so a line
  /// a hold kept goes on whichever of them draws next. The panel hears the
  /// keyboard for it, for its life ([ShiftLine.heardKey]), and the glass
  /// ([_heardAFingerLift]).
  final ShiftLine _shiftLine = ShiftLine();

  /// A finger left the glass: the line goes unless Shift is still held —
  /// by the key, or by a finger still resting
  /// ([CanvasTouchContacts.aFingerDownBesides]).
  void _heardAFingerLift() => _shiftLine.heldNow(
    ModifierKeys.isShiftPressed || CanvasTouchContacts.aFingerDownBesides(null),
  );

  /// The hand as the app hears it beyond this canvas, for the panel's life:
  /// a finger landing anywhere, and the key and the glass that say whether
  /// Shift still holds [_shiftLine].
  void _hearTheHand() {
    // 🚨D34 최종: a finger ANYWHERE drops the tool aim — see
    // [CanvasTouchContacts.addAppWideTouchListener] and [_handleAppWideTouch].
    CanvasTouchContacts.addAppWideTouchListener(_handleAppWideTouch);
    HardwareKeyboard.instance.addHandler(_shiftLine.heardKey);
    CanvasTouchContacts.addAppWideLiftListener(_heardAFingerLift);
  }

  void _stopHearingTheHand() {
    CanvasTouchContacts.removeAppWideTouchListener(_handleAppWideTouch);
    HardwareKeyboard.instance.removeHandler(_shiftLine.heardKey);
    CanvasTouchContacts.removeAppWideLiftListener(_heardAFingerLift);
  }

  /// What a save lands first (R9-rest): the stroke the view's pen is in
  /// AND the text in hand — nothing while no view is up. Held up for the
  /// panel's life ([BrushCanvasPanel.strokeLander]); it asks the view's
  /// hand when the save does.
  bool _landWorkInFlight() => _text.landBeside(_viewLander.now);

  /// The keeper [_landWorkInFlight] is held up to — taken as the panel
  /// comes up, so it is put down there as the panel goes.
  late final ViewHand<StrokeLander>? _saveKeeper = widget.strokeLander;

  /// Where the shape being dragged lands on content that is not one cel
  /// ([BrushCanvasPanel.contentShapeTargetAt]) — taken at the press, gone
  /// with the drag: the show of the view under the press, and a canvas
  /// point on that view's cel.
  ({ShapeShow show, CanvasPoint? Function(CanvasPoint point) onTheCel})?
  _contentShape;

  /// The shape tool's question at its press
  /// ([CanvasSelectionLayer.onPressNeedsCel]), [layer] being the context of
  /// the layer that asks — the box the canvas is laid in. On one cel it is
  /// the door over the view ([_markDoorOverTheView]); on content that is
  /// not one cel, the view under the press (F-420), which is the cel the
  /// shape lands on wherever the drag goes after — as a stroke is the
  /// window's it starts in (H49).
  bool Function(CanvasPoint at)? _shapePressNeedsCel(BuildContext layer) {
    final targetAt = widget.contentShapeTargetAt;
    if (targetAt == null) {
      final door = _markDoorOverTheView;
      return door == null ? null : (_) => door();
    }
    Offset onTheScreen(CanvasPoint point) {
      final local = _viewportState._viewport.canvasToViewport(point);
      final box = layer.findRenderObject()! as RenderBox;
      return box.localToGlobal(Offset(local.x, local.y));
    }

    return (at) {
      final target = targetAt(onTheScreen(at));
      _contentShape = switch (target) {
        null => null,
        (:final show, :final onTheCel) => (
          show: show,
          onTheCel: (point) => onTheCel(onTheScreen(point)),
        ),
      };
      return target != null;
    };
  }

  /// Whether the stamp's ghost is what [_shapeShow] shows — so a ghost
  /// going away takes back only itself, never a shape being dragged.
  bool _ghostShown = false;

  /// Whether the ghost is to be asked again at the end of this frame
  /// ([_askTheGhostAgain]) — once however many things ask.
  bool _ghostAskWaiting = false;

  /// 🚨THE STAMP'S GHOST IS WHAT A CLICK THERE LANDS — on the cel on screen,
  /// the door's own answer for it ([pieceDabs]), laid by the view as a
  /// dragged shape is: the last whole ghost stays up until the next is
  /// whole, while the cursor keeps its own pace.
  /// 🗣️brush-fidelity-Q9 (유저 2026-10-18): 「통일하면 좋음」 — every mode,
  /// normal too, pre-blended on the CPU; Q10: the shape tool's law.
  ///
  /// ↩️It was drawn on the GPU, `preBlended: false` on purpose: a hover
  /// ghost has no committed tiles to stand for, so pre-blending (what buys
  /// a stroke its byte-exact preview, R27 #4) was judged not worth it. That
  /// drew a mode the GPU has no blend for as normal (brush-fidelity-Q7), and
  /// a selection not at all.
  void _showStampGhost() {
    final show = _shapeShow.now;
    final preview = _stampPreview.value;
    final coordinator = widget.coordinator;
    if (show == null) {
      return;
    }
    if (preview == null || coordinator == null) {
      if (_ghostShown) {
        _ghostShown = false;
        show.drop();
      }
      return;
    }
    _ghostShown = true;
    show.show(_stampGhostArea(preview, coordinator));
  }

  /// The ghost of [preview] as the area the view lays ([ShapeArea]): the
  /// door's own answer for the cel on screen ([pieceDabs]), read and cut
  /// when the view lays it — inside a frame's share, never in the build or
  /// the hover that asked.
  ShapeArea _stampGhostArea(
    CutStampPreview preview,
    BrushFrameEditingCoordinator coordinator,
  ) {
    final store = coordinator.frameStore;
    final ground = _pieceGround(coordinator);
    final rect = preview.canvasRect;
    final onCanvas = CanvasPoint(x: rect.center.dx, y: rect.center.dy);
    // The aim's own blend: its change is what re-lays the ghost
    // ([CutStampPreview.blendMode]).
    final blend = preview.blendMode;
    final stamp = PieceStamp(
      // The click's own piece ([_CanvasPanelTap.pieceCentredOn]).
      onTheRow: _tap.pieceCentredOn(
        preview.piece,
        onCanvas,
        opacity: preview.opacity,
      ),
      blend: blend,
      description: 'Stamp',
    );
    final standing = store.canonicalKeyOf(coordinator.activeFrameKey);
    return (
      // 🚨EVERYTHING THE GHOST'S BYTES ARE MADE OF — the aim, the cel as it
      // is now, and every fact of the ground the door reads — so whatever
      // moves under a resting hand lays it again ([_askTheGhostAgain]),
      // and nothing else does.
      shape: (
        piece: preview.piece,
        at: onCanvas,
        opacity: preview.opacity,
        blend: blend,
        standing: standing,
        cel: ByIdentity(coordinator.currentSurfaceOf(standing)),
        selection: ground.selection,
        softness: ground.options,
        ladder: ByList([
          for (final key in ground.cels)
            (key, store.canonicalKeyOf(key), ground.placementOf(key)),
        ]),
      ),
      pieces: () sync* {
        final answer = pieceDabs(
          coordinator: coordinator,
          ground: ground,
          stamp: stamp,
          only: standing,
        )[standing];
        if (answer != null) {
          yield answer.dab;
        }
      },
      blend: blend,
    );
  }

  /// What the stamp's ghost listens to, let go: the aim and the softness
  /// it is cut at ([_showStampGhost], [_askTheGhostAgain]).
  void _stopAskingTheGhost() {
    widget.selectionMaskOptions?.removeListener(_askTheGhostAgain);
    _stampPreview.removeListener(_showStampGhost);
  }

  /// 🚨THE GHOST FOLLOWS WHAT IT IS MADE OF, NOT ONLY THE HAND: asks
  /// [_showStampGhost] again at the end of the frame while a ghost is up —
  /// the cel under it written (a landing, an undo, a verb pressed on the
  /// timeline), the marquee or its softness changed, the panel stood on
  /// another cel. Its shape holds all of that, so a ghost nothing moved
  /// under asks for nothing.
  ///
  /// At the end of the frame, because the drawing view hears a build after
  /// this panel does: a cel changed under it drops the ghost of the cel
  /// that went, and one asked for before would be laid on that cel.
  void _askTheGhostAgain() {
    if (!_ghostShown || _ghostAskWaiting) {
      return;
    }
    _ghostAskWaiting = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _ghostAskWaiting = false;
        if (mounted) {
          _showStampGhost();
        }
      })
      ..ensureVisualUpdate();
  }

  /// Draw a finished shape-tool drag (I-69) — [copies], the traced path
  /// and every copy the symmetry guide made of it, the original first — as
  /// the tool is set to lay it, and as the drag showed it (Q4ⓒ):
  ///
  /// - a line of the BRUSH type as ONE STROKE of the brush in hand, laid by
  ///   the drawing view through the stroke's own code — so the selection
  ///   clips it, symmetry copies it, undo covers it and it is saved as the
  ///   stroke it is ([ShapeShow.landStroke]). ⚠️So the stroke is handed the
  ///   ORIGINAL alone ([_tracedStroke]): it makes its own copies, and
  ///   handed theirs it would copy every copy;
  /// - everything else — 「채움」, and a line of the 「일반」 type — as ONE
  ///   AREA, every copy's together ([_tracedArea]), landed by the road a
  ///   fill lands by ([ShapeShow.land]). Where two copies overlap the area
  ///   is covered once (유저 답 I-69-Q6: 「따른다 — 도형 채우기도 같이
  ///   맞춘다」).
  void _drawTracedShape(List<DrawnShapePath> copies) =>
      _landTraced(copies, asStroke: _brush.shapeDrawsWithTheBrush);

  /// The shape a shape-tool drag has traced SO FAR — [copies], as
  /// [_drawTracedShape] takes them — shown under its outline as it will
  /// land, or taken back when there is none (유저 답 I-69-Q4ⓒ: 「윤곽선은 손을
  /// 따라오고, 실제 결과는 따라 그린다」).
  void _showTracedShape(List<DrawnShapePath>? copies) =>
      _showTraced(copies, asStroke: _brush.shapeDrawsWithTheBrush);

  /// Lands [copies] — a traced path and every copy the guide made of it,
  /// the original first — as ONE STROKE of the tool in hand where
  /// [asStroke], and as ONE AREA where not ([_drawTracedShape]). The shape
  /// tool's line and the line from the last stroke (I-119) both land here:
  /// 「도형도구의 직선이랑 최대한 동일하게 로직 재사용. 법 통일」. A stroke is
  /// laid at [pressure] the whole way ([ShapeShow.landStroke]).
  void _landTraced(
    List<DrawnShapePath> copies, {
    required bool asStroke,
    double pressure = 1,
  }) {
    final show = _contentShape?.show ?? _shapeShow.now;
    final onTheRow = _onTheRow(copies);
    _contentShape = null;
    if (show == null) {
      return;
    }
    if (onTheRow == null) {
      show.drop();
      return;
    }
    if (asStroke) {
      show.landStroke(_tracedStroke(onTheRow), pressure: pressure);
      return;
    }
    show.land(_tracedArea(onTheRow));
  }

  /// [_landTraced]'s show: [copies] traced so far, shown as they will land
  /// — or, null, taken back ([_showTracedShape]).
  void _showTraced(
    List<DrawnShapePath>? copies, {
    required bool asStroke,
    double pressure = 1,
  }) {
    final show = _contentShape?.show ?? _shapeShow.now;
    if (copies == null) {
      // The drag is over without a shape: what its press took goes too.
      _contentShape = null;
    }
    if (show == null) {
      return;
    }
    final onTheRow = copies == null ? null : _onTheRow(copies);
    if (onTheRow == null) {
      show.drop();
      return;
    }
    if (asStroke) {
      show.showStroke(_tracedStroke(onTheRow), pressure: pressure);
      return;
    }
    show.show(_tracedArea(onTheRow));
  }

  /// The STROKE the shape tool lays for [onTheRow] where it draws with the
  /// brush: along the original alone — the stroke makes the guide's copies
  /// itself — and round to its start again where it is closed.
  List<CanvasPoint> _tracedStroke(List<DrawnShapePath> onTheRow) {
    final path = onTheRow.first;
    return [...path.points, if (path.closed) path.points.first];
  }

  /// [copies] where the row shows them: traced on the canvas, drawn in the
  /// row's own artwork (a-marquee-on-a-posed-row) — or on the cel the
  /// press took on content that is not one cel (F-420). Null when there is
  /// nothing to draw on — no copy, or a placement that collapsed the row.
  List<DrawnShapePath>? _onTheRow(List<DrawnShapePath> copies) {
    final onTheCel =
        _contentShape?.onTheCel ?? _selectionSeat.pointOnTheRow;
    final onTheRow = <DrawnShapePath>[];
    for (final path in copies) {
      final points = <CanvasPoint>[];
      for (final point in path.points) {
        final there = onTheCel(point);
        if (there == null) {
          return null;
        }
        points.add(there);
      }
      onTheRow.add((points: points, closed: path.closed));
    }
    return onTheRow.isEmpty ? null : onTheRow;
  }

  /// The AREA the shape tool lays for [onTheRow] where it does not draw
  /// with the brush — every copy's together ([_shapeToolArea]), under the
  /// tool's blend. Exactly the area — it grows by nothing — at the tool's
  /// OWN opacity and with the tool's own edge: no brush is read (유저 답
  /// I-69-Q8: 「일반은 브러시랑 전혀 관계없는 독립적인것임」 · Q9: 「채움은
  /// 타입과 무관하다」).
  ShapeArea _tracedArea(List<DrawnShapePath> onTheRow) {
    final antiAlias = _brush.shapeOptions.antiAlias;
    final line = markUnderAPixel(
      _brush.shapeOptions.size,
      antiAliased: antiAlias,
    );
    final region = CanvasSelectionRegion.unionOf([
      for (final path in onTheRow) ?_shapeToolArea(path, lineWidth: line.width),
    ]);
    final color = _brush.color;
    final opacity = switch (_brush.shapePart) {
      // An outline's inside has no width for a pixel to hold.
      ShapePart.fill => _brush.activeOpacity,
      ShapePart.line => _brush.activeOpacity * line.opacity,
    };
    final blend = _brush.activeBlendMode;
    // The maker cuts ([ShapeArea]): the selection's hard outline on the row,
    // as the view's own clip cut it before (brush-fidelity-Q11 asks whether
    // a shape should take the selection's softness as a held picture does).
    final selection = switch (widget.selectionCommands?.region) {
      null => null,
      final live => _selectionSeat.regionOnTheRow(live),
    };
    return (
      shape: (region, color, opacity, antiAlias, blend),
      pieces: () => region == null
          ? const <BrushDab>[]
          : [
              for (final piece in regionFillPieces(
                region: region,
                color: color,
                opacity: opacity,
                options: FloodFillOptions(expandPx: 0, antiAlias: antiAlias),
              ))
                if (selection == null)
                  piece
                else
                  ?clipStampDabToSelection(piece, region: selection),
            ],
      blend: blend,
    );
  }

  /// What the shape tool lays where it does not draw with the brush, as
  /// the area it covers — [onTheRow] being the traced path in the row's
  /// own artwork:
  ///
  /// - 「채움」 (유저 답 I-69-Q7 메모): the shape's inside. Only a shape that
  ///   HAS one gets here ([BrushToolState.shapePart]), and its path is its
  ///   outline;
  /// - a line of the 「일반」 type: the line's own area, [lineWidth] across
  ///   and turning as the tool says ([plainLineRegion]).
  CanvasSelectionRegion? _shapeToolArea(
    DrawnShapePath onTheRow, {
    required double lineWidth,
  }) => switch (_brush.shapePart) {
    ShapePart.fill => CanvasSelectionRegion.shape(
      CanvasSelectionShape(onTheRow.points),
    ),
    ShapePart.line => plainLineRegion(
      points: onTheRow.points,
      closed: onTheRow.closed,
      width: lineWidth,
      corners: _brush.shapeOptions.corners,
    ),
  };

  /// Paint a finished shape-fill outline — with every copy the symmetry
  /// guide made of it, as one region — filled as ONE area, as a selection
  /// takes them (유저 답 I-69-Q6).
  ///
  /// Straight through the stroke funnel like the bucket's own pieces, so
  /// the live selection clips it, undo covers it and serialization is free
  /// — the fill has landed this way since P6 and the shape fill is the same
  /// stamp from a different source.
  void _fillDrawnOutline(CanvasSelectionRegion outline) {
    final build = widget.shapeFillDabsFor;
    // Drawn on the canvas, painted into the row's own artwork where the row
    // shows it (a-marquee-on-a-posed-row).
    final area = _selectionSeat.regionOnTheRow(outline);
    if (build == null || area == null) {
      return;
    }
    _layArea((color) => build(area, color));
  }

  /// Lays an AREA as one stroke, whichever tool drew it — the fill tool's
  /// shape fill, the shape tool's fill, its plain line: the stamp pieces
  /// are [build]'s, and everything after them is one road.
  void _layArea(List<BrushDab> Function(int color) build) {
    if (widget._editableCoordinator == null) {
      return;
    }
    final dabs = build(_brush.color);
    if (dabs.isEmpty) {
      return;
    }
    final blend = _brush.activeBlendMode;
    _commitSourceStroke(
      BrushStrokeCommitData(
        sourceDabs: [for (final dab in dabs) dab.underBlend(blend)],
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
  ///
  /// 🗣️I-28-paste-in-place-Q1 (유저 2026-10-01): 「같은 문으로 — 범위 전부 ·
  /// 페더 따름」 — on every cel 픽셀 붙여넣기 would land on, through the
  /// selection's softness ([_landStamp]). ↩️It asked for a cel under the
  /// playhead first; the ground answers that now, as it does for the paste.
  void pasteCutPieceAtOrigin() {
    final piece = widget.cutPieceSlot?.piece;
    if (piece == null) {
      return;
    }
    // ONE dab for every row: the piece goes back where it was cut from,
    // whichever row takes it.
    final dab = buildCutPasteDab(piece, opacity: _brush.cutStampOpacity);
    _landStamp((_) => dab);
  }

  /// Lands the held piece with the stamp tool's own blend — [onTheRow] is
  /// the piece as a row standing at a placement takes it
  /// ([PieceStamp.onTheRow]).
  ///
  /// 🚨★★★**ALL THREE STAMP ROADS, THROUGH THE PIECE DOOR** ([pieceLandings])
  /// — a press on the canvas, a drag's trail and 원래 위치에 붙여넣기 land
  /// where 픽셀 붙여넣기 lands: every cel the ladder names, each through the
  /// selection as its own row shows it, one undo.
  ///
  /// 🗣️F-293 (유저 2026-10-05): 「잘라내기도구의 스탬프, 여러 프레임 선택해서
  /// 여러프레임 붙여넣을수있도록. **색편집의 픽셀붙여넣기랑 법 통일**」 · 「선택
  /// 범위로 선택한채로 커서로 붙여넣거나, 원래 위치에 붙여넣기나 동일하게」.
  ///
  /// ↩️They went down the stroke funnel ([_commitSourceStroke]), which lands
  /// on the cel you stand on and cuts through a selection's hard outline.
  /// The erase flag a stamp's dab wears rode along here; the door sets it.
  void _landStamp(BrushDab? Function(LayerPlacement? placement) onTheRow) {
    final coordinator = widget.coordinator;
    if (coordinator == null) {
      return;
    }
    // The stamp's own, as its opacity is ([pasteCutPieceAtOrigin]) and as
    // its ghost shows it. ↩️It read the tool in hand — the same number only
    // while the stamp's own tile was the one pressing.
    final blend = _brush.cutStampBlendMode;
    final landed = pieceLandings(
      coordinator: coordinator,
      ground: _pieceGround(coordinator),
      stamp: PieceStamp(
        onTheRow: onTheRow,
        blend: blend,
        description: 'Stamp',
      ),
      cacheInvalidationSink: widget.cacheInvalidationSink,
    );
    if (landed.isEmpty) {
      // No cel named, or nothing of the piece inside the selection: nothing
      // lands, nothing undoes.
      return;
    }
    // What landed, cut as it landed — the pixels 확정 lays down again
    // ([LastStrokeSlot]): the cel you stand on's share when it took one.
    // ⛔The stamp is the one drawing verb that does not pass
    // [_commitSourceStroke], so it is the one that records itself.
    final standing = coordinator.frameStore.canonicalKeyOf(
      coordinator.activeFrameKey,
    );
    widget.lastStroke?.hold(
      BrushStrokeCommitData(
        sourceDabs: [(landed[standing] ?? landed.values.first).dab],
        blendMode: blend,
      ),
    );
    setState(() {
      final landings = [for (final cel in landed.values) cel.landing];
      final historyManager = widget.historyManager;
      if (historyManager == null) {
        // Headless hosts (focused tests): land raw.
        for (final landing in landings) {
          landing.execute();
        }
        return;
      }
      historyManager.executeAsOneStep('Stamp', landings);
    });
    // ⛔The ghost is not asked again here: the rebuild above asks, as an
    // undo's does ([_askTheGhostAgain]) — one road for every write under
    // it. ↩️It was asked here, a count of stamps landed in its shape: an
    // undo, or a verb pressed on the timeline, left it showing a cel that
    // was gone.
  }

  /// The ground a press reads, and the ghost with it: the host's
  /// ([BrushCanvasPanel.pieceGround]) — or, with no session behind this
  /// panel, the cel you stand on, when it can be drawn on, through what
  /// this panel holds.
  PieceGround _pieceGround(BrushFrameEditingCoordinator coordinator) =>
      widget.pieceGround?.call() ??
      PieceGround(
        cels: [
          if (widget._editableCoordinator != null) coordinator.activeFrameKey,
        ],
        placementOf:
            widget.cellPlacementOf ?? (_) => widget.interactiveContentPose,
        selection: widget.selectionCommands?.region,
        options:
            widget.selectionMaskOptions?.value ?? SelectionMaskOptions.none,
      );

  /// 확정's normal-state half: the last drawing action, laid down again at
  /// the same place on the cel you stand on — one step, one undo
  /// (confirm-button, 유저 2026-09-24).
  ///
  /// ⛔It goes through [_commitSourceStroke] like any stroke, so the live
  /// selection clips it and the history takes it the way it takes a stroke.
  void _reinputLastStroke() {
    final stroke = widget.lastStroke?.stroke;
    if (stroke == null) {
      return;
    }
    if (widget._editableCoordinator != null) {
      _commitSourceStroke(stroke);
      return;
    }
    // No cel to lay it on: the door a stroke on an empty cell takes — the
    // auto frame makes one, or the shell says why not.
    if (!(widget.onStrokeNeedsCel?.call() ?? false)) {
      return;
    }
    // ⚠️A frame apart, for the reason the press that makes its cel waits
    // (`_BrushEditCelPress`): the block exists now, and the rebuild that
    // stands this canvas on it comes after. The block and the stroke still
    // land as ONE undo — the stroke takes the block as its prefix — and a
    // block no stroke claimed keeps its own (I-10).
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted && widget._editableCoordinator != null) {
          _commitSourceStroke(stroke);
        }
        widget.onAutoFrameSettled?.call();
      })
      ..ensureVisualUpdate();
  }

  void _commitSourceStroke(BrushStrokeCommitData rawStrokeData) {
    // Only reachable from a stroke the interactive canvas began, and it
    // begins one only on a cel whose row takes strokes — the two halves
    // [_editableCoordinator] asks. ↩️F-196: the view used to hear only the
    // cel half, so a lane's stroke reached this and threw.
    final coordinator = widget._editableCoordinator!;
    final strokeData = _selectionSeat.clipStrokeToSelection(
      rawStrokeData,
      surface: coordinator.currentSurfaceOf(coordinator.activeFrameKey),
    );
    if (strokeData == null) {
      // Entirely outside the selection: nothing lands, nothing undoes.
      // The live overlay already showed it clipped, so the pen-up is
      // simply the overlay clearing.
      setState(() {});
      return;
    }
    // What landed, clipped as it landed — the pixels 확정 lays down again.
    // ⛔Here, for every verb that comes down this funnel: each passes this
    // line, so none can be the one that forgets to record itself. The one
    // drawing verb that lands elsewhere — the cut tool's stamp, through the
    // piece door — records at its own ([_landStamp]).
    widget.lastStroke?.hold(strokeData);
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
      // ⚠️The prefix ALREADY RAN at pen-down and re-running it is a
      // no-op: `UpdateLayerTimelineCommand` holds its before/after from
      // construction, so applying `after` twice writes the same layer. The
      // stroke runs for the first time here, into the block that prefix
      // made.
      historyManager.executeAsOneStep('Draw on a new frame', [
        ?widget.takeStrokePrefixCommand?.call(),
        stroke,
      ]);
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
  /// 🗣️F-209 (유저 2026-09-28): 「도킹시 스크롤바는 어차피 창 최대크기로
  /// 되어있으니까 그냥 알약이아니라 패널로서 공간 차지해서? 두자. 뒤에 캔버스
  /// 안보이게 되도 되니까」 — and the two capsules that F-201 stretched along
  /// their whole edges (「도킹된 패널은 스크롤바 알약 최대치로 늘리자 길이」)
  /// crossed at the corner (「가로 세로 스크롤바끼리 오른쪽끝에서 서로
  /// 겹치니까 안겹치도록」). A DOCKED panel's panbars are its own lanes now,
  /// flush with its right and bottom edges and meeting at a corner square of
  /// neither's. The artwork runs on behind them, and framing keeps out from
  /// under them as it does from under a panel (`_framingInsets`). A lane in
  /// a column of its own is [lane] wide.
  static EdgeInsets dockedLanesOf(double lane) =>
      EdgeInsets.only(right: lane, bottom: lane);

  /// 🗣️(유저 2026-09-30): 「판정을 알약까지 포함해서 판정. 타임시트 최대
  /// 스크롤기준이나 캔버스 재생시나 그런거」 — the pill is part of what hides
  /// the artwork, on the floor and docked alike: the band it floats in
  /// across the top edge, its margin above it and below, is cover to every
  /// frame the panel makes (Fit, playback's fit, a limit's window, the
  /// middle a zoom holds). ↩️It was a see-through capsule for a day
  /// (F-209); the user took that back for this.
  static double pillBandIn(BuildContext context) =>
      _capsuleBand(_CanvasViewportBottomBar.heightIn(context));

  /// The band a capsule floats in along the edge it rides: its own
  /// [thickness], with [_capsuleMargin] on either side of it.
  static double _capsuleBand(double thickness) =>
      _capsuleMargin + thickness + _capsuleMargin;

  /// What [transport] hides of the artwork's bottom edge — a docked panel's
  /// band and the rule over it; the floor's capsule, its margin on either
  /// side, and whatever lies on that edge under it ([floorOverlay]).
  /// Nothing with no transport.
  ///
  /// 🗣️A book's page turner is cover as a movie's player is — what F-346
  /// asked of it where it stood on the left edge (유저 2026-10-12: 「왼쪽
  /// 알약도 동일하게 하나의 기준? 아무튼 그쪽도 이동가능해야하는 부분으로서
  /// 판정하도록」): zoomed in, the view goes on until the paper's edge stands
  /// above the band.
  ///
  /// ⚠️The floor's overlay — the collapsed row — frames nothing by itself
  /// ([BrushCanvasPanel.floorBottomOverlaySpan]): it is see-through, and
  /// the picture does not move for it. The capsule standing ON it is not
  /// see-through, so with a transport the cover reaches from the edge up.
  static double transportCover(
    CanvasTransportBand? transport, {
    required bool onFloor,
    double floorOverlay = 0,
  }) {
    if (transport == null) {
      return 0;
    }
    return onFloor
        ? floorOverlay + _capsuleBand(transport.height)
        : transport.height + _transportRule;
  }

  /// The hairline between a docked panel's lanes and the band under them.
  static const double _transportRule = 1;

  /// 🗣️F-346 (유저 2026-10-12): 「왼쪽알약도 동일하게 하나의 기준? 아무튼
  /// 그쪽도 이동가능해야하는 부분으로서 판정하도록」 — what stands on the left
  /// edge is cover as the pill is ([pillBandIn]): the band it floats in down
  /// that edge, its margin either side. Zoomed in, the view goes on until
  /// the paper's left edge stands beside it. Nothing with nothing there.
  /// ↩️Asked of the page strip; the brush pill took the edge (I-34).
  static double leftPillBandOf(CanvasEdgePill? pill) =>
      pill == null ? 0 : _capsuleBand(pill.width);

  const _CanvasEditorPanelShell({
    required this.child,
    required this.bottomBar,
    required this.rightStripBar,
    required this.horizontalStripBar,
    required this.cover,
    required this.onFloor,
    required this.lane,
    this.transport,
    this.leftPill,
    this.documentName,
    this.documentAbsent = false,
    this.bottomOverlaySpan = 0,
    this.leftRailBand,
    this.rightRailBand,
    required this.onLeftPillLaidOut,
  });

  final Widget child;
  final Widget bottomBar;
  final Widget rightStripBar;

  /// Whether this panel is the FLOOR under the others — the canvas or the
  /// viewer — rather than a panel docked in a rail ([dockedLanesOf]).
  final bool onFloor;

  /// How thick its panbars are — the floor's capsule across, a docked
  /// panel's lane: the seat's ([AppScrollbarLaneScope], F-440).
  final double lane;

  /// The horizontal panbar: its own capsule on the floor's bottom edge, its
  /// own lane on a docked panel's.
  final Widget horizontalStripBar;

  /// See [BrushCanvasPanel.transport] — null means nothing under the bars.
  final CanvasTransportBand? transport;

  /// See [BrushCanvasPanel.leftPill] — null means nothing on the left edge.
  final CanvasEdgePill? leftPill;

  /// Told whether the left pill was laid out past the left rail
  /// ([_LeftEdgeSeat]).
  final ValueChanged<bool> onLeftPillLaidOut;

  /// See [BrushCanvasPanel.documentName].
  final String? documentName;

  /// See [BrushCanvasPanel.documentAbsent].
  final bool documentAbsent;

  double get _transportCover => transportCover(
    transport,
    onFloor: onFloor,
    floorOverlay: bottomOverlaySpan,
  );

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

  /// The vertical bands the rails on the two side edges occupy — see
  /// [BrushCanvasPanel.floorLeftRailBand].
  final CanvasFloorBand? leftRailBand;
  final CanvasFloorBand? rightRailBand;

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

  /// What a scrollbar capsule spans — only the floor has capsules — as a
  /// share of the edge it rides: clamped, because the point of a capsule is
  /// that it says where you are and lets you drag back, not that it maps
  /// the whole pasteboard. A docked panel's bars are lanes ([dockedLanesOf]).
  static const double _capsuleTrackFraction = 0.34;
  static const double _capsuleTrackMin = 80;

  static const double _capsuleTrackMax = 260;

  static double _capsuleTrack(double edge) {
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
        // Nothing shows through — the canvas lays its backdrop over the
        // whole box as the screen shows it, over THIS ground
        // ([backdropOnScreen], F-114) — but the floor is the one surface
        // with no panel behind it, so it states its own floor colour rather
        // than borrowing whatever the route happens to be sitting on. One
        // answer for it ([stageGroundOf]): the film and the fade's wash lay
        // the backdrop over the same ground.
        Positioned.fill(child: ColoredBox(color: stageGroundOf(context))),
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
        if (onFloor)
          _floorCapsules()
        else
          ..._dockedLanes(colorScheme),
        if (documentName != null || leftPill != null) _leftEdge(context),
        Positioned(
          // The pill answers the same way the horizontal bar does (유저,
          // R4): it holds the window's centre across the axis it sits on,
          // and yields only on the axis that would bury it — the region
          // docked on TOP is above it, a rail beside it is not. On a docked
          // panel it floats over what the lanes and the transport leave.
          left: 0,
          top: cover.top,
          right: onFloor ? 0 : lane,
          bottom: cover.bottom + (onFloor ? 0 : lane + _transportCover),
          child: _FloatingCanvasControls(
            children: [
              // THE PILL, at the TOP CENTRE (유저, R3 #6).
              //
              // ⛔It used to take the top corner away from the tool strip
              // (R2 #14), which needed a rule about which hand the strip was
              // under and an InheritedWidget to publish the answer. Centred,
              // there is no side to choose, and the pill is the same
              // distance from either hand.
              //
              // It sits ON the top edge now rather than one lane below it:
              // the horizontal panbar used to own that edge and has moved to
              // the bottom, so the row it was making way for is gone. Still
              // NOT the timeline's edge, for the old reason — that edge
              // moves on every resize and every threshold switch, and
              // 좌우반전 gets pressed dozens of times an hour.
              Positioned(
                left: _capsuleMargin,
                top: _capsuleMargin,
                right: _capsuleMargin,
                child: Align(
                  alignment: Alignment.topCenter,
                  // BOUNDED on purpose: an unbounded pill would offer itself
                  // everything, keep every control and overflow. The
                  // shedding is the whole reason it is measured. The bound
                  // is the two edges it is pinned between — the Align hands
                  // the pill what they leave, and nothing more.
                  //
                  // 🚨I-57 (10-13): it was a LayoutBuilder measuring the
                  // window to bound the pill a second time with the same
                  // number. A builder runs again whenever the panel is
                  // built, and its layout repainted the whole shell — the
                  // pill, its swatches and readouts, the panbars — on every
                  // notify and every cut crossed, for a pill that had not
                  // changed. (The bound was the builder's job when the pill
                  // sat in a Row, which hands its children no width.)
                  //
                  // There is no floor under which the pill disappears.
                  // There used to be — below 190px it stood down, on the
                  // reading that a capsule around an empty row says
                  // nothing. With the docked bar gone the row is never
                  // empty: Fit is in it at every width, and the panel narrow
                  // enough to have lost the pill is the one that needed it
                  // most.
                  child: CanvasCapsule(
                    keyValue: 'canvas-view-pill',
                    height: _CanvasViewportBottomBar.heightIn(context),
                    child: bottomBar,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The floor's panbars, in capsules. THE PANBARS ARE FURNITURE — but
  /// furniture in a room, not in the wall.
  ///
  /// 🆕유저, R3 #5·#6, and it is the third pass over this: the bars now
  /// CENTRE ON WHAT YOU CAN SEE. Both are placed inside the visible
  /// rectangle rather than the panel's — the vertical one at the middle
  /// of the visible HEIGHT (so docking the region at the bottom walks
  /// it up, which is what "하단패널이 열린거에 따라 중앙계산" asked back),
  /// the horizontal one at the middle of the visible WIDTH, on the
  /// BOTTOM edge (패널열리면 위치바뀌는거 허용).
  ///
  /// ★And the vertical bar only steps IN from the edge when the rail is
  /// actually beside it. A rail panel is as tall as it was left at, so
  /// a short one covers a band, not an edge: stepping in for the whole
  /// edge left the bar hanging in the middle of nothing.
  ///
  /// 🚨I-57 (10-13): each bar is SEATED where it is laid out
  /// ([_FloorVerticalBarSeat], [_FloorHorizontalBarSeat]). They were
  /// measured in a LayoutBuilder, and a builder runs again whenever the
  /// panel is built: its layout repainted the shell — the pill and
  /// everything on it — on every notify and every cut crossed, for bars
  /// that had not moved.
  Widget _floorCapsules() => Positioned.fill(
    child: Stack(
      children: [
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _FloorVerticalBarSeat(
              cover: cover,
              bottomCover: _transportCover,
              railBand: rightRailBand,
              lane: lane,
            ),
            child: CanvasCapsule(
              keyValue: 'canvas-panbar-vertical',
              width: lane,
              child: rightStripBar,
            ),
          ),
        ),
        // ⑩: …and above whatever lies ON the artwork at that edge. The
        // collapsed row frames nothing, so it is not in `cover` — but it is
        // exactly where this bar was, which is what the user saw. The
        // transport lies under the bar ([_floorTransportCapsule]), so the
        // bar stands on it.
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _FloorHorizontalBarSeat(
              bottom: _floorBarBottom,
              lane: lane,
            ),
            child: CanvasCapsule(
              keyValue: 'canvas-panbar-horizontal',
              height: lane,
              child: horizontalStripBar,
            ),
          ),
        ),
        if (transport case final transport?) _floorTransportCapsule(transport),
      ],
    ),
  );

  /// How far up the floor's bottom edge the horizontal bar's capsule
  /// stands: over what covers that edge, and over the transport when there
  /// is one.
  double get _floorBarBottom =>
      cover.bottom +
      bottomOverlaySpan +
      _capsuleMargin +
      (transport == null ? 0 : transport!.height + _capsuleMargin);

  /// The floor's transport, in a capsule under the horizontal bar — as wide
  /// as what the side panels leave.
  ///
  /// ⚠️It yields ALONG its edge too, where the pill and the bar hold the
  /// window's centre: those are small and stay clear of a rail, and a band
  /// this wide would have its ends — where the playhead reads and the sound
  /// is — under one.
  Positioned _floorTransportCapsule(
    CanvasTransportBand transport,
  ) => Positioned(
    left: cover.left + _capsuleMargin,
    right: cover.right + _capsuleMargin,
    bottom: cover.bottom + bottomOverlaySpan + _capsuleMargin,
    child: CanvasCapsule(
      keyValue: 'canvas-transport',
      height: transport.height,
      child: transport.child,
    ),
  );

  /// What stands on the left edge, seated together ([_LeftEdgeSeat]): the
  /// file's name ([_CanvasDocumentName]) and the left pill over it.
  Widget _leftEdge(BuildContext context) => Positioned.fill(
    child: CustomMultiChildLayout(
      delegate: _LeftEdgeSeat(
        cover: cover,
        onFloor: onFloor,
        top: cover.top + pillBandIn(context),
        nameBottom: onFloor
            ? _floorBarBottom + lane + _capsuleMargin
            : _transportCover + lane + _capsuleMargin,
        nameRight: (onFloor ? cover.right : lane) + _capsuleMargin,
        railBand: leftRailBand,
        onPillLaidOut: onLeftPillLaidOut,
      ),
      children: [
        if (documentName case final name?)
          LayoutId(
            id: _LeftEdgeSlot.name,
            child: _CanvasDocumentName(name, absent: documentAbsent),
          ),
        if (leftPill case final pill?)
          LayoutId(
            id: _LeftEdgeSlot.pill,
            // ★Its own layer: its bars repaint through every frame of a
            // drag, and without a boundary each one re-records the
            // furniture around it — the pill, the panbars — that has not
            // changed (I-57's lesson about this shell).
            child: RepaintBoundary(
              key: const ValueKey<String>('canvas-left-pill'),
              // A panel shorter than the pill gets the whole pill, smaller
              // — never a column that overflows, and never one missing a
              // control: the page strip's law on this edge, and the page
              // turner's under the bars.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: pill.child,
              ),
            ),
          ),
      ],
    ),
  );

  /// A docked panel's panbars ([dockedLanesOf]): each bar in a lane of its
  /// own, flush with its edge, and the corner between them left to neither.
  /// Each lane is ringed on its artwork side in the backdrop, for the
  /// capsule's reason ([CanvasCapsule]). The transport of a document that runs
  /// is a band under them, ruled off the same way.
  List<Widget> _dockedLanes(ColorScheme colorScheme) {
    final ring = BorderSide(color: AppColors.backdrop);
    Widget strip(String keyValue, Border ringed, [Widget? bar]) => DecoratedBox(
      key: ValueKey<String>(keyValue),
      decoration: BoxDecoration(color: colorScheme.surface, border: ringed),
      child: bar,
    );
    return [
      Positioned(
        top: 0,
        right: 0,
        bottom: lane + _transportCover,
        width: lane,
        child: strip(
          'canvas-panbar-vertical',
          Border(left: ring),
          rightStripBar,
        ),
      ),
      Positioned(
        left: 0,
        right: lane,
        bottom: _transportCover,
        height: lane,
        child: strip(
          'canvas-panbar-horizontal',
          Border(top: ring),
          horizontalStripBar,
        ),
      ),
      Positioned(
        right: 0,
        bottom: _transportCover,
        width: lane,
        height: lane,
        child: strip('canvas-panbar-corner', const Border()),
      ),
      if (transport case final transport?)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _transportCover,
          child: strip(
            'canvas-transport',
            Border(top: ring),
            Padding(
              padding: const EdgeInsets.only(top: _transportRule),
              child: transport.child,
            ),
          ),
        ),
    ];
  }

}

/// The file's name on a see-through plate ([BrushCanvasPanel.documentName]),
/// at the lower left of the room it is given and never wider than it.
///
/// A plate, not a control: it takes no pointer, so a press on it is the
/// canvas's.
class _CanvasDocumentName extends StatelessWidget {
  const _CanvasDocumentName(this.name, {required this.absent});

  final String name;

  /// See [BrushCanvasPanel.documentAbsent].
  final bool absent;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Align(
      alignment: Alignment.bottomLeft,
      child: DecoratedBox(
        key: const ValueKey<String>('canvas-document-name'),
        decoration: ShapeDecoration(
          color: AppColors.backdrop.withValues(alpha: 0.62),
          shape: AppShapes.container(AppShapes.wellRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(
              color: absent
                  ? AppColors.text.withValues(alpha: AppColors.offAlpha)
                  : AppColors.text,
            ),
          ),
        ),
      ),
    ),
  );
}

/// What stands on the left edge ([_LeftEdgeSeat]).
enum _LeftEdgeSlot { name, pill }

/// Seats what stands on the LEFT edge: the file's name at the artwork's
/// lower left ([BrushCanvasPanel.documentName]) — over the horizontal bar
/// and inside what the side panels leave — and the left pill
/// ([BrushCanvasPanel.leftPill]) in the middle of the room between the
/// pill's band and the name.
///
/// The axis law the two bars follow (유저, R4): ALONG the edge it rides the
/// left pill holds the room's centre, and ACROSS that edge it sits on the
/// edge — past the left rail where the rail's band is beside it, as the
/// vertical bar steps past the right one ([_FloorVerticalBarSeat]): under
/// a rail nothing on it could be reached, and a control that steps aside
/// for a panel nowhere near it reads as floating (유저, R3 #5). It was the
/// page strip's seat on this edge, gone with the strip under the bars
/// (F-383). It reports which it did, for framing (`_framingInsets`).
///
/// The room ends over the name (I-34): a column this tall would otherwise
/// stand on it. With no name written it ends where the name would stand.
class _LeftEdgeSeat extends MultiChildLayoutDelegate {
  _LeftEdgeSeat({
    required this.cover,
    required this.onFloor,
    required this.top,
    required this.nameBottom,
    required this.nameRight,
    required this.railBand,
    required this.onPillLaidOut,
  });

  /// See [_CanvasEditorPanelShell.cover].
  final EdgeInsets cover;

  /// See [_CanvasEditorPanelShell.onFloor].
  final bool onFloor;

  /// How far down the box the room starts: under the pill's band.
  final double top;

  /// How far up the box the name stands.
  final double nameBottom;

  /// How far in from the right edge the name may run.
  final double nameRight;

  /// See [_CanvasEditorPanelShell.leftRailBand].
  final CanvasFloorBand? railBand;

  final ValueChanged<bool> onPillLaidOut;

  static const double _margin = _CanvasEditorPanelShell._capsuleMargin;

  @override
  void performLayout(Size size) {
    final nameLeft = (onFloor ? cover.left : 0) + _margin;
    var roomBottom = size.height - nameBottom;
    if (hasChild(_LeftEdgeSlot.name)) {
      final name = layoutChild(
        _LeftEdgeSlot.name,
        BoxConstraints(
          maxWidth: math.max(0.0, size.width - nameLeft - nameRight),
        ),
      );
      positionChild(
        _LeftEdgeSlot.name,
        Offset(nameLeft, roomBottom - name.height),
      );
      roomBottom -= name.height + _margin;
    }
    if (!hasChild(_LeftEdgeSlot.pill)) {
      return;
    }
    final room = math.max(0.0, roomBottom - top);
    final pill = layoutChild(
      _LeftEdgeSlot.pill,
      BoxConstraints(maxHeight: room),
    );
    final pillTop = top + (room - pill.height) / 2;
    final beside = canvasFloorBandIntrudes(
      railBand,
      top: pillTop,
      bottom: pillTop + pill.height,
    );
    onPillLaidOut(beside);
    positionChild(
      _LeftEdgeSlot.pill,
      Offset((beside ? cover.left : 0) + _margin, pillTop),
    );
  }

  @override
  bool shouldRelayout(_LeftEdgeSeat oldDelegate) =>
      oldDelegate.cover != cover ||
      oldDelegate.onFloor != onFloor ||
      oldDelegate.top != top ||
      oldDelegate.nameBottom != nameBottom ||
      oldDelegate.nameRight != nameRight ||
      oldDelegate.railBand != railBand;
}

/// Seats the floor's vertical panbar in the middle of the visible HEIGHT,
/// on the right edge — past the right rail when the rail is beside it —
/// as long as that height allows ([_CanvasEditorPanelShell._capsuleTrack]).
///
/// The capsule's corner follows the lane it stands in, its stated axis.
class _FloorVerticalBarSeat extends SingleChildLayoutDelegate {
  const _FloorVerticalBarSeat({
    required this.cover,
    required this.bottomCover,
    required this.railBand,
    required this.lane,
  });

  /// See [_CanvasEditorPanelShell.cover].
  final EdgeInsets cover;

  /// See [_CanvasEditorPanelShell.lane].
  final double lane;

  /// What the transport hides of the bottom edge, past [cover]
  /// ([_CanvasEditorPanelShell.transportCover]).
  final double bottomCover;

  /// See [_CanvasEditorPanelShell.rightRailBand].
  final CanvasFloorBand? railBand;

  static const double _margin = _CanvasEditorPanelShell._capsuleMargin;

  double _visibleBottom(double height) =>
      math.max(cover.top, height - cover.bottom - bottomCover);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: lane,
        height: _CanvasEditorPanelShell._capsuleTrack(
          _visibleBottom(constraints.maxHeight) - cover.top,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final track = childSize.height;
    final centre = (cover.top + _visibleBottom(size.height)) / 2;
    final barTop = centre - track / 2;
    final intrudes = canvasFloorBandIntrudes(
      railBand,
      top: barTop,
      bottom: barTop + track,
    );
    final right = intrudes ? cover.right + _margin : _margin;
    return Offset(size.width - right - childSize.width, barTop);
  }

  @override
  bool shouldRelayout(_FloorVerticalBarSeat oldDelegate) =>
      oldDelegate.cover != cover ||
      oldDelegate.bottomCover != bottomCover ||
      oldDelegate.railBand != railBand ||
      oldDelegate.lane != lane;
}

/// Seats the floor's horizontal panbar on the bottom edge, [bottom] up it,
/// as long as the panel's width allows
/// ([_CanvasEditorPanelShell._capsuleTrack]).
///
/// 🆕유저 (R4): 가로스크롤바나 알약은 그냥 양옆에서 펼치든말든 중앙에. The
/// two axes are NOT the same question, and the answer differs by axis
/// rather than by widget:
///
///  * ALONG the edge it rides, the bar holds the window's centre. A side
///    panel opening is not a reason for the thing you read to walk
///    sideways — that is the 「읽는 것은 안 움직인다」 rule, and the
///    earlier pass over-applied "centre on what you can see" to it.
///  * ACROSS that edge it still yields, because there it is not a matter
///    of taste: a bar on the bottom edge with the region docked below
///    would be UNDER it.
///
/// The capsule's corner follows the lane it stands in, its stated axis.
class _FloorHorizontalBarSeat extends SingleChildLayoutDelegate {
  const _FloorHorizontalBarSeat({required this.bottom, required this.lane});

  /// How far up the bottom edge the bar stands
  /// ([_CanvasEditorPanelShell._floorBarBottom]).
  final double bottom;

  /// See [_CanvasEditorPanelShell.lane].
  final double lane;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: _CanvasEditorPanelShell._capsuleTrack(constraints.maxWidth),
        height: lane,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (size.width - childSize.width) / 2,
    size.height - bottom - childSize.height,
  );

  @override
  bool shouldRelayout(_FloorHorizontalBarSeat oldDelegate) =>
      oldDelegate.bottom != bottom || oldDelegate.lane != lane;
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
  static const double height = CanvasCapsule.barPillHeight;

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

  /// The two [DragValueLabel]s' widths — what the WIDEST number each can
  /// write needs, since F-122 has them write every digit the view has.
  ///
  /// 🧪Measured in the app's own face (BIZ UDPGothic, 2026-09-17): `1600.00%`
  /// at 12px is 68.9px and `-179.99°` at 11px is 52.9px, and the theme's
  /// body letter spacing (0.25 a glyph) adds 2px to each. ⚠️The 44 that
  /// stood here was already short of a plain `1600%` (46.9px). The test font
  /// cannot tell — every glyph in it is a square — so the pin loads the real
  /// one: `test/ui/brush/the_pill_readouts_fit_their_boxes_test.dart`.
  static const double _zoomReadoutWidth = 74;
  static const double _rotationReadoutWidth = 58;

  /// The readouts' type — the pill's only words (`1:1` is a glyph in an
  /// icon slot, see [_BottomBarBuild._resetButton]).
  static const double _zoomReadoutFontSize = 12;
  static const double _rotationReadoutFontSize = 11;

  /// 🚨text-scale-fixed-height-bars (유저 2026-09-18, 「막대가 글자 크기를
  /// 따라 자란다」). The widths above are what the widest numbers need at 1×;
  /// where the pill is shown they are what those numbers MEASURE, never
  /// less. 🔬At 1.5× in the app's face `100.00%` wrapped inside its 74.
  static double _widestIn(
    BuildContext context,
    double fontSize,
    String Function(String digit) number,
    double drawnAt,
  ) => math.max(
    drawnAt,
    TextMeasure(
      context,
      DefaultTextStyle.of(context).style.copyWith(fontSize: fontSize),
    ).widest(everyDigitIn(number)).ceilToDouble(),
  );

  static double zoomReadoutWidthIn(BuildContext context) => _widestIn(
    context,
    _zoomReadoutFontSize,
    (d) => '1$d$d$d.$d$d%',
    _zoomReadoutWidth,
  );

  static double rotationReadoutWidthIn(BuildContext context) => _widestIn(
    context,
    _rotationReadoutFontSize,
    (d) => '-1$d$d.$d$d°',
    _rotationReadoutWidth,
  );

  /// The pill where it is shown: [height] plus a readout line's growth.
  static double heightIn(BuildContext context) =>
      height +
      TextMeasure(
        context,
        DefaultTextStyle.of(
          context,
        ).style.copyWith(fontSize: _zoomReadoutFontSize),
      ).lineGrowthOf(TextMeasure.everyScript);
  static const double _swatchWidth = 18; // ColorSwatchButton.diameter
  static const double _swatchGap = 4;
  static const double _dividerWidth = 13; // 1px rule, 6px margin each side
  static const double _gearWidth = 28; // 16px glyph + 6px padding each side
  static const double _pillEnds = 2 * CanvasCapsule.barPillEnd;

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
    this.oneToOneOnPill = false,
    this.drivenByViewKeys = false,
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
    required this.pasteboardSize,
    required this.pasteboardInUse,
    required this.onPasteboardSizeChanged,
    required this.onPasteboardInUseChanged,
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

  /// [BrushCanvasPanel.oneToOneOnPill]: the 1:1 starts on the pill, as the
  /// floor's does, wherever the panel stands.
  final bool oneToOneOnPill;

  /// Whether the view KEYS drive this canvas — its panel holds the
  /// [BrushCanvasPanel.viewCommands] the key funnel calls (I-40). Only then
  /// do its view buttons name their keys: on any other canvas the same key
  /// moves the editor's canvas, not this one ([_viewKeys]).
  final bool drivenByViewKeys;

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

  /// The pasteboard's size and whether it is there (I-109), set in its
  /// colour window; the setters are null where this bar sets neither.
  final PasteboardSize pasteboardSize;
  final bool pasteboardInUse;
  final ValueChanged<PasteboardSize>? onPasteboardSizeChanged;
  final ValueChanged<bool>? onPasteboardInUseChanged;
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
      shortcuts: _viewKeys(shortcuts),
    );
  }

  /// [actions], where this canvas is the one their keys drive
  /// ([drivenByViewKeys]) — nothing anywhere else.
  List<String> _viewKeys(List<String> actions) =>
      drivenByViewKeys ? actions : const [];
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
    this.limit,
    required this.onViewportChanged,
    this.onViewportChangeEnd,
    this.enabled = true,
  });
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;
  final ({Rect rect, Rect window})? limit;
  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback? onViewportChangeEnd;
  final bool enabled;
  @override
  Widget build(BuildContext context) => _CanvasViewportPanbar(
    axis: Axis.horizontal,
    viewport: viewport,
    editorViewportSize: editorViewportSize,
    canvasSize: canvasSize,
    limit: limit,
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
    this.limit,
    required this.onViewportChanged,
    this.onViewportChangeEnd,
    this.enabled = true,
  });
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;
  final ({Rect rect, Rect window})? limit;
  final ValueChanged<CanvasViewport> onViewportChanged;
  final VoidCallback? onViewportChangeEnd;
  final bool enabled;
  @override
  Widget build(BuildContext context) => _CanvasViewportPanbar(
    axis: Axis.vertical,
    viewport: viewport,
    editorViewportSize: editorViewportSize,
    canvasSize: canvasSize,
    limit: limit,
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
    required this.limit,
    required this.onViewportChanged,
    this.onViewportChangeEnd,
    required this.enabled,
  });
  final Axis axis;
  final CanvasViewport viewport;
  final Size editorViewportSize;
  final CanvasSize canvasSize;

  /// The view's limit and its window — the span the bar covers (F-201).
  final ({Rect rect, Rect window})? limit;
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
      limit: limit,
    );
    return sizedAlong(
      axis,
      key: ValueKey<String>(
        isHorizontal
            ? 'canvas-viewport-horizontal-scrollbar'
            : 'canvas-viewport-vertical-scrollbar',
      ),
      along: double.infinity,
      across: AppScrollbarLaneScope.of(context),
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

/// The stage's outer planes behind the artwork (R3b): the backdrop with
/// the pasteboard over it, both RGBA (F-114), and the checkerboard
/// wherever one of them is ABSENT — laid as every cut seen through no
/// camera lays them ([StagePlanesPainter], where the laws of where each
/// plane lies live). The backdrop goes down as the screen shows it, over
/// the panel's ground ([backdropOnScreen]), as the film's floor does.
///
/// 🪦It used to subscribe to an ALPHA-PREVIEW toggle in the settings menu,
/// which replaced BOTH planes with the checkerboard. 유저 2026-09-16: 「설정의
/// 알파 미리보기 필요없어졌으니 잔재 싹 삭제」 — an absent plane already says
/// the same thing in the place it means it ([StagePlanesPainter], F-114).
class _StagePlanes extends StatelessWidget {
  const _StagePlanes({
    required this.backdropArgb,
    required this.pasteboardArgb,
    required this.backdropNone,
    required this.pasteboardNone,
    required this.pasteboardReach,
    required this.hasPasteboard,
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

  /// How far the pasteboard plane reaches past the paper (I-109).
  final PasteboardReach pasteboardReach;

  /// False on a [BrushCanvasPanel.canvasBase] panel.
  final bool hasPasteboard;
  final bool paperNone;
  final CanvasSize canvasSize;
  final CanvasViewport viewport;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: StagePlanesPainter(
        backdrop: backdropOnScreen((
          color: stageColorOnScreen(backdropArgb),
          none: backdropNone,
        ), stageGroundOf(context)),
        pasteboard: hasPasteboard
            ? (color: stageColorOnScreen(pasteboardArgb), none: pasteboardNone)
            : null,
        pasteboardReach: pasteboardReach,
        paperNone: paperNone,
        canvasSize: canvasSize,
        viewport: viewport,
        devicePixelRatio: EffectiveDevicePixelRatio.of(context),
      ),
      child: child,
    );
  }
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
    required bool oneToOneOnPill,
    required bool hasLeading,
    required double colorsWidth,
    required bool hasViewControls,
    required double viewControlsWidth,
    required bool hostVerbsCanUnfold,
    required int hostVerbCount,
    required bool hostSettingsListed,
    required double zoomReadoutWidth,
  }) {
    // WHERE EACH GROUP STARTS. The floor lays them all out; every
    // other panel starts where a floor pill ENDS UP once it has run
    // out of room, and stays there however wide it gets — except a 1:1
    // the panel keeps out ([BrushCanvasPanel.oneToOneOnPill], F-315).
    var showColors = onFloor && colorsWidth > 0;
    var showViewControls = onFloor && hasViewControls;
    var showReset = onFloor || oneToOneOnPill;
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
            zoomReadoutWidth,
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

    // The floor holds the readout, so it widens by what the readout does.
    final cramped =
        room <
        _CanvasViewportBottomBar.pillMinWidth +
            (zoomReadoutWidth - _CanvasViewportBottomBar._zoomReadoutWidth) +
            owed;
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
