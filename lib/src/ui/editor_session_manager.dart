import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/flutter_test_run.dart';
import '../services/font_library_service.dart';
import '../services/fx_plugins/device_fx_plugin_binding.dart';
import '../services/fx_plugins/installed_fx_plugins.dart';
import '../services/persistence/failed_save_copies.dart';
import '../services/persistence/media_staging_store.dart';
import '../services/persistence/open_project_file.dart';
import '../services/media/sheet_photo_edits.dart';
import '../services/project_lookup.dart'
    show brushFrameKeyIn, cutPositionOf, cutWritingRow, rowPoseSpace;
import '../models/app_language.dart';
import '../services/persistence/app_save_settings.dart';
import '../services/persistence/app_memory_settings.dart';
import '../models/app_input_settings.dart';
import 'session/drags/media_placement_drag.dart';
import 'canvas/after_frame_once.dart';
import 'session/attach_fx_confirm.dart';
import 'session/canvas_adjust.dart';
import 'session/sheet_photo_hold.dart';
import 'session/editor_app_settings.dart';
import 'session/editor_voice_recording.dart';
import '../models/app_accents.dart';
import '../services/editing/active_cut_helpers.dart';
import '../services/editing/editing_session_state.dart';
import '../services/editing/run_id_mint.dart' as frame_ids;
import '../services/editing/layer_standing_after_change.dart';
import '../models/brush_frame_key.dart';
import '../models/canvas_point.dart';
import '../models/canvas_size.dart';
import '../models/canvas_viewport.dart';
import '../models/conte_group.dart' show conteHeadFamiliesOf;
import '../models/cut.dart';
import '../models/transform_track.dart';
import '../models/cut_id.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/fx_plugin_binding.dart';
import '../models/layer.dart';
import '../models/layer_effect.dart' show EffectId;
import '../models/layer_id.dart';
import '../models/standing_place.dart';
import '../models/layer_kind.dart';
import '../models/media_asset.dart'
    show MediaAssetKind, mediaAssetKindForPath, normalizedMediaPath;
import '../models/movie_cel.dart' show isMovieReference;
import '../models/reference_swap.dart';
import '../services/import/import_layer_spot.dart';
import 'timeline/layer_drop_policy.dart' show newRowInsertionForSlot;
import 'import/import_file_settings.dart' show importBakeAllowed;
import '../models/timesheet_info.dart';
import '../models/timesheet_sheet_kind.dart';
import '../models/pasteboard_bounds.dart';
import '../models/project.dart';
import '../models/pill_subject.dart';
import '../models/timeline_selection_kind.dart';
import '../models/timeline_frame_range.dart';
import '../models/timeline_repeat.dart';
import '../models/timeline_row_address.dart';
import '../models/working_panel.dart';
import '../models/track.dart';
import '../models/track_camera_head.dart' show cameraHeadFamilyOf;
import '../models/track_frame_range.dart';
import '../models/track_id.dart';
import '../services/conte_step_scope.dart';
import '../services/cut_frame_composite_plan.dart';
import '../models/playback_mode.dart';
import '../models/track_transitions.dart' show drawnFrameCountsOf;
import '../services/playback/frame_demand.dart';
import '../services/playback/playback_frame_mapping.dart';
import '../core/dev_profile.dart';
import '../core/identity_memo.dart';
import 'playback/canvas_playback_controller.dart';
import 'session/active_cut_span.dart';
import 'session/cut_placement.dart';
import 'session/block_shift.dart';
import 'session/cut_shift.dart';
import 'session/history_pictures.dart';
import 'text/app_strings.dart';
import 'text/word_bake.dart' show RepaintOnWordBakes;
import '../models/track_frame_axis.dart';
import '../models/storyboard_timeline_layout.dart';
import '../services/command.dart' show WorkAhead;
import '../services/commands/cut_command_coordinator.dart';
import '../services/commands/link_mirror.dart' show headMirrorRows;
import '../services/audio/audio_conform_runner.dart' show runConformHere;
import '../native/qa_audio_device.dart' show audioDeviceUnlessTesting;
import '../native/qa_native_engine.dart';
import 'canvas/tile_picture_budget.dart';
import 'canvas/stroke_in_flight.dart';
import 'session/cache_budgets.dart';
import '../services/memory_allowance.dart';
import '../services/brush_tip_stamp_cache.dart';
import '../services/brush_live_stroke_rasterizer.dart';
import '../services/history_manager.dart';
import '../services/history_places.dart';
import '../services/project_repository.dart';
import 'audio/audio_conform_store.dart';
import 'brush/brush_canvas_panel.dart';
import 'brush/canvas_selection_commands.dart' show CanvasSelectionDocument;
// ⑨: the row selection grows through the SAME span law the cell selection
// uses — the rail's own drawn row list.
import 'timeline/timeline_cell_exposure_state.dart';
import 'timeline/timeline_drag_preview.dart';
import 'timeline/timeline_frame_ruler_painter.dart'
    show timelineFramePlaceLabel;
import 'timeline/timeline_grid_tile_store.dart';
import 'session/live_stroke_landing.dart';
import 'session/pixel_editing.dart';
import 'session/session_roles.dart';
import 'session/media_file_views.dart';
import 'session/media_fingerprint_ledger.dart';
import 'session/media_grant_ledger.dart';
import 'session/media_pool.dart';
import 'session/import_landing.dart';
import 'session/project_import_doors.dart';
import 'session/cut_folder_import_door.dart';
import 'session/tvpp_import_door.dart';
import 'session/clip_import_door.dart';
import 'session/audio_clips.dart';
import 'session/project_file.dart';
import 'session/project_file_door.dart';
import 'session/project_fonts.dart';
import 'session/project_audio.dart';
import 'session/movie_cel_hydrator.dart';
import 'session/playback_rig.dart';
import 'session/render_caches.dart';
import 'session/frame_range_move_drag.dart';
import 'session/edge_drag.dart';
import 'session/movie_end_drag.dart';
import 'session/folder_bands.dart';
import 'session/visibility_solo.dart';
import 'session/transitions.dart';
import 'session/camera.dart';
import 'session/camera_view_mode.dart';
import 'session/cut_under_playhead.dart';
import 'session/playhead_cursors.dart';
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
import 'session/app_clipboard.dart';
import 'session/frame_clipboard.dart';
import 'session/layer_clipboard.dart';
import 'session/effect_clipboard.dart';
import 'session/key_clipboard.dart';
import 'session/text_clipboard.dart';
import 'session/active_cut_controllers.dart';
import 'session/layer_stack.dart';
import 'session/layer_merging.dart';
import 'session/layer_verbs.dart';
import 'session/cut_verbs.dart';
import 'session/rail_view.dart';
import 'session/panel_view_memory.dart';
import 'session/timeline_zoom_memory.dart';
import 'session/range_selections.dart';
import 'session/se_entries.dart';
import 'session/block_move_commands.dart';
import 'session/run_frames_add_drag.dart';
import 'session/opacity_verbs.dart';
import 'session/active_cut_edits.dart';
import 'session/layer_id_mint.dart';
import 'session/layer_marks.dart';
import 'session/exposure_verbs.dart';
import 'session/block_naming.dart';
import 'session/cell_instances.dart';
import 'session/cell_verbs.dart';
import 'session/pixel_verbs.dart';
import 'session/rail_legends.dart';
import 'session/folders_and_attachments.dart';
import 'session/project_settings.dart';
import 'session/frame_verbs.dart';
import 'session/track_axis_walk.dart';
import 'session/standing.dart';
import 'session/cut_move_drag.dart';
import 'session/trimmed_pieces.dart';
import 'session/layer_switch_verbs.dart';
import 'session/editing_canvas.dart';
import 'track_effect_paint_policy.dart' show trackEffectsAt;
import 'package:flutter/painting.dart' show ImageCache;

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
        RetimeLaw {
  EditorSessionManager({
    required Project initialProject,
    EditorAppSettings? appSettings,
    AudioConformStore? audioConformStore,
    MediaStagingStore? mediaStagingStore,
    FontLibraryService? fontLibrary,
    InstalledFxPlugins? fxPlugins,
    ImageCache? frameworkImageCache,
    FailedSaveCopies? failedSaveCopies,
    AppClipboard? appClipboard,
    bool Function(String path)? fileIsOpenElsewhere,
  }) : editingSession = EditingSessionState.forProject(initialProject),
       _injectedAudioConformStore = audioConformStore,
       _injectedMediaStagingStore = mediaStagingStore,
       _injectedFontLibrary = fontLibrary,
       _frameworkImageCache = frameworkImageCache,
       failedSaveCopies = failedSaveCopies ?? FailedSaveCopies(),
       _appClipboard = appClipboard ?? AppClipboard(),
       _fileIsOpenElsewhere = fileIsOpenElsewhere,
       _ownsAppSettings = appSettings == null,
       fxPlugins = fxPlugins ?? InstalledFxPlugins(),
       _ownsFxPlugins = fxPlugins == null,
       appSettings = appSettings ?? (EditorAppSettings()..restore()),
       repository = ProjectRepository(initialProject: initialProject) {
    historyManager = HistoryManager()
      ..scope = ConteStepScope(repository)
      ..places.placeNow = () => standingPlace;
    cutCommandCoordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: editingSession,
      historyManager: historyManager,
      brushFrameStore: renderCaches.brushFrameStore,
    );
    activeCutControllers.rebuild();
    renderCaches.attach();
    playbackRig.attach();
    _followThePlayhead();
    // The canvas shows a reference movie's picture at the frame it stands
    // on — asked on every seek and every change, a no-op once the store has
    // it.
    editingFrameCursor.addListener(_hydrateShownMovieCels);
    addListener(_hydrateShownMovieCels);
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
    historyManager.addListener(_railFollowsTheDocument);
    // F-360: the rows' folds as the opened file holds them, before any
    // history change asks again.
    railView.readFolds(repository.currentProject);
    // F-363: the camera view is the camera row's eye and opacity — read
    // again on every change, and on every move of a slider, which no change
    // carries.
    addListener(cameraViewMode.read);
    opacityVerbs.dragPreview.addListener(cameraViewMode.read);
    cameraViewMode.read();
    layerStack.attach();
    // Every cache's budget, from this device's laws and the allowance a
    // person chose — set now, and again whenever the allowance moves.
    _applyCacheBudgets(enforce: false);
    AppMemory.settings.addListener(_applyCacheBudgets);
    // A plugin installed or taken off greys or ungreys the effects of it
    // this project's rails draw (🗣️I-132-Q28 a 「설치하면 그대로 다시
    // 걸린다」) — the app's one list, so every open project hears it.
    this.fxPlugins.addListener(notifyListeners);
  }

  /// What follows the playhead — the cut a run plays, the cut under it and
  /// where it is drawn — listening on every channel it moves on, in this
  /// order.
  void _followThePlayhead() {
    final playhead = playbackRig.playback.globalFrameIndexListenable;
    playhead.addListener(followPlaybackCut);
    // F-90: the cut under the playhead re-answers wherever the playhead or
    // the cut can move; [CutUnderPlayhead.sync] publishes crossings only.
    playhead.addListener(cutUnderPlayhead.sync);
    editingSession.gapParkingListenable.addListener(cutUnderPlayhead.sync);
    frameScrub.active.addListener(cutUnderPlayhead.sync);
    addListener(cutUnderPlayhead.resync);
    // …and answers now: the conte's plate reads its VALUE (F-248), where the
    // sheet and the envelope only heard it — null until the first notify.
    cutUnderPlayhead.resync();
    // Where the playhead is drawn re-answers on every channel it moves on —
    // after the cut follow above, so a tick that crosses into another cut
    // is answered against the cut it landed in. A scrub move fires the
    // editing cursor WITHOUT a session notify, so [playheadMoved], which
    // carries it, is what keeps the playhead glued to the pointer.
    playhead.addListener(playheadCursors.sync);
    playheadMoved.addListener(playheadCursors.sync);
    addListener(playheadCursors.sync);
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
  final EditorAppSettings appSettings;

  /// Whether [appSettings] is this session's own to let go of: the app's
  /// one is shared by every open project and released by the shell that
  /// made it (I-7); a session built without one made it for itself.
  final bool _ownsAppSettings;

  /// The fx plugins this device has installed (I-132) — the app's one,
  /// which every open project lists from, or this session's own, empty,
  /// where none was handed it (a test's).
  final InstalledFxPlugins fxPlugins;

  /// Whether [fxPlugins] is this session's own to let go of, as
  /// [_ownsAppSettings] says of [appSettings].
  final bool _ownsFxPlugins;

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

  /// How much of the device's allowance this project's own caches may take:
  /// all of it on screen, a share in a background tab — the shell says
  /// which ([OpenProjects], I-7). What it scales is what can be rebuilt or
  /// is kept whole elsewhere: the hot cels cool to the scratch room, the
  /// playback frames render again.
  ///
  /// ⛔NOT the undo stack. Its entries are the user's history, and a
  /// smaller budget parks them into a room that shrinks with it — the room
  /// weighs what the stack was allowed to (유저 확정 2026-09-10) — and past
  /// a full room the stack DROPS entries. A tab left in the background must
  /// not cost its history.
  double get cacheShare => _cacheShare;

  double _cacheShare = 1;

  set cacheShare(double share) {
    if (share == _cacheShare) {
      return;
    }
    _cacheShare = share;
    _applyCacheBudgets();
  }

  /// Every cache's budget at the automatic allowance, on this device's
  /// laws — what the memory tab's slider scales.
  late final CacheBudgets deviceCacheBudgets = CacheBudgets.forDevice(
    physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
  );

  /// The allowance when nobody has moved the slider: the device's, read
  /// ONCE here ([automaticAllowanceBytes]) — an app's limit drifts with
  /// what the app holds, and a slider whose automatic end kept moving
  /// would be a lie about what was chosen.
  late final int automaticAllowance = automaticAllowanceBytes(
    physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
    appMemoryLimitBytes: QaNativeEngine.instance?.appMemoryLimitBytes,
    floorBytes: CacheBudgets.floors.total,
    lawsTotalBytes: deviceCacheBudgets.total,
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
    final allowance =
        AppMemory.settings.value.allowanceBytes ?? automaticAllowance;
    final by = deviceCacheBudgets.factorFor(allowance);
    final budgets = deviceCacheBudgets.scaledBy(by);
    // This project's OWN caches take its share of the allowance ([cacheShare]);
    // the lines below them are the process's and take it whole.
    final own = _cacheShare == 1
        ? budgets
        : deviceCacheBudgets.scaledBy(by * _cacheShare);
    MemoryAllowance.factor.value = by;
    renderCaches.applyCacheBudgets(own);
    historyManager.byteBudget = budgets.undo;
    playbackRig.playbackCache.playbackCacheByteBudget = own.playback;
    QaNativeEngine.instance?.nativeUploadByteBudget = budgets.nativeUploads;
    BrushTipStampCache.instance.byteBudget = budgets.brushTips;
    BrushLiveStrokeRasterizer.residentResultByteBudget = budgets.liveStroke;
    // The two the allowance did not reach until 2026-09-16 (Q2): the
    // framework's image cache, seeded by the binding before any session,
    // and the engine's parked tile blocks, a compile-time cap until then.
    // ★A new [CacheBudgetLine] is applied HERE, and nowhere else.
    _frameworkImageCache?.maximumSizeBytes = budgets.imageCache;
    QaNativeEngine.instance?.setTilePoolByteCap(budgets.enginePool);
    // The canvas's tile pictures (render round, 2026-09-16): the walk that
    // lets the unshown ones go reads this ceiling after every paint.
    TilePictureBudget.instance.byteBudget = budgets.tileImages;
    if (enforce) {
      playbackRig.playbackCache.enforcePlaybackCacheBudget();
    }
    playbackLineMoved();
  }

  /// The playback line moved — the allowance, or a memory warning lifted as
  /// the app came back to the front (F-504) — so a warmer resting for want
  /// of room looks again, and a line that rose fills while nothing plays.
  void playbackLineMoved() => playbackRig.prerenderScheduler.wake();

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
    appSettings: appSettings,
  );

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
    sessionDisposed: () => disposed,
    onEditActivity: () => playbackRig.prerenderScheduler.notifyEditActivity(),
  );

  /// The OS memory-pressure signal, forwarded by the shell to every open
  /// project: the hot cel tier halves and cools, and the playback caches
  /// re-run their budget against the shrunken world. Standing down is
  /// lossless by construction — cels encode to cold, dirty ones stay.
  void respondToMemoryPressure() {
    // ⚠️EVERY cel store — the sheet-ink stores are cel stores like the
    // drawings', and until 2026-09-11 they never heard the warning, so this
    // walks the one list rather than naming them.
    for (final store in renderCaches.celStores) {
      store.respondToMemoryPressure();
    }
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
  /// Decodes a reference movie's pictures where they are shown — the playback
  /// warmer before each frame, the canvas at the frame it stands on.
  late final MovieCelHydrator movieCels = MovieCelHydrator(
    project: this,
    changes: this,
    renderCaches: renderCaches,
    frameRate: () => projectSettings.projectFrameRate,
    holdBytes: projectFile.holdMediaBytes,
    carryFor: projectFile.mediaCarryFor,
  );

  late final PlaybackRig playbackRig = PlaybackRig(
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    appSettings: appSettings,
    soloedSeLayerIds: visibilitySolo.soloedSeLayerIds,
    renderCaches: renderCaches,
    settings: projectSettings,
    audioConformStore: audioConformStore,
    movieCels: movieCels,
    voiceRecording: voiceRecording,
    onStopped: _onPlaybackStopped,
    onStoppedInGap: _onPlaybackStoppedInGap,
    onPlaylistWarmRequested: _onPlaybackPlaylistWarmRequested,
    // ⛔Not the tear-off `editingCanvas.playedStackAt`: it reads the canvas
    // as the rig is made, and the canvas's own making reaches the rig
    // (opacity verbs → transitions → camera → the scrub) — a stack overflow
    // the moment any part of the session is first asked for.
    stackOf: (picture) => switch (picture.ghosts) {
      FrameGhosts.none => editingCanvas.playedStackAt(
        picture.cut,
        picture.frameIndex,
      ),
      FrameGhosts.alone => editingCanvas.ghostsOverAt(
        picture.cut,
        picture.frameIndex,
      ),
      FrameGhosts.inPlace => editingCanvas.playedStackAt(
        picture.cut,
        picture.frameIndex,
        ghostsInPlace: true,
      ),
    },
  );

  /// ⚠️`void` and `async`: the playback controller does not wait for this,
  /// but the BODY's own order still matters — the take has to have landed
  /// before the cut selection below runs, or the two commands reach the
  /// undo history in whichever order the isolate happened to finish in.
  Future<void> _onPlaybackStopped(PlaybackPosition lastPosition) async {
    // Transport stop finishes a rolling take (REC1-B): record = play +
    // capture, so ending one ends the other. The result message goes out
    // on the notice channel — this path has no button to return through.
    //
    // ⚠️The guard stays at the call: awaiting on a stop that rolled no take
    // would push everything below to a later microtask, and every stop
    // lands its cut and frame synchronously today.
    if (voiceRecording.isVoiceRecording.value) {
      await voiceRecording.finishTakeThroughTheNotice();
    }
    // ↩️F-169 asked the standing law here too, and the session notified
    // once more: the quiet follow (R12-B) had seated each cut's row outside
    // the law and told nobody. A crossing is a cut switch now (I-57 ②), and
    // a cut switch asks the law and notifies for itself.
    _landOn(lastPosition);
  }

  /// Stop landed on a playlist GAP frame (UI-R9 #3): match the editing
  /// gap semantics — park there with NO active cut.
  /// ⚠️`void` and `async` for the same reason as [_onPlaybackStopped].
  Future<void> _onPlaybackStoppedInGap(int globalFrame) async {
    // The gap-stop twin of _onPlaybackStopped's take finish: a lane is
    // cut-independent, so a take may legitimately end over a gap.
    if (voiceRecording.isVoiceRecording.value) {
      await voiceRecording.finishTakeThroughTheNotice();
    }
    parkGlobalFrame(globalFrame);
  }

  /// Premiere-style follow: while playback crosses cut boundaries the
  /// ACTIVE cut tracks the playing cut and stays there when playback
  /// stops. Playback-only selection state — no command runs, the undo
  /// stack never sees it.
  ///
  /// 🗣️I-57 (유저 10-09, Q2: 「타임라인 행도 그 자리에서 — 행을 먼저 가볍게
  /// 만든 뒤 켠다」): the crossing is the landing every cut switch makes
  /// ([_landOn]), so the timeline's rows and everything else that reads the
  /// active cut turn over at the boundary — the crossing a scrub makes too
  /// ([FrameScrub.scrubGlobalFrame]). ↩️R12-B (07-13) kept it QUIET, with
  /// no notify and no warm, because rebuilding the visible panels at a
  /// boundary stuttered; whatever had to follow anyway was wired to the
  /// playhead one surface at a time. The rail's rows were made light for
  /// the crossing first (I-57 ①).
  ///
  /// 🚨THE CROSSING LANDS ONCE THE FRAME THAT SHOWS IT HAS BEEN HANDED OVER
  /// (I-57, 10-13). The canvas draws a run from its position, never from
  /// the active cut, so the crossing's first picture needs nothing the
  /// landing does — and landing INSIDE that frame made the picture wait for
  /// every panel's turn-over: 🔬23–32ms of UI at each boundary (profile,
  /// AMMI OP) against a held frame's 8.6, the new cut's first picture
  /// several refreshes late at every crossing (유저 10-13: 「재생시 컷 경계
  /// 넘을때도 버벅여. 매번」). The panels turn over in the next frame, with
  /// a film frame's time before the picture after it.
  void followPlaybackCut() {
    if (_crossedInto() != null) {
      _landingAfterThePicture.ask(() {
        if (_crossedInto() case final position? when !disposed) {
          _landOn(position);
        }
      });
    }
  }

  final AfterFrameOnce _landingAfterThePicture = AfterFrameOnce();

  /// Where a running playback stands when that is another cut than the
  /// active one.
  PlaybackPosition? _crossedInto() {
    if (playbackRig.playback.globalFrameIndexListenable.value == null) {
      return null;
    }
    final position = playbackRig.playback.position;
    if (position == null || position.cutId == editingSession.activeCutId) {
      return null;
    }
    return position;
  }

  /// Where a run stands — at a crossing while it plays, and where it stops:
  /// its cut, with the row [Standing.layerACutSwitchSeats] names, then the
  /// frame of that cut's own the run is on.
  void _landOn(PlaybackPosition position) {
    if (position.cutId != editingSession.activeCutId) {
      selectCut(position.cutId);
    }
    selectFrameIndex(
      activeCutControllers.clampedFrameIndex(
        playheadCursors.ownFrameOf(position),
      ),
    );
  }

  /// A run begins, and from here the warmer follows what it shows in the
  /// order it plays ([PlayingDemand]): the frame under the playhead first,
  /// so the pictures about to be shown are the ones made, and round to the
  /// frame behind it when the run loops — a second pass plays out of the
  /// cache as far as the allowance holds one.
  ///
  /// What a frame shows is what the screen draws there. A cut playing alone
  /// shows that cut, every frame it is DRAWN for (F-227 — the のりしろ an O.L
  /// asks of it, which its playlist entry already spans). The film shows
  /// the track stack: every covered track's cut, and both cuts of an O.L.
  void _onPlaybackPlaylistWarmRequested(
    List<StoryboardTimelineLayoutEntry> playlist,
    PlaybackScope scope,
    int startGlobalFrame,
  ) {
    final playback = playbackRig.playback;
    final totalFrames = playback.totalFrames;
    if (totalFrames == 0) {
      return;
    }
    final alone = scope == PlaybackScope.activeCut;
    // Where each cut's own frame 0 stands on the film's axis: asked once a
    // cut, because the budget asks it of every picture it weighs. And how
    // many frames the film shows of it — what it is DRAWN for; a frame past
    // that (a drawing out on the runway) is no frame of the film's.
    final mediaStarts = <CutId, int>{};
    final drawn = drawnFrameCountsOf(repository.requireProject());
    playbackRig.prerenderScheduler.follow(
      PlayingDemand(
        totalFrames: totalFrames,
        loops: () => playback.loopMode == PlaybackLoopMode.loop,
        playhead: () => playback.playlistFrame,
        picturesOf: alone
            ? (frame) {
                final position = resolvePlaybackPosition(
                  playlist: playlist,
                  globalFrameIndex: frame,
                );
                return [
                  if (position != null)
                    (
                      cut: position.cut,
                      frameIndex: position.localFrameIndex,
                      paintPaper: true,
                      ghosts: FrameGhosts.none,
                    ),
                ];
              }
            : (frame) => [
                for (final shown in rowSpans.trackStackContributionsAt(frame))
                  (
                    cut: shown.cut,
                    frameIndex: shown.localFrameIndex,
                    // The film's stage — its lowest track covered here —
                    // is on its paper; a track over it is not
                    // (`CanvasTrackStackView`).
                    paintPaper: shown.isBottomTrack,
                    ghosts: FrameGhosts.none,
                  ),
              ],
        playlistFrameOf: alone
            ? (cutId, frameIndex) =>
                  cutId == playlist.first.cutId ? frameIndex : null
            : (cutId, frameIndex) => frameIndex < (drawn[cutId] ?? 0)
                  ? (mediaStarts[cutId] ??= rowSpans.trackGlobalFrameOf(
                          cutId,
                          0,
                        )) +
                        frameIndex
                  : null,
        // Where the clock does not wait for a picture, one is started
        // where the playhead will be when it lands. Where it waits there is
        // no lead: what the run waits for is the warmer's to make.
        lead: (composeTime) =>
            playbackRig.playbackMode == PlaybackMode.skipFrames
            ? projectSettings.projectFrameRate.frameAtElapsed(composeTime)
            : null,
      ),
    );
  }

  @override
  late final HistoryManager historyManager;

  /// Undo and redo whose first frame is whole — see [HistoryPictures].
  late final HistoryPictures historyPictures = HistoryPictures(
    history: historyManager,
    store: renderCaches.brushFrameStore,
  );
  @override
  late final CutCommandCoordinator cutCommandCoordinator;

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
    editingFrameCursor: editingFrameCursor,
    playbackFrameCount: () => activeCutSpan.activeCutPlaybackFrameCount,
    activeCutHasLayer: (layerId) => activeCutSpan.activeCutHasLayer(layerId),
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

  // ── where a new row's id comes from: its own object ─────────────────
  //
  // A collaborator (session/layer_id_mint.dart): the `default-layer-N`
  // counter, and the project scan that keeps it honest.
  late final LayerIdMint layerIds = LayerIdMint(project: this);

  // ── the frame clipboard: its own object, in its own file ────────────
  //
  // A collaborator (session/frame_clipboard.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final FrameClipboard clipboard = FrameClipboard(board: _appClipboard.frames, project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, renderCaches: renderCaches, mediaBytesOf: projectFile.mediaByteSourceFor, staging: mediaStagingStore, laneVerbs: laneVerbs);
  late final LayerClipboard layerClipboard = LayerClipboard(board: _appClipboard.layers, project: this, selection: this, changes: this, layerStack: layerStack, renderCaches: renderCaches, mediaBytesOf: projectFile.mediaByteSourceFor, staging: mediaStagingStore, rowSelection: rowSelectionVerbs, layerVerbs: layerVerbs);
  late final KeyClipboard keyClipboard = KeyClipboard(board: _appClipboard.keys, laneVerbs: laneVerbs, changes: this);
  late final EffectClipboard effectClipboard = EffectClipboard(board: _appClipboard.effects, laneVerbs: laneVerbs, effectsAndFx: effectsAndFx, changes: this);
  late final TextClipboard textClipboard = TextClipboard(
    board: _appClipboard.texts,
    project: this,
    pixelEditing: pixelEditing,
    pixelVerbs: pixelVerbs,
    renderCaches: renderCaches,
    changes: this,
  );

  /// What the boards above hold — the APP's, handed to every open project
  /// by the shell (I-7, 유저 2026-09-26: 「탭사이에 복사나 붙여넣기 뭐든
  /// 가능. 앱 전체에 하나」). A session built without one keeps its own.
  final AppClipboard _appClipboard;

  /// [_appClipboard], for the memory census to weigh what it holds.
  AppClipboard get appClipboard => _appClipboard;

  // ── the layer verbs: their own object, in their own file ────────────
  //
  // A collaborator (session/layer_verbs.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final LayerVerbs layerVerbs = LayerVerbs(project: this, selection: this, changes: this, controllers: activeCutControllers, renderCaches: renderCaches, rowSelection: rowSelectionVerbs);

  // ── the merge (I-78): its own object, in its own file ───────────────
  late final LayerMerging layerMerging = LayerMerging(
    project: this,
    changes: this,
    frameIds: this,
    renderCaches: renderCaches,
    rowSelection: rowSelectionVerbs,
    rangeSelections: rangeSelections,
    layerVerbs: layerVerbs,
  );

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
    layerIds: layerIds,
    layerVerbs: layerVerbs,
    standing: standing,
    folderBands: folderBands,
    renderCaches: renderCaches,
    canvasStroke: canvasStroke,
    dragPreview: dragPreview,
    soundCannotPlay: (filePath) => playbackRig.soundCannotPlay(filePath),
    soundsMoved: () => playbackRig.soundsMoved,
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

  /// What the rail leaves off the screen (sections, the row filter, folded
  /// attach groups) and what it twirls open — held here because the
  /// standing law reads it (F-169), and the rows it names are this
  /// project's (I-7). The folds and twirls in it are read off the rows
  /// (F-360).
  late final RailView railView = RailView();

  /// Every use of [row] — the rows that twirl and fold as one with it: the
  /// rows that wear its head, in whichever cuts they stand
  /// ([headMirrorRows] — its link group's, a track's conte rows that are
  /// its row of the track's structure, and a track's cameras), and itself
  /// alone for a row that is none of these or that no cut holds (a track's).
  ///
  /// 🗣️F-302 (유저 2026-10-05): 「겸용컷, 레이어에서 fx 접기펼치기,
  /// 폴더/어태치 접기/펼치기 버튼도 공유. 지금 겸용컷별로 독립적임. 펼친
  /// 상태 접힌 상태 공유하라는것. 법통일」 — and the conte rows since I-73
  /// (10-08), whose head is one: 「콘티행도 동일하게 하고싶으니까 어태치
  /// 접기펼치기버튼등 동일하게 할수있는거 다 넣는거 잊지말고」 — and a
  /// track's cameras since I-73 ④, whose head is one as well: 「그럼
  /// 카메라행도 글로벌? 콘티행처럼 머리 같도록 할까하는데」. The storyboard
  /// draws them as one row, whose twirl opens every cut's camera lanes.
  ///
  /// The row is found in its OWN cut, the active one or not: the
  /// storyboard's rail presses the rows of every cut, a gap's included
  /// (I-73 ④ⓔ). ↩️It asked the active cut, and in a gap answered the row
  /// alone — a head shut there shut one row, and [RailView.followHeads] let
  /// it back open beside the rest.
  ///
  /// ↩️The folds and the twirls are written on these rows by their own
  /// commands since F-360 (`LinkMirroredLayerFieldCommand` walks the same
  /// head); what still asks here is what the rail keeps of them — a graph
  /// and a pin.
  List<LayerId> rowsFoldingWith(LayerId row) {
    final project = repository.requireProject();
    final cutId = cutWritingRow(project, row, standing: activeCutId);
    return cutId == null
        ? [row]
        : headMirrorRows(
            project,
            cutId: cutId,
            layerId: row,
            cameraHead: true,
          );
  }

  /// The timeline zoom each of this project's cuts was left at (F-253) —
  /// held here, not on the window, because the cuts it names are this
  /// project's (I-7).
  late final TimelineZoomMemory timelineZoom = TimelineZoomMemory();

  /// Where this project's panels were left — the conte's zoom and each frame
  /// panel's scroll (F-267) — held here for the zoom's reason (I-7).
  late final PanelViewMemory panelViews = PanelViewMemory();

  /// The page and the framing each file was left at in the viewers (F-382)
  /// — held here, not on the window that holds the viewers, for the zoom's
  /// reason (I-7): what a project's references were left at is that
  /// project's.
  late final MediaFileViews mediaFileViews = MediaFileViews();

  /// Where this project's CANVAS is framed — its zoom, pan and turn; null
  /// until something frames it, which the canvas resolves to the identity
  /// at read time.
  ///
  /// 🚨The PROJECT's since I-7 (a project per tab). The canvas is rebuilt
  /// for the tab on screen, so a framing kept in its State went with every
  /// switch, and a tab came back at the identity rather than where it was
  /// left.
  final ValueNotifier<CanvasViewport?> canvasViewport = ValueNotifier(null);

  /// This project's marquee and polygon trace — the app's selection channel
  /// shows it while this project is on screen (I-7; see
  /// [CanvasSelectionDocument]).
  final CanvasSelectionDocument canvasSelection = CanvasSelectionDocument();

  /// This project's canvas being resized on the canvas (I-79) — the size
  /// window opens it, the canvas shows its box and pill.
  final CanvasAdjust canvasAdjust = CanvasAdjust();

  /// The photos on this project's sheets (I-97), as the pool and a hand
  /// edit them.
  late final SheetPhotoEdits sheetPhotoEdits = SheetPhotoEdits(
    () => renderCaches.sheetInkStores,
  );

  /// This project's photo held on a sheet (I-97-Q3) — its box up and its
  /// pill under it.
  late final SheetPhotoHold sheetPhotoHold = SheetPhotoHold(
    edits: sheetPhotoEdits,
    history: historyManager,
  );

  // Where the user stands (Round 6): cut, row and layer.
  late final Standing standing = Standing(project: this, selection: this, changes: this, timeline: this, controllers: activeCutControllers, rowSelectionVerbs: rowSelectionVerbs, solo: visibilitySolo, trackSe: trackSe, rangeSelections: rangeSelections, selectTrackCutAtPlayhead: selectTrackCutAtPlayhead, brushInputActive: brushInputActive, sessionDisposed: () => disposed, playbackRig: playbackRig, railView: railView, fxEnabledOf: (layerId) => effectsAndFx.isLayerFxEnabled(layerId), activeCutHasLayer: (layerId) => activeCutSpan.activeCutHasLayer(layerId));

  // I-41: every door that MOVES where the user stands — the cut, the row,
  // the frame, the gap — first walks off ([HistoryPlaces.leave]): the last
  // edit settles where it left them, for the move is theirs, not the
  // edit's — and a hand the walk lets go of lands as made there. A door
  // that only passes through these (`selectRow`, `selectGlobalFrame`)
  // leaves it to them. The hand-offs inside an action go through
  // [standing] and the controllers, not through these.
  void selectCut(CutId cutId) {
    historyManager.places.leave();
    standing.selectCut(cutId);
  }

  TimelineRowAddress get currentRow => standing.currentRow;

  /// The panel the arrows, the flip and the bound keys answer to — the one
  /// last touched ([Standing.workingPanel]).
  WorkingPanel get workingPanel => standing.workingPanel;
  ValueListenable<WorkingPanel> get workingPanelListenable =>
      standing.workingPanelListenable;

  /// The row the STORYBOARD's verbs act on — [selectedRow], or a lane of a
  /// row that rail shows ([Standing.storyboardStandingRow]).
  @override
  TimelineRowAddress get storyboardStandingRow =>
      standing.storyboardStandingRow;

  /// The row the TIMELINE's verbs act on ([Standing.timelineStandingRow]).
  @override
  TimelineRowAddress get timelineStandingRow => standing.timelineStandingRow;

  void standOnRow(
    TimelineRowAddress row, {
    WorkingPanel panel = WorkingPanel.timeline,
    int? frameIndex,
    int? globalFrameIndex,
  }) {
    historyManager.places.leave();
    standing.standOnRow(
      row,
      panel: panel,
      frameIndex: frameIndex,
      globalFrameIndex: globalFrameIndex,
    );
  }

  void selectLayer(LayerId layerId) {
    historyManager.places.leave();
    standing.selectLayer(layerId);
  }

  void selectRow(TimelineRowAddress row) => standing.selectRow(row);
  void handOffCurrentRowOnFold(LayerId layerId, {String? laneId}) =>
      standing.handOffCurrentRowOnFold(layerId, laneId: laneId);
  void handOffCurrentRowOnAttachFold(LayerId baseId) =>
      standing.handOffCurrentRowOnAttachFold(baseId);
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
  ///
  /// Answered once per project, cut stood in and stored track
  /// ([IdentityMemo]): the session's other derivations key on it, and it
  /// walked every cut of the film per ask.
  @override
  TrackId get selectedTrackId => _selectedTrack.resolve(
    identity: repository.requireProject(),
    key: (editingSession.activeCutId, editingSession.selectedTrackId),
    build: _selectedTrackIdOf,
  );

  final _selectedTrack = IdentityMemo<TrackId>();

  TrackId _selectedTrackIdOf() {
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
    selection: this,
    projectSettings: projectSettings,
  );

  void claimStoryboardRow() => standing.claimStoryboardRow();

  /// A panel surface's word on whether it is on the screen
  /// ([Standing.panelInSight]). Its last word comes as it is unmounted, which
  /// at teardown can be after this session is gone.
  void panelInSight(
    WorkingPanel panel, {
    required Object surface,
    required bool inSight,
  }) {
    if (!disposed) {
      standing.panelInSight(panel, surface: surface, inSight: inSight);
    }
  }
  void updateStoryboardCutSelectionByFrame({
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TrackId? trackId,
    List<TimelineRowAddress> spanRows = const [],
  }) => rangeSelections.updateStoryboardCutSelectionByFrame(
    anchorGlobalFrame: anchorGlobalFrame,
    headGlobalFrame: headGlobalFrame,
    trackId: trackId,
    spanRows: spanRows,
  );
  @override
  void clearStoryboardCutSelection() =>
      storyboardRows.clearStoryboardCutSelection();


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
  late final RowSpans rowSpans = RowSpans(project: this, folderBands: folderBands, projectSettings: projectSettings, trackSe: trackSe, transitions: transitions);

  late final RowSelection rowSelectionVerbs = RowSelection(rangeSelections: rangeSelections, history: historyManager, repository: repository, standingIn: () => activeCutId);

  /// ⚠️A ROLE member, not a forwarder: [SelectionAccess.clearRowSelection]
  /// is asked of the SESSION by collaborators that must not name this one
  /// (RowSelection already holds RangeSelections, so the edge back would
  /// close a construction cycle). ↩️Whether a row is selected was the second
  /// such member; its one collaborator, [RangeSelections], takes the question
  /// as a closure now (the ninth family's cure for a cycle edge), and every
  /// other reader names [rowSelectionVerbs].
  @override
  void clearRowSelection() => rowSelectionVerbs.clearRowSelection();

  // ── the range selections: their own object, in their own file ───────
  //
  // A collaborator (session/range_selections.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final RangeSelections rangeSelections = RangeSelections(
    project: this,
    selection: this,
    retime: this,
    projectSettings: projectSettings,
    trackSe: trackSe,
    rowSpans: rowSpans,
    currentRow: () => standing.currentRow,
    playbackRig: playbackRig,
    // Lazily: RowSelection is built FROM rangeSelections.
    rowIsSelected: (row) => rowSelectionVerbs.rowIsSelected(row),
    selectTrackRow: selectTrackRow,
    selectLayer: selectLayer,
    standOnRow: standOnRow,
  );

  void updateFrameRangeSelectionDrag({
    required LayerId layerId,
    required int anchorIndex,
    required int headIndex,
    LayerId? headLayerId,
    List<TimelineRowAddress> spanRows = const [],
  }) => rangeSelections.updateFrameRangeSelectionDrag(
    layerId: layerId,
    anchorIndex: anchorIndex,
    headIndex: headIndex,
    headLayerId: headLayerId,
    spanRows: spanRows,
  );
  @override
  void clearFrameRangeSelection() =>
      rangeSelections.clearFrameRangeSelection();
  void updateTrackRowRangeSelectionByFrame({
    required LayerId layerId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TimelineRowAddress? anchorRow,
    List<TimelineRowAddress> spanRows = const [],
  }) => rangeSelections.updateTrackRowRangeSelectionByFrame(
    layerId: layerId,
    anchorGlobalFrame: anchorGlobalFrame,
    headGlobalFrame: headGlobalFrame,
    anchorRow: anchorRow,
    spanRows: spanRows,
  );
  void updateLaneRangeSelectionDrag({
    required LayerId layerId,
    required String laneId,
    required int anchorIndex,
    required int headIndex,
    required List<String> spanLaneIds,
    WorkingPanel panel = WorkingPanel.timeline,
  }) => rangeSelections.updateLaneRangeSelectionDrag(
    layerId: layerId,
    laneId: laneId,
    anchorIndex: anchorIndex,
    headIndex: headIndex,
    spanLaneIds: spanLaneIds,
    panel: panel,
  );
  void clearLaneRangeSelection() => rangeSelections.clearLaneRangeSelection();
  bool standingInsideSelection(
    TimelineRowAddress row, [
    int? frameIndex,
    bool frameIsGlobal = false,
  ]) =>
      rangeSelections.standingInsideSelection(row, frameIndex, frameIsGlobal);
  @override
  void clearTimelineSelections() => rangeSelections.clearTimelineSelections();
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

  /// Where the canvas leaves the live editing coordinator — a SIBLING the
  /// pixel verbs take ([PixelEditing] says why).
  final PixelEditing pixelEditing = PixelEditing();

  /// Where the canvas leaves 「land the stroke the pen is holding」, and
  /// where the save door picks it up.
  ///
  /// 🚨Filled in exactly the way [pixelEditing] is, from the same build — a
  /// SIBLING object rather than a name on the session. See
  /// [LiveStrokeLanding] for the rest of the reason.
  final LiveStrokeLanding liveStrokeLanding = LiveStrokeLanding();

  // ── the cell verbs: their own object, in their own file ─────────────
  //
  // A collaborator (session/cell_verbs.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final CellVerbs cells = CellVerbs(project: this, selection: this, changes: this, controllers: activeCutControllers, laneVerbs: laneVerbs, rangeSelections: rangeSelections, clipboard: clipboard, transitions: transitions);

  // ── the pixel verbs: the 색 편집 list and 전체 잘라내기 ─────────────
  //
  // A collaborator (session/pixel_verbs.dart), carved out of the cell verbs
  // when I-55 doubled the family. Callers name it, as they name [cells].
  late final PixelVerbs pixelVerbs = PixelVerbs(project: this, selection: this, controllers: activeCutControllers, pixelEditing: pixelEditing, renderCaches: renderCaches, pixelBoard: _appClipboard.pixels, solo: visibilitySolo, brushInputActive: brushInputActive, liveStrokeDraws: layerStack.liveStrokeDraws);

  // ── the rail legends: what each panel's header opens, for a key (I-40) ──
  final RailLegends railLegends = RailLegends();

  // ── 자동 이름 지정: its own object, in its own file ─────────────────────
  //
  // A collaborator (session/block_naming.dart, I-18): which blocks a press
  // numbers, the plan it writes, and writing it. Callers name it — the
  // panels' contexts ask `session.blockNaming` for their targets.
  late final BlockNaming blockNaming = BlockNaming(
    project: this,
    selection: this,
    changes: this,
    controllers: activeCutControllers,
    laneVerbs: laneVerbs,
    rangeSelections: rangeSelections,
    layerVerbs: layerVerbs,
    cutVerbs: cutVerbs,
    projectSettings: projectSettings,
  );

  TimelineRowAddress get selectedRow => standing.selectedRow;

  /// Makes a V row THE selected row and nothing else — no cut promotion, no
  /// seek. The cells press wants this half on its own: the frame it presses
  /// decides the cut, so promoting the playhead's cut first would switch
  /// cuts twice for one press.
  void selectTrackRow(TrackId trackId) {
    if (strokeInFlight) {
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
    dragPreview: dragPreview,
  );

  @override
  bool isTrackTransitionLayerId(LayerId layerId) =>
      transitions.isTrackTransitionLayerId(layerId);
  /// The active cut's global start frame on its track (cumulative cut
  /// durations — the storyboard layout's number for this cut).
  @override
  int get activeCutGlobalStartFrame =>
      cutGlobalStartFrameIn(activeTrack, editingSession.activeCutId) ?? 0;

  /// The track frame the active cut's OWN frame 0 shows — 🚨THE LENS
  /// between the cut's frames (its rows' keys, the timeline's columns) and
  /// the track's ([TrackFrameAxis.mediaStartOf]): the cut's place on the
  /// track less the のりしろ an O.L arriving into it asks. In every other
  /// cut it is [activeCutGlobalStartFrame], which stays the answer to WHERE
  /// THE CUT STANDS — what a span is measured against to say whether it
  /// crosses the cut, or began before it.
  ///
  /// ↩️The cut view's window on the track's rows counted from the cut's
  /// place (I-73-ol-index-space, 🧪2026-10-08: in a cut a 12-frame O.L
  /// arrives into, a sound at the track's frame 30 stood on the timeline's
  /// column 6 — and the picture it is heard with on column 12).
  @override
  int get activeCutMediaStartFrame {
    final cutId = editingSession.activeCutId;
    return cutId == null
        ? 0
        : projectSettings.projectAxis().mediaStartOf(cutId) ?? 0;
  }

  @override
  String framePlaceLabel(int frameIndex) => timelineFramePlaceLabel(
    frameIndex: frameIndex,
    framesPerSecond: projectSettings.projectFrameRate.countingBase,
    showSeconds: panelViews.showSeconds.value,
  );

  // ── the track SE display: its own object, in its own file ───────────
  //
  // A collaborator (session/track_se_display.dart). ⛔The forwarders are
  // gone (G3, 2026-09-07): callers say `session.trackSe.x`. What is left
  // below is the session IMPLEMENTING a role — those three are members of
  // `ProjectAccess`, not a second name for a verb.
  late final TrackSeDisplay trackSe = TrackSeDisplay(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, transitions: transitions, voiceRecording: voiceRecording);

  @override
  bool isTrackSeLayerId(LayerId layerId) => trackSe.isTrackSeLayerId(layerId);
  @override
  int rowAxisOffset(LayerId layerId) => trackSe.rowAxisOffset(layerId);
  @override
  Layer? trackSeGlobalLayerById(LayerId layerId) =>
      trackSe.trackSeGlobalLayerById(layerId);

  // ── the SE entries and name tags: their own object ──────────────────
  //
  // A collaborator (session/se_entries.dart). ⛔The forwarders are gone
  // (G3, 2026-09-07): callers say `session.seEntries.x`.
  late final SeEntries seEntries = SeEntries(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, camera: camera, frameVerbs: frameVerbs, projectSettings: projectSettings);

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

  /// The rail reads the rows' folds and twirls off the document
  /// ([RailView.readFolds], F-360), and a row a command made in a track's
  /// conte family — or a camera its cut brought onto a track — wears the
  /// family's graphs ([RailView.followHeads]) — asked after EVERY history
  /// change: a command, an undo, a redo.
  ///
  /// ↩️Asked in [refreshAfterCutCommand], beside the links, until a pin
  /// found the doors that make such a row never come through it
  /// (2026-10-08): the ＋ that bears a conte and the one that adds a row to
  /// it stand on their new row themselves. 🧪A conte born beside a folded
  /// group was born open — folded on the storyboard's rail, whose head is
  /// the first cut's, and open in its own cut's timeline.
  ///
  /// The families are read only while a graph is open or a lane pinned
  /// (`expand` is lazy): a stroke is a history change too.
  void _railFollowsTheDocument() {
    final project = repository.currentProject;
    railView.readFolds(project);
    if (project != null) {
      railView.followHeads(
        project.tracks.expand(
          (track) => [
            ...conteHeadFamiliesOf(track.cuts),
            cameraHeadFamilyOf(track.cuts),
          ],
        ),
      );
    }
  }

  @override
  void refreshAfterCutCommand({
    LayerId? preferredActiveLayerId,
    int? preferredFrameIndex,
    bool reveal = false,
    bool filterSparesStanding = true,
  }) {
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
    // F-302: a row the command linked wears its group's graphs. Its folds
    // it wears already — they are its own (F-360), and the rail read them
    // off the document as the command entered history, before the standing
    // law below asks which rows the rail shows.
    railView.followLinks(repository.requireProject().linkRegistry);
    // F-169: wherever the command left you, it is a row on screen.
    standing.keepStandingShown(
      reveal: reveal,
      filterSparesStanding: filterSparesStanding,
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
  /// canvas selection uses ([brushFrameKeyIn]).
  @override
  BrushFrameKey brushFrameKeyForCut(Cut cut, LayerId layerId, FrameId frameId) =>
      brushFrameKeyIn(repository.requireProject(), cut, layerId, frameId);

  /// Warms the active cut's composites around the playhead ("navigate away
  /// from a frame and it gets pre-rendered") — and the NEXT cut behind it
  /// (#31, 유저 확정: 스토리보드 프로의 룩어헤드를 따른다). The next cut
  /// is next in STORYBOARD order, the same order play-all and the panel
  /// read, so the bar that goes green is the bar beside the one you are
  /// on.
  @override
  void warmActiveCut() {
    if (playbackRig.playback.isActive) {
      // A run is being followed, and stays followed. What changed under it
      // — a reference movie's frame decoded — is looked at again from the
      // playhead.
      playbackRig.prerenderScheduler.wake(fromTheStart: true);
      return;
    }
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    playbackRig.prerenderScheduler.requestWarmCut(
      cutId: cut.id,
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

  /// A project closing lets go of every file it holds: the one it is bound
  /// to — held by the save or the open, cels or none — and whatever its
  /// clean cels read from (a copy a save moved them onto). The process holds
  /// a file per open project (I-7), and a tab that closed has no reason to
  /// keep its file undeletable.
  void _letGoOfTheFilesItHolds() {
    final files = {
      ?projectFile.path,
      for (final store in renderCaches.celStores) ...store.filesReadFrom,
    };
    for (final path in files) {
      OpenProjectFile.instance.releaseFor(path);
    }
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
  ///     the playback cursor before [playbackRig], the shown-movie decode
  ///     before [editingFrameCursor], the three history listeners before
  ///     [historyManager] at the very end;
  ///   - [LayerStack.dispose] removes ITS OWN listeners from [renderCaches]
  ///     and [canvasStroke], so it runs before either of them;
  ///   - [historyManager] goes last, after every listener it carries.
  /// A new entry belongs at the END unless it has one of those reasons —
  /// and then the reason is written here.
  List<void Function()> get _teardown => [
    () => AppMemory.settings.removeListener(_applyCacheBudgets),
    layerStack.dispose,
    rowSelectionVerbs.dispose,
    // ⚠️Deleting this line alone survives the teardown test: the `disposed`
    // guard inside [_publishCutLocalLaneRange] already answers. It stays
    // because the guard is the belt and this is the braces — a listener you
    // added is a listener you remove (measured 2026-09-08: with BOTH gone,
    // the test reports the write to a disposed notifier).
    () => laneRangeSelection.removeListener(_publishCutLocalLaneRange),
    cutLocalLaneRangeSelection.dispose,
    rangeSelections.dispose,
    memoryPressureTicks.dispose,
    () => playbackRig.playback.globalFrameIndexListenable.removeListener(
      followPlaybackCut,
    ),
    // F-90's listeners go before the rig and the two scrub notifiers they
    // hang on are released, and the session's own before it stops.
    () => playbackRig.playback.globalFrameIndexListenable.removeListener(
      cutUnderPlayhead.sync,
    ),
    () => editingSession.gapParkingListenable.removeListener(
      cutUnderPlayhead.sync,
    ),
    () => frameScrub.active.removeListener(cutUnderPlayhead.sync),
    () => removeListener(cutUnderPlayhead.resync),
    cutUnderPlayhead.dispose,
    // The same: off the rig and the playhead's channels before they go.
    () => playbackRig.playback.globalFrameIndexListenable.removeListener(
      playheadCursors.sync,
    ),
    () => playheadMoved.removeListener(playheadCursors.sync),
    () => removeListener(playheadCursors.sync),
    playheadCursors.dispose,
    // The guard in [_hydrateShownMovieCels] is the belt and this the braces
    // — the same pair as the lane range above.
    () => editingFrameCursor.removeListener(_hydrateShownMovieCels),
    () => historyManager.removeListener(projectFile.markDirty),
    () => historyManager.removeListener(refreshLiveAudioSchedule),
    () => historyManager.removeListener(_railFollowsTheDocument),
    voiceRecording.dispose,
    playbackRig.dispose,
    renderCaches.dispose,
    audioConformStore.dispose,
    () {
      if (_ownsAppSettings) {
        appSettings.dispose();
      }
      // Off the app's list, which outlives this project, before one of its
      // own is let go.
      fxPlugins.removeListener(notifyListeners);
      if (_ownsFxPlugins) {
        fxPlugins.dispose();
      }
    },
    visibilitySolo.dispose,
    editingFrameCursor.dispose,
    frameScrub.dispose,
    frameSeekCommitted.dispose,
    editingSession.dispose,
    frameRangeSelection.dispose,
    brushInputActive.dispose,
    dragPreview.dispose,
    canvasAdjust.dispose,
    sheetPhotoHold.dispose,
    // F-363's two listeners come off before the slider's notifier goes.
    () => opacityVerbs.dragPreview.removeListener(cameraViewMode.read),
    () => removeListener(cameraViewMode.read),
    cameraViewMode.dispose,
    opacityVerbs.dispose,
    onionSkin.dispose,
    cutVerbs.dispose,
    trackFrameRangeSelection.dispose,
    railView.dispose,
    canvasViewport.dispose,
    panelViews.dispose,
    historyPictures.dispose,
    () => unawaited(movieCels.dispose()),
    standing.dispose,
    _letGoOfTheFilesItHolds,
    // After the files: that reads what the stores read from (F-505).
    () {
      for (final store in renderCaches.celStores) {
        store.dispose();
      }
    },
    // The app's timeline tiles keep the resolvers they were baked against —
    // this project's, its whole session behind them (F-505, measured: the
    // first holder of a closed tab). The project on screen bakes its own
    // again.
    TimelineGridTileStore.instance.clear,
    // So do the rows' kept pictures, by what each was drawn from.
    RepaintOnWordBakes.clearKeptPictures,
    canvasStroke.dispose,
    historyManager.dispose,
  ];

  /// Test seam: widget tests inject a store with a fake runner so SE rows
  /// never decode real files.
  final AudioConformStore? _injectedAudioConformStore;
  final MediaStagingStore? _injectedMediaStagingStore;
  final FontLibraryService? _injectedFontLibrary;

  /// The fonts a person brought to this device (R9-rest) — asked, at a save
  /// and whenever a font this project carries is read, where the file the
  /// project registered is kept (`ProjectFile.fontsToStore`).
  ///
  /// The shell hands every open project the library its font list is read
  /// from. A session built without one reads the app's own folder — which
  /// under a test is a sandbox (`FontLibraryService.defaultFontDirectoryPath`).
  late final FontLibraryService fontLibrary =
      _injectedFontLibrary ?? FontLibraryService();

  /// [CacheBudgetLine.imageCache]'s holder: the framework's image cache,
  /// which exists only once a binding does. The screen hands it in. A plain
  /// test builds its session with no binding and hands nothing — the line
  /// then has no holder to reach, and `PaintingBinding.instance` has no
  /// null-safe form to ask.
  final ImageCache? _frameworkImageCache;

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
              resolveCarry: projectFile.mediaCarryFor,
              resolveProjectSampleRate: () =>
                  repository.requireProject().audioSampleRate,
              resolveAudioSpeed: () => repository.requireProject().audioSpeed,
              // Widget tests: run conforms inline — a worker isolate started
              // under fake async outlives the test (the prerender scheduler's
              // FLUTTER_TEST branch, same reason). Missing fixture paths
              // short-circuit before any decode, so this stays cheap.
              runner: underFlutterTest
                  ? (request) => Future.value(runConformHere(request))
                  : null,
              placeForPlayback: (floats) =>
                  audioDeviceUnlessTesting()?.newSamples(floats),
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
    appSettings: appSettings,
    camera: camera,
    trackSe: trackSe,
    transitions: transitions,
  );

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
    project: this,
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
    storyboardRows: storyboardRows,
    activeCut: _activeCutEdits,
    placement: cutPlacement,
    renderCaches: renderCaches,
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

  /// [canvas] out as far as the project's pasteboard reaches (I-109): the
  /// wall every picture on the floor stands behind.
  PasteboardWall pasteboardOf(CanvasSize canvas) =>
      canvas.pasteboardAt(repository.requireProject().pasteboardReach);

  /// The wall of the cut on screen ([pasteboardOf]). Null in a gap.
  PasteboardWall? get activePasteboardOrNull => switch (activeCutOrNull) {
    final cut? => pasteboardOf(cut.canvasSize),
    null => null,
  };

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
    controllers: activeCutControllers,
    dragPreview: dragPreview,
    activeCut: _activeCutEdits,
    cutUnderPlayhead: cutUnderPlayhead,
  );

  // ── the cut under the playhead: its own object, in its own file ───────
  //
  // A collaborator (session/cut_under_playhead.dart, F-90). Callers name it —
  // `session.cutUnderPlayhead.resolve()`.
  late final CutUnderPlayhead cutUnderPlayhead = CutUnderPlayhead(
    project: this,
    timeline: this,
    controllers: activeCutControllers,
    scrubbing: frameScrub.active,
    playbackRig: playbackRig,
  );

  // ── where the playhead is drawn: its own object, in its own file ──────
  //
  // A collaborator (session/playhead_cursors.dart). The panels and the rows
  // they fold into read it — `session.playheadCursors.cutFrame`.
  late final PlayheadCursors playheadCursors = PlayheadCursors(
    project: this,
    selection: this,
    timeline: this,
    playbackRig: playbackRig,
  );

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
    dragPreview: dragPreview,
    controllers: activeCutControllers,
    opacityVerbs: opacityVerbs,
    trackSe: trackSe,
    cutEffectsAt: (cutId, frameIndex) => trackEffectsAt(
      effectsAndFx.trackEffectsForCut(cutId),
      rowSpans.trackGlobalFrameOf(cutId, frameIndex),
      enabled: effectsAndFx.isCutFxEnabled(cutId),
    ),
    movieLaidAt: (key) => movieCels.laidAt(key),
    ghostsAt: (cut, frameIndex, dragPreview) =>
        onionSkin.ghostsAt(cut, frameIndex, dragPreview),
    pluginsIn: fxPluginsIn,
  );

  /// What runs the plugins [cut]'s chains run on this device
  /// ([deviceFxPluginBinding]): its builds ([InstalledFxPlugins.runnerFor]),
  /// the project's frame rate, and each row's cel as the store holds it.
  FxPluginBinding fxPluginsIn(Cut cut) => deviceFxPluginBinding(
    runnerFor: fxPlugins.runnerFor,
    frameRate: repository.requireProject().frameRate,
    surfaceOf: (layer, frame) =>
        renderCaches.celSurfaceIn(cut, layer.id, frame.id),
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
  );

  /// The camera view — the camera row's eye and opacity as the canvas and
  /// the bars read them (F-363; session/camera_view_mode.dart).
  late final CameraViewMode cameraViewMode = CameraViewMode(
    project: this,
    selection: this,
    opacity: opacityVerbs,
    switches: layerSwitches,
  );

  // The frame verbs (Round 6): the playhead's frame and what stands there.
  late final FrameVerbs frameVerbs = FrameVerbs(
    project: this,
    selection: this,
    changes: this,
    frameIds: this,
    timeline: this,
    controllers: activeCutControllers,
    dragPreview: dragPreview,
    currentRow: () => standing.currentRow,
    renderCaches: renderCaches,
    trackAxis: trackAxisWalk,
    workingPanel: () => standing.workingPanel,
  );

  // The track's axis, walked: the storyboard's rows and a gap's steps.
  late final TrackAxisWalk trackAxisWalk = TrackAxisWalk(
    project: this,
    selection: this,
    timeline: this,
    controllers: activeCutControllers,
    projectSettings: projectSettings,
    trackSe: trackSe,
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
    activeCut: _activeCutEdits,
    laneGroupShown: (row, laneId) => activeCutControllers.layerController
        .twirls
        .laneGroupShownCommand(row, laneId),
  );

  // `activeCutCanvasPoseSample` retired with the V row's transform: there is
  // no track pose for the editing canvas or the scrub preview to apply.

  // `setCutFade` and `updateTrackTransformTrack` retired with the V row's
  // transform. The cut fade is F.I / F.O spans on the TRANSITION row now
  // ([updateTransitionInstructions]) — where the span's length IS the ramp,
  // and where two cuts overlapping across a boundary can carry different
  // values, which one opacity lane per track never could.

  // ── the lane verbs: their own object, in their own file ─────────────
  //
  // A collaborator (session/lane_verbs.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4). The layer
  // transform write lives there too, beside its funnel (the fifteenth
  // family): `session.laneVerbs.updateLayerTransformTrack`.
  late final LaneVerbs laneVerbs = LaneVerbs(
    project: this,
    selection: this,
    timeline: this,
    controllers: activeCutControllers,
    effectsAndFx: effectsAndFx,
    dragPreview: dragPreview,
    changes: this,
    currentRow: () => standing.currentRow,
    sessionDisposed: () => disposed,
    activeCut: _activeCutEdits,
    // The camera's one write, not the camera — see
    // `LaneVerbs._updateCameraTrack`.
    updateCameraTrack: (cameraRow, track, {required description}) =>
        camera.updateCameraTrack(cameraRow, track, description: description),
    previewFormsOf: (row) => trackSe.previewFormsOf(row),
  );

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
      orElse: () => layerIdentityPose(_poseSpaceOf(layer)),
    );
  }

  /// The layer's resolved anchor point at [frameIndex] (the middle of its
  /// pose space while unkeyed) — the lane key-freeze source and the canvas
  /// gizmo's anchor.
  @override
  CanvasPoint layerAnchorPointAtFrame(Layer layer, int frameIndex) {
    final space = _poseSpaceOf(layer);
    return resolveLayerAnchorPointAt(layer: layer, frameIndex: frameIndex) ??
        CanvasPoint(x: space.width / 2, y: space.height / 2);
  }

  /// The space [layer] is posed in ([rowPoseSpace]): the shot, or the
  /// canvas of the cut writing it.
  CanvasSize _poseSpaceOf(Layer layer) => rowPoseSpace(
    repository.requireProject(),
    layer,
    standing: activeCutId,
  )!;

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
  );

  // --- Cut display gates ---------------------------------------------------

  // --- V track display: the static opacity and the fx master (R9 #21) ----

  // --- The V row's EFFECT CHAIN (fx on the cut, not on one layer) --------
  //
  // A layer's chain filters that layer's picture; this one filters the whole
  // composited cut under the playhead (user 2026-08-08). It is TRACK data on
  // the GLOBAL axis, exactly like the pose and the fade beside it, so these
  // verbs take a TrackId and no cut is ever in the loop.

  // ↩️The V row's EYES stood here (`CutPictureEyes`, the audit's
  // twenty-third family): the cuts whose picture the playback display hid.
  // They left with the V row's head on 2026-10-08 (I-73, 유저: 「V행의
  // 불투명도랑 비지블 필요없어보여서 삭제하고싶은데 어때」).

  /// Steps history and puts the session back where the new layer list says
  /// it should be.
  ///
  /// ⛔[undo] and [redo] were eighteen identical lines apart from which way
  /// the history moved. The rule of three usually holds a pair apart, and
  /// its reason — that a hasty merge leaves one flag answering two
  /// questions — does not apply here: the difference becomes the ARGUMENT,
  /// so there is no flag and nothing to read twice.
  ///
  /// [found] is where the step's edit found the user, for an undo: a row
  /// the undo takes away from under them hands them back there (F-350,
  /// [HistoryPlaces.foundAt]).
  void _stepHistory(void Function() move, {StandingPlace? found}) {
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
    // step used to run [refreshAfterCutCommand] — which CLEARS THE
    // FRAME-RANGE SELECTION (and dropped the copied frame too, until F-152
    // kept it in hand), rebuilds the cut controllers and wakes every
    // session listener. That is what a CUT command owes. Pressing Ctrl+Z
    // after a brush stroke owes none of it, and paid all of it: the user's
    // clipboard and their band went away because of an edit that moved no
    // row.
    //
    // ⚠️And the forward direction never did this. `HistoryManager`'s own
    // doc says 「brush strokes execute here WITHOUT a session notify, so
    // nothing else would ever tell them a stroke landed」 — the buttons
    // subscribe to the history, the canvas repaints off the invalidation
    // the commit sends. Undo is the same edit run backwards and owed the
    // same silence; it was the one direction that shouted.
    //
    // 🔬**THE WHOLE FAMILY, not the symptom.** Of the 53 command classes
    // that enter history, exactly five never touched the repository:
    // `BrushStrokeHistoryCommand`, `BrushLiftMoveHistoryCommand`,
    // `CelPixelOverwriteCommand`, `ToggleIdInSetCommand` and
    // `RekeyBrushFramesCommand` — and the last is only ever composed INTO a
    // step that also moves layers, so its group does move the document and
    // does get the tidy-up. One question answers all five. ↩️F-360 put the
    // twirls and the attach fold that `ToggleIdInSetCommand` wrote on the
    // rows and deleted it: undoing one moves the document now, and tidies
    // up as undoing a folder's fold always did.
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
      handBackTo: found?.cut == activeCutId ? found?.layer : null,
    );
    // F-169, the standing law's two questions. A row the step brought BACK
    // is where you stood when it went (② 「언두시에 접혀있는 레이어로 이동하면
    // 펼치고 해당 레이어에 서게」); any other new row is a HAND-OFF — the row
    // you stood on is gone and the walk picked this one, which the filter's
    // exemption must not put on the screen (①).
    final broughtBack =
        preferredLayerId != null &&
        beforeLayers.every((layer) => layer.id != preferredLayerId);
    refreshAfterCutCommand(
      preferredActiveLayerId: preferredLayerId,
      preferredFrameIndex: previousFrameIndex,
      reveal: broughtBack,
      filterSparesStanding:
          broughtBack || preferredLayerId == previousActiveLayerId,
    );
    notifyListeners();
  }

  /// Where the user stands — the cut, the row and the frame; null in the
  /// gap between cuts. What the history writes beside every entry (I-41).
  StandingPlace? get standingPlace {
    final cut = activeCutId;
    return cut == null
        ? null
        : (cut: cut, layer: activeLayerId, frame: currentFrameIndex);
  }

  /// ⚠️Through [historyPictures], never straight to the history: a step
  /// whose pictures are not ready yet waits for them instead of showing a
  /// blank frame.
  ///
  /// 🚨★★★I-41 (유저 2026-09-24): 「지금 위치가 그곳과 다르면 첫 언두는
  /// 그곳으로 이동만, 다음 언두가 편집을 되돌린다 … 리두는 대칭」. Standing
  /// elsewhere than the edit was made, the undo only WALKS there
  /// ([Standing.standOn]) and leaves the way back for redo.
  void undo() {
    _settleAndAdopt();
    final here = standingPlace;
    final gap = editingSession.gapGlobalFrame;
    if (_walkTo(undo: true) case final there?) {
      historyManager.leaveWalkBack(
        WalkBack(() {
          if (here != null) {
            standing.standOn(here);
          } else if (gap != null) {
            parkGlobalFrame(gap);
          }
        }),
      );
      standing.standOn(there);
      return;
    }
    historyPictures.step(
      undo: true,
      apply: () => _stepHistory(
        historyManager.undo,
        found: historyManager.undoFound,
      ),
    );
  }

  /// The mirror of [undo]: a redo whose edit was made elsewhere walks there
  /// first, and the walk an undo left behind takes the user back.
  void redo() {
    _settleAndAdopt();
    if (_walkTo(undo: false) case final there?) {
      standing.standOn(there);
      return;
    }
    historyPictures.step(
      undo: false,
      apply: () => _stepHistory(historyManager.redo),
    );
  }

  /// What the next [undo] — or, with [undo] false, [redo] — works out
  /// ahead of its step ([HistoryManager.workAhead]): null where the press
  /// only walks to the edit (I-41), or the step works nothing out. Settled
  /// first, as the press is, so it is asked of the step the press takes.
  WorkAhead? historyStepAhead({required bool undo}) {
    _settleAndAdopt();
    return _walkTo(undo: undo) == null
        ? historyManager.workAhead(undo: undo)
        : null;
  }

  /// Where the next [undo] — or redo — walks the user instead of stepping:
  /// the place its edit was made, while the user stands elsewhere (I-41).
  ///
  /// A gap is elsewhere too. ↩️Standing in one (no place) never walked
  /// (2026-09-24, unasked): the step was taken there, and a cel's pixels
  /// were refused at the gap's canvas — the undo did nothing (board
  /// `a-text-walked-into-a-gap-lands-at-its-size`).
  StandingPlace? _walkTo({required bool undo}) {
    final here = standingPlace;
    final there = undo ? historyManager.undoPlace : historyManager.redoPlace;
    return there != null &&
            (here == null || standing.isElsewhere(there, from: here))
        ? there
        : null;
  }

  /// ⚠️BEFORE the walk is decided, not inside the step. The last edit has
  /// settled where it left the user — a press is a new action — and work
  /// still in hand (a pending move) lands as an entry made HERE, which is
  /// what the press is for: asked first, the walk would carry the user away
  /// from it.
  void _settleAndAdopt() {
    historyManager.places.settle();
    historyManager.onBeforeUndoRedo?.call();
  }

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
  late final FoldersAndAttachments folders = FoldersAndAttachments(project: this, selection: this, changes: this, controllers: activeCutControllers, layerIds: layerIds, activeCut: _activeCutEdits, handOffOnFolderFold: standing.handOffCurrentRowOnFolderFold, keepStandingShown: standing.keepStandingShown);

  // The layer switches (Round 6): eye, mute, audio, blend mode, target kind.
  late final LayerSwitchVerbs layerSwitches = LayerSwitchVerbs(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, storyboardCursor: storyboardCursor);

  /// AUDIO-PRO R3: mid-run schedule refresh, fired by the history
  /// listener and by the SE solo — the one mix switch that bypasses
  /// history (mute, fader and pan are edits and undo).
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

  // ── the layer row drag: its own object, in its own file ─────────────
  //
  // A collaborator (session/layer_row_drag.dart): the row picked up in the
  // rail and where it may land — on a row, a track or an effect lane.
  late final LayerRowDrag layerRowDragVerbs = LayerRowDrag(project: this, changes: this, effectsAndFx: effectsAndFx, rowSelectionVerbs: rowSelectionVerbs, trackSe: trackSe, attachFxConfirm: attachFxConfirm);

  // ── a file held over the timeline: its own object, in its own file ──
  //
  // A collaborator (session/drags/media_placement_drag.dart): what a drop
  // would make, drawn while the file still hovers — on the ONE preview
  // channel every other drag publishes to, so 「끄는 동안 보이는 것」과
  // 「놓았을 때 생기는 것」이 같은 코드에서 나온다.
  late final MediaPlacementDrag mediaPlacement = MediaPlacementDrag(
    preview: dragPreview,
    layerById: layerById,
    cutFrameCount: () => activeCutFrameCount,
    drawnFrameCount: () => activeCutDrawnFrameCount,
    // The project's own lookup, not a scan here: five callers already ask
    // 「이 경로의 풀 항목」 through it.
    assetFor: (path) =>
        repository.currentProject?.mediaAssetByPath(path),
    // The conform's SYNCHRONOUS door: a hover cannot wait, and a sound the
    // conform has not answered for simply has no silhouette yet (the
    // length the landing uses is the one this returns).
    peaksFor: audioConformStore.peaksFor,
    frameRate: () => projectSettings.projectFrameRate,
    // 🚨An SE row is the TRACK's, so [layerById] — which walks the open
    // cut — never finds one. These are the doors `landSound` itself uses.
    seRowFor: trackSeGlobalLayerById,
    seWindow: () => trackSe.trackSeWindow,
  );

  /// Where a file being dragged stands on a row — the answer the silhouette
  /// is drawn from. It asks [dropSpotFor] first, so what is DRAWN and what
  /// a release DOES are the same question asked twice, never two rules.
  void showMediaPlacement(LayerId layerId, int frameIndex, String path) {
    final spot = dropSpotFor(layerId, frameIndex, path);
    switch (spot) {
      case SeCellSpot():
        mediaPlacement.showOnSeCell(
          layerId: layerId,
          frameIndex: frameIndex,
          path: path,
        );
      case RowFramesSpot():
        mediaPlacement.showOnFrames(
          layerId: layerId,
          frameIndex: frameIndex,
          path: path,
        );
      case ReferenceSwapSpot():
        mediaPlacement.showOnReference(layerId: layerId);
      case _:
        // Nowhere to land: nothing is drawn, which is what the chip's
        // 금지 표시 already says.
        mediaPlacement.clear();
    }
  }

  /// A file held over the LAYER AREA, in the gap [slot] of [displayLayers]:
  /// the rail's caret AND the row the drop would make, from ONE call.
  ///
  /// 🚨Two drawings of one hover, so they cannot disagree about where the
  /// row goes — the caret marks the gap and the silhouette stands in it
  /// (유저 2026-09-12, Q2). The caret keeps deciding whether a row may go
  /// there at all ([showPlacementCaret] refuses a sound and an illegal
  /// gap); the silhouette is drawn only where the same question said yes.
  void showLayerPlacement(List<Layer> displayLayers, int slot, String path) {
    layerRowDragVerbs.showPlacementCaret(displayLayers, slot, path);
    if (layerSlotSpotFor(displayLayers, slot, path) is LayerSlotSpot) {
      mediaPlacement.showOnLayerSlot(slot: slot, path: path);
    } else {
      // A sound goes to the SE rows whichever way it came in, so no row is
      // being made here and nothing stands in the gap.
      mediaPlacement.clear();
    }
  }

  /// The file left the layer area, or was let go: the caret and the row go
  /// together, because they arrived together.
  void clearLayerPlacement() {
    layerRowDragVerbs.clearPlacementCaret();
    mediaPlacement.clear();
  }

  /// The channel the workspace listens on when a drop wants a yes/no.
  ///
  /// 🚨Owned here rather than by a surface: TWO of them end a row drag, and
  /// a dialog raised by whichever happened to be on screen is a second copy
  /// of the sentence waiting to drift ([AttachFxConfirmController]).
  final AttachFxConfirmController attachFxConfirm = AttachFxConfirmController();

  // --- SE mix controls (AUDIO-PRO R1) ---------------------------------------
  // The solo set is [VisibilitySolo.soloedSeLayerIds], held by its toggle.

  /// Project-level sheet-header text (title/episode/artist) the timesheet
  /// document reads.
  TimesheetInfo get timesheetInfo => repository.requireProject().timesheetInfo;

  /// One undo step; no-op when unchanged.
  void updateTimesheetInfo(TimesheetInfo info) {
    cutCommandCoordinator.setTimesheetInfo(info);
    notifyListeners();
  }

  /// The 타임시트 서식 window's save — the work's sheet format and the paper
  /// of the cut [cutId] the sheet shows: one undo step, no-op when
  /// unchanged.
  void updateTimesheetFormat({
    required TimesheetInfo info,
    CutId? cutId,
    TimesheetSheetKind? kind,
  }) {
    cutCommandCoordinator.setTimesheetFormat(
      info: info,
      cutId: cutId,
      kind: kind,
    );
    notifyListeners();
  }

  // ── the layer marks: their own object, in their own file ────────────
  //
  // A collaborator (session/layer_marks.dart): the ● a row wears at a
  // frame — one row or every swept one — and every n koma down a block.
  late final LayerMarks layerMarks = LayerMarks(
    project: this,
    selection: this,
    changes: this,
    controllers: activeCutControllers,
    activeCut: _activeCutEdits,
    rangeSelections: rangeSelections,
  );

  // ── the instructions: their own object, in their own file ───────────
  //
  // A collaborator (session/instructions.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final Instructions instructionVerbs = Instructions(
    project: this,
    selection: this,
    changes: this,
    frameIds: this,
    controllers: activeCutControllers,
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
    retime: this,
    controllers: activeCutControllers,
    folders: folders,
    rangeSelections: rangeSelections,
    storyboardCursor: storyboardCursor,
    trackSe: trackSe,
    transitions: transitions,
    exposureVerbs: exposureVerbs,
    dragPreview: dragPreview,
  );

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
    acceptsPlacedFrames: acceptsPlacedFrames,
  );

  /// A trimmed file carried in as only its span ([TrimmedPieces]).
  late final TrimmedPieces trimmedPieces = TrimmedPieces(
    staging: mediaStagingStore,
    project: this,
    frameRate: () => projectSettings.projectFrameRate,
    soundPeaks: audioConformStore.ensurePeaksFor,
  );

  late final ProjectImportDoors importDoors = ProjectImportDoors(
    project: this,
    changes: this,
    renderCaches: renderCaches,
    landing: importLanding,
    fingerprints: mediaFingerprints,
    pool: mediaPool,
    conforms: audioConformStore,
    frameRate: () => projectSettings.projectFrameRate,
    holdBytes: projectFile.holdMediaBytes,
  );

  late final CutFolderImportDoor cutFolderDoor = CutFolderImportDoor(
    project: this,
    selection: this,
    changes: this,
    renderCaches: renderCaches,
    timeline: this,
    landing: importLanding,
    holdBytes: projectFile.holdMediaBytes,
  );

  // The TVPaint door (session/tvpp_import_door.dart). A .tvpp opens AS A
  // PROJECT — it holds several cuts — so unlike its sibling doors it lands
  // in a session born for it, as an .anicel does (I-7): what it does here
  // is bake the pictures the conversion planned, into the stores this
  // session was born with. (The clipboards it once emptied are the app's
  // now, and a project's arrival leaves them alone.)
  late final TvppImportDoor tvppDoor = TvppImportDoor(
    project: this,
    changes: this,
    renderCaches: renderCaches,
    file: projectFile,
    projectDoor: projectDoor,
    mediaPool: mediaPool,
  );

  // The CLIP STUDIO door (session/clip_import_door.dart) — a .clip opens AS
  // A PROJECT the way a .tvpp does, and what it does here is the same: bake
  // the pictures the plan made room for, into this session's stores, and
  // carry the sounds the file holds into its pool.
  late final ClipImportDoor clipDoor = ClipImportDoor(
    project: this,
    changes: this,
    renderCaches: renderCaches,
    file: projectFile,
    projectDoor: projectDoor,
    mediaPool: mediaPool,
  );

  bool disposed = false;

  // --- Voice recording, ADR, input meter, take preview ----------------------
  //
  // The section moved to [EditorVoiceRecording]. Unlike the settings block,
  // it did not come free: its constructor there lists the twenty-one session
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
    activeCutMediaStartFrame: () => activeCutMediaStartFrame,
    editingGlobalFrame: () => editingGlobalFrame,
    gapParkedGlobalFrame: () => editingSession.gapGlobalFrame,
    standingRow: () => currentRow,
    openSeLane: () => layerStack.addSeLane(),
    trackSeGlobalLayerById: trackSeGlobalLayerById,
    mintFrameId: mintFrameId,
    mediaAssets: () => mediaPool.mediaAssets,
    rememberMediaFingerprint: mediaFingerprints.rememberMediaFingerprint,
    staging: mediaStagingStore,
    frameRangeSelection: () => frameRangeSelection,
    trackFrameRangeSelection: () => trackFrameRangeSelection,
    notify: notifyListeners,
  );
  @override
  FrameId mintFrameId(LayerId layerId) => frame_ids.mintFrameId(layerId);

  // ── the storyboard cursor: its own object, in its own file ──────────
  //
  // A collaborator (session/storyboard_cursor.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final StoryboardCursor storyboardCursor = StoryboardCursor(project: this, selection: this, timeline: this, changes: this, frameIds: this, controllers: activeCutControllers, rangeSelections: rangeSelections, cells: cells, cutVerbs: cutVerbs, transitions: transitions);

  // --- Frame / cell state / commands -------------------------------------

  // ── the exposure verbs: their own object, in their own file ─────────
  //
  // A collaborator (session/exposure_verbs.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final ExposureVerbs exposureVerbs = ExposureVerbs(
    selection: this,
    project: this,
    changes: this,
    retime: this,
    controllers: activeCutControllers,
    camera: camera,
    rangeSelections: rangeSelections,
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

    activeCutControllers.timelineController.createDrawingFrameForLayer(
      layerId: layer.id,
      frameId: mintFrameId(layer.id),
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
    layerIds: layerIds,
    controllers: activeCutControllers,
    frameVerbs: frameVerbs,
  );

  // ── the cell instances: their own object, in their own file ─────────
  //
  // A collaborator (session/cell_instances.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final CellInstances cellInstances = CellInstances(project: this, selection: this, changes: this, frameIds: this, controllers: activeCutControllers, instructionVerbs: instructionVerbs, laneVerbs: laneVerbs, layerVerbs: layerVerbs, trackSe: trackSe, transitions: transitions, cells: cells, frameVerbs: frameVerbs, storyboardRows: storyboardRows);

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
    dragPreview: dragPreview,
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
    dragPreview: dragPreview,
  );

  // --- Which rows a block move takes part on --------------------------------
  //
  // A block moves by being selected and dragged as a range — along the frame
  // axis and across drawing layers, its cels travelling with it — through the
  // frame-range move ([rangeMove]), the one door since UI-R8 (#517).
  // ↩️Grabbing a drawing block's BODY was a drag of its own (R10-④b) until
  // then, and it went for good with the tests that alone still drove it
  // (2026-10-24).

  /// Whether [layerId] can take part in a block move (source or target):
  /// a plain drawing-section layer. Track-SE rows live on the global axis
  /// with audio attached; the rest of the standing-down is the shared
  /// retime law ([standsDownFromRetime]).
  @override
  bool blockMoveEligible(LayerId layerId) {
    // FREE attach rows move blocks like any drawing layer (UI-R21 #3) —
    // only the SYNCED ones stand down, which the shared law knows. Its
    // MOVING half only: a movie kept as a reference moves whole
    // ([standsDownFromRetime] says why it reshapes never).
    if (_timingIsNotItsOwn(layerId) || isTrackSeLayerId(layerId)) {
      return false;
    }
    final layer = layerById(layerId);
    return layer != null &&
        layer.kind.holdsDrawings &&
        layer.kind != LayerKind.se;
  }

  /// Whether a file dropped on [layerId]'s frame area may land there as new
  /// frames (유저 2026-09-11: 「이미지 · 참조 레이어의 프레임 영역 → 받지
  /// 않는다」): a row a dragged block may land on — that law, asked rather
  /// than restated, and it already turns an image row away (its one cel is
  /// pinned, [standsDownFromRetime]) — minus a reference row, whose cells
  /// come from its file.
  bool acceptsPlacedFrames(LayerId layerId) =>
      blockMoveEligible(layerId) && layerById(layerId)?.mediaReference == null;

  /// Where a file let go on [layerId]'s frame area, at [frameIndex], lands
  /// — or null when it lands nowhere. Frames are pixels, so only a file
  /// with pixels to bake lands on them ([importBakeAllowed] asks exactly
  /// that), and only on a row that takes frames ([acceptsPlacedFrames]).
  RowFramesSpot? frameDropSpot(LayerId layerId, int frameIndex, String path) =>
      acceptsPlacedFrames(layerId) &&
          importBakeAllowed(kind: mediaAssetKindForPath(path), placing: true)
      ? RowFramesSpot(layerId: layerId, frameIndex: frameIndex)
      : null;

  /// Where a file let go on ANY row lands — one question, whatever row the
  /// drop found: a picture on a row that takes frames ([frameDropSpot]), a
  /// SOUND on an SE row's empty cell (유저 2026-09-11: 「SE 행의 빈 칸 → 새
  /// 블록」), the file a REFERENCE row shows instead ([ReferenceSwapSpot],
  /// I-47 — the one row [acceptsPlacedFrames] turns frames away from, since
  /// its cells come from its file). Null when it lands nowhere, and the drop
  /// does nothing.
  ImportLayerSpot? dropSpotFor(LayerId layerId, int frameIndex, String path) {
    if (isTrackSeLayerId(layerId)) {
      final cut = activeCutOrNull;
      return cut == null
          ? null
          : _seCellSpotFor(
              layerId,
              // The ONE converter between the cut's frames and the track's:
              // the timeline's rows show the active cut's window.
              trackFrame: trackSe.trackSeWindow.toGlobalFrame(frameIndex),
              shownCell: frameIndex,
              path: path,
            );
    }
    final layer = layerById(layerId);
    if (layer != null && referenceSwapFor(layer, path) != null) {
      return ReferenceSwapSpot(layerId);
    }
    return frameDropSpot(layerId, frameIndex, path);
  }

  /// A SOUND on an SE row's empty cell, wherever the row showed it — the
  /// timeline's rows in the active cut's frames, the storyboard's in the
  /// track's.
  SeCellSpot? _seCellSpotFor(
    LayerId layerId, {
    required int trackFrame,
    required int shownCell,
    required String path,
  }) => _mayCarrySound(path)
      ? SeCellSpot(
          layerId: layerId,
          trackFrame: trackFrame,
          shownCell: shownCell,
        )
      : null;

  /// Whether [path] can put a SOUND on an SE row: a sound, or a movie the
  /// conform has not found silent (「소리 없는 영상이면 칩이 금지로
  /// 바뀐다」). A movie the conform has not answered yet is let through —
  /// its landing asks again, and lands nothing where there is nothing.
  bool _mayCarrySound(String path) => switch (mediaAssetKindForPath(path)) {
    MediaAssetKind.audio => true,
    MediaAssetKind.video =>
      audioConformStore.failureFor(normalizedMediaPath(path)) == null,
    _ => false,
  };

  /// Where a file let go on the LAYER AREA lands: a new row at the gap the
  /// rail's caret showed ([newRowInsertionForSlot]), 「레이어 영역(가로선) →
  /// 새 레이어」. A sound takes the SE rows' rule whichever way it came in
  /// ([_soundOnALayerArea]). Null where no new row may go, and the drop does
  /// nothing.
  ImportLayerSpot? layerSlotSpotFor(
    List<Layer> displayLayers,
    int slot,
    String path,
  ) {
    final sound = _soundOnALayerArea(path);
    if (sound != null) {
      return sound;
    }
    final cut = activeCutOrNull;
    final index = cut == null
        ? null
        : newRowInsertionForSlot(
            stack: cut.layers,
            displayRows: displayLayers,
            slot: slot,
          );
    return index == null ? null : LayerSlotSpot(index);
  }

  /// A SOUND let go on a LAYER AREA — the timeline's rail or the
  /// storyboard's — lands by the SE rows' rule whichever way it came in
  /// (round 6), and the canvas's spot is the one that already says so.
  ImportLayerSpot? _soundOnALayerArea(String path) =>
      mediaAssetKindForPath(path) == MediaAssetKind.audio
      ? const AboveActiveLayerSpot()
      : null;

  /// Where a file let go on a STORYBOARD row lands, at [globalFrame] — the
  /// storyboard's [dropSpotFor], asked in the track frames that panel
  /// draws: a picture on a track's frames is a NEW cut where Create Cut
  /// would put one there, a sound on an SE row's empty cell a new block
  /// from that cell — between cuts too (유저 2026-09-12: 「타임라인이랑 같은
  /// 법으로」). Null where it lands nowhere, and the drop does nothing.
  ImportLayerSpot? storyboardDropSpotFor(
    TimelineRowAddress row,
    int globalFrame,
    String path,
  ) => switch (row) {
    TrackRowAddress() => _newCutSpotAt(globalFrame, path),
    LayerRowAddress(:final layerId) when isTrackSeLayerId(layerId) =>
      _seCellSpotFor(
        layerId,
        trackFrame: globalFrame,
        shownCell: globalFrame,
        path: path,
      ),
    _ => null,
  };

  /// A NEW cut where Create Cut would put one at [globalFrame]
  /// ([CutPlacement.cutCreationPlanAt]). Only a file with pixels makes a cut
  /// there, the question a row's frames ask too ([frameDropSpot]); a sound's
  /// place is the SE rows.
  NewCutSpot? _newCutSpotAt(int globalFrame, String path) {
    if (!importBakeAllowed(kind: mediaAssetKindForPath(path), placing: true)) {
      return null;
    }
    final plan = cutPlacement.cutCreationPlanAt(globalFrame);
    return NewCutSpot(
      index: plan.index,
      leadingGapFrames: plan.leadingGapFrames,
    );
  }

  /// Where a file let go on the STORYBOARD's rail lands: a sound by the SE
  /// rows' rule, as on the timeline's rail. A picture lands nowhere — the
  /// layer area's answer for one is a new row at a gap of the active cut's
  /// stack, and no row of that stack is on this rail (유저 2026-09-12:
  /// 「레이어 영역쪽은 se 레이어를 늘리는거 말곤 할게없으니 … 법 최대한
  /// 유지하면서」).
  ImportLayerSpot? storyboardRailDropSpotFor(String path) =>
      _soundOnALayerArea(path);

  // ── the shove: its own object, in its own file ────────────────────────
  //
  // Push and pull, aimed at whatever is selected (session/block_shift.dart):
  // the frame-axis scope, its axis translation, the slack and the commit,
  // plus the aim that hands a cut selection to [cutShift] instead.
  late final BlockShift blockShift = BlockShift(
    project: this,
    selection: this,
    changes: this,
    retime: this,
    trackSe: trackSe,
    controllers: activeCutControllers,
    cutShift: cutShift,
    rangeSelections: rangeSelections,
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
    rangeSelections: rangeSelections,
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

  void _hydrateShownMovieCels() {
    // A notify can arrive mid-teardown; the stores it would fill are going.
    if (disposed) {
      return;
    }
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    unawaited(movieCels.hydrate(cut, editingFrameCursor.value));
  }

  void _publishCutLocalLaneRange() {
    if (disposed) {
      return;
    }
    final span = laneRangeSelection.value;
    if (span == null || !isTrackSeLayerId(span.layerId)) {
      cutLocalLaneRangeSelection.value = span;
      return;
    }
    final offset = rowAxisOffset(span.layerId);
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
    dragPreview: dragPreview,
    laneVerbs: laneVerbs,
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
    return global == null ? null : trackSe.trackSeWindow.displayLayer(global);
  }

  /// The layer ops COMMIT against: the GLOBAL form for track-SE rows.
  @override
  Layer? commitLayerById(LayerId layerId) => isTrackSeLayerId(layerId)
      ? trackSeGlobalLayerById(layerId)
      : layerById(layerId);

  // ── what a block move lands by: its own object ──────────────────────
  //
  // A collaborator (session/block_move_commands.dart), handed to the range
  // move, which lands every block move.
  late final BlockMoveCommands blockMoveCommands = BlockMoveCommands(
    project: this,
    renderCaches: renderCaches,
    pixelEditing: pixelEditing,
  );

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
    laneVerbs: laneVerbs,
    folders: folders,
    rangeSelections: rangeSelections,
    rowSpans: rowSpans,
    blockMove: blockMoveCommands,
    transitions: transitions,
    trackSe: trackSe,
    retime: this,
    dragPreview: dragPreview,
  );

  /// The door a collaborator announces through — `notifyListeners` is
  /// protected, and a collaborator is not a subclass.
  @override
  void notifyChanged() => notifyListeners();

  /// Every announcement first lets the verbs' row follow an active layer the
  /// program moved ([Standing.followActiveLayer], F-183 ③) — the one point
  /// every door that moves it passes, collaborators' and this class's own.
  /// The conte rows the selection and the rail's stand hold follow their
  /// rows' seats there too ([Standing.followConteSeats], F-322).
  @override
  void notifyListeners() {
    rowSelectionVerbs.followConteSeats();
    standing.followConteSeats();
    standing.followActiveLayer();
    super.notifyListeners();
  }

  // --- Run-edge NEW FRAMES drag (UI-R8 [+] handle) --------------------------

  // ── the run frames add drag: its own object ─────────────────────────
  //
  // A collaborator (session/run_frames_add_drag.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final RunFramesAddDragVerbs runFramesAdd = RunFramesAddDragVerbs(
    project: this,
    changes: this,
    controllers: activeCutControllers,
    rangeSelections: rangeSelections,
    dragPreview: dragPreview,
  );

  // --- Run-edge properties (UI-R9 #10 N/H/R tags) ----------------------------

  /// The active cut's conte 尺 — where a row that TILES its cut stops (the
  /// conte's blocks); zero without a cut.
  @override
  int get activeCutFrameCount => activeCutOrNull?.duration ?? 0;

  /// The run-behavior fill boundary: hold/repeat edges fill to the cut's
  /// DRAWN end (F-227), the number the ruler's blue line stands at.
  @override
  int get activeCutDrawnFrameCount => activeCutSpan.activeCutDrawnFrameCount;

  /// Whether the live frame-range selection can SCOPE a repeat pattern on
  /// this run edge (UI-R10 #5 rules: the selection must cover the edge
  /// block and cut the run short of the other end) — the tag flyout shows
  /// its explicit "Repeat selection" entry from this (UI-R19 #2). Any row
  /// the selection spans asks it, not only the one its drag began on
  /// (F-410).
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
    if (run == null || selection == null || !selection.coversLayer(layerId)) {
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
  ///
  /// A MOVIE kept as a reference stands down too, for its own reason: its
  /// positions count from its block's start, so a split, a gap or a squeeze
  /// would restart or skip the movie — its timing goes per-frame only once
  /// it is rasterized (the video spec the user approved, 2026-09-11). It is
  /// the one row whose timing IS its own to MOVE — whole, and trimmed at
  /// either end — so [blockMoveEligible] asks [_timingIsNotItsOwn], not
  /// this.
  @override
  bool standsDownFromRetime(LayerId layerId) =>
      _timingIsNotItsOwn(layerId) || _playsAMovie(layerId);

  /// The rows whose timing is somebody else's: a synced attach row follows
  /// its base, and an image row's one block is pinned.
  bool _timingIsNotItsOwn(LayerId layerId) =>
      folders.isSyncedAttachedLayerId(layerId) ||
      rowSpans.isSingleCelLayerId(layerId);

  bool _playsAMovie(LayerId layerId) {
    final layer = layerById(layerId);
    return layer != null && isMovieReference(layer);
  }

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
  PillSubject get deleteSubject => deleteSubjectFor(cutsAreThisPanels: true);

  /// [deleteSubject], asked of a PANEL — see [editInstanceSubjectFor] for
  /// why the cuts rung is a question and not a given (R5q1).
  PillSubject deleteSubjectFor({required bool cutsAreThisPanels}) =>
      pillSubjectOn(
        // A band that NAMES cuts — see
        // [StoryboardToolbarPanelContext.deleteSubject].
        cuts:
            cutsAreThisPanels &&
            storyboardRows.storyboardSelectedCutIds.isNotEmpty,
        layers: () => rowsHoldWhatDeleteTakes,
        cells: () => cells.canDeleteCellAtCurrentFrame,
      );

  /// THE ROWS RUNG of the shared delete, asked by both panels' ladders:
  /// whether the selected rows hold a layer it may delete, or an effect an
  /// fx header row names ([effectsToDeleteOfRows], F-476).
  bool get rowsHoldWhatDeleteTakes =>
      layerVerbs.deletableSelectedLayerIds().isNotEmpty ||
      effectsToDeleteOfRows().isNotEmpty;

  /// The effects the shared delete takes of the selected ROWS besides their
  /// layers: what their fx header rows name on rows that stay (F-476,
  /// [LaneVerbs.effectsNamedBySelectedRows]) — a row that goes takes its
  /// chain with it.
  List<({Layer row, List<EffectId> effects})> effectsToDeleteOfRows() {
    final layers = layerVerbs.deletableSelectedLayerIds();
    final going = {
      ...layers,
      for (final row in layerVerbs.rowsHeldBy(layers)) row.id,
    };
    return [
      for (final named in laneVerbs.effectsNamedBySelectedRows)
        if (!going.contains(named.row.id)) named,
    ];
  }

  /// Runs whatever [deleteSubject] names. One undo step either way — the cell
  /// path already composes its own.
  void deleteSelectionSubject({bool cutsAreThisPanels = true}) {
    switch (deleteSubjectFor(cutsAreThisPanels: cutsAreThisPanels)) {
      case PillSubject.cuts:
        cutVerbs.deleteActiveCut();
      case PillSubject.layers:
        final effects = effectsToDeleteOfRows();
        historyManager.runAsOneStep('Delete rows', () {
          laneVerbs.removeEffectsNamedByRows(effects);
          layerVerbs.deleteSelectedLayers();
        });
      case PillSubject.cells:
        cells.deleteCellAtCurrentFrame();
      case PillSubject.nothing:
        break;
    }
  }

  /// 🗣️I-78 — WHAT the shared MERGE would merge right now: the selected
  /// rows it makes one, else the band's blocks it makes one per row
  /// (round ③, Q4) — the pill's one ladder ([pillSubjectOn], T25). A band
  /// of cuts on the panel whose noun they are holds nothing a merge takes.
  PillSubject mergeSubjectFor({required bool cutsAreThisPanels}) =>
      pillSubjectOn(
        cuts:
            cutsAreThisPanels &&
            storyboardRows.storyboardSelectedCutIds.isNotEmpty,
        layers: () => layerMerging.mergesSelection,
        cells: () => layerMerging.mergesBand,
      );

  /// 🚨I-45 — WHAT the link-independent button would unlink right now, on
  /// the TIMELINE: the selected linked rows, else the frame axis.
  ///
  /// 유저 2026-09-20: 「링크 독립버튼. 위치는 타임라인의 공용 알약부분? 프레임
  /// 독립시키거나 레이어나 컷이나」, answered 2026-09-23 (link-independent-
  /// button): 「정확히는 다른 편집버튼등의 로직 그대로 따라감 … 선택안하면
  /// 현재프레임, 선택하면 해당 선택한 소재가 기준임」 — so it is the shared
  /// pill's one ladder ([pillSubjectOn]) with the linked predicates.
  ///
  /// ⚠️No cuts rung here: cuts are the storyboard's noun (R5q1), and its
  /// context resolves them through its own edit target.
  PillSubject get unlinkSubject => pillSubjectOn(
    cuts: false,
    layers: () => layerVerbs.linkedSelectedLayerIds().isNotEmpty,
    cells: () => cells.canUnlinkCells,
  );

  /// Runs whatever [unlinkSubject] names — one undo step either way.
  void unlinkSelectionSubject() {
    switch (unlinkSubject) {
      case PillSubject.layers:
        layerVerbs.unlinkSelectedLayers();
      case PillSubject.cells:
        cells.unlinkCells();
      case PillSubject.cuts:
      case PillSubject.nothing:
        break;
    }
  }

  /// Whether a live band names rows this press would MISS.
  ///
  /// The ACTIVE-ROW verbs — X-here, the ● mark, the cell rename and
  /// 잘라내기 — all resolve against the active layer. A band covering that
  /// row is served: 잘라내기 splices exactly the swept span (the clipboard
  /// asks this of its own place — [ClipboardPlace]), and the playhead verbs
  /// act on the row the user highlighted. A band naming only OTHER rows is a
  /// different statement, and acting on the active row then edits something the
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
    // R15-⑤: a live STROKE refuses the seek outright — a
    // flip under an in-flight edit tore widgets down inside the build
    // phase (red screens) and could land the edit on the wrong cel.
    if (strokeInFlight) {
      return;
    }
    historyManager.places.leave();
    // A direct cut-local seek leaves any gap parking (R16-⑥); the global
    // seek re-parks AFTER this call when it lands in a gap.
    editingSession.gapGlobalFrame = null;
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

  /// The stroke the main canvas has in flight — what makes the cel it draws
  /// count as drawn from pen-down (`LayerStack.liveStrokeDraws`), where it
  /// [StrokeInFlight.paints].
  ///
  /// ⛔NOT [brushInputActive] (F-482, 유저 2026-10-27: 「없던 블록에서
  /// 지우는 동작은 블록 채우지 않도록 근본/구조적으로」): that says a stroke
  /// is in flight on ANY surface — a sheet's, an eraser's — and read as
  /// 「the active cel is being drawn」, an eraser on an empty block turned it
  /// white until the pen lifted, and so did a pen on the timesheet.
  final ValueNotifier<StrokeInFlight> canvasStroke =
      ValueNotifier<StrokeInFlight>(StrokeInFlight.none);

  /// The main canvas's stroke goes up or lands: [canvasStroke], and a
  /// stroke in flight like any surface's ([setBrushInputActive]).
  void setCanvasStroke(StrokeInFlight stroke) {
    canvasStroke.value = stroke;
    setBrushInputActive(stroke != StrokeInFlight.none);
  }

  /// R15-⑤: a live STROKE blocks frame seeks, scrubs and cut switches
  /// entirely — the playhead moves when the pen lifts, never under it.
  ///
  /// 🗣️F-196 (유저 2026-09-27): 「애초에 잠그는 기능을 싹 다 빼고 필요한거만
  /// 보고해」. This is the one that is needed, MEASURED with it switched off
  /// (`only_a_stroke_holds_the_playhead_test`): a ruler scrub or a cut switch
  /// under the pen threw the stroke away, and a palm on the ruler is all it
  /// takes. A seek alone was already safe — the canvas pins a live stroke to
  /// its cel — but the playhead keeps one rule under the pen.
  ///
  /// ↩️A selection drag held it too, and no longer does: the selection
  /// layer carries a session to the next cel on a seek, and a float writes
  /// nothing until it lands, so nothing is lost ([RangeSelections]'s hold
  /// is only the prerender's now).
  bool get strokeInFlight => brushInputActive.value;

  // --- Track-global frame axis (R15-①) -----------------------------------

  /// THE structural model of the active track's timeline: cuts occupy
  /// [start, end) global ranges and the frames between them are REAL
  /// addresses (a layer timeline's empty frames, at track scale). The
  /// session playhead, the storyboard and the timeline consume THIS ONE
  /// axis — change it and every panel changes together.
  ///
  /// The selected track's axis ([ProjectSettings.axisForTrack], kept beside
  /// the layout it narrows) — every track's when that one has no cut.
  @override
  TrackFrameAxis trackFrameAxis() {
    final axis = projectSettings.axisForTrack(selectedTrackId);
    return axis.isEmpty ? projectSettings.projectAxis() : axis;
  }

  // The gap parking — the editing playhead standing where no cut is — lives
  // beside the active cut it is the other answer to
  // ([EditingSessionState.gapGlobalFrame]; the audit's twenty-first family,
  // 2026-09-29). `gapParkedGlobalFrame` went with it: a second name for the
  // same field.

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
  /// ★[EditingSessionState.playheadInGap] gets sharper for free: `isGap`
  /// can now answer
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
    final parked = editingSession.gapGlobalFrame;
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
  /// empty states and the canvas shows the void. QUIET: [parkGlobalFrame]
  /// notifies, batched with the parking and the commit signal.
  void _deselectActiveCutForGap() {
    if (editingSession.activeCutId == null) {
      return;
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
    clearFrameRangeSelection();
    activeCutControllers.rebuild();
  }

  /// V-TRACK selection (UI-R18 #6): tapping a V row makes THAT track's
  /// cut under the current global playhead the ACTIVE cut — every track
  /// reads the one shared global index, each independently (the V-row
  /// fx/eye subject rule). The landing keeps the global position: the new
  /// cut's local frame is the same global frame. A gap on the tapped
  /// track is a no-op, like the fx/eye buttons there.
  void selectTrackCutAtPlayhead(TrackId trackId) {
    if (strokeInFlight) {
      return;
    }
    // The TRACK is what the tap selected, so it is taken whether or not a
    // cut is found under the playhead — a gap on the tapped track is still
    // a no-op for the active cut, but the selection itself no longer
    // evaporates on the way, and the rail repaints even when nothing below
    // announces.
    selectTrackRow(trackId);
    final globalFrame = editingGlobalFrame;
    // The tapped track's own axis — its cuts, and where each one's own
    // frames stand on it.
    final axis = projectSettings.axisForTrack(trackId);
    final entry = axis.isGap(globalFrame) ? null : axis.ownerOf(globalFrame);
    if (entry != null) {
      if (entry.cutId != activeCutId) {
        selectCut(entry.cutId);
      }
      selectFrameIndex(axis.localIn(entry, globalFrame));
      return;
    }
    // A GAP on the tapped track PARKS there (user 2026-07-29, superseding
    // UI-R18 #6's no-op): selecting a row makes its current index the
    // active state, and with no cut to take that state is the parked
    // track stack — the display path (#768) that made a gap worth
    // standing on.
    parkGlobalFrame(globalFrame);
  }

  /// Moves the playhead to [globalFrame] and takes NO cut active — the
  /// parked state, whatever sits at that frame.
  ///
  /// A gap lands here because there is no cut to take — that is the whole
  /// of it now. The storyboard's SE rows used to land here too (feedback
  /// #7: pressing a sound says where you are, not which cut you are
  /// editing), on the reading that the active cut answers only to picking a
  /// cut on the row that HAS cuts. ⑭ retired that: one track means the
  /// index names one cut, so a row press seeks like any other and only a
  /// GAP still parks. A caller that parks a frame a cut covers declares
  /// that cut's picture hidden, so nothing shows there (the V-row eye,
  /// UI-R13 #2). ↩️The live scrub parked over other cuts' frames too, as a
  /// preview, until it crossed into them (I-57 ②).
  ///
  /// ⛔THE park. A stop in a gap and the V-row eye wrote these steps out
  /// for themselves and missed the settle and the live-stroke hold this
  /// one keeps (2026-09-29); they come through here now.
  ///
  /// 🚨A track with no cut is ALL gap, and parks like one (F-341): the
  /// storyboard's playhead, its rows and its run stand on the track's axis,
  /// which a cut does not make. ↩️An empty axis refused the park — a guard
  /// the first global seek needed for its `entries.first` (R15-1), outlived
  /// by the gap parking that replaced that line: a run stopped on a track
  /// with no cut left no playhead behind.
  void parkGlobalFrame(int globalFrame) {
    if (strokeInFlight) {
      return;
    }
    historyManager.places.leave();
    editingSession.gapGlobalFrame = globalFrame;
    _deselectActiveCutForGap();
    frameSeekCommitted.value += 1;
    notifyListeners();
  }

  /// THE canonical seek: a global frame in. Inside a cut it selects
  /// cut + local frame; in a GAP it deselects the cut ENTIRELY (UI-R9 #3)
  /// and PARKS there — the stored global addresses the gap exactly,
  /// including the leading gap before the first cut, and the canvas shows
  /// the no-cut void.
  ///
  /// [onAxis] lands the frame on a SPECIFIC track's axis instead of the
  /// selected track's. A caller that computed its move on one axis must
  /// land it on the same one — resolving on a different track would put
  /// the playhead in a cut the move never chose.
  @override
  void selectGlobalFrame(int globalFrame, {TrackFrameAxis? onAxis}) {
    if (strokeInFlight) {
      return;
    }
    final axis = onAxis ?? trackFrameAxis();
    final local = axis.localOf(globalFrame);
    if (local == null || axis.isGap(globalFrame)) {
      // A GAP (leading, mid-track, or a track with no cut — F-341): no cut
      // there — park + deselect.
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
    brushInputActive: brushInputActive,
    editingFrameCursor: editingFrameCursor,
    playbackRig: playbackRig,
  );

  // ── the onion skin: its own object, in its own file ─────────────────
  //
  // A collaborator (session/onion_skin.dart). Callers name it: a forwarder here
  // would be a second name for the same verb (round 8, G4).
  late final OnionSkin onionSkin = OnionSkin(
    settings: appSettings.onionSkinSettings,
    project: this,
    selection: this,
    changes: this,
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
    // Asked when a font is looked for, and not before: a session that
    // carries none never builds the library.
    deviceFontFile: (file) => fontLibrary.pathOfFontHeld(file),
    openElsewhere: _fileIsOpenElsewhere,
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
    sheetPhotos: sheetPhotoEdits,
  );

  // ── the fonts registered with the project: their own object ─────────
  //
  // A collaborator (session/project_fonts.dart). The list is the project's
  // and the bytes are [projectFile]'s; this is the registering and the
  // taking out.
  late final ProjectFonts projectFonts = ProjectFonts(
    project: this,
    changes: this,
    file: projectFile,
  );

  late final ProjectFileDoor projectDoor = ProjectFileDoor(
    file: projectFile,
    project: this,
    selection: this,
    changes: this,
    timeline: this,
    controllers: activeCutControllers,
    renderCaches: renderCaches,
    staging: mediaStagingStore,
    grants: mediaGrants,
    fingerprints: mediaFingerprints,
    audioConformStore: audioConformStore,
    mediaPool: mediaPool,
    liveStrokeLanding: liveStrokeLanding,
    solo: visibilitySolo,
    failedCopies: failedSaveCopies,
    keepStandingShown: standing.keepStandingShown,
    playback: playbackRig,
    timelineZoom: timelineZoom,
    panelViews: panelViews,
    laneGraphs: railView.laneGraphs,
    mediaFileViews: mediaFileViews,
  );

  /// Every FAILED COPY (실패본) this run holds — the work saves could not
  /// put in their project files, kept until the run ends (유저 2026-09-23,
  /// whole-write-temp-beside-the-file). Here rather than on the project
  /// file because it outlives any one binding: a person who opened another
  /// project can still back up the last one's.
  ///
  /// 🚨ONE per app, handed to every open project by the shell (I-7): the
  /// list is the RUN's, so a tab that closed leaves its copy on the list the
  /// other tabs offer. A session built without one keeps its own.
  final FailedSaveCopies failedSaveCopies;

  /// See [ProjectFile.isOpenElsewhere] — the shell's answer, handed down.
  final bool Function(String path)? _fileIsOpenElsewhere;

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
  /// layer, the canvas scrub preview) follow pointer-fast without a session
  /// notify rebuilding the tree.
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
  ///  * a scrub that walks into a gap parks instead, moving
  ///    [EditingSessionState.gapParkingListenable] and NOT the cursor —
  ///    which is why the
  ///    storyboard's shift pair stayed lit past the film's end while the
  ///    rest of its bar had already caught up.
  ///
  /// ⛔Playback is deliberately not a channel here: none of these three
  /// move while it runs, so a bar cannot start re-deriving 24 times a
  /// second because the film is playing.
  late final Listenable playheadMoved = Listenable.merge([
    frameSeekCommitted,
    editingFrameCursor,
    editingSession.gapParkingListenable,
  ]);

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
