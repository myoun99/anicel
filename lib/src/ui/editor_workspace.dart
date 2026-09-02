import 'widgets/app_icon_button.dart';
import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../models/brush_group_id.dart';
import '../models/brush_preset.dart';
import '../models/brush_preset_id.dart';
import '../models/canvas_shape_kind.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/media_viewer_bookmark.dart' show MediaViewerBookmark;
import '../models/project.dart'
    show
        Project,
        defaultProjectBackdropArgb,
        defaultProjectPasteboardArgb,
        defaultProjectPasteboardMargin;
import '../models/project_id.dart' show ProjectId;
import '../models/layer_id.dart';
import '../models/media_asset.dart' show MediaAsset;
import '../services/brush_preset_file_service.dart';
import '../services/brush_tip_library_service.dart';
import '../services/canvas_color_sampler.dart' show CanvasColorSampleSource;
import '../services/commands/toggle_id_in_set_command.dart';
import '../services/canvas_flood_fill.dart' show FloodFillOptions;
import '../services/canvas_selection.dart' show SelectionMaskOptions;
import '../models/brush_tip_entry.dart';
import '../services/cut_piece_slot.dart';
import '../services/cut_piece_tip.dart';
import '../services/color_palette_file_service.dart' show ColorPaletteState;
import 'brush/brush_preset_library.dart';
import 'brush/canvas_floor_insets.dart';
import 'color/color_panels.dart' show ColorPickerKind, ColorPickerPanel;
import 'color/color_slot_pair.dart';
import 'theme/app_theme.dart';
import 'brush/brush_hand_settings_store.dart';
import 'brush/brush_preset_panel.dart';
import 'brush/brush_tip_library.dart';
import 'brush/brush_tool_state.dart';
import 'brush/canvas_selection_commands.dart';
import 'brush/transform_tool_options.dart';
import 'brush/canvas_view_commands.dart';
import 'brush/paint_tool_state_notifier.dart';
import 'brush/brush_canvas_defaults.dart';
import 'brush/guide_panels.dart';
import 'brush/tool_library_panel.dart';
import 'brush/tool_settings_panel.dart';
import 'brush/tools_panel.dart';
import 'editor_canvas_area.dart';
import 'editor_session_manager.dart';
import 'shortcuts/editor_action_registry.dart';
import 'export/export_frame_renderer.dart';
import 'export/export_plan.dart';
import 'import/import_dialog.dart';
import 'media/media_asset_drag_data.dart';
import 'media/media_asset_drop_target.dart';
import 'media/media_pool_panel.dart';
import 'media/media_relink_flow.dart';
import 'media/media_viewer_tab_host.dart';
import 'layout/device_grid.dart';
import 'layout/device_grid_scroll_controller.dart';
import 'widgets/app_window.dart' show AppWindowAction, AppWindowActionEmphasis;
import '../services/audio/conform_wav_export.dart';
import '../services/persistence/file_type_groups.dart';
import 'dialogs/folder_pick_flow.dart';
import 'dialogs/app_confirm_dialog.dart' show AppConfirmDialog, showAppNotice;
import 'panels/editor_dock_host.dart';
import 'panels/editor_panel_dock.dart';
import 'panels/editor_panel_layout.dart';
import 'panels/panel_flash.dart';
import 'panels/panel_visibility_scope.dart';
import 'panels/editor_panel_tabs.dart';
import 'panels/workspace_layout_store.dart';
import 'panels/workspace_panels_menu.dart';
import 'widgets/app_scrollbar.dart';
import 'widgets/static_raster.dart';
import 'widgets/superellipse_clip.dart';
import 'keyed_keep_alive_stack.dart';
import 'sliced_value_listenable_builder.dart';
import 'conte/conte_fonts.dart';
import 'conte/conte_ink.dart';
import 'conte/conte_tab_host.dart';
import '../models/envelope/cut_envelope_presets.dart';
import 'envelope/cut_envelope_ink.dart';
import 'envelope/cut_envelope_tab_host.dart';
import 'envelope/envelope_image_cache.dart';
import 'storyboard_cut_thumbnail_store.dart';
import 'storyboard_cut_blocks_painter.dart' show storyboardCutBlocksPainterFor;
import 'storyboard_panel.dart' show StoryboardPanel, StoryboardTrackLabelRow;
import 'storyboard_playhead_mapping.dart';
import '../models/timeline_row_address.dart';
import 'playback/canvas_playback_controller.dart' show PlaybackScope;
import 'timeline/collapsed_row_overlay.dart';
import 'timeline/timeline_grid_metrics.dart' show TimelineGridMetrics;
import 'timeline/timeline_cel_content_source.dart'
    show TimelineCelContentSource;
import 'timeline/timeline_frame_cells_row.dart' show TimelineFrameCellsRow;
import 'timeline/timeline_frame_cursor_layer.dart' show TimelineCursorLayer;
import 'timeline/timeline_frame_geometry.dart' show TimelineFrameGeometryHandle;
import 'timeline/timeline_lane_rows.dart' show TimelineLaneFrameRow;
import 'timeline/timeline_layer_controls_row.dart'
    show TimelineLayerControlsRow;
import 'timeline/frame_panel_sill_controls.dart';
import 'timeline/timeline_command_bar.dart' show TimelineCommandBar;
import 'timeline/layer_rail_window.dart';
import '../models/layer_kind.dart' show LayerKind, layerKindHoldsDrawings;
import 'canvas/flip_hud_controller.dart';
import 'canvas/flip_hud_model.dart';
import 'timeline/layer_timeline_display_adapter.dart'
    show horizontalLayerDisplayOrder;
import 'timeline/property_lane_model.dart'
    show TimelineDisplayRow, buildTimelineDisplayRows, parseLaneGroupKey;
import 'timeline/timeline_se_row_visual.dart' show layerKindUsesSeSheetCells;
import 'timeline/timeline_lane_provider.dart';
import 'timeline/timeline_layer_nav.dart';
import 'timeline/timeline_row_filter.dart';
import 'timeline/timeline_section_policy.dart';
import '../models/onion_skin_settings.dart';
import 'panels/onion_skin_panel.dart';
import 'panels/tool_size_preset_panel.dart';
import 'storyboard_tab_host.dart';
import '../models/canvas_viewport.dart';
import 'timeline/timeline_orientation.dart';
import 'timeline/timeline_panel.dart' show TimelinePanel;
import 'text/app_strings.dart';
import 'timeline_tab_host.dart';
import 'timesheet/timesheet_ink_controller.dart';
import 'timesheet_tab_host.dart';
import 'input/control_press_claim.dart';

part 'workspace/workspace_collapsed_rows.dart';
part 'workspace/workspace_docks.dart';
part 'workspace/workspace_layout_persistence.dart';
part 'workspace/workspace_tabs.dart';

/// The editor workspace: side docks and the canvas' center dock over the
/// bottom dock, plus the slim edge docks that home the PS/CSP-style tool
/// bar (left OR right — left-handed choice). Every panel, the canvas and
/// the tool bar included, is a tab in one dock section of an
/// [EditorPanelLayoutModel]; tabs drag between docks with Photoshop/AE
/// style drop feedback (hover lights up the region the panel would take),
/// docks resize via splitters, and the whole arrangement persists to the
/// app-data workspace file.
///
/// This widget is the COMMON OWNER of all dockable-panel view state (brush
/// tool, preset library, camera view, timeline view state): a panel keeps
/// working wherever its tab is docked. Hot values (slider drags, zooms) are
/// ValueNotifiers consumed per-tab, so dragging a brush slider never
/// rebuilds the timeline and vice versa; this widget itself only rebuilds
/// on layout changes.
class EditorWorkspace extends StatefulWidget {
  const EditorWorkspace({
    super.key,
    required this.session,
    this.presetFileService,
    this.tipLibraryService,
    this.brushFilePicker,
    this.layoutStore,
    this.panelsMenu,
    this.brushTool,
    this.colorBackground,
    this.colorPalette,
    this.onColorPaletteChanged,
    this.canvasViewCommands,
    this.canvasNavigationRegionKey,
    this.canvasSelectionCommands,
    this.layerNav,
    this.onInvokeAction,
    this.flipHud,
  });

  final EditorSessionManager session;

  /// The active-tool notifier, owned by the shell (HomePage) so the tool
  /// shortcuts (B/E) and the workspace panels drive one state. Null keeps
  /// a workspace-local notifier (focused widget tests).
  final PaintToolStateNotifier? brushTool;

  /// The BACK colour slot and the palette, owned by the shell alongside the
  /// tool state — the colour picker is a rail panel now (유저 확정: 컬러
  /// 창은 오른쪽 서브띠 맨 위로), so the workspace needs what used to go
  /// only to the top strip. Null keeps the picker out of the rail
  /// (focused widget tests).
  final ValueNotifier<int>? colorBackground;
  final ValueNotifier<ColorPaletteState>? colorPalette;
  final ValueChanged<ColorPaletteState>? onColorPaletteChanged;

  /// The shell-owned rotate/flip shortcut channel (P8, R/Shift+R/H),
  /// forwarded to the canvas panel.
  final CanvasViewCommands? canvasViewCommands;

  /// D13: the canvas panel's subtree key — forwarded to the canvas area,
  /// which attaches it to the panel container the actuation gate's
  /// navigation hole measures.
  final GlobalKey? canvasNavigationRegionKey;

  /// The shell-owned selection shortcut channel (P9, Ctrl+D + nudges).
  final CanvasSelectionCommands? canvasSelectionCommands;

  /// The shell-owned ↑/↓ layer-nav channel (UI-R20 #14): this state binds
  /// the handler because it owns the timeline view state (row filter,
  /// hidden sections) the displayed-row walk must respect.
  final TimelineLayerNavCommands? layerNav;

  /// PEN-7b: the shell's action funnel for the canvas flip touch slot.
  final void Function(String actionId)? onInvokeAction;

  /// The flip HUD's state (shell-owned). This state BINDS the snapshot
  /// supplier — the displayed rows are its view state, exactly as the
  /// ↑/↓ walk's are.
  final FlipHudController? flipHud;

  /// Injectable preset persistence; defaults to the app-data preset file.
  final BrushPresetFileService? presetFileService;

  /// Injectable tip-library storage; defaults to the app-data tip folder.
  final BrushTipLibraryService? tipLibraryService;

  /// Injectable workspace-layout persistence; defaults to the app-data
  /// layout file outside tests (`FLUTTER_TEST` disables it so widget tests
  /// never read a developer's saved arrangement).
  final WorkspaceLayoutStore? layoutStore;

  /// Injectable brush-file picker; defaults to the platform file dialog.
  final BrushFilePicker? brushFilePicker;

  /// The AppBar's Panels menu bridge: lists every panel with visibility
  /// and reopens closed (X-ed) ones.
  final WorkspacePanelsMenuController? panelsMenu;

  /// D37 (유저, 2026-08-17): a dock's size opens as a FRACTION of the
  /// window, not a fixed number of pixels.
  ///
  /// 🚨What is proportional is the DEFAULT and the CEILING — the stored
  /// value stays pixels. A dock the user has dragged to a width is a width
  /// they chose; making it track the window would move it under them every
  /// time they resize, which no editor does. The complaint was that 260
  /// was too narrow on a large monitor and too wide on a small one, and
  /// that the drag hit a ceiling too early. Both are answered here.
  ///
  /// 0.18 of the window ≈ the old 260 at 1440 wide, so a monitor near that
  /// size sees no change; it is the far ends that move.
  static const double sideDockWidthFraction = 0.18;

  /// Half the window (유저 원문: 「타임라인 세로 = 화면 절반」).
  static const double bottomDockHeightFraction = 0.5;

  /// 🚨결정 8 (유저 확정 2026-08-22) — **A RAIL'S CEILING IS A SHARE OF THE
  /// WINDOW, AND OF NOTHING ELSE.**
  ///
  /// > 「①**창 폭의 절반의 3/4** (=37.5%)」
  ///
  /// ⛔What stood here was `3/7 · rest`, where `rest` had the OTHER dock's
  /// current width taken out. That is a faithful reading of 「중간의 3/4」 and
  /// it is exactly what the user reported: 「한쪽 띠 크기를 바꿀 때 **반대쪽도
  /// 바뀐다**」. A ceiling that names the other side makes the two sides one
  /// quantity — every build re-derived the right from the already-clamped
  /// left, so equal stored widths drew unequal and dragging either moved
  /// both.
  ///
  /// ★A fraction of the WINDOW cannot do that. Two rails at 37.5% leave 25%
  /// for the centre, so they always fit and neither has to ask about the
  /// other. The user picked the number that makes the coupling unnecessary
  /// rather than the one that describes its result.
  static const double sideDockCeilingFraction = 0.375;

  /// The bottom dock's own ceiling — 「하단 = **화면 절반**까지」, the same
  /// sentence on the other axis.
  static const double bottomDockCeilingFraction = 0.5;

  /// ⚠️Fallbacks for a window whose size is not known yet (an unbounded
  /// host, a test harness that never lays out). Every path that HAS the
  /// extent uses the fractions above — see [sideDockWidthFor] and
  /// [bottomDockHeightFallbackFor].
  static const double bottomPanelHeight = 350;
  static const double sideDockWidth = 260;

  /// The side dock's opening width for a window [availableWidth] wide,
  /// landed on the device grid.
  ///
  /// ⛔Quantized HERE and not at the reader: a fraction of a window is a
  /// fraction of a pixel almost always (0.18 × 1366 = 245.88), and R11's
  /// whole chain rests on the boundaries between the docks being integral
  /// device positions.
  /// ⚠️Floored at the old fixed width, and the floor is load-bearing:
  /// 0.18 of an 800-wide window is 144, at which the timesheet's own pill
  /// folds its buttons away (measured — it turned a test red). A fraction
  /// is a claim about how a dock should GROW, not a licence to open one
  /// too narrow to use, so it only ever wins upward.
  static double sideDockWidthFor(double availableWidth, DeviceGrid grid) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return sideDockWidth;
    }
    return grid.position(
      math.max(availableWidth * sideDockWidthFraction, sideDockWidth),
    );
  }

  /// The bottom dock's opening height for a window [availableHeight] tall,
  /// landed on the device grid.
  ///
  /// ⚠️Floored the same way and for the same reason as
  /// [sideDockWidthFor] — half of a short window is less than the timeline
  /// needs to show a row of blocks.
  static double bottomDockHeightFallbackFor(
    double availableHeight,
    DeviceGrid grid,
  ) {
    if (!availableHeight.isFinite || availableHeight <= 0) {
      return bottomPanelHeight;
    }
    return grid.position(
      math.max(availableHeight * bottomDockHeightFraction, bottomPanelHeight),
    );
  }

  /// How wide one side dock may be dragged — [sideDockCeilingFraction] of
  /// the window, and never so much that the pair could crowd the centre out
  /// on a narrow one.
  ///
  /// ⚠️It takes no `otherDockWidth`, and that absence IS the fix (결정 8).
  /// Both rails get the same answer from the same window, so one can never
  /// move the other.
  ///
  /// ⚠️The second term binds only below roughly 550px of window, where
  /// 37.5% twice would leave the centre under its floor. It still names no
  /// dock — it halves what is left after the floor, which both sides can
  /// take at once.
  static double sideDockCeiling({
    required double availableWidth,
    required double gaps,
    required double minCentreWidth,
  }) {
    if (!availableWidth.isFinite) {
      return double.infinity;
    }
    final share = availableWidth * sideDockCeilingFraction;
    final room = (availableWidth - gaps - minCentreWidth) / 2;
    return math.max(0.0, math.min(share, room));
  }

  /// How many GROUPS a rail can hold.
  ///
  /// A fixed pool declared up front rather than dock ids minted when the
  /// user makes a group, because [restoreWorkspaceLayout] seeds only the
  /// dock ids the defaults name and drops everything else — a runtime dock
  /// would survive until the next restart and then quietly lose its panels.
  static const int railSlots = 8;

  /// The dock holding one rail group. [slot] is 1-based.
  static String railGroupId({required bool right, required int slot}) =>
      'rail-${right ? 'R' : 'L'}$slot';

  /// 레일당 폭 하나 (유저 확정): every group on a rail shares one width, so
  /// widening one widens them all and the rail reads as a column rather
  /// than as a stack of differently-sized boxes.
  ///
  /// ⚠️Shared VALUE, not a shared splitter. Every group wears its own
  /// width grip on its own inner edge — a panel that floats has to be
  /// grabbable at its own edge — and they all write here, so pulling any
  /// of them moves all of them (유저, R2 #11).
  static String railWidthKey({required bool right}) =>
      right ? 'rail-R' : 'rail-L';

  /// What one rail group opens to before anyone drags it.
  ///
  /// A group keeps its own HEIGHT (유저 확정, R2 #7): opening a button
  /// raises a panel of the size that button was left at, not a column that
  /// swells to fill the rail. Stored under the group's own dock id — the
  /// width lives under [railWidthKey], so the two never collide.
  static const double railGroupHeight = 320;

  /// The first slot of each rail, which is where a panel with nowhere else
  /// to go lands. Named separately because the whole app already calls
  /// these "the left dock" and "the right dock".
  static const String leftGroupId = 'rail-L1';
  static const String rightGroupId = 'rail-R1';
  static const String centerGroupId = 'center';
  static const String bottomGroupId = 'bottom';

  /// The slim edge docks homing the vertical tool bar (one per workspace
  /// edge; only narrow-fit panels may dock there).
  static const String toolLeftGroupId = 'tool-left';
  static const String toolRightGroupId = 'tool-right';

  static const String toolsTabId = 'tools';
  static const String canvasTabId = 'canvas';
  static const String brushesTabId = 'brushes';
  static const String brushSettingsTabId = 'brush-settings';

  /// The three colour PANELS. They were the three tabs of one colour panel
  /// until R2 #8 — a strip inside a strip, asking "which panel" and "how am
  /// I picking" in the same place twice.
  static const String colorWheelTabId = 'color-wheel';
  static const String colorRgbTabId = 'color-rgb';
  static const String colorPaletteTabId = 'color-palette';
  static const String onionSkinTabId = 'onion-skin';

  /// 🚨I-2 (유저 결정 2026-08-25): 「**새 패널로 만든다 — 이번은 예외**」 —
  /// the first exception to 「툴 전용 패널을 새로 만들지 않는다」. The rule
  /// stands for tool SETTINGS; a rack of sizes you reach for while drawing
  /// has to be visible at the same time as the canvas, which is the one
  /// thing the settings panel cannot be.
  static const String toolSizeTabId = 'tool-size';
  static const String cameraTabId = 'camera';
  static const String mediaTabId = 'media';
  static const String timelineTabId = 'timeline';
  static const String storyboardTabId = 'storyboard';
  static const String conteTabId = 'conte';
  static const String envelopeTabId = 'envelope';
  static const String timesheetTabId = 'timesheet';
  static const String mediaViewerTabId = 'media-viewer';

  /// The SECOND viewer (유저 확정 ⑧, 2026-08-12): the same panel, docked
  /// like any other so it can sit narrow beside the drawing while the
  /// first one lies on the floor to be looked at large. Exactly two —
  /// a third would need panel ids the user can create at runtime, which
  /// this registry is not.
  static const String mediaViewerSubTabId = 'media-viewer-sub';

  /// Every tab id `_tabFor` can build — the registry, not the layout.
  ///
  /// 🚨 The default dock layout is NOT this list. A test that walks the
  /// docks it happens to find audits the panels that ship open and
  /// nothing else, which is how three panels went a whole round paying
  /// full raster price with an enforcement test sitting green over them.
  /// Anything added to `_tabFor` belongs here, and
  /// `panel_static_raster_test` asserts the two agree.
  ///
  /// ⚠️ [cameraTabId] is deliberately absent: it has no `_tabFor` case
  /// and building it throws. It is a dead constant, not a missed panel.
  @visibleForTesting
  static const List<String> debugAllTabIds = <String>[
    toolsTabId,
    canvasTabId,
    brushesTabId,
    brushSettingsTabId,
    colorWheelTabId,
    colorRgbTabId,
    colorPaletteTabId,
    onionSkinTabId,
    toolSizeTabId,
    mediaTabId,
    mediaViewerTabId,
    mediaViewerSubTabId,
    timelineTabId,
    storyboardTabId,
    conteTabId,
    envelopeTabId,
    timesheetTabId,
  ];

  /// The WIDTH frame-axis panels lay out at when docked somewhere narrower
  /// (their label rails and toolbars assume a wide region); the tab shell
  /// hosts them inside a horizontal scroller then. Unchanged by the
  /// shrink-floor round — in a narrow side dock, scrolling sideways is
  /// genuinely what helps.
  static const double _frameAxisMinContentWidth = 640;

  @override
  State<EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends State<EditorWorkspace>
    with WidgetsBindingObserver {
  /// The OS says memory is tight: the session stands its caches down —
  /// hot cels halve and cool, playback re-runs its budget. The workspace
  /// hosts the observer because its lifetime IS the session being on
  /// screen; nothing else in lib listens to the binding.
  @override
  void didHaveMemoryPressure() {
    widget.session.respondToMemoryPressure();
  }

  /// 🚨★★★**COMING BACK IS WHEN THE FILE MAY HAVE GONE.**
  ///
  /// 유저 2026-08-31, having lost 94 cels: 「이 문제 발생시 **해결법이
  /// 없기때문**」. A save turns every clean cel into a ref into the project
  /// file and drops its cold blob, so deleting that file — in Explorer, in
  /// the Files app, in Drive — takes those pixels with it. The app only
  /// found out at the next save, by which time the recycle bin had usually
  /// been emptied and the person had done an hour of work on a project
  /// that could no longer be written whole.
  ///
  /// ⛔The bytes cannot be recovered from here; nothing can. What CAN be
  /// recovered is the FILE, and only while it is still in a trash somewhere
  /// — which is exactly the window this notice exists to open.
  ///
  /// The observer was already here for memory pressure; resuming is the
  /// moment a person comes back from the file manager they just used.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_warnIfProjectFileVanished());
    }
  }

  /// The factory-default arrangement (also the validation baseline when a
  /// saved layout is restored: it names every known tab and its home dock).
  ///
  /// 🆕유저 확정 (R3 #10) — ONE PANEL PER BUTTON except where the panels
  /// are the same thing seen differently. The tool strip carries the tool
  /// LIBRARY and, under it, the tool SETTINGS: two buttons, both open, the
  /// two panels a stroke alternates between. The sub-strip carries the
  /// colour swatch, then the three PAPER surfaces of one cut (타임시트 ·
  /// 콘티 · 컷봉투) as one button, then the media pool, then the onion
  /// settings. The floating region keeps the two TIME axes — the timeline
  /// and the storyboard — because those are what a wide bottom strip is
  /// shaped for.
  ///
  /// The sheet being VISIBLE by default is what makes this change cost a
  /// test round: it mounts its own ink views and cells, so any finder that
  /// looks for a canvas widget app-wide now matches twice. The fix is
  /// always to scope the finder to its panel — never to hide the sheet
  /// again.
  static Map<String, DockGroup?> _defaultDocks() => {
    EditorWorkspace.toolLeftGroupId: DockGroup(
      tabs: [EditorWorkspace.toolsTabId],
    ),
    EditorWorkspace.toolRightGroupId: null,
    // The rest of the rail pool: declared empty so the ids exist for a
    // restore, and so dragging a panel onto an empty slot has somewhere to
    // put it. The filled slots are spelled out below.
    for (var slot = 3; slot <= EditorWorkspace.railSlots; slot += 1)
      EditorWorkspace.railGroupId(right: false, slot: slot): null,
    for (var slot = 5; slot <= EditorWorkspace.railSlots; slot += 1)
      EditorWorkspace.railGroupId(right: true, slot: slot): null,
    // 도구띠: 툴라이브러리 버튼, 그 밑에 툴설정 버튼 (유저 확정, R3 #10).
    // They used to be two tabs of one group, which made them one button
    // and hid one behind the other.
    EditorWorkspace.leftGroupId: DockGroup(
      tabs: [EditorWorkspace.brushesTabId],
    ),
    EditorWorkspace.railGroupId(right: false, slot: 2): DockGroup(
      tabs: [EditorWorkspace.brushSettingsTabId],
    ),
    // 오른쪽: 컬러(맨 위) (유저 확정). The picker is the top group of the
    // sub-strip, and its button is the swatch itself.
    // The colour group: three ways of picking, three tabs of ONE group,
    // and the group's own strip is the only strip.
    EditorWorkspace.rightGroupId: DockGroup(
      tabs: [
        EditorWorkspace.colorWheelTabId,
        EditorWorkspace.colorRgbTabId,
        EditorWorkspace.colorPaletteTabId,
      ],
    ),
    // 타임시트+콘티+컷봉투 한 버튼 — the three sheets that describe the same
    // cut, read beside the drawing.
    EditorWorkspace.railGroupId(right: true, slot: 2): DockGroup(
      tabs: [
        EditorWorkspace.timesheetTabId,
        EditorWorkspace.conteTabId,
        EditorWorkspace.envelopeTabId,
      ],
    ),
    // 해당버튼 밑에 미디어브라우저, 미디어브라우저밑에 어니언스킨.
    EditorWorkspace.railGroupId(right: true, slot: 3): DockGroup(
      tabs: [EditorWorkspace.mediaTabId],
    ),
    // I-2 rides WITH the onion rather than taking a sixth rail button, and
    // that is a measurement rather than a preference: a sixth group
    // overflowed the rail by 14px in the shortest window the shrink-floor
    // test defends ("in a window too short to pay the floor the dock yields
    // rather than pushing the canvas out"). The rail has no room for another
    // button there, so the tab shares one.
    EditorWorkspace.railGroupId(right: true, slot: 4): DockGroup(
      tabs: [EditorWorkspace.onionSkinTabId, EditorWorkspace.toolSizeTabId],
    ),
    // 서브 뷰어 (유저 확정 ⑥): right under the media pool it is opened
    // from, and its group ships CLOSED — a reference panel earns its
    // height only once there is a reference in it.
    EditorWorkspace.railGroupId(right: true, slot: 5): DockGroup(
      tabs: [EditorWorkspace.mediaViewerSubTabId],
    ),
    // THE FLOOR (유저 확정): the bottom layer everything else is drawn on.
    // The canvas and the media viewer are the two panels that can be it —
    // they are both full-page surfaces you look AT rather than read beside
    // the drawing — and the top strip's canvas/viewer pair is the switch
    // between them. The viewer used to live down among the paper tabs,
    // where opening a reference shrank the drawing to make room for it.
    EditorWorkspace.centerGroupId: DockGroup(
      tabs: [EditorWorkspace.canvasTabId, EditorWorkspace.mediaViewerTabId],
      activeTabId: EditorWorkspace.canvasTabId,
    ),
    // The floating region keeps the TIME axes only (유저 확정, R3 #10):
    // the paper sheets moved to the sub-strip, where a tall narrow column
    // suits a page better than a wide short one.
    EditorWorkspace.bottomGroupId: DockGroup(
      tabs: [EditorWorkspace.timelineTabId, EditorWorkspace.storyboardTabId],
      activeTabId: EditorWorkspace.timelineTabId,
    ),
  };

  /// The panels that BELONG on the floor — the two full-page surfaces you
  /// look at rather than read beside the drawing. They lead the top
  /// strip's switch and stay on it even when docked elsewhere, because
  /// pressing their button fetches them back ([_selectFloorTab]).
  static const List<String> _floorHomeTabIds = [
    EditorWorkspace.canvasTabId,
    EditorWorkspace.mediaViewerTabId,
  ];

  // ── the panel tabs: their own object, in their own file ─────────────
  //
  // A collaborator (workspace/workspace_tabs.dart, a part of this library). The
  // State keeps the entry points its build tree calls as forwarders.
  late final _WorkspaceTabs _tabs = _WorkspaceTabs(this);

  /// Only narrow-fit panels may live in the slim edge docks.
  static const Set<String> _edgeDockTabIds = {EditorWorkspace.toolsTabId};

  /// Which rail groups are OPEN.
  ///
  /// 여러 버튼 동시에 열림 (유저 확정) — this is a set and not a selection,
  /// because the rail is not a tab bar: opening a second group stacks it
  /// under the first and they divide the rail's height. A group with no
  /// panels in it has no button and cannot be opened.
  Set<String> _openRails = _WorkspaceLayoutPersistence.defaultOpenRails();

  // ── the workspace layout persistence: its own object ────────────────
  //
  // A collaborator (workspace/workspace_layout_persistence.dart, a part of this library). The
  // State keeps the entry points its build tree calls as forwarders.
  late final _WorkspaceLayoutPersistence _layoutPersistence =
      _WorkspaceLayoutPersistence(this);

  /// Opens every rail group at startup, for tests only.
  ///
  /// 🚨 A rail group that ships closed mounts no `EditorPanelTabs`, so a
  /// test that walks the tabs it can find cannot reach the panels inside
  /// one — seven of the app's fifteen. That is how three panels went a
  /// whole round paying full raster price with the enforcement test green
  /// over them.
  ///
  /// The alternative was to open them in the shipped app "temporarily for
  /// testing", which changes the product for a test's convenience and
  /// leaves a revert nobody remembers. This changes nothing anyone sees.
  @visibleForTesting
  static bool debugOpenEveryRail = false;

  /// The slots of one rail, in order, whatever is in them.
  static List<String> _railSlotIds({required bool right}) => [
    for (var slot = 1; slot <= EditorWorkspace.railSlots; slot += 1)
      EditorWorkspace.railGroupId(right: right, slot: slot),
  ];

  /// The slots of one rail that HOLD something — the buttons that exist.
  List<String> _railGroups({required bool right}) => [
    for (final id in _railSlotIds(right: right))
      if (_layout.tabsIn(id).isNotEmpty) id,
  ];

  /// The open groups of one rail, in rail order — the column, top to
  /// bottom.
  List<String> _openRailGroups({required bool right}) => [
    for (final id in _railGroups(right: right))
      if (_openRails.contains(id)) id,
  ];

  // ── the workspace docks: their own object, in their own file ────────
  //
  // A collaborator (workspace/workspace_docks.dart, a part of this library). The
  // State keeps the entry points its build tree calls as forwarders.
  late final _WorkspaceDocks _docks = _WorkspaceDocks(this);

  /// The door a collaborator rebuilds through - setState is protected,
  /// and a collaborator is not a subclass.
  void _rebuild(VoidCallback fn) => setState(fn);

  void _toggleRailGroup(String railId) {
    setState(() {
      if (!_openRails.remove(railId)) {
        _openRails.add(railId);
      }
    });
    _layoutPersistence.scheduleLayoutSave();
  }

  late final EditorPanelLayoutModel _layout = EditorPanelLayoutModel(
    docks: _defaultDocks(),
  );

  /// The reveal-flash channel (UI-R17 #5) every dock's panel shell
  /// listens to.
  final PanelFlashController _panelFlash = PanelFlashController();

  /// The tab in flight (null = none) — docks reveal their drop zones for
  /// an eligible tab only while this is set.
  final ValueNotifier<EditorPanelTabDragData?> _draggingTab = ValueNotifier(
    null,
  );

  /// Drag-locked tabs (the canvas by default: a stray drag must not undock
  /// the drawing surface — unlock via the lock glyph on its tab).
  Set<String> _lockedTabIds = {EditorWorkspace.canvasTabId};

  /// Keeps the canvas element (and its viewport state) alive when the
  /// canvas tab re-docks.
  final GlobalKey _canvasAreaKey = GlobalKey();

  /// The active-tool notifier. Typed as the SUBCLASS because the rail asks
  /// it which tile to re-enter a tool group on (`railEntry`), and that
  /// memory has to be the same one the shell's tool shortcuts read.
  late final PaintToolStateNotifier _brushTool =
      widget.brushTool ?? PaintToolStateNotifier(BrushToolState.defaults);

  /// The one piece the cut tool is holding.
  ///
  /// Owned here rather than by the session because the piece has to
  /// outlive a project change (유저: "다른 프로젝트에 붙여넣고 싶을 수 있으니")
  /// — it holds a raw pixel copy, so nothing about it belongs to the
  /// project it was taken from. Only quitting loses it.
  final CutPieceSlot _cutPieceSlot = CutPieceSlot();

  int _registeredCutTipSequence = 0;

  /// Rename a library tip. The model has had this since the library
  /// landed; what it never had was anywhere to be called from.
  Future<void> _renameTip(BrushTipEntry tip) async {
    final controller = TextEditingController(text: tip.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey<String>('rename-tip-dialog'),
        title: Text(AppText.strings.brRenameTip),
        content: TextField(
          key: const ValueKey<String>('rename-tip-name-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          ControlPressClaim(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: TextButton(
              onPressed: silentPress(() => Navigator.of(dialogContext).pop()),
              child: Text(AppText.strings.commonCancel),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(AppText.strings.commonRename),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      _tipLibrary.rename(tip.id, trimmed);
    }
  }

  /// Delete a library tip, behind a confirm.
  ///
  /// The confirm is not a general "are you sure" habit — this app's rule is
  /// that explanatory notices are noise — but deleting is destructive and
  /// unlike a stroke it has no undo behind it. Photoshop and Clip Studio
  /// both ask here too.
  Future<void> _deleteTip(BrushTipEntry tip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey<String>('delete-tip-dialog'),
        title: Text(AppText.strings.brDeleteTip),
        content: Text('“${tip.name}” will be removed from the library.'),
        actions: [
          ControlPressClaim(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: TextButton(
              onPressed: silentPress(
                () => Navigator.of(dialogContext).pop(false),
              ),
              child: Text(AppText.strings.commonCancel),
            ),
          ),
          FilledButton(
            key: const ValueKey<String>('delete-tip-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppText.strings.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _tipLibrary.delete(tip.id);
    }
  }

  /// Promotes the held piece into the brush tip library.
  ///
  /// Explicit, and it asks for a name — which is the whole reason cutting
  /// does NOT do this by itself. Photoshop and Clip Studio both make
  /// library registration a separate named command, and TVPaint's Tool
  /// History is the counter-example: it accumulates unnamed near-duplicates
  /// automatically and its own users gave up on it as a store. The user's
  /// objection to the first design was exactly that ("잘라낼 때마다 팁
  /// 라이브러리 늘리는 거 딱히 마음에 안 드는데").
  ///
  /// One field, like Photoshop's. Our tip library has no groups to file
  /// into — that is the preset library — so a second field would be asking
  /// about a place that does not exist.
  /// The id the stamp was last armed for, so a POSE change is not mistaken
  /// for a fresh cut (the slot notifies for both).
  String? _armedCutPieceId;

  /// TS8-adjacent (TS2): a finished cut arms the STAMP.
  ///
  /// 유저: *"잘라내고 나면 찍기로 모드전환"* — cutting is how you get
  /// something to stamp, so the tool that stamps it is where the hand is
  /// going next. TVPaint's cutting tool hands over to its custom brush the
  /// same way.
  ///
  /// It hangs off the SLOT rather than the cut gesture on purpose: the slot
  /// is only ever filled by a cut that actually lifted pixels (scraping an
  /// empty area deliberately leaves the held piece alone), so "a stray
  /// scrape switched my tool" cannot happen without an extra guard. The
  /// pose knobs notify through here too, hence [_armedCutPieceId] — ids are
  /// minted per cut and survive `copyWith`.
  ///
  /// Tool changes are view state, not history: this is one write, and undo
  /// never sees it.
  void _armStampOnFreshCut() {
    final piece = _cutPieceSlot.piece;
    if (piece == null || piece.image.id == _armedCutPieceId) {
      return;
    }
    _armedCutPieceId = piece.image.id;
    if (_brushTool.value.tool == CanvasTool.cutStamp) {
      return;
    }
    _brushTool.value = _brushTool.value.copyWith(tool: CanvasTool.cutStamp);
  }

  Future<void> _registerCutPieceAsTip() async {
    final piece = _cutPieceSlot.piece;
    if (piece == null) {
      return;
    }
    _registeredCutTipSequence += 1;
    final controller = TextEditingController(
      text: 'Cut $_registeredCutTipSequence',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey<String>('register-cut-tip-dialog'),
        title: Text(AppText.strings.tipRegisterTitle),
        content: TextField(
          key: const ValueKey<String>('register-cut-tip-name-field'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppText.strings.commonNameField,
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          ControlPressClaim(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: TextButton(
              onPressed: silentPress(() => Navigator.of(dialogContext).pop()),
              child: Text(AppText.strings.commonCancel),
            ),
          ),
          FilledButton(
            key: const ValueKey<String>('register-cut-tip-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(AppText.strings.commonRegister),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    final id = sanitizeBrushTipId(
      nextUserBrushTipId(sequence: _registeredCutTipSequence),
    );
    await _tipLibrary.register(cutPieceToTipMask(piece, id: id), name: trimmed);
  }

  /// Which preset is highlighted PER painting tool (R11-④: the brush and
  /// the eraser keep separate selections; their settings live in
  /// [PaintToolStateNotifier]'s bank).
  final Map<CanvasTool, BrushPresetId?> _activePresetByTool = {};

  /// 🚨H25 — WHAT THE HAND LAST SET ON EACH BRUSH.
  ///
  /// 유저 2026-08-23: 「브러시 고르고 브러시크기 설정하면 다음에 같은 브러시
  /// 선택할때 해당 브러시크기 남아있도록. 불투명도도 마찬가지」. A brush with no
  /// entry here reads the size baked into its own file — the other half of the
  /// answer, and the reason this is a bank and not a rewrite of the preset.
  ///
  /// ⛔The preset FILE is not touched (Q-brush-store): a slider drag must not
  /// write a document to disk. Persisted beside the app's other editor state.
  final Map<String, BrushHandSettings> _brushHandSettings = {};
  final BrushHandSettingsStore _brushHandSettingsStore =
      BrushHandSettingsStore();
  Timer? _brushHandSettingsSave;

  /// Records the live size/opacity against the ACTIVE preset.
  ///
  /// ⚠️Reads the state's own tool, never the notifier's last-known one: the
  /// eraser carries its own preset (R11-④), so recording under the wrong tool
  /// would give two brushes one memory.
  void _rememberBrushHandSettings() {
    final state = _brushTool.value;
    final presetId = _activePresetByTool[state.tool];
    if (presetId == null) {
      return;
    }
    final next = (size: state.size, opacity: state.activeOpacity);
    if (_brushHandSettings[presetId.value] == next) {
      return;
    }
    _brushHandSettings[presetId.value] = next;
    // Debounced: this fires on every slider frame, and the file is the
    // cheapest thing in the app to write too often.
    _brushHandSettingsSave?.cancel();
    _brushHandSettingsSave = Timer(const Duration(milliseconds: 400), () {
      unawaited(
        _brushHandSettingsStore.save(
          Map<String, BrushHandSettings>.of(_brushHandSettings),
        ),
      );
    });
  }

  /// The fill tool's flood options (Tool Settings knobs).
  final ValueNotifier<FloodFillOptions> _fillOptions = ValueNotifier(
    const FloodFillOptions(),
  );

  /// The Select tool's lift-time mask knobs (R26): grow/shrink, inward
  /// feather, edge AA. Defaults keep the lift byte-preserving.
  final ValueNotifier<SelectionMaskOptions> _selectionMaskOptions =
      ValueNotifier(SelectionMaskOptions.none);

  /// P3a: which resampler a transform commit runs through. Session state
  /// like its three neighbours here, deliberately NOT a [BrushToolState]
  /// field — everything there other than the tool itself forwards into
  /// [BrushShape], which is what a saved brush preset serialises, so the
  /// bit would follow every preset around for no reason.
  ///
  /// Blend is the default: smoothing is what a transform is expected to do
  /// everywhere else in the industry, and the argmax is the deliberate
  /// choice for two-value work.
  final ValueNotifier<TransformToolOptions> _transformOptions = ValueNotifier(
    TransformToolOptions.defaults,
  );

  /// R28 #6: the eyedropper's reference source (Tool Settings knob). The
  /// user's default is "pick what you SEE".
  final ValueNotifier<CanvasColorSampleSource> _eyedropperSource =
      ValueNotifier(CanvasColorSampleSource.display);

  // The colour state — the background slot, the pinned palette, its file
  // service and the recent-colour recorder — is the SHELL's now, alongside
  // `_brushTool`: the colour button moved to the top strip, and the strip is
  // mounted by the shell. Nothing in the workspace reads a colour any more.

  /// The head of the tool rail: undo, redo and the onion toggle — what a
  /// hand reaches for BETWEEN strokes, which is the rail's whole job.
  ///
  /// Undo and redo keep the keys they wore in the top strip
  /// (`undo-button` / `redo-button`); they are old keys and a good number
  /// of tests hold them, so the move costs those tests nothing.
  ///
  /// Wording is borrowed from the action registry by id rather than tabled
  /// again — these three are registry actions, and their names are already
  /// translated for the shortcut dialog.
  Widget _railHistoryControls() {
    final session = widget.session;
    final selection = widget.canvasSelectionCommands;
    return ListenableBuilder(
      listenable: Listenable.merge([
        session,
        session.historyManager,
        session.onionSkinLayerIds,
        // ㉜: the deselect button's enablement is the SELECTION's news, and
        // it arrives on that object's own channel — the selection layer
        // mutates inside builds and gesture handlers, so its notify is
        // microtask-deferred rather than riding a session notify.
        ?selection,
        // 🚨…and the timeline's four kinds, each on its own notifier. The
        // button lets go of ALL FIVE now, so it has to hear all five — it
        // used to answer `hasRegion` alone and could afford to listen to the
        // marquee alone. ⛔A `session` notify does not carry these: they are
        // ValueNotifiers of their own.
        session.frameRangeSelection,
        session.laneRangeSelection,
        session.trackFrameRangeSelection,
        session.rowSelection,
      ]),
      builder: (context, _) {
        final strings = AppText.strings;
        final layer = session.activeLayer;
        // Onion is PER LAYER (the per-layer model retired the master
        // switch), so this button is the active row's onion — the same
        // thing the `O` action toggles, not the legend's bulk sweep.
        final onionOn =
            layer != null && session.onionSkinLayerIds.value.contains(layer.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RailButton(
              keyValue: 'undo-button',
              tooltip: strings.shortcutLabel(EditorActionIds.undo, 'Undo'),
              icon: Icons.undo,
              selected: false,
              onPressed: session.canUndo ? session.undo : null,
            ),
            const SizedBox(height: 4),
            RailButton(
              keyValue: 'redo-button',
              tooltip: strings.shortcutLabel(EditorActionIds.redo, 'Redo'),
              icon: Icons.redo,
              selected: false,
              onPressed: session.canRedo ? session.redo : null,
            ),
            const SizedBox(height: 4),
            RailButton(
              keyValue: 'rail-onion-skin-button',
              tooltip: strings.shortcutLabel(
                EditorActionIds.onionSkinToggle,
                'Toggle Onion Skin',
              ),
              icon: Icons.filter_none_outlined,
              selected: onionOn,
              onPressed: layer != null ? session.toggleOnionSkin : null,
            ),
            // ㉜ (user, 2026-08-12): 「선택 해제 버튼이 없다」. The VERB was
            // already here — `Ctrl+D` runs it — so this is the entrance and
            // nothing else. It sits with undo/redo/onion because it is the
            // same kind of thing: what a hand reaches for BETWEEN strokes.
            //
            // Its wording comes from the action registry by id, like its
            // three neighbours, so the button and the shortcut dialog cannot
            // end up calling it two different names.
            if (selection != null) ...[
              const SizedBox(height: 4),
              RailButton(
                keyValue: 'rail-deselect-button',
                tooltip: strings.shortcutLabel(
                  EditorActionIds.selectionDeselect,
                  'Deselect',
                ),
                icon: Icons.deselect,
                selected: false,
                // Dimmed with nothing selected rather than hidden: a button
                // that comes and goes is one you have to look for.
                //
                // 🚨`hasRegion`, NOT `hasSelection`. The region is a
                // DOCUMENT-level fact and survives tool switches (R28-S);
                // `hasSelection` asks the MOUNTED selection layer, which
                // exists only while a selection tool is active, and answers
                // `false` the moment that layer unbinds. So the button went
                // dead the instant you picked the brush, with the selection
                // still on screen and Ctrl+D still working — 유저: 「다른툴
                // 이동하면 선택중인상태인데도 비활성화되있어」.
                //
                // `hasSelection` keeps its own job: arrow keys nudge instead
                // of flipping frames, and that one really does need a live
                // layer to nudge.
                // 🚨ONE question, and it is the SESSION's — the marquee is
                // one of five selection kinds, and this button is now the
                // only door out of any of them (유저 2026-08-27: 「선택해제
                // 타임라인에 중복으로 존재하는거」 — the pill's copy is gone).
                //
                // ⚠️`hasRegion` alone was right while this cleared only the
                // marquee. It would now light for half of what it does.
                onPressed: session.hasAnySelection
                    ? session.clearAllSelections
                    : null,
              ),
            ],
          ],
        );
      },
    );
  }

  late final BrushPresetLibrary _presetLibrary;
  late final BrushTipLibrary _tipLibrary;

  /// Camera view mode: overlay shown with the outside dimmed.
  final ValueNotifier<bool> _cameraViewEnabled = ValueNotifier(false);
  final ValueNotifier<double> _cameraDimOpacity = ValueNotifier(0.5);

  final ValueNotifier<TimelineOrientation> _timelineOrientation = ValueNotifier(
    TimelineOrientation.horizontal,
  );

  // One shared zoom slider drives whichever view is shown; the values are
  // kept per view so each keeps a sensible default scale.
  final ValueNotifier<double> _timelinePixelsPerFrame = ValueNotifier(
    TimelinePanel.defaultPixelsPerFrame,
  );
  final ValueNotifier<double> _storyboardPixelsPerFrame = ValueNotifier(8);

  /// The storyboard's V rows share ONE height (user's rule), kept here so
  /// it survives a tab switch the way the zoom does.
  final ValueNotifier<double> _storyboardTrackLaneHeight = ValueNotifier(
    StoryboardPanel.defaultTrackLaneHeight,
  );

  /// Shared frames↔seconds display toggle (conte-sheet 초+コマ notation).
  final ValueNotifier<bool> _showSecondsDisplay = ValueNotifier(false);

  /// Each frame panel's layer-rail WINDOW size, set by its splitter.
  ///
  /// Kept here rather than in the panels because the user asked for these
  /// to survive a restart: they ride the workspace layout file beside the
  /// dock widths, through the same debounced save.
  final Map<String, LayerRailExtent> _railExtents = {
    for (final railId in LayerRailId.values) railId: LayerRailExtent(),
  };

  /// Layers whose AE-style property-lane twirl-down is open (view state —
  /// survives tab switches, session-only).
  final ValueNotifier<Set<LayerId>> _expandedLaneLayerIds = ValueNotifier(
    const <LayerId>{},
  );

  void _toggleLayerLanes(LayerId layerId) {
    // 🚨UNDOABLE (유저 2026-08-29: 「아무튼 레이어에 있는 버튼 싹다」). The
    // property-lane twirl — the one the fx lanes live under — is a button
    // on a layer row like any other.
    //
    // ⛔The closing half still runs here and NOT inside the command: the
    // fold law hands the standing row to the layer when its lanes leave
    // the screen (R5 #11), and that is a selection move, not part of the
    // membership this undoes.
    final closing = _expandedLaneLayerIds.value.contains(layerId);
    widget.session.historyManager.execute(
      ToggleIdInSetCommand(
        notifier: _expandedLaneLayerIds,
        layerId: layerId,
        debugLabel: 'Toggle layer lanes',
      ),
    );
    if (closing) {
      widget.session.handOffCurrentRowOnFold(layerId);
    }
  }

  /// LANE GROUPS twirled open inside a layer's twirl-down (AE group
  /// collapse — default collapsed; view state, survives tab switches,
  /// session-only). Keyed by [laneGroupKey], because a row now carries more
  /// than one group: Transform, plus one header per R6 effect.
  final ValueNotifier<Set<String>> _expandedLaneGroupKeys = ValueNotifier(
    const <String>{},
  );

  void _toggleLaneGroup(String groupKey) {
    final next = Set<String>.of(_expandedLaneGroupKeys.value);
    if (next.remove(groupKey)) {
      // Closing: only this group's MEMBERS go, so the header is what
      // swallows them and where the standing row lands (R5 #11).
      final row = parseLaneGroupKey(groupKey);
      if (row != null) {
        widget.session.handOffCurrentRowOnFold(row.layerId, laneId: row.laneId);
      }
    } else {
      next.add(groupKey);
    }
    _expandedLaneGroupKeys.value = next;
  }

  /// SE/camera timeline sections hidden from the grids (view state —
  /// survives tab switches, session-only; toggled from the timeline
  /// toolbar, the retired fold/collapse UI's replacement).
  final ValueNotifier<Set<TimelineSection>> _hiddenTimelineSections =
      ValueNotifier(const <TimelineSection>{});

  /// Bases whose ATTACH GROUP is twirled shut (UI-R20 #9; view state —
  /// survives tab switches, session-only). Default expanded: a fresh
  /// attach layer must be visible the moment it's made.
  final ValueNotifier<Set<LayerId>> _collapsedAttachBaseIds = ValueNotifier(
    const <LayerId>{},
  );

  void _toggleAttachGroup(LayerId baseId) {
    final next = Set<LayerId>.of(_collapsedAttachBaseIds.value);
    if (!next.remove(baseId)) {
      next.add(baseId);
      // FOLDING while one of the group's attach rows is active (UI-R24
      // #4): hand the selection to the BASE so the group actually
      // disappears — the active-attach-stays-visible rule otherwise kept
      // the fold from taking effect until some other row was picked.
      final session = widget.session;
      final active = session.activeLayer;
      if (active != null && active.attachedToLayerId == baseId) {
        session.selectLayer(baseId);
      }
    }
    _collapsedAttachBaseIds.value = next;
  }

  void _toggleTimelineSection(TimelineSection section) {
    final next = Set<TimelineSection>.of(_hiddenTimelineSections.value);
    if (!next.remove(section)) {
      next.add(section);
    }
    _hiddenTimelineSections.value = next;
  }

  /// The rail's row FILTER (R2 view state): hides layer rows failing its
  /// predicate; survives tab switches, session-only, never persisted.
  final ValueNotifier<TimelineRowFilter> _timelineRowFilter = ValueNotifier(
    TimelineRowFilter.none,
  );

  void _setTimelineRowFilter(TimelineRowFilter filter) {
    _timelineRowFilter.value = filter;
    // UI-R6 #3: a non-passing active layer moves to the nearest passing
    // layer above it (instead of lingering through the exemption).
    if (filter.isActive) {
      widget.session.moveSelectionToFilteredLayer(
        (layer) => filter.allows(
          layer,
          fxEnabled: widget.session.isLayerFxEnabled(layer.id),
        ),
      );
    }
  }

  /// Timesheet tab view state: paper page-split ⟷ continuous, the sheet
  /// on screen in page view (R26 #41), the sheet viewport (zoom/pan) and
  /// the sheet-ink allow toggle — owned here so they survive tab switches.
  final ValueNotifier<bool> _timesheetContinuous = ValueNotifier(false);
  final ValueNotifier<int> _timesheetPage = ValueNotifier(0);
  final ValueNotifier<CanvasViewport?> _timesheetViewport = ValueNotifier(null);
  final ValueNotifier<bool> _timesheetInkEnabled = ValueNotifier(true);

  /// Sheet ink stores (S2 annotations) — owned here so freehand memos
  /// survive tab switches; separate from the session's cel stroke store.
  final TimesheetInkController _timesheetInk = TimesheetInkController();

  /// Conte tab view state (#16 — the conte rides the same canvas shell):
  /// the sheet viewport and its ink toggle, owned here like the
  /// timesheet's. Ink starts BLOCKED: the conte's first verb is reading
  /// and selecting cells.
  final ValueNotifier<CanvasViewport?> _conteViewport = ValueNotifier(null);
  final ValueNotifier<bool> _conteInkEnabled = ValueNotifier(false);

  /// Cut-envelope tab view state — the conte's pair, said of the 봉투.
  /// Ink starts BLOCKED here too: the envelope is read (and printed)
  /// before anybody writes on it.
  final ValueNotifier<CanvasViewport?> _envelopeViewport = ValueNotifier(null);
  final ValueNotifier<bool> _envelopeInkEnabled = ValueNotifier(false);

  /// The logo and 도장 the envelope prints, decoded once each.
  ///
  /// A repaint is all a landed decode needs, and the envelope tab is the
  /// only thing that reads it — but the cache lives HERE because that tab is
  /// rebuilt on every panel switch and would drop its images each time.
  late final EnvelopeImageCache _envelopeImages = EnvelopeImageCache(
    onLoaded: () {
      if (mounted) {
        setState(() {});
      }
    },
  );

  /// Which bundled 봉투 form the panel prints. Session-scoped for now: the
  /// project-level choice arrives with the form editor, and until there is
  /// a place to store one, remembering it here beats hard-coding it.
  final ValueNotifier<String> _envelopeFormId = ValueNotifier(
    CutEnvelopePresets.analogId,
  );

  /// The TWO viewers (R4 §6-h, second one 유저 확정 2026-08-12): the one
  /// that lies on the floor to be looked at large, and the one that sits
  /// on a rail beside the drawing. Same panel, same code, separate state
  /// — a reference opened in one never disturbs the other.
  ///
  /// Owned here rather than in the panels so all three of what/where/how
  /// far survive a tab switch, a re-dock, and a folded-away rail.
  final MediaViewerSlot _mainViewer = MediaViewerSlot();
  final MediaViewerSlot _subViewer = MediaViewerSlot();

  MediaViewerSlot _viewerSlot(String tabId) =>
      tabId == EditorWorkspace.mediaViewerSubTabId ? _subViewer : _mainViewer;

  Map<String, MediaViewerSlot> get _viewerSlots => {
    EditorWorkspace.mediaViewerTabId: _mainViewer,
    EditorWorkspace.mediaViewerSubTabId: _subViewer,
  };

  /// Which project the viewers were last filled from. A File ▸ Open
  /// replaces the project under this widget, and the references belong to
  /// the FILM — so the panels have to follow it rather than keep showing
  /// the last one's conte.
  ProjectId? _viewersSeededFrom;

  /// Puts each viewer back where the project left it (유저 확정 ⑤㉑).
  void _syncViewersWithProject() {
    final project = widget.session.repository.currentProject;
    if (project == null || project.id == _viewersSeededFrom) {
      return;
    }
    _viewersSeededFrom = project.id;
    for (final entry in _viewerSlots.entries) {
      final bookmark = project.mediaViewerBookmarks[entry.key];
      entry.value.restore(
        _requestForBookmark(bookmark, project),
        position: bookmark?.position ?? 0,
      );
    }
  }

  /// A remembered reference, or null when the app can no longer reach it.
  ///
  /// 유저 확정 ⑭: BOTH kinds come back — a pooled asset by its pool key
  /// (its name and kind are the pool's, which may have been renamed since)
  /// and a loose file by the absolute path it was opened from. A path
  /// that is neither is simply gone: the viewer comes back empty and says
  /// nothing, because a reference is not the work and losing one must not
  /// greet anybody with a dialog.
  MediaViewerRequest? _requestForBookmark(
    MediaViewerBookmark? bookmark,
    Project project,
  ) {
    if (bookmark == null) {
      return null;
    }
    final asset = project.mediaAssetByPath(bookmark.path);
    if (asset != null) {
      return MediaViewerRequest(
        path: asset.path,
        kind: asset.kind,
        name: asset.name,
      );
    }
    // Sync on purpose: this runs inside a notify, and a widget test's
    // fake-async zone never completes an awaited dart:io future.
    if (!File(bookmark.path).existsSync()) {
      return null;
    }
    return MediaViewerRequest(
      path: bookmark.path,
      kind: bookmark.kind,
      name: bookmark.name,
    );
  }

  /// Writes both viewers back into the project — no command, so no undo
  /// entry and no dirty flag (see [MediaViewerBookmark]).
  void _writeViewerBookmarks() {
    if (_viewersSeededFrom == null || !widget.session.repository.hasProject) {
      // Before the first seed there is nothing to write, and writing
      // would erase what we are about to read.
      return;
    }
    widget.session.repository.updateMediaViewerBookmarks(
      (_) => {
        for (final entry in _viewerSlots.entries)
          if (entry.value.request.value case final request?)
            entry.key: MediaViewerBookmark(
              path: request.path,
              kind: request.kind,
              name: request.name,
              position: entry.value.position.value,
            ),
      },
    );
  }

  /// The cel stores are the SESSION's (R5): the archive saves and loads
  /// them with the project; this controller owns only the edit sessions.
  late final ConteInkController _conteInk = ConteInkController(
    rowStore: widget.session.conteInkRowStore,
    pageStore: widget.session.conteInkPageStore,
  );

  late final CutEnvelopeInkController _envelopeInk = CutEnvelopeInkController(
    store: widget.session.envelopeInkStore,
  );

  late final StoryboardCutThumbnailStore _storyboardThumbnails;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 🚨The session asks, the workspace shows. A row drop that would throw
    // fx away holds itself until this answers (see [AttachFxConfirmController]).
    widget.session.attachFxConfirm.pending.addListener(_showAttachFxConfirm);
    _tipLibrary = BrushTipLibrary(service: widget.tipLibraryService);
    // 🚨The two canvas-side facts the PIXEL verbs need, published where both
    // of them are in scope. Getters, not copies: the marquee survives tool
    // switches and the colour changes under the pointer, so a value captured
    // here would be the one that was true when the editor opened.
    widget.session.pixelSelectionRegion = () =>
        widget.canvasSelectionCommands?.region;
    widget.session.pixelBrushColour = () => _brushTool.value.color;
    // The marquee, as the fifth selection kind — so one 선택 해제 can let go
    // of everything rather than half of it.
    widget.session.canvasHasSelection = () =>
        widget.canvasSelectionCommands?.hasRegion ?? false;
    widget.session.clearCanvasSelection = () =>
        widget.canvasSelectionCommands?.deselect();
    // H25: what the hand last set on each brush, from the last session.
    _brushTool.addListener(_rememberBrushHandSettings);
    unawaited(
      _brushHandSettingsStore.load().then((saved) {
        if (!mounted || saved.isEmpty) {
          return;
        }
        _brushHandSettings.addAll(saved);
      }),
    );
    _presetLibrary = BrushPresetLibrary(
      fileService: widget.presetFileService,
      filePicker: widget.brushFilePicker,
      tipLibrary: _tipLibrary,
    );
    // Tips first: presets reference them by id, so the library has to be
    // able to answer before the presets that ask are read.
    unawaited(
      _tipLibrary
          .load()
          .then((_) => _presetLibrary.load())
          .then((_) => _selectOpeningPreset()),
    );
    // Warm the conte's embedded faces so the sheet opens with its type
    // ready (the tab host still awaits, for the cold path).
    unawaited(ensureConteFontsLoaded());
    _storyboardThumbnails = StoryboardCutThumbnailStore(
      render: _renderStoryboardThumbnail,
      invalidationHub: widget.session.cacheInvalidationHub,
    );
    _layoutPersistence._layoutStore =
        widget.layoutStore ??
        (Platform.environment['FLUTTER_TEST'] == 'true'
            ? null
            : WorkspaceLayoutStore());
    unawaited(_layoutPersistence.restoreLayout());
    _cutPieceSlot.addListener(_armStampOnFreshCut);
    _layout.addListener(_layoutPersistence.scheduleLayoutSave);
    // Sizes no longer come through the model's own notifier, but they are
    // still persisted — the save has to hear them separately or a resized
    // dock would come back at its old width.
    _layout.extentRevision.addListener(_layoutPersistence.scheduleLayoutSave);
    for (final extent in _railExtents.values) {
      extent.addListener(_layoutPersistence.scheduleLayoutSave);
    }
    widget.panelsMenu?.attach(
      entriesProvider: _panelMenuEntries,
      toggler: _togglePanelVisibility,
      relay: _layout,
      layoutReset: _layoutPersistence.resetWorkspaceLayout,
      toolRailOnRight: () =>
          _layout.tabsIn(EditorWorkspace.toolRightGroupId).isNotEmpty,
      toolRailMover: _setToolRailOnRight,
      floorTabId: _tabs.activeFloorTabId,
      floorTabs: () => [
        for (final tabId in _tabs.floorTabIds())
          (
            tabId: tabId,
            label: _tabs.tabFor(tabId).label,
            icon: _tabs.tabFor(tabId).icon,
          ),
      ],
      floorTabSelector: _tabs.selectFloorTab,
      regionOnTop: () => _regionOnTop,
      regionMover: (onTop) {
        if (_regionOnTop == onTop) {
          return;
        }
        setState(() => _regionOnTop = onTop);
        _layoutPersistence.scheduleLayoutSave();
      },
    );
    widget.layerNav?.bind(this, _stepDisplayedLayer);
    widget.flipHud?.bind(this, _flipHudSnapshot);
    _syncFlipAxisWithTimeline();
    // The viewers follow the PROJECT: seed them from it now, and again
    // whenever a different one is opened under us.
    _syncViewersWithProject();
    widget.session.addListener(_syncViewersWithProject);
    for (final slot in _viewerSlots.values) {
      slot.request.addListener(_writeViewerBookmarks);
      slot.position.addListener(_writeViewerBookmarks);
    }
  }

  /// F-28: the canvas flip reads its frame direction off the sheet the user
  /// is looking at — 「타임라인패널 x시트일 경우 … 세로가 프레임이동 가로가
  /// 레이어이동 되도록. 그게 직관적임」.
  ///
  /// Told to the HUD rather than threaded down to the gesture layer: the HUD
  /// is already the one object this shell and the canvas gesture both hold,
  /// and it is the flip's own state.
  void _syncFlipAxisWithTimeline() {
    widget.flipHud?.framesRunVertically =
        _timelineOrientation.value == TimelineOrientation.vertical;
  }

  /// What the flip HUD draws: the rows the timeline is DISPLAYING, in its
  /// order, filtered and folded exactly as they are on screen.
  ///
  /// Same inputs as [_stepDisplayedLayer] on purpose — the window and the
  /// walk must not be able to disagree about which rows exist. The HUD
  /// reads this AFTER a step has landed; it never predicts one.
  FlipHudSnapshot _flipHudSnapshot(FlipHudAxis axis) {
    final session = widget.session;
    final cut = session.activeCutOrNull;
    if (cut == null) {
      // Parked in a GAP. There is no cut, so there are no layer rows —
      // but there IS a row: the track, whose blocks are its cuts. That is
      // the axis the flip actually walks here (`_flipCuts`), so the
      // window shows it rather than going blank on the one occasion you
      // most need to know where you are.
      return _flipHudTrackSnapshot(session);
    }
    final rows = buildTimelineDisplayRows(
      layers: horizontalLayerDisplayOrder(session.layers),
      expandedLayerIds: _expandedLaneLayerIds.value,
      lanesForLayer: (layer) => timelineLanesForLayer(
        layer: layer,
        session: session,
        expandedGroupKeys: _expandedLaneGroupKeys.value,
      ),
      hiddenSections: _hiddenTimelineSections.value,
      rowFilter: _timelineRowFilter.value,
      collapsedAttachBaseIds: _collapsedAttachBaseIds.value,
      activeLayerId: session.activeLayerId,
      fxEnabledOf: session.isLayerFxEnabled,
      stack: session.layers,
    );
    if (rows.isEmpty) {
      return FlipHudSnapshot.empty;
    }
    final currentRow = session.currentRow;
    var rowIndex = -1;
    for (var index = 0; index < rows.length; index += 1) {
      final row = rows[index];
      final address = row.isLane
          ? LaneRowAddress(row.layer.id, row.lane!.laneId)
          : LayerRowAddress(row.layer.id);
      if (address == currentRow) {
        rowIndex = index;
        break;
      }
    }
    if (rowIndex == -1) {
      // The row on record is not on screen — a track row (the storyboard
      // owns one), or a row a filter has hidden. The ↑/↓ walk falls back
      // to the active layer's own row in exactly this case, so the window
      // does too rather than pointing at whatever sits at the top.
      final activeLayerId = session.activeLayerId;
      for (var index = 0; index < rows.length; index += 1) {
        if (!rows[index].isLane && rows[index].layer.id == activeLayerId) {
          rowIndex = index;
          break;
        }
      }
    }
    if (rowIndex == -1) {
      rowIndex = 0;
    }
    // A frame-axis window draws ONE row, so only that row's blocks are
    // worth building. The others still take their place in the list (the
    // row index has to keep meaning what it means), but scanning every
    // layer's timeline for runs nobody draws is work per flip step.
    final onlyCurrent = axis == FlipHudAxis.frame;
    final hudRows = <FlipHudRow>[
      for (var index = 0; index < rows.length; index += 1)
        _collapsedRows.flipHudRow(
          rows[index],
          session,
          withRuns: !onlyCurrent || index == rowIndex,
        ),
    ];
    return FlipHudSnapshot(
      rows: hudRows,
      rowIndex: rowIndex,
      frameIndex: session.currentFrameIndex,
      // The axis has to reach wherever the cursor stands: rightward the
      // flip walks past the cut's end into the timeline's runway, and an
      // axis that stopped at the duration would show the last column as
      // the one you are on.
      frameCount: math.max(cut.duration, session.currentFrameIndex + 1),
      playbackFrameCount: cut.duration,
    );
  }

  /// The gap's window: one row — the track — with its cuts as blocks.
  ///
  /// Same model, same columns, same haptic rule; only the material
  /// changes, which is exactly what the flip itself does down in the
  /// session. A cut is a run, the space between cuts is uncovered.
  FlipHudSnapshot _flipHudTrackSnapshot(EditorSessionManager session) {
    final trackId = session.selectedTrackId;
    final entries = [
      for (final entry in session.projectTimelineLayout())
        if (entry.trackId == trackId) entry,
    ];
    if (entries.isEmpty) {
      return FlipHudSnapshot.empty;
    }
    final globalFrame = session.editingGlobalFrame;
    return FlipHudSnapshot(
      rows: [
        FlipHudRow(
          name: session.trackOwningCut(entries.first.cutId)?.name ?? 'Track',
          kind: LayerKind.storyboard,
          // A track is not a layer; the rail shows its name alone.
          showsKindIcon: false,
          // The space between cuts is not a missing drawing, so it
          // carries no timesheet X.
          holdsDrawings: false,
          runs: [
            for (final entry in entries)
              FlipHudRun(
                startIndex: entry.startFrame,
                length: entry.duration,
                label: entry.cut.name,
              ),
          ],
        ),
      ],
      rowIndex: 0,
      frameIndex: globalFrame,
      // Rightwards never runs out, so the playhead can stand PAST the
      // last cut. The axis has to reach wherever it is standing or the
      // window would show the final cut as the column you are on.
      frameCount: math.max(entries.last.endFrame, globalFrame + 1),
    );
  }

  // ── the collapsed rows: their own object, in their own file ─────────
  //
  // A collaborator (workspace/workspace_collapsed_rows.dart, a part of this library). The
  // State keeps the entry points its build tree calls as forwarders.
  late final _WorkspaceCollapsedRows _collapsedRows = _WorkspaceCollapsedRows(
    this,
  );

  /// ↑/↓ layer nav (UI-R20 #14): steps the active layer through the rows
  /// the timeline DISPLAYS. The inputs must mirror what this state hands
  /// the timeline tab (row filter, hidden sections, fx resolver) — a
  /// facet joining the display policy joins here too, or the keys and the
  /// screen disagree.
  void _stepDisplayedLayer(int direction) {
    final session = widget.session;
    final target = adjacentDisplayedRow(
      layers: session.layers,
      activeLayerId: session.activeLayerId,
      currentRow: session.currentRow,
      direction: direction,
      hiddenSections: _hiddenTimelineSections.value,
      rowFilter: _timelineRowFilter.value,
      collapsedAttachBaseIds: _collapsedAttachBaseIds.value,
      // R10 #19: property rows are stops now, so the walk needs the same
      // lane list the grids draw.
      expandedLayerIds: _expandedLaneLayerIds.value,
      lanesForLayer: (layer) => timelineLanesForLayer(
        layer: layer,
        session: session,
        expandedGroupKeys: _expandedLaneGroupKeys.value,
      ),
      fxEnabledOf: session.isLayerFxEnabled,
    );
    if (target == null || target is TrackRowAddress) {
      return;
    }
    // 🚨★★★ONE LAW, BOTH ENTRANCES. 유저 2026-08-27: 「플립이랑 화살표랑
    // **입구는 달라도 통하는건 하나**니까 둘 다 적용해야하는거지」 · 「플립으로
    // 레이어이동이든 화살표든 레이어이동도 똑같이 해야지」.
    //
    // This used to call `selectLayer` (and, for a lane, `selectRow` after
    // it) — which is exactly what [EditorSessionManager.standOnRow] does,
    // minus the one thing that matters: standing somewhere OUTSIDE the live
    // selection releases it. So clicking a row let a range go and walking to
    // the same row with the arrows kept it, and the frame flip — which does
    // clear — disagreed with its own sibling.
    //
    // ⛔The fix is not another `clearAllSelections()` here. The law has a
    // house, and the way to obey it is to walk through the door rather than
    // to copy the sentence written on it.
    session.standOnRow(target);
  }

  /// Every known panel in default-dock order, with its live visibility.
  List<WorkspacePanelEntry> _panelMenuEntries() => [
    for (final group in _defaultDocks().values)
      for (final tabId in group?.tabs ?? const <String>[])
        (
          tabId: tabId,
          label: _tabs.tabFor(tabId).label,
          visible: _layout.locateTab(tabId) != null,
        ),
  ];

  String _defaultDockOf(String tabId) {
    for (final entry in _defaultDocks().entries) {
      if (entry.value?.tabs.contains(tabId) ?? false) {
        return entry.key;
      }
    }
    return EditorWorkspace.leftGroupId;
  }

  void _togglePanelVisibility(String tabId) {
    if (_layout.locateTab(tabId) != null) {
      _tabs.closeTab(tabId);
    } else {
      _mutatingLayout(() {
        _layout.addTab(tabId, toDockId: _defaultDockOf(tabId));
      });
      _ensureRailOpen(_defaultDockOf(tabId));
    }
  }

  /// The COMMON "open or locate" entry (UI-R17 #5): hidden panels open
  /// into their default dock; an already-open panel fronts its tab and
  /// FLASHES so the user sees where it lives. Every non-Window "open
  /// panel" affordance should route here.
  /// A browser "open" — point ONE viewer at the asset and reveal that
  /// viewer's panel, through the common reveal verb so an already-open
  /// one fronts and flashes instead of duplicating.
  ///
  /// 유저 확정 ①: the DOUBLE-CLICK keeps going to the main viewer even
  /// though the main viewer is the floor, so a double-click still swaps
  /// the drawing away. The row menu's second entry is what opens beside
  /// the drawing instead.
  /// Said ONCE per disappearance, not once per resume: a person who has
  /// read it and chosen to carry on must not be asked again every time
  /// they alt-tab.
  bool _toldProjectFileVanished = false;

  Future<void> _warnIfProjectFileVanished() async {
    if (!widget.session.projectFileHasVanished()) {
      // Back again — restored from a trash, or re-synced. The next
      // disappearance is worth saying out loud too.
      _toldProjectFileVanished = false;
      return;
    }
    if (_toldProjectFileVanished || !mounted) {
      return;
    }
    _toldProjectFileVanished = true;
    await showAppNotice(
      context,
      windowKey: const ValueKey<String>('project-file-vanished-notice'),
      title: AppText.strings.commonNotice,
      message: AppText.strings.projectFileVanished,
    );
  }

  /// The pool's「WAV로 내보내기」: the session says which conform, the flow
  /// says where the file goes, and the writer streams it. False when the
  /// asset has no audio — the panel turns that into words.
  ///
  /// ⛔The conform is BUILT if this machine has not made it yet, rather
  /// than the item refusing on a file that simply has not been played. That
  /// is the same `ensureFor` playback would have called.
  Future<bool> _exportAssetWav(BuildContext context, MediaAsset asset) async {
    final conform = await widget.session.conformPathForExport(asset.path);
    if (conform == null || !context.mounted) {
      return conform != null;
    }
    await handWrittenFileToUser(
      context,
      suggestedName: '${asset.name}.wav',
      acceptedTypeGroups: const [FileTypeGroups.wav],
      write: (path) =>
          writeConformAsWav(conformPath: conform, destinationPath: path),
    );
    return true;
  }

  void _openAssetInViewer(MediaAsset asset, {required String tabId}) {
    _openInViewer(
      MediaViewerRequest(path: asset.path, kind: asset.kind, name: asset.name),
      tabId: tabId,
    );
  }

  void _openInViewer(MediaViewerRequest request, {required String tabId}) {
    _viewerSlot(tabId).open(request);
    _revealPanel(tabId);
  }

  /// 유저 확정 ②⑪⑯⑰⑳: the two viewers trade documents, and the one that
  /// receives is REVEALED. Without the reveal, pressing swap while the
  /// other viewer is closed reads as "my file just vanished" — the whole
  /// point of the button is to look at the thing somewhere else.
  void _swapViewers({required String fromTabId}) {
    _mainViewer.swapWith(_subViewer);
    _revealPanel(
      fromTabId == EditorWorkspace.mediaViewerSubTabId
          ? EditorWorkspace.mediaViewerTabId
          : EditorWorkspace.mediaViewerSubTabId,
    );
  }

  /// A media-browser row dropped ON a viewer (유저 확정 ⑬): the panel the
  /// row landed on is the one that opens it, so which viewer is chosen by
  /// where the hand went rather than by a menu entry.
  void _openDroppedAsset(MediaAssetDragData data, {required String tabId}) {
    final asset = widget.session.repository.currentProject?.mediaAssetByPath(
      data.path,
    );
    if (asset == null) {
      return;
    }
    // 유저 확정 ㉒: no kind filter. A sound dropped here lands on the
    // viewer's own "this kind has no viewer yet", which is exactly what
    // the row menu's open already does — refusing the drop instead would
    // make the same asset openable one way and not the other.
    _openAssetInViewer(asset, tabId: tabId);
  }

  void _revealPanel(String tabId) {
    final location = _layout.locateTab(tabId);
    if (location == null) {
      _mutatingLayout(() {
        _layout.addTab(tabId, toDockId: _defaultDockOf(tabId));
      });
      _ensureRailOpen(_defaultDockOf(tabId));
      return;
    }
    // An already-placed panel can still be out of sight — in a rail group
    // the user closed. Revealing it has to OPEN that group, or the flash
    // plays where nobody can see it.
    _ensureRailOpen(location.dockId);
    _mutatingLayout(() {
      _layout.selectTab(location.dockId, tabId);
    });
    _panelFlash.flash(tabId);
  }

  /// The one place that shows 「fx 가 사라집니다」, for every surface.
  ///
  /// ⚠️EVERY exit answers. A dialog dismissed by the barrier or by escape
  /// returns null, and a drop still held by an unanswered question would
  /// never commit and never let go — so null is a "no" here rather than a
  /// path that quietly does nothing.
  Future<void> _showAttachFxConfirm() async {
    final request = widget.session.attachFxConfirm.pending.value;
    if (request == null) {
      return;
    }
    final strings = AppText.strings;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        windowKey: const ValueKey<String>('attach-drops-fx-dialog'),
        title: strings.tlAttachDropsFxTitle,
        message: strings.tlAttachDropsFxBody,
        actions: [
          AppWindowAction(
            label: strings.commonCancel,
            actionKey: const ValueKey<String>('attach-drops-fx-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppWindowAction(
            label: strings.commonApply,
            actionKey: const ValueKey<String>('attach-drops-fx-confirm'),
            emphasis: AppWindowActionEmphasis.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    request.answer(proceed ?? false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.attachFxConfirm.pending.removeListener(_showAttachFxConfirm);
    _brushTool.removeListener(_rememberBrushHandSettings);
    // A pending debounce would write after the tree is gone; the values are
    // in memory, so writing them NOW is both safe and the last chance.
    if (_brushHandSettingsSave?.isActive ?? false) {
      _brushHandSettingsSave!.cancel();
      unawaited(
        _brushHandSettingsStore.save(
          Map<String, BrushHandSettings>.of(_brushHandSettings),
        ),
      );
    }
    _storyboardThumbnails.dispose();
    _presetLibrary.dispose();
    _tipLibrary.dispose();
    _cutPieceSlot.removeListener(_armStampOnFreshCut);
    // An injected tool notifier belongs to the shell; only a local
    // fallback is ours to dispose.
    if (widget.brushTool == null) {
      _brushTool.dispose();
    }
    _fillOptions.dispose();
    _transformOptions.dispose();
    _eyedropperSource.dispose();
    _cameraViewEnabled.dispose();
    _cameraDimOpacity.dispose();
    _timelineOrientation.dispose();
    _timelinePixelsPerFrame.dispose();
    _storyboardPixelsPerFrame.dispose();
    _storyboardTrackLaneHeight.dispose();
    _showSecondsDisplay.dispose();
    _expandedLaneLayerIds.dispose();
    _expandedLaneGroupKeys.dispose();
    _hiddenTimelineSections.dispose();
    _collapsedAttachBaseIds.dispose();
    _timelineRowFilter.dispose();
    _bottomInsetOverride.dispose();
    for (final controller in _railScrollControllers.values) {
      controller.dispose();
    }
    _panelFlash.dispose();
    _timesheetContinuous.dispose();
    _timesheetPage.dispose();
    _timesheetViewport.dispose();
    _timesheetInkEnabled.dispose();
    _timesheetInk.dispose();
    _conteViewport.dispose();
    _conteInkEnabled.dispose();
    _conteInk.dispose();
    _envelopeViewport.dispose();
    _envelopeInkEnabled.dispose();
    _envelopeImages.dispose();
    _envelopeFormId.dispose();
    _envelopeInk.dispose();
    widget.session.removeListener(_syncViewersWithProject);
    for (final slot in _viewerSlots.values) {
      slot.request.removeListener(_writeViewerBookmarks);
      slot.position.removeListener(_writeViewerBookmarks);
    }
    _mainViewer.dispose();
    _subViewer.dispose();
    _draggingTab.dispose();
    widget.layerNav?.unbind(this);
    widget.flipHud?.unbind(this);
    widget.panelsMenu?.detach();
    _layoutPersistence._layoutSaveTimer?.cancel();
    _layout.removeListener(_layoutPersistence.scheduleLayoutSave);
    _layout.extentRevision.removeListener(_layoutPersistence.scheduleLayoutSave);
    for (final extent in _railExtents.values) {
      extent
        ..removeListener(_layoutPersistence.scheduleLayoutSave)
        ..dispose();
    }
    _layout.dispose();
    super.dispose();
  }

  /// Thumbnails render the cut's thumbnail frame THROUGH THE CAMERA (what
  /// the shot actually frames — conte-sheet style), scaled to a small
  /// output; always current (a fresh renderer replays surfaces straight
  /// from the brush store).
  /// [frameIndex] is the PANEL's frame — the store keys by it, and the
  /// panel resolved which one it is (its own division, or the cut's pin
  /// when that falls inside it). Clamped here so a later trim can never
  /// break a request that was legal when it was made.
  Future<ui.Image?> _renderStoryboardThumbnail(
    Cut cut,
    int frameIndex,
    int thumbnailWidth,
  ) {
    final cameraSize = widget.session.cameraFrameSize;
    final height = math.max(
      1,
      (thumbnailWidth * cameraSize.height / cameraSize.width).round(),
    );
    return ExportFrameRenderer(session: widget.session).renderComposite(
      ExportFrameTask(
        cut: cut,
        frameIndex: frameIndex.clamp(0, math.max(0, cut.duration - 1)).toInt(),
      ),
      ExportSizeMode.camera,
      outputSize: CanvasSize(width: thumbnailWidth, height: height),
    );
  }

  void _applyPreset(BrushPreset preset) {
    // Applying a preset KEEPS the active painting tool (R11-④: the eraser
    // owns its own preset choice); from a non-painting tool it arms the
    // brush. Which settings survive the swap is the state's own rule —
    // see [BrushToolState.withPresetSettings].
    final current = _brushTool.value;
    final targetTool = canvasToolPaints(current.tool)
        ? current.tool
        : CanvasTool.brush;
    _brushTool.value = current.withPresetSettings(
      preset.settings,
      tool: targetTool,
      // H25: what the hand last set on THIS brush, or nothing — in which case
      // the brush's own baked size wins.
      handSet: _brushHandSettings[preset.id.value],
    );
    _activePresetByTool[targetTool] = preset.id;
    _presetLibrary.markActive(preset.id);
  }

  /// 🚨★★★THE LIBRARY OPENS SHOWING THE BRUSH THAT IS IN HAND.
  ///
  /// 유저 (F-63): 「브러시/지우개에서, 브러시 라이브러리에서 **초기값이
  /// 아무것도 선택안된 UI**인데, 브러시는 그려지는거 보니 **초기 브러시자체는
  /// 정해져있는거같음.** 그게 ui에도 연동되있도록」.
  ///
  /// ⛔They are exactly right, and the cause is that there were TWO facts:
  /// `PaintToolStateNotifier` opened with baked-in settings while
  /// `_activePresetByTool` opened EMPTY, so the app drew with a brush the
  /// library could not name. Nothing was persisted either way — the map is
  /// not saved — so no remembered choice is being overwritten here.
  ///
  /// ⇒ Applying a preset makes them ONE fact: the tool takes its settings,
  /// the panel highlights it, and H25's per-brush size/opacity comes back
  /// with it. ⚠️Through `_applyPreset`, not by writing the map — writing
  /// only the id would put the highlight on a brush the tool is not holding,
  /// which is the same disagreement pointing the other way.
  ///
  /// ⚠️Silent when the library is empty (a reset that saved nothing) and
  /// when a tool already has a preset — a load that lands after the user has
  /// picked must not overrule them.
  void _selectOpeningPreset() {
    if (!mounted) {
      return;
    }
    final tool = _brushTool.value.tool;
    final preset = openingPresetFor(
      presets: _presetLibrary.presets,
      toolPaints: canvasToolPaints(tool),
      alreadyChosen: _activePresetByTool[tool] != null,
    );
    if (preset == null) {
      return;
    }
    _applyPreset(preset);
  }

  /// The group the tool's active preset sits in — where a newly saved
  /// preset joins.
  BrushGroupId? _activePresetGroupId(CanvasTool tool) {
    final activeId = _activePresetByTool[tool];
    if (activeId == null) {
      return null;
    }
    for (final preset in _presetLibrary.presets) {
      if (preset.id == activeId) {
        return preset.groupId;
      }
    }
    return null;
  }

  Future<void> _importTipImage() async {
    final message = await _tipLibrary.importFromFile();
    if (message == null || !mounted) {
      return;
    }
    unawaited(
      showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: message,
      ),
    );
  }

  Future<void> _importBrushFile() async {
    final message = await _presetLibrary.importFromFile();
    if (message == null || !mounted) {
      return;
    }
    unawaited(
      showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: message,
      ),
    );
  }

  /// Runs a layout mutation and clamps the playhead when the storyboard
  /// just came on screen (over-end playheads on non-last cuts must land
  /// back on the counter frame — timeline parity).
  void _mutatingLayout(VoidCallback mutate) {
    final wasVisible = _layoutPersistence.isStoryboardVisible;
    mutate();
    if (!wasVisible && _layoutPersistence.isStoryboardVisible) {
      clampPlayheadForStoryboard(widget.session);
    }
  }

  /// Putting a panel somewhere OPENS that somewhere.
  ///
  /// A rail group can be closed, and a panel placed into a closed one is a
  /// panel that has silently disappeared — the same failure whether it was
  /// dropped there, reopened from the Panels menu, or revealed by a browser
  /// "open". So every path that places a panel comes through here rather
  /// than each remembering on its own.
  void _ensureRailOpen(String dockId) {
    if (!dockId.startsWith('rail-') || _openRails.contains(dockId)) {
      return;
    }
    setState(() => _openRails.add(dockId));
    _layoutPersistence.scheduleLayoutSave();
  }

  /// Moves the tool strip to the requested edge (the left-handed choice).
  ///
  /// This used to be a tab drag across the workspace. With 고정 도킹 the
  /// tab has no grip, so the choice needed a switch — and it lands in the
  /// LAYOUT, which is already persisted, rather than a new setting file.
  void _setToolRailOnRight(bool onRight) {
    final from = onRight
        ? EditorWorkspace.toolLeftGroupId
        : EditorWorkspace.toolRightGroupId;
    final to = onRight
        ? EditorWorkspace.toolRightGroupId
        : EditorWorkspace.toolLeftGroupId;
    final tabs = _layout.tabsIn(from);
    if (tabs.isEmpty) {
      return; // Already on the requested edge.
    }
    _mutatingLayout(() {
      for (final tabId in tabs) {
        _layout.moveTab(
          tabId: tabId,
          toDockId: to,
          insertIndex: _layout.tabsIn(to).length,
        );
      }
    });
  }

  /// The dual swatch, when [railId] is the group holding the colour picker.
  ///
  /// Null everywhere else: a rail button says what it holds with the glyph
  /// of its first panel, and this is the one panel whose STATE is the thing
  /// worth saying.
  Widget? _colorRailFace(String railId) {
    final background = widget.colorBackground;
    if (background == null) {
      return null;
    }
    final holdsColor = _layout
        .tabsIn(railId)
        .contains(EditorWorkspace.colorWheelTabId);
    if (!holdsColor) {
      return null;
    }
    return SlicedValueListenableBuilder<BrushToolState, int>(
      valueListenable: _brushTool,
      slice: (state) => state.color,
      builder: (context, toolState) => ValueListenableBuilder<int>(
        valueListenable: background,
        // Keeps the swatch's long-standing name: it changed address, not
        // identity, and every finder that means "the colour control" says
        // this.
        builder: (context, backgroundColor, _) => ColorSlotPair(
          key: const ValueKey<String>('tool-color-button'),
          keyPrefix: 'tool-color',
          foreground: Color(toolState.color),
          background: Color(backgroundColor),
          // The Photoshop gesture, carried by the BACK SLOT itself.
          onBackgroundTap: () {
            final foreground = _brushTool.value.color;
            _brushTool.value = _brushTool.value.copyWith(
              color: backgroundColor,
            );
            background.value = foreground;
          },
        ),
      ),
    );
  }

  /// A panel dropped on a rail button JOINS that group and opens it —
  /// dropping something out of sight would be a silent move.
  void _dropIntoRailGroup(String railId, EditorPanelTabDragData data) {
    final tabs = _layout.tabsIn(railId);
    _mutatingLayout(() {
      _layout.moveTab(
        tabId: data.tabId,
        toDockId: railId,
        insertIndex: tabs.length,
      );
    });
    setState(() => _openRails.add(railId));
    _layoutPersistence.scheduleLayoutSave();
  }

  /// One rail's COLUMN: every group the user has open on that side,
  /// stacked, sharing the rail's height.
  ///
  /// The sharing is the same water-filling the sections inside one dock
  /// already use ([dockSectionExtents]): each group is paid what its own
  /// panels need before anyone gets surplus, and when the rail cannot pay
  /// every floor they shrink together rather than starving whoever is last.
  /// There is deliberately NO splitter between groups — the rail's one
  /// splitter is its inner edge, and its height is divided rather than
  /// negotiated (유저 확정).
  ///
  /// [width] is the extent AFTER the workspace clamped both rails to what
  /// the window can actually spare.
  /// One scroller per rail, keyed by which rail it is. They exist whether
  /// or not the rail is currently overflowing — attaching is the scroll
  /// view's business, and the bar reads dimensions off the position.
  final Map<bool, ScrollController> _railScrollControllers = {
    false: ScrollController(),
    true: ScrollController(),
  };

  /// The pasteboard a rail leaves between two open groups, above the first
  /// one, and between the strip and all of them.
  ///
  /// It is what makes them read as floating objects rather than one column
  /// cut into pieces — the same job the margin around the bottom region
  /// does, and the reason a side panel is now the same KIND of thing as
  /// the timeline instead of a slab bolted to the strip (유저, R2 #7).
  static const double _railGroupGap = 8;

  /// One rail group's height: what it was left at, floored by what its
  /// panels need and capped by the rail.
  ///
  /// ⚠️Not a share of the rail. The rail used to divide its height between
  /// whatever was open, so opening a second group resized the first —
  /// which is a column's behaviour, not a floating panel's. 유저 확정: the
  /// saved height is FIXED, and a rail that cannot fit them all scrolls.
  double _railGroupHeight(String railId, double railExtent) {
    final floor = _verticalDockMinimumExtent(railId);
    final wanted = math.max(
      floor,
      _layout.dockExtent(railId, fallback: EditorWorkspace.railGroupHeight),
    );
    return railExtent.isFinite ? math.min(wanted, railExtent) : wanted;
  }

  /// The panel HOSTS of one rail, built once per workspace build and handed
  /// to [_buildRailColumn] rather than built inside it.
  ///
  /// ★A host does not depend on any extent — only on WHAT is docked — so
  /// building it inside the extent builder made every splitter frame
  /// rebuild every open panel on both rails. Hoisting it means the element
  /// tree sees the identical widget instance and skips the subtree
  /// wholesale, exactly the way the floor rides through as a `child:`.
  Map<String, Widget> _railHosts({required bool right}) => {
    for (final id in _openRailGroups(right: right)) id: _docks.buildDockHost(id),
  };

  /// The VERTICAL band one rail's column actually occupies, in the floor's
  /// own coordinates — or null when that rail has nothing open.
  ///
  /// A rail panel keeps the height it was left at, so an open rail covers a
  /// band and not a whole edge. Anything deciding whether it is IN THE WAY
  /// has to compare against this rather than against the width alone.
  ({double top, double bottom})? _railBand({
    required bool right,
    required double stop,
    required bool onTop,
    required double height,
    required DeviceGrid grid,
  }) {
    final open = _openRailGroups(right: right);
    if (open.isEmpty) {
      return null;
    }
    // The band's own top is a link in the chain to a rail-docked canvas:
    // the panel, and anything docked in it, begins here. `stop` is
    // already on the grid, and `position` composes exactly against a
    // snapped anchor — so this carries ONE rounding for the whole thing
    // rather than one for the stop and another for the gap.
    final top = grid.position((onTop ? stop : 0) + _railGroupGap);
    final available = math.max(0.0, height - top - (onTop ? 0 : stop));
    // 🚨★★The band has to be laid out by the SAME arithmetic as the
    // column, in the same order, or it describes a rail that is not
    // drawn. The column runs `take(height)` then `take(gap)` per group, so
    // this runs the identical sequence and reads the position after the
    // last HEIGHT — the trailing gap is taken and never counted, exactly
    // as there.
    //
    // ⛔A raw sum here became measurably wrong the moment the column
    // became a run: driven on a height grip, 40 of 40 steps disagreed at
    // 1.125, 1.25 and 1.35, worst 0.98 device px. It reproduced at 1.25,
    // where every other quantization in this round is inert — which is
    // what identified the run conversion as the cause rather than the
    // ratio.
    //
    // ⚠️The two loops are still hand-duplicated: this one measures against
    // `available`, the column against its own `railExtent`. They agree by
    // care rather than by construction, and the honest fix is for the
    // column to publish its geometry — a larger change than this round.
    final run = grid.run(from: top);
    var contentEnd = top;
    for (final id in open) {
      run.take(_railGroupHeight(id, available));
      contentEnd = run.position;
      run.take(_railGroupGap);
    }
    final content = contentEnd - top;
    return (top: top, bottom: top + math.min(content, available));
  }

  Widget _buildRailColumn(
    EditorPanelDockSide side, {
    required double width,
    required Map<String, Widget> hosts,

    /// D37's "up to ¾ of the centre", resolved against what the OTHER dock
    /// is taking — so the grip stops where the drawn width stops.
    ///
    /// ⚠️Passed in rather than computed here: only the caller knows the
    /// window, and a grip whose ceiling disagreed with the layout's would
    /// spend the drag moving a number nobody draws.
    required double dragCeiling,
  }) {
    final right = side == EditorPanelDockSide.right;
    final open = _openRailGroups(right: right);
    if (open.isEmpty) {
      // ⛔NO drop zone beside a closed rail (유저, R4 #7: 사이드에는 어차피
      // 띠에 버튼으로 추가하는거랑 똑같은 기능이니까 필요없다).
      //
      // A tall band appeared here whenever a tab lifted, and it offered
      // nothing the strip did not: `_buildRailButtons` already puts a drop
      // target on every group button AND raises one for the rail's first
      // empty slot for exactly as long as something is in flight. So the
      // band was a second door onto the same room, drawn across a third of
      // the window.
      //
      // The BOTTOM dock keeps its zone (`_buildBottomDock`) and so does an
      // emptied floor (`_buildCenterDock`) — those two have no strip button
      // standing in for them, so removing their band would leave a panel
      // dropped there with no way back.
      return const SizedBox.shrink();
    }
    // NO fill and NO border. A rail is not a container of panels, it is a
    // place panels float beside; anything painted here puts them back in a
    // box and undoes every rounded corner inside it.
    //
    // The box spans the GAP as well as the panels: that strip of pasteboard
    // between the strip and the panels is where the rail's own scrollbar
    // rides (유저, R3 #12), so it has to be inside something that knows
    // whether the rail is scrolling.
    return SizedBox(
      key: ValueKey<String>('editor-panel-dock-${right ? 'right' : 'left'}'),
      width: width + _railGroupGap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final colorScheme = Theme.of(context).colorScheme;
          final railExtent = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : double.infinity;
          final heights = [
            for (final id in open) _railGroupHeight(id, railExtent),
          ];
          var content = 0.0;
          for (final height in heights) {
            content += height + _railGroupGap;
          }
          content -= _railGroupGap;

          // Each open group is its OWN floating object: the app's corner,
          // clipped so the corner is real rather than painted, and a gap of
          // pasteboard between it and its neighbour.
          //
          // ★Its grips live INSIDE that clip, laid along the two edges they
          // resize. The clip is what makes them read as the panel's own edge
          // lighting up rather than as a bar parked beside it — a 5px band
          // cannot carry a 14px corner by itself (유저, R2 #11).
          Widget group(int i) {
            final railId = open[i];
            return SuperellipseClip(
              shape: AppShapes.container(AppShapes.floatingPanelRadius),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: colorScheme.surface,
                        shape: AppShapes.container(
                          AppShapes.floatingPanelRadius,
                        ),
                      ),
                      child: hosts[railId] ?? const SizedBox.shrink(),
                    ),
                  ),
                  // The WIDTH grip, on this panel's inner edge — the edge
                  // facing the artwork. Every group has one and they all
                  // write the rail's single width, so the rail stays one
                  // column wide however many panels are on it.
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: right ? 0 : null,
                    right: right ? null : 0,
                    width: DockEdgeSplitter.thickness,
                    child: DockEdgeSplitter(
                      key: ValueKey<String>('dock-resize-$railId'),
                      axis: Axis.vertical,
                      onDragDelta: (delta) {
                        // ⚠️The sign flip has to be UNDONE on the way back.
                        // A right rail grows as the pointer moves LEFT, so
                        // reporting the width's own delta would hand the
                        // splitter a debt pointing the wrong way — and a
                        // debt with the wrong sign is worse than none: it
                        // would make the edge run ahead instead of behind.
                        final used = _layout.resizeDock(
                          EditorWorkspace.railWidthKey(right: right),
                          right ? -delta : delta,
                          fallback: width,
                          maxExtent: dragCeiling,
                        );
                        return right ? -used : used;
                      },
                    ),
                  ),
                  // The HEIGHT grip, on this panel's bottom edge. It costs
                  // no layout, so the gap below stays a gap.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: DockEdgeSplitter.thickness,
                    child: DockEdgeSplitter(
                      key: ValueKey<String>('dock-resize-$railId-height'),
                      axis: Axis.horizontal,
                      onDragDelta: (delta) => _layout.resizeDock(
                        railId,
                        delta,
                        fallback: EditorWorkspace.railGroupHeight,
                        minExtent: _verticalDockMinimumExtent(railId),
                        // The RAIL is the ceiling, not the model's default
                        // 640: that number guards a width, and a panel's
                        // height here can legitimately be more than it on a
                        // tall window and must be less than it on a short
                        // one. Without this the grip banked height the rail
                        // could never show and then dragged dead on the way
                        // back — measured: 60px of return travel moved the
                        // edge 9px. It is the same defect this round already
                        // fixed for the floating region.
                        maxExtent: railExtent.isFinite ? railExtent : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // The rail's own cumulative chain, and the textbook case for a
          // run: floor each cumulative POSITION and take each extent as
          // the difference of neighbours. ⛔Snapping `heights[i]` and
          // `_railGroupGap` on their own instead would drift — n groups
          // would carry n roundings, all in the same direction, and the
          // last panel would walk off the rail's bottom.
          //
          // ⚠️A gap of 8 is 9 device px at 1.125 and 10.8 at 1.35, so the
          // run legitimately hands back slightly different gaps; that is
          // the residue landing where it must rather than accumulating.
          final children = <Widget>[];
          final run = DeviceGrid.of(context).run();
          for (var i = 0; i < open.length; i += 1) {
            final top = run.position;
            final height = run.take(heights[i]);
            children.add(
              Positioned(
                left: 0,
                right: 0,
                top: top,
                height: height,
                child: group(i),
              ),
            );
            run.take(_railGroupGap);
          }

          final column = SizedBox(
            height: content,
            child: Stack(clipBehavior: Clip.none, children: children),
          );
          // The panels themselves keep their own width; the gap beside them
          // is the rail's, and belongs to the strip side.
          // The gap beside the strip. It is a link in the chain to the
          // RAIL-DOCKED canvas — everything inside the rail panel starts
          // after it — and 8 × 1.35 is 10.8, so it is off the grid at
          // exactly the product ratios a UI scale produces.
          final gap = DeviceGrid.of(context).position(_railGroupGap);
          Widget inGap(Widget child) => Padding(
            // Keyed so the quantization can be PINNED. It is otherwise
            // unobservable from the canvas: 8 is already integral at
            // 1.125, 1.25 and 1.75, and at 1.35 — the one ratio where it
            // matters — a larger fraction upstream still dominates the
            // rail-docked boundary. Unpinned quantization is quantization
            // that a later edit undoes in silence.
            key: const ValueKey<String>('rail-group-gap'),
            padding: EdgeInsets.only(
              left: right ? 0 : gap,
              right: right ? gap : 0,
            ),
            child: child,
          );
          // 🚨★★★ ONE TREE SHAPE, ALWAYS (R6-⑤, 유저: 「아래스플리터가
          // 조작중에 멋대로 그립이 풀려버림. 클릭중인데도.」)
          //
          // This used to return two DIFFERENT trees — `Padding > Align >
          // column` under the rail's height, `Stack > … > SingleChildScrollView
          // > column` over it. Dragging the bottom height grip changes
          // `content`, so crossing that boundary swapped the trees, element
          // matching failed, and the whole column was rebuilt from scratch —
          // taking with it the State of the very `DockEdgeSplitter` the hand
          // was holding. The grip released itself mid-drag, while the button
          // was still down. The colour wheel and the timesheet hit it because
          // they are tall enough to sit near the boundary.
          //
          // ★The user's rule (넘칠 때만 스크롤) survives for free: a
          // `SingleChildScrollView` whose content fits has min == max extent,
          // and Flutter drops its drag recognizer at that point
          // (`shouldAcceptUserOffset`). So the scroller is always MOUNTED and
          // only sometimes LIVE, which is exactly what was wanted — and the
          // tree stops changing shape under a live gesture.
          final overflowing = railExtent.isFinite && content > railExtent;
          final controller = _railScrollControllers[right]!;
          return Stack(
            children: [
              Positioned.fill(
                // ⛔NOT the Material scrollbar. The framework's desktop
                // behaviour puts one on every vertical scrollable, and that
                // one fades out and FATTENS under the pointer — both of
                // which the app's own bar was written not to do (유저: 어떤
                // 레일이든 눌렀다고 크기가 바뀌지 않는다).
                child: inGap(
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      key: ValueKey<String>(
                        'rail-scroll-${right ? 'right' : 'left'}',
                      ),
                      controller: controller,
                      // 🚨★★ THE RAIL OWNS ITS PANELS, NOT ITS COLUMN
                      // (유저 2026-08-15 #1: 「작은거 열면 밑에 공간 남는데
                      // 그 공간에서 터치가 안먹힘」 — 그리기도 안 됐다).
                      //
                      // The column is laid out full height whatever is open
                      // on it, and it has to be: R6-⑤ pinned ONE tree shape
                      // so a live splitter drag cannot rebuild itself away.
                      // But a scroller's default `hitTestBehavior` is
                      // `opaque`, so that full-height rectangle took every
                      // pointer that entered it — and the floor is
                      // full-bleed underneath, so the pasteboard below a
                      // short panel was a pane of glass over live canvas.
                      // One hit test stopping stops every verb at once:
                      // the tap, the stroke, the hover, the wheel.
                      //
                      // Deferring to the child says the true thing instead
                      // — the rail owns exactly the rectangles its panels
                      // occupy — and it says it without changing the tree.
                      // ⚠️Nothing is lost when the rail DOES scroll: then
                      // the content fills the viewport and there is no
                      // empty space to have dragged in.
                      hitTestBehavior: HitTestBehavior.deferToChild,
                      // Top-aligned when it does not fill, which is what the
                      // `Align` used to do on the non-scrolling branch.
                      //
                      // ⚠️OUTERMOST FIRST: this rail is the outer scroller
                      // of the app's deepest chain, and a leaf corrected
                      // under an uncorrected ancestor buys nothing —
                      // measured 4.985e-1 inner-only against 1.4e-14 with
                      // both.
                      child: DeviceGridScrollBody(
                        controller: controller,
                        axisDirection: AxisDirection.down,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: column,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 띠랑 패널 사이공간에 (유저, R3 #12). The bar rides the gap
              // between the strip and the panels rather than the panels'
              // far edge, where it lay on whatever the panel had there and
              // pointed away from the strip it belongs to. The lane IS the
              // gap — narrower than the app's other lanes, and it can be,
              // because nothing else is within reach of it to mis-hit.
              // The BAR stays conditional — it is the one thing here that
              // should appear only while there is something to scroll, and
              // adding or removing it cannot disturb the column: it is a
              // SIBLING in the stack, not an ancestor.
              if (overflowing)
                Positioned(
                  left: right ? null : 0,
                  right: right ? 0 : null,
                  top: 0,
                  bottom: 0,
                  width: _railGroupGap,
                  child: AppControllerScrollbar(
                    controller: controller,
                    axis: Axis.vertical,
                    thumbKey: ValueKey<String>(
                      'rail-scroll-thumb-${right ? 'right' : 'left'}',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The HEIGHT floor each frame-axis panel states for itself, replacing
  /// the flat 280 all three used to share.
  ///
  /// That 280 is what the user reported (2026-08-02): shrinking the dock
  /// did not shrink the panel, it rendered the panel at 280 inside the tab
  /// shell's vertical scroller and CUT the bottom off — the pinned
  /// horizontal scrollbar row first, then the foot of the vertical
  /// scrollbar rail. At the dock's own minimum 150px was already gone.
  ///
  /// Each panel states what it actually costs, so the body is what shrinks
  /// and the rows the user needs to see stay on screen. BOTH places a
  /// height gets handed out honour it — [_verticalDockMinimumExtent] for
  /// the dock splitter, [dockSectionExtents] for the sections inside a
  /// dock. The shell's scroller is left as the guard for what neither can
  /// reach: an unbounded parent, or a dock too small to pay every section's
  /// floor at once.
  /// The WIDTH a frame-axis panel insists on, or null for one that has no
  /// opinion.
  ///
  /// 🐛유저, R3 #11: the conte and the envelope had one, and they should
  /// not. A panel narrower than its minimum renders at the minimum inside a
  /// horizontal scroller, so in a 260px rail the page laid out 640 wide and
  /// everything pinned to its right edge went off the end — the vertical
  /// panbar vanished outright and the horizontal one lost its tail. That is
  /// correct for a sheet made of COLUMNS, where scrolling sideways is what
  /// helps; it is wrong for a page that scales, which has no column to
  /// protect and a Fit button to answer with instead.
  double? _minContentWidthFor(String tabId) => switch (tabId) {
    EditorWorkspace.conteTabId || EditorWorkspace.envelopeTabId => null,
    _ => EditorWorkspace._frameAxisMinContentWidth,
  };

  double? _minContentHeightFor(String tabId) => switch (tabId) {
    // NOT one number for this tab: the x-sheet is the timeline toggled on
    // its side, and standing the rail up spends the panel's HEIGHT on what
    // the timeline spends its width on. Sharing the timeline's floor fits
    // the sheet without overflowing it and leaves its column headers a
    // 31px window — under the scrollbar's own 32px thumb minimum, so
    // nothing scrolls and nothing is readable. A floor that fits and is
    // useless is not a floor.
    EditorWorkspace.timelineTabId =>
      _timelineOrientation.value == TimelineOrientation.horizontal
          ? TimelinePanel.minPanelHeight
          : TimelinePanel.minSheetPanelHeight,
    EditorWorkspace.storyboardTabId => StoryboardTabHost.minPanelHeight,
    // The conte has no fixed ROWS — it is a page that scales — but it does
    // have one conditional chrome row, the action field under a selected
    // cell, and that row is not flexible.
    EditorWorkspace.conteTabId => ConteTabHost.minPanelHeight,
    // The envelope has no case here on purpose: a page that scales, with
    // no chrome row under the shell, has nothing of its own to protect.
    _ => null,
  };

  /// What a dock laid out along the VERTICAL axis needs before its panels
  /// start losing rows: its strip plus the tallest floor among its tabs.
  /// Same helper the rail divides by, so the number the splitter stops on
  /// is the number the layout will actually honour.
  double _verticalDockMinimumExtent(String dockId) {
    final tabs = _layout.tabsIn(dockId);
    if (tabs.isEmpty) {
      return 0;
    }
    return panelGroupFloorExtent([for (final tabId in tabs) _tabs.tabFor(tabId)]);
  }

  bool _bottomDockCollapsed = false;

  /// How far the floating region is pulled in from BOTH side edges, once
  /// somebody has SAID how far. Null means nobody has, and the default
  /// below answers instead.
  ///
  /// One number, not two: 아래 패널은 좌우 대칭 축소 (유저 확정). And the
  /// centre it stays on is the WINDOW's, never the visible canvas's —
  /// otherwise opening a rail column would slide the timeline sideways
  /// under the hand that opened it.
  /// A NOTIFIER and not a field: this is a size, and sizes ride the thin
  /// signal ([EditorPanelLayoutModel.extentRevision] is the other one) so a
  /// drag frame relays the workspace out without rebuilding the canvas and
  /// every open panel. Behind `setState` this grip was the last one still
  /// paying for a full rebuild per frame.
  final ValueNotifier<double?> _bottomInsetOverride = ValueNotifier<double?>(
    null,
  );

  /// The UN-detented value a side drag is accumulating.
  ///
  /// 🐛Without it the detent ate the drag: every frame added its few pixels
  /// to the SNAPPED value, landed back inside the detent window and snapped
  /// again, so once the edge touched the rail's width a slow drag could
  /// never leave it — "커서가 움직이는것보다 적게 움직임". The magnet is
  /// supposed to hold the RESULT, not to swallow the travel.
  double? _bottomInsetDragRaw;

  /// 하단 패널은 화면의 2/3정도 (유저 확정, R3 #10).
  ///
  /// A FRACTION rather than a stored pixel count, because the default has
  /// to mean the same thing on every window: a saved 300px inset is a
  /// third of a 1800px window and the whole of a 640px one. The moment the
  /// user drags an edge the answer becomes theirs ([_bottomInsetOverride])
  /// and stops following the window.
  static const double _defaultBottomRegionWidthFraction = 2 / 3;

  /// The inset in force for a window this wide.
  double _bottomInsetFor(double windowWidth) {
    final chosen = _bottomInsetOverride.value;
    if (chosen != null) {
      return chosen;
    }
    final wanted = windowWidth * (1 - _defaultBottomRegionWidthFraction) / 2;
    // …but the DEFAULT never squeezes the region below what its panels lay
    // out at. Under that width the timeline renders at its own minimum
    // inside a sideways scroller — which is a fine answer to a window
    // somebody made small, and a terrible one to arrive at by itself. Drag
    // the edge in past here and you get it; the app does not choose it.
    final floor = math.min(
      windowWidth,
      EditorWorkspace._frameAxisMinContentWidth,
    );
    return math.max(0.0, math.min(wanted, (windowWidth - floor) / 2));
  }

  /// Which edge the floating region is docked to.
  ///
  /// 아래 도킹 영역은 위/아래 설정 가능 (유저 확정), and NO new rule was
  /// needed to say what flips with it: 「기하는 캔버스 향한 변에, 정체성은
  /// 창틀 향한 변에」 already decides every piece. Docked at the top, the
  /// edge facing the artwork is the BOTTOM one — so the resize handle goes
  /// there and the 문턱 goes above it, and the region's square corners move
  /// to whichever side is against the frame. One flag, and the law does the
  /// rest.
  bool _regionOnTop = false;

  /// How close to the rail's width counts as "the same", so the edge lands on
  /// the pass-through boundary instead of just beside it.
  ///
  /// The rule that boundary decides ([_railPassesBottom]) has no mode and no
  /// switch — it is a comparison — so the only way to CHOOSE it is to be
  /// able to stop the drag exactly there.
  static const double _bottomInsetDetent = 14;

  /// ★ Whether a rail's column runs PAST the floating region to the window's
  /// bottom edge, or stops at its top edge.
  ///
  /// One comparison, and deliberately not a setting: the column can go down
  /// there exactly when the region has pulled far enough in to leave room,
  /// which is something the user can see. [railWidth] is that rail's shared
  /// width plus its splitter — the space the column actually occupies.
  static bool _railPassesBottom({
    required double bottomInset,
    required double railWidth,
  }) => bottomInset >= railWidth;

  /// The narrowest the floating region may be pulled: past this it stops
  /// being a panel you can read and starts being a sliver.
  static const double _minBottomRegionWidth = 320;

  /// One side grip of the floating region.
  ///
  /// Both drive the SAME number, mirrored — 좌우 대칭 축소 — and both stop
  /// on the pass-through boundary, so choosing "the columns go down past
  /// the region" is something the hand can land on rather than something a
  /// menu has to offer.
  ///
  /// ★They also stop SHORT of the 문턱. The grip runs the region's whole
  /// side, but the last [EditorPanelTabs.stripHeight] of that side is the
  /// strip on the frame-facing edge — and the strip's LEADING tab carries
  /// its 8px lift zone in exactly that corner. Two edge gestures cannot
  /// share five pixels: the splitter hit-tests opaque and won every one of
  /// them, so the first panel of the floating region could not be lifted at
  /// all, and its zone was painted over besides (the same bite took the
  /// collapse button's trailing edge on the other side). Which 30px to
  /// leave alone needs no rule of its own — 정체성은 창틀 향한 변에 already
  /// says whose they are, and it flips with the region out of [onTop].
  Widget _bottomInsetGrip({
    required bool right,
    required double inset,
    required bool onTop,
    required double railSpan,
    required double maxInset,
  }) {
    return Positioned(
      // Region-relative: this rides INSIDE the region's own clip now, so
      // the lit edge follows the silhouette instead of standing beside it
      // as a straight bar.
      left: right ? null : 0,
      right: right ? 0 : null,
      top: onTop ? EditorPanelTabs.stripHeight : 0,
      bottom: onTop ? 0 : EditorPanelTabs.stripHeight,
      width: DockEdgeSplitter.thickness,
      child: DockEdgeSplitter(
        key: ValueKey<String>('bottom-inset-${right ? 'right' : 'left'}'),
        axis: Axis.vertical,
        tooltip: AppText.strings.panelRegionWidth,
        // Back to the DEFAULT width, not to zero: the natural size of this
        // region is now 「화면의 2/3」 rather than "the whole window".
        onDoubleTap: () {
          _bottomInsetOverride.value = null;
          _layoutPersistence.scheduleLayoutSave();
        },
        onDragStart: () => _bottomInsetDragRaw = inset,
        onDragEnd: () => _bottomInsetDragRaw = null,
        onDragDelta: (delta) {
          // Pulling the LEFT edge right and the RIGHT edge left both grow
          // the inset, which is what "symmetric" means from the hand's side.
          final before = _bottomInsetDragRaw ?? inset;
          final raw = (before + (right ? -delta : delta))
              .clamp(0.0, maxInset)
              .toDouble();
          _bottomInsetDragRaw = raw;
          _bottomInsetOverride.value = _detented(raw, railSpan);
          _layoutPersistence.scheduleLayoutSave();
          // The DETENT costs nothing — `_bottomInsetDragRaw` keeps the
          // un-snapped total (R3 #2), so the magnet can be left. The WALLS
          // at 0 and maxInset do cost, and that is what goes back to the
          // splitter, converted out of inset units into pointer ones.
          final movedInset = raw - before;
          return right ? -movedInset : movedInset;
        },
      ),
    );
  }

  /// Snaps to the rail's width when the drag lands near it, so the
  /// pass-through boundary is reachable on purpose.
  static double _detented(double inset, double railSpan) =>
      railSpan > 0 && (inset - railSpan).abs() <= _bottomInsetDetent
      ? railSpan
      : inset;

  /// OS drag-and-drop (§6-i, confirmed): wherever the drop lands, the
  /// import/placement window opens with the dropped paths — never an
  /// instant import. Folders drop too (the cut-folder parser's entrance).
  void _onOsFilesDropped(DropDoneDetails details) {
    final paths = [for (final file in details.files) file.path];
    if (paths.isEmpty) {
      return;
    }
    _openImportWindow(initialPaths: paths);
  }

  /// The one import window, from whichever entrance asked for it.
  ///
  /// [poolOnly] is the media pool's ＋: it starts on the pool because
  /// registering for later is what that panel is for, and the other
  /// destinations stay on offer because it is the same window.
  void _openImportWindow({
    List<String> initialPaths = const [],
    bool poolOnly = false,
    bool placeOnly = false,
  }) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => ImportDialog(
          session: widget.session,
          initialPaths: initialPaths,
          poolOnly: poolOnly,
          placeOnly: placeOnly,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: _onOsFilesDropped,
      // THE STAGE'S OUTER SURFACES, SAID ONCE (유저, R4 #2). Every canvas
      // panel in the app is somewhere under here — the drawing floor, the
      // timesheet, the conte, the cut envelope, the media viewer — so this
      // is the one place the room's colours have to be right.
      //
      // ★The workspace rides through as a `child:`. The listenable is the
      // session, which notifies constantly, and the only thing that must
      // rebuild on it is this one wrapper: `updateShouldNotify` keeps the
      // panels still until a colour actually moves, and the identical child
      // instance means the tree below is never rebuilt at all.
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, child) {
          final project = widget.session.repository.currentProject;
          return CanvasStageColors(
            backdropArgb: project?.backdropArgb ?? defaultProjectBackdropArgb,
            pasteboardArgb:
                project?.pasteboardArgb ?? defaultProjectPasteboardArgb,
            pasteboardMargin:
                project?.pasteboardMargin ?? defaultProjectPasteboardMargin,
            child: child!,
          );
        },
        child: _buildWorkspace(context),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return ListenableBuilder(
      // The ORIENTATION belongs here as well as inside the tab: the
      // timeline and the x-sheet do not have the same floor, so toggling
      // between them changes what the dock owes its panel. Merged at this
      // level and not deeper because the floor is read by the dock
      // splitter and the section layout, both of which are built here.
      // (Zoom stays out on purpose — that one is per-drag.)
      // The EXTENTS are deliberately absent from this merge. This builder
      // wraps the whole workspace — both rails, the full-bleed canvas, the
      // floating region — so listening to a splitter here rebuilt the canvas
      // panel once per drag frame, which is what made dragging a divider
      // feel heavy. Sizes ride `_layout.extentRevision` and are read inside
      // the two builders that actually consume them.
      listenable: Listenable.merge([_layout, _timelineOrientation]),
      builder: (context, _) {
        // A rail is THERE when any of its groups is open; which groups
        // those are is the rail's own business.
        final hasLeftDock = _openRailGroups(right: false).isNotEmpty;
        final hasRightDock = _openRailGroups(right: true).isNotEmpty;
        final hasBottomDock = _layout
            .tabsIn(EditorWorkspace.bottomGroupId)
            .isNotEmpty;
        // ★EVERY HEAVY SUBTREE IS BUILT HERE, above the extent builder, and
        // merely REFERENCED inside it. An element whose new widget is the
        // identical instance is reused without rebuilding, so a splitter
        // drag re-lays these out and never rebuilds them — the same
        // mechanism the floor's `child:` uses, applied to the two things
        // that were still paying full price per drag frame.
        final leftRailHosts = _railHosts(right: false);
        final rightRailHosts = _railHosts(right: true);
        final bottomContent = hasBottomDock
            ? _docks.buildBottomDockContent(onTop: _regionOnTop)
            : null;
        return Row(
          children: [
            // The two tool strips are the only things that take space from
            // the canvas. Everything else LIES ON IT.
            _docks.buildEdgeDock(
              EditorWorkspace.toolLeftGroupId,
              EditorPanelDockSide.left,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    // EVERY read of an extent lives below this line. It is the
                    // narrowest wrapper that still sees them all, so a splitter
                    // drag rebuilds the rails and the region — and stops there.
                    //
                    // ★THE FLOOR RIDES THROUGH AS A CHILD. Building it inside
                    // this builder is what was left of the drag lag: every
                    // frame of every splitter drag rebuilt the canvas panel,
                    // and the edge trailed the cursor by however long that
                    // took. It does not depend on any extent — the cover it
                    // needs reaches it through an InheritedWidget, which
                    // notifies without rebuilding anything between.
                    ListenableBuilder(
                      // The region's own INSET rides here too. It used to be
                      // a plain field behind setState, so pulling the
                      // floating region's side in rebuilt the entire
                      // workspace — canvas included — once per drag frame,
                      // which is why that grip stayed heavy after the
                      // splitter one was fixed.
                      listenable: Listenable.merge([
                        _layout.extentRevision,
                        _bottomInsetOverride,
                      ]),
                      child: _docks.buildCenterDock(),
                      builder: (context, floor) {
                        // The side docks keep their saved extents but may never
                        // squeeze the canvas out: scale both down proportionally
                        // when the window can't fit them.
                        const minCenterWidth = 120.0;
                        final grid = DeviceGrid.of(context);
                        // D37: the OPENING width is a fraction of this window.
                        // A dock the user has sized keeps its pixels; only a
                        // dock that has never been dragged reads this.
                        final opening = EditorWorkspace.sideDockWidthFor(
                          constraints.maxWidth,
                          grid,
                        );
                        var leftWidth = hasLeftDock
                            ? _layout.dockExtent(
                                EditorWorkspace.railWidthKey(right: false),
                                fallback: opening,
                              )
                            : 0.0;
                        var rightWidth = hasRightDock
                            ? _layout.dockExtent(
                                EditorWorkspace.railWidthKey(right: true),
                                fallback: opening,
                              )
                            : 0.0;
                        // The gap between the strip and the panel floating
                        // beside it. It is what a rail costs the canvas
                        // beyond the panel itself; the width grips are
                        // overlays and cost nothing.
                        final gaps =
                            (hasLeftDock ? _railGroupGap : 0.0) +
                            (hasRightDock ? _railGroupGap : 0.0);
                        // D37's ceiling, applied on the way OUT as well as on
                        // the drag: a layout saved before it existed can sit
                        // above it, and the host must draw what the drag would
                        // now allow rather than what the file remembers.
                        //
                        // 🚨결정 8: ONE ceiling, computed from the window, and
                        // the SAME one for both sides. It used to take the
                        // other dock's width — so the right was clamped
                        // against an already-clamped left, and equal stored
                        // widths drew unequal.
                        final ceiling = EditorWorkspace.sideDockCeiling(
                          availableWidth: constraints.maxWidth,
                          gaps: gaps,
                          minCentreWidth: minCenterWidth,
                        );
                        leftWidth = math.min(leftWidth, ceiling);
                        rightWidth = math.min(rightWidth, ceiling);
                        // ⛔The proportional squeeze that stood here is GONE.
                        // It scaled BOTH sides by one factor whenever the pair
                        // overflowed, which is the other half of 「한쪽을
                        // 바꾸면 반대쪽도 바뀐다」 and the half that only
                        // showed on a small window. With a ceiling of at most
                        // half the room, two rails cannot overflow, so there
                        // is nothing left to share out.
                        // ⛔Snapped AFTER the squeeze, not before: the scale
                        // above is a fraction and would push an on-grid width
                        // back off it.
                        leftWidth = grid.position(leftWidth);
                        rightWidth = grid.position(rightWidth);
                        final bottomHeight = hasBottomDock
                            ? _docks.bottomDockHeight(constraints.maxHeight)
                            : 0.0;
                        // Symmetric, and clamped against the WINDOW: the region
                        // may narrow until it is a panel rather than a bar, and
                        // no further.
                        final bottomInset =
                            _bottomInsetFor(constraints.maxWidth)
                                .clamp(
                                  0.0,
                                  math.max(
                                    0.0,
                                    (constraints.maxWidth -
                                            _minBottomRegionWidth) /
                                        2,
                                  ),
                                )
                                .toDouble();
                        // 🚨★★★ONE VALUE PER BOUNDARY. `_detented` must aim
                        // at the same number `_railPassesBottom` compares
                        // against, or the pass-through state is not
                        // reachable at all.
                        //
                        // ⛔An earlier draft split this into raw and
                        // quantized, feeding the grips the raw span while
                        // the gate compared the quantized one — and the two
                        // rails quantize in OPPOSITE directions (the left
                        // floors, the right ceils, because the right is
                        // derived from a snapped far edge). Measured, one
                        // driven drag: 28 of 45 steps asymmetric at 1.125
                        // and at 1.35, with the rails 355 logical px apart
                        // at the detent — and the magnet pulls the user
                        // INTO that state, which is its whole job. Zero at
                        // 1.25 and 1.75, where `position` happens to be the
                        // identity for these numbers.
                        //
                        // ⛔And the reason that draft gave was FALSE. It
                        // cited this file's own "the detent ate the drag"
                        // defect, but R3 #2 already made that unreachable:
                        // the accumulator is `_bottomInsetDragRaw` and the
                        // reported travel is `raw - before`, neither of
                        // which can see this span. Measured travel ratio
                        // 1.000000 on both grips at every ratio, with the
                        // magnet releasing exactly on schedule. ⇒ Snapping
                        // the span costs no travel; splitting it broke a
                        // gate.
                        final leftRailSpanRaw = hasLeftDock
                            ? leftWidth + _railGroupGap
                            : 0.0;
                        final rightRailSpanRaw = hasRightDock
                            ? rightWidth + _railGroupGap
                            : 0.0;
                        final leftRailSpan = grid.position(leftRailSpanRaw);
                        // ⚠️The RIGHT span is a distance from the FAR edge,
                        // so snapping it as if it were measured from the
                        // origin puts the content's right boundary between
                        // two pixels. Snap the boundary itself — one run
                        // across the axis — and derive the span from it.
                        // `constraints.maxWidth × ratio` is integral by
                        // construction (the window's physical size is), so
                        // an integer minus an integer stays one.
                        final rightRailSpan = hasRightDock
                            ? constraints.maxWidth -
                                  grid.position(
                                    constraints.maxWidth - rightRailSpanRaw,
                                  )
                            : 0.0;
                        // Which edge the region is on. Everything below reads
                        // this and nothing anywhere else has to.
                        final onTop = _regionOnTop;
                        final regionSpan = hasBottomDock
                            ? bottomHeight + DockEdgeSplitter.thickness
                            : 0.0;
                        // What the panels hide from the artwork. The floor reads
                        // this and nothing else has to know it exists.
                        final floorCover = EdgeInsets.only(
                          left: leftRailSpan,
                          right: rightRailSpan,
                          top: onTop ? regionSpan : 0,
                          bottom: onTop ? 0 : regionSpan,
                        );
                        // ★What the region occupies against OTHER PANELS,
                        // which is a different question from what it hides
                        // from the artwork (⑫).
                        //
                        // The folded row lies ON the drawing on purpose — no
                        // ground, no fill — so it is deliberately absent from
                        // `floorCover`. That reading leaked into the rails,
                        // and a rail grown while the panel was folded stopped
                        // 23px INSIDE the row: it was standing in another
                        // panel's space because nobody had said the space was
                        // a panel's (유저 ⑫, 「옆에 패널들은 간편오버레이를
                        // 침범해서 자리차지함」).
                        //
                        // A `max` rather than a sum: the splitter's thickness
                        // is the room the region already claims above itself,
                        // and the folded row occupies that same band and then
                        // some. Reading BOTH from one number is what makes a
                        // taller fold later need no second edit (유저: 「그래야
                        // 수정했을때 아무것도 안고치고 반영되니까」).
                        final regionPanelSpan = hasBottomDock
                            ? bottomHeight +
                                  math.max(
                                    DockEdgeSplitter.thickness,
                                    _bottomDockCollapsed
                                        ? _collapsedRows.collapsedRowHeight()
                                        : 0.0,
                                  )
                            : 0.0;
                        // ★ Whether each column runs past the floating region or
                        // stops on its edge — one comparison per side, because the
                        // two rails can be different widths and the answer is
                        // about whether THIS one has room.
                        double columnStop(double railSpan) =>
                            hasBottomDock &&
                                !_railPassesBottom(
                                  bottomInset: bottomInset,
                                  railWidth: railSpan,
                                )
                            ? regionPanelSpan
                            : 0.0;
                        // 🚨★★★RAW on BOTH sides. This gate is a semantic
                        // question — "is the region wide enough to reach
                        // past the rail" — and the answer must not depend
                        // on which way each side happens to snap.
                        //
                        // ⛔The two spans quantize in OPPOSITE directions:
                        // the left FLOORS (it is a distance from the
                        // origin) and the right CEILS (it is derived from
                        // a snapped far edge). Comparing one raw inset
                        // against those gives different answers for the
                        // two rails at the same inset — measured, 28 of 45
                        // drag steps behaved differently at 1.125 and 1.35
                        // while 1.25 and 1.75 were untouched, because
                        // `position` is the identity for those numbers.
                        // The detent magnet then pulls the user into that
                        // window, which is its whole job.
                        final leftStop = columnStop(leftRailSpanRaw);
                        final rightStop = columnStop(rightRailSpanRaw);

                        return Stack(
                          children: [
                            // ★ THE FLOOR. Everything below this line is drawn on
                            // top of the drawing.
                            Positioned.fill(
                              child: CanvasFloorInsets(
                                insets: floorCover,
                                // ⑩: the collapsed row lies ON the artwork
                                // just past the region's edge. It frames
                                // nothing, so it is not in `insets` — but a
                                // bar on the bottom edge would be under it.
                                bottomOverlaySpan:
                                    hasBottomDock &&
                                        _bottomDockCollapsed &&
                                        !onTop
                                    ? _collapsedRows.collapsedRowHeight()
                                    : 0,
                                // WHERE each column actually is, not just how
                                // wide it is. A rail panel is as tall as it was
                                // left at, so a short one covers a band and not
                                // an edge — and the scrollbar that stepped
                                // aside for the whole edge read as floating for
                                // no reason (유저, R3 #5).
                                leftRailBand: _railBand(
                                  right: false,
                                  stop: leftStop,
                                  onTop: onTop,
                                  height: constraints.maxHeight,
                                  grid: grid,
                                ),
                                rightRailBand: _railBand(
                                  right: true,
                                  stop: rightStop,
                                  onTop: onTop,
                                  height: constraints.maxHeight,
                                  grid: grid,
                                ),
                                child: floor!,
                              ),
                            ),
                            // ★ The rails FLOAT. A gap of pasteboard between
                            // the strip and the panel, another above the
                            // first panel, and each panel its own rounded
                            // object — the same kind of thing the timeline
                            // is, rather than a slab bolted to the strip.
                            // Their width grips ride their own inner edges
                            // inside the column.
                            Positioned(
                              left: 0,
                              // ★These two widgets are what actually CARRY a
                              // rail-docked canvas, so this is where the
                              // chain lands on the grid or does not. The
                              // right span especially: it is subtracted
                              // from an on-grid right edge, so a raw width
                              // here puts the column's LEFT edge — and
                              // everything docked in it — between two
                              // device pixels.
                              top: grid.position(
                                (onTop ? leftStop : 0) + _railGroupGap,
                              ),
                              bottom: onTop ? 0 : leftStop,
                              // The gap is INSIDE the column's box now: the
                              // rail's own scrollbar rides it. ⛔Take the
                              // quantized span rather than re-adding the
                              // gap: `floorCover`, `columnStop` and this
                              // widget have to be one spelling of one
                              // boundary, or the canvas is framed against
                              // an edge the rail is not drawn at.
                              width: hasLeftDock ? leftRailSpan : null,
                              child: _buildRailColumn(
                                EditorPanelDockSide.left,
                                width: leftWidth,
                                hosts: leftRailHosts,
                                // 결정 8: the same ceiling both sides read.
                                dragCeiling: ceiling,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: grid.position(
                                (onTop ? rightStop : 0) + _railGroupGap,
                              ),
                              bottom: onTop ? 0 : rightStop,
                              width: hasRightDock ? rightRailSpan : null,
                              child: _buildRailColumn(
                                EditorPanelDockSide.right,
                                width: rightWidth,
                                hosts: rightRailHosts,
                                // 결정 8: the same ceiling both sides read.
                                dragCeiling: ceiling,
                              ),
                            ),
                            // ★The collapsed row, over the artwork and OUTSIDE
                            // the region's clip. It has to be a sibling: the
                            // region is inside a `SuperellipseClip`, so an
                            // overlay mounted in there could never reach up
                            // onto the canvas. It also has to come BEFORE the
                            // region in this stack — the region paints over
                            // it, which is what keeps the row from spilling
                            // onto the sill when the two meet.
                            if (hasBottomDock && _bottomDockCollapsed)
                              Positioned(
                                left: bottomInset,
                                right: bottomInset,
                                top: onTop ? bottomHeight : null,
                                bottom: onTop ? null : bottomHeight,
                                height: _collapsedRows.collapsedRowHeight(),
                                child: _collapsedRows.collapsedRowOverlay(),
                              ),
                            Positioned(
                              left: bottomInset,
                              right: bottomInset,
                              top: onTop ? 0 : null,
                              bottom: onTop ? null : 0,
                              height: hasBottomDock ? bottomHeight : null,
                              child: _docks.buildBottomDock(
                                availableExtent: constraints.maxHeight,
                                content: bottomContent,
                                inset: bottomInset > 0,
                                onTop: onTop,
                                // Every grip the region has, laid on its own
                                // edges inside its own clip.
                                grips: !hasBottomDock
                                    ? const []
                                    : [
                                        // ★NO HEIGHT GRIP WHILE COLLAPSED
                                        // (유저 확정, 2026-08-10): folding is a
                                        // state change, not a small size, so
                                        // the handle that changes size does not
                                        // appear and does not answer.
                                        //
                                        // ⛔It used to do the opposite —
                                        // dragging it meant "give me it back"
                                        // and unfolded the region. That was the
                                        // right call while the fold had no
                                        // representation of its own (a live
                                        // grip that moved nothing would have
                                        // been worse), and it is the wrong one
                                        // now: the collapsed panel is a working
                                        // surface, and a grip on its edge
                                        // invites a resize it cannot do.
                                        // ⇒ The sill's ⌃ is the only way in and
                                        // the only way out. The SIDE grips stay
                                        // live either way — width is not the
                                        // axis the fold is about.
                                        if (!_bottomDockCollapsed)
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            // 기하는 캔버스 향한 변에: the resize
                                            // handle rides whichever edge faces
                                            // the artwork, which flips with the
                                            // region and needs no rule of its
                                            // own.
                                            top: onTop ? null : 0,
                                            bottom: onTop ? 0 : null,
                                            height: DockEdgeSplitter.thickness,
                                            child: DockEdgeSplitter(
                                              key: const ValueKey<String>(
                                                'dock-resize-bottom',
                                              ),
                                              axis: Axis.horizontal,
                                              onDragDelta: (delta) {
                                                // What the edge used, back in
                                                // POINTER units — the sign flip
                                                // below has to be undone or the
                                                // splitter would bank the debt
                                                // the wrong way round.
                                                final used = _layout.resizeDock(
                                                  EditorWorkspace.bottomGroupId,
                                                  // Toward the artwork GROWS the
                                                  // region, on either edge: down
                                                  // when it is on top, up when it
                                                  // is on the bottom.
                                                  onTop ? delta : -delta,
                                                  fallback: EditorWorkspace
                                                      .bottomPanelHeight,
                                                  // The splitter stops where the
                                                  // panels stop shrinking, and
                                                  // never banks height past what
                                                  // the window can show — a
                                                  // surplus behind the ceiling is
                                                  // spent before the edge moves
                                                  // again, which reads as a
                                                  // splitter that lags the cursor.
                                                  minExtent: math.min(
                                                    _verticalDockMinimumExtent(
                                                      EditorWorkspace
                                                          .bottomGroupId,
                                                    ),
                                                    _docks.bottomDockCeiling(
                                                      constraints.maxHeight,
                                                    ),
                                                  ),
                                                  // The model's own 640 still
                                                  // applies here — the region
                                                  // has always had it, and
                                                  // lifting it is a separate
                                                  // decision from fixing the
                                                  // banking.
                                                  // 결정 8: the HAND stops at
                                                  // half the window.
                                                  maxExtent: math.min(
                                                    EditorPanelLayoutModel
                                                        .maxDockExtent,
                                                    _docks.bottomDockDragCeiling(
                                                      constraints.maxHeight,
                                                    ),
                                                  ),
                                                );
                                                return onTop ? used : -used;
                                              },
                                            ),
                                          ),
                                        // The region's side grips. TWO of
                                        // them and ONE number — pulling
                                        // either edge in pulls the other in
                                        // by the same amount, because the
                                        // region stays centred on the window.
                                        _bottomInsetGrip(
                                          right: false,
                                          inset: bottomInset,
                                          onTop: onTop,
                                          // RAW, to match the gate above.
                                          railSpan: leftRailSpanRaw,
                                          maxInset: math.max(
                                            0.0,
                                            (constraints.maxWidth -
                                                    _minBottomRegionWidth) /
                                                2,
                                          ),
                                        ),
                                        _bottomInsetGrip(
                                          right: true,
                                          inset: bottomInset,
                                          onTop: onTop,
                                          // RAW, to match the gate above.
                                          railSpan: rightRailSpanRaw,
                                          maxInset: math.max(
                                            0.0,
                                            (constraints.maxWidth -
                                                    _minBottomRegionWidth) /
                                                2,
                                          ),
                                        ),
                                      ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
              ),
            ),
            _docks.buildEdgeDock(
              EditorWorkspace.toolRightGroupId,
              EditorPanelDockSide.right,
            ),
          ],
        );
      },
    );
  }
}

/// One rail button: a GROUP of panels, opened and closed as a unit.
///
/// It says what it holds with the glyph of its first panel and a tooltip
/// naming them all — 패널 이름 글자는 어디에도 안 띄운다 (유저 확정), and
/// [EditorPanelTab.label] is still every panel's only accessibility name, so
/// the names move into the tooltip rather than out of existence.
///
/// It is also a DROP target: dragging a panel onto it puts that panel in this
/// group. That is the only way to build a group, which is why the strip must
/// not scroll — a scrolling strip would take the drag first.
class _RailGroupButton extends StatelessWidget {
  const _RailGroupButton({
    required this.railId,
    required this.open,
    required this.tabs,
    required this.dragging,
    required this.onPressed,
    required this.onTabDropped,
    this.face,
  });

  final String railId;
  final bool open;
  final List<EditorPanelTab> tabs;
  final EditorPanelTabDragData? dragging;

  /// Drawn INSTEAD of the glyph, for a group whose state is what the button
  /// should be saying — the colour pair.
  final Widget? face;

  /// Null for the empty slot, which is a target and not a switch.
  final VoidCallback? onPressed;
  final ValueChanged<EditorPanelTabDragData> onTabDropped;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tooltip = tabs.isEmpty
        ? AppText.strings.panelNewGroup
        : [for (final tab in tabs) tab.label].join(' · ');
    final Widget button = face == null
        ? RailButton(
            keyValue: 'rail-group-$railId',
            tooltip: tooltip,
            icon: tabs.isEmpty ? Icons.add : tabs.first.icon,
            selected: open,
            onPressed: onPressed,
          )
        : Tooltip(
            message: tooltip,
            child: Material(
              key: ValueKey<String>('rail-group-$railId'),
              color: open
                  ? colorScheme.surfaceContainerHigh
                  : Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: AppShapes.control(ToolsPanel.buttonExtent),
              child: ControlPressClaim(
                onPressed: onPressed,
                child: InkWell(
                  onTap: silentPress(onPressed),
                  // The pair sizes itself to one button cell, so a group that
                  // wears a face is the same square as every other.
                  child: SizedBox.square(
                    dimension: ToolsPanel.buttonExtent,
                    child: face,
                  ),
                ),
              ),
            ),
          );
    if (dragging == null) {
      return button;
    }
    return DragTarget<EditorPanelTabDragData>(
      onAcceptWithDetails: (details) => onTabDropped(details.data),
      builder: (context, candidate, rejected) {
        final hovered = candidate.isNotEmpty;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: ShapeDecoration(
            shape: AppShapes.control(
              ToolsPanel.buttonExtent,
              side: BorderSide(
                color: hovered
                    ? colorScheme.primary
                    : colorScheme.primary.withValues(alpha: 0.45),
                width: hovered ? 1.5 : 1,
              ),
            ),
          ),
          child: button,
        );
      },
    );
  }
}
