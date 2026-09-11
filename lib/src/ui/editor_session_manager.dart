import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/persistence/media_staging_store.dart';
import '../services/project_lookup.dart' show cutPositionOf;
import '../models/app_language.dart';
// The six settings stores are injected THROUGH this class into
// [EditorAppSettings], so their types stay in this file's constructor
// signature even though nothing here reads them.
import '../services/persistence/app_language_settings_store.dart';
import '../services/persistence/app_accent_settings_store.dart';
import '../services/persistence/app_ui_scale_store.dart';
import '../services/persistence/app_workspace_colors_store.dart';
import '../services/persistence/app_input_settings_store.dart';
import '../services/persistence/app_save_settings.dart';
import '../services/persistence/app_save_settings_store.dart';
import '../services/persistence/app_memory_settings_store.dart';
import '../services/persistence/app_memory_settings.dart';
import '../services/persistence/audio_sync_settings_store.dart';
import 'brush/brush_tool_state.dart' show CanvasTool;
import '../models/app_input_settings.dart';
import 'session/drags/drawing_block_move_drag.dart';
import 'session/attach_fx_confirm.dart';
import 'session/editor_app_settings.dart';
import 'session/editor_voice_recording.dart';
import '../models/app_accents.dart';
import '../services/editing/active_cut_helpers.dart';
import '../services/editing/editing_session_state.dart';
import '../services/editing/layer_standing_after_change.dart';
import '../controllers/timeline_controller.dart';
import '../models/bitmap_surface.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_point.dart';
import '../models/cut.dart';
import '../models/drawing_guide.dart';
import '../models/transform_track.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/pixel_verb_subject.dart';
import '../services/brush_frame_editing_coordinator.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/onion_skin_settings.dart';
import '../models/timesheet_info.dart';
import '../models/project.dart';
import '../models/timeline_empty_gaps.dart';
import '../models/delete_subject.dart';
import '../models/timeline_selection_kind.dart';
import '../models/timeline_frame_range.dart';
import '../models/timeline_repeat.dart';
import '../models/timeline_row_address.dart';
import '../models/track.dart';
import '../models/track_frame_range.dart';
import '../models/track_id.dart';
import '../models/track_se_window.dart';
import '../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../services/cut_frame_composite_plan.dart';
import '../services/playback/playback_frame_mapping.dart';
import '../core/dev_profile.dart';
import 'playback/canvas_playback_controller.dart';
import 'session/active_cut_span.dart';
import 'session/cut_placement.dart';
import 'session/block_shift.dart';
import 'session/cut_shift.dart';
import 'session/history_pictures.dart';
import 'text/app_strings.dart';
import '../models/track_frame_axis.dart';
import '../models/storyboard_timeline_layout.dart';
import '../services/commands/cut_command_coordinator.dart';
import '../services/commands/update_layer_transform_enabled_command.dart';
import '../services/commands/cut_reorder_planner.dart';
import '../services/audio/audio_conform_runner.dart' show runConformHere;
import '../native/qa_native_engine.dart';
import 'session/cache_budgets.dart';
import '../services/memory_allowance.dart';
import '../services/brush_tip_stamp_cache.dart';
import '../services/brush_live_stroke_rasterizer.dart';
import '../services/history_manager.dart';
import '../services/project_repository.dart';
import 'audio/audio_conform_store.dart';
import 'brush/brush_canvas_panel.dart';
// ⑨: the row selection grows through the SAME span law the cell selection
// uses — the rail's own drawn row list.
import 'timeline/timeline_cell_exposure_state.dart';
import 'timeline/timeline_drag_preview.dart';
import 'session/live_stroke_landing.dart';
import 'session/session_roles.dart';
import 'session/media_fingerprint_ledger.dart';
import 'session/media_grant_ledger.dart';
import 'session/media_pool.dart';
import 'session/import_landing.dart';
import 'session/project_import_doors.dart';
import 'session/cut_folder_import_door.dart';
import 'session/tvpp_import_door.dart';
import 'session/audio_clips.dart';
import 'session/project_file.dart';
import 'session/project_file_door.dart';
import 'session/project_audio.dart';
import 'session/playback_rig.dart';
import 'session/render_caches.dart';
import 'session/frame_range_move_drag.dart';
import 'session/edge_drag.dart';
import 'session/movie_end_drag.dart';
import 'session/folder_bands.dart';
import 'session/visibility_solo.dart';
import 'session/text_cel_bakes.dart';
import 'session/transitions.dart';
import 'session/camera.dart';
import 'session/frame_scrub.dart';
import 'session/row_selection.dart';
import 'session/row_spans.dart';
import 'session/layer_row_drag.dart';
import 'session/lane_range_move_drag.dart';
import 'session/instructions.dart';
import 'session/onion_skin.dart';
import 'session/effects_and_fx.dart';
import 'session/lane_verbs.dart';
import 'session/auto_frame_for_stroke.dart';
import 'session/track_se_display.dart';
import 'session/storyboard_cursor.dart';
import 'session/storyboard_rows.dart';
import 'session/frame_clipboard.dart';
import 'session/layer_clipboard.dart';
import 'session/active_cut_controllers.dart';
import 'session/layer_stack.dart';
import 'session/layer_verbs.dart';
import 'session/cut_verbs.dart';
import 'session/range_selections.dart';
import 'session/se_entries.dart';
import 'session/drawing_block_move_drag.dart';
import 'session/run_frames_add_drag.dart';
import 'session/opacity_verbs.dart';
import 'session/active_cut_edits.dart';
import 'session/layer_id_mint.dart';
import 'session/layer_marks.dart';
import 'session/exposure_verbs.dart';
import 'session/cell_instances.dart';
import 'session/cell_verbs.dart';
import 'session/folders_and_attachments.dart';
import 'session/project_settings.dart';
import 'session/frame_verbs.dart';
import 'session/standing.dart';
import 'session/cut_move_drag.dart';
import 'session/layer_switch_verbs.dart';
import 'session/editing_canvas.dart';

/// Owns the editable project session for [HomePage]: the repository, undo
/// history, cut/layer/timeline controllers, the cut command coordinator and the
/// transient clipboards.
///
/// It is a lightweight [ChangeNotifier] (Flutter built-in — no external state
/// package): mutations notify listeners so the hosting widget can rebuild. Pure
/// view state (viewport, brush tool, timeline orientation) intentionally stays
/// in the widget.

class EditorSessionManager extends ChangeNotifier
    implements
        ProjectAccess,
        SelectionAccess,
        ChangeSink,
        FrameIds,
        TimelineAccess,
        SessionInternals {
  EditorSessionManager({
    required Project initialProject,
    AudioConformStore? audioConformStore,
    MediaStagingStore? mediaStagingStore,
    AppLanguageSettingsStore? languageSettingsStore,
    AppAccentSettingsStore? accentSettingsStore,
    AppInputSettingsStore? inputSettingsStore,
    AppSaveSettingsStore? saveSettingsStore,
    AppMemorySettingsStore? memorySettingsStore,
    AudioSyncSettingsStore? audioSyncSettingsStore,
    AppWorkspaceColorsStore? workspaceColorsStore,
    AppUiScaleStore? uiScaleStore,
  }) : editingSession = EditingSessionState.forProject(initialProject),
       _injectedAudioConformStore = audioConformStore,
       _injectedMediaStagingStore = mediaStagingStore,
       appSettings = EditorAppSettings(
         languageSettingsStore: languageSettingsStore,
         accentSettingsStore: accentSettingsStore,
         workspaceColorsStore: workspaceColorsStore,
         inputSettingsStore: inputSettingsStore,
         saveSettingsStore: saveSettingsStore,
         memorySettingsStore: memorySettingsStore,
         audioSyncSettingsStore: audioSyncSettingsStore,
         uiScaleStore: uiScaleStore,
       ),
       repository = ProjectRepository(initialProject: initialProject) {
    appSettings.restore();
    historyManager = HistoryManager();
    cutCommandCoordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: editingSession,
      historyManager: historyManager,
      brushFrameStore: renderCaches.brushFrameStore,
    );
    activeCutControllers.rebuild();
    renderCaches.attach();
    playbackRig.attach();
    playbackRig.playback.globalFrameIndexListenable.addListener(
      followPlaybackCut,
    );
    // The lane span's cut-window view follows the span itself; the other
    // half of its input (which cut is open) republishes on cut switch.
    laneRangeSelection.addListener(_publishCutLocalLaneRange);
    // Dirty tracking (P3): every history change — commands, undo/redo and
    // brush strokes, which execute here straight from the canvas — marks
    // the project unsaved.
    historyManager.addListener(projectFile.markDirty);
    // AUDIO-PRO R3: any history change while the device carries playback
    // re-uploads the schedule, so edits (and their undo/redo) are heard
    // within one mixed block. Gated on carrying — the reupload costs a
    // PCM copy, and outside live playback the activation rebuild covers
    // it.
    historyManager.addListener(refreshLiveAudioSchedule);
    layerStack.attach();
    // Text cel projections follow the model through EVERY mutation path
    // (edit/undo/redo/paste/duplicate/link) — one history listener, the
    // sweep re-renders whatever went stale (R5).
    historyManager.addListener(textCelBakes.scheduleTextCelBakeSweep);
    // Every cache's budget, from this device's laws and the allowance a
    // person chose — set now, and again whenever the allowance moves.
    _applyCacheBudgets(enforce: false);
    AppMemory.settings.addListener(_applyCacheBudgets);
  }

  @override
  final EditingSessionState editingSession;
  @override
  final ProjectRepository repository;

  // --- App settings: language, accents, input, save, A/V offset -------------

  /// The app-level settings stores and their restore/persist path, which
  /// stopped being session code: see [EditorAppSettings] for what each one
  /// keeps and why the live values sit on app-wide notifiers instead.
  ///
  /// Everything below is this session's unchanged face on it.
  @override
  final EditorAppSettings appSettings;

  /// The program + notation languages — a value-only channel (widgets
  /// subscribe where they read strings; no whole-session notify).
  ValueNotifier<AppLanguageSettings> get languageSettings =>
      appSettings.languageSettings;

  /// The PROGRAM-language string table, read at call time — for session
  /// verbs that produce user-facing messages and for widgets that already
  /// hold the session.
  AppStrings get uiStrings => appSettings.uiStrings;

  void setLanguageSettings(AppLanguageSettings settings) =>
      appSettings.setLanguageSettings(settings);

  void setAccentSettings(AppAccentSettings settings) =>
      appSettings.setAccentSettings(settings);

  /// R11: the chrome's scale. Reading it is [AppUiScale.value], app-wide
  /// like the accents — this is only the write half.
  void setUiScale(double scale) => appSettings.setUiScale(scale);

  void setInputSettings(AppInputSettings settings) =>
      appSettings.setInputSettings(settings);

  void setSaveSettings(AppSaveSettings settings) =>
      appSettings.setSaveSettings(settings);

  void setMemorySettings(AppMemorySettings settings) =>
      appSettings.setMemorySettings(settings);

  /// Every cache's budget at the automatic allowance, on this device's
  /// laws — what the memory tab's slider scales.
  late final CacheBudgets deviceCacheBudgets = CacheBudgets.forDevice(
    physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
  );

  /// Sets every cache's budget from the device's laws and the allowance a
  /// person chose (the memory tab). A new allowance is a new normal, so it
  /// also lifts what a memory warning had halved.
  ///
  /// 유저 확정: the cel store's hot budget scales to the MACHINE — RAM/4
  /// clamped — instead of assuming a desktop (2026-08-16), and the undo
  /// byte budget the same way, RAM/8 (2026-09-07). Unknown RAM (no engine:
  /// tests, host runs) keeps the old fixed values, byte for byte. Both used
  /// to be set where each was built; this is now the one place every
  /// budget is set.
  void _applyCacheBudgets({bool enforce = true}) {
    final allowance = AppMemory.settings.value.allowanceBytes;
    final by = allowance == null
        ? 1.0
        : deviceCacheBudgets.factorFor(allowance);
    final budgets = deviceCacheBudgets.scaledBy(by);
    MemoryAllowance.factor.value = by;
    renderCaches.applyCacheBudgets(budgets);
    historyManager.byteBudget = budgets.undo;
    playbackRig.playbackCache.playbackCacheByteBudget = budgets.playback;
    QaNativeEngine.instance?.nativeUploadByteBudget = budgets.nativeUploads;
    BrushTipStampCache.instance.byteBudget = budgets.brushTips;
    BrushLiveStrokeRasterizer.residentResultByteBudget = budgets.liveStroke;
    if (enforce) {
      playbackRig.playbackCache.enforcePlaybackCacheBudget();
    }
  }

  // --- Workspace colors: the PROJECT half (R28 #9) --------------------------
  //
  // The app-level half — the NEW-PROJECT defaults and their store — lives in
  // [EditorAppSettings]. These three are project data (R3b): they print, so
  // they travel with the project and each is one undo step.

  // ── the project settings: their own object ──────────────────────────
  //
  // A collaborator (session/project_settings.dart). Callers name it —
  // `session.projectSettings.setProjectFps(24)` (round 8, G4).
  late final ProjectSettings projectSettings = ProjectSettings(
    project: this,
    changes: this,
    internals: this,
  );

  /// The tool a temporary hold sprang FROM; null = no hold live.
  ///
  /// It lives here rather than in the canvas area's State because the PEN
  /// TAIL holds for as long as the pen stays flipped — across strokes,
  /// panel rebuilds and tab switches — where a barrel hold lasted one
  /// press. A State that unmounted mid-hold would lose the tool to spring
  /// back to, and leave the user holding an eraser with nothing to undo
  /// it. Not a listenable: only the release path reads it.
  CanvasTool? heldOriginalTool;

  // ── every pixel this session is holding: its own object ─────────────
  //
  // A collaborator (session/render_caches.dart): the cel stores the
  // archive persists, the two playback render caches built over them,
  // the invalidation hub the commands publish on, and the debounce that
  // restarts warming once per edit burst.
  //
  // ⛔The session keeps [warmActiveCut] — which cut, around which frame,
  // at which quality reads the standing row, the timeline controller and
  // the storyboard order. A cache stack that reached back out for it
  // could not be built at all: the playback rig reaches IN here for the
  // composite cache.
  late final RenderCaches renderCaches = RenderCaches(
    project: this,
    changes: this,
    internals: this,
    onEditActivity: () => playbackRig.prerenderScheduler.notifyEditActivity(),
  );

  /// The OS memory-pressure signal, forwarded by the workspace's binding
  /// observer: the hot cel tier halves and cools, and the playback caches
  /// re-run their budget against the shrunken world. Standing down is
  /// lossless by construction — cels encode to cold, dirty ones stay.
  void respondToMemoryPressure() {
    renderCaches.brushFrameStore.respondToMemoryPressure();
    // ⚠️And the three sheet-ink stores — cel stores like the drawings',
    // and until 2026-09-11 they never heard the warning.
    renderCaches.conteInkRowStore.respondToMemoryPressure();
    renderCaches.conteInkPageStore.respondToMemoryPressure();
    renderCaches.envelopeInkStore.respondToMemoryPressure();
    // ⚠️And the undo stack, which was holding the larger share: a MOVE
    // retains a pre AND a post full-canvas surface per confirm.
    historyManager.respondToMemoryPressure();
    playbackRig.playbackCache.respondToMemoryPressure();
    memoryPressureTicks.value += 1;
  }

  /// 🚨**HOW THE WARNING REACHES A CACHE THE SESSION DOES NOT OWN.**
  ///
  /// Every cache above is the session's, so the session stands it down
  /// directly. The media viewers' page rasters are not: they live in a
  /// widget's State, they are created and thrown away as tabs open, and
  /// there can be two of them. Handing the session a registry of live
  /// viewers to call would mean widgets registering and unregistering
  /// themselves correctly on every rebuild — a notifier they can simply
  /// listen to costs neither side a lifecycle rule.
  ///
  /// It counts rather than carrying a payload because the SIGNAL is the
  /// whole message, and consecutive warnings must each be one tick (a
  /// bool would coalesce the second one into silence).
  final ValueNotifier<int> memoryPressureTicks = ValueNotifier<int>(0);

  // ── playback's own machinery: its own object ────────────────────────
  //
  // A collaborator (session/playback_rig.dart): the transport, its three
  // audio paths, the prerender warmer and the cache budget it feeds.
  //
  // ⛔The session keeps the REACTIONS below — where the playhead lands
  // when a run stops, which cut goes active while it crosses one, what a
  // rolling take does about it. They touch the selection, the standing
  // row and the voice recorder, and a rig that reached back out for those
  // could not be built: `Standing` and `RangeSelections` reach IN here
  // for the warmer.
  late final PlaybackRig playbackRig = PlaybackRig(
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    internals: this,
    renderCaches: renderCaches,
    settings: projectSettings,
    audioConformStore: audioConformStore,
    voiceRecording: voiceRecording,
    onStopped: _onPlaybackStopped,
    onStoppedInGap: _onPlaybackStoppedInGap,
    onPlaylistWarmRequested: _onPlaybackPlaylistWarmRequested,
  );

  /// ⚠️`void` and `async`: the playback controller does not wait for this,
  /// but the BODY's own order still matters — the take has to have landed
  /// before the cut selection below runs, or the two commands reach the
  /// undo history in whichever order the isolate happened to finish in.
  Future<void> _onPlaybackStopped(PlaybackPosition lastPosition) async {
    // Transport stop finishes a rolling take (REC1-B): record = play +
    // capture, so ending one ends the other. The result message goes out
    // on the notice channel — this path has no button to return through.
    if (voiceRecording.isVoiceRecording.value) {
      voiceRecording.voiceRecordingNotice.value =
          await voiceRecording.stopVoiceRecordingAndPlace();
    }
    if (lastPosition.cutId != editingSession.activeCutId) {
      selectCut(lastPosition.cutId);
    }
    selectFrameIndex(
      activeCutControllers.clampedFrameIndex(lastPosition.localFrameIndex),
    );
    // The mid-playback cut follow is QUIET (R12-B) — this is the one
    // session notify that catches every activeCut consumer up with where
    // playback landed.
    notifyListeners();
  }

  /// Stop landed on a playlist GAP frame (UI-R9 #3): match the editing
  /// gap semantics — park there with NO active cut.
  /// ⚠️`void` and `async` for the same reason as [_onPlaybackStopped].
  Future<void> _onPlaybackStoppedInGap(int globalFrame) async {
    // The gap-stop twin of _onPlaybackStopped's take finish: a lane is
    // cut-independent, so a take may legitimately end over a gap.
    if (voiceRecording.isVoiceRecording.value) {
      voiceRecording.voiceRecordingNotice.value =
          await voiceRecording.stopVoiceRecordingAndPlace();
    }
    gapGlobalFrame = globalFrame;
    _deselectActiveCutForGap();
    frameSeekCommitted.value += 1;
    notifyListeners();
  }

  /// Premiere-style follow: while playback crosses cut boundaries the
  /// ACTIVE cut tracks the playing cut and stays there when playback
  /// stops. Playback-only selection state — no command runs, the undo
  /// stack never sees it. QUIET by design (R12-B): no session notify and
  /// no warming — a boundary tick must not rebuild the visible panels
  /// mid-playback (that stutter was audible as the cut-transition lag).
  /// Live position display rides the playback listenables; activeCut
  /// consumers catch up on the stop notify.
  @override
  void followPlaybackCut() {
    if (playbackRig.playback.globalFrameIndexListenable.value == null) {
      return;
    }
    final position = playbackRig.playback.position;
    if (position == null || position.cutId == editingSession.activeCutId) {
      return;
    }
    editingSession.setActiveCutId(position.cutId);
    clipboard.dropCopiedFrame();
    activeCutControllers.rebuild(preferredFrameIndex: position.localFrameIndex);
  }

  void _onPlaybackPlaylistWarmRequested(
    List<StoryboardTimelineLayoutEntry> playlist,
    PlaybackScope scope,
    int startGlobalFrame,
  ) {
    // Playhead-forward with wrap-around: the frames about to play warm
    // first, so first-pass misses shrink toward zero and a looping second
    // pass starts fully cached.
    final frames = <(CutId, int)>[
      for (final entry in playlist)
        for (var index = 0; index < entry.duration; index += 1)
          (entry.cutId, index),
    ];
    if (frames.isEmpty) {
      return;
    }
    final start = startGlobalFrame.clamp(0, frames.length - 1);
    playbackRig.prerenderScheduler.requestWarmFrames(
      frames: [...frames.sublist(start), ...frames.sublist(0, start)],
      quality: playbackRig.playbackQuality,
    );
  }

  @override
  late final HistoryManager historyManager;

  /// Undo and redo whose first frame is whole — see [HistoryPictures].
  late final HistoryPictures historyPictures = HistoryPictures(
    history: historyManager,
  );
  @override
  late final CutCommandCoordinator cutCommandCoordinator;
  @override
  final CutReorderPlanner cutReorderPlanner = const CutReorderPlanner();

  // ── the active cut's two controllers: their own object ──────────────
  //
  // A collaborator (session/active_cut_controllers.dart). Everything
  // reads them and exactly one thing replaces them, together, because
  // they are one fact: the cut this session is editing.
  //
  // ⛔The session keeps the REACTION to a rebuild — the stranded verb
  // row, the drawn row, the cut-local view of a track-global lane span.
  // Those touch the standing row, and `Standing` reads the controllers,
  // so they arrive there as the `onRebuilt` callback.
  late final ActiveCutControllers activeCutControllers = ActiveCutControllers(
    project: this,
    selection: this,
    timeline: this,
    internals: this,
    playbackFrameCount: () => activeCutSpan.activeCutPlaybackFrameCount,
    trackSeDisplayLayers: () => trackSe.trackSeDisplayLayers,
    trackTransitionDisplayLayer: () => transitions.trackTransitionDisplayLayer,
    onRebuilt: () {
      standing.unseatStrandedVerbRow();
      // A cut switch re-seats the active layer, which is what the drawn row
      // falls back to when nothing is engaged.
      standing.publishCurrentRow();
      // The window moved, so the part of a track-global lane span this cut
      // can see moved with it. The selection itself is untouched.
      _publishCutLocalLaneRange();
    },
  );

  int _frameSequence = 0;

  // ── where a new row's id comes from: its own object ─────────────────
  //
  // A collaborator (session/layer_id_mint.dart): the `default-layer-N`
  // counter, and the project scan that keeps it honest.
  late final LayerIdMint layerIds = LayerIdMint(project: this);

  // ── the frame clipboard: its own object, in its own file ────────────
  //
  // A collaborator (session/frame_clipboard.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final FrameClipboard clipboard = FrameClipboard(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, internals: this, renderCaches: renderCaches);
  late final LayerClipboard layerClipboard = LayerClipboard(project: this, selection: this, changes: this, layerStack: layerStack);

  // ── the layer verbs: their own object, in their own file ────────────
  //
  // A collaborator (session/layer_verbs.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final LayerVerbs layerVerbs = LayerVerbs(project: this, selection: this, changes: this, controllers: activeCutControllers, activeCut: _activeCutEdits);

  // ── the cut's row stack: its own object ─────────────────────────────
  //
  // A collaborator (session/layer_stack.dart): which rows this cut can
  // still gain, and whether the row it already has is holding a picture.
  //
  // ⛔It does not reimplement "insert above the active row" — that verb
  // is [LayerVerbs.addRowAboveActive] and the stack calls it. What lives
  // there is the kind-by-kind decision of WHAT to insert.
  late final LayerStack layerStack = LayerStack(
    project: this,
    selection: this,
    changes: this,
    frameIds: this,
    controllers: activeCutControllers,
    internals: this,
    layerIds: layerIds,
    layerVerbs: layerVerbs,
    standing: standing,
    folderBands: folderBands,
    renderCaches: renderCaches,
    brushInputActive: brushInputActive,
  );

  bool get canCopyFrameAtCurrentFrame => clipboard.canCopyFrameAtCurrentFrame;
  void copyFrameAtCurrentFrame() => clipboard.copyFrameAtCurrentFrame();
  bool get canPasteLinkedFrameAtCurrentFrame =>
      clipboard.canPasteLinkedFrameAtCurrentFrame;
  bool get canPasteIndependentFrameAtCurrentFrame =>
      clipboard.canPasteIndependentFrameAtCurrentFrame;
  void pasteIndependentFrameAtCurrentFrame() =>
      clipboard.pasteIndependentFrameAtCurrentFrame();
  void pasteLinkedFrameAtCurrentFrame() =>
      clipboard.pasteLinkedFrameAtCurrentFrame();
  String get copiedFrameStatusText => clipboard.copiedFrameStatusText;
  String get linkedFrameUsesStatusText => clipboard.linkedFrameUsesStatusText;

  /// NULL = the editing playhead stands in a GAP (UI-R9 #3): no cut is
  /// selected. Cut-scoped surfaces show their empty states; cut-scoped
  /// commands stand down.
  @override
  CutId? get activeCutId => editingSession.activeCutId;

  bool get canUndo => historyManager.canUndo;
  bool get canRedo => historyManager.canRedo;

  // Where the user stands (Round 6): cut, row and layer.
  late final Standing standing = Standing(project: this, selection: this, changes: this, timeline: this, controllers: activeCutControllers, clipboard: clipboard, rowSelectionVerbs: rowSelectionVerbs, solo: visibilitySolo, trackSe: trackSe, rangeSelections: rangeSelections, internals: this, playbackRig: playbackRig);

  void selectCut(CutId cutId) => standing.selectCut(cutId);
  @override
  TimelineRowAddress get currentRow => standing.currentRow;
  @override
  void standOnRow(
    TimelineRowAddress row, {
    int? frameIndex,
    int? globalFrameIndex,
    bool takesLayerActive = true,
  }) => standing.standOnRow(
    row,
    frameIndex: frameIndex,
    globalFrameIndex: globalFrameIndex,
    takesLayerActive: takesLayerActive,
  );
  @override
  void selectLayer(LayerId layerId) => standing.selectLayer(layerId);
  void selectRow(TimelineRowAddress row) => standing.selectRow(row);
  void handOffCurrentRowOnFold(LayerId layerId, {String? laneId}) =>
      standing.handOffCurrentRowOnFold(layerId, laneId: laneId);
  void claimTimelineRow() => standing.claimTimelineRow();

  /// THE selected track — the storyboard's row selection, read by everything
  /// that used to hunt for "whichever track owns the active cut".
  ///
  /// Track selection is FIRST-CLASS state now ([EditingSessionState]): the
  /// old derivation had nowhere to live whenever the playhead parked in a
  /// gap, so tapping a V row and then scrubbing into a gap lost it. The
  /// reconciliation keeps the answer identical to the old one while a cut
  /// is active — the cut's own track wins — and falls back to the stored
  /// selection (then the first track) only when there is no active cut or
  /// the stored track is gone.
  @override
  TrackId get selectedTrackId {
    final project = repository.requireProject();
    final cutTrackId = trackIdOfCut(project, editingSession.activeCutId);
    if (cutTrackId != null) {
      return cutTrackId;
    }

    final stored = editingSession.selectedTrackId;
    if (stored != null) {
      for (final track in project.tracks) {
        if (track.id == stored) {
          return stored;
        }
      }
    }

    if (project.tracks.isEmpty) {
      throw StateError(
        'Cannot resolve the selected track in an empty project.',
      );
    }
    return project.tracks.first.id;
  }

  // ── the storyboard rows: their own object, in their own file ────────
  //
  // A collaborator (session/storyboard_rows.dart). Callers name it —
  // `session.storyboardRows.storyboardSelectedCutIds` (round 8, G3).
  late final StoryboardRows storyboardRows = StoryboardRows(
    project: this,
    selection: this,
    timeline: this,
    projectSettings: projectSettings,
  );

  void claimStoryboardRow() => standing.claimStoryboardRow();
  void updateStoryboardCutSelectionByFrame({
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TrackId? trackId,
    TimelineRowAddress? headRow,
  }) => rangeSelections.updateStoryboardCutSelectionByFrame(
    anchorGlobalFrame: anchorGlobalFrame,
    headGlobalFrame: headGlobalFrame,
    trackId: trackId,
    headRow: headRow,
  );
  @override
  void clearStoryboardCutSelection() =>
      storyboardRows.clearStoryboardCutSelection();

  /// [currentRow] as a LISTENABLE — R10 #19's other half. The row you are
  /// standing on is DRAWN now (the active layer's row, an fx header, a
  /// property lane), and the rails have to learn it moved WITHOUT a
  /// session notify: the claim that moves it fires on pointer-down, inside
  /// gestures whose whole contract is silence until release.
  ///
  /// A [ValueNotifier] only notifies on a real change, so pressing again
  /// in the row you are already standing on costs nothing — which is the
  /// common case, and the reason this can be published eagerly.
  @override
  final ValueNotifier<TimelineRowAddress?> currentRowListenable =
      ValueNotifier<TimelineRowAddress?>(null);

  /// The role's face on [RowSelection.rowSelection] — the collaborator owns
  /// the notifier, the session plays the role every other collaborator
  /// names.
  @override
  ValueNotifier<List<TimelineRowAddress>> get rowSelection =>
      rowSelectionVerbs.rowSelection;

  // ── the row selection: its own object, in its own file ──────────────
  //
  // A collaborator (session/row_selection.dart): the ⑨ row sweep — its
  // anchor, its span and the fold that swallows what left the screen.
  // ── what a row spans: its own object ───────────────────────────────
  //
  // A collaborator (session/row_spans.dart): where a row's material starts
  // and ends, what a range drag over it snaps to, and where a cut's frame
  // sits on the GLOBAL axis.
  late final RowSpans rowSpans = RowSpans(project: this, timeline: this, folderBands: folderBands, projectSettings: projectSettings, trackSe: trackSe, transitions: transitions);

  late final RowSelection rowSelectionVerbs = RowSelection(rangeSelections: rangeSelections);

  /// ⚠️Two ROLE members, not forwarders: [SessionInternals.rowIsSelected]
  /// and [SelectionAccess.clearRowSelection] are asked of the SESSION by
  /// collaborators that must not name this one (RowSelection already holds
  /// RangeSelections, so the edge back would close a construction cycle).
  @override
  bool rowIsSelected(TimelineRowAddress row) =>
      rowSelectionVerbs.rowIsSelected(row);
  @override
  void clearRowSelection() => rowSelectionVerbs.clearRowSelection();

  // ── the range selections: their own object, in their own file ───────
  //
  // A collaborator (session/range_selections.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final RangeSelections rangeSelections = RangeSelections(project: this, selection: this, changes: this, timeline: this, storyboardRows: storyboardRows, trackSe: trackSe, rowSpans: rowSpans, internals: this, playbackRig: playbackRig);

  void updateFrameRangeSelectionDrag({
    required LayerId layerId,
    required int anchorIndex,
    required int headIndex,
    LayerId? headLayerId,
    String? headLaneId,
    List<TimelineRowAddress> spanRows = const [],
  }) => rangeSelections.updateFrameRangeSelectionDrag(
    layerId: layerId,
    anchorIndex: anchorIndex,
    headIndex: headIndex,
    headLayerId: headLayerId,
    headLaneId: headLaneId,
    spanRows: spanRows,
  );
  @override
  void clearFrameRangeSelection() =>
      rangeSelections.clearFrameRangeSelection();
  void updateTrackRowRangeSelectionByFrame({
    required LayerId layerId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TimelineRowAddress? headRow,
    TimelineRowAddress? anchorRow,
    List<TimelineRowAddress> spanRows = const [],
  }) => rangeSelections.updateTrackRowRangeSelectionByFrame(
    layerId: layerId,
    anchorGlobalFrame: anchorGlobalFrame,
    headGlobalFrame: headGlobalFrame,
    headRow: headRow,
    anchorRow: anchorRow,
    spanRows: spanRows,
  );
  void updateLaneRangeSelectionDrag({
    required LayerId layerId,
    required String laneId,
    required int anchorIndex,
    required int headIndex,
    String? headLaneId,
    required List<String> spanLaneIds,
    bool framesAreGlobal = false,
  }) => rangeSelections.updateLaneRangeSelectionDrag(
    layerId: layerId,
    laneId: laneId,
    anchorIndex: anchorIndex,
    headIndex: headIndex,
    headLaneId: headLaneId,
    spanLaneIds: spanLaneIds,
    framesAreGlobal: framesAreGlobal,
  );
  void clearLaneRangeSelection() => rangeSelections.clearLaneRangeSelection();
  bool standingInsideSelection(
    TimelineRowAddress row, [
    int? frameIndex,
    bool frameIsGlobal = false,
  ]) =>
      rangeSelections.standingInsideSelection(row, frameIndex, frameIsGlobal);
  bool get hasAnySelection => rangeSelections.hasAnySelection;
  @override
  void clearAllSelections() => rangeSelections.clearAllSelections();
  void claimSelection(TimelineSelectionKind kind) =>
      rangeSelections.claimSelection(kind);
  void revealSelection() => rangeSelections.revealSelection();
  void beginSelectionInteraction() =>
      rangeSelections.beginSelectionInteraction();
  void endSelectionInteraction() => rangeSelections.endSelectionInteraction();

  /// The ladder every band verb climbs at the PLAYHEAD: the band answers
  /// first ([bandAnswers]), a band that names rows this press would miss
  /// ENDS it, and only then is the active row asked.
  ///
  /// ⛔THE MIDDLE RUNG IS THE ONE THAT MATTERS. A live band holding
  /// nothing the verb can touch makes the press a NO-OP — never a
  /// redirect onto whatever row happens to be active. A cell drag never
  /// moves the active layer, so those are routinely different rows, and a
  /// verb that skipped this rung would edit a row nobody swept.
  ///
  /// ⚠️Not every button climbs it: `＋` CREATES and is deliberately
  /// band-free.
  @override
  bool bandOrActiveRow(
    bool bandAnswers,
    bool Function(Layer layer) accepts,
    bool Function(Layer layer) atPlayhead,
  ) {
    if (bandAnswers) {
      return true;
    }
    if (bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = activeLayer;
    return layer != null && accepts(layer) && atPlayhead(layer);
  }

  /// The band answer a selection verb reaches: the swept rows whose layer
  /// passes [accepts], handed to [inBand] as ONE ask, and `const {}` when
  /// the band names nothing the verb can touch.
  ///
  /// ⚠️THE KIND FILTER LIVES IN THE VERB, NOT THE CONTROLLER — the button
  /// (`can…`) and the dispatch have to read one answer, and the verbs'
  /// own comments already named "three downstream copies of a filter" as
  /// how they stop agreeing. This is the walk they share; what differs is
  /// the predicate each verb names.
  @override
  Map<LayerId, T> bandRowsForSelection<T>(
    bool Function(Layer layer) accepts,
    Map<LayerId, T> Function(
      List<LayerId> ids,
      TimelineFrameRangeSelection selection,
    )
    inBand,
  ) {
    final selection = frameRangeSelection.value;
    if (selection == null) {
      return const {};
    }
    final ids = <LayerId>[];
    for (final id in selection.spanLayerIds) {
      final layer = rangeLayerById(id);
      if (layer != null && accepts(layer)) {
        ids.add(id);
      }
    }
    return ids.isEmpty ? const {} : inBand(ids, selection);
  }

  /// Whether the artwork carries a marquee, published by whoever owns it.
  @override
  bool Function()? canvasHasSelection;

  /// Lets go of the marquee, published by whoever owns it.
  @override
  void Function()? clearCanvasSelection;

  /// The live editing coordinator, published by the canvas host.
  ///
  /// 🚨Null before the canvas has built one — a fresh project, a gap parking,
  /// a test that mounts the timeline alone. Every pixel verb asks, and the
  /// buttons dim rather than the press throwing.
  @override
  BrushFrameEditingCoordinator? pixelEditingCoordinator;

  /// Where the canvas leaves 「land the stroke the pen is holding」, and
  /// where the save door picks it up.
  ///
  /// 🚨Filled in exactly the way [pixelEditingCoordinator] is, from the same
  /// build — but it is a SIBLING object rather than a name on
  /// [SessionInternals], because that interface only shrinks. See
  /// [LiveStrokeLanding] for the rest of the reason.
  final LiveStrokeLanding liveStrokeLanding = LiveStrokeLanding();

  /// The canvas-side facts a pixel-verb press needs, published by whoever
  /// owns them — see [PixelVerbCanvas].
  ///
  /// ⛔A getter, not a copy. The marquee is a document-level fact that
  /// survives tool switches (`CanvasSelectionCommands.region`), the colour
  /// changes under the pointer, and the mask moves with the tool settings
  /// panel — so a snapshot taken when the toolbar was built would act on a
  /// selection the user has since redrawn, in a colour they have left.
  ///
  /// 🚨The colour's ALPHA is ignored downstream — RGB only (유저 확정).
  @override
  PixelVerbCanvas Function()? pixelVerbCanvas;

  /// WHICH cels the two PIXEL verbs would act on — see [PixelVerbSubject].
  @override
  PixelVerbSubject get pixelVerbSubject {
    if (cells.pixelVerbCellKeys().isEmpty) {
      return PixelVerbSubject.nothing;
    }
    return frameRangeSelection.value == null
        ? PixelVerbSubject.standing
        : PixelVerbSubject.range;
  }

  // ── the cell verbs: their own object, in their own file ─────────────
  //
  // A collaborator (session/cell_verbs.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final CellVerbs cells = CellVerbs(project: this, selection: this, changes: this, timeline: this, controllers: activeCutControllers, laneVerbs: laneVerbs, rangeSelections: rangeSelections, clipboard: clipboard, internals: this, renderCaches: renderCaches);

  @override
  TimelineRowAddress get selectedRow => standing.selectedRow;

  /// Makes a V row THE selected row and nothing else — no cut promotion, no
  /// seek. The cells press wants this half on its own: the frame it presses
  /// decides the cut, so promoting the playhead's cut first would switch
  /// cuts twice for one press.
  @override
  void selectTrackRow(TrackId trackId) {
    if (editingInteractionBusy) {
      return;
    }
    final trackBefore = selectedTrackId;
    editingSession.setSelectedTrackId(trackId);
    if (standing.storeStoryboardRow(TrackRowAddress(trackId)) ||
        selectedTrackId != trackBefore) {
      notifyListeners();
    }
  }

  // --- Track-owned SE rows --------------------------------------------------
  //
  // SE rows live on the TRACK (global frame axis — sounds may cross cut
  // boundaries). Reads go through cut-local DISPLAY clones composed into
  // [layers]; mutations detect track-SE ids, convert local→global through
  // the window, and edit the track's GLOBAL layer (the clones are never
  // written back).

  @override
  Track get activeTrack {
    final trackId = selectedTrackId;
    return repository.requireProject().tracks.firstWhere(
      (track) => track.id == trackId,
    );
  }

  // ── the transitions: their own object, in their own file ───────────────
  //
  // A collaborator (session/transitions.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final Transitions transitions = Transitions(
    project: this,
    selection: this,
    changes: this,
    camera: camera,
  );

  @override
  bool isTrackTransitionLayerId(LayerId layerId) =>
      transitions.isTrackTransitionLayerId(layerId);
  /// The active cut's global start frame on its track (cumulative cut
  /// durations — the storyboard layout's number for this cut).
  @override
  int get activeCutGlobalStartFrame =>
      cutGlobalStartFrameIn(activeTrack, editingSession.activeCutId) ?? 0;

  // ── the track SE display: its own object, in its own file ───────────
  //
  // A collaborator (session/track_se_display.dart). ⛔The forwarders are
  // gone (G3, 2026-09-07): callers say `session.trackSe.x`. What is left
  // below is the session IMPLEMENTING a role — those three are members of
  // `ProjectAccess`/`SessionInternals`, not a second name for a verb.
  late final TrackSeDisplay trackSe = TrackSeDisplay(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, transitions: transitions, voiceRecording: voiceRecording);

  @override
  TrackSeWindow get trackSeWindow => trackSe.trackSeWindow;
  @override
  bool isTrackSeLayerId(LayerId layerId) => trackSe.isTrackSeLayerId(layerId);
  @override
  Layer? trackSeGlobalLayerById(LayerId layerId) =>
      trackSe.trackSeGlobalLayerById(layerId);

  // ── the SE entries and name tags: their own object ──────────────────
  //
  // A collaborator (session/se_entries.dart). ⛔The forwarders are gone
  // (G3, 2026-09-07): callers say `session.seEntries.x`.
  late final SeEntries seEntries = SeEntries(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, camera: camera, trackSe: trackSe, frameVerbs: frameVerbs);

  // ── the sounds an SE row carries: their own object ───────────────────
  //
  // A collaborator (session/audio_clips.dart). It OWNS the in-flight slide
  // drag, which was the one host field this cluster wrote.
  late final AudioClips audioClips = AudioClips(
    project: this,
    selection: this,
    changes: this,
    controllers: activeCutControllers,
    pool: mediaPool,
    seEntries: seEntries,
  );

  // `activeSeNameTagDefaultPosition` seeded the placement dialog's x/y
  // fields from a stacked per-row default. Both are gone with R5 #7: a tag
  // has no position of its own, so the SE row's Position lane is the whole
  // answer and there is nothing to seed.

  // ── the folder bands: their own cache, in their own file ───────────────
  //
  // A collaborator (session/folder_bands.dart): the folder row the rails
  // DRAW — its members, their merged runs, and the cache that keeps the
  // three one answer.
  late final FolderBands folderBands = FolderBands(project: this);

  @override
  void refreshAfterCutCommand({
    LayerId? preferredActiveLayerId,
    int? preferredFrameIndex,
  }) {
    clipboard.dropCopiedFrame();
    clearFrameRangeSelection();
    activeCutControllers.rebuild(
      // The ACTIVE layer survives cut commands by default (UI-R20 #1:
      // adding a camera key must not throw the selection to the bottom
      // row) — commands that switch cuts fall back naturally because the
      // old layer fails the has-layer check.
      preferredActiveLayerId: preferredActiveLayerId ?? activeLayerId,
      preferredFrameIndex:
          preferredFrameIndex ??
          activeCutControllers.timelineController.currentFrameIndex,
    );
    // Layer add/delete/undo may have moved the active row: keep the solo
    // mode following it (or exit if the command switched cuts).
    visibilitySolo.syncVisibilitySolo();
    warmActiveCut();
  }

  /// The cut with [cutId] anywhere in the project, or `null`.
  @override
  Cut? cutById(CutId cutId) =>
      cutPositionOf(repository.requireProject(), cutId)?.cut;

  /// The brush store key of a layer frame within [cut] — same derivation the
  /// canvas selection uses (track containing the cut, first track fallback).
  @override
  BrushFrameKey brushFrameKeyForCut(Cut cut, LayerId layerId, FrameId frameId) {
    final project = repository.requireProject();
    final trackId =
        cutPositionOf(project, cut.id)?.trackId ??
        (project.tracks.isEmpty ? const TrackId('') : project.tracks.first.id);
    return BrushFrameKey(
      projectId: project.id,
      trackId: trackId,
      cutId: cut.id,
      layerId: layerId,
      frameId: frameId,
    );
  }

  /// Warms the active cut's composites around the playhead ("navigate away
  /// from a frame and it gets pre-rendered") — and the NEXT cut behind it
  /// (#31, 유저 확정: 스토리보드 프로의 룩어헤드를 따른다). The next cut
  /// is next in STORYBOARD order, the same order play-all and the panel
  /// read, so the bar that goes green is the bar beside the one you are
  /// on.
  @override
  void warmActiveCut() {
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    playbackRig.prerenderScheduler.requestWarmCut(
      cutId: cut.id,
      quality: playbackRig.playbackQuality,
      aroundFrameIndex:
          activeCutControllers.timelineController.currentFrameIndex,
      followedByCutId: storyboardRows.nextCutIdInStoryboardOrder(cut.id),
    );
  }

  @override
  void dispose() {
    // First: a bake sweep suspended across an engine await must find the
    // flag set when it resumes — it stops touching the stores and never
    // notifies a disposed ChangeNotifier.
    disposed = true;
    for (final letGo in _teardown) {
      letGo();
    }
    super.dispose();
  }

  /// Everything the constructor wired up or opened, in the order it must be
  /// let go of — one list this class HOLDS, rather than a teardown it
  /// spells out step by step.
  ///
  /// ⛔THE ORDER IS NOT FREE, and it is the hand-written teardown's own
  /// order, kept entry for entry (2026-09-08, when the steps became a
  /// list). Three constraints run through it:
  ///   - every `removeListener` comes before the thing it was listening to
  ///     is released: the lane range before [cutLocalLaneRangeSelection],
  ///     the playback cursor before [playbackRig], the three history
  ///     listeners before [historyManager] at the very end;
  ///   - [LayerStack.dispose] removes ITS OWN listeners from [renderCaches]
  ///     and [brushInputActive], so it runs before either of them;
  ///   - [historyManager] goes last, after every listener it carries.
  /// A new entry belongs at the END unless it has one of those reasons —
  /// and then the reason is written here.
  List<void Function()> get _teardown => [
    () => AppMemory.settings.removeListener(_applyCacheBudgets),
    textCelBakes.dispose,
    layerStack.dispose,
    currentRowListenable.dispose,
    rowSelectionVerbs.dispose,
    // ⚠️Deleting this line alone survives the teardown test: the `disposed`
    // guard inside [_publishCutLocalLaneRange] already answers. It stays
    // because the guard is the belt and this is the braces — a listener you
    // added is a listener you remove (measured 2026-09-08: with BOTH gone,
    // the test reports the write to a disposed notifier).
    () => laneRangeSelection.removeListener(_publishCutLocalLaneRange),
    cutLocalLaneRangeSelection.dispose,
    revealSelectionTick.dispose,
    memoryPressureTicks.dispose,
    () => playbackRig.playback.globalFrameIndexListenable.removeListener(
      followPlaybackCut,
    ),
    () => historyManager.removeListener(projectFile.markDirty),
    () => historyManager.removeListener(refreshLiveAudioSchedule),
    () => historyManager.removeListener(textCelBakes.scheduleTextCelBakeSweep),
    voiceRecording.dispose,
    playbackRig.dispose,
    renderCaches.dispose,
    audioConformStore.dispose,
    appSettings.dispose,
    soloedSeLayerIds.dispose,
    editingFrameCursor.dispose,
    frameScrubActive.dispose,
    scrubOutOfTerritory.dispose,
    frameSeekCommitted.dispose,
    _gapGlobalFrameNotifier.dispose,
    frameRangeSelection.dispose,
    brushInputActive.dispose,
    selectionInteractionActive.dispose,
    dragPreview.dispose,
    transitionEdgeDragPreview.dispose,
    opacityDragPreview.dispose,
    onionSkinSettings.dispose,
    onionSkinLayerIds.dispose,
    trackFrameRangeSelection.dispose,
    historyPictures.dispose,
    historyManager.dispose,
  ];

  /// Test seam: widget tests inject a store with a fake runner so SE rows
  /// never decode real files.
  final AudioConformStore? _injectedAudioConformStore;
  final MediaStagingStore? _injectedMediaStagingStore;

  /// Where 품기 puts the bytes until a save absorbs them.
  ///
  /// 🚨Injectable for the same reason every other store here is: a test
  /// must not write into the real app container.
  late final MediaStagingStore mediaStagingStore =
      _injectedMediaStagingStore ?? MediaStagingStore();

  /// Conformed audio per source path (audio program wiring): waveform
  /// peaks, exact clip lengths and the device transport's PCM, decoded
  /// ONCE per file off the UI isolate. Conforms live in the app container
  /// (or a drive the user named), in a folder per project, under a name
  /// derived by rule from the source path — nothing recorded, nothing to
  /// fall out of sync.
  late final AudioConformStore audioConformStore =
      (_injectedAudioConformStore ??
            AudioConformStore(
              resolveConformPath: projectFile.conformPathFor,
              resolveByteSource: projectFile.mediaByteSourceFor,
              resolveCarriedConform: projectFile.carriedConformFor,
              resolveProjectSampleRate: () =>
                  repository.requireProject().audioSampleRate,
              resolveAudioSpeed: () {
                final project = repository.requireProject();
                return (
                  numerator: project.audioSpeedNumerator,
                  denominator: project.audioSpeedDenominator,
                );
              },
              // Widget tests: run conforms inline — a worker isolate started
              // under fake async outlives the test (the prerender scheduler's
              // FLUTTER_TEST branch, same reason). Missing fixture paths
              // short-circuit before any decode, so this stays cheap.
              runner: Platform.environment['FLUTTER_TEST'] == 'true'
                  ? (request) => Future.value(runConformHere(request))
                  : null,
            ))
        // The store answers when a conform lands or is let go, which is
        // exactly when the pool's size column stops being true.
        ..addListener(projectFile.invalidateConformStoredBytes)
        ..addListener(notifyListeners);

  // ── the active cut's span: its own object, in its own file ────────────
  //
  // How much film the active cut IS and which rows it shows
  // (session/active_cut_span.dart): the composed row list, the playback
  // and drawn frame counts, the のりしろ label and the export anchor.
  late final ActiveCutSpan activeCutSpan = ActiveCutSpan(
    project: this,
    selection: this,
    appSettings: appSettings,
    camera: camera,
    trackSe: trackSe,
    transitions: transitions,
  );

  /// ⛔THIS USED TO RE-DERIVE THE MEMBERSHIP BY KIND and knew only two of
  /// the three sources (see [ActiveCutSpan.activeCutRowLayers] for H17 and
  /// what it cost). It asks the composed list instead — and it stays HERE
  /// rather than moving into [ActiveCutSpan] because
  /// [ActiveCutControllers] is what asks it, and the span reads the
  /// track-owned rows those controllers build: injecting it there would
  /// close a construction cycle.
  @override
  bool activeCutHasLayer(LayerId? layerId) {
    if (layerId == null) {
      return false;
    }
    return activeCutSpan.activeCutRowLayers.any((layer) => layer.id == layerId);
  }

  // --- Cut commands -------------------------------------------------------

  // ── where a new cut lands: its own object, in its own file ────────────
  //
  // The one expression the Create Cut pill and the verb both read
  // (session/cut_placement.dart).
  late final CutPlacement cutPlacement = CutPlacement(
    selection: this,
    timeline: this,
  );

  // The envelope every active-cut and active-row verb shares, in seven
  // collaborators (session/active_cut_edits.dart). It is wired HERE and
  // handed to each of them; a collaborator that builds its own is a
  // second envelope waiting to drift.
  late final ActiveCutEdits _activeCutEdits = ActiveCutEdits(
    selection: this,
    timeline: this,
    changes: this,
  );

  // ── the cut verbs: their own object, in their own file ──────────────
  //
  // A collaborator (session/cut_verbs.dart). Callers name it —
  // `session.cutVerbs.createCut()` — because a forwarder here would be a
  // second name for the same verb (round 8, G3).
  late final CutVerbs cutVerbs = CutVerbs(
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    controllers: activeCutControllers,
    storyboardRows: storyboardRows,
    internals: this,
    activeCut: _activeCutEdits,
    placement: cutPlacement,
  );

  @override
  Cut? get activeCutOrNull {
    final project = repository.requireProject();
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id == editingSession.activeCutId) {
          return cut;
        }
      }
    }

    return null;
  }

  /// The active cut, THROWING when none is selected (gap state) — every
  /// caller is a conscious decision that a cut must exist here (UI-R9 #3
  /// audit rename; reach for [activeCutOrNull] on read paths instead).
  @override
  Cut get requireActiveCut {
    final cut = activeCutOrNull;
    if (cut == null) {
      throw StateError(
        'No active Cut (gap state): ${editingSession.activeCutId}',
      );
    }
    return cut;
  }

  // --- Camera --------------------------------------------------------------

  // ── the camera: its own object, in its own file ────────────────────────
  //
  // A collaborator (session/camera.dart). Callers name it —
  // `session.camera.cameraPoseAtCurrentFrame` (round 8, G4).
  late final Camera camera = Camera(
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    controllers: activeCutControllers,
    laneMove: laneMove,
    internals: this,
    activeCut: _activeCutEdits,
  );

  @override
  void updateActiveCutCameraTrack(
    TransformTrack track, {
    String description = 'Edit camera keyframes',
  }) => camera.updateActiveCutCameraTrack(track, description: description);
  GuideId? _selectedGuideId;

  /// Which guide the guide tool is editing.
  ///
  /// UI state, like the active layer — the CUT stores the guides, not which
  /// one is under the hand. It lives here rather than in a widget because
  /// two of them need it (the tool panels and the canvas overlay), and two
  /// copies of a selection are two answers waiting to disagree.
  GuideId? get selectedGuideId => _selectedGuideId;

  set selectedGuideId(GuideId? id) {
    if (_selectedGuideId == id) return;
    _selectedGuideId = id;
    notifyListeners();
  }

  // ── the editing canvas: its own object, in its own file ─────────────
  //
  // A collaborator (session/editing_canvas.dart): what the canvas draws at
  // the playhead and which cel the brush may touch in it — one subject,
  // because `layerAcceptsBrushInput` answers both. Callers name it: a
  // forwarder here would be a second name for the same verb (round 8, G4).
  late final EditingCanvas editingCanvas = EditingCanvas(
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    internals: this,
    controllers: activeCutControllers,
    opacityVerbs: opacityVerbs,
    trackSe: trackSe,
  );

  // ── the opacity verbs: their own object, in their own file ──────────
  //
  // A collaborator (session/opacity_verbs.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final OpacityVerbs opacityVerbs = OpacityVerbs(
    project: this,
    changes: this,
    controllers: activeCutControllers,
    transitions: transitions,
    internals: this,
  );

  // The frame verbs (Round 6): the playhead's frame and what stands there.
  late final FrameVerbs frameVerbs = FrameVerbs(
    project: this,
    selection: this,
    changes: this,
    frameIds: this,
    timeline: this,
    controllers: activeCutControllers,
    internals: this,
    renderCaches: renderCaches,
    projectSettings: projectSettings,
  );

  @override
  Frame? get selectedFrame => frameVerbs.selectedFrame;
  @override
  int get currentFrameIndex => frameVerbs.currentFrameIndex;
  /// The track that owns [cutId] — the V effects' home (R4: the transform
  /// lanes are TRACK data on the global axis, like the SE rows).
  @override
  Track? trackOwningCut(CutId cutId) =>
      cutPositionOf(repository.requireProject(), cutId)?.track;

  // `transformTrackForCut` retired with the V row's transform: every route
  // that asked for a track pose or fade now has neither to apply.

  // ── the effects and the fx switches: their own object ───────────────
  //
  // A collaborator (session/effects_and_fx.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final EffectsAndFx effectsAndFx = EffectsAndFx(
    project: this,
    selection: this,
    changes: this,
    internals: this,
    activeCut: _activeCutEdits,
  );

  // `activeCutCanvasPoseSample` retired with the V row's transform: there is
  // no track pose for the editing canvas or the scrub preview to apply.

  /// The drawable artwork of one layer frame in the active cut; `null` when
  /// nothing is drawn. This is the production [LayerFrameSurfaceResolver]
  /// for camera preview/export compositing and the canvas tools (eyedropper
  /// sample, fill compose). The store's display cache is consumed when
  /// valid (the editing coordinator donates the session surface on every
  /// commit/undo/redo); a cold rebuild replays the frame's paint commands
  /// ONCE and stores the result back as the new display cache — repeated
  /// tool taps must not replay the whole stroke history per tap (R11-②③).
  BitmapSurface? brushSurfaceForLayerFrame(Layer layer, Frame frame) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return null; // Gap state: no cut, no artwork.
    }
    final frameKey = BrushFrameKey(
      projectId: repository.requireProject().id,
      trackId: selectedTrackId,
      cutId: cut.id,
      layerId: layer.id,
      frameId: frame.id,
    );
    // R19 P3b: the baked raster is the truth — the resolver is a plain
    // reference read (valid display cache first, else baked). No replay
    // exists anymore.
    return renderCaches.brushFrameStore.currentSurfaceWithoutReplay(
      frameKey,
      canvasSize: cut.canvasSize,
    );
  }

  /// [layer]'s tight INK bounds at [frameIndex], in the layer's own
  /// artwork coordinates — what the canvas transform box frames (R5 #10:
  /// "레이어 그림의 바운드에 걸리는게 알기쉬울거같기도하고? 그렇게하자").
  /// Null while the row shows nothing there, or the cel is blank.
  ///
  /// Memoized on the surface INSTANCE, and that is not an optimisation but
  /// the condition of calling it at all: the scan reads every tile of the
  /// cel, and the box is framed from `build`. `BitmapSurface` is immutable
  /// with structural tile sharing, so identity is an exact key — a changed
  /// cel is always a new instance. The selection layer's own box learned
  /// this the hard way (`bitmap_surface_geometry.dart`'s note).
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  layerContentBoundsAt(Layer layer, int frameIndex) {
    final frame = resolveExposedFrameAt(layer, frameIndex);
    if (frame == null) {
      return null;
    }
    final surface = brushSurfaceForLayerFrame(layer, frame);
    if (surface == null) {
      return null;
    }
    if (identical(surface, _layerContentBoundsSurface)) {
      return _layerContentBoundsCached;
    }
    _layerContentBoundsSurface = surface;
    return _layerContentBoundsCached = bitmapSurfaceContentBounds(surface);
  }

  BitmapSurface? _layerContentBoundsSurface;
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  _layerContentBoundsCached;

  // `setCutFade` and `updateTrackTransformTrack` retired with the V row's
  // transform. The cut fade is F.I / F.O spans on the TRANSITION row now
  // ([updateTransitionInstructions]) — where the span's length IS the ramp,
  // and where two cuts overlapping across a boundary can carry different
  // values, which one opacity lane per track never could.

  /// Replaces [layerId]'s transform track (the AE Transform lanes on every
  /// drawing layer — applied at composite time, never baked); one undo
  /// step, no-op when unchanged.
  @override
  void updateLayerTransformTrack(
    LayerId layerId,
    TransformTrack track, {
    String description = 'Edit layer transform',
  }) {
    final cutId = editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    cutCommandCoordinator.updateLayerTransformTrack(
      cutId: cutId,
      layerId: layerId,
      transformTrack: track,
      description: description,
    );
    notifyListeners();
  }

  // ── the lane verbs: their own object, in their own file ─────────────
  //
  // A collaborator (session/lane_verbs.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final LaneVerbs laneVerbs = LaneVerbs(
    project: this,
    selection: this,
    timeline: this,
    controllers: activeCutControllers,
    effectsAndFx: effectsAndFx,
    internals: this,
  );

  @override
  bool resetLaneGroup(LayerId layerId, String headerLaneId) =>
      laneVerbs.resetLaneGroup(layerId, headerLaneId);
  // The single-key lane naming verbs (`laneKeyName`, `laneHasKeyAt`,
  // `currentLaneKeyAddress`, `setLaneKeyName`, `linkLaneKeyName`) retired
  // when the RANGE form arrived: a single key is the one-frame span at the
  // playhead, so `setLaneKeyNamesForSelection` covers both and leaving the
  // narrow pair here would only invite a future fix to land on the copy
  // nothing calls. The per-FAMILY pairs (`setEffectKeyName`,
  // `setTransformKeyName` and their links) followed on 2026-09-11 (F-84):
  // only tests still called them, and the transform one could never have
  // named a camera key.

  /// The layer's resolved transform pose at [frameIndex] (identity while
  /// the track is empty) — the lane value column and key-freeze source.
  @override
  TransformPose layerPoseAtFrame(Layer layer, int frameIndex) {
    return layer.transformTrack.resolveAt(
      frameIndex: frameIndex,
      orElse: () => layerIdentityPose(requireActiveCut.canvasSize),
    );
  }

  /// The layer's resolved anchor point at [frameIndex] — the anchor-point
  /// lane's value column and key-freeze source (canvas center while
  /// unkeyed).
  @override
  CanvasPoint layerAnchorPointAtFrame(Layer layer, int frameIndex) {
    return resolveLayerAnchorPointAt(layer: layer, frameIndex: frameIndex) ??
        CanvasPoint(
          x: requireActiveCut.canvasSize.width / 2,
          y: requireActiveCut.canvasSize.height / 2,
        );
  }

  /// The layer's animated Opacity sample (0..1; 1 while unkeyed) — the
  /// opacity lane's value column and key-freeze source.
  @override
  double layerOpacityAtFrame(Layer layer, int frameIndex) {
    return resolveOpacityTrackAt(layer.transformTrack.opacity, frameIndex);
  }

  // --- Layer FX switches (PERSISTED layer state, R8) -----------------------

  /// Writes one row's TRANSFORM switch; one undo step, no-op when unchanged.
  @override
  void updateLayerTransformEnabled(
    LayerId layerId, {
    required bool enabled,
    String description = 'Toggle transform FX',
  }) {
    final layer = effectsAndFx.fxSwitchLayerById(layerId);
    if (layer == null || layer.transformEnabled == enabled) {
      return;
    }
    historyManager.execute(
      UpdateLayerTransformEnabledCommand(
        repository: repository,
        layerId: layerId,
        transformEnabled: enabled,
        description: description,
      ),
    );
    notifyListeners(); // Not a structural cut edit — see [_setLayerFxSwitches].
  }

  // --- Visibility solo mode (session view state, not persisted) ------------

  // ── visibility solo: its own object, in its own file ───────────────────
  //
  // A collaborator (session/visibility_solo.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final VisibilitySolo visibilitySolo = VisibilitySolo(
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    controllers: activeCutControllers,
    internals: this,
  );

  // --- Cut display gates ---------------------------------------------------

  // --- V track display: the static opacity and the fx master (R9 #21) ----

  // --- The V row's EFFECT CHAIN (fx on the cut, not on one layer) --------
  //
  // A layer's chain filters that layer's picture; this one filters the whole
  // composited cut under the playhead (user 2026-08-08). It is TRACK data on
  // the GLOBAL axis, exactly like the pose and the fade beside it, so these
  // verbs take a TrackId and no cut is ever in the loop.

  /// The live V-row opacity drag (session-owned, per the drag-verb rule):
  /// per-move preview, ONE write on release.
  @override
  final ValueNotifier<({TrackId trackId, double opacity})?>
  trackOpacityDragPreview = ValueNotifier(null);

  /// Cuts whose PICTURE is hidden in the playback display — the storyboard
  /// V-row eye (R9). The paper stays, the composite doesn't draw. A working
  /// aid: the editing canvas, exports and thumbnails ignore it.
  final Set<CutId> _hiddenPictureCutIds = {};

  bool isCutPictureVisible(CutId cutId) =>
      !_hiddenPictureCutIds.contains(cutId);

  void toggleCutPictureVisibility(CutId cutId) {
    if (!_hiddenPictureCutIds.remove(cutId)) {
      _hiddenPictureCutIds.add(cutId);
      // UI-R13 #2: hiding the ACTIVE cut's picture is the no-cut state —
      // nothing displays at this index anymore, exactly like a gap
      // landing: park at the current global and deselect.
      if (cutId == editingSession.activeCutId) {
        gapGlobalFrame = editingGlobalFrame;
        _deselectActiveCutForGap();
        frameSeekCommitted.value += 1;
      }
      notifyListeners();
      return;
    }
    // Re-showing (UI-R14 #2): the symmetric restore — when the playhead
    // is parked ON the re-shown cut (the eye-off gap state), turning the
    // eye back on lands there again, exactly as if the position were
    // clicked. Without this the picture only returned in playback while
    // the editing view stayed in the void.
    final parked = gapGlobalFrame;
    if (parked != null &&
        editingSession.activeCutId == null &&
        trackFrameAxis().ownerOf(parked)?.cutId == cutId) {
      selectGlobalFrame(parked);
      return; // selectGlobalFrame notifies.
    }
    notifyListeners();
  }

  /// Steps history and puts the session back where the new layer list says
  /// it should be.
  ///
  /// ⛔[undo] and [redo] were eighteen identical lines apart from which way
  /// the history moved. The rule of three usually holds a pair apart, and
  /// its reason — that a hasty merge leaves one flag answering two
  /// questions — does not apply here: the difference becomes the ARGUMENT,
  /// so there is no flag and nothing to read twice.
  void _stepHistory(void Function() move) {
    final documentBefore = repository.currentProject;
    final beforeLayers = List<Layer>.of(
      activeCutOrNull?.layers ?? const <Layer>[],
    );
    final previousActiveLayerId =
        activeCutControllers.layerController.activeLayerId;
    final previousFrameIndex =
        activeCutControllers.timelineController.currentFrameIndex;

    move();
    // 🚨★★★**THE TIDY-UP FOLLOWS THE DOCUMENT, NOT THE KEYPRESS.** Every
    // step used to run [refreshAfterCutCommand] — which DROPS THE COPIED
    // FRAME and CLEARS THE FRAME-RANGE SELECTION, rebuilds the cut
    // controllers and wakes every session listener. That is what a CUT
    // command owes. Pressing Ctrl+Z after a brush stroke owes none of it,
    // and paid all of it: the user's clipboard and their band went away
    // because of an edit that moved no row.
    //
    // ⚠️And the forward direction never did this. `HistoryManager`'s own
    // doc says 「brush strokes execute here WITHOUT a session notify, so
    // nothing else would ever tell them a stroke landed」 — the buttons
    // subscribe to the history, the canvas repaints off the invalidation
    // the commit sends. Undo is the same edit run backwards and owed the
    // same silence; it was the one direction that shouted.
    //
    // 🔬**THE WHOLE FAMILY, not the symptom.** Of the 53 command classes
    // that enter history, exactly five never touch the repository:
    // `BrushStrokeHistoryCommand`, `BrushLiftMoveHistoryCommand`,
    // `CelPixelOverwriteCommand`, `ToggleIdInSetCommand` and
    // `RekeyBrushFramesCommand` — and the last is only ever composed INTO a
    // step that also moves layers, so its group does move the document and
    // does get the tidy-up. One question answers all five.
    //
    // ⚠️`identical` on the PROJECT is that question exactly, not a proxy
    // for it: `ProjectRepository` swaps the whole immutable project on
    // every structural edit ([ProjectRepository.replaceProject],
    // [ProjectRepository.updateProject]), and the five above write the
    // brush store or a `ValueNotifier` instead. Unchanged identity means no
    // cut, layer, frame or attribute moved — so the layer-preference walk
    // has nothing to prefer and the controller rebuild nothing to rebuild.
    //
    // ⛔**IT IS NOT A PERFORMANCE FIX, and was measured not to be one.**
    // Written while chasing H30 (유저 실기 2026-09-10: 「그리다가 언두하고
    // 빠르게 다음 스트로크 그리면 렉이 심하거든?」) on the theory that this
    // notify was the hitch. With this early return in place that stroke
    // still dirties 33 `LayoutBuilder`s against a control's 12 and still
    // paints 2011 render objects against 877 — unchanged to the object.
    // H30 has its own card and its own benchmark.
    if (identical(documentBefore, repository.currentProject)) {
      return;
    }
    final preferredLayerId = preferredLayerAfterLayerListChange(
      beforeLayers: beforeLayers,
      afterLayers: activeCutOrNull?.layers ?? const <Layer>[],
      previousActiveLayerId: previousActiveLayerId,
    );
    refreshAfterCutCommand(
      preferredActiveLayerId: preferredLayerId,
      preferredFrameIndex: previousFrameIndex,
    );
    notifyListeners();
  }

  /// ⚠️Through [historyPictures], never straight to the history: a step
  /// whose pictures are not ready yet waits for them instead of showing a
  /// blank frame.
  void undo() => historyPictures.step(
    undo: true,
    apply: () => _stepHistory(historyManager.undo),
  );

  void redo() => historyPictures.step(
    undo: false,
    apply: () => _stepHistory(historyManager.redo),
  );

  // --- Layer state / commands --------------------------------------------

  @override
  List<Layer> get layers => activeCutControllers.layerController.layers;
  @override
  LayerId? get activeLayerId =>
      activeCutControllers.layerController.activeLayerId;
  @override
  Layer? get activeLayer => activeCutControllers.layerController.activeLayer;

  // ── folders and attachments: their own object ───────────────────────
  //
  // A collaborator (session/folders_and_attachments.dart): the folder and
  // attach VERBS — grouping, dissolving, mounting, the 어태치 해제 and the
  // fold twirl — with the state each one reads.
  late final FoldersAndAttachments folders = FoldersAndAttachments(project: this, selection: this, changes: this, controllers: activeCutControllers, rowSelectionVerbs: rowSelectionVerbs, layerIds: layerIds, activeCut: _activeCutEdits);

  // The layer switches (Round 6): eye, mute, audio, blend mode, target kind.
  late final LayerSwitchVerbs layerSwitches = LayerSwitchVerbs(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, storyboardCursor: storyboardCursor, internals: this);

  /// AUDIO-PRO R3: mid-run schedule refresh, fired by the history
  /// listener and by the repo-direct mix edits (mute/fader/pan/solo,
  /// which bypass history).
  @override
  void refreshLiveAudioSchedule() {
    if (playbackRig.audioDeviceTransport.carryingPlayback) {
      playbackRig.audioDeviceTransport.refreshSchedule();
    }
  }

  // --- Folders ---------------------------------------------------------------
  //
  // A folder is a LAYER. Everything a folder does that a layer already does
  // — select, rename, eye, static opacity, blend, fx switch, FX lanes,
  // mark, delete — rides the layer API above; the nine folder-shaped
  // methods that used to live here are gone. What is left is the two
  // structural verbs (make one, take one apart) and the twirl.

  // --- The row-order DRAG ------------------------------------------------
  //
  // R5 #5: the STEP verbs that used to sit here are gone — menu entries,
  // session methods and all, with no shortcut left behind (user: "삭제해.
  // 단축키로도 남기지마 일단"). The drag is the whole answer now.
  //
  // What the step could reach and a caret cannot — the inside of an EMPTY
  // folder — is R5 #15's drop-ON-a-row instead, which is a better answer
  // anyway: it says the intent out loud rather than arriving there by
  // counting rows.
  //
  // The commit path they shared did not go with them. `layer_stack_move_test`
  // drives it through the drag now: a run travelling whole, the 겸용
  // mirroring, one drag one undo, a refused landing committing nothing.
  //
  // The caret has to SAY when a drop does something structural, because a
  // folder joined in silence is a change nobody asked for.

  /// A tick the rails watch to bring the SELECTION back into view (user,
  /// 2026-08-09: walking rows and frames with the arrow keys kept selecting
  /// things that were off screen).
  ///
  /// A tick rather than a value, and a notifier rather than a session
  /// notify: what to reveal is already readable — the current row and the
  /// current frame — so the only thing that has to travel is "now". Every
  /// surface answers it in its own geometry, which is the only way one
  /// signal can serve a rail that runs down, a sheet that runs across, and
  /// a storyboard on a global axis.
  ///
  /// ⚠️Deliberately NOT fired by every selection change. A cell tap already
  /// puts the thing under your finger, and the playhead moves every frame
  /// of playback — revealing on those would yank the view out from under
  /// the hand that put it there. It fires where the selection moves without
  /// the pointer: the arrow keys.
  @override
  final ValueNotifier<int> revealSelectionTick = ValueNotifier<int>(0);

  // ── the layer row drag: its own object, in its own file ─────────────
  //
  // A collaborator (session/layer_row_drag.dart): the row picked up in the
  // rail and where it may land — on a row, a track or an effect lane.
  late final LayerRowDrag layerRowDragVerbs = LayerRowDrag(project: this, changes: this, effectsAndFx: effectsAndFx, rowSelectionVerbs: rowSelectionVerbs, trackSe: trackSe, internals: this);

  /// The channel the workspace listens on when a drop wants a yes/no.
  ///
  /// 🚨Owned here rather than by a surface: TWO of them end a row drag, and
  /// a dialog raised by whichever happened to be on screen is a second copy
  /// of the sentence waiting to drift ([AttachFxConfirmController]).
  @override
  final AttachFxConfirmController attachFxConfirm = AttachFxConfirmController();

  // --- SE mix controls (AUDIO-PRO R1) ---------------------------------------

  /// The solo set — pure MONITORING state (never persisted, never
  /// exported): non-empty narrows playback/scrub to these SE rows.
  @override
  final ValueNotifier<Set<LayerId>> soloedSeLayerIds =
      ValueNotifier<Set<LayerId>>(const {});

  // --- Opacity drag preview (R4 #4/#6) ------------------------------------

  /// Live opacity-drag preview: per-move values ride this notifier into
  /// the editing canvas only (the dragged FieldSlider echoes locally)
  /// WITHOUT a session notify — the old per-move repo write rebuilt every
  /// panel per pointer move and made the slider feel heavy. Release
  /// commits ONE write + notify. The legend's master bar previews a SET of
  /// rows through the same channel.
  @override
  final ValueNotifier<({Set<LayerId> layerIds, double opacity})?>
  opacityDragPreview = ValueNotifier(null);

  /// The master bar's LAST committed value — the bar rests on this, not a
  /// live average (UI-R6 #2).
  @override
  double lastMasterOpacity = 1.0;

  /// Project-level sheet-header text (title/episode/artist) the timesheet
  /// document reads.
  TimesheetInfo get timesheetInfo => repository.requireProject().timesheetInfo;

  /// One undo step; no-op when unchanged.
  void updateTimesheetInfo(TimesheetInfo info) {
    cutCommandCoordinator.setTimesheetInfo(info);
    notifyListeners();
  }

  // ── the layer marks: their own object, in their own file ────────────
  //
  // A collaborator (session/layer_marks.dart): the ● a row wears at a
  // frame — one row or every swept one.
  late final LayerMarks layerMarks = LayerMarks(project: this, selection: this, changes: this, controllers: activeCutControllers, activeCut: _activeCutEdits);

  // ── the instructions: their own object, in their own file ───────────
  //
  // A collaborator (session/instructions.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final Instructions instructionVerbs = Instructions(
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    controllers: activeCutControllers,
    cutVerbs: cutVerbs,
    camera: camera,
    activeCut: _activeCutEdits,
  );

  // ---------------------------------------------------------------------
  // The TRANSITION row (O.L / F.I / F.O). Same spans, same dialog, same
  // grips as a cut's direction row — the differences are that the frames
  // are GLOBAL and the vocabulary is filtered to the 場面転換 terms.
  // ---------------------------------------------------------------------

  // --- The transition row's edge drags -------------------------------------
  //
  // The drag itself is [TransitionEdgeDrag] — the pilot [EditorDragSession]:
  // the gesture's state lives on a per-drag object, and the session keeps
  // only WHICH drag is live. These verbs are the session's unchanged face.

  // ── the edge drags: their own object, in their own file ─────────────────
  //
  // The second collaborator (session/edge_drag.dart): the exposure, cut
  // and transition edge drags with their snapshots. Callers name it
  // (round 8, G4).
  late final EdgeDragVerbs edgeDrag = EdgeDragVerbs(
    project: this,
    selection: this,
    changes: this,
    controllers: activeCutControllers,
    folders: folders,
    rangeSelections: rangeSelections,
    storyboardCursor: storyboardCursor,
    trackSe: trackSe,
    transitions: transitions,
    exposureVerbs: exposureVerbs,
    internals: this,
  );

  /// The transition row as the in-flight edge drag would leave it — the
  /// strip renders THIS while a grip is held, so the mark follows the hand
  /// instead of jumping on release. Null when no drag is in flight.
  @override
  final ValueNotifier<Layer?> transitionEdgeDragPreview = ValueNotifier(null);

  // --- Media import (R3b): stills, GIF sequences, cut folders -------------

  // ── the landing and the file doors: their own objects ────────────────
  //
  // Collaborators (session/import_landing.dart,
  // session/project_import_doors.dart). The destination GATE is the
  // landing's: image, PSD and PDF each carried a copy of it, and a copy
  // of a gate is a chance for one of them to slip behind a decode.
  late final ImportLanding importLanding = ImportLanding(
    project: this,
    selection: this,
    frameIds: this,
    timeline: this,
    layerIds: layerIds,
  );

  late final ProjectImportDoors importDoors = ProjectImportDoors(
    project: this,
    changes: this,
    internals: this,
    renderCaches: renderCaches,
    landing: importLanding,
    fingerprints: mediaFingerprints,
  );

  late final CutFolderImportDoor cutFolderDoor = CutFolderImportDoor(
    project: this,
    selection: this,
    changes: this,
    internals: this,
    renderCaches: renderCaches,
    timeline: this,
    landing: importLanding,
    staging: mediaStagingStore,
  );

  // The TVPaint door (session/tvpp_import_door.dart). A .tvpp opens AS A
  // PROJECT — it holds several cuts — so unlike its sibling doors it
  // replaces the session's project the way an .anicel open does, and its
  // constructor lists that: the reset touches the clipboards, the
  // controllers and the file record, not just the landing.
  late final TvppImportDoor tvppDoor = TvppImportDoor(
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    internals: this,
    renderCaches: renderCaches,
    landing: importLanding,
    controllers: activeCutControllers,
    playbackRig: playbackRig,
    file: projectFile,
    projectDoor: projectDoor,
    mediaPool: mediaPool,
    clipboard: clipboard,
    layerClipboard: layerClipboard,
    frameSeekCommitted: frameSeekCommitted,
  );

  // --- Text cel bake sweep (R5, §6-s) --------------------------------------
  //
  // A text cel's truth is [Frame.textContent]; the raster every consumer
  // composites is a PROJECTION baked into the ordinary cel store (the
  // import-cel grammar). Every mutation path that can move the truth —
  // edit, undo/redo, paste, duplicate, link merge, selection fills —
  // funnels through the history manager, so ONE listener re-renders
  // whatever projection went stale. Self-healing, no per-command hooks.

  // ── the text-cel bakes: their own sweep, in their own file ─────────────
  //
  // A collaborator (session/text_cel_bakes.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final TextCelBakes textCelBakes = TextCelBakes(
    project: this,
    selection: this,
    changes: this,
    controllers: activeCutControllers,
    internals: this,
    renderCaches: renderCaches,
  );

  @override
  bool disposed = false;

  // --- Voice recording, ADR, input meter, take preview ----------------------
  //
  // The section moved to [EditorVoiceRecording]. Unlike the settings block,
  // it did not come free: its constructor there lists the nineteen session
  // members it reads back, which is what this block's coupling actually is.
  //
  // ⛔The twenty-one forwarders that used to stand here are gone (G3,
  // 2026-09-07): callers say `session.voiceRecording.x`. Two names for one
  // verb is two names.
  //
  // `late` because the closures below read `this`; the consequence is that a
  // session nobody recorded on builds this at `dispose` just to dispose it.
  // That is deliberate and harmless — every line of its `dispose` is a
  // null-guarded no-op on an object that never ran.
  late final EditorVoiceRecording voiceRecording = EditorVoiceRecording(
    playback: () => playbackRig.playback,
    audioDeviceTransport: () => playbackRig.audioDeviceTransport,
    audioConformStore: () => audioConformStore,
    audioSyncSettings: () => appSettings.audioSyncSettings,
    repository: () => repository,
    cutCommandCoordinator: () => cutCommandCoordinator,
    uiStrings: () => uiStrings,
    projectFrameRate: () => projectSettings.projectFrameRate,
    activeCutGlobalStartFrame: () => activeCutGlobalStartFrame,
    editingGlobalFrame: () => editingGlobalFrame,
    gapParkedGlobalFrame: () => gapParkedGlobalFrame,
    activeLayerId: () => activeLayerId,
    trackSeGlobalLayerById: trackSeGlobalLayerById,
    mintFrameId: mintFrameId,
    mediaAssets: () => mediaPool.mediaAssets,
    rememberMediaFingerprint: mediaFingerprints.rememberMediaFingerprint,
    staging: mediaStagingStore,
    frameRangeSelection: () => frameRangeSelection,
    notify: notifyListeners,
  );
  @override
  FrameId mintFrameId(LayerId layerId) {
    _frameSequence += 1;
    return FrameId(nextFrameId(layerId));
  }

  @override
  Layer? get targetLayerForKindToggle => activeLayer;

  // ── the storyboard cursor: its own object, in its own file ──────────
  //
  // A collaborator (session/storyboard_cursor.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final StoryboardCursor storyboardCursor = StoryboardCursor(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, rangeSelections: rangeSelections, cells: cells, cutVerbs: cutVerbs, transitions: transitions, internals: this);

  // --- Frame / cell state / commands -------------------------------------

  // ── the exposure verbs: their own object, in their own file ─────────
  //
  // A collaborator (session/exposure_verbs.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final ExposureVerbs exposureVerbs = ExposureVerbs(
    selection: this,
    changes: this,
    controllers: activeCutControllers,
    camera: camera,
    rangeSelections: rangeSelections,
    cells: cells,
  );

  @override
  TimelineCellExposureState exposureStateForLayer(
    Layer layer,
    int frameIndex,
  ) => exposureVerbs.exposureStateForLayer(layer, frameIndex);
  void createDrawingAtCurrentFrame() {
    final layer = activeLayer;
    if (layer == null || !frameVerbs.canCreateDrawingAtCurrentFrame) {
      return;
    }

    _frameSequence += 1;
    activeCutControllers.timelineController.createDrawingFrameForLayer(
      layerId: layer.id,
      frameId: FrameId(nextFrameId(layer.id)),
    );
    notifyListeners();
  }

  // ── the auto frame for a stroke: its own object ─────────────────────
  //
  // A collaborator (session/auto_frame_for_stroke.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final AutoFrameForStroke autoFrame = AutoFrameForStroke(
    project: this,
    selection: this,
    changes: this,
    frameIds: this,
    controllers: activeCutControllers,
    frameVerbs: frameVerbs,
  );

  // ── the cell instances: their own object, in their own file ─────────
  //
  // A collaborator (session/cell_instances.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final CellInstances cellInstances = CellInstances(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, camera: camera, instructionVerbs: instructionVerbs, laneVerbs: laneVerbs, layerVerbs: layerVerbs, trackSe: trackSe, cells: cells, frameVerbs: frameVerbs, internals: this);

  @override
  bool get canCreateInstance => cellInstances.canCreateInstance;
  /// The selection range's maximal EMPTY runs on [layer]'s timeline.
  ///
  /// D20 (2026-08-18) rewrote the coverage half: GHOST coverage is
  /// authoring room — 「고스트일 뿐이니 생성 허용」 — the same sentence
  /// [TimelineController.canCreateDrawingAt] reads, so the single-cell
  /// verb and the range verb cannot answer "is this cell free"
  /// differently. (The old comment here said the opposite: "ghost
  /// coverage counts as covered".) A range over a repeat/hold tail
  /// therefore fills the projected cells with authored ones, and the
  /// rederive pass re-clamps the projection around them.
  @override
  List<({int startIndex, int length})> emptyGapsInRange(
    Layer layer,
    TimelineFrameRangeSelection selection,
  ) => emptyGapsBetween(
    layer,
    selection.startIndex,
    selection.endIndexExclusive,
  );

  /// ⚠️Formats an id from the CURRENT sequence — it does not advance it.
  /// Call [mintFrameId] unless you have just incremented `_frameSequence`
  /// yourself. The wall clock in here is decoration, not identity: its
  /// resolution on Windows is coarser than a tight mint loop, so two ids
  /// made in the same tick are equal, and equal frame ids are ONE drawing.
  @override
  String nextFrameId(LayerId layerId) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return 'ui-frame-${layerId.value}-$timestamp-$_frameSequence';
  }

  // --- Comma edge drag ------------------------------------------------------
  //
  // A drag previews live by recomputing the shifted layer from the drag-start
  // snapshot with the CUMULATIVE frame delta (idempotent — no per-step
  // accounting) and publishing it on [dragPreview]; releasing commits the
  // before→after pair as ONE undoable command. The repository and the
  // session listeners stay untouched until the release — a step rebuilds
  // only the preview consumers (the dragged row's gate, the cursor
  // overlay, the storyboard strips), never the panels (R5-⑧ generalized).

  /// The scoped edit-drag preview channel (exposure commas + cut trims).
  /// Value-only: per-step updates never fire a session notify.
  @override
  final ValueNotifier<TimelineDragPreview?> dragPreview =
      ValueNotifier<TimelineDragPreview?>(null);

  // --- Storyboard cut-trim edge drags --------------------------------------

  // Fade durability (W4) retired by R4: the fade keys live on the TRACK's
  // global axis now — a cut trim is a cut edit and moves no keys (the
  // user's independence rule, the SE precedent's sentence).

  // --- Movie-end drag (UI-R20 #3) -------------------------------------------

  // ── the movie-end drag: its own object, in its own file ────────────────
  //
  // A collaborator (session/movie_end_drag.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final MovieEndDragVerbs movieEnd = MovieEndDragVerbs(
    project: this,
    changes: this,
    internals: this,
  );

  // --- Storyboard cut RANGE selection (UI-R18 #1, O2c) ----------------------

  /// THE storyboard's selection: a frame RANGE on the track's global axis.
  ///
  /// The cut row used to carry a selection model of its own — a list of cut
  /// ids — which is what made "cut axis" a second domain next to the frame
  /// axis. It is one axis: a cut is a long block on the cut row, the snap
  /// expands a dragged range to whole blocks, and "these cuts" is what
  /// falls out ([StoryboardRows.storyboardSelectedCutIds]). Value-only view
  /// state; a plain tap clears it.
  @override
  final ValueNotifier<TrackFrameRangeSelection?> trackFrameRangeSelection =
      ValueNotifier<TrackFrameRangeSelection?>(null);

  /// The global frame axis of ONE track (the selected track's is
  /// [trackFrameAxis]).
  @override
  TrackFrameAxis axisForTrack(TrackId trackId) => TrackFrameAxis([
    for (final entry in buildStoryboardTimelineLayout(
      repository.requireProject(),
    ))
      if (entry.trackId == trackId) entry,
  ]);

  @override
  Track? trackById(TrackId trackId) {
    for (final track in repository.requireProject().tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  // --- Storyboard cut-block MOVE drags (R10-④) ----------------------------

  // The cut move drag (Round 6): begun, moved, ended or cancelled.
  late final CutMoveDragVerbs cutMove = CutMoveDragVerbs(
    project: this,
    selection: this,
    changes: this,
    storyboardRows: storyboardRows,
    internals: this,
  );

  // --- Whole-block move drags (R10-④b) --------------------------------------
  //
  // Grabbing a drawing block's BODY moves the block whole: along the frame
  // axis (slide) and across drawing layers (the cel travels, its brush
  // drawings re-keyed to the new layer). Landing requires empty space —
  // a block move never retimes other blocks. Same channel discipline as
  // the edge drags: repo untouched until release, one undo per drag.

  /// The drag in flight, or null. ⛔The only thing this class keeps about a
  /// block move now: its mid-drag state lives on the object and dies with
  /// the gesture (see [DrawingBlockMoveDrag]).
  @override
  DrawingBlockMoveDrag? blockMoveDrag;

  bool get isBlockMoveDragActive => blockMoveDrag != null;

  /// Whether [layerId] can take part in a block move (source or target):
  /// a plain drawing-section layer. Track-SE rows live on the global axis
  /// with audio attached; the rest of the standing-down is the shared
  /// retime law ([standsDownFromRetime]).
  @override
  bool blockMoveEligible(LayerId layerId) {
    // FREE attach rows move blocks like any drawing layer (UI-R21 #3) —
    // only the SYNCED ones stand down, which the shared law knows.
    if (standsDownFromRetime(layerId) || isTrackSeLayerId(layerId)) {
      return false;
    }
    final layer = layerById(layerId);
    return layer != null &&
        layer.kind.holdsDrawings &&
        layer.kind != LayerKind.se;
  }

  // ── the shove: its own object, in its own file ────────────────────────
  //
  // Push and pull, aimed at whatever is selected (session/block_shift.dart):
  // the frame-axis scope, its axis translation, the slack and the commit,
  // plus the aim that hands a cut selection to [cutShift] instead.
  late final BlockShift blockShift = BlockShift(
    project: this,
    selection: this,
    changes: this,
    internals: this,
    controllers: activeCutControllers,
    cutShift: cutShift,
  );

  // ── the cut-axis shove: its own object, in its own file ───────────────
  //
  // Push and pull on the CUT row (session/cut_shift.dart): the scope, the
  // slack, and the one commit that slides the anchor cut and everything
  // after it.
  late final CutShift cutShift = CutShift(
    project: this,
    changes: this,
    storyboardRows: storyboardRows,
  );

  // --- Frame RANGE selection (UI-R8, TVP-style) ----------------------------

  /// The selected frame range — ONE layer's [start,end) span snapped to
  /// whole exposure blocks. Value-only view state (drag moves never fire a
  /// session notify); cleared on layer/cut switches and plain cell taps.
  @override
  final ValueNotifier<TimelineFrameRangeSelection?> frameRangeSelection =
      ValueNotifier<TimelineFrameRangeSelection?>(null);

  /// The selected LANE range (UI-R23 #3 part 2): one (layer, lane)'s raw
  /// [start,end) span — the transform lanes' own selection domain,
  /// independent of (and mutually exclusive with) [frameRangeSelection].
  @override
  final ValueNotifier<TimelineLaneSelection?> laneRangeSelection =
      ValueNotifier<TimelineLaneSelection?>(null);

  /// [laneRangeSelection] as the CUT's timeline keys it.
  ///
  /// ★The display half of the global-master rule (user, 2026-08-09:
  /// **"글로벌 트랙이 메인이고 컷 타임라인 내부에서는 그걸 알기 쉽게
  /// 보여주기만 할 뿐"**). A track-SE row's span is stated on the track's
  /// global axis; a cut panel shows the part that falls inside its own
  /// window, on its own axis, and nothing when they do not overlap — the
  /// selection is still there, this cut just is not looking at it.
  /// Everything else passes straight through: only track-owned rows have
  /// two axes to be on.
  final ValueNotifier<TimelineLaneSelection?> cutLocalLaneRangeSelection =
      ValueNotifier<TimelineLaneSelection?>(null);

  void _publishCutLocalLaneRange() {
    if (disposed) {
      return;
    }
    final span = laneRangeSelection.value;
    if (span == null || !isTrackSeLayerId(span.layerId)) {
      cutLocalLaneRangeSelection.value = span;
      return;
    }
    final offset = activeCutGlobalStartFrame;
    final start = math.max(span.startIndex, offset);
    final end = math.min(
      span.endIndexExclusive,
      offset + activeCutSpan.activeCutPlaybackFrameCount,
    );
    cutLocalLaneRangeSelection.value = end <= start
        ? null
        : TimelineLaneSelection(
            layerId: span.layerId,
            laneId: span.laneId,
            startIndex: start - offset,
            endIndexExclusive: end - offset,
            laneIds: span.laneIds,
          );
  }

  // ── the lane range move drag: its own object, in its own file ───────
  //
  // A collaborator (session/lane_range_move_drag.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final LaneRangeMoveDragVerbs laneMove = LaneRangeMoveDragVerbs(
    project: this,
    selection: this,
    changes: this,
    laneVerbs: laneVerbs,
    effectsAndFx: effectsAndFx,
    internals: this,
  );

  /// The layer a RANGE selection reads (cut-local DISPLAY indexes): cut
  /// layers as-is, track-SE rows as their display clones.
  @override
  Layer? rangeLayerById(LayerId layerId) {
    final cutLayer = layerById(layerId);
    if (cutLayer != null) {
      return cutLayer;
    }
    if (!isTrackSeLayerId(layerId)) {
      return null;
    }
    final global = trackSeGlobalLayerById(layerId);
    return global == null ? null : trackSeWindow.displayLayer(global);
  }

  /// Maps a DISPLAY block start to the layer's COMMIT form key: identity
  /// for cut layers; the global-axis start for track-SE rows.
  @override
  int commitBlockStart(LayerId layerId, int displayStart) {
    if (!isTrackSeLayerId(layerId)) {
      return displayStart;
    }
    final global = trackSeGlobalLayerById(layerId);
    if (global == null) {
      return displayStart;
    }
    return trackSeWindow.globalBlockStartFor(global, displayStart);
  }

  /// The layer ops COMMIT against: the GLOBAL form for track-SE rows.
  @override
  Layer? commitLayerById(LayerId layerId) => isTrackSeLayerId(layerId)
      ? trackSeGlobalLayerById(layerId)
      : layerById(layerId);

  // ── the drawing block move drag: its own object ─────────────────────
  //
  // A collaborator (session/drawing_block_move_drag.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final DrawingBlockMoveDragVerbs drawingBlockMove = DrawingBlockMoveDragVerbs(project: this, changes: this, controllers: activeCutControllers, folders: folders, renderCaches: renderCaches, internals: this);

  // --- Frame RANGE move drag (UI-R8: drag the selected range) --------------

  // ── the frame-range move drag: its own object, in its own file ────────
  //
  // The first collaborator carved out of this class (2026-09-02, the audit's
  // SRP cut): the verbs live in `FrameRangeMoveDragVerbs`
  // (session/frame_range_move_drag.dart) and one gesture's state lives in
  // the `FrameRangeMoveDrag` its factory returns (session/drags/). Callers
  // name it — a forwarder here would be a second name for the same verb
  // (round 8, G4).
  late final FrameRangeMoveDragVerbs rangeMove = FrameRangeMoveDragVerbs(
    project: this,
    selection: this,
    changes: this,
    controllers: activeCutControllers,
    camera: camera,
    folders: folders,
    rangeSelections: rangeSelections,
    rowSpans: rowSpans,
    blockMove: drawingBlockMove,
    transitions: transitions,
    trackSe: trackSe,
    internals: this,
    renderCaches: renderCaches,
  );

  /// The door a collaborator announces through — `notifyListeners` is
  /// protected, and a collaborator is not a subclass.
  @override
  void notifyChanged() => notifyListeners();

  // --- Run-edge NEW FRAMES drag (UI-R8 [+] handle) --------------------------

  // ── the run frames add drag: its own object ─────────────────────────
  //
  // A collaborator (session/run_frames_add_drag.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final RunFramesAddDragVerbs runFramesAdd = RunFramesAddDragVerbs(
    project: this,
    changes: this,
    controllers: activeCutControllers,
    internals: this,
  );

  // --- Run-edge properties (UI-R9 #10 N/H/R tags) ----------------------------

  /// The run-behavior fill boundary (hold/repeat edges fill to the cut
  /// end); zero without a cut.
  @override
  int get activeCutFrameCount => activeCutOrNull?.duration ?? 0;

  /// Whether the live frame-range selection can SCOPE a repeat pattern on
  /// this run edge (UI-R10 #5 rules: the selection must cover the edge
  /// block and cut the run short of the other end) — the tag flyout shows
  /// its explicit "Repeat selection" entry from this (UI-R19 #2).
  bool canScopeRepeatToSelection({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineRunEdgeSide side,
  }) {
    final layer = layerById(layerId);
    if (layer == null) {
      return false;
    }
    final run = gluedRunAt(layer, blockStartIndex);
    final selection = frameRangeSelection.value;
    if (run == null || selection == null || selection.layerId != layerId) {
      return false;
    }
    if (side == TimelineRunEdgeSide.end) {
      return selection.contains(run.endIndexExclusive - 1) &&
          selection.startIndex > run.startIndex;
    }
    return selection.contains(run.startIndex) &&
        selection.endIndexExclusive < run.endIndexExclusive;
  }

  @override
  Layer? layerById(LayerId layerId) {
    for (final layer in layers) {
      if (layer.id == layerId) {
        return layer;
      }
    }
    return null;
  }

  /// Whether a RESHAPING verb — bulk retime, range move, push/pull, comma
  /// set, X-here — must stand [layerId] down, because the row's timing is
  /// not its own to move.
  ///
  /// ⛔ONE ANSWER FOR FIVE ASKS (the audit's clone scan, 2026-09-04; the
  /// range-selection gate below already called the others "the three
  /// downstream copies of this filter"). SYNCED attach rows follow their
  /// base by DERIVATION, so committing their display clone would write the
  /// derived timeline onto the stored-empty row. SINGLE-CEL (image) rows
  /// have their one covering block pinned by the write normalization, so a
  /// verb would PREVIEW the stretch and have the same write snap it back —
  /// the move-then-revert flicker the project bans outright.
  ///
  /// Both are ID-gated: the synced-block UI stopped marking mirror entries
  /// ghost, so the non-ghost block scans downstream no longer exclude them.
  @override
  bool standsDownFromRetime(LayerId layerId) =>
      folders.isSyncedAttachedLayerId(layerId) || rowSpans.isSingleCelLayerId(layerId);

  /// 🚨★★★ THE ONE DELETE — 유저 확정 2026-08-12 (⑰): 「딜리트버튼, 슬 통일하고싶음.
  /// 버튼 그냥 하나로. 기본적으로 누르면 액티브레이어의 현재 프레임블록 삭제하고,
  /// 물론 선택범위로 선택하고 삭제가능. 그리고 레이어 선택하고 누르면 레이어삭제.
  /// 물론 여러개도가능. 컷도 마찬가지로 컷 선택하고 삭제버튼누르면 컷 삭제.」
  ///
  /// ★The verb does not ask WHICH BUTTON was pressed — it asks **what is
  /// selected**, in the order the user gave. Delete lived in three separate
  /// places before this (the cut menu, the layer menu, a loose layer button),
  /// each hard-wired to one noun, which is why the same word did different
  /// things depending on where you reached for it.
  @override
  DeleteSubject get deleteSubject => deleteSubjectFor(cutsAreThisPanels: true);

  /// [deleteSubject], asked of a PANEL — see [editInstanceSubjectFor] for
  /// why the cuts rung is a question and not a given (R5q1).
  DeleteSubject deleteSubjectFor({required bool cutsAreThisPanels}) {
    if (cutsAreThisPanels && trackFrameRangeSelection.value != null) {
      return DeleteSubject.cuts;
    }
    // ⑨: rows outrank cells. A row selection is the more specific statement
    // — you named the rows out loud — while the cell rung answers from where
    // the playhead happens to stand.
    if (layerVerbs.deletableSelectedLayerIds().isNotEmpty) {
      return DeleteSubject.layers;
    }
    return cells.canDeleteCellAtCurrentFrame
        ? DeleteSubject.cells
        : DeleteSubject.nothing;
  }

  /// Runs whatever [deleteSubject] names. One undo step either way — the cell
  /// path already composes its own.
  void deleteSelectionSubject({bool cutsAreThisPanels = true}) {
    switch (deleteSubjectFor(cutsAreThisPanels: cutsAreThisPanels)) {
      case DeleteSubject.cuts:
        cutVerbs.deleteActiveCut();
      case DeleteSubject.layers:
        layerVerbs.deleteSelectedLayers();
      case DeleteSubject.cells:
        cells.deleteCellAtCurrentFrame();
      case DeleteSubject.nothing:
        break;
    }
  }

  /// Whether a live band names rows this press would MISS.
  ///
  /// The ACTIVE-ROW verbs — X-here, the ● mark, the cell rename and
  /// 잘라내기 — all resolve against the active layer. A band covering that
  /// row is served: 잘라내기 splices exactly the swept span
  /// ([FrameClipboard.spliceRunOnActiveRow]), and the playhead verbs act on the row the
  /// user highlighted. A band naming only OTHER rows is a different
  /// statement, and acting on the active row then edits something the
  /// user never swept while the highlight sits elsewhere explaining
  /// nothing — which for 잘라내기 means silently lifting a whole block.
  ///
  /// ⚠️Two wrong versions of this came first, and both are worth keeping
  /// in view. "A band is up AND holds nothing" is the DELETE ladder's
  /// test, and delete has a rung these verbs do not, so it let a band
  /// naming other rows straight through. Plain "a band is up" then broke
  /// 잘라내기's own documented use — 범위 선택 후 잘라내기 — because that
  /// band DOES cover the active row. The axis is neither the band's
  /// contents nor its mere existence: it is whether the band names the
  /// row this press would land on.
  ///
  /// 🔜Open design question for the user (board R8-c): X, the mark and
  /// the rename could instead LEARN a band rung and act on every swept
  /// block the way Delete and the comma do. Refusing is the honest
  /// reading of what they can do today, not a ruling that they never
  /// should.
  @override
  bool get bandNamesRowsThisPressWouldMiss {
    final selection = frameRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final layer = activeLayer;
    return layer == null || !selection.coversLayer(layer.id);
  }

  String? get selectedFrameName => selectedFrame?.name;

  // --- B8: the frame verbs, addressed by the STORYBOARD cursor --------------
  //
  // The storyboard's standing row × the track-global playhead. The rail's
  // standing row is separate state from the cut's drawing target (유저
  // 2026-07-27), so the cut-local verbs above cannot carry these — and the
  // toolbar pressed on that panel must not fall back to them (B8
  // 2026-08-17: 「누른 패널 기준으로 동작」, 「블록 종류 불문 같은 규칙」).

  /// A seek is NOT a session notify: the playhead move rebuilds nothing by
  /// itself. Cursor-driven widgets follow [editingFrameCursor]; the few
  /// seek-dependent surfaces (editing canvas, timeline toolbar enablement,
  /// camera pose panel, timesheet playhead) subscribe to
  /// [frameSeekCommitted] and rebuild once per committed seek.
  @override
  void selectFrameIndex(int frameIndex) {
    // R15-⑤: a live editing interaction REFUSES the seek outright — a
    // flip under an in-flight edit tore widgets down inside the build
    // phase (red screens) and could land the edit on the wrong cel.
    if (editingInteractionBusy) {
      return;
    }
    // A direct cut-local seek leaves any gap parking (R16-⑥); the global
    // seek re-parks AFTER this call when it lands in a gap.
    gapGlobalFrame = null;
    labProbe('selectFrameIndex(sync)', () {
      activeCutControllers.timelineController.selectFrameIndex(frameIndex);
      editingFrameCursor.value = frameIndex;
      // A seek is activity (R13-3): rapid frame flipping keeps pushing the
      // warm window, so composite warming never lands a full-canvas build
      // in the middle of a flip run.
      playbackRig.prerenderScheduler.notifyEditActivity();
      warmActiveCut();
      frameSeekCommitted.value += 1;
    });
  }

  /// Pen-down → warm stand-down (R13-3): while a stroke is live the
  /// prerender warmer must not touch the UI/raster threads at all — the
  /// idle debounce alone resumed warming MID-stroke. Latched: unbalanced
  /// end calls (view resets without an active stroke) are no-ops.
  ///
  /// Exposed as a listenable (R13-4) so the canvas retarget scope can PIN
  /// an in-progress stroke to its cel: a committed seek that lands while
  /// the pen is down defers the canvas retarget until the stroke ends.
  final ValueNotifier<bool> brushInputActive = ValueNotifier<bool>(false);

  void setBrushInputActive(bool active) {
    if (active == brushInputActive.value) {
      return;
    }
    brushInputActive.value = active;
    if (active) {
      playbackRig.prerenderScheduler.beginInputHold();
    } else {
      playbackRig.prerenderScheduler.endInputHold();
    }
  }

  /// Selection-tool interactions (marquee/move/transform drags) — counted
  /// so overlapping holds nest (R15-⑤).
  @override
  final ValueNotifier<bool> selectionInteractionActive = ValueNotifier<bool>(
    false,
  );

  /// R15-⑤: any live editing interaction (brush stroke, selection drag)
  /// blocks frame seeks, scrubs and cut switches entirely — the playhead
  /// moves when the pen lifts, never under it.
  @override
  bool get editingInteractionBusy =>
      brushInputActive.value || selectionInteractionActive.value;

  // --- Track-global frame axis (R15-①) -----------------------------------

  /// THE structural model of the active track's timeline: cuts occupy
  /// [start, end) global ranges and the frames between them are REAL
  /// addresses (a layer timeline's empty frames, at track scale). The
  /// session playhead, the storyboard and the timeline consume THIS ONE
  /// axis — change it and every panel changes together.
  @override
  TrackFrameAxis trackFrameAxis() {
    final layout = projectSettings.projectLayout();
    final trackId = selectedTrackId;
    final scoped = [
      for (final entry in layout)
        if (entry.trackId == trackId) entry,
    ];
    return TrackFrameAxis(scoped.isEmpty ? layout : scoped);
  }

  /// Set while the editing playhead is PARKED IN A GAP (R16-⑥, user
  /// semantics: a gap has NO cut — the canvas shows a paperless void).
  /// Stores the exact global frame, which the leading gap before the
  /// first cut cannot express as any cut-local index. Notifier-backed
  /// (UI-R7 #9): gap scrubs park PER MOVE now, and the storyboard
  /// playhead must follow even where the cut-local cursor cannot change
  /// (the leading gap pins local 0).
  final ValueNotifier<int?> _gapGlobalFrameNotifier = ValueNotifier<int?>(null);

  @override
  int? get gapGlobalFrame => _gapGlobalFrameNotifier.value;
  @override
  set gapGlobalFrame(int? value) => _gapGlobalFrameNotifier.value = value;

  /// Fires when the gap parking is set, moved or cleared — the storyboard
  /// playhead subscribes (per-move gap scrubs, UI-R7 #9).
  ValueListenable<int?> get gapParkingListenable => _gapGlobalFrameNotifier;

  /// Whether the editing playhead sits in a gap (no cut there). During a
  /// LIVE global scrub the parking transiently addresses ANY
  /// out-of-active-cut position — another cut's frames included (the
  /// quiet-crossing drag) — so consumers outside the scrub-gated display
  /// path must not read a true here as "certainly between cuts" until the
  /// release resolves it into a selection or a real gap parking.
  /// 🚨★★★ T12 — A GAP PARKING IS THE ONLY WAY TO BE IN A GAP.
  ///
  /// This used to also ask `trackFrameAxis().isGap(editingGlobalFrame)`, and
  /// that term was DEAD CODE only because the global frame was clamped into
  /// the cut: a clamped frame is inside its own cut by construction, so the
  /// question could never come back true. Unclamping woke it up, and it
  /// immediately said the wrong thing — standing on frame 31 of a 24-frame
  /// cut lands on a global the axis calls a gap, so the canvas dropped its
  /// paper and its layers.
  ///
  /// ⛔That is precisely the law's negation: 「컷길이 넘어서도 **공간은 항상
  /// 존재하고 항상 보인다**」. If a cut is active you are standing IN it —
  /// anywhere in it, past its end line included. Only a global seek that
  /// parked with no cut is a gap, and [gapGlobalFrame] is exactly that
  /// state, held explicitly rather than inferred.
  ///
  /// ⚠️This is the sweep the getter's own doc promised whoever unclamped:
  /// the term did not need updating, it needed removing.
  @override
  bool get editingPlayheadInGap => gapGlobalFrame != null;

  /// The gap parking's exact global frame, or null when the playhead sits
  /// on a cut. Cheap field read — per-tick consumers (the storyboard
  /// playhead) use it without rebuilding the axis.
  int? get gapParkedGlobalFrame => gapGlobalFrame;

  /// 🚨★★★ The editing playhead as a track-global frame — UNFOLDED (T12).
  ///
  /// 유저: 「컷길이 넘어서도 **공간은 항상 존재하고 항상 보인다고.**
  /// 스토리보드에서만 그걸 컷길이로 클램핑해서 보여줄 뿐인거고.」
  ///
  /// ⛔It used to fold the position onto the active cut's last frame: stand
  /// on frame 31 of a 24-frame cut and this answered 23, which the user read
  /// straight off the canvas probe. The old note justified the fold by
  /// calling those frames a RUNWAY — and that vocabulary is banned for the
  /// reason the fold was wrong. Naming them a runway makes them a different
  /// KIND of place, and the special rules follow the word.
  ///
  /// ⚠️Clamping is a DISPLAY decision and it belongs where the display is:
  /// [storyboard_playhead_mapping] still clamps, because that surface really
  /// does show the cut's territory and a stale over-end index there would
  /// address the next cut. What changed is that the session no longer
  /// answers a question about where you are standing with an answer about
  /// where it can be drawn.
  ///
  /// ★[editingPlayheadInGap] gets sharper for free: `isGap` can now answer
  /// past the end line, where the clamped value made the term dead code —
  /// it was structurally impossible for a clamped frame to be outside its
  /// own cut.
  ///
  /// ⛔It is NOT established that this is what removes the paper from the
  /// screen. Two measurements say the pieces were already correct —
  /// `past_cut_end_is_ordinary_test` (the session) and
  /// `past_cut_end_paints_test` (the widget really is handed
  /// `paintPaper: true` and a non-empty tree past the end line, last cut
  /// included). Neither reproduced what the user saw. This was fixed because
  /// the law was wrong, not because the screen was proven to follow.
  @override
  int get editingGlobalFrame {
    final parked = gapGlobalFrame;
    if (parked != null) {
      return parked;
    }
    final cutId = activeCutId;
    if (cutId == null) {
      // No cut and no parking: a degenerate state (empty project open).
      return currentFrameIndex;
    }
    return trackFrameAxis().globalOf(cutId, currentFrameIndex) ??
        currentFrameIndex;
  }

  /// Deselects the active cut for a GAP landing (UI-R9 #3): standing in a
  /// gap means NO cut is selected — the timeline/timesheet show their
  /// empty states and the canvas shows the void. QUIET: callers notify
  /// (they batch it with the parking + commit signals). False when no cut
  /// was selected to begin with.
  bool _deselectActiveCutForGap() {
    if (editingSession.activeCutId == null) {
      return false;
    }
    // Parking in a gap LEAVES the cut, so the row it was on is recorded
    // here too — scrubbing out and back keeps the layer.
    standing.rememberActiveLayerForCut();
    // The visibility solo is cut-scoped: restore the eyes before leaving
    // (the selectCut contract).
    if (visibilitySolo.layerVisibilitySoloEnabled) {
      visibilitySolo.exitVisibilitySolo();
    }
    editingSession.setActiveCutId(null);
    clipboard.dropCopiedFrame();
    clearFrameRangeSelection();
    activeCutControllers.rebuild();
    return true;
  }

  /// V-TRACK selection (UI-R18 #6): tapping a V row makes THAT track's
  /// cut under the current global playhead the ACTIVE cut — every track
  /// reads the one shared global index, each independently (the V-row
  /// fx/eye subject rule). The landing keeps the global position: the new
  /// cut's local frame is the same global frame. A gap on the tapped
  /// track is a no-op, like the fx/eye buttons there.
  @override
  void selectTrackCutAtPlayhead(TrackId trackId) {
    if (editingInteractionBusy) {
      return;
    }
    // The TRACK is what the tap selected, so it is taken whether or not a
    // cut is found under the playhead — a gap on the tapped track is still
    // a no-op for the active cut, but the selection itself no longer
    // evaporates on the way, and the rail repaints even when nothing below
    // announces.
    selectTrackRow(trackId);
    final globalFrame = editingGlobalFrame;
    final layout = buildStoryboardTimelineLayout(repository.requireProject());
    for (final entry in layout) {
      if (entry.trackId == trackId &&
          globalFrame >= entry.startFrame &&
          globalFrame < entry.endFrame) {
        if (entry.cutId != activeCutId) {
          selectCut(entry.cutId);
        }
        selectFrameIndex(globalFrame - entry.startFrame);
        return;
      }
    }
    // A GAP on the tapped track PARKS there (user 2026-07-29, superseding
    // UI-R18 #6's no-op): selecting a row makes its current index the
    // active state, and with no cut to take that state is the parked
    // track stack — the display path (#768) that made a gap worth
    // standing on.
    parkGlobalFrame(globalFrame);
  }

  /// THE canonical seek: a global frame in. Inside a cut it selects
  /// cut + local frame; in a GAP it deselects the cut ENTIRELY (UI-R9 #3)
  /// and PARKS there — the stored global addresses the gap exactly,
  /// including the leading gap before the first cut, and the canvas shows
  /// the no-cut void.
  /// Moves the playhead to [globalFrame] and takes NO cut active — the
  /// parked state, whatever sits at that frame.
  ///
  /// A gap lands here because there is no cut to take — that is the whole
  /// of it now. The storyboard's SE rows used to land here too (feedback
  /// #7: pressing a sound says where you are, not which cut you are
  /// editing), on the reading that the active cut answers only to picking a
  /// cut on the row that HAS cuts. ⑭ retired that: one track means the
  /// index names one cut, so a row press seeks like any other and only a
  /// GAP still parks. Callers that park a frame a cut covers are declaring
  /// a preview, not a landing — the live scrub is the one such caller.
  void parkGlobalFrame(int globalFrame) {
    if (editingInteractionBusy) {
      return;
    }
    if (trackFrameAxis().isEmpty) {
      return;
    }
    gapGlobalFrame = globalFrame;
    _deselectActiveCutForGap();
    frameSeekCommitted.value += 1;
    notifyListeners();
  }

  /// [onAxis] lands the frame on a SPECIFIC track's axis instead of the
  /// selected track's. A caller that computed its move on one axis must
  /// land it on the same one — resolving on a different track would put
  /// the playhead in a cut the move never chose.
  @override
  void selectGlobalFrame(int globalFrame, {TrackFrameAxis? onAxis}) {
    if (editingInteractionBusy) {
      return;
    }
    final axis = onAxis ?? trackFrameAxis();
    if (axis.isEmpty) {
      return;
    }
    final local = axis.localOf(globalFrame);
    if (local == null || axis.isGap(globalFrame)) {
      // A GAP (leading or mid-track): no cut there — park + deselect.
      parkGlobalFrame(globalFrame);
      return;
    }
    if (local.cutId != activeCutId) {
      selectCut(local.cutId);
    }
    selectFrameIndex(local.localFrame);
  }

  // ── the frame scrub: its own object, in its own file ───────────────────
  //
  // A collaborator (session/frame_scrub.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final FrameScrub frameScrub = FrameScrub(
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    controllers: activeCutControllers,
    internals: this,
    playbackRig: playbackRig,
  );

  // --- Onion skin (P2: Callipeg peg model) -----------------------------------

  /// Session view state — a ValueNotifier so the canvas underlay and the
  /// onion panel subscribe without whole-session notifies.
  @override
  final ValueNotifier<OnionSkinSettings> onionSkinSettings =
      ValueNotifier<OnionSkinSettings>(const OnionSkinSettings());

  /// PER-LAYER onion application (UI-R17 #5, TVPaint's light table): the
  /// layers whose ghosts composite. The panel's master switch is GONE —
  /// row/legend toggles drive this set.
  @override
  final ValueNotifier<Set<LayerId>> onionSkinLayerIds =
      ValueNotifier<Set<LayerId>>(<LayerId>{});

  // ── the onion skin: its own object, in its own file ─────────────────
  //
  // A collaborator (session/onion_skin.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final OnionSkin onionSkin = OnionSkin(
    project: this,
    selection: this,
    changes: this,
    controllers: activeCutControllers,
    internals: this,
  );

  // ── the pool's content fingerprints: their own object ────────────────
  //
  // A collaborator (session/media_fingerprint_ledger.dart). It owns the
  // map; the import doors write to it, the save reads it, and the open
  // restores it.
  late final MediaFingerprintLedger mediaFingerprints = MediaFingerprintLedger(
    project: this,
  );

  // ── the OS's permission to read a referenced file: its own object ────
  //
  // A collaborator (session/media_grant_ledger.dart). It owns BOTH lists —
  // what this launch can use and what the file should keep — because
  // neither means anything without the other.
  late final MediaGrantLedger mediaGrants = MediaGrantLedger(project: this);

  // --- Project persistence (P3: the .anicel container) ----------------------
  //
  // Two collaborators, and the split is between the record and the writer.
  // [ProjectFile] is WHICH archive this session is bound to, what it
  // carries, where those bytes are right now and whether anything is
  // unsaved; [ProjectFileDoor] is the only thing that writes one or reads
  // one back, and it pushes every fact it learns down into the record.
  late final ProjectFile projectFile = ProjectFile(
    project: this,
    staging: mediaStagingStore,
  );

  // ── the media pool: its own object ───────────────────────────────────
  //
  // A collaborator (session/media_pool.dart). It owns the pool's derived
  // facts — what is missing, when each file was last written — and every
  // verb that rewrites the list. It is built after [projectFile] because
  // the existence sweep asks the archive whether the project already
  // holds an asset's bytes.
  late final MediaPool mediaPool = MediaPool(
    project: this,
    changes: this,
    file: projectFile,
    staging: mediaStagingStore,
    conforms: audioConformStore,
    fingerprints: mediaFingerprints,
  );

  late final ProjectFileDoor projectDoor = ProjectFileDoor(
    file: projectFile,
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    controllers: activeCutControllers,
    playbackRig: playbackRig,
    renderCaches: renderCaches,
    staging: mediaStagingStore,
    grants: mediaGrants,
    fingerprints: mediaFingerprints,
    textCelBakes: textCelBakes,
    clipboard: clipboard,
    layerClipboard: layerClipboard,
    audioConformStore: audioConformStore,
    frameSeekCommitted: frameSeekCommitted,
    mediaPool: mediaPool,
    liveStrokeLanding: liveStrokeLanding,
  );

  // ── the project-wide audio settings: their own object ────────────────
  //
  // A collaborator (session/project_audio.dart). It owns no state — the
  // rate and the pull live in the project — but the two verbs that write
  // them belong together and belong out of here.
  late final ProjectAudio projectAudio = ProjectAudio(
    project: this,
    changes: this,
    settings: projectSettings,
    door: projectDoor,
  );

  // --- Editing frame scrub (ruler drags ride the cursor path) --------------

  /// The editing playhead as a VALUE stream: every seek — scrub moves
  /// included — lands here, so cursor-driven widgets (timeline cursor
  /// layer, frame counter, the canvas scrub preview) follow pointer-fast
  /// without a session notify rebuilding the tree.
  @override
  final ValueNotifier<int> editingFrameCursor = ValueNotifier<int>(0);

  /// Bumped once per committed seek ([selectFrameIndex]) — a serial, not a
  /// frame (a same-frame commit must still fire after a scrub returned to
  /// its start). Seek-dependent panels subscribe here instead of the full
  /// session notify.
  final ValueNotifier<int> frameSeekCommitted = ValueNotifier<int>(0);

  /// ★THE PLAYHEAD MOVED — every channel it can move on, as one listenable
  /// (#10, 2026-08-21: 「버튼이 제대로 인덱스에 맞춰서 활성화/비활성화가
  /// 안된다 … 버튼 싹 다 맞춰서」).
  ///
  /// A button whose enablement reads the playhead subscribes HERE and
  /// nowhere else. Hand-listing the channels is what produced the report:
  /// three surfaces each picked a different subset, so the same drag left
  /// a different set of buttons stale on each of them —
  ///
  ///  * the ruler DRAG moves [editingFrameCursor] and commits nothing until
  ///    the release, so a bar listening only to [frameSeekCommitted] was
  ///    stale for the whole gesture (measured: 9 of 25 buttons);
  ///  * a scrub that leaves the cut's territory parks instead, moving
  ///    [gapParkingListenable] and NOT the cursor — which is why the
  ///    storyboard's shift pair stayed lit past the film's end while the
  ///    rest of its bar had already caught up.
  ///
  /// ⛔Playback is deliberately not a channel here: none of these three
  /// move while it runs, so a bar cannot start re-deriving 24 times a
  /// second because the film is playing.
  late final Listenable playheadMoved = Listenable.merge([
    frameSeekCommitted,
    editingFrameCursor,
    gapParkingListenable,
  ]);

  /// True while a ruler scrub is in flight.
  ///
  /// 🚨★★★ #26 (2026-08-15): THIS NO LONGER SWAPS THE DISPLAY. It used to —
  /// the canvas became the composite-cache preview until the release commit
  /// — and the user's law retired that: 「그냥 액티브레이어급으로 그냥 원본
  /// 보여주게하고싶어 … 그냥 항상 full」. A scrub shows the editing canvas,
  /// which follows the cursor through the canvas area's retarget scope.
  ///
  /// ⛔What it still decides is the GAP ANSWER: a parked global reads as a
  /// gap only while the gesture is live (the `gapGlobalFrame` read below),
  /// so the flag stays and the canvas rebuilds at enter and leave.
  @override
  final ValueNotifier<bool> frameScrubActive = ValueNotifier<bool>(false);

  /// D6: whether the LIVE global scrub currently stands OUT of the active
  /// cut's territory — the EDGE the canvas content mount listens to.
  ///
  /// A drag that STARTED inside the cut used to cross the boundary
  /// invisibly: the out-of-territory branch parks quietly per move,
  /// [frameScrubActive] was already true (its flip is the only rebuild
  /// trigger the content mount had), and the cursor never fires out of
  /// territory — so `inGap` was never recomputed and the canvas kept the
  /// previous cut's picture until release. This is the retired `playheadHasCel`
  /// mechanism applied to that missing edge: one comparison per move,
  /// fires only when the ANSWER flips (out↔in), so the per-move parking
  /// stays as quiet as UI-R7 #9 demands. Set only while the gesture is
  /// live — a plain tap over another cut parks on pointer-down but never
  /// scrubs, so this stays false and nothing flashes (the no-flash rule).
  @override
  final ValueNotifier<bool> scrubOutOfTerritory = ValueNotifier<bool>(false);

  // 🚨★★★ 유저 #6 (2026-08-14): 「룰러로 이동할때, **블록이 있으면 사용가능**
  // 타임라인버튼 활성화되는식으로 버튼 상태 바꼈으면 좋겠는데 안바뀜.
  // **효율좋게** 하는데 바뀌게 하고싶음. 갱신을 매 룰러 드래그마다가 아니라
  // **해당 인덱스에 버튼이 있으면 한번, 없으면 한번** 이런식으로?」
  //
  // ⛔`playheadHasCel` LIVED HERE and is retired (#10, 2026-08-21). It was a
  // single boolean standing in for a whole toolbar, argued for as 「거의 다
  // “플레이헤드 밑에 셀이 있나”로 환원된다」, and it failed on both counts:
  //
  //  * it was synced ONLY from [scrubFrameIndex], so a committed seek left
  //    it holding the previous drag's answer. Measured: at a frame that HAS
  //    a cel it read `false`, so the first crossing of the next drag — the
  //    one the user is watching — could not flip it;
  //  * one boolean cannot carry twenty-five buttons. Measured on the
  //    default project: a scrub from a drawn frame to an empty one moves
  //    NINE of them.
  //
  // ★The replacement is not another proxy: every consumer subscribes to
  // [editingFrameCursor] — the playhead's own channel, moved by a scrub and
  // by a commit alike, and never by playback — and re-derives ITS OWN
  // answer, rebuilding only when that answer differs. The user's efficiency
  // instruction is kept exactly where it belongs: a crossed frame costs one
  // derivation and zero rebuilds unless something actually changed.

  // The per-layer "empty cels" memo TOKEN that used to live here is gone
  // with [celContentRevision]. It was the weaker form of the same idea: a
  // string rebuilt for every row on every pass, which forced a row REBUILD
  // and only when something else had already announced — which is exactly
  // why a freshly drawn block stayed grey until you switched layers.

  // --- Status text --------------------------------------------------------

  String get currentLayerStatusText {
    final layer = activeLayer;
    return 'Layer: ${layer?.name ?? 'None'}';
  }

  @override
  String drawingStartStatusForLayer(Layer layer, int frameIndex) {
    final frameName = frameVerbs.frameNameForLayer(layer, frameIndex);
    if (frameName == null || frameName.isEmpty) {
      return 'Drawing start';
    }

    return 'Drawing start: $frameName';
  }

  // --- Canvas selection labels -------------------------------------------

  CanvasEditorSelectionLabels get canvasSelectionLabels {
    final project = repository.requireProject();
    final cut = activeCutOrNull;
    final layer = activeCutControllers.layerController.activeLayer;
    final frame = selectedFrame;
    return CanvasEditorSelectionLabels(
      projectLabel: project.name,
      // Gap state: no cut selected — the label says so.
      cutLabel: cut?.name ?? '—',
      layerLabel: layer?.name ?? '-',
      frameLabel: frameVerbs.currentFrameDisplayLabel(layer, frame),
    );
  }
}
