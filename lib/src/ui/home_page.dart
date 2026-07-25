import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart' show SystemNavigator;

import 'dialogs/app_confirm_dialog.dart';
import 'widgets/app_window.dart';
import '../controllers/default_project_helpers.dart';
import '../models/project.dart';
import '../services/persistence/app_language_settings_store.dart';
import '../services/persistence/app_accent_settings_store.dart';
import '../services/persistence/app_workspace_colors_store.dart';
import '../services/persistence/app_input_settings_store.dart';
import '../services/persistence/app_save_settings.dart';
import '../services/persistence/app_save_settings_store.dart';
import '../services/persistence/audio_sync_settings_store.dart';
import '../services/persistence/project_autosave_service.dart';
import '../services/project_repository.dart';
import 'brush/brush_tool_state.dart';
import 'brush/paint_tool_state_notifier.dart';
import 'debug/input_inspector.dart';
import '../services/input/pencil_interaction_service.dart';
import 'shortcuts/touch_shortcuts.dart';
import 'brush/canvas_selection_commands.dart';
import 'brush/canvas_view_commands.dart';
import 'editor_session_manager.dart';
import 'editor_workspace.dart';
import '../services/persistence/app_export_settings_store.dart';
import 'export/export_dialog.dart';
import 'menu/editor_menu_bar.dart';
import 'panels/workspace_panels_menu.dart';
import 'playback/canvas_playback_controller.dart';
import 'playback/playback_transport_controls.dart'
    show toggleVoiceRecordingWithFeedback;
import 'shortcuts/editor_action_registry.dart';
import 'shortcuts/editor_shortcut_bindings.dart';
import 'shortcuts/shortcut_settings_store.dart';
import 'timeline/timeline_action_toolbar.dart'
    show showTimelineCommaCountDialog;
import 'text/app_strings.dart';
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
  final ValueNotifier<BrushToolState> _brushTool = PaintToolStateNotifier(
    BrushToolState.defaults,
  );

  /// The canvas rotate/flip channel (P8): the R/Shift+R/H shortcuts call
  /// in here; the mounted canvas panel binds the viewport handlers.
  final CanvasViewCommands _canvasViewCommands = CanvasViewCommands();

  /// The selection channel (P9): Ctrl+D and the arrow nudges call in
  /// here; without a live selection the arrows keep flipping frames.
  final CanvasSelectionCommands _canvasSelectionCommands =
      CanvasSelectionCommands();

  /// The ↑/↓ layer-nav channel (UI-R20 #14): without a live selection the
  /// vertical arrows walk the timeline's DISPLAYED layer rows; the
  /// workspace binds the handler (it owns the row filter view state).
  final TimelineLayerNavCommands _timelineLayerNav = TimelineLayerNavCommands();

  /// The customizable shortcut bindings (P1): registry defaults + the
  /// user's persisted overrides. Persistence is disabled under
  /// FLUTTER_TEST like the workspace layout.
  late final EditorShortcutBindings _shortcuts = EditorShortcutBindings(
    store: Platform.environment.containsKey('FLUTTER_TEST')
        ? null
        : ShortcutSettingsStore(),
  );

  /// Autosave (P3): periodic dirty-session snapshots into the sidecar.
  /// Never runs under FLUTTER_TEST (tests drive the service directly).
  ProjectAutosaveService? _autosave;

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
    final project = widget.initialProject ?? createDefaultProject();
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
    );
    // R16-①: undo/redo over a PENDING move session adopts it into history
    // first — an undo never pops out from under the unadopted lift.
    _session.historyManager.onBeforeUndoRedo =
        _canvasSelectionCommands.confirmPendingMove;
    widget.onRepositoryCreated?.call(_session.repository);
    unawaited(_shortcuts.restore());
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
    _lifecycle = AppLifecycleListener(onExitRequested: _handleExitRequested);
    // REC1-B: takes the TRANSPORT finishes (stop pressed mid-take) report
    // through this channel — the toggle button was not the caller, so its
    // snackbar path never runs.
    _session.voiceRecordingNotice.addListener(_showVoiceRecordingNotice);
    // R26 #13: the transform tool refuses to engage with nothing to
    // transform — announced through the shared cursor notice, never a
    // dialog, and the tool simply stays where it was. Installed on the
    // notifier so EVERY entrance (library panel, shortcut, Ctrl+T, pen
    // button) is covered by one guard.
    final toolNotifier = _brushTool;
    if (toolNotifier is PaintToolStateNotifier) {
      toolNotifier
        ..switchGuard = _refusalForTool
        ..onSwitchRefused = cursorNotices.show;
    }
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

  /// The refusal message for switching to [tool], or null to allow it.
  String? _refusalForTool(CanvasTool tool) {
    if (tool != CanvasTool.move) {
      return null;
    }
    final selection = _session.activeBrushEditorSelection;
    final hasPicture =
        selection != null &&
        _session.brushFrameStore.celHasRenderableContent(
          selection.toBrushFrameKey(),
        );
    if (hasPicture) {
      return null;
    }
    return AppStrings.of(
      _session.languageSettings.value.programLanguage,
    ).noticeNothingToTransform;
  }

  /// SAVE-1: (re)builds the autosave service to the current policy —
  /// disabled tears it down; an interval change restarts the timer.
  /// FLUTTER_TEST never runs the timer (tests drive [tick] directly).
  void _syncAutosaveService() {
    _autosave?.dispose();
    _autosave = null;
    if (Platform.environment.containsKey('FLUTTER_TEST') ||
        !AppSave.settings.value.autosaveEnabled) {
      return;
    }
    _autosave = ProjectAutosaveService(
      isDirty: () => _session.hasUnsavedChanges,
      writeSnapshot: _session.writeAutosaveSnapshot,
      // Only called once needsProjectFile says a real file exists.
      autosavePath: () => _session.autosaveSidecarPath!,
      // PEN-12 #8: a NEVER-SAVED project autosaves nowhere — instead
      // of piling sidecars into hidden app-data dirs, the first dirty
      // tick asks the user to pick a real file (OpenToonz-style).
      needsProjectFile: () => _session.projectFilePath == null,
      onUnsavedProject: _promptUnsavedAutosave,
      interval: AppSave.autosaveInterval,
    )..start();
  }

  @override
  void dispose() {
    PencilInteractionService.instance.onPencilTap = null;
    _session.voiceRecordingNotice.removeListener(_showVoiceRecordingNotice);
    AppSave.settings.removeListener(_syncAutosaveService);
    _lifecycle?.dispose();
    _autosave?.dispose();
    _session.dispose();
    _panelsMenu.dispose();
    _brushTool.dispose();
    _shortcuts.dispose();
    super.dispose();
  }

  /// Dispatches one registry action — the single funnel every shortcut
  /// lands in (menu items call the same session APIs directly).
  void _invokeAction(String actionId) {
    switch (actionId) {
      case EditorActionIds.framePrevious:
        // PEN-7c: the one-frame step (Ctrl+arrows / comma) — always a
        // frame flip, never a nudge.
        _session.selectPreviousFrame();
      case EditorActionIds.frameNext:
        _session.selectNextFrame();
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
        }
      case EditorActionIds.drawingNext:
        if (_canvasSelectionCommands.hasSelection) {
          if (!_session.brushInputActive.value) {
            _canvasSelectionCommands.nudge(1, 0);
          }
        } else {
          _session.selectNextDrawing();
        }
      case EditorActionIds.playbackToggle:
        final playback = _session.playback;
        if (playback.isActive && playback.isPlaying) {
          playback.pause();
        } else if (playback.isActive) {
          playback.resume();
        } else {
          playback.play(
            scope: PlaybackScope.activeCut,
            startGlobalFrame: _session.currentFrameIndex,
          );
        }
      case EditorActionIds.voiceRecordToggle:
        toggleVoiceRecordingWithFeedback(context, _session);
      case EditorActionIds.undo:
        if (_session.canUndo) {
          _session.undo();
        }
      case EditorActionIds.redo:
        if (_session.canRedo) {
          _session.redo();
        }
      case EditorActionIds.toolBrush:
        _brushTool.value = _brushTool.value.copyWith(tool: CanvasTool.brush);
      case EditorActionIds.toolEraser:
        _brushTool.value = _brushTool.value.copyWith(tool: CanvasTool.eraser);
      case EditorActionIds.toolEyedropper:
        _brushTool.value = _brushTool.value.copyWith(
          tool: CanvasTool.eyedropper,
        );
      case EditorActionIds.toolFill:
        _brushTool.value = _brushTool.value.copyWith(tool: CanvasTool.fill);
      case EditorActionIds.onionSkinToggle:
        _session.toggleOnionSkin();
      case EditorActionIds.canvasRotateCcw:
        _canvasViewCommands.rotateBy(-15);
      case EditorActionIds.canvasRotateCw:
        _canvasViewCommands.rotateBy(15);
      case EditorActionIds.canvasFlipHorizontal:
        _canvasViewCommands.toggleFlipHorizontal();
      case EditorActionIds.toolSelectRect:
        _brushTool.value = _brushTool.value.copyWith(
          tool: CanvasTool.selectRect,
        );
      case EditorActionIds.toolLasso:
        _brushTool.value = _brushTool.value.copyWith(tool: CanvasTool.lasso);
      case EditorActionIds.toolMove:
        _brushTool.value = _brushTool.value.copyWith(tool: CanvasTool.move);
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
        }
      case EditorActionIds.selectionNudgeDown:
        if (_canvasSelectionCommands.hasSelection) {
          if (!_session.brushInputActive.value) {
            _canvasSelectionCommands.nudge(0, 1);
          }
        } else {
          _timelineLayerNav.step(1);
        }
      case EditorActionIds.selectionFreeTransform:
        // R26 #17: Ctrl+T is not its own transform mode — it SWITCHES to
        // the Move tool, so one code path (and one set of guards) owns
        // transforming.
        _brushTool.value = _brushTool.value.copyWith(tool: CanvasTool.move);
      case EditorActionIds.selectionTransformCommit:
        _canvasSelectionCommands.commitTransform();
      case EditorActionIds.selectionTransformCancel:
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
        // PEN-8 #1: keep the editor OUT of the OS chrome (Android status
        // bar / gesture areas, notches) — desktop insets are zero, so this
        // is a tablet-only effect.
        // The app-level shortcut layer (P1): the manager stands bare-letter
        // shortcuts down while a text field has focus; the bindings notifier
        // rebuilds the map live as the user re-records keys.
        body: SafeArea(
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
                    // The pen program's diagnosis overlay (Edit ▸ Input
                    // Inspector) — inert until toggled, observes raw events
                    // only (never a gesture-arena participant).
                    // R26 #35/#13: the shared cursor-notice surface wraps
                    // the whole editor, so any refusal anywhere prints
                    // next to the pointer.
                    child: CursorNoticeOverlay(
                      child: InputInspectorHost(
                        child: Column(
                          children: [
                            // The top strip: title, the menu bar, and the quick actions
                            // (undo/redo/export keep their long-standing keys).
                            Material(
                              color: colorScheme.surfaceContainerHigh,
                              child: Row(
                                children: [
                                  // R26 #24: no app-name label in the strip —
                                  // the menu bar starts at the left edge.
                                  const SizedBox(width: 8),
                                  Expanded(
                                    // Narrow windows scroll the menu bar instead of
                                    // overflowing the strip.
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      // The menu re-reads its enablement per notify: the
                                      // history manager is merged in because brush strokes
                                      // execute into it straight from the canvas (no session
                                      // notify fires for a pen-up), the playback controller
                                      // for the Playback menu's state, the panels bridge for
                                      // the Window checkboxes.
                                      child: ListenableBuilder(
                                        listenable: Listenable.merge([
                                          _session,
                                          _session.historyManager,
                                          _session.playback,
                                          _panelsMenu,
                                        ]),
                                        builder: (context, _) => EditorMenuBar(
                                          session: _session,
                                          panelsMenu: _panelsMenu,
                                          shortcuts: _shortcuts,
                                        ),
                                      ),
                                    ),
                                  ),
                                  ListenableBuilder(
                                    listenable: Listenable.merge([
                                      _session,
                                      _session.historyManager,
                                    ]),
                                    builder: (context, _) => Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          key: const ValueKey<String>(
                                            'undo-button',
                                          ),
                                          tooltip: 'Undo',
                                          onPressed: _session.canUndo
                                              ? _session.undo
                                              : null,
                                          icon: const Icon(Icons.undo),
                                        ),
                                        IconButton(
                                          key: const ValueKey<String>(
                                            'redo-button',
                                          ),
                                          tooltip: 'Redo',
                                          onPressed: _session.canRedo
                                              ? _session.redo
                                              : null,
                                          icon: const Icon(Icons.redo),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    key: const ValueKey<String>(
                                      'export-png-button',
                                    ),
                                    tooltip: 'Export',
                                    onPressed: () {
                                      unawaited(
                                        showDialog<void>(
                                          context: context,
                                          builder: (context) => ExportDialog(
                                            session: _session,
                                            settingsStore:
                                                AppExportSettingsStore(),
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.save_alt),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                            Expanded(
                              child: EditorWorkspace(
                                session: _session,
                                panelsMenu: _panelsMenu,
                                brushTool: _brushTool,
                                canvasViewCommands: _canvasViewCommands,
                                canvasSelectionCommands:
                                    _canvasSelectionCommands,
                                layerNav: _timelineLayerNav,
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
            await _session.saveProjectToFile(path);
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
    // SAVE-1c: every platform prompts — the Save As flow routes to the
    // OS dialog on desktop and the in-app browser on mobile.
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
