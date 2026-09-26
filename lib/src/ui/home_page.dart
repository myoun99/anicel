import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart' show GestureBinding, PointerEvent;
import 'package:flutter/services.dart' show SystemNavigator;

import 'dialogs/app_confirm_dialog.dart';
import '../controllers/default_project_helpers.dart';
import '../models/project.dart';
import '../models/working_panel.dart';
import '../native/qa_native_engine.dart';
import '../services/brush_preset_file_service.dart';
import '../services/brush_tip_library_service.dart';
import '../services/last_stroke_slot.dart';
import '../services/persistence/app_language_settings_store.dart';
import '../services/persistence/failed_save_copies.dart';
import '../services/persistence/save_failure.dart' show SaveFailure;
import '../services/persistence/app_accent_settings_store.dart';
import '../services/persistence/app_frame_grid_settings_store.dart';
import '../services/persistence/app_onion_skin_settings_store.dart';
import '../services/persistence/app_ui_scale_store.dart';
import '../services/persistence/app_workspace_colors_store.dart';
import '../services/persistence/app_input_settings_store.dart';
import '../services/persistence/app_save_settings.dart';
import '../services/persistence/app_save_settings_store.dart';
import '../services/persistence/app_memory_settings_store.dart';
import '../services/persistence/recent_projects.dart';
import '../services/persistence/recent_projects_store.dart';
import '../services/persistence/audio_sync_settings_store.dart';
import '../services/persistence/autosave_clock.dart';
import '../services/persistence/session_scratch.dart';
import '../services/persistence/project_autosave_service.dart';
import '../services/color_palette_file_service.dart';
import '../services/project_repository.dart';
import 'brush/brush_tool_state.dart';
import 'brush/confirm_verb.dart';
import 'brush/history_verbs.dart';
import 'brush/temporary_tool.dart';
import 'brush/paint_tool_state_notifier.dart';
import 'brush/tool_press.dart';
import 'brush/transform_tool_options.dart';
import 'debug/input_inspector.dart';
import '../services/input/pencil_interaction_service.dart';
import 'shortcuts/touch_shortcuts.dart';
import 'brush/canvas_selection_commands.dart';
import 'brush/canvas_view_commands.dart';
import 'editor_session_manager.dart';
import 'editor_workspace.dart';
import 'menu/editor_top_strip.dart';
import 'panels/workspace_layout_store.dart';
import 'panels/workspace_panels_menu.dart';
import 'playback/canvas_playback_controller.dart';
import 'playback/playback_actuation_gate.dart';
import 'playback/playback_transport_controls.dart'
    show toggleVoiceRecordingWithFeedback;
import 'shortcuts/editor_action_registry.dart';
import 'shortcuts/editor_key_holds.dart';
import 'shortcuts/editor_shortcut_bindings.dart';
import 'shortcuts/editor_shortcut_scope.dart';
import 'shortcuts/shortcut_settings_store.dart';
import 'timeline/layer_name_commands.dart' show deleteRowSelectionWithDialog;
import 'timeline/timeline_action_toolbar.dart'
    show showTimelineCommaCountDialog;
import 'timeline/toolbar_panel_context.dart';
import 'text/app_strings.dart';
import 'canvas/flip_hud_controller.dart' show FlipHudController;
import 'layout/device_grid.dart';
import 'layout/device_grid_safe_area.dart';
import 'session/editor_app_settings.dart';
import 'open_projects.dart';
import 'session/project_file_door.dart' show SaveAsked;
import 'timeline/timeline_layer_nav.dart' show TimelineLayerNavCommands;
import 'widgets/cursor_notice.dart';

/// The editor shell: a slim top menu strip (menu bar + quick actions —
/// the AppBar retired so the editor keeps the vertical space) plus the
/// dockable-panel workspace. Every panel's WIRING lives in its own host
/// file (timeline_tab_host.dart, storyboard_tab_host.dart,
/// editor_canvas_area.dart) so parallel work on different panels stays in
/// different files; the workspace only owns the dock layout and shared
/// panel view state.
/// An app-side store, or null under `flutter test`: FLUTTER_TEST keeps
/// widget tests off the developer's saved files (UI-R10 #7 / UI-R22 #5).
T? _unlessTesting<T>(T Function() make) =>
    Platform.environment.containsKey('FLUTTER_TEST') ? null : make();

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.initialProject,
    this.onRepositoryCreated,
    this.layoutStore,
    this.presetFileService,
    this.tipLibraryService,
    this.languageSettingsStore,
  });

  final Project? initialProject;
  final void Function(ProjectRepository repository)? onRepositoryCreated;

  /// Where the workspace saves its layout. Null lets the workspace decide —
  /// its own store in the app, none under FLUTTER_TEST — so a test that
  /// measures the save hands one in here (the only road to it: every
  /// workspace test pumps HomePage).
  final WorkspaceLayoutStore? layoutStore;

  /// Where the workspace's preset library loads from. Null lets the
  /// workspace decide — the app's own files, nothing under FLUTTER_TEST, so
  /// the library is empty in tests — and a test that measures applying a
  /// preset hands one in here, the same road as [layoutStore].
  final BrushPresetFileService? presetFileService;

  /// Where the workspace's tip library loads from — the presets reference
  /// tips by id and load after them, so a test that seeds presets seeds
  /// this too, on its own directory.
  final BrushTipLibraryService? tipLibraryService;

  /// Where the program language is restored from, beside the two services
  /// above. Null reads the saved file outside tests and nothing inside them.
  final AppLanguageSettingsStore? languageSettingsStore;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  // ── the projects open in this window (I-7) ──────────────────────────

  /// The projects open in this window, one tab each — see [OpenProjects].
  late final OpenProjects _projects;

  /// The project on screen. Everything this shell does to 「the project」 —
  /// a key, a save, an undo — it does to this one.
  EditorSessionManager get _session => _projects.active;

  /// What this shell hangs on each open project, by project — see
  /// [_ProjectHooks].
  final Map<EditorSessionManager, _ProjectHooks> _hooks = {};

  /// Sessions closed while their tab was still on screen, waiting for the
  /// frame that takes them off it ([_letGo]).
  final Set<EditorSessionManager> _goingAway = {};

  /// The project the per-screen objects were last pointed at
  /// ([_followProjectOnScreen]).
  EditorSessionManager? _onScreen;

  /// The run's failed copies — ONE list, handed to every open project
  /// ([EditorSessionManager.failedSaveCopies]).
  final FailedSaveCopies _failedSaveCopies = FailedSaveCopies();

  /// The tool a temporary hold sprang from — the app's, beside the tool
  /// ([ToolHoldMemory]).
  final ToolHoldMemory _toolHold = ToolHoldMemory();

  /// The app's settings — ONE for every open project, restored once here
  /// (I-7; see [EditorAppSettings]). FLUTTER_TEST keeps widget tests off the
  /// developer's saved files.
  late final EditorAppSettings _appSettings = EditorAppSettings(
    // Language + accent settings persist app-side (UI-R10 #7 / UI-R22 #5).
    languageSettingsStore:
        widget.languageSettingsStore ??
        _unlessTesting(AppLanguageSettingsStore.new),
    accentSettingsStore: _unlessTesting(AppAccentSettingsStore.new),
    inputSettingsStore: _unlessTesting(AppInputSettingsStore.new),
    saveSettingsStore: _unlessTesting(AppSaveSettingsStore.new),
    memorySettingsStore: _unlessTesting(AppMemorySettingsStore.new),
    audioSyncSettingsStore: _unlessTesting(AudioSyncSettingsStore.new),
    // R28 #9: the pasteboard color, on the accents' app-state idiom.
    workspaceColorsStore: _unlessTesting(AppWorkspaceColorsStore.new),
    // R11: the UI scale's WRITE half only — it is RESTORED in `main()`
    // before the first frame, because a late restore would lay the window
    // out at 100% and then jump.
    uiScaleStore: _unlessTesting(AppUiScaleStore.new),
    onionSkinSettingsStore: _unlessTesting(AppOnionSkinSettingsStore.new),
    frameGridSettingsStore: _unlessTesting(AppFrameGridSettingsStore.new),
  )..restore();
  final WorkspacePanelsMenuController _panelsMenu =
      WorkspacePanelsMenuController();

  /// The active canvas tool, hoisted here so the tool shortcuts and the
  /// workspace's tool/brush panels drive one notifier. Paint tools keep
  /// per-tool settings memory (R11-④: the brush and the eraser each
  /// remember their own preset/settings).
  final PaintToolStateNotifier _brushTool = PaintToolStateNotifier(
    BrushToolState.defaults,
  );

  /// The transform tool's options, hoisted beside [_brushTool] for the same
  /// reason: a tool shortcut presses a transform MODE (유저 2026-09-13:
  /// 「그냥 변형이 아니라 일반변형에 컨트롤+t로 연결하고 … 자유변형을
  /// 컨트롤+y로」), so the notifier lives where the shortcuts land.
  ///
  /// P3a (it holds which resampler a transform commit runs through): session
  /// state, deliberately NOT a [BrushToolState] field — everything there
  /// other than the tool itself forwards into `BrushShape`, which is what a
  /// saved brush preset serialises, so the bit would follow every preset
  /// around for no reason. Blend is the default: smoothing is what a
  /// transform is expected to do everywhere else in the industry, and the
  /// argmax is the deliberate choice for two-value work.
  final ValueNotifier<TransformToolOptions> _transformOptions = ValueNotifier(
    TransformToolOptions.defaults,
  );

  /// The colour wheel's spare (background) slot; the foreground IS the brush
  /// colour, so it rides [_brushTool] and only the spare needs a home.
  ///
  /// Shell-owned like the tool itself, and for the same reason: the colour
  /// button is on the TOP STRIP, which the shell mounts. It sat in the
  /// workspace while the swatch was the tool rail's bottom control, and
  /// nothing in the workspace reads a colour any more.
  final ValueNotifier<int> _colorWheelBackground = ValueNotifier(0xFFFFFFFF);

  /// The pinned palette + recent colours (P4), persisted app-side — which is
  /// itself an argument for it living here rather than beside a panel.
  final ValueNotifier<ColorPaletteState> _colorPalette = ValueNotifier(
    const ColorPaletteState(),
  );
  ColorPaletteFileService? _paletteService;

  void _setColorPalette(ColorPaletteState next) {
    // `withRecentColor` hands back the SAME object when the colour is already
    // the newest, which is the common case: draw two strokes without changing
    // colour and the second has nothing to record. The notifier already knew
    // to stay quiet; the file write did not, so a palette JSON was being
    // written on every stroke commit.
    if (identical(next, _colorPalette.value)) {
      return;
    }
    _colorPalette.value = next;
    unawaited(_paletteService?.save(next));
  }

  /// Recent colours record on COMMITTED work (P4): the colour actually drawn
  /// with, not every wheel drag sample. That is why it hangs off the history
  /// manager rather than off [_brushTool].
  void _recordRecentColor() {
    _setColorPalette(
      _colorPalette.value.withRecentColor(_brushTool.value.color),
    );
  }

  /// The canvas rotate/flip channel (P8): the R/Shift+R/H shortcuts call
  /// in here; the mounted canvas panel binds the viewport handlers.
  final CanvasViewCommands _canvasViewCommands = CanvasViewCommands();

  /// D13: the canvas panel's subtree key — the actuation gate's
  /// navigation hole reads its on-screen rect at event time (pan/zoom
  /// keep working during playback; everything else still stops).
  final GlobalKey _canvasNavigationRegionKey = GlobalKey(
    debugLabel: 'canvas-navigation-region',
  );

  /// The selection channel (P9): Ctrl+D, Enter and Escape call in here.
  /// The WINDOW's; what it shows is the project on screen's
  /// ([CanvasSelectionDocument]).
  final CanvasSelectionCommands _canvasSelectionCommands =
      CanvasSelectionCommands();

  /// The last drawing action, which 확정 lays down again. Shell-owned
  /// because it outlives a project (유저: 「프로그램을 닫을 때까지」).
  final LastStrokeSlot _lastStroke = LastStrokeSlot();

  /// 확정 — Enter here, and the rail's ↵ and 적용 in the workspace.
  late final ConfirmVerb _confirm = ConfirmVerb(
    selection: _canvasSelectionCommands,
    lastStroke: _lastStroke,
    tool: _brushTool,
    transformOptions: _transformOptions,
  );

  /// Undo and redo — the keys, the finger taps and a mapped button here,
  /// the rail's ↶ ↷ in the workspace. The census is [_pointersDown]. Made
  /// for the project on screen ([_followProjectOnScreen]).
  late HistoryVerbs _history;

  /// The ↑/↓ layer-nav channel (UI-R20 #14): the arrows that cross the
  /// frame axis walk the timeline's DISPLAYED layer rows, selection or no
  /// selection (F-86); the workspace binds the handler (it owns the row
  /// filter view state).
  final TimelineLayerNavCommands _timelineLayerNav = TimelineLayerNavCommands();

  /// The flip HUD's state (R10 hand-feel): shown while a one-finger flip
  /// is live. Shell-owned like the nav channel above — a live-drag verb
  /// parked in a panel's State is how a release silently fails to land.
  final FlipHudController _flipHud = FlipHudController();

  /// The customizable shortcut bindings (P1): registry defaults + the
  /// user's persisted overrides. Persistence is disabled under
  /// FLUTTER_TEST like the workspace layout.
  late final EditorShortcutBindings _shortcuts = EditorShortcutBindings(
    store: _unlessTesting(ShortcutSettingsStore.new),
  );

  /// The keys that are HELD (I-15) — 「이동」 on Space and the eyedropper's
  /// Alt — taken on the same road as every shortcut; see [EditorKeyHolds].
  /// The window's: it follows the stroke of the project on screen.
  late final EditorKeyHolds _keyHolds = EditorKeyHolds(
    bindings: _shortcuts,
    tool: _brushTool,
    temporaryTool: TemporaryTool(
      memory: _toolHold,
      current: () => _brushTool.value,
      change: (next) => _brushTool.value = next,
    ),
    strokeLive: _session.brushInputActive,
  );

  /// 🚨F-1: THE autosave trigger. The clock's rule (count from the last
  /// snapshot, hold a fire until the pen lifts) lives in the clock rather
  /// than here, because a policy held as fields on a State is a policy
  /// nothing can test.
  ///
  /// ONE clock for every open project (I-7): a tick saves each one that
  /// needs it — autosave is the app's setting, so a tab behind the one on
  /// screen follows it too.
  late final AutosaveClock _autosaveClock = AutosaveClock(
    onSnapshot: () {
      for (final session in _projects.sessions) {
        unawaited(_hooks[session]?.autosave.saveNow());
      }
    },
  );

  /// Pointer ids currently down. A count rather than a bool because a
  /// second finger landing and lifting must not report the stroke over
  /// while the first is still drawing.
  final Set<int> _pointersDown = <int>{};

  /// PEN-12 #5: the DESKTOP exit gate — the window's close button lands
  /// in the same confirm dialog as the Android back button (the OS asks
  /// the framework before tearing the window down).
  AppLifecycleListener? _lifecycle;

  // NO whole-page session setState: rebuilding the app bar and every dock
  // and panel on every session notify was the editing jank's biggest
  // multiplier. Each panel host subscribes to the session itself; the app
  // bar's undo/redo buttons carry their own ListenableBuilder below.
  //
  // ⚠️The one whole-page rebuild left is a project TAB changing (I-7): the
  // workspace is handed another session, and that is a new screen.
  @override
  void initState() {
    super.initState();
    // PICK-4: the recent-projects list, read once so the File menu has
    // something to show on the first open.
    //
    // Unguarded, unlike the stores below: `RecentProjectsStore` redirects
    // itself to a per-process temp file under FLUTTER_TEST, so a widget test
    // that opens a project gets its own list rather than the developer's.
    // Sync, because the menu reads this while BUILDING.
    AppRecent.projects.value = RecentProjectsStore().load();
    _projects = OpenProjects(
      first: widget.initialProject ?? newUntitledProject(),
      openSession: _openSession,
      letGo: _letGo,
    )..addListener(_followProjectOnScreen);
    _pointAtProjectOnScreen();
    widget.onRepositoryCreated?.call(_session.repository);
    unawaited(_shortcuts.restore());
    _paletteService = _unlessTesting(ColorPaletteFileService.new);
    unawaited(
      _paletteService?.loadOrDefaults().then((palette) {
        if (mounted) {
          _colorPalette.value = palette;
        }
      }),
    );
    // Apple Pencil double-tap (PEN-5): honor the user's SYSTEM Pencil
    // preference — the switch actions toggle brush↔eraser; the palette/
    // ink-attribute actions stay no-ops for now (no matching surface).
    PencilInteractionService.instance.onPencilTap = (action) {
      switch (action) {
        case PencilTapAction.switchEraser || PencilTapAction.switchPrevious:
          _invokeAction(
            _brushTool.value.tool == CanvasTool.eraser
                ? EditorActionIds.toolBrush
                : EditorActionIds.toolEraser,
          );
        case PencilTapAction.showColorPalette ||
            PencilTapAction.showInkAttributes ||
            PencilTapAction.ignore:
          break;
      }
    };
    // SAVE-1: the autosave clock follows the LIVE policy — on/off and the
    // interval; the settings notifier is the one source.
    _syncAutosaveClock();
    AppSave.settings.addListener(_syncAutosaveClock);
    // The one answer a launch owes the app container: the room of every run
    // that is no longer here goes, whole, now. 유저 확정 2026-09-10 — there
    // is no recovery to hold anything back for, because a room only ever
    // held the cels that had COOLED and handing back part of a drawing is
    // worse than handing back none.
    //
    // ⛔**AND THIS RUN'S OWN ROOM IS NOT BUILT HERE.** It used to be, so a
    // launch that staged nothing still left a locked, empty room behind;
    // `stagedFolder`/`volatileFolder` build it at the first real use
    // instead ([SessionScratch.ensureThisRunsFolder]).
    SessionScratch.deleteFoldersOfRunsThatEnded();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_noteUserActivity);
    _lifecycle = AppLifecycleListener(
      onExitRequested: _handleExitRequested,
      // Every way the app can stop being in front of the user, because the
      // platforms disagree about which of these they send and in what
      // order — and on mobile the process may simply never wake up again.
      // F-1: no lifecycle snapshot any more — see the note by
      // [_noteUserActivity]. The exit GATE stays: leaving with unsaved
      // work still asks.
    );
    // The memory warning and coming back to the app — heard HERE since
    // I-7: both are for every open project, and the workspace that used to
    // hear them is the window's, not a project's.
    WidgetsBinding.instance.addObserver(this);
    // 🪦No tool-switch guard, and no hook to announce one.
    //
    // R26 #13 put one here: the transform tool refused to be SELECTED with
    // nothing to transform. 유저 확정 08-13 (피드백 ⑦) moved that refusal
    // onto the edit — "변형툴 선택은 허용으로 하고, 편집하려할때만
    // 거부하도록" — and it refuses quietly there, because a notice per tap
    // on an empty layer is a nag rather than an answer. The gate was also
    // answering for the cel that was active at the moment of the switch,
    // which went stale the instant the user moved to another layer
    // (피드백 ⑥); the live predicate cannot. Nothing installed a guard after
    // that, so the notifier's seam and the notice hook this line wired went
    // too (2026-09-16).
  }

  /// Makes a session for [project] and hangs this shell's hooks on it — the
  /// one way a project comes to be open ([OpenProjects.open] and
  /// [OpenProjects.prepare] call it).
  EditorSessionManager _openSession(Project project) {
    late final EditorSessionManager session;
    session = EditorSessionManager(
      initialProject: project,
      appSettings: _appSettings,
      frameworkImageCache: PaintingBinding.instance.imageCache,
      failedSaveCopies: _failedSaveCopies,
      // ONE FILE, ONE WRITER — see [ProjectFile.isOpenElsewhere].
      fileIsOpenElsewhere: (path) {
        final bound = _projects.boundTo(path);
        return bound != null && !identical(bound, session);
      },
    );
    _hooks[session] = _ProjectHooks(
      session,
      autosave: ProjectAutosaveService(
        // Stands down while a manual save runs: a tick that started its own
        // write inside one would be a SECOND writer appending to the same
        // archive, which tears the tail both of them are extending — and
        // stands down for a session the user closed WITHOUT saving, so the
        // way down cannot put back what they just threw away.
        isDirty: () =>
            session.projectFile.hasUnsavedChanges &&
            !session.projectFile.autosaveShouldStandDown,
        // 🚨★★★**THE TICK SAVES THE PROJECT FILE — the same writer the Save
        // button uses, minus the window nobody is watching.**
        //
        // 유저 2026-09-07, on being asked what happens to 「저장 안 하고 닫기
        // = 버리기」: 「기존 결정대로 자동저장이 파일갱신. 그게 싫으면 자동
        // 저장 off하면된다고 말했는데 안바꿧나보네」. So the discard rule is
        // not abolished, it is the OFF position of a switch the user owns:
        // autosave on and the file follows the work every n minutes;
        // autosave off and the file changes on an explicit save alone.
        saveProject: (path) => session.projectDoor.saveProjectToFile(
          path,
          // The clock, not a person — so the pen is left alone.
          asked: SaveAsked.byTheClock,
        ),
        // Only called once needsProjectFile says a real file exists.
        projectPath: () => session.projectFile.path!,
        // PEN-12 #8: a NEVER-SAVED project snapshots nowhere — instead of
        // piling files into hidden app-data dirs for a document with no
        // identity yet, the first dirty pass asks the user to pick a real
        // file (OpenToonz-style).
        needsProjectFile: () => session.projectFile.path == null,
        onUnsavedProject: () => _promptUnsavedAutosave(session),
        onFailed: (error) => _tellWhatTheClockCouldNotSave(session, error),
      ),
    )..hang(this);
    return session;
  }

  /// Takes this shell's hooks off [session] and lets it go — once nothing
  /// on screen is showing it.
  ///
  /// ⚠️A tab closed while it was ON SCREEN is still the workspace's session
  /// until the rebuild this frame makes, and the workspace takes its own
  /// hooks off in that rebuild: disposing it now would have the workspace
  /// unhook from a disposed session. So it goes after the frame; a window
  /// that is closing (this State's dispose, after the workspace's own) lets
  /// every one go at once.
  void _letGo(EditorSessionManager session) {
    _hooks.remove(session)?.unhang(this);
    if (!mounted) {
      session.dispose();
      return;
    }
    _goingAway.add(session);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_goingAway.remove(session)) {
        session.dispose();
      }
    });
  }

  /// Points what the shell keeps for the project ON SCREEN at the one that
  /// is there now — and rebuilds, because the workspace and the strip show
  /// it.
  ///
  /// 🚨Before it points anything, the canvas LANDS what it was holding in
  /// the project going behind: a lift or an open box is that project's, and
  /// once the selection shows the next project's document a landing would
  /// write its region there. The same move an undo makes first (R16-①).
  void _followProjectOnScreen() {
    // Rebuilt either way: a tab added behind, or one closed, changes the
    // row even when the project on screen stays.
    final changed = _pointAtProjectOnScreen();
    setState(() {});
    if (changed) {
      // What waited for this project to be on screen says itself now.
      _hooks[_session]?.sayWhatWaited(this);
      unawaited(_warnIfProjectFileVanished(_session));
    }
  }

  /// [_followProjectOnScreen]'s pointing, without the rebuild — the first
  /// project is pointed at before there is anything to rebuild. Whether
  /// the project on screen changed.
  bool _pointAtProjectOnScreen() {
    final session = _session;
    if (identical(session, _onScreen)) {
      return false;
    }
    if (_onScreen != null) {
      _canvasSelectionCommands.confirmPendingMove();
    }
    _onScreen = session;
    _canvasSelectionCommands.document = session.canvasSelection;
    _history = HistoryVerbs(
      selection: _canvasSelectionCommands,
      session: session,
      contactIsDown: () => _pointersDown.isNotEmpty,
    );
    _keyHolds.strokeLive = session.brushInputActive;
    return true;
  }

  /// A notice or a question about [session], with [session] on screen.
  ///
  /// 🚨★★★A PROJECT SPEAKS WHEN IT IS ON SCREEN (I-7). A tab behind the one
  /// in front can fail a save on the clock, finish a take, lose its file —
  /// and a window about it over another project's canvas would leave the
  /// person guessing which one it means. So it waits for its tab, and is
  /// said the moment that tab is shown ([_followProjectOnScreen]).
  void _sayAbout(EditorSessionManager session, Future<void> Function() say) {
    if (!mounted) {
      return;
    }
    if (identical(session, _session)) {
      unawaited(say());
      return;
    }
    _hooks[session]?.waiting.add(say);
  }

  void _showVoiceRecordingNotice(EditorSessionManager session) {
    final message = session.voiceRecording.voiceRecordingNotice.value;
    if (message == null) {
      return;
    }
    _sayAbout(
      session,
      () => showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: message,
      ),
    );
  }

  /// SAVE-1: follows the live policy. F-1 made the CLOCK the only trigger,
  /// so the policy is one number — [_autosaveClock] gets the interval (or
  /// stands down on null) and that is the whole sync.
  ///
  /// ⛔Each project's service is made ONCE, with the project
  /// ([_openSession]), and never rebuilt here: nothing in it is
  /// settings-derived (five closures reading live session state), and this
  /// listener fires on ANY settings change — a rebuild here dropped the
  /// in-flight `_writing` guard with it, so a tick mid-write plus a
  /// recordings-folder pick equalled two concurrent writers racing for the
  /// same archive.
  void _syncAutosaveClock() {
    final settings = AppSave.settings.value;
    final minutes = settings.periodicSnapshotMinutes;
    _autosaveClock.configure(
      interval: minutes == null ? null : Duration(minutes: minutes),
    );
  }

  /// ⛔F-1 (유저 2026-08-26): the LIFECYCLE snapshot is gone — 「앱 떠날때,
  /// 손 멈출때 스냅샷 기능 삭제. 심플하게 명시적저장 / n분주기 자동저장만
  /// 남김」.
  ///
  /// It used to fire on inactive/hidden/paused/detach and was the cheapest
  /// trigger by a distance (nobody is drawing on the way out). ⚠️On mobile
  /// it was also the ONLY warning the OS gives before it stops the
  /// process, so what an OS kill now costs is the work since the last
  /// tick. That is the price of 「심플하게」 and it was taken knowingly;
  /// it is written here rather than in a commit message so the next reader
  /// finds it where the hole is.
  ///
  /// ⛔Do not quietly put it back. If it should return it returns as the
  /// user's call, not as a fix for a bug report that is really this.

  /// Any pointer activity — the clock only wants to know about the PEN.
  ///
  /// Watched through the global pointer route rather than a [Listener]
  /// wrapped around the app: a global route OBSERVES events without
  /// joining hit testing, so nothing about how input reaches the canvas
  /// changes. This repo cares about that path more than most.
  void _noteUserActivity(PointerEvent event) {
    if (event is PointerDownEvent) {
      _pointersDown.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointersDown.remove(event.pointer);
    }
    _autosaveClock.noteActivity(strokeInFlight: _pointersDown.isNotEmpty);
  }

  /// The OS says memory is tight: EVERY open project stands its caches
  /// down — hot cels halve and cool, playback re-runs its budget — the tabs
  /// behind the one on screen as much as it (I-7).
  @override
  void didHaveMemoryPressure() {
    for (final session in _projects.sessions) {
      session.respondToMemoryPressure();
    }
    // The drawing engine is the process's, not a project's: its parked
    // tile blocks and scratch buffers hear the warning here too.
    QaNativeEngine.respondToMemoryPressure();
  }

  /// 🚨★★★**COMING BACK IS WHEN THE FILE MAY HAVE GONE.**
  ///
  /// 유저 2026-08-31, having lost 94 cels: 「이 문제 발생시 **해결법이
  /// 없기때문**」. A save turns every clean cel into a ref into the project
  /// file and drops its cold blob, so deleting that file — in Explorer, in
  /// the Files app, in Drive — takes those pixels with it. The app only
  /// found out at the next save, by which time the recycle bin had usually
  /// been emptied and the person had done an hour of work on a project
  /// that could no longer be written whole.
  ///
  /// What CAN be recovered is the FILE, and only while it is still in a
  /// trash somewhere — which is exactly the window this notice exists to
  /// open. ⚠️It no longer says the bytes are unrecoverable, because since
  /// the session started holding the file open that depends on the
  /// platform: on POSIX an `unlink` leaves our handle readable and a save
  /// carries those cels into a new file, on Windows the file can only
  /// vanish while nothing is held and then it does lose them. The app
  /// reports the MEASURED answer after a save instead, by count.
  ///
  /// 🚨This notice is HALF the answer. It opens the restore window; the
  /// other half is [ensureUnsavedWorkSettled] refusing to let the session
  /// close in silence, because closing the app is when a POSIX session's
  /// last descriptor on those bytes goes.
  ///
  /// The observer was already here for memory pressure; resuming is the
  /// moment a person comes back from the file manager they just used. With
  /// a project per tab (I-7) it asks for the project on SCREEN — a tab
  /// behind it is asked when it is shown, which is when its person comes
  /// back to it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_warnIfProjectFileVanished(_session));
    }
  }

  /// Said ONCE per disappearance, not once per resume: a person who has
  /// read it and chosen to carry on must not be asked again every time
  /// they alt-tab.
  Future<void> _warnIfProjectFileVanished(EditorSessionManager session) async {
    final hooks = _hooks[session];
    if (hooks == null) {
      return;
    }
    if (!session.projectFile.hasVanished()) {
      // Back again — restored from a trash, or re-synced. The next
      // disappearance is worth saying out loud too.
      hooks.toldProjectFileVanished = false;
      return;
    }
    if (hooks.toldProjectFileVanished || !mounted) {
      return;
    }
    hooks.toldProjectFileVanished = true;
    await showAppNotice(
      context,
      windowKey: const ValueKey<String>('project-file-vanished-notice'),
      title: AppText.strings.commonNotice,
      message: AppText.strings.projectFileVanished,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The pan flag is app-wide: a shell that goes away must not keep it.
    _keyHolds.dispose();
    PencilInteractionService.instance.onPencilTap = null;
    AppSave.settings.removeListener(_syncAutosaveClock);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_noteUserActivity);
    _autosaveClock.dispose();
    _lifecycle?.dispose();
    // Every open project goes with the window — and any closed one still
    // waiting for its frame, which is not coming now.
    _projects
      ..removeListener(_followProjectOnScreen)
      ..dispose();
    for (final session in _goingAway) {
      session.dispose();
    }
    _goingAway.clear();
    _appSettings.dispose();
    _panelsMenu.dispose();
    _brushTool.dispose();
    _transformOptions.dispose();
    _lastStroke.dispose();
    _colorWheelBackground.dispose();
    _colorPalette.dispose();
    _shortcuts.dispose();
    _flipHud.dispose();
    super.dispose();
  }

  /// Dispatches one registry action — the single funnel every shortcut
  /// lands in (menu items call the same session APIs directly).
  /// 🚨T28-c's consuming half for BOUND actuations. Returns true when the
  /// actuation's whole job was to stop playback.
  ///
  /// ⛔It stops here rather than at each action, and there is exactly one
  /// exception it does NOT need: the playback toggle. Stopping is what that
  /// key was going to do anyway, so being consumed and being obeyed look the
  /// same from the outside.
  ///
  /// ⚠️It asks the SAME object the gate asks — 「누가 재생 중인가」 has one
  /// answer or the two halves of one law disagree: a bound key would walk a
  /// frame while the media viewer was still running its own timer.
  bool _consumedByPlayback() {
    final transports = _session.playbackRig.transports;
    if (!transports.value) {
      return false;
    }
    transports.stopAll();
    return true;
  }

  /// One arrow step through the timeline, resolved by the AXIS it came from.
  ///
  /// 🚨★★★THE SAME QUESTION THE FLIP ASKS. 유저 2026-08-27: 「플립이랑
  /// 화살표랑 **입구는 달라도 통하는건 하나**니까 둘 다 적용해야하는거지」.
  ///
  /// The frame axis is sideways on the timeline and downward on the X-sheet
  /// (F-28), and the flip gesture already follows the sheet the user is
  /// reading — `CanvasViewportGestureLayer._flipsFrames`. The keyboard did
  /// not: left/right always walked drawings and up/down always walked rows,
  /// so on an X-sheet the arrows moved across the grid the flip moved along.
  ///
  /// Both entrances land in the one switch below — the flip invokes these
  /// very action ids — so the disagreement was never two mechanisms. It was
  /// one mechanism asked the question in only one of its two doorways.
  ///
  /// ↩️「⛔The canvas NUDGE never reaches here and stays keyed to the arrow's
  /// own direction」 — there is no nudge any more (F-86, 유저 2026-09-12:
  /// 「기능부터 잔존코드 싹 삭제」), so every plain arrow comes here.
  /// [byFrame] is the SIZE of the step along the frame axis — one FRAME
  /// (Ctrl+arrows, F-28) or one DRAWING (the plain arrows). It changes
  /// nothing about the axis question, which is exactly why it is a
  /// parameter here rather than a second walker: 유저 2026-08-28 asked for
  /// Ctrl+arrows to follow the sheet the way the plain ones already do,
  /// and a copy of this `if` is what `the_frame_axis_is_asked_in_one_place`
  /// exists to forbid.
  ///
  /// ⛔Across the axis both sizes mean the same thing — one ROW. A frame
  /// has no meaning perpendicular to the frames.
  void _walkTimeline({
    required bool horizontal,
    required bool forward,
    bool byFrame = false,
  }) {
    if (_flipHud.framesRunAlong(horizontal: horizontal)) {
      // Along the frame axis: one DRAWING, which is the plain arrow's step.
      if (byFrame) {
        if (forward) {
          _session.frameVerbs.selectNextFrame();
        } else {
          _session.frameVerbs.selectPreviousFrame();
        }
      } else if (forward) {
        _session.frameVerbs.flipRow(forward: true);
      } else {
        _session.frameVerbs.flipRow(forward: false);
      }
    } else {
      // Across it: the row stack, in the direction the sheet lays it out
      // (F-28, 유저 2026-08-31: 「좌우가 방향이 반대임」).
      _timelineLayerNav.step(_flipHud.rowStepAcross(forward: forward));
    }
    _session.revealSelection();
  }

  void _invokeAction(String actionId) {
    // 🚨T28-c — 「재생 중 첫 작동은 정지이고, **정지일 뿐이다**」.
    //
    // This funnel is where every BOUND actuation arrives: key bindings and
    // multi-finger touch shortcuts both come through here, so one check
    // covers both and no action needs to know about playback. The pointer
    // half is [PlaybackActuationGate]'s `AbsorbPointer`; between them, the
    // first actuation of any kind stops and does nothing else.
    //
    // ⚠️A bound KEY pressed during playback never gets here any more: the
    // gate's own `Focus` node eats it on the way up (2026-09-08). This
    // guard covers every OTHER entrance to the funnel — a control the D13
    // hole let through, a menu item — where the law is the same and the
    // gate has not already answered.
    // 🪦It used to be the key half too, and could not be: the gate's
    // `HardwareKeyboard` handler stops playback BEFORE focus dispatch, so
    // the question below was already answered 「아니오」 by the time a key
    // arrived. The comment here named a `_consumedActuation` that never
    // existed.
    // 🚨R6q3: a view ZOOM passes while the canvas run plays — the funnel half
    // of the pass-through the gate's key half makes, through the SAME
    // predicate, so a zoom key and a bound touch gesture answer alike.
    final definition = _shortcuts.definitionFor(actionId);
    final zoomPasses = viewZoomPassesPlayback(
      zoomsView: definition?.zoomsView ?? false,
      canvasRun: _session.playbackRig.playback,
    );
    if (!zoomPasses && _consumedByPlayback()) {
      return;
    }
    // 🗣️I-19 (유저 2026-09-13): 「툴 자체에 설정할수도있고 툴 내부의 세부툴도
    // 설정가능하게」 — a tool action presses what its rail button or tile
    // presses, through the one [pressTool]; a colour edit action runs its
    // row's verb behind the gate that row opens behind.
    if (definition?.toolPress case final press?) {
      pressTool(press, tool: _brushTool, transform: _transformOptions);
      return;
    }
    if (definition?.pixelVerb case final verb?) {
      if (_session.cells.canRunPixelVerb) {
        _session.cells.runPixelVerb(verb);
      }
      return;
    }
    switch (actionId) {
      case EditorActionIds.framePrevious:
        // PEN-7c: the one-frame step — always a frame flip, never a nudge.
        //
        // ⛔The COMMA and PERIOD keep this arm and stay axis-blind, which
        // is the point of F-28's split: they say "previous / next frame",
        // not a direction, so an X-sheet must not turn them into row
        // moves. The Ctrl+ARROWS moved to the four cases below, where a
        // direction is what the key means.
        //
        // R5: and the rails bring it back into view. These are the moves
        // that happen WITHOUT a pointer, so they are the ones that could
        // walk the selection off screen (user, 2026-08-09).
        _session.frameVerbs.selectPreviousFrame();
        _session.revealSelection();
      case EditorActionIds.frameNext:
        _session.frameVerbs.selectNextFrame();
        _session.revealSelection();
      // F-28 (유저 2026-08-28, Q2=2): Ctrl+arrows read the SHEET, exactly
      // as the plain arrows already do — along the frame axis one frame,
      // across it one row. On an X-sheet that makes Ctrl+↑↓ the frame step
      // and Ctrl+←→ the row step; on the horizontal timeline it is the
      // arrangement it always was.
      case EditorActionIds.frameWalkLeft:
        _walkTimeline(horizontal: true, forward: false, byFrame: true);
      case EditorActionIds.frameWalkRight:
        _walkTimeline(horizontal: true, forward: true, byFrame: true);
      case EditorActionIds.frameWalkUp:
        _walkTimeline(horizontal: false, forward: false, byFrame: true);
      case EditorActionIds.frameWalkDown:
        _walkTimeline(horizontal: false, forward: true, byFrame: true);
      // The plain arrows WALK the sheet (TVP layer nav, UI-R20 #14; which
      // way the frames run is the sheet's answer inside `_walkTimeline`,
      // F-28). ↩️With a live canvas selection they used to NUDGE it instead
      // — PS arbitration, standing down while a stroke was live (R16-③).
      // 유저 2026-09-12: 「선택툴 선택한채로 화살표키누르면 그림 이동되는데 왜
      // 멋대로 넣은거지? 기능부터 잔존코드 싹 삭제」 · 「화살표 이동하는거
      // 변형툴일때도 작동하는거같은데 제발 멋대로 하지말고 그냥 싹 잔존 삭제」
      // (F-86).
      case EditorActionIds.drawingPrevious:
        _walkTimeline(horizontal: true, forward: false);
      case EditorActionIds.drawingNext:
        _walkTimeline(horizontal: true, forward: true);
      case EditorActionIds.playbackToggle:
        _togglePlayback();
      case EditorActionIds.voiceRecordToggle:
        unawaited(toggleVoiceRecordingWithFeedback(context, _session));
      case EditorActionIds.undo:
        _history.undo();
      case EditorActionIds.redo:
        _history.redo();
      case EditorActionIds.onionSkinToggle:
        _session.onionSkin.toggleOnionSkin();
      // The film verbs, pressed by key — each through the button it names on
      // the panel being worked in (I-19), behind the very gate that button
      // reads: a key that fires on a row with nothing to do is a no-op, not
      // an error.
      case EditorActionIds.frameNewDrawing:
        final panel = _workingPanel;
        if (panel.canCreateInstance) {
          panel.createInstance();
        }
      case EditorActionIds.frameBlankExposure:
        final panel = _workingPanel;
        if (panel.canBlankExposure) {
          panel.blankExposure();
        }
      case EditorActionIds.frameToggleMark:
        final panel = _workingPanel;
        if (panel.canToggleMark) {
          panel.toggleMark();
        }
      case EditorActionIds.timelinePushBlocks:
        final row = _workingPanel.shiftCurrentRow;
        if (_session.blockShift.canPushBlocks(currentRow: row)) {
          _session.blockShift.pushBlocks(1, currentRow: row);
        }
      case EditorActionIds.timelinePullBlocks:
        final row = _workingPanel.shiftCurrentRow;
        if (_session.blockShift.canPullBlocks(currentRow: row)) {
          _session.blockShift.pullBlocks(1, currentRow: row);
        }
      case EditorActionIds.canvasRotateCcw:
        _canvasViewCommands.rotateBy(-15);
      case EditorActionIds.canvasRotateCw:
        _canvasViewCommands.rotateBy(15);
      case EditorActionIds.canvasFlipHorizontal:
        _canvasViewCommands.toggleFlipHorizontal();
      case EditorActionIds.selectionDeselect:
        _canvasSelectionCommands.deselect();
      case EditorActionIds.layerUp:
        _walkTimeline(horizontal: false, forward: false);
      case EditorActionIds.layerDown:
        _walkTimeline(horizontal: false, forward: true);
      case EditorActionIds.confirm:
        _confirm.confirm();
      case EditorActionIds.selectionTransformCancel:
        _abandonPolygonOrCancelTransform();
      // The comma set row (UI-R17 #7): current block or whole selection —
      // this panel's 1/2/3/4/N buttons, pressed by key.
      case EditorActionIds.timelineComma1:
        _setCommaByKey(1);
      case EditorActionIds.timelineComma2:
        _setCommaByKey(2);
      case EditorActionIds.timelineComma3:
        _setCommaByKey(3);
      case EditorActionIds.timelineComma4:
        _setCommaByKey(4);
      case EditorActionIds.timelineCommaN:
        final panel = _workingPanel;
        if (panel.canSetComma) {
          unawaited(
            showTimelineCommaCountDialog(context, _session, panel: panel),
          );
        }
      // 🗣️I-19: the shared pill's own buttons, pressed by key — through the
      // very getters the buttons fire, so a key cannot act where its button
      // is dim.
      case EditorActionIds.editCut:
        _workingPanel.cutPress?.call();
      case EditorActionIds.editCopy:
        _workingPanel.copyPress?.call();
      case EditorActionIds.editPasteLinked:
        _workingPanel.pasteLinkedPress?.call();
      case EditorActionIds.editPasteIndependent:
        _workingPanel.pasteIndependentPress?.call();
      case EditorActionIds.editDelete:
        _workingPanel
            .deletePress(
              onDeleteRowSelection: () =>
                  unawaited(deleteRowSelectionWithDialog(context, _session)),
            )
            ?.call();
      case EditorActionIds.fileSave:
        unawaited(saveProject(context, _session));
      case EditorActionIds.fileSaveAs:
        unawaited(promptSaveProjectAs(context, _session));
      case EditorActionIds.layerVisibilitySolo:
        _session.visibilitySolo.toggleLayerVisibilitySolo();
      case EditorActionIds.canvasZoomIn:
        _canvasViewCommands.zoomStep(zoomIn: true);
      case EditorActionIds.canvasZoomOut:
        _canvasViewCommands.zoomStep(zoomIn: false);
    }
  }

  /// The panel a key speaks to: the one being worked in — the one last
  /// touched (유저 2026-09-24: 「마지막으로 만진 패널 … 입구같은거나 규칙/법
  /// 완벽하게 통일」). A key presses the button that panel shows.
  ///
  /// ↩️It was the cut timeline's whatever panel you were in (09-13, the
  /// context every bound film verb spoke to then — a session's pick, not a
  /// ruling: the order was 「여러 단축키 기존 버튼에 연결」), so the
  /// storyboard's own pill and its keys answered differently.
  ToolbarPanelContext get _workingPanel => switch (_session.workingPanel) {
    WorkingPanel.timeline => TimelineToolbarPanelContext(_session),
    WorkingPanel.storyboard => StoryboardToolbarPanelContext(_session),
  };

  /// A 1/2/3/4 key: that button, on the panel being worked in.
  void _setCommaByKey(int comma) {
    final panel = _workingPanel;
    if (panel.canSetComma) {
      panel.setComma(comma);
    }
  }

  /// 🚨T28: play or stop, and nothing in between. The middle branch
  /// used to resume a paused transport — a state that no longer
  /// exists. The STOP half lives in the gate every bound actuation
  /// passes first (T28-c, [_consumedByPlayback]): a running transport
  /// is already stopped by the time this key arrives, so here it only
  /// ever plays — the mutation campaign found the stop arm unreachable.
  void _togglePlayback() {
    _session.playbackRig.playback.play(
      scope: PlaybackScope.activeCut,
      startGlobalFrame: _session.currentFrameIndex,
    );
  }

  void _abandonPolygonOrCancelTransform() {
    if (_canvasSelectionCommands.hasOpenPolygon) {
      _canvasSelectionCommands.abandonPolygon();
      return;
    }
    _canvasSelectionCommands.cancelTransform();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // PEN-11: the Android back button must never silently kill the
    // editor — back asks first and only an explicit Close exits (the
    // task-manager "close all" can't be intercepted; the autosave
    // sidecar is the shield there). Desktop/iPad have no system back,
    // so this never fires for them.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_confirmSystemExit());
        }
      },
      child: Scaffold(
        // PEN-8 #1: keep the editor out of the notch and the side cutouts —
        // desktop insets are zero, so this is a tablet-only effect.
        //
        // The BOTTOM inset is deliberately not honoured (유저 확정, 프로크리
        // ·카리페그처럼): on iPad that inset is the home-indicator strip, and
        // it was costing a band of canvas on every tablet while desktop —
        // where the padding is zero — showed nothing. The indicator draws
        // over the bottom dock instead, the way it does in Procreate.
        //
        // The app-level shortcut layer (P1): the manager stands bare-letter
        // shortcuts down while a text field has focus; the bindings notifier
        // rebuilds the map live as the user re-records keys.
        body: EditorShortcutScope(
          bindings: _shortcuts,
          child: DeviceGridSafeArea(
            bottom: false,
            child: ListenableBuilder(
              listenable: _shortcuts,
              builder: (context, _) => Shortcuts.manager(
                manager: EditorShortcutManager(
                  shortcuts: _shortcuts.shortcuts,
                  onHoldKey: _keyHolds.engage,
                ),
                child: Actions(
                  actions: {
                    EditorActionIntent: CallbackAction<EditorActionIntent>(
                      onInvoke: (intent) {
                        _invokeAction(intent.actionId);
                        return null;
                      },
                    ),
                  },
                  child: PlaybackActuationGate(
                    // 🚨T28-c — the whole editor behind ONE gate: while
                    // playing, the first actuation stops and is consumed.
                    //
                    // ⛔Inside `Shortcuts` AND above the editor's `FocusScope`,
                    // both deliberately. Inside `Shortcuts`, so a key that
                    // stopped playback is eaten rather than followed. ABOVE the
                    // scope, because key dispatch walks UPWARD from the primary
                    // focus — with no field focused the scope IS that focus, so
                    // a gate mounted under it is never consulted at all. It sat
                    // there until 2026-09-08 and the consuming half was dead:
                    // 실측 — pressing `.` during playback stopped the transport
                    // AND stepped a frame.
                    transports: _session.playbackRig.transports,
                    navigationRegion: (
                      key: _canvasNavigationRegionKey,
                      transport: _session.playbackRig.playback,
                    ),
                    child: FocusScope(
                      autofocus: true,
                      // Multi-finger touch shortcuts (R11-⑨) fire through the SAME
                      // action funnel as key bindings; the layer only observes raw
                      // touches, so drawing and pinch navigation are untouched.
                      child: TouchShortcutLayer(
                        // T28-c at the gesture's first contact — see the
                        // field; the funnel's own check comes too late here.
                        playing: _session.playbackRig.transports,
                        onGesture: (gesture) {
                          final actionId = _shortcuts.actionIdForTouchGesture(
                            gesture,
                          );
                          if (actionId != null) {
                            _invokeAction(actionId);
                          }
                        },
                        // The pen program's diagnosis overlay (Settings ▸ Input
                        // Inspector) — inert until toggled, observes raw events
                        // only (never a gesture-arena participant).
                        // R26 #35/#13: the shared cursor-notice surface wraps
                        // the whole editor, so any refusal anywhere prints
                        // next to the pointer.
                        child: CursorNoticeOverlay(
                          child: InputInspectorHost(
                            child: Column(
                              children: [
                                // The top strip: two popover buttons and the
                                // work's name. The seven-menu bar it replaced
                                // is gone — every command it carried now lives
                                // on the surface that shows its result, and
                                // undo/redo/export went with them. 48px so the
                                // buttons sit on the same grid as the rail's.
                                //
                                // The SAME fill as the tool rail, because they are
                                // the same thing: inert chrome. It used to sit two
                                // steps up the container ladder, which is why the
                                // strip and the rail never looked like one app.
                                Material(
                                  color: colorScheme.surface,
                                  child: Container(
                                    // The strip is the SECOND link in the
                                    // window-origin chain: everything below it,
                                    // including the canvas, starts at this
                                    // height. 48 is on the grid at every Windows
                                    // scaling step (48 = 16x3) and OFF it the
                                    // moment a UI scale makes the ratio a
                                    // product — 48 x 1.35 is 64.8.
                                    height: DeviceGrid.of(context).position(48),
                                    // The seam the tool rail already had and this
                                    // strip did not (유저, R4 #1: 상단띠랑 캔버스
                                    // 사이엔 없거든? 상단띠에도 아래에 추가).
                                    // Same `outlineVariant` and the same idiom as
                                    // `EditorPanelDock` — the border is drawn
                                    // INSIDE the strip's own height, so the
                                    // canvas below does not move to make room
                                    // for it. ⚠️Its own HEIGHT, not 48: the
                                    // line above quantizes it, so at an
                                    // effective 1.35 the strip is 47.41. The
                                    // seam the user sees — this border's bottom
                                    // edge against the canvas — is what lands
                                    // on the grid; the border's own 1.0-logical
                                    // width is 1.35 device px and can never be
                                    // crisp, which is a hairline problem and
                                    // not this link's.
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: colorScheme.outlineVariant,
                                        ),
                                      ),
                                    ),
                                    // Re-reads per notify: the panels bridge
                                    // drives the visibility checks, the open
                                    // projects their tabs — every one of them,
                                    // since a tab behind this one is renamed
                                    // by its own save — and the session on
                                    // screen the export gate.
                                    child: ListenableBuilder(
                                      listenable: Listenable.merge([
                                        _projects,
                                        ..._projects.sessions,
                                        _panelsMenu,
                                      ]),
                                      builder: (context, _) => EditorTopStrip(
                                        projects: _projects,
                                        onCloseProject: (session) =>
                                            unawaited(_closeProject(session)),
                                        panelsMenu: _panelsMenu,
                                        brushTool: _brushTool,
                                        colorBackground: _colorWheelBackground,
                                        colorPalette: _colorPalette,
                                        onColorPaletteChanged: _setColorPalette,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: EditorWorkspace(
                                    session: _session,
                                    layoutStore: widget.layoutStore,
                                    presetFileService: widget.presetFileService,
                                    tipLibraryService: widget.tipLibraryService,
                                    panelsMenu: _panelsMenu,
                                    brushTool: _brushTool,
                                    transformOptions: _transformOptions,
                                    colorBackground: _colorWheelBackground,
                                    colorPalette: _colorPalette,
                                    onColorPaletteChanged: _setColorPalette,
                                    canvasViewCommands: _canvasViewCommands,
                                    canvasNavigationRegionKey:
                                        _canvasNavigationRegionKey,
                                    canvasSelectionCommands:
                                        _canvasSelectionCommands,
                                    lastStroke: _lastStroke,
                                    toolHold: _toolHold,
                                    confirm: _confirm,
                                    history: _history,
                                    layerNav: _timelineLayerNav,
                                    flipHud: _flipHud,
                                    onInvokeAction: _invokeAction,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  /// The gate, and then the ONE thing that has to happen between 「yes」 and
  /// the process going away.
  ///
  /// 🚨★★★**BOTH DOORS, ONE ANSWER.** The back button and the window's
  /// close button are two entrances to the same departure, and the room
  /// this run keeps in the app container has to go through whichever one
  /// is used. Hanging it off only the desktop path is how a folder per
  /// launch accumulates on the platform nobody was watching.
  ///
  /// ⛔It is NOT hung inside [_showExitDialog]: that one is「ask」, and a
  /// question that also deletes things is a question no caller can reuse.
  Future<bool> _mayLeaveForGood() async {
    if (!await _showExitDialog()) {
      return false;
    }
    SessionScratch.deleteThisRunsFolder();
    return true;
  }

  /// PEN-11: the back-button exit gate. Dirty sessions call out the
  /// unsaved work; Close is the only way out.
  Future<void> _confirmSystemExit() async {
    if (await _mayLeaveForGood()) {
      await SystemNavigator.pop();
    }
  }

  /// PEN-12 #5: the desktop window-close request routes through the SAME
  /// gate — Cancel keeps the window open.
  Future<AppExitResponse> _handleExitRequested() async =>
      await _mayLeaveForGood() ? AppExitResponse.exit : AppExitResponse.cancel;

  bool _exitDialogOpen = false;

  /// Asks about every open project that has something to lose, each with
  /// its own tab on screen — the window closing closes all of them (I-7).
  /// Cancel on any one of them keeps the window open.
  Future<bool> _showExitDialog() async {
    if (_exitDialogOpen) {
      return false;
    }
    // R26 #43: a project with nothing to lose just closes — the prompt
    // exists to protect work. ⚠️"Nothing to lose" is no longer only the
    // dirty flag: a saved cel lives as a ref into the `.anicel`, so a
    // clean session whose file has gone is asked too. The predicate is
    // [ensureUnsavedWorkSettled]'s first statement, not this one.
    //
    // The question itself lives in [ensureUnsavedWorkSettled] now, shared
    // with a tab's close button — which closes a project just as surely as
    // this one.
    _exitDialogOpen = true;
    try {
      for (final session in _projects.sessions) {
        if (!mounted) {
          return false;
        }
        if (!await _settleWithItOnScreen(session)) {
          return false;
        }
      }
      return true;
    } finally {
      _exitDialogOpen = false;
    }
  }

  /// [ensureUnsavedWorkSettled] for [session], asked with [session] on
  /// screen when there is anything to ask (A PROJECT SPEAKS WHEN IT IS ON
  /// SCREEN — see [_sayAbout]). One with nothing to lose is not brought
  /// forward just to be let go.
  Future<bool> _settleWithItOnScreen(EditorSessionManager session) async {
    if (!session.projectFile.hasUnsavedChanges &&
        !session.projectFile.hasVanished()) {
      return true;
    }
    if (!identical(session, _session)) {
      _projects.activate(session);
      // The question waits for the frame that shows its project.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return false;
      }
    }
    return ensureUnsavedWorkSettled(context, session);
  }

  /// A tab's close button: the same question the window asks, for that
  /// project, and then the tab goes — leaving an untitled project when it
  /// was the last ([OpenProjects.close]).
  Future<void> _closeProject(EditorSessionManager session) async {
    if (_exitDialogOpen) {
      return;
    }
    _exitDialogOpen = true;
    try {
      if (!await _settleWithItOnScreen(session) || !mounted) {
        return;
      }
      _projects.close(session, fresh: newUntitledProject);
    } finally {
      _exitDialogOpen = false;
    }
  }

  /// The clock's save failed: said the way a person's is, at that moment —
  /// why, and the failed copy the work went to (유저 2026-09-23,
  /// whole-write-temp-beside-the-file). The service tells once per run of
  /// failures, so a file that stays locked is not announced every tick.
  /// A project behind the one on screen says it when it is shown.
  void _tellWhatTheClockCouldNotSave(
    EditorSessionManager session,
    Object error,
  ) {
    _sayAbout(session, () async {
      if (error is SaveFailure) {
        await showSaveFailure(context, session, error);
      } else {
        showFileError(context, error);
      }
    });
  }

  /// PEN-12 #8: a dirty NEVER-SAVED project asked for its first real
  /// file — offer the Save As picker right here; declining stops the
  /// asking for the rest of the session (the user chose to live risky).
  ///
  /// Asked only with that project ON SCREEN (I-7): the picker saves the
  /// project it is asked about, and a tab behind the one in front is asked
  /// at a tick after it is shown — its question is not spent meanwhile.
  Future<void> _promptUnsavedAutosave(EditorSessionManager session) async {
    // Every platform prompts. PICK-2: the Save As flow behind this is the
    // OS file dialog on Windows and Linux, and a folder grant plus a name
    // prompt on iPadOS, macOS and Android — the in-app browser it used to
    // reach on mobile is gone.
    final hooks = _hooks[session];
    if (hooks == null ||
        hooks.unsavedAutosavePromptShown ||
        !mounted ||
        !identical(session, _session)) {
      return;
    }
    hooks.unsavedAutosavePromptShown = true;
    final save = await askConfirm(
      context,
      ConfirmQuestion(
        keys: (
          window: const ValueKey<String>('unsaved-autosave-dialog'),
          decline: const ValueKey<String>('unsaved-autosave-later'),
          accept: const ValueKey<String>('unsaved-autosave-save'),
        ),
        title: AppText.strings.unsavedAutosaveTitle,
        titleIcon: Icons.save_outlined,
        message: AppText.strings.unsavedAutosaveBody,
      ),
      decline: ConfirmChoice(AppText.strings.commonNotNow),
      accept: ConfirmChoice(AppText.strings.commonSaveAs),
    );
    if ((save ?? false) && mounted) {
      await promptSaveProjectAs(context, session);
    }
  }
}

/// What the shell hangs on ONE open project, held so it can be taken off
/// again when the project closes (I-7) — and what the shell keeps for it:
/// its autosave, the questions it has already asked, and what it has to
/// say once it is on screen.
final class _ProjectHooks {
  _ProjectHooks(this.session, {required this.autosave});

  final EditorSessionManager session;

  /// Autosave (P3): dirty-session snapshots into the project's file. The
  /// service decides WHETHER; the shell's one clock decides WHEN.
  final ProjectAutosaveService autosave;

  /// PEN-12 #8: the never-saved autosave prompt fires once per project — a
  /// declined prompt must not nag every tick.
  bool unsavedAutosavePromptShown = false;

  /// Whether the vanished-file notice was said for the current
  /// disappearance — see `_warnIfProjectFileVanished`.
  bool toldProjectFileVanished = false;

  /// What came up while the project was behind another — said when it is
  /// on screen, in the order it came.
  final List<Future<void> Function()> waiting = [];

  VoidCallback? _voiceNotice;

  void hang(_HomePageState shell) {
    final history = session.historyManager;
    // R16-①: undo/redo over a PENDING move session adopts it into history
    // first — an undo never pops out from under the unadopted lift.
    history.onBeforeUndoRedo =
        shell._canvasSelectionCommands.confirmPendingMove;
    // ...and a step that WAITED for its pictures asks first whether there
    // is anything to adopt: work begun after the press is the user's.
    history.pendingBeforeUndoRedo = () =>
        shell._canvasSelectionCommands.movePending ||
        shell._canvasSelectionCommands.transformActive;
    history.addListener(shell._recordRecentColor);
    // REC1-B: takes the TRANSPORT finishes (stop pressed mid-take) report
    // through this channel — the toggle button was not the caller, so its
    // snackbar path never runs.
    _voiceNotice = () => shell._showVoiceRecordingNotice(session);
    session.voiceRecording.voiceRecordingNotice.addListener(_voiceNotice!);
  }

  void unhang(_HomePageState shell) {
    session.historyManager.removeListener(shell._recordRecentColor);
    if (_voiceNotice case final notice?) {
      session.voiceRecording.voiceRecordingNotice.removeListener(notice);
    }
    waiting.clear();
  }

  /// Says, in order, what waited for this project to be on screen.
  void sayWhatWaited(_HomePageState shell) {
    final said = [...waiting];
    waiting.clear();
    unawaited(() async {
      for (final say in said) {
        if (!shell.mounted) {
          return;
        }
        await say();
      }
    }());
  }
}

/// R26 #43's four answers live in [UnsavedWorkChoice] now, shared with the
// window's gate and a tab's close button.
