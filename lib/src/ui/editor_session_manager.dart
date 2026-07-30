import 'dart:async' show Timer, unawaited;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui show ImageByteFormat;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../controllers/default_cut_helpers.dart'
    show createDefaultCut, defaultCutCanvasSize;
import '../controllers/default_layer_helpers.dart';
import '../models/import/cut_folder_parse.dart';
import '../services/commands/import_media_command.dart';
import '../services/import/media_import_planner.dart';
import '../services/import/raster_cel_import.dart';
import '../services/pdf/pdf_render_service.dart';
import '../models/app_language.dart';
import '../services/persistence/app_language_settings_store.dart';
import '../services/persistence/app_accent_settings_store.dart';
import '../services/persistence/app_workspace_colors_store.dart';
import '../services/persistence/app_input_settings_store.dart';
import '../services/persistence/app_documents.dart' show appRecordingsDirectory;
import '../services/persistence/app_save_settings.dart';
import '../services/persistence/app_save_settings_store.dart';
import '../services/persistence/audio_sync_settings_store.dart';
import 'input/app_input_settings.dart';
import 'theme/app_accents.dart';
import 'theme/app_theme.dart' show AppColors;
import 'theme/app_workspace_colors.dart';
import '../controllers/active_cut_helpers.dart';
import '../controllers/editing_session_state.dart';
import '../controllers/layer_controller.dart';
import '../controllers/timeline_controller.dart';
import '../models/attached_layer_resolve.dart';
import '../models/attached_mode.dart';
import '../models/attached_placement.dart';
import '../models/bitmap_surface.dart';
import '../models/audio_clip.dart';
import '../models/brush_frame_key.dart';
import '../models/conte/conte_ink_keys.dart';
import '../models/camera_instruction.dart';
import '../models/camera_pose.dart';
import '../models/canvas_point.dart';
import '../models/canvas_resize_anchor.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/cut_camera.dart';
import '../models/transform_track.dart';
import '../models/cut_id.dart';
import '../models/cut_move_plan.dart';
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
import '../models/timeline_frame_range.dart';
import '../models/timeline_repeat.dart';
import '../models/timeline_row_address.dart';
import '../models/timeline_run_edit.dart';
import '../models/track.dart';
import '../models/track_frame_range.dart';
import '../models/track_id.dart';
import '../models/track_se_window.dart';
import '../models/track_transform_lane_carrier.dart';
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
import 'storyboard_cut_fade_policy.dart';
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
import '../services/commands/rekey_brush_frames_command.dart';
import '../services/commands/update_layer_effects_command.dart';
import '../services/commands/update_layer_transform_enabled_command.dart';
import '../services/commands/relink_media_asset_command.dart';
import '../services/commands/update_cut_camera_command.dart';
import '../services/commands/update_layer_fill_reference_command.dart';
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
import '../native/qa_audio_native.dart' show QaAudioNative;
import '../native/qa_audio_device.dart'
    show
        QaAudioDevice,
        audioInputDeviceIndexByName,
        audioOutputDeviceIndexByName;
import '../services/audio/audio_mixer_reference.dart'
    show AudioMixClip, AudioMixSource;
import 'playback/audio_input_monitor.dart';
import 'playback/audio_playback_schedule.dart' show ScheduledAudioClip;
import '../services/audio/audio_conform_pipeline.dart' show ProjectAssetLayout;
import '../services/audio/conform_wav_codec.dart' show encodeConformWav;
import '../services/commands/update_media_assets_command.dart';
import '../models/se_take_placement.dart';
import '../services/audio/audio_peaks_extractor.dart' show AudioPeaks;
import 'playback/audio_recorder.dart';
import 'playback/voice_take_processing.dart';
import '../services/audio/audio_conform_runner.dart' show runConformHere;
import '../services/commands/track_se_layer_commands.dart';
import '../services/history_manager.dart';
import '../services/project_repository.dart';
import 'audio/audio_conform_store.dart';
import 'brush/brush_canvas_panel.dart';
import 'brush/brush_editor_selection.dart';
import 'timeline/instruction_span_editing.dart';
import 'timeline/layer_label_controls.dart' show layerKindShowsBlendControl;
import 'timeline/layer_timeline_display_adapter.dart'
    show horizontalLayerDisplayOrder;
import 'timeline/timeline_cell_exposure_state.dart';
import 'timeline/timeline_drag_preview.dart';
import 'timeline/timeline_section_policy.dart';
import 'timeline/effect_lane_editing.dart'
    show
        effectLaneKeyFrames,
        effectsWithLaneKeyToggled,
        effectsWithLaneSpanKeysShifted;
import 'timeline/effect_lane_policy.dart'
    show effectLaneSpan, parseEffectLaneId;
import 'timeline/transform_lane_editing.dart'
    show
        transformLaneKeyFrames,
        transformTrackWithLaneKeyToggled,
        transformTrackWithLaneSpanKeysShifted;
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
       _audioSyncSettingsStore = audioSyncSettingsStore,
       _languageSettingsStore = languageSettingsStore,
       _accentSettingsStore = accentSettingsStore,
       _inputSettingsStore = inputSettingsStore,
       _saveSettingsStore = saveSettingsStore,
       _workspaceColorsStore = workspaceColorsStore,
       _repository = ProjectRepository(initialProject: initialProject) {
    unawaited(_restoreLanguageSettings());
    unawaited(_restoreAccentSettings());
    unawaited(_restoreWorkspaceColors());
    unawaited(_restoreInputSettings());
    unawaited(_restoreSaveSettings());
    unawaited(_restoreAudioSyncSettings());
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

  // --- Language settings (UI-R10 #7) ----------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppLanguageSettingsStore? _languageSettingsStore;

  /// The program + notation languages — a value-only channel (widgets
  /// subscribe where they read strings; no whole-session notify).
  ///
  /// The notifier itself lives app-wide on [AppText.settings], so canvas
  /// widgets that hold no session still read the chosen language; this is
  /// that same object, not a copy.
  ValueNotifier<AppLanguageSettings> get languageSettings => AppText.settings;

  /// The PROGRAM-language string table, read at call time — for session
  /// verbs that produce user-facing messages and for widgets that already
  /// hold the session.
  AppStrings get uiStrings =>
      AppStrings.of(languageSettings.value.programLanguage);

  Future<void> _restoreLanguageSettings() async {
    final restored = await _languageSettingsStore?.load();
    if (restored != null) {
      languageSettings.value = restored;
    }
  }

  void setLanguageSettings(AppLanguageSettings settings) {
    if (settings == languageSettings.value) {
      return;
    }
    languageSettings.value = settings;
    final store = _languageSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  // --- Accent settings (UI-R22 #5) ------------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppAccentSettingsStore? _accentSettingsStore;

  /// The LIVE accents live app-wide on [AppColors.accentSettings] (the
  /// theme root rebuilds off it); the session only restores/persists.
  Future<void> _restoreAccentSettings() async {
    final restored = await _accentSettingsStore?.load();
    if (restored != null) {
      AppColors.accentSettings.value = restored;
    }
  }

  void setAccentSettings(AppAccentSettings settings) {
    if (settings == AppColors.accentSettings.value) {
      return;
    }
    AppColors.accentSettings.value = settings;
    final store = _accentSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  // --- Workspace colors (R28 #9) --------------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppWorkspaceColorsStore? _workspaceColorsStore;

  /// The app-level workspace colors are the NEW-PROJECT DEFAULTS now
  /// (R3b): the pasteboard itself became project data — it prints, so it
  /// travels with the project (R28 #9 reversed by the user, 2026-07-29).
  /// This restore keeps the stored default alive for the next project.
  Future<void> _restoreWorkspaceColors() async {
    final restored = await _workspaceColorsStore?.load();
    if (restored != null) {
      AppWorkspaceColors.settings.value = restored;
    }
  }

  /// One undo step; no-op when unchanged. Writes the PROJECT's pasteboard
  /// (R3b promotion) — and remembers the choice as the app-level default
  /// for the NEXT project, which is all that remains of the old app-state
  /// pasteboard.
  void setPasteboardColor(int argb) {
    _cutCommandCoordinator.setProjectPasteboard(argb);
    notifyListeners();
    final next = AppWorkspaceColors.settings.value.copyWith(
      pasteboardArgb: argb,
    );
    if (next == AppWorkspaceColors.settings.value) {
      return;
    }
    AppWorkspaceColors.settings.value = next;
    final store = _workspaceColorsStore;
    if (store != null) {
      unawaited(store.save(next));
    }
  }

  /// One undo step; no-op when unchanged. The BACKDROP (R3b): the stage's
  /// opaque floor — what a fade reveals and what an opaque export bakes
  /// where nothing covers.
  void setProjectBackdrop(int argb) {
    _cutCommandCoordinator.setProjectBackdrop(argb);
    notifyListeners();
  }

  // --- Input settings (UI-R22 #6) -------------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppInputSettingsStore? _inputSettingsStore;

  Future<void> _restoreInputSettings() async {
    final restored = await _inputSettingsStore?.load();
    if (restored != null) {
      AppInput.settings.value = restored;
    }
  }

  void setInputSettings(AppInputSettings settings) {
    if (settings == AppInput.settings.value) {
      return;
    }
    AppInput.settings.value = settings;
    final store = _inputSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  // --- Save settings (SAVE-1) -----------------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AppSaveSettingsStore? _saveSettingsStore;

  Future<void> _restoreSaveSettings() async {
    final restored = await _saveSettingsStore?.load();
    if (restored != null) {
      AppSave.settings.value = restored;
    }
  }

  void setSaveSettings(AppSaveSettings settings) {
    if (settings == AppSave.settings.value) {
      return;
    }
    AppSave.settings.value = settings;
    final store = _saveSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  // --- A/V offset (audio program 2D) ----------------------------------------

  /// Injectable persistence; null (tests) keeps the in-memory defaults.
  final AudioSyncSettingsStore? _audioSyncSettingsStore;

  /// The user's A/V offset — the residual correction for THIS machine's
  /// output path (screen pipeline, Bluetooth, an AV receiver). App state,
  /// not project state: a rig's delay must not travel inside a `.anicel`.
  final ValueNotifier<AudioSyncSettings> audioSyncSettings =
      ValueNotifier<AudioSyncSettings>(AudioSyncSettings.defaults);

  Future<void> _restoreAudioSyncSettings() async {
    final restored = await _audioSyncSettingsStore?.load();
    if (restored != null) {
      audioSyncSettings.value = restored;
    }
  }

  void setAudioSyncSettings(AudioSyncSettings settings) {
    if (settings == audioSyncSettings.value) {
      return;
    }
    audioSyncSettings.value = settings;
    final store = _audioSyncSettingsStore;
    if (store != null) {
      unawaited(store.save(settings));
    }
  }

  /// App-level brush stroke store shared with the canvas host, so commands
  /// (e.g. anchored canvas resize) can transform stroke data.
  ///
  /// The link resolver reads the CURRENT project's registry on every
  /// resolve (L1) — link edits need no event plumbing to reach the store.
  late final BrushFrameStore brushFrameStore = BrushFrameStore()
    ..setLinkResolver(
      (key) =>
          _repository.currentProject?.linkRegistry.canonicalCelKey(key) ?? key,
    );

  /// The conte sheet ink's cel stores (R5) — SESSION-owned so the .anicel
  /// archive can persist them (the second cel namespace), while the ink
  /// controller (workspace UI) keeps the coordinators. The ROW store's
  /// keys carry storyboard block [FrameId]s: entries whose block no longer
  /// exists are pruned at LOAD (never at save — a deleted block's ink must
  /// survive its own undo), so "ink dies with the drawing" lands at the
  /// session boundary.
  final BrushFrameStore conteInkRowStore = BrushFrameStore();
  final BrushFrameStore conteInkPageStore = BrushFrameStore();

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
  void enforcePlaybackCacheBudget() =>
      _playbackCacheBudgetEnforcer.enforce(protect: _playbackProtectedRanges());

  /// What budget eviction must never touch: the full PLAYING playlist while
  /// playback is active (a looping pass must keep every cut warm so the
  /// second pass plays fully cached), otherwise the active cut's range.
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
        endFrame: math.max(0, cut.duration - 1),
        quality: playbackQuality,
      ),
    ];
  }

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
    if (row is LayerRowAddress && isTrackSeLayerId(row.layerId)) {
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
        final owner = _trackSeAnywhere(layerId)?.track;
        var trackMoved = false;
        if (owner != null && selectedTrackId != owner.id) {
          _editingSession.setSelectedTrackId(owner.id);
          trackMoved = true;
        }
        if (_storeStoryboardRow(row) || trackMoved) {
          notifyListeners();
        }
      case TrackRowAddress(:final trackId):
        selectTrackCutAtPlayhead(trackId);
    }
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

  bool isTrackSeLayerId(LayerId layerId) =>
      activeTrack.seLayers.any((layer) => layer.id == layerId);

  /// Whether the active row can carry an on-canvas name tag (R5b): the
  /// SE rows, and only while a cut gives the canvas its geometry.
  bool get canEditActiveSeNameTag =>
      activeLayer?.kind == LayerKind.se && activeCutOrNull != null;

  /// The stacked default position the active SE row draws with today —
  /// what the editor SEEDS its fields from, without writing it: pinning a
  /// per-cut default into absolute pixels would strand the tag on a
  /// differently sized cut.
  Offset? get activeSeNameTagDefaultPosition {
    final layer = activeLayer;
    final cut = activeCutOrNull;
    if (layer == null || cut == null || layer.kind != LayerKind.se) {
      return null;
    }
    var rowOffset = 0;
    for (final track in _repository.requireProject().tracks) {
      final rowIndex = track.seLayers.indexWhere((row) => row.id == layer.id);
      if (rowIndex >= 0) {
        return defaultSeNameTagPosition(
          canvas: cut.canvasSize,
          cameraFrame: cameraFrameSize,
          rowIndex: rowIndex,
          rowOffset: rowOffset,
        );
      }
      rowOffset += track.seLayers.length;
    }
    return null;
  }

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

  void _onBrushFrameInvalidated(BrushFrameCacheInvalidation invalidation) {
    layerFrameImageCache.invalidateFrame(invalidation.frameKey);
    cutFrameCompositeCache.invalidateWhereLayerFrame(
      layerId: invalidation.frameKey.layerId,
      frameId: invalidation.frameKey.frameId,
    );
    // Warming yields to the edit and then re-renders the dirty frames.
    prerenderScheduler.notifyEditActivity();
    _warmActiveCut();
  }

  /// Warms the active cut's composites around the playhead ("navigate away
  /// from a frame and it gets pre-rendered").
  void _warmActiveCut() {
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    prerenderScheduler.requestWarmCut(
      cutId: cut.id,
      quality: playbackQuality,
      aroundFrameIndex: _timelineController.currentFrameIndex,
    );
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
    cacheInvalidationHub.removeBrushFrameListener(_onBrushFrameInvalidated);
    playback.globalFrameIndexListenable.removeListener(_followPlaybackCut);
    _historyManager.removeListener(_markProjectDirty);
    _historyManager.removeListener(_refreshLiveAudioSchedule);
    _historyManager.removeListener(_scheduleTextCelBakeSweep);
    _voiceRecorder?.dispose();
    isVoiceRecording.dispose();
    voiceRecordingNotice.dispose();
    voiceRecordPreviewLane.dispose();
    voiceRecordClipLit.dispose();
    _testToneTimer?.cancel();
    _voiceRecordCountInTimer?.cancel();
    _deleteCueBeepDirectory();
    detachInputMeter();
    audioPlaybackSync.dispose();
    audioScrubber.dispose();
    audioDeviceTransport.dispose();
    playback.dispose();
    prerenderScheduler.dispose();
    cutFrameCompositeCache.dispose();
    layerFrameImageCache.dispose();
    audioConformStore.dispose();
    // languageSettings is NOT disposed here: it lives on AppText, app-wide,
    // and outlives this session (as the accent settings do).
    audioSyncSettings.dispose();
    soloedSeLayerIds.dispose();
    editingFrameCursor.dispose();
    frameScrubActive.dispose();
    frameSeekCommitted.dispose();
    _gapGlobalFrameNotifier.dispose();
    frameRangeSelection.dispose();
    brushInputActive.dispose();
    selectionInteractionActive.dispose();
    dragPreview.dispose();
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
  /// ONCE per file off the UI isolate. Conforms live in
  /// `<project>.assets/Conformed/`, derived by rule from the source path —
  /// nothing recorded, nothing to fall out of sync.
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

  String? _conformPathFor(String sourcePath) {
    final path = _projectFilePath;
    return path == null
        ? null
        : ProjectAssetLayout(path).conformPathFor(sourcePath);
  }

  /// Every audio path the project references (SE clips + the media pool) —
  /// what a project open warms so waveforms and playback PCM are ready
  /// before the first play.
  void _warmAudioConforms() {
    final project = _repository.requireProject();
    final paths = <String>{
      for (final track in project.tracks)
        for (final layer in track.seLayers)
          for (final clip in layer.audioClips) clip.filePath,
      for (final asset in project.mediaAssets) asset.path,
    };
    audioConformStore.warmPaths(paths);
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

  void createCut() {
    _cutCommandCoordinator.createCut(
      trackId: selectedTrackId,
      // New cuts inherit the active cut's canvas size, like new scenes in
      // TVPaint/Clip Studio inherit the project size.
      canvasSize: activeCutOrNull?.canvasSize,
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
        layerAcceptsBrushInput(activeStackLayer)) {
      activeLayerOpacity = !activeStackLayer.isVisible
          ? 0.0
          : _stackLayerOpacity(activeStackLayer, stackCut.layers, frameIndex);
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
  double _stackLayerOpacity(Layer layer, List<Layer> layers, int frameIndex) {
    final base = isAttachedLayer(layer) ? attachedBaseOf(layer, layers) : null;
    final fxCarrier = base ?? layer;
    // The animated Opacity is a TRANSFORM property, so its own group's
    // switch decides it — not the row master (R8).
    if (!fxCarrier.transformEnabled) {
      return layer.opacity.clamp(0.0, 1.0).toDouble();
    }
    return (layer.opacity *
            resolveOpacityTrackAt(fxCarrier.transformTrack.opacity, frameIndex))
        .clamp(0.0, 1.0)
        .toDouble();
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

  /// [cutId]'s owning track's transform lanes; empty for an orphan.
  TransformTrack transformTrackForCut(CutId cutId) =>
      trackOwningCut(cutId)?.transformTrack ?? TransformTrack.empty();

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

  /// The ACTIVE cut's V-track pose over the CANVAS at [frameIndex]
  /// (default: the playhead) — the storyboard V-row fx preview on the
  /// EDITING canvas and the scrub preview (R9-B). Non-null only while the
  /// TRACK's geometric lanes carry keys AND the cut's fx apply;
  /// canvas-space via the camera-frame conjugation (the exact remap
  /// playback uses, R8-③). Resolved at the frame's GLOBAL position (R4).
  LayerPoseSample? activeCutCanvasPoseSample({int? frameIndex}) {
    final cut = activeCutOrNull;
    if (cut == null || !isCutFxEnabled(cut.id)) {
      return null;
    }
    final track = transformTrackForCut(cut.id);
    if (!trackPoseIsActive(track)) {
      return null;
    }
    final preview = trackPoseForCanvasPreview(
      track,
      trackGlobalFrameOf(
        cut.id,
        frameIndex ?? _timelineController.currentFrameIndex,
      ),
      cameraFrameSize: cameraFrameSize,
      canvasSize: cut.canvasSize,
    );
    return (pose: preview.pose, anchorPoint: preview.anchorPoint);
  }

  /// The fade the editing canvas (and the scrub preview) shows at
  /// [frameIndex] (default: the playhead) — the TRACK's opacity at the
  /// frame's global position while the cut's fx apply, 1 when bypassed.
  /// R9-C rule: fx ALWAYS reflects; dark faded frames are worked with the
  /// fx switch off.
  double activeCutEditingFadeOpacity({int? frameIndex}) {
    final cut = activeCutOrNull;
    if (cut == null || !isCutFxEnabled(cut.id)) {
      return 1;
    }
    return trackFadeOpacityAt(
      transformTrackForCut(cut.id),
      trackGlobalFrameOf(
        cut.id,
        frameIndex ?? _timelineController.currentFrameIndex,
      ),
    );
  }

  /// Whether the playback composite for [frameIndex] is warmed at the
  /// current quality (the timeline's cached-range "green bar").
  bool isPlaybackFrameCached(int frameIndex) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return false;
    }
    return isPlaybackFrameCachedForCut(cut, frameIndex);
  }

  /// [isPlaybackFrameCached] for an arbitrary cut — the storyboard's green
  /// bar spans every cut of the track.
  bool isPlaybackFrameCachedForCut(Cut cut, int frameIndex) {
    return cutFrameCompositeCache.validCompositeOrNull(
          cut: cut,
          frameIndex: frameIndex,
          quality: playbackQuality,
        ) !=
        null;
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

  /// The resolved camera pose at the current playhead frame (keyframe,
  /// interpolation, or the default pose when the cut has no camera work).
  CameraPose get cameraPoseAtCurrentFrame => resolveCameraPoseAt(
    camera: requireActiveCut.camera,
    canvasSize: requireActiveCut.canvasSize,
    frameIndex: _timelineController.currentFrameIndex,
  );

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
    _cutCommandCoordinator.updateCutCamera(
      cutId: cutId,
      camera: CutCamera.fromTrack(track),
      description: description,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Sets [cutId]'s fade in/out lengths (the storyboard V-track's fade
  /// handles): rewrites the canonical fade shape into the CUT'S WINDOW of
  /// the owning TRACK's opacity lane (R4 — keys outside the window are
  /// other cuts' fades and stay put); one undo step, no-op when unchanged.
  void setCutFade(
    CutId cutId, {
    required int fadeInFrames,
    required int fadeOutFrames,
  }) {
    final owner = trackOwningCut(cutId);
    final cut = cutById(cutId);
    if (owner == null || cut == null) {
      return;
    }
    updateTrackTransformTrack(
      owner.id,
      trackTransformWithCutFade(
        owner.transformTrack,
        startFrame: trackGlobalFrameOf(cutId, 0),
        duration: cut.duration,
        fadeInFrames: fadeInFrames,
        fadeOutFrames: fadeOutFrames,
      ),
      description: 'Fade cut',
    );
  }

  /// Replaces [trackId]'s transform lanes (the storyboard V track's
  /// Transform — the whole composed picture moving on the display space,
  /// keys on the GLOBAL axis, applied at display time and never baked
  /// into composites); one undo step, no-op when unchanged. The fade
  /// handles keep writing the same track through [setCutFade].
  void updateTrackTransformTrack(
    TrackId trackId,
    TransformTrack track, {
    String description = 'Edit track transform',
  }) {
    _cutCommandCoordinator.updateTrackTransform(
      trackId: trackId,
      transformTrack: track,
      description: description,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

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
      final nextEffects = [
        for (final effect in layer.effects) effect.copyWith(enabled: enabled),
      ];
      if (!listEquals(nextEffects, layer.effects)) {
        commands.add(
          UpdateLayerEffectsCommand(
            repository: _repository,
            cutId: _editingSession.activeCutId ?? _repository.requireProject()
                .tracks
                .first
                .cuts
                .first
                .id,
            layerId: layer.id,
            effects: nextEffects,
          ),
        );
      }
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
    _refreshAfterCutCommand();
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
    _refreshAfterCutCommand();
    notifyListeners();
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
    for (final layer in layers) {
      _visibilitySoloSnapshot?.putIfAbsent(layer.id, () => layer.isVisible);
      final shouldShow = layer.id == activeId;
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

  // --- Cut display toggles (session view state, not persisted) -------------

  /// Cuts whose cut-level FX (the V track's Transform group — the pose AND
  /// the fade, "opacity joins the transform system") are bypassed at
  /// DISPLAY time — the storyboard V-row fx switch (R9). Display-time only,
  /// like the cut pose itself: playback (canvas + camera view) skips
  /// pose/fade; the MP4 bake, PNG export and thumbnails are untouched.
  final Set<CutId> _fxBypassedCutIds = {};

  bool isCutFxEnabled(CutId cutId) => !_fxBypassedCutIds.contains(cutId);

  void toggleCutFx(CutId cutId) {
    if (!_fxBypassedCutIds.remove(cutId)) {
      _fxBypassedCutIds.add(cutId);
    }
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
    if (!activeLayer.isVisible) {
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
    if (activeLayer == null) {
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

  void duplicateActiveLayer() {
    final activeLayer = this.activeLayer;
    // Track-owned SE rows: duplication stands down (same clipboard-shape
    // reason as copyActiveLayer); attach rows too (v1 — a duplicate would
    // double-link the same base cels).
    if (activeLayer == null ||
        !layerKindIsClipboardCopyable(activeLayer.kind) ||
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

  void renameActiveLayer(String name) {
    final activeLayer = this.activeLayer;
    if (activeLayer == null) {
      return;
    }
    renameLayer(activeLayer.id, name);
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

  /// Kind-explicit Add Layer (the split button's ▾ list): the same naming
  /// and insertion rules as [addLayer] with the requested kind.
  void addLayerOfKind(LayerKind kind) {
    if (activeCutOrNull == null) {
      return; // Gap state: no cut to add into (SE rows need one too —
      //         selection lives in the cut-scoped row list).
    }
    _layerSequence += 1;
    final layerId = defaultLayerIdForSequence(_layerSequence);
    switch (kind) {
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
      case LayerKind.camera:
      // Folders are MADE, not added: 폴더 생성 wraps existing rows
      // ([groupActiveLayerIntoFolder]). Add Layer with a folder row active
      // adds a drawing cel, like it does with the camera active.
      case LayerKind.folder:
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
    _layerSequence += 1;
    final layerId = defaultLayerIdForSequence(_layerSequence);
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
  void toggleLayerTimesheet(LayerId layerId) {
    final layer = layers.firstWhere((layer) => layer.id == layerId);
    // A resolvable row implies an active cut (gap state has no rows).
    _cutCommandCoordinator.setLayerTimesheet(
      cutId: requireActiveCut.id,
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

  /// Shows/hides every layer belonging to [section] (the section bracket's
  /// flyout) — visibility semantics like [setAllLayersVisibility].
  void setSectionLayersVisibility(TimelineSection section, bool visible) {
    for (final layer in layers) {
      if (timelineSectionForLayerKind(layer.kind) == section &&
          layer.isVisible != visible) {
        _layerController.toggleLayerVisibility(layer.id);
      }
    }
    notifyListeners();
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
  void addAudioClipToActiveSeLayer(String filePath) {
    final layer = activeLayer;
    if (layer == null || layer.kind != LayerKind.se) {
      return;
    }
    // Copy-on-import into the project's Media/ folder (falls back to the
    // original path while unsaved), then conform from scratch — the file
    // may have changed on disk since a previous import.
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
    addMediaAssets([effectivePath]);
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

  // --- Audio import: originals into the project's Media/ folder ------------

  /// Brings [sourcePath] into the project: copies it into
  /// `<project>.assets/Media/` (the Pro Tools/Logic copy-on-import
  /// default — the project folder owns its sounds, so a Drive folder
  /// opened on another machine has them) and kicks its conform. Returns
  /// the path the project should reference from here on.
  ///
  /// Falls back to referencing [sourcePath] directly when there is nowhere
  /// to copy yet (never-saved project) or the copy fails — an import must
  /// degrade to Premiere-style referencing, never refuse.
  String importAudioFile(String sourcePath) {
    final effectivePath = _copyIntoProjectMedia(sourcePath);
    // Fresh conform + waveform budget: on a re-import the file may have
    // changed on disk. (A byte-identical reused copy re-fingerprints
    // against the existing conform and lands as `reused` without a
    // decode.)
    audioConformStore.invalidate(effectivePath);
    audioConformStore.warmPaths([effectivePath]);
    return effectivePath;
  }

  /// The media browser's import: same copy-in as a timeline import, pool
  /// only (no clip link). Non-audio kinds register with their detected
  /// kind (R3b) — the batch stays one undo through [addMediaAssets].
  void importMediaFiles(List<String> paths) {
    final pool = mediaAssets;
    final known = {for (final asset in pool) asset.path};
    final added = <MediaAsset>[];
    for (final path in paths) {
      final kind = mediaAssetKindForPath(path) ?? MediaAssetKind.image;
      final effectivePath = kind == MediaAssetKind.audio
          ? importAudioFile(path)
          : _copyIntoProjectMedia(path);
      if (!known.add(effectivePath)) {
        continue;
      }
      added.add(
        MediaAsset(
          path: effectivePath,
          name: mediaAssetDefaultName(effectivePath),
          kind: kind,
          sourcePath: effectivePath == path ? null : path,
          sourceStamp: _mediaSourceStampFor(path),
        ),
      );
    }
    if (added.isEmpty) {
      return;
    }
    _cutCommandCoordinator.updateMediaAssets([...pool, ...added]);
    notifyListeners();
  }

  String? _mediaSourceStampFor(String path) {
    try {
      final stat = File(path).statSync();
      return mediaSourceStamp(
        lengthBytes: stat.size,
        modifiedMillis: stat.modified.millisecondsSinceEpoch,
      );
    } on Object {
      return null;
    }
  }

  // --- Media import (R3b): stills, GIF sequences, cut folders -------------

  int _importCutSequence = 0;

  ImportIdMint _importIdMint() => ImportIdMint(
    nextLayerId: () {
      _layerSequence += 1;
      return defaultLayerIdForSequence(_layerSequence);
    },
    nextFrameId: (layerId) => FrameId(_nextFrameId(layerId)),
    nextCutId: () {
      _importCutSequence += 1;
      final usedIds = {
        for (final track in _repository.requireProject().tracks)
          for (final cut in track.cuts) cut.id.value,
      };
      var candidate = 'import-cut-$_importCutSequence';
      while (usedIds.contains(candidate)) {
        _importCutSequence += 1;
        candidate = 'import-cut-$_importCutSequence';
      }
      return CutId(candidate);
    },
  );

  /// Imports one still or animated image file (PNG/JPEG/GIF…) — the
  /// import window's core verb. Reference mode (default) copies into
  /// `.assets/Media/`, registers the asset and stamps
  /// [Layer.mediaReference]; rasterize absorbs the pixels with no
  /// registration (§3). One undo step; the baked cels display through
  /// the ordinary store paths. Returns false when nothing imported.
  Future<bool> importImageFile({
    required String path,
    required ImportDestination destination,
    bool rasterize = false,
    MediaFitMode fit = MediaFitMode.contain,
    int? lengthFrames,
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
      bytes = await File(path).readAsBytes();
    } on Object {
      return false;
    }
    final List<DecodedImageFrame> decoded;
    try {
      decoded = await decodeImageFrames(bytes);
    } on Object {
      return false;
    }
    if (decoded.isEmpty) {
      return false;
    }
    final canvasSize =
        targetCut?.canvasSize ??
        activeCutOrNull?.canvasSize ??
        defaultCutCanvasSize;
    final project = _repository.requireProject();
    final mint = _importIdMint();
    final storedPath = rasterize ? path : _copyIntoProjectMedia(path);
    final sourceStamp = _mediaSourceStampFor(path);
    final displayName = mediaAssetDefaultName(path);

    final cutId = targetCut?.id ?? mint.nextCutId();
    final stillDuration = destination == ImportDestination.activeCutLayer
        ? (targetCut!.duration < 1 ? 1 : targetCut.duration)
        : (lengthFrames ?? project.fps);

    final Layer layer;
    final List<PlannedCelBake> bakes;
    final List<MediaAsset> assets;
    if (decoded.length == 1) {
      final plan = planStillImageLayer(
        sourceFile: storedPath,
        displayName: displayName,
        cutId: cutId,
        duration: stillDuration,
        fit: fit,
        rasterize: rasterize,
        mint: mint,
        sourcePath: storedPath == path ? null : path,
        sourceStamp: sourceStamp,
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
        sourceFiles: List<String>.filled(decoded.length, storedPath),
        frameFingerprints: fingerprints,
        displayName: displayName,
        cutId: cutId,
        fit: fit,
        rasterize: rasterize,
        mint: mint,
        referencePath: storedPath,
        sourcePath: storedPath == path ? null : path,
        sourceStamp: sourceStamp,
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
    bool rasterize = false,
    MediaFitMode fit = MediaFitMode.contain,
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
      final project = _repository.requireProject();
      final mint = _importIdMint();
      final storedPath = rasterize ? path : _copyIntoProjectMedia(path);
      final sourceStamp = _mediaSourceStampFor(path);
      final displayName = mediaAssetDefaultName(path);
      final cutId = targetCut?.id ?? mint.nextCutId();

      final Layer layer;
      final List<PlannedCelBake> bakes;
      final List<MediaAsset> assets;
      if (pageCount == 1) {
        // A one-page PDF is a still: an image-kind layer holding over the
        // cut, exactly like a placed PNG.
        final stillDuration = destination == ImportDestination.activeCutLayer
            ? (targetCut!.duration < 1 ? 1 : targetCut.duration)
            : project.fps;
        final plan = planStillImageLayer(
          sourceFile: storedPath,
          displayName: displayName,
          cutId: cutId,
          duration: stillDuration,
          fit: fit,
          rasterize: rasterize,
          mint: mint,
          sourcePath: storedPath == path ? null : path,
          sourceStamp: sourceStamp,
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
          sourceFiles: List<String>.filled(pageCount, storedPath),
          frameFingerprints: [for (var i = 0; i < pageCount; i += 1) i],
          displayName: displayName,
          cutId: cutId,
          fit: fit,
          rasterize: rasterize,
          mint: mint,
          referencePath: storedPath,
          sourcePath: storedPath == path ? null : path,
          sourceStamp: sourceStamp,
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
          duration: pageCount > 1 ? _sequenceLength(layer) : project.fps,
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
          try {
            final pageSize = document.pageSize(bake.sourceFrameIndex);
            final placement = placementRectFor(
              sourceWidth: pageSize.width.round().clamp(1, 1 << 13).toInt(),
              sourceHeight: pageSize.height.round().clamp(1, 1 << 13).toInt(),
              canvas: bakedCut.canvasSize,
              fit: bake.fit,
            );
            final image = await document.renderPage(
              bake.sourceFrameIndex,
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
            onPageRenderFailed?.call(bake.sourceFrameIndex);
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

    // References copy into the project's media folder like any import.
    final copiedAssets = [
      for (final asset in plan.assets)
        asset.copyWith(
          path: _copyIntoProjectMedia(asset.path),
          sourcePath: asset.path,
          sourceStamp: _mediaSourceStampFor(asset.path),
        ),
    ];

    _historyManager.execute(
      ImportMediaCommand(
        repository: _repository,
        editingSession: _editingSession,
        trackId: selectedTrackId,
        newCuts: [plan.cut],
        assetAdditions: copiedAssets,
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
            await File(bake.sourceFile).readAsBytes(),
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

  // --- Guide voice recording (AUDIO-PRO R5) --------------------------------

  /// True while the microphone is live — the record button's state.
  final ValueNotifier<bool> isVoiceRecording = ValueNotifier<bool>(false);

  /// A take the TRANSPORT finished (stop pressed mid-take): the message
  /// the toggle path would have returned, for whoever hosts the snackbar.
  /// Null = finished clean (or nothing to say).
  final ValueNotifier<String?> voiceRecordingNotice = ValueNotifier<String?>(
    null,
  );

  AudioRecorder? _voiceRecorder;
  LayerId? _voiceRecordLaneId;
  int _voiceRecordAnchorFrame = 0;
  int? _voiceRecordPunchEndFrame;
  int _voiceRecordHeadTrimSamples = 0;
  bool _voiceRecordStartedRoll = false;

  /// REC1-B2: the take shelf for a never-saved project — pinned at the
  /// first take so a mid-session settings change never scatters one
  /// session's takes across folders.
  String? _voiceRecordShelfDirectory;

  /// Every WAV this session recorded onto the shelf. The FIRST save
  /// adopts the still-referenced ones into `Media/`; undone takes stay
  /// on the shelf, findable.
  final Set<String> _voiceRecordShelfPaths = <String>{};

  /// Capture-chain settings SNAPSHOT at arm time (REC1-D): a take records
  /// with the gain/fold it started under; mid-take settings edits apply
  /// to the next one.
  int _voiceRecordGainDb = 0;
  VoiceInputChannelMode _voiceRecordChannelMode = VoiceInputChannelMode.device;
  bool _voiceRecordDenoise = false;
  bool _lastVoiceTakeClipped = false;

  /// The transport's clip light (REC1-D): latches on the first post-gain
  /// sample at the ceiling and stays lit for the rest of the take — the
  /// performer sees "that pass clipped" without reading a meter. Always
  /// on duty (the toast and block marker sit behind the notice toggle;
  /// this does not).
  final ValueNotifier<bool> voiceRecordClipLit = ValueNotifier<bool>(false);

  // --- ADR cueing (REC1-E) --------------------------------------------------

  /// Cue beeps riding the playback schedule while a take approaches its
  /// punch-in (REC1-E): three one-second-spaced beeps ending AT the
  /// punch — the "삐-삐-삐-(대사)" timing anchor, leaving the CHOSEN
  /// output device because they are ordinary schedule clips. Empty
  /// outside recording.
  List<ScheduledAudioClip> _voiceRecordCueClips = const [];
  List<ScheduledAudioClip> get voiceRecordCueClips => _voiceRecordCueClips;

  /// The streamer's window on the PLAYBACK axis (REC1-E): non-null while
  /// a take rolls toward a punch-in with the streamer enabled — the
  /// canvas overlay sweeps from [startFrame] to [punchFrame].
  ({int startFrame, int punchFrame})? _voiceRecordStreamerWindow;
  ({int startFrame, int punchFrame})? get voiceRecordStreamerWindow =>
      _voiceRecordStreamerWindow;

  Timer? _voiceRecordCountInTimer;
  String? _cueBeepPath;

  /// The OS temp folder holding [_cueBeepPath], kept so dispose can take it
  /// back. It is one small wav, but it was one small wav PER APP RUN left
  /// behind in the system temp forever.
  Directory? _cueBeepDirectory;

  void _deleteCueBeepDirectory() {
    final directory = _cueBeepDirectory;
    _cueBeepDirectory = null;
    _cueBeepPath = null;
    if (directory == null) {
      return;
    }
    try {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    } on Object {
      // A locked temp file is the OS's to clean up, not a shutdown failure.
    }
  }

  /// The cue beep on disk (project-rate mono, ~90 ms of 1 kHz with 5 ms
  /// ramps), written once per session and registered with the conform
  /// store like any take.
  String? _ensureCueBeepWav() {
    final existing = _cueBeepPath;
    if (existing != null && File(existing).existsSync()) {
      return existing;
    }
    try {
      final sampleRate = audioConformStore.projectSampleRate;
      final toneSamples = sampleRate * 9 ~/ 100;
      final ramp = sampleRate ~/ 200;
      final samples = Float32List(toneSamples);
      for (var sample = 0; sample < toneSamples; sample += 1) {
        var value = 0.5 * math.sin(2 * math.pi * 1000 * sample / sampleRate);
        if (sample < ramp) {
          value *= sample / ramp;
        } else if (sample >= toneSamples - ramp) {
          value *= (toneSamples - sample) / ramp;
        }
        samples[sample] = value;
      }
      final wav = encodeConformWav(
        samples: samples,
        channels: 1,
        sampleRate: sampleRate,
      );
      _deleteCueBeepDirectory(); // A stale one only happens if the file vanished.
      final directory = Directory.systemTemp.createTempSync('qa_cue_');
      _cueBeepDirectory = directory;
      final file = File('${directory.path}/cue-beep.wav');
      file.writeAsBytesSync(wav);
      audioConformStore.invalidate(file.path);
      audioConformStore.warmPaths([file.path]);
      _cueBeepPath = file.path;
      return file.path;
    } on Object {
      return null; // No beep is a degraded cue, never a failed take.
    }
  }

  /// Stopped-⏺ count-in beeps: the same standalone device path as the
  /// test tone — [seconds] beeps a second apart, then the device closes
  /// so the transport can take it for the roll.
  void _playCountInBeeps(int seconds) {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return;
    }
    final device = QaAudioDevice.instance;
    if (device == null || playback.isActive || device.isOpen) {
      return;
    }
    final index = audioOutputDeviceIndexByName(
      device,
      audioSyncSettings.value.outputDeviceName,
    );
    var opened = device.open(
      sampleRate: 48000,
      channels: 2,
      deviceIndex: index,
    );
    if (opened == 0 && index >= 0) {
      opened = device.open(sampleRate: 48000, channels: 2);
    }
    if (opened == 0) {
      return;
    }
    final sampleRate = device.sampleRate;
    final channels = device.channels;
    final toneSamples = sampleRate * 9 ~/ 100;
    final ramp = sampleRate ~/ 200;
    final pcm = Float32List(toneSamples * channels);
    for (var sample = 0; sample < toneSamples; sample += 1) {
      var value = 0.4 * math.sin(2 * math.pi * 1000 * sample / sampleRate);
      if (sample < ramp) {
        value *= sample / ramp;
      } else if (sample >= toneSamples - ramp) {
        value *= (toneSamples - sample) / ramp;
      }
      for (var channel = 0; channel < channels; channel += 1) {
        pcm[sample * channels + channel] = value;
      }
    }
    device.setSchedule(
      clips: [
        for (var beep = 0; beep < seconds; beep += 1)
          AudioMixClip(
            sourceIndex: 0,
            startSample: beep * sampleRate,
            endSample: beep * sampleRate + toneSamples,
          ),
      ],
      sources: [AudioMixSource(samples: pcm, channels: channels)],
    );
    device.play(
      startSample: 0,
      stopSample: (seconds - 1) * sampleRate + toneSamples,
    );
    _testToneTimer?.cancel();
    _testToneTimer = Timer(Duration(milliseconds: seconds * 1000), () {
      if (!playback.isActive && device.isOpen) {
        device.stop();
        device.close();
      }
    });
  }

  // --- Settings input meter + test tone (REC1-D2) --------------------------

  AudioInputMonitor? _inputMonitor;
  Timer? _testToneTimer;

  /// The settings dialog's live input meter: attach while the section is
  /// mounted, detach when it goes. The monitor yields to the recorder
  /// (capture is single-open) and resumes when the take finishes.
  AudioInputMonitor attachInputMeter() {
    final monitor = _inputMonitor ??= AudioInputMonitor(
      device: Platform.environment['FLUTTER_TEST'] == 'true'
          ? null
          : QaAudioDevice.instance,
    );
    _resumeInputMeter();
    return monitor;
  }

  void detachInputMeter() {
    _inputMonitor?.dispose();
    _inputMonitor = null;
  }

  /// The input device choice changed while the dialog is open: reopen on
  /// the new microphone.
  void restartInputMeter() {
    _inputMonitor?.stop();
    _resumeInputMeter();
  }

  void _resumeInputMeter() {
    final monitor = _inputMonitor;
    if (monitor == null || monitor.isRunning || isVoiceRecording.value) {
      return;
    }
    final device = Platform.environment['FLUTTER_TEST'] == 'true'
        ? null
        : QaAudioDevice.instance;
    monitor.start(
      sampleRate: audioConformStore.projectSampleRate,
      deviceIndex: device == null
          ? -1
          : audioInputDeviceIndexByName(
              device,
              audioSyncSettings.value.inputDeviceName,
            ),
    );
  }

  /// A short tone through the CHOSEN output device — the settings
  /// dialog's "is this speaker alive" button. Refuses while a transport
  /// run holds the device (it is busy making real sound). Returns false
  /// when nothing could open; the button stays quiet then.
  bool playOutputTestTone() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return false;
    }
    final device = QaAudioDevice.instance;
    if (device == null || playback.isActive || device.isOpen) {
      return false;
    }
    final index = audioOutputDeviceIndexByName(
      device,
      audioSyncSettings.value.outputDeviceName,
    );
    var opened = device.open(
      sampleRate: 48000,
      channels: 2,
      deviceIndex: index,
    );
    if (opened == 0 && index >= 0) {
      opened = device.open(sampleRate: 48000, channels: 2);
    }
    if (opened == 0) {
      return false;
    }
    final sampleRate = device.sampleRate;
    final channels = device.channels;
    final toneSamples = sampleRate ~/ 2;
    final pcm = Float32List(toneSamples * channels);
    for (var sample = 0; sample < toneSamples; sample += 1) {
      final value = 0.25 * math.sin(2 * math.pi * 440 * sample / sampleRate);
      for (var channel = 0; channel < channels; channel += 1) {
        pcm[sample * channels + channel] = value;
      }
    }
    device.setSchedule(
      clips: [
        AudioMixClip(
          sourceIndex: 0,
          startSample: 0,
          endSample: toneSamples,
          // 10 ms ramps: a bare sine edge lands as a click.
          fadeInSamples: sampleRate ~/ 100,
          fadeOutSamples: sampleRate ~/ 100,
        ),
      ],
      sources: [AudioMixSource(samples: pcm, channels: channels)],
    );
    device.play(startSample: 0, stopSample: toneSamples);
    _testToneTimer?.cancel();
    _testToneTimer = Timer(const Duration(milliseconds: 700), () {
      // The transport may have started meanwhile — never yank ITS device.
      if (!playback.isActive && device.isOpen) {
        device.stop();
        device.close();
      }
    });
    return true;
  }

  /// The SE lane whose playback yields to the microphone while a take
  /// rolls (the DAW armed-track rule); null when not recording.
  LayerId? get voiceRecordingMutedLaneId =>
      isVoiceRecording.value ? _voiceRecordLaneId : null;

  /// [voiceRecordingMutedLaneId] as the set the schedule builders take.
  Set<LayerId> get recordingMutedLayerIds {
    final lane = voiceRecordingMutedLaneId;
    return lane == null ? const <LayerId>{} : <LayerId>{lane};
  }

  // --- Live take preview (REC1-C) ------------------------------------------

  /// The sentinel clip path a rolling take's preview carries — never a
  /// real file; [audioPeaksForDisplay] resolves it to the live envelope.
  static const String voiceRecordPreviewPath = 'qa://recording-take';

  /// The armed lane WITH the in-flight take landed on it, recomputed
  /// through the same tape-style planner the stop uses — the timeline
  /// shows the real final state, not an overlay (user decision). Null
  /// outside recording. Changes at most once per FRAME (the boundary
  /// gate), and NEVER through a session notify: the timeline host
  /// subscribes directly (the R12-B playback-performance contract).
  final ValueNotifier<Layer?> voiceRecordPreviewLane = ValueNotifier<Layer?>(
    null,
  );

  /// The growing |peak| envelope of the take being recorded, folded from
  /// the recorder's chunk tap in the waveform store's own format.
  AudioPeaks? _voiceRecordLivePeaks;
  final List<double> _voiceRecordPeakBuckets = [];
  double _voiceRecordBucketMax = 0;
  int _voiceRecordBucketFill = 0;
  int _voiceRecordSamplesPerBucket = 0;
  int _voiceRecordLastPreviewLength = 0;

  /// What the waveform strips should paint for [path]: the live envelope
  /// for the preview sentinel, the conform store's peaks otherwise.
  AudioPeaks? audioPeaksForDisplay(String path) =>
      path == voiceRecordPreviewPath
      ? _voiceRecordLivePeaks
      : audioConformStore.peaksFor(path);

  /// Folds one captured chunk into the live envelope (the recorder's tap;
  /// split out so tests can feed made chunks).
  ///
  /// POST-chain (REC1-D): the channel fold picks what the take will
  /// keep, the gain scales it — the envelope and the clip light both
  /// show what lands in the file, which is the whole point of baking.
  @visibleForTesting
  void debugIngestVoiceRecordChunk(Float32List interleaved, int channels) {
    final perBucket = _voiceRecordSamplesPerBucket;
    if (channels <= 0 || perBucket <= 0) {
      return;
    }
    final factor = micGainFactor(_voiceRecordGainDb);
    final mode = channels >= 2
        ? _voiceRecordChannelMode
        : VoiceInputChannelMode.device;
    final frames = interleaved.length ~/ channels;
    for (var frame = 0; frame < frames; frame += 1) {
      final base = frame * channels;
      double magnitude;
      switch (mode) {
        case VoiceInputChannelMode.monoMix:
          var sum = 0.0;
          for (var channel = 0; channel < channels; channel += 1) {
            sum += interleaved[base + channel];
          }
          final mixed = sum / channels;
          magnitude = mixed < 0 ? -mixed : mixed;
        case VoiceInputChannelMode.left:
          final value = interleaved[base];
          magnitude = value < 0 ? -value : value;
        case VoiceInputChannelMode.right:
          final value = interleaved[base + 1];
          magnitude = value < 0 ? -value : value;
        case VoiceInputChannelMode.device:
          magnitude = 0;
          for (var channel = 0; channel < channels; channel += 1) {
            final value = interleaved[base + channel];
            final size = value < 0 ? -value : value;
            if (size > magnitude) {
              magnitude = size;
            }
          }
      }
      final scaled = magnitude * factor;
      if (scaled >= voiceClipThreshold && !voiceRecordClipLit.value) {
        voiceRecordClipLit.value = true;
      }
      final clamped = scaled > 1.0 ? 1.0 : scaled;
      if (clamped > _voiceRecordBucketMax) {
        _voiceRecordBucketMax = clamped;
      }
      _voiceRecordBucketFill += 1;
      if (_voiceRecordBucketFill == perBucket) {
        _voiceRecordPeakBuckets.add(_voiceRecordBucketMax);
        _voiceRecordBucketMax = 0;
        _voiceRecordBucketFill = 0;
      }
    }
  }

  /// Recomputes the preview when the roll crosses into a new frame —
  /// listener on the playback frame channel while recording. The planner
  /// runs on the lane's COMMIT form with the elapsed length; preview
  /// instance ids are minted fresh per pass (display-only material).
  void _syncVoiceRecordPreview() {
    if (!isVoiceRecording.value) {
      return;
    }
    final laneId = _voiceRecordLaneId;
    final lane = laneId == null ? null : trackSeGlobalLayerById(laneId);
    final global = _playbackTrackGlobalFrame();
    if (lane == null || global == null) {
      return;
    }
    // The playhead's frame is the one being spoken into: it counts.
    var end = global + 1;
    final punchEnd = _voiceRecordPunchEndFrame;
    if (punchEnd != null && end > punchEnd) {
      end = punchEnd;
    }
    final length = end - _voiceRecordAnchorFrame;
    if (length < 1) {
      if (voiceRecordPreviewLane.value != null) {
        voiceRecordPreviewLane.value = null;
      }
      return;
    }
    if (length == _voiceRecordLastPreviewLength &&
        voiceRecordPreviewLane.value != null) {
      return; // Same frame: the boundary gate holds the rebuild back.
    }
    _voiceRecordLastPreviewLength = length;
    _voiceRecordLivePeaks = AudioPeaks(
      bucketsPerSecond: 40,
      peaks: Float32List.fromList(_voiceRecordPeakBuckets),
    );
    var minted = 0;
    final plan = planSeTakePlacement(
      layer: lane,
      startFrame: _voiceRecordAnchorFrame,
      lengthFrames: length,
      filePath: voiceRecordPreviewPath,
      takeFrameId: const FrameId('rec-preview-take'),
      newFrameId: () => FrameId('rec-preview-${minted++}'),
    );
    voiceRecordPreviewLane.value = plan?.layer;
  }

  void _clearVoiceRecordPreview() {
    playback.globalFrameIndexListenable.removeListener(_syncVoiceRecordPreview);
    _voiceRecordLivePeaks = null;
    _voiceRecordPeakBuckets.clear();
    _voiceRecordBucketMax = 0;
    _voiceRecordBucketFill = 0;
    _voiceRecordSamplesPerBucket = 0;
    _voiceRecordLastPreviewLength = 0;
    voiceRecordClipLit.value = false;
    // The ADR cueing retires with the take (REC1-E): the stop's own
    // notify rebuilds the schedules without the beeps.
    _voiceRecordCountInTimer?.cancel();
    _voiceRecordCountInTimer = null;
    _voiceRecordCueClips = const [];
    _voiceRecordStreamerWindow = null;
    if (voiceRecordPreviewLane.value != null) {
      voiceRecordPreviewLane.value = null;
    }
  }

  /// Test hook: stand in for the microphone.
  @visibleForTesting
  AudioRecorder Function()? debugVoiceRecorderFactory;

  /// Test hook: stand in for the native RNNoise pass. Null result =
  /// "declined, keep the raw take" — the same contract as the C.
  @visibleForTesting
  Float32List? Function(Float32List samples, int channels, int sampleRate)?
  debugVoiceDenoiser;

  /// RNNoise runs at exactly this rate; capture asks for it when the
  /// suppression toggle is on, and the take conforms once on placement.
  static const int voiceDenoiseCaptureRate = 48000;

  static Float32List? _nativeVoiceDenoiser(
    Float32List samples,
    int channels,
    int sampleRate,
  ) => QaAudioNative.instance?.denoiseVoice(
    samples: samples,
    channels: channels,
    sampleRate: sampleRate,
  );

  /// The playing position on the TRACK-global axis, or null while
  /// playback is inactive. The all-cuts playlist IS the track axis
  /// (gaps included); the active-cut playlist is that cut alone, so its
  /// frames shift by the cut's global start.
  int? _playbackTrackGlobalFrame() {
    final global = playback.globalFrameIndexListenable.value;
    if (global == null) {
      return null;
    }
    return playback.scope == PlaybackScope.allCuts
        ? global
        : activeCutGlobalStartFrame + global;
  }

  /// Opens the microphone and ROLLS the transport (REC1-B): record =
  /// play + capture, the DAW rule — the playhead moves, every other row
  /// is audible, and the take lands where the roll started.
  ///
  /// The take lands on the ACTIVE track SE lane; any other active layer
  /// refuses (the armed-track contract — nothing records without an
  /// armed destination). A range selection on that lane is the PUNCH
  /// window: capture begins when playback enters it and ends at its far
  /// edge, however long the transport keeps rolling.
  VoiceRecordStartResult startVoiceRecording() {
    if (isVoiceRecording.value) {
      return VoiceRecordStartResult.alreadyRecording;
    }
    final laneId = activeLayerId;
    final lane = laneId == null ? null : trackSeGlobalLayerById(laneId);
    if (lane == null || laneId == null) {
      return VoiceRecordStartResult.needsSeLane;
    }
    // The settings meter yields the microphone to the take (REC1-D2).
    _inputMonitor?.stop();
    final device = Platform.environment['FLUTTER_TEST'] == 'true'
        ? null
        : QaAudioDevice.instance;
    final recorder =
        debugVoiceRecorderFactory?.call() ?? AudioRecorder(device: device);
    final deviceIndex = device == null
        ? -1
        : audioInputDeviceIndexByName(
            device,
            audioSyncSettings.value.inputDeviceName,
          );
    // Suppression captures at RNNoise's native 48 kHz; the take conforms
    // ONCE on placement, like any imported rate.
    final wantDenoise = audioSyncSettings.value.denoiseVoice;
    final rate = recorder.start(
      sampleRate: wantDenoise
          ? voiceDenoiseCaptureRate
          : audioConformStore.projectSampleRate,
      deviceIndex: deviceIndex,
    );
    if (rate == 0) {
      return VoiceRecordStartResult.deviceFailed;
    }

    // Where the roll starts, on the track-global axis: the playing (or
    // paused) position when the transport is active, otherwise the
    // editing playhead — gap parking included (a gap is a place on the
    // track; the lane is cut-independent).
    final rollStart = playback.isActive
        ? (_playbackTrackGlobalFrame() ??
              (gapParkedGlobalFrame ?? editingGlobalFrame))
        : (gapParkedGlobalFrame ?? editingGlobalFrame);

    // The punch window: a range selection on the armed lane, mapped from
    // its cut-local display axis onto the track axis.
    var anchor = rollStart;
    int? punchEnd;
    final selection = frameRangeSelection.value;
    if (selection != null && selection.coversLayer(laneId)) {
      final offset = activeCutGlobalStartFrame;
      final punchStart = selection.startIndex + offset;
      final windowEnd = selection.endIndexExclusive + offset;
      if (rollStart < windowEnd) {
        anchor = math.max(rollStart, punchStart);
        punchEnd = windowEnd;
      }
    }

    _voiceRecorder = recorder;
    _voiceRecordLaneId = laneId;
    _voiceRecordAnchorFrame = anchor;
    _voiceRecordPunchEndFrame = punchEnd;
    // The performer speaks against what they HEAR, which runs the output
    // latency behind the mix clock — that much comes off the take's head
    // (the DAW recording-compensation rule) — plus the run-up between
    // the roll start and the punch-in.
    _voiceRecordHeadTrimSamples =
        audioDeviceTransport.report.reportedLatencySamples +
        projectFrameRate.frameToSample(anchor - rollStart, rate);
    isVoiceRecording.value = true;
    // Capture-chain snapshot (REC1-D): gain and channel fold ride the
    // whole take; the clip light re-arms per take.
    _voiceRecordGainDb = AudioSyncSettings.clampMicGainDb(
      audioSyncSettings.value.micGainDb,
    );
    _voiceRecordChannelMode = audioSyncSettings.value.inputChannelMode;
    // A device that refused 48 kHz records clean — RNNoise has no other
    // rate, and a silently resampled pass would be a different promise.
    _voiceRecordDenoise = wantDenoise && rate == voiceDenoiseCaptureRate;
    _lastVoiceTakeClipped = false;
    voiceRecordClipLit.value = false;
    // Live preview (REC1-C): the recorder's chunk tap feeds the growing
    // waveform; the playback frame channel drives the block preview at
    // frame boundaries — no session notify per tick (R12-B).
    _voiceRecordSamplesPerBucket = rate ~/ 40;
    recorder.onChunk = debugIngestVoiceRecordChunk;
    playback.globalFrameIndexListenable.addListener(_syncVoiceRecordPreview);
    final wasRolling = playback.isActive && playback.isPlaying;
    // Stopped-⏺ count-in (REC1-E): the mic is ALREADY rolling, the
    // transport waits — the wait rides the head trim, so the take still
    // anchors where the roll will start. A punch has its own run-up; the
    // count-in stays out of its way.
    final countInSeconds = !wasRolling && punchEnd == null
        ? AudioSyncSettings.clampCountInSeconds(
            audioSyncSettings.value.countInSeconds,
          )
        : 0;
    if (wasRolling) {
      _voiceRecordStartedRoll = false;
    } else if (countInSeconds > 0) {
      _voiceRecordStartedRoll = true;
      _voiceRecordHeadTrimSamples += countInSeconds * rate;
      if (audioSyncSettings.value.cueBeeps) {
        _playCountInBeeps(countInSeconds);
      }
      _voiceRecordCountInTimer?.cancel();
      _voiceRecordCountInTimer = Timer(Duration(seconds: countInSeconds), () {
        if (!isVoiceRecording.value) {
          return;
        }
        if (playback.isActive) {
          playback.resume();
        } else {
          playback.play(
            scope: PlaybackScope.allCuts,
            startGlobalFrame: rollStart,
          );
        }
      });
    } else {
      _voiceRecordStartedRoll = true;
      if (playback.isActive) {
        playback.resume();
      } else {
        playback.play(
          scope: PlaybackScope.allCuts,
          startGlobalFrame: rollStart,
        );
      }
    }
    // ADR cue clips + the streamer window (REC1-E): only with a punch
    // AHEAD of the roll — the approach is what they count down.
    _voiceRecordCueClips = const [];
    _voiceRecordStreamerWindow = null;
    if (punchEnd != null && anchor > rollStart) {
      final axisShift =
          playback.isActive && playback.scope == PlaybackScope.activeCut
          ? activeCutGlobalStartFrame
          : 0;
      final secondFrames = projectFrameRate.framesCoveringExactSeconds(1, 1);
      if (secondFrames > 0) {
        final settingsNow = audioSyncSettings.value;
        if (settingsNow.cueBeeps) {
          final beepPath = _ensureCueBeepWav();
          if (beepPath != null) {
            final beepFrames = math.max(
              1,
              projectFrameRate.framesCoveringExactSeconds(9, 100),
            );
            _voiceRecordCueClips = [
              for (var beep = 3; beep >= 1; beep -= 1)
                if (anchor - beep * secondFrames >= rollStart)
                  ScheduledAudioClip(
                    filePath: beepPath,
                    startFrame: anchor - beep * secondFrames - axisShift,
                    endFrameExclusive:
                        anchor - beep * secondFrames - axisShift + beepFrames,
                    gain: 0.8,
                  ),
            ];
          }
        }
        if (settingsNow.streamerEnabled) {
          final approach = math.min(3 * secondFrames, anchor - rollStart);
          if (approach >= 1) {
            _voiceRecordStreamerWindow = (
              startFrame: anchor - approach - axisShift,
              punchFrame: anchor - axisShift,
            );
          }
        }
      }
    }
    _syncVoiceRecordPreview();
    notifyListeners(); // Armed-lane mute + cue clips join the schedules.
    return VoiceRecordStartResult.started;
  }

  /// Stops the take and lands it on the armed lane: WAV to disk, pool
  /// entry, and the lane's tape-style swap (trims, erasures, the new
  /// block and its link) — ONE undo for the whole landing.
  ///
  /// A roll this take started stops with it (record = play + capture,
  /// both directions). Returns null on clean success, otherwise a
  /// message for the user — including the case where the take was PLACED
  /// but the capture ring dropped frames (a damaged take must say so).
  String? stopVoiceRecordingAndPlace() {
    final recorder = _voiceRecorder;
    _voiceRecorder = null;
    final laneId = _voiceRecordLaneId;
    _voiceRecordLaneId = null;
    final startedRoll = _voiceRecordStartedRoll;
    _voiceRecordStartedRoll = false;
    isVoiceRecording.value = false;
    // The preview retires FIRST (listener off, sentinel peaks gone) —
    // every return path below shows committed rows again; a successful
    // placement swaps the real take in within the same stop.
    _clearVoiceRecordPreview();
    final recording = recorder?.stop();
    // The recorder released the microphone: the settings meter (if the
    // dialog is still open) takes it back.
    _resumeInputMeter();
    if (startedRoll && playback.isActive) {
      // Re-enters _onPlaybackStopped; the recorder is already detached.
      playback.stop();
    }
    notifyListeners(); // The armed lane unmutes.
    if (recording == null) {
      return uiStrings.recordNothingRecording;
    }
    if (recording.length == 0) {
      return uiStrings.recordTakeEmpty;
    }
    final placed = placeVoiceRecording(
      recording,
      laneId: laneId,
      anchorFrame: _voiceRecordAnchorFrame,
      punchEndFrame: _voiceRecordPunchEndFrame,
      headTrimSamples: _voiceRecordHeadTrimSamples,
      gainDb: _voiceRecordGainDb,
      channelMode: _voiceRecordChannelMode,
      denoise: _voiceRecordDenoise,
    );
    if (!placed) {
      return uiStrings.recordPlacementFailed;
    }
    if (recording.droppedFrames > 0) {
      return uiStrings.recordDroppedFramesTemplate.replaceAll(
        '{count}',
        '${recording.droppedFrames}',
      );
    }
    if (_lastVoiceTakeClipped && audioSyncSettings.value.clippingNotice) {
      return uiStrings.recordTakeClipped;
    }
    return null;
  }

  /// Lands a finished take (split out so tests can drive it with a made
  /// recording): trims the head (latency + punch run-up), clamps to the
  /// punch window, writes the WAV, and swaps the lane through the
  /// tape-style planner — pool entry and lane swap in ONE undo step.
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
  }) {
    final lane = laneId == null ? null : trackSeGlobalLayerById(laneId);
    if (lane == null ||
        anchorFrame < 0 ||
        recording.channels <= 0 ||
        recording.sampleRate <= 0) {
      return false;
    }
    var samples = recording.samples;
    if (headTrimSamples > 0) {
      final trimFloats = headTrimSamples * recording.channels;
      if (trimFloats >= samples.length) {
        return false; // Shorter than the run-up it rode on: nothing real.
      }
      samples = Float32List.sublistView(samples, trimFloats);
    }
    // Suppression first, on the trimmed raw capture (per channel, the
    // OBS filter order) — the RNNoise round. A declined pass (no native
    // engine, wrong rate) keeps the raw take: recording never fails
    // because a denoiser is missing.
    if (denoise) {
      final suppressed = (debugVoiceDenoiser ?? _nativeVoiceDenoiser)(
        samples,
        recording.channels,
        recording.sampleRate,
      );
      if (suppressed != null) {
        samples = suppressed;
      }
    }
    // The capture chain (REC1-D): channel fold + baked gain, applied to
    // the trimmed take — the file holds exactly what the meter showed.
    final processed = processVoiceTake(
      samples: samples,
      channels: recording.channels,
      gainDb: gainDb,
      channelMode: channelMode,
    );
    samples = processed.samples;
    final channels = processed.channels;
    _lastVoiceTakeClipped = processed.clipped;
    // Whole frames covering the take, so the block window matches what
    // was actually said (min 1 — a sub-frame take still needs a cell).
    var lengthFrames = math.max(
      1,
      projectFrameRate.framesCoveringExactSeconds(
        samples.length ~/ channels,
        recording.sampleRate,
      ),
    );
    final window = punchEndFrame == null ? null : punchEndFrame - anchorFrame;
    if (window != null) {
      if (window < 1) {
        return false;
      }
      if (lengthFrames > window) {
        lengthFrames = window;
        // The file carries the window alone — capture past the punch-out
        // is context the performer heard, not part of the take.
        final windowFloats =
            projectFrameRate.frameToSample(window, recording.sampleRate) *
            channels;
        if (windowFloats > 0 && windowFloats < samples.length) {
          samples = Float32List.sublistView(samples, 0, windowFloats);
        }
      }
    }
    final wav = encodeConformWav(
      samples: samples,
      channels: channels,
      sampleRate: recording.sampleRate,
    );
    final path = _writeRecordingWav(wav, laneName: lane.name);
    if (path == null) {
      return false;
    }

    final plan = planSeTakePlacement(
      layer: lane,
      startFrame: anchorFrame,
      lengthFrames: lengthFrames,
      filePath: path,
      takeFrameId: _mintFrameId(lane.id),
      newFrameId: () => _mintFrameId(lane.id),
      takeClipped: processed.clipped,
    );
    if (plan == null) {
      return false;
    }
    // Conform first (same order as an import), then the ONE undo step:
    // pool entry + the lane's whole swap.
    audioConformStore.invalidate(path);
    audioConformStore.warmPaths([path]);
    final pool = mediaAssets;
    _cutCommandCoordinator.historyManager.execute(
      CompositeCommand(
        description: 'Record voice',
        commands: [
          if (!pool.any((asset) => asset.path == path))
            UpdateMediaAssetsCommand(
              repository: _repository,
              mediaAssets: [
                ...pool,
                MediaAsset(path: path, name: mediaAssetDefaultName(path)),
              ],
              description: 'Record voice',
            ),
          UpdateLayerTimelineCommand(
            repository: _repository,
            before: lane,
            after: plan.layer,
          ),
        ],
      ),
    );
    notifyListeners();
    return true;
  }

  FrameId _mintFrameId(LayerId layerId) {
    _frameSequence += 1;
    return FrameId(_nextFrameId(layerId));
  }

  /// Writes a take's WAV under the project's `Media/` folder (the visible
  /// Recordings shelf when the project was never saved — REC1-B2, no
  /// hidden OS temp) and returns its path, or null when even that failed.
  ///
  /// Named `<lane>_T<n>.wav` (REC1-B): the recording-session convention —
  /// the pool line alone says whose take it is and which pass. On the
  /// shelf the walk continues past earlier sessions' takes.
  String? _writeRecordingWav(Uint8List bytes, {required String laneName}) {
    final base = laneName.replaceAll(RegExp(r'[\\/:*?"<>|.\s]+'), '_');
    final safeBase = base.isEmpty ? 'REC' : base;
    try {
      final projectPath = _projectFilePath;
      final onShelf = projectPath == null;
      final directory = onShelf
          ? (_voiceRecordShelfDirectory ??= appRecordingsDirectory())
          : ProjectAssetLayout(projectPath).mediaDirectory;
      Directory(directory).createSync(recursive: true);
      for (var take = 1; take < 10000; take += 1) {
        final file = File(
          '$directory/${safeBase}_T${take.toString().padLeft(2, '0')}.wav',
        );
        if (!file.existsSync()) {
          file.writeAsBytesSync(bytes);
          if (onShelf) {
            _voiceRecordShelfPaths.add(file.path);
          }
          return file.path;
        }
      }
      return null;
    } on Object {
      return null; // Full disk, permissions: the take reports, not crashes.
    }
  }

  /// REC1-B2: the FIRST save adopts this session's shelf takes — every
  /// still-referenced WAV recorded before the project had a home MOVES
  /// into the new project's `Media/`, and the pool entry plus every clip
  /// follow via the relink transform, applied OUTSIDE undo history
  /// (saving is not an edit). Undone takes stay on the shelf. Returns
  /// the new paths so the caller can refresh conforms once the project
  /// path is set.
  List<String> _adoptShelfTakesForSave(String projectFilePath) {
    if (_projectFilePath != null || _voiceRecordShelfPaths.isEmpty) {
      return const [];
    }
    final mediaDirectory = ProjectAssetLayout(projectFilePath).mediaDirectory;
    final referenced = {for (final asset in mediaAssets) asset.path};
    final adopted = <String>[];
    for (final oldPath in _voiceRecordShelfPaths) {
      if (!referenced.contains(oldPath)) {
        continue;
      }
      final newPath = _moveTakeIntoDirectory(oldPath, mediaDirectory);
      if (newPath == null) {
        continue; // The reference still plays from the shelf.
      }
      RelinkMediaAssetCommand(
        repository: _repository,
        oldPath: oldPath,
        newPath: newPath,
      ).execute();
      audioConformStore.invalidate(oldPath);
      adopted.add(newPath);
    }
    _voiceRecordShelfPaths.clear();
    _voiceRecordShelfDirectory = null;
    return adopted;
  }

  /// Moves a shelf take into [directory] under a collision-walked name.
  /// A custom shelf may sit on another volume, where rename fails —
  /// copy-then-retire covers that.
  String? _moveTakeIntoDirectory(String sourcePath, String directory) {
    try {
      final source = File(sourcePath);
      if (!source.existsSync()) {
        return null;
      }
      Directory(directory).createSync(recursive: true);
      final normalized = sourcePath.replaceAll('\\', '/');
      final name = normalized.substring(normalized.lastIndexOf('/') + 1);
      final dot = name.lastIndexOf('.');
      final stem = dot <= 0 ? name : name.substring(0, dot);
      final extension = dot <= 0 ? '' : name.substring(dot);
      for (var index = 0; index < 10000; index += 1) {
        final candidate = index == 0
            ? '$directory/$name'
            : '$directory/$stem-$index$extension';
        if (File(candidate).existsSync()) {
          continue;
        }
        try {
          source.renameSync(candidate);
        } on FileSystemException {
          source.copySync(candidate);
          source.deleteSync();
        }
        return candidate;
      }
      return null;
    } on Object {
      return null; // The save must not die on a shelf move.
    }
  }

  String _copyIntoProjectMedia(String sourcePath) {
    final projectPath = _projectFilePath;
    if (projectPath == null) {
      return sourcePath;
    }
    final mediaDirectory = ProjectAssetLayout(projectPath).mediaDirectory;
    final normalized = sourcePath.replaceAll('\\', '/');
    if (normalized.startsWith('$mediaDirectory/')) {
      // Already ours — a pool path re-imported from the browser.
      return sourcePath;
    }
    final name = normalized.substring(normalized.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final extension = dot <= 0 ? '' : name.substring(dot);
    try {
      final source = File(sourcePath);
      if (!source.existsSync()) {
        return sourcePath;
      }
      Directory(mediaDirectory).createSync(recursive: true);
      // Same name taken: REUSE it when the bytes match (re-importing the
      // same sound must not stack x-1, x-2 copies), otherwise walk to a
      // unique name (two different sounds sharing a name must never
      // overwrite each other — Pro Tools' import rule).
      for (var index = 0; index < 10000; index += 1) {
        final candidate = File(
          index == 0
              ? '$mediaDirectory/$name'
              : '$mediaDirectory/$stem-$index$extension',
        );
        if (!candidate.existsSync()) {
          source.copySync(candidate.path);
          return candidate.path;
        }
        if (_sameFileBytes(source, candidate)) {
          return candidate.path;
        }
      }
      return sourcePath;
    } on Object {
      // Cloud folder mid-sync, permissions, full disk: the reference
      // still plays and the pool can be relinked later.
      return sourcePath;
    }
  }

  static bool _sameFileBytes(File a, File b) {
    if (a.lengthSync() != b.lengthSync()) {
      return false;
    }
    // Full compare, but only ever reached on a NAME collision — rare, and
    // a wrong "same" here would silently play one sound for another.
    final bytesA = a.readAsBytesSync();
    final bytesB = b.readAsBytesSync();
    for (var index = 0; index < bytesA.length; index += 1) {
      if (bytesA[index] != bytesB[index]) {
        return false;
      }
    }
    return true;
  }

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

  List<AudioClip>? _audioOffsetDragBefore;
  LayerId? _audioOffsetDragLayerId;
  int? _audioOffsetDragClipIndex;

  /// Starts a live slide of [layerId]'s [clipIndex]th sound: the drag
  /// previews repo-direct (every waveform view repaints from the model in
  /// real time) and [endAudioClipOffsetDrag] commits ONE undo step.
  bool beginAudioClipOffsetDrag({
    required LayerId layerId,
    required int clipIndex,
  }) {
    final layer = _layerById(layerId);
    if (layer == null ||
        layer.kind != LayerKind.se ||
        clipIndex < 0 ||
        clipIndex >= layer.audioClips.length) {
      return false;
    }
    _audioOffsetDragBefore = layer.audioClips;
    _audioOffsetDragLayerId = layerId;
    _audioOffsetDragClipIndex = clipIndex;
    return true;
  }

  /// Applies the dragged ABSOLUTE offset as a live preview (clamped ≥ 0);
  /// no-op while no drag is in flight or the value is unchanged.
  void updateAudioClipOffsetDrag(int offsetFrames) {
    final layerId = _audioOffsetDragLayerId;
    final clipIndex = _audioOffsetDragClipIndex;
    if (layerId == null || clipIndex == null) {
      return;
    }
    final layer = _layerById(layerId);
    if (layer == null || clipIndex >= layer.audioClips.length) {
      return;
    }
    final clamped = offsetFrames < 0 ? 0 : offsetFrames;
    if (layer.audioClips[clipIndex].offsetFrames == clamped) {
      return;
    }
    final next = [...layer.audioClips];
    next[clipIndex] = next[clipIndex].copyWith(offsetFrames: clamped);
    _repository.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: next,
    );
    notifyListeners();
  }

  /// Commits the slide as a single undo step: the preview reverts
  /// silently, then the normal clip command applies the final list (its
  /// before-snapshot stays correct).
  void endAudioClipOffsetDrag() {
    final before = _audioOffsetDragBefore;
    final layerId = _audioOffsetDragLayerId;
    _audioOffsetDragBefore = null;
    _audioOffsetDragLayerId = null;
    _audioOffsetDragClipIndex = null;
    if (before == null || layerId == null) {
      return;
    }
    final layer = _layerById(layerId);
    if (layer == null) {
      return;
    }
    final after = layer.audioClips;
    if (listEquals(after, before)) {
      return;
    }
    _repository.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: before,
    );
    _cutCommandCoordinator.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: after,
      description: 'Slide sound',
    );
    notifyListeners();
  }

  /// Reverts an in-flight slide preview without touching history.
  void cancelAudioClipOffsetDrag() {
    final before = _audioOffsetDragBefore;
    final layerId = _audioOffsetDragLayerId;
    _audioOffsetDragBefore = null;
    _audioOffsetDragLayerId = null;
    _audioOffsetDragClipIndex = null;
    if (before == null || layerId == null) {
      return;
    }
    final layer = _layerById(layerId);
    if (layer == null || listEquals(layer.audioClips, before)) {
      return;
    }
    _repository.updateLayerAudioClips(
      cutId: requireActiveCut.id,
      layerId: layerId,
      audioClips: before,
    );
    notifyListeners();
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
  void addMediaAssets(List<String> paths) {
    final pool = mediaAssets;
    final known = {for (final asset in pool) asset.path};
    final added = [
      for (final path in paths)
        if (known.add(path))
          MediaAsset(path: path, name: mediaAssetDefaultName(path)),
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
    notifyListeners();
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

  /// SE toggle: animation ⇄ se. Any number of SE rows per cut (a sheet can
  /// carry several SE columns), but converting one away must not break the
  /// S1·S2 floor of two.
  String get activeLayerKindLabelText {
    final targetLayer = _targetLayerForKindToggle;
    return switch (targetLayer?.kind) {
      LayerKind.animation => 'Animation Layer',
      LayerKind.storyboard => 'Storyboard Layer',
      LayerKind.image => 'Image Layer',
      LayerKind.text => 'Text Layer',
      LayerKind.se => 'SE Layer',
      LayerKind.instruction => 'Instruction Layer',
      LayerKind.camera => 'Camera Layer',
      LayerKind.folder => 'Folder',
      LayerKind.adjustment => 'Adjustment Layer',
      null => 'No Layer',
    };
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

  /// The timesheet "X here" action: cuts the covering block's hold so the
  /// current cell (and the rest of the old hold) becomes empty.
  bool get canCutExposureAtCurrentFrame {
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
    final lane = laneRangeSelection.value;
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

  /// The selection range's maximal EMPTY runs on [layer]'s timeline
  /// (ghost coverage counts as covered — derived cells are not authoring
  /// room).
  List<({int startIndex, int length})> _emptyGapsInRange(
    Layer layer,
    TimelineFrameRangeSelection selection,
  ) {
    final gaps = <({int startIndex, int length})>[];
    int? gapStart;
    for (
      var index = selection.startIndex;
      index <= selection.endIndexExclusive;
      index += 1
    ) {
      final covered =
          index >= selection.endIndexExclusive ||
          index < 0 ||
          coveringDrawingBlockAt(layer.timeline, index) != null;
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
  /// value on every unkeyed frame of the range — one undo.
  void _createLaneKeysForSelection(TimelineLaneSelection lane) {
    final layer = _layerById(lane.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return;
    }
    // R6: an EFFECT-lane selection freezes keys on the effect chain
    // instead — same rule, same single undo.
    if (lane.spanLaneIds.any((laneId) => parseEffectLaneId(laneId) != null)) {
      var effects = layer.effects;
      var effectsChanged = false;
      for (final laneId in lane.spanLaneIds) {
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
        updateLayerEffects(layer.id, effects, description: 'Create keys');
      }
      return;
    }
    var track = layer.transformTrack;
    var changed = false;
    // R26 #3: a multi-lane span freezes keys on EVERY spanned lane —
    // still one undo.
    for (final laneId in lane.spanLaneIds) {
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
          resolvedPose: layerPoseAtFrame(layer, frame),
          resolvedAnchorPoint: layerAnchorPointAtFrame(layer, frame),
          resolvedOpacity: layerOpacityAtFrame(layer, frame),
        );
        if (next != null) {
          track = next;
          changed = true;
        }
      }
    }
    if (changed) {
      updateLayerTransformTrack(layer.id, track, description: 'Create keys');
    }
  }

  void copyFrameAtCurrentFrame() {
    final layer = activeLayer;
    final frame = selectedFrame;
    if (layer == null || frame == null || !canCopyFrameAtCurrentFrame) {
      return;
    }

    _copiedFrame = _CopiedFrameReference(
      layerId: layer.id,
      frameId: frame.id,
      frameName: frame.name,
    );
    notifyListeners();
  }

  void pasteLinkedFrameAtCurrentFrame() {
    final layer = activeLayer;
    final copiedFrame = _copiedFrame;
    if (layer == null ||
        copiedFrame == null ||
        !canPasteLinkedFrameAtCurrentFrame) {
      return;
    }

    _timelineController.pasteLinkedFrameForLayer(
      layerId: layer.id,
      frameId: copiedFrame.frameId,
    );
    notifyListeners();
  }

  void cutExposureAtCurrentFrame() {
    final layer = activeLayer;
    if (layer == null || !canCutExposureAtCurrentFrame) {
      return;
    }

    _timelineController.cutExposureForLayer(layerId: layer.id);
    notifyListeners();
  }

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

  bool get isExposureEdgeDragActive => _edgeDragBefore != null;

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
    int afterRowEnd,
  ) {
    final sync = _edgeDragCutSync;
    if (sync == null) {
      return null;
    }
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
    final syncedCut = activeCutOrNull?.id == sync.cutId
        ? activeCutOrNull
        : null;
    final floor = syncedCut == null ? 1 : minimumCutDurationFor(syncedCut);
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
    _edgeDragBefore = row;
    _edgeDragEdge = TimelineBlockEdge.end;
    _edgeDragBlockStart = blockKey;
    _edgeDragAfter = null;
    _edgeDragWindow = null;
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    _edgeDragBulkEdits = null;
    _edgeDragAfterDurations = null;
    _edgeDragAfterGaps = null;
    _edgeDragCutSync = _cutSyncSnapshotFor(cut: cut, row: row);
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
            resize = _cutSyncResizeFor(_storedRowEndOf(edit.after));
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
    final resize = after == before
        ? null
        : _cutSyncResizeFor(_storedRowEndOf(after));
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

  /// Which verb the in-flight cut-edge drag belongs to. One shape of edge,
  /// and where it sits decides what it re-times — the answer is taken at
  /// BEGIN and kept HERE, in the session the continuations already reach,
  /// so a host rebuild mid-drag cannot re-route the release onto a verb
  /// whose fields were never set (the failure that sank the first #5
  /// attempt).
  _CutEdgeDragVerb? _cutEdgeDragVerb;

  /// Starts a cut edge drag on [cutId]'s [edge], choosing the verb by what
  /// the edge sits on (feedback #5/#9: when the cut has a storyboard row,
  /// its edges are the ROW's edges):
  ///
  /// - a storyboard row's leading edge re-times the cut's LEAD — the first
  ///   cell's comma changes, the later cells and the following cuts come
  ///   along, and the cut start stays put (NOT a start trim);
  /// - its trailing edge is the LAST cell's comma, and the cut's length
  ///   follows it (the always-synced pair);
  /// - a cut with no row keeps the plain trims: the END edge trims the
  ///   duration (growth eats the following gap first); the START edge
  ///   TRIMS from the front (R12-B, timeline start-comma parity).
  ///
  /// The continuations ([updateCutEdgeDrag], [endCutEdgeDrag],
  /// [cancelCutEdgeDrag]) follow whichever verb began — they carry a delta
  /// and nothing else.
  bool beginCutEdgeDrag({
    required CutId cutId,
    required TimelineBlockEdge edge,
  }) {
    final cut = cutById(cutId);
    final row = cut == null ? null : storyboardLayerForCut(cut);
    if (cut != null && row != null) {
      if (edge == TimelineBlockEdge.start &&
          _beginStoryboardLeadDrag(cut, row)) {
        _cutEdgeDragVerb = _CutEdgeDragVerb.leadRetime;
        return true;
      }
      if (edge == TimelineBlockEdge.end &&
          _beginStoryboardLastCommaDrag(cut, row)) {
        _cutEdgeDragVerb = _CutEdgeDragVerb.comma;
        return true;
      }
    }
    if (_beginCutTrimDrag(cutId: cutId, edge: edge)) {
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
      case _CutEdgeDragVerb.leadRetime:
        _updateStoryboardLeadDrag(cumulativeDelta);
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
      case _CutEdgeDragVerb.leadRetime:
        _endStoryboardLeadDrag();
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
      case _CutEdgeDragVerb.leadRetime:
        _cancelStoryboardLeadDrag();
      case _CutEdgeDragVerb.comma:
        cancelExposureEdgeDrag();
    }
  }

  bool _beginCutTrimDrag({
    required CutId cutId,
    required TimelineBlockEdge edge,
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
    // The release commits from these, so a new drag must not inherit the
    // previous one's result: a press that never moves would otherwise land
    // an edit the pointer never asked for.
    _cutTrimAfterDurations = null;
    _cutTrimAfterGaps = null;
    return true;
  }

  /// Applies the drag's cumulative frame delta as a live preview on
  /// [dragPreview] (the repository is NOT touched).
  ///
  /// END edge: the duration changes; growth consumes the FOLLOWING cut's
  /// leading gap first (that cut holds still until the gap is spent, then
  /// ripples). Shrinking follows the timeline's block language (R10-⑦):
  /// only an ATTACHED next cut rides the boundary — a detached one holds
  /// its global position (its gap grows by the shrink). START edge: a
  /// TRIM (R12-B, timeline start-comma parity) — the END stays put and
  /// the LENGTH changes; leftward growth consumes its own gap then pushes
  /// the predecessors (cascade, frame-0 clamp), rightward shrink opens
  /// its gap (length clamps at 1).
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
    // are panels OF this cut, so the end cannot be dragged past the last
    // division on it (delete the cells to shrink further). Cuts without a
    // storyboard row keep the plain one-frame floor.
    final trimmedCut = cutById(cutId);
    final minDuration = trimmedCut == null
        ? 1
        : minimumCutDurationFor(trimmedCut);
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
      // START edge = a TRIM (R12-B, timeline start-comma parity): the
      // cut's END stays put and its LENGTH changes. Rightward movement
      // shrinks the cut (its own gap grows; length clamps at 1 frame);
      // leftward movement grows it — its own gap absorbs first, then the
      // predecessors get pushed left through theirs (cascade, frame-0
      // clamp). Followers never move: the start's movement and the length
      // change cancel exactly at the end boundary.
      final beforeDuration = beforeDurations[cutId]!;
      if (cumulativeDelta >= 0) {
        final moved = math.min(cumulativeDelta, beforeDuration - minDuration);
        durations[cutId] = beforeDuration - moved;
        gaps[cutId] = beforeGaps[cutId]! + moved;
      } else {
        final order = _cutTrimOrder!;
        var remaining = -cumulativeDelta;
        for (var i = _cutTrimIndex!; i >= 0 && remaining > 0; i -= 1) {
          final id = order[i];
          final take = math.min(remaining, beforeGaps[id]!);
          if (take > 0) {
            gaps[id] = beforeGaps[id]! - take;
            remaining -= take;
          }
        }
        final moved = (-cumulativeDelta) - remaining;
        durations[cutId] = beforeDuration + moved;
      }
    }

    final changed =
        durations[cutId] != beforeDurations[cutId] ||
        gaps.entries.any((entry) => beforeGaps[entry.key] != entry.value);
    // The release commits from THESE, never from the preview channel: a
    // consumer clearing [dragPreview] mid-drag must not be able to void
    // the commit.
    _cutTrimAfterDurations = changed ? durations : null;
    _cutTrimAfterGaps = changed ? gaps : null;
    dragPreview.value = changed
        ? CutTrimDragPreview(previewDurations: durations, previewGaps: gaps)
        : null;
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
    _cancelCutTrimDrag();
    if (beforeDurations == null ||
        beforeGaps == null ||
        afterDurations == null ||
        afterGaps == null) {
      return;
    }

    _cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: {
        for (final id in afterDurations.keys) id: beforeDurations[id]!,
      },
      afterDurations: afterDurations,
      beforeGaps: {for (final id in afterGaps.keys) id: beforeGaps[id]!},
      afterGaps: afterGaps,
    );
    _refreshAfterCutCommand();
    notifyListeners();
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
    dragPreview.value = null;
  }

  // --- Storyboard lead re-time drags (feedback #5) --------------------------
  //
  // The first panel's leading edge. NOT a cut start trim: the cut's start
  // stays put, the FIRST cell's comma changes, every later division comes
  // along keeping its own comma, and the cut's duration follows — which is
  // what keeps the last cell ending at the cut's end and the following
  // cuts attached. Equivalent to an END trim of -d plus a -d shift of
  // every division key, committed as ONE undo step.

  Layer? _leadDragBefore;
  CutId? _leadDragCutId;
  int? _leadDragBeforeDuration;
  CutId? _leadDragNextCutId;
  int? _leadDragNextBeforeGap;
  Layer? _leadDragAfter;
  Map<CutId, int>? _leadDragAfterDurations;
  Map<CutId, int>? _leadDragAfterGaps;

  bool _beginStoryboardLeadDrag(Cut cut, Layer row) {
    if (storyboardLeadRetimeMaxShrink(
          timeline: row.timeline,
          cutDuration: cut.duration,
        ) ==
        null) {
      return false;
    }
    final next = _nextCutInTrack(cut.id);
    _leadDragBefore = row;
    _leadDragCutId = cut.id;
    _leadDragBeforeDuration = cut.duration;
    _leadDragNextCutId = next?.id;
    _leadDragNextBeforeGap = next?.leadingGapFrames;
    _leadDragAfter = null;
    _leadDragAfterDurations = null;
    _leadDragAfterGaps = null;
    return true;
  }

  void _updateStoryboardLeadDrag(int cumulativeDelta) {
    final before = _leadDragBefore;
    final cutId = _leadDragCutId;
    final beforeDuration = _leadDragBeforeDuration;
    if (before == null || cutId == null || beforeDuration == null) {
      return;
    }
    final moved = storyboardTimelineWithLeadRetimed(
      timeline: before.timeline,
      cutDuration: beforeDuration,
      delta: cumulativeDelta,
    );
    if (moved == null) {
      _leadDragAfter = null;
      _leadDragAfterDurations = null;
      _leadDragAfterGaps = null;
      dragPreview.value = null;
      return;
    }
    final after = before.copyWith(timeline: moved);
    // The duration rides the row: the last cell's END must stay the cut's
    // end, so the cut shrinks (or grows) by exactly what the lead did.
    final maxShrink = storyboardLeadRetimeMaxShrink(
      timeline: before.timeline,
      cutDuration: beforeDuration,
    )!;
    final applied = cumulativeDelta > maxShrink ? maxShrink : cumulativeDelta;
    final durations = <CutId, int>{cutId: beforeDuration - applied};
    final gaps = <CutId, int>{
      ?_leadDragNextCutId: _followingGapAfterEndMove(
        baseGap: _leadDragNextBeforeGap ?? 0,
        growth: -applied,
      ),
    };
    _leadDragAfter = after;
    _leadDragAfterDurations = durations;
    _leadDragAfterGaps = gaps;
    dragPreview.value = CutTrimDragPreview(
      previewDurations: durations,
      previewGaps: gaps,
      previewLayers: {after.id: after},
    );
  }

  void _endStoryboardLeadDrag() {
    final before = _leadDragBefore;
    final after = _leadDragAfter;
    final beforeDuration = _leadDragBeforeDuration;
    final cutId = _leadDragCutId;
    final nextId = _leadDragNextCutId;
    final nextBeforeGap = _leadDragNextBeforeGap;
    final afterDurations = _leadDragAfterDurations;
    final afterGaps = _leadDragAfterGaps;
    _cancelStoryboardLeadDrag();
    if (before == null ||
        after == null ||
        cutId == null ||
        beforeDuration == null ||
        afterDurations == null ||
        afterGaps == null) {
      return;
    }
    final beforeDurations = <CutId, int>{cutId: beforeDuration};
    _timelineController.commitLayerTimelineDragsWithCutDurations(
      edits: [(before: before, after: after)],
      beforeDurations: beforeDurations,
      afterDurations: afterDurations,
      beforeGaps: {
        if (nextId != null && afterGaps.containsKey(nextId))
          nextId: nextBeforeGap!,
      },
      afterGaps: afterGaps,
      description: 'Retime cut lead',
    );
    _refreshAfterCutCommand();
    _warmActiveCut();
    notifyListeners();
  }

  void _cancelStoryboardLeadDrag() {
    _leadDragBefore = null;
    _leadDragCutId = null;
    _leadDragBeforeDuration = null;
    _leadDragNextCutId = null;
    _leadDragNextBeforeGap = null;
    _leadDragAfter = null;
    _leadDragAfterDurations = null;
    _leadDragAfterGaps = null;
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

  int? _movieEndBeforeTrailing;

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
    _movieEndBeforeTrailing = _repository.requireProject().trailingFrames;
    return true;
  }

  /// Applies the cumulative frame delta as a live preview (the movie end
  /// never dips below the content end: the trailing gap clamps at 0).
  void updateMovieEndDrag(int cumulativeDelta) {
    final before = _movieEndBeforeTrailing;
    if (before == null) {
      return;
    }
    final next = math.max(0, before + cumulativeDelta);
    dragPreview.value = next == before
        ? null
        : MovieEndDragPreview(trailingFrames: next);
  }

  void endMovieEndDrag() {
    final before = _movieEndBeforeTrailing;
    final preview = dragPreview.value;
    _movieEndBeforeTrailing = null;
    dragPreview.value = null;
    if (before == null || preview is! MovieEndDragPreview) {
      return;
    }
    _historyManager.execute(
      UpdateProjectTrailingFramesCommand(
        repository: _repository,
        trailingFrames: preview.trailingFrames,
      ),
    );
    notifyListeners();
  }

  void cancelMovieEndDrag() {
    _movieEndBeforeTrailing = null;
    dragPreview.value = null;
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
    int headRowDelta = 0,
  }) {
    final row = trackId ?? selectedTrackId;
    _updateTrackRangeSelection(
      trackId: row,
      anchorRow: TrackRowAddress(row),
      anchorGlobalFrame: anchorGlobalFrame,
      headGlobalFrame: headGlobalFrame,
      headRowDelta: headRowDelta,
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
        return layer == null ? null : (index) => exposureBlockAt(layer, index);
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
    required int headRowDelta,
  }) {
    final railRows = _storyboardRailRows(trackId);
    final anchorIndex = railRows.indexOf(anchorRow);
    final List<TimelineRowAddress> spanned;
    if (anchorIndex < 0 || railRows.length < 2) {
      spanned = [anchorRow];
    } else {
      // The clamp IS the guard: a delta past either end simply stops at the
      // rail's last row.
      final headIndex = (anchorIndex + headRowDelta).clamp(
        0,
        railRows.length - 1,
      );
      final first = math.min(anchorIndex, headIndex);
      final last = math.max(anchorIndex, headIndex);
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
    // Starting a TRACK-axis selection clears the cut-local one: the two
    // state the same thing in different axes, and only one may be on screen
    // (the timeline's own frame ⊥ lane rule, one level up).
    clearFrameRangeSelection();
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

  /// A select-drag step on a track-SE row of the storyboard, stated on the
  /// track's GLOBAL frame axis.
  ///
  /// The SAME selection the cut row paints — one axis, several rows. It
  /// cannot be the timeline's cut-local selection: the display clone the
  /// timeline shows is WINDOWED to the active cut, so a sound two cuts away
  /// has no cut-local address to be selected by. The snap runs on the
  /// GLOBAL layer, which is also the layer any edit would commit against.
  void updateTrackSeRangeSelectionByFrame({
    required LayerId layerId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    int headRowDelta = 0,
  }) {
    // The anchor row names its own track: gating on the ACTIVE track's SE
    // list (and stating the selection on [selectedTrackId]) killed every
    // drag that anchored on an unselected track's row — the rail lookup
    // missed, so a cross-row reach collapsed to the anchor alone.
    final owner = _trackSeAnywhere(layerId)?.track;
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
      headRowDelta: headRowDelta,
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

  TrackId? _cutMoveTrackId;
  List<CutMoveSlot>? _cutMoveSlots;
  int? _cutMoveIndex;

  /// The selected run's LAST index while a group slide is live (UI-R18
  /// #1: dragging inside the cut selection moves the whole run).
  int? _cutMoveGroupEndIndex;

  /// Starts a whole-block move drag on [cutId].
  ///
  /// Where it ends up is [planCutMove]'s answer: a drag that stays in its
  /// own free space re-times (its leading gap grows or shrinks, the
  /// neighbours hold still), and a drag that reaches past a neighbour's
  /// midpoint REORDERS the track instead. Sliding used to shove the
  /// followers along on contact; that whole-track shove is what the
  /// push/pull buttons are for, and a drag that could only shove could
  /// never say "put this cut after that one".
  bool beginCutMoveDrag(CutId cutId) {
    final project = _repository.requireProject();
    for (final track in project.tracks) {
      final index = track.cuts.indexWhere((cut) => cut.id == cutId);
      if (index < 0) {
        continue;
      }
      _cutMoveTrackId = track.id;
      _cutMoveSlots = [
        for (final cut in track.cuts)
          (
            id: cut.id,
            leadingGapFrames: cut.leadingGapFrames,
            duration: cut.duration,
          ),
      ];
      _cutMoveIndex = index;
      _cutMoveGroupEndIndex = null;
      // Dragging inside the cut SELECTION slides the whole run (UI-R18
      // #1): anchor at the run's first cut, compensate past its last.
      final selection = storyboardSelectedCutIds;
      if (selection.contains(cutId)) {
        final order = [for (final cut in track.cuts) cut.id];
        final indexes = [for (final id in selection) order.indexOf(id)]
          ..removeWhere((value) => value < 0);
        if (indexes.length > 1) {
          indexes.sort();
          // Only a CONTIGUOUS run travels as one — a selection with a hole
          // in it has no single length to carry.
          if (indexes.last - indexes.first == indexes.length - 1) {
            _cutMoveIndex = indexes.first;
            _cutMoveGroupEndIndex = indexes.last;
          }
        }
      }
      return true;
    }
    return false;
  }

  /// Applies the move's cumulative frame delta as a live preview on
  /// [dragPreview] (the repository is NOT touched).
  void updateCutMoveDrag(int cumulativeDelta) {
    final plan = _cutMovePlanFor(cumulativeDelta);
    final trackId = _cutMoveTrackId;
    if (plan == null || trackId == null) {
      return;
    }
    if (plan.isReorder) {
      dragPreview.value = CutTrimDragPreview(
        previewDurations: const {},
        previewOrder: {trackId: plan.order!},
      );
      return;
    }
    dragPreview.value = plan.gaps.isEmpty
        ? null
        : CutTrimDragPreview(
            previewDurations: const {},
            previewGaps: plan.gaps,
          );
  }

  CutMovePlan? _cutMovePlanFor(int cumulativeDelta) {
    final slots = _cutMoveSlots;
    final index = _cutMoveIndex;
    if (slots == null || index == null) {
      return null;
    }
    return planCutMove(
      slots: slots,
      runStart: index,
      runEnd: _cutMoveGroupEndIndex ?? index,
      frameDelta: cumulativeDelta,
    );
  }

  /// Commits the move as a single undo step (no-op when nothing changed):
  /// a re-time lands as gaps, a reorder as the track's new sequence.
  /// Durations are untouched either way, so no fade re-anchor is needed.
  void endCutMoveDrag() {
    final slots = _cutMoveSlots;
    final trackId = _cutMoveTrackId;
    final preview = dragPreview.value;
    _cutMoveTrackId = null;
    _cutMoveSlots = null;
    _cutMoveIndex = null;
    _cutMoveGroupEndIndex = null;
    dragPreview.value = null;
    if (slots == null || trackId == null || preview is! CutTrimDragPreview) {
      return;
    }
    final order = preview.previewOrder[trackId];
    if (order != null) {
      _cutCommandCoordinator.setCutOrder(trackId: trackId, order: order);
      _refreshAfterCutCommand();
      notifyListeners();
      return;
    }
    final beforeGaps = {
      for (final slot in slots) slot.id: slot.leadingGapFrames,
    };
    final afterGaps = {
      for (final id in beforeGaps.keys)
        id: preview.previewGaps[id] ?? beforeGaps[id]!,
    };
    final changed = afterGaps.entries.any(
      (entry) => beforeGaps[entry.key] != entry.value,
    );
    if (!changed) {
      return;
    }
    _cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: const {},
      afterDurations: const {},
      beforeGaps: beforeGaps,
      afterGaps: afterGaps,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Drops an in-flight move preview without touching history.
  void cancelCutMoveDrag() {
    _cutMoveTrackId = null;
    _cutMoveSlots = null;
    _cutMoveIndex = null;
    _cutMoveGroupEndIndex = null;
    dragPreview.value = null;
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
  void updateLaneRangeSelectionDrag({
    required LayerId layerId,
    required String laneId,
    required int anchorIndex,
    required int headIndex,
    String? headLaneId,
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
    clearFrameRangeSelection();
    final start = math.max(0, math.min(anchorIndex, headIndex));
    final endExclusive = math.max(anchorIndex, headIndex) + 1;
    if (endExclusive <= start) {
      return;
    }
    // R6: effect lanes span within their own effect; every other lane id
    // resolves against the transform order.
    final span =
        effectLaneSpan(
          _layerById(layerId)?.effects ?? const [],
          laneId,
          headLaneId ?? laneId,
        ) ??
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
  /// snapshots plus the last VALID shifted track (blocked steps HOLD it,
  /// the #10 policy). Exactly one of [layer]/[track] is set — a layer's
  /// lanes or the V TRACK's own lanes (R4b, the carrier route).
  ({Layer? layer, Track? track, TimelineLaneSelection selection})?
  _laneMoveBefore;
  TransformTrack? _laneMoveShifted;

  /// The in-flight EFFECT-lane move's last valid chain (R6) — the effect
  /// counterpart of [_laneMoveShifted]; exactly one of the two is ever set.
  List<LayerEffect>? _laneMoveShiftedEffects;

  /// Starts moving the current lane selection; false when there is none
  /// or it covers no keys on ANY spanned lane (nothing to move).
  bool beginLaneRangeMoveDrag() {
    final selection = laneRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final carrierTrackId = trackIdOfTransformLaneCarrier(selection.layerId);
    if (carrierTrackId != null) {
      final track = _trackById(carrierTrackId);
      if (track == null) {
        return false;
      }
      final keyed = selection.spanLaneIds.any(
        (laneId) => transformLaneKeyFrames(
          track.transformTrack,
          laneId,
        ).any(selection.contains),
      );
      if (!keyed) {
        return false;
      }
      _laneMoveBefore = (layer: null, track: track, selection: selection);
      _laneMoveShifted = null;
      // Both in-flight slots clear together: a stale effect chain here
      // would send the commit down the layer branch with layer == null.
      _laneMoveShiftedEffects = null;

      return true;
    }
    final layer = _layerById(selection.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return false;
    }
    // R6: an EFFECT lane selection moves the effect chain's keys instead of
    // the transform track's — same rigid all-or-nothing group, same drag.
    final isEffectSelection = selection.spanLaneIds.any(
      (laneId) => parseEffectLaneId(laneId) != null,
    );
    final keyed = selection.spanLaneIds.any(
      (laneId) => isEffectSelection
          ? effectLaneKeyFrames(layer.effects, laneId).any(selection.contains)
          : transformLaneKeyFrames(
              layer.transformTrack,
              laneId,
            ).any(selection.contains),
    );
    if (!keyed) {
      return false;
    }
    _laneMoveBefore = (layer: layer, track: null, selection: selection);
    _laneMoveShifted = null;
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

      dragPreview.value = null;
      laneRangeSelection.value = before.selection;
      return;
    }
    final effectLayer = before.layer;
    if (effectLayer != null &&
        before.selection.spanLaneIds.any(
          (laneId) => parseEffectLaneId(laneId) != null,
        )) {
      final shiftedEffects = effectsWithLaneSpanKeysShifted(
        effectLayer.effects,
        laneIds: before.selection.spanLaneIds,
        rangeStartIndex: before.selection.startIndex,
        rangeEndIndexExclusive: before.selection.endIndexExclusive,
        frameDelta: frameDelta,
      );
      if (shiftedEffects == null) {
        // Blocked landing: the last valid preview and outline HOLD.
        return;
      }
      _laneMoveShiftedEffects = shiftedEffects;
      dragPreview.value = BlockMoveDragPreview(
        previewLayers: {
          effectLayer.id: effectLayer.copyWith(effects: shiftedEffects),
        },
      );
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
    final sourceTrack =
        before.layer?.transformTrack ?? before.track!.transformTrack;
    final shifted = transformTrackWithLaneSpanKeysShifted(
      sourceTrack,
      laneIds: before.selection.spanLaneIds,
      rangeStartIndex: before.selection.startIndex,
      rangeEndIndexExclusive: before.selection.endIndexExclusive,
      frameDelta: frameDelta,
    );
    if (shifted == null) {
      // Blocked landing: the last valid preview and outline HOLD.
      return;
    }
    _laneMoveShifted = shifted;

    final layer = before.layer;
    dragPreview.value = layer != null
        ? BlockMoveDragPreview(
            previewLayers: {layer.id: layer.copyWith(transformTrack: shifted)},
          )
        : BlockMoveDragPreview(
            previewLayers: const {},
            previewTrackTransforms: {before.track!.id: shifted},
          );
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

    dragPreview.value = null;
    if (before != null && shiftedEffects != null) {
      updateLayerEffects(
        before.layer!.id,
        shiftedEffects,
        description: 'Move lane keys',
      );
      laneRangeSelection.value = landed;
      return;
    }
    if (before == null || shifted == null) {
      if (before != null) {
        laneRangeSelection.value = before.selection;
      }
      return;
    }
    final layer = before.layer;
    if (layer != null) {
      updateLayerTransformTrack(
        layer.id,
        shifted,
        description: 'Move lane keys',
      );
    } else {
      updateTrackTransformTrack(
        before.track!.id,
        shifted,
        description: 'Move lane keys',
      );
    }
    laneRangeSelection.value = landed;
  }

  /// Drops an in-flight lane-move preview, restoring the selection.
  void cancelLaneRangeMoveDrag() {
    final before = _laneMoveBefore;
    _laneMoveBefore = null;
    _laneMoveShifted = null;
    _laneMoveShiftedEffects = null;

    dragPreview.value = null;
    if (before != null) {
      laneRangeSelection.value = before.selection;
    }
  }

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
  void updateFrameRangeSelectionDrag({
    required LayerId layerId,
    required int anchorIndex,
    required int headIndex,
    LayerId? headLayerId,
    String? headLaneId,
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
    // Starting a CELL selection clears the lane selection (mutual
    // exclusion, UI-R23 #3 part 2) — unless THIS drag is the one
    // producing it (the mixed span below re-sets it).
    clearLaneRangeSelection();
    // …and the TRACK-axis selection, for the same reason one level up: the
    // two state a range in different axes and only one may be on screen.
    clearStoryboardCutSelection();
    final base = snapFrameRangeToBlocks(
      layer: layer,
      anchorIndex: anchorIndex,
      headIndex: headIndex,
    );
    if (base == null) {
      frameRangeSelection.value = null;
      return;
    }
    final spanIds = _selectionSpanLayerIds(layerId, headLayerId ?? layerId);
    if (spanIds.length <= 1) {
      frameRangeSelection.value = base;
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
    trackFrameRangeSelection.value = span == null
        ? null
        : TrackFrameRangeSelection(
            trackId: selectedTrackId,
            anchorRow: LayerRowAddress(span.layerId),
            rows: [for (final id in span.spanLayerIds) LayerRowAddress(id)],
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
    final sources = <({Layer commit, int offset})>[];
    for (final row in live.spanRows) {
      if (row is! LayerRowAddress) {
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
    if (sources.isEmpty) {
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
    _rangeMoveInstructionSources = null;
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
      cameraCutId: cameraShifted == null ? null : activeCutOrNull?.id,
      cameraKeyframes: cameraShifted,
      cameraMarkerLayer:
          cameraShifted == null || _rangeMoveCameraLayerId == null
          ? null
          : _layerById(_rangeMoveCameraLayerId!),
    );
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
    final selection = _rangeMoveSelectionBefore;
    if (selection != null) {
      _rangeMoveSelection = selection;
    }
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
      final previewLayers = <LayerId, Layer>{
        for (final plan in plans)
          // Track-SE rows preview in their DISPLAY form (UI-R18
          // #1 seam); commits keep the global form.
          plan.sourceAfter.id: isTrackSeLayerId(plan.sourceAfter.id)
              ? trackSeWindow.displayLayer(
                  rederiveRunBehaviors(
                    plan.sourceAfter,
                    cutFrameCount: _activeCutFrameCount,
                  ),
                )
              : rederiveRunBehaviors(
                  plan.sourceAfter,
                  cutFrameCount: _activeCutFrameCount,
                ),
        // Instruction rows preview with their shifted spans —
        // the cells row renders straight off layer.instructions.
        for (final entry in instructionShifted.entries)
          if (_layerById(entry.key) != null)
            entry.key: _layerById(
              entry.key,
            )!.copyWith(instructions: entry.value),
      };
      dragPreview.value = BlockMoveDragPreview(
        previewLayers: previewLayers,
        cameraCutId: cameraShifted == null ? null : activeCutOrNull?.id,
        cameraKeyframes: cameraShifted,
        cameraMarkerLayer: cameraMarker,
      );
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
        if (instructionShifted != null && cut != null)
          for (final entry in instructionShifted.entries)
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
    if (selection != null) {
      _rangeMoveSelection = selection;
    }
  }

  // --- Run-edge NEW FRAMES drag (UI-R8 [+] handle) --------------------------

  Layer? _addFramesBefore;
  int? _addFramesBlockStart;
  bool _addFramesAtEnd = true;
  Layer? _addFramesAfter;
  final List<FrameId> _addFramesReservedIds = [];

  /// Reserves project-unique frame ids for the drag, deterministically:
  /// the same ordinal always resolves the same id, so every preview step
  /// and the commit agree.
  FrameId _reservedNewFrameId(int ordinal) {
    while (_addFramesReservedIds.length <= ordinal) {
      final used = <String>{for (final id in _addFramesReservedIds) id.value};
      for (final track in _repository.requireProject().tracks) {
        for (final layer in track.seLayers) {
          for (final frame in layer.frames) {
            used.add(frame.id.value);
          }
        }
        for (final cut in track.cuts) {
          for (final layer in cut.layers) {
            for (final frame in layer.frames) {
              used.add(frame.id.value);
            }
          }
        }
      }
      var candidate = 1;
      while (used.contains('frame-$candidate')) {
        candidate += 1;
      }
      _addFramesReservedIds.add(FrameId('frame-$candidate'));
    }
    return _addFramesReservedIds[ordinal];
  }

  /// Starts a "+ add frames" drag at the run edge (UI-R8): [atEnd] picks
  /// the side. Returns false when the row stands down or there is no run.
  bool beginRunFramesAddDrag({
    required LayerId layerId,
    required int blockStartIndex,
    required bool atEnd,
  }) {
    if (!_blockMoveEligible(layerId)) {
      return false;
    }
    final layer = _layerById(layerId);
    if (layer == null || gluedRunAt(layer, blockStartIndex) == null) {
      return false;
    }
    _addFramesBefore = layer;
    _addFramesBlockStart = blockStartIndex;
    _addFramesAtEnd = atEnd;
    _addFramesAfter = null;
    _addFramesReservedIds.clear();
    return true;
  }

  /// Live preview: [count] new one-frame drawings at the run edge (0 shows
  /// the committed state).
  void updateRunFramesAddDrag(int count) {
    final before = _addFramesBefore;
    final blockStart = _addFramesBlockStart;
    if (before == null || blockStart == null) {
      return;
    }
    if (count < 1) {
      _addFramesAfter = null;
      dragPreview.value = null;
      return;
    }
    final result = layerWithNewFramesAtRunEdge(
      before,
      blockStartIndex: blockStart,
      atEnd: _addFramesAtEnd,
      count: count,
      frameIdAt: _reservedNewFrameId,
    );
    _addFramesAfter = result == null
        ? null
        : rederiveRunBehaviors(
            result.layer,
            cutFrameCount: _activeCutFrameCount,
          );
    dragPreview.value = _addFramesAfter == null
        ? null
        : ExposureEdgeDragPreview(previewLayer: _addFramesAfter!);
  }

  /// Commits the added frames as ONE undo step.
  void endRunFramesAddDrag() {
    final before = _addFramesBefore;
    final after = _addFramesAfter;
    _addFramesBefore = null;
    _addFramesBlockStart = null;
    _addFramesAfter = null;
    _addFramesReservedIds.clear();
    dragPreview.value = null;
    if (before == null || after == null || after == before) {
      return;
    }
    _timelineController.commitLayerTimelineDrag(before: before, after: after);
    _warmActiveCut();
    notifyListeners();
  }

  void cancelRunFramesAddDrag() {
    _addFramesBefore = null;
    _addFramesBlockStart = null;
    _addFramesAfter = null;
    _addFramesReservedIds.clear();
    dragPreview.value = null;
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

  bool get canDeleteCellAtCurrentFrame {
    // A live selection is deletable wherever the playhead stands (UI-R17
    // #2).
    if (_selectionBlockStartsByLayer() != null) {
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
        layer.kind != LayerKind.se ||
        !canRenameFrameAtCurrentFrame) {
      return;
    }

    _timelineController.renameFrameForLayer(
      layerId: layer.id,
      frameId: frame.id,
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
  bool get editingPlayheadInGap =>
      _gapGlobalFrame != null || trackFrameAxis().isGap(editingGlobalFrame);

  /// The gap parking's exact global frame, or null when the playhead sits
  /// on a cut. Cheap field read — per-tick consumers (the storyboard
  /// playhead) use it without rebuilding the axis.
  int? get gapParkedGlobalFrame => _gapGlobalFrame;

  /// The editing playhead as a track-global frame. A gap parking returns
  /// its stored global; otherwise over-end positions clamp to the active
  /// CUT's last frame (UI-R9 #4 — the timeline's runway is a clipped view
  /// of the cut, so the global axis never shows it inside the trailing
  /// gap).
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
    return trackFrameAxis().clampedToCutGlobalOf(cutId, currentFrameIndex) ??
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
  /// A gap has always landed here because there is no cut to take. The
  /// storyboard's SE rows land here too (feedback #7): pressing a sound
  /// says where you are, not which cut you are editing, and the active cut
  /// is meant to answer only to picking a cut on the row that HAS cuts.
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

  void selectGlobalFrame(int globalFrame) {
    if (editingInteractionBusy) {
      return;
    }
    final axis = trackFrameAxis();
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
  List<Layer> get _onionSweepLayers => [
    for (final layer in activeCutOrNull?.layers ?? const <Layer>[])
      if (layer.isVisible && layerKindAcceptsBrushInput(layer.kind)) layer,
  ];

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
        if (enabledIds.contains(layer.id) &&
            layer.isVisible &&
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
    return path == null ? null : AppSave.sidecarPathFor(path);
  }

  /// Writes the current state to [path] WITHOUT touching the dirty flag or
  /// the project path — the autosave service's snapshot writer. Creates
  /// the parent folder (a custom sidecar directory may not exist yet).
  Future<void> writeAutosaveSnapshot(String path) async {
    await _flushTextCelBakes();
    await File(path).parent.create(recursive: true);
    await _anicelFileService.save(
      project: _repository.requireProject(),
      brushFrameStore: brushFrameStore,
      auxCelStores: [conteInkRowStore, conteInkPageStore],
      filePath: path,
    );
  }

  /// Saves the project + every drawn frame into ONE .anicel file (atomic
  /// temp-then-rename write; media stays external with relative paths
  /// recorded for Drive portability). A successful save retires the
  /// autosave sidecar.
  Future<void> saveProjectToFile(String filePath) async {
    // A text bake in flight must land before the store snapshots — the
    // archive's parameters and raster must never disagree.
    await _flushTextCelBakes();
    final previousSidecar = autosaveSidecarPath;
    // Before serializing: the first save adopts the session's shelf
    // takes into Media/ so the .anicel carries the adopted paths.
    final adoptedTakePaths = _adoptShelfTakesForSave(filePath);
    await _anicelFileService.save(
      project: _repository.requireProject(),
      brushFrameStore: brushFrameStore,
      auxCelStores: [conteInkRowStore, conteInkPageStore],
      filePath: filePath,
    );
    _projectFilePath = filePath;
    _hasUnsavedChanges = false;
    if (adoptedTakePaths.isNotEmpty) {
      // With the project path set, conforms resolve into the new
      // `.assets` container — refresh the moved takes there.
      for (final path in adoptedTakePaths) {
        audioConformStore.invalidate(path);
      }
      audioConformStore.warmPaths(adoptedTakePaths);
    }
    // Awaited: a still-in-flight delete could otherwise race a following
    // autosave tick and eat its fresh sidecar. EVERY candidate location
    // retires (the sidecar-directory setting may have moved since the
    // stale one was written).
    if (previousSidecar != null) {
      await ProjectAutosaveService.deleteSidecar(previousSidecar);
    }
    for (final candidate in AppSave.sidecarCandidatesFor(filePath)) {
      await ProjectAutosaveService.deleteSidecar(candidate);
    }
    notifyListeners();
  }

  /// Opens a .anicel file, replacing the WHOLE session state: project,
  /// drawings, selection (first cut, frame 0) — and BOTH undo stacks
  /// (loaded state has no history; the load→draw→undo path is pinned by
  /// test). [recoverAs] opens autosave SIDECAR bytes while keeping the
  /// real file as the project path (the recovery flow).
  Future<void> openProjectFromFile(String filePath, {String? recoverAs}) async {
    final result = await _anicelFileService.open(filePath: filePath);
    playback.stop();
    _repository.replaceProject(result.project);
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
    Set<FrameId>? liveFrameIds;
    for (final entry in result.cels.entries) {
      final key = entry.key;
      if (!isConteInkKey(key)) {
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
    _historyManager.clear();
    _copiedFrame = null;
    _layerClipboard = null;
    _editingSession.setActiveCutId(result.project.tracks.first.cuts.first.id);
    _rebuildActiveCutControllers();
    // The replaced project's shelf takes are no longer this session's to
    // adopt — they stay on the shelf, findable.
    _voiceRecordShelfPaths.clear();
    _voiceRecordShelfDirectory = null;
    _projectFilePath = recoverAs ?? filePath;
    _warmAudioConforms();
    // A recovered session stays dirty: its content differs from the real
    // file until the user saves.
    _hasUnsavedChanges = recoverAs != null;
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

  /// Jumps to the previous drawing block's START on the active layer
  /// (Ctrl+`,`): from mid-block that is the current block's start — the
  /// clip-navigation convention.
  void selectPreviousDrawing() {
    final layer = activeLayer;
    if (layer == null) {
      return;
    }
    final block = previousDrawingBlockBefore(
      layer.timeline,
      _timelineController.currentFrameIndex,
    );
    if (block != null) {
      selectFrameIndex(block.startIndex);
    } else {
      // PEN-8 #2: no earlier drawing — walk EMPTY space one frame at a
      // time instead of dead-ending (the plain-arrow/파라파라 unit:
      // blocks where blocks exist, frames where they don't).
      selectPreviousFrame();
    }
  }

  /// Jumps to the next drawing block's start on the active layer
  /// (Ctrl+`.`).
  void selectNextDrawing() {
    final layer = activeLayer;
    if (layer == null) {
      return;
    }
    final block = nextDrawingBlockAfter(
      layer.timeline,
      _timelineController.currentFrameIndex,
    );
    if (block != null) {
      selectFrameIndex(block.startIndex);
    } else {
      // PEN-12 #2: no NEXT drawing but the cursor sits ON a block —
      // escape past its end in one press (never crawl through a long
      // tail block one frame at a time); pure empty space keeps the
      // PEN-8 one-frame walk.
      final covering = coveringDrawingBlockAt(
        layer.timeline,
        _timelineController.currentFrameIndex,
      );
      if (covering != null) {
        selectFrameIndex(covering.endIndexExclusive);
      } else {
        selectNextFrame();
      }
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

  /// True while a ruler scrub is in flight — the canvas swaps to the
  /// composite-cache preview (the playback display machinery) until the
  /// release commit.
  final ValueNotifier<bool> frameScrubActive = ValueNotifier<bool>(false);

  /// A scrub move: repositions the playhead WITHOUT notifying — only the
  /// cursor listenables fire; the full session notify is deferred to
  /// [commitFrameScrub] on release. The canvas preview engages on the
  /// first move that actually changes the frame, so a same-frame tap
  /// never flashes it.
  void scrubFrameIndex(int frameIndex) {
    // R15-⑤: scrubs are seeks too — refused under a live edit.
    if (editingInteractionBusy) {
      return;
    }
    if (frameIndex != _timelineController.currentFrameIndex) {
      _timelineController.selectFrameIndex(frameIndex);
      editingFrameCursor.value = frameIndex;
      // Each crossed frame plays its slice of the mix (2D audio scrub).
      audioScrubber.onScrubFrame(frameIndex);
      if (!frameScrubActive.value) {
        frameScrubActive.value = true;
        // One warm per gesture: the preview reads the composite cache, so
        // a cold cut starts filling immediately (per-move warms would only
        // thrash the scheduler's ordering).
        _warmActiveCut();
      }
    } else {
      editingFrameCursor.value = frameIndex;
    }
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

  /// Camera rows summarize their property lanes Blender-dopesheet style:
  /// the union of lane keys per frame, ■ when every keyed lane holds there
  /// and ◆ otherwise. The glyph rides the frame-name channel — the cell
  /// renders it marker-styled (no paper block).
  String? frameNameForLayer(Layer layer, int frameIndex) {
    if (layer.kind == LayerKind.camera) {
      // A camera row exists only with a cut on screen.
      final track = requireActiveCut.camera.track;
      final interpolations = [
        track.anchorPoint.keyAt(frameIndex)?.interpolation,
        track.position.keyAt(frameIndex)?.interpolation,
        track.scale.keyAt(frameIndex)?.interpolation,
        track.rotation.keyAt(frameIndex)?.interpolation,
        track.opacity.keyAt(frameIndex)?.interpolation,
      ].whereType<PropertyKeyInterpolation>().toList();
      if (interpolations.isEmpty) {
        return null;
      }
      return interpolations.every(
            (interpolation) => interpolation == PropertyKeyInterpolation.hold,
          )
          ? '■'
          : '◆';
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
    if (layer.kind == LayerKind.camera) {
      // The camera row's cells mirror the cut's camera keyframes — or
      // the in-flight key-range move's preview keys (P3b-2), so the row
      // follows the drag while the repository stays untouched.
      final previewKeys = _cameraKeysDragPreview;
      if (previewKeys != null) {
        return previewKeys.containsKey(frameIndex)
            ? TimelineCellExposureState.drawingStart
            : TimelineCellExposureState.uncovered;
      }
      return activeCutOrNull?.camera.keyframeAt(frameIndex) != null
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
  });

  final LayerId layerId;
  final FrameId frameId;
  final String? frameName;
}

/// Which verb an in-flight cut-edge drag belongs to (feedback #5/#9). One
/// shape of edge, and where it sat when the drag began decides what it
/// re-times; the session keeps the answer so the continuations cannot be
/// re-routed by anything a live preview rebuilds.
enum _CutEdgeDragVerb {
  /// A cut with no storyboard row: the plain duration/gap trims.
  cutTrim,

  /// The first panel's leading edge: the cut's LEAD re-times (the first
  /// cell's comma, the cut start pinned).
  leadRetime,

  /// ANY panel's trailing edge: that cell's comma, the later panels
  /// rippling glued and the cut's length riding the row end (feedback
  /// #9; the edge unification retired the division verb this replaced).
  comma,
}
