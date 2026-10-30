import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../controllers/default_project_helpers.dart'
    show newUntitledProject;
import '../../core/build_stamp.dart';
import '../../core/path_names.dart';
import '../../services/persistence/anicel_project_archive.dart';
import '../../services/persistence/app_documents.dart';
import '../../services/persistence/cel_places.dart';
import '../../services/persistence/failed_save_copies.dart';
import '../../services/persistence/file_type_groups.dart';
import '../../services/persistence/folder_grant.dart';
import '../../services/persistence/provider_documents.dart';
import '../../services/persistence/save_failure.dart';
import '../../services/persistence/save_stretch.dart';
import '../../services/persistence/recent_projects.dart';
import '../../services/persistence/recent_projects_store.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_progress_dialog.dart';
import '../../native/device_battery.dart';
import '../../native/window_full_screen.dart';
import '../brush/brush_tool_state.dart';
import '../brush/brush_value_group.dart';
import '../brush/tools_panel.dart' show RailButton;
import '../widgets/anchored_popup.dart';
import '../widgets/field_slider.dart';
import '../widgets/kept_tail_row.dart';
import '../text/app_strings.dart';
import '../../models/media_asset.dart' show MediaAssetKind;
import '../../models/timesheet_info.dart';
import '../text/place_lines.dart' show celPlaceLine;
import '../text/text_measure.dart';
import '../input/control_press_claim.dart';
import '../open_projects.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/setting_source_button.dart';
import '../widgets/strip_group_rule.dart';
import '../dialogs/folder_pick_flow.dart';
import '../dialogs/dialog_verb.dart';
import '../dialogs/feedback_window.dart';
import '../dialogs/preferences_dialog.dart';
import '../dialogs/work_settings_window.dart';
import '../debug/input_inspector.dart';
import '../debug/measurement_mode.dart';
import '../sliced_value_listenable_builder.dart';
import '../editor_session_manager.dart';
import '../../services/persistence/app_export_settings_store.dart';
import '../export/export_dialog.dart';
import '../workspace/workspace_door_commands.dart';
import '../export/export_format_availability.dart' show stillFormatWritable;
import '../export/export_plan.dart'
    show
        ExportFrameTask,
        ExportSizeMode,
        sanitizeExportFileComponent,
        unnamedExportName;
import '../export/frame_image_file.dart';
import '../../models/export_format_selection.dart';
import '../../models/export_spec.dart' show ImageExportSpec;
import '../panels/workspace_panels_menu.dart';
import 'project_open_door.dart';
import 'project_settings_menu.dart';
import '../session/project_file_door.dart'
    show SaveAsked, StagedArchive;
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_key_funnel.dart' show EditorKeyRoad;
import '../shortcuts/editor_shortcut_scope.dart';
import '../shortcuts/panel_actions.dart';
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
    required this.projects,
    required this.onCloseProject,
    required this.panelsMenu,
    this.door,
    this.keyRoad,
    this.brushTool,
    this.battery,
  });

  /// The projects open in the window — the strip's tabs (I-7).
  final OpenProjects projects;

  /// A tab's ✕ — the shell's, because closing asks about unsaved work with
  /// the project on screen, and lets its session go.
  final ValueChanged<EditorSessionManager> onCloseProject;

  /// The project on screen: what every entry in the project popover acts on.
  EditorSessionManager get session => projects.active;

  final WorkspacePanelsMenuController panelsMenu;

  /// The one door the 「파일 열기」 and 「폴더 열기」 rows knock on
  /// (F-282) — the workspace's, which holds what it hands files to. Null
  /// leaves the two rows dim (focused tests).
  final WorkspaceDoorCommands? door;

  /// The road the shell's keys run down — handed to the export window,
  /// which edits the sheets' papers under the same keys (I-127). Null
  /// leaves the window deaf to them (focused tests).
  final EditorKeyRoad? keyRoad;

  /// The active tool's settings. The size and opacity bars ride the strip's
  /// right end (프로크리·카리페그 배치) because they are values you set
  /// mid-stroke, and an anchored popover closes the moment you touch the
  /// canvas — a value button could never be adjusted against a test mark.
  ///
  /// They stand here only when [panelsMenu] says the brush's values are the
  /// strip's ([WorkspacePanelsMenuController.brushValuesOnStrip]); by
  /// default the canvas's pill holds them (I-34).
  ///
  /// Null leaves the right end empty (passive hosts and focused tests).
  final ValueNotifier<BrushToolState>? brushTool;

  /// The device's battery, at the strip's very end (I-103-Q1) — null on a
  /// device without one, which keeps no place for it ([DeviceBattery]).
  final ValueListenable<BatteryReading>? battery;

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
    List<PanelFlyoutEntry> Function()? submenuBuilder,
    List<String> shortcuts = const [],
  }) => PanelFlyoutItem(
    keyValue: 'menu-$id',
    // Every entry localizes HERE, by the id it is already keyed with, with
    // the English staying at the call sites where the strip is authored.
    label: AppText.strings.menuLabel(id, label),
    icon: icon,
    checked: checked,
    shortcuts: shortcuts,
    // A row that opens a SECOND level takes no tap of its own, so it has no
    // `onPressed` — and it must still be live (F-146).
    enabled: onPressed != null || submenuBuilder != null,
    onSelected: onPressed,
    submenuBuilder: submenuBuilder,
  );

  /// Every row of the strip's two menus as they would open right now
  /// ([flyoutRowsOf]) — what a KEY presses one of (I-40).
  ///
  /// 🗣️유저 2026-09-18: 「버튼 전수감사해서 숏컷리스트에 등록 … 설정의 패널
  /// 열기 닫기같은거든 뭐든 모든 버튼」. ★A KEY AND ITS ROW ARE ONE PRESS: the
  /// rows are built the way the menu builds them — a second level too — and
  /// the one that names the action is pressed if the menu would let it be
  /// ([pressFlyoutRow], which the shell runs over these and the timeline
  /// bar's). So a row that is dim does nothing by key either, and a row
  /// added to a menu with its action's name is reachable by key with no more
  /// written. [context] is where a row's window opens: the shell's own.
  List<PanelFlyoutItem> menuRows(BuildContext context) => flyoutRowsOf([
    ..._projectEntries(context),
    ..._settingsEntries(context),
  ]).toList();

  // --- File -----------------------------------------------------------------

  /// PICK-4: the recent projects — ONE row that opens them, or nothing at
  /// all.
  ///
  /// 🗣️유저 2026-09-16 (F-146): 「프로젝트버튼의 최근 프로젝트는 **최근
  /// 프로젝트라는 버튼안에** 넣고 … 시계아이콘?도 필요없고. **그걸 그냥 최근
  /// 프로젝트라는 버튼에 아이콘으로서** 넣고」. So the clock that repeated
  /// down every row is the row's own mark now, and the list it opens has a
  /// clean leading slot — a glyph that never varies says nothing.
  ///
  /// ⛔It is [PanelFlyoutItem.submenuBuilder], not a popover of its own —
  /// the second axis I-4 built for the colour labels (유저: 「추가
  /// 앵커팝오버는 색라벨같은거에서 공용화했을테니 그거사용」).
  ///
  /// Absent rather than empty-and-disabled when there is no history: a row
  /// that only ever says "no" is a row that should not be drawn.
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
      PanelFlyoutItem(
        keyValue: 'menu-recent-projects',
        label: strings.recentProjectsTitle,
        icon: Icons.history_outlined,
        submenuBuilder: () => [
          for (final entry in recents)
            PanelFlyoutItem(
              keyValue: 'menu-recent-${entry.path}',
              label: entry.needsReconnect
                  ? '${projectDisplayName(entry.name)} — '
                        '${strings.recentReconnect}'
                  : projectDisplayName(entry.name),
              // ⛔Only the ones that need something: a broken link is news,
              // "this is a recent project" is what the list already is.
              icon: entry.needsReconnect ? Icons.link_off_outlined : null,
              onSelected: () => unawaited(_openRecent(context, entry)),
            ),
        ],
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
        path = fileNameOfPath(resolved) == entry.name
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
    if (ProviderDocuments.isDocumentUri(path)) {
      // PICK-7: a document is reopened through its URI — the grant kept
      // from the pick is what reads it — and the name comes from the row,
      // the one place a new run has it.
      ProviderDocuments.remember(ProviderDocument(uri: path, name: entry.name));
    } else if (!File(path).existsSync()) {
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
    await ProjectOpenDoor(projects).open(context, (
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

  /// Whether the playhead stands in a cut — what the rows that write the
  /// film's pictures out ask. The export dialog is cut-anchored, and so is
  /// the picture Save As writes (its image tab's): off a cut, in the gap
  /// state, they are dim (UI-R9 #3).
  bool get _onACut => session.activeCutOrNull != null;

  /// The PROJECT popover: the file itself, and the two doors it has to the
  /// outside world. Export used to sit as its own icon in the strip; it is
  /// a once-a-session verb, so it belongs behind the same button as saving
  /// rather than costing a permanent slot.
  List<PanelFlyoutEntry> _projectEntries(BuildContext context) => [
    // 🗣️유저 2026-09-26 (I-7): 「새 프로젝트는 현재 프로젝트 냅두고 새로
    // 여는거야」 — a tab of its own beside the ones already open.
    _item(
      id: 'file-new',
      label: editorActionLabel(EditorActionIds.fileNew),
      shortcuts: const [EditorActionIds.fileNew],
      icon: Icons.note_add_outlined,
      onPressed: () => projects.open(newUntitledProject()),
    ),
    // 🗣️F-282 (유저 2026-10-09): 「열기랑 임포트랑 되도록 하나로」 — one
    // door for every file, and Q1 (가): 「파일 열기…」 and 「폴더 열기…」
    // as two rows. ↩️「열기…」 took projects alone, and 「가져오기/배치…」
    // below opened the import window on nothing.
    _item(
      id: 'file-open',
      label: editorActionLabel(EditorActionIds.fileOpen),
      shortcuts: const [EditorActionIds.fileOpen],
      icon: Icons.file_open_outlined,
      onPressed: door?.openFiles,
    ),
    _item(
      id: 'file-open-folder',
      label: editorActionLabel(EditorActionIds.fileOpenFolder),
      shortcuts: const [EditorActionIds.fileOpenFolder],
      icon: Icons.folder_open_outlined,
      onPressed: door?.openFolder,
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
    // 🗣️backlog-21-Q1 (유저 2026-10-08): 「「다른 이름으로 저장」에 둘째 단 —
    // 프로젝트(.anicel) · PNG · JPG」, and after those the formats I-117-Q1
    // added ([saveAsImageFormats]). The format is chosen HERE, the same
    // on every platform: Android's and iOS's save windows take one type
    // before they open and offer no list. The first row is the Save As there
    // always was, and Ctrl+Shift+S still presses it.
    _item(
      id: 'file-save-as-format',
      label: AppText.strings.saveAsTitle,
      icon: Icons.save_as_outlined,
      submenuBuilder: () => [
        _item(
          id: 'file-save-as',
          label: 'Project (.anicel)',
          shortcuts: const [EditorActionIds.fileSaveAs],
          onPressed: () => unawaited(promptSaveProjectAs(context, session)),
        ),
        for (final format in saveAsImageFormats)
          _item(
            id: saveAsImageActionId(format),
            label: format.label,
            shortcuts: [saveAsImageActionId(format)],
            onPressed: _onACut && stillFormatWritable(format)
                ? () => unawaited(saveFrameAsImage(context, session, format))
                : null,
          ),
      ],
    ),
    // 🗣️유저 2026-09-23: 「나중에 실패본에서 백업하기 … 해당파일
    // 지정해서」. Always in the list, off while this run holds no failed
    // copy — a row that appeared only after a refusal would be the UI that
    // pops into existence this app does not make.
    _item(
      id: 'file-back-up-failed-copy',
      label: editorActionLabel(EditorActionIds.fileBackUpFailedCopy),
      shortcuts: const [EditorActionIds.fileBackUpFailedCopy],
      icon: Icons.backup_outlined,
      onPressed: session.failedSaveCopies.entries.isEmpty
          ? null
          : () => unawaited(backUpFailedCopy(context, session)),
    ),
    ..._recentEntries(context),
    const PanelFlyoutDivider(),
    _item(
      id: 'file-export',
      label: editorActionLabel(EditorActionIds.fileExport),
      shortcuts: const [EditorActionIds.fileExport],
      icon: Icons.save_alt,
      onPressed: !_onACut
          ? null
          : () {
              unawaited(
                showDialog<void>(
                  context: context,
                  builder: (context) => ExportDialog(
                    session: session,
                    settingsStore: AppExportSettingsStore(),
                    keys: keyRoad,
                    paperEditing: door?.paperEditing,
                  ),
                ),
              );
            },
    ),
  ];

  // --- Settings -------------------------------------------------------------

  /// The SETTINGS popover: the app's own knobs, then two drawers — the
  /// WORKSPACE (`window-panels`) and the measurement switches
  /// (`edit-debug`).
  ///
  /// Undo, redo and the six frame verbs used to head this list. They were
  /// never settings — they are things you do to the work — and they now
  /// live on the tool rail and the timeline's command bar respectively.
  ///
  /// ↩️The panel switchboard and the three layout choices were siblings of
  /// Preferences and About until F-146, which made a list of what the
  /// WORKSPACE is read as a list of what the APP is. They are one drawer
  /// now (유저: 「도구 버튼부터 작업공간 배치 초기화까지 싹 다 패널설정
  /// 버튼안으로」). ⛔Behaviour unchanged where it is load-bearing: a closed
  /// panel still has no other way back than that list, one level in.
  List<PanelFlyoutEntry> _settingsEntries(BuildContext context) => [
    // 🗣️유저 09-25 (project-settings-window): 「작품명/화수는 이제
    // 타임시트패널같은곳에서 편집안하게 … 해당 설정은 프로젝트 설정쪽에
    // 버튼둬서. 상단띠의 설정버튼이 낫겟지」 — the work's words, above the
    // app's own settings.
    _item(
      id: 'work-settings',
      label: editorActionLabel(EditorActionIds.workSettings),
      shortcuts: const [EditorActionIds.workSettings],
      icon: Icons.theaters_outlined,
      onPressed: () => unawaited(
        askThenCommit<TimesheetInfo>(
          context,
          dialog: (_) => WorkSettingsWindow(
            initialInfo: session.timesheetInfo,
            projectName: session.repository.requireProject().name,
            pictures: [
              for (final asset in session.mediaPool.mediaAssets)
                if (asset.kind == MediaAssetKind.image) asset,
            ],
          ),
          commit: session.updateTimesheetInfo,
        ),
      ),
    ),
    // 유저 답 playback-quality-home-Q1 「프로젝트 설정으로 같이」 — 「다만
    // 프로젝트 설정이랑 작품설정이랑 나누는게 깔끔할지도?」: the project's own
    // values beside the work's, one level in — the sill's ⚙ rows, moved.
    _item(
      id: 'project-settings',
      label: 'Project settings',
      icon: Icons.video_settings_outlined,
      submenuBuilder: () => ProjectSettingsMenu(session).entries(context),
    ),
    const PanelFlyoutDivider(),
    _item(
      id: 'edit-keyboard-shortcuts',
      label: editorActionLabel(EditorActionIds.keyboardShortcuts),
      shortcuts: const [EditorActionIds.keyboardShortcuts],
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
      label: editorActionLabel(EditorActionIds.preferences),
      shortcuts: const [EditorActionIds.preferences],
      icon: Icons.tune,
      onPressed: () {
        unawaited(
          showPreferencesDialog(
            context,
            session: session,
            openSessions: projects.sessions,
          ),
        );
      },
    ),
    const PanelFlyoutDivider(),
    // 🗣️유저 2026-09-16 (F-146 ①): 「지금 툴/서브뷰어 이런게 흩뿌려져있는데,
    // **패널 이라는 곳에** 추가앵커팝오버로 해당 패널관련 설정들 넣고」, and
    // on being asked WHICH (`F-146-Q1`): 「그냥 **패널 관련 싹 다**야. **도구
    // 버튼부터 작업공간 배치 초기화까지 싹 다 패널설정 버튼안으로**」.
    //
    // So the switchboard and the three layout choices are one drawer. They
    // were siblings of Preferences and About, which made a list of what the
    // WORKSPACE is read as a list of what the APP is.
    //
    // ⛔The second level is [PanelFlyoutItem.submenuBuilder] — the axis I-4
    // built for the colour labels (유저: 「추가 앵커팝오버는 색라벨같은거에서
    // 공용화했을테니 그거사용」) — and the panel rows keep their keys, so a
    // closed panel's one path back is where it always was, one level in.
    _item(
      id: 'window-panels',
      label: 'Panels',
      icon: Icons.space_dashboard_outlined,
      submenuBuilder: () => [
        // The old Window menu. Every panel with its visibility — a closed
        // (X-ed) panel reopens ONLY from here, so this list is the one path
        // back and cannot be dropped with the rest of the menus.
        //
        // ⛔No glyph: it was `space_dashboard_outlined` on every row, which
        // is now the mark of the row they all live behind. A glyph that
        // never varies says only what the list already says.
        for (final entry in panelsMenu.entries)
          PanelFlyoutItem(
            keyValue: 'panels-menu-item-${entry.tabId}',
            label: entry.label,
            shortcuts: [panelActionId(entry.tabId)],
            checked: entry.visible,
            onSelected: () => panelsMenu.toggle(entry.tabId),
          ),
        const PanelFlyoutDivider(),
        // The left-handed choice. It was a tab drag until 고정 도킹 took the
        // grip away, and a strip you cannot move is the wrong answer for
        // half the people holding the stylus.
        _item(
          id: 'window-tool-rail-right',
          label: editorActionLabel(EditorActionIds.toolRailOnRight),
          shortcuts: const [EditorActionIds.toolRailOnRight],
          icon: Icons.flip,
          checked: panelsMenu.toolRailOnRight,
          onPressed: panelsMenu.canMoveToolRail
              ? () => panelsMenu.setToolRailOnRight(!panelsMenu.toolRailOnRight)
              : null,
        ),
        // 아래 도킹 영역은 위/아래 설정 가능 (유저 확정). What flips with it —
        // the resize handle to the other edge, the 문턱 with it, the square
        // corners to whichever side is against the frame — needed no new
        // rule: 「기하는 캔버스 향한 변에, 정체성은 창틀 향한 변에」 decides
        // all of it.
        _item(
          id: 'window-region-on-top',
          label: editorActionLabel(EditorActionIds.regionOnTop),
          shortcuts: const [EditorActionIds.regionOnTop],
          icon: Icons.vertical_align_top,
          checked: panelsMenu.regionOnTop,
          onPressed: panelsMenu.canMoveRegion
              ? () => panelsMenu.setRegionOnTop(!panelsMenu.regionOnTop)
              : null,
        ),
        // 🗣️I-34 (유저 2026-10-18): the brush's values stand in the canvas's
        // pill unless this row puts them back here.
        _item(
          id: 'window-brush-values-on-strip',
          label: editorActionLabel(EditorActionIds.brushValuesOnStrip),
          shortcuts: const [EditorActionIds.brushValuesOnStrip],
          icon: Icons.tune,
          checked: panelsMenu.brushValuesOnStrip,
          onPressed: panelsMenu.canMoveBrushValues
              ? () => panelsMenu.setBrushValuesOnStrip(
                  !panelsMenu.brushValuesOnStrip,
                )
              : null,
        ),
        // 🗣️I-128 (유저 2026-10-25): the shortcut buttons off the tool strip,
        // and the rule under them with them.
        _item(
          id: 'window-rail-tools-only',
          label: editorActionLabel(EditorActionIds.railToolsOnly),
          shortcuts: const [EditorActionIds.railToolsOnly],
          icon: Icons.handyman_outlined,
          checked: panelsMenu.railToolsOnly,
          onPressed: panelsMenu.canSetRailToolsOnly
              ? () => panelsMenu.setRailToolsOnly(!panelsMenu.railToolsOnly)
              : null,
        ),
        // 🗣️I-103-Q2 (유저 2026-10-16): 「데스크톱만 켜고 끄기, 모바일은
        // 지금처럼 늘 전체 화면」 — a row on the three desktops and none on
        // the iPad and Android, where there is nothing to switch. Its mark
        // is the window's, as its runner last said ([WindowFullScreen.on]).
        if (WindowFullScreen.offered)
          _item(
            id: 'window-full-screen',
            label: editorActionLabel(EditorActionIds.fullScreen),
            shortcuts: const [EditorActionIds.fullScreen],
            icon: Icons.fullscreen,
            checked: WindowFullScreen.on.value,
            onPressed: () => unawaited(
              WindowFullScreen.set(!WindowFullScreen.on.value),
            ),
          ),
        _item(
          id: 'window-reset-layout',
          label: editorActionLabel(EditorActionIds.resetLayout),
          shortcuts: const [EditorActionIds.resetLayout],
          icon: Icons.restart_alt,
          onPressed: panelsMenu.canResetLayout ? panelsMenu.resetLayout : null,
        ),
      ],
    ),
    const PanelFlyoutDivider(),
    // 🗣️유저 2026-09-16 (F-146): 「입력 인스펙터같은건 **디버그라는? 거기다**
    // 넣기」. Five measurement switches sat in the settings list beside the
    // panel switchboard, which made a list of things you use every day and a
    // list of things you use while hunting a jank read as one list.
    //
    // ⛔The second level is [PanelFlyoutItem.submenuBuilder] — the axis I-4
    // built for the colour labels — not a popover of its own (유저: 「추가
    // 앵커팝오버는 색라벨같은거에서 공용화했을테니 그거사용」).
    _item(
      id: 'edit-debug',
      label: 'Debug',
      icon: Icons.bug_report_outlined,
      submenuBuilder: () => [
        // The pen program's diagnosis overlay (PEN-1): toggles the live
        // pointer-event readout — kind/pressure/tilt straight from the
        // platform, the driver-vs-app separator.
        _item(
          id: 'edit-input-inspector',
          label: editorActionLabel(EditorActionIds.inputInspector),
          shortcuts: const [EditorActionIds.inputInspector],
          // ⛔Not the bug glyph: that one is the DEBUG row above, and a
          // child repeating its parent's mark says nothing. This one is
          // about the pointer.
          icon: Icons.touch_app_outlined,
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
          label: editorActionLabel(EditorActionIds.frameTimingOverlay),
          shortcuts: const [EditorActionIds.frameTimingOverlay],
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
          label: editorActionLabel(EditorActionIds.frameStats),
          shortcuts: const [EditorActionIds.frameStats],
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
          label: editorActionLabel(EditorActionIds.showRepaints),
          shortcuts: const [EditorActionIds.showRepaints],
          icon: Icons.flare_outlined,
          checked: MeasurementMode.showRepaints.value,
          onPressed: () {
            MeasurementMode.showRepaints.value =
                !MeasurementMode.showRepaints.value;
          },
        ),
        // ↩️「Bake Static Panels」, the bakes' A/B switch, stood here from
        // 2026-08-09 until the user had it taken out: off is only ever a loss
        // (유저 2026-10-23, F-448 「없애고 on인채로 두는게 맞지않을까」). Why
        // there is no global switch any more: `StaticRaster.enabled`.
      ],
    ),
    const PanelFlyoutDivider(),
    _item(
      id: 'help-about',
      label: editorActionLabel(EditorActionIds.about),
      shortcuts: const [EditorActionIds.about],
      icon: Icons.info_outline,
      // 🗣️app-version-shown (유저 2026-10-29): 「위치는 환경설정
      // 애니셀정보버튼 창 안에도 적음」 — this row's window says the build,
      // the line the launch notice's title carries.
      onPressed: () => showAboutDialog(
        context: context,
        applicationName: 'Anicel',
        applicationVersion: buildStamp,
      ),
    ),
    _item(
      id: 'help-send-feedback',
      label: editorActionLabel(EditorActionIds.sendFeedback),
      shortcuts: const [EditorActionIds.sendFeedback],
      icon: Icons.feedback_outlined,
      onPressed: () => showFeedbackWindow(context),
    ),
  ];

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
        const SizedBox(width: StripGroupRule.margin),
        const StripGroupRule(),
        const SizedBox(width: StripGroupRule.margin),
        _FloorSwitch(panelsMenu: panelsMenu),
        // 🗣️I-147 (유저 2026-10-30): 「상단띠에서 배경에 붙은 고정패널이랑
        // 변동이랑 구분하기위해 사이에 세로선추가. 환경설정/캔버스패널 사이에
        // 있는 같은 세로선」 — the floor's own two before it, which nothing
        // moves, and the buttons whose panels lie on the floor after it —
        // which stand the rule's margin before them where there are any
        // (`_WorkspaceStripButtons.build`).
        const SizedBox(width: StripGroupRule.margin),
        const StripGroupRule(),
        ListenableBuilder(
          listenable: panelsMenu,
          builder: (context, _) => panelsMenu.floorGroups(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          // The brush's values stand here only where the workspace says
          // so ([WorkspacePanelsMenuController.brushValuesOnStrip]).
          child: SlicedListenableBuilder<bool>(
            listenable: panelsMenu,
            slice: () => panelsMenu.brushValuesOnStrip,
            builder: (context, onStrip) => _TabsAndBrushGroup(
              tabs: _ProjectTabRow(projects: projects, onClose: onCloseProject),
              brushTool: onStrip ? brushTool : null,
              battery: battery,
            ),
          ),
        ),
        const SizedBox(width: 3),
      ],
    );
  }
}

/// The strip's flexible stretch: the project tabs, then the brush's group at
/// its end — and the ORDER THEY GIVE WAY IN when the window narrows.
///
/// 🗣️top-strip-narrow-overflow-Q1 (유저 2026-10-01): 「줄이지 않고 바로 ⋯
/// 목록으로」, corrected a minute later — 「답변 정정. 막대 먼저 줄어들고 다음
/// 목록으로」. The answer's own words: 「크기 · 불투명도 막대가 140px에서 이름과
/// 숫자가 막대 안에 들어가는 최소 폭까지 줄어든다. 그래도 안 들어가면 오른쪽
/// 브러시 묶음(혼합 모드 · 막대 · 필압 버튼)이 띠 끝의 ⋯ 버튼 하나로 들어가고,
/// 누르면 그 묶음이 팝오버로 뜬다. 탭 목록 버튼 자리는 끝까지 남는다. 탭
/// 줄이 이미 따르는 「줄이고 → 넘긴다」를 띠 전체에 같은 법으로」.
///
/// ⛔The group stood in the strip's row at its full width whatever the
/// window was, so under 770px — an iPad mini held upright is 744 — the tabs'
/// place fell below what one tab asks and the strip ran off its end
/// (measured 2026-10-01: 10px over at 760, 70 at 700, 46 + 34 at 640).
///
/// So the tabs give way first, as they always have (their own law: names
/// shorten, then tabs leave for the list button, which keeps its place);
/// with the tabs down to that place the two bars narrow, each as far as its
/// own writing allows ([FieldSlider.narrowestIn]); and past that the group
/// is one button.
///
/// And past THAT — a window too narrow for the button beside the list's
/// place, 320 (an iPad's third) — the group is all of it, smaller
/// ([KeptTailRow]): the list button's place is the one kept to the end, in
/// the answer's own words. ↩️The tabs were left less than that place, and
/// their row ran 15px over (measured 2026-10-15).
///
/// 🔬Measured 2026-10-07 in the app's faces at 1×, one project open: the
/// bars stand at 140 down to a 770 window and narrow from there; the group
/// is the button under 740 in English and in Japanese, under 727 in Korean,
/// under 750 in French. An iPad mini held upright (744) leaves the two bars
/// 254 between them, so it keeps its bars in the first three. ⚠️Measured
/// before each bar took its pencil (tool-settings-panel-tidy, 유저
/// 2026-10-10: 막대에도 연필을 「달도록」): each stands 21 wider since, so
/// these windows lie that much further out — not measured again.
///
/// Each bar goes to its OWN narrowest for that reason, not only because the
/// answer's words are each bar's: held to one width — the wider writing's,
/// English 「Size … 2000.0 px」 at 127.6 — the pair would ask for 255.2 of
/// those 254.
class _TabsAndBrushGroup extends StatelessWidget {
  const _TabsAndBrushGroup({
    required this.tabs,
    required this.brushTool,
    required this.battery,
  });

  final Widget tabs;
  final ValueNotifier<BrushToolState>? brushTool;
  final ValueListenable<BatteryReading>? battery;

  @override
  Widget build(BuildContext context) {
    // 🗣️I-103-Q1 (유저 2026-10-16): the battery stands after the brush's
    // group, at the very end, and is KEPT with it as the list button's place
    // is — the group gives way to its button that much sooner (the cost the
    // answer named), and a strip too narrow for even that shows both,
    // smaller.
    final gauge = switch (battery) {
      final battery? => _BatteryGauge(
        battery: battery,
        width: _BatteryGauge.widthIn(context),
      ),
      null => null,
    };
    final tool = brushTool;
    if (tool == null) {
      return gauge == null
          ? tabs
          : KeptTailRow(
              headKeeps: _ProjectTabRow._minTabWidth,
              head: tabs,
              tail: gauge,
            );
    }
    final narrowest = BrushValueBars.narrowestIn(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bars = BrushValueBars.widthsIn(
          // What the two bars may take between them once the tabs hold
          // only their list button's place and the group's fixed parts
          // and the battery stand.
          constraints.maxWidth -
              _ProjectTabRow._minTabWidth -
              _BrushGroup.fixedWidth -
              (gauge == null ? 0 : _BatteryGauge.gap + gauge.width),
          narrowest,
        );
        final group = bars != null
            ? _BrushGroup(brushTool: tool, bars: bars)
            : _BrushGroupButton(brushTool: tool);
        return KeptTailRow(
          headKeeps: _ProjectTabRow._minTabWidth,
          head: tabs,
          tail: gauge == null
              ? group
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    group,
                    const SizedBox(width: _BatteryGauge.gap),
                    gauge,
                  ],
                ),
        );
      },
    );
  }
}

/// The device's battery at the strip's very end (I-103-Q1): an icon that
/// fills with the charge — the bolt while on power — and the percent.
///
/// ONE width whatever it says ([widthIn]), so a charge that loses a digit
/// moves nothing beside it.
class _BatteryGauge extends StatelessWidget {
  const _BatteryGauge({required this.battery, required this.width});

  final ValueListenable<BatteryReading> battery;
  final double width;

  /// Between the brush's group and the gauge.
  static const double gap = 8;

  static const double _iconSize = 16;
  static const double _iconGap = 2;

  /// The charge as the icons draw it: none to six bars, then full.
  static const List<IconData> _levels = [
    Icons.battery_0_bar,
    Icons.battery_1_bar,
    Icons.battery_2_bar,
    Icons.battery_3_bar,
    Icons.battery_4_bar,
    Icons.battery_5_bar,
    Icons.battery_6_bar,
    Icons.battery_full,
  ];

  /// The size the project tabs write their names in.
  static TextStyle _styleIn(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(const TextStyle(fontSize: 12));

  /// The icon and the widest percent the gauge can write — measured, as the
  /// bars' floors are, so another face or OS text size still fits.
  static double widthIn(BuildContext context) =>
      _iconSize +
      _iconGap +
      TextMeasure(context, _styleIn(context)).widest([
        '100%',
        ...everyDigitIn((digit) => '$digit$digit%'),
      ]).ceilToDouble();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ValueListenableBuilder<BatteryReading>(
      valueListenable: battery,
      builder: (context, reading, _) => SizedBox(
        key: const ValueKey<String>('top-strip-battery'),
        width: width,
        child: Row(
          children: [
            Icon(
              reading.charging
                  ? Icons.battery_charging_full
                  : _levels[(reading.percent * (_levels.length - 1) / 100)
                        .round()],
              size: _iconSize,
              color: color,
            ),
            const SizedBox(width: _iconGap),
            Text(
              '${reading.percent}%',
              maxLines: 1,
              style: _styleIn(context).copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The brush's group as the strip shows it.
class _BrushGroup extends StatelessWidget {
  const _BrushGroup({required this.brushTool, required this.bars});

  final ValueNotifier<BrushToolState> brushTool;
  final BrushBarWidths bars;

  /// Between the blend, the rule and the bars — the rule's own margin.
  static const double _gap = StripGroupRule.margin;

  /// Everything of the group that is not a bar.
  static const double fixedWidth =
      BrushBlendModeControl.buttonWidth +
      _gap +
      StripGroupRule.width +
      _gap +
      BrushValueBars.fixedWidth;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // 유저 확정 order, left to right: blend + its lock, a rule, then
      // size and opacity each with their pressure curve, then the colour.
      // The rule is what makes the first two read as one group rather
      // than as a button that has wandered next to a slider.
      BrushBlendModeControl(brushTool: brushTool),
      const SizedBox(width: _gap),
      const StripGroupRule(),
      const SizedBox(width: _gap),
      BrushValueBars(brushTool: brushTool, widths: bars),
      // 컬러 창은 상단띠에서 오른쪽 서브띠 맨 위로 (유저 확정). It was
      // the one surface that opened DOWNWARD out of a strip; as a rail
      // group it opens sideways like everything else, and the swatch
      // goes with it — the rail button IS the pair now. 42px back.
    ],
  );
}

/// The brush's group as ONE button, for a strip with no room for the group:
/// pressed, the same controls open under it, one to a line — a window this
/// narrow has no width to lay them side by side in.
///
/// ⚠️The bars' own note stands (below): a popover closes on the first press
/// outside it, so here a value is set by open → set → close → draw. That is
/// the cost the answer was shown and took, for windows too narrow for the
/// narrowed bars.
class _BrushGroupButton extends StatelessWidget {
  const _BrushGroupButton({required this.brushTool});

  final ValueNotifier<BrushToolState> brushTool;

  static const double _padding = 8;
  static const double _lineGap = BrushValueBars.lineGap;

  @override
  Widget build(BuildContext context) {
    // The names of what is under it, in the words those controls wear —
    // what the button says, and what its popover is called (the popover's
    // name is read out, so it is words and not a key).
    final name =
        '${AppText.strings.brBlend} · ${AppText.strings.brSize} · '
        '${AppText.strings.brOpacity}';
    return RailButton(
      keyValue: 'top-strip-brush-group-button',
      tooltip: name,
      icon: Icons.more_horiz,
      selected: false,
      onPressed: () => unawaited(
        showAnchoredPopup<void>(
          context,
          label: name,
          width:
              _padding * 2 +
              BrushValueBars.fullBar +
              BrushValueBars.gap +
              SettingSourceButton.slotWidth,
          height:
              _padding * 2 + BrushValueBars.barHeight * 3 + _lineGap * 2,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(_padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: BrushValueBars.barHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: BrushBlendModeControl(brushTool: brushTool),
                  ),
                ),
                const SizedBox(height: _lineGap),
                BrushValueBars(
                  brushTool: brushTool,
                  widths: BrushValueBars.full,
                  layout: BrushValuesLayout.popover,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a project tab says: the saved file's name without its extension,
/// the name a project not saved yet came with from the file it was read
/// out of (a .tvpp, a .clip — 유저 10-09: 「애초에 프로젝트이름=파일이름
/// 아닌가? 애니셀이든 뭐든」), or 「Untitled n」 for a new one — the one
/// label the tab row and its overflow list both show.
///
/// ↩️The strip's middle used to be BLANK before the first save: 「a
/// standing "Untitled" would be a label that never becomes anything; the
/// empty middle is where the project switcher goes when more than one can
/// be open」 (472c99d0b — this code's own reasoning, not a ruling). The
/// switcher came (I-7), and a blank tab is one nobody can tell from the
/// next; 「Untitled n」 does become something — the file's name, at the
/// first save.
///
/// ⛔[projectDisplayName] is the sentence the recent list asks too (F-146).
String projectTabLabel(OpenProjects projects, EditorSessionManager session) {
  final path = session.projectFile.path;
  if (path != null) {
    return projectDisplayName(path);
  }
  final untitled = projects.untitledNumberOf(session);
  if (untitled == null) {
    return session.repository.requireProject().name;
  }
  return untitledProjectName(untitled);
}

/// The open projects, one tab each — the strip's middle (I-7).
///
/// 🗣️유저 2026-09-26: 「상단띠에 프로젝트 리스트있고 닫기버튼있고」, and
/// 「닫기버튼은 프로젝트 탭에 닫기버튼있으니 필요없을거같다」 — a tab is how a
/// project is both shown and closed. Its ✕ is always there, not on hover:
/// a control that appears under the pointer is UI this app does not make.
///
/// ⛔Selection is COLOUR only — the shown tab wears the raised fill and the
/// accent label. The tabs share the row and shrink with it, their names cut
/// short; what cannot fit at [_minTabWidth] waits in a list at the row's
/// end, in a tab's place — the panel strips' law for a row too full
/// (「넘치면 오버플로로 넘긴다」), and with it their other half: the tabs
/// shown never depend on which one is selected (tabs jumping under the
/// pointer when you pick one), so a selected tab in the list is spoken for
/// by the list's button instead.
class _ProjectTabRow extends StatelessWidget {
  const _ProjectTabRow({required this.projects, required this.onClose});

  final OpenProjects projects;
  final ValueChanged<EditorSessionManager> onClose;

  static const double _minTabWidth = 96;
  static const double _maxTabWidth = 200;

  @override
  Widget build(BuildContext context) {
    final sessions = projects.sessions;
    final active = projects.active;
    return LayoutBuilder(
      builder: (context, constraints) {
        var room = sessions.length;
        if (room * _minTabWidth > constraints.maxWidth) {
          // The list's button takes one tab's place.
          room = (constraints.maxWidth / _minTabWidth).floor() - 1;
          room = room < 0 ? 0 : room;
        }
        final shown = sessions.take(room).toList();
        final hidden = sessions.skip(room).toList();
        return Row(
          children: [
            for (final session in shown)
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxTabWidth),
                  child: _ProjectTab(
                    index: sessions.indexOf(session),
                    label: projectTabLabel(projects, session),
                    selected: identical(session, active),
                    onSelected: () => projects.activate(session),
                    onClose: () => onClose(session),
                  ),
                ),
              ),
            if (hidden.isNotEmpty)
              SizedBox(
                width: _minTabWidth,
                child: _ProjectTabOverflow(
                  projects: projects,
                  hidden: hidden,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One project's tab: its name, and its ✕.
class _ProjectTab extends StatelessWidget {
  const _ProjectTab({
    required this.index,
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.onClose,
  });

  final int index;
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = AppShapes.control(AppShapes.controlSmall);
    // Pressing the shown tab does nothing, so it takes no press at all.
    final press = selected ? null : onSelected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: AppTooltip(
        message: label,
        child: Material(
          color: selected ? colorScheme.surfaceContainerHigh : null,
          shape: shape,
          type: selected ? MaterialType.canvas : MaterialType.transparency,
          child: ControlPressClaim(
            onPressed: press,
            child: InkWell(
              mouseCursor: AppCursors.press,
              key: ValueKey<String>('project-tab-$index'),
              customBorder: shape,
              onTap: silentPress(press),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        // The key the strip's name has always worn, on the
                        // name of the project on screen.
                        key: selected
                            ? const ValueKey<String>('top-strip-project-name')
                            : null,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    // The window's own ✕ — the same button, the same size.
                    AppIconButton(
                      keyValue: 'project-tab-close-$index',
                      tooltip: AppText.strings.commonClose,
                      size: AppIconButtonSize.micro,
                      icon: const Icon(Icons.close),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tabs that did not fit, in a list — and, while the project on screen
/// is one of them, its name, since no tab is lit anywhere else.
class _ProjectTabOverflow extends StatelessWidget {
  const _ProjectTabOverflow({required this.projects, required this.hidden});

  final OpenProjects projects;
  final List<EditorSessionManager> hidden;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sessions = projects.sessions;
    final active = projects.active;
    final activeHidden = hidden.any((session) => identical(session, active));
    return PanelFlyoutTrigger(
      key: const ValueKey<String>('project-tab-overflow'),
      tooltip: '+${hidden.length}',
      padding: EdgeInsets.zero,
      // ⛔NOT a check: the open one accents, as a tab does.
      entriesBuilder: () => hidden.asFlyoutValueChoices(
        current: active,
        choiceOf: (session) => PanelFlyoutChoice(
          key: 'project-tab-overflow-${sessions.indexOf(session)}',
          label: projectTabLabel(projects, session),
        ),
        onPicked: projects.activate,
      ),
      child: Center(
        child: Text(
          activeHidden
              ? projectTabLabel(projects, active)
              : '+${hidden.length}',
          key: activeHidden
              ? const ValueKey<String>('top-strip-project-name')
              : null,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: activeHidden
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
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

/// Points the FILE picker at a project and answers what it grants: the
/// first file, its bookmark, and `placed: false` — nothing was written, so
/// whoever asked still has to write it.
///
/// The pick behind Reconnect — a recents row pointed at its project again.
/// What it answers for the file it is granted is what every project pick
/// answers ([projectPickOf]).
///
/// ↩️Open was its other caller until F-282 (2026-10-09): 「파일 열기」
/// takes every kind now, several at once, through the one door's pick
/// (`pickFilesToOpen`).
Future<ProjectPick?> pickProjectFile(
  BuildContext context, {
  required List<String> supportedExtensions,
  String? initialDirectory,
}) async {
  // A project opens from a document with no filesystem path through a
  // working copy (PICK-7, Drive on Android).
  final grant = await pickProjectGrantForUser(
    context,
    supportedExtensions: supportedExtensions,
    initialDirectory: initialDirectory,
  );
  return grant == null ? null : projectPickOf(grant);
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
///
/// On a scoped platform a destination with no filesystem path (PICK-7,
/// Drive on Android) is answered with its WORKING COPY — what the picker
/// poured in, kept for the saves that follow ([placeStagedFileForUser]).
/// A caller that does not go on saving there lets it go
/// ([ProviderDocuments.letGo]).
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
  // [name] carries the suffix, and the save window's door answers for it:
  // Windows shows the filter and never appends the extension, and the
  // suffixed name is asked the replace question the window asked of the
  // bare one (F-14 — [pickSaveFileForUser]).
  final grant = await pickSaveFileForUser(
    context,
    suggestedName: name,
    initialDirectory: initialDirectory,
    acceptedTypeGroups: const [FileTypeGroups.anicelProject],
  );
  final picked = grant?.path;
  return picked == null
      ? null
      : (path: picked, folderBookmark: grant!.bookmark, placed: false);
}

Future<ProjectPick?> _pickScopedSaveTarget(
  BuildContext context,
  String name,
  Future<void> Function(String stagingPath) stageArchive,
) async {
  final grant = await placeStagedFileForUser(
    context,
    suggestedName: name,
    keepsSavingThere: true,
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
      // buttons can undo, and this one they mostly cannot. A failed copy
      // comes next: the work is somewhere, but only until the program
      // closes (유저 2026-09-23: 「이 실패본은 프로그램 닫으면 사라진다고
      // 안내」).
      message: vanished
          ? strings.closeProjectVanishedBody
          : session.projectFile.failedCopy != null
          ? strings.closeProjectFailedCopyBody
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
        // 🗣️F-479-Q2 (유저 2026-10-27): 「닫기 창은 「저장」을 강조 버튼으로 —
        // Enter = 저장하고 닫기」 — the accent is on the answer that keeps the
        // work, so the window opens on it: a stray Enter saves once more and
        // loses nothing.
        AppWindowAction(
          label: strings.commonSave,
          actionKey: const ValueKey<String>('system-exit-save'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(UnsavedWorkChoice.save),
        ),
        // ⛔Danger, not the window's yes: it throws the work away, as every
        // answer that does wears danger (`ConfirmChoice.emphasis`). Kept as
        // the accent since the two-button gate of 07-19, it would have been
        // the button this window opens on (F-479-Q1) — a stray Enter from
        // losing what the window exists to keep.
        AppWindowAction(
          label: strings.commonClose,
          actionKey: const ValueKey<String>('system-exit-close'),
          emphasis: AppWindowActionEmphasis.danger,
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
  // 🗣️F-304 (유저 2026-10-06): 「…그게아니라 저장준비중 이라는 창을 띄우는게
  // 좋을듯」. Until the write first counts, the save is gathering what it
  // writes — on this isolate, and for a heavy session long — and the
  // window's changing line says so; the first count hands the line back to
  // the running label, and each stretch after it names itself (🗣️F-494,
  // 유저 2026-10-28: 「저장중 말고 … 하고있는 과정을 보여주는식으로」).
  final line = _SaveLine(AppText.strings.savePrepareRunning);
  try {
    await runWithAppProgress<void>(
      context: context,
      title: AppText.strings.commonSave,
      titleIcon: Icons.save_outlined,
      runningLabel: AppText.strings.saveProgressRunning,
      doneLabel: AppText.strings.saveProgressDone,
      windowKey: const ValueKey<String>('save-progress-dialog'),
      runningStatus: line,
      task: (report) =>
          session.projectDoor.saveProjectToFile(
            path,
            asked: SaveAsked.byAPerson,
            onProgress: (fraction) {
              line.counted();
              report(fraction);
            },
            onStretch: line.say,
          ),
    );
    if (context.mounted) {
      _tellWhatTheSaveCouldNotCarry(context, session);
    }
    return true;
  } on SaveFailure catch (failure) {
    if (context.mounted) {
      unawaited(showSaveFailure(context, session, failure));
    }
    return false;
  } on Object catch (error) {
    if (context.mounted) {
      showFileError(context, error);
    }
    return false;
  } finally {
    line.dispose();
  }
}

/// The running line of a save's window: [gathering] until the save first
/// counts or names a stretch, the running label at its first count, and
/// the stretch under way once one is named ([SaveStretch]).
///
/// ⚠️A count does not take a stretch's name back: the media set aside
/// count on this isolate after their stretch was named, and the write
/// names its own when it moves on.
class _SaveLine extends ValueNotifier<String> {
  _SaveLine(super.gathering);

  bool _named = false;

  /// The save counted.
  void counted() {
    if (!_named) {
      value = '';
    }
  }

  /// The save is in [stretch] now.
  void say(SaveStretch stretch) {
    _named = true;
    value = AppText.strings.saveStep(stretch);
  }
}

/// 🚨★★★**A SAVE ITS FILE REFUSED SAYS SO THEN — WHY, AND WHERE THE WORK
/// IS.**
///
/// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file): 「저장에 실패하여
/// 앱컨테이너에 있다는걸 그 상황에 알려주기 … 왜 실패했는지(파일을
/// 잡고있어서)같은것들 정확하게 알기쉽게 명시」, and 「이 실패본은 프로그램
/// 닫으면 사라진다고 안내」. The notice used to be the exception's own text.
///
/// From both ends a save can fail at: a person's ([saveProjectShowingProgress])
/// and the clock's (the shell hears the autosave's failure). The backup the
/// notice offers is there whenever there is a failed copy to back up —
/// and greyed out, not missing, when even that could not be written.
Future<void> showSaveFailure(
  BuildContext context,
  EditorSessionManager session,
  SaveFailure failure,
) {
  final strings = AppText.strings;
  final copy = failure.failedCopy;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AppConfirmDialog(
      windowKey: const ValueKey<String>('save-failure-notice'),
      title: strings.saveFailedTitle,
      titleIcon: Icons.error_outline,
      message: saveFailureMessage(failure),
      details: [
        NoticeDetails([
          if (copy != null) strings.saveFailedCopyLine(copy),
          strings.saveFailedErrorLine('${failure.error}'),
        ], heading: strings.saveFailedDetailsHeading),
      ],
      actions: [
        AppWindowAction(
          label: editorActionLabel(EditorActionIds.fileBackUpFailedCopy),
          actionKey: const ValueKey<String>('save-failure-back-up'),
          onPressed: copy == null
              ? null
              : () {
                  Navigator.of(dialogContext).pop();
                  unawaited(backUpFailedCopy(context, session, copy: copy));
                },
        ),
        AppWindowAction(
          label: strings.commonClose,
          actionKey: const ValueKey<String>('save-failure-close'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

/// What a person is told about [failure]: why the file refused, where the
/// work is now — and that it goes when the program does — and how the file
/// gets it after all.
String saveFailureMessage(SaveFailure failure) {
  final strings = AppText.strings;
  final why = switch (failure.cause) {
    SaveFailureCause.fileInUse => strings.saveFailedFileInUse,
    SaveFailureCause.readOnly => strings.saveFailedReadOnly,
    SaveFailureCause.diskFull => strings.saveFailedDiskFull,
    SaveFailureCause.locationGone => strings.saveFailedLocationGone,
    SaveFailureCause.replaceRefused => strings.saveFailedReplaceRefused,
    SaveFailureCause.unknown => strings.saveFailedUnknown,
  };
  final where = failure.failedCopy == null
      ? strings.saveFailedNoCopy
      : strings.saveFailedCopyKept;
  return '$why\n\n$where\n\n${strings.saveFailedRetry}';
}

/// 「실패본 백업」: a failed copy, saved where the person chooses.
///
/// 🗣️유저 2026-09-23: 「유저가 그 파일 따로 뭐 복사해서 저장해놔서 나중에
/// 실패본에서 백업하기 … 해당파일 지정해서 백업할수있게」. [copy] names the
/// one to back up (the notice's); without it the one there is is taken, or
/// the person picks among several — a run that met refusals in more than
/// one project keeps each one's until it ends.
///
/// The destination is asked the way Save As asks it, on every platform —
/// the save dialog on the desktop, the export picker that places a staged
/// file where there is none — and the session does not move there: a
/// backup is a copy to keep, not where this project saves from now on.
Future<void> backUpFailedCopy(
  BuildContext context,
  EditorSessionManager session, {
  String? copy,
}) async {
  final chosen = await _failedCopyToBackUp(context, session, copy);
  if (chosen == null || !context.mounted) {
    return;
  }
  final strings = AppText.strings;
  // ⚠️The order Save As keeps (유저 2026-08-31): where a picker PLACES a
  // staged file, the window before it says 「Ready」 — nothing is backed up
  // until the picker has put it somewhere — and 「Backed up」 comes after.
  Future<void> backUpTo(
    String destination, {
    required String running,
    required String done,
  }) => runWithAppProgress<void>(
    context: context,
    title: strings.commonSave,
    titleIcon: Icons.backup_outlined,
    runningLabel: running,
    doneLabel: done,
    windowKey: const ValueKey<String>('failed-copy-backup-progress'),
    task: (report) =>
        session.projectDoor.backUpFailedCopy(chosen.copyPath, destination),
  );
  try {
    final beside = folderOfPath(chosen.projectPath);
    final pick = await pickProjectSaveTarget(
      context,
      _backupNameFor(chosen),
      beside.isEmpty ? ensuredAppDocumentsDirectorySync() : beside,
      stageArchive: (stagingPath) => backUpTo(
        stagingPath,
        running: strings.savePrepareRunning,
        done: strings.savePrepareDone,
      ),
    );
    if (pick == null || !context.mounted) {
      return;
    }
    if (pick.placed) {
      // A backup is a copy to keep, not where the project saves from now
      // on: a working copy kept for a document it went into goes (PICK-7).
      ProviderDocuments.letGo(pick.path);
      await _sayFailedCopyBackedUp(context);
      return;
    }
    await backUpTo(
      pick.path,
      running: strings.failedCopyBackingUp,
      done: strings.failedCopyBackedUp,
    );
  } on Object catch (error) {
    if (context.mounted) {
      showFileError(context, error);
    }
  }
}

/// The picker PLACED the staged backup, so it is backed up now — and now is
/// when it says so: the other half of the order Save As keeps.
Future<void> _sayFailedCopyBackedUp(BuildContext context) =>
    runWithAppProgress<void>(
      context: context,
      title: AppText.strings.commonSave,
      titleIcon: Icons.backup_outlined,
      runningLabel: AppText.strings.failedCopyBackingUp,
      doneLabel: AppText.strings.failedCopyBackedUp,
      windowKey: const ValueKey<String>('failed-copy-backup-placed'),
      task: (report) async => report(1),
    );

/// Which failed copy a backup is of: [copy] when the notice named one, the
/// one there is, or the person's pick among several.
Future<FailedSaveCopy?> _failedCopyToBackUp(
  BuildContext context,
  EditorSessionManager session,
  String? copy,
) async {
  final standing = session.failedSaveCopies.entries;
  if (copy != null) {
    return standing.where((entry) => entry.copyPath == copy).firstOrNull;
  }
  if (standing.length <= 1) {
    return standing.firstOrNull;
  }
  return _pickFailedCopy(context, standing);
}

/// A name for [copy]'s backup beside its project that is not the project
/// file itself — the file that refused the save, which a backup offered
/// under its own name would be written over.
String _backupNameFor(FailedSaveCopy copy) {
  final name = fileNameOfPath(copy.projectPath);
  final dot = name.lastIndexOf('.');
  final stem = dot <= 0 ? name : name.substring(0, dot);
  final at = copy.savedAt;
  return '$stem-${at.year}${_twoDigits(at.month)}${_twoDigits(at.day)}-'
      '${_twoDigits(at.hour)}${_twoDigits(at.minute)}$anicelProjectSuffix';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// Which of several failed copies to back up — each answer names its
/// project and when it was written; the full paths are in the fold.
Future<FailedSaveCopy?> _pickFailedCopy(
  BuildContext context,
  List<FailedSaveCopy> copies,
) {
  final strings = AppText.strings;
  String clock(DateTime at) =>
      '${_twoDigits(at.hour)}:${_twoDigits(at.minute)}';
  return showDialog<FailedSaveCopy>(
    context: context,
    builder: (dialogContext) => AppConfirmDialog(
      windowKey: const ValueKey<String>('failed-copy-pick'),
      title: strings.failedCopyPickTitle,
      titleIcon: Icons.backup_outlined,
      message: strings.failedCopyVanishOnClose,
      details: [
        NoticeDetails([
          for (final copy in copies)
            '${copy.projectPath} — ${clock(copy.savedAt)}',
        ], heading: strings.saveFailedDetailsHeading),
      ],
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('failed-copy-pick-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        for (final (index, copy) in copies.indexed)
          AppWindowAction(
            label:
                '${fileNameOfPath(copy.projectPath)} · ${clock(copy.savedAt)}',
            actionKey: ValueKey<String>('failed-copy-pick-$index'),
            onPressed: () => Navigator.of(dialogContext).pop(copy),
          ),
      ],
    ),
  );
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
        NoticeDetails([
          for (final place in celPlacesOf(
            session.repository.requireProject(),
            lost,
          ))
            celPlaceLine(place, framePlace: session.framePlaceLabel),
        ], heading: strings.saveCelsLostHeading),
      ],
      windowKey: const ValueKey<String>('save-cels-lost-notice'),
    ),
  );
}

/// Writes the whole live session to [stagingPath] and answers what it wrote
/// — [ProjectFileDoor.writeArchiveCopy] in production — telling `report`
/// how far it is and `say` which [SaveStretch] it is in.
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
      void Function(SaveStretch stretch) say,
    );

Future<void> promptSaveProjectAs(
  BuildContext context,
  EditorSessionManager session, {
  ProjectArchiveWriter? writeArchive,
}) async {
  final suggested =
      '${sanitizeExportFileComponent(session.repository.requireProject().name)}'
      '$anicelProjectSuffix';
  final beside = folderOfPath(session.projectFile.path ?? '');
  // 🚨THE SYNC TWIN, like the open door's pick (`pickFilesToOpen`) — one file
  // asking one question one way. The async spelling stood here and it is
  // documented as unusable from a widget test: 「sync dart:io works under
  // the widget-test clock; async never completes there」. So the FIRST LINE
  // of the flow whose ordering F-57 is about could never be reached by a
  // test, whatever seam it was given.
  final initialDirectory = beside.isEmpty
      ? ensuredAppDocumentsDirectorySync()
      : beside;
  // What the staged archive holds, kept from the staging call to the
  // adoption below — the two are one decision ("this file is the project
  // now") split across the picker that sits between them.
  StagedArchive? staged;
  final write =
      writeArchive ??
      (
        String path,
        void Function(double) report,
        void Function(SaveStretch stretch) say,
      ) => session.projectDoor.writeArchiveCopy(
        path,
        asked: SaveAsked.byAPerson,
        onProgress: report,
        onStretch: say,
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
    // Its line names each stretch of the write, as a save's does (F-494).
    stageArchive: (stagingPath) async {
      final line = _SaveLine('');
      try {
        await runWithAppProgress<void>(
          context: context,
          title: AppText.strings.commonSave,
          titleIcon: Icons.save_outlined,
          runningLabel: AppText.strings.savePrepareRunning,
          doneLabel: AppText.strings.savePrepareDone,
          windowKey: const ValueKey<String>('save-progress-dialog'),
          runningStatus: line,
          task: (report) async {
            staged = await write(stagingPath, report, line.say);
          },
        );
      } finally {
        line.dispose();
      }
    },
  );
  if (pick == null || !context.mounted) {
    return;
  }
  // F-14: the suffix is the PICK's answer now — it is the only place that
  // can also answer for the placeholder it left at the un-suffixed name.
  final path = pick.path;
  // ONE FILE, ONE WRITER (I-7): another tab's file is refused here, in
  // words, before a byte is written to it — the door refuses the same path
  // on its own ([ProjectFile.isOpenElsewhere]). ⚠️A platform whose picker
  // PLACES the archive has written it by now; refusing still keeps this
  // session from binding there, which is the second writer.
  if (session.projectFile.isOpenElsewhere(path)) {
    await showAppNotice(
      context,
      windowKey: const ValueKey<String>('file-open-in-another-tab-notice'),
      title: AppText.strings.commonNotice,
      message: AppText.strings.fileOpenInAnotherTab,
    );
    return;
  }
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
    // true.
    if (context.mounted) {
      await _saySavedOncePlaced(context);
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

/// The picker PLACED what was saved, so it is saved now — and now is when
/// it says so: the other half of the order Save As keeps (유저 2026-08-31).
/// There is no work left to do, so the window is a confirmation and lingers
/// exactly as long as any other save's does.
Future<void> _saySavedOncePlaced(BuildContext context) =>
    runWithAppProgress<void>(
      context: context,
      title: AppText.strings.commonSave,
      titleIcon: Icons.save_outlined,
      runningLabel: AppText.strings.saveProgressRunning,
      doneLabel: AppText.strings.saveProgressDone,
      windowKey: const ValueKey<String>('save-placed-dialog'),
      task: (report) async => report(1),
    );

/// 「다른 이름으로 저장」's picture: [_pictureSaveAsWrites] as ONE [format]
/// file, where the person says — and the project stays the file it was. A
/// copy, never where it saves from now on.
Future<void> saveFrameAsImage(
  BuildContext context,
  EditorSessionManager session,
  ExportStillFormat format,
) async {
  final frame = frameUnderThePlayhead(session);
  if (frame == null) {
    return;
  }
  final writePicture = _pictureSaveAsWrites(session, frame, format);
  // The export window's image, and named as it is: after the cut it is a
  // frame of (F-404 — 「이미지는 기본적으로 현재컷이 대상인거니 … 컷이름」).
  final name = unnamedExportName(
    session.repository.requireProject(),
    cut: frame.cut,
  );
  final strings = AppText.strings;
  // ⚠️The order Save As keeps (유저 2026-08-31): where the file is written
  // into the app for a picker to place, the write ends 「Ready」, and
  // 「Saved」 waits for the picker.
  final staged = writtenFileIsStagedFirst;
  try {
    final placed = await handWrittenFileToUser(
      context,
      suggestedName: '$name.${format.fileExtension}',
      write: (path) => runWithAppProgress<bool>(
        context: context,
        title: strings.commonSave,
        titleIcon: Icons.save_outlined,
        runningLabel: staged
            ? strings.savePrepareRunning
            : strings.saveProgressRunning,
        doneLabel: staged ? strings.savePrepareDone : strings.saveProgressDone,
        windowKey: const ValueKey<String>('save-progress-dialog'),
        task: (report) async {
          final written = await writePicture(path);
          // ⛔Never 「Saved」 over no file: the throw takes the window down
          // before it says so, and the notice below says why.
          return written ? true : throw const _NothingWritten();
        },
      ),
    );
    if (placed != null && staged && context.mounted) {
      await _saySavedOncePlaced(context);
    }
  } on Object catch (error) {
    if (context.mounted) {
      showFileError(context, error);
    }
  }
}

/// What [saveFrameAsImage] writes as [format] — [task], the frame under the
/// playhead, at the canvas's size — as a writer of it to a path.
///
/// 🗣️backlog-21 (유저 08-13): 「다른이름으로 저장으로 csp처럼 현재
/// 보이는대로 png나 jpg 이런식으로 저장하게하고싶어. 물론 캔버스영역으로
/// 클립하는건 당연」. What it takes is Q7's answer (09-30): 「내보내기
/// 「이미지」와 같은 깨끗한 한 장」 — the image tab's picture at size =
/// canvas ([writeFrameImage]): the layers as they show, none of the editing
/// marks, the view's rotation and flip ignored, the pasteboard cut off. Its
/// settings are that tab's defaults, not the ones last used there: this is
/// Save As, not the export window — all but its ground. Whatever the
/// format, the picture stands on the project's PAPER as the canvas shows
/// it, its colour and its alpha; where the paper is absent or thin, a file
/// that keeps alpha (PNG) keeps nothing there and one that cannot (JPG)
/// shows white.
///
/// 🗣️F-371 (유저 10-16): 「그냥 저번처럼 RGBA 고정으로. 다만 RGB로직
/// 만든건 좋고 출력에서도 쓰니 그건 건들지않음. 설정만 RGBA로 할뿐」 ·
/// 「바탕 앱에서 설정한 캔버스 색 따라감. 캔버스색이 없으면 투명인거고
/// 그런식」 — the 캔버스 색 is the paper's swatch (`viewCanvasColor`) — and
/// the JPG with it, as the rule for every picture Save As writes: 「jpg도
/// 바탕 흰색고정말고 용지색으로 가자. 없음같은 투명한상황에서만 흰색으로
/// 하고. 앞으로 다른이름저장은 기본적으로 anicel형식아닌 이미지형식은 그걸
/// 기본으로」.
/// ↩️F-335 (유저 10-10) had made the PNG RGB on white, as the JPG was:
/// 「다른이름저장의 png, 형식 기본값 RGB의 배경흰색으로」.
Future<bool> Function(String path) _pictureSaveAsWrites(
  EditorSessionManager session,
  ExportFrameTask task,
  ExportStillFormat format,
) {
  final spec = ImageExportSpec(
    format: ExportFormatSelection(
      kind: ExportMediaKind.still,
      stillFormat: format,
      // A format that keeps no alpha makes its file RGB itself
      // ([ExportFormatSelection.effectiveChannels]).
      channels: ExportChannels.rgba,
      // ⚠️White where the paper lets the ground show in a file with no
      // alpha — not the window's default ground
      // ([defaultExportBackgroundArgb]), which answers what the export
      // window starts on and may change on its own.
      backgroundArgb: 0xFFFFFFFF,
    ),
    sizeMode: ExportSizeMode.canvas,
  );
  final paper = session.projectSettings.projectBackground;
  return (path) => writeFrameImage(
    session,
    task,
    spec,
    (
      directory: File(path).parent.path,
      name: fileNameOfPath(path),
      isCancelled: null,
      onProgress: null,
      // Its pictures are the picture alone ([saveAsImageFormats] has no
      // PSD): nothing is left out of one.
      onLeftOut: null,
    ),
    paper: paper,
  );
}

/// What a picture save that made no file says: the image tab's own sentence
/// for the same outcome ([AppStrings.exNothingInFrame]).
class _NothingWritten implements Exception {
  const _NothingWritten();

  @override
  String toString() => AppText.strings.exNothingInFrame;
}
