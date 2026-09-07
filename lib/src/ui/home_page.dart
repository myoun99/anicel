import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart' show GestureBinding, PointerEvent;
import 'package:flutter/services.dart' show SystemNavigator;

import 'dialogs/app_confirm_dialog.dart';
import '../controllers/default_project_helpers.dart';
import '../models/canvas_shape_kind.dart';
import '../models/project.dart';
import '../services/brush_preset_file_service.dart';
import '../services/brush_tip_library_service.dart';
import '../services/persistence/app_language_settings_store.dart';
import '../services/persistence/app_accent_settings_store.dart';
import '../services/persistence/app_ui_scale_store.dart';
import '../services/persistence/app_workspace_colors_store.dart';
import '../services/persistence/app_input_settings_store.dart';
import '../services/persistence/app_save_settings.dart';
import '../services/persistence/app_save_settings_store.dart';
import '../services/persistence/recent_projects.dart';
import '../services/persistence/recent_projects_store.dart';
import '../services/persistence/audio_sync_settings_store.dart';
import '../services/persistence/autosave_clock.dart';
import '../services/persistence/media_staging_store.dart';
import '../services/persistence/project_autosave_service.dart';
import '../services/color_palette_file_service.dart';
import '../services/project_repository.dart';
import 'brush/brush_tool_state.dart';
import 'brush/paint_tool_state_notifier.dart';
import '../models/app_workspace_colors.dart';
import 'debug/input_inspector.dart';
import '../services/input/pencil_interaction_service.dart';
import 'shortcuts/touch_shortcuts.dart';
import 'brush/canvas_selection_commands.dart';
import 'brush/canvas_view_commands.dart';
import 'editor_command_actions.dart';
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
import 'shortcuts/editor_shortcut_bindings.dart';
import 'shortcuts/shortcut_settings_store.dart';
import 'timeline/timeline_action_toolbar.dart'
    show showTimelineCommaCountDialog;
import 'text/app_strings.dart';
import 'canvas/flip_hud_controller.dart' show FlipHudController;
import 'layout/device_grid.dart';
import 'layout/device_grid_safe_area.dart';
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

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final EditorSessionManager _session;
  final WorkspacePanelsMenuController _panelsMenu =
      WorkspacePanelsMenuController();

  /// The active canvas tool, hoisted here so the tool shortcuts (B/E) and
  /// the workspace's tool/brush panels drive one notifier. Paint tools
  /// keep per-tool settings memory (R11-④: the brush and the eraser each
  /// remember their own preset/settings).
  final PaintToolStateNotifier _brushTool = PaintToolStateNotifier(
    BrushToolState.defaults,
  );

  /// Arms [group]'s current tile — the shortcut half of the rail button.
  ///
  /// Every tool shortcut goes through this rather than writing its own
  /// `copyWith(tool: …)`, so pressing `G` lands where the Fill BUTTON lands
  /// (유저 2026-08-15: 「모드 선택한게 초기화됨」 — a memory kept beside one
  /// entrance is a memory the other one disagrees with). For the groups
  /// with a single tile `railEntry` is the identity, so this costs them
  /// nothing and cannot be forgotten if one of them grows a second tile.
  void _armToolGroup(CanvasTool group) {
    _brushTool.value = _brushTool.value.copyWith(
      tool: _brushTool.railEntry(group),
    );
  }

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

  /// The selection channel (P9): Ctrl+D and the arrow nudges call in
  /// here; without a live selection the arrows keep flipping frames.
  final CanvasSelectionCommands _canvasSelectionCommands =
      CanvasSelectionCommands();

  /// The ↑/↓ layer-nav channel (UI-R20 #14): without a live selection the
  /// vertical arrows walk the timeline's DISPLAYED layer rows; the
  /// workspace binds the handler (it owns the row filter view state).
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

  /// Autosave (P3): dirty-session snapshots into the recovery folder. The
  /// service decides WHETHER; the two triggers below decide WHEN.
  ProjectAutosaveService? _autosave;

  /// 🚨F-1: THE autosave trigger. The clock's rule (count from the last
  /// snapshot, hold a fire until the pen lifts) lives in the clock rather
  /// than here, because a policy held as fields on a State is a policy
  /// nothing can test.
  late final AutosaveClock _autosaveClock = AutosaveClock(
    onSnapshot: () => unawaited(_autosave?.saveNow()),
  );

  /// Pointer ids currently down. A count rather than a bool because a
  /// second finger landing and lifting must not report the stroke over
  /// while the first is still drawing.
  final Set<int> _pointersDown = <int>{};

  /// PEN-12 #5: the DESKTOP exit gate — the window's close button lands
  /// in the same confirm dialog as the Android back button (the OS asks
  /// the framework before tearing the window down).
  AppLifecycleListener? _lifecycle;

  /// PEN-12 #8: the never-saved autosave prompt fires once per session —
  /// a declined prompt must not nag every tick.
  bool _unsavedAutosavePromptShown = false;

  // NO whole-page session setState: rebuilding the app bar and every dock
  // and panel on every session notify was the editing jank's biggest
  // multiplier. Each panel host subscribes to the session itself; the app
  // bar's undo/redo buttons carry their own ListenableBuilder below.
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
    // A NEW project seeds its pasteboard from the app-level default —
    // all that remains of the old app-state pasteboard (R3b promotion,
    // R28 #9 reversed): the color is project data now, and this is where
    // the "default for the next project" lands in one.
    final project =
        widget.initialProject ??
        createDefaultProject().copyWith(
          pasteboardArgb: AppWorkspaceColors.settings.value.pasteboardArgb,
        );
    _session = EditorSessionManager(
      initialProject: project,
      // Language + accent settings persist app-side (UI-R10 #7 /
      // UI-R22 #5); FLUTTER_TEST keeps widget tests off the developer's
      // saved files.
      languageSettingsStore: _unlessTesting(AppLanguageSettingsStore.new),
      accentSettingsStore: _unlessTesting(AppAccentSettingsStore.new),
      inputSettingsStore: _unlessTesting(AppInputSettingsStore.new),
      saveSettingsStore: _unlessTesting(AppSaveSettingsStore.new),
      audioSyncSettingsStore: _unlessTesting(AudioSyncSettingsStore.new),
      // R28 #9: the pasteboard color, on the accents' app-state idiom.
      workspaceColorsStore: _unlessTesting(AppWorkspaceColorsStore.new),
      // R11: the UI scale's WRITE half only — it is RESTORED in `main()`
      // before the first frame, because a late restore would lay the
      // window out at 100% and then jump.
      uiScaleStore: _unlessTesting(AppUiScaleStore.new),
    );
    // R16-①: undo/redo over a PENDING move session adopts it into history
    // first — an undo never pops out from under the unadopted lift.
    _session.historyManager.onBeforeUndoRedo =
        _canvasSelectionCommands.confirmPendingMove;
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
    _session.historyManager.addListener(_recordRecentColor);
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
    // SAVE-1: the autosave service follows the LIVE policy — on/off and
    // the interval rebuild it; the settings notifier is the one source.
    _syncAutosaveService();
    AppSave.settings.addListener(_syncAutosaveService);
    // Q-recovery-gc (유저 08-26: 「30일좋고」): snapshots whose project was
    // deleted or moved outside the app miss all three retirement moments
    // and would otherwise pile up in the app container for ever. Once per
    // launch, here, because this page is what makes snapshots exist at all.
    ProjectAutosaveService.sweepAbandonedRecovery();
    // The same moment and the same window for media a 품기'd import staged
    // and no save ever absorbed. ⛔At launch ONLY: a session open longer
    // than the window must not have its own staged bytes taken out from
    // under it, and at launch there is no session to take them from.
    MediaStagingStore().sweepAbandoned();
    // Q-scoped-folder-settings: reopen the folder settings' scopes for
    // this run (macOS forgets them at relaunch); stored only when a
    // folder actually moved, through the one settings write path.
    unawaited(
      AppSave.resolveSettingsDirectories().then((resolved) {
        if (resolved != null && mounted) {
          _session.setSaveSettings(resolved);
        }
      }),
    );
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
    // REC1-B: takes the TRANSPORT finishes (stop pressed mid-take) report
    // through this channel — the toggle button was not the caller, so its
    // snackbar path never runs.
    _session.voiceRecordingNotice.addListener(_showVoiceRecordingNotice);
    // The shared refusal channel stays wired; nothing installs a guard
    // any more.
    //
    // R26 #13 put one here: the transform tool refused to be SELECTED with
    // nothing to transform. 유저 확정 08-13 (피드백 ⑦) moved that refusal
    // onto the edit — "변형툴 선택은 허용으로 하고, 편집하려할때만
    // 거부하도록" — and it refuses quietly there, because a notice per tap
    // on an empty layer is a nag rather than an answer. The gate was also
    // answering for the cel that was active at the moment of the switch,
    // which went stale the instant the user moved to another layer
    // (피드백 ⑥); the live predicate cannot.
    // The type test this used to need is gone: [_brushTool] is declared as
    // the subclass now (the rail asks it for `railEntry`).
    _brushTool.onSwitchRefused = cursorNotices.show;
  }

  void _showVoiceRecordingNotice() {
    final message = _session.voiceRecordingNotice.value;
    if (message == null || !mounted) {
      return;
    }
    unawaited(
      showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: message,
      ),
    );
  }

  /// SAVE-1: follows the live policy. F-1 made the CLOCK the only trigger,
  /// so the policy is one number — [_autosaveClock] gets the interval (or
  /// stands down on null) and that is the whole sync.
  void _syncAutosaveService() {
    final settings = AppSave.settings.value;
    final minutes = settings.periodicSnapshotMinutes;
    _autosaveClock.configure(
      interval: minutes == null ? null : Duration(minutes: minutes),
    );
    // ONE service for the page's life, never rebuilt: nothing below is
    // settings-derived (five closures reading live session state), and
    // this listener fires on ANY settings change — a rebuild here dropped
    // the in-flight `_writing` guard with it, so a snapshot mid-write plus
    // a recordings-folder pick equalled two concurrent overlay writers
    // racing for the same rename.
    _autosave ??= ProjectAutosaveService(
      // Stands down while a manual save runs: a snapshot that lands after
      // the save's retirement leaves one behind for a project that was
      // saved and closed cleanly, and the next open then offers to recover
      // it — which is the exact signal this round exists to keep honest.
      isDirty: () =>
          _session.projectFile.hasUnsavedChanges &&
          !_session.projectFile.autosaveShouldStandDown,
      writeSnapshot: _session.projectDoor.writeAutosaveSnapshot,
      // Only called once needsProjectFile says a real file exists.
      autosavePath: () => _session.projectFile.autosaveSidecarPath!,
      // PEN-12 #8: a NEVER-SAVED project snapshots nowhere — instead of
      // piling files into hidden app-data dirs for a document with no
      // identity yet, the first dirty pass asks the user to pick a real
      // file (OpenToonz-style).
      needsProjectFile: () => _session.projectFile.path == null,
      onUnsavedProject: _promptUnsavedAutosave,
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

  @override
  void dispose() {
    PencilInteractionService.instance.onPencilTap = null;
    _session.historyManager.removeListener(_recordRecentColor);
    _session.voiceRecordingNotice.removeListener(_showVoiceRecordingNotice);
    AppSave.settings.removeListener(_syncAutosaveService);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_noteUserActivity);
    _autosaveClock.dispose();
    _lifecycle?.dispose();
    _session.dispose();
    _panelsMenu.dispose();
    _brushTool.dispose();
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
  bool _consumedByPlayback() {
    if (!_session.playbackRig.playback.isPlaying) {
      return false;
    }
    _session.playbackRig.playback.stop();
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
  /// ⛔The canvas NUDGE never reaches here and stays keyed to the arrow's own
  /// direction: pushing a selection right is +x whatever the sheet is
  /// reading. Only the timeline walk follows the sheet.
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
          _session.selectNextFrame();
        } else {
          _session.selectPreviousFrame();
        }
      } else if (forward) {
        _session.selectNextDrawing();
      } else {
        _session.selectPreviousDrawing();
      }
    } else {
      // Across it: the row stack.
      _timelineLayerNav.step(forward ? 1 : -1);
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
    // ⚠️The gate's keyboard handler has already stopped playback by the time
    // a bound key reaches here — Flutter dispatches the key message to the
    // focus tree even when a `HardwareKeyboard` handler claims it, so
    // returning true there stops the transport but does not eat the event.
    // `_consumedActuation` is what actually eats it.
    if (_consumedByPlayback()) {
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
        _session.selectPreviousFrame();
        _session.revealSelection();
      case EditorActionIds.frameNext:
        _session.selectNextFrame();
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
      case EditorActionIds.drawingPrevious:
        _nudgeOrWalk(-1, 0);
      case EditorActionIds.drawingNext:
        _nudgeOrWalk(1, 0);
      case EditorActionIds.playbackToggle:
        _togglePlayback();
      case EditorActionIds.voiceRecordToggle:
        unawaited(toggleVoiceRecordingWithFeedback(context, _session));
      case EditorActionIds.undo:
        _undoVertexOrDocument();
      case EditorActionIds.redo:
        _redoVertexOrDocument();
      case EditorActionIds.toolBrush:
        _armToolGroup(CanvasTool.brush);
      case EditorActionIds.toolEraser:
        _armToolGroup(CanvasTool.eraser);
      case EditorActionIds.toolEyedropper:
        _armToolGroup(CanvasTool.eyedropper);
      case EditorActionIds.toolFill:
        _armToolGroup(CanvasTool.fill);
      case EditorActionIds.onionSkinToggle:
        _session.toggleOnionSkin();
      // The film verbs. Each one guards itself the way the toolbar button
      // above it does — a key that fires on a row with nothing to do is a
      // no-op, not an error.
      case EditorActionIds.frameNewDrawing:
        createActiveInstance(_session);
      case EditorActionIds.frameBlankExposure:
        if (_session.canBlankExposureAtCurrentFrame) {
          _session.blankExposureAtCurrentFrame();
        }
      case EditorActionIds.frameToggleMark:
        if (_session.canToggleMarkAtCurrentFrame) {
          _session.toggleMarkAtCurrentFrame();
        }
      case EditorActionIds.timelinePushBlocks:
        if (_session.canPushBlocks()) {
          _session.pushBlocks(1);
        }
      case EditorActionIds.timelinePullBlocks:
        if (_session.canPullBlocks()) {
          _session.pullBlocks(1);
        }
      case EditorActionIds.canvasRotateCcw:
        _canvasViewCommands.rotateBy(-15);
      case EditorActionIds.canvasRotateCw:
        _canvasViewCommands.rotateBy(15);
      case EditorActionIds.canvasFlipHorizontal:
        _canvasViewCommands.toggleFlipHorizontal();
      // M and L still mean "rectangle select" and "lasso select" — the two
      // shortcuts survive the shape/verb split by setting both halves.
      case EditorActionIds.toolSelectRect:
        _brushTool.value = _brushTool.value.withShapeKind(
          CanvasShapeKind.rect,
          forTool: CanvasTool.select,
        );
      case EditorActionIds.toolLasso:
        _brushTool.value = _brushTool.value.withShapeKind(
          CanvasShapeKind.lasso,
          forTool: CanvasTool.select,
        );
      case EditorActionIds.toolMove:
        _armToolGroup(CanvasTool.move);
      case EditorActionIds.selectionDeselect:
        _canvasSelectionCommands.deselect();
      case EditorActionIds.selectionNudgeUp:
        _nudgeOrWalk(0, -1);
      case EditorActionIds.selectionNudgeDown:
        _nudgeOrWalk(0, 1);
      case EditorActionIds.selectionFreeTransform:
        // R26 #17: Ctrl+T is not its own transform mode — it SWITCHES to
        // the Move tool, so one code path (and one set of guards) owns
        // transforming.
        _armToolGroup(CanvasTool.move);
      case EditorActionIds.selectionTransformCommit:
        _confirmPolygonOrTransform();
      case EditorActionIds.selectionTransformCancel:
        _abandonPolygonOrCancelTransform();
      // The comma set row (UI-R17 #7): current block or whole selection.
      case EditorActionIds.timelineComma1:
        _session.setCommaForSelectionOrCurrent(1);
      case EditorActionIds.timelineComma2:
        _session.setCommaForSelectionOrCurrent(2);
      case EditorActionIds.timelineComma3:
        _session.setCommaForSelectionOrCurrent(3);
      case EditorActionIds.timelineComma4:
        _session.setCommaForSelectionOrCurrent(4);
      case EditorActionIds.timelineCommaN:
        if (_session.canSetCommaForSelectionOrCurrent) {
          unawaited(showTimelineCommaCountDialog(context, _session));
        }
    }
  }

  /// A live selection claims the PLAIN arrow keys as nudges (PS
  /// arbitration — the arbitration follows the KEYS, which walk
  /// drawings since PEN-7c). Nudges stand down while a stroke is
  /// live (R16-③: rewriting the lift under the pen froze both).
  /// Without a selection the arrows walk the displayed rows (TVP layer
  /// nav, UI-R20 #14) — along the frame axis for ←/→, across it for
  /// ↑/↓: the same dispatch-level arbitration for all four.
  void _nudgeOrWalk(int dx, int dy) {
    if (_canvasSelectionCommands.hasSelection) {
      if (!_session.brushInputActive.value) {
        _canvasSelectionCommands.nudge(dx.toDouble(), dy.toDouble());
      }
      return;
    }
    _walkTimeline(horizontal: dy == 0, forward: dx + dy > 0);
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

  /// While a polygon outline is open, undo/redo take its last vertex
  /// back and put it there again (유저 확정). They are NOT document
  /// history for that: a trace of twenty taps would otherwise bury the
  /// twenty real edits under it, and the undo cap is 200.
  ///
  /// The channel answers false once the trace is empty, so undo falls
  /// straight through to the document — undo never becomes a dead key
  /// just because a polygon was being drawn a moment ago.
  void _undoVertexOrDocument() {
    if (_canvasSelectionCommands.undoPolygonPoint()) {
      return;
    }
    if (_session.canUndo) {
      _session.undo();
    }
  }

  void _redoVertexOrDocument() {
    if (_canvasSelectionCommands.redoPolygonPoint()) {
      return;
    }
    if (_session.canRedo) {
      _session.redo();
    }
  }

  /// CONFIRM. An open polygon outline is the newest thing this key can
  /// be closing, and it takes precedence: it is what the user is
  /// looking at (유저 확정 — 폴리곤 확정은 확정 버튼으로).
  void _confirmPolygonOrTransform() {
    if (_canvasSelectionCommands.closePolygon()) {
      return;
    }
    _canvasSelectionCommands.commitTransform();
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
        body: DeviceGridSafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: _shortcuts,
            builder: (context, _) => Shortcuts.manager(
              manager: EditorShortcutManager(shortcuts: _shortcuts.shortcuts),
              child: Actions(
                actions: {
                  EditorActionIntent: CallbackAction<EditorActionIntent>(
                    onInvoke: (intent) {
                      _invokeAction(intent.actionId);
                      return null;
                    },
                  ),
                },
                child: FocusScope(
                  autofocus: true,
                  // 🚨T28-c — the whole editor behind ONE gate: while
                  // playing, the first actuation stops and is consumed.
                  // ⛔Inside `Shortcuts` deliberately, so a key is eaten
                  // rather than followed; see the widget's own note.
                  child: PlaybackActuationGate(
                    controller: _session.playbackRig.playback,
                    navigationRegionKey: _canvasNavigationRegionKey,
                    // Multi-finger touch shortcuts (R11-⑨) fire through the SAME
                    // action funnel as key bindings; the layer only observes raw
                    // touches, so drawing and pinch navigation are untouched.
                    child: TouchShortcutLayer(
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
                                  // drives the visibility checks, the session
                                  // the project name and the export gate.
                                  child: ListenableBuilder(
                                    listenable: Listenable.merge([
                                      _session,
                                      _panelsMenu,
                                    ]),
                                    builder: (context, _) => EditorTopStrip(
                                      session: _session,
                                      panelsMenu: _panelsMenu,
                                      brushTool: _brushTool,
                                      colorBackground: _colorWheelBackground,
                                      colorPalette: _colorPalette,
                                      onColorPaletteChanged: _setColorPalette,
                                      shortcuts: _shortcuts,
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
                                  colorBackground: _colorWheelBackground,
                                  colorPalette: _colorPalette,
                                  onColorPaletteChanged: _setColorPalette,
                                  canvasViewCommands: _canvasViewCommands,
                                  canvasNavigationRegionKey:
                                      _canvasNavigationRegionKey,
                                  canvasSelectionCommands:
                                      _canvasSelectionCommands,
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
    );
  }

  /// PEN-11: the back-button exit gate. Dirty sessions call out the
  /// unsaved work; Close is the only way out.
  Future<void> _confirmSystemExit() async {
    if (await _showExitDialog()) {
      await SystemNavigator.pop();
    }
  }

  /// PEN-12 #5: the desktop window-close request routes through the SAME
  /// gate — Cancel keeps the window open.
  Future<AppExitResponse> _handleExitRequested() async =>
      await _showExitDialog() ? AppExitResponse.exit : AppExitResponse.cancel;

  bool _exitDialogOpen = false;

  Future<bool> _showExitDialog() async {
    if (_exitDialogOpen) {
      return false;
    }
    // R26 #43: an UNEDITED project just closes — the prompt exists to
    // protect work, and there is none. "Edited" is the dirty flag the
    // history manager raises on every executed command.
    //
    // The question itself lives in [ensureUnsavedWorkSettled] now, shared
    // with the OPEN flow — which closes the current project just as surely
    // as this button and used to do it with no gate at all.
    _exitDialogOpen = true;
    try {
      return await ensureUnsavedWorkSettled(context, _session);
    } finally {
      _exitDialogOpen = false;
    }
  }

  /// PEN-12 #8: a dirty NEVER-SAVED project asked for its first real
  /// file — offer the Save As picker right here; declining stops the
  /// asking for the rest of the session (the user chose to live risky).
  Future<void> _promptUnsavedAutosave() async {
    // Every platform prompts. PICK-2: the Save As flow behind this is the
    // OS file dialog on Windows and Linux, and a folder grant plus a name
    // prompt on iPadOS, macOS and Android — the in-app browser it used to
    // reach on mobile is gone.
    if (_unsavedAutosavePromptShown || !mounted) {
      return;
    }
    _unsavedAutosavePromptShown = true;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        windowKey: const ValueKey<String>('unsaved-autosave-dialog'),
        title: AppText.strings.unsavedAutosaveTitle,
        titleIcon: Icons.save_outlined,
        message: AppText.strings.unsavedAutosaveBody,
        actions: confirmActions(
          context,
          declineLabel: AppText.strings.commonNotNow,
          declineKey: const ValueKey<String>('unsaved-autosave-later'),
          acceptLabel: AppText.strings.commonSaveAs,
          acceptKey: const ValueKey<String>('unsaved-autosave-save'),
        ),
      ),
    );
    if ((save ?? false) && mounted) {
      await promptSaveProjectAs(context, _session);
    }
  }
}

/// R26 #43's four answers live in [UnsavedWorkChoice] now, shared with the
// open flow's gate.
