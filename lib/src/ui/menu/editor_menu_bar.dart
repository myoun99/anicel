import 'dart:async';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/cut_id.dart';
import '../../services/persistence/anicel_project_archive.dart';
import '../../services/persistence/app_documents.dart';
import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/project_autosave_service.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/canvas_size_dialog.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../dialogs/convert_to_linked_cut_dialog.dart';
import '../dialogs/delete_layer_dialog.dart';
import '../dialogs/file_browser_dialog.dart';
import '../dialogs/preferences_dialog.dart';
import '../canvas/paper_background.dart' show alphaPreviewEnabled;
import '../debug/input_inspector.dart';
import '../debug/measurement_mode.dart';
import '../dialogs/project_background_dialog.dart';
import '../dialogs/rename_cut_dialog.dart';
import '../dialogs/rename_layer_dialog.dart';
import '../dialogs/se_name_tag_dialog.dart';
import '../editor_session_manager.dart';
import '../export/ae_keyframe_data.dart';
import '../../services/persistence/app_export_settings_store.dart';
import '../export/export_dialog.dart';
import '../import/import_dialog.dart';
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
    this.anicelOpenFilePicker,
    this.anicelSaveFilePicker,
  });

  final EditorSessionManager session;
  final WorkspacePanelsMenuController panelsMenu;

  /// Injectable for tests; default to the platform file dialogs.
  final Future<String?> Function()? anicelOpenFilePicker;
  final Future<String?> Function(String suggestedName)? anicelSaveFilePicker;

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
      // Every entry localizes HERE, by the id it is already keyed with —
      // 42 menu items in one place, with the English staying at the call
      // sites where the menu is actually authored.
      child: Text(AppText.strings.menuLabel(id, label)),
    );
  }

  // --- File -----------------------------------------------------------------

  static Future<String?> _defaultOpenPicker() async {
    final file = await openFile(
      // SAVE-1: pickers start in the app's project home (앱 문서 폴더).
      initialDirectory: await ensuredAppDocumentsDirectory(),
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Anicel project', extensions: [anicelProjectExtension]),
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
      label: 'Save as…',
      onPressed: () => unawaited(_saveProjectAs(context)),
    ),
    const Divider(height: 8),
    _item(
      id: 'file-project-background',
      label: 'Project background…',
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
      id: 'file-import',
      label: 'Import / Place…',
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
      label: 'Copy frame',
      onPressed: session.canCopyFrameAtCurrentFrame
          ? session.copyFrameAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-paste-linked-frame',
      label: 'Paste linked frame',
      onPressed: session.canPasteLinkedFrameAtCurrentFrame
          ? session.pasteLinkedFrameAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-new-drawing',
      label: 'New drawing at frame',
      onPressed: session.canCreateDrawingAtCurrentFrame
          ? session.createDrawingAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-delete-cell',
      label: 'Delete cell',
      onPressed: session.canDeleteCellAtCurrentFrame
          ? session.deleteCellAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-cut-exposure',
      label: 'Cut exposure',
      onPressed: session.canCutExposureAtCurrentFrame
          ? session.cutExposureAtCurrentFrame
          : null,
    ),
    _item(
      id: 'edit-toggle-mark',
      label: 'Toggle mark',
      onPressed: session.canToggleMarkAtCurrentFrame
          ? session.toggleMarkAtCurrentFrame
          : null,
    ),
    const Divider(height: 8),
    _item(
      id: 'edit-keyboard-shortcuts',
      label: 'Keyboard shortcuts…',
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
    // R3b: the BACKDROP plane rendered as the alpha checkerboard —
    // display-only, showing exactly what an alpha export leaves open.
    KeyedSubtree(
      key: const ValueKey<String>('menu-edit-alpha-preview'),
      child: CheckboxMenuButton(
        value: alphaPreviewEnabled.value,
        onChanged: (checked) {
          alphaPreviewEnabled.value = checked == true;
        },
        child: Text(AppText.strings.menuAlphaPreview),
      ),
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
    _item(id: 'cut-new', label: 'New cut', onPressed: session.createCut),
    _item(
      id: 'cut-duplicate',
      label: 'Duplicate cut',
      onPressed: session.duplicateActiveCut,
    ),
    // 겸용컷 (the link system, L4): same pictures, own timing.
    _item(
      id: 'cut-create-linked',
      label: 'Create linked cut',
      onPressed: session.activeCutOrNull != null
          ? session.createLinkedCutFromActiveCut
          : null,
    ),
    _item(
      id: 'cut-convert-linked',
      label: 'Convert to linked cut…',
      onPressed:
          session.activeCutOrNull != null &&
              session.convertToLinkedCutCandidates.isNotEmpty
          ? () => unawaited(_convertActiveCutToLinked(context))
          : null,
    ),
    _item(
      id: 'cut-rename',
      label: 'Rename cut…',
      onPressed: () => unawaited(_renameActiveCut(context)),
    ),
    _item(
      id: 'cut-canvas-size',
      label: 'Canvas size…',
      onPressed: () => unawaited(_resizeActiveCutCanvas(context)),
    ),
    const Divider(height: 8),
    _item(
      id: 'cut-move-left',
      label: 'Move cut left',
      onPressed: session.canMoveActiveCutLeft
          ? session.moveActiveCutLeft
          : null,
    ),
    _item(
      id: 'cut-move-right',
      label: 'Move cut right',
      onPressed: session.canMoveActiveCutRight
          ? session.moveActiveCutRight
          : null,
    ),
    const Divider(height: 8),
    // Relocated from the retired camera panel (R11-⑤): bakes the active
    // cut's camera work as AE keyframe data on the clipboard.
    _item(
      id: 'cut-copy-ae-camera',
      label: 'Copy camera AE keyframes',
      onPressed: () => _copyCameraAeKeyframes(context),
    ),
    const Divider(height: 8),
    _item(
      id: 'cut-delete',
      label: 'Delete cut',
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

  /// The SE row's on-canvas name tag (R5b): opens on what the row draws
  /// TODAY (its configured tag, or the stacked default), and Delete
  /// resets it back to that default.
  Future<void> _editSeNameTag(BuildContext context) async {
    final layer = session.activeLayer;
    final current = session.activeSeNameTagOrDefault;
    if (layer == null || current == null) {
      return;
    }
    final result = await showDialog<SeNameTagDialogResult>(
      context: context,
      builder: (context) =>
          SeNameTagDialog(initialTag: current, rowName: layer.name),
    );
    if (!context.mounted || result == null) {
      return;
    }
    session.setActiveSeNameTag(result.tag);
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
    _item(id: 'layer-add', label: 'Add layer', onPressed: session.addLayer),
    // Attach layers (W5 / UI-R21 #3): own cels riding the base's FX.
    // FREE = own timeline like a normal layer; SYNCED = the ghost mirror
    // riding the base's exposures.
    _item(
      id: 'layer-add-attach-free-above',
      label: 'Add attach free layer above',
      onPressed: session.canAddAttachedLayerToActive
          ? () => session.addAttachedLayer(
              AttachedPlacement.above,
              mode: AttachedMode.free,
            )
          : null,
    ),
    _item(
      id: 'layer-add-attach-free-below',
      label: 'Add attach free layer below',
      onPressed: session.canAddAttachedLayerToActive
          ? () => session.addAttachedLayer(
              AttachedPlacement.below,
              mode: AttachedMode.free,
            )
          : null,
    ),
    _item(
      id: 'layer-add-attach-above',
      label: 'Add attach synced layer above',
      onPressed: session.canAddAttachedLayerToActive
          ? () => session.addAttachedLayer(AttachedPlacement.above)
          : null,
    ),
    _item(
      id: 'layer-add-attach-below',
      label: 'Add attach synced layer below',
      onPressed: session.canAddAttachedLayerToActive
          ? () => session.addAttachedLayer(AttachedPlacement.below)
          : null,
    ),
    _item(
      id: 'layer-duplicate',
      label: 'Duplicate layer',
      onPressed: session.duplicateActiveLayer,
    ),
    // 링크 복제 / 독립시키기 (L4): the duplicate SHARES its pictures
    // ("이름이 같으면 같은 그림"); unlink forks them back out.
    _item(
      id: 'layer-link-duplicate',
      label: 'Link duplicate layer',
      onPressed: session.canLinkDuplicateActiveLayer
          ? session.linkDuplicateActiveLayer
          : null,
    ),
    _item(
      id: 'layer-unlink',
      label: 'Unlink layer',
      onPressed: session.canUnlinkActiveLayer
          ? session.unlinkActiveLayer
          : null,
    ),
    // 폴더 (L5): folds the active layer's whole attach group; rename/
    // dissolve live on the folder row's context menu.
    _item(
      id: 'layer-group-into-folder',
      label: 'Group into folder',
      onPressed: session.canGroupActiveLayerIntoFolder
          ? session.groupActiveLayerIntoFolder
          : null,
    ),
    // 공정 폴더: wraps the active ATTACH row in an organizer folder inside
    // its group ([연출]/[작감]… — adding from a row inside one lands its
    // siblings there too). Flat: rows already inside an organizer refuse.
    _item(
      id: 'layer-group-attach-into-folder',
      label: 'New attach folder',
      onPressed: session.canGroupActiveAttachIntoFolder
          ? session.groupActiveAttachIntoFolder
          : null,
    ),
    _item(
      id: 'layer-rename',
      label: 'Rename layer…',
      onPressed: () => unawaited(_renameActiveLayer(context)),
    ),
    // RASTERIZE (§6-f): the one verb for every media-reference layer —
    // pixels stay (they were always the cels), the link lets go.
    _item(
      id: 'layer-rasterize',
      label: 'Rasterize layer',
      onPressed: session.canRasterizeActiveLayer
          ? session.rasterizeActiveLayer
          : null,
    ),
    // The SE row's on-canvas name tag (R5b): placement and look — the
    // TEXT stays the block's own name/dialogue.
    _item(
      id: 'layer-se-name-tag',
      label: 'SE name tag…',
      onPressed: session.canEditActiveSeNameTag
          ? () => unawaited(_editSeNameTag(context))
          : null,
    ),
    const Divider(height: 8),
    _item(
      id: 'layer-copy',
      label: 'Copy layer',
      onPressed: session.copyActiveLayer,
    ),
    _item(
      id: 'layer-paste',
      label: 'Paste layer',
      onPressed: session.hasLayerClipboard
          ? session.pasteLayerFromClipboard
          : null,
    ),
    const Divider(height: 8),
    _item(
      id: 'layer-delete',
      label: 'Delete layer…',
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
      // Untabled by id on purpose: this label flips with playback state,
      // so it arrives already localized and the id lookup falls through.
      label: session.playback.isActive && session.playback.isPlaying
          ? AppText.strings.menuPause
          : AppText.strings.menuPlay,
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
      label: 'Play all cuts',
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
      label: 'Reset workspace layout',
      onPressed: panelsMenu.canResetLayout ? panelsMenu.resetLayout : null,
    ),
  ];

  // --- Help -----------------------------------------------------------------

  List<Widget> _helpItems(BuildContext context) => [
    _item(
      id: 'help-about',
      label: 'About Anicel',
      onPressed: () =>
          showAboutDialog(context: context, applicationName: 'Anicel'),
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
          child: Text(AppText.strings.menuBarFile),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-edit'),
          style: topLevelStyle,
          menuChildren: _editItems(context),
          child: Text(AppText.strings.menuBarEdit),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-cut'),
          style: topLevelStyle,
          menuChildren: _cutItems(context),
          child: Text(AppText.strings.menuBarCut),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-layer'),
          style: topLevelStyle,
          menuChildren: _layerItems(context),
          child: Text(AppText.strings.menuBarLayer),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-playback'),
          style: topLevelStyle,
          menuChildren: _playbackItems(context),
          child: Text(AppText.strings.menuBarPlayback),
        ),
        // The Panels menu of old (same item keys): every panel with its
        // visibility — closed (X-ed) panels reopen from here, PS
        // Window-menu style.
        SubmenuButton(
          key: const ValueKey<String>('panels-menu-button'),
          style: topLevelStyle,
          menuChildren: _windowItems(context),
          child: Text(AppText.strings.menuBarWindow),
        ),
        SubmenuButton(
          key: const ValueKey<String>('menu-help'),
          style: topLevelStyle,
          menuChildren: _helpItems(context),
          child: Text(AppText.strings.menuBarHelp),
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
