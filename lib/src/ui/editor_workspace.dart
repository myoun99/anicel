import 'widgets/app_tooltip.dart';
import 'widgets/app_icon_button.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart' show ValueListenable, listEquals;
import 'package:flutter/material.dart';

import '../services/flutter_test_run.dart';
import '../models/brush_group.dart';
import '../models/brush_group_id.dart';
import '../models/brush_preset.dart';
import '../models/brush_preset_id.dart';
import '../models/canvas_shape_kind.dart';
import '../models/cut_id.dart';
import '../models/media_viewer_bookmark.dart' show MediaViewerBookmark;
import '../models/project.dart'
    show Project, defaultProjectBackdropArgb, defaultProjectPasteboardArgb;
import '../models/project_font_file.dart';
import '../services/command.dart' show Command;
import '../models/project_id.dart' show ProjectId;
import '../models/layer_id.dart';
import '../models/media_asset.dart' show MediaAsset;
import '../models/reference_swap.dart';
import '../models/brush_hand_settings.dart' show brushHandSettingsRecalled;
import '../services/brush_hand_overlay.dart';
import '../services/brush_preset_file_service.dart';
import '../services/brush_tip_library_service.dart';
import '../services/font_library_service.dart';
import '../services/canvas_read_source.dart';
import '../services/canvas_flood_fill.dart' show FloodFillOptions;
import '../services/canvas_selection.dart' show SelectionMaskOptions;
import '../models/app_language.dart' show AppLanguage;
import '../models/brush_tip_entry.dart';
import '../models/canvas_size.dart';
import '../models/pasteboard_bounds.dart';
import '../models/drawing_guide.dart' show CutGuides, DrawingGuide, GuideId;
import '../services/cut_piece_slot.dart';
import '../services/last_stroke_slot.dart';
import '../services/cut_piece_tip.dart';
import '../services/color_palette_file_service.dart'
    show ColorPaletteFileService, ColorPaletteState;
import 'brush/arrange_brush_library_command.dart';
import 'brush/brush_library_keys.dart';
import 'brush/brush_library_look.dart';
import 'brush/brush_preset_library.dart';
import 'brush/temporary_tool.dart' show ToolHoldMemory;
import 'brush/canvas_floor_insets.dart';
import 'brush/brush_canvas_panel.dart' show CanvasEdgePill;
import 'brush/brush_value_group.dart' show BrushValuesPill;
import 'color/color_panels.dart' show ColorPickerKind, ColorPickerPanel;
import 'color/color_slot_pair.dart';
import 'color/palette_file_import.dart';
import 'theme/app_theme.dart';
import 'brush/brush_hand_settings_store.dart';
import 'brush/brush_preset_panel.dart';
import 'brush/brush_preset_view_options.dart';
import 'brush/brush_tip_library.dart';
import 'brush/brush_tool_state.dart';
import 'brush/canvas_selection_commands.dart';
import 'brush/canvas_traces.dart';
import 'brush/cel_text_commands.dart';
import 'brush/text_tool_options.dart';
import 'brush/confirm_verb.dart';
import 'brush/history_verbs.dart';
import 'brush/transform_tool_options.dart';
import 'brush/canvas_view_commands.dart';
import 'brush/paint_tool_state_notifier.dart';
import 'brush/tool_choice.dart';
import 'brush/brush_canvas_defaults.dart';
import 'brush/guide_panels.dart';
import 'brush/tool_library_panel.dart';
import 'brush/tool_press.dart';
import 'brush/tool_settings_panel.dart';
import 'brush/tools_panel.dart';
import 'editor_canvas_area.dart';
import 'editor_session_manager.dart';
import 'session/tab_rail_wiring.dart';
import 'session/text_clipboard.dart' show CanvasTextHand, TextCopy;
import 'shortcuts/editor_action_registry.dart';
import 'shortcuts/editor_shortcut_scope.dart';
import 'shortcuts/shortcut_file_import.dart';
import 'export/export_frame_renderer.dart';
import 'import/import_dialog.dart';
import 'import/settings_rows.dart';
import 'menu/opened_files_door.dart';
import 'menu/project_open_door.dart' show ProjectPick;
import '../services/import/import_layer_spot.dart';
import 'media/media_asset_drag_data.dart';
import 'media/media_asset_drop_target.dart';
import 'media/media_drop_verdict.dart';
import 'media/media_pool_panel.dart';
import 'media/media_relink_flow.dart';
import 'media/media_viewer_tab_host.dart';
import 'media/viewer_ink.dart';
import 'layout/device_grid.dart';
import 'layout/device_grid_scroll_controller.dart';
import '../services/audio/conform_wav_export.dart';
import '../services/persistence/file_type_groups.dart';
import 'dialogs/app_prompt_dialog.dart';
import 'dialogs/folder_pick_flow.dart';
import 'dialogs/fx_plugin_install_flow.dart';
import 'dialogs/app_confirm_dialog.dart'
    show
        ConfirmChoice,
        ConfirmQuestion,
        NoticeDetails,
        askConfirm,
        confirmDialogKeys,
        showAppNotice;
import 'panels/editor_dock_host.dart';
import 'panels/editor_panel_dock.dart';
import 'panels/editor_panel_layout.dart';
import 'panels/open_tab_content.dart';
import 'panels/panel_flash.dart';
import 'panels/editor_panel_tabs.dart';
import 'panels/workspace_layout_store.dart';
import 'panels/workspace_panels_menu.dart';
import 'widgets/app_scrollbar.dart';
import 'widgets/static_raster.dart';
import 'widgets/superellipse_clip.dart';
import 'widgets/tick_layer.dart';
import 'widgets/grip_band.dart' show LiftingGripBand;
import 'widgets/strip_group_rule.dart' show StripGroupRule;
import 'keyed_keep_alive_stack.dart';
import 'sliced_value_listenable_builder.dart';
import 'timeline/axis_turn.dart' show alongBox;
import 'timeline/memo_token.dart' show ByList;
import 'conte/conte_ink.dart';
import 'conte/conte_picture_ink.dart';
import 'conte/conte_tab_host.dart';
import 'envelope/cut_envelope_ink.dart';
import 'envelope/cut_envelope_tab_host.dart';
import 'sheet/paper_editing.dart';
import 'sheet/sheet_image_cache.dart';
import 'storyboard_cut_thumbnail_store.dart';
import 'storyboard_cut_blocks_painter.dart'
    show StandingCut, storyboardCutBlocksPainterFor;
import 'storyboard_panel.dart'
    show
        StoryboardPanel,
        StoryboardPlayheadTint,
        StoryboardTrackLabelRow,
        storyboardVideoRowName;
import 'storyboard_playhead_mapping.dart';
import '../models/storyboard_timeline_layout.dart' show movieEndFrames;
import '../models/timeline_row_address.dart';
import '../models/working_panel.dart';
import 'timeline/collapsed_row_overlay.dart';
import 'timeline/frame_ruler_view.dart';
import 'timeline/layer_label_controls.dart'
    show layerRailColumnWidthsIn;
import 'timeline/rail_eyes.dart' show RailEyes;
import 'timeline/timeline_grid_metrics.dart'
    show
        TimelineGridMetrics,
        timelineLayerControlsWidthFor,
        timelineLayerRowHeightIn;
import 'timeline/timeline_cel_content_source.dart'
    show TimelineCelContentSource;
import 'timeline/timeline_frame_cells_row.dart' show TimelineFrameCellsRow;
import 'timeline/timeline_tile_raster_source.dart'
    show timelineSubstrateGeneration;
import 'timeline/timeline_frame_cursor_layer.dart' show TimelineCursorLayer;
import 'timeline/timeline_row_edges.dart' show TimelineRowEdges;
import 'timeline/timeline_frame_geometry.dart' show TimelineFrameGeometryHandle;
import 'timeline/timeline_lane_rows.dart' show TimelineLaneFrameRow;
import 'timeline/timeline_layer_controls_row.dart'
    show TimelineLayerControlsRow;
import 'timeline/timeline_command_bar.dart' show TimelineCommandBar;
import 'timeline/layer_rail_window.dart';
import 'canvas/flip_hud_controller.dart';
import 'canvas/flip_hud_model.dart';
import 'canvas/flip_hud_rows.dart';
import 'canvas/guide_overlay.dart' show guideColorOf, guideLinesOnPaper;
import 'timeline/layer_timeline_display_adapter.dart'
    show horizontalLayerDisplayOrder;
import 'timeline/property_lane_model.dart'
    show
        TimelineDisplayRow,
        buildTimelineDisplayRows,
        indexOfDisplayRow;
import 'timeline/timeline_lane_provider.dart';
import 'timeline/timeline_layer_nav.dart';
import '../models/onion_skin_settings.dart';
import 'panels/onion_skin_panel.dart';
import 'panels/tool_size_preset_panel.dart';
import 'storyboard_tab_host.dart';
import 'storyboard/storyboard_rows_channel.dart';
import '../models/canvas_viewport.dart';
import 'timeline/timeline_edge_auto_pan.dart'
    show keptAxisWindows, revealKeptAxis;
import 'timeline/timeline_orientation.dart';
import 'timeline/timeline_zoom_limits.dart' show TimelineZoomLimits;
import 'workspace/workspace_bar_commands.dart';
import 'workspace/workspace_door_commands.dart';
import '../services/persistence/folder_grant.dart' show FolderGrant, handedPath;
import '../services/persistence/settings_file.dart' show SettingsFile;
import '../services/persistence/app_export_settings.dart'
    show AppExport, AppExportSettings;
import '../services/persistence/app_export_settings_store.dart';
import '../services/persistence/settings_room_file.dart'
    show putSettingsIntoTheRoom, settingsRoomPath;
import 'timeline/timeline_panel.dart' show TimelinePanel;
import 'text/app_strings.dart';
import 'text/imported_fonts.dart';
import 'text/place_lines.dart' show mediaAssetUseLine;
import 'timeline_tab_host.dart';
import 'timesheet/timesheet_ink_controller.dart';
import 'timesheet_tab_host.dart';
import 'input/control_press_claim.dart';
import 'input/os_file_drop.dart';

part 'workspace/workspace_collapsed_rows.dart';
part 'workspace/workspace_folded_storyboard.dart';
part 'workspace/workspace_docks.dart';
part 'workspace/workspace_layout_persistence.dart';
part 'workspace/workspace_tabs.dart';
part 'workspace/workspace_rail.dart';
part 'workspace/workspace_strip_buttons.dart';
part 'workspace/workspace_flip_hud.dart';
part 'workspace/workspace_brush_presets.dart';
part 'workspace/workspace_brush_groups.dart';
part 'workspace/workspace_brush_keys.dart';
part 'workspace/workspace_document_views.dart';

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
    required this.onOpenProjects,
    this.presetFileService,
    this.tipLibraryService,
    this.fontLibraryService,
    this.keepFontFiles,
    this.layoutStore,
    this.panelsMenu,
    this.brushTool,
    this.transformOptions,
    this.colorBackground,
    this.colorPalette,
    this.onColorPaletteChanged,
    this.canvasViewCommands,
    this.canvasNavigationRegionKey,
    this.canvasSelectionCommands,
    this.viewerSelections,
    this.canvasTraces,
    this.canvasTextCommands,
    this.lastStroke,
    this.toolHold,
    this.confirm,
    this.history,
    this.layerNav,
    this.barCommands,
    this.doorCommands,
    this.onInvokeAction,
    this.flipHud,
    this.brushKeys,
  });

  final EditorSessionManager session;

  /// Project files the door was handed (F-247, F-282) — the menu's 「파일
  /// 열기…」, a drop on the window, the media panel's ＋ — handed on to the
  /// shell's Open door, which holds the tabs a project opens into. The
  /// workspace only tells them from the rest ([OpenedFilesDoor]).
  final Future<void> Function(List<ProjectPick> picks) onOpenProjects;

  /// The active-tool notifier, owned by the shell (HomePage) so the tool
  /// shortcuts and the workspace panels drive one state. Null keeps a
  /// workspace-local notifier (focused widget tests).
  final PaintToolStateNotifier? brushTool;

  /// The transform tool's options, owned by the shell beside [brushTool] for
  /// the same reason: a tool shortcut presses a transform MODE (유저
  /// 2026-09-13: 「일반변형에 컨트롤+t로 연결 … 자유변형을 컨트롤+y로」).
  /// Null keeps a workspace-local notifier (focused widget tests).
  final ValueNotifier<TransformToolOptions>? transformOptions;

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

  /// Each viewer's selection channel, by its tab (F-380) — shell-owned, as
  /// the canvas's is: the window's verbs ask after the trace on it.
  final Map<String, CanvasSelectionCommands>? viewerSelections;

  /// Every canvas's polygon trace — the tool settings' 닫기 closes the one
  /// the user is in the middle of, as 확정 does.
  final CanvasTraces? canvasTraces;

  /// The shell-owned text channel (R9-rest): the canvas binds the text it
  /// holds, and the tool settings show and change it.
  final CelTextCommands? canvasTextCommands;

  /// The last drawing action (shell-owned — it outlives a project),
  /// forwarded to the canvas that records and lays it down.
  final LastStrokeSlot? lastStroke;

  /// The tool a hold sprang from (shell-owned — the tool is the app's),
  /// forwarded to the canvas, which is rebuilt per project mid-hold.
  final ToolHoldMemory? toolHold;

  /// 확정 (shell-owned, Enter's verb): the rail's ↵ and the move tool's 적용
  /// are its other doors. Null keeps both on their old verbs' absence
  /// (focused widget tests).
  final ConfirmVerb? confirm;

  /// Undo and redo (shell-owned, the keys' verbs): the rail's ↶ ↷ are their
  /// other doors. Null leaves the two buttons shut (focused widget tests).
  final HistoryVerbs? history;

  /// The shell-owned ↑/↓ layer-nav channel (UI-R20 #14): this state binds
  /// the handler because it owns the timeline view state (row filter,
  /// hidden sections) the displayed-row walk must respect.
  final TimelineLayerNavCommands? layerNav;

  /// The shell-owned channel to the bar buttons whose state this holds —
  /// the zooms, the ⇄ and the camera view (I-40).
  final WorkspaceBarCommands? barCommands;

  /// The shell-owned channel the top strip's 「파일 열기」 and 「폴더
  /// 열기…」 knock on: this state holds what the door hands files to.
  final WorkspaceDoorCommands? doorCommands;

  /// PEN-7b: the shell's action funnel for the canvas flip touch slot.
  final void Function(String actionId)? onInvokeAction;

  /// The flip HUD's state (shell-owned). This state BINDS the snapshot
  /// supplier — the displayed rows are its view state, exactly as the
  /// ↑/↓ walk's are.
  final FlipHudController? flipHud;

  /// The brush library as the shell's keys reach it (I-56): this state says
  /// what the library holds and lends its two presses.
  final BrushLibraryKeys? brushKeys;

  /// Injectable preset persistence; defaults to the app-data preset file.
  final BrushPresetFileService? presetFileService;

  /// Injectable tip-library storage; defaults to the app-data tip folder.
  final BrushTipLibraryService? tipLibraryService;

  /// Injectable storage of the fonts this device was brought; defaults to
  /// the app-data font folder (its own sandbox under a test).
  final FontLibraryService? fontLibraryService;

  /// Waited for before this device's font library lets go of files (named
  /// by the names they are kept under): the shell has every open project
  /// that carries one take its bytes first (`ProjectFonts.holdBytesOf`).
  /// Null where no project is open beside this window's.
  final Future<void> Function(Set<String> files)? keepFontFiles;

  /// Injectable workspace-layout persistence; defaults to the app-data
  /// layout file outside tests (`FLUTTER_TEST` disables it so widget tests
  /// never read a developer's saved arrangement).
  final WorkspaceLayoutStore? layoutStore;

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

  /// The dock holding one of the TOP STRIP's groups — the buttons after
  /// its second rule, whose panels lie on the floor rather than beside it.
  /// [slot] is 1-based, from the same pool size as a rail's
  /// ([railSlots]): the strip is the rail turned sideways.
  ///
  /// 🗣️I-147 (유저 2026-10-30): 「캔버스베이스 패널들 … 상단띠 통해 배경에
  /// 깔수있게 … 깔 때는 하나씩만 여는거니까」 — the floor shows one of
  /// them at a time, so a group here is never OPEN beside the drawing; it
  /// is LAID ([_EditorWorkspaceState._laidFloorTab]).
  static String topGroupId({required int slot}) => 'top-$slot';

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

  /// The width the floating region's DEFAULT never squeezes below
  /// ([_bottomInsetFor]).
  ///
  /// ↩️It was also the width the frame-axis panels INSISTED on: docked
  /// narrower, a panel laid out 640 wide inside the tab shell's sideways
  /// scroller. 🐛유저 R3 #11 took it off the conte and the envelope — a page
  /// that scales has no column to protect, and everything pinned to its
  /// right edge went off the end. 🗣️scrollbar-unify-Q1 (유저 2026-09-30:
  /// 「640 을 걷는다 — 콘티·컷봉투와 같은 법」) took it off the timeline and
  /// the storyboard too: in a narrow slot the shell's sideways bar and the
  /// panel's own frame rail sat on one line at the bottom edge (seen on the
  /// device 08-08). Every panel draws at its slot's width now, and what a
  /// narrow timeline loses its own rails take up.
  static const double _defaultRegionMinWidth = 640;

  @override
  State<EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends State<EditorWorkspace> {
  /// What the place entrance under a dragged pool file says of it — the
  /// chip's ban (「불가능 = 칩의 금지 표시」). One per workspace, because one
  /// drag is in flight at a time.
  final ValueNotifier<bool?> _mediaDropVerdict = ValueNotifier<bool?>(null);

  // 🪦The memory warning and the resume used to be heard HERE — 「the
  // workspace hosts the observer because its lifetime IS the session being
  // on screen」. With a project per tab (I-7) it is not: this State is the
  // window's and outlives every project, and a warning is for every open
  // project, not the one in front. The shell hears both now; what this
  // State holds for a project (the storyboard's thumbnails) hears the
  // warning through that project's `memoryPressureTicks`, the door the
  // media viewers already use.

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
    // The top strip's floor groups (I-147), the same pool — every one EMPTY:
    // 🗣️I-147-Q3 c (유저 2026-10-30): 「지금 자리 그대로 — 상단 띠의 그 자리는
    // 처음엔 비어 있다」. A button stands there once its band carries it
    // there; until then the sheets and the sub viewer open beside the
    // drawing from the right strip, as they did.
    for (var slot = 1; slot <= EditorWorkspace.railSlots; slot += 1)
      EditorWorkspace.topGroupId(slot: slot): null,
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

  // ── the rail: its own object, in its own file ───────────────────────
  //
  // A collaborator (workspace/workspace_rail.dart, a part of this library). The
  // State keeps the entry points its build tree calls as forwarders.
  late final _WorkspaceRail _rail = _WorkspaceRail(this);

  // ── the workspace docks: their own object, in their own file ────────
  //
  // A collaborator (workspace/workspace_docks.dart, a part of this library). The
  // State keeps the entry points its build tree calls as forwarders.
  late final _WorkspaceDocks _docks = _WorkspaceDocks(this);

  /// The strips' group buttons — the rails' and the top strip's (I-147):
  /// their own object, in workspace/workspace_strip_buttons.dart.
  late final _WorkspaceStripButtons _strips = _WorkspaceStripButtons(this);

  /// The door a collaborator rebuilds through - setState is protected,
  /// and a collaborator is not a subclass.
  void _rebuild(VoidCallback fn) => setState(fn);

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

  /// The strip BUTTON in flight, carried by its band (null = none) — the
  /// strips raise their empty slot for it only while this is set.
  final ValueNotifier<_StripGroupDragData?> _draggingGroup = ValueNotifier(
    null,
  );

  /// Whether the pointer is on each strip — the first rung its buttons'
  /// bands climb, as a tab's climbs when its panel is under the pointer.
  final ({
    ValueNotifier<bool> left,
    ValueNotifier<bool> right,
    ValueNotifier<bool> top,
  })
  _stripNearby = (
    left: ValueNotifier(false),
    right: ValueNotifier(false),
    top: ValueNotifier(false),
  );

  /// The panel laid on the floor out of a top strip group — null while the
  /// floor holds its own two, the canvas and the main viewer, whichever is
  /// in front of [EditorWorkspace.centerGroupId].
  ///
  /// A TAB, not a slot: a group moved to another slot keeps lying there,
  /// and one moved off the top strip, or emptied, stops ([_laidFloorDockId]
  /// asks where the tab is now, and [_mutatingLayout] lets go of it).
  final ValueNotifier<String?> _laidFloorTab = ValueNotifier(null);

  /// Drag-locked tabs (the canvas by default: a stray drag must not undock
  /// the drawing surface — unlock via the lock glyph on its tab).
  Set<String> _lockedTabIds = {EditorWorkspace.canvasTabId};

  /// Keeps the canvas element (and its viewport state) alive when the
  /// canvas tab re-docks — ONE PER PROJECT (I-7): a key shared by every
  /// project would carry the canvas State the tab switch is meant to
  /// replace into the next project, through the keyed rebuild
  /// ([_WorkspaceTabs.tabFor]), because a global key moves its element.
  GlobalKey get _canvasAreaKey => _CanvasAreaKey(widget.session);

  /// The active-tool notifier. Typed as the SUBCLASS because the rail asks
  /// it which tile to re-enter a tool group on (`railEntry`), and that
  /// memory has to be the same one the shell's tool shortcuts read.
  late final PaintToolStateNotifier _brushTool =
      widget.brushTool ?? PaintToolStateNotifier(BrushToolState.defaults);

  /// See [EditorWorkspace.transformOptions].
  late final ValueNotifier<TransformToolOptions> _transformOptions =
      widget.transformOptions ?? ValueNotifier(TransformToolOptions.defaults);

  /// What a rail button or a tile presses — the write a tool shortcut makes
  /// in the shell, through the same [pressTool].
  void _pressTool(ToolPress press) => pressTool(
    press,
    tool: _brushTool,
    transform: _transformOptions,
    cutWhole: widget.session.pixelVerbs.cutWhole,
  );

  /// The one piece the cut tool is holding.
  ///
  /// Owned here rather than by the session because the piece has to
  /// outlive a project change (유저: "다른 프로젝트에 붙여넣고 싶을 수 있으니")
  /// — it holds a raw pixel copy, so nothing about it belongs to the
  /// project it was taken from. Only quitting loses it.
  final CutPieceSlot _cutPieceSlot = CutPieceSlot();

  // ── the brush presets and tips: their own object ────────────────────
  //
  // A collaborator (workspace/workspace_brush_presets.dart, a part of this library). The
  // State keeps the entry points its build tree calls as forwarders.
  late final _WorkspaceBrushPresets _brushPresets = _WorkspaceBrushPresets(
    this,
  );

  // The group each paint tool opens on (F-250, workspace/workspace_brush_
  // groups.dart) — beside the presets, which take the brush up.
  late final _WorkspaceBrushGroups _brushGroups = _WorkspaceBrushGroups(this);

  // What the library lends to the shell's keys (I-56, workspace/workspace_
  // brush_keys.dart).
  late final _WorkspaceBrushKeys _brushKeys = _WorkspaceBrushKeys(this);

  // The document views' state (Round 6): what each panel shows and how.
  late final _WorkspaceDocumentViews _views = _WorkspaceDocumentViews();

  // The colour state — the background slot, the pinned palette, its file
  // service and the recent-colour recorder — is the SHELL's now, alongside
  // `_brushTool`: the colour button moved to the top strip, and the strip is
  // mounted by the shell. Nothing in the workspace reads a colour any more.

  late final BrushPresetLibrary _presetLibrary;
  late final BrushTipLibrary _tipLibrary;

  /// The fonts this device was brought — the text tool's faces beside the
  /// app's own. It stands as the run's faces from here
  /// (`CanvasLetterFaces.current`), so it is made before any canvas is.
  late final ImportedFonts _fonts;

  final ValueNotifier<TimelineOrientation> _timelineOrientation = ValueNotifier(
    TimelineOrientation.horizontal,
  );

  // One shared zoom readout drives whichever view is shown; the values are
  // kept per view so each keeps a sensible default scale.
  final ValueNotifier<double> _timelinePixelsPerFrame = ValueNotifier(
    TimelineZoomLimits.referencePixelsPerFrame,
  );

  /// The conte's zoom — the PROJECT's, held by the session and saved beside
  /// its file (`PanelViewMemory`, F-267). ↩️It was the window's, one for
  /// every tab.
  ValueNotifier<double> get _storyboardPixelsPerFrame =>
      widget.session.panelViews.storyboardPixelsPerFrame;

  /// The cut [_timelinePixelsPerFrame] was last set for (F-253) — a notify
  /// that leaves the active cut where it was leaves the zoom alone.
  CutId? _timelineZoomCut;

  /// The timeline's zoom follows the active cut: each cut shows at the zoom
  /// it was left at ([TimelineZoomMemory]), and a cut nobody zoomed at the
  /// zoom to work at (F-403; 200% on the bar since F-491) — not at the zoom
  /// the last cut was left at.
  void _followTimelineZoomToCut() {
    final session = widget.session;
    final cut = session.activeCutId;
    if (cut == _timelineZoomCut) {
      return;
    }
    _timelineZoomCut = cut;
    _timelinePixelsPerFrame.value =
        session.timelineZoom.zoomOf(cut) ??
        TimelineZoomLimits.referencePixelsPerFrame;
  }

  /// The zoom readout's one writer: the timeline shows [value], and the
  /// active cut remembers it.
  void _setTimelineZoom(double value) {
    _timelinePixelsPerFrame.value = value;
    widget.session.timelineZoom.remember(widget.session.activeCutId, value);
  }

  /// The storyboard's zoom readout's one writer — a method like the
  /// timeline's, so the callback its view cluster is kept by is the same
  /// across the workspace's rebuilds (a closure here was a new one each).
  void _setStoryboardZoom(double value) {
    _storyboardPixelsPerFrame.value = value;
  }

  /// One step of [panel]'s zoom in or out — a zoom key's, through the same
  /// writer (I-40). ↩️It was a press of the view cluster's − or +, until
  /// F-463 took the buttons off.
  void _stepZoom(WorkingPanel panel, {required bool zoomIn}) {
    final framesPerSecond =
        widget.session.projectSettings.projectFrameRate.countingBase;
    double stepped(double from) => TimelineZoomLimits.stepped(
      from,
      zoomIn: zoomIn,
      framesPerSecond: framesPerSecond,
    );
    switch (panel) {
      case WorkingPanel.timeline:
        _setTimelineZoom(stepped(_timelinePixelsPerFrame.value));
      case WorkingPanel.storyboard:
        _setStoryboardZoom(stepped(_storyboardPixelsPerFrame.value));
    }
  }

  /// One press of [panel]'s zoom fit — its button's and its key's (I-111,
  /// 유저 2026-10-19: 「타임라인/콘티패널등 줌 fit 버튼 추가. 해당 패널의
  /// 엔드라인에 맞춰서 스크롤바 fit하는것」): the closest zoom at which the
  /// end line the panel draws — the cut's on the timeline, the movie's on
  /// the conte — stands inside the window its frame axis was last shown in
  /// ([keptAxisWindows]), through the zoom's one writer; and the axis at
  /// its start.
  ///
  /// 🗣️F-472 (유저 2026-10-26): 「줌 fit 버튼의 동작이 너무 빡빡함. 엔드라인
  /// 조차 안보이니까 엔드라인뒤 1코마까지 추가로 보여주는걸로」 — so it fits
  /// one koma past the end line, on both panels. ↩️It fitted the end line
  /// alone, which then stood on the window's very edge.
  ///
  /// ⚠️The start is written a frame later: the grid re-anchors its axis on
  /// the playhead when the zoom it is built at changes
  /// ([applyZoomAnchoredScroll]), which would move it off the start again.
  void _fitZoom(WorkingPanel panel) {
    final session = widget.session;
    final (railId, frames, write) = switch (panel) {
      WorkingPanel.timeline => (
        _timelineOrientation.value == TimelineOrientation.horizontal
            ? LayerRailId.timeline
            : LayerRailId.xsheet,
        session.activeCutSpan.activeCutPlaybackFrameCount,
        _setTimelineZoom,
      ),
      WorkingPanel.storyboard => (
        LayerRailId.storyboard,
        movieEndFrames(session.repository.requireProject()),
        _setStoryboardZoom,
      ),
    };
    final kept = _frameAxisOffsets[railId];
    final window = kept == null ? null : keptAxisWindows[kept];
    if (kept == null || window == null) {
      return;
    }
    write(
      TimelineZoomLimits.fitting(
        window,
        frames: frames + 1,
        framesPerSecond: session.projectSettings.projectFrameRate.countingBase,
      ),
    );
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => kept.value = 0)
      ..scheduleFrame();
  }

  void _fitTimelineZoom() => _fitZoom(WorkingPanel.timeline);

  void _fitStoryboardZoom() => _fitZoom(WorkingPanel.storyboard);

  /// The timeline's ⇄ — its button's one writer.
  void _setTimelineOrientation(TimelineOrientation orientation) {
    _timelineOrientation.value = orientation;
    _flipHud.syncFlipAxis();
  }

  /// One press of [panel]'s ⇄ (I-40's key). Only the timeline's bar has
  /// one: the conte's answers nothing, as its missing button would.
  void _toggleOrientation(WorkingPanel panel) {
    if (panel != WorkingPanel.timeline) {
      return;
    }
    _setTimelineOrientation(_timelineOrientation.value.toggled);
  }

  /// The storyboard's V rows share ONE height (user's rule), kept here so
  /// it survives a tab switch the way the zoom does — as the splitter or a
  /// saved layout SET it. What the rows are drawn at is
  /// [_storyboardLaneHeight].
  final ValueNotifier<double> _storyboardTrackLaneHeight = ValueNotifier(
    StoryboardPanel.defaultTrackLaneHeight,
  );

  /// The V rows' ceiling on the screen [context] is on, for the film's
  /// camera ([StoryboardPanel.maxTrackLaneHeightFor]).
  double _storyboardLaneCeiling(BuildContext context) =>
      StoryboardPanel.maxTrackLaneHeightFor(
        widget.session.camera.cameraFrameSize,
        MediaQuery.devicePixelRatioOf(context),
      );

  /// The V rows' height as they are drawn — the set height, held under the
  /// ceiling: a smaller camera or a denser screen lowers the ceiling, and
  /// the height set above it comes back when the ceiling does.
  double _storyboardLaneHeight(BuildContext context) =>
      StoryboardPanel.clampTrackLaneHeight(
        _storyboardTrackLaneHeight.value,
        ceiling: _storyboardLaneCeiling(context),
      );

  /// How the frame rulers count, shared by every frame panel (frames ·
  /// conte-sheet 초+コマ · pages, I-81) — the PROJECT's, held by the session
  /// and saved beside its file (`PanelViewMemory.rulerView`, F-354).
  /// ↩️It was the window's, one for every tab.
  ValueNotifier<FrameRulerView> get _rulerView =>
      widget.session.panelViews.rulerView;

  /// Each frame panel's layer-rail WINDOW size, set by its splitter.
  ///
  /// Kept here rather than in the panels because the user asked for these
  /// to survive a restart: they ride the workspace layout file beside the
  /// dock widths, through the same debounced save.
  final Map<String, LayerRailExtent> _railExtents = {
    for (final railId in LayerRailId.values) railId: LayerRailExtent(),
  };

  /// Where each frame grid's FRAME axis is scrolled to, in pixels at that
  /// grid's own zoom — held above the grids, so it outlives a FOLD the way
  /// the zoom outlives a tab switch.
  ///
  /// 🚨F-143 (유저 2026-09-16): 「간편 오버레이가 타임라인의 스크롤을
  /// 그대로 안받음. 꽤 오른쪽으로 스크롤한채로 접으면 간편오버레이는 첫
  /// 인덱스쪽을 보여주고있어서. 뭐지?싶어서 타임라인 열면 스크롤바가
  /// 왼쪽으로 초기화되있는상태」. Each grid created its own, so folding the
  /// panel disposed it: the folded row had nothing to read and drew from
  /// frame 0, and the grid that came back started at 0. Owned here, the
  /// folded row and the grid read ONE fact — the same way the folded row
  /// already reads the rail's window「by construction rather than by
  /// agreement」.
  ///
  /// ↩️It was session-only, the window's: 「Nobody asked that of a scroll
  /// position」 — until F-267 (유저 2026-10-01): 「콘티패널,타임라인패널
  /// 스크롤상태 … 프로젝트 파일에 기록해서 다시 열면 그대로 열리도록」. So the
  /// PROJECT holds it (`PanelViewMemory`), and a save writes it beside the
  /// file; the rail windows still ride the layout file, being the device's.
  ///
  /// One per rail, like [_railExtents]: the timeline, the sheet and the
  /// storyboard each fold, and each had its own offset die with it.
  Map<String, ValueNotifier<double>> get _frameAxisOffsets =>
      widget.session.panelViews.frameAxisOffsets;

  // The hidden sections, the row filter, the folded attach groups and the
  // lane twirls are the SESSION's (`RailView`, F-169 and I-7): the standing
  // law reads them, and the layer ids they name are the project's. A tab
  // takes them, and their verbs, as `TabRailWiring` — the one wiring
  // (tests-hand-roll-the-tab-hosts-Q1 b, 2026-10-25) — whose twirl and
  // group fold are pressed through `SessionRowButtonPresses`: a press inside
  // the row selection folds every selected row (I-32).

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

  /// Which project the viewers were last filled from. A project tab coming
  /// on screen, or a file opened into the project on screen, puts another
  /// project under this widget, and the references belong to the FILM — so
  /// the panels have to follow it rather than keep showing the last one's
  /// conte. Null while nothing is seeded, or while seeding.
  ProjectId? _viewersSeededFrom;

  /// Puts each viewer back where the project left it (유저 확정 ⑤㉑) — its
  /// file at the page and the framing that file was left at (F-382).
  void _syncViewersWithProject() {
    final project = widget.session.repository.currentProject;
    if (project == null || project.id == _viewersSeededFrom) {
      return;
    }
    // Nothing is written back while the two are being filled: opening the
    // first viewer writes BOTH back, and the second still holds the last
    // project's document until it is opened too.
    _viewersSeededFrom = null;
    for (final MapEntry(key: viewer, value: slot) in _viewerSlots.entries) {
      // What a viewer keeps of the files it shows is the project's (I-7) —
      // handed as it is seeded, so the file opens at it.
      slot
        ..keepIn(widget.session.mediaFileViews, viewer: viewer)
        ..open(
          _requestForBookmark(project.mediaViewerBookmarks[viewer], project),
        );
    }
    _viewersSeededFrom = project.id;
  }

  /// A remembered reference, or null when the app can no longer reach it.
  ///
  /// 유저 확정 ⑭: BOTH kinds come back — a pooled asset by its pool key
  /// (its kind is the pool's; its name the viewer reads off the pool as it
  /// draws) and a loose file by the absolute path it was opened from. A path
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
      return MediaViewerRequest(path: asset.path, kind: asset.kind);
    }
    // Sync on purpose: this runs inside a notify, and a widget test's
    // fake-async zone never completes an awaited dart:io future.
    if (!File(bookmark.path).existsSync()) {
      return null;
    }
    return MediaViewerRequest(path: bookmark.path, kind: bookmark.kind);
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
            ),
      },
    );
  }

  /// The project on screen's storyboard pictures — made again for each
  /// project that comes on screen ([_bindSession]): its keys are cut ids,
  /// which the projects share.
  late StoryboardCutThumbnailStore _storyboardThumbnails;

  @override
  void initState() {
    super.initState();
    _tipLibrary = BrushTipLibrary(service: widget.tipLibraryService);
    // Only the index is read here — which families there are. A face is
    // read when letters are first asked for in it.
    _fonts = ImportedFonts(
      service: widget.fontLibraryService,
      beforeLettingGo: (files) async => widget.keepFontFiles?.call(files),
    );
    unawaited(_fonts.load());
    // R9-rest: a text lands WITH the faces it is set in — whoever lands
    // one asks here, where the fonts and the project on screen are both
    // in hand ([ProjectFonts.landingWith]).
    widget.canvasTextCommands?.landingWith = _landingWithItsFaces;
    // H25: what the hand last set on each brush, from the last session — and
    // H36: a painting tool taken up holding no brush opens on one.
    _brushTool.addListener(_brushPresets.followBrushTool);
    final handSettingsRecalled = _brushPresets.recallHandSettings();
    _presetLibrary = BrushPresetLibrary(
      fileService: widget.presetFileService,
      tipLibrary: _tipLibrary,
      handSettingsPort: _brushPresets._handSettingsPort,
    );
    // 🗣️I-56: the library's groups and brushes are shortcut rows, and a key
    // presses what the tab or the brush row does.
    _brushKeys.attach();
    // Tips first: presets reference them by id, so the library has to be
    // able to answer before the presets that ask are read. And the bank
    // before the opening brush is taken up, so that brush wears what the
    // hand left on it (H25-again) — read alongside the libraries, not after
    // them, so it adds no wait of its own.
    // And the saved LANGUAGE before either: the built-ins are named as they
    // are made (brush-preset-names-language-Q1), so a library made before the
    // language is back would store them in whatever the app said at launch.
    _brushPresets.libraryLanded = widget.session.appSettings.languageRestored
        .then((_) => _tipLibrary.load())
        .then((_) => _presetLibrary.load())
        .then((_) => handSettingsRecalled)
        .then((_) => _brushPresets.selectOpeningPreset());
    unawaited(_brushPresets.libraryLanded);
    _layoutPersistence._layoutStore =
        widget.layoutStore ??
        (underFlutterTest
            ? null
            : WorkspaceLayoutStore());
    unawaited(_layoutPersistence.restoreLayout());
    _cutPieceSlot.addListener(_brushPresets.armStampOnFreshCut);
    _layout.addListener(_layoutPersistence.scheduleLayoutSave);
    // Sizes no longer come through the model's own notifier, but they are
    // still persisted — the save has to hear them separately or a resized
    // dock would come back at its old width.
    _layout.extentRevision.addListener(_layoutPersistence.scheduleLayoutSave);
    for (final extent in _railExtents.values) {
      extent.addListener(_layoutPersistence.scheduleLayoutSave);
    }
    // The V rows' height is saved like the rail widths: its splitter moves
    // it, and the layout file keeps it.
    _storyboardTrackLaneHeight.addListener(
      _layoutPersistence.scheduleLayoutSave,
    );
    // So is where the brush detail window was left: its title bar moves it.
    _brushDetailAt.addListener(_layoutPersistence.scheduleLayoutSave);
    // And what lies on the floor (I-147).
    _laidFloorTab.addListener(_layoutPersistence.scheduleLayoutSave);
    widget.panelsMenu?.attach(
      entriesProvider: _panelMenuEntries,
      toggler: _togglePanelVisibility,
      // The brush's place too: the strip shows the brush's values or not
      // by it, where the region's place is read only when its row opens.
      relay: Listenable.merge([
        _layout,
        _brushValuesOnStrip,
        _railToolsOnly,
        _laidFloorTab,
      ]),
      layoutReset: _layoutPersistence.resetWorkspaceLayout,
      toolRailOnRight: () =>
          _layout.tabsIn(EditorWorkspace.toolRightGroupId).isNotEmpty,
      toolRailMover: _rail.setToolRailOnRight,
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
      floorGroups: (context) => _strips.buildFloorGroupButtons(),
      regionOnTop: () => _regionOnTop,
      regionMover: (onTop) {
        if (_regionOnTop == onTop) {
          return;
        }
        setState(() => _regionOnTop = onTop);
        _layoutPersistence.scheduleLayoutSave();
      },
      brushValuesOnStrip: () => _brushValuesOnStrip.value,
      brushValuesMover: (onStrip) {
        if (_brushValuesOnStrip.value == onStrip) {
          return;
        }
        _brushValuesOnStrip.value = onStrip;
        _layoutPersistence.scheduleLayoutSave();
      },
      railToolsOnly: () => _railToolsOnly.value,
      railToolsOnlySetter: (toolsOnly) {
        if (_railToolsOnly.value == toolsOnly) {
          return;
        }
        _railToolsOnly.value = toolsOnly;
        _layoutPersistence.scheduleLayoutSave();
      },
      regionFolder: _toggleRegionFolded,
    );
    widget.layerNav?.bind(this, _stepDisplayedLayer);
    widget.barCommands?.bind(
      this,
      zoomStep: _stepZoom,
      zoomFit: _fitZoom,
      toggleOrientation: _toggleOrientation,
    );
    widget.doorCommands?.bind(
      this,
      openFiles: () => unawaited(_pickAndOpen()),
      openFolder: () => unawaited(_pickFolderAndOpen()),
      openHanded: (handed) => unawaited(_door.open(context, handed)),
      paperEditing: () {
        final tool = widget.brushTool;
        return tool == null ? null : _views.paperEditingWith(tool);
      },
    );
    widget.flipHud?.bind(this, _flipHud.flipHudSnapshot);
    for (final slot in _viewerSlots.values) {
      slot.request.addListener(_writeViewerBookmarks);
    }
    _bindSession(widget.session);
  }

  @override
  void didUpdateWidget(covariant EditorWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _unbindSession(oldWidget.session);
      _bindSession(widget.session);
    }
  }

  /// Hangs this window's hooks on [session] — the project coming on screen.
  ///
  /// 🚨★★★ONE DOOR IN AND ONE OUT (I-7, a project per tab). This State is
  /// the WINDOW's — the dock layout, the libraries, the tool — and it
  /// outlives every project; a tab switch hands it another session. So
  /// everything it hangs on a session is hung here and taken off in
  /// [_unbindSession], and a switch is those two in a row. A hook hung
  /// anywhere else stays on the project that went behind: its drop would
  /// ask this window, its pixel verbs would read this canvas.
  ///
  /// The panels themselves are made again for each project — they are keyed
  /// by the session ([_sessionPanel]) — so nothing below them needs a door.
  void _bindSession(EditorSessionManager session) {
    // 🚨The session asks, the workspace shows. A row drop that would throw
    // fx away holds itself until this answers (see [AttachFxConfirmController]).
    session.attachFxConfirm.pending.addListener(_showAttachFxConfirm);
    // 🚨The canvas-side facts the PIXEL verbs need, published where all of
    // them are in scope. A getter, not a copy: the marquee survives tool
    // switches and the colour changes under the pointer, so a value captured
    // here would be the one that was true when the editor opened.
    //
    // 🚨★★★**THE SELECTION'S SOFTNESS IS PART OF THE SELECTION.** The verbs
    // ran on a hard mask whatever the user had set, while a Ctrl+T lift on
    // the SAME marquee honoured 확장·페더·AA — one outline, two meanings.
    // The parameter was wired all the way to `celPixelWalkFor`; only this
    // publisher was missing it. 유저 확정 2026-09-09
    // (`pixel-verbs-mask-options` = 가): 「선택툴로 선택한채로 사용할때 …
    // 선택의 aa 따르게」.
    session.pixelVerbs.pixelVerbCanvas = () => (
      region: widget.canvasSelectionCommands?.region,
      argb: _brushTool.value.color,
      mask: _views._selectionMaskOptions.value,
    );
    // I-28: where 전체 잘라내기 puts what it cuts — this window's cut tool.
    session.pixelVerbs.cutToolHand = _cutPieceSlot.hold;
    session.textClipboard.canvasText = _canvasTextHand;
    // F-123: what the tools were holding rides with the project — read at
    // each save, put back on open once the library can name the brushes.
    // ⚠️Left on when the project goes behind: the clock saves a tab that is
    // not in front, and the tools it records are the app's either way.
    session.projectDoor.toolChoice = (
      read: () => toolChoiceOf(_brushTool).toJson(),
      resume: (saved) =>
          _brushPresets.resumeChoice(ToolChoice.fromJson(saved)),
    );
    _storyboardThumbnails = _panelPicturesOf(session);
    session.memoryPressureTicks.addListener(
      _storyboardThumbnails.respondToMemoryPressure,
    );
    _views.bindSession(session);
    _collapsedRows.bindSession(session);
    _flipHud.syncFlipAxis();
    // The axis belongs to the panel being worked in, and a claim moves that
    // panel without a session notify.
    session.workingPanelListenable.addListener(_flipHud.syncFlipAxis);
    // The viewers follow the PROJECT: seed them from it now, and again
    // whenever a different one is opened under us.
    _viewersSeededFrom = null;
    _syncViewersWithProject();
    // F-253: the zoom is the cut's — this project's active cut's, from now.
    _timelineZoomCut = null;
    _followTimelineZoomToCut();
    session.addListener(_followTimelineZoomToCut);
    session.addListener(_syncViewersWithProject);
    _showFontsOf(session);
  }

  /// R9-rest: the fonts THIS project carries are what its families are set
  /// with while it is on screen. Stands [session]'s over this device's now
  /// — it is the project coming on screen — and again whenever its list of
  /// them is another ([_followProjectFonts]).
  void _showFontsOf(EditorSessionManager session) {
    _projectFontsShown = null;
    _followProjectFonts();
    session.addListener(_followProjectFonts);
  }

  /// The project on screen's list of fonts as the faces were last told of
  /// it ([_followProjectFonts]) — null: of no project yet.
  List<ProjectFontFile>? _projectFontsShown;

  /// Stands the fonts the project on screen carries over this device's
  /// ([ImportedFonts.showCarried]) when its list of them is another than
  /// the one last said. A step of history that registers a font, or takes
  /// one back out, is such a change; so is another project coming on
  /// screen ([_bindSession]).
  void _followProjectFonts() {
    final session = widget.session;
    final fonts = session.repository.requireProject().fonts;
    // 🚨BY WHAT THE LIST SAYS, NOT BY WHICH LIST IT IS. A project is made
    // anew at every edit and builds its lists anew with it (`Project`'s
    // constructor), so 「is it the same list」 is no at every stroke — and
    // saying the fonts again reads the project file's directory. The
    // session tells of every edit; this hears all of them.
    if (listEquals(fonts, _projectFontsShown)) {
      return;
    }
    _projectFontsShown = fonts;
    final ofTheProject = session.projectFonts;
    _fonts.showCarried((
      files: () => ofTheProject.letterFaceFiles,
      families: () => ofTheProject.families,
      takeOut: ofTheProject.takeOut,
    ));
  }

  /// The text the canvas holds by its box, as it is shown — none while its
  /// letters are typed into: the keys and their copy are the field's then.
  TextCopy? _textHeldByItsBox() {
    final hand = widget.canvasTextCommands;
    final shown = hand?.shownInHand.value;
    return hand == null || hand.typing || shown == null
        ? null
        : (content: shown.content, plate: shown.plate);
  }

  /// The text in hand off its cel — Delete's press on it (R9-rest).
  void _takeTheHeldTextOff() => widget.canvasTextCommands?.deleteText();

  /// I-101: the text this window's canvas holds — what the pill's copy and
  /// cut take ahead of anything selected — the faces a pasted text brings
  /// with it, as a text the hand lands does, and the hand's delete the cut
  /// takes it off its cel with.
  CanvasTextHand get _canvasTextHand => (
    heldByItsBox: _textHeldByItsBox,
    landingWith: _landingWithItsFaces,
    takeOff: _takeTheHeldTextOff,
  );

  /// [landing] — a text set on a cel — with the registering of the faces
  /// its letters are written in ([families]), as one step: the files each
  /// family is set with now, handed to the project on screen
  /// ([ProjectFonts.landingWith]).
  Command _landingWithItsFaces(Command landing, Set<String> families) =>
      widget.session.projectFonts.landingWith(landing, [
        for (final family in families) ..._fonts.filesSetWith(family),
      ]);

  /// The panel pictures [session]'s storyboard and conte draw — rendered
  /// through its camera, never past the camera frame's own size.
  ///
  /// A picture renders the cut's thumbnail frame THROUGH THE CAMERA (what
  /// the shot actually frames — conte-sheet style), scaled to a small
  /// output; always current (a fresh renderer replays surfaces straight
  /// from the brush store).
  /// The frame asked for is the PANEL's frame — the store keys by it, and
  /// the panel resolved which one it is (its own division, or the cut's pin
  /// when that falls inside it). Clamped here so a later trim can never
  /// break a request that was legal when it was made.
  ///
  /// A region — the canvas a conte cell's moving camera sweeps — is shown
  /// instead of the camera's view where it is given
  /// (`ExportFrameRenderer.renderPicture`).
  ///
  /// [session] is the project the store was made for, not whichever is on
  /// screen when a render lands — a render in flight across a tab switch
  /// finishes for the project that asked (I-7).
  StoryboardCutThumbnailStore _panelPicturesOf(EditorSessionManager session) =>
      StoryboardCutThumbnailStore(
        render: (cut, frameIndex, width, region) =>
            ExportFrameRenderer(session: session).renderPicture(
              cut,
              frameIndex.clamp(0, math.max(0, cut.duration - 1)).toInt(),
              width: width,
              region: region,
            ),
        originalSize: () {
          final camera = session.camera.cameraFrameSize;
          return ui.Size(camera.width.toDouble(), camera.height.toDouble());
        },
        invalidationHub: session.renderCaches.cacheInvalidationHub,
        // The census cannot reach a widget State; the session can be
        // reached.
        onHeldBytesChanged: (bytes) =>
            session.renderCaches.storyboardThumbnailBytes = bytes,
      );

  /// Takes off what [_bindSession] hung on [session] — see there.
  void _unbindSession(EditorSessionManager session) {
    session.attachFxConfirm.pending.removeListener(_showAttachFxConfirm);
    // A project behind the one on screen has no canvas: its marquee is not
    // this window's to report or to clear.
    session.pixelVerbs.pixelVerbCanvas = null;
    session.pixelVerbs.cutToolHand = null;
    session.textClipboard.canvasText = null;
    session.memoryPressureTicks.removeListener(
      _storyboardThumbnails.respondToMemoryPressure,
    );
    // Its pictures go with it; the store reports the zero to [session].
    _storyboardThumbnails.dispose();
    _views.unbindSession(session);
    _foldedStoryboard.unbindSession();
    session.workingPanelListenable.removeListener(_flipHud.syncFlipAxis);
    session.removeListener(_syncViewersWithProject);
    session.removeListener(_followTimelineZoomToCut);
    session.removeListener(_followProjectFonts);
  }

  // ── the flip HUD: its own object, in its own file ───────────────────
  //
  // A collaborator (workspace/workspace_flip_hud.dart, a part of this library). The
  // State keeps the entry points its build tree calls as forwarders.
  late final _WorkspaceFlipHud _flipHud = _WorkspaceFlipHud(this);

  // ── the collapsed rows: their own object, in their own file ─────────
  //
  // A collaborator (workspace/workspace_collapsed_rows.dart, a part of this library). The
  // State keeps the entry points its build tree calls as forwarders.
  late final _WorkspaceCollapsedRows _collapsedRows = _WorkspaceCollapsedRows(
    this,
  );

  /// The folded storyboard where it stands on another row than its V row
  /// (workspace/workspace_folded_storyboard.dart, F-322).
  late final _WorkspaceFoldedStoryboard _foldedStoryboard =
      _WorkspaceFoldedStoryboard(this);

  /// What the STORYBOARD panel stacks — bound by that panel, read by the ↑/↓
  /// walk and the flip window while it is the panel being worked in.
  final StoryboardRowsChannel _storyboardRows = StoryboardRowsChannel();

  /// ↑/↓ layer nav (UI-R20 #14): steps through the rows the panel being
  /// worked in DISPLAYS. The inputs must mirror what this state hands the
  /// timeline tab (row filter, hidden sections, fx resolver) — a facet
  /// joining the display policy joins here too, or the keys and the screen
  /// disagree.
  ///
  /// 🗣️유저 2026-09-24: 「v행에 서있다가 위 키 누르면 S1행으로 이동 … 위아래
  /// 이동이 타임라인 내부로 샌다거나 그런거 싹 다 해결」. ↩️The walk was the
  /// timeline's whatever panel you were in: the V row is not one of its
  /// rows, so ↑ from it fell back to the active layer and stepped inside the
  /// cut. The storyboard walks the rows IT stacks now, the same step over a
  /// different list ([stepAlongRows]).
  void _stepDisplayedLayer(int direction) {
    final session = widget.session;
    if (session.workingPanel == WorkingPanel.storyboard) {
      final rows = _storyboardRows.rows;
      var from = rows.indexOf(session.currentRow);
      if (from == -1) {
        // A row this rail no longer shows (its lanes folded) stands on the
        // row the rail lights — the fallback its standing ring takes.
        from = rows.indexOf(session.selectedRow);
      }
      final target = stepAlongRows(
        rows,
        fromIndex: from,
        direction: direction,
        current: session.currentRow,
      );
      if (target != null) {
        session.standOnRow(target, panel: WorkingPanel.storyboard);
      }
      return;
    }
    final target = adjacentDisplayedRow(
      layers: session.layers,
      activeLayerId: session.activeLayerId,
      currentRow: session.currentRow,
      direction: direction,
      hiddenSections: session.railView.hiddenSections.value,
      rowFilter: session.railView.rowFilter.value,
      collapsedAttachBaseIds: session.railView.collapsedAttachBaseIds.value,
      // R10 #19: property rows are stops now, so the walk needs the same
      // lane list the grids draw.
      expandedLayerIds: session.railView.expandedLaneLayerIds.value,
      lanesForLayer: (layer) => timelineLanesForLayer(
        layer: layer,
        session: session,
        expandedGroupKeys: session.railView.expandedLaneGroupKeys.value,
      ),
      fxEnabledOf: session.effectsAndFx.isLayerFxEnabled,
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
    // ⛔The fix is not another `clearTimelineSelections()` here. The law has a
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
      final dockId = _defaultDockOf(tabId);
      _mutatingLayout(() {
        _layout.addTab(tabId, toDockId: dockId);
      });
      _rail.ensureRailOpen(dockId);
      _claimPanelIfFront(tabId, dockId);
    }
  }

  /// The pool's「WAV로 내보내기」: the session says which conform, the flow
  /// says where the file goes, and the writer streams it. False when the
  /// asset has no audio — the panel turns that into words.
  ///
  /// ⛔The conform is BUILT if this machine has not made it yet, rather
  /// than the item refusing on a file that simply has not been played. That
  /// is the same `ensureFor` playback would have called.
  Future<bool> _exportAssetWav(BuildContext context, MediaAsset asset) async {
    final conform = await widget.session.mediaPool.conformBytesForExport(asset.path);
    if (conform == null || !context.mounted) {
      return conform != null;
    }
    await handWrittenFileToUser(
      context,
      suggestedName: '${asset.name}.wav',
      acceptedTypeGroups: const [FileTypeGroups.wav],
      write: (path) =>
          writeConformAsWav(conform: conform, destinationPath: path),
    );
    return true;
  }

  /// A browser "open" — point ONE viewer at the asset and reveal that
  /// viewer's panel, through the common reveal verb so an already-open
  /// one fronts and flashes instead of duplicating.
  ///
  /// 유저 확정 ①: the DOUBLE-CLICK keeps going to the main viewer even
  /// though the main viewer is the floor, so a double-click still swaps
  /// the drawing away. The row menu's second entry is what opens beside
  /// the drawing instead.
  void _openAssetInViewer(MediaAsset asset, {required String tabId}) {
    _openInViewer(
      MediaViewerRequest(path: asset.path, kind: asset.kind),
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

  /// The COMMON "open or locate" entry (UI-R17 #5): hidden panels open
  /// into their default dock; an already-open panel fronts its tab and
  /// FLASHES so the user sees where it lives. Every non-Window "open
  /// panel" affordance should route here.
  void _revealPanel(String tabId) {
    final location = _layout.locateTab(tabId);
    if (location == null) {
      _mutatingLayout(() {
        _layout.addTab(tabId, toDockId: _defaultDockOf(tabId));
      });
      _rail.ensureRailOpen(_defaultDockOf(tabId));
      return;
    }
    // An already-placed panel can still be out of sight — in a rail group
    // the user closed. Revealing it has to OPEN that group, or the flash
    // plays where nobody can see it.
    _rail.ensureRailOpen(location.dockId);
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
    final proceed = await askConfirm(
      context,
      ConfirmQuestion(
        keys: (
          window: const ValueKey<String>('attach-drops-fx-dialog'),
          decline: const ValueKey<String>('attach-drops-fx-cancel'),
          accept: const ValueKey<String>('attach-drops-fx-confirm'),
        ),
        title: strings.tlAttachDropsFxTitle,
        message: strings.tlAttachDropsFxBody,
        // F-303: WHICH rows — the request has always carried their names,
        // and the window never showed them.
        details: [
          NoticeDetails(request.rowNames, heading: strings.tlAttachDropsFxRows),
        ],
      ),
      accept: ConfirmChoice(strings.commonApply),
    );
    request.answer(proceed ?? false);
  }

  /// An injected tool notifier belongs to the shell; only a local fallback
  /// is ours to dispose — the tool's and the transform options' alike.
  void _disposeLocalToolNotifiers() {
    if (widget.brushTool == null) {
      _brushTool.dispose();
    }
    if (widget.transformOptions == null) {
      _transformOptions.dispose();
    }
  }

  @override
  void dispose() {
    _unbindSession(widget.session);
    _foldedStoryboard.dispose();
    _mediaDropVerdict.dispose();
    _brushTool.removeListener(_brushPresets.followBrushTool);
    // A pending debounce would write after the tree is gone; the values are
    // in memory, so writing them NOW is both safe and the last chance.
    if (_brushPresets._brushHandSettingsSave?.isActive ?? false) {
      _brushPresets._brushHandSettingsSave!.cancel();
      _brushPresets.saveHandSettings();
    }
    _brushKeys.detach();
    _brushGroups.dispose();
    _presetLibrary.dispose();
    _tipLibrary.dispose();
    if (widget.canvasTextCommands?.landingWith == _landingWithItsFaces) {
      widget.canvasTextCommands?.landingWith = null;
    }
    _fonts.dispose();
    _cutPieceSlot
      ..removeListener(_brushPresets.armStampOnFreshCut)
      // Its bytes are counted while it lives (CutPieceSlot.allPieceBytes),
      // so it has to stop living with the window.
      ..dispose();
    _disposeLocalToolNotifiers();
    _views.dispose();
    _timelineOrientation.dispose();
    _timelinePixelsPerFrame.dispose();
    _storyboardTrackLaneHeight.dispose();
    _bottomInsetOverride.dispose();
    _brushPresetView.dispose();
    _brushDetailAt
      ..removeListener(_layoutPersistence.scheduleLayoutSave)
      ..dispose();
    for (final controller in _railScrollControllers.values) {
      controller.dispose();
    }
    _panelFlash.dispose();
    for (final slot in _viewerSlots.values) {
      slot.request.removeListener(_writeViewerBookmarks);
    }
    _mainViewer.dispose();
    _subViewer.dispose();
    _draggingTab.dispose();
    _draggingGroup.dispose();
    _stripNearby
      ..left.dispose()
      ..right.dispose()
      ..top.dispose();
    _laidFloorTab.dispose();
    widget.layerNav?.unbind(this);
    widget.barCommands?.unbind(this);
    widget.doorCommands?.unbind(this);
    widget.flipHud?.unbind(this);
    widget.panelsMenu?.detach();
    // After the bridge lets go: its relay listens to it.
    _brushValuesOnStrip.dispose();
    _railToolsOnly.dispose();
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

  /// Runs a change to what the docks show — a layout mutation, or a rail
  /// group opening — and answers each frame panel it brought in front: the
  /// storyboard's playhead is clamped (over-end playheads on non-last cuts
  /// must land back on the counter frame — timeline parity), then the
  /// playhead is shown on the panel's own axis ([_revealThePlayheadOn]).
  ///
  /// ⚠️A rail group opening is one of these changes: a panel in front of a
  /// closed group is not on screen. ↩️It counted as shown wherever it was
  /// in front, since before there were rails.
  void _mutatingLayout(VoidCallback mutate) {
    final before = _framePanelsInFront();
    mutate();
    // The laid panel left the top strip — moved beside the drawing, closed —
    // so the floor is its own two again, and stays so when it comes back.
    if (_laidFloorDockId() == EditorWorkspace.centerGroupId) {
      _laidFloorTab.value = null;
    }
    final cameForward = _framePanelsInFront().difference(before);
    if (cameForward.contains(EditorWorkspace.storyboardTabId)) {
      clampPlayheadForStoryboard(widget.session);
    }
    cameForward.forEach(_revealThePlayheadOn);
  }

  /// The dock lying on the floor: the top strip group [_laidFloorTab] is in,
  /// or the floor's own ([EditorWorkspace.centerGroupId]).
  String _laidFloorDockId() {
    final laid = _laidFloorTab.value;
    final at = laid == null ? null : _layout.locateTab(laid);
    return at != null && _WorkspaceRail.isTopSlot(at.dockId)
        ? at.dockId
        : EditorWorkspace.centerGroupId;
  }

  /// The frame panels in front of a dock that shows.
  Set<String> _framePanelsInFront() => {
    for (final tabId in const [
      EditorWorkspace.timelineTabId,
      EditorWorkspace.storyboardTabId,
    ])
      if (_layout.locateTab(tabId) case final at?
          when _layout.activeTabIn(at.dockId) == tabId &&
              _rail.dockShows(at.dockId))
        tabId,
  };

  /// 🚨A FRAME PANEL BROUGHT FORWARD AGAIN SHOWS ITS PLAYHEAD (유저
  /// 2026-10-14, panels-are-built-only-while-open-Q1: 「다시 열 때
  /// 플레이헤드를 드러낸다」). A panel is built only while it shows, so one
  /// put back in front is built anew where its axis was left — and a run
  /// played meanwhile, or a walk on another panel, left the playhead
  /// elsewhere. Once, as it comes forward, the walk's law ([revealKeptAxis]):
  /// nothing moves while the playhead is in sight, else the least move that
  /// shows it. ⚠️The cost the answer took: a view scrolled away from the
  /// playhead on purpose is pulled back to it too.
  ///
  /// By VALUE, on the kept axis, before the panel is built — against the
  /// window it last showed ([keptAxisWindows]) — so its first frame stands
  /// there. A panel not shown since the project opened has no window, and
  /// stands where the project left it (F-267).
  void _revealThePlayheadOn(String tabId) {
    final cursors = widget.session.playheadCursors;
    final (railId, playhead, extent) = tabId == EditorWorkspace.timelineTabId
        ? (
            _timelineOrientation.value == TimelineOrientation.horizontal
                ? LayerRailId.timeline
                : LayerRailId.xsheet,
            cursors.cutFrame.value,
            _timelinePixelsPerFrame.value,
          )
        : (
            LayerRailId.storyboard,
            cursors.trackFrame.value,
            _storyboardPixelsPerFrame.value,
          );
    final kept = _frameAxisOffsets[railId];
    final window = kept == null ? null : keptAxisWindows[kept];
    if (kept == null || window == null || playhead == null) {
      return;
    }
    revealKeptAxis((
      offset: kept,
      viewport: window,
      extent: extent,
      at: playhead,
    ));
  }

  /// A panel brought forward by ITS OWN BUTTON — its tab, the floor switch
  /// when it lies on the floor, the rail button that opens its group — is a
  /// panel touched (유저 2026-09-24: 「탭 버튼 눌러 콘티로 바꾸는것도 콘티를
  /// 만진것으로」, and 「입구같은거나 규칙/법 완벽하게 통일」). The timeline's
  /// buttons are the same buttons, so they say the same thing.
  ///
  /// ⛔Only a PRESS: the panel's host claims every pointer-down inside it,
  /// and its buttons live in the dock's chrome, outside the host — so the
  /// tab you pressed to bring the storyboard forward left the arrows walking
  /// the timeline you had just put away.
  void _claimPanelOf(String? tabId) {
    switch (tabId) {
      case EditorWorkspace.timelineTabId:
        widget.session.claimTimelineRow();
      case EditorWorkspace.storyboardTabId:
        widget.session.claimStoryboardRow();
    }
  }

  /// [_claimPanelOf] for a door that PLACES a panel rather than fronting it
  /// — its tab dropped somewhere, the Panels list showing it again: the
  /// panel was the one in hand, and it is touched when it lands in front of
  /// [dockId]. A tab added behind another is no panel brought forward.
  void _claimPanelIfFront(String tabId, String dockId) {
    if (_layout.activeTabIn(dockId) == tabId) {
      _claimPanelOf(tabId);
    }
  }

  /// A tab PLACED by hand — dropped on a strip, on an empty dock or on a
  /// rail button: the one move all three drops make, and the one claim.
  void _placeTab(EditorPanelTabDragData data, String dockId, int insertIndex) {
    _mutatingLayout(() {
      _layout.moveTab(
        tabId: data.tabId,
        toDockId: dockId,
        insertIndex: insertIndex,
      );
    });
    _claimPanelIfFront(data.tabId, dockId);
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
  // No panel insists on a WIDTH any more — see [_defaultRegionMinWidth] for
  // the two decisions (R3 #11, scrollbar-unify-Q1) that took it off.

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
          ? TimelinePanel.minPanelHeightIn(context)
          : TimelinePanel.minSheetPanelHeightIn(context),
    EditorWorkspace.storyboardTabId => StoryboardTabHost.minPanelHeightIn(
      context,
    ),
    // The conte and the envelope have no case here on purpose: a page that
    // scales, with no chrome row under the shell, has nothing of its own to
    // protect. (↩️The conte had one — an ACTION field under the page — until
    // its ACTION was edited on the page itself.)
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

  /// The floating region's fold — its chevron's one writer, which the key
  /// presses too (I-40).
  void _toggleRegionFolded() {
    _rebuild(() => _bottomDockCollapsed = !_bottomDockCollapsed);
    _layoutPersistence.scheduleLayoutSave();
  }

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

  /// The brush library panel's five view toggles (F-73 ①). Held HERE, not
  /// in the panel: the Tool Library tab keeps no State once it closes, and
  /// the workspace file is where panel layout already lives.
  final ValueNotifier<BrushPresetViewOptions> _brushPresetView =
      ValueNotifier<BrushPresetViewOptions>(const BrushPresetViewOptions());

  /// Where the brush detail window stands — null until it has been moved
  /// (I-141-Q3 「창은 끌어서 옮기고 자리를 기억한다」). Held HERE for the same
  /// reason as [_brushPresetView]: the tool settings tab keeps no State once
  /// it closes, and the workspace file is where panel layout already lives.
  final ValueNotifier<Offset?> _brushDetailAt = ValueNotifier<Offset?>(null);

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
    // …but the DEFAULT never squeezes the region below 640. A narrower
    // timeline is a fine answer to a window somebody made small, and a poor
    // one to arrive at by itself. Drag the edge in past here and you get it;
    // the app does not choose it.
    final floor = math.min(windowWidth, EditorWorkspace._defaultRegionMinWidth);
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

  /// Whether the brush's values stand in the top strip — false, the
  /// default, stands them in the canvas's pill
  /// ([WorkspacePanelsMenuController.brushValuesOnStrip]).
  ///
  /// ↩️09-16 had the strip as the default; 유저 2026-10-18 (I-34): 「그리고
  /// 기본값은 알약으로 두는걸 기본값으로」. A notifier, as the strip above the
  /// workspace and the canvas inside it both follow it.
  final ValueNotifier<bool> _brushValuesOnStrip = ValueNotifier<bool>(false);

  /// Whether the tool strip holds its tools alone — false, the default,
  /// stands the shortcut buttons above them
  /// ([WorkspacePanelsMenuController.railToolsOnly], I-128).
  final ValueNotifier<bool> _railToolsOnly = ValueNotifier<bool>(false);

  /// How close to the rail's width counts as "the same", so the edge lands on
  /// the pass-through boundary instead of just beside it.
  ///
  /// The rule that boundary decides ([_railPassesBottom]) has no mode and no
  /// switch — it is a comparison — so the only way to CHOOSE it is to be
  /// able to stop the drag exactly there.
  static const double _bottomInsetDetent = 14;

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
      top: onTop ? EditorPanelTabs.stripHeight : DockEdgeSplitter.endInset,
      bottom: onTop ? DockEdgeSplitter.endInset : EditorPanelTabs.stripHeight,
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
        onDragDelta: _insetTravel(
          right: right,
          inset: inset,
          railSpan: railSpan,
          maxInset: maxInset,
        ),
      ),
    );
  }

  /// The side edge's travel, one frame of it — its grip's and its
  /// corner's.
  double Function(double delta) _insetTravel({
    required bool right,
    required double inset,
    required double railSpan,
    required double maxInset,
  }) => (delta) {
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
  };

  /// Snaps to the rail's width when the drag lands near it, so the
  /// pass-through boundary is reachable on purpose.
  static double _detented(double inset, double railSpan) =>
      railSpan > 0 && (inset - railSpan).abs() <= _bottomInsetDetent
      ? railSpan
      : inset;

  /// OS drag-and-drop (§6-i, confirmed): what the drop holds goes through
  /// the one door — never an instant import. Folders drop too (the
  /// cut-folder parser's entrance).
  ///
  /// ↩️F-247 (유저 2026-09-30): 「anicel이면 배치창이아니라 새 프로젝트로
  /// 열도록. tvpp도 똑같이」 — a file 「열기」 opens is not imported: it opens
  /// in a tab of its own, once the import window has closed
  /// ([OpenedFilesDoor]).
  ///
  /// ↩️F-378 (유저 2026-10-17): a drop on a place that opens files — a
  /// viewer, either one — opens there instead ([OsFileDropPlace]). It
  /// went through the door wherever it landed until then.
  void _onOsFilesDropped(DropDoneDetails details) {
    final paths = [for (final file in details.files) file.path];
    final place = _osFileDropPlaceAt(details.globalPosition);
    if (place != null) {
      place.take(paths);
      return;
    }
    unawaited(
      _door.open(context, [for (final path in paths) handedPath(path)]),
    );
  }

  /// The place a drag from the OS is over now, lit while it is
  /// ([OsFileDropPlace.hover]). A drop is left first: the plugin says the
  /// drag has gone before it says what was let go.
  OsFileDropPlace? _osDragOver;

  void _onOsDragMoved(DropEventDetails details) =>
      _osDragIsOver(_osFileDropPlaceAt(details.globalPosition));

  void _onOsDragLeft(DropEventDetails details) => _osDragIsOver(null);

  void _osDragIsOver(OsFileDropPlace? place) {
    if (identical(place, _osDragOver)) {
      return;
    }
    _osDragOver?.hover(over: false);
    _osDragOver = place;
    place?.hover(over: true);
  }

  OsFileDropPlace? _osFileDropPlaceAt(Offset globalPosition) =>
      osFileDropPlaceAt(globalPosition, View.of(context).viewId);

  /// THE ONE DOOR, with what this workspace holds for it (F-282): the
  /// shell's Open door for projects, the import window, the brush library,
  /// the fonts, the shortcut presets, the palettes and the fx plugins.
  OpenedFilesDoor get _door => OpenedFilesDoor(
    openProjects: widget.onOpenProjects,
    importWindow: (picked, {required toPool}) =>
        _openImportWindow(picked: picked, poolOnly: toPool),
    // After the library has landed, as a resumed tool choice is
    // ([_WorkspaceBrushPresets.libraryLanded]): the read puts back what the
    // file holds, and brushes brought before it would go under it — a file
    // the OS opened the app with knocks in the first frame
    // (`open-door-windows-open-with`).
    bringBrushes: (name, bytes) async {
      await _brushPresets.libraryLanded;
      return _presetLibrary.importFile((name: name, bytes: bytes));
    },
    bringFont: (bytes) async {
      final outcome = await _fonts.importBytes(bytes);
      final family = outcome.family;
      return _fonts.noticeOf(outcome) ??
          (family == null ? null : AppText.strings.fontBrought(family));
    },
    bringShortcuts: (files) async => switch (EditorShortcutScope.peek(context)) {
      final bindings? => importShortcutFiles(bindings, files),
      null => const [],
    },
    bringPalettes: (name, bytes) async {
      final current = widget.colorPalette?.value;
      final change = widget.onColorPaletteChanged;
      if (current == null || change == null) {
        return null;
      }
      final (:palettes, :said) = importPaletteFile(current, name, bytes);
      if (palettes != null) {
        change(palettes);
      }
      return said;
    },
    bringFxPlugins: (name, bytes) =>
        installFxPluginFile(context, widget.session.fxPlugins, name, bytes),
  );

  /// The top strip's 「파일 열기」 — and the media panel's ＋, which
  /// [toPool] says: the files it brings register.
  Future<void> _pickAndOpen({bool toPool = false}) async {
    final picked = await pickFilesToOpen(context);
    if (picked.isEmpty || !mounted) {
      return;
    }
    await _door.open(context, picked, toPool: toPool);
  }

  /// The top strip's 「폴더 열기」: a cut folder, into the import window.
  Future<void> _pickFolderAndOpen() async {
    // PICK-2: not `getDirectoryPath`. That call is unimplemented on iOS and
    // returns a SAF tree URI on Android — and the window the folder goes to
    // lists it with `Directory(folder).listSync(recursive: true)`, which
    // answers "that folder is gone" for a URI. A wrong answer that looks
    // like a right one. (The import window's own 「컷 폴더…」 picked it so
    // until F-282.)
    final grant = await pickFolderGrantForUser(context);
    if (grant == null || !mounted) {
      return;
    }
    await _door.open(context, [grant]);
  }

  /// A reference row shows [path] instead of its file (I-47) — no window:
  /// the row keeps every answer it already gave (Q1 2026-09-27: 「창 없이
  /// 바로 바꾼다 (언두 하나)」). A file that would not come in is said, as the
  /// window would have said it — and why ([referenceSwapWords]).
  Future<void> _swapReference(LayerId layerId, String path) async {
    final words = referenceSwapWords(
      await widget.session.importDoors.swapReference(
        layerId: layerId,
        path: path,
      ),
      path,
      widget.session.repository.requireProject(),
    );
    if (words == null || !mounted) {
      return;
    }
    await showAppNotice(
      context,
      title: AppText.strings.commonNotice,
      message: words,
    );
  }

  /// The one import window, from whichever entrance asked for it — done
  /// once it has closed.
  ///
  /// [picked] is what the door handed it ([OpenedFilesDoor]); [initialPaths]
  /// are files the app already holds (a media row, a drag from the pool).
  /// [poolOnly] is a pool's door — the media panel's ＋, the viewer's
  /// 「미디어에 등록」: registering for later is what was asked. [spot] is
  /// where a drop put the file — the window shows it locked.
  Future<void> _openImportWindow({
    List<String> initialPaths = const [],
    List<FolderGrant> picked = const [],
    bool poolOnly = false,
    bool placeOnly = false,
    ImportLayerSpot? spot,
  }) => showDialog<void>(
    context: context,
    builder: (context) => ImportDialog(
      session: widget.session,
      initialPaths: initialPaths,
      picked: picked,
      poolOnly: poolOnly,
      placeOnly: placeOnly,
      spot: spot,
      putSettingsInPlace: _putSettingsInPlace,
    ),
  );

  /// A settings file's [rows] put in place of this device's, each read again
  /// as the app reads it at its start (🗣️I-142-Q3: 「전부 갈아끼운다」) — and
  /// only what was put in place: a holder that saves after a pause would
  /// read back over what it has not written yet.
  Future<void> _putSettingsInPlace(
    SettingsFile file,
    List<SettingsRow> rows,
  ) async {
    await putSettingsIntoTheRoom(file, [
      for (final row in rows) ...row.entries,
    ]);
    for (final reader in {for (final row in rows) row.reader}) {
      if (!mounted) {
        return;
      }
      await _readAgain(reader);
    }
  }

  /// What [reader] holds, read again from the settings room.
  Future<void> _readAgain(SettingsReader reader) async {
    switch (reader) {
      case SettingsReader.appSettings:
        widget.session.appSettings.restore();
      case SettingsReader.uiScale:
        await widget.session.appSettings.rereadUiScale();
      case SettingsReader.shortcuts:
        await EditorShortcutScope.peek(context)?.restore();
      case SettingsReader.layout:
        // 🗣️I-142-Q3 (유저 2026-10-29): 「전부 갈아끼운다」 — no arrangement
        // saved is the factory one. ↩️Nothing read kept the arrangement as
        // it was (10-29).
        if (!await _layoutPersistence.restoreLayout() && mounted) {
          _layoutPersistence.resetWorkspaceLayout();
        }
      case SettingsReader.palette:
        final palette = await ColorPaletteFileService(
          filePath: settingsRoomPath(ColorPaletteFileService.fileName),
        ).loadOrDefaults(starterName: AppText.strings.paletteNumbered(1));
        if (mounted) {
          widget.onColorPaletteChanged?.call(palette);
        }
      case SettingsReader.brushes:
        // In the order the start reads them ([initState]): tips, the presets
        // that name them, and what the hand left on each.
        await _tipLibrary.load();
        await _presetLibrary.load();
        await _brushPresets.recallHandSettings(replacing: true);
        _brushPresets.selectOpeningPreset();
      case SettingsReader.exportWindow:
        // The window reads its file as it opens, and where the file holds
        // none it opens on the live value — this run's, not the defaults
        // the file was put back at (I-142-Q3).
        AppExport.settings.value =
            await AppExportSettingsStore().load() ?? AppExportSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: _onOsDragMoved,
      onDragUpdated: _onOsDragMoved,
      onDragExited: _onOsDragLeft,
      onDragDone: _onOsFilesDropped,
      // THE STAGE'S OUTER SURFACES, SAID ONCE (유저, R4 #2). Every canvas
      // panel in the app is somewhere under here — the drawing floor, the
      // timesheet, the conte, the cut envelope, the media viewer — so this
      // is the one place the room's colours have to be right. ↩️Since F-272
      // only the floor reads them: the others lie on black.
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
            backdropNone: project?.backdropNone ?? false,
            pasteboardNone: project?.pasteboardNone ?? false,
            pasteboardSize: project?.pasteboardSize ?? PasteboardSize.three,
            pasteboardInUse: project?.pasteboardInUse ?? true,
            child: child!,
          );
        },
        // Every place entrance and the pool are in here: the chip's answer
        // travels between them.
        child: MediaDropVerdictScope(
          verdict: _mediaDropVerdict,
          child: _buildWorkspace(context),
        ),
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
      listenable: Listenable.merge([
        _layout,
        _timelineOrientation,
        // What lies on the floor is what the floor is built from.
        _laidFloorTab,
      ]),
      builder: (context, _) => _workspace(context),
    );
  }

  /// The workspace for the current layout and timeline orientation: the
  /// two rails, the floor between them, and the docks floating over it.
  Widget _workspace(BuildContext context) {
    // A rail is THERE when any of its groups is open; which groups
    // those are is the rail's own business.
    final hasLeftDock = _rail.openRailGroups(right: false).isNotEmpty;
    final hasRightDock = _rail.openRailGroups(right: true).isNotEmpty;
    final hasBottomDock = _layout
        .tabsIn(EditorWorkspace.bottomGroupId)
        .isNotEmpty;
    // ★EVERY HEAVY SUBTREE IS BUILT HERE, above the extent builder, and
    // merely REFERENCED inside it. An element whose new widget is the
    // identical instance is reused without rebuilding, so a splitter
    // drag re-lays these out and never rebuilds them — the same
    // mechanism the floor's `child:` uses, applied to the two things
    // that were still paying full price per drag frame.
    final leftRailHosts = _rail.railHosts(right: false);
    final rightRailHosts = _rail.railHosts(right: true);
    final bottomContent = hasBottomDock
        ? _docks.buildBottomDockContent(onTop: _regionOnTop)
        : null;
    final room = _WorkspaceRoom(
      hasLeftDock: hasLeftDock,
      hasRightDock: hasRightDock,
      hasBottomDock: hasBottomDock,
      leftRailHosts: leftRailHosts,
      rightRailHosts: rightRailHosts,
      bottomContent: bottomContent,
    );
    return Row(
      children: [
        // The two tool strips are the only things that take space from
        // the canvas. Everything else LIES ON IT.
        _docks.buildEdgeDock(
          EditorWorkspace.toolLeftGroupId,
          EditorPanelDockSide.left,
        ),
        Expanded(
          // 🚨THE FLOOR IS A RELAYOUT BOUNDARY, which is the one job of this
          // box (F-166, 2026-09-26). The `LayoutBuilder` below owns the build
          // scope of everything on the floor, so a `setState` there that
          // lands OUTSIDE a frame — the canvas panel's at every pen-up, any
          // pointer handler or timer — lays the builder out again on the
          // next frame. Given the Row's loose height it was no boundary,
          // and that relayout climbed every box up to the Scaffold:
          // measured, 21 layouts on each pen-up, each one a repaint mark and
          // a semantics update. Tight constraints stop it at the builder.
          // ⚠️The floor is all `Positioned` children and reads only the
          // maxima, so it was always exactly this big — nothing moves.
          child: SizedBox.expand(
            key: const ValueKey<String>('workspace-floor'),
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
                      // The folded storyboard is the row it stands on, as
                      // tall as that row (F-322).
                      _foldedStoryboard.fold,
                    ]),
                    child: _docks.buildFloorDock(),
                    builder: (context, floor) =>
                        _floorFor(context, floor, room, constraints),
                  ),
            ),
          ),
        ),
        _docks.buildEdgeDock(
          EditorWorkspace.toolRightGroupId,
          EditorPanelDockSide.right,
        ),
      ],
    );
  }

  /// The FLOOR: the panel lying under everything, sized to the room the
  /// rails leave, with the docks floating over it and the region (the
  /// timeline and the paper panels) docked to its top or bottom edge.
  Widget _floorFor(
    BuildContext context,
    Widget? floor,
    _WorkspaceRoom room,
    BoxConstraints constraints,
  ) {
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
    var leftWidth = room.hasLeftDock
        ? _layout.dockExtent(
            EditorWorkspace.railWidthKey(right: false),
            fallback: opening,
          )
        : 0.0;
    var rightWidth = room.hasRightDock
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
        (room.hasLeftDock ? _railGroupGap : 0.0) +
        (room.hasRightDock ? _railGroupGap : 0.0);
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
    final bottomHeight = room.hasBottomDock
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
    final leftRailSpanRaw = room.hasLeftDock
        ? leftWidth + _railGroupGap
        : 0.0;
    final rightRailSpanRaw = room.hasRightDock
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
    final rightRailSpan = room.hasRightDock
        ? constraints.maxWidth -
              grid.position(
                constraints.maxWidth - rightRailSpanRaw,
              )
        : 0.0;
    // Which edge the region is on. Everything below reads
    // this and nothing anywhere else has to.
    final onTop = _regionOnTop;
    final regionSpan = room.hasBottomDock
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
    final regionPanelSpan = room.hasBottomDock
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
        room.hasBottomDock &&
            !_WorkspaceRail.railPassesBottom(
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

    final frame = _WorkspaceFrame(
      grid: grid,
      constraints: constraints,
      onTop: onTop,
      hasLeftDock: room.hasLeftDock,
      hasRightDock: room.hasRightDock,
      hasBottomDock: room.hasBottomDock,
      leftWidth: leftWidth,
      rightWidth: rightWidth,
      ceiling: ceiling,
      bottomHeight: bottomHeight,
      bottomInset: bottomInset,
      leftRailSpanRaw: leftRailSpanRaw,
      rightRailSpanRaw: rightRailSpanRaw,
      leftRailSpan: leftRailSpan,
      rightRailSpan: rightRailSpan,
      floorCover: floorCover,
      leftStop: leftStop,
      rightStop: rightStop,
    );
    return Stack(
      children: [
        // ★ THE FLOOR. Everything below this line is drawn on
        // top of the drawing.
        _floor(frame, floor),
        // ★ The rails FLOAT. A gap of pasteboard between
        // the strip and the panel, another above the
        // first panel, and each panel its own rounded
        // object — the same kind of thing the timeline
        // is, rather than a slab bolted to the strip.
        // Their width grips ride their own inner edges
        // inside the column.
        _leftRailColumn(frame, room.leftRailHosts),
        _rightRailColumn(frame, room.rightRailHosts),
        // ★The collapsed row, over the artwork and OUTSIDE
        // the region's clip. It has to be a sibling: the
        // region is inside a `SuperellipseClip`, so an
        // overlay mounted in there could never reach up
        // onto the canvas. It also has to come BEFORE the
        // region in this stack — the region paints over
        // it, which is what keeps the row from spilling
        // onto the sill when the two meet.
        if (room.hasBottomDock && _bottomDockCollapsed)
          _collapsedRowOverlay(frame),
        _bottomDock(frame, room.bottomContent),
      ],
    );
  }

  Positioned _bottomDock(_WorkspaceFrame frame, Widget? bottomContent) {
    return Positioned(
      // ★KEYED, because the folded row is laid into this stack just before
      // it: unkeyed, the region's slot was matched to the row's by position
      // and every fold and every unfold built the whole region afresh
      // (measured 09-27: a new grid, host and storyboard each time).
      key: const ValueKey<String>('workspace-bottom-region'),
      left: frame.bottomInset,
      right: frame.bottomInset,
      top: frame.onTop ? 0 : null,
      bottom: frame.onTop ? null : 0,
      height: frame.hasBottomDock ? frame.bottomHeight : null,
      child: _docks.buildBottomDock(
        availableExtent: frame.constraints.maxHeight,
        content: bottomContent == null
            ? null
            : _bottomDockSplitterEdges(frame.onTop, bottomContent),
        inset: frame.bottomInset > 0,
        onTop: frame.onTop,
        // Every grip the region has, laid on its own
        // edges inside its own clip.
        grips: !frame.hasBottomDock ? const [] : _bottomDockGrips(frame),
      ),
    );
  }

  /// [content] told the edges [_bottomDockGrips] lays its grips on
  /// (F-452): both sides, and the artwork-facing edge while unfolded.
  Widget _bottomDockSplitterEdges(bool onTop, Widget content) =>
      DockSplitterEdges(
        left: true,
        right: true,
        top: !_bottomDockCollapsed && !onTop,
        bottom: !_bottomDockCollapsed && onTop,
        child: content,
      );

  List<Widget> _bottomDockGrips(_WorkspaceFrame frame) {
    // The widest an inset may be: the region keeps at least
    // `_minBottomRegionWidth` between its two grips.
    final maxInset = math.max(
      0.0,
      (frame.constraints.maxWidth - _minBottomRegionWidth) / 2,
    );
    return [
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
        _bottomHeightGrip(frame.onTop, frame.constraints),
      // The region's side grips. TWO of
      // them and ONE number — pulling
      // either edge in pulls the other in
      // by the same amount, because the
      // region stays centred on the window.
      _bottomInsetGrip(
        right: false,
        inset: frame.bottomInset,
        onTop: frame.onTop,
        // RAW, to match the gate above.
        railSpan: frame.leftRailSpanRaw,
        maxInset: maxInset,
      ),
      _bottomInsetGrip(
        right: true,
        inset: frame.bottomInset,
        onTop: frame.onTop,
        // RAW, to match the gate above.
        railSpan: frame.rightRailSpanRaw,
        maxInset: maxInset,
      ),
      // Where those sides meet the height's edge (I-60) — gone with the
      // height grip while folded, which is the axis the fold is about.
      if (!_bottomDockCollapsed) ...[
        _bottomCornerGrip(right: false, frame: frame, maxInset: maxInset),
        _bottomCornerGrip(right: true, frame: frame, maxInset: maxInset),
      ],
    ];
  }

  Positioned _collapsedRowOverlay(_WorkspaceFrame frame) {
    return Positioned(
      left: frame.bottomInset,
      right: frame.bottomInset,
      top: frame.onTop ? frame.bottomHeight : null,
      bottom: frame.onTop ? null : frame.bottomHeight,
      height: _collapsedRows.collapsedRowHeight(),
      child: _collapsedRows.collapsedRowOverlay(),
    );
  }

  Positioned _rightRailColumn(
    _WorkspaceFrame frame,
    Map<String, Widget> rightRailHosts,
  ) {
    return Positioned(
      right: 0,
      top: frame.grid.position(
        (frame.onTop ? frame.rightStop : 0) + _railGroupGap,
      ),
      bottom: frame.onTop ? 0 : frame.rightStop,
      width: frame.hasRightDock ? frame.rightRailSpan : null,
      child: _rail.buildRailColumn(
        EditorPanelDockSide.right,
        width: frame.rightWidth,
        hosts: rightRailHosts,
        // 결정 8: the same ceiling both sides read.
        dragCeiling: frame.ceiling,
      ),
    );
  }

  Positioned _leftRailColumn(
    _WorkspaceFrame frame,
    Map<String, Widget> leftRailHosts,
  ) {
    return Positioned(
      left: 0,
      // ★These two widgets are what actually CARRY a
      // rail-docked canvas, so this is where the
      // chain lands on the grid or does not. The
      // right span especially: it is subtracted
      // from an on-grid right edge, so a raw width
      // here puts the column's LEFT edge — and
      // everything docked in it — between two
      // device pixels.
      top: frame.grid.position(
        (frame.onTop ? frame.leftStop : 0) + _railGroupGap,
      ),
      bottom: frame.onTop ? 0 : frame.leftStop,
      // The gap is INSIDE the column's box now: the
      // rail's own scrollbar rides it. ⛔Take the
      // quantized span rather than re-adding the
      // gap: `floorCover`, `columnStop` and this
      // widget have to be one spelling of one
      // boundary, or the canvas is framed against
      // an edge the rail is not drawn at.
      width: frame.hasLeftDock ? frame.leftRailSpan : null,
      child: _rail.buildRailColumn(
        EditorPanelDockSide.left,
        width: frame.leftWidth,
        hosts: leftRailHosts,
        // 결정 8: the same ceiling both sides read.
        dragCeiling: frame.ceiling,
      ),
    );
  }

  Positioned _floor(_WorkspaceFrame frame, Widget? floor) {
    return Positioned.fill(
      child: CanvasFloorInsets(
        insets: frame.floorCover,
        // ⑩: the collapsed row lies ON the artwork
        // just past the region's edge. It frames
        // nothing, so it is not in `insets` — but a
        // bar on the bottom edge would be under it.
        bottomOverlaySpan:
            frame.hasBottomDock && _bottomDockCollapsed && !frame.onTop
            ? _collapsedRows.collapsedRowHeight()
            : 0,
        // WHERE each column actually is, not just how
        // wide it is. A rail panel is as tall as it was
        // left at, so a short one covers a band and not
        // an edge — and the scrollbar that stepped
        // aside for the whole edge read as floating for
        // no reason (유저, R3 #5). The left one is for
        // the brush pill on that edge (I-34).
        leftRailBand: _rail.railBand(
          right: false,
          stop: frame.leftStop,
          onTop: frame.onTop,
          height: frame.constraints.maxHeight,
          grid: frame.grid,
        ),
        rightRailBand: _rail.railBand(
          right: true,
          stop: frame.rightStop,
          onTop: frame.onTop,
          height: frame.constraints.maxHeight,
          grid: frame.grid,
        ),
        child: floor!,
      ),
    );
  }

  Positioned _bottomHeightGrip(bool onTop, BoxConstraints constraints) {
    return Positioned(
      left: DockEdgeSplitter.endInset,
      right: DockEdgeSplitter.endInset,
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
        onDragDelta: _heightTravel(onTop, constraints),
      ),
    );
  }

  /// The artwork-facing edge's travel, one frame of it — its grip's and
  /// its corners'.
  double Function(double delta) _heightTravel(
    bool onTop,
    BoxConstraints constraints,
  ) => (delta) {
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
      // ↩️It fell back on the fixed 350 while the region is DRAWN at its
      // D37 opening (half the window), so the first pull of a region
      // nobody had sized jumped it to 350 and moved on from there — 125px
      // the wrong way on a 1000px window (found by I-60's corner, which is
      // this edge). The same opening the drawing reads.
      fallback: EditorWorkspace.bottomDockHeightFallbackFor(
        constraints.maxHeight,
        DeviceGrid.of(context),
      ),
      // The splitter stops where the
      // panels stop shrinking, and
      // never banks height past what
      // the window can show — a
      // surplus behind the ceiling is
      // spent before the edge moves
      // again, which reads as a
      // splitter that lags the cursor.
      minExtent: math.min(
        _verticalDockMinimumExtent(EditorWorkspace.bottomGroupId),
        _docks.bottomDockCeiling(constraints.maxHeight),
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
        EditorPanelLayoutModel.maxDockExtent,
        _docks.bottomDockDragCeiling(constraints.maxHeight),
      ),
    );
    return onTop ? used : -used;
  };

  /// A CORNER of the artwork-facing edge, where a side edge meets it
  /// (I-60): one drag, the side's width and the height, each through the
  /// travel its own grip spends.
  Positioned _bottomCornerGrip({
    required bool right,
    required _WorkspaceFrame frame,
    required double maxInset,
  }) {
    final onTop = frame.onTop;
    return Positioned(
      left: right ? null : 0,
      right: right ? 0 : null,
      top: onTop ? null : 0,
      bottom: onTop ? 0 : null,
      child: DockCornerGrip(
        key: ValueKey<String>('bottom-corner-${right ? 'right' : 'left'}'),
        corner: switch ((onTop, right)) {
          (false, false) => Alignment.topLeft,
          (false, true) => Alignment.topRight,
          (true, false) => Alignment.bottomLeft,
          (true, true) => Alignment.bottomRight,
        },
        onDragStart: () => _bottomInsetDragRaw = frame.bottomInset,
        onDragEnd: () => _bottomInsetDragRaw = null,
        onDragX: _insetTravel(
          right: right,
          inset: frame.bottomInset,
          railSpan: right ? frame.rightRailSpanRaw : frame.leftRailSpanRaw,
          maxInset: maxInset,
        ),
        onDragY: _heightTravel(onTop, frame.constraints),
      ),
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
///
/// 🗣️I-147 (유저 2026-10-30): and it wears the panel tab's band along its top
/// edge, inside its own square ([LiftingGripBand]) — 「버튼을 길게하는게
/// 아니라 … 버튼내에서 공간나누던가해서 오버레이로 위에 띠」 — which lifts
/// the button with every panel it holds to another strip's empty slot. The
/// empty slot wears none: it holds nothing to lift, and it takes a lifted
/// button as it takes a panel.
class _RailGroupButton extends StatelessWidget {
  const _RailGroupButton({
    required this.railId,
    required this.open,
    required this.tabs,
    required this.nearby,
    required this.dragging,
    required this.onPressed,
    required this.onTabDropped,
    this.carried,
    this.onGroupDropped,
    this.onLifted,
    this.face,
  });

  final String railId;
  final bool open;
  final List<EditorPanelTab> tabs;

  /// Whether the pointer is on the strip — the band's first rung.
  final ValueListenable<bool> nearby;

  /// The panel in flight that this button would take — null when none is,
  /// or when the one that is may not stand here.
  final EditorPanelTabDragData? dragging;

  /// The strip button in flight, for the empty slot that would take it.
  final _StripGroupDragData? carried;

  /// Drawn INSTEAD of the glyph, for a group whose state is what the button
  /// should be saying — the colour pair.
  final Widget? face;

  /// Null for the empty slot, which is a target and not a switch.
  final VoidCallback? onPressed;
  final ValueChanged<EditorPanelTabDragData> onTabDropped;

  /// Where a carried button lands — the empty slot's alone.
  final ValueChanged<_StripGroupDragData>? onGroupDropped;

  /// Told what this button's band carries as it is lifted, null as it lands.
  final ValueChanged<_StripGroupDragData?>? onLifted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tooltip = tabs.isEmpty
        ? AppText.strings.panelNewGroup
        : [for (final tab in tabs) tab.label].join(' · ');
    final band = tabs.isEmpty
        ? null
        : LiftingGripBand<_StripGroupDragData>(
            gripKey: ValueKey<String>('rail-group-band-$railId'),
            data: _StripGroupDragData(railId),
            chip: [
              for (final tab in tabs) (icon: tab.icon, label: tab.label),
            ],
            nearby: nearby,
            onLifted: onLifted,
          );
    final button = face == null
        ? RailButton(
            keyValue: 'rail-group-$railId',
            tooltip: tooltip,
            icon: tabs.isEmpty ? Icons.add : tabs.first.icon,
            selected: open,
            onPressed: onPressed,
            band: band,
          )
        : AppTooltip(
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
                  mouseCursor: AppCursors.press,
                  onTap: silentPress(onPressed),
                  // The pair sizes itself to one button cell, so a group that
                  // wears a face is the same square as every other.
                  child: SizedBox.square(
                    dimension: ToolsPanel.buttonExtent,
                    child: Stack(
                      children: [
                        Positioned.fill(child: face!),
                        if (band != null)
                          Positioned(left: 0, right: 0, top: 0, child: band),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
    final takesPanel = dragging == null
        ? button
        : DragTarget<EditorPanelTabDragData>(
            onAcceptWithDetails: (details) => onTabDropped(details.data),
            builder: (context, candidate, rejected) => _offered(
              colorScheme,
              hovered: candidate.isNotEmpty,
              child: button,
            ),
          );
    final landing = onGroupDropped;
    if (carried == null || landing == null) {
      return takesPanel;
    }
    return DragTarget<_StripGroupDragData>(
      onAcceptWithDetails: (details) => landing(details.data),
      builder: (context, candidate, rejected) => _offered(
        colorScheme,
        hovered: candidate.isNotEmpty,
        child: takesPanel,
      ),
    );
  }

  /// [child] outlined as a place something in flight may land.
  Widget _offered(
    ColorScheme colorScheme, {
    required bool hovered,
    required Widget child,
  }) => DecoratedBox(
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
    child: child,
  );
}

/// A strip BUTTON in flight — carried by its band ([LiftingGripBand]) with
/// every panel it holds (I-147).
class _StripGroupDragData {
  const _StripGroupDragData(this.groupId);

  /// The slot the button stood in as it was lifted.
  final String groupId;
}

/// The workspace's resolved geometry for one layout pass — what the rail
/// columns, the floor and the bottom region each need to know about where
/// the others are. Computed once per build.
///
/// ONE object instead of the eight loose numbers each builder used to take
/// (Round 0's extraction debt, repaid in Round 2 of the audit, 2026-09-03).
class _WorkspaceFrame {
  const _WorkspaceFrame({
    required this.grid,
    required this.constraints,
    required this.onTop,
    required this.hasLeftDock,
    required this.hasRightDock,
    required this.hasBottomDock,
    required this.leftWidth,
    required this.rightWidth,
    required this.ceiling,
    required this.bottomHeight,
    required this.bottomInset,
    required this.leftRailSpanRaw,
    required this.rightRailSpanRaw,
    required this.leftRailSpan,
    required this.rightRailSpan,
    required this.floorCover,
    required this.leftStop,
    required this.rightStop,
  });

  final DeviceGrid grid;
  final BoxConstraints constraints;
  final bool onTop;
  final bool hasLeftDock;
  final bool hasRightDock;
  final bool hasBottomDock;
  final double leftWidth;
  final double rightWidth;
  final double ceiling;
  final double bottomHeight;
  final double bottomInset;
  final double leftRailSpanRaw;
  final double rightRailSpanRaw;
  final double leftRailSpan;
  final double rightRailSpan;
  final EdgeInsets floorCover;
  final double leftStop;
  final double rightStop;
}

/// What one workspace build settled before laying out the floor: which
/// rails and the bottom dock are there, the rail hosts (built ONCE above
/// the extent builder and merely referenced inside it), and the bottom
/// dock's content. The floor reads it instead of six captured locals.
class _WorkspaceRoom {
  const _WorkspaceRoom({
    required this.hasLeftDock,
    required this.hasRightDock,
    required this.hasBottomDock,
    required this.leftRailHosts,
    required this.rightRailHosts,
    required this.bottomContent,
  });

  final bool hasLeftDock;
  final bool hasRightDock;
  final bool hasBottomDock;
  final Map<String, Widget> leftRailHosts;
  final Map<String, Widget> rightRailHosts;
  final Widget? bottomContent;
}

/// The canvas area's key for one project — see
/// [_EditorWorkspaceState._canvasAreaKey]. Equal for the same session,
/// distinct from every other key type's.
class _CanvasAreaKey extends GlobalObjectKey {
  const _CanvasAreaKey(super.value);
}

/// What a person reads when a file let go on a reference row did not come
/// in (I-47): the program language's sentence for why — or null when there
/// is nothing to say, the file in or the row left as it was.
///
/// 🗣️I-68 「가」 ⓐ (유저 2026-10-10 「추천대로가자」): a file that reads, and
/// only lacks the picture the row's cel shows, says that — 「bg.png에는
/// 2번째 그림이 없습니다」. ↩️It was told 「could not read the file」, and so
/// was a row that changed while its file was read.
///
/// The file is named as [project]'s pool shows it (F-376).
String? referenceSwapWords(
  ReferenceRedraw answer,
  String path,
  Project project,
) => switch (answer) {
  ReferenceLaid() || ReferenceLeftAlone() => null,
  ReferenceUnreadable() => AppText.strings.imUnreadable(
    project.shownNameOfMedia(path),
  ),
  ReferenceLacksPicture(:final picture) => AppText.strings.imLacksPicture(
    project.shownNameOfMedia(path),
    picture + 1,
  ),
};
