import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../models/brush_group_id.dart';
import '../models/brush_preset.dart';
import '../models/brush_preset_id.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/layer_id.dart';
import '../models/media_asset.dart' show MediaAsset;
import '../services/brush_preset_file_service.dart';
import '../services/brush_tip_library_service.dart';
import '../services/canvas_color_sampler.dart' show CanvasColorSampleSource;
import '../services/canvas_flood_fill.dart' show FloodFillOptions;
import '../services/canvas_selection.dart' show SelectionMaskOptions;
import '../services/resample/resample_kernel.dart' show ResampleMode;
import 'brush/brush_preset_library.dart';
import 'brush/brush_preset_panel.dart';
import 'brush/brush_tip_library.dart';
import 'brush/brush_tool_state.dart';
import 'brush/canvas_selection_commands.dart';
import 'brush/canvas_view_commands.dart';
import 'brush/paint_tool_state_notifier.dart';
import 'brush/tool_library_panel.dart';
import 'brush/tool_settings_panel.dart';
import 'color/color_button_window.dart';
import 'brush/tools_panel.dart';
import 'editor_canvas_area.dart';
import 'editor_session_manager.dart';
import 'export/export_frame_renderer.dart';
import 'export/export_plan.dart';
import 'import/import_dialog.dart';
import 'media/media_browser_panel.dart';
import 'media/media_viewer_tab_host.dart';
import 'panels/editor_dock_host.dart';
import 'panels/editor_panel_dock.dart';
import 'panels/editor_panel_layout.dart';
import 'panels/panel_flash.dart';
import 'panels/panel_visibility_scope.dart';
import 'panels/editor_panel_tabs.dart';
import 'panels/workspace_layout_store.dart';
import 'panels/workspace_panels_menu.dart';
import 'keyed_keep_alive_stack.dart';
import 'sliced_value_listenable_builder.dart';
import 'conte/conte_fonts.dart';
import 'conte/conte_ink.dart';
import 'conte/conte_tab_host.dart';
import 'storyboard_cut_thumbnail_store.dart';
import 'storyboard_panel.dart' show StoryboardPanel;
import 'storyboard_playhead_mapping.dart';
import '../models/timeline_row_address.dart';
import 'timeline/layer_rail_window.dart';
import '../models/layer_kind.dart' show layerKindHoldsDrawings;
import 'canvas/flip_hud_controller.dart';
import 'canvas/flip_hud_model.dart';
import 'timeline/layer_timeline_display_adapter.dart'
    show horizontalLayerDisplayOrder;
import 'timeline/property_lane_model.dart'
    show TimelineDisplayRow, buildTimelineDisplayRows;
import 'timeline/timeline_se_row_visual.dart' show layerKindUsesSeSheetCells;
import 'timeline/timeline_lane_provider.dart';
import 'timeline/timeline_layer_nav.dart';
import 'timeline/timeline_row_filter.dart';
import 'timeline/timeline_section_policy.dart';
import '../models/onion_skin_settings.dart';
import '../services/color_palette_file_service.dart';
import 'panels/onion_skin_panel.dart';
import 'storyboard_tab_host.dart';
import '../models/canvas_viewport.dart';
import 'timeline/timeline_orientation.dart';
import 'timeline/timeline_panel.dart' show TimelinePanel;
import 'text/app_strings.dart';
import 'timeline_tab_host.dart';
import 'timesheet/timesheet_ink_controller.dart';
import 'timesheet_tab_host.dart';

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
    this.canvasViewCommands,
    this.canvasSelectionCommands,
    this.layerNav,
    this.onInvokeAction,
    this.flipHud,
  });

  final EditorSessionManager session;

  /// The active-tool notifier, owned by the shell (HomePage) so the tool
  /// shortcuts (B/E) and the workspace panels drive one state. Null keeps
  /// a workspace-local notifier (focused widget tests).
  final ValueNotifier<BrushToolState>? brushTool;

  /// The shell-owned rotate/flip shortcut channel (P8, R/Shift+R/H),
  /// forwarded to the canvas panel.
  final CanvasViewCommands? canvasViewCommands;

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

  static const double bottomPanelHeight = 350;
  static const double sideDockWidth = 260;

  static const String leftGroupId = 'left';
  static const String rightGroupId = 'right';
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
  static const String colorWheelTabId = 'color-wheel';
  static const String onionSkinTabId = 'onion-skin';
  static const String cameraTabId = 'camera';
  static const String mediaTabId = 'media';
  static const String timelineTabId = 'timeline';
  static const String storyboardTabId = 'storyboard';
  static const String conteTabId = 'conte';
  static const String timesheetTabId = 'timesheet';
  static const String mediaViewerTabId = 'media-viewer';

  /// The WIDTH frame-axis panels lay out at when docked somewhere narrower
  /// (their label rails and toolbars assume a wide region); the tab shell
  /// hosts them inside a horizontal scroller then. Unchanged by the
  /// shrink-floor round — in a narrow side dock, scrolling sideways is
  /// genuinely what helps.
  static const double _frameAxisMinContentWidth = 640;

  /// The HEIGHT is each panel's own floor now, not one number for three.
  ///
  /// It used to be a flat 280 for all of them, and that is what the user
  /// reported (2026-08-02): shrinking the dock did not shrink the panel, it
  /// rendered the panel at 280 inside a vertical scroller and CUT the
  /// bottom off — the pinned horizontal scrollbar row first, then the foot
  /// of the vertical scrollbar rail. At the dock's own minimum 150px was
  /// already gone.
  ///
  /// Each panel states what it actually costs (chrome + two rows), so the
  /// body is what shrinks and the three rows the user needs to see stay on
  /// screen. `_verticalDockMinimumExtent` then stops the splitter there,
  /// which is what keeps the vertical scroller from ever engaging in
  /// practice — it survives only as the guard for hosts smaller still.
  static double? _minContentHeightFor(String tabId) => switch (tabId) {
    timelineTabId => TimelinePanel.minPanelHeight,
    storyboardTabId => StoryboardTabHost.minPanelHeight,
    // The conte sheet has no fixed rows to protect: it is a page that
    // scales, and the sweep finds no height at which it overflows. Giving
    // it a floor would only re-create the scroller this round removes.
    _ => null,
  };

  @override
  State<EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends State<EditorWorkspace> {
  /// The factory-default arrangement (also the validation baseline when a
  /// saved layout is restored: it names every known tab and its home dock).
  ///
  /// R26 #31 — the user's working arrangement: the TIMESHEET takes the
  /// right vertical dock (a B4 sheet wants height, not a bottom strip),
  /// the Tool Library keeps the top of the wide left dock and the Tool
  /// SETTINGS get their own section under it (the two panels a stroke
  /// alternates between, both open at once), and the frame-axis panels
  /// keep the bottom.
  ///
  /// The sheet being VISIBLE by default is what makes this change cost a
  /// test round: it mounts its own ink views and cells, so any finder that
  /// looks for a canvas widget app-wide now matches twice. The fix is
  /// always to scope the finder to its panel — never to hide the sheet
  /// again.
  static Map<String, List<DockSection>> _defaultDocks() => {
    EditorWorkspace.toolLeftGroupId: [
      DockSection(tabs: [EditorWorkspace.toolsTabId]),
    ],
    EditorWorkspace.toolRightGroupId: <DockSection>[],
    EditorWorkspace.leftGroupId: [
      DockSection(
        tabs: [
          EditorWorkspace.brushesTabId,
          // The Color TAB retired (R9 #14): the wheel and the palette are
          // the two tabs of the 「컬러 버튼창」 now, opened from the tool
          // rail's selected-colour swatch — the control the user actually
          // reaches for, in the place they reach for it.
          // The camera PANEL retired (R11-⑤): the canvas overlay handles
          // pose editing, the timeline camera row its eye/opacity, and the
          // AE clipboard copy moved to the Cut menu.
          EditorWorkspace.mediaTabId,
          // Trailing so the long-standing tab positions (and every test
          // tapping them) stay put; the strip scrolls to reach it.
          EditorWorkspace.onionSkinTabId,
        ],
        activeTabId: EditorWorkspace.brushesTabId,
      ),
      DockSection(tabs: [EditorWorkspace.brushSettingsTabId]),
    ],
    EditorWorkspace.rightGroupId: [
      DockSection(tabs: [EditorWorkspace.timesheetTabId]),
    ],
    EditorWorkspace.centerGroupId: [
      DockSection(tabs: [EditorWorkspace.canvasTabId]),
    ],
    EditorWorkspace.bottomGroupId: [
      DockSection(
        tabs: [
          EditorWorkspace.timelineTabId,
          EditorWorkspace.storyboardTabId,
          EditorWorkspace.conteTabId,
          // The media viewer (R4, §6-h) joins the paper-family tabs; it
          // fronts itself when the browser opens something into it.
          EditorWorkspace.mediaViewerTabId,
        ],
        activeTabId: EditorWorkspace.timelineTabId,
      ),
    ],
  };

  /// Only narrow-fit panels may live in the slim edge docks.
  static const Set<String> _edgeDockTabIds = {EditorWorkspace.toolsTabId};

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

  /// Layout persistence: null in tests (see [EditorWorkspace.layoutStore]).
  WorkspaceLayoutStore? _layoutStore;
  Timer? _layoutSaveTimer;

  /// Keeps the canvas element (and its viewport state) alive when the
  /// canvas tab re-docks.
  final GlobalKey _canvasAreaKey = GlobalKey();

  late final ValueNotifier<BrushToolState> _brushTool =
      widget.brushTool ?? PaintToolStateNotifier(BrushToolState.defaults);

  /// The last selection VARIANT used (R17-U: rectangle/lasso are one
  /// toolbar tool; the single Select button re-activates this).
  CanvasTool _lastSelectionVariant = CanvasTool.selectRect;

  void _rememberSelectionVariant() {
    final tool = _brushTool.value.tool;
    if (tool == CanvasTool.selectRect || tool == CanvasTool.lasso) {
      _lastSelectionVariant = tool;
    }
  }

  /// Which preset is highlighted PER painting tool (R11-④: the brush and
  /// the eraser keep separate selections; their settings live in
  /// [PaintToolStateNotifier]'s bank).
  final Map<CanvasTool, BrushPresetId?> _activePresetByTool = {};

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
  final ValueNotifier<ResampleMode> _transformResampleMode = ValueNotifier(
    ResampleMode.blend,
  );

  /// R28 #6: the eyedropper's reference source (Tool Settings knob). The
  /// user's default is "pick what you SEE".
  final ValueNotifier<CanvasColorSampleSource> _eyedropperSource =
      ValueNotifier(CanvasColorSampleSource.display);

  /// The color wheel's spare (background) slot; the foreground IS the
  /// brush color. Held here so it survives tab switches.
  final ValueNotifier<int> _colorWheelBackground = ValueNotifier(0xFFFFFFFF);

  /// The pinned palette + recent colors (P4), persisted app-side.
  final ValueNotifier<ColorPaletteState> _colorPalette = ValueNotifier(
    const ColorPaletteState(),
  );
  ColorPaletteFileService? _paletteService;

  void _setColorPalette(ColorPaletteState next) {
    _colorPalette.value = next;
    unawaited(_paletteService?.save(next));
  }

  void _recordRecentColor() {
    _setColorPalette(
      _colorPalette.value.withRecentColor(_brushTool.value.color),
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
    final next = Set<LayerId>.of(_expandedLaneLayerIds.value);
    if (!next.remove(layerId)) {
      next.add(layerId);
    }
    _expandedLaneLayerIds.value = next;
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
    if (!next.remove(groupKey)) {
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

  /// Media viewer state (R4, §6-h): what it looks at and its zoom/pan —
  /// owned here so both survive tab switches and re-docking.
  final ValueNotifier<MediaViewerRequest?> _mediaViewerRequest = ValueNotifier(
    null,
  );
  final ValueNotifier<CanvasViewport?> _mediaViewerViewport = ValueNotifier(
    null,
  );

  /// The cel stores are the SESSION's (R5): the archive saves and loads
  /// them with the project; this controller owns only the edit sessions.
  late final ConteInkController _conteInk = ConteInkController(
    rowStore: widget.session.conteInkRowStore,
    pageStore: widget.session.conteInkPageStore,
  );

  late final StoryboardCutThumbnailStore _storyboardThumbnails;

  @override
  void initState() {
    super.initState();
    _tipLibrary = BrushTipLibrary(service: widget.tipLibraryService);
    _presetLibrary = BrushPresetLibrary(
      fileService: widget.presetFileService,
      filePicker: widget.brushFilePicker,
      tipLibrary: _tipLibrary,
    );
    // Tips first: presets reference them by id, so the library has to be
    // able to answer before the presets that ask are read.
    unawaited(_tipLibrary.load().then((_) => _presetLibrary.load()));
    // Warm the conte's embedded faces so the sheet opens with its type
    // ready (the tab host still awaits, for the cold path).
    unawaited(ensureConteFontsLoaded());
    _paletteService = Platform.environment['FLUTTER_TEST'] == 'true'
        ? null
        : ColorPaletteFileService();
    unawaited(
      _paletteService?.loadOrDefaults().then((palette) {
        if (mounted) {
          _colorPalette.value = palette;
        }
      }),
    );
    // Recent colors record on COMMITTED work (history changes) — the color
    // actually drawn with, not every wheel drag sample (P4).
    widget.session.historyManager.addListener(_recordRecentColor);
    _brushTool.addListener(_rememberSelectionVariant);
    _storyboardThumbnails = StoryboardCutThumbnailStore(
      render: _renderStoryboardThumbnail,
      invalidationHub: widget.session.cacheInvalidationHub,
    );
    _layoutStore =
        widget.layoutStore ??
        (Platform.environment['FLUTTER_TEST'] == 'true'
            ? null
            : WorkspaceLayoutStore());
    unawaited(_restoreLayout());
    _layout.addListener(_scheduleLayoutSave);
    for (final extent in _railExtents.values) {
      extent.addListener(_scheduleLayoutSave);
    }
    widget.panelsMenu?.attach(
      entriesProvider: _panelMenuEntries,
      toggler: _togglePanelVisibility,
      relay: _layout,
      layoutReset: _resetWorkspaceLayout,
    );
    widget.layerNav?.bind(_stepDisplayedLayer);
    widget.flipHud?.bind(_flipHudSnapshot);
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
      return FlipHudSnapshot.empty;
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
        _flipHudRow(
          rows[index],
          session,
          withRuns: !onlyCurrent || index == rowIndex,
        ),
    ];
    return FlipHudSnapshot(
      rows: hudRows,
      rowIndex: rowIndex,
      frameIndex: session.currentFrameIndex,
      frameCount: cut.duration,
    );
  }

  FlipHudRow _flipHudRow(
    TimelineDisplayRow row,
    EditorSessionManager session, {
    required bool withRuns,
  }) {
    final layer = row.layer;
    final lane = row.lane;
    if (lane != null) {
      final keys = withRuns
          ? (lane.keyedFrames.toList()..sort())
          : const <int>[];
      return FlipHudRow(
        name: lane.label,
        kind: layer.kind,
        isLane: true,
        // A key row has no cels, so it prints no timesheet X — the same
        // reason the cells painter withholds one there.
        holdsDrawings: false,
        runs: [
          for (final frame in keys)
            FlipHudRun(
              startIndex: frame,
              length: 1,
              isKey: true,
              holdKey: lane.holdOutFrames.contains(frame),
            ),
        ],
      );
    }
    final runs = <FlipHudRun>[];
    if (withRuns) {
      for (final entry in layer.timeline.entries) {
        final exposure = entry.value;
        // Ghosts are derived edges, not authored blocks — the run-label
        // painter leaves them out for the same reason.
        if (!exposure.isDrawing || exposure.ghost) {
          continue;
        }
        runs.add(
          FlipHudRun(
            startIndex: entry.key,
            length: exposure.length ?? 1,
            label: session.frameNameForLayer(layer, entry.key) ?? '',
          ),
        );
      }
      runs.sort((a, b) => a.startIndex.compareTo(b.startIndex));
    }
    return FlipHudRow(
      name: layer.name,
      kind: layer.kind,
      runs: runs,
      // The cells painter's own rule for the X: only rows that hold
      // drawings print one, and SE columns stay blank between entries.
      holdsDrawings:
          layerKindHoldsDrawings(layer.kind) &&
          !layerKindUsesSeSheetCells(layer.kind),
    );
  }

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
    switch (target) {
      case null:
        return;
      case LayerRowAddress(:final layerId):
        session.selectLayer(layerId);
      case LaneRowAddress(:final layerId):
        // Landing on a property makes its OWNER the active layer — "현재
        // 위치한 레이어를 액티브레이어로" — so moving onto layer B's
        // Position row moves the drawing target to B, and drawing keeps
        // working while the property is the verb's subject.
        session.selectLayer(layerId);
        session.selectRow(target);
      case TrackRowAddress():
        return;
    }
  }

  /// Window > Reset Workspace Layout: back to the factory docks, extents
  /// and locks (the debounced save persists the reset like any edit).
  void _resetWorkspaceLayout() {
    setState(() {
      _lockedTabIds = {EditorWorkspace.canvasTabId};
    });
    for (final extent in _railExtents.values) {
      extent.reset();
    }
    _mutatingLayout(() {
      _layout.restore(docks: _defaultDocks());
    });
  }

  /// Every known panel in default-dock order, with its live visibility.
  List<WorkspacePanelEntry> _panelMenuEntries() => [
    for (final sections in _defaultDocks().values)
      for (final section in sections)
        for (final tabId in section.tabs)
          (
            tabId: tabId,
            label: _tabFor(tabId).label,
            visible: _layout.locateTab(tabId) != null,
          ),
  ];

  String _defaultDockOf(String tabId) {
    for (final entry in _defaultDocks().entries) {
      for (final section in entry.value) {
        if (section.tabs.contains(tabId)) {
          return entry.key;
        }
      }
    }
    return EditorWorkspace.leftGroupId;
  }

  void _closeTab(String tabId) {
    _mutatingLayout(() => _layout.removeTab(tabId));
  }

  void _togglePanelVisibility(String tabId) {
    if (_layout.locateTab(tabId) != null) {
      _closeTab(tabId);
    } else {
      _mutatingLayout(() {
        _layout.addTab(tabId, toDockId: _defaultDockOf(tabId));
      });
    }
  }

  /// The COMMON "open or locate" entry (UI-R17 #5): hidden panels open
  /// into their default dock; an already-open panel fronts its tab and
  /// FLASHES so the user sees where it lives. Every non-Window "open
  /// panel" affordance should route here.
  /// A browser "open" (double-click or the row menu): point the viewer at
  /// the asset and reveal its panel — the common reveal verb, so an
  /// already-open viewer fronts and flashes instead of duplicating.
  void _openAssetInViewer(MediaAsset asset) {
    _mediaViewerRequest.value = MediaViewerRequest(
      path: asset.path,
      kind: asset.kind,
      name: asset.name,
    );
    _revealPanel(EditorWorkspace.mediaViewerTabId);
  }

  void _revealPanel(String tabId) {
    final location = _layout.locateTab(tabId);
    if (location == null) {
      _mutatingLayout(() {
        _layout.addTab(tabId, toDockId: _defaultDockOf(tabId));
      });
      return;
    }
    _mutatingLayout(() {
      _layout.selectTab(location.dockId, location.sectionIndex, tabId);
    });
    _panelFlash.flash(tabId);
  }

  Future<void> _restoreLayout() async {
    final store = _layoutStore;
    if (store == null) {
      return;
    }
    final payload = await store.load();
    if (payload == null || !mounted) {
      return;
    }
    final restored = restoreWorkspaceLayout(
      payload: payload,
      defaults: _defaultDocks(),
    );
    if (restored == null || !mounted) {
      return;
    }
    setState(() {
      _lockedTabIds = restored.lockedTabIds;
      _layout.restore(docks: restored.docks, dockExtents: restored.dockExtents);
    });
    for (final entry in _railExtents.entries) {
      entry.value.value = restored.railExtents[entry.key];
    }
  }

  /// Debounced fire-and-forget save: layout changes come in bursts (drags,
  /// splitter moves) and persistence must never block or crash the editor.
  void _scheduleLayoutSave() {
    final store = _layoutStore;
    if (store == null) {
      return;
    }
    _layoutSaveTimer?.cancel();
    _layoutSaveTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(
        store
            .save({
              'layout': _layout.toJson(),
              'lockedTabs': _lockedTabIds.toList(),
              // Closed panels stay closed across restarts (restore only
              // returns tabs missing WITHOUT this marker to their docks —
              // i.e. panels added by an update).
              'hiddenTabs': [
                for (final entry in _panelMenuEntries())
                  if (!entry.visible) entry.tabId,
              ],
              // A rail the user never dragged stays ABSENT rather than
              // saving its current natural size — otherwise a later
              // column change would be pinned to yesterday's geometry.
              'railExtents': {
                for (final entry in _railExtents.entries)
                  if (entry.value.value != null) entry.key: entry.value.value,
              },
            })
            .catchError((Object _) {}),
      );
    });
  }

  @override
  void dispose() {
    _brushTool.removeListener(_rememberSelectionVariant);
    widget.session.historyManager.removeListener(_recordRecentColor);
    _colorPalette.dispose();
    _storyboardThumbnails.dispose();
    _presetLibrary.dispose();
    _tipLibrary.dispose();
    // An injected tool notifier belongs to the shell; only a local
    // fallback is ours to dispose.
    if (widget.brushTool == null) {
      _brushTool.dispose();
    }
    _fillOptions.dispose();
    _transformResampleMode.dispose();
    _eyedropperSource.dispose();
    _colorWheelBackground.dispose();
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
    _panelFlash.dispose();
    _timesheetContinuous.dispose();
    _timesheetPage.dispose();
    _timesheetViewport.dispose();
    _timesheetInkEnabled.dispose();
    _timesheetInk.dispose();
    _conteViewport.dispose();
    _conteInkEnabled.dispose();
    _conteInk.dispose();
    _mediaViewerRequest.dispose();
    _mediaViewerViewport.dispose();
    _draggingTab.dispose();
    widget.layerNav?.unbind();
    widget.flipHud?.unbind();
    widget.panelsMenu?.detach();
    _layoutSaveTimer?.cancel();
    _layout.removeListener(_scheduleLayoutSave);
    for (final extent in _railExtents.values) {
      extent
        ..removeListener(_scheduleLayoutSave)
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
  Future<ui.Image?> _renderStoryboardThumbnail(Cut cut, int frameIndex) {
    const thumbnailWidth = 128;
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
    );
    _activePresetByTool[targetTool] = preset.id;
    _presetLibrary.markActive(preset.id);
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
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importBrushFile() async {
    final message = await _presetLibrary.importFromFile();
    if (message == null || !mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Whether the storyboard tab is the active tab of any section (visible
  /// on screen).
  bool get _isStoryboardVisible =>
      _layout.activeTabs.contains(EditorWorkspace.storyboardTabId);

  /// Runs a layout mutation and clamps the playhead when the storyboard
  /// just came on screen (over-end playheads on non-last cuts must land
  /// back on the counter frame — timeline parity).
  void _mutatingLayout(VoidCallback mutate) {
    final wasVisible = _isStoryboardVisible;
    mutate();
    if (!wasVisible && _isStoryboardVisible) {
      clampPlayheadForStoryboard(widget.session);
    }
  }

  void _toggleTabLock(String tabId) {
    setState(() {
      if (!_lockedTabIds.remove(tabId)) {
        _lockedTabIds.add(tabId);
      }
    });
    _scheduleLayoutSave();
  }

  EditorPanelTab _tabFor(String tabId) {
    final locked = _lockedTabIds.contains(tabId);
    switch (tabId) {
      case EditorWorkspace.toolsTabId:
        return EditorPanelTab(
          id: tabId,
          label: 'Tools',
          icon: Icons.handyman_outlined,
          locked: locked,
          // Sliced (R18 UI-1): only an actual TOOL change reshapes this
          // panel — color/size/knob tweaks must not rebuild it.
          builder: (context) =>
              SlicedValueListenableBuilder<BrushToolState, CanvasTool>(
                valueListenable: _brushTool,
                slice: (state) => state.tool,
                builder: (context, toolState) => ToolsPanel(
                  tool: toolState.tool,
                  selectionVariant: _lastSelectionVariant,
                  onToolChanged: (tool) =>
                      _brushTool.value = _brushTool.value.copyWith(tool: tool),
                  // R9 #14: the selected colour rides the tool rail and
                  // opens the 「컬러 버튼창」. Its own listeners, so a
                  // colour change repaints the swatch without rebuilding
                  // the tool column above it.
                  colorButton:
                      SlicedValueListenableBuilder<BrushToolState, int>(
                        valueListenable: _brushTool,
                        slice: (state) => state.color,
                        builder: (context, colorState) =>
                            ValueListenableBuilder<int>(
                              valueListenable: _colorWheelBackground,
                              builder: (context, background, _) =>
                                  ValueListenableBuilder<ColorPaletteState>(
                                    valueListenable: _colorPalette,
                                    builder: (context, palette, _) =>
                                        SelectedColorButton(
                                          color: colorState.color,
                                          backgroundColor: background,
                                          palette: palette,
                                          onColorChanged: (color) =>
                                              _brushTool.value = _brushTool
                                                  .value
                                                  .copyWith(color: color),
                                          onBackgroundColorChanged: (color) =>
                                              _colorWheelBackground.value =
                                                  color,
                                          onPaletteChanged: _setColorPalette,
                                        ),
                                  ),
                            ),
                      ),
                ),
              ),
        );
      case EditorWorkspace.canvasTabId:
        return EditorPanelTab(
          id: tabId,
          label: 'Canvas',
          icon: Icons.image_outlined,
          locked: locked,
          keepAlive: true,
          builder: (context) => EditorCanvasArea(
            key: _canvasAreaKey,
            onInvokeAction: widget.onInvokeAction,
            session: widget.session,
            brushToolState: _brushTool,
            onBrushToolStateChanged: (state) => _brushTool.value = state,
            canvasViewCommands: widget.canvasViewCommands,
            canvasSelectionCommands: widget.canvasSelectionCommands,
            cameraViewEnabled: _cameraViewEnabled,
            cameraDimOpacity: _cameraDimOpacity,
            expandedLaneLayerIds: _expandedLaneLayerIds,
            fillOptions: _fillOptions,
            selectionMaskOptions: _selectionMaskOptions,
            transformResampleMode: _transformResampleMode,
            eyedropperSource: _eyedropperSource,
            flipHud: widget.flipHud,
          ),
        );
      case EditorWorkspace.brushesTabId:
        // The TOOL LIBRARY (R11-④, CSP sub-tool palette): content follows
        // the active tool — painting tools get the preset library (each
        // remembers its own selection), selection tools their variants.
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelToolLibrary,
          icon: Icons.brush_outlined,
          locked: locked,
          // Sliced (R18 UI-1) + per-tool keep-alive (R18 UI-4): the
          // library follows the active tool and that tool's remembered
          // preset — nothing else — and switching back to a tool whose
          // preset didn't change is a pure index flip (the preset grid
          // was the other half of the per-switch rebuild cost).
          builder: (context) =>
              SlicedValueListenableBuilder<
                BrushToolState,
                (CanvasTool, BrushPresetId?)
              >(
                valueListenable: _brushTool,
                slice: (state) => (state.tool, _activePresetByTool[state.tool]),
                builder: (context, toolState) =>
                    KeyedKeepAliveStack<CanvasTool, BrushPresetId?>(
                      keys: CanvasTool.values,
                      activeKey: toolState.tool,
                      stateOf: () => _activePresetByTool[toolState.tool],
                      builder: (context) => ToolLibraryPanel(
                        tool: toolState.tool,
                        onToolChanged: (tool) => _brushTool.value = _brushTool
                            .value
                            .copyWith(tool: tool),
                        brushLibrary: ListenableBuilder(
                          listenable: _presetLibrary,
                          builder: (context, _) => BrushPresetPanel(
                            presets: _presetLibrary.presets,
                            groups: _presetLibrary.groups,
                            selectedPresetId:
                                _activePresetByTool[toolState.tool],
                            onPresetApplied: _applyPreset,
                            onPresetSaveRequested: () {
                              _presetLibrary.saveCurrent(
                                _brushTool.value.toBrushSettings(),
                                // A saved variant lands beside the brush it
                                // came from rather than at the far end of
                                // the list.
                                groupId: _activePresetGroupId(toolState.tool),
                              );
                            },
                            onPresetDeleted: _presetLibrary.delete,
                            onPresetRenamed: _presetLibrary.rename,
                            onPresetsReordered: _presetLibrary.reorder,
                            onPresetImportRequested: () {
                              unawaited(_importBrushFile());
                            },
                            onGroupCreated: _presetLibrary.createGroup,
                            onGroupEdited: _presetLibrary.editGroup,
                            onGroupDeleted: _presetLibrary.deleteGroup,
                            onGroupsReordered: _presetLibrary.reorderGroups,
                            onLibraryReset: _presetLibrary.resetToDefaults,
                          ),
                        ),
                      ),
                    ),
              ),
        );
      case EditorWorkspace.brushSettingsTabId:
        // TOOL SETTINGS (R11-④, CSP tool property palette): the active
        // tool's detailed knobs.
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelToolSettings,
          icon: Icons.tune,
          locked: locked,
          // Per-tool keep-alive (R18 UI-4): switching back to a tool whose
          // settings didn't change is a pure index flip — the frozen-panel
          // experiment showed these per-switch rebuilds were the bulk of
          // the tool-switch jank. Each tool's panel also keeps its own
          // scroll position, CSP-style.
          builder: (context) => ValueListenableBuilder<BrushToolState>(
            valueListenable: _brushTool,
            builder: (context, toolState, _) =>
                ValueListenableBuilder<FloodFillOptions>(
                  valueListenable: _fillOptions,
                  builder: (context, fillOptions, _) =>
                      KeyedKeepAliveStack<
                        CanvasTool,
                        (BrushToolState, FloodFillOptions)
                      >(
                        keys: CanvasTool.values,
                        activeKey: toolState.tool,
                        stateOf: () => (toolState, fillOptions),
                        // The inner listenables SUBSCRIBE for themselves,
                        // which is why they need not appear in the
                        // keep-alive tuple above: that tuple decides when
                        // the kept-alive subtree is thrown away, not when
                        // it rebuilds.
                        builder: (context) => ValueListenableBuilder<ResampleMode>(
                          valueListenable: _transformResampleMode,
                          builder: (context, resampleMode, _) =>
                              ValueListenableBuilder<SelectionMaskOptions>(
                                valueListenable: _selectionMaskOptions,
                                builder: (context, maskOptions, _) =>
                                    ValueListenableBuilder<
                                      CanvasColorSampleSource
                                    >(
                                      valueListenable: _eyedropperSource,
                                      // The tip library loads in two passes,
                                      // so the pickers have to follow it.
                                      builder: (context, eyedropperSource, _) =>
                                          ListenableBuilder(
                                            listenable: _tipLibrary,
                                            builder: (context, _) =>
                                                ToolSettingsPanel(
                                                  state: toolState,
                                                  onChanged: (state) =>
                                                      _brushTool.value = state,
                                                  tips: _tipLibrary.tips,
                                                  onTipImportRequested: () {
                                                    unawaited(
                                                      _importTipImage(),
                                                    );
                                                  },
                                                  fillOptions: fillOptions,
                                                  onFillOptionsChanged:
                                                      (options) =>
                                                          _fillOptions.value =
                                                              options,
                                                  eyedropperSource:
                                                      eyedropperSource,
                                                  onEyedropperSourceChanged:
                                                      (source) =>
                                                          _eyedropperSource
                                                                  .value =
                                                              source,
                                                  selectionMaskOptions:
                                                      maskOptions,
                                                  onSelectionMaskOptionsChanged:
                                                      (options) =>
                                                          _selectionMaskOptions
                                                                  .value =
                                                              options,
                                                  transformResampleMode:
                                                      resampleMode,
                                                  onTransformResampleModeChanged:
                                                      (mode) =>
                                                          _transformResampleMode
                                                                  .value =
                                                              mode,
                                                  selectionCommands: widget
                                                      .canvasSelectionCommands,
                                                  language: widget
                                                      .session
                                                      .languageSettings
                                                      .value
                                                      .programLanguage,
                                                ),
                                          ),
                                    ),
                              ),
                        ),
                      ),
                ),
          ),
        );
      // R9 #14: there is no Color TAB. The wheel and the palette are the
      // two tabs of the 「컬러 버튼창」, opened from the tool rail's
      // selected-colour swatch. A saved layout still naming this id drops
      // it on restore — the store validates against the current defaults.
      case EditorWorkspace.onionSkinTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelOnionSkin,
          icon: Icons.layers_outlined,
          locked: locked,
          builder: (context) => ValueListenableBuilder<OnionSkinSettings>(
            valueListenable: widget.session.onionSkinSettings,
            builder: (context, settings, _) => OnionSkinPanel(
              settings: settings,
              onChanged: (next) =>
                  widget.session.onionSkinSettings.value = next,
            ),
          ),
        );
      case EditorWorkspace.mediaTabId:
        return EditorPanelTab(
          id: tabId,
          label: 'Media',
          icon: Icons.library_music_outlined,
          locked: locked,
          builder: (context) => ListenableBuilder(
            listenable: widget.session,
            builder: (context, _) => MediaBrowserPanel(
              assets: widget.session.mediaAssets,
              isAssetReferenced: widget.session.isMediaAssetReferenced,
              onImportPaths: widget.session.importMediaFiles,
              onRenameAsset: widget.session.renameMediaAsset,
              onRelinkAsset: widget.session.relinkMediaAsset,
              onRemoveAsset: widget.session.removeMediaAsset,
              onOpenAsset: _openAssetInViewer,
            ),
          ),
        );
      case EditorWorkspace.mediaViewerTabId:
        return EditorPanelTab(
          id: tabId,
          label: AppText.strings.panelMediaViewer,
          icon: Icons.preview_outlined,
          locked: locked,
          // Keeps its decoded pages/PDF document across tab switches.
          keepAlive: true,
          builder: (context) => PanelAwareListenableBuilder(
            // The request is the HOST's own subscription; only the
            // viewport value and the locale chrome rebuild from here.
            listenable: Listenable.merge([
              _mediaViewerViewport,
              widget.session.languageSettings,
            ]),
            builder: (context) => MediaViewerTabHost(
              session: widget.session,
              request: _mediaViewerRequest,
              viewport: _mediaViewerViewport.value,
              onViewportChanged: (viewport) {
                _mediaViewerViewport.value = viewport;
              },
            ),
          ),
        );
      case EditorWorkspace.timelineTabId:
        return EditorPanelTab(
          id: tabId,
          label: 'Timeline',
          icon: Icons.view_timeline_outlined,
          // The legacy mode-toggle keys stay on the tab buttons so every
          // existing flow (and test helper) keeps working.
          buttonKey: const ValueKey<String>('timeline-mode-timeline-button'),
          minContentWidth: EditorWorkspace._frameAxisMinContentWidth,
          minContentHeight: EditorWorkspace._minContentHeightFor(tabId),
          locked: locked,
          // The heavy frame-axis panels keep their subtree offstage
          // across switches (R10-②) — switching back is instant.
          keepAlive: true,
          builder: (context) => PanelAwareListenableBuilder(
            // The session subscription lives HERE now (HomePage no longer
            // setStates the world). Seeks are NOT session notifies — the
            // grids ride the frame cursor and never rebuild for them.
            // Panel-aware (R12-①): notifies arriving while the tab sits
            // offstage are deferred to one catch-up on re-activation.
            listenable: Listenable.merge([
              widget.session,
              _timelineOrientation,
              // Zoom (_timelinePixelsPerFrame) is NOT merged here (UI-R6
              // #4): the host scopes it to the panel subtree, so a zoom
              // step skips this whole tab rebuild.
              _showSecondsDisplay,
              _expandedLaneLayerIds,
              _expandedLaneGroupKeys,
              _hiddenTimelineSections,
              _collapsedAttachBaseIds,
              _timelineRowFilter,
            ]),
            builder: (context) => TimelineTabHost(
              session: widget.session,
              orientation: _timelineOrientation.value,
              onOrientationChanged: (orientation) {
                _timelineOrientation.value = orientation;
              },
              pixelsPerFrame: _timelinePixelsPerFrame.value,
              pixelsPerFrameListenable: _timelinePixelsPerFrame,
              onPixelsPerFrameChanged: (value) {
                _timelinePixelsPerFrame.value = value;
              },
              showSeconds: _showSecondsDisplay.value,
              onShowSecondsChanged: (show) {
                _showSecondsDisplay.value = show;
              },
              timelineRailExtent: _railExtents[LayerRailId.timeline],
              xsheetRailExtent: _railExtents[LayerRailId.xsheet],
              expandedLaneLayerIds: _expandedLaneLayerIds.value,
              onToggleLayerLanes: _toggleLayerLanes,
              expandedLaneGroupKeys: _expandedLaneGroupKeys.value,
              onToggleLaneGroupKey: _toggleLaneGroup,
              hiddenSections: _hiddenTimelineSections.value,
              onToggleSection: _toggleTimelineSection,
              rowFilter: _timelineRowFilter.value,
              onSetRowFilter: _setTimelineRowFilter,
              collapsedAttachBaseIds: _collapsedAttachBaseIds.value,
              onToggleAttachGroup: _toggleAttachGroup,
              // Unified layer controls: the camera row's visibility/opacity
              // drive the same camera-view state as the canvas overlay and
              // the camera panel.
              cameraViewEnabled: _cameraViewEnabled,
              cameraDimOpacity: _cameraDimOpacity,
              // The legend's "open onion panel" (UI-R17 #5): already open
              // = the panel flashes in place (the common reveal logic).
              onRevealOnionSkinPanel: () =>
                  _revealPanel(EditorWorkspace.onionSkinTabId),
            ),
          ),
        );
      case EditorWorkspace.storyboardTabId:
        return EditorPanelTab(
          id: tabId,
          label: 'Storyboard',
          icon: Icons.movie_outlined,
          buttonKey: const ValueKey<String>('timeline-mode-storyboard-button'),
          minContentWidth: EditorWorkspace._frameAxisMinContentWidth,
          minContentHeight: EditorWorkspace._minContentHeightFor(tabId),
          locked: locked,
          keepAlive: true,
          builder: (context) => PanelAwareListenableBuilder(
            // Session subscription (see the timeline tab) + COMMITTED
            // seeks only (W4 perf pass): scrub moves and playback ticks
            // ride the host's playhead notifier straight into the panel's
            // playhead overlay + ruler — the panel never rebuilds per
            // tick anymore. Panel-aware (R12-①): offstage notifies defer
            // to one catch-up on re-activation.
            listenable: Listenable.merge([
              widget.session,
              widget.session.frameSeekCommitted,
              _storyboardPixelsPerFrame,
              _storyboardTrackLaneHeight,
              _showSecondsDisplay,
              _storyboardThumbnails,
            ]),
            builder: (context) => StoryboardTabHost(
              session: widget.session,
              pixelsPerFrame: _storyboardPixelsPerFrame.value,
              onPixelsPerFrameChanged: (value) {
                _storyboardPixelsPerFrame.value = value;
              },
              showSeconds: _showSecondsDisplay.value,
              onShowSecondsChanged: (show) {
                _showSecondsDisplay.value = show;
              },
              railExtent: _railExtents[LayerRailId.storyboard],
              trackLaneHeight: _storyboardTrackLaneHeight.value,
              onTrackLaneHeightChanged: (value) {
                _storyboardTrackLaneHeight.value = value;
              },
              thumbnailFor: _storyboardThumbnails.thumbnailFor,
              // R28 #1: the same camera-view state the timeline command
              // bar and the canvas overlay drive — one notifier, three
              // entrances.
              cameraViewEnabled: _cameraViewEnabled,
            ),
          ),
        );
      case EditorWorkspace.conteTabId:
        return EditorPanelTab(
          id: tabId,
          label: 'Conte',
          icon: Icons.grid_on_outlined,
          buttonKey: const ValueKey<String>('timeline-mode-conte-button'),
          minContentWidth: EditorWorkspace._frameAxisMinContentWidth,
          minContentHeight: EditorWorkspace._minContentHeightFor(tabId),
          locked: locked,
          keepAlive: true,
          // The sheet reads the project and the SAME picture store the
          // storyboard strip draws from, so a cell and its strip panel are
          // one render rather than two that must be kept in step.
          // _brushTool is deliberately NOT merged (R18 UI-3): only the
          // ink overlay consumes it, through its own boundary builder.
          builder: (context) => PanelAwareListenableBuilder(
            listenable: Listenable.merge([
              widget.session,
              _storyboardThumbnails,
              _conteViewport,
              _conteInkEnabled,
              _conteInk,
              // The locale reprints the sheet chrome (labels/tooltips).
              widget.session.languageSettings,
            ]),
            builder: (context) => ConteTabHost(
              session: widget.session,
              thumbnailFor: _storyboardThumbnails.thumbnailFor,
              // A landed thumbnail render repaints the page painter
              // directly (its compared fields don't change for async
              // pictures).
              thumbnailRepaint: _storyboardThumbnails,
              viewport: _conteViewport.value,
              onViewportChanged: (viewport) {
                _conteViewport.value = viewport;
              },
              inkController: _conteInk,
              brushToolState: _brushTool,
              inkEnabled: _conteInkEnabled.value,
              onInkEnabledChanged: (enabled) {
                _conteInkEnabled.value = enabled;
              },
            ),
          ),
        );
      case EditorWorkspace.timesheetTabId:
        return EditorPanelTab(
          id: tabId,
          label: 'Timesheet',
          icon: Icons.table_chart_outlined,
          locked: locked,
          keepAlive: true,
          builder: (context) => PanelAwareListenableBuilder(
            // _brushTool is deliberately NOT merged here (R18 UI-3): the
            // sheet layout never depends on it, and rebuilding the whole
            // (keep-alive, often hidden) B4 document on every tool
            // switch / color notch was measurably half the tool-switch
            // jank. Only the ink overlay consumes the tool state, through
            // its own boundary builder inside the host.
            listenable: Listenable.merge([
              _timesheetContinuous,
              _timesheetPage,
              _timesheetViewport,
              _timesheetInkEnabled,
              // The notation language reprints the sheet (UI-R10 #7).
              widget.session.languageSettings,
            ]),
            builder: (context) => TimesheetTabHost(
              session: widget.session,
              continuous: _timesheetContinuous.value,
              onContinuousChanged: (continuous) {
                _timesheetContinuous.value = continuous;
              },
              page: _timesheetPage.value,
              onPageChanged: (page) {
                _timesheetPage.value = page;
              },
              viewport: _timesheetViewport.value,
              onViewportChanged: (viewport) {
                _timesheetViewport.value = viewport;
              },
              inkController: _timesheetInk,
              brushToolState: _brushTool,
              inkEnabled: _timesheetInkEnabled.value,
              onInkEnabledChanged: (enabled) {
                _timesheetInkEnabled.value = enabled;
              },
            ),
          ),
        );
      default:
        throw ArgumentError.value(tabId, 'tabId', 'Unknown panel tab');
    }
  }

  bool _canDockAccept(String dockId, EditorPanelTabDragData data) {
    // The slim edge docks only host narrow-fit panels (the tool bar);
    // everything else docks anywhere.
    if ((dockId == EditorWorkspace.toolLeftGroupId ||
            dockId == EditorWorkspace.toolRightGroupId) &&
        !_EditorWorkspaceState._edgeDockTabIds.contains(data.tabId)) {
      return false;
    }
    return _layout.canMoveTab(tabId: data.tabId, toDockId: dockId);
  }

  /// A dock's stacked sections with the PS/AE-style drop feedback.
  Widget _buildDockHost(String dockId, {bool compact = false}) {
    return EditorDockHost(
      layout: _layout,
      dockId: dockId,
      tabResolver: _tabFor,
      draggingTab: _draggingTab,
      compact: compact,
      canAcceptTab: (data) => _canDockAccept(dockId, data),
      onTabSelected: (sectionIndex, tabId) => _mutatingLayout(() {
        _layout.selectTab(dockId, sectionIndex, tabId);
      }),
      onTabMovedToSection: (data, sectionIndex, insertIndex) =>
          _mutatingLayout(() {
            _layout.moveTabToSection(
              tabId: data.tabId,
              toDockId: dockId,
              toSectionIndex: sectionIndex,
              insertIndex: insertIndex,
            );
          }),
      onTabMovedToNewSection: (data, atSectionIndex) => _mutatingLayout(() {
        _layout.moveTabToNewSection(
          tabId: data.tabId,
          toDockId: dockId,
          atSectionIndex: atSectionIndex,
        );
      }),
      onTabDragChanged: (data) => _draggingTab.value = data,
      onToggleLock: _toggleTabLock,
      onCloseTab: _closeTab,
      flash: _panelFlash,
    );
  }

  void _dropIntoEmptyDock(String dockId, EditorPanelTabDragData data) {
    _mutatingLayout(() {
      _layout.moveTabToNewSection(
        tabId: data.tabId,
        toDockId: dockId,
        atSectionIndex: 0,
      );
    });
  }

  EditorDockDropZone _emptyDockZone(
    String dockId,
    Axis axis, {
    bool expandToFill = false,
  }) {
    return EditorDockDropZone(
      dockId: dockId,
      axis: axis,
      draggingTab: _draggingTab,
      canAcceptTab: (data) => _canDockAccept(dockId, data),
      expandToFill: expandToFill,
      onDropped: (data) => _dropIntoEmptyDock(dockId, data),
    );
  }

  /// A slim edge dock homing the vertical tool bar on either workspace
  /// edge (left-handed choice); collapsed when empty.
  Widget _buildEdgeDock(String dockId, EditorPanelDockSide side) {
    if (_layout.sectionsIn(dockId).isEmpty) {
      return _emptyDockZone(dockId, Axis.vertical);
    }
    return EditorPanelDock.filled(
      side: side,
      width: ToolsPanel.dockWidth,
      dockId: dockId,
      child: _buildDockHost(dockId, compact: true),
    );
  }

  /// A side dock: full tab dock when populated, collapsed otherwise (a
  /// glowing drop rail appears while an eligible tab is in flight).
  /// [width] is the extent AFTER the workspace clamped both side docks to
  /// what the window can actually spare.
  Widget _buildSideDock(
    String dockId,
    EditorPanelDockSide side, {
    required double width,
  }) {
    if (_layout.sectionsIn(dockId).isEmpty) {
      return _emptyDockZone(dockId, Axis.vertical);
    }
    return EditorPanelDock.filled(
      side: side,
      width: width,
      // Panel names stay visible in every dock (the strip scrolls when
      // they overflow); only the slim edge docks go icon-only.
      child: _buildDockHost(dockId),
    );
  }

  /// What a dock stacked along the VERTICAL axis needs before its panels
  /// start losing rows: every section's tab strip plus the tallest floor
  /// among that section's tabs, and the splitters between sections.
  ///
  /// The tallest among ALL of a section's tabs, not the active one: a dock
  /// that shrinks while the conte is up and clips the moment you switch
  /// back to the timeline is the same bug wearing a different hat.
  double _verticalDockMinimumExtent(String dockId) {
    final sections = _layout.sectionsIn(dockId);
    if (sections.isEmpty) {
      return 0;
    }
    var total = (sections.length - 1) * DockEdgeSplitter.thickness;
    for (final section in sections) {
      var floor = 0.0;
      for (final tabId in section.tabs) {
        floor = math.max(
          floor,
          EditorWorkspace._minContentHeightFor(tabId) ?? 0,
        );
      }
      total += EditorPanelTabs.stripHeight + floor;
    }
    return total;
  }

  Widget _buildBottomDock() {
    if (_layout.sectionsIn(EditorWorkspace.bottomGroupId).isEmpty) {
      return _emptyDockZone(EditorWorkspace.bottomGroupId, Axis.horizontal);
    }
    return SizedBox(
      // Clamped on the way OUT as well as on the drag: a workspace saved
      // before this floor existed, or one whose bottom dock gained a
      // taller tab since, must still open at a height its panels fit in.
      height: math.max(
        _layout.dockExtent(
          EditorWorkspace.bottomGroupId,
          fallback: EditorWorkspace.bottomPanelHeight,
        ),
        _verticalDockMinimumExtent(EditorWorkspace.bottomGroupId),
      ),
      child: _buildDockHost(EditorWorkspace.bottomGroupId),
    );
  }

  /// The center dock hosts the canvas tab by default. Unlike the edge
  /// docks it always occupies its region — when emptied it stays a
  /// full-size drop surface.
  Widget _buildCenterDock() {
    if (_layout.sectionsIn(EditorWorkspace.centerGroupId).isEmpty) {
      return _emptyDockZone(
        EditorWorkspace.centerGroupId,
        Axis.vertical,
        expandToFill: true,
      );
    }
    return _buildDockHost(EditorWorkspace.centerGroupId);
  }

  /// OS drag-and-drop (§6-i, confirmed): wherever the drop lands, the
  /// import/placement window opens with the dropped paths — never an
  /// instant import. Folders drop too (the cut-folder parser's entrance).
  void _onOsFilesDropped(DropDoneDetails details) {
    final paths = [for (final file in details.files) file.path];
    if (paths.isEmpty) {
      return;
    }
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) =>
            ImportDialog(session: widget.session, initialPaths: paths),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: _onOsFilesDropped,
      child: _buildWorkspace(context),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return ListenableBuilder(
      listenable: _layout,
      builder: (context, _) {
        final hasLeftDock = _layout
            .sectionsIn(EditorWorkspace.leftGroupId)
            .isNotEmpty;
        final hasRightDock = _layout
            .sectionsIn(EditorWorkspace.rightGroupId)
            .isNotEmpty;
        final hasBottomDock = _layout
            .sectionsIn(EditorWorkspace.bottomGroupId)
            .isNotEmpty;
        return Row(
          children: [
            // The edge docks span the FULL workspace height; the bottom
            // dock runs between them.
            _buildEdgeDock(
              EditorWorkspace.toolLeftGroupId,
              EditorPanelDockSide.left,
            ),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // The side docks keep their saved extents but may
                        // never squeeze the canvas out: scale both down
                        // proportionally when the window can't fit them.
                        const minCenterWidth = 120.0;
                        var leftWidth = hasLeftDock
                            ? _layout.dockExtent(
                                EditorWorkspace.leftGroupId,
                                fallback: EditorWorkspace.sideDockWidth,
                              )
                            : 0.0;
                        var rightWidth = hasRightDock
                            ? _layout.dockExtent(
                                EditorWorkspace.rightGroupId,
                                fallback: EditorWorkspace.sideDockWidth,
                              )
                            : 0.0;
                        final splitters =
                            (hasLeftDock ? DockEdgeSplitter.thickness : 0) +
                            (hasRightDock ? DockEdgeSplitter.thickness : 0);
                        final room =
                            (constraints.maxWidth - splitters - minCenterWidth)
                                .clamp(0.0, double.infinity);
                        final wanted = leftWidth + rightWidth;
                        if (wanted > room && wanted > 0) {
                          final scale = room / wanted;
                          leftWidth *= scale;
                          rightWidth *= scale;
                        }
                        return Row(
                          children: [
                            _buildSideDock(
                              EditorWorkspace.leftGroupId,
                              EditorPanelDockSide.left,
                              width: leftWidth,
                            ),
                            if (hasLeftDock)
                              DockEdgeSplitter(
                                key: const ValueKey<String>('dock-resize-left'),
                                axis: Axis.vertical,
                                onDragDelta: (delta) => _layout.resizeDock(
                                  EditorWorkspace.leftGroupId,
                                  delta,
                                  fallback: EditorWorkspace.sideDockWidth,
                                ),
                              ),
                            Expanded(child: _buildCenterDock()),
                            if (hasRightDock)
                              DockEdgeSplitter(
                                key: const ValueKey<String>(
                                  'dock-resize-right',
                                ),
                                axis: Axis.vertical,
                                onDragDelta: (delta) => _layout.resizeDock(
                                  EditorWorkspace.rightGroupId,
                                  -delta,
                                  fallback: EditorWorkspace.sideDockWidth,
                                ),
                              ),
                            _buildSideDock(
                              EditorWorkspace.rightGroupId,
                              EditorPanelDockSide.right,
                              width: rightWidth,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (hasBottomDock)
                    DockEdgeSplitter(
                      key: const ValueKey<String>('dock-resize-bottom'),
                      axis: Axis.horizontal,
                      onDragDelta: (delta) => _layout.resizeDock(
                        EditorWorkspace.bottomGroupId,
                        -delta,
                        fallback: EditorWorkspace.bottomPanelHeight,
                        // The splitter stops where the panels stop
                        // shrinking. Without this the drag runs on past
                        // the floor and the tab shell's scroller — kept
                        // only as a guard — starts cutting the bottom
                        // rows off, which is the reported bug.
                        minExtent: _verticalDockMinimumExtent(
                          EditorWorkspace.bottomGroupId,
                        ),
                      ),
                    ),
                  _buildBottomDock(),
                ],
              ),
            ),
            _buildEdgeDock(
              EditorWorkspace.toolRightGroupId,
              EditorPanelDockSide.right,
            ),
          ],
        );
      },
    );
  }
}
