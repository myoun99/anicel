import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart' show GestureBinding, PointerEvent;
import 'package:flutter/services.dart' show SystemNavigator;

import 'dialogs/app_confirm_dialog.dart';
import 'widgets/app_window.dart';
import '../controllers/default_project_helpers.dart';
import '../models/canvas_shape_kind.dart';
import '../models/project.dart';
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
import '../services/persistence/idle_snapshot_guard.dart';
import '../services/persistence/project_autosave_service.dart';
import '../services/color_palette_file_service.dart';
import '../services/project_repository.dart';
import 'brush/brush_tool_state.dart';
import 'brush/paint_tool_state_notifier.dart';
import 'theme/app_workspace_colors.dart';
import 'debug/input_inspector.dart';
import '../services/input/pencil_interaction_service.dart';
import 'shortcuts/touch_shortcuts.dart';
import 'brush/canvas_selection_commands.dart';
import 'brush/canvas_view_commands.dart';
import 'editor_command_actions.dart';
import 'editor_session_manager.dart';
import 'editor_workspace.dart';
import 'menu/editor_top_strip.dart';
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
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initialProject, this.onRepositoryCreated});

  final Project? initialProject;
  final void Function(ProjectRepository repository)? onRepositoryCreated;

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
    store: Platform.environment.containsKey('FLUTTER_TEST')
        ? null
        : ShortcutSettingsStore(),
  );

  /// Autosave (P3): dirty-session snapshots into the recovery folder. The
  /// service decides WHETHER; the two triggers below decide WHEN.
  ProjectAutosaveService? _autosave;

  /// The crash guard for the exits no lifecycle callback sees — a SIGSEGV
  /// or a dead battery mid-session. Its rule (armed by activity, disarmed
  /// by firing) lives in the guard rather than here, because a policy held
  /// as two fields on a State is a policy nothing can test.
  late final IdleSnapshotGuard _idleGuard = IdleSnapshotGuard(
    idleAfter: const Duration(seconds: 15),
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
      languageSettingsStore: Platform.environment.containsKey('FLUTTER_TEST')
          ? null
          : AppLanguageSettingsStore(),
      accentSettingsStore: Platform.environment.containsKey('FLUTTER_TEST')
          ? null
          : AppAccentSettingsStore(),
      inputSettingsStore: Platform.environment.containsKey('FLUTTER_TEST')
          ? null
          : AppInputSettingsStore(),
      saveSettingsStore: Platform.environment.containsKey('FLUTTER_TEST')
          ? null
          : AppSaveSettingsStore(),
      audioSyncSettingsStore: Platform.environment.containsKey('FLUTTER_TEST')
          ? null
          : AudioSyncSettingsStore(),
      // R28 #9: the pasteboard color, on the accents' app-state idiom.
      workspaceColorsStore: Platform.environment.containsKey('FLUTTER_TEST')
          ? null
          : AppWorkspaceColorsStore(),
      // R11: the UI scale's WRITE half only — it is RESTORED in `main()`
      // before the first frame, because a late restore would lay the
      // window out at 100% and then jump.
      uiScaleStore: Platform.environment.containsKey('FLUTTER_TEST')
          ? null
          : AppUiScaleStore(),
    );
    // R16-①: undo/redo over a PENDING move session adopts it into history
    // first — an undo never pops out from under the unadopted lift.
    _session.historyManager.onBeforeUndoRedo =
        _canvasSelectionCommands.confirmPendingMove;
    widget.onRepositoryCreated?.call(_session.repository);
    unawaited(_shortcuts.restore());
    _paletteService = Platform.environment.containsKey('FLUTTER_TEST')
        ? null
        : ColorPaletteFileService();
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
    GestureBinding.instance.pointerRouter.addGlobalRoute(_noteUserActivity);
    _lifecycle = AppLifecycleListener(
      onExitRequested: _handleExitRequested,
      // Every way the app can stop being in front of the user, because the
      // platforms disagree about which of these they send and in what
      // order — and on mobile the process may simply never wake up again.
      onInactive: _snapshotForRecovery,
      onHide: _snapshotForRecovery,
      onPause: _snapshotForRecovery,
      onDetach: _snapshotForRecovery,
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
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// SAVE-1: (re)builds the autosave service to the current policy —
  /// disabled tears it down. No timer any more: [_snapshotForRecovery]
  /// decides WHEN, off the app lifecycle.
  void _syncAutosaveService() {
    final settings = AppSave.settings.value;
    final minutes = settings.periodicSnapshotMinutes;
    _idleGuard.configure(
      pauseEnabled: settings.pauseSnapshotEnabled,
      ceiling: minutes == null ? null : Duration(minutes: minutes),
    );
    // Built unconditionally now. It used to be torn down when autosave was
    // switched off, which also silenced the lifecycle snapshot — so the
    // one trigger that costs nothing and is the only one a mobile OS
    // leaves room for went away with the two that are optional.
    _autosave = ProjectAutosaveService(
      // Stands down while a manual save runs: a snapshot that lands after
      // the save's retirement leaves one behind for a project that was
      // saved and closed cleanly, and the next open then offers to recover
      // it — which is the exact signal this round exists to keep honest.
      isDirty: () =>
          _session.hasUnsavedChanges && !_session.autosaveShouldStandDown,
      writeSnapshot: _session.writeAutosaveSnapshot,
      // Only called once needsProjectFile says a real file exists.
      autosavePath: () => _session.autosaveSidecarPath!,
      // PEN-12 #8: a NEVER-SAVED project snapshots nowhere — instead of
      // piling files into hidden app-data dirs for a document with no
      // identity yet, the first dirty pass asks the user to pick a real
      // file (OpenToonz-style).
      needsProjectFile: () => _session.projectFilePath == null,
      onUnsavedProject: _promptUnsavedAutosave,
    );
  }

  /// Snapshots the session because the app is about to stop being in front
  /// of the user.
  ///
  /// This is the whole trigger now. A clock never knew when work was at
  /// risk; leaving the app is the moment that does — and on mobile it is
  /// the only warning there is, because the OS may never come back to ask
  /// again. Fires on inactive/hidden/paused rather than one of them: which
  /// of those a platform sends, and in what order, is not something to
  /// depend on, and the service collapses the burst itself.
  void _snapshotForRecovery() {
    if (!AppSave.settings.value.lifecycleSnapshotEnabled) {
      return;
    }
    // This trigger just wrote one, so the guard no longer owes anything.
    _idleGuard.standDown();
    unawaited(_autosave?.saveNow());
  }

  /// Any pointer activity: the user is here, so push the guard back.
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
    _idleGuard.noteActivity(strokeInFlight: _pointersDown.isNotEmpty);
  }

  @override
  void dispose() {
    PencilInteractionService.instance.onPencilTap = null;
    _session.historyManager.removeListener(_recordRecentColor);
    _session.voiceRecordingNotice.removeListener(_showVoiceRecordingNotice);
    AppSave.settings.removeListener(_syncAutosaveService);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_noteUserActivity);
    _idleGuard.dispose();
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
    if (!_session.playback.isPlaying) {
      return false;
    }
    _session.playback.stop();
    return true;
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
        // PEN-7c: the one-frame step (Ctrl+arrows / comma) — always a
        // frame flip, never a nudge.
        //
        // R5: and the rails bring it back into view. These are the moves
        // that happen WITHOUT a pointer, so they are the ones that could
        // walk the selection off screen (user, 2026-08-09).
        _session.selectPreviousFrame();
        _session.revealSelection();
      case EditorActionIds.frameNext:
        _session.selectNextFrame();
        _session.revealSelection();
      case EditorActionIds.drawingPrevious:
        // A live selection claims the PLAIN arrow keys as nudges (PS
        // arbitration — the arbitration follows the KEYS, which walk
        // drawings since PEN-7c). Nudges stand down while a stroke is
        // live (R16-③: rewriting the lift under the pen froze both).
        if (_canvasSelectionCommands.hasSelection) {
          if (!_session.brushInputActive.value) {
            _canvasSelectionCommands.nudge(-1, 0);
          }
        } else {
          _session.selectPreviousDrawing();
          _session.revealSelection();
        }
      case EditorActionIds.drawingNext:
        if (_canvasSelectionCommands.hasSelection) {
          if (!_session.brushInputActive.value) {
            _canvasSelectionCommands.nudge(1, 0);
          }
        } else {
          _session.selectNextDrawing();
          _session.revealSelection();
        }
      case EditorActionIds.playbackToggle:
        // 🚨T28: play or stop, and nothing in between. The middle branch
        // used to resume a paused transport — a state that no longer
        // exists.
        final playback = _session.playback;
        if (playback.isPlaying) {
          playback.stop();
        } else {
          playback.play(
            scope: PlaybackScope.activeCut,
            startGlobalFrame: _session.currentFrameIndex,
          );
        }
      case EditorActionIds.voiceRecordToggle:
        toggleVoiceRecordingWithFeedback(context, _session);
      // While a polygon outline is open, undo/redo take its last vertex
      // back and put it there again (유저 확정). They are NOT document
      // history for that: a trace of twenty taps would otherwise bury the
      // twenty real edits under it, and the undo cap is 200.
      //
      // The channel answers false once the trace is empty, so undo falls
      // straight through to the document — undo never becomes a dead key
      // just because a polygon was being drawn a moment ago.
      case EditorActionIds.undo:
        if (_canvasSelectionCommands.undoPolygonPoint()) {
          break;
        }
        if (_session.canUndo) {
          _session.undo();
        }
      case EditorActionIds.redo:
        if (_canvasSelectionCommands.redoPolygonPoint()) {
          break;
        }
        if (_session.canRedo) {
          _session.redo();
        }
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
      // With a live selection ↑/↓ nudge; otherwise they walk the
      // displayed layer rows (TVP layer nav, UI-R20 #14) — the same
      // dispatch-level arbitration the horizontal arrows use.
      case EditorActionIds.selectionNudgeUp:
        if (_canvasSelectionCommands.hasSelection) {
          if (!_session.brushInputActive.value) {
            _canvasSelectionCommands.nudge(0, -1);
          }
        } else {
          _timelineLayerNav.step(-1);
          _session.revealSelection();
        }
      case EditorActionIds.selectionNudgeDown:
        if (_canvasSelectionCommands.hasSelection) {
          if (!_session.brushInputActive.value) {
            _canvasSelectionCommands.nudge(0, 1);
          }
        } else {
          _timelineLayerNav.step(1);
          _session.revealSelection();
        }
      case EditorActionIds.selectionFreeTransform:
        // R26 #17: Ctrl+T is not its own transform mode — it SWITCHES to
        // the Move tool, so one code path (and one set of guards) owns
        // transforming.
        _armToolGroup(CanvasTool.move);
      // CONFIRM. An open polygon outline is the newest thing this key can
      // be closing, and it takes precedence: it is what the user is
      // looking at (유저 확정 — 폴리곤 확정은 확정 버튼으로).
      case EditorActionIds.selectionTransformCommit:
        if (_canvasSelectionCommands.closePolygon()) {
          break;
        }
        _canvasSelectionCommands.commitTransform();
      case EditorActionIds.selectionTransformCancel:
        if (_canvasSelectionCommands.hasOpenPolygon) {
          _canvasSelectionCommands.abandonPolygon();
          break;
        }
        _canvasSelectionCommands.cancelTransform();
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
          showTimelineCommaCountDialog(context, _session);
        }
    }
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
          _confirmSystemExit();
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
                    controller: _session.playback,
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
    if (!_session.hasUnsavedChanges) {
      return true;
    }
    _exitDialogOpen = true;
    try {
      final choice = await showDialog<_ExitChoice>(
        context: context,
        builder: (context) => AppConfirmDialog(
          windowKey: const ValueKey<String>('system-exit-dialog'),
          title: AppText.strings.closeProjectTitle,
          titleIcon: Icons.logout_outlined,
          message: AppText.strings.closeProjectBody,
          actions: [
            AppWindowAction(
              label: AppText.strings.commonCancel,
              actionKey: const ValueKey<String>('system-exit-cancel'),
              onPressed: () => Navigator.of(context).pop(_ExitChoice.cancel),
            ),
            AppWindowAction(
              label: AppText.strings.commonSaveAs,
              actionKey: const ValueKey<String>('system-exit-save-as'),
              onPressed: () => Navigator.of(context).pop(_ExitChoice.saveAs),
            ),
            AppWindowAction(
              label: AppText.strings.commonSave,
              actionKey: const ValueKey<String>('system-exit-save'),
              onPressed: () => Navigator.of(context).pop(_ExitChoice.save),
            ),
            AppWindowAction(
              label: AppText.strings.commonClose,
              actionKey: const ValueKey<String>('system-exit-close'),
              emphasis: AppWindowActionEmphasis.primary,
              onPressed: () => Navigator.of(context).pop(_ExitChoice.close),
            ),
          ],
        ),
      );
      switch (choice) {
        case null || _ExitChoice.cancel:
          return false;
        case _ExitChoice.close:
          // Discarding the work discards its sidecar too. Left alive it
          // outlives the session that made it, and the next open offers
          // to restore precisely what the user just chose to throw away
          // — with recovery reading a surviving sidecar as "the app
          // crashed", keeping one here makes that signal lie.
          _session.discardAutosaveSidecar();
          return true;
        case _ExitChoice.save:
        case _ExitChoice.saveAs:
          if (!mounted) {
            return false;
          }
          // The existing File-menu flows do the work (one writer, one
          // picker); a save that fails or a cancelled picker leaves the
          // project dirty, so the close is called off.
          final path = _session.projectFilePath;
          if (choice == _ExitChoice.saveAs || path == null) {
            await promptSaveProjectAs(context, _session);
          } else {
            // Through the shared flow, so this save shows what it is doing
            // and — the part this path used to get wrong — REPORTS a
            // failure instead of throwing past the `return` below.
            await saveProjectShowingProgress(context, _session, path);
          }
          return !_session.hasUnsavedChanges;
      }
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
        actions: [
          AppWindowAction(
            label: AppText.strings.commonNotNow,
            actionKey: const ValueKey<String>('unsaved-autosave-later'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppWindowAction(
            label: AppText.strings.commonSaveAs,
            actionKey: const ValueKey<String>('unsaved-autosave-save'),
            emphasis: AppWindowActionEmphasis.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if ((save ?? false) && mounted) {
      await promptSaveProjectAs(context, _session);
    }
  }
}

/// R26 #43: the exit prompt's four answers.
enum _ExitChoice { cancel, save, saveAs, close }
