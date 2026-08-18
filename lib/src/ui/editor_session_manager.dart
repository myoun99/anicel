import 'dart:async' show Timer;
import 'dart:collection' show SplayTreeMap;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/foundation.dart';

import '../controllers/default_cut_helpers.dart'
    show createDefaultCut, defaultCutCanvasSize;
import '../controllers/default_layer_helpers.dart';
import '../models/import/cut_folder_parse.dart';
import '../models/import/tvp_csv_parse.dart';
import '../models/import/tvp_json_parse.dart';
import '../services/commands/import_media_command.dart';
import '../services/commands/reorder_track_command.dart';
import '../services/import/media_identity_reader.dart';
import '../services/media/media_fingerprints.dart';
import '../services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32;
import '../services/media/media_byte_source.dart';
import '../services/media/project_media_sources.dart';
import '../services/import/media_import_planner.dart';
import '../services/import/psd_expand_import.dart';
import '../services/import/raster_cel_import.dart';
import '../services/import/tvp_json_import_planner.dart';
import '../services/pdf/pdf_render_service.dart';
import '../services/project_lookup.dart'
    show cutIdOfLayer, projectAudioSourcePaths, requireLayerAnywhere;
import '../models/app_language.dart';
// The six settings stores are injected THROUGH this class into
// [EditorAppSettings], so their types stay in this file's constructor
// signature even though nothing here reads them.
import '../services/persistence/app_language_settings_store.dart';
import '../services/persistence/app_accent_settings_store.dart';
import '../services/persistence/app_workspace_colors_store.dart';
import '../services/persistence/app_input_settings_store.dart';
import '../services/persistence/app_save_settings.dart';
import '../services/persistence/app_save_settings_store.dart';
import '../services/persistence/audio_sync_settings_store.dart';
import 'brush/brush_tool_state.dart' show CanvasTool;
import 'input/app_input_settings.dart';
import 'session/drags/audio_clip_offset_drag.dart';
import 'session/drags/cut_move_drag.dart';
import 'session/drags/movie_end_drag.dart';
import 'session/drags/row_order_drag.dart';
import 'session/drags/run_frames_add_drag.dart';
import 'session/drags/transition_edge_drag.dart';
import 'session/editor_app_settings.dart';
import 'session/editor_voice_recording.dart';
import 'theme/app_accents.dart';
import '../controllers/active_cut_helpers.dart';
import '../controllers/editing_session_state.dart';
import '../controllers/layer_controller.dart';
import '../controllers/timeline_controller.dart';
import '../models/attached_layer_mount.dart';
import '../models/attached_layer_resolve.dart';
import '../models/attached_mode.dart';
import '../models/attached_placement.dart';
import '../models/bitmap_surface.dart';
import '../models/audio_clip.dart';
import '../models/brush_frame_key.dart';
import '../models/conte/conte_ink_keys.dart';
import '../models/envelope/cut_envelope_ink_keys.dart';
import '../models/camera_instruction.dart';
import '../models/camera_pose.dart';
import '../models/canvas_point.dart';
import '../models/canvas_resize_anchor.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/cut_camera.dart';
import '../models/drawing_guide.dart';
import '../models/transform_track.dart';
import '../models/cut_id.dart';
import '../models/cut_warm_extent.dart';
import '../models/cut_lead_edge_plan.dart';
import '../models/exposure_memo.dart';
import '../models/layer_folder.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import '../models/key_range_move.dart';
import '../models/layer_kind.dart';
import '../models/layer_mark.dart';
import '../models/layer_section_defaults.dart';
import '../models/media_asset.dart';
import '../models/onion_skin_settings.dart';
import '../models/timesheet_document.dart' show timesheetMemoInstructionLine;
import '../models/project_background.dart';
import '../models/timesheet_info.dart';
import '../models/project.dart';
import '../models/project_frame_rate.dart';
import '../models/row_block_shift.dart';
import '../models/property_track.dart';
import '../models/range_snap.dart';
import '../models/se_name_tag.dart';
import '../models/storyboard_coverage.dart';
import '../models/text_cel_style.dart';
import '../models/timeline_coverage.dart';
import '../models/flip_column_step.dart';
import '../models/timeline_exposure.dart';
import '../controllers/cut_duplicate_helpers.dart' show duplicateFrameContent;
import '../models/timeline_splice.dart';
import '../models/delete_subject.dart';
import '../models/edit_instance_subject.dart';
import '../models/timeline_selection_kind.dart';
import '../models/timeline_frame_range.dart';
import '../models/timeline_repeat.dart';
import '../models/timeline_row_address.dart';
import '../models/track.dart';
import '../models/track_frame_range.dart';
import '../models/track_id.dart';
import '../models/track_se_window.dart';
import '../models/track_transform_lane_carrier.dart';
import '../models/transition_geometry.dart';
import '../services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import '../services/brush_frame_store.dart';
import '../services/camera_pose_resolver.dart';
import '../services/clipboard/layer_copy_payload.dart';
import '../services/commands/convert_to_linked_cut_plan.dart';
import '../models/brush_frame_cache_invalidation.dart';
import '../models/playback_quality.dart';
import '../services/cut_frame_composite_plan.dart';
import '../services/se_name_tag_plan.dart';
import '../services/playback/editor_cache_invalidation_hub.dart';
import '../services/playback/playback_frame_mapping.dart';
import 'canvas/canvas_layer_stack_view.dart';
import 'canvas/layer_pose_paint.dart';
import 'dev_profile.dart';
import 'playback/audio_device_transport.dart';
import 'playback/audio_playback_sync.dart';
import 'playback/audio_scrubber.dart';
import 'playback/audio_sync_settings.dart';
import 'playback/audioplayers_clip_player.dart';
import 'playback/canvas_playback_controller.dart';
import 'playback/cut_frame_composite_cache.dart';
import 'playback/layer_frame_image_cache.dart';
import 'playback/playback_cache_budget.dart';
import 'playback/playback_prerender_scheduler.dart';
import 'storyboard_layer_policy.dart';
import 'text/app_strings.dart';
import 'text/text_cel_render.dart';
import 'widgets/cursor_notice.dart';
import '../models/track_frame_axis.dart';
import 'storyboard_timeline_layout.dart';
import '../models/drawing_block_move.dart';
import '../models/multi_row_range_move.dart';
import '../services/command.dart';
import '../services/commands/cut_command_coordinator.dart';
import '../services/commands/cut_command_input_planner.dart'
    show nextFolderName;
import '../services/commands/rekey_brush_frames_command.dart';
import '../services/commands/update_layer_transform_enabled_command.dart';
import '../services/commands/update_cut_camera_command.dart';
import '../services/commands/update_layer_fill_reference_command.dart';
import '../services/commands/set_cut_guides_command.dart';
import '../services/commands/update_layer_instructions_command.dart';
import '../services/commands/update_layer_mark_command.dart';
import '../services/commands/update_layer_timeline_command.dart';
import '../services/commands/update_layer_timesheet_command.dart';
import '../services/commands/update_project_audio_sample_rate_command.dart';
import '../services/commands/update_project_frame_rate_command.dart';
import '../services/commands/update_project_trailing_frames_command.dart';
import '../services/onion_skin_plan.dart';
import '../services/persistence/project_autosave_service.dart';
import '../services/persistence/anicel_file_service.dart';
import '../services/commands/cut_reorder_planner.dart';
import '../native/qa_audio_device.dart' show QaAudioDevice;
import '../native/qa_native_engine.dart' show QaNativeEngine;
import 'playback/audio_input_monitor.dart';
import 'playback/audio_playback_schedule.dart' show ScheduledAudioClip;
import '../services/audio/audio_conform_pipeline.dart' show ConformCacheLayout;
import '../services/audio/conform_cache_maintenance.dart'
    show pruneConformCache;
import '../services/persistence/folder_grant.dart'
    show FolderGrant, FolderPicker;
import '../services/persistence/anicel_project_archive.dart'
    show projectMediaPaths, remapProjectMediaPaths;
import '../services/audio/audio_peaks_extractor.dart' show AudioPeaks;
import 'playback/audio_recorder.dart';
import '../services/audio/audio_conform_runner.dart' show runConformHere;
import '../services/commands/track_se_layer_commands.dart';
import '../services/commands/track_transition_commands.dart';
import '../services/history_manager.dart';
import '../services/project_repository.dart';
import 'audio/audio_conform_store.dart';
import 'brush/brush_canvas_panel.dart';
import 'brush/brush_editor_selection.dart';
import 'timeline/instruction_span_editing.dart';
import 'timeline/layer_drop_policy.dart'
    show detachLandingIndex, resolveLayerDrop;
import 'timeline/layer_row_drag.dart'
    show LayerRowDragState, LayerRowDragSubject;
import 'timeline/property_lane_model.dart'
    show TimelineDisplayRow, folderAggregateRuns;
// ⑨: the row selection grows through the SAME span law the cell selection
// uses — the rail's own drawn row list.
import 'timeline/timeline_row_span_resolver.dart'
    show resolveSelectionSpanRows;
import 'timeline/timeline_current_row.dart' show currentRowIsInsideGroup;
import 'timeline/layer_label_controls.dart' show layerKindShowsBlendControl;
import 'timeline/layer_timeline_display_adapter.dart'
    show horizontalLayerDisplayOrder;
import 'timeline/timeline_cell_exposure_state.dart';
import 'timeline/timeline_drag_preview.dart';
import 'timeline/timeline_section_policy.dart';
import 'timeline/effect_lane_editing.dart'
    show
        effectLaneKeyFrames,
        effectsWithEnabledToggled,
        effectsWithLaneKeyRemoved,
        effectsWithLaneRangeNamed,
        effectsWithLaneKeyToggled,
        effectsWithLaneSpanKeysShifted,
        effectsWithGroupReset;
import 'timeline/effect_lane_policy.dart'
    show effectLaneDisplayOrder, effectLaneSpan, parseEffectLaneId;
import 'timeline/transform_lane_editing.dart'
    show
        transformLaneKeyFrames,
        transformTrackWithLaneKeyRemoved,
        transformTrackWithLaneRangeNamed,
        transformTrackWithLaneKeyToggled,
        transformTrackWithLaneSpanKeysShifted,
        transformTrackWithGroupReset;
import 'timeline/se_name_tag_lane_policy.dart'
    show laneIsSeNameTag, seNameTagLaneSpan;
import 'timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder, transformLaneSpan;

/// A planned SE row-change pair in COMMIT (global track) form: the source
/// row after its blocks leave, the target row after they arrive.
typedef SeRowMovePair = ({
  LayerId sourceId,
  LayerId targetId,
  Layer sourceBefore,
  Layer sourceAfter,
  Layer targetBefore,
  Layer targetAfter,
});

/// Owns the editable project session for [HomePage]: the repository, undo
/// history, cut/layer/timeline controllers, the cut command coordinator and the
/// transient clipboards.
///
/// It is a lightweight [ChangeNotifier] (Flutter built-in — no external state
/// package): mutations notify listeners so the hosting widget can rebuild. Pure
/// view state (viewport, brush tool, timeline orientation) intentionally stays
/// in the widget.
class EditorSessionManager extends ChangeNotifier {
  EditorSessionManager({
    required Project initialProject,
    AudioConformStore? audioConformStore,
    AppLanguageSettingsStore? languageSettingsStore,
    AppAccentSettingsStore? accentSettingsStore,
    AppInputSettingsStore? inputSettingsStore,
    AppSaveSettingsStore? saveSettingsStore,
    AudioSyncSettingsStore? audioSyncSettingsStore,
    AppWorkspaceColorsStore? workspaceColorsStore,
  }) : _editingSession = EditingSessionState.forProject(initialProject),
       _injectedAudioConformStore = audioConformStore,
       _appSettings = EditorAppSettings(
         languageSettingsStore: languageSettingsStore,
         accentSettingsStore: accentSettingsStore,
         workspaceColorsStore: workspaceColorsStore,
         inputSettingsStore: inputSettingsStore,
         saveSettingsStore: saveSettingsStore,
         audioSyncSettingsStore: audioSyncSettingsStore,
       ),
       _repository = ProjectRepository(initialProject: initialProject) {
    _appSettings.restore();
    _historyManager = HistoryManager();
    _cutCommandCoordinator = CutCommandCoordinator(
      repository: _repository,
      editingSession: _editingSession,
      historyManager: _historyManager,
      brushFrameStore: brushFrameStore,
    );
    _rebuildActiveCutControllers();
    cacheInvalidationHub.addBrushFrameListener(_onBrushFrameInvalidated);
    // Transport FIRST: listener order is its contract with the fallback —
    // carryingPlayback must be decided before the sync consults it.
    audioDeviceTransport.attach();
    audioPlaybackSync.attach();
    playback.globalFrameIndexListenable.addListener(_followPlaybackCut);
    // The lane span's cut-window view follows the span itself; the other
    // half of its input (which cut is open) republishes on cut switch.
    laneRangeSelection.addListener(_publishCutLocalLaneRange);
    // Dirty tracking (P3): every history change — commands, undo/redo and
    // brush strokes, which execute here straight from the canvas — marks
    // the project unsaved.
    _historyManager.addListener(_markProjectDirty);
    // AUDIO-PRO R3: any history change while the device carries playback
    // re-uploads the schedule, so edits (and their undo/redo) are heard
    // within one mixed block. Gated on carrying — the reupload costs a
    // PCM copy, and outside live playback the activation rebuild covers
    // it.
    _historyManager.addListener(_refreshLiveAudioSchedule);
    // The unworked-block tint's two events (see [celTintRevision]): the
    // store's empty↔drawn crossing, and the pen going down on a cel.
    brushFrameStore.celContentRevision.addListener(_bumpCelTintRevision);
    brushInputActive.addListener(_bumpCelTintRevision);
    // Text cel projections follow the model through EVERY mutation path
    // (edit/undo/redo/paste/duplicate/link) — one history listener, the
    // sweep re-renders whatever went stale (R5).
    _historyManager.addListener(_scheduleTextCelBakeSweep);
  }

  static const FrameId _frameId = FrameId('default-frame');

  final EditingSessionState _editingSession;
  final ProjectRepository _repository;

  // --- App settings: language, accents, input, save, A/V offset -------------

  /// The app-level settings stores and their restore/persist path, which
  /// stopped being session code: see [EditorAppSettings] for what each one
  /// keeps and why the live values sit on app-wide notifiers instead.
  ///
  /// Everything below is this session's unchanged face on it.
  final EditorAppSettings _appSettings;

  /// The program + notation languages — a value-only channel (widgets
  /// subscribe where they read strings; no whole-session notify).
  ValueNotifier<AppLanguageSettings> get languageSettings =>
      _appSettings.languageSettings;

  /// The PROGRAM-language string table, read at call time — for session
  /// verbs that produce user-facing messages and for widgets that already
  /// hold the session.
  AppStrings get uiStrings => _appSettings.uiStrings;

  void setLanguageSettings(AppLanguageSettings settings) =>
      _appSettings.setLanguageSettings(settings);

  void setAccentSettings(AppAccentSettings settings) =>
      _appSettings.setAccentSettings(settings);

  void setInputSettings(AppInputSettings settings) =>
      _appSettings.setInputSettings(settings);

  void setSaveSettings(AppSaveSettings settings) =>
      _appSettings.setSaveSettings(settings);

  /// The user's A/V offset — the residual correction for THIS machine's
  /// output path (screen pipeline, Bluetooth, an AV receiver).
  ValueNotifier<AudioSyncSettings> get audioSyncSettings =>
      _appSettings.audioSyncSettings;

  void setAudioSyncSettings(AudioSyncSettings settings) =>
      _appSettings.setAudioSyncSettings(settings);

  // --- Workspace colors: the PROJECT half (R28 #9) --------------------------
  //
  // The app-level half — the NEW-PROJECT defaults and their store — lives in
  // [EditorAppSettings]. These three are project data (R3b): they print, so
  // they travel with the project and each is one undo step.

  /// One undo step; no-op when unchanged. Writes the PROJECT's pasteboard
  /// (R3b promotion) — and remembers the choice as the app-level default
  /// for the NEXT project, which is all that remains of the old app-state
  /// pasteboard.
  void setPasteboardColor(int argb) {
    _cutCommandCoordinator.setProjectPasteboard(argb);
    notifyListeners();
    _appSettings.rememberPasteboardDefault(argb);
  }

  /// One undo step; no-op when unchanged. The BACKDROP (R3b): the stage's
  /// opaque floor — what a fade reveals and what an opaque export bakes
  /// where nothing covers.
  void setProjectBackdrop(int argb) {
    _cutCommandCoordinator.setProjectBackdrop(argb);
    notifyListeners();
  }

  /// How far past the canvas the pasteboard SHOWS, in canvas widths and
  /// heights — where the pasteboard stops and the backdrop begins. One undo
  /// step; no-op when unchanged.
  void setProjectPasteboardMargin(double margin) {
    _cutCommandCoordinator.setProjectPasteboardMargin(margin);
    notifyListeners();
  }

  /// The tool a temporary hold sprang FROM; null = no hold live.
  ///
  /// It lives here rather than in the canvas area's State because the PEN
  /// TAIL holds for as long as the pen stays flipped — across strokes,
  /// panel rebuilds and tab switches — where a barrel hold lasted one
  /// press. A State that unmounted mid-hold would lose the tool to spring
  /// back to, and leave the user holding an eraser with nothing to undo
  /// it. Not a listenable: only the release path reads it.
  CanvasTool? heldOriginalTool;

  /// App-level brush stroke store shared with the canvas host, so commands
  /// (e.g. anchored canvas resize) can transform stroke data.
  ///
  /// The link resolver reads the CURRENT project's registry on every
  /// resolve (L1) — link edits need no event plumbing to reach the store.
  late final BrushFrameStore brushFrameStore = BrushFrameStore()
    // 유저 확정 (2026-08-16): the hot budget scales to the MACHINE —
    // RAM/4 clamped — instead of assuming a desktop. Unknown RAM (no
    // engine: tests, host) keeps the old 1536MB, byte-for-byte.
    ..hotCelByteBudget = deviceScaledHotCelBudget(
      physicalMemoryBytes: QaNativeEngine.instance?.physicalMemoryBytes,
    )
    ..setLinkResolver(
      (key) =>
          _repository.currentProject?.linkRegistry.canonicalCelKey(key) ?? key,
    );

  /// The OS memory-pressure signal, forwarded by the workspace's binding
  /// observer: the hot cel tier halves and cools, and the playback caches
  /// re-run their budget against the shrunken world. Standing down is
  /// lossless by construction — cels encode to cold, dirty ones stay.
  void respondToMemoryPressure() {
    brushFrameStore.respondToMemoryPressure();
    enforcePlaybackCacheBudget();
  }

  /// The conte sheet ink's cel stores (R5) — SESSION-owned so the .anicel
  /// archive can persist them (the second cel namespace), while the ink
  /// controller (workspace UI) keeps the coordinators. The ROW store's
  /// keys carry storyboard block [FrameId]s: entries whose block no longer
  /// exists are pruned at LOAD (never at save — a deleted block's ink must
  /// survive its own undo), so "ink dies with the drawing" lands at the
  /// session boundary.
  final BrushFrameStore conteInkRowStore = BrushFrameStore();
  final BrushFrameStore conteInkPageStore = BrushFrameStore();

  /// The cut envelope's ink store — SESSION-owned for the same reason: the
  /// archive persists it, the workspace's controller owns the coordinator.
  /// Its keys carry the OWNER cut's id, so an entry whose cut is gone is
  /// pruned at LOAD exactly like a conte row's.
  final BrushFrameStore envelopeInkStore = BrushFrameStore();

  /// Production sink for brush edit invalidations; playback caches and the
  /// prerender scheduler listen here.
  final EditorCacheInvalidationHub cacheInvalidationHub =
      EditorCacheInvalidationHub();

  // --- Playback render cache stack (all non-notifying; see plan R2-R4) -----

  late final LayerFrameImageCache layerFrameImageCache = LayerFrameImageCache(
    frameStore: brushFrameStore,
  );

  late final CutFrameCompositeCache cutFrameCompositeCache =
      CutFrameCompositeCache(
        layerImages: layerFrameImageCache,
        frameStore: brushFrameStore,
        frameKeyOf: brushFrameKeyForCut,
      );

  late final PlaybackCacheBudgetEnforcer _playbackCacheBudgetEnforcer =
      PlaybackCacheBudgetEnforcer(
        layerImages: layerFrameImageCache,
        composites: cutFrameCompositeCache,
      );

  late final PlaybackPrerenderScheduler prerenderScheduler =
      PlaybackPrerenderScheduler(
        composites: cutFrameCompositeCache,
        resolveCut: cutById,
        // Widget tests: zero idle delay, like before R13-3 — the
        // quiet-window polls otherwise leave a pending gate timer at
        // teardown (the session's tearDown dispose runs AFTER the
        // binding's timer invariant). The debounce/hold semantics have
        // their own scheduler unit tests with injected delays.
        //
        // Production: 1200ms (R13-4) — during an active work session the
        // warmer resumes only in REAL pauses; per-tile abort granularity
        // covers whatever still collides at the resume boundary.
        idleDelay: Platform.environment['FLUTTER_TEST'] == 'true'
            ? Duration.zero
            : const Duration(milliseconds: 1200),
        afterFrameCached: enforcePlaybackCacheBudget,
      );

  /// The composite-cache budget trim, runnable by every producer: the
  /// warmer after each cached frame, and the parked track stack after each
  /// on-demand build (its composites would otherwise grow the cache with
  /// nothing trimming until the next warm run). LRU: what is on screen was
  /// just touched, so it survives its own trim; held clones cover the rest.
  /// A6: the reserve is MEASURED now — the bytes the editing canvas has
  /// actually pinned — replacing an estimate that saturated at its clamp
  /// around twenty layers and then reported the same number for a
  /// hundred. The holders declare their clones to the cache (pins), so
  /// "what the screen needs" stopped being a guess about a widget tree
  /// and became a number the cache itself carries. While playing the
  /// editing stack holds no pins, so the old "zero while playing" rule
  /// falls out for free instead of being an `if`.
  void enforcePlaybackCacheBudget() => _playbackCacheBudgetEnforcer.enforce(
    protect: _playbackProtectedRanges(),
    reservedForDisplayBytes: layerFrameImageCache.pinnedBytes,
  );

  /// What budget eviction must never touch: the full PLAYING playlist while
  /// playback is active (a looping pass must keep every cut warm so the
  /// second pass plays fully cached), otherwise the active cut's range.
  ///
  /// B1: the non-playing range DERIVES from [cutWarmFrameCount] — the same
  /// law the warm bakes over — because the two disagreeing was not
  /// hypothetical: warming baked the runway past the end line while this
  /// stopped AT the line, so every runway composite was evictable the
  /// moment it landed, by the enforcer that runs after every baked frame.
  /// The PLAYING branch stays on `entry.duration` on purpose: a playlist
  /// plays exactly its duration, and protecting more than plays would
  /// starve the budget during the one activity that needs it most.
  List<PlaybackProtectedRange> _playbackProtectedRanges() {
    if (playback.isActive) {
      return [
        for (final entry in playback.playlist)
          PlaybackProtectedRange(
            cutId: entry.cutId,
            startFrame: 0,
            endFrame: math.max(0, entry.duration - 1),
            quality: playbackQuality,
          ),
      ];
    }

    final cut = activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    return [
      PlaybackProtectedRange(
        cutId: cut.id,
        startFrame: 0,
        endFrame: cutWarmFrameCount(cut) - 1,
        quality: playbackQuality,
      ),
    ];
  }

  /// [_playbackProtectedRanges], for the tests that pin the one-law
  /// derivation (warm count == protected count) — the production reader
  /// stays [enforcePlaybackCacheBudget].
  @visibleForTesting
  List<PlaybackProtectedRange> debugPlaybackProtectedRanges() =>
      _playbackProtectedRanges();

  /// Playback preview quality (Premiere/AE monitor resolution analogue).
  PlaybackQuality playbackQuality = defaultPlaybackQuality;

  void setPlaybackQuality(PlaybackQuality quality) {
    if (playbackQuality == quality) {
      return;
    }
    playbackQuality = quality;
    _warmActiveCut();
    notifyListeners();
  }

  /// Canvas playback state machine; only the playback view and transport
  /// controls listen (the session playhead syncs once on stop).
  late final CanvasPlaybackController playback = CanvasPlaybackController(
    resolveProject: () => _repository.requireProject(),
    resolveActiveCutId: () => _editingSession.activeCutId,
    resolveActiveTrackId: () => selectedTrackId,
    resolveFrameRate: () => projectFrameRate,
    onStopped: _onPlaybackStopped,
    onStoppedInGap: _onPlaybackStoppedInGap,
    onPlaylistWarmRequested: _onPlaybackPlaylistWarmRequested,
  );

  /// The native device transport (audio program wiring): when it carries a
  /// run, playback rides the audio master clock — the picture follows the
  /// samples handed to the device, and cumulative drift is structurally
  /// zero. Stands down per run (no binary/device, PCM not resident) onto
  /// [audioPlaybackSync].
  late final AudioDeviceTransport audioDeviceTransport = AudioDeviceTransport(
    controller: playback,
    resolveFrameRate: () => projectFrameRate,
    resolveProject: () => _repository.currentProject,
    conformStore: audioConformStore,
    // Widget tests must never open a real OS audio device.
    resolveDevice: Platform.environment['FLUTTER_TEST'] == 'true'
        ? () => null
        : null,
    resolveUserOffsetSamples: (sampleRate) =>
        audioSyncSettings.value.offsetSamples(
          sampleRate: sampleRate,
          frameRateNumerator: projectFrameRate.numerator,
          frameRateDenominator: projectFrameRate.denominator,
        ),
    resolveSoloedLayerIds: () => soloedSeLayerIds.value,
    resolveRecordingMutedLayerIds: () => recordingMutedLayerIds,
    resolveCueClips: () => voiceRecordCueClips,
    resolveOutputDeviceName: () => audioSyncSettings.value.outputDeviceName,
  );

  /// The output/input device lists for the Preferences pickers (AUDIO-PRO
  /// R4); empty without a native binary (widget tests, engine-less runs).
  List<({String name, bool isDefault})> audioDevicesOf({
    required bool capture,
  }) {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return const [];
    }
    return QaAudioDevice.instance?.devicesOf(capture: capture) ?? const [];
  }

  /// Scrubbing the playhead plays each crossed frame's slice of the mix
  /// (2D): one `play(frame, frame+1)` per crossed frame on the same
  /// transport playback uses. Stands down silently without a device or
  /// resident PCM — the scrub stays visual-only, as before.
  late final AudioScrubber audioScrubber = AudioScrubber(
    controller: playback,
    resolveFrameRate: () => projectFrameRate,
    resolveProject: () => _repository.currentProject,
    conformStore: audioConformStore,
    // Widget tests must never open a real OS audio device.
    resolveDevice: Platform.environment['FLUTTER_TEST'] == 'true'
        ? () => null
        : null,
    resolveSoloedLayerIds: () => soloedSeLayerIds.value,
    resolveRecordingMutedLayerIds: () => recordingMutedLayerIds,
    resolveOutputDeviceName: () => audioSyncSettings.value.outputDeviceName,
  );

  /// Frame-synced SE audio riding [playback]'s frame signals; clip lengths
  /// come from the conform store (exact sample counts, with the ffmpeg
  /// peaks approximation as its own fallback). Fallback path — stands down
  /// for runs the device transport carries.
  late final AudioPlaybackSync audioPlaybackSync = AudioPlaybackSync(
    controller: playback,
    resolveFrameRate: () => projectFrameRate,
    durationSecondsFor: audioConformStore.durationSecondsFor,
    playerFactory: AudioplayersClipPlayer.new,
    // Track-owned SE rows schedule from the tracks' global axes.
    resolveProject: () => _repository.currentProject,
    deviceCarriesPlayback: () => audioDeviceTransport.carryingPlayback,
    resolveSoloedLayerIds: () => soloedSeLayerIds.value,
    resolveRecordingMutedLayerIds: () => recordingMutedLayerIds,
    resolveCueClips: () => voiceRecordCueClips,
  );

  void _onPlaybackStopped(PlaybackPosition lastPosition) {
    // Transport stop finishes a rolling take (REC1-B): record = play +
    // capture, so ending one ends the other. The result message goes out
    // on the notice channel — this path has no button to return through.
    if (isVoiceRecording.value) {
      voiceRecordingNotice.value = stopVoiceRecordingAndPlace();
    }
    if (lastPosition.cutId != _editingSession.activeCutId) {
      selectCut(lastPosition.cutId);
    }
    selectFrameIndex(_clampedFrameIndex(lastPosition.localFrameIndex));
    // The mid-playback cut follow is QUIET (R12-B) — this is the one
    // session notify that catches every activeCut consumer up with where
    // playback landed.
    notifyListeners();
  }

  /// Stop landed on a playlist GAP frame (UI-R9 #3): match the editing
  /// gap semantics — park there with NO active cut.
  void _onPlaybackStoppedInGap(int globalFrame) {
    // The gap-stop twin of _onPlaybackStopped's take finish: a lane is
    // cut-independent, so a take may legitimately end over a gap.
    if (isVoiceRecording.value) {
      voiceRecordingNotice.value = stopVoiceRecordingAndPlace();
    }
    _gapGlobalFrame = globalFrame;
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
  void _followPlaybackCut() {
    if (playback.globalFrameIndexListenable.value == null) {
      return;
    }
    final position = playback.position;
    if (position == null || position.cutId == _editingSession.activeCutId) {
      return;
    }
    _editingSession.setActiveCutId(position.cutId);
    _copiedFrame = null;
    _rebuildActiveCutControllers(preferredFrameIndex: position.localFrameIndex);
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
    prerenderScheduler.requestWarmFrames(
      frames: [...frames.sublist(start), ...frames.sublist(0, start)],
      quality: playbackQuality,
    );
  }

  late final HistoryManager _historyManager;
  late final CutCommandCoordinator _cutCommandCoordinator;
  final CutReorderPlanner _cutReorderPlanner = const CutReorderPlanner();
  late LayerController _layerController;
  late TimelineController _timelineController;

  int _layerSequence = 1;
  int _frameSequence = 0;

  /// The next unused `default-layer-N`.
  ///
  /// The counter alone is not enough, and the reason is that it is SESSION
  /// state while the project can arrive from DISK. Open a file that already
  /// holds `default-layer-2` and the counter is still 1, so the next added
  /// layer is minted straight on top of an existing row: two layers, one id.
  /// It surfaced as a red screen from the rail (`multiple children with key
  /// …default-layer-2-row`), which is why the fix is here and not there — a
  /// duplicate key is what a duplicate id looks like downstream.
  ///
  /// So the project has the last word, exactly as it already does for
  /// imported cut ids ([_importIdMint]). The counter still carries a BATCH,
  /// where ids minted a moment ago are not in the project yet.
  ///
  /// [usedIds] lets a caller minting MANY ids hand the scan in once; see
  /// [_importIdMint], which is the only such caller.
  LayerId _mintLayerId({Set<String>? usedIds}) {
    final used = usedIds ?? _usedLayerIdValues();
    _layerSequence += 1;
    var candidate = defaultLayerIdForSequence(_layerSequence);
    while (used.contains(candidate.value)) {
      _layerSequence += 1;
      candidate = defaultLayerIdForSequence(_layerSequence);
    }
    return candidate;
  }

  Set<String> _usedLayerIdValues() => {
    for (final track in _repository.requireProject().tracks)
      for (final cut in track.cuts)
        for (final layer in cut.layers) layer.id.value,
  };

  _CopiedFrameReference? _copiedFrame;
  LayerCopyPayload? _layerClipboard;

  ProjectRepository get repository => _repository;
  HistoryManager get historyManager => _historyManager;

  /// NULL = the editing playhead stands in a GAP (UI-R9 #3): no cut is
  /// selected. Cut-scoped surfaces show their empty states; cut-scoped
  /// commands stand down.
  CutId? get activeCutId => _editingSession.activeCutId;

  bool get canUndo => _historyManager.canUndo;
  bool get canRedo => _historyManager.canRedo;

  void _rebuildActiveCutControllers({
    LayerId? preferredActiveLayerId,
    int preferredFrameIndex = 0,
  }) {
    final activeCutId = _editingSession.activeCutId;
    final initialActiveLayerId = _activeCutHasLayer(preferredActiveLayerId)
        ? preferredActiveLayerId
        : null;

    _layerController = LayerController(
      repository: _repository,
      historyManager: _historyManager,
      cutId: activeCutId,
      frameId: _frameId,
      initialActiveLayerId: initialActiveLayerId,
      trackSeDisplayLayers: () => trackSeDisplayLayers,
      trackTransitionDisplayLayer: () => trackTransitionDisplayLayer,
    );
    _timelineController = TimelineController(
      repository: _repository,
      historyManager: _historyManager,
      cutId: activeCutId,
      initialFrameIndex: _clampedFrameIndex(preferredFrameIndex),
      // Track-SE mutations shift to the global axis inside the controller;
      // reads keep flowing through the cut-local display clones.
      frameOffsetForLayer: (layerId) =>
          isTrackSeLayerId(layerId) ? activeCutGlobalStartFrame : 0,
      trackSeLayers: () => activeTrack.seLayers,
    );
    editingFrameCursor.value = _timelineController.currentFrameIndex;
    // A cut switch re-seats the active layer, which is what the drawn row
    // falls back to when nothing is engaged.
    _publishCurrentRow();
    // The window moved, so the part of a track-global lane span this cut
    // can see moved with it. The selection itself is untouched.
    _publishCutLocalLaneRange();
  }

  int _clampedFrameIndex(int frameIndex) {
    final maxIndex = math.max(0, activeCutPlaybackFrameCount - 1);
    return frameIndex.clamp(0, maxIndex);
  }

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
  TrackId get selectedTrackId {
    final project = _repository.requireProject();
    final cutTrackId = trackIdOfCut(project, _editingSession.activeCutId);
    if (cutTrackId != null) {
      return cutTrackId;
    }

    final stored = _editingSession.selectedTrackId;
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

  /// The storyboard rail's own selected row, as picked. Null = never
  /// picked, which reads as the selected track's V row.
  TimelineRowAddress? _storyboardRow;

  /// The row a frame-axis VERB acts on (R10 #13) — the rail's rows and the
  /// cut's layer rows alike, whichever the user last engaged.
  ///
  /// NOT the same thing as [selectedRow], and deliberately so. The user's
  /// correction when #13 was settled: a V row and a layer row are not
  /// siblings competing for one slot, they are a HIERARCHY — a V row is a
  /// cut, a layer row is a layer INSIDE a cut. So [selectedRow] keeps
  /// saying which row of the FILM is lit (and picking a layer still leaves
  /// it alone, the 2026-07-27 rule), while this says whose blocks the flip
  /// counts. Folding the two into one slot is what made picking a layer
  /// drop the rail's S-row highlight, which is not what either question
  /// was asking.
  TimelineRowAddress? _verbRow;

  /// The TIMELINE's own row, the way [_storyboardRow] is the rail's: the
  /// layer or property lane last engaged there. Kept so that returning to
  /// the timeline restores the row you were on rather than resetting to
  /// whatever the active layer happens to be.
  TimelineRowAddress? _timelineRow;

  /// The panel being worked in owns the frame-axis verbs (user, 2026-08-05:
  /// "마지막으로 무언가 액션이 있었던 패널을 기준으로"). Picking a row is
  /// no longer the only way to move the flip's subject — touching the
  /// panel at all is, because that is what "I am working here" looks like.
  ///
  /// Each panel claims the row IT remembers rather than a fresh one, so
  /// coming back to the timeline lands on the lane you left open instead
  /// of dropping to the layer row.
  ///
  /// A claim never NOTIFIES the session. It fires on pointer-DOWN, and a
  /// ruler drag's whole contract is that it stays silent per move and
  /// commits once on release. What the rails DRAW rides
  /// [currentRowListenable] instead, so the row that moved repaints its
  /// own small cells and nothing else.
  void claimTimelineRow() {
    final layerId = activeLayerId;
    final next =
        _timelineRow ?? (layerId == null ? null : LayerRowAddress(layerId));
    if (next != null) {
      _verbRow = next;
      _publishCurrentRow();
    }
  }

  void claimStoryboardRow() {
    _verbRow = selectedRow;
    _publishCurrentRow();
  }

  /// Defaults to the active layer's row, not the track's: with nothing
  /// picked yet the row you are on is the one you draw on. Only a cut with
  /// no layers at all falls through to the track row.
  TimelineRowAddress get currentRow {
    final stored = _verbRow;
    if (stored != null) {
      return stored;
    }
    final layerId = activeLayerId;
    return layerId == null
        ? TrackRowAddress(selectedTrackId)
        : LayerRowAddress(layerId);
  }

  /// [currentRow] as a LISTENABLE — R10 #19's other half. The row you are
  /// standing on is DRAWN now (the active layer's row, an fx header, a
  /// property lane), and the rails have to learn it moved WITHOUT a
  /// session notify: the claim that moves it fires on pointer-down, inside
  /// gestures whose whole contract is silence until release.
  ///
  /// A [ValueNotifier] only notifies on a real change, so pressing again
  /// in the row you are already standing on costs nothing — which is the
  /// common case, and the reason this can be published eagerly.
  final ValueNotifier<TimelineRowAddress?> currentRowListenable =
      ValueNotifier<TimelineRowAddress?>(null);

  /// ⑨ (user, 2026-08-12): 「레이어에도 선택 시스템 — 첫 드래그가 선택
  /// (1개/여러 개), 그 다음이 드래그. 타임라인 프레임과 **완전히 같은 순서**」.
  ///
  /// The rail's ROW selection: what the row verbs act on. Separate from
  /// [currentRow] on purpose — standing is where the frame verbs aim, this
  /// is a set the row verbs sweep — and separate from the frame range,
  /// whose rows are the cells the selection covers rather than the rows
  /// themselves.
  ///
  /// Addresses, not layers, so every drawn row kind can be in it (뿌리 A):
  /// what a row IS never decides whether it can be selected, only what the
  /// edit then does to it.
  final ValueNotifier<List<TimelineRowAddress>> rowSelection =
      ValueNotifier<List<TimelineRowAddress>>(const []);

  /// Where the live row-select drag started; null between drags.
  TimelineRowAddress? _rowSelectionAnchor;

  bool rowIsSelected(TimelineRowAddress row) =>
      rowSelection.value.contains(row);

  /// 🚨T10 — whether standing on ([row], [frameIndex]) lands INSIDE whatever
  /// is currently selected.
  ///
  /// The one question [standOnRow] asks before it clears. 유저 확정
  /// 2026-08-14: 「탭다운 하면 **먼저 기존 선택된거 삭제**하게 하면, 바꾸면
  /// 선택삭제고 거기서 이동하면 선택 새로 추가니까 문제없을거같은데」 — a
  /// press clears when it moves you somewhere else, and holds when it is the
  /// beginning of a MOVE of what is already selected.
  ///
  /// ★Asked HERE rather than threaded in from each surface. Handing every
  /// surface the same predicate and trusting each to use it is the shape T5
  /// and T13 spent a round deleting from the selection model — the next
  /// surface forgets, and the bug is invisible until someone drags on it.
  ///
  /// ★Every KIND is asked, and 「선택한 상태라는건 한 종류만 존재하도록」
  /// means at most one can answer yes anyway. A kind added later joins by
  /// being named here, exactly like [claimSelection]'s switch.
  ///
  /// ⚠️A null [frameIndex] means "no cell is in question", so only the ROW
  /// selection can answer. [standOnRow] does not pass null — it substitutes
  /// the playhead, because standing on a row without naming a frame IS
  /// standing there at the playhead.
  bool standingInsideSelection(
    TimelineRowAddress row, [
    int? frameIndex,
    bool frameIsGlobal = false,
  ]) {
    if (rowIsSelected(row)) {
      return true;
    }
    final cells = frameRangeSelection.value;
    if (cells != null &&
        frameIndex != null &&
        !frameIsGlobal &&
        cells.coversRow(row) &&
        frameIndex >= cells.startIndex &&
        frameIndex < cells.endIndexExclusive) {
      return true;
    }
    // ⚠️A lane selection has no `coversRow` — it names its rows by LANE
    // (`coversLane`), which is why this arm reads differently from the one
    // above rather than sharing it.
    //
    // C6 (2026-08-17): asked on the AXIS the span lives on. A track-SE
    // row's lane span is stored GLOBAL ([updateLaneRangeSelectionDrag]'s
    // own translation), while the cut panel presses in window frames — so
    // a window frame converts exactly as the drag's did, or a press inside
    // the very selection it made reads as outside and the standing clear
    // (now on the DOWN) would wipe the move it was starting.
    final lanes = laneRangeSelection.value;
    if (lanes != null && frameIndex != null && row is LaneRowAddress) {
      final laneAxisFrame =
          !frameIsGlobal && isTrackSeLayerId(row.layerId)
          ? frameIndex + activeCutGlobalStartFrame
          : frameIndex;
      if (lanes.coversLane(row.layerId, row.laneId) &&
          laneAxisFrame >= lanes.startIndex &&
          laneAxisFrame < lanes.endIndexExclusive) {
        return true;
      }
    }
    // The TRACK-axis selection (the storyboard's rows) answers for the
    // global-frame callers the same way the cut-local ones answer above.
    final trackSpan = trackFrameRangeSelection.value;
    if (trackSpan != null &&
        frameIndex != null &&
        frameIsGlobal &&
        trackSpan.coversRow(row) &&
        frameIndex >= trackSpan.startFrame &&
        frameIndex < trackSpan.endFrameExclusive) {
      return true;
    }
    return false;
  }

  /// A press that lands OUTSIDE the current selection starts a fresh one —
  /// the cells' rule, transposed (their range gesture's `isInSelection`).
  void beginRowSelection(TimelineRowAddress anchor) {
    claimSelection(TimelineSelectionKind.rows);
    _rowSelectionAnchor = anchor;
    rowSelection.value = [anchor];
  }

  /// Grows the live selection to [rowDelta] rows from its anchor, through
  /// the SAME law the cell span uses — the rail's own drawn row list, so a
  /// row that is visible is selectable and a new row kind needs no wiring.
  void updateRowSelection(List<TimelineDisplayRow> rows, int rowDelta) {
    final anchor = _rowSelectionAnchor;
    if (anchor == null) {
      return;
    }
    final span = resolveSelectionSpanRows(
      rows: rows,
      anchor: anchor,
      rowDelta: rowDelta,
    );
    if (span.isNotEmpty) {
      rowSelection.value = span;
    }
  }

  void endRowSelection() {
    _rowSelectionAnchor = null;
  }

  /// The selected rows that name a LAYER this cut may delete (⑨).
  ///
  /// A row's kind decides what the edit DOES, never whether the row could
  /// be selected (뿌리 A) — so lane rows, track rows and the floors' fixed
  /// rows simply contribute nothing here instead of being kept out of the
  /// selection.
  List<LayerId> deletableSelectedLayerIds() {
    final selection = rowSelection.value;
    if (selection.isEmpty) {
      return const [];
    }
    final byId = {for (final layer in layers) layer.id: layer};
    final ids = <LayerId>[];
    for (final row in selection) {
      if (row is! LayerRowAddress) {
        continue;
      }
      final layer = byId[row.layerId];
      if (layer != null && !ids.contains(layer.id) && canDeleteLayer(layer)) {
        ids.add(layer.id);
      }
    }
    return ids;
  }

  void clearRowSelection() {
    _rowSelectionAnchor = null;
    if (rowSelection.value.isNotEmpty) {
      rowSelection.value = const [];
    }
  }

  /// 🚨A CLICK CLEARS (유저 확정 2026-08-12): 「어딘가 클릭하면 사라지도록.
  /// 프레임셀처럼 다른곳 클릭하거나. 다른레이어 클릭하거나. **근데 선택된 내
  /// 물건 클릭해도 사라지도록** 하고싶어. 선택레이어로 ABC선택하고, C 클릭하면
  /// 사라지도록. **프레임셀쪽도 마찬가지**」.
  ///
  /// ★TAP clears, DRAG does not — the whole distinction, and the reason
  /// this hangs off the surfaces' SELECT callbacks rather than off
  /// pointer-down: a press the pan recognizer claims never reaches them, so
  /// a drag starting inside a selection still MOVES it (⑨'s second phase)
  /// while a tap on that same row lets it go.
  ///
  /// Clicking INSIDE the selection clears it too. That is the user's own
  /// call, and it is written out here because it is the surprising half —
  /// the ordinary desktop idiom keeps a selection you click into.
  void clearAllSelections() {
    clearFrameRangeSelection();
    clearLaneRangeSelection();
    clearStoryboardCutSelection();
    clearRowSelection();
  }

  /// 🚨T4 — STANDING ON A ROW, as one verb.
  ///
  /// 유저 2026-08-13: 「선택된게 풀리는거, **어떤 행이든 액티브 바꾸면
  /// 풀리도록.** 지금 레이어 액티브 바꾸면 풀리는데 **트랜스폼 멤버 행
  /// 액티브로하면 안풀림**」.
  ///
  /// ★The law was right and its ADDRESS was wrong. 「클릭하면 선택이
  /// 사라진다」 was hung on the timeline host's `onSelectLayer` callback — a
  /// wrapper — so it covered the doors that happened to go through that
  /// wrapper and missed the ones that call the session directly. Standing on
  /// a property lane was one of those, and it will not be the last: a wrapper
  /// is a place, and every new door has to be told about it.
  ///
  /// A verb cannot be walked around. Every surface that means 「여기 서라」
  /// says it here, and what standing DOES is decided once.
  ///
  /// [row] is the address stood on; [frameIndex] seeks as well, for the
  /// surfaces where standing and seeking are one gesture (a lane band's
  /// cells). A label press leaves it null — a label names a ROW, and the
  /// frame stays where it was.
  /// [globalFrameIndex] is the same seek stated on the TRACK's global axis
  /// — the storyboard's rows press in global frames (C6 2026-08-17: their
  /// lane bands stand through THIS verb now instead of a hand-rolled
  /// clear-and-seek that restated the law without the T10 guard). At most
  /// one of the two frames is passed.
  /// [takesLayerActive] is false on the STORYBOARD's rails, where the row you
  /// stand on and the layer you draw on are separate states (유저
  /// 2026-07-27). It is a parameter rather than a second verb because the
  /// clearing law is the same on both panels — only the active layer differs,
  /// and stating that difference once here beats restating the law at each
  /// call site, which is the mistake T4 was.
  void standOnRow(
    TimelineRowAddress row, {
    int? frameIndex,
    int? globalFrameIndex,
    bool takesLayerActive = true,
  }) {
    // 🚨T10. T4's law is untouched by this: the clearing still lives INSIDE
    // the verb rather than at its call sites — scattering it was T4's whole
    // bug. What changed is that the verb now asks a question first.
    //
    // A press that lands inside the current selection stands WITHOUT
    // clearing, because that press is most likely the start of a move.
    // Measured, not assumed: with this unconditional, turning the press-pick
    // on made an SE row move stop committing — the pick wiped the very rows
    // the move was about to carry.
    //
    // ⚠️A caller that names no frame is standing on the row AT THE
    // PLAYHEAD, so that is the cell the question is about. Falling back to
    // it rather than to "no cell" is what lets the guard see a cell range
    // at all: the surfaces reach this verb through a `ValueChanged<LayerId>`
    // that carries no frame, and a null there would make the guard blind to
    // exactly the selection it exists to protect.
    if (globalFrameIndex != null
        ? !standingInsideSelection(row, globalFrameIndex, true)
        : !standingInsideSelection(row, frameIndex ?? currentFrameIndex)) {
      clearAllSelections();
    }
    switch (row) {
      case LayerRowAddress(:final layerId):
        if (takesLayerActive) {
          selectLayer(layerId);
        } else {
          selectRow(row);
        }
      case LaneRowAddress(:final layerId):
        // A LANE also becomes the verb's subject, so Add keys that property
        // instead of adding a cel (R10 #19). `selectLayer` moves the verb row
        // to the LAYER, which is why the lane is claimed after it — and why a
        // layer row needs nothing more.
        if (takesLayerActive) {
          selectLayer(layerId);
        }
        selectRow(row);
      case TrackRowAddress():
        // A track row has no layer to make active either way.
        selectRow(row);
    }
    if (frameIndex != null) {
      selectFrameIndex(frameIndex);
    }
    if (globalFrameIndex != null) {
      selectGlobalFrame(globalFrameIndex);
    }
  }

  /// 🚨THE ONE-SELECTION LAW (유저 확정 2026-08-12): 「선택범위는 하나만
  /// 작동하도록. 프레임셀 선택범위 작동시키고 레이어쪽 선택범위 작동하면
  /// 기존 프레임셀쪽 사라지게. 반대도 마찬가지 (…) 즉 **선택한 상태라는건
  /// 한 종류만 존재하도록**」.
  ///
  /// Whichever selection is STARTING, the others go.
  ///
  /// The rule already existed in pieces — the track axis cleared the
  /// cut-local one, cells and lanes cleared each other — each stated at its
  /// own call site with its own words. Three kinds is where pairwise still
  /// reads; ⑨ made a fourth, and n² sentences is where it stops. Written
  /// once, a fifth kind joins by being named in this switch.
  void claimSelection(TimelineSelectionKind kind) {
    if (kind != TimelineSelectionKind.cells) {
      clearFrameRangeSelection();
    }
    if (kind != TimelineSelectionKind.lanes) {
      clearLaneRangeSelection();
    }
    if (kind != TimelineSelectionKind.cuts) {
      clearStoryboardCutSelection();
    }
    if (kind != TimelineSelectionKind.rows) {
      clearRowSelection();
    }
  }

  /// Re-publishes [currentRow]. Idempotent and cheap: call it after
  /// anything that could move the answer rather than reasoning about which
  /// writer was the one that did.
  ///
  /// Stands down while the answer would need a TRACK it cannot have (no
  /// row engaged, no active layer, and a project that may hold no tracks
  /// yet) — there is nothing to light in that state, and asking would
  /// throw.
  void _publishCurrentRow() {
    if (_disposed || (_verbRow == null && activeLayerId == null)) {
      return;
    }
    currentRowListenable.value = currentRow;
  }

  /// THE FOLD LAW (R5 #11): what disappears never keeps the selection.
  /// Folding something you are standing INSIDE hands the standing row to
  /// whatever swallowed it.
  ///
  /// Two folds already obeyed this, each in its own place and its own
  /// words — a folder taking the selection off a member
  /// ([toggleLayerCollapsed], R27 #24) and an attach base taking it off an
  /// attach row (the workspace's group fold, UI-R24 #4). The fx twirl and
  /// the lane-GROUP twirl did not, so closing a Transform group left you
  /// standing on a row that was no longer on screen, and the canvas went on
  /// refusing strokes for a lane nobody could see. Four folds, one rule,
  /// one place.
  ///
  /// [laneId] null means the whole twirl-down is closing (every lane of the
  /// layer goes), so the LAYER's own row is what swallows it. A non-null
  /// [laneId] is a GROUP header closing, and it swallows its members alone
  /// — the header itself stays on screen and is where you land.
  void handOffCurrentRowOnFold(LayerId layerId, {String? laneId}) {
    final row = currentRow;
    if (laneId == null) {
      if (row is LaneRowAddress && row.layerId == layerId) {
        selectLayer(layerId);
      }
      return;
    }
    if (currentRowIsInsideGroup(row, layerId, laneId)) {
      selectRow(LaneRowAddress(layerId, laneId));
    }
  }

  /// THE selected row of the STORYBOARD's rail — exactly ONE, whichever row
  /// was picked, the way the timeline has exactly one selected layer row.
  ///
  /// State of its OWN, not a projection of [activeLayerId]. The two row
  /// selections are separate things (user decision 2026-07-27): a CUT's
  /// selected row is the active layer — the drawing target, remembered per
  /// cut — while this one says which row of THIS RAIL the user is on.
  /// Deriving it is what forced the previous "only a track-SE layer names a
  /// row here" rule, which made the rail's two row kinds unequal for no
  /// reason the rail itself has.
  ///
  /// Picking a row here therefore never moves the drawing target — not for
  /// a V row (a track has no layer to select) and not for an S row.
  ///
  /// A stored row that the rail no longer shows (its track's SE slot went
  /// away) falls back to the track row rather than lighting nothing.
  TimelineRowAddress get selectedRow {
    final row = _storyboardRow;
    if (row is LayerRowAddress && isTrackOwnedRailLayerId(row.layerId)) {
      return row;
    }
    return TrackRowAddress(selectedTrackId);
  }

  /// Selects a row of the storyboard's rail by ADDRESS — the rail taps and
  /// the cells press come through here. A track row additionally promotes
  /// that track's cut under the playhead (UI-R18 #6); a layer row has no
  /// landing verb of its own, because the drawing target is not this
  /// selection's business.
  void selectRow(TimelineRowAddress row) {
    switch (row) {
      case LayerRowAddress(:final layerId):
        if (editingInteractionBusy) {
          return;
        }
        // The row lives on a track, so picking it picks that track too —
        // the rail's row selection and the track selection must not
        // disagree (the range drag that follows a press resolves its rows
        // against the SELECTED track's rail).
        final owner = _trackOwnedRailOwner(layerId);
        var trackMoved = false;
        if (owner != null && selectedTrackId != owner.id) {
          _editingSession.setSelectedTrackId(owner.id);
          trackMoved = true;
        }
        if (_storeStoryboardRow(row) || trackMoved) {
          notifyListeners();
        }
      case LaneRowAddress():
        // R10 #19: a property row is a row you can be ON. The rail's own
        // highlight resolves it to the containing V row, like any other
        // in-cut row; what moves is the verb's subject.
        //
        // A lane lives in the TIMELINE, so it is the timeline's row to
        // remember: coming back to that panel restores the lane rather
        // than dropping to the layer it hangs under.
        //
        // R5 #12: and the CELL range goes. A frame range is drawn on a
        // LAYER row, so standing on a property is always leaving the row
        // it belongs to — but `selectLayer` runs first on this path and
        // keeps a range whose layer has not changed, which left the band
        // sitting on the cells while the subject was a lane. Nothing draws
        // a frame range from a lane, so this can never drop one mid-drag.
        clearFrameRangeSelection();
        _timelineRow = row;
        if (_storeStoryboardRow(row)) {
          notifyListeners();
        }
      case TrackRowAddress(:final trackId):
        selectTrackCutAtPlayhead(trackId);
    }
    // Every arm can move the drawn row, and the track arm does it through
    // a path of its own — publishing once here beats three call sites that
    // must each remember.
    _publishCurrentRow();
  }

  /// Makes a V row THE selected row and nothing else — no cut promotion, no
  /// seek. The cells press wants this half on its own: the frame it presses
  /// decides the cut, so promoting the playhead's cut first would switch
  /// cuts twice for one press.
  void selectTrackRow(TrackId trackId) {
    if (editingInteractionBusy) {
      return;
    }
    final trackBefore = selectedTrackId;
    _editingSession.setSelectedTrackId(trackId);
    if (_storeStoryboardRow(TrackRowAddress(trackId)) ||
        selectedTrackId != trackBefore) {
      notifyListeners();
    }
  }

  /// Stores the rail's row. Returns whether the ANSWER moved — the store
  /// and the answer differ, since a row the rail no longer shows resolves
  /// back to the track row.
  bool _storeStoryboardRow(TimelineRowAddress row) {
    final before = selectedRow;
    _storyboardRow = row;
    // Picking a rail row is also engaging it, so the verb follows (R10
    // #13). The reverse does not hold — see [_verbRow].
    _verbRow = row;
    _publishCurrentRow();
    return selectedRow != before;
  }

  // --- Track-owned SE rows --------------------------------------------------
  //
  // SE rows live on the TRACK (global frame axis — sounds may cross cut
  // boundaries). Reads go through cut-local DISPLAY clones composed into
  // [layers]; mutations detect track-SE ids, convert local→global through
  // the window, and edit the track's GLOBAL layer (the clones are never
  // written back).

  Track get activeTrack {
    final trackId = selectedTrackId;
    return _repository.requireProject().tracks.firstWhere(
      (track) => track.id == trackId,
    );
  }

  /// The active track's transition spans on the GLOBAL frame axis — the one
  /// reader for every surface that has to answer a transition question
  /// (the sheet's のりしろ, the cut view's read-only marks, the compositor's
  /// ramp). They are plain records so nobody downstream has to know a layer is
  /// behind them — start, length and the TERM'S MARK, which is what says
  /// whether the span moves both cuts or only its own.
  List<TransitionSpan> get activeTrackTransitionSpans => [
    for (final entry in activeTrack.transitionLayer.instructions.entries)
      _transitionSpanOf(entry),
  ];

  /// The active cut's global start frame on its track (cumulative cut
  /// durations — the storyboard layout's number for this cut).
  int get activeCutGlobalStartFrame =>
      _cutGlobalStartFrameIn(activeTrack, _editingSession.activeCutId) ?? 0;

  /// [cutId]'s global start on [track]'s axis, or null when the track does
  /// not hold it. ONE cumulative walk — the same one
  /// [buildStoryboardTimelineLayout] makes (gap, then duration), kept in a
  /// single place so the SE tags and the SE window can never disagree with
  /// the storyboard about where a cut begins.
  int? _cutGlobalStartFrameIn(Track track, CutId? cutId) {
    if (cutId == null) {
      return null;
    }
    var start = 0;
    for (final cut in track.cuts) {
      start += cut.leadingGapFrames;
      if (cut.id == cutId) {
        return start;
      }
      start += cut.duration;
    }
    return null;
  }

  TrackSeWindow get trackSeWindow => TrackSeWindow(
    cutStartFrame: activeCutGlobalStartFrame,
    cutDurationFrames: activeCutOrNull?.duration ?? 0,
  );

  /// Whether [layerId] names a TRACK-owned SE row — a question about what
  /// KIND of row it is, on any track in the project.
  ///
  /// ★It used to ask `activeTrack` only, which quietly made it "…and that
  /// track holds the open cut". Every axis rule keyed off it then answered
  /// NO for another track's S row, so those rows fell onto the cut-layer
  /// paths and did nothing (user, 2026-08-09: "S행은 V랑 관련없이
  /// 독립적으로 움직일 수 있어야 해"). Which cut is open is not part of
  /// what a row IS.
  bool isTrackSeLayerId(LayerId layerId) => _trackSeAnywhere(layerId) != null;

  /// The track that owns [layerId] as its TRANSITION row, on any track.
  Track? _trackTransitionOwner(LayerId layerId) {
    for (final track in _repository.requireProject().tracks) {
      if (track.transitionLayer.id == layerId) {
        return track;
      }
    }
    return null;
  }

  bool isTrackTransitionLayerId(LayerId layerId) =>
      _trackTransitionOwner(layerId) != null;

  /// Whether [layerId] is a TRACK-OWNED row of the storyboard's rail — an SE
  /// lane or the transition row.
  ///
  /// ★Deliberately not `isTrackSeLayerId` at the call sites that mean THIS.
  /// "Is it an SE row" was standing in for "is it a row this rail can be
  /// standing on", and the transition row is the second answer — the same
  /// substitution that made the cut view's bulk verbs reach for a
  /// track-owned row as if it were a cut layer. Row behaviour that really is
  /// SE-specific (block snapping, sound order drags, range moves) keeps
  /// asking the SE question.
  bool isTrackOwnedRailLayerId(LayerId layerId) =>
      isTrackSeLayerId(layerId) || isTrackTransitionLayerId(layerId);

  /// The track that owns [layerId] as one of its rail rows — the resolver half
  /// of [isTrackOwnedRailLayerId], for the verbs that need the track and not
  /// just a yes.
  Track? _trackOwnedRailOwner(LayerId layerId) =>
      _trackSeAnywhere(layerId)?.track ?? _trackTransitionOwner(layerId);

  /// Whether the active row can carry an on-canvas name tag (R5b): the
  /// SE rows, and only while a cut gives the canvas its geometry.
  bool get canEditActiveSeNameTag =>
      activeLayer?.kind == LayerKind.se && activeCutOrNull != null;

  // `activeSeNameTagDefaultPosition` seeded the placement dialog's x/y
  // fields from a stacked per-row default. Both are gone with R5 #7: a tag
  // has no position of its own, so the SE row's Position lane is the whole
  // answer and there is nothing to seed.

  /// Sets (or with null resets) the active SE row's name tag — one undo,
  /// reaching the TRACK-owned row through the anywhere seam.
  void setActiveSeNameTag(SeNameTag? tag) {
    final layer = activeLayer;
    if (layer == null || layer.kind != LayerKind.se) {
      return;
    }
    _cutCommandCoordinator.setSeNameTag(layerId: layer.id, seNameTag: tag);
    notifyListeners();
  }

  /// A NAME TAG lane edit landing on [layerId] (R5 #7) — one undo.
  ///
  /// The tag's keys sit on the track-owned row's GLOBAL axis while the lane
  /// was read off a cut-local clone, so the frames convert on the way out,
  /// exactly as the transform track's do (#8). The lane helpers key at
  /// whatever frame the caller hands them, so the conversion belongs HERE —
  /// after the edit, before the commit.
  void setSeNameTagForLayer(LayerId layerId, SeNameTag? tag) {
    final keys = tag?.track;
    _cutCommandCoordinator.setSeNameTag(
      layerId: layerId,
      seNameTag: keys == null || !isTrackSeLayerId(layerId)
          ? tag
          : tag!.copyWith(track: trackSeWindow.globalSeNameTagTrack(keys)),
    );
    notifyListeners();
  }

  /// The ON-CANVAS name tags for a cut's local frame (R5b, §6-z15) — the
  /// one resolution every drawing surface asks (editing canvas, playback,
  /// the parked stack, export), so none of them can disagree. Works for
  /// ANY cut, not just the active one: it walks the owning track's global
  /// SE rows and converts through that cut's start.
  List<ResolvedSeNameTag> seNameTagsForCutFrame(Cut cut, int localFrameIndex) {
    // The over-end runway is a CLIPPED VIEW of the cut (UI-R9 #4): a
    // playhead past the last frame must never address the NEIGHBOUR
    // cut's SE window and put the next speaker over this picture. The
    // scrub preview already clamps this way, so drag and release agree.
    final maxLocal = cut.duration > 0 ? cut.duration - 1 : 0;
    final localFrame = localFrameIndex > maxLocal ? maxLocal : localFrameIndex;
    final project = _repository.requireProject();
    // Rows on the tracks BELOW this one: unconfigured defaults stack the
    // whole project's SE rows, so two covered tracks in the multitrack
    // stack never land on the same spot.
    var rowOffset = 0;
    for (final track in project.tracks) {
      // Cheap gate: most tracks hold no SE writing at all, and this runs
      // per painted frame per covered track.
      if (track.seLayers.isNotEmpty) {
        final start = _cutGlobalStartFrameIn(track, cut.id);
        if (start != null) {
          return resolveSeNameTagsAt(
            trackSeLayers: track.seLayers,
            cutStartFrame: start,
            localFrameIndex: localFrame,
            canvas: cut.canvasSize,
            cameraFrame: cameraFrameSize,
            rowOffset: rowOffset,
          );
        }
      }
      rowOffset += track.seLayers.length;
    }
    return const [];
  }

  /// The GLOBAL track layer for [layerId] (never a display clone).
  Layer? trackSeGlobalLayerById(LayerId layerId) {
    for (final layer in activeTrack.seLayers) {
      if (layer.id == layerId) {
        return layer;
      }
    }
    return null;
  }

  /// Display-clone cache (UI-R20 #4): the clones used to be rebuilt on
  /// EVERY read, so every session notify handed the grids fresh Layer
  /// identities — defeating all the identity-keyed row memos and
  /// rebuilding every SE row per notify (the "selecting a layer got slow
  /// after adding dialogue" regression). Keyed per SE layer: same source
  /// layer + same window = the SAME clone instance back.
  final Map<LayerId, (Layer, int, int, Layer)> _seDisplayCloneCache = {};

  Layer _trackSeDisplayCloneFor(TrackSeWindow window, Layer layer) {
    final cached = _seDisplayCloneCache[layer.id];
    if (cached != null &&
        identical(cached.$1, layer) &&
        cached.$2 == window.cutStartFrame &&
        cached.$3 == window.cutDurationFrames) {
      return cached.$4;
    }
    final display = window.displayLayer(layer);
    _seDisplayCloneCache[layer.id] = (
      layer,
      window.cutStartFrame,
      window.cutDurationFrames,
      display,
    );
    return display;
  }

  /// The folder BAND cache (R10): a folder row's display clone, whose
  /// `timeline` IS its subtree's exposure union.
  ///
  /// A folder Layer is empty — no frames, no timeline — so handing it to
  /// the shared cells painter paints a blank row, which is exactly what
  /// the X-sheet has been doing all along. Giving the clone the union as
  /// an ordinary timeline is what lets a folder row BE a cells row: the
  /// coverage question answers in O(log runs) off the standard raw value,
  /// with no per-cell walk and no new painter input.
  ///
  /// Identity is the whole point, and the same reason [_seDisplayCloneCache]
  /// exists: repaint, the tile bake key and the row memo all compare the
  /// Layer INSTANCE, and a folder's own instance does not move when a
  /// member is edited. Same union ⇒ the same clone back, so nothing
  /// re-records; a changed union ⇒ a new instance, so everything does.
  ///
  /// R5 #2: the key is the union AND the folder itself. The union alone was
  /// a cache key for the BAND, and the band is what this was written for —
  /// but the clone the rails render is the whole ROW, so every folder field
  /// that is not an exposure rode a key that could not see it change.
  /// Collapsing a folder, renaming it, picking a blend, flipping its eye:
  /// none of those move a member's exposure, so `listEquals` said "same"
  /// and handed back the clone from BEFORE the edit, forever. The rail row
  /// memo then compared that stale clone's fields and skipped its rebuild,
  /// which is why the twirl and the blend chip read as dead controls.
  /// A cache that stands in for a value must key on everything that value
  /// carries, not on the part it was built to summarise.
  final Map<
    LayerId,
    ({List<({int start, int endExclusive})> runs, Layer source, Layer band})
  >
  _folderBandCache = {};

  /// The stack the cache was filled from — a different stack identity means
  /// the members may have moved even where the runs did not.
  List<Layer>? _folderBandSource;
  final Map<LayerId, List<Layer>> _folderBandMembers = {};

  void _fillFolderBandCache() {
    final stack = layers;
    if (identical(_folderBandSource, stack)) {
      return;
    }
    _folderBandSource = stack;
    _folderBandMembers.clear();
    final index = LayerFolderIndex(stack);
    for (final layer in stack) {
      if (!layerKindGroupsLayers(layer.kind)) {
        continue;
      }
      final members = index.subtreeMembersOf(layer.id);
      _folderBandMembers[layer.id] = members;
      final runs = folderAggregateRuns(members);
      final cached = _folderBandCache[layer.id];
      // The FOLDER's own instance is half the key: the repository hands back
      // the same instance while nothing about the folder changed, and a new
      // one the moment anything did.
      if (cached != null &&
          identical(cached.source, layer) &&
          listEquals(cached.runs, runs)) {
        continue;
      }
      _folderBandCache[layer.id] = (
        runs: runs,
        source: layer,
        band: layer.copyWith(
          timeline: {
            for (final run in runs)
              run.start: TimelineExposure.drawing(
                // The union's entries are AUTHORED, not ghosts, and they
                // resolve to no Frame on purpose: nothing composites a
                // folder band, it only paints.
                FrameId('band:${layer.id.value}:${run.start}'),
                length: run.endExclusive - run.start,
              ),
          },
        ),
      );
    }
    _folderBandCache.removeWhere(
      (id, _) => !_folderBandMembers.containsKey(id),
    );
  }

  /// [folder]'s row as the grids should render it — the union band. Never
  /// leaves the display path: commands re-read the real layer by id.
  Layer folderBandLayerFor(Layer folder) {
    if (!layerKindGroupsLayers(folder.kind)) {
      return folder;
    }
    _fillFolderBandCache();
    return _folderBandCache[folder.id]?.band ?? folder;
  }

  /// The folder's subtree members — the empty-cel tint's union (R28 #11).
  List<Layer> folderBandMembersOf(LayerId folderId) {
    _fillFolderBandCache();
    return _folderBandMembers[folderId] ?? const [];
  }

  /// The folder's merged exposure runs — the range selection's snap lane.
  List<({int start, int endExclusive})> folderBandRunsOf(LayerId folderId) {
    _fillFolderBandCache();
    return _folderBandCache[folderId]?.runs ?? const [];
  }

  /// The track's SE rows as cut-local display clones for the active cut.
  ///
  /// While a take rolls, the armed lane shows its PREVIEW state (REC1-C):
  /// the in-flight take landed by the same planner the stop will use —
  /// commits and undo keep reading the repository lane untouched.
  List<Layer> get trackSeDisplayLayers {
    final window = trackSeWindow;
    final preview = voiceRecordPreviewLane.value;
    return [
      for (final layer in activeTrack.seLayers)
        _trackSeDisplayCloneFor(
          window,
          preview != null && preview.id == layer.id ? preview : layer,
        ),
    ];
  }

  /// The track's TRANSITION row as a cut-local display clone — the camera
  /// section's read-only third row.
  ///
  /// 🚨 Unlike the SE clones this is a PROJECTION, not a window
  /// ([transitionMarkInCut]): a span that crosses this cut's boundary shows
  /// at its FULL length on the side it belongs to, because half a bowtie
  /// says nothing to whoever is reading the row. The clone therefore does
  /// NOT describe where the span really is — the global row does that, and
  /// the global row is the only one that may be edited.
  ///
  /// Cached on the same terms as the SE clones: same source layer + same
  /// window = the same instance back, so identity-keyed row memos hold.
  Layer get trackTransitionDisplayLayer {
    final source = activeTrack.transitionLayer;
    final cutStart = activeCutGlobalStartFrame;
    final duration = activeCutOrNull?.duration ?? 0;
    final cached = _transitionDisplayClone;
    if (cached != null &&
        identical(cached.$1, source) &&
        cached.$2 == cutStart &&
        cached.$3 == duration) {
      return cached.$4;
    }
    final projected = SplayTreeMap<int, InstructionEvent>();
    // D26: the crossing answer is recorded under the PROJECTED key in the
    // same walk — the clone re-keys spans to cut-local starts, so a marker
    // bound by global key alone would miss or mis-mark projected blocks.
    final crossing = <int>{};
    for (final entry in source.instructions.entries) {
      final span = _transitionSpanOf(entry);
      final mark = transitionMarkInCut(
        span: span,
        cutStart: cutStart,
        cutEnd: cutStart + duration,
      );
      if (mark == null) {
        continue;
      }
      projected[mark.start] = entry.value;
      if (oneSidedSpanCrossesOwnCut(
        span: span,
        cutStart: cutStart,
        cutEnd: cutStart + duration,
      )) {
        crossing.add(mark.start);
      }
    }
    final display = source.copyWith(instructions: projected);
    _transitionDisplayClone = (source, cutStart, duration, display, crossing);
    return display;
  }

  (Layer, int, int, Layer, Set<int>)? _transitionDisplayClone;

  /// D26: the crossing-fade warning for the CUT-VIEW transition row, by
  /// the display clone's projected local start key. The answer is computed
  /// in [trackTransitionDisplayLayer]'s own projection walk with the SAME
  /// predicate the apply gate reads ([oneSidedSpanCrossesOwnCut]) — the
  /// T25 one-sentence law: the refusal and the warning cannot drift.
  String? transitionCrossingWarningInCutAt(int projectedStartKey) {
    // Resolve the clone first so the cache always answers for the active
    // cut the row is actually showing.
    trackTransitionDisplayLayer;
    return (_transitionDisplayClone?.$5.contains(projectedStartKey) ?? false)
        ? AppText.strings.tlTransitionCrossingWarning
        : null;
  }

  /// D26: the same warning for the GLOBAL authoring row (the storyboard's
  /// transition row), by the span's global start key. Walks the cuts the
  /// storyboard's own way (gap, then duration) to find the owning cut; a
  /// gap-anchored fade has no owner, is already inert today, and stays
  /// quietly unmarked.
  String? transitionCrossingWarningAtGlobalKey(int globalStartKey) {
    final event = activeTrack.transitionLayer.instructions[globalStartKey];
    if (event == null) {
      return null;
    }
    final span = _transitionSpanOf(MapEntry(globalStartKey, event));
    if (transitionSidesOf(span.mark) == TransitionSides.both) {
      return null;
    }
    var start = 0;
    for (final cut in activeTrack.cuts) {
      start += cut.leadingGapFrames;
      final cutEnd = start + cut.duration;
      if (oneSidedSpanOwnsCut(span: span, cutStart: start, cutEnd: cutEnd)) {
        return oneSidedSpanCrossesOwnCut(
              span: span,
              cutStart: start,
              cutEnd: cutEnd,
            )
            ? AppText.strings.tlTransitionCrossingWarning
            : null;
      }
      start = cutEnd;
    }
    return null;
  }

  /// The track SE rows whose display clone starts with a spill-in block —
  /// a sound carrying over from an earlier cut (UI-R7 #6: the timeline
  /// draws the `~` continuation at the cut start and drops the start
  /// grip; the block's real start lives in that earlier cut).
  Set<LayerId> get trackSeSpillInLayerIds {
    final window = trackSeWindow;
    return {
      for (final layer in activeTrack.seLayers)
        if (window.spillInBlock(layer) != null) layer.id,
    };
  }

  void _refreshAfterCutCommand({
    LayerId? preferredActiveLayerId,
    int? preferredFrameIndex,
  }) {
    _copiedFrame = null;
    clearFrameRangeSelection();
    _rebuildActiveCutControllers(
      // The ACTIVE layer survives cut commands by default (UI-R20 #1:
      // adding a camera key must not throw the selection to the bottom
      // row) — commands that switch cuts fall back naturally because the
      // old layer fails the has-layer check.
      preferredActiveLayerId: preferredActiveLayerId ?? activeLayerId,
      preferredFrameIndex:
          preferredFrameIndex ?? _timelineController.currentFrameIndex,
    );
    // Layer add/delete/undo may have moved the active row: keep the solo
    // mode following it (or exit if the command switched cuts).
    _syncVisibilitySolo();
    _warmActiveCut();
  }

  /// The cut with [cutId] anywhere in the project, or `null`.
  Cut? cutById(CutId cutId) {
    for (final track in _repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        if (cut.id == cutId) {
          return cut;
        }
      }
    }
    return null;
  }

  /// The brush store key of a layer frame within [cut] — same derivation the
  /// canvas selection uses (track containing the cut, first track fallback).
  BrushFrameKey brushFrameKeyForCut(Cut cut, LayerId layerId, FrameId frameId) {
    final project = _repository.requireProject();
    var trackId = project.tracks.isEmpty
        ? const TrackId('')
        : project.tracks.first.id;
    for (final track in project.tracks) {
      if (track.cuts.any((candidate) => candidate.id == cut.id)) {
        trackId = track.id;
        break;
      }
    }
    return BrushFrameKey(
      projectId: project.id,
      trackId: trackId,
      cutId: cut.id,
      layerId: layerId,
      frameId: frameId,
    );
  }

  /// A5 — the trailing edge of an edit burst, so the warming queue
  /// restarts ONCE per burst instead of once per dab commit. Only the
  /// RESTART is deferred: the cache invalidations and the yield signal
  /// stay synchronous, because a stale composite must be unservable the
  /// instant the stroke lands. The window costs nothing in production —
  /// warming cannot start until [PlaybackPrerenderScheduler.idleDelay]
  /// (1200ms) of quiet anyway, so any window under that only merges
  /// restarts it never delays.
  Timer? _warmDebounce;

  static final Duration _warmDebounceWindow =
      Platform.environment['FLUTTER_TEST'] == 'true'
      // Tests: next-turn, mirroring the scheduler's zero idleDelay — a
      // pending 200ms timer at teardown trips the binding's timer
      // invariant before the session's tearDown dispose runs. Zero still
      // debounces: a synchronous burst re-arms one timer and fires once.
      ? Duration.zero
      : const Duration(milliseconds: 200);

  void _onBrushFrameInvalidated(BrushFrameCacheInvalidation invalidation) {
    layerFrameImageCache.invalidateFrame(invalidation.frameKey);
    cutFrameCompositeCache.invalidateWhereLayerFrame(
      layerId: invalidation.frameKey.layerId,
      frameId: invalidation.frameKey.frameId,
    );
    // Warming yields to the edit and then re-renders the dirty frames.
    prerenderScheduler.notifyEditActivity();
    _warmDebounce?.cancel();
    _warmDebounce = Timer(_warmDebounceWindow, () {
      _warmDebounce = null;
      if (_disposed) {
        return;
      }
      _warmActiveCut();
    });
  }

  /// Warms the active cut's composites around the playhead ("navigate away
  /// from a frame and it gets pre-rendered") — and the NEXT cut behind it
  /// (#31, 유저 확정: 스토리보드 프로의 룩어헤드를 따른다). The next cut
  /// is next in STORYBOARD order, the same order play-all and the panel
  /// read, so the bar that goes green is the bar beside the one you are
  /// on.
  void _warmActiveCut() {
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    prerenderScheduler.requestWarmCut(
      cutId: cut.id,
      quality: playbackQuality,
      aroundFrameIndex: _timelineController.currentFrameIndex,
      followedByCutId: _nextCutIdInStoryboardOrder(cut.id),
    );
  }

  /// The cut after [cutId] in storyboard order, or null at the end.
  CutId? _nextCutIdInStoryboardOrder(CutId cutId) {
    final layout = _projectLayout();
    for (var index = 0; index < layout.length; index += 1) {
      if (layout[index].cutId == cutId) {
        return index + 1 < layout.length ? layout[index + 1].cutId : null;
      }
    }
    return null;
  }

  @override
  void dispose() {
    // First: a bake sweep suspended across an engine await must find the
    // flag set when it resumes — it stops touching the stores and never
    // notifies a disposed ChangeNotifier.
    _disposed = true;
    _textCelSweepDirty = false;
    brushFrameStore.celContentRevision.removeListener(_bumpCelTintRevision);
    brushInputActive.removeListener(_bumpCelTintRevision);
    celTintRevision.dispose();
    currentRowListenable.dispose();
    rowSelection.dispose();
    laneRangeSelection.removeListener(_publishCutLocalLaneRange);
    cutLocalLaneRangeSelection.dispose();
    revealSelectionTick.dispose();
    _warmDebounce?.cancel();
    cacheInvalidationHub.removeBrushFrameListener(_onBrushFrameInvalidated);
    playback.globalFrameIndexListenable.removeListener(_followPlaybackCut);
    _historyManager.removeListener(_markProjectDirty);
    _historyManager.removeListener(_refreshLiveAudioSchedule);
    _historyManager.removeListener(_scheduleTextCelBakeSweep);
    _voiceRecording.dispose();
    audioPlaybackSync.dispose();
    audioScrubber.dispose();
    audioDeviceTransport.dispose();
    playback.dispose();
    prerenderScheduler.dispose();
    cutFrameCompositeCache.dispose();
    layerFrameImageCache.dispose();
    audioConformStore.dispose();
    _appSettings.dispose();
    soloedSeLayerIds.dispose();
    editingFrameCursor.dispose();
    frameScrubActive.dispose();
    frameSeekCommitted.dispose();
    _gapGlobalFrameNotifier.dispose();
    frameRangeSelection.dispose();
    brushInputActive.dispose();
    selectionInteractionActive.dispose();
    dragPreview.dispose();
    transitionEdgeDragPreview.dispose();
    opacityDragPreview.dispose();
    onionSkinSettings.dispose();
    onionSkinLayerIds.dispose();
    trackFrameRangeSelection.dispose();
    _historyManager.dispose();
    super.dispose();
  }

  /// Test seam: widget tests inject a store with a fake runner so SE rows
  /// never decode real files.
  final AudioConformStore? _injectedAudioConformStore;

  /// Conformed audio per source path (audio program wiring): waveform
  /// peaks, exact clip lengths and the device transport's PCM, decoded
  /// ONCE per file off the UI isolate. Conforms live in the app container
  /// (or a drive the user named), in a folder per project, under a name
  /// derived by rule from the source path — nothing recorded, nothing to
  /// fall out of sync.
  late final AudioConformStore audioConformStore =
      (_injectedAudioConformStore ??
            AudioConformStore(
              resolveConformPath: _conformPathFor,
              resolveProjectSampleRate: () =>
                  _repository.requireProject().audioSampleRate,
              resolveAudioSpeed: () {
                final project = _repository.requireProject();
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
        ..addListener(notifyListeners);

  /// Resolved per call rather than cached: the cache root is a live
  /// setting and the project's rate and speed are live settings too, so a
  /// conform path held from before any of them would name a file nothing
  /// writes to.
  ///
  /// Never null now. It used to be, for a project with no path — the cache
  /// was named after the project, so an unsaved one had no name to cache
  /// under and re-decoded its audio every launch. Keying by source removed
  /// the question.
  String? _conformPathFor(String sourcePath) {
    final project = _repository.requireProject();
    return ConformCacheLayout.forAudio(
      sampleRate: project.audioSampleRate,
      speedNumerator: project.audioSpeedNumerator,
      speedDenominator: project.audioSpeedDenominator,
    ).conformPathFor(sourcePath);
  }

  /// Every audio path the project references (SE clips + the SOUND entries
  /// of the media pool) — what a project open warms so waveforms and
  /// playback PCM are ready before the first play.
  ///
  void _warmAudioConforms() {
    audioConformStore.warmPaths(
      projectAudioSourcePaths(_repository.requireProject()),
    );
  }

  /// Settles the conform cache's size — ON PROJECT OPEN ONLY.
  ///
  /// That is the moment a fresh batch of conforms is about to be built, so
  /// it is where the bound is worth enforcing, and it costs one directory
  /// scan instead of one per conform on the UI isolate. Pruning FIRST also
  /// means the entries this project is about to touch are the newest in
  /// the cache, so they are the last things a later prune considers.
  ///
  /// ⛔ NOT on the audio-settings knobs. Warming happens there too — a
  /// rate or speed change re-keys every conform — but a directory walk on
  /// the UI isolate is not something to hang off a knob somebody drags
  /// through four values to compare them ([[old-device-support-policy]]).
  ///
  /// The store lets go BEFORE the collector runs. A conform past the
  /// streaming threshold is held with no resident PCM and the file as the
  /// copy of record, so pruning one out from under a live entry leaves the
  /// clip silent for the session — see [AudioConformStore.releaseDiskBacked].
  ///
  /// ⚠️ Deliberately NOT switched off under `FLUTTER_TEST`. The root is
  /// already redirected to a temp folder there, and a call site compiled
  /// out of every test is a call site with no observer — which is how the
  /// path assembly went unwatched before ([[verify-before-claiming-shared]]).
  /// It costs nothing when the cache does not exist yet, which is the
  /// state every test starts in.
  void _settleConformCache() {
    audioConformStore.releaseDiskBacked();
    pruneConformCache();
  }

  bool _activeCutHasLayer(LayerId? layerId) {
    if (layerId == null) {
      return false;
    }
    final cut = activeCutOrNull;
    if (cut == null) {
      return false;
    }
    if (cut.layers.any((layer) => layer.id == layerId)) {
      return true;
    }
    // Track-SE rows are selectable layers too (W4): their selection
    // survives cut commands the same way (UI-R20 #1).
    return isTrackSeLayerId(layerId) &&
        activeTrack.seLayers.any((layer) => layer.id == layerId);
  }

  // --- Cut commands -------------------------------------------------------

  /// #18 — WHERE Create Cut lands right now, or null when nowhere.
  ///
  /// 유저: 「인덱스를 갭에 둔 상태로 컷생성도안되고 선택범위하고 컷생성도안됨.
  /// (…) 갭에서 컷생성누르면 스토리보드엔 컷 안생기는데 버튼쪽(…)은 활성화됨.」
  ///
  /// The old path asked NOTHING: `createCut()` took no arguments, the
  /// coordinator anchored on the active cut alone, and a gap press
  /// appended at the track's end — the cut did not fail to appear, it
  /// appeared somewhere else, which is why the frame buttons lit up.
  ///
  /// ★The same ladder as [deleteSubject]/[editInstanceSubject], the same
  /// order: the RANGE speaks first (it was said out loud), the parked
  /// playhead second, the active cut last. And per T25, this ONE
  /// expression answers both the pill button's enabled and the verb's
  /// dispatch — two sources is exactly how the button lied in the gap.
  ///
  /// The range rung answers only when the range lies entirely in EMPTY
  /// track space — a cut cannot be created over cuts, and saying null
  /// here is what turns the button off instead of letting it lie.
  ({TrackId trackId, int? index, int leadingGapFrames, int? duration})?
  get cutCreationPlan {
    final range = trackFrameRangeSelection.value;
    if (range != null && range.trackId == selectedTrackId) {
      final axis = trackFrameAxis();
      if (axis
          .cutsIn(range.startFrame, range.endFrameExclusive)
          .isNotEmpty) {
        return null;
      }
      return _cutCreationAt(
        axis,
        range.startFrame,
        duration: range.endFrameExclusive - range.startFrame,
      );
    }
    final parked = gapParkedGlobalFrame;
    if (parked != null) {
      return _cutCreationAt(trackFrameAxis(), parked, duration: null);
    }
    // The active-cut posture keeps its shape: the coordinator anchors to
    // the right of the active cut (or the track's end), unchanged.
    return (
      trackId: selectedTrackId,
      index: null,
      leadingGapFrames: 0,
      duration: null,
    );
  }

  /// The insertion a GLOBAL frame names: in front of the first cut that
  /// starts past it, with the walk-in distance from the gap's start as
  /// the new cut's own leading gap. The frame is in a gap by the callers'
  /// construction, so `gapStart <= globalFrame` always holds.
  ({TrackId trackId, int? index, int leadingGapFrames, int? duration})
  _cutCreationAt(TrackFrameAxis axis, int globalFrame, {int? duration}) {
    var index = 0;
    var gapStart = 0;
    for (final entry in axis.entries) {
      if (entry.startFrame > globalFrame) {
        break;
      }
      index += 1;
      gapStart = entry.endFrame;
    }
    return (
      trackId: selectedTrackId,
      index: index,
      leadingGapFrames: globalFrame - gapStart,
      duration: duration,
    );
  }

  /// The pill button reads THIS — the same sentence the verb runs on.
  bool get canCreateCut => cutCreationPlan != null;

  void createCut() {
    final plan = cutCreationPlan;
    if (plan == null) {
      return;
    }
    _cutCommandCoordinator.createCut(
      trackId: plan.trackId,
      // New cuts inherit the active cut's canvas size, like new scenes in
      // TVPaint/Clip Studio inherit the project size.
      canvasSize: activeCutOrNull?.canvasSize,
      placement: plan.index == null
          ? null
          : (
              index: plan.index,
              leadingGapFrames: plan.leadingGapFrames,
              duration: plan.duration,
            ),
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  void resizeActiveCutCanvas(
    CanvasSize canvasSize, {
    CanvasResizeAnchor anchor = CanvasResizeAnchor.center,
  }) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.resizeCutCanvas(
      cutId: cutId,
      canvasSize: canvasSize,
      anchor: anchor,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  void duplicateActiveCut() {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.duplicateCut(
      sourceCutId: cutId,
      targetTrackId: selectedTrackId,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  void deleteActiveCut() {
    // With a cut RANGE selection live, the delete command acts on the
    // whole run instead of the active cut (UI-R18 #1).
    if (storyboardSelectedCutIds.isNotEmpty) {
      deleteSelectedCuts();
      return;
    }
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.deleteCut(cutId: cutId);
    _refreshAfterCutCommand();
    notifyListeners();
  }

  CutPosition? get _activeCutPositionOrNull {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return null;
    }
    return _cutReorderPlanner.findCutPosition(
      project: _repository.requireProject(),
      cutId: cutId,
    );
  }

  CutPosition get _activeCutPosition {
    final position = _activeCutPositionOrNull;
    if (position == null) {
      throw StateError('Active Cut not found: ${_editingSession.activeCutId}');
    }
    return position;
  }

  bool get canMoveActiveCutLeft {
    final position = _activeCutPositionOrNull;
    return position != null && _cutReorderPlanner.canMoveLeft(position);
  }

  bool get canMoveActiveCutRight {
    final position = _activeCutPositionOrNull;
    return position != null && _cutReorderPlanner.canMoveRight(position);
  }

  void moveActiveCutLeft() {
    final position = _activeCutPosition;
    if (!_cutReorderPlanner.canMoveLeft(position)) {
      return;
    }

    _cutCommandCoordinator.reorderCut(
      trackId: position.trackId,
      cutId: position.cutId,
      newIndex: _cutReorderPlanner.moveLeftTargetIndex(position),
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  void moveActiveCutRight() {
    final position = _activeCutPosition;
    if (!_cutReorderPlanner.canMoveRight(position)) {
      return;
    }

    _cutCommandCoordinator.reorderCut(
      trackId: position.trackId,
      cutId: position.cutId,
      newIndex: _cutReorderPlanner.moveRightTargetIndex(position),
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  String? get activeCutNote => activeCutOrNull?.metadata.note;

  void updateActiveCutNote(String note) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.updateCutNote(cutId: cutId, note: note);
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Whether the active cut's storyboard thumbnail is pinned to the
  /// playhead frame (drives the toolbar toggle's state).
  bool get isActiveCutThumbnailPinnedHere =>
      activeCutOrNull?.metadata.thumbnailFrameIndex ==
          _timelineController.currentFrameIndex &&
      activeCutOrNull?.metadata.thumbnailFrameIndex != null;

  /// Pins the active cut's storyboard thumbnail to the playhead frame, or
  /// releases the pin back to the first frame when pressed on the pinned
  /// frame itself (toggle; one undo step either way).
  void toggleActiveCutThumbnailFrame() {
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    final frame = _timelineController.currentFrameIndex;
    final pinned = cut.metadata.thumbnailFrameIndex;
    _cutCommandCoordinator.updateCutThumbnailFrame(
      cutId: cut.id,
      frameIndex: pinned == frame ? null : frame,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  Cut? get activeCutOrNull {
    final project = _repository.requireProject();
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id == _editingSession.activeCutId) {
          return cut;
        }
      }
    }

    return null;
  }

  int get activeCutPlaybackFrameCount =>
      math.max(1, activeCutOrNull?.duration ?? 1);

  /// How many frames the active cut is DRAWN for: its conte 尺 plus the
  /// のりしろ every transition span crossing one of its boundaries asks for.
  /// Equal to [activeCutPlaybackFrameCount] whenever nothing crosses.
  ///
  /// ★The same number the sheet pages by and prints in parentheses
  /// (`2+0 (2+12)`), read from the same derivation — the ruler's blue line and
  /// the sheet's row count cannot disagree about how much there is to draw.
  int get activeCutDrawnFrameCount {
    final cut = activeCutOrNull;
    if (cut == null) {
      return activeCutPlaybackFrameCount;
    }
    final start = activeCutGlobalStartFrame;
    return cutTransitionHandles(
      cutStart: start,
      cutEnd: start + cut.duration,
      spans: activeTrackTransitionSpans,
    ).drawnFrames(activeCutPlaybackFrameCount);
  }

  /// What the ruler writes across that margin: the TERM that asked for it, then
  /// the word — "O.L のりしろ", "O.L 여백" (user 2026-08-10, "그럼 뭐때문에 여백
  /// 길이가 생겼는지 아니까"). Empty when nothing crosses this cut.
  ///
  /// Every span that FIRES on this cut is named, not just one: head and tail
  /// handles add up, so with a transition at each boundary no single term set
  /// the length and claiming one would be a half-truth.
  String get activeCutNoriShiroLabel {
    final cut = activeCutOrNull;
    if (cut == null) {
      return '';
    }
    final start = activeCutGlobalStartFrame;
    final end = start + cut.duration;
    final terms = <String>[];
    for (final entry in activeTrack.transitionLayer.instructions.entries) {
      if (!transitionSpanFires(
        span: _transitionSpanOf(entry),
        cutStart: start,
        cutEnd: end,
      )) {
        continue;
      }
      final term = entry.value.displayLabel(
        cameraInstructionSet.defById(entry.value.instructionId),
      );
      if (term.isNotEmpty && !terms.contains(term)) {
        terms.add(term);
      }
    }
    if (terms.isEmpty) {
      return '';
    }
    return '${terms.join('/')} ${uiStrings.tlNoriShiro}';
  }

  /// R27 #31: the cut an EXPORT anchors on. Parking the playhead in a gap
  /// leaves no active cut, but that is a playhead position — not "no
  /// film" — so the export window must still open (it used to throw
  /// [requireActiveCut] straight through the dialog's build and take the
  /// whole app down with it). Falls back to the first cut on the axis;
  /// null only when the project genuinely has no cuts at all, which is
  /// what disables the Export entry point.
  Cut? get exportAnchorCutOrNull {
    final active = activeCutOrNull;
    if (active != null) {
      return active;
    }
    for (final track in _repository.requireProject().tracks) {
      if (track.cuts.isNotEmpty) {
        return track.cuts.first;
      }
    }
    return null;
  }

  /// Whether an export would run off [exportAnchorCutOrNull]'s FALLBACK
  /// rather than a live selection — the window then defaults its scope to
  /// the whole project instead of silently exporting a cut the user is
  /// not standing on.
  bool get exportAnchorIsFallback =>
      activeCutOrNull == null && exportAnchorCutOrNull != null;

  /// The active cut, THROWING when none is selected (gap state) — every
  /// caller is a conscious decision that a cut must exist here (UI-R9 #3
  /// audit rename; reach for [activeCutOrNull] on read paths instead).
  Cut get requireActiveCut {
    final cut = activeCutOrNull;
    if (cut == null) {
      throw StateError(
        'No active Cut (gap state): ${_editingSession.activeCutId}',
      );
    }
    return cut;
  }

  void renameActiveCut(String newName) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.renameCut(cutId: cutId, newName: newName);
    _refreshAfterCutCommand();
    notifyListeners();
  }

  // --- Camera --------------------------------------------------------------

  CutCamera get activeCutCamera => requireActiveCut.camera;

  /// The camera's output frame size (the exported picture size); the camera
  /// view rect on canvas is this divided by the pose zoom.
  CanvasSize get cameraFrameSize => _repository.requireProject().cameraSize;

  /// The exact rate, for the surfaces that convert frames to REAL TIME
  /// (playback clock, audio placement, export). Everything that merely
  /// COUNTS frames wants [projectFps] instead.
  ProjectFrameRate get projectFrameRate =>
      _repository.requireProject().frameRate;

  int get projectFps => _repository.requireProject().fps;

  /// R26 #32: sets the PROJECT's frame rate (one undo step, no-op when
  /// unchanged). Everything timed — ruler seconds, sheet rows, playback,
  /// audio placement — reads this one axis, so this single write moves
  /// the whole project's time.
  /// The active cut's drawing guides — empty when parked in a gap.
  CutGuides get activeCutGuides => activeCutOrNull?.guides ?? CutGuides.empty;

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

  /// Writes the active cut's guides, fanning out to its 겸용 siblings in one
  /// undoable step (see [SetCutGuidesCommand]).
  ///
  /// Handle DRAGS call this once, at release. The live preview in between
  /// paints from the drag layer's own value and never touches the project,
  /// so a drag is one undo entry rather than one per pointer sample.
  void setActiveCutGuides(CutGuides guides) {
    final cut = activeCutOrNull;
    if (cut == null || cut.guides == guides) {
      return;
    }
    _historyManager.execute(
      SetCutGuidesCommand(
        repository: _repository,
        cutId: cut.id,
        guides: guides,
      ),
    );
    notifyListeners();
  }

  void setProjectFrameRate(ProjectFrameRate frameRate) {
    if (frameRate.numerator < 1 ||
        frameRate.denominator < 1 ||
        frameRate.countingBase < 1 ||
        frameRate == projectFrameRate) {
      return;
    }
    _historyManager.execute(
      UpdateProjectFrameRateCommand(
        repository: _repository,
        frameRate: frameRate,
      ),
    );
    _warmActiveCut();
    notifyListeners();
  }

  /// Whole-number convenience for the callers that only ever mean an
  /// integer rate (the custom-rate dialog, tests).
  void setProjectFps(int fps) {
    if (fps < 1) {
      return;
    }
    setProjectFrameRate(ProjectFrameRate.integer(fps));
  }

  /// Whether any SE row anywhere carries a sound — what decides if a
  /// pulldown-pair rate change even asks the audio question.
  bool get projectHasAnyAudio {
    for (final track in _repository.requireProject().tracks) {
      for (final layer in track.seLayers) {
        if (layer.audioClips.isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  /// EXPORT-AUDIO ④, the "frame-exact" choice: sets the rate AND pulls
  /// the audio by the exact pulldown rational (23.976→24 = 1001/1000) so
  /// every sound keeps its frame span — one undo step for both, and the
  /// conforms rebuild at the new speed in the background. Falls back to a
  /// plain rate change when the pair carries no pull.
  void setProjectFrameRateWithAudioPull(ProjectFrameRate frameRate) {
    final pull = audioPullBetween(projectFrameRate, frameRate);
    if (pull == null) {
      setProjectFrameRate(frameRate);
      return;
    }
    final project = _repository.requireProject();
    // Pulls accumulate — and cancel: 23.976→24→23.976 lands back at 1/1.
    var numerator = project.audioSpeedNumerator * pull.numerator;
    var denominator = project.audioSpeedDenominator * pull.denominator;
    final divisor = numerator.gcd(denominator);
    numerator ~/= divisor;
    denominator ~/= divisor;
    _historyManager.execute(
      UpdateProjectFrameRateCommand(
        repository: _repository,
        frameRate: frameRate,
        audioSpeedNumerator: numerator,
        audioSpeedDenominator: denominator,
      ),
    );
    _warmAudioConforms();
    _warmActiveCut();
    notifyListeners();
  }

  /// The project's audio rate — what every conform lands at (EXPORT-AUDIO
  /// ③).
  int get projectAudioSampleRate =>
      _repository.requireProject().audioSampleRate;

  /// Sets the project's audio rate (one undo step, no-op when unchanged).
  /// Existing conforms re-build at the new rate in the background — the
  /// store treats a rate-mismatched entry as stale on its own, so undo
  /// and redo self-heal too.
  void setProjectAudioSampleRate(int sampleRate) {
    if (sampleRate < 8000 ||
        sampleRate > 192000 ||
        sampleRate == projectAudioSampleRate) {
      return;
    }
    _historyManager.execute(
      UpdateProjectAudioSampleRateCommand(
        repository: _repository,
        audioSampleRate: sampleRate,
      ),
    );
    _warmAudioConforms();
    notifyListeners();
  }

  /// Resolved camera pose at an arbitrary playback frame (for rendering).
  CameraPose cameraPoseAtFrame(int frameIndex) => resolveCameraPoseAt(
    camera: requireActiveCut.camera,
    canvasSize: requireActiveCut.canvasSize,
    frameIndex: frameIndex,
  );

  /// Resolved camera pose for any cut (play-all renders other cuts too).
  /// The camera ROW's fx switch bypasses the camera work on this render
  /// route (playback, export, storyboard thumbnails all resolve through
  /// here) — the authoring overlays keep reading the real pose.
  CameraPose cameraPoseForCut(Cut cut, int frameIndex) {
    if (_cameraFxBypassedFor(cut)) {
      return CameraPose(
        center: CanvasPoint(
          x: cut.canvasSize.width / 2,
          y: cut.canvasSize.height / 2,
        ),
      );
    }
    return resolveCameraPoseAt(
      camera: cut.camera,
      canvasSize: cut.canvasSize,
      frameIndex: frameIndex,
    );
  }

  /// Whether [cut]'s camera row has its camera work bypassed — the camera
  /// row's own transform switch (R8: persisted like every other row's).
  bool _cameraFxBypassedFor(Cut cut) {
    final camera = cut.layers.cameraLayer;
    return camera != null && !camera.transformEnabled;
  }

  /// The editing canvas's composite TREE at the playhead — the same tree
  /// playback and export composite, with the ACTIVE layer standing in it
  /// as a [CanvasActiveLayerNode] instead of a cached image.
  ///
  /// That node is the whole point: the stack used to be two flat lists
  /// painted around the interactive view, so a folder's group buffer —
  /// one `saveLayer` — could never span the layer you were drawing on.
  /// Now one painter opens the buffer, draws the live surface inside it,
  /// and closes it.
  ///
  /// [activeLayerOpacity] is the active row's display opacity (0 while
  /// hidden; includes its animated Opacity); its pose rides separately
  /// through [layerCanvasPoseSample] into the interactive draw-through
  /// wrap, so it is repeated on the node for the merged painter.
  ({List<CanvasLayerStackNode> nodes, double activeLayerOpacity})
  get editingCanvasStack {
    final cut = activeCutOrNull;
    final activeLayerId = this.activeLayerId;
    if (cut == null) {
      return (nodes: const <CanvasLayerStackNode>[], activeLayerOpacity: 1.0);
    }

    final frameIndex = _timelineController.currentFrameIndex;
    var activeLayerOpacity = 1.0;
    // Opacity drag preview (R4 #4/#6, DISPLAY only): the dragged rows'
    // static opacity substitutes in before the shared visit, so the canvas
    // follows the drag without any repo write per move.
    final preview = opacityDragPreview.value;
    List<Layer> withOpacityPreview(List<Layer> source) => preview == null
        ? source
        : [
            for (final layer in source)
              preview.layerIds.contains(layer.id) &&
                      layerKindHasPictureOpacity(layer.kind)
                  ? layer.copyWith(opacity: preview.opacity)
                  : layer,
          ];
    final stackCut = preview == null
        ? cut
        : cut.copyWith(layers: withOpacityPreview(cut.layers));

    // The CUT layers ride the shared composite TREE (skip rules, fx
    // sharing, the W5 attach-layer expansion AND the group buffers agree
    // with playback by construction).
    CanvasLayerStackNode? mapNode(CutFrameCompositeEntryNode node) {
      switch (node) {
        case CutFrameCompositeEntryGroup(
          :final children,
          :final opacity,
          :final blendMode,
          :final effects,
        ):
          final mapped = <CanvasLayerStackNode>[
            for (final child in children) ?mapNode(child),
          ];
          if (mapped.isEmpty) {
            return null;
          }
          return CanvasLayerGroupNode(
            children: List.unmodifiable(mapped),
            opacity: opacity,
            blendMode: blendMode,
            effects: effects,
          );
        case CutFrameCompositeEntryAdjustment(
          :final children,
          :final effects,
          :final mix,
        ):
          final mapped = <CanvasLayerStackNode>[
            for (final child in children) ?mapNode(child),
          ];
          if (mapped.isEmpty) {
            return null;
          }
          return CanvasLayerAdjustmentNode(
            children: List.unmodifiable(mapped),
            effects: effects,
            mix: mix,
          );
        case CutFrameCompositeEntryLeaf(:final entry):
          // A brush-banned active layer (SE/instruction, R6-④; a media
          // REFERENCE layer, §6-z23) has no interactive surface — it
          // composites like any other stack row so its existing cels keep
          // displaying read-only.
          if (entry.layer.id == activeLayerId &&
              layerAcceptsBrushInput(entry.layer)) {
            activeLayerOpacity = !entry.layer.isVisible
                ? 0.0
                : _stackLayerOpacity(entry.layer, stackCut.layers, frameIndex);
            return CanvasActiveLayerNode(
              opacity: entry.opacity,
              // The active row's CEL key — the SAME key the image branch
              // below would have requested, so the stack can keep that
              // route's image as the first-activation stand-in while the
              // promoted surface's tiles decode.
              frameKey: brushFrameKeyForCut(
                cut,
                entry.layer.id,
                entry.frame.id,
              ),
              // The SAME entry the image branch below reads it from. It was
              // dropped right here — five fields arrived and four were
              // forwarded, so standing on a multiply row silently made it
              // normal on the editing canvas only.
              blendMode: entry.blendMode,
              pose: entry.pose,
              anchorPoint: entry.anchorPoint,
              effects: entry.effects,
            );
          }
          return CanvasLayerImageNode(
            CanvasLayerImageRequest(
              frameKey: brushFrameKeyForCut(
                cut,
                entry.layer.id,
                entry.frame.id,
              ),
              opacity: entry.opacity,
              blendMode: entry.blendMode,
              pose: entry.pose,
              anchorPoint: entry.anchorPoint,
              effects: entry.effects,
            ),
          );
      }
    }

    final nodes = <CanvasLayerStackNode>[
      for (final node in resolveCutFrameCompositeTree(
        cut: stackCut,
        frameIndex: frameIndex,
      ))
        ?mapNode(node),
    ];

    // An ACTIVE layer with nothing exposed at this frame resolves no entry
    // at all, so the walk above never reaches it. It still needs its node:
    // the interactive surface is where the next stroke lands.
    final activeStackLayer = activeLayerId == null
        ? null
        : stackCut.layers.byId(activeLayerId);
    if (activeStackLayer != null &&
        !_treeHoldsActiveLayer(nodes) &&
        layerAcceptsBrushInput(activeStackLayer) &&
        // 🚨THE FOLDER CHAIN, which the tree walk applies and this block does
        // not. A row WITH a cel never reaches here — a hidden folder drops
        // its whole subtree inside `resolveCutFrameCompositeTree`, so the
        // node simply is not in the tree. A row with nothing exposed at this
        // frame took this hand-built path instead and skipped that walk, so
        // the layer you were standing on went on being drawn out of a folder
        // the user had switched off — visible on the editing canvas and
        // nowhere else, which is the worst shape a difference can take.
        stackCut.layers.rowVisible(activeStackLayer)) {
      activeLayerOpacity = _stackLayerOpacity(
        activeStackLayer,
        stackCut.layers,
        frameIndex,
      );
      // R6: the surface you are about to draw on shows the effects the
      // composite will apply to it, so the first stroke lands in the
      // picture you can see. The chain comes from the FX CARRIER exactly
      // as [resolveCutFrameCompositeEntries] resolves it for a real entry —
      // an attach row wears its BASE's effects, and it is the base's fx
      // switch that bypasses them. Reading the row's own would leave this
      // one node unfiltered until its first cel exists, then snap.
      final activeFxBase = isAttachedLayer(activeStackLayer)
          ? attachedBaseOf(activeStackLayer, stackCut.layers)
          : null;
      final activeFxCarrier = activeFxBase ?? activeStackLayer;
      nodes.add(
        CanvasActiveLayerNode(
          opacity: activeLayerOpacity,
          // The row's own blend, since this route has no composite entry to
          // read one from. ⚠️That is the whole problem with this block and
          // not just with this field — it re-derives by hand what the plan
          // already knows, which is why it also loses the folder chain, the
          // group buffer and its z-position. Fixing THAT retires this
          // argument along with the rest of the block.
          blendMode: activeStackLayer.blendMode,
          // No master gate here: each effect's own switch gates it inside
          // the resolve, so this route cannot forget one (R8).
          effects: resolveLayerEffectsAt(
            effects: activeFxCarrier.effects,
            frameIndex: frameIndex,
          ),
        ),
      );
    }

    // Track-owned SE rows join as their cut-local display clones — they
    // composite read-only like before the ownership move (their transform
    // tracks are stripped, so the plain resolve path suffices). They live
    // outside the cut's stack, so they land at the top level.
    for (final layer in withOpacityPreview(trackSeDisplayLayers)) {
      if (!layer.isVisible || layer.opacity <= 0) {
        continue;
      }
      final opacity = layer.transformEnabled
          ? resolveLayerEffectiveOpacityAt(layer: layer, frameIndex: frameIndex)
          : layer.opacity.clamp(0.0, 1.0).toDouble();
      if (opacity <= 0) {
        continue;
      }
      final frame = resolveExposedFrameAt(layer, frameIndex);
      if (frame == null) {
        continue;
      }
      nodes.add(
        CanvasLayerImageNode(
          CanvasLayerImageRequest(
            frameKey: brushFrameKeyForCut(cut, layer.id, frame.id),
            opacity: opacity,
            pose: null,
            anchorPoint: null,
          ),
        ),
      );
    }
    return (
      nodes: List.unmodifiable(nodes),
      activeLayerOpacity: activeLayerOpacity,
    );
  }

  static bool _treeHoldsActiveLayer(List<CanvasLayerStackNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case CanvasActiveLayerNode():
          return true;
        case CanvasLayerGroupNode(:final children):
        case CanvasLayerAdjustmentNode(:final children):
          if (_treeHoldsActiveLayer(children)) {
            return true;
          }
        case CanvasLayerImageNode():
          break;
      }
    }
    return false;
  }

  /// The display opacity the editing stack (and the interactive view's
  /// dimming) uses for [layer]: the shared composite semantics — an attach
  /// layer multiplies its own static opacity with its BASE's animated
  /// Opacity sample (fx shared), a regular layer with its own.
  /// The active row's opacity for a view that draws it ALONE — the
  /// interactive canvas during a ruler scrub, where nothing else composites
  /// it and no folder buffer stands above it.
  ///
  /// 🚨THIS IS NOT `entry.opacity`, and the two must not be unified. An
  /// entry's opacity is BUFFER-RELATIVE: inside a buffering folder it is
  /// 1.0, because the folder node applies the folder's share once to the
  /// composed buffer. A standalone draw has no such buffer, so it needs the
  /// whole chain folded in — which is why the folder factor is here and not
  /// there.
  ///
  /// It used to stop at the row's own opacity, so scrubbing the ruler showed
  /// a row inside a half-opacity folder at FULL row opacity while every
  /// other row honoured the folder. Same shape as the rest of this round:
  /// the active row answered a question differently from everyone else.
  double _stackLayerOpacity(Layer layer, List<Layer> layers, int frameIndex) {
    final base = isAttachedLayer(layer) ? attachedBaseOf(layer, layers) : null;
    final fxCarrier = base ?? layer;
    var opacity = layer.opacity;
    // The animated Opacity is a TRANSFORM property, so its own group's
    // switch decides it — not the row master (R8).
    if (fxCarrier.transformEnabled) {
      opacity *= resolveOpacityTrackAt(
        fxCarrier.transformTrack.opacity,
        frameIndex,
      );
    }
    for (final folder in layers.ancestryOf(layer.folderId)) {
      opacity *= resolveFolderOpacityAt(folder: folder, frameIndex: frameIndex);
    }
    return opacity.clamp(0.0, 1.0).toDouble();
  }

  /// The geometric pose sample the interactive canvas shows for [layerId]
  /// at the playhead — the draw-through wrap input. Null = identity (no
  /// transform work, fx bypassed, or no such layer), which skips the wrap:
  /// the ALWAYS-APPLIED rule (the active layer shows its transform too; the
  /// old edit-in-artwork-space rule is retired, R3 ⑩).
  LayerPoseSample? layerCanvasPoseSample(LayerId layerId) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return null;
    }
    for (final layer in cut.layers) {
      if (layer.id != layerId) {
        continue;
      }
      // An attach layer rides its BASE's transform (fx shared, W5): the
      // interactive view wraps in the base's pose so drawing on the attach
      // row lines up with the composite.
      final fxCarrier = isAttachedLayer(layer)
          ? (attachedBaseOf(layer, cut.layers) ?? layer)
          : layer;
      if (!fxCarrier.transformEnabled) {
        return null;
      }
      final pose = resolveLayerPoseAt(
        layer: fxCarrier,
        canvasSize: cut.canvasSize,
        frameIndex: _timelineController.currentFrameIndex,
      );
      if (pose == null) {
        return null;
      }
      return (
        pose: pose,
        anchorPoint: resolveLayerAnchorPointAt(
          layer: fxCarrier,
          frameIndex: _timelineController.currentFrameIndex,
        ),
      );
    }
    return null;
  }

  /// The track that owns [cutId] — the V effects' home (R4: the transform
  /// lanes are TRACK data on the global axis, like the SE rows).
  Track? trackOwningCut(CutId cutId) {
    for (final track in _repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        if (cut.id == cutId) {
          return track;
        }
      }
    }
    return null;
  }

  // `transformTrackForCut` retired with the V row's transform: every route
  // that asked for a track pose or fade now has neither to apply.

  /// [cutId]'s owning track's EFFECT chain — the V row's fx, which every
  /// route that draws this cut filters its finished picture through. Empty
  /// for an orphan, and empty is the zero-cost path.
  List<LayerEffect> trackEffectsForCut(CutId cutId) =>
      trackOwningCut(cutId)?.effects ?? const [];

  /// The GLOBAL frame of [cutId]'s local [frameIndex] on its track's axis
  /// — what the track-owned lanes are keyed in.
  int trackGlobalFrameOf(CutId cutId, int frameIndex) {
    for (final entry in buildStoryboardTimelineLayout(
      _repository.requireProject(),
    )) {
      if (entry.cutId == cutId) {
        return entry.startFrame + frameIndex;
      }
    }
    return frameIndex;
  }

  // `activeCutCanvasPoseSample` retired with the V row's transform: there is
  // no track pose for the editing canvas or the scrub preview to apply.

  /// The fade the editing canvas (and the scrub preview) shows at
  /// [frameIndex] (default: the playhead).
  ///
  /// The animated half is the TRANSITION row's now (an F.O span thins the cut
  /// toward its end), so this is the track's STATIC opacity times the cut's
  /// own transition ramp. R9 #21 still holds for the static half: it is not an
  /// fx, so the fx bypass does not touch it.
  ///
  /// 🚨The RAMP, not [cutOpacityAt]. That one also answers the compositor's
  /// material question — 0 outside the cut's media range — and the playhead
  /// is unclamped (T12), so standing past the end line handed the fade wash
  /// a 0 and the wash painted an opaque backdrop plate over the paper and
  /// every drawing under it: 「캔버스가 용지나 그림이 사라짐」, with the
  /// paper's antialiased edge peeking past the plate as the stray white
  /// outline. Standing somewhere is not compositing a playlist; the frames
  /// past the end line are ordinary space and only a covering span may thin
  /// them.
  double activeCutEditingFadeOpacity({int? frameIndex}) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return 1;
    }
    final static = trackStaticOpacityForCut(cut.id);
    final start = activeCutGlobalStartFrame;
    return static *
        cutTransitionRampAt(
          cutStart: start,
          cutEnd: start + cut.duration,
          spans: activeTrackTransitionSpans,
          globalFrame:
              start + (frameIndex ?? _timelineController.currentFrameIndex),
        );
  }

  /// Whether [frameIndex] is READY to play at the current quality — the
  /// timeline ruler's green bar.
  bool isPlaybackFrameReady(int frameIndex) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return false;
    }
    return isPlaybackFrameReadyForCut(cut, frameIndex);
  }

  /// [isPlaybackFrameReady] for an arbitrary cut — the storyboard's green
  /// bar spans every cut of the track.
  ///
  /// TWO kinds of frame, one bar (유저 2026-08-16, 「왜 콘텐츠끝너머가
  /// 초록이되면 안되는거지? 재생가능한거잖아」):
  ///  * a frame with something to compose is green when its composite is
  ///    warmed — the bake IS its readiness;
  ///  * a frame that composes to NOTHING (a hole between blocks, the
  ///    runway past the drawings, hidden or faded-out layers) is not an
  ///    exception the bar skips — it is ready BY DEFINITION. Playback at
  ///    that frame draws exactly what its composite would hold: nothing.
  ///
  /// The empty answer reads the same shared visit the signature rides, so
  /// it cannot disagree with what the compose loop would actually paint.
  bool isPlaybackFrameReadyForCut(Cut cut, int frameIndex) {
    if (cutFrameCompositeCache.validCompositeOrNull(
          cut: cut,
          frameIndex: frameIndex,
          quality: playbackQuality,
        ) !=
        null) {
      return true;
    }
    return resolveCutFrameCompositeTree(
      cut: cut,
      frameIndex: frameIndex,
    ).isEmpty;
  }

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
      projectId: _repository.requireProject().id,
      trackId: selectedTrackId,
      cutId: cut.id,
      layerId: layer.id,
      frameId: frame.id,
    );
    // R19 P3b: the baked raster is the truth — the resolver is a plain
    // reference read (valid display cache first, else baked). No replay
    // exists anymore.
    return brushFrameStore.currentSurfaceWithoutReplay(
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
    _layerContentBoundsCached = bitmapSurfaceContentBounds(surface);
    return _layerContentBoundsCached;
  }

  BitmapSurface? _layerContentBoundsSurface;
  ({int left, int top, int rightExclusive, int bottomExclusive})?
  _layerContentBoundsCached;

  /// The resolved camera pose at the current playhead frame (keyframe,
  /// interpolation, or the default pose when the cut has no camera work).
  CameraPose get cameraPoseAtCurrentFrame => resolveCameraPoseAt(
    camera: requireActiveCut.camera,
    canvasSize: requireActiveCut.canvasSize,
    frameIndex: _timelineController.currentFrameIndex,
  );

  /// The camera pose the canvas should FRAME right now — not always the
  /// ACTIVE cut's (㊲).
  ///
  /// "Which cut am I editing" and "which cut is under the playhead" are two
  /// questions, and a live scrub makes them disagree ON PURPOSE: crossing a
  /// boundary parks per move and leaves the active cut alone, because
  /// switching it per move rebuilt every panel ([scrubGlobalFrame]). The
  /// camera frame read the active cut through that, so a T.U that ended
  /// zoomed kept framing the NEXT cut's pictures at the size the cut being
  /// left had finished on — and dragging the other way showed no camera
  /// work at all.
  ///
  /// Only a LIVE scrub asks the parked question: a committed parking means
  /// there is no cut here (a gap, or the V-row eye's hidden picture), and
  /// then there is nothing to frame. Null says exactly that.
  CameraPose? get displayedCameraPose {
    final parked = frameScrubActive.value ? _gapGlobalFrame : null;
    if (parked == null) {
      return activeCutOrNull == null ? null : cameraPoseAtCurrentFrame;
    }
    // 🚨[TrackFrameAxis.ownerOf] hands a gap frame to the PRECEDING cut on
    // purpose (its over-end runway) — it is an addressing rule, not a
    // containment test. [TrackFrameAxis.isGap] is the containment test, and
    // it is the same pair [selectGlobalFrame] asks, so what the drag frames
    // and what the release lands cannot disagree.
    final axis = trackFrameAxis();
    final owner = axis.isGap(parked) ? null : axis.ownerOf(parked);
    if (owner == null) {
      return null;
    }
    // The RENDER route's resolver (fx bypass honoured), because the picture
    // under this rectangle came through it too: preview and camera frame
    // must not disagree about the same cut.
    return cameraPoseForCut(owner.cut, parked - owner.startFrame);
  }

  bool get hasCameraKeyframeAtCurrentFrame =>
      activeCutOrNull?.camera.keyframeAt(
        _timelineController.currentFrameIndex,
      ) !=
      null;

  void setCameraKeyframeAtCurrentFrame(CameraPose pose) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.setCutCameraKeyframe(
      cutId: cutId,
      frameIndex: _timelineController.currentFrameIndex,
      pose: pose,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  void removeCameraKeyframeAtCurrentFrame() {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.removeCutCameraKeyframe(
      cutId: cutId,
      frameIndex: _timelineController.currentFrameIndex,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  void clearActiveCutCamera() {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.clearCutCamera(cutId: cutId);
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Replaces the active cut's camera track (one undo step) — the property
  /// lanes' per-property key edits route through here.
  void updateActiveCutCameraTrack(
    TransformTrack track, {
    String description = 'Edit camera keyframes',
  }) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    // "Same name, same value" INSIDE the camera's own track. A camera
    // belongs to its cut, so this naming space has no second use site to
    // reach — but two keys sharing a name on one lane still move together,
    // which is the whole link at its smallest.
    final before = cutById(cutId)?.camera.track;
    _cutCommandCoordinator.updateCutCamera(
      cutId: cutId,
      camera: CutCamera.fromTrack(
        before == null
            ? track
            : transformTrackWithNamedValues(
                track,
                transformNamedKeyChanges(before, track),
              ),
      ),
      description: description,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  // `setCutFade` and `updateTrackTransformTrack` retired with the V row's
  // transform. The cut fade is F.I / F.O spans on the TRANSITION row now
  // ([updateTransitionInstructions]) — where the span's length IS the ramp,
  // and where two cuts overlapping across a boundary can carry different
  // values, which one opacity lane per track never could.

  /// Replaces [layerId]'s transform track (the AE Transform lanes on every
  /// drawing layer — applied at composite time, never baked); one undo
  /// step, no-op when unchanged.
  void updateLayerTransformTrack(
    LayerId layerId,
    TransformTrack track, {
    String description = 'Edit layer transform',
  }) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.updateLayerTransformTrack(
      cutId: cutId,
      layerId: layerId,
      transformTrack: track,
      description: description,
    );
    notifyListeners();
  }

  /// Replaces [layerId]'s EFFECT CHAIN (R6 — the color/blur lanes); one
  /// undo step, no-op when unchanged.
  void updateLayerEffects(
    LayerId layerId,
    List<LayerEffect> effects, {
    String description = 'Edit layer effects',
  }) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.updateLayerEffects(
      cutId: cutId,
      layerId: layerId,
      effects: effects,
      description: description,
    );
    notifyListeners();
  }

  /// Whether the ACTIVE row can take an effect: a row that carries its own
  /// FX, and not a track-owned SE row (its display clone strips FX, so a
  /// chain committed through it would land nowhere the lanes could edit).
  bool get canAddEffectToActiveLayer {
    final layer = activeLayer;
    return layer != null &&
        layerKindHasLayerEffects(layer.kind) &&
        !isTrackSeLayerId(layer.id) &&
        // Attach rows wear their BASE's FX (W5) and have no lanes of their
        // own — the effect belongs on the base.
        layer.attachedToLayerId == null;
  }

  /// Appends a fresh effect of [kind] (every parameter at its default, so
  /// adding one changes nothing until a value moves) to the active row.
  void addEffectToActiveLayer(EffectKind kind) {
    final layer = activeLayer;
    if (layer == null || !canAddEffectToActiveLayer) {
      return;
    }
    _effectSequence += 1;
    final effect = LayerEffect.defaults(
      // Timestamped like the frame ids: the lane address embeds this, so
      // two effects added in the same session must never collide.
      id: EffectId(
        'fx-${layer.id.value}-'
        '${DateTime.now().microsecondsSinceEpoch}-$_effectSequence',
      ),
      kind: kind,
    );
    updateLayerEffects(layer.id, [
      ...layer.effects,
      effect,
    ], description: 'Add ${kind.label}');
  }

  /// Names (or un-names, with null) one effect-parameter KEY.
  ///
  /// A name is a link: every key called this, in this same parameter, holds
  /// one value — the frame-name rule said of keyframes (user 2026-07-30).
  /// Because linked rows share effect ids, that naming space reaches the
  /// 겸용 siblings whose chains otherwise only share their shape.
  ///
  /// Returns true when [name] is ALREADY taken in that space and NOTHING
  /// was written, so the caller can offer to join instead (see
  /// [linkEffectKeyName]) — the same report [renameSelectedFrame] makes
  /// about a colliding frame name. False means the rename applied, or could
  /// not.
  ///
  /// The collision is reported as a FACT rather than as the value behind
  /// it: a transform lane's value is a point, not a number, and a link
  /// whose two halves disagree about what they carry would be two links.
  bool setEffectKeyName({
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
    required String? name,
  }) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return false;
    }
    final site = _effectKeySite(
      cutId: cutId,
      layerId: layerId,
      effectId: effectId,
      parameterId: parameterId,
      frameIndex: frameIndex,
    );
    if (site == null || site.key.name == name) {
      return false;
    }
    if (name != null &&
        _cutCommandCoordinator.namedEffectKeyValueInSpace(
              cutId: cutId,
              layerId: layerId,
              effectId: effectId,
              parameterId: parameterId,
              name: name,
            ) !=
            null) {
      return true;
    }
    _writeEffectKeyName(
      cutId: cutId,
      layerId: layerId,
      effectId: effectId,
      parameterId: parameterId,
      frameIndex: frameIndex,
      name: name,
    );
    return false;
  }

  /// Joins [name], ADOPTING the value that name already holds — the answer
  /// to the "합칠까요?" [setEffectKeyName] raises.
  ///
  /// The key takes the number rather than imposing its own, exactly as
  /// [linkSelectedFrame] takes the drawing that is already there (user
  /// 2026-08-10). A name that turns out to be free just applies, so a stale
  /// confirmation cannot blank the value.
  void linkEffectKeyName({
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
    required String name,
  }) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _writeEffectKeyName(
      cutId: cutId,
      layerId: layerId,
      effectId: effectId,
      parameterId: parameterId,
      frameIndex: frameIndex,
      name: name,
      adopted: _cutCommandCoordinator.namedEffectKeyValueInSpace(
        cutId: cutId,
        layerId: layerId,
        effectId: effectId,
        parameterId: parameterId,
        name: name,
      ),
    );
  }

  /// Names (or un-names, with null) one TRANSFORM lane KEY — the twin of
  /// [setEffectKeyName], under the same contract: true means [name] was
  /// ALREADY taken in that lane's naming space and NOTHING was written, so
  /// the caller can offer to join instead (see [linkTransformKeyName]).
  ///
  /// The naming space is (link group, property). A transform carries no
  /// shared id the way an effect chain does — 겸용 siblings are different
  /// [LayerId]s holding the same part — so the group stands in for the
  /// effect id, and Rotation's "A" still cannot collide with Position's.
  bool setTransformKeyName({
    required LayerId layerId,
    required TransformPropertyId property,
    required int frameIndex,
    required String? name,
  }) {
    final cutId = _editingSession.activeCutId;
    final layer = _layerById(layerId);
    if (cutId == null || layer == null) {
      return false;
    }
    final track = layer.transformTrack;
    if (!transformLaneHasKeyAt(track, property, frameIndex) ||
        transformLaneKeyName(track, property, frameIndex) == name) {
      return false;
    }
    if (name != null &&
        _cutCommandCoordinator.transformTrackHoldingName(
              cutId: cutId,
              layerId: layerId,
              property: property,
              name: name,
            ) !=
            null) {
      return true;
    }
    updateLayerTransformTrack(
      layerId,
      transformTrackWithKeyName(track, property, frameIndex, name),
      description: name == null ? 'Unname key' : 'Name key',
    );
    return false;
  }

  /// Joins [name] on a transform lane, ADOPTING the value that name already
  /// holds — the answer to the "합칠까요?" [setTransformKeyName] raises, and
  /// the same pull [linkEffectKeyName] does.
  void linkTransformKeyName({
    required LayerId layerId,
    required TransformPropertyId property,
    required int frameIndex,
    required String name,
  }) {
    final cutId = _editingSession.activeCutId;
    final layer = _layerById(layerId);
    if (cutId == null || layer == null) {
      return;
    }
    final holder = _cutCommandCoordinator.transformTrackHoldingName(
      cutId: cutId,
      layerId: layerId,
      property: property,
      name: name,
    );
    var next = layer.transformTrack;
    if (holder != null) {
      // Adopt BEFORE naming: the value arrives on a still-unnamed key, so
      // the write that follows carries a rename and nothing else — which
      // is what keeps the joining key from imposing its own number.
      next = transformTrackAdoptingName(
        next,
        holder,
        property,
        frameIndex,
        name,
      );
    }
    updateLayerTransformTrack(
      layerId,
      transformTrackWithKeyName(next, property, frameIndex, name),
      description: 'Name key',
    );
  }

  // The single-key lane naming verbs (`laneKeyName`, `laneHasKeyAt`,
  // `currentLaneKeyAddress`, `setLaneKeyName`, `linkLaneKeyName`) retired
  // when the RANGE form arrived: a single key is the one-frame span at the
  // playhead, so `setLaneKeyNamesForSelection` covers both and leaving the
  // narrow pair here would only invite a future fix to land on the copy
  // nothing calls. The per-FAMILY verbs below (`setEffectKeyName`,
  // `setTransformKeyName`) stay — the range walk builds on them.

  /// The transform track that ALREADY holds [name] in this lane's naming
  /// space, or null when the name is free there.
  ///
  /// A LAYER row's space spans its 겸용 link group. A camera row's and a V
  /// row's do not: a camera track belongs to its cut and a V track is held
  /// once, so there is no second use site for a name to reach.
  /// [excludeFrames] are the keys a RANGE rename is about to name: they are
  /// the ones joining, so they must not be found as the holder.
  TransformTrack? _laneTransformHoldingName(
    Layer layer,
    TransformPropertyId property,
    String name, {
    Set<int> excludeFrames = const {},
  }) {
    final track = _laneTransformTrackOf(layer);
    if (transformLaneUsesName(
      track,
      property,
      name,
      excludeFrames: excludeFrames,
    )) {
      return track;
    }
    final cutId = _editingSession.activeCutId;
    if (cutId == null ||
        layer.kind == LayerKind.camera ||
        trackIdOfTransformLaneCarrier(layer.id) != null) {
      return null;
    }
    return _cutCommandCoordinator.transformTrackHoldingName(
      cutId: cutId,
      layerId: layer.id,
      property: property,
      name: name,
      excludeFramesOnSource: excludeFrames,
    );
  }

  /// The one effect-parameter key a naming verb addresses, with what its
  /// write needs — null when any link of that chain is missing.
  ({
    Layer layer,
    LayerEffect effect,
    int effectIndex,
    EffectParameter parameter,
    PropertyKey<double> key,
  })?
  _effectKeySite({
    required CutId cutId,
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
  }) {
    final layers = cutById(cutId)?.layers ?? const <Layer>[];
    final layerIndex = layers.indexWhere((row) => row.id == layerId);
    if (layerIndex == -1) {
      return null;
    }
    final layer = layers[layerIndex];
    final effectIndex = layer.effects.indexWhere(
      (effect) => effect.id == effectId,
    );
    if (effectIndex == -1) {
      return null;
    }
    final effect = layer.effects[effectIndex];
    final parameter = effect.parameters[parameterId];
    final key = parameter?.track.keyAt(frameIndex);
    if (parameter == null || key == null) {
      return null;
    }
    return (
      layer: layer,
      effect: effect,
      effectIndex: effectIndex,
      parameter: parameter,
      key: key,
    );
  }

  /// Writes one key's [name] — and, when [adopted] is given, the value that
  /// name brings with it — as ONE undo step. The key's interpolation is
  /// carried across explicitly: adopting a value must not silently restyle
  /// the segment leaving the key.
  void _writeEffectKeyName({
    required CutId cutId,
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
    required String? name,
    double? adopted,
  }) {
    final site = _effectKeySite(
      cutId: cutId,
      layerId: layerId,
      effectId: effectId,
      parameterId: parameterId,
      frameIndex: frameIndex,
    );
    if (site == null) {
      return;
    }
    var track = site.parameter.track;
    if (adopted != null && adopted != site.key.value) {
      track = track.withKey(
        frameIndex,
        adopted,
        interpolation: site.key.interpolation,
      );
    }
    track = track.withKeyName(frameIndex, name);
    final next = [...site.layer.effects]
      ..[site.effectIndex] = site.effect.withParameter(
        parameterId,
        EffectParameter(value: site.parameter.value, track: track),
      );
    updateLayerEffects(
      layerId,
      next,
      description: name == null ? 'Unname key' : 'Name key',
    );
  }

  /// Removes one effect from the active row (its keys go with it; one undo
  /// brings both back).
  void removeEffectFromActiveLayer(EffectId effectId) {
    final layer = activeLayer;
    if (layer == null) {
      return;
    }
    final next = [
      for (final effect in layer.effects)
        if (effect.id != effectId) effect,
    ];
    if (next.length == layer.effects.length) {
      return;
    }
    updateLayerEffects(layer.id, next, description: 'Remove effect');
  }

  int _effectSequence = 0;

  /// An effect parameter's resolved value at [frameIndex] — the lane value
  /// column and the key-freeze source, read through the SAME resolver the
  /// composite uses so the number in the lane is the number on the canvas.
  double layerEffectParameterAtFrame(
    Layer layer,
    EffectId effectId,
    String parameterId,
    int frameIndex,
  ) {
    for (final effect in layer.effects) {
      if (effect.id == effectId) {
        return effect.parameterOf(parameterId).resolveAt(frameIndex);
      }
    }
    return 0;
  }

  /// The layer's resolved transform pose at [frameIndex] (identity while
  /// the track is empty) — the lane value column and key-freeze source.
  TransformPose layerPoseAtFrame(Layer layer, int frameIndex) {
    return layer.transformTrack.resolveAt(
      frameIndex: frameIndex,
      orElse: () => layerIdentityPose(requireActiveCut.canvasSize),
    );
  }

  /// The layer's resolved anchor point at [frameIndex] — the anchor-point
  /// lane's value column and key-freeze source (canvas center while
  /// unkeyed).
  CanvasPoint layerAnchorPointAtFrame(Layer layer, int frameIndex) {
    return resolveLayerAnchorPointAt(layer: layer, frameIndex: frameIndex) ??
        CanvasPoint(
          x: requireActiveCut.canvasSize.width / 2,
          y: requireActiveCut.canvasSize.height / 2,
        );
  }

  /// The layer's animated Opacity sample (0..1; 1 while unkeyed) — the
  /// opacity lane's value column and key-freeze source.
  double layerOpacityAtFrame(Layer layer, int frameIndex) {
    return resolveOpacityTrackAt(layer.transformTrack.opacity, frameIndex);
  }

  // --- Layer FX switches (PERSISTED layer state, R8) -----------------------

  /// The row's FX state: its TRANSFORM switch ([Layer.transformEnabled])
  /// plus every effect's own switch, read as one answer for the layer-label
  /// button — AE's fx column, and a MASTER over the per-group switches
  /// (user, 2026-07-30: "통합토글버튼").
  ///
  /// [LayerFxState.mixed] is what makes it a master rather than a second
  /// independent bypass: some groups on, some off, and tapping resolves the
  /// whole row one way.
  LayerFxState layerFxState(LayerId layerId) {
    final layer = _fxSwitchLayerById(layerId);
    if (layer == null) {
      return LayerFxState.on;
    }
    final switches = <bool>[
      if (layerKindHasTransformFxSwitch(layer.kind)) layer.transformEnabled,
      for (final effect in layer.effects) effect.enabled,
    ];
    if (switches.isEmpty) {
      return LayerFxState.on; // An adjustment row with no effects yet.
    }
    if (switches.every((enabled) => enabled)) {
      return LayerFxState.on;
    }
    if (switches.every((enabled) => !enabled)) {
      return LayerFxState.off;
    }
    return LayerFxState.mixed;
  }

  /// Whether ANY of the row's FX apply — the row-level facet question the
  /// timeline filter asks ("show me the rows that are doing something").
  bool isLayerFxEnabled(LayerId layerId) =>
      layerFxState(layerId) != LayerFxState.off;

  /// Whether the row's TRANSFORM applies. Every reader of a transform
  /// PROPERTY (pose, animated opacity, the position gizmo) asks this and
  /// not [isLayerFxEnabled]: since R8 split the switches per group, a row
  /// can have its transform bypassed while a colour effect still runs —
  /// the master's [LayerFxState.mixed] answer cannot decide the pose.
  bool isLayerTransformFxEnabled(LayerId layerId) =>
      _fxSwitchLayerById(layerId)?.transformEnabled ?? true;

  /// The MASTER toggle: off unless the row is already fully off, in which
  /// case it turns everything back on. ONE undo step for the whole row.
  void toggleLayerFx(LayerId layerId) {
    final layer = _fxSwitchLayerById(layerId);
    if (layer == null) {
      return;
    }
    final turnOn = layerFxState(layerId) == LayerFxState.off;
    _setLayerFxSwitches([layer], enabled: turnOn);
  }

  /// The TRANSFORM group header's own switch (R8).
  void toggleLayerTransformFx(LayerId layerId) {
    final layer = _fxSwitchLayerById(layerId);
    if (layer == null) {
      return;
    }
    updateLayerTransformEnabled(
      layerId,
      enabled: !layer.transformEnabled,
      description: layer.transformEnabled
          ? 'Bypass transform'
          : 'Apply transform',
    );
  }

  /// The row a switch edit addresses: a cut layer, or a track-owned SE row
  /// (whose display clone is not the thing to write).
  Layer? _fxSwitchLayerById(LayerId layerId) =>
      _layerById(layerId) ?? trackSeGlobalLayerById(layerId);

  /// Writes every FX switch of [targets] to [enabled] as ONE undo step.
  void _setLayerFxSwitches(List<Layer> targets, {required bool enabled}) {
    final commands = <Command>[];
    for (final layer in targets) {
      // The camera row is IN: it carries no effects, but its own switch —
      // the one that bypasses the cut camera's work — is this flag.
      if (layerKindHasTransformFxSwitch(layer.kind) &&
          layer.transformEnabled != enabled) {
        commands.add(
          UpdateLayerTransformEnabledCommand(
            repository: _repository,
            layerId: layer.id,
            transformEnabled: enabled,
          ),
        );
      }
      if (layer.effects.isEmpty) {
        continue;
      }
      // Through the COORDINATOR, not a hand-built command: it owns the
      // 겸용컷 effect mirror, and a master that built its own would write
      // one cut of a link group and leave its twin permanently `mixed`.
      final cutId = cutIdOfLayer(_repository.requireProject(), layer.id);
      if (cutId == null) {
        continue; // A row no cut holds (a track-SE clone) has no chain here.
      }
      commands.addAll(
        _cutCommandCoordinator.layerEffectsCommands(
          cutId: cutId,
          layerId: layer.id,
          effects: [
            for (final effect in layer.effects)
              effect.copyWith(enabled: enabled),
          ],
          description: enabled ? 'Apply layer FX' : 'Bypass layer FX',
        ),
      );
    }
    if (commands.isEmpty) {
      return;
    }
    _historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: enabled ? 'Apply layer FX' : 'Bypass layer FX',
              commands: commands,
            ),
    );
    // A bare notify, like every sibling row write (opacity, blend, the
    // transform track, the effect chain): a switch flip is not a structural
    // cut edit, and refreshing as one threw away the frame-range selection
    // the user keeps while A/B-ing the switch.
    notifyListeners();
  }

  /// Writes one row's TRANSFORM switch; one undo step, no-op when unchanged.
  void updateLayerTransformEnabled(
    LayerId layerId, {
    required bool enabled,
    String description = 'Toggle transform FX',
  }) {
    final layer = _fxSwitchLayerById(layerId);
    if (layer == null || layer.transformEnabled == enabled) {
      return;
    }
    _historyManager.execute(
      UpdateLayerTransformEnabledCommand(
        repository: _repository,
        layerId: layerId,
        transformEnabled: enabled,
        description: description,
      ),
    );
    notifyListeners(); // Not a structural cut edit — see [_setLayerFxSwitches].
  }

  // --- Visibility solo mode (session view state, not persisted) ------------

  /// The legend eye's SOLO MODE (R4 #7 rework — REAL eye flips, user rule):
  /// engaging it snapshots every row's eye (cut layers + track SE), turns
  /// every non-active eye OFF and the active one ON — the rows show it and
  /// playback/fill follow naturally, exactly like clicking the eyes by
  /// hand (view-ish controller writes, not undoable). Switching the active
  /// layer re-solos; disengaging restores each eye from the snapshot.
  /// Leaving the cut exits the mode (restoring first) — the snapshot is
  /// cut-scoped.
  bool _layerVisibilitySoloEnabled = false;
  Map<LayerId, bool>? _visibilitySoloSnapshot;
  CutId? _visibilitySoloCutId;

  bool get layerVisibilitySoloEnabled => _layerVisibilitySoloEnabled;

  void toggleLayerVisibilitySolo() {
    if (_layerVisibilitySoloEnabled) {
      _exitVisibilitySolo();
    } else {
      _layerVisibilitySoloEnabled = true;
      _visibilitySoloCutId = _editingSession.activeCutId;
      _visibilitySoloSnapshot = {
        for (final layer in layers) layer.id: layer.isVisible,
      };
      _applyVisibilitySolo();
    }
    notifyListeners();
  }

  /// Re-solos to the CURRENT active layer. Rows born during the solo join
  /// the snapshot with their pre-flip eye so exiting restores them too.
  void _applyVisibilitySolo() {
    final activeId = activeLayerId;
    if (activeId == null) {
      return;
    }
    final stack = layers;
    // 🚨THE ANCESTORS STAY ON. Solo means "show this row alone", and a row
    // inside a folder is not shown by its own eye — turning every OTHER row
    // off turned its folders off with them, so soloing a row inside a folder
    // hid the very thing it was soloing. On the editing canvas that read as
    // "nothing happened"; in playback and export the frame came out EMPTY.
    final keepShown = <LayerId>{
      activeId,
      for (final folder in stack.ancestryOf(
        stack.where((layer) => layer.id == activeId).firstOrNull?.folderId,
      ))
        folder.id,
    };
    for (final layer in stack) {
      _visibilitySoloSnapshot?.putIfAbsent(layer.id, () => layer.isVisible);
      final shouldShow = keepShown.contains(layer.id);
      if (layer.isVisible != shouldShow) {
        _layerController.toggleLayerVisibility(layer.id);
      }
    }
  }

  void _exitVisibilitySolo() {
    _layerVisibilitySoloEnabled = false;
    _visibilitySoloCutId = null;
    final snapshot = _visibilitySoloSnapshot;
    _visibilitySoloSnapshot = null;
    if (snapshot == null) {
      return;
    }
    // Restore through the repository's anywhere seam — rows deleted during
    // the solo have nothing to restore (skip).
    snapshot.forEach((layerId, visible) {
      try {
        _repository.updateLayer(
          layerId: layerId,
          update: (layer) => layer.isVisible == visible
              ? layer
              : layer.copyWith(isVisible: visible),
        );
      } on StateError {
        // Layer gone.
      }
    });
  }

  /// Keeps the solo mode consistent after active-layer/cut changes: same
  /// cut → re-solo to the new active row; different cut → exit (restore).
  void _syncVisibilitySolo() {
    if (!_layerVisibilitySoloEnabled) {
      return;
    }
    if (_editingSession.activeCutId != _visibilitySoloCutId) {
      _exitVisibilitySolo();
    } else {
      _applyVisibilitySolo();
    }
  }

  // --- Cut display gates ---------------------------------------------------

  /// Whether the cut's fx (the V track's Transform group — the pose AND
  /// the fade, "opacity joins the transform system") apply at DISPLAY
  /// time. R9 #21: the owning TRACK's persisted master is folded in HERE
  /// rather than at each reader — the playback canvas, the multitrack
  /// stack and the editing preview all ask this one question, so the
  /// track switch reaches all three by arriving at the choke point
  /// instead of being threaded to them.
  ///
  /// R10 R3: the per-CUT bypass that used to sit in front of this line is
  /// gone. It was reachable only through a context menu, it never left the
  /// session, and while editing shows one cut at a time it said exactly
  /// what the track switch already says.
  bool isCutFxEnabled(CutId cutId) => trackOwningCut(cutId)?.fxEnabled ?? true;

  // --- V track display: the static opacity and the fx master (R9 #21) ----

  /// The V row's fx switch: OFF while the track's flag is down, ON
  /// otherwise. It stays a [LayerFxState] because the button it drives is
  /// the shared one.
  ///
  /// Still never MIXED, now that the row carries an effect chain as well:
  /// unlike a layer's, this master is STORED state rather than a reading of
  /// the switches beneath it, so it reports what it is. A bypassed effect
  /// says so on its own lane header, where the eye already looks.
  LayerFxState trackFxState(TrackId trackId) {
    final track = _trackById(trackId);
    if (track == null) {
      return LayerFxState.on;
    }
    return track.fxEnabled ? LayerFxState.on : LayerFxState.off;
  }

  // --- The V row's EFFECT CHAIN (fx on the cut, not on one layer) --------
  //
  // A layer's chain filters that layer's picture; this one filters the whole
  // composited cut under the playhead (user 2026-08-08). It is TRACK data on
  // the GLOBAL axis, exactly like the pose and the fade beside it, so these
  // verbs take a TrackId and no cut is ever in the loop.

  /// Replaces [trackId]'s effect chain; one undo step.
  void updateTrackEffects(
    TrackId trackId,
    List<LayerEffect> effects, {
    String description = 'Edit track effects',
  }) {
    _cutCommandCoordinator.updateTrackEffects(
      trackId: trackId,
      effects: effects,
      description: description,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Adds an effect to the V row's chain. Ids are minted the way a layer's
  /// are (the lane address embeds them, so two adds in one session must not
  /// collide) — off the TRACK id, since that is what carries the chain.
  void addEffectToTrack(TrackId trackId, EffectKind kind) {
    final track = _trackById(trackId);
    if (track == null) {
      return;
    }
    _effectSequence += 1;
    updateTrackEffects(
      trackId,
      [
        ...track.effects,
        LayerEffect.defaults(
          id: EffectId(
            'fx-${trackId.value}-'
            '${DateTime.now().microsecondsSinceEpoch}-$_effectSequence',
          ),
          kind: kind,
        ),
      ],
      description: 'Add ${kind.label}',
    );
  }

  void removeEffectFromTrack(TrackId trackId, EffectId effectId) {
    final track = _trackById(trackId);
    if (track == null) {
      return;
    }
    final next = [
      for (final effect in track.effects)
        if (effect.id != effectId) effect,
    ];
    if (next.length == track.effects.length) {
      return;
    }
    updateTrackEffects(trackId, next, description: 'Remove effect');
  }

  /// A V-track effect group's RESET (R5) — the track twin of
  /// [resetLaneGroup]. Track effects have no lane-range selection of their
  /// own, so the scope is always the playhead.
  bool resetTrackEffectGroup(TrackId trackId, String headerLaneId) {
    final track = _trackById(trackId);
    if (track == null) {
      return false;
    }
    final next = effectsWithGroupReset(
      track.effects,
      laneId: headerLaneId,
      frameIndexes: [_timelineController.currentFrameIndex],
    );
    if (next == null) {
      return false;
    }
    updateTrackEffects(trackId, next, description: 'Reset group');
    return true;
  }

  /// One effect's own bypass on the V row — the switch on its group header,
  /// the twin of a layer effect's.
  void toggleTrackEffectEnabled(TrackId trackId, EffectId effectId) {
    final track = _trackById(trackId);
    if (track == null) {
      return;
    }
    final next = effectsWithEnabledToggled(track.effects, effectId);
    if (next == null) {
      return;
    }
    updateTrackEffects(trackId, next, description: 'Toggle effect');
  }

  /// A track effect parameter's resolved value at GLOBAL [frameIndex] — the
  /// lane value column and the key-freeze source, through the same resolver
  /// the composite samples with.
  double trackEffectParameterAtFrame(
    Track track,
    EffectId effectId,
    String parameterId,
    int frameIndex,
  ) {
    for (final effect in track.effects) {
      if (effect.id == effectId) {
        return effect.parameterOf(parameterId).resolveAt(frameIndex);
      }
    }
    return 0;
  }

  /// The V row's fx toggle, one undoable write.
  void toggleTrackFx(TrackId trackId) {
    final track = _trackById(trackId);
    if (track == null) {
      return;
    }
    final turnOn = !track.fxEnabled;
    _cutCommandCoordinator.updateTrackDisplay(
      trackId: trackId,
      fxEnabled: turnOn,
      description: turnOn ? 'Apply track FX' : 'Bypass track FX',
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// The live V-row opacity drag (session-owned, per the drag-verb rule):
  /// per-move preview, ONE write on release.
  final ValueNotifier<({TrackId trackId, double opacity})?>
  trackOpacityDragPreview = ValueNotifier(null);

  /// The track's static opacity as everything should READ it — the live
  /// drag value while one is in flight, the stored value otherwise. The
  /// composite surfaces call the [forCut] form.
  double trackStaticOpacity(TrackId trackId) {
    final dragging = trackOpacityDragPreview.value;
    if (dragging != null && dragging.trackId == trackId) {
      return dragging.opacity;
    }
    return _trackById(trackId)?.opacity ?? 1.0;
  }

  double trackStaticOpacityForCut(CutId cutId) {
    final owner = trackOwningCut(cutId);
    return owner == null ? 1.0 : trackStaticOpacity(owner.id);
  }

  void previewTrackOpacity(TrackId trackId, double opacity) {
    trackOpacityDragPreview.value = (
      trackId: trackId,
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  void commitTrackOpacity(TrackId trackId, double opacity) {
    trackOpacityDragPreview.value = null;
    _cutCommandCoordinator.updateTrackDisplay(
      trackId: trackId,
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
      description: 'Track opacity',
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

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
      if (cutId == _editingSession.activeCutId) {
        _gapGlobalFrame = editingGlobalFrame;
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
    final parked = _gapGlobalFrame;
    if (parked != null &&
        _editingSession.activeCutId == null &&
        trackFrameAxis().ownerOf(parked)?.cutId == cutId) {
      selectGlobalFrame(parked);
      return; // selectGlobalFrame notifies.
    }
    notifyListeners();
  }

  void undo() {
    final beforeLayers = List<Layer>.of(
      activeCutOrNull?.layers ?? const <Layer>[],
    );
    final previousActiveLayerId = _layerController.activeLayerId;
    final previousFrameIndex = _timelineController.currentFrameIndex;

    _historyManager.undo();
    final preferredLayerId = _preferredLayerAfterLayerListChange(
      beforeLayers: beforeLayers,
      afterLayers: activeCutOrNull?.layers ?? const <Layer>[],
      previousActiveLayerId: previousActiveLayerId,
    );
    _refreshAfterCutCommand(
      preferredActiveLayerId: preferredLayerId,
      preferredFrameIndex: previousFrameIndex,
    );
    notifyListeners();
  }

  void redo() {
    final beforeLayers = List<Layer>.of(
      activeCutOrNull?.layers ?? const <Layer>[],
    );
    final previousActiveLayerId = _layerController.activeLayerId;
    final previousFrameIndex = _timelineController.currentFrameIndex;

    _historyManager.redo();
    final preferredLayerId = _preferredLayerAfterLayerListChange(
      beforeLayers: beforeLayers,
      afterLayers: activeCutOrNull?.layers ?? const <Layer>[],
      previousActiveLayerId: previousActiveLayerId,
    );
    _refreshAfterCutCommand(
      preferredActiveLayerId: preferredLayerId,
      preferredFrameIndex: previousFrameIndex,
    );
    notifyListeners();
  }

  /// The row each cut was last worked on, replayed on the way back in
  /// (user request 2026-07-26). SESSION view state on purpose: hanging it
  /// on the Cut would make picking a layer a document edit — an undo entry
  /// and a dirty file per click.
  final Map<CutId, LayerId> _lastLayerByCut = <CutId, LayerId>{};

  /// Records the layer a cut is being LEFT on — one funnel instead of a
  /// hook on every path that can move the active layer. Stale ids need no
  /// cleanup: [_activeCutHasLayer] already drops a layer the cut no longer
  /// has, and the rebuild falls back to the top row.
  ///
  /// SE rows are recorded like any other: what the timeline shows for them
  /// is a cut-local PROJECTION of the track layer, so "the row this cut was
  /// left on" can name one, and the id is the same in every cut — a cut
  /// left on S1 comes back on S1 for free.
  void _rememberActiveLayerForCut() {
    final cutId = _editingSession.activeCutId;
    final layerId = activeLayerId;
    if (cutId != null && layerId != null) {
      _lastLayerByCut[cutId] = layerId;
    }
  }

  void selectCut(CutId cutId) {
    if (cutId == _editingSession.activeCutId) {
      return;
    }
    // R15-⑤: never switch cuts under a live editing interaction.
    if (editingInteractionBusy) {
      return;
    }
    _rememberActiveLayerForCut();
    final nextActiveLayerId = _lastLayerByCut[cutId];

    final fromGap =
        _gapGlobalFrame != null || _editingSession.activeCutId == null;
    // The visibility solo is cut-scoped: restore the eyes before leaving.
    if (_layerVisibilitySoloEnabled) {
      _exitVisibilitySolo();
    }
    _editingSession.setActiveCutId(cutId);
    // Keep the pair reconciled at the seam instead of only at read time:
    // selecting a cut selects its track, so the stored selection is right
    // the moment the cut is dropped (a gap park) rather than falling back.
    _editingSession.setSelectedTrackId(
      trackIdOfCut(_repository.requireProject(), cutId) ??
          _editingSession.selectedTrackId,
    );
    _copiedFrame = null;
    clearFrameRangeSelection();
    // The cut comes back on the row it was left on; never visited (or the
    // layer is gone — the rebuild's own guard) falls back to the top row.
    _rebuildActiveCutControllers(preferredActiveLayerId: nextActiveLayerId);
    if (fromGap) {
      // Activating a cut FROM the gap lands on ITS first frame (UI-R10
      // #14): the stale gap-global cursor never leaks into the new cut
      // (selectFrameIndex also clears the parking).
      selectFrameIndex(0);
    }
    // Yield the warm window first, exactly as a frame seek does. A cut
    // switch used to warm immediately, which was fine while switching was
    // a click — but the V row's flip switches cuts once per press, so a
    // run of them queued a full-canvas warm per step and the run stuttered
    // on work it was about to invalidate anyway.
    prerenderScheduler.notifyEditActivity();
    _warmActiveCut();
    notifyListeners();
  }

  // --- Layer state / commands --------------------------------------------

  List<Layer> get layers => _layerController.layers;
  LayerId? get activeLayerId => _layerController.activeLayerId;
  Layer? get activeLayer => _layerController.activeLayer;

  BrushEditorSelection? get activeBrushEditorSelection {
    final activeLayer = this.activeLayer;
    final selectedFrame = this.selectedFrame;
    if (activeLayer == null || selectedFrame == null) {
      return null;
    }
    // Ghost repeat instances resolve to their ANCHOR cel deliberately
    // (UI-R19b, user decision): drawing with the playhead on a ghost
    // edits the source cel — the light-table workflow. Delete alone
    // stays refused on ghosts.
    // R6-④: SE/instruction cels are data rows — no editable brush target,
    // so the canvas never accepts strokes on them (the drawn stack still
    // composites them read-only). A media-REFERENCE layer (§6-z23) shows
    // a library asset: no strokes until it is rasterized.
    if (!layerAcceptsBrushInput(activeLayer)) {
      return null;
    }
    // R4 #1: a hidden layer takes no strokes either — you would be drawing
    // into something the canvas doesn't show. Flip the eye back on (or use
    // the solo mode) to draw.
    //
    // 🚨AND THE FOLDER'S EYE COUNTS (유저 2026-08-13: 「숨긴 폴더는 안에
    // 있는 레이어들도 숨김상태인거일거잖아. 그러면 브러시 막는거지」). The
    // reason R4 #1 gives — you would be drawing into something the canvas
    // doesn't show — is the SAME reason one folder up, and asking only the
    // row's own eye is how a stroke went on landing in a folder the user had
    // switched off.
    if (!layers.rowVisible(activeLayer)) {
      return null;
    }

    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return null; // Gap state: no cut, no brush target.
    }
    return BrushEditorSelection(
      projectId: _repository.requireProject().id,
      trackId: selectedTrackId,
      cutId: cutId,
      layerId: activeLayer.id,
      frameId: selectedFrame.id,
    );
  }

  bool get canDeleteActiveLayer {
    final activeLayer = this.activeLayer;
    return activeLayer != null && canDeleteLayer(activeLayer);
  }

  /// Whether [activeLayer] may be deleted at all — the FLOORS, asked of any
  /// row rather than only of the active one (⑨ needs it per selected row).
  ///
  /// The parameter keeps its name so the body below reads unchanged: this
  /// was [canDeleteActiveLayer]'s own text, lifted so two askers cannot
  /// drift apart ([[predicates-before-new-kind]]).
  bool canDeleteLayer(Layer activeLayer) {
    // Read-only where a cut can see it: the transition row is deleted (and
    // moved) on the global axis, never from inside a cut.
    if (layerKindIsReadOnlyInCut(activeLayer.kind)) {
      return false;
    }
    // Attach rows are accessories: always deletable, never counted toward
    // the drawing floor (deleting a BASE cascades over its attach rows).
    if (isAttachedLayer(activeLayer)) {
      return true;
    }
    final cut = activeCutOrNull;
    if (cut == null) {
      return false;
    }
    final layers = cut.layers;
    return switch (activeLayer.kind) {
      LayerKind.camera => false,
      // The TRANSITION row is a track fixture like the camera: exactly one,
      // never deleted from inside a cut.
      LayerKind.transition => false,
      // The sheet's fixture floors: at least two SE rows (S1·S2, now
      // track-owned) and one instruction row survive.
      LayerKind.se => activeTrack.seLayers.length > 2,
      LayerKind.instruction =>
        layers.where((layer) => layer.kind == LayerKind.instruction).length > 1,
      // R28 #14: NO drawing floor. The action section may stand empty —
      // the last action layer is deletable ("액션 레이어가 1개도 없는상황
      // 허용"). The global track is the thing that has to exist, not any
      // particular row inside a cut, and every drawing path already
      // handles "no editable cel" (that is the R26 #35 refusal notice).
      // A folder row deletes by DISSOLVING (the coordinator routes it) —
      // its members are rows of their own and survive.
      // An ADJUSTMENT row has no floor either: deleting it just stops the
      // stack below being filtered.
      LayerKind.animation ||
      LayerKind.storyboard ||
      LayerKind.image ||
      LayerKind.text ||
      LayerKind.folder ||
      LayerKind.adjustment => true,
    };
  }

  /// Whether the canvas is in camera manipulation mode.
  bool get isCameraLayerActive => activeLayer?.kind == LayerKind.camera;

  /// What the canvas shows while the camera layer is active: the first
  /// visible drawing layer with a frame at the playhead, so there is artwork
  /// to frame. `null` when the cut has nothing drawn at this frame.
  BrushEditorSelection? get cameraBackdropSelection {
    final cut = activeCutOrNull;
    if (cut == null) {
      return null;
    }
    final frameIndex = _timelineController.currentFrameIndex;
    for (final layer in cut.layers) {
      if (!layerKindPaintsArtwork(layer.kind) || !layer.isVisible) {
        continue;
      }
      final frame = _timelineController.resolveFrameForLayer(
        layer: layer,
        frameIndex: frameIndex,
      );
      if (frame == null) {
        continue;
      }
      return BrushEditorSelection(
        projectId: _repository.requireProject().id,
        trackId: selectedTrackId,
        cutId: cut.id,
        layerId: layer.id,
        frameId: frame.id,
      );
    }
    return null;
  }

  LayerId? _stableLayerIdAfterDeleting({
    required List<Layer> beforeLayers,
    required LayerId deletedLayerId,
  }) {
    final deletedIndex = beforeLayers.indexWhere(
      (layer) => layer.id == deletedLayerId,
    );
    if (deletedIndex == -1) {
      return null;
    }

    final remainingLayers = beforeLayers
        .where((layer) => layer.id != deletedLayerId)
        .toList(growable: false);
    if (remainingLayers.isEmpty) {
      return null;
    }
    if (deletedIndex < remainingLayers.length) {
      return remainingLayers[deletedIndex].id;
    }
    return remainingLayers[deletedIndex - 1].id;
  }

  LayerId? _preferredLayerAfterLayerListChange({
    required List<Layer> beforeLayers,
    required List<Layer> afterLayers,
    required LayerId? previousActiveLayerId,
  }) {
    final afterIds = afterLayers.map((layer) => layer.id).toSet();
    final beforeIds = beforeLayers.map((layer) => layer.id).toSet();
    final insertedLayers = afterLayers
        .where((layer) => !beforeIds.contains(layer.id))
        .toList(growable: false);
    if (insertedLayers.isNotEmpty) {
      return insertedLayers.first.id;
    }

    if (previousActiveLayerId != null &&
        !afterIds.contains(previousActiveLayerId)) {
      return _stableLayerIdAfterDeleting(
        beforeLayers: beforeLayers,
        deletedLayerId: previousActiveLayerId,
      );
    }

    return previousActiveLayerId;
  }

  String? get layerClipboardName => _layerClipboard?.name;
  bool get hasLayerClipboard => _layerClipboard != null;

  void copyActiveLayer() {
    final activeLayer = this.activeLayer;
    // SE rows are track-owned (global frame axis) — copying a cut-local
    // window onto the cut-layer clipboard would recreate the retired
    // cut-owned SE shape; stands down for now. Attach rows stand down too
    // (their cel links point into THIS cut's base).
    if (activeLayer == null ||
        !layerKindIsClipboardCopyable(activeLayer.kind) ||
        isAttachedLayer(activeLayer)) {
      return;
    }

    _layerClipboard = copyLayerToPayload(activeLayer);
    notifyListeners();
  }

  void pasteLayerFromClipboard() {
    final payload = _layerClipboard;
    if (payload == null) {
      return;
    }

    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    if (!canAddLayerOfKind(payload.kind)) {
      return; // R9 #7: this cut already holds its one row of that kind.
    }
    final activeLayer = this.activeLayer;
    final targetLayers = cut.layers;
    final activeLayerIndex = activeLayer == null
        ? -1
        : targetLayers.indexWhere((layer) => layer.id == activeLayer.id);
    final insertionIndex = activeLayerIndex == -1
        ? targetLayers.length
        : activeLayerIndex + 1;

    final pastedLayerId = _cutCommandCoordinator.pasteLayer(
      cutId: cut.id,
      payload: payload,
      insertionIndex: insertionIndex,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: pastedLayerId);
    notifyListeners();
  }

  /// The selected rows that may be DUPLICATED (⑨'s 복사).
  ///
  /// The stand-downs are [duplicateActiveLayer]'s, read off the same three
  /// predicates rather than restated: a track-owned SE row has no clipboard
  /// shape, a per-cut singleton cannot have a second, and an attach row's
  /// copy would double-link its base's cels.
  List<LayerId> duplicatableSelectedLayerIds() {
    final byId = {for (final layer in layers) layer.id: layer};
    final ids = <LayerId>[];
    for (final row in rowSelection.value) {
      if (row is! LayerRowAddress) {
        continue;
      }
      final layer = byId[row.layerId];
      if (layer != null &&
          !ids.contains(layer.id) &&
          layerKindIsClipboardCopyable(layer.kind) &&
          !layerKindIsSingletonPerCut(layer.kind) &&
          !isAttachedLayer(layer)) {
        ids.add(layer.id);
      }
    }
    return ids;
  }

  /// ⑨: every selected row duplicated, in ONE undo — the rename's twin.
  void duplicateSelectedLayers() {
    final cut = activeCutOrNull;
    final ids = duplicatableSelectedLayerIds();
    if (cut == null || ids.isEmpty) {
      return;
    }
    LayerId? landed;
    _historyManager.runAsOneStep('Duplicate rows', () {
      for (final layerId in ids) {
        landed = _cutCommandCoordinator.duplicateLayer(
          cutId: cut.id,
          sourceLayerId: layerId,
        );
      }
    });
    _refreshAfterCutCommand(preferredActiveLayerId: landed);
    notifyListeners();
  }

  /// ⑰'s law, applied to 복사: the verb asks WHAT IS SELECTED first and
  /// falls back to the row you are standing on. Every caller — the pill
  /// button, a shortcut — inherits that without asking twice.
  void duplicateActiveLayer() {
    if (duplicatableSelectedLayerIds().isNotEmpty) {
      duplicateSelectedLayers();
      return;
    }
    final activeLayer = this.activeLayer;
    // Track-owned SE rows: duplication stands down (same clipboard-shape
    // reason as copyActiveLayer); attach rows too (v1 — a duplicate would
    // double-link the same base cels).
    if (activeLayer == null ||
        !layerKindIsClipboardCopyable(activeLayer.kind) ||
        // R9 #7: the copy lands in the same cut — always the second one.
        layerKindIsSingletonPerCut(activeLayer.kind) ||
        isAttachedLayer(activeLayer)) {
      return;
    }

    final duplicatedLayerId = _cutCommandCoordinator.duplicateLayer(
      // A non-null active layer implies an active cut (gap state has no
      // rows at all).
      cutId: requireActiveCut.id,
      sourceLayerId: activeLayer.id,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: duplicatedLayerId);
    notifyListeners();
  }

  /// Whether the layer is a member of a link group in the ACTIVE cut
  /// (drives the link badge on its label).
  bool isLayerLinked(LayerId layerId) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return false;
    }
    return _repository.requireProject().linkRegistry.useCountOf(
          cutId: cut.id,
          layerId: layerId,
        ) >
        1;
  }

  bool get canLinkDuplicateActiveLayer {
    final activeLayer = this.activeLayer;
    // Same stand-downs as plain duplication; an attach row's LINK
    // duplicate is reached through its base (the group goes whole).
    return activeLayer != null &&
        layerKindIsClipboardCopyable(activeLayer.kind) &&
        // R9 #7: a duplicate lands in the SAME cut, so a singleton kind's
        // copy would always be the second one.
        !layerKindIsSingletonPerCut(activeLayer.kind) &&
        !isAttachedLayer(activeLayer);
  }

  /// 링크 복제: duplicates the active layer's whole attach group SHARING
  /// the originals' pictures (the store routes both to one cel bank).
  void linkDuplicateActiveLayer() {
    if (!canLinkDuplicateActiveLayer) {
      return;
    }
    final activeLayer = this.activeLayer!;
    _cutCommandCoordinator.linkDuplicateLayer(
      cutId: requireActiveCut.id,
      layerId: activeLayer.id,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: activeLayer.id);
    notifyListeners();
  }

  bool get canUnlinkActiveLayer {
    final activeLayer = this.activeLayer;
    final cut = activeCutOrNull;
    if (activeLayer == null || cut == null) {
      return false;
    }
    // The verb unlinks the whole attach group; it is offered when ANY
    // member is linked (mirrors the coordinator's own guard).
    final baseId = activeLayer.attachedToLayerId ?? activeLayer.id;
    final registry = _repository.requireProject().linkRegistry;
    return cut.layers.any(
      (layer) =>
          (layer.id == baseId || layer.attachedToLayerId == baseId) &&
          registry.useCountOf(cutId: cut.id, layerId: layer.id) > 1,
    );
  }

  /// 독립시키기: forks the active layer's group out of its links — the
  /// pictures stay identical but stop being shared from here on.
  void unlinkActiveLayer() {
    if (!canUnlinkActiveLayer) {
      return;
    }
    final activeLayer = this.activeLayer!;
    _cutCommandCoordinator.unlinkLayer(
      cutId: requireActiveCut.id,
      layerId: activeLayer.id,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: activeLayer.id);
    notifyListeners();
  }

  /// 겸용컷 생성: a new cut whose drawing layers are all LINKED to the
  /// active cut's (empty timelines — same pictures, own timing).
  void createLinkedCutFromActiveCut() {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.createLinkedCut(sourceCutId: cutId);
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// 겸용 변경 preview: what linking the active cut with [targetCutId]
  /// would do (drives the confirmation dialog's 안내문). Null when there
  /// is no active cut or the target is the active cut itself.
  ConvertToLinkedCutPlan? convertToLinkedCutPreview(CutId targetCutId) {
    final originCutId = _editingSession.activeCutId;
    if (originCutId == null || originCutId == targetCutId) {
      return null;
    }
    return _cutCommandCoordinator.convertToLinkedCutPreview(
      originCutId: originCutId,
      targetCutId: targetCutId,
    );
  }

  /// Cuts the active cut can 겸용-convert WITH (every other cut, all
  /// tracks — dialog picker data).
  List<({CutId id, String name})> get convertToLinkedCutCandidates {
    final activeCutId = _editingSession.activeCutId;
    if (activeCutId == null) {
      return const [];
    }
    return [
      for (final track in _repository.requireProject().tracks)
        for (final cut in track.cuts)
          if (cut.id != activeCutId) (id: cut.id, name: cut.name),
    ];
  }

  /// [convertToLinkedCutPreview] resolved to display strings for the
  /// 안내문 dialog. Null under the preview's own null conditions.
  ConvertToLinkedCutPreviewData? convertToLinkedCutPreviewData(
    CutId targetCutId,
  ) {
    final plan = convertToLinkedCutPreview(targetCutId);
    final originCut = activeCutOrNull;
    if (plan == null || originCut == null) {
      return null;
    }
    final project = _repository.requireProject();
    Cut? targetCut;
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        if (cut.id == targetCutId) {
          targetCut = cut;
        }
      }
    }
    if (targetCut == null) {
      return null;
    }
    String layerName(Cut cut, LayerId layerId) =>
        cut.layers.firstWhere((layer) => layer.id == layerId).name;
    return ConvertToLinkedCutPreviewData(
      targetCutName: targetCut.name,
      linkingLayerNames: [
        for (final pair in plan.layerPairs)
          layerName(originCut, pair.originLayerId),
      ],
      layerNamesAppearingInTarget: [
        for (final id in plan.originOnlyLayerIds) layerName(originCut, id),
      ],
      layerNamesAppearingInOrigin: [
        for (final id in plan.targetOnlyLayerIds) layerName(targetCut, id),
      ],
      replacedFrameCount: plan.replacedFrameCount,
      joiningFrameCount: plan.joiningFrameCount,
      linksAnything: plan.linksAnything,
      canvasSizesDiffer: originCut.canvasSize != targetCut.canvasSize,
    );
  }

  /// 겸용 변경: links the active cut (origin — 원본 승리) with
  /// [targetCutId]. Callers confirm through the preview dialog first.
  void convertActiveCutToLinked(CutId targetCutId) {
    final originCutId = _editingSession.activeCutId;
    if (originCutId == null || originCutId == targetCutId) {
      return;
    }
    _cutCommandCoordinator.convertCutToLinked(
      originCutId: originCutId,
      targetCutId: targetCutId,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Deletes the active layer. Callers should confirm via dialog first and check
  /// [canDeleteActiveLayer]; this is a no-op when deletion is not allowed.
  void deleteActiveLayer() {
    final activeLayer = this.activeLayer;
    if (activeLayer == null || !canDeleteActiveLayer) {
      return;
    }

    if (activeLayer.kind == LayerKind.se) {
      final beforeSe = activeTrack.seLayers;
      final nextActiveLayerId = _stableLayerIdAfterDeleting(
        beforeLayers: beforeSe,
        deletedLayerId: activeLayer.id,
      );
      _historyManager.execute(
        RemoveTrackSeLayerCommand(
          repository: _repository,
          trackId: selectedTrackId,
          layerId: activeLayer.id,
        ),
      );
      _refreshAfterCutCommand(preferredActiveLayerId: nextActiveLayerId);
      notifyListeners();
      return;
    }

    final beforeLayers = List<Layer>.of(requireActiveCut.layers);
    final nextActiveLayerId = _stableLayerIdAfterDeleting(
      beforeLayers: beforeLayers,
      deletedLayerId: activeLayer.id,
    );

    _cutCommandCoordinator.deleteLayer(
      cutId: requireActiveCut.id,
      layerId: activeLayer.id,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: nextActiveLayerId);
    notifyListeners();
  }

  /// ⑨: deletes every selected row that names a deletable layer, as ONE
  /// undo step — the gesture selected them together, so it undoes together.
  ///
  /// Deleting from the TOP down keeps each removal's own bookkeeping (the
  /// stable next-active pick, an attach cascade) reading the stack it was
  /// written against: taking a lower row out first would shift the ones
  /// above it under the loop's feet.
  void deleteSelectedLayers() {
    final ids = deletableSelectedLayerIds();
    if (ids.isEmpty) {
      return;
    }
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    final order = {
      for (var index = 0; index < cut.layers.length; index += 1)
        cut.layers[index].id: index,
    };
    final ordered = [...ids]
      ..sort((a, b) => (order[b] ?? -1).compareTo(order[a] ?? -1));
    final nextActiveLayerId = _stableLayerIdAfterDeleting(
      beforeLayers: List<Layer>.of(cut.layers),
      deletedLayerId: ordered.last,
    );
    _historyManager.runAsOneStep('Delete rows', () {
      for (final layerId in ordered) {
        _cutCommandCoordinator.deleteLayer(cutId: cut.id, layerId: layerId);
      }
    });
    clearRowSelection();
    _refreshAfterCutCommand(preferredActiveLayerId: nextActiveLayerId);
    notifyListeners();
  }

  void renameActiveLayer(String name) {
    final activeLayer = this.activeLayer;
    if (activeLayer == null) {
      return;
    }
    renameLayer(activeLayer.id, name);
  }

  /// ⑨: 「이름편집은 선택된 편집가능 레이어 전부를 같은 이름으로 일괄 변경」.
  ///
  /// One undo step, and the SAME name on every row — the user's words are
  /// "all of them to the same name", not "a numbered series", so nothing
  /// here invents suffixes.
  void renameSelectedLayers(String name) {
    final cut = activeCutOrNull;
    final ids = renameableSelectedLayerIds();
    if (cut == null || ids.isEmpty) {
      return;
    }
    _historyManager.runAsOneStep('Rename rows', () {
      for (final layerId in ids) {
        _cutCommandCoordinator.renameLayer(
          cutId: cut.id,
          layerId: layerId,
          name: name,
        );
      }
    });
    _refreshAfterCutCommand(preferredActiveLayerId: ids.first);
    notifyListeners();
  }

  /// The selected rows whose NAME may be edited (⑨).
  ///
  /// Read-only-in-cut rows are the exception, and they are the same ones
  /// [canDeleteLayer] refuses for the same reason: a track fixture seen from
  /// inside a cut is not this cut's to edit.
  List<LayerId> renameableSelectedLayerIds() {
    final selection = rowSelection.value;
    if (selection.isEmpty) {
      return const [];
    }
    final byId = {for (final layer in layers) layer.id: layer};
    final ids = <LayerId>[];
    for (final row in selection) {
      if (row is! LayerRowAddress) {
        continue;
      }
      final layer = byId[row.layerId];
      if (layer != null &&
          !ids.contains(layer.id) &&
          !layerKindIsReadOnlyInCut(layer.kind)) {
        ids.add(layer.id);
      }
    }
    return ids;
  }

  /// Renames any row by id — folders included, because a folder is a row.
  void renameLayer(LayerId layerId, String name) {
    _cutCommandCoordinator.renameLayer(
      cutId: requireActiveCut.id,
      layerId: layerId,
      name: name,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: layerId);
    notifyListeners();
  }

  /// THE unified Add Layer entrance: a new layer of the ACTIVE layer's
  /// kind, inserted directly above it, named by its section's own scheme
  /// (cel letters / S3 / CAM 2). The camera cannot be duplicated (exactly
  /// one per cut) — with it (or nothing) active, a default cel is added.
  void addLayer() => addLayerOfKind(activeLayer?.kind ?? LayerKind.animation);

  /// Whether the ACTIVE cut can take another row of [kind] (R9 #7): false
  /// once a singleton kind already has its one row. The Add Layer menu
  /// reads this to disable the entry rather than swallowing the tap, so a
  /// dead menu item never looks like a bug.
  bool canAddLayerOfKind(LayerKind kind) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return false;
    }
    return !layerKindIsSingletonPerCut(kind) ||
        !cut.layers.any((layer) => layer.kind == kind);
  }

  /// Kind-explicit Add Layer (the split button's ▾ list): the same naming
  /// and insertion rules as [addLayer] with the requested kind.
  void addLayerOfKind(LayerKind kind) {
    if (activeCutOrNull == null) {
      return; // Gap state: no cut to add into (SE rows need one too —
      //         selection lives in the cut-scoped row list).
    }
    if (!canAddLayerOfKind(kind)) {
      return; // The cut already holds its one row of a singleton kind.
    }
    final layerId = _mintLayerId();
    switch (kind) {
      case LayerKind.transition:
        // A track fixture, created with the track — "Add layer" never makes
        // one (canAddLayerOfKind refuses first; this keeps the switch
        // exhaustive and the intent stated).
        return;
      case LayerKind.se:
        // SE rows are track-owned: insert directly above the active SE row
        // in the TRACK list (the same S1,S3,S2 insertion order the
        // timeline shows — the single ordering every panel renders).
        final seLayers = activeTrack.seLayers;
        final activeIndex = seLayers.indexWhere(
          (layer) => layer.id == activeLayerId,
        );
        final newLayer = Layer(
          id: layerId,
          name: nextSeLayerName(seLayers),
          frames: const [],
          timeline: const {},
          kind: LayerKind.se,
        );
        _historyManager.execute(
          AddTrackSeLayerCommand(
            repository: _repository,
            trackId: selectedTrackId,
            layer: newLayer,
            insertionIndex: activeIndex < 0 ? null : activeIndex + 1,
          ),
        );
        _layerController.selectLayer(layerId);
      case LayerKind.instruction:
        _layerController.addLayer(
          layer: Layer(
            id: layerId,
            name: nextInstructionLayerName(_layerController.layers),
            frames: const [],
            timeline: const {},
            kind: LayerKind.instruction,
          ),
        );
      case LayerKind.animation:
      case LayerKind.storyboard:
      case LayerKind.image:
      case LayerKind.text:
        // The COVERING kinds (storyboard, image) are born covering their
        // cut — one cell, edge to edge. There is no "X" in their world,
        // so they never start empty and then have to be filled.
        Layer newLayerFor(Cut cut) => layerKindCoversWithoutGaps(kind)
            ? createCoveringLayer(
                layerId: layerId,
                frameId: FrameId(_nextFrameId(layerId)),
                cut: cut,
                kind: kind,
              )
            : kind == LayerKind.text
            // A text row starts all-empty like an animation cel row, under
            // its own T1/T2 naming (cel letters stay the pen rows').
            ? Layer(
                id: layerId,
                name: nextTextLayerName(requireActiveCut.layers),
                frames: const [],
                timeline: const {},
                kind: LayerKind.text,
              )
            : createDefaultAnimationLayer(layerId: layerId, cut: cut);
        _addRowAboveActive(newLayerFor);
      case LayerKind.adjustment:
        // R6b: a real row you ADD (unlike a folder), joining the stack
        // above the active layer like every other kind — which is exactly
        // what puts the rows it filters below it.
        _addRowAboveActive(
          (cut) => createAdjustmentLayer(
            id: layerId,
            name: nextAdjustmentLayerName(cut.layers),
          ),
        );
      case LayerKind.folder:
        // R5 #14: a folder is ADDED now, and it is born EMPTY.
        //
        // It used to be MADE by wrapping the active row, and Add Layer with
        // a folder selected quietly added a drawing cel instead. The user
        // asked for the file-manager shape every other app they work in
        // has: make the container, then put things in it by dropping them
        // on it. The drop is this round's other half; without it an empty
        // folder would be a room with no door, because a caret between
        // rows cannot address the inside of a folder that has none (the
        // "in" and the "below" are the same slot).
        _addRowAboveActive(
          (cut) => createFolderLayer(id: layerId, name: nextFolderName(cut)),
        );
      case LayerKind.camera:
        _layerController.addLayerWithDefaults(layerId: layerId);
    }
    notifyListeners();
  }

  /// Inserts a NEW ROW the way one joins the stack above the active layer.
  ///
  /// Two structural rules, and they used to live inside the drawing-kind
  /// arm where every later kind had to remember them:
  /// - an attach group is INDIVISIBLE (R26 #36): the row lands past the
  ///   whole group, never between a base and its attach rows — whether the
  ///   active row is the base or one of its attaches. BOTH sides count: a
  ///   below-only group used to slip through an above-only check.
  /// - the row INHERITS the active row's folder. A row inserted into a
  ///   folder's contiguous member run without belonging to it breaks the
  ///   folder invariant and composites in the wrong scope; for R6b's
  ///   adjustment that meant filtering nothing at all, silently.
  void _addRowAboveActive(Layer Function(Cut cut) build) {
    final cut = requireActiveCut;
    final active = activeLayer;
    final built = build(cut);
    final layer = active?.folderId == null
        ? built
        : built.copyWith(folderId: active!.folderId);
    final baseId = active == null
        ? null
        : isAttachedLayer(active)
        ? active.attachedToLayerId
        : active.id;
    if (baseId != null) {
      final groupEnd = attachedGroupEndIndex(baseId, cut.layers);
      final groupStart = attachedGroupStartIndex(baseId, cut.layers);
      if (groupEnd - groupStart > 1) {
        _layerController.addLayer(layer: layer, insertionIndex: groupEnd);
        return;
      }
    }
    _layerController.addLayer(layer: layer);
  }

  /// Whether the active layer can carry (or already rides within) an
  /// attach group — the Add Attach Layer entrance's gate (W5).
  bool get canAddAttachedLayerToActive {
    final active = activeLayer;
    if (active == null) {
      return false;
    }
    if (isAttachedLayer(active)) {
      // Adding from an attach row targets ITS base (same group).
      return attachedBaseOf(active, requireActiveCut.layers) != null;
    }
    return canCarryAttachedLayers(active);
  }

  /// Adds an ATTACH LAYER riding the active layer (or the active attach
  /// row's base): own cels/eye/opacity, the base's FX; [placement] picks
  /// above or below the base's picture. [mode] picks the timing contract
  /// (UI-R21 #3): synced = the W5 ghost mirror riding the base's
  /// exposures; free = authors its own timeline like a normal drawing
  /// layer. Selected on creation; excluded from the timesheet by default.
  void addAttachedLayer(
    AttachedPlacement placement, {
    AttachedMode mode = AttachedMode.synced,
  }) {
    if (!canAddAttachedLayerToActive) {
      return;
    }
    final active = activeLayer!;
    final cut = requireActiveCut;
    final base = isAttachedLayer(active)
        ? attachedBaseOf(active, cut.layers)!
        : active;
    final layerId = _mintLayerId();
    final baseIndex = cut.layers.indexWhere((layer) => layer.id == base.id);
    if (baseIndex == -1) {
      return;
    }
    // [below…, base, above…]: a new below goes bottommost (before the
    // existing belows and their organizer folders), a new above topmost
    // (past the group). The new row INHERITS the base's folderId — the
    // group shares the base's folder, and a null row inside a folder's
    // contiguous run would break the folder invariant.
    var insertionIndex = placement == AttachedPlacement.below
        ? attachedGroupStartIndex(base.id, cut.layers)
        : attachedGroupEndIndex(base.id, cut.layers);
    var folderId = base.folderId;
    // SIBLING rule: adding from an attach row that lives in an ORGANIZER
    // folder ([연출]/[작감]…) with the same placement joins that folder —
    // "add another part to this 공정" — landing right where the folder
    // row sits (which keeps the folder's member run contiguous).
    final activeOrganizer = cut.layers.folderById(active.folderId);
    if (activeOrganizer != null &&
        isAttachedLayer(active) &&
        active.attachedPlacement == placement &&
        attachOrganizerBaseOf(activeOrganizer, cut.layers) == base.id) {
      folderId = activeOrganizer.id;
      insertionIndex = cut.layers.indexWhere(
        (layer) => layer.id == activeOrganizer.id,
      );
    }
    // UI-R23 #7 v2: the row is added EMPTY — the repository's
    // always-mirror reconciliation fills one own cel + base link per base
    // cel in the same write (and keeps doing so live as the base gains
    // cels later), so every mirror cell is editable from the first frame.
    _layerController.addLayer(
      layer: Layer(
        id: layerId,
        name: nextAttachedLayerName(base, cut.layers, placement),
        frames: const [],
        timeline: const {},
        // An attach row exists to be DRAWN on (own cels riding the base's
        // FX) — a base kind that refuses the brush (text) must not pass
        // the refusal down. Mirrors the referenced-image behavior, where
        // the refusal lives in a non-inherited field and the attach row
        // is born drawable.
        kind: layerKindAcceptsBrushInput(base.kind)
            ? base.kind
            : LayerKind.animation,
        onTimesheet: false,
        attachedToLayerId: base.id,
        attachedPlacement: placement,
        attachedMode: mode,
        folderId: folderId,
      ),
      insertionIndex: insertionIndex,
    );
    notifyListeners();
  }

  // --- 분리 by MENU (P3) --------------------------------------------------
  //
  // MOUNTING has no menu verb: the drag makes an attach by dropping a row
  // strictly INSIDE a group, and R5 #15 gave the one case a gap cannot
  // reach — the first rider on a base — its own landing, dropping ON the row
  // ([updateLayerRowDropOnRow]). The pair of "장착 to the neighbour" verbs
  // that lived here were that door before it existed; R5 deleted them once
  // they became a second answer to the same question.
  //
  // The release keeps its menu entry: the drag must not be a one-way door.

  bool get canDetachActiveLayer =>
      activeLayer != null && isAttachedLayer(activeLayer!);

  /// 어태치 해제: the active row stops riding its base.
  ///
  /// The row also STEPS OUT of the group when it has to
  /// ([detachLandingIndex]) — a detached row left inside the run would cut
  /// the group in two. The move and the detach are one undo step: the menu
  /// named one intent.
  void detachActiveLayer() {
    final cut = activeCutOrNull;
    final row = activeLayer;
    if (cut == null || row == null || !isAttachedLayer(row)) {
      return;
    }
    final attach = LayerAttachDrop(detachIds: {row.id});
    final landing = detachLandingIndex(cut.layers, row.id);
    final plan = landing == null
        ? null
        : resolveLayerDrop(
            stack: cut.layers,
            movingId: row.id,
            insertAt: landing,
          );
    if (plan == null) {
      _cutCommandCoordinator.setLayerAttachment(
        cutId: cut.id,
        attach: attach,
        description: 'Detach layer',
      );
    } else {
      // The MENU says the row is leaving; the drop policy supplies the
      // geometry (order + membership) for the landing. Its own edge rule —
      // where a DRAG keeps the attachment — is deliberately overridden here,
      // because a drag's own travel is what says "still in the group" and a
      // menu item has no travel.
      _cutCommandCoordinator.setLayerPlacement(
        cutId: cut.id,
        order: plan.order,
        folderIds: plan.folderIds,
        movedIds: {row.id},
        attach: attach,
        description: 'Detach layer',
      );
    }
    _refreshAfterCutCommand(preferredActiveLayerId: row.id);
    notifyListeners();
  }

  /// Selects the CUT's row — the active layer, which is the drawing target
  /// and what the timeline's rail highlights. It does not touch the
  /// storyboard rail's own [selectedRow]: the two row selections are
  /// separate (user decision 2026-07-27).
  void selectLayer(LayerId layerId) {
    var changed = false;
    // A frame-range selection is single-layer (UI-R8): moving to another
    // row drops it. The lane selection follows the same rule.
    if (frameRangeSelection.value != null &&
        frameRangeSelection.value!.layerId != layerId) {
      clearFrameRangeSelection();
      changed = true;
    }
    if (laneRangeSelection.value != null &&
        laneRangeSelection.value!.layerId != layerId) {
      clearLaneRangeSelection();
      changed = true;
    }
    // ALREADY-ACTIVE IS FREE. Every timeline cell tap calls this before it
    // seeks — `select()` sends the layer and the frame — and the seek itself
    // is deliberately notify-free (it rides the cursor notifier). This was
    // not: clicking a second cell in the row you are already on announced
    // app-wide and rebuilt the whole panel, which is what made cell
    // selection feel like it lagged behind the pointer.
    if (activeLayerId != layerId) {
      _layerController.selectLayer(layerId);
      // The solo mode FOLLOWS the active layer (R4 #7) — nothing to follow
      // when the layer did not move, and re-applying it is what would have
      // fought a manual visibility toggle on every click.
      _syncVisibilitySolo();
      changed = true;
    }
    // R10 #13: picking a layer moves the VERB's row, so the flip counts
    // this layer's blocks from here. It does NOT touch the rail's row —
    // that stays where the user put it (2026-07-27), and it is a different
    // question: which row of the FILM is lit.
    _verbRow = LayerRowAddress(layerId);
    _timelineRow = _verbRow;
    // The drawn row rides its own notifier, so leaving a property lane for
    // its layer row repaints the rail even when nothing else changed —
    // "already active is free" stays true for the session notify.
    _publishCurrentRow();
    if (changed) {
      notifyListeners();
    }
  }

  void toggleLayerVisibility(LayerId layerId) {
    _layerController.toggleLayerVisibility(layerId);
    notifyListeners();
  }

  /// AUDIO-PRO R3: mid-run schedule refresh, fired by the history
  /// listener and by the repo-direct mix edits (mute/fader/pan/solo,
  /// which bypass history).
  void _refreshLiveAudioSchedule() {
    if (audioDeviceTransport.carryingPlayback) {
      audioDeviceTransport.refreshSchedule();
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

  /// The row drag in flight, as the rails draw it. A notifier rather than a
  /// session notify: a drag moves per pointer step, and the only things
  /// that change are the caret and the lifted row's opacity.
  final ValueNotifier<LayerRowDragState?> layerRowDrag =
      ValueNotifier<LayerRowDragState?>(null);

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
  final ValueNotifier<int> revealSelectionTick = ValueNotifier<int>(0);

  /// Asks the rails to scroll whatever is selected back into view.
  void revealSelection() => revealSelectionTick.value += 1;

  /// The in-flight row-order drag ([RowOrderDrag]), or null. The plans, the
  /// caret labels and the four commit paths live on the drag class; these
  /// verbs are the session's unchanged face.
  RowOrderDrag? _rowOrderDrag;

  /// ㊵: the rows a drag on [movingId] carries because they are SELECTED.
  ///
  /// Empty unless the pressed row is itself in the selection — a drag that
  /// starts outside one is an ordinary single-row move, and ⑨ already made
  /// that press a fresh SELECT rather than a move. Only layer rows count:
  /// lanes and headers ride their layer, they do not re-order.
  Set<LayerId> _rowSelectionCarriedBy(LayerId movingId) {
    final ids = <LayerId>{
      for (final row in rowSelection.value)
        if (row is LayerRowAddress) row.layerId,
    };
    return ids.contains(movingId) ? ids : const <LayerId>{};
  }

  void beginLayerRowDrag(LayerRowDragSubject subject) {
    _rowOrderDrag = RowOrderDrag(
      subject: subject,
      channel: layerRowDrag,
      tracksNow: () => _repository.requireProject().tracks,
      effectChainOf: _effectChainOf,
      trackSeAnywhere: _trackSeAnywhere,
      activeCutOrNull: () => activeCutOrNull,
      isTrackSeLayerId: isTrackSeLayerId,
      rowSelectionCarriedBy: _rowSelectionCarriedBy,
      trackIdOfTransformLaneCarrier: trackIdOfTransformLaneCarrier,
      mountModeFor: _cutCommandCoordinator.mountModeFor,
      uiStrings: () => uiStrings,
      commitTrackReorder:
          ({required fromIndex, required toIndex, required trackName}) {
            _historyManager.execute(
              ReorderTrackCommand(
                repository: _repository,
                fromIndex: fromIndex,
                toIndex: toIndex,
                trackName: trackName,
              ),
            );
            notifyListeners();
          },
      commitTrackEffects: (trackId, effects) => updateTrackEffects(
        trackId,
        effects,
        description: 'Reorder effects',
      ),
      commitLayerEffects: ({required cutId, required layerId, required effects}) {
        _cutCommandCoordinator.updateLayerEffects(
          cutId: cutId,
          layerId: layerId,
          effects: effects,
          description: 'Reorder effects',
        );
        _refreshAfterCutCommand(preferredActiveLayerId: layerId);
        notifyListeners();
      },
      commitSeOrder: ({required trackId, required order}) {
        _cutCommandCoordinator.setTrackSeOrder(trackId: trackId, order: order);
        notifyListeners();
      },
      commitPlacement:
          ({required cutId, required plan, required subjectLayerId, required movedIds}) {
            _cutCommandCoordinator.setLayerPlacement(
              cutId: cutId,
              order: plan.order,
              folderIds: plan.folderIds,
              movedIds: movedIds,
              // What the caret promised: the move AND the attach change it
              // named, as one undo step because it was one gesture.
              attach: plan.attach,
              description: 'Move layer',
            );
            _refreshAfterCutCommand(preferredActiveLayerId: subjectLayerId);
            notifyListeners();
          },
    );
  }

  void updateTrackRowDrag(int slot) => _rowOrderDrag?.updateTrackRow(slot);

  void updateEffectRowDrag(
    LayerId layerId,
    List<EffectId> displayEffects,
    int slot,
  ) => _rowOrderDrag?.updateEffectRow(layerId, displayEffects, slot);

  void updateLayerRowDrag(
    List<Layer> displayLayers,
    int slot, {
    String? noticeLabel,
  }) => _rowOrderDrag?.updateLayerRow(
    displayLayers,
    slot,
    noticeLabel: noticeLabel,
  );

  void updateLayerRowDropOnRow(
    List<Layer> displayLayers,
    int slot,
    LayerId targetId,
  ) => _rowOrderDrag?.updateLayerRowDropOnRow(displayLayers, slot, targetId);

  void endLayerRowDrag() {
    _rowOrderDrag?.commit();
    _rowOrderDrag = null;
  }

  /// The effect chain a lane/fx-header address names: a real layer's, or the
  /// V TRACK's through the carrier id (R4b). Null when neither exists.
  List<LayerEffect>? _effectChainOf(LayerId layerId) {
    final trackId = trackIdOfTransformLaneCarrier(layerId);
    if (trackId != null) {
      return _trackById(trackId)?.effects;
    }
    return _layerById(layerId)?.effects;
  }

  void cancelLayerRowDrag() {
    _rowOrderDrag?.cancel();
    _rowOrderDrag = null;
  }

  bool get canGroupActiveLayerIntoFolder =>
      activeLayer != null && activeLayer!.kind == LayerKind.animation;

  /// 폴더 생성: folds the active layer's whole attach group into a new
  /// folder row (mirrors into 겸용 cuts through the coordinator).
  void groupActiveLayerIntoFolder() {
    if (!canGroupActiveLayerIntoFolder) {
      return;
    }
    final activeLayerId = activeLayer!.id;
    _cutCommandCoordinator.createFolderFromLayer(
      cutId: requireActiveCut.id,
      layerId: activeLayerId,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: activeLayerId);
    notifyListeners();
  }

  /// Whether the active layer can be wrapped in an ATTACH-ORGANIZER
  /// folder ([연출]/[작감]… — 공정별 묶음): an attach row not already
  /// inside one (organizers are deliberately FLAT — one level, the brush
  /// groups' precedent; constraints are easy to loosen and hard to
  /// tighten).
  bool get canGroupActiveAttachIntoFolder {
    final active = activeLayer;
    if (active == null || !isAttachedLayer(active)) {
      return false;
    }
    final layers = activeCutOrNull?.layers ?? const <Layer>[];
    final folder = layers.folderById(active.folderId);
    return folder == null || attachOrganizerBaseOf(folder, layers) == null;
  }

  /// 공정 폴더 생성: wraps the active ATTACH row in an organizer folder
  /// inside its group. Siblings join via [addAttachedLayer]'s sibling
  /// rule; renaming is plain [renameLayer].
  void groupActiveAttachIntoFolder() {
    if (!canGroupActiveAttachIntoFolder) {
      return;
    }
    final activeLayerId = activeLayer!.id;
    _cutCommandCoordinator.createAttachOrganizerFolder(
      cutId: requireActiveCut.id,
      layerId: activeLayerId,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: activeLayerId);
    notifyListeners();
  }

  void dissolveFolder(LayerId folderId) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.dissolveFolder(cutId: cutId, folderId: folderId);
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// The row's twirl. R27 #24: FOLDING a folder that holds the active
  /// layer moves the selection to the folder row itself — otherwise the
  /// fold simply wouldn't look folded (the member row would have to stay
  /// on screen to keep something selected).
  void toggleLayerCollapsed(LayerId layerId) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    final wasCollapsed = cut.layers.folderById(layerId)?.collapsed ?? false;
    _layerController.toggleLayerCollapsed(layerId);
    final activeId = activeLayerId;
    if (!wasCollapsed &&
        activeId != null &&
        cut.layers.isInsideFolder(
          cut.layers.byId(activeId)?.folderId,
          layerId,
        )) {
      _layerController.selectLayer(layerId);
    }
    notifyListeners();
  }

  /// Silences/unsilences an SE row's sounds (the mute button — view state
  /// like visibility, not undoable): playback and export skip muted
  /// layers' clips, waveforms keep displaying.
  void toggleLayerMuted(LayerId layerId) {
    _layerController.toggleLayerMuted(layerId);
    _refreshLiveAudioSchedule();
    notifyListeners();
  }

  // --- SE mix controls (AUDIO-PRO R1) ---------------------------------------

  /// The solo set — pure MONITORING state (never persisted, never
  /// exported): non-empty narrows playback/scrub to these SE rows.
  final ValueNotifier<Set<LayerId>> soloedSeLayerIds =
      ValueNotifier<Set<LayerId>>(const {});

  /// Toggles an SE row's solo (pro semantics: multiple solos stack).
  void toggleLayerSolo(LayerId layerId) {
    final next = Set<LayerId>.of(soloedSeLayerIds.value);
    if (!next.remove(layerId)) {
      next.add(layerId);
    }
    soloedSeLayerIds.value = next;
    _refreshLiveAudioSchedule();
    notifyListeners();
  }

  /// The SE row's track fader + pan (mix state like mute, repo-direct).
  void setLayerAudio({required LayerId layerId, double? gain, double? pan}) {
    _layerController.setLayerAudio(layerId: layerId, gain: gain, pan: pan);
    _refreshLiveAudioSchedule();
    notifyListeners();
  }

  void setLayerOpacity({required LayerId layerId, required double opacity}) {
    _layerController.setLayerOpacity(layerId: layerId, opacity: opacity);
    notifyListeners();
  }

  /// R26 #30: the layer's composite blend — display state alongside the
  /// eye/static opacity (repo-direct, link-group mirrored).
  void setLayerBlendMode(LayerId layerId, LayerBlendMode blendMode) {
    _layerController.setLayerBlendMode(layerId: layerId, blendMode: blendMode);
    notifyListeners();
  }

  // --- Opacity drag preview (R4 #4/#6) ------------------------------------

  /// Live opacity-drag preview: per-move values ride this notifier into
  /// the editing canvas only (the dragged FieldSlider echoes locally)
  /// WITHOUT a session notify — the old per-move repo write rebuilt every
  /// panel per pointer move and made the slider feel heavy. Release
  /// commits ONE write + notify. The legend's master bar previews a SET of
  /// rows through the same channel.
  final ValueNotifier<({Set<LayerId> layerIds, double opacity})?>
  opacityDragPreview = ValueNotifier(null);

  void previewLayerOpacity(LayerId layerId, double opacity) {
    opacityDragPreview.value = (
      layerIds: {layerId},
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  void commitLayerOpacity(LayerId layerId, double opacity) {
    opacityDragPreview.value = null;
    setLayerOpacity(layerId: layerId, opacity: opacity);
  }

  /// The master-bar preview/commit (R4 #6): [layerIds] = the rows the rail
  /// currently DISPLAYS (filter-passing), computed by the grid. Camera
  /// stays untouched (its slider is the camera-view dim).
  void previewLayersOpacity(Set<LayerId> layerIds, double opacity) {
    opacityDragPreview.value = (
      layerIds: layerIds,
      opacity: opacity.clamp(0.0, 1.0).toDouble(),
    );
  }

  /// The master bar's LAST committed value — the bar rests on this, not a
  /// live average (UI-R6 #2).
  double lastMasterOpacity = 1.0;

  void commitLayersOpacity(Set<LayerId> layerIds, double opacity) {
    opacityDragPreview.value = null;
    final clamped = opacity.clamp(0.0, 1.0).toDouble();
    lastMasterOpacity = clamped;
    for (final layer in layers) {
      if (layerIds.contains(layer.id) &&
          layerKindHasPictureOpacity(layer.kind) &&
          layer.opacity != clamped) {
        _layerController.setLayerOpacity(layerId: layer.id, opacity: clamped);
      }
    }
    notifyListeners();
  }

  /// R27 #6: the legend's BLEND bulk — the master opacity bar's rule for
  /// the mode. Only rows that actually composite take it (the camera and
  /// the sound/instruction rows have no blend), and only rows that would
  /// change are written, so a no-op pick costs nothing.
  void setBlendModeForLayers(Set<LayerId> layerIds, LayerBlendMode mode) {
    var changed = false;
    for (final layer in layers) {
      if (!layerIds.contains(layer.id) ||
          !layerKindShowsBlendControl(layer.kind) ||
          layer.blendMode == mode) {
        continue;
      }
      _layerController.setLayerBlendMode(layerId: layer.id, blendMode: mode);
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Filter-set hook (UI-R6 #3): when the active layer fails [passes], the
  /// selection moves to the nearest PASSING layer ABOVE it on screen
  /// (horizontal display order), falling back to the first passing layer.
  void moveSelectionToFilteredLayer(bool Function(Layer layer) passes) {
    final active = activeLayer;
    if (active == null || passes(active)) {
      return;
    }
    final display = horizontalLayerDisplayOrder(layers);
    final activeIndex = display.indexWhere((layer) => layer.id == active.id);
    Layer? target;
    // Screen-up = earlier in horizontal display order.
    for (var index = activeIndex - 1; index >= 0; index -= 1) {
      if (passes(display[index])) {
        target = display[index];
        break;
      }
    }
    if (target == null) {
      for (final layer in display) {
        if (passes(layer)) {
          target = layer;
          break;
        }
      }
    }
    if (target != null) {
      selectLayer(target.id);
    }
  }

  /// Flips whether [layerId] is recorded on the timesheet output. One undo
  /// step; no controller rebuild — the flag never affects rendering.
  ///
  /// ANYWHERE lookup and a nullable cut (B5③ 2026-08-17): the storyboard
  /// rail reaches this for TRACK fixtures — S rows and the transition row —
  /// whose flag is the layer's own and must flip from a gap too. The cut id
  /// is command bookkeeping the write never reads.
  void toggleLayerTimesheet(LayerId layerId) {
    final layer = requireLayerAnywhere(
      _repository.requireProject(),
      layerId,
    );
    _cutCommandCoordinator.setLayerTimesheet(
      cutId: activeCutOrNull?.id,
      layerId: layerId,
      onTimesheet: !layer.onTimesheet,
    );
    notifyListeners();
  }

  /// Flips the layer's FILL-reference flag (R20-C2, the CSP lighthouse):
  /// while any visible layer of the cut carries it, fills read ONLY the
  /// flagged layers as their source picture. One undo step; the display
  /// composite never changes.
  void toggleLayerFillReference(LayerId layerId) {
    final layer = layers.firstWhere((layer) => layer.id == layerId);
    _cutCommandCoordinator.setLayerFillReference(
      cutId: requireActiveCut.id,
      layerId: layerId,
      isFillReference: !layer.isFillReference,
    );
    notifyListeners();
  }

  /// Project-level sheet-header text (title/episode/artist) the timesheet
  /// document reads.
  TimesheetInfo get timesheetInfo => _repository.requireProject().timesheetInfo;

  /// One undo step; no-op when unchanged.
  void updateTimesheetInfo(TimesheetInfo info) {
    _cutCommandCoordinator.setTimesheetInfo(info);
    notifyListeners();
  }

  /// The project's paper/background (R10-⑥): canvas paper, playback gap
  /// fill and export backing.
  ProjectBackground get projectBackground =>
      _repository.requireProject().background;

  /// One undo step; no-op when unchanged. Composites are untouched — the
  /// background paints at display/export time, never baked (the camera
  /// rule).
  void setProjectBackground(ProjectBackground background) {
    _cutCommandCoordinator.setProjectBackground(background);
    notifyListeners();
  }

  /// Sets [layerId]'s organizational color mark. One undo step.
  void setLayerMark(LayerId layerId, LayerMark mark) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.setLayerMark(
      cutId: cutId,
      layerId: layerId,
      mark: mark,
    );
    notifyListeners();
  }

  // --- Legend bulk commands (R-toolbar round) -----------------------------
  //
  // One legend-flyout action sweeps every eligible layer of the active cut.
  // Semantics mirror the per-row toggles: visibility/mute/opacity ride the
  // layer controller (view-ish state, not undoable — same as their single
  // buttons), sheet/mark/fill-reference are undoable and land as ONE
  // CompositeCommand entry.

  /// Shows or hides every layer of the active cut.
  void setAllLayersVisibility(bool visible) {
    for (final layer in layers) {
      if (layer.isVisible != visible) {
        _layerController.toggleLayerVisibility(layer.id);
      }
    }
    notifyListeners();
  }

  /// Mutes/unmutes every SE layer of the active cut.
  void setAllSeLayersMuted(bool muted) {
    for (final layer in layers) {
      if (layer.kind == LayerKind.se && layer.muted != muted) {
        _layerController.toggleLayerMuted(layer.id);
      }
    }
    notifyListeners();
  }

  /// Resets every opacity-bearing layer back to fully opaque. The camera
  /// row's slider is the camera-view DIM (a host notifier), not layer
  /// opacity — it stays untouched.
  void resetAllLayersOpacity() => setAllLayersOpacity(1.0);

  /// Sets every picture-opacity layer's opacity to [opacity] (the legend's
  /// numeric bulk set). Camera stays untouched (its slider is the dim).
  void setAllLayersOpacity(double opacity) {
    final clamped = opacity.clamp(0.0, 1.0);
    for (final layer in layers) {
      if (layerKindHasPictureOpacity(layer.kind) && layer.opacity != clamped) {
        _layerController.setLayerOpacity(layerId: layer.id, opacity: clamped);
      }
    }
    notifyListeners();
  }

  /// Turns the timesheet flag on/off for every eligible layer — one undo.
  /// Track-owned SE rows join the sweep: the flag commands resolve through
  /// the anywhere lookup now (the SE mark/sheet fix).
  void setAllLayersOnTimesheet(bool onTimesheet) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    final cutId = cut.id;
    final commands = <Command>[
      for (final layer in [...cut.layers, ...activeTrack.seLayers])
        if (layer.attachedToLayerId == null && layer.onTimesheet != onTimesheet)
          UpdateLayerTimesheetCommand(
            repository: _repository,
            cutId: cutId,
            layerId: layer.id,
            onTimesheet: onTimesheet,
          ),
    ];
    if (commands.isEmpty) {
      return;
    }
    _historyManager.execute(
      CompositeCommand(
        description: onTimesheet
            ? 'Add all layers to timesheet'
            : 'Remove all layers from timesheet',
        commands: commands,
      ),
    );
    notifyListeners();
  }

  /// Clears every layer mark of the active cut (track-owned SE rows
  /// included, like the sheet sweep) — one undo.
  void clearAllLayerMarks() {
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    final cutId = cut.id;
    final commands = <Command>[
      for (final layer in [...cut.layers, ...activeTrack.seLayers])
        if (layer.mark != LayerMark.none)
          UpdateLayerMarkCommand(
            repository: _repository,
            cutId: cutId,
            layerId: layer.id,
            mark: LayerMark.none,
          ),
    ];
    if (commands.isEmpty) {
      return;
    }
    _historyManager.execute(
      CompositeCommand(
        description: 'Clear all layer marks',
        commands: commands,
      ),
    );
    notifyListeners();
  }

  /// Drops the fill-reference flag from every layer — one undo (cut-owned
  /// layers, like the sheet sweep).
  void clearAllFillReferences() {
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    final cutId = cut.id;
    final commands = <Command>[
      for (final layer in cut.layers)
        if (layer.isFillReference)
          UpdateLayerFillReferenceCommand(
            repository: _repository,
            cutId: cutId,
            layerId: layer.id,
            isFillReference: false,
          ),
    ];
    if (commands.isEmpty) {
      return;
    }
    _historyManager.execute(
      CompositeCommand(
        description: 'Clear all fill references',
        commands: commands,
      ),
    );
    notifyListeners();
  }

  /// Bypasses or restores EVERY layer's fx — the legend's bulk flyout,
  /// through the same persisted switches the per-row master writes, as ONE
  /// undo step (R8).
  void setAllLayersFxBypassed(bool bypassed) {
    _setLayerFxSwitches(layers, enabled: !bypassed);
  }

  /// The project's instruction vocabulary (FI/FO/PAN …, user-editable).
  CameraInstructionSet get cameraInstructionSet =>
      _repository.requireProject().cameraInstructions;

  /// One undo step; no-op when unchanged.
  void updateCameraInstructionSet(CameraInstructionSet instructionSet) {
    _cutCommandCoordinator.updateCameraInstructionSet(instructionSet);
    notifyListeners();
  }

  /// Replaces [layerId]'s instruction span map (instruction rows only).
  /// One undo step; no-op when unchanged. Never touches rendering caches —
  /// instruction spans are timeline annotations, not composite inputs.
  void updateLayerInstructions(
    LayerId layerId,
    Map<int, InstructionEvent> instructions, {
    String description = 'Edit instructions',
  }) {
    final cutId = _editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _cutCommandCoordinator.updateLayerInstructions(
      cutId: cutId,
      layerId: layerId,
      instructions: instructions,
      description: description,
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // The TRANSITION row (O.L / F.I / F.O). Same spans, same dialog, same
  // grips as a cut's direction row — the differences are that the frames
  // are GLOBAL and the vocabulary is filtered to the 場面転換 terms.
  // ---------------------------------------------------------------------

  /// The terms a transition span may carry: F.I, F.O, W.I, W.O, O.L. The
  /// camera-work terms (PAN, T.U, …) stay on the cut's direction row.
  List<CameraInstructionDef> get transitionInstructionDefs => [
    for (final def in cameraInstructionSet.defs)
      if (cameraInstructionIsTransition(def)) def,
  ];

  /// Whether a transition span can start at the playhead: there has to be a
  /// vocabulary to draw from and no span there already.
  ///
  /// The playhead is [editingGlobalFrame] — the ONE track-global reader — and
  /// not "cut start + local index". A parked playhead sits in a GAP with no
  /// active cut, and a gap is a legitimate transition partner (a fade out to
  /// black, or the のりしろ an animator gets by opening a gap in front of the
  /// only cut they were given), so the arithmetic that needs a cut answers
  /// wrong in precisely the case this row exists for.
  /// 🚨★★ 유저 #17 (2026-08-15): 「스토리보드패널의 **트랜지션레이어**,
  /// 선택범위로 프레임생성누르면 **선택범위만큼 생성되는게 일반적인데 이
  /// 레이어만 다름.** 대체 왜? **왜 이렇게 규칙을 가끔가다 통일안하는거지?**」
  ///
  /// WHERE a new span starts and HOW LONG it is: the selection when the
  /// selection covers this row, the playhead and one frame otherwise. Null
  /// when there is nowhere to put one.
  ///
  /// ★One sentence, read by both the gate below and the verb under it (T25:
  /// 「버튼이 켜지는 근거와 눌렀을 때 도는 근거는 같은 문장 하나여야 한다.
  /// 둘이면 반드시 갈라진다」). The length hard-coded to 1 was this row's
  /// whole difference from every other row — everywhere else the count comes
  /// from the range, so this was a special case with no rule behind it.
  ///
  /// ⛔A long range is not refused when something is already in the way:
  /// [instructionMapWithEventAdded] clamps to the next span's start, so "the
  /// room ran out" answers with a shorter span, never with a lit button that
  /// does nothing.
  ({int startFrame, int length})? get transitionSpanCreationOrNull {
    if (transitionInstructionDefs.isEmpty) {
      return null;
    }
    final track = activeTrack;
    final selection = trackFrameRangeSelection.value;
    final overThisRow =
        selection != null &&
        selection.trackId == track.id &&
        selection.coversRow(LayerRowAddress(track.transitionLayer.id));
    final startFrame = overThisRow ? selection.startFrame : editingGlobalFrame;
    final length = overThisRow ? selection.lengthFrames : 1;
    if (startFrame < 0 || length < 1) {
      return null;
    }
    final covering = instructionSpanCovering(
      track.transitionLayer.instructions,
      startFrame,
    );
    return covering == null ? (startFrame: startFrame, length: length) : null;
  }

  bool get canCreateTransitionSpanAtPlayhead =>
      transitionSpanCreationOrNull != null;

  /// Starts a transition span on the GLOBAL axis, where and as long as
  /// [transitionSpanCreationOrNull] says.
  ///
  /// Dialog-free like its direction-row twin (UI-R25 #2): it takes the first
  /// transition term and the Edit Instance dialog changes it afterwards. The
  /// grips own the length from then on — and a span only DOES anything once
  /// it has been dragged across a cut boundary, which is the rule the
  /// geometry enforces rather than this verb.
  void createTransitionSpanAtPlayhead() {
    final plan = transitionSpanCreationOrNull;
    if (plan == null) {
      return;
    }
    final track = activeTrack;
    final before = track.transitionLayer;
    final next = instructionMapWithEventAdded(
      before.instructions,
      startIndex: plan.startFrame,
      event: InstructionEvent(
        instructionId: transitionInstructionDefs.first.id,
        length: plan.length,
      ),
    );
    if (next == null) {
      return;
    }
    _historyManager.execute(
      UpdateTrackTransitionLayerCommand(
        repository: _repository,
        trackId: track.id,
        before: before,
        after: before.copyWith(instructions: next),
        label: 'Add transition',
      ),
    );
    _transitionDisplayClone = null;
    notifyListeners();
  }

  /// Replaces the whole transition span map in one undo step — the writer
  /// behind the edge grips and the edit dialog.
  void updateTransitionInstructions(
    Map<int, InstructionEvent> instructions, {
    String description = 'Edit transition',
  }) {
    final track = activeTrack;
    final before = track.transitionLayer;
    _historyManager.execute(
      UpdateTrackTransitionLayerCommand(
        repository: _repository,
        trackId: track.id,
        before: before,
        after: before.copyWith(
          instructions: SplayTreeMap<int, InstructionEvent>.from(instructions),
        ),
        label: description,
      ),
    );
    _transitionDisplayClone = null;
    notifyListeners();
  }

  /// The vocabulary a transition dialog picks from — the same set object the
  /// picker already takes, holding only the 場面転換 terms. The vocabulary
  /// EDITOR is not offered from here: it commits the whole set, so editing a
  /// filtered copy would delete every camera-work term.
  CameraInstructionSet get transitionInstructionSet =>
      CameraInstructionSet(defs: transitionInstructionDefs);

  /// The transition span covering [globalFrame] on the active track, as
  /// (startIndex, event); null on an empty cell. Frames are GLOBAL — this
  /// row's axis is the track's.
  MapEntry<int, InstructionEvent>? transitionSpanAt(int globalFrame) =>
      instructionSpanCovering(
        activeTrack.transitionLayer.instructions,
        globalFrame,
      );

  /// Replaces the event of the span covering [globalFrame], keeping its start
  /// and length (the grips own those). No-op on an empty cell — creation is
  /// [createTransitionSpanAtPlayhead]'s job, so the dialog can never move a
  /// span by re-picking its term.
  void replaceTransitionEventAt(int globalFrame, InstructionEvent event) {
    final covering = transitionSpanAt(globalFrame);
    if (covering == null) {
      return;
    }
    final next = instructionMapWithEventReplaced(
      activeTrack.transitionLayer.instructions,
      spanStartIndex: covering.key,
      event: event,
    );
    if (next == null) {
      return;
    }
    updateTransitionInstructions(next, description: 'Edit transition');
  }

  /// Removes the transition span covering [globalFrame]; one undo step.
  void removeTransitionSpanAt(int globalFrame) {
    final covering = transitionSpanAt(globalFrame);
    if (covering == null) {
      return;
    }
    final next = instructionMapWithEventRemoved(
      activeTrack.transitionLayer.instructions,
      spanStartIndex: covering.key,
    );
    if (next == null) {
      return;
    }
    updateTransitionInstructions(next, description: 'Delete transition');
  }

  // --- The transition row's edge drags -------------------------------------
  //
  // The drag itself is [TransitionEdgeDrag] — the pilot [EditorDragSession]:
  // the gesture's state lives on a per-drag object, and the session keeps
  // only WHICH drag is live. These verbs are the session's unchanged face.

  TransitionEdgeDrag? _transitionEdgeDrag;

  /// The transition row as the in-flight edge drag would leave it — the
  /// strip renders THIS while a grip is held, so the mark follows the hand
  /// instead of jumping on release. Null when no drag is in flight.
  final ValueNotifier<Layer?> transitionEdgeDragPreview = ValueNotifier(null);

  /// Grabs [edge] of the transition span starting at [spanStartIndex]
  /// (GLOBAL frame); false when no span starts there — see
  /// [TransitionEdgeDrag.begin] for the active-track scoping rule.
  bool beginTransitionEdgeDrag({
    required int spanStartIndex,
    required TimelineBlockEdge edge,
    LayerId? layerId,
  }) {
    final drag = TransitionEdgeDrag.begin(
      layer: activeTrack.transitionLayer,
      spanStartIndex: spanStartIndex,
      edge: edge,
      layerId: layerId,
      preview: transitionEdgeDragPreview,
      commitInstructions: updateTransitionInstructions,
    );
    if (drag == null) {
      // A refused grip leaves an in-flight drag exactly as it was — the
      // slot is only ever cleared by the drag's own end/cancel.
      return false;
    }
    _transitionEdgeDrag = drag;
    return true;
  }

  void updateTransitionEdgeDrag(int cumulativeDelta) =>
      _transitionEdgeDrag?.update(cumulativeDelta);

  /// Commits the drag as ONE undo step through the row's own writer.
  void endTransitionEdgeDrag() {
    _transitionEdgeDrag?.commit();
    _transitionEdgeDrag = null;
  }

  void cancelTransitionEdgeDrag() {
    _transitionEdgeDrag?.cancel();
    _transitionEdgeDrag = null;
  }

  /// The instruction span covering [frameIndex] on [layerId], as
  /// (startIndex, event); null on empty cells / non-instruction rows.
  MapEntry<int, InstructionEvent>? instructionSpanAt(
    LayerId layerId,
    int frameIndex,
  ) {
    final layer = _layerById(layerId);
    if (layer == null || layer.kind != LayerKind.instruction) {
      return null;
    }
    return instructionSpanCovering(layer.instructions, frameIndex);
  }

  /// Dialog-free instruction creation (UI-R25 #2, 조작 통일화): an EMPTY
  /// instruction cell gains a ONE-frame event of the vocabulary's first
  /// entry directly — the Edit Instance dialog changes it afterwards.
  /// Covered cells no-op (creation never edits).
  void createDefaultInstructionEventAtCurrentFrame() {
    final layer = activeLayer;
    if (layer == null || layer.kind != LayerKind.instruction) {
      return;
    }
    final frameIndex = _timelineController.currentFrameIndex;
    if (frameIndex < 0 ||
        instructionSpanAt(layer.id, frameIndex) != null ||
        cameraInstructionSet.defs.isEmpty) {
      return;
    }
    upsertInstructionEventAt(
      layer.id,
      frameIndex,
      InstructionEvent(
        instructionId: cameraInstructionSet.defs.first.id,
        length: 1,
      ),
      createLengthFrames: 1,
    );
  }

  /// Creates or edits the instruction event at [frameIndex] in ONE undo
  /// step: a covered cell replaces its span's event (start/length stay), an
  /// empty cell starts a new span holding to the next one / the cut's end.
  void upsertInstructionEventAt(
    LayerId layerId,
    int frameIndex,
    InstructionEvent event, {
    int? createLengthFrames,
  }) {
    final layer = _layerById(layerId);
    if (layer == null || layer.kind != LayerKind.instruction) {
      return;
    }

    // New events take the dialog's length (clamped into the cut; the add
    // helper clamps at the next span too); null fills to the cut end.
    // A resolvable instruction layer implies an active cut.
    final available = (requireActiveCut.duration - frameIndex).clamp(
      1,
      1 << 20,
    );
    final covering = instructionSpanCovering(layer.instructions, frameIndex);
    final next = covering != null
        ? instructionMapWithEventReplaced(
            layer.instructions,
            spanStartIndex: covering.key,
            event: event,
          )
        : instructionMapWithEventAdded(
            layer.instructions,
            startIndex: frameIndex,
            event: event.copyWith(
              length: (createLengthFrames ?? available).clamp(1, available),
            ),
          );
    if (next == null) {
      return;
    }
    // The sheet's memo shorthand ('A→B PAN memo') writes itself ONCE at
    // creation and stays user-editable note text from then on (R5-⑥ — the
    // derived always-printed line could not be edited). Edits and removals
    // never rewrite the note; the user owns it. Event + note = ONE undo.
    String? appendedNote;
    if (covering == null) {
      final line = timesheetMemoInstructionLine(
        event,
        cameraInstructionSet.defById(event.instructionId),
      );
      if (line.isNotEmpty) {
        final note = activeCutNote ?? '';
        appendedNote = note.isEmpty ? line : '$note\n$line';
      }
    }
    _cutCommandCoordinator.updateLayerInstructions(
      cutId: requireActiveCut.id,
      layerId: layerId,
      instructions: next,
      description: covering == null ? 'Add instruction' : 'Edit instruction',
      note: appendedNote,
    );
    notifyListeners();
  }

  /// Removes the instruction span covering [frameIndex]; one undo step.
  void removeInstructionEventAt(LayerId layerId, int frameIndex) {
    final layer = _layerById(layerId);
    if (layer == null || layer.kind != LayerKind.instruction) {
      return;
    }
    final covering = instructionSpanCovering(layer.instructions, frameIndex);
    if (covering == null) {
      return;
    }
    final next = instructionMapWithEventRemoved(
      layer.instructions,
      spanStartIndex: covering.key,
    );
    if (next == null) {
      return;
    }
    updateLayerInstructions(layerId, next, description: 'Delete instruction');
  }

  /// Whether the active layer can take an audio clip (SE rows only).
  bool get canImportAudioToActiveLayer => activeLayer?.kind == LayerKind.se;

  /// Links [filePath] to the SE instance under the playhead — sounds are
  /// FRAME-LINKED like drawings: the carrying block is the sound's window
  /// (start, length) and deleting the block silences it. Importing onto an
  /// empty cell creates the SE instance first (its own undo step), then
  /// links the sound (one more).
  void addAudioClipToActiveSeLayer(
    String filePath, {
    required bool copyIntoProject,
  }) {
    final layer = activeLayer;
    if (layer == null || layer.kind != LayerKind.se) {
      return;
    }
    // Conform from scratch — the file may have changed on disk since a
    // previous import.
    final effectivePath = importAudioFile(filePath);
    final frameIndex = _timelineController.currentFrameIndex < 0
        ? 0
        : _timelineController.currentFrameIndex;
    var frame = resolveExposedFrameAt(layer, frameIndex);
    if (frame == null) {
      createSeEntryAtCurrentFrame(name: '');
      final created = activeLayer;
      frame = created == null
          ? null
          : resolveExposedFrameAt(created, frameIndex);
      if (frame == null) {
        return;
      }
    }
    final carrier = activeLayer ?? layer;
    // The pool learns every imported file (its own undo step, like the
    // SE-instance creation above) so the browser can offer it for reuse.
    // The choice travels WITH it: the pool entry is what the save reads to
    // decide whose bytes go inside the archive, so an import that dropped
    // it here would leave a carried sound outside the file it was carried
    // into.
    addMediaAssets([effectivePath], carried: copyIntoProject);
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: carrier.id,
      audioClips: [
        ...carrier.audioClips,
        AudioClip(filePath: effectivePath, frameId: frame.id),
      ],
      description: 'Import audio',
    );
    notifyListeners();
  }

  // --- Audio import: conform and waveform for a freshly picked file -------

  /// Kicks [sourcePath]'s conform and returns the path the project records
  /// for it — the file where the user keeps it, whichever way the import
  /// window's carry-or-reference switch is set.
  ///
  /// CARRYING used to mean a second copy on disk under
  /// `<project>.assets/Media/`, and that copy was the last thing making a
  /// `.anicel` grow a sibling folder. It now means the save writes the
  /// bytes INSIDE the archive, so the choice is recorded as
  /// [MediaAsset.carried] — where a choice belongs — instead of being
  /// smuggled into the path and read back off it later.
  String importAudioFile(String sourcePath) {
    final effectivePath = _normalizedPath(sourcePath);
    // Fresh conform + waveform budget: on a re-import the file may have
    // changed on disk. (A byte-identical reused copy re-fingerprints
    // against the existing conform and lands as `reused` without a
    // decode.)
    audioConformStore.invalidate(effectivePath);
    audioConformStore.warmPaths([effectivePath]);
    return effectivePath;
  }

  /// The media browser's import: same carry-or-reference choice as a
  /// timeline import, pool only (no clip link). Non-audio kinds register
  /// with their detected kind (R3b) — the batch stays one undo through
  /// [addMediaAssets].
  void importMediaFiles(
    List<String> paths, {
    required bool copyIntoProject,
  }) {
    final pool = mediaAssets;
    final known = {for (final asset in pool) asset.path};
    final added = <MediaAsset>[];
    for (final path in paths) {
      final source = _normalizedPath(path);
      final kind = mediaAssetKindForPath(source) ?? MediaAssetKind.image;
      if (kind == MediaAssetKind.audio) {
        importAudioFile(source);
      }
      if (!known.add(source)) {
        continue;
      }
      added.add(
        MediaAsset(
          path: source,
          name: mediaAssetDefaultName(source),
          kind: kind,
          // What the user asked for. The kind still decides whether it CAN
          // be carried, and NEITHER is a path any more: every import
          // records the file where the user keeps it, and the save reads
          // this to decide whose bytes travel inside the archive.
          carried: copyIntoProject,
          // Answers "which file is this?", so it is stamped for a carried
          // asset and a reference alike — a reference is exactly the one
          // that can go missing and have to be found again, and a carried
          // asset still has an original on disk until the first save.
          identity: readMediaIdentity(source),
        ),
      );
    }
    if (added.isEmpty) {
      return;
    }
    _cutCommandCoordinator.updateMediaAssets([...pool, ...added]);
    notifyListeners();
  }

  // --- Media import (R3b): stills, GIF sequences, cut folders -------------

  int _importCutSequence = 0;

  ImportIdMint _importIdMint() {
    // ONE scan for the whole batch. An import mints an id per layer and per
    // cut it brings in, and scanning the project inside each of those turns
    // a 200-layer PSD landing in a heavy project into 200 walks of every
    // layer in it. The snapshot stays correct because the counters only
    // climb: an id minted a moment ago is not in this set, and it is not
    // reachable again either.
    final usedLayerIds = _usedLayerIdValues();
    final usedCutIds = {
      for (final track in _repository.requireProject().tracks)
        for (final cut in track.cuts) cut.id.value,
    };
    return ImportIdMint(
      nextLayerId: () => _mintLayerId(usedIds: usedLayerIds),
      // Through the MINT, not the formatter. `_nextFrameId` reads
      // `_frameSequence` and does not advance it, so calling it directly
      // leaves the wall clock as the only thing telling two cels apart —
      // and an import mints a whole layer inside one clock tick. Every cel
      // of that layer came out with the SAME id, which is not "cels that
      // look alike": it is one drawing exposed N times. A 10-drawing layer
      // arrived as one drawing.
      nextFrameId: _mintFrameId,
      nextCutId: () {
        _importCutSequence += 1;
        var candidate = 'import-cut-$_importCutSequence';
        while (usedCutIds.contains(candidate)) {
          _importCutSequence += 1;
          candidate = 'import-cut-$_importCutSequence';
        }
        return CutId(candidate);
      },
    );
  }

  /// Imports one still or animated image file (PNG/JPEG/GIF…) — the
  /// import window's core verb. Reference mode (default) copies into
  /// `.assets/Media/`, registers the asset and stamps
  /// [Layer.mediaReference]; rasterize absorbs the pixels with no
  /// registration (§3). One undo step; the baked cels display through
  /// the ordinary store paths. Returns false when nothing imported.
  Future<bool> importImageFile({
    required String path,
    required ImportDestination destination,
    required bool copyIntoProject,
    bool rasterize = false,
    MediaFitMode fit = MediaFitMode.contain,
    int? lengthFrames,
    int inFrame = 0,
    int? outFrame,
  }) async {
    // The destination gate runs BEFORE any decode: a refused import must
    // not have images to leak.
    final targetCut = destination == ImportDestination.activeCutLayer
        ? activeCutOrNull
        : null;
    if (destination == ImportDestination.activeCutLayer && targetCut == null) {
      return false;
    }
    final Uint8List bytes;
    try {
      bytes = await MediaFileBytes(path).read();
    } on Object {
      return false;
    }
    final List<DecodedImageFrame> allFrames;
    try {
      allFrames = await decodeImageFrames(bytes);
    } on Object {
      return false;
    }
    if (allFrames.isEmpty) {
      return false;
    }
    // IN/OUT on a multi-frame source: only the chosen span becomes cels.
    // The frames outside it are disposed HERE rather than left to the
    // finally block, which only knows about the ones that were kept.
    final start = inFrame < 0
        ? 0
        : (inFrame > allFrames.length - 1 ? allFrames.length - 1 : inFrame);
    final last = outFrame == null || outFrame > allFrames.length - 1
        ? allFrames.length - 1
        : (outFrame < start ? start : outFrame);
    final decoded = allFrames.sublist(start, last + 1);
    for (var index = 0; index < allFrames.length; index += 1) {
      if (index < start || index > last) {
        allFrames[index].image.dispose();
      }
    }
    final canvasSize =
        targetCut?.canvasSize ??
        activeCutOrNull?.canvasSize ??
        defaultCutCanvasSize;
    final project = _repository.requireProject();
    final mint = _importIdMint();
    final source = _normalizedPath(path);
    // The file where the user keeps it, either way: carrying is a fact
    // about the SAVE now, not about a copy made at import time.
    final identity = readMediaIdentity(source);
    final displayName = mediaAssetDefaultName(source);

    final cutId = targetCut?.id ?? mint.nextCutId();
    final stillDuration = destination == ImportDestination.activeCutLayer
        ? (targetCut!.duration < 1 ? 1 : targetCut.duration)
        : (lengthFrames ?? project.fps);

    final Layer layer;
    final List<PlannedCelBake> bakes;
    final List<MediaAsset> assets;
    if (decoded.length == 1) {
      final plan = planStillImageLayer(
        sourceFile: source,
        displayName: displayName,
        cutId: cutId,
        duration: stillDuration,
        fit: fit,
        rasterize: rasterize,
        mint: mint,
        identity: identity,
        carried: copyIntoProject,
      );
      layer = plan.layer;
      bakes = plan.bakes;
      assets = plan.assets;
    } else {
      // Animated (GIF): frames become cels with duplicate folding; the
      // fingerprint is a cheap fold over each frame's RGBA bytes.
      final fingerprints = <Object?>[];
      for (final frame in decoded) {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        fingerprints.add(data == null ? null : _foldBytes(data));
      }
      final plan = planSequenceLayer(
        sourceFiles: List<String>.filled(decoded.length, source),
        frameFingerprints: fingerprints,
        displayName: displayName,
        cutId: cutId,
        fit: fit,
        rasterize: rasterize,
        mint: mint,
        referencePath: source,
        identity: identity,
        carried: copyIntoProject,
      );
      layer = plan.layer;
      bakes = plan.bakes;
      assets = plan.assets;
    }

    if (destination == ImportDestination.activeCutLayer) {
      _historyManager.execute(
        ImportMediaCommand(
          repository: _repository,
          editingSession: _editingSession,
          targetCutId: cutId,
          newLayers: [layer],
          assetAdditions: assets,
          description: 'Import $displayName',
        ),
      );
    } else {
      final defaultCut = createDefaultCut(
        cutId: cutId,
        name: displayName,
        layerId: mint.nextLayerId(),
        canvasSize: canvasSize,
      );
      final fixtureLayers = [
        for (final fixture in defaultCut.layers)
          if (fixture.kind != LayerKind.animation) fixture,
      ];
      final cut = defaultCut.copyWith(
        duration: decoded.length > 1 ? _sequenceLength(layer) : stillDuration,
        layers: [layer, ...fixtureLayers],
      );
      _historyManager.execute(
        ImportMediaCommand(
          repository: _repository,
          editingSession: _editingSession,
          trackId: selectedTrackId,
          newCuts: [cut],
          assetAdditions: assets,
          description: 'Import $displayName',
        ),
      );
    }
    // 🔑 AFTER the registration, and only when there IS one. The bytes were
    // read to decode them so the hash costs no I/O — but it is not free of
    // CPU, and a RASTERIZING import registers no asset at all (§3: absorbed
    // pixels register nothing), so hashing there would be a full pass over
    // a large file on the UI isolate for a value the next save discards.
    //
    // Worth taking where it does register: a REFERENCED image is the asset
    // that can go missing and have to be found again, and `A1.png` repeats
    // in every cut folder on a real drive.
    if (assets.isNotEmpty) {
      rememberMediaFingerprint(source, bytes);
    }

    // Bake pixels AFTER the structure exists (keys resolve the owner
    // track through the inserted cut). Duplicate folding compresses the
    // bake list, so every bake names its SOURCE frame index.
    try {
      final bakedCut = _cutById(cutId);
      if (bakedCut != null) {
        for (final bake in bakes) {
          final surface = await rasterizeImageToSurface(
            image: decoded[bake.sourceFrameIndex].image,
            canvas: bakedCut.canvasSize,
            fit: bake.fit,
          );
          bakeCelSurface(
            brushFrameStore,
            brushFrameKeyForCut(bakedCut, bake.layerId, bake.frameId),
            surface,
          );
        }
      }
    } finally {
      for (final frame in decoded) {
        frame.image.dispose();
      }
    }

    _refreshAfterCutCommand(preferredActiveLayerId: layer.id);
    notifyListeners();
    return true;
  }

  /// EXPAND: a Photoshop stack becomes ours — ONE folder named after the
  /// file, holding its layers with their groups, names, opacity, blend and
  /// eye intact.
  ///
  /// Always baked. "One of them baked means all of them are" is the rule
  /// the user set: a half-linked stack would take original updates on some
  /// rows and not others, and a reorder in Photoshop would break the match
  /// for the rest. So nothing registers and nothing keeps a reference —
  /// the merged reading ([importImageFile]) is the one that stays live.
  ///
  /// Returns the warnings (colour conversions, blends we have no
  /// equivalent for, adjustment layers left behind), or null when the
  /// import did not happen — including a FLATTENED document, which has no
  /// stack to expand and which merge reads perfectly.
  Future<List<String>?> importPsdExpanded({
    required String path,
    required ImportDestination destination,
    MediaFitMode fit = MediaFitMode.contain,
    int? lengthFrames,
  }) async {
    // Same order as the image path: the destination gate runs before any
    // read, so a refused import never has pixels to leak.
    final targetCut = destination == ImportDestination.activeCutLayer
        ? activeCutOrNull
        : null;
    if (destination == ImportDestination.activeCutLayer && targetCut == null) {
      return null;
    }
    final Uint8List bytes;
    try {
      bytes = await MediaFileBytes(path).read();
    } on Object {
      return null;
    }
    final canvasSize =
        targetCut?.canvasSize ??
        activeCutOrNull?.canvasSize ??
        defaultCutCanvasSize;
    final project = _repository.requireProject();
    final mint = _importIdMint();
    final source = _normalizedPath(path);
    final displayName = mediaAssetDefaultName(source);
    final cutId = targetCut?.id ?? mint.nextCutId();
    final duration = destination == ImportDestination.activeCutLayer
        ? (targetCut!.duration < 1 ? 1 : targetCut.duration)
        : (lengthFrames ?? project.fps);

    final PsdExpansion? expansion;
    try {
      expansion = await readPsdExpansion(
        bytes: bytes,
        displayName: displayName,
        cutId: cutId,
        duration: duration,
        canvas: canvasSize,
        fit: fit,
        mint: mint,
      );
    } on Object {
      return null;
    }
    if (expansion == null || expansion.layers.isEmpty) {
      return null;
    }

    if (destination == ImportDestination.activeCutLayer) {
      _historyManager.execute(
        ImportMediaCommand(
          repository: _repository,
          editingSession: _editingSession,
          targetCutId: cutId,
          newLayers: expansion.layers,
          description: 'Import $displayName',
        ),
      );
    } else {
      final defaultCut = createDefaultCut(
        cutId: cutId,
        name: displayName,
        layerId: mint.nextLayerId(),
        canvasSize: canvasSize,
      );
      final fixtureLayers = [
        for (final fixture in defaultCut.layers)
          if (fixture.kind != LayerKind.animation) fixture,
      ];
      final cut = defaultCut.copyWith(
        duration: duration,
        layers: [...expansion.layers, ...fixtureLayers],
      );
      _historyManager.execute(
        ImportMediaCommand(
          repository: _repository,
          editingSession: _editingSession,
          trackId: selectedTrackId,
          newCuts: [cut],
          description: 'Import $displayName',
        ),
      );
    }

    // Pixels after the structure, like every other import: the cel keys
    // resolve their owner through the cut that now exists.
    final bakedCut = _cutById(cutId);
    if (bakedCut != null) {
      for (final cel in expansion.cels) {
        bakeCelSurface(
          brushFrameStore,
          brushFrameKeyForCut(bakedCut, cel.layerId, cel.frameId),
          cel.surface,
        );
      }
    }

    // The folder row is the last layer, and a folder takes no brush — so
    // the topmost PICTURE is what the hand should land on.
    final picture = expansion.layers.lastWhere(
      (layer) => layer.kind != LayerKind.folder,
      orElse: () => expansion!.layers.last,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: picture.id);
    notifyListeners();
    return expansion.warnings;
  }

  /// Imports a PDF: pages become cels at canvas resolution — §6-m's full
  /// pre-conversion, with the CEL STORE as the persistent home (it saves
  /// inside the .anicel, so placement rides every display/export path
  /// untouched; no separate disk cache). 1 page = 1 frame (§6-k).
  /// Returns false when the renderer is absent
  /// ([PdfRenderService.availability] says which), the destination
  /// refuses, or the document has no pages; a corrupt/locked file throws
  /// at open. A single page failing to RENDER leaves its cel empty and
  /// reports through [onPageRenderFailed] — the import still completes.
  Future<bool> importPdfFile({
    required String path,
    required ImportDestination destination,
    required bool copyIntoProject,
    bool rasterize = false,
    MediaFitMode fit = MediaFitMode.contain,
    int inFrame = 0,
    int? outFrame,
    void Function(int done, int total)? onRenderProgress,
    void Function(int pageIndex)? onPageRenderFailed,
  }) async {
    // The destination gate runs BEFORE any native work — a refused
    // import must not have opened a document to leak.
    final targetCut = destination == ImportDestination.activeCutLayer
        ? activeCutOrNull
        : null;
    if (destination == ImportDestination.activeCutLayer && targetCut == null) {
      return false;
    }
    final document = await PdfRenderService.open(path);
    if (document == null) {
      return false; // Renderer absent — the honest-absence state.
    }
    try {
      final pageCount = document.pageCount;
      if (pageCount <= 0) {
        return false;
      }
      // IN/OUT over PAGES: a hundred-page conte is imported for the cuts
      // someone is drawing this week, not for all of it. The span decides
      // how many cels there are; [pageCount] keeps describing the FILE,
      // because that is what the asset records about it.
      final firstPage = inFrame < 0
          ? 0
          : (inFrame > pageCount - 1 ? pageCount - 1 : inFrame);
      final lastPage = outFrame == null || outFrame > pageCount - 1
          ? pageCount - 1
          : (outFrame < firstPage ? firstPage : outFrame);
      final spanCount = lastPage - firstPage + 1;
      final project = _repository.requireProject();
      final mint = _importIdMint();
      final source = _normalizedPath(path);
      final identity = readMediaIdentity(source);
      final displayName = mediaAssetDefaultName(source);
      final cutId = targetCut?.id ?? mint.nextCutId();

      final Layer layer;
      final List<PlannedCelBake> bakes;
      final List<MediaAsset> assets;
      if (spanCount == 1) {
        // A one-page span is a still: an image-kind layer holding over the
        // cut, exactly like a placed PNG.
        final stillDuration = destination == ImportDestination.activeCutLayer
            ? (targetCut!.duration < 1 ? 1 : targetCut.duration)
            : project.fps;
        final plan = planStillImageLayer(
          sourceFile: source,
          displayName: displayName,
          cutId: cutId,
          duration: stillDuration,
          fit: fit,
          rasterize: rasterize,
          mint: mint,
          identity: identity,
          carried: copyIntoProject,
          assetKind: MediaAssetKind.pdf,
          pageCount: pageCount,
        );
        layer = plan.layer;
        bakes = plan.bakes;
        assets = plan.assets;
      } else {
        // Pages never fold (the fingerprint is the page index): a conte's
        // pages can repeat a layout, but page 12 is still page 12.
        final plan = planSequenceLayer(
          sourceFiles: List<String>.filled(spanCount, source),
          frameFingerprints: [
            for (var i = 0; i < spanCount; i += 1) firstPage + i,
          ],
          displayName: displayName,
          cutId: cutId,
          fit: fit,
          rasterize: rasterize,
          mint: mint,
          referencePath: source,
          identity: identity,
          carried: copyIntoProject,
          assetKind: MediaAssetKind.pdf,
          pageCount: pageCount,
        );
        layer = plan.layer;
        bakes = plan.bakes;
        assets = plan.assets;
      }

      if (destination == ImportDestination.activeCutLayer) {
        _historyManager.execute(
          ImportMediaCommand(
            repository: _repository,
            editingSession: _editingSession,
            targetCutId: cutId,
            newLayers: [layer],
            assetAdditions: assets,
            description: 'Import $displayName',
          ),
        );
      } else {
        final canvasSize = activeCutOrNull?.canvasSize ?? defaultCutCanvasSize;
        final defaultCut = createDefaultCut(
          cutId: cutId,
          name: displayName,
          layerId: mint.nextLayerId(),
          canvasSize: canvasSize,
        );
        final fixtureLayers = [
          for (final fixture in defaultCut.layers)
            if (fixture.kind != LayerKind.animation) fixture,
        ];
        final cut = defaultCut.copyWith(
          duration: spanCount > 1 ? _sequenceLength(layer) : project.fps,
          layers: [layer, ...fixtureLayers],
        );
        _historyManager.execute(
          ImportMediaCommand(
            repository: _repository,
            editingSession: _editingSession,
            trackId: selectedTrackId,
            newCuts: [cut],
            assetAdditions: assets,
            description: 'Import $displayName',
          ),
        );
      }
      // ⛔ No fingerprint here. A PDF is opened BY PATH and rendered page by
      // page precisely so a hundred-page conte never lands in memory at
      // once; reading it whole to hash it would undo the one thing this
      // path is written to avoid. A PDF that goes missing stays findable by
      // name and length like it was before.

      // Bake AFTER the structure exists, one page at a time: render the
      // page at exactly its placement size (the vector source rasters
      // once, at the size it will live at — no second resample), then
      // donate through the ordinary cel path. Each page guards itself
      // (the importCutFolder contract): the command is already committed,
      // so one damaged page must leave its cel empty and be REPORTED —
      // never abort into a half-baked import the dialog would retry as a
      // duplicate.
      final bakedCut = _cutById(cutId);
      if (bakedCut != null) {
        var done = 0;
        for (final bake in bakes) {
          // The bake counts within the SPAN; the document counts from its
          // first page.
          final pageIndex = firstPage + bake.sourceFrameIndex;
          try {
            final pageSize = document.pageSize(pageIndex);
            final placement = placementRectFor(
              sourceWidth: pageSize.width.round().clamp(1, 1 << 13).toInt(),
              sourceHeight: pageSize.height.round().clamp(1, 1 << 13).toInt(),
              canvas: bakedCut.canvasSize,
              fit: bake.fit,
            );
            final image = await document.renderPage(
              pageIndex,
              width: placement.width.round().clamp(1, 1 << 13).toInt(),
              height: placement.height.round().clamp(1, 1 << 13).toInt(),
            );
            try {
              final surface = await rasterizeImageToSurface(
                image: image,
                canvas: bakedCut.canvasSize,
                fit: bake.fit,
              );
              bakeCelSurface(
                brushFrameStore,
                brushFrameKeyForCut(bakedCut, bake.layerId, bake.frameId),
                surface,
              );
            } finally {
              image.dispose();
            }
          } on Object {
            onPageRenderFailed?.call(pageIndex);
          }
          done += 1;
          onRenderProgress?.call(done, bakes.length);
        }
      }

      _refreshAfterCutCommand(preferredActiveLayerId: layer.id);
      notifyListeners();
      return true;
    } finally {
      await document.dispose();
    }
  }

  int _sequenceLength(Layer layer) {
    var end = 1;
    for (final entry in layer.timeline.entries) {
      final length = entry.value.length ?? 1;
      if (entry.key + length > end) {
        end = entry.key + length;
      }
    }
    return end;
  }

  Object _foldBytes(ByteData data) {
    // Every 4th PIXEL, all four channels — a fold that read one channel
    // would merge frames whose change hides in the others.
    var hash = 0x811c9dc5;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 16) {
      hash = (hash ^ data.getUint32(i)) * 0x01000193 & 0xFFFFFFFF;
    }
    return Object.hash(hash, data.lengthInBytes);
  }

  Cut? _cutById(CutId cutId) {
    for (final track in _repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        if (cut.id == cutId) {
          return cut;
        }
      }
    }
    return null;
  }

  /// Imports a CUT FOLDER (the field's delivery structure) parsed by
  /// [parseCutFolder]: one fully-formed cut — symbol layers with named
  /// cels one comma each, `_BG`/`_BOOK` picture layers, archived-process
  /// attach folders when opted in — plus reference registrations, in one
  /// undo. Multi-cut folders (rule H) follow up with linked-cut creation
  /// per extra number (the field 겸용컷; separate undo steps).
  /// Returns the parse-and-plan warnings, or null when nothing imported.
  Future<List<String>?> importCutFolder({
    required String folderPath,
    required bool copyIntoProject,
    CutFolderParseConfig config = const CutFolderParseConfig(),
    MediaFitMode fit = MediaFitMode.contain,
  }) async {
    final directory = Directory(folderPath);
    if (!directory.existsSync()) {
      return null;
    }
    final entries = <CutFolderEntry>[];
    final prefixLength = directory.path.length + 1;
    try {
      await for (final entity in directory.list(recursive: true)) {
        final relative = entity.path.length > prefixLength
            ? entity.path.substring(prefixLength)
            : entity.path;
        entries.add(
          CutFolderEntry(
            relative.replaceAll('\\', '/'),
            isDirectory: entity is Directory,
          ),
        );
      }
    } on FileSystemException {
      return null; // Unreadable folder (permissions, vanished share).
    }
    final folderName = mediaAssetDefaultName(folderPath);
    final parentName = directory.parent.path.isEmpty
        ? null
        : mediaAssetDefaultName(directory.parent.path);
    final parsed = parseCutFolder(
      folderName: folderName,
      entries: entries,
      config: config,
      parentFolderName: parentName,
    );

    final canvasSize = activeCutOrNull?.canvasSize ?? defaultCutCanvasSize;
    final mint = _importIdMint();
    final plan = planCutFolderImport(
      parsed: parsed,
      resolveFile: (relativePath) => '$folderPath/$relativePath',
      canvasSize: canvasSize,
      fit: fit,
      mint: mint,
    );
    if (plan.bakes.isEmpty && plan.assets.isEmpty) {
      return plan.warnings;
    }

    // A cut folder's reference registrations follow the import's
    // carry-or-reference choice like any other file. The planner cannot
    // know it — it is given a folder, not a window — so the answer is
    // stamped on the way out.
    //
    // 🚨 It used to be stamped as a COPY into `.assets/Media` and nothing
    // else, which meant the pool entry itself said `carried: false`: the
    // one thing the save reads. The first save after a folder import left
    // every 参考 scan OUTSIDE the archive, and only a reopen put it right
    // (the old `sourcePath` spelling of the same answer). The kind still
    // sets the ceiling above this, so a delivery's 참고영상 stays a
    // reference either way.
    final registeredAssets = [
      for (final asset in plan.assets) asset.copyWith(carried: copyIntoProject),
    ];

    _historyManager.execute(
      ImportMediaCommand(
        repository: _repository,
        editingSession: _editingSession,
        trackId: selectedTrackId,
        newCuts: [plan.cut],
        assetAdditions: registeredAssets,
        description: 'Import folder $folderName',
      ),
    );

    final bakedCut = _cutById(plan.cut.id);
    if (bakedCut != null) {
      // Each file bakes exactly once — decode, bake, dispose, so the
      // peak stays ONE image no matter how large the folder (the
      // measured folders run past 100 scanned cels).
      for (final bake in plan.bakes) {
        final List<DecodedImageFrame> frames;
        try {
          frames = await decodeImageFrames(
            await MediaFileBytes(bake.sourceFile).read(),
          );
        } on Object {
          continue; // Unreadable file — the cel stays empty.
        }
        if (frames.isEmpty) {
          continue;
        }
        try {
          final surface = await rasterizeImageToSurface(
            image: frames.first.image,
            canvas: bakedCut.canvasSize,
            fit: bake.fit,
          );
          bakeCelSurface(
            brushFrameStore,
            brushFrameKeyForCut(bakedCut, bake.layerId, bake.frameId),
            surface,
          );
        } finally {
          for (final frame in frames) {
            frame.image.dispose();
          }
        }
      }
    }

    // Rule H: the folder's extra cut numbers become 겸용컷 copies of the
    // imported cut, sharing its cel banks.
    for (final extraNumber in plan.extraCutNumbers) {
      _cutCommandCoordinator.createLinkedCut(
        sourceCutId: plan.cut.id,
        name: extraNumber,
      );
    }

    _refreshAfterCutCommand();
    notifyListeners();
    return plan.warnings;
  }

  /// Imports a TVPaint JSON export: one cut carrying the clip's whole
  /// layer stack, exposure, hold/repeat edges and cel numbers, in one
  /// undo. [jsonPath] is the `.json` TVPaint wrote; its image folders sit
  /// beside it, which is what [planTvpJsonImport] resolves against.
  ///
  /// Returns the read-and-plan warnings, or null when the file is gone or
  /// is not a TVPaint export.
  /// The CSV that names this export's cels, when one was exported beside
  /// it — `343.json` is answered by `343.csv`.
  ///
  /// Asked for rather than picked: the TVPaint import already takes the
  /// FOLDER (iOS grants exactly the item chosen, and the images are
  /// siblings), so a CSV in that folder is already readable and asking
  /// for it a second time would be a window with nothing to decide. The
  /// same-stem file wins; failing that, a folder holding exactly one CSV
  /// is unambiguous. Anything else, and the cels arrive unnamed — the
  /// planner says so in its warnings, and a wrong name is worse than none.
  TvpCsvNames? _tvpNamesBeside(String jsonPath) {
    final normalized = jsonPath.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    final directory = slash <= 0 ? '.' : normalized.substring(0, slash);
    final stem = normalized.substring(
      slash + 1,
      normalized.length - '.json'.length,
    );
    try {
      final beside = File('$directory/$stem.csv');
      final candidates = beside.existsSync()
          ? [beside]
          : [
              for (final entity in Directory(directory).listSync())
                if (entity is File &&
                    entity.path.toLowerCase().endsWith('.csv'))
                  entity,
            ];
      if (candidates.length != 1) {
        return null;
      }
      return parseTvpCsv(candidates.single.readAsStringSync());
    } on Object {
      // Unreadable or not a TVPaint CSV: the import proceeds without it.
      return null;
    }
  }

  Future<List<String>?> importTvpJson({
    required String jsonPath,
    MediaFitMode fit = MediaFitMode.none,
  }) async {
    final file = File(jsonPath);
    final TvpJsonParseResult parsed;
    try {
      parsed = parseTvpJson(await file.readAsString());
    } on TvpJsonParseException {
      return null;
    } on FileSystemException {
      return null;
    }

    final directory = file.parent.path.replaceAll('\\', '/');
    final mint = _importIdMint();
    final plan = planTvpJsonImport(
      parsed: parsed,
      // The export writes POSIX-ish relative paths (`[003] D/[0004] D.png`)
      // whichever platform wrote it.
      resolveFile: (relative) =>
          '$directory/${relative.replaceAll('\\', '/')}',
      mint: mint,
      // The clip's own shooting frame becomes a zoom against THIS project's
      // frame — a cut import must not repoint the project's camera.
      cameraFrameSize: cameraFrameSize,
      names: _tvpNamesBeside(jsonPath),
      fit: fit,
    );

    _historyManager.execute(
      ImportMediaCommand(
        repository: _repository,
        editingSession: _editingSession,
        trackId: selectedTrackId,
        newCuts: [plan.cut],
        // Nothing registers: a TVPaint export's images ARE the cels.
        assetAdditions: const [],
        description: 'Import TVPaint ${parsed.clipName}',
      ),
    );

    final bakedCut = _cutById(plan.cut.id);
    if (bakedCut != null) {
      for (final bake in plan.bakes) {
        final List<DecodedImageFrame> frames;
        try {
          frames = await decodeImageFrames(
            await MediaFileBytes(bake.sourceFile).read(),
          );
        } on Object {
          continue; // Unreadable file — the cel keeps its name, no pixels.
        }
        if (frames.isEmpty) {
          continue;
        }
        try {
          final surface = await rasterizeImageToSurface(
            image: frames.first.image,
            canvas: bakedCut.canvasSize,
            fit: bake.fit,
          );
          // 「빈 사진 포함」 exports a fully transparent PNG for every
          // instance with no pixels — a quarter of a real clip's files.
          // Those rasterize to zero tiles; donating one would mark an
          // empty cel edited and carry it into every save for nothing.
          // The cel still exists, still holds its label.
          if (surface.tiles.isNotEmpty) {
            bakeCelSurface(
              brushFrameStore,
              brushFrameKeyForCut(bakedCut, bake.layerId, bake.frameId),
              surface,
            );
          }
        } finally {
          for (final frame in frames) {
            frame.image.dispose();
          }
        }
      }
    }

    _refreshAfterCutCommand();
    notifyListeners();
    return plan.warnings;
  }

  /// Rasterize (§6-f): the ONE verb for every derived-content layer.
  /// Reference layers null [Layer.mediaReference] (the pixels are already
  /// the cels) and drop the asset registration when nothing else uses it
  /// (§6-t); TEXT layers become plain animation rows — the parameters go,
  /// the baked pixels stay, the brush unlocks (§6-s).
  bool get canRasterizeActiveLayer =>
      activeLayer?.mediaReference != null ||
      activeLayer?.kind == LayerKind.text;

  void rasterizeActiveLayer() {
    final layer = activeLayer;
    if (layer != null && layer.kind == LayerKind.text) {
      _timelineController.rasterizeTextLayer(layerId: layer.id);
      _refreshAfterCutCommand(preferredActiveLayerId: layer.id);
      notifyListeners();
      return;
    }
    final reference = layer?.mediaReference;
    final cutId = _editingSession.activeCutId;
    if (layer == null || reference == null || cutId == null) {
      return;
    }
    // The asset survives when ANY OTHER layer still references its path
    // (audio clips count through the ordinary reference check) — only
    // the last referrer's rasterize unregisters (§6-t).
    var othersReference = false;
    outer:
    for (final track in _repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        for (final other in cut.layers) {
          if (other.id != layer.id &&
              other.mediaReference?.assetPath == reference.assetPath) {
            othersReference = true;
            break outer;
          }
        }
      }
    }
    _cutCommandCoordinator.rasterizeLayerReference(
      cutId: cutId,
      layerId: layer.id,
      assetStillReferenced: othersReference,
    );
    _refreshAfterCutCommand(preferredActiveLayerId: layer.id);
    notifyListeners();
  }

  // --- Text cel bake sweep (R5, §6-s) --------------------------------------
  //
  // A text cel's truth is [Frame.textContent]; the raster every consumer
  // composites is a PROJECTION baked into the ordinary cel store (the
  // import-cel grammar). Every mutation path that can move the truth —
  // edit, undo/redo, paste, duplicate, link merge, selection fills —
  // funnels through the history manager, so ONE listener re-renders
  // whatever projection went stale. Self-healing, no per-command hooks.

  /// Canonical cel key → the exact inputs its stored raster was rendered
  /// from. The CONTENT itself, not a hash — equality gates skipping a
  /// re-bake, and a ~29-bit hash collision would freeze a stale
  /// projection silently. Entries whose cel stops being a text frame are
  /// pruned, never clear-baked — a rasterized text layer KEEPS its
  /// pixels.
  final Map<BrushFrameKey, (TextCelContent?, CanvasSize)> _textCelBakedContent =
      {};
  bool _textCelSweepDirty = false;
  Future<void>? _textCelSweep;
  bool _disposed = false;

  /// Test hook: awaits the in-flight bake sweep (projection settles).
  @visibleForTesting
  Future<void> get debugTextCelSweepDone => _textCelSweep ?? Future.value();

  void _scheduleTextCelBakeSweep() {
    _textCelSweepDirty = true;
    _textCelSweep ??= Future.microtask(_runTextCelBakeSweeps);
  }

  /// Saves snapshot the store synchronously, so an in-flight bake must
  /// land first — otherwise the archive pairs NEW parameters with the OLD
  /// raster, and the first-sight trust after reload cements the stale
  /// picture forever.
  Future<void> _flushTextCelBakes() async {
    while (_textCelSweep != null) {
      await _textCelSweep;
    }
  }

  Future<void> _runTextCelBakeSweeps() async {
    try {
      while (_textCelSweepDirty && !_disposed) {
        _textCelSweepDirty = false;
        await _sweepTextCelBakesOnce();
      }
    } finally {
      _textCelSweep = null;
    }
  }

  Future<void> _sweepTextCelBakesOnce() async {
    final project = _repository.currentProject;
    if (project == null) {
      _textCelBakedContent.clear();
      return;
    }
    final registry = project.linkRegistry;
    final seen = <BrushFrameKey>{};
    var changed = false;
    for (final track in project.tracks) {
      for (final cut in track.cuts) {
        for (final layer in cut.layers) {
          if (layer.kind != LayerKind.text) {
            continue;
          }
          for (final frame in layer.frames) {
            if (_disposed) {
              return; // Mid-sweep dispose: stop touching the stores.
            }
            final raw = brushFrameKeyForCut(cut, layer.id, frame.id);
            final key = registry.canonicalCelKey(raw);
            if (!seen.add(key)) {
              continue; // Linked banks share one physical projection.
            }
            final content = frame.textContent;
            final baked = (content, cut.canvasSize);
            final known = _textCelBakedContent[key];
            if (known == baked) {
              continue;
            }
            if (known == null &&
                content != null &&
                content.text.isNotEmpty &&
                brushFrameStore.celHasRenderableContent(raw)) {
              // First sight of a cel that already carries pixels (a loaded
              // project): trust the stored projection instead of paying a
              // full re-render on open (saves flush in-flight bakes, so an
              // archive can never pair new params with an old raster). A
              // pasted/duplicated cel arrives with an EMPTY store bank and
              // falls through to the bake.
              _textCelBakedContent[key] = baked;
              continue;
            }
            if (content == null || content.text.isEmpty) {
              // The parameters went (undo of a set, cleared text): the
              // projection goes with them — the cel reads blank again.
              // ONLY for cels this sweep itself baked: a drawn cel that
              // arrives on a text row through a cross-row move has no
              // entry here, and blank-baking it would destroy artwork
              // undo cannot restore.
              if (known != null) {
                bakeCelSurface(
                  brushFrameStore,
                  raw,
                  BitmapSurface(canvasSize: cut.canvasSize),
                );
                changed = true;
              }
            } else {
              final rendered = await renderTextCelImage(
                content: content,
                canvas: cut.canvasSize,
              );
              try {
                if (_disposed) {
                  return;
                }
                final surface = await rasterizeImageToSurface(
                  image: rendered.image,
                  canvas: cut.canvasSize,
                  fit: MediaFitMode.none,
                  // The render already clipped to the pasteboard wall —
                  // its own placement keeps off-canvas overflow alive,
                  // like any oversized drop.
                  placement: rendered.placement,
                );
                if (_disposed) {
                  return;
                }
                bakeCelSurface(brushFrameStore, raw, surface);
                changed = true;
              } finally {
                rendered.image.dispose();
              }
            }
            _textCelBakedContent[key] = baked;
          }
        }
      }
    }
    _textCelBakedContent.removeWhere((key, _) => !seen.contains(key));
    if (changed && !_disposed) {
      notifyListeners();
    }
  }

  /// The active text cel's parameters (null on blank cells and non-text
  /// rows) — the text editor dialog's read side.
  TextCelContent? get selectedTextCelContent =>
      activeLayer?.kind == LayerKind.text ? selectedFrame?.textContent : null;

  /// Commits the text editor's result onto the selected cel: one undo,
  /// linked-cut mirror, projection re-baked by the sweep.
  void setTextCelContentForSelectedFrame(TextCelContent content) {
    final layer = activeLayer;
    final frame = selectedFrame;
    if (layer == null || layer.kind != LayerKind.text || frame == null) {
      return;
    }
    _timelineController.setTextContentForFrame(
      layerId: layer.id,
      frameId: frame.id,
      textContent: content,
    );
    notifyListeners();
  }

  // --- Voice recording, ADR, input meter, take preview ----------------------
  //
  // The section moved to [EditorVoiceRecording]. Unlike the settings block,
  // it did not come free: its constructor there lists the nineteen session
  // members it reads back, which is what this block's coupling actually is.
  // Everything below is the session's unchanged face on it.
  //
  // `late` because the closures below read `this`; the consequence is that a
  // session nobody recorded on builds this at `dispose` just to dispose it.
  // That is deliberate and harmless — every line of its `dispose` is a
  // null-guarded no-op on an object that never ran.
  late final EditorVoiceRecording _voiceRecording = EditorVoiceRecording(
    playback: () => playback,
    audioDeviceTransport: () => audioDeviceTransport,
    audioConformStore: () => audioConformStore,
    audioSyncSettings: () => audioSyncSettings,
    repository: () => _repository,
    cutCommandCoordinator: () => _cutCommandCoordinator,
    uiStrings: () => uiStrings,
    projectFrameRate: () => projectFrameRate,
    activeCutGlobalStartFrame: () => activeCutGlobalStartFrame,
    editingGlobalFrame: () => editingGlobalFrame,
    gapParkedGlobalFrame: () => gapParkedGlobalFrame,
    activeLayerId: () => activeLayerId,
    trackSeGlobalLayerById: trackSeGlobalLayerById,
    mintFrameId: _mintFrameId,
    mediaAssets: () => mediaAssets,
    rememberMediaFingerprint: rememberMediaFingerprint,
    frameRangeSelection: () => frameRangeSelection,
    projectFilePath: () => _projectFilePath,
    notify: notifyListeners,
  );

  /// True while a guide take is rolling (AUDIO-PRO R5).
  ValueNotifier<bool> get isVoiceRecording => _voiceRecording.isVoiceRecording;

  /// The take's transient message, or null when there is nothing to say.
  ValueNotifier<String?> get voiceRecordingNotice =>
      _voiceRecording.voiceRecordingNotice;

  /// The lane the live take previews on (REC1-C), or null between takes.
  ValueNotifier<Layer?> get voiceRecordPreviewLane =>
      _voiceRecording.voiceRecordPreviewLane;

  /// Lit while the last block of input clipped.
  ValueNotifier<bool> get voiceRecordClipLit => _voiceRecording.voiceRecordClipLit;

  /// The path a live take's preview waveform answers to (REC1-C).
  static const String voiceRecordPreviewPath =
      EditorVoiceRecording.voiceRecordPreviewPath;

  /// The capture rate the native denoiser is built for.
  static const int voiceDenoiseCaptureRate =
      EditorVoiceRecording.voiceDenoiseCaptureRate;

  List<ScheduledAudioClip> get voiceRecordCueClips =>
      _voiceRecording.voiceRecordCueClips;

  ({int startFrame, int punchFrame})? get voiceRecordStreamerWindow =>
      _voiceRecording.voiceRecordStreamerWindow;

  LayerId? get voiceRecordingMutedLaneId =>
      _voiceRecording.voiceRecordingMutedLaneId;

  Set<LayerId> get recordingMutedLayerIds =>
      _voiceRecording.recordingMutedLayerIds;

  AudioPeaks? audioPeaksForDisplay(String path) =>
      _voiceRecording.audioPeaksForDisplay(path);

  AudioInputMonitor attachInputMeter() => _voiceRecording.attachInputMeter();

  void detachInputMeter() => _voiceRecording.detachInputMeter();

  void restartInputMeter() => _voiceRecording.restartInputMeter();

  bool playOutputTestTone() => _voiceRecording.playOutputTestTone();

  VoiceRecordStartResult startVoiceRecording() =>
      _voiceRecording.startVoiceRecording();

  String? stopVoiceRecordingAndPlace() =>
      _voiceRecording.stopVoiceRecordingAndPlace();

  /// Test seams: assignable, so both halves of the property are forwarded.
  @visibleForTesting
  AudioRecorder Function()? get debugVoiceRecorderFactory =>
      _voiceRecording.debugVoiceRecorderFactory;

  @visibleForTesting
  set debugVoiceRecorderFactory(AudioRecorder Function()? factory) =>
      _voiceRecording.debugVoiceRecorderFactory = factory;

  @visibleForTesting
  Float32List? Function(Float32List samples, int channels, int sampleRate)?
  get debugVoiceDenoiser => _voiceRecording.debugVoiceDenoiser;

  @visibleForTesting
  set debugVoiceDenoiser(
    Float32List? Function(Float32List samples, int channels, int sampleRate)?
    denoiser,
  ) => _voiceRecording.debugVoiceDenoiser = denoiser;

  @visibleForTesting
  void debugIngestVoiceRecordChunk(Float32List interleaved, int channels) =>
      _voiceRecording.debugIngestVoiceRecordChunk(interleaved, channels);

  @visibleForTesting
  bool placeVoiceRecording(
    AudioRecording recording, {
    required LayerId? laneId,
    required int anchorFrame,
    int? punchEndFrame,
    int headTrimSamples = 0,
    int gainDb = 0,
    VoiceInputChannelMode channelMode = VoiceInputChannelMode.device,
    bool denoise = false,
  }) => _voiceRecording.placeVoiceRecording(
    recording,
    laneId: laneId,
    anchorFrame: anchorFrame,
    punchEndFrame: punchEndFrame,
    headTrimSamples: headTrimSamples,
    gainDb: gainDb,
    channelMode: channelMode,
    denoise: denoise,
  );

  FrameId _mintFrameId(LayerId layerId) {
    _frameSequence += 1;
    return FrameId(_nextFrameId(layerId));
  }

  /// One spelling for every path the project records: forward slashes.
  ///
  /// The media pool is keyed by path, so `C:\a\b.wav` and `C:/a/b.wav`
  /// reaching it as written are two assets for one file — two rows, a
  /// dedupe that does not, and a usage badge counting half the clips.
  /// Paths arrive spelled however the OS handed them over, so every site
  /// that records one passes it through here first.
  static String _normalizedPath(String path) => path.replaceAll('\\', '/');

  /// Removes the [clipIndex]th clip of [layerId]; one undo step.
  void removeAudioClipAt(LayerId layerId, int clipIndex) {
    final layer = _layerById(layerId);
    if (layer == null ||
        layer.kind != LayerKind.se ||
        clipIndex < 0 ||
        clipIndex >= layer.audioClips.length) {
      return;
    }
    final next = [...layer.audioClips]..removeAt(clipIndex);
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: next,
      description: 'Remove audio',
    );
    notifyListeners();
  }

  /// Sets the [clipIndex]th clip's offset trim (frames skipped into the
  /// file where its block starts) — the audio lane's slide edit; one undo
  /// step, clamped non-negative, no-op when unchanged.
  void setAudioClipOffset(LayerId layerId, int clipIndex, int offsetFrames) {
    final layer = _layerById(layerId);
    if (layer == null ||
        layer.kind != LayerKind.se ||
        clipIndex < 0 ||
        clipIndex >= layer.audioClips.length) {
      return;
    }
    final clamped = offsetFrames < 0 ? 0 : offsetFrames;
    if (layer.audioClips[clipIndex].offsetFrames == clamped) {
      return;
    }
    final next = [...layer.audioClips];
    next[clipIndex] = next[clipIndex].copyWith(offsetFrames: clamped);
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: next,
      description: 'Slide sound',
    );
    notifyListeners();
  }

  // --- Audio offset live drags (comma-drag idiom) --------------------------

  /// The in-flight slide ([AudioClipOffsetDrag]), or null. The repo-direct
  /// idiom's rationale lives on the drag class.
  AudioClipOffsetDrag? _audioOffsetDrag;

  bool beginAudioClipOffsetDrag({
    required LayerId layerId,
    required int clipIndex,
  }) {
    final drag = AudioClipOffsetDrag.begin(
      layerId: layerId,
      clipIndex: clipIndex,
      layerById: _layerById,
      previewClips: ({required layerId, required audioClips}) {
        _repository.updateLayerAudioClips(
          cutId: requireActiveCut.id,
          layerId: layerId,
          audioClips: audioClips,
        );
      },
      commitClips: ({required layerId, required audioClips}) {
        _cutCommandCoordinator.updateLayerAudioClips(
          cutId: requireActiveCut.id,
          layerId: layerId,
          audioClips: audioClips,
          description: 'Slide sound',
        );
      },
      notify: notifyListeners,
    );
    if (drag == null) {
      // A refused grip leaves an in-flight drag exactly as it was.
      return false;
    }
    _audioOffsetDrag = drag;
    return true;
  }

  void updateAudioClipOffsetDrag(int offsetFrames) =>
      _audioOffsetDrag?.update(offsetFrames);

  void endAudioClipOffsetDrag() {
    _audioOffsetDrag?.commit();
    _audioOffsetDrag = null;
  }

  void cancelAudioClipOffsetDrag() {
    _audioOffsetDrag?.cancel();
    _audioOffsetDrag = null;
  }

  /// Sets the [clipIndex]th clip's fade lengths (the audio lane's edge
  /// handles); one undo step, clamped non-negative, no-op when unchanged.
  void setAudioClipFades(
    LayerId layerId,
    int clipIndex, {
    required int fadeInFrames,
    required int fadeOutFrames,
  }) {
    final layer = _layerById(layerId);
    if (layer == null ||
        layer.kind != LayerKind.se ||
        clipIndex < 0 ||
        clipIndex >= layer.audioClips.length) {
      return;
    }
    final clampedIn = fadeInFrames < 0 ? 0 : fadeInFrames;
    final clampedOut = fadeOutFrames < 0 ? 0 : fadeOutFrames;
    final clip = layer.audioClips[clipIndex];
    if (clip.fadeInFrames == clampedIn && clip.fadeOutFrames == clampedOut) {
      return;
    }
    final next = [...layer.audioClips];
    next[clipIndex] = clip.copyWith(
      fadeInFrames: clampedIn,
      fadeOutFrames: clampedOut,
    );
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: next,
      description: 'Fade sound',
    );
    notifyListeners();
  }

  /// Sets the [clipIndex]th clip's gain (the audio lane's volume dialog);
  /// one undo step, clamped non-negative, no-op when unchanged.
  void setAudioClipGain(LayerId layerId, int clipIndex, double gain) {
    final layer = _layerById(layerId);
    if (layer == null ||
        layer.kind != LayerKind.se ||
        clipIndex < 0 ||
        clipIndex >= layer.audioClips.length) {
      return;
    }
    final clamped = gain < 0 ? 0.0 : gain;
    if (layer.audioClips[clipIndex].gain == clamped) {
      return;
    }
    final next = [...layer.audioClips];
    next[clipIndex] = next[clipIndex].copyWith(gain: clamped);
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: next,
      description: 'Sound gain',
    );
    notifyListeners();
  }

  /// Sets the [clipIndex]th clip's fade curve (AUDIO-PRO R1); one undo
  /// step, no-op when unchanged.
  void setAudioClipFadeCurve(
    LayerId layerId,
    int clipIndex,
    AudioFadeCurve curve,
  ) {
    final layer = _layerById(layerId);
    if (layer == null ||
        layer.kind != LayerKind.se ||
        clipIndex < 0 ||
        clipIndex >= layer.audioClips.length ||
        layer.audioClips[clipIndex].fadeCurve == curve) {
      return;
    }
    final next = [...layer.audioClips];
    next[clipIndex] = next[clipIndex].copyWith(fadeCurve: curve);
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: next,
      description: 'Sound fade curve',
    );
    notifyListeners();
  }

  /// Sets the [clipIndex]th clip's volume envelope (AUDIO-PRO R1); one
  /// undo step. [keys] arrive sorted from the editor; an empty list
  /// clears the envelope.
  void setAudioClipEnvelope(
    LayerId layerId,
    int clipIndex,
    List<AudioVolumeKey> keys,
  ) {
    final layer = _layerById(layerId);
    if (layer == null ||
        layer.kind != LayerKind.se ||
        clipIndex < 0 ||
        clipIndex >= layer.audioClips.length) {
      return;
    }
    final next = [...layer.audioClips];
    next[clipIndex] = next[clipIndex].copyWith(volumeKeys: keys);
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: next,
      description: 'Sound envelope',
    );
    notifyListeners();
  }

  /// The project's media pool, in pool order (the browser panel's list).
  List<MediaAsset> get mediaAssets => _repository.requireProject().mediaAssets;

  /// Whether any clip anywhere still references [path] (remove-guard and
  /// the browser's usage badge).
  bool isMediaAssetReferenced(String path) {
    // Only clips that resolve to a live frame count (REC1-A): a dangling
    // link is inaudible everywhere, so it must not hold the pool hostage.
    // A layer's MEDIA REFERENCE (§6-z23) counts too — a referenced still
    // or sequence keeps its asset in the pool.
    bool layerReferences(Layer layer) {
      if (layer.mediaReference?.assetPath == path) {
        return true;
      }
      Set<FrameId>? liveIds;
      for (final clip in layer.audioClips) {
        if (clip.filePath != path) {
          continue;
        }
        liveIds ??= {for (final frame in layer.frames) frame.id};
        if (liveIds.contains(clip.frameId)) {
          return true;
        }
      }
      return false;
    }

    for (final track in _repository.requireProject().tracks) {
      for (final layer in track.seLayers) {
        if (layerReferences(layer)) {
          return true;
        }
      }
      for (final cut in track.cuts) {
        for (final layer in cut.layers) {
          if (layerReferences(layer)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Adds [paths] to the pool (skipping known ones) without linking them
  /// anywhere — import-to-browse, one undo step.
  ///
  /// [carried] defaults to referencing, for the callers that are not an
  /// import and so have no answer to give: linking a file that was already
  /// on disk registers it as what it is, and only a picker the user
  /// answered can say the project should own the bytes.
  void addMediaAssets(List<String> paths, {bool carried = false}) {
    final pool = mediaAssets;
    final known = {for (final asset in pool) asset.path};
    final added = [
      for (final path in paths)
        if (known.add(path))
          MediaAsset(
            path: path,
            name: mediaAssetDefaultName(path),
            identity: readMediaIdentity(path),
            carried: carried,
          ),
    ];
    if (added.isEmpty) {
      return;
    }
    _cutCommandCoordinator.updateMediaAssets([
      ...pool,
      ...added,
    ], description: 'Import media');
    notifyListeners();
  }

  /// Renames the [path] asset's display name; one undo step.
  void renameMediaAsset(String path, String name) {
    _cutCommandCoordinator.updateMediaAssets([
      for (final asset in mediaAssets)
        asset.path == path ? asset.copyWith(name: name) : asset,
    ], description: 'Rename media');
    notifyListeners();
  }

  /// Removes the [path] asset from the pool; refuses while any clip still
  /// references it (returns false). One undo step.
  bool removeMediaAsset(String path) {
    if (isMediaAssetReferenced(path)) {
      return false;
    }
    final next = mediaAssets.where((asset) => asset.path != path).toList();
    if (next.length == mediaAssets.length) {
      return false;
    }
    _cutCommandCoordinator.updateMediaAssets(next, description: 'Remove media');
    notifyListeners();
    return true;
  }

  /// Points the [oldPath] asset at [newPath] — the pool entry AND every
  /// referencing clip, one undo step (Resolve-style relink for moved
  /// files). Waveforms re-extract from the new file.
  void relinkMediaAsset(String oldPath, String newPath) {
    audioConformStore.invalidate(newPath);
    _cutCommandCoordinator.relinkMediaAsset(oldPath: oldPath, newPath: newPath);
    _moveMediaFingerprints({oldPath: newPath});
    refreshMediaExistence();
    notifyListeners();
  }

  /// RELINK-2: the batch form — the media browser's "find them all under
  /// this folder" pass, in one undo step.
  ///
  /// Conforms are invalidated for every destination for the same reason the
  /// single form does it: the file behind the path changed, so a conform
  /// fingerprinted against the old one is stale even though the pool entry
  /// now looks correct.
  void relinkMediaAssets(Map<String, String> moves) {
    if (moves.isEmpty) {
      return;
    }
    for (final newPath in moves.values) {
      audioConformStore.invalidate(newPath);
    }
    _cutCommandCoordinator.relinkMediaAssets(moves);
    // 🚨 The fingerprints follow, or the next save erases the very facts
    // this relink was decided by — the store is keyed by path and the save
    // keeps only keys the pool still holds. Left out, the feature works
    // exactly once per asset and only on the machine that imported it.
    _moveMediaFingerprints(moves);
    refreshMediaExistence();
    notifyListeners();
  }

  /// RELINK-2: pool paths that were not on disk as of the last refresh.
  ///
  /// CACHED rather than probed per row. The media browser used to call
  /// `File.existsSync()` while building every row, and the loss banner
  /// would have multiplied that — a banner has to count the WHOLE pool, so
  /// one repaint became one disk hit per asset.
  ///
  /// Nothing polls. This is refreshed when the project opens, after
  /// anything that moves files, and when the user asks — the three moments
  /// where the answer can actually have changed.
  Set<String> get missingMediaPaths => _missingMediaPaths;
  Set<String> _missingMediaPaths = const <String>{};

  /// Test seam for the existence probe. Widget tests must not depend on
  /// what happens to exist on the machine running them.
  @visibleForTesting
  bool Function(String path)? debugMediaFileExists;

  /// When each pool file was last written, for the browser's rows.
  ///
  /// Filled by the same sweep that answers "is it still there", because
  /// the sweep is already touching every file: a row that asked the disk
  /// for its own date would turn one repaint into one stat per asset, and
  /// a panel repaints for reasons that have nothing to do with the file
  /// system (the same argument that moved the existence probe here).
  Map<String, DateTime> get mediaModifiedTimes => _mediaModifiedTimes;
  Map<String, DateTime> _mediaModifiedTimes = const <String, DateTime>{};

  /// Re-probes the pool. Notifies only when the answer changed, so calling
  /// it after an import that touched nothing missing is free.
  void refreshMediaExistence() {
    final probe = debugMediaFileExists ?? (String path) => File(path).existsSync();
    final missing = <String>{};
    final modified = <String, DateTime>{};
    for (final asset in mediaAssets) {
      if (!probe(asset.path)) {
        missing.add(asset.path);
        continue;
      }
      try {
        modified[asset.path] = File(asset.path).lastModifiedSync();
      } on Object {
        // Present but unreadable — a network share mid-reconnect. The row
        // shows no date rather than a wrong one.
      }
    }
    if (setEquals(missing, _missingMediaPaths) &&
        mapEquals(modified, _mediaModifiedTimes)) {
      return;
    }
    _missingMediaPaths = missing;
    _mediaModifiedTimes = modified;
    notifyListeners();
  }

  /// Marks the [path] asset as one the project CARRIES — the per-asset
  /// promotion out of the media browser, and the answer to what a
  /// REFERENCE does when the user decides they want the project to own it
  /// after all.
  ///
  /// One undo step, and nothing on disk moves. Carrying used to mean a
  /// copy under `<project>.assets/Media/`, so this verb relinked every
  /// referencing clip onto the copy's path and invalidated its conform;
  /// it now means the next save writes the bytes INSIDE the `.anicel`,
  /// and the file stays exactly where it was. Same sound, same address —
  /// nothing to relink, nothing to re-conform.
  ///
  /// Returns false when there is nothing to promote — no such asset, one
  /// already carried, or a kind that is never carried whatever anyone
  /// picks — because a promotion that changed nothing must not spend an
  /// undo step saying so.
  ///
  /// ⛔ONE DIRECTION on purpose. Carrying is always safe; UN-carrying
  /// strands a project whose original has since been moved or deleted, so
  /// the two are not a pair of switches to offer side by side. A reverse
  /// verb needs a "the original is still there" guard of its own first,
  /// and that is a separate decision.
  bool promoteMediaAssetIntoProject(String path) {
    final pool = mediaAssets;
    var promotes = false;
    for (final asset in pool) {
      if (asset.path != path) {
        continue;
      }
      // Any kind: the kind decides the DEFAULT at import, and this verb is
      // the user changing their mind afterwards.
      promotes = !asset.carried;
      break;
    }
    if (!promotes) {
      return false;
    }
    _cutCommandCoordinator.updateMediaAssets([
      for (final asset in pool)
        asset.path == path ? asset.copyWith(carried: true) : asset,
    ], description: 'Register media in project');
    notifyListeners();
    return true;
  }

  /// Links the pool asset at [path] to the SE block of [layerId] starting
  /// at [blockStartFrame] (the browser's drag-drop target hook). The block
  /// carries the sound exactly like an import at that spot; unknown pool
  /// paths register first (their own undo step, same as import).
  void linkMediaAssetToSeBlock({
    required LayerId layerId,
    required int blockStartFrame,
    required String path,
  }) {
    final layer = _layerById(layerId);
    if (layer == null || layer.kind != LayerKind.se) {
      return;
    }
    FrameId? frameId;
    for (final block in drawingBlocks(layer.timeline)) {
      if (block.startIndex == blockStartFrame) {
        frameId = block.frameId;
        break;
      }
    }
    if (frameId == null) {
      return;
    }
    final resolvedFrameId = frameId;
    // The same frame already carrying this sound is a no-op (a second link
    // would double the playback).
    if (layer.audioClips.any(
      (clip) => clip.filePath == path && clip.frameId == resolvedFrameId,
    )) {
      return;
    }
    addMediaAssets([path]);
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: [
        ...layer.audioClips,
        AudioClip(filePath: path, frameId: resolvedFrameId),
      ],
      description: 'Link sound',
    );
    notifyListeners();
  }

  Frame? get selectedFrame {
    final layer = activeLayer;
    if (layer == null) {
      return null;
    }

    return _timelineController.getSelectedFrameForLayer(layer);
  }

  Layer? get _targetLayerForKindToggle => activeLayer;

  bool get canToggleTargetLayerKind {
    final targetLayer = _targetLayerForKindToggle;
    // Only the animation ⇄ storyboard pair; other kinds have their own
    // toggles (SE) or are fixed (camera/instruction/attach rows).
    if (targetLayer == null ||
        isAttachedLayer(targetLayer) ||
        targetLayer.kind != LayerKind.animation &&
            targetLayer.kind != LayerKind.storyboard) {
      return false;
    }
    if (targetLayer.kind == LayerKind.storyboard) {
      return true;
    }

    return !_layerController.layers.any(
      (layer) =>
          layer.id != targetLayer.id && layer.kind == LayerKind.storyboard,
    );
  }

  /// Why the storyboard toggle is refused, or null when it is allowed.
  ///
  /// A cut holds at most ONE storyboard row: the conte has one strip per
  /// cut and the coverage rule has one row to tile it. The toggle says so
  /// rather than silently doing nothing, and rather than making the second
  /// row that used to red-screen the V row.
  String? get targetLayerStoryboardRefusal {
    final targetLayer = _targetLayerForKindToggle;
    if (targetLayer == null || targetLayer.kind == LayerKind.storyboard) {
      return null;
    }
    final cut = activeCutOrNull;
    if (cut == null ||
        cutAcceptsAnotherStoryboardLayer(cut, exceptLayerId: targetLayer.id)) {
      return null;
    }
    return AppText.strings.sbOneStoryboardRowPerCut;
  }

  void toggleTargetLayerKind() {
    final targetLayer = _targetLayerForKindToggle;
    if (targetLayer == null || targetLayerStoryboardRefusal != null) {
      return;
    }

    final toStoryboard = targetLayer.kind != LayerKind.storyboard;
    final nextKind = toStoryboard ? LayerKind.storyboard : LayerKind.animation;

    // A storyboard row TILES its cut, so a row that becomes one is filled
    // to cover before it changes kind — otherwise its holes would show as
    // "X" cells in the timeline while the strip, which reads the coverage
    // rule, showed none. An empty row becomes a fresh blank panel, which
    // is what a new storyboard row is born as.
    if (toStoryboard) {
      final cut = requireActiveCut;
      final filled = storyboardTimelineFilledToCover(
        timeline: targetLayer.timeline,
        cutDuration: cut.duration,
      );
      final covered = filled == null
          ? createStoryboardLayer(
              layerId: targetLayer.id,
              frameId: FrameId(_nextFrameId(targetLayer.id)),
              cut: cut,
            ).copyWith(name: targetLayer.name)
          : targetLayer.copyWith(timeline: filled);
      if (covered != targetLayer) {
        _timelineController.commitLayerTimelineDrag(
          before: targetLayer,
          after: covered,
        );
      }
    }

    _cutCommandCoordinator.updateLayerKind(
      cutId: requireActiveCut.id,
      layerId: targetLayer.id,
      kind: nextKind,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  // --- Frame / cell state / commands -------------------------------------

  bool get hasActiveNonNegativeCell {
    return activeLayer != null && _timelineController.currentFrameIndex >= 0;
  }

  bool get canCreateDrawingAtCurrentFrame {
    final layer = activeLayer;
    if (layer == null || !layerKindHoldsDrawings(layer.kind)) {
      return false;
    }
    // SYNCED attach rows (UI-R23 #7 v2): the ALWAYS-MIRROR invariant keeps
    // one own cel per base cel automatically — there is never anything
    // left to create by hand. FREE attach rows (UI-R21 #3) fall through
    // to the normal authoring path below.
    if (isSyncedAttachedLayer(layer)) {
      return false;
    }
    // A REFERENCE layer's picture comes from the library (any kind) —
    // nothing to author until rasterized. An IMAGE layer holds ONE cel by
    // definition — once it exists there is no second cel to create (paper
    // switching is cel NAMES + link banks, never another cel in the same
    // cut).
    if (layer.mediaReference != null) {
      return false;
    }
    if (layerKindHoldsSingleCel(layer.kind) && layer.frames.isNotEmpty) {
      return false;
    }

    return _timelineController.canCreateDrawingAt(
      layer: layer,
      frameIndex: _timelineController.currentFrameIndex,
    );
  }

  bool get canCopyFrameAtCurrentFrame {
    return selectedFrame != null;
  }

  bool get canPasteLinkedFrameAtCurrentFrame {
    final layer = activeLayer;
    final copiedFrame = _copiedFrame;
    if (layer == null ||
        copiedFrame == null ||
        layer.id != copiedFrame.layerId ||
        // SYNCED attach rows own no timeline — linked reuse happens
        // through the BASE's links (link the base cel instead). Free
        // attach rows author normally (UI-R21 #3).
        isSyncedAttachedLayer(layer)) {
      return false;
    }

    // 🚨T3 — the clipboard may be holding cels the layer no longer has: a
    // 잘라내기 lifted them out and orphaned them. They come BACK on the
    // paste (same ids, so it is the same cel), and gating on "the layer
    // still has it" would have made cut-then-paste-back impossible while
    // the button sat lit.
    if (copiedFrame.cels.any((cel) => cel.id == copiedFrame.frameId)) {
      return _timelineController.currentFrameIndex >= 0;
    }

    return _timelineController.canPasteLinkedFrameAt(
      layer: layer,
      frameIndex: _timelineController.currentFrameIndex,
      copiedFrameId: copiedFrame.frameId,
    );
  }

  String get copiedFrameStatusText {
    final copiedFrame = _copiedFrame;
    if (copiedFrame == null) {
      return 'Copy: -';
    }

    final label = copiedFrame.frameName?.isNotEmpty == true
        ? copiedFrame.frameName!
        : copiedFrame.frameId.value;
    return 'Copy: $label';
  }

  String get linkedFrameUsesStatusText {
    final layer = activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null) {
      return 'Links: -';
    }

    final uses = _timelineController.linkedUseCountForLayerFrame(
      layer: layer,
      frameId: frame.id,
    );
    return 'Links: $uses';
  }

  /// The timesheet "X here" action: blanks the covering block's hold so the
  /// current cell (and the rest of the old hold) becomes empty.
  ///
  /// ⛔Renamed off "cut" in T3 — see [blankExposureAtCurrentFrame].
  bool get canBlankExposureAtCurrentFrame {
    final layer = activeLayer;
    // SYNCED attach rows have no timing of their own (the base owns it);
    // free attach rows cut exposures like any drawing layer (UI-R21 #3).
    // SINGLE-CEL (image) rows hold one covering block by definition — an
    // X-here would be reverted by the covering normalization.
    if (layer == null ||
        !layerKindHoldsDrawings(layer.kind) ||
        layerKindHoldsSingleCel(layer.kind) ||
        isSyncedAttachedLayer(layer)) {
      return false;
    }

    return _timelineController.canCutExposureAt(
      layer: layer,
      frameIndex: _timelineController.currentFrameIndex,
    );
  }

  void createDrawingAtCurrentFrame() {
    final layer = activeLayer;
    if (layer == null || !canCreateDrawingAtCurrentFrame) {
      return;
    }

    _frameSequence += 1;
    _timelineController.createDrawingFrameForLayer(
      layerId: layer.id,
      frameId: FrameId(_nextFrameId(layer.id)),
    );
    notifyListeners();
  }

  /// UI-R25 #3: Add with a LIVE selection fills the WHOLE selection —
  /// wherever creation is possible, kind by kind (the rule: anywhere
  /// selectable creates). Returns true when a selection owned the press.
  ///
  /// - Cell selection: every spanned row fills its EMPTY gaps inside the
  ///   range — drawing/SE rows with a new cel per gap (exposure = gap,
  ///   ONE undo across all rows), instruction rows with a default-
  ///   vocabulary event per gap (one undo per row), the camera row with a
  ///   pose key frozen on every unkeyed frame (one undo).
  /// - Lane selection: the lane freezes a key on every unkeyed frame of
  ///   the range (one undo) — the navigator toggle's range form.
  bool createInstancesForSelection() {
    // #16 — THE TRACK RANGE SPEAKS FIRST, like it does for delete and
    // edit (유저: 「스토리보드패널에서 S행의 프레임생성이 안됨」). The S-row
    // drag writes trackFrameRangeSelection and its claim CLEARS the
    // cut-local selection this verb used to read, so creation fell
    // through to the stale active layer — the wrong row entirely. The
    // ladder rung was simply missing.
    final trackRange = trackFrameRangeSelection.value;
    if (trackRange != null && _createTrackSeEntriesForRange(trackRange)) {
      return true;
    }
    // R10 #19: a live lane SPAN, or the property row you are STANDING on
    // as a one-frame span at the playhead — one verb either way, which is
    // what makes a group HEADER key its whole member set and an effect
    // lane key its chain without a second code path (the user's
    // "카메라레이어랑 같은 동작이지? 로직 통일화해서").
    final lane = _laneVerbRange;
    if (lane != null) {
      _createLaneKeysForSelection(lane);
      return true;
    }
    final selection = frameRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final displayById = {for (final layer in layers) layer.id: layer};
    final fills =
        <
          LayerId,
          List<({int startIndex, int length, FrameId frameId, String? name})>
        >{};
    // R26 #1: every row of the selection composes into ONE undo step.
    // Camera goes FIRST — its undo restores a whole-project snapshot, so it
    // must be the last command undone (CompositeCommand undoes in reverse).
    final cameraCommands = <Command>[];
    final instructionCommands = <Command>[];
    for (final layerId in selection.spanLayerIds) {
      final layer = displayById[layerId];
      if (layer == null) {
        continue;
      }
      if (layer.kind == LayerKind.camera) {
        final command = _cameraKeysCommandForRange(selection);
        if (command != null) {
          cameraCommands.add(command);
        }
        continue;
      }
      if (layer.kind == LayerKind.instruction) {
        final command = _instructionEventsCommandForRange(layer, selection);
        if (command != null) {
          instructionCommands.add(command);
        }
        continue;
      }
      if (!layerKindHoldsDrawings(layer.kind) || isSyncedAttachedLayer(layer)) {
        continue; // Synced mirrors follow their base; nothing to author.
      }
      // R9 #9: a COVERING row is one cel edge to edge — there is no "add a
      // frame" in its world, so a selection that happens to span it must
      // pass over it rather than author into it. Until now nothing happened
      // by luck (the covering normalization leaves no empty gap to fill),
      // and #1 is about to put folders — and so their image members — into
      // range selections on purpose. Say it instead of relying on it.
      if (layerKindCoversWithoutGaps(layer.kind)) {
        continue;
      }
      final layerFills =
          <({int startIndex, int length, FrameId frameId, String? name})>[];
      for (final gap in _emptyGapsInRange(layer, selection)) {
        _frameSequence += 1;
        layerFills.add((
          startIndex: gap.startIndex,
          length: gap.length,
          frameId: FrameId(_nextFrameId(layer.id)),
          name: null,
        ));
      }
      if (layerFills.isNotEmpty) {
        fills[layer.id] = layerFills;
      }
    }
    final commands = <Command>[
      ...cameraCommands,
      ...instructionCommands,
      if (fills.isNotEmpty)
        ..._timelineController.drawingFramesCommandsForLayers(fills),
    ];
    if (commands.isNotEmpty) {
      _historyManager.execute(
        commands.length == 1
            ? commands.single
            : CompositeCommand(
                description: 'Create selected cells',
                commands: commands,
              ),
      );
      if (cameraCommands.isNotEmpty || instructionCommands.isNotEmpty) {
        _refreshAfterCutCommand();
      }
    }
    notifyListeners();
    return true;
  }

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
  List<({int startIndex, int length})> _emptyGapsInRange(
    Layer layer,
    TimelineFrameRangeSelection selection,
  ) => _emptyGapsBetween(
    layer,
    selection.startIndex,
    selection.endIndexExclusive,
  );

  /// The uncovered runs of [layer]'s timeline inside `[start, end)` — the
  /// index space is whatever the timeline's own keys speak (cut-local for
  /// cut layers, GLOBAL for track SE rows), which is what lets #16's
  /// track rung and the cell path share one walk.
  List<({int startIndex, int length})> _emptyGapsBetween(
    Layer layer,
    int startIndex,
    int endIndexExclusive,
  ) {
    final gaps = <({int startIndex, int length})>[];
    int? gapStart;
    for (var index = startIndex; index <= endIndexExclusive; index += 1) {
      final block = index >= endIndexExclusive || index < 0
          ? null
          : coveringDrawingBlockAt(layer.timeline, index);
      final covered =
          index >= endIndexExclusive ||
          index < 0 ||
          (block != null && !block.entry.ghost);
      if (!covered) {
        gapStart ??= index;
        continue;
      }
      if (gapStart != null) {
        gaps.add((startIndex: gapStart, length: index - gapStart));
        gapStart = null;
      }
    }
    return gaps;
  }

  /// #16 — creation on the TRACK axis: the S rows the range names get one
  /// blank dialogue entry per uncovered run, in one undo step. Returns
  /// false when the range names no track SE row (a cut-row range is the
  /// cut pill's business, #18) — the verb then falls down its ladder.
  ///
  /// Track SE timelines are GLOBAL-keyed, and the fills carry explicit
  /// indexes, so no cut-start lens is involved — the same reason the
  /// storyboard could never reach these rows through the cut-local
  /// selection object.
  /// #17 잔여 — THE CREATE BUTTON'S ONE SENTENCE (T25). Mirrors
  /// [createActiveInstance]'s ladder rung for rung: the selection rungs
  /// first (track S rows → lane span → cut-local range), then the
  /// current-frame capability the kind dispatch actually has.
  ///
  /// The toolbar used to keep its OWN switch, and it disagreed with the
  /// dispatch in both directions: it did not know the selection rungs
  /// (the S-row range #16 just taught the verb), and its `_ => true` arm
  /// lit the button on folder/adjustment/transition rows whose dispatch
  /// is a documented no-op — the #18 lie, one pill over.
  bool get canCreateInstance {
    if (canCreateInstanceForSelection) {
      return true;
    }
    final layer = activeLayer;
    if (layer == null || !hasActiveNonNegativeCell) {
      return false;
    }
    return switch (layer.kind) {
      LayerKind.se => canCreateDrawingAtCurrentFrame,
      LayerKind.folder ||
      LayerKind.adjustment ||
      LayerKind.transition => false,
      _ => true,
    };
  }

  /// The SELECTION rungs of [canCreateInstance], alone — the panel-shared
  /// half (B8). [createInstancesForSelection] is their dispatch, rung for
  /// rung; the storyboard's toolbar context reads THIS and then asks its
  /// own standing row, where the timeline falls to the active layer.
  bool get canCreateInstanceForSelection {
    final trackRange = trackFrameRangeSelection.value;
    if (trackRange != null && _trackSeCreationGaps(trackRange).isNotEmpty) {
      return true;
    }
    if (_laneVerbRange != null) {
      return true;
    }
    return frameRangeSelection.value != null;
  }

  /// The PLAN half of the track rung, mutation-free: which S rows the
  /// range names and which uncovered runs they hold. Split out so the
  /// button's enabled ([canCreateInstance]) and the verb read the SAME
  /// walk — a twin implementation is how enabled and dispatch drift.
  Map<Layer, List<({int startIndex, int length})>> _trackSeCreationGaps(
    TrackFrameRangeSelection range,
  ) {
    Track? track;
    for (final candidate in _repository.requireProject().tracks) {
      if (candidate.id == range.trackId) {
        track = candidate;
        break;
      }
    }
    if (track == null) {
      return const {};
    }
    final targetIds = <LayerId>{
      for (final row in [range.anchorRow, ...range.rows])
        if (row is LayerRowAddress) row.layerId,
    };
    final gaps = <Layer, List<({int startIndex, int length})>>{};
    for (final layer in track.seLayers) {
      if (!targetIds.contains(layer.id)) {
        continue;
      }
      final layerGaps = _emptyGapsBetween(
        layer,
        range.startFrame,
        range.endFrameExclusive,
      );
      if (layerGaps.isNotEmpty) {
        gaps[layer] = layerGaps;
      }
    }
    return gaps;
  }

  bool _createTrackSeEntriesForRange(TrackFrameRangeSelection range) {
    final gapsByLayer = _trackSeCreationGaps(range);
    final fills =
        <
          LayerId,
          List<({int startIndex, int length, FrameId frameId, String? name})>
        >{};
    for (final entry in gapsByLayer.entries) {
      final layer = entry.key;
      // ⚠️The fills funnel re-applies the track-SE display lens
      // (`frameOffsetForLayer` adds the active cut's global start on the
      // way in), because its usual callers speak CUT-LOCAL indexes. These
      // gaps are already GLOBAL — pre-subtract the SAME expression the
      // lens uses, or every entry lands double-shifted.
      final lensOffset = isTrackSeLayerId(layer.id)
          ? activeCutGlobalStartFrame
          : 0;
      final layerFills =
          <({int startIndex, int length, FrameId frameId, String? name})>[];
      for (final gap in entry.value) {
        _frameSequence += 1;
        layerFills.add((
          startIndex: gap.startIndex - lensOffset,
          length: gap.length,
          frameId: FrameId(_nextFrameId(layer.id)),
          // A blank DIALOGUE, like the cut-scope SE creation makes — the
          // entry exists to be written into.
          name: '',
        ));
      }
      fills[layer.id] = layerFills;
    }
    if (fills.isEmpty) {
      return false;
    }
    final commands = _timelineController.drawingFramesCommandsForLayers(fills);
    _historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: 'Create SE entries',
              commands: commands,
            ),
    );
    notifyListeners();
    return true;
  }

  Command? _cameraKeysCommandForRange(TimelineFrameRangeSelection selection) {
    final cut = activeCutOrNull;
    final cutId = _editingSession.activeCutId;
    if (cut == null || cutId == null) {
      return null;
    }
    var camera = cut.camera;
    var changed = false;
    for (
      var frame = selection.startIndex;
      frame < selection.endIndexExclusive;
      frame += 1
    ) {
      if (frame < 0 || camera.keyframeAt(frame) != null) {
        continue;
      }
      // Freeze the RESOLVED pose (AE behavior): keys appear, the picture
      // does not move.
      camera = camera.withKeyframe(
        frame,
        resolveCameraPoseAt(
          camera: cut.camera,
          canvasSize: cut.canvasSize,
          frameIndex: frame,
        ),
      );
      changed = true;
    }
    if (!changed) {
      return null;
    }
    return UpdateCutCameraCommand(
      repository: _repository,
      cutId: cutId,
      camera: camera,
      description: 'Create camera keys',
    );
  }

  Command? _instructionEventsCommandForRange(
    Layer layer,
    TimelineFrameRangeSelection selection,
  ) {
    final cutId = _editingSession.activeCutId;
    final defaultDef = cameraInstructionSet.defs.isEmpty
        ? null
        : cameraInstructionSet.defs.first;
    if (defaultDef == null || cutId == null) {
      return null;
    }
    bool covered(int index) {
      for (final entry in layer.instructions.entries) {
        if (index >= entry.key && index < entry.key + entry.value.length) {
          return true;
        }
      }
      return false;
    }

    final next = Map<int, InstructionEvent>.of(layer.instructions);
    var changed = false;
    int? gapStart;
    for (
      var index = selection.startIndex;
      index <= selection.endIndexExclusive;
      index += 1
    ) {
      final inGap =
          index < selection.endIndexExclusive && index >= 0 && !covered(index);
      if (inGap) {
        gapStart ??= index;
        continue;
      }
      if (gapStart != null) {
        next[gapStart] = InstructionEvent(
          instructionId: defaultDef.id,
          length: index - gapStart,
        );
        changed = true;
        gapStart = null;
      }
    }
    if (!changed) {
      return null;
    }
    return UpdateLayerInstructionsCommand(
      repository: _repository,
      cutId: cutId,
      layerId: layer.id,
      instructions: next,
      description: 'Create events',
    );
  }

  /// The lane-selection create (UI-R25 #3): a key frozen at the resolved
  /// The lanes a VERB acts on for a span (R9 #20): a GROUP HEADER stands
  /// for its members.
  ///
  /// #20 took the header's special case out of SELECTION — a header is a
  /// row and a drag selects the rows it drew over. This is the separate,
  /// and separately true, statement that a row's verbs act on what the row
  /// SHOWS: the header band paints its members' key union, so a move that
  /// grabs it moves those keys ("한번에 잡아 이동"). Keeping the two apart
  /// is the whole of #20 — one used to be doing the other's job.
  List<String> _laneVerbTargets(
    List<String> spanLaneIds, {
    List<LayerEffect> effects = const [],
  }) {
    final targets = <String>[];
    void add(String laneId) {
      if (!targets.contains(laneId)) {
        targets.add(laneId);
      }
    }

    for (final laneId in spanLaneIds) {
      if (laneId == transformGroupHeaderLane.laneId) {
        transformLaneDisplayOrder.forEach(add);
        continue;
      }
      final address = parseEffectLaneId(laneId);
      if (address != null && address.parameterId == null) {
        for (final effect in effects) {
          if (effect.id == address.effectId) {
            effectLaneDisplayOrder(effect).forEach(add);
            break;
          }
        }
        continue;
      }
      add(laneId);
    }
    return targets;
  }

  /// The LANE range a verb should act on, or null when the subject is not
  /// a property row (R10 #19).
  ///
  /// A live lane SPAN wins; otherwise the row you are standing on, as a
  /// one-frame span at the playhead. Expressing the standing case as a
  /// span is what makes Add and Delete need no second code path — the
  /// group header's whole-member expansion and the effect-lane branch
  /// come along either way.
  TimelineLaneSelection? get _laneVerbRange {
    final span = laneRangeSelection.value;
    if (span != null) {
      return span;
    }
    if (currentRow case LaneRowAddress(:final layerId, :final laneId)) {
      final frame = _laneVerbFrameFor(layerId);
      return TimelineLaneSelection(
        layerId: layerId,
        laneId: laneId,
        startIndex: frame,
        endIndexExclusive: frame + 1,
      );
    }
    return null;
  }

  /// The transform track a LANE row edits: the CAMERA row's lanes live on
  /// the cut's camera, every other row's on the layer itself.
  ///
  /// R10 R3: the lane-verb family read `layer.transformTrack` flat, so Add
  /// and Delete silently missed the camera row — which only showed once
  /// the Frame ▾ menu became the delete key's home and had to answer for
  /// the lane the marker's context menu used to.
  TransformTrack _laneTransformTrackOf(Layer layer) =>
      layer.kind == LayerKind.camera
      ? (activeCutOrNull?.camera.track ?? layer.transformTrack)
      : layer.transformTrack;

  /// The layer a LANE verb READS and WRITES.
  ///
  /// ★A track-owned SE row answers with the GLOBAL layer, never the cut's
  /// display clone (user, 2026-08-09: **"글로벌 트랙이 메인이고 컷
  /// 타임라인 내부에서는 그걸 알기 쉽게 보여주기만 할 뿐"**). The lane
  /// selection is stated on that same global axis, so a span that runs
  /// past the cut edge still reaches every key it covers — reading the
  /// clone could only ever have touched the keys the current cut happens
  /// to show.
  ///
  /// This is the axis rule the frame-shift verbs already follow
  /// ([_shiftLayerFor], UI-R18 #1), now said once more for the lane
  /// family. R5 #8's window conversion on the way OUT retires with it:
  /// what goes in was global to begin with.
  /// ★And a V TRACK's own lane rows answer with a CARRIER layer — the
  /// track's transform and chain wearing the carrier id, the very shape
  /// the rails already draw those rows with ([_vLaneCarrier]). Without it
  /// the verbs looked the carrier up as a layer, found nothing, and
  /// reported "no keys here": Delete then fell through to the CEL path and
  /// removed the active layer's drawing instead. The commit funnels below
  /// send it home to the track.
  Layer? _laneVerbLayerFor(LayerId layerId) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layerId);
    if (carrierTrackId != null) {
      final track = _trackById(carrierTrackId);
      return track == null
          ? null
          : Layer(
              id: layerId,
              name: 'V',
              frames: const [],
              // No transform of its own any more; the V row's lane carrier
              // exists for the EFFECT chain alone.
              effects: track.effects,
            );
    }
    return isTrackSeLayerId(layerId)
        ? trackSeGlobalLayerById(layerId)
        : _layerById(layerId);
  }

  /// The playhead as [layerId]'s own lanes key it — the frame half of
  /// [_laneVerbLayerFor]. A track-SE row is on the global axis, so the
  /// cut-local cursor has to be translated before it can name a key.
  int _laneVerbFrameFor(LayerId layerId) =>
      _timelineController.currentFrameIndex +
      (isTrackSeLayerId(layerId) ? activeCutGlobalStartFrame : 0);

  void _commitLaneTransformTrack(
    Layer layer,
    TransformTrack track, {
    required String description,
  }) {
    if (layer.kind == LayerKind.camera) {
      updateActiveCutCameraTrack(track, description: description);
      return;
    }
    // A V row's carrier has no transform to go home to any more: the row's
    // lanes are its EFFECT chain alone, so a transform commit here would be
    // writing where nothing reads.
    if (trackIdOfTransformLaneCarrier(layer.id) != null) {
      return;
    }
    // No window conversion: [_laneVerbLayerFor] hands these verbs the
    // GLOBAL layer for a track-SE row, so the track they edited is already
    // on the axis it belongs to. Converting here would shift it twice.
    updateLayerTransformTrack(layer.id, track, description: description);
  }

  /// The lane path's EFFECT commit — the twin of [_commitLaneTransformTrack].
  ///
  /// A funnel rather than three call sites: Add, Delete and Reset all
  /// commit chains read off the same layer, and which axis that layer is
  /// on is exactly the kind of step that gets remembered in two places out
  /// of three.
  void _commitLaneEffects(
    Layer layer,
    List<LayerEffect> effects, {
    required String description,
  }) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layer.id);
    if (carrierTrackId != null) {
      updateTrackEffects(carrierTrackId, effects, description: description);
      return;
    }
    updateLayerEffects(layer.id, effects, description: description);
  }

  /// The lanes a verb may act on for [layer]. The CAMERA row draws only
  /// position/scale/rotation ([timelineLanesForLayer] builds its lanes
  /// without anchor and opacity), so a GROUP-header span — which expands
  /// to every transform lane — must not key two lanes that row has no way
  /// to show, move or delete.
  List<String> _laneVerbTargetsFor(Layer layer, List<String> targets) {
    if (layer.kind != LayerKind.camera) {
      return targets;
    }
    return targets
        .where((laneId) => laneId != 'anchor-point' && laneId != 'opacity')
        .toList();
  }

  /// The value a lane verb freezes at [frameIndex]. The camera's pose does
  /// not live on the camera pseudo-layer — its own transform track is
  /// permanently empty — so reading [layerPoseAtFrame] there froze the
  /// canvas-centre identity pose and snapped the camera mid-move.
  CameraPose _laneResolvedPose(Layer layer, int frameIndex) {
    if (layer.kind != LayerKind.camera) {
      return layerPoseAtFrame(layer, frameIndex);
    }
    final cut = activeCutOrNull;
    if (cut == null) {
      return layerPoseAtFrame(layer, frameIndex);
    }
    return resolveCameraPoseAt(
      camera: cut.camera,
      canvasSize: cut.canvasSize,
      frameIndex: frameIndex,
    );
  }

  /// Removes every key the range covers on every spanned lane — the
  /// mirror of [_createLaneKeysForSelection], one undo. Returns whether
  /// anything was there to remove.
  bool _removeLaneKeysForSelection(TimelineLaneSelection lane) {
    final layer = _laneVerbLayerFor(lane.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return false;
    }
    final targets = _laneVerbTargets(lane.spanLaneIds, effects: layer.effects);
    if (targets.any((laneId) => parseEffectLaneId(laneId) != null)) {
      var effects = layer.effects;
      var changed = false;
      for (final laneId in targets) {
        for (final frame in effectLaneKeyFrames(effects, laneId).toList()) {
          if (!lane.contains(frame)) {
            continue;
          }
          final next = effectsWithLaneKeyRemoved(
            effects,
            laneId: laneId,
            frameIndex: frame,
          );
          if (next != null) {
            effects = next;
            changed = true;
          }
        }
      }
      if (changed) {
        _commitLaneEffects(layer, effects, description: 'Delete keys');
      }
      return changed;
    }
    var track = _laneTransformTrackOf(layer);
    var changed = false;
    for (final laneId in _laneVerbTargetsFor(layer, targets)) {
      for (final frame in transformLaneKeyFrames(track, laneId).toList()) {
        if (!lane.contains(frame)) {
          continue;
        }
        final next = transformTrackWithLaneKeyRemoved(
          track,
          laneId: laneId,
          frameIndex: frame,
        );
        if (next != null) {
          track = next;
          changed = true;
        }
      }
    }
    if (changed) {
      _commitLaneTransformTrack(layer, track, description: 'Delete keys');
    }
    return changed;
  }

  /// The names the LANE RANGE's keys carry — one entry per key, null for an
  /// unnamed one. Empty when the range holds no key at all.
  ///
  /// Both naming gates read this, so "can I name here" and "what do they
  /// already say" cannot disagree about which keys the range covers.
  Set<String?> _laneRangeKeyNames() {
    final lane = _laneVerbRange;
    if (lane == null) {
      return const {};
    }
    final layer = _laneVerbLayerFor(lane.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return const {};
    }
    final targets = _laneVerbTargets(lane.spanLaneIds, effects: layer.effects);
    final names = <String?>{};
    if (targets.any((laneId) => parseEffectLaneId(laneId) != null)) {
      for (final laneId in targets) {
        final address = parseEffectLaneId(laneId);
        final parameterId = address?.parameterId;
        if (address == null || parameterId == null) {
          continue;
        }
        for (final effect in layer.effects) {
          if (effect.id != address.effectId) {
            continue;
          }
          final track = effect.parameters[parameterId]?.track;
          if (track == null) {
            continue;
          }
          for (final entry in track.keys.entries) {
            if (lane.contains(entry.key)) {
              names.add(entry.value.name);
            }
          }
        }
      }
      return names;
    }
    final track = _laneTransformTrackOf(layer);
    for (final laneId in _laneVerbTargetsFor(layer, targets)) {
      final property = transformPropertyOfLaneId(laneId);
      if (property == null) {
        continue;
      }
      for (final frame in transformLaneKeyFrames(track, laneId)) {
        if (lane.contains(frame)) {
          names.add(transformLaneKeyName(track, property, frame));
        }
      }
    }
    return names;
  }

  /// Whether the lane range has a key to name — Edit Instance's gate on a
  /// property row.
  bool get canNameLaneKeys => _laneRangeKeyNames().isNotEmpty;

  /// The name the range's keys AGREE on, or null when they disagree (or
  /// none is named) — what the rename dialog opens with.
  ///
  /// Same rule the group header shows (user 2026-07-30: "내부 이름이 전부
  /// 같으면 그 이름, 다르면 …"), said once so the field and the header
  /// cannot drift.
  String? get laneKeyNameForSelection {
    final names = _laneRangeKeyNames();
    return names.length == 1 ? names.first : null;
  }

  /// Names every key the LANE RANGE covers, on every lane it spans — the
  /// range form of [setLaneKeyName], committed as ONE undo step.
  ///
  /// Scope is [_laneVerbRange]'s, the same one Add and Delete Key take: a
  /// live lane span, or the row you are STANDING on as a one-frame span at
  /// the playhead. Expressing the single key as a one-frame span is what
  /// makes this the ONLY naming path the UI needs (user 2026-08-10:
  /// "선택범위로 통하는 조작이 모두 다른것들이랑 동일한 로직").
  ///
  /// ★The covered keys of ONE lane end up at ONE value, which is the point
  /// rather than a side effect: a name MEANS "same value", so asking for
  /// one name across five keys is asking for exactly that. Lanes stay
  /// separate spaces, so a span across a whole pose leaves Position and
  /// Rotation each with their own single value.
  ///
  /// Returns true when [name] is ALREADY taken OUTSIDE the range and
  /// NOTHING was written — the caller asks ONCE for the whole range and
  /// then calls [linkLaneKeyNamesForSelection].
  bool setLaneKeyNamesForSelection(String? name) =>
      _writeLaneKeyNamesForSelection(name, adopt: false);

  /// Joins [name] across the range, ADOPTING the value it already holds —
  /// the answer to the "합칠까요?" [setLaneKeyNamesForSelection] raises.
  void linkLaneKeyNamesForSelection(String name) =>
      _writeLaneKeyNamesForSelection(name, adopt: true);

  /// The shared body: walks the spanned lanes, and stops at the FIRST lane
  /// whose name is taken unless [adopt] says the user already agreed.
  /// Stopping before any commit is what makes the confirmation honest —
  /// nothing is half-written while the dialog is up.
  bool _writeLaneKeyNamesForSelection(String? name, {required bool adopt}) {
    final lane = _laneVerbRange;
    if (lane == null) {
      return false;
    }
    final layer = _laneVerbLayerFor(lane.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return false;
    }
    final cutId = _editingSession.activeCutId;
    final targets = _laneVerbTargets(lane.spanLaneIds, effects: layer.effects);
    final preferred = _laneVerbFrameFor(lane.layerId);
    final why = name == null ? 'Unname keys' : 'Name keys';

    if (targets.any((laneId) => parseEffectLaneId(laneId) != null)) {
      var effects = layer.effects;
      var changed = false;
      for (final laneId in targets) {
        final address = parseEffectLaneId(laneId);
        final parameterId = address?.parameterId;
        if (address == null || parameterId == null) {
          continue;
        }
        final frames = effectLaneKeyFrames(
          effects,
          laneId,
        ).where(lane.contains).toSet();
        if (frames.isEmpty) {
          continue;
        }
        double? adopted;
        if (name != null && cutId != null) {
          adopted = _cutCommandCoordinator.namedEffectKeyValueInSpace(
            cutId: cutId,
            layerId: layer.id,
            effectId: address.effectId,
            parameterId: parameterId,
            name: name,
            excludeFramesOnSource: frames,
          );
          if (adopted != null && !adopt) {
            return true;
          }
        }
        final next = effectsWithLaneRangeNamed(
          effects,
          laneId: laneId,
          frames: frames,
          name: name,
          adopted: adopted,
          preferredFrame: preferred,
        );
        if (next != null) {
          effects = next;
          changed = true;
        }
      }
      if (changed) {
        _commitLaneEffects(layer, effects, description: why);
      }
      return false;
    }

    var track = _laneTransformTrackOf(layer);
    var changed = false;
    for (final laneId in _laneVerbTargetsFor(layer, targets)) {
      final property = transformPropertyOfLaneId(laneId);
      if (property == null) {
        continue;
      }
      final frames = transformLaneKeyFrames(
        track,
        laneId,
      ).where(lane.contains).toSet();
      if (frames.isEmpty) {
        continue;
      }
      TransformTrack? holder;
      if (name != null) {
        holder = _laneTransformHoldingName(
          layer,
          property,
          name,
          excludeFrames: frames,
        );
        if (holder != null && !adopt) {
          return true;
        }
      }
      final next = transformTrackWithLaneRangeNamed(
        track,
        laneId: laneId,
        frames: frames,
        name: name,
        adoptFrom: holder,
        preferredFrame: preferred,
      );
      if (next != null) {
        track = next;
        changed = true;
      }
    }
    if (changed) {
      _commitLaneTransformTrack(layer, track, description: why);
    }
    return false;
  }

  /// AE's group Reset (R5, user 2026-08-09): puts a GROUP HEADER's members
  /// back to their defaults without deleting a single key.
  ///
  /// Scope is [_laneVerbRange]'s, the same one Add and Delete Key take —
  /// the playhead alone, or a live lane-range selection. What differs is
  /// what a span MEANS here: "선택범위에서 작동하면 선택한 키들 리셋", so a
  /// span resets the keys it covers and authors none, while the playhead
  /// case must write one on an animated lane (nothing else can make the
  /// value THERE the default). An unkeyed lane is left alone either way —
  /// it already sits at its default, and keying it would turn a static
  /// property into an animated one behind the user's back.
  ///
  /// [headerLaneId] names the group: the transform header resets the
  /// transform track, an `fx-group:` header its own effect.
  bool resetLaneGroup(LayerId layerId, String headerLaneId) {
    final layer = _laneVerbLayerFor(layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return false;
    }
    final span = laneRangeSelection.value;
    // A span covering this very group is the only one that scopes the
    // reset: standing elsewhere with a selection alive on another row must
    // not silently retarget it.
    final scoped =
        span != null &&
        span.layerId == layerId &&
        span.spanLaneIds.contains(headerLaneId);
    final frames = scoped
        ? [for (var i = span.startIndex; i < span.endIndexExclusive; i += 1) i]
        : [_laneVerbFrameFor(layerId)];

    if (parseEffectLaneId(headerLaneId) != null) {
      final effects = effectsWithGroupReset(
        layer.effects,
        laneId: headerLaneId,
        frameIndexes: frames,
        keyedFramesOnly: scoped,
      );
      if (effects == null) {
        return false;
      }
      _commitLaneEffects(layer, effects, description: 'Reset group');
      return true;
    }
    if (headerLaneId != transformGroupHeaderLane.laneId) {
      return false;
    }
    final canvasSize = requireActiveCut.canvasSize;
    final next = transformTrackWithGroupReset(
      _laneTransformTrackOf(layer),
      frameIndexes: frames,
      identity: layerIdentityPose(canvasSize),
      defaultAnchorPoint: CanvasPoint(
        x: canvasSize.width / 2,
        y: canvasSize.height / 2,
      ),
      keyedFramesOnly: scoped,
    );
    if (next == null) {
      return false;
    }
    _commitLaneTransformTrack(layer, next, description: 'Reset group');
    return true;
  }

  /// Whether [_laneVerbRange] holds a key to delete.
  bool get _laneVerbRangeHasKeys {
    final lane = _laneVerbRange;
    // The same layer the verb will act on, or the answer is about a
    // different set of keys than the one Delete is about to remove: a
    // track-SE row's clone holds only this cut's, on this cut's numbers,
    // and the span is stated globally.
    final layer = lane == null ? null : _laneVerbLayerFor(lane.layerId);
    if (lane == null || layer == null || isAttachedLayer(layer)) {
      return false;
    }
    final targets = _laneVerbTargetsFor(
      layer,
      _laneVerbTargets(lane.spanLaneIds, effects: layer.effects),
    );
    return targets.any(
      (laneId) => parseEffectLaneId(laneId) != null
          ? effectLaneKeyFrames(layer.effects, laneId).any(lane.contains)
          : transformLaneKeyFrames(
              _laneTransformTrackOf(layer),
              laneId,
            ).any(lane.contains),
    );
  }

  /// value on every unkeyed frame of the range — one undo.
  void _createLaneKeysForSelection(TimelineLaneSelection lane) {
    final layer = _laneVerbLayerFor(lane.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return;
    }
    final targets = _laneVerbTargets(lane.spanLaneIds, effects: layer.effects);
    // R6: an EFFECT-lane selection freezes keys on the effect chain
    // instead — same rule, same single undo.
    if (targets.any((laneId) => parseEffectLaneId(laneId) != null)) {
      var effects = layer.effects;
      var effectsChanged = false;
      for (final laneId in targets) {
        for (
          var frame = lane.startIndex;
          frame < lane.endIndexExclusive;
          frame += 1
        ) {
          if (frame < 0 ||
              effectLaneKeyFrames(effects, laneId).contains(frame)) {
            continue;
          }
          final next = effectsWithLaneKeyToggled(
            effects,
            laneId: laneId,
            frameIndex: frame,
          );
          if (next != null) {
            effects = next;
            effectsChanged = true;
          }
        }
      }
      if (effectsChanged) {
        _commitLaneEffects(layer, effects, description: 'Create keys');
      }
      return;
    }
    var track = _laneTransformTrackOf(layer);
    final isCamera = layer.kind == LayerKind.camera;
    var changed = false;
    // R26 #3: a multi-lane span freezes keys on EVERY spanned lane —
    // still one undo.
    for (final laneId in _laneVerbTargetsFor(layer, targets)) {
      for (
        var frame = lane.startIndex;
        frame < lane.endIndexExclusive;
        frame += 1
      ) {
        if (frame < 0 ||
            transformLaneKeyFrames(track, laneId).contains(frame)) {
          continue;
        }
        final next = transformTrackWithLaneKeyToggled(
          track,
          laneId: laneId,
          frameIndex: frame,
          resolvedPose: _laneResolvedPose(layer, frame),
          resolvedAnchorPoint: isCamera
              ? null
              : layerAnchorPointAtFrame(layer, frame),
          resolvedOpacity: isCamera ? 1 : layerOpacityAtFrame(layer, frame),
        );
        if (next != null) {
          track = next;
          changed = true;
        }
      }
    }
    if (changed) {
      _commitLaneTransformTrack(layer, track, description: 'Create keys');
    }
  }

  void copyFrameAtCurrentFrame() {
    final layer = activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null || !canCopyFrameAtCurrentFrame) {
      return;
    }

    final run = _spliceRunOnActiveRow();
    // 🚨T3 — the clip brings its LENGTH: 「내가 하고싶은건 프레임만 복붙이
    // 아니라 코마까지 포함해서 블록 자체를 복붙한다는 느낌」. What travels is
    // the run of cells, gaps and all, not one cel id that the destination
    // then decides a length for.
    final clip = run == null
        ? null
        : _timelineController.copyRunForLayer(
            layerId: layer.id,
            index: run.index,
            count: run.count,
          );
    final cels = <FrameId>{
      for (final exposure in clip?.exposures.values ?? const <TimelineExposure>[])
        if (exposure.frameId != null) exposure.frameId!,
    };
    _copiedFrame = _CopiedFrameReference(
      layerId: layer.id,
      frameId: frame.id,
      frameName: frame.name,
      clip: clip,
      cels: [
        for (final cel in layer.frames)
          if (cels.contains(cel.id)) cel,
      ],
    );
    notifyListeners();
  }

  /// 🚨T3 신설 — 잘라내기: the same lift the paste does, with the clip going
  /// to the clipboard instead of a row.
  ///
  /// 유저 확정 2026-08-13: 「잘라내기 버튼을 공용 알약에 신설 — 복사 버튼
  /// 왼쪽. 복사=원본 남기고 클립 저장 · 잘라내기=원본 지우고 클립 저장」.
  ///
  /// ★It is literally copy followed by the lift half of [spliceTimeline],
  /// which is why it needs no rules of its own.
  bool get canCutRunAtCurrentFrame => canCopyFrameAtCurrentFrame;

  void cutRunAtCurrentFrame() {
    final layer = activeLayer;
    if (layer == null || !canCutRunAtCurrentFrame) {
      return;
    }
    final run = _spliceRunOnActiveRow();
    if (run == null) {
      return;
    }
    copyFrameAtCurrentFrame();
    _timelineController.spliceRunsForLayers(
      runs: [
        (
          layerId: layer.id,
          index: run.index,
          liftCount: run.count,
          clip: null,
          bornFrames: const <Frame>[],
        ),
      ],
      description: 'Cut frames',
    );
    clearFrameRangeSelection();
    notifyListeners();
  }

  /// 🚨T2 복제 — 유저 확정 2026-08-13: 「복붙은 **선택**하고 붙여넣기가
  /// 기본이지만, **복제는 현재 액티브인 대상**을 상대로 적용하는 것」.
  ///
  /// ⛔So it is NOT on the shared pill: that pill's verbs ask what is
  /// selected, and this one deliberately does not. It lives inside the noun
  /// it copies, beside the layer's pair and the cut's.
  ///
  /// ★The logic is copy-then-paste in one press — 「로직은 복붙 통합 버튼과
  /// **똑같고** 그것을 독립복제 / 링크복제로 나눈 버전」 — so it goes through
  /// the same splice everything else does.
  ///
  /// ⚠️It lands at the block's END, not at the playhead. Standing in the
  /// middle of a hold and inserting there would split the block and put the
  /// copy INSIDE it, which for an independent duplicate is visibly wrong
  /// (`A P P P A A`) and for a linked one is only right by accident.
  ///
  /// ⛔The CLIPBOARD is not touched. A duplicate that clobbered what you had
  /// copied would be a second verb hiding inside the first.
  bool get canDuplicateActiveBlock {
    final layer = activeLayer;
    if (layer == null || !layerKindHoldsDrawings(layer.kind)) {
      return false;
    }
    return coveringDrawingBlockAt(
          layer.timeline,
          _timelineController.currentFrameIndex,
        ) !=
        null;
  }

  void duplicateActiveBlock({required bool linked}) {
    final layer = activeLayer;
    if (layer == null || !canDuplicateActiveBlock) {
      return;
    }
    final block = coveringDrawingBlockAt(
      layer.timeline,
      _timelineController.currentFrameIndex,
    );
    if (block == null) {
      return;
    }
    final clip = _timelineController.copyRunForLayer(
      layerId: layer.id,
      index: block.startIndex,
      count: block.endIndexExclusive - block.startIndex,
    );
    final bornFrames = <Frame>[];
    var placed = clip;
    if (!linked) {
      final minted = <FrameId, FrameId>{};
      final exposures = <int, TimelineExposure>{};
      for (final entry in clip.exposures.entries) {
        final sourceId = entry.value.frameId;
        if (sourceId == null) {
          continue;
        }
        final newId = minted.putIfAbsent(sourceId, () {
          final id = _mintFrameId(layer.id);
          final source = layer.frames
              .where((frame) => frame.id == sourceId)
              .firstOrNull;
          if (source != null) {
            // Unnamed, for the reason the independent paste is: a name is a
            // cel's identity inside the layer, and two cels claiming one is
            // a state no rename could produce.
            bornFrames.add(
              duplicateFrameContent(
                frame: source,
                newFrameId: id,
              ).copyWith(name: null),
            );
          }
          return id;
        });
        exposures[entry.key] = entry.value.copyWith(frameId: newId);
      }
      placed = TimelineClipRow(exposures: exposures, length: clip.length);
    }
    _timelineController.spliceRunsForLayers(
      runs: [
        (
          layerId: layer.id,
          index: block.endIndexExclusive,
          liftCount: 0,
          clip: placed,
          bornFrames: bornFrames,
        ),
      ],
      description: linked ? 'Link duplicate frames' : 'Duplicate frames',
    );
    notifyListeners();
  }

  /// WHERE a copy, cut or paste acts on the active row, in COMMIT keys.
  ///
  /// ★The one place the two halves of 「N칸을 들어내고 클립을 넣는다」 get
  /// their N: a live selection says its own range, and with none the verb
  /// means the block under the playhead. Copy, cut and paste all ask this,
  /// so they cannot disagree about what "the run" is.
  ///
  /// ⚠️The ROW is the active layer's alone. T3's multi-row anchoring
  /// (「선택의 첫 행을 현재 행에 맞춘다」) needs a rail-display-order source
  /// the session does not have — [TimelineController.spliceRunsForLayers]
  /// already takes a list so the extension is additive, but nothing here
  /// pretends to do it yet.
  ({int index, int count})? _spliceRunOnActiveRow() {
    final layer = activeLayer;
    if (layer == null) {
      return null;
    }
    final selection = frameRangeSelection.value;
    if (selection != null && selection.coversLayer(layer.id)) {
      return (
        index: _commitBlockStart(layer.id, selection.startIndex),
        count: selection.lengthFrames,
      );
    }
    final index = _timelineController.currentFrameIndex;
    final covering = coveringDrawingBlockAt(layer.timeline, index);
    if (covering == null) {
      return (index: index, count: 1);
    }
    return (
      index: covering.startIndex,
      count: covering.endIndexExclusive - covering.startIndex,
    );
  }

  /// ㉕: the copied cel's content here, as a cel of its own.
  ///
  /// 🚨★★★ 유저 #4 (2026-08-14): 「프레임블록 복사하고 **다른 애니메이션행 등
  /// 이동가능한행에 붙혀넣기 불가.** 이런 붙혀넣기같은건 **같은 섹션 등
  /// 허용되는곳이라면 가능하도록**」.
  ///
  /// ⛔It used to delegate to the LINKED gate, which asks 「is that cel in
  /// THIS row」 — and for a link that question is the right one, because a
  /// link means *the same cel* and a cel belongs to a layer. This verb
  /// MINTS a cel, so the question does not apply to it: it asks whether
  /// this row can hold an authored drawing at all, which is what
  /// 「허용되는곳」 names.
  ///
  /// ⚠️Reachable only because the clipboard carries its cels by value
  /// (유저 #3's fix) — a cross-row paste has no source in `layer.frames` by
  /// definition, so this and that are one change made in two steps.
  ///
  /// ⛔The stand-downs are the AUTHORING ones and are shared with
  /// [canCreateDrawingAtCurrentFrame] deliberately; what is NOT shared is
  /// its block-start refusal, which exists because there is nothing there
  /// to divide — a paste inserts rather than divides.
  bool get canPasteIndependentFrameAtCurrentFrame {
    final layer = activeLayer;
    if (layer == null || _copiedFrame == null) {
      return false;
    }
    if (!layerKindHoldsDrawings(layer.kind) ||
        // SYNCED attach rows own no timeline of their own.
        isSyncedAttachedLayer(layer) ||
        // A reference row's picture comes from the library.
        layer.mediaReference != null ||
        // An IMAGE row holds ONE cel by definition.
        layerKindHoldsSingleCel(layer.kind)) {
      return false;
    }
    return _timelineController.currentFrameIndex >= 0;
  }

  void pasteIndependentFrameAtCurrentFrame() {
    final layer = activeLayer;
    final copiedFrame = _copiedFrame;
    if (layer == null ||
        copiedFrame == null ||
        !canPasteIndependentFrameAtCurrentFrame) {
      return;
    }
    _pasteRun(layer: layer, copied: copiedFrame, independent: true);
  }

  void pasteLinkedFrameAtCurrentFrame() {
    final layer = activeLayer;
    final copiedFrame = _copiedFrame;
    if (layer == null ||
        copiedFrame == null ||
        !canPasteLinkedFrameAtCurrentFrame) {
      return;
    }
    _pasteRun(layer: layer, copied: copiedFrame, independent: false);
  }

  /// 🚨★★★ BOTH pastes, because they differ in ONE thing.
  ///
  /// 유저 확정: 「링크 붙여넣기 = 겸용(링크) 생성 · 독립 붙여넣기 = 그냥 복제」.
  /// That is the only difference — which cel the exposures end up pointing
  /// at — so the PLACEMENT is written once. Where the two used to share a
  /// private helper they now share the splice itself, and 「선택이 있으면
  /// 갈아끼우기, 없으면 끼워넣기」 is the same sentence for both.
  ///
  /// ⚠️A cel is minted PER SOURCE CEL, not per cell: a clip holding one
  /// drawing exposed three times pastes as one new drawing exposed three
  /// times. Minting per cell would quietly unlink a block from itself.
  void _pasteRun({
    required Layer layer,
    required _CopiedFrameReference copied,
    required bool independent,
  }) {
    final clip =
        copied.clip ??
        TimelineClipRow(
          exposures: {0: TimelineExposure.drawing(copied.frameId, length: 1)},
          length: 1,
        );
    final run = _spliceRunOnActiveRow();
    // ⛔A selection REPLACES what it covers; with none, nothing comes out.
    // 「뭘 선택하든 덮어써버리면 선택범위를 조절하는 의미가 통째로 사라지잖아」
    final selection = frameRangeSelection.value;
    final replacing = selection != null && selection.coversLayer(layer.id);
    final index = replacing
        ? run!.index
        : _timelineController.currentFrameIndex;
    final liftCount = replacing ? run!.count : 0;

    final bornFrames = <Frame>[
      // A 잘라내기 orphaned the cels it lifted, so the layer no longer holds
      // them; the clipboard does. Bringing back the SAME id is what makes
      // cut-then-paste-back a move rather than a deletion — and re-adding
      // only what is missing keeps a plain copy from duplicating anything.
      if (!independent)
        for (final cel in copied.cels)
          if (!layer.frames.any((frame) => frame.id == cel.id)) cel,
    ];
    var placed = clip;
    if (independent) {
      final minted = <FrameId, FrameId>{};
      final exposures = <int, TimelineExposure>{};
      for (final entry in clip.exposures.entries) {
        final sourceId = entry.value.frameId;
        if (sourceId == null) {
          continue;
        }
        // 🚨THE CLIPBOARD IS THE SECOND PLACE TO LOOK, and after a 잘라내기
        // it is the ONLY one (유저 #3, 2026-08-14).
        //
        // A cut orphans the cels it lifted, so they are gone from
        // `layer.frames` by the time this runs. Reading only the layer found
        // nothing, minted an id anyway, and authored an exposure pointing at
        // a cel that does not exist: a white block, `?` where the name goes,
        // and every verb that resolves the cel refusing — 「완전한 버그상태」.
        // The clipboard has carried these cels since the splice landed; only
        // the LINKED branch was reading them.
        final source =
            layer.frames.where((frame) => frame.id == sourceId).firstOrNull ??
            copied.cels.where((frame) => frame.id == sourceId).firstOrNull;
        if (source == null) {
          // ⛔An exposure with no cel behind it is the damage itself. Drop
          // the cell rather than author a reference nothing can resolve —
          // an empty cell is a state the row already knows how to be.
          continue;
        }
        final newId = minted.putIfAbsent(sourceId, () {
          // 🚨Through the MINT. `_nextFrameId` reads the sequence without
          // advancing it, so two independent pastes inside one clock tick
          // would come out as the SAME cel — which is not "two cels that
          // look alike", it is one cel exposed twice, and the import round
          // already paid for that lesson once.
          final id = _mintFrameId(layer.id);
          // 🚨IT COMES OUT UNNAMED, and that is the point rather than an
          // omission. A cel's name is its IDENTITY inside the layer — the
          // rename path REFUSES a duplicate and offers to merge instead,
          // which is this app's 「같은 이름 = 같은 그림」 rule. Carrying the
          // source's name would assert the very link this verb exists to
          // avoid, and do it behind that dialog's back.
          bornFrames.add(
            duplicateFrameContent(
              frame: source,
              newFrameId: id,
            ).copyWith(name: null),
          );
          return id;
        });
        exposures[entry.key] = entry.value.copyWith(frameId: newId);
      }
      placed = TimelineClipRow(exposures: exposures, length: clip.length);
    }

    _timelineController.spliceRunsForLayers(
      runs: [
        (
          layerId: layer.id,
          index: index,
          liftCount: liftCount,
          clip: placed,
          bornFrames: bornFrames,
        ),
      ],
      description: independent ? 'Paste frames' : 'Paste linked frames',
    );
    if (replacing) {
      clearFrameRangeSelection();
    }
    notifyListeners();
  }

  /// The timesheet "X here" — ⛔NOT the clipboard's cut.
  ///
  /// 🚨T3 rename: this was `cutExposureAtCurrentFrame` while 「잘라내기」 was
  /// a word nothing in the app used. Now that [cutRunAtCurrentFrame] exists,
  /// two different verbs would answer to "cut". The UI never said 「cut」
  /// here — the button is `×` (`blank-exposure-button`, tooltip `tlBlankX`)
  /// — so the code name follows the button and the new verb takes the word
  /// the user gave it.
  void blankExposureAtCurrentFrame() {
    final layer = activeLayer;
    if (layer == null || !canBlankExposureAtCurrentFrame) {
      return;
    }

    _timelineController.cutExposureForLayer(layerId: layer.id);
    notifyListeners();
  }

  /// ⚠️Formats an id from the CURRENT sequence — it does not advance it.
  /// Call [_mintFrameId] unless you have just incremented `_frameSequence`
  /// yourself. The wall clock in here is decoration, not identity: its
  /// resolution on Windows is coarser than a tight mint loop, so two ids
  /// made in the same tick are equal, and equal frame ids are ONE drawing.
  String _nextFrameId(LayerId layerId) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return 'ui-frame-${layerId.value}-$timestamp-$_frameSequence';
  }

  /// The toolbar +/- buttons are one-frame comma adjustments of the
  /// selected block's end edge (the same op the drag grips use).
  void increaseSelectedExposure() => _shiftSelectedExposureEnd(1);

  void decreaseSelectedExposure() => _shiftSelectedExposureEnd(-1);

  void _shiftSelectedExposureEnd(int delta) {
    final layer = activeLayer;
    if (layer == null) {
      return;
    }
    final block = _timelineController.blockForLayerAt(layer: layer);
    if (block == null) {
      return;
    }

    _timelineController.shiftExposureEdge(
      layerId: layer.id,
      blockStartIndex: block.startIndex,
      edge: TimelineBlockEdge.end,
      delta: delta,
    );
    notifyListeners();
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
  final ValueNotifier<TimelineDragPreview?> dragPreview =
      ValueNotifier<TimelineDragPreview?>(null);

  Layer? _edgeDragBefore;
  TimelineBlockEdge? _edgeDragEdge;
  int? _edgeDragBlockStart;

  /// UI-R17 #3/#8: when the dragged edge belongs to a block INSIDE the
  /// frame range selection, the drag retimes EVERY selected block on
  /// EVERY spanned layer together (null = single-block drag).
  Map<LayerId, List<int>>? _edgeDragBulkStartsByLayer;
  Map<LayerId, Layer>? _edgeDragBulkBefore;
  List<({Layer before, Layer after})>? _edgeDragBulkEdits;

  /// The drag's current result (GLOBAL layer for track SE): [dragPreview]
  /// carries the DISPLAY form, so the commit reads this instead.
  Layer? _edgeDragAfter;

  /// Non-null while a track-SE drag is in flight — previews window through
  /// it before publishing.
  TrackSeWindow? _edgeDragWindow;

  /// Non-null while the dragged (or bulk-spanned) row is a cut-owned
  /// STORYBOARD row (feedback #9): its stored extent and its cut's length
  /// are one thing, so a comma that moves the row's end moves the cut's
  /// end with it — previewed together, committed as ONE undo step.
  ({
    CutId cutId,
    LayerId layerId,
    int beforeDuration,
    int beforeRowEnd,
    CutId? nextCutId,
    int nextBeforeGap,
  })?
  _edgeDragCutSync;

  /// The synced cut resize the release commits (null while the row's end
  /// has not moved). Fields, never the preview channel: a consumer
  /// clearing [dragPreview] mid-drag must not void the commit.
  Map<CutId, int>? _edgeDragAfterDurations;
  Map<CutId, int>? _edgeDragAfterGaps;

  /// Where [layer]'s stored row ends — the cut-length twin the sync rule
  /// keeps the cut's duration equal to.
  int _storedRowEndOf(Layer layer) {
    var end = 0;
    for (final entry in layer.timeline.entries) {
      if (!entry.value.isDrawing || entry.value.ghost) {
        continue;
      }
      final blockEnd = entry.key + (entry.value.length ?? 1);
      if (blockEnd > end) {
        end = blockEnd;
      }
    }
    return end;
  }

  /// Snapshots the cut-sync half of a storyboard row's comma drag.
  ({
    CutId cutId,
    LayerId layerId,
    int beforeDuration,
    int beforeRowEnd,
    CutId? nextCutId,
    int nextBeforeGap,
  })
  _cutSyncSnapshotFor({required Cut cut, required Layer row}) {
    final next = _nextCutInTrack(cut.id);
    return (
      cutId: cut.id,
      layerId: row.id,
      beforeDuration: cut.duration,
      beforeRowEnd: _storedRowEndOf(row),
      nextCutId: next?.id,
      nextBeforeGap: next?.leadingGapFrames ?? 0,
    );
  }

  /// The synced durations/gaps for the row's end having moved to
  /// [afterRowEnd], or null when it has not moved.
  ///
  /// The cut ENDS WHERE THE ROW ENDS — that is what "always synced" means,
  /// and taking it literally is also what makes the floor structural: a
  /// row's end is its last block's end, so the duration can never land
  /// before the last division (the `minimumCutDurationFor` guarantee the
  /// plain trim clamps for by hand). Deriving the duration from a DELTA
  /// instead would decouple the two the moment a stored row end differs
  /// from the cut duration, and then the row's last comma clamps at one
  /// frame while the duration keeps absorbing the whole delta.
  ({Map<CutId, int> durations, Map<CutId, int> gaps})? _cutSyncResizeFor(
    Layer afterRow,
  ) {
    final sync = _edgeDragCutSync;
    if (sync == null) {
      return null;
    }
    final afterRowEnd = _storedRowEndOf(afterRow);
    // Nothing moved on the row = nothing to sync (a drag that never left
    // its frame must not snap a mismatched pair on its own).
    if (afterRowEnd == sync.beforeRowEnd) {
      return null;
    }
    // The structural floor above holds when the sync row IS the
    // storyboard row. With a second covering kind (image) able to anchor
    // the sync, the storyboard row's divisions are somebody else's data —
    // clamp to their floor explicitly so shrinking through the IMAGE row
    // can never strand a division outside the cut.
    //
    // Whichever row holds the divisions, the floor must be read off the
    // form THIS DRAG is previewing, not off the repository's: the drag
    // never writes mid-gesture, so a repository read answers about the row
    // as it was when the pointer went down. Reading a stale floor against a
    // live row end is `max()` comparing two different rows, and it pinned
    // the duration above the row's end — the committed desync the user hit,
    // invisible on the strip (whose last cell stretches to the duration) and
    // a hole in the timeline (which paints the stored blocks).
    //
    // On the storyboard row this now collapses: a previewed row's end is its
    // last block's end, so `floor <= afterRowEnd` always and the duration
    // simply follows the row.
    final syncedCut = cutById(sync.cutId);
    final divisionRow = syncedCut == null
        ? null
        : storyboardLayerForCut(syncedCut);
    final floor = divisionRow == null
        ? 1
        : minimumCutDurationForStoryboardRow(
            divisionRow.id == afterRow.id ? afterRow : divisionRow,
          );
    final duration = math.max(floor, afterRowEnd);
    return (
      durations: {sync.cutId: duration},
      gaps: {
        // The FOLLOWING cut rides the cut's end, so its gap answers to how
        // far that end actually moved — not to how far the row's did.
        ?sync.nextCutId: _followingGapAfterEndMove(
          baseGap: sync.nextBeforeGap,
          growth: duration - sync.beforeDuration,
        ),
      },
    );
  }

  /// Starts the strip's trailing-edge drag on [cut]'s storyboard row: the
  /// LAST cell's comma, with the cut's length riding it (feedback #9 — the
  /// cut block's last edge is the ROW's edge when the row exists). Joins
  /// the ordinary exposure comma machinery, so the strip, the timeline row
  /// and the X-sheet are one verb.
  bool _beginStoryboardLastCommaDrag(Cut cut, Layer row) {
    int? lastKey;
    for (final entry in row.timeline.entries) {
      if (entry.value.isDrawing && !entry.value.ghost) {
        lastKey = entry.key;
      }
    }
    if (lastKey == null) {
      return false;
    }
    _seedStoryboardCommaDrag(cut, row, lastKey);
    return true;
  }

  /// Seeds the comma machinery for a drag on [row]'s block keyed
  /// [blockKey], with [cut]'s length riding the row end (feedback #9).
  ///
  /// Every field the comma machinery reads, set from scratch. A press
  /// that never moves commits whatever _edgeDragAfter holds, so a value
  /// left by an earlier drag would land on release without the pointer
  /// ever having asked for it.
  void _seedStoryboardCommaDrag(Cut cut, Layer row, int blockKey) {
    _clearEdgeDragFields();
    _edgeDragBefore = row;
    _edgeDragEdge = TimelineBlockEdge.end;
    _edgeDragBlockStart = blockKey;
    _edgeDragCutSync = _cutSyncSnapshotFor(cut: cut, row: row);
  }

  /// Every field a comma drag reads, back to nothing.
  ///
  /// The reason is above: a press that never moves commits whatever
  /// `_edgeDragAfter` holds, so a value an earlier drag left behind lands
  /// on release without the pointer ever asking for it.
  ///
  /// It lives HERE rather than being spelled out at each entry point
  /// because the two entry points had drifted — the storyboard's seed
  /// cleared all of them and [beginExposureEdgeDrag] cleared some, which
  /// is the shape of thing that is latent until an unrelated round adds a
  /// path where the terminators do not run.
  void _clearEdgeDragFields() {
    _edgeDragBefore = null;
    _edgeDragEdge = null;
    _edgeDragBlockStart = null;
    _edgeDragAfter = null;
    _edgeDragWindow = null;
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    _edgeDragBulkEdits = null;
    _edgeDragAfterDurations = null;
    _edgeDragAfterGaps = null;
    _edgeDragCutSync = null;
  }

  /// Starts a comma drag on the block keyed [blockStartIndex] (cut-local)
  /// of [cutId]'s storyboard row — an INNER panel's trailing edge on the
  /// strip. The edge unification: every trailing edge on a storyboard row
  /// is the SAME comma verb, so the panel's comma resizes, the later
  /// panels ripple along glued, and the cut's length rides the row end
  /// (feedback #9) — where the retired division verb moved a boundary and
  /// pinned the length. Returns false when there is no such drawing block.
  ///
  /// Any cut's panels drag, not only the active cut's: the row is read
  /// through the cut, which is why this does NOT go through
  /// [beginExposureEdgeDrag] — that path resolves the layer and the cut
  /// sync through the ACTIVE cut and would sync the wrong one.
  bool beginStoryboardCommaDrag({
    required CutId cutId,
    required int blockStartIndex,
  }) {
    final cut = cutById(cutId);
    final row = cut == null ? null : storyboardLayerForCut(cut);
    final entry = row?.timeline[blockStartIndex];
    // A negative key is junk data the coverage rule merely tolerates
    // (folded onto frame 0 for display) — resizing it would throw in the
    // comma shift's before-zero guard mid-drag, so refuse at begin.
    if (cut == null ||
        row == null ||
        entry == null ||
        !entry.isDrawing ||
        entry.ghost ||
        blockStartIndex < 0) {
      _cutEdgeDragVerb = null;
      return false;
    }
    _seedStoryboardCommaDrag(cut, row, blockStartIndex);
    // Joins the cut-edge continuations ([updateCutEdgeDrag] and friends):
    // the strip's grips share one set of hooks, and which verb a drag
    // belongs to is the session's to remember, not the host's.
    _cutEdgeDragVerb = _CutEdgeDragVerb.comma;
    return true;
  }

  /// Starts a comma drag on [edge] of the block starting at
  /// [blockStartIndex] (as DISPLAYED — cut-local); returns false when
  /// there is no such block. Instruction rows join the same pipeline —
  /// their spans live on Layer.instructions and shift without ripple.
  /// Track-SE rows convert to the global axis here; a spill-in block's
  /// start edge is rejected (its real start lives in an earlier cut).
  /// Track-global hosts (the storyboard SE strips) pass
  /// [blockStartIsGlobal] with TRUE global starts — any cut's block drags
  /// there (UI-R7 #5), no window conversion, no spill synthesis.
  bool beginExposureEdgeDrag({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    bool blockStartIsGlobal = false,
  }) {
    // SYNCED attach rows own no timing — no comma grips (the BASE's
    // grips move both, W5); free attach rows drag like normal (UI-R21).
    if (_isSyncedAttachedLayerId(layerId)) {
      return false;
    }
    // From scratch, the way the storyboard's seed already did it. The two
    // entry points set overlapping halves of the same field set, and only
    // one of them cleared the rest.
    _clearEdgeDragFields();
    if (isTrackSeLayerId(layerId)) {
      final global = trackSeGlobalLayerById(layerId);
      if (global == null) {
        return false;
      }
      final window = trackSeWindow;
      if (!blockStartIsGlobal &&
          edge == TimelineBlockEdge.start &&
          window.isSpillInStart(global, blockStartIndex)) {
        return false;
      }
      final globalStart = blockStartIsGlobal
          ? blockStartIndex
          : window.globalBlockStartFor(global, blockStartIndex);
      if (!(global.timeline[globalStart]?.isDrawing ?? false)) {
        return false;
      }
      _edgeDragBefore = global;
      _edgeDragEdge = edge;
      _edgeDragBlockStart = globalStart;
      _edgeDragWindow = window;
      _edgeDragCutSync = null;
      // SE rows join the selection bulk (UI-R18 #1) — display-local
      // starts only (the storyboard's global-keyed grips stand down).
      if (!blockStartIsGlobal) {
        _captureEdgeBulk(layerId, blockStartIndex, isDrawingBlock: true);
        // The bulk can reach DOWN to the cut's storyboard row, and that row
        // brings its cut's length with it wherever the drag was anchored
        // (feedback #9). The anchor's own kind must not be what decides:
        // an SE-anchored bulk used to retime the row and leave the cut
        // behind, which is the "drawing outside its cut" state this round
        // exists to make unreachable.
        _captureEdgeDragCutSync(null);
      }
      return true;
    }

    final layer = _layerById(layerId);
    if (layer == null) {
      return false;
    }
    final isInstructionSpan =
        layer.kind == LayerKind.instruction &&
        layer.instructions.containsKey(blockStartIndex);
    final isDrawingBlock =
        layerKindHoldsDrawings(layer.kind) &&
        (layer.timeline[blockStartIndex]?.isDrawing ?? false);
    if (!isInstructionSpan && !isDrawingBlock) {
      return false;
    }

    _edgeDragBefore = layer;
    _edgeDragEdge = edge;
    _edgeDragBlockStart = blockStartIndex;
    // Dragging an edge inside the selection retimes the WHOLE selection
    // (UI-R17 #3/#8) — every selected block on every spanned layer
    // follows the delta live, one undo step on release.
    _captureEdgeBulk(layerId, blockStartIndex, isDrawingBlock: isDrawingBlock);
    _captureEdgeDragCutSync(layer);
    return true;
  }

  /// Snapshots the cut-length half of an exposure comma drag (feedback #9).
  ///
  /// A storyboard row ANYWHERE in the drag brings its cut's length along —
  /// whether it is the row the pointer grabbed ([anchor]) or one the bulk
  /// selection reaches. Both entry paths call this so the anchor's kind
  /// cannot be what decides whether the pair stays synced.
  void _captureEdgeDragCutSync(Layer? anchor) {
    final bulkBefore = _edgeDragBulkBefore;
    Layer? syncRow;
    if (bulkBefore != null) {
      for (final candidate in bulkBefore.values) {
        if (layerKindCoversWithoutGaps(candidate.kind)) {
          syncRow = candidate;
          break;
        }
      }
    } else if (anchor != null && layerKindCoversWithoutGaps(anchor.kind)) {
      syncRow = anchor;
    }
    final activeId = activeCutId;
    final activeCut = syncRow == null || activeId == null
        ? null
        : cutById(activeId);
    _edgeDragCutSync = syncRow == null || activeCut == null
        ? null
        : _cutSyncSnapshotFor(cut: activeCut, row: syncRow);
  }

  /// Captures the bulk-retime set when the dragged edge sits inside the
  /// live selection (UI-R17 #3 → UI-R18 #1: SE rows join through the
  /// commit-key seam — starts and before-layers are COMMIT forms).
  void _captureEdgeBulk(
    LayerId layerId,
    int displayBlockStart, {
    required bool isDrawingBlock,
  }) {
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    final selection = frameRangeSelection.value;
    if (!isDrawingBlock ||
        selection == null ||
        !selection.coversLayer(layerId) ||
        !selection.contains(displayBlockStart)) {
      return;
    }
    final startsByLayer = <LayerId, List<int>>{};
    final beforeByLayer = <LayerId, Layer>{};
    for (final id in selection.spanLayerIds) {
      // SYNCED attach rows never join a bulk retime: their commit form is
      // the DISPLAY CLONE, and committing it would write the derived
      // timeline onto the stored-empty row (the mirror follows the base's
      // retime by derivation anyway). Id-gated — the synced-block UI
      // stopped marking mirror entries ghost, so the non-ghost block scan
      // below no longer excludes them.
      if (_isSyncedAttachedLayerId(id)) {
        continue;
      }
      final display = _rangeLayerById(id);
      final commit = _commitLayerById(id);
      if (display == null || commit == null) {
        continue;
      }
      final starts = _selectionBlockStarts(
        display,
        selection.startIndex,
        selection.endIndexExclusive,
      );
      if (starts.isEmpty) {
        continue;
      }
      startsByLayer[id] = [
        for (final start in starts) _commitBlockStart(id, start),
      ];
      beforeByLayer[id] = commit;
    }
    final multiBlock =
        startsByLayer.length > 1 || (startsByLayer[layerId]?.length ?? 0) > 1;
    if (multiBlock) {
      _edgeDragBulkStartsByLayer = startsByLayer;
      _edgeDragBulkBefore = beforeByLayer;
    }
  }

  /// A span's real (non-ghost) drawing-block start keys on [layer], in
  /// order. Axis-free on purpose: the caller states the span in whichever
  /// axis its layer is keyed by, which is what lets the cut-local and the
  /// track-global selections share this.
  List<int> _selectionBlockStarts(
    Layer layer,
    int startIndex,
    int endIndexExclusive,
  ) => [
    for (final entry in layer.timeline.entries)
      if (entry.key >= startIndex &&
          entry.key < endIndexExclusive &&
          entry.value.isDrawing &&
          !entry.value.ghost)
        entry.key,
  ];

  Layer _edgeDraggedLayer({
    required Layer before,
    required int blockStart,
    required TimelineBlockEdge edge,
    required int delta,
  }) {
    if (before.kind == LayerKind.instruction) {
      final shifted = instructionMapWithEdgeShifted(
        before.instructions,
        spanStartIndex: blockStart,
        startEdge: edge == TimelineBlockEdge.start,
        delta: delta,
      );
      return shifted == null ? before : before.copyWith(instructions: shifted);
    }
    return _timelineController.shiftedLayerForEdge(
          layer: before,
          blockStartIndex: blockStart,
          edge: edge,
          delta: delta,
        ) ??
        before;
  }

  /// Applies the drag's current cumulative frame delta as a live preview
  /// on [dragPreview] — the repository is NOT touched.
  void updateExposureEdgeDrag(int cumulativeDelta) {
    final before = _edgeDragBefore;
    final edge = _edgeDragEdge;
    final blockStart = _edgeDragBlockStart;
    if (before == null || edge == null || blockStart == null) {
      return;
    }

    // Bulk selection retime (UI-R17 #3/#8): the edge delta becomes a
    // LENGTH delta on every selected block of every spanned layer (end
    // edge: +delta, start edge: dragging right shrinks); the ripple
    // packs/pushes downstream per layer. One composite undo on release.
    final bulkStarts = _edgeDragBulkStartsByLayer;
    final bulkBefore = _edgeDragBulkBefore;
    if (bulkStarts != null && bulkBefore != null) {
      final lengthDelta = edge == TimelineBlockEdge.end
          ? cumulativeDelta
          : -cumulativeDelta;
      final edits = <({Layer before, Layer after})>[];
      final previews = <LayerId, Layer>{};
      for (final entry in bulkStarts.entries) {
        final beforeLayer = bulkBefore[entry.key];
        if (beforeLayer == null) {
          continue;
        }
        final after = _timelineController.retimedLayerForBlocks(
          layer: beforeLayer,
          newLengthByStart: {
            for (final start in entry.value)
              if (beforeLayer.timeline[start]?.isDrawing ?? false)
                start: beforeLayer.timeline[start]!.length! + lengthDelta,
          },
        );
        if (after != null && after != beforeLayer) {
          edits.add((before: beforeLayer, after: after));
          // Track-SE rows preview in their DISPLAY form (cut-local axis);
          // the commit keeps the global form (UI-R18 #1 seam).
          previews[entry.key] = isTrackSeLayerId(entry.key)
              ? trackSeWindow.displayLayer(after)
              : after;
        }
      }
      _edgeDragBulkEdits = edits.isEmpty ? null : edits;
      // A storyboard row in the bulk drags its cut's length along
      // (feedback #9) — one preview, one release.
      ({Map<CutId, int> durations, Map<CutId, int> gaps})? resize;
      final sync = _edgeDragCutSync;
      if (sync != null) {
        for (final edit in edits) {
          if (edit.after.id == sync.layerId) {
            resize = _cutSyncResizeFor(edit.after);
            break;
          }
        }
      }
      _edgeDragAfterDurations = resize?.durations;
      _edgeDragAfterGaps = resize?.gaps;
      dragPreview.value = previews.isEmpty
          ? null
          : resize != null
          ? CutTrimDragPreview(
              previewDurations: resize.durations,
              previewGaps: resize.gaps,
              previewLayers: previews,
            )
          : previews.length == 1
          ? ExposureEdgeDragPreview(previewLayer: previews.values.single)
          : BlockMoveDragPreview(previewLayers: previews);
      return;
    }

    final after = _edgeDraggedLayer(
      before: before,
      blockStart: blockStart,
      edge: edge,
      delta: cumulativeDelta,
    );
    // No notifyEditActivity here: composites self-validate against the
    // committed edit, the drag-end warm request re-renders what changed,
    // and the idle gate's REAL-time delay would leave timers pending under
    // the fake test clock.
    _edgeDragAfter = after == before ? null : after;
    // A storyboard row's comma moves its cut's end with it (feedback #9):
    // the resize previews and commits WITH the row, never beside it.
    final resize = after == before ? null : _cutSyncResizeFor(after);
    _edgeDragAfterDurations = resize?.durations;
    _edgeDragAfterGaps = resize?.gaps;
    if (resize != null) {
      dragPreview.value = CutTrimDragPreview(
        previewDurations: resize.durations,
        previewGaps: resize.gaps,
        previewLayers: {after.id: after},
      );
      return;
    }
    // Track-SE drags: the preview channel carries the DISPLAY form (the
    // row gates render cut-local clones) PLUS the global form for the
    // storyboard's track-global strips (UI-R7 #7); the commit uses
    // _edgeDragAfter.
    final window = _edgeDragWindow;
    dragPreview.value = after == before
        ? null
        : ExposureEdgeDragPreview(
            previewLayer: window == null ? after : window.displayLayer(after),
            globalPreviewLayer: window == null ? null : after,
          );
  }

  /// Commits the drag as a single undo step (no-op when nothing changed):
  /// the command's execute applies the final result to the repository —
  /// and, for a storyboard row, the cut resize its comma implied
  /// (feedback #9: one undo restores both or a drawing lands outside its
  /// cut).
  void endExposureEdgeDrag() {
    final before = _edgeDragBefore;
    final after = _edgeDragAfter;
    final bulkEdits = _edgeDragBulkEdits;
    final sync = _edgeDragCutSync;
    final afterDurations = _edgeDragAfterDurations;
    final afterGaps = _edgeDragAfterGaps;
    _edgeDragBefore = null;
    _edgeDragEdge = null;
    _edgeDragBlockStart = null;
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    _edgeDragBulkEdits = null;
    _edgeDragAfter = null;
    _edgeDragWindow = null;
    _edgeDragCutSync = null;
    _edgeDragAfterDurations = null;
    _edgeDragAfterGaps = null;
    dragPreview.value = null;
    if (bulkEdits != null) {
      // The selection covers the same cels after the retime (starts kept).
      _commitEdgeDragEdits(
        edits: bulkEdits,
        sync: sync,
        afterDurations: afterDurations,
        afterGaps: afterGaps,
      );
      return;
    }
    if (before == null) {
      return;
    }

    if (after == null || after == before) {
      return;
    }
    _commitEdgeDragEdits(
      edits: [(before: before, after: after)],
      sync: sync,
      afterDurations: afterDurations,
      afterGaps: afterGaps,
    );
  }

  /// One release, one undo step: the layer edits, plus the synced cut
  /// resize when a storyboard row's end moved.
  void _commitEdgeDragEdits({
    required List<({Layer before, Layer after})> edits,
    required ({
      CutId cutId,
      LayerId layerId,
      int beforeDuration,
      int beforeRowEnd,
      CutId? nextCutId,
      int nextBeforeGap,
    })?
    sync,
    required Map<CutId, int>? afterDurations,
    required Map<CutId, int>? afterGaps,
  }) {
    if (sync == null || afterDurations == null || afterGaps == null) {
      _timelineController.commitLayerTimelineDrags(edits);
      _warmActiveCut();
      notifyListeners();
      return;
    }
    final beforeDurations = <CutId, int>{sync.cutId: sync.beforeDuration};
    // No re-tile here: "the row tiles its cut" is a WRITE-TIME invariant now
    // ([cutWithCoveringStoryboardRow]), so it holds for this commit, for the
    // undo replay, and for the verbs that never come through a drag at all.
    //
    // No fade re-anchor rides along any more (R4): the fade keys are the
    // TRACK's, on the global axis — a cut resize edits the cut, not them.
    _timelineController.commitLayerTimelineDragsWithCutDurations(
      edits: edits,
      beforeDurations: beforeDurations,
      afterDurations: afterDurations,
      beforeGaps: {
        if (sync.nextCutId != null && afterGaps.containsKey(sync.nextCutId))
          sync.nextCutId!: sync.nextBeforeGap,
      },
      afterGaps: afterGaps,
      description: 'Retime storyboard cells',
    );
    _refreshAfterCutCommand();
    _warmActiveCut();
    notifyListeners();
  }

  // --- Storyboard cut-trim edge drags --------------------------------------

  Map<CutId, int>? _cutTrimBeforeDurations;
  Map<CutId, int>? _cutTrimBeforeGaps;
  Map<CutId, int>? _cutTrimAfterDurations;
  Map<CutId, int>? _cutTrimAfterGaps;
  CutId? _cutTrimCutId;
  CutId? _cutTrimNextCutId;
  TimelineBlockEdge? _cutTrimEdge;

  /// Track cut order + the dragged cut's slot, snapshotted for START-edge
  /// slides (the leftward cascade pushes predecessor gaps, R12-⑦).
  List<CutId>? _cutTrimOrder;
  int? _cutTrimIndex;

  /// Which conte PANEL a START-edge drag grabbed, cut-local. Every panel
  /// hangs a front grip on the strip (user's rule 2026-08-02), and the
  /// panel you grabbed is the one that loses commas — so the verb cannot be
  /// resolved from the cut alone. Taken at BEGIN and kept here for the same
  /// reason [_cutEdgeDragVerb] is.
  int? _cutTrimPanelIndex;

  /// The conte row as the in-flight LEAD drag would leave it, stashed for
  /// the release. The row rewrite is part of the SAME edit as the duration
  /// change — deriving it again at commit time would read the repository,
  /// which no longer says what the drag decided.
  List<({Layer before, Layer after})>? _cutTrimAfterRowEdits;

  /// Which verb the in-flight cut-edge drag belongs to. One shape of edge,
  /// and where it sits decides what it re-times — the answer is taken at
  /// BEGIN and kept HERE, in the session the continuations already reach,
  /// so a host rebuild mid-drag cannot re-route the release onto a verb
  /// whose fields were never set (the failure that sank the first #5
  /// attempt).
  _CutEdgeDragVerb? _cutEdgeDragVerb;

  /// Starts a cut edge drag on [cutId]'s [edge].
  ///
  /// - the LEAD edge is one verb for every cut (R10 R4): the cut loses
  ///   frames off its front, its END holds so the cuts behind never move,
  ///   the cut GLUED in front translates wholesale, and the difference
  ///   comes to rest at the head of the film ([planCutLeadEdge]). On a cut
  ///   WITH a conte row the frames come off [panelIndex] — the panel the
  ///   grip belongs to — and every other panel keeps its commas
  ///   ([storyboardTimelineWithPanelLeadRetimed], user's rule 2026-08-02).
  ///   The row is what floors the drag, and it floors the GRABBED panel,
  ///   not the last one;
  /// - the TRAILING edge still asks what it sits on (feedback #9): on a
  ///   cut with a storyboard row it is the LAST cell's comma and the cut's
  ///   length follows it (the always-synced pair); otherwise it trims the
  ///   duration, growth eating the following gap first.
  ///
  /// The continuations ([updateCutEdgeDrag], [endCutEdgeDrag],
  /// [cancelCutEdgeDrag]) follow whichever verb began — they carry a delta
  /// and nothing else.
  bool beginCutEdgeDrag({
    required CutId cutId,
    required TimelineBlockEdge edge,
    int panelIndex = 0,
  }) {
    final cut = cutById(cutId);
    final row = cut == null ? null : storyboardLayerForCut(cut);
    if (cut != null && row != null) {
      // R10 R4: only the TRAILING edge still asks about the conte row, and
      // its two arms agree at the cut level. The LEAD edge does not ask
      // any more — one gesture, one meaning, whether or not the cut has
      // been drawn on. The row still bounds the drag, through
      // [minimumCutDurationFor]: you cannot trim past your own panels.
      if (edge == TimelineBlockEdge.end &&
          _beginStoryboardLastCommaDrag(cut, row)) {
        _cutEdgeDragVerb = _CutEdgeDragVerb.comma;
        return true;
      }
    }
    if (_beginCutTrimDrag(cutId: cutId, edge: edge, panelIndex: panelIndex)) {
      _cutEdgeDragVerb = _CutEdgeDragVerb.cutTrim;
      return true;
    }
    _cutEdgeDragVerb = null;
    return false;
  }

  /// Applies the drag's cumulative frame delta to whichever verb
  /// [beginCutEdgeDrag] (or [beginStoryboardCommaDrag]) chose.
  void updateCutEdgeDrag(int cumulativeDelta) {
    switch (_cutEdgeDragVerb) {
      case null:
        return;
      case _CutEdgeDragVerb.cutTrim:
        _updateCutTrimDrag(cumulativeDelta);
      case _CutEdgeDragVerb.comma:
        updateExposureEdgeDrag(cumulativeDelta);
    }
  }

  /// Commits whichever verb began, as a single undo step.
  void endCutEdgeDrag() {
    final verb = _cutEdgeDragVerb;
    _cutEdgeDragVerb = null;
    switch (verb) {
      case null:
        return;
      case _CutEdgeDragVerb.cutTrim:
        _endCutTrimDrag();
      case _CutEdgeDragVerb.comma:
        endExposureEdgeDrag();
    }
  }

  /// Drops whichever verb began without touching history.
  void cancelCutEdgeDrag() {
    final verb = _cutEdgeDragVerb;
    _cutEdgeDragVerb = null;
    switch (verb) {
      case null:
        return;
      case _CutEdgeDragVerb.cutTrim:
        _cancelCutTrimDrag();
      case _CutEdgeDragVerb.comma:
        cancelExposureEdgeDrag();
    }
  }

  bool _beginCutTrimDrag({
    required CutId cutId,
    required TimelineBlockEdge edge,
    int panelIndex = 0,
  }) {
    final layout = buildStoryboardTimelineLayout(_repository.requireProject());
    StoryboardTimelineLayoutEntry? entry;
    for (final candidate in layout) {
      if (candidate.cutId == cutId) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      return false;
    }
    StoryboardTimelineLayoutEntry? next;
    if (edge == TimelineBlockEdge.end) {
      for (final candidate in layout) {
        if (candidate.trackId == entry.trackId &&
            candidate.cutIndex == entry.cutIndex + 1) {
          next = candidate;
          break;
        }
      }
    }

    _cutTrimBeforeDurations = {entry.cutId: entry.cut.duration};
    if (edge == TimelineBlockEdge.start) {
      // The start TRIM's leftward growth cascades through the
      // PREDECESSORS' gaps, so the whole track's order and gaps join the
      // drag snapshot.
      final trackEntries = [
        for (final candidate in layout)
          if (candidate.trackId == entry.trackId) candidate,
      ];
      _cutTrimOrder = [for (final candidate in trackEntries) candidate.cutId];
      _cutTrimIndex = entry.cutIndex;
      _cutTrimBeforeGaps = {
        for (final candidate in trackEntries)
          candidate.cutId: candidate.cut.leadingGapFrames,
      };
    } else {
      _cutTrimBeforeGaps = {
        entry.cutId: entry.cut.leadingGapFrames,
        if (next != null) next.cutId: next.cut.leadingGapFrames,
      };
    }
    _cutTrimCutId = cutId;
    _cutTrimNextCutId = next?.cutId;
    _cutTrimEdge = edge;
    _cutTrimPanelIndex = panelIndex;
    // The release commits from these, so a new drag must not inherit the
    // previous one's result: a press that never moves would otherwise land
    // an edit the pointer never asked for.
    _cutTrimAfterDurations = null;
    _cutTrimAfterGaps = null;
    _cutTrimAfterRowEdits = null;
    return true;
  }

  /// How far a LEAD drag on [cutId]'s [panelIndex] may shrink the cut, as a
  /// minimum DURATION — the shape [planCutLeadEdge] wants.
  ///
  /// The floor belongs to the panel the grip is on: that panel keeps one
  /// frame, and since every other panel keeps its commas, the cut's floor is
  /// its current duration less that panel's room. A cut with no conte row
  /// (or a row a drag cannot address) keeps the plain one-frame floor.
  ///
  /// ⚠️ [minimumCutDurationFor] is the LAST panel's floor and is the right
  /// answer for the trailing edge only. Using it here let a drag ask the
  /// first cell for a negative length — the assert in
  /// [StoryboardCoverageCell] — whenever the grabbed panel was shorter than
  /// the last one.
  int _leadMinimumDurationFor(Cut cut, int panelIndex) {
    final row = storyboardLayerForCut(cut);
    if (row == null) {
      return 1;
    }
    final maxShrink = storyboardPanelLeadMaxShrink(
      timeline: row.timeline,
      cutDuration: cut.duration,
      panelIndex: panelIndex,
    );
    return maxShrink == null ? 1 : math.max(1, cut.duration - maxShrink);
  }

  /// Applies the drag's cumulative frame delta as a live preview on
  /// [dragPreview] (the repository is NOT touched).
  ///
  /// END edge: the duration changes; growth consumes the FOLLOWING cut's
  /// leading gap first (that cut holds still until the gap is spent, then
  /// ripples). Shrinking follows the timeline's block language (R10-⑦):
  /// only an ATTACHED next cut rides the boundary — a detached one holds
  /// its global position (its gap grows by the shrink). START edge: the
  /// LEAD verb ([planCutLeadEdge], R10 R4) — the END stays put and the
  /// LENGTH changes, so nothing behind moves; a GLUED predecessor rides
  /// the boundary in either direction and a separated one lets its gap
  /// absorb the move; growth is walled by frame 0 and shrink by
  /// [minimumCutDurationFor].
  void _updateCutTrimDrag(int cumulativeDelta) {
    final beforeDurations = _cutTrimBeforeDurations;
    final beforeGaps = _cutTrimBeforeGaps;
    final cutId = _cutTrimCutId;
    final edge = _cutTrimEdge;
    if (beforeDurations == null ||
        beforeGaps == null ||
        cutId == null ||
        edge == null) {
      return;
    }

    final durations = <CutId, int>{};
    final gaps = <CutId, int>{};
    // The floor is the STORYBOARD row's extent, not one frame: its cells
    // are panels OF this cut, so an edge cannot be dragged past the panel it
    // belongs to (delete the cells to shrink further). Cuts without a
    // storyboard row keep the plain one-frame floor.
    //
    // WHICH panel is the floor differs by edge, and that is not a detail:
    // the trailing edge sits on the LAST panel, the leading edge on the one
    // it was grabbed from.
    final trimmedCut = cutById(cutId);
    final minDuration = trimmedCut == null
        ? 1
        : edge == TimelineBlockEdge.end
        ? minimumCutDurationFor(trimmedCut)
        : _leadMinimumDurationFor(trimmedCut, _cutTrimPanelIndex ?? 0);
    if (edge == TimelineBlockEdge.end) {
      final newDuration = math.max(
        minDuration,
        beforeDurations[cutId]! + cumulativeDelta,
      );
      durations[cutId] = newDuration;
      final nextId = _cutTrimNextCutId;
      if (nextId != null) {
        gaps[nextId] = _followingGapAfterEndMove(
          baseGap: beforeGaps[nextId]!,
          growth: newDuration - beforeDurations[cutId]!,
        );
      }
    } else {
      // START edge = the LEAD edge, and R10 R4 made it the frame axis's
      // answer ([planCutLeadEdge] over the shared contact rule): the cut's
      // END stays put and its LENGTH changes, so followers never move; the
      // cut GLUED in front translates wholesale rather than having a gap
      // torn open between them, its own glued predecessor follows, and the
      // difference comes to rest at the head of the film.
      //
      // Two behaviours used to live here — this one's ancestor opened the
      // dragged cut's own leading gap, and a cut WITH a conte row went
      // somewhere else entirely (a lead retime that pinned the start and
      // pulled the followers in). Neither was what the timeline does, and
      // the fork is why the storyboard read as a different instrument.
      final order = _cutTrimOrder!;
      final plan = planCutLeadEdge(
        slots: [
          for (final id in order)
            (
              id: id,
              leadingGapFrames: beforeGaps[id]!,
              // Nothing but the dragged cut changes duration mid-drag, and
              // the preview never touches the repository, so a live read
              // IS the before-value for every slot.
              duration: cutById(id)?.duration ?? 1,
            ),
        ],
        targetIndex: _cutTrimIndex!,
        frameDelta: cumulativeDelta,
        minDuration: minDuration,
      );
      durations.addAll(plan.durations);
      gaps.addAll(plan.gaps);
    }

    // The conte row is re-keyed by the SAME drag, and it is re-keyed HERE
    // rather than at the release: the strip and the timeline both re-derive
    // panels from (row, duration), so a preview that moved only the duration
    // showed the LAST panel shrinking for the whole gesture and then jumped
    // to the real answer on pointer-up.
    //
    // The shift is read off the plan's own result, never off
    // [cumulativeDelta] — the plan clamps, and the raw delta does not know
    // it did.
    final rowEdits = edge == TimelineBlockEdge.start
        ? _storyboardRowEditsForLeadDrag(
            cutId: cutId,
            panelIndex: _cutTrimPanelIndex ?? 0,
            applied: beforeDurations[cutId]! - (durations[cutId] ?? 0),
          )
        : const <({Layer before, Layer after})>[];

    final changed =
        durations[cutId] != beforeDurations[cutId] ||
        gaps.entries.any((entry) => beforeGaps[entry.key] != entry.value);
    // The release commits from THESE, never from the preview channel: a
    // consumer clearing [dragPreview] mid-drag must not be able to void
    // the commit.
    _cutTrimAfterDurations = changed ? durations : null;
    _cutTrimAfterGaps = changed ? gaps : null;
    _cutTrimAfterRowEdits = changed ? rowEdits : null;
    dragPreview.value = changed
        ? CutTrimDragPreview(
            previewDurations: durations,
            previewGaps: gaps,
            previewLayers: {
              for (final edit in rowEdits) edit.after.id: edit.after,
            },
          )
        : null;
  }

  /// The conte-row rewrite a LEAD drag owes: the grabbed panel loses
  /// [applied] frames off its front and every other panel keeps its commas.
  ///
  /// Empty when the cut has no row, when the drag was clamped to nothing, or
  /// when the row cannot be addressed — in each of those the plain cut
  /// duration change is the whole edit.
  List<({Layer before, Layer after})> _storyboardRowEditsForLeadDrag({
    required CutId cutId,
    required int panelIndex,
    required int applied,
  }) {
    if (applied == 0) {
      return const [];
    }
    final cut = cutById(cutId);
    final row = cut == null ? null : storyboardLayerForCut(cut);
    if (row == null) {
      return const [];
    }
    final retimed = storyboardTimelineWithPanelLeadRetimed(
      timeline: row.timeline,
      cutDuration: cut!.duration,
      panelIndex: panelIndex,
      delta: applied,
    );
    if (retimed == null || mapEquals(retimed, row.timeline)) {
      return const [];
    }
    return [(before: row, after: row.copyWith(timeline: retimed))];
  }

  /// Commits the drag as a single undo step (no-op when nothing changed):
  /// the command's execute applies the final durations AND gaps, plus the
  /// fade re-anchor (W4 fade durability) — a trimmed cut's CANONICAL fade
  /// envelope is rebuilt for the new duration so the fade-out keeps riding
  /// the cut's end. Hand-keyed opacity lanes are left untouched (the
  /// "Opacity lane = fade envelope" invariant only owns the canonical
  /// shape).
  void _endCutTrimDrag() {
    final beforeDurations = _cutTrimBeforeDurations;
    final beforeGaps = _cutTrimBeforeGaps;
    final afterDurations = _cutTrimAfterDurations;
    final afterGaps = _cutTrimAfterGaps;
    final leadRowEdits = _cutTrimAfterRowEdits;
    _cancelCutTrimDrag();
    if (beforeDurations == null ||
        beforeGaps == null ||
        afterDurations == null ||
        afterGaps == null) {
      return;
    }

    final scopedBeforeDurations = {
      for (final id in afterDurations.keys) id: beforeDurations[id]!,
    };
    final scopedBeforeGaps = {
      for (final id in afterGaps.keys) id: beforeGaps[id]!,
    };

    // "The cut ENDS WHERE THE ROW ENDS" (see [_cutSyncResizeFor]). A drag
    // that changes the duration without going near the row would leave a
    // conte cut's stored row ending somewhere the cut no longer does — and
    // the next end/comma drag, which derives the duration FROM the row end,
    // would snap the cut back to the stale one and shove the cuts behind it.
    //
    // The two edges pay that debt at opposite ends of the row. A LEAD drag
    // already decided which panel gives way, back when it knew the pointer's
    // grip. A TRAILING one has no such record, and its last panel simply
    // follows the new end.
    final rowEdits = leadRowEdits != null && leadRowEdits.isNotEmpty
        ? leadRowEdits
        : _storyboardRowEditsForResizedCuts(
            beforeDurations: scopedBeforeDurations,
            afterDurations: afterDurations,
          );
    if (rowEdits.isNotEmpty) {
      _timelineController.commitLayerTimelineDragsWithCutDurations(
        edits: rowEdits,
        beforeDurations: scopedBeforeDurations,
        afterDurations: afterDurations,
        beforeGaps: scopedBeforeGaps,
        afterGaps: afterGaps,
        description: 'Trim cut duration',
      );
      _refreshAfterCutCommand();
      _warmActiveCut();
      notifyListeners();
      return;
    }

    _cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: scopedBeforeDurations,
      afterDurations: afterDurations,
      beforeGaps: scopedBeforeGaps,
      afterGaps: afterGaps,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// The storyboard-row rewrites a duration change owes, one per resized
  /// cut that HAS a row: the row re-tiled to the cut's new length, so its
  /// last panel ends exactly where the cut now does.
  ///
  /// Empty when no resized cut has a row — the overwhelmingly common case,
  /// and the one that keeps the plain cut-duration command as the commit.
  List<({Layer before, Layer after})> _storyboardRowEditsForResizedCuts({
    required Map<CutId, int> beforeDurations,
    required Map<CutId, int> afterDurations,
  }) {
    final edits = <({Layer before, Layer after})>[];
    for (final entry in afterDurations.entries) {
      if (beforeDurations[entry.key] == entry.value) {
        continue;
      }
      final cut = cutById(entry.key);
      final row = cut == null ? null : storyboardLayerForCut(cut);
      if (row == null) {
        continue;
      }
      final filled = storyboardTimelineFilledToCover(
        timeline: row.timeline,
        cutDuration: entry.value,
      );
      if (filled == null || mapEquals(filled, row.timeline)) {
        continue;
      }
      edits.add((before: row, after: row.copyWith(timeline: filled)));
    }
    return edits;
  }

  // Fade durability (W4) retired by R4: the fade keys live on the TRACK's
  // global axis now — a cut trim is a cut edit and moves no keys (the
  // user's independence rule, the SE precedent's sentence).

  /// The END-boundary gap rule every verb that moves a cut's end shares.
  /// Growth: consume the following cut's gap, then push. Shrink: an
  /// ATTACHED next cut (gap 0 at drag start) rides the boundary; a
  /// DETACHED one holds its global position — the gap absorbs the shrink.
  int _followingGapAfterEndMove({required int baseGap, required int growth}) =>
      growth > 0
      ? math.max(0, baseGap - growth)
      : (baseGap > 0 ? baseGap - growth : 0);

  /// Drops an in-flight trim preview without touching history (the
  /// repository was never written during the drag).
  void _cancelCutTrimDrag() {
    _cutTrimBeforeDurations = null;
    _cutTrimBeforeGaps = null;
    _cutTrimAfterDurations = null;
    _cutTrimAfterGaps = null;
    _cutTrimCutId = null;
    _cutTrimNextCutId = null;
    _cutTrimEdge = null;
    _cutTrimOrder = null;
    _cutTrimIndex = null;
    _cutTrimPanelIndex = null;
    _cutTrimAfterRowEdits = null;
    dragPreview.value = null;
  }

  /// The cut after [cutId] on its own track, or null at the track's end.
  Cut? _nextCutInTrack(CutId cutId) {
    for (final track in _repository.requireProject().tracks) {
      final cuts = track.cuts;
      for (var index = 0; index < cuts.length; index += 1) {
        if (cuts[index].id == cutId) {
          return index + 1 < cuts.length ? cuts[index + 1] : null;
        }
      }
    }
    return null;
  }

  /// The camera frame's aspect — what the conte's PICTURE column is shaped
  /// by, so a cell's silhouette matches the cut's.
  double get cameraFrameAspect {
    final size = cameraFrameSize;
    return size.height <= 0 ? 16 / 9 : size.width / size.height;
  }

  /// Writes a conte cell's ACTION text, undoably.
  ///
  /// A cell is a panel of the cut's storyboard row, so the text lands on the
  /// exposure that OPENS it — block-owned like the inbetween dots, which is
  /// what lets it ride every move and copy with no re-indexing. Typing into
  /// a cut with no storyboard row does nothing yet: there is no block to
  /// hang it on until the row exists.
  void setStoryboardCellAction({
    required CutId cutId,
    required int cellIndex,
    required String action,
  }) {
    final cut = cutById(cutId);
    if (cut == null) {
      return;
    }
    final layer = storyboardLayerForCut(cut);
    if (layer == null) {
      return;
    }
    final cells = storyboardCoverageCells(
      timeline: layer.timeline,
      cutDuration: cut.duration,
    );
    if (cellIndex < 0 || cellIndex >= cells.length) {
      return;
    }
    final blockStart = cells[cellIndex].startIndex;
    final entry = layer.timeline[blockStart];
    if (entry == null || !entry.isDrawing || entry.ghost) {
      return;
    }
    _cutCommandCoordinator.updateExposureMemo(
      cutId: cutId,
      layerId: layer.id,
      blockStartIndex: blockStart,
      memo: (entry.memo ?? const ExposureMemo.empty()).copyWith(
        actionMemo: action,
      ),
    );
    notifyListeners();
  }

  // --- Movie-end drag (UI-R20 #3) -------------------------------------------

  /// The in-flight end-line drag ([MovieEndDrag]), or null.
  MovieEndDrag? _movieEndDrag;

  /// The movie's content end: the last cut end across every track.
  int get movieContentEndFrame {
    var end = 0;
    for (final entry in buildStoryboardTimelineLayout(
      _repository.requireProject(),
    )) {
      if (entry.endFrame > end) {
        end = entry.endFrame;
      }
    }
    return end;
  }

  /// Starts an end-line drag (UI-R20 #3): the line edits the movie's
  /// FINAL LENGTH — the project's trailing gap past the last cut — never
  /// the cuts themselves (the tail gap is as first-class as any other
  /// gap on this timeline).
  bool beginMovieEndDrag() {
    _movieEndDrag = MovieEndDrag(
      beforeTrailing: _repository.requireProject().trailingFrames,
      preview: dragPreview,
      commitTrailing: (trailingFrames) {
        _historyManager.execute(
          UpdateProjectTrailingFramesCommand(
            repository: _repository,
            trailingFrames: trailingFrames,
          ),
        );
        notifyListeners();
      },
    );
    return true;
  }

  void updateMovieEndDrag(int cumulativeDelta) =>
      _movieEndDrag?.update(cumulativeDelta);

  void endMovieEndDrag() {
    _movieEndDrag?.commit();
    _movieEndDrag = null;
  }

  void cancelMovieEndDrag() {
    _movieEndDrag?.cancel();
    _movieEndDrag = null;
  }

  // --- Storyboard cut RANGE selection (UI-R18 #1, O2c) ----------------------

  /// THE storyboard's selection: a frame RANGE on the track's global axis.
  ///
  /// The cut row used to carry a selection model of its own — a list of cut
  /// ids — which is what made "cut axis" a second domain next to the frame
  /// axis. It is one axis: a cut is a long block on the cut row, the snap
  /// expands a dragged range to whole blocks, and "these cuts" is what
  /// falls out ([storyboardSelectedCutIds]). Value-only view state; a plain
  /// tap clears it.
  final ValueNotifier<TrackFrameRangeSelection?> trackFrameRangeSelection =
      ValueNotifier<TrackFrameRangeSelection?>(null);

  /// The cuts the storyboard selection covers — DERIVED from the range, in
  /// track order.
  List<CutId> get storyboardSelectedCutIds {
    final selection = trackFrameRangeSelection.value;
    if (selection == null ||
        !selection.coversRow(TrackRowAddress(selection.trackId))) {
      return const [];
    }
    return _axisForTrack(
      selection.trackId,
    ).cutsIn(selection.startFrame, selection.endFrameExclusive);
  }

  /// The global frame axis of ONE track (the selected track's is
  /// [trackFrameAxis]).
  TrackFrameAxis _axisForTrack(TrackId trackId) => TrackFrameAxis([
    for (final entry in buildStoryboardTimelineLayout(
      _repository.requireProject(),
    ))
      if (entry.trackId == trackId) entry,
  ]);

  /// D40, the cut row: [trackId]'s whole cut span — the first cut's start
  /// through the last cut's end — or null when the track has no cuts.
  ({int startFrame, int endFrameExclusive})? trackCutSpan(TrackId trackId) {
    final entries = _axisForTrack(trackId).entries;
    if (entries.isEmpty) {
      return null;
    }
    return (
      startFrame: entries.first.startFrame,
      endFrameExclusive: entries.last.endFrame,
    );
  }

  /// D40, the track-owned rows: [layerId]'s authored span on the global
  /// axis — an S row's first block start through its last block end, or
  /// the transition row's first span start through its last span end.
  /// Null for empty rows (and for ids that are no track row at all).
  ({int startFrame, int endFrameExclusive})? trackRowAuthoredSpan(
    LayerId layerId,
  ) {
    final transitionTrack = _trackTransitionOwner(layerId);
    if (transitionTrack != null) {
      final events = transitionTrack.transitionLayer.instructions;
      if (events.isEmpty) {
        return null;
      }
      int? first;
      var lastExclusive = 0;
      for (final entry in events.entries) {
        if (first == null || entry.key < first) {
          first = entry.key;
        }
        final end = entry.key + entry.value.length;
        if (end > lastExclusive) {
          lastExclusive = end;
        }
      }
      return (startFrame: first!, endFrameExclusive: lastExclusive);
    }
    final layer = _trackSeAnywhere(layerId)?.layer;
    if (layer == null) {
      return null;
    }
    int? first;
    var lastExclusive = 0;
    for (final entry in layer.timeline.entries) {
      if (entry.value.ghost) {
        continue;
      }
      first ??= entry.key;
      lastExclusive = entry.key + entry.value.length!;
    }
    if (first == null) {
      return null;
    }
    return (startFrame: first, endFrameExclusive: lastExclusive);
  }

  /// A cut-select drag step stated on the track's GLOBAL FRAME axis — the
  /// timeline's range grammar, cuts as the blocks. Dragging from anywhere
  /// inside one cut to anywhere inside another selects both whole, and a
  /// span that only crosses a gap selects nothing there.
  ///
  /// This is the ONLY cut-select entry point: the storyboard's cut row now
  /// mounts the shared range gesture, which speaks frames, so the ordinal
  /// form it used to need is gone.
  ///
  /// [trackId] names the row the drag is on; omitting it means the selected
  /// track (the panel always knows, the session's own callers rarely do).
  void updateStoryboardCutSelectionByFrame({
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TrackId? trackId,
    TimelineRowAddress? headRow,
  }) {
    final row = trackId ?? selectedTrackId;
    _updateTrackRangeSelection(
      trackId: row,
      anchorRow: TrackRowAddress(row),
      anchorGlobalFrame: anchorGlobalFrame,
      headGlobalFrame: headGlobalFrame,
      headRow: headRow,
    );
  }

  /// The storyboard rail's rows for [trackId], in the order the panel
  /// stacks them: the SE rows top-down (highest slot first — slot 0 sits
  /// just above the cut row), then the CUT row at the bottom.
  ///
  /// A range drag walks THIS list (feedback #14, the timeline's Excel-style
  /// cross-row select), so the list order IS the visual order — a positive
  /// row delta must mean "downward on screen". It used to lead with the
  /// cut row, which inverted every cross-row drag: dragging from an S row
  /// down toward the V row walked the list AWAY from it (the real-device
  /// "row-span select does nothing" report).
  ///
  /// Only track-GLOBAL rows are on it — the strip is a cut-owned row on
  /// the other axis, so it cannot be reached by a row delta, and the clamp
  /// below is therefore the whole of the kind guard (the row-move
  /// precedent: what is not on the list is unreachable, so there is
  /// nothing to refuse).
  List<TimelineRowAddress> _storyboardRailRows(TrackId trackId) {
    final track = _trackById(trackId);
    return [
      // The TRANSITION row heads the group on screen, so it heads the list: a
      // row delta walks this in VISUAL order, and a row missing from it is
      // unreachable — which is what left a cross-row drag unable to start on
      // it or arrive at it (user 2026-08-11).
      if (track != null) LayerRowAddress(track.transitionLayer.id),
      if (track != null)
        for (final layer in track.seLayers.reversed) LayerRowAddress(layer.id),
      TrackRowAddress(trackId),
    ];
  }

  Track? _trackById(TrackId trackId) {
    for (final track in _repository.requireProject().tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  /// The track that owns [layerId] as one of its SE lanes, with the GLOBAL
  /// layer itself — ANY track, not just the selected one. A storyboard
  /// drag anchors on whatever row sits under the pointer, and resolving
  /// through [selectedTrackId]/[trackSeGlobalLayerById] (both active-track
  /// bound) made every verb on an unselected track's row a silent no-op.
  ({Track track, Layer layer})? _trackSeAnywhere(LayerId layerId) {
    for (final track in _repository.requireProject().tracks) {
      for (final layer in track.seLayers) {
        if (layer.id == layerId) {
          return (track: track, layer: layer);
        }
      }
    }
    return null;
  }

  /// "Where does this row's blocks live" as a snap lane, or null for a row
  /// that has none to snap to.
  RangeBlock? Function(int)? _trackRowSnapLane(
    TimelineRowAddress row,
    TrackFrameAxis axis,
  ) {
    switch (row) {
      case TrackRowAddress():
        return axis.cutBlockAt;
      case LayerRowAddress(:final layerId):
        // Resolved on the row's OWN track: the active-track lookup left
        // every unselected track's sounds snapless.
        final layer = _trackSeAnywhere(layerId)?.layer;
        if (layer != null) {
          return (index) => exposureBlockAt(layer, index);
        }
        // 🚨The transition row snaps to its SPANS, and a row with no snap lane
        // at all produced no span — which cleared the selection instead of
        // making one. Its blocks are instruction events rather than exposures,
        // so the material differs and the shape does not.
        final transition = _trackTransitionOwner(layerId)?.transitionLayer;
        if (transition == null) {
          return null;
        }
        return (index) {
          final covering = instructionSpanCovering(
            transition.instructions,
            index,
          );
          return covering == null
              ? null
              : RangeBlock(
                  startIndex: covering.key,
                  endIndexExclusive: covering.key + covering.value.length,
                );
        };
      case LaneRowAddress():
        // Lane keys are POINTS, not blocks — the lane domain's own rule
        // ("raw cells, no block snap"), so there is nothing to snap to.
        return null;
    }
  }

  /// THE track-axis select-drag step, whichever storyboard row started it.
  ///
  /// The span snaps against EVERY row it covers at once (the union snap):
  /// reaching a cut row expands the range to whole cuts, reaching an SE row
  /// expands it to whole sounds, and a drag across both gets the union —
  /// which is what makes "the selection covers these rows" a single fact
  /// rather than one per row.
  void _updateTrackRangeSelection({
    required TrackId trackId,
    required TimelineRowAddress anchorRow,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    required TimelineRowAddress? headRow,
  }) {
    final railRows = _storyboardRailRows(trackId);
    final anchorIndex = railRows.indexOf(anchorRow);
    final List<TimelineRowAddress> spanned;
    if (anchorIndex < 0 || railRows.length < 2) {
      spanned = [anchorRow];
    } else {
      // R9 #25: the head arrives as an ADDRESS, resolved by the panel
      // against the heights it paints. It used to arrive as a row DELTA
      // computed from one row's height, which under-counted every row that
      // was a different size — the whole of the "V행에서 위로 끌면 S1에서
      // 막힘" report. A row this rail does not hold (or none at all) simply
      // leaves the anchor alone: what is not on the list is unreachable,
      // which is the same guard the clamp used to be.
      final headIndex = headRow == null
          ? anchorIndex
          : railRows.indexOf(headRow);
      final resolvedHead = headIndex < 0 ? anchorIndex : headIndex;
      final first = math.min(anchorIndex, resolvedHead);
      final last = math.max(anchorIndex, resolvedHead);
      spanned = railRows.sublist(first, last + 1);
    }

    final axis = _axisForTrack(trackId);
    final lanes = <RangeBlock? Function(int)>[
      for (final row in spanned) ?_trackRowSnapLane(row, axis),
    ];
    final span = lanes.isEmpty
        ? null
        : snapSpanToBlocks(
            lanes: lanes,
            anchorIndex: anchorGlobalFrame,
            headIndex: headGlobalFrame,
          );
    // A span that only crosses a GAP still selects: these are frame-block
    // rows like any other, and an empty cell is selectable on every one of
    // them. It simply covers no blocks, so the verbs that act on them find
    // nothing to act on — what an empty selection means everywhere else.
    if (span == null) {
      trackFrameRangeSelection.value = null;
      return;
    }
    // THE ONE-SELECTION LAW — see [claimSelection].
    claimSelection(TimelineSelectionKind.cuts);
    trackFrameRangeSelection.value = TrackFrameRangeSelection(
      trackId: trackId,
      anchorRow: anchorRow,
      // Single-row drags leave this empty, which is what `spanRows` reads
      // as "the anchor alone" — no caller has to special-case the common
      // case.
      rows: spanned.length > 1 ? spanned : const [],
      startFrame: span.startIndex,
      endFrameExclusive: span.endIndexExclusive,
    );
  }

  void clearStoryboardCutSelection() {
    if (trackFrameRangeSelection.value != null) {
      trackFrameRangeSelection.value = null;
    }
  }

  /// A select-drag step on a TRACK-OWNED rail row of the storyboard — an SE
  /// lane or the transition row — stated on the track's GLOBAL frame axis.
  ///
  /// The SAME selection the cut row paints — one axis, several rows. It
  /// cannot be the timeline's cut-local selection: the display clone the
  /// timeline shows is WINDOWED to the active cut, so a sound two cuts away
  /// has no cut-local address to be selected by. The snap runs on the
  /// GLOBAL layer, which is also the layer any edit would commit against.
  ///
  /// 🚨The owner lookup asks [isTrackOwnedRailLayerId]'s question, not "is it
  /// an SE row" — that substitution is what left the transition row the one row
  /// of this rail a range drag could not touch (user 2026-08-11:
  /// 「선택범위… 트랜지션레이어만 작동안하니까 공통 규칙 그대로」). Selecting is
  /// reading; the read-only rule bites on the verbs that CHANGE a row, and the
  /// transition row simply mounts no move half.
  void updateTrackRowRangeSelectionByFrame({
    required LayerId layerId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TimelineRowAddress? headRow,
  }) {
    // The anchor row names its own track: gating on the ACTIVE track's row
    // list (and stating the selection on [selectedTrackId]) killed every
    // drag that anchored on an unselected track's row — the rail lookup
    // missed, so a cross-row reach collapsed to the anchor alone.
    final owner = _trackOwnedRailOwner(layerId);
    if (owner == null) {
      return;
    }
    // The SAME path the cut row takes — one select-drag step for the rail,
    // not one per row kind.
    _updateTrackRangeSelection(
      trackId: owner.id,
      anchorRow: LayerRowAddress(layerId),
      anchorGlobalFrame: anchorGlobalFrame,
      headGlobalFrame: headGlobalFrame,
      headRow: headRow,
    );
  }

  /// The selection filtered to cuts that still EXIST — nothing to filter
  /// any more: [storyboardSelectedCutIds] reads the CURRENT layout, so a
  /// cut another command deleted since the drag painted the range is simply
  /// not in it.
  List<CutId> get _liveSelectedCutIds => storyboardSelectedCutIds;

  /// Whether the selection can delete: cuts selected AND at least one
  /// cut survives (the project never empties).
  bool get canDeleteSelectedCuts {
    final selection = _liveSelectedCutIds;
    if (selection.isEmpty) {
      return false;
    }
    var total = 0;
    for (final track in _repository.requireProject().tracks) {
      total += track.cuts.length;
    }
    return total > selection.length;
  }

  /// Deletes every selected cut as ONE undo step (UI-R18 #1: the cut
  /// delete button acts on the selection).
  void deleteSelectedCuts() {
    if (!canDeleteSelectedCuts) {
      return;
    }
    _cutCommandCoordinator.deleteCuts(cutIds: _liveSelectedCutIds);
    clearStoryboardCutSelection();
    _refreshAfterCutCommand();
    notifyListeners();
  }

  // --- Storyboard cut-block MOVE drags (R10-④) ----------------------------

  /// The in-flight whole-block move ([CutMoveDrag]), or null. The move's
  /// own doc — re-time vs reorder, the contiguous-run rule — lives on the
  /// drag class.
  CutMoveDrag? _cutMoveDrag;

  bool beginCutMoveDrag(CutId cutId) {
    final drag = CutMoveDrag.begin(
      cutId: cutId,
      tracks: _repository.requireProject().tracks,
      selectedCutIds: storyboardSelectedCutIds,
      preview: dragPreview,
      selection: trackFrameRangeSelection.value,
      publishSelection: (selection) =>
          trackFrameRangeSelection.value = selection,
      commitOrder:
          ({
            required trackId,
            required order,
            required beforeGaps,
            required afterGaps,
          }) {
            _cutCommandCoordinator.commitCutMoveReorder(
              trackId: trackId,
              order: order,
              beforeGaps: beforeGaps,
              afterGaps: afterGaps,
            );
            _refreshAfterCutCommand();
            notifyListeners();
          },
      commitGaps: ({required beforeGaps, required afterGaps}) {
        _cutCommandCoordinator.commitCutDurationDrag(
          beforeDurations: const {},
          afterDurations: const {},
          beforeGaps: beforeGaps,
          afterGaps: afterGaps,
        );
        _refreshAfterCutCommand();
        notifyListeners();
      },
    );
    if (drag == null) {
      // A refused grip leaves an in-flight drag exactly as it was.
      return false;
    }
    _cutMoveDrag = drag;
    return true;
  }

  void updateCutMoveDrag(int cumulativeDelta) =>
      _cutMoveDrag?.update(cumulativeDelta);

  void endCutMoveDrag() {
    _cutMoveDrag?.commit();
    _cutMoveDrag = null;
  }

  /// Drops an in-flight move preview without touching history.
  void cancelCutMoveDrag() {
    _cutMoveDrag?.cancel();
    _cutMoveDrag = null;
  }

  /// Drops an in-flight drag preview without touching history (the
  /// repository was never written during the drag).
  void cancelExposureEdgeDrag() {
    _edgeDragBefore = null;
    _edgeDragEdge = null;
    _edgeDragBlockStart = null;
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    _edgeDragBulkEdits = null;
    _edgeDragAfter = null;
    _edgeDragWindow = null;
    _edgeDragCutSync = null;
    _edgeDragAfterDurations = null;
    _edgeDragAfterGaps = null;
    dragPreview.value = null;
  }

  // --- Whole-block move drags (R10-④b) --------------------------------------
  //
  // Grabbing a drawing block's BODY moves the block whole: along the frame
  // axis (slide) and across drawing layers (the cel travels, its brush
  // drawings re-keyed to the new layer). Landing requires empty space —
  // a block move never retimes other blocks. Same channel discipline as
  // the edge drags: repo untouched until release, one undo per drag.

  Layer? _blockMoveSourceBefore;
  int? _blockMoveBlockStart;
  DrawingBlockMovePlan? _blockMovePlan;

  bool get isBlockMoveDragActive => _blockMoveSourceBefore != null;

  /// Whether [layerId] can take part in a block move (source or target):
  /// a plain drawing-section layer. Track-SE rows live on the global axis
  /// with audio attached and attach rows own no timing — both stand down.
  /// SINGLE-CEL rows (image) stand down too: their one covering block is
  /// immovable by definition, and a cel dropped ONTO one would collide
  /// with the covering normalization (two entries, one survives — silent
  /// cel loss).
  bool _blockMoveEligible(LayerId layerId) {
    // Synced attach rows own no timing; FREE attach rows move blocks
    // like any drawing layer (UI-R21 #3).
    if (_isSyncedAttachedLayerId(layerId) || isTrackSeLayerId(layerId)) {
      return false;
    }
    final layer = _layerById(layerId);
    return layer != null &&
        layerKindHoldsDrawings(layer.kind) &&
        !layerKindHoldsSingleCel(layer.kind) &&
        layer.kind != LayerKind.se;
  }

  // --- PUSH / PULL (design D) ----------------------------------------------
  //
  // The rigid shove a drag used to do, as a verb you aim. PUSH opens n
  // frames at the anchor and everything after it travels with its own
  // spacing intact; PULL closes them and stops where the first affected
  // row runs out of room. The arithmetic is [rowPullSlack] /
  // [timelineShiftedFrom] for both axes; only the commit differs — re-keyed
  // exposures on a layer row, a leading gap on a track's cuts.
  //
  // SCOPE: the live selection's rows, anchored at its start; with no
  // selection, the current row at the current index.

  /// The frame-axis scope: which layer rows shift, from where, and which
  /// AXIS that anchor is stated in.
  ///
  /// A track-axis selection (the storyboard's S rows) arrives already in
  /// commit keys; a cut-local one has to be translated for those same rows.
  /// Carrying the axis is what keeps the shove from translating twice.
  ({List<LayerId> layerIds, int anchorIndex, bool anchorIsGlobal})?
  _frameShiftScope({TimelineRowAddress? currentRow}) {
    final trackSelection = trackFrameRangeSelection.value;
    if (trackSelection != null) {
      final rows = [
        for (final row in trackSelection.spanRows)
          if (row is LayerRowAddress &&
              trackSeGlobalLayerById(row.layerId) != null)
            row.layerId,
      ];
      if (rows.isNotEmpty) {
        return (
          layerIds: rows,
          anchorIndex: trackSelection.startFrame,
          anchorIsGlobal: true,
        );
      }
    }
    final selection = frameRangeSelection.value;
    if (selection != null) {
      // SYNCED attach rows shift by DERIVATION (the base's shift carries
      // the mirror); committing their display clone would write the
      // derived timeline onto the stored-empty row. SINGLE-CEL (image)
      // rows' covering block is pinned by the write normalization.
      final rows = [
        for (final id in selection.spanLayerIds)
          if (!_isSyncedAttachedLayerId(id) &&
              !_isSingleCelLayerId(id) &&
              _rangeLayerById(id) != null)
            id,
      ];
      return rows.isEmpty
          ? null
          : (
              layerIds: rows,
              anchorIndex: selection.startIndex,
              anchorIsGlobal: false,
            );
    }
    // NO selection: the current row at the current cell — the timeline's
    // rule, applied to whichever rail asked. The storyboard's current row
    // is an S row on the global axis, so its anchor is the global playhead.
    if (currentRow is LayerRowAddress &&
        trackSeGlobalLayerById(currentRow.layerId) != null) {
      return (
        layerIds: [currentRow.layerId],
        anchorIndex: editingGlobalFrame,
        anchorIsGlobal: true,
      );
    }
    final layerId = activeLayerId;
    final index = _timelineController.currentFrameIndex;
    if (layerId == null ||
        index < 0 ||
        _isSyncedAttachedLayerId(layerId) ||
        _isSingleCelLayerId(layerId) ||
        _rangeLayerById(layerId) == null) {
      return null;
    }
    return (layerIds: [layerId], anchorIndex: index, anchorIsGlobal: false);
  }

  /// The layer a shift MEASURES against, in the axis the anchor will be
  /// translated to: track-SE rows ALWAYS answer with the global layer —
  /// [_shiftAnchorFor] puts every anchor on that axis for them — and
  /// everything else with the cut-local range layer, matching a cut-local
  /// anchor. Measuring the SE display clone against the translated global
  /// anchor mixed the axes: the pull verb read zero slack in any cut past
  /// the first, and a mixed selection's pull sailed past the SE wall into
  /// an overlap crash.
  Layer? _shiftLayerFor(LayerId layerId) => isTrackSeLayerId(layerId)
      ? trackSeGlobalLayerById(layerId)
      : _rangeLayerById(layerId);

  /// The scope's anchor as [layerId]'s own timeline keys it.
  int _shiftAnchorFor(
    LayerId layerId,
    int anchorIndex, {
    required bool anchorIsGlobal,
  }) =>
      // Track-SE rows live on the GLOBAL axis, so a cut-local anchor has to
      // be translated before it can address their blocks. A global one is
      // already there.
      !anchorIsGlobal && isTrackSeLayerId(layerId)
      ? _commitBlockStart(layerId, anchorIndex)
      : anchorIndex;

  bool canPushFrames({TimelineRowAddress? currentRow}) =>
      _frameShiftScope(currentRow: currentRow) != null;

  /// How far a frame PULL can travel: the LEAST slack across the scope's
  /// rows, so the whole scope stops where the first one touches.
  int framePullSlack({TimelineRowAddress? currentRow}) {
    final scope = _frameShiftScope(currentRow: currentRow);
    if (scope == null) {
      return 0;
    }
    var slack = 0x7fffffff;
    for (final layerId in scope.layerIds) {
      final layer = _shiftLayerFor(layerId);
      if (layer == null) {
        continue;
      }
      slack = math.min(
        slack,
        rowPullSlack(
          blocks: timelineShiftableBlocks(layer.timeline),
          anchorIndex: _shiftAnchorFor(
            layerId,
            scope.anchorIndex,
            anchorIsGlobal: scope.anchorIsGlobal,
          ),
        ),
      );
    }
    return slack == 0x7fffffff ? 0 : slack;
  }

  bool canPullFrames({TimelineRowAddress? currentRow}) =>
      framePullSlack(currentRow: currentRow) > 0;

  /// Opens [count] frames at the anchor across the scope's rows; the
  /// blocks after it keep their own spacing (empty space is carried, not
  /// eaten). ONE undo step for every row it touches.
  void pushFrames(int count, {TimelineRowAddress? currentRow}) =>
      _shiftFrames(count, currentRow: currentRow);

  /// Closes up to [count] frames, clamped to [framePullSlack].
  void pullFrames(int count, {TimelineRowAddress? currentRow}) => _shiftFrames(
    -math.min(count, framePullSlack(currentRow: currentRow)),
    currentRow: currentRow,
  );

  void _shiftFrames(int delta, {TimelineRowAddress? currentRow}) {
    final scope = _frameShiftScope(currentRow: currentRow);
    if (scope == null || delta == 0) {
      return;
    }
    final edits = <({Layer before, Layer after})>[];
    for (final layerId in scope.layerIds) {
      // The COMMIT layer, never the display clone: a track-SE row's clone
      // is a projection and writing it back would drop the edit (the
      // clones are never written back).
      final before = _commitLayerById(layerId);
      if (before == null) {
        continue;
      }
      final anchor = _shiftAnchorFor(
        layerId,
        scope.anchorIndex,
        anchorIsGlobal: scope.anchorIsGlobal,
      );
      final after = before.copyWith(
        timeline: timelineShiftedFrom(
          before.timeline,
          anchorIndex: anchor,
          delta: delta,
        ),
      );
      if (after.timeline != before.timeline) {
        edits.add((before: before, after: after));
      }
    }
    if (edits.isEmpty) {
      return;
    }
    _timelineController.commitLayerTimelineDrags(edits);
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// The cut-axis scope: which track, and the ordinal the shove starts at.
  ({TrackId trackId, int anchorCutIndex})? _cutShiftScope() {
    final project = _repository.requireProject();
    final selection = storyboardSelectedCutIds;
    for (final track in project.tracks) {
      if (selection.isNotEmpty) {
        final indexes = [
          for (final id in selection) track.cuts.indexWhere((c) => c.id == id),
        ]..removeWhere((value) => value < 0);
        if (indexes.isEmpty) {
          continue;
        }
        indexes.sort();
        return (trackId: track.id, anchorCutIndex: indexes.first);
      }
      final activeIndex = track.cuts.indexWhere((c) => c.id == activeCutId);
      if (activeIndex >= 0) {
        return (trackId: track.id, anchorCutIndex: activeIndex);
      }
    }
    return null;
  }

  List<ShiftableBlock> _cutShiftBlocks(TrackId trackId) => [
    for (final entry in buildStoryboardTimelineLayout(
      _repository.requireProject(),
    ))
      if (entry.trackId == trackId)
        (startIndex: entry.startFrame, endIndexExclusive: entry.endFrame),
  ];

  bool get canPushCuts => _cutShiftScope() != null;

  /// How far a cut PULL can travel — the same slack rule, read off the
  /// track's cuts instead of a layer's exposures.
  int get cutPullSlack {
    final scope = _cutShiftScope();
    if (scope == null) {
      return 0;
    }
    final blocks = _cutShiftBlocks(scope.trackId);
    if (scope.anchorCutIndex >= blocks.length) {
      return 0;
    }
    final slack = rowPullSlack(
      blocks: blocks,
      anchorIndex: blocks[scope.anchorCutIndex].startIndex,
    );
    return slack == 0x7fffffff ? 0 : slack;
  }

  bool get canPullCuts => cutPullSlack > 0;

  /// Slides the anchor cut and everything after it [count] frames later.
  /// Cut LENGTHS never change (design D) — only where the run starts.
  void pushCuts(int count) => _shiftCuts(count);

  void pullCuts(int count) => _shiftCuts(-math.min(count, cutPullSlack));

  void _shiftCuts(int delta) {
    final scope = _cutShiftScope();
    if (scope == null || delta == 0) {
      return;
    }
    final track = _repository.requireProject().tracks.firstWhere(
      (track) => track.id == scope.trackId,
    );
    if (scope.anchorCutIndex >= track.cuts.length) {
      return;
    }
    // Positions are cumulative, so the anchor's own leading gap carries the
    // whole run: every cut after it follows for free with its spacing
    // intact, which is exactly what "rigid" means here.
    final anchor = track.cuts[scope.anchorCutIndex];
    final after = anchor.leadingGapFrames + delta;
    if (after < 0) {
      return;
    }
    _cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: const {},
      afterDurations: const {},
      beforeGaps: {anchor.id: anchor.leadingGapFrames},
      afterGaps: {anchor.id: after},
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  // --- ONE push / pull -----------------------------------------------------
  //
  // Push and pull are ONE verb aimed at whatever is selected, not two
  // verbs the user picks between: a cut is a block on the cut row exactly
  // as an exposure is a block on a layer row, so "shove from here" means
  // the same thing on both and only the commit differs.
  //
  // [currentRow] is the asking rail's current row, used only when nothing
  // is selected — the timeline's "current row at the current cell" rule,
  // applied to whichever rail asked.

  /// Whether a shove aims at the CUT axis: the selection is on a cut row,
  /// or — with nothing selected — the asking rail is.
  bool _shiftAimsAtCuts(TimelineRowAddress? currentRow) {
    final trackSelection = trackFrameRangeSelection.value;
    if (trackSelection != null) {
      return trackSelection.spanRows.whereType<TrackRowAddress>().isNotEmpty;
    }
    if (frameRangeSelection.value != null) {
      return false;
    }
    return currentRow is TrackRowAddress;
  }

  bool canPushBlocks({TimelineRowAddress? currentRow}) =>
      _shiftAimsAtCuts(currentRow)
      ? canPushCuts
      : canPushFrames(currentRow: currentRow);

  int blockPullSlack({TimelineRowAddress? currentRow}) =>
      _shiftAimsAtCuts(currentRow)
      ? cutPullSlack
      : framePullSlack(currentRow: currentRow);

  bool canPullBlocks({TimelineRowAddress? currentRow}) =>
      blockPullSlack(currentRow: currentRow) > 0;

  void pushBlocks(int count, {TimelineRowAddress? currentRow}) =>
      _shiftAimsAtCuts(currentRow)
      ? pushCuts(count)
      : pushFrames(count, currentRow: currentRow);

  void pullBlocks(int count, {TimelineRowAddress? currentRow}) =>
      _shiftAimsAtCuts(currentRow)
      ? pullCuts(count)
      : pullFrames(count, currentRow: currentRow);

  // --- Frame RANGE selection (UI-R8, TVP-style) ----------------------------

  /// The selected frame range — ONE layer's [start,end) span snapped to
  /// whole exposure blocks. Value-only view state (drag moves never fire a
  /// session notify); cleared on layer/cut switches and plain cell taps.
  final ValueNotifier<TimelineFrameRangeSelection?> frameRangeSelection =
      ValueNotifier<TimelineFrameRangeSelection?>(null);

  /// The selected LANE range (UI-R23 #3 part 2): one (layer, lane)'s raw
  /// [start,end) span — the transform lanes' own selection domain,
  /// independent of (and mutually exclusive with) [frameRangeSelection].
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
    if (_disposed) {
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
      offset + activeCutPlaybackFrameCount,
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

  /// A lane-band select-drag step (raw cells — lane keys are points, no
  /// block snap). Starting a lane selection clears the cell selection
  /// (mutual exclusion, the F4 rule).
  ///
  /// R26 #3 — the cells' grammar on lane rows: [headLaneId] (the lane row
  /// under the pointer) spans the selection across the layer's lane group
  /// in display order; the group HEADER as anchor selects every member
  /// lane. Starting on ANOTHER layer's lanes activates that layer
  /// (선택하면 액티브 레이어가 바뀜); lanes of the active layer leave it
  /// unchanged — the fx-row selection rides ALONGSIDE the active layer.
  /// [framesAreGlobal] says which axis the surface counted in — the same
  /// question [_shiftAnchorFor] asks for the frame-shift verbs. The
  /// storyboard's strips ARE the track's global axis; a cut panel's are
  /// its window, and a track-SE row's span is translated onto the global
  /// axis on the way in, because that is where the selection lives.
  void updateLaneRangeSelectionDrag({
    required LayerId layerId,
    required String laneId,
    required int anchorIndex,
    required int headIndex,
    String? headLaneId,
    bool framesAreGlobal = false,
  }) {
    final carrierTrackId = trackIdOfTransformLaneCarrier(layerId);
    if (carrierTrackId != null) {
      // The V track's lanes (R4b): the carrier id routes the selection
      // onto the TRACK's lanes — global frame indexes, no layer to
      // activate. Selecting the row keeps the rail's answer honest,
      // without promoting a cut (the drag is about keys, not cuts).
      if (_trackById(carrierTrackId) == null) {
        return;
      }
      selectTrackRow(carrierTrackId);
    } else {
      if (_layerById(layerId) == null) {
        return;
      }
      if (activeLayerId != layerId) {
        // selectLayer first: it drops the OLD selection (a different
        // layer's), then the fresh span lands for the new active layer.
        selectLayer(layerId);
      }
    }
    // THE ONE-SELECTION LAW — see [claimSelection].
    claimSelection(TimelineSelectionKind.lanes);
    final toGlobal = !framesAreGlobal && isTrackSeLayerId(layerId)
        ? activeCutGlobalStartFrame
        : 0;
    final start =
        math.max(0, math.min(anchorIndex, headIndex)) + toGlobal;
    final endExclusive = math.max(anchorIndex, headIndex) + 1 + toGlobal;
    if (endExclusive <= start) {
      return;
    }
    // R6: effect lanes span within their own effect; the NAME-TAG group
    // spans within its own order (C3 2026-08-17 — [seNameTagLaneSpan] was
    // "a complete twin of transformLaneSpan" that this switch never
    // consulted, so a drag across the tag's members folded to the one row
    // it started on: the T13 imprisonment, back on one more family);
    // every other lane id resolves against the transform order. The chain
    // may be a layer's or the V TRACK's — the carrier id says which.
    final span =
        effectLaneSpan(
          _effectChainOf(layerId) ?? const [],
          laneId,
          headLaneId ?? laneId,
        ) ??
        (laneIsSeNameTag(laneId)
            ? seNameTagLaneSpan(laneId, headLaneId ?? laneId)
            : null) ??
        transformLaneSpan(laneId, headLaneId ?? laneId);
    laneRangeSelection.value = TimelineLaneSelection(
      layerId: layerId,
      laneId: laneId,
      startIndex: start,
      endIndexExclusive: endExclusive,
      laneIds: span.length <= 1 ? const [] : span,
    );
  }

  void clearLaneRangeSelection() {
    if (laneRangeSelection.value != null) {
      laneRangeSelection.value = null;
    }
  }

  /// The in-flight lane range move (UI-R23 #3 part 2): the drag-start
  /// snapshot plus the last VALID shifted payload (blocked steps HOLD it,
  /// the #10 policy).
  ({_LaneMoveSubject subject, TimelineLaneSelection selection})? _laneMoveBefore;
  TransformTrack? _laneMoveShifted;

  /// The in-flight EFFECT-lane move's last valid chain (R6) — the effect
  /// counterpart of [_laneMoveShifted]; exactly one of the two is ever set.
  List<LayerEffect>? _laneMoveShiftedEffects;

  /// WHAT a lane selection edits: where its keys live, how they go back,
  /// and what a step in flight previews as.
  ///
  /// The move path used to name its subjects inline, in three methods that
  /// each had to remember the whole list — and two subjects were missing
  /// from all three. A CAMERA lane edits `cut.camera.track`, not the camera
  /// layer's own (unused) transform track, so opening the band there would
  /// have written keys where nothing reads them; that is why camera keys
  /// were left with a private marker drag while every other lane moved by
  /// selection. A V TRACK's EFFECT chain was simply never looked at, so an
  /// fx key range on that row answered "nothing to move" and refused in
  /// silence.
  ///
  /// One resolver instead, and the three steps stop knowing.
  _LaneMoveSubject? _laneMoveSubjectFor(TimelineLaneSelection selection) {
    // The V TRACK's own lanes (R4b, the carrier route).
    final carrierTrackId = trackIdOfTransformLaneCarrier(selection.layerId);
    if (carrierTrackId != null) {
      final track = _trackById(carrierTrackId);
      if (track == null) {
        return null;
      }
      // EFFECT lanes only: the V row has no transform of its own, so a
      // transform key range on it has nothing to move and says so.
      return _LaneMoveSubject(
        transformTrack: TransformTrack.empty(),
        effects: track.effects,
        commitTransform: (_) {},
        commitEffects: (next) =>
            updateTrackEffects(track.id, next, description: _laneMoveWhy),
        previewTransform: (_) =>
            const BlockMoveDragPreview(previewLayers: {}),
        previewEffects: (next) => BlockMoveDragPreview(
          previewLayers: const {},
          previewTrackEffects: {track.id: next},
        ),
      );
    }
    final layer = _laneVerbLayerFor(selection.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return null;
    }
    // A CAMERA row's transform lanes ride the CUT's camera track; its fx
    // lanes are still its own. The two answers live in one subject because
    // which one applies is the lane's question, not the row's.
    final isCamera = layer.kind == LayerKind.camera;
    final cameraTrack = isCamera ? activeCutOrNull?.camera.track : null;
    if (isCamera && cameraTrack == null) {
      return null;
    }
    return _LaneMoveSubject(
      transformTrack: cameraTrack ?? layer.transformTrack,
      effects: layer.effects,
      commitTransform: isCamera
          ? (next) => updateActiveCutCameraTrack(next, description: _laneMoveWhy)
          : (next) =>
                updateLayerTransformTrack(layer.id, next, description: _laneMoveWhy),
      commitEffects: (next) =>
          updateLayerEffects(layer.id, next, description: _laneMoveWhy),
      previewTransform: isCamera
          // The camera's lanes are built from the SESSION (the cut owns the
          // track, not the row's layer), so its preview is a session field
          // the lane provider reads — see [activeCutCameraTrack]. The
          // marker layer is here only to trip the row's preview gate, the
          // P3b-2 trick — and it must be a FRESH CLONE per step (the P3b-2
          // contract): the gate compares identities, so handing it the
          // repository instance tripped nothing and the camera's rows sat
          // still for the whole drag (B4-②).
          ? (next) => BlockMoveDragPreview(
              previewLayers: const {},
              cameraMarkerLayer: _layerById(layer.id)?.copyWith(),
            )
          : (next) => BlockMoveDragPreview(
              previewLayers: {layer.id: layer.copyWith(transformTrack: next)},
            ),
      previewEffects: (next) => BlockMoveDragPreview(
        previewLayers: {layer.id: layer.copyWith(effects: next)},
      ),
      onPreviewTransform: isCamera ? (next) => _cameraLaneTrackPreview = next : null,
    );
  }

  static const String _laneMoveWhy = 'Move lane keys';

  /// Starts moving the current lane selection; false when there is none
  /// or it covers no keys on ANY spanned lane (nothing to move).
  bool beginLaneRangeMoveDrag() {
    final selection = laneRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final subject = _laneMoveSubjectFor(selection);
    if (subject == null) {
      return false;
    }
    // R6: an EFFECT lane selection moves the effect chain's keys instead of
    // the transform track's — same rigid all-or-nothing group, same drag.
    //
    // ONE mode for the whole span, decided the same way
    // [updateLaneRangeMoveDrag] decides it. Asking per lane would let this
    // answer "there are keys" about a lane the step is not going to shift.
    final moveTargets = _laneVerbTargets(
      selection.spanLaneIds,
      effects: subject.effects,
    );
    final isEffectSelection = moveTargets.any(
      (laneId) => parseEffectLaneId(laneId) != null,
    );
    final keyed = moveTargets.any(
      (laneId) => isEffectSelection
          ? effectLaneKeyFrames(subject.effects, laneId).any(selection.contains)
          : transformLaneKeyFrames(
              subject.transformTrack,
              laneId,
            ).any(selection.contains),
    );
    if (!keyed) {
      return false;
    }
    _laneMoveBefore = (subject: subject, selection: selection);
    _laneMoveShifted = null;
    // Both in-flight slots clear together: a stale payload here would send
    // the commit down the wrong branch.
    _laneMoveShiftedEffects = null;

    return true;
  }

  /// A lane-move drag step: shifts EVERY spanned lane's ranged keys by
  /// [frameDelta] (R26 #3 — one rigid group, all-or-nothing across
  /// lanes) and previews via [dragPreview]. A blocked landing HOLDS the
  /// last valid preview (UI-R23 #10 — no snap-back).
  void updateLaneRangeMoveDrag({required int frameDelta}) {
    final before = _laneMoveBefore;
    if (before == null) {
      return;
    }
    if (frameDelta == 0) {
      _laneMoveShifted = null;
      _laneMoveShiftedEffects = null;
      _cameraLaneTrackPreview = null;

      dragPreview.value = null;
      laneRangeSelection.value = before.selection;
      return;
    }
    final subject = before.subject;
    final targets = _laneVerbTargets(
      before.selection.spanLaneIds,
      effects: subject.effects,
    );
    if (targets.any((laneId) => parseEffectLaneId(laneId) != null)) {
      final shiftedEffects = effectsWithLaneSpanKeysShifted(
        subject.effects,
        laneIds: targets,
        rangeStartIndex: before.selection.startIndex,
        rangeEndIndexExclusive: before.selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (shiftedEffects == null) {
        // Blocked landing: the last valid preview and outline HOLD.
        return;
      }
      _laneMoveShiftedEffects = shiftedEffects;
      dragPreview.value = subject.previewEffects(shiftedEffects);
      final effectStart = before.selection.startIndex + frameDelta;
      if (effectStart >= 0) {
        laneRangeSelection.value = TimelineLaneSelection(
          layerId: before.selection.layerId,
          laneId: before.selection.laneId,
          startIndex: effectStart,
          endIndexExclusive: before.selection.endIndexExclusive + frameDelta,
          laneIds: before.selection.laneIds,
        );
      }
      return;
    }
    final shifted = transformTrackWithLaneSpanKeysShifted(
      subject.transformTrack,
      laneIds: targets,
      rangeStartIndex: before.selection.startIndex,
      rangeEndIndexExclusive: before.selection.endIndexExclusive,
      frameDelta: frameDelta,
    );
    if (shifted == null) {
      // Blocked landing: the last valid preview and outline HOLD.
      return;
    }
    _laneMoveShifted = shifted;
    // A subject whose lanes are not built from the row's own Layer (the
    // camera's live on the CUT) parks its preview where the lane provider
    // reads it; the channel below still fires, to trip the row's gate.
    subject.onPreviewTransform?.call(shifted);
    dragPreview.value = subject.previewTransform(shifted);
    final newStart = before.selection.startIndex + frameDelta;
    if (newStart >= 0) {
      laneRangeSelection.value = TimelineLaneSelection(
        layerId: before.selection.layerId,
        laneId: before.selection.laneId,
        startIndex: newStart,
        endIndexExclusive: before.selection.endIndexExclusive + frameDelta,
        laneIds: before.selection.laneIds,
      );
    }
  }

  /// Commits the lane move as ONE undo step; the selection stays on the
  /// landed span.
  void endLaneRangeMoveDrag() {
    final before = _laneMoveBefore;
    final shifted = _laneMoveShifted;
    final shiftedEffects = _laneMoveShiftedEffects;
    final landed = laneRangeSelection.value;
    _laneMoveBefore = null;
    _laneMoveShifted = null;
    _laneMoveShiftedEffects = null;
    _cameraLaneTrackPreview = null;

    dragPreview.value = null;
    if (before != null && shiftedEffects != null) {
      before.subject.commitEffects(shiftedEffects);
      laneRangeSelection.value = landed;
      return;
    }
    if (before == null || shifted == null) {
      if (before != null) {
        laneRangeSelection.value = before.selection;
      }
      return;
    }
    before.subject.commitTransform(shifted);
    laneRangeSelection.value = landed;
  }

  /// Drops an in-flight lane-move preview, restoring the selection.
  void cancelLaneRangeMoveDrag() {
    final before = _laneMoveBefore;
    _laneMoveBefore = null;
    _laneMoveShifted = null;
    _laneMoveShiftedEffects = null;
    _cameraLaneTrackPreview = null;

    dragPreview.value = null;
    if (before != null) {
      laneRangeSelection.value = before.selection;
    }
  }

  /// The CAMERA lane move's in-flight track (see [_LaneMoveSubject]).
  ///
  /// A camera row's transform lanes are built from the CUT, not from the
  /// row's own Layer, so the preview cannot ride the layer channel the way
  /// every other row's does — it is parked here and [activeCutCameraTrack]
  /// hands it out. Exactly the shape [_cameraKeysDragPreview] already uses
  /// for the camera ROW's block move (P3b-2).
  TransformTrack? _cameraLaneTrackPreview;

  /// [_cameraKeysDragPreview] as a [TransformTrack], memoized by the map's
  /// identity — the getter below is read per cell during paints, and
  /// rebuilding a SplayTreeMap track per read would be O(cells·keys).
  Map<int, CameraPose>? _cameraBlockPreviewTrackSource;
  TransformTrack? _cameraBlockPreviewTrackMemo;
  TransformTrack? get _cameraBlockPreviewTrack {
    final keys = _cameraKeysDragPreview;
    if (keys == null) {
      return null;
    }
    if (!identical(keys, _cameraBlockPreviewTrackSource)) {
      _cameraBlockPreviewTrackSource = keys;
      // The pose-facade form — the exact shape the block-ride commit lands
      // (`CutCamera(keyframes: cameraShifted)`), so the preview can never
      // promise a landing the release won't keep.
      _cameraBlockPreviewTrackMemo = TransformTrack(keyframes: keys);
    }
    return _cameraBlockPreviewTrackMemo;
  }

  /// The camera track THE DISPLAY reads — the in-flight LANE-move preview,
  /// the in-flight BLOCK-ride preview (P3b-2), or the committed track. The
  /// lane provider, the union summary markers and the row's exposure states
  /// all read THIS one answer (B4, 2026-08-17), so a camera key follows any
  /// drag live instead of jumping on release — and every reader moves in
  /// the same frame.
  TransformTrack? get activeCutCameraTrack =>
      _cameraLaneTrackPreview ??
      _cameraBlockPreviewTrack ??
      activeCutOrNull?.camera.track;

  /// Whether [layerId] can take part in a RANGE selection (UI-R20 #2:
  /// cells are cells — EVERY layer row selects, camera and instruction
  /// included; what a selection can DO stays kind-gated at each op's
  /// seam). Attach rows stand down until the ghost-snap rework lets
  /// their all-ghost mirrors join (P3b).
  bool _rangeSelectionEligible(LayerId layerId) {
    // EVERY row selects now — synced attach mirrors included (P3b: the
    // ghost snap covers them; their mirror snaps to the base's blocks).
    if (isTrackSeLayerId(layerId)) {
      return trackSeGlobalLayerById(layerId) != null;
    }
    return _layerById(layerId) != null;
  }

  /// The layer a RANGE selection reads (cut-local DISPLAY indexes): cut
  /// layers as-is, track-SE rows as their display clones.
  Layer? _rangeLayerById(LayerId layerId) {
    final cutLayer = _layerById(layerId);
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
  int _commitBlockStart(LayerId layerId, int displayStart) {
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
  Layer? _commitLayerById(LayerId layerId) => isTrackSeLayerId(layerId)
      ? trackSeGlobalLayerById(layerId)
      : _layerById(layerId);

  /// A range-select drag step: [anchorIndex] is where the drag started,
  /// [headIndex] where the pointer is now (both cut-local cell indices).
  /// Rows that cannot range-edit (attach/camera rows) stay unselectable;
  /// SE rows joined in UI-R18 #1.
  ///
  /// [headLayerId] (UI-R17 #8, Excel-style): the row under the pointer —
  /// the selection spans every ELIGIBLE layer between anchor and head in
  /// display order, and the frame range grows until it covers whole
  /// blocks on every spanned layer.
  ///
  /// [headLaneId] (R27 #14): the pointer is on one of the ANCHOR layer's
  /// property-lane rows. The drag then reaches down that layer's own lane
  /// group and stops at the hovered lane — "A셀부터 오파시티까지만" —
  /// instead of stepping over the whole group to the next layer's cells.
  /// Cells and lanes are still two selection objects (their edits differ:
  /// blocks vs keys), but ONE drag now produces both, and the frame range
  /// is shared so the highlight reads as one rectangle.
  /// The snap lane a FOLDER row selects against (R9 #1): the very runs its
  /// band draws, which are its subtree members' exposures merged. Empty for
  /// every row that owns its own blocks.
  List<({int start, int endExclusive})> _aggregateRunsForRow(Layer layer) {
    if (!layerKindGroupsLayers(layer.kind)) {
      return const [];
    }
    // R10: the band cache's runs, so the snap and the painted band are one
    // answer. This used to walk the subtree fresh on every call — inside
    // the select-drag loop.
    return folderBandRunsOf(layer.id);
  }

  /// D40: whether the standing row has an authored span for
  /// [selectRowSpanForCurrentRow] to select (one resolver for the pair —
  /// T25).
  bool get canSelectRowSpanForCurrentRow => _rowSpanForCurrentRow() != null;

  /// D40: selects the standing row's WHOLE authored span — first authored
  /// cell through last — through the range-select entry point, so the
  /// block snap and the ONE-SELECTION claim come with it.
  void selectRowSpanForCurrentRow() {
    final target = _rowSpanForCurrentRow();
    if (target == null) {
      return;
    }
    updateFrameRangeSelectionDrag(
      layerId: target.layerId,
      anchorIndex: target.first,
      headIndex: target.lastExclusive - 1,
    );
  }

  /// The standing row's RANGE layer and its authored extremes (ghosts are
  /// derived projections, not authored cells), or null when the row has
  /// nothing to select. Lane rows fall back to their owning layer — the
  /// lane address's own law: standing on a property never costs you the
  /// layer.
  ({LayerId layerId, int first, int lastExclusive})? _rowSpanForCurrentRow() {
    final rowLayerId = switch (currentRow) {
      LayerRowAddress(:final layerId) => layerId,
      LaneRowAddress(:final layerId) => layerId,
      TrackRowAddress() => activeLayerId,
    };
    if (rowLayerId == null || !_rangeSelectionEligible(rowLayerId)) {
      return null;
    }
    final layer = _rangeLayerById(rowLayerId);
    if (layer == null) {
      return null;
    }
    int? first;
    var lastExclusive = 0;
    for (final entry in layer.timeline.entries) {
      if (entry.value.ghost) {
        continue;
      }
      first ??= entry.key;
      lastExclusive = entry.key + entry.value.length!;
    }
    if (first == null) {
      return null;
    }
    return (layerId: rowLayerId, first: first, lastExclusive: lastExclusive);
  }

  /// 🚨★★★ [spanRows] — what the drag SWEPT, straight off the rail's own row
  /// list ([resolveSelectionSpanRows]).
  ///
  /// The span used to be re-derived here, out of `cut.layers + seLayers`, and
  /// three kinds of on-screen row are not in that walk: the track-owned
  /// transition clone, lane rows, group headers. So an anchor on one of them
  /// missed and the span collapsed to a single row, while crossing one
  /// stepped over it. ⛔**Do not reintroduce a model walk here.** The surface
  /// that DRAWS the rows is the only thing that knows what is on screen; if
  /// this list is empty the caller had no rows in reach (the storyboard cut
  /// axis), and the anchor row alone is the honest answer.
  void updateFrameRangeSelectionDrag({
    required LayerId layerId,
    required int anchorIndex,
    required int headIndex,
    LayerId? headLayerId,
    String? headLaneId,
    List<TimelineRowAddress> spanRows = const [],
  }) {
    if (!_rangeSelectionEligible(layerId)) {
      return;
    }
    final layer = _rangeLayerById(layerId);
    if (layer == null) {
      return;
    }
    // A lane TAIL only exists on the anchor layer's own group: the lane
    // domain is one layer's keys (R26 #3), and a span reaching a further
    // layer's lanes is that layer's cells being selected, not its keys.
    final laneTail = headLaneId != null && (headLayerId ?? layerId) == layerId
        ? headLaneId
        : null;
    // THE ONE-SELECTION LAW — see [claimSelection]. The lane clear is not
    // final for THIS drag: a mixed span below re-sets it, which is the one
    // case where a cell drag ends up owning lane state too.
    claimSelection(TimelineSelectionKind.cells);
    final base = snapFrameRangeToBlocks(
      layer: layer,
      anchorIndex: anchorIndex,
      headIndex: headIndex,
      aggregateRuns: _aggregateRunsForRow(layer),
    );
    if (base == null) {
      frameRangeSelection.value = null;
      return;
    }
    // The layer half of what was swept, in display order — derived from the
    // rows rather than rebuilt, so the two can never disagree.
    final spanIds = spanRows.isEmpty
        ? _selectionSpanLayerIds(layerId, headLayerId ?? layerId)
        : <LayerId>[
            for (final row in spanRows)
              if (row is LayerRowAddress) row.layerId,
          ];
    if (spanIds.length <= 1) {
      frameRangeSelection.value = spanRows.isEmpty
          ? base
          : TimelineFrameRangeSelection(
              layerId: base.layerId,
              startIndex: base.startIndex,
              endIndexExclusive: base.endIndexExclusive,
              rows: spanRows,
            );
      _applySelectionLaneTail(
        layerId: layerId,
        headLaneId: laneTail,
        startIndex: base.startIndex,
        endIndexExclusive: base.endIndexExclusive,
      );
      return;
    }
    // Union-snap: expand until no spanned layer's block is cut. Each pass
    // can only grow the range, so the loop terminates.
    var start = base.startIndex;
    var end = base.endIndexExclusive;
    var changed = true;
    while (changed) {
      changed = false;
      for (final id in spanIds) {
        final spanned = _rangeLayerById(id);
        if (spanned == null) {
          continue;
        }
        final snapped = snapFrameRangeToBlocks(
          layer: spanned,
          anchorIndex: start,
          headIndex: end - 1,
          aggregateRuns: _aggregateRunsForRow(spanned),
        );
        if (snapped == null) {
          continue;
        }
        if (snapped.startIndex < start || snapped.endIndexExclusive > end) {
          start = math.min(start, snapped.startIndex);
          end = math.max(end, snapped.endIndexExclusive);
          changed = true;
        }
      }
    }
    frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: layerId,
      startIndex: start,
      endIndexExclusive: end,
      layerIds: spanIds,
      rows: spanRows,
    );
    _applySelectionLaneTail(
      layerId: layerId,
      headLaneId: laneTail,
      startIndex: start,
      endIndexExclusive: end,
    );
  }

  /// R27 #14: publishes the LANE half of a mixed cell→lane drag — the
  /// layer's lane group from its FIRST lane down to the hovered one, over
  /// the same frame range the cells settled on, so the two halves read as
  /// one rectangle. No-op (and no clear — the caller already cleared) when
  /// the drag never reached a lane row.
  ///
  /// The active layer does NOT move here: a cell drag has never changed
  /// it, and reaching into that layer's own lanes is the same gesture.
  void _applySelectionLaneTail({
    required LayerId layerId,
    required String? headLaneId,
    required int startIndex,
    required int endIndexExclusive,
  }) {
    if (headLaneId == null) {
      return;
    }
    // The tail always anchors on the FIRST transform lane, so only a
    // transform row can be its head. A drag ending on some other lane kind
    // — an SE audio lane, or (R6) an effect parameter lane — has no
    // representable span from that anchor: [transformLaneSpan] falls back
    // to the anchor alone, and publishing that would put the selection on
    // Anchor Point, where the next Add would write keys the user never
    // asked for. Nothing published, cell selection kept.
    if (headLaneId != transformGroupHeaderLane.laneId &&
        !transformLaneDisplayOrder.contains(headLaneId)) {
      return;
    }
    final span = transformLaneSpan(transformLaneDisplayOrder.first, headLaneId);
    laneRangeSelection.value = TimelineLaneSelection(
      layerId: layerId,
      laneId: transformLaneDisplayOrder.first,
      startIndex: startIndex,
      endIndexExclusive: endIndexExclusive,
      laneIds: span.length <= 1 ? const [] : span,
    );
  }

  /// The display-ordered ELIGIBLE layers between [anchor] and [head]
  /// (inclusive) — the SECTIONED order the grids render (drawing rows,
  /// then the SE section with the track rows, then camera/instruction),
  /// so a cross-row drag spans exactly the rows it visually crosses.
  /// Ineligible rows inside the span are skipped; cross-KIND moves stay
  /// blocked at the move seam (UI-R18 #1 safety).
  List<LayerId> _selectionSpanLayerIds(LayerId anchor, LayerId head) {
    final ordered = sectionedLayerOrder([
      ...activeCutOrNull?.layers ?? const <Layer>[],
      ...activeTrack.seLayers,
    ]);
    final eligible = [
      for (final layer in ordered)
        if (_rangeSelectionEligible(layer.id)) layer.id,
    ];
    final anchorIndex = eligible.indexOf(anchor);
    final headIndex = eligible.indexOf(head);
    if (anchorIndex == -1 || headIndex == -1) {
      return [anchor];
    }
    final low = math.min(anchorIndex, headIndex);
    final high = math.max(anchorIndex, headIndex);
    return eligible.sublist(low, high + 1);
  }

  void clearFrameRangeSelection() {
    if (frameRangeSelection.value != null) {
      frameRangeSelection.value = null;
    }
  }

  /// Starts a whole-block move on the block starting at [blockStartIndex];
  /// returns false when there is no such block or the row stands down.
  bool beginDrawingBlockMoveDrag({
    required LayerId layerId,
    required int blockStartIndex,
  }) {
    if (!_blockMoveEligible(layerId)) {
      _noticeSyncedAttachRefusal(layerId);
      return false;
    }
    final layer = _layerById(layerId);
    final entry = layer?.timeline[blockStartIndex];
    // Ghost repeat instances are DERIVED — their timing is the region's,
    // not draggable (UI-R8).
    if (layer == null || entry == null || !entry.isDrawing || entry.ghost) {
      return false;
    }
    _blockMoveSourceBefore = layer;
    _blockMoveBlockStart = blockStartIndex;
    return true;
  }

  /// Applies the drag's cumulative deltas as a live preview on
  /// [dragPreview] (repository untouched). [targetLayerId] is the layer row
  /// currently under the pointer (null or the source id = plain slide).
  /// Blocks in the way are pushed in the direction of travel (R12-②) and
  /// ride the preview live; the rare still-illegal landing (mark collision,
  /// ineligible row, linked cel) clears the preview — the block shows at
  /// its committed spot until the pointer reaches a legal one.
  void updateDrawingBlockMoveDrag({
    required int frameDelta,
    LayerId? targetLayerId,
  }) {
    final source = _blockMoveSourceBefore;
    final blockStart = _blockMoveBlockStart;
    if (source == null || blockStart == null) {
      return;
    }
    Layer? target = source;
    if (targetLayerId != null && targetLayerId != source.id) {
      target = _blockMoveEligible(targetLayerId)
          ? _layerById(targetLayerId)
          : null;
    }
    final plan = target == null
        ? null
        : planDrawingBlockMove(
            source: source,
            target: target,
            blockStartIndex: blockStart,
            frameDelta: frameDelta,
            cutFrameCount: _activeCutFrameCount,
          );
    _blockMovePlan = plan;
    // Ghosts follow the moved run LIVE (UI-R8 rederive on the preview).
    dragPreview.value = plan == null
        ? null
        : BlockMoveDragPreview(
            previewLayers: {
              plan.sourceAfter.id: rederiveRunBehaviors(
                plan.sourceAfter,
                cutFrameCount: _activeCutFrameCount,
              ),
              if (plan.targetAfter != null)
                plan.targetAfter!.id: rederiveRunBehaviors(
                  plan.targetAfter!,
                  cutFrameCount: _activeCutFrameCount,
                ),
            },
          );
  }

  /// The single undo step a ONE-ROW move lands as: the source row's
  /// rewrite, the target row's rewrite when the move crossed rows, and the
  /// brush-frame rekey that carries the cels across with it.
  ///
  /// The drawing-block drag and the frame-range drag both land exactly
  /// this way — same plan type, same three pieces, same collapse to a bare
  /// command when there is only one. They differed in the undo LABEL and
  /// nothing else, so that is all this takes. (The multi-row rigid move is
  /// a different shape: SE row pairs, instruction and camera riders, and a
  /// rekey list built from the plan instead of the moved frame ids.)
  Command _singleRowMoveCommand(
    DrawingBlockMovePlan plan, {
    required Layer source,
    required String description,
  }) {
    final commands = <Command>[
      UpdateLayerTimelineCommand(
        repository: _repository,
        before: source,
        after: rederiveRunBehaviors(
          plan.sourceAfter,
          cutFrameCount: _activeCutFrameCount,
        ),
      ),
      if (plan.targetBefore != null)
        UpdateLayerTimelineCommand(
          repository: _repository,
          before: plan.targetBefore!,
          after: rederiveRunBehaviors(
            plan.targetAfter!,
            cutFrameCount: _activeCutFrameCount,
          ),
        ),
    ];
    if (plan.isCrossLayer && plan.movedFrameIds.isNotEmpty) {
      final cut = requireActiveCut;
      commands.add(
        RekeyBrushFramesCommand(
          store: brushFrameStore,
          pairs: [
            for (final frameId in plan.movedFrameIds)
              (
                brushFrameKeyForCut(cut, source.id, frameId),
                brushFrameKeyForCut(cut, plan.targetAfter!.id, frameId),
              ),
          ],
        ),
      );
    }
    return commands.length == 1
        ? commands.single
        : CompositeCommand(description: description, commands: commands);
  }

  /// Commits the move as a single undo step (no-op when the drag ends on
  /// an illegal or unchanged landing). Cross-layer moves compose the two
  /// layer updates with the brush-store rekey so undo restores everything.
  void endDrawingBlockMoveDrag() {
    final source = _blockMoveSourceBefore;
    final plan = _blockMovePlan;
    _blockMoveSourceBefore = null;
    _blockMoveBlockStart = null;
    _blockMovePlan = null;
    dragPreview.value = null;
    if (source == null || plan == null) {
      return;
    }
    _historyManager.execute(
      _singleRowMoveCommand(
        plan,
        source: source,
        description: 'Move drawing block',
      ),
    );
    // The selection follows the block onto its new layer (R12-④): the
    // user grabbed THAT drawing — keep working on it where it landed.
    if (plan.isCrossLayer) {
      _layerController.selectLayer(plan.targetAfter!.id);
    }
    _warmActiveCut();
    notifyListeners();
  }

  /// Drops an in-flight move preview without touching history.
  void cancelDrawingBlockMoveDrag() {
    _blockMoveSourceBefore = null;
    _blockMoveBlockStart = null;
    _blockMovePlan = null;
    dragPreview.value = null;
  }

  // --- Frame RANGE move drag (UI-R8: drag the selected range) --------------

  /// Whether the drag in flight belongs to the TRACK-axis selection (the
  /// storyboard's rows) rather than the cut-local one.
  ///
  /// The machine itself is axis-free: it plans on its sources' COMMIT
  /// forms, which for a track-SE row is the global layer either way. Only
  /// two things depend on the axis — which selection object the live and
  /// landed spans are published to, and which one a cancel restores — and
  /// both go through [_rangeMoveSelection].
  bool _rangeMoveOnTrackAxis = false;

  /// THE selection this move reads and publishes, in the axis its sources
  /// are keyed by. Every step of the drag writes through here instead of
  /// touching a notifier directly, so the machine never has to know which
  /// object owns it.
  TimelineFrameRangeSelection? get _rangeMoveSelection {
    if (!_rangeMoveOnTrackAxis) {
      return frameRangeSelection.value;
    }
    final live = trackFrameRangeSelection.value;
    final anchor = live?.anchorRow;
    if (live == null || anchor is! LayerRowAddress) {
      return null;
    }
    return TimelineFrameRangeSelection(
      layerId: anchor.layerId,
      startIndex: live.startFrame,
      endIndexExclusive: live.endFrameExclusive,
      layerIds: [
        for (final row in live.spanRows)
          if (row is LayerRowAddress) row.layerId,
      ],
    );
  }

  set _rangeMoveSelection(TimelineFrameRangeSelection? span) {
    if (!_rangeMoveOnTrackAxis) {
      frameRangeSelection.value = span;
      return;
    }
    if (span == null) {
      trackFrameRangeSelection.value = null;
      return;
    }
    // The axis's own facts ride from the drag-start capture: the anchor
    // names its OWN track (the select path's law — re-keying to
    // [selectedTrackId] here hid the band for the whole drag on any other
    // track and left the landed selection keyed to the wrong one), and a
    // non-layer row in a mixed span is not something the layer-stated span
    // can re-derive.
    final before = _rangeMoveTrackSelectionBefore;
    trackFrameRangeSelection.value = TrackFrameRangeSelection(
      trackId: before?.trackId ?? selectedTrackId,
      anchorRow: LayerRowAddress(span.layerId),
      rows: [
        for (final id in span.spanLayerIds) LayerRowAddress(id),
        if (before != null)
          for (final row in before.rows)
            if (row is! LayerRowAddress) row,
      ],
      startFrame: span.startIndex,
      endFrameExclusive: span.endIndexExclusive,
    );
  }

  /// The display→commit offset the move applies to [layerId]'s span. ZERO
  /// on the track axis: the span is already stated in commit keys, and
  /// translating it again would address another cut's frames.
  int _rangeMoveCommitOffset(LayerId layerId, int spanStart) =>
      _rangeMoveOnTrackAxis
      ? 0
      : _commitBlockStart(layerId, spanStart) - spanStart;

  Layer? _rangeMoveSourceBefore;

  /// The move's subject span as it stood at drag start, stated in the axis
  /// its sources commit in (see [_rangeMoveSelection]).
  TimelineFrameRangeSelection? _rangeMoveSelectionBefore;

  /// The TRACK-axis selection as it stood at drag start — the setter reads
  /// the track id and the non-layer rows from here, because the machine's
  /// layer-stated span cannot carry them and the LIVE value is the very
  /// thing the setter is overwriting.
  TrackFrameRangeSelection? _rangeMoveTrackSelectionBefore;
  int? _rangeMoveGroupStart;
  DrawingBlockMovePlan? _rangeMovePlan;

  /// Cross-layer selections (UI-R18 #1): every spanned layer's drag-start
  /// snapshot in COMMIT form (+ the display→commit index offset for
  /// track-SE rows); the move slides them together along the FRAME axis
  /// (row changes stay single-layer anim-only — the kind guard would make
  /// partial rect drops ambiguous).
  List<({Layer commit, int offset})>? _rangeMoveMultiSources;
  List<DrawingBlockMovePlan>? _rangeMoveMultiPlans;

  /// The in-flight MULTI-ROW range move (UI-R23 #9): a multi-layer drawing
  /// selection dragged onto a different row shifts every selected row
  /// rigidly. Set only while a valid rigid landing is previewed; an illegal
  /// step leaves the last valid plan in place (UI-R23 #10).
  MultiRowRangeMovePlan? _rangeMoveMultiRowPlan;

  /// R27 #8: the row the move drag GRABBED — the hop origin. The
  /// selection's anchor row is a different thing (selecting upward makes
  /// them differ), and using it made "this block lands on that row" come
  /// out shifted by however far the two were apart.
  LayerId? _rangeMoveGrabLayerId;

  /// KEY sources riding the range move (P3b-2, #2 second half): the
  /// camera row's keyframe snapshot and the spanned instruction rows —
  /// their keys shift with the same delta the blocks slide.
  Map<int, CameraPose>? _rangeMoveCameraBefore;
  LayerId? _rangeMoveCameraLayerId;
  List<Layer>? _rangeMoveInstructionSources;
  Map<int, CameraPose>? _rangeMoveCameraShifted;
  Map<LayerId, Map<int, InstructionEvent>>? _rangeMoveInstructionShifted;

  /// A ROW-CHANGE drop in flight within the SE / camera sections (P3b-4,
  /// 같은 섹션 행이동): the planned GLOBAL layer pair for an SE→SE drop,
  /// or the instruction-map pair for instruction→instruction.
  ({
    LayerId sourceId,
    LayerId targetId,
    Layer sourceBefore,
    Layer sourceAfter,
    Layer targetBefore,
    Layer targetAfter,
  })?
  _rangeMoveSeRowChange;

  /// The SE rows riding a MULTI-ROW rigid move (R26 #2): a span that also
  /// covers a track-SE row moves that row's blocks by the same row delta
  /// within the SE lattice — "if a block is movable, it moves no matter
  /// how many rows you select" applies to SE rows too.
  List<SeRowMovePair>? _rangeMoveMultiSeRowChanges;
  ({
    LayerId sourceId,
    LayerId targetId,
    Map<int, InstructionEvent> sourceAfter,
    Map<int, InstructionEvent> targetAfter,
  })?
  _rangeMoveInstructionRowChange;

  /// The in-flight camera-key preview the cell resolution consults
  /// (exposureStateForLayer): the camera row's cells follow the drag
  /// without the repository moving.
  Map<int, CameraPose>? _cameraKeysDragPreview;

  /// Starts moving the CURRENT frame-range selection; returns false when
  /// there is none (or its row stands down).
  ///
  /// Cross-layer selections (UI-R18 #1) move too: every spanned layer's
  /// selected blocks slide together along the frame axis, one composite
  /// undo on release. Row-changing drops stay single-layer (the kind
  /// guard would make partial rect drops ambiguous).
  /// [grabLayerId] = the row the pointer went down on (R27 #8); null falls
  /// back to the selection's anchor row (the callers that have no pointer,
  /// e.g. tests of a single-row move).
  /// A range-move drag on the TRACK axis — the storyboard's S rows.
  ///
  /// The same machine: it plans on its sources' COMMIT forms, and a
  /// track-SE row's commit form is the global layer whichever rail asked.
  /// What is different is only the axis the span is stated in, so the
  /// sources take offset 0 (the range is ALREADY in their keys) where a
  /// cut-local drag would carry the cut's start.
  ///
  /// Track rows are not movable subjects here: a cut row's blocks are cuts
  /// and sliding those is the cut drag's job, which the storyboard's own V
  /// row already mounts.
  bool beginTrackRangeMoveDrag([LayerId? grabLayerId]) {
    _rangeMoveOnTrackAxis = true;
    final live = trackFrameRangeSelection.value;
    if (live == null) {
      return false;
    }
    _rangeMoveTrackSelectionBefore = live;
    final sources = <({Layer commit, int offset})>[];
    // C1 (2026-08-17): the TRANSITION row is a movable subject on THIS
    // axis — its spans live global, and this rail is their one author
    // (the cut timeline's clone stays the read-only projection). It rides
    // the move machine's existing INSTRUCTION-source arm, exactly as the
    // cut-local instruction rows do in [beginFrameRangeMoveDrag].
    final instructionSources = <Layer>[];
    for (final row in live.spanRows) {
      if (row is! LayerRowAddress) {
        continue;
      }
      final transition = _trackTransitionOwner(row.layerId)?.transitionLayer;
      if (transition != null) {
        final hasSpan = transition.instructions.keys.any(
          (key) => key >= live.startFrame && key < live.endFrameExclusive,
        );
        if (hasSpan) {
          instructionSources.add(transition);
        }
        continue;
      }
      final commit = trackSeGlobalLayerById(row.layerId);
      if (commit == null) {
        continue;
      }
      // Only rows that actually carry a WHOLE block inside the range move
      // — the cross-layer slide's rule, unchanged.
      final hasBlock = drawingBlocks(commit.timeline).any(
        (block) =>
            !block.entry.ghost &&
            block.startIndex >= live.startFrame &&
            block.endIndexExclusive <= live.endFrameExclusive,
      );
      if (hasBlock) {
        sources.add((commit: commit, offset: 0));
      }
    }
    if (sources.isEmpty && instructionSources.isEmpty) {
      return false;
    }
    _rangeMoveGrabLayerId = grabLayerId;
    _rangeMoveSourceBefore = null;
    _rangeMoveGroupStart = null;
    _rangeMovePlan = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraBefore = null;
    _rangeMoveCameraLayerId = null;
    _rangeMoveInstructionSources = instructionSources.isEmpty
        ? null
        : instructionSources;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _rangeMoveMultiSources = sources;
    _rangeMoveSelectionBefore = _rangeMoveSelection;
    return _rangeMoveSelectionBefore != null;
  }

  bool beginFrameRangeMoveDrag([LayerId? grabLayerId]) {
    // The axis is decided HERE and nowhere else: every begin states it, so
    // no path can inherit the previous drag's answer.
    _rangeMoveOnTrackAxis = false;
    _rangeMoveTrackSelectionBefore = null;
    final selection = _rangeMoveSelection;
    if (selection == null || !_rangeSelectionEligible(selection.layerId)) {
      return false;
    }
    _rangeMoveGrabLayerId = grabLayerId ?? selection.layerId;
    _rangeMoveMultiSources = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraBefore = null;
    _rangeMoveCameraLayerId = null;
    _rangeMoveInstructionSources = null;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    // KEY sources (P3b-2, #2 second half): camera keys, instruction
    // spans AND the layers' own transform-track keys (P3c, #13) inside
    // the selection move with the blocks — same delta, one rigid group.
    // SYNCED attach mirrors stay PASSENGERS (P3b-1): the base's slide
    // carries them by derivation.
    Map<int, CameraPose>? cameraBefore;
    LayerId? cameraLayerId;
    final instructionSources = <Layer>[];
    bool anyKeyIn(Iterable<int> keys) => keys.any(
      (key) => key >= selection.startIndex && key < selection.endIndexExclusive,
    );
    for (final id in selection.spanLayerIds) {
      final layer = _layerById(id);
      if (layer == null) {
        continue;
      }
      if (layer.kind == LayerKind.camera) {
        final keyframes = activeCutOrNull?.camera.keyframes;
        if (keyframes != null && anyKeyIn(keyframes.keys)) {
          cameraBefore = Map<int, CameraPose>.of(keyframes);
          cameraLayerId = id;
        }
        continue;
      }
      if (layer.kind == LayerKind.instruction &&
          anyKeyIn(layer.instructions.keys)) {
        instructionSources.add(layer);
      }
      // UI-R23 #3: a frame-range selection NO LONGER carries the layer's
      // own transform keys — frame selection ⊥ transform keys. The
      // transform lanes own their keys through their own lane-scoped
      // selection domain; camera keys and instruction spans (a camera /
      // instruction row's OWN content) still ride below.
    }
    // Multi-layer spans, SE rows and KEY sources route through the
    // frame-axis slide (UI-R18 #1): per-layer plans on the COMMIT forms;
    // row-change drops stay the single-anim path below.
    if (selection.spanLayerIds.length > 1 ||
        isTrackSeLayerId(selection.layerId) ||
        cameraBefore != null ||
        instructionSources.isNotEmpty) {
      final sources = <({Layer commit, int offset})>[];
      for (final id in selection.spanLayerIds) {
        // SYNCED attach rows never source a move (their commit form owns
        // no timing) — they stay PASSENGERS, carried by the base's slide
        // through derivation. Id-gated: the synced-block UI stopped
        // marking mirror entries ghost, so the block filter below no
        // longer excludes them. SINGLE-CEL (image) rows stand down too:
        // their covering block is pinned by the write normalization.
        if (_isSyncedAttachedLayerId(id) || _isSingleCelLayerId(id)) {
          continue;
        }
        final display = _rangeLayerById(id);
        final commit = _commitLayerById(id);
        if (display == null || commit == null) {
          continue;
        }
        final hasBlock = drawingBlocks(display.timeline).any(
          (block) =>
              !block.entry.ghost &&
              block.startIndex >= selection.startIndex &&
              block.endIndexExclusive <= selection.endIndexExclusive,
        );
        if (hasBlock) {
          sources.add((
            commit: commit,
            offset: _rangeMoveCommitOffset(id, selection.startIndex),
          ));
        }
      }
      if (sources.isEmpty &&
          cameraBefore == null &&
          instructionSources.isEmpty) {
        // An all-synced span dies here — say why at the cursor, like the
        // single-row path does.
        _noticeSyncedAttachRefusal(selection.layerId);
        return false;
      }
      _rangeMoveMultiSources = sources;
      _rangeMoveCameraBefore = cameraBefore;
      _rangeMoveCameraLayerId = cameraLayerId;
      _rangeMoveInstructionSources = instructionSources.isEmpty
          ? null
          : instructionSources;
      _rangeMoveSelectionBefore = selection;
      return true;
    }
    // A SYNCED attach row's blocks are borrowed exposures — the move
    // refuses with the "edit the owner" pill (the synced-block UI made
    // the row look grabbable; before it, the all-ghost timeline fell out
    // of the block scan below on its own). A SINGLE-CEL (image) row's
    // covering block is immovable — the normalization would revert it.
    if (_isSyncedAttachedLayerId(selection.layerId)) {
      _noticeSyncedAttachRefusal(selection.layerId);
      return false;
    }
    if (_isSingleCelLayerId(selection.layerId)) {
      return false;
    }
    final layer = _layerById(selection.layerId);
    if (layer == null) {
      return false;
    }
    int? groupStart;
    for (final block in drawingBlocks(layer.timeline)) {
      if (block.entry.ghost) {
        continue;
      }
      if (block.startIndex >= selection.startIndex &&
          block.endIndexExclusive <= selection.endIndexExclusive) {
        groupStart = block.startIndex;
        break;
      }
    }
    if (groupStart == null) {
      return false; // Nothing but empty cells selected — nothing to move.
    }
    _rangeMoveSourceBefore = layer;
    _rangeMoveSelectionBefore = selection;
    _rangeMoveGroupStart = groupStart;
    return true;
  }

  /// A ROW-CHANGE drag step (P3b-4): returns true when it OWNED the step
  /// — either a planned SE→SE / instruction→instruction landing (preview
  /// published) or an owned-but-illegal hover (preview cleared). False
  /// falls through to the plain frame-axis slide.
  bool _updateRangeRowChangeDrag(
    TimelineFrameRangeSelection selection,
    int frameDelta,
    LayerId targetLayerId,
  ) {
    void keepLastValid() {
      // UI-R23 #10: a blocked / incompatible landing KEEPS the last valid
      // preview and outline — the move "stops at the last legal spot" and
      // resumes when a legal row returns, uniform across every source kind
      // (the R22-B snap-back-to-origin is retired). Nothing to mutate: the
      // stored last-valid plan and the live preview stand.
    }

    void followOutline() {
      _rangeMoveMultiPlans = null;
      _rangeMoveCameraShifted = null;
      _rangeMoveInstructionShifted = null;
      _cameraKeysDragPreview = null;
      final newStart = selection.startIndex + frameDelta;
      if (newStart >= 0) {
        _rangeMoveSelection = TimelineFrameRangeSelection(
          layerId: targetLayerId,
          startIndex: newStart,
          endIndexExclusive: selection.endIndexExclusive + frameDelta,
        );
      }
    }

    final sourceIsSe = isTrackSeLayerId(selection.layerId);
    if (sourceIsSe && isTrackSeLayerId(targetLayerId)) {
      final sourceGlobal = trackSeGlobalLayerById(selection.layerId);
      final targetGlobal = trackSeGlobalLayerById(targetLayerId);
      if (sourceGlobal == null || targetGlobal == null) {
        keepLastValid();
        return true;
      }
      final offset = _rangeMoveCommitOffset(
        selection.layerId,
        selection.startIndex,
      );
      final plan = planSeRangeRowMove(
        source: sourceGlobal,
        target: targetGlobal,
        rangeStartIndex: selection.startIndex + offset,
        rangeEndIndexExclusive: selection.endIndexExclusive + offset,
        frameDelta: frameDelta,
      );
      if (plan == null) {
        keepLastValid();
        return true;
      }
      _rangeMoveSeRowChange = (
        sourceId: selection.layerId,
        targetId: targetLayerId,
        sourceBefore: sourceGlobal,
        sourceAfter: plan.sourceAfter,
        targetBefore: targetGlobal,
        targetAfter: plan.targetAfter,
      );
      dragPreview.value = BlockMoveDragPreview(
        previewLayers: {
          selection.layerId: trackSeWindow.displayLayer(plan.sourceAfter),
          targetLayerId: trackSeWindow.displayLayer(plan.targetAfter),
        },
        // C2: the plans ARE the global forms — the storyboard strips
        // follow the cross-row drop live through the same one gate.
        previewGlobalLayers: {
          selection.layerId: plan.sourceAfter,
          targetLayerId: plan.targetAfter,
        },
      );
      followOutline();
      return true;
    }
    final sourceLayer = _layerById(selection.layerId);
    final targetLayer = _layerById(targetLayerId);
    final sourceIsInstruction = sourceLayer?.kind == LayerKind.instruction;
    if (sourceIsInstruction && targetLayer?.kind == LayerKind.instruction) {
      final plan = planInstructionRangeRowMove(
        source: sourceLayer!.instructions,
        target: targetLayer!.instructions,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (plan == null) {
        keepLastValid();
        return true;
      }
      _rangeMoveInstructionRowChange = (
        sourceId: selection.layerId,
        targetId: targetLayerId,
        sourceAfter: plan.sourceAfter,
        targetAfter: plan.targetAfter,
      );
      dragPreview.value = BlockMoveDragPreview(
        previewLayers: {
          selection.layerId: sourceLayer.copyWith(
            instructions: plan.sourceAfter,
          ),
          targetLayerId: targetLayer.copyWith(instructions: plan.targetAfter),
        },
      );
      followOutline();
      return true;
    }
    // SE / instruction sources hovering an INCOMPATIBLE row: the drop is
    // illegal — the last valid preview HOLDS until a legal row returns
    // (UI-R23 #10, the cross-section discipline). Every other source falls
    // through to the plain slide (the camera key drag keeps ignoring row
    // wander, P3b-2).
    if (sourceIsSe || sourceIsInstruction) {
      keepLastValid();
      return true;
    }
    return false;
  }

  /// The display-ordered lattice of move-eligible DRAWING rows — the rows a
  /// multi-row rigid shift can travel across (all one section).
  List<Layer> _blockMoveLattice() {
    final ordered = sectionedLayerOrder(activeCutOrNull?.layers ?? const []);
    return [
      for (final layer in ordered)
        if (_blockMoveEligible(layer.id)) layer,
    ];
  }

  /// R27 #8: EVERY row the timeline shows, in the order it shows them —
  /// drawing rows, SE rows (track clones included) and the camera /
  /// instruction rows alike.
  ///
  /// A range move's row hop is a fact about what the POINTER did on
  /// screen; deriving it from one content lattice (the old behaviour)
  /// made the hop uncomputable whenever the drag was anchored on a row
  /// that lattice does not contain — a camera or instruction row — and
  /// the whole multi-row move silently died even though the selected
  /// blocks had a perfectly legal home. Each moving row translates this
  /// display hop into its own lattice below.
  List<Layer> _rangeRowOrder() => sectionedLayerOrder(layers);

  /// The display-row hop from [anchorId] to [targetId]; null when either
  /// row is not on screen.
  int? _displayRowDelta(List<Layer> rows, LayerId anchorId, LayerId targetId) {
    final anchorIndex = rows.indexWhere((layer) => layer.id == anchorId);
    final targetIndex = rows.indexWhere((layer) => layer.id == targetId);
    if (anchorIndex == -1 || targetIndex == -1) {
      return null;
    }
    return targetIndex - anchorIndex;
  }

  /// What [displayDelta] means INSIDE [lattice] for the row [layerId]:
  /// walk the display rows by the hop, then read where the row it landed
  /// on sits in the lattice. Null when the hop leaves the screen or lands
  /// on a row this kind of content cannot live on.
  int? _latticeHopFor({
    required List<Layer> rows,
    required List<Layer> lattice,
    required LayerId layerId,
    required int displayDelta,
  }) {
    final rowIndex = rows.indexWhere((layer) => layer.id == layerId);
    if (rowIndex == -1) {
      return null;
    }
    final landingIndex = rowIndex + displayDelta;
    if (landingIndex < 0 || landingIndex >= rows.length) {
      return null;
    }
    final landingId = rows[landingIndex].id;
    final from = lattice.indexWhere((layer) => layer.id == layerId);
    final to = lattice.indexWhere((layer) => layer.id == landingId);
    if (from == -1 || to == -1) {
      return null;
    }
    return to - from;
  }

  /// The one lattice hop every content-bearing row in [ids] agrees on.
  /// `blocked` when a row cannot land, or when two rows would need
  /// different hops (the rigid move is all-or-nothing); a null `delta`
  /// with `blocked: false` means nothing in this lattice is moving.
  ({bool blocked, int? delta}) _agreedLatticeHop({
    required List<Layer> rows,
    required List<Layer> lattice,
    required List<LayerId> ids,
    required int displayDelta,
  }) {
    int? shared;
    for (final id in ids) {
      final hop = _latticeHopFor(
        rows: rows,
        lattice: lattice,
        layerId: id,
        displayDelta: displayDelta,
      );
      if (hop == null || (shared != null && shared != hop)) {
        return (blocked: true, delta: null);
      }
      shared = hop;
    }
    return (blocked: false, delta: shared);
  }

  /// A MULTI-ROW range move step (UI-R23 #9): a multi-layer DRAWING
  /// selection dragged onto a different row shifts every selected row
  /// rigidly by the same row + frame delta. Returns true when it OWNS the
  /// step — a valid rigid landing (preview published) or an illegal one
  /// that HOLDS the last valid preview (UI-R23 #10). Returns false (falls
  /// through to the plain frame slide) for same-row steps or spans whose
  /// NON-drawing rows carry content in range (keys ride the frame axis
  /// only). Empty rows of any kind never block (UI-R24 #3: only the
  /// frames inside the selection move).
  bool _updateMultiRowRangeMove(
    TimelineFrameRangeSelection selection,
    int frameDelta,
    LayerId targetLayerId,
  ) {
    if (selection.spanLayerIds.length <= 1) {
      return false;
    }
    bool anyKeyIn(Iterable<int> keys) => keys.any(
      (key) => key >= selection.startIndex && key < selection.endIndexExclusive,
    );
    bool carriesBlockInRange(Layer layer) => drawingBlocks(layer.timeline).any(
      (block) =>
          !block.entry.ghost &&
          block.startIndex < selection.endIndexExclusive &&
          block.endIndexExclusive > selection.startIndex,
    );
    // R27 #8: sort the span by what each row can DO with the hop. Drawing
    // rows and track-SE rows travel across their own lattice; the camera
    // and instruction rows have no row axis to travel, so their keys ride
    // the FRAME delta and stay put. Empty rows contribute nothing at all.
    //
    // The old code made a key-carrying camera/instruction row veto the
    // whole move ("keys ride the frame axis only" → `return false`). That
    // is the "임시처방" the user called out: selecting a CAM row next to a
    // sound block made the sound unmovable, even though its landing row
    // was empty. A row that cannot change rows now simply doesn't.
    final drawingSourceIds = <LayerId>[];
    final sePassengerIds = <LayerId>[];
    var cameraRides = false;
    final instructionRiders = <Layer>[];
    for (final id in selection.spanLayerIds) {
      if (_blockMoveEligible(id)) {
        final layer = _layerById(id);
        if (layer != null && carriesBlockInRange(layer)) {
          drawingSourceIds.add(id);
        }
        continue;
      }
      if (isTrackSeLayerId(id)) {
        final display = _rangeLayerById(id);
        if (display != null && carriesBlockInRange(display)) {
          sePassengerIds.add(id);
        }
        continue;
      }
      final layer = _layerById(id);
      if (layer == null) {
        continue;
      }
      if (layer.kind == LayerKind.camera) {
        final keyframes = activeCutOrNull?.camera.keyframes;
        if (keyframes != null && anyKeyIn(keyframes.keys)) {
          cameraRides = true;
        }
        continue;
      }
      if (layer.kind == LayerKind.instruction) {
        if (anyKeyIn(layer.instructions.keys)) {
          instructionRiders.add(layer);
        }
        continue;
      }
      // A row that is neither move-eligible nor a known frame-axis rider
      // (a SYNCED attach row) still routes the step to the plain slide
      // when it carries content: its timing belongs to its base.
      if (carriesBlockInRange(layer)) {
        return false;
      }
    }
    final lattice = _blockMoveLattice();
    final seLattice = activeTrack.seLayers;
    final rows = _rangeRowOrder();
    final displayDelta = _displayRowDelta(
      rows,
      _rangeMoveGrabLayerId ?? selection.layerId,
      targetLayerId,
    );
    if (displayDelta == null) {
      // The pointer left the rows entirely. When something in the span
      // CAN travel, HOLD the last valid preview (UI-R23 #10); otherwise
      // the plain slide owns the step.
      return drawingSourceIds.isNotEmpty || sePassengerIds.isNotEmpty;
    }
    if (displayDelta == 0) {
      // No row change this step — the plain frame slide owns it.
      return false;
    }
    final drawingHop = _agreedLatticeHop(
      rows: rows,
      lattice: lattice,
      ids: drawingSourceIds,
      displayDelta: displayDelta,
    );
    final seHop = _agreedLatticeHop(
      rows: rows,
      lattice: seLattice,
      ids: sePassengerIds,
      displayDelta: displayDelta,
    );
    if (drawingHop.blocked || seHop.blocked) {
      // A content-bearing row has nowhere to land (or two rows would need
      // different hops): all-or-nothing, HOLD the last valid preview.
      return true;
    }
    // A hop of 0 alongside a non-zero one would tear the rigid move apart
    // — the slide owns those steps instead.
    final rowDelta = drawingHop.delta ?? seHop.delta;
    if (rowDelta == null || rowDelta == 0) {
      return false;
    }
    if ((drawingHop.delta ?? rowDelta) != rowDelta ||
        (seHop.delta ?? rowDelta) != rowDelta) {
      return false;
    }
    MultiRowRangeMovePlan? plan;
    if (drawingSourceIds.isNotEmpty) {
      plan = planMultiRowRangeMove(
        orderedLayers: lattice,
        sourceLayerIds: selection.spanLayerIds,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
        rowDelta: rowDelta,
      );
      if (plan == null) {
        // An illegal rigid landing HOLDS the last valid preview (R23 #10).
        return true;
      }
    }
    final sePlans = sePassengerIds.isEmpty
        ? const <SeRowMovePair>[]
        : _planMultiRowSePassengers(
            seSourceIds: sePassengerIds,
            seLattice: seLattice,
            selection: selection,
            frameDelta: frameDelta,
            rowDelta: rowDelta,
          );
    if (sePlans == null) {
      return true; // An SE passenger cannot land — the whole move voids.
    }
    if (plan == null && sePlans.isEmpty) {
      return false; // Nothing to carry — the plain slide owns the step.
    }
    // R27 #8: the frame-axis riders shift with the same frame delta. A
    // rider that cannot shift voids the move like any other passenger.
    Map<int, CameraPose>? cameraShifted;
    if (cameraRides) {
      cameraShifted = shiftCameraKeysInRange(
        keyframes: activeCutOrNull?.camera.keyframes ?? const {},
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (cameraShifted == null) {
        return true;
      }
    }
    final instructionShifted = <LayerId, Map<int, InstructionEvent>>{};
    for (final layer in instructionRiders) {
      final shifted = shiftInstructionEventsInRange(
        events: layer.instructions,
        rangeStartIndex: selection.startIndex,
        rangeEndIndexExclusive: selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (shifted == null) {
        return true;
      }
      instructionShifted[layer.id] = shifted;
    }
    // A valid rigid landing supersedes the slide / row-change plans.
    _rangeMoveMultiRowPlan = plan;
    _rangeMoveMultiSeRowChanges = sePlans.isEmpty ? null : sePlans;
    _rangeMoveMultiPlans = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _rangeMoveCameraShifted = cameraShifted;
    _rangeMoveInstructionShifted = instructionShifted.isEmpty
        ? null
        : instructionShifted;
    _cameraKeysDragPreview = cameraShifted;
    dragPreview.value = BlockMoveDragPreview(
      previewLayers: {
        if (plan != null)
          for (final entry in plan.layersAfter.entries)
            entry.key: rederiveRunBehaviors(
              entry.value,
              cutFrameCount: _activeCutFrameCount,
            ),
        for (final se in sePlans) ...{
          se.sourceId: trackSeWindow.displayLayer(se.sourceAfter),
          se.targetId: trackSeWindow.displayLayer(se.targetAfter),
        },
        // R27 #8: the frame-axis riders preview their shifted spans in
        // place (the cells row renders straight off layer.instructions).
        for (final entry in instructionShifted.entries)
          if (_layerById(entry.key) != null)
            entry.key: _layerById(
              entry.key,
            )!.copyWith(instructions: entry.value),
      },
      // C2: the SE passengers' global forms, for the storyboard strips.
      previewGlobalLayers: {
        for (final se in sePlans) ...{
          se.sourceId: se.sourceAfter,
          se.targetId: se.targetAfter,
        },
      },
      cameraCutId: cameraShifted == null ? null : activeCutOrNull?.id,
      cameraKeyframes: cameraShifted,
      // A FRESH CLONE per step (the P3b-2 contract) — the gate compares
      // identities, and the repository instance trips nothing (B4-①: the
      // multi-row rigid path was the one place still handing it over raw,
      // so a union drag spanning rows froze the camera's markers).
      cameraMarkerLayer:
          cameraShifted == null || _rangeMoveCameraLayerId == null
          ? null
          : _layerById(_rangeMoveCameraLayerId!)?.copyWith(),
    );
    // C1: the transition channel follows every published step — this
    // path's shift map never carries a transition entry, so the write is
    // the CLEAR that keeps a stale plain-slide form from lingering.
    _publishRangeMoveTransitionPreview(instructionShifted);
    // The outline rides the rigid shift to the target rows (rows that
    // carried nothing — off the lattice or shifted off it — drop out of
    // the outline; only the moved frames' landings read selected).
    final indexById = {
      for (var i = 0; i < lattice.length; i += 1) lattice[i].id: i,
    };
    final seIndexById = {
      for (var i = 0; i < seLattice.length; i += 1) seLattice[i].id: i,
    };
    final landedLayerIds = [
      for (final id in selection.spanLayerIds)
        if (indexById[id] case final index?
            when index + rowDelta >= 0 && index + rowDelta < lattice.length)
          lattice[index + rowDelta].id
        else if (seIndexById[id] case final index?
            when index + rowDelta >= 0 && index + rowDelta < seLattice.length)
          seLattice[index + rowDelta].id,
    ];
    final newStart = selection.startIndex + frameDelta;
    if (newStart >= 0) {
      _rangeMoveSelection = TimelineFrameRangeSelection(
        layerId: targetLayerId,
        startIndex: newStart,
        endIndexExclusive: selection.endIndexExclusive + frameDelta,
        layerIds: landedLayerIds,
      );
    }
    return true;
  }

  /// Plans the SE passengers of a multi-row rigid move (R26 #2): every
  /// track-SE row in [seSourceIds] shifts [rowDelta] rows inside the SE
  /// lattice, carrying its selected blocks (and their audio clips, which
  /// anchor to the cels). Null when ANY passenger cannot land — the whole
  /// move voids, the multi-row all-or-nothing rule.
  List<SeRowMovePair>? _planMultiRowSePassengers({
    required List<LayerId> seSourceIds,
    required List<Layer> seLattice,
    required TimelineFrameRangeSelection selection,
    required int frameDelta,
    required int rowDelta,
  }) {
    final sourceIndexes = <int>{
      for (final id in seSourceIds) seLattice.indexWhere((l) => l.id == id),
    };
    if (sourceIndexes.contains(-1)) {
      return null;
    }
    final plans = <SeRowMovePair>[];
    for (final sourceId in seSourceIds) {
      final sourceIndex = seLattice.indexWhere((l) => l.id == sourceId);
      final targetIndex = sourceIndex + rowDelta;
      if (targetIndex < 0 || targetIndex >= seLattice.length) {
        return null; // Off the SE lattice.
      }
      if (sourceIndexes.contains(targetIndex)) {
        return null; // A chained/swapped landing — voided rather than
        // ordered (two SE rows never shift the same delta legally).
      }
      final source = seLattice[sourceIndex];
      final target = seLattice[targetIndex];
      final offset = _rangeMoveCommitOffset(sourceId, selection.startIndex);
      final plan = planSeRangeRowMove(
        source: source,
        target: target,
        rangeStartIndex: selection.startIndex + offset,
        rangeEndIndexExclusive: selection.endIndexExclusive + offset,
        frameDelta: frameDelta,
      );
      if (plan == null) {
        return null;
      }
      plans.add((
        sourceId: sourceId,
        targetId: target.id,
        sourceBefore: source,
        sourceAfter: plan.sourceAfter,
        targetBefore: target,
        targetAfter: plan.targetAfter,
      ));
    }
    return plans;
  }

  /// R28 #5: returns the drag preview to the block's REAL position.
  ///
  /// `planDrawingRangeMove` answers null for two different questions —
  /// "impossible" and "no movement" (frameDelta 0, or a landing back on
  /// the group's own start). The drag step read every null as blocked and
  /// so HELD the last valid preview (UI-R23 #10, which is right for a
  /// blocked landing). A drag that went right and came back therefore
  /// froze one step out and refused to reach home: "더 이상 왼쪽으로 이동이
  /// 안먹혀버리고 그 자리에서 멈춰버린다". Zero delta is not a blocked
  /// landing — it is the origin, and the preview must show it.
  void _resetRangeMovePreviewToOrigin() {
    _rangeMovePlan = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _cameraKeysDragPreview = null;
    dragPreview.value = null;
    transitionEdgeDragPreview.value = null;
    final selection = _rangeMoveSelectionBefore;
    if (selection != null) {
      _rangeMoveSelection = selection;
    }
  }

  /// C1 (2026-08-17): the in-flight form of a range-moved TRANSITION row,
  /// published on [transitionEdgeDragPreview] — the channel the row's edge
  /// drags already preview on and the storyboard's transition strip
  /// already renders. One preview channel per row family: the move joins
  /// the edge drag instead of growing a second gate.
  ///
  /// A step whose shift map carries no transition entry CLEARS the channel
  /// (a null write on an already-null notifier is a silent no-op), so an
  /// ordinary cell move can never leave a stale transition form standing.
  void _publishRangeMoveTransitionPreview(
    Map<LayerId, Map<int, InstructionEvent>> instructionShifted,
  ) {
    Layer? preview;
    for (final entry in instructionShifted.entries) {
      final owner = _trackTransitionOwner(entry.key);
      if (owner != null) {
        preview = owner.transitionLayer.copyWith(
          instructions: SplayTreeMap<int, InstructionEvent>.from(entry.value),
        );
      }
    }
    transitionEdgeDragPreview.value = preview;
  }

  /// A range-move drag step: live preview on [dragPreview] (repository
  /// untouched), the selection outline riding the previewed landing.
  void updateFrameRangeMoveDrag({
    required int frameDelta,
    LayerId? targetLayerId,
  }) {
    final selection = _rangeMoveSelectionBefore;
    final multiSources = _rangeMoveMultiSources;
    // R28 #5: back at the start = the origin, not a refusal. A row change
    // still owns the step (a delta-0 drop onto a sibling row is a real
    // move), so only same-row zero deltas reset.
    if (selection != null &&
        frameDelta == 0 &&
        (targetLayerId == null ||
            targetLayerId == selection.layerId ||
            targetLayerId == _rangeMoveGrabLayerId)) {
      _resetRangeMovePreviewToOrigin();
      return;
    }
    if (selection != null && multiSources != null) {
      // ROW-CHANGE drops within the SE / camera sections (P3b-4, 같은
      // 섹션 행이동): a single-row track-SE selection may land on a
      // sibling SE row, an instruction selection on a sibling
      // instruction row — the handler owns the step then (an incompatible
      // hover HOLDS the last valid landing, UI-R23 #10).
      if (targetLayerId != null &&
          targetLayerId != selection.layerId &&
          selection.spanLayerIds.length == 1 &&
          _updateRangeRowChangeDrag(selection, frameDelta, targetLayerId)) {
        return;
      }
      // MULTI-ROW rigid move (UI-R23 #9): a multi-layer drawing selection
      // dragged onto a different row carries every selected row together.
      if (targetLayerId != null &&
          selection.spanLayerIds.length > 1 &&
          _updateMultiRowRangeMove(selection, frameDelta, targetLayerId)) {
        return;
      }
      // Falling to the plain slide: any prior row-change / multi-row plan
      // is stale now (the slide, not the row change, is last valid).
      _rangeMoveSeRowChange = null;
      _rangeMoveInstructionRowChange = null;
      _rangeMoveMultiRowPlan = null;
      _rangeMoveMultiSeRowChanges = null;
      // Cross-layer slide (UI-R18 #1): every spanned layer plans the SAME
      // frame delta on itself; any illegal landing HOLDS the last valid
      // preview (all-or-nothing, the single-layer discipline). KEY
      // sources (P3b-2) join the same contract: camera keys and
      // instruction spans shift by the same delta or the whole move
      // voids.
      var illegal = false;
      final plans = <DrawingBlockMovePlan>[];
      for (final source in multiSources) {
        final plan = planDrawingRangeMove(
          source: source.commit,
          target: source.commit,
          rangeStartIndex: selection.startIndex + source.offset,
          rangeEndIndexExclusive: selection.endIndexExclusive + source.offset,
          frameDelta: frameDelta,
          cutFrameCount: _activeCutFrameCount,
        );
        if (plan == null) {
          illegal = true;
          plans.clear();
          break;
        }
        plans.add(plan);
      }
      if (multiSources.isEmpty && frameDelta == 0) {
        illegal = true;
      }
      final cameraBefore = _rangeMoveCameraBefore;
      Map<int, CameraPose>? cameraShifted;
      if (!illegal && cameraBefore != null) {
        cameraShifted = shiftCameraKeysInRange(
          keyframes: cameraBefore,
          rangeStartIndex: selection.startIndex,
          rangeEndIndexExclusive: selection.endIndexExclusive,
          frameDelta: frameDelta,
        );
        illegal = cameraShifted == null;
      }
      final instructionShifted = <LayerId, Map<int, InstructionEvent>>{};
      if (!illegal) {
        for (final layer in _rangeMoveInstructionSources ?? const <Layer>[]) {
          final shifted = shiftInstructionEventsInRange(
            events: layer.instructions,
            rangeStartIndex: selection.startIndex,
            rangeEndIndexExclusive: selection.endIndexExclusive,
            frameDelta: frameDelta,
          );
          if (shifted == null) {
            illegal = true;
            break;
          }
          instructionShifted[layer.id] = shifted;
        }
      }
      if (illegal) {
        // UI-R23 #10: a blocked landing HOLDS the last valid preview,
        // outline and stored plans — no snap-back to the origin.
        return;
      }
      _rangeMoveMultiPlans = plans.isEmpty ? null : plans;
      _rangeMoveCameraShifted = cameraShifted;
      _rangeMoveInstructionShifted = instructionShifted.isEmpty
          ? null
          : instructionShifted;
      _cameraKeysDragPreview = cameraShifted;
      final cameraMarker = cameraShifted == null
          ? null
          : _layerById(_rangeMoveCameraLayerId!)?.copyWith();
      final previewLayers = <LayerId, Layer>{};
      // C2 (2026-08-17): the GLOBAL forms ride the same preview — the
      // storyboard's track-global SE strips resolve THIS map, exactly as
      // they resolve an edge drag's global form, so a move follows the
      // hand live there too instead of jumping on release.
      final previewGlobalLayers = <LayerId, Layer>{};
      for (final plan in plans) {
        // The commit form is computed ONCE; the display clone is that
        // form windowed (UI-R18 #1 seam) — the two can never disagree.
        final commitForm = rederiveRunBehaviors(
          plan.sourceAfter,
          cutFrameCount: _activeCutFrameCount,
        );
        if (isTrackSeLayerId(plan.sourceAfter.id)) {
          previewLayers[plan.sourceAfter.id] = trackSeWindow.displayLayer(
            commitForm,
          );
          previewGlobalLayers[plan.sourceAfter.id] = commitForm;
        } else {
          previewLayers[plan.sourceAfter.id] = commitForm;
        }
      }
      // Instruction rows preview with their shifted spans — the cells row
      // renders straight off layer.instructions. The track-owned
      // TRANSITION row is not a cut layer, so it is absent from
      // [_layerById] and skips this map; it previews on its own channel
      // below instead.
      for (final entry in instructionShifted.entries) {
        final layer = _layerById(entry.key);
        if (layer != null) {
          previewLayers[entry.key] = layer.copyWith(
            instructions: entry.value,
          );
        }
      }
      dragPreview.value = BlockMoveDragPreview(
        previewLayers: previewLayers,
        previewGlobalLayers: previewGlobalLayers,
        cameraCutId: cameraShifted == null ? null : activeCutOrNull?.id,
        cameraKeyframes: cameraShifted,
        cameraMarkerLayer: cameraMarker,
      );
      // C1 (2026-08-17): a moved TRANSITION row previews on the row's own
      // channel — the SAME one its edge drags publish to, which is what
      // the storyboard's transition strip already renders live.
      _publishRangeMoveTransitionPreview(instructionShifted);
      final newStart = selection.startIndex + frameDelta;
      if (newStart >= 0) {
        _rangeMoveSelection = TimelineFrameRangeSelection(
          layerId: selection.layerId,
          startIndex: newStart,
          endIndexExclusive: selection.endIndexExclusive + frameDelta,
          layerIds: selection.layerIds,
        );
      }
      return;
    }

    final source = _rangeMoveSourceBefore;
    final groupStart = _rangeMoveGroupStart;
    if (source == null || selection == null || groupStart == null) {
      return;
    }
    Layer? target = source;
    if (targetLayerId != null && targetLayerId != source.id) {
      target = _blockMoveEligible(targetLayerId)
          ? _layerById(targetLayerId)
          : null;
      // Cross-row drops stay within the SAME SECTION (UI-R20 #2 P3b-3:
      // 행이동도 같은 섹션 내 — animation/storyboard/image interchange
      // freely now; an animation range still never lands on the SE or
      // camera sections).
      if (target != null &&
          timelineSectionForLayerKind(target.kind) !=
              timelineSectionForLayerKind(source.kind)) {
        target = null;
      }
    }
    final plan = target == null
        ? null
        : planDrawingRangeMove(
            source: source,
            target: target,
            rangeStartIndex: selection.startIndex,
            rangeEndIndexExclusive: selection.endIndexExclusive,
            frameDelta: frameDelta,
            cutFrameCount: _activeCutFrameCount,
          );
    if (plan == null) {
      // UI-R23 #10: a blocked / incompatible landing HOLDS the last valid
      // preview, outline and plan — the move stops at the last legal spot
      // and resumes on a legal return (no snap-back to the origin).
      return;
    }
    _rangeMovePlan = plan;
    dragPreview.value = BlockMoveDragPreview(
      previewLayers: {
        plan.sourceAfter.id: rederiveRunBehaviors(
          plan.sourceAfter,
          cutFrameCount: _activeCutFrameCount,
        ),
        if (plan.targetAfter != null)
          plan.targetAfter!.id: rederiveRunBehaviors(
            plan.targetAfter!,
            cutFrameCount: _activeCutFrameCount,
          ),
      },
    );
    // The selection outline follows the previewed landing live.
    final landedLayerId = plan.isCrossLayer ? plan.targetAfter!.id : source.id;
    final startShift = plan.destinationStartIndex - groupStart;
    final newStart = selection.startIndex + startShift;
    if (newStart >= 0) {
      _rangeMoveSelection = TimelineFrameRangeSelection(
        layerId: landedLayerId,
        startIndex: newStart,
        endIndexExclusive: selection.endIndexExclusive + startShift,
      );
    }
  }

  /// Commits the range move as ONE undo step (layer updates + the brush
  /// re-key on cross-layer carries), mirroring the block-move commit.
  void endFrameRangeMoveDrag() {
    final source = _rangeMoveSourceBefore;
    final selection = _rangeMoveSelectionBefore;
    final plan = _rangeMovePlan;
    final multiPlans = _rangeMoveMultiPlans;
    final multiSources = _rangeMoveMultiSources;
    final cameraShifted = _rangeMoveCameraShifted;
    final instructionShifted = _rangeMoveInstructionShifted;
    final seRowChange = _rangeMoveSeRowChange;
    final instructionRowChange = _rangeMoveInstructionRowChange;
    final multiRowPlan = _rangeMoveMultiRowPlan;
    final multiSeRowChanges = _rangeMoveMultiSeRowChanges;
    final landedSelection = _rangeMoveSelection;
    _rangeMoveSourceBefore = null;
    _rangeMoveSelectionBefore = null;
    _rangeMoveGrabLayerId = null;
    _rangeMoveGroupStart = null;
    _rangeMovePlan = null;
    _rangeMoveMultiSources = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraBefore = null;
    _rangeMoveCameraLayerId = null;
    _rangeMoveInstructionSources = null;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _cameraKeysDragPreview = null;
    dragPreview.value = null;
    transitionEdgeDragPreview.value = null;
    // ROW-CHANGE commits (P3b-4): the planned pair replaces both rows in
    // one composite undo; the selection follows the landing row.
    if (selection != null && seRowChange != null) {
      _historyManager.execute(
        CompositeCommand(
          description: 'Move frame range',
          commands: [
            UpdateLayerTimelineCommand(
              repository: _repository,
              before: seRowChange.sourceBefore,
              after: seRowChange.sourceAfter,
            ),
            UpdateLayerTimelineCommand(
              repository: _repository,
              before: seRowChange.targetBefore,
              after: seRowChange.targetAfter,
            ),
          ],
        ),
      );
      _rangeMoveSelection = landedSelection;
      _layerController.selectLayer(seRowChange.targetId);
      _warmActiveCut();
      notifyListeners();
      return;
    }
    if (selection != null && instructionRowChange != null) {
      final cut = activeCutOrNull;
      if (cut != null) {
        _historyManager.execute(
          CompositeCommand(
            description: 'Move frame range',
            commands: [
              UpdateLayerInstructionsCommand(
                repository: _repository,
                cutId: cut.id,
                layerId: instructionRowChange.sourceId,
                instructions: instructionRowChange.sourceAfter,
                description: 'Move instruction keys',
              ),
              UpdateLayerInstructionsCommand(
                repository: _repository,
                cutId: cut.id,
                layerId: instructionRowChange.targetId,
                instructions: instructionRowChange.targetAfter,
                description: 'Move instruction keys',
              ),
            ],
          ),
        );
        _rangeMoveSelection = landedSelection;
        _layerController.selectLayer(instructionRowChange.targetId);
        _warmActiveCut();
        notifyListeners();
      } else {
        _rangeMoveSelection = selection;
      }
      return;
    }
    if (selection != null &&
        (multiRowPlan != null || multiSeRowChanges != null)) {
      // MULTI-ROW rigid move commit (UI-R23 #9): every affected drawing row
      // rewrites in one composite undo, and each cross-row cel re-keys its
      // brush frame to the target row. Track-SE passengers (R26 #2) join
      // the SAME undo step through their global-form layer pair.
      final cut = activeCutOrNull;
      final commands = <Command>[];
      for (final se in multiSeRowChanges ?? const <SeRowMovePair>[]) {
        commands.add(
          UpdateLayerTimelineCommand(
            repository: _repository,
            before: se.sourceBefore,
            after: se.sourceAfter,
          ),
        );
        commands.add(
          UpdateLayerTimelineCommand(
            repository: _repository,
            before: se.targetBefore,
            after: se.targetAfter,
          ),
        );
      }
      for (final entry
          in multiRowPlan?.layersAfter.entries ??
              const <MapEntry<LayerId, Layer>>[]) {
        final before = _layerById(entry.key);
        if (before == null) {
          continue;
        }
        final after = rederiveRunBehaviors(
          entry.value,
          cutFrameCount: _activeCutFrameCount,
        );
        if (after == before) {
          continue; // An untouched source/target row — no command.
        }
        commands.add(
          UpdateLayerTimelineCommand(
            repository: _repository,
            before: before,
            after: after,
          ),
        );
      }
      // R27 #8: the frame-axis riders (camera keys, instruction spans)
      // land in the SAME undo step as the rigid row move.
      if (cut != null && instructionShifted != null) {
        for (final entry in instructionShifted.entries) {
          commands.add(
            UpdateLayerInstructionsCommand(
              repository: _repository,
              cutId: cut.id,
              layerId: entry.key,
              instructions: entry.value,
              description: 'Move instruction keys',
            ),
          );
        }
      }
      if (cut != null && cameraShifted != null) {
        commands.add(
          UpdateCutCameraCommand(
            repository: _repository,
            cutId: cut.id,
            camera: CutCamera(keyframes: cameraShifted),
            description: 'Move camera keys',
          ),
        );
      }
      if (cut != null && (multiRowPlan?.rekeys.isNotEmpty ?? false)) {
        commands.add(
          RekeyBrushFramesCommand(
            store: brushFrameStore,
            pairs: [
              for (final rekey in multiRowPlan!.rekeys)
                (
                  brushFrameKeyForCut(cut, rekey.from, rekey.frameId),
                  brushFrameKeyForCut(cut, rekey.to, rekey.frameId),
                ),
            ],
          ),
        );
      }
      if (commands.isEmpty) {
        _rangeMoveSelection = selection;
        return;
      }
      _historyManager.execute(
        commands.length == 1
            ? commands.single
            : CompositeCommand(
                description: 'Move frame range',
                commands: commands,
              ),
      );
      _rangeMoveSelection = landedSelection;
      if (landedSelection != null) {
        _layerController.selectLayer(landedSelection.layerId);
      }
      _warmActiveCut();
      notifyListeners();
      return;
    }
    if (selection != null && multiSources != null) {
      // Cross-layer slide commit (UI-R18 #1) + key shifts (P3b-2): one
      // composite undo across blocks, camera keys and instruction spans.
      // (UI-R23 #3: the layer transform track no longer rides the slide.)
      final cut = activeCutOrNull;
      final commands = <Command>[
        if (multiPlans != null)
          for (var i = 0; i < multiPlans.length; i += 1)
            UpdateLayerTimelineCommand(
              repository: _repository,
              before: multiSources[i].commit,
              after: rederiveRunBehaviors(
                multiPlans[i].sourceAfter,
                cutFrameCount: _activeCutFrameCount,
              ),
            ),
        if (instructionShifted != null)
          for (final entry in instructionShifted.entries)
            // C1 (2026-08-17): the TRANSITION row's shifted spans land
            // through the row's own track-owned writer (the edge drags'
            // command) — it has no cut to be addressed by, so the cut
            // gate below must not swallow it. Cut-local instruction rows
            // keep the cut-addressed command they always had.
            if (_trackTransitionOwner(entry.key) case final owner?)
              UpdateTrackTransitionLayerCommand(
                repository: _repository,
                trackId: owner.id,
                before: owner.transitionLayer,
                after: owner.transitionLayer.copyWith(
                  instructions: SplayTreeMap<int, InstructionEvent>.from(
                    entry.value,
                  ),
                ),
                label: 'Move transition',
              )
            else if (cut != null)
              UpdateLayerInstructionsCommand(
                repository: _repository,
                cutId: cut.id,
                layerId: entry.key,
                instructions: entry.value,
                description: 'Move instruction keys',
              ),
        if (cameraShifted != null && cut != null)
          UpdateCutCameraCommand(
            repository: _repository,
            cutId: cut.id,
            camera: CutCamera(keyframes: cameraShifted),
            description: 'Move camera keys',
          ),
      ];
      if (commands.isEmpty) {
        _rangeMoveSelection = selection;
        return;
      }
      _historyManager.execute(
        commands.length == 1
            ? commands.single
            : CompositeCommand(
                description: 'Move frame range',
                commands: commands,
              ),
      );
      _rangeMoveSelection = landedSelection;
      _warmActiveCut();
      notifyListeners();
      return;
    }
    if (source == null || selection == null) {
      return;
    }
    if (plan == null) {
      _rangeMoveSelection = selection;
      return;
    }
    _historyManager.execute(
      _singleRowMoveCommand(
        plan,
        source: source,
        description: 'Move frame range',
      ),
    );
    // The selection stays on the moved frames where they landed.
    _rangeMoveSelection = landedSelection;
    if (plan.isCrossLayer) {
      _layerController.selectLayer(plan.targetAfter!.id);
    }
    _warmActiveCut();
    notifyListeners();
  }

  /// Drops an in-flight range-move preview, restoring the selection.
  void cancelFrameRangeMoveDrag() {
    final selection = _rangeMoveSelectionBefore;
    _rangeMoveSourceBefore = null;
    _rangeMoveSelectionBefore = null;
    _rangeMoveGrabLayerId = null;
    _rangeMoveGroupStart = null;
    _rangeMovePlan = null;
    _rangeMoveMultiSources = null;
    _rangeMoveMultiPlans = null;
    _rangeMoveMultiRowPlan = null;
    _rangeMoveMultiSeRowChanges = null;
    _rangeMoveCameraBefore = null;
    _rangeMoveCameraLayerId = null;
    _rangeMoveInstructionSources = null;
    _rangeMoveCameraShifted = null;
    _rangeMoveInstructionShifted = null;
    _rangeMoveSeRowChange = null;
    _rangeMoveInstructionRowChange = null;
    _cameraKeysDragPreview = null;
    dragPreview.value = null;
    transitionEdgeDragPreview.value = null;
    if (selection != null) {
      _rangeMoveSelection = selection;
    }
  }

  // --- Run-edge NEW FRAMES drag (UI-R8 [+] handle) --------------------------

  /// The in-flight "+ add frames" drag ([RunFramesAddDrag]), or null. The
  /// deterministic id reservation that keeps preview == commit lives on
  /// the drag class.
  RunFramesAddDrag? _runFramesAddDrag;

  /// Starts a "+ add frames" drag at the run edge (UI-R8): [atEnd] picks
  /// the side. Returns false when the row stands down or there is no run.
  bool beginRunFramesAddDrag({
    required LayerId layerId,
    required int blockStartIndex,
    required bool atEnd,
  }) {
    final drag = RunFramesAddDrag.begin(
      layerId: layerId,
      blockStartIndex: blockStartIndex,
      atEnd: atEnd,
      blockMoveEligible: _blockMoveEligible,
      layerById: _layerById,
      tracksNow: () => _repository.requireProject().tracks,
      activeCutFrameCount: () => _activeCutFrameCount,
      preview: dragPreview,
      commitLayerDrag: ({required before, required after}) {
        _timelineController.commitLayerTimelineDrag(
          before: before,
          after: after,
        );
        _warmActiveCut();
        notifyListeners();
      },
    );
    if (drag == null) {
      // A refused grip leaves an in-flight drag exactly as it was.
      return false;
    }
    _runFramesAddDrag = drag;
    return true;
  }

  void updateRunFramesAddDrag(int count) => _runFramesAddDrag?.update(count);

  void endRunFramesAddDrag() {
    _runFramesAddDrag?.commit();
    _runFramesAddDrag = null;
  }

  void cancelRunFramesAddDrag() {
    _runFramesAddDrag?.cancel();
    _runFramesAddDrag = null;
  }

  // --- Run-edge properties (UI-R9 #10 N/H/R tags) ----------------------------

  /// The run-behavior fill boundary (hold/repeat edges fill to the cut
  /// end); zero without a cut.
  int get _activeCutFrameCount => activeCutOrNull?.duration ?? 0;

  /// Whether the live frame-range selection can SCOPE a repeat pattern on
  /// this run edge (UI-R10 #5 rules: the selection must cover the edge
  /// block and cut the run short of the other end) — the tag flyout shows
  /// its explicit "Repeat selection" entry from this (UI-R19 #2).
  bool canScopeRepeatToSelection({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineRunEdgeSide side,
  }) {
    final layer = _layerById(layerId);
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

  /// Sets or clears the [side] edge property of the glued run containing
  /// [blockStartIndex] (UI-R9 #10): `mode` null = None. With
  /// [scopeToSelection] (the flyout's explicit "Repeat selection" entry,
  /// UI-R19 #2), Repeat captures the current frame-range selection as its
  /// pattern when the selection covers the run's edge block (end side:
  /// selection start → run end; start side: run start → selection end);
  /// otherwise — and always when [scopeToSelection] is false — the whole
  /// run cycles. Ghosts always fill to the cut boundary. One undo step,
  /// committed immediately.
  void setRunEdgeBehavior({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineRunEdgeSide side,
    TimelineRunEdgeMode? mode,
    bool scopeToSelection = true,
  }) {
    if (!_blockMoveEligible(layerId)) {
      return;
    }
    final before = _layerById(layerId);
    if (before == null) {
      return;
    }
    // Design E: the storyboard row refuses repeat/hold regions outright —
    // a derived instance would look exactly like a panel while owning no
    // memo of its own. Copy the frames instead.
    if (!layerKindAcceptsRepeatRegions(before.kind)) {
      return;
    }
    final run = gluedRunAt(before, blockStartIndex);
    if (run == null) {
      return;
    }

    // Replace any behavior already sitting on this (run, side).
    bool ownsThisEdge(TimelineRunBehavior behavior) {
      if (behavior.side != side) {
        return false;
      }
      for (final entry in before.timeline.entries) {
        if (entry.value.ghost ||
            entry.value.frameId != behavior.anchorFrameId) {
          continue;
        }
        return entry.key >= run.startIndex && entry.key < run.endIndexExclusive;
      }
      return false;
    }

    FrameId? patternAnchor;
    if (mode == TimelineRunEdgeMode.repeat && scopeToSelection) {
      final selection = frameRangeSelection.value;
      if (selection != null && selection.layerId == layerId) {
        if (side == TimelineRunEdgeSide.end &&
            selection.contains(run.endIndexExclusive - 1) &&
            selection.startIndex > run.startIndex) {
          // Pattern = first block at/after the selection start → run end.
          for (final entry in before.timeline.entries) {
            if (!entry.value.ghost &&
                entry.key >= selection.startIndex &&
                entry.key < run.endIndexExclusive) {
              patternAnchor = entry.value.frameId;
              break;
            }
          }
        } else if (side == TimelineRunEdgeSide.start &&
            selection.contains(run.startIndex) &&
            selection.endIndexExclusive < run.endIndexExclusive) {
          // Pattern = run start → the last block ending by the selection.
          for (final entry in before.timeline.entries) {
            if (entry.value.ghost ||
                entry.key < run.startIndex ||
                entry.key >= selection.endIndexExclusive) {
              continue;
            }
            patternAnchor = entry.value.frameId;
          }
        }
      }
    }

    // The behavior anchors to its EDGE block (UI-R10 #4): the end side to
    // the run's LAST block, the start side to the FIRST — splitting the
    // run keeps the property with the fragment that owns that edge.
    var edgeAnchor = run.anchorFrameId;
    if (side == TimelineRunEdgeSide.end) {
      for (final entry in before.timeline.entries) {
        if (entry.value.ghost ||
            entry.key < run.startIndex ||
            entry.key >= run.endIndexExclusive) {
          continue;
        }
        edgeAnchor = entry.value.frameId!;
      }
    }
    final behaviors = [
      for (final behavior in before.runBehaviors)
        if (!ownsThisEdge(behavior)) behavior,
      if (mode != null)
        TimelineRunBehavior(
          anchorFrameId: edgeAnchor,
          side: side,
          mode: mode,
          patternAnchorFrameId: patternAnchor,
        ),
    ];
    final after = rederiveRunBehaviors(
      before.copyWith(runBehaviors: behaviors),
      cutFrameCount: _activeCutFrameCount,
    );
    if (after == before) {
      return;
    }
    _timelineController.commitLayerTimelineDrag(before: before, after: after);
    _warmActiveCut();
    notifyListeners();
  }

  Layer? _layerById(LayerId layerId) {
    for (final layer in layers) {
      if (layer.id == layerId) {
        return layer;
      }
    }
    return null;
  }

  /// The "edit the owner" cursor pill for a grab that landed on a SYNCED
  /// attach row: the synced-block UI makes those rows look like ordinary
  /// blocks, so a refused drag must SAY why instead of dying silently
  /// (the pre-block ghost rows never invited the drag in the first place).
  void _noticeSyncedAttachRefusal(LayerId layerId) {
    if (_isSyncedAttachedLayerId(layerId)) {
      cursorNotices.show(AppText.strings.noticeEditAttachOwner);
    }
  }

  /// Whether [layerId] names a SINGLE-CEL (image) row of the active cut:
  /// its one covering block is pinned by the write normalization, so the
  /// reshaping verbs (range move, push/pull, comma set, X-here) stand
  /// down — committing them would be reverted in the same write, leaving
  /// a phantom no-op on the undo stack.
  bool _isSingleCelLayerId(LayerId layerId) {
    final layer = _layerById(layerId);
    return layer != null && layerKindHoldsSingleCel(layer.kind);
  }

  /// Whether [layerId] names one of the active cut's SYNCED attach rows —
  /// the timing standdowns key off THIS (free attach rows author their
  /// own timeline like any drawing layer, UI-R21 #3).
  bool _isSyncedAttachedLayerId(LayerId layerId) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return false;
    }
    for (final layer in cut.layers) {
      if (layer.id == layerId) {
        return isSyncedAttachedLayer(layer);
      }
    }
    return false;
  }

  bool get canToggleMarkAtCurrentFrame {
    final layer = activeLayer;
    // SYNCED attach rows carry no cell marks (the base's sheet row
    // does); free attach rows mark like normal (UI-R21 #3).
    if (layer == null ||
        !layerKindHoldsDrawings(layer.kind) ||
        isSyncedAttachedLayer(layer)) {
      return false;
    }

    return _timelineController.canToggleMarkAt(
      layer: layer,
      frameIndex: _timelineController.currentFrameIndex,
    );
  }

  void toggleMarkAtCurrentFrame() {
    final layer = activeLayer;
    if (layer == null || !canToggleMarkAtCurrentFrame) {
      return;
    }

    _timelineController.toggleMarkForLayer(layerId: layer.id);
    notifyListeners();
  }

  bool get canRenameFrameAtCurrentFrame {
    final layer = activeLayer;
    if (layer == null) {
      return false;
    }

    return _timelineController.canRenameFrameAt(
      layer: layer,
      frameIndex: _timelineController.currentFrameIndex,
    );
  }

  /// 🚨T25 — whether the CELL under the playhead has an instance editor.
  ///
  /// ⚠️Kind-aware, because 「인스턴스」 is not one thing: a drawing cell's is
  /// its NAME, a camera or direction cell's is the key/event dialog, an SE
  /// cell's is the entry — or the creation of one. This lived in the
  /// toolbar as a private getter while the button was hard-wired to cells;
  /// [editInstanceSubject] asked [canRenameFrameAtCurrentFrame] instead, and
  /// the two disagreed for every non-drawing kind. The button stayed lit and
  /// the press did nothing, which is the worst of the three possible
  /// answers. One question, one getter.
  ///
  /// ⛔The HOST's answer is deliberately not folded in: the storyboard's
  /// standing row is separate state from its drawing target (유저
  /// 2026-07-27), so no session getter can see it.
  bool get canEditCellInstanceAtCurrentFrame {
    final layer = activeLayer;
    if (layer == null) {
      return false;
    }
    // Standing on a LANE row, the instance is that lane's KEY — which the
    // owning layer's kind cannot answer.
    if (canNameLaneKeys) {
      return true;
    }
    return switch (layer.kind) {
      LayerKind.camera || LayerKind.instruction => hasActiveNonNegativeCell,
      LayerKind.se =>
        selectedFrame != null || canCreateDrawingAtCurrentFrame,
      _ => canRenameFrameAtCurrentFrame,
    };
  }

  /// 🚨T25 — WHAT the one Edit Instance button would rename right now.
  ///
  /// 유저 확정 2026-08-14: 「인스턴스 편집 버튼도 공통버튼으로 이동. 그래서
  /// **선택범위 통해 동사통일화** 가능하게.」
  ///
  /// ★Deliberately the SAME ladder as [deleteSubject], in the same order and
  /// for the same reason. Two shared-pill verbs that both ask 「지금 무엇이
  /// 선택됐나」 and answer it differently would be a rule the user has to
  /// hold two versions of.
  ///
  /// ⚠️Where the two DIFFER is only in the predicate each rung uses:
  /// deleting asks what is deletable, renaming asks what is renameable, and
  /// those are not the same set (a camera row selects and renames but does
  /// not delete).
  EditInstanceSubject get editInstanceSubject {
    if (trackFrameRangeSelection.value != null) {
      return EditInstanceSubject.cuts;
    }
    if (renameableSelectedLayerIds().isNotEmpty) {
      return EditInstanceSubject.layers;
    }
    return canEditCellInstanceAtCurrentFrame
        ? EditInstanceSubject.cells
        : EditInstanceSubject.nothing;
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
  DeleteSubject get deleteSubject {
    if (trackFrameRangeSelection.value != null) {
      return DeleteSubject.cuts;
    }
    // ⑨: rows outrank cells. A row selection is the more specific statement
    // — you named the rows out loud — while the cell rung answers from where
    // the playhead happens to stand.
    if (deletableSelectedLayerIds().isNotEmpty) {
      return DeleteSubject.layers;
    }
    return canDeleteCellAtCurrentFrame
        ? DeleteSubject.cells
        : DeleteSubject.nothing;
  }

  /// Runs whatever [deleteSubject] names. One undo step either way — the cell
  /// path already composes its own.
  void deleteSelectionSubject() {
    switch (deleteSubject) {
      case DeleteSubject.cuts:
        deleteActiveCut();
      case DeleteSubject.layers:
        deleteSelectedLayers();
      case DeleteSubject.cells:
        deleteCellAtCurrentFrame();
      case DeleteSubject.nothing:
        break;
    }
  }

  /// The SELECTION-borne rungs of the cell delete, alone (B8): lane keys
  /// under the lane-verb context, or a live selection's real blocks —
  /// either axis. [deleteCellAtCurrentFrame] dispatches both before it ever
  /// asks the active layer, so a caller gated on THIS can hand the press to
  /// that verb without the active-layer rung becoming reachable.
  bool get canDeleteCellForSelection =>
      // R10 #19: the same rule Add follows — when the subject is a PROPERTY
      // row, Delete removes its keys, not a cel. It also closes a gap the
      // other way round: a live LANE span used to fall through to the cell
      // path and delete the active layer's cel instead of the keys under it.
      _laneVerbRangeHasKeys ||
      // A live selection is deletable wherever the playhead stands (UI-R17
      // #2).
      _selectionBlockStartsByLayer() != null;

  bool get canDeleteCellAtCurrentFrame {
    if (canDeleteCellForSelection) {
      return true;
    }
    final layer = activeLayer;
    // SYNCED attach rows: cel removal is out of v1 scope (delete the row
    // or undo the creation) — cells are display material there. Free
    // attach rows delete cells like normal (UI-R21 #3).
    if (layer == null || isSyncedAttachedLayer(layer)) {
      return false;
    }

    return _timelineController.canDeleteCellAt(
      layer: layer,
      frameIndex: _timelineController.currentFrameIndex,
    );
  }

  String? get selectedFrameName => selectedFrame?.name;

  /// SE rows: the selected entry's speaker/effect name (the accent box).
  String? get selectedFrameSeName => selectedFrame?.seName;

  /// The sounds the SELECTED SE instance carries, each with the index it
  /// sits at in its layer's clip list (R5 #19 — the instance editor shows
  /// what a block is linked to, and lets you take it off).
  ///
  /// The index travels with the clip because [removeAudioClipAt] addresses
  /// by position: a clip has no id of its own, and looking it up again
  /// afterwards would search a list that just changed.
  List<({AudioClip clip, int index})> get selectedSeAudioClips {
    final layer = activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null) {
      return const [];
    }
    return [
      for (var index = 0; index < layer.audioClips.length; index += 1)
        if (layer.audioClips[index].frameId == frame.id)
          (clip: layer.audioClips[index], index: index),
    ];
  }

  /// Takes the sounds at [clipIndexes] off the ACTIVE layer in one step —
  /// the instance editor's unlink, which can drop several at once and must
  /// be one undo with them.
  ///
  /// Descending removal: every index is into the list as it stands NOW, and
  /// removing a low one would shift the rest.
  void unlinkAudioClipsFromActiveLayer(Iterable<int> clipIndexes) {
    final layer = activeLayer;
    if (layer == null) {
      return;
    }
    unlinkAudioClipsFromLayer(layer.id, clipIndexes);
  }

  /// The same unlink addressed by ROW (B6 2026-08-17): the storyboard's SE
  /// instance editor takes sounds off a TRACK fixture whose row is never
  /// the drawing target. One removal body with the active form above.
  void unlinkAudioClipsFromLayer(LayerId layerId, Iterable<int> clipIndexes) {
    final layer = requireLayerAnywhere(_repository.requireProject(), layerId);
    final ordered = clipIndexes.toList()..sort((a, b) => b.compareTo(a));
    final next = [...layer.audioClips];
    for (final index in ordered) {
      if (index >= 0 && index < next.length) {
        next.removeAt(index);
      }
    }
    if (next.length == layer.audioClips.length) {
      return;
    }
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: activeCutOrNull?.id,
      layerId: layerId,
      audioClips: next,
      description: 'Unlink audio',
    );
    notifyListeners();
  }

  /// Applies a rename to the currently selected frame.
  ///
  /// Returns `null` when the rename was applied (or was not possible). When the
  /// new [name] collides with another frame, returns that frame's id without
  /// mutating so the caller can offer to link instead (see [linkSelectedFrame]).
  /// SE rows are exempt from the collision rule — the same dialogue can
  /// legitimately repeat on a sheet, so duplicates just apply.
  FrameId? renameSelectedFrame(String name) {
    final layer = activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null || !canRenameFrameAtCurrentFrame) {
      return null;
    }

    final allowDuplicateName = layer.kind == LayerKind.se;
    if (!allowDuplicateName) {
      final conflictingFrameId = _timelineController
          .conflictingFrameIdForRename(
            layer: layer,
            frameId: frame.id,
            name: name,
          );
      if (conflictingFrameId != null) {
        return conflictingFrameId;
      }
    }

    _timelineController.renameFrameForLayer(
      layerId: layer.id,
      frameId: frame.id,
      name: name,
      allowDuplicateName: allowDuplicateName,
    );
    notifyListeners();
    return null;
  }

  /// Creates an SE entry at the current cell carrying [name] (the sheet's
  /// dialogue text) and the optional [seName] (speaker/effect, the accent
  /// box) in ONE undo step. The entry takes [lengthFrames] (the dialog's
  /// length input); null falls back to filling to the cut end (legacy).
  ///
  /// The cut end no longer clamps the length (SE globalization): a sound
  /// may run past it — the `~` crossing mark says so — and the NEXT
  /// entry bounds the length in the controller, on the global axis, so
  /// the neighbouring cuts' sounds count as walls too.
  void createSeEntryAtCurrentFrame({
    required String name,
    String? seName,
    int? lengthFrames,
  }) {
    final layer = activeLayer;
    if (layer == null ||
        layer.kind != LayerKind.se ||
        !canCreateDrawingAtCurrentFrame) {
      return;
    }

    final remaining =
        requireActiveCut.duration - _timelineController.currentFrameIndex;
    final toCutEnd = remaining < 1 ? 1 : remaining;
    final requested = lengthFrames ?? toCutEnd;
    _frameSequence += 1;
    _timelineController.createDrawingFrameForLayer(
      layerId: layer.id,
      frameId: FrameId(_nextFrameId(layer.id)),
      length: requested < 1 ? 1 : requested,
      name: name,
      seName: seName,
    );
    notifyListeners();
  }

  /// SE rows: updates the selected entry's dialogue (Frame.name) and
  /// speaker name in ONE undo step. Duplicates are allowed — the same
  /// dialogue can legitimately repeat on a sheet.
  void updateSelectedSeEntry({required String dialogue, String? seName}) {
    final layer = activeLayer;
    final frame = selectedFrame;
    if (layer == null ||
        frame == null ||
        !canRenameFrameAtCurrentFrame) {
      return;
    }
    updateSeEntryForLayer(layer.id, frame.id, dialogue: dialogue, seName: seName);
  }

  /// The same edit addressed by ROW + ENTRY instead of by standing (B6
  /// 2026-08-17): the storyboard's SE editor commits here, because that
  /// rail's standing row never moves the drawing target (유저 2026-07-27)
  /// and so [activeLayer]/[selectedFrame] cannot carry its answer. The
  /// timeline's [updateSelectedSeEntry] funnels into this too — one commit
  /// body, two addressings.
  void updateSeEntryForLayer(
    LayerId layerId,
    FrameId frameId, {
    required String dialogue,
    String? seName,
  }) {
    final layer = requireLayerAnywhere(_repository.requireProject(), layerId);
    if (layer.kind != LayerKind.se) {
      return;
    }
    _timelineController.renameFrameForLayer(
      layerId: layerId,
      frameId: frameId,
      name: dialogue,
      allowDuplicateName: true,
      seName: seName,
      updateSeName: true,
    );
    notifyListeners();
  }

  void linkSelectedFrame(FrameId targetFrameId) {
    final layer = activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null) {
      return;
    }

    _timelineController.linkFrameForLayer(
      layerId: layer.id,
      sourceFrameId: frame.id,
      targetFrameId: targetFrameId,
    );
    notifyListeners();
  }

  void deleteCellAtCurrentFrame() {
    // R10 #19: a property row is its own subject — see
    // [canDeleteCellAtCurrentFrame].
    final lane = _laneVerbRange;
    if (lane != null && _removeLaneKeysForSelection(lane)) {
      return;
    }
    // A live selection routes the delete to EVERY selected block on
    // EVERY spanned layer (UI-R17 #2/#8, one composite undo); the
    // leftover selection covers empty cells so it clears with the delete.
    final selectionTargets = _selectionBlockStartsByLayer();
    if (selectionTargets != null) {
      _timelineController.deleteBlocksForLayers(selectionTargets);
      // Whichever axis answered: the leftover span covers empty cells now.
      clearFrameRangeSelection();
      clearStoryboardCutSelection();
      notifyListeners();
      return;
    }
    final layer = activeLayer;
    if (layer == null || !canDeleteCellAtCurrentFrame) {
      return;
    }

    _timelineController.deleteCellForLayer(layerId: layer.id);
    notifyListeners();
  }

  /// THE selection resolved to real block starts per layer, in COMMIT
  /// keys; null when neither selection holds real blocks anywhere.
  ///
  /// Whichever axis the live selection is in: the cut-local one maps its
  /// display starts onto the global axis for track-SE rows (UI-R18 #1),
  /// the track-global one is already stated in commit keys. The two are
  /// mutually exclusive, so at most one answers.
  Map<LayerId, List<int>>? _selectionBlockStartsByLayer() =>
      _cutLocalSelectionBlockStartsByLayer() ??
      _trackSelectionBlockStartsByLayer();

  Map<LayerId, List<int>>? _cutLocalSelectionBlockStartsByLayer() {
    final selection = frameRangeSelection.value;
    if (selection == null) {
      return null;
    }
    final byLayer = <LayerId, List<int>>{};
    for (final id in selection.spanLayerIds) {
      // SYNCED attach rows hold no editable blocks of their own — their
      // mirror blocks are non-ghost now (the synced-block UI), so without
      // this gate a mirror-only selection would light up delete/comma
      // verbs that then no-op against the stored-empty row.
      if (_isSyncedAttachedLayerId(id)) {
        continue;
      }
      final layer = _rangeLayerById(id);
      if (layer == null) {
        continue;
      }
      final starts = _selectionBlockStarts(
        layer,
        selection.startIndex,
        selection.endIndexExclusive,
      );
      if (starts.isNotEmpty) {
        byLayer[id] = [
          for (final start in starts) _commitBlockStart(id, start),
        ];
      }
    }
    return byLayer.isEmpty ? null : byLayer;
  }

  /// The storyboard's selection resolved the same way. Its LAYER rows are
  /// the track-SE rows, whose global layer is the commit layer AND the one
  /// the range is stated against — so there is nothing to translate here.
  /// (Its track row's blocks are cuts; deleting those is
  /// [deleteSelectedCuts]'s job, not a layer edit.)
  Map<LayerId, List<int>>? _trackSelectionBlockStartsByLayer() {
    final selection = trackFrameRangeSelection.value;
    if (selection == null) {
      return null;
    }
    final byLayer = <LayerId, List<int>>{};
    for (final row in selection.spanRows) {
      if (row is! LayerRowAddress) {
        continue;
      }
      final layer = trackSeGlobalLayerById(row.layerId);
      if (layer == null) {
        continue;
      }
      final starts = _selectionBlockStarts(
        layer,
        selection.startFrame,
        selection.endFrameExclusive,
      );
      if (starts.isNotEmpty) {
        byLayer[row.layerId] = starts;
      }
    }
    return byLayer.isEmpty ? null : byLayer;
  }

  // --- Comma set (UI-R17 #7: the 1/2/3/4/N buttons) -------------------------

  /// Whether a comma set has a target: the selection's blocks, else the
  /// active layer's block covering the playhead.
  bool get canSetCommaForSelectionOrCurrent =>
      _selectionBlockStartsByLayer() != null || canDeleteCellAtCurrentFrame;

  /// Sets the exposure length of every selected block — or the covering
  /// block at the playhead without a selection — to [comma], packing each
  /// layer's run with the retime ripple (1--2--3-- set to 1 reads 123;
  /// TVP). One composite undo across spanned layers; the selection
  /// follows the retimed span so repeated comma presses keep operating on
  /// the same cels.
  void setCommaForSelectionOrCurrent(int comma) {
    if (comma < 1) {
      return;
    }
    final selection = frameRangeSelection.value;
    // SINGLE-CEL (image) rows never retime: the covering normalization
    // would revert the commit in the same write (a phantom undo entry).
    final selectionTargets = _selectionBlockStartsByLayer() == null
        ? null
        : {
            for (final entry in _selectionBlockStartsByLayer()!.entries)
              if (!_isSingleCelLayerId(entry.key)) entry.key: entry.value,
          };
    if (selection != null &&
        selectionTargets != null &&
        selectionTargets.isNotEmpty) {
      _timelineController.retimeBlocksForLayers({
        for (final entry in selectionTargets.entries)
          entry.key: {for (final start in entry.value) start: comma},
      });
      _reselectRetimedSelection(selection, selectionTargets);
      _warmActiveCut();
      notifyListeners();
      return;
    }
    final layer = activeLayer;
    // Synced attach rows own no timing (free rows retime normally);
    // single-cel rows are pinned by the covering normalization.
    if (layer == null ||
        isSyncedAttachedLayer(layer) ||
        layerKindHoldsSingleCel(layer.kind)) {
      return;
    }
    final block = coveringDrawingBlockAt(
      layer.timeline,
      _timelineController.currentFrameIndex,
    );
    if (block == null || block.entry.ghost) {
      return;
    }
    _timelineController.retimeBlocksForLayer(
      layerId: layer.id,
      newLengthByStart: {block.startIndex: comma},
    );
    _warmActiveCut();
    notifyListeners();
  }

  /// Re-snaps the selection to the SAME cels after a retime: each layer's
  /// first retimed block kept its start; the span now ends where the last
  /// of its retimed blocks ends (max across layers).
  void _reselectRetimedSelection(
    TimelineFrameRangeSelection selection,
    Map<LayerId, List<int>> startsByLayer,
  ) {
    int? end;
    for (final entry in startsByLayer.entries) {
      final layer = _layerById(entry.key);
      if (layer == null) {
        continue;
      }
      var remaining = entry.value.length;
      for (final timelineEntry in layer.timeline.entries) {
        if (timelineEntry.key < entry.value.first ||
            !timelineEntry.value.isDrawing ||
            timelineEntry.value.ghost) {
          continue;
        }
        final blockEnd = timelineEntry.key + timelineEntry.value.length!;
        end = end == null ? blockEnd : math.max(end, blockEnd);
        remaining -= 1;
        if (remaining == 0) {
          break;
        }
      }
    }
    frameRangeSelection.value = end == null
        ? null
        : TimelineFrameRangeSelection(
            layerId: selection.layerId,
            startIndex: selection.startIndex,
            endIndexExclusive: end,
            layerIds: selection.layerIds,
          );
  }

  // --- B8: the frame verbs, addressed by the STORYBOARD cursor --------------
  //
  // The storyboard's standing row × the track-global playhead. The rail's
  // standing row is separate state from the cut's drawing target (유저
  // 2026-07-27), so the cut-local verbs above cannot carry these — and the
  // toolbar pressed on that panel must not fall back to them (B8
  // 2026-08-17: 「누른 패널 기준으로 동작」, 「블록 종류 불문 같은 규칙」).

  /// The BLOCK under the storyboard cursor, whatever its kind: the standing
  /// V row's cut, the standing S row's SE block, or the transition row's
  /// span. Null where the cursor covers nothing (a gap is an honest
  /// nothing, not a fallback to the other panel's subject).
  _StoryboardCursorBlock? _storyboardCursorBlockOrNull() {
    switch (selectedRow) {
      case LayerRowAddress(:final layerId)
          when isTrackTransitionLayerId(layerId):
        final span = transitionSpanAt(editingGlobalFrame);
        if (span == null) {
          return null;
        }
        return _StoryboardCursorTransitionSpan(span.key, span.value.length);
      case LayerRowAddress(:final layerId):
        final global = trackSeGlobalLayerById(layerId);
        final frame = editingGlobalFrame;
        if (global == null || frame < 0) {
          return null;
        }
        final block = coveringDrawingBlockAt(global.timeline, frame);
        if (block == null || block.entry.ghost) {
          return null;
        }
        return _StoryboardCursorSeBlock(layerId, block.startIndex);
      case LaneRowAddress():
        // A lane row holds keys, not blocks — the lane-verb family owns it.
        return null;
      case TrackRowAddress():
        // Not parked in a gap ⇒ the cut-local playhead sits inside the
        // ACTIVE cut, so the cut under the cursor is that cut by
        // construction (the storyboard's cell press promotes it).
        if (editingPlayheadInGap) {
          return null;
        }
        final cut = activeCutOrNull;
        return cut == null ? null : _StoryboardCursorCutBlock(cut);
    }
  }

  /// Whether the storyboard's comma press (1/2/3/4/N) has a target: a live
  /// selection's blocks — either axis — else the block under the cursor.
  bool get canSetCommaForStoryboardCursor {
    if (_selectionBlockStartsByLayer() != null) {
      return true;
    }
    return switch (_storyboardCursorBlockOrNull()) {
      null => false,
      // The controller resolves track-SE commit layers through the active
      // cut's lens machinery; a parked playhead has no cut to lens through.
      _StoryboardCursorSeBlock() => activeCutOrNull != null,
      _StoryboardCursorCutBlock() || _StoryboardCursorTransitionSpan() => true,
    };
  }

  /// The storyboard's comma press: the selection's blocks, else THE BLOCK
  /// UNDER THE CURSOR takes length [comma] — one rule for every block kind
  /// (B8: 「컷블록 위 4 = 컷길이 4」), each kind through the SAME machinery
  /// its own grips already commit with:
  ///
  /// - a CUT block rides the trailing-edge drag verbs, so a conte row's
  ///   last comma and the following gap behave exactly as if the edge had
  ///   been dragged to frame [comma];
  /// - an SE block takes the timeline comma buttons' own retime
  ///   ([TimelineController.retimeBlocksForLayers]), stated in global keys;
  /// - a TRANSITION span rides its edge-drag verbs (the grips own length).
  void setCommaForStoryboardCursor(int comma) {
    if (comma < 1) {
      return;
    }
    // The strip's cut-local selection: the shared verb's selection branch,
    // verbatim. ⚠️Guarded so its active-layer fallback — the other panel's
    // subject — stays unreachable from this panel.
    final selection = frameRangeSelection.value;
    if (selection != null) {
      final targets = _cutLocalSelectionBlockStartsByLayer();
      final retimable =
          targets != null &&
          targets.keys.any((id) => !_isSingleCelLayerId(id));
      if (retimable) {
        setCommaForSelectionOrCurrent(comma);
      }
      return;
    }
    // The S rows' track-axis selection: the same retime, already in global
    // commit keys (the shared verb never had this rung — its selection
    // branch reads the cut-local notifier alone).
    final trackTargets = _trackSelectionBlockStartsByLayer();
    if (trackTargets != null) {
      if (activeCutOrNull == null) {
        return;
      }
      _timelineController.retimeBlocksForLayers({
        for (final entry in trackTargets.entries)
          entry.key: {for (final start in entry.value) start: comma},
      });
      _warmActiveCut();
      notifyListeners();
      return;
    }
    switch (_storyboardCursorBlockOrNull()) {
      case null:
        return;
      case _StoryboardCursorCutBlock(:final cut):
        if (comma == cut.duration) {
          return; // A no-move drag must not land an undo step.
        }
        if (!beginCutEdgeDrag(cutId: cut.id, edge: TimelineBlockEdge.end)) {
          return;
        }
        updateCutEdgeDrag(comma - cut.duration);
        endCutEdgeDrag();
      case _StoryboardCursorSeBlock(:final layerId, :final blockStartIndex):
        if (activeCutOrNull == null) {
          return;
        }
        _timelineController.retimeBlocksForLayers({
          layerId: {blockStartIndex: comma},
        });
        _warmActiveCut();
        notifyListeners();
      case _StoryboardCursorTransitionSpan(
        :final spanStartIndex,
        :final spanLength,
      ):
        if (comma == spanLength) {
          return;
        }
        if (!beginTransitionEdgeDrag(
          spanStartIndex: spanStartIndex,
          edge: TimelineBlockEdge.end,
        )) {
          return;
        }
        updateTransitionEdgeDrag(comma - spanLength);
        endTransitionEdgeDrag();
    }
  }

  /// Whether the storyboard's delete has a block under the cursor (its
  /// selection rungs are asked separately — see the toolbar context).
  bool get canDeleteBlockAtStoryboardCursor =>
      switch (_storyboardCursorBlockOrNull()) {
        null => false,
        _StoryboardCursorSeBlock() => activeCutOrNull != null,
        _StoryboardCursorCutBlock() ||
        _StoryboardCursorTransitionSpan() => true,
      };

  /// Deletes THE BLOCK UNDER THE CURSOR, whatever its kind — the cut, the
  /// SE block, or the transition span, each through its own existing
  /// removal verb. One undo step each, like the cell delete it mirrors.
  void deleteBlockAtStoryboardCursor() {
    switch (_storyboardCursorBlockOrNull()) {
      case null:
        return;
      case _StoryboardCursorCutBlock():
        deleteActiveCut();
      case _StoryboardCursorSeBlock(:final layerId, :final blockStartIndex):
        if (activeCutOrNull == null) {
          return;
        }
        _timelineController.deleteBlocksForLayers({
          layerId: [blockStartIndex],
        });
        notifyListeners();
      case _StoryboardCursorTransitionSpan():
        removeTransitionSpanAt(editingGlobalFrame);
    }
  }

  /// Whether the frame `＋` can author a fresh SE entry on the standing S
  /// row: standing there, an EMPTY cursor frame, and an active cut for the
  /// fills funnel's lens to resolve through.
  bool get canCreateSeEntryAtStoryboardCursor {
    if (activeCutOrNull == null) {
      return false;
    }
    final row = selectedRow;
    if (row is! LayerRowAddress || isTrackTransitionLayerId(row.layerId)) {
      return false;
    }
    final global = trackSeGlobalLayerById(row.layerId);
    final frame = editingGlobalFrame;
    return global != null &&
        frame >= 0 &&
        coveringDrawingBlockAt(global.timeline, frame) == null;
  }

  /// One blank one-frame dialogue entry at the cursor — the cut-scoped SE
  /// creation ([createSeEntryAtCurrentFrame]) said of the standing row, via
  /// the SAME fills funnel the track-range create commits through.
  void createSeEntryAtStoryboardCursor() {
    if (!canCreateSeEntryAtStoryboardCursor) {
      return;
    }
    final row = selectedRow as LayerRowAddress;
    final layerId = row.layerId;
    _frameSequence += 1;
    // ⚠️The fills funnel re-applies the track-SE display lens on the way in
    // (the active cut's global start) — pre-subtract the SAME expression,
    // exactly as [_createTrackSeEntriesForRange] does, or the entry lands
    // double-shifted.
    final commands = _timelineController.drawingFramesCommandsForLayers({
      layerId: [
        (
          startIndex: editingGlobalFrame - activeCutGlobalStartFrame,
          length: 1,
          frameId: FrameId(_nextFrameId(layerId)),
          name: '',
        ),
      ],
    });
    if (commands.isEmpty) {
      return;
    }
    _historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(
              description: 'Create SE entry',
              commands: commands,
            ),
    );
    notifyListeners();
  }

  int get currentFrameIndex => _timelineController.currentFrameIndex;

  /// A seek is NOT a session notify: the playhead move rebuilds nothing by
  /// itself. Cursor-driven widgets follow [editingFrameCursor]; the few
  /// seek-dependent surfaces (editing canvas, timeline toolbar enablement,
  /// camera pose panel, timesheet playhead) subscribe to
  /// [frameSeekCommitted] and rebuild once per committed seek.
  void selectFrameIndex(int frameIndex) {
    // R15-⑤: a live editing interaction REFUSES the seek outright — a
    // flip under an in-flight edit tore widgets down inside the build
    // phase (red screens) and could land the edit on the wrong cel.
    if (editingInteractionBusy) {
      return;
    }
    // A direct cut-local seek leaves any gap parking (R16-⑥); the global
    // seek re-parks AFTER this call when it lands in a gap.
    _gapGlobalFrame = null;
    labProbe('selectFrameIndex(sync)', () {
      _timelineController.selectFrameIndex(frameIndex);
      editingFrameCursor.value = frameIndex;
      // A seek is activity (R13-3): rapid frame flipping keeps pushing the
      // warm window, so composite warming never lands a full-canvas build
      // in the middle of a flip run.
      prerenderScheduler.notifyEditActivity();
      _warmActiveCut();
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
      prerenderScheduler.beginInputHold();
    } else {
      prerenderScheduler.endInputHold();
    }
  }

  /// Selection-tool interactions (marquee/move/transform drags) — counted
  /// so overlapping holds nest (R15-⑤).
  final ValueNotifier<bool> selectionInteractionActive = ValueNotifier<bool>(
    false,
  );
  int _selectionInteractionHolds = 0;

  void beginSelectionInteraction() {
    _selectionInteractionHolds += 1;
    selectionInteractionActive.value = true;
    prerenderScheduler.beginInputHold();
  }

  void endSelectionInteraction() {
    if (_selectionInteractionHolds > 0) {
      _selectionInteractionHolds -= 1;
      prerenderScheduler.endInputHold();
    }
    selectionInteractionActive.value = _selectionInteractionHolds > 0;
  }

  /// R15-⑤: any live editing interaction (brush stroke, selection drag)
  /// blocks frame seeks, scrubs and cut switches entirely — the playhead
  /// moves when the pen lifts, never under it.
  bool get editingInteractionBusy =>
      brushInputActive.value || selectionInteractionActive.value;

  // --- Track-global frame axis (R15-①) -----------------------------------

  /// THE structural model of the active track's timeline: cuts occupy
  /// [start, end) global ranges and the frames between them are REAL
  /// addresses (a layer timeline's empty frames, at track scale). The
  /// session playhead, the storyboard and the timeline consume THIS ONE
  /// axis — change it and every panel changes together.
  TrackFrameAxis trackFrameAxis() {
    final layout = _projectLayout();
    final trackId = selectedTrackId;
    final scoped = [
      for (final entry in layout)
        if (entry.trackId == trackId) entry,
    ];
    return TrackFrameAxis(scoped.isEmpty ? layout : scoped);
  }

  /// The whole-project layout, memoized on PROJECT IDENTITY: scrubs ask
  /// per MOVE and all-cuts playback per TICK, and the project only changes
  /// identity on an edit — rebuilding the whole cross-track layout each
  /// call was a fixed per-move tax (the same memo the storyboard host
  /// keeps).
  /// The memoized layout, for surfaces outside this class that need the
  /// same cut ranges — the flip HUD's gap window reads the track's cuts
  /// through here rather than rebuilding a second layout that could
  /// disagree with the one the flip walks.
  List<StoryboardTimelineLayoutEntry> projectTimelineLayout() =>
      _projectLayout();

  List<StoryboardTimelineLayoutEntry> _projectLayout() {
    final project = repository.requireProject();
    if (!identical(project, _projectLayoutProject)) {
      _projectLayoutProject = project;
      _projectLayoutMemo = buildStoryboardTimelineLayout(project);
    }
    return _projectLayoutMemo!;
  }

  Project? _projectLayoutProject;
  List<StoryboardTimelineLayoutEntry>? _projectLayoutMemo;

  /// Set while the editing playhead is PARKED IN A GAP (R16-⑥, user
  /// semantics: a gap has NO cut — the canvas shows a paperless void).
  /// Stores the exact global frame, which the leading gap before the
  /// first cut cannot express as any cut-local index. Notifier-backed
  /// (UI-R7 #9): gap scrubs park PER MOVE now, and the storyboard
  /// playhead must follow even where the cut-local cursor cannot change
  /// (the leading gap pins local 0).
  final ValueNotifier<int?> _gapGlobalFrameNotifier = ValueNotifier<int?>(null);

  int? get _gapGlobalFrame => _gapGlobalFrameNotifier.value;
  set _gapGlobalFrame(int? value) => _gapGlobalFrameNotifier.value = value;

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
  /// parked with no cut is a gap, and [_gapGlobalFrame] is exactly that
  /// state, held explicitly rather than inferred.
  ///
  /// ⚠️This is the sweep the getter's own doc promised whoever unclamped:
  /// the term did not need updating, it needed removing.
  bool get editingPlayheadInGap => _gapGlobalFrame != null;

  /// The gap parking's exact global frame, or null when the playhead sits
  /// on a cut. Cheap field read — per-tick consumers (the storyboard
  /// playhead) use it without rebuilding the axis.
  int? get gapParkedGlobalFrame => _gapGlobalFrame;

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
  int get editingGlobalFrame {
    final parked = _gapGlobalFrame;
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

  /// The multitrack display resolution: every track's covered cut at
  /// [globalFrame], STRICT containment, in project track order. Unlike
  /// [trackFrameAxis] this is never scoped to the selected track and has
  /// no whole-layout fallback — a track that gaps here simply contributes
  /// nothing. The parked canvas stacks these (one camera-projected
  /// composite per covered track).
  ///
  List<PlaybackPosition> trackStackPositionsAt(int globalFrame) =>
      resolveTrackStackPositions(
        layout: _projectLayout(),
        globalFrameIndex: globalFrame,
      );

  /// The same resolution WITH transitions: an O.L answers with both cuts,
  /// leaving one first, each carrying its share of the frame. One reader for
  /// the parked canvas, all-cuts playback and the camera-size bake.
  List<TrackStackContribution> trackStackContributionsAt(int globalFrame) =>
      resolveTrackStackContributions(
        layout: _projectLayout(),
        spansOf: transitionSpansOfTrack,
        globalFrameIndex: globalFrame,
      );

  /// One track's transition spans on its own global axis. Falls back to no
  /// spans for a track id the project no longer holds.
  ///
  /// A hidden transition row contributes NOTHING (B5③ 2026-08-17: 「비지블
  /// = 해당 합성 반영/미반영」) — the composite plan's own visibility law,
  /// said of the one row whose contribution is fades instead of pixels.
  /// The row still draws its spans; only playback stops fading. Asked as
  /// `rowVisible` (the hidden-folder law's one door, ratcheted by
  /// `hidden_folder_is_hidden_test`); the fixture lives in no folder, so
  /// the singleton stack it stands in is its own.
  List<TransitionSpan> transitionSpansOfTrack(TrackId trackId) {
    for (final track in _repository.requireProject().tracks) {
      if (track.id == trackId) {
        final transition = track.transitionLayer;
        if (!<Layer>[transition].rowVisible(transition)) {
          return const [];
        }
        return [
          for (final entry in transition.instructions.entries)
            _transitionSpanOf(entry),
        ];
      }
    }
    return const [];
  }

  /// One instruction event as a geometry span, WITH its term's mark.
  ///
  /// 🚨The mark is what tells O.L from F.O downstream. Dropping it here — which
  /// this used to do — made `cutOpacityAt` treat every span as a symmetric
  /// cross-dissolve, so an F.O faded the next cut IN and behaved as an O.L
  /// (user 2026-08-11). An id the vocabulary no longer holds falls back to the
  /// bowtie, which is the shape a file from another build most likely meant.
  TransitionSpan _transitionSpanOf(MapEntry<int, InstructionEvent> entry) => (
    start: entry.key,
    length: entry.value.length,
    mark:
        cameraInstructionSet.defById(entry.value.instructionId)?.markType ??
        CameraInstructionMarkType.ol,
  );

  /// Deselects the active cut for a GAP landing (UI-R9 #3): standing in a
  /// gap means NO cut is selected — the timeline/timesheet show their
  /// empty states and the canvas shows the void. QUIET: callers notify
  /// (they batch it with the parking + commit signals). False when no cut
  /// was selected to begin with.
  bool _deselectActiveCutForGap() {
    if (_editingSession.activeCutId == null) {
      return false;
    }
    // Parking in a gap LEAVES the cut, so the row it was on is recorded
    // here too — scrubbing out and back keeps the layer.
    _rememberActiveLayerForCut();
    // The visibility solo is cut-scoped: restore the eyes before leaving
    // (the selectCut contract).
    if (_layerVisibilitySoloEnabled) {
      _exitVisibilitySolo();
    }
    _editingSession.setActiveCutId(null);
    _copiedFrame = null;
    clearFrameRangeSelection();
    _rebuildActiveCutControllers();
    return true;
  }

  /// V-TRACK selection (UI-R18 #6): tapping a V row makes THAT track's
  /// cut under the current global playhead the ACTIVE cut — every track
  /// reads the one shared global index, each independently (the V-row
  /// fx/eye subject rule). The landing keeps the global position: the new
  /// cut's local frame is the same global frame. A gap on the tapped
  /// track is a no-op, like the fx/eye buttons there.
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
    _gapGlobalFrame = globalFrame;
    _deselectActiveCutForGap();
    frameSeekCommitted.value += 1;
    notifyListeners();
  }

  /// [onAxis] lands the frame on a SPECIFIC track's axis instead of the
  /// selected track's. A caller that computed its move on one axis must
  /// land it on the same one — resolving on a different track would put
  /// the playhead in a cut the move never chose.
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

  /// Global scrub: rides the cursor path inside the active cut's
  /// territory; EVERY out-of-territory move — a gap OR another cut's
  /// frames — parks the exact global PER MOVE (UI-R7 #9) and commits
  /// NOTHING. The parking notifier drives the storyboard playhead and the
  /// track-stack preview live, while the active cut and its controllers
  /// stay untouched for the whole drag: the old per-move escalation to
  /// [selectGlobalFrame] on a boundary cross ran selectCut + a committed
  /// seek per move, rebuilding every visible panel — the cut-boundary
  /// crossing lag — and the gap branch's immediate deselect was the same
  /// hitch on gap entry. [_followPlaybackCut] keeps playback's crossings
  /// quiet for exactly this reason; the release ([commitFrameScrub])
  /// lands the ONE full seek, where cut activation and gap deselection
  /// now both live (UI-R10 #13's live empty-out moved there on purpose).
  void scrubGlobalFrame(int globalFrame) {
    if (editingInteractionBusy) {
      return;
    }
    final axis = trackFrameAxis();
    if (axis.isEmpty) {
      return;
    }
    final owner = axis.ownerOf(globalFrame);
    if (axis.isGap(globalFrame) ||
        owner == null ||
        owner.cutId != activeCutId) {
      // The preview engages on the SECOND out-of-territory event — an
      // actual drag move — never on the pointer-down alone: a plain TAP
      // over another cut's frames must not flash the track-stack
      // presentation for its press-release interval (the same no-flash
      // rule scrubFrameIndex keeps for in-cut taps; the playhead itself
      // follows immediately through the parking either way). No warm:
      // the track stack self-fills, there is no active-cut cache to fill.
      final parked = _gapGlobalFrame;
      if (parked != null && parked != globalFrame && !frameScrubActive.value) {
        frameScrubActive.value = true;
      }
      _gapGlobalFrame = globalFrame;
      return;
    }
    if (_gapGlobalFrame != null) {
      // Scrubbing back onto the cut un-parks — and kicks the warm the
      // out-of-territory engage skipped (one warm per territory entry,
      // not per move: the preview reads the composite cache, so a cold
      // stretch would otherwise show stale paper for the whole re-entry).
      _gapGlobalFrame = null;
      _warmActiveCut();
    }
    scrubFrameIndex(math.max(0, globalFrame - owner.startFrame));
  }

  // --- Onion skin (P2: Callipeg peg model) -----------------------------------

  /// Session view state — a ValueNotifier so the canvas underlay and the
  /// onion panel subscribe without whole-session notifies.
  final ValueNotifier<OnionSkinSettings> onionSkinSettings =
      ValueNotifier<OnionSkinSettings>(const OnionSkinSettings());

  /// PER-LAYER onion application (UI-R17 #5, TVPaint's light table): the
  /// layers whose ghosts composite. The panel's master switch is GONE —
  /// row/legend toggles drive this set.
  final ValueNotifier<Set<LayerId>> onionSkinLayerIds =
      ValueNotifier<Set<LayerId>>(<LayerId>{});

  bool isLayerOnionSkinEnabled(LayerId layerId) =>
      onionSkinLayerIds.value.contains(layerId);

  void toggleLayerOnionSkin(LayerId layerId) {
    final next = Set<LayerId>.from(onionSkinLayerIds.value);
    if (!next.remove(layerId)) {
      next.add(layerId);
    }
    onionSkinLayerIds.value = next;
    // Row/legend toggle glyphs read through the session listenable.
    notifyListeners();
  }

  /// The drawing layers the legend's bulk onion sweep addresses: the
  /// active cut's VISIBLE brush-holding rows.
  List<Layer> get _onionSweepLayers {
    final stack = activeCutOrNull?.layers ?? const <Layer>[];
    return [
      for (final layer in stack)
        // `rowVisible`, not `isVisible`: a row inside a hidden folder is not
        // displayed, so the sweep over "every displayed layer" must not
        // count it — otherwise the bulk button reads OFF because of rows
        // nobody can see.
        if (stack.rowVisible(layer) && layerKindAcceptsBrushInput(layer.kind))
          layer,
    ];
  }

  /// Whether the legend's bulk button reads ON (every displayed layer
  /// currently ghosting).
  bool get displayedLayersOnionSkinEnabled {
    final targets = _onionSweepLayers;
    return targets.isNotEmpty &&
        targets.every((layer) => isLayerOnionSkinEnabled(layer.id));
  }

  /// Legend bulk sweep (UI-R17 #5): all displayed layers on — or, when
  /// they all are already, all off.
  void toggleOnionSkinForDisplayedLayers() {
    final targets = _onionSweepLayers;
    if (targets.isEmpty) {
      return;
    }
    final enable = !displayedLayersOnionSkinEnabled;
    final next = Set<LayerId>.from(onionSkinLayerIds.value);
    for (final layer in targets) {
      enable ? next.add(layer.id) : next.remove(layer.id);
    }
    onionSkinLayerIds.value = next;
    notifyListeners();
  }

  /// The `O` shortcut: toggles the ACTIVE layer's onion (the per-layer
  /// model's successor of the old master toggle).
  void toggleOnionSkin() {
    final layer = activeLayer;
    if (layer == null) {
      return;
    }
    toggleLayerOnionSkin(layer.id);
  }

  /// The ghost frames to composite at the playhead: every onion-enabled
  /// VISIBLE drawing layer contributes its plan (unique drawings, peg
  /// opacities, side tints) in layer-stack order.
  List<CanvasLayerImageRequest> onionSkinCanvasRequests() {
    final settings = onionSkinSettings.value;
    final cut = activeCutOrNull;
    final enabledIds = onionSkinLayerIds.value;
    if (cut == null || enabledIds.isEmpty) {
      return const [];
    }
    return [
      for (final layer in cut.layers)
        // A ghost is that layer's artwork, so it is shown exactly when the
        // layer is: hiding the FOLDER used to leave its members' onion skins
        // on screen with nothing under them.
        if (enabledIds.contains(layer.id) &&
            cut.layers.rowVisible(layer) &&
            layerKindAcceptsBrushInput(layer.kind))
          for (final plan in planOnionSkin(
            layer: layer,
            frameIndex: _timelineController.currentFrameIndex,
            settings: settings,
          ))
            CanvasLayerImageRequest(
              frameKey: brushFrameKeyForCut(cut, layer.id, plan.frameId),
              opacity: plan.opacity,
              tint: plan.tint,
            ),
    ];
  }

  // --- Project persistence (P3: the .anicel container) -------------------------

  static const AnicelFileService _anicelFileService = AnicelFileService();

  String? _projectFilePath;

  /// Pool path → archive entry, for the media this project carries.
  ///
  /// NAMES, not offsets. A compaction moves every byte in the file, so a
  /// remembered offset would read a window of whatever landed in its
  /// place — a project that opens fine and plays the wrong sound. The
  /// offset is looked up from the layout at the moment it is wanted, and
  /// the layout is already being parsed then.
  Map<String, String> _mediaEntryNames = const {};

  /// What the project carries, for tests and for anything that needs to
  /// resolve an asset's bytes without going through a save.
  Map<String, String> get mediaEntryNames =>
      Map<String, String>.unmodifiable(_mediaEntryNames);

  /// The open project's file path; null until first saved/opened (Save
  /// falls back to Save As).
  String? get projectFilePath => _projectFilePath;

  bool _hasUnsavedChanges = false;

  /// Whether edits exist since the last save/open (autosave + title dots).
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  void _markProjectDirty() {
    _hasUnsavedChanges = true;
  }

  /// The autosave sidecar for the CURRENT state (SAVE-1: beside the file
  /// or in the user's sidecar directory — [AppSave.sidecarPathFor]);
  /// null while the project has never been saved (the service prompts
  /// for a real file instead of writing into hidden app-data dirs).
  String? get autosaveSidecarPath {
    final path = _projectFilePath;
    return path == null ? null : AppSave.recoveryPathFor(path);
  }

  /// Writes the current state to [path] WITHOUT touching the dirty flag or
  /// the project path — the recovery service's snapshot writer.
  ///
  /// An OVERLAY on the saved project: only the cels edited since the last
  /// manual save. This runs as the app is going away, with a few seconds
  /// and no promise of coming back, so it has to cost what the user drew
  /// rather than what the project weighs. Everything left out is already
  /// in the project file, unchanged, which is also what the base stamp
  /// inside the overlay is there to guarantee.
  Future<void> writeAutosaveSnapshot(String path) async {
    final base = _projectFilePath;
    if (base == null) {
      return;
    }
    // 🚨A RECOVERED session must not write one. Recovery pointed every
    // restored cel's ref INTO this file and cleared the RAM tiers, and it
    // also cleared the dirty set — so a snapshot taken now would carry no
    // cels at all and rename itself over the only copy of the work, and
    // the live refs would then read past the end of a file holding a
    // stamp and a project.json. The session has nothing new to snapshot
    // until a manual save moves those pixels into the project file, which
    // is exactly when this unblocks.
    if (_recoveredFromSidecar != null) {
      return;
    }
    // The user chose to throw this session's work away and the app is
    // shutting down around that choice; the lifecycle callbacks that
    // follow must not put it back.
    if (_discardedUnsavedWork) {
      return;
    }
    await _flushTextCelBakes();
    await _anicelFileService.writeRecoveryOverlay(
      project: _repository.requireProject(),
      brushFrameStore: brushFrameStore,
      auxCelStores: [conteInkRowStore, conteInkPageStore, envelopeInkStore],
      filePath: path,
      baseFilePath: base,
      // The overlay's project.json replaces the base file's, so a snapshot
      // that left these out would hand the recovered session no grants —
      // and its first save would write that emptiness back over the file.
      grants: _grantsToStore(),
      // What the base file already carries. Without it the recovered
      // session forgets its media is inside the archive and its first
      // save writes one that no longer holds it.
      mediaInArchive: _mediaEntryNames.keys.toSet(),
      // And what it knows about its media's content. A recovered session
      // without these still opens and still looks right — it has just
      // forgotten how to tell one `A1.png` from another.
      mediaCrcs: _mediaCrcsToStore(),
      // Asked again at the rename: a manual save can begin and finish
      // while this one is in the isolate, and it retires the snapshot on
      // its way out.
      isStale: () => autosaveShouldStandDown,
    );
  }

  /// Saves the project + every drawn frame into ONE .anicel file (atomic
  /// temp-then-rename write; media stays external with relative paths
  /// recorded for Drive portability). A successful save retires the
  /// autosave sidecar.
  ///
  /// [onProgress] is called with 0..1 as the write proceeds, for the window
  /// a manual save puts in front of itself. Omitted by the autosave tick,
  /// which nobody is watching.
  Future<void> saveProjectToFile(
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    // A text bake in flight must land before the store snapshots — the
    // archive's parameters and raster must never disagree.
    // Raised for the WHOLE save, retirement included. An autosave tick that
    // starts inside a save renames its own temp onto the sidecar path
    // AFTER the retirement ran, and the session is clean by then — so the
    // exit gate returns early, nothing retires it, and the next open offers
    // recovery for a project that was closed cleanly. Making the delete
    // synchronous did not close this: sync ordering settles delete-versus-
    // write, and this is write-versus-delete, which is an isolate wide.
    _saveInFlight = true;
    try {
      await _writeProjectToFile(filePath, onProgress: onProgress);
    } finally {
      _saveInFlight = false;
    }
  }

  /// True while a manual save is running, so the autosave tick stands down
  /// instead of racing it. Read through [autosaveShouldStandDown].
  bool _saveInFlight = false;

  /// Whether a snapshot should do nothing right now: a save is mid-flight
  /// (anything written would land beside a retirement that has already
  /// run), the session was recovered (its refs point INTO the snapshot,
  /// see [writeAutosaveSnapshot]), or the user threw the work away.
  bool get autosaveShouldStandDown =>
      _saveInFlight || _discardedUnsavedWork || _recoveredFromSidecar != null;

  Future<void> _writeProjectToFile(
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    await _flushTextCelBakes();
    // Captured BEFORE the save moves the project path: a Save As has to
    // retire the sidecars of the file it was saved FROM as well.
    final previousPath = _projectFilePath;
    // Before serializing: the first save takes this session's recordings
    // off the shelf. Nothing moves on disk — see the verb.
    _voiceRecording.releaseShelfTakesToProject();
    // Resolved against the CURRENT project path, before it moves. On a
    // save-as that makes each source point into the file being left
    // behind, and the writer streams from there into the new one — which
    // is how a copy carries its media without a copy step of its own.
    final mediaToStore = projectMediaSources(
      project: _repository.requireProject(),
      projectFilePath: _projectFilePath,
      mediaEntryNames: _mediaEntryNames,
    );
    await _anicelFileService.save(
      project: _repository.requireProject(),
      brushFrameStore: brushFrameStore,
      auxCelStores: [conteInkRowStore, conteInkPageStore, envelopeInkStore],
      filePath: filePath,
      mediaToStore: mediaToStore,
      grants: _grantsToStore(),
      mediaCrcs: _mediaCrcsToStore(),
      onProgress: onProgress,
    );
    _mediaEntryNames = mediaEntryNamesFor(mediaToStore.keys);
    _projectFilePath = filePath;
    _hasUnsavedChanges = false;
    // The recovered work now lives in the project file, so the snapshot is
    // ordinary again and the retirement below is free to take it.
    _recoveredFromSidecar = null;
    // A save is the session saying it is worth keeping after all; whatever
    // was discarded before it is not this session's state any more.
    _discardedUnsavedWork = false;
    // No conform refresh here any more. It existed because a take MOVED
    // into the project on first save, which changed the path a conform is
    // keyed by; takes stay put now, and the cache is keyed by source
    // rather than by anything the project owns, so a save moves nothing a
    // conform depends on.
    if (previousPath != null) {
      ProjectAutosaveService.retireSidecarsFor(previousPath);
    }
    ProjectAutosaveService.retireSidecarsFor(filePath);
    notifyListeners();
  }

  /// The sidecar this session was RECOVERED from, while its contents still
  /// live nowhere else. Null in every ordinary session.
  ///
  /// Recovery loads the sidecar's bytes and mints every cel ref into it,
  /// then clears the RAM tiers — so from that moment the sidecar is the
  /// only home those pixels have. A manual save moves them into the
  /// project file and clears this.
  String? _recoveredFromSidecar;

  /// The user threw this session's unsaved work away (closed without
  /// saving). Its sidecar has to go with it: "저장 안 하고 닫기 = 버리기"
  /// is only literally true if the next open cannot offer to resurrect
  /// exactly what was discarded.
  ///
  /// A never-saved project has no sidecar to retire (its dirty ticks ask
  /// for a real file instead of writing one).
  ///
  /// 🚨A RECOVERED session is the exception, and the reason is that the
  /// sidecar is not this session's discard to make. It holds the PREVIOUS
  /// session's crash work, it is the only copy of it (recovery drops every
  /// RAM tier and points every ref inside it), and a recovered session
  /// arrives already dirty with zero edits — so the exit gate fires and
  /// offers Close as the primary button before the user has touched
  /// anything. Retiring here deletes hours of crash work at one tap on a
  /// prompt that says nothing about it. Keeping it means the next open
  /// offers recovery again, which is what it did before this round; the
  /// user discards it by saving, not by closing.
  void discardAutosaveSidecar() {
    // Recorded even when there is nothing to delete: what this really
    // says is "the user threw this session away", and the shutdown that
    // follows delivers the same lifecycle callbacks as any other — which
    // would otherwise write a fresh snapshot straight over the retirement
    // and hand the discarded work back at the next open. Deleting without
    // stopping the trigger is a race the trigger wins.
    _discardedUnsavedWork = true;
    final path = _projectFilePath;
    if (path == null || _recoveredFromSidecar != null) {
      return;
    }
    ProjectAutosaveService.retireSidecarsFor(path);
  }

  /// True once the user has closed without saving. The session is on its
  /// way out; nothing may snapshot it again.
  bool _discardedUnsavedWork = false;

  /// Security-scoped tokens for media the project REFERENCES, held beside
  /// the project rather than inside it.
  ///
  /// 🚨 Outside [Project] on purpose. Apple re-issues a bookmark on every
  /// resolve, so a grant in the model would mark the film dirty simply for
  /// having been opened — an edit the user never made, and a "save your
  /// changes?" they cannot account for. Keeping them here costs one
  /// argument at the save call and buys that.
  ///
  /// Empty on Windows, Linux and Android, where a recorded path keeps
  /// working on its own.
  List<FolderGrant> _mediaGrants = const [];

  /// Content fingerprints for the pool, held OUT of the project.
  ///
  /// 🚨 Out here because recording one is not an edit. The length on
  /// [MediaAsset.identity] is imprinted by an import, which the user did;
  /// a CRC arrives whenever something reads an asset's bytes for its own
  /// reasons, which the user did not — and a viewer showing a picture must
  /// not put a dot on the title bar. Same law as [_storedGrants], same
  /// shape: this map rides to the writer as an argument, never through
  /// `Project`.
  MediaFingerprints _mediaFingerprints = const MediaFingerprints.empty();

  /// What is known about [poolPath]'s content: the length the import
  /// imprinted, plus the CRC if anyone has paid for one.
  ///
  /// Null when the pool has no such asset, or when even the length is
  /// missing — which is every asset registered by a build that predates
  /// [MediaIdentity], and is exactly the case that must answer "unknown"
  /// rather than guess.
  MediaIdentity? recordedMediaIdentity(String poolPath) {
    final wanted = _normalizedPath(poolPath);
    for (final asset in mediaAssets) {
      if (_normalizedPath(asset.path) == wanted) {
        return _mediaFingerprints.identityFor(wanted, asset.identity);
      }
    }
    return null;
  }

  /// Records that [poolPath]'s bytes hash to [crc32], because something
  /// read them anyway.
  ///
  /// 🔑 Deliberately NOT an edit: no command, no undo entry, no dirty
  /// flag, no notify. Flipping through the media browser must not make the
  /// project look unsaved. The price is that a fingerprint learned in a
  /// session that never saves is forgotten, which is the right way round —
  /// it is a cache of something re-derivable, and the file it describes is
  /// still there to be read again.
  ///
  /// Takes any path, registered or not. An import reads the bytes BEFORE
  /// it knows whether the import will happen, so demanding the asset exist
  /// first would forfeit the one reading that is guaranteed free. What
  /// reaches the FILE is narrowed to the pool at save time instead, which
  /// is where the same filter has to run anyway for assets since removed.
  void rememberMediaFingerprint(String poolPath, Uint8List bytes) {
    _mediaFingerprints = _mediaFingerprints.remembering(
      poolPath,
      // Both halves from THESE bytes. Taking the length off the asset
      // instead would weld a value imprinted at first registration onto a
      // hash taken now, and a file edited in between would be described as
      // a revision that never existed.
      MediaIdentity(lengthBytes: bytes.length, crc32: anicelCrc32(bytes)),
    );
  }

  /// Follows [moves] (old pool path → new) so a fingerprint survives its
  /// asset being pointed somewhere else.
  ///
  /// 🚨 Called from every place a pool path changes. The store is keyed by
  /// path and the save keeps only keys the pool still holds, so a move that
  /// skips this does not merely mislay the fact — the next save DELETES it.
  void _moveMediaFingerprints(Map<String, String> moves) {
    _mediaFingerprints = _mediaFingerprints.moved(moves);
  }

  /// The fingerprints as the file should keep them: only for media the
  /// project still references.
  Map<String, Object?> _mediaCrcsToStore() => _mediaFingerprints
      .narrowedTo({
        for (final asset in mediaAssets) _normalizedPath(asset.path),
      })
      .toJson();

  @visibleForTesting
  MediaFingerprints get debugMediaFingerprints => _mediaFingerprints;

  /// 🚨 What the FILE should keep, which is not the same question as what
  /// this launch can USE.
  ///
  /// A bookmark that will not resolve right now is unusable today and
  /// perfectly good tomorrow: the volume is unmounted, the provider is
  /// signed out, the phone is in a different country. Keeping only what
  /// resolved would mean the next save writes the survivors and DELETES
  /// the rest — so plugging the drive back in would no longer help,
  /// because the token that named the file is gone from the only place it
  /// was written down.
  ///
  /// Android makes that concrete without any failure at all: it reports
  /// scoped grants, and its `resolveBookmark` answers `unavailable`
  /// unconditionally — so a project authored on an iPad, opened once on an
  /// Android tablet and saved, would come back to the iPad stripped of
  /// every bookmark it had.
  ///
  /// So resolution narrows [_mediaGrants]; it never narrows this.
  List<FolderGrant> _storedGrants = const [];

  /// What the session is holding, for tests. There is no production reader
  /// — grants leave through the save argument and arrive through the open
  /// result — so without this the round trip has no observer at all.
  @visibleForTesting
  List<FolderGrant> get debugMediaGrants => List.unmodifiable(_mediaGrants);

  /// What the next save would write down, for tests. Distinct from
  /// [debugMediaGrants] exactly where it matters: a grant the OS refused
  /// today is absent there and present here.
  @visibleForTesting
  List<FolderGrant> get debugStoredGrants => List.unmodifiable(_storedGrants);

  /// Adds what a picker just granted, replacing any grant for the same
  /// path. Newest wins: Apple hands back a fresh token every time, and the
  /// old one is the stale copy.
  ///
  /// ⛔ Does NOT touch `_hasUnsavedChanges`. This is OS bookkeeping, not
  /// the user's work — it rides along on the next save they were going to
  /// make anyway (그쪽 확정 ⑩).
  void rememberMediaGrants(Iterable<FolderGrant> grants) {
    final incoming = [
      for (final grant in grants)
        if (grant.isGranted && grant.bookmark != null) grant,
    ];
    if (incoming.isEmpty) {
      return;
    }
    final replaced = {for (final grant in incoming) grant.path};
    _mediaGrants = [
      for (final grant in _mediaGrants)
        if (!replaced.contains(grant.path)) grant,
      ...incoming,
    ];
    _storedGrants = [
      for (final grant in _storedGrants)
        if (!replaced.contains(grant.path)) grant,
      ...incoming,
    ];
  }

  /// Hands every stored bookmark back to the OS, so the session may read
  /// the media this project only REFERENCES.
  ///
  /// Resolved ALL AT ONCE on open rather than lazily at each read. There
  /// is no single point where media bytes are asked for — audio decode,
  /// image decode and thumbnails each reach for a file — so a lazy scheme
  /// would need that point built first. References are few by design (the
  /// kind rule keeps everything but video inside the archive), which is
  /// what makes the simple answer affordable.
  ///
  /// 🚨 The answer REPLACES what was stored. Apple re-issues a bookmark on
  /// every resolve, and a bookmark tracks the file rather than the path —
  /// so this is also how a referenced movie that was moved or renamed is
  /// followed instead of lost. Dropping the new token is a bug this
  /// codebase has already had once (`_openRecent` overwrote a fresh
  /// bookmark with the stale one it had in hand).
  ///
  /// ⛔ Never dirties the project. The re-issue is the OS's bookkeeping,
  /// not an edit, and it rides along on the next save.
  ///
  /// ⛔ A grant that will not resolve is unusable THIS LAUNCH and is not
  /// forgotten: it stays in [_storedGrants] so the next save writes it back
  /// unchanged. Dropping it from the file would turn "the drive is
  /// unplugged" into "the permission is gone", and plugging the drive back
  /// in would no longer help.
  ///
  /// Returns {old path: new path} for every bookmark that came back
  /// pointing somewhere else, so the caller can take the project with it.
  Future<Map<String, String>> _resolveMediaGrants(
    List<Map<String, Object?>> stored,
  ) async {
    final parsed = [for (final json in stored) ?FolderGrant.fromJson(json)];
    _storedGrants = parsed;
    if (parsed.isEmpty || !FolderPicker.grantsAreScoped) {
      // Nothing to hold, or a platform where a path is durable on its own
      // — Windows and Linux never minted these in the first place.
      _mediaGrants = parsed;
      return const {};
    }
    final resolved = <FolderGrant>[];
    final stillStored = <FolderGrant>[];
    final moved = <String, String>{};
    for (final grant in parsed) {
      final answer = await FolderPicker.resolveBookmark(
        grant.bookmark!,
        kind: grant.kind,
      );
      if (!answer.isGranted || answer.path == null) {
        stillStored.add(grant); // Unusable today. Not gone.
        continue;
      }
      final fresh = FolderGrant.granted(
        path: answer.path!,
        // The freshly issued token, never the one we arrived with.
        bookmark: answer.bookmark ?? grant.bookmark,
        kind: grant.kind,
      );
      if (fresh.path != grant.path) {
        moved[grant.path!] = fresh.path!;
      }
      resolved.add(fresh);
      stillStored.add(fresh);
    }
    _mediaGrants = resolved;
    _storedGrants = stillStored;
    return moved;
  }

  /// The grants worth writing into this save, as JSON.
  ///
  /// Filtered HERE rather than in the writer, which runs in an isolate and
  /// has no business knowing what a grant is. A token for a file the pool
  /// no longer holds is a permission record for something nobody uses, and
  /// a project file that accumulates those is the shape that reads as an
  /// app hoarding access.
  List<Map<String, Object?>> _grantsToStore() {
    if (_storedGrants.isEmpty) {
      return const [];
    }
    final referenced = projectMediaPaths(_repository.requireProject());
    return [
      for (final grant in _storedGrants)
        if (referenced.any(grant.covers)) ?grant.toJson(),
    ];
  }

  /// Opens a .anicel file, replacing the WHOLE session state: project,
  /// drawings, selection (first cut, frame 0) — and BOTH undo stacks
  /// (loaded state has no history; the load→draw→undo path is pinned by
  /// test). [recoverAs] opens autosave SIDECAR bytes while keeping the
  /// real file as the project path (the recovery flow).
  Future<void> openProjectFromFile(
    String filePath, {
    String? recoverAs,
    String? overlayPath,
  }) async {
    final result = await _anicelFileService.open(
      filePath: filePath,
      overlayPath: overlayPath,
    );
    playback.stop();
    // BEFORE the project lands: a bookmark tracks the file rather than the
    // path, so resolving one is how a referenced movie that was renamed or
    // moved is found again — and the project has to be told, or the pool
    // goes on naming an address nothing answers at. This is the same move
    // the relative-path remap above makes, at the same moment, for the
    // same reason.
    final movedByGrant = await _resolveMediaGrants(result.grants);
    _repository.replaceProject(
      movedByGrant.isEmpty
          ? result.project
          : remapProjectMediaPaths(result.project, movedByGrant),
    );
    // What this project carries, as the file on disk says. Anything the
    // pool names that is NOT here is an ordinary outside reference and
    // resolves by path like it always did.
    _mediaEntryNames = result.mediaEntryNames;
    // Through the bookmark move as well. The service already narrowed these
    // against the RELATIVE-path remap it can see; this second move happens
    // out here, after a bookmark resolved to a file the user renamed, and
    // the service never learns about it. Two movers, both of which have to
    // be followed — miss one and the next save deletes the fact.
    _mediaFingerprints = result.mediaFingerprints.moved(movedByGrant);
    // R22-C: opens land every cel FILE-BACKED — pixels stay in the .anicel
    // until a cel is first shown (near-zero RAM for 1500-cut projects).
    // The conte ink namespace routes to its own stores (R5); a ROW entry
    // whose storyboard block no longer exists in the loaded project is
    // pruned HERE — the load boundary is where "ink dies with the
    // drawing" becomes permanent (saving never prunes, so an undone
    // delete keeps its ink within the session).
    final mainCels = <BrushFrameKey, AnicelCelFileRef>{};
    final inkRowCels = <BrushFrameKey, AnicelCelFileRef>{};
    final inkPageCels = <BrushFrameKey, AnicelCelFileRef>{};
    final envelopeCels = <BrushFrameKey, AnicelCelFileRef>{};
    Set<FrameId>? liveFrameIds;
    Set<CutId>? liveCutIds;
    for (final entry in result.cels.entries) {
      final key = entry.key;
      if (isEnvelopeInkKey(key)) {
        // An envelope's ink is keyed by its OWNER cut: the sheet dies with
        // the cut it describes. Which BOX a stroke sits in is never pruned
        // — swapping the form preset back has to bring the writing back
        // with it.
        liveCutIds ??= {
          for (final track in result.project.tracks)
            for (final cut in track.cuts) cut.id,
        };
        if (liveCutIds.contains(key.cutId)) {
          envelopeCels[key] = entry.value;
        }
      } else if (!isConteInkKey(key)) {
        mainCels[key] = entry.value;
      } else if (key.layerId == conteInkRowLayerId) {
        liveFrameIds ??= {
          for (final track in result.project.tracks)
            for (final cut in track.cuts)
              for (final layer in cut.layers)
                for (final frame in layer.frames) frame.id,
        };
        if (liveFrameIds.contains(key.frameId)) {
          inkRowCels[key] = entry.value;
        }
      } else {
        inkPageCels[key] = entry.value;
      }
    }
    brushFrameStore.restoreFromFile(mainCels);
    conteInkRowStore.restoreFromFile(inkRowCels);
    conteInkPageStore.restoreFromFile(inkPageCels);
    envelopeInkStore.restoreFromFile(envelopeCels);
    _historyManager.clear();
    _copiedFrame = null;
    _layerClipboard = null;
    _editingSession.setActiveCutId(result.project.tracks.first.cuts.first.id);
    _rebuildActiveCutControllers();
    // The replaced project's shelf takes are no longer this session's to
    // adopt — they stay on the shelf, findable.
    _voiceRecording.forgetShelfTakes();
    _projectFilePath = recoverAs ?? filePath;
    // Remembered because the recovered work lives ONLY in that file — an
    // overlay holds the edited cels and every ref for them points inside
    // it, and the RAM tiers were just cleared — so until a save moves
    // those pixels into the project file, deleting it is deleting the
    // work. (A snapshot from an older build is a whole archive opened as
    // [filePath]; same reasoning, same field.) Reset on an ordinary open
    // so a later session never inherits another one's exception.
    _recoveredFromSidecar = overlayPath ?? (recoverAs == null ? null : filePath);
    // A different project is a different session; a discard that belonged
    // to the last one must not silence this one's snapshots.
    _discardedUnsavedWork = false;
    _settleConformCache();
    _warmAudioConforms();
    // RELINK-2: the first of the three refresh moments. A project opened
    // on a machine that does not have its referenced media has to SAY so —
    // that is the whole point of the banner, and it is the one moment the
    // user has not done anything to prompt it.
    refreshMediaExistence();
    // A recovered session stays dirty: its content differs from the real
    // file until the user saves.
    _hasUnsavedChanges = recoverAs != null || overlayPath != null;
    _warmActiveCut();
    frameSeekCommitted.value += 1;
    notifyListeners();
  }

  // --- Frame flipping (P1 shortcuts) ----------------------------------------

  /// Steps the playhead one frame back (flipping `,`) — a committed seek,
  /// clamped at the cut start.
  void selectPreviousFrame() {
    final current = _timelineController.currentFrameIndex;
    if (current <= 0) {
      return;
    }
    selectFrameIndex(current - 1);
  }

  /// Steps the playhead one frame forward (flipping `.`), clamped at the
  /// cut's last frame.
  void selectNextFrame() {
    final cut = activeCutOrNull;
    if (cut == null) {
      return; // Gap state: no cut axis to flip along.
    }
    final last = math.max(0, cut.duration - 1);
    final current = _timelineController.currentFrameIndex;
    if (current >= last) {
      return;
    }
    selectFrameIndex(current + 1);
  }

  /// Steps one BLOCK back along [currentRow] (Ctrl+`,`).
  ///
  /// R10 #13, the user's rule with no exceptions: **whatever the row is,
  /// count THAT row's blocks; a block where there are blocks, a frame
  /// where there are none.** A layer row counts its exposure blocks, an SE
  /// row its sound blocks — the same code, because an SE row is a layer
  /// with a timeline and needs no branch of its own — and a V row counts
  /// CUTS, which is the only place a flip crosses a cut boundary.
  ///
  /// That last part is the rule's dividend: "coming out of a cut on a
  /// layer row, which row of the next cut do you land on?" is a question
  /// that never gets asked, because layer rows live inside one cut.
  void selectPreviousDrawing() => _flipRow(forward: false);

  /// Steps one BLOCK forward along [currentRow] (Ctrl+`.`). See
  /// [selectPreviousDrawing] for the rule.
  void selectNextDrawing() => _flipRow(forward: true);

  void _flipRow({required bool forward}) {
    switch (currentRow) {
      case TrackRowAddress(:final trackId):
        _flipCuts(trackId, forward: forward);
      case LayerRowAddress(:final layerId):
        final layer = _layerById(layerId) ?? activeLayer;
        if (layer == null) {
          // No such layer to stand on — the playhead is parked in a GAP
          // (no cut, so no rows), or the stored row outlived its cut. The
          // row you are actually on is the TRACK, so walk cuts rather
          // than dead-ending: that is how a gap is stepped out of.
          _flipCuts(selectedTrackId, forward: forward);
          return;
        }
        _flipBlocks(layer, forward: forward);
      case LaneRowAddress():
        // A lane's "blocks" would be its KEYS, but jumping key to key is
        // deferred by the user's own instruction — for now a property row
        // walks ONE FRAME, which is the same rule's other half ("a frame
        // where there are no blocks") rather than an exception written for
        // it. Attaching the key jump later changes this arm and nothing
        // else.
        if (forward) {
          selectNextFrame();
        } else {
          selectPreviousFrame();
        }
    }
  }

  /// The layer-row half: the row's drawing blocks are its columns.
  ///
  /// It used to step between authored KEYS, which is why the directions
  /// disagreed. A key list has no entry for an uncovered frame, so a gap
  /// between two blocks was not a destination at all: forward jumped
  /// clean over it, and backward — which had no equivalent of forward's
  /// "escape past the block I am on" clause — jumped all the way to the
  /// previous block's head. Counting COLUMNS instead makes both
  /// directions the same sentence and puts the gap back on the axis.
  ///
  /// Past the cut's last frame is still THIS row's axis. The timeline's
  /// frame axis is endless: it papers whatever has been scrolled into
  /// existence, marks the cut end with its boundary line and draws the
  /// cells beyond it dimmed. So rightward never runs out without the
  /// flip having to leave — handing the landing to the track would drop
  /// the row being flipped, which is the one thing a layer row must not
  /// do. Leftward the cut's own frame 0 is the floor, which keeps
  /// "which row of the next cut do I land on?" a question nobody asks.
  void _flipBlocks(Layer layer, {required bool forward}) {
    if (activeCutOrNull == null) {
      return; // Gap state: no cut axis — the TRACK row is the one to walk.
    }
    final current = _timelineController.currentFrameIndex;
    final next = flipColumnStep(
      frame: current,
      direction: forward ? 1 : -1,
      // A7① (2026-08-17): a HOLD is one flip unit — the column absorbs
      // hold-mode ghost tails/lead-ins into their owning run, so the flip
      // never lands inside a hold the HUD draws as empty. Repeat ghosts
      // stay their own columns; the merge lives HERE, in the flip's
      // column definition only (creation gates, painters and playback
      // keep reading raw coverage).
      columnAt: (frame) => holdMergedFlipColumnAt(layer, frame),
    );
    if (next != current && next >= 0) {
      selectFrameIndex(next);
    }
  }

  /// The V-row half: the track's CUTS are its columns, on the global axis.
  ///
  /// The same column step the layer row takes, with the track's cuts as
  /// the covering material instead of a layer's blocks — which is the
  /// whole point of stating the rule as columns. It carried the identical
  /// key-stepping defect before, so a gap between two cuts was skipped in
  /// both directions here too.
  ///
  /// This is also the axis a GAP is walked on: [selectGlobalFrame] lands
  /// the result inside a cut or parks it in the void, so a playhead
  /// standing between cuts can step out under its own power.
  void _flipCuts(TrackId trackId, {required bool forward}) {
    // The MEMOIZED layout (identity-keyed on the project): a flip step is
    // a per-move cost, and rebuilding the whole cross-track layout for
    // each one is exactly the tax that memo exists to remove.
    final entries = [
      for (final entry in _projectLayout())
        if (entry.trackId == trackId) entry,
    ];
    if (entries.isEmpty) {
      return;
    }
    final axis = TrackFrameAxis(entries);
    final globalFrame = editingGlobalFrame;
    final next = flipColumnStep(
      frame: globalFrame,
      direction: forward ? 1 : -1,
      columnAt: (frame) {
        final block = axis.cutBlockAt(frame);
        return block == null
            ? null
            : (start: block.startIndex, endExclusive: block.endIndexExclusive);
      },
    );
    // The start of the film is the only floor; rightward the runway past
    // the last cut is a place you may stand.
    if (next != globalFrame && next >= 0) {
      // Land on the axis the step was measured on: this row may name a
      // track that is not the selected one.
      selectGlobalFrame(next, onAxis: axis);
    }
  }

  // --- Editing frame scrub (ruler drags ride the cursor path) --------------

  /// The editing playhead as a VALUE stream: every seek — scrub moves
  /// included — lands here, so cursor-driven widgets (timeline cursor
  /// layer, frame counter, the canvas scrub preview) follow pointer-fast
  /// without a session notify rebuilding the tree.
  final ValueNotifier<int> editingFrameCursor = ValueNotifier<int>(0);

  /// Bumped once per committed seek ([selectFrameIndex]) — a serial, not a
  /// frame (a same-frame commit must still fire after a scrub returned to
  /// its start). Seek-dependent panels subscribe here instead of the full
  /// session notify.
  final ValueNotifier<int> frameSeekCommitted = ValueNotifier<int>(0);

  /// True while a ruler scrub is in flight.
  ///
  /// 🚨★★★ #26 (2026-08-15): THIS NO LONGER SWAPS THE DISPLAY. It used to —
  /// the canvas became the composite-cache preview until the release commit
  /// — and the user's law retired that: 「그냥 액티브레이어급으로 그냥 원본
  /// 보여주게하고싶어 … 그냥 항상 full」. A scrub shows the editing canvas,
  /// which follows the cursor through the canvas area's retarget scope.
  ///
  /// ⛔What it still decides is the GAP ANSWER: a parked global reads as a
  /// gap only while the gesture is live (the `_gapGlobalFrame` read below),
  /// so the flag stays and the canvas rebuilds at enter and leave.
  final ValueNotifier<bool> frameScrubActive = ValueNotifier<bool>(false);

  /// A scrub move: repositions the playhead WITHOUT notifying — only the
  /// cursor listenables fire; the full session notify is deferred to
  /// [commitFrameScrub] on release.
  ///
  /// ⛔The cursor is not decoration: since #26 the editing canvas listens to
  /// it, so this is what makes the scrub show the crossed frame. It fires on
  /// the same-frame branch too — a tap that lands where it already was is a
  /// no-op the retarget scope swallows by index.
  void scrubFrameIndex(int frameIndex) {
    // R15-⑤: scrubs are seeks too — refused under a live edit.
    if (editingInteractionBusy) {
      return;
    }
    if (frameIndex != _timelineController.currentFrameIndex) {
      _timelineController.selectFrameIndex(frameIndex);
      editingFrameCursor.value = frameIndex;
      _syncPlayheadHasCel();
      // Each crossed frame plays its slice of the mix (2D audio scrub).
      audioScrubber.onScrubFrame(frameIndex);
      if (!frameScrubActive.value) {
        frameScrubActive.value = true;
        // One warm per gesture. A scrub is a seek and every other seek
        // warms; per-move warms would only thrash the scheduler's ordering.
        _warmActiveCut();
      }
    } else {
      editingFrameCursor.value = frameIndex;
    }
  }

  /// 🚨★★★ 유저 #6 (2026-08-14): 「룰러로 이동할때, **블록이 있으면 사용가능**
  /// 타임라인버튼 활성화되는식으로 버튼 상태 바꼈으면 좋겠는데 안바뀜.
  /// **효율좋게** 하는데 바뀌게 하고싶음. 갱신을 매 룰러 드래그마다가 아니라
  /// **해당 인덱스에 버튼이 있으면 한번, 없으면 한번** 이런식으로?」
  ///
  /// ★The user named the mechanism, and this is it: a scrub deliberately
  /// does NOT notify the session — 「Seeks are NOT session notifies」, which
  /// is what keeps a ruler drag from rebuilding every panel per frame — so
  /// the toolbar never re-asked its predicates and the buttons sat stale
  /// for the whole gesture.
  ///
  /// A `ValueNotifier<bool>` costs one comparison per crossed frame and
  /// fires only when the ANSWER flips, so a drag across twenty empty frames
  /// rebuilds the toolbar零 times and the frame that reaches a block
  /// rebuilds it once. That is 「있으면 한번, 없으면 한번」 exactly.
  ///
  /// ⛔One boolean rather than each button's own predicate: they nearly all
  /// reduce to 「is there a cel under the playhead」, and a notifier per verb
  /// would put the per-frame cost back that this exists to avoid.
  final ValueNotifier<bool> playheadHasCel = ValueNotifier<bool>(false);

  void _syncPlayheadHasCel() {
    playheadHasCel.value = selectedFrame != null;
  }

  /// The scrub gesture's release: ends the preview and commits the
  /// scrubbed playhead as ONE ordinary seek (warm + committed-seek signal).
  /// A drag that ended OUT of the active cut's territory carries its exact
  /// global in the parking — the deferred full seek lands here: over a cut
  /// it activates it (selectCut + local frame), in a gap it deselects and
  /// keeps the parking (UI-R9 #3). This is the ONLY place a global drag
  /// commits — the moves themselves never do.
  void commitFrameScrub() {
    audioScrubber.onScrubEnd();
    if (frameScrubActive.value) {
      frameScrubActive.value = false;
    }
    final parked = _gapGlobalFrame;
    if (parked != null) {
      // R15-⑤: a live editing interaction refuses the landing seek — the
      // parking stays put (the parked display state) instead of being
      // half-cleared.
      if (editingInteractionBusy) {
        return;
      }
      // The parking is cleared BEFORE the landing seek: selectCut must
      // not read a live drag's parking as a committed gap departure —
      // its fromGap branch would land frame 0 first and double the
      // committed-seek signal. A gap landing re-parks by itself.
      _gapGlobalFrame = null;
      selectGlobalFrame(parked);
      return;
    }
    selectFrameIndex(_timelineController.currentFrameIndex);
  }

  bool hasMarkForLayer(Layer layer, int frameIndex) {
    if (!layerKindHoldsDrawings(layer.kind)) {
      return false;
    }
    return _timelineController.hasMarkAt(layer: layer, frameIndex: frameIndex);
  }

  String? frameNameForLayer(Layer layer, int frameIndex) {
    if (layer.kind == LayerKind.camera) {
      // B4 (2026-08-17): the camera row's key summary no longer rides the
      // frame-name channel as a private ◆/■ text table. It is a
      // [transformUnionHeader] lane drawn by the shared lane key markers
      // ([timelineCameraUnionLane]) — the same code as the fx transform
      // header's union, which is what keeps its glyph a diamond mid-drag
      // and its size the one union constant. A camera layer has no cel
      // names, so the channel answers nothing here.
      return null;
    }
    // SYNCED attach mirrors PRINT THE BASE's cel name (UI-R24 #2 — the
    // name follows the owner; mirror cels are unnameable): the mirror row
    // reads 1ㅇㅇ----- exactly like its base.
    if (isSyncedAttachedLayer(layer)) {
      final base = attachedBaseOf(
        layer,
        activeCutOrNull?.layers ?? const <Layer>[],
      );
      if (base != null) {
        return _timelineController
            .resolveFrameForLayer(layer: base, frameIndex: frameIndex)
            ?.name;
      }
    }
    return _timelineController
        .resolveFrameForLayer(layer: layer, frameIndex: frameIndex)
        ?.name;
  }

  TimelineCellExposureState exposureStateForLayer(Layer layer, int frameIndex) {
    if (layerKindGroupsLayers(layer.kind)) {
      // R10: a folder row is a CELLS row whose coverage is the subtree
      // union, carried by its band clone's own timeline. HELD, never
      // drawingStart — a held cell prints no glyph, so the band stays
      // nameless (L5) without touching the shared marker table, and the
      // block chrome still wraps the whole merged run because the segment
      // rule bounds on coverage rather than on starts.
      return coveringDrawingBlockAt(layer.timeline, frameIndex) != null
          ? TimelineCellExposureState.held
          : TimelineCellExposureState.uncovered;
    }
    if (layer.kind == LayerKind.camera) {
      // The camera row's cells mirror [activeCutCameraTrack] — the ONE
      // preview-aware answer (lane move, block ride, or committed), the
      // same track the member lanes and the union markers read (B4), so
      // the row follows any drag while the repository stays untouched.
      return activeCutCameraTrack?.keyframeAt(frameIndex) != null
          ? TimelineCellExposureState.drawingStart
          : TimelineCellExposureState.uncovered;
    }

    if (_timelineController.isDrawingStartForLayer(
      layer: layer,
      frameIndex: frameIndex,
    )) {
      return TimelineCellExposureState.drawingStart;
    }

    final held = _timelineController.isHeldExposureForLayer(
      layer: layer,
      frameIndex: frameIndex,
    );
    // Block-owned dots live on held cells only (offsets 1..length-1), so
    // markUncovered is never produced anymore — the enum value survives
    // solely for exhaustive switches over legacy-visual states.
    if (held &&
        _timelineController.hasMarkAt(layer: layer, frameIndex: frameIndex)) {
      return TimelineCellExposureState.markHeld;
    }
    return held
        ? TimelineCellExposureState.held
        : TimelineCellExposureState.uncovered;
  }

  /// R26 #44: whether the drawing block covering [frameIndex] holds ANY
  /// picture in its cel — the ACTION-section rows' unworked-block tint
  /// reads this. Non-drawing sections (SE / camera / instruction) and
  /// uncovered cells always answer true (no tint).
  bool celHasContentForLayer(Layer layer, int frameIndex) {
    if (layerKindGroupsLayers(layer.kind)) {
      // R28 #11 carried onto the shared painter: a folder frame is grey
      // only when NO member drew there ("다른곳에서 해당위치에 그림그려진
      // 하얀 블록 존재하면 하얗게"). Without this arm the folder falls into
      // the drawing-section branch, resolves no frame of its own and
      // answers `true` — the union grey would vanish silently.
      return folderBandMembersOf(
        layer.id,
      ).any((member) => celHasContentForLayer(member, frameIndex));
    }
    if (timelineSectionForLayerKind(layer.kind) != TimelineSection.drawing) {
      return true;
    }
    final cut = activeCutOrNull;
    if (cut == null) {
      return true;
    }
    final frame = _timelineController.resolveFrameForLayer(
      layer: layer,
      frameIndex: frameIndex,
    );
    if (frame == null) {
      return true;
    }
    // A LIVE stroke already counts. The store only learns about pixels at
    // commit (`markCelEdited` on pen-up), so waiting for it left the block
    // grey for the whole stroke — the user asked for it to go white the
    // moment the line starts, which is also when the cel stops being
    // "unworked" in any sense that matters.
    if (brushInputActive.value &&
        layer.id == activeLayerId &&
        frame.id == selectedFrame?.id) {
      return true;
    }
    return brushFrameStore.celHasRenderableContent(
      brushFrameKeyForCut(cut, layer.id, frame.id),
    );
  }

  /// Bumps whenever [celHasContentForLayer] can have changed anywhere: the
  /// store crosses empty↔drawn, or the pen goes down on a cel.
  ///
  /// The store's own crossing signal (R27 #13) already existed and NOTHING
  /// SUBSCRIBED TO IT — which is the whole bug: the tint is derived state
  /// living outside the immutable Layer, so with no listener it only caught
  /// up when an unrelated edit announced app-wide (switch layers, rename a
  /// frame). This adds the live-stroke half and hands the row painters one
  /// thing to listen to.
  final ValueNotifier<int> celTintRevision = ValueNotifier<int>(0);

  void _bumpCelTintRevision() => celTintRevision.value += 1;

  // The per-layer "empty cels" memo TOKEN that used to live here is gone
  // with [celContentRevision]. It was the weaker form of the same idea: a
  // string rebuilt for every row on every pass, which forced a row REBUILD
  // and only when something else had already announced — which is exactly
  // why a freshly drawn block stayed grey until you switched layers.

  int? get selectedEffectiveDuration {
    final layer = activeLayer;
    if (layer == null || selectedFrame == null) {
      return null;
    }
    return _timelineController.effectiveDurationForLayerAt(layer: layer);
  }

  bool get canDecreaseSelectedExposure {
    final layer = activeLayer;
    if (layer == null) {
      return false;
    }
    final block = _timelineController.blockForLayerAt(layer: layer);
    return block != null && block.length > 1;
  }

  bool get canIncreaseSelectedExposure {
    final layer = activeLayer;
    if (layer == null) {
      return false;
    }
    return _timelineController.blockForLayerAt(layer: layer) != null;
  }

  // --- Status text --------------------------------------------------------

  String get currentLayerStatusText {
    final layer = activeLayer;
    return 'Layer: ${layer?.name ?? 'None'}';
  }

  String get currentFrameStatusText {
    return 'Frame: ${_timelineController.currentFrameIndex + 1}';
  }

  String get currentCellStatusText {
    final layer = activeLayer;
    if (layer == null) {
      return 'Cell: No layer';
    }

    return 'Cell: ${_cellStatusLabelForLayer(layer)}';
  }

  String get compactCellActionText {
    final layer = activeLayer;
    if (layer == null) {
      return 'No layer';
    }

    final frameIndex = _timelineController.currentFrameIndex;
    final exposureState = exposureStateForLayer(layer, frameIndex);
    final canPaste = canPasteLinkedFrameAtCurrentFrame;

    switch (exposureState) {
      case TimelineCellExposureState.drawingStart:
        return 'Drawing: Copy / Rename / Delete';
      case TimelineCellExposureState.held:
        return canPaste
            ? 'Held: Paste / Copy / Rename / Mark'
            : 'Held: Copy / Rename / Mark';
      case TimelineCellExposureState.markHeld:
        return canPaste
            ? 'Held + ●: Paste / Copy / Rename / Mark'
            : 'Held + ●: Copy / Rename / Mark';
      case TimelineCellExposureState.uncovered:
        // Dots are block-owned: an empty cell offers no Mark (author an
        // unnamed frame first).
        return canPaste ? 'X: Paste / New Frame' : 'X: New Frame';
      case TimelineCellExposureState.markUncovered:
        return canPaste
            ? 'X + ●: Paste / New Frame / Mark'
            : 'X + ●: New Frame / Mark';
    }
  }

  String _cellStatusLabelForLayer(Layer layer) {
    final frameIndex = _timelineController.currentFrameIndex;
    final exposureState = exposureStateForLayer(layer, frameIndex);
    return switch (exposureState) {
      TimelineCellExposureState.drawingStart => _drawingStartStatusForLayer(
        layer,
        frameIndex,
      ),
      TimelineCellExposureState.held => 'Held drawing',
      TimelineCellExposureState.markHeld => 'Held drawing + Mark ●',
      TimelineCellExposureState.uncovered => 'Empty (X)',
      TimelineCellExposureState.markUncovered => 'Empty (X) + Mark ●',
    };
  }

  String _drawingStartStatusForLayer(Layer layer, int frameIndex) {
    final frameName = frameNameForLayer(layer, frameIndex);
    if (frameName == null || frameName.isEmpty) {
      return 'Drawing start';
    }

    return 'Drawing start: $frameName';
  }

  // --- Canvas selection labels -------------------------------------------

  CanvasEditorSelectionLabels get canvasSelectionLabels {
    final project = _repository.requireProject();
    final cut = activeCutOrNull;
    final layer = _layerController.activeLayer;
    final frame = selectedFrame;
    return CanvasEditorSelectionLabels(
      projectLabel: project.name,
      // Gap state: no cut selected — the label says so.
      cutLabel: cut?.name ?? '—',
      layerLabel: layer?.name ?? '-',
      frameLabel: _currentFrameDisplayLabel(layer, frame),
    );
  }

  String _currentFrameDisplayLabel(Layer? layer, Frame? frame) {
    if (layer == null) {
      return '-';
    }
    final frameIndex = _timelineController.currentFrameIndex;
    final frameName = frame?.name;
    final exposureState = exposureStateForLayer(layer, frameIndex);
    return switch (exposureState) {
      TimelineCellExposureState.drawingStart =>
        frameName == null || frameName.isEmpty ? '○' : frameName,
      TimelineCellExposureState.held =>
        frameName == null || frameName.isEmpty ? '' : frameName,
      TimelineCellExposureState.markHeld =>
        frameName == null || frameName.isEmpty ? '●' : '$frameName ●',
      TimelineCellExposureState.uncovered => 'X',
      TimelineCellExposureState.markUncovered => '●',
    };
  }
}

class _CopiedFrameReference {
  const _CopiedFrameReference({
    required this.layerId,
    required this.frameId,
    required this.frameName,
    this.clip,
    this.cels = const [],
  });

  final LayerId layerId;

  /// The ANCHOR cel — what the status line names and what the old one-cel
  /// paste gate asks about. It is the clip's first drawing, kept as its own
  /// field because "is there something to paste into this row" is a
  /// question about a cel belonging to a layer, not about a run.
  final FrameId frameId;
  final String? frameName;

  /// 🚨T3 — the run that was copied, 코마째. Null only for a clipboard
  /// written before the run existed (no such writer remains); readers treat
  /// null as "one cell of [frameId]", which is exactly what the retired
  /// behaviour did.
  final TimelineClipRow? clip;

  /// 🚨The CELS the clip's exposures point at, carried by value.
  ///
  /// Without this a 잘라내기 is lossy: the lift orphans the cels it took
  /// out, the layer drops them, and pasting them back finds nothing to point
  /// at — cut-then-paste, the most ordinary thing anyone does with a
  /// clipboard, would silently do nothing. A clipboard that does not hold
  /// what was put on it is not one.
  ///
  /// ⛔Re-added only when MISSING. A copy leaves the originals where they
  /// are, and adding them again would put one cel in the layer twice.
  final List<Frame> cels;
}

/// Which verb an in-flight cut-edge drag belongs to (feedback #5/#9). One
/// shape of edge, and where it sat when the drag began decides what it
/// re-times; the session keeps the answer so the continuations cannot be
/// re-routed by anything a live preview rebuilds.
enum _CutEdgeDragVerb {
  /// Both cut edges' plain duration/gap drags. R10 R4 folded the lead
  /// edge's second verb into this one: a conte row no longer changes what
  /// dragging a cut's front edge means, only how far it may go.
  cutTrim,

  /// ANY panel's trailing edge: that cell's comma, the later panels
  /// rippling glued and the cut's length riding the row end (feedback
  /// #9; the edge unification retired the division verb this replaced).
  comma,
}

/// WHERE a lane-range move's keys live, how they go back, and what a step
/// in flight looks like — resolved once from the selection so the drag's
/// three steps stop naming their subjects inline.
///
/// See [EditorSessionManager._laneMoveSubjectFor] for why this exists: the
/// two subjects the old inline lists forgot are exactly the two rows whose
/// keys could not be moved by selection at all.
class _LaneMoveSubject {
  const _LaneMoveSubject({
    required this.transformTrack,
    required this.effects,
    required this.commitTransform,
    required this.commitEffects,
    required this.previewTransform,
    required this.previewEffects,
    this.onPreviewTransform,
  });

  /// The transform lanes' keys, and the effect chain's. Which one a drag
  /// reads is the LANE's question — an effect lane on a camera row moves
  /// the layer's chain while its Position lane moves the cut's camera.
  final TransformTrack transformTrack;
  final List<LayerEffect> effects;

  final void Function(TransformTrack next) commitTransform;
  final void Function(List<LayerEffect> next) commitEffects;

  final BlockMoveDragPreview Function(TransformTrack next) previewTransform;
  final BlockMoveDragPreview Function(List<LayerEffect> next) previewEffects;

  /// A side channel for subjects whose lanes are NOT built from the row's
  /// own Layer, so the preview cannot travel in [previewTransform]'s
  /// payload. Only the camera has one today.
  final void Function(TransformTrack next)? onPreviewTransform;
}

/// B8 — the block under the STORYBOARD cursor (standing row × track-global
/// playhead), resolved once per verb so the gates and the dispatches read
/// one answer. Kinds, not rules: every kind takes the same verbs (comma =
/// length, delete = removal), each through its own existing machinery.
sealed class _StoryboardCursorBlock {
  const _StoryboardCursorBlock();
}

class _StoryboardCursorCutBlock extends _StoryboardCursorBlock {
  const _StoryboardCursorCutBlock(this.cut);

  final Cut cut;
}

class _StoryboardCursorSeBlock extends _StoryboardCursorBlock {
  const _StoryboardCursorSeBlock(this.layerId, this.blockStartIndex);

  final LayerId layerId;

  /// GLOBAL — the S rows' timelines live on the track's axis.
  final int blockStartIndex;
}

class _StoryboardCursorTransitionSpan extends _StoryboardCursorBlock {
  const _StoryboardCursorTransitionSpan(this.spanStartIndex, this.spanLength);

  final int spanStartIndex;
  final int spanLength;
}
