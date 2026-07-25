import 'dart:async' show Timer, unawaited;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../controllers/default_layer_helpers.dart';
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
import '../controllers/editing_session_state.dart';
import '../controllers/layer_controller.dart';
import '../controllers/timeline_controller.dart';
import '../models/attached_layer_resolve.dart';
import '../models/attached_mode.dart';
import '../models/attached_placement.dart';
import '../models/bitmap_surface.dart';
import '../models/audio_clip.dart';
import '../models/brush_frame_key.dart';
import '../models/camera_instruction.dart';
import '../models/camera_pose.dart';
import '../models/canvas_point.dart';
import '../models/canvas_resize_anchor.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/cut_camera.dart';
import '../models/transform_track.dart';
import '../models/cut_id.dart';
import '../models/cut_metadata.dart';
import '../models/layer_folder.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_blend_mode.dart';
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
import '../models/property_track.dart';
import '../models/timeline_coverage.dart';
import '../models/timeline_frame_range.dart';
import '../models/timeline_repeat.dart';
import '../models/timeline_run_edit.dart';
import '../models/track.dart';
import '../models/track_id.dart';
import '../models/track_se_window.dart';
import '../services/brush_frame_store.dart';
import '../services/camera_pose_resolver.dart';
import '../services/clipboard/layer_copy_payload.dart';
import '../services/commands/convert_to_linked_cut_plan.dart';
import '../models/brush_frame_cache_invalidation.dart';
import '../models/playback_quality.dart';
import '../services/cut_frame_composite_plan.dart';
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
import 'text/app_strings.dart';
import '../models/track_frame_axis.dart';
import 'storyboard_timeline_layout.dart';
import '../models/drawing_block_move.dart';
import '../models/multi_row_range_move.dart';
import '../services/command.dart';
import '../services/commands/cut_command_coordinator.dart';
import '../services/commands/rekey_brush_frames_command.dart';
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
import '../services/persistence/qap_file_service.dart';
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
import 'timeline/transform_lane_editing.dart'
    show
        transformLaneKeyFrames,
        transformTrackWithLaneKeyToggled,
        transformTrackWithLaneSpanKeysShifted;
import 'timeline/transform_lane_policy.dart'
    show transformLaneDisplayOrder, transformLaneSpan;

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

  /// The PASTEBOARD color is app state (the accents' idiom): it is the
  /// working environment around the stage, never part of the artwork.
  /// The canvas paper is the project's, through [setProjectBackground].
  Future<void> _restoreWorkspaceColors() async {
    final restored = await _workspaceColorsStore?.load();
    if (restored != null) {
      AppWorkspaceColors.settings.value = restored;
    }
  }

  void setPasteboardColor(int argb) {
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
  /// not project state: a rig's delay must not travel inside a `.qap`.
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
        fxBypassedLayerIdsOf: () => _fxBypassedLayerIds,
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
        afterFrameCached: () => _playbackCacheBudgetEnforcer.enforce(
          protect: _playbackProtectedRanges(),
        ),
      );

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
    resolveActiveTrackId: () => activeCutTrackId,
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
    resolveUserOffsetSamples: (sampleRate) => audioSyncSettings.value
        .offsetSamples(
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

  TrackId get activeCutTrackId {
    final activeCutId = _editingSession.activeCutId;
    final project = _repository.requireProject();
    for (final track in project.tracks) {
      if (track.cuts.any((cut) => cut.id == activeCutId)) {
        return track.id;
      }
    }

    if (project.tracks.isEmpty) {
      throw StateError('Cannot resolve active Cut track in an empty project.');
    }
    return project.tracks.first.id;
  }

  // --- Track-owned SE rows --------------------------------------------------
  //
  // SE rows live on the TRACK (global frame axis — sounds may cross cut
  // boundaries). Reads go through cut-local DISPLAY clones composed into
  // [layers]; mutations detect track-SE ids, convert local→global through
  // the window, and edit the track's GLOBAL layer (the clones are never
  // written back).

  Track get activeTrack {
    final trackId = activeCutTrackId;
    return _repository.requireProject().tracks.firstWhere(
      (track) => track.id == trackId,
    );
  }

  /// The active cut's global start frame on its track (cumulative cut
  /// durations — the storyboard layout's number for this cut).
  int get activeCutGlobalStartFrame {
    final activeCutId = _editingSession.activeCutId;
    var start = 0;
    for (final cut in activeTrack.cuts) {
      start += cut.leadingGapFrames;
      if (cut.id == activeCutId) {
        return start;
      }
      start += cut.duration;
    }
    return 0;
  }

  TrackSeWindow get trackSeWindow => TrackSeWindow(
    cutStartFrame: activeCutGlobalStartFrame,
    cutDurationFrames: activeCutOrNull?.duration ?? 0,
  );

  bool isTrackSeLayerId(LayerId layerId) =>
      activeTrack.seLayers.any((layer) => layer.id == layerId);

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
    brushFrameStore.celContentRevision.removeListener(_bumpCelTintRevision);
    brushInputActive.removeListener(_bumpCelTintRevision);
    celTintRevision.dispose();
    cacheInvalidationHub.removeBrushFrameListener(_onBrushFrameInvalidated);
    playback.globalFrameIndexListenable.removeListener(_followPlaybackCut);
    _historyManager.removeListener(_markProjectDirty);
    _historyManager.removeListener(_refreshLiveAudioSchedule);
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
    storyboardCutSelection.dispose();
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
      trackId: activeCutTrackId,
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
      targetTrackId: activeCutTrackId,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  void deleteActiveCut() {
    // With a cut RANGE selection live, the delete command acts on the
    // whole run instead of the active cut (UI-R18 #1).
    if (storyboardCutSelection.value?.isNotEmpty ?? false) {
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

  void reorderCut({
    required CutId draggedCutId,
    required TrackId targetTrackId,
    required int targetCutIndex,
  }) {
    final plan = _cutReorderPlanner.planSameTrackDrop(
      project: _repository.requireProject(),
      draggedCutId: draggedCutId,
      targetTrackId: targetTrackId,
      targetCutIndex: targetCutIndex,
    );
    if (plan == null) {
      return;
    }

    _cutCommandCoordinator.reorderCut(
      trackId: plan.trackId,
      cutId: plan.cutId,
      newIndex: plan.newIndex,
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

  /// Whether [cut]'s camera layer sits in the fx-bypass set.
  bool _cameraFxBypassedFor(Cut cut) {
    final camera = cut.layers.cameraLayer;
    return camera != null && _fxBypassedLayerIds.contains(camera.id);
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
          );
        case CutFrameCompositeEntryLeaf(:final entry):
          // A brush-banned active layer (SE/instruction, R6-④) has no
          // interactive surface — it composites like any other stack row
          // so its existing cels keep displaying read-only.
          if (entry.layer.id == activeLayerId &&
              layerKindAcceptsBrushInput(entry.layer.kind)) {
            activeLayerOpacity = !entry.layer.isVisible
                ? 0.0
                : _stackLayerOpacity(entry.layer, stackCut.layers, frameIndex);
            return CanvasActiveLayerNode(
              opacity: entry.opacity,
              pose: entry.pose,
              anchorPoint: entry.anchorPoint,
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
            ),
          );
      }
    }

    final nodes = <CanvasLayerStackNode>[
      for (final node in resolveCutFrameCompositeTree(
        cut: stackCut,
        frameIndex: frameIndex,
        fxBypassedLayerIds: fxBypassedLayerIds,
      ))
        ?mapNode(node),
    ];

    // An ACTIVE layer with nothing exposed at this frame resolves no entry
    // at all, so the walk above never reaches it. It still needs its node:
    // the interactive surface is where the next stroke lands.
    if (activeLayerId != null &&
        !_treeHoldsActiveLayer(nodes) &&
        layerKindAcceptsBrushInput(
          stackCut.layers.byId(activeLayerId)?.kind ?? LayerKind.camera,
        )) {
      final active = stackCut.layers.byId(activeLayerId)!;
      activeLayerOpacity = !active.isVisible
          ? 0.0
          : _stackLayerOpacity(active, stackCut.layers, frameIndex);
      nodes.add(CanvasActiveLayerNode(opacity: activeLayerOpacity));
    }

    // Track-owned SE rows join as their cut-local display clones — they
    // composite read-only like before the ownership move (their transform
    // tracks are stripped, so the plain resolve path suffices). They live
    // outside the cut's stack, so they land at the top level.
    for (final layer in withOpacityPreview(trackSeDisplayLayers)) {
      final fxEnabled = isLayerFxEnabled(layer.id);
      if (!layer.isVisible || layer.opacity <= 0) {
        continue;
      }
      final opacity = fxEnabled
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
    if (!isLayerFxEnabled(fxCarrier.id)) {
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
      if (!isLayerFxEnabled(fxCarrier.id)) {
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

  /// The ACTIVE cut's cut-level pose over the CANVAS at [frameIndex]
  /// (default: the playhead) — the storyboard V-row fx preview on the
  /// EDITING canvas and the scrub preview (R9-B). Non-null only while the
  /// cut's geometric lanes carry keys AND its fx apply; canvas-space via
  /// the camera-frame conjugation (cutPoseForCanvasPreview — the exact
  /// remap playback uses, R8-③).
  LayerPoseSample? activeCutCanvasPoseSample({int? frameIndex}) {
    final cut = activeCutOrNull;
    if (cut == null || !isCutFxEnabled(cut.id) || !cutPoseIsActive(cut)) {
      return null;
    }
    final preview = cutPoseForCanvasPreview(
      cut,
      frameIndex ?? _timelineController.currentFrameIndex,
      cameraFrameSize: cameraFrameSize,
      canvasSize: cut.canvasSize,
    );
    return (pose: preview.pose, anchorPoint: preview.anchorPoint);
  }

  /// The cut fade the editing canvas (and the scrub preview) shows at
  /// [frameIndex] (default: the playhead) — the resolved opacity while the
  /// cut's fx apply, 1 when bypassed. R9-C rule: fx ALWAYS reflects; dark
  /// faded frames are worked with the fx switch off.
  double activeCutEditingFadeOpacity({int? frameIndex}) {
    final cut = activeCutOrNull;
    if (cut == null || !isCutFxEnabled(cut.id)) {
      return 1;
    }
    return cut.fadeOpacityAt(
      frameIndex ?? _timelineController.currentFrameIndex,
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
      trackId: activeCutTrackId,
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
  /// handles): rewrites the cut-level transform's opacity lane to the
  /// canonical fade shape; one undo step, no-op when unchanged.
  void setCutFade(
    CutId cutId, {
    required int fadeInFrames,
    required int fadeOutFrames,
  }) {
    final cut = cutById(cutId);
    if (cut == null) {
      return;
    }
    _cutCommandCoordinator.updateCutTransform(
      cutId: cutId,
      transformTrack: cutTransformWithFade(
        cut,
        fadeInFrames: fadeInFrames,
        fadeOutFrames: fadeOutFrames,
      ),
      description: 'Fade cut',
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Replaces [cutId]'s cut-level transform track (the storyboard V
  /// track's Transform lanes — the whole cut's finished picture moving on
  /// the display space, applied at display time like the fade, never
  /// baked into composites); one undo step, no-op when unchanged. The
  /// fade handles keep writing the same track through [setCutFade].
  void updateCutTransformTrack(
    CutId cutId,
    TransformTrack track, {
    String description = 'Edit cut transform',
  }) {
    _cutCommandCoordinator.updateCutTransform(
      cutId: cutId,
      transformTrack: track,
      description: description,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Sets what [cutId]'s fade fades TO — black (FO) or white (WO); one
  /// undo step, no-op when unchanged. Playback and the MP4 bake share the
  /// value.
  void setCutFadeTarget(CutId cutId, CutFadeTarget fadeTarget) {
    _cutCommandCoordinator.updateCutFadeTarget(
      cutId: cutId,
      fadeTarget: fadeTarget,
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

  // --- Layer FX bypass (session view state, not persisted) -----------------

  /// Layers whose FX (transform + animated opacity) are bypassed on every
  /// composite route — the layer-label fx switch. The set joins the
  /// composite signatures, so toggling self-invalidates the caches.
  final Set<LayerId> _fxBypassedLayerIds = {};

  Set<LayerId> get fxBypassedLayerIds => _fxBypassedLayerIds;

  bool isLayerFxEnabled(LayerId layerId) =>
      !_fxBypassedLayerIds.contains(layerId);

  void toggleLayerFx(LayerId layerId) {
    if (!_fxBypassedLayerIds.remove(layerId)) {
      _fxBypassedLayerIds.add(layerId);
    }
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

  void selectCut(CutId cutId) {
    if (cutId == _editingSession.activeCutId) {
      return;
    }
    // R15-⑤: never switch cuts under a live editing interaction.
    if (editingInteractionBusy) {
      return;
    }

    final fromGap =
        _gapGlobalFrame != null || _editingSession.activeCutId == null;
    // The visibility solo is cut-scoped: restore the eyes before leaving.
    if (_layerVisibilitySoloEnabled) {
      _exitVisibilitySolo();
    }
    _editingSession.setActiveCutId(cutId);
    _copiedFrame = null;
    clearFrameRangeSelection();
    _rebuildActiveCutControllers();
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
    // composites them read-only).
    if (!layerKindAcceptsBrushInput(activeLayer.kind)) {
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
      trackId: activeCutTrackId,
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
      LayerKind.animation ||
      LayerKind.storyboard ||
      LayerKind.art ||
      LayerKind.folder => true,
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
        trackId: activeCutTrackId,
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
          trackId: activeCutTrackId,
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
            trackId: activeCutTrackId,
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
      case LayerKind.art:
        // An attach group is INDIVISIBLE (R26 #36): a new regular layer
        // lands past the whole group, never between a base and its attach
        // rows — whether the active row is the base itself or one of its
        // attach rows (W5).
        final active = activeLayer;
        final baseId = active == null
            ? null
            : isAttachedLayer(active)
            ? active.attachedToLayerId
            : active.id;
        if (baseId != null) {
          final cut = requireActiveCut;
          final groupEnd = attachedGroupEndIndex(baseId, cut.layers);
          final baseIndex = cut.layers.indexWhere((l) => l.id == baseId);
          if (groupEnd > baseIndex + 1) {
            _layerController.addLayer(
              layer: createDefaultAnimationLayer(
                layerId: layerId,
                cut: cut,
              ).copyWith(kind: kind),
              insertionIndex: groupEnd,
            );
            break;
          }
        }
        _layerController.addLayerWithDefaults(layerId: layerId, kind: kind);
      case LayerKind.camera:
      // Folders are MADE, not added: 폴더 생성 wraps existing rows
      // ([groupActiveLayerIntoFolder]). Add Layer with a folder row active
      // adds a drawing cel, like it does with the camera active.
      case LayerKind.folder:
        _layerController.addLayerWithDefaults(layerId: layerId);
    }
    notifyListeners();
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
    // existing belows), a new above topmost (past the group).
    final insertionIndex = placement == AttachedPlacement.below
        ? baseIndex -
              attachedLayersOf(base.id, cut.layers)
                  .where(
                    (layer) =>
                        layer.attachedPlacement == AttachedPlacement.below,
                  )
                  .length
        : attachedGroupEndIndex(base.id, cut.layers);
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
        kind: base.kind,
        onTimesheet: false,
        attachedToLayerId: base.id,
        attachedPlacement: placement,
        attachedMode: mode,
      ),
      insertionIndex: insertionIndex,
    );
    notifyListeners();
  }

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

  /// Bypasses or restores EVERY layer's fx (session view state, like the
  /// per-row switch).
  void setAllLayersFxBypassed(bool bypassed) {
    if (bypassed) {
      _fxBypassedLayerIds.addAll(layers.map((layer) => layer.id));
    } else {
      _fxBypassedLayerIds.clear();
    }
    notifyListeners();
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
  /// only (no clip link).
  void importMediaFiles(List<String> paths) {
    addMediaAssets([for (final path in paths) importAudioFile(path)]);
  }

  // --- Guide voice recording (AUDIO-PRO R5) --------------------------------

  /// True while the microphone is live — the record button's state.
  final ValueNotifier<bool> isVoiceRecording = ValueNotifier<bool>(false);

  /// A take the TRANSPORT finished (stop pressed mid-take): the message
  /// the toggle path would have returned, for whoever hosts the snackbar.
  /// Null = finished clean (or nothing to say).
  final ValueNotifier<String?> voiceRecordingNotice =
      ValueNotifier<String?>(null);

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
    var opened = device.open(sampleRate: 48000, channels: 2, deviceIndex: index);
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
  final ValueNotifier<Layer?> voiceRecordPreviewLane =
      ValueNotifier<Layer?>(null);

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
  AudioPeaks? audioPeaksForDisplay(String path) => path == voiceRecordPreviewPath
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
    playback.globalFrameIndexListenable.removeListener(
      _syncVoiceRecordPreview,
    );
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
    bool layerReferences(Layer layer) {
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
    // toggles (SE/art) or are fixed (camera/instruction/attach rows).
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
      LayerKind.art => 'Art Layer',
      LayerKind.se => 'SE Layer',
      LayerKind.instruction => 'Instruction Layer',
      LayerKind.camera => 'Camera Layer',
      LayerKind.folder => 'Folder',
      null => 'No Layer',
    };
  }

  /// Art toggle: animation ⇄ art (BG/BOOK cels behave like animation cels;
  /// only the material differs).
  bool get canToggleTargetLayerArt {
    final targetLayer = _targetLayerForKindToggle;
    return targetLayer != null &&
        !isAttachedLayer(targetLayer) &&
        (targetLayer.kind == LayerKind.animation ||
            targetLayer.kind == LayerKind.art);
  }

  void toggleTargetLayerArt() {
    final targetLayer = _targetLayerForKindToggle;
    if (targetLayer == null || !canToggleTargetLayerArt) {
      return;
    }

    _cutCommandCoordinator.updateLayerKind(
      cutId: requireActiveCut.id,
      layerId: targetLayer.id,
      kind: targetLayer.kind == LayerKind.art
          ? LayerKind.animation
          : LayerKind.art,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  void toggleTargetLayerKind() {
    final targetLayer = _targetLayerForKindToggle;
    if (targetLayer == null) {
      return;
    }

    final nextKind = targetLayer.kind == LayerKind.storyboard
        ? LayerKind.animation
        : LayerKind.storyboard;

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
    if (layer == null ||
        !layerKindHoldsDrawings(layer.kind) ||
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

  bool get isExposureEdgeDragActive => _edgeDragBefore != null;

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
      // SE rows join the selection bulk (UI-R18 #1) — display-local
      // starts only (the storyboard's global-keyed grips stand down).
      if (!blockStartIsGlobal) {
        _captureEdgeBulk(layerId, blockStartIndex, isDrawingBlock: true);
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
    return true;
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
      final display = _rangeLayerById(id);
      final commit = _commitLayerById(id);
      if (display == null || commit == null) {
        continue;
      }
      final starts = _selectionBlockStarts(display, selection);
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

  /// The selection's real (non-ghost) drawing-block start keys, in order.
  List<int> _selectionBlockStarts(
    Layer layer,
    TimelineFrameRangeSelection selection,
  ) => [
    for (final entry in layer.timeline.entries)
      if (entry.key >= selection.startIndex &&
          entry.key < selection.endIndexExclusive &&
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
      dragPreview.value = previews.isEmpty
          ? null
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
  /// the command's execute applies the final result to the repository.
  void endExposureEdgeDrag() {
    final before = _edgeDragBefore;
    final after = _edgeDragAfter;
    final bulkEdits = _edgeDragBulkEdits;
    _edgeDragBefore = null;
    _edgeDragEdge = null;
    _edgeDragBlockStart = null;
    _edgeDragBulkStartsByLayer = null;
    _edgeDragBulkBefore = null;
    _edgeDragBulkEdits = null;
    _edgeDragAfter = null;
    _edgeDragWindow = null;
    dragPreview.value = null;
    if (bulkEdits != null) {
      // The selection covers the same cels after the retime (starts kept).
      _timelineController.commitLayerTimelineDrags(bulkEdits);
      _warmActiveCut();
      notifyListeners();
      return;
    }
    if (before == null) {
      return;
    }

    if (after == null || after == before) {
      return;
    }
    _timelineController.commitLayerTimelineDrag(before: before, after: after);
    _warmActiveCut();
    notifyListeners();
  }

  // --- Storyboard cut-trim edge drags --------------------------------------

  Map<CutId, int>? _cutTrimBeforeDurations;
  Map<CutId, int>? _cutTrimBeforeGaps;
  CutId? _cutTrimCutId;
  CutId? _cutTrimNextCutId;
  TimelineBlockEdge? _cutTrimEdge;

  /// Track cut order + the dragged cut's slot, snapshotted for START-edge
  /// slides (the leftward cascade pushes predecessor gaps, R12-⑦).
  List<CutId>? _cutTrimOrder;
  int? _cutTrimIndex;

  /// Starts a storyboard edge drag on [cutId]'s [edge]. The END edge trims
  /// the duration (growth eats the following gap first); the START edge
  /// TRIMS from the front (R12-B, timeline start-comma parity): the end
  /// stays put, the length changes, and the start's movement adjusts the
  /// leading gaps. Any cut's start may trim, the first one included.
  bool beginCutEdgeDrag({
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
  void updateCutEdgeDrag(int cumulativeDelta) {
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
    if (edge == TimelineBlockEdge.end) {
      final newDuration = math.max(
        1,
        beforeDurations[cutId]! + cumulativeDelta,
      );
      durations[cutId] = newDuration;
      final nextId = _cutTrimNextCutId;
      if (nextId != null) {
        final growth = newDuration - beforeDurations[cutId]!;
        final baseGap = beforeGaps[nextId]!;
        // Growth: consume the gap, then push. Shrink: an attached next
        // cut (gap 0 at drag start) ripples with the boundary; a DETACHED
        // one holds its global position — the gap absorbs the shrink.
        gaps[nextId] = growth > 0
            ? math.max(0, baseGap - growth)
            : (baseGap > 0 ? baseGap - growth : 0);
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
        final moved = math.min(cumulativeDelta, beforeDuration - 1);
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
  void endCutEdgeDrag() {
    final beforeDurations = _cutTrimBeforeDurations;
    final beforeGaps = _cutTrimBeforeGaps;
    final preview = dragPreview.value;
    _cutTrimBeforeDurations = null;
    _cutTrimBeforeGaps = null;
    _cutTrimCutId = null;
    _cutTrimNextCutId = null;
    _cutTrimEdge = null;
    _cutTrimOrder = null;
    _cutTrimIndex = null;
    dragPreview.value = null;
    if (beforeDurations == null || beforeGaps == null) {
      return;
    }

    final previewDurations = preview is CutTrimDragPreview
        ? preview.previewDurations
        : const <CutId, int>{};
    final previewGaps = preview is CutTrimDragPreview
        ? preview.previewGaps
        : const <CutId, int>{};
    final afterDurations = {
      for (final id in beforeDurations.keys)
        id: previewDurations[id] ?? beforeDurations[id]!,
    };
    final afterGaps = {
      for (final id in beforeGaps.keys) id: previewGaps[id] ?? beforeGaps[id]!,
    };
    final changed =
        afterDurations.entries.any(
          (entry) => beforeDurations[entry.key] != entry.value,
        ) ||
        afterGaps.entries.any((entry) => beforeGaps[entry.key] != entry.value);
    if (!changed) {
      return;
    }

    // Fade durability: re-anchor each resized cut's canonical fade to its
    // new duration. cutFadeLengths returns (0, 0) for unkeyed AND for
    // hand-keyed (non-canonical) lanes — both stay untouched.
    final beforeTransforms = <CutId, TransformTrack>{};
    final afterTransforms = <CutId, TransformTrack>{};
    for (final entry in afterDurations.entries) {
      if (entry.value == beforeDurations[entry.key]) {
        continue;
      }
      final cut = cutById(entry.key);
      if (cut == null) {
        continue;
      }
      final lengths = cutFadeLengths(cut);
      if (lengths.fadeInFrames == 0 && lengths.fadeOutFrames == 0) {
        continue;
      }
      final rebuilt = cutTransformWithFade(
        cut.copyWith(duration: entry.value),
        fadeInFrames: lengths.fadeInFrames,
        fadeOutFrames: lengths.fadeOutFrames,
      );
      if (rebuilt == cut.transformTrack) {
        continue;
      }
      beforeTransforms[entry.key] = cut.transformTrack;
      afterTransforms[entry.key] = rebuilt;
    }

    _cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: beforeDurations,
      afterDurations: afterDurations,
      beforeGaps: beforeGaps,
      afterGaps: afterGaps,
      beforeTransforms: beforeTransforms,
      afterTransforms: afterTransforms,
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Drops an in-flight trim preview without touching history (the
  /// repository was never written during the drag).
  void cancelCutEdgeDrag() {
    _cutTrimBeforeDurations = null;
    _cutTrimBeforeGaps = null;
    _cutTrimCutId = null;
    _cutTrimNextCutId = null;
    _cutTrimEdge = null;
    _cutTrimOrder = null;
    _cutTrimIndex = null;
    dragPreview.value = null;
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

  /// The storyboard's selected cut RUN — one track, contiguous, in track
  /// order (the timeline range-selection model applied to cuts). Value-
  /// only view state; a plain tap clears it.
  final ValueNotifier<List<CutId>?> storyboardCutSelection =
      ValueNotifier<List<CutId>?>(null);

  /// A cut-select drag step: anchor/head are CUT ORDINALS on [trackId].
  void updateStoryboardCutSelectionDrag({
    required TrackId trackId,
    required int anchorCutIndex,
    required int headCutIndex,
  }) {
    for (final track in _repository.requireProject().tracks) {
      if (track.id != trackId) {
        continue;
      }
      if (track.cuts.isEmpty) {
        storyboardCutSelection.value = null;
        return;
      }
      final low = math
          .min(anchorCutIndex, headCutIndex)
          .clamp(0, track.cuts.length - 1);
      final high = math
          .max(anchorCutIndex, headCutIndex)
          .clamp(0, track.cuts.length - 1);
      storyboardCutSelection.value = [
        for (var i = low; i <= high; i += 1) track.cuts[i].id,
      ];
      return;
    }
  }

  void clearStoryboardCutSelection() {
    if (storyboardCutSelection.value != null) {
      storyboardCutSelection.value = null;
    }
  }

  /// The selection filtered to cuts that still EXIST (other commands may
  /// have deleted/reordered members since the drag painted it).
  List<CutId> get _liveSelectedCutIds {
    final selection = storyboardCutSelection.value;
    if (selection == null || selection.isEmpty) {
      return const [];
    }
    final existing = <CutId>{
      for (final track in _repository.requireProject().tracks)
        for (final cut in track.cuts) cut.id,
    };
    return [
      for (final id in selection)
        if (existing.contains(id)) id,
    ];
  }

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

  List<CutId>? _cutMoveOrder;
  Map<CutId, int>? _cutMoveBeforeGaps;
  int? _cutMoveIndex;

  /// The selected run's LAST index while a group slide is live (UI-R18
  /// #1: dragging inside the cut selection moves the whole run).
  int? _cutMoveGroupEndIndex;

  /// Starts a whole-block move drag on [cutId]: the cut SLIDES along the
  /// frame axis by adjusting gaps, and pushes neighbors edge-style on
  /// contact — rightward pushes the followers (their gap absorbs first),
  /// leftward pushes the predecessors (each one's own gap absorbs before
  /// the wave reaches the next), clamped when the chain hits frame 0.
  bool beginCutMoveDrag(CutId cutId) {
    final project = _repository.requireProject();
    for (final track in project.tracks) {
      final index = track.cuts.indexWhere((cut) => cut.id == cutId);
      if (index < 0) {
        continue;
      }
      _cutMoveOrder = [for (final cut in track.cuts) cut.id];
      _cutMoveBeforeGaps = {
        for (final cut in track.cuts) cut.id: cut.leadingGapFrames,
      };
      _cutMoveIndex = index;
      _cutMoveGroupEndIndex = null;
      // Dragging inside the cut SELECTION slides the whole run (UI-R18
      // #1): anchor at the run's first cut, compensate past its last.
      final selection = storyboardCutSelection.value;
      if (selection != null && selection.contains(cutId)) {
        final indexes = [for (final id in selection) _cutMoveOrder!.indexOf(id)]
          ..removeWhere((value) => value < 0);
        if (indexes.length > 1) {
          indexes.sort();
          _cutMoveIndex = indexes.first;
          _cutMoveGroupEndIndex = indexes.last;
        }
      }
      return true;
    }
    return false;
  }

  /// Applies the move's cumulative frame delta as a live preview on
  /// [dragPreview] (the repository is NOT touched).
  void updateCutMoveDrag(int cumulativeDelta) {
    final order = _cutMoveOrder;
    final beforeGaps = _cutMoveBeforeGaps;
    final index = _cutMoveIndex;
    if (order == null || beforeGaps == null || index == null) {
      return;
    }
    final gaps = _cutMoveGaps(
      order: order,
      beforeGaps: beforeGaps,
      index: index,
      delta: cumulativeDelta,
      groupEndIndex: _cutMoveGroupEndIndex,
    );
    final changed = gaps.entries.any(
      (entry) => beforeGaps[entry.key] != entry.value,
    );
    dragPreview.value = changed
        ? CutTrimDragPreview(previewDurations: const {}, previewGaps: gaps)
        : null;
  }

  /// The previewed gap map for a move by [delta] (pure — shared by update
  /// and tests). Rightward: the moved cut's gap grows, the follower's gap
  /// absorbs (followers hold still) until spent, then the rest pushes.
  /// Leftward: the moved cut's own gap absorbs first, then each
  /// predecessor's in turn (pushing them left), clamped at the chain's
  /// total slack; the follower's gap grows by the applied movement so
  /// everything after holds still.
  static Map<CutId, int> _cutMoveGaps({
    required List<CutId> order,
    required Map<CutId, int> beforeGaps,
    required int index,
    required int delta,
    int? groupEndIndex,
  }) {
    final gaps = <CutId, int>{};
    // A selected RUN slides as one unit (UI-R18 #1): the first cut's gap
    // carries the delta (the run follows for free — positions are
    // cumulative), the compensation lands past the run's LAST cut.
    final end = groupEndIndex ?? index;
    if (delta > 0) {
      gaps[order[index]] = beforeGaps[order[index]]! + delta;
      if (end + 1 < order.length) {
        final nextId = order[end + 1];
        gaps[nextId] = math.max(0, beforeGaps[nextId]! - delta);
      }
    } else if (delta < 0) {
      var remaining = -delta;
      for (var i = index; i >= 0 && remaining > 0; i -= 1) {
        final id = order[i];
        final take = math.min(remaining, beforeGaps[id]!);
        if (take > 0) {
          gaps[id] = beforeGaps[id]! - take;
          remaining -= take;
        }
      }
      final applied = (-delta) - remaining;
      if (end + 1 < order.length && applied > 0) {
        final nextId = order[end + 1];
        gaps[nextId] = beforeGaps[nextId]! + applied;
      }
    }
    return gaps;
  }

  /// Commits the move as a single undo step (no-op when nothing changed).
  /// Durations are untouched, so no fade re-anchor is needed.
  void endCutMoveDrag() {
    final beforeGaps = _cutMoveBeforeGaps;
    final preview = dragPreview.value;
    _cutMoveOrder = null;
    _cutMoveBeforeGaps = null;
    _cutMoveIndex = null;
    _cutMoveGroupEndIndex = null;
    dragPreview.value = null;
    if (beforeGaps == null) {
      return;
    }
    final previewGaps = preview is CutTrimDragPreview
        ? preview.previewGaps
        : const <CutId, int>{};
    final afterGaps = {
      for (final id in beforeGaps.keys) id: previewGaps[id] ?? beforeGaps[id]!,
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
      beforeTransforms: const {},
      afterTransforms: const {},
    );
    _refreshAfterCutCommand();
    notifyListeners();
  }

  /// Drops an in-flight move preview without touching history.
  void cancelCutMoveDrag() {
    _cutMoveOrder = null;
    _cutMoveBeforeGaps = null;
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
  bool _blockMoveEligible(LayerId layerId) {
    // Synced attach rows own no timing; FREE attach rows move blocks
    // like any drawing layer (UI-R21 #3).
    if (_isSyncedAttachedLayerId(layerId) || isTrackSeLayerId(layerId)) {
      return false;
    }
    final layer = _layerById(layerId);
    return layer != null &&
        layerKindHoldsDrawings(layer.kind) &&
        layer.kind != LayerKind.se;
  }

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
    if (_layerById(layerId) == null) {
      return;
    }
    if (activeLayerId != layerId) {
      // selectLayer first: it drops the OLD selection (a different
      // layer's), then the fresh span lands for the new active layer.
      selectLayer(layerId);
    }
    clearFrameRangeSelection();
    final start = math.max(0, math.min(anchorIndex, headIndex));
    final endExclusive = math.max(anchorIndex, headIndex) + 1;
    if (endExclusive <= start) {
      return;
    }
    final span = transformLaneSpan(laneId, headLaneId ?? laneId);
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
  /// the #10 policy).
  ({Layer layer, TimelineLaneSelection selection})? _laneMoveBefore;
  TransformTrack? _laneMoveShifted;

  /// Starts moving the current lane selection; false when there is none
  /// or it covers no keys on ANY spanned lane (nothing to move).
  bool beginLaneRangeMoveDrag() {
    final selection = laneRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final layer = _layerById(selection.layerId);
    if (layer == null || isAttachedLayer(layer)) {
      return false;
    }
    final keyed = selection.spanLaneIds.any(
      (laneId) => transformLaneKeyFrames(
        layer.transformTrack,
        laneId,
      ).any(selection.contains),
    );
    if (!keyed) {
      return false;
    }
    _laneMoveBefore = (layer: layer, selection: selection);
    _laneMoveShifted = null;

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

      dragPreview.value = null;
      laneRangeSelection.value = before.selection;
      return;
    }
    final shifted = transformTrackWithLaneSpanKeysShifted(
      before.layer.transformTrack,
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

    dragPreview.value = BlockMoveDragPreview(
      previewLayers: {
        before.layer.id: before.layer.copyWith(transformTrack: shifted),
      },
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
    final landed = laneRangeSelection.value;
    _laneMoveBefore = null;
    _laneMoveShifted = null;

    dragPreview.value = null;
    if (before == null || shifted == null) {
      if (before != null) {
        laneRangeSelection.value = before.selection;
      }
      return;
    }
    updateLayerTransformTrack(
      before.layer.id,
      shifted,
      description: 'Move lane keys',
    );
    laneRangeSelection.value = landed;
  }

  /// Drops an in-flight lane-move preview, restoring the selection.
  void cancelLaneRangeMoveDrag() {
    final before = _laneMoveBefore;
    _laneMoveBefore = null;
    _laneMoveShifted = null;

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

  Layer? _rangeMoveSourceBefore;
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
  bool beginFrameRangeMoveDrag([LayerId? grabLayerId]) {
    final selection = frameRangeSelection.value;
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
            offset:
                _commitBlockStart(id, selection.startIndex) -
                selection.startIndex,
          ));
        }
      }
      if (sources.isEmpty &&
          cameraBefore == null &&
          instructionSources.isEmpty) {
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
        frameRangeSelection.value = TimelineFrameRangeSelection(
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
      final offset =
          _commitBlockStart(selection.layerId, selection.startIndex) -
          selection.startIndex;
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
  int? _displayRowDelta(
    List<Layer> rows,
    LayerId anchorId,
    LayerId targetId,
  ) {
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
      cameraMarkerLayer: cameraShifted == null || _rangeMoveCameraLayerId == null
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
      frameRangeSelection.value = TimelineFrameRangeSelection(
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
      final offset =
          _commitBlockStart(sourceId, selection.startIndex) -
          selection.startIndex;
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
      frameRangeSelection.value = selection;
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
        frameRangeSelection.value = TimelineFrameRangeSelection(
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
      // 행이동도 같은 섹션 내 — animation/storyboard/art interchange
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
      frameRangeSelection.value = TimelineFrameRangeSelection(
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
    final landedSelection = frameRangeSelection.value;
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
      frameRangeSelection.value = landedSelection;
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
        frameRangeSelection.value = landedSelection;
        _layerController.selectLayer(instructionRowChange.targetId);
        _warmActiveCut();
        notifyListeners();
      } else {
        frameRangeSelection.value = selection;
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
        frameRangeSelection.value = selection;
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
      frameRangeSelection.value = landedSelection;
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
        frameRangeSelection.value = selection;
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
      frameRangeSelection.value = landedSelection;
      _warmActiveCut();
      notifyListeners();
      return;
    }
    if (source == null || selection == null) {
      return;
    }
    if (plan == null) {
      frameRangeSelection.value = selection;
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
    frameRangeSelection.value = landedSelection;
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
      frameRangeSelection.value = selection;
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
  /// length input), clamped into the room to the next entry / cut end;
  /// null falls back to filling that room (legacy behavior).
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
    final available = remaining < 1 ? 1 : remaining;
    _frameSequence += 1;
    _timelineController.createDrawingFrameForLayer(
      layerId: layer.id,
      frameId: FrameId(_nextFrameId(layer.id)),
      length: (lengthFrames ?? available).clamp(1, available),
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
      clearFrameRangeSelection();
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

  /// The selection resolved to real block starts per spanned layer —
  /// in COMMIT keys (track-SE rows map their display starts onto the
  /// global axis, UI-R18 #1); null when there is no selection (or it
  /// holds no real blocks anywhere).
  Map<LayerId, List<int>>? _selectionBlockStartsByLayer() {
    final selection = frameRangeSelection.value;
    if (selection == null) {
      return null;
    }
    final byLayer = <LayerId, List<int>>{};
    for (final id in selection.spanLayerIds) {
      final layer = _rangeLayerById(id);
      if (layer == null) {
        continue;
      }
      final starts = _selectionBlockStarts(layer, selection);
      if (starts.isNotEmpty) {
        byLayer[id] = [
          for (final start in starts) _commitBlockStart(id, start),
        ];
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
    final selectionTargets = _selectionBlockStartsByLayer();
    if (selection != null && selectionTargets != null) {
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
    // Synced attach rows own no timing (free rows retime normally).
    if (layer == null || isSyncedAttachedLayer(layer)) {
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
    final layout = buildStoryboardTimelineLayout(repository.requireProject());
    for (final entry in layout) {
      if (entry.cutId == activeCutId) {
        return TrackFrameAxis(
          layout
              .where((candidate) => candidate.trackId == entry.trackId)
              .toList(growable: false),
        );
      }
    }
    return TrackFrameAxis(layout);
  }

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

  /// Whether the editing playhead sits in a gap (no cut there).
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

  /// Deselects the active cut for a GAP landing (UI-R9 #3): standing in a
  /// gap means NO cut is selected — the timeline/timesheet show their
  /// empty states and the canvas shows the void. QUIET: callers notify
  /// (they batch it with the parking + commit signals). False when no cut
  /// was selected to begin with.
  bool _deselectActiveCutForGap() {
    if (_editingSession.activeCutId == null) {
      return false;
    }
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
  }

  /// THE canonical seek: a global frame in. Inside a cut it selects
  /// cut + local frame; in a GAP it deselects the cut ENTIRELY (UI-R9 #3)
  /// and PARKS there — the stored global addresses the gap exactly,
  /// including the leading gap before the first cut, and the canvas shows
  /// the no-cut void.
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
      _gapGlobalFrame = globalFrame;
      _deselectActiveCutForGap();
      frameSeekCommitted.value += 1;
      notifyListeners();
      return;
    }
    if (local.cutId != activeCutId) {
      selectCut(local.cutId);
    }
    selectFrameIndex(local.localFrame);
  }

  /// Global scrub: rides the cursor path inside the active cut's
  /// territory, falls back to the full seek when the drag crosses into
  /// another cut's. GAP moves ride the cursor path too and park PER MOVE
  /// (UI-R7 #9): the playhead follows the exact gap frame, the canvas
  /// shows the no-cut void DURING the drag, and no committed seek fires
  /// per move (the old full-seek-per-move made gap scrubs crawl and the
  /// release commit wiped the leading-gap parking entirely).
  void scrubGlobalFrame(int globalFrame) {
    if (editingInteractionBusy) {
      return;
    }
    final axis = trackFrameAxis();
    if (axis.isEmpty) {
      return;
    }
    final owner = axis.ownerOf(globalFrame);
    if (axis.isGap(globalFrame)) {
      // Gap moves park PER MOVE (UI-R7 #9) and the FIRST gap entry
      // deselects the cut IMMEDIATELY (UI-R10 #13): the timesheet and
      // timeline empty out live during the drag, not on release
      // (commitFrameScrub stays the idempotent backstop).
      _gapGlobalFrame = globalFrame;
      if (_deselectActiveCutForGap()) {
        frameSeekCommitted.value += 1;
        notifyListeners();
      }
      return;
    }
    if (owner == null || owner.cutId != activeCutId) {
      selectGlobalFrame(globalFrame);
      return;
    }
    // Scrubbing back onto the cut un-parks.
    _gapGlobalFrame = null;
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

  // --- Project persistence (P3: the .qap container) -------------------------

  static const QapFileService _qapFileService = QapFileService();

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
    await File(path).parent.create(recursive: true);
    await _qapFileService.save(
      project: _repository.requireProject(),
      brushFrameStore: brushFrameStore,
      filePath: path,
    );
  }

  /// Saves the project + every drawn frame into ONE .qap file (atomic
  /// temp-then-rename write; media stays external with relative paths
  /// recorded for Drive portability). A successful save retires the
  /// autosave sidecar.
  Future<void> saveProjectToFile(String filePath) async {
    final previousSidecar = autosaveSidecarPath;
    // Before serializing: the first save adopts the session's shelf
    // takes into Media/ so the .qap carries the adopted paths.
    final adoptedTakePaths = _adoptShelfTakesForSave(filePath);
    await _qapFileService.save(
      project: _repository.requireProject(),
      brushFrameStore: brushFrameStore,
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

  /// Opens a .qap file, replacing the WHOLE session state: project,
  /// drawings, selection (first cut, frame 0) — and BOTH undo stacks
  /// (loaded state has no history; the load→draw→undo path is pinned by
  /// test). [recoverAs] opens autosave SIDECAR bytes while keeping the
  /// real file as the project path (the recovery flow).
  Future<void> openProjectFromFile(String filePath, {String? recoverAs}) async {
    final result = await _qapFileService.open(filePath: filePath);
    playback.stop();
    _repository.replaceProject(result.project);
    // R22-C: opens land every cel FILE-BACKED — pixels stay in the .qap
    // until a cel is first shown (near-zero RAM for 1500-cut projects).
    brushFrameStore.restoreFromFile(result.cels);
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
  /// A gap-parked release COMMITS the no-cut state (UI-R9 #3): the active
  /// cut deselects and the parking carries the exact position.
  void commitFrameScrub() {
    audioScrubber.onScrubEnd();
    if (frameScrubActive.value) {
      frameScrubActive.value = false;
    }
    if (_gapGlobalFrame != null) {
      _deselectActiveCutForGap();
      frameSeekCommitted.value += 1;
      notifyListeners();
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
