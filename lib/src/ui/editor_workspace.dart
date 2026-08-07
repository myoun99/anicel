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
import '../services/color_palette_file_service.dart' show ColorPaletteState;
import 'brush/brush_preset_library.dart';
import 'brush/canvas_floor_insets.dart';
import 'color/color_panels.dart' show ColorPickerKind, ColorPickerPanel;
import 'color/color_slot_pair.dart';
import 'theme/app_theme.dart';
import 'brush/brush_preset_panel.dart';
import 'brush/brush_tip_library.dart';
import 'brush/brush_tool_state.dart';
import 'brush/canvas_selection_commands.dart';
import 'brush/canvas_view_commands.dart';
import 'brush/paint_tool_state_notifier.dart';
import 'brush/tool_library_panel.dart';
import 'brush/tool_settings_panel.dart';
import 'brush/tools_panel.dart';
import 'editor_canvas_area.dart';
import 'editor_session_manager.dart';
import 'shortcuts/editor_action_registry.dart';
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
import 'widgets/app_scrollbar.dart';
import 'keyed_keep_alive_stack.dart';
import 'sliced_value_listenable_builder.dart';
import 'conte/conte_fonts.dart';
import 'conte/conte_ink.dart';
import 'conte/conte_tab_host.dart';
import '../models/envelope/cut_envelope_presets.dart';
import 'envelope/cut_envelope_ink.dart';
import 'envelope/cut_envelope_tab_host.dart';
import 'storyboard_cut_thumbnail_store.dart';
import 'storyboard_panel.dart' show StoryboardPanel;
import 'storyboard_playhead_mapping.dart';
import '../models/timeline_row_address.dart';
import 'timeline/layer_rail_window.dart';
import '../models/layer_kind.dart' show LayerKind, layerKindHoldsDrawings;
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
    this.colorBackground,
    this.colorPalette,
    this.onColorPaletteChanged,
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
  static const String cameraTabId = 'camera';
  static const String mediaTabId = 'media';
  static const String timelineTabId = 'timeline';
  static const String storyboardTabId = 'storyboard';
  static const String conteTabId = 'conte';
  static const String envelopeTabId = 'envelope';
  static const String timesheetTabId = 'timesheet';
  static const String mediaViewerTabId = 'media-viewer';

  /// The WIDTH frame-axis panels lay out at when docked somewhere narrower
  /// (their label rails and toolbars assume a wide region); the tab shell
  /// hosts them inside a horizontal scroller then. Unchanged by the
  /// shrink-floor round — in a narrow side dock, scrolling sideways is
  /// genuinely what helps.
  static const double _frameAxisMinContentWidth = 640;

  @override
  State<EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends State<EditorWorkspace> {
  /// The factory-default arrangement (also the validation baseline when a
  /// saved layout is restored: it names every known tab and its home dock).
  ///
  /// 🆕유저 확정 (R3 #10) — ONE PANEL PER BUTTON except where the panels
  /// are the same thing seen differently. The tool strip carries the tool
  /// LIBRARY and, under it, the tool SETTINGS: two buttons, both open, the
  /// two panels a stroke alternates between. The sub-strip carries the
  /// colour swatch, then the three PAPER surfaces of one cut (타임시트 ·
  /// 콘티 · 컷봉투) as one button, then the media browser, then the onion
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
    EditorWorkspace.railGroupId(right: true, slot: 4): DockGroup(
      tabs: [EditorWorkspace.onionSkinTabId],
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
      tabs: [
        EditorWorkspace.timelineTabId,
        EditorWorkspace.storyboardTabId,
      ],
      activeTabId: EditorWorkspace.timelineTabId,
    ),
  };

  /// The panels that may lie on the floor, in the order the top strip's
  /// switch offers them.
  static const List<String> _floorTabIds = [
    EditorWorkspace.canvasTabId,
    EditorWorkspace.mediaViewerTabId,
  ];

  /// Only narrow-fit panels may live in the slim edge docks.
  static const Set<String> _edgeDockTabIds = {EditorWorkspace.toolsTabId};

  /// Which rail groups are OPEN.
  ///
  /// 여러 버튼 동시에 열림 (유저 확정) — this is a set and not a selection,
  /// because the rail is not a tab bar: opening a second group stacks it
  /// under the first and they divide the rail's height. A group with no
  /// panels in it has no button and cannot be opened.
  Set<String> _openRails = _defaultOpenRails();

  static Set<String> _defaultOpenRails() => {
    // The tool library and the tool settings are the pair a stroke
    // alternates between, so both open — they are two buttons now rather
    // than two tabs of one, and only opening one of them would hide the
    // other behind a click that used to cost nothing.
    EditorWorkspace.leftGroupId,
    EditorWorkspace.railGroupId(right: false, slot: 2),
    EditorWorkspace.railGroupId(right: true, slot: 2),
  };

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

  /// The first EMPTY slot of a rail, or null when the pool is full. This is
  /// where a panel dropped on the rail's "new group" target lands.
  String? _emptyRailSlot({required bool right}) {
    for (final id in _railSlotIds(right: right)) {
      if (_layout.tabsIn(id).isEmpty) {
        return id;
      }
    }
    return null;
  }

  void _toggleRailGroup(String railId) {
    setState(() {
      if (!_openRails.remove(railId)) {
        _openRails.add(railId);
      }
    });
    _scheduleLayoutSave();
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
    return ListenableBuilder(
      listenable: Listenable.merge([
        session,
        session.historyManager,
        session.onionSkinLayerIds,
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

  /// Cut-envelope tab view state — the conte's pair, said of the 봉투.
  /// Ink starts BLOCKED here too: the envelope is read (and printed)
  /// before anybody writes on it.
  final ValueNotifier<CanvasViewport?> _envelopeViewport = ValueNotifier(null);
  final ValueNotifier<bool> _envelopeInkEnabled = ValueNotifier(false);

  /// Which bundled 봉투 form the panel prints. Session-scoped for now: the
  /// project-level choice arrives with the form editor, and until there is
  /// a place to store one, remembering it here beats hard-coding it.
  final ValueNotifier<String> _envelopeFormId = ValueNotifier(
    CutEnvelopePresets.analogId,
  );

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

  late final CutEnvelopeInkController _envelopeInk = CutEnvelopeInkController(
    store: widget.session.envelopeInkStore,
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
    // Sizes no longer come through the model's own notifier, but they are
    // still persisted — the save has to hear them separately or a resized
    // dock would come back at its old width.
    _layout.extentRevision.addListener(_scheduleLayoutSave);
    for (final extent in _railExtents.values) {
      extent.addListener(_scheduleLayoutSave);
    }
    widget.panelsMenu?.attach(
      entriesProvider: _panelMenuEntries,
      toggler: _togglePanelVisibility,
      relay: _layout,
      layoutReset: _resetWorkspaceLayout,
      toolRailOnRight: () =>
          _layout.tabsIn(EditorWorkspace.toolRightGroupId).isNotEmpty,
      toolRailMover: _setToolRailOnRight,
      floorTabId: _activeFloorTabId,
      floorTabs: () => [
        for (final tabId in _EditorWorkspaceState._floorTabIds)
          (
            tabId: tabId,
            label: _tabFor(tabId).label,
            icon: _tabFor(tabId).icon,
          ),
      ],
      floorTabSelector: _selectFloorTab,
      regionOnTop: () => _regionOnTop,
      regionMover: (onTop) {
        if (_regionOnTop == onTop) {
          return;
        }
        setState(() => _regionOnTop = onTop);
        _scheduleLayoutSave();
      },
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

  /// 워크스페이스 초기화: EVERYTHING the workspace remembers, back to the
  /// factory arrangement (the debounced save persists the reset like any
  /// other edit).
  ///
  /// It used to reset the docks, the extents and the locks — which is most
  /// of a layout but not a layout. Which rail groups were OPEN, which edge
  /// the strips were on, how far the floating region was inset, whether it
  /// was collapsed and which edge it sat on all survived the reset, so the
  /// button could not get someone out of an arrangement they disliked.
  /// Every field the save writes is reset here; that is the rule, and it is
  /// why the two lists are worth reading side by side.
  void _resetWorkspaceLayout() {
    for (final extent in _railExtents.values) {
      extent.reset();
    }
    setState(() {
      _lockedTabIds = {EditorWorkspace.canvasTabId};
      _openRails = _defaultOpenRails();
      _bottomDockCollapsed = false;
      _regionOnTop = false;
    });
    // Back to "nobody has said", which is the 2/3 default — not to 0,
    // which is now an arrangement rather than the absence of one.
    _bottomInsetOverride.value = null;
    _mutatingLayout(() {
      _layout.restore(docks: _defaultDocks());
    });
  }

  /// Every known panel in default-dock order, with its live visibility.
  List<WorkspacePanelEntry> _panelMenuEntries() => [
    for (final group in _defaultDocks().values)
      for (final tabId in group?.tabs ?? const <String>[])
        (
          tabId: tabId,
          label: _tabFor(tabId).label,
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
      _ensureRailOpen(_defaultDockOf(tabId));
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
      // The two rail WIDTHS are extents that are not docks — they belong to
      // the rail, which every group on it shares. Unnamed here they were
      // dropped on every restore, so a widened rail was narrow again at the
      // next launch.
      extraExtentKeys: {
        EditorWorkspace.railWidthKey(right: false),
        EditorWorkspace.railWidthKey(right: true),
      },
    );
    if (restored == null || !mounted) {
      return;
    }
    final openRails = payload['openRails'];
    setState(() {
      _lockedTabIds = restored.lockedTabIds;
      _bottomDockCollapsed = payload['bottomCollapsed'] == true;
      _regionOnTop = payload['regionOnTop'] == true;
      final savedInset = payload['bottomInset'];
      if (savedInset is num && savedInset.isFinite && savedInset >= 0) {
        _bottomInsetOverride.value = savedInset.toDouble();
      }
      if (openRails is List) {
        // Filtered against the POOL, not taken on trust: a file written by
        // a build with a different pool size would otherwise leave open
        // ids that name nothing.
        final known = {
          ..._railSlotIds(right: false),
          ..._railSlotIds(right: true),
        };
        _openRails = {
          for (final id in openRails)
            if (id is String && known.contains(id)) id,
        };
      }
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
              // NEW keys rather than a new layout version: an older build
              // reading this file simply does not see them, whereas bumping
              // the version makes that build throw the whole arrangement
              // away (there is no migration code, only a version check).
              'bottomCollapsed': _bottomDockCollapsed,
              // ABSENT while the default is in force, the same rule the
              // rail extents follow: writing today's resolved pixels would
              // pin tomorrow's window to this one's width.
              if (_bottomInsetOverride.value != null)
                'bottomInset': _bottomInsetOverride.value,
              'openRails': _openRails.toList(),
              'regionOnTop': _regionOnTop,
            })
            .catchError((Object _) {}),
      );
    });
  }

  @override
  void dispose() {
    _brushTool.removeListener(_rememberSelectionVariant);
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
    _envelopeFormId.dispose();
    _envelopeInk.dispose();
    _mediaViewerRequest.dispose();
    _mediaViewerViewport.dispose();
    _draggingTab.dispose();
    widget.layerNav?.unbind();
    widget.flipHud?.unbind();
    widget.panelsMenu?.detach();
    _layoutSaveTimer?.cancel();
    _layout.removeListener(_scheduleLayoutSave);
    _layout.extentRevision.removeListener(_scheduleLayoutSave);
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

  /// One of the three colour panels. They differ by their picker and by
  /// nothing else — same live colour, same palette, same status bar — so
  /// they are built from one place rather than three that could drift.
  EditorPanelTab _colorTab(
    String tabId, {
    required ColorPickerKind kind,
    required String label,
    required IconData icon,
    required bool locked,
  }) {
    return EditorPanelTab(
      id: tabId,
      label: label,
      icon: icon,
      locked: locked,
      builder: (context) {
        final palette = widget.colorPalette;
        final onPaletteChanged = widget.onColorPaletteChanged;
        if (palette == null || onPaletteChanged == null) {
          return const SizedBox.shrink();
        }
        return SlicedValueListenableBuilder<BrushToolState, int>(
          valueListenable: _brushTool,
          slice: (state) => state.color,
          builder: (context, toolState) =>
              ValueListenableBuilder<ColorPaletteState>(
                valueListenable: palette,
                builder: (context, paletteState, _) => ColorPickerPanel(
                  kind: kind,
                  color: toolState.color,
                  palette: paletteState,
                  onColorChanged: (color) =>
                      _brushTool.value = _brushTool.value.copyWith(
                        color: color,
                      ),
                  onPaletteChanged: onPaletteChanged,
                ),
              ),
        );
      },
    );
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
                  // The between-strokes group. Its own listeners, so undoing
                  // does not rebuild the tool column above it.
                  historyControls: _railHistoryControls(),
                ),
              ),
        );
      case EditorWorkspace.colorWheelTabId:
        return _colorTab(
          tabId,
          kind: ColorPickerKind.wheel,
          label: AppText.strings.panelColorWheel,
          icon: Icons.palette_outlined,
          locked: locked,
        );
      case EditorWorkspace.colorRgbTabId:
        return _colorTab(
          tabId,
          kind: ColorPickerKind.rgb,
          label: AppText.strings.panelColorRgb,
          icon: Icons.tune,
          locked: locked,
        );
      case EditorWorkspace.colorPaletteTabId:
        return _colorTab(
          tabId,
          kind: ColorPickerKind.palette,
          label: AppText.strings.panelColorPalette,
          icon: Icons.grid_view_outlined,
          locked: locked,
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
          // ⛔NOT the brush glyph (유저, R3 #7). The tool strip's own brush
          // button already wears it two rows above, so the rail read as
          // having the brush twice — and this panel is not the brush, it is
          // the SET you pick one out of.
          icon: Icons.widgets_outlined,
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
      // two tabs of the 「컬러 버튼창」, opened from the top strip's
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
          minContentWidth: _minContentWidthFor(tabId),
          minContentHeight: _minContentHeightFor(tabId),
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
          minContentWidth: _minContentWidthFor(tabId),
          minContentHeight: _minContentHeightFor(tabId),
          locked: locked,
          keepAlive: true,
          builder: (context) => PanelAwareListenableBuilder(
            // Session subscription — the timeline tab's list exactly, and
            // for the same reason: seeks are NOT session notifies, so this
            // panel never rebuilds for one. Scrub moves, playback ticks and
            // committed seeks all ride the host's own channels (playhead
            // overlay + ruler, the rail's lane-label cursor, the command
            // bar's own subscription). `frameSeekCommitted` sat in THIS
            // merge until 2026-08-05 and cost a whole-panel rebuild per
            // arrow press — measured at 38ms a step (12 build / 22 layout /
            // 3 paint) with a six-cut project. Panel-aware (R12-①):
            // offstage notifies defer to one catch-up on re-activation.
            listenable: Listenable.merge([
              widget.session,
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
          minContentWidth: _minContentWidthFor(tabId),
          minContentHeight: _minContentHeightFor(tabId),
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
      case EditorWorkspace.envelopeTabId:
        return EditorPanelTab(
          id: tabId,
          label: 'Envelope',
          icon: Icons.mail_outline,
          buttonKey: const ValueKey<String>('timeline-mode-envelope-button'),
          minContentWidth: _minContentWidthFor(tabId),
          minContentHeight: _minContentHeightFor(tabId),
          locked: locked,
          keepAlive: true,
          // _brushTool is deliberately NOT merged (R18 UI-3): only the ink
          // overlay consumes it, through its own boundary builder.
          builder: (context) => PanelAwareListenableBuilder(
            listenable: Listenable.merge([
              widget.session,
              _envelopeViewport,
              _envelopeInkEnabled,
              _envelopeFormId,
              _envelopeInk,
              widget.session.languageSettings,
            ]),
            builder: (context) => CutEnvelopeTabHost(
              session: widget.session,
              formId: _envelopeFormId.value,
              onFormIdChanged: (formId) {
                _envelopeFormId.value = formId;
              },
              viewport: _envelopeViewport.value,
              onViewportChanged: (viewport) {
                _envelopeViewport.value = viewport;
              },
              inkController: _envelopeInk,
              brushToolState: _brushTool,
              inkEnabled: _envelopeInkEnabled.value,
              onInkEnabledChanged: (enabled) {
                _envelopeInkEnabled.value = enabled;
              },
              // imageFor stays unwired until the 작품 정보 round: nothing
              // sets a logo or a 도장 path yet, so there is no image to
              // resolve — and a resolver with no source is dead code.
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
  Widget _buildDockHost(
    String dockId, {
    bool compact = false,
    bool chromeless = false,
    bool stripAtBottom = false,
    List<Widget>? trailing,
  }) {
    return EditorDockHost(
      chromeless: chromeless,
      stripAtBottom: stripAtBottom,
      trailing: trailing,
      layout: _layout,
      dockId: dockId,
      tabResolver: _tabFor,
      draggingTab: _draggingTab,
      compact: compact,
      canAcceptTab: (data) => _canDockAccept(dockId, data),
      onTabSelected: (tabId) => _mutatingLayout(() {
        _layout.selectTab(dockId, tabId);
      }),
      onTabMoved: (data, insertIndex) => _mutatingLayout(() {
        _layout.moveTab(
          tabId: data.tabId,
          toDockId: dockId,
          insertIndex: insertIndex,
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
      _layout.moveTab(tabId: data.tabId, toDockId: dockId, insertIndex: 0);
    });
    _ensureRailOpen(dockId);
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
    _scheduleLayoutSave();
  }

  EditorDockDropZone _emptyDockZone(
    String dockId,
    Axis axis, {
    bool expandToFill = false,
    String? keyId,
  }) {
    return EditorDockDropZone(
      dockId: dockId,
      keyId: keyId,
      axis: axis,
      draggingTab: _draggingTab,
      canAcceptTab: (data) => _canDockAccept(dockId, data),
      expandToFill: expandToFill,
      onDropped: (data) => _dropIntoEmptyDock(dockId, data),
    );
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

  /// A workspace STRIP: 48px of buttons down one edge.
  ///
  /// One of the two also holds the tool column (whichever [dockId] the
  /// `tools` tab currently lives in — the left-handed switch moves it); the
  /// other is the SUB-STRIP, which used to be an empty 0px dock. Both carry
  /// the same thing underneath: one button per rail GROUP, which opens and
  /// closes that group's column beside the strip.
  Widget _buildEdgeDock(String dockId, EditorPanelDockSide side) {
    final right = side == EditorPanelDockSide.right;
    final hasTools = _layout.tabsIn(dockId).isNotEmpty;
    final groups = _railGroups(right: right);
    final emptySlot = _emptyRailSlot(right: right);
    if (!hasTools && groups.isEmpty && emptySlot == null) {
      return _emptyDockZone(dockId, Axis.vertical);
    }
    return EditorPanelDock.filled(
      side: side,
      width: ToolsPanel.dockWidth,
      dockId: dockId,
      // 고정 도킹 (유저 확정): the strip renders with NO panel frame — no tab
      // name, no lock, no X, no grip. It holds what it holds, and a header
      // over a column of buttons is a title for something that needs no
      // title. Every other dock keeps its strip.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The tool column is rendered as CONTENT, not through a dock host.
          // A host fills whatever it is handed — that is right for a panel
          // and wrong for a strip, and it is why the group buttons under the
          // tools sat at the far end of the tool strip while the sub-strip's
          // sat at the top. Both strips read from the top down now, which is
          // the only way they read as one family.
          if (hasTools)
            Flexible(
              child: Builder(
                builder: (context) =>
                    _tabFor(_layout.tabsIn(dockId).first).builder(context),
              ),
            ),
          // 도구툴그룹밑에도 (유저, R3 #15). The tool column already ends its
          // history cluster with one of these; the panel buttons under it
          // are a third kind of thing and were the only seam on the strip
          // with nothing marking it.
          if (hasTools && (groups.isNotEmpty || emptySlot != null))
            _stripDivider(context),
          _buildRailButtons(right: right, groups: groups, emptySlot: emptySlot),
        ],
      ),
    );
  }

  /// The rule between the tool column and the panel buttons under it,
  /// indented to the same left edge the buttons on both sides of it use.
  Widget _stripDivider(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 3),
    child: ToolsPanel.groupDivider(context),
  );

  /// The rail's group buttons.
  ///
  /// 띠는 스크롤하지 않는다 (유저 확정): a strip that scrolls hands drags to
  /// its scroll arena before the buttons ever see them, and dragging a
  /// panel ONTO a button is how a group is made. So the column is plain —
  /// eight slots is the pool, and eight 42px buttons fit any window tall
  /// enough to draw in.
  Widget _buildRailButtons({
    required bool right,
    required List<String> groups,
    required String? emptySlot,
  }) {
    return ValueListenableBuilder<EditorPanelTabDragData?>(
      valueListenable: _draggingTab,
      builder: (context, dragging, _) {
        return Padding(
          padding: const EdgeInsets.only(left: 3, top: 4, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final railId in groups) ...[
                _RailGroupButton(
                  railId: railId,
                  open: _openRails.contains(railId),
                  tabs: [
                    for (final tabId in _layout.tabsIn(railId)) _tabFor(tabId),
                  ],
                  // The COLOUR group's button is the swatch itself. The
                  // strip's swatch was the one place the two colours you
                  // paint with were readable without opening anything, and
                  // moving the picker to a rail would have taken that with
                  // it — so the button that opens the picker shows them,
                  // and tapping the back slot still swaps (⛔there is no
                  // swap glyph: that would be the same verb twice).
                  face: _colorRailFace(railId),
                  dragging: dragging,
                  onPressed: () => _toggleRailGroup(railId),
                  onTabDropped: (data) => _dropIntoRailGroup(railId, data),
                ),
                const SizedBox(height: 4),
              ],
              // The one empty slot on offer, and only while something is in
              // flight: a permanently visible "+" would be a button that
              // does nothing until you happen to be dragging.
              if (emptySlot != null && dragging != null)
                _RailGroupButton(
                  railId: emptySlot,
                  open: false,
                  tabs: const [],
                  dragging: dragging,
                  onPressed: null,
                  onTabDropped: (data) => _dropIntoRailGroup(emptySlot, data),
                ),
            ],
          ),
        );
      },
    );
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
    _scheduleLayoutSave();
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
    for (final id in _openRailGroups(right: right)) id: _buildDockHost(id),
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
  }) {
    final open = _openRailGroups(right: right);
    if (open.isEmpty) {
      return null;
    }
    final top = (onTop ? stop : 0) + _railGroupGap;
    final available = math.max(0.0, height - top - (onTop ? 0 : stop));
    var content = 0.0;
    for (final id in open) {
      content += _railGroupHeight(id, available) + _railGroupGap;
    }
    content -= _railGroupGap;
    return (top: top, bottom: top + math.min(content, available));
  }

  Widget _buildRailColumn(
    EditorPanelDockSide side, {
    required double width,
    required Map<String, Widget> hosts,
  }) {
    final right = side == EditorPanelDockSide.right;
    final open = _openRailGroups(right: right);
    if (open.isEmpty) {
      return _emptyDockZone(
        _emptyRailSlot(right: right) ??
            (right
                ? EditorWorkspace.rightGroupId
                : EditorWorkspace.leftGroupId),
        Axis.vertical,
        // The RAIL is what the user is aiming at; which of its slots takes
        // the panel is bookkeeping.
        keyId: right ? 'right' : 'left',
      );
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
            return ClipPath(
              clipper: AppShapes.clipper(
                AppShapes.container(AppShapes.floatingPanelRadius),
              ),
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
                      onDragDelta: (delta) => _layout.resizeDock(
                        EditorWorkspace.railWidthKey(right: right),
                        right ? -delta : delta,
                        fallback: EditorWorkspace.sideDockWidth,
                      ),
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

          final children = <Widget>[];
          var y = 0.0;
          for (var i = 0; i < open.length; i += 1) {
            children.add(
              Positioned(
                left: 0,
                right: 0,
                top: y,
                height: heights[i],
                child: group(i),
              ),
            );
            y += heights[i] + _railGroupGap;
          }

          final column = SizedBox(
            height: content,
            child: Stack(clipBehavior: Clip.none, children: children),
          );
          // The panels themselves keep their own width; the gap beside them
          // is the rail's, and belongs to the strip side.
          Widget inGap(Widget child) => Padding(
            padding: EdgeInsets.only(
              left: right ? 0 : _railGroupGap,
              right: right ? _railGroupGap : 0,
            ),
            child: child,
          );
          // 넘칠 때만 (유저 확정). A rail that scrolls hands vertical drags
          // to the scroll arena before the panel tabs see them, so it may
          // not scroll a moment sooner than it has to.
          if (!railExtent.isFinite || content <= railExtent) {
            return inGap(
              Align(alignment: Alignment.topCenter, child: column),
            );
          }
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
                      child: column,
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
    return panelGroupFloorExtent([for (final tabId in tabs) _tabFor(tabId)]);
  }

  /// The canvas keeps at least this much of the workspace's height, the
  /// way [minCenterWidth] keeps it width against the side docks. The bottom
  /// dock had no such guard, and the floor this round added is a force that
  /// GROWS it — without a ceiling a few stacked sections would push the
  /// canvas to zero and then refuse to shrink back.
  static const double _minCenterHeight = 120;

  /// What the window can spare for the bottom dock: everything but the
  /// canvas's own minimum and the splitter between them.
  ///
  /// ONE helper, read by BOTH the render clamp and the splitter's stop. The
  /// first round of this change wrote those two from different premises —
  /// one capped at the model's maximum, the other capped at nothing — and
  /// they agreed only in the default configuration.
  double _bottomDockCeiling(double availableExtent) {
    if (!availableExtent.isFinite) {
      return double.infinity;
    }
    return math.max(
      0.0,
      availableExtent - _minCenterHeight - DockEdgeSplitter.thickness,
    );
  }

  /// The collapsed floating region: its 문턱 plus a brief line of whatever
  /// is open (the timeline's ruler, the storyboard's first row).
  ///
  /// Collapsed is not CLOSED — 유저 확정. The region stays on screen, keeps
  /// its threshold, and keeps taking drops; it just stops asking for a
  /// third of the drawing.
  static const double _collapsedBottomHeight = 70;

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
  double _bottomInsetFor(double windowWidth) =>
      _bottomInsetOverride.value ??
      math.max(
        0.0,
        windowWidth * (1 - _defaultBottomRegionWidthFraction) / 2,
      );

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

  /// How tall the bottom panel is drawn — read by the layout that positions
  /// it AND by the cover the floor is told about, so the panel and the hole
  /// it makes in the artwork can never disagree.
  double _bottomDockHeight(double availableExtent) {
    if (_bottomDockCollapsed) {
      // Through the same ceiling as the open height: collapsed is smaller,
      // but in a window short enough for 70px to crowd the drawing out it
      // is still the window that decides.
      return math.min(
        _collapsedBottomHeight,
        math.max(0.0, _bottomDockCeiling(availableExtent)),
      );
    }
    // Clamped on the way OUT as well as on the drag: a workspace saved
    // before this floor existed, or one whose bottom dock gained a taller
    // tab since, must still open at a height its panels fit in.
    final wanted = math.max(
      _layout.dockExtent(
        EditorWorkspace.bottomGroupId,
        fallback: EditorWorkspace.bottomPanelHeight,
      ),
      _verticalDockMinimumExtent(EditorWorkspace.bottomGroupId),
    );
    // …but never past what the window has. A floor is a promise about how
    // the dock divides its own height, not a claim on someone else's: when
    // the window cannot pay it, the dock yields and the sections share the
    // shortfall ([dockSectionExtents]) with the shell's scroller behind
    // them. The user can always drag their way back out.
    return math.min(wanted, _bottomDockCeiling(availableExtent));
  }

  /// The floating region over the canvas: the timeline and the paper panels
  /// it switches between.
  ///
  /// It is a Stack child of this route and NOT an OverlayPortal — an
  /// OverlayPortal's child draws under the next OverlayEntry, so one dialog
  /// would bury the timeline and swallow its clicks. Being a plain child
  /// means it takes pointers over its whole rectangle, which is why the
  /// clip is not decoration: without it the four corners the silhouette cut
  /// away would still eat strokes aimed at the canvas behind them.
  /// The floating region's PANELS — the heavy part, and the part that does
  /// not depend on a single extent.
  ///
  /// Built above the extent builder and handed in, so pulling the region's
  /// edge re-lays the timeline out without rebuilding it (see the note where
  /// it is built).
  Widget _buildBottomDockContent({required bool onTop}) => _buildDockHost(
    EditorWorkspace.bottomGroupId,
    // 이름 없이 아이콘만 (유저 확정) — the 문턱 says WHICH panel with a
    // glyph and a tooltip. The tab's label is still its only accessibility
    // name, so the names move into the tooltip rather than out of
    // existence.
    compact: true,
    // 정체성은 창틀 향한 변에: the 문턱 rides the edge against the window
    // frame, which is the far side from the artwork — so it flips with the
    // region out of the same law that moved the resize handle.
    stripAtBottom: !onTop,
    trailing: [_bottomCollapseButton(onTop: onTop)],
  );

  Widget _buildBottomDock({
    required double availableExtent,
    required Widget? content,
    bool inset = false,
    bool onTop = false,
    List<Widget> grips = const [],
  }) {
    if (content == null ||
        _layout.tabsIn(EditorWorkspace.bottomGroupId).isEmpty) {
      return _emptyDockZone(EditorWorkspace.bottomGroupId, Axis.horizontal);
    }
    return DecoratedBox(
      // The ring the palette reserves for exactly this: a floating panel
      // has to end somewhere, and it is lying on a colour the user picked,
      // so no fill of ours can be relied on to contrast with it. Drawn
      // OUTSIDE the clip, or the clip would eat its outer half.
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: _floatingBottomShape(
          inset: inset,
          onTop: onTop,
          side: const BorderSide(color: AppColors.backdrop),
        ),
      ),
      child: ClipPath(
        key: const ValueKey<String>('floating-bottom-region'),
        clipper: AppShapes.clipper(
          _floatingBottomShape(inset: inset, onTop: onTop),
        ),
        // The height is the layout's to hand out now (see
        // [_bottomDockHeight]); the region just fills what it is given.
        //
        // ★The grips are INSIDE this clip (R2 #11). They used to sit
        // outside it, beside the region, which is why hovering one lit a
        // straight bar against a rounded panel: the clip is what makes a
        // grip read as the panel's own edge.
        child: Stack(
          children: [
            Positioned.fill(child: content),
            ...grips,
          ],
        ),
      ),
    );
  }

  /// The silhouette of the floating region.
  ///
  /// A corner that lies ON the window's own edge is square: a rounded one
  /// there would show the scaffold through the notch rather than the
  /// artwork, which reads as a rendering fault rather than as a shape. So
  /// the rule is about where the edges ARE, and it keeps holding when the
  /// region gains its symmetric side inset.
  RoundedSuperellipseBorder _floatingBottomShape({
    bool inset = false,
    bool onTop = false,
    BorderSide side = BorderSide.none,
  }) {
    const radius = Radius.circular(AppShapes.floatingPanelRadius);
    // The corner that lies ON the window's own edge is square; the one
    // facing the artwork is round. Which is which flips with the region's
    // edge, and pulling the sides in rounds the flush pair too, because
    // then they are not touching the frame either.
    final flush = inset ? radius : Radius.zero;
    return AppShapes.containerRadius(
      BorderRadius.vertical(
        top: onTop ? flush : radius,
        bottom: onTop ? radius : flush,
      ),
      side: side,
    );
  }

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
          _scheduleLayoutSave();
        },
        onDragStart: () => _bottomInsetDragRaw = inset,
        onDragEnd: () => _bottomInsetDragRaw = null,
        onDragDelta: (delta) {
          // Pulling the LEFT edge right and the RIGHT edge left both grow
          // the inset, which is what "symmetric" means from the hand's side.
          final raw = ((_bottomInsetDragRaw ?? inset) + (right ? -delta : delta))
              .clamp(0.0, maxInset)
              .toDouble();
          _bottomInsetDragRaw = raw;
          _bottomInsetOverride.value = _detented(raw, railSpan);
          _scheduleLayoutSave();
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

  Widget _bottomCollapseButton({bool onTop = false}) {
    return IconButton(
      key: const ValueKey<String>('floating-bottom-collapse'),
      tooltip: _bottomDockCollapsed
          ? AppText.strings.panelExpandRegion
          : AppText.strings.panelCollapseRegion,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: AppShapes.control(28),
      ),
      onPressed: () {
        setState(() => _bottomDockCollapsed = !_bottomDockCollapsed);
        _scheduleLayoutSave();
      },
      // The chevron points where the region would GO — toward the artwork
      // to open, toward the frame to collapse — so it flips with the edge
      // rather than always meaning "down".
      icon: Icon(
        _bottomDockCollapsed == onTop
            ? Icons.keyboard_arrow_down
            : Icons.keyboard_arrow_up,
      ),
    );
  }

  /// Which panel is currently lying on the floor.
  String? _activeFloorTabId() =>
      _layout.activeTabIn(EditorWorkspace.centerGroupId);

  /// The top strip's canvas/viewer switch: swap what the app is lying on.
  ///
  /// Selecting is the whole job when the panel is already down there, which
  /// is the default arrangement. It is not the only arrangement — a panel
  /// can be dragged anywhere, and a workspace saved before the floor existed
  /// still has the viewer among the paper tabs — so a switch that only
  /// selected would be a dead button for exactly the people whose layout
  /// predates it. Fetching it back is what makes the switch mean the same
  /// thing every time it is pressed.
  void _selectFloorTab(String tabId) {
    final tabs = _layout.tabsIn(EditorWorkspace.centerGroupId);
    if (tabs.contains(tabId)) {
      _mutatingLayout(() {
        _layout.selectTab(EditorWorkspace.centerGroupId, tabId);
      });
      return;
    }
    _mutatingLayout(() {
      _layout.moveTab(
        tabId: tabId,
        toDockId: EditorWorkspace.centerGroupId,
        insertIndex: tabs.length,
      );
    });
  }

  /// The center dock hosts the canvas tab by default. Unlike the edge
  /// docks it always occupies its region — when emptied it stays a
  /// full-size drop surface.
  Widget _buildCenterDock() {
    if (_layout.tabsIn(EditorWorkspace.centerGroupId).isEmpty) {
      return _emptyDockZone(
        EditorWorkspace.centerGroupId,
        Axis.vertical,
        expandToFill: true,
      );
    }
    // The floor has NO tab strip. Two reasons, and either alone would be
    // enough: the strip would be under the panels floating on it (the left
    // column starts at the floor's own top-left corner, so its first 30
    // pixels are exactly where the tabs used to be), and the switch between
    // the floor's panels has moved to the top strip, where it is reachable
    // whatever is open.
    //
    // Losing the strip also takes the canvas's lock glyph and its X, and
    // that is the protection rather than a hole in it: a surface with no
    // grip cannot be dragged off the floor by a slip of the hand, which is
    // what the default lock was there to prevent.
    return _buildDockHost(EditorWorkspace.centerGroupId, chromeless: true);
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
            ? _buildBottomDockContent(onTop: _regionOnTop)
            : null;
        return Row(
          children: [
            // The two tool strips are the only things that take space from
            // the canvas. Everything else LIES ON IT.
            _buildEdgeDock(
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
                      child: _buildCenterDock(),
                      builder: (context, floor) {
                        // The side docks keep their saved extents but may never
                        // squeeze the canvas out: scale both down proportionally
                        // when the window can't fit them.
                        const minCenterWidth = 120.0;
                        var leftWidth = hasLeftDock
                            ? _layout.dockExtent(
                                EditorWorkspace.railWidthKey(right: false),
                                fallback: EditorWorkspace.sideDockWidth,
                              )
                            : 0.0;
                        var rightWidth = hasRightDock
                            ? _layout.dockExtent(
                                EditorWorkspace.railWidthKey(right: true),
                                fallback: EditorWorkspace.sideDockWidth,
                              )
                            : 0.0;
                        // The gap between the strip and the panel floating
                        // beside it. It is what a rail costs the canvas
                        // beyond the panel itself; the width grips are
                        // overlays and cost nothing.
                        final gaps =
                            (hasLeftDock ? _railGroupGap : 0) +
                            (hasRightDock ? _railGroupGap : 0);
                        final room =
                            (constraints.maxWidth - gaps - minCenterWidth)
                                .clamp(0.0, double.infinity);
                        final wanted = leftWidth + rightWidth;
                        if (wanted > room && wanted > 0) {
                          final scale = room / wanted;
                          leftWidth *= scale;
                          rightWidth *= scale;
                        }
                        final bottomHeight = hasBottomDock
                            ? _bottomDockHeight(constraints.maxHeight)
                            : 0.0;
                        // Symmetric, and clamped against the WINDOW: the region
                        // may narrow until it is a panel rather than a bar, and
                        // no further.
                        final bottomInset = _bottomInsetFor(constraints.maxWidth)
                            .clamp(
                              0.0,
                              math.max(
                                0.0,
                                (constraints.maxWidth - _minBottomRegionWidth) /
                                    2,
                              ),
                            )
                            .toDouble();
                        final leftRailSpan = hasLeftDock
                            ? leftWidth + _railGroupGap
                            : 0.0;
                        final rightRailSpan = hasRightDock
                            ? rightWidth + _railGroupGap
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
                            ? regionSpan
                            : 0.0;
                        final leftStop = columnStop(leftRailSpan);
                        final rightStop = columnStop(rightRailSpan);

                        return Stack(
                          children: [
                            // ★ THE FLOOR. Everything below this line is drawn on
                            // top of the drawing.
                            Positioned.fill(
                              child: CanvasFloorInsets(
                                insets: floorCover,
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
                                ),
                                rightRailBand: _railBand(
                                  right: true,
                                  stop: rightStop,
                                  onTop: onTop,
                                  height: constraints.maxHeight,
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
                              top: (onTop ? leftStop : 0) + _railGroupGap,
                              bottom: onTop ? 0 : leftStop,
                              // The gap is INSIDE the column's box now: the
                              // rail's own scrollbar rides it.
                              width: hasLeftDock
                                  ? leftWidth + _railGroupGap
                                  : null,
                              child: _buildRailColumn(
                                EditorPanelDockSide.left,
                                width: leftWidth,
                                hosts: leftRailHosts,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: (onTop ? rightStop : 0) + _railGroupGap,
                              bottom: onTop ? 0 : rightStop,
                              width: hasRightDock
                                  ? rightWidth + _railGroupGap
                                  : null,
                              child: _buildRailColumn(
                                EditorPanelDockSide.right,
                                width: rightWidth,
                                hosts: rightRailHosts,
                              ),
                            ),
                            Positioned(
                              left: bottomInset,
                              right: bottomInset,
                              top: onTop ? 0 : null,
                              bottom: onTop ? null : 0,
                              height: hasBottomDock ? bottomHeight : null,
                              child: _buildBottomDock(
                                availableExtent: constraints.maxHeight,
                                content: bottomContent,
                                inset: bottomInset > 0,
                                onTop: onTop,
                                // Every grip the region has, laid on its own
                                // edges inside its own clip.
                                grips: !hasBottomDock
                                    ? const []
                                    : [
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          // 기하는 캔버스 향한 변에: the resize
                                          // handle rides whichever edge faces
                                          // the artwork, which flips with the
                                          // region and needs no rule of its own.
                                          top: onTop ? null : 0,
                                          bottom: onTop ? 0 : null,
                                          height: DockEdgeSplitter.thickness,
                                          child: DockEdgeSplitter(
                                            key: const ValueKey<String>(
                                              'dock-resize-bottom',
                                            ),
                                            axis: Axis.horizontal,
                                            onDragDelta: (delta) {
                                              // Dragging the handle of a
                                              // collapsed region means "give
                                              // me it back" — otherwise the
                                              // grip is live, moves nothing,
                                              // and the only way out is a
                                              // button somewhere else.
                                              if (_bottomDockCollapsed) {
                                                setState(
                                                  () => _bottomDockCollapsed =
                                                      false,
                                                );
                                                _scheduleLayoutSave();
                                              }
                                              _layout.resizeDock(
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
                                                  _bottomDockCeiling(
                                                    constraints.maxHeight,
                                                  ),
                                                ),
                                                // The model's own 640 still
                                                // applies here — the region
                                                // has always had it, and
                                                // lifting it is a separate
                                                // decision from fixing the
                                                // banking.
                                                maxExtent: math.min(
                                                  EditorPanelLayoutModel
                                                      .maxDockExtent,
                                                  _bottomDockCeiling(
                                                    constraints.maxHeight,
                                                  ),
                                                ),
                                              );
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
                                          railSpan: leftRailSpan,
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
                                          railSpan: rightRailSpan,
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
              child: InkWell(
                onTap: onPressed,
                // The pair sizes itself to one button cell, so a group that
                // wears a face is the same square as every other.
                child: SizedBox.square(
                  dimension: ToolsPanel.buttonExtent,
                  child: face,
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
