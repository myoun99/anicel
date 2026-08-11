import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/persistence/anicel_project_archive.dart';
import '../../services/persistence/app_documents.dart';
import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/persistence/folder_grant.dart';
import '../../services/persistence/project_autosave_service.dart';
import '../../services/persistence/recent_projects.dart';
import '../../services/persistence/recent_projects_store.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/brush_pressure_curve.dart';
import '../../services/color_palette_file_service.dart';
import '../brush/brush_tool_state.dart';
import '../brush/tools_panel.dart' show RailButton;
import '../widgets/field_slider.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pressure_curve_popup.dart';
import '../dialogs/app_prompt_dialog.dart';
import '../dialogs/folder_pick_flow.dart';
import '../dialogs/project_chooser_dialog.dart';
import '../dialogs/preferences_dialog.dart';
import '../canvas/paper_background.dart' show alphaPreviewEnabled;
import '../debug/input_inspector.dart';
import '../debug/measurement_mode.dart';
import '../widgets/static_raster.dart';
import '../dialogs/project_background_dialog.dart';
import '../editor_session_manager.dart';
import '../../services/persistence/app_export_settings_store.dart';
import '../export/export_dialog.dart';
import '../import/import_dialog.dart';
import '../export/export_plan.dart' show sanitizeExportFileComponent;
import '../panels/workspace_panels_menu.dart';
import '../shortcuts/editor_shortcut_bindings.dart';
import '../shortcuts/shortcut_settings_dialog.dart';

/// The editor's top strip: two icon buttons and the work's name, the way
/// Procreate and Callipeg do it.
///
/// This was a seven-menu bar in the CSP/Photoshop language. Every command
/// it carried now lives where its result shows up — layer and cut verbs in
/// the timeline's flyouts, undo/redo and onion at the head of the tool
/// rail, the frame verbs on the timeline command bar — so what is left is
/// the two things that belong to no surface in particular: the PROJECT
/// (open, save, hand off) and the SETTINGS of the app itself.
///
/// The strip deliberately keeps the old `menu-<id>` keys on its items.
/// They name commands, not menus, and a command that only moved house
/// should not cost every test that reaches for it.
class EditorTopStrip extends StatelessWidget {
  const EditorTopStrip({
    super.key,
    required this.session,
    required this.panelsMenu,
    this.brushTool,
    this.colorBackground,
    this.colorPalette,
    this.onColorPaletteChanged,
    this.shortcuts,
    this.anicelOpenFilePicker,
    this.anicelSaveFilePicker,
  });

  final EditorSessionManager session;
  final WorkspacePanelsMenuController panelsMenu;

  /// The active tool's settings. The size and opacity bars ride the strip's
  /// right end (프로크리·카리페그 배치) because they are values you set
  /// mid-stroke, and an anchored popover closes the moment you touch the
  /// canvas — a value button could never be adjusted against a test mark.
  ///
  /// Null leaves the right end empty (passive hosts and focused tests).
  final ValueNotifier<BrushToolState>? brushTool;

  /// The colour control's other two pieces: the spare (background) slot and
  /// the pinned palette. The FOREGROUND colour is not here — it rides
  /// [brushTool], which is where a colour has always lived.
  ///
  /// All three are null together in practice; the colour button needs the
  /// set, so a host that supplies part of it gets no button.
  final ValueNotifier<int>? colorBackground;
  final ValueNotifier<ColorPaletteState>? colorPalette;

  /// Palette writes go back through the host because they PERSIST — the
  /// strip must not learn where a palette file lives.
  final ValueChanged<ColorPaletteState>? onColorPaletteChanged;

  /// Injectable for tests; default to the platform file dialogs.
  final Future<String?> Function()? anicelOpenFilePicker;
  final Future<String?> Function(String suggestedName)? anicelSaveFilePicker;

  /// The customizable shortcut bindings (P1); null hides the shortcut
  /// labels and disables the settings entry (focused widget tests).
  final EditorShortcutBindings? shortcuts;

  /// One popover entry. The single funnel every item goes through, so the
  /// key and the wording are decided in one place.
  ///
  /// A null [onPressed] disables the row, which is how the old menu said
  /// the same thing.
  PanelFlyoutItem _item({
    required String id,
    required String label,
    VoidCallback? onPressed,
    IconData? icon,
    bool? checked,
  }) => PanelFlyoutItem(
    keyValue: 'menu-$id',
    // Every entry localizes HERE, by the id it is already keyed with, with
    // the English staying at the call sites where the strip is authored.
    label: AppText.strings.menuLabel(id, label),
    icon: icon,
    checked: checked,
    enabled: onPressed != null,
    onSelected: onPressed,
  );

  // --- File -----------------------------------------------------------------

  static Future<String?> _defaultOpenPicker() async {
    final file = await openFile(
      // SAVE-1: pickers start in the app's project home (앱 문서 폴더).
      initialDirectory: await ensuredAppDocumentsDirectory(),
      acceptedTypeGroups: const [FileTypeGroups.anicelProject],
    );
    return file?.path;
  }

  void _showFileError(BuildContext context, Object error) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('$error')));
  }

  Future<void> _openProject(BuildContext context) async {
    final ProjectPick? pick;
    if (anicelOpenFilePicker != null) {
      final injected = await anicelOpenFilePicker!();
      pick = injected == null ? null : (path: injected, folderBookmark: null);
    } else {
      pick = await pickProjectToOpen(context);
    }
    if (pick == null || !context.mounted) {
      return;
    }
    final path = pick.path;
    // A newer autosave sidecar offers recovery (crash / sync loss).
    // SAVE-1: the sidecar may live beside the file OR in the user's
    // sidecar directory (and the setting may have changed since it was
    // written) — every candidate location is checked, newest wins.
    var openPath = path;
    String? recoverAs;
    final sidecar = AppSave.newestExistingSidecarFor(path);
    if (sidecar != null &&
        ProjectAutosaveService.sidecarIsNewer(
          filePath: path,
          sidecarPath: sidecar,
        )) {
      final recover = await showDialog<bool>(
        context: context,
        builder: (context) => AppConfirmDialog(
          windowKey: const ValueKey<String>('recover-autosave-dialog'),
          title: AppText.strings.recoverAutosaveTitle,
          titleIcon: Icons.restore_outlined,
          message: AppText.strings.recoverAutosaveBody,
          actions: [
            AppWindowAction(
              label: AppText.strings.recoverOpenSaved,
              actionKey: const ValueKey<String>('recover-open-saved-button'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            AppWindowAction(
              label: AppText.strings.recoverAction,
              actionKey: const ValueKey<String>('recover-autosave-button'),
              emphasis: AppWindowActionEmphasis.primary,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (recover == null || !context.mounted) {
        return;
      }
      if (recover) {
        openPath = sidecar;
        recoverAs = path;
      }
    }
    try {
      await session.openProjectFromFile(openPath, recoverAs: recoverAs);
      // Recorded AFTER the open succeeds, not at pick time: a file that
      // fails to parse has no business sitting at the top of the menu.
      // `path` rather than `openPath` — recovering from a sidecar still
      // means the user opened the project, not the sidecar.
      recordRecentProject(
        RecentProject(path: path, folderBookmark: pick.folderBookmark),
      );
    } catch (error) {
      if (context.mounted) {
        _showFileError(context, error);
      }
    }
  }

  Future<void> _saveProjectAs(BuildContext context) =>
      promptSaveProjectAs(context, session, savePicker: anicelSaveFilePicker);

  Future<void> _saveProject(BuildContext context) async {
    final path = session.projectFilePath;
    if (path == null) {
      await _saveProjectAs(context);
      return;
    }
    try {
      await session.saveProjectToFile(path);
    } catch (error) {
      if (context.mounted) {
        _showFileError(context, error);
      }
    }
  }

  /// PICK-4: the recent projects, or nothing at all.
  ///
  /// Absent rather than empty-and-disabled when there is no history: a
  /// heading over nothing is a menu row that only ever says "no".
  ///
  /// These do NOT go through [_item]. That helper localizes by id, and a
  /// project's file name is not a phrase in five languages — routing it
  /// through the menu-label table would ask the app to translate the user's
  /// own filenames.
  List<PanelFlyoutEntry> _recentEntries(BuildContext context) {
    final recents = AppRecent.projects.value.entries;
    if (recents.isEmpty) {
      return const [];
    }
    final strings = AppText.strings;
    return [
      const PanelFlyoutDivider(),
      PanelFlyoutHeader(strings.recentProjectsTitle),
      for (final entry in recents)
        PanelFlyoutItem(
          keyValue: 'menu-recent-${entry.path}',
          label: entry.needsReconnect
              ? '${entry.name} — ${strings.recentReconnect}'
              : entry.name,
          icon: entry.needsReconnect
              ? Icons.link_off_outlined
              : Icons.history_outlined,
          enabled: true,
          onSelected: () => unawaited(_openRecent(context, entry)),
        ),
    ];
  }

  /// Opens a remembered project, re-acquiring its folder first.
  ///
  /// On Apple platforms the stored path alone is refused — the security
  /// scope has to be taken again from the bookmark before anything may read
  /// it. When that fails the row is not deleted: the user still knows which
  /// project they mean, so they are handed the folder picker to point at it
  /// again, and a match by FILE NAME inside the newly granted folder is what
  /// re-links it. That also covers the ordinary case of a project the user
  /// moved themselves.
  Future<void> _openRecent(BuildContext context, RecentProject entry) async {
    var path = entry.path;
    final bookmark = entry.folderBookmark;
    if (bookmark != null) {
      final grant = await FolderPicker.resolveBookmark(bookmark);
      if (grant.isGranted) {
        path = '${grant.path}/${entry.name}';
      } else {
        storeRecentProjects(
          AppRecent.projects.value.withReconnectNeeded(entry.path),
        );
        if (!context.mounted) {
          return;
        }
        final regrant = await pickFolderGrantForUser(context);
        final folder = regrant?.path;
        if (folder == null) {
          return;
        }
        path = '$folder/${entry.name}';
        storeRecentProjects(
          AppRecent.projects.value.withReconnected(entry.path, regrant!.bookmark),
        );
      }
    }
    if (!File(path).existsSync()) {
      storeRecentProjects(
        AppRecent.projects.value.withReconnectNeeded(entry.path),
      );
      if (context.mounted) {
        _showFileError(context, 'Not found: $path');
      }
      return;
    }
    try {
      await session.openProjectFromFile(path);
      recordRecentProject(
        RecentProject(path: path, folderBookmark: entry.folderBookmark),
      );
    } catch (error) {
      if (context.mounted) {
        _showFileError(context, error);
      }
    }
  }

  /// The PROJECT popover: the file itself, and the two doors it has to the
  /// outside world. Export used to sit as its own icon in the strip; it is
  /// a once-a-session verb, so it belongs behind the same button as saving
  /// rather than costing a permanent slot.
  List<PanelFlyoutEntry> _projectEntries(BuildContext context) => [
    _item(
      id: 'file-open',
      label: 'Open…',
      icon: Icons.folder_open_outlined,
      onPressed: () => unawaited(_openProject(context)),
    ),
    _item(
      id: 'file-save',
      label: 'Save',
      icon: Icons.save_outlined,
      onPressed: () => unawaited(_saveProject(context)),
    ),
    _item(
      id: 'file-save-as',
      label: 'Save as…',
      icon: Icons.save_as_outlined,
      onPressed: () => unawaited(_saveProjectAs(context)),
    ),
    ..._recentEntries(context),
    const PanelFlyoutDivider(),
    _item(
      id: 'file-project-background',
      label: 'Project background…',
      icon: Icons.gradient_outlined,
      onPressed: () {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (context) => ProjectBackgroundDialog(session: session),
          ),
        );
      },
    ),
    const PanelFlyoutDivider(),
    _item(
      id: 'file-import',
      label: 'Import / Place…',
      icon: Icons.file_download_outlined,
      onPressed: () {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (context) => ImportDialog(session: session),
          ),
        );
      },
    ),
    _item(
      id: 'file-export',
      label: 'Export…',
      icon: Icons.save_alt,
      // The export dialog is cut-anchored — disabled in the no-cut gap
      // state (UI-R9 #3).
      onPressed: session.activeCutOrNull == null
          ? null
          : () {
              unawaited(
                showDialog<void>(
                  context: context,
                  builder: (context) => ExportDialog(
                    session: session,
                    settingsStore: AppExportSettingsStore(),
                  ),
                ),
              );
            },
    ),
  ];

  // --- Settings -------------------------------------------------------------

  /// The SETTINGS popover: the app's own knobs, the panel switchboard, and
  /// the three diagnosis overlays.
  ///
  /// Undo, redo and the six frame verbs used to head this list. They were
  /// never settings — they are things you do to the work — and they now
  /// live on the tool rail and the timeline's command bar respectively.
  ///
  /// The panel rows are the old Window menu, behaviour unchanged: a closed
  /// panel has no other way back, so that list is load-bearing.
  List<PanelFlyoutEntry> _settingsEntries(BuildContext context) => [
    _item(
      id: 'edit-keyboard-shortcuts',
      label: 'Keyboard shortcuts…',
      icon: Icons.keyboard_outlined,
      onPressed: shortcuts == null
          ? null
          : () {
              unawaited(
                showDialog<void>(
                  context: context,
                  builder: (context) =>
                      ShortcutSettingsDialog(bindings: shortcuts!),
                ),
              );
            },
    ),
    // SAVE-1: Input/Autosave/Language/Accent collapsed into ONE
    // Preferences window (the per-domain dialogs live on as thin
    // wrappers around the same section widgets).
    _item(
      id: 'edit-preferences',
      label: 'Preferences…',
      icon: Icons.tune,
      onPressed: () {
        unawaited(showPreferencesDialog(context, session: session));
      },
    ),
    const PanelFlyoutDivider(),
    // The old Window menu. Every panel with its visibility — a closed
    // (X-ed) panel reopens ONLY from here, so this list is the one path
    // back and cannot be dropped with the rest of the menus.
    for (final entry in panelsMenu.entries)
      PanelFlyoutItem(
        keyValue: 'panels-menu-item-${entry.tabId}',
        label: entry.label,
        icon: Icons.space_dashboard_outlined,
        checked: entry.visible,
        onSelected: () => panelsMenu.toggle(entry.tabId),
      ),
    // The left-handed choice. It was a tab drag until 고정 도킹 took the
    // grip away, and a strip you cannot move is the wrong answer for half
    // the people holding the stylus.
    _item(
      id: 'window-tool-rail-right',
      label: 'Tool strip on the right',
      icon: Icons.flip,
      checked: panelsMenu.toolRailOnRight,
      onPressed: panelsMenu.canMoveToolRail
          ? () => panelsMenu.setToolRailOnRight(!panelsMenu.toolRailOnRight)
          : null,
    ),
    // 아래 도킹 영역은 위/아래 설정 가능 (유저 확정). What flips with it —
    // the resize handle to the other edge, the 문턱 with it, the square
    // corners to whichever side is against the frame — needed no new rule:
    // 「기하는 캔버스 향한 변에, 정체성은 창틀 향한 변에」 decides all of it.
    _item(
      id: 'window-region-on-top',
      label: 'Timeline region on top',
      icon: Icons.vertical_align_top,
      checked: panelsMenu.regionOnTop,
      onPressed: panelsMenu.canMoveRegion
          ? () => panelsMenu.setRegionOnTop(!panelsMenu.regionOnTop)
          : null,
    ),
    _item(
      id: 'window-reset-layout',
      label: 'Reset workspace layout',
      icon: Icons.restart_alt,
      onPressed: panelsMenu.canResetLayout ? panelsMenu.resetLayout : null,
    ),
    const PanelFlyoutDivider(),
    // The pen program's diagnosis overlay (PEN-1): toggles the live
    // pointer-event readout — kind/pressure/tilt straight from the
    // platform, the driver-vs-app separator.
    _item(
      id: 'edit-input-inspector',
      label: 'Input Inspector',
      icon: Icons.bug_report_outlined,
      checked: InputInspector.visible.value,
      onPressed: () {
        InputInspector.visible.value = !InputInspector.visible.value;
      },
    ),
    // Its sibling measurement switch: the inspector says what the
    // platform DELIVERED, this says what the app did with the frame it
    // had. A toggle rather than a build flag because flipping a
    // --dart-define on a tablet costs a rebuild and an install.
    _item(
      id: 'edit-frame-timing-overlay',
      label: 'Frame Timing Overlay',
      icon: Icons.speed_outlined,
      checked: MeasurementMode.frameTimingOverlay.value,
      onPressed: () {
        MeasurementMode.frameTimingOverlay.value =
            !MeasurementMode.frameTimingOverlay.value;
      },
    ),
    // The same clock in numbers, and the one to believe when the two
    // disagree: percentiles instead of max/avg, END-TO-END LATENCY,
    // which the graphs have no line for, and the engine's raster-cache
    // counts, which are the only way from Dart to ask whether a repaint
    // boundary bought anything on the GPU. It is also six lines of text
    // at 4 Hz, where the graphs are two full-width bars redrawn every
    // frame inside the scene whose raster time they report.
    _item(
      id: 'edit-frame-stats',
      label: 'Frame Stats',
      icon: Icons.query_stats_outlined,
      checked: MeasurementMode.frameStats.value,
      onPressed: () {
        MeasurementMode.frameStats.value = !MeasurementMode.frameStats.value;
      },
    ),
    // Krita ships `KisRepaintDebugger` in production and Blender tints
    // every drawn region under `debug_value == 888`, both for the same
    // reason this program keeps rediscovering: a panel paying full price
    // looks exactly like a free one. The standing report says WHICH
    // panels bake; this says WHEN, while you work. A surface that
    // strobes as the pen moves is re-baking on your pointer.
    _item(
      id: 'edit-show-repaints',
      label: 'Show Repaints',
      icon: Icons.flare_outlined,
      checked: MeasurementMode.showRepaints.value,
      onPressed: () {
        MeasurementMode.showRepaints.value =
            !MeasurementMode.showRepaints.value;
      },
    ),
    // The A/B. Turning the bakes off puts the app back the way it was
    // before them, in the SAME build, so "what did this actually buy" is
    // two readings a few seconds apart rather than an argument.
    //
    // 🚨 It existed as a `ValueNotifier` from the day the bakes shipped
    // and was never wired to anything, so the one switch the whole
    // measurement needs could not be reached without editing code. A
    // debug affordance nobody can press is a debug affordance nobody has.
    _item(
      id: 'edit-bake-panels',
      label: 'Bake Static Panels',
      icon: Icons.layers_outlined,
      checked: StaticRaster.globallyEnabled.value,
      onPressed: () {
        StaticRaster.globallyEnabled.value =
            !StaticRaster.globallyEnabled.value;
      },
    ),
    // And the marker for where the canvas painter had NO picture for a
    // coordinate it was asked to draw. The whole stale-tile family is
    // that one event, and it is invisible because the painter's answer
    // to "I have nothing here" is to draw nothing — so every instance
    // had to be found by hand, from a real session, one report at a
    // time. Magenta means "no picture", never "no artwork".
    _item(
      id: 'edit-show-unpainted-tiles',
      label: 'Show Unpainted Tiles',
      icon: Icons.grid_off_outlined,
      checked: MeasurementMode.showUnpaintedTiles.value,
      onPressed: () {
        MeasurementMode.showUnpaintedTiles.value =
            !MeasurementMode.showUnpaintedTiles.value;
      },
    ),
    // R3b: the BACKDROP plane rendered as the alpha checkerboard —
    // display-only, showing exactly what an alpha export leaves open.
    PanelFlyoutItem(
      keyValue: 'menu-edit-alpha-preview',
      label: AppText.strings.menuAlphaPreview,
      icon: Icons.texture_outlined,
      checked: alphaPreviewEnabled.value,
      onSelected: () => alphaPreviewEnabled.value = !alphaPreviewEnabled.value,
    ),
    const PanelFlyoutDivider(),
    _item(
      id: 'help-about',
      label: 'About Anicel',
      icon: Icons.info_outline,
      onPressed: () =>
          showAboutDialog(context: context, applicationName: 'Anicel'),
    ),
  ];

  /// What the strip calls the work: the saved file's name without its
  /// extension, and nothing at all before the first save. A placeholder
  /// like "Untitled" would be a label that never changes into anything —
  /// the empty middle is honest, and it is where the project SWITCHER goes
  /// once more than one project can be open at a time.
  String get _projectLabel {
    final path = session.projectFilePath;
    if (path == null) {
      return '';
    }
    final file = path.split(RegExp(r'[\\/]')).last;
    return file.endsWith('.$anicelProjectExtension')
        ? file.substring(0, file.length - anicelProjectExtension.length - 1)
        : file;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 3),
        _StripPopoverButton(
          keyValue: 'top-strip-project-button',
          tooltip: AppText.strings.topStripProject,
          icon: Icons.folder_outlined,
          entriesBuilder: () => _projectEntries(context),
        ),
        const SizedBox(width: 4),
        _StripPopoverButton(
          keyValue: 'top-strip-settings-button',
          tooltip: AppText.strings.topStripSettings,
          icon: Icons.settings_outlined,
          entriesBuilder: () => _settingsEntries(context),
        ),
        const SizedBox(width: 6),
        const _StripGroupRule(),
        const SizedBox(width: 6),
        _FloorSwitch(panelsMenu: panelsMenu),
        Expanded(
          child: Center(
            child: Text(
              _projectLabel,
              key: const ValueKey<String>('top-strip-project-name'),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // 유저 확정 order, left to right: blend + its lock, a rule, then
        // size and opacity each with their pressure curve, then the colour.
        // The rule is what makes the first two read as one group rather
        // than as a button that has wandered next to a slider.
        if (brushTool != null) ...[
          _BlendModeControl(brushTool: brushTool!),
          const SizedBox(width: 6),
          const _StripGroupRule(),
          const SizedBox(width: 6),
          _BrushValueBars(brushTool: brushTool!),
          // 컬러 창은 상단띠에서 오른쪽 서브띠 맨 위로 (유저 확정). It was
          // the one surface that opened DOWNWARD out of a strip; as a rail
          // group it opens sideways like everything else, and the swatch
          // goes with it — the rail button IS the pair now. 42px back.
        ],
        const SizedBox(width: 3),
      ],
    );
  }
}

/// Size and opacity, each followed by its pressure curve button.
///
/// Bars rather than value buttons: these are set WHILE drawing, against a
/// test mark on the canvas, and an anchored popover closes on the first
/// pointer-down outside it (R27 #5) — a button would force open-adjust-
/// close-draw every time. [FieldSlider] already puts the name and the
/// number inside the track, so one 140px run says everything.
///
/// The pressure buttons came WITH them from the tool settings panel (유저
/// 확정): a curve belongs beside the value it shapes, and splitting them
/// across two surfaces would mean setting a size here and asking how the
/// pen affects it over there.
///
/// Its own listener: a size drag must not rebuild the popover buttons or
/// re-read the project name beside them.
class _BrushValueBars extends StatelessWidget {
  const _BrushValueBars({required this.brushTool});

  final ValueNotifier<BrushToolState> brushTool;

  static const double _barWidth = 140;
  static const double _barHeight = 42;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BrushToolState>(
      valueListenable: brushTool,
      builder: (context, state, _) {
        Widget pressure(BrushPressureTarget target, String title) {
          return PressureCurveButton(
            keyValue: 'brush-tool-pressure-${target.name}',
            title: title,
            curve: state.pressureCurveFor(target),
            onChanged: (curve) =>
                brushTool.value = state.withPressureCurve(target, curve),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _barWidth,
              height: _barHeight,
              child: FieldSlider(
                key: const ValueKey<String>('top-strip-size-bar'),
                label: AppText.strings.brSize,
                value: BrushToolState.clampSize(state.size),
                min: BrushToolState.minSize,
                max: BrushToolState.maxSize,
                // Equal travel multiplies the value, so the left half covers
                // the small sizes where a pixel matters.
                scale: FieldSliderScale.exponential,
                valueText: '${state.size.round()} px',
                height: _barHeight,
                onChanged: (value) =>
                    brushTool.value = brushTool.value.copyWith(size: value),
              ),
            ),
            const SizedBox(width: 4),
            pressure(BrushPressureTarget.size, AppText.strings.brSize),
            const SizedBox(width: 4),
            SizedBox(
              width: _barWidth,
              height: _barHeight,
              child: FieldSlider(
                key: const ValueKey<String>('top-strip-opacity-bar'),
                label: AppText.strings.brOpacity,
                value: BrushToolState.clampOpacity(state.opacity),
                min: 0,
                max: 1,
                valueText: '${(state.opacity * 100).round()}%',
                height: _barHeight,
                onChanged: (value) =>
                    brushTool.value = brushTool.value.copyWith(opacity: value),
              ),
            ),
            const SizedBox(width: 4),
            pressure(BrushPressureTarget.opacity, AppText.strings.brOpacity),
          ],
        );
      },
    );
  }
}

/// The rule between the strip's groups — the same one the tool rail draws
/// between its history head and its tools, stood on its end.
class _StripGroupRule extends StatelessWidget {
  const _StripGroupRule();

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      indent: 6,
      endIndent: 6,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// The blend mode and its lock, at the strip's left-most right-group slot.
///
/// The BRUSH BLEND dropdown (BB-2) moved here whole from the tool settings
/// panel (유저 확정) — the PS/CSP vocabulary where the LABEL is the current
/// mode, plus the pin that keeps a brush on one blend. A named button beats
/// the icon popover the strip briefly wore: a blend you cannot read without
/// opening it is a blend you check by opening it.
///
/// It is one of the three settings a preset deliberately never carries
/// (R26 #10), which is what makes it belong out here with the hand's other
/// standing choices rather than inside a preset.
///
/// The width is FIXED (유저 확정): the label is the mode name, and letting
/// the button breathe with the text meant every blend change shoved the
/// bars beside it sideways. Long names ellipsize instead.
class _BlendModeControl extends StatelessWidget {
  const _BlendModeControl({required this.brushTool});

  final ValueNotifier<BrushToolState> brushTool;

  /// Wider than the label needs on average, so the common modes read whole
  /// and only the long ones are cut.
  static const double _buttonWidth = 116;
  static const double _lockWidth = 32;

  /// What the whole group occupies — held constant across BOTH states, so
  /// picking up the eraser (which retires the lock, since the eraser is not
  /// making a blend choice) does not slide the bars sideways either. Same
  /// reason the button width is fixed.
  static const double _groupWidth = _buttonWidth + _lockWidth;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BrushToolState>(
      valueListenable: brushTool,
      builder: (context, state, _) {
        final theme = Theme.of(context);
        final language = AppText.settings.value.programLanguage;
        // The ERASER tool locks it to 消去/Erase — the eraser IS the erase
        // blend — and that is not a blend CHOICE, so the flyout stands down.
        final toolLocked = state.tool == CanvasTool.eraser;
        // The brush's own pin, if it has one; distinct from the eraser's.
        final pinned = state.lockedBlendMode;
        final mode = toolLocked
            ? BrushBlendMode.erase
            : state.effectiveBlendMode;
        if (toolLocked) {
          return SizedBox(
            width: _groupWidth,
            child: Container(
              key: const ValueKey<String>('brush-tool-blend-locked'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      mode.labelFor(language),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.lock_outline,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _buttonWidth,
              child: PanelFlyoutButton(
                key: const ValueKey<String>('brush-tool-blend-menu-button'),
                label: mode.labelFor(language),
                tooltip: AppText.strings.brBlendMode,
                // A LOCK THAT LOCKS (유저, R4 #12: 잠궜는데 바꿀 수 있으면
                // 잠금이 아니잖아).
                //
                // ⛔The pin used to stay editable, and picking a mode while
                // pinned rewrote the PIN — so the one control that says "this
                // brush is fixed to Multiply" was also the control that
                // changed which mode it was fixed to. Two verbs on one
                // button, and the quieter one was the one the padlock had
                // just promised. Unlock, choose, lock again; the lock is
                // one tap away and it is right beside this.
                enabled: pinned == null,
                // `expand` is what makes the fixed box hold: the label
                // becomes Flexible inside it, so it ellipsizes rather than
                // overflowing the width the strip budgeted.
                expand: true,
                entriesBuilder: () => [
                  for (final candidate in BrushBlendMode.values)
                    PanelFlyoutItem(
                      keyValue: 'brush-tool-blend-${candidate.name}',
                      label: candidate.labelFor(language),
                      checked: candidate == mode,
                      onSelected: () =>
                          brushTool.value = state.copyWith(
                            brushBlendMode: candidate,
                          ),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: _lockWidth,
              child: IconButton(
                key: const ValueKey<String>('brush-tool-blend-lock-toggle'),
                icon: Icon(
                  pinned == null
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                  size: 16,
                ),
                color: pinned == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
                tooltip: AppText.strings.brBlendLock,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: _lockWidth,
                  height: _lockWidth,
                ),
                // The 32px box IS the target: M3 would otherwise inflate to
                // 48 and blow the width this group promised to hold.
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                // Locking captures whatever is showing, so the stroke does
                // not change under you at the moment you pin it.
                onPressed: () => brushTool.value = pinned == null
                    ? state.copyWith(lockedBlendMode: mode)
                    : state.copyWith(clearBlendLock: true),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A strip button that opens a popover — the same square the tool rail
/// wears, because the strip IS the rail turned sideways (유저 확정: 상단
/// 띠는 사이드 띠와 같은 디자인).
/// The FLOOR switch (유저 확정): which panel the whole app is lying on.
///
/// Not a panel-visibility toggle — the canvas and the media viewer are both
/// full-page surfaces you look AT, and only one of them can be the bottom
/// layer, so this reads as a two-position switch rather than as two things
/// you can open. Its label and icon come from each panel's own tab
/// definition, so there is no second place for them to drift.
class _FloorSwitch extends StatelessWidget {
  const _FloorSwitch({required this.panelsMenu});

  final WorkspacePanelsMenuController panelsMenu;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: panelsMenu,
      builder: (context, _) {
        final tabs = panelsMenu.floorTabs;
        if (tabs.isEmpty) {
          // The workspace has not attached yet (first frame, or a test that
          // mounts the strip alone).
          return const SizedBox.shrink();
        }
        final active = panelsMenu.floorTabId;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tab in tabs)
              RailButton(
                keyValue: 'top-strip-floor-${tab.tabId}',
                tooltip: tab.label,
                icon: tab.icon,
                selected: tab.tabId == active,
                onPressed: () => panelsMenu.selectFloorTab(tab.tabId),
              ),
          ],
        );
      },
    );
  }
}

class _StripPopoverButton extends StatelessWidget {
  const _StripPopoverButton({
    required this.keyValue,
    required this.tooltip,
    required this.icon,
    required this.entriesBuilder,
  });

  final String keyValue;
  final String tooltip;
  final IconData icon;
  final List<PanelFlyoutEntry> Function() entriesBuilder;

  @override
  Widget build(BuildContext context) {
    return RailButton(
      keyValue: keyValue,
      tooltip: tooltip,
      icon: icon,
      selected: false,
      // This element wraps the button alone, so its box IS the anchor the
      // flyout measures.
      onPressed: () =>
          unawaited(showPanelFlyout(context, entries: entriesBuilder())),
    );
  }
}

/// PEN-12 #8: the shared Save As flow — the File menu and the
/// unsaved-autosave prompt land in the same picker + writer. SAVE-1: a
/// never-saved project's picker starts in the app's project home (앱
/// 문서 폴더); a saved one starts beside its current file.
/// PICK-2: whether the project pickers ask for a FOLDER rather than a file.
///
/// Windows and Linux hand out real paths with no permission attached, so a
/// file dialog is the whole story there and nothing changes. The other three
/// need a grant the app has to hold — and because a grant covers exactly
/// what was picked, picking the project FILE would leave its sibling
/// `.assets/` folder and its autosave sidecar outside the grant.
///
/// macOS sits with iPad rather than with Windows here, which is the part
/// that surprises: it is sandboxed, so a file selection extends the sandbox
/// to that file and nothing beside it.
@visibleForTesting
bool? debugUseFolderPickerOverride;

bool get useFolderPickerForProjects =>
    debugUseFolderPickerOverride ??
    (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// A chosen project, plus the token that reopens its folder next launch.
///
/// The bookmark travels with the path because the recent-projects list is
/// worthless without it on Apple platforms — a stored path outside the app
/// container is refused after relaunch unless the app can produce the
/// security scope it was granted.
typedef ProjectPick = ({String path, String? folderBookmark});

/// Open: a folder grant, then which project inside it.
///
/// The chooser is skipped when the folder holds exactly one project, so the
/// common single-project folder costs no extra tap.
@visibleForTesting
Future<ProjectPick?> pickProjectToOpen(BuildContext context) async {
  if (!useFolderPickerForProjects) {
    final path = await EditorTopStrip._defaultOpenPicker();
    return path == null ? null : (path: path, folderBookmark: null);
  }
  // The SYNC twin on purpose: async `dart:io` never completes under the
  // widget-test clock, and this is the first line of the open flow — awaiting
  // the async one here would make the whole flow untestable.
  final grant = await pickFolderGrantForUser(
    context,
    initialDirectory: ensuredAppDocumentsDirectorySync(),
  );
  if (grant?.path == null || !context.mounted) {
    return null;
  }
  final chosen = await showProjectChooser(
    context,
    entries: anicelProjectsIn(grant!.path!),
  );
  return chosen == null
      ? null
      : (path: chosen, folderBookmark: grant.bookmark);
}

/// Save As: a folder grant, then a name.
///
/// The name is asked in-app because iOS HAS no save panel — Apple never
/// shipped one, and every iOS app that writes a document asks for the name
/// itself. Confirming an overwrite is asked here too, for the same reason:
/// the system dialog that would normally do it is not in this flow.
@visibleForTesting
Future<ProjectPick?> pickProjectSaveTarget(
  BuildContext context,
  String suggestedName,
  String initialDirectory,
) async {
  if (!useFolderPickerForProjects) {
    final path = await _defaultAnicelSavePicker(suggestedName, initialDirectory);
    return path == null ? null : (path: path, folderBookmark: null);
  }
  final grant = await pickFolderGrantForUser(
    context,
    initialDirectory: initialDirectory,
  );
  final folder = grant?.path;
  if (folder == null || !context.mounted) {
    return null;
  }
  final strings = AppText.strings;
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AppPromptDialog(
      windowKey: const ValueKey<String>('project-save-name-dialog'),
      title: strings.fileSaveTitle,
      titleIcon: Icons.save_outlined,
      fieldLabel: strings.fileNameLabel,
      initialValue: suggestedName,
      confirmLabel: strings.commonSave,
      emptyError: strings.fileNameEmpty,
      fieldKey: const ValueKey<String>('project-save-name-field'),
      cancelKey: const ValueKey<String>('project-save-name-cancel'),
      confirmKey: const ValueKey<String>('project-save-name-confirm'),
    ),
  );
  if (name == null || name.isEmpty || !context.mounted) {
    return null;
  }
  var target = '$folder/$name';
  if (!target.toLowerCase().endsWith(anicelProjectSuffix)) {
    target = '$target$anicelProjectSuffix';
  }
  if (!File(target).existsSync()) {
    return (path: target, folderBookmark: grant!.bookmark);
  }
  final replace = await showDialog<bool>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('project-save-replace-dialog'),
      title: strings.replaceFileTitle,
      titleIcon: Icons.warning_amber_outlined,
      message: strings.replaceFileMessageTemplate.replaceAll('{name}', name),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('project-save-replace-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppWindowAction(
          label: strings.commonReplace,
          actionKey: const ValueKey<String>('project-save-replace-confirm'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return replace == true
      ? (path: target, folderBookmark: grant!.bookmark)
      : null;
}

Future<void> promptSaveProjectAs(
  BuildContext context,
  EditorSessionManager session, {
  Future<String?> Function(String suggestedName)? savePicker,
}) async {
  final suggested =
      '${sanitizeExportFileComponent(session.repository.requireProject().name)}'
      '$anicelProjectSuffix';
  final currentPath = session.projectFilePath?.replaceAll('\\', '/');
  final initialDirectory = currentPath != null && currentPath.contains('/')
      ? currentPath.substring(0, currentPath.lastIndexOf('/'))
      : await ensuredAppDocumentsDirectory();
  if (!context.mounted) {
    return;
  }
  final ProjectPick? pick;
  if (savePicker != null) {
    final injected = await savePicker(suggested);
    pick = injected == null ? null : (path: injected, folderBookmark: null);
  } else {
    pick = await pickProjectSaveTarget(context, suggested, initialDirectory);
  }
  if (pick == null || !context.mounted) {
    return;
  }
  var path = pick.path;
  if (!path.toLowerCase().endsWith(anicelProjectSuffix)) {
    path = '$path$anicelProjectSuffix';
  }
  try {
    await session.saveProjectToFile(path);
    recordRecentProject(
      RecentProject(path: path, folderBookmark: pick.folderBookmark),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

Future<String?> _defaultAnicelSavePicker(
  String suggestedName,
  String initialDirectory,
) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    initialDirectory: initialDirectory,
    acceptedTypeGroups: const [FileTypeGroups.anicelProject],
  );
  return location?.path;
}
