import 'dart:async';
import 'dart:io' show File, FileSystemException;

import 'package:flutter/material.dart';

import '../../services/audio/audio_conform_pipeline.dart'
    show ProjectAssetLayout;
import '../../services/persistence/anicel_project_archive.dart';
import '../../services/persistence/app_documents.dart';
import '../../services/persistence/cel_places.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/persistence/folder_grant.dart';
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
import '../../models/import/import_warning.dart';
import '../text/model_vocabulary.dart';
import '../text/place_lines.dart' show celPlaceLine;
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pressure_curve_popup.dart';
import '../dialogs/folder_pick_flow.dart';
import '../dialogs/preferences_dialog.dart';
import '../canvas/paper_background.dart' show alphaPreviewEnabled;
import '../debug/input_inspector.dart';
import '../debug/measurement_mode.dart';
import '../widgets/static_raster.dart';
import '../editor_session_manager.dart';
import '../../services/persistence/app_export_settings_store.dart';
import '../export/export_dialog.dart';
import '../import/import_dialog.dart';
import '../export/export_plan.dart' show sanitizeExportFileComponent;
import '../panels/workspace_panels_menu.dart';
import '../session/project_file_door.dart' show SaveAsked, StagedArchive;
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../shortcuts/shortcut_settings_dialog.dart';
import '../theme/app_theme.dart';

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

  /// 🪦Two picker seams stood here — `anicelOpenFilePicker` and
  /// `anicelSaveFilePicker`, both「injectable for tests」. **Nothing ever
  /// supplied either one**, in `lib/` or in `test/`, and each bought a
  /// branch that no run took. Faking a picker already has a home that the
  /// platform code shares: `FolderPicker.debugFilePicker` /
  /// `debugFileExporter` / `debugSaveDestinationPicker`, which
  /// `project_pickers_test` drives. A second way in would have been a
  /// copy — and the save one was worse than dead, because its `String?`
  /// could not say `placed`, so injecting it silently took the DESKTOP
  /// branch and skipped the very ordering F-57 fixed.

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
    List<String> shortcuts = const [],
  }) => PanelFlyoutItem(
    keyValue: 'menu-$id',
    // Every entry localizes HERE, by the id it is already keyed with, with
    // the English staying at the call sites where the strip is authored.
    label: AppText.strings.menuLabel(id, label),
    icon: icon,
    checked: checked,
    shortcuts: shortcuts,
    enabled: onPressed != null,
    onSelected: onPressed,
  );

  // --- File -----------------------------------------------------------------

  Future<void> _openProject(BuildContext context) async {
    final pick = await pickProjectToOpen(context);
    if (pick == null || !context.mounted) {
      return;
    }
    await _openPickedProject(context, pick);
  }

  /// Opens [pick] behind the unsaved-work gate, from a staged copy if the
  /// file will not read in place, and records it in Recents afterwards.
  ///
  /// Shared with the Recent-projects rows on purpose: opening from Recent is
  /// the ONE-TAP common case PICK-4 exists to make, and every guard this
  /// door has has to be on that path too.
  ///
  /// 🪦It offered autosave RECOVERY first until 2026-09-08, and that is the
  /// whole of what it lost.
  Future<void> _openPickedProject(
    BuildContext context,
    ProjectPick pick,
  ) async {
    final path = pick.path;
    if (path.toLowerCase().endsWith('.tvpp')) {
      await _openTvppAsProject(context, path);
      return;
    }
    // Opening ANOTHER project closes this one as surely as the window's X,
    // and this was the one door with no gate: a single Recents tap
    // silently discarded a dirty session. Same question, same window, same
    // keys as the exit gate.
    //
    // 🪦**AND REOPENING THE CURRENT PROJECT NO LONGER SKIPS IT.** The
    // exception was written for recovery: the reload threw the live edits
    // away on its own, and answering Recover on a re-open was the one way
    // back to them — so a gate that retired the sidecar first would have
    // closed that door. With no sidecar to reach, the exception is a
    // silent discard with nothing behind it, and「reload from disk」is
    // still reachable by answering Discard at the gate.
    if (!await ensureUnsavedWorkSettled(context, session) || !context.mounted) {
      return;
    }
    final ({({bool staged}) value})? opened;
    try {
      opened = await _openBehindWindow<({bool staged})>(
        context,
        (wait, _) => _readProject(path, wait),
      );
    } on Object catch (error) {
      // The archive's own complaint — a file that would not parse.
      if (context.mounted) {
        showFileError(context, error);
      }
      return;
    }
    if (opened == null || !context.mounted) {
      return;
    }
    await _afterOpened(context, pick, staged: opened.value.staged);
  }

  /// The read itself, from wherever the bytes are.
  ///
  /// The same materializer every open uses: a File Provider pick can be a
  /// placeholder a plain read refuses, and the archive reader needs random
  /// access — so an unreadable pick opens from a staged local copy, and the
  /// session is bound back to the real file so saves land there.
  Future<({bool staged})> _readProject(String path, _CloudWait wait) async {
    final source = await FolderPicker.materializeOpenedFile(
      path,
      within: null,
      onWaiting: wait.report,
      isCancelled: wait.isCancelled,
    );
    // The bytes are here; the read that follows is the app's own.
    wait.arrived();
    await session.projectDoor.openProjectFromFile(
      source.path,
      // Only when they differ: binding is what says「saves go back THERE」,
      // and a session reading its own file has nowhere else.
      bindTo: source.staged ? path : null,
      isCancelled: wait.isCancelled,
    );
    return (staged: source.staged);
  }

  /// The three things that follow a SUCCESSFUL open: Recents, the word
  /// about a staged copy, the word about a legacy assets folder.
  Future<void> _afterOpened(
    BuildContext context,
    ProjectPick pick, {
    required bool staged,
  }) async {
    final path = pick.path;
    // Recorded AFTER the open succeeds, not at pick time: a file that
    // fails to parse has no business sitting at the top of the menu.
    // `path` rather than the staged copy — reading out of a copy still
    // means the user opened the project, not the copy.
    recordRecentProject(
      RecentProject(path: path, folderBookmark: pick.folderBookmark),
    );
    if (staged) {
      // Said out loud on purpose (유저 2026-08-27): the wait is meant to
      // make this road unreachable, so a build that still takes it must be
      // visible rather than quietly slower. A copy also means every cel
      // ref points into a temp file for the session — the one case where
      // the user deserves to know before they draw.
      await showAppNotice(
        context,
        windowKey: const ValueKey<String>('opened-from-staged-copy'),
        title: AppText.strings.commonNotice,
        message:
            '제자리에서 읽지 못해 임시 사본으로 열었습니다 — '
            '이 문구가 보이면 알려주세요.',
      );
      if (!context.mounted) {
        return;
      }
    }
    // A project from a build that kept its media in a sibling folder.
    // Said AFTER the open, because a file that failed to parse has no
    // media to absorb and the folder is still the only copy.
    final layout = ProjectAssetLayout(path);
    if (layout.hasLegacyAssetsDirectory) {
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
  }

  /// A TVPaint project opens AS A PROJECT (the user's rule — a .tvpp holds
  /// several cuts): everything current is replaced, so the same
  /// unsaved-work gate as any open guards it. No recents entry — the
  /// result is a NEW unsaved project until its first save.
  Future<void> _openTvppAsProject(BuildContext context, String path) async {
    if (!await ensureUnsavedWorkSettled(context, session) || !context.mounted) {
      return;
    }
    // Decoding and baking a whole project is a save-sized wait; a frozen
    // screen before the cuts appear reads as a hang (hands-on, 288's 96
    // frames × 19 layers).
    final opened = await _openBehindWindow<List<ImportWarning>?>(
      context,
      (wait, report) => session.tvppDoor.openAsProject(
        tvppPath: path,
        onProgress: (fraction) {
          // Reading has started, so the waiting line has nothing left
          // to say.
          wait.arrived();
          report(fraction);
        },
        onWaiting: wait.report,
        isCancelled: wait.isCancelled,
      ),
    );
    if (opened == null || !context.mounted) {
      return;
    }
    final warnings = opened.value;
    if (warnings == null) {
      showFileError(context, AppText.strings.imNotTvpp);
    } else if (warnings.isNotEmpty) {
      await showAppNotice(
        context,
        windowKey: const ValueKey<String>('tvpp-import-warnings-notice'),
        title: AppText.strings.commonNotice,
        message: warnings
            .take(6)
            .map((warning) => warning.textFor(AppText.language))
            .join('\n'),
      );
    }
  }

  /// The ONE window every open stands behind, up from the first frame, for
  /// a .anicel and a .tvpp alike.
  ///
  /// 🚨IT USED TO COVER ONLY THE WAIT FOR A PROVIDER'S BYTES and stay silent
  /// for a local pick, on the premise that an open is instant. A 74MB
  /// project on a cloud drive is not, and the person could not tell an open
  /// from nothing (유저 2026-09-13: 「로딩창 안 떠서 여는 중인지 아닌지
  /// 모르겠어」). F-53 had already said what a wait window does — it goes
  /// up at once — and this is that law with its one exception removed. The
  /// status line still says whose work a cloud wait is ([_CloudWait]); once
  /// the bytes are here the rest is the app's own.
  ///
  /// The two answers every open can end in are given HERE: the user stopped
  /// waiting (nothing was applied, the door closes without a word), or the
  /// file could not be read (access, not format — the same file opens once
  /// it is readable: a cloud placeholder mid-download, a provider signed
  /// out). Null is either of those; anything else wraps [task]'s own answer,
  /// so a task whose answer is itself null is not mistaken for a cancel.
  Future<({T value})?> _openBehindWindow<T>(
    BuildContext context,
    Future<T> Function(_CloudWait wait, void Function(double) report) task,
  ) async {
    final wait = _CloudWait();
    try {
      final value = await runWithAppProgress<T>(
        context: context,
        title: AppText.strings.fileOpenTitle,
        titleIcon: Icons.folder_open_outlined,
        runningLabel: AppText.strings.openProgressRunning,
        doneLabel: AppText.strings.openProgressDone,
        windowKey: const ValueKey<String>('open-progress-dialog'),
        runningStatus: wait.status,
        onCancel: wait.cancel,
        task: (report) => task(wait, report),
      );
      return (value: value);
    } on MaterializeCancelled {
      return null;
    } on FileSystemException {
      if (context.mounted) {
        showFileError(context, AppText.strings.imFileUnreadable);
      }
      return null;
    } finally {
      wait.dispose();
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
        if (!context.mounted) {
          return;
        }
        final relinked = await _reconnect(context, entry);
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
      if (!context.mounted) {
        return;
      }
      final relinked = await _reconnect(context, entry);
      if (relinked == null) {
        return;
      }
      path = relinked.path;
      bookmark = relinked.folderBookmark;
      if (!File(path).existsSync()) {
        if (context.mounted) {
          showFileError(context, AppText.strings.imNotFound(path));
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
    await _openPickedProject(context, (
      path: path,
      folderBookmark: bookmark,
      placed: false,
    ));
  }

  /// Flags [entry] as needing a reconnect and asks for the project it has
  /// lost track of — with the FILE picker, the same door Open uses.
  ///
  /// It used to raise the FOLDER picker and rejoin by file name, a shape
  /// left over from the folder-as-permission-unit world. That mode is the
  /// one Google Drive refuses on iOS, so the reconnect flow for a Drive
  /// project was a dead end pointing at the very provider the file-mode
  /// round un-blocked. Picking the file itself needs no name join, works
  /// everywhere file mode works, and hands back the file bookmark the
  /// recents row wants anyway.
  ///
  /// The two ways a recent row goes stale — no bookmark to resolve, and a
  /// bookmark that resolved to a file that is gone — reach exactly this
  /// step, so the row is flagged HERE rather than at each of them.
  Future<ProjectPick?> _reconnect(BuildContext context, RecentProject entry) {
    storeRecentProjects(
      AppRecent.projects.value.withReconnectNeeded(entry.path),
    );
    return pickProjectFile(
      context,
      supportedExtensions: FileTypeGroups.anicelProject.extensions ?? const [],
    );
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
    // The registry's names: Ctrl+S and Ctrl+Shift+S press these (I-19), and
    // the shortcut list says the same two words.
    _item(
      id: 'file-save',
      label: editorActionLabel(EditorActionIds.fileSave),
      shortcuts: const [EditorActionIds.fileSave],
      icon: Icons.save_outlined,
      onPressed: () => unawaited(saveProject(context, session)),
    ),
    _item(
      id: 'file-save-as',
      label: editorActionLabel(EditorActionIds.fileSaveAs),
      shortcuts: const [EditorActionIds.fileSaveAs],
      icon: Icons.save_as_outlined,
      onPressed: () => unawaited(promptSaveProjectAs(context, session)),
    ),
    ..._recentEntries(context),
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
      // The bindings arrive down the ONE scope every key label reads — a
      // second pipe for the same object is how a menu and its tooltips
      // would come to disagree. No scope (a bare host) has nothing to edit.
      onPressed: switch (EditorShortcutScope.peek(context)) {
        null => null,
        final bindings => () {
          unawaited(
            showDialog<void>(
              context: context,
              builder: (context) => ShortcutSettingsDialog(bindings: bindings),
            ),
          );
        },
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
    final path = session.projectFile.path;
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
            curves: state.targetCurves(target),
            enabled: pressureOn,
            onChanged: (curves) =>
                brushTool.value = state.withTargetCurves(target, curves),
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
                unit: ' px',
                height: _barHeight,
                onChanged: sizeOn
                    ? (value) => brushTool.value = brushTool.value.copyWith(
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
              child: FieldSlider.opacity(
                key: const ValueKey<String>('top-strip-opacity-bar'),
                label: AppText.strings.brOpacity,
                // TP1: the ACTIVE tool's opacity — the fill and the stamp
                // keep their own, so this bar stops being the brush's alone
                // (유저: 툴마다 기억하게해서 필 툴도 불투명도 설정하면 그걸로
                // 채워지게).
                value: BrushToolState.clampOpacity(state.activeOpacity),
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
  ///
  /// ONE width for BOTH states, so picking up the eraser — which shows a
  /// fixed 消去 instead of a chooser — does not slide the bars sideways.
  static const double _buttonWidth = 116;

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
        // The ERASER tool fixes it to 消去/Erase — the eraser IS the erase
        // blend — and that is not a blend CHOICE, so the flyout stands down.
        final toolLocked = state.tool == CanvasTool.eraser;
        final mode = state.activeBlendMode;
        if (toolLocked) {
          return SizedBox(
            width: _buttonWidth,
            child: Container(
              key: const ValueKey<String>('brush-tool-blend-locked'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: ShapeDecoration(
                shape: AppShapes.container(
                  AppShapes.wellRadius,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
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
        return SizedBox(
          width: _buttonWidth,
          child: PanelFlyoutButton(
            key: const ValueKey<String>('brush-tool-blend-menu-button'),
            label: mode.labelFor(language),
            tooltip: AppText.strings.brBlendMode,
            enabled: blendOn,
            // `expand` is what makes the fixed box hold: the label
            // becomes Flexible inside it, so it ellipsizes rather than
            // overflowing the width the strip budgeted.
            expand: true,
            // ONE list for every tool that composites — TS8 유저 법:
            // 「블렌드모드가 존재한다면 다 공통이야. 지우개만 이레이저만
            // 남기는거고. 나머지는 이레이저 포함 다 있어.」 The stamp
            // joining `toolHasBlendMode` is all it took: the eraser's
            // single-entry case is the `toolLocked` box above, so this
            // list needs no per-tool filter to obey that law.
            entriesBuilder: () => BrushBlendMode.values.asFlyoutChoices(
              current: mode,
              keyPrefix: 'brush-tool-blend-',
              labelOf: (candidate) => candidate.labelFor(language),
              // Writes to whichever drawer the armed tool owns — the
              // BRUSH's is its own shape, so the mode picked here is
              // the mode that brush keeps and exports. The button
              // never names a tool (유저 확정: 블렌드모드 선택도 툴에
              // 산다).
              onPicked: (candidate) =>
                  brushTool.value = state.withActiveBlendMode(candidate),
            ),
          ),
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

/// What a door says while a file it did not write is on its way.
///
/// One object for the three things a wait needs — a line that changes, a
/// stop, and the question 「were we stopped?」 — so both doors say the
/// same thing with the same words rather than each inventing its own.
///
/// The line NAMES THE CLOUD (유저 2026-08-27: 「프로바이더가 로컬로
/// 다운로드하는 걸 기다리고 있다고 명확히 표기하는 게 좋겠다」). 「여는 중」
/// across a download makes the app look slow for work the provider is
/// doing, and the person waiting cannot tell the two apart without being
/// told which one it is.
class _CloudWait {
  final ValueNotifier<String> status = ValueNotifier<String>('');
  final Completer<void> _started = Completer<void>();
  bool _cancelled = false;

  /// After this, the line stops counting up quietly and says that
  /// nothing has come — which is when a person starts deciding.
  static const Duration _sayNothingArrivedAfter = Duration(seconds: 10);

  /// Completes the first time the work says it is WAITING — which is what
  /// a door raises its window on. A pick that reads straight away never
  /// completes it, and so never draws anything.
  Future<void> get started => _started.future;

  void report(Duration waited) {
    if (!_started.isCompleted) {
      _started.complete();
    }
    final seconds = waited.inSeconds;
    final strings = AppText.strings;
    status.value =
        (waited >= _sayNothingArrivedAfter
                ? strings.openWaitingStalledTemplate
                : strings.openWaitingCloudTemplate)
            .replaceAll('{sec}', '$seconds');
  }

  /// The bytes are here; whatever comes next is the app's own work.
  void arrived() => status.value = '';

  void cancel() => _cancelled = true;

  bool isCancelled() => _cancelled;

  void dispose() => status.dispose();
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
///
/// [placed] says the archive is ALREADY there: the scoped picker moves a
/// file the app wrote rather than handing back an empty destination, so
/// the bytes at [path] are the ones just serialized and writing them a
/// second time is at best waste — see [promptSaveProjectAs].
typedef ProjectPick = ({String path, String? folderBookmark, bool placed});

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
Future<ProjectPick?> pickProjectToOpen(BuildContext context) => pickProjectFile(
  context,
  // TVPaint projects open through the same door (the user's call: ONE
  // entry, the Open button — the import pickers retire later). A .tvpp
  // converts into cuts rather than loading as a project.
  //
  // 🚨These are now what the open ACCEPTS, not what the dialog SHOWS —
  // 유저 2026-08-29 named this exact dialog: 「특히 윈도우 열기시 anicel
  // 이랑 tvp만 설정따라서 보이게 되있는데 그게아니라 … 어떤 확장자던
  // 선택할수 있게」.
  supportedExtensions: const [anicelProjectExtension, 'tvpp'],
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

/// Points the FILE picker at a project and answers what it grants: the
/// first file, its bookmark, and `placed: false` — nothing was written, so
/// whoever asked still has to write it.
///
/// 🚨THE ONE PICK BEHIND EVERY PROJECT DOOR. Open and Reconnect are the
/// same act with two bound constants — which extensions the door accepts,
/// and whether a desktop starting folder is offered — so they are one
/// function with two arguments rather than two functions that drift.
Future<ProjectPick?> pickProjectFile(
  BuildContext context, {
  required List<String> supportedExtensions,
  String? initialDirectory,
}) async {
  final grants = await pickFileGrantsForUser(
    context,
    supportedExtensions: supportedExtensions,
    initialDirectory: initialDirectory,
  );
  final grant = grants.isEmpty ? null : grants.first;
  final path = grant?.path;
  if (path == null) {
    return null;
  }
  return (path: path, folderBookmark: grant!.bookmark, placed: false);
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
/// Scoped platforms (iOS/Android — no save panel exists): [stageArchive]
/// writes the whole live session into the system temp and the export
/// picker MOVES that file to wherever the user points it, reporting where
/// it landed. The picker moves its source over whatever it is pointed at,
/// so a decoy placeholder made "replace an existing project" destroy that
/// project the moment the picker confirmed, and a 22-byte placeholder
/// stranded an unopenable husk whenever the provider refused the in-place
/// save meant to fill it (실측 iPhone+Drive, 08-26). What the picker
/// places is a COMPLETE, CURRENT project — which is why the caller adopts
/// it rather than writing over it (`placed: true`).
@visibleForTesting
Future<ProjectPick?> pickProjectSaveTarget(
  BuildContext context,
  String suggestedName,
  String initialDirectory, {
  required Future<void> Function(String stagingPath) stageArchive,
}) async {
  var name = suggestedName;
  if (!name.toLowerCase().endsWith(anicelProjectSuffix)) {
    name = '$name$anicelProjectSuffix';
  }
  if (!FolderPicker.grantsAreScoped) {
    return _pickDesktopSaveTarget(context, name, initialDirectory);
  }
  return _pickScopedSaveTarget(context, name, stageArchive);
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
    return (path: picked, folderBookmark: grant!.bookmark, placed: false);
  }
  // F-14: the suffix is the pick's answer. But appending it claims a
  // DIFFERENT path than the one the dialog's replace prompt asked about —
  // "type Foo over an existing Foo.anicel" was a silent overwrite — so
  // when the real target is taken, the question is asked again about it.
  final suffixed = '$picked$anicelProjectSuffix';
  if (File(suffixed).existsSync()) {
    final strings = AppText.strings;
    final replace = await askConfirm(
      context,
      ConfirmQuestion(
        keys: (
          window: const ValueKey<String>('save-as-replace-dialog'),
          decline: const ValueKey<String>('save-as-replace-cancel'),
          accept: const ValueKey<String>('save-as-replace-confirm'),
        ),
        title: strings.replaceFileTitle,
        titleIcon: Icons.save_as_outlined,
        message: strings.replaceFileMessageTemplate.replaceAll(
          '{name}',
          suffixed.split('/').last,
        ),
      ),
      accept: ConfirmChoice(
        strings.commonReplace,
        emphasis: AppWindowActionEmphasis.danger,
      ),
    );
    if (replace != true || !context.mounted) {
      return null;
    }
  }
  return (path: suffixed, folderBookmark: grant!.bookmark, placed: false);
}

Future<ProjectPick?> _pickScopedSaveTarget(
  BuildContext context,
  String name,
  Future<void> Function(String stagingPath) stageArchive,
) async {
  final grant = await placeStagedFileForUser(
    context,
    suggestedName: name,
    write: (stagingPath) async {
      try {
        // WRITTEN, whole, from the live session — never copied from the
        // file being left behind. It used to be a 22-byte empty-zip
        // placeholder, on the theory that the save landing after the move
        // would fill it; a provider that refuses in-place writes (실측
        // iPhone+Drive, 08-26) turned that theory into an unopenable husk
        // sitting exactly where the user meant to put their work.
        //
        // 🚨And copying the LIVE ARCHIVE — the shape in between — was only
        // ever correct because that same second write followed it: the
        // archive on disk is the last SAVED state, so a Save As from a
        // dirty session staged a file that was already out of date. The
        // second write is gone now (the caller adopts what the picker
        // placed), so what is placed has to be the current state, and only
        // a fresh write is that.
        await stageArchive(stagingPath);
        return true;
      } on Object catch (error) {
        // A staging failure used to return null silently — the Save As
        // button read as dead, and on the exit path it silently cancelled
        // the close.
        if (context.mounted) {
          showFileError(context, error);
        }
        return false;
      }
    },
  );
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
  // `placed: true` — the archive the picker MOVED is the one this session
  // just serialized, so the caller adopts it instead of writing it again.
  return (path: placed, folderBookmark: grant!.bookmark, placed: true);
}

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
/// user discarded. False calls the whole thing off.
///
/// ⚠️**What「discard」can still throw away depends on the autosave
/// switch**, and this gate does not decide that. With autosave ON a tick
/// has been saving the project file, so discarding drops only the work
/// since the last tick; with it OFF, 「저장 안 하고 닫기 = 버리기」 is
/// literal. 유저 2026-09-07 chose that trade explicitly — 「그게 싫으면
/// 자동저장 off하면된다」 — see [AppSaveSettings.periodicSnapshotMinutes].
///
/// ⚠️It is no longer only a DIRTY session that gets asked — see the first
/// statement.
Future<bool> ensureUnsavedWorkSettled(
  BuildContext context,
  EditorSessionManager session,
) async {
  // 🚨★★★**THE QUESTION IS 「WILL THE WORK SURVIVE THIS TEAR-DOWN」, NOT
  // 「ARE THERE UNSAVED EDITS」.**
  //
  // After a save a clean cel keeps only `{path, offset, length}` — the
  // `.anicel` IS the cold tier. So a session with NOTHING unsaved still
  // loses drawings when its file is gone: [OpenProjectFile] holds the file
  // open, and on POSIX that is precisely why the session kept working
  // after an `unlink` — and precisely why **closing the app is the moment
  // those bytes really go**. Asking only about the dirty flag let that
  // session walk out the door in silence.
  //
  // The disappearance already had a NOTICE (`_warnIfProjectFileVanished`,
  // said once when the user comes back from their file manager) and no
  // gate. One fact, two doors: the notice opens the window to restore the
  // file, this closes the one where it is thrown away.
  final vanished = session.projectFile.hasVanished();
  if (!session.projectFile.hasUnsavedChanges && !vanished) {
    return true;
  }
  final strings = AppText.strings;
  final choice = await showDialog<UnsavedWorkChoice>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('system-exit-dialog'),
      title: strings.closeProjectTitle,
      titleIcon: Icons.logout_outlined,
      // A vanished file wins the wording even when there are unsaved
      // edits too: 「your changes are not saved」 describes a loss the four
      // buttons can undo, and this one they mostly cannot.
      message: vanished
          ? strings.closeProjectVanishedBody
          : strings.closeProjectBody,
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
      // Recorded on the session, because the tear-down that follows runs
      // the same lifecycle callbacks any close does — without this the
      // autosave clock could come due on the way down and save the very
      // work the user just chose to throw away.
      session.projectFile.discardUnsavedWork();
      return true;
    case UnsavedWorkChoice.save:
    case UnsavedWorkChoice.saveAs:
      if (!context.mounted) {
        return false;
      }
      // The File menu's own saves do the work (one writer, one picker); a
      // save that fails or a cancelled picker leaves the project dirty, so
      // the tear-down is called off.
      if (choice == UnsavedWorkChoice.saveAs) {
        await promptSaveProjectAs(context, session);
      } else {
        await saveProject(context, session);
      }
      return !session.projectFile.hasUnsavedChanges;
  }
}

/// 🔑 THE Save: back to the file this session is bound to, or Save As when
/// it has none yet.
///
/// 🗣️I-19 (유저 2026-09-12): 「컨트롤s로 저장 로직 연결 … 법 나뉘어진거
/// 있으면 겸사겸사 통일」. It was split: the File menu's Save and the exit
/// prompt's Save each asked 「is there a file yet?」 on their own. One answer
/// now, and Ctrl+S asks it too.
Future<void> saveProject(
  BuildContext context,
  EditorSessionManager session,
) async {
  final path = session.projectFile.path;
  if (path == null) {
    await promptSaveProjectAs(context, session);
    return;
  }
  await saveProjectShowingProgress(context, session, path);
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
      task: (report) =>
          session.projectDoor.saveProjectToFile(
            path,
            asked: SaveAsked.byAPerson,
            onProgress: report,
          ),
    );
    if (context.mounted) {
      _tellWhatTheSaveCouldNotCarry(context, session);
    }
    return true;
  } on Object catch (error) {
    if (context.mounted) {
      showFileError(context, error);
    }
    return false;
  }
}

/// 🚨★★★**A SAVE THAT WROTE FEWER CELS THAN IT HOLDS MUST SAY SO.**
///
/// 유저 2026-08-30, on an iPad: delete the project file in the Files
/// app while the project is open, draw, press Save. A save turns every
/// cel into a ref into that file and drops its cold blob, so once the
/// file is gone those cels' bytes are nowhere — the save now writes
/// everything it can still reach rather than coming apart, and this is
/// where the person is told what it could not carry.
///
/// ⛔Through [showAppNotice] because F-10 says every refusal does, and from
/// BOTH ends a save can finish at: [saveProjectShowingProgress] — the menu,
/// the shortcut, the unsaved-work prompt — and a Save As the picker PLACED,
/// which returns without passing through it (F-72, 2026-09-11: that end
/// never asked, so a copy one cel short said nothing).
void _tellWhatTheSaveCouldNotCarry(
  BuildContext context,
  EditorSessionManager session,
) {
  final lost = session.projectDoor.celsLostToAMissingFile;
  if (lost.isEmpty) {
    return;
  }
  final strings = AppText.strings;
  unawaited(
    showAppNotice(
      context,
      title: strings.commonNotice,
      message: strings.saveCelsLostTemplate.replaceAll(
        '{count}',
        '${lost.length}',
      ),
      // WHICH pictures, not only how many (C-save-percent, 유저 2026-09-11:
      // 「사라진 그림이 뭔지 이름 리스트로 표시하는게 필요해보임」) — in the
      // fold every notice has for what its sentence is about.
      details: [
        for (final place in celPlacesOf(
          session.repository.requireProject(),
          lost,
        ))
          celPlaceLine(place),
      ],
      detailsHeading: strings.saveCelsLostHeading,
      windowKey: const ValueKey<String>('save-cels-lost-notice'),
    ),
  );
}

/// Writes the whole live session to [stagingPath] and answers what it wrote
/// — [ProjectFileDoor.writeArchiveCopy] in production.
///
/// 🚨★★★**A SEAM BECAUSE THE WRITER CANNOT RUN UNDER A FAKE CLOCK**, not
/// because anyone wanted a choice about who writes the archive.
/// `AnicelFileService.save` goes through `Isolate.run` four times, and
/// `testWidgets` runs in a fake-async zone where awaiting a real isolate is
/// a HANG rather than a wait. Without this the ordering below — 「Ready」
/// before the picker and 「Saved」only after it — had no test that could
/// even reach it, which is how F-57 shipped with the wrong word for a day.
///
/// ⛔The picker is NOT a seam here, and that is deliberate: faking one
/// already has a home the platform code shares
/// ([FolderPicker.debugFileExporter] and friends). See the gravestone on
/// [EditorTopStrip].
typedef ProjectArchiveWriter =
    Future<StagedArchive> Function(
      String stagingPath,
      void Function(double) report,
    );

Future<void> promptSaveProjectAs(
  BuildContext context,
  EditorSessionManager session, {
  ProjectArchiveWriter? writeArchive,
}) async {
  final suggested =
      '${sanitizeExportFileComponent(session.repository.requireProject().name)}'
      '$anicelProjectSuffix';
  final currentPath = session.projectFile.path?.replaceAll('\\', '/');
  // 🚨THE SYNC TWIN, like [pickProjectToOpen] twenty lines up — one file
  // asking one question one way. The async spelling stood here and it is
  // documented as unusable from a widget test: 「sync dart:io works under
  // the widget-test clock; async never completes there」. So the FIRST LINE
  // of the flow whose ordering F-57 is about could never be reached by a
  // test, whatever seam it was given.
  final initialDirectory = currentPath != null && currentPath.contains('/')
      ? currentPath.substring(0, currentPath.lastIndexOf('/'))
      : ensuredAppDocumentsDirectorySync();
  // What the staged archive holds, kept from the staging call to the
  // adoption below — the two are one decision ("this file is the project
  // now") split across the picker that sits between them.
  StagedArchive? staged;
  final write =
      writeArchive ??
      (String path, void Function(double) report) =>
          session.projectDoor.writeArchiveCopy(
            path,
            asked: SaveAsked.byAPerson,
            onProgress: report,
          );
  // 🪦ONE CALL, not two. An injected picker used to get its own branch
  // here, and that branch re-answered the suffix question the pick already
  // answers (F-14) — a second spelling of one law, kept alive by a seam
  // nothing supplied.
  final pick = await pickProjectSaveTarget(
    context,
    suggested,
    initialDirectory,
    // What a scoped platform stages: the whole live session, written on
    // the spot — behind the same progress window a save wears, because
    // a long-drawn session serializing whole is a save-sized wait and a
    // frozen screen before a picker reads as a hang.
    // 🚨★★★**THIS WINDOW SAYS「READY」, NOT「SAVED」.**
    //
    // 유저 2026-08-31, on an iPad: 「로딩창뜨고 저장이 완료됬습니다 뜨고
    // 픽커 뜨는데, 그게아니라 로딩창뜨고, **준비가 완료됐습니다** 띄우고
    // … 픽커 완료되고 나서 로딩/저장완료 안내창 띄우는게 직관적」.
    //
    // They are right, and it was a lie: nothing has been saved when this
    // finishes. iOS has no save panel, so the archive is written into
    // the app container FIRST and the picker then places it — and if the
    // person cancels there, the file this window just announced as
    // 「saved」is deleted. Announcing the end of the WRITE as the end of
    // the SAVE told them a thing that could still be undone.
    stageArchive: (stagingPath) => runWithAppProgress<void>(
      context: context,
      title: AppText.strings.commonSave,
      titleIcon: Icons.save_outlined,
      runningLabel: AppText.strings.savePrepareRunning,
      doneLabel: AppText.strings.savePrepareDone,
      windowKey: const ValueKey<String>('save-progress-dialog'),
      task: (report) async {
        staged = await write(stagingPath, report);
      },
    ),
  );
  if (pick == null || !context.mounted) {
    return;
  }
  // F-14: the suffix is the PICK's answer now — it is the only place that
  // can also answer for the placeholder it left at the un-suffixed name.
  final path = pick.path;
  final written = staged;
  if (pick.placed && written != null) {
    // 🚨NO SECOND WRITE. The picker MOVED the archive this session just
    // serialized, so the bytes at [path] are already current — the picker
    // is modal, nothing could have edited them in between. Writing them
    // again was a second full serialization AND the thing that failed:
    // a destination the picker moved a file INTO is not one the app may
    // write to afterwards, and Save As died with 「the location refused
    // both a direct write and a coordinated replace」 on a path it had
    // just successfully filled (실기 08-27, iPhone).
    session.projectDoor.adoptPlacedArchive(path, staged: written);
    recordRecentProject(
      RecentProject(path: path, folderBookmark: pick.folderBookmark),
    );
    // 🚨AND NOW it is saved — so now is when it says so. The staging window
    // above said 「Ready」; this is the other half of the order 유저
    // 2026-08-31 asked for, and the only moment at which the sentence is
    // true. There is no work left to do, so the window is a confirmation
    // and lingers exactly as long as any other save's does.
    if (context.mounted) {
      await runWithAppProgress<void>(
        context: context,
        title: AppText.strings.commonSave,
        titleIcon: Icons.save_outlined,
        runningLabel: AppText.strings.saveProgressRunning,
        doneLabel: AppText.strings.saveProgressDone,
        windowKey: const ValueKey<String>('save-placed-dialog'),
        task: (report) async => report(1),
      );
    }
    if (context.mounted) {
      _tellWhatTheSaveCouldNotCarry(context, session);
    }
    return;
  }
  if (await saveProjectShowingProgress(context, session, path)) {
    recordRecentProject(
      RecentProject(path: path, folderBookmark: pick.folderBookmark),
    );
  }
}
