import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/persistence/anicel_project_archive.dart';
import '../../services/persistence/app_documents.dart';
import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/project_autosave_service.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../brush/brush_tool_state.dart';
import '../brush/tools_panel.dart' show RailButton;
import '../widgets/field_slider.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import '../dialogs/file_browser_dialog.dart';
import '../dialogs/preferences_dialog.dart';
import '../canvas/paper_background.dart' show alphaPreviewEnabled;
import '../debug/input_inspector.dart';
import '../debug/measurement_mode.dart';
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
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Anicel project',
          extensions: [anicelProjectExtension],
        ),
      ],
    );
    return file?.path;
  }

  void _showFileError(BuildContext context, Object error) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('$error')));
  }

  Future<void> _openProject(BuildContext context) async {
    final path = anicelOpenFilePicker != null
        ? await anicelOpenFilePicker!()
        // SAVE-1c: mobile routes to the in-app browser (the OS pickers
        // hand out content URIs the real-path save stack cannot edit in
        // place); desktop keeps the OS dialog.
        : useInAppBrowserForPickers
        ? await showAnicelFileBrowser(context, mode: FileBrowserMode.open)
        : await _defaultOpenPicker();
    if (path == null || !context.mounted) {
      return;
    }
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
    // The third: where the canvas painter had NO picture for a
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
        if (brushTool != null) ...[
          _BrushValueBars(brushTool: brushTool!),
          const SizedBox(width: 4),
        ],
        const SizedBox(width: 3),
      ],
    );
  }
}

/// Size and opacity at the strip's right end.
///
/// Bars rather than value buttons: these are set WHILE drawing, against a
/// test mark on the canvas, and an anchored popover closes on the first
/// pointer-down outside it (R27 #5) — a button would force open-adjust-
/// close-draw every time. [FieldSlider] already puts the name and the
/// number inside the track, so one 140px run says everything.
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
      builder: (context, state, _) => Row(
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
        ],
      ),
    );
  }
}

/// A strip button that opens a popover — the same square the tool rail
/// wears, because the strip IS the rail turned sideways (유저 확정: 상단
/// 띠는 사이드 띠와 같은 디자인).
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
/// SAVE-1c: whether the save/open pickers use the in-app browser — the
/// mobile real-path model's surface. Desktop keeps the OS dialogs.
@visibleForTesting
bool? debugUseInAppBrowserOverride;

bool get useInAppBrowserForPickers =>
    debugUseInAppBrowserOverride ?? (Platform.isAndroid || Platform.isIOS);

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
  var path = savePicker != null
      ? await savePicker(suggested)
      : useInAppBrowserForPickers
      ? await showAnicelFileBrowser(
          context,
          mode: FileBrowserMode.saveAs,
          suggestedName: suggested,
          initialDirectory: initialDirectory,
        )
      : await _defaultAnicelSavePicker(suggested, initialDirectory);
  if (path == null || !context.mounted) {
    return;
  }
  if (!path.toLowerCase().endsWith(anicelProjectSuffix)) {
    path = '$path$anicelProjectSuffix';
  }
  try {
    await session.saveProjectToFile(path);
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
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Anicel project', extensions: [anicelProjectExtension]),
    ],
  );
  return location?.path;
}
