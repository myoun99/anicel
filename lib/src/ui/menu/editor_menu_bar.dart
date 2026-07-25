import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/cut_id.dart';
import '../../services/persistence/app_documents.dart';
import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/project_autosave_service.dart';
import '../dialogs/canvas_size_dialog.dart';
import '../dialogs/convert_to_linked_cut_dialog.dart';
import '../dialogs/delete_layer_dialog.dart';
import '../dialogs/file_browser_dialog.dart';
import '../dialogs/preferences_dialog.dart';
import '../debug/input_inspector.dart';
import '../debug/measurement_mode.dart';
import '../dialogs/project_background_dialog.dart';
import '../dialogs/rename_cut_dialog.dart';
import '../dialogs/rename_layer_dialog.dart';
import '../editor_session_manager.dart';
import '../export/ae_keyframe_data.dart';
import '../../services/persistence/app_export_settings_store.dart';
import '../export/export_dialog.dart';
import '../export/export_plan.dart' show sanitizeExportFileComponent;
import '../panels/workspace_panels_menu.dart';
import '../playback/canvas_playback_controller.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_bindings.dart';
import '../shortcuts/shortcut_settings_dialog.dart';
import '../storyboard_playhead_mapping.dart';

/// The editor's top menu bar (the CSP/Photoshop File-Edit-… language),
/// organizing every session command in one discoverable place. Items call
/// the SAME session APIs the panels wire — the menu adds no new command
/// paths, only entrances.
///
/// Forward slots: File > Open/Save/Save As stay disabled until project
/// persistence lands (P3). Edit > Keyboard Shortcuts… opens the P1
/// registry's settings dialog; the registry also feeds
/// [MenuItemButton.shortcut] labels through [_item].
class EditorMenuBar extends StatelessWidget {
  const EditorMenuBar({
    super.key,
    required this.session,
    required this.panelsMenu,
    this.shortcuts,
    this.qapOpenFilePicker,
    this.qapSaveFilePicker,
  });

  final EditorSessionManager session;
  final WorkspacePanelsMenuController panelsMenu;

  /// Injectable for tests; default to the platform file dialogs.
  final Future<String?> Function()? qapOpenFilePicker;
  final Future<String?> Function(String suggestedName)? qapSaveFilePicker;

  /// The customizable shortcut bindings (P1); null hides the shortcut
  /// labels and disables the settings entry (focused widget tests).
  final EditorShortcutBindings? shortcuts;

  /// The LIVE shortcut label for a registry action (menu items show the
  /// primary activator).
  MenuSerializableShortcut? _shortcutFor(String actionId) =>
      shortcuts?.primaryActivatorFor(actionId);

  /// One menu entry. The single funnel every item goes through so the P1
  /// shortcut registry can later inject `shortcut:` labels without
  /// restructuring the menus.
  MenuItemButton _item({
    required String id,
    required String label,
    VoidCallback? onPressed,
    MenuSerializableShortcut? shortcut,
  }) {
    return MenuItemButton(
      key: ValueKey<String>('menu-$id'),
      onPressed: onPressed,
      shortcut: shortcut,
      child: Text(label),
    );
  }

  // --- File -----------------------------------------------------------------

  static Future<String?> _defaultOpenPicker() async {
    final file = await openFile(
      // SAVE-1: pickers start in the app's project home (앱 문서 폴더).
      initialDirectory: await ensuredAppDocumentsDirectory(),
      acceptedTypeGroups: const [
        XTypeGroup(label: 'QuickAnimaker project', extensions: ['qap']),
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
    final path = qapOpenFilePicker != null
        ? await qapOpenFilePicker!()
        // SAVE-1c: mobile routes to the in-app browser (the OS pickers
        // hand out content URIs the real-path save stack cannot edit in
        // place); desktop keeps the OS dialog.
        : useInAppBrowserForPickers
        ? await showQapFileBrowser(context, mode: FileBrowserMode.open)
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
        builder: (context) => AlertDialog(
          title: const Text('Recover autosaved changes?'),
          content: const Text(
            'A newer autosave exists for this project. Recover it, or open '
            'the file as last saved?',
          ),
          actions: [
            TextButton(
              key: const ValueKey<String>('recover-open-saved-button'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Open Saved'),
            ),
            TextButton(
              key: const ValueKey<String>('recover-autosave-button'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Recover'),
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
      promptSaveProjectAs(context, session, savePicker: qapSaveFilePicker);

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

  List<Widget> _fileItems(BuildContext context) => [
    _item(
      id: 'file-open',
      label: 'Open…',
      onPressed: () => unawaited(_openProject(context)),
    ),
    _item(
      id: 'file-save',
      label: 'Save',
      onPressed: () => unawaited(_saveProject(context)),
    ),
    _item(
      id: 'file-save-as',
      label: 'Save As…',
      onPressed: () => unawaited(_saveProjectAs(context)),
    ),
    const Divider(height: 8),
    _item(
      id: 'file-project-background',
      label: 'Project Background…',
      onPressed: () {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (context) => ProjectBackgroundDialog(session: session),
          ),
        );
      },
    ),
    const Divider(height: 8),
    _item(
      id: 'file-export',
      label: 'Export…',
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

  // --- Edit -----------------------------------------------------------------

  List<Widget> _editItems(BuildContext context) => [
    _item(
      id: 'edit-undo',
      label: 'Undo',
      onPressed: session.canUndo ? session.undo : null,
      shortcut: _shortcutFor(EditorActionIds.undo),
    ),
    _item(
      id: 'edit-redo',
      label: 'Redo',
      onPressed: session.canRedo ? session.redo : null,
      shortcut: _shortcutFor(EditorActionIds.redo),
    ),
    const Divider(height: 8),
    _item(
      id: 'edit-copy-frame',
      label: 'Copy Frame',
      onPressed: session.canCopyFrameAtCurrentFrame
          ? session.copyFrameAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-paste-linked-frame',
      label: 'Paste Linked Frame',
      onPressed: session.canPasteLinkedFrameAtCurrentFrame
          ? session.pasteLinkedFrameAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-new-drawing',
      label: 'New Drawing at Frame',
      onPressed: session.canCreateDrawingAtCurrentFrame
          ? session.createDrawingAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-delete-cell',
      label: 'Delete Cell',
      onPressed: session.canDeleteCellAtCurrentFrame
          ? session.deleteCellAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-cut-exposure',
      label: 'Cut Exposure',
      onPressed: session.canCutExposureAtCurrentFrame
          ? session.cutExposureAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-toggle-mark',
      label: 'Toggle Mark',
      onPressed: session.canToggleMarkAtCurrentFrame
          ? session.toggleMarkAtCurrentFrame
          : null,
    ),
    const Divider(height: 8),
    _item(
      id: 'edit-keyboard-shortcuts',
      label: 'Keyboard Shortcuts…',
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
      onPressed: () {
        unawaited(showPreferencesDialog(context, session: session));
      },
    ),
    // The pen program's diagnosis overlay (PEN-1): toggles the live
    // pointer-event readout — kind/pressure/tilt straight from the
    // platform, the driver-vs-app separator.
    _item(
      id: 'edit-input-inspector',
      label: InputInspector.visible.value
          ? 'Hide Input Inspector'
          : 'Input Inspector',
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
      label: MeasurementMode.frameTimingOverlay.value
          ? 'Hide Frame Timing Overlay'
          : 'Frame Timing Overlay',
      onPressed: () {
        MeasurementMode.frameTimingOverlay.value =
            !MeasurementMode.frameTimingOverlay.value;
      },
    ),
  ];

  // --- Cut ------------------------------------------------------------------

  Future<void> _renameActiveCut(BuildContext context) async {
    final cut = session.activeCutOrNull;
    if (cut == null) {
      return; // Gap state: no cut to rename.
    }
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => RenameCutDialog(initialName: cut.name),
    );
    if (!context.mounted || nextName == null || nextName.trim().isEmpty) {
      return;
    }
    session.renameActiveCut(nextName);
  }

  Future<void> _resizeActiveCutCanvas(BuildContext context) async {
    final cut = session.activeCutOrNull;
    if (cut == null) {
      return; // Gap state: no cut canvas to resize.
    }
    final request = await showDialog<CanvasResizeRequest>(
      context: context,
      builder: (context) => CanvasSizeDialog(initialSize: cut.canvasSize),
    );
    if (!context.mounted || request == null) {
      return;
    }
    session.resizeActiveCutCanvas(request.size, anchor: request.anchor);
  }

  List<Widget> _cutItems(BuildContext context) => [
    _item(id: 'cut-new', label: 'New Cut', onPressed: session.createCut),
    _item(
      id: 'cut-duplicate',
      label: 'Duplicate Cut',
      onPressed: session.duplicateActiveCut,
    ),
    // 겸용컷 (the link system, L4): same pictures, own timing.
    _item(
      id: 'cut-create-linked',
      label: 'Create Linked Cut',
      onPressed: session.activeCutOrNull != null
          ? session.createLinkedCutFromActiveCut
          : null,
    ),
    _item(
      id: 'cut-convert-linked',
      label: 'Convert to Linked Cut…',
      onPressed:
          session.activeCutOrNull != null &&
              session.convertToLinkedCutCandidates.isNotEmpty
          ? () => unawaited(_convertActiveCutToLinked(context))
          : null,
    ),
    _item(
      id: 'cut-rename',
      label: 'Rename Cut…',
      onPressed: () => unawaited(_renameActiveCut(context)),
    ),
    _item(
      id: 'cut-canvas-size',
      label: 'Canvas Size…',
      onPressed: () => unawaited(_resizeActiveCutCanvas(context)),
    ),
    const Divider(height: 8),
    _item(
      id: 'cut-move-left',
      label: 'Move Cut Left',
      onPressed: session.canMoveActiveCutLeft
          ? session.moveActiveCutLeft
          : null,
    ),
    _item(
      id: 'cut-move-right',
      label: 'Move Cut Right',
      onPressed: session.canMoveActiveCutRight
          ? session.moveActiveCutRight
          : null,
    ),
    const Divider(height: 8),
    // Relocated from the retired camera panel (R11-⑤): bakes the active
    // cut's camera work as AE keyframe data on the clipboard.
    _item(
      id: 'cut-copy-ae-camera',
      label: 'Copy Camera AE Keyframes',
      onPressed: () => _copyCameraAeKeyframes(context),
    ),
    const Divider(height: 8),
    _item(
      id: 'cut-delete',
      label: 'Delete Cut',
      onPressed: session.deleteActiveCut,
    ),
  ];

  Future<void> _convertActiveCutToLinked(BuildContext context) async {
    final activeCut = session.activeCutOrNull;
    if (activeCut == null) {
      return;
    }
    final targetCutId = await showDialog<CutId>(
      context: context,
      builder: (context) => ConvertToLinkedCutDialog(
        activeCutName: activeCut.name,
        candidates: session.convertToLinkedCutCandidates,
        previewOf: session.convertToLinkedCutPreviewData,
      ),
    );
    if (!context.mounted || targetCutId == null) {
      return;
    }
    session.convertActiveCutToLinked(targetCutId);
  }

  /// Bakes per frame; paste onto the canvas-sequence layer in a
  /// camera-frame-sized comp.
  void _copyCameraAeKeyframes(BuildContext context) {
    final cut = session.activeCutOrNull;
    if (cut == null) {
      return; // Gap state: no camera work to bake.
    }
    final cameraSize = session.cameraFrameSize;
    final text = buildAeTransformKeyframeData(
      framesPerSecond: session.projectFps,
      sourceWidth: cameraSize.width,
      sourceHeight: cameraSize.height,
      samples: bakeCameraAeSamples(
        camera: cut.camera,
        canvasSize: cut.canvasSize,
        frameCount: session.activeCutPlaybackFrameCount,
      ),
    );
    unawaited(Clipboard.setData(ClipboardData(text: text)));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Camera keyframes copied for After Effects.'),
      ),
    );
  }

  // --- Layer ----------------------------------------------------------------

  Future<void> _renameActiveLayer(BuildContext context) async {
    final activeLayer = session.activeLayer;
    if (activeLayer == null) {
      return;
    }
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => RenameLayerDialog(initialName: activeLayer.name),
    );
    if (!context.mounted || nextName == null) {
      return;
    }
    session.renameActiveLayer(nextName);
  }

  Future<void> _deleteActiveLayer(BuildContext context) async {
    final activeLayer = session.activeLayer;
    if (activeLayer == null || !session.canDeleteActiveLayer) {
      return;
    }
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => DeleteLayerDialog(layerName: activeLayer.name),
    );
    if (!context.mounted || shouldDelete != true) {
      return;
    }
    session.deleteActiveLayer();
  }

  List<Widget> _layerItems(BuildContext context) => [
    _item(id: 'layer-add', label: 'Add Layer', onPressed: session.addLayer),
    // Attach layers (W5 / UI-R21 #3): own cels riding the base's FX.
    // FREE = own timeline like a normal layer; SYNCED = the ghost mirror
    // riding the base's exposures.
    _item(
      id: 'layer-add-attach-free-above',
      label: 'Add Attach Free Layer Above',
      onPressed: session.canAddAttachedLayerToActive
          ? () => session.addAttachedLayer(
              AttachedPlacement.above,
              mode: AttachedMode.free,
            )
          : null,
    ),
    _item(
      id: 'layer-add-attach-free-below',
      label: 'Add Attach Free Layer Below',
      onPressed: session.canAddAttachedLayerToActive
          ? () => session.addAttachedLayer(
              AttachedPlacement.below,
              mode: AttachedMode.free,
            )
          : null,
    ),
    _item(
      id: 'layer-add-attach-above',
      label: 'Add Attach Synced Layer Above',
      onPressed: session.canAddAttachedLayerToActive
          ? () => session.addAttachedLayer(AttachedPlacement.above)
          : null,
    ),
    _item(
      id: 'layer-add-attach-below',
      label: 'Add Attach Synced Layer Below',
      onPressed: session.canAddAttachedLayerToActive
          ? () => session.addAttachedLayer(AttachedPlacement.below)
          : null,
    ),
    _item(
      id: 'layer-duplicate',
      label: 'Duplicate Layer',
      onPressed: session.duplicateActiveLayer,
    ),
    // 링크 복제 / 독립시키기 (L4): the duplicate SHARES its pictures
    // ("이름이 같으면 같은 그림"); unlink forks them back out.
    _item(
      id: 'layer-link-duplicate',
      label: 'Link Duplicate Layer',
      onPressed: session.canLinkDuplicateActiveLayer
          ? session.linkDuplicateActiveLayer
          : null,
    ),
    _item(
      id: 'layer-unlink',
      label: 'Unlink Layer',
      onPressed: session.canUnlinkActiveLayer
          ? session.unlinkActiveLayer
          : null,
    ),
    // 폴더 (L5): folds the active layer's whole attach group; rename/
    // dissolve live on the folder row's context menu.
    _item(
      id: 'layer-group-into-folder',
      label: 'Group into Folder',
      onPressed: session.canGroupActiveLayerIntoFolder
          ? session.groupActiveLayerIntoFolder
          : null,
    ),
    _item(
      id: 'layer-rename',
      label: 'Rename Layer…',
      onPressed: () => unawaited(_renameActiveLayer(context)),
    ),
    const Divider(height: 8),
    _item(
      id: 'layer-copy',
      label: 'Copy Layer',
      onPressed: session.copyActiveLayer,
    ),
    _item(
      id: 'layer-paste',
      label: 'Paste Layer',
      onPressed: session.hasLayerClipboard
          ? session.pasteLayerFromClipboard
          : null,
    ),
    const Divider(height: 8),
    _item(
      id: 'layer-delete',
      label: 'Delete Layer…',
      onPressed: session.canDeleteActiveLayer
          ? () => unawaited(_deleteActiveLayer(context))
          : null,
    ),
  ];

  // --- Playback ---------------------------------------------------------------

  void _togglePlayPause() {
    final playback = session.playback;
    if (playback.isActive && playback.isPlaying) {
      playback.pause();
    } else if (playback.isActive) {
      playback.resume();
    } else {
      playback.play(
        scope: PlaybackScope.activeCut,
        startGlobalFrame: session.currentFrameIndex,
      );
    }
  }

  List<Widget> _playbackItems(BuildContext context) => [
    _item(
      id: 'playback-play-pause',
      label: session.playback.isActive && session.playback.isPlaying
          ? 'Pause'
          : 'Play',
      onPressed: _togglePlayPause,
      shortcut: _shortcutFor(EditorActionIds.playbackToggle),
    ),
    _item(
      id: 'playback-stop',
      label: 'Stop',
      onPressed: session.playback.isActive ? session.playback.stop : null,
    ),
    _item(
      id: 'playback-play-all',
      label: 'Play All Cuts',
      onPressed: () {
        session.playback.play(
          scope: PlaybackScope.allCuts,
          startGlobalFrame: storyboardPlayheadFrame(session) ?? 0,
        );
      },
    ),
    const Divider(height: 8),
    KeyedSubtree(
      key: const ValueKey<String>('menu-playback-loop'),
      child: CheckboxMenuButton(
        value: session.playback.loopMode == PlaybackLoopMode.loop,
        onChanged: (checked) {
          session.playback.loopMode = checked == true
              ? PlaybackLoopMode.loop
              : PlaybackLoopMode.once;
        },
        child: const Text('Loop'),
      ),
    ),
  ];

  // --- Window ---------------------------------------------------------------

  List<Widget> _windowItems(BuildContext context) => [
    for (final entry in panelsMenu.entries)
      // KeyedSubtree, not a key on the button: CheckboxMenuButton forwards
      // its key to the inner MenuItemButton, which would make the key
      // match two widgets.
      KeyedSubtree(
        key: ValueKey<String>('panels-menu-item-${entry.tabId}'),
        child: CheckboxMenuButton(
          value: entry.visible,
          onChanged: (_) => panelsMenu.toggle(entry.tabId),
          child: Text(entry.label),
        ),
      ),
    const Divider(height: 8),
    _item(
      id: 'window-reset-layout',
      label: 'Reset Workspace Layout',
      onPressed: panelsMenu.canResetLayout ? panelsMenu.resetLayout : null,
    ),
  ];

  // --- Help -----------------------------------------------------------------

  List<Widget> _helpItems(BuildContext context) => [
    _item(
      id: 'help-about',
      label: 'About QuickAnimaker',
      onPressed: () =>
          showAboutDialog(context: context, applicationName: 'QuickAnimaker'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Compact top-level buttons: the strip is slim and seven menus plus
    // the quick actions must fit ordinary window widths.
    const topLevelStyle = ButtonStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
      minimumSize: WidgetStatePropertyAll(Size(0, 36)),
      visualDensity: VisualDensity.compact,
    );
    return MenuBar(
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      children: [
        SubmenuButton(
          key: const ValueKey<String>('menu-file'),
          style: topLevelStyle,
          menuChildren: _fileItems(context),
          child: const Text('File'),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-edit'),
          style: topLevelStyle,
          menuChildren: _editItems(context),
          child: const Text('Edit'),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-cut'),
          style: topLevelStyle,
          menuChildren: _cutItems(context),
          child: const Text('Cut'),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-layer'),
          style: topLevelStyle,
          menuChildren: _layerItems(context),
          child: const Text('Layer'),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-playback'),
          style: topLevelStyle,
          menuChildren: _playbackItems(context),
          child: const Text('Playback'),
        ),
        // The Panels menu of old (same item keys): every panel with its
        // visibility — closed (X-ed) panels reopen from here, PS
        // Window-menu style.
        SubmenuButton(
          key: const ValueKey<String>('panels-menu-button'),
          style: topLevelStyle,
          menuChildren: _windowItems(context),
          child: const Text('Window'),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-help'),
          style: topLevelStyle,
          menuChildren: _helpItems(context),
          child: const Text('Help'),
        ),
      ],
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
      '${sanitizeExportFileComponent(session.repository.requireProject().name)}.qap';
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
      ? await showQapFileBrowser(
          context,
          mode: FileBrowserMode.saveAs,
          suggestedName: suggested,
          initialDirectory: initialDirectory,
        )
      : await _defaultQapSavePicker(suggested, initialDirectory);
  if (path == null || !context.mounted) {
    return;
  }
  if (!path.toLowerCase().endsWith('.qap')) {
    path = '$path.qap';
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

Future<String?> _defaultQapSavePicker(
  String suggestedName,
  String initialDirectory,
) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    initialDirectory: initialDirectory,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'QuickAnimaker project', extensions: ['qap']),
    ],
  );
  return location?.path;
}
