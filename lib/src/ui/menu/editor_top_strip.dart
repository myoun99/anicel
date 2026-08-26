import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';

import '../../services/persistence/anicel_file_service.dart'
    show anicelSnapshotIsOverlay;
import '../../services/audio/audio_conform_pipeline.dart'
    show ProjectAssetLayout;
import '../../services/persistence/anicel_project_archive.dart';
import '../../services/persistence/app_documents.dart';
import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/persistence/folder_grant.dart';
import '../../services/persistence/project_autosave_service.dart';
import '../../services/persistence/recent_projects.dart';
import '../../services/persistence/recent_projects_store.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_progress_dialog.dart';
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
import '../dialogs/folder_pick_flow.dart';
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


  void _showFileError(BuildContext context, Object error) {
    unawaited(
      showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: '$error',
      ),
    );
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
    await _openWithRecovery(context, pick);
  }

  /// Opens [pick], offering autosave recovery first and recording the result.
  ///
  /// Shared with the Recent-projects rows on purpose. When this lived only in
  /// `_openProject`, opening from Recent — which PICK-4 exists to make the
  /// ONE-TAP common case — skipped the recovery prompt entirely: after a
  /// crash the stale file loaded, the first save overwrote it, and the newer
  /// sidecar was never offered. The prompt would have vanished from exactly
  /// the path this round promoted.
  Future<void> _openWithRecovery(BuildContext context, ProjectPick pick) async {
    final path = pick.path;
    // A TVPaint project: its clips land as new cuts in the CURRENT
    // project — nothing is discarded, so no unsaved-work gate, and no
    // recovery/recents machinery (there is no .anicel here to track).
    if (path.toLowerCase().endsWith('.tvpp')) {
      final warnings = await session.importTvpp(tvppPath: path);
      if (!context.mounted) {
        return;
      }
      if (warnings == null) {
        _showFileError(
          context,
          const FormatException('TVPaint 프로젝트로 읽을 수 없는 파일'),
        );
      } else if (warnings.isNotEmpty) {
        await showAppNotice(
          context,
          windowKey: const ValueKey<String>('tvpp-import-warnings-notice'),
          title: AppText.strings.commonNotice,
          message: warnings.take(6).join('\n'),
        );
      }
      return;
    }
    // Opening ANOTHER project closes this one as surely as the window's X,
    // and this was the one door with no gate: a single Recents tap
    // silently discarded a dirty session (and after F-1 the loss window is
    // the whole autosave interval). Same question, same window, same keys
    // as the exit gate. Reopening the CURRENT project deliberately skips
    // it — that flow's semantics (recovery re-offer, sidecar kept as the
    // one way back) are documented below and a gate in front of them
    // would retire the very sidecar the reopen exists to reach.
    if (session.projectFilePath != path) {
      if (!await ensureUnsavedWorkSettled(context, session) ||
          !context.mounted) {
        return;
      }
    }
    // A newer autosave sidecar offers recovery (crash / sync loss). The
    // snapshot lives in the app-support Recovery folder now, with the
    // legacy beside-the-file spot kept as a read-only candidate — every
    // candidate location is checked, newest wins.
    var openPath = path;
    String? recoverAs;
    String? overlayPath;
    var declinedSidecar = false;
    // Reopening the project that is ALREADY open and dirty. There is no
    // unsaved-changes gate on the open flow, so this reload throws the
    // live edits away on its own — and if a tick had written the sidecar,
    // every cold cel's ref points inside it, which makes it the only copy.
    // Retiring it here would remove the one way back (reopen, answer
    // Recover). Captured before the open, because the open rewrites both
    // of these.
    final reopeningDirtySelf =
        session.projectFilePath == path && session.hasUnsavedChanges;
    final sidecar = AppSave.newestExistingRecoveryFor(path);
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
            // 🚨 The DESTRUCTIVE half, and it did not look like it. Saying
            // "open the saved one" is only half of what this does: the
            // snapshot is deleted on the way past (see the retirement
            // below), because leaving it would re-ask the same question at
            // every open until the next save. That is the right behaviour
            // and it was invisible — a plain second button, worded as a
            // preference between two files, that throws unsaved work away
            // and cannot be undone.
            AppWindowAction(
              label: AppText.strings.recoverOpenSaved,
              actionKey: const ValueKey<String>('recover-open-saved-button'),
              emphasis: AppWindowActionEmphasis.danger,
              tooltip: AppText.strings.recoverOpenSavedHint,
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
        if (anicelSnapshotIsOverlay(sidecar)) {
          // The snapshot holds only what changed since the last save, so
          // the PROJECT is what gets opened and the snapshot goes on top.
          overlayPath = sidecar;
        } else {
          // A build before overlays wrote a complete archive: open it
          // directly, keeping the project as the path to save back to.
          openPath = sidecar;
          recoverAs = path;
        }
      } else {
        declinedSidecar = true;
      }
    }
    try {
      await session.openProjectFromFile(
        openPath,
        recoverAs: recoverAs,
        overlayPath: overlayPath,
      );
      // Recorded AFTER the open succeeds, not at pick time: a file that
      // fails to parse has no business sitting at the top of the menu.
      // `path` rather than `openPath` — recovering from a sidecar still
      // means the user opened the project, not the sidecar.
      recordRecentProject(
        RecentProject(path: path, folderBookmark: pick.folderBookmark),
      );
      if (declinedSidecar && !reopeningDirtySelf) {
        // "Open the saved one" is an answer about THIS sidecar, not a
        // deferral: leaving it alive re-asks the same question at every
        // open until the next manual save. Retired only after the open
        // SUCCEEDS — a file that fails to parse is exactly when the
        // declined sidecar is the user's last copy.
        ProjectAutosaveService.retireSidecarsFor(path);
      }
      // A project from a build that kept its media in a sibling folder.
      // Said AFTER the open, because a file that failed to parse has no
      // media to absorb and the folder is still the only copy.
      final layout = ProjectAssetLayout(path);
      if (layout.hasLegacyAssetsDirectory && context.mounted) {
        final name = layout.assetsDirectory.split('/').last;
        await showAppNotice(
          context,
          windowKey: const ValueKey<String>('legacy-assets-folder-notice'),
          title: AppText.strings.commonNotice,
          message: AppText.strings.projectLegacyAssetsFolder.replaceAll(
            '{name}',
            name,
          ),
        );
      }
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
    await saveProjectShowingProgress(context, session, path);
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
    // The FRESHEST token wins, and it is tracked rather than assumed. Both
    // Apple runners re-mint on every resolve, so an entry that keeps opening
    // keeps its bookmark young instead of decaying until it one day refuses
    // and drops the user into the reconnect flow for no visible reason.
    var bookmark = entry.folderBookmark;
    if (bookmark != null) {
      final grant = await FolderPicker.resolveBookmark(bookmark);
      if (grant.isGranted) {
        // The stored field carries TWO dialects: the reconnect flow mints
        // FOLDER bookmarks, but since PICK-6 both Open and Save As store
        // FILE bookmarks — whose resolved path IS the project. Joining the
        // name onto a file path built '/…/Foo.anicel/Foo.anicel', so every
        // file-bookmarked recent failed its exists-check, wore "Reconnect"
        // for ever, and on iPad dropped Drive projects into the one picker
        // mode Drive refuses. The resolved item's own name is the
        // discriminator.
        final resolved = grant.path!;
        path = resolved.split('/').last == entry.name
            ? resolved
            : '$resolved/${entry.name}';
        bookmark = grant.bookmark ?? bookmark;
      } else {
        storeRecentProjects(
          AppRecent.projects.value.withReconnectNeeded(entry.path),
        );
        if (!context.mounted) {
          return;
        }
        final relinked = await _relink(context, entry);
        if (relinked == null) {
          return;
        }
        path = relinked.path;
        bookmark = relinked.folderBookmark;
      }
    }
    if (!File(path).existsSync()) {
      // No bookmark, or a bookmark that resolved to a folder the project has
      // since left. Offer the picker here too: without this the row wears a
      // "Reconnect" label that nothing honours, and on Android — where there
      // are no bookmarks at all — every row after a revoked storage grant
      // became permanently dead with a "not found" that blamed the wrong
      // thing.
      storeRecentProjects(
        AppRecent.projects.value.withReconnectNeeded(entry.path),
      );
      if (!context.mounted) {
        return;
      }
      final relinked = await _relink(context, entry);
      if (relinked == null) {
        return;
      }
      path = relinked.path;
      bookmark = relinked.folderBookmark;
      if (!File(path).existsSync()) {
        if (context.mounted) {
          _showFileError(context, 'Not found: $path');
        }
        return;
      }
    }
    // The old row goes when the project moved, or the list keeps a dead
    // path beside the live one and both re-flag on the next launch.
    if (path != entry.path) {
      storeRecentProjects(AppRecent.projects.value.without(entry.path));
    }
    if (!context.mounted) {
      return;
    }
    await _openWithRecovery(context, (path: path, folderBookmark: bookmark));
  }

  /// Asks for the project a remembered row has lost track of — with the
  /// FILE picker, the same door Open uses.
  ///
  /// It used to raise the FOLDER picker and rejoin by file name, a shape
  /// left over from the folder-as-permission-unit world. That mode is the
  /// one Google Drive refuses on iOS, so the reconnect flow for a Drive
  /// project was a dead end pointing at the very provider the file-mode
  /// round un-blocked. Picking the file itself needs no name join, works
  /// everywhere file mode works, and hands back the file bookmark the
  /// recents row wants anyway.
  Future<ProjectPick?> _relink(
    BuildContext context,
    RecentProject entry,
  ) async {
    final grants = await pickFileGrantsForUser(
      context,
      acceptedTypeGroups: const [FileTypeGroups.anicelProject],
    );
    final grant = grants.isEmpty ? null : grants.first;
    final path = grant?.path;
    if (path == null) {
      return null;
    }
    return (path: path, folderBookmark: grant!.bookmark);
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
    // The other in-build A/B: the compose knee at 1. ON composes at
    // screen resolution whenever the artwork has more pixels than the
    // screen; OFF is today's canvas-resolution buffer. Same build, same
    // view, two readings — the device evidence stage 6's default flip
    // is waiting on. See [MeasurementMode.kneeAtOne] for the four
    // check-points the A/B is looking at.
    _item(
      id: 'edit-knee-at-one',
      label: 'Screen-Res Buffer',
      icon: Icons.photo_size_select_small_outlined,
      checked: MeasurementMode.kneeAtOne.value,
      onPressed: () {
        MeasurementMode.kneeAtOne.value = !MeasurementMode.kneeAtOne.value;
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
        // TP2: one group, and each member is DIMMED rather than hidden when
        // the armed tool has no use for it (유저: 뭐가 적용되고 뭐가
        // 적용안되는지 몰라할거같으니까 … 적용안되는툴이나 모드면
        // 비활성화시키도록). The table lives on the state — see
        // [BrushToolState.supports] — so the strip cannot disagree with the
        // commit about what a tool reads.
        //
        // Dimmed, never removed: a control that comes and goes is one you
        // have to look for, and the layout would jump every tool switch.
        final sizeOn = state.supports(ToolParameter.size);
        final opacityOn = state.supports(ToolParameter.opacity);
        final pressureOn = state.supports(ToolParameter.pressure);
        Widget pressure(BrushPressureTarget target, String title) {
          return PressureCurveButton(
            keyValue: 'brush-tool-pressure-${target.name}',
            title: title,
            curve: state.pressureCurveFor(target),
            enabled: pressureOn,
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
                valueText: sliderValueText(state.size, unit: ' px'),
                height: _barHeight,
                onChanged: sizeOn
                    ? (value) =>
                          brushTool.value = brushTool.value.copyWith(
                            size: value,
                          )
                    : null,
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
                // TP1: the ACTIVE tool's opacity — the fill and the stamp
                // keep their own, so this bar stops being the brush's alone
                // (유저: 툴마다 기억하게해서 필 툴도 불투명도 설정하면 그거대로
                // 채워지게).
                value: BrushToolState.clampOpacity(state.activeOpacity),
                min: 0,
                max: 1,
                valueText: sliderValueText(state.activeOpacity * 100, unit: '%'),
                height: _barHeight,
                onChanged: opacityOn
                    ? (value) => brushTool.value = brushTool.value
                          .withActiveOpacity(value)
                    : null,
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
        // TP2: tools that composite nothing get the control DIMMED, not an
        // empty gap. It used to be shown for every one of them (a dropdown
        // answering a question nobody downstream asked), then reserved as
        // blank space — and blank space says nothing about why. Dim says
        // "this exists and does not apply here", which is the question the
        // user actually had: 뭐가 적용되고 뭐가 적용안되는지.
        final blendOn = state.supports(ToolParameter.blend);
        // The ERASER tool locks it to 消去/Erase — the eraser IS the erase
        // blend — and that is not a blend CHOICE, so the flyout stands down.
        final toolLocked = state.tool == CanvasTool.eraser;
        // The active tool's own pin, if it has one; distinct from the
        // eraser's.
        final pinned = state.activeBlendLock;
        final mode = state.activeBlendMode;
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
                enabled: blendOn && pinned == null,
                // `expand` is what makes the fixed box hold: the label
                // becomes Flexible inside it, so it ellipsizes rather than
                // overflowing the width the strip budgeted.
                expand: true,
                entriesBuilder: () => [
                  // ONE list for every tool that composites — TS8 유저 법:
                  // 「블렌드모드가 존재한다면 다 공통이야. 지우개만 이레이저만
                  // 남기는거고. 나머지는 이레이저 포함 다 있어.」 The stamp
                  // joining `toolHasBlendMode` is all it took: the eraser's
                  // single-entry case is the `toolLocked` box above, so this
                  // list needs no per-tool filter to obey that law.
                  for (final candidate in BrushBlendMode.values)
                    PanelFlyoutItem(
                      keyValue: 'brush-tool-blend-${candidate.name}',
                      label: candidate.labelFor(language),
                      checked: candidate == mode,
                      // Writes to whichever tool is armed — the button
                      // never names one (유저 확정: 블렌드모드 선택도 툴에
                      // 산다).
                      onSelected: () =>
                          brushTool.value = state.withActiveBlendMode(
                            candidate,
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
                // not change under you at the moment you pin it. Null while
                // the tool composites nothing — pinning a blend it does not
                // read would be pinning nothing (TP2).
                onPressed: blendOn
                    ? () => brushTool.value = state.withActiveBlendLock(
                        pinned == null ? mode : null,
                      )
                    : null,
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
// PICK-6: `useFolderPickerForProjects` and its platform tuple are GONE.
//
// They routed Apple and Android to a FOLDER grant because a grant covers
// exactly what was picked, and a project used to be a file PLUS a sibling
// `.assets/` folder PLUS an autosave sidecar — so granting the file alone
// granted the one item that could not be saved.
//
// The single-file save format removed both siblings, and with them the
// reason. Every platform now picks the project file itself, which also
// unblocks Google Drive: it declines folder mode outright but serves file
// mode fine.

/// A chosen project, plus the token that reopens it next launch.
///
/// The bookmark travels with the path because the recent-projects list is
/// worthless without it on Apple platforms — a stored path outside the app
/// container is refused after relaunch unless the app can produce the
/// security scope it was granted.
typedef ProjectPick = ({String path, String? folderBookmark});

/// Open: the project FILE itself, on every platform.
///
/// PICK-6: the folder grant and the chooser it fed are both gone. A project
/// is one file now — no sibling `.assets/`, no autosave sidecar — so the
/// permission can land on the file, and asking for a folder would be asking
/// for more than the job needs.
///
/// It also unblocks Google Drive, which declines folder mode outright
/// (measured on iOS 26.5.2) but serves file mode fine.
@visibleForTesting
Future<ProjectPick?> pickProjectToOpen(BuildContext context) async {
  final grants = await pickFileGrantsForUser(
    context,
    // TVPaint projects open through the same door (the user's call: ONE
    // entry, the Open button — the import pickers retire later). A .tvpp
    // converts into cuts rather than loading as a project.
    acceptedTypeGroups: [
      FileTypeGroups.anicelProject,
      FileTypeGroups.tvppProject,
    ],
    // A DESKTOP hint only, and the SYNC twin on purpose: async `dart:io`
    // never completes under the widget-test clock, and this is the first
    // line of the open flow.
    //
    // Withheld wherever grants are scoped — on macOS the sandbox makes
    // `$HOME` the container, so this would point at
    // `~/Library/Containers/…/Documents/Anicel` and the panel would open
    // inside the sandbox on every Open. With no hint the Apple pickers
    // restore wherever the user last was, which is what Files trains them
    // to expect.
    initialDirectory: FolderPicker.grantsAreScoped
        ? null
        : ensuredAppDocumentsDirectorySync(),
  );
  final grant = grants.isEmpty ? null : grants.first;
  final path = grant?.path;
  if (path == null) {
    return null;
  }
  return (path: path, folderBookmark: grant!.bookmark);
}

/// Save As.
///
/// Desktop: the system save dialog answers with a PATH — nothing is
/// created, nothing moves — and the save that follows writes it (temp
/// beside the destination + rename, atomic against whatever it replaces).
/// The dialog it used to share with the scoped platforms staged a 22-byte
/// placeholder in the system temp and moved it into place, which is how
/// Save As to any drive but C: failed outright (`File.rename` cannot cross
/// volumes) and how a Save As pointed at the LIVE project replaced it with
/// 22 bytes before the save could read its own cels.
///
/// Scoped platforms (iOS/Android — no save panel exists): a staged file is
/// handed to the export picker, which MOVES it and reports where it
/// landed. 🚨The staged file is a COPY OF THE LIVE ARCHIVE when one
/// exists, and the minimal valid archive only for a never-saved project.
/// The picker moves its source over whatever the user points it at, so a
/// decoy placeholder made "replace an existing project" destroy that
/// project the moment the picker confirmed — with the real bytes staged,
/// the destination holds a complete archive until the save lands on top.
@visibleForTesting
Future<ProjectPick?> pickProjectSaveTarget(
  BuildContext context,
  String suggestedName,
  String initialDirectory, {
  String? currentProjectPath,
}) async {
  var name = suggestedName;
  if (!name.toLowerCase().endsWith(anicelProjectSuffix)) {
    name = '$name$anicelProjectSuffix';
  }
  if (!FolderPicker.grantsAreScoped) {
    return _pickDesktopSaveTarget(context, name, initialDirectory);
  }
  return _pickScopedSaveTarget(context, name, currentProjectPath);
}

Future<ProjectPick?> _pickDesktopSaveTarget(
  BuildContext context,
  String name,
  String initialDirectory,
) async {
  final grant = await pickSaveDestinationForUser(
    context,
    suggestedName: name,
    initialDirectory: initialDirectory,
    // The dialog filters to the project type; Windows shows the filter but
    // never appends the extension itself, so the suffix answer below stays.
    acceptedTypeGroups: const [FileTypeGroups.anicelProject],
  );
  final picked = grant?.path;
  if (picked == null || !context.mounted) {
    return null;
  }
  if (picked.toLowerCase().endsWith(anicelProjectSuffix)) {
    return (path: picked, folderBookmark: grant!.bookmark);
  }
  // F-14: the suffix is the pick's answer. But appending it claims a
  // DIFFERENT path than the one the dialog's replace prompt asked about —
  // "type Foo over an existing Foo.anicel" was a silent overwrite — so
  // when the real target is taken, the question is asked again about it.
  final suffixed = '$picked$anicelProjectSuffix';
  if (File(suffixed).existsSync()) {
    final strings = AppText.strings;
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        windowKey: const ValueKey<String>('save-as-replace-dialog'),
        title: strings.replaceFileTitle,
        titleIcon: Icons.save_as_outlined,
        message: strings.replaceFileMessageTemplate.replaceAll(
          '{name}',
          suffixed.split('/').last,
        ),
        actions: [
          AppWindowAction(
            label: strings.commonCancel,
            actionKey: const ValueKey<String>('save-as-replace-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppWindowAction(
            label: strings.commonReplace,
            actionKey: const ValueKey<String>('save-as-replace-confirm'),
            emphasis: AppWindowActionEmphasis.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (replace != true || !context.mounted) {
      return null;
    }
  }
  return (path: suffixed, folderBookmark: grant!.bookmark);
}

Future<ProjectPick?> _pickScopedSaveTarget(
  BuildContext context,
  String name,
  String? currentProjectPath,
) async {
  // Its own directory so the cleanup below cannot reach anything else.
  final Directory stagingDirectory;
  final File staged;
  try {
    stagingDirectory = Directory.systemTemp.createTempSync('anicel_save_');
    staged = File('${stagingDirectory.path}/$name');
    if (currentProjectPath != null && File(currentProjectPath).existsSync()) {
      // The live archive, whole. ASYNC — this can be gigabytes and must
      // not stop the UI isolate; a test that drives this branch runs under
      // `tester.runAsync` (the fake clock never completes real dart:io).
      await File(currentProjectPath).copy(staged.path);
    } else {
      // A never-saved project has nothing to copy; a minimal valid archive
      // claims the spot so anything opening it before the save lands reads
      // an empty project rather than a corrupt file.
      //
      // SYNC on purpose: async `dart:io` never completes under the
      // widget-test clock, and this sits before the picker.
      staged.writeAsBytesSync(_emptyAnicelArchive, flush: true);
    }
  } on Object catch (error) {
    // A staging failure used to return null silently — the Save As button
    // read as dead, and on the exit path it silently cancelled the close.
    if (context.mounted) {
      unawaited(
        showAppNotice(
          context,
          title: AppText.strings.commonNotice,
          message: '$error',
        ),
      );
    }
    return null;
  }
  if (!context.mounted) {
    _discardStaging(stagingDirectory);
    return null;
  }
  final grant = await exportFileForUser(
    context,
    sourcePath: staged.path,
    suggestedName: name,
  );
  // On success the staged file was MOVED out and only the empty directory
  // is left; on cancel it is still in it. Same cleanup.
  _discardStaging(stagingDirectory);
  final placed = grant?.path;
  if (placed == null) {
    return null;
  }
  // The placed path is accepted AS-IS. The old flow chased a missing
  // `.anicel` suffix by deleting the placed file and claiming the suffixed
  // sibling — but the security scope and the bookmark cover exactly the
  // item the picker placed, so the "corrected" path was one the sandbox
  // refused and the bookmark named a file that no longer existed. A
  // bare-named project is reachable (recents, and the OS keeps the
  // extension in its own UI); an unsaveable one is not.
  return (path: placed, folderBookmark: grant!.bookmark);
}

/// Removes the staging directory. A leak here must never fail a save — or a
/// cancel, which is the path that reaches it most often.
void _discardStaging(Directory directory) {
  try {
    directory.deleteSync(recursive: true);
  } on Object {
    // Temp is the OS's to reclaim if this ever loses the race.
  }
}

/// An empty but VALID zip: the 22-byte end-of-central-directory record and
/// nothing else.
///
/// Enough for a picker to place, and enough that anything opening it in the
/// moment before the real save lands reads an empty archive rather than a
/// corrupt file.
const List<int> _emptyAnicelArchive = [
  0x50, 0x4B, 0x05, 0x06, // signature
  0, 0, // number of this disk
  0, 0, // disk where the central directory starts
  0, 0, // central directory records on this disk
  0, 0, // central directory records total
  0, 0, 0, 0, // size of the central directory
  0, 0, 0, 0, // offset of the central directory
  0, 0, // comment length
];

/// What a dirty session's user chose at the gate.
enum UnsavedWorkChoice { cancel, saveAs, save, discard }

/// The one question both doors ask before a dirty session is torn down.
///
/// The window's close button had this gate; Open and the Recents rows —
/// which close the current project just as surely — did not, so one tap
/// on a recent row silently discarded every live edit. One window, one
/// set of keys (the `system-exit-*` names the exit tests already pin),
/// so the matrix cell cannot re-open by one door forgetting.
///
/// Returns whether the tear-down may proceed: the save landed, or the
/// user discarded (which retires the sidecar — 「저장 안 하고 닫기 =
/// 버리기」 stays literal). False calls the whole thing off.
Future<bool> ensureUnsavedWorkSettled(
  BuildContext context,
  EditorSessionManager session,
) async {
  if (!session.hasUnsavedChanges) {
    return true;
  }
  final strings = AppText.strings;
  final choice = await showDialog<UnsavedWorkChoice>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('system-exit-dialog'),
      title: strings.closeProjectTitle,
      titleIcon: Icons.logout_outlined,
      message: strings.closeProjectBody,
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('system-exit-cancel'),
          onPressed: () => Navigator.of(context).pop(UnsavedWorkChoice.cancel),
        ),
        AppWindowAction(
          label: strings.commonSaveAs,
          actionKey: const ValueKey<String>('system-exit-save-as'),
          onPressed: () => Navigator.of(context).pop(UnsavedWorkChoice.saveAs),
        ),
        AppWindowAction(
          label: strings.commonSave,
          actionKey: const ValueKey<String>('system-exit-save'),
          onPressed: () => Navigator.of(context).pop(UnsavedWorkChoice.save),
        ),
        AppWindowAction(
          label: strings.commonClose,
          actionKey: const ValueKey<String>('system-exit-close'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(UnsavedWorkChoice.discard),
        ),
      ],
    ),
  );
  switch (choice) {
    case null || UnsavedWorkChoice.cancel:
      return false;
    case UnsavedWorkChoice.discard:
      // Discarding the work discards its sidecar too. Left alive it
      // outlives the session that made it, and the next open offers to
      // restore precisely what the user just chose to throw away — with
      // recovery reading a surviving sidecar as "the app crashed",
      // keeping one here makes that signal lie.
      session.discardAutosaveSidecar();
      return true;
    case UnsavedWorkChoice.save:
    case UnsavedWorkChoice.saveAs:
      if (!context.mounted) {
        return false;
      }
      // The existing File-menu flows do the work (one writer, one
      // picker); a save that fails or a cancelled picker leaves the
      // project dirty, so the tear-down is called off.
      final path = session.projectFilePath;
      if (choice == UnsavedWorkChoice.saveAs || path == null) {
        await promptSaveProjectAs(context, session);
      } else {
        await saveProjectShowingProgress(context, session, path);
      }
      return !session.hasUnsavedChanges;
  }
}

/// 🔑 THE ONE WAY a manual save runs: behind a window that shows it
/// happening and then says it landed.
///
/// Every button the user can press to save goes through here — Save, Save
/// As, and the save inside the exit prompt. Wrapping them one at a time is
/// how "the button I use does not show anything" comes back.
///
/// Returns whether the file was written. The exit flow needs that answer:
/// a save that failed must call the close off rather than take the project
/// down with it. Failure is reported the way every other file error in this
/// strip is, once the window is out of the way.
Future<bool> saveProjectShowingProgress(
  BuildContext context,
  EditorSessionManager session,
  String path,
) async {
  try {
    await runWithAppProgress<void>(
      context: context,
      title: AppText.strings.commonSave,
      titleIcon: Icons.save_outlined,
      runningLabel: AppText.strings.saveProgressRunning,
      doneLabel: AppText.strings.saveProgressDone,
      windowKey: const ValueKey<String>('save-progress-dialog'),
      task: (report) => session.saveProjectToFile(path, onProgress: report),
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      unawaited(
        showAppNotice(
          context,
          title: AppText.strings.commonNotice,
          message: '$error',
        ),
      );
    }
    return false;
  }
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
    // The injected picker places no staged file, so it answers the suffix
    // question the plain way — but it still has to ANSWER it, because the
    // caller below no longer does (F-14).
    pick = injected == null
        ? null
        : (
            path: injected.toLowerCase().endsWith(anicelProjectSuffix)
                ? injected
                : '$injected$anicelProjectSuffix',
            folderBookmark: null,
          );
  } else {
    pick = await pickProjectSaveTarget(
      context,
      suggested,
      initialDirectory,
      // What a scoped platform stages: the live archive, so the export
      // picker never moves a decoy over a real project.
      currentProjectPath: session.projectFilePath,
    );
  }
  if (pick == null || !context.mounted) {
    return;
  }
  // F-14: the suffix is the PICK's answer now — it is the only place that
  // can also answer for the placeholder it left at the un-suffixed name.
  final path = pick.path;
  if (await saveProjectShowingProgress(context, session, path)) {
    recordRecentProject(
      RecentProject(path: path, folderBookmark: pick.folderBookmark),
    );
  }
}

