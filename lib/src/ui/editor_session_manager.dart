import 'dart:async' show Timer, unawaited;
import 'dart:collection' show SplayTreeMap;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/foundation.dart';

import '../services/editing/default_cut_helpers.dart'
    show createDefaultCut, defaultCutCanvasSize;
import '../services/editing/default_layer_helpers.dart';
import '../models/import/cut_folder_parse.dart';
import '../models/import/tvpp_convert.dart';
import '../models/import/tvpp_parse.dart';
import '../services/cel_source_effect_pass.dart';
import '../services/commands/import_media_command.dart';
import '../services/commands/reorder_track_command.dart';
import '../services/commands/toggle_id_in_set_command.dart';
import '../services/import/media_identity_reader.dart';
import '../services/media/media_fingerprints.dart';
import '../services/persistence/media_blob_codec.dart';
import '../services/persistence/media_staging_store.dart';
import '../services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32, parseAnicelZipLayoutFile;
import '../services/media/media_byte_source.dart';
import '../services/media/project_media_sources.dart';
import '../services/import/media_import_planner.dart';
import '../services/import/psd_expand_import.dart';
import '../services/import/raster_cel_import.dart';
import '../services/import/tvp_import_planner.dart';
import '../services/import/tvpp_raster_decoder.dart';
import '../services/pdf/pdf_render_service.dart';
import '../services/project_lookup.dart'
    show
        cutIdOfLayer,
        projectArchivedMediaPaths,
        projectAudioSourcePaths,
        requireLayerAnywhere;
import '../models/app_language.dart';
// The six settings stores are injected THROUGH this class into
// [EditorAppSettings], so their types stay in this file's constructor
// signature even though nothing here reads them.
import '../services/persistence/app_language_settings_store.dart';
import '../services/persistence/app_accent_settings_store.dart';
import '../services/persistence/app_ui_scale_store.dart';
import '../services/persistence/app_workspace_colors_store.dart';
import '../services/persistence/app_input_settings_store.dart';
import '../services/diagnostics/memory_black_box.dart';
import '../services/persistence/app_save_settings.dart';
import '../services/persistence/app_save_settings_store.dart';
import '../services/persistence/audio_sync_settings_store.dart';
import 'brush/brush_tool_state.dart' show CanvasTool;
import '../models/app_input_settings.dart';
import 'session/drags/audio_clip_offset_drag.dart';
import 'session/drags/cut_move_drag.dart';
import 'session/drags/drawing_block_move_drag.dart';
import 'session/drags/lane_range_move_drag.dart';
import 'session/drags/movie_end_drag.dart';
import 'session/attach_fx_confirm.dart';
import 'session/drags/row_order_drag.dart';
import 'session/drags/run_frames_add_drag.dart';
import 'session/drags/transition_edge_drag.dart';
import 'session/editor_app_settings.dart';
import 'session/editor_voice_recording.dart';
import '../models/app_accents.dart';
import '../services/editing/active_cut_helpers.dart';
import '../services/editing/editing_session_state.dart';
import '../services/editing/layer_standing_after_change.dart';
import '../controllers/layer_controller.dart';
import '../controllers/timeline_controller.dart';
import '../models/attached_layer_mount.dart';
import '../models/attached_layer_resolve.dart';
import '../models/attached_mode.dart';
import '../models/attached_placement.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/tile_coord.dart';
import '../models/audio_clip.dart';
import '../models/brush_frame_key.dart';
import '../models/conte/conte_ink_keys.dart';
import '../models/envelope/cut_envelope_ink_keys.dart';
import '../models/camera_instruction.dart';
import '../models/camera_pose.dart';
import '../models/canvas_point.dart';
import '../models/canvas_resize_anchor.dart';
import '../models/canvas_size.dart';
import '../models/track_se_migration.dart';
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
import '../models/pixel_verb_subject.dart';
import '../services/brush_frame_editing_coordinator.dart';
import '../services/canvas_selection_region.dart';
import '../services/cel_pixel_overwrite.dart';
import '../services/cel_pixel_region.dart';
import '../services/commands/cel_pixel_overwrite_command.dart';
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
import '../models/project_id.dart';
import '../models/project_frame_rate.dart';
import '../models/row_block_shift.dart';
import '../models/property_track.dart';
import '../models/range_snap.dart';
import '../models/se_name_tag.dart';
import '../models/storyboard_coverage.dart';
import '../models/text_cel_style.dart';
import '../models/timeline_coverage.dart';
import '../models/timeline_empty_gaps.dart';
import '../models/flip_column_step.dart';
import '../models/timeline_exposure.dart';
import '../services/editing/cut_duplicate_helpers.dart'
    show duplicateFrameContent;
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
import '../services/layer_pose_paint.dart';
import '../core/dev_profile.dart';
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
import '../models/storyboard_timeline_layout.dart';
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
import '../services/commands/update_project_camera_size_command.dart';
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
    show anicelConformEntryNames, projectMediaPaths, remapProjectMediaPaths;
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
import 'timeline/timeline_row_span_resolver.dart' show resolveSelectionSpanRows;
import 'timeline/timeline_current_row.dart' show currentRowIsInsideGroup;
import 'timeline/layer_label_controls.dart' show layerKindShowsBlendControl;
import 'timeline/layer_timeline_display_adapter.dart'
    show horizontalLayerDisplayOrder;
import 'timeline/timeline_cell_exposure_state.dart';
import 'timeline/timeline_instruction_row_visual.dart'
    show instructionCellExposureState;
import 'timeline/timeline_drag_preview.dart';
import 'timeline/timeline_section_policy.dart';
import 'timeline/effect_lane_editing.dart'
    show
        effectLaneKeyFrames,
        effectsWithAdded,
        effectsWithEnabledToggled,
        effectsWithGroupReset,
        effectsWithLaneKeyRemoved,
        effectsWithLaneKeyToggled,
        effectsWithLaneRangeNamed,
        effectsWithRemoved;
import 'timeline/effect_lane_policy.dart'
    show effectLaneDisplayOrder, parseEffectLaneId;
import 'timeline/transform_lane_editing.dart'
    show
        transformLaneKeyFrames,
        transformTrackWithGroupReset,
        transformTrackWithLaneKeyRemoved,
        transformTrackWithLaneKeyToggled,
        transformTrackWithLaneRangeNamed;
import 'timeline/se_name_tag_lane_policy.dart'
    show seNameTagGroupLaneId, seNameTagLaneDisplayOrder;
import 'timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane, transformLaneDisplayOrder, transformLaneSpan;

part 'session/frame_range_move_drag.dart';
part 'session/edge_drag.dart';
part 'session/movie_end_drag.dart';
part 'session/folder_bands.dart';
part 'session/visibility_solo.dart';
part 'session/text_cel_bakes.dart';
part 'session/transitions.dart';
part 'session/camera.dart';
part 'session/frame_scrub.dart';
part 'session/row_selection.dart';
part 'session/layer_row_drag.dart';
part 'session/lane_range_move_drag.dart';
part 'session/instructions.dart';
part 'session/onion_skin.dart';
part 'session/effects_and_fx.dart';
part 'session/lane_verbs.dart';
part 'session/auto_frame_for_stroke.dart';
part 'session/track_se_display.dart';
part 'session/storyboard_cursor.dart';
part 'session/storyboard_rows.dart';
part 'session/frame_clipboard.dart';
part 'session/playback_cache_budget.dart';
part 'session/layer_verbs.dart';
part 'session/cut_verbs.dart';
part 'session/range_selections.dart';
part 'session/se_entries.dart';
part 'session/drawing_block_move_drag.dart';
part 'session/run_frames_add_drag.dart';
part 'session/opacity_verbs.dart';
part 'session/layer_marks.dart';
part 'session/exposure_verbs.dart';
part 'session/cell_instances.dart';
part 'session/cell_verbs.dart';
part 'session/folders_and_attachments.dart';
part 'session/project_settings.dart';
part 'session/frame_verbs.dart';
part 'session/standing.dart';
part 'session/cut_move_drag.dart';

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
    MediaStagingStore? mediaStagingStore,
    AppLanguageSettingsStore? languageSettingsStore,
    AppAccentSettingsStore? accentSettingsStore,
    AppInputSettingsStore? inputSettingsStore,
    AppSaveSettingsStore? saveSettingsStore,
    AudioSyncSettingsStore? audioSyncSettingsStore,
    AppWorkspaceColorsStore? workspaceColorsStore,
    AppUiScaleStore? uiScaleStore,
  }) : _editingSession = EditingSessionState.forProject(initialProject),
       _injectedAudioConformStore = audioConformStore,
       _injectedMediaStagingStore = mediaStagingStore,
       _appSettings = EditorAppSettings(
         languageSettingsStore: languageSettingsStore,
         accentSettingsStore: accentSettingsStore,
         workspaceColorsStore: workspaceColorsStore,
         inputSettingsStore: inputSettingsStore,
         saveSettingsStore: saveSettingsStore,
         audioSyncSettingsStore: audioSyncSettingsStore,
         uiScaleStore: uiScaleStore,
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
    // 🚨And the THIRD: any pixel edit at all. The crossing detector above
    // asks whether the store HOLDS a surface for the cel, not whether that
    // surface has ink in it — so 픽셀 비우기 leaves an all-transparent
    // surface, `has == had`, and it never bumps. The block went on showing
    // 「그려짐」 for a cel with nothing in it (유저 2026-08-27: 「블록도
    // 반영안되는데」), because the tint's own revision never moved and the
    // painter's repaint gating had no reason to re-ask.
    //
    // ⚠️This fires as often as the user draws — but the timeline host ALSO
    // merges `celPixelRevision` into its frame-ready signal, so the rebuild
    // it costs is one that was already happening; what changes is that the
    // tint re-reads inside it instead of serving a stale answer.
    brushFrameStore.celPixelRevision.addListener(_bumpCelTintRevision);
    // Text cel projections follow the model through EVERY mutation path
    // (edit/undo/redo/paste/duplicate/link) — one history listener, the
    // sweep re-renders whatever went stale (R5).
    _historyManager.addListener(_textCelBakes.scheduleTextCelBakeSweep);
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

  /// R11: the chrome's scale. Reading it is [AppUiScale.value], app-wide
  /// like the accents — this is only the write half.
  void setUiScale(double scale) => _appSettings.setUiScale(scale);

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

  // ── the project settings: their own object ──────────────────────────
  //
  // A collaborator (session/project_settings.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _ProjectSettings _projectSettings = _ProjectSettings(this);

  void setProjectBackdrop(int argb) =>
      _projectSettings.setProjectBackdrop(argb);
  void setProjectPasteboardMargin(double margin) =>
      _projectSettings.setProjectPasteboardMargin(margin);
  void setPasteboardColor(int argb) =>
      _projectSettings.setPasteboardColor(argb);
  ProjectFrameRate get projectFrameRate => _projectSettings.projectFrameRate;
  int get projectFps => _projectSettings.projectFps;
  void setProjectFrameRate(ProjectFrameRate frameRate) =>
      _projectSettings.setProjectFrameRate(frameRate);
  void setProjectFps(int fps) => _projectSettings.setProjectFps(fps);
  ProjectBackground get projectBackground => _projectSettings.projectBackground;
  void setProjectBackground(ProjectBackground background) =>
      _projectSettings.setProjectBackground(background);
  List<StoryboardTimelineLayoutEntry> projectTimelineLayout() =>
      _projectSettings.projectTimelineLayout();

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
    // ⚠️And the undo stack, which was holding the larger share: a MOVE
    // retains a pre AND a post full-canvas surface per confirm.
    _historyManager.respondToMemoryPressure();
    _playbackCache._playbackCacheBudgetEnforcer.respondToMemoryPressure();
    enforcePlaybackCacheBudget();
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

  /// Page-raster bytes each mounted media viewer is holding, by viewer id.
  ///
  /// 🚨**PUSHED, where every other census number is PULLED.** The census
  /// is deliberately addition rather than measurement — it reads counters
  /// the holder already keeps — and it can do that because the session
  /// owns those holders. It does not own these: the viewer's pages live in
  /// a widget State that mounts and unmounts as tabs open and rails fold,
  /// and there are two of them. So the viewers write here instead, and
  /// clear their entry when they go.
  ///
  /// ⛔Without this the panel that answers「어떤항목이 얼만큼」 was silent
  /// about a cache that can hold a quarter of a gigabyte per viewer — the
  /// gap would land in `untrackedBytes` and read as engine overhead.
  final Map<String, int> viewerRasterBytesByViewer = <String, int>{};

  /// What the media viewers hold between them.
  int get viewerRasterBytes {
    var total = 0;
    for (final bytes in viewerRasterBytesByViewer.values) {
      total += bytes;
    }
    return total;
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

  // ── the playback cache budget: its own object ───────────────────────
  //
  // A collaborator (session/playback_cache_budget.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _PlaybackCacheBudget _playbackCache = _PlaybackCacheBudget(this);

  /// A test's budget for the playback caches (see the collaborator).
  @visibleForTesting
  void debugSetPlaybackCacheBudgetBytes(int bytes) =>
      _playbackCache._debugMaxBytes = bytes;

  int get playbackCacheByteBudget => _playbackCache.playbackCacheByteBudget;
  void enforcePlaybackCacheBudget() =>
      _playbackCache.enforcePlaybackCacheBudget();
  List<PlaybackProtectedRange> debugPlaybackProtectedRanges() =>
      _playbackCache.debugPlaybackProtectedRanges();
  bool isPlaybackFrameReady(int frameIndex) =>
      _playbackCache.isPlaybackFrameReady(frameIndex);
  bool isPlaybackFrameReadyForCut(Cut cut, int frameIndex) =>
      _playbackCache.isPlaybackFrameReadyForCut(cut, frameIndex);

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
    resolveProject: _repository.requireProject,
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

  /// ⚠️`void` and `async`: the playback controller does not wait for this,
  /// but the BODY's own order still matters — the take has to have landed
  /// before the cut selection below runs, or the two commands reach the
  /// undo history in whichever order the isolate happened to finish in.
  Future<void> _onPlaybackStopped(PlaybackPosition lastPosition) async {
    // Transport stop finishes a rolling take (REC1-B): record = play +
    // capture, so ending one ends the other. The result message goes out
    // on the notice channel — this path has no button to return through.
    if (isVoiceRecording.value) {
      voiceRecordingNotice.value = await stopVoiceRecordingAndPlace();
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
  /// ⚠️`void` and `async` for the same reason as [_onPlaybackStopped].
  Future<void> _onPlaybackStoppedInGap(int globalFrame) async {
    // The gap-stop twin of _onPlaybackStopped's take finish: a lane is
    // cut-independent, so a take may legitimately end over a gap.
    if (isVoiceRecording.value) {
      voiceRecordingNotice.value = await stopVoiceRecordingAndPlace();
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
    _clipboard._copiedFrame = null;
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

  // ── the frame clipboard: its own object, in its own file ────────────
  //
  // A collaborator (session/frame_clipboard.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _FrameClipboard _clipboard = _FrameClipboard(this);

  // ── the layer verbs: their own object, in their own file ────────────
  //
  // A collaborator (session/layer_verbs.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _LayerVerbs _layerVerbs = _LayerVerbs(this);

  bool get canDeleteActiveLayer => _layerVerbs.canDeleteActiveLayer;
  bool canDeleteLayer(Layer activeLayer) =>
      _layerVerbs.canDeleteLayer(activeLayer);
  void deleteActiveLayer() => _layerVerbs.deleteActiveLayer();
  void deleteSelectedLayers() => _layerVerbs.deleteSelectedLayers();
  void duplicateSelectedLayers() => _layerVerbs.duplicateSelectedLayers();
  void duplicateActiveLayer() => _layerVerbs.duplicateActiveLayer();
  bool get canLinkDuplicateActiveLayer =>
      _layerVerbs.canLinkDuplicateActiveLayer;
  void linkDuplicateActiveLayer() => _layerVerbs.linkDuplicateActiveLayer();
  bool get canUnlinkActiveLayer => _layerVerbs.canUnlinkActiveLayer;
  void unlinkActiveLayer() => _layerVerbs.unlinkActiveLayer();
  bool isLayerLinked(LayerId layerId) => _layerVerbs.isLayerLinked(layerId);
  void renameActiveLayer(String name) => _layerVerbs.renameActiveLayer(name);
  void copyActiveLayer() => _layerVerbs.copyActiveLayer();

  bool get canCopyFrameAtCurrentFrame => _clipboard.canCopyFrameAtCurrentFrame;
  void copyFrameAtCurrentFrame() => _clipboard.copyFrameAtCurrentFrame();
  void pasteLayerFromClipboard() => _clipboard.pasteLayerFromClipboard();
  bool get canPasteLinkedFrameAtCurrentFrame =>
      _clipboard.canPasteLinkedFrameAtCurrentFrame;
  bool get canPasteIndependentFrameAtCurrentFrame =>
      _clipboard.canPasteIndependentFrameAtCurrentFrame;
  void pasteIndependentFrameAtCurrentFrame() =>
      _clipboard.pasteIndependentFrameAtCurrentFrame();
  void pasteLinkedFrameAtCurrentFrame() =>
      _clipboard.pasteLinkedFrameAtCurrentFrame();
  String? get layerClipboardName => _clipboard.layerClipboardName;
  bool get hasLayerClipboard => _clipboard.hasLayerClipboard;
  String get copiedFrameStatusText => _clipboard.copiedFrameStatusText;
  String get linkedFrameUsesStatusText => _clipboard.linkedFrameUsesStatusText;

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
    // F-20, the DELETE half: a row whose layer no longer exists is not a
    // deliberate stand anywhere — it is a dangling id. A row that still
    // resolves is left alone, which is what keeps the storyboard's S rows
    // (they resolve through the track) out of this.
    final strandedOwner = _standing._verbRow?.owningLayerId;
    if (strandedOwner != null && _rangeLayerById(strandedOwner) == null) {
      _standing._verbRow = null;
      _standing._timelineRow = null;
      _standing.seatVerbRowOnActiveLayer();
    }
    // A cut switch re-seats the active layer, which is what the drawn row
    // falls back to when nothing is engaged.
    _standing.publishCurrentRow();
    // The window moved, so the part of a track-global lane span this cut
    // can see moved with it. The selection itself is untouched.
    _publishCutLocalLaneRange();
  }

  // Where the user stands (Round 6): cut, row and layer.
  late final _Standing _standing = _Standing(this);

  void selectCut(CutId cutId) => _standing.selectCut(cutId);
  TimelineRowAddress get currentRow => _standing.currentRow;
  void standOnRow(
    TimelineRowAddress row, {
    int? frameIndex,
    int? globalFrameIndex,
    bool takesLayerActive = true,
  }) => _standing.standOnRow(
    row,
    frameIndex: frameIndex,
    globalFrameIndex: globalFrameIndex,
    takesLayerActive: takesLayerActive,
  );
  void selectLayer(LayerId layerId) => _standing.selectLayer(layerId);
  void selectRow(TimelineRowAddress row) => _standing.selectRow(row);
  void handOffCurrentRowOnFold(LayerId layerId, {String? laneId}) =>
      _standing.handOffCurrentRowOnFold(layerId, laneId: laneId);
  void claimTimelineRow() => _standing.claimTimelineRow();

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

  // ── the storyboard rows: their own object, in their own file ────────
  //
  // A collaborator (session/storyboard_rows.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _StoryboardRows _storyboardRows = _StoryboardRows(this);

  void claimStoryboardRow() => _storyboardRows.claimStoryboardRow();
  List<CutId> get storyboardSelectedCutIds =>
      _storyboardRows.storyboardSelectedCutIds;
  void updateStoryboardCutSelectionByFrame({
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TrackId? trackId,
    TimelineRowAddress? headRow,
  }) => _storyboardRows.updateStoryboardCutSelectionByFrame(
    anchorGlobalFrame: anchorGlobalFrame,
    headGlobalFrame: headGlobalFrame,
    trackId: trackId,
    headRow: headRow,
  );
  void clearStoryboardCutSelection() =>
      _storyboardRows.clearStoryboardCutSelection();

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

  // ── the row selection: its own object, in its own file ──────────────
  //
  // A collaborator (session/row_selection.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _RowSelection _rowSelection = _RowSelection(this);

  bool rowIsSelected(TimelineRowAddress row) =>
      _rowSelection.rowIsSelected(row);
  void beginRowSelection(TimelineRowAddress anchor) =>
      _rowSelection.beginRowSelection(anchor);
  void updateRowSelection(List<TimelineDisplayRow> rows, int rowDelta) =>
      _rowSelection.updateRowSelection(rows, rowDelta);
  void endRowSelection() => _rowSelection.endRowSelection();
  void clearRowSelection() => _rowSelection.clearRowSelection();

  // ── the range selections: their own object, in their own file ───────
  //
  // A collaborator (session/range_selections.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _RangeSelections _rangeSelections = _RangeSelections(this);

  void updateFrameRangeSelectionDrag({
    required LayerId layerId,
    required int anchorIndex,
    required int headIndex,
    LayerId? headLayerId,
    String? headLaneId,
    List<TimelineRowAddress> spanRows = const [],
  }) => _rangeSelections.updateFrameRangeSelectionDrag(
    layerId: layerId,
    anchorIndex: anchorIndex,
    headIndex: headIndex,
    headLayerId: headLayerId,
    headLaneId: headLaneId,
    spanRows: spanRows,
  );
  void clearFrameRangeSelection() =>
      _rangeSelections.clearFrameRangeSelection();
  void updateTrackRowRangeSelectionByFrame({
    required LayerId layerId,
    required int anchorGlobalFrame,
    required int headGlobalFrame,
    TimelineRowAddress? headRow,
    TimelineRowAddress? anchorRow,
    List<TimelineRowAddress> spanRows = const [],
  }) => _rangeSelections.updateTrackRowRangeSelectionByFrame(
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
  }) => _rangeSelections.updateLaneRangeSelectionDrag(
    layerId: layerId,
    laneId: laneId,
    anchorIndex: anchorIndex,
    headIndex: headIndex,
    headLaneId: headLaneId,
    spanLaneIds: spanLaneIds,
    framesAreGlobal: framesAreGlobal,
  );
  void clearLaneRangeSelection() => _rangeSelections.clearLaneRangeSelection();
  bool standingInsideSelection(
    TimelineRowAddress row, [
    int? frameIndex,
    bool frameIsGlobal = false,
  ]) =>
      _rangeSelections.standingInsideSelection(row, frameIndex, frameIsGlobal);
  bool get hasAnySelection => _rangeSelections.hasAnySelection;
  void clearAllSelections() => _rangeSelections.clearAllSelections();
  void claimSelection(TimelineSelectionKind kind) =>
      _rangeSelections.claimSelection(kind);
  void revealSelection() => _rangeSelections.revealSelection();
  void beginSelectionInteraction() =>
      _rangeSelections.beginSelectionInteraction();
  void endSelectionInteraction() => _rangeSelections.endSelectionInteraction();

  /// The selected rows that name a LAYER this cut may delete (⑨).
  ///
  /// A row's kind decides what the edit DOES, never whether the row could
  /// be selected (뿌리 A) — so lane rows, track rows and the floors' fixed
  /// rows simply contribute nothing here instead of being kept out of the
  /// selection.
  List<LayerId> deletableSelectedLayerIds() =>
      _selectedLayerIdsWhere(canDeleteLayer);

  /// The selected LAYER rows whose layer passes [keep], in selection order,
  /// once each — the one walk behind [deletableSelectedLayerIds] and
  /// [renameableSelectedLayerIds] (the audit's clone scan, 2026-09-03).
  List<LayerId> _selectedLayerIdsWhere(bool Function(Layer layer) keep) {
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
      if (layer != null && !ids.contains(layer.id) && keep(layer)) {
        ids.add(layer.id);
      }
    }
    return ids;
  }

  /// Whether the artwork carries a marquee, published by whoever owns it.
  bool Function()? canvasHasSelection;

  /// Lets go of the marquee, published by whoever owns it.
  void Function()? clearCanvasSelection;

  /// The live editing coordinator, published by the canvas host.
  ///
  /// 🚨Null before the canvas has built one — a fresh project, a gap parking,
  /// a test that mounts the timeline alone. Every pixel verb asks, and the
  /// buttons dim rather than the press throwing.
  BrushFrameEditingCoordinator? pixelEditingCoordinator;

  /// The marquee on the artwork, published by whoever owns it.
  ///
  /// ⛔A getter, not a copy. The region is a document-level fact that survives
  /// tool switches (`CanvasSelectionCommands.region`), and a snapshot taken
  /// when the toolbar was built would act on a selection the user has since
  /// redrawn.
  CanvasSelectionRegion? Function()? pixelSelectionRegion;

  /// The drawing colour, published by whoever owns the paint tool state.
  ///
  /// ⛔The BAR does not read this. A toolbar button that had to know about
  /// brush colour would be the second place the answer lives; the verb reads
  /// it at the moment of the press, which is also the only moment it is true.
  ///
  /// 🚨Its ALPHA is ignored downstream — RGB only (유저 확정).
  int Function()? pixelBrushColour;

  /// WHICH cels the two PIXEL verbs would act on — see [PixelVerbSubject].
  PixelVerbSubject get pixelVerbSubject {
    if (pixelVerbCellKeys().isEmpty) {
      return PixelVerbSubject.nothing;
    }
    return frameRangeSelection.value == null
        ? PixelVerbSubject.standing
        : PixelVerbSubject.range;
  }

  // ── the cell verbs: their own object, in their own file ─────────────
  //
  // A collaborator (session/cell_verbs.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _CellVerbs _cells = _CellVerbs(this);

  bool get canDeleteCellForSelection => _cells.canDeleteCellForSelection;
  bool get cellSelectionClaimsSubject => _cells.cellSelectionClaimsSubject;
  bool get canDeleteCellAtCurrentFrame => _cells.canDeleteCellAtCurrentFrame;
  void deleteCellAtCurrentFrame() => _cells.deleteCellAtCurrentFrame();
  String get currentCellStatusText => _cells.currentCellStatusText;
  String get compactCellActionText => _cells.compactCellActionText;
  bool get hasActiveNonNegativeCell => _cells.hasActiveNonNegativeCell;
  List<BrushFrameKey> pixelVerbCellKeys() => _cells.pixelVerbCellKeys();
  bool get canRunPixelVerb => _cells.canRunPixelVerb;
  void runPixelVerb(CelPixelVerb verb) => _cells.runPixelVerb(verb);

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
    final row = _storyboardRows._storyboardRow;
    if (row is LayerRowAddress && isTrackOwnedRailLayerId(row.layerId)) {
      return row;
    }
    return TrackRowAddress(selectedTrackId);
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
    if (_storyboardRows.storeStoryboardRow(TrackRowAddress(trackId)) ||
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

  Track get activeTrack {
    final trackId = selectedTrackId;
    return _repository.requireProject().tracks.firstWhere(
      (track) => track.id == trackId,
    );
  }

  // ── the transitions: their own object, in their own file ───────────────
  //
  // A collaborator (session/transitions.dart, a part of this library). The
  // session keeps the public queries and commands as forwarders.
  late final _Transitions _transitions = _Transitions(this);

  List<TransitionSpan> get activeTrackTransitionSpans =>
      _transitions.activeTrackTransitionSpans;
  bool isTrackTransitionLayerId(LayerId layerId) =>
      _transitions.isTrackTransitionLayerId(layerId);
  Layer get trackTransitionDisplayLayer =>
      _transitions.trackTransitionDisplayLayer;
  String? transitionCrossingWarningInCutAt(int projectedStartKey) =>
      _transitions.transitionCrossingWarningInCutAt(projectedStartKey);
  Layer get trackTransitionSheetLayer => _transitions.trackTransitionSheetLayer;
  String? transitionCrossingWarningAtGlobalKey(int globalStartKey) =>
      _transitions.transitionCrossingWarningAtGlobalKey(globalStartKey);
  List<CameraInstructionDef> get transitionInstructionDefs =>
      _transitions.transitionInstructionDefs;
  ({int startFrame, int length})? get transitionSpanCreationOrNull =>
      _transitions.transitionSpanCreationOrNull;
  bool get canCreateTransitionSpanAtPlayhead =>
      _transitions.canCreateTransitionSpanAtPlayhead;
  void createTransitionSpanAtPlayhead() =>
      _transitions.createTransitionSpanAtPlayhead();
  void updateTransitionInstructions(
    Map<int, InstructionEvent> instructions, {
    String description = 'Edit transition',
  }) => _transitions.updateTransitionInstructions(
    instructions,
    description: description,
  );
  CameraInstructionSet get transitionInstructionSet =>
      _transitions.transitionInstructionSet;
  MapEntry<int, InstructionEvent>? transitionSpanAt(int globalFrame) =>
      _transitions.transitionSpanAt(globalFrame);
  void replaceTransitionEventAt(int globalFrame, InstructionEvent event) =>
      _transitions.replaceTransitionEventAt(globalFrame, event);
  void removeTransitionSpanAt(int globalFrame) =>
      _transitions.removeTransitionSpanAt(globalFrame);
  List<TransitionSpan> transitionSpansOfTrack(TrackId trackId) =>
      _transitions.transitionSpansOfTrack(trackId);

  /// The active cut's global start frame on its track (cumulative cut
  /// durations — the storyboard layout's number for this cut).
  int get activeCutGlobalStartFrame =>
      cutGlobalStartFrameIn(activeTrack, _editingSession.activeCutId) ?? 0;

  // ── the track SE display: its own object, in its own file ───────────
  //
  // A collaborator (session/track_se_display.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _TrackSeDisplay _trackSe = _TrackSeDisplay(this);

  TrackSeWindow get trackSeWindow => _trackSe.trackSeWindow;
  bool isTrackSeLayerId(LayerId layerId) => _trackSe.isTrackSeLayerId(layerId);
  bool isTrackOwnedRailLayerId(LayerId layerId) =>
      _trackSe.isTrackOwnedRailLayerId(layerId);
  Layer? trackSeGlobalLayerById(LayerId layerId) =>
      _trackSe.trackSeGlobalLayerById(layerId);
  List<Layer> get trackSeDisplayLayers => _trackSe.trackSeDisplayLayers;
  Set<LayerId> get trackSeSpillInLayerIds => _trackSe.trackSeSpillInLayerIds;

  // ── the SE entries and name tags: their own object ──────────────────
  //
  // A collaborator (session/se_entries.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _SeEntries _seEntries = _SeEntries(this);

  void createSeEntryAtCurrentFrame({
    required String name,
    String? seName,
    int? lengthFrames,
  }) => _seEntries.createSeEntryAtCurrentFrame(
    name: name,
    seName: seName,
    lengthFrames: lengthFrames,
  );
  void updateSelectedSeEntry({required String dialogue, String? seName}) =>
      _seEntries.updateSelectedSeEntry(dialogue: dialogue, seName: seName);
  void updateSeEntryForLayer(
    LayerId layerId,
    FrameId frameId, {
    required String dialogue,
    String? seName,
  }) => _seEntries.updateSeEntryForLayer(
    layerId,
    frameId,
    dialogue: dialogue,
    seName: seName,
  );
  bool get canEditActiveSeNameTag => _seEntries.canEditActiveSeNameTag;
  void setActiveSeNameTag(SeNameTag? tag) => _seEntries.setActiveSeNameTag(tag);
  void setSeNameTagForLayer(LayerId layerId, SeNameTag? tag) =>
      _seEntries.setSeNameTagForLayer(layerId, tag);
  List<ResolvedSeNameTag> seNameTagsForCutFrame(Cut cut, int localFrameIndex) =>
      _seEntries.seNameTagsForCutFrame(cut, localFrameIndex);
  String? get selectedFrameSeName => _seEntries.selectedFrameSeName;

  // `activeSeNameTagDefaultPosition` seeded the placement dialog's x/y
  // fields from a stacked per-row default. Both are gone with R5 #7: a tag
  // has no position of its own, so the SE row's Position lane is the whole
  // answer and there is nothing to seed.

  // ── the folder bands: their own cache, in their own file ───────────────
  //
  // A collaborator (session/folder_bands.dart, a part of this library). The
  // session keeps the public queries as forwarders.
  late final _FolderBands _folderBands = _FolderBands(this);

  Layer folderBandLayerFor(Layer folder) =>
      _folderBands.folderBandLayerFor(folder);
  List<Layer> folderBandMembersOf(LayerId folderId) =>
      _folderBands.folderBandMembersOf(folderId);
  List<({int start, int endExclusive})> folderBandRunsOf(LayerId folderId) =>
      _folderBands.folderBandRunsOf(folderId);

  void _refreshAfterCutCommand({
    LayerId? preferredActiveLayerId,
    int? preferredFrameIndex,
  }) {
    _clipboard._copiedFrame = null;
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
    _solo.syncVisibilitySolo();
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
      followedByCutId: _storyboardRows.nextCutIdInStoryboardOrder(cut.id),
    );
  }

  @override
  void dispose() {
    // First: a bake sweep suspended across an engine await must find the
    // flag set when it resumes — it stops touching the stores and never
    // notifies a disposed ChangeNotifier.
    _disposed = true;
    _textCelBakes._textCelSweepDirty = false;
    brushFrameStore.celContentRevision.removeListener(_bumpCelTintRevision);
    brushFrameStore.celPixelRevision.removeListener(_bumpCelTintRevision);
    brushInputActive.removeListener(_bumpCelTintRevision);
    celTintRevision.dispose();
    currentRowListenable.dispose();
    rowSelection.dispose();
    laneRangeSelection.removeListener(_publishCutLocalLaneRange);
    cutLocalLaneRangeSelection.dispose();
    revealSelectionTick.dispose();
    memoryPressureTicks.dispose();
    _warmDebounce?.cancel();
    cacheInvalidationHub.removeBrushFrameListener(_onBrushFrameInvalidated);
    playback.globalFrameIndexListenable.removeListener(_followPlaybackCut);
    _historyManager.removeListener(_markProjectDirty);
    _historyManager.removeListener(_refreshLiveAudioSchedule);
    _historyManager.removeListener(_textCelBakes.scheduleTextCelBakeSweep);
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
    scrubOutOfTerritory.dispose();
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
  final MediaStagingStore? _injectedMediaStagingStore;

  /// Where 품기 puts the bytes until a save absorbs them.
  ///
  /// 🚨Injectable for the same reason every other store here is: a test
  /// must not write into the real app container.
  late final MediaStagingStore mediaStagingStore =
      _injectedMediaStagingStore ?? MediaStagingStore();

  /// Whether the PROJECT has [poolPath]'s bytes, wherever the file on disk
  /// has got to.
  ///
  /// 🚨★★★**THIS IS WHAT「MISSING」HAS TO MEAN.** An asset whose original
  /// is gone but whose bytes the project holds is not missing — that is
  /// carrying working. Asking only about the ARCHIVE was right until 품기
  /// started staging at import: between the import and the first save the
  /// bytes are in the container and nowhere else, so a carried asset whose
  /// original the user deleted wore a "File missing — relink it" banner
  /// over a file the project had already secured.
  ///
  /// ⛔And the banner is not cosmetic. It feeds the relink hunt, whose
  /// "success" re-keys the asset to a different path — which, for bytes
  /// held under the OLD key, is how you lose them.
  ///
  /// ⚠️Cheap on purpose: a map lookup and a stat. The pool draws a row per
  /// asset and must not open the archive to do it.
  bool projectHoldsMediaBytes(String poolPath) =>
      _mediaEntryNames.containsKey(poolPath) ||
      mediaStagingStore.find(poolPath) != null;

  /// 🚨★★★**EVERY WAY AN ASSET BECOMES CARRIED COMES THROUGH HERE.**
  ///
  /// Carrying means the project holds the bytes from the moment the choice
  /// is made — 유저 2026-08-30: 「품은 순간 데이터를 가지고있고 **불변**
  /// 이었으면좋겠어서」 — and there are FOUR ways to make that choice: the
  /// import window, a folder import, promoting a reference afterwards, and
  /// recording a voice take. Each one used to be free to forget, and three
  /// of them did.
  ///
  /// ⛔Called BEFORE the pool records the asset. A staged copy with no
  /// asset is an orphan the sweep takes; an asset the pool holds whose
  /// bytes were never staged is the old behaviour back, silently — and
  /// silently is how it survived two rounds of this work.
  /// 🚨★★★**AWAIT IT. A DROPPED FUTURE HERE IS THE OLD BUG, SILENTLY.**
  ///
  /// The compression moved into an isolate so a carried movie stops
  /// freezing the app, and that turned this into a `Future`. Nothing in the
  /// analyzer stops a caller from ignoring it — `stageCarriedBytes(paths);`
  /// still compiles inside a `void` method — and a caller that does has put
  /// the registration back in front of the bytes, which is exactly the
  /// state the ⛔ above forbids. That is why the entrances are async now.
  Future<void> stageCarriedBytes(Iterable<String> poolPaths) =>
      mediaStagingStore.stageAll(poolPaths);

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
              resolveByteSource: mediaByteSourceFor,
              resolveCarriedConform: _carriedConformFor,
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
        // The store answers when a conform lands or is let go, which is
        // exactly when the pool's size column stops being true.
        ..addListener(_invalidateConformStoredBytes)
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

  /// What a save should do about conforms — the bytes to write and the
  /// entry names this project may hold — at the CURRENT audio settings.
  ///
  /// ⚠️Resolved fresh at every save, like the media sources beside it: the
  /// archive half is a byte range, and offsets belong to one layout.
  ProjectConforms _conformsToStore() {
    final project = _repository.requireProject();
    return projectConformSources(
      project: project,
      conformBasePathFor: _conformPathFor,
      projectFilePath: _projectFilePath,
      sampleRate: project.audioSampleRate,
      speedNumerator: project.audioSpeedNumerator,
      speedDenominator: project.audioSpeedDenominator,
    );
  }

  /// The conform this project CARRIES for [sourcePath], as a range inside
  /// the `.anicel`, or null when it carries none.
  ///
  /// 🚨★★★**WHAT `conform-in-project` = always BUYS** (유저 2026-08-30).
  /// Open the project on another machine, or after the cache was emptied,
  /// and the pipeline copies this out instead of decoding and resampling
  /// every sound first. An hour of dialogue is the difference between
  /// playing now and playing after a full pass over 55MB of compressed
  /// audio.
  ///
  /// ⚠️Resolved per call and never held — the same rule
  /// [mediaByteSourceFor] follows: a compaction moves every byte, and a
  /// range kept from before would read whatever landed on those offsets.
  ///
  /// ⛔The entry name is DERIVED, not recorded. Media records its entry
  /// names because an old project may have been written under a different
  /// rule; a conform is younger than that problem, and recording a second
  /// map would be a second thing to keep in step.
  MediaByteSource? _carriedConformFor(String sourcePath) {
    final archivePath = _projectFilePath;
    if (archivePath == null) {
      return null;
    }
    final project = _repository.requireProject();
    try {
      final layout = parseAnicelZipLayoutFile(archivePath);
      // Only the names the CURRENT settings produce. A conform carried at
      // another rate is not a conform for this project any more, and the
      // next save is what takes it away.
      for (final name in anicelConformEntryNames(
        sourcePath,
        sampleRate: project.audioSampleRate,
        speedNumerator: project.audioSpeedNumerator,
        speedDenominator: project.audioSpeedDenominator,
      )) {
        final entry = layout.entryNamed(name);
        if (entry != null) {
          return MediaArchiveBytes(
            archivePath: archivePath,
            dataOffset: entry.dataOffset,
            length: entry.length,
            entryCrc32: entry.crc32,
            framed: mediaEntryIsFramed(name),
          );
        }
      }
    } on Object {
      // A torn or momentarily unreadable archive: the decode below still
      // works, which is the entire fallback this optimisation stands on.
    }
    return null;
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

  /// Every row the ACTIVE cut SHOWS — the cut's own layers plus the
  /// TRACK-owned rows that join them, which is exactly what
  /// `LayerController.layers` composes.
  ///
  /// 🚨H17 (유저 2026-08-22): 「**트랜지션 레이어에 서있을때 엔드라인 드래그로
  /// 조작하면 액티브레이어가 액션레이어로 바뀜.** 또 통일안하고 멋대로 이상한
  /// 규칙 만들어낸흔적」.
  ///
  /// ⛔[_activeCutHasLayer] USED TO RE-DERIVE THIS MEMBERSHIP BY KIND, and
  /// had been told about only two of the three sources: the cut's layers,
  /// and track-SE rows (a hand-written arm added by W4). The track
  /// TRANSITION row joined the composed list later 「on the same terms as
  /// the SE rows」 and this predicate was never told — so standing on it and
  /// committing ANY cut command answered "that layer is gone", the rebuilt
  /// controller started with no preference, and `_activeLayerId ??=
  /// layers.first.id` handed the active row to the bottom of the raw list:
  /// the action layer.
  ///
  /// 🧪Measured, not reasoned: the transition row is still in `layers` the
  /// whole time, and `currentRow` never moved — only the ACTIVE layer did,
  /// and only for this one row kind (camera and SE both survive the same
  /// drag). A fourth row kind must join HERE, next to the composition it
  /// mirrors, rather than buying another arm on a predicate.
  List<Layer> get activeCutRowLayers {
    final cut = activeCutOrNull;
    if (cut == null) {
      return const [];
    }
    return [
      ...cut.layers,
      ...trackSeDisplayLayers,
      trackTransitionDisplayLayer,
    ];
  }

  bool _activeCutHasLayer(LayerId? layerId) {
    if (layerId == null) {
      return false;
    }
    return activeCutRowLayers.any((layer) => layer.id == layerId);
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
      if (axis.cutsIn(range.startFrame, range.endFrameExclusive).isNotEmpty) {
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

  // ── the cut verbs: their own object, in their own file ──────────────
  //
  // A collaborator (session/cut_verbs.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _CutVerbs _cutVerbs = _CutVerbs(this);

  void deleteActiveCut() => _cutVerbs.deleteActiveCut();
  bool get canDeleteSelectedCuts => _cutVerbs.canDeleteSelectedCuts;
  void deleteSelectedCuts() => _cutVerbs.deleteSelectedCuts();
  void duplicateActiveCut() => _cutVerbs.duplicateActiveCut();
  void createCut() => _cutVerbs.createCut();
  void renameActiveCut(String newName) => _cutVerbs.renameActiveCut(newName);
  bool get canMoveActiveCutLeft => _cutVerbs.canMoveActiveCutLeft;
  bool get canMoveActiveCutRight => _cutVerbs.canMoveActiveCutRight;
  void moveActiveCutLeft() => _cutVerbs.moveActiveCutLeft();
  void moveActiveCutRight() => _cutVerbs.moveActiveCutRight();
  void createLinkedCutFromActiveCut() =>
      _cutVerbs.createLinkedCutFromActiveCut();
  ConvertToLinkedCutPlan? convertToLinkedCutPreview(CutId targetCutId) =>
      _cutVerbs.convertToLinkedCutPreview(targetCutId);
  List<({CutId id, String name})> get convertToLinkedCutCandidates =>
      _cutVerbs.convertToLinkedCutCandidates;
  ConvertToLinkedCutPreviewData? convertToLinkedCutPreviewData(
    CutId targetCutId,
  ) => _cutVerbs.convertToLinkedCutPreviewData(targetCutId);
  void convertActiveCutToLinked(CutId targetCutId) =>
      _cutVerbs.convertActiveCutToLinked(targetCutId);
  void resizeActiveCutCanvas(
    CanvasSize canvasSize, {
    CanvasResizeAnchor anchor = CanvasResizeAnchor.center,
  }) => _cutVerbs.resizeActiveCutCanvas(canvasSize, anchor: anchor);
  void updateActiveCutNote(String note) => _cutVerbs.updateActiveCutNote(note);
  String? get activeCutNote => _cutVerbs.activeCutNote;
  CutGuides get activeCutGuides => _cutVerbs.activeCutGuides;
  void setActiveCutGuides(CutGuides guides) =>
      _cutVerbs.setActiveCutGuides(guides);
  bool get isActiveCutThumbnailPinnedHere =>
      _cutVerbs.isActiveCutThumbnailPinnedHere;
  void toggleActiveCutThumbnailFrame() =>
      _cutVerbs.toggleActiveCutThumbnailFrame();

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
        span: _transitions.transitionSpanOf(entry),
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

  // --- Camera --------------------------------------------------------------

  // ── the camera: its own object, in its own file ────────────────────────
  //
  // A collaborator (session/camera.dart, a part of this library). The session
  // keeps the public queries and commands as forwarders.
  late final _Camera _camera = _Camera(this);

  CutCamera get activeCutCamera => _camera.activeCutCamera;
  CanvasSize get cameraFrameSize => _camera.cameraFrameSize;
  void setProjectCameraSize(CanvasSize size) =>
      _camera.setProjectCameraSize(size);
  CameraPose cameraPoseAtFrame(int frameIndex) =>
      _camera.cameraPoseAtFrame(frameIndex);
  CameraPose cameraPoseForCut(Cut cut, int frameIndex) =>
      _camera.cameraPoseForCut(cut, frameIndex);
  CameraPose get cameraPoseAtCurrentFrame => _camera.cameraPoseAtCurrentFrame;
  CameraPose? get displayedCameraPose => _camera.displayedCameraPose;
  bool get hasCameraKeyframeAtCurrentFrame =>
      _camera.hasCameraKeyframeAtCurrentFrame;
  void setCameraKeyframeAtCurrentFrame(CameraPose pose) =>
      _camera.setCameraKeyframeAtCurrentFrame(pose);
  void removeCameraKeyframeAtCurrentFrame() =>
      _camera.removeCameraKeyframeAtCurrentFrame();
  void clearActiveCutCamera() => _camera.clearActiveCutCamera();
  void updateActiveCutCameraTrack(
    TransformTrack track, {
    String description = 'Edit camera keyframes',
  }) => _camera.updateActiveCutCameraTrack(track, description: description);
  bool get isCameraLayerActive => _camera.isCameraLayerActive;
  BrushEditorSelection? get cameraBackdropSelection =>
      _camera.cameraBackdropSelection;
  CameraInstructionSet get cameraInstructionSet => _camera.cameraInstructionSet;
  void updateCameraInstructionSet(CameraInstructionSet instructionSet) =>
      _camera.updateCameraInstructionSet(instructionSet);
  double get cameraFrameAspect => _camera.cameraFrameAspect;
  TransformTrack? get activeCutCameraTrack => _camera.activeCutCameraTrack;

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
  ({
    List<CanvasLayerStackNode> nodes,
    double activeLayerOpacity,
    List<ResolvedLayerEffect> activeSourceEffects,
  })
  get editingCanvasStack {
    final cut = activeCutOrNull;
    final activeLayerId = this.activeLayerId;
    if (cut == null) {
      return (
        nodes: const <CanvasLayerStackNode>[],
        activeLayerOpacity: 1.0,
        activeSourceEffects: const <ResolvedLayerEffect>[],
      );
    }

    final frameIndex = _timelineController.currentFrameIndex;
    var activeLayerOpacity = 1.0;
    // 🚨THE ACTIVE ROW'S CPU HALF, CARRIED OUT WITH THE OPACITY.
    //
    // The row you are DRAWING on is painted tile by tile by the brush
    // panel's own painter, which never sees a CutFrameCompositeLayer and
    // never asks the image cache — the two places the colour keys are
    // applied. Without this the keyed colour comes back the moment you
    // stand on the row, and goes again when you step off: exactly the
    // "발신자에 따라 길이 갈렸다" shape #1280 was about.
    //
    // It is resolved HERE because this is where the active node's chain is
    // already resolved — asking a second time somewhere else is how the
    // panel and the stack would come to disagree.
    var activeSourceEffects = const <ResolvedLayerEffect>[];
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
                : _opacity.stackLayerOpacity(
                    entry.layer,
                    stackCut.layers,
                    frameIndex,
                  );
            activeSourceEffects = splitSourceEffects(entry.effects).source;
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
      activeLayerOpacity = _opacity.stackLayerOpacity(
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
      activeSourceEffects = splitSourceEffects(
        resolveLayerEffectsAt(
          effects: activeFxCarrier.effects,
          frameIndex: frameIndex,
        ),
      ).source;
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
      activeSourceEffects: activeSourceEffects,
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

  // ── the opacity verbs: their own object, in their own file ──────────
  //
  // A collaborator (session/opacity_verbs.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _OpacityVerbs _opacity = _OpacityVerbs(this);

  double activeCutEditingFadeOpacity({int? frameIndex}) =>
      _opacity.activeCutEditingFadeOpacity(frameIndex: frameIndex);
  double trackStaticOpacity(TrackId trackId) =>
      _opacity.trackStaticOpacity(trackId);
  double trackStaticOpacityForCut(CutId cutId) =>
      _opacity.trackStaticOpacityForCut(cutId);
  void previewTrackOpacity(TrackId trackId, double opacity) =>
      _opacity.previewTrackOpacity(trackId, opacity);
  void commitTrackOpacity(TrackId trackId, double opacity) =>
      _opacity.commitTrackOpacity(trackId, opacity);
  void setLayerOpacity({required LayerId layerId, required double opacity}) =>
      _opacity.setLayerOpacity(layerId: layerId, opacity: opacity);
  void previewLayerOpacity(LayerId layerId, double opacity) =>
      _opacity.previewLayerOpacity(layerId, opacity);
  void commitLayerOpacity(LayerId layerId, double opacity) =>
      _opacity.commitLayerOpacity(layerId, opacity);
  void previewLayersOpacity(Set<LayerId> layerIds, double opacity) =>
      _opacity.previewLayersOpacity(layerIds, opacity);
  void commitLayersOpacity(Set<LayerId> layerIds, double opacity) =>
      _opacity.commitLayersOpacity(layerIds, opacity);
  void resetAllLayersOpacity() => _opacity.resetAllLayersOpacity();
  void setAllLayersOpacity(double opacity) =>
      _opacity.setAllLayersOpacity(opacity);

  // The frame verbs (Round 6): the playhead's frame and what stands there.
  late final _FrameVerbs _frameVerbs = _FrameVerbs(this);

  LayerPoseSample? layerCanvasPoseSample(LayerId layerId) =>
      _frameVerbs.layerCanvasPoseSample(layerId);
  Frame? get selectedFrame => _frameVerbs.selectedFrame;
  bool get canCreateDrawingAtCurrentFrame =>
      _frameVerbs.canCreateDrawingAtCurrentFrame;
  bool get canDuplicateActiveBlock => _frameVerbs.canDuplicateActiveBlock;
  void duplicateActiveBlock({required bool linked}) =>
      _frameVerbs.duplicateActiveBlock(linked: linked);
  bool get canRenameFrameAtCurrentFrame =>
      _frameVerbs.canRenameFrameAtCurrentFrame;
  FrameId? renameSelectedFrame(String name) =>
      _frameVerbs.renameSelectedFrame(name);
  void linkSelectedFrame(FrameId targetFrameId) =>
      _frameVerbs.linkSelectedFrame(targetFrameId);
  int get currentFrameIndex => _frameVerbs.currentFrameIndex;
  void selectPreviousFrame() => _frameVerbs.selectPreviousFrame();
  void selectNextFrame() => _frameVerbs.selectNextFrame();
  String? frameNameForLayer(Layer layer, int frameIndex) =>
      _frameVerbs.frameNameForLayer(layer, frameIndex);
  int? get selectedEffectiveDuration => _frameVerbs.selectedEffectiveDuration;
  String get currentFrameStatusText => _frameVerbs.currentFrameStatusText;

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

  // ── the effects and the fx switches: their own object ───────────────
  //
  // A collaborator (session/effects_and_fx.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _EffectsAndFx _effectsAndFx = _EffectsAndFx(this);

  List<LayerEffect> trackEffectsForCut(CutId cutId) =>
      _effectsAndFx.trackEffectsForCut(cutId);
  void updateLayerEffects(
    LayerId layerId,
    List<LayerEffect> effects, {
    String description = 'Edit layer effects',
  }) => _effectsAndFx.updateLayerEffects(
    layerId,
    effects,
    description: description,
  );
  bool get canAddEffectToActiveLayer => _effectsAndFx.canAddEffectToActiveLayer;
  void addEffectToActiveLayer(EffectKind kind) =>
      _effectsAndFx.addEffectToActiveLayer(kind);
  bool setEffectKeyName({
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
    required String? name,
  }) => _effectsAndFx.setEffectKeyName(
    layerId: layerId,
    effectId: effectId,
    parameterId: parameterId,
    frameIndex: frameIndex,
    name: name,
  );
  void linkEffectKeyName({
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
    required int frameIndex,
    required String name,
  }) => _effectsAndFx.linkEffectKeyName(
    layerId: layerId,
    effectId: effectId,
    parameterId: parameterId,
    frameIndex: frameIndex,
    name: name,
  );
  void removeEffectFromActiveLayer(EffectId effectId) =>
      _effectsAndFx.removeEffectFromActiveLayer(effectId);
  double layerEffectParameterAtFrame(
    Layer layer,
    EffectId effectId,
    String parameterId,
    int frameIndex,
  ) => _effectsAndFx.layerEffectParameterAtFrame(
    layer,
    effectId,
    parameterId,
    frameIndex,
  );
  void updateTrackEffects(
    TrackId trackId,
    List<LayerEffect> effects, {
    String description = 'Edit track effects',
  }) => _effectsAndFx.updateTrackEffects(
    trackId,
    effects,
    description: description,
  );
  void addEffectToTrack(TrackId trackId, EffectKind kind) =>
      _effectsAndFx.addEffectToTrack(trackId, kind);
  void removeEffectFromTrack(TrackId trackId, EffectId effectId) =>
      _effectsAndFx.removeEffectFromTrack(trackId, effectId);
  bool resetTrackEffectGroup(TrackId trackId, String headerLaneId) =>
      _effectsAndFx.resetTrackEffectGroup(trackId, headerLaneId);
  void toggleTrackEffectEnabled(TrackId trackId, EffectId effectId) =>
      _effectsAndFx.toggleTrackEffectEnabled(trackId, effectId);
  double trackEffectParameterAtFrame(
    Track track,
    EffectId effectId,
    String parameterId,
    int frameIndex,
  ) => _effectsAndFx.trackEffectParameterAtFrame(
    track,
    effectId,
    parameterId,
    frameIndex,
  );
  LayerFxState layerFxState(LayerId layerId) =>
      _effectsAndFx.layerFxState(layerId);
  bool isLayerFxEnabled(LayerId layerId) =>
      _effectsAndFx.isLayerFxEnabled(layerId);
  bool isLayerTransformFxEnabled(LayerId layerId) =>
      _effectsAndFx.isLayerTransformFxEnabled(layerId);
  void toggleLayerFx(LayerId layerId) => _effectsAndFx.toggleLayerFx(layerId);
  void toggleLayerTransformFx(LayerId layerId) =>
      _effectsAndFx.toggleLayerTransformFx(layerId);
  bool isCutFxEnabled(CutId cutId) => _effectsAndFx.isCutFxEnabled(cutId);
  LayerFxState trackFxState(TrackId trackId) =>
      _effectsAndFx.trackFxState(trackId);
  void toggleTrackFx(TrackId trackId) => _effectsAndFx.toggleTrackFx(trackId);
  void setAllLayersFxBypassed(bool bypassed) =>
      _effectsAndFx.setAllLayersFxBypassed(bypassed);

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

  // ── the lane verbs: their own object, in their own file ─────────────
  //
  // A collaborator (session/lane_verbs.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _LaneVerbs _laneVerbs = _LaneVerbs(this);

  bool get canNameLaneKeys => _laneVerbs.canNameLaneKeys;
  String? get laneKeyNameForSelection => _laneVerbs.laneKeyNameForSelection;
  bool setLaneKeyNamesForSelection(String? name) =>
      _laneVerbs.setLaneKeyNamesForSelection(name);
  void linkLaneKeyNamesForSelection(String name) =>
      _laneVerbs.linkLaneKeyNamesForSelection(name);
  bool resetLaneGroup(LayerId layerId, String headerLaneId) =>
      _laneVerbs.resetLaneGroup(layerId, headerLaneId);
  bool setTransformKeyName({
    required LayerId layerId,
    required TransformPropertyId property,
    required int frameIndex,
    required String? name,
  }) => _laneVerbs.setTransformKeyName(
    layerId: layerId,
    property: property,
    frameIndex: frameIndex,
    name: name,
  );
  void linkTransformKeyName({
    required LayerId layerId,
    required TransformPropertyId property,
    required int frameIndex,
    required String name,
  }) => _laneVerbs.linkTransformKeyName(
    layerId: layerId,
    property: property,
    frameIndex: frameIndex,
    name: name,
  );

  // The single-key lane naming verbs (`laneKeyName`, `laneHasKeyAt`,
  // `currentLaneKeyAddress`, `setLaneKeyName`, `linkLaneKeyName`) retired
  // when the RANGE form arrived: a single key is the one-frame span at the
  // playhead, so `setLaneKeyNamesForSelection` covers both and leaving the
  // narrow pair here would only invite a future fix to land on the copy
  // nothing calls. The per-FAMILY verbs below (`setEffectKeyName`,
  // `setTransformKeyName`) stay — the range walk builds on them.

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

  /// Writes one row's TRANSFORM switch; one undo step, no-op when unchanged.
  void updateLayerTransformEnabled(
    LayerId layerId, {
    required bool enabled,
    String description = 'Toggle transform FX',
  }) {
    final layer = _effectsAndFx.fxSwitchLayerById(layerId);
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

  // ── visibility solo: its own object, in its own file ───────────────────
  //
  // A collaborator (session/visibility_solo.dart, a part of this library). The
  // session keeps the public toggles as forwarders.
  late final _VisibilitySolo _solo = _VisibilitySolo(this);

  bool get layerVisibilitySoloEnabled => _solo.layerVisibilitySoloEnabled;
  void toggleLayerVisibilitySolo() => _solo.toggleLayerVisibilitySolo();
  void toggleLayerSolo(LayerId layerId) => _solo.toggleLayerSolo(layerId);

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
    final preferredLayerId = preferredLayerAfterLayerListChange(
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
    final preferredLayerId = preferredLayerAfterLayerListChange(
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
  List<LayerId> renameableSelectedLayerIds() =>
      _selectedLayerIdsWhere((layer) => !layerKindIsReadOnlyInCut(layer.kind));

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
        _layerVerbs.addRowAboveActive(newLayerFor);
      case LayerKind.adjustment:
        // R6b: a real row you ADD (unlike a folder), joining the stack
        // above the active layer like every other kind — which is exactly
        // what puts the rows it filters below it.
        _layerVerbs.addRowAboveActive(
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
        _layerVerbs.addRowAboveActive(
          (cut) => createFolderLayer(id: layerId, name: nextFolderName(cut)),
        );
      case LayerKind.camera:
        _layerController.addLayerWithDefaults(layerId: layerId);
    }
    // F-20: the row you just made IS the subject now. Every arm above seats
    // the controller's active layer directly, so none of them went through
    // [selectLayer].
    _standing.seatVerbRowOnActiveLayer();
    notifyListeners();
  }

  // ── folders and attachments: their own object ───────────────────────
  //
  // A collaborator (session/folders_and_attachments.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _FoldersAndAttachments _folders = _FoldersAndAttachments(this);

  bool get canAddAttachedLayerToActive => _folders.canAddAttachedLayerToActive;
  void addAttachedLayer(
    AttachedPlacement placement, {
    AttachedMode mode = AttachedMode.synced,
  }) => _folders.addAttachedLayer(placement, mode: mode);
  bool get canGroupActiveAttachIntoFolder =>
      _folders.canGroupActiveAttachIntoFolder;
  void groupActiveAttachIntoFolder() => _folders.groupActiveAttachIntoFolder();
  bool get canGroupActiveLayerIntoFolder =>
      _folders.canGroupActiveLayerIntoFolder;
  void groupActiveLayerIntoFolder() => _folders.groupActiveLayerIntoFolder();
  void dissolveFolder(LayerId folderId) => _folders.dissolveFolder(folderId);

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

  // ── the layer row drag: its own object, in its own file ─────────────
  //
  // A collaborator (session/layer_row_drag.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _LayerRowDrag _layerRowDrag = _LayerRowDrag(this);

  void beginLayerRowDrag(LayerRowDragSubject subject) =>
      _layerRowDrag.beginLayerRowDrag(subject);
  void updateTrackRowDrag(int slot) => _layerRowDrag.updateTrackRowDrag(slot);
  void updateEffectRowDrag(
    LayerId layerId,
    List<EffectId> displayEffects,
    int slot,
  ) => _layerRowDrag.updateEffectRowDrag(layerId, displayEffects, slot);
  void updateLayerRowDrag(
    List<Layer> displayLayers,
    int slot, {
    LayerId? pointerInRow,
  }) => _layerRowDrag.updateLayerRowDrag(
    displayLayers,
    slot,
    pointerInRow: pointerInRow,
  );
  void updateLayerRowDropOnRow(
    List<Layer> displayLayers,
    int slot,
    LayerId targetId,
  ) => _layerRowDrag.updateLayerRowDropOnRow(displayLayers, slot, targetId);
  void endLayerRowDrag() => _layerRowDrag.endLayerRowDrag();
  void cancelLayerRowDrag() => _layerRowDrag.cancelLayerRowDrag();

  /// The channel the workspace listens on when a drop wants a yes/no.
  ///
  /// 🚨Owned here rather than by a surface: TWO of them end a row drag, and
  /// a dialog raised by whichever happened to be on screen is a second copy
  /// of the sentence waiting to drift ([AttachFxConfirmController]).
  final AttachFxConfirmController attachFxConfirm = AttachFxConfirmController();

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
    // H6: the fold law's selection half, on the FOLDER fold too — every
    // row inside a folder that just shut is off the screen, and the band
    // must not go on drawing over them ([_foldRowSelection]). The active
    // layer's own hand-off below is the standing-row half of the same law.
    if (!wasCollapsed) {
      bool insideThisFolder(LayerId? id) =>
          id != null &&
          cut.layers.isInsideFolder(cut.layers.byId(id)?.folderId, layerId);
      _rowSelection.foldRowSelection(
        vanished: (address) => switch (address) {
          LayerRowAddress(:final layerId) => insideThisFolder(layerId),
          LaneRowAddress(:final layerId) => insideThisFolder(layerId),
          _ => false,
        },
        swallower: LayerRowAddress(layerId),
      );
    }
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

  /// The SE row's track fader + pan (mix state like mute, repo-direct).
  void setLayerAudio({required LayerId layerId, double? gain, double? pan}) {
    _layerController.setLayerAudio(layerId: layerId, gain: gain, pan: pan);
    _refreshLiveAudioSchedule();
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

  /// The master bar's LAST committed value — the bar rests on this, not a
  /// live average (UI-R6 #2).
  double lastMasterOpacity = 1.0;

  /// R27 #6: the legend's BLEND bulk — the master opacity bar's rule for
  /// the mode. Only rows that actually composite take it (the camera and
  /// the sound/instruction rows have no blend), and only rows that would
  /// change are written, so a no-op pick costs nothing.
  void setBlendModeForLayers(Set<LayerId> layerIds, LayerBlendMode mode) {
    // ⛔ONE undo step for one blend pick, however many rows it lands on.
    final targets = [
      for (final layer in layers)
        if (layerIds.contains(layer.id) &&
            layerKindShowsBlendControl(layer.kind) &&
            layer.blendMode != mode)
          layer.id,
    ];
    if (targets.isNotEmpty) {
      _layerController.setLayersBlendMode(layerIds: targets, blendMode: mode);
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
  /// Whether [layerId]'s TRANSFORM group is applied right now.
  ///
  /// 🚨A LIVE READ, like [isLayerEyeOn] and [isLayerOnTimesheet]: a lane row
  /// built at the last frame carries a stale `groupEnabled`, and the rail's
  /// bulk-drag has to spread what the press just set.
  bool isLayerTransformOn(LayerId layerId) => requireLayerAnywhere(
    _repository.requireProject(),
    layerId,
  ).transformEnabled;

  /// Whether [layerId]'s own eye is on RIGHT NOW.
  ///
  /// 🚨A LIVE READ, for the same reason as [isLayerOnTimesheet]: a caller
  /// holding a [Layer] captured at build time reads the value the last frame
  /// had, and the rail's bulk-drag needs the one the press just set.
  bool isLayerEyeOn(LayerId layerId) =>
      requireLayerAnywhere(_repository.requireProject(), layerId).isVisible;

  /// Whether [layerId] is on the timesheet RIGHT NOW.
  ///
  /// 🚨A LIVE READ, and that is the point. A caller holding a [Layer] it
  /// captured at build time reads the value the LAST FRAME had, which stays
  /// wrong for the whole length of a gesture that already toggled it. The
  /// rail's bulk-drag needs the live one: the button under the finger fires
  /// on the DOWN (유저 2026-08-30) and the sweep spreads what that set, so a
  /// snapshot sends it the other way — measured, on one rail in one gesture:
  /// the eye column read live and swept correctly, the sheet column read a
  /// captured layer and swept backwards.
  bool isLayerOnTimesheet(LayerId layerId) =>
      requireLayerAnywhere(_repository.requireProject(), layerId).onTimesheet;

  /// ANYWHERE lookup and a nullable cut (B5③ 2026-08-17): the storyboard
  /// rail reaches this for TRACK fixtures — S rows and the transition row —
  /// whose flag is the layer's own and must flip from a gap too. The cut id
  /// is command bookkeeping the write never reads.
  void toggleLayerTimesheet(LayerId layerId) {
    final layer = requireLayerAnywhere(_repository.requireProject(), layerId);
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

  // ── the layer marks: their own object, in their own file ────────────
  //
  // A collaborator (session/layer_marks.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _LayerMarks _marks = _LayerMarks(this);

  void setLayerMark(LayerId layerId, LayerMark mark) =>
      _marks.setLayerMark(layerId, mark);
  void clearAllLayerMarks() => _marks.clearAllLayerMarks();
  bool get canToggleMarkForSelection => _marks.canToggleMarkForSelection;
  bool get canToggleMarkAtCurrentFrame => _marks.canToggleMarkAtCurrentFrame;
  void toggleMarkAtCurrentFrame() => _marks.toggleMarkAtCurrentFrame();
  bool hasMarkForLayer(Layer layer, int frameIndex) =>
      _marks.hasMarkForLayer(layer, frameIndex);

  // --- Legend bulk commands (R-toolbar round) -----------------------------
  //
  // One legend-flyout action sweeps every eligible layer of the active cut.
  // Semantics mirror the per-row toggles — and since 2026-08-29 that means
  // UNDOABLE for all of them (유저: 「눈을 껏다키든 뭐든 다 언두」). Every
  // bulk action lands as ONE entry, the way sheet/mark/fill-reference
  // already did.

  /// Shows or hides every layer of the active cut.
  void setAllLayersVisibility(bool visible) {
    // ⛔ONE undo step for one legend press — the loop used to make one per
    // row, which is 유저's 「일괄로 버튼 조작하고 언두하면 바꼈던 레이어들
    // 다 한번에 언두되야하는데 안됨」 in the place it is easiest to hit.
    _layerController.setLayersVisible(
      layerIds: [
        for (final layer in layers)
          if (layer.isVisible != visible) layer.id,
      ],
      visible: visible,
    );
    notifyListeners();
  }

  /// Mutes/unmutes every SE layer of the active cut.
  void setAllSeLayersMuted(bool muted) {
    _layerController.setLayersMuted(
      layerIds: [
        for (final layer in layers)
          if (layer.kind == LayerKind.se && layer.muted != muted) layer.id,
      ],
      muted: muted,
    );
    notifyListeners();
  }

  /// Turns the timesheet flag on/off for every eligible layer — one undo.
  /// Track-owned rows join the sweep: SE rows since the SE mark/sheet fix,
  /// and the transition row since D31 gave its flag a printed column —
  /// the flag commands resolve through the anywhere lookup.
  void setAllLayersOnTimesheet(bool onTimesheet) {
    final cut = activeCutOrNull;
    if (cut == null) {
      return;
    }
    final cutId = cut.id;
    final commands = <Command>[
      for (final layer in [
        ...cut.layers,
        ...activeTrack.seLayers,
        activeTrack.transitionLayer,
      ])
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

  // ── the instructions: their own object, in their own file ───────────
  //
  // A collaborator (session/instructions.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _Instructions _instructions = _Instructions(this);

  void updateLayerInstructions(
    LayerId layerId,
    Map<int, InstructionEvent> instructions, {
    String description = 'Edit instructions',
  }) => _instructions.updateLayerInstructions(
    layerId,
    instructions,
    description: description,
  );
  MapEntry<int, InstructionEvent>? instructionSpanAt(
    LayerId layerId,
    int frameIndex,
  ) => _instructions.instructionSpanAt(layerId, frameIndex);
  void createDefaultInstructionEventAtCurrentFrame() =>
      _instructions.createDefaultInstructionEventAtCurrentFrame();
  void upsertInstructionEventAt(
    LayerId layerId,
    int frameIndex,
    InstructionEvent event, {
    int? createLengthFrames,
  }) => _instructions.upsertInstructionEventAt(
    layerId,
    frameIndex,
    event,
    createLengthFrames: createLengthFrames,
  );
  void removeInstructionEventAt(LayerId layerId, int frameIndex) =>
      _instructions.removeInstructionEventAt(layerId, frameIndex);

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
  // The second collaborator (session/edge_drag.dart, a part of this library):
  // the exposure, cut and transition edge drags with their snapshots. The
  // session keeps the public entry points as forwarders.
  late final _EdgeDrag _edgeDrag = _EdgeDrag(this);

  bool beginExposureEdgeDrag({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineBlockEdge edge,
    bool blockStartIsGlobal = false,
  }) => _edgeDrag.beginExposureEdgeDrag(
    layerId: layerId,
    blockStartIndex: blockStartIndex,
    edge: edge,
    blockStartIsGlobal: blockStartIsGlobal,
  );
  void updateExposureEdgeDrag(int cumulativeDelta) =>
      _edgeDrag.updateExposureEdgeDrag(cumulativeDelta);
  void endExposureEdgeDrag() => _edgeDrag.endExposureEdgeDrag();
  void cancelExposureEdgeDrag() => _edgeDrag.cancelExposureEdgeDrag();
  bool beginCutEdgeDrag({
    required CutId cutId,
    required TimelineBlockEdge edge,
    int panelIndex = 0,
  }) => _edgeDrag.beginCutEdgeDrag(
    cutId: cutId,
    edge: edge,
    panelIndex: panelIndex,
  );
  void updateCutEdgeDrag(int cumulativeDelta) =>
      _edgeDrag.updateCutEdgeDrag(cumulativeDelta);
  void endCutEdgeDrag() => _edgeDrag.endCutEdgeDrag();
  void cancelCutEdgeDrag() => _edgeDrag.cancelCutEdgeDrag();
  bool beginTransitionEdgeDrag({
    required int spanStartIndex,
    required TimelineBlockEdge edge,
    LayerId? layerId,
  }) => _edgeDrag.beginTransitionEdgeDrag(
    spanStartIndex: spanStartIndex,
    edge: edge,
    layerId: layerId,
  );
  void updateTransitionEdgeDrag(int cumulativeDelta) =>
      _edgeDrag.updateTransitionEdgeDrag(cumulativeDelta);
  void endTransitionEdgeDrag() => _edgeDrag.endTransitionEdgeDrag();
  void cancelTransitionEdgeDrag() => _edgeDrag.cancelTransitionEdgeDrag();
  bool beginStoryboardCommaDrag({
    required CutId cutId,
    required int blockStartIndex,
  }) => _edgeDrag.beginStoryboardCommaDrag(
    cutId: cutId,
    blockStartIndex: blockStartIndex,
  );
  void setCommaForStoryboardCursor(int comma) =>
      _edgeDrag.setCommaForStoryboardCursor(comma);

  /// The transition row as the in-flight edge drag would leave it — the
  /// strip renders THIS while a grip is held, so the mark follows the hand
  /// instead of jumping on release. Null when no drag is in flight.
  final ValueNotifier<Layer?> transitionEdgeDragPreview = ValueNotifier(null);

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
    unawaited(addMediaAssets([effectivePath], carried: copyIntoProject));
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

  /// The media pool's import: same carry-or-reference choice as a
  /// timeline import, pool only (no clip link). Non-audio kinds register
  /// with their detected kind (R3b) — the batch stays one undo through
  /// [addMediaAssets].
  void importMediaFiles(List<String> paths, {required bool copyIntoProject}) {
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
    // (the old `sourcePath` spelling of the same answer).
    //
    // 🪦This paragraph used to end「the kind still sets the ceiling above
    // this, so a delivery's 참고영상 stays a reference either way」. That
    // ceiling died 2026-08-14 — the kind only picks the import window's
    // DEFAULT now, and a movie carries if the person says so.
    final registeredAssets = [
      for (final asset in plan.assets) asset.copyWith(carried: copyIntoProject),
    ];
    if (copyIntoProject) {
      // ⛔Awaited BEFORE the command that registers them. The isolate that
      // secures these bytes is the reason this is a `Future` at all, and
      // letting the registration overtake it is the one thing carrying
      // must not do.
      await stageCarriedBytes([for (final asset in plan.assets) asset.path]);
    }

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

  /// Opens a TVPaint project file AS A PROJECT — a .tvpp holds several
  /// cuts, so it replaces the session's project the way an .anicel open
  /// does: every clip a cut, pixels/timeline/folders/marks/camera/audio
  /// straight out of the file. The result is a NEW UNSAVED project (no
  /// [projectFilePath]); the first save asks where the .anicel goes.
  ///
  /// Returns the accumulated warnings, or null when the file is not
  /// readable as a TVPaint project. The CALLER gates unsaved work — this
  /// replaces everything.
  Future<List<String>?> openTvppAsProject({
    required String tvppPath,
    void Function(double fraction)? onProgress,
    void Function(Duration waited)? onWaiting,
    bool Function()? isCancelled,
  }) async {
    // A read failure THROWS (FileSystemException, out of the
    // materializer) and only a parse failure answers null — the door
    // used to show 「읽을 수 없는 파일」 for both, which sent the user
    // chasing a format problem when the real one was access (실측
    // 08-26: Drive on iPhone). Same materializer as the .anicel open;
    // the staged copy is read-and-discard here.
    final source = await FolderPicker.materializeOpenedFile(
      tvppPath,
      // A door that can be cancelled waits as long as the file takes;
      // one that cannot keeps the default backstop.
      within: isCancelled == null ? const Duration(minutes: 10) : null,
      onWaiting: onWaiting,
      isCancelled: isCancelled,
    );
    final TvppParseResult parsed;
    try {
      // SCOPED, so the whole-file bytes are collectable the moment the
      // structure is out of them. Everything after this reads the file by
      // OFFSET — a slot knows where its record is, so the long half of an
      // import (decoding every cel) never needs the file resident. Before
      // this the bytes stayed reachable for the entire import, which on a
      // 200MB project is 200MB held for minutes next to everything the
      // decode is building.
      final bytes = await File(source.path).readAsBytes();
      parsed = parseTvppStructure(bytes);
    } on TvppParseException {
      if (source.staged) {
        unawaited(
          File(source.path).delete().then<void>((_) {}, onError: (_) {}),
        );
      }
      return null;
    }
    // The other candidate for last-thing-the-app-ever-did: decoding a
    // whole TVPaint project holds every cel it builds.
    MemoryBlackBox.begin('tvpp-import');

    playback.stop();
    // The .tvpp becomes the WHOLE project, so its shooting frame does
    // too — fitting a 960×430 layout camera into our 16:9 default framed
    // wider than TVPaint did (288, hands-on).
    final cameraSize =
        parsed.projectCameraWidth != null && parsed.projectCameraHeight != null
        ? CanvasSize(
            width: parsed.projectCameraWidth!,
            height: parsed.projectCameraHeight!,
          )
        : defaultProjectCameraSize;
    final mint = _importIdMint();
    final warnings = [...parsed.warnings];
    if (source.staged) {
      // The last resort fired. Said out loud on purpose (유저 2026-08-27:
      // 「최후 수단이 발동됐다는 걸 표시해줬으면」): the wait is supposed to
      // make this road unreachable, so a build that still takes it should
      // be visible rather than quietly slower — and if it never appears
      // in the field, the road comes out.
      warnings.add('제자리에서 읽지 못해 임시 사본으로 열었습니다 — 이 문구가 보이면 알려주세요.');
    }
    final plans = <(TvpImportPlan, Map<String, TvppSlot>)>[];
    for (var c = 0; c < parsed.clips.length; c++) {
      final conversion = convertTvppClip(parsed.clips[c], clipIndex: c);
      final plan = planTvpImport(
        parsed: conversion.result,
        // Block files are synthetic slot keys, resolved against
        // [conversion.slotsByFile] at bake time — not paths.
        resolveFile: (key) => key,
        mint: mint,
      );
      warnings.addAll(plan.warnings);
      plans.add((plan, conversion.slotsByFile));
    }
    if (plans.isEmpty) {
      return null;
    }

    final name = tvppPath
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'\.tvpp$', caseSensitive: false), '');
    _repository.replaceProject(
      Project(
        id: ProjectId('tvpp-${DateTime.now().toUtc().millisecondsSinceEpoch}'),
        name: name,
        createdAt: DateTime.now().toUtc(),
        cameraSize: cameraSize,
        tracks: [
          // The planner still emits each clip's sound as a per-cut SE
          // row (the shape TVPaint stores); SE rows LIVE on the track's
          // global axis now, so the same lift the legacy-file migration
          // uses promotes them — one law for both doors.
          () {
            final lifted = liftCutSeLayersToTrack(
              const TrackId('default-track'),
              [for (final (plan, _) in plans) plan.cut],
            );
            return Track(
              id: const TrackId('default-track'),
              name: 'Track 1',
              cuts: lifted.cuts,
              seLayers: lifted.seLayers,
            );
          }(),
        ],
        // The sound tracks reference their files; register them so the
        // pool knows the paths and RELINK can say when one is missing.
        mediaAssets: const [],
      ),
    );

    // The whole-state reset an .anicel open performs, minus the parts
    // that only exist for saved files (recovery, cel restore, healing).
    brushFrameStore.restoreFromFile(const {});
    conteInkRowStore.restoreFromFile(const {});
    conteInkPageStore.restoreFromFile(const {});
    envelopeInkStore.restoreFromFile(const {});
    _historyManager.clear();
    _clipboard._copiedFrame = null;
    _clipboard._layerClipboard = null;
    clearAllSelections();
    trackFrameRangeSelection.value = null;
    _editingSession.setActiveCutId(plans.first.$1.cut.id);
    _rebuildActiveCutControllers();
    _voiceRecording.forgetShelfTakes();
    _projectFilePath = null;
    _recoveredFromSidecar = null;
    _discardedUnsavedWork = false;

    // Decoding is the import's whole cost (zlib + PackBits per cel, on
    // 288: ~30s of it, single-threaded) and it is pure — so it fans out
    // over worker isolates, in WAVES the size of the pool so at most
    // that many full-canvas RGBA buffers are ever alive at once. The
    // GPU bake stays here: it needs the UI thread and is cheap next to
    // the decode. Isolate.run moves its result out (no copy back).
    final work = <(TvpImportPlan, Cut, PlannedCelBake, TvppSlot)>[];
    for (final (plan, slotsByFile) in plans) {
      final bakedCut = _cutById(plan.cut.id);
      if (bakedCut == null) {
        continue;
      }
      for (final bake in plan.bakes) {
        final slot = slotsByFile[bake.sourceFile];
        if (slot != null) {
          work.add((plan, bakedCut, bake, slot));
        }
      }
    }
    final pool = math.max(1, math.min(Platform.numberOfProcessors - 1, 8));
    var bakedSoFar = 0;
    // 🚨READ BY OFFSET, ONE SLOT AT A TIME.
    //
    // A slot knows where its record is, so the decode never needs the
    // file resident — the reader seeks, takes that record, and nothing
    // else is held. Two costs went with the old shape of handing the
    // whole `Uint8List` around:
    //
    // - `Isolate.run` COPIES what its closure captures, so capturing the
    //   file gave every worker its own copy: a pool of eight meant eight
    //   whole projects at once, on top of the original and everything the
    //   import had already built;
    // - and the file stayed reachable for the WHOLE import, which on a
    //   200MB project is 200MB held for minutes beside the cels being
    //   made.
    //
    // Both scale with the FILE rather than with the work, which on a
    // phone is the allocation that gets the app killed.
    final reader = await File(source.path).open();
    try {
      for (var at = 0; at < work.length; at += pool) {
        final wave = work.sublist(at, math.min(at + pool, work.length));
        final windows = <Uint8List>[];
        for (final (_, _, _, slot) in wave) {
          await reader.setPosition(slot.chunkOffset);
          windows.add(await reader.read(slot.chunkLength));
        }
        final decoded = await Future.wait([
          for (var w = 0; w < wave.length; w++)
            () {
              final (plan, _, _, slot) = wave[w];
              final window = windows[w];
              // The record's offsets count from the record, so a window
              // rebased to zero is the same input by a different name.
              final windowSlot = TvppSlot(
                kind: slot.kind,
                chunkOffset: 0,
                chunkLength: slot.chunkLength,
                compressed: slot.compressed,
                v10WholeCanvas: slot.v10WholeCanvas,
              );
              final width = plan.cut.canvasSize.width;
              final height = plan.cut.canvasSize.height;
              return Isolate.run(() {
                try {
                  return decodeTvppSlotTiles(
                    recordBytes: window,
                    slot: windowSlot,
                    width: width,
                    height: height,
                  );
                } on TvppRasterDecodeException catch (error) {
                  return error;
                }
              });
            }(),
        ]);
        for (var i = 0; i < wave.length; i++) {
          final (_, bakedCut, bake, _) = wave[i];
          bakedSoFar += 1;
          onProgress?.call(bakedSoFar / work.length);
          final result = decoded[i];
          if (result is TvppRasterDecodeException) {
            warnings.add('${bake.sourceFile}: $result');
            continue;
          }
          final tiles = result as List<TvppCelTile>?;
          // A blank instance (빈 셀) decodes to zero tiles: the cel stays,
          // its pixels stay absent — same shape the drawing store gives an
          // empty cel.
          if (tiles == null || tiles.isEmpty) {
            continue;
          }
          final surface = BitmapSurface(canvasSize: bakedCut.canvasSize)
              .putTiles([
                for (final tile in tiles)
                  BitmapTile(
                    coord: TileCoord(x: tile.x, y: tile.y),
                    size: 256,
                    pixels: tile.pixels,
                  ),
              ]);
          bakeCelSurface(
            brushFrameStore,
            brushFrameKeyForCut(bakedCut, bake.layerId, bake.frameId),
            surface,
          );
        }
      }
    } finally {
      await reader.close();
      // The staged copy outlives the decode now, because the decode
      // reads FROM it. It was deleted the moment the bytes were in hand
      // back when the whole file was held in memory.
      if (source.staged) {
        unawaited(
          File(source.path).delete().then<void>((_) {}, onError: (_) {}),
        );
      }
    }

    // The audio references become pool assets so relink and existence
    // checks see them; a missing file surfaces as a warning, not a crash.
    final audioPaths = <String>{
      for (final clip in parsed.clips)
        for (final track in clip.audioTracks) track.filePath,
    };
    if (audioPaths.isNotEmpty) {
      unawaited(addMediaAssets(audioPaths.toList()));
      _historyManager.clear();
      for (final path in audioPaths) {
        if (!File(path).existsSync()) {
          warnings.add('사운드 파일이 이 자리에 없다: $path');
        }
      }
    }

    _settleConformCache();
    _warmAudioConforms();
    refreshMediaExistence();
    // A conversion is unsaved by definition — nothing on disk holds it.
    _hasUnsavedChanges = true;
    _warmActiveCut();
    frameSeekCommitted.value += 1;
    _refreshAfterCutCommand();
    notifyListeners();
    MemoryBlackBox.end('tvpp-import');
    return warnings;
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

  // ── the text-cel bakes: their own sweep, in their own file ─────────────
  //
  // A collaborator (session/text_cel_bakes.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _TextCelBakes _textCelBakes = _TextCelBakes(this);

  Future<void> get debugTextCelSweepDone => _textCelBakes.debugTextCelSweepDone;
  TextCelContent? get selectedTextCelContent =>
      _textCelBakes.selectedTextCelContent;
  void setTextCelContentForSelectedFrame(TextCelContent content) =>
      _textCelBakes.setTextCelContentForSelectedFrame(content);

  bool _disposed = false;

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
    stageCarriedBytes: stageCarriedBytes,
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
  ValueNotifier<bool> get voiceRecordClipLit =>
      _voiceRecording.voiceRecordClipLit;

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

  Future<String?> stopVoiceRecordingAndPlace() =>
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
  Future<bool> placeVoiceRecording(
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
  /// Registers [paths] in the pool. When [carried], the bytes are COPIED
  /// into the app container on the spot.
  ///
  /// 🚨★★★**That copy is what「품기」means now.** It used to be a promise
  /// kept only at SAVE time — the flag said the file travels with the
  /// project while the bytes were still the ones on disk, so editing or
  /// deleting the original before the first save changed or emptied what
  /// got saved. 유저 2026-08-30: 「품은 순간 데이터를 가지고있고 **불변**
  /// 이었으면좋겠어서」.
  ///
  /// ⚠️Async because that copy runs in an isolate now, and the pool must
  /// not record an asset before its bytes are secured. A caller that
  /// forgets to await gets the pre-carry behaviour back without a word.
  Future<void> addMediaAssets(
    List<String> paths, {
    bool carried = false,
  }) async {
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
    if (carried) {
      await stageCarriedBytes([for (final asset in added) asset.path]);
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
  ///
  /// ⛔**It does NOT retire the staged copy, and that is deliberate.** This
  /// is UNDOABLE — the description above makes an undo entry — so throwing
  /// the bytes away here would mean an undo brings the asset back empty
  /// whenever the original file is also gone, which is precisely the case
  /// 품기 exists for. The 30-day sweep owns them instead
  /// ([MediaStagingStore.sweepAbandoned]): waiting costs a file in the
  /// container, and not waiting costs the picture.
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
  ///
  /// ⚠️Async because the re-stage below runs in an isolate — see
  /// [stageCarriedBytes].
  Future<void> relinkMediaAsset(String oldPath, String newPath) async {
    audioConformStore.invalidate(newPath);
    _cutCommandCoordinator.relinkMediaAsset(oldPath: oldPath, newPath: newPath);
    _moveMediaFingerprints({oldPath: newPath});
    // 🚨★★★**THIS RELINK RE-STAGES; THE BATCH ONE MOVES. THE DIFFERENCE
    // IS WHAT EACH CALLER KNOWS.**
    //
    // Here the user picked a file by hand and said「this asset is THAT
    // one」. Nothing checked that it holds the same content — so carrying
    // the OLD staged bytes over to the new key would keep serving the old
    // picture under the name of the new file, for ever, with the project
    // insisting it was right.
    //
    // The batch relink below verified identity before proposing anything,
    // so there the bytes ARE the same and moving them costs one rename
    // instead of re-reading every matched file.
    mediaStagingStore.retire(oldPath);
    // ⛔Through [projectArchivedMediaPaths] rather than a hand-rolled
    // `any(... && asset.carried)`. That function is the ONE answer to
    // 「which media does this project carry」, and a second spelling of it
    // here is how the kind ceiling came to be enforced in two places and
    // disagree with itself.
    if (projectArchivedMediaPaths(
      _repository.requireProject(),
    ).contains(newPath)) {
      await stageCarriedBytes([newPath]);
    }
    refreshMediaExistence();
    notifyListeners();
  }

  /// RELINK-2: the batch form — the media pool's "find them all under
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
    // And the staged bytes, keyed by the same path — see
    // [MediaStagingStore.rename]. The sentence above about derived state
    // is the whole reason both of these lines exist.
    //
    // ⚠️MOVED, not re-staged, and only because this caller EARNED it: the
    // matcher accepts a candidate only when its identity matches the one
    // recorded for the missing asset, so the bytes are the same bytes and
    // re-reading every matched file would be work for nothing. The
    // by-hand relink above cannot say that, and re-stages.
    for (final move in moves.entries) {
      mediaStagingStore.rename(move.key, move.value);
    }
    refreshMediaExistence();
    notifyListeners();
  }

  /// RELINK-2: pool paths that were not on disk as of the last refresh.
  ///
  /// CACHED rather than probed per row. The media pool used to call
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
    final probe =
        debugMediaFileExists ?? (String path) => File(path).existsSync();
    final missing = <String>{};
    final modified = <String, DateTime>{};
    for (final asset in mediaAssets) {
      if (!probe(asset.path)) {
        // The import original leaving is NOT "missing" for an asset whose
        // bytes the project holds — deleting the original is the very act
        // carrying exists to survive. Probing only the path put the "File
        // missing — relink it" banner on assets the project already owns
        // and fed them to the relink hunt, whose "success" would re-key
        // the asset and orphan what held its bytes.
        if (!projectHoldsMediaBytes(asset.path)) {
          missing.add(asset.path);
        }
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
    // A path that came BACK (the share mounted, the drive returned) may
    // have burned its conform attempt budget while it was gone — three
    // "missing" answers and the clip stayed silent for the whole session
    // even after the file reappeared. Reappearing is the retry signal.
    for (final path in _missingMediaPaths) {
      if (!missing.contains(path)) {
        audioConformStore.invalidate(path);
      }
    }
    _missingMediaPaths = missing;
    _mediaModifiedTimes = modified;
    notifyListeners();
  }

  /// Marks the [path] asset as one the project CARRIES — the per-asset
  /// promotion out of the media pool, and the answer to what a
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
  /// Returns false when there is nothing to promote: no such asset, or one
  /// already carried. A promotion that changed nothing must not spend an
  /// undo step saying so.
  ///
  /// 🪦It used to add「or a kind that is never carried whatever anyone
  /// picks」. That ceiling died 2026-08-14 — every kind carries now, and
  /// the kind only chooses the import window's default.
  ///
  /// ⛔ONE DIRECTION on purpose. Carrying is always safe; UN-carrying
  /// strands a project whose original has since been moved or deleted, so
  /// the two are not a pair of switches to offer side by side. A reverse
  /// verb needs a "the original is still there" guard of its own first,
  /// and that is a separate decision.
  ///
  /// ⚠️Async because securing the bytes runs in an isolate — see
  /// [stageCarriedBytes]. The answer still means「something changed」, and
  /// it is still decided before any waiting happens.
  /// Whether this project HAS a file on disk and that file is gone.
  ///
  /// 🚨A clean cel lives as a ref into the project file — the store drops
  /// its cold blob on adoption — so the file disappearing takes those
  /// pixels with it. Nothing here can bring them back; the point of asking
  /// is to say so while the FILE can still be restored from a trash.
  ///
  /// ⛔False for a never-saved project. There is no file to have lost, and
  /// a session with nothing on disk is the ordinary state.
  bool projectFileHasVanished() {
    final path = _projectFilePath;
    return path != null && !File(path).existsSync();
  }

  /// Where [path]'s conformed audio is on disk, building it if this machine
  /// has not yet — or null when the asset has no audio to conform.
  ///
  /// 🔑The pool panel's export asks for this and nothing else. Reading the
  /// conform, swapping the header and placing the file are three different
  /// jobs living in three different places already; what was missing was
  /// only the session saying WHICH file.
  Future<String?> conformPathForExport(String path) async {
    final result = await audioConformStore.ensureFor(path);
    if (result == null || !result.isUsable) {
      return null;
    }
    return result.conformPath;
  }

  Future<bool> promoteMediaAssetIntoProject(String path) async {
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
    await stageCarriedBytes([path]);
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
    unawaited(addMediaAssets([path]));
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

  // ── the storyboard cursor: its own object, in its own file ──────────
  //
  // A collaborator (session/storyboard_cursor.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _StoryboardCursor _storyboardCursor = _StoryboardCursor(this);

  bool get canSetCommaForStoryboardCursor =>
      _storyboardCursor.canSetCommaForStoryboardCursor;
  bool get canDeleteBlockAtStoryboardCursor =>
      _storyboardCursor.canDeleteBlockAtStoryboardCursor;
  void deleteBlockAtStoryboardCursor() =>
      _storyboardCursor.deleteBlockAtStoryboardCursor();
  bool get canCreateSeEntryAtStoryboardCursor =>
      _storyboardCursor.canCreateSeEntryAtStoryboardCursor;
  void createSeEntryAtStoryboardCursor() =>
      _storyboardCursor.createSeEntryAtStoryboardCursor();
  bool get canCreateStoryboardPanelAtCursor =>
      _storyboardCursor.canCreateStoryboardPanelAtCursor;
  void createStoryboardPanelAtCursor() =>
      _storyboardCursor.createStoryboardPanelAtCursor();
  void setStoryboardCellAction({
    required CutId cutId,
    required int cellIndex,
    required String action,
  }) => _storyboardCursor.setStoryboardCellAction(
    cutId: cutId,
    cellIndex: cellIndex,
    action: action,
  );
  String? get targetLayerStoryboardRefusal =>
      _storyboardCursor.targetLayerStoryboardRefusal;

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

  // ── the exposure verbs: their own object, in their own file ─────────
  //
  // A collaborator (session/exposure_verbs.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _ExposureVerbs _exposure = _ExposureVerbs(this);

  bool get canBlankExposureForSelection =>
      _exposure.canBlankExposureForSelection;
  bool get canBlankExposureAtCurrentFrame =>
      _exposure.canBlankExposureAtCurrentFrame;
  void blankExposureAtCurrentFrame() => _exposure.blankExposureAtCurrentFrame();
  void increaseSelectedExposure() => _exposure.increaseSelectedExposure();
  void decreaseSelectedExposure() => _exposure.decreaseSelectedExposure();
  TimelineCellExposureState exposureStateForLayer(
    Layer layer,
    int frameIndex,
  ) => _exposure.exposureStateForLayer(layer, frameIndex);
  bool get canDecreaseSelectedExposure => _exposure.canDecreaseSelectedExposure;
  bool get canIncreaseSelectedExposure => _exposure.canIncreaseSelectedExposure;

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

  // ── the auto frame for a stroke: its own object ─────────────────────
  //
  // A collaborator (session/auto_frame_for_stroke.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _AutoFrameForStroke _autoFrame = _AutoFrameForStroke(this);

  bool get canAutoCreateFrameForStroke =>
      _autoFrame.canAutoCreateFrameForStroke;
  bool beginAutoFrameForStroke() => _autoFrame.beginAutoFrameForStroke();
  Command? takeAutoFrameForStroke() => _autoFrame.takeAutoFrameForStroke();
  void flushAutoFrameForStroke() => _autoFrame.flushAutoFrameForStroke();

  // ── the cell instances: their own object, in their own file ─────────
  //
  // A collaborator (session/cell_instances.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _CellInstances _instances = _CellInstances(this);

  bool createInstancesForSelection() =>
      _instances.createInstancesForSelection();
  bool get canCreateInstance => _instances.canCreateInstance;
  bool get activeCellHoldsAnInstance => _instances.activeCellHoldsAnInstance;
  bool get canCreateInstanceForSelection =>
      _instances.canCreateInstanceForSelection;
  bool get canEditCellInstanceAtCurrentFrame =>
      _instances.canEditCellInstanceAtCurrentFrame;
  EditInstanceSubject get editInstanceSubject => _instances.editInstanceSubject;
  EditInstanceSubject editInstanceSubjectFor({
    required bool cutsAreThisPanels,
  }) => _instances.editInstanceSubjectFor(cutsAreThisPanels: cutsAreThisPanels);

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
  ) => emptyGapsBetween(
    layer,
    selection.startIndex,
    selection.endIndexExclusive,
  );

  /// 🚨T3 신설 — 잘라내기: the same lift the paste does, with the clip going
  /// to the clipboard instead of a row.
  ///
  /// 유저 확정 2026-08-13: 「잘라내기 버튼을 공용 알약에 신설 — 복사 버튼
  /// 왼쪽. 복사=원본 남기고 클립 저장 · 잘라내기=원본 지우고 클립 저장」.
  ///
  /// ★It is literally copy followed by the lift half of [spliceTimeline],
  /// which is why it needs no rules of its own — with ONE exception: the
  /// lift has to survive the write. On a SINGLE-CEL (image) row it does
  /// not. The covering normalization rebuilds the picture's block from
  /// the same write, so the press changes nothing on screen and costs a
  /// phantom undo entry — the next Ctrl+Z then eats the user's real
  /// previous edit. Same standdown, same reason, as the delete gate
  /// (D22). COPY stays lit: it takes the cel to the clipboard without
  /// claiming to remove it, which is honest here.
  bool get canCutRunAtCurrentFrame {
    // 잘라내기 resolves its run on the ACTIVE row, so under a band naming
    // other rows it lifts a block the user never swept — and being the
    // destructive half of the clipboard pair, it did so while Delete sat
    // dark one button away on the same pill. No band rung to serve, so
    // the band ends the ladder — and so does COPY, its documented twin:
    // "it only reads" was wrong, since it writes the clipboard.
    if (bandNamesRowsThisPressWouldMiss) {
      return false;
    }
    final layer = activeLayer;
    if (layer != null && layerKindHoldsSingleCel(layer.kind)) {
      return false;
    }
    return canCopyFrameAtCurrentFrame;
  }

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
    // 🚨결정 14 ②ⓐ — the lift takes every row the copy just banked, in ONE
    // undo. ⛔It reads the CLIPBOARD's rows rather than re-resolving the
    // band: the two must not be able to disagree about which rows were
    // taken, because a row lifted but not banked is work that cannot come
    // back — 「클립보드가 담지 않은 것을 들어내면 그건 삭제지 잘라내기가
    // 아니다」.
    final selection = frameRangeSelection.value;
    final banked = _clipboard._copiedFrame?.rows ?? const <_CopiedRow>[];
    _timelineController.spliceRunsForLayers(
      runs: [
        for (final row in banked)
          (
            layerId: row.layerId,
            index: row.layerId == layer.id
                ? run.index
                : _commitBlockStart(row.layerId, selection!.startIndex),
            liftCount: row.layerId == layer.id
                ? run.count
                : selection!.lengthFrames,
            clip: null,
            bornFrames: const <Frame>[],
          ),
        if (banked.isEmpty)
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

  /// ⚠️Formats an id from the CURRENT sequence — it does not advance it.
  /// Call [_mintFrameId] unless you have just incremented `_frameSequence`
  /// yourself. The wall clock in here is decoration, not identity: its
  /// resolution on Windows is coarser than a tight mint loop, so two ids
  /// made in the same tick are equal, and equal frame ids are ONE drawing.
  String _nextFrameId(LayerId layerId) {
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
  final ValueNotifier<TimelineDragPreview?> dragPreview =
      ValueNotifier<TimelineDragPreview?>(null);

  // --- Storyboard cut-trim edge drags --------------------------------------

  // Fade durability (W4) retired by R4: the fade keys live on the TRACK's
  // global axis now — a cut trim is a cut edit and moves no keys (the
  // user's independence rule, the SE precedent's sentence).

  // --- Movie-end drag (UI-R20 #3) -------------------------------------------

  // ── the movie-end drag: its own object, in its own file ────────────────
  //
  // A collaborator (session/movie_end_drag.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _MovieEndDrag _movieEnd = _MovieEndDrag(this);

  int get movieContentEndFrame => _movieEnd.movieContentEndFrame;
  bool beginMovieEndDrag() => _movieEnd.beginMovieEndDrag();
  void updateMovieEndDrag(int cumulativeDelta) =>
      _movieEnd.updateMovieEndDrag(cumulativeDelta);
  void endMovieEndDrag() => _movieEnd.endMovieEndDrag();
  void cancelMovieEndDrag() => _movieEnd.cancelMovieEndDrag();

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
    final transitionTrack = _transitions.trackTransitionOwner(layerId);
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
    final layer = _trackSe.trackSeAnywhere(layerId)?.layer;
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

  Track? _trackById(TrackId trackId) {
    for (final track in _repository.requireProject().tracks) {
      if (track.id == trackId) {
        return track;
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
        final layer = _trackSe.trackSeAnywhere(layerId)?.layer;
        if (layer != null) {
          return (index) => exposureBlockAt(layer, index);
        }
        // 🚨The transition row snaps to its SPANS, and a row with no snap lane
        // at all produced no span — which cleared the selection instead of
        // making one. Its blocks are instruction events rather than exposures,
        // so the material differs and the shape does not.
        final transition = _transitions
            .trackTransitionOwner(layerId)
            ?.transitionLayer;
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

  /// The selection filtered to cuts that still EXIST — nothing to filter
  /// any more: [storyboardSelectedCutIds] reads the CURRENT layout, so a
  /// cut another command deleted since the drag painted the range is simply
  /// not in it.
  List<CutId> get _liveSelectedCutIds => storyboardSelectedCutIds;

  // --- Storyboard cut-block MOVE drags (R10-④) ----------------------------

  // The cut move drag (Round 6): begun, moved, ended or cancelled.
  late final _CutMoveDragVerbs _cutMove = _CutMoveDragVerbs(this);

  bool beginCutMoveDrag(CutId cutId) => _cutMove.beginCutMoveDrag(cutId);
  void updateCutMoveDrag(int cumulativeDelta) =>
      _cutMove.updateCutMoveDrag(cumulativeDelta);
  void endCutMoveDrag() => _cutMove.endCutMoveDrag();
  void cancelCutMoveDrag() => _cutMove.cancelCutMoveDrag();

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
  DrawingBlockMoveDrag? _blockMoveDrag;

  bool get isBlockMoveDragActive => _blockMoveDrag != null;

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
    if (_folders.isSyncedAttachedLayerId(layerId) ||
        isTrackSeLayerId(layerId)) {
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
      final rows = <LayerId>[
        ...{
          for (final row in trackSelection.spanRows)
            if (row.owningLayerId case final id?
                when trackSeGlobalLayerById(id) != null)
              id,
        },
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
          if (!_folders.isSyncedAttachedLayerId(id) &&
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
        _folders.isSyncedAttachedLayerId(layerId) ||
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
      _frameVerbs.shiftFrames(count, currentRow: currentRow);

  /// Closes up to [count] frames, clamped to [framePullSlack].
  void pullFrames(int count, {TimelineRowAddress? currentRow}) => _frameVerbs.shiftFrames(
    -math.min(count, framePullSlack(currentRow: currentRow)),
    currentRow: currentRow,
  );

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

  // ── the lane range move drag: its own object, in its own file ───────
  //
  // A collaborator (session/lane_range_move_drag.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _LaneRangeMoveDrag _laneMove = _LaneRangeMoveDrag(this);

  bool beginLaneRangeMoveDrag() => _laneMove.beginLaneRangeMoveDrag();
  void updateLaneRangeMoveDrag({required int frameDelta}) =>
      _laneMove.updateLaneRangeMoveDrag(frameDelta: frameDelta);
  void endLaneRangeMoveDrag() => _laneMove.endLaneRangeMoveDrag();
  void cancelLaneRangeMoveDrag() => _laneMove.cancelLaneRangeMoveDrag();

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

  /// The standing row's RANGE layer and its authored extremes, or null
  /// when the row has nothing to select. Lane rows fall back to their
  /// owning layer — the lane address's own law: standing on a property
  /// never costs you the layer.
  ///
  /// The extremes are read off the SAME three lanes the range snap uses
  /// ([snapFrameRangeToBlocks]): exposure blocks (ghosts are derived
  /// projections, not authored cells), instruction chips, and a folder
  /// row's aggregate runs — so the gate answers true exactly where a drag
  /// would select something (T25).
  ({LayerId layerId, int first, int lastExclusive})? _rowSpanForCurrentRow() {
    final rowLayerId = switch (currentRow) {
      LayerRowAddress(:final layerId) => layerId,
      LaneRowAddress(:final layerId) => layerId,
      TrackRowAddress() => activeLayerId,
    };
    if (rowLayerId == null ||
        !_rangeSelections.rangeSelectionEligible(rowLayerId)) {
      return null;
    }
    final layer = _rangeLayerById(rowLayerId);
    if (layer == null) {
      return null;
    }
    int? first;
    var lastExclusive = 0;
    void widen(int start, int endExclusive) {
      if (first == null || start < first!) {
        first = start;
      }
      if (endExclusive > lastExclusive) {
        lastExclusive = endExclusive;
      }
    }

    for (final entry in layer.timeline.entries) {
      if (entry.value.ghost) {
        continue;
      }
      widen(entry.key, entry.key + entry.value.length!);
    }
    for (final entry in layer.instructions.entries) {
      widen(entry.key, entry.key + entry.value.length);
    }
    for (final run in _aggregateRunsForRow(layer)) {
      widen(run.start, run.endExclusive);
    }
    final start = first;
    if (start == null) {
      return null;
    }
    return (layerId: rowLayerId, first: start, lastExclusive: lastExclusive);
  }

  // ── the drawing block move drag: its own object ─────────────────────
  //
  // A collaborator (session/drawing_block_move_drag.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _DrawingBlockMoveDrag _drawingBlockMove = _DrawingBlockMoveDrag(
    this,
  );

  bool beginDrawingBlockMoveDrag({
    required LayerId layerId,
    required int blockStartIndex,
  }) => _drawingBlockMove.beginDrawingBlockMoveDrag(
    layerId: layerId,
    blockStartIndex: blockStartIndex,
  );
  void updateDrawingBlockMoveDrag({
    required int frameDelta,
    LayerId? targetLayerId,
  }) => _drawingBlockMove.updateDrawingBlockMoveDrag(
    frameDelta: frameDelta,
    targetLayerId: targetLayerId,
  );
  void endDrawingBlockMoveDrag() => _drawingBlockMove.endDrawingBlockMoveDrag();
  void cancelDrawingBlockMoveDrag() =>
      _drawingBlockMove.cancelDrawingBlockMoveDrag();

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

  // --- Frame RANGE move drag (UI-R8: drag the selected range) --------------

  // ── the frame-range move drag: its own object, in its own file ────────
  //
  // The first collaborator carved out of this class (2026-09-02, the audit's
  // SRP cut): the drag's state and steps live in `_FrameRangeMoveDrag`
  // (session/frame_range_move_drag.dart, a part of this library so the
  // private seams stay private). The session keeps the public entry points
  // as forwarders, so every caller is unchanged.
  late final _FrameRangeMoveDrag _rangeMove = _FrameRangeMoveDrag(this);

  /// The door a collaborator announces through — `notifyListeners` is
  /// protected, and a collaborator is not a subclass.
  void _notifyChanged() => notifyListeners();

  bool beginFrameRangeMoveDrag([LayerId? grabLayerId]) =>
      _rangeMove.beginFrameRangeMoveDrag(grabLayerId);
  bool beginTrackRangeMoveDrag([LayerId? grabLayerId]) =>
      _rangeMove.beginTrackRangeMoveDrag(grabLayerId);
  void updateFrameRangeMoveDrag({
    required int frameDelta,
    LayerId? targetLayerId,
  }) => _rangeMove.updateFrameRangeMoveDrag(
    frameDelta: frameDelta,
    targetLayerId: targetLayerId,
  );
  void endFrameRangeMoveDrag() => _rangeMove.endFrameRangeMoveDrag();
  void cancelFrameRangeMoveDrag() => _rangeMove.cancelFrameRangeMoveDrag();
  void setRunEdgeBehavior({
    required LayerId layerId,
    required int blockStartIndex,
    required TimelineRunEdgeSide side,
    TimelineRunEdgeMode? mode,
    bool scopeToSelection = true,
  }) => _rangeMove.setRunEdgeBehavior(
    layerId: layerId,
    blockStartIndex: blockStartIndex,
    side: side,
    mode: mode,
    scopeToSelection: scopeToSelection,
  );

  // --- Run-edge NEW FRAMES drag (UI-R8 [+] handle) --------------------------

  // ── the run frames add drag: its own object ─────────────────────────
  //
  // A collaborator (session/run_frames_add_drag.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _RunFramesAddDrag _runFramesAdd = _RunFramesAddDrag(this);

  bool beginRunFramesAddDrag({
    required LayerId layerId,
    required int blockStartIndex,
    required bool atEnd,
  }) => _runFramesAdd.beginRunFramesAddDrag(
    layerId: layerId,
    blockStartIndex: blockStartIndex,
    atEnd: atEnd,
  );
  void updateRunFramesAddDrag(int count) =>
      _runFramesAdd.updateRunFramesAddDrag(count);
  void endRunFramesAddDrag() => _runFramesAdd.endRunFramesAddDrag();
  void cancelRunFramesAddDrag() => _runFramesAdd.cancelRunFramesAddDrag();

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

  Layer? _layerById(LayerId layerId) {
    for (final layer in layers) {
      if (layer.id == layerId) {
        return layer;
      }
    }
    return null;
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
    if (deletableSelectedLayerIds().isNotEmpty) {
      return DeleteSubject.layers;
    }
    return canDeleteCellAtCurrentFrame
        ? DeleteSubject.cells
        : DeleteSubject.nothing;
  }

  /// Runs whatever [deleteSubject] names. One undo step either way — the cell
  /// path already composes its own.
  void deleteSelectionSubject({bool cutsAreThisPanels = true}) {
    switch (deleteSubjectFor(cutsAreThisPanels: cutsAreThisPanels)) {
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

  /// Whether a live band names rows this press would MISS.
  ///
  /// The ACTIVE-ROW verbs — X-here, the ● mark, the cell rename and
  /// 잘라내기 — all resolve against the active layer. A band covering that
  /// row is served: 잘라내기 splices exactly the swept span
  /// ([_spliceRunOnActiveRow]), and the playhead verbs act on the row the
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
  bool get bandNamesRowsThisPressWouldMiss {
    final selection = frameRangeSelection.value;
    if (selection == null) {
      return false;
    }
    final layer = activeLayer;
    return layer == null || !selection.coversLayer(layer.id);
  }

  String? get selectedFrameName => selectedFrame?.name;

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

  // --- Comma set (UI-R17 #7: the 1/2/3/4/N buttons) -------------------------

  /// Whether a comma set has a target: the selection's blocks, else the
  /// active layer's block covering the playhead.
  ///
  /// The second rung borrows the delete gate, which answers true for LANE
  /// KEYS as well — a subject this verb has no branch for. Under a
  /// claiming band that inheritance is what lit the buttons over a press
  /// [setCommaForSelectionOrCurrent] then refuses, so the band's claim is
  /// read here too and the two stay one answer.
  bool get canSetCommaForSelectionOrCurrent =>
      _rangeSelections.selectionBlockStartsByLayer() != null ||
      (!cellSelectionClaimsSubject && canDeleteCellAtCurrentFrame);

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
    // Single-cel rows are already absent — the shared collector states
    // that standdown once, so this verb and its `can…` gate agree.
    final selectionTargets = _rangeSelections.selectionBlockStartsByLayer();
    if (selection != null &&
        selectionTargets != null &&
        selectionTargets.isNotEmpty) {
      _timelineController.retimeBlocksForLayers({
        for (final entry in selectionTargets.entries)
          entry.key: {for (final start in entry.value) start: comma},
      });
      _rangeSelections.reselectRetimedSelection(selection, selectionTargets);
      _warmActiveCut();
      notifyListeners();
      return;
    }
    if (cellSelectionClaimsSubject) {
      // Same law as the delete verb: a band that resolves to nothing
      // retimable is a no-op, never a press that lands on some other row.
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
    final layout = _projectSettings.projectLayout();
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
        layout: _projectSettings.projectLayout(),
        globalFrameIndex: globalFrame,
      );

  /// The same resolution WITH transitions: an O.L answers with both cuts,
  /// leaving one first, each carrying its share of the frame. One reader for
  /// the parked canvas, all-cuts playback and the camera-size bake.
  List<TrackStackContribution> trackStackContributionsAt(int globalFrame) =>
      resolveTrackStackContributions(
        layout: _projectSettings.projectLayout(),
        spansOf: transitionSpansOfTrack,
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
    _standing.rememberActiveLayerForCut();
    // The visibility solo is cut-scoped: restore the eyes before leaving
    // (the selectCut contract).
    if (_solo._layerVisibilitySoloEnabled) {
      _solo.exitVisibilitySolo();
    }
    _editingSession.setActiveCutId(null);
    _clipboard._copiedFrame = null;
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

  // ── the frame scrub: its own object, in its own file ───────────────────
  //
  // A collaborator (session/frame_scrub.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _FrameScrub _frameScrub = _FrameScrub(this);

  void scrubGlobalFrame(int globalFrame) =>
      _frameScrub.scrubGlobalFrame(globalFrame);
  void scrubFrameIndex(int frameIndex) =>
      _frameScrub.scrubFrameIndex(frameIndex);
  void abandonFrameScrubPreview() => _frameScrub.abandonFrameScrubPreview();
  void commitFrameScrub() => _frameScrub.commitFrameScrub();

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

  // ── the onion skin: its own object, in its own file ─────────────────
  //
  // A collaborator (session/onion_skin.dart, a part of this library). The
  // session keeps the public entry points as forwarders.
  late final _OnionSkin _onionSkin = _OnionSkin(this);

  bool isLayerOnionSkinEnabled(LayerId layerId) =>
      _onionSkin.isLayerOnionSkinEnabled(layerId);
  void toggleLayerOnionSkin(LayerId layerId) =>
      _onionSkin.toggleLayerOnionSkin(layerId);
  bool get displayedLayersOnionSkinEnabled =>
      _onionSkin.displayedLayersOnionSkinEnabled;
  void toggleOnionSkinForDisplayedLayers() =>
      _onionSkin.toggleOnionSkinForDisplayedLayers();
  void toggleOnionSkin() => _onionSkin.toggleOnionSkin();
  List<CanvasLayerImageRequest> onionSkinCanvasRequests() =>
      _onionSkin.onionSkinCanvasRequests();

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

  /// What [poolPath]'s bytes ACTUALLY occupy right now, or null when only
  /// the file on disk knows.
  ///
  /// 🚨★★★**THE SIZE SHOWN IS THE SIZE TAKEN** (유저 2026-08-30: 「파일이
  /// 보여주는 크기는 압축된 크기를 보여주는게 맞겟지? … 아무튼 실제크기」).
  /// The media pool used to read `identity.lengthBytes` — the length
  /// the file had when it was REGISTERED — which after compression is a
  /// number matching nothing: not the disk, not the project file, not the
  /// staged copy.
  ///
  /// ⛔[MediaAsset.identity] is left alone. That field answers「is this the
  /// same file?」for relink, and a compressed length would make every
  /// carried asset fail to match itself.
  ///
  /// ⚠️Cheap by construction — a stat on the staged file, or a length the
  /// archive layout already handed over. The browser draws a row per asset
  /// and must not parse a ZIP to do it, which is why the archive half is
  /// remembered at save/open rather than asked for here.
  int? mediaStoredBytesFor(String poolPath) {
    final staged = mediaStagingStore.find(poolPath);
    if (staged != null) {
      return staged.storedLength;
    }
    return _archivedMediaBytes()[poolPath];
  }

  /// Stored lengths for the media inside the project file, parsed ONCE per
  /// completed save and kept until the next one.
  ///
  /// ⚠️Keyed on [_completedSaveGeneration] rather than time: a compaction
  /// moves every byte, so a length from before one describes nothing. The
  /// generation is the thing that already changes exactly when that
  /// happens.
  Map<String, int> _archivedMediaBytes() => _archivedBytes().media;

  /// The archived lengths of the media AND of the conforms, from ONE walk
  /// of the central directory.
  ///
  /// 🚨★★★**ONE PARSE, BECAUSE THE SECOND ONE WAS FREE-LOOKING AND WAS
  /// NOT.** The conform column asks the same question about the same file,
  /// and answering it separately meant a tail parse PER ASSET — and then
  /// again every time the conform store answered, which is once per sound
  /// while a project is warming up. The media half was already careful
  /// about this; the fix was to join them rather than to be careful twice.
  ({Map<String, int> media, Map<String, int> conform}) _archivedBytes() {
    final path = _projectFilePath;
    if (path == null) {
      return (media: const {}, conform: const {});
    }
    if (_archivedBytesGeneration == _completedSaveGeneration) {
      return (media: _mediaStoredBytes, conform: _conformArchivedBytes);
    }
    var media = const <String, int>{};
    var conform = const <String, int>{};
    try {
      final layout = parseAnicelZipLayoutFile(path);
      media = {
        for (final entry in _mediaEntryNames.entries)
          if (layout.entryNamed(entry.value) case final found?)
            entry.key: found.length,
      };
      final project = _repository.requireProject();
      conform = {
        for (final asset in project.mediaAssets)
          for (final name in anicelConformEntryNames(
            asset.path,
            sampleRate: project.audioSampleRate,
            speedNumerator: project.audioSpeedNumerator,
            speedDenominator: project.audioSpeedDenominator,
          ))
            if (layout.entryNamed(name) case final found?)
              asset.path: found.length,
      };
    } on Object {
      // A torn or momentarily unreadable archive answers nothing rather
      // than a wrong number; the row falls back to what it always showed.
    }
    _mediaStoredBytes = media;
    _conformArchivedBytes = conform;
    _archivedBytesGeneration = _completedSaveGeneration;
    return (media: media, conform: conform);
  }

  Map<String, int> _mediaStoredBytes = const {};
  Map<String, int> _conformArchivedBytes = const {};
  int _archivedBytesGeneration = -1;

  /// What [poolPath]'s CONFORM occupies, or null when it has none.
  ///
  /// 🚨★★★**ASKED FOR BY NAME** (유저 2026-08-30, answering
  /// `conform-in-project`): 「가시화정책에 따라 미디어풀 패널에서 해당파일의
  /// 컨폼파일 크기 표시할것」. A conform is the biggest thing an audio asset
  /// costs — several times the sound itself — and until now it was a
  /// number only the settings dialog knew, as one lump for the whole
  /// container.
  ///
  /// The CACHE file first, the carried entry second, and they are the same
  /// bytes: whichever is present answers. A pruned cache still has a size
  /// to report, because the project is still carrying one.
  ///
  /// ⚠️Compressed size, not decoded — the same「실제크기」policy
  /// [mediaStoredBytesFor] follows, because it is the number that says
  /// what the disk lost.
  int? conformStoredBytesFor(String poolPath) {
    final base = _conformPathFor(poolPath);
    if (base != null) {
      for (final candidate in mediaFramedOrPlainPaths(base)) {
        final stat = FileStat.statSync(candidate);
        if (stat.type == FileSystemEntityType.file) {
          return stat.size;
        }
      }
    }
    // ⛔Through the shared per-generation walk, NOT [_carriedConformFor]:
    // that one parses the archive on the spot, which is right for a single
    // playback request and wrong for a column drawn per asset.
    return _archivedBytes().conform[poolPath];
  }

  /// [conformStoredBytesFor] for every asset that has one — the map the
  /// pool panel draws from.
  ///
  /// 🚨★★★**MEMOISED, BECAUSE A ROW MUST NOT STAT THE DISK TO DRAW
  /// ITSELF.** The panel reads this in `build`, and a panel is rebuilt for
  /// reasons that have nothing to do with the file system — which is the
  /// same reason `missingPaths` and `modifiedTimes` are handed in as maps
  /// instead of probed per row. Without this, every repaint cost two stats
  /// per asset.
  ///
  /// ⚠️Invalidated by [_invalidateConformStoredBytes] on two events and
  /// they are BOTH needed: a completed save (the carried entry's length
  /// moved) and the conform store answering (a conform was just built, or
  /// dropped by [AudioConformStore.releaseDiskBacked]). Keying on the save
  /// generation alone — what the media map does — would leave a freshly
  /// conformed sound showing nothing until the next save.
  Map<String, int> get conformStoredBytes {
    final known = _conformStoredBytes;
    if (known != null) {
      return known;
    }
    final sizes = <String, int>{};
    for (final asset in _repository.requireProject().mediaAssets) {
      final bytes = conformStoredBytesFor(asset.path);
      if (bytes != null && bytes > 0) {
        sizes[asset.path] = bytes;
      }
    }
    return _conformStoredBytes = Map<String, int>.unmodifiable(sizes);
  }

  Map<String, int>? _conformStoredBytes;

  void _invalidateConformStoredBytes() => _conformStoredBytes = null;

  /// Cels the last save could not write because the file their only copy
  /// lived in had been deleted.
  ///
  /// 🚨★★★**EMPTY IS THE ONLY ANSWER ANYBODY EXPECTED** until 유저 hit it
  /// on an iPad (2026-08-30): open a project, delete the file in the Files
  /// app, draw a stroke, press Save. A save turns every cel into a file ref
  /// and drops its cold blob as「redundant with the file」, so once that
  /// file is gone the untouched cels have their bytes nowhere — and the
  /// save used to come apart with a raw `PathNotFoundException` carrying a
  /// path.
  ///
  /// It now writes everything it can still reach and says what it could
  /// not. ⛔The UI has to SHOW this: a save that quietly wrote fewer cels
  /// than it holds is the shape this repo refuses for media, and a cel is
  /// the picture itself.
  Set<BrushFrameKey> celsLostToAMissingFile = const {};

  /// Every carried asset's actual size, for a list that shows sizes.
  Map<String, int> get mediaStoredBytes {
    final sizes = <String, int>{};
    for (final asset in mediaAssets) {
      final bytes = mediaStoredBytesFor(asset.path);
      if (bytes != null) {
        sizes[asset.path] = bytes;
      }
    }
    return sizes;
  }

  /// What the project carries, for tests and for anything that needs to
  /// resolve an asset's bytes without going through a save.
  Map<String, String> get mediaEntryNames =>
      Map<String, String>.unmodifiable(_mediaEntryNames);

  /// Where [poolPath]'s bytes actually are RIGHT NOW — the read side of
  /// carrying. The save always knew how to stream an embedded asset
  /// forward; playback, the waveform and the existence probe kept asking
  /// the filesystem, so deleting the import original (the very act
  /// carrying exists to survive) silenced the clip and hung a "missing"
  /// banner on an asset the project owns.
  ///
  /// Resolved fresh per call, never held: offsets belong to one layout
  /// and a compaction moves every byte. The archive range carries the
  /// entry's CRC, and the conform pipeline treats a mismatch as transient
  /// — a read that raced a compaction retries against fresh offsets
  /// rather than decoding whatever moved into the window.
  MediaByteSource mediaByteSourceFor(String poolPath) {
    final entryName = _mediaEntryNames[poolPath];
    final archivePath = _projectFilePath;
    if (entryName != null && archivePath != null) {
      try {
        final entry = parseAnicelZipLayoutFile(
          archivePath,
        ).entryNamed(entryName);
        if (entry != null) {
          final range = MediaArchiveBytes(
            archivePath: archivePath,
            dataOffset: entry.dataOffset,
            length: entry.length,
            entryCrc32: entry.crc32,
            framed: mediaEntryIsFramed(entryName),
          );
          // 🚨A framed entry is decoded HERE and nowhere downstream. Every
          // consumer asked for「the bytes of this asset」and must keep
          // getting them — the block index is this layer's business, and
          // the reader still serves a window rather than the whole file.
          return mediaSourceDecodingFrames(range);
        }
      } on Object {
        // A torn or momentarily unreadable archive: the file fallback
        // below still answers for assets whose original survives, and the
        // conform store's transient handling covers the rest.
      }
    }
    // ⚠️Not in the archive yet — but 품기 may have staged it, and after an
    // import that is the only place its bytes are.
    final staged = mediaStagingStore.find(poolPath);
    if (staged != null) {
      // Through [mediaAppFileSource] rather than assembling the pair here:
      // framed-or-not is written into the name, and one place reads it.
      return mediaAppFileSource(staged.path);
    }
    return MediaFileBytes(poolPath);
  }

  /// The open project's file path; null until first saved/opened (Save
  /// falls back to Save As).
  String? get projectFilePath => _projectFilePath;

  bool _hasUnsavedChanges = false;

  /// Whether edits exist since the last save/open (autosave + title dots).
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  void _markProjectDirty() {
    _hasUnsavedChanges = true;
  }

  /// The recovery overlay for the CURRENT state — always in the app
  /// container ([AppSave.recoveryPathFor]), never beside the file: a
  /// sibling would need the grant the crash just took down with it.
  /// Null while the project has never been saved (the service prompts
  /// for a real file instead of writing into hidden app-data dirs).
  String? get autosaveSidecarPath {
    final path = _projectFilePath;
    return path == null ? null : AppSave.recoveryPathFor(path);
  }

  /// Writes the current state to [path] WITHOUT touching the dirty flag or
  /// the project path — the recovery service's snapshot writer.
  ///
  /// An OVERLAY on the saved project: only the cels edited since the last
  /// manual save. This runs mid-session on the periodic tick (F-1 made the
  /// clock the only trigger), so it has to cost what the user drew rather
  /// than what the project weighs. Everything left out is already in the
  /// project file, unchanged, which is also what the base stamp inside the
  /// overlay is there to guarantee.
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
    await _textCelBakes.flushTextCelBakes();
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
      // its way out. Generation-armed, not just the in-flight flag — the
      // flag is already down again by the time a spanning snapshot asks.
      isStale: beginAutosaveStaleCheck(),
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
    // The breadcrumb a silent kill cannot erase. A save is the work this
    // app is most likely to die inside — and when iOS kills for memory
    // there is no exception, no crash report, and nothing in App Store
    // Connect (실기 08-27: three kills, an iPad that survived the same
    // press, and not one line of evidence anywhere). An entry with no END
    // at the next launch is the only thing that says otherwise.
    MemoryBlackBox.begin('save');
    try {
      await _writeProjectToFile(filePath, onProgress: onProgress);
    } finally {
      _saveInFlight = false;
      MemoryBlackBox.end('save');
    }
  }

  /// True while a manual save is running, so the autosave tick stands down
  /// instead of racing it. Read through [autosaveShouldStandDown].
  bool _saveInFlight = false;

  /// Bumped each time a manual save COMPLETES. [_saveInFlight] is a
  /// point-in-time flag: a snapshot that started BEFORE a save and came
  /// out of its isolate AFTER it sees the flag down again — and would
  /// rename an overlay stamped against the pre-save base onto the path
  /// the save just retired. That is a recovery file for a cleanly saved
  /// project, and its Accept can only fail the stamp check. A snapshot
  /// therefore captures this at its start and refuses to land if it
  /// moved — see [beginAutosaveStaleCheck].
  int _completedSaveGeneration = 0;

  /// The staleness question a recovery snapshot carries into its isolate:
  /// armed when the snapshot starts, it answers true the moment any
  /// manual save has completed since (or the session stood down).
  bool Function() beginAutosaveStaleCheck() {
    final generationAtStart = _completedSaveGeneration;
    return () =>
        autosaveShouldStandDown ||
        _completedSaveGeneration != generationAtStart;
  }

  /// Whether a snapshot should do nothing right now: a save is mid-flight
  /// (anything written would land beside a retirement that has already
  /// run), the session was recovered (its refs point INTO the snapshot,
  /// see [writeAutosaveSnapshot]), or the user threw the work away.
  bool get autosaveShouldStandDown =>
      _saveInFlight || _discardedUnsavedWork || _recoveredFromSidecar != null;

  /// Writes the CURRENT state to [path] as a complete, standalone archive
  /// and changes NOTHING about this session — no path adoption, no ref
  /// adoption, no dirty-flag or sidecar movement. The Save As STAGING
  /// writer on scoped platforms: the file this produces is about to be
  /// MOVED by a document picker, so anything the session learned from it
  /// would name a path that stops existing moments later.
  ///
  /// 🚨 Exists because of the 22-byte placeholder this replaces (실측
  /// iPhone+Drive, 08-26): a provider that refuses in-place writes made
  /// the post-placement save fail, and what the picker had placed was the
  /// EMPTY placeholder — an unopenable husk where the user meant to put
  /// their project. A complete archive staged up front costs the same
  /// move and can never strand a husk.
  /// Returns the media entry names the archive was written with, which is
  /// what [adoptPlacedArchive] needs if this copy becomes the project.
  Future<Map<String, String>> writeArchiveCopy(
    String path, {
    void Function(double)? onProgress,
  }) async {
    await _textCelBakes.flushTextCelBakes();
    final mediaToStore = projectMediaSources(
      project: _repository.requireProject(),
      projectFilePath: _projectFilePath,
      mediaEntryNames: _mediaEntryNames,
      staging: mediaStagingStore,
    );
    final conforms = _conformsToStore();
    await _anicelFileService.save(
      project: _repository.requireProject(),
      brushFrameStore: brushFrameStore,
      auxCelStores: [conteInkRowStore, conteInkPageStore, envelopeInkStore],
      filePath: path,
      mediaToStore: mediaToStore,
      conforms: conforms,
      grants: _grantsToStore(),
      mediaCrcs: _mediaCrcsToStore(),
      onProgress: onProgress,
      adoptRefs: false,
    );
    return mediaEntryNamesFor(mediaToStore);
  }

  /// The archive at [placedPath] IS this project now — no second write.
  ///
  /// iOS has no save panel: the export picker MOVES a file the app wrote
  /// and reports where it landed, so by the time Save As knows the
  /// destination, [writeArchiveCopy]'s bytes are already sitting there and
  /// the picker's modality means nothing could have edited them since.
  ///
  /// 🚨Saving AGAIN over that path was the old shape and it is not merely
  /// wasteful. A destination the picker moved a file INTO is not one the
  /// app may keep writing to: Save As died with 「the location refused
  /// both a direct write and a coordinated replace」 on a path it had just
  /// successfully filled (실기 08-27, iPhone). Adoption cannot be refused,
  /// because there is nothing left to write.
  ///
  /// ⚠️Cel refs are NOT repointed into the placed file. [writeArchiveCopy]
  /// writes with `adoptRefs: false` precisely because a file about to be
  /// MOVED cannot back a ref, and the destination may be somewhere the app
  /// cannot read back on demand either. The pixels stay where they were —
  /// in RAM — which is what a never-saved session was already doing.
  void adoptPlacedArchive(
    String placedPath, {
    required Map<String, String> mediaEntryNames,
  }) {
    final previousPath = _projectFilePath;
    _mediaEntryNames = mediaEntryNames;
    _projectFilePath = placedPath;
    _hasUnsavedChanges = false;
    _completedSaveGeneration += 1;
    _invalidateConformStoredBytes();
    _recoveredFromSidecar = null;
    _discardedUnsavedWork = false;
    if (previousPath != null) {
      ProjectAutosaveService.retireSidecarsFor(previousPath);
    }
    ProjectAutosaveService.retireSidecarsFor(placedPath);
    notifyListeners();
  }

  /// The provider-refusal fallback: a complete archive written into the
  /// app's own Recovery folder (so an orphan is swept in ≤30 days), then
  /// swapped over [filePath] by the platform's file coordinator.
  ///
  /// The staging save ADOPTS normally — its refs are valid while the
  /// staging file exists, and it exists until the sweep. After a
  /// successful replace the copy at [filePath] is byte-identical, so the
  /// same offsets hold there and clean keys' refs are simply repointed.
  /// ⚠️ Keys dirty AGAIN (drawn on while the save ran) keep their staging
  /// refs and their dirt: repointing them through [adoptSavedFile] would
  /// CLEAR that dirt, and the next save would quietly skip the stroke —
  /// the exact loss shape the editTick round closed.
  ///
  /// A replace that also fails rethrows the file-system refusal: the
  /// notice names the real problem, and Q-drive-resave owns what the app
  /// should offer instead.
  Future<void> _saveViaCoordinatedReplace(
    String filePath, {
    required Map<String, MediaByteSource> mediaToStore,
    required ProjectConforms conforms,
    void Function(double)? onProgress,
  }) async {
    final stagingDirectory = Directory(AppSave.recoveryDirectory())
      ..createSync(recursive: true);
    final staging =
        '${stagingDirectory.path.replaceAll('\\', '/')}'
        '/replace.tmp-${DateTime.now().microsecondsSinceEpoch}';
    await _anicelFileService.save(
      project: _repository.requireProject(),
      brushFrameStore: brushFrameStore,
      auxCelStores: [conteInkRowStore, conteInkPageStore, envelopeInkStore],
      filePath: staging,
      mediaToStore: mediaToStore,
      conforms: conforms,
      grants: _grantsToStore(),
      mediaCrcs: _mediaCrcsToStore(),
      onProgress: onProgress,
    );
    final replaced = await FolderPicker.replaceFileCoordinated(
      sourcePath: staging,
      destinationPath: filePath,
    );
    if (!replaced) {
      throw FileSystemException(
        'the location refused both a direct write and a coordinated '
        'replace — this provider cannot be saved to in place',
        filePath,
      );
    }
    for (final store in [
      brushFrameStore,
      conteInkRowStore,
      conteInkPageStore,
      envelopeInkStore,
    ]) {
      final snapshot = store.bakedSnapshotForSave();
      final dirtyAgain = store.dirtyCelKeysSinceSave;
      final moved = <BrushFrameKey, AnicelCelFileRef>{
        for (final entry in snapshot.fileRefs.entries)
          if (!dirtyAgain.contains(entry.key) &&
              entry.value.filePath.replaceAll('\\', '/') == staging)
            entry.key: AnicelCelFileRef(
              filePath: filePath,
              dataOffset: entry.value.dataOffset,
              length: entry.value.length,
              canvasSize: entry.value.canvasSize,
              tileSize: entry.value.tileSize,
            ),
      };
      if (moved.isNotEmpty) {
        store.adoptSavedFile(moved, dirtyTicksAtSnapshot: snapshot.dirtyTicks);
      }
    }
  }

  Future<void> _writeProjectToFile(
    String filePath, {
    void Function(double)? onProgress,
  }) async {
    await _textCelBakes.flushTextCelBakes();
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
      staging: mediaStagingStore,
    );
    final conforms = _conformsToStore();
    try {
      celsLostToAMissingFile = await _anicelFileService.save(
        project: _repository.requireProject(),
        brushFrameStore: brushFrameStore,
        auxCelStores: [conteInkRowStore, conteInkPageStore, envelopeInkStore],
        filePath: filePath,
        mediaToStore: mediaToStore,
        conforms: conforms,
        grants: _grantsToStore(),
        mediaCrcs: _mediaCrcsToStore(),
        onProgress: onProgress,
        // 🚨A Save As is「writing somewhere else」and nothing more subtle:
        // the target is not the file this session has been saving to. 유저
        // 2026-08-31 asked for it to be a full write every time — 「기존
        // 파일에 저장 덮어씌우기를 하더라도 고치기위해 풀저장」 — and the
        // case that was NOT already whole is exactly this one, an overwrite
        // onto an older copy of the same project.
        rewriteWhole:
            previousPath != null &&
            previousPath.replaceAll(r'\', '/') !=
                filePath.replaceAll(r'\', '/'),
      );
    } on FileSystemException {
      // 실측 (08-26, iPhone + Google Drive): a File Provider can refuse
      // plain in-place writes outright. The sanctioned way through is a
      // COORDINATED replace — write the whole archive app-locally, then
      // hand it to NSFileCoordinator to swap over the provider file.
      // Scoped platforms only: a desktop refusal (locked file, dead
      // drive) has no coordinator to appeal to and must stay loud.
      if (!FolderPicker.grantsAreScoped) {
        rethrow;
      }
      await _saveViaCoordinatedReplace(
        filePath,
        mediaToStore: mediaToStore,
        conforms: conforms,
        onProgress: onProgress,
      );
    }
    _mediaEntryNames = mediaEntryNamesFor(mediaToStore);
    // 🚨The save ABSORBED the staged bytes, so the staged copy stops being
    // anything — 유저 08-27: 「사본 남으면 진짜 용서안할게」. Retired HERE
    // rather than on close or on import-undo, because this is the one
    // moment the bytes provably live somewhere else.
    for (final path in mediaToStore.keys) {
      mediaStagingStore.retire(path);
    }
    _projectFilePath = filePath;
    _hasUnsavedChanges = false;
    _completedSaveGeneration += 1;
    _invalidateConformStoredBytes();
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
  /// flag, no notify. Flipping through the media pool must not make the
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
  Map<String, Object?> _mediaCrcsToStore() => _mediaFingerprints.narrowedTo({
    for (final asset in mediaAssets) _normalizedPath(asset.path),
  }).toJson();

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
    // The mirror of "a whole archive is refused as an overlay" (pinned in
    // recovery_overlay_test): an OVERLAY fed through the legacy
    // whole-archive arm is refused too. Its project.json is the full
    // project, so it would OPEN and look right while every base cel reads
    // as empty — and the next full rewrite makes that loss permanent.
    // Loud beats silently lossy; the shell's routing is the one caller and
    // routes overlays to [overlayPath].
    if (recoverAs != null && anicelSnapshotIsOverlay(filePath)) {
      throw const FormatException(
        'this snapshot is a recovery overlay — it holds only what changed '
        'since its base was saved, and has to be opened OVER that base, '
        'never as the project itself',
      );
    }
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
    // R7q2 (유저 08-18: 「치유가 가볍게 가능하다면 해도 됨」): heal cels
    // whose stored canvas size disagrees with their cut — files written
    // while the resize was still split in two could leave 겸용 or
    // unselected cuts' cels at a stale size, which display as EMPTY and
    // turn permanent on the first stroke (the D5 loss, preserved in the
    // save). A healthy file walks this map once and finds nothing; a
    // broken cel gets the same strictly cut-scoped crop the resize
    // itself uses (R27), and the heal marks the project unsaved so the
    // next save writes the repaired truth.
    final cutSizes = {
      for (final track in result.project.tracks)
        for (final cut in track.cuts) cut.id: cut.canvasSize,
    };
    final healedCuts = <CutId>{};
    for (final entry in mainCels.entries) {
      final cutSize = cutSizes[entry.key.cutId];
      if (cutSize != null && entry.value.canvasSize != cutSize) {
        healedCuts.add(entry.key.cutId);
      }
    }
    for (final cutId in healedCuts) {
      brushFrameStore.resizeBakedSurfaces(cutSizes[cutId]!, cutId: cutId);
    }
    conteInkRowStore.restoreFromFile(inkRowCels);
    conteInkPageStore.restoreFromFile(inkPageCels);
    envelopeInkStore.restoreFromFile(envelopeCels);
    _historyManager.clear();
    _clipboard._copiedFrame = null;
    _clipboard._layerClipboard = null;
    // The selections name rows of the project being discarded, so no grid
    // can draw them — and a band nothing shows still CLAIMS the cell verbs
    // ([cellSelectionClaimsSubject]), which would leave Delete and the
    // comma buttons dark with nothing on screen to explain why. Every
    // other whole-state reset clears here; this one was the omission.
    clearAllSelections();
    trackFrameRangeSelection.value = null;
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
    _recoveredFromSidecar =
        overlayPath ?? (recoverAs == null ? null : filePath);
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
    // file until the user saves — and so does a session whose load just
    // HEALED mismatched cels (R7q2).
    _hasUnsavedChanges =
        recoverAs != null || overlayPath != null || healedCuts.isNotEmpty;
    _warmActiveCut();
    frameSeekCommitted.value += 1;
    notifyListeners();
  }

  // --- Frame flipping (P1 shortcuts) ----------------------------------------

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
  void selectPreviousDrawing() => _frameVerbs.flipRow(forward: false);

  /// Steps one BLOCK forward along [currentRow] (Ctrl+`.`). See
  /// [selectPreviousDrawing] for the rule.
  void selectNextDrawing() => _frameVerbs.flipRow(forward: true);

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
      for (final entry in _projectSettings.projectLayout())
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
    // the last cut is a place you may stand. F-21: and a step that falls
    // through that floor lands ON it rather than doing nothing — the layer
    // row's law, on the axis this row counts.
    final landing = next < 0 ? 0 : next;
    if (landing != globalFrame) {
      // Land on the axis the step was measured on: this row may name a
      // track that is not the selected one.
      selectGlobalFrame(landing, onAxis: axis);
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
  /// gap only while the gesture is live (the `_gapGlobalFrame` read below),
  /// so the flag stays and the canvas rebuilds at enter and leave.
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
    // 🚨THE QUESTION IS 「CAN THIS ROW HOLD A PICTURE」, not 「is it in the
    // drawing SECTION」 (유저 2026-08-27, R27 #16: 「추가로 **없으면 블록을
    // 회색으로**. 로직은 통일」). The direction row is a camera-section row
    // that holds cels, so the section test answered `true` — no tint — and
    // an empty block there was indistinguishable from a full one.
    //
    // ⛔The two only looked like one question while every cel-holding row
    // happened to sit in the drawing section, which is the same trap R27
    // #16 found in `layerKindCarriesInstructions`.
    if (!layerKindIsDrawingCel(layer.kind)) {
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
      // 🚨A SPAN-COVERED CELL ON A DIRECTION ROW IS A BLOCK — it simply has
      // no cel behind it yet, which is the state 유저 asked to see: 「추가로
      // **없으면 블록을 회색으로**」. Everywhere else a cell with no frame
      // is not a block at all, so there is nothing to tint and `true` is
      // the right answer.
      //
      // ⛔It asks the span ADAPTER rather than reading `layer.instructions`
      // again — 「is this frame under a span」 has one home, and the band
      // that draws the block reads the same one ([[no-copy-to-share]]).
      if (!layerKindCarriesInstructions(layer.kind)) {
        return true;
      }
      return instructionCellExposureState(layer, frameIndex) ==
          TimelineCellExposureState.uncovered;
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

  // --- Status text --------------------------------------------------------

  String get currentLayerStatusText {
    final layer = activeLayer;
    return 'Layer: ${layer?.name ?? 'None'}';
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
      frameLabel: _frameVerbs.currentFrameDisplayLabel(layer, frame),
    );
  }

}

/// 🚨결정 14 ②ⓐ (유저 확정 2026-08-22) — ONE ROW OF THE CLIPBOARD.
///
/// The board held a single row until copy learned the band. It holds a LIST
/// now, and this is one entry: which row it came from, the run of cells, and
/// the cels those cells point at.
class _CopiedRow {
  const _CopiedRow({
    required this.layerId,
    required this.clip,
    this.cels = const [],
  });

  final LayerId layerId;
  final TimelineClipRow clip;

  /// Carried BY VALUE, for [_CopiedFrameReference.cels]'s reason: a
  /// 잘라내기 orphans what it lifted, and a clipboard that does not hold
  /// what was put on it is not one.
  final List<Frame> cels;
}

class _CopiedFrameReference {
  const _CopiedFrameReference({
    required this.layerId,
    required this.frameId,
    required this.frameName,
    this.clip,
    this.cels = const [],
    this.rows = const [],
  });

  /// 🚨결정 14 ②ⓐ — EVERY swept row, in display order, the anchor first.
  ///
  /// > 「지우기 눌렀다고해서 현재 행만 지우는게아니라 **선택된 모든게**
  /// > 지워지는걸 말하는거임. **복사든 뭐든 마찬가지**」
  ///
  /// ⚠️The scalar fields below still describe the ANCHOR — the status line
  /// and the paste gates read those. This is the whole board. A copy with no
  /// band writes ONE entry, so the single-row clipboard is this list of
  /// length one rather than a second shape standing beside it.
  final List<_CopiedRow> rows;

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

/// D28: the cut's STORYBOARD PANEL under the cursor — with a storyboard
/// layer on the cut, the frame verbs target the panel, not the cut
/// (「스토리보드레이어 존재 시 대상이 스토리보드레이어로」, the later law
/// superseding 「컷블록 위 4 = 컷길이 4」 exactly where a panel exists).
class _StoryboardCursorStoryboardPanel extends _StoryboardCursorBlock {
  const _StoryboardCursorStoryboardPanel(
    this.cut,
    this.row,
    this.panelStartIndex,
    this.panelLength,
  );

  final Cut cut;
  final Layer row;

  /// CUT-LOCAL — the storyboard row lives inside its cut.
  final int panelStartIndex;
  final int panelLength;
}
